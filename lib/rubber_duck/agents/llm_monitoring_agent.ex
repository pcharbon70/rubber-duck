defmodule RubberDuck.Agents.LLMMonitoringAgent do
  @moduledoc """
  Autonomous monitoring agent that reacts to LLM health signals.

  This agent:
  - Monitors provider health through sensor signals
  - Takes corrective actions when providers degrade
  - Learns patterns from failures to predict issues
  - Coordinates with other agents for system stability
  """

  use RubberDuck.Agents.Base,
    name: "llm_monitoring",
    description: "Monitors and maintains LLM provider health",
    schema: [
      monitoring_active: [type: :boolean, default: true],
      auto_recovery_enabled: [type: :boolean, default: true],
      alert_threshold: [type: :integer, default: 3],
      recovery_strategies: [type: :map, default: %{}],
      failure_patterns: [type: :list, default: []],
      provider_history: [type: :map, default: %{}]
    ],
    actions: [
      RubberDuck.Actions.LLM.SelectProvider
    ]

  require Logger

  # Subscribe to health signals
  @health_signals [
    "llm.health.provider.healthy",
    "llm.health.provider.degraded",
    "llm.health.provider.failed",
    "llm.health.check.completed",
    "llm.provider.selected",
    "llm.fallback.triggered"
  ]

  def init(opts) do
    # Subscribe to all health-related signals
    Enum.each(@health_signals, &RubberDuck.Signal.subscribe/1)

    # Set initial goals
    initial_goals = [
      %{
        id: "maintain_health",
        type: :continuous,
        description: "Maintain healthy LLM provider ecosystem",
        priority: :high
      },
      %{
        id: "learn_patterns",
        type: :continuous,
        description: "Learn failure patterns to predict issues",
        priority: :medium
      }
    ]

    {:ok, Map.update(opts, :goals, initial_goals, fn existing -> existing ++ initial_goals end)}
  end

  def handle_info(:checkpoint, agent) do
    # Delegate to base module's checkpoint handler
    on_checkpoint(agent)
  end

  def handle_info(msg, agent) do
    Logger.debug("Unhandled message in monitoring agent: #{inspect(msg)}")
    {:ok, agent}
  end

  def handle_signal("llm.health.provider.failed", payload, agent) do
    provider = payload.provider
    error = payload.error

    Logger.error("Provider #{provider} failed: #{inspect(error)}")

    # Update failure history
    updated_agent = record_provider_failure(agent, provider, error, payload)

    # Check if we need to take action
    if should_take_corrective_action?(updated_agent, provider) do
      take_corrective_action(updated_agent, provider, error)
    else
      {:ok, updated_agent}
    end
  end

  def handle_signal("llm.health.provider.degraded", payload, agent) do
    provider = payload.provider
    reason = payload.reason

    Logger.warning("Provider #{provider} degraded: #{inspect(reason)}")

    # Learn from degradation patterns
    updated_agent = learn_degradation_pattern(agent, provider, reason, payload)

    # Proactively adjust if needed
    if agent.state.auto_recovery_enabled do
      suggest_provider_adjustment(updated_agent, provider, reason)
    else
      {:ok, updated_agent}
    end
  end

  def handle_signal("llm.health.provider.healthy", payload, agent) do
    provider = payload.provider

    Logger.info("Provider #{provider} recovered to healthy state")

    # Record recovery
    updated_agent = record_provider_recovery(agent, provider, payload)

    # Learn from recovery patterns
    {:ok, learn_recovery_pattern(updated_agent, provider)}
  end

  def handle_signal("llm.health.check.completed", payload, agent) do
    # Analyze overall system health
    healthy_count = payload.healthy_count
    degraded_count = payload.degraded_count
    failed_count = payload.failed_count

    total_providers = healthy_count + degraded_count + failed_count
    health_ratio = if total_providers > 0, do: healthy_count / total_providers, else: 0

    # Update system health metrics
    updated_agent = update_system_health_metrics(agent, %{
      health_ratio: health_ratio,
      degraded_count: degraded_count,
      failed_count: failed_count,
      timestamp: payload.timestamp
    })

    # Check if system health is concerning
    if health_ratio < 0.5 && agent.state.monitoring_active do
      handle_system_health_crisis(updated_agent, payload)
    else
      {:ok, updated_agent}
    end
  end

  def handle_signal("llm.fallback.triggered", payload, agent) do
    # Learn from fallback patterns
    from_provider = payload.from_provider
    to_provider = payload.to_provider

    updated_agent = record_fallback_event(agent, from_provider, to_provider)

    # If too many fallbacks, investigate
    if count_recent_fallbacks(updated_agent, from_provider) > agent.state.alert_threshold do
      investigate_provider_issues(updated_agent, from_provider)
    else
      {:ok, updated_agent}
    end
  end

  def handle_instruction({:diagnose_provider, provider_name}, agent) do
    diagnosis = perform_provider_diagnosis(agent, provider_name)

    {:ok, diagnosis, agent}
  end

  def handle_instruction({:predict_failures, time_window}, agent) do
    predictions = predict_provider_failures(agent, time_window)

    {:ok, predictions, agent}
  end

  def handle_instruction(:get_health_summary, agent) do
    summary = compile_health_summary(agent)

    {:ok, summary, agent}
  end

  # Private functions

  defp record_provider_failure(agent, provider, error, payload) do
    try do
      history = Map.get(agent.state.provider_history, provider, %{
        failures: [],
        recoveries: [],
        degradations: []
      })

      failure_record = %{
        error: error,
        timestamp: DateTime.utc_now(),
        metrics: payload[:metrics]
      }

      updated_history = Map.update(history, :failures, [failure_record], &[failure_record | &1])

      %{agent | state: Map.put(agent.state, :provider_history,
        Map.put(agent.state.provider_history, provider, updated_history))}
    rescue
      exception ->
        Logger.error("Failed to record provider failure: #{inspect(exception)}")
        agent  # Return unchanged agent on error
    end
  end

  defp record_provider_recovery(agent, provider, payload) do
    history = Map.get(agent.state.provider_history, provider, %{
      failures: [],
      recoveries: [],
      degradations: []
    })

    recovery_record = %{
      timestamp: DateTime.utc_now(),
      response_time_ms: payload.response_time_ms,
      metrics: payload[:metrics]
    }

    updated_history = Map.update(history, :recoveries, [recovery_record], &[recovery_record | &1])

    %{agent | state: Map.put(agent.state, :provider_history,
      Map.put(agent.state.provider_history, provider, updated_history))}
  end

  defp should_take_corrective_action?(agent, provider) do
    history = Map.get(agent.state.provider_history, provider, %{})
    recent_failures = get_recent_events(history[:failures] || [], 300) # Last 5 minutes

    length(recent_failures) >= agent.state.alert_threshold
  end

  defp take_corrective_action(agent, provider, error) do
    try do
      Logger.info("Taking corrective action for provider #{provider}")

      # Emit signal for other agents to avoid this provider temporarily
      try do
        RubberDuck.Signal.emit("llm.monitoring.provider.quarantine", %{
          provider: provider,
          reason: error,
          duration_seconds: 300,  # 5 minute quarantine
          suggested_alternatives: suggest_alternatives(agent, provider),
          timestamp: DateTime.utc_now()
        })
      rescue
        e -> Logger.warning("Failed to emit quarantine signal: #{inspect(e)}")
      end

      # Record the action taken
      updated_agent = record_corrective_action(agent, provider, :quarantine)

      {:ok, updated_agent}
    rescue
      exception ->
        Logger.error("Corrective action failed: #{inspect(exception)}")
        {:ok, agent}  # Continue with unchanged agent
    end
  end

  defp learn_degradation_pattern(agent, provider, reason, payload) do
    # Extract pattern features
    pattern = %{
      provider: provider,
      reason: reason,
      time_of_day: get_hour_of_day(),
      day_of_week: get_day_of_week(),
      metrics: payload[:metrics],
      timestamp: DateTime.utc_now()
    }

    # Add to failure patterns
    updated_patterns = [pattern | agent.state.failure_patterns] |> Enum.take(1000)

    %{agent | state: Map.put(agent.state, :failure_patterns, updated_patterns)}
  end

  defp learn_recovery_pattern(agent, provider) do
    # Analyze what led to recovery
    history = Map.get(agent.state.provider_history, provider, %{})

    if last_failure = List.first(history[:failures] || []) do
      recovery_time = DateTime.diff(DateTime.utc_now(), last_failure.timestamp)

      # Update recovery strategies
      strategy = determine_recovery_strategy(last_failure, recovery_time)

      updated_strategies = Map.put(
        agent.state.recovery_strategies,
        {provider, last_failure.error},
        strategy
      )

      %{agent | state: Map.put(agent.state, :recovery_strategies, updated_strategies)}
    else
      agent
    end
  end

  defp suggest_provider_adjustment(agent, provider, reason) do
    adjustment = case reason do
      {:slow_response, ms} when ms > 10_000 ->
        %{action: :reduce_load, reason: "Very slow response times"}

      {:high_error_rate, rate} when rate > 0.8 ->
        %{action: :temporary_disable, reason: "Extremely high error rate"}

      _ ->
        %{action: :monitor, reason: "Continue monitoring"}
    end

    RubberDuck.Signal.emit("llm.monitoring.adjustment.suggested", %{
      provider: provider,
      adjustment: adjustment,
      current_reason: reason
    })

    {:ok, agent}
  end

  defp handle_system_health_crisis(agent, health_data) do
    try do
      Logger.error("System health crisis detected: #{inspect(health_data)}")

      # Emit crisis signal
      try do
        RubberDuck.Signal.emit("llm.monitoring.crisis", %{
          health_ratio: health_data[:health_ratio],
          failed_providers: health_data[:failed_count],
          degraded_providers: health_data[:degraded_count],
          recommended_actions: [
            "Scale up healthy providers",
            "Investigate root cause",
            "Enable fallback modes",
            "Alert operations team"
          ],
          timestamp: DateTime.utc_now()
        })
      rescue
        e -> Logger.error("Failed to emit crisis signal: #{inspect(e)}")
      end

      # Mark goal as critical
      updated_goals = Enum.map(agent.state.goals, fn goal ->
        if is_map(goal) && goal[:id] == "maintain_health" do
          Map.put(goal, :status, :critical)
        else
          goal
        end
      end)

      {:ok, %{agent | state: Map.put(agent.state, :goals, updated_goals)}}
    rescue
      exception ->
        Logger.error("Crisis handling failed: #{inspect(exception)}")
        {:ok, agent}  # Continue with unchanged agent
    end
  end

  defp record_fallback_event(agent, from_provider, to_provider) do
    event = %{
      from: from_provider,
      to: to_provider,
      timestamp: DateTime.utc_now()
    }

    # Add to experience
    on_experience_gained(agent, %{
      type: :fallback,
      event: event,
      goal: %{type: :maintain_health}
    })
  end

  defp count_recent_fallbacks(agent, provider) do
    agent.state.experience
    |> Enum.filter(fn exp ->
      exp[:type] == :fallback &&
      exp.event.from == provider &&
      DateTime.diff(DateTime.utc_now(), exp.timestamp) < 300
    end)
    |> length()
  end

  defp investigate_provider_issues(agent, provider) do
    # Gather all recent data about the provider
    investigation = %{
      provider: provider,
      recent_failures: get_provider_recent_failures(agent, provider),
      recent_fallbacks: count_recent_fallbacks(agent, provider),
      patterns: find_failure_patterns(agent, provider),
      recommendation: determine_provider_recommendation(agent, provider)
    }

    RubberDuck.Signal.emit("llm.monitoring.investigation.complete", investigation)

    {:ok, agent}
  end

  defp perform_provider_diagnosis(agent, provider_name) do
    history = Map.get(agent.state.provider_history, provider_name, %{})
    patterns = find_failure_patterns(agent, provider_name)

    %{
      provider: provider_name,
      health_score: calculate_provider_health_score(history),
      recent_issues: get_recent_events(history[:failures] || [], 3600),
      identified_patterns: patterns,
      recommendations: generate_provider_recommendations(history, patterns)
    }
  end

  defp predict_provider_failures(agent, time_window_seconds) do
    # Simple prediction based on patterns
    agent.state.failure_patterns
    |> Enum.group_by(& &1.provider)
    |> Enum.map(fn {provider, patterns} ->
      failure_probability = calculate_failure_probability(patterns, time_window_seconds)

      %{
        provider: provider,
        failure_probability: failure_probability,
        likely_reasons: extract_likely_reasons(patterns),
        preventive_actions: suggest_preventive_actions(failure_probability)
      }
    end)
    |> Enum.filter(& &1.failure_probability > 0.3)
  end

  defp compile_health_summary(agent) do
    %{
      monitoring_active: agent.state.monitoring_active,
      providers_monitored: Map.keys(agent.state.provider_history),
      total_failures: count_total_failures(agent.state.provider_history),
      total_recoveries: count_total_recoveries(agent.state.provider_history),
      learned_patterns: length(agent.state.failure_patterns),
      active_goals: length(agent.state.goals),
      last_crisis: find_last_crisis(agent.state.experience)
    }
  end

  # Helper functions

  defp get_recent_events(events, seconds) do
    cutoff = DateTime.add(DateTime.utc_now(), -seconds, :second)
    Enum.filter(events, fn event ->
      DateTime.compare(event.timestamp, cutoff) == :gt
    end)
  end

  defp get_hour_of_day do
    DateTime.utc_now().hour
  end

  defp get_day_of_week do
    Date.day_of_week(DateTime.utc_now())
  end

  defp suggest_alternatives(agent, failed_provider) do
    # Get all providers except the failed one
    all_providers = Map.keys(agent.state.provider_history)

    all_providers
    |> Enum.reject(& &1 == failed_provider)
    |> Enum.map(fn provider ->
      history = Map.get(agent.state.provider_history, provider, %{})
      score = calculate_provider_health_score(history)
      {provider, score}
    end)
    |> Enum.sort_by(fn {_, score} -> score end, :desc)
    |> Enum.take(3)
    |> Enum.map(fn {provider, _} -> provider end)
  end

  defp calculate_provider_health_score(history) do
    recent_failures = length(get_recent_events(history[:failures] || [], 3600))
    recent_recoveries = length(get_recent_events(history[:recoveries] || [], 3600))

    if recent_failures + recent_recoveries == 0 do
      1.0
    else
      recent_recoveries / (recent_failures + recent_recoveries)
    end
  end

  defp determine_recovery_strategy(failure, recovery_time_seconds) do
    %{
      error_type: categorize_error(failure.error),
      recovery_time: recovery_time_seconds,
      effectiveness: if(recovery_time_seconds < 300, do: :fast, else: :slow),
      suggested_wait: calculate_suggested_wait(recovery_time_seconds)
    }
  end

  defp categorize_error({:error, :timeout}), do: :timeout
  defp categorize_error({:error, :rate_limit}), do: :rate_limit
  defp categorize_error({:error, {:http_error, _}}), do: :http_error
  defp categorize_error(_), do: :unknown

  defp calculate_suggested_wait(recovery_time) do
    # Suggest waiting 20% of recovery time before retry
    div(recovery_time, 5)
  end

  defp find_failure_patterns(agent, provider) do
    agent.state.failure_patterns
    |> Enum.filter(& &1.provider == provider)
    |> Enum.group_by(& &1.reason)
    |> Enum.map(fn {reason, occurrences} ->
      %{
        reason: reason,
        count: length(occurrences),
        time_pattern: analyze_time_pattern(occurrences)
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  defp analyze_time_pattern(occurrences) do
    hours = Enum.map(occurrences, & &1.time_of_day)
    most_common_hour = most_common(hours)

    %{
      most_common_hour: most_common_hour,
      occurrences_by_hour: Enum.frequencies(hours)
    }
  end

  defp most_common(list) do
    list
    |> Enum.frequencies()
    |> Enum.max_by(fn {_, count} -> count end, fn -> {nil, 0} end)
    |> elem(0)
  end

  defp get_provider_recent_failures(agent, provider) do
    history = Map.get(agent.state.provider_history, provider, %{})
    get_recent_events(history[:failures] || [], 3600)
  end

  defp determine_provider_recommendation(agent, provider) do
    recent_failures = get_provider_recent_failures(agent, provider)
    failure_rate = length(recent_failures) / 12  # Per 5-minute interval in last hour

    cond do
      failure_rate > 2.0 -> :immediate_disable
      failure_rate > 1.0 -> :reduce_traffic
      failure_rate > 0.5 -> :monitor_closely
      true -> :normal_operation
    end
  end

  defp generate_provider_recommendations(_history, patterns) do
    recommendations = []

    # Check for timeout patterns
    timeout_patterns = Enum.filter(patterns, fn p ->
      case p.reason do
        {:slow_response, _} -> true
        _ -> false
      end
    end)
    recommendations = if length(timeout_patterns) > 0 do
      ["Increase timeout thresholds or optimize provider configuration" | recommendations]
    else
      recommendations
    end

    # Check for time-based patterns
    time_patterns = Enum.find(patterns, & &1.time_pattern.most_common_hour != nil)
    recommendations = if time_patterns do
      ["Consider load balancing during hour #{time_patterns.time_pattern.most_common_hour}" | recommendations]
    else
      recommendations
    end

    recommendations
  end

  defp calculate_failure_probability(patterns, time_window_seconds) do
    recent_patterns = get_recent_events(patterns, time_window_seconds)

    if length(recent_patterns) < 2 do
      0.0
    else
      # Simple linear extrapolation
      failure_rate = length(recent_patterns) / (time_window_seconds / 3600)
      min(failure_rate * 0.5, 1.0)  # Cap at 100%
    end
  end

  defp extract_likely_reasons(patterns) do
    patterns
    |> Enum.map(& &1.reason)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.take(3)
    |> Enum.map(fn {reason, _} -> reason end)
  end

  defp suggest_preventive_actions(probability) do
    cond do
      probability > 0.8 ->
        ["Preemptively switch to backup provider", "Scale up alternative providers"]

      probability > 0.5 ->
        ["Increase monitoring frequency", "Prepare fallback configuration"]

      probability > 0.3 ->
        ["Monitor provider closely", "Verify backup providers are healthy"]

      true ->
        []
    end
  end

  defp count_total_failures(provider_history) do
    provider_history
    |> Map.values()
    |> Enum.map(& length(Map.get(&1, :failures, [])))
    |> Enum.sum()
  end

  defp count_total_recoveries(provider_history) do
    provider_history
    |> Map.values()
    |> Enum.map(& length(Map.get(&1, :recoveries, [])))
    |> Enum.sum()
  end

  defp find_last_crisis(experience) do
    experience
    |> Enum.find(& &1[:type] == :crisis)
    |> case do
      nil -> nil
      crisis -> crisis.timestamp
    end
  end

  defp record_corrective_action(agent, provider, action) do
    experience = %{
      type: :corrective_action,
      provider: provider,
      action: action,
      timestamp: DateTime.utc_now(),
      goal: %{type: :maintain_health}
    }

    elem(on_experience_gained(agent, experience), 1)
  end

  defp update_system_health_metrics(agent, metrics) do
    updated_metrics = Map.merge(agent.state.performance_metrics, %{
      last_health_check: metrics.timestamp,
      system_health_ratio: metrics.health_ratio,
      degraded_providers: metrics.degraded_count,
      failed_providers: metrics.failed_count
    })

    %{agent | state: Map.put(agent.state, :performance_metrics, updated_metrics)}
  end
end
