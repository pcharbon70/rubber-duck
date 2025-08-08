defmodule RubberDuck.Skills.CodeAnalysisSkillPerformanceIntegrationTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Skills.CodeAnalysisSkill
  alias RubberDuck.Messages.Code.{Analyze, PerformanceAnalyze}

  describe "integration with Performance analyzer" do
    test "performance analysis via Analyze message" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :performance,
        depth: :moderate,
        auto_fix: false
      }

      context = %{
        content: """
        def slow_function(data) do
          for item <- data do
            for sub_item <- item.children do
              expensive_operation(sub_item)
            end
          end
        end
        """,
        state: %{}
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)
      assert Map.has_key?(result, :performance)
      assert is_map(result.performance)
      assert Map.has_key?(result.performance, :time_complexity)
      assert Map.has_key?(result.performance, :bottlenecks)
    end

    test "comprehensive analysis includes performance" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :comprehensive,
        depth: :moderate,
        auto_fix: false
      }

      context = %{
        content:
          "def inefficient, do: Enum.map(data, &Enum.filter(&1, fn x -> expensive(x) end))",
        state: %{}
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)
      assert Map.has_key?(result, :performance)
      assert is_map(result.performance)
    end

    test "PerformanceAnalyze message delegation" do
      message = %PerformanceAnalyze{
        content: """
        def bubble_sort(list) do
          for x <- list do
            for y <- list do
              compare(x, y)
            end
          end
        end
        """,
        metrics: [:complexity, :hotspots]
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_performance_analyze(message, %{})
      assert Map.has_key?(result, :complexity_analysis)
      assert result.complexity_analysis.complexity == :quadratic
    end

    test "legacy signal handler for code.performance.analyze" do
      signal = %{
        type: "code.performance.analyze",
        data: %{
          content: """
          def recursive_fibonacci(0), do: 0
          def recursive_fibonacci(1), do: 1
          def recursive_fibonacci(n), do: recursive_fibonacci(n-1) + recursive_fibonacci(n-2)
          """,
          metrics: [:complexity, :optimizations]
        }
      }

      state = %{}

      assert {:ok, performance_result, _updated_state} =
               CodeAnalysisSkill.handle_signal(signal, state)

      assert Map.has_key?(performance_result, :complexity_analysis)
      assert performance_result.complexity_analysis.has_recursion
    end

    test "legacy signal handler for code.analyze.file with performance enabled" do
      signal = %{
        type: "code.analyze.file",
        data: %{
          file_path: "test.ex",
          content: """
          def process_data(items) do
            items
            |> Enum.map(&transform_item/1)
            |> Enum.filter(&valid_item?/1)
            |> Enum.map(&save_item/1)
          end
          """
        }
      }

      state = %{opts: %{performance_check: true}}

      assert {:ok, analysis_result, _updated_state} =
               CodeAnalysisSkill.handle_signal(signal, state)

      assert Map.has_key?(analysis_result, :performance)
      assert is_map(analysis_result.performance)
      assert Map.has_key?(analysis_result.performance, :bottlenecks)
    end

    test "performance analysis disabled in legacy signal" do
      signal = %{
        type: "code.analyze.file",
        data: %{
          file_path: "test.ex",
          content: "def simple_function, do: :ok"
        }
      }

      state = %{opts: %{performance_check: false}}

      assert {:ok, result, _updated_state} = CodeAnalysisSkill.handle_signal(signal, state)
      refute Map.has_key?(result, :performance)
    end
  end

  describe "error handling" do
    test "handles performance analyzer errors gracefully in perform_performance_analysis" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :performance,
        depth: :moderate,
        auto_fix: false
      }

      # Empty context should still work but with limited functionality
      context = %{}

      assert {:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)
      assert Map.has_key?(result, :performance)
      assert is_map(result.performance)
    end

    test "handles PerformanceAnalyze errors gracefully" do
      # Test with nil content (should be handled gracefully)
      message = %PerformanceAnalyze{
        content: nil,
        metrics: [:complexity]
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_performance_analyze(message, %{})
      assert Map.has_key?(result, :hot_spots)
    end
  end
end
