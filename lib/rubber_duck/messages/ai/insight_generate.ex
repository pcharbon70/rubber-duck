defmodule RubberDuck.Messages.AI.InsightGenerate do
  @moduledoc """
  Message for AI insight generation.

  Replaces the string-based "ai.insight.generate" signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:analysis_results]
  defstruct [
    :analysis_results,
    :insight_types,
    :max_insights,
    :combine_related,
    :include_recommendations,
    :context,
    metadata: %{}
  ]

  @type insight_type :: :improvement | :risk | :opportunity | :trend | :anomaly

  @type t :: %__MODULE__{
          analysis_results: map() | [map()],
          insight_types: [insight_type()] | nil,
          max_insights: integer() | nil,
          combine_related: boolean() | nil,
          include_recommendations: boolean() | nil,
          context: map() | nil,
          metadata: map()
        }

  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.AI.InsightGenerate

    def validate(%InsightGenerate{} = msg) do
      with :ok <- validate_analysis_results(msg.analysis_results),
           :ok <- validate_insight_types(msg.insight_types),
           :ok <- validate_max_insights(msg.max_insights) do
        {:ok, msg}
      end
    end

    def route(%InsightGenerate{} = msg, context) do
      # Route to AI Analysis Agent
      if Code.ensure_loaded?(RubberDuck.Agents.AIAnalysisAgent) do
        RubberDuck.Agents.AIAnalysisAgent.handle_instruction({:generate_insights, msg}, context)
      else
        {:error, :handler_not_loaded}
      end
    end

    def to_jido_signal(%InsightGenerate{} = msg) do
      data = Map.from_struct(msg)
      %{
        type: "ai.insight.generate",
        data: data |> Map.delete(:metadata),
        metadata: msg.metadata
      }
    end

    def priority(_), do: :normal
    def timeout(_), do: 30_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))

    defp validate_analysis_results(results) when is_map(results) or is_list(results), do: :ok
    defp validate_analysis_results(_), do: {:error, :invalid_analysis_results}

    defp validate_insight_types(nil), do: :ok

    defp validate_insight_types(types) when is_list(types) do
      valid_types = [:improvement, :risk, :opportunity, :trend, :anomaly]
      if Enum.all?(types, &(&1 in valid_types)), do: :ok, else: {:error, :invalid_insight_types}
    end

    defp validate_insight_types(_), do: {:error, :invalid_insight_types}

    defp validate_max_insights(nil), do: :ok
    defp validate_max_insights(max) when is_integer(max) and max > 0, do: :ok
    defp validate_max_insights(_), do: {:error, :invalid_max_insights}
  end
end
