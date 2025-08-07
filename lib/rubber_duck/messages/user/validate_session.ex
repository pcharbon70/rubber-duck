defmodule RubberDuck.Messages.User.ValidateSession do
  @moduledoc """
  Message for validating user session.

  Replaces the string-based "user.session.validate" signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:user_id, :session_id]
  defstruct [
    :user_id,
    :session_id,
    :check_expiry,
    :refresh_if_valid,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          user_id: String.t(),
          session_id: String.t(),
          check_expiry: boolean(),
          refresh_if_valid: boolean(),
          metadata: map()
        }

  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.User.ValidateSession

    def validate(%ValidateSession{} = msg) do
      with :ok <- validate_user_id(msg.user_id),
           :ok <- validate_session_id(msg.session_id) do
        {:ok, msg}
      end
    end

    def route(%ValidateSession{} = msg, context) do
      if Code.ensure_loaded?(RubberDuck.Skills.UserManagementSkill) do
        RubberDuck.Skills.UserManagementSkill.handle_validate_session(msg, context)
      else
        {:error, :handler_not_loaded}
      end
    end

    def to_jido_signal(%ValidateSession{} = msg) do
      %{
        type: "user.session.validate",
        data: Map.from_struct(msg) |> Map.delete(:metadata),
        metadata: msg.metadata
      }
    end

    def priority(_), do: :high
    def timeout(_), do: 3_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))

    defp validate_user_id(id) when is_binary(id) and byte_size(id) > 0, do: :ok
    defp validate_user_id(_), do: {:error, :invalid_user_id}

    defp validate_session_id(id) when is_binary(id) and byte_size(id) > 0, do: :ok
    defp validate_session_id(_), do: {:error, :invalid_session_id}
  end
end
