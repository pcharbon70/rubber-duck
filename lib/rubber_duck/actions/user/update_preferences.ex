defmodule RubberDuck.Actions.User.UpdatePreferences do
  @moduledoc """
  Action to update user preferences based on learned behavior.
  """

  use Jido.Action,
    name: "update_preferences",
    description: "Updates user preferences based on behavioral patterns",
    schema: [
      user_id: [type: :string, required: true],
      current_preferences: [type: :map, default: %{}],
      behavior_analysis: [type: :map, required: true],
      learning_rate: [type: :float, default: 0.1]
    ]

  @impl true
  def run(params, _context) do
    updated_prefs =
      params.current_preferences
      |> update_action_preferences(params.behavior_analysis, params.learning_rate)
      |> update_time_preferences(params.behavior_analysis, params.learning_rate)
      |> update_feature_preferences(params.behavior_analysis)
      |> add_metadata()

    {:ok, updated_prefs}
  end

  defp update_action_preferences(preferences, analysis, learning_rate) do
    action_prefs = Map.get(preferences, :preferred_actions, %{})

    updated_actions =
      Enum.reduce(analysis.action_frequency, action_prefs, fn {action, stats}, acc ->
        current_weight = Map.get(acc, action, 0.5)

        # Adjust weight based on frequency
        adjustment =
          if stats.percentage > 20 do
            learning_rate
          else
            -learning_rate * 0.5
          end

        new_weight = max(0.0, min(1.0, current_weight + adjustment))
        Map.put(acc, action, new_weight)
      end)

    Map.put(preferences, :preferred_actions, updated_actions)
  end

  defp update_time_preferences(preferences, analysis, learning_rate) do
    time_prefs = Map.get(preferences, :preferred_times, %{})

    updated_times =
      Enum.reduce(analysis.time_patterns.by_time_of_day, time_prefs, fn {time, stats}, acc ->
        current_weight = Map.get(acc, time, 0.5)

        # Increase weight for frequently used times
        adjustment = stats.percentage / 100 * learning_rate
        new_weight = min(1.0, current_weight + adjustment)

        Map.put(acc, time, new_weight)
      end)

    preferences
    |> Map.put(:preferred_times, updated_times)
    |> Map.put(:peak_hours, analysis.time_patterns.peak_hours)
  end

  defp update_feature_preferences(preferences, analysis) do
    # Extract feature preferences from sequence patterns
    feature_prefs =
      analysis.sequence_patterns
      |> Enum.filter(&(&1.confidence > 0.1))
      |> Enum.map(fn pattern ->
        {pattern.sequence,
         %{
           confidence: pattern.confidence,
           frequency: pattern.count
         }}
      end)
      |> Map.new()

    Map.put(preferences, :feature_sequences, feature_prefs)
  end

  defp add_metadata(preferences) do
    Map.merge(preferences, %{
      last_updated: DateTime.utc_now(),
      version: Map.get(preferences, :version, 0) + 1
    })
  end
end
