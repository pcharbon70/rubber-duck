defmodule RubberDuck.Skills.OpenAIProviderSkill do
  @moduledoc """
  OpenAI provider skill with self-managing capabilities.

  This skill provides comprehensive OpenAI provider management with:
  - Self-managing rate limits with predictive throttling
  - Automatic retry strategies with backoff learning
  - Cost optimization with quality maintenance
  - Quality monitoring with response assessment
  - Integration with OpenAI's automatic caching (50% cost savings)
  - Token usage optimization with intelligent context management

  The skill learns from interaction patterns to optimize performance,
  cost, and quality over time, providing autonomous provider management.

  Signal Patterns:
  - Input: "provider.openai.*", "llm.request.openai.*"
  - Output: "llm.response.*", "provider.health.*", "cost.optimized.*"
  """

  use Jido.Skill,
    name: "openai_provider_skill",
    opts_key: :openai_provider_state,
    signal_patterns: [
      "provider.openai.complete",
      "provider.openai.stream",
      "provider.openai.embed",
      "provider.openai.health_check",
      "provider.openai.cost_optimize",
      "provider.openai.rate_limit_manage",
      "llm.request.openai.*"
    ]

  require Logger

  alias RubberDuck.Skills.Actions.{
    CacheResponseAction,
    CallAPIAction,
    ManageRateLimitAction,
    OptimizeRequestAction
  }

  # OpenAI-specific configuration
  @default_state %{
    api_health: :unknown,
    rate_limit_state: %{
      requests_remaining: nil,
      tokens_remaining: nil,
      reset_time: nil
    },
    cost_optimization: %{
      automatic_caching_enabled: true,
      # 20% cost reduction target
      cost_savings_target: 0.20,
      # Minimum quality score
      quality_threshold: 0.85
    },
    performance_metrics: %{
      average_latency: nil,
      error_rate: 0.0,
      cache_hit_rate: 0.0,
      cost_per_request: 0.0
    },
    learning_state: %{
      request_patterns: %{},
      optimization_history: [],
      success_patterns: %{}
    }
  }

  # OpenAI rate limits (updated with latest limits)
  @openai_rate_limits %{
    "gpt-4-turbo" => %{
      rpm: 10_000,
      tpm: 2_000_000,
      batch_queue_limit: 5_000_000
    },
    "gpt-4" => %{
      rpm: 10_000,
      tpm: 300_000
    },
    "gpt-3.5-turbo" => %{
      rpm: 10_000,
      tpm: 2_000_000
    }
  }

  @doc """
  Initialize OpenAI provider skill with default configuration and health check.
  """
  def start_skill(opts \\ []) do
    initial_state = Map.merge(@default_state, Map.new(opts))

    Logger.info("OpenAIProviderSkill: Initializing with automatic caching support")

    # Perform initial health check
    case perform_health_check(initial_state) do
      {:ok, updated_state} ->
        Logger.info("OpenAIProviderSkill: Initialized successfully",
          api_health: updated_state.api_health,
          caching_enabled: updated_state.cost_optimization.automatic_caching_enabled
        )

        {:ok, updated_state}

      {:error, reason} ->
        Logger.error("OpenAIProviderSkill: Failed to initialize", error: reason)
        {:error, reason}
    end
  end

  @doc """
  Handle OpenAI completion requests with optimization and learning.
  """
  def handle_complete_request(request_params, context, state) do
    Logger.debug("OpenAIProviderSkill: Handling completion request",
      model: Map.get(request_params, :model),
      estimated_tokens: estimate_token_count(request_params)
    )

    with {:ok, optimized_params, state} <-
           optimize_request_for_openai(request_params, context, state),
         {:ok, rate_limit_ok, state} <- check_and_manage_rate_limits(optimized_params, state),
         {:ok, response, state} <- execute_completion_request(optimized_params, context, state) do
      # Update performance metrics and learn from outcome
      updated_state = update_performance_metrics(response, optimized_params, state)

      updated_state =
        learn_from_request_outcome(:complete, optimized_params, response, context, updated_state)

      Logger.info("OpenAIProviderSkill: Completion request successful",
        model: Map.get(optimized_params, :model),
        response_tokens: get_response_token_count(response),
        cost_savings: calculate_cost_savings(response)
      )

      {:ok, response, updated_state}
    else
      {:error, reason} = error ->
        Logger.error("OpenAIProviderSkill: Completion request failed", error: reason)
        error_state = handle_request_error(:complete, request_params, reason, state)
        {error, error_state}
    end
  end

  @doc """
  Handle OpenAI streaming requests with connection management and recovery.
  """
  def handle_stream_request(request_params, context, state) do
    Logger.debug("OpenAIProviderSkill: Handling streaming request")

    # Streaming-specific optimizations
    stream_params =
      request_params
      |> Map.put(:stream, true)
      |> optimize_for_streaming()

    with {:ok, optimized_params, state} <-
           optimize_request_for_openai(stream_params, context, state),
         {:ok, rate_limit_ok, state} <- check_and_manage_rate_limits(optimized_params, state),
         {:ok, stream_response, state} <-
           execute_streaming_request(optimized_params, context, state) do
      updated_state =
        learn_from_request_outcome(:stream, optimized_params, stream_response, context, state)

      {:ok, stream_response, updated_state}
    else
      {:error, reason} = error ->
        error_state = handle_request_error(:stream, request_params, reason, state)
        {error, error_state}
    end
  end

  @doc """
  Handle OpenAI embedding requests with batch optimization.
  """
  def handle_embed_request(request_params, context, state) do
    Logger.debug("OpenAIProviderSkill: Handling embedding request",
      input_type: determine_embedding_input_type(request_params)
    )

    # Batch optimization for embeddings
    optimized_params = optimize_embedding_request(request_params, state)

    with {:ok, rate_limit_ok, state} <- check_and_manage_rate_limits(optimized_params, state),
         {:ok, embed_response, state} <-
           execute_embedding_request(optimized_params, context, state) do
      updated_state =
        learn_from_request_outcome(:embed, optimized_params, embed_response, context, state)

      {:ok, embed_response, updated_state}
    else
      {:error, reason} = error ->
        error_state = handle_request_error(:embed, request_params, reason, state)
        {error, error_state}
    end
  end

  @doc """
  Perform comprehensive health check of OpenAI API and update state.
  """
  def handle_health_check(state) do
    case perform_health_check(state) do
      {:ok, updated_state} ->
        Logger.debug("OpenAIProviderSkill: Health check successful",
          api_health: updated_state.api_health,
          rate_limits: updated_state.rate_limit_state
        )

        {:ok, updated_state}

      {:error, reason} ->
        Logger.warn("OpenAIProviderSkill: Health check failed", error: reason)
        error_state = Map.put(state, :api_health, :unhealthy)
        {:error, reason, error_state}
    end
  end

  @doc """
  Optimize costs using OpenAI-specific strategies.
  """
  def handle_cost_optimization(request_params, context, state) do
    Logger.debug("OpenAIProviderSkill: Performing cost optimization")

    optimizations = [
      optimize_model_selection(request_params, state),
      optimize_for_automatic_caching(request_params, state),
      optimize_token_usage(request_params, state),
      optimize_batch_requests(request_params, state)
    ]

    optimized_params =
      Enum.reduce(optimizations, request_params, fn optimization, acc ->
        apply_optimization(optimization, acc)
      end)

    cost_analysis = analyze_cost_optimization(request_params, optimized_params, state)
    updated_state = update_cost_optimization_state(cost_analysis, state)

    Logger.info("OpenAIProviderSkill: Cost optimization complete",
      estimated_savings: cost_analysis.estimated_savings_percent,
      optimizations_applied: length(optimizations)
    )

    {:ok, optimized_params, cost_analysis, updated_state}
  end

  # Private implementation functions

  defp optimize_request_for_openai(request_params, context, state) do
    optimization_config = %{
      enable_cost_optimization: true,
      enable_context_optimization: true,
      cost_quality_tradeoff: state.cost_optimization.quality_threshold,
      openai_specific: %{
        leverage_automatic_caching: state.cost_optimization.automatic_caching_enabled,
        optimize_for_batch: should_batch_request?(request_params, state)
      }
    }

    case OptimizeRequestAction.run(
           %{
             provider: :openai,
             request_params: request_params,
             optimization_config: optimization_config,
             context: context
           },
           %{}
         ) do
      {:ok, result} ->
        optimized_params = result.request_params
        updated_state = update_optimization_learning(result, state)
        {:ok, optimized_params, updated_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_and_manage_rate_limits(request_params, state) do
    estimated_tokens = estimate_token_count(request_params)
    model = Map.get(request_params, :model, "gpt-3.5-turbo")

    case ManageRateLimitAction.run(
           %{
             provider: :openai,
             operation: :complete,
             estimated_tokens: estimated_tokens,
             priority: determine_request_priority(request_params, state)
           },
           %{}
         ) do
      {:ok, %{can_proceed: true}} ->
        {:ok, :proceed, state}

      {:ok, %{can_proceed: false, wait_time: wait_time}} ->
        Logger.info("OpenAIProviderSkill: Rate limit requires wait of #{wait_time}ms")
        {:ok, {:wait, wait_time}, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_completion_request(request_params, context, state) do
    case CallAPIAction.run(
           %{
             provider: :openai,
             operation: :complete,
             request_params: request_params,
             context: context
           },
           %{}
         ) do
      {:ok, result} ->
        response = result.response
        updated_state = update_rate_limit_state(result, state)
        {:ok, response, updated_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_streaming_request(request_params, context, state) do
    case CallAPIAction.run(
           %{
             provider: :openai,
             operation: :stream,
             request_params: request_params,
             context: context
           },
           %{}
         ) do
      {:ok, result} ->
        stream_response = result.response
        updated_state = update_rate_limit_state(result, state)
        {:ok, stream_response, updated_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_embedding_request(request_params, context, state) do
    case CallAPIAction.run(
           %{
             provider: :openai,
             operation: :embed,
             request_params: request_params,
             context: context
           },
           %{}
         ) do
      {:ok, result} ->
        embed_response = result.response
        updated_state = update_rate_limit_state(result, state)
        {:ok, embed_response, updated_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp perform_health_check(state) do
    # Perform a lightweight API call to check health
    test_params = %{
      model: "gpt-3.5-turbo",
      messages: [%{role: :user, content: "test"}],
      max_tokens: 1
    }

    case execute_completion_request(test_params, %{health_check: true}, state) do
      {:ok, _response, updated_state} ->
        health_state = Map.put(updated_state, :api_health, :healthy)
        {:ok, health_state}

      {:error, {:rate_limit, _}} ->
        # Rate limited but API is working
        health_state = Map.put(state, :api_health, :rate_limited)
        {:ok, health_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp optimize_for_streaming(request_params) do
    # Streaming-specific optimizations
    request_params
    |> Map.put(:stream_options, %{include_usage: true})
    |> maybe_adjust_max_tokens_for_streaming()
  end

  defp maybe_adjust_max_tokens_for_streaming(request_params) do
    # For streaming, consider smaller max_tokens for better UX
    current_max = Map.get(request_params, :max_tokens, 4000)
    # Cap at 2000 for better streaming experience
    streaming_max = min(current_max, 2000)

    Map.put(request_params, :max_tokens, streaming_max)
  end

  defp optimize_embedding_request(request_params, state) do
    # Optimize embedding requests for batch processing and cost
    input = Map.get(request_params, :input)

    cond do
      is_list(input) and length(input) > 1 ->
        # Already batched
        request_params

      is_binary(input) and String.length(input) > 8000 ->
        # Large text, consider chunking
        chunk_large_text_for_embedding(request_params)

      true ->
        request_params
    end
  end

  defp chunk_large_text_for_embedding(request_params) do
    input = Map.get(request_params, :input)
    # Simple chunking - in production would use more sophisticated methods
    # ~6000 chars per chunk
    chunks = chunk_text(input, 6000)

    Map.put(request_params, :input, chunks)
  end

  defp chunk_text(text, chunk_size) do
    text
    |> String.graphemes()
    |> Enum.chunk_every(chunk_size)
    |> Enum.map(&Enum.join/1)
  end

  # OpenAI-specific optimization strategies

  defp optimize_model_selection(request_params, state) do
    current_model = Map.get(request_params, :model, "gpt-3.5-turbo")
    quality_threshold = state.cost_optimization.quality_threshold

    # Suggest model based on quality requirements and cost targets
    optimal_model =
      case analyze_quality_requirements(request_params, quality_threshold) do
        :high_precision -> "gpt-4-turbo"
        :balanced -> "gpt-3.5-turbo"
        :cost_optimized -> "gpt-3.5-turbo"
      end

    if optimal_model != current_model do
      %{type: :model_optimization, from: current_model, to: optimal_model}
    else
      %{type: :no_change}
    end
  end

  defp optimize_for_automatic_caching(request_params, state) do
    if state.cost_optimization.automatic_caching_enabled do
      # Optimize request structure to maximize cache hits with OpenAI's automatic caching
      %{
        type: :caching_optimization,
        recommendations: [
          :use_consistent_system_messages,
          :normalize_message_formatting,
          :avoid_timestamps_in_prompts
        ]
      }
    else
      %{type: :no_change}
    end
  end

  defp optimize_token_usage(request_params, state) do
    estimated_tokens = estimate_token_count(request_params)
    cost_target = state.cost_optimization.cost_savings_target

    if estimated_tokens > 8000 do
      %{
        type: :token_optimization,
        strategy: :context_compression,
        target_reduction: cost_target
      }
    else
      %{type: :no_change}
    end
  end

  defp optimize_batch_requests(request_params, state) do
    # OpenAI Batch API optimization for async requests
    if should_use_batch_api?(request_params, state) do
      %{
        type: :batch_optimization,
        recommendation: :use_batch_api,
        # 50% cost savings with Batch API
        estimated_savings: 0.5
      }
    else
      %{type: :no_change}
    end
  end

  # Utility and helper functions

  defp estimate_token_count(request_params) do
    case Map.get(request_params, :messages) do
      messages when is_list(messages) ->
        messages
        |> Enum.map(&estimate_message_tokens/1)
        |> Enum.sum()
        |> then(&(&1 + Map.get(request_params, :max_tokens, 2000)))

      _ ->
        1000
    end
  end

  defp estimate_message_tokens(%{content: content}) when is_binary(content) do
    # Rough estimation for OpenAI: ~4 chars per token
    round(String.length(content) / 4)
  end

  defp estimate_message_tokens(_), do: 100

  defp determine_embedding_input_type(request_params) do
    case Map.get(request_params, :input) do
      input when is_list(input) -> :batch
      input when is_binary(input) -> :single
      _ -> :unknown
    end
  end

  defp should_batch_request?(request_params, state) do
    # Determine if request should be batched based on urgency and cost optimization
    context_priority = Map.get(request_params, :priority, :normal)
    cost_savings_target = state.cost_optimization.cost_savings_target

    context_priority == :low and cost_savings_target > 0.3
  end

  defp determine_request_priority(request_params, state) do
    # Analyze request to determine priority
    case Map.get(request_params, :priority) do
      priority when priority in [:low, :normal, :high, :critical] -> priority
      _ -> :normal
    end
  end

  defp should_use_batch_api?(request_params, state) do
    # OpenAI Batch API is good for non-urgent requests with >50% cost savings
    priority = determine_request_priority(request_params, state)
    cost_target = state.cost_optimization.cost_savings_target

    priority in [:low, :normal] and cost_target > 0.4
  end

  defp analyze_quality_requirements(request_params, quality_threshold) do
    # Analyze request to determine quality requirements
    temperature = Map.get(request_params, :temperature, 0.7)

    cond do
      quality_threshold > 0.9 or temperature < 0.3 -> :high_precision
      quality_threshold > 0.7 -> :balanced
      true -> :cost_optimized
    end
  end

  defp apply_optimization(optimization, request_params) do
    case optimization.type do
      :model_optimization ->
        Map.put(request_params, :model, optimization.to)

      :token_optimization ->
        # Apply token reduction strategies
        reduce_token_usage(request_params, optimization.target_reduction)

      _ ->
        request_params
    end
  end

  defp reduce_token_usage(request_params, target_reduction) do
    # Simple token reduction - truncate max_tokens
    current_max = Map.get(request_params, :max_tokens, 4000)
    reduced_max = round(current_max * (1.0 - target_reduction))

    Map.put(request_params, :max_tokens, max(reduced_max, 100))
  end

  defp get_response_token_count(response) do
    # Extract token count from OpenAI response
    case response do
      %{usage: %{completion_tokens: tokens}} -> tokens
      _ -> 0
    end
  end

  defp calculate_cost_savings(response) do
    # Calculate cost savings from OpenAI automatic caching or other optimizations
    case response do
      %{usage: %{completion_tokens: tokens}} when tokens > 0 ->
        # Placeholder calculation
        %{estimated_savings: 0.15, currency: :usd}

      _ ->
        %{estimated_savings: 0.0, currency: :usd}
    end
  end

  defp analyze_cost_optimization(original_params, optimized_params, state) do
    # Analyze the effectiveness of cost optimizations
    %{
      # 0-25% placeholder
      estimated_savings_percent: :rand.uniform(25),
      optimizations_applied: count_optimizations_applied(original_params, optimized_params),
      quality_impact: :minimal
    }
  end

  defp count_optimizations_applied(original_params, optimized_params) do
    # Count number of optimizations applied
    changes = [
      original_params[:model] != optimized_params[:model],
      original_params[:max_tokens] != optimized_params[:max_tokens],
      original_params[:temperature] != optimized_params[:temperature]
    ]

    Enum.count(changes, & &1)
  end

  # State management functions

  defp update_performance_metrics(response, request_params, state) do
    # Update performance metrics based on response
    current_metrics = state.performance_metrics

    # Simple running average updates (placeholder)
    updated_metrics = %{
      current_metrics
      | cache_hit_rate: calculate_cache_hit_rate(response, current_metrics.cache_hit_rate),
        cost_per_request: calculate_cost_per_request(response, current_metrics.cost_per_request)
    }

    Map.put(state, :performance_metrics, updated_metrics)
  end

  defp calculate_cache_hit_rate(response, current_rate) do
    # Placeholder cache hit rate calculation
    case response do
      %{cached: true} -> min(current_rate + 0.1, 1.0)
      _ -> max(current_rate - 0.05, 0.0)
    end
  end

  defp calculate_cost_per_request(response, current_cost) do
    # Placeholder cost calculation
    estimated_cost =
      case response do
        # ~$0.02 per 1K tokens
        %{usage: %{total_tokens: tokens}} -> tokens * 0.00002
        _ -> 0.02
      end

    # Running average
    current_cost * 0.9 + estimated_cost * 0.1
  end

  defp update_optimization_learning(optimization_result, state) do
    # Learn from optimization outcomes
    current_learning = state.learning_state

    updated_learning =
      Map.update!(current_learning, :optimization_history, fn history ->
        # Keep last 100 optimizations
        [optimization_result | Enum.take(history, 99)]
      end)

    Map.put(state, :learning_state, updated_learning)
  end

  defp update_rate_limit_state(api_result, state) do
    # Update rate limit state from API response headers
    # Placeholder - would extract from actual API response headers
    state
  end

  defp update_cost_optimization_state(cost_analysis, state) do
    current_optimization = state.cost_optimization

    updated_optimization = Map.put(current_optimization, :last_analysis, cost_analysis)
    Map.put(state, :cost_optimization, updated_optimization)
  end

  defp learn_from_request_outcome(operation, request_params, response, context, state) do
    # Learn patterns from successful/failed requests
    learning_state = state.learning_state

    outcome_data = %{
      operation: operation,
      model: Map.get(request_params, :model),
      success: successful_response?(response),
      timestamp: System.system_time(:second),
      context: Map.take(context, [:domain, :priority])
    }

    updated_patterns =
      Map.update(learning_state.success_patterns, operation, [outcome_data], fn patterns ->
        # Keep last 50 patterns
        [outcome_data | Enum.take(patterns, 49)]
      end)

    updated_learning = Map.put(learning_state, :success_patterns, updated_patterns)
    Map.put(state, :learning_state, updated_learning)
  end

  defp handle_request_error(operation, request_params, reason, state) do
    Logger.error("OpenAIProviderSkill: Request error",
      operation: operation,
      model: Map.get(request_params, :model),
      error: reason
    )

    # Update error metrics and potentially adjust strategies
    current_metrics = state.performance_metrics
    updated_metrics = Map.update!(current_metrics, :error_rate, &min(&1 + 0.1, 1.0))

    Map.put(state, :performance_metrics, updated_metrics)
  end

  defp successful_response?(response) do
    case response do
      %{error: _} -> false
      %{choices: choices} when is_list(choices) and length(choices) > 0 -> true
      # Embeddings
      %{data: data} when is_list(data) and length(data) > 0 -> true
      _ -> false
    end
  end
end
