defmodule RubberDuck.Actions.EnhanceAshSignIn do
  @moduledoc """
  Enhanced Ash sign-in action with behavioral analysis and security intelligence.

  This action integrates with Ash Authentication to provide intelligent
  sign-in enhancement with threat detection and behavioral learning.
  """

  use Jido.Action,
    name: "enhance_ash_sign_in",
    schema: [
      user_credentials: [type: :map, required: true],
      request_context: [type: :map, required: true],
      security_options: [type: :map, default: %{}]
    ]

  alias RubberDuck.Skills.{AuthenticationSkill, LearningSkill, ThreatDetectionSkill}

  @doc """
  Enhance Ash sign-in process with security intelligence.
  """
  def run(
        %{user_credentials: credentials, request_context: context, security_options: options} =
          _params,
        agent_context
      ) do
    with {:ok, sign_in_result} <- perform_ash_sign_in(credentials, context),
         {:ok, threat_analysis} <- analyze_sign_in_threats(credentials, context, agent_context),
         {:ok, behavioral_analysis} <-
           analyze_sign_in_behavior(sign_in_result, context, agent_context),
         {:ok, security_enhancements} <-
           apply_security_enhancements(
             sign_in_result,
             threat_analysis,
             behavioral_analysis,
             options
           ) do
      # Track successful enhanced sign-in for learning
      learning_context = %{
        user_id: sign_in_result.user_id,
        threat_level: threat_analysis.threat_level,
        behavioral_score: behavioral_analysis.behavioral_score,
        enhancements_applied: length(security_enhancements.enhancements)
      }

      LearningSkill.track_experience(
        %{
          experience: %{action: :enhance_ash_sign_in, threat_level: threat_analysis.threat_level},
          outcome: :success,
          context: learning_context
        },
        agent_context
      )

      {:ok,
       %{
         sign_in: sign_in_result,
         threat_analysis: threat_analysis,
         behavioral_analysis: behavioral_analysis,
         security_enhancements: security_enhancements
       }}
    else
      {:error, reason} ->
        # Track failed sign-in enhancement for learning
        learning_context = %{
          error_reason: reason,
          user_email: Map.get(credentials, :email, "unknown"),
          request_ip: Map.get(context, :ip_address, "unknown")
        }

        LearningSkill.track_experience(
          %{
            experience: %{action: :enhance_ash_sign_in, failed: true},
            outcome: :failure,
            context: learning_context
          },
          agent_context
        )

        {:error, reason}
    end
  end

  # Private helper functions

  defp perform_ash_sign_in(credentials, context) do
    # TODO: Integrate with actual Ash Authentication sign-in
    # For now, simulate sign-in process
    email = Map.get(credentials, :email)
    password = Map.get(credentials, :password)

    if email && password do
      {:ok,
       %{
         user_id: generate_user_id(),
         email: email,
         token: generate_auth_token(),
         session_id: generate_session_id(),
         sign_in_timestamp: DateTime.utc_now(),
         ip_address: Map.get(context, :ip_address),
         user_agent: Map.get(context, :user_agent)
       }}
    else
      {:error, :invalid_credentials}
    end
  end

  defp analyze_sign_in_threats(credentials, context, agent_context) do
    # Use ThreatDetectionSkill to analyze potential threats
    request_data = %{
      email: Map.get(credentials, :email),
      password_attempt: true,
      ip_address: Map.get(context, :ip_address),
      user_agent: Map.get(context, :user_agent)
    }

    user_context = %{
      # Use email as identifier for analysis
      user_id: Map.get(credentials, :email),
      ip_address: Map.get(context, :ip_address),
      access_time: DateTime.utc_now(),
      device_fingerprint: Map.get(context, :device_fingerprint)
    }

    case ThreatDetectionSkill.detect_threat(
           %{request_data: request_data, user_context: user_context},
           agent_context
         ) do
      {:ok, threat_analysis, _updated_context} ->
        {:ok, threat_analysis}

      error ->
        # If threat analysis fails, assume moderate threat
        {:ok,
         %{
           threat_level: :medium,
           anomaly_score: 0.5,
           confidence: 0.3,
           timestamp: DateTime.utc_now()
         }}
    end
  end

  defp analyze_sign_in_behavior(sign_in_result, context, agent_context) do
    # Use AuthenticationSkill to analyze behavioral patterns
    session_data = %{
      # New session
      age_hours: 0,
      mfa_verified: false,
      ip_address: Map.get(context, :ip_address)
    }

    request_context = %{
      ip_address: Map.get(context, :ip_address),
      user_agent: Map.get(context, :user_agent),
      device_fingerprint: Map.get(context, :device_fingerprint),
      access_time: DateTime.utc_now()
    }

    case AuthenticationSkill.enhance_session(
           %{
             user_id: sign_in_result.user_id,
             session_data: session_data,
             request_context: request_context
           },
           agent_context
         ) do
      {:ok, session_analysis, _updated_context} ->
        {:ok, session_analysis}

      error ->
        # If behavioral analysis fails, assume neutral behavior
        {:ok,
         %{
           behavioral_score: 0.5,
           session_risk_level: :medium,
           confidence: 0.3
         }}
    end
  end

  defp apply_security_enhancements(sign_in_result, threat_analysis, behavioral_analysis, options) do
    enhancements = []

    # Apply threat-based enhancements
    enhancements =
      case threat_analysis.threat_level do
        :critical ->
          [:immediate_mfa_required, :session_monitoring, :ip_restriction | enhancements]

        :high ->
          [:enhanced_mfa, :increased_logging | enhancements]

        :medium ->
          [:standard_mfa_prompt | enhancements]

        _ ->
          enhancements
      end

    # Apply behavioral-based enhancements
    enhancements =
      case behavioral_analysis.session_risk_level do
        :critical ->
          [:additional_verification, :session_time_limit | enhancements]

        :high ->
          [:enhanced_session_monitoring | enhancements]

        _ ->
          enhancements
      end

    # Apply option-based enhancements
    if Map.get(options, :force_mfa, false) do
      enhancements = [:force_mfa | enhancements]
    end

    enhanced_sign_in = apply_enhancements_to_session(sign_in_result, enhancements)

    {:ok,
     %{
       enhanced_session: enhanced_sign_in,
       enhancements: Enum.uniq(enhancements),
       enhancement_rationale:
         generate_enhancement_rationale(threat_analysis, behavioral_analysis),
       security_level: determine_session_security_level(enhancements)
     }}
  end

  defp apply_enhancements_to_session(sign_in_result, enhancements) do
    enhanced_session =
      sign_in_result
      |> Map.put(:security_enhancements, enhancements)
      |> Map.put(:enhanced_at, DateTime.utc_now())

    # Apply specific enhancements
    Enum.reduce(enhancements, enhanced_session, fn enhancement, session ->
      case enhancement do
        :immediate_mfa_required ->
          session
          |> Map.put(:mfa_required, true)
          # 5 minutes
          |> Map.put(:mfa_timeout, 300)

        :session_monitoring ->
          session
          |> Map.put(:monitoring_enabled, true)
          |> Map.put(:monitoring_level, :high)

        :ip_restriction ->
          session
          |> Map.put(:ip_locked, true)
          |> Map.put(:allowed_ip, Map.get(session, :ip_address))

        :enhanced_mfa ->
          session
          |> Map.put(:mfa_required, true)
          |> Map.put(:mfa_methods, [:totp, :sms])

        :session_time_limit ->
          session
          |> Map.put(:session_timeout_minutes, 30)
          |> Map.put(:hard_timeout, true)

        :additional_verification ->
          session
          |> Map.put(:additional_verification_required, true)
          |> Map.put(:verification_methods, [:security_questions, :email_verification])

        _ ->
          # Unknown enhancement, no action
          session
      end
    end)
  end

  defp generate_enhancement_rationale(threat_analysis, behavioral_analysis) do
    rationale_parts = []

    rationale_parts =
      case threat_analysis.threat_level do
        level when level in [:critical, :high] ->
          ["High threat level detected requiring enhanced security measures" | rationale_parts]

        :medium ->
          ["Moderate security risk identified" | rationale_parts]

        _ ->
          rationale_parts
      end

    rationale_parts =
      case behavioral_analysis.session_risk_level do
        level when level in [:critical, :high] ->
          ["Behavioral anomalies detected requiring additional verification" | rationale_parts]

        _ ->
          rationale_parts
      end

    if Enum.empty?(rationale_parts) do
      "Standard security enhancements applied"
    else
      Enum.join(rationale_parts, "; ")
    end
  end

  defp determine_session_security_level(enhancements) do
    high_security_enhancements = [
      :immediate_mfa_required,
      :session_monitoring,
      :ip_restriction,
      :additional_verification
    ]

    high_security_count = Enum.count(enhancements, &(&1 in high_security_enhancements))
    total_enhancements = length(enhancements)

    cond do
      high_security_count >= 3 -> :maximum
      high_security_count >= 2 -> :high
      total_enhancements >= 2 -> :elevated
      total_enhancements >= 1 -> :standard
      true -> :minimal
    end
  end

  # Helper functions for ID generation

  defp generate_user_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp generate_auth_token do
    :crypto.strong_rand_bytes(32) |> Base.encode64(padding: false)
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
