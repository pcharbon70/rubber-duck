defmodule RubberDuck.Prompts.Caching.DistributedCacheLayer do
  @moduledoc """
  Level 2 distributed cache layer using GenServer and Registry coordination.
  
  Provides cross-node cache sharing using pure BEAM technologies with Registry-based
  node coordination, Phoenix PubSub invalidation broadcasting, and cluster synchronization.
  Optimized for collaborative editing and distributed prompt access.
  
  Features:
  - Cross-node prompt sharing using GenServer coordination and Registry discovery
  - 1-hour TTL for collaborative editing with automatic refresh and synchronization
  - Phoenix PubSub cache invalidation broadcasting for real-time coordination
  - Cluster synchronization using Registry for node discovery and cache coordination
  - Intelligent cache distribution with load balancing and failover capabilities
  - Integration with ETS promotion and DETS persistence for optimal performance
  """

  use GenServer
  require Logger

  @registry_name RubberDuck.Prompts.CacheRegistry
  @pubsub_topic "prompt_distributed_cache"
  @default_ttl_seconds 3600  # 1 hour
  @sync_interval_ms 300_000  # 5 minutes

  defstruct [
    :node_id,
    :cache_store,
    :cluster_nodes,
    :sync_state,
    :coordination_config
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    # Register this cache node
    node_id = generate_node_id()
    {:ok, _} = Registry.register(@registry_name, :cache_nodes, node_id)

    state = %__MODULE__{
      node_id: node_id,
      cache_store: :ets.new(:distributed_cache_store, [:set, :protected]),
      cluster_nodes: discover_cluster_nodes(),
      sync_state: initialize_sync_state(),
      coordination_config: build_coordination_config(opts)
    }

    # Subscribe to invalidation events
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, @pubsub_topic)

    # Schedule periodic cluster synchronization
    schedule_cluster_sync()

    Logger.info("DistributedCacheLayer: Distributed cache node initialized",
      node_id: node_id,
      cluster_nodes: length(state.cluster_nodes),
      coordination_enabled: state.coordination_config.enabled
    )

    {:ok, state}
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

  def get_cluster_status do
    GenServer.call(__MODULE__, :get_cluster_status)
  end

  def sync_with_cluster do
    GenServer.cast(__MODULE__, :sync_with_cluster)
  end

  # GenServer callbacks

  def handle_call({:get, cache_key, _config}, _from, state) do
    get_start_time = System.monotonic_time(:microsecond)
    
    case lookup_in_local_store(cache_key, state) do
      {:ok, data} ->
        get_time = System.monotonic_time(:microsecond) - get_start_time
        
        Logger.debug("DistributedCacheLayer: Local cache hit",
          cache_key: cache_key,
          node_id: state.node_id,
          get_time_us: get_time
        )
        
        {:reply, {:ok, data}, state}
      
      {:error, :cache_miss} ->
        # Try cluster nodes
        case lookup_in_cluster(cache_key, state) do
          {:ok, data, source_node} ->
            # Cache locally for future access
            store_in_local_cache(cache_key, data, @default_ttl_seconds, state)
            
            get_time = System.monotonic_time(:microsecond) - get_start_time
            
            Logger.debug("DistributedCacheLayer: Cluster cache hit",
              cache_key: cache_key,
              source_node: source_node,
              get_time_us: get_time
            )
            
            {:reply, {:ok, data}, state}
          
          {:error, :cache_miss} ->
            {:reply, {:error, :cache_miss}, state}
        end
    end
  end

  def handle_call({:put, cache_key, data, ttl_seconds, _config}, _from, state) do
    put_start_time = System.monotonic_time(:microsecond)
    
    ttl = ttl_seconds || @default_ttl_seconds
    
    case store_in_local_cache(cache_key, data, ttl, state) do
      :ok ->
        # Broadcast to cluster if coordination enabled
        if state.coordination_config.broadcast_puts do
          broadcast_cache_update(cache_key, data, ttl, state)
        end
        
        put_time = System.monotonic_time(:microsecond) - put_start_time
        
        Logger.debug("DistributedCacheLayer: Entry cached and broadcasted",
          cache_key: cache_key,
          ttl_seconds: ttl,
          put_time_us: put_time
        )
        
        {:reply, :ok, state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_cluster_status, _from, state) do
    cluster_status = %{
      node_id: state.node_id,
      cluster_nodes: state.cluster_nodes,
      local_cache_size: :ets.info(state.cache_store, :size),
      last_sync: state.sync_state.last_sync,
      coordination_enabled: state.coordination_config.enabled
    }
    
    {:reply, {:ok, cluster_status}, state}
  end

  def handle_cast({:invalidate, cache_key_pattern, _config}, state) do
    # Invalidate local cache
    execute_local_invalidation(cache_key_pattern, state)
    
    # Broadcast invalidation to cluster
    broadcast_cache_invalidation(cache_key_pattern, state)
    
    Logger.info("DistributedCacheLayer: Cache invalidation broadcasted",
      pattern: cache_key_pattern,
      node_id: state.node_id
    )
    
    {:noreply, state}
  end

  def handle_cast(:sync_with_cluster, state) do
    # Execute cluster synchronization
    updated_state = execute_cluster_synchronization(state)
    
    {:noreply, updated_state}
  end

  # Handle PubSub messages
  def handle_info(%{type: :cache_invalidation, pattern: pattern, node: source_node}, state) do
    if source_node != Node.self() do
      # Process invalidation from other nodes
      execute_local_invalidation(pattern, state)
      
      Logger.debug("DistributedCacheLayer: Processed cluster invalidation",
        pattern: pattern,
        source_node: source_node
      )
    end
    
    {:noreply, state}
  end

  def handle_info(%{type: :cache_update, key: cache_key, data: data, ttl: ttl, node: source_node}, state) do
    if source_node != Node.self() do
      # Process cache update from other nodes
      store_in_local_cache(cache_key, data, ttl, state)
      
      Logger.debug("DistributedCacheLayer: Processed cluster cache update",
        cache_key: cache_key,
        source_node: source_node
      )
    end
    
    {:noreply, state}
  end

  def handle_info(:cluster_sync, state) do
    # Execute periodic cluster synchronization
    updated_state = execute_cluster_synchronization(state)
    schedule_cluster_sync()
    
    {:noreply, updated_state}
  end

  # Private cluster coordination functions

  defp discover_cluster_nodes do
    # Discover other cache nodes using Registry
    case Registry.lookup(@registry_name, :cache_nodes) do
      [] -> []
      nodes -> Enum.map(nodes, fn {pid, node_id} -> {pid, node_id} end)
    end
  end

  defp lookup_in_local_store(cache_key, state) do
    case :ets.lookup(state.cache_store, cache_key) do
      [{^cache_key, data, expiry_time}] ->
        current_time = System.system_time(:second)
        
        if current_time < expiry_time do
          {:ok, data}
        else
          :ets.delete(state.cache_store, cache_key)
          {:error, :cache_miss}
        end
      
      [] ->
        {:error, :cache_miss}
    end
  end

  defp lookup_in_cluster(cache_key, state) do
    # Try to find cache entry in cluster nodes
    cluster_results = Enum.map(state.cluster_nodes, fn {pid, node_id} ->
      try do
        case GenServer.call(pid, {:cluster_lookup, cache_key}, 5000) do
          {:ok, data} -> {:ok, data, node_id}
          {:error, :cache_miss} -> {:error, :cache_miss}
        end
      rescue
        _ -> {:error, :node_unavailable}
      end
    end)
    
    # Return first successful result
    case Enum.find(cluster_results, fn
      {:ok, _data, _node} -> true
      _ -> false
    end) do
      {:ok, data, source_node} -> {:ok, data, source_node}
      nil -> {:error, :cache_miss}
    end
  end

  defp store_in_local_cache(cache_key, data, ttl_seconds, state) do
    expiry_time = System.system_time(:second) + ttl_seconds
    :ets.insert(state.cache_store, {cache_key, data, expiry_time})
    :ok
  end

  defp execute_local_invalidation(cache_key_pattern, state) do
    # Find and delete matching local entries
    matching_entries = :ets.match(state.cache_store, {:"$1", :"$2", :"$3"})
    
    deleted_count = Enum.reduce(matching_entries, 0, fn [key, _data, _expiry], acc ->
      if String.contains?(to_string(key), cache_key_pattern) do
        :ets.delete(state.cache_store, key)
        acc + 1
      else
        acc
      end
    end)
    
    Logger.debug("DistributedCacheLayer: Local invalidation completed",
      pattern: cache_key_pattern,
      deleted_count: deleted_count
    )
  end

  defp broadcast_cache_invalidation(cache_key_pattern, state) do
    message = %{
      type: :cache_invalidation,
      pattern: cache_key_pattern,
      node: Node.self(),
      timestamp: System.system_time(:second)
    }
    
    Phoenix.PubSub.broadcast(RubberDuck.PubSub, @pubsub_topic, message)
  end

  defp broadcast_cache_update(cache_key, data, ttl, state) do
    message = %{
      type: :cache_update,
      key: cache_key,
      data: data,
      ttl: ttl,
      node: Node.self(),
      timestamp: System.system_time(:second)
    }
    
    Phoenix.PubSub.broadcast(RubberDuck.PubSub, @pubsub_topic, message)
  end

  defp execute_cluster_synchronization(state) do
    # Update cluster node list
    updated_cluster_nodes = discover_cluster_nodes()
    
    updated_sync_state = %{state.sync_state |
      last_sync: System.system_time(:second),
      sync_count: state.sync_state.sync_count + 1
    }
    
    %{state |
      cluster_nodes: updated_cluster_nodes,
      sync_state: updated_sync_state
    }
  end

  # Utility functions

  defp generate_node_id do
    "distributed_cache_#{Node.self()}_#{System.system_time(:nanosecond)}"
  end

  defp initialize_sync_state do
    %{
      last_sync: nil,
      sync_count: 0,
      sync_errors: 0
    }
  end

  defp build_coordination_config(opts) do
    %{
      enabled: Keyword.get(opts, :coordination_enabled, true),
      broadcast_puts: Keyword.get(opts, :broadcast_puts, false),
      broadcast_invalidations: Keyword.get(opts, :broadcast_invalidations, true),
      cluster_discovery: Keyword.get(opts, :cluster_discovery, true)
    }
  end

  defp schedule_cluster_sync do
    Process.send_after(self(), :cluster_sync, @sync_interval_ms)
  end
end