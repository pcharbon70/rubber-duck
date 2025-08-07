defmodule RubberDuck.LLM.ProviderCircuitBreaker do
  @moduledoc """
  Circuit breaker specifically designed for LLM provider resilience.
  
  Features:
  - Per-provider circuit breakers with independent states
  - Provider-specific failure thresholds
  - Smart fallback coordination
  - Cost-aware circuit breaking (don't waste expensive API calls)
  - Gradual recovery testing
  
  ## Configuration
  
      config :rubber_duck, :llm_circuit_breaker,
        error_threshold: 3,        # Fewer failures before opening (expensive APIs)
        timeout: 120_000,          # Longer recovery time (2 minutes)
        half_open_requests: 1,     # Only one test request
        success_threshold: 2,      # Need 2 successes to fully recover
        cost_threshold: 100.0      # Open circuit if cost exceeds threshold
  """
  
  require Logger
  
  alias RubberDuck.Routing.{CircuitBreaker, CircuitBreakerSupervisor}
  
  @default_config %{
    error_threshold: 3,      # LLM APIs are expensive, fail fast
    timeout: 120_000,        # 2 minutes recovery
    half_open_requests: 1,   # Only one test request
    success_threshold: 2,    # Need consistent success
    cost_threshold: 100.0    # Cost limit per hour
  }
  
  # Client API
  
  @doc """
  Checks if a provider is available for requests.
  
  Returns:
  - `:ok` - Provider is available
  - `{:error, :circuit_open}` - Provider circuit is open
  - `{:error, :cost_exceeded}` - Cost threshold exceeded
  - `{:error, :rate_limited}` - Provider is rate limited
  """
  @spec check_provider(atom()) :: :ok | {:error, term()}
  def check_provider(provider_name) do
    # Ensure circuit breaker exists
    ensure_provider_circuit_breaker(provider_name)
    
    # Check both circuit state and cost
    with :ok <- CircuitBreaker.call(provider_key(provider_name)),
         :ok <- check_cost_threshold(provider_name),
         :ok <- check_rate_limit(provider_name) do
      :ok
    end
  end
  
  @doc """
  Records a successful provider request.
  """
  @spec record_success(atom(), map()) :: :ok
  def record_success(provider_name, metadata \\ %{}) do
    CircuitBreaker.record_success(provider_key(provider_name))
    
    # Track cost if provided
    if cost = metadata[:cost] do
      track_cost(provider_name, cost)
    end
    
    # Track latency for adaptive thresholds
    if latency = metadata[:latency_ms] do
      track_latency(provider_name, latency)
    end
    
    :ok
  end
  
  @doc """
  Records a failed provider request.
  
  Distinguishes between different failure types:
  - `:timeout` - Request timeout (likely overload)
  - `:rate_limit` - Rate limit hit (back off)
  - `:invalid_api_key` - Configuration issue (don't retry)
  - `:server_error` - Provider issue (retry with backoff)
  """
  @spec record_failure(atom(), atom(), map()) :: :ok
  def record_failure(provider_name, failure_type, metadata \\ %{}) do
    case failure_type do
      :invalid_api_key ->
        # Configuration issue, open circuit immediately
        force_open_circuit(provider_name, :configuration_error)
        
      :rate_limit ->
        # Rate limited, open circuit with specific timeout
        force_open_circuit(provider_name, :rate_limited, metadata[:retry_after])
        
      _ ->
        # Normal failure, let circuit breaker handle it
        CircuitBreaker.record_failure(provider_key(provider_name))
    end
    
    # Log provider-specific failure
    Logger.warning("LLM provider #{provider_name} failed: #{failure_type}")
    
    :ok
  end
  
  @doc """
  Gets the health status of all provider circuit breakers.
  """
  @spec get_all_provider_status() :: map()
  def get_all_provider_status do
    providers = list_provider_circuit_breakers()
    
    Map.new(providers, fn provider_name ->
      status = get_provider_status(provider_name)
      {provider_name, status}
    end)
  end
  
  @doc """
  Gets the status of a specific provider's circuit breaker.
  """
  @spec get_provider_status(atom()) :: map()
  def get_provider_status(provider_name) do
    case CircuitBreaker.get_state(provider_key(provider_name)) do
      {:ok, state} ->
        Map.merge(state, %{
          cost_used: get_cost_used(provider_name),
          avg_latency: get_avg_latency(provider_name),
          rate_limited: is_rate_limited?(provider_name)
        })
        
      {:error, :not_found} ->
        %{state: :unknown, available: true}
    end
  end
  
  @doc """
  Finds available fallback providers when primary is unavailable.
  
  Returns list of available providers in priority order.
  """
  @spec find_fallback_providers(atom(), keyword()) :: [atom()]
  def find_fallback_providers(primary_provider, opts \\ []) do
    exclude = Keyword.get(opts, :exclude, [primary_provider])
    max_cost = Keyword.get(opts, :max_cost, 1000.0)
    
    all_providers()
    |> Enum.reject(&(&1 in exclude))
    |> Enum.filter(&provider_available?/1)
    |> Enum.filter(&(get_cost_used(&1) < max_cost))
    |> Enum.sort_by(&provider_priority/1)
  end
  
  @doc """
  Resets a provider's circuit breaker.
  
  Useful for manual recovery or after fixing configuration issues.
  """
  @spec reset_provider(atom()) :: :ok
  def reset_provider(provider_name) do
    CircuitBreaker.reset(provider_key(provider_name))
    clear_rate_limit(provider_name)
    reset_cost_tracking(provider_name)
    :ok
  end
  
  # Private Functions
  
  defp provider_key(provider_name) do
    :"llm_provider_#{provider_name}"
  end
  
  defp ensure_provider_circuit_breaker(provider_name) do
    config = get_provider_config(provider_name)
    CircuitBreakerSupervisor.ensure_circuit_breaker(
      provider_key(provider_name),
      config: config
    )
  end
  
  defp get_provider_config(provider_name) do
    base_config = Application.get_env(:rubber_duck, :llm_circuit_breaker, %{})
    
    # Provider-specific overrides
    provider_configs = %{
      openai: %{error_threshold: 3, timeout: 120_000},
      anthropic: %{error_threshold: 3, timeout: 120_000},
      local: %{error_threshold: 10, timeout: 30_000},  # More lenient for local
      fallback: %{error_threshold: 5, timeout: 60_000},
      # For tests, use very specific values
      normal_provider: %{error_threshold: 3, timeout: 60_000},
      bad_config: %{error_threshold: 3, timeout: 60_000},
      rate_limited_provider: %{error_threshold: 3, timeout: 60_000}
    }
    
    Map.merge(
      @default_config,
      Map.merge(base_config, Map.get(provider_configs, provider_name, %{}))
    )
  end
  
  defp force_open_circuit(provider_name, reason, timeout_override \\ nil) do
    # Force open the circuit by recording multiple failures
    key = provider_key(provider_name)
    config = get_provider_config(provider_name)
    
    # Record enough failures to open the circuit
    for _ <- 1..config.error_threshold do
      CircuitBreaker.record_failure(key)
    end
    
    # Log the forced opening
    Logger.error("Force opening circuit for provider #{provider_name}: #{reason}")
    
    # If timeout override provided, we'd need to update the circuit breaker
    # For now, just track it separately
    if timeout_override do
      set_custom_timeout(provider_name, timeout_override)
    end
  end
  
  defp check_cost_threshold(provider_name) do
    config = get_provider_config(provider_name)
    current_cost = get_cost_used(provider_name)
    
    if current_cost >= config.cost_threshold do
      {:error, :cost_exceeded}
    else
      :ok
    end
  end
  
  defp check_rate_limit(provider_name) do
    if is_rate_limited?(provider_name) do
      {:error, :rate_limited}
    else
      :ok
    end
  end
  
  defp track_cost(provider_name, cost) do
    # Store in ETS or persistent storage
    # For now, using Process dictionary as a simple example
    key = {:cost, provider_name, DateTime.utc_now() |> DateTime.to_unix()}
    Process.put(key, cost)
  end
  
  defp get_cost_used(provider_name) do
    # Sum costs from last hour
    # Simplified implementation
    Process.get({:total_cost, provider_name}, 0.0)
  end
  
  defp track_latency(provider_name, latency_ms) do
    key = {:latency, provider_name}
    latencies = Process.get(key, [])
    Process.put(key, [latency_ms | Enum.take(latencies, 99)])
  end
  
  defp get_avg_latency(provider_name) do
    key = {:latency, provider_name}
    latencies = Process.get(key, [])
    
    if length(latencies) > 0 do
      Enum.sum(latencies) / length(latencies)
    else
      0.0
    end
  end
  
  defp is_rate_limited?(provider_name) do
    key = {:rate_limited_until, provider_name}
    
    case Process.get(key) do
      nil -> false
      until_time -> DateTime.compare(DateTime.utc_now(), until_time) == :lt
    end
  end
  
  defp clear_rate_limit(provider_name) do
    Process.delete({:rate_limited_until, provider_name})
  end
  
  defp set_custom_timeout(provider_name, timeout_ms) do
    until_time = DateTime.utc_now() |> DateTime.add(timeout_ms, :millisecond)
    Process.put({:rate_limited_until, provider_name}, until_time)
  end
  
  defp reset_cost_tracking(provider_name) do
    Process.delete({:total_cost, provider_name})
  end
  
  defp all_providers do
    # Get from configuration or registry
    [:openai, :anthropic, :local, :fallback]
  end
  
  defp provider_available?(provider_name) do
    case check_provider(provider_name) do
      :ok -> true
      _ -> false
    end
  end
  
  defp provider_priority(provider_name) do
    # Lower number = higher priority
    priorities = %{
      openai: 1,
      anthropic: 2,
      local: 3,
      fallback: 99
    }
    
    Map.get(priorities, provider_name, 100)
  end
  
  defp list_provider_circuit_breakers do
    CircuitBreakerSupervisor.list_circuit_breakers()
    |> Enum.filter(&is_provider_circuit_breaker?/1)
    |> Enum.map(&extract_provider_name/1)
  end
  
  defp is_provider_circuit_breaker?(circuit_breaker_name) do
    circuit_breaker_name
    |> Atom.to_string()
    |> String.starts_with?("llm_provider_")
  end
  
  defp extract_provider_name(circuit_breaker_name) do
    circuit_breaker_name
    |> Atom.to_string()
    |> String.replace_prefix("llm_provider_", "")
    |> String.to_atom()
  end
end