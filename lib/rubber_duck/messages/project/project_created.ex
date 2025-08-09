defmodule RubberDuck.Messages.Project.ProjectCreated do
  @moduledoc """
  Message indicating a project was created.

  Replaces the string-based signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:project_id]
  defstruct [:project_id, :name, :path, :timestamp]

  @type t :: %__MODULE__{
          project_id: String.t(),
          name: String.t() | nil,
          path: String.t() | nil,
          timestamp: DateTime.t() | nil
        }
end
