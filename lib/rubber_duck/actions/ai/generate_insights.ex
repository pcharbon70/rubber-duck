defmodule RubberDuck.Actions.AI.GenerateInsights do
  @moduledoc """
  Action for generating actionable insights from patterns and analyses.

  Creates:
  - Trend analysis
  - Predictive insights
  - Optimization opportunities
  - Strategic recommendations
  """

  use Jido.Action,
    name: "generate_insights",
    description: "Generate actionable insights from analysis data",
    schema: [
      context: [type: :map, required: true],
      patterns: [type: {:list, :map}, default: []],
      cache: [type: :map, default: %{}],
      depth: [type: :atom, default: :normal]
    ]

  require Logger

  @impl true
  def run(params, _context) do
    with {:ok, analyzed} <- analyze_context(params.context, params.patterns),
         {:ok, trends} <- identify_trends(analyzed, params.cache),
         {:ok, predictions} <- generate_predictions(trends, params.depth),
         {:ok, opportunities} <- identify_opportunities(analyzed, predictions),
         {:ok, recommendations} <- formulate_recommendations(opportunities, params.context) do

      {:ok, build_insights(params, trends, predictions, opportunities, recommendations)}
    end
  end

  defp build_insights(params, trends, predictions, opportunities, recommendations) do
    %{
      context_id: generate_context_id(params.context),
      trends: trends,
      predictions: predictions,
      opportunities: opportunities,
      recommendations: recommendations,
      confidence: calculate_insight_confidence(trends, predictions),
      timestamp: DateTime.utc_now(),
      metadata: build_insight_metadata(params)
    }
  end

  defp analyze_context(context, patterns) do
    analysis = %{
      scope: determine_scope(context),
      time_range: extract_time_range(context),
      relevant_patterns: filter_relevant_patterns(patterns, context),
      key_metrics: extract_key_metrics(context),
      baseline: establish_baseline(context)
    }

    {:ok, analysis}
  end

  defp determine_scope(context) do
    cond do
      context[:project_id] -> :project
      context[:file_id] -> :file
      context[:workspace] -> :workspace
      true -> :unknown
    end
  end

  defp extract_time_range(context) do
    %{
      start: context[:start_date] || DateTime.add(DateTime.utc_now(), -30, :day),
      end: context[:end_date] || DateTime.utc_now()
    }
  end

  defp filter_relevant_patterns(patterns, context) do
    Enum.filter(patterns, fn pattern ->
      pattern_relevant_to_context?(pattern, context)
    end)
  end

  defp pattern_relevant_to_context?(pattern, context) do
    cond do
      context[:project_id] && pattern[:details][:project_id] == context.project_id -> true
      context[:file_id] && pattern[:details][:file_id] == context.file_id -> true
      context[:workspace] -> true
      true -> false
    end
  end

  defp extract_key_metrics(context) do
    %{
      quality_score: context[:quality_score],
      complexity: context[:complexity],
      coverage: context[:coverage],
      performance: context[:performance]
    }
  end

  defp establish_baseline(context) do
    # Establish baseline metrics for comparison
    %{
      average_quality: context[:historical_quality] || 75.0,
      average_complexity: context[:historical_complexity] || 10,
      typical_issues: context[:typical_issues] || []
    }
  end

  defp identify_trends(analysis, cache) do
    trends = %{
      quality: analyze_quality_trend(analysis),
      complexity: analyze_complexity_trend(analysis),
      patterns: analyze_pattern_trends(analysis.relevant_patterns),
      velocity: calculate_development_velocity(analysis),
      stability: assess_stability_trend(analysis, cache)
    }

    {:ok, trends}
  end

  defp analyze_quality_trend(analysis) do
    current = analysis.key_metrics.quality_score || analysis.baseline.average_quality
    baseline = analysis.baseline.average_quality

    trend = cond do
      current > baseline + 5 -> :improving
      current < baseline - 5 -> :declining
      true -> :stable
    end

    %{
      direction: trend,
      magnitude: abs(current - baseline),
      confidence: 0.75
    }
  end

  defp analyze_complexity_trend(analysis) do
    current = analysis.key_metrics.complexity || analysis.baseline.average_complexity
    baseline = analysis.baseline.average_complexity

    trend = cond do
      current > baseline * 1.2 -> :increasing
      current < baseline * 0.8 -> :decreasing
      true -> :stable
    end

    %{
      direction: trend,
      magnitude: abs(current - baseline) / baseline,
      areas_of_concern: identify_complexity_hotspots(analysis)
    }
  end

  defp identify_complexity_hotspots(analysis) do
    analysis.relevant_patterns
    |> Enum.filter(& &1.type == :high_complexity)
    |> Enum.map(& &1.details)
    |> Enum.take(5)
  end

  defp analyze_pattern_trends(patterns) do
    # Group patterns by age/timestamp if available
    recent = Enum.filter(patterns, &recent_pattern?/1)
    older = Enum.filter(patterns, &(not recent_pattern?(&1)))

    %{
      emerging: identify_emerging_patterns(recent, older),
      diminishing: identify_diminishing_patterns(recent, older),
      persistent: identify_persistent_patterns(recent, older)
    }
  end

  defp recent_pattern?(pattern) do
    if pattern[:discovered_at] do
      DateTime.diff(DateTime.utc_now(), pattern.discovered_at, :day) < 7
    else
      true
    end
  end

  defp identify_emerging_patterns(recent, older) do
    recent_types = MapSet.new(recent, & &1.type)
    older_types = MapSet.new(older, & &1.type)

    recent_types
    |> MapSet.difference(older_types)
    |> Enum.to_list()
  end

  defp identify_diminishing_patterns(recent, older) do
    recent_types = MapSet.new(recent, & &1.type)
    older_types = MapSet.new(older, & &1.type)

    older_types
    |> MapSet.difference(recent_types)
    |> Enum.to_list()
  end

  defp identify_persistent_patterns(recent, older) do
    recent_types = MapSet.new(recent, & &1.type)
    older_types = MapSet.new(older, & &1.type)

    recent_types
    |> MapSet.intersection(older_types)
    |> Enum.to_list()
  end

  defp calculate_development_velocity(analysis) do
    # Simplified velocity calculation
    pattern_count = length(analysis.relevant_patterns)

    cond do
      pattern_count > 20 -> :high
      pattern_count > 10 -> :medium
      pattern_count > 5 -> :low
      true -> :minimal
    end
  end

  defp assess_stability_trend(analysis, cache) do
    # Compare with cached historical data
    if cache[:previous_analysis] do
      previous_patterns = cache.previous_analysis[:pattern_count] || 0
      current_patterns = length(analysis.relevant_patterns)

      cond do
        current_patterns < previous_patterns * 0.8 -> :improving
        current_patterns > previous_patterns * 1.2 -> :degrading
        true -> :stable
      end
    else
      :unknown
    end
  end

  defp generate_predictions(trends, depth) do
    predictions = %{
      short_term: generate_short_term_predictions(trends),
      long_term: if depth == :deep do
        generate_long_term_predictions(trends)
      else
        []
      end,
      risk_areas: predict_risk_areas(trends),
      improvement_potential: estimate_improvement_potential(trends)
    }

    {:ok, predictions}
  end

  defp generate_short_term_predictions(trends) do
    predictions = []

    # Quality predictions
    predictions = case trends.quality.direction do
      :improving ->
        ["Quality metrics likely to exceed baseline within 1-2 weeks" | predictions]
      :declining ->
        ["Quality degradation may reach critical levels without intervention" | predictions]
      _ ->
        predictions
    end

    # Complexity predictions
    predictions = case trends.complexity.direction do
      :increasing ->
        ["Code complexity trending toward maintenance difficulties" | predictions]
      :decreasing ->
        ["Complexity reduction efforts showing positive results" | predictions]
      _ ->
        predictions
    end

    predictions
  end

  defp generate_long_term_predictions(trends) do
    predictions = []

    # Pattern evolution predictions
    predictions = if length(trends.patterns.emerging) > 0 do
      ["Emerging patterns may become dominant: #{Enum.join(trends.patterns.emerging, ", ")}" | predictions]
    else
      predictions
    end

    # Stability predictions
    predictions = case trends.stability do
      :degrading ->
        ["System stability at risk - proactive measures recommended" | predictions]
      :improving ->
        ["Continued stability improvements expected with current practices" | predictions]
      _ ->
        predictions
    end

    predictions
  end

  defp predict_risk_areas(trends) do
    risks = []

    risks = if trends.quality.direction == :declining do
      [%{area: :quality, level: :medium, description: "Declining code quality"} | risks]
    else
      risks
    end

    risks = if trends.complexity.direction == :increasing do
      [%{area: :complexity, level: :high, description: "Increasing complexity"} | risks]
    else
      risks
    end

    risks = if length(trends.patterns.persistent) > 5 do
      [%{area: :patterns, level: :medium, description: "Persistent problematic patterns"} | risks]
    else
      risks
    end

    risks
  end

  defp estimate_improvement_potential(trends) do
    base_potential = 50.0

    adjustments = 0
    adjustments = if trends.quality.direction == :improving, do: adjustments + 20, else: adjustments
    adjustments = if trends.complexity.direction == :decreasing, do: adjustments + 15, else: adjustments
    adjustments = if trends.stability == :stable, do: adjustments + 10, else: adjustments

    min(100, base_potential + adjustments)
  end

  defp identify_opportunities(analysis, predictions) do
    opportunities = []

    # Quick wins
    quick_wins = identify_quick_wins(analysis)
    opportunities = opportunities ++ Enum.map(quick_wins, &Map.put(&1, :category, :quick_win))

    # Strategic improvements
    strategic = identify_strategic_improvements(analysis, predictions)
    opportunities = opportunities ++ Enum.map(strategic, &Map.put(&1, :category, :strategic))

    # Preventive measures
    preventive = identify_preventive_measures(predictions)
    opportunities = opportunities ++ Enum.map(preventive, &Map.put(&1, :category, :preventive))

    {:ok, opportunities}
  end

  defp identify_quick_wins(analysis) do
    wins = []

    # Low-hanging fruit from patterns
    simple_patterns = analysis.relevant_patterns
      |> Enum.filter(& &1[:impact] && &1.impact.effort == :low)
      |> Enum.take(3)

    wins = wins ++ Enum.map(simple_patterns, fn pattern ->
      %{
        action: "Fix #{pattern.type}",
        impact: :medium,
        effort: :low,
        roi: :high
      }
    end)

    wins
  end

  defp identify_strategic_improvements(_analysis, predictions) do
    improvements = []

    # Based on improvement potential
    if predictions.improvement_potential > 70 do
      _improvements = [%{
        action: "Implement comprehensive refactoring",
        impact: :high,
        effort: :high,
        roi: :medium,
        timeline: "2-4 weeks"
      } | improvements]
    end

    # Based on risk areas
    high_risks = Enum.filter(predictions.risk_areas, & &1.level == :high)
    risk_improvements = Enum.map(high_risks, fn risk ->
      %{
        action: "Address #{risk.area} risk: #{risk.description}",
        impact: :high,
        effort: :medium,
        roi: :high,
        timeline: "1-2 weeks"
      }
    end)

    improvements ++ risk_improvements
  end

  defp identify_preventive_measures(predictions) do
    # Based on predicted risks
    predictions.risk_areas
      |> Enum.filter(& &1.level in [:medium, :high])
      |> Enum.map(fn risk ->
        %{
          action: "Prevent #{risk.area} issues",
          impact: :medium,
          effort: :low,
          roi: :high,
          description: "Proactive measure for #{risk.description}"
        }
      end)
  end

  defp formulate_recommendations(opportunities, context) do
    # Prioritize opportunities
    prioritized = opportunities
      |> score_opportunities()
      |> Enum.sort_by(& &1.score, :desc)
      |> Enum.take(10)

    # Format as actionable recommendations
    recommendations = Enum.map(prioritized, fn opp ->
      %{
        action: opp.action,
        priority: determine_priority(opp),
        expected_impact: opp.impact,
        implementation: generate_implementation_steps(opp, context),
        rationale: generate_rationale(opp)
      }
    end)

    {:ok, recommendations}
  end

  defp score_opportunities(opportunities) do
    Enum.map(opportunities, fn opp ->
      score = 0
      score = score + impact_score(opp.impact)
      score = score + effort_score(opp.effort)
      score = score + roi_score(opp[:roi])

      Map.put(opp, :score, score)
    end)
  end

  defp impact_score(:high), do: 30
  defp impact_score(:medium), do: 20
  defp impact_score(:low), do: 10
  defp impact_score(_), do: 5

  defp effort_score(:low), do: 30
  defp effort_score(:medium), do: 20
  defp effort_score(:high), do: 10
  defp effort_score(_), do: 5

  defp roi_score(:high), do: 25
  defp roi_score(:medium), do: 15
  defp roi_score(:low), do: 5
  defp roi_score(_), do: 0

  defp determine_priority(opportunity) do
    cond do
      opportunity.score > 70 -> :critical
      opportunity.score > 50 -> :high
      opportunity.score > 30 -> :medium
      true -> :low
    end
  end

  defp generate_implementation_steps(opportunity, _context) do
    base_steps = case opportunity.category do
      :quick_win ->
        ["Identify affected code", "Apply fix", "Test changes"]
      :strategic ->
        ["Plan implementation", "Allocate resources", "Execute in phases", "Monitor progress"]
      :preventive ->
        ["Set up monitoring", "Define thresholds", "Create alerts"]
      _ ->
        ["Assess current state", "Implement change", "Verify results"]
    end

    base_steps
  end

  defp generate_rationale(opportunity) do
    "#{opportunity.action} offers #{opportunity.impact} impact with #{opportunity.effort} effort" <>
    if opportunity[:roi], do: " and #{opportunity.roi} ROI", else: ""
  end

  defp calculate_insight_confidence(trends, predictions) do
    factors = []

    # Trend confidence
    trend_confidence = [
      trends.quality.confidence || 0.5,
      0.7  # Default confidence for other trends
    ]
    factors = factors ++ trend_confidence

    # Prediction confidence based on risk count
    prediction_confidence = if length(predictions.risk_areas) > 0 do
      0.6
    else
      0.8
    end
    factors = [prediction_confidence | factors]

    # Average all confidence factors
    if length(factors) > 0 do
      Enum.sum(factors) / length(factors)
    else
      0.5
    end
  end

  defp generate_context_id(context) do
    context
    |> :erlang.term_to_binary()
    |> then(& :crypto.hash(:md5, &1))
    |> Base.encode16()
    |> String.slice(0, 8)
  end

  defp build_insight_metadata(params) do
    %{
      depth: params.depth,
      pattern_count: length(params.patterns),
      cache_hit: map_size(params.cache) > 0,
      generated_at: DateTime.utc_now()
    }
  end
end
