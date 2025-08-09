defmodule RubberDuck.Telemetry.ActionTelemetryTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Telemetry.ActionTelemetry

  describe "span/3" do
    test "emits start and stop events for successful execution" do
      self_pid = self()
      
      # Attach test handler to capture events
      :telemetry.attach_many(
        "test-handler-#{inspect(self_pid)}",
        [
          [:test, :action, :start],
          [:test, :action, :stop]
        ],
        fn event, measurements, metadata, _ ->
          send(self_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      # Execute span with successful function
      result = ActionTelemetry.span(
        [:test, :action],
        %{action_type: "test_action", resource: "test_resource"},
        fn ->
          {:ok, "success"}
        end
      )

      # Verify result
      assert result == {:ok, "success"}

      # Verify start event was emitted
      assert_receive {:telemetry_event, [:test, :action, :start], start_measurements, start_metadata}
      assert is_integer(start_measurements.monotonic_time)
      assert start_metadata.action_type == "test_action"
      assert start_metadata.resource == "test_resource"
      assert is_integer(start_metadata.system_time)

      # Verify stop event was emitted
      assert_receive {:telemetry_event, [:test, :action, :stop], stop_measurements, stop_metadata}
      assert is_integer(stop_measurements.duration)
      assert stop_measurements.duration > 0
      assert is_integer(stop_measurements.monotonic_time)
      assert stop_metadata.action_type == "test_action"
      assert stop_metadata.resource == "test_resource"
      assert stop_metadata.status == :success

      # Cleanup
      :telemetry.detach("test-handler-#{inspect(self_pid)}")
    end

    test "emits start and exception events for failed execution" do
      self_pid = self()
      
      # Attach test handler to capture events
      :telemetry.attach_many(
        "test-handler-exception-#{inspect(self_pid)}",
        [
          [:test, :action, :start],
          [:test, :action, :exception]
        ],
        fn event, measurements, metadata, _ ->
          send(self_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      # Execute span with failing function
      assert_raise RuntimeError, "test error", fn ->
        ActionTelemetry.span(
          [:test, :action],
          %{action_type: "test_action", resource: "test_resource"},
          fn ->
            raise "test error"
          end
        )
      end

      # Verify start event was emitted
      assert_receive {:telemetry_event, [:test, :action, :start], start_measurements, start_metadata}
      assert is_integer(start_measurements.monotonic_time)
      assert start_metadata.action_type == "test_action"

      # Verify exception event was emitted
      assert_receive {:telemetry_event, [:test, :action, :exception], exception_measurements, exception_metadata}
      assert is_integer(exception_measurements.duration)
      assert exception_measurements.duration > 0
      assert exception_metadata.action_type == "test_action"
      assert exception_metadata.error =~ "test error"
      assert exception_metadata.kind == :error

      # Cleanup
      :telemetry.detach("test-handler-exception-#{inspect(self_pid)}")
    end

    test "correctly determines status from various result formats" do
      self_pid = self()
      
      # Attach test handler
      :telemetry.attach(
        "test-handler-status-#{inspect(self_pid)}",
        [:test, :action, :stop],
        fn _event, _measurements, metadata, _ ->
          send(self_pid, {:status, metadata.status})
        end,
        nil
      )

      # Test {:ok, _} result
      ActionTelemetry.span([:test, :action], %{}, fn -> {:ok, "data"} end)
      assert_receive {:status, :success}

      # Test {:error, _} result
      ActionTelemetry.span([:test, :action], %{}, fn -> {:error, "reason"} end)
      assert_receive {:status, :error}

      # Test :ok result
      ActionTelemetry.span([:test, :action], %{}, fn -> :ok end)
      assert_receive {:status, :success}

      # Test :error result
      ActionTelemetry.span([:test, :action], %{}, fn -> :error end)
      assert_receive {:status, :error}

      # Test other result
      ActionTelemetry.span([:test, :action], %{}, fn -> "other" end)
      assert_receive {:status, :unknown}

      # Cleanup
      :telemetry.detach("test-handler-status-#{inspect(self_pid)}")
    end
  end

  describe "event/3" do
    test "emits telemetry event with measurements and metadata" do
      self_pid = self()
      
      # Attach test handler
      :telemetry.attach(
        "test-handler-event-#{inspect(self_pid)}",
        [:test, :custom, :event],
        fn event, measurements, metadata, _ ->
          send(self_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      # Emit event
      ActionTelemetry.event(
        [:test, :custom, :event],
        %{value: 42, count: 10},
        %{tag: "test_tag"}
      )

      # Verify event was emitted
      assert_receive {:telemetry_event, [:test, :custom, :event], measurements, metadata}
      assert measurements.value == 42
      assert measurements.count == 10
      assert metadata.tag == "test_tag"

      # Cleanup
      :telemetry.detach("test-handler-event-#{inspect(self_pid)}")
    end

    test "works with empty metadata" do
      self_pid = self()
      
      # Attach test handler
      :telemetry.attach(
        "test-handler-empty-#{inspect(self_pid)}",
        [:test, :empty],
        fn event, measurements, metadata, _ ->
          send(self_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      # Emit event without metadata
      ActionTelemetry.event([:test, :empty], %{value: 1})

      # Verify event was emitted with empty metadata
      assert_receive {:telemetry_event, [:test, :empty], measurements, metadata}
      assert measurements.value == 1
      assert metadata == %{}

      # Cleanup
      :telemetry.detach("test-handler-empty-#{inspect(self_pid)}")
    end
  end

  describe "handle_event/4" do
    test "handles action start events" do
      self_pid = self()
      
      # Attach handler to verify the count metric is emitted
      :telemetry.attach(
        "test-start-count-#{inspect(self_pid)}",
        [:rubber_duck, :action, :count],
        fn _event, measurements, metadata, _ ->
          send(self_pid, {:count_metric, measurements, metadata})
        end,
        nil
      )
      
      # Handle start event
      ActionTelemetry.handle_event(
        [:rubber_duck, :action, :start],
        %{monotonic_time: System.monotonic_time()},
        %{action_type: "test", resource: "user"},
        nil
      )
      
      # Verify count metric was emitted with started status
      assert_receive {:count_metric, %{value: 1}, metadata}
      assert metadata.status == :started
      assert metadata.action_type == "test"
      assert metadata.resource == "user"
      
      # Cleanup
      :telemetry.detach("test-start-count-#{inspect(self_pid)}")
    end

    test "handles action stop events and emits metrics" do
      self_pid = self()
      
      # Attach handler to capture secondary metrics
      :telemetry.attach_many(
        "test-metrics-#{inspect(self_pid)}",
        [
          [:rubber_duck, :action, :count],
          [:rubber_duck, :action, :duration],
          [:rubber_duck, :action, :execution_time]
        ],
        fn event, measurements, metadata, _ ->
          send(self_pid, {:metric, event, measurements, metadata})
        end,
        nil
      )

      # Handle stop event
      ActionTelemetry.handle_event(
        [:rubber_duck, :action, :stop],
        %{duration: 1_000_000}, # 1ms in native time
        %{action_type: "test", resource: "user"},
        nil
      )

      # Verify metrics were emitted
      assert_receive {:metric, [:rubber_duck, :action, :count], %{value: 1}, metadata}
      assert metadata.status in [:success, :unknown]
      
      assert_receive {:metric, [:rubber_duck, :action, :duration], %{value: duration_ms}, _}
      assert is_number(duration_ms)
      
      assert_receive {:metric, [:rubber_duck, :action, :execution_time], %{value: exec_time}, _}
      assert is_number(exec_time)

      # Cleanup
      :telemetry.detach("test-metrics-#{inspect(self_pid)}")
    end

    test "handles action exception events" do
      self_pid = self()
      
      # Attach handler to capture metrics
      :telemetry.attach_many(
        "test-exception-metrics-#{inspect(self_pid)}",
        [
          [:rubber_duck, :action, :count],
          [:rubber_duck, :action, :duration]
        ],
        fn event, measurements, metadata, _ ->
          send(self_pid, {:metric, event, measurements, metadata})
        end,
        nil
      )

      # Handle exception event
      assert capture_log(fn ->
        ActionTelemetry.handle_event(
          [:rubber_duck, :action, :exception],
          %{duration: 1_000_000},
          %{action_type: "test", resource: "user", error: "RuntimeError"},
          nil
        )
      end) =~ "Action failed: test on user"

      # Verify failure metrics were emitted
      assert_receive {:metric, [:rubber_duck, :action, :count], %{value: 1}, metadata}
      assert metadata.status == :failure
      
      assert_receive {:metric, [:rubber_duck, :action, :duration], %{value: _}, metadata}
      assert metadata.status == :failure

      # Cleanup
      :telemetry.detach("test-exception-metrics-#{inspect(self_pid)}")
    end
  end

  # Helper to capture logs
  defp capture_log(fun) do
    ExUnit.CaptureLog.capture_log(fun)
  end
end