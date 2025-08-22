defmodule RubberDuck.Agents.TokenAgent do
  @moduledoc """
  Token agent for self-managing token lifecycle with predictive renewal.

  This agent manages token lifecycles, predicts optimal renewal timing,
  analyzes usage patterns, and detects security anomalies autonomously.
  """

  use Jido.Agent,
    name: "token_agent",
    description: "Self-managing token lifecycle with predictive renewal",
    category: "security",
    tags: ["tokens", "lifecycle", "predictive"],
    vsn: "1.0.0",
    actions: []

  alias RubberDuck.Skills.TokenManagementSkill

  @doc """
  Create a new TokenAgent instance.
  """
  def create_token_agent do
    with {:ok, agent} <- __MODULE__.new(),
         {:ok, agent} <-
           __MODULE__.set(agent,
             managed_tokens: %{},
             renewal_schedule: %{},
             usage_analytics: %{},
             security_alerts: [],
             predictive_models: %{},
             last_maintenance: nil
           ) do
      {:ok, agent}
    end
  end

  @doc """
  Register token for intelligent management.
  """
  def register_token(agent, token_id, token_metadata) do
    managed_tokens = Map.get(agent, :managed_tokens, %{})

    token_registration = %{
      token_id: token_id,
      metadata: token_metadata,
      registered_at: DateTime.utc_now(),
      management_status: :active,
      risk_level: :low
    }

    updated_tokens = Map.put(managed_tokens, token_id, token_registration)

    {:ok, updated_agent} =
      __MODULE__.set(agent,
        managed_tokens: updated_tokens,
        last_registration: DateTime.utc_now()
      )

    {:ok, token_registration, updated_agent}
  end

  @doc """
  Analyze token usage patterns and predict renewal needs.
  """
  def analyze_token_usage(agent, token_id, recent_usage) do
    case TokenManagementSkill.analyze_usage(
           %{token_id: token_id, recent_usage: recent_usage},
           agent
         ) do
      {:ok, usage_analysis, updated_agent} ->
        # Update usage analytics
        usage_analytics = Map.get(agent, :usage_analytics, %{})
        updated_analytics = Map.put(usage_analytics, token_id, usage_analysis)

        {:ok, final_agent} =
          __MODULE__.set(updated_agent,
            usage_analytics: updated_analytics,
            last_usage_analysis: DateTime.utc_now()
          )

        {:ok, usage_analysis, final_agent}

      error ->
        error
    end
  end

  @doc """
  Predict optimal token renewal timing.
  """
  def predict_renewal(agent, token_id, usage_patterns) do
    case TokenManagementSkill.predict_renewal(
           %{token_id: token_id, usage_patterns: usage_patterns},
           agent
         ) do
      {:ok, renewal_prediction, updated_agent} ->
        # Update renewal schedule
        renewal_schedule = Map.get(agent, :renewal_schedule, %{})
        updated_schedule = Map.put(renewal_schedule, token_id, renewal_prediction)

        {:ok, final_agent} =
          __MODULE__.set(updated_agent,
            renewal_schedule: updated_schedule,
            last_renewal_prediction: DateTime.utc_now()
          )

        {:ok, renewal_prediction, final_agent}

      error ->
        error
    end
  end

  @doc """
  Manage token lifecycle with intelligent decisions.
  """
  def manage_lifecycle(agent, token_id, user_context) do
    case TokenManagementSkill.manage_lifecycle(
           %{token_id: token_id, user_context: user_context},
           agent
         ) do
      {:ok, lifecycle_analysis, updated_agent} ->
        # Execute lifecycle management actions
        management_result = execute_lifecycle_actions(lifecycle_analysis, user_context)

        # Update managed tokens
        managed_tokens = Map.get(agent, :managed_tokens, %{})

        updated_token_data =
          Map.get(managed_tokens, token_id, %{})
          |> Map.put(:lifecycle_status, lifecycle_analysis.lifecycle_status)
          |> Map.put(:last_managed, DateTime.utc_now())

        updated_tokens = Map.put(managed_tokens, token_id, updated_token_data)

        {:ok, final_agent} =
          __MODULE__.set(updated_agent,
            managed_tokens: updated_tokens,
            last_lifecycle_management: DateTime.utc_now()
          )

        {:ok, %{analysis: lifecycle_analysis, management: management_result}, final_agent}

      error ->
        error
    end
  end

  @doc """
  Detect and respond to token security anomalies.
  """
  def detect_anomalies(agent, token_id, current_usage) do
    case TokenManagementSkill.detect_anomalies(
           %{token_id: token_id, current_usage: current_usage},
           agent
         ) do
      {:ok, anomaly_detection, updated_agent} ->
        # Generate security alert if anomalies detected
        if anomaly_detection.overall_anomaly_score > 0.6 do
          security_alert = create_security_alert(token_id, anomaly_detection)
          security_alerts = [security_alert | agent.security_alerts] |> Enum.take(100)

          {:ok, final_agent} =
            __MODULE__.set(updated_agent,
              security_alerts: security_alerts,
              last_anomaly_detection: DateTime.utc_now()
            )

          {:ok, %{anomalies: anomaly_detection, alert: security_alert}, final_agent}
        else
          {:ok, %{anomalies: anomaly_detection, alert: nil}, updated_agent}
        end

      error ->
        error
    end
  end

  @doc """
  Get comprehensive token management status.
  """
  def get_token_status(agent) do
    managed_tokens = Map.get(agent, :managed_tokens, %{})
    renewal_schedule = Map.get(agent, :renewal_schedule, %{})
    security_alerts = Map.get(agent, :security_alerts, [])

    status_report = %{
      total_managed_tokens: map_size(managed_tokens),
      tokens_requiring_attention: count_tokens_requiring_attention(managed_tokens),
      pending_renewals: count_pending_renewals(renewal_schedule),
      active_security_alerts: count_active_alerts(security_alerts),
      overall_token_health: calculate_overall_token_health(agent),
      management_effectiveness: calculate_management_effectiveness(agent),
      last_updated: DateTime.utc_now()
    }

    {:ok, status_report}
  end

  @doc """
  Perform predictive maintenance on all managed tokens.
  """
  def perform_maintenance(agent) do
    managed_tokens = Map.get(agent, :managed_tokens, %{})

    maintenance_results =
      Enum.map(managed_tokens, fn {token_id, token_data} ->
        perform_token_maintenance(token_id, token_data, agent)
      end)

    maintenance_summary = %{
      tokens_processed: length(maintenance_results),
      tokens_renewed: count_renewals_performed(maintenance_results),
      tokens_flagged: count_tokens_flagged(maintenance_results),
      maintenance_duration: calculate_maintenance_duration(maintenance_results),
      maintenance_timestamp: DateTime.utc_now()
    }

    {:ok, updated_agent} =
      __MODULE__.set(agent,
        last_maintenance: DateTime.utc_now(),
        maintenance_history:
          [maintenance_summary | Map.get(agent, :maintenance_history, [])] |> Enum.take(50)
      )

    {:ok, maintenance_summary, updated_agent}
  end

  # Private helper functions

  defp execute_lifecycle_actions(lifecycle_analysis, _user_context) do
    case lifecycle_analysis.renewal_recommendation do
      :immediate_renewal ->
        %{action: :token_renewed, status: :completed, priority: :high}

      :schedule_renewal ->
        %{action: :renewal_scheduled, status: :scheduled, priority: :medium}

      :plan_renewal ->
        %{action: :renewal_planned, status: :planned, priority: :low}

      :monitor_closely ->
        %{action: :monitoring_enhanced, status: :active, priority: :medium}

      _ ->
        %{action: :no_action, status: :monitoring, priority: :low}
    end
  end

  defp create_security_alert(token_id, anomaly_detection) do
    %{
      alert_id: generate_alert_id(),
      token_id: token_id,
      alert_type: :security_anomaly,
      severity: determine_alert_severity(anomaly_detection.overall_anomaly_score),
      details: anomaly_detection,
      recommended_actions: anomaly_detection.recommended_actions,
      created_at: DateTime.utc_now(),
      status: :active
    }
  end

  defp count_tokens_requiring_attention(managed_tokens) do
    Enum.count(Map.values(managed_tokens), fn token_data ->
      Map.get(token_data, :management_status) in [
        :requires_attention,
        :renewal_needed,
        :security_risk
      ]
    end)
  end

  defp count_pending_renewals(renewal_schedule) do
    Enum.count(Map.values(renewal_schedule), fn renewal ->
      renewal.renewal_urgency in [:urgent, :moderate]
    end)
  end

  defp count_active_alerts(security_alerts) do
    Enum.count(security_alerts, fn alert ->
      Map.get(alert, :status) == :active
    end)
  end

  defp calculate_overall_token_health(agent) do
    managed_tokens = Map.get(agent, :managed_tokens, %{})
    security_alerts = Map.get(agent, :security_alerts, [])

    if map_size(managed_tokens) == 0 do
      :no_tokens
    else
      tokens_needing_attention = count_tokens_requiring_attention(managed_tokens)
      active_alerts = count_active_alerts(security_alerts)

      health_score = 1.0 - (tokens_needing_attention + active_alerts) / map_size(managed_tokens)

      cond do
        health_score > 0.9 -> :excellent
        health_score > 0.7 -> :good
        health_score > 0.5 -> :adequate
        health_score > 0.3 -> :concerning
        true -> :critical
      end
    end
  end

  defp calculate_management_effectiveness(agent) do
    maintenance_history = Map.get(agent, :maintenance_history, [])

    if Enum.empty?(maintenance_history) do
      # No history, assume moderate effectiveness
      0.5
    else
      recent_maintenance = Enum.take(maintenance_history, 5)
      effectiveness_scores = calculate_effectiveness_scores(recent_maintenance)
      Enum.sum(effectiveness_scores) / length(effectiveness_scores)
    end
  end

  defp calculate_effectiveness_scores(maintenance_records) do
    Enum.map(maintenance_records, fn maintenance ->
      calculate_single_effectiveness_score(maintenance)
    end)
  end

  defp calculate_single_effectiveness_score(maintenance) do
    tokens_processed = maintenance.tokens_processed
    tokens_flagged = maintenance.tokens_flagged

    if tokens_processed > 0 do
      1.0 - tokens_flagged / tokens_processed
    else
      0.5
    end
  end

  defp perform_token_maintenance(token_id, token_data, _agent) do
    # Perform maintenance check on individual token
    risk_level = Map.get(token_data, :risk_level, :low)
    age = calculate_token_age_hours(token_data)

    maintenance_action =
      cond do
        risk_level == :high -> :security_review_required
        # 1 week
        age > 168 -> :renewal_recommended
        # 2 days
        age > 48 -> :monitoring_enhanced
        true -> :no_action_needed
      end

    %{
      token_id: token_id,
      maintenance_action: maintenance_action,
      processed_at: DateTime.utc_now()
    }
  end

  defp count_renewals_performed(maintenance_results) do
    Enum.count(maintenance_results, fn result ->
      result.maintenance_action in [:token_renewed, :renewal_recommended]
    end)
  end

  defp count_tokens_flagged(maintenance_results) do
    Enum.count(maintenance_results, fn result ->
      result.maintenance_action == :security_review_required
    end)
  end

  defp calculate_maintenance_duration(maintenance_results) do
    # Simple duration calculation
    # Assume 50ms per token
    length(maintenance_results) * 50
  end

  defp generate_alert_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp determine_alert_severity(anomaly_score) do
    cond do
      anomaly_score > 0.8 -> :critical
      anomaly_score > 0.6 -> :high
      anomaly_score > 0.4 -> :medium
      true -> :low
    end
  end

  defp calculate_token_age_hours(token_data) do
    created_at = Map.get(token_data, :registered_at, DateTime.utc_now())
    DateTime.diff(DateTime.utc_now(), created_at, :hour)
  end
end
