defmodule RubberDuck.Actions.User.RecordInteraction do
  @moduledoc """
  Action to record user interactions for behavioral learning.
  """

  use Jido.Action,
    name: "record_interaction",
    description: "Records a user interaction for pattern analysis",
    schema: [
      user_id: [type: :string, required: true],
      action_type: [type: :atom, required: true],
      action_details: [type: :map, default: %{}],
      context: [type: :map, default: %{}]
    ]

  @impl true
  def run(params, _context) do
    interaction = %{
      id: generate_interaction_id(),
      user_id: params.user_id,
      action: %{
        type: params.action_type,
        details: params.action_details
      },
      context: enrich_context(params.context),
      timestamp: DateTime.utc_now()
    }

    {:ok, interaction}
  end

  defp generate_interaction_id do
    "int_#{System.unique_integer([:positive])}_#{System.os_time(:millisecond)}"
  end

  defp enrich_context(context) do
    Map.merge(context, %{
      time_of_day: get_time_category(),
      day_of_week: Date.day_of_week(Date.utc_today()),
      week_of_year: get_week_of_year(),
      recorded_at: DateTime.utc_now()
    })
  end

  defp get_time_category do
    hour = DateTime.utc_now().hour
    cond do
      hour >= 5 && hour < 12 -> :morning
      hour >= 12 && hour < 17 -> :afternoon
      hour >= 17 && hour < 21 -> :evening
      true -> :night
    end
  end

  defp get_week_of_year do
    {year, week} = :calendar.iso_week_number(Date.to_erl(Date.utc_today()))
    {year, week}
  end
end
