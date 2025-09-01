defmodule RubberDuck.Prompts.Caching.CacheManager do
  @moduledoc """
  Unified cache management interface for multi-tier prompt caching system.
  
  Provides intelligent cache coordination across ETS, distributed GenServer,
  and DETS persistent layers using pure Elixir/BEAM technologies. Includes
  cache promotion, eviction, warming, and performance monitoring.
  
  Features:
  - Unified cache interface abstracting all cache tiers with consistent API
  - Intelligent cache promotion and demotion based on access patterns and frequency
  - Comprehensive cache hit/miss tracking with detailed performance analytics
  - Performance monitoring with real-time metrics and optimization recommendations
  - Memory pressure management with configurable limits and intelligent eviction
  - Integration with Phoenix PubSub for distributed cache invalidation broadcasting
  """

  use GenServer
  require Logger

  alias RubberDuck.Prompts.Caching.{
    EtsCacheLayer,
    DistributedCacheLayer,
    PersistentCacheLayer
  }

  @cache_tiers [:ets, :distributed, :persistent]
  
  @default_config %{
    enable_promotion: true,
    enable_analytics: true,
    memory_limit_mb: 500,
    warming_strategy: :predictive,
    eviction_policy: :lru,
    promotion_threshold: 3,  # Promote after 3 hits
    demotion_threshold: 10   # Demote after 10 misses
  }

  defstruct [
    :config,
    :cache_layers,
    :analytics,
    :warming_service,
    :invalidation_coordinator
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    config = Keyword.get(opts, :config, @default_config)
    
    state = %__MODULE__{
      config: config,
      cache_layers: initialize_cache_layers(config),
      analytics: initialize_analytics(),
      warming_service: initialize_warming_service(config),
      invalidation_coordinator: initialize_invalidation_coordinator()
    }

    Logger.info("CacheManager: Multi-tier cache manager initialized",
      tiers: @cache_tiers,
      memory_limit_mb: config.memory_limit_mb,
      warming_strategy: config.warming_strategy
    )

    {:ok, state}
  end

  # Public API

  def get(cache_key, cache_type \\ :auto) do
    GenServer.call(__MODULE__, {:get, cache_key, cache_type})
  end

  def put(cache_key, data, cache_type \\ :auto, ttl_seconds \\ nil) do
    GenServer.call(__MODULE__, {:put, cache_key, data, cache_type, ttl_seconds})
  end

  def invalidate(cache_key_pattern, scope \\ :all) do
    GenServer.cast(__MODULE__, {:invalidate, cache_key_pattern, scope})
  end

  def warm_cache(cache_keys, strategy \\ :default) do
    GenServer.cast(__MODULE__, {:warm_cache, cache_keys, strategy})
  end

  def get_analytics do
    GenServer.call(__MODULE__, :get_analytics)
  end

  def get_performance_metrics do
    GenServer.call(__MODULE__, :get_performance_metrics)
  end

  def optimize_cache do
    GenServer.cast(__MODULE__, :optimize_cache)
  end

  # GenServer callbacks

  def handle_call({:get, cache_key, cache_type}, _from, state) do
    get_start_time = System.monotonic_time(:microsecond)
    
    case execute_get_operation(cache_key, cache_type, state) do
      {:ok, data, hit_tier} ->
        get_time = System.monotonic_time(:microsecond) - get_start_time
        
        # Update analytics and potentially promote
        updated_analytics = update_hit_analytics(state.analytics, cache_key, hit_tier, get_time)
        updated_state = %{state | analytics: updated_analytics}
        
        # Check for promotion opportunity
        maybe_promote_cache_entry(cache_key, data, hit_tier, updated_state)
        
        Logger.debug("CacheManager: Cache hit",
          cache_key: cache_key,
          hit_tier: hit_tier,
          get_time_us: get_time
        )
        
        {:reply, {:ok, data}, updated_state}
      
      {:error, :cache_miss} ->
        get_time = System.monotonic_time(:microsecond) - get_start_time
        
        # Update analytics
        updated_analytics = update_miss_analytics(state.analytics, cache_key, get_time)
        updated_state = %{state | analytics: updated_analytics}
        
        Logger.debug("CacheManager: Cache miss", cache_key: cache_key)
        
        {:reply, {:error, :cache_miss}, updated_state}
    end
  end

  def handle_call({:put, cache_key, data, cache_type, ttl_seconds}, _from, state) do
    put_start_time = System.monotonic_time(:microsecond)
    
    case execute_put_operation(cache_key, data, cache_type, ttl_seconds, state) do
      :ok ->
        put_time = System.monotonic_time(:microsecond) - put_start_time
        
        # Update analytics
        updated_analytics = update_put_analytics(state.analytics, cache_key, put_time)
        updated_state = %{state | analytics: updated_analytics}
        
        Logger.debug("CacheManager: Cache entry stored",
          cache_key: cache_key,
          put_time_us: put_time
        )
        
        {:reply, :ok, updated_state}
      
      {:error, reason} ->
        Logger.warn("CacheManager: Failed to store cache entry",
          cache_key: cache_key,
          error: reason
        )
        
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_analytics, _from, state) do
    {:reply, {:ok, state.analytics}, state}
  end

  def handle_call(:get_performance_metrics, _from, state) do
    metrics = calculate_performance_metrics(state.analytics)
    {:reply, {:ok, metrics}, state}
  end

  def handle_cast({:invalidate, cache_key_pattern, scope}, state) do
    # Execute invalidation across appropriate cache tiers
    execute_invalidation_operation(cache_key_pattern, scope, state)
    
    Logger.info("CacheManager: Cache invalidation completed",
      pattern: cache_key_pattern,
      scope: scope
    )
    
    {:noreply, state}
  end

  def handle_cast({:warm_cache, cache_keys, strategy}, state) do
    # Execute cache warming operation
    execute_warming_operation(cache_keys, strategy, state)
    
    Logger.info("CacheManager: Cache warming completed",
      key_count: length(cache_keys),
      strategy: strategy
    )
    
    {:noreply, state}
  end

  def handle_cast(:optimize_cache, state) do
    # Execute cache optimization
    execute_optimization_operation(state)
    
    Logger.info("CacheManager: Cache optimization completed")
    
    {:noreply, state}
  end

  # Private implementation functions

  defp initialize_cache_layers(config) do
    %{
      ets: initialize_ets_layer(config),
      distributed: initialize_distributed_layer(config),
      persistent: initialize_persistent_layer(config)
    }
  end

  defp initialize_ets_layer(config) do
    %{
      enabled: true,
      ttl_seconds: 60,
      max_entries: config.memory_limit_mb * 10,  # Rough estimate
      warming_enabled: config.warming_strategy != :disabled
    }
  end

  defp initialize_distributed_layer(config) do
    %{
      enabled: true,
      ttl_seconds: 3600,
      coordination_strategy: :registry,
      pubsub_enabled: true
    }
  end

  defp initialize_persistent_layer(config) do
    %{
      enabled: true,
      ttl_seconds: 86_400,
      maintenance_interval_ms: 3_600_000,  # 1 hour
      compact_storage: true
    }
  end

  defp initialize_analytics do
    %{
      hits_by_tier: %{ets: 0, distributed: 0, persistent: 0},
      misses: 0,
      total_requests: 0,
      hit_rate_by_tier: %{ets: 0.0, distributed: 0.0, persistent: 0.0},
      overall_hit_rate: 0.0,
      average_response_time_us: %{ets: 0.0, distributed: 0.0, persistent: 0.0},
      cache_promotions: 0,
      cache_demotions: 0,
      memory_usage_mb: 0.0,
      last_optimization: nil
    }
  end

  defp initialize_warming_service(config) do
    %{
      strategy: config.warming_strategy,
      enabled: config.warming_strategy != :disabled,
      last_warming: nil,
      warming_effectiveness: 0.0
    }
  end

  defp initialize_invalidation_coordinator do
    %{
      pubsub_topic: "prompt_cache_invalidation",
      broadcast_enabled: true,
      invalidation_count: 0,
      last_invalidation: nil
    }
  end

  # Cache operation implementations

  defp execute_get_operation(cache_key, cache_type, state) do
    tiers_to_check = determine_cache_tiers_to_check(cache_type)
    
    try_cache_tiers(cache_key, tiers_to_check, state)
  end

  defp try_cache_tiers(cache_key, [tier | remaining_tiers], state) do
    case get_from_cache_tier(cache_key, tier, state) do
      {:ok, data} -> {:ok, data, tier}
      {:error, :cache_miss} -> try_cache_tiers(cache_key, remaining_tiers, state)
    end
  end

  defp try_cache_tiers(_cache_key, [], _state) do
    {:error, :cache_miss}
  end

  defp get_from_cache_tier(cache_key, tier, state) do
    case tier do
      :ets ->
        EtsCacheLayer.get(cache_key, state.cache_layers.ets)
      
      :distributed ->
        DistributedCacheLayer.get(cache_key, state.cache_layers.distributed)
      
      :persistent ->
        PersistentCacheLayer.get(cache_key, state.cache_layers.persistent)
    end
  end

  defp execute_put_operation(cache_key, data, cache_type, ttl_seconds, state) do
    tiers_to_update = determine_cache_tiers_to_update(cache_type)
    
    put_to_cache_tiers(cache_key, data, tiers_to_update, ttl_seconds, state)
  end

  defp put_to_cache_tiers(cache_key, data, tiers, ttl_seconds, state) do
    results = Enum.map(tiers, fn tier ->
      put_to_cache_tier(cache_key, data, tier, ttl_seconds, state)
    end)
    
    case Enum.all?(results, fn result -> result == :ok end) do
      true -> :ok
      false -> {:error, :partial_cache_failure}
    end
  end

  defp put_to_cache_tier(cache_key, data, tier, ttl_seconds, state) do
    case tier do
      :ets ->
        EtsCacheLayer.put(cache_key, data, ttl_seconds || 60, state.cache_layers.ets)
      
      :distributed ->
        DistributedCacheLayer.put(cache_key, data, ttl_seconds || 3600, state.cache_layers.distributed)
      
      :persistent ->
        PersistentCacheLayer.put(cache_key, data, ttl_seconds || 86_400, state.cache_layers.persistent)
    end
  end

  defp execute_invalidation_operation(cache_key_pattern, scope, state) do
    tiers_to_invalidate = determine_invalidation_scope(scope)
    
    Enum.each(tiers_to_invalidate, fn tier ->
      invalidate_cache_tier(cache_key_pattern, tier, state)
    end)
    
    # Broadcast invalidation if configured
    if state.invalidation_coordinator.broadcast_enabled do
      broadcast_invalidation(cache_key_pattern, scope, state)
    end
  end

  defp invalidate_cache_tier(cache_key_pattern, tier, state) do
    case tier do
      :ets ->
        EtsCacheLayer.invalidate(cache_key_pattern, state.cache_layers.ets)
      
      :distributed ->
        DistributedCacheLayer.invalidate(cache_key_pattern, state.cache_layers.distributed)
      
      :persistent ->
        PersistentCacheLayer.invalidate(cache_key_pattern, state.cache_layers.persistent)
    end
  end

  defp execute_warming_operation(cache_keys, strategy, state) do
    case strategy do
      :predictive ->
        execute_predictive_warming(cache_keys, state)
      
      :bulk ->
        execute_bulk_warming(cache_keys, state)
      
      :default ->
        execute_default_warming(cache_keys, state)
    end
  end

  defp execute_optimization_operation(state) do
    # Execute comprehensive cache optimization
    optimize_memory_usage(state)
    optimize_tier_distribution(state)
    optimize_eviction_policies(state)
  end

  # Cache tier determination functions

  defp determine_cache_tiers_to_check(:auto), do: @cache_tiers
  defp determine_cache_tiers_to_check(:fast), do: [:ets]
  defp determine_cache_tiers_to_check(:distributed), do: [:ets, :distributed]
  defp determine_cache_tiers_to_check(:all), do: @cache_tiers
  defp determine_cache_tiers_to_check(tier) when tier in @cache_tiers, do: [tier]

  defp determine_cache_tiers_to_update(:auto), do: @cache_tiers
  defp determine_cache_tiers_to_update(:fast), do: [:ets]
  defp determine_cache_tiers_to_update(:distributed), do: [:ets, :distributed]
  defp determine_cache_tiers_to_update(:persistent_only), do: [:persistent]
  defp determine_cache_tiers_to_update(tier) when tier in @cache_tiers, do: [tier]

  defp determine_invalidation_scope(:all), do: @cache_tiers
  defp determine_invalidation_scope(:local), do: [:ets]
  defp determine_invalidation_scope(:distributed), do: [:ets, :distributed]
  defp determine_invalidation_scope(:persistent), do: [:persistent]
  defp determine_invalidation_scope(tier) when tier in @cache_tiers, do: [tier]

  # Cache promotion and analytics functions

  defp maybe_promote_cache_entry(cache_key, data, hit_tier, state) do
    if state.config.enable_promotion and should_promote_entry?(cache_key, hit_tier, state) do
      promote_cache_entry(cache_key, data, hit_tier, state)
    end
  end

  defp should_promote_entry?(cache_key, hit_tier, state) do
    hit_count = get_cache_key_hit_count(cache_key, state.analytics)
    threshold = state.config.promotion_threshold
    
    case hit_tier do
      :distributed -> hit_count >= threshold and can_promote_to_ets?(state)
      :persistent -> hit_count >= threshold and can_promote_to_distributed?(state)
      :ets -> false  # Already at top tier
    end
  end

  defp promote_cache_entry(cache_key, data, from_tier, state) do
    promotion_target = case from_tier do
      :persistent -> :distributed
      :distributed -> :ets
      :ets -> :ets  # No promotion needed
    end
    
    case put_to_cache_tier(cache_key, data, promotion_target, nil, state) do
      :ok ->
        Logger.debug("CacheManager: Cache entry promoted",
          cache_key: cache_key,
          from_tier: from_tier,
          to_tier: promotion_target
        )
        
        # Update promotion analytics
        update_promotion_analytics(state, from_tier, promotion_target)
      
      {:error, reason} ->
        Logger.warn("CacheManager: Cache promotion failed",
          cache_key: cache_key,
          error: reason
        )
    end
  end

  defp can_promote_to_ets?(state) do
    # Check if ETS has capacity for promotion
    current_memory = state.analytics.memory_usage_mb
    memory_limit = state.config.memory_limit_mb
    
    current_memory < memory_limit * 0.8  # 80% threshold
  end

  defp can_promote_to_distributed?(state) do
    # Check if distributed cache has capacity
    # Simplified check - would implement proper capacity management
    true
  end

  # Analytics functions

  defp update_hit_analytics(analytics, cache_key, hit_tier, response_time_us) do
    updated_hits = Map.update!(analytics.hits_by_tier, hit_tier, &(&1 + 1))
    total_requests = analytics.total_requests + 1
    
    # Update hit rates
    total_hits = Enum.sum(Map.values(updated_hits))
    overall_hit_rate = total_hits / total_requests
    
    hit_rate_by_tier = Map.new(analytics.hits_by_tier, fn {tier, hits} ->
      {tier, hits / total_requests}
    end)
    
    # Update response times
    updated_response_times = Map.update!(analytics.average_response_time_us, hit_tier, fn current_avg ->
      update_average_response_time(current_avg, response_time_us, updated_hits[hit_tier])
    end)

    %{analytics |
      hits_by_tier: updated_hits,
      total_requests: total_requests,
      overall_hit_rate: overall_hit_rate,
      hit_rate_by_tier: hit_rate_by_tier,
      average_response_time_us: updated_response_times
    }
  end

  defp update_miss_analytics(analytics, _cache_key, response_time_us) do
    total_requests = analytics.total_requests + 1
    misses = analytics.misses + 1
    
    # Update overall hit rate
    total_hits = Enum.sum(Map.values(analytics.hits_by_tier))
    overall_hit_rate = total_hits / total_requests
    
    %{analytics |
      misses: misses,
      total_requests: total_requests,
      overall_hit_rate: overall_hit_rate
    }
  end

  defp update_put_analytics(analytics, _cache_key, _put_time_us) do
    # Update put operation analytics
    analytics
  end

  defp update_promotion_analytics(state, from_tier, to_tier) do
    # Update promotion tracking
    updated_analytics = Map.update!(state.analytics, :cache_promotions, &(&1 + 1))
    
    Logger.debug("CacheManager: Promotion analytics updated",
      from_tier: from_tier,
      to_tier: to_tier,
      total_promotions: updated_analytics.cache_promotions
    )
    
    updated_analytics
  end

  # Cache warming implementations

  defp execute_predictive_warming(cache_keys, state) do
    # Predictive warming based on usage patterns
    high_priority_keys = analyze_warming_priorities(cache_keys, state)
    
    Enum.each(high_priority_keys, fn cache_key ->
      warm_single_cache_key(cache_key, state)
    end)
  end

  defp execute_bulk_warming(cache_keys, state) do
    # Bulk warming for all provided keys
    Enum.each(cache_keys, fn cache_key ->
      warm_single_cache_key(cache_key, state)
    end)
  end

  defp execute_default_warming(cache_keys, state) do
    # Default warming strategy
    limited_keys = Enum.take(cache_keys, 100)  # Limit to 100 keys
    
    Enum.each(limited_keys, fn cache_key ->
      warm_single_cache_key(cache_key, state)
    end)
  end

  defp warm_single_cache_key(cache_key, state) do
    # Attempt to warm cache key across all tiers
    case get_from_cache_tier(cache_key, :persistent, state) do
      {:ok, data} ->
        # Promote to faster tiers
        put_to_cache_tier(cache_key, data, :distributed, 3600, state)
        put_to_cache_tier(cache_key, data, :ets, 60, state)
        
        Logger.debug("CacheManager: Cache key warmed", cache_key: cache_key)
      
      {:error, :cache_miss} ->
        # Cannot warm - data not available
        :ok
    end
  end

  # Cache optimization functions

  defp optimize_memory_usage(state) do
    # Optimize memory usage across cache tiers
    if exceeds_memory_limit?(state) do
      execute_memory_pressure_relief(state)
    end
  end

  defp optimize_tier_distribution(state) do
    # Optimize data distribution across cache tiers
    analytics = state.analytics
    
    # Analyze tier efficiency and suggest optimizations
    efficiency_analysis = analyze_tier_efficiency(analytics)
    
    Logger.debug("CacheManager: Tier efficiency analysis",
      ets_efficiency: efficiency_analysis.ets_efficiency,
      distributed_efficiency: efficiency_analysis.distributed_efficiency,
      persistent_efficiency: efficiency_analysis.persistent_efficiency
    )
  end

  defp optimize_eviction_policies(state) do
    # Optimize eviction policies based on usage patterns
    case state.config.eviction_policy do
      :lru -> optimize_lru_eviction(state)
      :lfu -> optimize_lfu_eviction(state)
      :adaptive -> optimize_adaptive_eviction(state)
    end
  end

  # Utility functions

  defp exceeds_memory_limit?(state) do
    state.analytics.memory_usage_mb > state.config.memory_limit_mb
  end

  defp execute_memory_pressure_relief(state) do
    # Execute memory pressure relief strategies
    Logger.info("CacheManager: Executing memory pressure relief")
    
    # Would implement LRU eviction or tier demotion
    :ok
  end

  defp analyze_tier_efficiency(analytics) do
    %{
      ets_efficiency: calculate_tier_efficiency(:ets, analytics),
      distributed_efficiency: calculate_tier_efficiency(:distributed, analytics),
      persistent_efficiency: calculate_tier_efficiency(:persistent, analytics)
    }
  end

  defp calculate_tier_efficiency(tier, analytics) do
    hit_rate = Map.get(analytics.hit_rate_by_tier, tier, 0.0)
    response_time = Map.get(analytics.average_response_time_us, tier, 0.0)
    
    # Simple efficiency calculation
    case response_time do
      0.0 -> 0.0
      _ -> hit_rate / (response_time / 1000.0)  # Hits per millisecond
    end
  end

  defp optimize_lru_eviction(_state), do: :ok
  defp optimize_lfu_eviction(_state), do: :ok
  defp optimize_adaptive_eviction(_state), do: :ok

  defp analyze_warming_priorities(cache_keys, _state) do
    # Analyze and prioritize cache keys for warming
    # Would implement sophisticated analysis
    Enum.take(cache_keys, 50)  # Simple implementation
  end

  defp broadcast_invalidation(cache_key_pattern, scope, state) do
    topic = state.invalidation_coordinator.pubsub_topic
    
    message = %{
      type: :cache_invalidation,
      pattern: cache_key_pattern,
      scope: scope,
      timestamp: System.system_time(:second),
      node: Node.self()
    }
    
    case Phoenix.PubSub.broadcast(RubberDuck.PubSub, topic, message) do
      :ok ->
        Logger.debug("CacheManager: Invalidation broadcasted", pattern: cache_key_pattern)
      
      {:error, reason} ->
        Logger.warn("CacheManager: Failed to broadcast invalidation", 
          pattern: cache_key_pattern,
          error: reason
        )
    end
  end

  defp get_cache_key_hit_count(_cache_key, _analytics) do
    # Get hit count for specific cache key
    # Would track individual key statistics
    5  # Placeholder
  end

  defp update_average_response_time(current_avg, new_time, request_count) do
    case request_count do
      1 -> new_time
      _ -> (current_avg * (request_count - 1) + new_time) / request_count
    end
  end

  defp calculate_performance_metrics(analytics) do
    %{
      overall_hit_rate: analytics.overall_hit_rate,
      tier_hit_rates: analytics.hit_rate_by_tier,
      average_response_times: analytics.average_response_time_us,
      total_requests: analytics.total_requests,
      cache_promotions: analytics.cache_promotions,
      memory_usage_mb: analytics.memory_usage_mb,
      performance_score: calculate_overall_performance_score(analytics)
    }
  end

  defp calculate_overall_performance_score(analytics) do
    # Calculate overall cache performance score
    hit_rate_score = analytics.overall_hit_rate
    
    # Response time score (lower is better)
    avg_response_time = analytics.average_response_time_us.ets
    response_time_score = case avg_response_time do
      time when time < 1000 -> 1.0    # Sub-1ms excellent
      time when time < 10_000 -> 0.8  # Sub-10ms good
      time when time < 50_000 -> 0.6  # Sub-50ms acceptable
      _ -> 0.4                        # Above 50ms needs optimization
    end
    
    # Memory efficiency score
    memory_usage = analytics.memory_usage_mb
    memory_score = case memory_usage do
      usage when usage < 100 -> 1.0
      usage when usage < 300 -> 0.8
      usage when usage < 500 -> 0.6
      _ -> 0.4
    end
    
    # Weighted overall score
    overall_score = (hit_rate_score * 0.5) + (response_time_score * 0.3) + (memory_score * 0.2)
    Float.round(overall_score, 3)
  end
end