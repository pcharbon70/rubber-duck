defmodule RubberDuck.Messages.LLM.ProviderSelect do
  @moduledoc """
  Message for selecting an LLM provider.

  Replaces the string-based "llm.provider.select" signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:request_type]
  defstruct [
    :request_type,
    :model_requirements,
    :cost_constraint,
    :quality_threshold,
    :preferred_providers,
    :excluded_providers,
    metadata: %{}
  ]

  @type request_type :: :completion | :embedding | :chat | :function_call

  @type t :: %__MODULE__{
          request_type: request_type(),
          model_requirements: map() | nil,
          cost_constraint: float() | nil,
          quality_threshold: float() | nil,
          preferred_providers: [atom()] | nil,
          excluded_providers: [atom()] | nil,
          metadata: map()
        }

  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.LLM.ProviderSelect

    def validate(%ProviderSelect{} = msg) do
      with :ok <- validate_request_type(msg.request_type),
           :ok <- validate_cost_constraint(msg.cost_constraint),
           :ok <- validate_quality_threshold(msg.quality_threshold) do
        {:ok, msg}
      end
    end

    def route(%ProviderSelect{} = msg, context) do
      # Route to LLM Orchestrator Agent
      if Code.ensure_loaded?(RubberDuck.Agents.LLMOrchestratorAgent) do
        RubberDuck.Agents.LLMOrchestratorAgent.handle_instruction(
          {:select_provider, msg},
          context
        )
      else
        {:error, :handler_not_loaded}
      end
    end

    def to_jido_signal(%ProviderSelect{} = msg) do
      %{
        type: "llm.provider.select",
        data: Map.from_struct(msg) |> Map.delete(:metadata),
        metadata: msg.metadata
      }
    end

    def priority(_), do: :high
    def timeout(_), do: 5_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))

    defp validate_request_type(type)
         when type in [:completion, :embedding, :chat, :function_call],
         do: :ok

    defp validate_request_type(_), do: {:error, :invalid_request_type}

    defp validate_cost_constraint(nil), do: :ok
    defp validate_cost_constraint(cost) when is_float(cost) and cost > 0, do: :ok
    defp validate_cost_constraint(_), do: {:error, :invalid_cost_constraint}

    defp validate_quality_threshold(nil), do: :ok

    defp validate_quality_threshold(threshold)
         when is_float(threshold) and threshold >= 0 and threshold <= 1,
         do: :ok

    defp validate_quality_threshold(_), do: {:error, :invalid_quality_threshold}
  end
end
