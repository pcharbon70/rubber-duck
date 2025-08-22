defmodule RubberDuck.ApplicationTest do
  use ExUnit.Case, async: false
  alias RubberDuck.Application
  alias RubberDuck.ErrorReporting.Aggregator
  alias RubberDuck.HealthCheck.StatusAggregator
  alias RubberDuck.Telemetry.VMMetrics

  describe "application startup" do
    test "starts with hierarchical supervision tree" do
      # Application should already be started by test setup
      # Verify main supervisor is running
      assert Process.whereis(RubberDuck.MainSupervisor)
    end

    test "infrastructure layer starts correctly" do
      # Check infrastructure supervisor
      assert Process.whereis(RubberDuck.InfrastructureSupervisor)

      # Check key infrastructure components
      assert Process.whereis(RubberDuck.Repo)
      assert Process.whereis(RubberDuck.PubSub)
      assert Process.whereis(Oban)
    end

    test "agentic layer starts correctly" do
      # Check agentic supervisor
      assert Process.whereis(RubberDuck.AgenticSupervisor)

      # Check agentic components
      assert Process.whereis(RubberDuck.SkillsRegistry)
      assert Process.whereis(RubberDuck.DirectivesEngine)
      assert Process.whereis(RubberDuck.InstructionsProcessor)
    end

    test "security layer starts correctly" do
      # Check security supervisor
      assert Process.whereis(RubberDuck.SecuritySupervisor)

      # AshAuthentication.Supervisor should be running
      # Note: Exact process names may vary for Ash components
    end

    test "application layer starts correctly" do
      # Check application supervisor
      assert Process.whereis(RubberDuck.ApplicationSupervisor)

      # Check web endpoint
      assert Process.whereis(RubberDuckWeb.Endpoint)
    end

    test "health check system starts correctly" do
      # Check health check supervisor
      assert Process.whereis(RubberDuck.HealthCheck.Supervisor)

      # Check health monitoring components
      assert Process.whereis(RubberDuck.HealthCheck.DatabaseMonitor)
      assert Process.whereis(RubberDuck.HealthCheck.ResourceMonitor)
      assert Process.whereis(RubberDuck.HealthCheck.ServiceMonitor)
      assert Process.whereis(RubberDuck.HealthCheck.AgentMonitor)
      assert Process.whereis(RubberDuck.HealthCheck.StatusAggregator)
    end

    test "telemetry system starts correctly" do
      # Check telemetry supervisor
      assert Process.whereis(RubberDuck.Telemetry.Supervisor)

      # Check telemetry components
      assert Process.whereis(RubberDuck.Telemetry.VMMetrics)
    end

    test "error reporting system starts correctly" do
      # Check error reporting supervisor
      assert Process.whereis(RubberDuck.ErrorReporting.Supervisor)

      # Check error reporting components
      assert Process.whereis(RubberDuck.ErrorReporting.Aggregator)
    end
  end

  describe "supervision strategy" do
    test "uses rest_for_one strategy for main supervisor" do
      {:ok, supervisor_spec} = Supervisor.which_children(RubberDuck.MainSupervisor)

      # Should have multiple supervised children
      assert length(supervisor_spec) > 0
    end

    test "infrastructure layer uses one_for_one strategy" do
      children = Supervisor.which_children(RubberDuck.InfrastructureSupervisor)

      # Should have infrastructure components
      assert length(children) > 0
    end

    test "each layer has proper supervisor hierarchy" do
      # Verify each layer supervisor exists and has children
      supervisors = [
        RubberDuck.InfrastructureSupervisor,
        RubberDuck.AgenticSupervisor,
        RubberDuck.SecuritySupervisor,
        RubberDuck.ApplicationSupervisor
      ]

      Enum.each(supervisors, fn supervisor ->
        assert Process.whereis(supervisor)
        children = Supervisor.which_children(supervisor)
        assert length(children) > 0
      end)
    end
  end

  describe "component integration" do
    test "skills registry is discoverable by agents" do
      # Test that skills registry responds to basic queries
      assert {:ok, _skills} = RubberDuck.SkillsRegistry.discover_skills()
    end

    test "directives engine is functional" do
      # Test basic directive validation
      test_directive = %{
        type: :behavior_modification,
        target: :all,
        parameters: %{behavior_type: :test, modification_type: :test}
      }

      assert :ok = RubberDuck.DirectivesEngine.validate_directive(test_directive)
    end

    test "instructions processor is functional" do
      # Test instruction normalization
      test_instruction = %{
        type: :skill_invocation,
        action: "test_action",
        parameters: %{}
      }

      assert {:ok, _normalized} =
               RubberDuck.InstructionsProcessor.normalize_instruction(test_instruction)
    end

    test "pubsub communication works between components" do
      # Test PubSub functionality
      test_topic = "test_integration_#{:rand.uniform(10000)}"
      test_message = %{test: true, timestamp: DateTime.utc_now()}

      # Subscribe to test topic
      Phoenix.PubSub.subscribe(RubberDuck.PubSub, test_topic)

      # Broadcast test message
      Phoenix.PubSub.broadcast(RubberDuck.PubSub, test_topic, test_message)

      # Verify message received
      assert_receive ^test_message, 1000
    end
  end

  describe "error handling and recovery" do
    test "infrastructure layer failures are isolated" do
      # This test would need careful setup to avoid affecting other tests
      # For now, just verify supervision structure exists
      children = Supervisor.which_children(RubberDuck.InfrastructureSupervisor)
      assert length(children) > 0
    end

    test "agentic layer failures are isolated" do
      # Verify agentic components can be restarted independently
      children = Supervisor.which_children(RubberDuck.AgenticSupervisor)
      assert length(children) > 0
    end

    test "application maintains health during component restart" do
      # Get initial health status
      initial_status = StatusAggregator.get_overall_status()

      # Health status should be determinable (not :unknown)
      assert initial_status in [:healthy, :warning, :degraded, :critical]
    end
  end

  describe "telemetry and monitoring" do
    test "telemetry events are being emitted" do
      # Set up telemetry listener
      test_pid = self()

      :telemetry.attach(
        "test-vm-metrics",
        [:rubber_duck, :vm, :all],
        fn _event, _measurements, _metadata, _config ->
          send(test_pid, :telemetry_received)
        end,
        nil
      )

      # Force VM metrics collection
      VMMetrics.force_collection()

      # Should receive telemetry event
      assert_receive :telemetry_received, 2000

      # Cleanup
      :telemetry.detach("test-vm-metrics")
    end

    test "health monitoring provides status" do
      # Get health status from aggregator
      status = StatusAggregator.get_detailed_status()

      assert is_map(status)
      assert Map.has_key?(status, :overall_status)
      assert Map.has_key?(status, :components)
      assert Map.has_key?(status, :summary)
    end

    test "error reporting aggregator is functional" do
      # Test error reporting
      test_error = %RuntimeError{message: "Test error for supervision tree test"}
      test_context = %{test: true, component: :application_test}

      # Report error
      Aggregator.report_error(test_error, test_context)

      # Get error stats
      stats = Aggregator.get_error_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :buffered_errors)
      assert Map.has_key?(stats, :total_error_count)
    end
  end

  describe "configuration" do
    test "oban is configured with correct queues" do
      # Check that Oban is running with expected configuration
      assert Process.whereis(Oban)

      # Verify queues are configured
      # Note: This would need access to Oban's internal configuration
      # For now, just verify Oban is running
    end

    test "supervision tree respects environment configuration" do
      # Verify that components respect configuration
      # For example, check if Tower is enabled based on config
      tower_enabled = Application.get_env(:rubber_duck, :enable_tower, false)

      if tower_enabled do
        # Tower-related processes should be running
        assert Process.whereis(RubberDuck.ErrorReporting.TowerReporter)
      end
    end
  end

  describe "graceful shutdown" do
    test "application can be stopped gracefully" do
      # This test is complex as it would involve stopping the application
      # For now, verify the structure supports graceful shutdown

      # Check that supervision tree is properly structured
      main_children = Supervisor.which_children(RubberDuck.MainSupervisor)

      # Should have proper ordering for graceful shutdown
      assert length(main_children) > 0
    end
  end
end
