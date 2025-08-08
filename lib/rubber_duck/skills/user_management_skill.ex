defmodule RubberDuck.Skills.UserManagementSkill do
  @moduledoc """
  Skill for managing user sessions and learning from user behavior patterns.

  This skill provides autonomous session management, behavioral learning,
  preference adaptation, and proactive assistance suggestions based on
  user interaction patterns.

  Uses typed messages exclusively for all user management operations.
  """

  use RubberDuck.Skills.Base,
    name: "user_management",
    description: "Manages user sessions and learns from behavioral patterns",
    category: "user",
    tags: ["user", "session", "behavior", "learning", "preferences"],
    vsn: "2.0.0",
    opts_key: :user_management,
    opts_schema: [
      session_timeout: [type: :pos_integer, default: 1800],
      max_concurrent_sessions: [type: :pos_integer, default: 5],
      behavior_learning_enabled: [type: :boolean, default: true],
      pattern_confidence_threshold: [type: :float, default: 0.7],
      adaptation_rate: [type: :float, default: 0.1],
      prediction_window: [type: :pos_integer, default: 100]
    ]

  require Logger

  alias RubberDuck.Messages.User.{
    ValidateSession,
    UpdatePreferences,
    TrackActivity,
    GenerateSuggestions
  }

  # Typed message handlers

  @doc """
  Handle typed ValidateSession message
  """
  def handle_validate_session(%ValidateSession{} = msg, context) do
    state = context[:state] || %{users: %{}}
    user_state = get_in(state, [:users, msg.user_id]) || %{}
    session = user_state[:current_session]

    # Validate session
    validation_result =
      cond do
        session == nil ->
          %{valid: false, reason: :no_session}

        session[:id] != msg.session_id ->
          %{valid: false, reason: :session_mismatch}

        msg.check_expiry and session_expired?(session, get_timeout(state)) ->
          %{valid: false, reason: :session_expired}

        true ->
          %{valid: true}
      end

    # Refresh if requested and valid
    validation_result =
      if validation_result.valid and msg.refresh_if_valid do
        refreshed_session = Map.put(session, :last_activity, DateTime.utc_now())

        validation_result
        |> Map.put(:refreshed, true)
        |> Map.put(:session, refreshed_session)
      else
        validation_result
      end

    {:ok, validation_result}
  end

  @doc """
  Handle typed UpdatePreferences message
  """
  def handle_update_preferences(%UpdatePreferences{} = msg, context) do
    state = context[:state] || %{users: %{}}
    user_state = get_in(state, [:users, msg.user_id]) || initialize_user_state(msg.user_id)
    current_prefs = user_state[:preferences] || %{}

    # Apply merge strategy
    new_prefs =
      case msg.merge_strategy do
        :replace ->
          msg.preferences

        :merge ->
          Map.merge(current_prefs, msg.preferences)

        :deep_merge ->
          deep_merge(current_prefs, msg.preferences)

        _ ->
          Map.merge(current_prefs, msg.preferences)
      end

    # Track preference changes
    changes = detect_preference_changes(current_prefs, new_prefs)

    # Learn from preference updates if enabled
    learning_insights =
      if get_in(state, [:opts, :behavior_learning_enabled]) do
        learn_from_preference_changes(user_state, changes)
      else
        []
      end

    result = %{
      success: true,
      user_id: msg.user_id,
      previous_preferences: current_prefs,
      new_preferences: new_prefs,
      changes: changes,
      learning_insights: learning_insights
    }

    {:ok, result}
  end

  @doc """
  Handle typed TrackActivity message
  """
  def handle_track_activity(%TrackActivity{} = msg, context) do
    state = context[:state] || %{users: %{}}
    user_state = get_in(state, [:users, msg.user_id]) || initialize_user_state(msg.user_id)

    # Create activity record
    activity = %{
      id: generate_activity_id(),
      user_id: msg.user_id,
      type: msg.activity_type,
      data: msg.activity_data || %{},
      timestamp: msg.timestamp || DateTime.utc_now(),
      session_id: msg.session_id || user_state[:current_session][:id]
    }

    # Update behavior history
    behavior_history = [activity | Enum.take(user_state[:behavior_history] || [], 999)]

    # Detect patterns if learning is enabled
    patterns =
      if get_in(state, [:opts, :behavior_learning_enabled]) and length(behavior_history) >= 10 do
        detect_behavior_patterns(
          behavior_history,
          get_in(state, [:opts, :pattern_confidence_threshold])
        )
      else
        []
      end

    # Generate predictions based on patterns
    predictions =
      if length(patterns) > 0 do
        predict_next_user_actions(patterns, activity)
      else
        []
      end

    result = %{
      tracked: true,
      activity_id: activity.id,
      patterns_detected: length(patterns),
      predictions: predictions,
      session_active: user_state[:current_session] != nil
    }

    {:ok, result}
  end

  @doc """
  Handle typed GenerateSuggestions message
  """
  def handle_generate_suggestions(%GenerateSuggestions{} = msg, context) do
    state = context[:state] || %{users: %{}}
    user_state = get_in(state, [:users, msg.user_id]) || initialize_user_state(msg.user_id)

    # Get relevant data for suggestion generation
    patterns = user_state[:behavioral_patterns] || []
    preferences = user_state[:preferences] || %{}
    recent_activities = Enum.take(user_state[:behavior_history] || [], 20)

    # Generate suggestions based on requested types
    suggestion_types = msg.suggestion_types || [:workflow, :shortcut, :optimization, :learning]

    suggestions =
      suggestion_types
      |> Enum.flat_map(fn type ->
        generate_suggestions_by_type(type, user_state, msg.context)
      end)
      |> score_suggestions(patterns, preferences)
      |> Enum.sort_by(& &1.score, :desc)
      |> Enum.take(msg.max_suggestions || 5)

    # Add personalization metadata
    suggestions =
      suggestions
      |> Enum.map(fn suggestion ->
        suggestion
        |> Map.put(:personalized, true)
        |> Map.put(:confidence, calculate_suggestion_confidence(suggestion, patterns))
      end)

    result = %{
      user_id: msg.user_id,
      suggestions: suggestions,
      based_on: %{
        patterns: length(patterns),
        recent_activities: length(recent_activities),
        preferences: map_size(preferences)
      }
    }

    {:ok, result}
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
        |> Enum.filter(fn pattern ->
          pattern.type == :action_sequence && Enum.take(pattern.sequence, 2) == recent_actions
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

  # Additional helper functions for typed messages

  defp session_expired?(session, timeout) do
    last_activity = session[:last_activity] || session[:started_at]
    diff = DateTime.diff(DateTime.utc_now(), last_activity, :second)
    diff > timeout
  end

  defp get_timeout(state) do
    state[:opts][:session_timeout] || 1800
  end

  defp deep_merge(map1, map2) do
    Map.merge(map1, map2, fn
      _k, v1, v2 when is_map(v1) and is_map(v2) -> deep_merge(v1, v2)
      _k, _v1, v2 -> v2
    end)
  end

  defp detect_preference_changes(old_prefs, new_prefs) do
    all_keys = (Map.keys(old_prefs) ++ Map.keys(new_prefs)) |> Enum.uniq()

    Enum.reduce(all_keys, [], fn key, changes ->
      old_val = Map.get(old_prefs, key)
      new_val = Map.get(new_prefs, key)

      cond do
        old_val == nil and new_val != nil ->
          [{:added, key, new_val} | changes]

        old_val != nil and new_val == nil ->
          [{:removed, key, old_val} | changes]

        old_val != new_val ->
          [{:changed, key, old_val, new_val} | changes]

        true ->
          changes
      end
    end)
  end

  defp learn_from_preference_changes(_user_state, changes) do
    # Analyze preference changes for insights
    changes
    |> Enum.map(fn
      {:added, key, value} ->
        %{type: :preference_discovered, key: key, value: value}

      {:changed, key, _old, new} ->
        %{type: :preference_evolved, key: key, new_value: new}

      {:removed, key, _} ->
        %{type: :preference_abandoned, key: key}
    end)
  end

  defp generate_activity_id do
    bytes = :crypto.strong_rand_bytes(8)
    "activity_#{bytes |> Base.encode16(case: :lower)}"
  end

  defp detect_behavior_patterns(behavior_history, confidence_threshold) do
    # Detect patterns in user behavior
    behavior_history
    |> group_by_type()
    |> Enum.flat_map(fn {type, activities} ->
      if length(activities) >= 3 do
        [
          %{
            id: "pattern_#{:erlang.unique_integer([:positive])}",
            type: type,
            frequency: length(activities),
            confidence: min(length(activities) / 10, 1.0),
            sequence: extract_sequence(activities),
            timestamps: Enum.map(activities, & &1[:timestamp])
          }
        ]
      else
        []
      end
    end)
    |> Enum.filter(&(&1.confidence >= confidence_threshold))
  end

  defp group_by_type(activities) do
    Enum.group_by(activities, & &1[:type])
  end

  defp extract_sequence(activities) do
    activities
    |> Enum.take(5)
    |> Enum.map(& &1[:type])
  end

  defp predict_next_user_actions(patterns, current_activity) do
    # Simple prediction based on pattern matching
    patterns
    |> Enum.filter(& &1[:sequence])
    |> Enum.flat_map(fn pattern ->
      if pattern.sequence |> List.first() == current_activity.type do
        [
          %{
            predicted_action: pattern.sequence |> Enum.at(1),
            confidence: pattern[:confidence] || 0.5,
            based_on_pattern: pattern[:id]
          }
        ]
      else
        []
      end
    end)
    |> Enum.take(3)
  end

  defp generate_suggestions_by_type(type, user_state, context) do
    case type do
      :workflow ->
        generate_workflow_suggestions(user_state, context)

      :shortcut ->
        generate_shortcut_suggestions(user_state, context)

      :optimization ->
        generate_optimization_suggestions(user_state, context)

      :learning ->
        generate_learning_suggestions(user_state, context)

      _ ->
        []
    end
  end

  defp generate_workflow_suggestions(user_state, _context) do
    patterns = user_state[:behavioral_patterns] || []

    patterns
    |> Enum.filter(&(&1[:type] == :sequence))
    |> Enum.take(2)
    |> Enum.map(fn pattern ->
      %{
        type: :workflow,
        title: "Automate frequent workflow",
        description: "You frequently perform this sequence: #{inspect(pattern[:sequence])}",
        action: :create_automation,
        score: 0.0
      }
    end)
  end

  defp generate_shortcut_suggestions(user_state, _context) do
    recent = Enum.take(user_state[:behavior_history] || [], 50)

    # Find frequently used commands
    freq_commands =
      recent
      |> Enum.filter(&(&1[:type] == :command_run))
      |> Enum.map(& &1[:data][:command])
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_, count} -> count end, :desc)
      |> Enum.take(2)

    Enum.map(freq_commands, fn {command, count} ->
      %{
        type: :shortcut,
        title: "Create shortcut for '#{command}'",
        description: "You've used this command #{count} times recently",
        action: :create_shortcut,
        score: 0.0
      }
    end)
  end

  defp generate_optimization_suggestions(_user_state, _context) do
    [
      %{
        type: :optimization,
        title: "Enable caching for faster performance",
        description: "Based on your usage patterns, caching could improve response times",
        action: :enable_caching,
        score: 0.0
      }
    ]
  end

  defp generate_learning_suggestions(_user_state, _context) do
    [
      %{
        type: :learning,
        title: "Explore advanced features",
        description: "There are features you haven't used that might be helpful",
        action: :show_tutorial,
        score: 0.0
      }
    ]
  end

  defp score_suggestions(suggestions, patterns, preferences) do
    suggestions
    |> Enum.map(fn suggestion ->
      pattern_score = calculate_pattern_relevance(suggestion, patterns)
      pref_score = calculate_preference_alignment(suggestion, preferences)

      suggestion
      |> Map.put(:score, (pattern_score + pref_score) / 2)
    end)
  end

  defp calculate_pattern_relevance(suggestion, patterns) do
    # Score based on how well suggestion aligns with user patterns
    if Enum.any?(patterns, &(&1[:type] == suggestion.type)) do
      0.8
    else
      0.3
    end
  end

  defp calculate_preference_alignment(suggestion, preferences) do
    # Score based on user preferences
    if preferences[:suggestions_enabled] == false do
      0.0
    else
      case suggestion.type do
        :workflow -> preferences[:workflow_automation] || 0.5
        :shortcut -> preferences[:shortcuts_enabled] || 0.6
        :optimization -> preferences[:performance_focus] || 0.7
        :learning -> preferences[:learning_enabled] || 0.4
      end
    end
  end

  defp calculate_suggestion_confidence(suggestion, patterns) do
    base_confidence = suggestion[:score] || 0.5
    pattern_boost = if length(patterns) > 5, do: 0.2, else: 0.0

    min(base_confidence + pattern_boost, 1.0)
  end
end
