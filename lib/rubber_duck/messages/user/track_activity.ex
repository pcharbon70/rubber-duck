defmodule RubberDuck.Messages.User.TrackActivity do
  @moduledoc """
  Message for tracking user activity.

  Replaces the string-based "user.activity.track" signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:user_id, :activity_type]
  defstruct [
    :user_id,
    :activity_type,
    :activity_data,
    :timestamp,
    :session_id,
    metadata: %{}
  ]

  @type activity_type :: :code_edit | :file_open | :command_run | :search | :navigation

  @type t :: %__MODULE__{
          user_id: String.t(),
          activity_type: activity_type(),
          activity_data: map() | nil,
          timestamp: DateTime.t() | nil,
          session_id: String.t() | nil,
          metadata: map()
        }

  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.User.TrackActivity

    def validate(%TrackActivity{} = msg) do
      with :ok <- validate_user_id(msg.user_id),
           :ok <- validate_activity_type(msg.activity_type) do
        {:ok, msg}
      end
    end

    def route(%TrackActivity{} = msg, context) do
      if Code.ensure_loaded?(RubberDuck.Skills.UserManagementSkill) do
        RubberDuck.Skills.UserManagementSkill.handle_track_activity(msg, context)
      else
        {:error, :handler_not_loaded}
      end
    end

    def to_jido_signal(%TrackActivity{} = msg) do
      data = Map.from_struct(msg)

      %{
        type: "user.activity.track",
        data: data |> Map.delete(:metadata),
        metadata: msg.metadata
      }
    end

    def priority(%TrackActivity{activity_type: :command_run}), do: :high
    def priority(_), do: :low

    def timeout(_), do: 2_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))

    defp validate_user_id(id) when is_binary(id) and byte_size(id) > 0, do: :ok
    defp validate_user_id(_), do: {:error, :invalid_user_id}

    defp validate_activity_type(type)
         when type in [:code_edit, :file_open, :command_run, :search, :navigation],
         do: :ok

    defp validate_activity_type(_), do: {:error, :invalid_activity_type}
  end
end
