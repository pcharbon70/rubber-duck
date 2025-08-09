defmodule RubberDuck.Messages.Project.QualityDegraded do
  @moduledoc """
  Message indicating project quality has degraded.

  Replaces the string-based signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:project_id]
  defstruct [:project_id, :metrics, :violations, :severity, :timestamp]

  @type severity :: :low | :medium | :high | :critical

  @type t :: %__MODULE__{
          project_id: String.t(),
          metrics: map() | nil,
          violations: list() | nil,
          severity: severity() | nil,
          timestamp: DateTime.t() | nil
        }
end
