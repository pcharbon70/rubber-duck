defmodule RubberDuck.TelemetryTest do
  use ExUnit.Case

  describe "Telemetry supervisor" do
    test "telemetry supervisor starts successfully" do
      assert Process.whereis(RubberDuck.Telemetry) != nil
    end

    test "telemetry metrics are defined" do
      metrics = RubberDuck.Telemetry.metrics()
      assert is_list(metrics)
      assert length(metrics) > 0

      # Check for key metric types
      metric_names = Enum.map(metrics, & &1.name)

      # VM metrics
      assert [:vm, :memory, :total] in metric_names
      assert [:vm, :total_run_queue_lengths, :total] in metric_names

      # Application metrics
      assert [:rubber_duck, :health, :database] in metric_names
      assert [:rubber_duck, :repo, :queue_size] in metric_names
    end

    test "periodic measurements are configured" do
      # The telemetry poller should be running
      assert Process.whereis(:rubber_duck_poller) != nil
    end
  end

  describe "Telemetry events" do
    test "health check telemetry is emitted" do
      # Set up telemetry handler
      handler_id = :test_health_handler

      events = [
        [:rubber_duck, :health, :database],
        [:rubber_duck, :health, :services]
      ]

      :telemetry.attach_many(
        handler_id,
        events,
        fn event, measurements, _metadata, config ->
          send(config.test_pid, {:telemetry_event, event, measurements})
        end,
        %{test_pid: self()}
      )

      # Trigger health check
      RubberDuck.Telemetry.dispatch_health_check()

      # Verify events were received
      assert_receive {:telemetry_event, [:rubber_duck, :health, :database], %{value: _}}, 1000
      assert_receive {:telemetry_event, [:rubber_duck, :health, :services], %{value: _}}, 1000

      # Cleanup
      :telemetry.detach(handler_id)
    end

    test "repo metrics function executes without error" do
      # Simply verify the function can be called without crashing
      # The actual metrics emission depends on repo state
      assert :ok = RubberDuck.Telemetry.dispatch_repo_metrics()
    end
  end
end
