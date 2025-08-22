defmodule RubberDuck.Agents.DataHealthSensor do
  @moduledoc """
  Data health sensor for performance monitoring and predictive anomaly detection.

  This sensor monitors database health, detects performance anomalies,
  predicts capacity issues, and triggers automatic scaling actions.
  """

  use Jido.Agent,
    name: "data_health_sensor",
    description: "Performance monitoring with predictive anomaly detection",
    category: "database",
    tags: ["health", "monitoring", "anomaly-detection"],
    vsn: "1.0.0",
    actions: []

  @doc """
  Create a new DataHealthSensor instance.
  """
  def create_health_sensor(monitoring_scope \\ :database) do
    with {:ok, agent} <- __MODULE__.new(),
         {:ok, agent} <-
           __MODULE__.set(agent,
             monitoring_scope: monitoring_scope,
             health_metrics: %{},
             performance_baselines: %{},
             anomaly_history: [],
             capacity_predictions: %{},
             scaling_triggers: default_scaling_triggers(),
             alert_history: [],
             last_health_check: nil
           ) do
      {:ok, agent}
    end
  end

  @doc """
  Monitor database performance and detect anomalies.
  """
  def monitor_performance(agent) do
    # Collect current performance metrics
    current_metrics = collect_performance_metrics(agent.monitoring_scope)
    
    # Compare against baselines for anomaly detection
    anomaly_analysis = detect_performance_anomalies(current_metrics, agent.performance_baselines)
    
    # Update health metrics
    health_assessment = assess_database_health(current_metrics, anomaly_analysis)
    
    # Check scaling triggers
    scaling_assessment = assess_scaling_needs(current_metrics, agent.scaling_triggers)

    health_monitoring_result = %{
      current_metrics: current_metrics,
      anomaly_analysis: anomaly_analysis,
      health_assessment: health_assessment,
      scaling_assessment: scaling_assessment,
      monitoring_timestamp: DateTime.utc_now()
    }

    # Update agent state
    health_metrics = Map.merge(agent.health_metrics, %{
      latest: health_monitoring_result,
      last_updated: DateTime.utc_now()
    })

    # Store anomaly if detected
    anomaly_history = if anomaly_analysis.anomalies_detected do
      [anomaly_analysis | agent.anomaly_history] |> Enum.take(200)
    else
      agent.anomaly_history
    end

    {:ok, updated_agent} =
      __MODULE__.set(agent,
        health_metrics: health_metrics,
        anomaly_history: anomaly_history,
        last_health_check: DateTime.utc_now()
      )

    {:ok, health_monitoring_result, updated_agent}
  end

  @doc """
  Predict capacity issues and scaling needs.
  """
  def predict_capacity_issues(agent, prediction_horizon_hours \\ 24) do
    health_metrics = agent.health_metrics
    historical_data = extract_historical_metrics(agent, prediction_horizon_hours * 2)

    capacity_prediction = %{
      prediction_horizon_hours: prediction_horizon_hours,
      cpu_utilization_forecast: predict_cpu_utilization(historical_data),
      memory_utilization_forecast: predict_memory_utilization(historical_data),
      storage_growth_forecast: predict_storage_growth(historical_data),
      connection_demand_forecast: predict_connection_demand(historical_data),
      performance_degradation_risk: assess_performance_degradation_risk(historical_data),
      recommended_actions: generate_capacity_recommendations(historical_data),
      prediction_confidence: calculate_prediction_confidence(historical_data)
    }

    # Store predictions for accuracy tracking
    capacity_predictions = Map.put(agent.capacity_predictions, DateTime.utc_now(), capacity_prediction)

    {:ok, updated_agent} =
      __MODULE__.set(agent,
        capacity_predictions: capacity_predictions,
        last_capacity_prediction: DateTime.utc_now()
      )

    {:ok, capacity_prediction, updated_agent}
  end

  @doc """
  Trigger automatic scaling based on performance metrics.
  """
  def trigger_scaling(agent, scaling_action, scaling_parameters \\ %{}) do
    current_metrics = Map.get(agent.health_metrics, :latest, %{})
    
    scaling_analysis = %{
      scaling_action: scaling_action,
      scaling_parameters: scaling_parameters,
      trigger_metrics: current_metrics,
      scaling_justification: generate_scaling_justification(scaling_action, current_metrics),
      estimated_impact: estimate_scaling_impact(scaling_action, scaling_parameters),
      rollback_plan: create_scaling_rollback_plan(scaling_action, scaling_parameters)
    }

    # Execute scaling action if auto-scaling is enabled
    auto_scaling = Map.get(scaling_parameters, :auto_execute, false)
    
    scaling_result = if auto_scaling do
      execute_scaling_action(scaling_analysis)
    else
      %{
        scaling_scheduled: true,
        auto_executed: false,
        manual_approval_required: true,
        scheduled_for: DateTime.add(DateTime.utc_now(), 3600, :second)
      }
    end

    # Track scaling for learning
    scaling_history = Map.get(agent, :scaling_history, [])
    scaling_record = Map.merge(scaling_analysis, %{
      scaling_result: scaling_result,
      scaling_timestamp: DateTime.utc_now()
    })

    updated_history = [scaling_record | scaling_history] |> Enum.take(100)

    {:ok, updated_agent} =
      __MODULE__.set(agent,
        scaling_history: updated_history,
        last_scaling: DateTime.utc_now()
      )

    {:ok, %{analysis: scaling_analysis, result: scaling_result}, updated_agent}
  end

  @doc """
  Establish performance baselines for anomaly detection.
  """
  def establish_baselines(agent, baseline_period_hours \\ 168) do
    # Collect historical metrics for baseline calculation
    historical_metrics = extract_historical_metrics(agent, baseline_period_hours)
    
    performance_baselines = %{
      cpu_baseline: calculate_cpu_baseline(historical_metrics),
      memory_baseline: calculate_memory_baseline(historical_metrics),
      io_baseline: calculate_io_baseline(historical_metrics),
      query_performance_baseline: calculate_query_baseline(historical_metrics),
      connection_baseline: calculate_connection_baseline(historical_metrics),
      baseline_period_hours: baseline_period_hours,
      baseline_established_at: DateTime.utc_now(),
      baseline_confidence: calculate_baseline_confidence(historical_metrics)
    }

    {:ok, updated_agent} =
      __MODULE__.set(agent,
        performance_baselines: performance_baselines,
        last_baseline_update: DateTime.utc_now()
      )

    {:ok, performance_baselines, updated_agent}
  end

  @doc """
  Generate comprehensive health report.
  """
  def generate_health_report(agent) do
    health_report = %{
      monitoring_scope: agent.monitoring_scope,
      current_health_status: assess_current_health_status(agent),
      recent_anomalies: get_recent_anomalies(agent),
      capacity_status: assess_capacity_status(agent),
      scaling_recommendations: get_scaling_recommendations(agent),
      baseline_quality: assess_baseline_quality(agent),
      prediction_accuracy: assess_prediction_accuracy(agent),
      alert_summary: summarize_recent_alerts(agent),
      report_generated_at: DateTime.utc_now()
    }

    {:ok, health_report}
  end

  # Private helper functions

  defp default_scaling_triggers do
    %{
      cpu_threshold: 0.8,      # 80% CPU utilization
      memory_threshold: 0.85,  # 85% memory utilization
      connection_threshold: 0.9,  # 90% connection pool utilization
      query_latency_threshold: 1000,  # 1 second average query time
      io_wait_threshold: 0.3,  # 30% IO wait time
      alert_escalation_count: 3  # 3 consecutive alerts trigger scaling
    }
  end

  defp collect_performance_metrics(monitoring_scope) do
    # TODO: Integrate with actual PostgreSQL metrics collection
    # For now, simulate comprehensive performance metrics
    %{
      cpu_utilization: :rand.uniform(),
      memory_utilization: :rand.uniform(),
      disk_utilization: :rand.uniform(),
      active_connections: :rand.uniform(50),
      max_connections: 100,
      average_query_time_ms: 50 + :rand.uniform(200),
      queries_per_second: 10 + :rand.uniform(90),
      cache_hit_ratio: 0.7 + :rand.uniform() * 0.3,
      index_hit_ratio: 0.8 + :rand.uniform() * 0.2,
      io_operations_per_second: :rand.uniform(1000),
      locks_waiting: :rand.uniform(5),
      deadlocks_per_hour: :rand.uniform(2),
      table_bloat_percentage: :rand.uniform(20),
      index_bloat_percentage: :rand.uniform(15),
      monitoring_scope: monitoring_scope,
      collection_timestamp: DateTime.utc_now()
    }
  end

  defp detect_performance_anomalies(current_metrics, baselines) do
    if map_size(baselines) == 0 do
      %{
        anomalies_detected: false,
        baseline_available: false,
        message: "No baselines available for anomaly detection"
      }
    else
      anomalies = []

      # CPU anomaly detection
      anomalies = if anomaly_detected?(:cpu, current_metrics.cpu_utilization, baselines) do
        [{:cpu_anomaly, current_metrics.cpu_utilization} | anomalies]
      else
        anomalies
      end

      # Memory anomaly detection
      anomalies = if anomaly_detected?(:memory, current_metrics.memory_utilization, baselines) do
        [{:memory_anomaly, current_metrics.memory_utilization} | anomalies]
      else
        anomalies
      end

      # Query performance anomaly detection
      anomalies = if anomaly_detected?(:query_time, current_metrics.average_query_time_ms, baselines) do
        [{:query_performance_anomaly, current_metrics.average_query_time_ms} | anomalies]
      else
        anomalies
      end

      %{
        anomalies_detected: not Enum.empty?(anomalies),
        detected_anomalies: anomalies,
        anomaly_count: length(anomalies),
        severity: assess_anomaly_severity(anomalies),
        baseline_available: true,
        detection_timestamp: DateTime.utc_now()
      }
    end
  end

  defp assess_database_health(current_metrics, anomaly_analysis) do
    health_factors = %{
      cpu_health: assess_cpu_health(current_metrics.cpu_utilization),
      memory_health: assess_memory_health(current_metrics.memory_utilization),
      connection_health: assess_connection_health(current_metrics.active_connections, current_metrics.max_connections),
      query_performance_health: assess_query_health(current_metrics.average_query_time_ms),
      cache_health: assess_cache_health(current_metrics.cache_hit_ratio),
      io_health: assess_io_health(current_metrics.io_operations_per_second)
    }

    # Calculate overall health score
    health_scores = Map.values(health_factors) |> Enum.map(&health_score_to_number/1)
    overall_score = Enum.sum(health_scores) / length(health_scores)

    # Adjust for anomalies
    anomaly_penalty = if anomaly_analysis.anomalies_detected do
      case anomaly_analysis.severity do
        :critical -> 0.4
        :high -> 0.2
        :medium -> 0.1
        _ -> 0.05
      end
    else
      0.0
    end

    final_score = max(overall_score - anomaly_penalty, 0.0)

    %{
      overall_health: categorize_health_score(final_score),
      health_score: final_score,
      health_factors: health_factors,
      anomaly_impact: anomaly_penalty,
      assessment_timestamp: DateTime.utc_now()
    }
  end

  defp assess_scaling_needs(current_metrics, scaling_triggers) do
    scaling_needs = []

    # Check CPU scaling needs
    scaling_needs = if current_metrics.cpu_utilization > scaling_triggers.cpu_threshold do
      [{:cpu_scaling, :scale_up} | scaling_needs]
    else
      scaling_needs
    end

    # Check memory scaling needs
    scaling_needs = if current_metrics.memory_utilization > scaling_triggers.memory_threshold do
      [{:memory_scaling, :scale_up} | scaling_needs]
    else
      scaling_needs
    end

    # Check connection scaling needs
    connection_utilization = current_metrics.active_connections / current_metrics.max_connections
    scaling_needs = if connection_utilization > scaling_triggers.connection_threshold do
      [{:connection_scaling, :increase_pool} | scaling_needs]
    else
      scaling_needs
    end

    # Check query performance scaling needs
    scaling_needs = if current_metrics.average_query_time_ms > scaling_triggers.query_latency_threshold do
      [{:performance_scaling, :optimize_queries} | scaling_needs]
    else
      scaling_needs
    end

    %{
      scaling_needed: not Enum.empty?(scaling_needs),
      scaling_requirements: scaling_needs,
      urgency: assess_scaling_urgency(scaling_needs, current_metrics),
      recommended_actions: recommend_scaling_actions(scaling_needs),
      assessment_timestamp: DateTime.utc_now()
    }
  end

  # Performance prediction helpers

  defp predict_cpu_utilization(historical_data) do
    cpu_values = extract_metric_values(historical_data, :cpu_utilization)
    
    if length(cpu_values) < 3 do
      %{prediction: :insufficient_data}
    else
      trend = calculate_trend(cpu_values)
      current_value = List.last(cpu_values)
      
      %{
        current_value: current_value,
        trend: trend,
        predicted_value: current_value + trend,
        confidence: calculate_trend_confidence(cpu_values)
      }
    end
  end

  defp predict_memory_utilization(historical_data) do
    memory_values = extract_metric_values(historical_data, :memory_utilization)
    
    if length(memory_values) < 3 do
      %{prediction: :insufficient_data}
    else
      trend = calculate_trend(memory_values)
      current_value = List.last(memory_values)
      
      %{
        current_value: current_value,
        trend: trend,
        predicted_value: min(current_value + trend, 1.0),
        confidence: calculate_trend_confidence(memory_values)
      }
    end
  end

  defp predict_storage_growth(historical_data) do
    storage_values = extract_metric_values(historical_data, :disk_utilization)
    
    if length(storage_values) < 5 do
      %{prediction: :insufficient_data}
    else
      growth_rate = calculate_growth_rate(storage_values)
      current_value = List.last(storage_values)
      
      %{
        current_utilization: current_value,
        growth_rate_per_hour: growth_rate,
        predicted_utilization_24h: min(current_value + (growth_rate * 24), 1.0),
        days_until_full: calculate_days_until_full(current_value, growth_rate),
        confidence: calculate_trend_confidence(storage_values)
      }
    end
  end

  defp predict_connection_demand(historical_data) do
    connection_values = extract_metric_values(historical_data, :active_connections)
    
    if length(connection_values) < 3 do
      %{prediction: :insufficient_data}
    else
      trend = calculate_trend(connection_values)
      current_value = List.last(connection_values)
      max_connections = 100  # TODO: Get from actual configuration
      
      %{
        current_connections: current_value,
        trend: trend,
        predicted_peak: current_value + trend,
        utilization_forecast: (current_value + trend) / max_connections,
        pool_exhaustion_risk: assess_pool_exhaustion_risk(current_value, trend, max_connections)
      }
    end
  end

  defp assess_performance_degradation_risk(historical_data) do
    query_times = extract_metric_values(historical_data, :average_query_time_ms)
    
    if length(query_times) < 5 do
      %{risk_level: :unknown, reason: "Insufficient data"}
    else
      performance_trend = calculate_trend(query_times)
      current_performance = List.last(query_times)
      
      degradation_rate = if current_performance > 0 do
        performance_trend / current_performance
      else
        0.0
      end

      risk_level = cond do
        degradation_rate > 0.3 -> :high
        degradation_rate > 0.1 -> :medium
        degradation_rate > 0.05 -> :low
        true -> :minimal
      end

      %{
        risk_level: risk_level,
        degradation_rate: degradation_rate,
        current_performance: current_performance,
        trend: performance_trend,
        confidence: calculate_trend_confidence(query_times)
      }
    end
  end

  defp generate_capacity_recommendations(historical_data) do
    recommendations = []

    # CPU recommendations
    cpu_forecast = predict_cpu_utilization(historical_data)
    recommendations = if Map.get(cpu_forecast, :predicted_value, 0) > 0.8 do
      ["Consider CPU scaling or optimization" | recommendations]
    else
      recommendations
    end

    # Memory recommendations
    memory_forecast = predict_memory_utilization(historical_data)
    recommendations = if Map.get(memory_forecast, :predicted_value, 0) > 0.9 do
      ["Plan memory scaling or optimization" | recommendations]
    else
      recommendations
    end

    # Storage recommendations
    storage_forecast = predict_storage_growth(historical_data)
    days_until_full = Map.get(storage_forecast, :days_until_full, 365)
    recommendations = if days_until_full < 30 do
      ["Urgent: Storage capacity will be exhausted in #{days_until_full} days" | recommendations]
    else
      recommendations
    end

    if Enum.empty?(recommendations) do
      ["System capacity is adequate for predicted workload"]
    else
      recommendations
    end
  end

  # Anomaly detection helpers

  defp anomaly_detected?(metric_type, current_value, baselines) do
    baseline = Map.get(baselines, metric_type)
    
    if baseline do
      baseline_value = Map.get(baseline, :value, current_value)
      threshold = Map.get(baseline, :threshold, 0.2)  # 20% deviation
      
      deviation = abs(current_value - baseline_value) / baseline_value
      deviation > threshold
    else
      false  # No baseline, no anomaly
    end
  end

  defp assess_anomaly_severity(anomalies) do
    if Enum.empty?(anomalies) do
      :none
    else
      severity_scores = Enum.map(anomalies, fn {anomaly_type, _value} ->
        case anomaly_type do
          :cpu_anomaly -> 0.8
          :memory_anomaly -> 0.9
          :query_performance_anomaly -> 0.7
          :connection_anomaly -> 0.6
          _ -> 0.5
        end
      end)

      max_severity = Enum.max(severity_scores)
      
      cond do
        max_severity > 0.8 -> :critical
        max_severity > 0.6 -> :high
        max_severity > 0.4 -> :medium
        true -> :low
      end
    end
  end

  # Health assessment helpers

  defp assess_cpu_health(cpu_utilization) do
    cond do
      cpu_utilization > 0.9 -> :critical
      cpu_utilization > 0.8 -> :warning
      cpu_utilization > 0.7 -> :moderate
      true -> :healthy
    end
  end

  defp assess_memory_health(memory_utilization) do
    cond do
      memory_utilization > 0.95 -> :critical
      memory_utilization > 0.85 -> :warning
      memory_utilization > 0.75 -> :moderate
      true -> :healthy
    end
  end

  defp assess_connection_health(active_connections, max_connections) do
    utilization = active_connections / max_connections
    
    cond do
      utilization > 0.95 -> :critical
      utilization > 0.85 -> :warning
      utilization > 0.7 -> :moderate
      true -> :healthy
    end
  end

  defp assess_query_health(average_query_time) do
    cond do
      average_query_time > 2000 -> :critical  # > 2 seconds
      average_query_time > 1000 -> :warning   # > 1 second
      average_query_time > 500 -> :moderate   # > 500ms
      true -> :healthy
    end
  end

  defp assess_cache_health(cache_hit_ratio) do
    cond do
      cache_hit_ratio < 0.5 -> :critical
      cache_hit_ratio < 0.7 -> :warning
      cache_hit_ratio < 0.8 -> :moderate
      true -> :healthy
    end
  end

  defp assess_io_health(io_ops_per_second) do
    cond do
      io_ops_per_second > 5000 -> :critical
      io_ops_per_second > 2000 -> :warning
      io_ops_per_second > 1000 -> :moderate
      true -> :healthy
    end
  end

  defp health_score_to_number(health_status) do
    case health_status do
      :healthy -> 1.0
      :moderate -> 0.7
      :warning -> 0.4
      :critical -> 0.1
      _ -> 0.5
    end
  end

  defp categorize_health_score(score) do
    cond do
      score > 0.8 -> :excellent
      score > 0.6 -> :good
      score > 0.4 -> :adequate
      score > 0.2 -> :concerning
      true -> :critical
    end
  end

  defp assess_scaling_urgency(scaling_needs, current_metrics) do
    if Enum.empty?(scaling_needs) do
      :none
    else
      urgency_factors = Enum.map(scaling_needs, fn {need_type, _action} ->
        case need_type do
          :cpu_scaling -> current_metrics.cpu_utilization
          :memory_scaling -> current_metrics.memory_utilization
          :connection_scaling -> current_metrics.active_connections / current_metrics.max_connections
          :performance_scaling -> min(current_metrics.average_query_time_ms / 1000.0, 1.0)
          _ -> 0.5
        end
      end)

      max_urgency = Enum.max(urgency_factors)
      
      cond do
        max_urgency > 0.95 -> :immediate
        max_urgency > 0.9 -> :urgent
        max_urgency > 0.8 -> :moderate
        true -> :low
      end
    end
  end

  defp recommend_scaling_actions(scaling_needs) do
    Enum.map(scaling_needs, fn {need_type, action} ->
      case {need_type, action} do
        {:cpu_scaling, :scale_up} ->
          %{action: :increase_cpu_resources, priority: :high, estimated_time: "15-30 minutes"}
        
        {:memory_scaling, :scale_up} ->
          %{action: :increase_memory_allocation, priority: :high, estimated_time: "10-20 minutes"}
        
        {:connection_scaling, :increase_pool} ->
          %{action: :increase_connection_pool_size, priority: :medium, estimated_time: "5-10 minutes"}
        
        {:performance_scaling, :optimize_queries} ->
          %{action: :trigger_query_optimization, priority: :medium, estimated_time: "30-60 minutes"}
        
        _ ->
          %{action: :monitor_closely, priority: :low, estimated_time: "immediate"}
      end
    end)
  end

  # Prediction calculation helpers

  defp extract_historical_metrics(agent, hours) do
    # TODO: Implement actual historical data extraction
    # For now, simulate historical metrics
    health_metrics = Map.get(agent.health_metrics, :history, [])
    
    # Generate simulated historical data if none exists
    if Enum.empty?(health_metrics) do
      simulate_historical_metrics(hours)
    else
      Enum.take(health_metrics, hours)
    end
  end

  defp simulate_historical_metrics(hours) do
    Enum.map(1..min(hours, 24), fn hour ->
      %{
        cpu_utilization: 0.3 + :rand.uniform() * 0.4,
        memory_utilization: 0.4 + :rand.uniform() * 0.3,
        disk_utilization: 0.2 + :rand.uniform() * 0.2,
        active_connections: 10 + :rand.uniform(30),
        average_query_time_ms: 50 + :rand.uniform(100),
        timestamp: DateTime.add(DateTime.utc_now(), -hour * 3600, :second)
      }
    end)
  end

  defp extract_metric_values(historical_data, metric_key) do
    Enum.map(historical_data, &Map.get(&1, metric_key, 0))
  end

  defp calculate_trend(values) do
    if length(values) < 2 do
      0.0
    else
      # Simple linear trend calculation
      n = length(values)
      indexed_values = Enum.with_index(values, 1)
      
      sum_x = n * (n + 1) / 2
      sum_y = Enum.sum(values)
      sum_xy = Enum.sum(Enum.map(indexed_values, fn {value, index} -> value * index end))
      sum_x2 = n * (n + 1) * (2 * n + 1) / 6
      
      # Linear regression slope
      if n * sum_x2 - sum_x * sum_x != 0 do
        (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x * sum_x)
      else
        0.0
      end
    end
  end

  defp calculate_growth_rate(values) do
    # Calculate percentage growth rate per hour
    if length(values) < 2 do
      0.0
    else
      first_value = List.first(values)
      last_value = List.last(values)
      hours_elapsed = length(values)
      
      if first_value > 0 and hours_elapsed > 0 do
        total_growth = (last_value - first_value) / first_value
        total_growth / hours_elapsed
      else
        0.0
      end
    end
  end

  defp calculate_days_until_full(current_utilization, growth_rate) do
    if growth_rate <= 0 do
      9999  # No growth or negative growth
    else
      remaining_capacity = 1.0 - current_utilization
      hours_until_full = remaining_capacity / growth_rate
      hours_until_full / 24.0
    end
  end

  defp calculate_prediction_confidence(historical_data) do
    if Enum.empty?(historical_data) do
      0.0
    else
      data_quality = min(length(historical_data) / 24.0, 1.0)  # Full confidence at 24+ hours
      temporal_consistency = assess_temporal_consistency(historical_data)
      
      (data_quality + temporal_consistency) / 2
    end
  end

  defp calculate_trend_confidence(values) do
    if length(values) < 5 do
      0.3
    else
      # Calculate R-squared for trend line fit
      trend = calculate_trend(values)
      mean_value = Enum.sum(values) / length(values)
      
      # Simple R-squared approximation
      predicted_values = Enum.with_index(values, 1)
      |> Enum.map(fn {_value, index} -> mean_value + trend * index end)
      
      total_variance = Enum.sum(Enum.map(values, &((&1 - mean_value) ** 2)))
      explained_variance = Enum.zip(values, predicted_values)
      |> Enum.map(fn {actual, predicted} -> (actual - predicted) ** 2 end)
      |> Enum.sum()
      
      if total_variance > 0 do
        1.0 - (explained_variance / total_variance)
      else
        1.0
      end
    end
  end

  # Baseline calculation helpers

  defp calculate_cpu_baseline(historical_metrics) do
    cpu_values = extract_metric_values(historical_metrics, :cpu_utilization)
    calculate_metric_baseline(cpu_values, :cpu)
  end

  defp calculate_memory_baseline(historical_metrics) do
    memory_values = extract_metric_values(historical_metrics, :memory_utilization)
    calculate_metric_baseline(memory_values, :memory)
  end

  defp calculate_io_baseline(historical_metrics) do
    io_values = extract_metric_values(historical_metrics, :io_operations_per_second)
    calculate_metric_baseline(io_values, :io)
  end

  defp calculate_query_baseline(historical_metrics) do
    query_values = extract_metric_values(historical_metrics, :average_query_time_ms)
    calculate_metric_baseline(query_values, :query_time)
  end

  defp calculate_connection_baseline(historical_metrics) do
    connection_values = extract_metric_values(historical_metrics, :active_connections)
    calculate_metric_baseline(connection_values, :connections)
  end

  defp calculate_metric_baseline(values, metric_type) do
    if Enum.empty?(values) do
      %{error: :no_data}
    else
      %{
        metric_type: metric_type,
        value: Enum.sum(values) / length(values),
        min_value: Enum.min(values),
        max_value: Enum.max(values),
        std_deviation: calculate_standard_deviation(values),
        threshold: determine_anomaly_threshold(metric_type),
        sample_size: length(values),
        confidence: min(length(values) / 24.0, 1.0)
      }
    end
  end

  defp calculate_baseline_confidence(historical_metrics) do
    if Enum.empty?(historical_metrics) do
      0.0
    else
      data_points = length(historical_metrics)
      temporal_span = assess_temporal_span(historical_metrics)
      
      data_confidence = min(data_points / 168.0, 1.0)  # Full confidence at 1 week of data
      temporal_confidence = min(temporal_span / 168.0, 1.0)
      
      (data_confidence + temporal_confidence) / 2
    end
  end

  # Status assessment helpers

  defp assess_current_health_status(agent) do
    latest_health = Map.get(agent.health_metrics, :latest)
    
    if latest_health do
      latest_health.health_assessment.overall_health
    else
      :unknown
    end
  end

  defp get_recent_anomalies(agent) do
    agent.anomaly_history
    |> Enum.take(10)
    |> Enum.map(fn anomaly ->
      %{
        anomaly_count: anomaly.anomaly_count,
        severity: anomaly.severity,
        timestamp: anomaly.detection_timestamp
      }
    end)
  end

  defp assess_capacity_status(agent) do
    capacity_predictions = agent.capacity_predictions
    
    if map_size(capacity_predictions) == 0 do
      :unknown
    else
      latest_prediction = capacity_predictions |> Map.values() |> List.last()
      
      # Assess capacity based on latest predictions
      cpu_risk = Map.get(latest_prediction.cpu_utilization_forecast, :predicted_value, 0.5)
      memory_risk = Map.get(latest_prediction.memory_utilization_forecast, :predicted_value, 0.5)
      
      max_risk = max(cpu_risk, memory_risk)
      
      cond do
        max_risk > 0.95 -> :critical
        max_risk > 0.85 -> :warning
        max_risk > 0.75 -> :moderate
        true -> :adequate
      end
    end
  end

  defp get_scaling_recommendations(agent) do
    scaling_history = Map.get(agent, :scaling_history, [])
    
    if Enum.empty?(scaling_history) do
      ["No scaling history available"]
    else
      recent_scaling = Enum.take(scaling_history, 5)
      
      successful_scalings = Enum.count(recent_scaling, fn scaling ->
        Map.get(scaling.scaling_result, :scaling_success, false)
      end)

      success_rate = successful_scalings / length(recent_scaling)
      
      if success_rate > 0.8 do
        ["Scaling operations are performing well"]
      else
        ["Review scaling procedures - success rate: #{round(success_rate * 100)}%"]
      end
    end
  end

  defp assess_baseline_quality(agent) do
    baselines = agent.performance_baselines
    
    if map_size(baselines) == 0 do
      :no_baselines
    else
      baseline_confidence = Map.get(baselines, :baseline_confidence, 0.0)
      
      cond do
        baseline_confidence > 0.8 -> :excellent
        baseline_confidence > 0.6 -> :good
        baseline_confidence > 0.4 -> :adequate
        true -> :poor
      end
    end
  end

  defp assess_prediction_accuracy(agent) do
    capacity_predictions = agent.capacity_predictions
    
    if map_size(capacity_predictions) < 2 do
      :insufficient_data
    else
      # TODO: Implement actual prediction accuracy assessment
      # For now, simulate moderate accuracy
      :moderate_accuracy
    end
  end

  defp summarize_recent_alerts(agent) do
    alert_history = Map.get(agent, :alert_history, [])
    recent_alerts = Enum.take(alert_history, 20)
    
    %{
      total_alerts: length(recent_alerts),
      alert_types: summarize_alert_types(recent_alerts),
      alert_frequency: calculate_alert_frequency(recent_alerts)
    }
  end

  # Utility helpers

  defp execute_scaling_action(scaling_analysis) do
    # TODO: Implement actual scaling action execution
    # For now, simulate scaling execution
    %{
      scaling_action: scaling_analysis.scaling_action,
      scaling_success: :rand.uniform() > 0.1,  # 90% success rate
      scaling_duration_ms: :rand.uniform(30_000),  # 0-30 seconds
      resources_allocated: simulate_resource_allocation(scaling_analysis.scaling_action),
      scaling_timestamp: DateTime.utc_now()
    }
  end

  defp generate_scaling_justification(scaling_action, current_metrics) do
    case scaling_action do
      :scale_up_cpu ->
        "CPU utilization at #{round(current_metrics.cpu_utilization * 100)}% requires scaling"
      
      :scale_up_memory ->
        "Memory utilization at #{round(current_metrics.memory_utilization * 100)}% requires scaling"
      
      :increase_connections ->
        "Connection pool utilization requires expansion"
      
      _ ->
        "Performance metrics indicate scaling is beneficial"
    end
  end

  defp estimate_scaling_impact(scaling_action, _scaling_parameters) do
    case scaling_action do
      :scale_up_cpu ->
        %{performance_improvement: 0.3, cost_increase: 0.5, complexity: :medium}
      
      :scale_up_memory ->
        %{performance_improvement: 0.25, cost_increase: 0.3, complexity: :low}
      
      :increase_connections ->
        %{performance_improvement: 0.15, cost_increase: 0.1, complexity: :low}
      
      _ ->
        %{performance_improvement: 0.1, cost_increase: 0.2, complexity: :medium}
    end
  end

  defp create_scaling_rollback_plan(scaling_action, _scaling_parameters) do
    %{
      rollback_action: determine_rollback_action(scaling_action),
      estimated_rollback_time: "5-15 minutes",
      data_safety: :preserved,
      rollback_triggers: ["Performance degradation", "Resource allocation failure", "Manual trigger"]
    }
  end

  defp calculate_standard_deviation(values) do
    if length(values) < 2 do
      0.0
    else
      mean = Enum.sum(values) / length(values)
      variance = Enum.sum(Enum.map(values, &((&1 - mean) ** 2))) / length(values)
      :math.sqrt(variance)
    end
  end

  defp determine_anomaly_threshold(metric_type) do
    case metric_type do
      :cpu -> 0.2      # 20% deviation for CPU
      :memory -> 0.15  # 15% deviation for memory
      :query_time -> 0.5  # 50% deviation for query time
      :connections -> 0.3  # 30% deviation for connections
      _ -> 0.25        # 25% default deviation
    end
  end

  defp assess_temporal_span(historical_metrics) do
    if length(historical_metrics) < 2 do
      0
    else
      timestamps = Enum.map(historical_metrics, &Map.get(&1, :timestamp, DateTime.utc_now()))
      earliest = Enum.min_by(timestamps, &DateTime.to_unix/1)
      latest = Enum.max_by(timestamps, &DateTime.to_unix/1)
      
      DateTime.diff(latest, earliest, :hour)
    end
  end

  defp assess_temporal_consistency(historical_data) do
    if length(historical_data) < 5 do
      0.5
    else
      # Simple consistency check based on data availability
      timestamps = Enum.map(historical_data, &Map.get(&1, :timestamp, DateTime.utc_now()))
      time_gaps = calculate_time_gaps(timestamps)
      
      # Lower variance in time gaps = higher consistency
      if Enum.empty?(time_gaps) do
        0.5
      else
        avg_gap = Enum.sum(time_gaps) / length(time_gaps)
        gap_variance = Enum.sum(Enum.map(time_gaps, &((&1 - avg_gap) ** 2))) / length(time_gaps)
        
        # Normalize variance to 0-1 scale (lower variance = higher consistency)
        max(1.0 - (gap_variance / (avg_gap ** 2)), 0.0)
      end
    end
  end

  defp assess_pool_exhaustion_risk(current_connections, trend, max_connections) do
    if trend <= 0 do
      :no_risk  # No growth or declining connections
    else
      hours_to_exhaustion = (max_connections - current_connections) / trend
      
      cond do
        hours_to_exhaustion < 1 -> :immediate
        hours_to_exhaustion < 6 -> :high
        hours_to_exhaustion < 24 -> :medium
        hours_to_exhaustion < 168 -> :low  # 1 week
        true -> :minimal
      end
    end
  end

  defp calculate_time_gaps(timestamps) do
    if length(timestamps) < 2 do
      []
    else
      sorted_timestamps = Enum.sort(timestamps, DateTime)
      
      Enum.zip(sorted_timestamps, Enum.drop(sorted_timestamps, 1))
      |> Enum.map(fn {t1, t2} -> DateTime.diff(t2, t1, :hour) end)
    end
  end

  defp simulate_resource_allocation(scaling_action) do
    case scaling_action do
      :scale_up_cpu -> %{cpu_cores: 2, cpu_allocation: "50% increase"}
      :scale_up_memory -> %{memory_gb: 4, memory_allocation: "4GB additional"}
      :increase_connections -> %{max_connections: 150, pool_increase: "50 connections"}
      _ -> %{resource_type: :unknown, allocation: "Standard scaling"}
    end
  end

  defp determine_rollback_action(scaling_action) do
    case scaling_action do
      :scale_up_cpu -> :scale_down_cpu
      :scale_up_memory -> :scale_down_memory
      :increase_connections -> :decrease_connections
      _ -> :revert_scaling
    end
  end

  defp summarize_alert_types(alerts) do
    # TODO: Implement alert type summarization
    %{performance: length(alerts), capacity: 0, anomaly: 0}
  end

  defp calculate_alert_frequency(alerts) do
    if Enum.empty?(alerts) do
      0.0
    else
      # Calculate alerts per hour
      time_span = assess_temporal_span(alerts)
      if time_span > 0, do: length(alerts) / time_span, else: 0.0
    end
  end
end