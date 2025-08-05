defmodule RubberDuck.Actions.LLM.Embed do
  @moduledoc """
  Action for generating embeddings using an LLM provider.
  
  Converts text into vector representations for semantic search
  and similarity comparisons.
  """

  use Jido.Action,
    name: "llm_embed",
    description: "Generate embeddings for text using specified LLM provider",
    schema: [
      provider: [type: :map, required: true],
      texts: [type: {:list, :string}, required: true],
      model: [type: :string, default: nil],
      timeout: [type: :pos_integer, default: 30_000],
      batch_size: [type: :pos_integer, default: 100]
    ]

  alias RubberDuck.LLM.HealthMonitor
  require Logger

  @impl true
  def run(params, _context) do
    provider = params.provider
    texts = params.texts
    _timeout = params.timeout
    batch_size = params.batch_size
    
    # Check if provider supports embeddings
    unless supports_embeddings?(provider) do
      {:error, %{
        reason: :embeddings_not_supported,
        provider: provider.name,
        message: "Provider #{provider.name} does not support embeddings"
      }}
    else
      start_time = System.monotonic_time(:millisecond)
      
      try do
        # Process in batches if needed
        results = if length(texts) > batch_size do
          process_in_batches(texts, batch_size, provider, params)
        else
          process_single_batch(texts, provider, params)
        end
        
        case results do
          {:ok, embeddings} ->
            duration = System.monotonic_time(:millisecond) - start_time
            HealthMonitor.record_success(provider.name, duration)
            
            {:ok, %{
              embeddings: embeddings,
              provider: provider.name,
              model: determine_model(provider, params.model),
              count: length(embeddings),
              duration_ms: duration,
              dimensions: get_embedding_dimensions(embeddings)
            }}
          
          {:error, reason} ->
            duration = System.monotonic_time(:millisecond) - start_time
            HealthMonitor.record_failure(provider.name, reason)
            
            Logger.warning("Embedding generation failed for provider #{provider.name}: #{inspect(reason)}")
            
            {:error, %{
              reason: reason,
              provider: provider.name,
              duration_ms: duration
            }}
        end
      rescue
        exception ->
          duration = System.monotonic_time(:millisecond) - start_time
          HealthMonitor.record_failure(provider.name, exception)
          
          Logger.error("Embedding generation crashed for provider #{provider.name}: #{inspect(exception)}")
          
          {:error, %{
            reason: {:exception, exception},
            provider: provider.name,
            duration_ms: duration
          }}
      end
    end
  end

  def describe do
    %{
      name: "LLM Embed",
      description: "Generates vector embeddings for text using an LLM provider",
      category: "llm",
      inputs: %{
        provider: "The provider configuration map with module and config",
        texts: "List of texts to generate embeddings for",
        model: "Specific embedding model to use (optional)",
        timeout: "Maximum time to wait for embeddings in milliseconds",
        batch_size: "Maximum number of texts to process in a single request"
      },
      outputs: %{
        success: %{
          embeddings: "List of embedding vectors",
          provider: "Name of the provider used",
          model: "The embedding model used",
          count: "Number of embeddings generated",
          duration_ms: "Time taken for generation",
          dimensions: "Dimension count of the embeddings"
        },
        error: %{
          reason: "The error reason",
          provider: "Name of the provider that failed",
          duration_ms: "Time taken before failure"
        }
      }
    }
  end

  # Private functions

  defp supports_embeddings?(provider) do
    try do
      capabilities = provider.module.capabilities()
      Map.get(capabilities, :embeddings, false)
    rescue
      _ -> false
    end
  end

  defp process_single_batch(texts, provider, params) do
    request = build_embedding_request(texts, params)
    config = Map.put(provider.config, :timeout, params.timeout)
    
    case apply(provider.module, :embed, [request, config]) do
      {:ok, response} ->
        embeddings = extract_embeddings(response)
        {:ok, embeddings}
      
      {:error, _reason} = error ->
        error
    end
  end

  defp process_in_batches(texts, batch_size, provider, params) do
    # Process texts in parallel batches
    batches = Enum.chunk_every(texts, batch_size)
    
    tasks = Enum.map(batches, fn batch ->
      Task.async(fn ->
        process_single_batch(batch, provider, params)
      end)
    end)
    
    # Wait for all tasks with timeout
    results = Task.await_many(tasks, params.timeout)
    
    # Check if all succeeded
    errors = Enum.filter(results, fn
      {:ok, _} -> false
      {:error, _} -> true
    end)
    
    if Enum.empty?(errors) do
      # Combine all embeddings
      all_embeddings = 
        results
        |> Enum.flat_map(fn {:ok, embeddings} -> embeddings end)
      
      {:ok, all_embeddings}
    else
      # Return first error
      hd(errors)
    end
  end

  defp build_embedding_request(texts, params) do
    base_request = %{
      input: texts,
      encoding_format: "float"
    }
    
    if params.model do
      Map.put(base_request, :model, params.model)
    else
      base_request
    end
  end

  defp extract_embeddings(response) do
    # Handle different response formats
    cond do
      # OpenAI format
      Map.has_key?(response, :data) ->
        response.data
        |> Enum.sort_by(& &1.index)
        |> Enum.map(& &1.embedding)
      
      # Direct embeddings array
      Map.has_key?(response, :embeddings) ->
        response.embeddings
      
      # Single embedding
      Map.has_key?(response, :embedding) ->
        [response.embedding]
      
      true ->
        []
    end
  end

  defp determine_model(provider, requested_model) do
    if requested_model do
      requested_model
    else
      # Get default embedding model for provider
      case provider.name do
        :openai -> "text-embedding-3-small"
        :anthropic -> "claude-3-embed"
        _ -> "default"
      end
    end
  end

  defp get_embedding_dimensions([first | _]) when is_list(first) do
    length(first)
  end
  defp get_embedding_dimensions(_), do: 0
end