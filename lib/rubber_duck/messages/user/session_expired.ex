defmodule RubberDuck.Messages.User.SessionExpired do
  @moduledoc """
  Message indicating a user session has expired.
  
  Replaces the string-based signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:user_id]
  defstruct [:user_id, :session_id, :reason, :timestamp]

  @type t :: %__MODULE__{
          user_id: String.t(),
          session_id: String.t() | nil,
          reason: atom() | nil,
          timestamp: DateTime.t() | nil
        }
end