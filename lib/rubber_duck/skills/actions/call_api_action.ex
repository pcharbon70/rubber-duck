defmodule RubberDuck.Skills.Actions.CallAPIAction do
  @moduledoc """
  Universal API calling action with provider-specific handling.

  This action provides a unified interface for LLM API calls across all providers
  (OpenAI, Anthropic, local models) with adaptive error handling, automatic retries,
  and provider-specific optimization strategies.

  Supports three operation modes:
  - Complete: Full response generation with blocking operation
  - Stream: Streaming responses with real-time token delivery
  - Embed: Embedding generation with batch optimization

  Features:
  - Provider-specific error handling and recovery strategies
  - Adaptive rate limit management with predictive throttling
  - Context window optimization based on provider capabilities
  - Cost optimization with quality maintenance
  - Performance tracking and learning integration
  """

  use Jido.Action,
    name: "call_api",
    schema: [
      provider: [
        type: :atom,
        required: true,
        doc: "Provider identifier (:openai, :anthropic, :local)"
      ],
      operation: [type: :atom, required: true, doc: "API operation (:complete, :stream, :embed)"],
      request_params: [type: :map, required: true, doc: "Provider-specific request parameters"],
      optimization_config: [type: :map, default: %{}, doc: "Optimization configuration"],
      retry_config: [type: :map, default: %{}, doc: "Retry configuration"],
      context: [type: :map, default: %{}, doc: "Request context for learning"]
    ]

  require Logger

  alias RubberDuck.LlmProviders.{ProviderRegistry, UniversalProviderService}
  alias RubberDuck.Skills.Actions.{ManageRateLimitAction, OptimizeRequestAction}

  @default_retry_config %{
    max_attempts: 3,
    base_backoff: 1000,
    max_backoff: 10_000,
    jitter: true
  }

  @default_optimization_config %{
    enable_cost_optimization: true,
    enable_context_optimization: true,
    enable_quality_monitoring: true,
    track_performance: true
  }

  @doc """
  Execute API call with provider-specific handling and optimization.
  """
  def run(params, context) do
    %{
      provider: provider,
      operation: operation,
      request_params: request_params,
      optimization_config: optimization_config,
      retry_config: retry_config,
      context: request_context
    } = params

    merged_retry_config = Map.merge(@default_retry_config, retry_config)
    merged_optimization_config = Map.merge(@default_optimization_config, optimization_config)

    Logger.info("CallAPIAction: Starting #{operation} request for provider #{provider}",
      provider: provider,
      operation: operation,
      context: request_context
    )

    with {:ok, provider_status} <- check_provider_health(provider),
         {:ok, rate_limit_status} <- manage_rate_limits(provider, operation, merged_retry_config),
         {:ok, optimized_params} <-
           optimize_request(provider, request_params, merged_optimization_config),
         {:ok, response} <-
           execute_api_call(provider, operation, optimized_params, merged_retry_config, context) do
      # Track successful request for learning
      track_request_outcome(
        provider,
        operation,
        :success,
        optimized_params,
        response,
        request_context
      )

      {:ok,
       %{
         response: response,
         provider: provider,
         operation: operation,
         optimizations_applied: optimized_params.optimizations_applied || [],
         performance_metrics: response.performance_metrics || %{},
         cost_metrics: response.cost_metrics || %{}
       }}
    else
      {:error, reason} = error ->
        Logger.error("CallAPIAction: Failed #{operation} request for provider #{provider}",
          provider: provider,
          operation: operation,
          error: reason,
          context: request_context
        )

        # Track failed request for learning
        track_request_outcome(
          provider,
          operation,
          :error,
          request_params,
          reason,
          request_context
        )

        error
    end
  end

  # Private implementation functions

  defp check_provider_health(provider) do
    case ProviderRegistry.get_provider_health(provider) do
      {:ok, %{status: :healthy}} ->
        {:ok, :healthy}

      {:ok, %{status: status}} when status in [:degraded, :recovering] ->
        Logger.warn("CallAPIAction: Provider #{provider} is #{status}, proceeding with caution")
        {:ok, status}

      {:ok, %{status: :unhealthy}} ->
        {:error, :provider_unhealthy}

      {:error, reason} ->
        {:error, {:health_check_failed, reason}}
    end
  end

  defp manage_rate_limits(provider, operation, retry_config) do
    case ManageRateLimitAction.run(
           %{
             provider: provider,
             operation: operation,
             retry_config: retry_config
           },
           %{}
         ) do
      {:ok, %{can_proceed: true}} ->
        {:ok, :proceeding}

      {:ok, %{can_proceed: false, wait_time: wait_time}} ->
        Logger.info("CallAPIAction: Rate limit reached for #{provider}, waiting #{wait_time}ms")
        Process.sleep(wait_time)
        {:ok, :waited}

      {:error, reason} ->
        {:error, {:rate_limit_error, reason}}
    end
  end

  defp optimize_request(provider, request_params, optimization_config) do
    if optimization_config.enable_cost_optimization ||
         optimization_config.enable_context_optimization do
      OptimizeRequestAction.run(
        %{
          provider: provider,
          request_params: request_params,
          optimization_config: optimization_config
        },
        %{}
      )
    else
      {:ok, request_params}
    end
  end

  defp execute_api_call(provider, operation, request_params, retry_config, context) do
    execute_with_retry(provider, operation, request_params, retry_config, context, 1)
  end

  defp execute_with_retry(provider, operation, request_params, retry_config, context, attempt) do
    Logger.debug(
      "CallAPIAction: Attempt #{attempt}/#{retry_config.max_attempts} for #{provider}.#{operation}"
    )

    case call_provider_api(provider, operation, request_params, context) do
      {:ok, response} ->
        Logger.debug("CallAPIAction: Successful #{operation} response from #{provider}")
        {:ok, response}

      {:error, reason} when attempt < retry_config.max_attempts ->
        if should_retry?(reason) do
          backoff_time = calculate_backoff(attempt, retry_config)

          Logger.info(
            "CallAPIAction: Retrying #{operation} for #{provider} in #{backoff_time}ms (attempt #{attempt + 1})"
          )

          Process.sleep(backoff_time)

          execute_with_retry(
            provider,
            operation,
            request_params,
            retry_config,
            context,
            attempt + 1
          )
        else
          {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call_provider_api(provider, operation, request_params, context) do
    case provider do
      :openai ->
        call_openai_operation(operation, request_params, context)

      :anthropic ->
        call_anthropic_operation(operation, request_params, context)

      :local ->
        call_local_operation(operation, request_params, context)

      _ ->
        {:error, {:unsupported_provider, provider}}
    end
  end

  defp call_openai_operation(operation, request_params, context) do
    case operation do
      :complete -> call_openai_complete(request_params, context)
      :stream -> call_openai_stream(request_params, context)
      :embed -> call_openai_embed(request_params, context)
      _ -> {:error, {:unsupported_operation, :openai, operation}}
    end
  end

  defp call_anthropic_operation(operation, request_params, context) do
    case operation do
      :complete -> call_anthropic_complete(request_params, context)
      :stream -> call_anthropic_stream(request_params, context)
      _ -> {:error, {:unsupported_operation, :anthropic, operation}}
    end
  end

  defp call_local_operation(operation, request_params, context) do
    case operation do
      :complete -> call_local_complete(request_params, context)
      :stream -> call_local_stream(request_params, context)
      :embed -> call_local_embed(request_params, context)
      _ -> {:error, {:unsupported_operation, :local, operation}}
    end
  end

  # OpenAI provider implementations
  defp call_openai_complete(request_params, context) do
    UniversalProviderService.complete_request(%{
      provider: :openai,
      params: request_params,
      context: context
    })
  end

  defp call_openai_stream(request_params, context) do
    UniversalProviderService.stream_request(%{
      provider: :openai,
      params: request_params,
      context: context
    })
  end

  defp call_openai_embed(request_params, context) do
    UniversalProviderService.embed_request(%{
      provider: :openai,
      params: request_params,
      context: context
    })
  end

  # Anthropic provider implementations
  defp call_anthropic_complete(request_params, context) do
    UniversalProviderService.complete_request(%{
      provider: :anthropic,
      params: request_params,
      context: context
    })
  end

  defp call_anthropic_stream(request_params, context) do
    UniversalProviderService.stream_request(%{
      provider: :anthropic,
      params: request_params,
      context: context
    })
  end

  # Local model implementations
  defp call_local_complete(request_params, context) do
    UniversalProviderService.complete_request(%{
      provider: :local,
      params: request_params,
      context: context
    })
  end

  defp call_local_stream(request_params, context) do
    UniversalProviderService.stream_request(%{
      provider: :local,
      params: request_params,
      context: context
    })
  end

  defp call_local_embed(request_params, context) do
    UniversalProviderService.embed_request(%{
      provider: :local,
      params: request_params,
      context: context
    })
  end

  # Utility functions

  defp should_retry?(reason) do
    case reason do
      {:rate_limit, _} -> true
      {:network_error, _} -> true
      {:timeout, _} -> true
      {:service_unavailable, _} -> true
      {:internal_server_error, _} -> true
      _ -> false
    end
  end

  defp calculate_backoff(attempt, retry_config) do
    base_backoff = retry_config.base_backoff
    max_backoff = retry_config.max_backoff
    jitter = retry_config.jitter

    # Exponential backoff with optional jitter
    backoff = min(base_backoff * :math.pow(2, attempt - 1), max_backoff)

    if jitter do
      jitter_amount = backoff * 0.1 * :rand.uniform()
      round(backoff + jitter_amount)
    else
      round(backoff)
    end
  end

  defp track_request_outcome(
         provider,
         operation,
         outcome,
         request_params,
         response_or_error,
         context
       ) do
    # Track request outcome for learning - this would integrate with ProviderLearning skill
    Logger.debug("CallAPIAction: Tracking #{outcome} outcome for #{provider}.#{operation}",
      provider: provider,
      operation: operation,
      outcome: outcome,
      context: context
    )

    # TODO: Integrate with ProviderLearning skill when implemented
    :ok
  end
end
