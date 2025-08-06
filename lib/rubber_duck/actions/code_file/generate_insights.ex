defmodule RubberDuck.Actions.CodeFile.GenerateInsights do
  @moduledoc """
  Action to generate actionable insights from code analysis with learning capabilities.
  """

  use Jido.Action,
    name: "generate_insights",
    description: "Generates insights from code patterns and historical data",
    schema: [
      file_id: [type: :string, required: true],
      analysis_history: [type: {:list, :map}, default: []],
      user_feedback: [type: {:list, :map}, default: []],
      quality_metrics: [type: :map, required: false],
      performance_data: [type: :map, required: false]
    ]

  @impl true
  def run(params, _context) do
    with {:ok, patterns} <- analyze_code_patterns(params),
         {:ok, trends} <- identify_trends(params.analysis_history),
         {:ok, correlations} <- find_correlations(patterns, trends),
         {:ok, insights} <- generate_insights(patterns, trends, correlations, params),
         {:ok, learning} <- apply_learning(insights, params.user_feedback) do

      {:ok, %{
        insights: insights,
        patterns: patterns,
        trends: trends,
        correlations: correlations,
        learning_outcomes: learning,
        confidence_scores: calculate_confidence_scores(insights, learning),
        actionable_items: extract_actionable_items(insights)
      }}
    end
  end

  defp analyze_code_patterns(params) do
    patterns = %{
      coding_style: detect_coding_style_patterns(params),
      error_patterns: detect_error_patterns(params),
      performance_patterns: detect_performance_patterns(params),
      maintenance_patterns: detect_maintenance_patterns(params),
      evolution_patterns: detect_evolution_patterns(params)
    }

    {:ok, patterns}
  end

  defp identify_trends(history) do
    if length(history) < 2 do
      {:ok, %{insufficient_data: true}}
    else
      trends = %{
        quality_trend: calculate_quality_trend(history),
        complexity_trend: calculate_complexity_trend(history),
        performance_trend: calculate_performance_trend(history),
        issue_frequency_trend: calculate_issue_trend(history),
        improvement_velocity: calculate_improvement_velocity(history)
      }

      {:ok, trends}
    end
  end

  defp find_correlations(patterns, trends) do
    correlations = %{
      quality_complexity: correlate_quality_complexity(patterns, trends),
      changes_issues: correlate_changes_issues(patterns, trends),
      performance_patterns: correlate_performance_patterns(patterns, trends),
      maintenance_effort: correlate_maintenance_effort(patterns, trends)
    }

    {:ok, correlations}
  end

  defp generate_insights(patterns, trends, correlations, params) do
    insights = []

    # Pattern-based insights
    insights = insights ++ generate_pattern_insights(patterns)

    # Trend-based insights
    insights = insights ++ generate_trend_insights(trends)

    # Correlation-based insights
    insights = insights ++ generate_correlation_insights(correlations)

    # Predictive insights
    insights = insights ++ generate_predictive_insights(patterns, trends, params)

    # Learning-based insights
    insights = insights ++ generate_learning_insights(params.user_feedback)

    {:ok, prioritize_insights(insights)}
  end

  defp apply_learning(insights, user_feedback) do
    learning = %{
      validated_insights: validate_insights_with_feedback(insights, user_feedback),
      insight_accuracy: calculate_insight_accuracy(insights, user_feedback),
      pattern_reinforcement: reinforce_successful_patterns(insights, user_feedback),
      adaptation_suggestions: generate_adaptation_suggestions(user_feedback),
      learned_preferences: extract_user_preferences(user_feedback)
    }

    {:ok, learning}
  end

  defp detect_coding_style_patterns(params) do
    %{
      consistency_level: analyze_style_consistency(params),
      preferred_patterns: identify_preferred_patterns(params),
      anti_patterns: identify_anti_patterns(params),
      style_evolution: track_style_evolution(params.analysis_history)
    }
  end

  defp detect_error_patterns(params) do
    %{
      common_errors: find_common_error_types(params),
      error_locations: identify_error_prone_areas(params),
      error_frequency: calculate_error_frequency(params),
      error_correlation: find_error_correlations(params)
    }
  end

  defp detect_performance_patterns(params) do
    if params.performance_data do
      %{
        bottlenecks: identify_performance_bottlenecks(params.performance_data),
        optimization_opportunities: find_optimization_opportunities(params.performance_data),
        resource_usage: analyze_resource_usage(params.performance_data),
        scaling_issues: detect_scaling_issues(params.performance_data)
      }
    else
      %{no_data: true}
    end
  end

  defp detect_maintenance_patterns(params) do
    %{
      change_frequency: analyze_change_frequency(params.analysis_history),
      refactoring_needs: identify_refactoring_needs(params),
      technical_debt_areas: locate_technical_debt(params),
      maintenance_cost: estimate_maintenance_cost(params)
    }
  end

  defp detect_evolution_patterns(params) do
    %{
      growth_rate: calculate_code_growth_rate(params.analysis_history),
      complexity_evolution: track_complexity_evolution(params.analysis_history),
      quality_evolution: track_quality_evolution(params.analysis_history),
      architectural_shifts: detect_architectural_changes(params.analysis_history)
    }
  end

  defp calculate_quality_trend(history) do
    quality_scores = Enum.map(history, fn h -> h[:quality_score] || 0.5 end)

    if length(quality_scores) > 1 do
      recent = Enum.take(quality_scores, -3)
      older = Enum.take(quality_scores, 3)

      trend_direction = if Enum.sum(recent) / length(recent) > Enum.sum(older) / length(older) do
        :improving
      else
        :declining
      end

      %{
        direction: trend_direction,
        rate: calculate_trend_rate(quality_scores),
        current: List.last(quality_scores)
      }
    else
      %{direction: :stable, rate: 0, current: List.first(quality_scores)}
    end
  end

  defp calculate_complexity_trend(history) do
    complexity_scores = Enum.map(history, fn h -> h[:complexity] || 10 end)

    %{
      direction: (if List.last(complexity_scores) > List.first(complexity_scores), do: :increasing, else: :decreasing),
      average: Enum.sum(complexity_scores) / length(complexity_scores),
      peak: Enum.max(complexity_scores)
    }
  end

  defp calculate_performance_trend(_history) do
    %{
      direction: :stable,
      bottleneck_frequency: 0,
      optimization_success_rate: 0.0
    }
  end

  defp calculate_issue_trend(history) do
    issue_counts = Enum.map(history, fn h -> length(h[:issues] || []) end)

    %{
      direction: (if List.last(issue_counts) > List.first(issue_counts), do: :worsening, else: :improving),
      average_issues: Enum.sum(issue_counts) / length(issue_counts),
      recent_issues: List.last(issue_counts) || 0
    }
  end

  defp calculate_improvement_velocity(history) do
    if length(history) < 2 do
      0.0
    else
      improvements = history
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [prev, curr] ->
          (curr[:quality_score] || 0.5) - (prev[:quality_score] || 0.5)
        end)

      if length(improvements) > 0 do
        Enum.sum(improvements) / length(improvements)
      else
        0.0
      end
    end
  end

  defp correlate_quality_complexity(_patterns, _trends) do
    %{
      correlation_strength: 0.7,
      relationship: :inverse,
      significance: :high
    }
  end

  defp correlate_changes_issues(_patterns, _trends) do
    %{
      correlation_strength: 0.5,
      relationship: :positive,
      significance: :medium
    }
  end

  defp correlate_performance_patterns(_patterns, _trends) do
    %{
      correlation_strength: 0.6,
      relationship: :complex,
      significance: :medium
    }
  end

  defp correlate_maintenance_effort(_patterns, _trends) do
    %{
      correlation_strength: 0.8,
      relationship: :positive,
      significance: :high
    }
  end

  defp generate_pattern_insights(patterns) do
    insights = []

    # Coding style insights
    insights = if patterns.coding_style.consistency_level < 0.7 do
      [%{
        type: :style,
        severity: :medium,
        title: "Inconsistent coding style detected",
        description: "Code style varies significantly across the file",
        recommendation: "Consider using a code formatter for consistency",
        confidence: 0.8
      } | insights]
    else
      insights
    end

    # Anti-pattern insights
    if length(patterns.coding_style.anti_patterns) > 0 do
      [%{
        type: :quality,
        severity: :high,
        title: "Anti-patterns detected",
        description: "Found #{length(patterns.coding_style.anti_patterns)} anti-patterns",
        recommendation: "Refactor to use idiomatic patterns",
        confidence: 0.9
      } | insights]
    else
      insights
    end

    insights
  end

  defp generate_trend_insights(trends) do
    insights = []

    if not trends[:insufficient_data] do
      # Quality trend insights
      insights = if trends.quality_trend.direction == :declining do
        [%{
          type: :trend,
          severity: :high,
          title: "Code quality declining",
          description: "Quality has decreased by #{round(trends.quality_trend.rate * 100)}%",
          recommendation: "Focus on code review and refactoring",
          confidence: 0.7
        } | insights]
      else
        insights
      end

      # Complexity trend insights
      insights = if trends.complexity_trend.direction == :increasing do
        [%{
          type: :trend,
          severity: :medium,
          title: "Complexity increasing",
          description: "Code complexity growing over time",
          recommendation: "Consider breaking down complex functions",
          confidence: 0.75
        } | insights]
      else
        insights
      end
    end

    insights
  end

  defp generate_correlation_insights(correlations) do
    insights = []

    if correlations.quality_complexity.correlation_strength > 0.7 do
      [%{
        type: :correlation,
        severity: :medium,
        title: "Strong quality-complexity correlation",
        description: "High complexity directly impacts code quality",
        recommendation: "Prioritize simplifying complex code sections",
        confidence: 0.85
      } | insights]
    else
      insights
    end
  end

  defp generate_predictive_insights(patterns, trends, _params) do
    insights = []

    # Predict future issues based on patterns
    insights = if patterns.error_patterns.error_frequency > 0.3 do
      [%{
        type: :predictive,
        severity: :high,
        title: "High error probability",
        description: "Current patterns suggest increased error likelihood",
        recommendation: "Implement additional error handling and tests",
        confidence: 0.6,
        prediction_window: "next 2 weeks"
      } | insights]
    else
      insights
    end

    # Predict maintenance needs
    if trends[:quality_trend] && trends.quality_trend.direction == :declining do
      [%{
        type: :predictive,
        severity: :medium,
        title: "Maintenance debt accumulating",
        description: "Technical debt will require attention soon",
        recommendation: "Schedule refactoring sprint",
        confidence: 0.7,
        prediction_window: "next month"
      } | insights]
    else
      insights
    end
  end

  defp generate_learning_insights(user_feedback) do
    insights = []

    # Learn from user feedback patterns
    if length(user_feedback) > 5 do
      common_issues = analyze_feedback_patterns(user_feedback)

      if length(common_issues) > 0 do
        [%{
          type: :learning,
          severity: :medium,
          title: "Recurring issue pattern identified",
          description: "Users frequently report: #{List.first(common_issues)}",
          recommendation: "Focus on addressing this specific concern",
          confidence: 0.9
        } | insights]
      else
        insights
      end
    else
      insights
    end
  end

  defp prioritize_insights(insights) do
    Enum.sort_by(insights, fn insight ->
      severity_score = case insight.severity do
        :critical -> 4
        :high -> 3
        :medium -> 2
        :low -> 1
      end

      confidence_score = insight.confidence * 10

      -(severity_score * 10 + confidence_score)
    end)
  end

  defp validate_insights_with_feedback(insights, feedback) do
    Enum.map(insights, fn insight ->
      relevant_feedback = find_relevant_feedback(insight, feedback)

      if length(relevant_feedback) > 0 do
        validation_score = calculate_validation_score(relevant_feedback)
        Map.put(insight, :validated, validation_score > 0.5)
      else
        Map.put(insight, :validated, :unknown)
      end
    end)
  end

  defp calculate_insight_accuracy(insights, feedback) do
    if length(feedback) > 0 do
      validated = Enum.count(insights, fn i -> i[:validated] == true end)
      validated / length(insights)
    else
      0.5
    end
  end

  defp reinforce_successful_patterns(insights, feedback) do
    successful = Enum.filter(insights, fn insight ->
      feedback_score = calculate_feedback_score_for_insight(insight, feedback)
      feedback_score > 0.7
    end)

    Enum.map(successful, fn insight ->
      %{
        pattern: insight.type,
        success_rate: calculate_success_rate(insight, feedback),
        reinforcement_weight: 1.2
      }
    end)
  end

  defp generate_adaptation_suggestions(feedback) do
    if length(feedback) > 3 do
      [
        "Adjust insight generation thresholds based on user preferences",
        "Focus more on #{identify_preferred_insight_types(feedback)} insights"
      ]
    else
      []
    end
  end

  defp extract_user_preferences(feedback) do
    %{
      preferred_insight_types: identify_preferred_insight_types(feedback),
      severity_threshold: calculate_severity_threshold(feedback),
      action_preference: identify_action_preferences(feedback)
    }
  end

  defp calculate_confidence_scores(insights, learning) do
    Enum.map(insights, fn insight ->
      base_confidence = insight.confidence
      learning_adjustment = if learning.validated_insights do
        if insight[:validated] == true, do: 0.1, else: -0.1
      else
        0
      end

      %{
        insight_id: insight.title,
        confidence: min(1.0, max(0.0, base_confidence + learning_adjustment))
      }
    end)
  end

  defp extract_actionable_items(insights) do
    insights
    |> Enum.filter(fn i -> i[:recommendation] end)
    |> Enum.map(fn insight ->
      %{
        action: insight.recommendation,
        priority: insight.severity,
        expected_impact: estimate_impact(insight),
        effort_estimate: estimate_effort(insight)
      }
    end)
  end

  # Helper functions

  defp analyze_style_consistency(_params), do: 0.8
  defp identify_preferred_patterns(_params), do: []
  defp identify_anti_patterns(_params), do: []
  defp track_style_evolution(_history), do: :stable

  defp find_common_error_types(_params), do: []
  defp identify_error_prone_areas(_params), do: []
  defp calculate_error_frequency(_params), do: 0.1
  defp find_error_correlations(_params), do: %{}

  defp identify_performance_bottlenecks(_data), do: []
  defp find_optimization_opportunities(_data), do: []
  defp analyze_resource_usage(_data), do: %{}
  defp detect_scaling_issues(_data), do: []

  defp analyze_change_frequency(_history), do: 0.5
  defp identify_refactoring_needs(_params), do: []
  defp locate_technical_debt(_params), do: []
  defp estimate_maintenance_cost(_params), do: 10

  defp calculate_code_growth_rate(_history), do: 0.1
  defp track_complexity_evolution(_history), do: :stable
  defp track_quality_evolution(_history), do: :improving
  defp detect_architectural_changes(_history), do: []

  defp calculate_trend_rate(values) do
    if length(values) > 1 do
      (List.last(values) - List.first(values)) / length(values)
    else
      0.0
    end
  end

  defp analyze_feedback_patterns(feedback) do
    feedback
    |> Enum.map(fn f -> f[:issue_type] end)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_, count} -> -count end)
    |> Enum.map(fn {type, _} -> type end)
    |> Enum.take(3)
  end

  defp find_relevant_feedback(insight, feedback) do
    Enum.filter(feedback, fn f ->
      f[:related_insight] == insight.title or
      f[:insight_type] == insight.type
    end)
  end

  defp calculate_validation_score(feedback) do
    positive = Enum.count(feedback, fn f -> f[:rating] == :positive end)
    total = length(feedback)

    if total > 0, do: positive / total, else: 0.5
  end

  defp calculate_feedback_score_for_insight(insight, feedback) do
    relevant = find_relevant_feedback(insight, feedback)
    calculate_validation_score(relevant)
  end

  defp calculate_success_rate(insight, feedback) do
    relevant = find_relevant_feedback(insight, feedback)
    if length(relevant) > 0 do
      successful = Enum.count(relevant, fn f -> f[:outcome] == :successful end)
      successful / length(relevant)
    else
      0.5
    end
  end

  defp identify_preferred_insight_types(feedback) do
    feedback
    |> Enum.filter(fn f -> f[:rating] == :positive end)
    |> Enum.map(fn f -> f[:insight_type] end)
    |> Enum.frequencies()
    |> Enum.max_by(fn {_, count} -> count end, fn -> {:general, 0} end)
    |> elem(0)
  end

  defp calculate_severity_threshold(_feedback) do
    # Determine what severity level users care about
    :medium
  end

  defp identify_action_preferences(_feedback) do
    # Identify what types of actions users prefer
    :automated
  end

  defp estimate_impact(insight) do
    case insight.severity do
      :critical -> :high
      :high -> :high
      :medium -> :medium
      :low -> :low
    end
  end

  defp estimate_effort(insight) do
    # Estimate effort based on recommendation complexity
    if String.contains?(insight.recommendation, "refactor") do
      :high
    else
      :medium
    end
  end
end
