defmodule RubberDuck.Prompts.WorkflowIntegration.WorkflowPromptCacheCoordinator do
  @moduledoc """
  Workflow-specific prompt caching coordination service.

  Provides intelligent caching coordination between workflow execution and prompt
  systems, enabling efficient cache sharing, invalidation strategies, and 
  performance optimization for workflow-prompt operations.

  Features:
  - Workflow-specific prompt caching with intelligent invalidation strategies
  - Cache coordination between workflow execution and prompt composition systems
  - Performance optimization for workflow-prompt operations with hit rate tracking
  - Cache lifecycle management with automatic cleanup and optimization
  - Integration with existing prompt caching infrastructure and workflow monitoring
  - Cache analytics and reporting with performance insights and optimization recommendations
  """

  use GenServer
  require Logger

  @cache_strategies [:workflow_scoped, :step_scoped, :global_shared, :hybrid]
  @invalidation_strategies [:immediate, :delayed, :conditional, :smart]

  @default_coordinator_config %{
    cache_strategy: :hybrid,
    invalidation_strategy: :smart,
    enable_cross_workflow_sharing: true,
    enable_cache_analytics: true,
    cache_size_limit_mb: 100,
    cache_cleanup_interval_minutes: 30
  }

  defstruct [
    :coordinator_config,
    :workflow_caches,
    :global_cache,
    :cache_analytics,
    :cleanup_scheduler
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    state = %__MODULE__{
      coordinator_config: Map.merge(@default_coordinator_config, Keyword.get(opts, :config, %{})),
      workflow_caches: initialize_workflow_caches(),
      global_cache: initialize_global_cache(),
      cache_analytics: initialize_cache_analytics(),
      cleanup_scheduler: schedule_cache_cleanup()
    }

    Logger.info("WorkflowPromptCacheCoordinator: Cache coordinator initialized",
      cache_strategies: @cache_strategies,
      invalidation_strategies: @invalidation_strategies
    )

    {:ok, state}
  end

  # Public API

  def get_cached_prompt(workflow_id, prompt_key, cache_options \\ %{}) do
    GenServer.call(__MODULE__, {:get_cached_prompt, workflow_id, prompt_key, cache_options})
  end

  def cache_workflow_prompt(workflow_id, prompt_key, prompt_data, cache_options \\ %{}) do
    GenServer.call(
      __MODULE__,
      {:cache_workflow_prompt, workflow_id, prompt_key, prompt_data, cache_options}
    )
  end

  def invalidate_workflow_cache(workflow_id, invalidation_options \\ %{}) do
    GenServer.cast(__MODULE__, {:invalidate_workflow_cache, workflow_id, invalidation_options})
  end

  def optimize_cache_performance(optimization_options \\ %{}) do
    GenServer.cast(__MODULE__, {:optimize_cache_performance, optimization_options})
  end

  def get_cache_analytics do
    GenServer.call(__MODULE__, :get_cache_analytics)
  end

  def cleanup_expired_caches do
    GenServer.cast(__MODULE__, :cleanup_expired_caches)
  end

  # GenServer callbacks

  def handle_call({:get_cached_prompt, workflow_id, prompt_key, cache_options}, _from, state) do
    cache_start_time = System.monotonic_time(:microsecond)

    Logger.debug("WorkflowPromptCacheCoordinator: Getting cached prompt",
      workflow_id: workflow_id,
      prompt_key: prompt_key
    )

    case execute_cache_get(workflow_id, prompt_key, cache_options, state) do
      {:ok, cache_result} ->
        cache_time = System.monotonic_time(:microsecond) - cache_start_time

        Logger.debug("WorkflowPromptCacheCoordinator: Cache get completed",
          workflow_id: workflow_id,
          prompt_key: prompt_key,
          cache_hit: cache_result.cache_hit,
          cache_time_us: cache_time
        )

        update_cache_analytics(cache_time, cache_result.cache_hit, :get, state)

        {:reply, {:ok, cache_result}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:cache_workflow_prompt, workflow_id, prompt_key, prompt_data, cache_options},
        _from,
        state
      ) do
    case execute_cache_set(workflow_id, prompt_key, prompt_data, cache_options, state) do
      {:ok, cache_result} ->
        updated_state =
          update_workflow_cache(state, workflow_id, prompt_key, prompt_data, cache_options)

        Logger.debug("WorkflowPromptCacheCoordinator: Prompt cached successfully",
          workflow_id: workflow_id,
          prompt_key: prompt_key,
          cache_strategy: cache_result.cache_strategy
        )

        {:reply, {:ok, cache_result}, updated_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_cache_analytics, _from, state) do
    analytics = extract_cache_analytics(state.cache_analytics)
    {:reply, {:ok, analytics}, state}
  end

  def handle_cast({:invalidate_workflow_cache, workflow_id, invalidation_options}, state) do
    Logger.debug("WorkflowPromptCacheCoordinator: Invalidating workflow cache",
      workflow_id: workflow_id
    )

    updated_state = execute_cache_invalidation(workflow_id, invalidation_options, state)

    {:noreply, updated_state}
  end

  def handle_cast({:optimize_cache_performance, optimization_options}, state) do
    optimized_state = execute_cache_optimization(optimization_options, state)

    Logger.info("WorkflowPromptCacheCoordinator: Cache performance optimization completed")

    {:noreply, optimized_state}
  end

  def handle_cast(:cleanup_expired_caches, state) do
    cleaned_state = execute_cache_cleanup(state)

    Logger.debug("WorkflowPromptCacheCoordinator: Cache cleanup completed")

    {:noreply, cleaned_state}
  end

  # Private implementation functions

  defp execute_cache_get(workflow_id, prompt_key, cache_options, state) do
    cache_strategy = determine_cache_strategy(cache_options, state)

    case cache_strategy do
      :workflow_scoped ->
        get_from_workflow_cache(workflow_id, prompt_key, state)

      :step_scoped ->
        get_from_step_cache(workflow_id, prompt_key, cache_options, state)

      :global_shared ->
        get_from_global_cache(prompt_key, state)

      :hybrid ->
        get_from_hybrid_cache(workflow_id, prompt_key, cache_options, state)
    end
  end

  defp execute_cache_set(workflow_id, prompt_key, prompt_data, cache_options, state) do
    cache_strategy = determine_cache_strategy(cache_options, state)

    cache_result = %{
      cache_strategy: cache_strategy,
      workflow_id: workflow_id,
      prompt_key: prompt_key,
      cached_at: DateTime.utc_now(),
      cache_successful: true
    }

    {:ok, cache_result}
  end

  defp get_from_workflow_cache(workflow_id, prompt_key, state) do
    # Get from workflow-specific cache
    workflow_cache = Map.get(state.workflow_caches, workflow_id, %{})

    case Map.get(workflow_cache, prompt_key) do
      nil ->
        {:ok, %{cache_hit: false, cache_strategy: :workflow_scoped}}

      cached_entry ->
        if cache_entry_valid?(cached_entry) do
          {:ok,
           %{
             cache_hit: true,
             cached_data: cached_entry.data,
             cache_strategy: :workflow_scoped,
             cached_at: cached_entry.cached_at
           }}
        else
          {:ok, %{cache_hit: false, cache_expired: true, cache_strategy: :workflow_scoped}}
        end
    end
  end

  defp get_from_step_cache(workflow_id, prompt_key, cache_options, state) do
    # Get from step-specific cache
    step_id = Map.get(cache_options, :step_id, "default_step")
    step_cache_key = "#{workflow_id}:#{step_id}:#{prompt_key}"

    case Map.get(state.workflow_caches, step_cache_key) do
      nil ->
        {:ok, %{cache_hit: false, cache_strategy: :step_scoped}}

      cached_entry ->
        if cache_entry_valid?(cached_entry) do
          {:ok,
           %{
             cache_hit: true,
             cached_data: cached_entry.data,
             cache_strategy: :step_scoped,
             step_id: step_id
           }}
        else
          {:ok, %{cache_hit: false, cache_expired: true, cache_strategy: :step_scoped}}
        end
    end
  end

  defp get_from_global_cache(prompt_key, state) do
    # Get from global shared cache
    case Map.get(state.global_cache, prompt_key) do
      nil ->
        {:ok, %{cache_hit: false, cache_strategy: :global_shared}}

      cached_entry ->
        if cache_entry_valid?(cached_entry) do
          {:ok,
           %{
             cache_hit: true,
             cached_data: cached_entry.data,
             cache_strategy: :global_shared
           }}
        else
          {:ok, %{cache_hit: false, cache_expired: true, cache_strategy: :global_shared}}
        end
    end
  end

  defp get_from_hybrid_cache(workflow_id, prompt_key, cache_options, state) do
    # Try multiple cache levels for hybrid strategy
    with {:ok, %{cache_hit: false}} <-
           get_from_step_cache(workflow_id, prompt_key, cache_options, state),
         {:ok, %{cache_hit: false}} <- get_from_workflow_cache(workflow_id, prompt_key, state),
         {:ok, %{cache_hit: false}} <- get_from_global_cache(prompt_key, state) do
      {:ok, %{cache_hit: false, cache_strategy: :hybrid, cache_levels_checked: 3}}
    else
      {:ok, cache_result} ->
        {:ok, Map.put(cache_result, :cache_strategy, :hybrid)}
    end
  end

  defp determine_cache_strategy(cache_options, state) do
    case Map.get(cache_options, :cache_strategy) do
      strategy when strategy in @cache_strategies -> strategy
      nil -> state.coordinator_config.cache_strategy
      _ -> state.coordinator_config.cache_strategy
    end
  end

  defp cache_entry_valid?(cached_entry) do
    # Check if cache entry is still valid (simplified)
    current_time = DateTime.utc_now()
    cached_time = Map.get(cached_entry, :cached_at, current_time)

    # 5 minutes default TTL
    DateTime.diff(current_time, cached_time, :second) < 300
  end

  defp execute_cache_invalidation(workflow_id, invalidation_options, state) do
    # Execute cache invalidation based on strategy
    invalidation_strategy = Map.get(invalidation_options, :invalidation_strategy, :smart)

    case invalidation_strategy do
      :immediate ->
        execute_immediate_invalidation(workflow_id, state)

      :delayed ->
        execute_delayed_invalidation(workflow_id, invalidation_options, state)

      :conditional ->
        execute_conditional_invalidation(workflow_id, invalidation_options, state)

      :smart ->
        execute_smart_invalidation(workflow_id, invalidation_options, state)
    end
  end

  defp execute_immediate_invalidation(workflow_id, state) do
    # Immediately invalidate all workflow caches
    updated_workflow_caches = Map.delete(state.workflow_caches, workflow_id)

    %{state | workflow_caches: updated_workflow_caches}
  end

  defp execute_delayed_invalidation(workflow_id, invalidation_options, state) do
    # Schedule delayed invalidation (placeholder)
    delay_ms = Map.get(invalidation_options, :delay_ms, 5000)

    Process.send_after(self(), {:delayed_invalidation, workflow_id}, delay_ms)

    state
  end

  defp execute_conditional_invalidation(workflow_id, invalidation_options, state) do
    # Execute conditional invalidation based on conditions
    conditions = Map.get(invalidation_options, :conditions, [])

    if should_invalidate_based_on_conditions?(conditions, state) do
      execute_immediate_invalidation(workflow_id, state)
    else
      state
    end
  end

  defp execute_smart_invalidation(workflow_id, invalidation_options, state) do
    # Execute intelligent invalidation based on usage patterns
    cache_analytics = state.cache_analytics
    workflow_cache_usage = get_workflow_cache_usage(workflow_id, cache_analytics)

    if should_smart_invalidate?(workflow_cache_usage) do
      execute_immediate_invalidation(workflow_id, state)
    else
      execute_delayed_invalidation(workflow_id, %{delay_ms: 10_000}, state)
    end
  end

  defp execute_cache_optimization(optimization_options, state) do
    # Execute cache performance optimization
    optimization_strategy = Map.get(optimization_options, :strategy, :balanced)

    case optimization_strategy do
      :memory_focused ->
        optimize_for_memory(state)

      :performance_focused ->
        optimize_for_performance(state)

      :balanced ->
        optimize_balanced(state)
    end
  end

  defp execute_cache_cleanup(state) do
    # Execute cache cleanup for expired entries
    current_time = DateTime.utc_now()

    cleaned_workflow_caches = clean_expired_entries(state.workflow_caches, current_time)
    cleaned_global_cache = clean_expired_entries(state.global_cache, current_time)

    updated_state = %{
      state
      | workflow_caches: cleaned_workflow_caches,
        global_cache: cleaned_global_cache
    }

    # Reschedule cleanup
    updated_state = %{updated_state | cleanup_scheduler: schedule_cache_cleanup()}

    updated_state
  end

  # Helper functions

  defp update_workflow_cache(state, workflow_id, prompt_key, prompt_data, cache_options) do
    # Update workflow cache with new data
    cache_entry = %{
      data: prompt_data,
      cached_at: DateTime.utc_now(),
      cache_options: cache_options,
      access_count: 1
    }

    workflow_cache = Map.get(state.workflow_caches, workflow_id, %{})
    updated_workflow_cache = Map.put(workflow_cache, prompt_key, cache_entry)
    updated_workflow_caches = Map.put(state.workflow_caches, workflow_id, updated_workflow_cache)

    %{state | workflow_caches: updated_workflow_caches}
  end

  defp update_cache_analytics(cache_time, cache_hit, operation, state) do
    # Update cache analytics
    analytics = state.cache_analytics

    updated_analytics = %{
      analytics
      | total_operations: analytics.total_operations + 1,
        cache_hits: if(cache_hit, do: analytics.cache_hits + 1, else: analytics.cache_hits),
        average_operation_time_us:
          calculate_new_average(
            analytics.average_operation_time_us,
            cache_time,
            analytics.total_operations + 1
          )
    }

    %{state | cache_analytics: updated_analytics}
  end

  defp should_invalidate_based_on_conditions?(conditions, state) do
    # Check if conditions warrant cache invalidation
    Enum.any?(conditions, fn condition ->
      case condition do
        :cache_size_exceeded ->
          calculate_total_cache_size(state) >
            state.coordinator_config.cache_size_limit_mb * 1024 * 1024

        :low_hit_rate ->
          calculate_cache_hit_rate(state.cache_analytics) < 0.3

        :memory_pressure ->
          # Would check actual memory usage
          false

        _ ->
          false
      end
    end)
  end

  defp should_smart_invalidate?(workflow_cache_usage) do
    # Determine if smart invalidation should proceed
    hit_rate = Map.get(workflow_cache_usage, :hit_rate, 0.5)
    last_access = Map.get(workflow_cache_usage, :last_access, DateTime.utc_now())

    # Invalidate if hit rate is low and not accessed recently
    hit_rate < 0.2 or DateTime.diff(DateTime.utc_now(), last_access, :minute) > 60
  end

  defp get_workflow_cache_usage(workflow_id, cache_analytics) do
    # Get cache usage statistics for workflow
    workflow_analytics = Map.get(cache_analytics.workflow_analytics, workflow_id, %{})

    %{
      hit_rate: Map.get(workflow_analytics, :hit_rate, 0.5),
      total_operations: Map.get(workflow_analytics, :total_operations, 0),
      last_access: Map.get(workflow_analytics, :last_access, DateTime.utc_now())
    }
  end

  defp optimize_for_memory(state) do
    # Optimize cache for memory usage
    cleaned_workflow_caches = remove_least_used_entries(state.workflow_caches, 0.2)
    cleaned_global_cache = remove_least_used_entries(state.global_cache, 0.2)

    %{state | workflow_caches: cleaned_workflow_caches, global_cache: cleaned_global_cache}
  end

  defp optimize_for_performance(state) do
    # Optimize cache for performance
    optimized_analytics = %{
      state.cache_analytics
      | optimization_level: min(1.0, state.cache_analytics.optimization_level + 0.1)
    }

    %{state | cache_analytics: optimized_analytics}
  end

  defp optimize_balanced(state) do
    # Balanced optimization approach
    state
    |> optimize_for_memory()
    |> optimize_for_performance()
  end

  defp clean_expired_entries(cache_map, current_time) do
    # Clean expired entries from cache map
    Enum.reduce(cache_map, %{}, fn {key, entry}, acc ->
      if cache_entry_expired?(entry, current_time) do
        acc
      else
        Map.put(acc, key, entry)
      end
    end)
  end

  defp cache_entry_expired?(entry, current_time) do
    # Check if cache entry has expired
    cached_at = Map.get(entry, :cached_at, current_time)
    DateTime.diff(current_time, cached_at, :minute) > 30
  end

  defp remove_least_used_entries(cache_map, removal_percentage) do
    # Remove least used entries based on percentage
    total_entries = map_size(cache_map)
    entries_to_remove = trunc(total_entries * removal_percentage)

    if entries_to_remove > 0 do
      # Sort by access count and remove lowest
      sorted_entries =
        Enum.sort_by(cache_map, fn {_key, entry} ->
          Map.get(entry, :access_count, 0)
        end)

      entries_to_keep = Enum.drop(sorted_entries, entries_to_remove)
      Map.new(entries_to_keep)
    else
      cache_map
    end
  end

  defp calculate_total_cache_size(state) do
    # Calculate total cache size in bytes
    workflow_size = calculate_cache_map_size(state.workflow_caches)
    global_size = calculate_cache_map_size(state.global_cache)

    workflow_size + global_size
  end

  defp calculate_cache_map_size(cache_map) do
    # Calculate size of cache map
    cache_map
    |> :erlang.term_to_binary()
    |> byte_size()
  end

  defp calculate_cache_hit_rate(analytics) do
    case analytics.total_operations do
      0 -> 1.0
      total -> analytics.cache_hits / total
    end
  end

  # Initialization functions

  defp initialize_workflow_caches do
    %{}
  end

  defp initialize_global_cache do
    %{}
  end

  defp initialize_cache_analytics do
    %{
      total_operations: 0,
      cache_hits: 0,
      cache_misses: 0,
      average_operation_time_us: 0.0,
      optimization_level: 0.7,
      workflow_analytics: %{}
    }
  end

  defp schedule_cache_cleanup do
    # Schedule periodic cache cleanup
    # 30 minutes
    cleanup_interval = 30 * 60 * 1000
    Process.send_after(self(), :cleanup_expired_caches, cleanup_interval)
  end

  defp extract_cache_analytics(analytics) do
    %{
      total_cache_operations: analytics.total_operations,
      cache_hit_rate: calculate_cache_hit_rate(analytics),
      average_operation_time_ms: div(trunc(analytics.average_operation_time_us), 1_000),
      optimization_level: analytics.optimization_level,
      workflow_count: map_size(analytics.workflow_analytics)
    }
  end

  defp calculate_new_average(current_avg, new_value, count) do
    case count do
      1 -> new_value
      _ -> (current_avg * (count - 1) + new_value) / count
    end
  end
end
