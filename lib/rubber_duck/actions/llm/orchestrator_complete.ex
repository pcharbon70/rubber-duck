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
  
  alias RubberDuck.LLM.{ProviderRegistry, HealthMonitor}
  alias RubberDuck.Signal
  require Logger
  
  # Signal definitions
  @signal_provider_selected "llm.provider.selected"
  @signal_request_completed "llm.request.completed"
  @signal_request_failed "llm.request.failed"
  @signal_fallback_triggered "llm.fallback.triggered"
  @signal_cache_hit "llm.cache.hit"
  
  @impl true
  def run(params, context) do
    # Validate required parameters
    with :ok <- validate_orchestrator_params(params),
         :ok <- validate_context(context) do
      try do
        agent = context[:agent]
        request = params.request
        start_time = System.monotonic_time(:millisecond)
        
        # Check cache first if enabled
        cache_key = generate_cache_key(request)
        
        case maybe_get_from_cache(agent, cache_key) do
          {:ok, cached_response} ->
            emit_signal(@signal_cache_hit, %{request_id: request[:id], cache_key: cache_key})
            {:ok, cached_response}
          
          :miss ->
            # Select best provider based on learning
            with {:ok, provider} <- select_optimal_provider(agent, request),
                 _ = emit_signal(@signal_provider_selected, %{
                   provider: provider.name,
                   request_id: request[:id],
                   selection_reason: provider.selection_reason
                 }),
                 {:ok, response} <- execute_completion(agent, provider, request) do
              
              duration = System.monotonic_time(:millisecond) - start_time
              
              emit_signal(@signal_request_completed, %{
                provider: provider.name,
                request_id: request[:id],
                duration: duration,
                tokens: response.usage.total_tokens
              })
              
              {:ok, response}
            else
              {:error, reason} ->
                handle_completion_failure(agent, request, reason, start_time)
            end
        end
      rescue
        exception ->
          Logger.error("Orchestrator completion error: #{inspect(exception)}\n#{Exception.format_stacktrace()}")
          {:error, %{
            reason: {:exception, exception},
            message: Exception.message(exception),
            request_id: params.request[:id]
          }}
      end
    else
      {:error, reason} -> {:error, %{reason: reason, stage: :validation}}
    end
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
    :crypto.hash(:sha256, :erlang.term_to_binary(request))
    |> Base.encode16()
  end
  
  defp emit_signal(signal_type, payload) do
    try do
      Signal.emit(signal_type, Map.put(payload, :timestamp, DateTime.utc_now()))
    rescue
      exception ->
        Logger.warning("Failed to emit signal #{signal_type}: #{inspect(exception)}")
        :ok
    end
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