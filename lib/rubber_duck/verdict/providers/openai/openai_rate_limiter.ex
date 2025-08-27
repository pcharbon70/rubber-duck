defmodule RubberDuck.Verdict.Providers.OpenAI.OpenAIRateLimiter do
  @moduledoc """
  Rate limiting and quota management for OpenAI API calls.

  This module implements sophisticated rate limiting to respect OpenAI's
  API limits while maximizing throughput:
  - Token-based and request-based rate limiting
  - Intelligent queuing and backoff strategies  
  - Quota tracking and budget management
  - Integration with OpenAI's rate limit headers
  """

  use GenServer
  require Logger

  @default_limits %{
    requests_per_minute: 500,
    tokens_per_minute: 10_000,
    requests_per_hour: 10_000,
    tokens_per_hour: 200_000
  }

  # 1 second
  @bucket_refill_interval 1000

  # Public API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def initialize(rate_limits) do
    GenServer.start_link(__MODULE__, rate_limits)
  end

  def check_limits(rate_limiter_pid, request_count, token_count) when is_pid(rate_limiter_pid) do
    GenServer.call(rate_limiter_pid, {:check_limits, request_count, token_count})
  end

  def record_usage(rate_limiter_pid, request_count, token_count, response_headers \\ %{})
      when is_pid(rate_limiter_pid) do
    GenServer.cast(
      rate_limiter_pid,
      {:record_usage, request_count, token_count, response_headers}
    )
  end

  def get_status(rate_limiter_pid) when is_pid(rate_limiter_pid) do
    GenServer.call(rate_limiter_pid, :get_status)
  end

  def update_limits(rate_limiter_pid, new_limits) when is_pid(rate_limiter_pid) do
    GenServer.call(rate_limiter_pid, {:update_limits, new_limits})
  end

  def shutdown(rate_limiter_pid) when is_pid(rate_limiter_pid) do
    GenServer.stop(rate_limiter_pid)
  end

  # GenServer implementation

  @impl true
  def init(rate_limits) do
    limits = Map.merge(@default_limits, rate_limits)

    state = %{
      limits: limits,
      buckets: initialize_token_buckets(limits),
      usage_history: [],
      last_refill: DateTime.utc_now(),
      openai_quota_info: %{},
      stats: %{
        requests_allowed: 0,
        requests_denied: 0,
        total_tokens_consumed: 0,
        avg_wait_time_ms: 0
      }
    }

    # Start bucket refill timer
    schedule_bucket_refill()

    Logger.debug("OpenAI rate limiter initialized with limits: #{inspect(limits)}")
    {:ok, state}
  end

  @impl true
  def handle_call({:check_limits, request_count, token_count}, _from, state) do
    case can_proceed?(state, request_count, token_count) do
      :ok ->
        # Reserve capacity
        updated_state = reserve_capacity(state, request_count, token_count)
        updated_stats = Map.update!(updated_state.stats, :requests_allowed, &(&1 + 1))
        {:reply, :ok, %{updated_state | stats: updated_stats}}

      {:wait, delay_ms} ->
        Logger.debug("Rate limit hit, suggesting wait: #{delay_ms}ms")
        updated_stats = Map.update!(state.stats, :requests_denied, &(&1 + 1))
        {:reply, {:wait, delay_ms}, %{state | stats: updated_stats}}

      {:error, reason} = error ->
        Logger.warning("Rate limit check failed: #{reason}")
        updated_stats = Map.update!(state.stats, :requests_denied, &(&1 + 1))
        {:reply, error, %{state | stats: updated_stats}}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      requests_remaining: state.buckets.requests_per_minute.current,
      tokens_remaining: state.buckets.tokens_per_minute.current,
      requests_per_minute_limit: state.limits.requests_per_minute,
      tokens_per_minute_limit: state.limits.tokens_per_minute,
      quota_percentage_used: calculate_quota_usage(state),
      last_refill: state.last_refill,
      stats: state.stats
    }

    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call({:update_limits, new_limits}, _from, state) do
    updated_limits = Map.merge(state.limits, new_limits)
    updated_buckets = initialize_token_buckets(updated_limits)

    Logger.info("Updated OpenAI rate limits: #{inspect(new_limits)}")
    {:reply, :ok, %{state | limits: updated_limits, buckets: updated_buckets}}
  end

  @impl true
  def handle_cast({:record_usage, request_count, token_count, response_headers}, state) do
    # Record actual usage and update buckets
    timestamp = DateTime.utc_now()

    usage_entry = %{
      timestamp: timestamp,
      requests: request_count,
      tokens: token_count,
      response_headers: response_headers
    }

    # Update usage history (keep last 100 entries)
    updated_history = [usage_entry | state.usage_history] |> Enum.take(100)

    # Update OpenAI quota info from response headers
    updated_quota_info = parse_openai_headers(response_headers)

    # Update statistics
    updated_stats = %{
      state.stats
      | total_tokens_consumed: state.stats.total_tokens_consumed + token_count
    }

    new_state = %{
      state
      | usage_history: updated_history,
        openai_quota_info: updated_quota_info,
        stats: updated_stats
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:refill_buckets, state) do
    updated_state = refill_token_buckets(state)
    schedule_bucket_refill()
    {:noreply, updated_state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # Private implementation

  defp initialize_token_buckets(limits) do
    %{
      requests_per_minute: %{
        capacity: limits.requests_per_minute,
        current: limits.requests_per_minute,
        # Per second
        refill_rate: limits.requests_per_minute / 60
      },
      tokens_per_minute: %{
        capacity: limits.tokens_per_minute,
        current: limits.tokens_per_minute,
        # Per second
        refill_rate: limits.tokens_per_minute / 60
      }
    }
  end

  defp can_proceed?(state, request_count, token_count) do
    requests_available = state.buckets.requests_per_minute.current >= request_count
    tokens_available = state.buckets.tokens_per_minute.current >= token_count

    cond do
      requests_available and tokens_available ->
        :ok

      not requests_available ->
        wait_time = calculate_wait_time_for_requests(state, request_count)
        {:wait, wait_time}

      not tokens_available ->
        wait_time = calculate_wait_time_for_tokens(state, token_count)
        {:wait, wait_time}

      true ->
        {:error, "Unknown rate limit condition"}
    end
  end

  defp reserve_capacity(state, request_count, token_count) do
    updated_buckets = %{
      requests_per_minute: %{
        state.buckets.requests_per_minute
        | current: state.buckets.requests_per_minute.current - request_count
      },
      tokens_per_minute: %{
        state.buckets.tokens_per_minute
        | current: state.buckets.tokens_per_minute.current - token_count
      }
    }

    %{state | buckets: updated_buckets}
  end

  defp calculate_wait_time_for_requests(state, needed_requests) do
    available_requests = state.buckets.requests_per_minute.current
    deficit = needed_requests - available_requests
    refill_rate = state.buckets.requests_per_minute.refill_rate

    # Calculate time needed to accumulate required requests
    # Add small buffer
    trunc(deficit / refill_rate * 1000) + 100
  end

  defp calculate_wait_time_for_tokens(state, needed_tokens) do
    available_tokens = state.buckets.tokens_per_minute.current
    deficit = needed_tokens - available_tokens
    refill_rate = state.buckets.tokens_per_minute.refill_rate

    # Calculate time needed to accumulate required tokens
    # Add small buffer
    trunc(deficit / refill_rate * 1000) + 100
  end

  defp refill_token_buckets(state) do
    now = DateTime.utc_now()
    time_since_refill = DateTime.diff(now, state.last_refill, :millisecond)

    # Calculate refill amount based on time elapsed
    refill_seconds = time_since_refill / 1000

    updated_buckets = %{
      requests_per_minute:
        refill_bucket(
          state.buckets.requests_per_minute,
          refill_seconds
        ),
      tokens_per_minute:
        refill_bucket(
          state.buckets.tokens_per_minute,
          refill_seconds
        )
    }

    %{state | buckets: updated_buckets, last_refill: now}
  end

  defp refill_bucket(bucket, refill_seconds) do
    refill_amount = bucket.refill_rate * refill_seconds
    new_current = min(bucket.capacity, bucket.current + refill_amount)

    %{bucket | current: new_current}
  end

  defp parse_openai_headers(headers) when is_map(headers) do
    %{
      requests_remaining: parse_header_value(headers, "x-ratelimit-remaining-requests"),
      tokens_remaining: parse_header_value(headers, "x-ratelimit-remaining-tokens"),
      requests_reset_at: parse_header_timestamp(headers, "x-ratelimit-reset-requests"),
      tokens_reset_at: parse_header_timestamp(headers, "x-ratelimit-reset-tokens")
    }
  end

  defp parse_openai_headers(_), do: %{}

  defp parse_header_value(headers, header_name) do
    case Map.get(headers, header_name) do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {num, _} -> num
          :error -> 0
        end

      value when is_integer(value) ->
        value

      _ ->
        0
    end
  end

  defp parse_header_timestamp(headers, header_name) do
    case Map.get(headers, header_name) do
      timestamp when is_binary(timestamp) ->
        case DateTime.from_iso8601(timestamp) do
          {:ok, dt, _offset} -> dt
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp calculate_quota_usage(state) do
    requests_used = state.limits.requests_per_minute - state.buckets.requests_per_minute.current
    tokens_used = state.limits.tokens_per_minute - state.buckets.tokens_per_minute.current

    request_percentage = requests_used / state.limits.requests_per_minute
    token_percentage = tokens_used / state.limits.tokens_per_minute

    # Return the higher percentage as overall usage
    max(request_percentage, token_percentage) * 100
  end

  defp schedule_bucket_refill do
    Process.send_after(self(), :refill_buckets, @bucket_refill_interval)
  end

  # Public utility functions

  def estimate_request_tokens(request) when is_map(request) do
    # Estimate tokens for OpenAI request
    messages = Map.get(request, :messages, [])

    message_tokens =
      messages
      |> Enum.map(fn msg ->
        content = Map.get(msg, :content, "")
        # Rough estimate: 4 characters per token
        div(String.length(content), 4)
      end)
      |> Enum.sum()

    # Add overhead for message formatting and response
    message_tokens + 100
  end

  def calculate_optimal_batch_size(available_requests, available_tokens, avg_tokens_per_request) do
    # Calculate how many requests can fit in current quota
    requests_by_quota = available_requests

    requests_by_tokens =
      if avg_tokens_per_request > 0 do
        trunc(available_tokens / avg_tokens_per_request)
      else
        available_requests
      end

    min(requests_by_quota, requests_by_tokens)
  end

  def get_wait_time_estimate(rate_limiter_pid, request_count, token_count)
      when is_pid(rate_limiter_pid) do
    case check_limits(rate_limiter_pid, request_count, token_count) do
      :ok -> 0
      {:wait, delay_ms} -> delay_ms
      {:error, _} -> :infinity
    end
  end
end
