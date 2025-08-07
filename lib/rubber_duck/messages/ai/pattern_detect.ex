defmodule RubberDuck.Messages.AI.PatternDetect do
  @moduledoc """
  Message for AI pattern detection.

  Replaces the string-based "ai.pattern.detect" signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:data_source]
  defstruct [
    :data_source,
    :pattern_types,
    :confidence_threshold,
    :time_window,
    :min_occurrences,
    :context,
    metadata: %{}
  ]

  @type pattern_type :: :behavioral | :structural | :temporal | :anomaly | :correlation

  @type t :: %__MODULE__{
          data_source: String.t() | map(),
          pattern_types: [pattern_type()] | nil,
          confidence_threshold: float() | nil,
          time_window: integer() | nil,
          min_occurrences: integer() | nil,
          context: map() | nil,
          metadata: map()
        }

  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.AI.PatternDetect

    def validate(%PatternDetect{} = msg) do
      with :ok <- validate_data_source(msg.data_source),
           :ok <- validate_pattern_types(msg.pattern_types),
           :ok <- validate_confidence_threshold(msg.confidence_threshold) do
        {:ok, msg}
      end
    end

    def route(%PatternDetect{} = msg, context) do
      # Route to AI Analysis Agent
      if Code.ensure_loaded?(RubberDuck.Agents.AIAnalysisAgent) do
        RubberDuck.Agents.AIAnalysisAgent.handle_instruction({:detect_patterns, msg}, context)
      else
        {:error, :handler_not_loaded}
      end
    end

    def to_jido_signal(%PatternDetect{} = msg) do
      %{
        type: "ai.pattern.detect",
        data: Map.from_struct(msg) |> Map.delete(:metadata),
        metadata: msg.metadata
      }
    end

    def priority(%PatternDetect{pattern_types: types}) when is_list(types) do
      if :anomaly in types, do: :high, else: :normal
    end

    def priority(_), do: :normal

    def timeout(_), do: 45_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))

    defp validate_data_source(source) when is_binary(source) or is_map(source), do: :ok
    defp validate_data_source(_), do: {:error, :invalid_data_source}

    defp validate_pattern_types(nil), do: :ok

    defp validate_pattern_types(types) when is_list(types) do
      valid_types = [:behavioral, :structural, :temporal, :anomaly, :correlation]
      if Enum.all?(types, &(&1 in valid_types)), do: :ok, else: {:error, :invalid_pattern_types}
    end

    defp validate_pattern_types(_), do: {:error, :invalid_pattern_types}

    defp validate_confidence_threshold(nil), do: :ok

    defp validate_confidence_threshold(threshold)
         when is_float(threshold) and threshold >= 0 and threshold <= 1,
         do: :ok

    defp validate_confidence_threshold(_), do: {:error, :invalid_confidence_threshold}
  end
end
