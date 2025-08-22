defmodule RubberDuck.Actions.AssessPermissionRisk do
  @moduledoc """
  Permission risk assessment action with context awareness and behavioral analysis.

  This action provides comprehensive permission risk evaluation with contextual
  analysis, historical behavior assessment, and actionable risk mitigation recommendations.
  """

  use Jido.Action,
    name: "assess_permission_risk",
    schema: [
      user_id: [type: :string, required: true],
      requested_permissions: [type: :list, required: true],
      access_context: [type: :map, required: true],
      assessment_options: [type: :map, default: %{}]
    ]

  alias RubberDuck.Skills.{LearningSkill, PolicyEnforcementSkill}

  @doc """
  Perform comprehensive permission risk assessment with behavioral analysis.
  """
  def run(
        %{
          user_id: user_id,
          requested_permissions: permissions,
          access_context: context,
          assessment_options: options
        } = _params,
        agent_context
      ) do
    with {:ok, risk_assessment} <-
           perform_risk_assessment(user_id, permissions, context, agent_context),
         {:ok, behavioral_analysis} <-
           analyze_permission_behavior(user_id, permissions, context, agent_context),
         {:ok, context_analysis} <- analyze_access_context(context, agent_context),
         {:ok, mitigation_plan} <-
           generate_mitigation_plan(
             risk_assessment,
             behavioral_analysis,
             context_analysis,
             options
           ),
         {:ok, final_recommendation} <-
           generate_final_recommendation(risk_assessment, mitigation_plan, options) do
      # Track successful risk assessment for learning
      learning_context = %{
        user_id: user_id,
        permission_count: length(permissions),
        risk_level: risk_assessment.permission_risk_level,
        context_anomalies: length(context_analysis.detected_anomalies)
      }

      LearningSkill.track_experience(
        %{
          experience: %{
            action: :assess_permission_risk,
            risk_level: risk_assessment.permission_risk_level
          },
          outcome: :success,
          context: learning_context
        },
        agent_context
      )

      {:ok,
       %{
         risk_assessment: risk_assessment,
         behavioral_analysis: behavioral_analysis,
         context_analysis: context_analysis,
         mitigation_plan: mitigation_plan,
         final_recommendation: final_recommendation
       }}
    else
      {:error, reason} ->
        # Track failed risk assessment for learning
        learning_context = %{
          user_id: user_id,
          error_reason: reason,
          assessment_stage: determine_assessment_failure_stage(reason)
        }

        LearningSkill.track_experience(
          %{
            experience: %{action: :assess_permission_risk, failed: true},
            outcome: :failure,
            context: learning_context
          },
          agent_context
        )

        {:error, reason}
    end
  end

  # Private helper functions

  defp perform_risk_assessment(user_id, permissions, context, agent_context) do
    # Use PolicyEnforcementSkill to assess permission risk
    case PolicyEnforcementSkill.assess_risk(
           %{user_id: user_id, requested_permissions: permissions, context: context},
           agent_context
         ) do
      {:ok, risk_assessment, _updated_context} ->
        {:ok, risk_assessment}

      error ->
        error
    end
  end

  defp analyze_permission_behavior(user_id, permissions, context, agent_context) do
    # Analyze behavioral patterns related to permission requests
    behavioral_data = %{
      permission_types: classify_permission_types(permissions),
      request_timing: analyze_request_timing(context),
      access_pattern: extract_access_pattern(context),
      historical_consistency: assess_historical_consistency(user_id, permissions, agent_context)
    }

    behavioral_analysis = %{
      behavior_score: calculate_behavior_score(behavioral_data),
      anomaly_indicators: identify_behavioral_anomalies(behavioral_data),
      trust_level: calculate_trust_level(user_id, behavioral_data, agent_context),
      consistency_score: behavioral_data.historical_consistency,
      analysis_confidence: calculate_behavioral_confidence(behavioral_data)
    }

    {:ok, behavioral_analysis}
  end

  defp analyze_access_context(context, _agent_context) do
    # Analyze the access context for security implications
    context_factors = %{
      ip_reputation: assess_ip_reputation(Map.get(context, :ip_address)),
      device_trust: assess_device_trust(Map.get(context, :device_fingerprint)),
      session_security: assess_session_security(context),
      geographic_factors: analyze_geographic_factors(context),
      temporal_factors: analyze_temporal_factors(context)
    }

    detected_anomalies = identify_context_anomalies(context_factors)

    context_analysis = %{
      context_risk_score: calculate_context_risk_score(context_factors),
      detected_anomalies: detected_anomalies,
      security_recommendations: generate_context_security_recommendations(context_factors),
      confidence_level: calculate_context_confidence(context_factors),
      analysis_timestamp: DateTime.utc_now()
    }

    {:ok, context_analysis}
  end

  defp generate_mitigation_plan(risk_assessment, behavioral_analysis, context_analysis, _options) do
    # Generate comprehensive mitigation plan based on all analyses
    overall_risk = calculate_overall_risk(risk_assessment, behavioral_analysis, context_analysis)

    mitigation_strategies = []

    # Risk-based mitigations
    mitigation_strategies =
      case overall_risk do
        risk when risk > 0.8 ->
          [
            "Deny access immediately",
            "Require supervisor approval",
            "Enable session recording" | mitigation_strategies
          ]

        risk when risk > 0.6 ->
          [
            "Require additional verification",
            "Enable enhanced monitoring",
            "Limit session duration" | mitigation_strategies
          ]

        risk when risk > 0.4 ->
          ["Require MFA confirmation", "Enable audit logging" | mitigation_strategies]

        _ ->
          ["Apply standard monitoring" | mitigation_strategies]
      end

    # Context-specific mitigations
    mitigation_strategies =
      if Enum.empty?(context_analysis.detected_anomalies) do
        mitigation_strategies
      else
        [
          "Address context anomalies: #{Enum.join(context_analysis.detected_anomalies, ", ")}"
          | mitigation_strategies
        ]
      end

    # Behavioral mitigations
    mitigation_strategies =
      if behavioral_analysis.trust_level < 0.5 do
        [
          "Implement behavior verification",
          "Establish new behavioral baseline" | mitigation_strategies
        ]
      else
        mitigation_strategies
      end

    mitigation_plan = %{
      overall_risk_level: categorize_overall_risk(overall_risk),
      recommended_mitigations: mitigation_strategies,
      priority_actions: prioritize_mitigations(mitigation_strategies),
      implementation_urgency: determine_urgency(overall_risk),
      estimated_effectiveness: estimate_mitigation_effectiveness(mitigation_strategies),
      plan_confidence:
        calculate_plan_confidence(risk_assessment, behavioral_analysis, context_analysis)
    }

    {:ok, mitigation_plan}
  end

  defp generate_final_recommendation(risk_assessment, mitigation_plan, options) do
    # Generate final actionable recommendation
    auto_apply = Map.get(options, :auto_apply_mitigations, false)

    recommendation = %{
      access_decision: determine_access_decision(risk_assessment, mitigation_plan),
      required_mitigations: mitigation_plan.priority_actions,
      auto_apply_enabled: auto_apply,
      implementation_timeline: generate_implementation_timeline(mitigation_plan),
      monitoring_requirements: generate_monitoring_requirements(risk_assessment, mitigation_plan),
      review_schedule: determine_review_schedule(risk_assessment.permission_risk_level),
      recommendation_confidence: mitigation_plan.plan_confidence,
      generated_at: DateTime.utc_now()
    }

    {:ok, recommendation}
  end

  # Analysis helper functions

  defp classify_permission_types(permissions) do
    classification =
      Enum.group_by(permissions, fn permission ->
        cond do
          String.contains?(to_string(permission), "admin") -> :administrative
          String.contains?(to_string(permission), "delete") -> :destructive
          String.contains?(to_string(permission), "modify") -> :modification
          String.contains?(to_string(permission), "read") -> :read_only
          true -> :other
        end
      end)

    Map.new(classification, fn {type, perms} -> {type, length(perms)} end)
  end

  defp analyze_request_timing(context) do
    current_time = Map.get(context, :timestamp, DateTime.utc_now())

    hour =
      current_time
      |> DateTime.to_time()
      |> Time.to_string()
      |> String.slice(0, 2)
      |> String.to_integer()

    %{
      hour: hour,
      is_business_hours: hour >= 8 and hour <= 18,
      is_off_hours: hour < 6 or hour > 22,
      day_of_week: Date.day_of_week(DateTime.to_date(current_time))
    }
  end

  defp extract_access_pattern(context) do
    %{
      ip_address: Map.get(context, :ip_address, "unknown"),
      user_agent: Map.get(context, :user_agent, "unknown"),
      referrer: Map.get(context, :referrer, "direct"),
      session_duration: Map.get(context, :session_duration, 0)
    }
  end

  defp assess_historical_consistency(_user_id, _permissions, _agent_context) do
    # TODO: Implement actual historical consistency analysis
    # For now, return moderate consistency
    0.7
  end

  defp calculate_behavior_score(behavioral_data) do
    permission_risk = calculate_permission_type_risk(behavioral_data.permission_types)
    timing_risk = calculate_timing_risk(behavioral_data.request_timing)
    consistency_bonus = behavioral_data.historical_consistency * 0.2

    # Higher score = lower risk
    base_score = 1.0 - (permission_risk + timing_risk) / 2
    min(base_score + consistency_bonus, 1.0)
  end

  defp identify_behavioral_anomalies(behavioral_data) do
    anomalies = []

    # Check for permission type anomalies
    admin_perms = Map.get(behavioral_data.permission_types, :administrative, 0)
    destructive_perms = Map.get(behavioral_data.permission_types, :destructive, 0)

    anomalies =
      if admin_perms > 0 do
        [:administrative_access_requested | anomalies]
      else
        anomalies
      end

    anomalies =
      if destructive_perms > 0 do
        [:destructive_permissions_requested | anomalies]
      else
        anomalies
      end

    # Check for timing anomalies
    anomalies =
      if behavioral_data.request_timing.is_off_hours do
        [:off_hours_request | anomalies]
      else
        anomalies
      end

    anomalies
  end

  defp calculate_trust_level(_user_id, behavioral_data, _agent_context) do
    # Simple trust calculation based on behavioral factors
    base_trust = 0.5

    # Increase trust for business hours access
    trust_adjustment =
      if behavioral_data.request_timing.is_business_hours do
        0.2
      else
        -0.1
      end

    # Adjust based on historical consistency
    trust_adjustment = trust_adjustment + behavioral_data.historical_consistency * 0.3

    min(max(base_trust + trust_adjustment, 0.0), 1.0)
  end

  defp calculate_behavioral_confidence(behavioral_data) do
    # Confidence based on data completeness
    data_completeness = [
      not Enum.empty?(behavioral_data.permission_types),
      behavioral_data.request_timing != nil,
      behavioral_data.access_pattern != nil,
      behavioral_data.historical_consistency > 0
    ]

    enabled_factors = Enum.count(data_completeness, & &1)
    enabled_factors / length(data_completeness)
  end

  # Context analysis helpers

  defp assess_ip_reputation(ip_address) when is_binary(ip_address) do
    # TODO: Integrate with actual IP reputation service
    # Simple heuristic based on IP patterns
    cond do
      String.starts_with?(ip_address, "192.168.") -> :trusted_internal
      String.starts_with?(ip_address, "10.") -> :trusted_internal
      String.starts_with?(ip_address, "127.") -> :localhost
      true -> :external_unknown
    end
  end

  defp assess_ip_reputation(_), do: :unknown

  defp assess_device_trust(device_fingerprint) when is_binary(device_fingerprint) do
    # TODO: Implement device trust analysis
    # For now, return moderate trust
    :moderate_trust
  end

  defp assess_device_trust(_), do: :unknown_device

  defp assess_session_security(context) do
    security_factors = [
      Map.get(context, :https_used, true),
      Map.get(context, :secure_cookies, true),
      Map.get(context, :csrf_protection, true),
      not Map.get(context, :session_hijack_risk, false)
    ]

    secure_factors = Enum.count(security_factors, & &1)
    secure_factors / length(security_factors)
  end

  defp analyze_geographic_factors(context) do
    location = Map.get(context, :location, "unknown")

    %{
      location: location,
      location_risk: assess_location_risk(location),
      vpn_detected: Map.get(context, :vpn_detected, false),
      proxy_detected: Map.get(context, :proxy_detected, false)
    }
  end

  defp analyze_temporal_factors(context) do
    timestamp = Map.get(context, :timestamp, DateTime.utc_now())

    %{
      access_time: timestamp,
      is_business_hours: business_hours?(timestamp),
      is_weekend: weekend?(timestamp),
      time_zone_anomaly: Map.get(context, :timezone_mismatch, false)
    }
  end

  defp identify_context_anomalies(context_factors) do
    anomalies = []

    # IP-based anomalies
    anomalies =
      case context_factors.ip_reputation do
        :external_unknown -> [:unknown_ip | anomalies]
        _ -> anomalies
      end

    # Device anomalies
    anomalies =
      case context_factors.device_trust do
        :unknown_device -> [:unknown_device | anomalies]
        _ -> anomalies
      end

    # Security anomalies
    anomalies =
      if context_factors.session_security < 0.8 do
        [:insecure_session | anomalies]
      else
        anomalies
      end

    # Geographic anomalies
    anomalies =
      if context_factors.geographic_factors.vpn_detected do
        [:vpn_usage | anomalies]
      else
        anomalies
      end

    anomalies
  end

  defp calculate_context_risk_score(context_factors) do
    risk_components = [
      assess_ip_risk(context_factors.ip_reputation),
      assess_device_risk(context_factors.device_trust),
      # Invert security score to get risk
      1.0 - context_factors.session_security,
      context_factors.geographic_factors.location_risk,
      assess_temporal_risk(context_factors)
    ]

    Enum.sum(risk_components) / length(risk_components)
  end

  defp generate_context_security_recommendations(context_factors) do
    recommendations = []

    recommendations =
      case context_factors.ip_reputation do
        :external_unknown ->
          ["Verify IP address reputation", "Consider IP allowlisting" | recommendations]

        _ ->
          recommendations
      end

    recommendations =
      if context_factors.session_security < 0.8 do
        ["Enhance session security", "Enable secure transport" | recommendations]
      else
        recommendations
      end

    recommendations =
      if context_factors.geographic_factors.vpn_detected do
        ["Verify VPN usage legitimacy", "Apply VPN-specific policies" | recommendations]
      else
        recommendations
      end

    if Enum.empty?(recommendations) do
      ["Context security is adequate"]
    else
      recommendations
    end
  end

  defp calculate_context_confidence(context_factors) do
    # Confidence based on available context data
    confidence_factors = [
      context_factors.ip_reputation != :unknown,
      context_factors.device_trust != :unknown_device,
      context_factors.session_security > 0.0,
      context_factors.geographic_factors.location != "unknown"
    ]

    enabled_factors = Enum.count(confidence_factors, & &1)
    enabled_factors / length(confidence_factors)
  end

  defp calculate_overall_risk(risk_assessment, behavioral_analysis, context_analysis) do
    # Combine all risk factors with appropriate weights
    permission_risk = risk_assessment.permission_risk_level
    behavioral_risk = 1.0 - behavioral_analysis.behavior_score
    context_risk = context_analysis.context_risk_score

    # Weighted combination
    # Permission risk weighted highest
    weights = [0.4, 0.3, 0.3]
    risks = [permission_risk, behavioral_risk, context_risk]

    risks
    |> Enum.zip(weights)
    |> Enum.map(fn {risk, weight} -> risk * weight end)
    |> Enum.sum()
  end

  defp categorize_overall_risk(risk_score) do
    cond do
      risk_score > 0.8 -> :critical
      risk_score > 0.6 -> :high
      risk_score > 0.4 -> :medium
      risk_score > 0.2 -> :low
      true -> :minimal
    end
  end

  defp prioritize_mitigations(mitigations) do
    # Simple prioritization based on urgency keywords
    high_priority =
      Enum.filter(mitigations, fn mitigation ->
        String.contains?(mitigation, "Deny") or
          String.contains?(mitigation, "immediately") or
          String.contains?(mitigation, "supervisor")
      end)

    medium_priority =
      Enum.filter(mitigations, fn mitigation ->
        String.contains?(mitigation, "Require") or
          (String.contains?(mitigation, "Enable") and
             mitigation not in high_priority)
      end)

    low_priority = mitigations -- (high_priority -- medium_priority)

    %{
      high: high_priority,
      medium: medium_priority,
      low: low_priority
    }
  end

  defp determine_urgency(risk_score) do
    cond do
      risk_score > 0.8 -> :immediate
      risk_score > 0.6 -> :urgent
      risk_score > 0.4 -> :moderate
      true -> :low
    end
  end

  defp estimate_mitigation_effectiveness(mitigations) do
    # Estimate how effective the proposed mitigations will be
    effectiveness_scores =
      Enum.map(mitigations, fn mitigation ->
        case mitigation do
          "Deny access immediately" -> 0.95
          "Require supervisor approval" -> 0.9
          "Require additional verification" -> 0.8
          "Enable enhanced monitoring" -> 0.6
          "Require MFA confirmation" -> 0.85
          _ -> 0.5
        end
      end)

    if Enum.empty?(effectiveness_scores) do
      0.5
    else
      Enum.sum(effectiveness_scores) / length(effectiveness_scores)
    end
  end

  defp calculate_plan_confidence(risk_assessment, behavioral_analysis, context_analysis) do
    confidence_scores = [
      Map.get(risk_assessment, :confidence, 0.5),
      behavioral_analysis.analysis_confidence,
      context_analysis.confidence_level
    ]

    Enum.sum(confidence_scores) / length(confidence_scores)
  end

  defp determine_access_decision(risk_assessment, mitigation_plan) do
    case {risk_assessment.permission_risk_level, mitigation_plan.overall_risk_level} do
      {risk, _} when risk > 0.8 -> :deny_access
      {_, :critical} -> :deny_access
      {_, :high} -> :conditional_access
      {_, :medium} -> :monitored_access
      _ -> :standard_access
    end
  end

  defp generate_implementation_timeline(mitigation_plan) do
    case mitigation_plan.implementation_urgency do
      :immediate -> "Execute within 30 seconds"
      :urgent -> "Execute within 5 minutes"
      :moderate -> "Execute within 1 hour"
      :low -> "Execute within 24 hours"
    end
  end

  defp generate_monitoring_requirements(_risk_assessment, mitigation_plan) do
    base_monitoring = ["Standard access logging"]

    enhanced_monitoring =
      case mitigation_plan.overall_risk_level do
        :critical ->
          [
            "Real-time session monitoring",
            "Privileged access tracking",
            "Behavioral analysis" | base_monitoring
          ]

        :high ->
          ["Enhanced session logging", "Permission usage tracking" | base_monitoring]

        :medium ->
          ["Increased log detail" | base_monitoring]

        _ ->
          base_monitoring
      end

    enhanced_monitoring |> Enum.uniq()
  end

  defp determine_review_schedule(risk_level) do
    case risk_level do
      level when level > 0.8 -> "Daily review required"
      level when level > 0.6 -> "Weekly review recommended"
      level when level > 0.4 -> "Monthly review sufficient"
      _ -> "Quarterly review adequate"
    end
  end

  # Risk calculation helpers

  defp calculate_permission_type_risk(permission_types) do
    risk_weights = %{
      administrative: 0.9,
      destructive: 0.8,
      modification: 0.5,
      read_only: 0.1,
      other: 0.3
    }

    if map_size(permission_types) == 0 do
      0.0
    else
      weighted_risks =
        Enum.map(permission_types, fn {type, count} ->
          risk_weight = Map.get(risk_weights, type, 0.3)
          # Scale by count
          risk_weight * min(count / 5.0, 1.0)
        end)

      # Highest risk permission type determines risk
      Enum.max(weighted_risks)
    end
  end

  defp calculate_timing_risk(request_timing) do
    base_risk = if request_timing.is_off_hours, do: 0.6, else: 0.1
    weekend_risk = if request_timing.day_of_week in [6, 7], do: 0.2, else: 0.0

    min(base_risk + weekend_risk, 1.0)
  end

  defp assess_ip_risk(ip_reputation) do
    case ip_reputation do
      :trusted_internal -> 0.0
      :localhost -> 0.0
      :external_unknown -> 0.6
      :unknown -> 0.4
    end
  end

  defp assess_device_risk(device_trust) do
    case device_trust do
      :high_trust -> 0.0
      :moderate_trust -> 0.3
      :unknown_device -> 0.7
      :untrusted -> 0.9
    end
  end

  defp assess_temporal_risk(context_factors) do
    temporal_factors = Map.get(context_factors, :temporal_factors, %{})

    risk_score = 0.0

    risk_score =
      if Map.get(temporal_factors, :is_weekend, false) do
        risk_score + 0.2
      else
        risk_score
      end

    risk_score =
      if Map.get(temporal_factors, :is_business_hours, true) do
        risk_score
      else
        risk_score + 0.4
      end

    risk_score =
      if Map.get(temporal_factors, :time_zone_anomaly, false) do
        risk_score + 0.3
      else
        risk_score
      end

    min(risk_score, 1.0)
  end

  defp assess_location_risk(location) do
    case location do
      "unknown" ->
        0.5

      location when is_binary(location) ->
        # TODO: Implement sophisticated location risk assessment
        if String.contains?(location, "VPN") or String.contains?(location, "Proxy") do
          0.7
        else
          0.2
        end

      _ ->
        0.4
    end
  end

  defp business_hours?(timestamp) do
    hour =
      timestamp
      |> DateTime.to_time()
      |> Time.to_string()
      |> String.slice(0, 2)
      |> String.to_integer()

    hour >= 8 and hour <= 18
  end

  defp weekend?(timestamp) do
    day_of_week = Date.day_of_week(DateTime.to_date(timestamp))
    day_of_week in [6, 7]
  end

  defp determine_assessment_failure_stage(reason) do
    case reason do
      :risk_assessment_failed -> :risk_analysis
      :behavioral_analysis_failed -> :behavioral_analysis
      :context_analysis_failed -> :context_analysis
      :mitigation_planning_failed -> :mitigation_planning
      _ -> :unknown_stage
    end
  end
end
