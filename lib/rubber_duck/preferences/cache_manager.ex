defmodule RubberDuck.Preferences.CacheManager do
  @moduledoc """
  High-performance ETS-based cache management for preference resolution.

  Provides fast in-memory caching with TTL support, pattern-based invalidation,
  and cache warming strategies for optimal performance.
  """

  require Logger

  @default_ttl :timer.minutes(30)

  @doc """
  Create a new ETS cache table.
  """
  @spec create_table(atom(), list()) :: atom()
  def create_table(table_name, options \\ [:set, :public, :named_table]) do
    case :ets.info(table_name) do
      :undefined ->
        :ets.new(table_name, options)
        Logger.info("Created ETS cache table: #{table_name}")
        table_name

      _ ->
        Logger.debug("ETS cache table already exists: #{table_name}")
        table_name
    end
  end

  @doc """
  Get a value from cache with TTL checking.
  """
  @spec get(atom(), String.t()) :: {:ok, any()} | {:error, :not_found | :expired}
  def get(table, key) do
    case :ets.lookup(table, key) do
      [{^key, value, expires_at}] ->
        if System.system_time(:millisecond) < expires_at do
          {:ok, value}
        else
          :ets.delete(table, key)
          {:error, :expired}
        end

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Store a value in cache with TTL.
  """
  @spec put(atom(), String.t(), any(), non_neg_integer()) :: :ok
  def put(table, key, value, ttl_ms \\ @default_ttl) do
    expires_at = System.system_time(:millisecond) + ttl_ms
    :ets.insert(table, {key, value, expires_at})
    :ok
  end

  @doc """
  Remove a specific key from cache.
  """
  @spec invalidate(atom(), String.t()) :: :ok
  def invalidate(table, key) do
    :ets.delete(table, key)
    :ok
  end

  @doc """
  Remove all keys matching a pattern (using Elixir pattern matching).
  """
  @spec invalidate_pattern(atom(), String.t()) :: :ok
  def invalidate_pattern(table, pattern) do
    # Convert shell-style pattern to regex
    regex_pattern =
      pattern
      |> String.replace("*", ".*")
      |> then(&"^#{&1}$")
      |> Regex.compile!()

    table
    |> :ets.tab2list()
    |> Enum.each(fn {key, _value, _expires_at} ->
      if Regex.match?(regex_pattern, key) do
        :ets.delete(table, key)
      end
    end)

    :ok
  end

  @doc """
  Clear all entries from cache.
  """
  @spec clear_all(atom()) :: :ok
  def clear_all(table) do
    :ets.delete_all_objects(table)
    :ok
  end

  @doc """
  Get cache statistics for monitoring.
  """
  @spec stats(atom()) :: %{
          size: non_neg_integer(),
          memory_usage: non_neg_integer(),
          expired_entries: non_neg_integer()
        }
  def stats(table) do
    size = :ets.info(table, :size)
    memory_usage = :ets.info(table, :memory) * :erlang.system_info(:wordsize)

    current_time = System.system_time(:millisecond)

    expired_count =
      table
      |> :ets.tab2list()
      |> Enum.count(fn {_key, _value, expires_at} -> expires_at <= current_time end)

    %{
      size: size,
      memory_usage: memory_usage,
      expired_entries: expired_count
    }
  end

  @doc """
  Clean up expired entries to free memory.
  """
  @spec cleanup_expired(atom()) :: non_neg_integer()
  def cleanup_expired(table) do
    current_time = System.system_time(:millisecond)

    expired_keys =
      table
      |> :ets.tab2list()
      |> Enum.filter(fn {_key, _value, expires_at} -> expires_at <= current_time end)
      |> Enum.map(fn {key, _value, _expires_at} -> key end)

    Enum.each(expired_keys, &:ets.delete(table, &1))

    expired_count = length(expired_keys)

    if expired_count > 0 do
      Logger.debug("Cleaned up #{expired_count} expired cache entries from #{table}")
    end

    expired_count
  end

  @doc """
  Warm cache with frequently accessed preferences.
  """
  @spec warm_cache(atom(), [
          %{user_id: binary(), preference_keys: [String.t()], project_id: binary() | nil}
        ]) :: :ok
  def warm_cache(_table, warmup_specs) do
    Logger.info("Warming cache for #{length(warmup_specs)} user/project combinations")

    Enum.each(warmup_specs, fn %{user_id: user_id, preference_keys: keys, project_id: project_id} ->
      Enum.each(keys, fn key ->
        # This will populate cache as a side effect
        RubberDuck.Preferences.PreferenceResolver.resolve(user_id, key, project_id)
      end)
    end)

    :ok
  end

  @doc """
  Check if cache table exists and is accessible.
  """
  @spec table_exists?(atom()) :: boolean()
  def table_exists?(table) do
    case :ets.info(table) do
      :undefined -> false
      _ -> true
    end
  end
end
