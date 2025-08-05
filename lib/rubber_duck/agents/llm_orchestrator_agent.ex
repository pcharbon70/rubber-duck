defmodule RubberDuck.Agents.LLMOrchestratorAgent do
  @moduledoc """
  Autonomous agent that orchestrates LLM operations.

  Replaces the traditional LLM Service with an intelligent agent that:
  - Autonomously selects the best provider for each request
  - Learns from past interactions to improve provider selection
  - Handles failures gracefully with intelligent fallback
  - Optimizes requests for cost and quality
  """

  use RubberDuck.Agents.Base,
    name: "llm_orchestrator",
    description: "Orchestrates LLM operations with autonomous provider selection",
    schema: [
      provider_performance: [type: :map, default: %{}],
      cost_budget: [type: :float, default: nil],
      quality_threshold: [type: :float, default: 0.8],
      optimization_preference: [type: :atom, values: [:cost, :quality, :balanced], default: :balanced],
      fallback_enabled: [type: :boolean, default: true],
      cache_enabled: [type: :boolean, default: true],
      request_cache: [type: :map, default: %{}]
    ],
    actions: [
      RubberDuck.Actions.LLM.Complete,
      RubberDuck.Actions.LLM.Stream,
      RubberDuck.Actions.LLM.Embed,
      RubberDuck.Actions.LLM.SelectProvider,
      RubberDuck.Actions.LLM.OptimizeRequest,
      RubberDuck.Actions.LLM.CacheResponse
    ]

  alias RubberDuck.LLM.{ProviderRegistry, HealthMonitor}
  require Logger

  # Signal definitions
  @signal_provider_selected "llm.provider.selected"
  @signal_request_completed "llm.request.completed"
  @signal_request_failed "llm.request.failed"
  @signal_fallback_triggered "llm.fallback.triggered"
  @signal_cache_hit "llm.cache.hit"

  def init(opts) do
    try do
      # Subscribe to relevant signals
      :ok = RubberDuck.Signal.subscribe(@signal_request_completed)
      :ok = RubberDuck.Signal.subscribe(@signal_request_failed)

      {:ok, opts}
    rescue
      exception ->
        Logger.error("Failed to initialize LLM Orchestrator: #{inspect(exception)}")
        {:error, exception}
    end
  end

  def handle_instruction({:complete, request}, agent) do
    try do
      validate_completion_request!(request)
      process_completion_request(agent, request)
    rescue
      exception ->
        handle_completion_exception(exception, agent)
    catch
      {:error, reason} ->
        {{:error, reason}, agent}
    end
  end

  defp validate_completion_request!(request) do
    unless is_map(request) do
      throw({:error, :invalid_request})
    end
  end

  defp process_completion_request(agent, request) do
    start_time = System.monotonic_time(:millisecond)
    cache_key = generate_cache_key(request)

    case maybe_get_from_cache(agent, cache_key) do
      {:ok, cached_response} ->
        handle_cache_hit(request, cache_key, cached_response, agent)
      :miss ->
        execute_fresh_completion(agent, request, start_time, cache_key)
    end
  end

  defp handle_cache_hit(request, cache_key, cached_response, agent) do
    emit_signal(@signal_cache_hit, %{request_id: request[:id], cache_key: cache_key})
    {:ok, cached_response, agent}
  end

  defp execute_fresh_completion(agent, request, start_time, cache_key) do
    with {:ok, provider} <- select_optimal_provider(agent, request),
         _ = emit_provider_selected_signal(provider, request),
         {:ok, response} <- execute_completion(agent, provider, request) do
      
      finalize_successful_completion(agent, provider, request, response, start_time, cache_key)
    else
      {:error, reason} ->
        handle_completion_failure(agent, request, reason, start_time)
    end
  end

  defp emit_provider_selected_signal(provider, request) do
    emit_signal(@signal_provider_selected, %{
      provider: provider.name,
      request_id: request[:id],
      selection_reason: provider.selection_reason
    })
  end

  defp finalize_successful_completion(agent, provider, request, response, start_time, cache_key) do
    duration = System.monotonic_time(:millisecond) - start_time
    
    updated_agent = update_provider_performance(agent, provider.name, %{
      success: true,
      duration: duration,
      tokens_used: response.usage.total_tokens,
      quality_score: estimate_quality(response)
    })
    
    final_agent = maybe_cache_response(updated_agent, cache_key, response)
    
    emit_completion_success_signal(provider, request, duration, response)
    {:ok, response, final_agent}
  end

  defp emit_completion_success_signal(provider, request, duration, response) do
    emit_signal(@signal_request_completed, %{
      provider: provider.name,
      request_id: request[:id],
      duration: duration,
      tokens: response.usage.total_tokens
    })
  end

  defp handle_completion_exception(exception, agent) do
    Logger.error("Orchestrator complete failed: #{inspect(exception)}\n#{Exception.format_stacktrace()}")
    {{:error, {:exception, exception}}, agent}
  end

  def handle_instruction({:stream, request}, agent) do
    try do
      validate_streaming_request!(request)
      process_streaming_request(agent, request)
    rescue
      exception ->
        handle_streaming_exception(exception, agent)
    catch
      {:error, reason} ->
        {{:error, reason}, agent}
    end
  end

  defp validate_streaming_request!(request) do
    unless is_map(request) do
      throw({:error, :invalid_request})
    end
  end

  defp process_streaming_request(agent, request) do
    with {:ok, provider} <- select_optimal_provider(agent, request),
         {:ok, stream} <- execute_streaming(agent, provider, request) do
      
      tracked_stream = create_tracked_stream(stream)
      {:ok, tracked_stream, agent}
    else
      {:error, reason} = error ->
        handle_streaming_error(agent, request, reason, error)
    end
  end

  defp create_tracked_stream(stream) do
    Stream.transform(stream, 0, &track_stream_chunk/2)
  end

  defp track_stream_chunk(chunk, token_count) do
    try do
      new_count = token_count + estimate_tokens(chunk)
      {[chunk], new_count}
    rescue
      _ -> {[chunk], token_count}  # Continue on error
    end
  end

  defp handle_streaming_error(agent, request, reason, error) do
    if agent.state.fallback_enabled do
      attempt_streaming_fallback(agent, request, reason)
    else
      {error, agent}
    end
  end

  defp handle_streaming_exception(exception, agent) do
    Logger.error("Orchestrator stream failed: #{inspect(exception)}\n#{Exception.format_stacktrace()}")
    {{:error, {:exception, exception}}, agent}
  end

  def handle_info(:checkpoint, agent) do
    # Delegate to base module's checkpoint handler
    on_checkpoint(agent)
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, agent) do
    # Handle monitored process downs if needed
    {:ok, agent}
  end

  def handle_info(msg, agent) do
    Logger.debug("Unhandled message in orchestrator agent: #{inspect(msg)}")
    {:ok, agent}
  end

  def handle_signal(@signal_request_completed, payload, agent) do
    # Learn from completed requests
    if payload.provider do
      updated_performance =
        Map.update(
          agent.state.provider_performance,
          payload.provider,
          %{success_count: 1, total_duration: payload.duration},
          fn stats ->
            %{stats |
              success_count: stats.success_count + 1,
              total_duration: stats.total_duration + payload.duration
            }
          end
        )

      {:ok, %{agent | state: Map.put(agent.state, :provider_performance, updated_performance)}}
    else
      {:ok, agent}
    end
  end

  def handle_signal(@signal_request_failed, payload, agent) do
    # Learn from failures
    if payload.provider do
      updated_performance =
        Map.update(
          agent.state.provider_performance,
          payload.provider,
          %{failure_count: 1},
          fn stats ->
            Map.update(stats, :failure_count, 1, &(&1 + 1))
          end
        )

      {:ok, %{agent | state: Map.put(agent.state, :provider_performance, updated_performance)}}
    else
      {:ok, agent}
    end
  end

  # Private functions

  defp select_optimal_provider(agent, request) do
    available_providers = ProviderRegistry.list_available()

    if Enum.empty?(available_providers) do
      {:error, :no_providers_available}
    else
      # Apply learned insights to provider selection
      insights = apply_learned_insights(agent, %{
        request_type: :complete,
        providers: available_providers,
        request: request
      })

      # Score each provider based on agent's learning
      scored_providers =
        available_providers
        |> Enum.map(fn provider ->
          base_score = calculate_provider_score(agent, provider, request)
          # Adjust score based on learned insights
          adjusted_score = apply_insight_adjustments(base_score, provider, insights)
          Map.put(provider, :score, adjusted_score)
        end)
        |> Enum.sort_by(& &1.score, :desc)

      best_provider = hd(scored_providers)

      # Add learning recommendations to selection reason
      base_selection_reason = determine_selection_reason(agent, best_provider)
      final_selection_reason = build_final_selection_reason(base_selection_reason, insights)

      {:ok, Map.put(best_provider, :selection_reason, final_selection_reason)}
    end
  end

  defp calculate_provider_score(agent, provider, request) do
    performance = Map.get(agent.state.provider_performance, provider.name, %{})

    # Base score
    base_score = 100.0

    # Success rate factor
    success_rate = calculate_provider_success_rate(performance)
    success_factor = success_rate * 50

    # Speed factor (if we care about speed)
    avg_duration = calculate_provider_average_duration(performance)
    speed_factor = if avg_duration > 0, do: 1000 / avg_duration, else: 10

    # Cost factor (if we care about cost)
    cost_factor = estimate_cost_factor(provider, request)

    # Apply optimization preference
    case agent.state.optimization_preference do
      :cost ->
        base_score + success_factor + cost_factor * 2
      :quality ->
        base_score + success_factor * 2 + speed_factor
      :balanced ->
        base_score + success_factor + speed_factor * 0.5 + cost_factor * 0.5
    end
  end

  defp calculate_provider_success_rate(performance) do
    s = Map.get(performance, :success_count, 0)
    f = Map.get(performance, :failure_count, 0)
    if s + f > 0 do
      s / (s + f)
    else
      0.95  # Optimistic default
    end
  end

  defp calculate_provider_average_duration(performance) do
    total = Map.get(performance, :total_duration, 0)
    count = Map.get(performance, :success_count, 0)
    if count > 0 do
      total / count
    else
      1000  # 1 second default
    end
  end

  defp estimate_cost_factor(provider, _request) do
    # Simplified cost estimation
    case provider.name do
      :openai -> 20.0  # More expensive
      :anthropic -> 25.0  # Most expensive
      :local -> 100.0  # Free
      _ -> 50.0
    end
  end

  defp determine_selection_reason(agent, _provider) do
    case agent.state.optimization_preference do
      :cost -> "Selected for lowest cost"
      :quality -> "Selected for highest quality"
      :balanced -> "Selected for best balance of cost and quality"
    end
  end

  defp build_final_selection_reason(base_reason, insights) do
    case {insights.confidence > 0.7, has_valid_recommendations?(insights.recommendations)} do
      {true, true} ->
        first_recommendation = get_first_recommendation(insights.recommendations)
        base_reason <> " (Learning: " <> first_recommendation <> ")"
      _ ->
        base_reason
    end
  end

  defp has_valid_recommendations?(recommendations) when is_list(recommendations) do
    length(recommendations) > 0
  end
  defp has_valid_recommendations?(_), do: false

  defp get_first_recommendation(recommendations) do
    case List.first(recommendations) do
      nil -> "no recommendations available"
      recommendation -> recommendation
    end
  end

  defp execute_completion(_agent, provider, request) do
    # Use the existing provider infrastructure
    case provider.module.complete(request, provider.config) do
      {:ok, response} ->
        HealthMonitor.record_success(provider.name, response[:duration] || 100)
        {:ok, response}

      {:error, reason} = error ->
        HealthMonitor.record_failure(provider.name, reason)
        error
    end
  end

  defp execute_streaming(_agent, provider, request) do
    case provider.module.stream(request, provider.config) do
      {:ok, stream} -> {:ok, stream}
      error -> error
    end
  end

  defp handle_completion_failure(agent, request, reason, start_time) do
    emit_signal(@signal_request_failed, %{
      request_id: request[:id],
      reason: reason,
      duration: System.monotonic_time(:millisecond) - start_time
    })

    if agent.state.fallback_enabled do
      attempt_fallback(agent, request, reason)
    else
      {{:error, reason}, agent}
    end
  end

  defp attempt_fallback(agent, request, original_error) do
    # Try next best provider
    case select_optimal_provider(agent, Map.put(request, :exclude_providers, [request[:attempted_provider]])) do
      {:ok, fallback_provider} ->
        emit_signal(@signal_fallback_triggered, %{
          request_id: request[:id],
          from_provider: request[:attempted_provider],
          to_provider: fallback_provider.name
        })

        updated_request = Map.put(request, :attempted_provider, fallback_provider.name)
        handle_instruction({:complete, updated_request}, agent)

      {:error, _} ->
        {{:error, {:fallback_failed, original_error}}, agent}
    end
  end

  defp attempt_streaming_fallback(agent, _request, original_error) do
    # Similar to attempt_fallback but for streaming
    {{:error, {:streaming_fallback_failed, original_error}}, agent}
  end

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

  defp maybe_cache_response(agent, cache_key, response) do
    if agent.state.cache_enabled do
      # Simple cache with size limit
      updated_cache =
        agent.state.request_cache
        |> Map.put(cache_key, response)
        |> limit_cache_size(100)  # Keep only 100 most recent

      %{agent | state: Map.put(agent.state, :request_cache, updated_cache)}
    else
      agent
    end
  end

  defp generate_cache_key(request) do
    try do
      # Generate a cache key from request parameters
      request
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16()
    rescue
      _ ->
        # Fallback to simple key on error
        "req_#{:erlang.phash2(request)}"
    end
  end

  defp limit_cache_size(cache, max_size) when map_size(cache) <= max_size, do: cache
  defp limit_cache_size(cache, max_size) do
    # Remove oldest entries (simplified - in production use LRU)
    cache
    |> Enum.take(max_size)
    |> Map.new()
  end

  defp estimate_quality(response) do
    # Simplified quality estimation based on response
    cond do
      response[:choices] == [] -> 0.0
      response[:finish_reason] == "length" -> 0.7
      true -> 0.9
    end
  end

  defp estimate_tokens(chunk) do
    # Simplified token estimation
    String.length(chunk) / 4
  end

  defp emit_signal(signal_type, payload) do
    try do
      RubberDuck.Signal.emit(signal_type, Map.put(payload, :timestamp, DateTime.utc_now()))
    rescue
      exception ->
        Logger.warning("Failed to emit signal #{signal_type}: #{inspect(exception)}")
        :ok
    end
  end

  defp update_provider_performance(agent, provider_name, metrics) do
    updated_performance =
      Map.update(
        agent.state.provider_performance,
        provider_name,
        %{
          success_count: 1,
          total_duration: metrics.duration,
          total_tokens: metrics.tokens_used,
          quality_sum: metrics.quality_score
        },
        fn stats ->
          %{stats |
            success_count: stats.success_count + 1,
            total_duration: stats.total_duration + metrics.duration,
            total_tokens: Map.get(stats, :total_tokens, 0) + metrics.tokens_used,
            quality_sum: Map.get(stats, :quality_sum, 0) + metrics.quality_score
          }
        end
      )

    %{agent | state: Map.put(agent.state, :provider_performance, updated_performance)}
  end

  defp apply_insight_adjustments(base_score, provider, insights) do
    # Apply learning-based adjustments to provider scores
    case {insights.applicable, insights.confidence > 0.5} do
      {true, true} ->
        adjustment = calculate_provider_adjustment(provider, insights.recommendations, insights.confidence)
        base_score + adjustment
      _ ->
        base_score
    end
  end

  defp calculate_provider_adjustment(provider, recommendations, confidence) do
    adjustments = Enum.map(recommendations, fn rec ->
      calculate_recommendation_score(rec, provider)
    end)

    Enum.sum(adjustments) * confidence
  end

  defp calculate_recommendation_score(rec, provider) do
    cond do
      provider_specific_recommendation?(rec, provider) ->
        calculate_provider_specific_score(rec, provider)
      general_recommendation?(rec, provider) ->
        calculate_general_recommendation_score(rec, provider)
      true ->
        0.0
    end
  end

  defp provider_specific_recommendation?(rec, provider) do
    String.contains?(rec, "#{provider.name}")
  end

  defp general_recommendation?(rec, provider) do
    cost_recommendation?(rec, provider) or quality_recommendation?(rec, provider)
  end

  defp calculate_provider_specific_score(rec, _provider) do
    cond do
      String.contains?(rec, "avoid") -> -20.0
      String.contains?(rec, "prioritize") -> 20.0
      true -> 0.0
    end
  end

  defp calculate_general_recommendation_score(rec, provider) do
    cond do
      cost_recommendation?(rec, provider) -> 10.0
      quality_recommendation?(rec, provider) -> 10.0
      true -> 0.0
    end
  end

  defp cost_recommendation?(rec, provider) do
    String.contains?(rec, "cost") && provider.name == :local
  end

  defp quality_recommendation?(rec, provider) do
    String.contains?(rec, "quality") && provider.name in [:openai, :anthropic]
  end
end
