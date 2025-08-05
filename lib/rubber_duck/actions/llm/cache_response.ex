defmodule RubberDuck.Actions.LLM.CacheResponse do
  @moduledoc """
  Action for caching LLM responses to reduce costs and improve performance.

  Implements intelligent caching with TTL, invalidation, and similarity matching.
  """

  use Jido.Action,
    name: "llm_cache_response",
    description: "Cache or retrieve LLM responses for efficiency",
    schema: [
      operation: [type: :atom, values: [:get, :put, :invalidate], required: true],
      request: [type: :map, required: true],
      response: [type: :map, required: false],
      ttl_seconds: [type: :pos_integer, default: 3600],
      similarity_threshold: [type: :float, default: 0.95],
      cache_backend: [type: :atom, values: [:memory, :redis, :ets], default: :ets]
    ]

  require Logger

  # Use ETS for caching
  @cache_table :llm_response_cache
  @cache_stats_table :llm_cache_stats

  @impl true
  def run(params, _context) do
    case validate_cache_params(params) do
      :ok ->
        try do
          ensure_cache_tables()

          case params.operation do
            :get ->
              handle_cache_get(params)

            :put ->
              handle_cache_put(params)

            :invalidate ->
              handle_cache_invalidate(params)

            other ->
              {:error, %{reason: :invalid_operation, operation: other}}
          end
        rescue
          exception ->
            Logger.error("Cache operation failed: #{inspect(exception)}\n#{Exception.format_stacktrace()}")
            {:error, %{
              reason: {:exception, exception},
              message: Exception.message(exception),
              operation: params.operation
            }}
        end

      {:error, reason} ->
        {:error, %{reason: reason, stage: :validation}}
    end
  end

  def describe do
    %{
      name: "Cache LLM Response",
      description: "Manages caching of LLM responses for performance optimization",
      category: "llm",
      inputs: %{
        operation: "Cache operation to perform (:get, :put, :invalidate)",
        request: "The LLM request (used as cache key)",
        response: "The LLM response to cache (required for :put)",
        ttl_seconds: "Time to live for cached responses",
        similarity_threshold: "Threshold for fuzzy matching similar requests",
        cache_backend: "Backend storage for cache"
      },
      outputs: %{
        get_hit: %{
          cached_response: "The cached response",
          cache_key: "The cache key used",
          age_seconds: "Age of the cached response",
          similarity_score: "Similarity score if fuzzy matched"
        },
        get_miss: %{
          cache_key: "The cache key that was checked",
          reason: "Why the cache miss occurred"
        },
        put_success: %{
          cache_key: "The key under which response was cached",
          expires_at: "When the cache entry will expire"
        },
        invalidate_success: %{
          invalidated_count: "Number of entries invalidated",
          pattern: "The pattern used for invalidation"
        }
      }
    }
  end

  # Private functions

  defp ensure_cache_tables do
    try do
      # Create tables if they don't exist
      if :ets.whereis(@cache_table) == :undefined do
        :ets.new(@cache_table, [:set, :public, :named_table, read_concurrency: true])
      end

      if :ets.whereis(@cache_stats_table) == :undefined do
        :ets.new(@cache_stats_table, [:set, :public, :named_table])
        :ets.insert(@cache_stats_table, {:hits, 0})
        :ets.insert(@cache_stats_table, {:misses, 0})
        :ets.insert(@cache_stats_table, {:puts, 0})
      end
      :ok
    rescue
      exception ->
        Logger.error("Failed to create cache tables: #{inspect(exception)}")
        {:error, :cache_initialization_failed}
    end
  end

  defp handle_cache_get(params) do
    cache_key = generate_cache_key(params.request)
    now = System.system_time(:second)

    case lookup_cache(cache_key, params.similarity_threshold) do
      {:exact, cached_entry} ->
        handle_exact_cache_match(cached_entry, cache_key, now)
      {:similar, similar_key, similarity_score, cached_entry} ->
        handle_similar_cache_match(cached_entry, similar_key, similarity_score, cache_key, now, params)
      :not_found ->
        handle_cache_miss(cache_key)
    end
  end

  defp handle_exact_cache_match(cached_entry, cache_key, now) do
    if cached_entry.expires_at > now do
      handle_valid_cache_hit(cached_entry, cache_key, now, 1.0)
    else
      handle_expired_cache_entry(cache_key)
    end
  end

  defp handle_similar_cache_match(cached_entry, similar_key, similarity_score, cache_key, now, params) do
    if cached_entry.expires_at > now && similarity_score >= params.similarity_threshold do
      handle_valid_similarity_hit(cached_entry, similar_key, similarity_score, now)
    else
      handle_insufficient_similarity(cache_key)
    end
  end

  defp handle_valid_cache_hit(cached_entry, cache_key, now, similarity_score) do
    update_stats(:hit)
    {:ok, %{
      cached_response: cached_entry.response,
      cache_key: cache_key,
      age_seconds: now - cached_entry.cached_at,
      similarity_score: similarity_score
    }}
  end

  defp handle_valid_similarity_hit(cached_entry, similar_key, similarity_score, now) do
    update_stats(:hit)
    Logger.debug("Cache hit with similarity #{similarity_score} for key #{similar_key}")
    {:ok, %{
      cached_response: cached_entry.response,
      cache_key: similar_key,
      age_seconds: now - cached_entry.cached_at,
      similarity_score: similarity_score
    }}
  end

  defp handle_expired_cache_entry(cache_key) do
    :ets.delete(@cache_table, cache_key)
    update_stats(:miss)
    {:ok, %{cache_key: cache_key, reason: :expired}}
  end

  defp handle_insufficient_similarity(cache_key) do
    update_stats(:miss)
    {:ok, %{cache_key: cache_key, reason: :no_similar_match}}
  end

  defp handle_cache_miss(cache_key) do
    update_stats(:miss)
    {:ok, %{cache_key: cache_key, reason: :not_found}}
  end

  defp handle_cache_put(params) do
    if params.response do
      cache_key = generate_cache_key(params.request)
      now = System.system_time(:second)
      expires_at = now + params.ttl_seconds

      cache_entry = %{
        request: sanitize_request(params.request),
        response: params.response,
        cached_at: now,
        expires_at: expires_at,
        hit_count: 0
      }

      :ets.insert(@cache_table, {cache_key, cache_entry})
      update_stats(:put)

      # Clean up old entries periodically
      maybe_cleanup_expired()

      {:ok, %{
        cache_key: cache_key,
        expires_at: DateTime.from_unix!(expires_at)
      }}
    else
      {:error, %{reason: :response_required_for_put}}
    end
  end

  defp handle_cache_invalidate(params) do
    pattern = params.request[:pattern] || params.request[:model] || "_"

    # Find all matching keys
    matching_keys = @cache_table
      |> :ets.tab2list()
      |> Enum.filter(fn {key, _entry} ->
        String.contains?(key, pattern)
      end)
      |> Enum.map(fn {key, _} -> key end)

    # Delete matching entries
    Enum.each(matching_keys, &:ets.delete(@cache_table, &1))

    {:ok, %{
      invalidated_count: length(matching_keys),
      pattern: pattern
    }}
  end

  defp generate_cache_key(request) do
    # Create a normalized key from request
    normalized = %{
      model: request[:model],
      messages: normalize_messages(request[:messages] || []),
      temperature: request[:temperature] || 0,
      max_tokens: request[:max_tokens],
      system_fingerprint: get_system_fingerprint(request)
    }

    normalized
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16()
  end

  defp normalize_messages(messages) do
    # Normalize messages for consistent caching
    messages
    |> Enum.map(fn msg ->
      %{
        role: msg["role"] || msg[:role],
        content: String.trim(msg["content"] || msg[:content] || "")
      }
    end)
  end

  defp get_system_fingerprint(request) do
    # Extract system message as fingerprint
    messages = request[:messages] || []

    system_msg = Enum.find(messages, fn msg ->
      (msg["role"] || msg[:role]) == "system"
    end)

    if system_msg do
      content = system_msg["content"] || system_msg[:content] || ""
      content |> then(&:crypto.hash(:md5, &1)) |> Base.encode16() |> String.slice(0..7)
    else
      "no_system"
    end
  end

  defp sanitize_request(request) do
    # Remove sensitive or variable data from cached request
    request
    |> Map.drop([:api_key, :user_id, :session_id])
    |> Map.update(:messages, [], &sanitize_messages/1)
  end

  defp sanitize_messages(messages) do
    Enum.map(messages, fn msg ->
      msg
      |> Map.take(["role", "content", :role, :content])
      |> Map.update("content", "", &String.slice(&1, 0..200))
      |> Map.update(:content, "", &String.slice(&1, 0..200))
    end)
  end

  defp lookup_cache(cache_key, similarity_threshold) do
    case :ets.lookup(@cache_table, cache_key) do
      [{^cache_key, entry}] ->
        # Update hit count
        updated_entry = Map.update(entry, :hit_count, 1, &(&1 + 1))
        :ets.insert(@cache_table, {cache_key, updated_entry})
        {:exact, updated_entry}

      [] when similarity_threshold < 1.0 ->
        # Try fuzzy matching
        find_similar_cache_entry(cache_key, similarity_threshold)

      [] ->
        :not_found
    end
  end

  defp find_similar_cache_entry(target_key, threshold) do
    # This is a simplified similarity check
    # In production, use proper vector similarity or semantic matching

    all_entries = :ets.tab2list(@cache_table)

    similar_entries =
      all_entries
      |> Enum.map(fn {key, entry} ->
        score = calculate_similarity(target_key, key)
        {key, entry, score}
      end)
      |> Enum.filter(fn {_key, _entry, score} -> score >= threshold end)
      |> Enum.sort_by(fn {_key, _entry, score} -> score end, :desc)

    case similar_entries do
      [{key, entry, score} | _] ->
        {:similar, key, score, entry}
      [] ->
        :not_found
    end
  end

  defp calculate_similarity(key1, key2) do
    # Simple byte-wise similarity
    # In production, use proper distance metrics
    if key1 == key2 do
      1.0
    else
      # Compare first N bytes for rough similarity
      bytes1 = :binary.bin_to_list(key1, 0, min(16, byte_size(key1)))
      bytes2 = :binary.bin_to_list(key2, 0, min(16, byte_size(key2)))

      matching = bytes1
      |> Enum.zip(bytes2)
      |> Enum.count(fn {a, b} -> a == b end)

      matching / max(length(bytes1), length(bytes2))
    end
  end

  defp update_stats(type) do
    case type do
      :hit -> :ets.update_counter(@cache_stats_table, :hits, 1)
      :miss -> :ets.update_counter(@cache_stats_table, :misses, 1)
      :put -> :ets.update_counter(@cache_stats_table, :puts, 1)
    end
  end

  defp maybe_cleanup_expired do
    try do
      # Cleanup every 100 puts
      case :ets.lookup(@cache_stats_table, :puts) do
        [{:puts, put_count}] ->
          if rem(put_count, 100) == 0 do
            Task.start(fn ->
              try do
                cleanup_expired_entries()
              rescue
                e -> Logger.warning("Cleanup task failed: #{inspect(e)}")
              end
            end)
          end
        _ ->
          :ok
      end
    rescue
      exception ->
        Logger.warning("Failed to check cleanup: #{inspect(exception)}")
        :ok
    end
  end

  defp cleanup_expired_entries do
    try do
      expired_keys = find_expired_cache_keys()
      remove_expired_keys(expired_keys)
      log_cleanup_results(expired_keys)
    rescue
      exception ->
        Logger.error("Cleanup failed: #{inspect(exception)}")
    end
  end

  defp find_expired_cache_keys do
    now = System.system_time(:second)

    @cache_table
    |> :ets.tab2list()
    |> Enum.filter(&is_expired_entry?(&1, now))
    |> Enum.map(fn {key, _} -> key end)
  end

  defp is_expired_entry?({_key, entry}, now) do
    is_map(entry) && Map.get(entry, :expires_at, now + 1) <= now
  end

  defp remove_expired_keys(expired_keys) do
    Enum.each(expired_keys, &safe_delete_cache_key/1)
  end

  defp safe_delete_cache_key(key) do
    try do
      :ets.delete(@cache_table, key)
    rescue
      _ -> :ok
    end
  end

  defp log_cleanup_results(expired_keys) do
    if length(expired_keys) > 0 do
      Logger.info("Cleaned up #{length(expired_keys)} expired cache entries")
    end
  end

  defp validate_cache_params(params) do
    cond do
      not is_map(params) ->
        {:error, :invalid_params}

      not is_atom(params[:operation]) ->
        {:error, :invalid_operation_type}

      not is_map(params[:request]) ->
        {:error, :invalid_request}

      params.operation == :put && not is_map(params[:response]) ->
        {:error, :response_required_for_put}

      true ->
        :ok
    end
  end
end
