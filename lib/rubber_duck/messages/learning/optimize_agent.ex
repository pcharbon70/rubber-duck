defmodule RubberDuck.Messages.Learning.OptimizeAgent do
  @moduledoc """
  Message for optimizing agent behavior based on learning.
  
  Replaces the "learning.optimize.agent" signal pattern.
  """
  
  @enforce_keys [:agent_id]
  defstruct [
    :agent_id,
    goals: [:performance, :accuracy, :efficiency],
    use_historical_data: true,
    optimization_strategy: :balanced,
    metadata: %{}
  ]
  
  @type goal :: :performance | :accuracy | :efficiency | :reliability
  @type strategy :: :aggressive | :balanced | :conservative
  
  @type t :: %__MODULE__{
    agent_id: String.t(),
    goals: [goal()],
    use_historical_data: boolean(),
    optimization_strategy: strategy(),
    metadata: map()
  }
  
  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.Learning.OptimizeAgent
    
    def validate(%OptimizeAgent{} = msg) do
      with :ok <- validate_agent_id(msg.agent_id),
           :ok <- validate_goals(msg.goals),
           :ok <- validate_strategy(msg.optimization_strategy) do
        {:ok, msg}
      end
    end
    
    def route(%OptimizeAgent{} = msg, context) do
      if Code.ensure_loaded?(RubberDuck.Skills.LearningSkill) do
        RubberDuck.Skills.LearningSkill.handle_optimize_agent(msg, context)
      else
        {:error, :handler_not_loaded}
      end
    end
    
    def to_jido_signal(%OptimizeAgent{} = msg) do
      %{
        type: "learning.optimize.agent",
        data: Map.from_struct(msg) |> Map.delete(:metadata),
        metadata: msg.metadata
      }
    end
    
    def priority(_), do: :low  # Optimization is background task
    def timeout(_), do: 30_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))
    
    defp validate_agent_id(id) when is_binary(id) and byte_size(id) > 0, do: :ok
    defp validate_agent_id(_), do: {:error, :invalid_agent_id}
    
    defp validate_goals(goals) when is_list(goals) do
      valid_goals = [:performance, :accuracy, :efficiency, :reliability]
      if Enum.all?(goals, &(&1 in valid_goals)) do
        :ok
      else
        {:error, :invalid_goals}
      end
    end
    defp validate_goals(_), do: {:error, :goals_must_be_list}
    
    defp validate_strategy(strategy) when strategy in [:aggressive, :balanced, :conservative], do: :ok
    defp validate_strategy(_), do: {:error, :invalid_strategy}
  end
end