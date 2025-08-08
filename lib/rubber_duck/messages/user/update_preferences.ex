defmodule RubberDuck.Messages.User.UpdatePreferences do
  @moduledoc """
  Message for updating user preferences.

  Replaces the string-based "user.preferences.update" signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:user_id, :preferences]
  defstruct [
    :user_id,
    :preferences,
    :merge_strategy,
    metadata: %{}
  ]

  @type merge_strategy :: :replace | :merge | :deep_merge

  @type t :: %__MODULE__{
          user_id: String.t(),
          preferences: map(),
          merge_strategy: merge_strategy(),
          metadata: map()
        }

  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.User.UpdatePreferences

    def validate(%UpdatePreferences{} = msg) do
      with :ok <- validate_user_id(msg.user_id),
           :ok <- validate_preferences(msg.preferences),
           :ok <- validate_merge_strategy(msg.merge_strategy) do
        {:ok, msg}
      end
    end

    def route(%UpdatePreferences{} = msg, context) do
      if Code.ensure_loaded?(RubberDuck.Skills.UserManagementSkill) do
        RubberDuck.Skills.UserManagementSkill.handle_update_preferences(msg, context)
      else
        {:error, :handler_not_loaded}
      end
    end

    def to_jido_signal(%UpdatePreferences{} = msg) do
      data = Map.from_struct(msg)

      %{
        type: "user.preferences.update",
        data: data |> Map.delete(:metadata),
        metadata: msg.metadata
      }
    end

    def priority(_), do: :normal
    def timeout(_), do: 5_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))

    defp validate_user_id(id) when is_binary(id) and byte_size(id) > 0, do: :ok
    defp validate_user_id(_), do: {:error, :invalid_user_id}

    defp validate_preferences(prefs) when is_map(prefs), do: :ok
    defp validate_preferences(_), do: {:error, :preferences_must_be_map}

    defp validate_merge_strategy(nil), do: :ok

    defp validate_merge_strategy(strategy) when strategy in [:replace, :merge, :deep_merge],
      do: :ok

    defp validate_merge_strategy(_), do: {:error, :invalid_merge_strategy}
  end
end
