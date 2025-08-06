defmodule RubberDuck.Actions.User.GenerateSuggestions do
  @moduledoc """
  Action to generate proactive assistance suggestions based on user patterns.
  """

  use Jido.Action,
    name: "generate_suggestions",
    description: "Generates proactive suggestions based on user behavior patterns",
    schema: [
      user_id: [type: :string, required: true],
      detected_patterns: [type: :map, required: true],
      user_preferences: [type: :map, default: %{}],
      current_context: [type: :map, default: %{}],
      max_suggestions: [type: :pos_integer, default: 5]
    ]

  @impl true
  def run(params, _context) do
    suggestions =
      []
      |> add_temporal_suggestions(params.detected_patterns, params.current_context)
      |> add_sequential_suggestions(params.detected_patterns, params.current_context)
      |> add_contextual_suggestions(params.detected_patterns, params.current_context)
      |> add_preference_based_suggestions(params.user_preferences)
      |> prioritize_suggestions()
      |> Enum.take(params.max_suggestions)

    {:ok,
     %{
       suggestions: suggestions,
       generated_at: DateTime.utc_now(),
       context_used: params.current_context
     }}
  end

  defp add_temporal_suggestions(suggestions, patterns, _context) do
    temporal_patterns = Map.get(patterns, :temporal, %{})
    current_hour = DateTime.utc_now().hour
    current_day = Date.day_of_week(Date.utc_today())

    hourly_suggestions =
      temporal_patterns
      |> Map.get(:hourly, [])
      |> Enum.filter(fn pattern ->
        pattern.time_key == current_hour && pattern.confidence > 0.6
      end)
      |> Enum.flat_map(fn pattern ->
        pattern.dominant_actions
        |> Enum.map(fn action ->
          %{
            type: :temporal,
            action: action.action,
            reason: "You usually #{action.action} at this time",
            confidence: pattern.confidence,
            priority: calculate_priority(:temporal, pattern.confidence)
          }
        end)
      end)

    daily_suggestions =
      temporal_patterns
      |> Map.get(:daily, [])
      |> Enum.filter(fn pattern ->
        pattern.time_key == current_day && pattern.confidence > 0.6
      end)
      |> Enum.flat_map(fn pattern ->
        pattern.dominant_actions
        |> Enum.map(fn action ->
          %{
            type: :temporal,
            action: action.action,
            reason: "You often #{action.action} on #{day_name(current_day)}s",
            confidence: pattern.confidence,
            priority: calculate_priority(:temporal, pattern.confidence)
          }
        end)
      end)

    suggestions ++ hourly_suggestions ++ daily_suggestions
  end

  defp add_sequential_suggestions(suggestions, patterns, context) do
    sequential_patterns = Map.get(patterns, :sequential, [])
    last_action = Map.get(context, :last_action)

    if last_action do
      sequence_suggestions =
        sequential_patterns
        |> Enum.filter(fn pattern ->
          List.first(pattern.sequence) == last_action && pattern.confidence > 0.5
        end)
        |> Enum.map(fn pattern ->
          next_action = Enum.at(pattern.sequence, 1)

          %{
            type: :sequential,
            action: next_action,
            reason: "Based on your pattern of #{format_sequence(pattern.sequence)}",
            confidence: pattern.confidence,
            priority: calculate_priority(:sequential, pattern.confidence)
          }
        end)

      suggestions ++ sequence_suggestions
    else
      suggestions
    end
  end

  defp add_contextual_suggestions(suggestions, patterns, context) do
    contextual_patterns = Map.get(patterns, :contextual, [])
    current_device = Map.get(context, :device_type)
    current_location = Map.get(context, :location_type)

    context_suggestions =
      contextual_patterns
      |> Enum.filter(fn pattern ->
        pattern.context.device == current_device &&
          pattern.context.location == current_location &&
          pattern.confidence > 0.4
      end)
      |> Enum.flat_map(fn pattern ->
        pattern.actions
        |> Enum.take(2)
        |> Enum.map(fn {action, _frequency} ->
          %{
            type: :contextual,
            action: action,
            reason: "Common action when using #{current_device} at #{current_location}",
            confidence: pattern.confidence,
            priority: calculate_priority(:contextual, pattern.confidence)
          }
        end)
      end)

    suggestions ++ context_suggestions
  end

  defp add_preference_based_suggestions(suggestions, preferences) do
    pref_suggestions =
      preferences
      |> Map.get(:preferred_actions, %{})
      |> Enum.filter(fn {_action, weight} -> weight > 0.7 end)
      |> Enum.map(fn {action, weight} ->
        %{
          type: :preference,
          action: action,
          reason: "One of your preferred actions",
          confidence: weight,
          priority: calculate_priority(:preference, weight)
        }
      end)

    suggestions ++ pref_suggestions
  end

  defp prioritize_suggestions(suggestions) do
    suggestions
    |> Enum.uniq_by(& &1.action)
    |> Enum.sort_by(& &1.priority, :desc)
    |> Enum.map(fn suggestion ->
      Map.drop(suggestion, [:priority])
    end)
  end

  defp calculate_priority(type, confidence) do
    type_weight =
      case type do
        # Recent actions are highly relevant
        :sequential -> 1.2
        # Time-based patterns are reliable
        :temporal -> 1.0
        # Context matters but less than sequence
        :contextual -> 0.9
        # General preferences have lower priority
        :preference -> 0.8
      end

    confidence * type_weight
  end

  defp format_sequence(sequence) do
    sequence
    |> Enum.map(&to_string/1)
    |> Enum.join(" → ")
  end

  defp day_name(day_number) do
    case day_number do
      1 -> "Monday"
      2 -> "Tuesday"
      3 -> "Wednesday"
      4 -> "Thursday"
      5 -> "Friday"
      6 -> "Saturday"
      7 -> "Sunday"
    end
  end
end
