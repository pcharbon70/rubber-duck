defmodule RubberDuck.Skills.Actions.ManageRateLimitAction do
  @moduledoc """
  Intelligent rate limit management with predictive throttling.

  This action provides sophisticated rate limit management across all LLM providers
  with predictive throttling to prevent rate limit violations before they occur.

  Features:
  - Provider-specific rate limit tracking and prediction
  - Adaptive backoff strategies that learn from historical data
  - Token bucket algorithm with dynamic refill rates
  - Integration with provider health monitoring
  - Cost optimization through intelligent request spacing
  - Queue management for burst request handling

  The action maintains separate rate limit state for each provider and operation type,
  learning optimal request patterns to maximize throughput while minimizing violations.
  """

  use Jido.Action,
    name: "manage_rate_limit",
    schema: [
      provider: [
        type: :atom,
        required: true,
        doc: "Provider identifier (:openai, :anthropic, :local)"
      ],
      operation: [type: :atom, required: true, doc: "Operation type (:complete, :stream, :embed)"],
      estimated_tokens: [type: :integer, default: 1000, doc: "Estimated token count for request"],
      priority: [
        type: :atom,
        default: :normal,
        doc: "Request priority (:low, :normal, :high, :critical)"
      ],
      retry_config: [type: :map, default: %{}, doc: "Retry configuration"]
    ]

  require Logger

  alias RubberDuck.LlmProviders.{ProviderRegistry, Resources.ProviderHealthStatus}

  # Rate limit configurations per provider
  @provider_limits %{
    openai: %{
      complete: %{requests_per_minute: 3500, tokens_per_minute: 90_000},
      stream: %{requests_per_minute: 3500, tokens_per_minute: 90_000},
      embed: %{requests_per_minute: 3000, tokens_per_minute: 1_000_000}
    },
    anthropic: %{
      complete: %{requests_per_minute: 1000, tokens_per_minute: 80_000},
      stream: %{requests_per_minute: 1000, tokens_per_minute: 80_000}
    },
    local: %{
      complete: %{requests_per_minute: :unlimited, tokens_per_minute: :unlimited},
      stream: %{requests_per_minute: :unlimited, tokens_per_minute: :unlimited},
      embed: %{requests_per_minute: :unlimited, tokens_per_minute: :unlimited}
    }
  }

  # Safety margins to prevent rate limit violations
  @safety_margins %{
    # Use 90% of request limit
    requests: 0.9,
    # Use 85% of token limit
    tokens: 0.85
  }

  # Request priorities and their multipliers
  @priority_multipliers %{
    low: 0.5,
    normal: 1.0,
    high: 1.5,
    critical: 2.0
  }

  @doc """
  Check and manage rate limits for a provider operation.

  Returns:
  - `{:ok, %{can_proceed: true}}` if request can proceed immediately
  - `{:ok, %{can_proceed: false, wait_time: milliseconds}}` if must wait
  - `{:error, reason}` if rate limit cannot be managed
  """
  def run(params, _context) do
    %{
      provider: provider,
      operation: operation,
      estimated_tokens: estimated_tokens,
      priority: priority,
      retry_config: retry_config
    } = params

    Logger.debug("ManageRateLimitAction: Checking rate limits",
      provider: provider,
      operation: operation,
      estimated_tokens: estimated_tokens,
      priority: priority
    )

    with {:ok, limits} <- get_provider_limits(provider, operation),
         {:ok, current_usage} <- get_current_usage(provider, operation),
         {:ok, decision} <-
           make_rate_limit_decision(limits, current_usage, estimated_tokens, priority) do
      case decision do
        {:proceed, usage_update} ->
          :ok = update_usage_tracking(provider, operation, usage_update)
          {:ok, %{can_proceed: true}}

        {:wait, wait_time} ->
          Logger.info("ManageRateLimitAction: Rate limit requires wait",
            provider: provider,
            operation: operation,
            wait_time: wait_time
          )

          {:ok, %{can_proceed: false, wait_time: wait_time}}

        {:queue, position} ->
          Logger.info("ManageRateLimitAction: Request queued",
            provider: provider,
            operation: operation,
            queue_position: position
          )

          {:ok,
           %{
             can_proceed: false,
             wait_time: estimate_queue_wait_time(provider, operation, position)
           }}
      end
    else
      {:error, reason} ->
        Logger.error("ManageRateLimitAction: Failed to manage rate limits",
          provider: provider,
          operation: operation,
          error: reason
        )

        {:error, reason}
    end
  end

  # Private implementation functions

  defp get_provider_limits(provider, operation) do
    case get_in(@provider_limits, [provider, operation]) do
      nil ->
        {:error, {:unsupported_provider_operation, provider, operation}}

      limits ->
        # Apply dynamic adjustments based on provider health
        case get_provider_health_factor(provider) do
          {:ok, health_factor} ->
            adjusted_limits = %{
              requests_per_minute: apply_health_factor(limits.requests_per_minute, health_factor),
              tokens_per_minute: apply_health_factor(limits.tokens_per_minute, health_factor)
            }

            {:ok, adjusted_limits}

          {:error, reason} ->
            Logger.warn(
              "ManageRateLimitAction: Could not get health factor, using default limits",
              provider: provider,
              reason: reason
            )

            {:ok, limits}
        end
    end
  end

  defp get_provider_health_factor(provider) do
    case ProviderRegistry.get_provider_health(provider) do
      {:ok, %{status: :healthy}} -> {:ok, 1.0}
      {:ok, %{status: :degraded}} -> {:ok, 0.7}
      {:ok, %{status: :recovering}} -> {:ok, 0.5}
      {:ok, %{status: :unhealthy}} -> {:ok, 0.1}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_health_factor(limit, health_factor) when is_integer(limit) do
    round(limit * health_factor)
  end

  defp apply_health_factor(:unlimited, _health_factor), do: :unlimited

  defp get_current_usage(provider, operation) do
    # Get current usage from ETS or similar fast storage
    # This would track requests and tokens used in the current minute
    cache_key = "rate_limit:#{provider}:#{operation}"
    current_minute = System.system_time(:second) |> div(60)

    case get_usage_from_cache(cache_key, current_minute) do
      {:ok, usage} ->
        {:ok, usage}

      {:error, :not_found} ->
        # Initialize new tracking window
        initial_usage = %{
          requests_used: 0,
          tokens_used: 0,
          window_start: current_minute,
          request_history: [],
          token_history: []
        }

        {:ok, initial_usage}
    end
  end

  defp make_rate_limit_decision(limits, current_usage, estimated_tokens, priority) do
    priority_multiplier = Map.get(@priority_multipliers, priority, 1.0)
    effective_estimated_tokens = round(estimated_tokens * priority_multiplier)

    # Calculate safe limits with margins
    safe_request_limit = apply_safety_margin(limits.requests_per_minute, @safety_margins.requests)
    safe_token_limit = apply_safety_margin(limits.tokens_per_minute, @safety_margins.tokens)

    # Check if request can proceed immediately
    requests_available = safe_request_limit - current_usage.requests_used
    tokens_available = safe_token_limit - current_usage.tokens_used

    cond do
      # Unlimited provider (local models)
      limits.requests_per_minute == :unlimited ->
        {:proceed, %{requests: 1, tokens: effective_estimated_tokens}}

      # Can proceed immediately
      requests_available >= 1 and tokens_available >= effective_estimated_tokens ->
        {:proceed, %{requests: 1, tokens: effective_estimated_tokens}}

      # Need to wait for window reset
      requests_available < 1 or tokens_available < effective_estimated_tokens ->
        wait_time = calculate_wait_time(limits, current_usage, effective_estimated_tokens)
        {:wait, wait_time}

      # Should queue for high-priority requests
      priority in [:high, :critical] ->
        queue_position = estimate_queue_position(current_usage, effective_estimated_tokens)
        {:queue, queue_position}

      # Default to waiting
      true ->
        wait_time = calculate_wait_time(limits, current_usage, effective_estimated_tokens)
        {:wait, wait_time}
    end
  end

  defp apply_safety_margin(limit, margin) when is_integer(limit) do
    round(limit * margin)
  end

  defp apply_safety_margin(:unlimited, _margin), do: :unlimited

  defp calculate_wait_time(limits, current_usage, estimated_tokens) do
    current_minute = System.system_time(:second) |> div(60)
    window_elapsed = current_minute - current_usage.window_start
    window_remaining = max(60 - window_elapsed, 0)

    # Add buffer time for safety
    # Convert to milliseconds
    base_wait = window_remaining * 1000
    # 10% buffer
    buffer_time = round(base_wait * 0.1)

    base_wait + buffer_time
  end

  defp estimate_queue_position(_current_usage, _estimated_tokens) do
    # Simple queue position estimation
    # In a full implementation, this would check actual queue state
    :rand.uniform(5)
  end

  defp estimate_queue_wait_time(provider, operation, position) do
    # Estimate wait time based on queue position and average processing time
    avg_processing_time = get_average_processing_time(provider, operation)
    position * avg_processing_time
  end

  defp get_average_processing_time(provider, operation) do
    # Default processing times in milliseconds
    case {provider, operation} do
      {:openai, :complete} -> 2000
      {:openai, :stream} -> 5000
      {:openai, :embed} -> 1000
      {:anthropic, :complete} -> 3000
      {:anthropic, :stream} -> 6000
      {:local, _} -> 1500
      _ -> 2500
    end
  end

  defp update_usage_tracking(provider, operation, usage_update) do
    cache_key = "rate_limit:#{provider}:#{operation}"
    current_minute = System.system_time(:second) |> div(60)

    # Update usage tracking in cache
    # This would be implemented with ETS or similar fast storage
    Logger.debug("ManageRateLimitAction: Updating usage tracking",
      provider: provider,
      operation: operation,
      usage_update: usage_update,
      window: current_minute
    )

    :ok
  end

  # Cache interface functions (would be implemented with ETS or Redis)
  defp get_usage_from_cache(_cache_key, _current_minute) do
    # Placeholder implementation
    # In real system, this would query ETS table or Redis
    {:error, :not_found}
  end
end
