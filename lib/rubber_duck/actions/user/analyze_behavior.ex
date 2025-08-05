defmodule RubberDuck.Actions.User.AnalyzeBehavior do
  @moduledoc """
  Action to analyze user behavior patterns from interactions.
  """

  use Jido.Action,
    name: "analyze_behavior",
    description: "Analyzes user interactions to identify behavior patterns",
    schema: [
      user_id: [type: :string, required: true],
      interactions: [type: {:list, :map}, required: true],
      min_pattern_count: [type: :pos_integer, default: 3],
      time_window_days: [type: :pos_integer, default: 30]
    ]

  @impl true
  def run(params, _context) do
    recent_interactions = filter_recent_interactions(params.interactions, params.time_window_days)

    analysis = %{
      total_interactions: length(recent_interactions),
      action_frequency: analyze_action_frequency(recent_interactions),
      time_patterns: analyze_time_patterns(recent_interactions),
      sequence_patterns: analyze_sequence_patterns(recent_interactions, params.min_pattern_count),
      behavior_score: calculate_behavior_score(recent_interactions)
    }

    {:ok, analysis}
  end

  defp filter_recent_interactions(interactions, days) do
    cutoff = DateTime.add(DateTime.utc_now(), -days * 24 * 60 * 60, :second)

    Enum.filter(interactions, fn interaction ->
      DateTime.compare(interaction.timestamp, cutoff) == :gt
    end)
  end

  defp analyze_action_frequency(interactions) do
    interactions
    |> Enum.group_by(& &1.action.type)
    |> Enum.map(fn {action_type, group} ->
      {action_type, %{
        count: length(group),
        percentage: length(group) / length(interactions) * 100
      }}
    end)
    |> Map.new()
  end

  defp analyze_time_patterns(interactions) do
    %{
      by_time_of_day: group_by_time_of_day(interactions),
      by_day_of_week: group_by_day_of_week(interactions),
      peak_hours: find_peak_hours(interactions)
    }
  end

  defp group_by_time_of_day(interactions) do
    interactions
    |> Enum.group_by(& &1.context.time_of_day)
    |> Enum.map(fn {time, group} ->
      {time, %{count: length(group), percentage: length(group) / length(interactions) * 100}}
    end)
    |> Map.new()
  end

  defp group_by_day_of_week(interactions) do
    interactions
    |> Enum.group_by(& &1.context.day_of_week)
    |> Enum.map(fn {day, group} ->
      {day, %{count: length(group), percentage: length(group) / length(interactions) * 100}}
    end)
    |> Map.new()
  end

  defp find_peak_hours(interactions) do
    interactions
    |> Enum.group_by(& DateTime.to_time(&1.timestamp).hour)
    |> Enum.map(fn {hour, group} -> {hour, length(group)} end)
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.take(3)
    |> Enum.map(fn {hour, _} -> hour end)
  end

  defp analyze_sequence_patterns(interactions, min_count) do
    interactions
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [first, second] ->
      {first.action.type, second.action.type}
    end)
    |> Enum.frequencies()
    |> Enum.filter(fn {_, count} -> count >= min_count end)
    |> Enum.map(fn {{from, to}, count} ->
      %{
        sequence: [from, to],
        count: count,
        confidence: count / length(interactions)
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  defp calculate_behavior_score(interactions) do
    # Simple scoring based on consistency and activity
    if Enum.empty?(interactions) do
      0.0
    else
      consistency_score = calculate_consistency_score(interactions)
      activity_score = min(length(interactions) / 100, 1.0)

      (consistency_score + activity_score) / 2
    end
  end

  defp calculate_consistency_score(interactions) do
    # Measure how consistent the user's behavior is
    time_consistency = measure_time_consistency(interactions)
    action_consistency = measure_action_consistency(interactions)

    (time_consistency + action_consistency) / 2
  end

  defp measure_time_consistency(interactions) do
    time_groups = Enum.group_by(interactions, & &1.context.time_of_day)

    if map_size(time_groups) == 0 do
      0.0
    else
      # Lower variance = higher consistency
      counts = Enum.map(time_groups, fn {_, group} -> length(group) end)
      avg = Enum.sum(counts) / length(counts)
      variance = Enum.sum(Enum.map(counts, fn c -> :math.pow(c - avg, 2) end)) / length(counts)

      1.0 / (1.0 + variance / avg)
    end
  end

  defp measure_action_consistency(interactions) do
    action_groups = Enum.group_by(interactions, & &1.action.type)

    if map_size(action_groups) == 0 do
      0.0
    else
      # Fewer action types = higher consistency
      1.0 / map_size(action_groups)
    end
  end
end
