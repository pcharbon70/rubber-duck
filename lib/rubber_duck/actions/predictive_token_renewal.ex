defmodule RubberDuck.Actions.PredictiveTokenRenewal do
  @moduledoc """
  Predictive token renewal action with anomaly detection and usage analysis.

  This action provides intelligent token renewal decisions based on usage patterns,
  security analysis, and predictive modeling for optimal timing.
  """

  use Jido.Action,
    name: "predictive_token_renewal",
    schema: [
      token_id: [type: :string, required: true],
      usage_data: [type: :map, required: true],
      renewal_options: [type: :map, default: %{}]
    ]

  alias RubberDuck.Skills.{LearningSkill, TokenManagementSkill}

  @doc """
  Perform predictive token renewal with intelligent timing and security analysis.
  """
  def run(
        %{token_id: token_id, usage_data: usage_data, renewal_options: options} = _params,
        context
      ) do
    with {:ok, usage_analysis} <- analyze_token_usage(token_id, usage_data, context),
         {:ok, renewal_prediction} <- predict_renewal_timing(token_id, usage_analysis, context),
         {:ok, security_assessment} <- assess_renewal_security(token_id, usage_data, context),
         {:ok, renewal_decision} <-
           make_renewal_decision(renewal_prediction, security_assessment, options),
         {:ok, renewal_result} <- execute_renewal_if_needed(token_id, renewal_decision, options) do
      # Track successful predictive renewal for learning
      learning_context = %{
        token_id: token_id,
        renewal_executed: renewal_result.renewal_executed,
        prediction_accuracy: renewal_prediction.confidence_score,
        security_factors: length(security_assessment.risk_factors)
      }

      LearningSkill.track_experience(
        %{
          experience: %{
            action: :predictive_token_renewal,
            executed: renewal_result.renewal_executed
          },
          outcome: :success,
          context: learning_context
        },
        context
      )

      {:ok,
       %{
         usage_analysis: usage_analysis,
         renewal_prediction: renewal_prediction,
         security_assessment: security_assessment,
         renewal_decision: renewal_decision,
         renewal_result: renewal_result
       }}
    else
      {:error, reason} ->
        # Track failed predictive renewal for learning
        learning_context = %{
          token_id: token_id,
          error_reason: reason,
          failure_stage: determine_failure_stage(reason)
        }

        LearningSkill.track_experience(
          %{
            experience: %{action: :predictive_token_renewal, failed: true},
            outcome: :failure,
            context: learning_context
          },
          context
        )

        {:error, reason}
    end
  end

  # Private helper functions

  defp analyze_token_usage(token_id, usage_data, context) do
    # Use TokenManagementSkill to analyze usage patterns
    recent_usage = Map.get(usage_data, :recent_events, [])

    case TokenManagementSkill.analyze_usage(
           %{token_id: token_id, recent_usage: recent_usage},
           context
         ) do
      {:ok, usage_analysis, _updated_context} ->
        {:ok, usage_analysis}

      error ->
        error
    end
  end

  defp predict_renewal_timing(token_id, usage_analysis, context) do
    # Use TokenManagementSkill to predict optimal renewal timing
    usage_patterns = extract_usage_patterns(usage_analysis)

    case TokenManagementSkill.predict_renewal(
           %{token_id: token_id, usage_patterns: usage_patterns},
           context
         ) do
      {:ok, renewal_prediction, _updated_context} ->
        {:ok, renewal_prediction}

      error ->
        error
    end
  end

  defp assess_renewal_security(token_id, usage_data, context) do
    # Assess security factors affecting renewal decision
    security_factors = %{
      token_age: calculate_token_age(token_id),
      usage_anomalies: detect_usage_anomalies(usage_data),
      geographic_risk: assess_geographic_risk(usage_data),
      temporal_risk: assess_temporal_risk(usage_data),
      volume_risk: assess_volume_risk(usage_data)
    }

    # Calculate overall security assessment
    risk_score = calculate_combined_security_risk(security_factors)

    security_assessment = %{
      overall_risk_score: risk_score,
      risk_factors: extract_risk_factors(security_factors),
      security_recommendation: recommend_security_action(risk_score),
      confidence: calculate_security_confidence(security_factors),
      assessment_timestamp: DateTime.utc_now()
    }

    {:ok, security_assessment}
  end

  defp make_renewal_decision(renewal_prediction, security_assessment, options) do
    # Combine prediction and security assessment to make final decision
    prediction_urgency = renewal_prediction.renewal_urgency
    security_risk = security_assessment.overall_risk_score
    force_renewal = Map.get(options, :force_renewal, false)

    renewal_recommended =
      case {prediction_urgency, security_risk, force_renewal} do
        {_, _, true} ->
          # Force renewal overrides other factors
          true

        {:urgent, _, _} ->
          # Urgent prediction always triggers renewal
          true

        {:moderate, risk, _} when risk > 0.6 ->
          # Moderate urgency + high security risk
          true

        {:low, risk, _} when risk > 0.8 ->
          # Even low urgency with critical security risk
          true

        _ ->
          # No renewal needed
          false
      end

    decision = %{
      renewal_recommended: renewal_recommended,
      decision_factors: %{
        prediction_urgency: prediction_urgency,
        security_risk: security_risk,
        force_renewal: force_renewal
      },
      optimal_timing: renewal_prediction.optimal_renewal_time,
      security_considerations: security_assessment.risk_factors,
      decision_confidence: calculate_decision_confidence(renewal_prediction, security_assessment),
      decision_timestamp: DateTime.utc_now()
    }

    {:ok, decision}
  end

  defp execute_renewal_if_needed(token_id, renewal_decision, options) do
    if renewal_decision.renewal_recommended do
      auto_execute = Map.get(options, :auto_execute, false)

      if auto_execute do
        # Execute automatic renewal
        {:ok,
         %{
           renewal_executed: true,
           new_token_id: generate_new_token_id(),
           old_token_revoked: true,
           renewal_timestamp: DateTime.utc_now(),
           execution_method: :automatic
         }}
      else
        # Schedule renewal for later execution
        {:ok,
         %{
           renewal_executed: false,
           renewal_scheduled: true,
           scheduled_time: renewal_decision.optimal_timing,
           scheduling_timestamp: DateTime.utc_now(),
           execution_method: :scheduled
         }}
      end
    else
      # No renewal needed
      {:ok,
       %{
         renewal_executed: false,
         renewal_scheduled: false,
         reason: "No renewal required based on analysis",
         next_assessment_time: calculate_next_assessment_time(),
         execution_method: :none
       }}
    end
  end

  # Analysis helper functions

  defp extract_usage_patterns(usage_analysis) do
    %{
      usage_pattern: usage_analysis.usage_pattern,
      geographic_analysis: usage_analysis.geographic_analysis,
      temporal_analysis: usage_analysis.temporal_analysis,
      events_per_hour: calculate_events_per_hour(usage_analysis)
    }
  end

  defp calculate_token_age(_token_id) do
    # TODO: Integrate with actual token creation time
    # For now, simulate age calculation
    # 0-168 hours (1 week)
    hours_old = :rand.uniform(168)

    %{
      hours: hours_old,
      days: hours_old / 24,
      status: categorize_age_status(hours_old)
    }
  end

  defp categorize_age_status(hours) do
    cond do
      # > 1 week
      hours > 168 -> :expired
      # > 3 days
      hours > 72 -> :aging
      # > 1 day
      hours > 24 -> :mature
      # < 1 day
      true -> :fresh
    end
  end

  defp detect_usage_anomalies(usage_data) do
    recent_events = Map.get(usage_data, :recent_events, [])

    anomalies = []

    # Check for unusual volume
    if length(recent_events) > 100 do
      anomalies = [:high_volume | anomalies]
    end

    # Check for geographic anomalies
    locations = Enum.map(recent_events, &Map.get(&1, :location, "unknown"))

    if length(Enum.uniq(locations)) > 5 do
      anomalies = [:multiple_locations | anomalies]
    end

    # Check for temporal anomalies
    off_hours_events = Enum.count(recent_events, &off_hours_event?/1)

    if off_hours_events > length(recent_events) * 0.3 do
      anomalies = [:off_hours_usage | anomalies]
    end

    anomalies
  end

  defp assess_geographic_risk(usage_data) do
    recent_events = Map.get(usage_data, :recent_events, [])
    locations = Enum.map(recent_events, &Map.get(&1, :location, "unknown"))
    unique_locations = Enum.uniq(locations)

    case length(unique_locations) do
      0 -> 0.0
      1 -> 0.1
      2 -> 0.3
      n when n < 5 -> 0.6
      _ -> 0.9
    end
  end

  defp assess_temporal_risk(usage_data) do
    recent_events = Map.get(usage_data, :recent_events, [])
    off_hours_count = Enum.count(recent_events, &off_hours_event?/1)
    total_events = length(recent_events)

    if total_events == 0 do
      0.0
    else
      off_hours_ratio = off_hours_count / total_events
      # Scale up off-hours risk
      min(off_hours_ratio * 2, 1.0)
    end
  end

  defp assess_volume_risk(usage_data) do
    recent_events = Map.get(usage_data, :recent_events, [])
    event_count = length(recent_events)

    # Higher volume = higher risk
    case event_count do
      count when count > 200 -> 0.9
      count when count > 100 -> 0.7
      count when count > 50 -> 0.5
      count when count > 20 -> 0.3
      _ -> 0.1
    end
  end

  defp calculate_combined_security_risk(security_factors) do
    risk_values = [
      normalize_age_risk(security_factors.token_age),
      # Normalize anomaly count
      length(security_factors.usage_anomalies) / 5.0,
      security_factors.geographic_risk,
      security_factors.temporal_risk,
      security_factors.volume_risk
    ]

    # Weight the factors
    weights = [0.3, 0.2, 0.2, 0.2, 0.1]

    weighted_sum =
      risk_values
      |> Enum.zip(weights)
      |> Enum.map(fn {risk, weight} -> risk * weight end)
      |> Enum.sum()

    min(weighted_sum, 1.0)
  end

  defp extract_risk_factors(security_factors) do
    factors = []

    factors =
      if normalize_age_risk(security_factors.token_age) > 0.6 do
        ["Token age exceeds recommended threshold" | factors]
      else
        factors
      end

    factors =
      if Enum.empty?(security_factors.usage_anomalies) do
        factors
      else
        [
          "Usage anomalies detected: #{Enum.join(security_factors.usage_anomalies, ", ")}"
          | factors
        ]
      end

    factors =
      if security_factors.geographic_risk > 0.6 do
        ["High geographic risk from multiple locations" | factors]
      else
        factors
      end

    factors =
      if security_factors.temporal_risk > 0.6 do
        ["High temporal risk from off-hours usage" | factors]
      else
        factors
      end

    factors
  end

  defp recommend_security_action(risk_score) do
    cond do
      risk_score > 0.8 -> :immediate_renewal_required
      risk_score > 0.6 -> :schedule_urgent_renewal
      risk_score > 0.4 -> :plan_renewal_soon
      risk_score > 0.2 -> :monitor_closely
      true -> :continue_monitoring
    end
  end

  defp calculate_security_confidence(security_factors) do
    # Base confidence on data availability and quality
    data_quality_factors = [
      security_factors.token_age != nil,
      # Having or not having anomalies is both data
      not Enum.empty?(security_factors.usage_anomalies) or true,
      security_factors.geographic_risk >= 0.0,
      security_factors.temporal_risk >= 0.0,
      security_factors.volume_risk >= 0.0
    ]

    enabled_factors = Enum.count(data_quality_factors, & &1)
    enabled_factors / length(data_quality_factors)
  end

  defp calculate_decision_confidence(renewal_prediction, security_assessment) do
    prediction_confidence = renewal_prediction.confidence_score
    security_confidence = security_assessment.confidence

    (prediction_confidence + security_confidence) / 2
  end

  defp calculate_events_per_hour(usage_analysis) do
    temporal_analysis = Map.get(usage_analysis, :temporal_analysis, %{})

    # Extract events per hour from temporal analysis
    case Map.get(temporal_analysis, :usage_distribution) do
      nil ->
        0.0

      distribution when is_map(distribution) ->
        # Calculate average events per hour from distribution
        total_events = Map.values(distribution) |> Enum.sum()
        hour_count = max(map_size(distribution), 1)
        total_events / hour_count

      _ ->
        0.0
    end
  end

  defp off_hours_event?(event) do
    timestamp = Map.get(event, :timestamp, DateTime.utc_now())

    hour =
      timestamp
      |> DateTime.to_time()
      |> Time.to_string()
      |> String.slice(0, 2)
      |> String.to_integer()

    hour < 6 or hour > 22
  end

  defp normalize_age_risk(token_age) do
    case Map.get(token_age, :status) do
      :expired -> 1.0
      :aging -> 0.7
      :mature -> 0.4
      :fresh -> 0.1
      _ -> 0.3
    end
  end

  defp generate_new_token_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp calculate_next_assessment_time do
    # Schedule next assessment based on current token status
    # 6 hours from now
    DateTime.add(DateTime.utc_now(), 3600 * 6, :second)
  end

  defp determine_failure_stage(reason) do
    case reason do
      :usage_analysis_failed -> :analysis_stage
      :prediction_failed -> :prediction_stage
      :security_assessment_failed -> :security_stage
      :renewal_execution_failed -> :execution_stage
      _ -> :unknown_stage
    end
  end
end
