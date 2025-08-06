defmodule RubberDuck.Messages.Project.OptimizeResources do
  @moduledoc """
  Message for optimizing project resource allocation.
  
  Replaces the string-based "project.resources.optimize" signal pattern
  with a strongly-typed struct.
  """
  
  @enforce_keys [:project_id]
  defstruct [
    :project_id,
    :optimization_goal,
    :constraints,
    :include_recommendations,
    metadata: %{}
  ]
  
  @type optimization_goal :: :cost | :performance | :balanced
  
  @type t :: %__MODULE__{
    project_id: String.t(),
    optimization_goal: optimization_goal() | nil,
    constraints: map() | nil,
    include_recommendations: boolean(),
    metadata: map()
  }
  
  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.Project.OptimizeResources
    
    def validate(%OptimizeResources{} = msg) do
      with :ok <- validate_project_id(msg.project_id),
           :ok <- validate_goal(msg.optimization_goal) do
        {:ok, msg}
      end
    end
    
    def route(%OptimizeResources{} = msg, context) do
      if Code.ensure_loaded?(RubberDuck.Skills.ProjectManagementSkill) do
        RubberDuck.Skills.ProjectManagementSkill.handle_optimize_resources(msg, context)
      else
        {:error, :handler_not_loaded}
      end
    end
    
    def to_jido_signal(%OptimizeResources{} = msg) do
      %{
        type: "project.resources.optimize",
        data: Map.from_struct(msg) |> Map.delete(:metadata),
        metadata: msg.metadata
      }
    end
    
    def priority(%OptimizeResources{optimization_goal: :performance}), do: :high
    def priority(_), do: :normal
    
    def timeout(_), do: 20_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))
    
    defp validate_project_id(id) when is_binary(id) and byte_size(id) > 0, do: :ok
    defp validate_project_id(_), do: {:error, :invalid_project_id}
    
    defp validate_goal(nil), do: :ok
    defp validate_goal(goal) when goal in [:cost, :performance, :balanced], do: :ok
    defp validate_goal(_), do: {:error, :invalid_optimization_goal}
  end
end