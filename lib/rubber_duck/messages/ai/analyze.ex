defmodule RubberDuck.Messages.AI.Analyze do
  @moduledoc """
  Message for AI analysis requests.

  Replaces the string-based "ai.analysis.request" signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:target, :analysis_type]
  defstruct [
    :target,
    :analysis_type,
    :depth,
    :include_suggestions,
    :include_metrics,
    :context,
    :priority_areas,
    metadata: %{}
  ]

  @type analysis_type :: :code | :project | :pattern | :quality | :security | :performance
  @type depth :: :shallow | :moderate | :deep

  @type t :: %__MODULE__{
          target: String.t(),
          analysis_type: analysis_type(),
          depth: depth() | nil,
          include_suggestions: boolean() | nil,
          include_metrics: boolean() | nil,
          context: map() | nil,
          priority_areas: [atom()] | nil,
          metadata: map()
        }

  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.AI.Analyze

    def validate(%Analyze{} = msg) do
      with :ok <- validate_target(msg.target),
           :ok <- validate_analysis_type(msg.analysis_type),
           :ok <- validate_depth(msg.depth) do
        {:ok, msg}
      end
    end

    def route(%Analyze{} = msg, context) do
      # Route to AI Analysis Agent
      if Code.ensure_loaded?(RubberDuck.Agents.AIAnalysisAgent) do
        RubberDuck.Agents.AIAnalysisAgent.handle_instruction({:analyze, msg}, context)
      else
        {:error, :handler_not_loaded}
      end
    end

    def to_jido_signal(%Analyze{} = msg) do
      data = Map.from_struct(msg)

      %{
        type: "ai.analysis.request",
        data: data |> Map.delete(:metadata),
        metadata: msg.metadata
      }
    end

    def priority(%Analyze{analysis_type: :security}), do: :critical
    def priority(%Analyze{depth: :deep}), do: :normal
    def priority(_), do: :high

    def timeout(%Analyze{depth: :deep}), do: 120_000
    def timeout(%Analyze{depth: :moderate}), do: 60_000
    def timeout(_), do: 30_000

    def encode(msg), do: Jason.encode!(Map.from_struct(msg))

    defp validate_target(target) when is_binary(target) and byte_size(target) > 0, do: :ok
    defp validate_target(_), do: {:error, :invalid_target}

    defp validate_analysis_type(type)
         when type in [:code, :project, :pattern, :quality, :security, :performance],
         do: :ok

    defp validate_analysis_type(_), do: {:error, :invalid_analysis_type}

    defp validate_depth(nil), do: :ok
    defp validate_depth(depth) when depth in [:shallow, :moderate, :deep], do: :ok
    defp validate_depth(_), do: {:error, :invalid_depth}
  end
end
