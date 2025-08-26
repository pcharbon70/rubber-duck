defmodule RubberDuck.Verdict.Feedback.ImplicitFeedbackAnalyzer do
  @moduledoc """
  Analyzer for implicit user feedback through behavioral patterns and system usage.

  Extracts learning insights from user behaviors such as acceptance patterns,
  retry frequency, edit behaviors, and usage flows to understand user satisfaction
  and system effectiveness without requiring explicit feedback.
  """

  require Logger

  @behavior_confidence_weights %{
    acceptance: 0.8,
    rejection: 0.85,
    retry: 0.7,
    edit: 0.75,
    abandonment: 0.6,
    quick_accept: 0.9
  }

  @doc """
  Analyze user behavior patterns for learning insights.

  ## Parameters
  - `evaluation_id` - The evaluation this behavior relates to
  - `behavior_type` - Type of implicit behavior observed
  - `behavior_data` - The behavioral data and context
  - `options` - Analysis options

  ## Returns
  - `{:ok, analyzed_behavior}` - Analysis successful
  - `{:error, reason}` - Analysis failed
  """
  def analyze_behavior(evaluation_id, behavior_type, behavior_data, options \\ []) do
    Logger.debug("Analyzing #{behavior_type} behavior for evaluation #{evaluation_id}")

    case behavior_type do
      :implicit_acceptance ->
        analyze_acceptance_behavior(evaluation_id, behavior_data, options)

      :implicit_rejection ->
        analyze_rejection_behavior(evaluation_id, behavior_data, options)

      :implicit_retry ->
        analyze_retry_behavior(evaluation_id, behavior_data, options)

      :implicit_edit ->
        analyze_edit_behavior(evaluation_id, behavior_data, options)

      _ ->
        {:error, "Unsupported behavior type: #{behavior_type}"}
    end
  end

  @doc """
  Analyze user session patterns for behavioral insights.

  ## Parameters
  - `user_id` - User to analyze
  - `session_data` - Session behavioral data
  - `time_window` - Analysis time window

  ## Returns
  - `{:ok, session_insights}` - Analysis successful
  - `{:error, reason}` - Analysis failed
  """
  def analyze_session_patterns(user_id, session_data, time_window \\ {7, :day}) do
    Logger.info("Analyzing session patterns for user #{user_id}")

    case validate_session_data(session_data) do
      {:ok, validated_data} ->
        patterns = extract_session_patterns(validated_data, time_window)
        behavioral_profile = build_behavioral_profile(patterns, user_id)
        learning_insights = derive_learning_insights_from_patterns(patterns, behavioral_profile)

        session_insights = %{
          user_id: user_id,
          analysis_window: time_window,
          behavioral_patterns: patterns,
          user_profile: behavioral_profile,
          learning_insights: learning_insights,
          confidence: calculate_session_analysis_confidence(patterns),
          analyzed_at: DateTime.utc_now()
        }

        {:ok, session_insights}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Private Analysis Functions

  defp analyze_acceptance_behavior(evaluation_id, behavior_data, options) do
    acceptance_speed = Map.get(behavior_data, :acceptance_time_ms)
    interaction_count = Map.get(behavior_data, :interaction_count, 1)
    context = Map.get(behavior_data, :context, %{})

    confidence = calculate_acceptance_confidence(acceptance_speed, interaction_count)

    learning_value =
      calculate_acceptance_learning_value(acceptance_speed, interaction_count, context)

    analyzed_behavior = %{
      evaluation_id: evaluation_id,
      behavior_type: :implicit_acceptance,
      confidence: confidence,
      learning_value: learning_value,
      behavioral_indicators: %{
        acceptance_speed: classify_acceptance_speed(acceptance_speed),
        interaction_pattern: classify_interaction_pattern(interaction_count),
        user_confidence_level: infer_user_confidence(acceptance_speed, interaction_count)
      },
      insights: %{
        system_effectiveness: assess_system_effectiveness_from_acceptance(acceptance_speed),
        user_satisfaction_indicator:
          assess_satisfaction_from_acceptance(acceptance_speed, interaction_count),
        judge_quality_indicator: infer_judge_quality_from_acceptance(context)
      },
      learning_actions: generate_acceptance_learning_actions(acceptance_speed, interaction_count),
      analyzed_at: DateTime.utc_now(),
      analysis_metadata: %{
        analyzer: :acceptance_behavior_analyzer,
        version: "1.0.0",
        options: options
      }
    }

    {:ok, analyzed_behavior}
  end

  defp analyze_rejection_behavior(evaluation_id, behavior_data, options) do
    rejection_reason = Map.get(behavior_data, :rejection_reason)
    alternative_action = Map.get(behavior_data, :alternative_action)
    rejection_speed = Map.get(behavior_data, :rejection_time_ms)

    confidence = Map.get(@behavior_confidence_weights, :rejection)

    learning_value =
      calculate_rejection_learning_value(rejection_reason, alternative_action, rejection_speed)

    analyzed_behavior = %{
      evaluation_id: evaluation_id,
      behavior_type: :implicit_rejection,
      confidence: confidence,
      learning_value: learning_value,
      behavioral_indicators: %{
        rejection_speed: classify_rejection_speed(rejection_speed),
        rejection_reason: rejection_reason,
        alternative_sought: not is_nil(alternative_action)
      },
      insights: %{
        dissatisfaction_level: assess_dissatisfaction_level(rejection_reason, rejection_speed),
        improvement_areas: identify_improvement_areas_from_rejection(rejection_reason),
        judge_effectiveness_issue:
          assess_judge_effectiveness_issue(rejection_reason, alternative_action)
      },
      learning_actions: generate_rejection_learning_actions(rejection_reason, alternative_action),
      analyzed_at: DateTime.utc_now(),
      analysis_metadata: %{
        analyzer: :rejection_behavior_analyzer,
        version: "1.0.0",
        options: options
      }
    }

    {:ok, analyzed_behavior}
  end

  defp analyze_retry_behavior(evaluation_id, behavior_data, options) do
    retry_count = Map.get(behavior_data, :retry_count)
    retry_interval = Map.get(behavior_data, :retry_interval_ms)
    modifications = Map.get(behavior_data, :modifications_made, [])

    confidence = calculate_retry_confidence(retry_count, modifications)
    learning_value = calculate_retry_learning_value(retry_count, modifications, retry_interval)

    analyzed_behavior = %{
      evaluation_id: evaluation_id,
      behavior_type: :implicit_retry,
      confidence: confidence,
      learning_value: learning_value,
      behavioral_indicators: %{
        retry_frequency: classify_retry_frequency(retry_count),
        retry_pattern: classify_retry_pattern(retry_interval),
        modification_intensity: assess_modification_intensity(modifications)
      },
      insights: %{
        system_reliability_indicator: assess_system_reliability_from_retries(retry_count),
        user_persistence_level: assess_user_persistence(retry_count, retry_interval),
        evaluation_difficulty: infer_evaluation_difficulty(retry_count, modifications)
      },
      learning_actions: generate_retry_learning_actions(retry_count, modifications),
      analyzed_at: DateTime.utc_now(),
      analysis_metadata: %{
        analyzer: :retry_behavior_analyzer,
        version: "1.0.0",
        options: options
      }
    }

    {:ok, analyzed_behavior}
  end

  defp analyze_edit_behavior(evaluation_id, behavior_data, options) do
    edit_count = Map.get(behavior_data, :edit_count)
    edit_types = Map.get(behavior_data, :edit_types, [])
    time_to_first_edit = Map.get(behavior_data, :time_to_first_edit_ms)

    confidence = calculate_edit_confidence(edit_count, edit_types)
    learning_value = calculate_edit_learning_value(edit_count, edit_types, time_to_first_edit)

    analyzed_behavior = %{
      evaluation_id: evaluation_id,
      behavior_type: :implicit_edit,
      confidence: confidence,
      learning_value: learning_value,
      behavioral_indicators: %{
        edit_frequency: classify_edit_frequency(edit_count),
        edit_complexity: classify_edit_complexity(edit_types),
        initial_satisfaction: infer_initial_satisfaction(time_to_first_edit)
      },
      insights: %{
        evaluation_completeness:
          assess_evaluation_completeness_from_edits(edit_count, edit_types),
        user_expertise_level: infer_user_expertise_from_edits(edit_types),
        system_guidance_effectiveness:
          assess_guidance_effectiveness(time_to_first_edit, edit_count)
      },
      learning_actions: generate_edit_learning_actions(edit_count, edit_types),
      analyzed_at: DateTime.utc_now(),
      analysis_metadata: %{
        analyzer: :edit_behavior_analyzer,
        version: "1.0.0",
        options: options
      }
    }

    {:ok, analyzed_behavior}
  end

  # Behavioral pattern analysis helpers

  defp validate_session_data(session_data) when is_map(session_data), do: {:ok, session_data}
  defp validate_session_data(_), do: {:error, "Invalid session data format"}

  defp extract_session_patterns(session_data, time_window) do
    {amount, unit} = time_window

    %{
      usage_frequency: calculate_usage_frequency(session_data, time_window),
      average_session_duration: calculate_average_session_duration(session_data),
      common_workflows: identify_common_workflows(session_data),
      peak_usage_times: identify_peak_usage_times(session_data),
      feature_usage_patterns: analyze_feature_usage_patterns(session_data)
    }
  end

  defp build_behavioral_profile(patterns, user_id) do
    %{
      user_id: user_id,
      engagement_level: classify_engagement_level(patterns),
      expertise_level: infer_expertise_level(patterns),
      usage_style: classify_usage_style(patterns),
      satisfaction_indicators: extract_satisfaction_indicators(patterns),
      learning_potential: assess_learning_potential(patterns)
    }
  end

  defp derive_learning_insights_from_patterns(patterns, profile) do
    %{
      optimization_opportunities: identify_optimization_opportunities(patterns),
      personalization_potential: assess_personalization_potential(profile),
      system_adaptation_recommendations: generate_adaptation_recommendations(patterns, profile)
    }
  end

  # Classification and calculation helpers (stubs for comprehensive implementation)

  defp calculate_acceptance_confidence(acceptance_time, interaction_count) do
    base_confidence = Map.get(@behavior_confidence_weights, :acceptance)

    # Quick acceptance with minimal interaction suggests high confidence
    speed_bonus = if acceptance_time && acceptance_time < 5_000, do: 0.1, else: 0.0
    interaction_bonus = if interaction_count == 1, do: 0.05, else: 0.0

    min(1.0, base_confidence + speed_bonus + interaction_bonus)
  end

  defp calculate_acceptance_learning_value(acceptance_time, interaction_count, context) do
    base_value = 0.7

    # Quick acceptance indicates system effectiveness
    speed_value = if acceptance_time && acceptance_time < 3_000, do: 0.15, else: 0.0
    context_value = if map_size(context) > 0, do: 0.1, else: 0.0

    min(1.0, base_value + speed_value + context_value)
  end

  defp calculate_rejection_learning_value(rejection_reason, alternative_action, rejection_speed) do
    # Rejections are high learning value
    base_value = 0.8

    # Specific rejection reasons are more valuable
    reason_value =
      if is_atom(rejection_reason) and rejection_reason != :unknown, do: 0.1, else: 0.0

    # Alternative actions show user intent
    alternative_value = if is_nil(alternative_action), do: 0.0, else: 0.1

    min(1.0, base_value + reason_value + alternative_value)
  end

  defp calculate_retry_confidence(retry_count, modifications) do
    base_confidence = Map.get(@behavior_confidence_weights, :retry)

    # Multiple retries with modifications show deliberate user action
    retry_bonus = min(0.1, retry_count * 0.03)
    modification_bonus = min(0.1, length(modifications) * 0.05)

    min(1.0, base_confidence + retry_bonus + modification_bonus)
  end

  defp calculate_retry_learning_value(retry_count, modifications, retry_interval) do
    base_value = 0.65

    # More retries indicate system issues (higher learning value)
    retry_value = min(0.2, retry_count * 0.05)

    # Modifications show user engagement
    modification_value = min(0.15, length(modifications) * 0.03)

    min(1.0, base_value + retry_value + modification_value)
  end

  defp calculate_edit_confidence(edit_count, edit_types) do
    base_confidence = Map.get(@behavior_confidence_weights, :edit)

    # More edits and varied edit types increase confidence
    edit_bonus = min(0.1, edit_count * 0.02)
    type_bonus = min(0.1, length(edit_types) * 0.03)

    min(1.0, base_confidence + edit_bonus + type_bonus)
  end

  defp calculate_edit_learning_value(edit_count, edit_types, time_to_first_edit) do
    base_value = 0.7

    # Immediate edits suggest evaluation quality issues
    speed_value = if time_to_first_edit && time_to_first_edit < 1_000, do: 0.15, else: 0.0

    # Complex edits provide more learning value
    complexity_value = assess_edit_complexity_value(edit_types)

    min(1.0, base_value + speed_value + complexity_value)
  end

  # Behavioral classification helpers (stubs for full implementation)

  defp classify_acceptance_speed(time_ms) when is_number(time_ms) do
    cond do
      time_ms < 2_000 -> :instant
      time_ms < 5_000 -> :quick
      time_ms < 10_000 -> :normal
      true -> :slow
    end
  end

  defp classify_acceptance_speed(_), do: :unknown

  defp classify_interaction_pattern(count) when count == 1, do: :direct
  defp classify_interaction_pattern(count) when count <= 3, do: :minimal
  defp classify_interaction_pattern(count) when count <= 7, do: :moderate
  defp classify_interaction_pattern(_), do: :extensive

  defp infer_user_confidence(acceptance_time, interaction_count) do
    case {classify_acceptance_speed(acceptance_time),
          classify_interaction_pattern(interaction_count)} do
      {:instant, :direct} -> :very_high
      {:quick, :minimal} -> :high
      {:normal, :moderate} -> :medium
      _ -> :low
    end
  end

  defp assess_system_effectiveness_from_acceptance(acceptance_time) do
    case classify_acceptance_speed(acceptance_time) do
      speed when speed in [:instant, :quick] -> :high
      :normal -> :good
      _ -> :needs_improvement
    end
  end

  defp assess_satisfaction_from_acceptance(acceptance_time, interaction_count) do
    user_confidence = infer_user_confidence(acceptance_time, interaction_count)

    case user_confidence do
      level when level in [:very_high, :high] -> :satisfied
      :medium -> :neutral
      _ -> :potentially_unsatisfied
    end
  end

  defp infer_judge_quality_from_acceptance(context) do
    # Would analyze context to infer judge effectiveness
    if map_size(context) > 3, do: :good, else: :unknown
  end

  defp classify_rejection_speed(time_ms) when is_number(time_ms) do
    cond do
      time_ms < 1_000 -> :immediate
      time_ms < 3_000 -> :quick
      time_ms < 8_000 -> :considered
      true -> :delayed
    end
  end

  defp classify_rejection_speed(_), do: :unknown

  defp assess_dissatisfaction_level(rejection_reason, rejection_speed) do
    reason_severity = calculate_reason_severity(rejection_reason)
    speed_factor = calculate_speed_factor(rejection_speed)
    combine_severity_factors(reason_severity, speed_factor)
  end

  defp calculate_reason_severity(rejection_reason) do
    case rejection_reason do
      :quality_issues -> :high
      :accuracy_concerns -> :high
      :speed_issues -> :medium
      :usability_problems -> :medium
      _ -> :low
    end
  end

  defp calculate_speed_factor(rejection_speed) do
    case classify_rejection_speed(rejection_speed) do
      :immediate -> :high
      :quick -> :medium
      _ -> :low
    end
  end

  defp combine_severity_factors(reason_severity, speed_factor) do
    case {reason_severity, speed_factor} do
      {:high, :high} -> :severe
      {:high, _} -> :high
      {:medium, :high} -> :high
      {:medium, _} -> :medium
      _ -> :low
    end
  end

  defp identify_improvement_areas_from_rejection(:quality_issues),
    do: [:evaluation_accuracy, :judge_selection]

  defp identify_improvement_areas_from_rejection(:speed_issues),
    do: [:performance_optimization, :caching]

  defp identify_improvement_areas_from_rejection(_), do: [:general_improvement]

  defp assess_judge_effectiveness_issue(rejection_reason, alternative_action) do
    if rejection_reason in [:quality_issues, :accuracy_concerns] and
         not is_nil(alternative_action) do
      :significant
    else
      :minor
    end
  end

  defp generate_acceptance_learning_actions(acceptance_time, interaction_count) do
    case {classify_acceptance_speed(acceptance_time),
          classify_interaction_pattern(interaction_count)} do
      {:instant, :direct} -> ["reinforce_judge_selection", "maintain_current_quality"]
      {:slow, :extensive} -> ["investigate_usability", "optimize_evaluation_speed"]
      _ -> ["monitor_acceptance_patterns"]
    end
  end

  defp generate_rejection_learning_actions(rejection_reason, alternative_action) do
    base_actions = ["investigate_rejection_cause", "improve_evaluation_quality"]

    reason_actions =
      case rejection_reason do
        :quality_issues -> ["enhance_judge_accuracy", "review_scoring_criteria"]
        :speed_issues -> ["optimize_performance", "implement_faster_routing"]
        _ -> []
      end

    base_actions ++ reason_actions
  end

  defp classify_retry_frequency(count) when count == 1, do: :single
  defp classify_retry_frequency(count) when count <= 3, do: :occasional
  defp classify_retry_frequency(count) when count <= 6, do: :frequent
  defp classify_retry_frequency(_), do: :excessive

  defp classify_retry_pattern(interval_ms) when is_number(interval_ms) do
    cond do
      interval_ms < 5_000 -> :impatient
      interval_ms < 30_000 -> :normal
      true -> :patient
    end
  end

  defp classify_retry_pattern(_), do: :unknown

  defp assess_modification_intensity(modifications) do
    case length(modifications) do
      0 -> :none
      count when count <= 2 -> :minimal
      count when count <= 5 -> :moderate
      _ -> :extensive
    end
  end

  defp generate_retry_learning_actions(retry_count, modifications) do
    base_actions =
      case classify_retry_frequency(retry_count) do
        freq when freq in [:frequent, :excessive] ->
          ["investigate_system_reliability", "improve_first_time_success"]

        _ ->
          ["monitor_retry_patterns"]
      end

    modification_actions =
      case assess_modification_intensity(modifications) do
        intensity when intensity in [:moderate, :extensive] ->
          ["analyze_modification_patterns", "improve_initial_evaluation"]

        _ ->
          []
      end

    base_actions ++ modification_actions
  end

  defp classify_edit_frequency(count) when count <= 1, do: :minimal
  defp classify_edit_frequency(count) when count <= 3, do: :normal
  defp classify_edit_frequency(count) when count <= 6, do: :frequent
  defp classify_edit_frequency(_), do: :extensive

  defp classify_edit_complexity(edit_types) do
    complexity_score = calculate_complexity_score(edit_types)
    score_to_complexity_level(complexity_score)
  end

  defp calculate_complexity_score(edit_types) do
    Enum.reduce(edit_types, 0, fn edit_type, acc ->
      acc + edit_type_score(edit_type)
    end)
  end

  defp edit_type_score(edit_type) do
    case edit_type do
      :minor_text_edit -> 1
      :criteria_adjustment -> 3
      :score_modification -> 2
      :complete_rewrite -> 5
      _ -> 1
    end
  end

  defp score_to_complexity_level(complexity_score) do
    cond do
      complexity_score <= 2 -> :simple
      complexity_score <= 6 -> :moderate
      complexity_score <= 12 -> :complex
      true -> :very_complex
    end
  end

  defp infer_initial_satisfaction(time_to_first_edit) when is_number(time_to_first_edit) do
    case time_to_first_edit do
      t when t < 2_000 -> :unsatisfied
      t when t < 10_000 -> :somewhat_satisfied
      _ -> :satisfied
    end
  end

  defp infer_initial_satisfaction(_), do: :unknown

  defp assess_edit_complexity_value(edit_types) do
    complexity = classify_edit_complexity(edit_types)

    case complexity do
      :very_complex -> 0.15
      :complex -> 0.1
      :moderate -> 0.05
      _ -> 0.0
    end
  end

  defp generate_edit_learning_actions(edit_count, edit_types) do
    frequency_actions =
      case classify_edit_frequency(edit_count) do
        freq when freq in [:frequent, :extensive] ->
          ["improve_initial_evaluation", "enhance_guidance"]

        _ ->
          []
      end

    complexity_actions =
      case classify_edit_complexity(edit_types) do
        complexity when complexity in [:complex, :very_complex] ->
          ["analyze_edit_patterns", "improve_evaluation_completeness"]

        _ ->
          []
      end

    frequency_actions ++ complexity_actions
  end

  # Session pattern analysis helpers (stubs)

  defp calculate_usage_frequency(_session_data, _time_window), do: :regular
  defp calculate_average_session_duration(_session_data), do: 15.5
  defp identify_common_workflows(_session_data), do: ["standard_evaluation", "detailed_review"]
  # Hours
  defp identify_peak_usage_times(_session_data), do: [9, 14, 16]

  defp analyze_feature_usage_patterns(_session_data),
    do: %{most_used: :evaluation, least_used: :advanced_settings}

  defp classify_engagement_level(_patterns), do: :high
  defp infer_expertise_level(_patterns), do: :intermediate
  defp classify_usage_style(_patterns), do: :methodical
  defp extract_satisfaction_indicators(_patterns), do: %{overall: :positive}
  defp assess_learning_potential(_patterns), do: :high

  defp calculate_session_analysis_confidence(_patterns), do: 0.75

  defp identify_optimization_opportunities(_patterns),
    do: ["workflow_streamlining", "feature_enhancement"]

  defp assess_personalization_potential(_profile), do: :high

  defp generate_adaptation_recommendations(_patterns, _profile),
    do: ["personalize_evaluation_flow", "optimize_common_workflows"]

  # Additional behavioral assessment helpers

  defp assess_system_reliability_from_retries(retry_count) do
    case retry_count do
      count when count <= 1 -> :excellent
      count when count <= 3 -> :good
      count when count <= 6 -> :concerning
      _ -> :poor
    end
  end

  defp assess_user_persistence(retry_count, retry_interval) do
    frequency = classify_retry_frequency(retry_count)
    pattern = classify_retry_pattern(retry_interval)

    case {frequency, pattern} do
      {:excessive, :impatient} -> :very_high
      {:frequent, _} -> :high
      {:occasional, :patient} -> :moderate
      _ -> :low
    end
  end

  defp infer_evaluation_difficulty(retry_count, modifications) do
    retry_factor = classify_retry_frequency(retry_count)
    modification_factor = assess_modification_intensity(modifications)

    case {retry_factor, modification_factor} do
      {freq, intensity}
      when freq in [:frequent, :excessive] and intensity in [:moderate, :extensive] ->
        :very_high

      {freq, _} when freq in [:frequent, :excessive] ->
        :high

      {_, intensity} when intensity in [:moderate, :extensive] ->
        :moderate

      _ ->
        :low
    end
  end

  defp assess_evaluation_completeness_from_edits(edit_count, edit_types) do
    if edit_count > 3 or :complete_rewrite in edit_types do
      :incomplete
    else
      :adequate
    end
  end

  defp infer_user_expertise_from_edits(edit_types) do
    complex_edits =
      Enum.count(edit_types, fn type -> type in [:criteria_adjustment, :complete_rewrite] end)

    case complex_edits do
      count when count >= 2 -> :expert
      1 -> :intermediate
      _ -> :beginner
    end
  end

  defp assess_guidance_effectiveness(time_to_first_edit, edit_count) do
    initial_satisfaction = infer_initial_satisfaction(time_to_first_edit)
    edit_frequency = classify_edit_frequency(edit_count)

    case {initial_satisfaction, edit_frequency} do
      {:satisfied, :minimal} -> :excellent
      {:somewhat_satisfied, :normal} -> :good
      {:unsatisfied, _} -> :poor
      _ -> :fair
    end
  end
end
