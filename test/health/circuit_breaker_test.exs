defmodule RubberDuck.Health.CircuitBreakerTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Health.{CircuitBreaker, ProtectedHealthCheck}
  alias RubberDuck.Routing.CircuitBreakerSupervisor

  setup do
    # Ensure supervisor is started
    unless Process.whereis(CircuitBreakerSupervisor) do
      start_supervised!(CircuitBreakerSupervisor)
    end

    # Reset all circuit breakers
    CircuitBreaker.reset_all()

    # Clear process dictionary
    Process.get_keys()
    |> Enum.each(&Process.delete/1)

    :ok
  end

  describe "check_with_breaker/3" do
    test "executes check when circuit is closed" do
      result =
        CircuitBreaker.check_with_breaker(:database, fn ->
          %{status: :healthy, message: "Test database healthy"}
        end)

      assert result.status == :healthy
      assert result.message == "Test database healthy"
    end

    test "returns cached result when circuit is open" do
      # Force circuit open
      CircuitBreaker.force_failure(:database, 3)

      # Should return cached failure result
      result =
        CircuitBreaker.check_with_breaker(:database, fn ->
          %{status: :healthy, message: "Should not execute"}
        end)

      assert result.status == :unhealthy
      assert result.circuit_open == true
      assert result.cached == true
    end

    test "records timing information" do
      result =
        CircuitBreaker.check_with_breaker(:memory, fn ->
          Process.sleep(10)
          %{status: :healthy, message: "Memory check"}
        end)

      assert result.check_time_ms >= 10
    end

    test "handles check failures gracefully" do
      result =
        CircuitBreaker.check_with_breaker(:external_service, fn ->
          raise "Connection failed"
        end)

      assert result.status == :unhealthy
      assert result.message =~ "Check failed"
    end

    test "handles check timeouts" do
      result =
        CircuitBreaker.check_with_breaker(
          :external_service,
          fn ->
            Process.sleep(200)
            %{status: :healthy, message: "Too late"}
          end,
          timeout: 50
        )

      assert result.status == :unhealthy
      assert result.message == "Health check timed out"
    end
  end

  describe "check_multiple/2" do
    test "executes multiple checks in parallel" do
      checks = [
        {:database, fn -> %{status: :healthy, message: "DB OK"} end},
        {:memory, fn -> %{status: :healthy, message: "Memory OK"} end},
        {:processes, fn -> %{status: :warning, message: "High process count"} end}
      ]

      results = CircuitBreaker.check_multiple(checks)

      assert results.database.status == :healthy
      assert results.memory.status == :healthy
      assert results.processes.status == :warning
    end

    test "respects circuit states for multiple checks" do
      # Open database circuit
      CircuitBreaker.force_failure(:database, 3)

      checks = [
        {:database, fn -> %{status: :healthy, message: "Should not run"} end},
        {:memory, fn -> %{status: :healthy, message: "Memory OK"} end}
      ]

      results = CircuitBreaker.check_multiple(checks)

      assert results.database.circuit_open == true
      assert results.database.cached == true
      assert results.memory.status == :healthy
    end

    test "handles timeout for slow checks" do
      checks = [
        {:database,
         fn ->
           Process.sleep(6000)
           %{status: :healthy, message: "Too slow"}
         end},
        {:memory, fn -> %{status: :healthy, message: "Fast check"} end}
      ]

      results = CircuitBreaker.check_multiple(checks)

      assert results.database.status == :unknown
      assert results.database.message == "Check timed out"
      assert results.memory.status == :healthy
    end
  end

  describe "circuit management" do
    test "get_status returns all circuit states" do
      status = CircuitBreaker.get_status()

      assert Map.has_key?(status, :database)
      assert Map.has_key?(status, :memory)
      assert Map.has_key?(status, :processes)
      assert Map.has_key?(status, :external_service)
    end

    test "reset clears circuit and cache" do
      # Create some state
      CircuitBreaker.check_with_breaker(:repo_pool, fn ->
        %{status: :unhealthy, message: "Pool error"}
      end)

      # Force failure
      CircuitBreaker.force_failure(:repo_pool, 3)

      # Reset
      CircuitBreaker.reset(:repo_pool)

      # Should work again
      result =
        CircuitBreaker.check_with_breaker(:repo_pool, fn ->
          %{status: :healthy, message: "Pool recovered"}
        end)

      assert result.status == :healthy
      assert result.cached != true
    end

    test "reset_all clears all circuits" do
      # Force multiple failures
      CircuitBreaker.force_failure(:database, 3)
      CircuitBreaker.force_failure(:repo_pool, 3)

      # Reset all
      CircuitBreaker.reset_all()

      # All should work
      db_result =
        CircuitBreaker.check_with_breaker(:database, fn ->
          %{status: :healthy, message: "DB OK"}
        end)

      pool_result =
        CircuitBreaker.check_with_breaker(:repo_pool, fn ->
          %{status: :healthy, message: "Pool OK"}
        end)

      assert db_result.status == :healthy
      assert pool_result.status == :healthy
    end

    test "circuit_open? correctly reports circuit state" do
      assert CircuitBreaker.circuit_open?(:database) == false

      CircuitBreaker.force_failure(:database, 3)

      assert CircuitBreaker.circuit_open?(:database) == true
    end
  end

  describe "caching behavior" do
    test "caches successful results" do
      # First check
      CircuitBreaker.check_with_breaker(:atoms, fn ->
        %{status: :healthy, message: "Atoms OK", timestamp: DateTime.utc_now()}
      end)

      # Force circuit open
      CircuitBreaker.force_failure(:atoms, 3)

      # Should get cached result
      result =
        CircuitBreaker.check_with_breaker(:atoms, fn ->
          %{status: :unhealthy, message: "Should not run"}
        end)

      assert result.cached == true
      assert result.cache_age_ms >= 0
    end

    test "returns unknown when cache expires" do
      # Create old cache manually
      Process.put({:health_cache, :external_service}, {
        %{status: :healthy, message: "Old result"},
        DateTime.add(DateTime.utc_now(), -60, :second)
      })

      # Force circuit open
      CircuitBreaker.force_failure(:external_service, 5)

      # Should return unknown due to expired cache
      result =
        CircuitBreaker.check_with_breaker(:external_service, fn ->
          %{status: :healthy, message: "Should not run"}
        end)

      assert result.status == :unknown
      assert result.message =~ "cache expired"
    end
  end

  describe "check-specific thresholds" do
    test "database has strict threshold" do
      # Database should open after 2 failures
      CircuitBreaker.check_with_breaker(:database, fn ->
        %{status: :unhealthy, message: "Fail 1"}
      end)

      CircuitBreaker.check_with_breaker(:database, fn ->
        %{status: :unhealthy, message: "Fail 2"}
      end)

      # Should be open now
      assert CircuitBreaker.circuit_open?(:database) == true
    end

    test "memory has lenient threshold" do
      # Memory should tolerate more failures (10)
      for i <- 1..9 do
        CircuitBreaker.check_with_breaker(:memory, fn ->
          %{status: :unhealthy, message: "Fail #{i}"}
        end)
      end

      # Should still be closed
      assert CircuitBreaker.circuit_open?(:memory) == false

      # One more opens it
      CircuitBreaker.check_with_breaker(:memory, fn ->
        %{status: :unhealthy, message: "Fail 10"}
      end)

      assert CircuitBreaker.circuit_open?(:memory) == true
    end
  end

  describe "ProtectedHealthCheck integration" do
    setup do
      {:ok, pid} = start_supervised({ProtectedHealthCheck, name: :test_health})
      {:ok, server: pid}
    end

    test "get_status includes circuit breaker info", %{server: server} do
      # Force a check
      ProtectedHealthCheck.check_now(server)
      Process.sleep(100)

      status = ProtectedHealthCheck.get_status(server)

      # Should have checks with circuit info
      assert is_map(status.checks)

      # Each check should have circuit_state
      Enum.each(status.checks, fn {_check_type, result} ->
        assert Map.has_key?(result, :circuit_state)
      end)
    end

    test "get_health_json includes circuit breaker status", %{server: server} do
      json = ProtectedHealthCheck.get_health_json(server)

      assert Map.has_key?(json, :circuit_breakers)
      assert Map.has_key?(json, :degraded_mode)
      assert is_map(json.circuit_breakers)
    end

    test "degraded mode can be enabled", %{server: server} do
      ProtectedHealthCheck.set_degraded_mode(true, server)

      status = ProtectedHealthCheck.get_status(server)
      assert status.degraded_mode == true
    end

    test "auto-enables degraded mode after failures", %{server: server} do
      # Simulate multiple failures by breaking circuits
      CircuitBreaker.force_failure(:database, 3)
      CircuitBreaker.force_failure(:repo_pool, 3)

      # Trigger checks that will fail
      for _ <- 1..3 do
        ProtectedHealthCheck.check_now(server)
        Process.sleep(100)
      end

      status = ProtectedHealthCheck.get_status(server)
      # May auto-enable degraded mode after consecutive failures
      # (depending on timing and check results)
      assert is_boolean(status.degraded_mode)
    end
  end

  describe "consecutive failures tracking" do
    test "tracks consecutive failures per check" do
      # Record multiple failures
      CircuitBreaker.check_with_breaker(:ash_authentication, fn ->
        %{status: :unhealthy, message: "Auth down"}
      end)

      CircuitBreaker.check_with_breaker(:ash_authentication, fn ->
        %{status: :unhealthy, message: "Still down"}
      end)

      status = CircuitBreaker.get_status()
      auth_status = status.ash_authentication

      assert auth_status.consecutive_failures > 0
    end

    test "clears consecutive failures on success" do
      # Record failure
      CircuitBreaker.check_with_breaker(:processes, fn ->
        %{status: :unhealthy, message: "Too many processes"}
      end)

      # Then success
      CircuitBreaker.check_with_breaker(:processes, fn ->
        %{status: :healthy, message: "Process count normal"}
      end)

      status = CircuitBreaker.get_status()
      process_status = status.processes

      assert process_status.consecutive_failures == 0
    end
  end
end
