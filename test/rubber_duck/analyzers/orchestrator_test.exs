defmodule RubberDuck.Analyzers.OrchestratorTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Analyzers.Orchestrator
  alias RubberDuck.Messages.Code.Analyze

  describe "orchestrate/1" do
    setup do
      request = %{
        file_path: "lib/example.ex",
        content: """
        defmodule Example do
          def unsafe_query(user_input) do
            Repo.query("SELECT * FROM users WHERE name = '\#{user_input}'")
          end
          
          def complex_function(a, b, c, d, e, f) do
            result = a + b * c - d / e + f
            if result > 100 do
              nested_value = Enum.reduce(1..100, 0, fn i, acc ->
                if rem(i, 2) == 0 do
                  acc + i * result
                else
                  acc - i
                end
              end)
              nested_value * result
            else
              result
            end
          end
        end
        """,
        analyzers: :all,
        strategy: :standard,
        context: %{},
        options: %{}
      }

      {:ok, request: request}
    end

    test "performs standard orchestration with all analyzers", %{request: request} do
      assert {:ok, result} = Orchestrator.orchestrate(request)

      assert result.file_path == "lib/example.ex"
      assert result.strategy == :standard
      assert is_map(result.results)
      assert is_list(result.insights)
      assert is_list(result.recommendations)
      assert is_map(result.overall_health)
      assert is_integer(result.execution_time)
    end

    test "runs quick strategy with minimal analyzers", %{request: request} do
      quick_request = %{request | strategy: :quick}

      assert {:ok, result} = Orchestrator.orchestrate(quick_request)

      assert result.strategy == :quick
      # Should only run quality and maybe security
      assert map_size(result.results) <= 2
    end

    test "runs deep strategy with comprehensive analysis", %{request: request} do
      deep_request = %{request | strategy: :deep}

      assert {:ok, result} = Orchestrator.orchestrate(deep_request)

      assert result.strategy == :deep
      # Should run most/all analyzers
      assert map_size(result.results) >= 3
    end

    test "runs specific analyzers when requested", %{request: request} do
      specific_request = %{request | analyzers: [:security, :performance]}

      assert {:ok, result} = Orchestrator.orchestrate(specific_request)

      assert Map.has_key?(result.results, :security)
      assert Map.has_key?(result.results, :performance)
      refute Map.has_key?(result.results, :impact)
    end
  end

  describe "adaptive_analysis/1" do
    test "adapts analysis based on initial findings" do
      request = %{
        file_path: "lib/vulnerable.ex",
        content: """
        defmodule Vulnerable do
          def execute_command(cmd) do
            System.cmd(cmd, [])  # Security issue
          end
        end
        """,
        analyzers: :all,
        strategy: :adaptive,
        context: %{},
        options: %{}
      }

      assert {:ok, result} = Orchestrator.adaptive_analysis(request)

      # Should detect security issue and run additional analyzers
      assert Map.has_key?(result.results, :security)
      assert length(result.results[:security][:vulnerabilities] || []) > 0
    end

    test "skips additional analysis when code is healthy" do
      request = %{
        file_path: "lib/healthy.ex",
        content: """
        defmodule Healthy do
          @doc "A simple, well-structured function"
          def add(a, b) when is_number(a) and is_number(b) do
            a + b
          end
        end
        """,
        analyzers: :all,
        strategy: :adaptive,
        context: %{},
        options: %{}
      }

      assert {:ok, result} = Orchestrator.adaptive_analysis(request)

      # Should only run initial quick analysis
      assert map_size(result.results) <= 2
    end
  end

  describe "run_analyzer/3" do
    test "runs security analyzer with context" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :security,
        depth: :moderate,
        auto_fix: false
      }

      context = %{
        content: "System.cmd(user_input, [])"
      }

      assert {:ok, result} = Orchestrator.run_analyzer(:security, message, context)
      assert is_list(result.vulnerabilities)
    end

    test "runs performance analyzer with context" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :performance,
        depth: :moderate,
        auto_fix: false
      }

      context = %{
        content: "Enum.map(1..1000000, fn x -> x * x end)"
      }

      assert {:ok, result} = Orchestrator.run_analyzer(:performance, message, context)
      assert Map.has_key?(result, :optimization_potential)
    end

    test "returns error for unknown analyzer" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :unknown,
        depth: :moderate,
        auto_fix: false
      }

      assert {:error, :unknown_analyzer} = Orchestrator.run_analyzer(:unknown, message, %{})
    end
  end

  describe "cross-analyzer insights" do
    test "generates insights from correlated findings" do
      request = %{
        file_path: "lib/problematic.ex",
        content: """
        defmodule Problematic do
          # High complexity + security issues
          def process_user_data(input) do
            query = "SELECT * FROM users WHERE id = '\#{input}'"
            
            result = Repo.query(query)
            
            Enum.reduce(result, %{}, fn row, acc ->
              nested_result = Enum.map(row.items, fn item ->
                if item.active do
                  calculate_complex_score(item)
                else
                  0
                end
              end)
              
              Map.put(acc, row.id, nested_result)
            end)
          end
          
          defp calculate_complex_score(item) do
            # Deeply nested complexity
            Enum.reduce(1..100, 0, fn i, acc ->
              if rem(i, 2) == 0 do
                inner = Enum.reduce(1..50, 0, fn j, inner_acc ->
                  inner_acc + i * j * item.value
                end)
                acc + inner
              else
                acc
              end
            end)
          end
        end
        """,
        analyzers: :all,
        strategy: :deep,
        context: %{},
        options: %{}
      }

      assert {:ok, result} = Orchestrator.orchestrate(request)

      # Should generate insights about security + complexity correlation
      assert Enum.any?(result.insights, fn insight ->
               insight.type in [:security_performance_tradeoff, :complex_high_impact_change]
             end)
    end

    test "identifies critical code health issues" do
      request = %{
        file_path: "lib/critical.ex",
        content: """
        defmodule Critical do
          # Multiple issues: security, quality, performance
          def bad_code(x) do
            eval(x)  # Security issue
            System.cmd(x, [])  # Another security issue
            
            # Performance issue
            Enum.each(1..1000000, fn i ->
              Enum.each(1..1000000, fn j ->
                i * j
              end)
            end)
          end
        end
        """,
        analyzers: :all,
        strategy: :standard,
        context: %{},
        options: %{}
      }

      assert {:ok, result} = Orchestrator.orchestrate(request)

      # Should identify critical health issues
      assert Enum.any?(result.insights, fn insight ->
               insight.severity == :critical
             end)
    end
  end

  describe "recommendations" do
    test "generates prioritized recommendations" do
      request = %{
        file_path: "lib/needs_work.ex",
        content: """
        defmodule NeedsWork do
          def process(data) do
            # SQL injection vulnerability
            Repo.query("SELECT * FROM table WHERE col = '\#{data}'")
            
            # Performance issue
            result = Enum.map(1..1000000, fn x ->
              Enum.map(1..100, fn y ->
                x * y
              end)
            end)
            
            result
          end
        end
        """,
        analyzers: :all,
        strategy: :standard,
        context: %{},
        options: %{}
      }

      assert {:ok, result} = Orchestrator.orchestrate(request)

      assert length(result.recommendations) > 0

      # Security recommendations should be prioritized
      first_rec = hd(result.recommendations)
      assert first_rec.priority in [:critical, :high]

      # Should have recommendations from multiple analyzers
      all_analyzers = Enum.flat_map(result.recommendations, & &1.analyzers)
      assert :security in all_analyzers
      assert :performance in all_analyzers
    end

    test "limits recommendations to top 10" do
      # Create content with many issues
      content = """
      defmodule ManyIssues do
        #{Enum.map(1..20, fn i -> "def issue_#{i}(x), do: System.cmd(x, [])\n" end)}
      end
      """

      request = %{
        file_path: "lib/many_issues.ex",
        content: content,
        analyzers: :all,
        strategy: :deep,
        context: %{},
        options: %{}
      }

      assert {:ok, result} = Orchestrator.orchestrate(request)

      assert length(result.recommendations) <= 10
    end
  end

  describe "overall health calculation" do
    test "calculates health scores from analyzer results" do
      request = %{
        file_path: "lib/example.ex",
        content: """
        defmodule Example do
          @doc "Well documented function"
          def safe_add(a, b) when is_number(a) and is_number(b) do
            a + b
          end
        end
        """,
        analyzers: :all,
        strategy: :standard,
        context: %{},
        options: %{}
      }

      assert {:ok, result} = Orchestrator.orchestrate(request)

      health = result.overall_health
      assert health.overall >= 0 and health.overall <= 1
      assert health.security >= 0 and health.security <= 1
      assert health.performance >= 0 and health.performance <= 1
      assert health.quality >= 0 and health.quality <= 1
      assert health.maintainability >= 0 and health.maintainability <= 1
    end

    test "reflects poor health for problematic code" do
      request = %{
        file_path: "lib/bad.ex",
        content: """
        defmodule Bad do
          def x(y) do
            eval(y)
            System.cmd(y, [])
            Enum.map(1..1000000, fn z -> z * z * z * z end)
          end
        end
        """,
        analyzers: :all,
        strategy: :standard,
        context: %{},
        options: %{}
      }

      assert {:ok, result} = Orchestrator.orchestrate(request)

      assert result.overall_health.overall < 0.5
      assert result.overall_health.security < 0.5
    end
  end

  describe "execution strategies" do
    test "focused strategy for security audit" do
      request = %{
        file_path: "lib/audit.ex",
        content: "defmodule Audit do\nend",
        analyzers: :all,
        strategy: :focused,
        context: %{focus: :security_audit},
        options: %{}
      }

      assert {:ok, result} = Orchestrator.orchestrate(request)

      assert Map.has_key?(result.results, :security)
      assert Map.has_key?(result.results, :impact)
    end

    test "focused strategy for performance optimization" do
      request = %{
        file_path: "lib/optimize.ex",
        content: "defmodule Optimize do\nend",
        analyzers: :all,
        strategy: :focused,
        context: %{focus: :performance_optimization},
        options: %{}
      }

      assert {:ok, result} = Orchestrator.orchestrate(request)

      assert Map.has_key?(result.results, :performance)
      assert Map.has_key?(result.results, :quality)
    end

    test "focused strategy for refactoring" do
      request = %{
        file_path: "lib/refactor.ex",
        content: "defmodule Refactor do\nend",
        analyzers: :all,
        strategy: :focused,
        context: %{focus: :refactoring},
        options: %{}
      }

      assert {:ok, result} = Orchestrator.orchestrate(request)

      assert Map.has_key?(result.results, :quality)
      assert Map.has_key?(result.results, :impact) or Map.has_key?(result.results, :performance)
    end
  end

  describe "error handling" do
    test "handles analyzer failures gracefully" do
      request = %{
        # This will cause some analyzers to fail
        file_path: nil,
        content: "invalid",
        analyzers: :all,
        strategy: :standard,
        context: %{},
        options: %{}
      }

      # Should still return a result even if some analyzers fail
      assert {:ok, result} = Orchestrator.orchestrate(request)
      assert is_map(result.results)
    end

    test "respects timeout option" do
      request = %{
        file_path: "lib/timeout.ex",
        content: "defmodule Timeout do\nend",
        analyzers: [:quality],
        strategy: :quick,
        context: %{},
        # Very short timeout
        options: %{timeout: 100}
      }

      # Should complete quickly or timeout gracefully
      assert {:ok, _result} = Orchestrator.orchestrate(request)
    end
  end
end
