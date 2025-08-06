defmodule RubberDuck.Messages.Code.PerformanceAnalyze do
  @moduledoc """
  Message for analyzing code performance characteristics.

  Replaces the "code.performance.analyze" signal pattern.
  """

  @enforce_keys [:content]
  defstruct [
    :content,
    :file_path,
    analyze_complexity: true,
    analyze_memory: true,
    analyze_database: true,
    analyze_bottlenecks: true,
    metrics: %{},
    opts: %{},
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          content: String.t(),
          file_path: String.t() | nil,
          analyze_complexity: boolean(),
          analyze_memory: boolean(),
          analyze_database: boolean(),
          analyze_bottlenecks: boolean(),
          metrics: map(),
          opts: map(),
          metadata: map()
        }

  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.Code.PerformanceAnalyze

    def validate(%PerformanceAnalyze{} = msg) do
      if is_binary(msg.content) and byte_size(msg.content) > 0 do
        {:ok, msg}
      else
        {:error, :invalid_content}
      end
    end

    def route(%PerformanceAnalyze{} = msg, context) do
      if Code.ensure_loaded?(RubberDuck.Skills.CodeAnalysisSkill) do
        RubberDuck.Skills.CodeAnalysisSkill.handle_performance_analyze(msg, context)
      else
        {:error, :handler_not_loaded}
      end
    end

    def to_jido_signal(%PerformanceAnalyze{} = msg) do
      %{
        type: "code.performance.analyze",
        data: Map.from_struct(msg) |> Map.delete(:metadata),
        metadata: msg.metadata
      }
    end

    def priority(_), do: :normal
    def timeout(_), do: 20_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))
  end
end
