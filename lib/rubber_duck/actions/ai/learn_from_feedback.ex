defmodule RubberDuck.Actions.AI.LearnFromFeedback do
  @moduledoc """
  Action for learning from user feedback on AI analyses.

  Processes feedback to:
  - Improve future analysis accuracy
  - Adjust analysis parameters
  - Update quality metrics
  - Refine pattern recognition
  """

  use Jido.Action,
    name: "learn_from_feedback",
    description: "Learn and improve from analysis feedback",
    schema: [
      feedback: [type: :map, required: true],
      history: [type: {:list, :map}, default: []],
      learning_rate: [type: :float, default: 0.1]
    ]

  require Logger

  @impl true
  def run(params, _context) do
    with {:ok, processed} <- process_feedback(params.feedback),
         {:ok, patterns} <- extract_learning_patterns(processed, params.history),
         {:ok, adjustments} <- calculate_adjustments(patterns, params.learning_rate),
         {:ok, updates} <- generate_learning_updates(adjustments, processed) do

      {:ok, %{
        processed_feedback: processed,
        identified_patterns: patterns,
        accuracy_updates: updates.accuracy,
        improvement_areas: updates.improvements,
        preferences: updates.preferences,
        confidence: calculate_learning_confidence(patterns, params.history),
        recommendations: generate_recommendations(patterns, adjustments)
      }}
    end
  end

  defp process_feedback(feedback) do
    processed = %{
      type: determine_feedback_type(feedback),
      sentiment: analyze_sentiment(feedback),
      specificity: measure_specificity(feedback),
      actionable_points: extract_actionable_points(feedback),
      analysis_id: feedback[:analysis_id],
      timestamp: DateTime.utc_now()
    }

    {:ok, processed}
  end

  defp determine_feedback_type(feedback) do
    cond do
      feedback[:rating] -> :rating
      feedback[:correction] -> :correction
      feedback[:suggestion] -> :suggestion
      feedback[:complaint] -> :complaint
      feedback[:praise] -> :praise
      true -> :general
    end
  end

  defp analyze_sentiment(feedback) do
    # Simple sentiment analysis
    analyze_by_rating(feedback) || analyze_by_content(feedback)
  end

  defp analyze_by_rating(feedback) do
    case feedback[:rating] do
      rating when is_number(rating) and rating >= 4 -> :positive
      rating when is_number(rating) and rating <= 2 -> :negative
      _ -> nil
    end
  end

  defp analyze_by_content(feedback) do
    cond do
      feedback[:praise] -> :positive
      feedback[:complaint] -> :negative
      contains_positive_words?(feedback) -> :positive
      contains_negative_words?(feedback) -> :negative
      true -> :neutral
    end
  end

  defp contains_positive_words?(feedback) do
    positive_words = ["good", "great", "excellent", "helpful", "accurate", "useful"]
    text = extract_text(feedback)

    Enum.any?(positive_words, &String.contains?(String.downcase(text), &1))
  end

  defp contains_negative_words?(feedback) do
    negative_words = ["bad", "wrong", "incorrect", "useless", "poor", "terrible"]
    text = extract_text(feedback)

    Enum.any?(negative_words, &String.contains?(String.downcase(text), &1))
  end

  defp extract_text(feedback) do
    [
      feedback[:comment],
      feedback[:text],
      feedback[:message],
      feedback[:description]
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
  end

  defp measure_specificity(feedback) do
    points = 0

    # Check for specific elements
    points = if feedback[:analysis_id], do: points + 1, else: points
    points = if feedback[:specific_issue], do: points + 2, else: points
    points = if feedback[:correction], do: points + 3, else: points
    points = if feedback[:line_number] || feedback[:location], do: points + 2, else: points

    cond do
      points >= 5 -> :high
      points >= 3 -> :medium
      true -> :low
    end
  end

  defp extract_actionable_points(feedback) do
    points = []

    points = if feedback[:correction] do
      [%{type: :correction, detail: feedback.correction} | points]
    else
      points
    end

    points = if feedback[:suggestion] do
      [%{type: :suggestion, detail: feedback.suggestion} | points]
    else
      points
    end

    points = if feedback[:specific_issue] do
      [%{type: :issue, detail: feedback.specific_issue} | points]
    else
      points
    end

    points
  end

  defp extract_feedback_patterns(processed, history) do
    recent_feedback = [processed | Enum.take(history, 50)]

    patterns = %{
      sentiment_trend: analyze_sentiment_trend(recent_feedback),
      common_issues: identify_common_issues(recent_feedback),
      improvement_velocity: calculate_improvement_velocity(recent_feedback),
      feedback_consistency: measure_feedback_consistency(recent_feedback),
      preference_patterns: extract_preference_patterns(recent_feedback)
    }

    {:ok, patterns}
  end

  defp analyze_sentiment_trend(feedback_list) do
    sentiments = Enum.map(feedback_list, & &1.sentiment)

    positive_count = Enum.count(sentiments, & &1 == :positive)
    negative_count = Enum.count(sentiments, & &1 == :negative)
    total = length(sentiments)

    cond do
      total == 0 -> :neutral
      positive_count / total > 0.6 -> :improving
      negative_count / total > 0.6 -> :declining
      true -> :stable
    end
  end

  defp identify_common_issues(feedback_list) do
    feedback_list
    |> Enum.flat_map(& &1.actionable_points)
    |> Enum.filter(& &1.type == :issue)
    |> Enum.group_by(& &1.detail)
    |> Enum.map(fn {issue, occurrences} ->
      %{issue: issue, frequency: length(occurrences)}
    end)
    |> Enum.sort_by(& &1.frequency, :desc)
    |> Enum.take(5)
  end

  defp calculate_improvement_velocity(feedback_list) do
    # Compare recent vs older feedback
    if length(feedback_list) >= 10 do
      recent = Enum.take(feedback_list, 5)
      older = Enum.slice(feedback_list, 5, 5)

      recent_positive = Enum.count(recent, & &1.sentiment == :positive)
      older_positive = Enum.count(older, & &1.sentiment == :positive)

      cond do
        recent_positive > older_positive -> :accelerating
        recent_positive < older_positive -> :decelerating
        true -> :steady
      end
    else
      :insufficient_data
    end
  end

  defp measure_feedback_consistency(feedback_list) do
    specificities = Enum.map(feedback_list, & &1.specificity)

    if length(specificities) > 0 do
      high_count = Enum.count(specificities, & &1 == :high)
      high_count / length(specificities)
    else
      0.0
    end
  end

  defp extract_preference_patterns(feedback_list) do
    preferences = %{}

    # Extract preferences from suggestions
    suggestions = feedback_list
      |> Enum.flat_map(& &1.actionable_points)
      |> Enum.filter(& &1.type == :suggestion)

    # Group by type of suggestion
    grouped = Enum.group_by(suggestions, fn suggestion ->
      categorize_suggestion(suggestion.detail)
    end)

    Enum.reduce(grouped, preferences, fn {category, items}, acc ->
      Map.put(acc, category, %{
        count: length(items),
        examples: Enum.take(items, 3)
      })
    end)
  end

  defp categorize_suggestion(detail) when is_binary(detail) do
    cond do
      String.contains?(detail, ["performance", "speed", "optimize"]) -> :performance
      String.contains?(detail, ["security", "vulnerable", "safe"]) -> :security
      String.contains?(detail, ["quality", "clean", "maintain"]) -> :quality
      String.contains?(detail, ["document", "comment", "explain"]) -> :documentation
      true -> :general
    end
  end
  defp categorize_suggestion(_), do: :general

  defp calculate_adjustments(patterns, learning_rate) do
    adjustments = %{
      accuracy_weight: calculate_accuracy_adjustment(patterns, learning_rate),
      focus_areas: determine_focus_adjustments(patterns),
      threshold_adjustments: calculate_threshold_adjustments(patterns, learning_rate),
      preference_weights: calculate_preference_weights(patterns.preference_patterns)
    }

    {:ok, adjustments}
  end

  defp calculate_accuracy_adjustment(patterns, learning_rate) do
    base_adjustment = case patterns.sentiment_trend do
      :improving -> learning_rate
      :declining -> -learning_rate
      _ -> 0
    end

    # Modify based on consistency
    base_adjustment * (0.5 + patterns.feedback_consistency * 0.5)
  end

  defp determine_focus_adjustments(patterns) do
    patterns.common_issues
    |> Enum.map(fn issue ->
      %{
        area: categorize_issue(issue.issue),
        weight: calculate_issue_weight(issue.frequency),
        priority: determine_issue_priority(issue)
      }
    end)
  end

  defp categorize_issue(issue) when is_binary(issue) do
    cond do
      String.contains?(issue, ["false", "incorrect"]) -> :accuracy
      String.contains?(issue, ["miss", "overlook"]) -> :completeness
      String.contains?(issue, ["irrelevant", "unnecessary"]) -> :relevance
      true -> :general
    end
  end
  defp categorize_issue(_), do: :general

  defp calculate_issue_weight(frequency) do
    min(1.0, frequency * 0.2)
  end

  defp determine_issue_priority(issue) do
    if issue.frequency > 3, do: :high, else: :normal
  end

  defp calculate_threshold_adjustments(patterns, learning_rate) do
    %{
      confidence_threshold: adjust_confidence_threshold(patterns, learning_rate),
      quality_threshold: adjust_quality_threshold(patterns, learning_rate),
      complexity_threshold: adjust_complexity_threshold(patterns, learning_rate)
    }
  end

  defp adjust_confidence_threshold(patterns, learning_rate) do
    case patterns.sentiment_trend do
      :declining -> -learning_rate * 0.1  # Lower threshold if declining
      :improving -> learning_rate * 0.05   # Slightly raise if improving
      _ -> 0
    end
  end

  defp adjust_quality_threshold(patterns, learning_rate) do
    if patterns.feedback_consistency > 0.7 do
      learning_rate * 0.1
    else
      0
    end
  end

  defp adjust_complexity_threshold(_patterns, _learning_rate) do
    0  # Keep stable for now
  end

  defp calculate_preference_weights(preference_patterns) do
    total_suggestions = preference_patterns
      |> Map.values()
      |> Enum.map(& &1.count)
      |> Enum.sum()

    if total_suggestions > 0 do
      Enum.reduce(preference_patterns, %{}, fn {category, data}, acc ->
        weight = data.count / total_suggestions
        Map.put(acc, category, weight)
      end)
    else
      %{}
    end
  end

  defp generate_learning_updates(adjustments, processed) do
    updates = %{
      accuracy: generate_accuracy_updates(adjustments, processed),
      improvements: generate_improvement_updates(adjustments),
      preferences: generate_preference_updates(adjustments)
    }

    {:ok, updates}
  end

  defp generate_accuracy_updates(adjustments, processed) do
    base_updates = %{
      weight: adjustments.accuracy_weight,
      timestamp: DateTime.utc_now()
    }

    # Add specific updates based on feedback type
    case processed.type do
      :correction ->
        Map.put(base_updates, :correction_applied, true)
      :rating ->
        Map.put(base_updates, :rating_incorporated, true)
      _ ->
        base_updates
    end
  end

  defp generate_improvement_updates(adjustments) do
    adjustments.focus_areas
    |> Enum.map(fn area ->
      %{
        area: area.area,
        priority: area.priority,
        adjustment_weight: area.weight,
        action: determine_improvement_action(area)
      }
    end)
  end

  defp determine_improvement_action(area) do
    case area.area do
      :accuracy -> :increase_validation
      :completeness -> :expand_coverage
      :relevance -> :refine_filtering
      _ -> :monitor
    end
  end

  defp generate_preference_updates(adjustments) do
    %{
      weights: adjustments.preference_weights,
      thresholds: adjustments.threshold_adjustments,
      updated_at: DateTime.utc_now()
    }
  end

  defp calculate_learning_confidence(patterns, history) do
    factors = []

    # Factor in data volume
    factors = if length(history) > 20 do
      [0.3 | factors]
    else
      [0.1 | factors]
    end

    # Factor in consistency
    factors = [patterns.feedback_consistency * 0.4 | factors]

    # Factor in trend clarity
    trend_factor = case patterns.sentiment_trend do
      :improving -> 0.3
      :declining -> 0.2
      :stable -> 0.25
      _ -> 0.1
    end
    factors = [trend_factor | factors]

    Enum.sum(factors)
  end

  defp generate_recommendations(patterns, adjustments) do
    recommendations = []

    # Add recommendations based on patterns
    recommendations = case patterns.sentiment_trend do
      :declining ->
        ["Review and adjust analysis algorithms" | recommendations]
      :improving ->
        ["Continue current approach with minor refinements" | recommendations]
      _ ->
        recommendations
    end

    # Add recommendations based on common issues
    issue_recommendations = patterns.common_issues
      |> Enum.take(3)
      |> Enum.map(fn issue ->
        "Address recurring issue: #{issue.issue}"
      end)

    recommendations = recommendations ++ issue_recommendations

    # Add preference-based recommendations
    preference_recommendations = adjustments.preference_weights
      |> Enum.sort_by(fn {_, weight} -> weight end, :desc)
      |> Enum.take(2)
      |> Enum.map(fn {category, _} ->
        "Increase focus on #{category} analysis"
      end)

    recommendations ++ preference_recommendations
  end
end
