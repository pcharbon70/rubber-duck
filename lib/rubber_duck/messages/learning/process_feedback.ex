defmodule RubberDuck.Messages.Learning.ProcessFeedback do
  @moduledoc """
  Message for processing feedback on agent experiences.
  
  Replaces the "learning.feedback.process" signal pattern.
  """
  
  @enforce_keys [:agent_id, :experience_id, :feedback]
  defstruct [
    :agent_id,
    :experience_id,
    :feedback,
    :learning_rate,
    metadata: %{}
  ]
  
  @type feedback_type :: :positive | :negative | :neutral | :corrective
  
  @type feedback :: %{
    type: feedback_type(),
    value: float() | nil,
    corrections: map() | nil,
    correction_factor: float() | nil
  }
  
  @type t :: %__MODULE__{
    agent_id: String.t(),
    experience_id: String.t(),
    feedback: feedback(),
    learning_rate: float() | nil,
    metadata: map()
  }
  
  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.Learning.ProcessFeedback
    
    def validate(%ProcessFeedback{} = msg) do
      with :ok <- validate_agent_id(msg.agent_id),
           :ok <- validate_experience_id(msg.experience_id),
           :ok <- validate_feedback(msg.feedback),
           :ok <- validate_learning_rate(msg.learning_rate) do
        {:ok, msg}
      end
    end
    
    def route(%ProcessFeedback{} = msg, context) do
      if Code.ensure_loaded?(RubberDuck.Skills.LearningSkill) do
        RubberDuck.Skills.LearningSkill.handle_process_feedback(msg, context)
      else
        {:error, :handler_not_loaded}
      end
    end
    
    def to_jido_signal(%ProcessFeedback{} = msg) do
      %{
        type: "learning.feedback.process",
        data: %{
          agent_id: msg.agent_id,
          experience_id: msg.experience_id,
          feedback: msg.feedback,
          learning_rate: msg.learning_rate
        },
        metadata: msg.metadata
      }
    end
    
    def priority(%ProcessFeedback{feedback: %{type: :corrective}}), do: :high
    def priority(_), do: :normal
    
    def timeout(_), do: 5_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))
    
    defp validate_agent_id(id) when is_binary(id) and byte_size(id) > 0, do: :ok
    defp validate_agent_id(_), do: {:error, :invalid_agent_id}
    
    defp validate_experience_id(id) when is_binary(id) and byte_size(id) > 0, do: :ok
    defp validate_experience_id(_), do: {:error, :invalid_experience_id}
    
    defp validate_feedback(%{type: type}) when type in [:positive, :negative, :neutral, :corrective], do: :ok
    defp validate_feedback(_), do: {:error, :invalid_feedback}
    
    defp validate_learning_rate(nil), do: :ok
    defp validate_learning_rate(rate) when is_float(rate) and rate >= 0 and rate <= 1, do: :ok
    defp validate_learning_rate(_), do: {:error, :invalid_learning_rate}
  end
end