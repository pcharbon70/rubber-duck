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
    if supports_embeddings?(params.provider) do
      execute_embedding_generation(params)
    else
      handle_unsupported_provider(params.provider)
    end
  end

  defp execute_embedding_generation(params) do
    start_time = System.monotonic_time(:millisecond)

    results = process_embedding_request(params)
    handle_embedding_results(results, params.provider, start_time)
  rescue
    exception ->
      handle_embedding_exception(exception, params.provider, System.monotonic_time(:millisecond))
  end

  defp process_embedding_request(params) do
    if length(params.texts) > params.batch_size do
      process_in_batches(params.texts, params.batch_size, params.provider, params)
    else
      process_single_batch(params.texts, params.provider, params)
    end
  end

  defp handle_embedding_results(results, provider, start_time) do
    case results do
      {:ok, embeddings} ->
        handle_successful_embeddings(embeddings, provider, start_time)
      {:error, reason} ->
        handle_embedding_failure(reason, provider, start_time)
    end
  end

  defp handle_successful_embeddings(embeddings, provider, start_time) do
    duration = System.monotonic_time(:millisecond) - start_time
    HealthMonitor.record_success(provider.name, duration)

    {:ok, build_success_response(embeddings, provider, duration)}
  end

  defp build_success_response(embeddings, provider, duration) do
    %{
      embeddings: embeddings,
      provider: provider.name,
      model: determine_model(provider, provider.model),
      count: length(embeddings),
      duration_ms: duration,
      dimensions: get_embedding_dimensions(embeddings)
    }
  end

  defp handle_embedding_failure(reason, provider, start_time) do
    duration = System.monotonic_time(:millisecond) - start_time
    HealthMonitor.record_failure(provider.name, reason)
    Logger.warning("Embedding generation failed for provider #{provider.name}: #{inspect(reason)}")

    {:error, build_error_response(reason, provider, duration)}
  end

  defp handle_embedding_exception(exception, provider, start_time) do
    duration = System.monotonic_time(:millisecond) - start_time
    HealthMonitor.record_failure(provider.name, exception)
    Logger.error("Embedding generation crashed for provider #{provider.name}: #{inspect(exception)}")

    {:error, build_error_response({:exception, exception}, provider, duration)}
  end

  defp build_error_response(reason, provider, duration) do
    %{
      reason: reason,
      provider: provider.name,
      duration_ms: duration
    }
  end

  defp handle_unsupported_provider(provider) do
    {:error, %{
      reason: :embeddings_not_supported,
      provider: provider.name,
      message: "Provider #{provider.name} does not support embeddings"
    }}
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
    capabilities = provider.module.capabilities()
    Map.get(capabilities, :embeddings, false)
  rescue
    _ -> false
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
