defmodule RubberDuck.Messages.User.PreferenceLearned do
  @moduledoc """
  Message indicating a user preference was learned.

  Replaces the string-based signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:user_id]
  defstruct [:user_id, :preference_key, :preference_value, :confidence, :timestamp]

  @type t :: %__MODULE__{
          user_id: String.t(),
          preference_key: String.t() | nil,
          preference_value: any() | nil,
          confidence: float() | nil,
          timestamp: DateTime.t() | nil
        }
end
