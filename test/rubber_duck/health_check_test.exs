defmodule RubberDuck.HealthCheckTest do
  use ExUnit.Case, async: false

  alias RubberDuck.HealthCheck.{
    AgentMonitor,
    DatabaseMonitor,
    ResourceMonitor,
    ServiceMonitor,
    StatusAggregator
  }

  describe "database monitor" do
    test "provides health status" do
      status = DatabaseMonitor.get_health_status()

      assert is_map(status)
      assert Map.has_key?(status, :status)
      assert Map.has_key?(status, :last_check)
      assert status.status in [:healthy, :warning, :degraded, :critical, :unknown]
    end

    test "can force health check" do
      # Force a check and verify it completes
      assert :ok = DatabaseMonitor.force_check()

      # Allow some time for the check to complete
      Process.sleep(100)

      status = DatabaseMonitor.get_health_status()
      assert status.last_check != nil
    end

    test "monitors database connectivity" do
      status = DatabaseMonitor.get_health_status()

      # Should have performance metrics if healthy
      if status.status == :healthy do
        assert Map.has_key?(status, :performance_metrics)
        assert Map.has_key?(status.performance_metrics, :query_response_time_ms)
      end
    end
  end

  describe "resource monitor" do
    test "provides resource health status" do
      status = ResourceMonitor.get_health_status()

      assert is_map(status)
      assert Map.has_key?(status, :status)
      assert Map.has_key?(status, :resource_metrics)
      assert status.status in [:healthy, :warning, :degraded, :critical, :unknown]
    end

    test "monitors memory usage" do
      status = ResourceMonitor.get_health_status()
      metrics = status.resource_metrics

      assert Map.has_key?(metrics, :memory)
      assert Map.has_key?(metrics.memory, :total)
      assert Map.has_key?(metrics.memory, :utilization)
      assert is_number(metrics.memory.utilization)
    end

    test "monitors process counts" do
      status = ResourceMonitor.get_health_status()
      metrics = status.resource_metrics

      assert Map.has_key?(metrics, :processes)
      assert Map.has_key?(metrics.processes, :count)
      assert Map.has_key?(metrics.processes, :limit)
      assert Map.has_key?(metrics.processes, :utilization)
      assert metrics.processes.count > 0
      assert metrics.processes.limit > metrics.processes.count
    end

    test "monitors atom table usage" do
      status = ResourceMonitor.get_health_status()
      metrics = status.resource_metrics

      assert Map.has_key?(metrics, :atoms)
      assert Map.has_key?(metrics.atoms, :count)
      assert Map.has_key?(metrics.atoms, :limit)
      assert Map.has_key?(metrics.atoms, :utilization)
      assert metrics.atoms.count > 0
    end

    test "can force resource check" do
      assert :ok = ResourceMonitor.force_check()

      Process.sleep(100)

      status = ResourceMonitor.get_health_status()
      assert status.last_check != nil
    end
  end

  describe "service monitor" do
    test "provides service health status" do
      status = ServiceMonitor.get_health_status()

      assert is_map(status)
      assert Map.has_key?(status, :status)
      assert Map.has_key?(status, :services)
      assert status.status in [:healthy, :warning, :degraded, :critical, :unknown]
    end

    test "monitors PubSub service" do
      status = ServiceMonitor.get_health_status()
      services = status.services

      assert Map.has_key?(services, :pubsub)
      pubsub_status = services.pubsub

      assert Map.has_key?(pubsub_status, :status)
      assert pubsub_status.status in [:healthy, :warning, :degraded, :critical]
    end

    test "monitors Oban service" do
      status = ServiceMonitor.get_health_status()
      services = status.services

      assert Map.has_key?(services, :oban)
      oban_status = services.oban

      assert Map.has_key?(oban_status, :status)
      assert oban_status.status in [:healthy, :warning, :degraded, :critical]
    end

    test "monitors agentic services" do
      status = ServiceMonitor.get_health_status()
      services = status.services

      # Check Skills Registry
      assert Map.has_key?(services, :skills_registry)

      # Check Directives Engine
      assert Map.has_key?(services, :directives_engine)

      # Check Instructions Processor
      assert Map.has_key?(services, :instructions_processor)
    end

    test "can force service check" do
      assert :ok = ServiceMonitor.force_check()

      Process.sleep(100)

      status = ServiceMonitor.get_health_status()
      assert status.last_check != nil
    end
  end

  describe "agent monitor" do
    test "provides agent health status" do
      status = AgentMonitor.get_health_status()

      assert is_map(status)
      assert Map.has_key?(status, :status)
      assert Map.has_key?(status, :agents)
      assert Map.has_key?(status, :performance)
      assert status.status in [:healthy, :warning, :degraded, :critical, :unknown]
    end

    test "monitors agent ecosystem" do
      status = AgentMonitor.get_health_status()
      agents = status.agents

      assert Map.has_key?(agents, :skills_registry_health)
      assert Map.has_key?(agents, :directives_engine_health)
      assert Map.has_key?(agents, :instructions_processor_health)
    end

    test "collects performance metrics" do
      status = AgentMonitor.get_health_status()
      performance = status.performance

      assert Map.has_key?(performance, :total_agent_processes)
      assert Map.has_key?(performance, :average_message_queue_length)
      assert Map.has_key?(performance, :agent_memory_usage)
      assert is_number(performance.total_agent_processes)
    end

    test "can register and unregister agents" do
      test_agent_id = "test_agent_#{:rand.uniform(10000)}"
      test_agent_pid = self()

      # Register agent
      assert :ok = AgentMonitor.register_agent(test_agent_id, test_agent_pid)

      # Unregister agent
      assert :ok = AgentMonitor.unregister_agent(test_agent_id)
    end
  end

  describe "status aggregator" do
    test "provides overall health status" do
      status = StatusAggregator.get_overall_status()

      assert status in [:healthy, :warning, :degraded, :critical, :unknown]
    end

    test "provides detailed status report" do
      detailed = StatusAggregator.get_detailed_status()

      assert is_map(detailed)
      assert Map.has_key?(detailed, :overall_status)
      assert Map.has_key?(detailed, :components)
      assert Map.has_key?(detailed, :summary)
      assert Map.has_key?(detailed, :last_update)
    end

    test "aggregates component statuses correctly" do
      detailed = StatusAggregator.get_detailed_status()
      components = detailed.components

      # Should have status from all monitors
      expected_components = [:database, :resources, :services, :agents]

      Enum.each(expected_components, fn component ->
        assert Map.has_key?(components, component)
        assert Map.has_key?(components[component], :status)
      end)
    end

    test "provides status summary" do
      detailed = StatusAggregator.get_detailed_status()
      summary = detailed.summary

      assert Map.has_key?(summary, :total_components)
      assert Map.has_key?(summary, :healthy)
      assert Map.has_key?(summary, :warning)
      assert Map.has_key?(summary, :degraded)
      assert Map.has_key?(summary, :critical)
      assert Map.has_key?(summary, :health_percentage)

      assert summary.total_components > 0
      assert is_number(summary.health_percentage)
    end

    test "maintains status history" do
      history = StatusAggregator.get_status_history(5)

      assert is_list(history)
      # History might be empty initially, that's okay
    end
  end

  describe "telemetry integration" do
    test "emits health check telemetry events" do
      test_pid = self()

      # Listen for health check telemetry
      :telemetry.attach(
        "test-health-check",
        [:rubber_duck, :health_check, :overall],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, measurements, metadata})
        end,
        nil
      )

      # Force status aggregation (this should emit telemetry)
      # We can't directly force aggregation, but we can check if telemetry is working
      # by waiting for the next scheduled aggregation

      # Wait for telemetry event
      receive do
        {:telemetry, measurements, metadata} ->
          assert is_map(measurements)
          assert is_map(metadata)
          assert Map.has_key?(measurements, :status_numeric)
          assert Map.has_key?(metadata, :status)
      after
        # 10 seconds should be enough for at least one aggregation cycle
        10_000 ->
          flunk("No health check telemetry received within timeout")
      end

      # Cleanup
      :telemetry.detach("test-health-check")
    end
  end

  describe "error conditions" do
    test "handles monitor failures gracefully" do
      # Get initial status
      initial_status = StatusAggregator.get_detailed_status()

      # Should have some components reporting
      assert map_size(initial_status.components) > 0

      # Even if some components fail, others should still report
      # This is more of a structural test
    end

    test "provides reasonable defaults for unavailable data" do
      # Force checks on all monitors to ensure they handle edge cases
      DatabaseMonitor.force_check()
      ResourceMonitor.force_check()
      ServiceMonitor.force_check()
      AgentMonitor.force_check()

      # Allow time for checks to complete
      Process.sleep(200)

      # All should provide valid status
      db_status = DatabaseMonitor.get_health_status()
      resource_status = ResourceMonitor.get_health_status()
      service_status = ServiceMonitor.get_health_status()
      agent_status = AgentMonitor.get_health_status()

      assert db_status.status in [:healthy, :warning, :degraded, :critical]
      assert resource_status.status in [:healthy, :warning, :degraded, :critical]
      assert service_status.status in [:healthy, :warning, :degraded, :critical]
      assert agent_status.status in [:healthy, :warning, :degraded, :critical]
    end
  end
end
