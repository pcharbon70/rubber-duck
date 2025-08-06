defmodule RubberDuck.HealthCheckTest do
  use RubberDuck.DataCase

  describe "HealthCheck GenServer" do
    test "health check process starts successfully" do
      assert Process.whereis(RubberDuck.HealthCheck) != nil
    end

    test "get_status returns health information" do
      status = RubberDuck.HealthCheck.get_status()

      assert %RubberDuck.HealthCheck{} = status
      assert status.status in [:healthy, :degraded, :unhealthy, :initializing]
      assert is_map(status.checks)
    end

    test "get_health_json returns JSON-compatible health data" do
      health_json = RubberDuck.HealthCheck.get_health_json()

      assert is_map(health_json)
      assert Map.has_key?(health_json, :status)
      assert Map.has_key?(health_json, :timestamp)
      assert Map.has_key?(health_json, :checks)
      assert Map.has_key?(health_json, :uptime)

      # Verify timestamp is ISO8601 format
      assert {:ok, _datetime, _} = DateTime.from_iso8601(health_json.timestamp)

      # Verify uptime is a number
      assert is_integer(health_json.uptime)
    end

    test "health checks include all required components" do
      status = RubberDuck.HealthCheck.get_status()
      checks = status.checks

      # Verify all expected health checks are present
      assert Map.has_key?(checks, :database)
      assert Map.has_key?(checks, :memory)
      assert Map.has_key?(checks, :processes)
      assert Map.has_key?(checks, :atoms)
      assert Map.has_key?(checks, :ash_authentication)
      assert Map.has_key?(checks, :repo_pool)

      # Each check should have a status and message
      Enum.each(checks, fn {_name, check} ->
        assert Map.has_key?(check, :status)
        assert Map.has_key?(check, :message)
        assert check.status in [:healthy, :degraded, :warning, :unhealthy, :unknown]
      end)
    end

    test "database health check works" do
      status = RubberDuck.HealthCheck.get_status()
      db_check = status.checks.database

      # Database should be healthy in test environment
      assert db_check.status == :healthy
      assert db_check.message =~ "successful"
    end

    test "memory usage check provides metrics" do
      status = RubberDuck.HealthCheck.get_status()
      memory_check = status.checks.memory

      assert memory_check.status in [:healthy, :warning]
      assert is_float(memory_check.total_mb)
      assert is_float(memory_check.process_mb)
      assert memory_check.total_mb > 0
    end

    test "process count check provides limits" do
      status = RubberDuck.HealthCheck.get_status()
      process_check = status.checks.processes

      assert process_check.status in [:healthy, :warning]
      assert is_integer(process_check.count)
      assert is_integer(process_check.limit)
      assert process_check.count > 0
      assert process_check.count < process_check.limit
    end

    test "atom usage check provides limits" do
      status = RubberDuck.HealthCheck.get_status()
      atom_check = status.checks.atoms

      assert atom_check.status in [:healthy, :warning]
      assert is_integer(atom_check.count)
      assert is_integer(atom_check.limit)
      assert atom_check.count > 0
      assert atom_check.count < atom_check.limit
    end

    test "ash authentication check verifies system" do
      status = RubberDuck.HealthCheck.get_status()
      auth_check = status.checks.ash_authentication

      # Should be healthy since application is running
      assert auth_check.status == :healthy
      assert auth_check.message =~ "available"
    end

    test "repo pool check verifies database pool" do
      status = RubberDuck.HealthCheck.get_status()
      pool_check = status.checks.repo_pool

      # Should be healthy since repo is running
      assert pool_check.status == :healthy
      assert pool_check.message =~ "healthy"
      assert pool_check.queue == 0
      assert pool_check.size == 10
    end

    test "check_now triggers immediate health check" do
      # Get initial status
      initial_status = RubberDuck.HealthCheck.get_status()
      initial_check_time = initial_status.last_check

      # Small delay to ensure time difference
      Process.sleep(10)

      # Trigger immediate check
      RubberDuck.HealthCheck.check_now()

      # Give it time to complete
      Process.sleep(100)

      # Get new status
      new_status = RubberDuck.HealthCheck.get_status()
      new_check_time = new_status.last_check

      # Verify check was performed
      if initial_check_time && new_check_time do
        assert DateTime.compare(new_check_time, initial_check_time) == :gt
      end
    end
  end
end
