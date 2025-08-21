defmodule RubberDuck.Skills.ThreatDetectionSkill do
  @moduledoc """
  Threat detection skill with pattern learning and anomaly detection.

  Provides capabilities for detecting security threats, analyzing attack patterns,
  and coordinating automatic countermeasures with confidence scoring.
  """

  use Jido.Skill,
    name: "threat_detection_skill",
    opts_key: :threat_detection_state,
    signal_patterns: [
      "security.detect_threat",
      "security.analyze_pattern",
      "security.assess_risk",
      "security.coordinate_response"
    ]

  @doc """
  Detect security threats based on behavioral patterns.
  """
  def detect_threat(%{request_data: request_data, user_context: user_context} = _params, state) do
    threat_analysis = %{
      threat_level: calculate_threat_level(request_data, user_context),
      anomaly_score: detect_anomalies(request_data, user_context, state),
      pattern_matches: find_threat_patterns(request_data, state),
      behavioral_deviation: analyze_behavioral_deviation(user_context, state),
      confidence: calculate_detection_confidence(request_data, user_context, state),
      timestamp: DateTime.utc_now()
    }

    # Update threat patterns database
    threat_patterns = Map.get(state, :threat_patterns, [])
    updated_patterns = [threat_analysis | threat_patterns] |> Enum.take(1000)

    new_state =
      state
      |> Map.put(:threat_patterns, updated_patterns)
      |> Map.put(:last_detection, DateTime.utc_now())

    {:ok, threat_analysis, new_state}
  end

  @doc """
  Analyze attack patterns and update threat intelligence.
  """
  def analyze_pattern(%{attack_data: attack_data, source_ip: source_ip} = _params, state) do
    pattern_analysis = %{
      attack_type: classify_attack_type(attack_data),
      source_reputation: assess_source_reputation(source_ip, state),
      pattern_frequency: calculate_pattern_frequency(attack_data, state),
      sophistication_level: assess_attack_sophistication(attack_data),
      correlation_score: correlate_with_known_attacks(attack_data, state),
      mitigation_recommendations: generate_mitigation_strategies(attack_data)
    }

    # Store pattern for future reference
    attack_patterns = Map.get(state, :attack_patterns, %{})
    attack_type = pattern_analysis.attack_type

    updated_attack_patterns =
      Map.update(
        attack_patterns,
        attack_type,
        [pattern_analysis],
        fn existing -> [pattern_analysis | existing] |> Enum.take(100) end
      )

    new_state =
      state
      |> Map.put(:attack_patterns, updated_attack_patterns)
      |> Map.put(:last_pattern_analysis, DateTime.utc_now())

    {:ok, pattern_analysis, new_state}
  end

  @doc """
  Assess current risk level based on accumulated intelligence.
  """
  def assess_risk(%{context: context} = _params, state) do
    risk_assessment = %{
      current_risk_level: calculate_current_risk(context, state),
      active_threats: count_active_threats(state),
      risk_factors: identify_risk_factors(context, state),
      recommended_security_level: recommend_security_level(context, state),
      confidence_score: calculate_risk_confidence(state),
      assessment_timestamp: DateTime.utc_now()
    }

    # Update risk history
    risk_history = Map.get(state, :risk_history, [])
    updated_history = [risk_assessment | risk_history] |> Enum.take(200)

    new_state =
      state
      |> Map.put(:risk_history, updated_history)
      |> Map.put(:current_risk_assessment, risk_assessment)

    {:ok, risk_assessment, new_state}
  end

  @doc """
  Coordinate threat response with other security agents.
  """
  def coordinate_response(
        %{threat_data: threat_data, response_type: response_type} = _params,
        state
      ) do
    coordination_plan = %{
      threat_id: generate_threat_id(),
      response_type: response_type,
      coordinated_actions: plan_coordinated_actions(threat_data, response_type),
      agent_assignments: assign_response_agents(threat_data, response_type),
      escalation_triggers: define_escalation_triggers(threat_data),
      success_criteria: define_response_success_criteria(threat_data, response_type),
      initiated_at: DateTime.utc_now()
    }

    # Track coordination for learning
    coordination_history = Map.get(state, :coordination_history, [])
    updated_history = [coordination_plan | coordination_history] |> Enum.take(100)

    new_state =
      state
      |> Map.put(:coordination_history, updated_history)
      |> Map.put(:active_coordinations, [
        coordination_plan | Map.get(state, :active_coordinations, [])
      ])

    {:ok, coordination_plan, new_state}
  end

  # Private helper functions

  defp calculate_threat_level(request_data, user_context) do
    base_threat = analyze_request_anomalies(request_data)
    behavioral_threat = analyze_behavioral_anomalies(user_context)

    combined_score = (base_threat + behavioral_threat) / 2

    cond do
      combined_score > 0.8 -> :critical
      combined_score > 0.6 -> :high
      combined_score > 0.4 -> :medium
      combined_score > 0.2 -> :low
      true -> :minimal
    end
  end

  defp detect_anomalies(request_data, user_context, state) do
    baseline_patterns = Map.get(state, :baseline_patterns, %{})

    request_anomaly = calculate_request_anomaly(request_data, baseline_patterns)
    behavioral_anomaly = calculate_behavioral_anomaly(user_context, baseline_patterns)
    temporal_anomaly = calculate_temporal_anomaly(user_context, baseline_patterns)

    (request_anomaly + behavioral_anomaly + temporal_anomaly) / 3
  end

  defp find_threat_patterns(request_data, state) do
    known_patterns = Map.get(state, :threat_patterns, [])

    Enum.filter(known_patterns, fn pattern ->
      pattern_similarity(request_data, pattern) > 0.7
    end)
  end

  defp analyze_behavioral_deviation(user_context, state) do
    user_baselines = Map.get(state, :user_baselines, %{})
    user_id = Map.get(user_context, :user_id)

    case Map.get(user_baselines, user_id) do
      # No baseline, medium deviation
      nil -> 0.5
      baseline -> calculate_deviation_score(user_context, baseline)
    end
  end

  defp calculate_detection_confidence(request_data, user_context, state) do
    sample_size = length(Map.get(state, :threat_patterns, []))
    baseline_quality = assess_baseline_quality(state)
    data_completeness = assess_data_completeness(request_data, user_context)

    # Combine factors for confidence score
    (min(sample_size / 100.0, 1.0) + baseline_quality + data_completeness) / 3
  end

  defp classify_attack_type(attack_data) do
    cond do
      String.contains?(to_string(attack_data), "brute") -> :brute_force
      String.contains?(to_string(attack_data), "injection") -> :sql_injection
      String.contains?(to_string(attack_data), "xss") -> :xss_attack
      String.contains?(to_string(attack_data), "csrf") -> :csrf_attack
      String.contains?(to_string(attack_data), "dos") -> :denial_of_service
      true -> :unknown_attack
    end
  end

  defp assess_source_reputation(source_ip, state) do
    ip_reputation = Map.get(state, :ip_reputation, %{})

    case Map.get(ip_reputation, source_ip) do
      nil -> :unknown
      reputation when reputation > 0.8 -> :trusted
      reputation when reputation > 0.5 -> :neutral
      reputation when reputation > 0.2 -> :suspicious
      _ -> :malicious
    end
  end

  defp calculate_pattern_frequency(attack_data, state) do
    attack_type = classify_attack_type(attack_data)
    attack_patterns = Map.get(state, :attack_patterns, %{})

    case Map.get(attack_patterns, attack_type) do
      nil -> 0.0
      # Normalize to 0-1 scale
      patterns -> length(patterns) / 100.0
    end
  end

  defp assess_attack_sophistication(attack_data) do
    # Simple sophistication scoring based on attack characteristics
    sophistication_indicators = [
      String.contains?(to_string(attack_data), "encrypted"),
      String.contains?(to_string(attack_data), "obfuscated"),
      String.contains?(to_string(attack_data), "polymorphic"),
      String.contains?(to_string(attack_data), "multi-stage")
    ]

    score = Enum.count(sophistication_indicators, & &1) / length(sophistication_indicators)

    cond do
      score > 0.75 -> :advanced
      score > 0.5 -> :intermediate
      score > 0.25 -> :basic
      true -> :simple
    end
  end

  defp correlate_with_known_attacks(attack_data, state) do
    known_attacks = Map.get(state, :known_attack_signatures, [])

    correlations =
      Enum.map(known_attacks, fn signature ->
        similarity_score(attack_data, signature)
      end)

    if Enum.empty?(correlations), do: 0.0, else: Enum.max(correlations)
  end

  defp generate_mitigation_strategies(attack_data) do
    attack_type = classify_attack_type(attack_data)

    case attack_type do
      :brute_force ->
        ["Rate limiting", "Account lockout", "IP blocking", "MFA enforcement"]

      :sql_injection ->
        ["Parameter sanitization", "Query parameterization", "WAF rules", "Input validation"]

      :xss_attack ->
        ["Output encoding", "CSP headers", "Input sanitization", "DOM security"]

      :csrf_attack ->
        ["CSRF tokens", "SameSite cookies", "Referrer validation", "Origin checking"]

      _ ->
        ["General monitoring", "Log analysis", "Incident response", "Security review"]
    end
  end

  defp calculate_current_risk(context, state) do
    # Last hour
    recent_threats = get_recent_threats(state, 3600)
    active_patterns = count_active_attack_patterns(state)
    baseline_risk = Map.get(context, :baseline_risk, 0.3)

    threat_factor = min(length(recent_threats) / 10.0, 1.0)
    pattern_factor = min(active_patterns / 5.0, 1.0)

    combined_risk = baseline_risk + threat_factor * 0.4 + pattern_factor * 0.3
    min(combined_risk, 1.0)
  end

  defp count_active_threats(state) do
    # Last 30 minutes
    recent_threats = get_recent_threats(state, 1800)
    length(recent_threats)
  end

  defp identify_risk_factors(context, state) do
    factors = []

    # Check for high-risk conditions
    factors =
      if Map.get(context, :off_hours, false) do
        ["Off-hours access" | factors]
      else
        factors
      end

    factors =
      if Map.get(context, :new_device, false) do
        ["New device detected" | factors]
      else
        factors
      end

    factors =
      if count_active_threats(state) > 3 do
        ["Multiple active threats" | factors]
      else
        factors
      end

    factors
  end

  defp recommend_security_level(context, state) do
    current_risk = calculate_current_risk(context, state)

    cond do
      current_risk > 0.8 -> :maximum
      current_risk > 0.6 -> :high
      current_risk > 0.4 -> :elevated
      current_risk > 0.2 -> :normal
      true -> :minimal
    end
  end

  defp calculate_risk_confidence(state) do
    pattern_count = length(Map.get(state, :threat_patterns, []))
    history_depth = length(Map.get(state, :risk_history, []))

    confidence_factors = [
      min(pattern_count / 50.0, 1.0),
      min(history_depth / 100.0, 1.0)
    ]

    Enum.sum(confidence_factors) / length(confidence_factors)
  end

  defp plan_coordinated_actions(_threat_data, :immediate) do
    [
      %{agent: :authentication, action: :increase_security_level},
      %{agent: :token, action: :revoke_suspicious_tokens},
      %{agent: :permission, action: :restrict_permissions}
    ]
  end

  defp plan_coordinated_actions(_threat_data, :investigation) do
    [
      %{agent: :monitor, action: :enhance_logging},
      %{agent: :authentication, action: :require_additional_verification},
      %{agent: :token, action: :reduce_token_lifetime}
    ]
  end

  defp plan_coordinated_actions(_threat_data, _response_type) do
    [
      %{agent: :monitor, action: :increase_monitoring}
    ]
  end

  defp assign_response_agents(threat_data, response_type) do
    case {classify_attack_type(threat_data), response_type} do
      {:brute_force, :immediate} ->
        [:authentication_agent, :token_agent]

      {:sql_injection, :immediate} ->
        [:permission_agent, :security_monitor]

      {_, :investigation} ->
        [:security_monitor, :authentication_agent]

      _ ->
        [:security_monitor]
    end
  end

  defp define_escalation_triggers(threat_data) do
    attack_type = classify_attack_type(threat_data)

    case attack_type do
      :brute_force ->
        [
          %{condition: :failed_attempts_exceeded, threshold: 10},
          %{condition: :multiple_source_ips, threshold: 5}
        ]

      :sql_injection ->
        [
          %{condition: :successful_injection, threshold: 1},
          %{condition: :data_access_attempted, threshold: 1}
        ]

      _ ->
        [
          %{condition: :pattern_repetition, threshold: 3}
        ]
    end
  end

  defp define_response_success_criteria(_threat_data, response_type) do
    case response_type do
      :immediate ->
        %{
          threat_neutralized: true,
          # seconds
          response_time: 30,
          false_positive_rate: 0.05
        }

      :investigation ->
        %{
          evidence_collected: true,
          pattern_identified: true,
          # seconds
          response_time: 300
        }

      _ ->
        %{
          monitoring_enhanced: true,
          response_time: 60
        }
    end
  end

  defp generate_threat_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  # Analysis helper functions

  defp analyze_request_anomalies(request_data) do
    # Analyze request for suspicious patterns
    suspicious_indicators = [
      String.contains?(to_string(request_data), "script"),
      String.contains?(to_string(request_data), "union"),
      String.contains?(to_string(request_data), "../"),
      String.contains?(to_string(request_data), "eval")
    ]

    Enum.count(suspicious_indicators, & &1) / length(suspicious_indicators)
  end

  defp analyze_behavioral_anomalies(user_context) do
    # Simple behavioral analysis
    anomaly_score = 0.0

    # Check for time-based anomalies
    anomaly_score =
      if Map.get(user_context, :access_time_unusual, false) do
        anomaly_score + 0.3
      else
        anomaly_score
      end

    # Check for location anomalies
    anomaly_score =
      if Map.get(user_context, :location_unusual, false) do
        anomaly_score + 0.4
      else
        anomaly_score
      end

    # Check for device anomalies
    anomaly_score =
      if Map.get(user_context, :device_new, false) do
        anomaly_score + 0.2
      else
        anomaly_score
      end

    min(anomaly_score, 1.0)
  end

  defp calculate_request_anomaly(request_data, baseline_patterns) do
    if map_size(baseline_patterns) == 0 do
      # No baseline, assume medium anomaly
      0.5
    else
      # Compare request against baseline patterns
      similarity_scores =
        Enum.map(Map.values(baseline_patterns), fn pattern ->
          pattern_similarity(request_data, pattern)
        end)

      max_similarity =
        if Enum.empty?(similarity_scores), do: 0.0, else: Enum.max(similarity_scores)

      # High similarity = low anomaly
      1.0 - max_similarity
    end
  end

  defp calculate_behavioral_anomaly(user_context, baseline_patterns) do
    user_id = Map.get(user_context, :user_id)
    user_baseline = Map.get(baseline_patterns, user_id, %{})

    if map_size(user_baseline) == 0 do
      # No baseline, moderate anomaly
      0.4
    else
      calculate_deviation_score(user_context, user_baseline)
    end
  end

  defp calculate_temporal_anomaly(_user_context, _baseline_patterns) do
    current_hour =
      DateTime.utc_now()
      |> DateTime.to_time()
      |> Time.to_string()
      |> String.slice(0, 2)
      |> String.to_integer()

    # Simple time-based anomaly (higher risk during off-hours)
    cond do
      # Night hours
      current_hour < 6 or current_hour > 22 -> 0.6
      # Early/late hours
      current_hour < 8 or current_hour > 18 -> 0.3
      # Business hours
      true -> 0.1
    end
  end

  defp pattern_similarity(data1, data2) do
    # Simple similarity calculation
    string1 = to_string(data1)
    string2 = to_string(data2)

    # Use Jaro-Winkler similarity or simple overlap
    common_chars =
      String.graphemes(string1)
      |> Enum.filter(&String.contains?(string2, &1))
      |> length()

    max_length = max(String.length(string1), String.length(string2))
    if max_length > 0, do: common_chars / max_length, else: 0.0
  end

  defp calculate_deviation_score(user_context, baseline) do
    # Calculate how much current context deviates from user baseline
    deviations = []

    # Check access pattern deviation
    deviations =
      if Map.get(user_context, :access_pattern) != Map.get(baseline, :typical_access_pattern) do
        [0.3 | deviations]
      else
        deviations
      end

    # Check time deviation
    deviations =
      if Map.get(user_context, :unusual_time, false) do
        [0.4 | deviations]
      else
        deviations
      end

    if Enum.empty?(deviations), do: 0.0, else: Enum.sum(deviations) / length(deviations)
  end

  defp assess_baseline_quality(state) do
    patterns = Map.get(state, :threat_patterns, [])
    baselines = Map.get(state, :baseline_patterns, %{})

    pattern_quality = min(length(patterns) / 50.0, 1.0)
    baseline_quality = min(map_size(baselines) / 20.0, 1.0)

    (pattern_quality + baseline_quality) / 2
  end

  defp assess_data_completeness(request_data, user_context) do
    required_fields = [:user_id, :ip_address, :user_agent, :timestamp]
    available_fields = Map.keys(Map.merge(request_data, user_context))

    matching_fields = Enum.count(required_fields, &(&1 in available_fields))
    matching_fields / length(required_fields)
  end

  defp get_recent_threats(state, seconds_ago) do
    threat_patterns = Map.get(state, :threat_patterns, [])
    cutoff_time = DateTime.add(DateTime.utc_now(), -seconds_ago, :second)

    Enum.filter(threat_patterns, fn pattern ->
      DateTime.compare(pattern.timestamp, cutoff_time) == :gt
    end)
  end

  defp count_active_attack_patterns(state) do
    attack_patterns = Map.get(state, :attack_patterns, %{})
    Map.keys(attack_patterns) |> length()
  end

  defp similarity_score(data1, data2) do
    # Simple similarity calculation for attack correlation
    pattern_similarity(data1, data2)
  end
end
