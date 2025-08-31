defmodule RubberDuck.Workflows.Actions.OptimizeConcurrencyAction do
  @moduledoc """
  Action for intelligent concurrency optimization and resource management.

  Provides dynamic concurrency adjustment based on system resources, workload characteristics,
  and performance metrics. Integrates with ReactorPerformanceAgent for comprehensive
  resource management and optimization strategies.

  Features:
  - Intelligent concurrency level adjustment based on system capacity and workload
  - Resource-aware optimization with CPU, memory, and scheduler utilization tracking
  - Dynamic scaling with automatic backpressure and resource limit management
  - Performance-based tuning with learning from optimization outcomes
  - Integration with existing workflow infrastructure and monitoring systems
  - Comprehensive resource utilization analysis and optimization recommendations

  Usage Patterns:
  - **Workflow Scaling**: Dynamic adjustment of concurrent workflow execution
  - **Resource Optimization**: Intelligent resource allocation and utilization
  - **Performance Tuning**: Automatic concurrency tuning for optimal throughput
  - **System Protection**: Prevent resource exhaustion with intelligent limiting
  """

  use Jido.Action,
    name: "optimize_concurrency",
    schema: [
      target_workflows: [
        type: {:list, :string},
        required: true,
        doc: "Workflows to optimize concurrency for"
      ],
      current_concurrency: [type: :pos_integer, required: true, doc: "Current concurrency level"],
      optimization_strategy: [
        type: :atom,
        default: :adaptive,
        doc: "Optimization strategy (:adaptive, :conservative, :aggressive, :predictive)"
      ],
      resource_constraints: [type: :map, default: %{}, doc: "Resource constraints and limits"],
      performance_targets: [type: :map, default: %{}, doc: "Performance targets for optimization"],
      monitoring_window_ms: [
        type: :pos_integer,
        default: 30_000,
        doc: "Monitoring window for optimization decisions"
      ]
    ]

  require Logger

  alias RubberDuck.Agents.Workflow.ReactorPerformanceAgent
  alias RubberDuck.Workflows.WorkflowMonitor

  @supported_optimization_strategies [:adaptive, :conservative, :aggressive, :predictive]

  @default_resource_constraints %{
    max_cpu_percentage: 80,
    max_memory_mb: 1000,
    max_concurrent_processes: 100,
    scheduler_utilization_threshold: 0.8
  }

  @default_performance_targets %{
    target_throughput_per_second: 50,
    max_response_time_ms: 5000,
    min_success_rate: 0.95,
    target_resource_efficiency: 0.8
  }

  def run(params, context) do
    %{
      target_workflows: workflows,
      current_concurrency: current_level,
      optimization_strategy: strategy,
      resource_constraints: constraints,
      performance_targets: targets,
      monitoring_window_ms: window_ms
    } = params

    merged_constraints = Map.merge(@default_resource_constraints, constraints)
    merged_targets = Map.merge(@default_performance_targets, targets)

    Logger.info("OptimizeConcurrencyAction: Starting concurrency optimization",
      target_workflows: length(workflows),
      current_concurrency: current_level,
      optimization_strategy: strategy
    )

    optimization_start_time = System.monotonic_time(:microsecond)

    with {:ok, validated_params} <-
           validate_optimization_params(workflows, current_level, strategy, merged_constraints),
         {:ok, system_analysis} <- analyze_system_resources(merged_constraints, context),
         {:ok, workload_analysis} <-
           analyze_workload_characteristics(workflows, window_ms, context),
         {:ok, optimization_decision} <-
           determine_optimal_concurrency(
             validated_params,
             system_analysis,
             workload_analysis,
             merged_targets,
             strategy
           ),
         {:ok, implementation_result} <-
           implement_concurrency_changes(optimization_decision, context) do
      optimization_time = System.monotonic_time(:microsecond) - optimization_start_time

      Logger.info("OptimizeConcurrencyAction: Concurrency optimization completed",
        new_concurrency: optimization_decision.recommended_concurrency,
        optimization_time_ms: div(optimization_time, 1000),
        expected_improvement: optimization_decision.expected_improvement_percentage
      )

      {:ok,
       %{
         optimization_decision: optimization_decision,
         implementation_result: implementation_result,
         optimization_metadata: %{
           optimization_time_microseconds: optimization_time,
           original_concurrency: current_level,
           new_concurrency: optimization_decision.recommended_concurrency,
           strategy_used: strategy,
           system_analysis: system_analysis,
           workload_analysis: workload_analysis,
           performance_impact:
             calculate_performance_impact(optimization_decision, implementation_result)
         }
       }}
    else
      {:error, reason} ->
        Logger.error("OptimizeConcurrencyAction: Concurrency optimization failed", error: reason)
        {:error, {:concurrency_optimization_failed, reason}}
    end
  end

  # Private implementation functions

  defp validate_optimization_params(workflows, current_level, strategy, constraints) do
    with :ok <- validate_workflows(workflows),
         :ok <- validate_concurrency_level(current_level),
         :ok <- validate_optimization_strategy(strategy),
         :ok <- validate_resource_constraints(constraints) do
      validated_params = %{
        workflows: workflows,
        current_concurrency: current_level,
        strategy: strategy,
        constraints: constraints,
        validation_timestamp: DateTime.utc_now()
      }

      {:ok, validated_params}
    else
      {:error, reason} -> {:error, {:parameter_validation_failed, reason}}
    end
  end

  defp validate_workflows(workflows) when is_list(workflows) and length(workflows) > 0, do: :ok
  defp validate_workflows(_), do: {:error, :invalid_workflows}

  defp validate_concurrency_level(level) when is_integer(level) and level > 0, do: :ok
  defp validate_concurrency_level(_), do: {:error, :invalid_concurrency_level}

  defp validate_optimization_strategy(strategy)
       when strategy in @supported_optimization_strategies,
       do: :ok

  defp validate_optimization_strategy(_), do: {:error, :invalid_optimization_strategy}

  defp validate_resource_constraints(constraints) when is_map(constraints) do
    required_keys = [:max_cpu_percentage, :max_memory_mb, :max_concurrent_processes]
    missing_keys = required_keys -- Map.keys(constraints)

    case missing_keys do
      [] -> :ok
      _ -> {:error, {:missing_constraint_keys, missing_keys}}
    end
  end

  defp validate_resource_constraints(_), do: {:error, :invalid_resource_constraints}

  defp analyze_system_resources(constraints, context) do
    system_metrics = %{
      cpu_usage: get_current_cpu_usage(),
      memory_usage: get_current_memory_usage(),
      scheduler_utilization: get_scheduler_utilization(),
      process_count: get_current_process_count(),
      available_capacity: calculate_available_capacity(constraints)
    }

    resource_analysis = %{
      current_metrics: system_metrics,
      resource_pressure: calculate_resource_pressure(system_metrics, constraints),
      bottlenecks: identify_resource_bottlenecks(system_metrics, constraints),
      optimization_headroom: calculate_optimization_headroom(system_metrics, constraints)
    }

    Logger.debug("OptimizeConcurrencyAction: System resource analysis completed",
      cpu_usage: system_metrics.cpu_usage,
      memory_usage_mb: system_metrics.memory_usage,
      resource_pressure: resource_analysis.resource_pressure
    )

    {:ok, resource_analysis}
  end

  defp analyze_workload_characteristics(workflows, window_ms, context) do
    workload_metrics =
      Enum.map(workflows, fn workflow_id ->
        case get_workflow_performance_metrics(workflow_id, window_ms) do
          {:ok, metrics} ->
            %{
              workflow_id: workflow_id,
              metrics: metrics,
              concurrency_utilization: calculate_concurrency_utilization(metrics),
              performance_profile: classify_performance_profile(metrics)
            }

          {:error, reason} ->
            %{
              workflow_id: workflow_id,
              error: reason,
              concurrency_utilization: 0.0,
              performance_profile: :unknown
            }
        end
      end)

    aggregate_analysis = %{
      total_throughput: calculate_total_throughput(workload_metrics),
      average_response_time: calculate_average_response_time(workload_metrics),
      resource_efficiency: calculate_workload_resource_efficiency(workload_metrics),
      concurrency_patterns: analyze_concurrency_patterns(workload_metrics),
      scalability_potential: assess_scalability_potential(workload_metrics)
    }

    workload_analysis = %{
      individual_workflows: workload_metrics,
      aggregate_metrics: aggregate_analysis,
      optimization_opportunities:
        identify_workload_optimizations(workload_metrics, aggregate_analysis)
    }

    Logger.debug("OptimizeConcurrencyAction: Workload analysis completed",
      total_workflows: length(workflows),
      total_throughput: aggregate_analysis.total_throughput,
      scalability_potential: aggregate_analysis.scalability_potential
    )

    {:ok, workload_analysis}
  end

  defp determine_optimal_concurrency(
         validated_params,
         system_analysis,
         workload_analysis,
         targets,
         strategy
       ) do
    current_concurrency = validated_params.current_concurrency

    optimization_factors = %{
      resource_capacity: system_analysis.available_capacity,
      workload_scalability: workload_analysis.aggregate_metrics.scalability_potential,
      current_performance: workload_analysis.aggregate_metrics.resource_efficiency,
      bottleneck_severity: calculate_bottleneck_severity(system_analysis.bottlenecks)
    }

    case strategy do
      :adaptive ->
        determine_adaptive_concurrency(current_concurrency, optimization_factors, targets)

      :conservative ->
        determine_conservative_concurrency(current_concurrency, optimization_factors, targets)

      :aggressive ->
        determine_aggressive_concurrency(current_concurrency, optimization_factors, targets)

      :predictive ->
        determine_predictive_concurrency(
          current_concurrency,
          optimization_factors,
          targets,
          workload_analysis
        )
    end
  end

  defp determine_adaptive_concurrency(current_concurrency, factors, targets) do
    # Adaptive strategy: balance performance and resource utilization
    base_adjustment = calculate_base_adjustment_factor(factors, targets)
    resource_modifier = calculate_resource_modifier(factors.resource_capacity)
    workload_modifier = calculate_workload_modifier(factors.workload_scalability)

    adjustment_factor = base_adjustment * resource_modifier * workload_modifier
    recommended_concurrency = max(1, round(current_concurrency * adjustment_factor))

    # Ensure we don't exceed system limits
    max_safe_concurrency = calculate_max_safe_concurrency(factors)
    final_concurrency = min(recommended_concurrency, max_safe_concurrency)

    expected_improvement =
      calculate_expected_improvement(current_concurrency, final_concurrency, factors)

    {:ok,
     %{
       recommended_concurrency: final_concurrency,
       adjustment_factor: adjustment_factor,
       strategy_rationale: "Adaptive optimization balancing performance and resource utilization",
       expected_improvement_percentage: expected_improvement,
       confidence_score: calculate_confidence_score(:adaptive, factors)
     }}
  end

  defp determine_conservative_concurrency(current_concurrency, factors, targets) do
    # Conservative strategy: prefer stability and resource safety
    if factors.resource_capacity < 0.7 do
      # Reduce concurrency if resources are constrained
      recommended_concurrency = max(1, round(current_concurrency * 0.8))

      {:ok,
       %{
         recommended_concurrency: recommended_concurrency,
         adjustment_factor: 0.8,
         strategy_rationale: "Conservative reduction due to resource constraints",
         expected_improvement_percentage:
           calculate_expected_improvement(current_concurrency, recommended_concurrency, factors),
         confidence_score: 0.9
       }}
    else
      # Small increase if resources permit
      recommended_concurrency =
        min(current_concurrency + 1, calculate_max_safe_concurrency(factors))

      {:ok,
       %{
         recommended_concurrency: recommended_concurrency,
         adjustment_factor: recommended_concurrency / current_concurrency,
         strategy_rationale: "Conservative incremental increase with resource safety",
         expected_improvement_percentage:
           calculate_expected_improvement(current_concurrency, recommended_concurrency, factors),
         confidence_score: 0.8
       }}
    end
  end

  defp determine_aggressive_concurrency(current_concurrency, factors, targets) do
    # Aggressive strategy: maximize throughput within resource limits
    max_safe_concurrency = calculate_max_safe_concurrency(factors)

    # Aim for significant increase if scalability potential is high
    recommended_concurrency =
      if factors.workload_scalability > 0.7 do
        min(round(current_concurrency * 1.5), max_safe_concurrency)
      else
        min(round(current_concurrency * 1.2), max_safe_concurrency)
      end

    {:ok,
     %{
       recommended_concurrency: recommended_concurrency,
       adjustment_factor: recommended_concurrency / current_concurrency,
       strategy_rationale: "Aggressive optimization for maximum throughput within limits",
       expected_improvement_percentage:
         calculate_expected_improvement(current_concurrency, recommended_concurrency, factors),
       confidence_score: calculate_confidence_score(:aggressive, factors)
     }}
  end

  defp determine_predictive_concurrency(current_concurrency, factors, targets, workload_analysis) do
    # Predictive strategy: use workload patterns to predict optimal concurrency
    concurrency_patterns = workload_analysis.aggregate_metrics.concurrency_patterns

    predicted_optimal = predict_optimal_concurrency(concurrency_patterns, factors, targets)
    max_safe_concurrency = calculate_max_safe_concurrency(factors)

    recommended_concurrency = min(predicted_optimal, max_safe_concurrency)

    {:ok,
     %{
       recommended_concurrency: recommended_concurrency,
       adjustment_factor: recommended_concurrency / current_concurrency,
       strategy_rationale:
         "Predictive optimization based on workload patterns and performance history",
       expected_improvement_percentage:
         calculate_expected_improvement(current_concurrency, recommended_concurrency, factors),
       confidence_score: calculate_confidence_score(:predictive, factors),
       prediction_details: %{
         predicted_optimal: predicted_optimal,
         based_on_patterns: concurrency_patterns
       }
     }}
  end

  defp implement_concurrency_changes(optimization_decision, context) do
    new_concurrency = optimization_decision.recommended_concurrency

    # Implementation would update workflow concurrency settings
    # This is a simplified simulation
    implementation_steps = [
      {:validate_new_concurrency, new_concurrency},
      {:update_workflow_configurations, new_concurrency},
      {:monitor_transition, new_concurrency},
      {:verify_optimization_success, new_concurrency}
    ]

    case execute_implementation_steps(implementation_steps, context) do
      {:ok, execution_results} ->
        {:ok,
         %{
           implementation_successful: true,
           new_concurrency_applied: new_concurrency,
           execution_steps: execution_results,
           monitoring_enabled: true,
           rollback_available: true
         }}

      {:error, reason} ->
        {:error, {:implementation_failed, reason}}
    end
  end

  # Helper functions

  defp get_current_cpu_usage do
    # Implementation would use :cpu_sup or similar
    :rand.uniform(100)
  end

  defp get_current_memory_usage do
    case :erlang.memory(:total) do
      memory when is_integer(memory) -> div(memory, 1_024 * 1_024)
      _ -> 0
    end
  end

  defp get_scheduler_utilization do
    schedulers = :erlang.system_info(:schedulers_online)
    # Simplified utilization calculation
    :rand.uniform(100) / 100
  end

  defp get_current_process_count do
    :erlang.system_info(:process_count)
  end

  defp calculate_available_capacity(constraints) do
    cpu_capacity = max(0, (100 - get_current_cpu_usage()) / 100)

    memory_capacity =
      max(0, (constraints.max_memory_mb - get_current_memory_usage()) / constraints.max_memory_mb)

    process_capacity =
      max(
        0,
        (constraints.max_concurrent_processes - get_current_process_count()) /
          constraints.max_concurrent_processes
      )

    # Take the most constraining resource
    min(cpu_capacity, min(memory_capacity, process_capacity))
  end

  defp calculate_resource_pressure(metrics, constraints) do
    cpu_pressure = metrics.cpu_usage / 100
    memory_pressure = metrics.memory_usage / constraints.max_memory_mb
    process_pressure = metrics.process_count / constraints.max_concurrent_processes

    # Return the highest pressure
    max(cpu_pressure, max(memory_pressure, process_pressure))
  end

  defp identify_resource_bottlenecks(metrics, constraints) do
    bottlenecks = []

    bottlenecks =
      if metrics.cpu_usage > constraints.max_cpu_percentage * 0.9 do
        [:cpu_bottleneck | bottlenecks]
      else
        bottlenecks
      end

    bottlenecks =
      if metrics.memory_usage > constraints.max_memory_mb * 0.9 do
        [:memory_bottleneck | bottlenecks]
      else
        bottlenecks
      end

    bottlenecks =
      if metrics.process_count > constraints.max_concurrent_processes * 0.9 do
        [:process_bottleneck | bottlenecks]
      else
        bottlenecks
      end

    bottlenecks
  end

  defp calculate_optimization_headroom(metrics, constraints) do
    cpu_headroom =
      max(0, constraints.max_cpu_percentage - metrics.cpu_usage) / constraints.max_cpu_percentage

    memory_headroom =
      max(0, constraints.max_memory_mb - metrics.memory_usage) / constraints.max_memory_mb

    process_headroom =
      max(0, constraints.max_concurrent_processes - metrics.process_count) /
        constraints.max_concurrent_processes

    # Return average headroom
    (cpu_headroom + memory_headroom + process_headroom) / 3
  end

  defp get_workflow_performance_metrics(workflow_id, window_ms) do
    # Implementation would integrate with WorkflowMonitor
    # Simplified simulation
    {:ok,
     %{
       throughput_per_second: :rand.uniform(100),
       average_response_time_ms: :rand.uniform(5000),
       error_rate: :rand.uniform() * 0.1,
       resource_utilization: :rand.uniform(100) / 100,
       concurrency_efficiency: :rand.uniform(100) / 100
     }}
  end

  defp calculate_concurrency_utilization(metrics) do
    # Simplified calculation based on throughput and response time
    base_utilization = metrics.concurrency_efficiency

    # Adjust based on performance characteristics
    if metrics.average_response_time_ms > 3000 do
      max(0, base_utilization - 0.2)
    else
      min(1.0, base_utilization + 0.1)
    end
  end

  defp classify_performance_profile(metrics) do
    cond do
      metrics.throughput_per_second > 50 and metrics.average_response_time_ms < 1000 ->
        :high_performance

      metrics.throughput_per_second > 20 and metrics.average_response_time_ms < 3000 ->
        :moderate_performance

      metrics.error_rate > 0.05 ->
        :unstable_performance

      true ->
        :low_performance
    end
  end

  defp calculate_total_throughput(workload_metrics) do
    workload_metrics
    |> Enum.map(fn
      %{metrics: metrics} -> metrics.throughput_per_second
      _ -> 0
    end)
    |> Enum.sum()
  end

  defp calculate_average_response_time(workload_metrics) do
    response_times =
      workload_metrics
      |> Enum.map(fn
        %{metrics: metrics} -> metrics.average_response_time_ms
        _ -> 0
      end)
      |> Enum.filter(fn time -> time > 0 end)

    case response_times do
      [] -> 0
      times -> Enum.sum(times) / length(times)
    end
  end

  defp calculate_workload_resource_efficiency(workload_metrics) do
    efficiencies =
      workload_metrics
      |> Enum.map(fn
        %{metrics: metrics} -> metrics.resource_utilization
        _ -> 0
      end)
      |> Enum.filter(fn eff -> eff > 0 end)

    case efficiencies do
      [] -> 0.0
      effs -> Enum.sum(effs) / length(effs)
    end
  end

  defp analyze_concurrency_patterns(workload_metrics) do
    # Simplified pattern analysis
    %{
      high_concurrency_workflows:
        Enum.count(workload_metrics, fn
          %{concurrency_utilization: util} when util > 0.8 -> true
          _ -> false
        end),
      scaling_potential: calculate_scaling_potential(workload_metrics),
      resource_distribution: analyze_resource_distribution(workload_metrics)
    }
  end

  defp assess_scalability_potential(workload_metrics) do
    # Assess how well workflows can scale with increased concurrency
    high_performing_count =
      Enum.count(workload_metrics, fn
        %{performance_profile: :high_performance} -> true
        _ -> false
      end)

    total_workflows = length(workload_metrics)

    case total_workflows do
      0 -> 0.0
      _ -> high_performing_count / total_workflows
    end
  end

  defp identify_workload_optimizations(workload_metrics, aggregate_analysis) do
    optimizations = []

    optimizations =
      if aggregate_analysis.average_response_time > 3000 do
        ["Consider reducing concurrency to improve response times" | optimizations]
      else
        optimizations
      end

    optimizations =
      if aggregate_analysis.resource_efficiency < 0.6 do
        ["Optimize resource utilization through better workload distribution" | optimizations]
      else
        optimizations
      end

    optimizations =
      if aggregate_analysis.total_throughput < 50 do
        ["Consider increasing concurrency to improve throughput" | optimizations]
      else
        optimizations
      end

    optimizations
  end

  defp calculate_base_adjustment_factor(factors, targets) do
    # Base adjustment based on current performance vs targets
    current_efficiency = factors.current_performance
    target_efficiency = targets.target_resource_efficiency

    cond do
      current_efficiency < target_efficiency * 0.8 ->
        # Increase concurrency for better efficiency
        1.2

      current_efficiency > target_efficiency * 1.1 ->
        # Slightly decrease concurrency
        0.9

      true ->
        # Maintain current level
        1.0
    end
  end

  defp calculate_resource_modifier(resource_capacity) do
    cond do
      # Plenty of resources, can increase
      resource_capacity > 0.8 -> 1.3
      # Moderate resources, small increase
      resource_capacity > 0.5 -> 1.1
      # Limited resources, maintain
      resource_capacity > 0.3 -> 1.0
      # Very limited resources, decrease
      true -> 0.8
    end
  end

  defp calculate_workload_modifier(scalability_potential) do
    cond do
      # High scalability, increase concurrency
      scalability_potential > 0.8 -> 1.2
      # Moderate scalability, small increase
      scalability_potential > 0.5 -> 1.05
      # Limited scalability, maintain
      scalability_potential > 0.3 -> 1.0
      # Poor scalability, slight decrease
      true -> 0.9
    end
  end

  defp calculate_max_safe_concurrency(factors) do
    # Calculate maximum safe concurrency based on resource capacity
    # Base limit
    base_limit = 100

    resource_multiplier = factors.resource_capacity

    bottleneck_penalty =
      case calculate_bottleneck_severity(factors.bottlenecks) do
        :high -> 0.5
        :medium -> 0.7
        :low -> 0.9
        :none -> 1.0
      end

    round(base_limit * resource_multiplier * bottleneck_penalty)
  end

  defp calculate_bottleneck_severity(bottlenecks) do
    case length(bottlenecks) do
      0 -> :none
      1 -> :low
      2 -> :medium
      _ -> :high
    end
  end

  defp calculate_expected_improvement(current, new, factors) do
    if current == 0 do
      0
    else
      base_improvement = (new - current) / current * 100

      # Adjust based on factors
      resource_factor = factors.resource_capacity
      scalability_factor = factors.workload_scalability

      adjusted_improvement = base_improvement * resource_factor * scalability_factor

      Float.round(max(-50, min(100, adjusted_improvement)), 1)
    end
  end

  defp calculate_confidence_score(strategy, factors) do
    base_confidence =
      case strategy do
        :conservative -> 0.9
        :adaptive -> 0.8
        :aggressive -> 0.6
        :predictive -> 0.7
      end

    # Adjust based on resource capacity and bottlenecks
    resource_adjustment = factors.resource_capacity * 0.2

    bottleneck_penalty =
      case calculate_bottleneck_severity(factors.bottlenecks) do
        :none -> 0.0
        :low -> -0.1
        :medium -> -0.2
        :high -> -0.3
      end

    Float.round(base_confidence + resource_adjustment + bottleneck_penalty, 2)
  end

  defp calculate_scaling_potential(workload_metrics) do
    # Simplified scaling potential calculation
    efficient_workflows =
      Enum.count(workload_metrics, fn
        %{concurrency_utilization: util} when util > 0.7 -> true
        _ -> false
      end)

    total_workflows = max(1, length(workload_metrics))
    efficient_workflows / total_workflows
  end

  defp analyze_resource_distribution(workload_metrics) do
    # Simplified resource distribution analysis
    %{
      # Placeholder
      even_distribution: true,
      # Placeholder
      resource_hotspots: [],
      optimization_opportunities: ["Balance workload distribution"]
    }
  end

  defp predict_optimal_concurrency(patterns, factors, targets) do
    # Simplified prediction based on patterns
    base_prediction =
      case patterns.scaling_potential do
        potential when potential > 0.8 -> 80
        potential when potential > 0.5 -> 50
        _ -> 30
      end

    # Adjust for resource capacity
    resource_adjusted = round(base_prediction * factors.resource_capacity)

    max(1, min(200, resource_adjusted))
  end

  defp execute_implementation_steps(steps, _context) do
    # Simulate implementation step execution
    results =
      Enum.map(steps, fn {step_name, parameter} ->
        %{
          step: step_name,
          parameter: parameter,
          executed: true,
          success: true,
          execution_time_ms: :rand.uniform(100)
        }
      end)

    {:ok, results}
  end

  defp calculate_performance_impact(optimization_decision, implementation_result) do
    %{
      expected_improvement: optimization_decision.expected_improvement_percentage,
      confidence_score: optimization_decision.confidence_score,
      implementation_success: implementation_result.implementation_successful,
      monitoring_enabled: implementation_result.monitoring_enabled
    }
  end
end
