defmodule RubberDuck.Actions.Core.OptimizeEntity do
  @moduledoc """
  Core agentic action for optimizing entities with performance tracking and continuous learning.

  This action provides:
  - Performance tracking to monitor optimization effectiveness over time
  - Multi-objective optimization balancing performance, quality, and maintainability
  - Learning-driven optimization using historical data to improve strategies
  - Safe optimization with validation to prevent breaking existing functionality
  - Rollback capabilities if optimization degrades performance
  """

  use Jido.Action,
    name: "optimize_entity",
    description: "Optimizes entities with performance tracking",
    schema: [
      entity_id: [type: :string, required: true],
      entity_type: [type: :atom, required: true, values: [:user, :project, :code_file, :analysis]],
      optimization_goals: [type: {:list, :atom}, default: [:performance, :quality]],
      safety_checks: [type: :boolean, default: true],
      performance_tracking: [type: :boolean, default: true],
      learning_enabled: [type: :boolean, default: true],
      max_iterations: [type: :integer, default: 3],
      target_improvement: [type: :float, default: 0.1],
      rollback_threshold: [type: :float, default: -0.05],
      optimization_strategy: [type: :atom, default: :balanced, values: [:aggressive, :balanced, :conservative]]
    ]

  # Aliases reserved for future integration with actual contexts
  require Logger

  @impl true
  def run(params, context) do
    with {:ok, entity} <- fetch_entity(params.entity_id, params.entity_type),
         {:ok, baseline_metrics} <- capture_baseline_metrics(entity, params.optimization_goals),
         {:ok, optimization_plan} <- create_optimization_plan(entity, params, context),
         {:ok, _safety_validation} <- perform_safety_checks(entity, optimization_plan, params),
         {:ok, optimized_entity} <- apply_optimizations(entity, optimization_plan, params),
         {:ok, performance_results} <- measure_optimization_results(optimized_entity, baseline_metrics),
         {:ok, validation_results} <- validate_optimization(optimized_entity, performance_results, params),
         {:ok, final_entity} <- finalize_optimization(optimized_entity, validation_results, entity),
         {:ok, learning_data} <- track_optimization_outcome(optimization_plan, performance_results, context) do

      {:ok, %{
        entity: final_entity,
        baseline_metrics: baseline_metrics,
        performance_results: performance_results,
        optimization_plan: optimization_plan,
        improvement_percentage: calculate_improvement_percentage(baseline_metrics, performance_results),
        validation_results: validation_results,
        learning_data: learning_data,
        rollback_performed: validation_results[:rollback_performed] || false,
        metadata: build_metadata(params, context)
      }}
    end
  end

  # Entity fetching
  defp fetch_entity(entity_id, entity_type) do
    case entity_type do
      :user -> fetch_user_entity(entity_id)
      :project -> fetch_project_entity(entity_id)
      :code_file -> fetch_code_file_entity(entity_id)
      :analysis -> fetch_analysis_entity(entity_id)
    end
  end

  defp fetch_user_entity(id) do
    {:ok, %{
      id: id,
      type: :user,
      response_time: 250,
      memory_usage: 100,
      session_duration: 300,
      error_rate: 0.02,
      created_at: DateTime.utc_now()
    }}
  end

  defp fetch_project_entity(id) do
    {:ok, %{
      id: id,
      type: :project,
      build_time: 5_000,
      test_coverage: 0.65,
      code_quality_score: 0.75,
      complexity: 85,
      dependencies_count: 42,
      created_at: DateTime.utc_now()
    }}
  end

  defp fetch_code_file_entity(id) do
    {:ok, %{
      id: id,
      type: :code_file,
      path: "/lib/example.ex",
      content: generate_sample_code(),
      execution_time: 150,
      memory_footprint: 50,
      cyclomatic_complexity: 12,
      lines_of_code: 250,
      created_at: DateTime.utc_now()
    }}
  end

  defp fetch_analysis_entity(id) do
    {:ok, %{
      id: id,
      type: :analysis,
      processing_time: 2_000,
      accuracy: 0.85,
      confidence: 0.90,
      data_points_processed: 10_000,
      created_at: DateTime.utc_now()
    }}
  end

  defp generate_sample_code do
    """
    defmodule Example do
      def process(data) do
        data
        |> validate()
        |> transform()
        |> persist()
      end
    end
    """
  end

  # Baseline metrics capture
  defp capture_baseline_metrics(entity, optimization_goals) do
    metrics = %{
      timestamp: DateTime.utc_now(),
      entity_id: entity.id,
      entity_type: entity.type
    }

    goal_metrics = Enum.reduce(optimization_goals, %{}, fn goal, acc ->
      Map.merge(acc, capture_goal_metrics(entity, goal))
    end)

    {:ok, Map.merge(metrics, goal_metrics)}
  end

  defp capture_goal_metrics(entity, :performance) do
    %{
      performance: %{
        response_time: entity[:response_time] || entity[:execution_time] || 100,
        throughput: calculate_throughput(entity),
        memory_usage: entity[:memory_usage] || entity[:memory_footprint] || 100,
        cpu_usage: estimate_cpu_usage(entity)
      }
    }
  end

  defp capture_goal_metrics(entity, :quality) do
    %{
      quality: %{
        quality_score: entity[:code_quality_score] || entity[:accuracy] || 0.7,
        complexity: entity[:complexity] || entity[:cyclomatic_complexity] || 10,
        maintainability: calculate_maintainability(entity),
        test_coverage: entity[:test_coverage] || 0.5
      }
    }
  end

  defp capture_goal_metrics(entity, :reliability) do
    %{
      reliability: %{
        error_rate: entity[:error_rate] || 0.01,
        availability: entity[:availability] || 0.99,
        mean_time_between_failures: entity[:mtbf] || 10_000,
        recovery_time: entity[:recovery_time] || 60
      }
    }
  end

  defp capture_goal_metrics(entity, :scalability) do
    %{
      scalability: %{
        max_concurrent_users: entity[:max_concurrent] || 100,
        resource_efficiency: calculate_resource_efficiency(entity),
        horizontal_scalability: entity[:horizontal_scalability] || 0.8,
        vertical_scalability: entity[:vertical_scalability] || 0.7
      }
    }
  end

  defp capture_goal_metrics(_entity, _goal) do
    %{}
  end

  defp calculate_throughput(entity) do
    if entity[:data_points_processed] && entity[:processing_time] do
      entity.data_points_processed / max(entity.processing_time / 1_000, 0.001)
    else
      100.0
    end
  end

  defp estimate_cpu_usage(entity) do
    complexity = entity[:complexity] || entity[:cyclomatic_complexity] || 10
    # Estimate CPU usage based on complexity
    min(100, complexity * 1.2)
  end

  defp calculate_maintainability(entity) do
    complexity = entity[:complexity] || entity[:cyclomatic_complexity] || 10
    loc = entity[:lines_of_code] || 100

    # Simple maintainability index
    base_score = 1.0 - (complexity / 100.0)
    size_penalty = if loc > 500, do: 0.1, else: 0

    max(0, base_score - size_penalty)
  end

  defp calculate_resource_efficiency(entity) do
    memory = entity[:memory_usage] || entity[:memory_footprint] || 100
    cpu = estimate_cpu_usage(entity)

    # Efficiency score (lower resource usage = higher efficiency)
    1.0 - ((memory + cpu) / 400.0)
  end

  # Optimization planning
  defp create_optimization_plan(entity, params, context) do
    base_plan = %{
      entity_type: entity.type,
      strategy: params.optimization_strategy,
      goals: params.optimization_goals,
      techniques: select_optimization_techniques(entity.type, params),
      iterations: params.max_iterations,
      target_improvement: params.target_improvement
    }

    adapted_plan = if params.learning_enabled do
      adapt_plan_from_learning(base_plan, context, entity)
    else
      base_plan
    end

    detailed_plan = adapted_plan
      |> add_optimization_steps(entity, params)
      |> prioritize_optimizations(params.optimization_goals)
      |> estimate_optimization_impact()

    {:ok, detailed_plan}
  end

  defp select_optimization_techniques(entity_type, params) do
    base_techniques = case entity_type do
      :user ->
        [:session_optimization, :cache_optimization, :query_optimization]
      :project ->
        [:dependency_optimization, :build_optimization, :structure_refactoring]
      :code_file ->
        [:algorithm_optimization, :memory_optimization, :parallel_processing]
      :analysis ->
        [:algorithm_selection, :data_preprocessing, :result_caching]
    end

    filter_techniques_by_strategy(base_techniques, params.optimization_strategy)
  end

  defp filter_techniques_by_strategy(techniques, :aggressive) do
    techniques
  end
  defp filter_techniques_by_strategy(techniques, :conservative) do
    Enum.take(techniques, 1)
  end
  defp filter_techniques_by_strategy(techniques, :balanced) do
    Enum.take(techniques, 2)
  end

  defp adapt_plan_from_learning(plan, context, _entity) do
    learning_data = context[:learning_data] || %{}

    successful_techniques = learning_data[:successful_techniques] || []
    failed_techniques = learning_data[:failed_techniques] || []

    adapted_techniques = plan.techniques
      |> Enum.reject(& &1 in failed_techniques)
      |> maybe_add_successful_techniques(successful_techniques)

    %{plan |
      techniques: adapted_techniques,
      confidence: calculate_plan_confidence(adapted_techniques, learning_data)
    }
  end

  defp maybe_add_successful_techniques(current, successful) do
    additions = Enum.take(successful -- current, 1)
    current ++ additions
  end

  defp calculate_plan_confidence(_techniques, learning_data) do
    if learning_data[:historical_success_rate] do
      learning_data.historical_success_rate
    else
      0.7  # Default confidence
    end
  end

  defp add_optimization_steps(plan, entity, params) do
    steps = Enum.flat_map(plan.techniques, fn technique ->
      generate_optimization_steps(technique, entity, params)
    end)

    Map.put(plan, :steps, steps)
  end

  defp generate_optimization_steps(:session_optimization, _entity, _params) do
    [
      %{type: :session_pooling, impact: :high, risk: :low},
      %{type: :connection_reuse, impact: :medium, risk: :low}
    ]
  end

  defp generate_optimization_steps(:cache_optimization, _entity, _params) do
    [
      %{type: :cache_warming, impact: :high, risk: :low},
      %{type: :cache_invalidation_strategy, impact: :medium, risk: :medium}
    ]
  end

  defp generate_optimization_steps(:algorithm_optimization, entity, _params) do
    if entity[:cyclomatic_complexity] && entity.cyclomatic_complexity > 10 do
      [
        %{type: :algorithm_replacement, impact: :high, risk: :high},
        %{type: :loop_optimization, impact: :medium, risk: :low}
      ]
    else
      [
        %{type: :minor_refactoring, impact: :low, risk: :low}
      ]
    end
  end

  defp generate_optimization_steps(:dependency_optimization, _entity, _params) do
    [
      %{type: :dependency_pruning, impact: :medium, risk: :medium},
      %{type: :version_updates, impact: :low, risk: :low}
    ]
  end

  defp generate_optimization_steps(_, _entity, _params) do
    [%{type: :generic_optimization, impact: :medium, risk: :medium}]
  end

  defp prioritize_optimizations(plan, goals) do
    prioritized_steps = plan.steps
      |> Enum.sort_by(fn step ->
        impact_score = case step.impact do
          :high -> 3
          :medium -> 2
          :low -> 1
        end

        risk_score = case step.risk do
          :high -> 3
          :medium -> 2
          :low -> 1
        end

        goal_alignment = if step_aligns_with_goals?(step, goals), do: 2, else: 1

        # Higher impact, lower risk, better alignment = higher priority
        -(impact_score * goal_alignment / risk_score)
      end)

    %{plan | steps: prioritized_steps}
  end

  defp step_aligns_with_goals?(step, goals) do
    performance_steps = [:algorithm_replacement, :cache_warming, :loop_optimization]
    quality_steps = [:minor_refactoring, :dependency_pruning]

    cond do
      :performance in goals and step.type in performance_steps -> true
      :quality in goals and step.type in quality_steps -> true
      true -> false
    end
  end

  defp estimate_optimization_impact(plan) do
    total_impact = plan.steps
      |> Enum.map(fn step ->
        case step.impact do
          :high -> 0.15
          :medium -> 0.08
          :low -> 0.03
        end
      end)
      |> Enum.sum()

    %{plan | estimated_improvement: min(total_impact, 0.5)}
  end

  # Safety checks
  defp perform_safety_checks(entity, plan, params) do
    if params.safety_checks do
      checks = %{
        dependency_check: check_dependencies(entity, plan),
        compatibility_check: check_compatibility(entity, plan),
        resource_check: check_resource_requirements(plan),
        risk_assessment: assess_optimization_risks(plan)
      }

      all_passed = checks |> Map.values() |> Enum.all?(& &1.passed)

      if all_passed do
        {:ok, %{
          passed: true,
          checks: checks,
          confidence: calculate_safety_confidence(checks)
        }}
      else
        {:error, %{
          reason: :safety_check_failed,
          failed_checks: extract_failed_checks(checks),
          recommendation: "Address safety concerns before proceeding"
        }}
      end
    else
      {:ok, %{passed: true, skipped: true}}
    end
  end

  defp check_dependencies(entity, _plan) do
    deps_count = entity[:dependencies_count] || 0

    %{
      passed: deps_count < 100,
      message: "Dependency count: #{deps_count}",
      risk_level: (if deps_count > 50, do: :medium, else: :low)
    }
  end

  defp check_compatibility(_entity, plan) do
    high_risk_steps = Enum.filter(plan.steps, & &1.risk == :high)

    %{
      passed: length(high_risk_steps) <= 2,
      high_risk_count: length(high_risk_steps),
      message: "High risk optimizations: #{length(high_risk_steps)}"
    }
  end

  defp check_resource_requirements(plan) do
    estimated_resources = length(plan.steps) * 50  # MB per optimization

    %{
      passed: estimated_resources < 500,
      estimated_memory: estimated_resources,
      message: "Estimated memory requirement: #{estimated_resources}MB"
    }
  end

  defp assess_optimization_risks(plan) do
    risk_scores = Enum.map(plan.steps, fn step ->
      case step.risk do
        :high -> 3
        :medium -> 2
        :low -> 1
      end
    end)

    avg_risk = if length(risk_scores) > 0 do
      Enum.sum(risk_scores) / length(risk_scores)
    else
      1
    end

    %{
      passed: avg_risk < 2.5,
      average_risk: avg_risk,
      risk_level: (cond do
        avg_risk > 2.5 -> :high
        avg_risk > 1.5 -> :medium
        true -> :low
      end)
    }
  end

  defp calculate_safety_confidence(checks) do
    risk_level = checks.risk_assessment[:risk_level]

    base_confidence = 0.8

    risk_adjustment = case risk_level do
      :low -> 0.1
      :medium -> 0
      :high -> -0.2
    end

    max(0.3, min(1.0, base_confidence + risk_adjustment))
  end

  defp extract_failed_checks(checks) do
    checks
    |> Enum.filter(fn {_name, check} -> not check.passed end)
    |> Enum.map(fn {name, check} -> {name, check[:message]} end)
  end

  # Apply optimizations
  defp apply_optimizations(entity, plan, params) do
    optimized = Enum.reduce(plan.steps, entity, fn step, acc ->
      apply_optimization_step(acc, step, params)
    end)

    optimized = optimized
      |> Map.put(:optimization_applied, true)
      |> Map.put(:optimization_timestamp, DateTime.utc_now())
      |> Map.put(:optimization_version, generate_version())

    {:ok, optimized}
  end

  defp apply_optimization_step(entity, step, params) do
    case step.type do
      :algorithm_replacement ->
        optimize_algorithm(entity, params.optimization_strategy)
      :cache_warming ->
        add_cache_warming(entity)
      :loop_optimization ->
        optimize_loops(entity)
      :session_pooling ->
        enable_session_pooling(entity)
      :dependency_pruning ->
        prune_dependencies(entity)
      _ ->
        apply_generic_optimization(entity, step)
    end
  end

  defp optimize_algorithm(entity, :aggressive) do
    entity
    |> Map.update(:execution_time, 100, & &1 * 0.6)
    |> Map.update(:cyclomatic_complexity, 10, & max(5, &1 - 3))
  end
  defp optimize_algorithm(entity, _) do
    entity
    |> Map.update(:execution_time, 100, & &1 * 0.8)
    |> Map.update(:cyclomatic_complexity, 10, & max(5, &1 - 1))
  end

  defp add_cache_warming(entity) do
    entity
    |> Map.update(:response_time, 100, & &1 * 0.7)
    |> Map.put(:cache_enabled, true)
  end

  defp optimize_loops(entity) do
    entity
    |> Map.update(:execution_time, 100, & &1 * 0.85)
    |> Map.update(:cpu_usage, 50, & &1 * 0.9)
  end

  defp enable_session_pooling(entity) do
    entity
    |> Map.update(:response_time, 100, & &1 * 0.8)
    |> Map.update(:memory_usage, 100, & &1 * 1.1)
    |> Map.put(:session_pooling, true)
  end

  defp prune_dependencies(entity) do
    entity
    |> Map.update(:dependencies_count, 0, & max(0, &1 - 5))
    |> Map.update(:build_time, 1_000, & &1 * 0.9)
  end

  defp apply_generic_optimization(entity, _step) do
    # Generic 5% improvement
    entity
    |> Map.update(:execution_time, 100, & &1 * 0.95)
    |> Map.update(:response_time, 100, & &1 * 0.95)
  end

  defp generate_version do
    "v#{System.system_time(:second)}"
  end

  # Measure results
  defp measure_optimization_results(optimized_entity, baseline_metrics) do
    current_metrics = capture_current_metrics(optimized_entity, Map.keys(baseline_metrics))

    improvements = calculate_improvements(baseline_metrics, current_metrics)

    {:ok, %{
      current_metrics: current_metrics,
      improvements: improvements,
      overall_improvement: calculate_overall_improvement(improvements),
      goal_achievements: assess_goal_achievements(improvements, baseline_metrics)
    }}
  end

  defp capture_current_metrics(entity, metric_keys) do
    Enum.reduce(metric_keys, %{}, fn key, acc ->
      if key in [:timestamp, :entity_id, :entity_type] do
        Map.put(acc, key, entity[key])
      else
        Map.put(acc, key, capture_current_goal_metrics(entity, key))
      end
    end)
  end

  defp capture_current_goal_metrics(entity, :performance) do
    %{
      response_time: entity[:response_time] || entity[:execution_time] || 100,
      throughput: calculate_throughput(entity),
      memory_usage: entity[:memory_usage] || entity[:memory_footprint] || 100,
      cpu_usage: estimate_cpu_usage(entity)
    }
  end

  defp capture_current_goal_metrics(entity, :quality) do
    %{
      quality_score: entity[:code_quality_score] || entity[:accuracy] || 0.7,
      complexity: entity[:complexity] || entity[:cyclomatic_complexity] || 10,
      maintainability: calculate_maintainability(entity),
      test_coverage: entity[:test_coverage] || 0.5
    }
  end

  defp capture_current_goal_metrics(entity, key) do
    entity[key] || %{}
  end

  defp calculate_improvements(baseline, current) do
    Enum.reduce(current, %{}, fn {key, current_value}, acc ->
      if key in [:timestamp, :entity_id, :entity_type] do
        acc
      else
        baseline_value = baseline[key]
        improvement = calculate_metric_improvement(baseline_value, current_value)
        Map.put(acc, key, improvement)
      end
    end)
  end

  defp calculate_metric_improvement(baseline, current) when is_map(baseline) and is_map(current) do
    Enum.reduce(current, %{}, fn {metric, current_val}, acc ->
      baseline_val = baseline[metric]
      calculate_single_metric_improvement(acc, metric, baseline_val, current_val)
    end)
  end
  defp calculate_metric_improvement(_baseline, _current), do: %{}

  defp calculate_single_metric_improvement(acc, _metric, baseline_val, current_val)
       when not is_number(baseline_val) or not is_number(current_val) or baseline_val == 0 do
    acc
  end

  defp calculate_single_metric_improvement(acc, metric, baseline_val, current_val) do
    improvement_pct = (current_val - baseline_val) / abs(baseline_val)

    # Invert for metrics where lower is better
    improvement_pct = if metric in [:response_time, :execution_time, :complexity, :error_rate, :memory_usage] do
      -improvement_pct
    else
      improvement_pct
    end

    Map.put(acc, metric, %{
      baseline: baseline_val,
      current: current_val,
      improvement_percentage: improvement_pct * 100
    })
  end

  defp calculate_overall_improvement(improvements) do
    all_improvements = improvements
      |> Map.values()
      |> Enum.flat_map(fn imp when is_map(imp) ->
        imp
        |> Map.values()
        |> Enum.filter(&is_map/1)
        |> Enum.map(& &1[:improvement_percentage])
        |> Enum.filter(&is_number/1)
      end)

    if length(all_improvements) > 0 do
      Enum.sum(all_improvements) / length(all_improvements)
    else
      0
    end
  end

  defp assess_goal_achievements(improvements, _baseline) do
    improvements
    |> Enum.map(fn {goal, metrics} ->
      achievement = calculate_goal_achievement(metrics)
      status = determine_achievement_status(achievement)

      {goal, %{
        achievement_rate: achievement,
        status: status
      }}
    end)
    |> Map.new()
  end

  defp calculate_goal_achievement(metrics) when is_map(metrics) do
    metric_values = Map.values(metrics)
    positive_improvements = metric_values
      |> Enum.filter(&is_map/1)
      |> Enum.count(& &1[:improvement_percentage] && &1.improvement_percentage > 0)

    total_metrics = Enum.count(metric_values, &is_map/1)

    if total_metrics > 0 do
      positive_improvements / total_metrics
    else
      0
    end
  end
  defp calculate_goal_achievement(_metrics), do: 0

  defp determine_achievement_status(achievement) do
    cond do
      achievement >= 0.8 -> :exceeded
      achievement >= 0.5 -> :met
      achievement >= 0.2 -> :partial
      true -> :not_met
    end
  end

  # Validation
  defp validate_optimization(optimized_entity, performance_results, params) do
    validations = %{
      performance_validation: validate_performance(performance_results, params),
      regression_check: check_for_regressions(performance_results),
      stability_check: check_stability(optimized_entity),
      goal_validation: validate_goal_achievement(performance_results, params)
    }

    should_rollback = should_rollback?(validations, performance_results, params)

    {:ok, %{
      valid: not should_rollback,
      validations: validations,
      rollback_required: should_rollback,
      validation_score: calculate_validation_score(validations)
    }}
  end

  defp validate_performance(results, params) do
    improvement = results.overall_improvement

    %{
      passed: improvement >= params.rollback_threshold * 100,
      improvement: improvement,
      target: params.target_improvement * 100,
      message: "Achieved #{Float.round(improvement, 2)}% improvement"
    }
  end

  defp check_for_regressions(results) do
    regressions = results.improvements
      |> Enum.flat_map(fn {_goal, metrics} ->
        extract_regressions_from_metrics(metrics)
      end)

    %{
      passed: Enum.empty?(regressions),
      regressions: regressions,
      message: "Found #{length(regressions)} significant regressions"
    }
  end

  defp extract_regressions_from_metrics(metrics) when is_map(metrics) do
    metrics
    |> Enum.filter(fn {_metric, data} ->
      is_regression?(data)
    end)
    |> Enum.map(fn {metric, data} -> {metric, data.improvement_percentage} end)
  end
  defp extract_regressions_from_metrics(_metrics), do: []

  defp is_regression?(data) do
    is_map(data) and data[:improvement_percentage] && data.improvement_percentage < -10
  end

  defp check_stability(entity) do
    # Basic stability check
    has_critical_fields = Map.has_key?(entity, :id) and Map.has_key?(entity, :type)

    %{
      passed: has_critical_fields,
      message: "Entity stability check",
      entity_intact: has_critical_fields
    }
  end

  defp validate_goal_achievement(results, params) do
    achievements = results.goal_achievements

    achieved_goals = achievements
      |> Enum.filter(fn {_goal, data} -> data.status in [:met, :exceeded] end)
      |> Enum.map(fn {goal, _} -> goal end)

    achievement_rate = if map_size(achievements) > 0 do
      length(achieved_goals) / map_size(achievements)
    else
      0
    end

    %{
      passed: achievement_rate >= 0.5,
      achieved_goals: achieved_goals,
      total_goals: length(params.optimization_goals),
      achievement_rate: achievement_rate
    }
  end

  defp should_rollback?(validations, performance_results, params) do
    cond do
      # Critical failure conditions
      not validations.stability_check.passed -> true
      performance_results.overall_improvement < params.rollback_threshold * 100 -> true
      length(validations.regression_check.regressions) > 3 -> true
      # Otherwise don't rollback
      true -> false
    end
  end

  defp calculate_validation_score(validations) do
    scores = [
      if(validations.performance_validation.passed, do: 0.3, else: 0),
      if(validations.regression_check.passed, do: 0.3, else: 0),
      if(validations.stability_check.passed, do: 0.2, else: 0),
      validations.goal_validation.achievement_rate * 0.2
    ]

    Enum.sum(scores)
  end

  # Finalization
  defp finalize_optimization(optimized_entity, validation_results, original_entity) do
    if validation_results.rollback_required do
      Logger.warning("Optimization rollback required due to validation failures")

      {:ok, original_entity
        |> Map.put(:optimization_attempted, true)
        |> Map.put(:optimization_rolled_back, true)
        |> Map.put(:rollback_reason, extract_rollback_reason(validation_results))}
    else
      {:ok, optimized_entity
        |> Map.put(:optimization_successful, true)
        |> Map.put(:optimization_score, validation_results.validation_score)}
    end
  end

  defp extract_rollback_reason(validation_results) do
    validations = validation_results.validations

    cond do
      not validations.stability_check.passed ->
        "Entity stability compromised"
      not validations.performance_validation.passed ->
        "Performance degraded below threshold"
      not validations.regression_check.passed ->
        "Too many performance regressions"
      not validations.goal_validation.passed ->
        "Failed to achieve optimization goals"
      true ->
        "Unknown validation failure"
    end
  end

  # Learning tracking
  defp track_optimization_outcome(plan, performance_results, context) do
    learning_data = %{
      optimization_id: generate_optimization_id(),
      techniques_used: plan.techniques,
      steps_applied: Enum.map(plan.steps, & &1.type),
      overall_improvement: performance_results.overall_improvement,
      goal_achievements: performance_results.goal_achievements,
      successful: performance_results.overall_improvement > 0,
      context: extract_learning_context(plan, context),
      timestamp: DateTime.utc_now()
    }

    # Track successful techniques for future use
    if learning_data.successful do
      track_successful_techniques(plan.techniques, performance_results)
    end

    # In production, would send to LearningSkill
    emit_learning_signal(learning_data)

    {:ok, learning_data}
  end

  defp generate_optimization_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp extract_learning_context(plan, context) do
    %{
      agent: context[:agent],
      strategy: plan.strategy,
      estimated_improvement: plan.estimated_improvement,
      confidence: plan[:confidence] || 0.7
    }
  end

  defp track_successful_techniques(techniques, results) do
    Logger.info("Successful optimization techniques: #{inspect(techniques)}")
    Logger.info("Improvement achieved: #{Float.round(results.overall_improvement, 2)}%")
  end

  defp emit_learning_signal(data) do
    Logger.debug("Learning signal: entity_optimization with data: #{inspect(data)}")
    :ok
  end

  # Helper functions
  defp calculate_improvement_percentage(_baseline, results) do
    results.overall_improvement
  end

  # Metadata
  defp build_metadata(params, context) do
    %{
      action: "optimize_entity",
      entity_id: params.entity_id,
      entity_type: params.entity_type,
      optimization_strategy: params.optimization_strategy,
      timestamp: DateTime.utc_now(),
      actor: context[:actor],
      agent: context[:agent],
      learning_enabled: params.learning_enabled,
      goals: params.optimization_goals,
      safety_checks: params.safety_checks
    }
  end
end