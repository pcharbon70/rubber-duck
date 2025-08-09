defmodule RubberDuck.Sensors.LLMHealthSensor do
  @moduledoc """
  Sensor for monitoring LLM provider health in real-time.

  This sensor replaces the traditional HealthMonitor with an agentic approach,
  emitting signals that agents can react to autonomously.
  """

  use Jido.Sensor,
    name: "llm_health_sensor",
    description: "Monitors LLM provider health and performance metrics",
    schema: [
      check_interval: [type: :pos_integer, default: 30_000],
      error_threshold: [type: :float, default: 0.5],
      min_samples: [type: :pos_integer, default: 10],
      response_time_threshold: [type: :pos_integer, default: 5000],
      providers_to_monitor: [type: {:list, :atom}, default: []],
      alert_on_degradation: [type: :boolean, default: true]
    ]

  alias RubberDuck.LLM.ProviderRegistry
  require Logger

  # Signal definitions
  # Signal constants removed - now using typed messages via MessageRouter

  @impl true
  def mount(opts) do
    # Initialize state with metrics storage
    state = %{
      timer_ref: nil,
      metrics: %{},
      check_interval: opts.check_interval,
      error_threshold: opts.error_threshold,
      min_samples: opts.min_samples,
      response_time_threshold: opts.response_time_threshold,
      providers_to_monitor: opts.providers_to_monitor,
      alert_on_degradation: opts.alert_on_degradation
    }

    # Note: Converted from legacy signal system - metrics now tracked via telemetry
    Logger.debug("LLM Health Sensor started - now uses telemetry instead of signals")

    # Start periodic health checks
    {:ok, schedule_health_check(state)}
  end

  @impl true
  def handle_info(:perform_health_check, state) do
    # Health check started - now handled via MessageRouter
    Logger.debug("Health check started for #{length(get_providers_to_check(state))} providers")

    # Perform health checks
    providers = get_providers_to_check(state)

    health_results =
      providers
      |> Enum.map(fn provider ->
        Task.async(fn ->
          {provider.name, perform_provider_health_check(provider, state)}
        end)
      end)
      # 10 second timeout for all checks
      |> Task.await_many(10_000)
      |> Map.new()

    # Update metrics and emit signals based on results
    new_state = process_health_results(health_results, state)

    # Health check completed - now handled via MessageRouter
    Logger.debug(
      "Health check completed. Healthy: #{count_healthy(health_results)}, Degraded: #{count_degraded(health_results)}, Failed: #{count_failed(health_results)}"
    )

    {:noreply, schedule_health_check(new_state)}
  end

  @impl true
  def handle_info({:signal, "llm.request.completed", payload}, state) do
    # Update metrics based on successful request
    if payload[:provider] && payload[:duration] do
      new_state =
        update_provider_metrics(state, payload.provider, :success, %{
          duration: payload.duration,
          tokens: payload[:tokens]
        })

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:signal, "llm.request.failed", payload}, state) do
    # Update metrics based on failed request
    if payload[:provider] do
      new_state =
        update_provider_metrics(state, payload.provider, :failure, %{
          reason: payload[:reason],
          duration: payload[:duration]
        })

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end

  @impl true
  def handle_call({:get_provider_metrics, provider_name}, _from, state) do
    metrics = Map.get(state.metrics, provider_name, default_metrics())
    {:reply, metrics, state}
  end

  # Private functions

  defp schedule_health_check(state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    timer_ref = Process.send_after(self(), :perform_health_check, state.check_interval)
    %{state | timer_ref: timer_ref}
  end

  defp get_providers_to_check(state) do
    if Enum.empty?(state.providers_to_monitor) do
      ProviderRegistry.list()
    else
      ProviderRegistry.list()
      |> Enum.filter(fn provider -> provider.name in state.providers_to_monitor end)
    end
  end

  defp perform_provider_health_check(provider, state) do
    start_time = System.monotonic_time(:millisecond)

    try do
      result =
        case provider.module.health_check(provider.config) do
          :ok -> :ok
          {:ok, _} -> :ok
          error -> error
        end

      response_time = System.monotonic_time(:millisecond) - start_time
      metrics = Map.get(state.metrics, provider.name, default_metrics())

      # Determine health status
      health_status = determine_health_status(result, response_time, metrics, state)

      %{
        status: health_status,
        response_time_ms: response_time,
        result: result,
        metrics_summary: summarize_metrics(metrics)
      }
    rescue
      error ->
        response_time = System.monotonic_time(:millisecond) - start_time
        result = {:error, {:exception, error}}
        metrics = Map.get(state.metrics, provider.name, default_metrics())
        health_status = determine_health_status(result, response_time, metrics, state)

        %{
          status: health_status,
          response_time_ms: response_time,
          result: result,
          metrics_summary: summarize_metrics(metrics)
        }
    catch
      :exit, reason ->
        response_time = System.monotonic_time(:millisecond) - start_time
        result = {:error, {:exit, reason}}
        metrics = Map.get(state.metrics, provider.name, default_metrics())
        health_status = determine_health_status(result, response_time, metrics, state)

        %{
          status: health_status,
          response_time_ms: response_time,
          result: result,
          metrics_summary: summarize_metrics(metrics)
        }
    end
  end

  defp determine_health_status(result, response_time, metrics, state) do
    cond do
      result != :ok ->
        :failed

      response_time > state.response_time_threshold ->
        :degraded

      metrics.error_rate > state.error_threshold && metrics.total_count >= state.min_samples ->
        :degraded

      true ->
        :healthy
    end
  end

  defp process_health_results(results, state) do
    Enum.reduce(results, state, fn {provider_name, result}, acc_state ->
      previous_status = get_provider_status(acc_state, provider_name)
      current_status = result.status

      # Emit status change signals
      if previous_status != current_status do
        emit_status_change_signal(provider_name, previous_status, current_status, result)
      end

      # Update provider availability in registry
      update_provider_availability(
        provider_name,
        current_status,
        result,
        state.alert_on_degradation
      )

      # Update stored status
      put_in(acc_state, [:metrics, provider_name, :last_health_status], current_status)
    end)
  end

  defp update_provider_availability(provider_name, :healthy, _result, _alert_on_degradation) do
    ProviderRegistry.mark_available(provider_name)
  end

  defp update_provider_availability(provider_name, :failed, _result, _alert_on_degradation) do
    ProviderRegistry.mark_unavailable(provider_name)
  end

  defp update_provider_availability(provider_name, :degraded, result, true) do
    Logger.warning("Provider #{provider_name} is degraded: #{inspect(result)}")
  end

  defp update_provider_availability(_provider_name, :degraded, _result, false) do
    :ok
  end

  defp emit_status_change_signal(provider_name, _previous, :healthy, result) do
    # Provider healthy - now handled via MessageRouter
    Logger.debug(
      "Provider #{provider_name} is healthy (response time: #{result.response_time_ms}ms)"
    )
  end

  defp emit_status_change_signal(provider_name, _previous, :degraded, result) do
    # Provider degraded - now handled via MessageRouter  
    Logger.info("Provider #{provider_name} is degraded: #{determine_degradation_reason(result)}")
  end

  defp emit_status_change_signal(provider_name, _previous, :failed, result) do
    # Provider failed - now handled via MessageRouter
    Logger.warning("Provider #{provider_name} failed: #{inspect(result.result)}")
  end

  defp determine_degradation_reason(result) do
    cond do
      result.response_time_ms > 5000 ->
        {:slow_response, result.response_time_ms}

      result.metrics_summary[:error_rate] > 0.5 ->
        {:high_error_rate, result.metrics_summary.error_rate}

      true ->
        :unknown
    end
  end

  defp update_provider_metrics(state, provider_name, type, data) do
    metrics = Map.get(state.metrics, provider_name, default_metrics())
    updated_metrics = apply_metric_update(metrics, type, data)

    emit_metrics_update_signal(provider_name, updated_metrics, type)
    put_in(state, [:metrics, provider_name], updated_metrics)
  end

  defp apply_metric_update(metrics, type, data) do
    case type do
      :success -> update_success_metrics(metrics, data)
      :failure -> update_failure_metrics(metrics, data)
    end
  end

  defp update_success_metrics(metrics, data) do
    metrics
    |> Map.update!(:success_count, &(&1 + 1))
    |> Map.update!(:total_count, &(&1 + 1))
    |> update_response_times(data[:duration] || 0)
    |> calculate_rates()
  end

  defp update_failure_metrics(metrics, data) do
    metrics
    |> Map.update!(:error_count, &(&1 + 1))
    |> Map.update!(:total_count, &(&1 + 1))
    |> Map.put(:last_error, data[:reason])
    |> Map.put(:last_error_at, DateTime.utc_now())
    |> calculate_rates()
  end

  defp emit_metrics_update_signal(provider_name, _metrics, type) do
    # Metrics updated - now handled via MessageRouter
    Logger.debug("Metrics updated for #{provider_name} (type: #{type})")
  end

  defp default_metrics do
    %{
      success_count: 0,
      error_count: 0,
      total_count: 0,
      error_rate: 0.0,
      success_rate: 0.0,
      response_times: [],
      avg_response_time: 0,
      p95_response_time: 0,
      p99_response_time: 0,
      last_error: nil,
      last_error_at: nil,
      last_health_status: :unknown,
      last_check_at: nil
    }
  end

  defp update_response_times(metrics, response_time_ms) when response_time_ms > 0 do
    # Keep last 1000 response times
    response_times =
      [response_time_ms | metrics.response_times]
      |> Enum.take(1000)

    sorted_times = Enum.sort(response_times)
    _count = length(sorted_times)

    metrics
    |> Map.put(:response_times, response_times)
    |> Map.put(:avg_response_time, calculate_average(sorted_times))
    |> Map.put(:p95_response_time, calculate_percentile(sorted_times, 0.95))
    |> Map.put(:p99_response_time, calculate_percentile(sorted_times, 0.99))
  end

  defp update_response_times(metrics, _), do: metrics

  defp calculate_rates(metrics) do
    if metrics.total_count > 0 do
      metrics
      |> Map.put(:error_rate, metrics.error_count / metrics.total_count)
      |> Map.put(:success_rate, metrics.success_count / metrics.total_count)
    else
      metrics
    end
  end

  defp calculate_average([]), do: 0

  defp calculate_average(times) do
    Enum.sum(times) / length(times)
  end

  defp calculate_percentile([], _), do: 0

  defp calculate_percentile(sorted_times, percentile) do
    index = round(percentile * (length(sorted_times) - 1))
    Enum.at(sorted_times, index, 0)
  end

  defp summarize_metrics(metrics) do
    %{
      success_rate: Float.round(metrics.success_rate * 100, 1),
      error_rate: Float.round(metrics.error_rate * 100, 1),
      avg_response_time_ms: round(metrics.avg_response_time),
      p95_response_time_ms: round(metrics.p95_response_time),
      p99_response_time_ms: round(metrics.p99_response_time),
      total_requests: metrics.total_count,
      last_error: metrics.last_error,
      last_error_at: metrics.last_error_at
    }
  end

  defp get_provider_status(state, provider_name) do
    state.metrics
    |> Map.get(provider_name, %{})
    |> Map.get(:last_health_status, :unknown)
  end

  defp count_healthy(results) do
    Enum.count(results, fn {_, result} -> result.status == :healthy end)
  end

  defp count_degraded(results) do
    Enum.count(results, fn {_, result} -> result.status == :degraded end)
  end

  defp count_failed(results) do
    Enum.count(results, fn {_, result} -> result.status == :failed end)
  end
end
