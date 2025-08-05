defmodule RubberDuck.Actions.User.ValidateSession do
  @moduledoc """
  Action to validate an existing user session.
  """

  use Jido.Action,
    name: "validate_session",
    description: "Validates if a user session is still active",
    schema: [
      session_id: [type: :string, required: true],
      user_id: [type: :string, required: true],
      timeout_seconds: [type: :pos_integer, default: 1800]
    ]

  @impl true
  def run(params, context) do
    agent = context[:agent]

    case find_session(agent, params.user_id, params.session_id) do
      nil ->
        {:error, :session_not_found}

      session ->
        if session_active?(session, params.timeout_seconds) do
          {:ok, %{valid: true, session: session}}
        else
          {:ok, %{valid: false, reason: :expired}}
        end
    end
  end

  defp find_session(agent, user_id, session_id) do
    sessions = Map.get(agent.state.active_sessions, user_id, [])
    Enum.find(sessions, & &1.id == session_id)
  end

  defp session_active?(session, timeout_seconds) do
    DateTime.diff(DateTime.utc_now(), session.last_activity, :second) <= timeout_seconds
  end
end
