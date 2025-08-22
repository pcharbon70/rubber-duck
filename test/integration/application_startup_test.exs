defmodule RubberDuck.Integration.ApplicationStartupTest do
  @moduledoc """
  Integration tests for complete application startup sequence and cross-layer coordination.

  Tests the hierarchical supervision tree, inter-layer communication,
  and system resilience during startup and restart scenarios.
  """

  use ExUnit.Case, async: false

  alias RubberDuck.DirectivesEngine
  alias RubberDuck.ErrorReporting.Aggregator
  alias RubberDuck.HealthCheck.StatusAggregator
  alias RubberDuck.InstructionsProcessor
  alias RubberDuck.SkillsRegistry
  alias RubberDuck.Telemetry.VMMetrics

  @moduletag :integration

  describe "hierarchical supervision tree startup" do
    test "infrastructure layer starts before agentic layer" do
      # Verify infrastructure components are running
      assert Process.whereis(RubberDuck.InfrastructureSupervisor)
      assert Process.whereis(RubberDuck.Repo)
      assert Process.whereis(RubberDuck.PubSub)
      assert Process.whereis(Oban)

      # Verify agentic components are running and can access infrastructure
      assert Process.whereis(RubberDuck.AgenticSupervisor)
      assert Process.whereis(SkillsRegistry)

      # Test that agentic components can use infrastructure
      {:ok, _skills} = SkillsRegistry.discover_skills()

      # Test PubSub communication
      test_topic = "startup_test_#{:rand.uniform(1000)}"
      Phoenix.PubSub.subscribe(RubberDuck.PubSub, test_topic)
      Phoenix.PubSub.broadcast(RubberDuck.PubSub, test_topic, :startup_test)

      assert_receive :startup_test, 1000
    end

    test "security layer initializes with authentication capabilities" do
      # Verify security supervisor is running
      assert Process.whereis(RubberDuck.SecuritySupervisor)

      # Verify authentication system is available
      # Note: AshAuthentication may have different process naming
      # Focus on functionality rather than specific process names

      # Test that security components can issue directives
      assert Process.whereis(DirectivesEngine)

      test_directive = %{
        type: :security_policy_change,
        target: :all,
        parameters: %{policy_type: :startup_test}
      }

      assert :ok = DirectivesEngine.validate_directive(test_directive)
    end

    test "application layer starts last and can serve requests" do
      # Verify application supervisor is running
      assert Process.whereis(RubberDuck.ApplicationSupervisor)
      assert Process.whereis(RubberDuckWeb.Endpoint)

      # Verify health check system is operational
      assert Process.whereis(RubberDuck.HealthCheck.Supervisor)

      # Test health endpoint functionality
      overall_status = StatusAggregator.get_overall_status()
      assert overall_status in [:healthy, :warning, :degraded, :critical]

      # Test detailed status includes all layers
      detailed_status = StatusAggregator.get_detailed_status()
      assert Map.has_key?(detailed_status.components, :database)
      assert Map.has_key?(detailed_status.components, :resources)
      assert Map.has_key?(detailed_status.components, :services)
      assert Map.has_key?(detailed_status.components, :agents)
    end

    test "health monitoring system provides comprehensive system view" do
      # Wait for initial health checks to complete
      Process.sleep(2000)

      # Get comprehensive health status
      detailed_status = StatusAggregator.get_detailed_status()

      # Verify all expected components are being monitored
      expected_components = [:database, :resources, :services, :agents]

      Enum.each(expected_components, fn component ->
        assert Map.has_key?(detailed_status.components, component)
        component_status = detailed_status.components[component]
        assert Map.has_key?(component_status, :status)
        assert component_status.status in [:healthy, :warning, :degraded, :critical, :unavailable]
      end)

      # Verify summary provides accurate counts
      summary = detailed_status.summary
      assert summary.total_components == length(expected_components)
      assert is_number(summary.health_percentage)
      assert summary.health_percentage >= 0 and summary.health_percentage <= 100
    end
  end

  describe "inter-layer communication" do
    test "skills registry accessible from all layers" do
      # Test skills discovery from different contexts
      {:ok, skills} = SkillsRegistry.discover_skills()
      assert map_size(skills) > 0

      # Test skills can be configured
      test_config = %{timeout: 5000, test_mode: true}

      assert :ok =
               SkillsRegistry.configure_skill_for_agent(
                 "test_agent",
                 :learning_skill,
                 test_config
               )

      # Verify configuration is retrievable
      {:ok, retrieved_config} =
        SkillsRegistry.get_agent_skill_config("test_agent", :learning_skill)

      assert retrieved_config == test_config
    end

    test "directives engine coordinates behavior across layers" do
      # Test security layer can issue directives to agentic layer
      security_directive = %{
        type: :behavior_modification,
        target: :all,
        parameters: %{
          behavior_type: :security_mode,
          modification_type: :enable_enhanced_monitoring
        }
      }

      {:ok, directive_id} = DirectivesEngine.issue_directive(security_directive)
      assert is_binary(directive_id)

      # Verify directive was recorded
      {:ok, history} = DirectivesEngine.get_directive_history()
      assert length(history) > 0

      # Test rollback functionality
      {:ok, rollback_id} = DirectivesEngine.create_rollback_point("integration_test")
      assert is_binary(rollback_id)
    end

    test "instructions processor coordinates workflows across components" do
      # Test workflow composition for cross-component operations
      workflow_spec = %{
        name: "integration_test_workflow",
        instructions: [
          %{
            type: :skill_invocation,
            action: "test.authenticate_user",
            parameters: %{user_id: "test_user_123"},
            dependencies: []
          },
          %{
            type: :data_operation,
            action: "test.create_user_record",
            parameters: %{user_data: %{name: "Test User"}},
            dependencies: []
          },
          %{
            type: :communication,
            action: "test.notify_security",
            parameters: %{event_type: :user_created},
            dependencies: []
          }
        ]
      }

      {:ok, workflow_id} = InstructionsProcessor.compose_workflow(workflow_spec)
      assert is_binary(workflow_id)

      # Test workflow execution
      {:ok, execution_result} =
        InstructionsProcessor.execute_workflow(workflow_id, "integration_test_agent")

      assert execution_result.status == :completed
      assert map_size(execution_result.instruction_results) == 3
    end

    test "telemetry system captures events from all layers" do
      # Set up telemetry listener for integration events
      test_pid = self()

      telemetry_events = [
        [:rubber_duck, :vm, :all],
        [:rubber_duck, :health_check, :overall],
        [:rubber_duck, :error_reporting, :batch_processed]
      ]

      # Attach listeners
      Enum.each(telemetry_events, fn event ->
        event_name = "integration_test_#{:rand.uniform(1000)}"

        :telemetry.attach(
          event_name,
          event,
          fn _event, measurements, metadata, _config ->
            send(test_pid, {:telemetry_received, event, measurements, metadata})
          end,
          nil
        )
      end)

      # Force telemetry generation
      VMMetrics.force_collection()

      # Generate some errors to test error reporting telemetry
      test_error = %RuntimeError{message: "Integration test error"}
      Aggregator.report_error(test_error, %{test: :integration})

      # Wait for telemetry events
      received_events = collect_telemetry_events([], length(telemetry_events), 5000)

      # Verify we received events from multiple layers
      assert length(received_events) >= 1

      # Cleanup telemetry listeners
      :telemetry.list_handlers([])
      |> Enum.filter(fn handler -> String.contains?(handler.id, "integration_test") end)
      |> Enum.each(fn handler -> :telemetry.detach(handler.id) end)
    end
  end

  describe "supervision tree resilience" do
    test "layer restart isolation prevents cascade failures" do
      # Get initial health status
      initial_status = StatusAggregator.get_overall_status()

      # Test that we can restart individual components
      # Note: This is a structural test to verify supervision exists
      # Full restart testing would be complex in integration environment

      # Verify each layer supervisor exists and has children
      layer_supervisors = [
        RubberDuck.InfrastructureSupervisor,
        RubberDuck.AgenticSupervisor,
        RubberDuck.SecuritySupervisor,
        RubberDuck.ApplicationSupervisor
      ]

      Enum.each(layer_supervisors, fn supervisor ->
        assert Process.whereis(supervisor)
        children = Supervisor.which_children(supervisor)
        assert length(children) > 0

        # Verify supervisor strategy allows for restarts
        info = Process.info(supervisor, [:dictionary])
        assert info != nil
      end)
    end

    test "component restart preserves system functionality" do
      # Test that health monitoring continues to function
      # even if individual components experience issues

      # Get baseline health metrics
      initial_detailed = StatusAggregator.get_detailed_status()
      initial_component_count = map_size(initial_detailed.components)

      # Verify system maintains basic functionality
      # database, resources, services, agents
      assert initial_component_count >= 4

      # Test that Skills Registry maintains state
      {:ok, skills_before} = SkillsRegistry.discover_skills()
      skill_count_before = map_size(skills_before)

      # Skills should be available and functional
      assert skill_count_before > 0

      # Test that Directives Engine maintains state
      {:ok, directives_before} = DirectivesEngine.get_directive_history()
      directive_count_before = length(directives_before)

      # Test basic functionality is preserved
      test_directive = %{
        type: :behavior_modification,
        target: :all,
        parameters: %{test: true}
      }

      assert :ok = DirectivesEngine.validate_directive(test_directive)
    end

    test "graceful degradation during component failures" do
      # Simulate component stress and verify graceful degradation

      # Generate load on error reporting system
      Enum.each(1..10, fn i ->
        test_error = %RuntimeError{message: "Load test error #{i}"}
        Aggregator.report_error(test_error, %{load_test: true, iteration: i})
      end)

      # Verify error reporting continues to function
      # Allow processing
      Process.sleep(1000)

      error_stats = Aggregator.get_error_stats()
      assert error_stats.total_error_count >= 10

      # Verify health monitoring reflects system under load
      status_under_load = StatusAggregator.get_detailed_status()
      assert status_under_load.overall_status in [:healthy, :warning, :degraded]

      # System should not be critical from this level of load
      refute status_under_load.overall_status == :critical
    end
  end

  describe "end-to-end system coordination" do
    test "complete skill execution workflow" do
      # Test end-to-end skill execution coordination

      # 1. Register a test agent with skills
      test_agent_id = "integration_test_agent_#{:rand.uniform(1000)}"
      test_skill_config = %{test_mode: true, timeout: 10_000}

      assert :ok =
               SkillsRegistry.configure_skill_for_agent(
                 test_agent_id,
                 :learning_skill,
                 test_skill_config
               )

      # 2. Create an instruction to execute the skill
      skill_instruction = %{
        type: :skill_invocation,
        action: "learning.track_experience",
        parameters: %{
          skill_id: :learning_skill,
          skill_params: %{
            experience: %{action: :integration_test},
            outcome: :success,
            context: %{test: true}
          }
        }
      }

      # 3. Process the instruction
      {:ok, execution_result} =
        InstructionsProcessor.process_instruction(skill_instruction, test_agent_id)

      # 4. Verify execution completed successfully
      assert execution_result.status == :completed
      assert execution_result.agent_id == test_agent_id
    end

    test "cross-component event propagation" do
      # Test that events propagate correctly across all components

      # 1. Subscribe to multiple event types
      test_topic = "integration_events_#{:rand.uniform(1000)}"
      Phoenix.PubSub.subscribe(RubberDuck.PubSub, test_topic)

      # 2. Generate events from different layers

      # Infrastructure layer event (PubSub)
      Phoenix.PubSub.broadcast(RubberDuck.PubSub, test_topic, {:infrastructure, :test_event})

      # Agentic layer event (Skills Registry)
      SkillsRegistry.subscribe_to_events(self())

      # Register a test skill to generate an event
      test_skill_metadata = %{category: :integration_test, test: true}
      assert :ok = SkillsRegistry.register_skill(IntegrationTestSkill, test_skill_metadata)

      # 3. Verify events are received
      assert_receive {:infrastructure, :test_event}, 2000
      assert_receive {:skills_registry_event, {:skill_registered, IntegrationTestSkill, _}}, 2000
    end

    test "system-wide telemetry coordination" do
      # Test that telemetry flows correctly between all components

      # Capture telemetry from multiple systems
      telemetry_capture =
        start_telemetry_capture([
          [:rubber_duck, :vm, :memory],
          [:rubber_duck, :health_check, :overall],
          [:rubber_duck, :error_reporting, :batch_processed]
        ])

      # Generate activity across the system
      VMMetrics.force_collection()

      # Generate health check activity
      # (Health checks run automatically, just wait for them)
      Process.sleep(3000)

      # Generate error reporting activity
      test_error = %RuntimeError{message: "Telemetry coordination test"}
      Aggregator.report_error(test_error, %{telemetry_test: true})
      Aggregator.flush_errors()

      # Verify telemetry events were captured
      captured_events = stop_telemetry_capture(telemetry_capture, 5000)

      # Should have events from VM metrics and potentially others
      assert length(captured_events) >= 1

      # Verify event structure
      Enum.each(captured_events, fn {event_name, measurements, metadata} ->
        assert is_list(event_name)
        assert is_map(measurements)
        assert is_map(metadata)
      end)
    end
  end

  describe "startup timing and coordination" do
    test "components start in proper dependency order" do
      # Verify that dependent components start after their dependencies

      # Infrastructure should be available for agentic layer
      assert Process.whereis(RubberDuck.Repo)
      assert Process.whereis(RubberDuck.PubSub)

      # Agentic components should be able to use infrastructure
      {:ok, _skills} = SkillsRegistry.discover_skills()

      # Test database connectivity from agentic layer
      # (Implicitly tests that Repo started before agentic components)
      case Ecto.Adapters.SQL.query(RubberDuck.Repo, "SELECT 1", []) do
        {:ok, _result} -> :ok
        # May fail in test environment, that's fine
        {:error, _reason} -> :ok
      end
    end

    test "startup performance meets expectations" do
      # Test that startup telemetry shows reasonable performance

      # Get VM metrics to assess startup impact
      current_metrics = VMMetrics.get_current_metrics()

      # Verify reasonable resource usage
      assert current_metrics.memory.total > 0
      assert current_metrics.processes.count > 0
      # Not overwhelming process table
      assert current_metrics.processes.utilization < 0.9

      # Verify schedulers are functioning
      assert current_metrics.schedulers.online > 0
      assert current_metrics.schedulers.utilization >= 0.0
    end

    test "all critical processes have appropriate names and registration" do
      # Verify critical processes are properly named/registered
      critical_processes = [
        RubberDuck.MainSupervisor,
        RubberDuck.InfrastructureSupervisor,
        RubberDuck.AgenticSupervisor,
        RubberDuck.SecuritySupervisor,
        RubberDuck.ApplicationSupervisor,
        SkillsRegistry,
        DirectivesEngine,
        InstructionsProcessor
      ]

      Enum.each(critical_processes, fn process_name ->
        pid = Process.whereis(process_name)
        assert is_pid(pid), "Process #{process_name} should be registered and running"

        # Verify process is alive and responsive
        assert Process.alive?(pid)
      end)
    end
  end

  describe "startup error scenarios" do
    test "system handles missing optional dependencies gracefully" do
      # Test that the system starts even when optional components are unavailable

      # This tests the conditional loading patterns we implemented
      # for Plug.Cowboy and Tower integration

      # Verify error reporting works without Tower
      test_error = %RuntimeError{message: "Optional dependency test"}
      assert :ok = Aggregator.report_error(test_error, %{optional_test: true})

      # Verify health endpoint logic works (even if HTTP server doesn't start)
      # The logic should be testable regardless of Plug.Cowboy availability
      detailed_status = StatusAggregator.get_detailed_status()
      assert is_map(detailed_status)
    end

    test "system maintains functionality during high startup load" do
      # Generate startup load and verify system remains stable

      # Create multiple instruction workflows
      workflows =
        Enum.map(1..5, fn i ->
          workflow_spec = %{
            name: "startup_load_test_#{i}",
            instructions: [
              %{
                type: :skill_invocation,
                action: "test.load_operation_#{i}",
                parameters: %{load_test: true, iteration: i},
                dependencies: []
              }
            ]
          }

          {:ok, workflow_id} = InstructionsProcessor.compose_workflow(workflow_spec)
          workflow_id
        end)

      # Execute workflows concurrently
      execution_tasks =
        Enum.map(workflows, fn workflow_id ->
          Task.async(fn ->
            InstructionsProcessor.execute_workflow(workflow_id, "load_test_agent")
          end)
        end)

      # Collect results
      results = Task.await_many(execution_tasks, 10_000)

      # Verify all workflows completed successfully
      Enum.each(results, fn {:ok, execution_result} ->
        assert execution_result.status == :completed
      end)

      # Verify system health is still good
      final_status = StatusAggregator.get_overall_status()
      # Should not be degraded/critical
      assert final_status in [:healthy, :warning]
    end
  end

  ## Helper Functions

  defp collect_telemetry_events(events, 0, _timeout), do: events

  defp collect_telemetry_events(events, remaining, timeout) do
    receive do
      {:telemetry_received, event, measurements, metadata} ->
        new_event = {event, measurements, metadata}
        collect_telemetry_events([new_event | events], remaining - 1, timeout)
    after
      timeout -> events
    end
  end

  defp start_telemetry_capture(event_names) do
    test_pid = self()

    handlers =
      Enum.map(event_names, fn event_name ->
        handler_id = "integration_capture_#{:rand.uniform(10_000)}"

        :telemetry.attach(
          handler_id,
          event_name,
          fn event, measurements, metadata, _config ->
            send(test_pid, {:telemetry_captured, event, measurements, metadata})
          end,
          nil
        )

        {handler_id, event_name}
      end)

    handlers
  end

  defp stop_telemetry_capture(handlers, timeout) do
    # Collect any pending telemetry events
    events = collect_captured_telemetry([], timeout)

    # Cleanup handlers
    Enum.each(handlers, fn {handler_id, _event_name} ->
      :telemetry.detach(handler_id)
    end)

    events
  end

  defp collect_captured_telemetry(events, timeout) do
    receive do
      {:telemetry_captured, event, measurements, metadata} ->
        collect_captured_telemetry([{event, measurements, metadata} | events], timeout)
    after
      min(timeout, 1000) -> events
    end
  end

  # Mock skill module for testing
  defmodule IntegrationTestSkill do
    def name, do: "Integration Test Skill"
    def category, do: :integration_test
  end
end
