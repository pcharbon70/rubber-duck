defmodule RubberDuck.Skills.TokenManagementSkill do
  @moduledoc """
  Token management skill with lifecycle control and predictive renewal.

  Provides capabilities for intelligent token management, usage pattern analysis,
  and predictive renewal based on behavioral patterns.
  """

  use Jido.Skill,
    name: "token_management_skill",
    opts_key: :token_management_state,
    signal_patterns: [
      "token.manage_lifecycle",
      "token.predict_renewal",
      "token.analyze_usage",
      "token.detect_anomalies"
    ]

  @doc """
  Manage token lifecycle with intelligent decisions.
  """
  def manage_lifecycle(%{token_id: token_id, user_context: user_context} = _params, state) do
    lifecycle_analysis = %{
      token_id: token_id,
      current_age: calculate_token_age(token_id),
      usage_frequency: calculate_usage_frequency(token_id, state),
      security_risk: assess_token_security_risk(token_id, user_context, state),
      renewal_recommendation: recommend_renewal_action(token_id, user_context, state),
      lifecycle_status: determine_lifecycle_status(token_id, state)
    }

    # Update token tracking
    token_tracking = Map.get(state, :token_tracking, %{})
    updated_tracking = Map.put(token_tracking, token_id, lifecycle_analysis)

    new_state =
      state
      |> Map.put(:token_tracking, updated_tracking)
      |> Map.put(:last_lifecycle_analysis, DateTime.utc_now())

    {:ok, lifecycle_analysis, new_state}
  end

  @doc """
  Predict optimal token renewal timing.
  """
  def predict_renewal(%{token_id: token_id, usage_patterns: usage_patterns} = _params, state) do
    renewal_prediction = %{
      token_id: token_id,
      optimal_renewal_time: calculate_optimal_renewal_time(token_id, usage_patterns, state),
      renewal_urgency: assess_renewal_urgency(token_id, usage_patterns, state),
      predicted_usage_window: predict_usage_window(usage_patterns),
      confidence_score: calculate_renewal_confidence(token_id, usage_patterns, state),
      recommendation: generate_renewal_recommendation(token_id, usage_patterns, state)
    }

    # Store prediction for learning
    renewal_predictions = Map.get(state, :renewal_predictions, [])
    updated_predictions = [renewal_prediction | renewal_predictions] |> Enum.take(200)

    new_state =
      state
      |> Map.put(:renewal_predictions, updated_predictions)
      |> Map.put(:last_renewal_prediction, DateTime.utc_now())

    {:ok, renewal_prediction, new_state}
  end

  @doc """
  Analyze token usage patterns for anomaly detection.
  """
  def analyze_usage(%{token_id: token_id, recent_usage: recent_usage} = _params, state) do
    usage_analysis = %{
      token_id: token_id,
      usage_pattern: classify_usage_pattern(recent_usage),
      anomaly_score: detect_usage_anomalies(token_id, recent_usage, state),
      geographic_analysis: analyze_geographic_usage(recent_usage),
      temporal_analysis: analyze_temporal_usage(recent_usage),
      risk_assessment: assess_usage_risk(token_id, recent_usage, state)
    }

    # Update usage patterns database
    usage_patterns = Map.get(state, :usage_patterns, %{})
    updated_patterns = Map.put(usage_patterns, token_id, usage_analysis)

    new_state =
      state
      |> Map.put(:usage_patterns, updated_patterns)
      |> Map.put(:last_usage_analysis, DateTime.utc_now())

    {:ok, usage_analysis, new_state}
  end

  @doc """
  Detect token-related security anomalies.
  """
  def detect_anomalies(%{token_id: token_id, current_usage: current_usage} = _params, state) do
    anomaly_detection = %{
      token_id: token_id,
      suspicious_patterns: identify_suspicious_patterns(current_usage, state),
      geographic_anomalies: detect_geographic_anomalies(current_usage, state),
      temporal_anomalies: detect_temporal_anomalies(current_usage, state),
      volume_anomalies: detect_volume_anomalies(token_id, current_usage, state),
      overall_anomaly_score: calculate_overall_anomaly_score(current_usage, state),
      recommended_actions: generate_anomaly_response_actions(current_usage, state)
    }

    # Store anomaly detection results
    anomaly_history = Map.get(state, :anomaly_history, [])
    updated_history = [anomaly_detection | anomaly_history] |> Enum.take(500)

    new_state =
      state
      |> Map.put(:anomaly_history, updated_history)
      |> Map.put(:last_anomaly_detection, DateTime.utc_now())

    {:ok, anomaly_detection, new_state}
  end

  # Private helper functions

  defp calculate_token_age(_token_id) do
    # TODO: Integrate with actual Token resource to get creation time
    # For now, simulate age calculation
    # 0-72 hours
    hours_old = :rand.uniform(72)
    %{hours: hours_old, status: if(hours_old > 48, do: :aging, else: :fresh)}
  end

  defp calculate_usage_frequency(token_id, state) do
    usage_patterns = Map.get(state, :usage_patterns, %{})

    case Map.get(usage_patterns, token_id) do
      nil ->
        %{frequency: :unknown, last_used: nil}

      pattern ->
        usage_events = Map.get(pattern, :usage_events, [])

        recent_usage =
          Enum.filter(usage_events, fn event ->
            DateTime.diff(DateTime.utc_now(), event.timestamp, :hour) < 24
          end)

        %{
          frequency: calculate_frequency_score(recent_usage),
          last_used: get_last_usage_time(usage_events),
          daily_usage_count: length(recent_usage)
        }
    end
  end

  defp assess_token_security_risk(token_id, user_context, state) do
    _usage_patterns = Map.get(state, :usage_patterns, %{})
    anomaly_history = Map.get(state, :anomaly_history, [])

    # Check for recent anomalies
    recent_anomalies =
      Enum.filter(anomaly_history, fn anomaly ->
        anomaly.token_id == token_id and
          DateTime.diff(DateTime.utc_now(), anomaly.timestamp, :hour) < 6
      end)

    # Check user context risk factors
    context_risk = assess_context_risk_factors(user_context)

    combined_risk =
      case {length(recent_anomalies), context_risk} do
        {0, :low} -> :low
        {0, :medium} -> :low
        {1, :low} -> :medium
        {1, :medium} -> :medium
        {_, :high} -> :high
        _ -> :high
      end

    combined_risk
  end

  defp recommend_renewal_action(token_id, user_context, state) do
    risk_level = assess_token_security_risk(token_id, user_context, state)
    age_info = calculate_token_age(token_id)
    usage_frequency = calculate_usage_frequency(token_id, state)

    case {risk_level, age_info.status, usage_frequency.frequency} do
      {:high, _, _} -> :immediate_renewal
      {_, :aging, :high} -> :schedule_renewal
      {_, :aging, :medium} -> :plan_renewal
      {:medium, :fresh, :high} -> :monitor_closely
      _ -> :no_action_needed
    end
  end

  defp determine_lifecycle_status(token_id, state) do
    age_info = calculate_token_age(token_id)
    usage_freq = calculate_usage_frequency(token_id, state)

    case {age_info.status, usage_freq.frequency} do
      {:fresh, :high} -> :active_healthy
      {:fresh, :medium} -> :active_normal
      {:aging, :high} -> :aging_active
      {:aging, :low} -> :aging_inactive
      {_, :unknown} -> :status_unknown
      _ -> :requires_review
    end
  end

  defp calculate_optimal_renewal_time(_token_id, usage_patterns, _state) do
    # Analyze usage patterns to predict optimal renewal timing
    _peak_usage_hours = extract_peak_usage_hours(usage_patterns)
    low_usage_periods = extract_low_usage_periods(usage_patterns)

    optimal_time =
      if Enum.empty?(low_usage_periods) do
        # If no clear low-usage periods, use early morning
        %{hour: 3, minute: 0, timezone: "UTC"}
      else
        List.first(low_usage_periods)
      end

    optimal_time
  end

  defp assess_renewal_urgency(token_id, usage_patterns, state) do
    risk_level = assess_token_security_risk(token_id, %{}, state)
    age_info = calculate_token_age(token_id)
    usage_intensity = calculate_usage_intensity(usage_patterns)

    risk_score = calculate_risk_score(risk_level)
    age_score = calculate_age_score(age_info.status)
    usage_score = calculate_usage_score(usage_intensity)

    urgency_score = risk_score + age_score + usage_score

    determine_urgency_level(urgency_score)
  end

  defp calculate_risk_score(:high), do: 0.8
  defp calculate_risk_score(:medium), do: 0.5
  defp calculate_risk_score(:low), do: 0.2

  defp calculate_age_score(:aging), do: 0.3
  defp calculate_age_score(:fresh), do: 0.0

  defp calculate_usage_score(:high), do: 0.2
  defp calculate_usage_score(:medium), do: 0.1
  defp calculate_usage_score(:low), do: 0.0

  defp determine_urgency_level(urgency_score) do
    cond do
      urgency_score > 0.8 -> :urgent
      urgency_score > 0.5 -> :moderate
      urgency_score > 0.3 -> :low
      true -> :no_urgency
    end
  end

  defp predict_usage_window(usage_patterns) do
    # Predict when token will be most/least used
    hourly_usage = extract_hourly_usage_distribution(usage_patterns)

    %{
      peak_hours: find_peak_usage_hours(hourly_usage),
      quiet_hours: find_quiet_usage_hours(hourly_usage),
      predicted_next_use: predict_next_usage_time(usage_patterns)
    }
  end

  defp calculate_renewal_confidence(token_id, usage_patterns, state) do
    historical_data_quality = assess_historical_data_quality(token_id, state)
    pattern_consistency = assess_pattern_consistency(usage_patterns)

    (historical_data_quality + pattern_consistency) / 2
  end

  defp generate_renewal_recommendation(token_id, usage_patterns, state) do
    urgency = assess_renewal_urgency(token_id, usage_patterns, state)
    optimal_time = calculate_optimal_renewal_time(token_id, usage_patterns, state)

    case urgency do
      :urgent ->
        "Immediate token renewal recommended due to security concerns"

      :moderate ->
        "Schedule token renewal within next 24 hours, preferably at #{optimal_time.hour}:00 UTC"

      :low ->
        "Plan token renewal for next maintenance window"

      _ ->
        "Token renewal not currently required"
    end
  end

  # Usage analysis helper functions

  defp classify_usage_pattern(recent_usage) do
    usage_count = length(recent_usage)
    time_span = calculate_time_span(recent_usage)

    determine_usage_pattern(usage_count, time_span, recent_usage)
  end

  defp determine_usage_pattern(usage_count, time_span, recent_usage) do
    cond do
      burst_usage?(usage_count, time_span) -> :burst_usage
      steady_usage?(usage_count, time_span) -> :steady_usage
      light_usage?(usage_count, time_span) -> :light_usage
      scheduled_usage?(usage_count, recent_usage) -> :scheduled_usage
      true -> :irregular_usage
    end
  end

  defp burst_usage?(usage_count, time_span) do
    usage_count > 100 and time_span < 3600
  end

  defp steady_usage?(usage_count, time_span) do
    usage_count > 50 and time_span > 86_400
  end

  defp light_usage?(usage_count, time_span) do
    usage_count < 10 and time_span > 86_400
  end

  defp scheduled_usage?(usage_count, recent_usage) do
    usage_count > 20 and has_regular_intervals?(recent_usage)
  end

  defp detect_usage_anomalies(token_id, recent_usage, state) do
    baseline_patterns = Map.get(state, :usage_patterns, %{})

    case Map.get(baseline_patterns, token_id) do
      nil ->
        # No baseline, moderate anomaly score
        0.3

      baseline ->
        pattern_deviation = calculate_pattern_deviation(recent_usage, baseline)
        volume_deviation = calculate_volume_deviation(recent_usage, baseline)

        (pattern_deviation + volume_deviation) / 2
    end
  end

  defp analyze_geographic_usage(recent_usage) do
    locations = Enum.map(recent_usage, &Map.get(&1, :location, "unknown"))
    unique_locations = Enum.uniq(locations)

    %{
      unique_locations: length(unique_locations),
      primary_location: find_most_common_location(locations),
      geographic_spread: calculate_geographic_spread(unique_locations),
      suspicious_locations: identify_suspicious_locations(locations)
    }
  end

  defp analyze_temporal_usage(recent_usage) do
    usage_times = Enum.map(recent_usage, &Map.get(&1, :timestamp, DateTime.utc_now()))

    %{
      usage_distribution: calculate_hourly_distribution(usage_times),
      peak_usage_time: find_peak_usage_time(usage_times),
      usage_consistency: calculate_temporal_consistency(usage_times),
      off_hours_usage: count_off_hours_usage(usage_times)
    }
  end

  defp assess_usage_risk(token_id, recent_usage, state) do
    anomaly_score = detect_usage_anomalies(token_id, recent_usage, state)
    geographic_risk = assess_geographic_risk(recent_usage)
    temporal_risk = assess_temporal_risk(recent_usage)

    combined_risk = (anomaly_score + geographic_risk + temporal_risk) / 3

    cond do
      combined_risk > 0.8 -> :high
      combined_risk > 0.6 -> :medium
      combined_risk > 0.4 -> :low
      true -> :minimal
    end
  end

  # Simple helper implementations for core functionality

  defp calculate_frequency_score(recent_usage) do
    count = length(recent_usage)

    cond do
      count > 50 -> :high
      count > 20 -> :medium
      count > 5 -> :low
      true -> :minimal
    end
  end

  defp get_last_usage_time(usage_events) do
    if Enum.empty?(usage_events) do
      nil
    else
      Enum.max_by(usage_events, & &1.timestamp).timestamp
    end
  end

  defp assess_context_risk_factors(user_context) do
    risk_indicators = [
      Map.get(user_context, :new_device, false),
      Map.get(user_context, :unusual_location, false),
      Map.get(user_context, :off_hours_access, false)
    ]

    risk_count = Enum.count(risk_indicators, & &1)

    case risk_count do
      0 -> :low
      1 -> :medium
      _ -> :high
    end
  end

  defp extract_peak_usage_hours(_usage_patterns) do
    # TODO: Implement sophisticated peak hour analysis
    # Typical business hours
    [9, 10, 11, 14, 15, 16]
  end

  defp extract_low_usage_periods(_usage_patterns) do
    # TODO: Implement low usage period detection
    [
      %{hour: 2, minute: 0, timezone: "UTC"},
      %{hour: 3, minute: 0, timezone: "UTC"}
    ]
  end

  defp calculate_usage_intensity(usage_patterns) do
    # Simple intensity calculation
    events_per_hour = Map.get(usage_patterns, :events_per_hour, 0)

    cond do
      events_per_hour > 10 -> :high
      events_per_hour > 3 -> :medium
      events_per_hour > 0 -> :low
      true -> :none
    end
  end

  defp extract_hourly_usage_distribution(_usage_patterns) do
    # TODO: Implement actual hourly distribution analysis
    %{
      "morning" => 0.3,
      "afternoon" => 0.5,
      "evening" => 0.2,
      "night" => 0.1
    }
  end

  defp find_peak_usage_hours(hourly_usage) do
    # TODO: Implement peak hour identification
    Enum.max_by(hourly_usage, fn {_period, usage} -> usage end) |> elem(0)
  end

  defp find_quiet_usage_hours(hourly_usage) do
    # TODO: Implement quiet hour identification
    Enum.min_by(hourly_usage, fn {_period, usage} -> usage end) |> elem(0)
  end

  defp predict_next_usage_time(_usage_patterns) do
    # TODO: Implement sophisticated next usage prediction
    # Predict 1 hour from now
    DateTime.add(DateTime.utc_now(), 3600, :second)
  end

  defp assess_historical_data_quality(token_id, state) do
    usage_patterns = Map.get(state, :usage_patterns, %{})

    case Map.get(usage_patterns, token_id) do
      nil ->
        0.2

      pattern ->
        data_points = length(Map.get(pattern, :usage_events, []))
        min(data_points / 50.0, 1.0)
    end
  end

  defp assess_pattern_consistency(usage_patterns) do
    # Simple consistency check
    if Map.has_key?(usage_patterns, :events_per_hour) do
      0.8
    else
      0.4
    end
  end

  defp calculate_time_span(usage_events) do
    if length(usage_events) < 2 do
      0
    else
      timestamps = Enum.map(usage_events, &Map.get(&1, :timestamp, DateTime.utc_now()))
      earliest = Enum.min_by(timestamps, &DateTime.to_unix/1)
      latest = Enum.max_by(timestamps, &DateTime.to_unix/1)

      DateTime.diff(latest, earliest, :second)
    end
  end

  defp has_regular_intervals?(usage_events) do
    if length(usage_events) < 3, do: false

    timestamps =
      Enum.map(usage_events, &Map.get(&1, :timestamp, DateTime.utc_now()))
      |> Enum.sort(DateTime)

    intervals =
      Enum.zip(timestamps, Enum.drop(timestamps, 1))
      |> Enum.map(fn {t1, t2} -> DateTime.diff(t2, t1, :minute) end)

    # Check if intervals are relatively consistent (within 20% variance)
    if Enum.empty?(intervals) do
      false
    else
      avg_interval = Enum.sum(intervals) / length(intervals)
      variance = Enum.map(intervals, &(abs(&1 - avg_interval) / avg_interval)) |> Enum.max()

      variance < 0.2
    end
  end

  defp calculate_pattern_deviation(recent_usage, baseline) do
    # Simple pattern comparison
    recent_pattern = classify_usage_pattern(recent_usage)
    baseline_pattern = Map.get(baseline, :typical_pattern, :irregular_usage)

    if recent_pattern == baseline_pattern, do: 0.0, else: 0.7
  end

  defp calculate_volume_deviation(recent_usage, baseline) do
    recent_count = length(recent_usage)
    baseline_count = Map.get(baseline, :typical_daily_count, 10)

    if baseline_count > 0 do
      deviation = abs(recent_count - baseline_count) / baseline_count
      min(deviation, 1.0)
    else
      0.5
    end
  end

  defp find_most_common_location(locations) do
    if Enum.empty?(locations) do
      "unknown"
    else
      locations
      |> Enum.frequencies()
      |> Enum.max_by(fn {_location, count} -> count end)
      |> elem(0)
    end
  end

  defp calculate_geographic_spread(unique_locations) do
    case length(unique_locations) do
      0 -> :no_data
      1 -> :single_location
      2 -> :dual_location
      n when n < 5 -> :few_locations
      _ -> :many_locations
    end
  end

  defp identify_suspicious_locations(_locations) do
    # TODO: Implement geolocation-based suspicious location detection
    []
  end

  defp calculate_hourly_distribution(usage_times) do
    hours =
      Enum.map(usage_times, fn time ->
        time
        |> DateTime.to_time()
        |> Time.to_string()
        |> String.slice(0, 2)
        |> String.to_integer()
      end)

    Enum.frequencies(hours)
  end

  defp find_peak_usage_time(usage_times) do
    hourly_dist = calculate_hourly_distribution(usage_times)

    if map_size(hourly_dist) == 0 do
      # Default to noon
      12
    else
      {peak_hour, _count} = Enum.max_by(hourly_dist, fn {_hour, count} -> count end)
      peak_hour
    end
  end

  defp calculate_temporal_consistency(usage_times) do
    # Simple consistency calculation based on usage time distribution
    hourly_dist = calculate_hourly_distribution(usage_times)

    if map_size(hourly_dist) == 0 do
      0.0
    else
      # More concentrated usage = higher consistency
      max_count = Map.values(hourly_dist) |> Enum.max()
      total_usage = Map.values(hourly_dist) |> Enum.sum()

      max_count / total_usage
    end
  end

  defp count_off_hours_usage(usage_times) do
    Enum.count(usage_times, fn time ->
      hour =
        time
        |> DateTime.to_time()
        |> Time.to_string()
        |> String.slice(0, 2)
        |> String.to_integer()

      hour < 6 or hour > 22
    end)
  end

  defp assess_geographic_risk(recent_usage) do
    locations = Enum.map(recent_usage, &Map.get(&1, :location, "unknown"))
    unique_count = Enum.uniq(locations) |> length()

    case unique_count do
      0 -> 0.0
      1 -> 0.1
      2 -> 0.3
      n when n < 5 -> 0.6
      _ -> 0.9
    end
  end

  defp assess_temporal_risk(recent_usage) do
    off_hours_count =
      recent_usage
      |> Enum.map(&Map.get(&1, :timestamp, DateTime.utc_now()))
      |> count_off_hours_usage()

    total_usage = length(recent_usage)

    if total_usage == 0 do
      0.0
    else
      off_hours_ratio = off_hours_count / total_usage
      # Scale up off-hours risk
      min(off_hours_ratio * 2, 1.0)
    end
  end

  defp identify_suspicious_patterns(_current_usage, _state) do
    # TODO: Implement sophisticated suspicious pattern detection
    []
  end

  defp detect_geographic_anomalies(_current_usage, _state) do
    # TODO: Implement geographic anomaly detection
    []
  end

  defp detect_temporal_anomalies(_current_usage, _state) do
    # TODO: Implement temporal anomaly detection
    []
  end

  defp detect_volume_anomalies(_token_id, _current_usage, _state) do
    # TODO: Implement volume anomaly detection
    []
  end

  defp calculate_overall_anomaly_score(_current_usage, _state) do
    # TODO: Implement comprehensive anomaly scoring
    # Low anomaly score as default
    0.2
  end

  defp generate_anomaly_response_actions(_current_usage, _state) do
    # TODO: Implement anomaly response action generation
    ["Continue monitoring", "Log suspicious activity"]
  end
end
