defmodule RubberDuck.Actions.Core.AnalyzeEntity do
  @moduledoc """
  Core agentic action for analyzing entities with learning from outcomes and adaptive insights.

  This action provides:
  - Multi-domain analysis leveraging appropriate skills based on entity type
  - Learning integration to improve analysis quality based on historical outcomes
  - Goal-driven analysis focusing on agent goals and objectives
  - Adaptive analysis adjusting depth and focus based on learning insights
  - Pattern recognition and trend detection across entity history
  """

  use Jido.Action,
    name: "analyze_entity",
    description: "Analyzes entities with learning from outcomes",
    schema: [
      entity_id: [type: :string, required: true],
      entity_type: [type: :atom, required: true, values: [:user, :project, :code_file, :analysis]],
      analysis_depth: [type: :atom, default: :moderate, values: [:shallow, :moderate, :deep]],
      analysis_goals: [type: {:list, :atom}, default: []],
      learning_context: [type: :map, default: %{}],
      adaptive_analysis: [type: :boolean, default: true],
      historical_data: [type: {:list, :map}, default: []],
      skill_selection: [type: :atom, default: :auto, values: [:auto, :manual]],
      preferred_skills: [type: {:list, :atom}, default: []]
    ]

  alias RubberDuck.Skills.{
    UserManagementSkill,
    ProjectManagementSkill,
    CodeAnalysisSkill,
    LearningSkill
  }

  require Logger

  @impl true
  def run(params, context) do
    with {:ok, entity} <- fetch_entity(params.entity_id, params.entity_type),
         {:ok, enriched_entity} <- enrich_with_history(entity, params.historical_data),
         {:ok, analysis_plan} <- create_adaptive_analysis_plan(enriched_entity, params, context),
         {:ok, analysis_results} <- execute_analysis(enriched_entity, analysis_plan, context),
         {:ok, insights} <-
           generate_goal_driven_insights(analysis_results, params.analysis_goals),
         {:ok, patterns} <- detect_patterns(analysis_results, params.historical_data),
         {:ok, predictions} <- generate_predictions(patterns, analysis_results),
         {:ok, recommendations} <- generate_recommendations(insights, patterns, predictions),
         {:ok, learning_data} <- track_analysis_outcome(analysis_results, insights, context) do
      {:ok,
       %{
         entity: entity,
         analysis_results: analysis_results,
         insights: insights,
         patterns: patterns,
         predictions: predictions,
         recommendations: recommendations,
         learning_data: learning_data,
         analysis_plan: analysis_plan,
         confidence_score: calculate_analysis_confidence(analysis_results, learning_data),
         metadata: build_metadata(params, context)
       }}
    end
  end

  # Entity fetching and enrichment
  defp fetch_entity(entity_id, entity_type) do
    # In production, would fetch from appropriate context
    case entity_type do
      :user -> fetch_user_entity(entity_id)
      :project -> fetch_project_entity(entity_id)
      :code_file -> fetch_code_file_entity(entity_id)
      :analysis -> fetch_analysis_entity(entity_id)
    end
  end

  defp fetch_user_entity(id) do
    {:ok,
     %{
       id: id,
       type: :user,
       email: "user@example.com",
       username: "testuser",
       sessions: [],
       activity_level: :moderate,
       created_at: DateTime.utc_now()
     }}
  end

  defp fetch_project_entity(id) do
    {:ok,
     %{
       id: id,
       type: :project,
       name: "Test Project",
       description: "A test project",
       status: :active,
       quality_score: 0.75,
       complexity: 50,
       created_at: DateTime.utc_now()
     }}
  end

  defp fetch_code_file_entity(id) do
    {:ok,
     %{
       id: id,
       type: :code_file,
       path: "/lib/example.ex",
       content: "defmodule Example do\nend",
       language: :elixir,
       lines_of_code: 100,
       complexity: 10,
       created_at: DateTime.utc_now()
     }}
  end

  defp fetch_analysis_entity(id) do
    {:ok,
     %{
       id: id,
       type: :analysis,
       analysis_type: :quality,
       target: "project_123",
       status: :completed,
       results: %{score: 0.8},
       created_at: DateTime.utc_now()
     }}
  end

  defp enrich_with_history(entity, historical_data) do
    enriched =
      entity
      |> Map.put(:history_count, length(historical_data))
      |> Map.put(:has_history, length(historical_data) > 0)
      |> Map.put(:historical_trends, calculate_historical_trends(historical_data))
      |> Map.put(:change_frequency, calculate_change_frequency(historical_data))

    {:ok, enriched}
  end

  defp calculate_historical_trends(historical_data) when length(historical_data) < 2 do
    %{insufficient_data: true}
  end

  defp calculate_historical_trends(historical_data) do
    %{
      quality_trend: extract_trend(historical_data, :quality),
      complexity_trend: extract_trend(historical_data, :complexity),
      activity_trend: extract_trend(historical_data, :activity)
    }
  end

  defp extract_trend(data, field) do
    values =
      data
      |> Enum.map(fn d -> d[field] end)
      |> Enum.filter(& &1)

    if length(values) >= 2 do
      first_half = Enum.take(values, div(length(values), 2))
      second_half = Enum.drop(values, div(length(values), 2))

      first_avg = Enum.sum(first_half) / max(length(first_half), 1)
      second_avg = Enum.sum(second_half) / max(length(second_half), 1)

      cond do
        second_avg > first_avg * 1.1 -> :increasing
        second_avg < first_avg * 0.9 -> :decreasing
        true -> :stable
      end
    else
      :unknown
    end
  end

  defp calculate_change_frequency(historical_data) when length(historical_data) < 2, do: 0

  defp calculate_change_frequency(historical_data) do
    changes =
      historical_data
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.count(fn [prev, curr] -> significantly_changed?(prev, curr) end)

    changes / max(length(historical_data) - 1, 1)
  end

  defp significantly_changed?(prev, curr) do
    # Check if significant fields have changed
    prev[:quality] != curr[:quality] or
      prev[:status] != curr[:status] or
      abs((prev[:complexity] || 0) - (curr[:complexity] || 0)) > 10
  end

  # Adaptive analysis planning
  defp create_adaptive_analysis_plan(entity, params, _context) do
    base_plan = create_base_analysis_plan(entity.type, params.analysis_depth)

    adapted_plan =
      if params.adaptive_analysis do
        adapt_plan_from_learning(base_plan, params.learning_context, entity)
      else
        base_plan
      end

    final_plan = %{
      adapted_plan
      | skills: select_analysis_skills(entity.type, params),
        focus_areas: determine_focus_areas(entity, params.analysis_goals),
        metrics_to_collect: determine_metrics(entity.type, params.analysis_depth),
        analysis_techniques: select_techniques(entity.type, params.analysis_depth)
    }

    {:ok, final_plan}
  end

  defp create_base_analysis_plan(entity_type, depth) do
    %{
      entity_type: entity_type,
      depth: depth,
      base_duration: estimate_duration(depth),
      required_checks: get_required_checks(entity_type),
      optional_checks: get_optional_checks(entity_type, depth)
    }
  end

  defp adapt_plan_from_learning(plan, learning_context, entity) do
    adaptations = %{
      adjusted_depth: adjust_depth_from_learning(plan.depth, learning_context),
      priority_checks: prioritize_checks_from_learning(plan.required_checks, learning_context),
      skip_checks: identify_checks_to_skip(learning_context, entity),
      additional_checks: suggest_additional_checks(learning_context, entity)
    }

    Map.merge(plan, adaptations)
  end

  defp adjust_depth_from_learning(current_depth, learning_context) do
    if learning_context[:high_value_entity] do
      :deep
    else
      case learning_context[:previous_accuracy] do
        acc when acc < 0.6 -> upgrade_depth(current_depth)
        acc when acc > 0.9 -> downgrade_depth(current_depth)
        _ -> current_depth
      end
    end
  end

  defp upgrade_depth(:shallow), do: :moderate
  defp upgrade_depth(:moderate), do: :deep
  defp upgrade_depth(depth), do: depth

  defp downgrade_depth(:deep), do: :moderate
  defp downgrade_depth(:moderate), do: :shallow
  defp downgrade_depth(depth), do: depth

  defp prioritize_checks_from_learning(checks, learning_context) do
    priority_areas = learning_context[:priority_areas] || []

    Enum.sort_by(checks, fn check ->
      if check in priority_areas, do: 0, else: 1
    end)
  end

  defp identify_checks_to_skip(learning_context, _entity) do
    skippable = []

    # Skip certain checks if they've been consistently passing
    if learning_context[:consistent_passes] do
      [:basic_validation | skippable]
    else
      skippable
    end
  end

  defp suggest_additional_checks(learning_context, entity) do
    additional = []

    # Add checks based on recent failures
    additional =
      if learning_context[:recent_failures] do
        [:deep_integrity_check | additional]
      else
        additional
      end

    # Add trend analysis if entity has history
    if entity[:has_history] do
      [:trend_analysis | additional]
    else
      additional
    end
  end

  defp estimate_duration(:shallow), do: 100
  defp estimate_duration(:moderate), do: 500
  defp estimate_duration(:deep), do: 2_000

  defp get_required_checks(entity_type) do
    case entity_type do
      :user -> [:authentication, :authorization, :activity]
      :project -> [:structure, :dependencies, :quality]
      :code_file -> [:syntax, :complexity, :patterns]
      :analysis -> [:completeness, :accuracy, :relevance]
    end
  end

  defp get_optional_checks(entity_type, depth) do
    base_checks =
      case entity_type do
        :user -> [:preferences, :behavior_patterns]
        :project -> [:performance, :security]
        :code_file -> [:test_coverage, :documentation]
        :analysis -> [:confidence, :alternatives]
      end

    case depth do
      :shallow -> []
      :moderate -> Enum.take(base_checks, 1)
      :deep -> base_checks
    end
  end

  defp select_analysis_skills(entity_type, params) do
    if params.skill_selection == :manual and length(params.preferred_skills) > 0 do
      params.preferred_skills
    else
      case entity_type do
        :user -> [UserManagementSkill, LearningSkill]
        :project -> [ProjectManagementSkill, LearningSkill]
        :code_file -> [CodeAnalysisSkill, LearningSkill]
        :analysis -> [LearningSkill]
      end
    end
  end

  defp determine_focus_areas(entity, analysis_goals) do
    base_areas =
      case entity.type do
        :user -> [:engagement, :satisfaction]
        :project -> [:quality, :maintainability]
        :code_file -> [:correctness, :performance]
        :analysis -> [:accuracy, :insights]
      end

    # Combine with specific goals
    goal_areas = Enum.map(analysis_goals, &goal_to_focus_area/1)

    Enum.uniq(base_areas ++ goal_areas)
  end

  defp goal_to_focus_area(:quality), do: :code_quality
  defp goal_to_focus_area(:performance), do: :performance_metrics
  defp goal_to_focus_area(:security), do: :security_vulnerabilities
  defp goal_to_focus_area(:usability), do: :user_experience
  defp goal_to_focus_area(_), do: :general

  defp determine_metrics(entity_type, depth) do
    base_metrics =
      case entity_type do
        :user -> [:session_count, :activity_frequency, :engagement_score]
        :project -> [:loc, :complexity_score, :test_coverage]
        :code_file -> [:cyclomatic_complexity, :coupling, :cohesion]
        :analysis -> [:execution_time, :accuracy_score, :confidence_level]
      end

    case depth do
      :shallow -> Enum.take(base_metrics, 1)
      :moderate -> Enum.take(base_metrics, 2)
      :deep -> base_metrics
    end
  end

  defp select_techniques(entity_type, depth) do
    techniques =
      case entity_type do
        :user -> [:behavioral_analysis, :pattern_matching, :anomaly_detection]
        :project -> [:dependency_analysis, :complexity_analysis, :quality_assessment]
        :code_file -> [:static_analysis, :pattern_detection, :smell_detection]
        :analysis -> [:result_validation, :trend_analysis, :correlation_analysis]
      end

    case depth do
      :shallow -> [List.first(techniques)]
      :moderate -> Enum.take(techniques, 2)
      :deep -> techniques
    end
  end

  # Analysis execution
  defp execute_analysis(entity, plan, context) do
    # Execute required checks
    required_results =
      plan.required_checks
      |> Enum.map(fn check ->
        {check, execute_check(check, entity, context)}
      end)
      |> Map.new()

    # Execute optional checks
    optional_results =
      (plan.optional_checks || [])
      |> Enum.map(fn check ->
        {check, execute_check(check, entity, context)}
      end)
      |> Map.new()

    # Execute analysis techniques
    technique_results =
      plan.analysis_techniques
      |> Enum.map(fn technique ->
        {technique, apply_technique(technique, entity, context)}
      end)
      |> Map.new()

    # Collect metrics
    metrics =
      plan.metrics_to_collect
      |> Enum.map(fn metric ->
        {metric, collect_metric(metric, entity)}
      end)
      |> Map.new()

    {:ok,
     %{
       required_checks: required_results,
       optional_checks: optional_results,
       techniques_applied: technique_results,
       metrics: metrics,
       entity_score: calculate_entity_score(required_results, metrics),
       analysis_quality: assess_analysis_quality(required_results, optional_results),
       completeness: calculate_completeness(required_results, optional_results)
     }}
  end

  defp execute_check(check, entity, _context) do
    # Simulate check execution
    case check do
      :authentication -> %{passed: true, details: "Valid authentication"}
      :authorization -> %{passed: true, details: "Proper authorization"}
      :structure -> %{passed: entity[:status] == :active, details: "Structure check"}
      :dependencies -> %{passed: true, issues: []}
      :syntax -> %{passed: true, errors: []}
      :complexity -> %{passed: entity[:complexity] < 100, score: entity[:complexity]}
      _ -> %{passed: true, details: "Check completed"}
    end
  end

  defp apply_technique(technique, _entity, _context) do
    case technique do
      :behavioral_analysis ->
        %{patterns: ["regular_usage", "power_user"], anomalies: []}

      :dependency_analysis ->
        %{direct: 5, transitive: 12, circular: 0}

      :static_analysis ->
        %{issues: [], warnings: ["unused_variable"], suggestions: ["use_pattern_matching"]}

      :result_validation ->
        %{valid: true, confidence: 0.95}

      _ ->
        %{result: "Technique applied", status: :success}
    end
  end

  defp collect_metric(metric, entity) do
    case metric do
      :session_count -> entity[:sessions] |> length()
      :activity_frequency -> calculate_activity_frequency(entity)
      :engagement_score -> calculate_engagement_score(entity)
      :loc -> entity[:lines_of_code] || 0
      :complexity_score -> entity[:complexity] || 0
      :test_coverage -> entity[:test_coverage] || 0.0
      :cyclomatic_complexity -> entity[:complexity] || 1
      :execution_time -> 100
      :accuracy_score -> 0.85
      _ -> 0
    end
  end

  defp calculate_activity_frequency(entity) do
    case entity[:activity_level] do
      :high -> 0.9
      :moderate -> 0.5
      :low -> 0.2
      _ -> 0.1
    end
  end

  defp calculate_engagement_score(entity) do
    base_score = calculate_activity_frequency(entity)

    # Adjust based on other factors
    if entity[:sessions] && length(entity.sessions) > 10 do
      min(1.0, base_score * 1.2)
    else
      base_score
    end
  end

  defp calculate_entity_score(checks, metrics) do
    check_score =
      checks
      |> Map.values()
      |> Enum.count(& &1[:passed])
      |> Kernel./(max(map_size(checks), 1))

    metric_score =
      if map_size(metrics) > 0 do
        normalized_metrics =
          metrics
          |> Map.values()
          |> Enum.filter(&is_number/1)
          |> Enum.map(&normalize_metric/1)

        if length(normalized_metrics) > 0 do
          Enum.sum(normalized_metrics) / length(normalized_metrics)
        else
          0.5
        end
      else
        0.5
      end

    check_score * 0.6 + metric_score * 0.4
  end

  defp normalize_metric(value) when value < 0, do: 0.0
  defp normalize_metric(value) when value > 100, do: 1.0
  defp normalize_metric(value), do: value / 100

  defp assess_analysis_quality(required_results, optional_results) do
    total_checks = map_size(required_results) + map_size(optional_results)

    if total_checks > 0 do
      detailed_checks =
        Enum.count(required_results ++ optional_results, fn {_, result} ->
          Map.has_key?(result, :details) or Map.has_key?(result, :issues)
        end)

      %{
        detail_level: detailed_checks / total_checks,
        coverage: calculate_coverage_score(required_results, optional_results),
        reliability: calculate_reliability_score(required_results)
      }
    else
      %{detail_level: 0, coverage: 0, reliability: 0}
    end
  end

  defp calculate_coverage_score(required, optional) do
    required_coverage = if map_size(required) > 0, do: 1.0, else: 0.0
    optional_coverage = map_size(optional) * 0.2

    min(1.0, required_coverage + optional_coverage)
  end

  defp calculate_reliability_score(results) do
    if map_size(results) > 0 do
      confident_results =
        Enum.count(results, fn {_, r} ->
          r[:confidence] && r.confidence > 0.8
        end)

      confident_results / map_size(results)
    else
      0.5
    end
  end

  defp calculate_completeness(required_results, optional_results) do
    required_complete = Enum.all?(required_results, fn {_, r} -> r[:passed] != nil end)

    optional_ratio =
      if map_size(optional_results) > 0 do
        Enum.count(optional_results, fn {_, r} -> r[:passed] != nil end) /
          map_size(optional_results)
      else
        1.0
      end

    if required_complete do
      0.7 + optional_ratio * 0.3
    else
      optional_ratio * 0.5
    end
  end

  # Insight generation
  defp generate_goal_driven_insights(analysis_results, analysis_goals) do
    base_insights = generate_base_insights(analysis_results)
    goal_insights = generate_goal_specific_insights(analysis_results, analysis_goals)

    all_insights = base_insights ++ goal_insights

    {:ok,
     %{
       insights: prioritize_insights(all_insights),
       insight_count: length(all_insights),
       high_priority_count: Enum.count(all_insights, &(&1.priority == :high))
     }}
  end

  defp generate_base_insights(results) do
    insights = []

    # Check for failed checks
    failed_checks =
      results.required_checks
      |> Enum.filter(fn {_, r} -> r[:passed] == false end)
      |> Enum.map(fn {check, _} -> check end)

    insights =
      if length(failed_checks) > 0 do
        [
          %{
            type: :critical,
            priority: :high,
            title: "Failed critical checks",
            description: "The following checks failed: #{Enum.join(failed_checks, ", ")}",
            recommendation: "Address these issues immediately"
          }
          | insights
        ]
      else
        insights
      end

    # Check for low scores
    if results.entity_score < 0.5 do
      [
        %{
          type: :warning,
          priority: :medium,
          title: "Low entity score",
          description: "Entity score is #{Float.round(results.entity_score, 2)}",
          recommendation: "Review entity configuration and quality"
        }
        | insights
      ]
    else
      insights
    end
  end

  defp generate_goal_specific_insights(results, goals) do
    Enum.flat_map(goals, fn goal ->
      case goal do
        :quality ->
          analyze_quality_insights(results)

        :performance ->
          analyze_performance_insights(results)

        :security ->
          analyze_security_insights(results)

        _ ->
          []
      end
    end)
  end

  defp analyze_quality_insights(results) do
    quality_metrics = [:complexity_score, :test_coverage, :code_quality]

    quality_issues =
      Enum.filter(quality_metrics, fn metric ->
        value = get_in(results, [:metrics, metric])
        value && value < 0.6
      end)

    if length(quality_issues) > 0 do
      [
        %{
          type: :quality,
          priority: :medium,
          title: "Quality concerns detected",
          description: "Low scores in: #{Enum.join(quality_issues, ", ")}",
          recommendation: "Focus on improving code quality metrics"
        }
      ]
    else
      []
    end
  end

  defp analyze_performance_insights(results) do
    if execution_time = get_in(results, [:metrics, :execution_time]) do
      if execution_time > 1_000 do
        [
          %{
            type: :performance,
            priority: :high,
            title: "High execution time",
            description: "Execution took #{execution_time}ms",
            recommendation: "Optimize performance bottlenecks"
          }
        ]
      else
        []
      end
    else
      []
    end
  end

  defp analyze_security_insights(results) do
    security_issues =
      get_in(results, [:techniques_applied, :security_scan, :vulnerabilities]) || []

    if length(security_issues) > 0 do
      [
        %{
          type: :security,
          priority: :critical,
          title: "Security vulnerabilities found",
          description: "#{length(security_issues)} security issues detected",
          recommendation: "Address security vulnerabilities immediately"
        }
      ]
    else
      []
    end
  end

  defp prioritize_insights(insights) do
    Enum.sort_by(insights, fn insight ->
      priority_value =
        case insight.priority do
          :critical -> 0
          :high -> 1
          :medium -> 2
          :low -> 3
        end

      {priority_value, insight.type}
    end)
  end

  # Pattern detection
  defp detect_patterns(analysis_results, historical_data) do
    patterns = %{
      recurring_issues: find_recurring_issues(analysis_results, historical_data),
      improvement_areas: identify_improvement_areas(analysis_results, historical_data),
      stability_patterns: analyze_stability_patterns(historical_data),
      anomalies: detect_anomalies(analysis_results, historical_data)
    }

    {:ok, patterns}
  end

  defp find_recurring_issues(current_results, historical_data) do
    if length(historical_data) < 3 do
      []
    else
      current_issues = extract_issues(current_results)

      historical_issues =
        historical_data
        |> Enum.take(-5)
        |> Enum.flat_map(&extract_historical_issues/1)
        |> Enum.frequencies()

      historical_issues
      |> Enum.filter(fn {issue, count} -> count >= 3 and issue in current_issues end)
      |> Enum.map(fn {issue, count} ->
        %{
          issue: issue,
          frequency: count,
          persistence: "Occurred #{count} times in last 5 analyses"
        }
      end)
    end
  end

  defp extract_issues(results) do
    failed_checks =
      results.required_checks
      |> Enum.filter(fn {_, r} -> r[:passed] == false end)
      |> Enum.map(fn {check, _} -> check end)

    warnings = get_in(results, [:techniques_applied, :static_analysis, :warnings]) || []

    failed_checks ++ warnings
  end

  defp extract_historical_issues(historical_entry) do
    historical_entry[:issues] || []
  end

  defp identify_improvement_areas(current_results, historical_data) do
    if length(historical_data) < 2 do
      []
    else
      current_score = current_results.entity_score
      historical_scores = Enum.map(historical_data, &(&1[:score] || 0.5))

      avg_historical = Enum.sum(historical_scores) / max(length(historical_scores), 1)

      areas = []

      areas =
        if current_score < avg_historical * 0.9 do
          ["Overall quality declining" | areas]
        else
          areas
        end

      areas =
        if get_in(current_results, [:metrics, :complexity_score]) > 50 do
          ["High complexity needs attention" | areas]
        else
          areas
        end

      areas
    end
  end

  defp analyze_stability_patterns(historical_data) do
    if length(historical_data) < 5 do
      %{status: :insufficient_data}
    else
      scores = Enum.map(historical_data, &(&1[:score] || 0.5))
      variance = calculate_variance(scores)

      %{
        stability: if(variance < 0.1, do: :stable, else: :volatile),
        variance: variance,
        trend: calculate_trend(scores)
      }
    end
  end

  defp calculate_variance([]), do: 0

  defp calculate_variance(values) do
    mean = Enum.sum(values) / length(values)

    sum_squared_diff =
      values
      |> Enum.map(fn v -> :math.pow(v - mean, 2) end)
      |> Enum.sum()

    sum_squared_diff / length(values)
  end

  defp calculate_trend(values) when length(values) < 2, do: :unknown

  defp calculate_trend(values) do
    first_half_avg =
      values
      |> Enum.take(div(length(values), 2))
      |> Enum.sum()
      |> Kernel./(max(div(length(values), 2), 1))

    second_half_avg =
      values
      |> Enum.drop(div(length(values), 2))
      |> Enum.sum()
      |> Kernel./(max(length(values) - div(length(values), 2), 1))

    cond do
      second_half_avg > first_half_avg * 1.1 -> :improving
      second_half_avg < first_half_avg * 0.9 -> :declining
      true -> :stable
    end
  end

  defp detect_anomalies(current_results, historical_data) do
    if length(historical_data) < 5 do
      []
    else
      historical_scores = Enum.map(historical_data, &(&1[:score] || 0.5))
      mean = Enum.sum(historical_scores) / length(historical_scores)
      std_dev = :math.sqrt(calculate_variance(historical_scores))

      anomalies = []

      # Check if current score is an anomaly
      if abs(current_results.entity_score - mean) > 2 * std_dev do
        [
          %{
            type: :score_anomaly,
            value: current_results.entity_score,
            expected_range: {mean - std_dev, mean + std_dev},
            severity: :high
          }
          | anomalies
        ]
      else
        anomalies
      end
    end
  end

  # Prediction generation
  defp generate_predictions(patterns, analysis_results) do
    predictions = []

    # Predict based on patterns
    predictions =
      if patterns.stability_patterns[:trend] == :declining do
        [
          %{
            type: :quality_degradation,
            probability: 0.7,
            timeframe: "next 2 weeks",
            impact: :medium,
            preventive_action: "Implement quality gates"
          }
          | predictions
        ]
      else
        predictions
      end

    # Predict based on recurring issues
    predictions =
      if length(patterns.recurring_issues) > 2 do
        [
          %{
            type: :issue_persistence,
            probability: 0.8,
            timeframe: "ongoing",
            impact: :high,
            preventive_action: "Address root causes of recurring issues"
          }
          | predictions
        ]
      else
        predictions
      end

    # Predict based on current metrics
    predictions =
      if complexity = get_in(analysis_results, [:metrics, :complexity_score]) do
        if complexity > 75 do
          [
            %{
              type: :maintainability_risk,
              probability: 0.6,
              timeframe: "next month",
              impact: :medium,
              preventive_action: "Refactor complex components"
            }
            | predictions
          ]
        else
          predictions
        end
      else
        predictions
      end

    {:ok, predictions}
  end

  # Recommendation generation
  defp generate_recommendations(insights, patterns, predictions) do
    _recommendations = []

    # Recommendations from insights
    insight_recommendations =
      insights.insights
      |> Enum.filter(& &1[:recommendation])
      |> Enum.map(fn i ->
        %{
          source: :insight,
          priority: i.priority,
          action: i.recommendation,
          rationale: i.description
        }
      end)

    # Recommendations from patterns
    pattern_recommendations =
      if length(patterns.recurring_issues) > 0 do
        [
          %{
            source: :pattern,
            priority: :high,
            action: "Implement systematic fix for recurring issues",
            rationale: "Issues are recurring across multiple analyses"
          }
        ]
      else
        []
      end

    # Recommendations from predictions
    prediction_recommendations =
      predictions
      |> Enum.filter(&(&1.probability > 0.6))
      |> Enum.map(fn p ->
        %{
          source: :prediction,
          priority: if(p.impact == :high, do: :high, else: :medium),
          action: p.preventive_action,
          rationale: "#{p.probability * 100}% chance of #{p.type}"
        }
      end)

    all_recommendations =
      insight_recommendations ++ pattern_recommendations ++ prediction_recommendations

    {:ok,
     %{
       recommendations: Enum.take(all_recommendations, 5),
       total_count: length(all_recommendations)
     }}
  end

  # Learning tracking
  defp track_analysis_outcome(analysis_results, insights, context) do
    learning_data = %{
      analysis_id: generate_analysis_id(),
      entity_score: analysis_results.entity_score,
      insight_count: insights.insight_count,
      high_priority_insights: insights.high_priority_count,
      analysis_quality: analysis_results.analysis_quality,
      completeness: analysis_results.completeness,
      techniques_used: Map.keys(analysis_results.techniques_applied),
      context: extract_learning_context(context),
      timestamp: DateTime.utc_now()
    }

    # In production, would send to LearningSkill
    emit_learning_signal(learning_data)

    {:ok, learning_data}
  end

  defp generate_analysis_id do
    bytes = :crypto.strong_rand_bytes(8)
    bytes |> Base.encode16(case: :lower)
  end

  defp extract_learning_context(context) do
    %{
      agent: context[:agent],
      user: context[:user],
      environment: context[:environment] || :production
    }
  end

  defp emit_learning_signal(data) do
    Logger.debug("Learning signal: entity_analysis with data: #{inspect(data)}")
    :ok
  end

  # Confidence calculation
  defp calculate_analysis_confidence(analysis_results, learning_data) do
    base_confidence = analysis_results.completeness

    # Adjust based on analysis quality
    quality_adjustment =
      if analysis_results.analysis_quality[:reliability] do
        analysis_results.analysis_quality.reliability * 0.2
      else
        0
      end

    # Adjust based on learning data
    learning_adjustment =
      if learning_data.techniques_used && length(learning_data.techniques_used) > 2 do
        0.1
      else
        0
      end

    min(1.0, base_confidence + quality_adjustment + learning_adjustment)
  end

  # Metadata
  defp build_metadata(params, context) do
    %{
      action: "analyze_entity",
      entity_id: params.entity_id,
      entity_type: params.entity_type,
      analysis_depth: params.analysis_depth,
      timestamp: DateTime.utc_now(),
      actor: context[:actor],
      agent: context[:agent],
      adaptive_analysis: params.adaptive_analysis,
      goal_count: length(params.analysis_goals)
    }
  end
end
