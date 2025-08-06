defmodule RubberDuck.Messages.Learning.RecordExperience do
  @moduledoc """
  Message for recording agent learning experiences.
  
  Replaces the "learning.experience.record" signal pattern.
  """
  
  @enforce_keys [:agent_id, :action, :outcome]
  defstruct [
    :agent_id,
    :action,
    :outcome,
    :context,
    :inputs,
    :outputs,
    :metrics,
    :tags,
    :success,
    metadata: %{}
  ]
  
  @type outcome :: :success | :failure | :partial | :unknown
  
  @type t :: %__MODULE__{
    agent_id: String.t(),
    action: String.t() | atom(),
    outcome: outcome(),
    context: map() | nil,
    inputs: map() | nil,
    outputs: map() | nil,
    metrics: map() | nil,
    tags: [String.t()] | nil,
    success: boolean() | nil,
    metadata: map()
  }
  
  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.Learning.RecordExperience
    
    def validate(%RecordExperience{} = msg) do
      with :ok <- validate_agent_id(msg.agent_id),
           :ok <- validate_outcome(msg.outcome) do
        {:ok, msg}
      end
    end
    
    def route(%RecordExperience{} = msg, context) do
      if Code.ensure_loaded?(RubberDuck.Skills.LearningSkill) do
        RubberDuck.Skills.LearningSkill.handle_record_experience(msg, context)
      else
        {:error, :handler_not_loaded}
      end
    end
    
    def to_jido_signal(%RecordExperience{} = msg) do
      %{
        type: "learning.experience.record",
        data: %{
          agent_id: msg.agent_id,
          action: msg.action,
          outcome: msg.outcome,
          context: msg.context || %{},
          inputs: msg.inputs || %{},
          outputs: msg.outputs || %{},
          metrics: msg.metrics || %{},
          tags: msg.tags || [],
          success: determine_success(msg)
        },
        metadata: msg.metadata
      }
    end
    
    def priority(_), do: :normal
    def timeout(_), do: 5_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))
    
    defp validate_agent_id(id) when is_binary(id) and byte_size(id) > 0, do: :ok
    defp validate_agent_id(_), do: {:error, :invalid_agent_id}
    
    defp validate_outcome(outcome) when outcome in [:success, :failure, :partial, :unknown], do: :ok
    defp validate_outcome(_), do: {:error, :invalid_outcome}
    
    defp determine_success(%{success: success}) when is_boolean(success), do: success
    defp determine_success(%{outcome: :success}), do: true
    defp determine_success(%{outcome: :failure}), do: false
    defp determine_success(_), do: false
  end
end