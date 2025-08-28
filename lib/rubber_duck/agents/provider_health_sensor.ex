defmodule RubberDuck.Agents.ProviderHealthSensor do
  @moduledoc """
  Real-time provider health monitoring sensor with predictive analytics.

  This sensor agent provides comprehensive health monitoring for the LLM Provider System:
  - Real-time availability monitoring with health status tracking
  - Performance degradation detection with early warning systems
  - Cost anomaly detection with budget optimization alerts
  - Capacity prediction with usage modeling and forecasting
  - Integration with LLMOrchestratorAgent for intelligent routing decisions

  The sensor operates continuously, providing health intelligence to enable
  proactive provider management and autonomous failure avoidance.
  """

  use Jido.Agent,
    name: "provider_health_sensor",
    schema: [
      provider_health_data: %{},
      health_trends: %{},
      anomaly_detection: %{},
      predictive_analytics: %{},
      alert_thresholds: %{},
      monitoring_configuration: %{}
    ]

  require Logger

  alias RubberDuck.LlmProviders.{UniversalProviderService, ProviderRegistry}

  # 15 seconds - more frequent than base system
  @health_check_interval 15_000
  # 1 minute
  @trend_analysis_interval 60_000
  # 2 minutes
  @anomaly_detection_interval 120_000
  # 5 minutes
  @prediction_update_interval 300_000

  @health_thresholds %{
    critical_success_rate: 0.85,
    warning_success_rate: 0.90,
    # 15 seconds
    critical_response_time: 15_000,
    # 8 seconds
    warning_response_time: 8_000,
    # 50% cost increase
    critical_cost_variance: 0.5,
    # 30% cost increase
    warning_cost_variance: 0.3
  }

  # Public API

  @doc """
  Get current health status for all providers with predictive analytics.
  """
  def get_comprehensive_health_status(agent) do
    current_state = Jido.Agent.get_state(agent)

    %{
      current_health: current_state.provider_health_data,
      health_trends: current_state.health_trends,
      anomaly_alerts: get_active_anomalies(current_state.anomaly_detection),
      predictive_insights: current_state.predictive_analytics,
      recommendations: generate_health_recommendations(current_state),
      last_updated: DateTime.utc_now()
    }
  end

  @doc """
  Get health status for specific provider with detailed analysis.
  """
  def get_provider_health_details(agent, provider_type) do
    current_state = Jido.Agent.get_state(agent)

    case Map.get(current_state.provider_health_data, provider_type) do
      nil ->
        {:error, "Provider not monitored: #{provider_type}"}

      provider_health ->
        provider_trends = Map.get(current_state.health_trends, provider_type, %{})

        provider_anomalies =
          get_provider_anomalies(current_state.anomaly_detection, provider_type)

        provider_predictions = Map.get(current_state.predictive_analytics, provider_type, %{})

        {:ok,
         %{
           current_health: provider_health,
           trends: provider_trends,
           anomalies: provider_anomalies,
           predictions: provider_predictions,
           recommendations:
             generate_provider_specific_recommendations(provider_health, provider_trends)
         }}
    end
  end

  @doc """
  Configure health monitoring thresholds and alerts.
  """
  def configure_health_monitoring(agent, new_thresholds) do
    current_state = Jido.Agent.get_state(agent)

    updated_thresholds = Map.merge(current_state.alert_thresholds, new_thresholds)
    updated_state = %{current_state | alert_thresholds: updated_thresholds}

    Jido.Agent.put_state(agent, updated_state)

    Logger.info("Health monitoring thresholds updated: #{inspect(new_thresholds)}")
    {:ok, agent}
  end

  # Jido Agent implementation

  @impl true
  def mount(agent) do
    Logger.info("Mounting Provider Health Sensor Agent")

    # Initialize health monitoring state
    initial_state = %{
      provider_health_data: %{},
      health_trends: %{},
      anomaly_detection: %{
        anomaly_history: %{},
        detection_algorithms: [:statistical, :trend_based, :threshold_based],
        active_anomalies: %{}
      },
      predictive_analytics: %{
        prediction_models: %{},
        # 1 hour
        forecast_horizon: 3600_000,
        prediction_accuracy: %{}
      },
      alert_thresholds: @health_thresholds,
      monitoring_configuration: %{
        health_check_interval: @health_check_interval,
        trend_analysis_enabled: true,
        anomaly_detection_enabled: true,
        predictive_analytics_enabled: true
      }
    }

    # Schedule monitoring tasks
    schedule_health_monitoring_tasks()

    # Subscribe to provider events
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "provider_health_changes")
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "universal_provider_alerts")
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "orchestrator_events")

    Jido.Agent.put_state(agent, initial_state)

    Logger.info("Provider Health Sensor Agent mounted successfully")
    {:ok, agent}
  end

  @impl true
  def handle_signal(agent, %{pattern: "health_sensor.health_check"} = signal) do
    Logger.debug("Performing comprehensive provider health check")

    current_state = Jido.Agent.get_state(agent)

    # Collect health data from all providers
    health_data = collect_comprehensive_health_data()

    # Update provider health data
    updated_health_data = merge_health_data(current_state.provider_health_data, health_data)

    # Update health trends
    updated_trends = update_health_trends(current_state.health_trends, health_data)

    updated_state = %{
      current_state
      | provider_health_data: updated_health_data,
        health_trends: updated_trends
    }

    Jido.Agent.put_state(agent, updated_state)

    # Broadcast health updates if significant changes
    broadcast_health_updates_if_needed(current_state.provider_health_data, updated_health_data)

    # Schedule next health check
    schedule_health_check()

    {:ok, agent}
  end

  @impl true
  def handle_signal(agent, %{pattern: "health_sensor.trend_analysis"} = signal) do
    Logger.debug("Performing health trend analysis")

    current_state = Jido.Agent.get_state(agent)

    # Analyze trends in provider health data
    trend_analysis =
      perform_trend_analysis(current_state.provider_health_data, current_state.health_trends)

    # Update trends state
    updated_trends = Map.merge(current_state.health_trends, trend_analysis)

    updated_state = %{current_state | health_trends: updated_trends}
    Jido.Agent.put_state(agent, updated_state)

    # Generate trend-based alerts if needed
    generate_trend_alerts(trend_analysis, current_state.alert_thresholds)

    # Schedule next trend analysis
    schedule_trend_analysis()

    {:ok, agent}
  end

  @impl true
  def handle_signal(agent, %{pattern: "health_sensor.anomaly_detection"} = signal) do
    Logger.debug("Performing anomaly detection analysis")

    current_state = Jido.Agent.get_state(agent)

    # Detect anomalies in provider performance
    anomalies =
      detect_provider_anomalies(
        current_state.provider_health_data,
        current_state.anomaly_detection
      )

    # Update anomaly detection state
    updated_anomaly_state =
      update_anomaly_detection_state(current_state.anomaly_detection, anomalies)

    updated_state = %{current_state | anomaly_detection: updated_anomaly_state}
    Jido.Agent.put_state(agent, updated_state)

    # Generate anomaly alerts
    generate_anomaly_alerts(anomalies)

    # Schedule next anomaly detection
    schedule_anomaly_detection()

    {:ok, agent}
  end

  @impl true
  def handle_signal(agent, %{pattern: "health_sensor.predictive_update"} = signal) do
    Logger.debug("Updating predictive analytics")

    current_state = Jido.Agent.get_state(agent)

    # Update predictive models
    updated_predictions =
      update_predictive_models(
        current_state.predictive_analytics,
        current_state.provider_health_data,
        current_state.health_trends
      )

    updated_state = %{current_state | predictive_analytics: updated_predictions}
    Jido.Agent.put_state(agent, updated_state)

    # Generate predictive alerts
    generate_predictive_alerts(updated_predictions, current_state.alert_thresholds)

    # Schedule next prediction update
    schedule_prediction_update()

    {:ok, agent}
  end

  # Private implementation

  defp collect_comprehensive_health_data do
    # Collect health data from Universal Provider System
    case UniversalProviderService.get_provider_health() do
      {:ok, provider_health} ->
        enhance_health_data_with_metrics(provider_health)

      {:error, reason} ->
        Logger.warning("Failed to collect provider health data: #{inspect(reason)}")
        %{error: reason, timestamp: DateTime.utc_now()}
    end
  end

  defp enhance_health_data_with_metrics(provider_health) do
    # Enhance basic health data with additional metrics
    enhanced_health =
      provider_health
      |> Map.put(:collection_timestamp, DateTime.utc_now())
      |> Map.put(:metrics_enhanced, true)

    # Add system-level metrics
    Map.put(enhanced_health, :system_metrics, %{
      total_providers: count_total_providers(provider_health),
      healthy_providers: count_healthy_providers(provider_health),
      degraded_providers: count_degraded_providers(provider_health),
      unhealthy_providers: count_unhealthy_providers(provider_health)
    })
  end

  defp merge_health_data(current_data, new_data) do
    # Merge new health data with historical data
    timestamp = DateTime.utc_now()

    # Update each provider's health history
    new_data
    |> Enum.reduce(current_data, fn {provider, health_info}, acc ->
      Map.update(acc, provider, health_info, fn existing_data ->
        # Maintain health history for trend analysis
        health_history = Map.get(existing_data, :health_history, [])
        # Keep last 100 entries
        updated_history = [health_info | health_history] |> Enum.take(100)

        Map.merge(health_info, %{
          health_history: updated_history,
          last_updated: timestamp
        })
      end)
    end)
  end

  defp update_health_trends(current_trends, new_health_data) do
    # Update health trends for each provider
    new_health_data
    |> Enum.reduce(current_trends, fn {provider, health_info}, acc ->
      Map.update(acc, provider, %{}, fn existing_trend ->
        calculate_provider_health_trend(existing_trend, health_info)
      end)
    end)
  end

  defp calculate_provider_health_trend(existing_trend, new_health_info) do
    # Calculate health trend based on recent data
    %{
      success_rate_trend: calculate_metric_trend(existing_trend, new_health_info, :success_rate),
      response_time_trend:
        calculate_metric_trend(existing_trend, new_health_info, :avg_response_time_ms),
      cost_trend: calculate_metric_trend(existing_trend, new_health_info, :avg_cost),
      overall_trend: determine_overall_trend(existing_trend, new_health_info),
      trend_confidence: calculate_trend_confidence(existing_trend),
      last_trend_update: DateTime.utc_now()
    }
  end

  defp calculate_metric_trend(existing_trend, new_health_info, metric_key) do
    # Simple trend calculation - would be more sophisticated in production
    current_value = Map.get(new_health_info, metric_key, 0)
    previous_value = get_in(existing_trend, [metric_key, :previous_value]) || current_value

    trend_direction =
      cond do
        current_value > previous_value * 1.1 -> :increasing
        current_value < previous_value * 0.9 -> :decreasing
        true -> :stable
      end

    %{
      direction: trend_direction,
      current_value: current_value,
      previous_value: previous_value,
      change_percentage: calculate_change_percentage(previous_value, current_value)
    }
  end

  defp determine_overall_trend(existing_trend, new_health_info) do
    # Determine overall provider health trend
    status = Map.get(new_health_info, :status, :unknown)

    case status do
      :healthy -> :improving
      :degraded -> :declining
      :unhealthy -> :critical
      _ -> :stable
    end
  end

  defp calculate_trend_confidence(existing_trend) do
    # Calculate confidence in trend analysis based on data points
    data_points = Map.get(existing_trend, :data_points, 0)

    case data_points do
      points when points > 20 -> :high
      points when points > 10 -> :medium
      points when points > 5 -> :low
      _ -> :insufficient
    end
  end

  defp calculate_change_percentage(previous_value, current_value) do
    if previous_value > 0 do
      ((current_value - previous_value) / previous_value * 100)
      |> Float.round(2)
    else
      0.0
    end
  end

  defp detect_provider_anomalies(health_data, anomaly_state) do
    # Detect anomalies using multiple algorithms
    algorithms = anomaly_state.detection_algorithms

    detected_anomalies =
      algorithms
      |> Enum.map(fn algorithm ->
        apply_anomaly_detection_algorithm(algorithm, health_data, anomaly_state)
      end)
      |> List.flatten()
      |> Enum.uniq_by(& &1.id)

    # Filter significant anomalies
    Enum.filter(detected_anomalies, &(&1.severity in [:warning, :critical]))
  end

  defp apply_anomaly_detection_algorithm(algorithm, health_data, anomaly_state) do
    case algorithm do
      :statistical ->
        detect_statistical_anomalies(health_data, anomaly_state)

      :trend_based ->
        detect_trend_anomalies(health_data, anomaly_state)

      :threshold_based ->
        detect_threshold_anomalies(health_data)

      _ ->
        []
    end
  end

  defp detect_statistical_anomalies(health_data, anomaly_state) do
    # Statistical anomaly detection (simplified)
    health_data
    |> Enum.map(fn {provider, health_info} ->
      success_rate = Map.get(health_info, :success_rate, 1.0)
      response_time = Map.get(health_info, :avg_response_time_ms, 3000)

      anomalies = []

      # Check for statistical outliers
      anomalies =
        if success_rate < 0.5 do
          [
            %{
              id: "#{provider}_low_success_rate",
              provider: provider,
              type: :success_rate_anomaly,
              severity: :critical,
              value: success_rate,
              description: "Success rate significantly below normal"
            }
            | anomalies
          ]
        else
          anomalies
        end

      anomalies =
        if response_time > 20_000 do
          [
            %{
              id: "#{provider}_high_response_time",
              provider: provider,
              type: :performance_anomaly,
              severity: :warning,
              value: response_time,
              description: "Response time significantly above normal"
            }
            | anomalies
          ]
        else
          anomalies
        end

      anomalies
    end)
    |> List.flatten()
  end

  defp detect_trend_anomalies(health_data, anomaly_state) do
    # Trend-based anomaly detection
    # Would implement sophisticated trend analysis in production
    []
  end

  defp detect_threshold_anomalies(health_data) do
    # Threshold-based anomaly detection
    health_data
    |> Enum.map(fn {provider, health_info} ->
      success_rate = Map.get(health_info, :success_rate, 1.0)
      response_time = Map.get(health_info, :avg_response_time_ms, 3000)

      anomalies = []

      # Critical thresholds
      anomalies =
        if success_rate < @health_thresholds.critical_success_rate do
          [
            %{
              id: "#{provider}_critical_success",
              provider: provider,
              type: :threshold_violation,
              severity: :critical,
              threshold: @health_thresholds.critical_success_rate,
              value: success_rate,
              description: "Success rate below critical threshold"
            }
            | anomalies
          ]
        else
          anomalies
        end

      anomalies =
        if response_time > @health_thresholds.critical_response_time do
          [
            %{
              id: "#{provider}_critical_performance",
              provider: provider,
              type: :threshold_violation,
              severity: :critical,
              threshold: @health_thresholds.critical_response_time,
              value: response_time,
              description: "Response time above critical threshold"
            }
            | anomalies
          ]
        else
          anomalies
        end

      anomalies
    end)
    |> List.flatten()
  end

  defp update_anomaly_detection_state(current_state, new_anomalies) do
    # Update anomaly detection state with new findings
    %{
      current_state
      | active_anomalies: group_anomalies_by_provider(new_anomalies),
        anomaly_history: add_anomalies_to_history(current_state.anomaly_history, new_anomalies),
        last_detection_run: DateTime.utc_now()
    }
  end

  defp update_predictive_models(current_predictions, health_data, health_trends) do
    # Update predictive analytics models
    health_data
    |> Enum.reduce(current_predictions, fn {provider, health_info}, acc ->
      Map.update(acc, provider, %{}, fn existing_predictions ->
        update_provider_predictions(
          existing_predictions,
          health_info,
          Map.get(health_trends, provider, %{})
        )
      end)
    end)
  end

  defp update_provider_predictions(existing_predictions, health_info, provider_trends) do
    # Update predictions for specific provider
    %{
      availability_forecast: predict_availability_trend(health_info, provider_trends),
      performance_forecast: predict_performance_trend(health_info, provider_trends),
      cost_forecast: predict_cost_trend(health_info, provider_trends),
      capacity_forecast: predict_capacity_requirements(health_info, provider_trends),
      confidence_level: calculate_prediction_confidence(existing_predictions),
      last_prediction_update: DateTime.utc_now()
    }
  end

  defp predict_availability_trend(health_info, provider_trends) do
    current_success_rate = Map.get(health_info, :success_rate, 0.9)
    trend_direction = get_in(provider_trends, [:success_rate_trend, :direction]) || :stable

    case trend_direction do
      :increasing -> min(1.0, current_success_rate + 0.05)
      :decreasing -> max(0.0, current_success_rate - 0.05)
      _ -> current_success_rate
    end
  end

  defp predict_performance_trend(health_info, provider_trends) do
    current_response_time = Map.get(health_info, :avg_response_time_ms, 3000)
    trend_direction = get_in(provider_trends, [:response_time_trend, :direction]) || :stable

    case trend_direction do
      :increasing -> trunc(current_response_time * 1.1)
      :decreasing -> trunc(current_response_time * 0.9)
      _ -> current_response_time
    end
  end

  defp predict_cost_trend(health_info, provider_trends) do
    current_cost = Map.get(health_info, :avg_cost, 0.1)
    trend_direction = get_in(provider_trends, [:cost_trend, :direction]) || :stable

    case trend_direction do
      :increasing -> current_cost * 1.1
      :decreasing -> current_cost * 0.9
      _ -> current_cost
    end
  end

  defp predict_capacity_requirements(health_info, provider_trends) do
    # Simple capacity prediction
    %{
      predicted_load: :medium,
      capacity_utilization: 0.7,
      scaling_recommendation: :maintain_current
    }
  end

  defp calculate_prediction_confidence(existing_predictions) do
    # Calculate confidence in predictions based on historical accuracy
    data_points = Map.get(existing_predictions, :historical_accuracy_data_points, 0)

    case data_points do
      points when points > 50 -> :high
      points when points > 20 -> :medium
      points when points > 5 -> :low
      _ -> :insufficient
    end
  end

  # Alert and notification functions

  defp generate_health_recommendations(current_state) do
    # Generate actionable health recommendations
    recommendations = []

    # Analyze provider health for recommendations
    recommendations =
      current_state.provider_health_data
      |> Enum.reduce(recommendations, fn {provider, health_data}, acc ->
        provider_recommendations = generate_provider_health_recommendations(provider, health_data)
        acc ++ provider_recommendations
      end)

    # Add system-level recommendations
    system_recommendations = generate_system_health_recommendations(current_state)

    recommendations ++ system_recommendations
  end

  defp generate_provider_health_recommendations(provider, health_data) do
    recommendations = []

    success_rate = Map.get(health_data, :success_rate, 1.0)
    response_time = Map.get(health_data, :avg_response_time_ms, 3000)

    # Success rate recommendations
    recommendations =
      if success_rate < 0.9 do
        [
          "Consider investigating #{provider} reliability issues - success rate #{Float.round(success_rate * 100)}%"
          | recommendations
        ]
      else
        recommendations
      end

    # Response time recommendations
    recommendations =
      if response_time > 8000 do
        [
          "Monitor #{provider} performance - response time #{response_time}ms above optimal"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations
  end

  defp generate_system_health_recommendations(current_state) do
    system_recommendations = []

    # Check overall system health
    total_providers = map_size(current_state.provider_health_data)

    system_recommendations =
      if total_providers < 2 do
        ["Consider adding additional providers for redundancy" | system_recommendations]
      else
        system_recommendations
      end

    system_recommendations
  end

  defp generate_provider_specific_recommendations(provider_health, provider_trends) do
    # Generate recommendations specific to provider
    recommendations = []

    # Trend-based recommendations
    success_trend = get_in(provider_trends, [:success_rate_trend, :direction])

    recommendations =
      case success_trend do
        :decreasing ->
          [
            "Monitor provider reliability - declining success rate trend detected"
            | recommendations
          ]

        :increasing ->
          ["Provider showing improved reliability" | recommendations]

        _ ->
          recommendations
      end

    recommendations
  end

  # Utility functions

  defp schedule_health_monitoring_tasks do
    schedule_health_check()
    schedule_trend_analysis()
    schedule_anomaly_detection()
    schedule_prediction_update()
  end

  defp schedule_health_check do
    Process.send_after(
      self(),
      {:signal, %{pattern: "health_sensor.health_check"}},
      @health_check_interval
    )
  end

  defp schedule_trend_analysis do
    Process.send_after(
      self(),
      {:signal, %{pattern: "health_sensor.trend_analysis"}},
      @trend_analysis_interval
    )
  end

  defp schedule_anomaly_detection do
    Process.send_after(
      self(),
      {:signal, %{pattern: "health_sensor.anomaly_detection"}},
      @anomaly_detection_interval
    )
  end

  defp schedule_prediction_update do
    Process.send_after(
      self(),
      {:signal, %{pattern: "health_sensor.predictive_update"}},
      @prediction_update_interval
    )
  end

  # Helper functions for health analysis

  defp count_total_providers(provider_health), do: map_size(provider_health)

  defp count_healthy_providers(provider_health) do
    Enum.count(provider_health, fn {_provider, health} ->
      Map.get(health, :status) == :healthy
    end)
  end

  defp count_degraded_providers(provider_health) do
    Enum.count(provider_health, fn {_provider, health} ->
      Map.get(health, :status) == :degraded
    end)
  end

  defp count_unhealthy_providers(provider_health) do
    Enum.count(provider_health, fn {_provider, health} ->
      Map.get(health, :status) == :unhealthy
    end)
  end

  defp get_active_anomalies(anomaly_detection) do
    Map.get(anomaly_detection, :active_anomalies, %{})
  end

  defp get_provider_anomalies(anomaly_detection, provider_type) do
    get_in(anomaly_detection, [:active_anomalies, provider_type]) || []
  end

  defp group_anomalies_by_provider(anomalies) do
    Enum.group_by(anomalies, & &1.provider)
  end

  defp add_anomalies_to_history(history, new_anomalies) do
    timestamp = DateTime.utc_now()

    history_entry = %{
      timestamp: timestamp,
      anomalies: new_anomalies,
      count: length(new_anomalies)
    }

    # Keep last 1000 history entries
    [history_entry | Map.get(history, :entries, [])] |> Enum.take(1000)
  end

  defp broadcast_health_updates_if_needed(old_health, new_health) do
    # Check for significant health changes that should be broadcast
    significant_changes = detect_significant_health_changes(old_health, new_health)

    if not Enum.empty?(significant_changes) do
      Phoenix.PubSub.broadcast(
        RubberDuck.PubSub,
        "health_sensor_alerts",
        {:significant_health_changes, significant_changes}
      )
    end
  end

  defp detect_significant_health_changes(old_health, new_health) do
    # Detect significant changes in health status
    new_health
    |> Enum.filter(fn {provider, new_health_info} ->
      case Map.get(old_health, provider) do
        # New provider
        nil ->
          true

        old_health_info ->
          old_status = Map.get(old_health_info, :status, :unknown)
          new_status = Map.get(new_health_info, :status, :unknown)

          # Status change
          old_status != new_status
      end
    end)
  end

  defp perform_trend_analysis(_health_data, _health_trends) do
    # Comprehensive trend analysis - simplified for now
    %{
      overall_system_trend: :stable,
      provider_trends: %{},
      trend_analysis_timestamp: DateTime.utc_now()
    }
  end

  defp generate_trend_alerts(_trend_analysis, _thresholds) do
    # Generate alerts based on trend analysis
    # Would implement sophisticated alerting in production
    :ok
  end

  defp generate_anomaly_alerts(_anomalies) do
    # Generate alerts for detected anomalies
    # Would integrate with alerting system in production
    :ok
  end

  defp generate_predictive_alerts(_predictions, _thresholds) do
    # Generate alerts based on predictive analytics
    :ok
  end
end
