defmodule RubberDuck.Actions.Agent.Learn do
  @moduledoc """
  Action for enabling agents to learn from their experiences.

  This action analyzes agent experiences and extracts patterns,
  improving future decision-making.
  """

  use Jido.Action,
    name: "agent_learn",
    description: "Extract patterns and insights from agent experiences",
    schema: [
      experiences: [type: {:list, :map}, required: true],
      learning_type: [type: :atom, values: [:pattern, :correlation, :prediction, :optimization], required: true],
      context: [type: :map, default: %{}],
      min_confidence: [type: :float, default: 0.7],
      max_patterns: [type: :pos_integer, default: 10]
    ]

  require Logger

  @impl true
  def run(params, _context) do
    case validate_learning_params(params) do
      :ok ->
        perform_learning(params.experiences, params.learning_type, params)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp perform_learning(experiences, _learning_type, _params) when length(experiences) < 3 do
    {:ok, %{
      learned: false,
      reason: :insufficient_data,
      required_experiences: 3,
      current_experiences: length(experiences)
    }}
  end

  defp perform_learning(experiences, learning_type, params) do
    insights = execute_learning_type(learning_type, experiences, params)

    {:ok, %{
      learned: true,
      learning_type: learning_type,
      insights: insights,
      confidence: calculate_confidence(insights, experiences),
      applicable_scenarios: identify_applicable_scenarios(insights)
    }}
  end

  defp execute_learning_type(:pattern, experiences, params), do: learn_patterns(experiences, params)
  defp execute_learning_type(:correlation, experiences, params), do: learn_correlations(experiences, params)
  defp execute_learning_type(:prediction, experiences, params), do: learn_predictions(experiences, params)
  defp execute_learning_type(:optimization, experiences, params), do: learn_optimizations(experiences, params)

  def describe do
    %{
      name: "Agent Learning",
      description: "Analyzes experiences to extract patterns and improve decision-making",
      category: "agent",
      inputs: %{
        experiences: "List of agent experiences to learn from",
        learning_type: "Type of learning to perform",
        context: "Additional context for learning",
        min_confidence: "Minimum confidence threshold for patterns",
        max_patterns: "Maximum number of patterns to extract"
      },
      outputs: %{
        success: %{
          learned: "Whether learning was successful",
          insights: "Extracted patterns or correlations",
          confidence: "Confidence level in the learned insights",
          applicable_scenarios: "Scenarios where insights can be applied"
        },
        insufficient_data: %{
          learned: "Always false for insufficient data",
          reason: "Why learning couldn't proceed",
          required_experiences: "Minimum experiences needed",
          current_experiences: "Current experience count"
        }
      }
    }
  end

  # Private functions

  defp learn_patterns(experiences, params) do
    # Group experiences by outcome
    grouped = Enum.group_by(experiences, fn exp ->
      get_outcome_category(exp)
    end)

    # Find common patterns in successful outcomes
    success_patterns = extract_success_patterns(grouped[:success] || [], params)
    failure_patterns = extract_failure_patterns(grouped[:failure] || [], params)

    %{
      success_patterns: Enum.take(success_patterns, params.max_patterns),
      failure_patterns: Enum.take(failure_patterns, params.max_patterns),
      pattern_confidence: calculate_pattern_confidence(success_patterns, failure_patterns),
      recommendations: generate_pattern_recommendations(success_patterns, failure_patterns)
    }
  end

  defp learn_correlations(experiences, params) do
    # Extract features from experiences
    features = extract_features(experiences)

    # Find correlations between features and outcomes
    correlations = calculate_correlations(features, experiences)

    # Filter by confidence threshold
    significant_correlations =
      correlations
      |> Enum.filter(fn {_, corr} -> abs(corr.coefficient) >= params.min_confidence end)
      |> Enum.sort_by(fn {_, corr} -> abs(corr.coefficient) end, :desc)
      |> Enum.take(params.max_patterns)

    %{
      correlations: Map.new(significant_correlations),
      strongest_factors: identify_strongest_factors(significant_correlations),
      correlation_insights: generate_correlation_insights(significant_correlations)
    }
  end

  defp learn_predictions(experiences, params) do
    # Analyze temporal patterns
    time_series = build_time_series(experiences)

    # Identify trends
    trends = identify_trends(time_series)

    # Build predictive patterns
    predictions = build_predictions(trends, params.context)

    %{
      trends: trends,
      predictions: Enum.take(predictions, params.max_patterns),
      prediction_accuracy: estimate_prediction_accuracy(predictions, experiences),
      time_patterns: extract_time_patterns(experiences)
    }
  end

  defp learn_optimizations(experiences, params) do
    # Analyze performance metrics
    performance_data = extract_performance_metrics(experiences)

    # Identify optimization opportunities
    optimizations = find_optimization_opportunities(performance_data, params)

    # Calculate potential improvements
    improvements = calculate_potential_improvements(optimizations, performance_data)

    %{
      current_performance: summarize_performance(performance_data),
      optimization_opportunities: Enum.take(optimizations, params.max_patterns),
      potential_improvements: improvements,
      recommended_actions: generate_optimization_actions(optimizations)
    }
  end

  defp get_outcome_category(experience) do
    cond do
      experience[:result][:success] == true -> :success
      experience[:result][:success] == false -> :failure
      experience[:goal][:status] == :completed -> :success
      experience[:goal][:status] == :failed -> :failure
      true -> :neutral
    end
  end

  defp extract_success_patterns(success_experiences, _params) do
    success_experiences
    |> Enum.flat_map(&extract_experience_features/1)
    |> Enum.frequencies()
    |> Enum.map(fn {feature, count} ->
      %{
        feature: feature,
        frequency: count / length(success_experiences),
        occurrences: count,
        pattern_type: :success_indicator
      }
    end)
    |> Enum.sort_by(& &1.frequency, :desc)
  end

  defp extract_failure_patterns(failure_experiences, _params) do
    failure_experiences
    |> Enum.flat_map(&extract_experience_features/1)
    |> Enum.frequencies()
    |> Enum.map(fn {feature, count} ->
      %{
        feature: feature,
        frequency: count / length(failure_experiences),
        occurrences: count,
        pattern_type: :failure_indicator
      }
    end)
    |> Enum.sort_by(& &1.frequency, :desc)
  end

  defp extract_experience_features(experience) do
    try do
      features = []

      # Extract goal type
      features = if goal = experience[:goal] do
        [{:goal_type, goal[:type]} | features]
      else
        features
      end

      # Extract action type
      features = if action = experience[:action] do
        [{:action_type, action} | features]
      else
        features
      end

      # Extract context features
      features = if context = experience[:context] do
        extract_context_features(context) ++ features
      else
        features
      end

      # Extract result features
      features = if result = experience[:result] do
        extract_result_features(result) ++ features
      else
        features
      end

      features
    rescue
      _ -> []
    end
  end

  defp extract_context_features(context) do
    context
    |> Enum.map(fn {k, v} ->
      {:context, {k, categorize_value(v)}}
    end)
    |> Enum.take(5)  # Limit context features
  end

  defp extract_result_features(result) do
    features = []

    # Duration category
    features = if duration = result[:duration_ms] do
      [{:duration_category, categorize_duration(duration)} | features]
    else
      features
    end

    # Error type
    features = if error = result[:error] || result[:reason] do
      [{:error_type, categorize_error(error)} | features]
    else
      features
    end

    features
  end

  defp categorize_value(value) when is_number(value) do
    cond do
      value < 0 -> :negative
      value == 0 -> :zero
      value < 10 -> :low
      value < 100 -> :medium
      true -> :high
    end
  end
  defp categorize_value(value) when is_boolean(value), do: value
  defp categorize_value(value) when is_atom(value), do: value
  defp categorize_value(_), do: :other

  defp categorize_duration(ms) do
    cond do
      ms < 100 -> :instant
      ms < 1000 -> :fast
      ms < 5000 -> :normal
      ms < 10_000 -> :slow
      true -> :very_slow
    end
  end

  defp categorize_error({:timeout, _}), do: :timeout
  defp categorize_error({:error, :rate_limit}), do: :rate_limit
  defp categorize_error({:error, {:http_error, code}}) when code >= 500, do: :server_error
  defp categorize_error({:error, {:http_error, code}}) when code >= 400, do: :client_error
  defp categorize_error(_), do: :unknown_error

  defp calculate_pattern_confidence(success_patterns, failure_patterns) do
    # Higher confidence when patterns are distinct between success and failure
    success_features = MapSet.new(success_patterns, & &1.feature)
    failure_features = MapSet.new(failure_patterns, & &1.feature)

    overlap = MapSet.intersection(success_features, failure_features)
    total = MapSet.union(success_features, failure_features)

    if MapSet.size(total) > 0 do
      1.0 - (MapSet.size(overlap) / MapSet.size(total))
    else
      0.0
    end
  end

  defp generate_pattern_recommendations(success_patterns, failure_patterns) do
    recommendations = []

    # Recommend following success patterns
    top_success = Enum.take(success_patterns, 3)
    recommendations = if length(top_success) > 0 do
      ["Prioritize scenarios with: " <>
       Enum.map_join(top_success, ", ", fn p -> inspect(p.feature) end) | recommendations]
    else
      recommendations
    end

    # Recommend avoiding failure patterns
    top_failure = Enum.take(failure_patterns, 3)
    recommendations = if length(top_failure) > 0 do
      ["Avoid scenarios with: " <>
       Enum.map_join(top_failure, ", ", fn p -> inspect(p.feature) end) | recommendations]
    else
      recommendations
    end

    recommendations
  end

  defp extract_features(experiences) do
    experiences
    |> Enum.map(&extract_experience_features/1)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp calculate_correlations(features, experiences) do
    features
    |> Enum.map(fn feature ->
      correlation = calculate_feature_correlation(feature, experiences)
      {feature, correlation}
    end)
    |> Map.new()
  end

  defp calculate_feature_correlation(feature, experiences) do
    # Simplified correlation calculation
    with_feature = Enum.filter(experiences, fn exp ->
      feature in extract_experience_features(exp)
    end)

    success_with = Enum.count(with_feature, fn exp ->
      get_outcome_category(exp) == :success
    end)

    total_with = length(with_feature)

    if total_with > 0 do
      %{
        coefficient: (success_with / total_with) - 0.5,  # -0.5 to 0.5 range
        sample_size: total_with,
        success_rate: success_with / total_with
      }
    else
      %{coefficient: 0.0, sample_size: 0, success_rate: 0.0}
    end
  end

  defp identify_strongest_factors(correlations) do
    correlations
    |> Enum.take(5)
    |> Enum.map(fn {feature, corr} ->
      %{
        feature: feature,
        impact: if(corr.coefficient > 0, do: :positive, else: :negative),
        strength: abs(corr.coefficient)
      }
    end)
  end

  defp generate_correlation_insights(correlations) do
    correlations
    |> Enum.map(fn {feature, corr} ->
      impact = if corr.coefficient > 0, do: "increases", else: "decreases"
      "#{inspect(feature)} #{impact} success rate by #{Float.round(abs(corr.coefficient) * 100, 1)}%"
    end)
  end

  defp build_time_series(experiences) do
    experiences
    |> Enum.sort_by(& &1[:timestamp])
    |> Enum.map(fn exp ->
      %{
        timestamp: exp[:timestamp],
        outcome: get_outcome_category(exp),
        metrics: extract_metrics(exp)
      }
    end)
  end

  defp extract_metrics(experience) do
    %{
      duration_ms: experience[:result][:duration_ms] || 0,
      success: experience[:result][:success] || false
    }
  end

  defp identify_trends(time_series) do
    # Simple trend identification
    if length(time_series) < 3 do
      %{trend_type: :insufficient_data}
    else
      success_rates = calculate_windowed_success_rates(time_series)

      cond do
        increasing_trend?(success_rates) -> %{trend_type: :improving, confidence: 0.8}
        decreasing_trend?(success_rates) -> %{trend_type: :degrading, confidence: 0.8}
        true -> %{trend_type: :stable, confidence: 0.6}
      end
    end
  end

  defp calculate_windowed_success_rates(time_series) do
    time_series
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.map(fn window ->
      success_count = Enum.count(window, & &1.outcome == :success)
      success_count / length(window)
    end)
  end

  defp increasing_trend?(rates) when length(rates) < 2, do: false
  defp increasing_trend?(rates) do
    rates
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> b >= a end)
  end

  defp decreasing_trend?(rates) when length(rates) < 2, do: false
  defp decreasing_trend?(rates) do
    rates
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> b <= a end)
  end

  defp build_predictions(trends, _context) do
    case trends.trend_type do
      :improving ->
        [%{
          prediction: "Performance will continue to improve",
          confidence: trends.confidence,
          recommendation: "Maintain current strategy"
        }]

      :degrading ->
        [%{
          prediction: "Performance degradation likely to continue",
          confidence: trends.confidence,
          recommendation: "Implement corrective measures"
        }]

      :stable ->
        [%{
          prediction: "Performance will remain stable",
          confidence: trends.confidence,
          recommendation: "Consider optimization opportunities"
        }]

      _ ->
        []
    end
  end

  defp estimate_prediction_accuracy(_predictions, _experiences) do
    # Placeholder - would need historical predictions to validate
    0.75
  end

  defp extract_time_patterns(experiences) do
    experiences
    |> Enum.group_by(fn exp ->
      if ts = exp[:timestamp] do
        Date.day_of_week(DateTime.to_date(ts))
      else
        :unknown
      end
    end)
    |> Enum.map(fn {day, exps} ->
      success_rate = calculate_success_rate(exps)
      {day, success_rate}
    end)
    |> Map.new()
  end

  defp calculate_success_rate(experiences) do
    total = length(experiences)
    if total > 0 do
      success = Enum.count(experiences, & get_outcome_category(&1) == :success)
      success / total
    else
      0.0
    end
  end

  defp extract_performance_metrics(experiences) do
    experiences
    |> Enum.map(fn exp ->
      %{
        duration_ms: exp[:result][:duration_ms] || 0,
        success: get_outcome_category(exp) == :success,
        timestamp: exp[:timestamp],
        action: exp[:action]
      }
    end)
  end

  defp find_optimization_opportunities(performance_data, _params) do
    opportunities = []

    # Find slow operations
    avg_duration = calculate_average_duration(performance_data)
    slow_actions = find_slow_actions(performance_data, avg_duration)

    opportunities = if length(slow_actions) > 0 do
      [%{
        type: :performance,
        description: "Optimize slow actions",
        targets: slow_actions,
        potential_improvement: "30-50% reduction in response time"
      } | opportunities]
    else
      opportunities
    end

    # Find high failure rate actions
    high_failure_actions = find_high_failure_actions(performance_data)

    opportunities = if length(high_failure_actions) > 0 do
      [%{
        type: :reliability,
        description: "Improve reliability of error-prone actions",
        targets: high_failure_actions,
        potential_improvement: "Reduce failure rate by 50%"
      } | opportunities]
    else
      opportunities
    end

    opportunities
  end

  defp calculate_average_duration(performance_data) do
    durations = Enum.map(performance_data, & &1.duration_ms)
    if length(durations) > 0 do
      Enum.sum(durations) / length(durations)
    else
      0
    end
  end

  defp find_slow_actions(performance_data, avg_duration) do
    performance_data
    |> Enum.group_by(& &1.action)
    |> Enum.map(fn {action, data} ->
      avg_action_duration = calculate_average_duration(data)
      {action, avg_action_duration}
    end)
    |> Enum.filter(fn {_, duration} -> duration > avg_duration * 1.5 end)
    |> Enum.map(fn {action, _} -> action end)
  end

  defp find_high_failure_actions(performance_data) do
    performance_data
    |> Enum.group_by(& &1.action)
    |> Enum.map(fn {action, data} ->
      failure_rate = 1.0 - calculate_success_rate(data)
      {action, failure_rate}
    end)
    |> Enum.filter(fn {_, rate} -> rate > 0.2 end)
    |> Enum.map(fn {action, _} -> action end)
  end

  defp calculate_potential_improvements(optimizations, performance_data) do
    current_metrics = summarize_performance(performance_data)

    %{
      current_success_rate: current_metrics.success_rate,
      potential_success_rate: min(current_metrics.success_rate + 0.15, 0.99),
      current_avg_duration: current_metrics.avg_duration,
      potential_avg_duration: current_metrics.avg_duration * 0.7,
      improvement_areas: Enum.map(optimizations, & &1.type)
    }
  end

  defp summarize_performance(performance_data) do
    total = length(performance_data)
    successful = Enum.count(performance_data, & &1.success)

    %{
      total_operations: total,
      success_rate: if(total > 0, do: successful / total, else: 0),
      avg_duration: calculate_average_duration(performance_data),
      duration_p95: calculate_percentile_duration(performance_data, 0.95)
    }
  end

  defp calculate_percentile_duration(performance_data, percentile) do
    sorted_durations =
      performance_data
      |> Enum.map(& &1.duration_ms)
      |> Enum.sort()

    if length(sorted_durations) > 0 do
      index = round(percentile * (length(sorted_durations) - 1))
      Enum.at(sorted_durations, index)
    else
      0
    end
  end

  defp generate_optimization_actions(optimizations) do
    optimizations
    |> Enum.flat_map(fn opt ->
      case opt.type do
        :performance ->
          ["Implement caching for #{inspect(opt.targets)}",
           "Consider parallel processing",
           "Profile and optimize hot paths"]

        :reliability ->
          ["Add retry logic for #{inspect(opt.targets)}",
           "Implement circuit breakers",
           "Improve error handling"]

        _ ->
          []
      end
    end)
    |> Enum.take(5)
  end

  defp calculate_confidence(insights, experiences) do
    try do
      base_confidence = min(length(experiences) / 100, 1.0) * 0.5

      insight_confidence = case insights do
        %{pattern_confidence: pc} -> pc
        %{prediction_accuracy: pa} -> pa
        %{correlations: corr} when is_map(corr) and map_size(corr) > 0 -> 0.7
        _ -> 0.5
      end

      base_confidence + (insight_confidence * 0.5)
    rescue
      _ -> 0.5  # Default medium confidence on error
    end
  end

  defp identify_applicable_scenarios(insights) do
    scenarios = []

    # Pattern-based scenarios
    scenarios = if patterns = insights[:success_patterns] do
      pattern_scenarios = Enum.map(Enum.take(patterns, 3), fn pattern ->
        "When #{inspect(pattern.feature)} is present"
      end)
      scenarios ++ pattern_scenarios
    else
      scenarios
    end

    # Correlation-based scenarios
    scenarios = if correlations = insights[:strongest_factors] do
      correlation_scenarios = Enum.map(Enum.take(correlations, 3), fn factor ->
        "To #{factor.impact} success rate via #{inspect(factor.feature)}"
      end)
      scenarios ++ correlation_scenarios
    else
      scenarios
    end

    # Optimization scenarios
    scenarios = if opportunities = insights[:optimization_opportunities] do
      opt_scenarios = Enum.map(opportunities, fn opt ->
        "For #{opt.description}"
      end)
      scenarios ++ opt_scenarios
    else
      scenarios
    end

    Enum.uniq(scenarios)
  end

  defp validate_learning_params(params) do
    validations = [
      fn -> validate_params_structure(params) end,
      fn -> validate_experiences(params[:experiences]) end,
      fn -> validate_learning_type(params[:learning_type]) end,
      fn -> validate_min_confidence(params[:min_confidence]) end,
      fn -> validate_max_patterns(params[:max_patterns]) end
    ]

    Enum.reduce_while(validations, :ok, fn validation_fn, :ok ->
      case validation_fn.() do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_params_structure(params) when is_map(params), do: :ok
  defp validate_params_structure(_), do: {:error, :invalid_params}

  defp validate_experiences(experiences) when is_list(experiences), do: :ok
  defp validate_experiences(_), do: {:error, :invalid_experiences}

  defp validate_learning_type(type) when is_atom(type) do
    if type in [:pattern, :correlation, :prediction, :optimization] do
      :ok
    else
      {:error, :unknown_learning_type}
    end
  end
  defp validate_learning_type(_), do: {:error, :invalid_learning_type}

  defp validate_min_confidence(confidence) when is_float(confidence) do
    if confidence >= 0 and confidence <= 1 do
      :ok
    else
      {:error, :invalid_min_confidence}
    end
  end
  defp validate_min_confidence(_), do: {:error, :invalid_min_confidence}

  defp validate_max_patterns(patterns) when is_integer(patterns) do
    if patterns > 0 do
      :ok
    else
      {:error, :invalid_max_patterns}
    end
  end
  defp validate_max_patterns(_), do: {:error, :invalid_max_patterns}
end
