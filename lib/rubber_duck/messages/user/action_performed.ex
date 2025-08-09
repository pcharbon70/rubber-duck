defmodule RubberDuck.Messages.User.ActionPerformed do
  @moduledoc """
  Message indicating a user performed an action.
  
  Replaces the string-based signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:user_id, :action]
  defstruct [:user_id, :action, :details, :timestamp]

  @type t :: %__MODULE__{
          user_id: String.t(),
          action: String.t() | atom(),
          details: map() | nil,
          timestamp: DateTime.t() | nil
        }
end