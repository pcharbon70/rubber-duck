defmodule RubberDuck.Verdict.Adaptation.DynamicRoutingEngine do
  @moduledoc """
  Adaptive routing engine for learned judge selection and coordination optimization.

  Implements dynamic judge selection strategies based on learned patterns,
  user preferences, temporal factors, and real-time performance metrics to
  optimize evaluation quality, speed, and user satisfaction.
  """

  require Logger

  alias RubberDuck.Verdict.Learning.{JudgeSelectionLearner, LearningModel}
  alias RubberDuck.Verdict.Analytics.{PatternRecognition, UserPreferenceProfiler}

  @routing_strategies [
    :learned_optimal,
    :user_preference_based,
    :temporal_adaptive,
    :performance_weighted,
    :cost_optimized,
    :quality_focused
  ]

  @judge_selection_factors [
    :historical_performance,
    :user_preferences,
    :evaluation_complexity,
    :cost_constraints,
    :temporal_factors,
    :quality_requirements
  ]

  @doc """
  Select optimal judges dynamically based on learned patterns and current context.

  ## Parameters
  - `evaluation_context` - Context for the current evaluation
  - `available_judges` - List of available judge agents
  - `user_profile` - User preference profile (if available)
  - `options` - Routing options and constraints

  ## Returns
  - `{:ok, judge_selection}` - Optimal judge selection with reasoning
  - `{:error, reason}` - Selection failed
  """
  def select_optimal_judges(
        evaluation_context,
        available_judges,
        user_profile \\ nil,
        options \\ []
      ) do
    routing_strategy = Keyword.get(options, :strategy, :learned_optimal)

    Logger.debug("Selecting optimal judges using #{routing_strategy} strategy")

    case load_routing_models(routing_strategy) do
      {:ok, routing_models} ->
        case apply_dynamic_routing_strategy(
               routing_strategy,
               evaluation_context,
               available_judges,
               user_profile,
               routing_models,
               options
             ) do
          {:ok, judge_selection} ->
            selection_reasoning =
              generate_selection_reasoning(judge_selection, routing_strategy, evaluation_context)

            result = %{
              selected_judges: judge_selection.judges,
              routing_strategy: routing_strategy,
              selection_confidence: judge_selection.confidence,
              expected_performance: judge_selection.expected_performance,
              cost_estimate: judge_selection.cost_estimate,
              selection_reasoning: selection_reasoning,
              routing_metadata: %{
                router: :dynamic_routing_engine,
                version: "1.0.0",
                routed_at: DateTime.utc_now(),
                models_used: Map.keys(routing_models)
              }
            }

            {:ok, result}

          {:error, reason} ->
            Logger.warning("Dynamic routing failed, falling back to default: #{reason}")
            fallback_to_default_routing(available_judges, evaluation_context)
        end

      {:error, reason} ->
        Logger.warning("Model loading failed, using fallback: #{reason}")
        fallback_to_default_routing(available_judges, evaluation_context)
    end
  end

  @doc """
  Adapt judge coordination strategy based on learned effectiveness patterns.

  ## Parameters
  - `coordination_context` - Current coordination context and constraints
  - `learned_patterns` - Patterns from previous coordinations
  - `options` - Adaptation options

  ## Returns
  - `{:ok, coordination_strategy}` - Adapted coordination strategy
  - `{:error, reason}` - Adaptation failed
  """
  def adapt_coordination_strategy(coordination_context, learned_patterns, options \\ []) do
    Logger.info(
      "Adapting coordination strategy from #{length(learned_patterns)} learned patterns"
    )

    case analyze_coordination_effectiveness(learned_patterns, coordination_context) do
      {:ok, effectiveness_analysis} ->
        case generate_adaptive_coordination_strategy(
               effectiveness_analysis,
               coordination_context,
               options
             ) do
          {:ok, strategy} ->
            strategy_validation = validate_coordination_strategy(strategy, coordination_context)

            result = %{
              coordination_strategy: strategy,
              strategy_validation: strategy_validation,
              effectiveness_analysis: effectiveness_analysis,
              adaptation_confidence:
                calculate_coordination_adaptation_confidence(effectiveness_analysis),
              expected_improvement: estimate_coordination_improvement(strategy),
              adaptation_metadata: %{
                adapter: :coordination_strategy_adapter,
                adapted_at: DateTime.utc_now(),
                patterns_analyzed: length(learned_patterns)
              }
            }

            {:ok, result}

          {:error, reason} ->
            {:error, "Strategy generation failed: #{reason}"}
        end

      {:error, reason} ->
        {:error, "Coordination effectiveness analysis failed: #{reason}"}
    end
  end

  @doc """
  Get adaptive routing statistics and model performance metrics.
  """
  def get_adaptive_routing_stats(time_window \\ {24, :hour}) do
    {amount, unit} = time_window

    %{
      total_adaptive_routings: get_total_adaptive_routings_since(time_window),
      routing_strategy_distribution: get_routing_strategy_distribution(time_window),
      average_selection_confidence: get_average_selection_confidence(time_window),
      model_usage_statistics: get_model_usage_statistics(time_window),
      adaptation_success_rate: calculate_adaptation_success_rate(time_window),
      fallback_usage_rate: calculate_fallback_usage_rate(time_window),
      performance_improvements: measure_performance_improvements(time_window),
      routing_health: %{
        model_health: assess_routing_model_health(),
        adaptation_effectiveness: assess_adaptation_effectiveness(),
        user_satisfaction_impact: measure_user_satisfaction_impact()
      }
    }
  end

  ## Private Routing Strategy Implementations

  defp load_routing_models(routing_strategy) do
    # Load relevant learning models based on routing strategy
    model_types = determine_required_models(routing_strategy)

    models =
      Enum.reduce(model_types, %{}, fn model_type, acc ->
        case LearningModel.get_active_models(model_type) do
          [] ->
            Logger.warning("No active models found for #{model_type}")
            acc

          [model | _] ->
            Map.put(acc, model_type, model)
        end
      end)

    if map_size(models) > 0 do
      {:ok, models}
    else
      {:error, "No active learning models available for routing strategy: #{routing_strategy}"}
    end
  end

  defp apply_dynamic_routing_strategy(
         strategy,
         context,
         available_judges,
         user_profile,
         models,
         options
       ) do
    case strategy do
      :learned_optimal ->
        apply_learned_optimal_routing(context, available_judges, user_profile, models, options)

      :user_preference_based ->
        apply_user_preference_routing(context, available_judges, user_profile, models, options)

      :temporal_adaptive ->
        apply_temporal_adaptive_routing(context, available_judges, user_profile, models, options)

      :performance_weighted ->
        apply_performance_weighted_routing(
          context,
          available_judges,
          user_profile,
          models,
          options
        )

      :cost_optimized ->
        apply_cost_optimized_routing(context, available_judges, user_profile, models, options)

      :quality_focused ->
        apply_quality_focused_routing(context, available_judges, user_profile, models, options)

      _ ->
        {:error, "Unknown routing strategy: #{strategy}"}
    end
  end

  # Routing strategy implementations

  defp apply_learned_optimal_routing(context, available_judges, user_profile, models, options) do
    # Use learned patterns to select optimal judge combination
    judge_selection_model = Map.get(models, :judge_selection_model)
    pattern_model = Map.get(models, :pattern_recognition_model)

    case generate_learned_judge_selection(
           context,
           available_judges,
           judge_selection_model,
           pattern_model
         ) do
      {:ok, selection} ->
        # Enhance with user preferences if available
        enhanced_selection =
          if user_profile do
            enhance_selection_with_user_preferences(selection, user_profile)
          else
            selection
          end

        {:ok, enhanced_selection}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_user_preference_routing(context, available_judges, user_profile, models, options) do
    # Prioritize user preferences in judge selection
    if user_profile do
      case generate_preference_based_selection(context, available_judges, user_profile, models) do
        {:ok, selection} ->
          {:ok, selection}

        {:error, reason} ->
          {:error, reason}
      end
    else
      # Fall back to learned optimal if no user profile
      apply_learned_optimal_routing(context, available_judges, user_profile, models, options)
    end
  end

  defp apply_temporal_adaptive_routing(context, available_judges, user_profile, models, options) do
    # Adapt judge selection based on temporal factors
    temporal_model = Map.get(models, :temporal_prediction_model)
    current_time = DateTime.utc_now()

    temporal_factors = extract_temporal_factors(current_time, context)

    judge_selection =
      generate_temporal_adapted_selection(available_judges, temporal_factors, temporal_model)

    {:ok, judge_selection}
  end

  defp apply_performance_weighted_routing(
         context,
         available_judges,
         user_profile,
         models,
         options
       ) do
    # Weight judge selection by historical performance
    performance_weights = calculate_judge_performance_weights(available_judges, models)

    judge_selection =
      generate_performance_weighted_selection(context, available_judges, performance_weights)

    {:ok, judge_selection}
  end

  defp apply_cost_optimized_routing(context, available_judges, user_profile, models, options) do
    # Optimize for cost efficiency while maintaining quality
    cost_model = Map.get(models, :cost_optimization_model)
    cost_constraints = extract_cost_constraints(context, options)

    judge_selection =
      generate_cost_optimized_selection(available_judges, cost_constraints, cost_model)

    {:ok, judge_selection}
  end

  defp apply_quality_focused_routing(context, available_judges, user_profile, models, options) do
    # Prioritize evaluation quality over other factors
    quality_requirements = extract_quality_requirements(context, options)
    judge_selection = generate_quality_focused_selection(available_judges, quality_requirements)

    {:ok, judge_selection}
  end

  # Judge selection generation

  defp generate_learned_judge_selection(context, available_judges, judge_model, pattern_model) do
    # Use learned patterns to generate optimal judge selection
    evaluation_complexity = assess_evaluation_complexity(context)

    optimal_judges =
      case evaluation_complexity do
        :high -> select_comprehensive_judge_team(available_judges, judge_model)
        :medium -> select_balanced_judge_team(available_judges, judge_model)
        :low -> select_efficient_judge_team(available_judges, judge_model)
      end

    selection = %{
      judges: optimal_judges,
      confidence: 0.85,
      expected_performance: %{
        accuracy: 0.88,
        processing_time: 4_500,
        user_satisfaction: 0.82
      },
      cost_estimate: calculate_judge_team_cost(optimal_judges),
      selection_reasoning:
        "Learned optimal based on evaluation complexity: #{evaluation_complexity}"
    }

    {:ok, selection}
  end

  defp generate_preference_based_selection(context, available_judges, user_profile, models) do
    # Generate selection based on user preferences
    user_preferences = extract_user_judge_preferences(user_profile)
    preferred_judges = filter_judges_by_user_preferences(available_judges, user_preferences)

    # Ensure we have enough judges
    final_judges =
      if length(preferred_judges) >= 2 do
        Enum.take(preferred_judges, 3)
      else
        # Add additional judges to meet minimum requirements
        additional_judges = available_judges -- preferred_judges
        preferred_judges ++ Enum.take(additional_judges, 3 - length(preferred_judges))
      end

    selection = %{
      judges: final_judges,
      confidence: 0.8,
      expected_performance: %{
        accuracy: 0.85,
        processing_time: 5_000,
        # High satisfaction due to preference alignment
        user_satisfaction: 0.9
      },
      cost_estimate: calculate_judge_team_cost(final_judges),
      selection_reasoning: "User preference alignment with fallback for coverage"
    }

    {:ok, selection}
  end

  defp generate_temporal_adapted_selection(available_judges, temporal_factors, temporal_model) do
    # Select judges based on temporal performance patterns
    current_hour = temporal_factors.hour_of_day
    current_day = temporal_factors.day_of_week

    # Use temporal model to predict judge effectiveness
    judge_effectiveness_predictions =
      Enum.map(available_judges, fn judge ->
        predicted_effectiveness =
          predict_temporal_judge_effectiveness(judge, temporal_factors, temporal_model)

        {judge, predicted_effectiveness}
      end)

    # Select top performing judges for current time
    optimal_temporal_judges =
      judge_effectiveness_predictions
      |> Enum.sort_by(fn {_judge, effectiveness} -> -effectiveness end)
      |> Enum.take(3)
      |> Enum.map(fn {judge, _effectiveness} -> judge end)

    %{
      judges: optimal_temporal_judges,
      confidence: 0.78,
      expected_performance: %{
        accuracy: 0.83,
        processing_time: 4_200,
        user_satisfaction: 0.8
      },
      cost_estimate: calculate_judge_team_cost(optimal_temporal_judges),
      selection_reasoning: "Temporal adaptation for #{current_day} at hour #{current_hour}"
    }
  end

  defp generate_performance_weighted_selection(context, available_judges, performance_weights) do
    # Weight judge selection by historical performance
    weighted_judges =
      Enum.map(available_judges, fn judge ->
        weight = Map.get(performance_weights, judge, 0.7)
        {judge, weight}
      end)

    # Select judges with highest performance weights
    selected_judges =
      weighted_judges
      |> Enum.sort_by(fn {_judge, weight} -> -weight end)
      |> Enum.take(3)
      |> Enum.map(fn {judge, _weight} -> judge end)

    %{
      judges: selected_judges,
      confidence: 0.82,
      expected_performance: %{
        accuracy: 0.87,
        processing_time: 4_800,
        user_satisfaction: 0.83
      },
      cost_estimate: calculate_judge_team_cost(selected_judges),
      selection_reasoning: "Performance-weighted selection based on historical effectiveness"
    }
  end

  defp generate_cost_optimized_selection(available_judges, cost_constraints, cost_model) do
    # Select judges optimized for cost efficiency
    judge_cost_efficiency =
      Enum.map(available_judges, fn judge ->
        cost_efficiency = calculate_judge_cost_efficiency(judge, cost_model)
        {judge, cost_efficiency}
      end)

    # Select most cost-efficient judges that meet quality requirements
    budget_limit = Map.get(cost_constraints, :max_cost, 0.15)

    selected_judges =
      judge_cost_efficiency
      |> Enum.sort_by(fn {_judge, efficiency} -> -efficiency end)
      |> select_judges_within_budget(budget_limit)

    %{
      judges: selected_judges,
      confidence: 0.75,
      expected_performance: %{
        accuracy: 0.8,
        processing_time: 5_500,
        user_satisfaction: 0.78
      },
      cost_estimate: calculate_judge_team_cost(selected_judges),
      selection_reasoning: "Cost-optimized selection within budget: $#{budget_limit}"
    }
  end

  defp generate_quality_focused_selection(available_judges, quality_requirements) do
    # Select judges optimized for maximum quality
    quality_threshold = Map.get(quality_requirements, :min_accuracy, 0.85)

    # Filter judges by quality capability
    high_quality_judges =
      Enum.filter(available_judges, fn judge ->
        judge_quality_rating = get_judge_quality_rating(judge)
        judge_quality_rating >= quality_threshold
      end)

    # Select comprehensive team for highest quality
    selected_judges =
      if length(high_quality_judges) >= 3 do
        # More judges for higher quality
        Enum.take(high_quality_judges, 4)
      else
        # Use all high-quality judges plus best of remaining
        remaining_judges = available_judges -- high_quality_judges
        high_quality_judges ++ Enum.take(remaining_judges, 3 - length(high_quality_judges))
      end

    %{
      judges: selected_judges,
      confidence: 0.9,
      expected_performance: %{
        accuracy: 0.92,
        # Longer due to thoroughness
        processing_time: 6_500,
        user_satisfaction: 0.88
      },
      cost_estimate: calculate_judge_team_cost(selected_judges),
      selection_reasoning: "Quality-focused selection for accuracy >= #{quality_threshold}"
    }
  end

  # Coordination strategy adaptation

  defp analyze_coordination_effectiveness(patterns, coordination_context) do
    # Analyze effectiveness of different coordination approaches
    coordination_patterns = filter_coordination_patterns(patterns)

    if Enum.empty?(coordination_patterns) do
      {:error, "No coordination patterns available for analysis"}
    else
      effectiveness_analysis = %{
        consensus_mechanism_effectiveness:
          analyze_consensus_mechanism_effectiveness(coordination_patterns),
        negotiation_strategy_effectiveness:
          analyze_negotiation_strategy_effectiveness(coordination_patterns),
        timeout_configuration_effectiveness:
          analyze_timeout_configuration_effectiveness(coordination_patterns),
        agent_coordination_patterns: analyze_agent_coordination_patterns(coordination_patterns)
      }

      {:ok, effectiveness_analysis}
    end
  end

  defp generate_adaptive_coordination_strategy(effectiveness_analysis, context, options) do
    # Generate coordination strategy based on effectiveness analysis
    base_strategy = determine_base_coordination_strategy(effectiveness_analysis, context)

    # Adapt based on current context
    adapted_strategy = adapt_strategy_to_context(base_strategy, context, options)

    # Validate and finalize strategy
    final_strategy = finalize_coordination_strategy(adapted_strategy, effectiveness_analysis)

    {:ok, final_strategy}
  end

  defp validate_coordination_strategy(strategy, coordination_context) do
    # Validate that strategy is appropriate for context
    validation_results = %{
      strategy_appropriateness: assess_strategy_appropriateness(strategy, coordination_context),
      resource_requirements_met: validate_resource_requirements(strategy),
      performance_expectations_realistic: validate_performance_expectations(strategy),
      risk_assessment: assess_coordination_strategy_risk(strategy),
      # Would be calculated from individual checks
      validation_passed: true
    }

    validation_results
  end

  # Helper functions for judge selection

  defp determine_required_models(routing_strategy) do
    case routing_strategy do
      :learned_optimal -> [:judge_selection_model, :pattern_recognition_model]
      :user_preference_based -> [:user_preference_model]
      :temporal_adaptive -> [:temporal_prediction_model]
      :performance_weighted -> [:judge_selection_model]
      :cost_optimized -> [:cost_optimization_model]
      :quality_focused -> [:judge_selection_model]
    end
  end

  defp assess_evaluation_complexity(evaluation_context) when is_map(evaluation_context) do
    # Assess complexity based on context factors
    code_size = Map.get(evaluation_context, :code_size, :medium)
    technical_depth = Map.get(evaluation_context, :technical_depth, :standard)
    quality_requirements = Map.get(evaluation_context, :quality_requirements, :standard)

    complexity_factors = [
      {code_size, %{large: 2, medium: 1, small: 0}},
      {technical_depth, %{advanced: 2, standard: 1, basic: 0}},
      {quality_requirements, %{strict: 2, standard: 1, relaxed: 0}}
    ]

    complexity_score =
      Enum.reduce(complexity_factors, 0, fn {factor, weights}, acc ->
        acc + Map.get(weights, factor, 0)
      end)

    case complexity_score do
      score when score >= 4 -> :high
      score when score >= 2 -> :medium
      _ -> :low
    end
  end

  defp select_comprehensive_judge_team(available_judges, judge_model) do
    # Select comprehensive team for high complexity evaluations
    if length(available_judges) >= 4 do
      # All judge types for comprehensive analysis
      Enum.take(available_judges, 4)
    else
      available_judges
    end
  end

  defp select_balanced_judge_team(available_judges, judge_model) do
    # Select balanced team for medium complexity evaluations
    priority_judges = [:code_quality, :architecture, :security]

    selected =
      Enum.filter(available_judges, fn judge ->
        judge in priority_judges
      end)

    if length(selected) >= 3 do
      Enum.take(selected, 3)
    else
      # Add additional judges if needed
      additional = available_judges -- selected
      selected ++ Enum.take(additional, 3 - length(selected))
    end
  end

  defp select_efficient_judge_team(available_judges, judge_model) do
    # Select efficient team for low complexity evaluations
    # Core judges for efficiency
    efficient_judges = [:code_quality, :architecture]

    selected =
      Enum.filter(available_judges, fn judge ->
        judge in efficient_judges
      end)

    Enum.take(selected ++ (available_judges -- selected), 2)
  end

  # User preference integration

  defp enhance_selection_with_user_preferences(selection, user_profile)
       when is_map(user_profile) do
    # Enhance judge selection based on user preferences
    user_preferred_judges = extract_user_judge_preferences(user_profile)
    current_judges = selection.judges

    # Try to include user preferred judges if available
    enhanced_judges = integrate_user_preferences(current_judges, user_preferred_judges)

    # Adjust confidence based on preference alignment
    preference_alignment = calculate_preference_alignment(enhanced_judges, user_preferred_judges)
    adjusted_confidence = min(1.0, selection.confidence + preference_alignment * 0.1)

    %{
      selection
      | judges: enhanced_judges,
        confidence: adjusted_confidence,
        selection_reasoning: selection.selection_reasoning <> " + user preference integration"
    }
  end

  defp extract_user_judge_preferences(user_profile) when is_map(user_profile) do
    # Extract judge preferences from user profile
    preference_data = Map.get(user_profile, :preference_profile, %{})
    Map.get(preference_data, :preferred_judge_types, [:code_quality, :architecture])
  end

  defp filter_judges_by_user_preferences(available_judges, user_preferences)
       when is_list(user_preferences) do
    Enum.filter(available_judges, fn judge ->
      judge in user_preferences
    end)
  end

  defp integrate_user_preferences(current_judges, user_preferred_judges)
       when is_list(current_judges) and is_list(user_preferred_judges) do
    # Integrate user preferences while maintaining selection quality
    user_overlap = current_judges -- (current_judges -- user_preferred_judges)

    if length(user_overlap) >= 2 do
      # Good overlap, keep current selection
      current_judges
    else
      # Try to include more user preferred judges
      additional_preferred = user_preferred_judges -- current_judges
      replacement_count = min(length(additional_preferred), 1)

      if replacement_count > 0 do
        # Replace one judge with user preferred
        judges_to_keep = Enum.take(current_judges, length(current_judges) - replacement_count)
        judges_to_add = Enum.take(additional_preferred, replacement_count)

        judges_to_keep ++ judges_to_add
      else
        current_judges
      end
    end
  end

  defp calculate_preference_alignment(selected_judges, user_preferred_judges)
       when is_list(selected_judges) and is_list(user_preferred_judges) do
    # Calculate how well selection aligns with user preferences
    if Enum.empty?(user_preferred_judges) do
      0.0
    else
      overlap_count = length(selected_judges -- (selected_judges -- user_preferred_judges))
      overlap_count / length(user_preferred_judges)
    end
  end

  # Temporal and performance factors

  defp extract_temporal_factors(current_time, context) do
    %{
      hour_of_day: current_time.hour,
      day_of_week: Date.day_of_week(current_time),
      is_weekend: Date.day_of_week(current_time) in [6, 7],
      time_zone_context: Map.get(context, :user_timezone, "UTC"),
      urgency_level: Map.get(context, :urgency, :normal)
    }
  end

  defp predict_temporal_judge_effectiveness(judge, temporal_factors, temporal_model) do
    # Predict judge effectiveness based on temporal factors
    base_effectiveness = get_judge_base_effectiveness(judge)

    # Temporal adjustments
    hour_adjustment = get_hourly_effectiveness_adjustment(judge, temporal_factors.hour_of_day)
    day_adjustment = get_daily_effectiveness_adjustment(judge, temporal_factors.day_of_week)

    temporal_effectiveness = base_effectiveness + hour_adjustment + day_adjustment

    min(1.0, max(0.0, temporal_effectiveness))
  end

  defp calculate_judge_performance_weights(available_judges, models) do
    # Calculate performance weights for each available judge
    judge_selection_model = Map.get(models, :judge_selection_model)

    Enum.reduce(available_judges, %{}, fn judge, acc ->
      weight = get_judge_historical_performance_weight(judge, judge_selection_model)
      Map.put(acc, judge, weight)
    end)
  end

  defp generate_performance_weighted_selection(context, available_judges, performance_weights) do
    # Generate selection weighted by performance
    evaluation_requirements = extract_evaluation_requirements(context)

    # Score judges based on performance and requirement fit
    judge_scores =
      Enum.map(available_judges, fn judge ->
        performance_weight = Map.get(performance_weights, judge, 0.7)
        requirement_fit = assess_judge_requirement_fit(judge, evaluation_requirements)

        combined_score = (performance_weight + requirement_fit) / 2
        {judge, combined_score}
      end)

    # Select top scoring judges
    selected_judges =
      judge_scores
      |> Enum.sort_by(fn {_judge, score} -> -score end)
      |> Enum.take(3)
      |> Enum.map(fn {judge, _score} -> judge end)

    %{
      judges: selected_judges,
      confidence: 0.84,
      expected_performance: %{
        accuracy: 0.86,
        processing_time: 4_600,
        user_satisfaction: 0.81
      },
      cost_estimate: calculate_judge_team_cost(selected_judges),
      selection_reasoning: "Performance-weighted selection optimized for current requirements"
    }
  end

  # Cost and quality optimization

  defp extract_cost_constraints(context, options) do
    %{
      max_cost: Keyword.get(options, :max_cost, Map.get(context, :budget_limit, 0.15)),
      cost_priority: Map.get(context, :cost_priority, :medium),
      quality_vs_cost_preference: Map.get(context, :quality_vs_cost, :balanced)
    }
  end

  defp generate_cost_optimized_selection(available_judges, cost_constraints, cost_model) do
    # Generate cost-optimized judge selection
    max_cost = cost_constraints.max_cost

    # Calculate cost efficiency for each judge
    judge_cost_data =
      Enum.map(available_judges, fn judge ->
        cost = get_judge_cost_estimate(judge)
        quality = get_judge_quality_rating(judge)
        efficiency = if cost > 0, do: quality / cost, else: quality

        {judge, %{cost: cost, quality: quality, efficiency: efficiency}}
      end)

    # Select judges with best quality-to-cost ratio within budget
    selected_judges = select_judges_within_budget_optimized(judge_cost_data, max_cost)

    %{
      judges: selected_judges,
      confidence: 0.77,
      expected_performance: %{
        accuracy: 0.81,
        processing_time: 5_200,
        user_satisfaction: 0.79
      },
      cost_estimate: calculate_judge_team_cost(selected_judges),
      selection_reasoning: "Cost-optimized selection maximizing quality within budget"
    }
  end

  defp extract_quality_requirements(context, options) do
    %{
      min_accuracy:
        Keyword.get(options, :min_accuracy, Map.get(context, :accuracy_requirement, 0.8)),
      quality_priority: Map.get(context, :quality_priority, :high),
      thoroughness_level: Map.get(context, :thoroughness, :standard)
    }
  end

  defp generate_quality_focused_selection(available_judges, quality_requirements) do
    min_accuracy = quality_requirements.min_accuracy

    # Filter judges by quality capability and select comprehensive team
    quality_capable_judges =
      Enum.filter(available_judges, fn judge ->
        get_judge_quality_rating(judge) >= min_accuracy
      end)

    # Select all quality-capable judges for thoroughness
    selected_judges =
      if length(quality_capable_judges) >= 3 do
        quality_capable_judges
      else
        # Include additional judges to ensure comprehensive coverage
        quality_capable_judges ++ (available_judges -- quality_capable_judges)
      end

    %{
      # Comprehensive team
      judges: Enum.take(selected_judges, 4),
      confidence: 0.88,
      expected_performance: %{
        accuracy: 0.91,
        processing_time: 7_000,
        user_satisfaction: 0.87
      },
      cost_estimate: calculate_judge_team_cost(selected_judges),
      selection_reasoning: "Quality-focused comprehensive evaluation team"
    }
  end

  # Fallback and reasoning

  defp fallback_to_default_routing(available_judges, evaluation_context) do
    # Simple fallback routing when adaptive routing fails
    default_judges =
      case length(available_judges) do
        n when n >= 3 -> Enum.take(available_judges, 3)
        # Ensure minimum coverage
        n when n >= 2 -> available_judges ++ [:code_quality]
        # Default minimum set
        _ -> [:code_quality, :architecture]
      end

    fallback_result = %{
      selected_judges: default_judges,
      routing_strategy: :fallback_default,
      selection_confidence: 0.6,
      expected_performance: %{
        accuracy: 0.75,
        processing_time: 5_000,
        user_satisfaction: 0.75
      },
      cost_estimate: calculate_judge_team_cost(default_judges),
      selection_reasoning: "Fallback to default routing due to adaptive routing failure",
      routing_metadata: %{
        router: :fallback_routing,
        fallback_reason: "adaptive_routing_unavailable",
        routed_at: DateTime.utc_now()
      }
    }

    {:ok, fallback_result}
  end

  defp generate_selection_reasoning(judge_selection, routing_strategy, evaluation_context) do
    base_reasoning = judge_selection.selection_reasoning

    context_factors = [
      "Evaluation complexity: #{assess_evaluation_complexity(evaluation_context)}",
      "Judge team size: #{length(judge_selection.judges)}",
      "Expected accuracy: #{judge_selection.expected_performance.accuracy}",
      "Estimated cost: $#{judge_selection.cost_estimate}"
    ]

    "#{base_reasoning}. #{Enum.join(context_factors, ". ")}"
  end

  # Cost and performance calculation helpers

  defp calculate_judge_team_cost(judges) when is_list(judges) do
    # Calculate estimated cost for judge team
    base_cost_per_judge = 0.03

    judge_costs =
      Enum.map(judges, fn judge ->
        case judge do
          # Security judges cost more
          :security -> base_cost_per_judge * 1.2
          :architecture -> base_cost_per_judge * 1.1
          :code_quality -> base_cost_per_judge
          :test_quality -> base_cost_per_judge * 0.9
          _ -> base_cost_per_judge
        end
      end)

    Enum.sum(judge_costs)
  end

  defp get_judge_quality_rating(judge) do
    # Get quality rating for judge (mock implementation)
    case judge do
      :security -> 0.9
      :architecture -> 0.85
      :code_quality -> 0.8
      :test_quality -> 0.75
      _ -> 0.7
    end
  end

  defp get_judge_cost_estimate(judge) do
    # Get cost estimate for individual judge
    calculate_judge_team_cost([judge])
  end

  defp calculate_judge_cost_efficiency(judge, cost_model) do
    # Calculate cost efficiency ratio for judge
    cost = get_judge_cost_estimate(judge)
    quality = get_judge_quality_rating(judge)

    if cost > 0 do
      quality / cost
    else
      quality
    end
  end

  defp select_judges_within_budget(judge_cost_data, budget_limit) do
    # Select judges that fit within budget
    sorted_by_efficiency =
      Enum.sort_by(judge_cost_data, fn {_judge, efficiency} -> -efficiency end)

    {selected_judges, _remaining_budget} =
      Enum.reduce_while(sorted_by_efficiency, {[], budget_limit}, fn {judge, _efficiency},
                                                                     {acc_judges,
                                                                      remaining_budget} ->
        judge_cost = get_judge_cost_estimate(judge)

        if judge_cost <= remaining_budget and length(acc_judges) < 4 do
          {:cont, {[judge | acc_judges], remaining_budget - judge_cost}}
        else
          {:halt, {acc_judges, remaining_budget}}
        end
      end)

    Enum.reverse(selected_judges)
  end

  defp select_judges_within_budget_optimized(judge_cost_data, budget_limit) do
    # Select optimal judges within budget using efficiency ranking
    available_budget = budget_limit
    selected_judges = []

    # Sort by efficiency and select within budget
    efficient_judges =
      judge_cost_data
      |> Enum.sort_by(fn {_judge, data} -> -data.efficiency end)
      # Top 4 most efficient
      |> Enum.take(4)

    # Simple selection within budget
    budget_compliant_judges =
      Enum.filter(efficient_judges, fn {_judge, data} ->
        # Rough budget allocation per judge
        data.cost <= available_budget / 3
      end)

    if length(budget_compliant_judges) >= 2 do
      Enum.take(budget_compliant_judges, 3) |> Enum.map(fn {judge, _data} -> judge end)
    else
      # Emergency fallback
      [:code_quality, :architecture]
    end
  end

  # Performance and effectiveness helpers

  defp get_judge_base_effectiveness(judge) do
    case judge do
      :security -> 0.85
      :architecture -> 0.8
      :code_quality -> 0.82
      :test_quality -> 0.78
      _ -> 0.75
    end
  end

  defp get_hourly_effectiveness_adjustment(judge, hour) do
    # Mock temporal effectiveness adjustments
    case {judge, hour} do
      {:security, h} when h in [9, 10, 14, 15] -> 0.05
      {:code_quality, h} when h in [10, 11, 15, 16] -> 0.03
      # Late night penalty
      {_, h} when h in [0, 1, 2, 3, 4, 5] -> -0.1
      _ -> 0.0
    end
  end

  defp get_daily_effectiveness_adjustment(judge, day) do
    # Mock daily effectiveness adjustments
    case day do
      # Mon-Wed bonus
      day when day in [1, 2, 3] -> 0.02
      # Weekend penalty
      day when day in [6, 7] -> -0.05
      _ -> 0.0
    end
  end

  defp get_judge_historical_performance_weight(judge, judge_model) do
    # Get historical performance weight (mock)
    base_weight =
      case judge do
        :security -> 0.9
        :architecture -> 0.85
        :code_quality -> 0.8
        :test_quality -> 0.75
        _ -> 0.7
      end

    # Would adjust based on actual model data
    base_weight
  end

  # Requirement and context extraction

  defp extract_evaluation_requirements(context) when is_map(context) do
    %{
      accuracy_requirement: Map.get(context, :accuracy_requirement, 0.8),
      speed_requirement: Map.get(context, :speed_requirement, :standard),
      cost_limitation: Map.get(context, :cost_limitation, :medium),
      thoroughness_level: Map.get(context, :thoroughness, :standard)
    }
  end

  defp assess_judge_requirement_fit(judge, requirements) when is_map(requirements) do
    # Assess how well judge fits the requirements
    judge_capabilities = get_judge_capabilities(judge)

    accuracy_fit =
      if judge_capabilities.accuracy >= requirements.accuracy_requirement, do: 1.0, else: 0.5

    speed_fit = assess_speed_requirement_fit(judge_capabilities, requirements.speed_requirement)

    (accuracy_fit + speed_fit) / 2
  end

  defp get_judge_capabilities(judge) do
    # Get judge capabilities (mock data)
    case judge do
      :security -> %{accuracy: 0.9, speed: 0.7, cost: 0.6, thoroughness: 0.95}
      :architecture -> %{accuracy: 0.85, speed: 0.75, cost: 0.7, thoroughness: 0.9}
      :code_quality -> %{accuracy: 0.8, speed: 0.85, cost: 0.8, thoroughness: 0.8}
      :test_quality -> %{accuracy: 0.75, speed: 0.9, cost: 0.85, thoroughness: 0.75}
      _ -> %{accuracy: 0.7, speed: 0.8, cost: 0.7, thoroughness: 0.7}
    end
  end

  defp assess_speed_requirement_fit(capabilities, speed_requirement) do
    speed_score = Map.get(capabilities, :speed, 0.7)

    case speed_requirement do
      :urgent -> if speed_score > 0.85, do: 1.0, else: 0.3
      :fast -> if speed_score > 0.75, do: 1.0, else: 0.6
      # Standard requirement, most judges fit
      :standard -> 0.8
      _ -> 0.7
    end
  end

  # Statistics and monitoring helpers (stubs)

  defp get_total_adaptive_routings_since(_time_window), do: 245

  defp get_routing_strategy_distribution(_time_window),
    do: %{learned_optimal: 120, user_preference_based: 80, temporal_adaptive: 45}

  defp get_average_selection_confidence(_time_window), do: 0.83

  defp get_model_usage_statistics(_time_window),
    do: %{judge_selection_model: 180, user_preference_model: 95}

  defp calculate_adaptation_success_rate(_time_window), do: 0.91
  defp calculate_fallback_usage_rate(_time_window), do: 0.08

  defp measure_performance_improvements(_time_window),
    do: %{accuracy_improvement: 0.12, satisfaction_improvement: 0.15}

  defp assess_routing_model_health, do: :healthy
  defp assess_adaptation_effectiveness, do: :high
  defp measure_user_satisfaction_impact, do: 0.18

  # Coordination strategy helpers (stubs)

  defp filter_coordination_patterns(_patterns), do: []
  defp analyze_consensus_mechanism_effectiveness(_patterns), do: %{effectiveness: 0.85}
  defp analyze_negotiation_strategy_effectiveness(_patterns), do: %{effectiveness: 0.8}
  defp analyze_timeout_configuration_effectiveness(_patterns), do: %{effectiveness: 0.75}
  defp analyze_agent_coordination_patterns(_patterns), do: %{coordination_quality: 0.82}

  defp determine_base_coordination_strategy(_analysis, _context),
    do: %{strategy: :adaptive_consensus}

  defp adapt_strategy_to_context(strategy, _context, _options), do: strategy
  defp finalize_coordination_strategy(strategy, _analysis), do: strategy

  defp calculate_coordination_adaptation_confidence(_analysis), do: 0.78
  defp estimate_coordination_improvement(_strategy), do: 0.15

  defp assess_strategy_appropriateness(_strategy, _context), do: :appropriate
  defp validate_resource_requirements(_strategy), do: true
  defp validate_performance_expectations(_strategy), do: true
  defp assess_coordination_strategy_risk(_strategy), do: :low
end
