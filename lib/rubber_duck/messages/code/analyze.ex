defmodule RubberDuck.Messages.Code.Analyze do
  @moduledoc """
  Message for requesting code analysis.

  This message replaces the string-based "code.analyze.file" signal pattern
  with a strongly-typed struct that provides compile-time validation.

  ## Fields

  - `:file_path` (required) - Path to the file to analyze
  - `:analysis_type` (required) - Type of analysis (:comprehensive | :security | :performance | :quality)
  - `:depth` - Analysis depth (:shallow | :moderate | :deep), defaults to :moderate
  - `:auto_fix` - Whether to automatically fix issues, defaults to false
  - `:context` - Additional context for the analysis
  - `:opts` - Additional options
  - `:metadata` - Message metadata

  ## Example

      message = %Analyze{
        file_path: "/lib/my_module.ex",
        analysis_type: :security,
        depth: :deep
      }
      
      {:ok, result} = MessageRouter.route(message)
  """

  @enforce_keys [:file_path, :analysis_type]
  defstruct [
    :file_path,
    :analysis_type,
    depth: :moderate,
    auto_fix: false,
    context: %{},
    opts: %{},
    metadata: %{}
  ]

  @type analysis_type :: :comprehensive | :security | :performance | :quality
  @type depth :: :shallow | :moderate | :deep

  @type t :: %__MODULE__{
          file_path: String.t(),
          analysis_type: analysis_type(),
          depth: depth(),
          auto_fix: boolean(),
          context: map(),
          opts: map(),
          metadata: map()
        }

  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.Code.Analyze

    def validate(%Analyze{} = msg) do
      with :ok <- validate_file_path(msg.file_path),
           :ok <- validate_analysis_type(msg.analysis_type),
           :ok <- validate_depth(msg.depth) do
        {:ok, msg}
      end
    end

    def route(%Analyze{} = msg, context) do
      # Route to CodeAnalysis skill
      if Code.ensure_loaded?(RubberDuck.Skills.CodeAnalysisSkill) do
        RubberDuck.Skills.CodeAnalysisSkill.handle_analyze(msg, context)
      else
        {:error, :handler_not_loaded}
      end
    end

    def to_jido_signal(%Analyze{} = msg) do
      %{
        type: "code.analyze.file",
        data: %{
          file_path: msg.file_path,
          analysis_type: msg.analysis_type,
          depth: msg.depth,
          auto_fix: msg.auto_fix,
          context: msg.context,
          opts: msg.opts
        },
        metadata: msg.metadata
      }
    end

    def priority(%Analyze{analysis_type: :security}), do: :high
    def priority(%Analyze{analysis_type: :performance}), do: :normal
    def priority(%Analyze{analysis_type: :quality}), do: :low
    def priority(%Analyze{analysis_type: :comprehensive}), do: :normal

    def timeout(%Analyze{depth: :deep}), do: 30_000
    def timeout(%Analyze{depth: :moderate}), do: 10_000
    def timeout(%Analyze{depth: :shallow}), do: 5_000

    def encode(%Analyze{} = msg) do
      Jason.encode!(Map.from_struct(msg))
    end

    # Private validation helpers
    defp validate_file_path(path) when is_binary(path) do
      if String.length(path) > 0 do
        :ok
      else
        {:error, :empty_file_path}
      end
    end

    defp validate_file_path(_), do: {:error, :invalid_file_path}

    defp validate_analysis_type(type)
         when type in [:comprehensive, :security, :performance, :quality] do
      :ok
    end

    defp validate_analysis_type(type), do: {:error, {:invalid_analysis_type, type}}

    defp validate_depth(depth) when depth in [:shallow, :moderate, :deep], do: :ok
    defp validate_depth(depth), do: {:error, {:invalid_depth, depth}}
  end
end
