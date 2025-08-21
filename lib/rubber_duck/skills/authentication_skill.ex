defmodule RubberDuck.Skills.AuthenticationSkill do
  @moduledoc """
  Authentication skill with session management and behavioral analysis.

  Provides capabilities for intelligent session management, behavioral
  authentication, and adaptive security policy enforcement.
  """

  use Jido.Skill,
    name: "authentication_skill",
    opts_key: :authentication_state,
    signal_patterns: [
      "auth.enhance_session",
      "auth.analyze_behavior",
      "auth.adjust_security",
      "auth.validate_context"
    ]

  alias RubberDuck.Accounts.User
  alias RubberDuck.Repo

  @doc """
  Enhance authentication session with behavioral analysis.
  """
  def enhance_session(
        %{user_id: user_id, session_data: session_data, request_context: request_context} =
          _params,
        state
      ) do
    # Analyze current session for security enhancement opportunities
    session_analysis = %{
      user_id: user_id,
      behavioral_score: calculate_behavioral_score(user_id, request_context, state),
      session_risk_level: assess_session_risk(session_data, request_context),
      authentication_strength: evaluate_auth_strength(session_data),
      recommended_enhancements: suggest_session_enhancements(session_data, request_context),
      confidence: calculate_enhancement_confidence(user_id, state)
    }

    # Update user behavioral baselines
    user_baselines = Map.get(state, :user_baselines, %{})
    updated_baseline = update_user_baseline(user_baselines, user_id, request_context)

    new_state =
      state
      |> Map.put(:user_baselines, updated_baseline)
      |> Map.put(:last_session_analysis, session_analysis)

    {:ok, session_analysis, new_state}
  end

  @doc """
  Analyze user behavior patterns for authentication decisions.
  """
  def analyze_behavior(%{user_id: user_id, current_behavior: behavior_data} = _params, state) do
    behavior_analysis = %{
      user_id: user_id,
      behavior_pattern: classify_behavior_pattern(behavior_data),
      anomaly_score: detect_behavior_anomalies(user_id, behavior_data, state),
      trust_score: calculate_trust_score(user_id, behavior_data, state),
      risk_indicators: identify_risk_indicators(behavior_data),
      authentication_recommendation: recommend_auth_level(user_id, behavior_data, state)
    }

    # Store behavior analysis for learning
    behavior_history = Map.get(state, :behavior_history, [])
    updated_history = [behavior_analysis | behavior_history] |> Enum.take(1000)

    new_state =
      state
      |> Map.put(:behavior_history, updated_history)
      |> Map.put(:last_behavior_analysis, DateTime.utc_now())

    {:ok, behavior_analysis, new_state}
  end

  @doc """
  Adjust security policies based on risk assessment.
  """
  def adjust_security(%{risk_level: risk_level, context: context} = _params, state) do
    current_policies = Map.get(state, :security_policies, default_security_policies())

    adjusted_policies =
      case risk_level do
        :critical ->
          enhance_policies_for_critical_risk(current_policies)

        :high ->
          enhance_policies_for_high_risk(current_policies)

        :medium ->
          moderate_security_enhancements(current_policies)

        :low ->
          standard_security_policies(current_policies)

        _ ->
          current_policies
      end

    policy_change = %{
      previous_policies: current_policies,
      adjusted_policies: adjusted_policies,
      risk_level: risk_level,
      context: context,
      adjustment_timestamp: DateTime.utc_now()
    }

    # Track policy changes for learning
    policy_history = Map.get(state, :policy_history, [])
    updated_history = [policy_change | policy_history] |> Enum.take(100)

    new_state =
      state
      |> Map.put(:security_policies, adjusted_policies)
      |> Map.put(:policy_history, updated_history)
      |> Map.put(:last_policy_adjustment, DateTime.utc_now())

    {:ok, adjusted_policies, new_state}
  end

  @doc """
  Validate authentication context for security compliance.
  """
  def validate_context(%{user_id: user_id, auth_context: auth_context} = _params, state) do
    validation_result = %{
      user_id: user_id,
      context_valid: validate_auth_context(auth_context),
      security_compliance: check_security_compliance(auth_context, state),
      behavioral_consistency: check_behavioral_consistency(user_id, auth_context, state),
      recommended_actions: generate_context_recommendations(auth_context, state),
      validation_confidence: calculate_validation_confidence(user_id, auth_context, state)
    }

    {:ok, validation_result, state}
  end

  # Private helper functions

  defp calculate_behavioral_score(user_id, request_context, state) do
    user_baselines = Map.get(state, :user_baselines, %{})

    case Map.get(user_baselines, user_id) do
      nil ->
        # No baseline, neutral score
        0.5

      baseline ->
        similarity_score = calculate_context_similarity(request_context, baseline)
        # Higher similarity = higher behavioral score
        similarity_score
    end
  end

  defp assess_session_risk(session_data, request_context) do
    risk_factors = []

    # Check session age
    risk_factors =
      if Map.get(session_data, :age_hours, 0) > 24 do
        [:session_too_old | risk_factors]
      else
        risk_factors
      end

    # Check IP consistency
    risk_factors =
      if Map.get(request_context, :ip_changed, false) do
        [:ip_address_changed | risk_factors]
      else
        risk_factors
      end

    # Check device consistency
    risk_factors =
      if Map.get(request_context, :device_changed, false) do
        [:device_changed | risk_factors]
      else
        risk_factors
      end

    case length(risk_factors) do
      0 -> :low
      1 -> :medium
      2 -> :high
      _ -> :critical
    end
  end

  defp evaluate_auth_strength(session_data) do
    strength_factors = %{
      mfa_enabled: Map.get(session_data, :mfa_verified, false),
      strong_password: Map.get(session_data, :password_strength, :medium) == :strong,
      recent_verification: check_recent_verification(session_data),
      secure_channel: Map.get(session_data, :https_used, true)
    }

    enabled_factors = Enum.count(Map.values(strength_factors), & &1)
    total_factors = map_size(strength_factors)

    strength_score = enabled_factors / total_factors

    cond do
      strength_score > 0.8 -> :strong
      strength_score > 0.6 -> :moderate
      strength_score > 0.4 -> :weak
      true -> :very_weak
    end
  end

  defp suggest_session_enhancements(session_data, request_context) do
    suggestions = []

    suggestions =
      if Map.get(session_data, :mfa_verified, false) do
        suggestions
      else
        ["Enable multi-factor authentication" | suggestions]
      end

    suggestions =
      if Map.get(request_context, :suspicious_activity, false) do
        ["Require additional verification" | suggestions]
      else
        suggestions
      end

    suggestions =
      if Map.get(session_data, :age_hours, 0) > 12 do
        ["Consider session renewal" | suggestions]
      else
        suggestions
      end

    if Enum.empty?(suggestions) do
      ["Session security is adequate"]
    else
      suggestions
    end
  end

  defp calculate_enhancement_confidence(user_id, state) do
    user_baselines = Map.get(state, :user_baselines, %{})
    behavior_history = Map.get(state, :behavior_history, [])

    baseline_quality = if Map.has_key?(user_baselines, user_id), do: 0.7, else: 0.3
    history_depth = min(length(behavior_history) / 50.0, 1.0)

    (baseline_quality + history_depth) / 2
  end

  defp update_user_baseline(user_baselines, user_id, request_context) do
    current_baseline =
      Map.get(user_baselines, user_id, %{
        access_patterns: [],
        typical_times: [],
        common_ips: [],
        device_fingerprints: []
      })

    updated_baseline = %{
      access_patterns: update_access_patterns(current_baseline.access_patterns, request_context),
      typical_times: update_typical_times(current_baseline.typical_times, request_context),
      common_ips: update_common_ips(current_baseline.common_ips, request_context),
      device_fingerprints:
        update_device_fingerprints(current_baseline.device_fingerprints, request_context),
      last_updated: DateTime.utc_now()
    }

    Map.put(user_baselines, user_id, updated_baseline)
  end

  defp classify_behavior_pattern(behavior_data) do
    cond do
      Map.get(behavior_data, :rapid_requests, false) -> :automated_behavior
      Map.get(behavior_data, :unusual_timing, false) -> :temporal_anomaly
      Map.get(behavior_data, :new_location, false) -> :location_anomaly
      Map.get(behavior_data, :new_device, false) -> :device_anomaly
      true -> :normal_behavior
    end
  end

  defp detect_behavior_anomalies(user_id, behavior_data, state) do
    user_baselines = Map.get(state, :user_baselines, %{})

    case Map.get(user_baselines, user_id) do
      nil ->
        # No baseline, assume moderate anomaly
        0.3

      baseline ->
        calculate_behavioral_deviation(behavior_data, baseline)
    end
  end

  defp calculate_trust_score(user_id, _behavior_data, state) do
    behavior_history = Map.get(state, :behavior_history, [])

    user_behavior_history = Enum.filter(behavior_history, &(&1.user_id == user_id))

    if Enum.empty?(user_behavior_history) do
      # No history, neutral trust
      0.5
    else
      # Calculate trust based on historical behavior consistency
      recent_behaviors = Enum.take(user_behavior_history, 10)
      anomaly_scores = Enum.map(recent_behaviors, & &1.anomaly_score)
      avg_anomaly = Enum.sum(anomaly_scores) / length(anomaly_scores)

      # Lower anomaly = higher trust
      1.0 - avg_anomaly
    end
  end

  defp identify_risk_indicators(behavior_data) do
    indicators = []

    indicators =
      if Map.get(behavior_data, :off_hours_access, false) do
        [:off_hours_access | indicators]
      else
        indicators
      end

    indicators =
      if Map.get(behavior_data, :multiple_failed_attempts, false) do
        [:failed_authentication_attempts | indicators]
      else
        indicators
      end

    indicators =
      if Map.get(behavior_data, :privilege_escalation_attempt, false) do
        [:privilege_escalation | indicators]
      else
        indicators
      end

    indicators
  end

  defp recommend_auth_level(user_id, behavior_data, state) do
    trust_score = calculate_trust_score(user_id, behavior_data, state)
    anomaly_score = detect_behavior_anomalies(user_id, behavior_data, state)

    combined_score = trust_score * 0.7 + (1.0 - anomaly_score) * 0.3

    cond do
      combined_score > 0.8 -> :standard
      combined_score > 0.6 -> :elevated
      combined_score > 0.4 -> :high
      true -> :maximum
    end
  end

  # Policy helper functions

  defp default_security_policies do
    %{
      session_timeout_minutes: 120,
      mfa_required: false,
      ip_validation: false,
      device_tracking: true,
      suspicious_activity_monitoring: true
    }
  end

  defp enhance_policies_for_critical_risk(policies) do
    policies
    |> Map.put(:session_timeout_minutes, 15)
    |> Map.put(:mfa_required, true)
    |> Map.put(:ip_validation, true)
    |> Map.put(:require_reverification, true)
  end

  defp enhance_policies_for_high_risk(policies) do
    policies
    |> Map.put(:session_timeout_minutes, 30)
    |> Map.put(:mfa_required, true)
    |> Map.put(:enhanced_logging, true)
  end

  defp moderate_security_enhancements(policies) do
    policies
    |> Map.put(:session_timeout_minutes, 60)
    |> Map.put(:enhanced_monitoring, true)
  end

  defp standard_security_policies(policies) do
    policies
    |> Map.put(:session_timeout_minutes, 120)
    |> Map.put(:mfa_required, false)
  end

  # Validation helper functions

  defp validate_auth_context(auth_context) do
    required_fields = [:user_id, :session_id, :ip_address, :user_agent]

    missing_fields =
      Enum.filter(required_fields, fn field ->
        not Map.has_key?(auth_context, field) or Map.get(auth_context, field) == nil
      end)

    Enum.empty?(missing_fields)
  end

  defp check_security_compliance(auth_context, state) do
    policies = Map.get(state, :security_policies, default_security_policies())

    compliance_checks = %{
      ip_validation: check_ip_compliance(auth_context, policies),
      device_tracking: check_device_compliance(auth_context, policies),
      session_timeout: check_timeout_compliance(auth_context, policies)
    }

    failed_checks = Enum.filter(Map.values(compliance_checks), &(&1 == false)) |> length()
    total_checks = map_size(compliance_checks)

    compliance_score = (total_checks - failed_checks) / total_checks

    cond do
      compliance_score == 1.0 -> :fully_compliant
      compliance_score > 0.8 -> :mostly_compliant
      compliance_score > 0.6 -> :partially_compliant
      true -> :non_compliant
    end
  end

  defp check_behavioral_consistency(user_id, auth_context, state) do
    user_baselines = Map.get(state, :user_baselines, %{})

    case Map.get(user_baselines, user_id) do
      nil ->
        :no_baseline

      baseline ->
        consistency_score = calculate_context_similarity(auth_context, baseline)

        cond do
          consistency_score > 0.8 -> :highly_consistent
          consistency_score > 0.6 -> :moderately_consistent
          consistency_score > 0.4 -> :somewhat_consistent
          true -> :inconsistent
        end
    end
  end

  defp generate_context_recommendations(auth_context, state) do
    recommendations = []

    recommendations =
      if validate_auth_context(auth_context) do
        recommendations
      else
        ["Complete authentication context validation" | recommendations]
      end

    recommendations =
      if check_security_compliance(auth_context, state) != :fully_compliant do
        ["Address security policy compliance issues" | recommendations]
      else
        recommendations
      end

    if Enum.empty?(recommendations) do
      ["Authentication context is valid"]
    else
      recommendations
    end
  end

  defp calculate_validation_confidence(user_id, auth_context, state) do
    baseline_confidence =
      if Map.has_key?(Map.get(state, :user_baselines, %{}), user_id) do
        0.8
      else
        0.4
      end

    context_completeness = if validate_auth_context(auth_context), do: 1.0, else: 0.5

    (baseline_confidence + context_completeness) / 2
  end

  # Helper functions for behavioral analysis

  defp calculate_context_similarity(context1, context2)
       when is_map(context1) and is_map(context2) do
    # Simple context similarity calculation
    common_keys =
      MapSet.intersection(MapSet.new(Map.keys(context1)), MapSet.new(Map.keys(context2)))

    all_keys = MapSet.union(MapSet.new(Map.keys(context1)), MapSet.new(Map.keys(context2)))

    if MapSet.size(all_keys) == 0 do
      1.0
    else
      MapSet.size(common_keys) / MapSet.size(all_keys)
    end
  end

  defp calculate_context_similarity(_context1, _context2), do: 0.0

  defp calculate_behavioral_deviation(behavior_data, baseline) do
    # Calculate deviation from established baseline
    deviations = []

    # Time-based deviation
    deviations =
      if Map.get(behavior_data, :access_time) in Map.get(baseline, :typical_times, []) do
        deviations
      else
        [0.3 | deviations]
      end

    # Location-based deviation
    deviations =
      if Map.get(behavior_data, :ip_address) in Map.get(baseline, :common_ips, []) do
        deviations
      else
        [0.4 | deviations]
      end

    if Enum.empty?(deviations), do: 0.0, else: Enum.sum(deviations) / length(deviations)
  end

  defp check_recent_verification(session_data) do
    last_verification = Map.get(session_data, :last_verification)

    if last_verification do
      minutes_since = DateTime.diff(DateTime.utc_now(), last_verification, :minute)
      # Recent if within 30 minutes
      minutes_since < 30
    else
      false
    end
  end

  # Baseline update functions

  defp update_access_patterns(patterns, context) do
    new_pattern = Map.get(context, :access_pattern, "unknown")
    [new_pattern | patterns] |> Enum.uniq() |> Enum.take(20)
  end

  defp update_typical_times(times, _context) do
    current_hour =
      DateTime.utc_now() |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 2)

    [current_hour | times] |> Enum.uniq() |> Enum.take(24)
  end

  defp update_common_ips(ips, context) do
    new_ip = Map.get(context, :ip_address)
    if new_ip, do: [new_ip | ips] |> Enum.uniq() |> Enum.take(10), else: ips
  end

  defp update_device_fingerprints(fingerprints, context) do
    new_fingerprint = Map.get(context, :device_fingerprint)

    if new_fingerprint,
      do: [new_fingerprint | fingerprints] |> Enum.uniq() |> Enum.take(5),
      else: fingerprints
  end

  # Compliance checking functions

  defp check_ip_compliance(auth_context, policies) do
    if Map.get(policies, :ip_validation, false) do
      Map.has_key?(auth_context, :ip_address) and Map.get(auth_context, :ip_address) != nil
    else
      # Not required
      true
    end
  end

  defp check_device_compliance(auth_context, policies) do
    if Map.get(policies, :device_tracking, false) do
      Map.has_key?(auth_context, :device_fingerprint)
    else
      # Not required
      true
    end
  end

  defp check_timeout_compliance(auth_context, policies) do
    session_age = Map.get(auth_context, :session_age_minutes, 0)
    timeout_limit = Map.get(policies, :session_timeout_minutes, 120)

    session_age < timeout_limit
  end
end
