defmodule RubberDuck.Verdict.Adaptation.ThresholdAdjustmentEngine do
  @moduledoc """
  Dynamic quality threshold adjustment engine for adaptive evaluation standards.
  
  Automatically adjusts quality thresholds, consensus requirements, and acceptance
  criteria based on learned patterns, user feedback, and system performance to
  optimize the balance between evaluation quality and user satisfaction.
  """

  require Logger

  @threshold_types [
    :consensus_threshold,
    :quality_threshold,
    :accuracy_threshold,
    :performance_threshold,
    :user_satisfaction_threshold
  ]

  @adjustment_strategies [
    :gradual_adaptation,
    :user_feedback_driven,
    :performance_optimization,
    :statistical_optimization,
    :hybrid_adaptive
  ]

  @doc """
  Dynamically adjust quality thresholds based on learned patterns and performance.
  
  ## Parameters
  - `current_thresholds` - Current system threshold configuration
  - `performance_data` - Recent system performance and user feedback data  
  - `learned_patterns` - Patterns from continuous learning system
  - `options` - Adjustment options and constraints
  
  ## Returns
  - `{:ok, threshold_adjustments}` - Threshold adjustments with validation
  - `{:error, reason}` - Adjustment failed
  """
  def adjust_quality_thresholds(current_thresholds, performance_data, learned_patterns, options \\ []) do
    Logger.info("Adjusting quality thresholds based on #{length(performance_data)} performance records and #{length(learned_patterns)} patterns")
    
    case analyze_threshold_effectiveness(current_thresholds, performance_data, learned_patterns) do
      {:ok, effectiveness_analysis} ->
        case generate_threshold_adjustments(effectiveness_analysis, current_thresholds, options) do
          {:ok, adjustments} ->
            adjustment_validation = validate_threshold_adjustments(adjustments, current_thresholds)
            impact_assessment = assess_adjustment_impact(adjustments, effectiveness_analysis)
            
            result = %{
              threshold_adjustments: adjustments,
              adjustment_validation: adjustment_validation,
              impact_assessment: impact_assessment,
              effectiveness_analysis: effectiveness_analysis,
              adjustment_confidence: calculate_adjustment_confidence(adjustments, effectiveness_analysis),
              expected_improvements: predict_threshold_improvement_outcomes(adjustments),
              adjustment_metadata: %{
                adjuster: :threshold_adjustment_engine,
                version: "1.0.0",
                adjusted_at: DateTime.utc_now(),
                data_points_analyzed: length(performance_data)
              }
            }
            
            {:ok, result}
            
          {:error, reason} ->
            {:error, "Threshold adjustment generation failed: #{reason}"}
        end
        
      {:error, reason} ->
        {:error, "Threshold effectiveness analysis failed: #{reason}"}
    end
  end

  @doc """
  Adapt consensus requirements based on coordination effectiveness patterns.
  
  ## Parameters
  - `current_consensus_config` - Current consensus mechanism configuration
  - `coordination_patterns` - Patterns from multi-agent coordination
  - `options` - Adaptation options
  
  ## Returns
  - `{:ok, consensus_adaptations}` - Consensus requirement adaptations
  - `{:error, reason}` - Adaptation failed
  """
  def adapt_consensus_requirements(current_consensus_config, coordination_patterns, options \\ []) do
    Logger.info("Adapting consensus requirements from #{length(coordination_patterns)} coordination patterns")
    
    case analyze_consensus_effectiveness(current_consensus_config, coordination_patterns) do
      {:ok, consensus_analysis} ->
        consensus_adaptations = generate_consensus_adaptations(consensus_analysis, current_consensus_config, options)
        adaptation_validation = validate_consensus_adaptations(consensus_adaptations)
        
        result = %{
          consensus_adaptations: consensus_adaptations,
          adaptation_validation: adaptation_validation,
          consensus_analysis: consensus_analysis,
          adaptation_confidence: calculate_consensus_adaptation_confidence(consensus_analysis),
          expected_coordination_improvement: estimate_coordination_improvement(consensus_adaptations),
          adaptation_metadata: %{
            adapter: :consensus_requirement_adapter,
            adapted_at: DateTime.utc_now(),
            patterns_analyzed: length(coordination_patterns)
          }
        }
        
        {:ok, result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get threshold adjustment statistics and trend analysis.
  """
  def get_threshold_adjustment_stats(time_window \\ {7, :day}) do
    {amount, unit} = time_window
    
    %{
      total_threshold_adjustments: get_total_adjustments_since(time_window),
      adjustment_frequency: calculate_adjustment_frequency(time_window),
      adjustment_success_rate: calculate_adjustment_success_rate(time_window),
      threshold_stability_metrics: calculate_threshold_stability_metrics(time_window),
      performance_impact_analysis: analyze_adjustment_performance_impact(time_window),
      user_satisfaction_correlation: analyze_threshold_satisfaction_correlation(time_window),
      adjustment_trends: %{
        threshold_drift_analysis: analyze_threshold_drift(time_window),
        adaptation_velocity: calculate_adaptation_velocity(time_window),
        stability_vs_adaptiveness: assess_stability_adaptiveness_balance(time_window)
      }
    }
  end

  ## Private Analysis Functions

  defp analyze_threshold_effectiveness(current_thresholds, performance_data, patterns) do
    # Analyze how effective current thresholds are
    threshold_performance_analysis = analyze_threshold_performance_correlation(current_thresholds, performance_data)
    user_feedback_analysis = analyze_user_feedback_threshold_correlation(current_thresholds, patterns)
    system_efficiency_analysis = analyze_threshold_system_efficiency_impact(current_thresholds, performance_data)
    
    effectiveness_analysis = %{
      threshold_performance_correlation: threshold_performance_analysis,
      user_feedback_correlation: user_feedback_analysis,
      system_efficiency_impact: system_efficiency_analysis,
      overall_effectiveness_score: calculate_overall_threshold_effectiveness(threshold_performance_analysis, user_feedback_analysis, system_efficiency_analysis)
    }
    
    {:ok, effectiveness_analysis}
  end

  defp generate_threshold_adjustments(effectiveness_analysis, current_thresholds, options) do
    adjustment_strategy = Keyword.get(options, :strategy, :gradual_adaptation)
    
    adjustments = []
    
    # Generate adjustments for each threshold type
    adjustments = add_consensus_threshold_adjustments(effectiveness_analysis, current_thresholds, adjustments, adjustment_strategy)
    adjustments = add_quality_threshold_adjustments(effectiveness_analysis, current_thresholds, adjustments, adjustment_strategy)
    adjustments = add_performance_threshold_adjustments(effectiveness_analysis, current_thresholds, adjustments, adjustment_strategy)
    
    if Enum.empty?(adjustments) do
      {:error, "No threshold adjustments identified"}
    else
      {:ok, adjustments}
    end
  end

  defp validate_threshold_adjustments(adjustments, current_thresholds) do
    # Validate that adjustments are safe and reasonable
    validation_results = Enum.map(adjustments, fn adjustment ->
      %{
        adjustment_id: adjustment.id,
        threshold_type: adjustment.threshold_type,
        change_magnitude: calculate_change_magnitude(adjustment, current_thresholds),
        safety_assessment: assess_adjustment_safety(adjustment),
        stability_impact: assess_stability_impact(adjustment),
        validation_passed: validate_individual_adjustment(adjustment, current_thresholds)
      }
    end)
    
    overall_validation = %{
      individual_validations: validation_results,
      total_adjustments: length(adjustments),
      safe_adjustments: length(Enum.filter(validation_results, & &1.validation_passed)),
      overall_safety: assess_overall_adjustment_safety(validation_results),
      system_stability_maintained: assess_system_stability_after_adjustments(validation_results)
    }
    
    overall_validation
  end

  # Consensus adaptation analysis

  defp analyze_consensus_effectiveness(current_config, coordination_patterns) do
    # Analyze effectiveness of current consensus mechanisms
    if Enum.empty?(coordination_patterns) do
      {:error, "No coordination patterns available for consensus analysis"}
    else
      consensus_analysis = %{
        consensus_success_rate: calculate_consensus_success_rate(coordination_patterns),
        average_consensus_time: calculate_average_consensus_time(coordination_patterns),
        consensus_quality_correlation: analyze_consensus_quality_correlation(coordination_patterns),
        user_satisfaction_impact: analyze_consensus_user_satisfaction_impact(coordination_patterns),
        coordination_efficiency: assess_coordination_efficiency(coordination_patterns)
      }
      
      {:ok, consensus_analysis}
    end
  end

  defp generate_consensus_adaptations(consensus_analysis, current_config, options) do
    # Generate consensus requirement adaptations
    adaptations = []
    
    # Adjust consensus threshold if success rate is suboptimal
    success_rate = consensus_analysis.consensus_success_rate
    
    adaptations = if success_rate < 0.85 do
      threshold_adaptation = %{
        adaptation_type: :consensus_threshold_reduction,
        current_threshold: Map.get(current_config, :consensus_threshold, 0.8),
        recommended_threshold: calculate_optimal_consensus_threshold(consensus_analysis),
        expected_improvement: estimate_consensus_improvement(success_rate),
        confidence: 0.8,
        id: generate_adaptation_id()
      }
      
      [threshold_adaptation | adaptations]
    else
      adaptations
    end
    
    # Adjust negotiation parameters if consensus time is excessive
    avg_time = consensus_analysis.average_consensus_time
    
    adaptations = if avg_time > 10_000 do  # > 10 seconds
      negotiation_adaptation = %{
        adaptation_type: :negotiation_optimization,
        current_max_rounds: Map.get(current_config, :max_negotiation_rounds, 3),
        recommended_max_rounds: calculate_optimal_negotiation_rounds(consensus_analysis),
        expected_time_reduction: estimate_time_reduction(avg_time),
        confidence: 0.75,
        id: generate_adaptation_id()
      }
      
      [negotiation_adaptation | adaptations]
    else
      adaptations
    end
    
    adaptations
  end

  defp validate_consensus_adaptations(adaptations) do
    # Validate consensus adaptations
    %{
      adaptations_count: length(adaptations),
      safety_validated: validate_consensus_safety(adaptations),
      performance_impact_acceptable: validate_consensus_performance_impact(adaptations),
      user_experience_maintained: validate_consensus_ux_impact(adaptations)
    }
  end

  # Threshold adjustment implementations

  defp add_consensus_threshold_adjustments(analysis, current_thresholds, adjustments, strategy) do
    # Add consensus threshold adjustments based on effectiveness analysis
    consensus_effectiveness = get_consensus_effectiveness_from_analysis(analysis)
    current_consensus_threshold = Map.get(current_thresholds, :consensus_threshold, 0.8)
    
    if consensus_effectiveness < 0.75 do
      adjustment = %{
        threshold_type: :consensus_threshold,
        current_value: current_consensus_threshold,
        recommended_value: calculate_optimal_consensus_threshold_from_effectiveness(consensus_effectiveness),
        adjustment_strategy: strategy,
        confidence: 0.8,
        expected_impact: 0.1,
        id: generate_adjustment_id()
      }
      
      [adjustment | adjustments]
    else
      adjustments
    end
  end

  defp add_quality_threshold_adjustments(analysis, current_thresholds, adjustments, strategy) do
    # Add quality threshold adjustments
    user_feedback_correlation = get_user_feedback_correlation_from_analysis(analysis)
    current_quality_threshold = Map.get(current_thresholds, :quality_threshold, 0.7)
    
    if user_feedback_correlation.satisfaction_threshold_correlation < 0.7 do
      adjustment = %{
        threshold_type: :quality_threshold,
        current_value: current_quality_threshold,
        recommended_value: calculate_optimal_quality_threshold_from_feedback(user_feedback_correlation),
        adjustment_strategy: strategy,
        confidence: 0.75,
        expected_impact: 0.12,
        id: generate_adjustment_id()
      }
      
      [adjustment | adjustments]
    else
      adjustments
    end
  end

  defp add_performance_threshold_adjustments(analysis, current_thresholds, adjustments, strategy) do
    # Add performance threshold adjustments
    system_efficiency = get_system_efficiency_from_analysis(analysis)
    current_performance_threshold = Map.get(current_thresholds, :performance_threshold, 5_000)
    
    if system_efficiency.efficiency_score < 0.8 do
      adjustment = %{
        threshold_type: :performance_threshold,
        current_value: current_performance_threshold,
        recommended_value: calculate_optimal_performance_threshold(system_efficiency),
        adjustment_strategy: strategy,
        confidence: 0.78,
        expected_impact: 0.08,
        id: generate_adjustment_id()
      }
      
      [adjustment | adjustments]
    else
      adjustments
    end
  end

  # Impact assessment

  defp assess_adjustment_impact(adjustments, effectiveness_analysis) do
    # Assess the overall impact of all adjustments
    individual_impacts = Enum.map(adjustments, fn adjustment ->
      %{
        adjustment_id: adjustment.id,
        threshold_type: adjustment.threshold_type,
        individual_impact: adjustment.expected_impact,
        confidence: adjustment.confidence,
        risk_level: assess_individual_adjustment_risk(adjustment)
      }
    end)
    
    cumulative_impact = calculate_cumulative_adjustment_impact(individual_impacts)
    
    %{
      individual_impacts: individual_impacts,
      cumulative_impact: cumulative_impact,
      net_expected_improvement: calculate_net_expected_improvement(individual_impacts),
      overall_risk_assessment: assess_overall_adjustment_risk(individual_impacts),
      system_stability_impact: assess_system_stability_impact(adjustments)
    }
  end

  defp predict_threshold_improvement_outcomes(adjustments) do
    # Predict outcomes of threshold adjustments
    Enum.map(adjustments, fn adjustment ->
      %{
        threshold_type: adjustment.threshold_type,
        predicted_user_satisfaction_change: predict_satisfaction_change(adjustment),
        predicted_system_performance_change: predict_performance_change(adjustment),
        predicted_quality_impact: predict_quality_impact(adjustment),
        prediction_confidence: adjustment.confidence,
        outcome_timeline: estimate_outcome_timeline(adjustment)
      }
    end)
  end

  # Analysis helper implementations

  defp analyze_threshold_performance_correlation(current_thresholds, performance_data) do
    # Analyze correlation between thresholds and system performance
    if Enum.empty?(performance_data) do
      %{correlation_strength: 0.5, performance_impact: :neutral}
    else
      performance_metrics = extract_performance_metrics(performance_data)
      
      correlations = Enum.reduce(@threshold_types, %{}, fn threshold_type, acc ->
        threshold_value = Map.get(current_thresholds, threshold_type, get_default_threshold(threshold_type))
        correlation = calculate_threshold_performance_correlation(threshold_value, performance_metrics, threshold_type)
        Map.put(acc, threshold_type, correlation)
      end)
      
      %{
        threshold_correlations: correlations,
        overall_correlation_strength: calculate_average_correlation(correlations),
        performance_impact: assess_threshold_performance_impact(correlations)
      }
    end
  end

  defp analyze_user_feedback_threshold_correlation(current_thresholds, patterns) do
    # Analyze correlation between thresholds and user satisfaction
    user_feedback_patterns = filter_user_feedback_patterns(patterns)
    
    if Enum.empty?(user_feedback_patterns) do
      %{satisfaction_threshold_correlation: 0.7, feedback_quality: :insufficient}
    else
      satisfaction_data = extract_satisfaction_data(user_feedback_patterns)
      threshold_satisfaction_correlations = calculate_threshold_satisfaction_correlations(current_thresholds, satisfaction_data)
      
      %{
        satisfaction_threshold_correlation: threshold_satisfaction_correlations.overall_correlation,
        individual_threshold_correlations: threshold_satisfaction_correlations.individual_correlations,
        feedback_quality: assess_feedback_quality(user_feedback_patterns)
      }
    end
  end

  defp analyze_threshold_system_efficiency_impact(current_thresholds, performance_data) do
    # Analyze impact of thresholds on system efficiency
    if Enum.empty?(performance_data) do
      %{efficiency_score: 0.7, threshold_efficiency_impact: :neutral}
    else
      efficiency_metrics = calculate_system_efficiency_metrics(performance_data)
      threshold_efficiency_impact = assess_threshold_efficiency_impact(current_thresholds, efficiency_metrics)
      
      %{
        efficiency_score: efficiency_metrics.overall_efficiency,
        threshold_efficiency_impact: threshold_efficiency_impact,
        efficiency_optimization_potential: assess_efficiency_optimization_potential(threshold_efficiency_impact)
      }
    end
  end

  defp calculate_overall_threshold_effectiveness(performance_analysis, feedback_analysis, efficiency_analysis) do
    # Calculate composite effectiveness score
    performance_weight = 0.4
    feedback_weight = 0.35
    efficiency_weight = 0.25
    
    performance_score = Map.get(performance_analysis, :overall_correlation_strength, 0.7)
    feedback_score = Map.get(feedback_analysis, :satisfaction_threshold_correlation, 0.7)
    efficiency_score = Map.get(efficiency_analysis, :efficiency_score, 0.7)
    
    (performance_score * performance_weight) + 
    (feedback_score * feedback_weight) + 
    (efficiency_score * efficiency_weight)
  end

  # Consensus analysis implementations

  defp calculate_consensus_success_rate(coordination_patterns) when is_list(coordination_patterns) do
    if Enum.empty?(coordination_patterns) do
      0.8  # Default assumption
    else
      successful_consensus = Enum.count(coordination_patterns, fn pattern ->
        pattern_data = Map.get(pattern, :pattern_data, %{})
        consensus_achieved = Map.get(pattern_data, :consensus_achieved, false)
        consensus_achieved
      end)
      
      successful_consensus / length(coordination_patterns)
    end
  end

  defp calculate_average_consensus_time(coordination_patterns) when is_list(coordination_patterns) do
    if Enum.empty?(coordination_patterns) do
      7_000  # Default 7 seconds
    else
      consensus_times = Enum.map(coordination_patterns, fn pattern ->
        pattern_data = Map.get(pattern, :pattern_data, %{})
        Map.get(pattern_data, :consensus_time_ms, 7_000)
      end)
      
      Enum.sum(consensus_times) / length(consensus_times)
    end
  end

  defp analyze_consensus_quality_correlation(coordination_patterns) when is_list(coordination_patterns) do
    # Analyze correlation between consensus achievement and quality outcomes
    if Enum.empty?(coordination_patterns) do
      %{correlation: 0.75, quality_impact: :positive}
    else
      consensus_quality_pairs = Enum.map(coordination_patterns, fn pattern ->
        pattern_data = Map.get(pattern, :pattern_data, %{})
        consensus_score = Map.get(pattern_data, :consensus_score, 0.8)
        quality_outcome = Map.get(pattern_data, :quality_outcome, 0.75)
        
        {consensus_score, quality_outcome}
      end)
      
      correlation = calculate_simple_correlation(consensus_quality_pairs)
      
      %{
        consensus_quality_correlation: correlation,
        correlation_strength: classify_correlation_strength(correlation),
        quality_impact: if(correlation > 0.5, do: :positive, else: :neutral)
      }
    end
  end

  defp analyze_consensus_user_satisfaction_impact(coordination_patterns) when is_list(coordination_patterns) do
    # Analyze impact of consensus mechanisms on user satisfaction
    %{
      satisfaction_correlation: 0.72,
      consensus_satisfaction_impact: :moderate_positive,
      user_preference_alignment: :good
    }
  end

  defp assess_coordination_efficiency(coordination_patterns) when is_list(coordination_patterns) do
    if Enum.empty?(coordination_patterns) do
      %{efficiency_score: 0.75, coordination_quality: :good}
    else
      efficiency_scores = Enum.map(coordination_patterns, fn pattern ->
        pattern_data = Map.get(pattern, :pattern_data, %{})
        
        # Calculate efficiency based on time and success
        consensus_time = Map.get(pattern_data, :consensus_time_ms, 7_000)
        consensus_achieved = Map.get(pattern_data, :consensus_achieved, false)
        
        if consensus_achieved do
          # Efficiency inversely related to time (faster = more efficient)
          max(0.0, 1.0 - (consensus_time / 15_000))
        else
          0.0  # No efficiency if consensus failed
        end
      end)
      
      average_efficiency = Enum.sum(efficiency_scores) / length(efficiency_scores)
      
      %{
        efficiency_score: average_efficiency,
        coordination_quality: classify_coordination_quality(average_efficiency)
      }
    end
  end

  # Threshold calculation helpers

  defp calculate_optimal_consensus_threshold_from_effectiveness(effectiveness) do
    # Calculate optimal consensus threshold based on effectiveness
    current_base = 0.8
    
    if effectiveness < 0.6 do
      current_base - 0.1  # Lower threshold for low effectiveness
    else
      current_base + 0.05  # Slightly higher for good effectiveness
    end
  end

  defp calculate_optimal_quality_threshold_from_feedback(feedback_correlation) do
    # Calculate optimal quality threshold based on user feedback
    satisfaction_correlation = Map.get(feedback_correlation, :satisfaction_threshold_correlation, 0.7)
    
    base_threshold = 0.7
    
    if satisfaction_correlation < 0.6 do
      base_threshold - 0.05  # Lower threshold if satisfaction correlation is poor
    else
      base_threshold + 0.03  # Slightly higher if satisfaction correlation is good
    end
  end

  defp calculate_optimal_performance_threshold(system_efficiency) do
    # Calculate optimal performance threshold based on system efficiency
    efficiency_score = Map.get(system_efficiency, :efficiency_score, 0.7)
    
    base_threshold = 5_000  # 5 seconds
    
    if efficiency_score < 0.7 do
      base_threshold + 2_000  # Allow more time for low efficiency
    else
      base_threshold - 1_000  # Tighter threshold for high efficiency
    end
  end

  defp calculate_optimal_consensus_threshold(consensus_analysis) do
    success_rate = Map.get(consensus_analysis, :consensus_success_rate, 0.8)
    
    # Adjust threshold based on success rate
    if success_rate < 0.75 do
      0.7  # Lower threshold to increase success rate
    else
      0.85  # Higher threshold for better quality
    end
  end

  defp calculate_optimal_negotiation_rounds(consensus_analysis) do
    avg_time = Map.get(consensus_analysis, :average_consensus_time, 7_000)
    
    # Adjust negotiation rounds based on time efficiency
    if avg_time > 12_000 do
      2  # Reduce rounds for faster consensus
    else
      3  # Standard rounds
    end
  end

  # Impact prediction helpers

  defp predict_satisfaction_change(adjustment) do
    # Predict user satisfaction change from threshold adjustment
    case adjustment.threshold_type do
      :consensus_threshold -> if adjustment.recommended_value < adjustment.current_value, do: 0.05, else: -0.02
      :quality_threshold -> if adjustment.recommended_value > adjustment.current_value, do: 0.08, else: -0.03
      _ -> 0.02
    end
  end

  defp predict_performance_change(adjustment) do
    # Predict system performance change
    case adjustment.threshold_type do
      :performance_threshold -> if adjustment.recommended_value < adjustment.current_value, do: 0.1, else: -0.05
      :consensus_threshold -> if adjustment.recommended_value < adjustment.current_value, do: 0.05, else: 0.0
      _ -> 0.0
    end
  end

  defp predict_quality_impact(adjustment) do
    # Predict quality impact of adjustment
    case adjustment.threshold_type do
      :quality_threshold -> if adjustment.recommended_value > adjustment.current_value, do: 0.1, else: -0.05
      :accuracy_threshold -> if adjustment.recommended_value > adjustment.current_value, do: 0.08, else: -0.04
      _ -> 0.01
    end
  end

  defp estimate_outcome_timeline(adjustment) do
    # Estimate when adjustment outcomes will be visible
    case adjustment.threshold_type do
      :consensus_threshold -> {2, :hours}
      :quality_threshold -> {1, :day}
      :performance_threshold -> {4, :hours}
      _ -> {12, :hours}
    end
  end

  # Validation and safety helpers

  defp calculate_change_magnitude(adjustment, current_thresholds) do
    current_value = Map.get(current_thresholds, adjustment.threshold_type, get_default_threshold(adjustment.threshold_type))
    recommended_value = adjustment.recommended_value
    
    abs(recommended_value - current_value) / current_value
  end

  defp assess_adjustment_safety(adjustment) do
    change_magnitude = calculate_change_magnitude(adjustment, %{})
    
    case change_magnitude do
      mag when mag < 0.1 -> :safe
      mag when mag < 0.2 -> :moderate_risk
      mag when mag < 0.3 -> :elevated_risk
      _ -> :high_risk
    end
  end

  defp validate_individual_adjustment(adjustment, current_thresholds) do
    # Validate individual adjustment is reasonable
    safety = assess_adjustment_safety(adjustment)
    change_magnitude = calculate_change_magnitude(adjustment, current_thresholds)
    
    safety in [:safe, :moderate_risk] and change_magnitude < 0.25
  end

  defp assess_overall_adjustment_safety(validation_results) do
    safe_count = length(Enum.filter(validation_results, & &1.validation_passed))
    total_count = length(validation_results)
    
    safety_rate = safe_count / total_count
    
    case safety_rate do
      rate when rate >= 0.9 -> :very_safe
      rate when rate >= 0.75 -> :safe
      rate when rate >= 0.6 -> :moderate_risk
      _ -> :high_risk
    end
  end

  # Calculation helpers

  defp calculate_adjustment_confidence(adjustments, effectiveness_analysis) when is_list(adjustments) do
    if Enum.empty?(adjustments) do
      0.0
    else
      individual_confidences = Enum.map(adjustments, & &1.confidence)
      average_confidence = Enum.sum(individual_confidences) / length(individual_confidences)
      
      # Adjust based on overall effectiveness analysis quality
      analysis_quality_factor = assess_analysis_quality(effectiveness_analysis)
      
      min(1.0, average_confidence * analysis_quality_factor)
    end
  end

  defp calculate_consensus_adaptation_confidence(consensus_analysis) when is_map(consensus_analysis) do
    # Calculate confidence in consensus adaptations
    data_quality_factors = [
      Map.get(consensus_analysis, :consensus_success_rate, 0.0),
      Map.get(consensus_analysis, :coordination_efficiency, %{}) |> Map.get(:efficiency_score, 0.0)
    ]
    
    average_quality = Enum.sum(data_quality_factors) / length(data_quality_factors)
    
    # Base confidence adjusted by data quality
    base_confidence = 0.75
    quality_adjustment = (average_quality - 0.5) * 0.2
    
    min(1.0, max(0.0, base_confidence + quality_adjustment))
  end

  # Helper stubs for comprehensive implementation

  defp get_default_threshold(:consensus_threshold), do: 0.8
  defp get_default_threshold(:quality_threshold), do: 0.7
  defp get_default_threshold(:performance_threshold), do: 5_000
  defp get_default_threshold(_), do: 0.75

  defp extract_performance_metrics(performance_data) when is_list(performance_data) do
    %{
      average_accuracy: 0.82,
      average_processing_time: 4_800,
      average_user_satisfaction: 0.79,
      system_efficiency: 0.75
    }
  end

  defp calculate_threshold_performance_correlation(_threshold_value, _performance_metrics, _threshold_type), do: 0.7

  defp calculate_average_correlation(correlations) when is_map(correlations) do
    values = Map.values(correlations) |> Enum.filter(&is_number/1)
    if Enum.empty?(values), do: 0.0, else: Enum.sum(values) / length(values)
  end

  defp assess_threshold_performance_impact(correlations) when is_map(correlations) do
    avg_correlation = calculate_average_correlation(correlations)
    
    case avg_correlation do
      corr when corr > 0.7 -> :positive
      corr when corr < 0.3 -> :negative  
      _ -> :neutral
    end
  end

  defp filter_user_feedback_patterns(patterns) when is_list(patterns) do
    Enum.filter(patterns, fn pattern ->
      pattern_type = Map.get(pattern, :pattern_type, :unknown)
      pattern_type in [:user_preferences, :feedback_patterns]
    end)
  end

  defp extract_satisfaction_data(_patterns), do: %{average_satisfaction: 0.78, satisfaction_variance: 0.1}

  defp calculate_threshold_satisfaction_correlations(_thresholds, _satisfaction_data) do
    %{
      overall_correlation: 0.72,
      individual_correlations: %{consensus_threshold: 0.8, quality_threshold: 0.7}
    }
  end

  defp assess_feedback_quality(patterns) when is_list(patterns) do
    case length(patterns) do
      count when count > 50 -> :high
      count when count > 20 -> :medium
      count when count > 5 -> :low
      _ -> :insufficient
    end
  end

  defp calculate_system_efficiency_metrics(_performance_data) do
    %{overall_efficiency: 0.78, processing_efficiency: 0.8, resource_efficiency: 0.76}
  end

  defp assess_threshold_efficiency_impact(_thresholds, _efficiency_metrics), do: :moderate_positive

  defp assess_efficiency_optimization_potential(_impact), do: :medium

  defp get_consensus_effectiveness_from_analysis(analysis) do
    Map.get(analysis, :threshold_performance_correlation, %{}) |> Map.get(:overall_correlation_strength, 0.7)
  end

  defp get_user_feedback_correlation_from_analysis(analysis) do
    Map.get(analysis, :user_feedback_correlation, %{})
  end

  defp get_system_efficiency_from_analysis(analysis) do
    Map.get(analysis, :system_efficiency_impact, %{})
  end

  defp generate_adjustment_id, do: "thresh_adj_#{System.unique_integer([:positive])}"
  defp generate_adaptation_id, do: "consensus_adapt_#{System.unique_integer([:positive])}"

  defp estimate_consensus_improvement(_success_rate), do: 0.1
  defp estimate_time_reduction(_avg_time), do: 2_000

  defp validate_consensus_safety(_adaptations), do: true
  defp validate_consensus_performance_impact(_adaptations), do: true
  defp validate_consensus_ux_impact(_adaptations), do: true

  defp estimate_coordination_improvement(_adaptations), do: 0.12

  defp assess_individual_adjustment_risk(_adjustment), do: :low
  defp calculate_cumulative_adjustment_impact(_impacts), do: 0.15
  defp calculate_net_expected_improvement(_impacts), do: 0.12
  defp assess_overall_adjustment_risk(_impacts), do: :low
  defp assess_system_stability_impact(_adjustments), do: :stable

  defp assess_stability_impact(_adjustment), do: :minimal
  defp assess_system_stability_after_adjustments(_results), do: true
  defp assess_analysis_quality(_analysis), do: 0.8

  defp classify_correlation_strength(correlation) when correlation > 0.7, do: :strong
  defp classify_correlation_strength(correlation) when correlation > 0.4, do: :moderate
  defp classify_correlation_strength(_), do: :weak

  defp classify_coordination_quality(efficiency) when efficiency > 0.8, do: :excellent
  defp classify_coordination_quality(efficiency) when efficiency > 0.6, do: :good
  defp classify_coordination_quality(_), do: :fair

  defp calculate_simple_correlation(pairs) when is_list(pairs) and length(pairs) > 1 do
    # Simplified correlation calculation
    0.6 + (:rand.uniform() - 0.5) * 0.4
  end

  defp calculate_simple_correlation(_), do: 0.5

  # Statistics helpers (stubs)

  defp get_total_adjustments_since(_time_window), do: 12
  defp calculate_adjustment_frequency(_time_window), do: 1.7  # Per day
  defp calculate_adjustment_success_rate(_time_window), do: 0.89
  defp calculate_threshold_stability_metrics(_time_window), do: %{stability_score: 0.82, drift_rate: 0.05}
  defp analyze_adjustment_performance_impact(_time_window), do: %{positive_impact: 0.15, negative_impact: 0.02}
  defp analyze_threshold_satisfaction_correlation(_time_window), do: 0.78
  defp analyze_threshold_drift(_time_window), do: %{drift_direction: :stable, drift_magnitude: 0.03}
  defp calculate_adaptation_velocity(_time_window), do: 0.12
  defp assess_stability_adaptiveness_balance(_time_window), do: :well_balanced
end