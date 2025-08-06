defmodule RubberDuck.Actions.LLM.Stream do
  @moduledoc """
  Action for streaming text generation using an LLM provider.

  Returns a stream that yields completion chunks as they're generated.
  """

  use Jido.Action,
    name: "llm_stream",
    description: "Generate streaming text completion using specified LLM provider",
    schema: [
      provider: [type: :map, required: true],
      request: [type: :map, required: true],
      timeout: [type: :pos_integer, default: 60_000],
      chunk_timeout: [type: :pos_integer, default: 5_000]
    ]

  alias RubberDuck.LLM.HealthMonitor
  require Logger

  @impl true
  def run(params, _context) do
    provider = params.provider
    request = params.request
    timeout = params.timeout
    chunk_timeout = params.chunk_timeout

    try do
      # Ensure streaming is requested
      streaming_request = Map.put(request, :stream, true)

      # Add timeout to provider config
      config = Map.put(provider.config, :timeout, timeout)

      start_time = System.monotonic_time(:millisecond)

      case apply(provider.module, :stream, [streaming_request, config]) do
        {:ok, stream} ->
          # Wrap the stream to add monitoring and error handling
          monitored_stream = create_monitored_stream(stream, provider, start_time, chunk_timeout)

          {:ok, %{
            stream: monitored_stream,
            provider: provider.name,
            started_at: DateTime.utc_now()
          }}

        {:error, reason} ->
          duration = System.monotonic_time(:millisecond) - start_time
          HealthMonitor.record_failure(provider.name, reason)

          Logger.warning("LLM streaming failed for provider #{provider.name}: #{inspect(reason)}")

          {:error, %{
            reason: reason,
            provider: provider.name,
            duration_ms: duration
          }}
      end
    rescue
      exception ->
        # Record failure metrics
        HealthMonitor.record_failure(provider.name, exception)

        Logger.error("LLM streaming crashed for provider #{provider.name}: #{inspect(exception)}")

        {:error, %{
          reason: {:exception, exception},
          provider: provider.name,
          duration_ms: 0
        }}
    end
  end

  def describe do
    %{
      name: "LLM Stream",
      description: "Executes a streaming text generation request against an LLM provider",
      category: "llm",
      inputs: %{
        provider: "The provider configuration map with module and config",
        request: "The streaming request with model, messages, and parameters",
        timeout: "Maximum time to wait for stream completion in milliseconds",
        chunk_timeout: "Maximum time to wait for each chunk in milliseconds"
      },
      outputs: %{
        success: %{
          stream: "The stream of completion chunks",
          provider: "Name of the provider used",
          started_at: "When the stream started"
        },
        error: %{
          reason: "The error reason",
          provider: "Name of the provider that failed",
          duration_ms: "Time taken before failure"
        }
      }
    }
  end

  # Private functions

  defp create_monitored_stream(stream, provider, start_time, chunk_timeout) do
    Stream.resource(
      fn -> initialize_stream_state() end,
      fn state -> handle_stream_chunk(stream, state, provider, start_time, chunk_timeout) end,
      fn state -> cleanup_stream(state) end
    )
  end

  defp initialize_stream_state do
    %{
      chunks_received: 0,
      total_tokens: 0,
      last_chunk_time: System.monotonic_time(:millisecond)
    }
  end

  defp handle_stream_chunk(stream, state, provider, start_time, chunk_timeout) do
    task = create_chunk_task(stream)
    process_chunk_result(task, state, provider, start_time, chunk_timeout)
  rescue
    exception ->
      handle_stream_error(exception, provider, state)
  end

  defp create_chunk_task(stream) do
    Task.async(fn ->
      case Enum.take(stream, 1) do
        [chunk] -> {:ok, chunk}
        [] -> :done
      end
    end)
  end

  defp process_chunk_result(task, state, provider, start_time, chunk_timeout) do
    case Task.yield(task, chunk_timeout) || Task.shutdown(task) do
      {:ok, {:ok, chunk}} ->
        handle_successful_chunk(chunk, state)
      {:ok, :done} ->
        handle_stream_completion(provider, start_time, state)
      nil ->
        handle_chunk_timeout(provider, state)
    end
  end

  defp handle_successful_chunk(chunk, state) do
    new_state = %{state |
      chunks_received: state.chunks_received + 1,
      total_tokens: state.total_tokens + estimate_tokens(chunk),
      last_chunk_time: System.monotonic_time(:millisecond)
    }
    {[chunk], new_state}
  end

  defp handle_stream_completion(provider, start_time, state) do
    duration = System.monotonic_time(:millisecond) - start_time
    HealthMonitor.record_success(provider.name, duration)
    {:halt, state}
  end

  defp handle_chunk_timeout(provider, state) do
    Logger.warning("Stream chunk timeout for provider #{provider.name}")
    HealthMonitor.record_failure(provider.name, :chunk_timeout)
    {:halt, state}
  end

  defp handle_stream_error(exception, provider, state) do
    Logger.error("Stream chunk error for provider #{provider.name}: #{inspect(exception)}")
    HealthMonitor.record_failure(provider.name, exception)
    {:halt, state}
  end

  defp cleanup_stream(state) do
    Logger.debug("Stream completed: #{state.chunks_received} chunks, ~#{state.total_tokens} tokens")
  end

  defp estimate_tokens(chunk) when is_binary(chunk) do
    # Simple estimation: ~1 token per 4 characters
    div(String.length(chunk), 4)
  end

  defp estimate_tokens(chunk) when is_map(chunk) do
    # For structured chunks, estimate based on content
    content = chunk[:content] || chunk["content"] || ""
    estimate_tokens(content)
  end

  defp estimate_tokens(_), do: 0
end
