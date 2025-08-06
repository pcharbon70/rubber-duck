defmodule RubberDuck.Skills.LearningSkill do
  @moduledoc """
  Skill for cross-agent experience tracking and learning optimization.

  This skill provides a unified learning system that tracks experiences across
  all agents, identifies successful patterns, and optimizes agent behaviors
  based on outcomes. It enables continuous improvement through feedback loops
  and adaptation strategies.
  """

  use Jido.Skill,
    name: "learning",
    description: "Tracks experiences and optimizes agent behaviors through learning",
    category: "meta",
    tags: ["learning", "experience", "optimization", "adaptation", "feedback"],
    vsn: "1.0.0",
    opts_key: :learning,
    signal_patterns: [
      "learning.experience.*",
      "learning.feedback.*",
      "learning.pattern.*",
      "learning.optimize.*",
      "learning.share.*"
    ],
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

  @impl true
  def handle_signal(%{type: "learning.experience.record"} = signal, state) do
    agent_id = signal.data.agent_id
    experience = build_experience(signal.data)

    # Record the experience
    updated_state =
      update_in(state, [:experiences, agent_id], fn experiences ->
        experiences = experiences || []
        [experience | Enum.take(experiences, state.opts.experience_window - 1)]
      end)

    # Update experience statistics
    updated_state = update_experience_stats(updated_state, agent_id, experience)

    # Check for emerging patterns
    patterns =
      if length(get_in(updated_state, [:experiences, agent_id]) || []) >= 10 do
        detect_experience_patterns(updated_state, agent_id)
      else
        []
      end

    # Store patterns if found
    updated_state =
      if length(patterns) > 0 do
        put_in(updated_state, [:patterns, agent_id], patterns)
      else
        updated_state
      end

    {:ok, %{recorded: true, patterns_detected: length(patterns)}, updated_state}
  end

  @impl true
  def handle_signal(%{type: "learning.feedback.process"} = signal, state) do
    agent_id = signal.data.agent_id
    feedback = signal.data.feedback
    experience_id = signal.data.experience_id

    # Find the related experience
    experience = find_experience(state, agent_id, experience_id)

    if experience do
      # Process the feedback
      learning_update = process_feedback(experience, feedback, state.opts.learning_rate)

      # Update agent's learning model
      updated_state =
        update_in(state, [:learning_models, agent_id], fn model ->
          apply_learning_update(model || initialize_learning_model(), learning_update)
        end)

      # Generate optimization suggestions
      optimizations = generate_optimizations(updated_state, agent_id)

      # Emit optimization signal if significant improvements found
      if length(optimizations) > 0 && optimizations |> List.first() |> Map.get(:improvement) > 0.1 do
        emit_signal("learning.optimization.available", %{
          agent_id: agent_id,
          optimizations: optimizations
        })
      end

      {:ok, %{processed: true, optimizations: optimizations}, updated_state}
    else
      {:ok, %{processed: false, reason: :experience_not_found}, state}
    end
  end

  @impl true
  def handle_signal(%{type: "learning.pattern.analyze"} = signal, state) do
    agent_id = signal.data.agent_id
    analysis_depth = signal.data[:depth] || :normal

    # Analyze patterns across agent experiences
    patterns = analyze_agent_patterns(state, agent_id, analysis_depth)

    # Identify successful patterns
    successful_patterns =
      patterns
      |> Enum.filter(&(&1.success_rate > state.opts.pattern_threshold))
      |> Enum.sort_by(& &1.success_rate, :desc)

    # Identify failure patterns
    failure_patterns =
      patterns
      |> Enum.filter(&(&1.failure_rate > state.opts.pattern_threshold))
      |> Enum.sort_by(& &1.failure_rate, :desc)

    # Generate insights
    insights = generate_pattern_insights(successful_patterns, failure_patterns)

    # Store analyzed patterns
    updated_state =
      put_in(state, [:analyzed_patterns, agent_id], %{
        successful: successful_patterns,
        failures: failure_patterns,
        insights: insights,
        analyzed_at: DateTime.utc_now()
      })

    {:ok,
     %{
       successful_patterns: length(successful_patterns),
       failure_patterns: length(failure_patterns),
       insights: insights
     }, updated_state}
  end

  @impl true
  def handle_signal(%{type: "learning.optimize.agent"} = signal, state) do
    agent_id = signal.data.agent_id
    optimization_goals = signal.data[:goals] || [:performance, :accuracy, :efficiency]

    # Get agent's learning model
    model = get_in(state, [:learning_models, agent_id]) || initialize_learning_model()

    # Optimize for each goal
    optimizations =
      Enum.map(optimization_goals, fn goal ->
        optimize_for_goal(model, goal, state)
      end)

    # Apply optimizations to model
    optimized_model =
      Enum.reduce(optimizations, model, fn opt, acc_model ->
        apply_optimization(acc_model, opt)
      end)

    # Calculate improvement metrics
    improvements = calculate_improvements(model, optimized_model)

    # Update state with optimized model
    updated_state = put_in(state, [:learning_models, agent_id], optimized_model)

    # Track optimization history
    updated_state =
      update_in(updated_state, [:optimization_history, agent_id], fn history ->
        optimization_record = %{
          timestamp: DateTime.utc_now(),
          goals: optimization_goals,
          improvements: improvements,
          applied: true
        }

        [optimization_record | Enum.take(history || [], 99)]
      end)

    {:ok, %{optimized: true, improvements: improvements}, updated_state}
  end

  @impl true
  def handle_signal(%{type: "learning.share.knowledge"} = signal, state) do
    source_agent = signal.data.source_agent
    target_agents = signal.data.target_agents || :all
    knowledge_type = signal.data[:knowledge_type] || :patterns

    if state.opts.cross_agent_learning do
      # Extract sharable knowledge from source agent
      knowledge = extract_sharable_knowledge(state, source_agent, knowledge_type)

      # Determine target agents
      targets =
        case target_agents do
          :all -> Map.keys(state.learning_models) -- [source_agent]
          list when is_list(list) -> list
          _ -> []
        end

      # Share knowledge with target agents
      updated_state =
        Enum.reduce(targets, state, fn target_agent, acc_state ->
          integrate_shared_knowledge(acc_state, target_agent, knowledge, source_agent)
        end)

      # Track knowledge sharing
      updated_state =
        update_in(updated_state, [:knowledge_sharing_log], fn log ->
          share_record = %{
            timestamp: DateTime.utc_now(),
            source: source_agent,
            targets: targets,
            knowledge_type: knowledge_type,
            items_shared: map_size(knowledge)
          }

          [share_record | Enum.take(log || [], 999)]
        end)

      {:ok,
       %{
         shared: true,
         targets: length(targets),
         knowledge_items: map_size(knowledge)
       }, updated_state}
    else
      {:ok, %{shared: false, reason: :cross_agent_learning_disabled}, state}
    end
  end

  @impl true
  def handle_signal(%{type: "learning.experience.query"} = signal, state) do
    agent_id = signal.data.agent_id
    query_params = signal.data.query || %{}

    # Query experiences based on parameters
    experiences = query_experiences(state, agent_id, query_params)

    # Analyze query results
    analysis = analyze_experience_set(experiences)

    {:ok,
     %{
       experiences: experiences,
       count: length(experiences),
       analysis: analysis
     }, state}
  end

  @impl true
  def handle_signal(_signal, state) do
    {:ok, state}
  end

  # Private helper functions

  defp build_experience(data) do
    %{
      id: generate_experience_id(),
      timestamp: DateTime.utc_now(),
      action: data.action,
      context: data.context || %{},
      inputs: data.inputs || %{},
      outputs: data.outputs || %{},
      outcome: data.outcome || :unknown,
      performance_metrics: data.metrics || %{},
      success: determine_success(data),
      tags: data.tags || []
    }
  end

  defp generate_experience_id do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  defp determine_success(data) do
    case data[:outcome] do
      :success -> true
      :failure -> false
      _ -> data[:success] || false
    end
  end

  defp update_experience_stats(state, agent_id, experience) do
    update_in(state, [:statistics, agent_id], fn stats ->
      current_stats =
        stats ||
          %{
            total_experiences: 0,
            successful: 0,
            failed: 0,
            average_performance: 0.0
          }

      total = current_stats.total_experiences + 1

      successful =
        if experience.success, do: current_stats.successful + 1, else: current_stats.successful

      failed = if experience.success, do: current_stats.failed, else: current_stats.failed + 1

      # Update average performance
      perf_score = experience.performance_metrics[:score] || 0.0

      avg_perf =
        (current_stats.average_performance * current_stats.total_experiences + perf_score) / total

      %{
        total_experiences: total,
        successful: successful,
        failed: failed,
        average_performance: avg_perf,
        success_rate: if(total > 0, do: successful / total, else: 0.0)
      }
    end)
  end

  defp detect_experience_patterns(state, agent_id) do
    experiences = get_in(state, [:experiences, agent_id]) || []

    # Group experiences by action
    grouped = Enum.group_by(experiences, & &1.action)

    # Detect patterns for each action
    Enum.flat_map(grouped, fn {action, action_experiences} ->
      if length(action_experiences) >= 3 do
        pattern = analyze_action_pattern(action, action_experiences)

        if pattern.confidence > state.opts.pattern_threshold do
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

  defp find_experience(state, agent_id, experience_id) do
    experiences = get_in(state, [:experiences, agent_id]) || []
    Enum.find(experiences, &(&1.id == experience_id))
  end

  defp process_feedback(experience, feedback, learning_rate) do
    %{
      experience_id: experience.id,
      action: experience.action,
      feedback_type: feedback.type,
      feedback_value: feedback.value,
      adjustment: calculate_adjustment(feedback, learning_rate),
      context_updates: generate_context_updates(experience, feedback),
      weight_updates: calculate_weight_updates(experience, feedback, learning_rate)
    }
  end

  defp calculate_adjustment(feedback, learning_rate) do
    case feedback.type do
      :positive -> learning_rate
      :negative -> -learning_rate
      :neutral -> 0
      :corrective -> feedback.correction_factor * learning_rate
    end
  end

  defp generate_context_updates(experience, feedback) do
    # Generate updates based on feedback to improve future decisions
    %{
      preferred_contexts: if(feedback.type == :positive, do: experience.context, else: %{}),
      avoided_contexts: if(feedback.type == :negative, do: experience.context, else: %{}),
      corrections: feedback[:corrections] || %{}
    }
  end

  defp calculate_weight_updates(experience, feedback, learning_rate) do
    # Calculate weight adjustments for learning model
    base_weight =
      case feedback.type do
        :positive -> 1.0 + learning_rate
        :negative -> 1.0 - learning_rate
        _ -> 1.0
      end

    %{
      action_weight: base_weight,
      context_weights: Map.new(experience.context, fn {k, _v} -> {k, base_weight} end)
    }
  end

  defp initialize_learning_model do
    %{
      version: 1,
      created_at: DateTime.utc_now(),
      action_weights: %{},
      context_weights: %{},
      performance_baseline: 0.5,
      adaptation_rate: 0.1,
      optimization_count: 0
    }
  end

  defp apply_learning_update(model, update) do
    model
    |> update_action_weights(update)
    |> update_context_weights(update)
    |> increment_version()
  end

  defp update_action_weights(model, update) do
    update_in(model, [:action_weights, update.action], fn current ->
      (current || 1.0) * update.weight_updates.action_weight
    end)
  end

  defp update_context_weights(model, update) do
    Enum.reduce(update.weight_updates.context_weights, model, fn {key, weight}, acc ->
      update_in(acc, [:context_weights, key], fn current ->
        (current || 1.0) * weight
      end)
    end)
  end

  defp increment_version(model) do
    Map.update(model, :version, 1, &(&1 + 1))
  end

  defp generate_optimizations(state, agent_id) do
    _model = get_in(state, [:learning_models, agent_id])
    patterns = get_in(state, [:patterns, agent_id]) || []

    optimizations = []

    # Optimize based on successful patterns
    successful_patterns = Enum.filter(patterns, &(&1.success_rate > 0.8))

    optimizations =
      Enum.map(successful_patterns, fn pattern ->
        %{
          type: :reinforce_success,
          action: pattern.action,
          improvement: pattern.success_rate - 0.5,
          suggestion: "Increase frequency of #{pattern.action} in similar contexts"
        }
      end) ++ optimizations

    # Optimize based on failure patterns
    failure_patterns = Enum.filter(patterns, &(&1.success_rate < 0.3))

    failure_opts =
      Enum.map(failure_patterns, fn pattern ->
        %{
          type: :avoid_failure,
          action: pattern.action,
          improvement: 0.5 - pattern.success_rate,
          suggestion: "Reduce or modify #{pattern.action} in current contexts"
        }
      end)

    optimizations ++ failure_opts
  end

  defp analyze_agent_patterns(state, agent_id, depth) do
    experiences = get_in(state, [:experiences, agent_id]) || []

    # Basic pattern analysis
    patterns = extract_basic_patterns(experiences)

    # Add deeper analysis if requested
    patterns =
      if depth in [:deep, :comprehensive] do
        patterns
        |> add_sequence_patterns(experiences)
        |> add_temporal_patterns(experiences)
        |> add_context_correlation_patterns(experiences)
      else
        patterns
      end

    patterns
  end

  defp extract_basic_patterns(experiences) do
    experiences
    |> Enum.group_by(& &1.action)
    |> Enum.map(fn {action, exps} ->
      successful = Enum.count(exps, & &1.success)
      failed = length(exps) - successful

      %{
        type: :action_outcome,
        action: action,
        total_occurrences: length(exps),
        success_rate: if(length(exps) > 0, do: successful / length(exps), else: 0),
        failure_rate: if(length(exps) > 0, do: failed / length(exps), else: 0),
        average_performance:
          average(Enum.map(exps, &(get_in(&1, [:performance_metrics, :score]) || 0)))
      }
    end)
  end

  defp add_sequence_patterns(patterns, experiences) do
    # Analyze action sequences
    sequences =
      experiences
      |> Enum.chunk_every(3, 1, :discard)
      |> Enum.map(fn [a, b, c] ->
        %{
          sequence: [a.action, b.action, c.action],
          success: c.success,
          performance: get_in(c, [:performance_metrics, :score]) || 0
        }
      end)
      |> Enum.group_by(& &1.sequence)
      |> Enum.map(fn {seq, instances} ->
        %{
          type: :sequence,
          sequence: seq,
          occurrences: length(instances),
          success_rate: Enum.count(instances, & &1.success) / length(instances),
          average_performance: average(Enum.map(instances, & &1.performance))
        }
      end)

    patterns ++ sequences
  end

  defp add_temporal_patterns(patterns, _experiences) do
    # Analyze time-based patterns
    patterns
  end

  defp add_context_correlation_patterns(patterns, _experiences) do
    # Analyze context correlations with outcomes
    patterns
  end

  defp generate_pattern_insights(successful_patterns, failure_patterns) do
    insights = []

    # Insights from successful patterns
    insights =
      if length(successful_patterns) > 0 do
        top_success = List.first(successful_patterns)

        [
          "Highest success rate: #{top_success.action} at #{Float.round(top_success.success_rate * 100, 1)}%"
          | insights
        ]
      else
        insights
      end

    # Insights from failure patterns
    insights =
      if length(failure_patterns) > 0 do
        top_failure = List.first(failure_patterns)

        [
          "Highest failure rate: #{top_failure.action} at #{Float.round(top_failure.failure_rate * 100, 1)}%"
          | insights
        ]
      else
        insights
      end

    insights
  end

  defp optimize_for_goal(model, goal, state) do
    case goal do
      :performance ->
        %{
          goal: :performance,
          adjustments: optimize_for_performance(model, state),
          expected_improvement: 0.15
        }

      :accuracy ->
        %{
          goal: :accuracy,
          adjustments: optimize_for_accuracy(model, state),
          expected_improvement: 0.10
        }

      :efficiency ->
        %{
          goal: :efficiency,
          adjustments: optimize_for_efficiency(model, state),
          expected_improvement: 0.20
        }

      _ ->
        %{goal: goal, adjustments: %{}, expected_improvement: 0}
    end
  end

  defp optimize_for_performance(model, _state) do
    # Increase weights for high-performing actions
    %{
      action_weight_multiplier: 1.1,
      context_weight_adjustments: %{},
      adaptation_rate: model.adaptation_rate * 1.05
    }
  end

  defp optimize_for_accuracy(model, _state) do
    # Focus on reducing errors
    %{
      action_weight_multiplier: 1.0,
      context_weight_adjustments: %{},
      adaptation_rate: model.adaptation_rate * 0.95
    }
  end

  defp optimize_for_efficiency(model, _state) do
    # Optimize for speed and resource usage
    %{
      action_weight_multiplier: 0.95,
      context_weight_adjustments: %{},
      adaptation_rate: model.adaptation_rate * 1.1
    }
  end

  defp apply_optimization(model, optimization) do
    model
    |> Map.update(:optimization_count, 1, &(&1 + 1))
    |> Map.put(:last_optimization, DateTime.utc_now())
    |> Map.put(:last_optimization_goal, optimization.goal)
  end

  defp calculate_improvements(old_model, new_model) do
    %{
      version_delta: new_model.version - old_model.version,
      optimization_count: new_model.optimization_count - old_model.optimization_count,
      estimated_performance_gain: 0.1
    }
  end

  defp extract_sharable_knowledge(state, source_agent, knowledge_type) do
    case knowledge_type do
      :patterns ->
        Map.get(state, :patterns, %{})[source_agent] || %{}

      :experiences ->
        # Share only successful experiences
        experiences = get_in(state, [:experiences, source_agent]) || []

        experiences
        |> Enum.filter(& &1.success)
        |> Enum.take(10)
        |> Map.new(fn exp -> {exp.id, exp} end)

      :model ->
        # Share model weights
        model = get_in(state, [:learning_models, source_agent])
        if model, do: %{model: model}, else: %{}

      _ ->
        %{}
    end
  end

  defp integrate_shared_knowledge(state, target_agent, knowledge, source_agent) do
    # Integrate knowledge with attribution to source
    update_in(state, [:shared_knowledge, target_agent], fn current ->
      current = current || %{}

      Map.put(current, source_agent, %{
        knowledge: knowledge,
        received_at: DateTime.utc_now()
      })
    end)
  end

  defp query_experiences(state, agent_id, query_params) do
    experiences = get_in(state, [:experiences, agent_id]) || []

    experiences
    |> filter_by_success(query_params[:success])
    |> filter_by_action(query_params[:action])
    |> filter_by_time_range(query_params[:from], query_params[:to])
    |> Enum.take(query_params[:limit] || 100)
  end

  defp filter_by_success(experiences, nil), do: experiences

  defp filter_by_success(experiences, success) do
    Enum.filter(experiences, &(&1.success == success))
  end

  defp filter_by_action(experiences, nil), do: experiences

  defp filter_by_action(experiences, action) do
    Enum.filter(experiences, &(&1.action == action))
  end

  defp filter_by_time_range(experiences, nil, nil), do: experiences

  defp filter_by_time_range(experiences, from, to) do
    Enum.filter(experiences, fn exp ->
      (from == nil or DateTime.compare(exp.timestamp, from) != :lt) and
        (to == nil or DateTime.compare(exp.timestamp, to) != :gt)
    end)
  end

  defp analyze_experience_set(experiences) do
    if length(experiences) > 0 do
      %{
        total: length(experiences),
        successful: Enum.count(experiences, & &1.success),
        failed: Enum.count(experiences, &(not &1.success)),
        average_performance:
          average(Enum.map(experiences, &(get_in(&1, [:performance_metrics, :score]) || 0))),
        actions: experiences |> Enum.map(& &1.action) |> Enum.uniq()
      }
    else
      %{total: 0, successful: 0, failed: 0, average_performance: 0, actions: []}
    end
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

  defp emit_signal(type, data) do
    # In a real implementation, this would emit through the Jido signal system
    Logger.debug("Emitting signal: #{type} with data: #{inspect(data)}")
    :ok
  end
end
