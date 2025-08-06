defmodule RubberDuck.Messages.Learning.AnalyzePattern do
  @moduledoc """
  Message for analyzing patterns in agent experiences.

  Replaces the "learning.pattern.analyze" signal pattern.
  """

  @enforce_keys [:agent_id]
  defstruct [
    :agent_id,
    depth: :normal,
    time_window: nil,
    pattern_types: [:action_outcome, :sequence, :temporal],
    metadata: %{}
  ]

  @type depth :: :shallow | :normal | :deep | :comprehensive
  @type pattern_type :: :action_outcome | :sequence | :temporal | :context_correlation

  @type t :: %__MODULE__{
          agent_id: String.t(),
          depth: depth(),
          time_window: {DateTime.t(), DateTime.t()} | nil,
          pattern_types: [pattern_type()],
          metadata: map()
        }

  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.Learning.AnalyzePattern

    def validate(%AnalyzePattern{} = msg) do
      with :ok <- validate_agent_id(msg.agent_id),
           :ok <- validate_depth(msg.depth),
           :ok <- validate_pattern_types(msg.pattern_types) do
        {:ok, msg}
      end
    end

    def route(%AnalyzePattern{} = msg, context) do
      if Code.ensure_loaded?(RubberDuck.Skills.LearningSkill) do
        RubberDuck.Skills.LearningSkill.handle_analyze_pattern(msg, context)
      else
        {:error, :handler_not_loaded}
      end
    end

    def to_jido_signal(%AnalyzePattern{} = msg) do
      %{
        type: "learning.pattern.analyze",
        data: %{
          agent_id: msg.agent_id,
          depth: msg.depth,
          time_window: msg.time_window,
          pattern_types: msg.pattern_types
        },
        metadata: msg.metadata
      }
    end

    def priority(%AnalyzePattern{depth: :comprehensive}), do: :low
    def priority(%AnalyzePattern{depth: :deep}), do: :normal
    def priority(_), do: :normal

    def timeout(%AnalyzePattern{depth: :comprehensive}), do: 30_000
    def timeout(%AnalyzePattern{depth: :deep}), do: 20_000
    def timeout(_), do: 10_000

    def encode(msg), do: Jason.encode!(Map.from_struct(msg))

    defp validate_agent_id(id) when is_binary(id) and byte_size(id) > 0, do: :ok
    defp validate_agent_id(_), do: {:error, :invalid_agent_id}

    defp validate_depth(depth) when depth in [:shallow, :normal, :deep, :comprehensive], do: :ok
    defp validate_depth(_), do: {:error, :invalid_depth}

    defp validate_pattern_types(types) when is_list(types) do
      valid_types = [:action_outcome, :sequence, :temporal, :context_correlation]

      if Enum.all?(types, &(&1 in valid_types)) do
        :ok
      else
        {:error, :invalid_pattern_types}
      end
    end

    defp validate_pattern_types(_), do: {:error, :pattern_types_must_be_list}
  end
end
