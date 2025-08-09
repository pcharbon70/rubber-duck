defmodule RubberDuck.Messages.Project.StructureOptimization do
  @moduledoc """
  Message for structure optimization operations.
  
  Replaces the string-based signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:project_id]
  defstruct [:project_id, :optimization_type, :suggestions, metadata: %{}]

  @type t :: %__MODULE__{
          project_id: String.t(),
          optimization_type: atom() | nil,
          suggestions: list() | nil,
          metadata: map()
        }
end