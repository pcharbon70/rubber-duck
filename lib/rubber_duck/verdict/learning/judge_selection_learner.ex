defmodule RubberDuck.Verdict.Learning.JudgeSelectionLearner do
  @moduledoc """
  Specialized learning engine for optimizing judge selection and routing strategies.

  Learns from historical judge performance data, user feedback patterns, and 
  evaluation outcomes to continuously improve judge selection algorithms,
  specialization matching, and multi-agent coordination effectiveness.
  """

  require Logger

  @judge_types [:code_quality, :architecture, :security, :test_quality]
  @selection_strategies [
    :random,
    :round_robin,
    :specialization_based,
    :performance_weighted,
    :user_preference_based
  ]
  @optimization_objectives [
    :accuracy_optimization,
    :speed_optimization,
    :cost_optimization,
    :user_satisfaction_optimization
  ]

  @doc """
  Learn judge selection improvements from identified patterns.

  ## Parameters
  - `patterns` - Success/failure patterns related to judge selection
  - `options` - Learning options and configuration

  ## Returns
  - `{:ok, learning_result}` - Learning successful with adaptations
  - `{:error, reason}` - Learning failed
  """
  def learn_from_patterns(patterns, options \\ []) do
    Logger.info("Learning judge selection improvements from #{length(patterns)} patterns")

    case analyze_judge_selection_patterns(patterns) do
      {:ok, selection_analysis} ->
        case generate_selection_optimizations(selection_analysis, options) do
          {:ok, optimizations} ->
            effectiveness_predictions = predict_optimization_effectiveness(optimizations)

            learning_result = %{
              engine_name: :judge_selection_learner,
              adaptations: optimizations,
              effectiveness_predictions: effectiveness_predictions,
              learning_confidence: calculate_learning_confidence(optimizations),
              patterns_processed: length(patterns),
              learning_metadata: %{
                learner: :judge_selection_learner,
                version: "1.0.0",
                learned_at: DateTime.utc_now(),
                optimization_objectives: identify_optimization_objectives(patterns)
              }
            }

            {:ok, learning_result}

          {:error, reason} ->
            {:error, "Optimization generation failed: #{reason}"}
        end

      {:error, reason} ->
        {:error, "Pattern analysis failed: #{reason}"}
    end
  end

  @doc """
  Optimize judge routing based on real-time performance data.

  ## Parameters
  - `current_routing_data` - Current judge routing performance
  - `optimization_target` - Specific optimization objective
  - `options` - Optimization options

  ## Returns
  - `{:ok, routing_optimizations}` - Routing optimizations generated
  - `{:error, reason}` - Optimization failed
  """
  def optimize_judge_routing(current_routing_data, optimization_target, options \\ []) do
    Logger.info("Optimizing judge routing for target: #{optimization_target}")

    case analyze_current_routing_performance(current_routing_data, optimization_target) do
      {:ok, performance_analysis} ->
        case generate_routing_improvements(performance_analysis, optimization_target, options) do
          {:ok, improvements} ->
            routing_optimizations = %{
              optimization_target: optimization_target,
              routing_improvements: improvements,
              expected_performance_gain: calculate_expected_performance_gain(improvements),
              implementation_complexity: assess_routing_implementation_complexity(improvements),
              optimization_metadata: %{
                analyzer: :judge_routing_optimizer,
                optimized_at: DateTime.utc_now(),
                data_points_analyzed: length(current_routing_data)
              }
            }

            {:ok, routing_optimizations}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Update judge specialization weights based on performance feedback.

  ## Parameters
  - `judge_performance_feedback` - Feedback on individual judge performance
  - `options` - Update options

  ## Returns
  - `{:ok, weight_updates}` - Weight updates generated
  - `{:error, reason}` - Update failed
  """
  def update_specialization_weights(judge_performance_feedback, options \\ []) do
    Logger.info(
      "Updating judge specialization weights from #{length(judge_performance_feedback)} feedback items"
    )

    case analyze_judge_specialization_effectiveness(judge_performance_feedback) do
      {:ok, specialization_analysis} ->
        weight_updates = calculate_specialization_weight_updates(specialization_analysis)
        validation_metrics = validate_weight_updates(weight_updates)

        result = %{
          judge_weight_updates: weight_updates,
          validation_metrics: validation_metrics,
          expected_improvement: estimate_weight_update_improvement(weight_updates),
          update_confidence: calculate_weight_update_confidence(specialization_analysis),
          update_metadata: %{
            updater: :specialization_weight_updater,
            updated_at: DateTime.utc_now(),
            feedback_items_processed: length(judge_performance_feedback)
          }
        }

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Private Analysis Functions

  defp analyze_judge_selection_patterns(patterns) when is_list(patterns) do
    # Analyze patterns to extract judge selection insights
    selection_patterns = filter_judge_selection_patterns(patterns)

    if Enum.empty?(selection_patterns) do
      {:error, "No judge selection patterns found"}
    else
      analysis_result = %{
        successful_selections: extract_successful_selection_patterns(selection_patterns),
        failed_selections: extract_failed_selection_patterns(selection_patterns),
        judge_performance_correlations:
          analyze_judge_performance_correlations(selection_patterns),
        user_preference_patterns: extract_user_preference_patterns(selection_patterns),
        temporal_selection_patterns: analyze_temporal_selection_effectiveness(selection_patterns)
      }

      {:ok, analysis_result}
    end
  end

  defp generate_selection_optimizations(selection_analysis, options) do
    # Generate concrete optimization recommendations
    optimizations = []

    # Judge specialization optimizations
    optimizations = add_specialization_optimizations(selection_analysis, optimizations)

    # Performance-based routing optimizations
    optimizations = add_performance_routing_optimizations(selection_analysis, optimizations)

    # User preference-based optimizations
    optimizations = add_user_preference_optimizations(selection_analysis, optimizations)

    # Temporal optimization recommendations
    optimizations = add_temporal_optimizations(selection_analysis, optimizations)

    if Enum.empty?(optimizations) do
      {:error, "No viable optimizations identified"}
    else
      {:ok, optimizations}
    end
  end

  defp predict_optimization_effectiveness(optimizations) when is_list(optimizations) do
    Enum.map(optimizations, fn optimization ->
      %{
        optimization_id: Map.get(optimization, :id, generate_optimization_id()),
        optimization_type: optimization.optimization_type,
        predicted_effectiveness: calculate_optimization_effectiveness_prediction(optimization),
        confidence_interval: calculate_optimization_confidence_interval(optimization),
        risk_assessment: assess_optimization_risk(optimization),
        implementation_timeline: estimate_optimization_timeline(optimization)
      }
    end)
  end

  defp calculate_learning_confidence(optimizations) when is_list(optimizations) do
    if Enum.empty?(optimizations) do
      0.0
    else
      confidences =
        Enum.map(optimizations, fn optimization ->
          Map.get(optimization, :confidence, 0.7)
        end)

      Enum.sum(confidences) / length(confidences)
    end
  end

  defp identify_optimization_objectives(patterns) when is_list(patterns) do
    # Identify what objectives these patterns suggest optimizing for
    objective_indicators =
      Enum.flat_map(patterns, fn pattern ->
        case Map.get(pattern, :pattern_type, :unknown) do
          :success_patterns -> [:accuracy_optimization, :user_satisfaction_optimization]
          :failure_modes -> [:speed_optimization, :cost_optimization]
          :user_preferences -> [:user_satisfaction_optimization]
          _ -> [:accuracy_optimization]
        end
      end)

    # Count and prioritize objectives
    objective_counts = Enum.frequencies(objective_indicators)

    objective_counts
    |> Enum.sort_by(fn {_objective, count} -> -count end)
    |> Enum.map(fn {objective, _count} -> objective end)
    # Top 3 objectives
    |> Enum.take(3)
  end

  # Routing optimization analysis

  defp analyze_current_routing_performance(routing_data, optimization_target) do
    # Analyze current routing performance for the specified target
    performance_metrics = extract_routing_performance_metrics(routing_data, optimization_target)
    bottlenecks = identify_routing_bottlenecks(routing_data, optimization_target)

    improvement_opportunities =
      identify_routing_improvement_opportunities(performance_metrics, bottlenecks)

    analysis_result = %{
      current_performance: performance_metrics,
      identified_bottlenecks: bottlenecks,
      improvement_opportunities: improvement_opportunities,
      baseline_metrics: calculate_baseline_metrics(performance_metrics),
      optimization_potential: assess_optimization_potential(improvement_opportunities)
    }

    {:ok, analysis_result}
  end

  defp generate_routing_improvements(performance_analysis, optimization_target, options) do
    # Generate specific routing improvements based on analysis
    current_performance = performance_analysis.current_performance
    opportunities = performance_analysis.improvement_opportunities

    improvements =
      case optimization_target do
        :accuracy_optimization ->
          generate_accuracy_routing_improvements(current_performance, opportunities)

        :speed_optimization ->
          generate_speed_routing_improvements(current_performance, opportunities)

        :cost_optimization ->
          generate_cost_routing_improvements(current_performance, opportunities)

        :user_satisfaction_optimization ->
          generate_satisfaction_routing_improvements(current_performance, opportunities)

        _ ->
          generate_general_routing_improvements(current_performance, opportunities)
      end

    if Enum.empty?(improvements) do
      {:error, "No routing improvements identified for target: #{optimization_target}"}
    else
      {:ok, improvements}
    end
  end

  # Specialization weight analysis

  defp analyze_judge_specialization_effectiveness(feedback) when is_list(feedback) do
    # Group feedback by judge type and analyze effectiveness
    judge_feedback_groups =
      Enum.group_by(feedback, fn feedback_item ->
        Map.get(feedback_item, :judge_type, :unknown)
      end)

    specialization_analysis =
      Enum.map(judge_feedback_groups, fn {judge_type, judge_feedback} ->
        effectiveness_metrics = calculate_judge_effectiveness_metrics(judge_feedback)
        specialization_strength = assess_specialization_strength(judge_feedback, judge_type)

        %{
          judge_type: judge_type,
          effectiveness_metrics: effectiveness_metrics,
          specialization_strength: specialization_strength,
          feedback_count: length(judge_feedback),
          performance_trend: analyze_judge_performance_trend(judge_feedback)
        }
      end)

    {:ok, specialization_analysis}
  end

  defp calculate_specialization_weight_updates(specialization_analysis) do
    # Calculate new weights based on effectiveness analysis
    Enum.map(specialization_analysis, fn judge_analysis ->
      current_weight = get_current_judge_weight(judge_analysis.judge_type)

      effectiveness_score =
        Map.get(judge_analysis.effectiveness_metrics, :overall_effectiveness, 0.7)

      # Adjust weight based on effectiveness
      weight_adjustment = calculate_weight_adjustment(effectiveness_score, current_weight)
      new_weight = apply_weight_adjustment(current_weight, weight_adjustment)

      %{
        judge_type: judge_analysis.judge_type,
        current_weight: current_weight,
        new_weight: new_weight,
        weight_change: new_weight - current_weight,
        confidence: judge_analysis.specialization_strength,
        reasoning: generate_weight_change_reasoning(judge_analysis, weight_adjustment)
      }
    end)
  end

  defp validate_weight_updates(weight_updates) when is_list(weight_updates) do
    # Validate that weight updates are reasonable and safe
    total_weight_change = Enum.sum(Enum.map(weight_updates, & &1.weight_change))

    max_individual_change =
      Enum.max_by(weight_updates, fn update -> abs(update.weight_change) end).weight_change

    %{
      total_weight_change: total_weight_change,
      max_individual_change: max_individual_change,
      weight_balance_maintained: abs(total_weight_change) < 0.2,
      individual_changes_reasonable: abs(max_individual_change) < 0.3,
      validation_passed: abs(total_weight_change) < 0.2 and abs(max_individual_change) < 0.3
    }
  end

  # Pattern filtering and extraction helpers

  defp filter_judge_selection_patterns(patterns) when is_list(patterns) do
    Enum.filter(patterns, fn pattern ->
      pattern_type = Map.get(pattern, :pattern_type, :unknown)
      pattern_data = Map.get(pattern, :pattern_data, %{})

      # Patterns related to judge selection, coordination, or performance
      pattern_type in [:success_patterns, :failure_modes, :judge_performance] or
        Map.has_key?(pattern_data, :judge_selection_data) or
        Map.has_key?(pattern_data, :coordination_data)
    end)
  end

  defp extract_successful_selection_patterns(selection_patterns) do
    success_patterns =
      Enum.filter(selection_patterns, fn pattern ->
        Map.get(pattern, :pattern_type) == :success_patterns
      end)

    Enum.map(success_patterns, fn pattern ->
      pattern_data = Map.get(pattern, :pattern_data, %{})

      %{
        pattern_id: Map.get(pattern, :id),
        judge_combination: extract_judge_combination(pattern_data),
        success_factors: extract_success_factors(pattern_data),
        effectiveness_score: Map.get(pattern, :effectiveness_score, 0.7),
        replication_guidance: extract_replication_guidance(pattern_data)
      }
    end)
  end

  defp extract_failed_selection_patterns(selection_patterns) do
    failure_patterns =
      Enum.filter(selection_patterns, fn pattern ->
        Map.get(pattern, :pattern_type) == :failure_modes
      end)

    Enum.map(failure_patterns, fn pattern ->
      pattern_data = Map.get(pattern, :pattern_data, %{})

      %{
        pattern_id: Map.get(pattern, :id),
        failed_judge_combination: extract_judge_combination(pattern_data),
        failure_factors: extract_failure_factors(pattern_data),
        severity: Map.get(pattern, :severity, :medium),
        avoidance_guidance: extract_avoidance_guidance(pattern_data)
      }
    end)
  end

  defp analyze_judge_performance_correlations(selection_patterns) do
    # Analyze correlations between judge selections and outcomes
    performance_data =
      Enum.map(selection_patterns, fn pattern ->
        pattern_data = Map.get(pattern, :pattern_data, %{})

        %{
          judges_used: extract_judge_combination(pattern_data),
          outcome_quality: extract_outcome_quality(pattern_data),
          user_satisfaction: extract_user_satisfaction(pattern_data),
          processing_efficiency: extract_processing_efficiency(pattern_data)
        }
      end)

    correlations = calculate_judge_outcome_correlations(performance_data)

    %{
      judge_accuracy_correlations: extract_accuracy_correlations(correlations),
      judge_efficiency_correlations: extract_efficiency_correlations(correlations),
      judge_satisfaction_correlations: extract_satisfaction_correlations(correlations),
      optimal_judge_combinations: identify_optimal_combinations(correlations)
    }
  end

  # Optimization generation helpers

  defp add_specialization_optimizations(analysis, optimizations) do
    successful_selections = analysis.successful_selections

    specialization_opts =
      Enum.map(successful_selections, fn selection ->
        %{
          optimization_type: :judge_specialization_enhancement,
          judge_combination: selection.judge_combination,
          effectiveness_boost: selection.effectiveness_score,
          confidence: 0.8,
          id: generate_optimization_id()
        }
      end)

    optimizations ++ specialization_opts
  end

  defp add_performance_routing_optimizations(analysis, optimizations) do
    correlations = analysis.judge_performance_correlations

    performance_opts =
      Enum.map(correlations.optimal_judge_combinations, fn combination ->
        %{
          optimization_type: :performance_based_routing,
          optimal_combination: combination,
          expected_performance_gain: Map.get(combination, :performance_gain, 0.1),
          confidence: 0.75,
          id: generate_optimization_id()
        }
      end)

    optimizations ++ performance_opts
  end

  defp add_user_preference_optimizations(analysis, optimizations) do
    preference_patterns = analysis.user_preference_patterns

    preference_opts =
      Enum.map(preference_patterns, fn pattern ->
        %{
          optimization_type: :user_preference_alignment,
          preference_pattern: pattern,
          personalization_potential: assess_personalization_potential(pattern),
          confidence: 0.7,
          id: generate_optimization_id()
        }
      end)

    optimizations ++ preference_opts
  end

  defp add_temporal_optimizations(analysis, optimizations) do
    temporal_patterns = analysis.temporal_selection_patterns

    temporal_opts =
      Enum.map(temporal_patterns, fn pattern ->
        %{
          optimization_type: :temporal_judge_scheduling,
          temporal_pattern: pattern,
          scheduling_improvement: extract_scheduling_improvement(pattern),
          confidence: 0.65,
          id: generate_optimization_id()
        }
      end)

    optimizations ++ temporal_opts
  end

  # Performance analysis helpers

  defp extract_routing_performance_metrics(routing_data, target) when is_list(routing_data) do
    # Extract performance metrics focused on the optimization target
    base_metrics = %{
      average_accuracy: calculate_average_accuracy(routing_data),
      average_processing_time: calculate_average_processing_time(routing_data),
      average_cost: calculate_average_cost(routing_data),
      average_user_satisfaction: calculate_average_user_satisfaction(routing_data),
      success_rate: calculate_routing_success_rate(routing_data)
    }

    # Add target-specific metrics
    target_specific_metrics =
      case target do
        :accuracy_optimization ->
          %{accuracy_distribution: analyze_accuracy_distribution(routing_data)}

        :speed_optimization ->
          %{processing_time_distribution: analyze_processing_time_distribution(routing_data)}

        :cost_optimization ->
          %{cost_distribution: analyze_cost_distribution(routing_data)}

        _ ->
          %{}
      end

    Map.merge(base_metrics, target_specific_metrics)
  end

  defp identify_routing_bottlenecks(routing_data, target) when is_list(routing_data) do
    # Identify specific bottlenecks based on optimization target
    case target do
      :speed_optimization ->
        identify_speed_bottlenecks(routing_data)

      :accuracy_optimization ->
        identify_accuracy_bottlenecks(routing_data)

      :cost_optimization ->
        identify_cost_bottlenecks(routing_data)

      _ ->
        identify_general_bottlenecks(routing_data)
    end
  end

  defp identify_routing_improvement_opportunities(metrics, bottlenecks) do
    # Identify concrete improvement opportunities
    opportunities = []

    # Performance-based opportunities
    opportunities =
      if Map.get(metrics, :success_rate, 1.0) < 0.9 do
        [%{opportunity: :improve_success_rate, potential_gain: 0.1} | opportunities]
      else
        opportunities
      end

    # Bottleneck-based opportunities
    bottleneck_opportunities =
      Enum.map(bottlenecks, fn bottleneck ->
        %{
          opportunity: :resolve_bottleneck,
          bottleneck_type: bottleneck.type,
          potential_gain: Map.get(bottleneck, :resolution_impact, 0.15)
        }
      end)

    opportunities ++ bottleneck_opportunities
  end

  # Routing improvement generation

  defp generate_accuracy_routing_improvements(performance, opportunities) do
    accuracy_opportunities =
      Enum.filter(opportunities, fn opp ->
        opp.opportunity in [:improve_success_rate, :enhance_judge_accuracy]
      end)

    Enum.map(accuracy_opportunities, fn opportunity ->
      %{
        improvement_type: :accuracy_enhancement,
        current_accuracy: Map.get(performance, :average_accuracy, 0.75),
        target_accuracy:
          Map.get(performance, :average_accuracy, 0.75) + opportunity.potential_gain,
        implementation_strategy: :enhance_judge_selection_accuracy,
        confidence: 0.8
      }
    end)
  end

  defp generate_speed_routing_improvements(performance, opportunities) do
    speed_opportunities =
      Enum.filter(opportunities, fn opp ->
        opp.opportunity in [:improve_processing_speed, :optimize_judge_routing]
      end)

    Enum.map(speed_opportunities, fn opportunity ->
      %{
        improvement_type: :speed_optimization,
        current_processing_time: Map.get(performance, :average_processing_time, 5_000),
        target_processing_time:
          Map.get(performance, :average_processing_time, 5_000) * (1 - opportunity.potential_gain),
        implementation_strategy: :optimize_judge_routing_speed,
        confidence: 0.75
      }
    end)
  end

  defp generate_cost_routing_improvements(performance, opportunities) do
    cost_opportunities =
      Enum.filter(opportunities, fn opp ->
        opp.opportunity in [:reduce_costs, :optimize_resource_usage]
      end)

    Enum.map(cost_opportunities, fn opportunity ->
      %{
        improvement_type: :cost_optimization,
        current_cost: Map.get(performance, :average_cost, 0.08),
        target_cost: Map.get(performance, :average_cost, 0.08) * (1 - opportunity.potential_gain),
        implementation_strategy: :optimize_cost_efficient_routing,
        confidence: 0.7
      }
    end)
  end

  defp generate_satisfaction_routing_improvements(performance, opportunities) do
    satisfaction_opportunities =
      Enum.filter(opportunities, fn opp ->
        opp.opportunity in [:improve_user_satisfaction, :enhance_user_experience]
      end)

    Enum.map(satisfaction_opportunities, fn opportunity ->
      %{
        improvement_type: :satisfaction_enhancement,
        current_satisfaction: Map.get(performance, :average_user_satisfaction, 0.7),
        target_satisfaction:
          Map.get(performance, :average_user_satisfaction, 0.7) + opportunity.potential_gain,
        implementation_strategy: :personalize_judge_selection,
        confidence: 0.72
      }
    end)
  end

  defp generate_general_routing_improvements(performance, opportunities) do
    # Generate balanced improvements across multiple dimensions
    Enum.map(opportunities, fn opportunity ->
      %{
        improvement_type: :general_optimization,
        optimization_area: opportunity.opportunity,
        potential_gain: opportunity.potential_gain,
        implementation_strategy: :balanced_optimization_approach,
        confidence: 0.65
      }
    end)
  end

  # Judge effectiveness calculation helpers

  defp calculate_judge_effectiveness_metrics(judge_feedback) when is_list(judge_feedback) do
    if Enum.empty?(judge_feedback) do
      %{overall_effectiveness: 0.5, consistency_score: 0.5}
    else
      effectiveness_scores = Enum.map(judge_feedback, &extract_effectiveness_score/1)
      valid_scores = Enum.filter(effectiveness_scores, &is_number/1)

      overall_effectiveness =
        if Enum.empty?(valid_scores) do
          0.5
        else
          Enum.sum(valid_scores) / length(valid_scores)
        end

      consistency_score = calculate_judge_consistency_score(valid_scores)

      %{
        overall_effectiveness: overall_effectiveness,
        consistency_score: consistency_score,
        improvement_trend: calculate_improvement_trend(valid_scores),
        performance_stability: assess_performance_stability(valid_scores)
      }
    end
  end

  defp assess_specialization_strength(judge_feedback, judge_type) when is_list(judge_feedback) do
    # Assess how well the judge performs in its specialization area
    specialization_feedback =
      Enum.filter(judge_feedback, fn feedback ->
        feedback_context = Map.get(feedback, :evaluation_context, %{})
        evaluation_type = Map.get(feedback_context, :primary_focus, :general)

        # Check if evaluation type matches judge specialization
        judge_specializes_in_evaluation_type?(judge_type, evaluation_type)
      end)

    if Enum.empty?(specialization_feedback) do
      # Neutral strength if no specialization data
      0.5
    else
      specialization_scores = Enum.map(specialization_feedback, &extract_effectiveness_score/1)
      valid_scores = Enum.filter(specialization_scores, &is_number/1)

      if Enum.empty?(valid_scores) do
        0.5
      else
        Enum.sum(valid_scores) / length(valid_scores)
      end
    end
  end

  defp analyze_judge_performance_trend(judge_feedback) when is_list(judge_feedback) do
    # Analyze if judge performance is improving, declining, or stable
    if length(judge_feedback) < 3 do
      :insufficient_data
    else
      calculate_performance_trend(judge_feedback)
    end
  end

  defp calculate_performance_trend(judge_feedback) do
    # Sort by timestamp and analyze trend
    sorted_feedback =
      Enum.sort_by(judge_feedback, fn feedback ->
        Map.get(feedback, :timestamp, DateTime.utc_now())
      end)

    effectiveness_scores =
      Enum.map(sorted_feedback, &extract_effectiveness_score/1)
      |> Enum.filter(&is_number/1)

    if length(effectiveness_scores) < 3 do
      :insufficient_data
    else
      trend = calculate_simple_trend(effectiveness_scores)
      classify_trend_slope(trend)
    end
  end

  defp classify_trend_slope(trend) do
    case trend do
      slope when slope > 0.05 -> :improving
      slope when slope < -0.05 -> :declining
      _ -> :stable
    end
  end

  # Weight update calculation helpers

  defp get_current_judge_weight(judge_type) do
    # Get current weight for judge type - would integrate with actual system
    case judge_type do
      :security -> 1.0
      :architecture -> 0.9
      :code_quality -> 0.8
      :test_quality -> 0.7
      _ -> 0.6
    end
  end

  defp calculate_weight_adjustment(effectiveness_score, current_weight) do
    # Calculate how much to adjust the weight
    target_effectiveness = 0.8
    effectiveness_gap = effectiveness_score - target_effectiveness

    # Conservative adjustment - max 10% change per update
    adjustment = effectiveness_gap * 0.1
    max_adjustment = current_weight * 0.1

    # Clamp adjustment to reasonable bounds
    min(max_adjustment, max(-max_adjustment, adjustment))
  end

  defp apply_weight_adjustment(current_weight, adjustment) do
    new_weight = current_weight + adjustment

    # Ensure weight stays within reasonable bounds
    min(2.0, max(0.1, new_weight))
  end

  defp generate_weight_change_reasoning(judge_analysis, weight_adjustment) do
    effectiveness = judge_analysis.effectiveness_metrics.overall_effectiveness
    trend = judge_analysis.performance_trend

    cond do
      weight_adjustment > 0.05 ->
        "Increasing weight due to high effectiveness (#{Float.round(effectiveness, 2)}) and #{trend} trend"

      weight_adjustment < -0.05 ->
        "Decreasing weight due to low effectiveness (#{Float.round(effectiveness, 2)}) and #{trend} trend"

      true ->
        "Maintaining weight - performance is stable at #{Float.round(effectiveness, 2)}"
    end
  end

  # Effectiveness calculation and validation helpers

  defp estimate_weight_update_improvement(weight_updates) when is_list(weight_updates) do
    # Estimate overall system improvement from weight updates
    positive_changes = Enum.filter(weight_updates, fn update -> update.weight_change > 0 end)
    negative_changes = Enum.filter(weight_updates, fn update -> update.weight_change < 0 end)

    # Net positive weight changes should improve system
    net_positive_change = Enum.sum(Enum.map(positive_changes, & &1.weight_change))
    net_negative_change = abs(Enum.sum(Enum.map(negative_changes, & &1.weight_change)))

    # Estimate improvement based on net positive changes
    estimated_improvement = (net_positive_change - net_negative_change * 0.5) * 0.1

    max(0.0, min(0.3, estimated_improvement))
  end

  defp calculate_weight_update_confidence(specialization_analysis)
       when is_list(specialization_analysis) do
    if Enum.empty?(specialization_analysis) do
      0.0
    else
      # Average specialization strength as confidence indicator
      strengths = Enum.map(specialization_analysis, & &1.specialization_strength)
      average_strength = Enum.sum(strengths) / length(strengths)

      # Adjust based on data quality
      data_quality_factor = assess_analysis_data_quality(specialization_analysis)

      min(1.0, average_strength * data_quality_factor)
    end
  end

  # Helper stubs for comprehensive implementation

  defp extract_user_preference_patterns(_patterns), do: []

  defp analyze_temporal_selection_effectiveness(_patterns),
    do: %{peak_performance_times: [10, 14, 16]}

  defp calculate_expected_performance_gain(_improvements), do: 0.12
  defp assess_routing_implementation_complexity(_improvements), do: :medium

  defp extract_judge_combination(pattern_data) when is_map(pattern_data) do
    Map.get(pattern_data, :judges_used, [:code_quality])
  end

  defp extract_success_factors(_pattern_data), do: ["high_consensus", "fast_processing"]
  defp extract_failure_factors(_pattern_data), do: ["low_consensus", "slow_processing"]
  defp extract_replication_guidance(_pattern_data), do: "Use successful judge combination"
  defp extract_avoidance_guidance(_pattern_data), do: "Avoid failed judge combination"

  defp extract_outcome_quality(_pattern_data), do: 0.8
  defp extract_user_satisfaction(_pattern_data), do: 0.75
  defp extract_processing_efficiency(_pattern_data), do: 0.7

  defp calculate_judge_outcome_correlations(_performance_data) do
    # Mock correlation calculation
    %{judge_accuracy_correlation: 0.8, judge_efficiency_correlation: 0.6}
  end

  defp extract_accuracy_correlations(correlations),
    do: Map.get(correlations, :judge_accuracy_correlation, 0.0)

  defp extract_efficiency_correlations(correlations),
    do: Map.get(correlations, :judge_efficiency_correlation, 0.0)

  defp extract_satisfaction_correlations(correlations), do: 0.7

  defp identify_optimal_combinations(_correlations),
    do: [%{judges: [:code_quality, :architecture], performance_gain: 0.15}]

  defp calculate_optimization_effectiveness_prediction(_optimization), do: 0.78
  defp calculate_optimization_confidence_interval(_optimization), do: {0.65, 0.9}
  defp assess_optimization_risk(_optimization), do: :low
  defp estimate_optimization_timeline(_optimization), do: {1, :week}

  defp generate_optimization_id, do: "opt_#{System.unique_integer([:positive])}"

  defp calculate_baseline_metrics(performance_metrics) when is_map(performance_metrics) do
    # Establish baseline for comparison
    %{
      baseline_accuracy: Map.get(performance_metrics, :average_accuracy, 0.75),
      baseline_speed: Map.get(performance_metrics, :average_processing_time, 5_000),
      baseline_cost: Map.get(performance_metrics, :average_cost, 0.08)
    }
  end

  defp assess_optimization_potential(opportunities) when is_list(opportunities) do
    if Enum.empty?(opportunities) do
      :low
    else
      max_gain = Enum.max_by(opportunities, & &1.potential_gain).potential_gain

      case max_gain do
        gain when gain > 0.3 -> :high
        gain when gain > 0.15 -> :medium
        gain when gain > 0.05 -> :low
        _ -> :minimal
      end
    end
  end

  # Performance calculation stubs

  defp calculate_average_accuracy(routing_data), do: 0.78
  defp calculate_average_processing_time(routing_data), do: 4_500
  defp calculate_average_cost(routing_data), do: 0.07
  defp calculate_average_user_satisfaction(routing_data), do: 0.8
  defp calculate_routing_success_rate(routing_data), do: 0.88

  defp analyze_accuracy_distribution(_routing_data), do: %{p50: 0.78, p95: 0.92, std_dev: 0.08}

  defp analyze_processing_time_distribution(_routing_data),
    do: %{p50: 4_000, p95: 8_500, std_dev: 1_200}

  defp analyze_cost_distribution(_routing_data), do: %{p50: 0.06, p95: 0.12, std_dev: 0.02}

  defp identify_speed_bottlenecks(_routing_data), do: [%{type: :consensus_delay, impact: 0.2}]

  defp identify_accuracy_bottlenecks(_routing_data),
    do: [%{type: :judge_specialization_mismatch, impact: 0.15}]

  defp identify_cost_bottlenecks(_routing_data),
    do: [%{type: :overuse_expensive_judges, impact: 0.25}]

  defp identify_general_bottlenecks(_routing_data), do: []

  defp extract_effectiveness_score(feedback) when is_map(feedback) do
    Map.get(feedback, :effectiveness_score, 0.7)
  end

  defp extract_effectiveness_score(_), do: 0.5

  defp calculate_judge_consistency_score(scores) when is_list(scores) and length(scores) > 1 do
    mean = Enum.sum(scores) / length(scores)

    variance =
      Enum.reduce(scores, 0.0, fn score, acc ->
        acc + :math.pow(score - mean, 2)
      end) / length(scores)

    # Lower variance = higher consistency
    max(0.0, 1.0 - variance)
  end

  defp calculate_judge_consistency_score(_), do: 0.5

  defp calculate_improvement_trend(scores) when is_list(scores) and length(scores) > 2 do
    # Simple linear trend calculation
    calculate_simple_trend(scores)
  end

  defp calculate_improvement_trend(_), do: 0.0

  defp calculate_simple_trend(values) when is_list(values) and length(values) > 1 do
    # Simple slope calculation for trend
    n = length(values)
    x_values = Enum.to_list(1..n)

    x_mean = Enum.sum(x_values) / n
    y_mean = Enum.sum(values) / n

    numerator =
      Enum.zip(x_values, values)
      |> Enum.reduce(0.0, fn {x, y}, acc -> acc + (x - x_mean) * (y - y_mean) end)

    denominator = Enum.reduce(x_values, 0.0, fn x, acc -> acc + :math.pow(x - x_mean, 2) end)

    if denominator == 0 do
      0.0
    else
      numerator / denominator
    end
  end

  defp calculate_simple_trend(_), do: 0.0

  defp assess_performance_stability(scores) when is_list(scores) and length(scores) > 1 do
    consistency = calculate_judge_consistency_score(scores)

    case consistency do
      score when score > 0.8 -> :very_stable
      score when score > 0.6 -> :stable
      score when score > 0.4 -> :somewhat_stable
      _ -> :unstable
    end
  end

  defp assess_performance_stability(_), do: :unknown

  defp judge_specializes_in_evaluation_type?(judge_type, evaluation_type) do
    specializations = %{
      code_quality: [:code_review, :quality_assessment, :general],
      architecture: [:architectural_review, :design_analysis, :general],
      security: [:security_review, :vulnerability_assessment],
      test_quality: [:test_review, :test_coverage_analysis]
    }

    judge_specializations = Map.get(specializations, judge_type, [:general])
    evaluation_type in judge_specializations or evaluation_type == :general
  end

  defp assess_analysis_data_quality(analysis) when is_list(analysis) do
    # Assess the quality of the analysis data
    total_feedback = Enum.sum(Enum.map(analysis, & &1.feedback_count))

    case total_feedback do
      count when count > 100 -> 1.0
      count when count > 50 -> 0.9
      count when count > 20 -> 0.8
      count when count > 10 -> 0.7
      _ -> 0.6
    end
  end

  # Additional helper stubs

  defp assess_personalization_potential(_pattern), do: 0.7
  defp extract_scheduling_improvement(_pattern), do: %{optimal_hours: [9, 14, 16]}
end
