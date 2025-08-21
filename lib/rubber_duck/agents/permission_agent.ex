defmodule RubberDuck.Agents.PermissionAgent do
  @moduledoc """
  Permission agent for dynamic permission adjustment and context-aware access control.

  This agent manages permission policies, monitors privilege escalation,
  performs risk-based authentication, and adapts access controls dynamically.
  """

  use Jido.Agent,
    name: "permission_agent",
    description: "Dynamic permission adjustment based on context",
    category: "security",
    tags: ["permissions", "access-control", "risk-based"],
    vsn: "1.0.0",
    actions: []

  alias RubberDuck.Skills.{LearningSkill, PolicyEnforcementSkill}

  @doc """
  Create a new PermissionAgent instance.
  """
  def create_permission_agent do
    with {:ok, agent} <- __MODULE__.new(),
         {:ok, agent} <-
           __MODULE__.set(agent,
             active_policies: %{},
             user_permissions: %{},
             access_logs: [],
             escalation_monitors: %{},
             risk_assessments: %{},
             policy_violations: [],
             last_policy_update: nil
           ) do
      {:ok, agent}
    end
  end

  @doc """
  Evaluate and enforce access control for resource requests.
  """
  def enforce_access_control(agent, user_id, resource, action, context) do
    case PolicyEnforcementSkill.enforce_access(
           %{user_id: user_id, resource: resource, action: action, context: context},
           agent
         ) do
      {:ok, enforcement_result, updated_agent} ->
        # Log access decision
        access_log = create_access_log(user_id, resource, action, enforcement_result, context)
        access_logs = [access_log | agent.access_logs] |> Enum.take(2000)

        {:ok, final_agent} =
          __MODULE__.set(updated_agent,
            access_logs: access_logs,
            last_access_enforcement: DateTime.utc_now()
          )

        {:ok, enforcement_result, final_agent}

      error ->
        error
    end
  end

  @doc """
  Assess permission risk for user requests.
  """
  def assess_permission_risk(agent, user_id, requested_permissions, context) do
    case PolicyEnforcementSkill.assess_risk(
           %{user_id: user_id, requested_permissions: requested_permissions, context: context},
           agent
         ) do
      {:ok, risk_assessment, updated_agent} ->
        # Update risk assessments
        risk_assessments = Map.get(agent, :risk_assessments, %{})
        updated_assessments = Map.put(risk_assessments, user_id, risk_assessment)

        {:ok, final_agent} =
          __MODULE__.set(updated_agent,
            risk_assessments: updated_assessments,
            last_risk_assessment: DateTime.utc_now()
          )

        {:ok, risk_assessment, final_agent}

      error ->
        error
    end
  end

  @doc """
  Dynamically adjust user permissions based on risk context.
  """
  def adjust_user_permissions(agent, user_id, risk_context, options \\ []) do
    current_permissions = get_user_permissions(agent, user_id)

    case PolicyEnforcementSkill.adjust_permissions(
           %{
             user_id: user_id,
             current_permissions: current_permissions,
             risk_context: risk_context
           },
           agent
         ) do
      {:ok, adjustment_result, updated_agent} ->
        # Update user permissions if auto-applied
        user_permissions = Map.get(agent, :user_permissions, %{})

        updated_permissions =
          if adjustment_result.result.auto_applied do
            Map.put(user_permissions, user_id, adjustment_result.result.adjusted_permissions)
          else
            user_permissions
          end

        {:ok, final_agent} =
          __MODULE__.set(updated_agent,
            user_permissions: updated_permissions,
            last_permission_adjustment: DateTime.utc_now()
          )

        {:ok, adjustment_result, final_agent}

      error ->
        error
    end
  end

  @doc """
  Monitor and respond to privilege escalation attempts.
  """
  def monitor_privilege_escalation(agent, user_id, escalation_data) do
    case PolicyEnforcementSkill.monitor_escalation(
           %{user_id: user_id, escalation_attempt: escalation_data},
           agent
         ) do
      {:ok, escalation_analysis, updated_agent} ->
        # Execute escalation response if needed
        response_result = execute_escalation_response(escalation_analysis, escalation_data)

        # Update escalation monitors
        escalation_monitors = Map.get(agent, :escalation_monitors, %{})

        updated_monitors =
          update_escalation_monitor(escalation_monitors, user_id, escalation_analysis)

        {:ok, final_agent} =
          __MODULE__.set(updated_agent,
            escalation_monitors: updated_monitors,
            last_escalation_monitoring: DateTime.utc_now()
          )

        {:ok, %{analysis: escalation_analysis, response: response_result}, final_agent}

      error ->
        error
    end
  end

  @doc """
  Get comprehensive permission status report.
  """
  def get_permission_status(agent) do
    status_report = %{
      active_policy_count: map_size(agent.active_policies),
      managed_user_count: map_size(agent.user_permissions),
      recent_access_requests: count_recent_access_requests(agent),
      policy_violations: count_recent_violations(agent),
      escalation_attempts: count_recent_escalations(agent),
      overall_security_posture: calculate_permission_security_posture(agent),
      risk_distribution: calculate_user_risk_distribution(agent),
      last_updated: DateTime.utc_now()
    }

    {:ok, status_report}
  end

  @doc """
  Update security policies with learning-based improvements.
  """
  def update_security_policies(agent, policy_updates, learning_context \\ %{}) do
    current_policies = Map.get(agent, :active_policies, %{})
    updated_policies = Map.merge(current_policies, policy_updates)

    policy_change = %{
      previous_policies: current_policies,
      updated_policies: updated_policies,
      change_reason: Map.get(learning_context, :reason, "Manual update"),
      effectiveness_prediction: predict_policy_effectiveness(policy_updates, agent),
      change_timestamp: DateTime.utc_now()
    }

    # Track policy changes for effectiveness learning
    policy_history = Map.get(agent, :policy_history, [])
    updated_history = [policy_change | policy_history] |> Enum.take(100)

    {:ok, updated_agent} =
      __MODULE__.set(agent,
        active_policies: updated_policies,
        policy_history: updated_history,
        last_policy_update: DateTime.utc_now()
      )

    {:ok, policy_change, updated_agent}
  end

  # Private helper functions

  defp create_access_log(user_id, resource, action, enforcement_result, context) do
    %{
      user_id: user_id,
      resource: resource,
      action: action,
      access_granted: enforcement_result.access_granted,
      risk_level: enforcement_result.risk_assessment,
      policy_violations: enforcement_result.policy_violations,
      context: context,
      timestamp: DateTime.utc_now(),
      session_id: Map.get(context, :session_id)
    }
  end

  defp get_user_permissions(agent, user_id) do
    user_permissions = Map.get(agent, :user_permissions, %{})
    Map.get(user_permissions, user_id, default_user_permissions())
  end

  defp default_user_permissions do
    [:read_access, :basic_modify]
  end

  defp execute_escalation_response(escalation_analysis, escalation_data) do
    case escalation_analysis.response_recommendation do
      :immediate_denial_and_alert ->
        %{
          action: :access_denied,
          alert_generated: true,
          security_team_notified: true,
          user_notified: true,
          response_time_ms: 50
        }

      :require_supervisor_approval ->
        %{
          action: :approval_required,
          supervisor_notified: true,
          escalation_queued: true,
          estimated_approval_time: "2-4 hours",
          response_time_ms: 200
        }

      :require_additional_verification ->
        %{
          action: :additional_verification,
          verification_methods: ["MFA", "Security questions"],
          verification_timeout: 300,
          response_time_ms: 100
        }

      :enhanced_monitoring ->
        %{
          action: :monitoring_enhanced,
          monitoring_level: :high,
          session_recording: true,
          response_time_ms: 75
        }

      _ ->
        %{
          action: :standard_processing,
          monitoring_level: :normal,
          response_time_ms: 25
        }
    end
  end

  defp update_escalation_monitor(escalation_monitors, user_id, escalation_analysis) do
    current_monitor =
      Map.get(escalation_monitors, user_id, %{
        escalation_count: 0,
        risk_trend: :stable,
        last_escalation: nil
      })

    updated_monitor = %{
      escalation_count: current_monitor.escalation_count + 1,
      risk_trend: determine_risk_trend(current_monitor, escalation_analysis),
      last_escalation: DateTime.utc_now(),
      recent_escalation_types:
        add_escalation_type(current_monitor, escalation_analysis.escalation_type)
    }

    Map.put(escalation_monitors, user_id, updated_monitor)
  end

  defp count_recent_access_requests(agent) do
    access_logs = Map.get(agent, :access_logs, [])
    # Last hour
    recent_cutoff = DateTime.add(DateTime.utc_now(), -3600, :second)

    Enum.count(access_logs, fn log ->
      DateTime.compare(log.timestamp, recent_cutoff) == :gt
    end)
  end

  defp count_recent_violations(agent) do
    policy_violations = Map.get(agent, :policy_violations, [])
    # Last hour
    recent_cutoff = DateTime.add(DateTime.utc_now(), -3600, :second)

    Enum.count(policy_violations, fn violation ->
      violation_time = Map.get(violation, :timestamp, DateTime.utc_now())
      DateTime.compare(violation_time, recent_cutoff) == :gt
    end)
  end

  defp count_recent_escalations(agent) do
    escalation_monitors = Map.get(agent, :escalation_monitors, %{})
    recent_cutoff = DateTime.add(DateTime.utc_now(), -3600, :second)

    Enum.reduce(Map.values(escalation_monitors), 0, fn monitor, acc ->
      count_monitor_escalations(monitor, recent_cutoff, acc)
    end)
  end

  defp count_monitor_escalations(monitor, recent_cutoff, acc) do
    last_escalation = Map.get(monitor, :last_escalation)

    if last_escalation && DateTime.compare(last_escalation, recent_cutoff) == :gt do
      acc + 1
    else
      acc
    end
  end

  defp calculate_permission_security_posture(agent) do
    violation_count = count_recent_violations(agent)
    escalation_count = count_recent_escalations(agent)
    access_request_count = count_recent_access_requests(agent)

    # Calculate security posture based on recent activity
    if access_request_count == 0 do
      :inactive
    else
      violation_rate = violation_count / access_request_count
      escalation_rate = escalation_count / access_request_count

      combined_rate = violation_rate + escalation_rate

      cond do
        combined_rate > 0.2 -> :concerning
        combined_rate > 0.1 -> :elevated
        combined_rate > 0.05 -> :moderate
        true -> :good
      end
    end
  end

  defp calculate_user_risk_distribution(agent) do
    risk_assessments = Map.get(agent, :risk_assessments, %{})

    if map_size(risk_assessments) == 0 do
      %{distribution: :no_data}
    else
      risk_levels = extract_risk_levels(risk_assessments)
      distribution = categorize_risk_levels(risk_levels)
      build_risk_distribution_summary(distribution, risk_assessments)
    end
  end

  defp extract_risk_levels(risk_assessments) do
    Map.values(risk_assessments)
    |> Enum.map(&Map.get(&1, :permission_risk_level, 0.3))
  end

  defp categorize_risk_levels(risk_levels) do
    Enum.frequencies_by(risk_levels, fn risk ->
      categorize_individual_risk(risk)
    end)
  end

  defp categorize_individual_risk(risk) do
    cond do
      risk > 0.8 -> :high_risk
      risk > 0.6 -> :medium_risk
      risk > 0.4 -> :low_risk
      true -> :minimal_risk
    end
  end

  defp build_risk_distribution_summary(distribution, risk_assessments) do
    %{
      high_risk_users: Map.get(distribution, :high_risk, 0),
      medium_risk_users: Map.get(distribution, :medium_risk, 0),
      low_risk_users: Map.get(distribution, :low_risk, 0),
      minimal_risk_users: Map.get(distribution, :minimal_risk, 0),
      total_users: map_size(risk_assessments)
    }
  end

  defp predict_policy_effectiveness(policy_updates, agent) do
    # Simple effectiveness prediction based on historical data
    policy_history = Map.get(agent, :policy_history, [])

    if Enum.empty?(policy_history) do
      %{prediction: :unknown, confidence: 0.3}
    else
      # Analyze similar policy changes
      similar_changes = find_similar_policy_changes(policy_updates, policy_history)

      if Enum.empty?(similar_changes) do
        %{prediction: :moderate_improvement, confidence: 0.5}
      else
        avg_effectiveness = calculate_average_effectiveness(similar_changes)

        %{
          prediction: categorize_effectiveness(avg_effectiveness),
          confidence: min(length(similar_changes) / 5.0, 1.0)
        }
      end
    end
  end

  defp determine_risk_trend(current_monitor, escalation_analysis) do
    current_count = current_monitor.escalation_count

    case {current_count, escalation_analysis.risk_level} do
      {count, risk} when count > 5 and risk > 0.8 -> :rapidly_increasing
      {count, risk} when count > 3 and risk > 0.6 -> :increasing
      {count, risk} when count < 2 and risk < 0.4 -> :decreasing
      _ -> :stable
    end
  end

  defp add_escalation_type(current_monitor, escalation_type) do
    recent_types = Map.get(current_monitor, :recent_escalation_types, [])
    [escalation_type | recent_types] |> Enum.uniq() |> Enum.take(10)
  end

  defp find_similar_policy_changes(policy_updates, policy_history) do
    # Simple similarity based on changed policy keys
    update_keys = Map.keys(policy_updates)

    Enum.filter(policy_history, fn change ->
      change_keys = Map.keys(change.updated_policies)
      overlap = MapSet.intersection(MapSet.new(update_keys), MapSet.new(change_keys))
      MapSet.size(overlap) > 0
    end)
  end

  defp calculate_average_effectiveness(policy_changes) do
    # TODO: Implement sophisticated effectiveness calculation
    # For now, simulate based on policy change outcomes
    effectiveness_scores =
      Enum.map(policy_changes, fn _change ->
        # Random between 0.6-0.9
        0.6 + :rand.uniform() * 0.3
      end)

    Enum.sum(effectiveness_scores) / length(effectiveness_scores)
  end

  defp categorize_effectiveness(avg_effectiveness) do
    cond do
      avg_effectiveness > 0.8 -> :high_improvement
      avg_effectiveness > 0.6 -> :moderate_improvement
      avg_effectiveness > 0.4 -> :slight_improvement
      true -> :minimal_improvement
    end
  end
end
