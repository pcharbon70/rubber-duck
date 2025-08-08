defmodule RubberDuck.Messages.LLM.HealthCheck do
  @moduledoc """
  Message for LLM provider health checks.

  Replaces the string-based "llm.health.check" signal pattern
  with a strongly-typed struct.
  """

  @enforce_keys [:provider]
  defstruct [
    :provider,
    :check_type,
    :timeout_ms,
    :include_latency,
    :include_availability,
    metadata: %{}
  ]

  @type check_type :: :ping | :full | :minimal

  @type t :: %__MODULE__{
          provider: atom(),
          check_type: check_type() | nil,
          timeout_ms: integer() | nil,
          include_latency: boolean() | nil,
          include_availability: boolean() | nil,
          metadata: map()
        }

  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.LLM.HealthCheck

    def validate(%HealthCheck{} = msg) do
      with :ok <- validate_provider(msg.provider),
           :ok <- validate_check_type(msg.check_type),
           :ok <- validate_timeout(msg.timeout_ms) do
        {:ok, msg}
      end
    end

    def route(%HealthCheck{} = msg, context) do
      # Route to LLM Monitoring Agent
      if Code.ensure_loaded?(RubberDuck.Agents.LLMMonitoringAgent) do
        RubberDuck.Agents.LLMMonitoringAgent.handle_instruction({:health_check, msg}, context)
      else
        {:error, :handler_not_loaded}
      end
    end

    def to_jido_signal(%HealthCheck{} = msg) do
      data = Map.from_struct(msg)

      %{
        type: "llm.health.check",
        data: data |> Map.delete(:metadata),
        metadata: msg.metadata
      }
    end

    def priority(%HealthCheck{check_type: :ping}), do: :critical
    def priority(_), do: :high

    def timeout(%HealthCheck{timeout_ms: ms}) when is_integer(ms), do: ms
    def timeout(_), do: 10_000

    def encode(msg), do: Jason.encode!(Map.from_struct(msg))

    defp validate_provider(provider) when is_atom(provider), do: :ok
    defp validate_provider(_), do: {:error, :invalid_provider}

    defp validate_check_type(nil), do: :ok
    defp validate_check_type(type) when type in [:ping, :full, :minimal], do: :ok
    defp validate_check_type(_), do: {:error, :invalid_check_type}

    defp validate_timeout(nil), do: :ok
    defp validate_timeout(ms) when is_integer(ms) and ms > 0 and ms <= 60_000, do: :ok
    defp validate_timeout(_), do: {:error, :invalid_timeout}
  end
end
