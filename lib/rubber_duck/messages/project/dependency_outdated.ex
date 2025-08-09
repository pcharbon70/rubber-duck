defmodule RubberDuck.Messages.Project.DependencyOutdated do
  @moduledoc """
  Message indicating dependencies are outdated.
  
  Replaces the string-based signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:project_id]
  defstruct [:project_id, :dependencies, :vulnerabilities, :timestamp]

  @type t :: %__MODULE__{
          project_id: String.t(),
          dependencies: list() | nil,
          vulnerabilities: list() | nil,
          timestamp: DateTime.t() | nil
        }
end