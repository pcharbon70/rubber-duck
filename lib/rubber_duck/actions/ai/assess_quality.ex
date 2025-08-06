defmodule RubberDuck.Actions.AI.AssessQuality do
  @moduledoc """
  Action for assessing the quality of AI analysis results.

  Self-evaluates analysis outcomes to:
  - Measure accuracy and relevance
  - Identify areas for improvement
  - Track quality trends over time
  - Learn from assessment patterns
  """

  use Jido.Action,
    name: "assess_quality",
    description: "Self-assess AI analysis quality",
    schema: [
      analysis_result: [type: :map, required: true],
      historical_data: [type: :map, default: %{}],
      criteria: [type: {:list, :atom}, default: [:accuracy, :relevance, :completeness, :actionability]]
    ]

  require Logger

  @impl true
  def run(params, _context) do
    with {:ok, assessment} <- perform_quality_assessment(params.analysis_result, params.criteria),
         {:ok, comparison} <- compare_with_historical(assessment, params.historical_data),
         {:ok, insights} <- derive_quality_insights(assessment, comparison) do

      {:ok, %{
        metrics: assessment,
        comparison: comparison,
        insights: insights,
        overall_score: calculate_overall_score(assessment),
        improvement_areas: identify_improvement_areas(assessment, comparison),
        confidence: calculate_confidence_level(assessment, params.historical_data)
      }}
    end
  end

  defp perform_quality_assessment(result, criteria) do
    assessment = Enum.reduce(criteria, %{}, fn criterion, acc ->
      score = assess_criterion(result, criterion)
      Map.put(acc, criterion, score)
    end)

    {:ok, assessment}
  end

  defp assess_criterion(result, :accuracy) do
    # Assess accuracy based on result properties
    score = cond do
      # Check if score is within reasonable bounds
      result[:score] && result.score >= 0 && result.score <= 100 -> 0.8

      # Check if has necessary details
      result[:details] && map_size(result.details) > 0 -> 0.7

      # Default lower score
      true -> 0.5
    end

    %{
      score: score,
      factors: analyze_accuracy_factors(result),
      confidence: calculate_accuracy_confidence(result)
    }
  end

  defp assess_criterion(result, :relevance) do
    score = cond do
      # Check if suggestions are present and relevant
      result[:suggestions] && length(result.suggestions) > 0 -> 0.85

      # Check if summary is meaningful
      result[:summary] && String.length(result.summary) > 20 -> 0.7

      true -> 0.5
    end

    %{
      score: score,
      factors: analyze_relevance_factors(result),
      context_match: evaluate_context_match(result)
    }
  end

  defp assess_criterion(result, :completeness) do
    required_fields = [:summary, :details, :score, :suggestions]
    present_fields = Enum.filter(required_fields, &Map.has_key?(result, &1))

    score = length(present_fields) / length(required_fields)

    %{
      score: score,
      missing_fields: required_fields -- present_fields,
      coverage: calculate_coverage(result)
    }
  end

  defp assess_criterion(result, :actionability) do
    suggestions = result[:suggestions] || []

    score = cond do
      length(suggestions) >= 3 -> 0.9
      length(suggestions) >= 1 -> 0.7
      true -> 0.3
    end

    %{
      score: score,
      suggestion_count: length(suggestions),
      specificity: evaluate_suggestion_specificity(suggestions)
    }
  end

  defp assess_criterion(_result, _criterion) do
    # Default assessment for unknown criteria
    %{score: 0.5, note: "Unknown criterion"}
  end

  defp analyze_accuracy_factors(result) do
    factors = []

    factors = if result[:score] do
      [{:has_score, true} | factors]
    else
      [{:has_score, false} | factors]
    end

    factors = if result[:metrics] do
      [{:has_metrics, true} | factors]
    else
      [{:has_metrics, false} | factors]
    end

    factors
  end

  defp calculate_accuracy_confidence(result) do
    base_confidence = 0.5

    adjustments = cond do
      result[:confidence] -> result.confidence
      result[:metrics] && map_size(result.metrics) > 3 -> base_confidence + 0.3
      result[:details] && map_size(result.details) > 0 -> base_confidence + 0.2
      true -> base_confidence
    end

    min(1.0, adjustments)
  end

  defp analyze_relevance_factors(result) do
    %{
      has_suggestions: result[:suggestions] != nil,
      has_summary: result[:summary] != nil,
      suggestion_quality: evaluate_suggestion_quality(result[:suggestions] || [])
    }
  end

  defp evaluate_context_match(_result) do
    # Would compare against expected context
    0.75
  end

  defp calculate_coverage(result) do
    covered_aspects = []

    covered_aspects = if result[:summary], do: [:summary | covered_aspects], else: covered_aspects
    covered_aspects = if result[:details], do: [:details | covered_aspects], else: covered_aspects
    covered_aspects = if result[:suggestions], do: [:suggestions | covered_aspects], else: covered_aspects
    covered_aspects = if result[:score], do: [:score | covered_aspects], else: covered_aspects

    length(covered_aspects)
  end

  defp evaluate_suggestion_specificity(suggestions) do
    if length(suggestions) > 0 do
      specific_count = Enum.count(suggestions, &String.length(&1) > 30)
      specific_count / length(suggestions)
    else
      0.0
    end
  end

  defp evaluate_suggestion_quality(suggestions) do
    cond do
      Enum.empty?(suggestions) -> :none
      Enum.all?(suggestions, &String.length(&1) > 50) -> :high
      Enum.any?(suggestions, &String.length(&1) > 30) -> :medium
      true -> :low
    end
  end

  defp compare_with_historical(assessment, historical_data) do
    if map_size(historical_data) == 0 do
      {:ok, %{status: :no_history, trends: %{}}}
    else
      comparison = %{
        status: :compared,
        trends: calculate_trends(assessment, historical_data),
        percentile: calculate_percentile(assessment, historical_data),
        improvement_rate: calculate_improvement_rate(assessment, historical_data)
      }

      {:ok, comparison}
    end
  end

  defp calculate_trends(assessment, historical) do
    Enum.reduce(assessment, %{}, fn {criterion, current}, acc ->
      historical_values = Map.get(historical, criterion, [])
      trend = calculate_single_trend(current, historical_values)
      Map.put(acc, criterion, trend)
    end)
  end

  defp calculate_single_trend(current, historical_values) do
    if length(historical_values) > 0 do
      avg_historical = Enum.sum(Enum.map(historical_values, & &1.score)) / length(historical_values)

      cond do
        current.score > avg_historical + 0.1 -> :improving
        current.score < avg_historical - 0.1 -> :declining
        true -> :stable
      end
    else
      :unknown
    end
  end

  defp calculate_percentile(assessment, historical) do
    overall = calculate_overall_score(assessment)

    historical_scores = Map.get(historical, :overall_scores, [])

    if length(historical_scores) > 0 do
      better_than = Enum.count(historical_scores, & &1 < overall)
      (better_than / length(historical_scores)) * 100
    else
      50.0  # Default to median if no history
    end
  end

  defp calculate_improvement_rate(assessment, historical) do
    recent_scores = historical
      |> Map.get(:recent_scores, [])
      |> Enum.take(10)

    if length(recent_scores) >= 2 do
      first = List.first(recent_scores)
      current = calculate_overall_score(assessment)

      if first > 0 do
        ((current - first) / first) * 100
      else
        0.0
      end
    else
      0.0
    end
  end

  defp derive_quality_insights(assessment, comparison) do
    insights = []

    # Check for high-performing areas
    high_performers = Enum.filter(assessment, fn {_, v} ->
      v[:score] && v.score > 0.8
    end)

    insights = if length(high_performers) > 0 do
      ["Strong performance in: #{Enum.map_join(high_performers, ", ", &elem(&1, 0))}" | insights]
    else
      insights
    end

    # Check for improvement areas
    low_performers = Enum.filter(assessment, fn {_, v} ->
      v[:score] && v.score < 0.6
    end)

    insights = if length(low_performers) > 0 do
      ["Needs improvement in: #{Enum.map_join(low_performers, ", ", &elem(&1, 0))}" | insights]
    else
      insights
    end

    # Add trend insights
    insights = if comparison[:trends] do
      add_trend_insights(insights, comparison.trends)
    else
      insights
    end

    {:ok, insights}
  end

  defp add_trend_insights(insights, trends) do
    improving = Enum.filter(trends, fn {_, trend} -> trend == :improving end)

    if length(improving) > 0 do
      ["Improving trends in: #{Enum.map_join(improving, ", ", &elem(&1, 0))}" | insights]
    else
      insights
    end
  end

  defp calculate_overall_score(assessment) do
    scores = assessment
      |> Enum.map(fn {_, v} -> v[:score] || 0 end)
      |> Enum.filter(& &1 > 0)

    if length(scores) > 0 do
      Enum.sum(scores) / length(scores)
    else
      0.0
    end
  end

  defp identify_improvement_areas(assessment, comparison) do
    areas = []

    # Find low-scoring criteria
    low_scores = assessment
    |> Enum.filter(fn {_, v} ->
      v[:score] && v.score < 0.6
    end)
    |> Enum.map(&elem(&1, 0))

    areas = if length(low_scores) > 0 do
      low_scores ++ areas
    else
      areas
    end

    # Find declining trends
    declining = if comparison[:trends] do
      comparison.trends
      |> Enum.filter(fn {_, trend} ->
        trend == :declining
      end)
      |> Enum.map(&elem(&1, 0))
    else
      []
    end

    Enum.uniq(areas ++ declining)
  end

  defp calculate_confidence_level(assessment, historical_data) do
    base_confidence = calculate_overall_score(assessment)

    # Adjust based on historical consistency
    consistency_factor = if map_size(historical_data) > 0 do
      calculate_consistency(assessment, historical_data)
    else
      0.5
    end

    # Combine factors
    (base_confidence * 0.7 + consistency_factor * 0.3)
  end

  defp calculate_consistency(assessment, historical) do
    current_score = calculate_overall_score(assessment)
    historical_scores = Map.get(historical, :overall_scores, [current_score])

    if length(historical_scores) > 0 do
      avg = Enum.sum(historical_scores) / length(historical_scores)
      variance = Enum.reduce(historical_scores, 0, fn score, acc ->
        acc + :math.pow(score - avg, 2)
      end) / length(historical_scores)

      std_dev = :math.sqrt(variance)

      # Lower std_dev means higher consistency
      if std_dev < 0.1 do
        0.9
      else
        max(0.3, 1.0 - std_dev)
      end
    else
      0.5
    end
  end
end
