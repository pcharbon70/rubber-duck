defmodule RubberDuck.Preferences.Llm.FallbackManager do
  @moduledoc """
  Manages LLM provider fallback chains and failure recovery.

  Implements intelligent fallback strategies based on user preferences,
  provider health, and request characteristics. Handles graceful degradation
  and maintains service continuity during provider failures.
  """

  require Logger

  alias RubberDuck.Preferences.Llm.ProviderConfig
  alias RubberDuck.Preferences.PreferenceResolver

  @doc """
  Get the fallback provider chain for a user/project.
  """
  @spec get_fallback_chain(user_id :: binary(), project_id :: binary() | nil) :: [atom()]
  def get_fallback_chain(user_id, project_id \\ nil) do
    config = ProviderConfig.get_complete_config(user_id, project_id)
    fallback_config = config.fallback_config

    case Map.get(fallback_config, :chain, []) do
      providers when is_list(providers) ->
        providers
        |> Enum.map(&String.to_existing_atom/1)
        |> Enum.filter(&(&1 in config.enabled_providers))

      # Fall back to enabled providers
      _ ->
        config.enabled_providers
    end
  end

  @doc """
  Determine if fallback should be triggered based on error and configuration.
  """
  @spec should_trigger_fallback?(
          user_id :: binary(),
          error :: term(),
          provider :: atom(),
          project_id :: binary() | nil
        ) :: boolean()
  def should_trigger_fallback?(user_id, error, _provider, project_id \\ nil) do
    config = ProviderConfig.get_complete_config(user_id, project_id)

    # Check if fallback is enabled
    if config.fallback_enabled do
      trigger_conditions = get_trigger_conditions(config)
      error_triggers_fallback?(error, trigger_conditions)
    else
      false
    end
  end

  @doc """
  Get the next provider in the fallback chain.
  """
  @spec get_next_provider(
          user_id :: binary(),
          current_provider :: atom(),
          failed_providers :: [atom()],
          project_id :: binary() | nil
        ) ::
          {:ok, atom()} | {:error, :no_fallback_available}
  def get_next_provider(user_id, current_provider, failed_providers \\ [], project_id \\ nil) do
    chain = get_fallback_chain(user_id, project_id)

    # Find position of current provider in chain
    current_index = Enum.find_index(chain, &(&1 == current_provider))

    if current_index do
      # Get remaining providers after current
      remaining_providers = Enum.drop(chain, current_index + 1)

      # Filter out already failed providers
      available_providers = Enum.filter(remaining_providers, &(&1 not in failed_providers))

      case available_providers do
        [next_provider | _] -> {:ok, next_provider}
        [] -> {:error, :no_fallback_available}
      end
    else
      # Current provider not in chain, use first available
      case Enum.filter(chain, &(&1 not in failed_providers)) do
        [next_provider | _] -> {:ok, next_provider}
        [] -> {:error, :no_fallback_available}
      end
    end
  end

  @doc """
  Execute fallback strategy with retry logic.
  """
  @spec execute_fallback(
          user_id :: binary(),
          request_fn :: function(),
          original_provider :: atom(),
          error :: term(),
          project_id :: binary() | nil
        ) :: {:ok, any()} | {:error, term()}
  def execute_fallback(user_id, request_fn, original_provider, original_error, project_id \\ nil) do
    if should_trigger_fallback?(user_id, original_error, original_provider, project_id) do
      execute_fallback_chain(user_id, request_fn, [original_provider], project_id)
    else
      {:error, original_error}
    end
  end

  @doc """
  Check provider health and update fallback preferences if needed.
  """
  @spec check_provider_health(
          user_id :: binary(),
          provider :: atom(),
          project_id :: binary() | nil
        ) :: :healthy | :degraded | :failed
  def check_provider_health(user_id, provider, project_id \\ nil) do
    config = ProviderConfig.get_complete_config(user_id, project_id)
    monitoring_config = config.monitoring_config

    if monitoring_config.health_check_enabled do
      perform_health_check(provider, monitoring_config.alert_thresholds)
    else
      # Assume healthy if monitoring disabled
      :healthy
    end
  end

  @doc """
  Get fallback statistics for analytics.
  """
  @spec get_fallback_statistics(user_id :: binary(), project_id :: binary() | nil) :: map()
  def get_fallback_statistics(user_id, project_id \\ nil) do
    # This would integrate with telemetry data in a real implementation
    %{
      user_id: user_id,
      project_id: project_id,
      fallback_enabled: fallback_enabled?(user_id, project_id),
      total_fallback_events: get_fallback_event_count(user_id, project_id),
      most_common_failures: get_common_failure_types(user_id, project_id),
      fallback_success_rate: get_fallback_success_rate(user_id, project_id),
      average_fallback_time: get_average_fallback_time(user_id, project_id),
      generated_at: DateTime.utc_now()
    }
  end

  # Private functions

  defp execute_fallback_chain(user_id, request_fn, failed_providers, project_id) do
    case get_next_provider(user_id, List.first(failed_providers), failed_providers, project_id) do
      {:ok, next_provider} ->
        Logger.info("Attempting fallback to provider: #{next_provider}")

        case execute_with_provider(request_fn, next_provider) do
          {:ok, result} ->
            record_fallback_success(user_id, next_provider, project_id)
            {:ok, result}

          {:error, error} ->
            record_fallback_failure(user_id, next_provider, error, project_id)

            execute_fallback_chain(
              user_id,
              request_fn,
              [next_provider | failed_providers],
              project_id
            )
        end

      {:error, :no_fallback_available} ->
        Logger.error("No fallback providers available for user #{user_id}")
        {:error, :all_providers_failed}
    end
  end

  defp execute_with_provider(request_fn, provider) do
    request_fn.(provider)
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, {:exit, reason}}
    error -> {:error, error}
  end

  defp get_trigger_conditions(config) do
    fallback_config = config.fallback_config

    Map.get(fallback_config, :trigger_conditions, %{
      "error_types" => ["timeout", "rate_limit", "server_error"],
      "consecutive_failures" => 2,
      "failure_rate_threshold" => 0.3
    })
  end

  defp error_triggers_fallback?(error, trigger_conditions) do
    error_types = Map.get(trigger_conditions, "error_types", [])

    # Simple error type checking - in production this would be more sophisticated
    error_type = classify_error(error)
    error_type in error_types
  end

  defp classify_error({:timeout, _}), do: "timeout"
  defp classify_error({:rate_limit, _}), do: "rate_limit"
  defp classify_error({:server_error, _}), do: "server_error"
  defp classify_error({:network_error, _}), do: "network_error"
  defp classify_error({:authentication_error, _}), do: "auth_error"
  defp classify_error(_), do: "unknown_error"

  defp perform_health_check(provider, alert_thresholds) do
    # Simplified health check - in production this would make actual API calls
    # or check telemetry data

    # Simulate health check based on provider
    case provider do
      :openai -> simulate_health_check(0.99, 1500, alert_thresholds)
      :anthropic -> simulate_health_check(0.98, 2000, alert_thresholds)
      :google -> simulate_health_check(0.96, 2500, alert_thresholds)
      :local -> simulate_health_check(0.95, 500, alert_thresholds)
      _ -> :failed
    end
  end

  defp simulate_health_check(availability, response_time, thresholds) do
    min_availability = Map.get(thresholds, "availability", 0.95)
    max_response_time = Map.get(thresholds, "response_time_ms", 10_000)

    cond do
      availability < min_availability -> :failed
      response_time > max_response_time -> :degraded
      true -> :healthy
    end
  end

  defp fallback_enabled?(user_id, project_id) do
    case PreferenceResolver.resolve(user_id, "llm.providers.fallback_enabled", project_id) do
      {:ok, enabled} -> enabled
      # Default to enabled
      {:error, _} -> true
    end
  end

  # Placeholder functions for telemetry integration
  defp get_fallback_event_count(_user_id, _project_id), do: 0
  defp get_common_failure_types(_user_id, _project_id), do: ["timeout", "rate_limit"]
  defp get_fallback_success_rate(_user_id, _project_id), do: 0.85
  defp get_average_fallback_time(_user_id, _project_id), do: 2500.0

  defp record_fallback_success(user_id, provider, project_id) do
    :telemetry.execute(
      [:rubber_duck, :llm, :fallback_success],
      %{count: 1},
      %{
        user_id: user_id,
        provider: provider,
        project_id: project_id,
        timestamp: DateTime.utc_now()
      }
    )
  end

  defp record_fallback_failure(user_id, provider, error, project_id) do
    :telemetry.execute(
      [:rubber_duck, :llm, :fallback_failure],
      %{count: 1},
      %{
        user_id: user_id,
        provider: provider,
        error_type: classify_error(error),
        project_id: project_id,
        timestamp: DateTime.utc_now()
      }
    )
  end
end
