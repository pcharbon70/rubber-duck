defmodule RubberDuck.Skills.UserManagementSkill do
  @moduledoc """
  Skill for managing user sessions and learning from user behavior patterns.

  This skill provides autonomous session management, behavioral learning,
  preference adaptation, and proactive assistance suggestions based on
  user interaction patterns.
  """

  use Jido.Skill,
    name: "user_management",
    description: "Manages user sessions and learns from behavioral patterns",
    category: "user",
    tags: ["user", "session", "behavior", "learning", "preferences"],
    vsn: "1.0.0",
    opts_key: :user_management,
    signal_patterns: [
      "user.session.*",
      "user.behavior.*",
      "user.preference.*",
      "user.interaction.*",
      "user.pattern.*"
    ],
    opts_schema: [
      session_timeout: [type: :pos_integer, default: 1800],
      max_concurrent_sessions: [type: :pos_integer, default: 5],
      behavior_learning_enabled: [type: :boolean, default: true],
      pattern_confidence_threshold: [type: :float, default: 0.7],
      adaptation_rate: [type: :float, default: 0.1],
      prediction_window: [type: :pos_integer, default: 100]
    ]

  require Logger

  @impl true
  def handle_signal(%{type: "user.session.start"} = signal, state) do
    user_id = signal.data.user_id

    # Initialize or retrieve user session state
    user_state = Map.get(state.users, user_id, initialize_user_state(user_id))

    # Start session with behavioral tracking
    session = %{
      id: generate_session_id(),
      user_id: user_id,
      started_at: DateTime.utc_now(),
      ip_address: signal.data[:ip_address],
      user_agent: signal.data[:user_agent],
      behavior_tracking: state.opts.behavior_learning_enabled,
      patterns: user_state.behavioral_patterns
    }

    # Update state with new session
    updated_user_state = Map.put(user_state, :current_session, session)
    updated_state = put_in(state, [:users, user_id], updated_user_state)

    # Emit session started signal
    emit_signal("user.session.started", %{
      user_id: user_id,
      session_id: session.id,
      predicted_actions: predict_initial_actions(user_state)
    })

    {:ok, session, updated_state}
  end

  @impl true
  def handle_signal(%{type: "user.session.end"} = signal, state) do
    user_id = signal.data.user_id

    case get_in(state, [:users, user_id, :current_session]) do
      nil ->
        {:ok, %{status: :no_active_session}, state}

      session ->
        # Calculate session metrics
        duration = DateTime.diff(DateTime.utc_now(), session.started_at)

        # Update behavioral patterns if learning is enabled
        updated_state =
          if state.opts.behavior_learning_enabled do
            update_behavioral_patterns(state, user_id, signal.data[:interactions] || [])
          else
            state
          end

        # Clear current session
        updated_state = put_in(updated_state, [:users, user_id, :current_session], nil)

        # Store session history
        session_record = Map.put(session, :ended_at, DateTime.utc_now())

        updated_state =
          update_in(updated_state, [:users, user_id, :session_history], fn history ->
            [session_record | Enum.take(history || [], 99)]
          end)

        {:ok, %{status: :session_ended, duration: duration}, updated_state}
    end
  end

  @impl true
  def handle_signal(%{type: "user.behavior.track"} = signal, state) do
    user_id = signal.data.user_id
    action = signal.data.action
    context = signal.data.context || %{}

    if state.opts.behavior_learning_enabled do
      # Track the behavior
      behavior = %{
        action: action,
        context: context,
        timestamp: DateTime.utc_now(),
        session_id: get_in(state, [:users, user_id, :current_session, :id])
      }

      # Update behavior history
      updated_state =
        update_in(state, [:users, user_id, :behavior_history], fn history ->
          [behavior | Enum.take(history || [], state.opts.prediction_window - 1)]
        end)

      # Learn patterns if we have enough data
      updated_state =
        if length(get_in(updated_state, [:users, user_id, :behavior_history]) || []) >= 10 do
          learn_behavioral_patterns(updated_state, user_id)
        else
          updated_state
        end

      # Generate predictions for next likely actions
      predictions = predict_next_actions(updated_state, user_id)

      {:ok, %{tracked: true, predictions: predictions}, updated_state}
    else
      {:ok, %{tracked: false}, state}
    end
  end

  @impl true
  def handle_signal(%{type: "user.preference.update"} = signal, state) do
    user_id = signal.data.user_id
    preference_key = signal.data.key
    preference_value = signal.data.value

    # Adapt preferences with learning
    updated_state =
      update_in(state, [:users, user_id, :preferences], fn prefs ->
        current_prefs = prefs || %{}

        # Apply adaptation rate if preference exists
        new_value =
          if Map.has_key?(current_prefs, preference_key) do
            adapt_preference(
              current_prefs[preference_key],
              preference_value,
              state.opts.adaptation_rate
            )
          else
            preference_value
          end

        Map.put(current_prefs, preference_key, new_value)
      end)

    # Track preference changes for learning
    updated_state =
      update_in(updated_state, [:users, user_id, :preference_history], fn history ->
        change = %{
          key: preference_key,
          old_value: get_in(state, [:users, user_id, :preferences, preference_key]),
          new_value: preference_value,
          timestamp: DateTime.utc_now()
        }

        [change | Enum.take(history || [], 49)]
      end)

    {:ok, %{preference_updated: true}, updated_state}
  end

  @impl true
  def handle_signal(%{type: "user.pattern.detect"} = signal, state) do
    user_id = signal.data.user_id

    user_state = get_in(state, [:users, user_id]) || initialize_user_state(user_id)

    # Detect patterns from recent behavior
    patterns = detect_behavioral_patterns(user_state.behavior_history || [])

    # Filter by confidence threshold
    confident_patterns =
      Enum.filter(patterns, fn pattern ->
        pattern.confidence >= state.opts.pattern_confidence_threshold
      end)

    # Update stored patterns
    updated_state = put_in(state, [:users, user_id, :behavioral_patterns], confident_patterns)

    # Generate proactive suggestions based on patterns
    suggestions = generate_proactive_suggestions(confident_patterns, user_state)

    {:ok, %{patterns: confident_patterns, suggestions: suggestions}, updated_state}
  end

  @impl true
  def handle_signal(%{type: "user.interaction.complete"} = signal, state) do
    user_id = signal.data.user_id
    interaction = signal.data.interaction

    # Learn from the completed interaction
    updated_state =
      if state.opts.behavior_learning_enabled do
        learn_from_interaction(state, user_id, interaction)
      else
        state
      end

    # Update interaction statistics
    updated_state =
      update_in(updated_state, [:users, user_id, :stats], fn stats ->
        current_stats = stats || %{total_interactions: 0, successful: 0, failed: 0}

        current_stats
        |> Map.update(:total_interactions, 1, &(&1 + 1))
        |> Map.update(
          if(interaction.success, do: :successful, else: :failed),
          1,
          &(&1 + 1)
        )
      end)

    {:ok, %{learned: state.opts.behavior_learning_enabled}, updated_state}
  end

  @impl true
  def handle_signal(_signal, state) do
    {:ok, state}
  end

  # Private helper functions

  defp initialize_user_state(user_id) do
    %{
      user_id: user_id,
      current_session: nil,
      session_history: [],
      behavioral_patterns: [],
      behavior_history: [],
      preferences: %{},
      preference_history: [],
      stats: %{
        total_interactions: 0,
        successful: 0,
        failed: 0
      },
      created_at: DateTime.utc_now()
    }
  end

  defp generate_session_id do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  defp update_behavioral_patterns(state, user_id, interactions) do
    current_patterns = get_in(state, [:users, user_id, :behavioral_patterns]) || []

    # Analyze interactions to update patterns
    new_patterns = analyze_interactions_for_patterns(interactions)

    # Merge with existing patterns, updating confidence scores
    merged_patterns = merge_patterns(current_patterns, new_patterns, state.opts.adaptation_rate)

    put_in(state, [:users, user_id, :behavioral_patterns], merged_patterns)
  end

  defp learn_behavioral_patterns(state, user_id) do
    behavior_history = get_in(state, [:users, user_id, :behavior_history]) || []

    # Detect sequential patterns
    patterns = detect_behavioral_patterns(behavior_history)

    # Update stored patterns
    put_in(state, [:users, user_id, :behavioral_patterns], patterns)
  end

  defp detect_behavioral_patterns(behaviors) when length(behaviors) < 2, do: []

  defp detect_behavioral_patterns(behaviors) do
    # Group behaviors by action type
    grouped = Enum.group_by(behaviors, & &1.action)

    # Find sequential patterns
    patterns =
      Enum.flat_map(grouped, fn {action, instances} ->
        if length(instances) >= 3 do
          # Calculate pattern metrics
          timestamps = Enum.map(instances, & &1.timestamp)
          intervals = calculate_intervals(timestamps)

          [
            %{
              type: :recurring_action,
              action: action,
              frequency: length(instances),
              avg_interval: average(intervals),
              confidence: min(1.0, length(instances) / 10.0),
              detected_at: DateTime.utc_now()
            }
          ]
        else
          []
        end
      end)

    # Detect action sequences
    sequence_patterns = detect_action_sequences(behaviors)

    patterns ++ sequence_patterns
  end

  defp detect_action_sequences(behaviors) when length(behaviors) < 3, do: []

  defp detect_action_sequences(behaviors) do
    # Look for common action sequences (trigrams)
    behaviors
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.map(fn [a, b, c] -> [a.action, b.action, c.action] end)
    |> Enum.frequencies()
    |> Enum.filter(fn {_, count} -> count >= 2 end)
    |> Enum.map(fn {sequence, count} ->
      %{
        type: :action_sequence,
        sequence: sequence,
        frequency: count,
        confidence: min(1.0, count / 5.0),
        detected_at: DateTime.utc_now()
      }
    end)
  end

  defp predict_next_actions(state, user_id) do
    patterns = get_in(state, [:users, user_id, :behavioral_patterns]) || []
    recent_behaviors = get_in(state, [:users, user_id, :behavior_history]) || []

    if length(recent_behaviors) >= 2 do
      recent_actions =
        recent_behaviors
        |> Enum.take(2)
        |> Enum.map(& &1.action)
        |> Enum.reverse()

      # Find matching sequence patterns
      matching_sequences =
        patterns
        |> Enum.filter(&(&1.type == :action_sequence))
        |> Enum.filter(fn pattern ->
          Enum.take(pattern.sequence, 2) == recent_actions
        end)
        |> Enum.map(fn pattern ->
          %{
            action: Enum.at(pattern.sequence, 2),
            confidence: pattern.confidence,
            reason: :sequence_pattern
          }
        end)

      # Sort by confidence
      matching_sequences
      |> Enum.sort_by(& &1.confidence, :desc)
      |> Enum.take(3)
    else
      []
    end
  end

  defp predict_initial_actions(user_state) do
    # Predict likely initial actions based on historical patterns
    user_state.behavioral_patterns
    |> Enum.filter(&(&1.type == :recurring_action))
    |> Enum.sort_by(& &1.confidence, :desc)
    |> Enum.take(3)
    |> Enum.map(fn pattern ->
      %{
        action: pattern.action,
        confidence: pattern.confidence,
        reason: :historical_pattern
      }
    end)
  end

  defp generate_proactive_suggestions(patterns, _user_state) do
    suggestions = []

    # Suggest based on recurring patterns
    recurring_suggestions =
      patterns
      |> Enum.filter(&(&1.type == :recurring_action && &1.confidence >= 0.8))
      |> Enum.map(fn pattern ->
        %{
          type: :automation,
          action: pattern.action,
          message: "Automate #{pattern.action} - performed #{pattern.frequency} times",
          confidence: pattern.confidence
        }
      end)

    # Suggest based on sequences
    sequence_suggestions =
      patterns
      |> Enum.filter(&(&1.type == :action_sequence && &1.confidence >= 0.7))
      |> Enum.map(fn pattern ->
        %{
          type: :workflow,
          sequence: pattern.sequence,
          message: "Create workflow for: #{Enum.join(pattern.sequence, " → ")}",
          confidence: pattern.confidence
        }
      end)

    suggestions ++ recurring_suggestions ++ sequence_suggestions
  end

  defp learn_from_interaction(state, user_id, interaction) do
    # Update success/failure patterns
    pattern_key = {interaction.action, interaction.success}

    update_in(state, [:users, user_id, :interaction_patterns, pattern_key], fn count ->
      (count || 0) + 1
    end)
  end

  defp adapt_preference(old_value, new_value, adaptation_rate)
       when is_number(old_value) and is_number(new_value) do
    old_value * (1 - adaptation_rate) + new_value * adaptation_rate
  end

  defp adapt_preference(_old_value, new_value, _adaptation_rate), do: new_value

  defp analyze_interactions_for_patterns(interactions) do
    interactions
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, instances} ->
      %{
        type: :interaction_pattern,
        interaction_type: type,
        frequency: length(instances),
        confidence: min(1.0, length(instances) / 5.0),
        detected_at: DateTime.utc_now()
      }
    end)
  end

  defp merge_patterns(existing, new_patterns, adaptation_rate) do
    # Create a map of existing patterns by key
    existing_map =
      Map.new(existing, fn pattern ->
        key = pattern_key(pattern)
        {key, pattern}
      end)

    # Merge new patterns
    new_patterns
    |> Enum.reduce(existing_map, fn new_pattern, acc ->
      key = pattern_key(new_pattern)

      Map.update(acc, key, new_pattern, fn existing_pattern ->
        # Adapt confidence score
        %{
          existing_pattern
          | confidence:
              adapt_preference(
                existing_pattern.confidence,
                new_pattern.confidence,
                adaptation_rate
              ),
            frequency: existing_pattern.frequency + new_pattern.frequency
        }
      end)
    end)
    |> Map.values()
  end

  defp pattern_key(%{type: :recurring_action, action: action}), do: {:recurring, action}
  defp pattern_key(%{type: :action_sequence, sequence: seq}), do: {:sequence, seq}

  defp pattern_key(%{type: :interaction_pattern, interaction_type: type}),
    do: {:interaction, type}

  defp pattern_key(pattern), do: {:unknown, :erlang.phash2(pattern)}

  defp calculate_intervals([_]), do: []

  defp calculate_intervals([t1, t2 | rest]) do
    [DateTime.diff(t2, t1) | calculate_intervals([t2 | rest])]
  end

  defp average([]), do: 0
  defp average(list), do: Enum.sum(list) / length(list)

  defp emit_signal(type, data) do
    # In a real implementation, this would emit through the Jido signal system
    Logger.debug("Emitting signal: #{type} with data: #{inspect(data)}")
    :ok
  end
end
