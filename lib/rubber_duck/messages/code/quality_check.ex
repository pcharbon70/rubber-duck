defmodule RubberDuck.Messages.Code.QualityCheck do
  @moduledoc """
  Message for requesting code quality checks.

  Replaces the "code.quality.check" signal pattern with a typed message.
  """

  @enforce_keys [:target]
  defstruct [
    :target,
    metrics: [:complexity, :coverage, :duplication],
    thresholds: %{},
    opts: %{},
    metadata: %{}
  ]

  @type metric :: :complexity | :coverage | :duplication | :maintainability | :reliability

  @type t :: %__MODULE__{
          target: String.t(),
          metrics: [metric()],
          thresholds: map(),
          opts: map(),
          metadata: map()
        }

  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.Code.QualityCheck

    def validate(%QualityCheck{} = msg) do
      with :ok <- validate_target(msg.target),
           :ok <- validate_metrics(msg.metrics) do
        {:ok, msg}
      end
    end

    def route(%QualityCheck{} = msg, context) do
      if Code.ensure_loaded?(RubberDuck.Skills.CodeAnalysisSkill) do
        RubberDuck.Skills.CodeAnalysisSkill.handle_quality_check(msg, context)
      else
        {:error, :handler_not_loaded}
      end
    end

    def to_jido_signal(%QualityCheck{} = msg) do
      data = Map.from_struct(msg)

      %{
        type: "code.quality.check",
        data: data |> Map.delete(:metadata),
        metadata: msg.metadata
      }
    end

    def priority(_), do: :normal
    def timeout(_), do: 10_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))

    defp validate_target(target) when is_binary(target) and byte_size(target) > 0, do: :ok
    defp validate_target(_), do: {:error, :invalid_target}

    defp validate_metrics(metrics) when is_list(metrics) do
      valid_metrics = [:complexity, :coverage, :duplication, :maintainability, :reliability]

      if Enum.all?(metrics, &(&1 in valid_metrics)) do
        :ok
      else
        {:error, :invalid_metrics}
      end
    end

    defp validate_metrics(_), do: {:error, :metrics_must_be_list}
  end
end
