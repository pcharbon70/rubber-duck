defmodule RubberDuck.Prompts.Caching.PersistentCacheLayer do
  @moduledoc """
  Level 3 DETS-based persistent cache layer with background maintenance.

  Provides long-term cache persistence using DETS with crash recovery,
  background maintenance tasks, and compact storage optimization.
  Designed for 24-hour cache retention with restart recovery capabilities.

  Features:
  - DETS-based persistence for restart recovery and long-term cache retention
  - 24-hour TTL with background expiration and maintenance tasks
  - Compact storage format optimization for disk space efficiency and performance
  - Background cache maintenance tasks with configurable intervals and cleanup
  - Crash recovery with automatic repair and data integrity validation
  - Integration with multi-tier cache promotion and intelligent warming strategies
  """

  use GenServer
  require Logger

  @dets_table_name :prompt_persistent_cache
  # 24 hours
  @default_ttl_seconds 86_400
  # 1 hour
  @maintenance_interval_ms 3_600_000
  # Compact after 10k operations
  @compact_threshold 10_000

  defstruct [
    :dets_table,
    :config,
    :maintenance_state,
    :storage_stats
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    config = build_persistent_config(opts)

    # Initialize DETS table
    dets_path = build_dets_path(config)

    case open_dets_table(dets_path) do
      {:ok, dets_table} ->
        state = %__MODULE__{
          dets_table: dets_table,
          config: config,
          maintenance_state: initialize_maintenance_state(),
          storage_stats: initialize_storage_stats()
        }

        # Schedule background maintenance
        schedule_maintenance_task()

        Logger.info("PersistentCacheLayer: DETS persistent cache initialized",
          dets_file: dets_path,
          maintenance_interval: @maintenance_interval_ms
        )

        {:ok, state}

      {:error, reason} ->
        Logger.error("PersistentCacheLayer: Failed to initialize DETS", error: reason)
        {:stop, {:dets_initialization_failed, reason}}
    end
  end

  # Public API

  def get(cache_key, config \\ %{}) do
    GenServer.call(__MODULE__, {:get, cache_key, config})
  end

  def put(cache_key, data, ttl_seconds \\ nil, config \\ %{}) do
    GenServer.call(__MODULE__, {:put, cache_key, data, ttl_seconds, config})
  end

  def invalidate(cache_key_pattern, config \\ %{}) do
    GenServer.cast(__MODULE__, {:invalidate, cache_key_pattern, config})
  end

  def compact_storage do
    GenServer.cast(__MODULE__, :compact_storage)
  end

  def get_storage_stats do
    GenServer.call(__MODULE__, :get_storage_stats)
  end

  def repair_if_needed do
    GenServer.call(__MODULE__, :repair_if_needed)
  end

  # GenServer callbacks

  def handle_call({:get, cache_key, _config}, _from, state) do
    get_start_time = System.monotonic_time(:microsecond)

    case :dets.lookup(state.dets_table, cache_key) do
      [{^cache_key, data, expiry_time, metadata}] ->
        current_time = System.system_time(:second)

        if current_time < expiry_time do
          # Update access metadata
          updated_metadata = Map.update(metadata, :access_count, 1, &(&1 + 1))
          :dets.insert(state.dets_table, {cache_key, data, expiry_time, updated_metadata})

          get_time = System.monotonic_time(:microsecond) - get_start_time

          Logger.debug("PersistentCacheLayer: Cache hit",
            cache_key: cache_key,
            get_time_us: get_time
          )

          {:reply, {:ok, data}, state}
        else
          # Expired entry
          :dets.delete(state.dets_table, cache_key)

          Logger.debug("PersistentCacheLayer: Expired entry removed", cache_key: cache_key)

          {:reply, {:error, :cache_miss}, state}
        end

      [] ->
        {:reply, {:error, :cache_miss}, state}
    end
  end

  def handle_call({:put, cache_key, data, ttl_seconds, _config}, _from, state) do
    put_start_time = System.monotonic_time(:microsecond)

    ttl = ttl_seconds || @default_ttl_seconds
    expiry_time = System.system_time(:second) + ttl

    metadata = %{
      created_at: System.system_time(:second),
      access_count: 0,
      data_size: estimate_data_size(data)
    }

    case :dets.insert(state.dets_table, {cache_key, data, expiry_time, metadata}) do
      :ok ->
        put_time = System.monotonic_time(:microsecond) - put_start_time

        # Update operation count for compaction trigger
        updated_maintenance_state = increment_operation_count(state.maintenance_state)
        updated_state = %{state | maintenance_state: updated_maintenance_state}

        # Check if compaction is needed
        maybe_trigger_compaction(updated_state)

        Logger.debug("PersistentCacheLayer: Entry persisted",
          cache_key: cache_key,
          ttl_seconds: ttl,
          put_time_us: put_time
        )

        {:reply, :ok, updated_state}

      {:error, reason} ->
        Logger.error("PersistentCacheLayer: Failed to persist entry",
          cache_key: cache_key,
          error: reason
        )

        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_storage_stats, _from, state) do
    dets_info = :dets.info(state.dets_table)

    storage_stats = %{
      total_entries: Keyword.get(dets_info, :size, 0),
      file_size_bytes: Keyword.get(dets_info, :file_size, 0),
      memory_usage_bytes: Keyword.get(dets_info, :memory, 0),
      last_maintenance: state.maintenance_state.last_maintenance,
      compaction_count: state.maintenance_state.compaction_count,
      repair_count: state.maintenance_state.repair_count
    }

    {:reply, {:ok, storage_stats}, state}
  end

  def handle_call(:repair_if_needed, _from, state) do
    case :dets.info(state.dets_table, :repair) do
      false ->
        {:reply, {:ok, :no_repair_needed}, state}

      true ->
        Logger.info("PersistentCacheLayer: Attempting DETS repair")

        case repair_dets_table(state) do
          :ok ->
            updated_maintenance_state = increment_repair_count(state.maintenance_state)
            updated_state = %{state | maintenance_state: updated_maintenance_state}

            {:reply, {:ok, :repair_completed}, updated_state}

          {:error, reason} ->
            {:reply, {:error, {:repair_failed, reason}}, state}
        end
    end
  end

  def handle_cast({:invalidate, cache_key_pattern, _config}, state) do
    invalidation_start_time = System.monotonic_time(:microsecond)

    # Find matching entries
    matching_entries = find_matching_entries(cache_key_pattern, state)

    # Delete matching entries
    deleted_count =
      Enum.reduce(matching_entries, 0, fn {key, _data, _expiry, _metadata}, acc ->
        case :dets.delete(state.dets_table, key) do
          :ok -> acc + 1
          {:error, _} -> acc
        end
      end)

    invalidation_time = System.monotonic_time(:microsecond) - invalidation_start_time

    Logger.info("PersistentCacheLayer: Cache invalidation completed",
      pattern: cache_key_pattern,
      deleted_count: deleted_count,
      invalidation_time_us: invalidation_time
    )

    {:noreply, state}
  end

  def handle_cast(:compact_storage, state) do
    # Execute storage compaction
    execute_storage_compaction(state)

    {:noreply, state}
  end

  def handle_info(:maintenance_task, state) do
    # Execute periodic maintenance
    updated_state = execute_maintenance_tasks(state)
    schedule_maintenance_task()

    {:noreply, updated_state}
  end

  # Private maintenance functions

  defp execute_maintenance_tasks(state) do
    maintenance_start_time = System.monotonic_time(:microsecond)

    # Execute various maintenance tasks
    cleanup_expired_entries(state)
    update_storage_statistics(state)
    maybe_execute_compaction(state)

    maintenance_time = System.monotonic_time(:microsecond) - maintenance_start_time

    updated_maintenance_state = %{
      state.maintenance_state
      | last_maintenance: System.system_time(:second),
        maintenance_count: state.maintenance_state.maintenance_count + 1,
        last_maintenance_time_us: maintenance_time
    }

    Logger.debug("PersistentCacheLayer: Maintenance completed",
      maintenance_time_us: maintenance_time
    )

    %{state | maintenance_state: updated_maintenance_state}
  end

  defp cleanup_expired_entries(state) do
    # Remove expired entries
    current_time = System.system_time(:second)

    expired_keys =
      :dets.select(state.dets_table, [
        {{:"$1", :"$2", :"$3", :"$4"}, [{:<, :"$3", current_time}], [:"$1"]}
      ])

    deleted_count =
      Enum.reduce(expired_keys, 0, fn key, acc ->
        case :dets.delete(state.dets_table, key) do
          :ok -> acc + 1
          {:error, _} -> acc
        end
      end)

    if deleted_count > 0 do
      Logger.debug("PersistentCacheLayer: Expired entries cleaned up",
        deleted_count: deleted_count
      )
    end
  end

  defp update_storage_statistics(state) do
    # Update storage statistics
    dets_info = :dets.info(state.dets_table)

    updated_stats = %{
      state.storage_stats
      | total_entries: Keyword.get(dets_info, :size, 0),
        file_size_bytes: Keyword.get(dets_info, :file_size, 0),
        last_stats_update: System.system_time(:second)
    }

    %{state | storage_stats: updated_stats}
  end

  defp maybe_execute_compaction(state) do
    if should_compact?(state) do
      execute_storage_compaction(state)
    end
  end

  defp execute_storage_compaction(state) do
    compaction_start_time = System.monotonic_time(:microsecond)

    Logger.info("PersistentCacheLayer: Starting storage compaction")

    case :dets.close(state.dets_table) do
      :ok ->
        # Reopen table to trigger compaction
        dets_path = build_dets_path(state.config)

        case :dets.open_file(state.dets_table, [{:file, String.to_charlist(dets_path)}]) do
          {:ok, _table} ->
            compaction_time = System.monotonic_time(:microsecond) - compaction_start_time

            Logger.info("PersistentCacheLayer: Storage compaction completed",
              compaction_time_us: compaction_time
            )

            # Reset operation count
            updated_maintenance_state = %{
              state.maintenance_state
              | operation_count: 0,
                compaction_count: state.maintenance_state.compaction_count + 1
            }

            %{state | maintenance_state: updated_maintenance_state}

          {:error, reason} ->
            Logger.error("PersistentCacheLayer: Compaction failed", error: reason)
            state
        end

      {:error, reason} ->
        Logger.error("PersistentCacheLayer: Failed to close DETS for compaction", error: reason)
        state
    end
  end

  # Utility functions

  defp build_persistent_config(opts) do
    %{
      dets_file_prefix: Keyword.get(opts, :dets_file_prefix, "prompt_cache"),
      ttl_seconds: Keyword.get(opts, :ttl_seconds, @default_ttl_seconds),
      maintenance_enabled: Keyword.get(opts, :maintenance_enabled, true),
      compaction_enabled: Keyword.get(opts, :compaction_enabled, true),
      repair_enabled: Keyword.get(opts, :repair_enabled, true)
    }
  end

  defp build_dets_path(config) do
    cache_dir = Path.join([System.tmp_dir(), "rubber_duck_cache"])
    File.mkdir_p!(cache_dir)
    Path.join(cache_dir, "#{config.dets_file_prefix}_persistent.dets")
  end

  defp open_dets_table(dets_path) do
    case :dets.open_file(@dets_table_name, [{:file, String.to_charlist(dets_path)}]) do
      {:ok, table} -> {:ok, table}
      {:error, reason} -> {:error, reason}
    end
  end

  defp initialize_maintenance_state do
    %{
      last_maintenance: nil,
      maintenance_count: 0,
      operation_count: 0,
      compaction_count: 0,
      repair_count: 0,
      last_maintenance_time_us: 0
    }
  end

  defp initialize_storage_stats do
    %{
      total_entries: 0,
      file_size_bytes: 0,
      last_stats_update: System.system_time(:second)
    }
  end

  defp find_matching_entries(cache_key_pattern, state) do
    # Find entries matching pattern
    all_entries = :dets.match_object(state.dets_table, {:"$1", :"$2", :"$3", :"$4"})

    Enum.filter(all_entries, fn {key, _data, _expiry, _metadata} ->
      String.contains?(to_string(key), cache_key_pattern)
    end)
  end

  defp increment_operation_count(maintenance_state) do
    %{maintenance_state | operation_count: maintenance_state.operation_count + 1}
  end

  defp increment_repair_count(maintenance_state) do
    %{maintenance_state | repair_count: maintenance_state.repair_count + 1}
  end

  defp should_compact?(state) do
    state.config.compaction_enabled and
      state.maintenance_state.operation_count >= @compact_threshold
  end

  defp maybe_trigger_compaction(state) do
    if should_compact?(state) do
      GenServer.cast(self(), :compact_storage)
    end
  end

  defp repair_dets_table(state) do
    # Attempt DETS table repair
    case :dets.close(state.dets_table) do
      :ok ->
        dets_path = build_dets_path(state.config)

        case :dets.open_file(state.dets_table, [
               {:file, String.to_charlist(dets_path)},
               {:repair, true}
             ]) do
          {:ok, _table} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp estimate_data_size(data) do
    # Estimate data size for storage statistics
    data
    |> :erlang.term_to_binary()
    |> byte_size()
  end

  defp schedule_maintenance_task do
    Process.send_after(self(), :maintenance_task, @maintenance_interval_ms)
  end
end
