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

  # Removed unused function generate_session_id/0

  # Removed unused functions:
  # - update_behavioral_patterns/3
  # - learn_behavioral_patterns/2

  # Removed unused function detect_behavioral_patterns/1

  # Removed unused functions:
  # - detect_action_sequences/1
  # - predict_next_actions/2  
  # - predict_initial_actions/1
  # - generate_proactive_suggestions/2

  # Removed unused function generate_proactive_suggestions_unused/2

  # Removed unused functions:
  # - learn_from_interaction/3
  # - adapt_preference/3 
  # - analyze_interactions_for_patterns/1
  # - merge_patterns/3
  # - pattern_key/1
  # - calculate_intervals/1
  # - average/1

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
