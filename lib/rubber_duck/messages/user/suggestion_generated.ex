defmodule RubberDuck.Messages.User.SuggestionGenerated do
  @moduledoc """
  Message indicating suggestions were generated for a user.
  
  Replaces the string-based signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:user_id]
  defstruct [:user_id, :suggestions, :context, :timestamp]

  @type t :: %__MODULE__{
          user_id: String.t(),
          suggestions: list() | nil,
          context: map() | nil,
          timestamp: DateTime.t() | nil
        }
end