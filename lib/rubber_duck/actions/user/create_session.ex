defmodule RubberDuck.Actions.User.CreateSession do
  @moduledoc """
  Action to create a new user session.
  """

  use Jido.Action,
    name: "create_session",
    description: "Creates a new session for a user",
    schema: [
      user_id: [type: :string, required: true],
      metadata: [type: :map, default: %{}]
    ]

  @impl true
  def run(params, _context) do
    session = %{
      id: generate_session_id(),
      user_id: params.user_id,
      started_at: DateTime.utc_now(),
      last_activity: DateTime.utc_now(),
      metadata: params.metadata,
      active: true
    }

    {:ok, session}
  end

  defp generate_session_id do
    "sess_#{UUID.uuid4()}"
  end
end
