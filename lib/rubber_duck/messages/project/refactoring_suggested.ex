defmodule RubberDuck.Messages.Project.RefactoringSuggested do
  @moduledoc """
  Message indicating refactoring suggestions are available.

  Replaces the string-based signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:project_id]
  defstruct [:project_id, :suggestions, :priority, :impact, :timestamp]

  @type priority :: :low | :medium | :high

  @type t :: %__MODULE__{
          project_id: String.t(),
          suggestions: list() | nil,
          priority: priority() | nil,
          impact: map() | nil,
          timestamp: DateTime.t() | nil
        }
end
