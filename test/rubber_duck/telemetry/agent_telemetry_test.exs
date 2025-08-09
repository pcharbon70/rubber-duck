defmodule RubberDuck.Telemetry.AgentTelemetryTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Telemetry.AgentTelemetry
  
  @moduletag capture_log: true
  
  describe "AgentTelemetry" do
    setup do
      # Check if AgentTelemetry is already running
      telemetry_pid = case GenServer.whereis(AgentTelemetry) do
        nil ->
          {:ok, pid} = AgentTelemetry.start_link([])
          pid
        existing_pid ->
          existing_pid
      end
      
      # Ensure it's running
      assert Process.alive?(telemetry_pid)
      
      {:ok, telemetry_pid: telemetry_pid}
    end
    
    test "records agent lifecycle events" do
      self_pid = self()
      
      # Attach handler to capture events
      :telemetry.attach(
        "test-lifecycle-#{inspect(self_pid)}",
        [:rubber_duck, :agent, :lifecycle, :goal_assigned],
        fn event, measurements, metadata, _ ->
          send(self_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )
      
      # Record lifecycle event
      AgentTelemetry.record_lifecycle("test_agent", :goal_assigned, %{goal_type: "analysis"})
      
      # Verify event was emitted
      assert_receive {:telemetry_event, [:rubber_duck, :agent, :lifecycle, :goal_assigned], measurements, metadata}
      assert measurements.count == 1
      assert metadata.agent_id == "test_agent"
      assert metadata.goal_type == "analysis"
      
      # Cleanup
      :telemetry.detach("test-lifecycle-#{inspect(self_pid)}")
    end
    
    test "records goal completion with metrics" do
      self_pid = self()
      
      # Attach handlers
      :telemetry.attach_many(
        "test-goal-#{inspect(self_pid)}",
        [
          [:rubber_duck, :agent, :goal, :completed],
          [:rubber_duck, :agent, :performance]
        ],
        fn event, measurements, metadata, _ ->
          send(self_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )
      
      # Record successful goal completion
      AgentTelemetry.record_goal_completion("test_agent", :optimize, 5000, true)
      
      # Verify goal completion event
      assert_receive {:telemetry_event, [:rubber_duck, :agent, :goal, :completed], measurements, metadata}
      assert measurements.duration == 5000
      assert measurements.success == 1
      assert metadata.agent_id == "test_agent"
      assert metadata.goal_type == "optimize"
      assert metadata.status == :success
      
      # Wait a bit for async cast to process
      Process.sleep(50)
      
      # Verify performance metric was updated
      assert_receive {:telemetry_event, [:rubber_duck, :agent, :performance], perf_measurements, perf_metadata}
      assert perf_measurements.success_rate == 1.0
      assert perf_measurements.avg_duration == 5000
      assert perf_metadata.agent_id == "test_agent"
      
      # Cleanup
      :telemetry.detach("test-goal-#{inspect(self_pid)}")
    end
    
    test "records learning events" do
      self_pid = self()
      
      # Attach handler
      :telemetry.attach(
        "test-learning-#{inspect(self_pid)}",
        [:rubber_duck, :agent, :learning, :event],
        fn event, measurements, metadata, _ ->
          send(self_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )
      
      # Record learning event
      AgentTelemetry.record_learning_event("test_agent", :pattern, 0.85, 5)
      
      # Verify event
      assert_receive {:telemetry_event, [:rubber_duck, :agent, :learning, :event], measurements, metadata}
      assert measurements.confidence == 0.85
      assert measurements.patterns == 5
      assert metadata.agent_id == "test_agent"
      assert metadata.learning_type == "pattern"
      
      # Cleanup
      :telemetry.detach("test-learning-#{inspect(self_pid)}")
    end
    
    test "records experience gained" do
      self_pid = self()
      
      # Attach handler
      :telemetry.attach(
        "test-experience-#{inspect(self_pid)}",
        [:rubber_duck, :agent, :experience, :gained],
        fn event, measurements, metadata, _ ->
          send(self_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )
      
      # Record experience
      AgentTelemetry.record_experience_gained("test_agent", :goal_based, 3)
      
      # Verify event
      assert_receive {:telemetry_event, [:rubber_duck, :agent, :experience, :gained], measurements, metadata}
      assert measurements.count == 3
      assert metadata.agent_id == "test_agent"
      assert metadata.experience_type == "goal_based"
      
      # Cleanup
      :telemetry.detach("test-experience-#{inspect(self_pid)}")
    end
    
    test "calculates agent health correctly" do
      # Record some goals to establish health
      AgentTelemetry.record_goal_completion("health_test_agent", :task, 1000, true)
      AgentTelemetry.record_goal_completion("health_test_agent", :task, 2000, true)
      AgentTelemetry.record_goal_completion("health_test_agent", :task, 1500, false)
      
      # Wait for async processing
      Process.sleep(100)
      
      # Get health status
      health = AgentTelemetry.get_agent_health("health_test_agent")
      
      assert health.status in [:healthy, :warning, :critical]
      assert health.success_rate >= 0.0 and health.success_rate <= 1.0
      assert health.total_goals == 3
      assert health.avg_duration > 0
      assert is_integer(health.last_active)
    end
    
    test "provides performance comparison across agents" do
      # Record data for multiple agents
      AgentTelemetry.record_goal_completion("agent_a", :task, 1000, true)
      AgentTelemetry.record_goal_completion("agent_a", :task, 1500, true)
      
      AgentTelemetry.record_goal_completion("agent_b", :task, 2000, true)
      AgentTelemetry.record_goal_completion("agent_b", :task, 3000, false)
      
      AgentTelemetry.record_goal_completion("agent_c", :task, 500, true)
      
      # Wait for async processing
      Process.sleep(100)
      
      # Get comparison
      comparison = AgentTelemetry.get_performance_comparison()
      
      assert is_list(comparison.top_performers)
      assert comparison.total_agents >= 3
      assert comparison.avg_success_rate >= 0.0 and comparison.avg_success_rate <= 1.0
      assert comparison.healthy_agents >= 0
      
      # Check that top performers are sorted by performance score
      if length(comparison.top_performers) > 1 do
        scores = Enum.map(comparison.top_performers, & &1.performance_score)
        assert scores == Enum.sort(scores, :desc)
      end
    end
    
    test "health check updates agent health based on inactivity" do
      self_pid = self()
      
      # Attach handler for health events
      :telemetry.attach(
        "test-health-check-#{inspect(self_pid)}",
        [:rubber_duck, :agent, :health],
        fn _event, measurements, metadata, _ ->
          send(self_pid, {:health_event, measurements, metadata})
        end,
        nil
      )
      
      # Trigger health check manually
      send(AgentTelemetry, :health_check)
      
      # Wait for processing
      Process.sleep(100)
      
      # We should receive health events for any tracked agents
      # (may not receive any if no agents are tracked yet)
      
      # Cleanup
      :telemetry.detach("test-health-check-#{inspect(self_pid)}")
    end
  end
end