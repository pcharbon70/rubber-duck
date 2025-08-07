defmodule RubberDuck.Routing.RouterBenchmarkTest do
  @moduledoc """
  Benchmark tests comparing runtime vs compile-time routing performance.
  """
  use ExUnit.Case, async: false

  alias RubberDuck.Routing.MessageRouter
  alias RubberDuck.Routing.EnhancedMessageRouter

  @iterations 10_000
  @batch_size 100

  setup do
    # Create sample messages for benchmarking
    messages = [
      %RubberDuck.Messages.Code.Analyze{
        file_path: "/test/file.ex",
        analysis_type: :security
      },
      %RubberDuck.Messages.Learning.RecordExperience{
        agent_id: "test_agent",
        action: "test_action",
        outcome: %{success: true}
      },
      %RubberDuck.Messages.Project.UpdateStatus{
        project_id: "test-123",
        status: :active,
        metadata: %{}
      },
      %RubberDuck.Messages.User.ValidateSession{
        session_id: "session-456",
        user_id: "user-789"
      }
    ]

    {:ok, messages: messages}
  end

  describe "single message routing performance" do
    test "runtime routing performance", %{messages: messages} do
      message = List.first(messages)

      {time_microseconds, _} =
        :timer.tc(fn ->
          for _ <- 1..@iterations do
            # Simulate runtime routing with map lookup
            module = message.__struct__
            _route = Map.get(get_routes(), module)
            _function = determine_handler_function(module)
          end
        end)

      time_ms = time_microseconds / 1000
      ops_per_second = @iterations * 1000 / time_ms

      IO.puts("\nRuntime Routing Performance:")
      IO.puts("  Time for #{@iterations} iterations: #{Float.round(time_ms, 2)}ms")
      IO.puts("  Operations per second: #{Float.round(ops_per_second, 0)}")

      assert time_ms < 1000, "Runtime routing should complete in under 1 second"
    end

    test "compile-time routing performance", %{messages: messages} do
      message = List.first(messages)

      {time_microseconds, _} =
        :timer.tc(fn ->
          for _ <- 1..@iterations do
            # Compile-time routing - just pattern matching
            EnhancedMessageRouter.dispatch_fast(message, %{})
          end
        end)

      time_ms = time_microseconds / 1000
      ops_per_second = @iterations * 1000 / time_ms

      IO.puts("\nCompile-Time Routing Performance:")
      IO.puts("  Time for #{@iterations} iterations: #{Float.round(time_ms, 2)}ms")
      IO.puts("  Operations per second: #{Float.round(ops_per_second, 0)}")

      assert time_ms < 200, "Compile-time routing should complete in under 200ms"
    end
  end

  describe "batch routing performance" do
    test "runtime batch routing", %{messages: messages} do
      # Create a batch of messages
      stream = Stream.cycle(messages)
      batch = stream |> Enum.take(@batch_size)
      iterations_div_100 = div(@iterations, 100)

      {time_microseconds, _results} =
        :timer.tc(fn ->
          for _ <- 1..iterations_div_100 do
            # Simulate runtime batch routing
            Enum.map(batch, fn message ->
              module = message.__struct__
              _route = Map.get(get_routes(), module)
              _function = determine_handler_function(module)
              {:ok, :processed}
            end)
          end
        end)

      time_ms = time_microseconds / 1000
      messages_per_second = iterations_div_100 * @batch_size * 1000 / time_ms

      IO.puts("\nRuntime Batch Routing Performance:")
      IO.puts("  Time for #{iterations_div_100} batches: #{Float.round(time_ms, 2)}ms")
      IO.puts("  Messages per second: #{Float.round(messages_per_second, 0)}")

      assert messages_per_second > 1000, "Should process at least 1000 messages/second"
    end

    test "compile-time batch routing", %{messages: messages} do
      # Create a batch of messages
      stream = Stream.cycle(messages)
      batch = stream |> Enum.take(@batch_size)
      iterations_div_100 = div(@iterations, 100)

      {time_microseconds, _results} =
        :timer.tc(fn ->
          for _ <- 1..iterations_div_100 do
            # Compile-time batch routing
            EnhancedMessageRouter.dispatch_batch(batch, max_concurrency: 4)
          end
        end)

      time_ms = time_microseconds / 1000
      messages_per_second = iterations_div_100 * @batch_size * 1000 / time_ms

      IO.puts("\nCompile-Time Batch Routing Performance:")
      IO.puts("  Time for #{iterations_div_100} batches: #{Float.round(time_ms, 2)}ms")
      IO.puts("  Messages per second: #{Float.round(messages_per_second, 0)}")

      assert messages_per_second > 5000, "Should process at least 5000 messages/second"
    end
  end

  describe "performance comparison" do
    test "compile-time routing should be at least 3x faster", %{messages: messages} do
      message = List.first(messages)

      # Measure runtime routing
      {runtime_us, _} =
        :timer.tc(fn ->
          for _ <- 1..1000 do
            module = message.__struct__
            _route = Map.get(get_routes(), module)
            _function = determine_handler_function(module)
          end
        end)

      # Measure compile-time routing
      {compile_time_us, _} =
        :timer.tc(fn ->
          for _ <- 1..1000 do
            EnhancedMessageRouter.dispatch_fast(message, %{})
          end
        end)

      speedup = runtime_us / compile_time_us

      IO.puts("\nPerformance Comparison:")
      IO.puts("  Runtime: #{runtime_us}μs")
      IO.puts("  Compile-time: #{compile_time_us}μs")
      IO.puts("  Speedup: #{Float.round(speedup, 2)}x")

      assert speedup >= 3.0, "Compile-time routing should be at least 3x faster"
    end
  end

  # Helper functions

  defp get_routes do
    %{
      RubberDuck.Messages.Code.Analyze => RubberDuck.Skills.CodeAnalysisSkill,
      RubberDuck.Messages.Learning.RecordExperience => RubberDuck.Skills.LearningSkill,
      RubberDuck.Messages.Project.UpdateStatus => RubberDuck.Skills.ProjectManagementSkill,
      RubberDuck.Messages.User.ValidateSession => RubberDuck.Skills.UserManagementSkill
    }
  end

  defp determine_handler_function(message_module) do
    message_module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> then(&:"handle_#{&1}")
  end
end
