defmodule RubberDuck.Messages.Project.ProjectDeleted do
  @moduledoc """
  Message indicating a project was deleted.

  Replaces the string-based signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:project_id]
  defstruct [:project_id, :timestamp]

  @type t :: %__MODULE__{
          project_id: String.t(),
          timestamp: DateTime.t() | nil
        }
end
