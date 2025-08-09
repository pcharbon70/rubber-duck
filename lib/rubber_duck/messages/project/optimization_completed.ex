defmodule RubberDuck.Messages.Project.OptimizationCompleted do
  @moduledoc """
  Message indicating optimization has been completed.
  
  Replaces the string-based signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:project_id]
  defstruct [:project_id, :optimization_type, :results, :improvements, :timestamp]

  @type t :: %__MODULE__{
          project_id: String.t(),
          optimization_type: atom() | nil,
          results: list() | nil,
          improvements: map() | nil,
          timestamp: DateTime.t() | nil
        }
end