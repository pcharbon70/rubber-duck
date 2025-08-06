defmodule RubberDuck.Integration.ApplicationStartupTest do
  @moduledoc """
  Integration tests for complete application startup.

  Verifies that all components initialize correctly and work together.
  """

  use ExUnit.Case

  describe "Application startup and initialization" do
    test "application starts with all required processes" do
      # Verify main supervisor is running
      assert Process.whereis(RubberDuck.Supervisor) != nil

      # Verify core processes
      assert Process.whereis(RubberDuck.Repo) != nil
      assert Process.whereis(RubberDuck.Telemetry) != nil
      assert Process.whereis(RubberDuck.HealthCheck) != nil
      assert Process.whereis(:rubber_duck_poller) != nil
    end

    test "supervision tree has correct structure" do
      # Get supervisor children
      children = Supervisor.which_children(RubberDuck.Supervisor)

      # Verify expected children are present
      child_ids = Enum.map(children, fn {id, _, _, _} -> id end)

      # Check for expected child processes without exact tuple matching
      assert RubberDuck.Repo in child_ids
      assert RubberDuck.Telemetry in child_ids
      assert RubberDuck.HealthCheck in child_ids

      # Check that AshAuthentication.Supervisor is present (may be in different format)
      ash_auth_present = Enum.any?(child_ids, fn
        {AshAuthentication.Supervisor, _} -> true
        _ -> false
      end)
      assert ash_auth_present || AshAuthentication.Supervisor in child_ids
    end

    test "telemetry system initializes correctly" do
      # Verify telemetry metrics are defined
      metrics = RubberDuck.Telemetry.metrics()
      assert is_list(metrics)
      assert length(metrics) > 0

      # Set up a test handler to verify events are being emitted
      handler_id = :test_startup_handler
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:rubber_duck, :health, :database],
        fn _event, measurements, _metadata, _config ->
          send(test_pid, {:telemetry_received, measurements})
        end,
        nil
      )

      # Trigger a health check
      RubberDuck.Telemetry.dispatch_health_check()

      # Verify we receive telemetry
      assert_receive {:telemetry_received, %{value: _}}, 2000

      # Cleanup
      :telemetry.detach(handler_id)
    end

    test "health check system starts and responds" do
      # Verify health check is running
      assert Process.whereis(RubberDuck.HealthCheck) != nil

      # Get health status
      status = RubberDuck.HealthCheck.get_status()

      assert %RubberDuck.HealthCheck{} = status
      assert status.status in [:healthy, :degraded, :unhealthy, :initializing]
      assert is_map(status.checks)

      # Verify health JSON endpoint works
      health_json = RubberDuck.HealthCheck.get_health_json()
      assert is_map(health_json)
      assert Map.has_key?(health_json, :status)
      assert Map.has_key?(health_json, :timestamp)
    end

    test "database connection is established" do
      # Test database connectivity
      assert {:ok, %{rows: [[1]]}} = RubberDuck.Repo.query("SELECT 1", [])

      # Verify repo is in healthy state
      assert Process.alive?(Process.whereis(RubberDuck.Repo))
    end

    test "ash domains are loaded and accessible" do
      # Verify domains are compiled and accessible
      assert Code.ensure_loaded?(RubberDuck.Accounts)
      assert Code.ensure_loaded?(RubberDuck.Projects)
      assert Code.ensure_loaded?(RubberDuck.AI)

      # Verify resources are loaded
      assert Code.ensure_loaded?(RubberDuck.Accounts.User)
      assert Code.ensure_loaded?(RubberDuck.Accounts.Token)
      assert Code.ensure_loaded?(RubberDuck.Projects.Project)
      assert Code.ensure_loaded?(RubberDuck.Projects.CodeFile)
      assert Code.ensure_loaded?(RubberDuck.AI.AnalysisResult)
      assert Code.ensure_loaded?(RubberDuck.AI.Prompt)
    end

    test "error reporting (Tower) is configured" do
      # Tower configuration should be present
      tower_config = Application.get_env(:tower, :reporters)
      assert tower_config != nil
      assert is_list(tower_config)
    end

    test "application can recover from supervisor restart" do
      # Get current supervisor PID
      sup_pid = Process.whereis(RubberDuck.Supervisor)
      assert sup_pid != nil

      # Get current health check PID
      health_pid = Process.whereis(RubberDuck.HealthCheck)
      assert health_pid != nil

      # Kill health check process (should be restarted by supervisor)
      Process.exit(health_pid, :kill)

      # Give supervisor time to restart the process
      Process.sleep(100)

      # Verify health check was restarted with new PID
      new_health_pid = Process.whereis(RubberDuck.HealthCheck)
      assert new_health_pid != nil
      assert new_health_pid != health_pid

      # Verify it's functional
      status = RubberDuck.HealthCheck.get_status()
      assert %RubberDuck.HealthCheck{} = status
    end
  end
end
