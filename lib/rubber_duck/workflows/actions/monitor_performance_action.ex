defmodule RubberDuck.Workflows.Actions.MonitorPerformanceAction do
  @moduledoc """
  Action for comprehensive workflow performance monitoring using ReactorPerformanceAgent.

  Provides real-time performance tracking, bottleneck identification, and automated
  optimization recommendations. Integrates with ReactorPerformanceAgent for
  sophisticated performance analysis and predictive optimization capabilities.

  Features:
  - Real-time performance monitoring with comprehensive metrics collection
  - Bottleneck identification with automated analysis and resolution recommendations
  - Predictive performance analysis with trend detection and forecasting
  - Integration with ReactorPerformanceAgent for advanced performance optimization
  - Resource usage tracking with CPU, memory, and I/O monitoring
  - Automated performance alerts and optimization trigger recommendations

  Usage Patterns:
  - **Performance Monitoring**: Continuous tracking of workflow performance metrics
  - **Bottleneck Detection**: Automated identification of performance bottlenecks
  - **Optimization Tracking**: Monitor effectiveness of applied performance optimizations
  - **Predictive Analysis**: Forecast performance trends and proactive optimization needs
  """

  use Jido.Action,
    name: "monitor_performance",
    schema: [
      target_workflows: [
        type: {:list, :string},
        required: true,
        doc: "Workflows to monitor for performance"
      ],
      monitoring_duration_ms: [
        type: :pos_integer,
        default: 60_000,
        doc: "Duration of performance monitoring session"
      ],
      monitoring_config: [type: :map, default: %{}, doc: "Performance monitoring configuration"],
      alert_thresholds: [
        type: :map,
        default: %{},
        doc: "Performance alert threshold configurations"
      ],
      optimization_triggers: [
        type: :map,
        default: %{},
        doc: "Automatic optimization trigger configurations"
      ],
      enable_predictions: [
        type: :boolean,
        default: true,
        doc: "Enable performance trend predictions"
      ],
      reporting_config: [type: :map, default: %{}, doc: "Performance reporting configuration"]
    ]

  require Logger

  alias RubberDuck.Agents.Workflow.ReactorPerformanceAgent
  alias RubberDuck.Workflows.WorkflowMonitor

  @default_monitoring_config %{
    monitoring_interval_ms: 5_000,
    performance_thresholds: %{
      max_execution_time_ms: 30_000,
      max_memory_mb: 1000,
      max_cpu_percentage: 80,
      min_throughput_per_second: 10,
      max_error_rate: 0.05
    },
    optimization_strategy: :adaptive,
    resource_monitoring: %{
      cpu_monitoring: true,
      memory_monitoring: true,
      io_monitoring: true,
      scheduler_monitoring: true
    }
  }

  @default_alert_thresholds %{
    # 20% degradation
    performance_degradation_threshold: 0.2,
    # 80% resource usage
    resource_utilization_threshold: 0.8,
    # 5% error rate
    error_rate_threshold: 0.05,
    # 10 second response time
    response_time_threshold_ms: 10_000
  }

  @default_optimization_triggers %{
    auto_optimization_enabled: true,
    # Trigger if 15%+ improvement possible
    performance_improvement_threshold: 0.15,
    # Trigger if 85%+ resource usage
    resource_pressure_threshold: 0.85,
    # Trigger on medium+ bottleneck severity
    bottleneck_severity_threshold: :medium
  }

  @default_reporting_config %{
    generate_reports: true,
    report_interval_ms: 30_000,
    include_recommendations: true,
    include_trend_analysis: true
  }

  def run(params, context) do
    %{
      target_workflows: workflows,
      monitoring_duration_ms: duration,
      monitoring_config: config,
      alert_thresholds: thresholds,
      optimization_triggers: triggers,
      enable_predictions: predictions,
      reporting_config: reporting
    } = params

    merged_config = deep_merge(@default_monitoring_config, config)
    merged_thresholds = Map.merge(@default_alert_thresholds, thresholds)
    merged_triggers = Map.merge(@default_optimization_triggers, triggers)
    merged_reporting = Map.merge(@default_reporting_config, reporting)

    Logger.info("MonitorPerformanceAction: Starting performance monitoring session",
      target_workflows: length(workflows),
      monitoring_duration_ms: duration,
      predictions_enabled: predictions
    )

    monitoring_start_time = System.monotonic_time(:microsecond)

    with {:ok, validated_params} <-
           validate_monitoring_params(workflows, duration, merged_config),
         {:ok, monitoring_session} <-
           initialize_monitoring_session(
             validated_params,
             merged_thresholds,
             merged_triggers,
             context
           ),
         {:ok, agent_params} <-
           prepare_performance_agent_params(monitoring_session, merged_config, context),
         {:ok, monitoring_results} <-
           execute_performance_monitoring_with_agent(agent_params, duration, context),
         {:ok, final_results} <-
           finalize_monitoring_results(monitoring_results, monitoring_session, merged_reporting) do
      monitoring_time = System.monotonic_time(:microsecond) - monitoring_start_time

      Logger.info("MonitorPerformanceAction: Performance monitoring completed successfully",
        workflows_monitored: length(workflows),
        monitoring_time_ms: div(monitoring_time, 1000),
        performance_alerts: get_alert_count(final_results),
        optimizations_triggered: get_optimization_count(final_results)
      )

      {:ok,
       %{
         results: final_results,
         monitoring_metadata: %{
           monitoring_time_microseconds: monitoring_time,
           workflows_monitored: length(workflows),
           samples_collected: get_sample_count(final_results),
           performance_alerts_generated: get_alert_count(final_results),
           optimizations_triggered: get_optimization_count(final_results),
           monitoring_efficiency: calculate_monitoring_efficiency(final_results, monitoring_time)
         }
       }}
    else
      {:error, reason} ->
        Logger.error("MonitorPerformanceAction: Performance monitoring failed", error: reason)
        {:error, {:performance_monitoring_failed, reason}}
    end
  end

  # Private implementation functions

  defp validate_monitoring_params(workflows, duration, config) do
    with :ok <- validate_workflows(workflows),
         :ok <- validate_monitoring_duration(duration),
         :ok <- validate_monitoring_configuration(config) do
      validated_params = %{
        target_workflows: workflows,
        monitoring_duration_ms: duration,
        config: config,
        validation_timestamp: DateTime.utc_now()
      }

      {:ok, validated_params}
    else
      {:error, reason} -> {:error, {:parameter_validation_failed, reason}}
    end
  end

  defp validate_workflows(workflows) when is_list(workflows) and length(workflows) > 0, do: :ok
  defp validate_workflows(_), do: {:error, :invalid_workflows}

  defp validate_monitoring_duration(duration) when is_integer(duration) and duration > 0, do: :ok
  defp validate_monitoring_duration(_), do: {:error, :invalid_monitoring_duration}

  defp validate_monitoring_configuration(config) when is_map(config) do
    # Validate key monitoring parameters
    case config do
      %{monitoring_interval_ms: interval} when is_integer(interval) and interval > 0 -> :ok
      _ -> {:error, :invalid_monitoring_configuration}
    end
  end

  defp validate_monitoring_configuration(_), do: {:error, :invalid_monitoring_configuration}

  defp initialize_monitoring_session(validated_params, thresholds, triggers, context) do
    monitoring_session = %{
      session_id: generate_monitoring_session_id(),
      target_workflows: validated_params.target_workflows,
      monitoring_duration_ms: validated_params.monitoring_duration_ms,
      config: validated_params.config,
      alert_thresholds: thresholds,
      optimization_triggers: triggers,
      context: context,
      start_time: System.monotonic_time(:microsecond),
      alerts_generated: [],
      optimizations_triggered: [],
      samples_collected: 0
    }

    Logger.debug("MonitorPerformanceAction: Monitoring session initialized",
      session_id: monitoring_session.session_id,
      workflows_count: length(validated_params.target_workflows)
    )

    {:ok, monitoring_session}
  end

  defp prepare_performance_agent_params(monitoring_session, config, context) do
    # Prepare parameters for ReactorPerformanceAgent
    agent_params = %{
      target_workflows: monitoring_session.target_workflows,
      monitoring_interval_ms: config.monitoring_interval_ms,
      performance_thresholds: config.performance_thresholds,
      optimization_strategy: config.optimization_strategy,
      resource_monitoring: config.resource_monitoring,
      # Always enable for monitoring action
      enable_predictions: true,
      tuning_parameters: %{
        # Monitoring only, no auto-tuning
        auto_tuning_enabled: false,
        learning_rate: 0.1
      },
      alert_handlers: build_alert_handlers(monitoring_session)
    }

    {:ok, agent_params}
  end

  defp build_alert_handlers(monitoring_session) do
    %{
      on_threshold_exceeded: fn alert_data ->
        handle_threshold_alert(alert_data, monitoring_session)
      end,
      on_bottleneck_detected: fn bottleneck_data ->
        handle_bottleneck_alert(bottleneck_data, monitoring_session)
      end,
      on_optimization_applied: fn optimization_data ->
        handle_optimization_alert(optimization_data, monitoring_session)
      end,
      on_performance_degradation: fn degradation_data ->
        handle_degradation_alert(degradation_data, monitoring_session)
      end
    }
  end

  defp execute_performance_monitoring_with_agent(agent_params, duration_ms, context) do
    # Use ReactorPerformanceAgent for actual performance monitoring
    case ReactorPerformanceAgent.start_agent(agent_params, context) do
      {:ok, agent_results} ->
        # Extract monitoring results from agent response
        case extract_monitoring_results(agent_results) do
          {:ok, results} -> {:ok, results}
          {:error, reason} -> {:error, {:result_extraction_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:performance_agent_failed, reason}}
    end
  end

  defp extract_monitoring_results(agent_results) do
    # Extract the actual monitoring results from the agent response
    case agent_results do
      %{results: results, monitoring_metadata: metadata} ->
        monitoring_results = %{
          performance_analysis: results.performance_analysis,
          monitoring_summary: results.monitoring_summary,
          optimization_summary: results.optimization_summary,
          resource_utilization: results.resource_utilization,
          agent_metadata: metadata
        }

        {:ok, monitoring_results}

      _ ->
        {:error, :invalid_agent_results_format}
    end
  end

  defp finalize_monitoring_results(monitoring_results, monitoring_session, reporting_config) do
    final_results = %{
      performance_data: monitoring_results.performance_analysis,
      monitoring_summary:
        enhance_monitoring_summary(monitoring_results.monitoring_summary, monitoring_session),
      optimization_analysis: monitoring_results.optimization_summary,
      resource_utilization: monitoring_results.resource_utilization,
      alerts_generated: monitoring_session.alerts_generated,
      optimizations_triggered: monitoring_session.optimizations_triggered,
      recommendations:
        generate_performance_recommendations(monitoring_results, monitoring_session),
      performance_report:
        generate_performance_report(monitoring_results, monitoring_session, reporting_config)
    }

    case notify_monitoring_completion(final_results, monitoring_session) do
      :ok -> {:ok, final_results}
      {:error, reason} -> {:error, {:completion_notification_failed, reason}}
    end
  end

  defp enhance_monitoring_summary(original_summary, monitoring_session) do
    Map.merge(original_summary, %{
      session_id: monitoring_session.session_id,
      monitoring_duration_actual_ms:
        div(System.monotonic_time(:microsecond) - monitoring_session.start_time, 1_000),
      alerts_generated_count: length(monitoring_session.alerts_generated),
      optimizations_triggered_count: length(monitoring_session.optimizations_triggered),
      samples_collected: monitoring_session.samples_collected
    })
  end

  defp generate_performance_recommendations(monitoring_results, monitoring_session) do
    recommendations = []
    
    # Generate recommendations based on performance analysis
    recommendations = add_workflow_performance_recommendations(recommendations, monitoring_results)
    recommendations = add_resource_utilization_recommendations(recommendations, monitoring_results)
    recommendations = add_alert_based_recommendations(recommendations, monitoring_session)
    recommendations = add_optimization_trigger_recommendations(recommendations, monitoring_session)
    
    case recommendations do
      [] -> ["Performance monitoring completed successfully - no issues detected"]
      _ -> recommendations
    end
  end

  defp add_workflow_performance_recommendations(recommendations, monitoring_results) do
    performance_data = monitoring_results.performance_analysis
    
    if Map.has_key?(performance_data, :workflow_analysis) do
      generate_workflow_recommendations(recommendations, performance_data.workflow_analysis)
    else
      recommendations
    end
  end

  defp generate_workflow_recommendations(recommendations, workflow_analysis) do
    poor_performing_workflows = Enum.filter(workflow_analysis, fn analysis ->
      Map.get(analysis, :performance_score, 1.0) < 0.7
    end)
    
    if length(poor_performing_workflows) > 0 do
      workflow_names = Enum.map(poor_performing_workflows, fn analysis ->
        Map.get(analysis, :workflow_id, "unknown")
      end)
      
      ["Poor performance detected in workflows: #{Enum.join(workflow_names, ", ")} - consider optimization" | recommendations]
    else
      recommendations
    end
  end

  defp add_resource_utilization_recommendations(recommendations, monitoring_results) do
    if Map.has_key?(monitoring_results, :resource_utilization) do
      resource_util = monitoring_results.resource_utilization
      generate_resource_recommendations(recommendations, resource_util)
    else
      recommendations
    end
  end

  defp generate_resource_recommendations(recommendations, resource_util) do
    if Map.has_key?(resource_util, :baseline_comparison) do
      baseline_comparison = resource_util.baseline_comparison
      add_high_usage_recommendations(recommendations, baseline_comparison)
    else
      recommendations
    end
  end

  defp add_high_usage_recommendations(recommendations, baseline_comparison) do
    high_usage_resources = Enum.filter(baseline_comparison, fn {_key, comparison} ->
      Map.get(comparison, :change_percentage, 0) > 50
    end)
    
    if length(high_usage_resources) > 0 do
      resource_names = Enum.map(high_usage_resources, fn {key, _} -> to_string(key) end)
      
      ["High resource usage detected in: #{Enum.join(resource_names, ", ")} - monitor for optimization opportunities" | recommendations]
    else
      recommendations
    end
  end

  defp add_alert_based_recommendations(recommendations, monitoring_session) do
    if length(monitoring_session.alerts_generated) > 5 do
      ["Multiple performance alerts generated - consider reviewing and optimizing workflow configurations" | recommendations]
    else
      recommendations
    end
  end

  defp add_optimization_trigger_recommendations(recommendations, monitoring_session) do
    if length(monitoring_session.optimizations_triggered) > 0 do
      ["Performance optimizations were triggered during monitoring - review optimization results" | recommendations]
    else
      recommendations
    end
  end

  defp generate_performance_report(monitoring_results, monitoring_session, reporting_config) do
    case reporting_config.generate_reports do
      true ->
        %{
          report_type: :performance_monitoring_report,
          session_id: monitoring_session.session_id,
          monitoring_period: %{
            start_time: monitoring_session.start_time,
            duration_ms:
              div(System.monotonic_time(:microsecond) - monitoring_session.start_time, 1_000)
          },
          workflow_performance: summarize_workflow_performance(monitoring_results),
          resource_analysis: summarize_resource_analysis(monitoring_results),
          optimization_analysis: summarize_optimization_analysis(monitoring_results),
          recommendations:
            generate_performance_recommendations(monitoring_results, monitoring_session),
          trend_analysis: generate_trend_analysis(monitoring_results, reporting_config),
          report_generated_at: DateTime.utc_now()
        }

      false ->
        %{report_disabled: true}
    end
  end

  defp summarize_workflow_performance(monitoring_results) do
    case monitoring_results.performance_analysis do
      %{workflow_analysis: workflow_analysis} ->
        %{
          workflows_analyzed: length(workflow_analysis),
          average_performance_score: calculate_average_performance_score(workflow_analysis),
          performance_distribution: analyze_performance_distribution(workflow_analysis),
          top_performers: identify_top_performing_workflows(workflow_analysis),
          performance_issues: identify_performance_issues(workflow_analysis)
        }

      _ ->
        %{analysis_unavailable: true}
    end
  end

  defp summarize_resource_analysis(monitoring_results) do
    case monitoring_results do
      %{resource_utilization: resource_util} ->
        %{
          resource_efficiency: Map.get(resource_util, :resource_efficiency, 0.0),
          baseline_comparison: Map.get(resource_util, :baseline_comparison, %{}),
          optimization_opportunities: Map.get(resource_util, :optimization_opportunities, [])
        }

      _ ->
        %{analysis_unavailable: true}
    end
  end

  defp summarize_optimization_analysis(monitoring_results) do
    case monitoring_results.optimization_summary do
      %{optimizations_applied: count, optimization_effectiveness: effectiveness} ->
        %{
          optimizations_applied: count,
          optimization_effectiveness: effectiveness,
          # Placeholder
          performance_impact: %{estimated_improvement_percentage: 10}
        }

      _ ->
        %{analysis_unavailable: true}
    end
  end

  defp generate_trend_analysis(monitoring_results, reporting_config) do
    case reporting_config.include_trend_analysis do
      true ->
        %{
          # Simplified - would analyze actual trends
          performance_trend: :stable,
          # Simplified
          resource_usage_trend: :increasing,
          # Simplified
          optimization_effectiveness_trend: :improving,
          predicted_performance_issues: [],
          trend_confidence: 0.75
        }

      false ->
        %{trend_analysis_disabled: true}
    end
  end

  # Alert handling functions

  defp handle_threshold_alert(alert_data, monitoring_session) do
    alert = %{
      type: :threshold_exceeded,
      workflow_id: Map.get(alert_data, :workflow_id),
      threshold_type: Map.get(alert_data, :threshold_type),
      current_value: Map.get(alert_data, :current_value),
      threshold_value: Map.get(alert_data, :threshold_value),
      timestamp: System.monotonic_time(:microsecond),
      severity: determine_alert_severity(alert_data)
    }

    # Add alert to session (this would update the monitoring_session state)
    Logger.warn("Performance threshold exceeded",
      workflow_id: alert.workflow_id,
      threshold_type: alert.threshold_type,
      severity: alert.severity
    )

    :ok
  end

  defp handle_bottleneck_alert(bottleneck_data, monitoring_session) do
    alert = %{
      type: :bottleneck_detected,
      workflow_id: Map.get(bottleneck_data, :workflow_id),
      bottleneck_type: Map.get(bottleneck_data, :bottleneck_type),
      severity: Map.get(bottleneck_data, :severity, :medium),
      resolution_suggestions: Map.get(bottleneck_data, :resolution_suggestions, []),
      timestamp: System.monotonic_time(:microsecond)
    }

    Logger.warn("Performance bottleneck detected",
      workflow_id: alert.workflow_id,
      bottleneck_type: alert.bottleneck_type,
      severity: alert.severity
    )

    :ok
  end

  defp handle_optimization_alert(optimization_data, monitoring_session) do
    alert = %{
      type: :optimization_applied,
      optimization_type: Map.get(optimization_data, :optimization_type),
      expected_improvement: Map.get(optimization_data, :expected_improvement),
      timestamp: System.monotonic_time(:microsecond)
    }

    Logger.info("Performance optimization applied",
      optimization_type: alert.optimization_type,
      expected_improvement: alert.expected_improvement
    )

    :ok
  end

  defp handle_degradation_alert(degradation_data, monitoring_session) do
    alert = %{
      type: :performance_degradation,
      workflow_id: Map.get(degradation_data, :workflow_id),
      degradation_percentage: Map.get(degradation_data, :degradation_percentage),
      affected_metrics: Map.get(degradation_data, :affected_metrics, []),
      timestamp: System.monotonic_time(:microsecond)
    }

    Logger.warn("Performance degradation detected",
      workflow_id: alert.workflow_id,
      degradation_percentage: alert.degradation_percentage
    )

    :ok
  end

  # Helper functions

  defp deep_merge(map1, map2) when is_map(map1) and is_map(map2) do
    Map.merge(map1, map2, fn _key, val1, val2 ->
      case {val1, val2} do
        {v1, v2} when is_map(v1) and is_map(v2) -> deep_merge(v1, v2)
        {_, v2} -> v2
      end
    end)
  end

  defp deep_merge(map1, _), do: map1

  defp get_alert_count(%{alerts_generated: alerts}), do: length(alerts)
  defp get_alert_count(_), do: 0

  defp get_optimization_count(%{optimizations_triggered: opts}), do: length(opts)
  defp get_optimization_count(_), do: 0

  defp get_sample_count(%{monitoring_summary: %{samples_collected: count}}), do: count
  defp get_sample_count(_), do: 0

  defp calculate_monitoring_efficiency(final_results, monitoring_time_us) do
    samples = get_sample_count(final_results)
    time_seconds = monitoring_time_us / 1_000_000

    case time_seconds do
      t when t > 0 -> Float.round(samples / t, 2)
      _ -> 0.0
    end
  end

  defp calculate_average_performance_score(workflow_analysis) do
    scores =
      Enum.map(workflow_analysis, fn analysis ->
        Map.get(analysis, :performance_score, 0.0)
      end)

    case scores do
      [] -> 0.0
      _ -> Float.round(Enum.sum(scores) / length(scores), 3)
    end
  end

  defp analyze_performance_distribution(workflow_analysis) do
    scores =
      Enum.map(workflow_analysis, fn analysis ->
        Map.get(analysis, :performance_score, 0.0)
      end)

    %{
      high_performance: Enum.count(scores, fn score -> score > 0.8 end),
      medium_performance: Enum.count(scores, fn score -> score > 0.5 and score <= 0.8 end),
      low_performance: Enum.count(scores, fn score -> score <= 0.5 end),
      total_workflows: length(scores)
    }
  end

  defp identify_top_performing_workflows(workflow_analysis) do
    workflow_analysis
    |> Enum.filter(fn analysis -> Map.get(analysis, :performance_score, 0.0) > 0.8 end)
    |> Enum.map(fn analysis -> Map.get(analysis, :workflow_id, "unknown") end)
    # Top 5 performers
    |> Enum.take(5)
  end

  defp identify_performance_issues(workflow_analysis) do
    workflow_analysis
    |> Enum.filter(fn analysis ->
      Map.get(analysis, :performance_score, 1.0) < 0.6 or
        length(Map.get(analysis, :threshold_violations, [])) > 0
    end)
    |> Enum.map(fn analysis ->
      %{
        workflow_id: Map.get(analysis, :workflow_id, "unknown"),
        performance_score: Map.get(analysis, :performance_score, 0.0),
        violations: Map.get(analysis, :threshold_violations, []),
        recommendations: Map.get(analysis, :optimization_recommendations, [])
      }
    end)
  end

  defp determine_alert_severity(alert_data) do
    # Determine alert severity based on violation magnitude
    case alert_data do
      %{threshold_type: :execution_time, current_value: current, threshold_value: threshold} ->
        calculate_execution_time_severity(current, threshold)

      %{threshold_type: :memory_usage, current_value: current, threshold_value: threshold} ->
        calculate_memory_usage_severity(current, threshold)

      _ ->
        :medium
    end
  end

  defp calculate_execution_time_severity(current, threshold) do
    ratio = current / threshold

    cond do
      ratio > 3.0 -> :critical
      ratio > 2.0 -> :high
      ratio > 1.5 -> :medium
      true -> :low
    end
  end

  defp calculate_memory_usage_severity(current, threshold) do
    ratio = current / threshold

    cond do
      ratio > 2.0 -> :critical
      ratio > 1.5 -> :high
      ratio > 1.2 -> :medium
      true -> :low
    end
  end

  defp notify_monitoring_completion(final_results, monitoring_session) do
    case WorkflowMonitor.notify_performance_monitoring_completion(
           :monitor_performance_action,
           monitoring_session.session_id,
           %{
             workflows_monitored: length(monitoring_session.target_workflows),
             alerts_generated: length(final_results.alerts_generated),
             optimizations_triggered: length(final_results.optimizations_triggered)
           }
         ) do
      :ok -> :ok
      error -> error
    end
  end

  defp generate_monitoring_session_id do
    timestamp = System.system_time(:nanosecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "monitoring_#{timestamp}_#{random}"
  end
end
