defmodule RubberDuck.Telemetry.MLReporterTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Telemetry.MLReporter

  @moduletag capture_log: true

  describe "MLReporter" do
    setup do
      # Start the ML Reporter
      {:ok, reporter_pid} = MLReporter.start_link([])
      
      # Ensure it's running
      assert Process.alive?(reporter_pid)
      
      on_exit(fn ->
        if Process.alive?(reporter_pid) do
          GenServer.stop(reporter_pid)
        end
      end)
      
      %{reporter_pid: reporter_pid}
    end

    test "records prediction events", %{reporter_pid: _pid} do
      # Test prediction event recording
      assert :ok = MLReporter.record_prediction("classifier", 0.95, 150, %{test: true})
      
      # Allow some time for async processing
      Process.sleep(10)
    end

    test "records agent performance events", %{reporter_pid: _pid} do
      # Test agent performance recording
      assert :ok = MLReporter.record_agent_performance("agent_123", 0.87, 200, %{test: true})
      
      Process.sleep(10)
    end

    test "records business impact events", %{reporter_pid: _pid} do
      # Test business impact recording
      assert :ok = MLReporter.record_business_impact(8.5, 1000.0, "code_analysis", %{test: true})
      
      Process.sleep(10)
    end

    test "dispatches system metrics", %{reporter_pid: _pid} do
      # Test system metrics dispatch
      assert :ok = MLReporter.dispatch_system_metrics()
      
      Process.sleep(50)  # Allow time for async processing
    end

    test "handles telemetry events correctly" do
      # Setup telemetry event capture
      ref = :telemetry_test.attach_event_handlers(self(), [
        [:rubber_duck, :ml, :prediction],
        [:rubber_duck, :agent, :performance],
        [:rubber_duck, :impact, :business]
      ])
      
      # Start reporter
      {:ok, reporter_pid} = MLReporter.start_link([])
      
      # Generate events
      MLReporter.record_prediction("test_model", 0.9, 100)
      MLReporter.record_agent_performance("test_agent", 0.8, 250)
      MLReporter.record_business_impact(7.0, 500.0, "test_analysis")
      
      # Clean up
      :telemetry.detach(ref)
      GenServer.stop(reporter_pid)
    end
  end
end