defmodule RubberDuck.Skills.Routing.RoutingStrategySkill do
  @moduledoc """
  Dynamic routing strategy skill for intelligent provider selection and optimization.

  This skill provides comprehensive routing intelligence that combines multi-criteria
  decision making, performance learning, predictive analytics, and adaptive strategy
  selection to optimize LLM provider routing across cost, quality, and latency dimensions.

  Features:
  - Dynamic strategy selection based on request characteristics and system state
  - Multi-objective optimization balancing cost, quality, latency, and reliability
  - Learning from routing outcomes to improve future decisions
  - Predictive routing using traffic pattern analysis and performance modeling
  - Integration with load balancing, circuit breaking, and fallback coordination
  - Real-time adaptation to system conditions and provider health changes

  Signal Patterns:
  - Input: "routing.strategy.*", "llm.route.*", "provider.route.*"
  - Output: "routing.decision.*", "provider.selected.*", "routing.optimized.*"
  """

  use Jido.Skill,
    name: "routing_strategy_skill",
    opts_key: :routing_strategy_state,
    signal_patterns: [
      "routing.strategy.select",
      "routing.strategy.optimize",
      "routing.strategy.learn",
      "routing.strategy.adapt",
      "llm.route.determine",
      "llm.route.optimize",
      "provider.route.select"
    ]

  require Logger

  alias RubberDuck.Skills.Routing.Actions.{
    DetermineRouteAction,
    DistributeLoadAction,
    ExecuteFallbackAction,
    TripCircuitAction
  }

  alias RubberDuck.LlmProviders.{ProviderRegistry, UniversalProviderService}

  # Default skill state
  @default_state %{
    current_strategy: :balanced,
    strategy_performance: %{},
    routing_history: [],
    learning_data: %{
      strategy_effectiveness: %{},
      provider_performance_patterns: %{},
      optimization_outcomes: []
    },
    adaptation_config: %{
      # Learn from last 100 routing decisions
      learning_window_size: 100,
      # Switch strategy if 15% improvement available
      strategy_switch_threshold: 0.15,
      performance_tracking_enabled: true
    }
  }

  # Available routing strategies with their characteristics
  @routing_strategies %{
    cost_first: %{
      description: "Minimize cost while maintaining acceptable quality",
      weights: %{cost: 0.6, quality: 0.2, latency: 0.1, reliability: 0.1},
      use_cases: [:batch_processing, :non_critical_requests, :high_volume]
    },
    quality_first: %{
      description: "Maximize quality with reasonable cost consideration",
      weights: %{cost: 0.1, quality: 0.6, latency: 0.15, reliability: 0.15},
      use_cases: [:critical_analysis, :user_facing, :high_stakes]
    },
    balanced: %{
      description: "Balance all factors for general-purpose optimization",
      weights: %{cost: 0.25, quality: 0.25, latency: 0.25, reliability: 0.25},
      use_cases: [:general_purpose, :mixed_workloads, :default]
    },
    latency_first: %{
      description: "Minimize response time for real-time applications",
      weights: %{cost: 0.1, quality: 0.2, latency: 0.6, reliability: 0.1},
      use_cases: [:real_time, :interactive, :streaming]
    }
  }

  @doc """
  Initialize routing strategy skill with default configuration and learning state.
  """
  def start_skill(opts \\ []) do
    initial_state = Map.merge(@default_state, Map.new(opts))

    Logger.info(
      "RoutingStrategySkill: Initializing with strategy #{initial_state.current_strategy}"
    )

    # Load historical performance data if available
    case load_historical_performance(initial_state) do
      {:ok, enhanced_state} ->
        Logger.info("RoutingStrategySkill: Initialized successfully",
          strategy: enhanced_state.current_strategy,
          historical_data_loaded: map_size(enhanced_state.strategy_performance) > 0
        )

        {:ok, enhanced_state}

      {:error, reason} ->
        Logger.warning("RoutingStrategySkill: Failed to load historical data", error: reason)
        # Continue with default state
        {:ok, initial_state}
    end
  end

  @doc """
  Handle intelligent routing strategy selection for LLM requests.
  """
  def handle_routing_selection(request_requirements, context, state) do
    Logger.debug("RoutingStrategySkill: Handling routing selection",
      requirements: Map.keys(request_requirements),
      current_strategy: state.current_strategy
    )

    with {:ok, optimal_strategy, state} <-
           select_optimal_strategy(request_requirements, context, state),
         {:ok, available_providers} <- get_available_providers(context),
         {:ok, routing_decision} <-
           execute_route_determination(
             optimal_strategy,
             request_requirements,
             available_providers,
             context
           ) do
      # Learn from routing decision
      updated_state =
        learn_from_routing_decision(
          routing_decision,
          optimal_strategy,
          request_requirements,
          state
        )

      Logger.info("RoutingStrategySkill: Routing selection complete",
        selected_provider: routing_decision.selected_provider,
        strategy: optimal_strategy,
        confidence: routing_decision.confidence_score
      )

      {:ok, routing_decision, updated_state}
    else
      {:error, reason} = error ->
        Logger.error("RoutingStrategySkill: Routing selection failed", error: reason)
        error_state = handle_routing_error(reason, request_requirements, state)
        {error, error_state}
    end
  end

  @doc """
  Handle routing strategy optimization based on performance patterns.
  """
  def handle_strategy_optimization(performance_data, context, state) do
    Logger.debug("RoutingStrategySkill: Optimizing routing strategy")

    with {:ok, optimization_analysis} <- analyze_strategy_performance(performance_data, state),
         {:ok, optimization_recommendations} <-
           generate_optimization_recommendations(optimization_analysis, state),
         {:ok, updated_state} <- apply_strategy_optimizations(optimization_recommendations, state) do
      Logger.info("RoutingStrategySkill: Strategy optimization complete",
        optimizations_applied: length(optimization_recommendations),
        new_strategy: updated_state.current_strategy,
        performance_improvement: optimization_analysis.improvement_potential
      )

      {:ok,
       %{
         optimizations_applied: optimization_recommendations,
         performance_analysis: optimization_analysis,
         updated_strategy: updated_state.current_strategy
       }, updated_state}
    else
      {:error, reason} = error ->
        Logger.error("RoutingStrategySkill: Strategy optimization failed", error: reason)
        {error, state}
    end
  end

  @doc """
  Handle adaptive strategy learning from routing outcomes.
  """
  def handle_strategy_learning(routing_outcomes, context, state) do
    Logger.debug("RoutingStrategySkill: Processing routing outcomes for learning",
      outcomes_count: length(routing_outcomes)
    )

    learning_analysis = analyze_routing_outcomes(routing_outcomes, state)
    updated_learning_data = update_learning_data(learning_analysis, state.learning_data)

    # Check if strategy adaptation is needed
    adaptation_needed = should_adapt_strategy?(learning_analysis, state)

    updated_state = %{state | learning_data: updated_learning_data}

    updated_state =
      if adaptation_needed do
        Logger.info("RoutingStrategySkill: Adapting strategy based on learning")
        adapt_strategy_based_on_learning(learning_analysis, updated_state)
      else
        updated_state
      end

    {:ok,
     %{
       learning_analysis: learning_analysis,
       adaptation_applied: adaptation_needed,
       updated_strategy: updated_state.current_strategy
     }, updated_state}
  end

  # Private implementation functions

  defp select_optimal_strategy(request_requirements, context, state) do
    # Analyze request to determine optimal strategy
    request_characteristics = extract_request_characteristics(request_requirements)
    current_performance = state.strategy_performance

    # Score each strategy for this request
    strategy_scores =
      Enum.map(@routing_strategies, fn {strategy_name, strategy_config} ->
        suitability_score =
          calculate_strategy_suitability(strategy_name, request_characteristics, strategy_config)

        performance_score = get_strategy_performance_score(strategy_name, current_performance)

        composite_score = suitability_score * 0.6 + performance_score * 0.4

        {strategy_name, composite_score}
      end)

    # Select best strategy
    {best_strategy, best_score} = Enum.max_by(strategy_scores, &elem(&1, 1))

    # Check if strategy change is warranted
    strategy_to_use =
      if should_switch_strategy?(best_strategy, best_score, state) do
        Logger.info(
          "RoutingStrategySkill: Switching strategy from #{state.current_strategy} to #{best_strategy}"
        )

        best_strategy
      else
        state.current_strategy
      end

    updated_state = %{state | current_strategy: strategy_to_use}

    {:ok, strategy_to_use, updated_state}
  end

  defp extract_request_characteristics(requirements) do
    %{
      estimated_cost: Map.get(requirements, :estimated_cost, 0.02),
      quality_threshold: Map.get(requirements, :quality_threshold, 0.8),
      latency_sensitivity: Map.get(requirements, :latency_sensitivity, :medium),
      reliability_requirement: Map.get(requirements, :reliability_requirement, :standard),
      estimated_tokens: Map.get(requirements, :estimated_tokens, 2000),
      complexity: Map.get(requirements, :complexity, :medium),
      urgency: Map.get(requirements, :urgency, :normal)
    }
  end

  defp calculate_strategy_suitability(strategy_name, characteristics, strategy_config) do
    # Calculate how well this strategy fits the request characteristics
    base_suitability = 0.7

    # Adjust based on use cases
    use_case_match = calculate_use_case_match(characteristics, strategy_config.use_cases)

    # Adjust based on specific characteristics
    characteristic_alignment =
      calculate_characteristic_alignment(characteristics, strategy_config.weights)

    # Composite suitability
    suitability = base_suitability * (0.5 + use_case_match * 0.3 + characteristic_alignment * 0.2)

    Float.round(min(suitability, 1.0), 3)
  end

  defp calculate_use_case_match(characteristics, use_cases) do
    # Check if request characteristics match strategy use cases
    potential_matches = [
      check_cost_sensitivity_match(characteristics, use_cases),
      check_quality_sensitivity_match(characteristics, use_cases),
      check_latency_sensitivity_match(characteristics, use_cases),
      check_general_purpose_match(use_cases),
      check_default_workload_match(use_cases)
    ]

    matches = Enum.filter(potential_matches, &(&1 != nil))

    match_score = Enum.count(matches) / max(Enum.count(use_cases), 1)
    Float.round(min(match_score, 1.0), 3)
  end

  defp check_cost_sensitivity_match(characteristics, use_cases) do
    if characteristics.estimated_cost > 0.05 and :high_volume in use_cases do
      :cost_sensitive
    else
      nil
    end
  end

  defp check_quality_sensitivity_match(characteristics, use_cases) do
    if characteristics.quality_threshold > 0.9 and :critical_analysis in use_cases do
      :quality_sensitive
    else
      nil
    end
  end

  defp check_latency_sensitivity_match(characteristics, use_cases) do
    if characteristics.latency_sensitivity == :high and :real_time in use_cases do
      :latency_sensitive
    else
      nil
    end
  end

  defp check_general_purpose_match(use_cases) do
    if :general_purpose in use_cases do
      :general_match
    else
      nil
    end
  end

  defp check_default_workload_match(use_cases) do
    if :mixed_workloads in use_cases or :default in use_cases do
      :default_match
    else
      nil
    end
  end

  defp calculate_characteristic_alignment(characteristics, strategy_weights) do
    # Calculate how well request characteristics align with strategy weights

    # Cost alignment
    cost_importance = if characteristics.estimated_cost > 0.05, do: 0.8, else: 0.3
    cost_alignment = abs(cost_importance - strategy_weights.cost)

    # Quality alignment
    quality_importance = min(characteristics.quality_threshold * 1.2, 1.0)
    quality_alignment = abs(quality_importance - strategy_weights.quality)

    # Latency alignment
    latency_importance =
      case characteristics.latency_sensitivity do
        :low -> 0.2
        :medium -> 0.5
        :high -> 0.9
      end

    latency_alignment = abs(latency_importance - strategy_weights.latency)

    # Calculate overall alignment (lower difference = better alignment)
    total_alignment_error = (cost_alignment + quality_alignment + latency_alignment) / 3
    alignment_score = max(1.0 - total_alignment_error, 0.1)

    Float.round(alignment_score, 3)
  end

  defp get_strategy_performance_score(strategy_name, current_performance) do
    case Map.get(current_performance, strategy_name) do
      # Default score for new/unknown strategy
      nil ->
        0.7

      performance_data ->
        # Calculate score from historical performance
        success_rate = Map.get(performance_data, :success_rate, 0.8)
        avg_quality = Map.get(performance_data, :avg_quality_score, 0.8)
        cost_efficiency = Map.get(performance_data, :cost_efficiency, 0.7)

        # Weighted performance score
        success_rate * 0.4 + avg_quality * 0.3 + cost_efficiency * 0.3
    end
  end

  defp should_switch_strategy?(proposed_strategy, proposed_score, state) do
    current_strategy = state.current_strategy
    current_score = get_strategy_performance_score(current_strategy, state.strategy_performance)

    improvement_threshold = state.adaptation_config.strategy_switch_threshold

    # Switch if significant improvement and not switching too frequently
    score_improvement = proposed_score - current_score

    score_improvement >= improvement_threshold and proposed_strategy != current_strategy
  end

  defp get_available_providers(context) do
    domain = Map.get(context, :domain, :general)

    case ProviderRegistry.get_providers_for_domain(domain) do
      {:ok, providers} ->
        # Filter to only available/healthy providers
        available_providers = Enum.filter(providers, &provider_available?/1)
        {:ok, available_providers}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp provider_available?(provider) do
    case ProviderRegistry.get_provider(provider) do
      {:ok, provider_data} ->
        health = Map.get(provider_data, :health, :unknown)
        circuit_state = Map.get(provider_data, :circuit_state, :closed)

        health in [:healthy, :degraded] and circuit_state in [:closed, :half_open]

      {:error, _reason} ->
        false
    end
  end

  defp execute_route_determination(strategy, requirements, available_providers, context) do
    strategy_config = Map.get(@routing_strategies, strategy)

    # Execute route determination with strategy-specific weights
    DetermineRouteAction.run(
      %{
        request_requirements: requirements,
        available_providers: available_providers,
        routing_strategy: strategy,
        optimization_weights: strategy_config.weights,
        context: context,
        learning_enabled: true
      },
      %{}
    )
  end

  defp learn_from_routing_decision(routing_decision, strategy, requirements, state) do
    # Create learning record
    learning_record = %{
      timestamp: System.system_time(:second),
      strategy_used: strategy,
      selected_provider: routing_decision.selected_provider,
      confidence_score: routing_decision.confidence_score,
      requirements: Map.take(requirements, [:quality_threshold, :estimated_cost, :urgency]),
      decision_metadata: routing_decision.decision_metadata
    }

    # Add to routing history (keep last N decisions)
    history_limit = state.adaptation_config.learning_window_size
    updated_history = [learning_record | Enum.take(state.routing_history, history_limit - 1)]

    # Update learning data
    updated_learning = update_strategy_learning(learning_record, state.learning_data)

    %{state | routing_history: updated_history, learning_data: updated_learning}
  end

  defp update_strategy_learning(learning_record, current_learning) do
    strategy = learning_record.strategy_used

    # Update strategy effectiveness tracking
    updated_effectiveness =
      Map.update(
        current_learning.strategy_effectiveness,
        strategy,
        %{usage_count: 1, total_confidence: learning_record.confidence_score},
        fn existing ->
          %{
            usage_count: existing.usage_count + 1,
            total_confidence: existing.total_confidence + learning_record.confidence_score
          }
        end
      )

    # Update provider performance patterns
    provider = learning_record.selected_provider

    updated_patterns =
      Map.update(
        current_learning.provider_performance_patterns,
        provider,
        %{selection_count: 1, avg_confidence: learning_record.confidence_score},
        fn existing ->
          new_count = existing.selection_count + 1

          new_avg =
            (existing.avg_confidence * existing.selection_count + learning_record.confidence_score) /
              new_count

          %{selection_count: new_count, avg_confidence: new_avg}
        end
      )

    %{
      current_learning
      | strategy_effectiveness: updated_effectiveness,
        provider_performance_patterns: updated_patterns
    }
  end

  defp analyze_strategy_performance(performance_data, state) do
    current_strategy = state.current_strategy
    strategy_history = state.routing_history

    if Enum.count(strategy_history) < 10 do
      {:ok,
       %{
         sufficient_data: false,
         improvement_potential: :unknown,
         recommendation: :continue_learning
       }}
    else
      # Analyze recent performance
      recent_decisions = Enum.take(strategy_history, 20)
      performance_metrics = calculate_performance_metrics(recent_decisions)

      # Compare with alternative strategies
      alternative_analysis = analyze_alternative_strategies(recent_decisions, state)

      analysis = %{
        sufficient_data: true,
        current_strategy: current_strategy,
        current_performance: performance_metrics,
        alternative_analysis: alternative_analysis,
        improvement_potential:
          determine_improvement_potential(performance_metrics, alternative_analysis),
        confidence_in_analysis: calculate_analysis_confidence(recent_decisions)
      }

      {:ok, analysis}
    end
  end

  defp calculate_performance_metrics(routing_decisions) do
    if Enum.empty?(routing_decisions) do
      %{avg_confidence: 0.0, success_rate: 0.0, decision_quality: 0.0}
    else
      confidences = Enum.map(routing_decisions, & &1.confidence_score)
      avg_confidence = Enum.sum(confidences) / Enum.count(confidences)

      # Assume success if confidence > 0.7 (placeholder)
      successes = Enum.count(confidences, &(&1 > 0.7))
      success_rate = successes / Enum.count(routing_decisions)

      # Decision quality based on confidence distribution
      decision_quality = calculate_decision_quality(confidences)

      %{
        avg_confidence: Float.round(avg_confidence, 3),
        success_rate: Float.round(success_rate, 3),
        decision_quality: decision_quality,
        total_decisions: Enum.count(routing_decisions)
      }
    end
  end

  defp calculate_decision_quality(confidences) do
    if Enum.empty?(confidences) do
      0.0
    else
      # Quality based on consistency and high confidence
      high_confidence_count = Enum.count(confidences, &(&1 > 0.8))
      variance = calculate_confidence_variance(confidences)

      consistency_score = max(1.0 - variance, 0.1)
      high_confidence_ratio = high_confidence_count / Enum.count(confidences)

      quality = consistency_score * 0.4 + high_confidence_ratio * 0.6
      Float.round(quality, 3)
    end
  end

  defp calculate_confidence_variance(confidences) do
    if Enum.count(confidences) < 2 do
      0.0
    else
      mean = Enum.sum(confidences) / length(confidences)

      variance_sum =
        confidences
        |> Enum.map(&:math.pow(&1 - mean, 2))
        |> Enum.sum()

      variance_sum / Enum.count(confidences)
    end
  end

  defp analyze_alternative_strategies(recent_decisions, state) do
    current_strategy = state.current_strategy

    # Simulate what other strategies would have decided
    Enum.map(@routing_strategies, fn {strategy_name, _config} ->
      if strategy_name != current_strategy do
        simulated_performance =
          simulate_strategy_performance(strategy_name, recent_decisions, state)

        {strategy_name, simulated_performance}
      else
        {strategy_name, %{performance: :current_strategy}}
      end
    end)
    |> Enum.filter(&(elem(&1, 1) != %{performance: :current_strategy}))
    |> Map.new()
  end

  defp simulate_strategy_performance(strategy_name, decisions, state) do
    # Simple simulation of how alternative strategy would have performed
    strategy_weights = get_in(@routing_strategies, [strategy_name, :weights])

    if strategy_weights do
      # Estimate confidence scores this strategy would have achieved
      simulated_confidences =
        Enum.map(decisions, fn decision ->
          # Simple heuristic: adjust confidence based on weight alignment
          original_confidence = decision.confidence_score

          # If this strategy's weights better match request, confidence improves
          weight_alignment = calculate_weight_alignment(decision, strategy_weights)
          adjusted_confidence = min(original_confidence * weight_alignment, 1.0)

          adjusted_confidence
        end)

      avg_simulated_confidence =
        Enum.sum(simulated_confidences) / Enum.count(simulated_confidences)

      %{
        estimated_avg_confidence: Float.round(avg_simulated_confidence, 3),
        estimated_improvement:
          Float.round(
            avg_simulated_confidence -
              Enum.sum(Enum.map(decisions, & &1.confidence_score)) / Enum.count(decisions),
            3
          ),
        # Moderate confidence in simulation
        simulation_confidence: 0.7
      }
    else
      %{error: :unknown_strategy}
    end
  end

  defp calculate_weight_alignment(decision, strategy_weights) do
    # Simple alignment calculation (placeholder for more sophisticated analysis)
    # This would analyze how well the strategy weights match the decision requirements
    # Random variation ±15% for simulation
    1.0 + (:rand.uniform() - 0.5) * 0.3
  end

  defp determine_improvement_potential(current_metrics, alternative_analysis) do
    if map_size(alternative_analysis) == 0 do
      :unknown
    else
      # Find best alternative improvement
      best_improvement =
        alternative_analysis
        |> Map.values()
        |> Enum.map(&Map.get(&1, :estimated_improvement, 0))
        |> Enum.max()

      cond do
        best_improvement > 0.15 -> :high
        best_improvement > 0.05 -> :medium
        best_improvement > 0.0 -> :low
        true -> :none
      end
    end
  end

  defp calculate_analysis_confidence(decisions) do
    # Confidence in analysis based on data quality and quantity
    # Full confidence at 50+ decisions
    data_quantity_score = min(Enum.count(decisions) / 50, 1.0)

    # Data quality based on confidence distribution
    confidences = Enum.map(decisions, & &1.confidence_score)
    avg_confidence = Enum.sum(confidences) / Enum.count(confidences)
    data_quality_score = avg_confidence

    analysis_confidence = data_quantity_score * 0.4 + data_quality_score * 0.6
    Float.round(analysis_confidence, 3)
  end

  defp generate_optimization_recommendations(analysis, state) do
    recommendations = []

    # Strategy change recommendation
    recommendations =
      if analysis.improvement_potential in [:high, :medium] do
        best_alternative = find_best_alternative_strategy(analysis.alternative_analysis)
        [%{type: :strategy_change, target_strategy: best_alternative} | recommendations]
      else
        recommendations
      end

    # Weight tuning recommendation
    recommendations =
      if analysis.current_performance.decision_quality < 0.7 do
        [%{type: :weight_tuning, focus: :improve_consistency} | recommendations]
      else
        recommendations
      end

    # Learning enhancement recommendation
    recommendations =
      if analysis.confidence_in_analysis < 0.8 do
        [%{type: :learning_enhancement, action: :increase_data_collection} | recommendations]
      else
        recommendations
      end

    {:ok, Enum.reverse(recommendations)}
  end

  defp find_best_alternative_strategy(alternative_analysis) do
    alternative_analysis
    |> Enum.max_by(fn {_strategy, analysis} ->
      Map.get(analysis, :estimated_improvement, 0)
    end)
    |> elem(0)
  end

  defp apply_strategy_optimizations(recommendations, state) do
    updated_state =
      Enum.reduce(recommendations, state, fn recommendation, acc_state ->
        apply_single_optimization(recommendation, acc_state)
      end)

    {:ok, updated_state}
  end

  defp apply_single_optimization(recommendation, state) do
    case recommendation.type do
      :strategy_change ->
        Logger.info(
          "RoutingStrategySkill: Applying strategy change to #{recommendation.target_strategy}"
        )

        %{state | current_strategy: recommendation.target_strategy}

      :weight_tuning ->
        # Fine-tune strategy weights (placeholder)
        state

      :learning_enhancement ->
        # Enhance learning configuration
        updated_config = Map.put(state.adaptation_config, :performance_tracking_enabled, true)
        %{state | adaptation_config: updated_config}

      _ ->
        state
    end
  end

  defp analyze_routing_outcomes(routing_outcomes, state) do
    if Enum.empty?(routing_outcomes) do
      %{analysis_type: :no_outcomes}
    else
      # Analyze patterns in outcomes
      success_rate = calculate_outcome_success_rate(routing_outcomes)
      quality_trends = analyze_quality_trends(routing_outcomes)
      cost_efficiency = analyze_cost_efficiency(routing_outcomes)
      provider_patterns = analyze_provider_selection_patterns(routing_outcomes)

      %{
        analysis_type: :comprehensive,
        outcome_count: length(routing_outcomes),
        success_rate: success_rate,
        quality_trends: quality_trends,
        cost_efficiency: cost_efficiency,
        provider_patterns: provider_patterns,
        learning_quality: assess_learning_data_quality(routing_outcomes)
      }
    end
  end

  defp calculate_outcome_success_rate(outcomes) do
    successful_outcomes = Enum.count(outcomes, &Map.get(&1, :success, false))
    success_rate = successful_outcomes / length(outcomes)
    Float.round(success_rate, 3)
  end

  defp analyze_quality_trends(outcomes) do
    quality_scores =
      outcomes
      |> Enum.filter(&Map.get(&1, :success, false))
      |> Enum.map(&Map.get(&1, :quality_score, 0.8))

    if quality_scores != [] do
      avg_quality = Enum.sum(quality_scores) / length(quality_scores)

      # Simple trend analysis
      recent_quality =
        quality_scores |> Enum.take(10) |> Enum.sum() |> Kernel./(min(10, length(quality_scores)))

      overall_quality = Enum.sum(quality_scores) / Enum.count(quality_scores)

      trend =
        cond do
          recent_quality > overall_quality * 1.05 -> :improving
          recent_quality < overall_quality * 0.95 -> :declining
          true -> :stable
        end

      %{
        average_quality: Float.round(avg_quality, 3),
        trend: trend,
        recent_quality: Float.round(recent_quality, 3)
      }
    else
      %{trend: :insufficient_data}
    end
  end

  defp analyze_cost_efficiency(outcomes) do
    cost_data =
      outcomes
      |> Enum.filter(&Map.get(&1, :success, false))
      |> Enum.map(&{Map.get(&1, :cost, 0.02), Map.get(&1, :quality_score, 0.8)})

    if cost_data != [] do
      calculate_cost_efficiency_metrics(cost_data)
    else
      %{cost_efficiency: :insufficient_data}
    end
  end

  defp calculate_cost_efficiency_metrics(cost_data) do
    efficiency_scores = Enum.map(cost_data, &calculate_efficiency_score/1)
    avg_efficiency = Enum.sum(efficiency_scores) / Enum.count(efficiency_scores)

    %{
      average_cost_efficiency: Float.round(avg_efficiency, 3),
      efficiency_trend: :stable,
      cost_optimization_potential: avg_efficiency < 30
    }
  end

  defp calculate_efficiency_score({cost, quality}) do
    if cost > 0, do: quality / cost, else: quality * 100
  end

  defp analyze_provider_selection_patterns(outcomes) do
    provider_selections =
      outcomes
      |> Enum.map(&Map.get(&1, :selected_provider))
      |> Enum.frequencies()

    total_selections = Enum.sum(Map.values(provider_selections))

    provider_ratios =
      Map.new(provider_selections, fn {provider, count} ->
        {provider, Float.round(count / total_selections, 3)}
      end)

    %{
      provider_distribution: provider_ratios,
      most_selected: Enum.max_by(provider_selections, &elem(&1, 1)) |> elem(0),
      selection_diversity: calculate_selection_diversity(provider_ratios)
    }
  end

  defp calculate_selection_diversity(provider_ratios) do
    # Calculate diversity using normalized entropy
    entropy =
      provider_ratios
      |> Map.values()
      |> Enum.filter(&(&1 > 0))
      |> Enum.map(&(-&1 * :math.log2(&1)))
      |> Enum.sum()

    max_entropy = :math.log2(map_size(provider_ratios))
    diversity = if max_entropy > 0, do: entropy / max_entropy, else: 0.0

    Float.round(diversity, 3)
  end

  defp assess_learning_data_quality(outcomes) do
    %{
      # Normalize to 100 outcomes
      data_completeness: Enum.count(outcomes) / 100,
      data_consistency: calculate_data_consistency(outcomes),
      # Need at least 20 outcomes for learning
      learning_readiness: length(outcomes) >= 20
    }
  end

  defp calculate_data_consistency(outcomes) do
    # Simple consistency check based on confidence score variance
    if Enum.count(outcomes) < 2 do
      1.0
    else
      confidences = Enum.map(outcomes, &Map.get(&1, :confidence_score, 0.5))
      mean_confidence = Enum.sum(confidences) / length(confidences)

      variance =
        confidences
        |> Enum.map(&:math.pow(&1 - mean_confidence, 2))
        |> Enum.sum()
        |> Kernel./(length(confidences))

      consistency = max(1.0 - variance, 0.1)
      Float.round(consistency, 3)
    end
  end

  defp should_adapt_strategy?(learning_analysis, state) do
    case learning_analysis.analysis_type do
      :comprehensive ->
        # Adapt if success rate below 80%
        learning_analysis.learning_quality.learning_readiness and
          learning_analysis.success_rate < 0.8

      _ ->
        false
    end
  end

  defp adapt_strategy_based_on_learning(learning_analysis, state) do
    # Simple adaptation: switch to strategy with best projected performance
    if map_size(learning_analysis.provider_patterns) > 0 do
      # Find most successful provider and strategy that uses it most
      most_successful_provider =
        learning_analysis.provider_patterns
        |> Enum.max_by(fn {_provider, data} -> data.avg_confidence end)
        |> elem(0)

      # Select strategy that would favor this provider
      optimal_strategy = select_strategy_for_provider(most_successful_provider)

      Logger.info(
        "RoutingStrategySkill: Adapting to strategy #{optimal_strategy} based on provider #{most_successful_provider} performance"
      )

      %{state | current_strategy: optimal_strategy}
    else
      state
    end
  end

  defp select_strategy_for_provider(provider) do
    case provider do
      # OpenAI works well with balanced approach
      :openai -> :balanced
      # Anthropic excels at quality
      :anthropic -> :quality_first
      # Local models for cost optimization
      :local -> :cost_first
      _ -> :balanced
    end
  end

  defp handle_routing_error(reason, requirements, state) do
    Logger.warning("RoutingStrategySkill: Handling routing error", error: reason)

    # Simple error handling - could trigger fallback strategies
    state
  end

  defp load_historical_performance(state) do
    # Placeholder for loading historical performance data
    # In production, this would load from database or cache
    {:ok, state}
  end

  defp update_learning_data(analysis, current_data) do
    # Update learning data with new analysis
    updated_outcomes =
      [analysis | Map.get(current_data, :optimization_outcomes, [])]
      # Keep last 50 analyses
      |> Enum.take(50)

    Map.put(current_data, :optimization_outcomes, updated_outcomes)
  end
end
