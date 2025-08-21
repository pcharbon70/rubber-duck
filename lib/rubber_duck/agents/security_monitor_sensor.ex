defmodule RubberDuck.Agents.SecurityMonitorSensor do
  @moduledoc """
  Security monitoring sensor for real-time threat detection and response.

  This sensor continuously monitors security events, correlates threats,
  and coordinates automatic countermeasures with other security agents.
  """

  use Jido.Agent,
    name: "security_monitor_sensor",
    description: "Real-time threat detection with pattern recognition",
    category: "security",
    tags: ["security", "monitoring", "threat-detection"],
    vsn: "1.0.0",
    actions: []

  alias RubberDuck.Skills.{LearningSkill, ThreatDetectionSkill}

  @doc """
  Create a new SecurityMonitorSensor instance.
  """
  def create_monitor(monitoring_scope \\ :global) do
    with {:ok, agent} <- __MODULE__.new(),
         {:ok, agent} <-
           __MODULE__.set(agent,
             monitoring_scope: monitoring_scope,
             active_threats: %{},
             threat_patterns: [],
             security_events: [],
             baseline_metrics: %{},
             escalation_rules: default_escalation_rules(),
             last_scan: nil
           ) do
      {:ok, agent}
    end
  end

  @doc """
  Process security event and detect threats.
  """
  def process_security_event(agent, event_data) do
    # Analyze the security event
    case ThreatDetectionSkill.detect_threat(
           %{request_data: event_data, user_context: extract_user_context(event_data)},
           agent
         ) do
      {:ok, threat_analysis, updated_agent} ->
        # Process the threat based on level
        response_action = determine_response_action(threat_analysis)

        # Update agent state
        {:ok, final_agent} =
          __MODULE__.set(updated_agent,
            security_events: [event_data | agent.security_events] |> Enum.take(500),
            last_scan: DateTime.utc_now()
          )

        # Trigger response if threat detected
        if threat_analysis.threat_level != :minimal do
          trigger_threat_response(final_agent, threat_analysis, response_action)
        else
          {:ok, %{status: :no_threat, analysis: threat_analysis}, final_agent}
        end

      error ->
        error
    end
  end

  @doc """
  Correlate security events and identify attack patterns.
  """
  def correlate_events(agent, time_window_minutes \\ 10) do
    events = agent.security_events
    cutoff_time = DateTime.add(DateTime.utc_now(), -time_window_minutes * 60, :second)

    recent_events =
      Enum.filter(events, fn event ->
        event_time = Map.get(event, :timestamp, DateTime.utc_now())
        DateTime.compare(event_time, cutoff_time) == :gt
      end)

    correlation_analysis = %{
      event_count: length(recent_events),
      source_ips: extract_unique_sources(recent_events),
      attack_patterns: identify_coordinated_patterns(recent_events),
      correlation_confidence: calculate_correlation_confidence(recent_events),
      recommended_actions: generate_correlation_recommendations(recent_events)
    }

    {:ok, updated_agent} =
      __MODULE__.set(agent,
        last_correlation: DateTime.utc_now(),
        correlation_results: correlation_analysis
      )

    {:ok, correlation_analysis, updated_agent}
  end

  @doc """
  Establish security baseline for anomaly detection.
  """
  def establish_baseline(agent, baseline_period_hours \\ 24) do
    events = agent.security_events
    cutoff_time = DateTime.add(DateTime.utc_now(), -baseline_period_hours * 3600, :second)

    baseline_events =
      Enum.filter(events, fn event ->
        event_time = Map.get(event, :timestamp, DateTime.utc_now())
        DateTime.compare(event_time, cutoff_time) == :gt
      end)

    baseline_metrics = %{
      average_events_per_hour: length(baseline_events) / baseline_period_hours,
      common_source_ips: extract_common_sources(baseline_events),
      typical_request_patterns: extract_request_patterns(baseline_events),
      normal_user_behaviors: extract_user_behaviors(baseline_events),
      baseline_established_at: DateTime.utc_now()
    }

    {:ok, updated_agent} =
      __MODULE__.set(agent,
        baseline_metrics: baseline_metrics,
        baseline_last_updated: DateTime.utc_now()
      )

    {:ok, baseline_metrics, updated_agent}
  end

  @doc """
  Generate security intelligence report.
  """
  def generate_intelligence_report(agent) do
    active_threats = agent.active_threats
    threat_patterns = agent.threat_patterns
    _recent_events = Enum.take(agent.security_events, 100)

    intelligence_report = %{
      monitoring_scope: agent.monitoring_scope,
      active_threat_count: map_size(active_threats),
      threat_severity_distribution: calculate_severity_distribution(active_threats),
      pattern_evolution: analyze_pattern_evolution(threat_patterns),
      security_posture_score: calculate_security_posture(agent),
      recommendations: generate_security_recommendations(agent),
      report_generated_at: DateTime.utc_now()
    }

    {:ok, intelligence_report}
  end

  @doc """
  Update escalation rules based on learning.
  """
  def update_escalation_rules(agent, new_rules) do
    current_rules = agent.escalation_rules
    merged_rules = Map.merge(current_rules, new_rules)

    {:ok, updated_agent} =
      __MODULE__.set(agent,
        escalation_rules: merged_rules,
        rules_last_updated: DateTime.utc_now()
      )

    {:ok, "Escalation rules updated successfully", updated_agent}
  end

  # Private helper functions

  defp default_escalation_rules do
    %{
      critical_threat_threshold: 0.9,
      high_threat_threshold: 0.7,
      automated_response_enabled: true,
      max_response_time_seconds: 30,
      require_human_approval: false
    }
  end

  defp extract_user_context(event_data) do
    %{
      user_id: Map.get(event_data, :user_id),
      ip_address: Map.get(event_data, :ip_address),
      user_agent: Map.get(event_data, :user_agent),
      session_id: Map.get(event_data, :session_id),
      access_time: Map.get(event_data, :timestamp, DateTime.utc_now())
    }
  end

  defp determine_response_action(threat_analysis) do
    case threat_analysis.threat_level do
      :critical -> :immediate_lockdown
      :high -> :enhanced_monitoring
      :medium -> :increased_verification
      :low -> :passive_monitoring
      :minimal -> :no_action
    end
  end

  defp trigger_threat_response(agent, threat_analysis, response_action) do
    case ThreatDetectionSkill.coordinate_response(
           %{threat_data: threat_analysis, response_type: response_action},
           agent
         ) do
      {:ok, coordination_plan, updated_agent} ->
        # Update active threats
        threat_id = coordination_plan.threat_id
        active_threats = Map.put(agent.active_threats, threat_id, threat_analysis)

        {:ok, final_agent} =
          __MODULE__.set(updated_agent,
            active_threats: active_threats
          )

        {:ok, %{status: :threat_response_triggered, coordination: coordination_plan}, final_agent}

      error ->
        error
    end
  end

  defp extract_unique_sources(events) do
    events
    |> Enum.map(&Map.get(&1, :ip_address))
    |> Enum.filter(&(&1 != nil))
    |> Enum.uniq()
  end

  defp identify_coordinated_patterns(events) do
    # Group events by source IP to identify coordinated attacks
    by_source = Enum.group_by(events, &Map.get(&1, :ip_address))

    coordinated_sources =
      Enum.filter(by_source, fn {_ip, ip_events} ->
        # More than 5 events from same IP
        length(ip_events) > 5
      end)

    %{
      coordinated_source_count: length(coordinated_sources),
      max_events_per_source:
        if Enum.empty?(coordinated_sources) do
          0
        else
          coordinated_sources
          |> Enum.map(fn {_ip, events} -> length(events) end)
          |> Enum.max()
        end,
      attack_distribution: calculate_attack_distribution(by_source)
    }
  end

  defp calculate_correlation_confidence(events) do
    event_count = length(events)
    unique_sources = extract_unique_sources(events) |> length()

    # Higher confidence with more events and fewer unique sources (indicates coordination)
    if event_count > 0 do
      coordination_factor = 1.0 - unique_sources / event_count
      volume_factor = min(event_count / 20.0, 1.0)

      (coordination_factor + volume_factor) / 2
    else
      0.0
    end
  end

  defp generate_correlation_recommendations(events) do
    event_count = length(events)
    unique_sources = extract_unique_sources(events) |> length()

    recommendations = []

    recommendations =
      if event_count > 20 do
        ["Implement rate limiting for high-volume sources" | recommendations]
      else
        recommendations
      end

    recommendations =
      if unique_sources < event_count / 3 do
        ["Consider IP-based blocking for coordinated sources" | recommendations]
      else
        recommendations
      end

    if Enum.empty?(recommendations) do
      ["Continue monitoring current security posture"]
    else
      recommendations
    end
  end

  defp extract_common_sources(events) do
    events
    |> Enum.map(&Map.get(&1, :ip_address))
    |> Enum.filter(&(&1 != nil))
    |> Enum.frequencies()
    |> Enum.filter(fn {_ip, count} -> count > 2 end)
    |> Enum.map(fn {ip, _count} -> ip end)
  end

  defp extract_request_patterns(events) do
    events
    |> Enum.map(&Map.get(&1, :request_path, "/"))
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_path, count} -> count end, :desc)
    |> Enum.take(10)
  end

  defp extract_user_behaviors(events) do
    events
    |> Enum.group_by(&Map.get(&1, :user_id))
    |> Enum.map(fn {user_id, user_events} ->
      {user_id,
       %{
         event_count: length(user_events),
         avg_session_duration: calculate_avg_session_duration(user_events),
         common_access_patterns: extract_access_patterns(user_events)
       }}
    end)
    |> Enum.into(%{})
  end

  defp calculate_severity_distribution(active_threats) do
    threats = Map.values(active_threats)

    distribution = Enum.frequencies_by(threats, & &1.threat_level)

    %{
      critical: Map.get(distribution, :critical, 0),
      high: Map.get(distribution, :high, 0),
      medium: Map.get(distribution, :medium, 0),
      low: Map.get(distribution, :low, 0)
    }
  end

  defp analyze_pattern_evolution(threat_patterns) do
    if length(threat_patterns) < 10 do
      %{trend: :insufficient_data}
    else
      recent_patterns = Enum.take(threat_patterns, 50)
      older_patterns = Enum.drop(threat_patterns, 50) |> Enum.take(50)

      recent_avg_threat = calculate_average_threat_level(recent_patterns)
      older_avg_threat = calculate_average_threat_level(older_patterns)

      %{
        trend: determine_threat_trend(recent_avg_threat, older_avg_threat),
        recent_average: recent_avg_threat,
        historical_average: older_avg_threat
      }
    end
  end

  defp calculate_security_posture(agent) do
    active_threat_count = map_size(agent.active_threats)
    baseline_quality = assess_baseline_quality(agent.baseline_metrics)
    detection_effectiveness = calculate_detection_effectiveness(agent)

    # Combine factors for overall security posture
    threat_factor = max(1.0 - active_threat_count / 10.0, 0.0)
    baseline_factor = baseline_quality
    detection_factor = detection_effectiveness

    overall_score = (threat_factor + baseline_factor + detection_factor) / 3

    cond do
      overall_score > 0.9 -> :excellent
      overall_score > 0.7 -> :good
      overall_score > 0.5 -> :adequate
      overall_score > 0.3 -> :concerning
      true -> :critical
    end
  end

  defp generate_security_recommendations(agent) do
    posture = calculate_security_posture(agent)
    active_threats = map_size(agent.active_threats)

    recommendations = []

    recommendations =
      case posture do
        :critical ->
          ["Immediate security review required", "Consider system lockdown" | recommendations]

        :concerning ->
          ["Enhanced monitoring recommended", "Review security policies" | recommendations]

        :adequate ->
          ["Maintain current security posture", "Regular baseline updates" | recommendations]

        _ ->
          ["Continue current monitoring" | recommendations]
      end

    recommendations =
      if active_threats > 5 do
        ["Scale threat response capabilities" | recommendations]
      else
        recommendations
      end

    recommendations
  end

  defp calculate_attack_distribution(by_source) do
    source_counts = Enum.map(by_source, fn {_ip, events} -> length(events) end)

    if Enum.empty?(source_counts) do
      %{mean: 0, max: 0, distribution: :even}
    else
      mean_events = Enum.sum(source_counts) / length(source_counts)
      max_events = Enum.max(source_counts)

      distribution_type =
        if max_events > mean_events * 3 do
          :concentrated
        else
          :distributed
        end

      %{
        mean: mean_events,
        max: max_events,
        distribution: distribution_type
      }
    end
  end

  defp calculate_avg_session_duration(user_events) do
    # Simple duration calculation based on event timestamps
    if length(user_events) < 2 do
      0
    else
      sorted_events = Enum.sort_by(user_events, &Map.get(&1, :timestamp, DateTime.utc_now()))
      first_event = List.first(sorted_events)
      last_event = List.last(sorted_events)

      first_time = Map.get(first_event, :timestamp, DateTime.utc_now())
      last_time = Map.get(last_event, :timestamp, DateTime.utc_now())

      DateTime.diff(last_time, first_time, :second)
    end
  end

  defp extract_access_patterns(user_events) do
    user_events
    |> Enum.map(&Map.get(&1, :request_path, "/"))
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_path, count} -> count end, :desc)
    |> Enum.take(5)
  end

  defp calculate_average_threat_level(patterns) do
    if Enum.empty?(patterns) do
      0.0
    else
      threat_scores = Enum.map(patterns, &threat_level_to_score(&1.threat_level))
      Enum.sum(threat_scores) / length(threat_scores)
    end
  end

  defp threat_level_to_score(:critical), do: 1.0
  defp threat_level_to_score(:high), do: 0.8
  defp threat_level_to_score(:medium), do: 0.6
  defp threat_level_to_score(:low), do: 0.4
  defp threat_level_to_score(:minimal), do: 0.2

  defp determine_threat_trend(recent_avg, older_avg) do
    difference = recent_avg - older_avg

    cond do
      difference > 0.2 -> :escalating
      difference > 0.1 -> :increasing
      difference < -0.2 -> :decreasing
      difference < -0.1 -> :improving
      true -> :stable
    end
  end

  defp assess_baseline_quality(baseline_metrics) when is_map(baseline_metrics) do
    if map_size(baseline_metrics) == 0 do
      0.0
    else
      # Simple quality assessment based on data availability
      quality_factors = [
        Map.has_key?(baseline_metrics, :average_events_per_hour),
        Map.has_key?(baseline_metrics, :common_source_ips),
        Map.has_key?(baseline_metrics, :typical_request_patterns),
        Map.has_key?(baseline_metrics, :normal_user_behaviors)
      ]

      Enum.count(quality_factors, & &1) / length(quality_factors)
    end
  end

  defp assess_baseline_quality(_), do: 0.0

  defp calculate_detection_effectiveness(agent) do
    # Simple effectiveness calculation based on threat detection history
    threat_patterns = agent.threat_patterns

    if length(threat_patterns) < 5 do
      # Insufficient data
      0.5
    else
      # Calculate based on confidence scores of recent detections
      recent_detections = Enum.take(threat_patterns, 20)
      confidence_scores = Enum.map(recent_detections, &Map.get(&1, :confidence, 0.5))

      Enum.sum(confidence_scores) / length(confidence_scores)
    end
  end
end
