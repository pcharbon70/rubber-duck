defmodule RubberDuck.Messages.Code.ImpactAssess do
  @moduledoc """
  Message for assessing the impact of code changes.
  
  Replaces the "code.impact.assess" signal pattern.
  """
  
  @enforce_keys [:file_path, :changes]
  defstruct [
    :file_path,
    :changes,
    include_dependencies: true,
    include_performance: true,
    include_security: true,
    opts: %{},
    metadata: %{}
  ]
  
  @type t :: %__MODULE__{
    file_path: String.t(),
    changes: map(),
    include_dependencies: boolean(),
    include_performance: boolean(),
    include_security: boolean(),
    opts: map(),
    metadata: map()
  }
  
  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.Code.ImpactAssess
    
    def validate(%ImpactAssess{} = msg) do
      with :ok <- validate_file_path(msg.file_path),
           :ok <- validate_changes(msg.changes) do
        {:ok, msg}
      end
    end
    
    def route(%ImpactAssess{} = msg, context) do
      if Code.ensure_loaded?(RubberDuck.Skills.CodeAnalysis) do
        RubberDuck.Skills.CodeAnalysis.handle_impact_assess(msg, context)
      else
        {:error, :handler_not_loaded}
      end
    end
    
    def to_jido_signal(%ImpactAssess{} = msg) do
      %{
        type: "code.impact.assess",
        data: Map.from_struct(msg) |> Map.delete(:metadata),
        metadata: msg.metadata
      }
    end
    
    def priority(%ImpactAssess{changes: changes}) when map_size(changes) > 10, do: :high
    def priority(_), do: :normal
    
    def timeout(_), do: 15_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))
    
    defp validate_file_path(path) when is_binary(path) and byte_size(path) > 0, do: :ok
    defp validate_file_path(_), do: {:error, :invalid_file_path}
    
    defp validate_changes(changes) when is_map(changes), do: :ok
    defp validate_changes(_), do: {:error, :changes_must_be_map}
  end
end