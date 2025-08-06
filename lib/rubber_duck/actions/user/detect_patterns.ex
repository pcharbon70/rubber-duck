defmodule RubberDuck.Actions.User.DetectPatterns do
  @moduledoc """
  Action to detect behavior patterns from user interactions.
  """

  use Jido.Action,
    name: "detect_patterns",
    description: "Detects behavioral patterns from user interaction history",
    schema: [
      user_id: [type: :string, required: true],
      interactions: [type: {:list, :map}, required: true],
      min_occurrences: [type: :pos_integer, default: 3],
      confidence_threshold: [type: :float, default: 0.7],
      pattern_types: [type: {:list, :atom}, default: [:temporal, :sequential, :contextual]]
    ]

  @impl true
  def run(params, _context) do
    patterns =
      params.pattern_types
      |> Enum.map(fn type ->
        {type, detect_pattern_type(type, params.interactions, params)}
      end)
      |> Map.new()
      |> filter_by_confidence(params.confidence_threshold)

    {:ok,
     %{
       patterns: patterns,
       pattern_count: count_patterns(patterns),
       confidence_scores: calculate_confidence_scores(patterns)
     }}
  end

  defp detect_pattern_type(:temporal, interactions, params) do
    detect_temporal_patterns(interactions, params.min_occurrences)
  end

  defp detect_pattern_type(:sequential, interactions, params) do
    detect_sequential_patterns(interactions, params.min_occurrences)
  end

  defp detect_pattern_type(:contextual, interactions, params) do
    detect_contextual_patterns(interactions, params.min_occurrences)
  end

  defp detect_temporal_patterns(interactions, min_occurrences) do
    # Group by hour of day and day of week
    hourly_patterns =
      interactions
      |> Enum.group_by(fn int ->
        DateTime.to_time(int.timestamp).hour
      end)
      |> analyze_temporal_groups(min_occurrences, :hourly)

    daily_patterns =
      interactions
      |> Enum.group_by(& &1.context.day_of_week)
      |> analyze_temporal_groups(min_occurrences, :daily)

    %{
      hourly: hourly_patterns,
      daily: daily_patterns,
      combined: combine_temporal_patterns(hourly_patterns, daily_patterns)
    }
  end

  defp analyze_temporal_groups(groups, min_occurrences, type) do
    groups
    |> Enum.filter(fn {_, group} -> length(group) >= min_occurrences end)
    |> Enum.map(fn {time_key, group} ->
      actions = group |> Enum.map(& &1.action.type) |> Enum.frequencies()

      %{
        time_key: time_key,
        type: type,
        occurrences: length(group),
        dominant_actions: get_dominant_actions(actions),
        confidence: calculate_temporal_confidence(group, groups |> Map.values() |> List.flatten())
      }
    end)
    |> Enum.sort_by(& &1.confidence, :desc)
  end

  defp combine_temporal_patterns(hourly, daily) do
    # Find patterns that occur at specific times on specific days
    for h <- hourly, d <- daily do
      if h.confidence > 0.5 && d.confidence > 0.5 do
        %{
          pattern: {h.time_key, d.time_key},
          type: :hour_day_combo,
          confidence: (h.confidence + d.confidence) / 2
        }
      end
    end
    |> Enum.filter(& &1)
  end

  defp detect_sequential_patterns(interactions, min_occurrences) do
    # Detect action sequences
    interactions
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.map(fn chunk ->
      Enum.map(chunk, & &1.action.type)
    end)
    |> Enum.frequencies()
    |> Enum.filter(fn {_, count} -> count >= min_occurrences end)
    |> Enum.map(fn {sequence, count} ->
      %{
        sequence: sequence,
        length: length(sequence),
        occurrences: count,
        confidence: calculate_sequence_confidence(count, length(interactions))
      }
    end)
    |> Enum.sort_by(& &1.confidence, :desc)
  end

  defp detect_contextual_patterns(interactions, min_occurrences) do
    # Detect patterns based on context
    context_groups =
      interactions
      |> Enum.group_by(fn int ->
        {int.context.device_type, int.context.location_type}
      end)

    context_groups
    |> Enum.filter(fn {_, group} -> length(group) >= min_occurrences end)
    |> Enum.map(fn {{device, location}, group} ->
      actions = group |> Enum.map(& &1.action.type) |> Enum.frequencies()

      %{
        context: %{device: device, location: location},
        occurrences: length(group),
        actions: actions,
        confidence: length(group) / length(interactions)
      }
    end)
  end

  defp get_dominant_actions(action_frequencies) do
    action_frequencies
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.take(3)
    |> Enum.map(fn {action, count} ->
      %{action: action, frequency: count}
    end)
  end

  defp calculate_temporal_confidence(group, all_interactions) do
    group_size = length(group)
    total_size = length(all_interactions)

    # Confidence based on relative frequency and consistency
    frequency_score = group_size / total_size

    # Check consistency of actions within the group
    action_types = group |> Enum.map(& &1.action.type) |> Enum.uniq() |> length()
    consistency_score = 1.0 / action_types

    (frequency_score + consistency_score) / 2
  end

  defp calculate_sequence_confidence(occurrences, total_interactions) do
    # Higher confidence for more frequent sequences
    base_confidence = occurrences / max(total_interactions - 2, 1)

    # Boost confidence for longer sequences
    length_bonus = :math.log(occurrences + 1) / 10

    min(base_confidence + length_bonus, 1.0)
  end

  defp filter_by_confidence(patterns, threshold) do
    patterns
    |> Enum.map(fn {type, type_patterns} ->
      filtered = filter_type_patterns(type_patterns, threshold)
      {type, filtered}
    end)
    |> Map.new()
  end

  defp filter_type_patterns(%{} = map, threshold) do
    map
    |> Enum.map(fn {k, v} ->
      {k, filter_patterns_list(v, threshold)}
    end)
    |> Map.new()
  end

  defp filter_type_patterns(list, threshold) when is_list(list) do
    filter_patterns_list(list, threshold)
  end

  defp filter_patterns_list(patterns, threshold) when is_list(patterns) do
    Enum.filter(patterns, &(&1.confidence >= threshold))
  end

  defp filter_patterns_list(patterns, _threshold), do: patterns

  defp count_patterns(patterns) do
    patterns
    |> Enum.map(fn {_, type_patterns} ->
      case type_patterns do
        %{} = map ->
          map
          |> Map.values()
          |> Enum.map(&length/1)
          |> Enum.sum()

        list when is_list(list) ->
          length(list)
      end
    end)
    |> Enum.sum()
  end

  defp calculate_confidence_scores(patterns) do
    patterns
    |> Enum.map(fn {type, type_patterns} ->
      avg_confidence = calculate_average_confidence(type_patterns)
      {type, avg_confidence}
    end)
    |> Map.new()
  end

  defp calculate_average_confidence(%{} = map) do
    all_patterns = map |> Map.values() |> List.flatten()
    calculate_list_average_confidence(all_patterns)
  end

  defp calculate_average_confidence(list) when is_list(list) do
    calculate_list_average_confidence(list)
  end

  defp calculate_average_confidence(_), do: 0.0

  defp calculate_list_average_confidence([]), do: 0.0

  defp calculate_list_average_confidence(patterns) do
    confidences = Enum.map(patterns, & &1.confidence)
    Enum.sum(confidences) / length(confidences)
  end
end
