defmodule RubberDuck.Messages.Project.DependencyUpdate do
  @moduledoc """
  Message to trigger dependency updates.

  Replaces the string-based signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:project_id]
  defstruct [:project_id, :dependencies, :update_strategy, metadata: %{}]

  @type t :: %__MODULE__{
          project_id: String.t(),
          dependencies: list() | nil,
          update_strategy: atom() | nil,
          metadata: map()
        }
end
