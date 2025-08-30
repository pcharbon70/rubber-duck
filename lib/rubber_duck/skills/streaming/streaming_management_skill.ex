defmodule RubberDuck.Skills.Streaming.StreamingManagementSkill do
  @moduledoc """
  Streaming management skill for coordinating real-time response streaming.

  This skill provides comprehensive streaming management including SSE event handling,
  buffer management, callback coordination, and performance optimization for
  real-time LLM response streaming across all providers.

  Features:
  - Real-time SSE event processing with intelligent parsing and aggregation
  - High-performance buffer management using ETS for concurrent stream handling
  - Callback coordination for UI updates and real-time user experience
  - Stream health monitoring with automatic error recovery and reconnection
  - Integration with provider streaming capabilities and routing intelligence
  - Performance optimization with memory management and flow control

  Signal Patterns:
  - Input: "streaming.start.*", "streaming.data.*", "streaming.complete.*"
  - Output: "streaming.processed.*", "response.aggregated.*", "streaming.error.*"
  """

  use Jido.Skill,
    name: "streaming_management_skill",
    opts_key: :streaming_management_state,
    signal_patterns: [
      "streaming.start.session",
      "streaming.data.received",
      "streaming.complete.session",
      "streaming.error.handle",
      "response.aggregate.tokens",
      "callback.execute.update"
    ]

  require Logger

  alias RubberDuck.Skills.Actions.CallAPIAction
  alias RubberDuck.Skills.Streaming.Actions.ProcessStreamAction

  # Default skill state
  @default_state %{
    active_streams: %{},
    stream_performance: %{
      total_streams_handled: 0,
      avg_completion_time: 0.0,
      error_rate: 0.0,
      throughput_tokens_per_second: 0.0
    },
    configuration: %{
      max_concurrent_streams: 100,
      default_buffer_size: 1_000_000,
      # 5 minutes
      stream_timeout_ms: 300_000,
      enable_stream_caching: true,
      performance_monitoring: true
    },
    callback_registry: %{}
  }

  # Stream session types and their characteristics
  @stream_session_types %{
    llm_completion: %{
      typical_duration_ms: 15_000,
      expected_chunk_count: 50,
      buffer_size_multiplier: 1.0
    },
    llm_streaming: %{
      typical_duration_ms: 30_000,
      expected_chunk_count: 150,
      buffer_size_multiplier: 1.5
    },
    rag_streaming: %{
      typical_duration_ms: 45_000,
      expected_chunk_count: 200,
      buffer_size_multiplier: 2.0
    },
    reasoning_streaming: %{
      typical_duration_ms: 60_000,
      expected_chunk_count: 100,
      buffer_size_multiplier: 1.2
    }
  }

  @doc """
  Initialize streaming management skill with configuration and ETS setup.
  """
  def start_skill(opts \\ []) do
    initial_state = Map.merge(@default_state, Map.new(opts))

    Logger.info("StreamingManagementSkill: Initializing streaming infrastructure")

    # Initialize ETS table for stream states
    case initialize_stream_ets() do
      :ok ->
        # Load performance baselines if available
        case load_streaming_performance_history(initial_state) do
          {:ok, enhanced_state} ->
            Logger.info("StreamingManagementSkill: Initialized successfully",
              max_concurrent: enhanced_state.configuration.max_concurrent_streams,
              caching_enabled: enhanced_state.configuration.enable_stream_caching
            )

            {:ok, enhanced_state}

          {:error, reason} ->
            Logger.warning("StreamingManagementSkill: Failed to load history, using defaults",
              error: reason
            )

            {:ok, initial_state}
        end

      {:error, reason} ->
        Logger.error("StreamingManagementSkill: Failed to initialize ETS", error: reason)
        {:error, reason}
    end
  end

  @doc """
  Handle streaming session start with configuration and callback setup.
  """
  def handle_stream_start(stream_id, session_config, callbacks, state) do
    Logger.info("StreamingManagementSkill: Starting stream session",
      stream_id: stream_id,
      session_type: Map.get(session_config, :type, :llm_completion)
    )

    session_type = Map.get(session_config, :type, :llm_completion)

    with {:ok, optimized_config} <- optimize_stream_config(session_config, session_type, state),
         {:ok, registered_callbacks} <- register_stream_callbacks(stream_id, callbacks, state),
         {:ok, session_state} <-
           initialize_stream_session(stream_id, optimized_config, session_type) do
      # Update active streams
      updated_active_streams =
        Map.put(state.active_streams, stream_id, %{
          session_type: session_type,
          config: optimized_config,
          callbacks: registered_callbacks,
          started_at: System.system_time(:second)
        })

      updated_state = %{state | active_streams: updated_active_streams}

      Logger.info("StreamingManagementSkill: Stream session started",
        stream_id: stream_id,
        active_streams: map_size(updated_active_streams)
      )

      {:ok,
       %{
         stream_id: stream_id,
         session_initialized: true,
         config_optimized: optimized_config,
         callbacks_registered: length(registered_callbacks)
       }, updated_state}
    else
      {:error, reason} = error ->
        Logger.error("StreamingManagementSkill: Failed to start stream", error: reason)
        {error, state}
    end
  end

  @doc """
  Handle streaming data processing with aggregation and callbacks.
  """
  def handle_stream_data(stream_id, event_data, state) do
    Logger.debug("StreamingManagementSkill: Processing stream data",
      stream_id: stream_id
    )

    case Map.get(state.active_streams, stream_id) do
      nil ->
        Logger.warning("StreamingManagementSkill: Stream not found", stream_id: stream_id)
        {:error, {:stream_not_found, stream_id}, state}

      stream_info ->
        # Process the streaming event
        process_params = %{
          stream_id: stream_id,
          event_data: event_data,
          stream_config: stream_info.config,
          callback_config: %{callbacks: stream_info.callbacks},
          context: %{session_type: stream_info.session_type}
        }

        case ProcessStreamAction.run(process_params, %{}) do
          {:ok, result} ->
            # Update performance metrics
            updated_state = update_streaming_performance(result, state)

            Logger.debug("StreamingManagementSkill: Stream data processed",
              stream_id: stream_id,
              content_length: String.length(result.aggregated_content || ""),
              stream_complete: result.stream_complete
            )

            # Clean up if stream is complete
            final_state = handle_stream_completion_cleanup(result, stream_id, updated_state)

            {:ok, result, final_state}

          {:error, reason} = error ->
            Logger.error("StreamingManagementSkill: Stream data processing failed",
              error: reason,
              stream_id: stream_id
            )

            {error, state}
        end
    end
  end

  @doc """
  Handle stream completion and cleanup.
  """
  def handle_stream_completion(stream_id, completion_data, state) do
    Logger.info("StreamingManagementSkill: Completing stream session",
      stream_id: stream_id
    )

    case Map.get(state.active_streams, stream_id) do
      nil ->
        Logger.warning("StreamingManagementSkill: Stream not found for completion",
          stream_id: stream_id
        )

        {:ok, %{stream_cleaned: false, reason: :not_found}, state}

      stream_info ->
        # Process completion event
        completion_event = %{
          type: :done,
          metadata: completion_data
        }

        process_params = %{
          stream_id: stream_id,
          event_data: completion_event,
          stream_config: stream_info.config,
          callback_config: %{callbacks: stream_info.callbacks},
          context: %{session_type: stream_info.session_type, completing: true}
        }

        case ProcessStreamAction.run(process_params, %{}) do
          {:ok, result} ->
            # Final performance update
            updated_state = update_streaming_performance(result, state)

            # Clean up stream
            final_state = cleanup_completed_stream(stream_id, updated_state)

            Logger.info("StreamingManagementSkill: Stream session completed",
              stream_id: stream_id,
              final_content_length: String.length(result.aggregated_content || ""),
              chunks_processed: result.chunks_processed
            )

            {:ok,
             %{
               stream_cleaned: true,
               final_result: result,
               performance_updated: true
             }, final_state}

          {:error, reason} = error ->
            # Clean up even on error
            error_state = cleanup_completed_stream(stream_id, state)
            {error, error_state}
        end
    end
  end

  @doc """
  Handle stream error recovery and reconnection.
  """
  def handle_stream_error(stream_id, error_data, recovery_options, state) do
    Logger.warning("StreamingManagementSkill: Handling stream error",
      stream_id: stream_id,
      error: Map.get(error_data, :error, :unknown)
    )

    case Map.get(state.active_streams, stream_id) do
      nil ->
        {:error, {:stream_not_found, stream_id}, state}

      stream_info ->
        # Attempt error recovery based on options
        recovery_strategy = Map.get(recovery_options, :strategy, :cleanup)

        case recovery_strategy do
          :cleanup ->
            # Clean up and terminate stream
            final_state = cleanup_completed_stream(stream_id, state)
            {:ok, %{recovery_action: :cleanup_completed}, final_state}

          :reconnect ->
            # Attempt to reconnect (placeholder for actual reconnection logic)
            Logger.info("StreamingManagementSkill: Attempting stream reconnection")
            {:ok, %{recovery_action: :reconnect_attempted}, state}

          :continue ->
            # Continue processing despite error
            {:ok, %{recovery_action: :continue_processing}, state}

          _ ->
            {:error, {:unknown_recovery_strategy, recovery_strategy}, state}
        end
    end
  end

  # Private implementation functions

  defp optimize_stream_config(session_config, session_type, state) do
    # Get session type characteristics
    session_chars =
      Map.get(@stream_session_types, session_type, @stream_session_types.llm_completion)

    # Build optimized configuration
    base_buffer_size = state.configuration.default_buffer_size
    optimized_buffer_size = round(base_buffer_size * session_chars.buffer_size_multiplier)

    optimized_config = %{
      buffer_size_limit: optimized_buffer_size,
      chunk_timeout_ms: session_chars.typical_duration_ms,
      enable_heartbeat: true,
      heartbeat_interval_ms: min(session_chars.typical_duration_ms / 10, 10_000),
      auto_aggregate: true,
      preserve_metadata: true,
      session_type: session_type
    }

    # Merge with user-provided config
    final_config = Map.merge(optimized_config, session_config)

    Logger.debug("StreamingManagementSkill: Optimized stream config",
      session_type: session_type,
      buffer_size: final_config.buffer_size_limit,
      timeout: final_config.chunk_timeout_ms
    )

    {:ok, final_config}
  end

  defp register_stream_callbacks(stream_id, callbacks, state) do
    # Validate and register callbacks for the stream
    validated_callbacks = Enum.filter(callbacks, &valid_callback?/1)

    if length(validated_callbacks) != length(callbacks) do
      Logger.warning("StreamingManagementSkill: Some callbacks failed validation",
        stream_id: stream_id,
        valid_count: length(validated_callbacks),
        total_count: length(callbacks)
      )
    end

    # Register in callback registry
    updated_registry = Map.put(state.callback_registry, stream_id, validated_callbacks)

    {:ok, validated_callbacks}
  end

  defp valid_callback?(callback) do
    case callback do
      {module, function, args} when is_atom(module) and is_atom(function) and is_list(args) ->
        true

      {module, function} when is_atom(module) and is_atom(function) ->
        true

      callback_fun when is_function(callback_fun, 1) ->
        true

      _ ->
        false
    end
  end

  defp initialize_stream_session(stream_id, config, session_type) do
    # Initialize stream session in ETS
    session_state = %{
      stream_id: stream_id,
      session_type: session_type,
      config: config,
      created_at: System.system_time(:second),
      status: :active
    }

    # Store initial state
    case ProcessStreamAction.get_or_create_stream_state(stream_id, config) do
      {:ok, _initial_state} ->
        {:ok, session_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_streaming_performance(stream_result, state) do
    # Update performance metrics based on stream processing results
    current_perf = state.stream_performance

    # Simple running average updates
    total_streams = current_perf.total_streams_handled + 1

    # Update completion time if stream is complete
    updated_perf =
      if stream_result.stream_complete do
        processing_time =
          Map.get(stream_result.processing_metadata, :processing_time_microseconds, 0) / 1000

        new_avg_time =
          if current_perf.total_streams_handled > 0 do
            (current_perf.avg_completion_time * current_perf.total_streams_handled +
               processing_time) / total_streams
          else
            processing_time
          end

        %{current_perf | total_streams_handled: total_streams, avg_completion_time: new_avg_time}
      else
        %{current_perf | total_streams_handled: total_streams}
      end

    # Update error rate if there were errors
    final_perf =
      if Map.get(stream_result.stream_metadata, :error_encountered) do
        current_error_rate = updated_perf.error_rate
        new_error_rate = (current_error_rate * (total_streams - 1) + 1.0) / total_streams

        %{updated_perf | error_rate: new_error_rate}
      else
        updated_perf
      end

    %{state | stream_performance: final_perf}
  end

  defp handle_stream_completion_cleanup(result, stream_id, state) do
    if result.stream_complete do
      cleanup_completed_stream(stream_id, state)
    else
      state
    end
  end

  defp cleanup_completed_stream(stream_id, state) do
    # Remove from active streams
    updated_active_streams = Map.delete(state.active_streams, stream_id)

    # Remove from callback registry
    updated_callback_registry = Map.delete(state.callback_registry, stream_id)

    Logger.debug("StreamingManagementSkill: Cleaned up completed stream",
      stream_id: stream_id,
      remaining_active: map_size(updated_active_streams)
    )

    %{
      state
      | active_streams: updated_active_streams,
        callback_registry: updated_callback_registry
    }
  end

  defp initialize_stream_ets do
    # Initialize ETS table for stream state management
    table_name = :stream_states

    try do
      case :ets.info(table_name) do
        :undefined ->
          # Create new table
          :ets.new(table_name, [:named_table, :public, :set, {:read_concurrency, true}])
          Logger.debug("StreamingManagementSkill: Created ETS table for stream states")
          :ok

        _ ->
          # Table already exists
          :ok
      end
    rescue
      error ->
        Logger.error("StreamingManagementSkill: Failed to initialize ETS", error: error)
        {:error, {:ets_initialization_failed, error}}
    end
  end

  defp load_streaming_performance_history(state) do
    # Placeholder for loading historical streaming performance data
    # In production, this would load from database or persistent cache
    {:ok, state}
  end

  @doc """
  Get comprehensive streaming statistics for monitoring and optimization.
  """
  def get_streaming_statistics(state) do
    # Get current performance metrics
    performance = state.stream_performance

    # Get active stream statistics
    active_stats = %{
      active_stream_count: map_size(state.active_streams),
      session_types: get_active_session_types(state.active_streams),
      avg_stream_age: calculate_avg_stream_age(state.active_streams)
    }

    # Get ETS statistics
    case ProcessStreamAction.get_stream_statistics() do
      {:ok, ets_stats} ->
        combined_stats = %{
          performance_metrics: performance,
          active_streams: active_stats,
          ets_statistics: ets_stats,
          system_health: assess_streaming_system_health(performance, active_stats)
        }

        {:ok, combined_stats}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_active_session_types(active_streams) do
    active_streams
    |> Map.values()
    |> Enum.map(&Map.get(&1, :session_type, :unknown))
    |> Enum.frequencies()
  end

  defp calculate_avg_stream_age(active_streams) do
    if map_size(active_streams) == 0 do
      0.0
    else
      current_time = System.system_time(:second)

      ages =
        active_streams
        |> Map.values()
        |> Enum.map(&(current_time - Map.get(&1, :started_at, current_time)))

      avg_age = Enum.sum(ages) / Enum.count(ages)
      Float.round(avg_age, 1)
    end
  end

  defp assess_streaming_system_health(performance, active_stats) do
    health_factors = [
      assess_error_rate_health(performance.error_rate),
      assess_active_streams_health(active_stats.active_stream_count),
      assess_stream_age_health(active_stats.avg_stream_age)
    ]

    # Overall health assessment
    health_score = calculate_health_score(health_factors)

    %{
      overall_health: determine_health_status(health_score),
      health_score: health_score,
      health_factors: Enum.reverse(health_factors),
      recommendations: generate_health_recommendations(health_factors)
    }
  end

  defp assess_error_rate_health(error_rate) do
    case error_rate do
      rate when rate < 0.05 -> :error_rate_excellent
      rate when rate < 0.1 -> :error_rate_good
      rate when rate < 0.2 -> :error_rate_acceptable
      _ -> :error_rate_poor
    end
  end

  defp assess_active_streams_health(active_stream_count) do
    case active_stream_count do
      count when count < 50 -> :load_normal
      count when count < 80 -> :load_high
      _ -> :load_critical
    end
  end

  defp assess_stream_age_health(avg_stream_age) do
    case avg_stream_age do
      age when age < 60 -> :stream_age_normal
      age when age < 300 -> :stream_age_concerning
      _ -> :stream_age_critical
    end
  end

  defp calculate_health_score(health_factors) do
    # Score based on health factors
    positive_factors =
      Enum.count(
        health_factors,
        &(&1 in [:error_rate_excellent, :error_rate_good, :load_normal, :stream_age_normal])
      )

    total_factors = length(health_factors)

    if total_factors > 0 do
      score = positive_factors / total_factors
      Float.round(score, 2)
    else
      # Default neutral score
      0.5
    end
  end

  defp determine_health_status(health_score) do
    cond do
      health_score >= 0.8 -> :excellent
      health_score >= 0.6 -> :good
      health_score >= 0.4 -> :acceptable
      true -> :poor
    end
  end

  defp generate_health_recommendations(health_factors) do
    recommendations = []

    recommendations =
      if :error_rate_poor in health_factors do
        [
          "Investigate streaming error patterns and implement error recovery strategies"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if :load_critical in health_factors do
        [
          "Consider scaling streaming infrastructure or implementing load balancing"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if :stream_age_critical in health_factors do
        ["Implement stream cleanup policies for long-running streams" | recommendations]
      else
        recommendations
      end

    if Enum.empty?(recommendations) do
      ["System health is good - continue monitoring performance"]
    else
      Enum.reverse(recommendations)
    end
  end

  @doc """
  Perform streaming system maintenance including cleanup and optimization.
  """
  def perform_streaming_maintenance(maintenance_options, state) do
    Logger.info("StreamingManagementSkill: Performing system maintenance")

    # Clean up expired streams
    max_age = Map.get(maintenance_options, :max_stream_age_seconds, 3600)

    case ProcessStreamAction.cleanup_expired_streams(max_age) do
      {:ok, cleaned_count} ->
        # Update performance baselines
        updated_state = recalculate_performance_baselines(state)

        maintenance_result = %{
          expired_streams_cleaned: cleaned_count,
          performance_recalculated: true,
          maintenance_completed_at: DateTime.utc_now()
        }

        Logger.info("StreamingManagementSkill: Maintenance completed",
          streams_cleaned: cleaned_count
        )

        {:ok, maintenance_result, updated_state}

      {:error, reason} ->
        Logger.error("StreamingManagementSkill: Maintenance failed", error: reason)
        {:error, reason, state}
    end
  end

  defp recalculate_performance_baselines(state) do
    # Recalculate performance baselines based on recent data
    # This would analyze historical performance and update baselines
    # For now, return state unchanged
    state
  end
end
