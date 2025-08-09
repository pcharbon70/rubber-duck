defmodule RubberDuck.Messages.Project.ImpactAnalysis do
  @moduledoc """
  Message to request impact analysis.

  Replaces the string-based signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:project_id]
  defstruct [:project_id, :change_type, :targets, metadata: %{}]

  @type t :: %__MODULE__{
          project_id: String.t(),
          change_type: atom() | nil,
          targets: list() | nil,
          metadata: map()
        }
end
