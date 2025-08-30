defmodule RubberDuck.Skills.Streaming.Actions.ProcessStreamAction do
  @moduledoc """
  Stream processing action for Server-Sent Events (SSE) and token streaming.

  This action handles real-time processing of streaming responses from LLM providers
  including SSE event parsing, chunk aggregation, buffer management, and callback
  coordination for seamless streaming experiences.

  Features:
  - SSE event parsing with proper data extraction and error handling
  - Intelligent chunk aggregation with partial response reconstruction
  - High-performance buffer management using ETS for concurrent access
  - Stream termination detection with proper cleanup and finalization
  - Integration with callback systems for real-time UI updates
  - Performance optimization with memory management and flow control

  Stream Event Types:
  - **data**: Content chunks with token data
  - **error**: Error events with retry information
  - **done**: Stream completion with final metadata
  - **heartbeat**: Keep-alive events for connection health
  """

  use Jido.Action,
    name: "process_stream",
    schema: [
      stream_id: [type: :string, required: true, doc: "Unique stream identifier"],
      event_data: [type: :map, required: true, doc: "SSE event data to process"],
      stream_config: [type: :map, default: %{}, doc: "Stream processing configuration"],
      callback_config: [type: :map, default: %{}, doc: "Callback configuration"],
      context: [type: :map, default: %{}, doc: "Processing context"]
    ]

  require Logger

  # Stream processing configuration
  @default_stream_config %{
    # 1MB buffer limit
    buffer_size_limit: 1_000_000,
    # 30 second timeout
    chunk_timeout_ms: 30_000,
    enable_heartbeat: true,
    # 10 second heartbeat
    heartbeat_interval_ms: 10_000,
    auto_aggregate: true,
    preserve_metadata: true
  }

  # SSE event types and their handlers
  @sse_event_types %{
    data: :handle_data_event,
    error: :handle_error_event,
    done: :handle_completion_event,
    heartbeat: :handle_heartbeat_event,
    metadata: :handle_metadata_event
  }

  @doc """
  Process streaming event with intelligent parsing and aggregation.

  Returns processing result with updated stream state, aggregated content,
  and callback information for real-time updates.
  """
  def run(params, _context) do
    %{
      stream_id: stream_id,
      event_data: event_data,
      stream_config: config,
      callback_config: callback_config,
      context: processing_context
    } = params

    merged_config = Map.merge(@default_stream_config, config)

    Logger.debug("ProcessStreamAction: Processing stream event",
      stream_id: stream_id,
      event_type: Map.get(event_data, :type, :unknown)
    )

    processing_start_time = System.monotonic_time(:microsecond)

    with {:ok, event_type} <- identify_event_type(event_data),
         {:ok, stream_state} <- get_or_create_stream_state(stream_id, merged_config),
         {:ok, processed_result} <-
           process_stream_event(event_type, event_data, stream_state, merged_config),
         {:ok, updated_state} <- update_stream_state(stream_id, processed_result.stream_state),
         {:ok, callback_result} <-
           execute_callbacks(processed_result, callback_config, processing_context) do
      processing_time = System.monotonic_time(:microsecond) - processing_start_time

      Logger.debug("ProcessStreamAction: Stream event processed",
        stream_id: stream_id,
        event_type: event_type,
        processing_time_us: processing_time,
        content_length: String.length(processed_result.aggregated_content || "")
      )

      {:ok,
       %{
         stream_id: stream_id,
         event_type: event_type,
         aggregated_content: processed_result.aggregated_content,
         stream_complete: processed_result.stream_complete,
         stream_metadata: processed_result.metadata,
         callback_results: callback_result,
         processing_metadata: %{
           processing_time_microseconds: processing_time,
           buffer_size: processed_result.buffer_size,
           chunks_processed: processed_result.chunks_processed,
           stream_health: assess_stream_health(processed_result.stream_state)
         }
       }}
    else
      {:error, reason} ->
        Logger.error("ProcessStreamAction: Stream processing failed",
          error: reason,
          stream_id: stream_id,
          event_type: Map.get(event_data, :type, :unknown)
        )

        {:error, reason}
    end
  end

  # Private implementation functions

  defp identify_event_type(event_data) do
    event_type =
      case event_data do
        %{type: type} when type in [:data, :error, :done, :heartbeat, :metadata] ->
          type

        %{event: "data"} ->
          :data

        %{event: "error"} ->
          :error

        %{event: "done"} ->
          :done

        %{event: "heartbeat"} ->
          :heartbeat

        # OpenAI streaming format
        %{data: data} when is_binary(data) ->
          :data

        # Anthropic streaming format
        %{type: "content_block_delta"} ->
          :data

        %{type: "content_block_stop"} ->
          :done

        %{type: "message_stop"} ->
          :done

        # Error detection
        %{error: _} ->
          :error

        _ ->
          :unknown
      end

    if event_type == :unknown do
      {:error, {:unknown_event_type, event_data}}
    else
      {:ok, event_type}
    end
  end

  defp get_or_create_stream_state(stream_id, config) do
    # Get existing stream state from ETS or create new one
    case get_stream_state_from_ets(stream_id) do
      {:ok, existing_state} ->
        {:ok, existing_state}

      {:error, :not_found} ->
        # Create new stream state
        initial_state = %{
          stream_id: stream_id,
          created_at: System.system_time(:second),
          chunks: [],
          aggregated_content: "",
          metadata: %{},
          buffer_size: 0,
          chunks_processed: 0,
          last_heartbeat: System.system_time(:second),
          stream_complete: false,
          errors: [],
          config: config
        }

        case store_stream_state_in_ets(stream_id, initial_state) do
          :ok -> {:ok, initial_state}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp process_stream_event(event_type, event_data, stream_state, config) do
    handler_function = Map.get(@sse_event_types, event_type, :handle_unknown_event)
    apply(__MODULE__, handler_function, [event_data, stream_state, config])
  end

  # SSE Event Handlers

  def handle_data_event(event_data, stream_state, config) do
    # Extract content from data event
    content = extract_content_from_event(event_data)

    if content && String.trim(content) != "" do
      # Add chunk to stream state
      chunk_data = %{
        content: content,
        timestamp: System.system_time(:microsecond),
        sequence: stream_state.chunks_processed + 1
      }

      updated_chunks = [chunk_data | stream_state.chunks]
      updated_content = stream_state.aggregated_content <> content
      updated_buffer_size = stream_state.buffer_size + String.length(content)

      # Check buffer limits
      if updated_buffer_size > config.buffer_size_limit do
        Logger.warning("ProcessStreamAction: Buffer size limit exceeded",
          stream_id: stream_state.stream_id,
          buffer_size: updated_buffer_size,
          limit: config.buffer_size_limit
        )

        # Implement buffer management strategy
        {managed_chunks, managed_content, managed_size} =
          manage_buffer_overflow(updated_chunks, updated_content, config)

        updated_state = %{
          stream_state
          | chunks: managed_chunks,
            aggregated_content: managed_content,
            buffer_size: managed_size,
            chunks_processed: stream_state.chunks_processed + 1
        }

        {:ok,
         %{
           stream_state: updated_state,
           aggregated_content: managed_content,
           stream_complete: false,
           chunks_processed: updated_state.chunks_processed,
           buffer_size: managed_size,
           metadata: %{buffer_managed: true}
         }}
      else
        updated_state = %{
          stream_state
          | chunks: updated_chunks,
            aggregated_content: updated_content,
            buffer_size: updated_buffer_size,
            chunks_processed: stream_state.chunks_processed + 1
        }

        {:ok,
         %{
           stream_state: updated_state,
           aggregated_content: updated_content,
           stream_complete: false,
           chunks_processed: updated_state.chunks_processed,
           buffer_size: updated_buffer_size,
           metadata: %{chunk_added: true}
         }}
      end
    else
      # Empty or whitespace-only content, skip
      {:ok,
       %{
         stream_state: stream_state,
         aggregated_content: stream_state.aggregated_content,
         stream_complete: false,
         chunks_processed: stream_state.chunks_processed,
         buffer_size: stream_state.buffer_size,
         metadata: %{chunk_skipped: :empty_content}
       }}
    end
  end

  def handle_error_event(event_data, stream_state, config) do
    error_info = %{
      error: Map.get(event_data, :error, "Unknown streaming error"),
      timestamp: System.system_time(:second),
      stream_position: stream_state.chunks_processed
    }

    updated_errors = [error_info | stream_state.errors]
    updated_state = %{stream_state | errors: updated_errors}

    Logger.error("ProcessStreamAction: Stream error event",
      stream_id: stream_state.stream_id,
      error: error_info.error,
      chunks_processed: stream_state.chunks_processed
    )

    {:ok,
     %{
       stream_state: updated_state,
       aggregated_content: stream_state.aggregated_content,
       stream_complete: false,
       chunks_processed: stream_state.chunks_processed,
       buffer_size: stream_state.buffer_size,
       metadata: %{error_encountered: error_info}
     }}
  end

  def handle_completion_event(event_data, stream_state, config) do
    # Stream is complete
    completion_metadata = extract_completion_metadata(event_data)

    final_state = %{
      stream_state
      | stream_complete: true,
        metadata: Map.merge(stream_state.metadata, completion_metadata)
    }

    Logger.info("ProcessStreamAction: Stream completed",
      stream_id: stream_state.stream_id,
      total_chunks: stream_state.chunks_processed,
      final_content_length: String.length(stream_state.aggregated_content),
      processing_time: System.system_time(:second) - stream_state.created_at
    )

    {:ok,
     %{
       stream_state: final_state,
       aggregated_content: stream_state.aggregated_content,
       stream_complete: true,
       chunks_processed: stream_state.chunks_processed,
       buffer_size: stream_state.buffer_size,
       metadata: Map.merge(%{stream_completed: true}, completion_metadata)
     }}
  end

  def handle_heartbeat_event(event_data, stream_state, config) do
    # Update heartbeat timestamp
    updated_state = %{stream_state | last_heartbeat: System.system_time(:second)}

    Logger.debug("ProcessStreamAction: Heartbeat received",
      stream_id: stream_state.stream_id
    )

    {:ok,
     %{
       stream_state: updated_state,
       aggregated_content: stream_state.aggregated_content,
       stream_complete: false,
       chunks_processed: stream_state.chunks_processed,
       buffer_size: stream_state.buffer_size,
       metadata: %{heartbeat_received: true}
     }}
  end

  def handle_metadata_event(event_data, stream_state, config) do
    # Process metadata event
    metadata = Map.get(event_data, :metadata, %{})
    updated_metadata = Map.merge(stream_state.metadata, metadata)

    updated_state = %{stream_state | metadata: updated_metadata}

    {:ok,
     %{
       stream_state: updated_state,
       aggregated_content: stream_state.aggregated_content,
       stream_complete: false,
       chunks_processed: stream_state.chunks_processed,
       buffer_size: stream_state.buffer_size,
       metadata: %{metadata_updated: metadata}
     }}
  end

  def handle_unknown_event(event_data, stream_state, config) do
    Logger.warning("ProcessStreamAction: Unknown event type",
      stream_id: stream_state.stream_id,
      event_data: event_data
    )

    {:ok,
     %{
       stream_state: stream_state,
       aggregated_content: stream_state.aggregated_content,
       stream_complete: false,
       chunks_processed: stream_state.chunks_processed,
       buffer_size: stream_state.buffer_size,
       metadata: %{unknown_event: event_data}
     }}
  end

  # Content extraction from different provider formats

  defp extract_content_from_event(event_data) do
    case event_data do
      # OpenAI streaming format
      %{choices: [%{delta: %{content: content}} | _]} -> content
      # Anthropic streaming format
      %{delta: %{text: text}} -> text
      %{content_block: %{text: text}} -> text
      # Generic formats
      %{data: data} when is_binary(data) -> data
      %{content: content} when is_binary(content) -> content
      %{text: text} when is_binary(text) -> text
      # Raw string data
      data when is_binary(data) -> data
      _ -> nil
    end
  end

  defp extract_completion_metadata(event_data) do
    case event_data do
      # OpenAI completion metadata
      %{choices: [%{finish_reason: finish_reason} | _], usage: usage} ->
        %{
          finish_reason: finish_reason,
          token_usage: usage,
          completion_source: :openai
        }

      # Anthropic completion metadata
      %{type: "message_stop", usage: usage} ->
        %{
          finish_reason: "stop",
          token_usage: usage,
          completion_source: :anthropic
        }

      # Generic completion
      %{metadata: metadata} when is_map(metadata) ->
        metadata

      _ ->
        %{completion_source: :unknown}
    end
  end

  # Buffer management and optimization

  defp manage_buffer_overflow(chunks, content, config) do
    # Implement buffer management strategy when size limit exceeded
    buffer_limit = config.buffer_size_limit

    # Strategy 1: Keep recent chunks and truncate old ones
    # Keep last 100 chunks
    recent_chunks = Enum.take(chunks, 100)

    # Recalculate content from recent chunks
    recent_content =
      recent_chunks
      # Reverse to get chronological order
      |> Enum.reverse()
      |> Enum.map(&Map.get(&1, :content, ""))
      |> Enum.join("")

    # If still too large, truncate content
    final_content =
      if String.length(recent_content) > buffer_limit do
        Logger.warning("ProcessStreamAction: Truncating content due to buffer limits")
        String.slice(recent_content, -buffer_limit, buffer_limit)
      else
        recent_content
      end

    final_size = String.length(final_content)

    {recent_chunks, final_content, final_size}
  end

  defp assess_stream_health(stream_state) do
    current_time = System.system_time(:second)
    time_since_heartbeat = current_time - stream_state.last_heartbeat

    cond do
      stream_state.stream_complete -> :completed
      not Enum.empty?(stream_state.errors) -> :error
      # No heartbeat for 1 minute
      time_since_heartbeat > 60 -> :stale
      # No heartbeat for 30 seconds
      time_since_heartbeat > 30 -> :degraded
      true -> :healthy
    end
  end

  # Callback execution

  defp execute_callbacks(processed_result, callback_config, context) do
    callbacks = Map.get(callback_config, :callbacks, [])

    if Enum.empty?(callbacks) do
      {:ok, %{callbacks_executed: 0}}
    else
      # Execute each callback with error handling
      callback_results =
        Enum.map(callbacks, fn callback ->
          execute_single_callback(callback, processed_result, context)
        end)

      successful_callbacks = Enum.count(callback_results, &match?({:ok, _}, &1))

      {:ok,
       %{
         callbacks_executed: length(callbacks),
         successful_callbacks: successful_callbacks,
         callback_results: callback_results
       }}
    end
  end

  defp execute_single_callback(callback, processed_result, context) do
    try do
      case callback do
        {module, function, args} ->
          apply(module, function, [processed_result | args])

        {module, function} ->
          apply(module, function, [processed_result])

        callback_fun when is_function(callback_fun, 1) ->
          callback_fun.(processed_result)

        _ ->
          {:error, {:invalid_callback_format, callback}}
      end
    rescue
      error ->
        Logger.error("ProcessStreamAction: Callback execution failed",
          callback: callback,
          error: error
        )

        {:error, {:callback_execution_failed, error}}
    end
  end

  # Stream state management with ETS

  defp get_stream_state_from_ets(stream_id) do
    table_name = :stream_states

    case :ets.lookup(table_name, stream_id) do
      [{^stream_id, state}] -> {:ok, state}
      [] -> {:error, :not_found}
    end
  rescue
    ArgumentError ->
      # Table doesn't exist, create it
      :ets.new(:stream_states, [:named_table, :public, :set])
      {:error, :not_found}
  end

  defp store_stream_state_in_ets(stream_id, state) do
    table_name = :stream_states

    try do
      :ets.insert(table_name, {stream_id, state})
      :ok
    rescue
      ArgumentError ->
        # Table doesn't exist, create it and retry
        :ets.new(table_name, [:named_table, :public, :set])
        :ets.insert(table_name, {stream_id, state})
        :ok
    end
  end

  defp update_stream_state(stream_id, updated_state) do
    case store_stream_state_in_ets(stream_id, updated_state) do
      :ok -> {:ok, updated_state}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Clean up completed or expired streams from ETS.
  """
  def cleanup_expired_streams(max_age_seconds \\ 3600) do
    table_name = :stream_states
    current_time = System.system_time(:second)
    cutoff_time = current_time - max_age_seconds

    try do
      # Find expired streams
      expired_streams =
        :ets.select(table_name, [
          {{:"$1", :"$2"}, [{:<, {:map_get, :created_at, :"$2"}, cutoff_time}], [:"$1"]}
        ])

      # Delete expired streams
      Enum.each(expired_streams, fn stream_id ->
        :ets.delete(table_name, stream_id)
      end)

      Logger.debug("ProcessStreamAction: Cleaned up expired streams",
        expired_count: length(expired_streams)
      )

      {:ok, length(expired_streams)}
    rescue
      ArgumentError ->
        # Table doesn't exist
        {:ok, 0}
    end
  end

  @doc """
  Get stream statistics for monitoring and optimization.
  """
  def get_stream_statistics do
    table_name = :stream_states

    try do
      all_streams = :ets.tab2list(table_name)
      current_time = System.system_time(:second)

      stats =
        Enum.reduce(
          all_streams,
          %{
            total_streams: 0,
            active_streams: 0,
            completed_streams: 0,
            error_streams: 0,
            total_chunks: 0,
            total_content_length: 0,
            avg_processing_time: 0.0
          },
          fn {_stream_id, state}, acc ->
            processing_time = current_time - state.created_at

            %{
              acc
              | total_streams: acc.total_streams + 1,
                active_streams: acc.active_streams + if(state.stream_complete, do: 0, else: 1),
                completed_streams:
                  acc.completed_streams + if(state.stream_complete, do: 1, else: 0),
                error_streams: acc.error_streams + if(Enum.empty?(state.errors), do: 0, else: 1),
                total_chunks: acc.total_chunks + state.chunks_processed,
                total_content_length:
                  acc.total_content_length + String.length(state.aggregated_content),
                avg_processing_time:
                  (acc.avg_processing_time * (acc.total_streams - 1) + processing_time) /
                    acc.total_streams
            }
          end
        )

      {:ok, stats}
    rescue
      ArgumentError ->
        # Table doesn't exist
        {:ok,
         %{
           total_streams: 0,
           active_streams: 0,
           completed_streams: 0,
           error_streams: 0,
           total_chunks: 0,
           total_content_length: 0,
           avg_processing_time: 0.0
         }}
    end
  end
end
