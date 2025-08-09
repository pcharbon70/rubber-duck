defmodule RubberDuck.Messages.User.PatternDetected do
  @moduledoc """
  Message indicating a user behavior pattern was detected.
  
  Replaces the string-based signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:user_id]
  defstruct [:user_id, :pattern_type, :confidence, :details, :timestamp]

  @type t :: %__MODULE__{
          user_id: String.t(),
          pattern_type: atom() | nil,
          confidence: float() | nil,
          details: map() | nil,
          timestamp: DateTime.t() | nil
        }
end