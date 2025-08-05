defmodule RubberDuck.Agents.UserAgent do
  @moduledoc """
  Autonomous agent for user session management and behavioral learning.

  This agent provides:
  - Autonomous user session management with behavioral learning
  - Preference learning and proactive adaptation
  - User behavior pattern recognition and prediction
  - Proactive assistance suggestions based on usage patterns
  """

  use RubberDuck.Agents.Base,
    name: "user_agent",
    description: "Manages user sessions and learns from behavior patterns",
    schema: [
      # Base agent fields
      goals: [type: {:list, :map}, default: []],
      completed_goals: [type: {:list, :map}, default: []],
      experience: [type: {:list, :map}, default: []],
      learning_enabled: [type: :boolean, default: true],
      performance_metrics: [type: :map, default: %{}],
      learned_insights: [type: :map, default: %{}],
      learning_interval: [type: :pos_integer, default: 100],
      last_learning_at: [type: {:or, [:naive_datetime, :nil]}, default: nil],
      persistence_enabled: [type: :boolean, default: false],
      checkpoint_interval: [type: :pos_integer, default: 300_000],
      experience_retention_days: [type: :pos_integer, default: 30],
      max_memory_experiences: [type: :pos_integer, default: 1000],
      agent_state_id: [type: {:or, [:string, :nil]}, default: nil],
      last_checkpoint: [type: {:or, [:utc_datetime, :nil]}, default: nil],

      # Session management
      active_sessions: [type: :map, default: %{}],
      session_timeout: [type: :pos_integer, default: 1800], # 30 minutes
      max_concurrent_sessions: [type: :pos_integer, default: 5],

      # Behavioral learning
      behavior_patterns: [type: :map, default: %{}],
      interaction_history: [type: {:list, :map}, default: []],
      pattern_confidence_threshold: [type: :float, default: 0.7],

      # Preference learning
      user_preferences: [type: :map, default: %{}],
      preference_weights: [type: :map, default: %{}],
      adaptation_rate: [type: :float, default: 0.1],

      # Pattern recognition
      recognized_patterns: [type: :map, default: %{}],
      pattern_detection_window: [type: :pos_integer, default: 100], # last N interactions
      min_pattern_occurrences: [type: :pos_integer, default: 3],

      # Proactive assistance
      suggestion_queue: [type: {:list, :map}, default: []],
      suggestion_confidence_threshold: [type: :float, default: 0.8],
      max_suggestions_per_session: [type: :pos_integer, default: 3],
      last_suggestion_time: [type: {:or, [:utc_datetime, :nil]}, default: nil]
    ],
    actions: [
      RubberDuck.Actions.User.CreateSession,
      RubberDuck.Actions.User.ValidateSession,
      RubberDuck.Actions.User.RecordInteraction,
      RubberDuck.Actions.User.AnalyzeBehavior,
      RubberDuck.Actions.User.UpdatePreferences,
      RubberDuck.Actions.User.DetectPatterns,
      RubberDuck.Actions.User.GenerateSuggestions
    ]

  alias RubberDuck.Signal
  require Logger

  # Signal definitions
  @signal_session_created "user.session.created"
  @signal_session_expired "user.session.expired"
  @signal_pattern_detected "user.pattern.detected"
  @signal_preference_learned "user.preference.learned"
  @signal_suggestion_generated "user.suggestion.generated"

  def init(opts) do
    # Subscribe to relevant signals
    :ok = Signal.subscribe("auth.user.signed_in")
    :ok = Signal.subscribe("auth.user.signed_out")
    :ok = Signal.subscribe("user.action.performed")

    # Schedule periodic session cleanup
    schedule_session_cleanup()

    {:ok, opts}
  end

  def handle_instruction({:create_session, user_id}, agent) do
    case create_user_session(agent, user_id) do
      {:ok, session} ->
        updated_agent = update_active_sessions(agent, user_id, session)
        emit_signal(@signal_session_created, %{user_id: user_id, session_id: session.id})
        {:ok, session, updated_agent}

      {:error, reason} ->
        Logger.warning("Failed to create session for user #{user_id}: #{inspect(reason)}")
        {{:error, reason}, agent}
    end
  end

  def handle_instruction({:record_interaction, %{user_id: user_id, action: action, context: context}}, agent) do
    if valid_session?(agent, user_id) do
      interaction = build_interaction(user_id, action, context)
      updated_agent = agent
        |> record_interaction_history(interaction)
        |> analyze_for_patterns(user_id)
        |> update_user_preferences(user_id, interaction)
        |> generate_proactive_suggestions(user_id)

      {:ok, %{recorded: true}, updated_agent}
    else
      {{:error, :invalid_session}, agent}
    end
  end

  def handle_instruction({:get_suggestions, user_id}, agent) do
    suggestions = get_user_suggestions(agent, user_id)
    {:ok, suggestions, agent}
  end

  def handle_instruction({:analyze_behavior, user_id}, agent) do
    analysis = analyze_user_behavior(agent, user_id)
    {:ok, analysis, agent}
  end

  def handle_signal("auth.user.signed_in", %{user_id: user_id}, agent) do
    # Automatically create session on sign in
    handle_instruction({:create_session, user_id}, agent)
  end

  def handle_signal("auth.user.signed_out", %{user_id: user_id}, agent) do
    # Clean up session on sign out
    updated_agent = remove_user_session(agent, user_id)
    {:ok, updated_agent}
  end

  def handle_signal("user.action.performed", payload, agent) do
    # Record user actions for learning
    handle_instruction({:record_interaction, payload}, agent)
  end

  def handle_info(:cleanup_sessions, agent) do
    updated_agent = cleanup_expired_sessions(agent)
    schedule_session_cleanup()
    {:noreply, updated_agent}
  end

  # Private functions

  defp create_user_session(agent, user_id) do
    if can_create_session?(agent, user_id) do
      session = %{
        id: generate_session_id(),
        user_id: user_id,
        started_at: DateTime.utc_now(),
        last_activity: DateTime.utc_now(),
        interaction_count: 0
      }
      {:ok, session}
    else
      {:error, :max_sessions_reached}
    end
  end

  defp can_create_session?(agent, user_id) do
    user_sessions = Map.get(agent.state.active_sessions, user_id, [])
    length(user_sessions) < agent.state.max_concurrent_sessions
  end

  defp update_active_sessions(agent, user_id, session) do
    sessions = Map.get(agent.state.active_sessions, user_id, [])
    updated_sessions = [session | sessions]

    put_in(agent.state.active_sessions[user_id], updated_sessions)
  end

  defp valid_session?(agent, user_id) do
    case Map.get(agent.state.active_sessions, user_id) do
      nil -> false
      [] -> false
      sessions ->
        Enum.any?(sessions, &session_active?(&1, agent.state.session_timeout))
    end
  end

  defp session_active?(session, timeout_seconds) do
    case DateTime.diff(DateTime.utc_now(), session.last_activity, :second) do
      diff when diff <= timeout_seconds -> true
      _ -> false
    end
  end

  defp build_interaction(user_id, action, context) do
    %{
      user_id: user_id,
      action: action,
      context: context,
      timestamp: DateTime.utc_now(),
      session_context: extract_session_context(context)
    }
  end

  defp extract_session_context(context) do
    %{
      time_of_day: get_time_category(),
      day_of_week: Date.day_of_week(Date.utc_today()),
      device_type: context[:device_type] || :unknown,
      location_type: context[:location_type] || :unknown
    }
  end

  defp get_time_category do
    hour = DateTime.utc_now().hour
    cond do
      hour >= 5 && hour < 12 -> :morning
      hour >= 12 && hour < 17 -> :afternoon
      hour >= 17 && hour < 21 -> :evening
      true -> :night
    end
  end

  defp record_interaction_history(agent, interaction) do
    history = [interaction | agent.state.interaction_history]
      |> Enum.take(agent.state.pattern_detection_window)

    %{agent | state: %{agent.state | interaction_history: history}}
  end

  defp analyze_for_patterns(agent, user_id) do
    user_interactions = Enum.filter(agent.state.interaction_history, & &1.user_id == user_id)

    patterns = detect_behavior_patterns(user_interactions, agent.state.min_pattern_occurrences)

    if map_size(patterns) > 0 do
      emit_signal(@signal_pattern_detected, %{user_id: user_id, patterns: patterns})
      put_in(agent.state.recognized_patterns[user_id], patterns)
    else
      agent
    end
  end

  defp detect_behavior_patterns(interactions, min_occurrences) do
    interactions
    |> Enum.group_by(& {&1.action, &1.session_context.time_of_day})
    |> Enum.filter(fn {_, group} -> length(group) >= min_occurrences end)
    |> Enum.map(fn {{action, time}, group} ->
      pattern = %{
        action: action,
        time_preference: time,
        frequency: length(group),
        confidence: calculate_pattern_confidence(group, interactions)
      }
      {action, pattern}
    end)
    |> Map.new()
  end

  defp calculate_pattern_confidence(pattern_group, all_interactions) do
    pattern_count = length(pattern_group)
    total_count = length(all_interactions)

    if total_count > 0 do
      pattern_count / total_count
    else
      0.0
    end
  end

  defp update_user_preferences(agent, user_id, interaction) do
    current_prefs = Map.get(agent.state.user_preferences, user_id, %{})

    updated_prefs = learn_from_interaction(current_prefs, interaction, agent.state.adaptation_rate)

    if prefs_changed?(current_prefs, updated_prefs) do
      emit_signal(@signal_preference_learned, %{user_id: user_id, preferences: updated_prefs})
      put_in(agent.state.user_preferences[user_id], updated_prefs)
    else
      agent
    end
  end

  defp learn_from_interaction(preferences, interaction, adaptation_rate) do
    action_type = interaction.action[:type] || :unknown

    # Update action preferences
    action_prefs = Map.get(preferences, :actions, %{})
    updated_action_count = Map.get(action_prefs, action_type, 0) + 1

    # Update time preferences
    time_prefs = Map.get(preferences, :time_preferences, %{})
    time_of_day = interaction.session_context.time_of_day
    updated_time_weight = Map.get(time_prefs, time_of_day, 0.0) + adaptation_rate

    %{
      actions: Map.put(action_prefs, action_type, updated_action_count),
      time_preferences: Map.put(time_prefs, time_of_day, min(updated_time_weight, 1.0)),
      last_updated: DateTime.utc_now()
    }
  end

  defp prefs_changed?(old_prefs, new_prefs) do
    old_prefs != new_prefs
  end

  defp generate_proactive_suggestions(agent, user_id) do
    patterns = Map.get(agent.state.recognized_patterns, user_id, %{})
    preferences = Map.get(agent.state.user_preferences, user_id, %{})

    suggestions = build_suggestions(patterns, preferences, agent.state.suggestion_confidence_threshold)

    if length(suggestions) > 0 do
      emit_signal(@signal_suggestion_generated, %{user_id: user_id, count: length(suggestions)})

      updated_queue = Enum.take(suggestions ++ agent.state.suggestion_queue,
                                agent.state.max_suggestions_per_session)

      %{agent | state: %{agent.state |
        suggestion_queue: updated_queue,
        last_suggestion_time: DateTime.utc_now()
      }}
    else
      agent
    end
  end

  defp build_suggestions(patterns, _preferences, confidence_threshold) do
    patterns
    |> Enum.filter(fn {_, pattern} -> pattern.confidence >= confidence_threshold end)
    |> Enum.map(fn {action, pattern} ->
      %{
        action: action,
        reasoning: "Based on your usage pattern",
        confidence: pattern.confidence,
        context: pattern,
        created_at: DateTime.utc_now()
      }
    end)
    |> Enum.sort_by(& &1.confidence, :desc)
  end

  defp get_user_suggestions(agent, user_id) do
    agent.state.suggestion_queue
    |> Enum.filter(& &1.user_id == user_id)
    |> Enum.take(agent.state.max_suggestions_per_session)
  end

  defp analyze_user_behavior(agent, user_id) do
    interactions = Enum.filter(agent.state.interaction_history, & &1.user_id == user_id)
    patterns = Map.get(agent.state.recognized_patterns, user_id, %{})
    _preferences = Map.get(agent.state.user_preferences, user_id, %{})

    %{
      total_interactions: length(interactions),
      recognized_patterns: map_size(patterns),
      top_actions: get_top_actions(interactions, 5),
      time_preferences: get_time_preferences(interactions),
      learning_confidence: calculate_learning_confidence(patterns)
    }
  end

  defp get_top_actions(interactions, limit) do
    interactions
    |> Enum.group_by(& &1.action[:type])
    |> Enum.map(fn {action, group} -> {action, length(group)} end)
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.take(limit)
    |> Map.new()
  end

  defp get_time_preferences(interactions) do
    interactions
    |> Enum.group_by(& &1.session_context.time_of_day)
    |> Enum.map(fn {time, group} -> {time, length(group)} end)
    |> Map.new()
  end

  defp calculate_learning_confidence(patterns) do
    if map_size(patterns) == 0 do
      0.0
    else
      confidences = Enum.map(patterns, fn {_, pattern} -> pattern.confidence end)
      Enum.sum(confidences) / length(confidences)
    end
  end

  defp remove_user_session(agent, user_id) do
    %{agent | state: %{agent.state | active_sessions: Map.delete(agent.state.active_sessions, user_id)}}
  end

  defp cleanup_expired_sessions(agent) do
    timeout = agent.state.session_timeout

    cleaned_sessions = agent.state.active_sessions
      |> Enum.map(fn {user_id, sessions} ->
        active_sessions = Enum.filter(sessions, &session_active?(&1, timeout))
        expired_count = length(sessions) - length(active_sessions)

        if expired_count > 0 do
          emit_signal(@signal_session_expired, %{user_id: user_id, count: expired_count})
        end

        {user_id, active_sessions}
      end)
      |> Enum.reject(fn {_, sessions} -> Enum.empty?(sessions) end)
      |> Map.new()

    %{agent | state: %{agent.state | active_sessions: cleaned_sessions}}
  end

  defp schedule_session_cleanup do
    Process.send_after(self(), :cleanup_sessions, 60_000) # Every minute
  end

  defp generate_session_id do
    "session_#{System.unique_integer([:positive])}_#{System.os_time(:nanosecond)}"
  end

  defp emit_signal(signal_type, payload) do
    Signal.emit(signal_type, Map.put(payload, :timestamp, DateTime.utc_now()))
  rescue
    e -> Logger.warning("Failed to emit signal #{signal_type}: #{inspect(e)}")
  end
end
