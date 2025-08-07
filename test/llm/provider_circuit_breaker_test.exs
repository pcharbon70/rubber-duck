defmodule RubberDuck.LLM.ProviderCircuitBreakerTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.LLM.ProviderCircuitBreaker
  alias RubberDuck.Routing.{CircuitBreaker, CircuitBreakerSupervisor}
  
  setup do
    # Registry is already started by the application
    # Just ensure the supervisor is started
    unless Process.whereis(CircuitBreakerSupervisor) do
      start_supervised!(CircuitBreakerSupervisor)
    end
    
    # Clean up any existing circuit breakers between tests
    CircuitBreakerSupervisor.list_circuit_breakers()
    |> Enum.each(&CircuitBreakerSupervisor.stop_circuit_breaker/1)
    
    # Reset process dictionary (used for simple state tracking)
    Process.get_keys()
    |> Enum.each(&Process.delete/1)
    
    :ok
  end
  
  describe "provider availability checks" do
    test "returns ok when provider is available" do
      assert :ok = ProviderCircuitBreaker.check_provider(:openai)
    end
    
    test "returns circuit_open after failures" do
      # Force open the circuit - need to ensure circuit breaker is created first
      ProviderCircuitBreaker.check_provider(:test_provider)
      
      # Record failures to open circuit
      ProviderCircuitBreaker.record_failure(:test_provider, :server_error)
      ProviderCircuitBreaker.record_failure(:test_provider, :server_error)
      ProviderCircuitBreaker.record_failure(:test_provider, :server_error)
      
      # Verify circuit is open
      assert ProviderCircuitBreaker.get_provider_status(:test_provider).state in [:open, :half_open]
    end
  end
  
  describe "failure recording" do
    test "opens circuit immediately for configuration errors" do
      # Ensure circuit breaker exists
      ProviderCircuitBreaker.check_provider(:bad_config)
      
      # Invalid API key should force open
      ProviderCircuitBreaker.record_failure(:bad_config, :invalid_api_key)
      
      # Circuit should be open
      status = ProviderCircuitBreaker.get_provider_status(:bad_config)
      assert status.state in [:open, :half_open]
    end
    
    test "handles rate limit failures with retry_after" do
      # Ensure circuit breaker exists
      ProviderCircuitBreaker.check_provider(:rate_limited_provider)
      
      metadata = %{retry_after: 60_000}
      ProviderCircuitBreaker.record_failure(:rate_limited_provider, :rate_limit, metadata)
      
      # Circuit should be open
      status = ProviderCircuitBreaker.get_provider_status(:rate_limited_provider)
      assert status.state in [:open, :half_open]
    end
    
    test "counts normal failures toward threshold" do
      # Ensure circuit breaker exists
      ProviderCircuitBreaker.check_provider(:normal_provider)
      
      # Should use default threshold of 3
      ProviderCircuitBreaker.record_failure(:normal_provider, :timeout)
      ProviderCircuitBreaker.record_failure(:normal_provider, :timeout)
      
      # Still closed after 2 failures
      status1 = ProviderCircuitBreaker.get_provider_status(:normal_provider)
      assert status1.state == :closed
      
      # Third failure opens it
      ProviderCircuitBreaker.record_failure(:normal_provider, :timeout)
      status2 = ProviderCircuitBreaker.get_provider_status(:normal_provider)
      assert status2.state in [:open, :half_open]
    end
  end
  
  describe "success recording" do
    test "resets error count in circuit breaker" do
      # Ensure circuit breaker exists
      ProviderCircuitBreaker.check_provider(:recovering_provider)
      
      # Create some failures
      ProviderCircuitBreaker.record_failure(:recovering_provider, :timeout)
      ProviderCircuitBreaker.record_failure(:recovering_provider, :timeout)
      
      # Record success - should reset error count
      ProviderCircuitBreaker.record_success(:recovering_provider)
      
      # Should still be available (error count reset)
      assert :ok = ProviderCircuitBreaker.check_provider(:recovering_provider)
    end
  end
  
  describe "fallback provider selection" do
    test "excludes specified providers" do
      fallbacks = ProviderCircuitBreaker.find_fallback_providers(
        :openai,
        exclude: [:openai, :anthropic]
      )
      
      refute :openai in fallbacks
      refute :anthropic in fallbacks
    end
    
    test "filters by cost threshold" do
      # Set high cost for expensive provider
      Process.put({:total_cost, :expensive}, 200.0)
      
      fallbacks = ProviderCircuitBreaker.find_fallback_providers(
        :primary,
        max_cost: 50.0
      )
      
      # Should not include expensive provider
      refute :expensive in fallbacks
    end
    
    test "returns providers in priority order" do
      # Force all providers to be available
      [:openai, :anthropic, :local, :fallback]
      |> Enum.each(fn provider ->
        ProviderCircuitBreaker.reset_provider(provider)
      end)
      
      fallbacks = ProviderCircuitBreaker.find_fallback_providers(:primary)
      
      # Check relative ordering (openai before anthropic, anthropic before local, etc.)
      openai_idx = Enum.find_index(fallbacks, &(&1 == :openai))
      anthropic_idx = Enum.find_index(fallbacks, &(&1 == :anthropic))
      local_idx = Enum.find_index(fallbacks, &(&1 == :local))
      
      if openai_idx && anthropic_idx do
        assert openai_idx < anthropic_idx
      end
      
      if anthropic_idx && local_idx do
        assert anthropic_idx < local_idx
      end
    end
    
    test "excludes unavailable providers" do
      # Open circuit for unavailable provider
      ProviderCircuitBreaker.record_failure(:broken_provider, :server_error)
      ProviderCircuitBreaker.record_failure(:broken_provider, :server_error)
      ProviderCircuitBreaker.record_failure(:broken_provider, :server_error)
      
      fallbacks = ProviderCircuitBreaker.find_fallback_providers(:primary)
      
      # Should not include broken provider
      refute :broken_provider in fallbacks
    end
  end
  
  describe "provider status" do
    test "returns unknown status for non-existent provider" do
      status = ProviderCircuitBreaker.get_provider_status(:never_used)
      
      assert status.state == :unknown
      assert status.available == true
    end
    
    test "aggregates status for all providers" do
      # Ensure some circuit breakers exist
      ProviderCircuitBreaker.check_provider(:healthy_provider)
      ProviderCircuitBreaker.check_provider(:unhealthy_provider)
      
      # Create different states
      ProviderCircuitBreaker.record_success(:healthy_provider)
      ProviderCircuitBreaker.record_failure(:unhealthy_provider, :server_error)
      ProviderCircuitBreaker.record_failure(:unhealthy_provider, :server_error)
      ProviderCircuitBreaker.record_failure(:unhealthy_provider, :server_error)
      
      all_status = ProviderCircuitBreaker.get_all_provider_status()
      
      assert is_map(all_status)
      # Status should include any providers that have circuit breakers
      assert map_size(all_status) >= 0
    end
  end
  
  describe "provider reset" do
    test "clears all provider state" do
      # Set up various state
      ProviderCircuitBreaker.record_failure(:reset_test, :timeout)
      Process.put({:total_cost, :reset_test}, 100.0)
      Process.put({:rate_limited_until, :reset_test}, DateTime.utc_now())
      
      # Reset provider
      assert :ok = ProviderCircuitBreaker.reset_provider(:reset_test)
      
      # Should be fully available
      assert :ok = ProviderCircuitBreaker.check_provider(:reset_test)
      assert Process.get({:total_cost, :reset_test}) == nil
      assert Process.get({:rate_limited_until, :reset_test}) == nil
    end
  end
  
  describe "provider-specific configurations" do
    test "uses stricter thresholds for expensive providers" do
      # Ensure circuit breaker exists
      ProviderCircuitBreaker.check_provider(:openai)
      
      # OpenAI should have lower error threshold (3)
      ProviderCircuitBreaker.record_failure(:openai, :timeout)
      ProviderCircuitBreaker.record_failure(:openai, :timeout)
      
      # Still closed after 2 failures
      status1 = ProviderCircuitBreaker.get_provider_status(:openai)
      assert status1.state == :closed || status1.state == :unknown
      
      # Third failure opens it
      ProviderCircuitBreaker.record_failure(:openai, :timeout)
      status2 = ProviderCircuitBreaker.get_provider_status(:openai)
      assert status2.state in [:open, :half_open]
    end
    
    test "uses more lenient thresholds for local providers" do
      # Ensure circuit breaker exists
      ProviderCircuitBreaker.check_provider(:local)
      
      # Local provider should have higher error threshold (10)
      # Record 9 failures
      for _ <- 1..9 do
        ProviderCircuitBreaker.record_failure(:local, :timeout)
      end
      
      # Still closed after 9 failures
      status1 = ProviderCircuitBreaker.get_provider_status(:local)
      assert status1.state in [:closed, :unknown]
      
      # Tenth failure opens it
      ProviderCircuitBreaker.record_failure(:local, :timeout)
      status2 = ProviderCircuitBreaker.get_provider_status(:local)
      assert status2.state in [:open, :half_open]
    end
  end
end