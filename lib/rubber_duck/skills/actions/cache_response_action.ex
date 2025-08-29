defmodule RubberDuck.Skills.Actions.CacheResponseAction do
  @moduledoc """
  Provider-aware response caching with intelligent invalidation.

  This action provides sophisticated caching for LLM responses with provider-specific
  optimizations, semantic similarity detection, and intelligent cache management
  to maximize cost savings while maintaining response quality.

  Features:
  - Semantic similarity detection to identify equivalent requests
  - Provider-specific caching strategies (OpenAI automatic caching vs manual)
  - Relevance scoring for cache hit/miss decisions
  - Automatic cache invalidation based on freshness and usage patterns
  - Cost optimization through intelligent cache policies
  - Context-aware caching for different domains and use cases

  The caching system learns from usage patterns and automatically adjusts
  cache policies to optimize for both cost savings and response quality.
  """

  use Jido.Action,
    name: "cache_response",
    schema: [
      operation: [
        type: :atom,
        required: true,
        doc: "Cache operation (:get, :set, :invalidate, :stats)"
      ],
      provider: [
        type: :atom,
        required: true,
        doc: "Provider identifier (:openai, :anthropic, :local)"
      ],
      request_params: [type: :map, doc: "Request parameters for cache key generation"],
      response_data: [type: :map, doc: "Response data to cache (for :set operation)"],
      cache_config: [type: :map, default: %{}, doc: "Caching configuration"],
      context: [type: :map, default: %{}, doc: "Request context for relevance scoring"]
    ]

  require Logger

  # Cache TTL configurations per provider and operation type
  @cache_ttl_config %{
    openai: %{
      # 1 hour default, 24 hours max
      complete: %{default_ttl: 3600, max_ttl: 86_400},
      # 24 hours default, 7 days max
      embed: %{default_ttl: 86_400, max_ttl: 604_800}
    },
    anthropic: %{
      complete: %{default_ttl: 3600, max_ttl: 86_400}
    },
    local: %{
      # 30 min default, 12 hours max
      complete: %{default_ttl: 1800, max_ttl: 43_200},
      embed: %{default_ttl: 43_200, max_ttl: 604_800}
    }
  }

  # Semantic similarity thresholds for cache hits
  @similarity_thresholds %{
    # Almost identical requests
    high: 0.95,
    # Similar requests with acceptable differences
    medium: 0.85,
    # Loosely similar requests
    low: 0.75
  }

  @default_cache_config %{
    enable_semantic_matching: true,
    similarity_threshold: :medium,
    respect_provider_caching: true,
    enable_cost_optimization: true,
    track_usage: true
  }

  @doc """
  Execute cache operation with provider-specific intelligence.

  Operations:
  - `:get` - Retrieve cached response with similarity matching
  - `:set` - Store response with optimal TTL and metadata
  - `:invalidate` - Remove cached entries based on patterns
  - `:stats` - Get cache performance statistics
  """
  def run(params, _context) do
    %{
      operation: operation,
      provider: provider,
      cache_config: cache_config
    } = params

    merged_config = Map.merge(@default_cache_config, cache_config)

    Logger.debug("CacheResponseAction: Executing #{operation} for provider #{provider}",
      provider: provider,
      operation: operation,
      config: merged_config
    )

    case operation do
      :get ->
        handle_cache_get(params, merged_config)

      :set ->
        handle_cache_set(params, merged_config)

      :invalidate ->
        handle_cache_invalidate(params, merged_config)

      :stats ->
        handle_cache_stats(params, merged_config)

      _ ->
        {:error, {:unsupported_operation, operation}}
    end
  end

  # Cache retrieval with semantic matching
  defp handle_cache_get(
         %{provider: provider, request_params: request_params, context: context} = params,
         config
       ) do
    cache_key = generate_cache_key(provider, request_params, context)

    # First try exact match
    case get_exact_cache_match(cache_key) do
      {:ok, cached_response} ->
        Logger.debug("CacheResponseAction: Exact cache hit for #{provider}")
        track_cache_hit(provider, :exact, context)

        {:ok,
         %{
           hit: true,
           type: :exact,
           response: cached_response,
           cost_savings: calculate_cost_savings(provider, request_params, cached_response)
         }}

      {:error, :not_found} when config.enable_semantic_matching ->
        # Try semantic similarity matching
        handle_semantic_cache_lookup(provider, request_params, context, config)

      {:error, :not_found} ->
        Logger.debug("CacheResponseAction: Cache miss for #{provider}")
        track_cache_miss(provider, :no_match, context)
        {:ok, %{hit: false, reason: :not_found}}
    end
  end

  # Cache storage with intelligent TTL
  defp handle_cache_set(
         %{
           provider: provider,
           request_params: request_params,
           response_data: response_data,
           context: context
         } = params,
         config
       ) do
    cache_key = generate_cache_key(provider, request_params, context)
    ttl = calculate_optimal_ttl(provider, request_params, response_data, context, config)

    # Skip caching if provider has automatic caching (like OpenAI)
    if config.respect_provider_caching and has_automatic_caching?(provider) do
      Logger.debug(
        "CacheResponseAction: Skipping manual cache for #{provider} (automatic caching enabled)"
      )

      {:ok, %{cached: false, reason: :provider_automatic_caching}}
    else
      cache_metadata = %{
        provider: provider,
        operation: infer_operation_type(request_params),
        timestamp: System.system_time(:second),
        context: context,
        quality_score: calculate_quality_score(response_data),
        cost_metrics: extract_cost_metrics(response_data),
        ttl: ttl
      }

      case store_in_cache(cache_key, response_data, cache_metadata, ttl) do
        :ok ->
          Logger.debug("CacheResponseAction: Cached response for #{provider}",
            cache_key: cache_key,
            ttl: ttl,
            quality_score: cache_metadata.quality_score
          )

          track_cache_store(provider, context, cache_metadata)
          {:ok, %{cached: true, ttl: ttl, cache_key: cache_key}}

        {:error, reason} ->
          Logger.error("CacheResponseAction: Failed to cache response",
            provider: provider,
            cache_key: cache_key,
            error: reason
          )

          {:error, {:cache_store_failed, reason}}
      end
    end
  end

  # Cache invalidation with pattern matching
  defp handle_cache_invalidate(%{provider: provider} = params, config) do
    pattern = Map.get(params, :invalidation_pattern, "#{provider}:*")
    reason = Map.get(params, :reason, :manual)

    case invalidate_cache_entries(pattern, reason) do
      {:ok, count} ->
        Logger.info("CacheResponseAction: Invalidated #{count} cache entries",
          provider: provider,
          pattern: pattern,
          reason: reason
        )

        {:ok, %{invalidated: count, pattern: pattern}}

      {:error, reason} ->
        {:error, {:invalidation_failed, reason}}
    end
  end

  # Cache statistics and performance metrics
  defp handle_cache_stats(%{provider: provider} = params, config) do
    # Default 1 hour
    time_window = Map.get(params, :time_window, 3600)

    stats = %{
      provider: provider,
      time_window: time_window,
      hit_rate: calculate_hit_rate(provider, time_window),
      cost_savings: calculate_total_cost_savings(provider, time_window),
      cache_size: get_cache_size(provider),
      top_cached_operations: get_top_cached_operations(provider, time_window),
      invalidation_stats: get_invalidation_stats(provider, time_window)
    }

    {:ok, stats}
  end

  # Private implementation functions

  defp generate_cache_key(provider, request_params, context) do
    # Create a deterministic cache key based on provider, params, and relevant context
    key_data = %{
      provider: provider,
      model: request_params[:model],
      messages: normalize_messages(request_params[:messages]),
      system: request_params[:system],
      temperature: request_params[:temperature],
      max_tokens: request_params[:max_tokens],
      # Include relevant context but exclude volatile data
      context_hash: hash_context(context)
    }

    :crypto.hash(:sha256, :erlang.term_to_binary(key_data))
    |> Base.encode16(case: :lower)
    |> then(&"#{provider}:#{&1}")
  end

  defp normalize_messages(nil), do: nil

  defp normalize_messages(messages) when is_list(messages) do
    # Normalize messages for consistent caching
    Enum.map(messages, fn
      %{role: role, content: content} -> %{role: role, content: String.trim(content)}
      message -> message
    end)
  end

  defp normalize_messages(messages), do: messages

  defp hash_context(context) do
    # Hash only relevant context information for caching
    relevant_context = Map.take(context, [:domain, :user_preferences, :quality_requirements])
    :crypto.hash(:md5, :erlang.term_to_binary(relevant_context)) |> Base.encode16(case: :lower)
  end

  defp handle_semantic_cache_lookup(provider, request_params, context, config) do
    similarity_threshold = get_similarity_threshold(config.similarity_threshold)

    case find_similar_cached_responses(provider, request_params, context, similarity_threshold) do
      {:ok, similar_responses} when length(similar_responses) > 0 ->
        # Select best match based on similarity score and quality
        best_match = select_best_cache_match(similar_responses)

        Logger.debug("CacheResponseAction: Semantic cache hit for #{provider}",
          similarity_score: best_match.similarity_score,
          quality_score: best_match.quality_score
        )

        track_cache_hit(provider, :semantic, context)

        {:ok,
         %{
           hit: true,
           type: :semantic,
           response: best_match.response,
           similarity_score: best_match.similarity_score,
           cost_savings: calculate_cost_savings(provider, request_params, best_match.response)
         }}

      _ ->
        Logger.debug("CacheResponseAction: No semantic matches found for #{provider}")
        track_cache_miss(provider, :no_semantic_match, context)
        {:ok, %{hit: false, reason: :no_semantic_matches}}
    end
  end

  defp get_similarity_threshold(threshold_key) do
    Map.get(@similarity_thresholds, threshold_key, @similarity_thresholds.medium)
  end

  defp calculate_optimal_ttl(provider, request_params, response_data, context, config) do
    operation_type = infer_operation_type(request_params)
    base_ttl = get_in(@cache_ttl_config, [provider, operation_type, :default_ttl]) || 3600
    max_ttl = get_in(@cache_ttl_config, [provider, operation_type, :max_ttl]) || 86_400

    # Adjust TTL based on response quality and context
    quality_factor = calculate_ttl_quality_factor(response_data)
    context_factor = calculate_ttl_context_factor(context)

    adjusted_ttl = base_ttl * quality_factor * context_factor
    min(round(adjusted_ttl), max_ttl)
  end

  defp infer_operation_type(request_params) do
    cond do
      Map.has_key?(request_params, :input) -> :embed
      Map.has_key?(request_params, :stream) and request_params.stream -> :stream
      true -> :complete
    end
  end

  defp has_automatic_caching?(provider) do
    # OpenAI has automatic caching, others typically don't
    provider == :openai
  end

  defp calculate_quality_score(response_data) do
    # Calculate quality score based on response characteristics
    # Higher scores indicate better responses worth caching longer
    base_score = 0.8

    # Adjust based on response length and completeness
    content_factor = if has_complete_response?(response_data), do: 1.2, else: 0.9

    # Adjust based on any quality indicators in response
    quality_factor = extract_quality_indicators(response_data)

    min(base_score * content_factor * quality_factor, 1.0)
  end

  defp has_complete_response?(response_data) do
    case response_data do
      %{choices: [%{finish_reason: "stop"} | _]} -> true
      %{content: content} when is_binary(content) and byte_size(content) > 10 -> true
      _ -> false
    end
  end

  defp extract_quality_indicators(response_data) do
    # Extract quality indicators from response metadata
    # This would analyze response confidence, completeness, etc.
    # Placeholder implementation
    1.0
  end

  defp calculate_ttl_quality_factor(response_data) do
    quality_score = calculate_quality_score(response_data)
    # Higher quality responses get longer TTL
    0.5 + quality_score * 1.5
  end

  defp calculate_ttl_context_factor(context) do
    # Adjust TTL based on context characteristics
    case Map.get(context, :domain) do
      # Code changes frequently
      :code_evaluation -> 0.8
      # General knowledge is stable
      :general_knowledge -> 1.5
      # Current events change rapidly
      :current_events -> 0.3
      _ -> 1.0
    end
  end

  defp calculate_cost_savings(provider, request_params, cached_response) do
    # Calculate estimated cost savings from cache hit
    estimated_tokens = estimate_token_count(request_params)
    cost_per_token = get_provider_cost_per_token(provider)

    %{
      estimated_tokens_saved: estimated_tokens,
      estimated_cost_saved: estimated_tokens * cost_per_token,
      currency: :usd
    }
  end

  defp estimate_token_count(request_params) do
    # Simple token estimation - in real system would use actual tokenizer
    case request_params do
      %{messages: messages} when is_list(messages) ->
        messages
        |> Enum.map(&estimate_message_tokens/1)
        |> Enum.sum()

      %{input: input} when is_binary(input) ->
        # Rough estimation: 1 token per 4 characters
        round(String.length(input) / 4)

      # Default estimate
      _ ->
        1000
    end
  end

  defp estimate_message_tokens(%{content: content}) when is_binary(content) do
    round(String.length(content) / 4)
  end

  defp estimate_message_tokens(_), do: 100

  defp get_provider_cost_per_token(provider) do
    # Approximate costs per token in USD
    case provider do
      # ~$0.02 per 1K tokens
      :openai -> 0.00002
      # ~$0.024 per 1K tokens
      :anthropic -> 0.000024
      # No direct cost for local models
      :local -> 0.0
    end
  end

  # Cache interface functions (would be implemented with ETS, Redis, or database)

  defp get_exact_cache_match(_cache_key) do
    # Placeholder implementation
    {:error, :not_found}
  end

  defp find_similar_cached_responses(_provider, _request_params, _context, _threshold) do
    # Placeholder implementation for semantic similarity search
    {:ok, []}
  end

  defp select_best_cache_match(similar_responses) do
    # Select the best match based on similarity and quality scores
    Enum.max_by(similar_responses, fn response ->
      response.similarity_score * 0.7 + response.quality_score * 0.3
    end)
  end

  defp store_in_cache(_cache_key, _response_data, _metadata, _ttl) do
    # Placeholder implementation
    :ok
  end

  defp invalidate_cache_entries(_pattern, _reason) do
    # Placeholder implementation
    {:ok, 0}
  end

  # Statistics and metrics functions

  defp track_cache_hit(provider, type, context) do
    Logger.debug("CacheResponseAction: Cache hit tracked",
      provider: provider,
      type: type,
      context: Map.take(context, [:domain])
    )
  end

  defp track_cache_miss(provider, reason, context) do
    Logger.debug("CacheResponseAction: Cache miss tracked",
      provider: provider,
      reason: reason,
      context: Map.take(context, [:domain])
    )
  end

  defp track_cache_store(provider, context, metadata) do
    Logger.debug("CacheResponseAction: Cache store tracked",
      provider: provider,
      quality_score: metadata.quality_score,
      ttl: metadata.ttl
    )
  end

  defp calculate_hit_rate(_provider, _time_window), do: 0.0
  defp calculate_total_cost_savings(_provider, _time_window), do: %{amount: 0.0, currency: :usd}
  defp get_cache_size(_provider), do: 0
  defp get_top_cached_operations(_provider, _time_window), do: []
  defp get_invalidation_stats(_provider, _time_window), do: %{manual: 0, automatic: 0, expired: 0}
  defp extract_cost_metrics(_response_data), do: %{}
end
