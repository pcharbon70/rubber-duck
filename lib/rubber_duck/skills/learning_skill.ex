defmodule RubberDuck.Skills.LearningSkill do
  @moduledoc """
  Skill for cross-agent experience tracking and learning optimization.

  This skill provides a unified learning system that tracks experiences across
  all agents, identifies successful patterns, and optimizes agent behaviors
  based on outcomes. It enables continuous improvement through feedback loops
  and adaptation strategies.

  Uses typed messages exclusively for all learning operations.
  """

  use RubberDuck.Skills.Base,
    name: "learning",
    description: "Tracks experiences and optimizes agent behaviors through learning",
    category: "meta",
    tags: ["learning", "experience", "optimization", "adaptation", "feedback"],
    vsn: "2.0.0",
    opts_key: :learning,
    opts_schema: [
      enabled: [type: :boolean, default: true],
      learning_rate: [type: :float, default: 0.1],
      experience_window: [type: :pos_integer, default: 1000],
      pattern_threshold: [type: :float, default: 0.7],
      optimization_interval: [type: :pos_integer, default: 3600],
      cross_agent_learning: [type: :boolean, default: true],
      persistence_enabled: [type: :boolean, default: true]
    ]

  require Logger

  alias RubberDuck.Messages.Learning.{
    RecordExperience,
    ProcessFeedback,
    AnalyzePattern,
    OptimizeAgent
  }

  # Typed message handlers

  @doc """
  Handle typed RecordExperience message
  """
  def handle_record_experience(%RecordExperience{} = msg, context) do
    state = context[:state] || %{experiences: %{}, patterns: %{}, learning_models: %{}}

    experience = %{
      id: generate_experience_id(),
      timestamp: DateTime.utc_now(),
      agent_id: msg.agent_id,
      action: msg.action,
      outcome: msg.outcome,
      context: msg.context,
      performance_metrics: msg.metrics,
      success: msg.success,
      tags: msg.tags
    }

    # Record the experience
    experiences = Map.get(state.experiences, msg.agent_id, [])
    window_size = Map.get(state, :experience_window, 1000)
    updated_experiences = [experience | Enum.take(experiences, window_size - 1)]

    # Detect patterns if enough experiences
    patterns =
      if length(updated_experiences) >= 10 do
        detect_experience_patterns(
          %{experiences: %{msg.agent_id => updated_experiences}},
          msg.agent_id
        )
      else
        []
      end

    result = %{
      recorded: true,
      experience_id: experience.id,
      patterns_detected: length(patterns),
      patterns: patterns
    }

    {:ok, result}
  end

  @doc """
  Handle typed ProcessFeedback message
  """
  def handle_process_feedback(%ProcessFeedback{} = msg, context) do
    state = context[:state] || %{}
    learning_rate = get_in(state, [:opts, :learning_rate]) || 0.1

    # Process the feedback
    learning_update = %{
      agent_id: msg.agent_id,
      experience_id: msg.experience_id,
      feedback_type: msg.feedback.type,
      score: msg.score,
      adjustments: calculate_adjustments(msg.feedback.type, msg.score, learning_rate),
      metadata: msg.metadata
    }

    # Generate optimization suggestions based on feedback
    optimizations =
      if msg.score < 0.5 do
        [
          %{
            type: :parameter_adjustment,
            parameter: msg.feedback.type,
            suggested_change: learning_update.adjustments,
            improvement: (1.0 - msg.score) * learning_rate
          }
        ]
      else
        []
      end

    result = %{
      processed: true,
      learning_update: learning_update,
      optimizations: optimizations,
      improvement_potential: calculate_improvement_potential(msg.score, learning_rate)
    }

    {:ok, result}
  end

  @doc """
  Handle typed AnalyzePattern message
  """
  def handle_analyze_pattern(%AnalyzePattern{} = msg, context) do
    state = context[:state] || %{}

    # Get experiences for the agent
    experiences = get_in(state, [:experiences, msg.agent_id]) || []

    # Filter by pattern type if specified
    filtered_experiences =
      case hd(msg.pattern_types || []) do
        :success -> Enum.filter(experiences, & &1[:success])
        :failure -> Enum.filter(experiences, &(!&1[:success]))
        _ -> experiences
      end

    # Analyze patterns
    patterns =
      filtered_experiences
      |> group_by_action()
      |> Enum.map(fn {action, exps} ->
        %{
          action: action,
          frequency: length(exps),
          success_rate: calculate_success_rate(exps),
          common_context: extract_common_context(exps),
          performance_trend: calculate_performance_trend(exps)
        }
      end)
      |> Enum.filter(&(&1.frequency >= (msg.min_occurrences || 3)))

    result = %{
      agent_id: msg.agent_id,
      patterns_found: length(patterns),
      patterns: patterns,
      analysis_depth: length(filtered_experiences),
      confidence: calculate_pattern_confidence(patterns)
    }

    {:ok, result}
  end

  @doc """
  Handle typed OptimizeAgent message
  """
  def handle_optimize_agent(%OptimizeAgent{} = msg, context) do
    state = context[:state] || %{}

    # Get agent's learning model and experiences
    learning_model = get_in(state, [:learning_models, msg.agent_id]) || %{}
    experiences = get_in(state, [:experiences, msg.agent_id]) || []
    patterns = get_in(state, [:patterns, msg.agent_id]) || []

    # Generate optimization strategies
    strategies = []

    # Add performance-based optimizations
    strategies =
      if recent_performance_declining?(experiences) do
        [
          %{
            type: :performance_recovery,
            actions: ["increase_exploration", "reset_parameters"],
            priority: :high
          }
          | strategies
        ]
      else
        strategies
      end

    # Add pattern-based optimizations  
    strategies =
      patterns
      |> Enum.filter(&(&1[:success_rate] > 0.7))
      |> Enum.map(fn pattern ->
        %{
          type: :reinforce_pattern,
          pattern: pattern.action,
          priority: :medium,
          expected_improvement: pattern.success_rate * 0.1
        }
      end)
      |> Kernel.++(strategies)

    # Apply target metrics if provided
    strategies =
      if msg.target_metrics do
        metric_strategies = generate_metric_strategies(learning_model, msg.target_metrics)
        strategies ++ metric_strategies
      else
        strategies
      end

    result = %{
      agent_id: msg.agent_id,
      optimization_strategies: strategies,
      estimated_improvement: calculate_total_improvement(strategies),
      current_performance: calculate_current_performance(experiences),
      recommendations: generate_recommendations(strategies)
    }

    {:ok, result}
  end

  # Private helper functions

  defp generate_experience_id do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  defp detect_experience_patterns(state, agent_id) do
    experiences = get_in(state, [:experiences, agent_id]) || []
    pattern_threshold = get_in(state, [:opts, :pattern_threshold]) || 0.7

    # Group experiences by action
    grouped = Enum.group_by(experiences, & &1.action)

    # Detect patterns for each action
    Enum.flat_map(grouped, fn {action, action_experiences} ->
      if length(action_experiences) >= 3 do
        pattern = analyze_action_pattern(action, action_experiences)

        if pattern.confidence > pattern_threshold do
          [pattern]
        else
          []
        end
      else
        []
      end
    end)
  end

  defp analyze_action_pattern(action, experiences) do
    successful = Enum.count(experiences, & &1.success)
    total = length(experiences)

    # Analyze context patterns
    context_patterns =
      experiences
      |> Enum.map(& &1.context)
      |> find_common_patterns()

    # Analyze performance trends
    perf_scores =
      experiences
      |> Enum.map(&(get_in(&1, [:performance_metrics, :score]) || 0))

    %{
      action: action,
      occurrences: total,
      success_rate: if(total > 0, do: successful / total, else: 0),
      average_performance: average(perf_scores),
      performance_trend: calculate_trend(perf_scores),
      context_patterns: context_patterns,
      confidence: min(1.0, total / 10.0),
      detected_at: DateTime.utc_now()
    }
  end

  defp find_common_patterns(contexts) do
    # Find common keys and values in contexts
    common_keys =
      contexts
      |> Enum.map(&Map.keys/1)
      |> Enum.reduce(&MapSet.intersection(MapSet.new(&1), MapSet.new(&2)))
      |> MapSet.to_list()

    Enum.map(common_keys, fn key ->
      values = Enum.map(contexts, & &1[key])

      %{
        key: key,
        common_value: mode(values),
        frequency: frequency_of_mode(values)
      }
    end)
  end

  defp average([]), do: 0
  defp average(list), do: Enum.sum(list) / length(list)

  defp calculate_trend(values) when length(values) < 2, do: :insufficient_data

  defp calculate_trend(values) do
    first_half = Enum.take(values, div(length(values), 2))
    second_half = Enum.drop(values, div(length(values), 2))

    first_avg = average(first_half)
    second_avg = average(second_half)

    cond do
      second_avg > first_avg * 1.1 -> :improving
      second_avg < first_avg * 0.9 -> :declining
      true -> :stable
    end
  end

  defp mode(list) do
    list
    |> Enum.frequencies()
    |> Enum.max_by(fn {_, count} -> count end, fn -> {nil, 0} end)
    |> elem(0)
  end

  defp frequency_of_mode(list) do
    frequencies = Enum.frequencies(list)
    max_count = frequencies |> Map.values() |> Enum.max(fn -> 0 end)
    if length(list) > 0, do: max_count / length(list), else: 0
  end

  # Additional helper functions for typed messages

  defp calculate_adjustments(feedback_type, score, learning_rate) do
    # Calculate parameter adjustments based on feedback
    adjustment_factor = (1.0 - score) * learning_rate

    case feedback_type do
      :performance -> %{speed: adjustment_factor, accuracy: adjustment_factor * 0.5}
      :accuracy -> %{threshold: -adjustment_factor, validation: adjustment_factor}
      :efficiency -> %{resource_usage: -adjustment_factor, optimization: adjustment_factor}
      _ -> %{general: adjustment_factor}
    end
  end

  defp calculate_improvement_potential(score, learning_rate) do
    # Estimate potential improvement based on current score
    (1.0 - score) * learning_rate * 100
  end

  defp group_by_action(experiences) do
    Enum.group_by(experiences, & &1[:action])
  end

  defp calculate_success_rate(experiences) do
    successful = Enum.count(experiences, & &1[:success])
    total = length(experiences)
    if total > 0, do: successful / total, else: 0.0
  end

  defp extract_common_context(experiences) do
    # Extract common context patterns from experiences
    experiences
    |> Enum.map(& &1[:context])
    |> Enum.filter(& &1)
    |> find_common_elements()
  end

  defp find_common_elements([]), do: %{}

  defp find_common_elements(contexts) do
    # Find keys that appear in all contexts
    first = List.first(contexts)

    if first do
      first
      |> Enum.filter(fn {key, value} ->
        Enum.all?(contexts, fn ctx ->
          Map.get(ctx, key) == value
        end)
      end)
      |> Enum.into(%{})
    else
      %{}
    end
  end

  defp calculate_performance_trend(experiences) do
    # Calculate performance trend over time
    sorted = Enum.sort_by(experiences, & &1[:timestamp])

    if length(sorted) >= 2 do
      recent = Enum.take(sorted, -5)
      older = Enum.take(sorted, 5)

      recent_perf = calculate_average_performance(recent)
      older_perf = calculate_average_performance(older)

      cond do
        recent_perf > older_perf * 1.1 -> :improving
        recent_perf < older_perf * 0.9 -> :declining
        true -> :stable
      end
    else
      :insufficient_data
    end
  end

  defp calculate_average_performance(experiences) do
    metrics = experiences |> Enum.map(& &1[:performance_metrics]) |> Enum.filter(& &1)

    if length(metrics) > 0 do
      # Simple average of all numeric metrics
      metrics
      |> Enum.flat_map(&Map.values/1)
      |> Enum.filter(&is_number/1)
      |> average()
    else
      0.5
    end
  end

  defp calculate_pattern_confidence(patterns) do
    if Enum.empty?(patterns) do
      0.0
    else
      # Confidence based on pattern frequency and success rate
      patterns
      |> Enum.map(fn p -> p.frequency * p.success_rate end)
      |> average()
      |> min(1.0)
    end
  end

  defp recent_performance_declining?(experiences) do
    calculate_performance_trend(experiences) == :declining
  end

  defp generate_metric_strategies(_model, target_metrics) do
    # Generate strategies to achieve target metrics
    Enum.map(target_metrics, fn {metric, target} ->
      %{
        type: :metric_optimization,
        metric: metric,
        target: target,
        priority: :high,
        expected_improvement: 0.15
      }
    end)
  end

  defp calculate_total_improvement(strategies) do
    strategies
    |> Enum.map(&(&1[:expected_improvement] || 0.05))
    |> Enum.sum()
    |> min(1.0)
  end

  defp calculate_current_performance(experiences) do
    recent = Enum.take(experiences, 20)
    calculate_average_performance(recent)
  end

  defp generate_recommendations(strategies) do
    strategies
    |> Enum.sort_by(& &1[:priority])
    |> Enum.take(3)
    |> Enum.map(fn strategy ->
      "Apply #{strategy.type} optimization#{if strategy[:pattern], do: " for #{strategy.pattern}", else: ""}"
    end)
  end
end