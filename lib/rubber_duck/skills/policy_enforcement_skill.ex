defmodule RubberDuck.Skills.PolicyEnforcementSkill do
  @moduledoc """
  Policy enforcement skill with risk assessment and dynamic control.

  Provides capabilities for enforcing security policies, assessing permission risks,
  and adapting access controls based on contextual analysis.
  """

  use Jido.Skill,
    name: "policy_enforcement_skill",
    opts_key: :policy_enforcement_state,
    signal_patterns: [
      "policy.enforce_access",
      "policy.assess_risk",
      "policy.adjust_permissions",
      "policy.monitor_escalation"
    ]

  @doc """
  Enforce access control policies with contextual analysis.
  """
  def enforce_access(
        %{user_id: user_id, resource: resource, action: action, context: context} = _params,
        state
      ) do
    enforcement_result = %{
      user_id: user_id,
      resource: resource,
      action: action,
      access_granted: evaluate_access_permission(user_id, resource, action, context, state),
      risk_assessment: assess_access_risk(user_id, resource, action, context, state),
      policy_violations: check_policy_violations(user_id, resource, action, context, state),
      recommended_restrictions: suggest_access_restrictions(user_id, resource, context, state),
      confidence_score: calculate_enforcement_confidence(user_id, resource, state)
    }

    # Track enforcement decision for learning
    enforcement_history = Map.get(state, :enforcement_history, [])
    updated_history = [enforcement_result | enforcement_history] |> Enum.take(1000)

    new_state =
      state
      |> Map.put(:enforcement_history, updated_history)
      |> Map.put(:last_enforcement, DateTime.utc_now())

    {:ok, enforcement_result, new_state}
  end

  @doc """
  Assess permission risk for access requests.
  """
  def assess_risk(
        %{user_id: user_id, requested_permissions: permissions, context: context} = _params,
        state
      ) do
    risk_assessment = %{
      user_id: user_id,
      permission_risk_level: calculate_permission_risk_level(permissions, context, state),
      escalation_risk: assess_escalation_risk(user_id, permissions, context, state),
      context_anomalies: detect_context_anomalies(context, state),
      historical_behavior: analyze_historical_permission_behavior(user_id, state),
      recommended_mitigations: generate_risk_mitigations(permissions, context, state)
    }

    # Update risk profiles
    risk_profiles = Map.get(state, :risk_profiles, %{})
    updated_profiles = Map.put(risk_profiles, user_id, risk_assessment)

    new_state =
      state
      |> Map.put(:risk_profiles, updated_profiles)
      |> Map.put(:last_risk_assessment, DateTime.utc_now())

    {:ok, risk_assessment, new_state}
  end

  @doc """
  Adjust permissions based on dynamic risk assessment.
  """
  def adjust_permissions(
        %{user_id: user_id, current_permissions: current_perms, risk_context: context} = _params,
        state
      ) do
    adjustment_analysis = %{
      user_id: user_id,
      current_permissions: current_perms,
      suggested_adjustments:
        calculate_permission_adjustments(user_id, current_perms, context, state),
      adjustment_rationale: generate_adjustment_rationale(user_id, current_perms, context, state),
      impact_assessment: assess_adjustment_impact(current_perms, context),
      confidence_level: calculate_adjustment_confidence(user_id, context, state)
    }

    # Apply adjustments if auto-adjustment is enabled
    auto_adjust = Map.get(context, :auto_adjust, false)

    final_permissions =
      if auto_adjust do
        apply_permission_adjustments(current_perms, adjustment_analysis.suggested_adjustments)
      else
        current_perms
      end

    adjustment_result = %{
      previous_permissions: current_perms,
      adjusted_permissions: final_permissions,
      auto_applied: auto_adjust,
      adjustment_timestamp: DateTime.utc_now()
    }

    # Track adjustment history
    adjustment_history = Map.get(state, :adjustment_history, [])
    updated_history = [adjustment_result | adjustment_history] |> Enum.take(500)

    new_state =
      state
      |> Map.put(:adjustment_history, updated_history)
      |> Map.put(:last_adjustment, DateTime.utc_now())

    {:ok, %{analysis: adjustment_analysis, result: adjustment_result}, new_state}
  end

  @doc """
  Monitor privilege escalation attempts and respond.
  """
  def monitor_escalation(%{user_id: user_id, escalation_attempt: attempt_data} = _params, state) do
    escalation_analysis = %{
      user_id: user_id,
      escalation_type: classify_escalation_type(attempt_data),
      risk_level: assess_escalation_risk_level(attempt_data, state),
      legitimacy_score: evaluate_escalation_legitimacy(user_id, attempt_data, state),
      response_recommendation: recommend_escalation_response(attempt_data, state),
      monitoring_adjustments: suggest_monitoring_adjustments(user_id, attempt_data, state)
    }

    # Track escalation attempts
    escalation_attempts = Map.get(state, :escalation_attempts, [])
    updated_attempts = [escalation_analysis | escalation_attempts] |> Enum.take(200)

    # Update user risk profile based on escalation
    risk_profiles = Map.get(state, :risk_profiles, %{})
    updated_risk_profile = update_user_risk_profile(risk_profiles, user_id, escalation_analysis)

    new_state =
      state
      |> Map.put(:escalation_attempts, updated_attempts)
      |> Map.put(:risk_profiles, updated_risk_profile)
      |> Map.put(:last_escalation_monitoring, DateTime.utc_now())

    {:ok, escalation_analysis, new_state}
  end

  # Private helper functions

  defp evaluate_access_permission(user_id, resource, action, context, state) do
    # Check base permissions
    base_permission = check_base_permissions(user_id, resource, action)

    # Apply contextual adjustments
    contextual_adjustment = evaluate_contextual_factors(context, state)

    # Check risk-based restrictions
    risk_restrictions = evaluate_risk_restrictions(user_id, resource, action, state)

    # Combine all factors
    final_decision = base_permission and contextual_adjustment and not risk_restrictions

    final_decision
  end

  defp assess_access_risk(user_id, resource, action, context, state) do
    # Calculate risk factors
    user_risk = get_user_risk_level(user_id, state)
    resource_sensitivity = assess_resource_sensitivity(resource)
    action_risk = assess_action_risk(action)
    context_risk = assess_context_risk(context)

    # Combine risk factors
    combined_risk = (user_risk + resource_sensitivity + action_risk + context_risk) / 4

    categorize_risk_level(combined_risk)
  end

  defp check_policy_violations(user_id, resource, action, context, state) do
    active_policies = Map.get(state, :active_policies, default_policies())

    violations = []

    # Check time-based violations
    violations = check_time_violations(context, active_policies, violations)

    # Check resource access violations
    violations = check_resource_violations(user_id, resource, active_policies, violations)

    # Check action restrictions
    violations = check_action_violations(action, context, active_policies, violations)

    violations
  end

  defp suggest_access_restrictions(user_id, resource, context, state) do
    risk_level = get_user_risk_level(user_id, state)
    resource_sensitivity = assess_resource_sensitivity(resource)

    restrictions = []

    restrictions =
      case risk_level do
        score when score > 0.8 ->
          ["Require additional verification", "Limit session duration" | restrictions]

        score when score > 0.6 ->
          ["Enable enhanced logging", "Require supervisor approval" | restrictions]

        score when score > 0.4 ->
          ["Increase monitoring frequency" | restrictions]

        _ ->
          restrictions
      end

    restrictions =
      cond do
        resource_sensitivity > 0.8 ->
          ["Require multi-factor authentication", "Enable audit trail" | restrictions]

        resource_sensitivity > 0.5 ->
          ["Enable access logging" | restrictions]

        true ->
          restrictions
      end

    if Enum.empty?(restrictions) do
      ["No additional restrictions required"]
    else
      restrictions
    end
  end

  defp calculate_enforcement_confidence(user_id, resource, state) do
    enforcement_history = Map.get(state, :enforcement_history, [])

    # Find similar enforcement decisions
    similar_enforcements =
      Enum.filter(enforcement_history, fn enforcement ->
        enforcement.user_id == user_id and enforcement.resource == resource
      end)

    confidence_factors = [
      # Historical data
      min(length(similar_enforcements) / 10.0, 1.0),
      # Overall experience
      min(length(enforcement_history) / 100.0, 1.0)
    ]

    Enum.sum(confidence_factors) / length(confidence_factors)
  end

  defp calculate_permission_risk_level(permissions, context, state) do
    # Assess risk of requested permissions
    permission_risks =
      Enum.map(permissions, fn permission ->
        assess_individual_permission_risk(permission, context, state)
      end)

    if Enum.empty?(permission_risks) do
      0.0
    else
      # Highest risk permission determines overall risk
      Enum.max(permission_risks)
    end
  end

  defp assess_escalation_risk(user_id, permissions, context, state) do
    current_user_level = get_user_permission_level(user_id, state)
    requested_level = calculate_requested_permission_level(permissions)

    escalation_magnitude = requested_level - current_user_level
    context_risk = assess_context_risk(context)

    # Higher escalation + higher context risk = higher escalation risk
    escalation_risk = escalation_magnitude * 0.7 + context_risk * 0.3

    min(escalation_risk, 1.0)
  end

  defp detect_context_anomalies(context, state) do
    baseline_contexts = Map.get(state, :baseline_contexts, %{})

    anomalies = []

    # Check time anomalies
    anomalies =
      if unusual_access_time?(context) do
        [:unusual_access_time | anomalies]
      else
        anomalies
      end

    # Check location anomalies
    anomalies =
      if unusual_location?(context, baseline_contexts) do
        [:unusual_location | anomalies]
      else
        anomalies
      end

    # Check device anomalies
    anomalies =
      if unusual_device?(context, baseline_contexts) do
        [:unusual_device | anomalies]
      else
        anomalies
      end

    anomalies
  end

  defp analyze_historical_permission_behavior(user_id, state) do
    enforcement_history = Map.get(state, :enforcement_history, [])

    user_history = Enum.filter(enforcement_history, &(&1.user_id == user_id))

    if Enum.empty?(user_history) do
      %{pattern: :no_history}
    else
      %{
        total_requests: length(user_history),
        approval_rate: calculate_approval_rate(user_history),
        common_resources: extract_common_resources(user_history),
        risk_trend: calculate_risk_trend(user_history)
      }
    end
  end

  defp generate_risk_mitigations(permissions, context, _state) do
    mitigations = []

    # High-risk permission mitigations
    high_risk_perms = Enum.filter(permissions, &(assess_permission_base_risk(&1) > 0.7))

    mitigations =
      if Enum.empty?(high_risk_perms) do
        mitigations
      else
        ["Require supervisor approval for high-risk permissions" | mitigations]
      end

    # Context-based mitigations
    mitigations =
      if Map.get(context, :off_hours, false) do
        ["Implement additional verification for off-hours access" | mitigations]
      else
        mitigations
      end

    mitigations =
      if Map.get(context, :remote_access, false) do
        ["Enable enhanced monitoring for remote access" | mitigations]
      else
        mitigations
      end

    if Enum.empty?(mitigations) do
      ["Standard monitoring sufficient"]
    else
      mitigations
    end
  end

  defp calculate_permission_adjustments(user_id, current_perms, context, state) do
    risk_level = get_user_risk_level(user_id, state)
    context_risk = assess_context_risk(context)

    combined_risk = (risk_level + context_risk) / 2

    case combined_risk do
      score when score > 0.8 ->
        %{action: :restrict_permissions, level: :high}

      score when score > 0.6 ->
        %{action: :add_restrictions, level: :medium}

      score when score > 0.4 ->
        %{action: :enhance_monitoring, level: :low}

      _ ->
        %{action: :maintain_current, level: :none}
    end
  end

  defp generate_adjustment_rationale(user_id, _current_perms, context, state) do
    risk_factors = []

    risk_factors =
      if get_user_risk_level(user_id, state) > 0.6 do
        ["User has elevated risk profile" | risk_factors]
      else
        risk_factors
      end

    risk_factors =
      if Map.get(context, :suspicious_activity, false) do
        ["Suspicious activity detected in current session" | risk_factors]
      else
        risk_factors
      end

    risk_factors =
      if Map.get(context, :off_hours, false) do
        ["Off-hours access increases security risk" | risk_factors]
      else
        risk_factors
      end

    if Enum.empty?(risk_factors) do
      "No significant risk factors identified"
    else
      "Risk factors: " <> Enum.join(risk_factors, ", ")
    end
  end

  defp assess_adjustment_impact(current_perms, _context) do
    %{
      affected_permissions: length(current_perms),
      user_impact: :moderate,
      security_improvement: :significant,
      operational_impact: :minimal
    }
  end

  defp calculate_adjustment_confidence(user_id, context, state) do
    user_history_depth = get_user_history_depth(user_id, state)
    context_completeness = assess_context_completeness(context)

    (user_history_depth + context_completeness) / 2
  end

  # Classification and assessment helpers

  defp classify_escalation_type(attempt_data) do
    cond do
      Map.get(attempt_data, :admin_access_requested, false) -> :admin_escalation
      Map.get(attempt_data, :sudo_attempted, false) -> :sudo_escalation
      Map.get(attempt_data, :role_change_requested, false) -> :role_escalation
      Map.get(attempt_data, :permission_bypass_attempted, false) -> :bypass_attempt
      true -> :unknown_escalation
    end
  end

  defp assess_escalation_risk_level(attempt_data, state) do
    escalation_type = classify_escalation_type(attempt_data)
    recent_attempts = count_recent_escalation_attempts(state)

    base_risk =
      case escalation_type do
        :admin_escalation -> 0.9
        :sudo_escalation -> 0.8
        :role_escalation -> 0.6
        :bypass_attempt -> 0.7
        _ -> 0.4
      end

    # Increase risk based on recent attempts
    frequency_multiplier = min(1.0 + recent_attempts * 0.2, 2.0)

    min(base_risk * frequency_multiplier, 1.0)
  end

  defp evaluate_escalation_legitimacy(user_id, attempt_data, state) do
    # Check if escalation request is legitimate based on user patterns
    user_history = get_user_escalation_history(user_id, state)

    legitimacy_factors = [
      check_business_justification(attempt_data),
      check_timing_legitimacy(attempt_data),
      check_historical_pattern(user_history, attempt_data),
      check_approval_workflow(attempt_data)
    ]

    legitimate_factors = Enum.count(legitimacy_factors, & &1)
    legitimate_factors / length(legitimacy_factors)
  end

  defp recommend_escalation_response(attempt_data, state) do
    risk_level = assess_escalation_risk_level(attempt_data, state)
    escalation_type = classify_escalation_type(attempt_data)

    case {escalation_type, risk_level} do
      {_, risk} when risk > 0.8 ->
        :immediate_denial_and_alert

      {:admin_escalation, risk} when risk > 0.6 ->
        :require_supervisor_approval

      {:sudo_escalation, risk} when risk > 0.6 ->
        :require_additional_verification

      {_, risk} when risk > 0.4 ->
        :enhanced_monitoring

      _ ->
        :standard_processing
    end
  end

  defp suggest_monitoring_adjustments(user_id, attempt_data, state) do
    escalation_type = classify_escalation_type(attempt_data)
    user_risk = get_user_risk_level(user_id, state)

    adjustments = []

    adjustments =
      case escalation_type do
        :admin_escalation ->
          ["Enable privileged access monitoring", "Activate session recording" | adjustments]

        :sudo_escalation ->
          ["Monitor command execution", "Enable file access tracking" | adjustments]

        _ ->
          ["Increase activity logging" | adjustments]
      end

    adjustments =
      if user_risk > 0.6 do
        ["Implement real-time behavior analysis" | adjustments]
      else
        adjustments
      end

    adjustments
  end

  # Permission evaluation helpers

  defp check_base_permissions(user_id, resource, action) do
    # TODO: Integrate with actual Ash authorization system
    # For now, simulate permission checking
    case {resource, action} do
      {:admin_panel, _} -> user_id in get_admin_users()
      {:user_data, :read} -> true
      {:user_data, :write} -> user_id in get_privileged_users()
      {:system_config, _} -> user_id in get_admin_users()
      _ -> true
    end
  end

  defp evaluate_contextual_factors(context, _state) do
    # Evaluate context factors that might affect access
    risk_factors = [
      Map.get(context, :off_hours, false),
      Map.get(context, :unusual_location, false),
      Map.get(context, :new_device, false),
      Map.get(context, :suspicious_activity, false)
    ]

    risk_count = Enum.count(risk_factors, & &1)

    # Allow access if risk factors are minimal
    risk_count < 2
  end

  defp evaluate_risk_restrictions(user_id, resource, action, state) do
    user_risk = get_user_risk_level(user_id, state)
    resource_sensitivity = assess_resource_sensitivity(resource)
    action_risk = assess_action_risk(action)

    # Apply restrictions if combined risk is high
    combined_risk = (user_risk + resource_sensitivity + action_risk) / 3

    combined_risk > 0.7
  end

  defp get_user_risk_level(user_id, state) do
    risk_profiles = Map.get(state, :risk_profiles, %{})

    case Map.get(risk_profiles, user_id) do
      # Default moderate risk for unknown users
      nil -> 0.3
      profile -> Map.get(profile, :permission_risk_level, 0.3)
    end
  end

  defp assess_resource_sensitivity(resource) do
    case resource do
      :admin_panel -> 0.9
      :user_data -> 0.7
      :system_config -> 0.95
      :financial_data -> 0.85
      :public_data -> 0.2
      _ -> 0.5
    end
  end

  defp assess_action_risk(action) do
    case action do
      :delete -> 0.8
      :modify -> 0.6
      :create -> 0.4
      :read -> 0.2
      :list -> 0.1
      _ -> 0.3
    end
  end

  defp assess_context_risk(context) do
    risk_indicators = [
      Map.get(context, :off_hours, false),
      Map.get(context, :remote_access, false),
      Map.get(context, :new_device, false),
      Map.get(context, :unusual_location, false)
    ]

    risk_count = Enum.count(risk_indicators, & &1)
    risk_count / length(risk_indicators)
  end

  defp categorize_risk_level(risk_score) do
    cond do
      risk_score > 0.8 -> :critical
      risk_score > 0.6 -> :high
      risk_score > 0.4 -> :medium
      risk_score > 0.2 -> :low
      true -> :minimal
    end
  end

  defp default_policies do
    %{
      off_hours_restrictions: true,
      admin_approval_required: [:admin_panel, :system_config],
      mfa_required_resources: [:financial_data, :system_config],
      session_timeout_minutes: 60,
      max_failed_attempts: 3
    }
  end

  defp check_time_violations(context, policies, violations) do
    if Map.get(policies, :off_hours_restrictions, false) and Map.get(context, :off_hours, false) do
      [:off_hours_access | violations]
    else
      violations
    end
  end

  defp check_resource_violations(user_id, resource, policies, violations) do
    admin_required = Map.get(policies, :admin_approval_required, [])

    if resource in admin_required and user_id not in get_admin_users() do
      [:admin_approval_required | violations]
    else
      violations
    end
  end

  defp check_action_violations(action, context, policies, violations) do
    if action in [:delete, :modify] and Map.get(context, :bulk_operation, false) do
      [:bulk_operation_restriction | violations]
    else
      violations
    end
  end

  defp apply_permission_adjustments(current_perms, adjustments) do
    case adjustments.action do
      :restrict_permissions ->
        Enum.filter(current_perms, &(assess_permission_base_risk(&1) < 0.6))

      :add_restrictions ->
        Enum.map(current_perms, &add_permission_restrictions/1)

      _ ->
        current_perms
    end
  end

  defp assess_individual_permission_risk(permission, _context, _state) do
    # Simple permission risk assessment
    case permission do
      :admin_access -> 0.9
      :delete_access -> 0.8
      :modify_access -> 0.6
      :create_access -> 0.4
      :read_access -> 0.2
      _ -> 0.3
    end
  end

  defp get_user_permission_level(user_id, _state) do
    # TODO: Integrate with actual user role system
    cond do
      user_id in get_admin_users() -> 0.9
      user_id in get_privileged_users() -> 0.7
      true -> 0.3
    end
  end

  defp calculate_requested_permission_level(permissions) do
    if Enum.empty?(permissions) do
      0.0
    else
      permission_levels = Enum.map(permissions, &assess_permission_base_risk/1)
      Enum.max(permission_levels)
    end
  end

  defp count_recent_escalation_attempts(state) do
    escalation_attempts = Map.get(state, :escalation_attempts, [])

    # Last hour
    recent_cutoff = DateTime.add(DateTime.utc_now(), -3600, :second)

    Enum.count(escalation_attempts, fn attempt ->
      attempt_time = Map.get(attempt, :timestamp, DateTime.utc_now())
      DateTime.compare(attempt_time, recent_cutoff) == :gt
    end)
  end

  defp get_user_escalation_history(user_id, state) do
    escalation_attempts = Map.get(state, :escalation_attempts, [])

    Enum.filter(escalation_attempts, &(&1.user_id == user_id))
    # Last 20 attempts
    |> Enum.take(20)
  end

  defp check_business_justification(attempt_data) do
    Map.get(attempt_data, :business_justification_provided, false)
  end

  defp check_timing_legitimacy(attempt_data) do
    # Check if escalation timing is reasonable (business hours)
    not Map.get(attempt_data, :off_hours_request, false)
  end

  defp check_historical_pattern(user_history, attempt_data) do
    if Enum.empty?(user_history) do
      # No pattern to verify
      false
    else
      # Check if similar escalations were legitimate in the past
      escalation_type = classify_escalation_type(attempt_data)

      similar_attempts =
        Enum.filter(user_history, fn attempt ->
          classify_escalation_type(attempt) == escalation_type
        end)

      legitimate_rate =
        if Enum.empty?(similar_attempts) do
          0.5
        else
          legitimate_count = Enum.count(similar_attempts, &Map.get(&1, :was_legitimate, false))
          legitimate_count / length(similar_attempts)
        end

      legitimate_rate > 0.6
    end
  end

  defp check_approval_workflow(attempt_data) do
    Map.get(attempt_data, :approval_workflow_followed, false)
  end

  defp update_user_risk_profile(risk_profiles, user_id, escalation_analysis) do
    current_profile = Map.get(risk_profiles, user_id, %{permission_risk_level: 0.3})

    # Adjust risk based on escalation attempt
    risk_adjustment =
      case escalation_analysis.escalation_type do
        :admin_escalation -> 0.2
        :sudo_escalation -> 0.15
        :role_escalation -> 0.1
        _ -> 0.05
      end

    # Increase or decrease risk based on legitimacy
    adjusted_risk =
      if escalation_analysis.legitimacy_score > 0.7 do
        # Legitimate escalation, slight risk reduction
        max(current_profile.permission_risk_level - 0.05, 0.0)
      else
        # Questionable escalation, increase risk
        min(current_profile.permission_risk_level + risk_adjustment, 1.0)
      end

    updated_profile = Map.put(current_profile, :permission_risk_level, adjusted_risk)
    Map.put(risk_profiles, user_id, updated_profile)
  end

  # Helper functions for user categories

  defp get_admin_users do
    # TODO: Integrate with actual user role system
    ["admin_user_1", "admin_user_2"]
  end

  defp get_privileged_users do
    # TODO: Integrate with actual user role system
    ["privileged_user_1", "privileged_user_2", "privileged_user_3"]
  end

  # Context analysis helpers

  defp unusual_access_time?(_context) do
    # Simple time-based anomaly detection
    current_hour =
      DateTime.utc_now()
      |> DateTime.to_time()
      |> Time.to_string()
      |> String.slice(0, 2)
      |> String.to_integer()

    current_hour < 6 or current_hour > 22
  end

  defp unusual_location?(context, _baseline_contexts) do
    # TODO: Implement sophisticated location anomaly detection
    Map.get(context, :location_flagged, false)
  end

  defp unusual_device?(context, _baseline_contexts) do
    # TODO: Implement device fingerprint anomaly detection
    Map.get(context, :device_new, false)
  end

  defp calculate_approval_rate(user_history) do
    if Enum.empty?(user_history) do
      0.0
    else
      approved_count = Enum.count(user_history, & &1.access_granted)
      approved_count / length(user_history)
    end
  end

  defp extract_common_resources(user_history) do
    user_history
    |> Enum.map(& &1.resource)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_resource, count} -> count end, :desc)
    |> Enum.take(5)
  end

  defp calculate_risk_trend(user_history) do
    if length(user_history) < 5 do
      :insufficient_data
    else
      recent_risks = Enum.take(user_history, 5) |> Enum.map(&Map.get(&1, :risk_assessment, 0.3))

      older_risks =
        Enum.drop(user_history, 5)
        |> Enum.take(5)
        |> Enum.map(&Map.get(&1, :risk_assessment, 0.3))

      recent_avg = Enum.sum(recent_risks) / length(recent_risks)
      older_avg = Enum.sum(older_risks) / length(older_risks)

      cond do
        recent_avg > older_avg + 0.1 -> :increasing
        recent_avg < older_avg - 0.1 -> :decreasing
        true -> :stable
      end
    end
  end

  defp assess_permission_base_risk(permission) do
    case permission do
      :admin_access -> 0.9
      :delete_access -> 0.8
      :system_modify -> 0.85
      :user_modify -> 0.6
      :data_export -> 0.7
      :read_access -> 0.2
      _ -> 0.4
    end
  end

  defp add_permission_restrictions(permission) do
    # Add restrictions to permission
    %{
      permission: permission,
      restrictions: [:enhanced_logging, :time_limited],
      restricted_at: DateTime.utc_now()
    }
  end

  defp get_user_history_depth(user_id, state) do
    enforcement_history = Map.get(state, :enforcement_history, [])
    user_history = Enum.filter(enforcement_history, &(&1.user_id == user_id))

    min(length(user_history) / 20.0, 1.0)
  end

  defp assess_context_completeness(context) do
    required_fields = [:ip_address, :user_agent, :session_id, :timestamp]
    available_fields = Map.keys(context)

    matching_fields = Enum.count(required_fields, &(&1 in available_fields))
    matching_fields / length(required_fields)
  end
end
