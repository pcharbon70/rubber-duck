defmodule RubberDuck.Messages.Project.UpdateStatus do
  @moduledoc """
  Message for updating project status.
  
  Replaces the string-based "project.status.update" signal pattern
  with a strongly-typed struct.
  """
  
  @enforce_keys [:project_id, :status]
  defstruct [
    :project_id,
    :status,
    :reason,
    :updated_by,
    metadata: %{}
  ]
  
  @type status :: :active | :paused | :completed | :archived
  
  @type t :: %__MODULE__{
    project_id: String.t(),
    status: status(),
    reason: String.t() | nil,
    updated_by: String.t() | nil,
    metadata: map()
  }
  
  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.Project.UpdateStatus
    
    def validate(%UpdateStatus{} = msg) do
      with :ok <- validate_project_id(msg.project_id),
           :ok <- validate_status(msg.status) do
        {:ok, msg}
      end
    end
    
    def route(%UpdateStatus{} = msg, context) do
      if Code.ensure_loaded?(RubberDuck.Skills.ProjectManagementSkill) do
        RubberDuck.Skills.ProjectManagementSkill.handle_update_status(msg, context)
      else
        {:error, :handler_not_loaded}
      end
    end
    
    def to_jido_signal(%UpdateStatus{} = msg) do
      %{
        type: "project.status.update",
        data: Map.from_struct(msg) |> Map.delete(:metadata),
        metadata: msg.metadata
      }
    end
    
    def priority(%UpdateStatus{status: :completed}), do: :high
    def priority(_), do: :normal
    
    def timeout(_), do: 5_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))
    
    defp validate_project_id(id) when is_binary(id) and byte_size(id) > 0, do: :ok
    defp validate_project_id(_), do: {:error, :invalid_project_id}
    
    defp validate_status(status) when status in [:active, :paused, :completed, :archived], do: :ok
    defp validate_status(_), do: {:error, :invalid_status}
  end
end