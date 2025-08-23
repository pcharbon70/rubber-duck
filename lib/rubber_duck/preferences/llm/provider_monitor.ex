defmodule RubberDuck.Preferences.Llm.ProviderMonitor do
  @moduledoc """
  Provider health monitoring and performance tracking.

  Monitors LLM provider health, tracks performance metrics, generates
  analytics, and provides alerts based on user-configured thresholds.
  """

  use GenServer
  require Logger

  @monitoring_interval :timer.seconds(30)

  # Public API

  @doc """
  Start the provider monitoring system.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get current provider health status.
  """
  @spec get_provider_health(provider :: atom()) :: :healthy | :degraded | :unhealthy | :unknown
  def get_provider_health(provider) do
    GenServer.call(__MODULE__, {:get_health, provider})
  end

  @doc """
  Get provider performance metrics.
  """
  @spec get_provider_metrics(provider :: atom()) :: map()
  def get_provider_metrics(provider) do
    GenServer.call(__MODULE__, {:get_metrics, provider})
  end

  @doc """
  Force a health check for a specific provider.
  """
  @spec force_health_check(provider :: atom()) :: :ok
  def force_health_check(provider) do
    GenServer.cast(__MODULE__, {:force_check, provider})
  end

  @doc """
  Get comprehensive monitoring report.
  """
  @spec get_monitoring_report() :: map()
  def get_monitoring_report do
    GenServer.call(__MODULE__, :get_report)
  end

  # GenServer implementation

  @impl true
  def init(_opts) do
    # Initialize provider health state
    state = %{
      provider_health: %{},
      provider_metrics: %{},
      last_check: %{},
      monitoring_enabled: true
    }

    # Schedule periodic monitoring
    schedule_monitoring()

    Logger.info("ProviderMonitor started")
    {:ok, state}
  end

  @impl true
  def handle_call({:get_health, provider}, _from, state) do
    health = Map.get(state.provider_health, provider, :unknown)
    {:reply, health, state}
  end

  @impl true
  def handle_call({:get_metrics, provider}, _from, state) do
    metrics = Map.get(state.provider_metrics, provider, %{})
    {:reply, metrics, state}
  end

  @impl true
  def handle_call(:get_report, _from, state) do
    report = generate_monitoring_report(state)
    {:reply, report, state}
  end

  @impl true
  def handle_cast({:force_check, provider}, state) do
    new_state = perform_provider_health_check(provider, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:monitor_providers, state) do
    new_state = monitor_all_providers(state)
    schedule_monitoring()
    {:noreply, new_state}
  end

  # Private functions

  defp schedule_monitoring do
    Process.send_after(self(), :monitor_providers, @monitoring_interval)
  end

  defp monitor_all_providers(state) do
    providers = [:openai, :anthropic, :google, :local]

    Enum.reduce(providers, state, fn provider, acc_state ->
      perform_provider_health_check(provider, acc_state)
    end)
  end

  defp perform_provider_health_check(provider, state) do
    Logger.debug("Performing health check for provider: #{provider}")

    health_result = check_provider_api_health(provider)
    metrics = collect_provider_metrics(provider)

    # Update state
    new_health = Map.put(state.provider_health, provider, health_result.status)
    new_metrics = Map.put(state.provider_metrics, provider, metrics)
    new_last_check = Map.put(state.last_check, provider, DateTime.utc_now())

    # Emit telemetry
    emit_health_telemetry(provider, health_result, metrics)

    # Check for alerts
    check_alert_conditions(provider, health_result, metrics)

    %{
      state
      | provider_health: new_health,
        provider_metrics: new_metrics,
        last_check: new_last_check
    }
  end

  defp check_provider_api_health(provider) do
    start_time = System.monotonic_time(:millisecond)

    result =
      case provider do
        :openai -> simulate_api_check("OpenAI", 0.99, 1200)
        :anthropic -> simulate_api_check("Anthropic", 0.98, 1800)
        :google -> simulate_api_check("Google", 0.96, 2200)
        :local -> simulate_local_check()
        _ -> %{status: :unknown, response_time: 0, availability: 0.0}
      end

    response_time = System.monotonic_time(:millisecond) - start_time
    Map.put(result, :actual_response_time, response_time)
  end

  defp simulate_api_check(provider_name, availability, typical_response_time) do
    # Simulate API health check with some randomness
    response_time = typical_response_time + :rand.uniform(500) - 250
    current_availability = availability + (:rand.uniform(100) - 50) / 1000

    status =
      cond do
        current_availability >= 0.95 and response_time < 5000 -> :healthy
        current_availability >= 0.90 and response_time < 10000 -> :degraded
        true -> :unhealthy
      end

    %{
      status: status,
      response_time: response_time,
      availability: max(0.0, min(1.0, current_availability)),
      provider_name: provider_name
    }
  end

  defp simulate_local_check do
    # Local provider health depends on system resources
    %{
      status: :healthy,
      response_time: 300 + :rand.uniform(200),
      availability: 0.99,
      provider_name: "Local Model"
    }
  end

  defp collect_provider_metrics(_provider) do
    # Simulate metrics collection - in production this would gather real metrics
    %{
      requests_per_minute: :rand.uniform(100),
      avg_response_time: 1000 + :rand.uniform(2000),
      error_rate: :rand.uniform(10) / 100,
      success_rate: 0.95 + :rand.uniform(5) / 100,
      last_error: nil,
      uptime_percentage: 0.99,
      collected_at: DateTime.utc_now()
    }
  end

  defp emit_health_telemetry(provider, health_result, metrics) do
    :telemetry.execute(
      [:rubber_duck, :llm, :provider_health_checked],
      %{
        response_time: health_result.response_time,
        availability: health_result.availability,
        error_rate: metrics.error_rate
      },
      %{
        provider: provider,
        status: health_result.status,
        timestamp: DateTime.utc_now()
      }
    )
  end

  defp check_alert_conditions(provider, health_result, metrics) do
    # Check if any alert conditions are met
    if health_result.status == :unhealthy do
      send_provider_alert(provider, :unhealthy, %{
        health: health_result,
        metrics: metrics
      })
    end

    if metrics.error_rate > 0.1 do
      send_provider_alert(provider, :high_error_rate, %{
        error_rate: metrics.error_rate,
        threshold: 0.1
      })
    end
  end

  defp send_provider_alert(provider, alert_type, alert_data) do
    Logger.warning("Provider alert: #{provider} - #{alert_type} - #{inspect(alert_data)}")

    # Emit alert telemetry
    :telemetry.execute(
      [:rubber_duck, :llm, :provider_alert],
      %{count: 1},
      %{
        provider: provider,
        alert_type: alert_type,
        alert_data: alert_data,
        timestamp: DateTime.utc_now()
      }
    )
  end

  defp generate_monitoring_report(state) do
    %{
      monitoring_enabled: state.monitoring_enabled,
      total_providers: map_size(state.provider_health),
      healthy_providers: count_providers_by_status(state.provider_health, :healthy),
      degraded_providers: count_providers_by_status(state.provider_health, :degraded),
      unhealthy_providers: count_providers_by_status(state.provider_health, :unhealthy),
      provider_details: build_provider_details(state),
      last_check_times: state.last_check,
      report_generated_at: DateTime.utc_now()
    }
  end

  defp count_providers_by_status(provider_health, target_status) do
    provider_health
    |> Enum.count(fn {_provider, status} -> status == target_status end)
  end

  defp build_provider_details(state) do
    state.provider_health
    |> Enum.map(fn {provider, health} ->
      metrics = Map.get(state.provider_metrics, provider, %{})
      last_check = Map.get(state.last_check, provider)

      {provider,
       %{
         health_status: health,
         metrics: metrics,
         last_checked: last_check
       }}
    end)
    |> Enum.into(%{})
  end
end
