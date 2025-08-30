defmodule RubberDuck.Skills.Rag.Actions.GenerateEmbeddingAction do
  @moduledoc """
  Embedding generation action with provider abstraction and optimization.

  This action provides unified embedding generation across multiple providers
  including OpenAI, Anthropic, Cohere, local models, and specialized embedding
  services with intelligent provider selection and batch optimization.

  Features:
  - Multi-provider embedding generation (OpenAI, Anthropic, Cohere, local)
  - Intelligent provider selection based on content characteristics
  - Batch processing optimization for large document sets
  - Embedding quality assessment and validation
  - Cost optimization with caching and provider routing
  - Integration with the Universal Provider System from Phase 2.2

  The action supports both single and batch embedding generation with
  automatic optimization for cost, quality, and performance.
  """

  use Jido.Action,
    name: "generate_embedding",
    schema: [
      input: [
        type: {:or, [:string, {:list, :string}]},
        required: true,
        doc: "Text or list of texts to embed"
      ],
      provider: [
        type: :atom,
        default: :auto,
        doc: "Embedding provider (:openai, :anthropic, :cohere, :local, :auto)"
      ],
      model: [type: :string, doc: "Specific model to use for embedding"],
      embedding_config: [
        type: :map,
        default: %{},
        doc: "Provider-specific embedding configuration"
      ],
      optimization_config: [type: :map, default: %{}, doc: "Optimization settings"],
      context: [type: :map, default: %{}, doc: "Request context for optimization"]
    ]

  require Logger

  alias RubberDuck.LlmProviders.{ProviderRegistry, UniversalProviderService}
  alias RubberDuck.Skills.Actions.{CallAPIAction, OptimizeRequestAction}

  # Provider capabilities for embedding generation
  @embedding_providers %{
    openai: %{
      models: ["text-embedding-3-small", "text-embedding-3-large", "text-embedding-ada-002"],
      max_tokens_per_request: 8191,
      dimensions: [1536, 3072],
      # text-embedding-3-small
      cost_per_1k_tokens: 0.00002,
      batch_size_limit: 2048,
      quality_score: 0.9
    },
    anthropic: %{
      # Hypothetical - Anthropic doesn't have dedicated embedding models
      models: ["claude-3-embedding"],
      max_tokens_per_request: 8000,
      dimensions: [1024],
      cost_per_1k_tokens: 0.00001,
      batch_size_limit: 1000,
      quality_score: 0.85
    },
    cohere: %{
      models: ["embed-english-v3.0", "embed-multilingual-v3.0"],
      max_tokens_per_request: 512,
      dimensions: [1024, 384],
      cost_per_1k_tokens: 0.0001,
      batch_size_limit: 96,
      quality_score: 0.88
    },
    local: %{
      models: [
        "sentence-transformers/all-MiniLM-L6-v2",
        "sentence-transformers/all-mpnet-base-v2"
      ],
      max_tokens_per_request: 512,
      dimensions: [384, 768],
      # No direct cost
      cost_per_1k_tokens: 0.0,
      # Hardware dependent
      batch_size_limit: 100,
      quality_score: 0.75
    }
  }

  @default_optimization_config %{
    auto_provider_selection: true,
    enable_batching: true,
    enable_caching: true,
    quality_threshold: 0.8,
    cost_optimization: true,
    max_retries: 3
  }

  @doc """
  Generate embeddings for input text(s) with provider optimization.

  Returns embedding vectors with generation metadata, quality assessment,
  and optimization information for learning and monitoring.
  """
  def run(params, _context) do
    %{
      input: input,
      provider: provider,
      model: model,
      embedding_config: config,
      optimization_config: opt_config,
      context: request_context
    } = params

    merged_opt_config = Map.merge(@default_optimization_config, opt_config)

    Logger.debug("GenerateEmbeddingAction: Starting embedding generation",
      provider: provider,
      input_type: determine_input_type(input),
      optimization_enabled: merged_opt_config.auto_provider_selection
    )

    generation_start_time = System.monotonic_time(:microsecond)

    with {:ok, selected_provider, final_config} <-
           select_optimal_provider(provider, model, input, merged_opt_config, request_context),
         {:ok, processed_input} <- preprocess_input(input, selected_provider, merged_opt_config),
         {:ok, embedding_result} <-
           execute_embedding_generation(
             selected_provider,
             processed_input,
             final_config,
             request_context
           ) do
      generation_time = System.monotonic_time(:microsecond) - generation_start_time

      # Assess embedding quality
      quality_assessment = assess_embedding_quality(embedding_result, input, selected_provider)

      # Calculate cost metrics
      cost_metrics =
        calculate_embedding_cost(embedding_result, selected_provider, processed_input)

      Logger.info("GenerateEmbeddingAction: Embedding generation complete",
        provider: selected_provider,
        input_count: get_input_count(processed_input),
        generation_time_us: generation_time,
        quality_score: quality_assessment.quality_score
      )

      {:ok,
       %{
         embeddings: embedding_result.embeddings,
         provider_used: selected_provider,
         model_used: embedding_result.model,
         input_processed: processed_input,
         quality_assessment: quality_assessment,
         cost_metrics: cost_metrics,
         generation_metadata: %{
           generation_time_microseconds: generation_time,
           provider_selection_reason: embedding_result.selection_reason,
           optimization_applied: embedding_result.optimizations_applied,
           batch_processing_used: is_list(processed_input),
           dimensions: get_embedding_dimensions(embedding_result.embeddings)
         }
       }}
    else
      {:error, reason} ->
        Logger.error("GenerateEmbeddingAction: Embedding generation failed",
          error: reason,
          provider: provider,
          input_type: determine_input_type(input)
        )

        {:error, reason}
    end
  end

  # Private implementation functions

  defp select_optimal_provider(:auto, model, input, opt_config, context) do
    if opt_config.auto_provider_selection do
      # Analyze input to determine optimal provider
      input_characteristics = analyze_input_characteristics(input, context)
      optimal_provider = determine_optimal_embedding_provider(input_characteristics, opt_config)

      Logger.debug("GenerateEmbeddingAction: Auto-selected provider #{optimal_provider}")

      provider_config = get_provider_config(optimal_provider, model)
      {:ok, optimal_provider, provider_config}
    else
      # Default to OpenAI if no auto-selection
      provider_config = get_provider_config(:openai, model)
      {:ok, :openai, provider_config}
    end
  end

  defp select_optimal_provider(provider, model, _input, _opt_config, _context) do
    # Use specified provider
    case get_provider_config(provider, model) do
      {:ok, config} -> {:ok, provider, config}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_provider_config(provider, model) do
    case Map.get(@embedding_providers, provider) do
      nil ->
        {:error, {:unsupported_provider, provider}}

      provider_caps ->
        final_model = model || select_default_model(provider, provider_caps)

        if final_model in provider_caps.models do
          config = Map.put(provider_caps, :selected_model, final_model)
          {:ok, config}
        else
          {:error, {:unsupported_model, provider, final_model}}
        end
    end
  end

  defp select_default_model(provider, provider_caps) do
    # Select the best default model for provider
    case provider do
      # Good balance of cost and quality
      :openai -> "text-embedding-3-small"
      :anthropic -> List.first(provider_caps.models)
      # Latest English model
      :cohere -> "embed-english-v3.0"
      # Fast and efficient
      :local -> "sentence-transformers/all-MiniLM-L6-v2"
    end
  end

  defp analyze_input_characteristics(input, context) do
    input_list = if is_list(input), do: input, else: [input]

    %{
      total_length: calculate_total_length(input_list),
      average_length: calculate_average_length(input_list),
      item_count: length(input_list),
      language: detect_language(input_list),
      domain: Map.get(context, :domain, :general),
      batch_processing_beneficial: length(input_list) > 1,
      large_content: calculate_total_length(input_list) > 10_000
    }
  end

  defp determine_optimal_embedding_provider(characteristics, opt_config) do
    # Score each provider based on input characteristics
    provider_scores =
      Enum.map(Map.keys(@embedding_providers), fn provider ->
        score = calculate_provider_embedding_score(provider, characteristics, opt_config)
        {provider, score}
      end)

    # Select highest scoring provider
    {best_provider, _score} = Enum.max_by(provider_scores, &elem(&1, 1))
    best_provider
  end

  defp calculate_provider_embedding_score(provider, characteristics, opt_config) do
    provider_caps = Map.get(@embedding_providers, provider)

    # Base quality score
    quality_score = provider_caps.quality_score

    # Cost optimization factor
    cost_factor =
      if opt_config.cost_optimization do
        # Lower cost = higher score
        # Normalize against highest cost
        max_cost = 0.0001
        1.0 - provider_caps.cost_per_1k_tokens / max_cost
      else
        # Neutral if cost not a factor
        0.5
      end

    # Batch processing capability
    batch_factor =
      if characteristics.batch_processing_beneficial do
        # Higher batch limit = better score
        # Normalize to OpenAI limit
        provider_caps.batch_size_limit / 2048
      else
        # Not relevant for single items
        1.0
      end

    # Large content handling
    content_factor =
      if characteristics.large_content do
        # Normalize to OpenAI limit
        provider_caps.max_tokens_per_request / 8191
      else
        1.0
      end

    # Availability factor (check if provider is healthy)
    availability_factor = get_provider_availability_score(provider)

    # Weighted composite score
    composite_score =
      quality_score * 0.3 +
        cost_factor * 0.25 +
        batch_factor * 0.2 +
        content_factor * 0.15 +
        availability_factor * 0.1

    Float.round(composite_score, 3)
  end

  defp get_provider_availability_score(provider) do
    case ProviderRegistry.get_provider(provider) do
      {:ok, provider_data} ->
        health = Map.get(provider_data, :health, :unknown)

        case health do
          :healthy -> 1.0
          :degraded -> 0.7
          :recovering -> 0.5
          _ -> 0.3
        end

      {:error, _reason} ->
        # Low availability if can't get status
        0.3
    end
  end

  defp preprocess_input(input, provider, opt_config) do
    provider_caps = Map.get(@embedding_providers, provider)

    cond do
      is_list(input) and opt_config.enable_batching ->
        # Batch processing
        preprocess_batch_input(input, provider_caps, opt_config)

      is_list(input) ->
        # Convert to single concatenated string if batching disabled
        concatenated = Enum.join(input, " ")
        preprocess_single_input(concatenated, provider_caps)

      is_binary(input) ->
        preprocess_single_input(input, provider_caps)

      true ->
        {:error, {:invalid_input_type, input}}
    end
  end

  defp preprocess_single_input(text, provider_caps) do
    # Check token limits and truncate if necessary
    estimated_tokens = estimate_token_count(text)

    if estimated_tokens > provider_caps.max_tokens_per_request do
      truncated_text = truncate_text(text, provider_caps.max_tokens_per_request)

      Logger.warn("GenerateEmbeddingAction: Text truncated for provider limits",
        original_tokens: estimated_tokens,
        max_tokens: provider_caps.max_tokens_per_request
      )

      {:ok, truncated_text}
    else
      {:ok, text}
    end
  end

  defp preprocess_batch_input(texts, provider_caps, opt_config) do
    # Optimize batch size and handle token limits
    batch_limit = provider_caps.batch_size_limit
    max_tokens = provider_caps.max_tokens_per_request

    # Process each text for token limits
    processed_texts =
      Enum.map(texts, fn text ->
        estimated_tokens = estimate_token_count(text)

        if estimated_tokens > max_tokens do
          truncate_text(text, max_tokens)
        else
          text
        end
      end)

    # Split into batches if needed
    if length(processed_texts) > batch_limit do
      Logger.info("GenerateEmbeddingAction: Splitting into batches",
        total_items: length(processed_texts),
        batch_size: batch_limit
      )

      batches = Enum.chunk_every(processed_texts, batch_limit)
      {:ok, {:batched, batches}}
    else
      {:ok, processed_texts}
    end
  end

  defp execute_embedding_generation(provider, processed_input, config, context) do
    case processed_input do
      {:batched, batches} ->
        execute_batch_embedding(provider, batches, config, context)

      input when is_list(input) ->
        execute_single_batch_embedding(provider, input, config, context)

      input when is_binary(input) ->
        execute_single_embedding(provider, input, config, context)
    end
  end

  defp execute_single_embedding(provider, text, config, context) do
    embedding_params = build_embedding_params(provider, text, config)

    case CallAPIAction.run(
           %{
             provider: provider,
             operation: :embed,
             request_params: embedding_params,
             context: context
           },
           %{}
         ) do
      {:ok, result} ->
        embedding_vector = extract_embedding_vector(result.response)

        {:ok,
         %{
           embeddings: [embedding_vector],
           model: config.selected_model,
           provider: provider,
           input_count: 1,
           selection_reason: "Single embedding generation",
           optimizations_applied: result.optimizations_applied || []
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_single_batch_embedding(provider, texts, config, context) do
    embedding_params = build_batch_embedding_params(provider, texts, config)

    case CallAPIAction.run(
           %{
             provider: provider,
             operation: :embed,
             request_params: embedding_params,
             context: context
           },
           %{}
         ) do
      {:ok, result} ->
        embeddings = extract_batch_embeddings(result.response)

        {:ok,
         %{
           embeddings: embeddings,
           model: config.selected_model,
           provider: provider,
           input_count: length(texts),
           selection_reason: "Batch embedding generation",
           optimizations_applied: result.optimizations_applied || []
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_batch_embedding(provider, batches, config, context) do
    Logger.info("GenerateEmbeddingAction: Processing #{length(batches)} batches")

    # Process each batch and combine results
    batch_results =
      Enum.with_index(batches, 1)
      |> Enum.map(fn {batch, index} ->
        Logger.debug("GenerateEmbeddingAction: Processing batch #{index}/#{length(batches)}")

        case execute_single_batch_embedding(provider, batch, config, context) do
          {:ok, result} ->
            result.embeddings

          {:error, reason} ->
            Logger.error("GenerateEmbeddingAction: Batch #{index} failed", error: reason)
            []
        end
      end)

    # Combine all embeddings
    all_embeddings = List.flatten(batch_results)

    if Enum.empty?(all_embeddings) do
      {:error, :all_batches_failed}
    else
      {:ok,
       %{
         embeddings: all_embeddings,
         model: config.selected_model,
         provider: provider,
         input_count: length(all_embeddings),
         selection_reason: "Multi-batch embedding generation",
         optimizations_applied: [:batch_processing]
       }}
    end
  end

  # Provider-specific parameter building

  defp build_embedding_params(provider, text, config) do
    base_params = %{
      input: text,
      model: config.selected_model
    }

    # Add provider-specific parameters
    case provider do
      :openai ->
        Map.merge(base_params, %{
          dimensions: get_optimal_dimensions(:openai, config),
          encoding_format: "float"
        })

      :cohere ->
        Map.merge(base_params, %{
          # or "classification", "clustering"
          input_type: "search_query",
          truncate: "END"
        })

      :local ->
        # Local models typically use simple input format
        base_params

      _ ->
        base_params
    end
  end

  defp build_batch_embedding_params(provider, texts, config) do
    case provider do
      :openai ->
        %{
          input: texts,
          model: config.selected_model,
          dimensions: get_optimal_dimensions(:openai, config),
          encoding_format: "float"
        }

      :cohere ->
        %{
          texts: texts,
          model: config.selected_model,
          input_type: "search_document",
          truncate: "END"
        }

      _ ->
        %{input: texts, model: config.selected_model}
    end
  end

  defp get_optimal_dimensions(provider, config) do
    provider_caps = Map.get(@embedding_providers, provider)
    quality_threshold = Map.get(config, :quality_threshold, 0.8)

    # Higher quality threshold = higher dimensions
    if quality_threshold > 0.9 and provider == :openai do
      # High-quality dimensions for OpenAI
      3072
    else
      # Default dimensions
      List.first(provider_caps.dimensions)
    end
  end

  # Response processing and extraction

  defp extract_embedding_vector(response) do
    case response do
      %{data: [%{embedding: embedding} | _]} -> embedding
      %{embedding: embedding} -> embedding
      %{embeddings: [embedding | _]} -> embedding
      _ -> []
    end
  end

  defp extract_batch_embeddings(response) do
    case response do
      %{data: data} when is_list(data) ->
        Enum.map(data, &Map.get(&1, :embedding, []))

      %{embeddings: embeddings} when is_list(embeddings) ->
        embeddings

      _ ->
        []
    end
  end

  # Quality assessment and cost calculation

  defp assess_embedding_quality(embedding_result, original_input, provider) do
    embeddings = embedding_result.embeddings
    provider_caps = Map.get(@embedding_providers, provider)

    # Basic quality metrics
    quality_metrics = %{
      provider_base_quality: provider_caps.quality_score,
      embedding_consistency: calculate_embedding_consistency(embeddings),
      dimension_correctness: validate_embedding_dimensions(embeddings, provider_caps),
      non_zero_values: check_non_zero_embeddings(embeddings)
    }

    # Overall quality score
    quality_score = calculate_composite_quality_score(quality_metrics)

    %{
      quality_score: quality_score,
      quality_metrics: quality_metrics,
      validation_passed: quality_score >= 0.7,
      issues: identify_quality_issues(quality_metrics)
    }
  end

  defp calculate_embedding_cost(embedding_result, provider, processed_input) do
    provider_caps = Map.get(@embedding_providers, provider)
    input_count = get_input_count(processed_input)

    # Estimate tokens processed
    total_tokens =
      case processed_input do
        {:batched, batches} ->
          batches
          |> List.flatten()
          |> Enum.map(&estimate_token_count/1)
          |> Enum.sum()

        texts when is_list(texts) ->
          Enum.map(texts, &estimate_token_count/1) |> Enum.sum()

        text when is_binary(text) ->
          estimate_token_count(text)
      end

    estimated_cost = total_tokens / 1000 * provider_caps.cost_per_1k_tokens

    %{
      provider: provider,
      estimated_tokens: total_tokens,
      estimated_cost_usd: estimated_cost,
      cost_per_embedding: if(input_count > 0, do: estimated_cost / input_count, else: 0),
      input_count: input_count,
      cost_efficiency: calculate_cost_efficiency(estimated_cost, embedding_result, provider_caps)
    }
  end

  # Utility functions

  defp determine_input_type(input) do
    case input do
      text when is_binary(text) -> :single_text
      texts when is_list(texts) -> :batch_texts
      _ -> :unknown
    end
  end

  defp get_input_count(processed_input) do
    case processed_input do
      {:batched, batches} -> batches |> List.flatten() |> length()
      texts when is_list(texts) -> length(texts)
      _ -> 1
    end
  end

  defp calculate_total_length(texts) when is_list(texts) do
    Enum.map(texts, &String.length/1) |> Enum.sum()
  end

  defp calculate_total_length(text) when is_binary(text), do: String.length(text)

  defp calculate_average_length(texts) when is_list(texts) do
    if Enum.empty?(texts) do
      0
    else
      total = calculate_total_length(texts)
      total / Enum.count(texts)
    end
  end

  defp detect_language([first_text | _]) when is_binary(first_text) do
    # Simple language detection heuristic
    cond do
      String.contains?(String.downcase(first_text), ["the", "and", "or", "but", "in", "on"]) ->
        :english

      String.contains?(String.downcase(first_text), ["und", "oder", "aber", "in", "auf"]) ->
        :german

      String.contains?(String.downcase(first_text), ["et", "ou", "mais", "dans", "sur"]) ->
        :french

      true ->
        :unknown
    end
  end

  defp detect_language(_), do: :unknown

  defp estimate_token_count(text) when is_binary(text) do
    # Rough estimation: 1 token per 4 characters
    round(String.length(text) / 4)
  end

  defp truncate_text(text, max_tokens) when is_binary(text) do
    # Simple truncation based on character count
    # Approximate conversion
    max_chars = max_tokens * 4
    String.slice(text, 0, max_chars)
  end

  defp get_embedding_dimensions(embeddings) when is_list(embeddings) do
    case List.first(embeddings) do
      embedding when is_list(embedding) -> length(embedding)
      _ -> 0
    end
  end

  # Quality assessment helper functions

  defp calculate_embedding_consistency(embeddings) when is_list(embeddings) do
    if length(embeddings) < 2 do
      # Single embedding is "consistent"
      1.0
    else
      # Check if all embeddings have same dimensions
      dimensions = Enum.map(embeddings, &length/1)
      unique_dimensions = Enum.uniq(dimensions)

      if length(unique_dimensions) == 1 do
        # All same dimension
        1.0
      else
        # Inconsistent dimensions
        0.0
      end
    end
  end

  defp validate_embedding_dimensions(embeddings, provider_caps) do
    expected_dimensions = List.first(provider_caps.dimensions)
    actual_dimensions = get_embedding_dimensions(embeddings)

    if actual_dimensions == expected_dimensions do
      1.0
    else
      # Wrong dimensions but might still be usable
      0.5
    end
  end

  defp check_non_zero_embeddings(embeddings) when is_list(embeddings) do
    non_zero_count =
      Enum.count(embeddings, fn embedding ->
        case embedding do
          values when is_list(values) -> Enum.any?(values, &(&1 != 0.0))
          _ -> false
        end
      end)

    if length(embeddings) > 0 do
      non_zero_count / length(embeddings)
    else
      0.0
    end
  end

  defp calculate_composite_quality_score(quality_metrics) do
    base_quality = quality_metrics.provider_base_quality
    consistency = quality_metrics.embedding_consistency
    dimensions = quality_metrics.dimension_correctness
    non_zero = quality_metrics.non_zero_values

    # Weighted composite score
    composite = base_quality * 0.4 + consistency * 0.2 + dimensions * 0.2 + non_zero * 0.2
    Float.round(composite, 3)
  end

  defp identify_quality_issues(quality_metrics) do
    issues = []

    issues =
      if quality_metrics.embedding_consistency < 1.0 do
        [:inconsistent_dimensions | issues]
      else
        issues
      end

    issues =
      if quality_metrics.dimension_correctness < 1.0 do
        [:incorrect_dimensions | issues]
      else
        issues
      end

    issues =
      if quality_metrics.non_zero_values < 0.8 do
        [:too_many_zero_embeddings | issues]
      else
        issues
      end

    Enum.reverse(issues)
  end

  defp calculate_cost_efficiency(estimated_cost, embedding_result, provider_caps) do
    # Cost efficiency = quality per dollar
    quality = provider_caps.quality_score
    embedding_count = length(embedding_result.embeddings)

    if estimated_cost > 0 and embedding_count > 0 do
      # Quality * count per cost
      quality * embedding_count / estimated_cost
    else
      # High efficiency for free providers
      quality * 1000
    end
  end
end
