defmodule RubberDuck.Verdict.Providers.OpenAI.OpenAIClient do
  @moduledoc """
  HTTP client for OpenAI API integration.

  This module handles all HTTP communication with OpenAI's API including:
  - Chat completions for code evaluation
  - Streaming responses for real-time feedback
  - Error handling and retry logic
  - Rate limit detection and backoff
  """

  use GenServer
  require Logger

  @openai_base_url "https://api.openai.com"
  @default_timeout 30_000
  @max_retries 3
  @retry_base_delay 1000

  # Public API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def initialize(config) do
    case validate_client_config(config) do
      :ok ->
        # Start HTTP client process
        GenServer.start_link(__MODULE__, config)

      error ->
        error
    end
  end

  def complete(client_pid, request) when is_pid(client_pid) do
    GenServer.call(client_pid, {:complete, request}, @default_timeout + 5000)
  end

  def complete_streaming(client_pid, request, callback)
      when is_pid(client_pid) and is_function(callback) do
    GenServer.call(client_pid, {:complete_streaming, request, callback}, @default_timeout + 5000)
  end

  def shutdown(client_pid) when is_pid(client_pid) do
    GenServer.stop(client_pid)
  end

  # GenServer implementation

  @impl true
  def init(config) do
    state = %{
      api_key: config.api_key,
      base_url: Map.get(config, :base_url, @openai_base_url),
      timeout: Map.get(config, :timeout_ms, @default_timeout),
      retry_config:
        Map.get(config, :retry_config, %{
          max_retries: @max_retries,
          base_delay_ms: @retry_base_delay
        }),
      stats: %{
        requests_sent: 0,
        requests_successful: 0,
        total_response_time_ms: 0,
        last_request_at: nil
      }
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:complete, request}, _from, state) do
    start_time = System.monotonic_time(:millisecond)

    result = perform_completion_request(state, request)

    response_time = System.monotonic_time(:millisecond) - start_time
    updated_state = update_request_stats(state, result, response_time)

    {:reply, result, updated_state}
  end

  @impl true
  def handle_call({:complete_streaming, request, callback}, _from, state) do
    start_time = System.monotonic_time(:millisecond)

    result = perform_streaming_request(state, request, callback)

    response_time = System.monotonic_time(:millisecond) - start_time
    updated_state = update_request_stats(state, result, response_time)

    {:reply, result, updated_state}
  end

  # Private implementation

  defp validate_client_config(config) do
    case Map.get(config, :api_key) do
      nil -> {:error, "OpenAI API key is required"}
      key when is_binary(key) and byte_size(key) > 0 -> :ok
      _ -> {:error, "Invalid OpenAI API key format"}
    end
  end

  defp perform_completion_request(state, request) do
    url = "#{state.base_url}/v1/chat/completions"
    headers = build_headers(state.api_key)

    case make_http_request_with_retry(url, headers, request, state.retry_config, state.timeout) do
      {:ok, response_body} ->
        case Jason.decode(response_body) do
          {:ok, decoded_response} ->
            {:ok, decoded_response}

          {:error, json_error} ->
            Logger.error("Failed to decode OpenAI response: #{inspect(json_error)}")
            {:error, "Invalid JSON response from OpenAI"}
        end

      error ->
        error
    end
  end

  defp perform_streaming_request(state, request, callback) do
    url = "#{state.base_url}/v1/chat/completions"
    headers = build_headers(state.api_key) ++ [{"Accept", "text/event-stream"}]

    # Add streaming to request
    streaming_request = Map.put(request, :stream, true)

    case make_streaming_request(url, headers, streaming_request, callback, state.timeout) do
      {:ok, final_response} -> {:ok, final_response}
      error -> error
    end
  end

  defp build_headers(api_key) do
    [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"},
      {"User-Agent", "RubberDuck-Verdict/1.0"}
    ]
  end

  defp make_http_request_with_retry(url, headers, body, retry_config, timeout, attempt \\ 1) do
    json_body = Jason.encode!(body)

    case Req.post(url, headers: headers, body: json_body, receive_timeout: timeout) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %{status: 429}} when attempt <= retry_config.max_retries ->
        # Rate limited - retry with exponential backoff
        delay = retry_config.base_delay_ms * :math.pow(2, attempt - 1)
        Logger.info("OpenAI rate limited, retrying in #{delay}ms (attempt #{attempt})")
        Process.sleep(trunc(delay))
        make_http_request_with_retry(url, headers, body, retry_config, timeout, attempt + 1)

      {:ok, %{status: status, body: error_body}} ->
        Logger.error("OpenAI API error #{status}: #{inspect(error_body)}")
        {:error, "OpenAI API error: #{status}"}

      {:error, %{reason: :timeout}} ->
        {:error, "OpenAI API timeout"}

      {:error, reason} ->
        Logger.error("OpenAI HTTP request failed: #{inspect(reason)}")
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp make_streaming_request(url, headers, body, callback, timeout) do
    # This is a simplified streaming implementation
    # In production, would use proper Server-Sent Events parsing
    json_body = Jason.encode!(body)

    case Req.post(url, headers: headers, body: json_body, receive_timeout: timeout) do
      {:ok, %{status: 200, body: response_body}} ->
        # For now, simulate streaming by calling callback with chunks
        simulate_streaming_response(response_body, callback)

        # Parse final response
        case Jason.decode(response_body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:error, "Invalid streaming response"}
        end

      {:ok, %{status: status}} ->
        {:error, "OpenAI streaming error: #{status}"}

      {:error, reason} ->
        {:error, "Streaming request failed: #{inspect(reason)}"}
    end
  end

  defp simulate_streaming_response(response_body, callback) do
    # Simulate streaming by chunking the response
    chunks = String.split(response_body, " ") |> Enum.chunk_every(10)

    Enum.with_index(chunks, fn chunk, index ->
      callback.(%{
        type: :chunk,
        content: Enum.join(chunk, " "),
        chunk_index: index,
        timestamp: DateTime.utc_now()
      })

      # Small delay to simulate streaming
      Process.sleep(50)
    end)

    callback.(%{
      type: :complete,
      timestamp: DateTime.utc_now()
    })
  end

  defp update_request_stats(state, result, response_time) do
    current_stats = state.stats

    updated_stats = %{
      requests_sent: current_stats.requests_sent + 1,
      requests_successful:
        current_stats.requests_successful + if(match?({:ok, _}, result), do: 1, else: 0),
      total_response_time_ms: current_stats.total_response_time_ms + response_time,
      last_request_at: DateTime.utc_now()
    }

    %{state | stats: updated_stats}
  end

  # Public helper functions

  def get_client_stats(client_pid) when is_pid(client_pid) do
    GenServer.call(client_pid, :get_stats)
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    enhanced_stats =
      Map.merge(state.stats, %{
        success_rate: calculate_success_rate(state.stats),
        avg_response_time_ms: calculate_avg_response_time(state.stats)
      })

    {:reply, {:ok, enhanced_stats}, state}
  end

  defp calculate_success_rate(stats) do
    if stats.requests_sent > 0 do
      stats.requests_successful / stats.requests_sent
    else
      0.0
    end
  end

  defp calculate_avg_response_time(stats) do
    if stats.requests_sent > 0 do
      stats.total_response_time_ms / stats.requests_sent
    else
      0.0
    end
  end

  # Configuration and validation helpers

  def validate_api_key(api_key) when is_binary(api_key) do
    cond do
      String.starts_with?(api_key, "sk-") and String.length(api_key) > 20 ->
        :ok

      String.length(api_key) == 0 ->
        {:error, "API key cannot be empty"}

      true ->
        {:error, "Invalid OpenAI API key format"}
    end
  end

  def validate_api_key(_), do: {:error, "API key must be a string"}

  def test_connection(config) do
    case initialize(config) do
      {:ok, client_pid} ->
        test_request = %{
          model: "gpt-4o-mini",
          messages: [%{role: "user", content: "Test connection"}],
          max_tokens: 5
        }

        result = complete(client_pid, test_request)
        shutdown(client_pid)

        case result do
          {:ok, _response} -> {:ok, "Connection successful"}
          error -> error
        end

      error ->
        error
    end
  end
end
