defmodule RubberDuck.Messages.Project.MonitorHealth do
  @moduledoc """
  Message for monitoring project health metrics.
  
  Replaces the string-based "project.health.monitor" signal pattern
  with a strongly-typed struct.
  """
  
  @enforce_keys [:project_id]
  defstruct [
    :project_id,
    metrics: [:quality, :velocity, :debt],
    threshold_alerts: true,
    metadata: %{}
  ]
  
  @type metric :: :quality | :velocity | :debt | :coverage | :complexity
  
  @type t :: %__MODULE__{
    project_id: String.t(),
    metrics: [metric()],
    threshold_alerts: boolean(),
    metadata: map()
  }
  
  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.Project.MonitorHealth
    
    def validate(%MonitorHealth{} = msg) do
      with :ok <- validate_project_id(msg.project_id),
           :ok <- validate_metrics(msg.metrics) do
        {:ok, msg}
      end
    end
    
    def route(%MonitorHealth{} = msg, context) do
      if Code.ensure_loaded?(RubberDuck.Skills.ProjectManagementSkill) do
        RubberDuck.Skills.ProjectManagementSkill.handle_monitor_health(msg, context)
      else
        {:error, :handler_not_loaded}
      end
    end
    
    def to_jido_signal(%MonitorHealth{} = msg) do
      %{
        type: "project.health.monitor",
        data: Map.from_struct(msg) |> Map.delete(:metadata),
        metadata: msg.metadata
      }
    end
    
    def priority(_), do: :low
    def timeout(_), do: 30_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))
    
    defp validate_project_id(id) when is_binary(id) and byte_size(id) > 0, do: :ok
    defp validate_project_id(_), do: {:error, :invalid_project_id}
    
    defp validate_metrics(metrics) when is_list(metrics) do
      valid_metrics = [:quality, :velocity, :debt, :coverage, :complexity]
      if Enum.all?(metrics, &(&1 in valid_metrics)) do
        :ok
      else
        {:error, :invalid_metrics}
      end
    end
    defp validate_metrics(_), do: {:error, :metrics_must_be_list}
  end
end