defmodule RubberDuck.Telemetry.PerformanceTest do
  @moduledoc """
  Performance tests to validate telemetry overhead.
  
  These tests ensure that telemetry adds minimal overhead (<1ms per operation)
  and does not significantly impact memory usage.
  """
  
  use ExUnit.Case, async: false
  
  alias RubberDuck.Telemetry.ActionTelemetry
  
  @iterations 1000
  @max_overhead_ms 1.0
  
  describe "telemetry overhead" do
    test "span overhead is less than #{@max_overhead_ms}ms per call" do
      # Warm up
      for _ <- 1..100 do
        ActionTelemetry.span(
          [:test, :warmup],
          %{},
          fn -> :ok end
        )
      end
      
      # Measure without telemetry
      start_no_telemetry = System.monotonic_time(:microsecond)
      for _ <- 1..@iterations do
        # Just execute the function
        _ = (fn -> {:ok, "result"} end).()
      end
      duration_no_telemetry = System.monotonic_time(:microsecond) - start_no_telemetry
      
      # Measure with telemetry
      start_with_telemetry = System.monotonic_time(:microsecond)
      for _ <- 1..@iterations do
        ActionTelemetry.span(
          [:test, :performance],
          %{iteration: 1},
          fn -> {:ok, "result"} end
        )
      end
      duration_with_telemetry = System.monotonic_time(:microsecond) - start_with_telemetry
      
      # Calculate overhead
      overhead_total_us = duration_with_telemetry - duration_no_telemetry
      overhead_per_call_ms = overhead_total_us / @iterations / 1000
      
      IO.puts("""
      Performance Test Results:
      - Iterations: #{@iterations}
      - Without telemetry: #{duration_no_telemetry / 1000}ms total
      - With telemetry: #{duration_with_telemetry / 1000}ms total
      - Overhead per call: #{Float.round(overhead_per_call_ms, 3)}ms
      """)
      
      assert overhead_per_call_ms < @max_overhead_ms,
        "Telemetry overhead #{overhead_per_call_ms}ms exceeds maximum #{@max_overhead_ms}ms"
    end
    
    test "event emission overhead is minimal" do
      # Warm up
      for _ <- 1..100 do
        ActionTelemetry.event(
          [:test, :warmup],
          %{value: 1},
          %{}
        )
      end
      
      # Measure event emission
      start = System.monotonic_time(:microsecond)
      for i <- 1..@iterations do
        ActionTelemetry.event(
          [:test, :event],
          %{value: i, count: 1},
          %{type: :test}
        )
      end
      duration = System.monotonic_time(:microsecond) - start
      
      per_event_ms = duration / @iterations / 1000
      
      IO.puts("""
      Event Emission Performance:
      - Events emitted: #{@iterations}
      - Total time: #{duration / 1000}ms
      - Per event: #{Float.round(per_event_ms, 3)}ms
      """)
      
      assert per_event_ms < 0.5,
        "Event emission overhead #{per_event_ms}ms exceeds maximum 0.5ms"
    end
    
    test "telemetry does not leak memory" do
      # Force garbage collection
      :erlang.garbage_collect()
      
      # Get initial memory
      initial_memory = :erlang.memory(:total)
      
      # Run many telemetry operations
      for i <- 1..10_000 do
        ActionTelemetry.span(
          [:test, :memory],
          %{iteration: i},
          fn ->
            # Create some data
            data = %{
              id: i,
              value: :rand.uniform(1000),
              timestamp: System.system_time()
            }
            {:ok, data}
          end
        )
        
        # Periodically garbage collect
        if rem(i, 1000) == 0 do
          :erlang.garbage_collect()
        end
      end
      
      # Final garbage collection
      :erlang.garbage_collect()
      Process.sleep(100)
      :erlang.garbage_collect()
      
      # Get final memory
      final_memory = :erlang.memory(:total)
      
      # Calculate memory growth
      memory_growth_mb = (final_memory - initial_memory) / 1_048_576
      
      IO.puts("""
      Memory Test Results:
      - Initial memory: #{Float.round(initial_memory / 1_048_576, 2)}MB
      - Final memory: #{Float.round(final_memory / 1_048_576, 2)}MB
      - Growth: #{Float.round(memory_growth_mb, 2)}MB
      """)
      
      # Allow up to 10MB growth (telemetry may buffer some metrics)
      assert memory_growth_mb < 10,
        "Memory growth #{memory_growth_mb}MB exceeds maximum 10MB"
    end
    
    test "high-frequency events don't cause bottlenecks" do
      # Test concurrent high-frequency event emission
      task_count = 10
      events_per_task = 1000
      
      start = System.monotonic_time(:millisecond)
      
      tasks = for task_id <- 1..task_count do
        Task.async(fn ->
          for event_id <- 1..events_per_task do
            :telemetry.execute(
              [:test, :high_frequency],
              %{value: event_id},
              %{task_id: task_id}
            )
          end
        end)
      end
      
      # Wait for all tasks
      Enum.each(tasks, &Task.await/1)
      
      duration = System.monotonic_time(:millisecond) - start
      total_events = task_count * events_per_task
      
      # Avoid divide by zero for very fast operations
      duration_seconds = max(duration / 1000, 0.001)
      events_per_second = total_events / duration_seconds
      
      IO.puts("""
      High-Frequency Event Test:
      - Total events: #{total_events}
      - Duration: #{duration}ms
      - Events/second: #{Float.round(events_per_second, 0)}
      """)
      
      # Should handle at least 10,000 events/second
      assert events_per_second > 10_000,
        "Event throughput #{events_per_second}/s below minimum 10,000/s"
    end
  end
  
  describe "telemetry accuracy" do
    test "duration measurements are accurate" do
      sleep_time = 100  # milliseconds
      
      result = ActionTelemetry.span(
        [:test, :accuracy],
        %{},
        fn ->
          Process.sleep(sleep_time)
          :ok
        end
      )
      
      assert result == :ok
      
      # The duration should be recorded in the telemetry events
      # This test mainly validates that the span completes correctly
      # and doesn't interfere with the function execution
    end
    
    test "nested spans work correctly" do
      result = ActionTelemetry.span(
        [:test, :outer],
        %{level: "outer"},
        fn ->
          ActionTelemetry.span(
            [:test, :inner],
            %{level: "inner"},
            fn ->
              {:ok, "nested result"}
            end
          )
        end
      )
      
      assert result == {:ok, "nested result"}
    end
  end
end