defmodule RubberDuck.Messages.Project.AnalyzeStructure do
  @moduledoc """
  Message for requesting project structure analysis.

  Replaces the string-based "project.structure.analyze" signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:project_id]
  defstruct [
    :project_id,
    :include_dependencies,
    :analyze_complexity,
    :depth,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          project_id: String.t(),
          include_dependencies: boolean(),
          analyze_complexity: boolean(),
          depth: :shallow | :deep,
          metadata: map()
        }

  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.Project.AnalyzeStructure

    def validate(%AnalyzeStructure{} = msg) do
      with :ok <- validate_project_id(msg.project_id) do
        {:ok, msg}
      end
    end

    def route(%AnalyzeStructure{} = msg, context) do
      if Code.ensure_loaded?(RubberDuck.Skills.ProjectManagementSkill) do
        RubberDuck.Skills.ProjectManagementSkill.handle_analyze_structure(msg, context)
      else
        {:error, :handler_not_loaded}
      end
    end

    def to_jido_signal(%AnalyzeStructure{} = msg) do
      data = Map.from_struct(msg)

      %{
        type: "project.structure.analyze",
        data: data |> Map.delete(:metadata),
        metadata: msg.metadata
      }
    end

    def priority(_), do: :normal
    def timeout(_), do: 15_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))

    defp validate_project_id(id) when is_binary(id) and byte_size(id) > 0, do: :ok
    defp validate_project_id(_), do: {:error, :invalid_project_id}
  end
end
