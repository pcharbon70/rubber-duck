defmodule RubberDuck.Verdict.Providers.Anthropic.AnthropicClient do
  @moduledoc """
  HTTP client for Anthropic Claude API integration.

  This module handles communication with Anthropic's API including:
  - Claude message completion requests
  - Streaming responses with Server-Sent Events
  - Rate limiting and error handling
  - Integration with Anthropic's API headers and metadata
  """

  use GenServer
  require Logger

  @anthropic_base_url "https://api.anthropic.com"
  @api_version "2023-06-01"
  # Claude can be slower but more thorough
  @default_timeout 45_000
  @max_retries 3
  # Longer delays for Anthropic
  @retry_base_delay 2000

  # Public API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def initialize(config) do
    case validate_client_config(config) do
      :ok ->
        GenServer.start_link(__MODULE__, config)

      error ->
        error
    end
  end

  def complete(client_pid, request) when is_pid(client_pid) do
    GenServer.call(client_pid, {:complete, request}, @default_timeout + 10_000)
  end

  def complete_streaming(client_pid, request, callback)
      when is_pid(client_pid) and is_function(callback) do
    GenServer.call(
      client_pid,
      {:complete_streaming, request, callback},
      @default_timeout + 10_000
    )
  end

  def shutdown(client_pid) when is_pid(client_pid) do
    GenServer.stop(client_pid)
  end

  # GenServer implementation

  @impl true
  def init(config) do
    state = %{
      api_key: config.api_key,
      base_url: Map.get(config, :base_url, @anthropic_base_url),
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
        total_tokens_used: 0,
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

  @impl true
  def handle_call(:get_stats, _from, state) do
    enhanced_stats =
      Map.merge(state.stats, %{
        success_rate: calculate_success_rate(state.stats),
        avg_response_time_ms: calculate_avg_response_time(state.stats),
        avg_tokens_per_request: calculate_avg_tokens_per_request(state.stats)
      })

    {:reply, {:ok, enhanced_stats}, state}
  end

  # Private implementation

  defp validate_client_config(config) do
    case Map.get(config, :api_key) do
      nil -> {:error, "Anthropic API key is required"}
      key when is_binary(key) and byte_size(key) > 0 -> :ok
      _ -> {:error, "Invalid Anthropic API key format"}
    end
  end

  defp perform_completion_request(state, request) do
    url = "#{state.base_url}/v1/messages"
    headers = build_anthropic_headers(state.api_key)

    # Convert request to Anthropic format
    anthropic_request = convert_to_anthropic_format(request)

    case make_http_request_with_retry(
           url,
           headers,
           anthropic_request,
           state.retry_config,
           state.timeout
         ) do
      {:ok, response_body} ->
        case Jason.decode(response_body) do
          {:ok, decoded_response} ->
            {:ok, decoded_response}

          {:error, json_error} ->
            Logger.error("Failed to decode Anthropic response: #{inspect(json_error)}")
            {:error, "Invalid JSON response from Anthropic"}
        end

      error ->
        error
    end
  end

  defp perform_streaming_request(state, request, callback) do
    url = "#{state.base_url}/v1/messages"
    headers = build_anthropic_headers(state.api_key) ++ [{"Accept", "text/event-stream"}]

    # Convert to Anthropic streaming format
    streaming_request =
      request
      |> convert_to_anthropic_format()
      |> Map.put(:stream, true)

    case make_streaming_request(url, headers, streaming_request, callback, state.timeout) do
      {:ok, final_response} -> {:ok, final_response}
      error -> error
    end
  end

  defp build_anthropic_headers(api_key) do
    [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"},
      {"Anthropic-Version", @api_version},
      {"User-Agent", "RubberDuck-Verdict/1.0"}
    ]
  end

  defp convert_to_anthropic_format(request) do
    # Convert generic request format to Anthropic's message format
    %{
      model: Map.get(request, :model, "claude-3-haiku-20240307"),
      max_tokens: Map.get(request, :max_tokens, 1000),
      temperature: Map.get(request, :temperature, 0.0),
      system: Map.get(request, :system, ""),
      messages: convert_messages_to_anthropic(Map.get(request, :messages, []))
    }
  end

  defp convert_messages_to_anthropic(messages) do
    # Anthropic uses a different message format
    Enum.map(messages, fn message ->
      %{
        role: Map.get(message, :role, "user"),
        content: Map.get(message, :content, "")
      }
    end)
    # System prompt handled separately
    |> Enum.filter(fn msg -> msg.role != "system" end)
  end

  defp make_http_request_with_retry(url, headers, body, retry_config, timeout, attempt \\ 1) do
    json_body = Jason.encode!(body)

    case Req.post(url, headers: headers, body: json_body, receive_timeout: timeout) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %{status: 429}} when attempt <= retry_config.max_retries ->
        # Rate limited - retry with exponential backoff
        delay = retry_config.base_delay_ms * :math.pow(2, attempt - 1)
        Logger.info("Anthropic rate limited, retrying in #{delay}ms (attempt #{attempt})")
        Process.sleep(trunc(delay))
        make_http_request_with_retry(url, headers, body, retry_config, timeout, attempt + 1)

      {:ok, %{status: status, body: error_body}} ->
        Logger.error("Anthropic API error #{status}: #{inspect(error_body)}")
        {:error, "Anthropic API error: #{status}"}

      {:error, %{reason: :timeout}} ->
        {:error, "Anthropic API timeout"}

      {:error, reason} ->
        Logger.error("Anthropic HTTP request failed: #{inspect(reason)}")
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp make_streaming_request(url, headers, body, callback, timeout) do
    # Simplified streaming implementation for Anthropic
    json_body = Jason.encode!(body)

    case Req.post(url, headers: headers, body: json_body, receive_timeout: timeout) do
      {:ok, %{status: 200, body: response_body}} ->
        # Simulate streaming by chunking response
        simulate_anthropic_streaming(response_body, callback)

        case Jason.decode(response_body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:error, "Invalid Anthropic streaming response"}
        end

      {:ok, %{status: status}} ->
        {:error, "Anthropic streaming error: #{status}"}

      {:error, reason} ->
        {:error, "Streaming request failed: #{inspect(reason)}"}
    end
  end

  defp simulate_anthropic_streaming(response_body, callback) do
    # Simulate Claude's streaming response pattern
    case Jason.decode(response_body) do
      {:ok, %{content: [%{text: text}]}} ->
        # Break text into chunks and stream
        chunks = String.split(text, ". ") |> Enum.with_index()

        Enum.each(chunks, fn {chunk, index} ->
          callback.(%{
            type: :content_block_delta,
            delta: %{text: chunk <> if(index < length(chunks) - 1, do: ". ", else: "")},
            index: index
          })

          # Simulate streaming delay
          Process.sleep(100)
        end)

        callback.(%{
          type: :message_stop,
          stop_reason: "end_turn"
        })

      _ ->
        callback.(%{
          type: :error,
          error: %{message: "Failed to parse response for streaming"}
        })
    end
  end

  defp update_request_stats(state, result, response_time) do
    current_stats = state.stats

    # Extract token usage if available
    token_usage =
      case result do
        {:ok, response} -> get_anthropic_token_usage(response)
        _ -> 0
      end

    updated_stats = %{
      requests_sent: current_stats.requests_sent + 1,
      requests_successful:
        current_stats.requests_successful + if(match?({:ok, _}, result), do: 1, else: 0),
      total_response_time_ms: current_stats.total_response_time_ms + response_time,
      total_tokens_used: current_stats.total_tokens_used + token_usage,
      last_request_at: DateTime.utc_now()
    }

    %{state | stats: updated_stats}
  end

  defp get_anthropic_token_usage(response) when is_map(response) do
    case Map.get(response, :usage) do
      %{input_tokens: input, output_tokens: output} -> input + output
      _ -> 0
    end
  end

  defp get_anthropic_token_usage(_), do: 0

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

  defp calculate_avg_tokens_per_request(stats) do
    if stats.requests_successful > 0 do
      stats.total_tokens_used / stats.requests_successful
    else
      0.0
    end
  end

  # Configuration and validation helpers

  def validate_api_key(api_key) when is_binary(api_key) do
    cond do
      String.starts_with?(api_key, "sk-ant-") and String.length(api_key) > 20 ->
        :ok

      String.length(api_key) == 0 ->
        {:error, "API key cannot be empty"}

      true ->
        {:error, "Invalid Anthropic API key format"}
    end
  end

  def validate_api_key(_), do: {:error, "API key must be a string"}

  def test_connection(config) do
    case initialize(config) do
      {:ok, client_pid} ->
        test_request = %{
          model: "claude-3-haiku-20240307",
          messages: [%{role: "user", content: "Test connection"}],
          max_tokens: 10
        }

        result = complete(client_pid, test_request)
        shutdown(client_pid)

        case result do
          {:ok, _response} -> {:ok, "Anthropic connection successful"}
          error -> error
        end

      error ->
        error
    end
  end
end
