defmodule RubberDuck.LLM do
  @moduledoc """
  Client API for interacting with the agentic LLM system.

  This module provides a clean interface that maintains backward compatibility
  while leveraging the new agent-based architecture underneath.
  """

  require Logger

  @doc """
  Generate a text completion using the best available LLM provider.

  ## Options
  - `:timeout` - Maximum time to wait for completion (default: 30_000ms)
  - `:optimization` - Optimization preference (:cost, :quality, :balanced)
  - `:cache` - Whether to use caching (default: true)

  ## Examples

      iex> RubberDuck.LLM.complete(%{
      ...>   model: "gpt-3.5-turbo",
      ...>   messages: [%{role: "user", content: "Hello!"}]
      ...> })
      {:ok, %{choices: [...], usage: %{...}}}
  """
  def complete(request, opts \\ []) do
    with {:ok, agent} <- get_orchestrator_agent() do
      # Send completion request to the orchestrator agent
      timeout = Keyword.get(opts, :timeout, 30_000)
      GenServer.call(agent, {:complete, add_request_id(request)}, timeout)
    end
  end

  @doc """
  Generate a streaming text completion.

  Returns a stream that yields completion chunks as they arrive.

  ## Options
  - `:timeout` - Maximum time for the entire stream (default: 60_000ms)
  - `:chunk_timeout` - Maximum time between chunks (default: 5_000ms)

  ## Examples

      iex> {:ok, stream} = RubberDuck.LLM.stream(%{
      ...>   model: "gpt-3.5-turbo",
      ...>   messages: [%{role: "user", content: "Tell me a story"}]
      ...> })
      iex> Enum.each(stream, &IO.write/1)
  """
  def stream(request, opts \\ []) do
    with {:ok, agent} <- get_orchestrator_agent() do
      GenServer.call(agent, {:stream, add_request_id(request)}, Keyword.get(opts, :timeout, 60_000))
    end
  end

  @doc """
  Generate embeddings for text.

  ## Options
  - `:model` - Specific embedding model to use
  - `:batch_size` - Number of texts to process per batch (default: 100)

  ## Examples

      iex> RubberDuck.LLM.embed(["Hello world", "How are you?"])
      {:ok, %{embeddings: [[0.1, 0.2, ...], [0.3, 0.4, ...]], dimensions: 1536}}
  """
  def embed(texts, opts \\ []) when is_list(texts) do
    with {:ok, agent} <- get_orchestrator_agent() do
      request = %{
        texts: texts,
        model: opts[:model]
      }

      GenServer.call(agent, {:embed, add_request_id(request)}, Keyword.get(opts, :timeout, 30_000))
    end
  end

  @doc """
  Get current health status of all LLM providers.

  Returns a map of provider names to their health metrics.

  ## Examples

      iex> RubberDuck.LLM.health_status()
      %{
        openai: %{status: :healthy, success_rate: 99.5, avg_response_time_ms: 450},
        anthropic: %{status: :degraded, success_rate: 85.0, avg_response_time_ms: 2100}
      }
  """
  def health_status do
    with {:ok, monitoring_agent} <- get_monitoring_agent() do
      case GenServer.call(monitoring_agent, :get_health_summary, 5_000) do
        {:ok, summary} -> format_health_summary(summary)
        error -> error
      end
    end
  end

  @doc """
  Diagnose issues with a specific provider.

  ## Examples

      iex> RubberDuck.LLM.diagnose_provider(:openai)
      %{
        provider: :openai,
        health_score: 0.95,
        recent_issues: [...],
        recommendations: ["Consider increasing timeout for large requests"]
      }
  """
  def diagnose_provider(provider_name) do
    with {:ok, monitoring_agent} <- get_monitoring_agent() do
      GenServer.call(
        monitoring_agent,
        {:diagnose_provider, provider_name},
        10_000
      )
    end
  end

  @doc """
  Predict potential failures in the next time window.

  ## Examples

      iex> RubberDuck.LLM.predict_failures(300)  # Next 5 minutes
      [
        %{provider: :anthropic, failure_probability: 0.75, likely_reasons: [:rate_limit]}
      ]
  """
  def predict_failures(time_window_seconds \\ 300) do
    with {:ok, monitoring_agent} <- get_monitoring_agent() do
      GenServer.call(
        monitoring_agent,
        {:predict_failures, time_window_seconds},
        10_000
      )
    end
  end

  @doc """
  List all available LLM providers and their capabilities.

  ## Examples

      iex> RubberDuck.LLM.list_providers()
      [
        %{name: :openai, available: true, capabilities: %{embeddings: true, streaming: true}},
        %{name: :anthropic, available: true, capabilities: %{embeddings: false, streaming: true}}
      ]
  """
  def list_providers do
    RubberDuck.LLM.ProviderRegistry.list()
  end

  @doc """
  Get metrics for a specific provider.

  ## Examples

      iex> RubberDuck.LLM.get_provider_metrics(:openai)
      %{
        success_rate: 0.995,
        avg_response_time_ms: 450,
        p95_response_time_ms: 1200,
        total_requests: 10000
      }
  """
  def get_provider_metrics(provider_name) do
    GenServer.call(RubberDuck.Sensors.LLMHealthSensor, {:get_provider_metrics, provider_name})
  end

  # Private functions

  defp get_orchestrator_agent do
    case Process.whereis(:"Elixir.RubberDuck.Agents.LLMOrchestratorAgent.llm_orchestrator") do
      nil ->
        Logger.error("LLM Orchestrator Agent not found. Ensure application is started.")
        {:error, :agent_not_found}
      pid ->
        {:ok, pid}
    end
  end

  defp get_monitoring_agent do
    case Process.whereis(:"Elixir.RubberDuck.Agents.LLMMonitoringAgent.llm_monitoring") do
      nil ->
        Logger.error("LLM Monitoring Agent not found. Ensure application is started.")
        {:error, :agent_not_found}
      pid ->
        {:ok, pid}
    end
  end

  defp add_request_id(request) do
    if Map.has_key?(request, :id) do
      request
    else
      Map.put(request, :id, generate_request_id())
    end
  end

  defp generate_request_id do
    "req_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp format_health_summary(summary) do
    # Transform the monitoring agent's summary into a user-friendly format
    providers = summary[:providers_monitored] || []

    providers
    |> Enum.map(fn provider ->
      metrics = GenServer.call(
        RubberDuck.Sensors.LLMHealthSensor,
        {:get_provider_metrics, provider}
      )

      status = determine_provider_status(metrics)

      {provider, %{
        status: status,
        success_rate: Float.round(metrics.success_rate * 100, 1),
        avg_response_time_ms: round(metrics.avg_response_time)
      }}
    end)
    |> Map.new()
  end

  defp determine_provider_status(metrics) do
    cond do
      metrics.success_rate < 0.5 -> :failed
      metrics.success_rate < 0.9 -> :degraded
      metrics.avg_response_time > 5000 -> :degraded
      true -> :healthy
    end
  end
end
