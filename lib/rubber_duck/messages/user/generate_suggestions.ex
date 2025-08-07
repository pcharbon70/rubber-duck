defmodule RubberDuck.Messages.User.GenerateSuggestions do
  @moduledoc """
  Message for generating personalized suggestions for a user.

  Replaces the string-based "user.suggestions.generate" signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:user_id]
  defstruct [
    :user_id,
    :context,
    :suggestion_types,
    :max_suggestions,
    metadata: %{}
  ]

  @type suggestion_type :: :workflow | :shortcut | :optimization | :learning

  @type t :: %__MODULE__{
          user_id: String.t(),
          context: map() | nil,
          suggestion_types: [suggestion_type()] | nil,
          max_suggestions: pos_integer() | nil,
          metadata: map()
        }

  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.User.GenerateSuggestions

    def validate(%GenerateSuggestions{} = msg) do
      with :ok <- validate_user_id(msg.user_id),
           :ok <- validate_suggestion_types(msg.suggestion_types),
           :ok <- validate_max_suggestions(msg.max_suggestions) do
        {:ok, msg}
      end
    end

    def route(%GenerateSuggestions{} = msg, context) do
      if Code.ensure_loaded?(RubberDuck.Skills.UserManagementSkill) do
        RubberDuck.Skills.UserManagementSkill.handle_generate_suggestions(msg, context)
      else
        {:error, :handler_not_loaded}
      end
    end

    def to_jido_signal(%GenerateSuggestions{} = msg) do
      %{
        type: "user.suggestions.generate",
        data: Map.from_struct(msg) |> Map.delete(:metadata),
        metadata: msg.metadata
      }
    end

    def priority(_), do: :low
    def timeout(_), do: 10_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))

    defp validate_user_id(id) when is_binary(id) and byte_size(id) > 0, do: :ok
    defp validate_user_id(_), do: {:error, :invalid_user_id}

    defp validate_suggestion_types(nil), do: :ok

    defp validate_suggestion_types(types) when is_list(types) do
      valid_types = [:workflow, :shortcut, :optimization, :learning]

      if Enum.all?(types, &(&1 in valid_types)) do
        :ok
      else
        {:error, :invalid_suggestion_types}
      end
    end

    defp validate_suggestion_types(_), do: {:error, :suggestion_types_must_be_list}

    defp validate_max_suggestions(nil), do: :ok
    defp validate_max_suggestions(max) when is_integer(max) and max > 0, do: :ok
    defp validate_max_suggestions(_), do: {:error, :invalid_max_suggestions}
  end
end
