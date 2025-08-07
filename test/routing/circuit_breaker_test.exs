defmodule RubberDuck.Routing.CircuitBreakerTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Routing.{CircuitBreaker, CircuitBreakerSupervisor}
  
  # Test message module
  defmodule TestMessage do
    defstruct [:content]
  end
  
  setup do
    # Registry is already started by the application
    # Just ensure the supervisor is started
    unless Process.whereis(CircuitBreakerSupervisor) do
      start_supervised!(CircuitBreakerSupervisor)
    end
    
    # Clean up any existing circuit breakers between tests
    CircuitBreakerSupervisor.list_circuit_breakers()
    |> Enum.each(&CircuitBreakerSupervisor.stop_circuit_breaker/1)
    
    :ok
  end
  
  describe "circuit breaker states" do
    test "starts in closed state" do
      assert :ok = CircuitBreakerSupervisor.ensure_circuit_breaker(TestMessage)
      assert {:ok, state} = CircuitBreaker.get_state(TestMessage)
      assert state.state == :closed
    end
    
    test "allows requests in closed state" do
      assert :ok = CircuitBreakerSupervisor.ensure_circuit_breaker(TestMessage)
      assert :ok = CircuitBreaker.call(TestMessage)
    end
    
    test "transitions to open after threshold failures" do
      config = [config: %{error_threshold: 3, timeout: 100}]
      assert :ok = CircuitBreakerSupervisor.ensure_circuit_breaker(TestMessage, config)
      
      # Record failures up to threshold
      CircuitBreaker.record_failure(TestMessage)
      CircuitBreaker.record_failure(TestMessage)
      
      # Still closed
      assert :ok = CircuitBreaker.call(TestMessage)
      
      # One more failure opens it
      CircuitBreaker.record_failure(TestMessage)
      
      # Now open
      assert {:error, :circuit_open} = CircuitBreaker.call(TestMessage)
      assert {:ok, state} = CircuitBreaker.get_state(TestMessage)
      assert state.state == :open
    end
    
    test "rejects requests in open state" do
      config = [config: %{error_threshold: 1, timeout: 100}]
      assert :ok = CircuitBreakerSupervisor.ensure_circuit_breaker(TestMessage, config)
      
      # Open the circuit
      CircuitBreaker.record_failure(TestMessage)
      
      # Should reject requests
      assert {:error, :circuit_open} = CircuitBreaker.call(TestMessage)
    end
    
    test "transitions to half-open after timeout" do
      config = [config: %{error_threshold: 1, timeout: 50}]
      assert :ok = CircuitBreakerSupervisor.ensure_circuit_breaker(TestMessage, config)
      
      # Open the circuit
      CircuitBreaker.record_failure(TestMessage)
      assert {:error, :circuit_open} = CircuitBreaker.call(TestMessage)
      
      # Wait for timeout
      Process.sleep(60)
      
      # Should be half-open and allow limited requests
      assert :ok = CircuitBreaker.call(TestMessage)
      assert {:ok, state} = CircuitBreaker.get_state(TestMessage)
      assert state.state == :half_open
    end
    
    test "limits requests in half-open state" do
      config = [config: %{
        error_threshold: 1, 
        timeout: 50, 
        half_open_requests: 2
      }]
      assert :ok = CircuitBreakerSupervisor.ensure_circuit_breaker(TestMessage, config)
      
      # Open the circuit
      CircuitBreaker.record_failure(TestMessage)
      
      # Wait for timeout
      Process.sleep(60)
      
      # Should allow limited requests
      assert :ok = CircuitBreaker.call(TestMessage)
      assert :ok = CircuitBreaker.call(TestMessage)
      
      # Should reject after limit
      assert {:error, :circuit_half_open_limit} = CircuitBreaker.call(TestMessage)
    end
    
    test "closes from half-open after success threshold" do
      config = [config: %{
        error_threshold: 1,
        timeout: 50,
        success_threshold: 2
      }]
      assert :ok = CircuitBreakerSupervisor.ensure_circuit_breaker(TestMessage, config)
      
      # Open the circuit
      CircuitBreaker.record_failure(TestMessage)
      
      # Wait for timeout to go half-open
      Process.sleep(60)
      
      # Record successes
      assert :ok = CircuitBreaker.call(TestMessage)
      CircuitBreaker.record_success(TestMessage)
      CircuitBreaker.record_success(TestMessage)
      
      # Should be closed
      assert {:ok, state} = CircuitBreaker.get_state(TestMessage)
      assert state.state == :closed
    end
    
    test "returns to open from half-open on failure" do
      config = [config: %{
        error_threshold: 1,
        timeout: 50
      }]
      assert :ok = CircuitBreakerSupervisor.ensure_circuit_breaker(TestMessage, config)
      
      # Open the circuit
      CircuitBreaker.record_failure(TestMessage)
      
      # Wait for timeout to go half-open
      Process.sleep(60)
      
      # Allow a request and fail it
      assert :ok = CircuitBreaker.call(TestMessage)
      CircuitBreaker.record_failure(TestMessage)
      
      # Should be open again
      assert {:error, :circuit_open} = CircuitBreaker.call(TestMessage)
      assert {:ok, state} = CircuitBreaker.get_state(TestMessage)
      assert state.state == :open
    end
  end
  
  describe "circuit breaker operations" do
    test "reset brings circuit to closed state" do
      config = [config: %{error_threshold: 1}]
      assert :ok = CircuitBreakerSupervisor.ensure_circuit_breaker(TestMessage, config)
      
      # Open the circuit
      CircuitBreaker.record_failure(TestMessage)
      assert {:error, :circuit_open} = CircuitBreaker.call(TestMessage)
      
      # Reset
      assert :ok = CircuitBreaker.reset(TestMessage)
      
      # Should be closed
      assert :ok = CircuitBreaker.call(TestMessage)
      assert {:ok, state} = CircuitBreaker.get_state(TestMessage)
      assert state.state == :closed
      assert state.error_count == 0
    end
    
    test "success in closed state resets error count" do
      config = [config: %{error_threshold: 3}]
      assert :ok = CircuitBreakerSupervisor.ensure_circuit_breaker(TestMessage, config)
      
      # Record some failures
      CircuitBreaker.record_failure(TestMessage)
      CircuitBreaker.record_failure(TestMessage)
      
      # Record success
      CircuitBreaker.record_success(TestMessage)
      
      # Error count should be reset
      assert {:ok, state} = CircuitBreaker.get_state(TestMessage)
      assert state.error_count == 0
    end
    
    test "handles non-existent circuit breaker gracefully" do
      # These should not crash
      assert :ok = CircuitBreaker.call(TestMessage)
      assert :ok = CircuitBreaker.record_success(TestMessage)
      assert :ok = CircuitBreaker.record_failure(TestMessage)
      assert {:error, :not_found} = CircuitBreaker.get_state(TestMessage)
      assert :ok = CircuitBreaker.reset(TestMessage)
    end
  end
  
  describe "circuit breaker supervisor" do
    test "creates circuit breakers on demand" do
      # Clean up to ensure we start with no circuit breakers
      CircuitBreakerSupervisor.list_circuit_breakers()
      |> Enum.each(&CircuitBreakerSupervisor.stop_circuit_breaker/1)
      
      assert [] = CircuitBreakerSupervisor.list_circuit_breakers()
      
      assert :ok = CircuitBreakerSupervisor.ensure_circuit_breaker(TestMessage)
      assert [TestMessage] = CircuitBreakerSupervisor.list_circuit_breakers()
    end
    
    test "handles duplicate circuit breaker creation" do
      assert :ok = CircuitBreakerSupervisor.ensure_circuit_breaker(TestMessage)
      assert :ok = CircuitBreakerSupervisor.ensure_circuit_breaker(TestMessage)
      
      # Should only have one
      assert [TestMessage] = CircuitBreakerSupervisor.list_circuit_breakers()
    end
    
    test "can stop circuit breakers" do
      assert :ok = CircuitBreakerSupervisor.ensure_circuit_breaker(TestMessage)
      assert [TestMessage] = CircuitBreakerSupervisor.list_circuit_breakers()
      
      assert :ok = CircuitBreakerSupervisor.stop_circuit_breaker(TestMessage)
      assert [] = CircuitBreakerSupervisor.list_circuit_breakers()
    end
    
    test "returns stats for all circuit breakers" do
      defmodule TestMessage2 do
        defstruct [:content]
      end
      
      assert :ok = CircuitBreakerSupervisor.ensure_circuit_breaker(TestMessage)
      assert :ok = CircuitBreakerSupervisor.ensure_circuit_breaker(TestMessage2, 
                    config: %{error_threshold: 1})
      
      # Open one circuit
      CircuitBreaker.record_failure(TestMessage2)
      
      stats = CircuitBreakerSupervisor.get_all_stats()
      
      assert Map.has_key?(stats, TestMessage)
      assert Map.has_key?(stats, TestMessage2)
      assert stats[TestMessage].state == :closed
      assert stats[TestMessage2].state == :open
    end
  end
  
  describe "configuration" do
    test "uses default configuration when not specified" do
      assert :ok = CircuitBreakerSupervisor.ensure_circuit_breaker(TestMessage)
      
      # Default threshold is 5
      CircuitBreaker.record_failure(TestMessage)
      CircuitBreaker.record_failure(TestMessage)
      CircuitBreaker.record_failure(TestMessage)
      CircuitBreaker.record_failure(TestMessage)
      
      # Still closed
      assert :ok = CircuitBreaker.call(TestMessage)
      
      # Fifth failure opens it
      CircuitBreaker.record_failure(TestMessage)
      assert {:error, :circuit_open} = CircuitBreaker.call(TestMessage)
    end
    
    test "accepts custom configuration" do
      config = [config: %{
        error_threshold: 2,
        timeout: 100,
        half_open_requests: 1,
        success_threshold: 1
      }]
      
      assert :ok = CircuitBreakerSupervisor.ensure_circuit_breaker(TestMessage, config)
      
      # Custom threshold of 2
      CircuitBreaker.record_failure(TestMessage)
      assert :ok = CircuitBreaker.call(TestMessage)
      
      CircuitBreaker.record_failure(TestMessage)
      assert {:error, :circuit_open} = CircuitBreaker.call(TestMessage)
    end
  end
end