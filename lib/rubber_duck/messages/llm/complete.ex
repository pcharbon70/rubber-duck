defmodule RubberDuck.Messages.LLM.Complete do
  @moduledoc """
  Message for LLM completion requests.

  Replaces the string-based "llm.request.complete" signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:prompt]
  defstruct [
    :prompt,
    :model,
    :provider,
    :temperature,
    :max_tokens,
    :system_prompt,
    :stop_sequences,
    :stream,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          prompt: String.t(),
          model: String.t() | nil,
          provider: atom() | nil,
          temperature: float() | nil,
          max_tokens: integer() | nil,
          system_prompt: String.t() | nil,
          stop_sequences: [String.t()] | nil,
          stream: boolean() | nil,
          metadata: map()
        }

  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.LLM.Complete

    def validate(%Complete{} = msg) do
      with :ok <- validate_prompt(msg.prompt),
           :ok <- validate_temperature(msg.temperature),
           :ok <- validate_max_tokens(msg.max_tokens) do
        {:ok, msg}
      end
    end

    def route(%Complete{} = msg, context) do
      # Route to LLM Orchestrator Agent
      if Code.ensure_loaded?(RubberDuck.Agents.LLMOrchestratorAgent) do
        RubberDuck.Agents.LLMOrchestratorAgent.handle_instruction({:complete, msg}, context)
      else
        {:error, :handler_not_loaded}
      end
    end

    def to_jido_signal(%Complete{} = msg) do
      data = Map.from_struct(msg)
      %{
        type: "llm.request.complete",
        data: data |> Map.delete(:metadata),
        metadata: msg.metadata
      }
    end

    def priority(%Complete{stream: true}), do: :high
    def priority(_), do: :normal

    def timeout(%Complete{max_tokens: max}) when is_integer(max) and max > 1000, do: 60_000
    def timeout(_), do: 30_000

    def encode(msg), do: Jason.encode!(Map.from_struct(msg))

    defp validate_prompt(prompt) when is_binary(prompt) and byte_size(prompt) > 0, do: :ok
    defp validate_prompt(_), do: {:error, :invalid_prompt}

    defp validate_temperature(nil), do: :ok
    defp validate_temperature(temp) when is_float(temp) and temp >= 0 and temp <= 2, do: :ok
    defp validate_temperature(_), do: {:error, :invalid_temperature}

    defp validate_max_tokens(nil), do: :ok
    defp validate_max_tokens(max) when is_integer(max) and max > 0, do: :ok
    defp validate_max_tokens(_), do: {:error, :invalid_max_tokens}
  end
end
