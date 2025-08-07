defmodule RubberDuck.Messages.AI.QualityAssess do
  @moduledoc """
  Message for AI quality assessment.

  Replaces the string-based "ai.quality.assess" signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:target, :assessment_type]
  defstruct [
    :target,
    :assessment_type,
    :criteria,
    :baseline,
    :compare_to_baseline,
    :include_scores,
    :include_recommendations,
    metadata: %{}
  ]

  @type assessment_type :: :code | :analysis | :prediction | :recommendation

  @type t :: %__MODULE__{
          target: String.t() | map(),
          assessment_type: assessment_type(),
          criteria: map() | nil,
          baseline: map() | nil,
          compare_to_baseline: boolean() | nil,
          include_scores: boolean() | nil,
          include_recommendations: boolean() | nil,
          metadata: map()
        }

  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.AI.QualityAssess

    def validate(%QualityAssess{} = msg) do
      with :ok <- validate_target(msg.target),
           :ok <- validate_assessment_type(msg.assessment_type) do
        {:ok, msg}
      end
    end

    def route(%QualityAssess{} = msg, context) do
      # Route to AI Analysis Agent
      if Code.ensure_loaded?(RubberDuck.Agents.AIAnalysisAgent) do
        RubberDuck.Agents.AIAnalysisAgent.handle_instruction({:assess_quality, msg}, context)
      else
        {:error, :handler_not_loaded}
      end
    end

    def to_jido_signal(%QualityAssess{} = msg) do
      data = Map.from_struct(msg)
      %{
        type: "ai.quality.assess",
        data: data |> Map.delete(:metadata),
        metadata: msg.metadata
      }
    end

    def priority(_), do: :normal
    def timeout(_), do: 20_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))

    defp validate_target(target) when is_binary(target) or is_map(target), do: :ok
    defp validate_target(_), do: {:error, :invalid_target}

    defp validate_assessment_type(type)
         when type in [:code, :analysis, :prediction, :recommendation],
         do: :ok

    defp validate_assessment_type(_), do: {:error, :invalid_assessment_type}
  end
end
