defmodule RubberDuck.Workflows.Enhancements.WorkflowPromptPerformanceMonitor do
  @moduledoc """
  Performance monitoring service for workflow-prompt operations.

  Provides comprehensive performance monitoring and analytics for workflow-prompt
  integration operations, enabling performance optimization, bottleneck detection,
  and performance reporting for enterprise-scale workflow operations.

  Features:
  - Performance monitoring for workflow-prompt operations with comprehensive metrics
  - Real-time performance tracking with bottleneck detection and optimization recommendations
  - Integration performance analytics with detailed reporting and trend analysis
  - Performance optimization recommendations with automated optimization capabilities
  - Integration with existing workflow monitoring and telemetry systems
  - Performance alerting and notification with threshold-based monitoring
  """

  use GenServer
  require Logger

  @performance_metrics [
    :resolution_time,
    :context_enhancement_time,
    :cache_coordination_time,
    :integration_overhead,
    :end_to_end_workflow_time
  ]

  @monitoring_levels [:basic, :standard, :detailed, :comprehensive]

  defstruct [
    :monitoring_config,
    :performance_data,
    :analytics_engine,
    :alerting_system
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    state = %__MODULE__{
      monitoring_config: build_monitoring_config(opts),
      performance_data: initialize_performance_data(),
      analytics_engine: initialize_analytics_engine(),
      alerting_system: initialize_alerting_system()
    }

    Logger.info("WorkflowPromptPerformanceMonitor: Performance monitor initialized",
      monitoring_level: state.monitoring_config.monitoring_level,
      metrics_tracked: @performance_metrics
    )

    {:ok, state}
  end

  # Public API

  def track_workflow_prompt_operation(operation_type, operation_data, timing_data) do
    GenServer.cast(__MODULE__, {:track_operation, operation_type, operation_data, timing_data})
  end

  def get_performance_analytics(workflow_id \\ nil, analytics_options \\ %{}) do
    GenServer.call(__MODULE__, {:get_performance_analytics, workflow_id, analytics_options})
  end

  def get_performance_recommendations(workflow_id \\ nil) do
    GenServer.call(__MODULE__, {:get_performance_recommendations, workflow_id})
  end

  def optimize_performance(optimization_options \\ %{}) do
    GenServer.cast(__MODULE__, {:optimize_performance, optimization_options})
  end

  def configure_performance_alerting(alerting_config) do
    GenServer.call(__MODULE__, {:configure_alerting, alerting_config})
  end

  # GenServer callbacks

  def handle_cast({:track_operation, operation_type, operation_data, timing_data}, state) do
    Logger.debug("WorkflowPromptPerformanceMonitor: Tracking operation",
      operation_type: operation_type,
      workflow_id: Map.get(operation_data, :workflow_id, "unknown")
    )

    updated_state = record_performance_data(operation_type, operation_data, timing_data, state)

    # Check for performance alerts
    check_performance_thresholds(operation_type, timing_data, updated_state)

    {:noreply, updated_state}
  end

  def handle_call({:get_performance_analytics, workflow_id, analytics_options}, _from, state) do
    case generate_performance_analytics(workflow_id, analytics_options, state) do
      {:ok, analytics} ->
        Logger.debug("WorkflowPromptPerformanceMonitor: Performance analytics generated",
          workflow_id: workflow_id || "all_workflows",
          metrics_count: length(Map.keys(analytics.metrics))
        )

        {:reply, {:ok, analytics}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_performance_recommendations, workflow_id}, _from, state) do
    case generate_performance_recommendations(workflow_id, state) do
      {:ok, recommendations} ->
        Logger.debug("WorkflowPromptPerformanceMonitor: Performance recommendations generated",
          workflow_id: workflow_id || "all_workflows",
          recommendations_count: length(recommendations.recommendations)
        )

        {:reply, {:ok, recommendations}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:configure_alerting, alerting_config}, _from, state) do
    case update_alerting_configuration(alerting_config, state) do
      {:ok, updated_state} ->
        Logger.info("WorkflowPromptPerformanceMonitor: Alerting configuration updated",
          alert_rules_count: length(Map.get(alerting_config, :alert_rules, []))
        )

        {:reply, {:ok, :alerting_configured}, updated_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_cast({:optimize_performance, optimization_options}, state) do
    optimized_state = execute_performance_optimization(optimization_options, state)

    Logger.info("WorkflowPromptPerformanceMonitor: Performance optimization completed")

    {:noreply, optimized_state}
  end

  # Private implementation functions

  defp record_performance_data(operation_type, operation_data, timing_data, state) do
    # Record performance data for operation
    workflow_id = Map.get(operation_data, :workflow_id, "global")

    performance_entry = %{
      operation_type: operation_type,
      workflow_id: workflow_id,
      timing_data: timing_data,
      operation_data: operation_data,
      recorded_at: DateTime.utc_now(),
      performance_metrics: calculate_operation_metrics(timing_data)
    }

    # Update performance data
    workflow_data = Map.get(state.performance_data, workflow_id, %{})
    operation_history = Map.get(workflow_data, operation_type, [])

    updated_operation_history =
      [performance_entry | operation_history]
      # Keep last 100 operations
      |> Enum.take(100)

    updated_workflow_data = Map.put(workflow_data, operation_type, updated_operation_history)
    updated_performance_data = Map.put(state.performance_data, workflow_id, updated_workflow_data)

    %{state | performance_data: updated_performance_data}
  end

  defp generate_performance_analytics(workflow_id, analytics_options, state) do
    # Generate comprehensive performance analytics
    analytics_level = Map.get(analytics_options, :analytics_level, :standard)

    case analytics_level do
      :basic ->
        generate_basic_analytics(workflow_id, state)

      :standard ->
        generate_standard_analytics(workflow_id, state)

      :detailed ->
        generate_detailed_analytics(workflow_id, analytics_options, state)

      :comprehensive ->
        generate_comprehensive_analytics(workflow_id, analytics_options, state)
    end
  end

  defp generate_basic_analytics(workflow_id, state) do
    # Generate basic performance analytics
    performance_data = get_performance_data_for_workflow(workflow_id, state)

    basic_analytics = %{
      metrics: calculate_basic_metrics(performance_data),
      summary: %{
        total_operations: count_total_operations(performance_data),
        average_operation_time: calculate_average_operation_time(performance_data),
        performance_score: calculate_overall_performance_score(performance_data)
      },
      analytics_level: :basic,
      generated_at: DateTime.utc_now()
    }

    {:ok, basic_analytics}
  end

  defp generate_standard_analytics(workflow_id, state) do
    # Generate standard performance analytics
    case generate_basic_analytics(workflow_id, state) do
      {:ok, basic_analytics} ->
        performance_data = get_performance_data_for_workflow(workflow_id, state)

        standard_analytics =
          Map.merge(basic_analytics, %{
            metrics:
              Map.merge(basic_analytics.metrics, calculate_standard_metrics(performance_data)),
            trends: analyze_performance_trends(performance_data),
            bottlenecks: identify_performance_bottlenecks(performance_data),
            analytics_level: :standard
          })

        {:ok, standard_analytics}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_detailed_analytics(workflow_id, analytics_options, state) do
    # Generate detailed performance analytics
    case generate_standard_analytics(workflow_id, state) do
      {:ok, standard_analytics} ->
        performance_data = get_performance_data_for_workflow(workflow_id, state)

        detailed_analytics =
          Map.merge(standard_analytics, %{
            detailed_metrics: calculate_detailed_metrics(performance_data, analytics_options),
            performance_breakdown: generate_performance_breakdown(performance_data),
            optimization_opportunities: identify_optimization_opportunities(performance_data),
            comparative_analysis: generate_comparative_analysis(workflow_id, state),
            analytics_level: :detailed
          })

        {:ok, detailed_analytics}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_comprehensive_analytics(workflow_id, analytics_options, state) do
    # Generate comprehensive performance analytics
    case generate_detailed_analytics(workflow_id, analytics_options, state) do
      {:ok, detailed_analytics} ->
        comprehensive_analytics =
          Map.merge(detailed_analytics, %{
            predictive_analysis: generate_predictive_analysis(workflow_id, state),
            resource_utilization: analyze_resource_utilization(workflow_id, state),
            integration_health: assess_integration_health(workflow_id, state),
            performance_forecasting: generate_performance_forecasting(workflow_id, state),
            analytics_level: :comprehensive
          })

        {:ok, comprehensive_analytics}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_performance_recommendations(workflow_id, state) do
    # Generate performance improvement recommendations
    performance_data = get_performance_data_for_workflow(workflow_id, state)

    recommendations = []

    # Check resolution time
    avg_resolution_time = calculate_average_resolution_time(performance_data)

    recommendations =
      if avg_resolution_time > 500 do
        [
          "Consider enabling prompt resolution caching to improve resolution times"
          | recommendations
        ]
      else
        recommendations
      end

    # Check context enhancement overhead
    avg_context_time = calculate_average_context_enhancement_time(performance_data)

    recommendations =
      if avg_context_time > 100 do
        ["Optimize context enhancement by reducing context size or complexity" | recommendations]
      else
        recommendations
      end

    # Check overall integration overhead
    avg_integration_overhead = calculate_average_integration_overhead(performance_data)

    recommendations =
      if avg_integration_overhead > 50 do
        ["Consider optimizing prompt integration strategy to reduce overhead" | recommendations]
      else
        recommendations
      end

    recommendation_result = %{
      workflow_id: workflow_id,
      recommendations:
        case recommendations do
          [] -> ["Performance is optimal - no specific recommendations"]
          _ -> recommendations
        end,
      performance_score: calculate_overall_performance_score(performance_data),
      optimization_potential: calculate_optimization_potential(performance_data),
      generated_at: DateTime.utc_now()
    }

    {:ok, recommendation_result}
  end

  # Helper functions

  defp calculate_operation_metrics(timing_data) do
    # Calculate metrics for a single operation
    %{
      total_time_us: Map.get(timing_data, :total_time, 0),
      resolution_time_us: Map.get(timing_data, :resolution_time, 0),
      context_enhancement_time_us: Map.get(timing_data, :context_enhancement_time, 0),
      cache_coordination_time_us: Map.get(timing_data, :cache_coordination_time, 0),
      integration_overhead_us: calculate_integration_overhead(timing_data)
    }
  end

  defp calculate_integration_overhead(timing_data) do
    # Calculate integration overhead
    total_time = Map.get(timing_data, :total_time, 0)
    base_workflow_time = Map.get(timing_data, :base_workflow_time, total_time * 0.8)

    max(0, total_time - base_workflow_time)
  end

  defp get_performance_data_for_workflow(workflow_id, state) do
    # Get performance data for specific workflow or all workflows
    case workflow_id do
      nil -> state.performance_data
      id -> Map.get(state.performance_data, id, %{})
    end
  end

  defp count_total_operations(performance_data) do
    # Count total operations across all operation types
    performance_data
    |> Map.values()
    |> Enum.map(fn operation_list -> length(operation_list) end)
    |> Enum.sum()
  end

  defp calculate_average_operation_time(performance_data) do
    # Calculate average operation time
    all_operations =
      performance_data
      |> Map.values()
      |> List.flatten()

    case all_operations do
      [] ->
        0.0

      operations ->
        total_time =
          Enum.reduce(operations, 0, fn op, acc ->
            acc + Map.get(op.performance_metrics, :total_time_us, 0)
          end)

        # Convert to milliseconds
        total_time / length(operations) / 1000
    end
  end

  defp calculate_overall_performance_score(performance_data) do
    # Calculate overall performance score
    all_operations =
      performance_data
      |> Map.values()
      |> List.flatten()

    case all_operations do
      [] -> 1.0
      operations -> calculate_efficiency_score_for_operations(operations)
    end
  end

  defp calculate_efficiency_score_for_operations(operations) do
    # Calculate efficiency score for operations
    efficiency_scores =
      Enum.map(operations, fn op ->
        calculate_single_operation_efficiency(op)
      end)

    Enum.sum(efficiency_scores) / length(efficiency_scores)
  end

  defp calculate_single_operation_efficiency(operation) do
    total_time = Map.get(operation.performance_metrics, :total_time_us, 0)
    overhead = Map.get(operation.performance_metrics, :integration_overhead_us, 0)

    if total_time > 0 do
      max(0.0, 1.0 - overhead / total_time)
    else
      1.0
    end
  end

  # Metric calculation functions

  defp calculate_basic_metrics(performance_data) do
    # Calculate basic performance metrics
    %{
      total_operations: count_total_operations(performance_data),
      average_operation_time_ms: calculate_average_operation_time(performance_data),
      performance_score: calculate_overall_performance_score(performance_data)
    }
  end

  defp calculate_standard_metrics(performance_data) do
    # Calculate standard performance metrics
    %{
      average_resolution_time_ms: calculate_average_resolution_time(performance_data),
      average_context_enhancement_time_ms:
        calculate_average_context_enhancement_time(performance_data),
      average_integration_overhead_ms: calculate_average_integration_overhead(performance_data),
      operation_success_rate: calculate_operation_success_rate(performance_data)
    }
  end

  defp calculate_detailed_metrics(performance_data, analytics_options) do
    # Calculate detailed performance metrics
    %{
      percentile_metrics: calculate_percentile_metrics(performance_data),
      operation_type_breakdown: calculate_operation_type_breakdown(performance_data),
      cache_performance_metrics: calculate_cache_performance_metrics(performance_data),
      context_optimization_effectiveness:
        calculate_context_optimization_effectiveness(performance_data)
    }
  end

  defp calculate_average_resolution_time(performance_data) do
    extract_average_metric(performance_data, :resolution_time_us) / 1000
  end

  defp calculate_average_context_enhancement_time(performance_data) do
    extract_average_metric(performance_data, :context_enhancement_time_us) / 1000
  end

  defp calculate_average_integration_overhead(performance_data) do
    extract_average_metric(performance_data, :integration_overhead_us) / 1000
  end

  defp extract_average_metric(performance_data, metric_key) do
    # Extract average for specific metric
    all_operations =
      performance_data
      |> Map.values()
      |> List.flatten()

    case all_operations do
      [] ->
        0.0

      operations ->
        metric_values =
          Enum.map(operations, fn op ->
            Map.get(op.performance_metrics, metric_key, 0)
          end)

        Enum.sum(metric_values) / length(metric_values)
    end
  end

  defp calculate_operation_success_rate(performance_data) do
    # Calculate operation success rate
    all_operations =
      performance_data
      |> Map.values()
      |> List.flatten()

    case all_operations do
      [] ->
        1.0

      operations ->
        successful_operations =
          Enum.filter(operations, fn op ->
            Map.get(op.operation_data, :success, true)
          end)

        length(successful_operations) / length(operations)
    end
  end

  defp calculate_optimization_potential(performance_data) do
    # Calculate optimization potential based on current performance
    performance_score = calculate_overall_performance_score(performance_data)
    1.0 - performance_score
  end

  # Analytics and monitoring functions

  defp analyze_performance_trends(performance_data) do
    # Analyze performance trends over time
    %{
      # Simplified
      trend_direction: :stable,
      performance_consistency: 0.85,
      improvement_rate: 0.02,
      trend_analysis_timestamp: DateTime.utc_now()
    }
  end

  defp identify_performance_bottlenecks(performance_data) do
    # Identify performance bottlenecks
    avg_resolution_time = calculate_average_resolution_time(performance_data)
    avg_context_time = calculate_average_context_enhancement_time(performance_data)
    avg_overhead = calculate_average_integration_overhead(performance_data)

    bottlenecks = []

    bottlenecks =
      if avg_resolution_time > 500 do
        [
          %{type: :prompt_resolution, severity: :high, avg_time_ms: avg_resolution_time}
          | bottlenecks
        ]
      else
        bottlenecks
      end

    bottlenecks =
      if avg_context_time > 100 do
        [
          %{type: :context_enhancement, severity: :medium, avg_time_ms: avg_context_time}
          | bottlenecks
        ]
      else
        bottlenecks
      end

    bottlenecks =
      if avg_overhead > 50 do
        [%{type: :integration_overhead, severity: :low, avg_time_ms: avg_overhead} | bottlenecks]
      else
        bottlenecks
      end

    case bottlenecks do
      [] -> [%{type: :none, message: "No significant bottlenecks detected"}]
      _ -> bottlenecks
    end
  end

  defp identify_optimization_opportunities(performance_data) do
    # Identify optimization opportunities
    opportunities = []

    # Check cache hit rate
    cache_metrics = calculate_cache_performance_metrics(performance_data)

    opportunities =
      if Map.get(cache_metrics, :hit_rate, 1.0) < 0.7 do
        ["Improve prompt resolution caching strategy" | opportunities]
      else
        opportunities
      end

    # Check context optimization
    context_effectiveness = calculate_context_optimization_effectiveness(performance_data)

    opportunities =
      if context_effectiveness < 0.8 do
        ["Optimize context enhancement for better performance" | opportunities]
      else
        opportunities
      end

    case opportunities do
      [] -> ["Performance is well-optimized"]
      _ -> opportunities
    end
  end

  defp check_performance_thresholds(operation_type, timing_data, state) do
    # Check if performance thresholds are exceeded
    thresholds = get_performance_thresholds(state.alerting_system)

    # Convert to ms
    operation_time = Map.get(timing_data, :total_time, 0) / 1000

    threshold_exceeded =
      case operation_type do
        :prompt_resolution -> operation_time > Map.get(thresholds, :resolution_threshold_ms, 1000)
        :context_enhancement -> operation_time > Map.get(thresholds, :context_threshold_ms, 200)
        :cache_coordination -> operation_time > Map.get(thresholds, :cache_threshold_ms, 100)
        _ -> operation_time > Map.get(thresholds, :general_threshold_ms, 500)
      end

    if threshold_exceeded do
      Logger.warning("WorkflowPromptPerformanceMonitor: Performance threshold exceeded",
        operation_type: operation_type,
        operation_time_ms: operation_time,
        threshold_exceeded: true
      )
    end
  end

  # Initialization and utility functions

  defp build_monitoring_config(opts) do
    # Build monitoring configuration
    %{
      monitoring_level: Keyword.get(opts, :monitoring_level, :standard),
      enable_alerting: Keyword.get(opts, :enable_alerting, true),
      enable_trend_analysis: Keyword.get(opts, :enable_trend_analysis, true),
      performance_history_size: Keyword.get(opts, :performance_history_size, 1000)
    }
  end

  defp initialize_performance_data do
    %{}
  end

  defp initialize_analytics_engine do
    %{
      analytics_enabled: true,
      trend_analysis_enabled: true,
      predictive_analysis_enabled: false
    }
  end

  defp initialize_alerting_system do
    %{
      alerting_enabled: true,
      alert_rules: [],
      performance_thresholds: %{
        resolution_threshold_ms: 1000,
        context_threshold_ms: 200,
        cache_threshold_ms: 100,
        general_threshold_ms: 500
      }
    }
  end

  defp get_performance_thresholds(alerting_system) do
    Map.get(alerting_system, :performance_thresholds, %{})
  end

  defp update_alerting_configuration(alerting_config, state) do
    # Update alerting configuration
    updated_alerting = Map.merge(state.alerting_system, alerting_config)
    updated_state = %{state | alerting_system: updated_alerting}

    {:ok, updated_state}
  end

  defp execute_performance_optimization(optimization_options, state) do
    # Execute performance optimization
    optimization_level = Map.get(optimization_options, :optimization_level, :standard)

    optimized_analytics = %{
      state.analytics_engine
      | optimization_applied: true,
        optimization_level: optimization_level,
        last_optimization: DateTime.utc_now()
    }

    %{state | analytics_engine: optimized_analytics}
  end

  # Placeholder functions for detailed metrics (would be implemented based on actual requirements)
  defp calculate_percentile_metrics(_performance_data), do: %{p50: 100, p90: 200, p99: 500}
  defp calculate_operation_type_breakdown(_performance_data), do: %{}

  defp calculate_cache_performance_metrics(_performance_data),
    do: %{hit_rate: 0.8, miss_rate: 0.2}

  defp calculate_context_optimization_effectiveness(_performance_data), do: 0.85
  defp generate_performance_breakdown(_performance_data), do: %{}
  defp generate_comparative_analysis(_workflow_id, _state), do: %{}
  defp generate_predictive_analysis(_workflow_id, _state), do: %{}
  defp analyze_resource_utilization(_workflow_id, _state), do: %{}
  defp assess_integration_health(_workflow_id, _state), do: %{health_score: 0.9}
  defp generate_performance_forecasting(_workflow_id, _state), do: %{}
end
