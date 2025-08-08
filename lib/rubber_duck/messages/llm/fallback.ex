defmodule RubberDuck.Messages.LLM.Fallback do
  @moduledoc """
  Message for LLM fallback operations.

  Replaces the string-based "llm.fallback.trigger" signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:original_provider, :reason]
  defstruct [
    :original_provider,
    :reason,
    :original_request,
    :attempted_providers,
    :max_retries,
    :retry_count,
    metadata: %{}
  ]

  @type fallback_reason :: :timeout | :error | :rate_limit | :quality | :cost

  @type t :: %__MODULE__{
          original_provider: atom(),
          reason: fallback_reason(),
          original_request: map() | nil,
          attempted_providers: [atom()] | nil,
          max_retries: integer() | nil,
          retry_count: integer() | nil,
          metadata: map()
        }

  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.LLM.Fallback

    def validate(%Fallback{} = msg) do
      with :ok <- validate_provider(msg.original_provider),
           :ok <- validate_reason(msg.reason),
           :ok <- validate_retries(msg.max_retries) do
        {:ok, msg}
      end
    end

    def route(%Fallback{} = msg, context) do
      # Route to LLM Orchestrator Agent for fallback handling
      if Code.ensure_loaded?(RubberDuck.Agents.LLMOrchestratorAgent) do
        RubberDuck.Agents.LLMOrchestratorAgent.handle_instruction({:fallback, msg}, context)
      else
        {:error, :handler_not_loaded}
      end
    end

    def to_jido_signal(%Fallback{} = msg) do
      data = Map.from_struct(msg)

      %{
        type: "llm.fallback.trigger",
        data: data |> Map.delete(:metadata),
        metadata: msg.metadata
      }
    end

    def priority(_), do: :critical
    def timeout(_), do: 15_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))

    defp validate_provider(provider) when is_atom(provider), do: :ok
    defp validate_provider(_), do: {:error, :invalid_provider}

    defp validate_reason(reason) when reason in [:timeout, :error, :rate_limit, :quality, :cost],
      do: :ok

    defp validate_reason(_), do: {:error, :invalid_reason}

    defp validate_retries(nil), do: :ok
    defp validate_retries(retries) when is_integer(retries) and retries >= 0, do: :ok
    defp validate_retries(_), do: {:error, :invalid_retries}
  end
end
