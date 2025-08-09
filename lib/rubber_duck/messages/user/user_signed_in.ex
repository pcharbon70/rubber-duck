defmodule RubberDuck.Messages.User.UserSignedIn do
  @moduledoc """
  Message indicating a user signed in.
  
  Replaces the string-based signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:user_id]
  defstruct [:user_id, :session_id, :metadata, :timestamp]

  @type t :: %__MODULE__{
          user_id: String.t(),
          session_id: String.t() | nil,
          metadata: map() | nil,
          timestamp: DateTime.t() | nil
        }
end