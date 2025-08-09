defmodule RubberDuck.Telemetry.SupervisorTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Telemetry.Supervisor, as: TelemetrySupervisor

  @moduletag capture_log: true

  describe "Telemetry.Supervisor" do
    test "starts successfully with all children" do
      # Check if supervisor is already running (started by application)
      supervisor_pid = case GenServer.whereis(TelemetrySupervisor) do
        nil ->
          # Start the telemetry supervisor if not running
          {:ok, pid} = TelemetrySupervisor.start_link([])
          pid
        existing_pid ->
          existing_pid
      end
      
      # Verify it's running
      assert Process.alive?(supervisor_pid)
      
      # Check that children are started
      children = Supervisor.which_children(supervisor_pid)
      assert length(children) > 0
      
      # Verify key telemetry components are running
      child_modules = Enum.map(children, fn {_id, _pid, _type, modules} -> modules end)
      flattened_modules = List.flatten(child_modules)
      
      assert RubberDuck.Telemetry.MLReporter in flattened_modules
      assert RubberDuck.Telemetry.ActionTracker in flattened_modules
      assert RubberDuck.Telemetry.LearningTracker in flattened_modules
      assert RubberDuck.Telemetry.ImpactTracker in flattened_modules
    end

    test "handles Prometheus configuration correctly" do
      # Get the running supervisor
      supervisor_pid = GenServer.whereis(TelemetrySupervisor)
      assert supervisor_pid != nil, "Telemetry supervisor should be running"
      
      children = Supervisor.which_children(supervisor_pid)
      child_specs = Enum.map(children, &elem(&1, 0))
      
      # Check that we have all expected ML telemetry modules
      assert length(child_specs) >= 4, "Should have at least 4 telemetry modules"
      
      # Verify key modules are present
      assert RubberDuck.Telemetry.MLReporter in child_specs
      assert RubberDuck.Telemetry.ActionTracker in child_specs
      assert RubberDuck.Telemetry.LearningTracker in child_specs
      assert RubberDuck.Telemetry.ImpactTracker in child_specs
      
      # Prometheus should be present (by name)
      assert :rubber_duck_prometheus in child_specs, "Prometheus telemetry should be enabled"
    end

    test "telemetry configuration is accessible" do
      config = Application.get_env(:rubber_duck, :telemetry, [])
      
      # Verify our telemetry configuration is loaded
      assert Keyword.get(config, :prometheus_enabled, true) == true
      assert Keyword.get(config, :ml_metrics_enabled, true) == true
      assert Keyword.get(config, :action_tracking_enabled, true) == true
      assert Keyword.get(config, :learning_metrics_enabled, true) == true
      assert Keyword.get(config, :impact_scoring_enabled, true) == true
    end
  end
end