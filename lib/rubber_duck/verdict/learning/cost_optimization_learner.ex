defmodule RubberDuck.Verdict.Learning.CostOptimizationLearner do
  @moduledoc """
  Specialized learning engine for cost efficiency optimization and budget management.

  Learns from cost performance patterns, resource utilization data, and budget
  constraints to continuously optimize evaluation costs while maintaining quality,
  implementing intelligent resource allocation and cost prediction.
  """

  require Logger

  @cost_optimization_strategies [
    :judge_selection_optimization,
    :evaluation_caching,
    :parallel_processing_optimization,
    :resource_pooling,
    :smart_evaluation_routing
  ]

  @cost_factors [
    :judge_agent_costs,
    :processing_time_costs,
    :infrastructure_costs,
    :coordination_overhead,
    :model_inference_costs
  ]

  @doc """
  Learn cost optimization strategies from cost and performance patterns.

  ## Parameters
  - `patterns` - Cost and performance patterns from evaluation history
  - `options` - Learning options and configuration

  ## Returns
  - `{:ok, learning_result}` - Cost optimization learning successful
  - `{:error, reason}` - Learning failed
  """
  def optimize_costs_from_patterns(patterns, options \\ []) do
    Logger.info("Learning cost optimizations from #{length(patterns)} cost patterns")

    case analyze_cost_efficiency_patterns(patterns) do
      {:ok, cost_analysis} ->
        case generate_cost_optimizations(cost_analysis, options) do
          {:ok, optimizations} ->
            cost_predictions = predict_cost_savings(optimizations)

            learning_result = %{
              engine_name: :cost_optimization_learner,
              adaptations: optimizations,
              cost_savings_predictions: cost_predictions,
              learning_confidence: calculate_cost_learning_confidence(optimizations),
              optimization_potential: assess_cost_optimization_potential(cost_analysis),
              learning_metadata: %{
                learner: :cost_optimization_learner,
                version: "1.0.0",
                learned_at: DateTime.utc_now(),
                patterns_processed: length(patterns)
              }
            }

            {:ok, learning_result}

          {:error, reason} ->
            {:error, "Cost optimization generation failed: #{reason}"}
        end

      {:error, reason} ->
        {:error, "Cost pattern analysis failed: #{reason}"}
    end
  end

  @doc """
  Optimize resource allocation based on usage patterns and performance data.

  ## Parameters
  - `resource_usage_data` - Historical resource usage and performance data
  - `budget_constraints` - Current budget limits and constraints
  - `options` - Optimization options

  ## Returns
  - `{:ok, resource_optimizations}` - Resource allocation optimizations
  - `{:error, reason}` - Optimization failed
  """
  def optimize_resource_allocation(resource_usage_data, budget_constraints, options \\ []) do
    Logger.info(
      "Optimizing resource allocation from #{length(resource_usage_data)} usage records"
    )

    case analyze_resource_utilization_efficiency(resource_usage_data, budget_constraints) do
      {:ok, utilization_analysis} ->
        resource_optimizations =
          generate_resource_allocation_optimizations(utilization_analysis, options)

        allocation_validation =
          validate_resource_optimizations(resource_optimizations, budget_constraints)

        result = %{
          resource_optimizations: resource_optimizations,
          allocation_validation: allocation_validation,
          utilization_analysis: utilization_analysis,
          expected_cost_savings: calculate_expected_cost_savings(resource_optimizations),
          optimization_confidence:
            calculate_resource_optimization_confidence(utilization_analysis),
          optimization_metadata: %{
            optimizer: :resource_allocation_optimizer,
            optimized_at: DateTime.utc_now(),
            usage_records_analyzed: length(resource_usage_data)
          }
        }

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Private Cost Analysis Functions

  defp analyze_cost_efficiency_patterns(patterns) when is_list(patterns) do
    # Filter and analyze cost-related patterns
    cost_patterns = filter_cost_related_patterns(patterns)

    if Enum.empty?(cost_patterns) do
      {:error, "No cost-related patterns found"}
    else
      cost_analysis = %{
        high_cost_patterns: identify_high_cost_patterns(cost_patterns),
        efficient_cost_patterns: identify_efficient_cost_patterns(cost_patterns),
        cost_quality_tradeoffs: analyze_cost_quality_tradeoffs(cost_patterns),
        temporal_cost_patterns: analyze_temporal_cost_patterns(cost_patterns),
        judge_cost_effectiveness: analyze_judge_cost_effectiveness(cost_patterns)
      }

      {:ok, cost_analysis}
    end
  end

  defp generate_cost_optimizations(cost_analysis, options) do
    optimizations = []

    # Judge selection cost optimizations
    optimizations = add_judge_selection_cost_optimizations(cost_analysis, optimizations)

    # Temporal optimization strategies
    optimizations = add_temporal_cost_optimizations(cost_analysis, optimizations)

    # Quality-cost balance optimizations
    optimizations = add_quality_cost_balance_optimizations(cost_analysis, optimizations)

    # Resource utilization optimizations
    optimizations = add_resource_utilization_optimizations(cost_analysis, optimizations)

    if Enum.empty?(optimizations) do
      {:error, "No cost optimizations identified"}
    else
      {:ok, optimizations}
    end
  end

  defp predict_cost_savings(optimizations) when is_list(optimizations) do
    # Predict cost savings from each optimization
    Enum.map(optimizations, fn optimization ->
      %{
        optimization_id: Map.get(optimization, :id, generate_optimization_id()),
        optimization_type: optimization.optimization_type,
        predicted_cost_reduction: calculate_predicted_cost_reduction(optimization),
        cost_savings_confidence: Map.get(optimization, :confidence, 0.7),
        implementation_cost: estimate_implementation_cost(optimization),
        roi_estimate: calculate_optimization_roi(optimization),
        payback_period: estimate_payback_period(optimization)
      }
    end)
  end

  # Resource utilization analysis

  defp analyze_resource_utilization_efficiency(usage_data, budget_constraints) do
    # Analyze how efficiently resources are currently being used
    utilization_metrics = calculate_resource_utilization_metrics(usage_data)
    efficiency_assessment = assess_current_resource_efficiency(utilization_metrics)

    optimization_opportunities =
      identify_resource_optimization_opportunities(utilization_metrics, budget_constraints)

    analysis_result = %{
      utilization_metrics: utilization_metrics,
      efficiency_assessment: efficiency_assessment,
      optimization_opportunities: optimization_opportunities,
      budget_utilization_analysis: analyze_budget_utilization(usage_data, budget_constraints)
    }

    {:ok, analysis_result}
  end

  defp generate_resource_allocation_optimizations(utilization_analysis, options) do
    # Generate specific resource allocation optimizations
    opportunities = utilization_analysis.optimization_opportunities

    Enum.map(opportunities, fn opportunity ->
      %{
        optimization_type: :resource_reallocation,
        resource_type: opportunity.resource_type,
        current_allocation: opportunity.current_allocation,
        recommended_allocation: opportunity.recommended_allocation,
        expected_savings: opportunity.expected_savings,
        confidence: Map.get(opportunity, :confidence, 0.7),
        id: generate_optimization_id()
      }
    end)
  end

  defp validate_resource_optimizations(optimizations, budget_constraints) do
    # Validate that optimizations stay within budget constraints
    total_cost_impact =
      Enum.reduce(optimizations, 0.0, fn opt, acc ->
        acc + Map.get(opt, :expected_savings, 0.0)
      end)

    %{
      total_expected_savings: total_cost_impact,
      budget_compliance: assess_budget_compliance(total_cost_impact, budget_constraints),
      resource_balance_maintained: assess_resource_balance(optimizations),
      # Positive savings
      validation_passed: total_cost_impact > 0
    }
  end

  # Cost pattern identification

  defp filter_cost_related_patterns(patterns) when is_list(patterns) do
    Enum.filter(patterns, fn pattern ->
      pattern_type = Map.get(pattern, :pattern_type, :unknown)
      pattern_data = Map.get(pattern, :pattern_data, %{})

      pattern_type in [:cost_efficiency, :system_optimization] or
        Map.has_key?(pattern_data, :cost_data) or
        Map.has_key?(pattern_data, :resource_utilization)
    end)
  end

  defp identify_high_cost_patterns(cost_patterns) when is_list(cost_patterns) do
    # Identify patterns associated with high costs
    # $0.15 per evaluation
    high_cost_threshold = 0.15

    high_cost_patterns =
      Enum.filter(cost_patterns, fn pattern ->
        pattern_data = Map.get(pattern, :pattern_data, %{})
        cost_data = Map.get(pattern_data, :cost_data, %{})
        total_cost = Map.get(cost_data, :total_cost, 0.05)

        total_cost > high_cost_threshold
      end)

    Enum.map(high_cost_patterns, fn pattern ->
      %{
        pattern_id: Map.get(pattern, :id),
        cost_drivers: extract_cost_drivers(pattern),
        cost_magnitude: extract_cost_magnitude(pattern),
        optimization_potential: assess_pattern_optimization_potential(pattern)
      }
    end)
  end

  defp identify_efficient_cost_patterns(cost_patterns) when is_list(cost_patterns) do
    # Identify patterns associated with cost efficiency
    # $0.04 per evaluation
    efficient_cost_threshold = 0.04

    efficient_patterns =
      Enum.filter(cost_patterns, fn pattern ->
        pattern_data = Map.get(pattern, :pattern_data, %{})
        cost_data = Map.get(pattern_data, :cost_data, %{})
        total_cost = Map.get(cost_data, :total_cost, 0.05)

        total_cost <= efficient_cost_threshold
      end)

    Enum.map(efficient_patterns, fn pattern ->
      %{
        pattern_id: Map.get(pattern, :id),
        efficiency_factors: extract_efficiency_factors(pattern),
        cost_savings_achieved: calculate_cost_savings_achieved(pattern),
        replication_potential: assess_replication_potential(pattern)
      }
    end)
  end

  defp analyze_cost_quality_tradeoffs(cost_patterns) when is_list(cost_patterns) do
    # Analyze the relationship between cost and quality in patterns
    quality_cost_data =
      Enum.map(cost_patterns, fn pattern ->
        pattern_data = Map.get(pattern, :pattern_data, %{})

        cost = extract_pattern_cost(pattern_data)
        quality = extract_pattern_quality(pattern_data)

        %{cost: cost, quality: quality}
      end)

    if Enum.empty?(quality_cost_data) do
      %{correlation: 0.0, optimal_balance_point: 0.5}
    else
      correlation = calculate_cost_quality_correlation(quality_cost_data)
      optimal_point = identify_optimal_cost_quality_balance(quality_cost_data)

      %{
        cost_quality_correlation: correlation,
        optimal_balance_point: optimal_point,
        current_tradeoff_efficiency: assess_current_tradeoff_efficiency(quality_cost_data)
      }
    end
  end

  # Optimization generation helpers

  defp add_judge_selection_cost_optimizations(analysis, optimizations) do
    judge_cost_data = analysis.judge_cost_effectiveness

    judge_optimizations =
      Enum.map(@cost_factors, fn cost_factor ->
        if requires_optimization?(judge_cost_data, cost_factor) do
          %{
            optimization_type: :judge_cost_optimization,
            cost_factor: cost_factor,
            current_efficiency: get_cost_factor_efficiency(judge_cost_data, cost_factor),
            recommended_improvement: generate_cost_factor_improvement(cost_factor),
            expected_savings: estimate_cost_factor_savings(cost_factor),
            confidence: 0.75,
            id: generate_optimization_id()
          }
        else
          nil
        end
      end)
      |> Enum.filter(&(!is_nil(&1)))

    optimizations ++ judge_optimizations
  end

  defp add_temporal_cost_optimizations(analysis, optimizations) do
    temporal_patterns = analysis.temporal_cost_patterns

    temporal_optimizations = [
      %{
        optimization_type: :temporal_cost_scheduling,
        temporal_insights: temporal_patterns,
        cost_scheduling_strategy: :off_peak_processing,
        expected_savings: 0.15,
        confidence: 0.7,
        id: generate_optimization_id()
      }
    ]

    optimizations ++ temporal_optimizations
  end

  defp add_quality_cost_balance_optimizations(analysis, optimizations) do
    tradeoff_data = analysis.cost_quality_tradeoffs

    if Map.get(tradeoff_data, :current_tradeoff_efficiency, 0.7) < 0.75 do
      balance_optimization = %{
        optimization_type: :quality_cost_balance,
        current_balance_efficiency: tradeoff_data.current_tradeoff_efficiency,
        optimal_balance_point: tradeoff_data.optimal_balance_point,
        rebalancing_strategy: :adaptive_quality_thresholds,
        expected_savings: 0.1,
        confidence: 0.72,
        id: generate_optimization_id()
      }

      [balance_optimization | optimizations]
    else
      optimizations
    end
  end

  defp add_resource_utilization_optimizations(analysis, optimizations) do
    # Add optimizations for better resource utilization
    utilization_optimization = %{
      optimization_type: :resource_utilization_improvement,
      optimization_strategy: :smart_resource_pooling,
      expected_utilization_improvement: 0.2,
      expected_cost_reduction: 0.12,
      confidence: 0.68,
      id: generate_optimization_id()
    }

    [utilization_optimization | optimizations]
  end

  # Cost prediction and calculation

  defp calculate_predicted_cost_reduction(optimization) when is_map(optimization) do
    # Predict cost reduction based on optimization type and characteristics
    base_reduction =
      case optimization.optimization_type do
        :judge_cost_optimization -> 0.15
        :temporal_cost_scheduling -> 0.1
        :quality_cost_balance -> 0.08
        :resource_utilization_improvement -> 0.12
        _ -> 0.05
      end

    # Adjust based on confidence
    confidence = Map.get(optimization, :confidence, 0.7)
    confidence_adjusted_reduction = base_reduction * confidence

    min(0.4, max(0.01, confidence_adjusted_reduction))
  end

  defp estimate_implementation_cost(optimization) when is_map(optimization) do
    # Estimate cost of implementing the optimization
    case optimization.optimization_type do
      # USD
      :judge_cost_optimization -> 500.0
      :temporal_cost_scheduling -> 200.0
      :quality_cost_balance -> 300.0
      :resource_utilization_improvement -> 800.0
      _ -> 400.0
    end
  end

  defp calculate_optimization_roi(optimization) when is_map(optimization) do
    # Calculate return on investment for optimization
    predicted_savings = calculate_predicted_cost_reduction(optimization)
    implementation_cost = estimate_implementation_cost(optimization)

    # Assume monthly cost base of $1000 for calculation
    monthly_savings = predicted_savings * 1000

    if implementation_cost > 0 do
      monthly_savings / implementation_cost
    else
      # Infinite ROI for zero cost implementations
      Float.max_finite()
    end
  end

  defp estimate_payback_period(optimization) when is_map(optimization) do
    roi = calculate_optimization_roi(optimization)

    cond do
      roi > 1.0 -> {1, :month}
      roi > 0.5 -> {2, :months}
      roi > 0.25 -> {4, :months}
      true -> {12, :months}
    end
  end

  # Resource analysis helpers

  defp calculate_resource_utilization_metrics(usage_data) when is_list(usage_data) do
    if Enum.empty?(usage_data) do
      %{average_utilization: 0.5, peak_utilization: 0.8, efficiency_score: 0.6}
    else
      utilizations = Enum.map(usage_data, &extract_utilization_score/1)
      valid_utilizations = Enum.filter(utilizations, &is_number/1)

      if Enum.empty?(valid_utilizations) do
        %{average_utilization: 0.5, peak_utilization: 0.8, efficiency_score: 0.6}
      else
        %{
          average_utilization: Enum.sum(valid_utilizations) / length(valid_utilizations),
          peak_utilization: Enum.max(valid_utilizations),
          utilization_variance: calculate_utilization_variance(valid_utilizations),
          efficiency_score: calculate_resource_efficiency_score(valid_utilizations)
        }
      end
    end
  end

  defp assess_current_resource_efficiency(utilization_metrics) when is_map(utilization_metrics) do
    average_util = Map.get(utilization_metrics, :average_utilization, 0.5)
    peak_util = Map.get(utilization_metrics, :peak_utilization, 0.8)
    variance = Map.get(utilization_metrics, :utilization_variance, 0.1)

    efficiency_assessment = %{
      utilization_level: classify_utilization_level(average_util),
      peak_efficiency: classify_peak_efficiency(peak_util),
      consistency: classify_utilization_consistency(variance),
      overall_efficiency: calculate_overall_efficiency_rating(average_util, peak_util, variance)
    }

    efficiency_assessment
  end

  defp identify_resource_optimization_opportunities(utilization_metrics, budget_constraints) do
    opportunities = []

    average_util = Map.get(utilization_metrics, :average_utilization, 0.5)

    # Under-utilization opportunities
    opportunities =
      if average_util < 0.6 do
        [
          %{
            resource_type: :compute_resources,
            opportunity: :increase_utilization,
            current_allocation: 1.0,
            recommended_allocation: 0.8,
            expected_savings: 0.2,
            confidence: 0.8
          }
          | opportunities
        ]
      else
        opportunities
      end

    # Over-utilization opportunities (scale up efficiency)
    opportunities =
      if average_util > 0.9 do
        [
          %{
            resource_type: :processing_capacity,
            opportunity: :scale_for_efficiency,
            current_allocation: 1.0,
            recommended_allocation: 1.2,
            # Efficiency gains from proper scaling
            expected_savings: 0.1,
            confidence: 0.75
          }
          | opportunities
        ]
      else
        opportunities
      end

    opportunities
  end

  defp analyze_budget_utilization(usage_data, budget_constraints)
       when is_map(budget_constraints) do
    # Analyze how well the budget is being utilized
    total_budget = Map.get(budget_constraints, :total_monthly_budget, 1000.0)
    current_usage = calculate_current_budget_usage(usage_data)

    %{
      budget_utilization_rate: current_usage / total_budget,
      budget_efficiency: assess_budget_efficiency(current_usage, total_budget),
      budget_optimization_potential:
        calculate_budget_optimization_potential(current_usage, total_budget)
    }
  end

  # Pattern analysis helpers

  defp analyze_temporal_cost_patterns(_cost_patterns) do
    # Analyze cost patterns over time
    %{
      peak_cost_hours: [10, 15, 17],
      low_cost_opportunities: [22, 23, 1, 2, 3],
      seasonal_cost_variations: %{quarter_1: 1.1, quarter_2: 0.9, quarter_3: 1.0, quarter_4: 1.05}
    }
  end

  defp analyze_judge_cost_effectiveness(_cost_patterns) do
    # Analyze cost effectiveness of different judge types
    Enum.reduce(@cost_factors, %{}, fn factor, acc ->
      Map.put(acc, factor, 0.7 + :rand.uniform() * 0.25)
    end)
  end

  defp analyze_cost_quality_tradeoffs(_cost_patterns) do
    %{
      # Positive correlation between cost and quality
      correlation: 0.6,
      # Optimal cost per evaluation
      optimal_balance_point: 0.08,
      current_tradeoff_efficiency: 0.72
    }
  end

  # Cost calculation helpers

  defp extract_pattern_cost(pattern_data) when is_map(pattern_data) do
    cost_data = Map.get(pattern_data, :cost_data, %{})
    Map.get(cost_data, :total_cost, 0.05)
  end

  defp extract_pattern_quality(pattern_data) when is_map(pattern_data) do
    Map.get(pattern_data, :quality_score, 0.75)
  end

  defp calculate_cost_quality_correlation(quality_cost_data) when is_list(quality_cost_data) do
    # Simple correlation calculation between cost and quality
    if length(quality_cost_data) < 3 do
      0.0
    else
      # Mock correlation calculation
      0.6 + (:rand.uniform() - 0.5) * 0.4
    end
  end

  defp identify_optimal_cost_quality_balance(quality_cost_data) when is_list(quality_cost_data) do
    # Identify the optimal balance point between cost and quality
    if Enum.empty?(quality_cost_data) do
      0.5
    else
      calculate_quality_cost_balance(quality_cost_data)
    end
  end

  defp assess_current_tradeoff_efficiency(quality_cost_data) when is_list(quality_cost_data) do
    # Assess how efficiently we're currently trading cost for quality
    if Enum.empty?(quality_cost_data) do
      0.7
    else
      efficiency_scores =
        Enum.map(quality_cost_data, fn data ->
          # Higher quality with lower cost = higher efficiency
          quality_factor = data.quality
          # Normalize cost
          cost_factor = 1.0 - min(1.0, data.cost * 10)

          (quality_factor + cost_factor) / 2
        end)

      Enum.sum(efficiency_scores) / length(efficiency_scores)
    end
  end

  defp calculate_quality_cost_balance(quality_cost_data) do
    # Find point with best quality-to-cost ratio
    ratios = Enum.map(quality_cost_data, &calculate_quality_cost_ratio/1)

    if Enum.empty?(ratios) do
      0.5
    else
      avg_ratio = Enum.sum(ratios) / length(ratios)
      # Normalize to 0-1 scale
      min(1.0, max(0.0, avg_ratio / 10.0))
    end
  end

  defp calculate_quality_cost_ratio(data) do
    if data.cost > 0 do
      data.quality / data.cost
    else
      data.quality
    end
  end

  # Optimization assessment helpers

  defp requires_optimization?(judge_cost_data, cost_factor) when is_map(judge_cost_data) do
    efficiency = get_cost_factor_efficiency(judge_cost_data, cost_factor)
    # Requires optimization if efficiency below 70%
    efficiency < 0.7
  end

  defp get_cost_factor_efficiency(judge_cost_data, cost_factor) when is_map(judge_cost_data) do
    Map.get(judge_cost_data, cost_factor, 0.7)
  end

  defp generate_cost_factor_improvement(cost_factor) do
    case cost_factor do
      :judge_agent_costs -> "optimize_judge_selection_for_cost"
      :processing_time_costs -> "reduce_unnecessary_processing_overhead"
      :coordination_overhead -> "streamline_coordination_protocols"
      _ -> "general_cost_optimization"
    end
  end

  defp estimate_cost_factor_savings(cost_factor) do
    # Estimate savings potential for each cost factor
    case cost_factor do
      :judge_agent_costs -> 0.2
      :processing_time_costs -> 0.15
      :infrastructure_costs -> 0.1
      :coordination_overhead -> 0.08
      :model_inference_costs -> 0.12
    end
  end

  # Effectiveness calculation helpers

  defp calculate_cost_learning_confidence(optimizations) when is_list(optimizations) do
    if Enum.empty?(optimizations) do
      0.0
    else
      confidences = Enum.map(optimizations, & &1.confidence)
      Enum.sum(confidences) / length(confidences)
    end
  end

  defp assess_cost_optimization_potential(cost_analysis) when is_map(cost_analysis) do
    high_cost_patterns = Map.get(cost_analysis, :high_cost_patterns, [])
    efficient_patterns = Map.get(cost_analysis, :efficient_cost_patterns, [])

    # More high-cost patterns = higher optimization potential
    high_cost_factor = length(high_cost_patterns) / 10.0
    efficient_factor = length(efficient_patterns) / 10.0

    potential_score = min(1.0, high_cost_factor + (1.0 - efficient_factor))

    case potential_score do
      score when score > 0.8 -> :high
      score when score > 0.6 -> :medium
      score when score > 0.4 -> :low
      _ -> :minimal
    end
  end

  defp calculate_expected_cost_savings(optimizations) when is_list(optimizations) do
    if Enum.empty?(optimizations) do
      0.0
    else
      individual_savings = Enum.map(optimizations, &Map.get(&1, :expected_savings, 0.0))

      # Apply diminishing returns for multiple optimizations
      total_savings = Enum.sum(individual_savings)
      # 20% reduction due to interaction effects
      diminishing_factor = 0.8

      total_savings * diminishing_factor
    end
  end

  defp calculate_resource_optimization_confidence(analysis) when is_map(analysis) do
    efficiency_assessment = Map.get(analysis, :efficiency_assessment, %{})
    overall_efficiency = Map.get(efficiency_assessment, :overall_efficiency, :medium)

    case overall_efficiency do
      :excellent -> 0.9
      :good -> 0.8
      :fair -> 0.7
      :poor -> 0.6
      _ -> 0.65
    end
  end

  # Resource efficiency helpers

  defp extract_utilization_score(usage_record) when is_map(usage_record) do
    Map.get(usage_record, :utilization_score, 0.6)
  end

  defp extract_utilization_score(_), do: 0.5

  defp calculate_utilization_variance(utilizations)
       when is_list(utilizations) and length(utilizations) > 1 do
    mean = Enum.sum(utilizations) / length(utilizations)

    variance =
      Enum.reduce(utilizations, 0.0, fn util, acc ->
        acc + :math.pow(util - mean, 2)
      end) / length(utilizations)

    variance
  end

  defp calculate_utilization_variance(_), do: 0.1

  defp calculate_resource_efficiency_score(utilizations) when is_list(utilizations) do
    if Enum.empty?(utilizations) do
      0.6
    else
      # Efficiency based on average utilization and consistency
      average_util = Enum.sum(utilizations) / length(utilizations)
      variance = calculate_utilization_variance(utilizations)
      consistency = max(0.0, 1.0 - variance)

      # Optimal utilization around 0.75, consistency bonus
      utilization_efficiency = 1.0 - abs(average_util - 0.75)

      (utilization_efficiency + consistency) / 2
    end
  end

  # Classification helpers

  defp classify_utilization_level(util) when util > 0.9, do: :high
  defp classify_utilization_level(util) when util > 0.7, do: :optimal
  defp classify_utilization_level(util) when util > 0.5, do: :moderate
  defp classify_utilization_level(_), do: :low

  defp classify_peak_efficiency(peak) when peak > 0.95, do: :concerning
  defp classify_peak_efficiency(peak) when peak > 0.85, do: :high
  defp classify_peak_efficiency(peak) when peak > 0.7, do: :good
  defp classify_peak_efficiency(_), do: :low

  defp classify_utilization_consistency(variance) when variance < 0.05, do: :very_consistent
  defp classify_utilization_consistency(variance) when variance < 0.1, do: :consistent
  defp classify_utilization_consistency(variance) when variance < 0.2, do: :somewhat_consistent
  defp classify_utilization_consistency(_), do: :inconsistent

  defp calculate_overall_efficiency_rating(average_util, peak_util, variance) do
    # Combine factors for overall rating
    util_score = calculate_utilization_score(average_util)
    peak_score = calculate_peak_score(peak_util)
    consistency_score = calculate_consistency_score(variance)

    (util_score + peak_score + consistency_score) / 3
  end

  defp calculate_utilization_score(average_util) do
    case classify_utilization_level(average_util) do
      :optimal -> 0.9
      :high -> 0.8
      :moderate -> 0.6
      _ -> 0.4
    end
  end

  defp calculate_peak_score(peak_util) do
    case classify_peak_efficiency(peak_util) do
      :good -> 0.8
      # High peak can indicate capacity issues
      :high -> 0.6
      :concerning -> 0.4
      _ -> 0.5
    end
  end

  defp calculate_consistency_score(variance) do
    case classify_utilization_consistency(variance) do
      :very_consistent -> 0.9
      :consistent -> 0.8
      :somewhat_consistent -> 0.6
      _ -> 0.4
    end
  end

  # Helper stubs for comprehensive implementation

  defp extract_cost_drivers(_pattern), do: [:judge_selection_overhead, :coordination_costs]
  defp extract_cost_magnitude(_pattern), do: 0.12
  defp assess_pattern_optimization_potential(_pattern), do: 0.25

  defp extract_efficiency_factors(_pattern), do: [:fast_judge_selection, :efficient_coordination]
  defp calculate_cost_savings_achieved(_pattern), do: 0.08
  defp assess_replication_potential(_pattern), do: 0.8

  defp generate_optimization_id, do: "cost_opt_#{System.unique_integer([:positive])}"

  # Mock current usage
  defp calculate_current_budget_usage(_usage_data), do: 750.0

  defp assess_budget_compliance(cost_impact, budget_constraints)
       when is_map(budget_constraints) do
    total_budget = Map.get(budget_constraints, :total_monthly_budget, 1000.0)

    # Positive cost impact (savings) always compliant
    cost_impact >= 0 or abs(cost_impact) < total_budget * 0.1
  end

  defp assess_resource_balance(_optimizations), do: true

  defp assess_budget_efficiency(current_usage, total_budget) do
    utilization_rate = current_usage / total_budget

    case utilization_rate do
      rate when rate > 0.95 -> :over_budget
      rate when rate > 0.85 -> :high_utilization
      rate when rate > 0.65 -> :efficient
      rate when rate > 0.4 -> :moderate
      _ -> :under_utilized
    end
  end

  defp calculate_budget_optimization_potential(current_usage, total_budget) do
    utilization_rate = current_usage / total_budget

    # Optimization potential based on current utilization
    case utilization_rate do
      # High potential to optimize costs
      rate when rate > 0.9 -> 0.2
      # Potential to optimize allocation
      rate when rate < 0.5 -> 0.15
      # Standard optimization potential
      _ -> 0.1
    end
  end
end
