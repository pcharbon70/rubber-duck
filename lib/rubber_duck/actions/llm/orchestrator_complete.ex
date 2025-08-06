defmodule RubberDuck.Actions.LLM.OrchestratorComplete do
  @moduledoc """
  Action that handles LLM completion requests through the orchestrator agent.
  This wraps the handle_instruction pattern to work with Jido's action system.
  """

  use Jido.Action,
    name: "orchestrator_complete",
    description: "Handle LLM completion through orchestrator",
    schema: [
      request: [type: :map, required: true]
    ]

  alias RubberDuck.LLM.{HealthMonitor, ProviderRegistry}
  require Logger

  # Signal definitions
  @signal_provider_selected "llm.provider.selected"
  @signal_request_completed "llm.request.completed"
  @signal_request_failed "llm.request.failed"
  @signal_cache_hit "llm.cache.hit"

  @impl true
  def run(params, context) do
    with :ok <- validate_orchestrator_params(params),
         :ok <- validate_context(context) do
      execute_orchestrated_completion(params, context)
    else
      {:error, reason} -> {:error, %{reason: reason, stage: :validation}}
    end
  end

  defp execute_orchestrated_completion(params, context) do
    agent = context[:agent]
    request = params.request
    start_time = System.monotonic_time(:millisecond)

    process_completion_with_cache(agent, request, start_time)
  rescue
    exception ->
      handle_orchestrator_exception(exception, params)
  end

  defp process_completion_with_cache(agent, request, start_time) do
    cache_key = generate_cache_key(request)

    case maybe_get_from_cache(agent, cache_key) do
      {:ok, cached_response} ->
        handle_cache_hit_response(request, cache_key, cached_response)

      :miss ->
        execute_fresh_completion_request(agent, request, start_time)
    end
  end

  defp handle_cache_hit_response(request, cache_key, cached_response) do
    emit_signal(@signal_cache_hit, %{request_id: request[:id], cache_key: cache_key})
    {:ok, cached_response}
  end

  defp execute_fresh_completion_request(agent, request, start_time) do
    with {:ok, provider} <- select_optimal_provider(agent, request),
         _ = emit_provider_selection_signal(provider, request),
         {:ok, response} <- execute_completion(agent, provider, request) do
      finalize_completion_success(provider, request, response, start_time)
    else
      {:error, reason} ->
        handle_completion_failure(agent, request, reason, start_time)
    end
  end

  defp emit_provider_selection_signal(provider, request) do
    emit_signal(@signal_provider_selected, %{
      provider: provider.name,
      request_id: request[:id],
      selection_reason: provider.selection_reason
    })
  end

  defp finalize_completion_success(provider, request, response, start_time) do
    duration = System.monotonic_time(:millisecond) - start_time

    emit_signal(@signal_request_completed, %{
      provider: provider.name,
      request_id: request[:id],
      duration: duration,
      tokens: response.usage.total_tokens
    })

    {:ok, response}
  end

  defp handle_orchestrator_exception(exception, params) do
    Logger.error(
      "Orchestrator completion error: #{inspect(exception)}\n#{Exception.format_stacktrace()}"
    )

    {:error,
     %{
       reason: {:exception, exception},
       message: Exception.message(exception),
       request_id: params.request[:id]
     }}
  end

  # Private functions (simplified versions of the orchestrator logic)

  defp maybe_get_from_cache(agent, cache_key) do
    if agent.state.cache_enabled do
      case Map.get(agent.state.request_cache, cache_key) do
        nil -> :miss
        cached -> {:ok, cached}
      end
    else
      :miss
    end
  end

  defp select_optimal_provider(_agent, _request) do
    # Simplified - in real implementation this would use the full logic
    available_providers = ProviderRegistry.list_available()

    if Enum.empty?(available_providers) do
      {:error, :no_providers_available}
    else
      provider = hd(available_providers)
      {:ok, Map.put(provider, :selection_reason, "Selected as available provider")}
    end
  end

  defp execute_completion(_agent, provider, request) do
    case provider.module.complete(request, provider.config) do
      {:ok, response} ->
        HealthMonitor.record_success(provider.name, response[:duration] || 100)
        {:ok, response}

      {:error, reason} = error ->
        HealthMonitor.record_failure(provider.name, reason)
        error
    end
  end

  defp handle_completion_failure(_agent, request, reason, start_time) do
    emit_signal(@signal_request_failed, %{
      request_id: request[:id],
      reason: reason,
      duration: System.monotonic_time(:millisecond) - start_time
    })

    {:error, reason}
  end

  defp generate_cache_key(request) do
    request
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16()
  end

  defp emit_signal(signal_type, payload) do
    Logger.debug("Legacy signal emission: #{signal_type}, payload: #{inspect(payload)}")
    # Note: Converted from legacy signal system - signals are now handled via MessageRouter
    :ok
  rescue
    exception ->
      Logger.warning("Failed to emit signal #{signal_type}: #{inspect(exception)}")
      :ok
  end

  defp validate_orchestrator_params(params) do
    cond do
      not is_map(params) ->
        {:error, :invalid_params}

      not is_map(params[:request]) ->
        {:error, :invalid_request}

      true ->
        :ok
    end
  end

  defp validate_context(context) do
    cond do
      not is_map(context) ->
        {:error, :invalid_context}

      not is_map(context[:agent]) ->
        {:error, :agent_not_in_context}

      not is_map(context[:agent][:state]) ->
        {:error, :invalid_agent_state}

      true ->
        :ok
    end
  end
end
