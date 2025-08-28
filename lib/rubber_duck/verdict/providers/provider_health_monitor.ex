defmodule RubberDuck.Verdict.Providers.ProviderHealthMonitor do
  @moduledoc """
  Advanced health monitoring system for AI evaluation providers.

  This module provides comprehensive health monitoring including:
  - Real-time provider status tracking
  - Performance metrics collection and analysis
  - Automatic failover detection and recovery
  - Health-based routing decisions and alerts
  - Integration with provider registry and routing systems
  """

  use GenServer
  require Logger

  alias RubberDuck.Verdict.Providers.ProviderInterface
  alias RubberDuck.Verdict.Providers.ProviderRegistry

  # 30 seconds
  @health_check_interval 30_000
  # 1 hour performance tracking
  @performance_window_minutes 60
  @alert_thresholds %{
    success_rate_critical: 0.90,
    success_rate_warning: 0.95,
    # 10 seconds
    response_time_critical: 10_000,
    # 5 seconds
    response_time_warning: 5_000
  }

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get comprehensive health status for all providers.
  """
  def get_health_status do
    GenServer.call(__MODULE__, :get_health_status)
  end

  @doc """
  Get detailed health metrics for specific provider.
  """
  def get_provider_health(provider_type) do
    GenServer.call(__MODULE__, {:get_provider_health, provider_type})
  end

  @doc """
  Record evaluation result for health tracking.
  """
  def record_evaluation_result(provider_type, result) do
    GenServer.cast(__MODULE__, {:record_result, provider_type, result})
  end

  @doc """
  Get provider performance analytics over time.
  """
  def get_performance_analytics(provider_type, time_window \\ :last_hour) do
    GenServer.call(__MODULE__, {:get_analytics, provider_type, time_window})
  end

  @doc """
  Set custom health thresholds for provider monitoring.
  """
  def configure_health_thresholds(thresholds) do
    GenServer.cast(__MODULE__, {:configure_thresholds, thresholds})
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    # Subscribe to provider registry events
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "provider_health_changes")
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "provider_registry_events")

    # Start health monitoring cycle
    schedule_health_monitoring()

    state = %{
      health_data: %{},
      performance_history: %{},
      alert_thresholds: @alert_thresholds,
      monitoring_enabled: Keyword.get(opts, :enabled, true),
      stats: %{
        health_checks_performed: 0,
        alerts_sent: 0,
        recovery_events: 0,
        monitoring_start_time: DateTime.utc_now()
      }
    }

    Logger.info("ProviderHealthMonitor started with interval: #{@health_check_interval}ms")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_health_status, _from, state) do
    # Compile current health status with performance metrics
    health_summary =
      state.health_data
      |> Enum.map(fn {provider_type, health_info} ->
        performance_data = Map.get(state.performance_history, provider_type, %{})

        {provider_type,
         Map.merge(health_info, %{
           performance_metrics: calculate_performance_metrics(performance_data),
           last_updated: Map.get(health_info, :last_check, DateTime.utc_now())
         })}
      end)
      |> Enum.into(%{})

    {:reply, {:ok, health_summary}, state}
  end

  @impl true
  def handle_call({:get_provider_health, provider_type}, _from, state) do
    case Map.get(state.health_data, provider_type) do
      nil ->
        {:reply, {:error, :not_monitored}, state}

      health_info ->
        performance_data = Map.get(state.performance_history, provider_type, %{})

        detailed_health =
          Map.merge(health_info, %{
            performance_metrics: calculate_performance_metrics(performance_data),
            performance_history: get_recent_performance_history(performance_data),
            health_trend: calculate_health_trend(performance_data),
            recommendations: generate_health_recommendations(health_info, performance_data)
          })

        {:reply, {:ok, detailed_health}, state}
    end
  end

  @impl true
  def handle_call({:get_analytics, provider_type, time_window}, _from, state) do
    performance_data = Map.get(state.performance_history, provider_type, %{})
    analytics = calculate_analytics_for_window(performance_data, time_window)

    {:reply, {:ok, analytics}, state}
  end

  @impl true
  def handle_cast({:record_result, provider_type, result}, state) do
    # Record evaluation result for performance tracking
    timestamp = DateTime.utc_now()

    performance_entry = %{
      timestamp: timestamp,
      success: Map.get(result, :success, false),
      response_time_ms: Map.get(result, :response_time_ms, 0),
      cost_usd: Map.get(result, :cost_usd, 0.0),
      tokens_used: Map.get(result, :tokens_used, 0),
      confidence: Map.get(result, :confidence, 0.0)
    }

    # Add to performance history
    updated_history =
      state.performance_history
      |> Map.update(provider_type, [performance_entry], fn entries ->
        # Keep only recent entries within performance window
        cutoff_time = DateTime.add(timestamp, -@performance_window_minutes, :minute)

        recent_entries =
          Enum.filter(entries, &(DateTime.compare(&1.timestamp, cutoff_time) != :lt))

        # Limit memory usage
        [performance_entry | recent_entries] |> Enum.take(1000)
      end)

    # Update health data with latest performance
    updated_health_data =
      update_health_from_performance(state.health_data, provider_type, performance_entry)

    new_state = %{state | performance_history: updated_history, health_data: updated_health_data}

    # Check for health alerts
    check_and_send_health_alerts(provider_type, performance_entry, state.alert_thresholds)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:configure_thresholds, thresholds}, state) do
    Logger.info("Updating health monitoring thresholds")
    updated_thresholds = Map.merge(state.alert_thresholds, thresholds)
    {:noreply, %{state | alert_thresholds: updated_thresholds}}
  end

  @impl true
  def handle_info(:health_monitoring_cycle, state) do
    if state.monitoring_enabled do
      Logger.debug("Starting health monitoring cycle")

      # Get all registered providers and perform health checks
      case ProviderRegistry.get_providers() do
        {:ok, providers} ->
          updated_state = perform_health_checks_for_all(providers, state)
          schedule_health_monitoring()

          updated_stats =
            Map.update!(
              updated_state.stats,
              :health_checks_performed,
              &(&1 + map_size(providers))
            )

          {:noreply, %{updated_state | stats: updated_stats}}

        {:error, reason} ->
          Logger.error("Failed to get providers for health monitoring: #{inspect(reason)}")
          schedule_health_monitoring()
          {:noreply, state}
      end
    else
      schedule_health_monitoring()
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:provider_registry_changed, event_data}, state) do
    Logger.debug("Provider registry changed: #{inspect(event_data)}")

    # Initialize health monitoring for new providers
    case event_data do
      {:provider_registered, provider_type} ->
        schedule_immediate_health_check(provider_type)
        {:noreply, state}

      {:provider_unregistered, provider_type} ->
        # Clean up health data for removed provider
        updated_health_data = Map.delete(state.health_data, provider_type)
        updated_performance_history = Map.delete(state.performance_history, provider_type)

        {:noreply,
         %{
           state
           | health_data: updated_health_data,
             performance_history: updated_performance_history
         }}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # Private implementation

  defp perform_health_checks_for_all(providers, state) do
    Enum.reduce(providers, state, fn {provider_type, provider_info}, acc_state ->
      health_check_result = perform_individual_health_check(provider_info)
      update_provider_health_data(acc_state, provider_type, health_check_result)
    end)
  end

  defp perform_individual_health_check(provider_info) do
    start_time = System.monotonic_time(:millisecond)

    try do
      case provider_info.module.health_check(provider_info.state) do
        {:ok, health_data} ->
          response_time = System.monotonic_time(:millisecond) - start_time
          {:ok, Map.put(health_data, :response_time_ms, response_time)}

        {:error, reason} ->
          response_time = System.monotonic_time(:millisecond) - start_time

          {:error,
           %{
             reason: reason,
             response_time_ms: response_time,
             status: :unhealthy
           }}
      end
    rescue
      error ->
        response_time = System.monotonic_time(:millisecond) - start_time

        {:error,
         %{
           reason: Exception.message(error),
           response_time_ms: response_time,
           status: :unhealthy
         }}
    end
  end

  defp update_provider_health_data(state, provider_type, health_check_result) do
    timestamp = DateTime.utc_now()

    health_info =
      case health_check_result do
        {:ok, health_data} ->
          %{
            status: Map.get(health_data, :status, :healthy),
            last_check: timestamp,
            success_rate: Map.get(health_data, :success_rate, 1.0),
            avg_response_time_ms: Map.get(health_data, :response_time_ms, 0),
            error_count: Map.get(health_data, :error_count, 0),
            availability_percentage: Map.get(health_data, :availability_percentage, 100.0),
            consecutive_successes: increment_consecutive_successes(state, provider_type),
            consecutive_failures: 0
          }

        {:error, error_data} ->
          %{
            status: :unhealthy,
            last_check: timestamp,
            last_error: error_data.reason,
            error_response_time_ms: error_data.response_time_ms,
            consecutive_failures: increment_consecutive_failures(state, provider_type),
            consecutive_successes: 0
          }
      end

    updated_health_data = Map.put(state.health_data, provider_type, health_info)

    # Broadcast health status changes
    previous_status = get_previous_health_status(state, provider_type)

    if previous_status != health_info.status do
      broadcast_health_change(provider_type, previous_status, health_info.status)
    end

    %{state | health_data: updated_health_data}
  end

  defp calculate_performance_metrics(performance_data) when is_list(performance_data) do
    if Enum.empty?(performance_data) do
      %{
        success_rate: 0.0,
        avg_response_time_ms: 0,
        total_evaluations: 0,
        avg_cost_per_evaluation: 0.0,
        avg_confidence: 0.0
      }
    else
      successful_evaluations = Enum.count(performance_data, & &1.success)
      total_evaluations = length(performance_data)

      %{
        success_rate: successful_evaluations / total_evaluations,
        avg_response_time_ms:
          Enum.reduce(performance_data, 0, &(&1.response_time_ms + &2)) / total_evaluations,
        total_evaluations: total_evaluations,
        avg_cost_per_evaluation:
          Enum.reduce(performance_data, 0, &(&1.cost_usd + &2)) / total_evaluations,
        avg_confidence:
          Enum.reduce(performance_data, 0, &(&1.confidence + &2)) / total_evaluations,
        p95_response_time_ms: calculate_p95_response_time(performance_data),
        error_rate: (total_evaluations - successful_evaluations) / total_evaluations
      }
    end
  end

  defp calculate_performance_metrics(_), do: %{}

  defp calculate_p95_response_time(performance_data) do
    response_times = Enum.map(performance_data, & &1.response_time_ms) |> Enum.sort()
    p95_index = trunc(length(response_times) * 0.95)
    Enum.at(response_times, p95_index, 0)
  end

  defp get_recent_performance_history(performance_data) when is_list(performance_data) do
    performance_data
    # Last 10 evaluations
    |> Enum.take(10)
    |> Enum.map(fn entry ->
      %{
        timestamp: entry.timestamp,
        success: entry.success,
        response_time_ms: entry.response_time_ms,
        cost_usd: entry.cost_usd
      }
    end)
  end

  defp get_recent_performance_history(_), do: []

  defp calculate_health_trend(performance_data) when is_list(performance_data) do
    if length(performance_data) < 5 do
      :insufficient_data
    else
      # Calculate trend over recent evaluations
      recent_data = Enum.take(performance_data, 10)
      older_data = Enum.slice(performance_data, 10, 10)

      recent_success_rate = Enum.count(recent_data, & &1.success) / length(recent_data)

      older_success_rate =
        if Enum.empty?(older_data) do
          recent_success_rate
        else
          Enum.count(older_data, & &1.success) / length(older_data)
        end

      cond do
        recent_success_rate > older_success_rate + 0.05 -> :improving
        recent_success_rate < older_success_rate - 0.05 -> :degrading
        true -> :stable
      end
    end
  end

  defp calculate_health_trend(_), do: :insufficient_data

  defp generate_health_recommendations(health_info, performance_data) do
    recommendations = []

    # Check success rate
    recommendations =
      if health_info.status != :healthy do
        ["Provider showing health issues - consider using alternative provider"] ++
          recommendations
      else
        recommendations
      end

    # Check response time
    avg_response_time = Map.get(health_info, :avg_response_time_ms, 0)

    recommendations =
      if avg_response_time > @alert_thresholds.response_time_warning do
        ["Response times elevated - monitor for performance degradation"] ++ recommendations
      else
        recommendations
      end

    # Check cost efficiency
    recommendations =
      case calculate_cost_efficiency(performance_data) do
        :high_cost ->
          ["Provider costs above average - consider cost optimization"] ++ recommendations

        _ ->
          recommendations
      end

    case recommendations do
      [] -> ["Provider operating normally - no action required"]
      recs -> recs
    end
  end

  defp calculate_cost_efficiency(performance_data) when is_list(performance_data) do
    if Enum.empty?(performance_data) do
      :unknown
    else
      avg_cost = Enum.reduce(performance_data, 0, &(&1.cost_usd + &2)) / length(performance_data)

      cond do
        avg_cost > 0.5 -> :high_cost
        avg_cost > 0.2 -> :moderate_cost
        true -> :low_cost
      end
    end
  end

  defp calculate_cost_efficiency(_), do: :unknown

  defp calculate_analytics_for_window(performance_data, time_window)
       when is_list(performance_data) do
    cutoff_time =
      case time_window do
        :last_hour -> DateTime.add(DateTime.utc_now(), -1, :hour)
        :last_day -> DateTime.add(DateTime.utc_now(), -1, :day)
        :last_week -> DateTime.add(DateTime.utc_now(), -7, :day)
        _ -> DateTime.add(DateTime.utc_now(), -1, :hour)
      end

    window_data =
      Enum.filter(performance_data, &(DateTime.compare(&1.timestamp, cutoff_time) != :lt))

    if Enum.empty?(window_data) do
      %{
        time_window: time_window,
        data_points: 0,
        message: "No data available for specified time window"
      }
    else
      %{
        time_window: time_window,
        data_points: length(window_data),
        performance_metrics: calculate_performance_metrics(window_data),
        cost_analysis: analyze_cost_trends(window_data),
        reliability_analysis: analyze_reliability_trends(window_data),
        recommendations: generate_analytics_recommendations(window_data)
      }
    end
  end

  defp calculate_analytics_for_window(_, time_window) do
    %{
      time_window: time_window,
      data_points: 0,
      message: "No performance data available"
    }
  end

  defp analyze_cost_trends(performance_data) do
    costs = Enum.map(performance_data, & &1.cost_usd)

    %{
      total_cost: Enum.sum(costs),
      avg_cost_per_evaluation: Enum.sum(costs) / length(costs),
      min_cost: Enum.min(costs),
      max_cost: Enum.max(costs),
      cost_trend: calculate_cost_trend(performance_data)
    }
  end

  defp analyze_reliability_trends(performance_data) do
    successes = Enum.count(performance_data, & &1.success)

    %{
      total_requests: length(performance_data),
      successful_requests: successes,
      success_rate: successes / length(performance_data),
      avg_confidence:
        Enum.reduce(performance_data, 0, &(&1.confidence + &2)) / length(performance_data),
      reliability_trend: calculate_reliability_trend(performance_data)
    }
  end

  defp calculate_cost_trend(performance_data) do
    if length(performance_data) < 5 do
      :insufficient_data
    else
      # Simple trend calculation: compare first half to second half
      mid_point = div(length(performance_data), 2)
      first_half = Enum.take(performance_data, mid_point)
      second_half = Enum.drop(performance_data, mid_point)

      first_avg = Enum.reduce(first_half, 0, &(&1.cost_usd + &2)) / length(first_half)
      second_avg = Enum.reduce(second_half, 0, &(&1.cost_usd + &2)) / length(second_half)

      cond do
        second_avg > first_avg * 1.1 -> :increasing
        second_avg < first_avg * 0.9 -> :decreasing
        true -> :stable
      end
    end
  end

  defp calculate_reliability_trend(performance_data) do
    if length(performance_data) < 5 do
      :insufficient_data
    else
      recent_successes = Enum.take(performance_data, 5) |> Enum.count(& &1.success)
      older_successes = Enum.slice(performance_data, 5, 5) |> Enum.count(& &1.success)

      cond do
        recent_successes > older_successes -> :improving
        recent_successes < older_successes -> :degrading
        true -> :stable
      end
    end
  end

  defp generate_analytics_recommendations(performance_data) do
    recommendations = []

    # Analyze patterns and suggest optimizations
    performance_metrics = calculate_performance_metrics(performance_data)

    recommendations =
      if performance_metrics.success_rate < 0.95 do
        ["Consider provider configuration review due to low success rate"] ++ recommendations
      else
        recommendations
      end

    recommendations =
      if performance_metrics.avg_response_time_ms > 5000 do
        ["Response times elevated - check provider load and network conditions"] ++
          recommendations
      else
        recommendations
      end

    recommendations =
      if performance_metrics.avg_cost_per_evaluation > 0.3 do
        ["Costs above target - consider cost optimization strategies"] ++ recommendations
      else
        recommendations
      end

    case recommendations do
      [] -> ["Provider performance within normal parameters"]
      recs -> recs
    end
  end

  defp update_health_from_performance(health_data, provider_type, performance_entry) do
    current_health =
      Map.get(health_data, provider_type, %{
        status: :unknown,
        consecutive_successes: 0,
        consecutive_failures: 0
      })

    updated_health =
      if performance_entry.success do
        %{
          current_health
          | status: :healthy,
            consecutive_successes: current_health[:consecutive_successes] + 1,
            consecutive_failures: 0,
            last_success: DateTime.utc_now()
        }
      else
        %{
          current_health
          | status: determine_status_from_failures(current_health[:consecutive_failures] + 1),
            consecutive_failures: current_health[:consecutive_failures] + 1,
            consecutive_successes: 0,
            last_failure: DateTime.utc_now()
        }
      end

    Map.put(health_data, provider_type, updated_health)
  end

  defp determine_status_from_failures(failure_count) do
    cond do
      failure_count >= 5 -> :unhealthy
      failure_count >= 2 -> :degraded
      true -> :healthy
    end
  end

  defp check_and_send_health_alerts(provider_type, performance_entry, thresholds) do
    # Check for critical alerts
    alerts = []

    alerts =
      if performance_entry.success do
        alerts
      else
        ["Provider #{provider_type} evaluation failed"] ++ alerts
      end

    alerts =
      if performance_entry.response_time_ms > thresholds.response_time_critical do
        [
          "Provider #{provider_type} response time critical: #{performance_entry.response_time_ms}ms"
        ] ++ alerts
      else
        alerts
      end

    # Send alerts if any were triggered
    unless Enum.empty?(alerts) do
      send_health_alerts(provider_type, alerts)
    end
  end

  defp send_health_alerts(provider_type, alerts) do
    # Broadcast alerts via PubSub
    Phoenix.PubSub.broadcast(
      RubberDuck.PubSub,
      "provider_health_alerts",
      {:provider_alerts, provider_type, alerts, DateTime.utc_now()}
    )

    Logger.warning("Health alerts for #{provider_type}: #{Enum.join(alerts, "; ")}")
  end

  defp broadcast_health_change(provider_type, old_status, new_status) do
    Phoenix.PubSub.broadcast(
      RubberDuck.PubSub,
      "provider_health_changes",
      {:provider_status_changed, provider_type, old_status, new_status, DateTime.utc_now()}
    )

    Logger.info("Provider #{provider_type} status changed: #{old_status} → #{new_status}")
  end

  defp get_previous_health_status(state, provider_type) do
    case Map.get(state.health_data, provider_type) do
      nil -> :unknown
      health_info -> Map.get(health_info, :status, :unknown)
    end
  end

  defp increment_consecutive_successes(state, provider_type) do
    case get_in(state, [:health_data, provider_type, :consecutive_successes]) do
      nil -> 1
      count -> count + 1
    end
  end

  defp increment_consecutive_failures(state, provider_type) do
    case get_in(state, [:health_data, provider_type, :consecutive_failures]) do
      nil -> 1
      count -> count + 1
    end
  end

  defp schedule_health_monitoring do
    Process.send_after(self(), :health_monitoring_cycle, @health_check_interval)
  end

  defp schedule_immediate_health_check(provider_type) do
    Process.send_after(self(), {:immediate_health_check, provider_type}, 100)
  end
end
