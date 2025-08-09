defmodule RubberDuck.Messages.Project.ProjectUpdated do
  @moduledoc """
  Message indicating a project was updated.
  
  Replaces the string-based signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:project_id]
  defstruct [:project_id, :changes, :timestamp]

  @type t :: %__MODULE__{
          project_id: String.t(),
          changes: map() | nil,
          timestamp: DateTime.t() | nil
        }
end