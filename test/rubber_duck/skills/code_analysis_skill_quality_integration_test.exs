defmodule RubberDuck.Skills.CodeAnalysisSkillQualityIntegrationTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Skills.CodeAnalysisSkill
  alias RubberDuck.Messages.Code.{Analyze, QualityCheck}

  describe "integration with Quality analyzer" do
    test "quality analysis via Analyze message" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality,
        depth: :moderate,
        auto_fix: false
      }

      context = %{
        content: """
        defmodule ComplexModule do
          def complex_function(x, y, z) do
            if x > 10 do
              case y do
                1 -> if z > 5, do: :case1, else: :other1
                2 -> if z > 5, do: :case2, else: :other2
                _ -> :default
              end
            else
              cond do
                y > 5 -> :branch1
                y > 3 -> :branch2
                true -> :branch3
              end
            end
          end
        end
        """,
        state: %{}
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)
      assert Map.has_key?(result, :quality)
      assert is_map(result.quality)
      assert Map.has_key?(result.quality, :quality_score)
      assert Map.has_key?(result.quality, :metrics)
      assert Map.has_key?(result.quality, :issues)
      assert Map.has_key?(result.quality, :suggestions)
    end

    test "comprehensive analysis includes quality" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :comprehensive,
        depth: :moderate,
        auto_fix: false
      }

      context = %{
        content: "defmodule SimpleModule do\n  def simple_function(x), do: x + 1\nend",
        state: %{}
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)
      assert Map.has_key?(result, :quality)
      assert is_map(result.quality)
      assert Map.has_key?(result.quality, :quality_score)
      assert result.quality.quality_score >= 0.0
      assert result.quality.quality_score <= 1.0
    end

    test "QualityCheck message delegation" do
      message = %QualityCheck{
        target: "test.ex",
        metrics: [:complexity, :coverage, :duplication],
        thresholds: %{complexity: 10, coverage: 80, duplication: 5}
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_quality_check(message, %{})
      assert Map.has_key?(result, :status)
      assert result.status == :completed
      assert Map.has_key?(result, :metrics)
      assert Map.has_key?(result, :passed)
      assert is_boolean(result.passed)
    end

    test "legacy signal handler for code.quality.check" do
      signal = %{
        type: "code.quality.check",
        data: %{
          target: "test.ex",
          metrics: [:complexity, :coverage],
          thresholds: %{complexity: 15, coverage: 70}
        }
      }

      state = %{}

      assert {:ok, quality_result, _updated_state} =
               CodeAnalysisSkill.handle_signal(signal, state)

      assert Map.has_key?(quality_result, :status)
      assert quality_result.status == :completed
      assert Map.has_key?(quality_result, :quality_score)
      assert Map.has_key?(quality_result, :target)
    end

    test "legacy signal handler for code.analyze.file includes quality" do
      signal = %{
        type: "code.analyze.file",
        data: %{
          file_path: "test.ex",
          content: """
          defmodule TestModule do
            def test_function(input) do
              if input > 0 do
                input * 2
              else
                0
              end
            end
          end
          """
        }
      }

      state = %{
        opts: %{
          depth: :moderate,
          impact_analysis: false,
          performance_check: false,
          security_scan: false
        }
      }

      assert {:ok, analysis_result, _updated_state} =
               CodeAnalysisSkill.handle_signal(signal, state)

      assert Map.has_key?(analysis_result, :quality_score)
      assert Map.has_key?(analysis_result, :issues)
      assert Map.has_key?(analysis_result, :suggestions)
      assert is_float(analysis_result.quality_score)
      assert is_list(analysis_result.issues)
      assert is_list(analysis_result.suggestions)
    end

    test "quality analysis provides maintainability insights" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality,
        depth: :deep,
        auto_fix: false
      }

      context = %{
        content: """
        def poor_quality_function(a, b, c, d, e, f) do
          temp1 = a + b
          temp2 = c + d
          temp3 = e + f
          
          if temp1 > 10 do
            if temp2 > 20 do
              if temp3 > 30 do
                temp1 + temp2 + temp3
              else
                temp1 + temp2
              end
            else
              temp1
            end
          else
            0
          end
        end
        """,
        state: %{}
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)
      quality_analysis = result.quality

      assert Map.has_key?(quality_analysis, :maintainability_score)
      assert Map.has_key?(quality_analysis, :technical_debt_indicators)
      assert is_list(quality_analysis.technical_debt_indicators)
      assert quality_analysis.maintainability_score >= 0.0
      assert quality_analysis.maintainability_score <= 1.0
    end

    test "quality metrics calculation" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality,
        depth: :moderate,
        auto_fix: false
      }

      context = %{
        content: """
        defmodule MetricsTest do
          @moduledoc "Test module for metrics"
          
          @doc "Simple addition function"
          def add(a, b), do: a + b
          
          @doc "More complex function"
          def complex_calc(x) do
            if x > 5 do
              x * 2
            else
              x + 1
            end
          end
        end
        """,
        state: %{}
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)
      metrics = result.quality.metrics

      assert Map.has_key?(metrics, :complexity)
      assert Map.has_key?(metrics, :loc)
      assert Map.has_key?(metrics, :maintainability_index)
      assert metrics.complexity >= 1
      assert metrics.loc > 0
      assert is_number(metrics.maintainability_index)
    end
  end

  describe "error handling" do
    test "handles quality analyzer errors gracefully in perform_quality_analysis" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality,
        depth: :moderate,
        auto_fix: false
      }

      # Empty context should still work but with limited functionality
      context = %{}

      assert {:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)
      assert Map.has_key?(result, :quality)
      assert is_map(result.quality)
    end

    test "handles QualityCheck errors gracefully" do
      # Test with minimal QualityCheck message
      message = %QualityCheck{
        target: "nonexistent.ex",
        metrics: [:complexity],
        thresholds: %{}
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_quality_check(message, %{})
      assert Map.has_key?(result, :status)
    end
  end

  describe "backward compatibility" do
    test "maintains same interface for legacy analysis" do
      signal = %{
        type: "code.analyze.file",
        data: %{
          file_path: "test.ex",
          content: "def simple, do: :ok"
        }
      }

      state = %{
        opts: %{
          depth: :shallow,
          impact_analysis: false,
          performance_check: false,
          security_scan: false
        }
      }

      assert {:ok, result, _updated_state} = CodeAnalysisSkill.handle_signal(signal, state)

      # Should maintain the same structure as before
      assert Map.has_key?(result, :file)
      assert Map.has_key?(result, :quality_score)
      assert Map.has_key?(result, :issues)
      assert Map.has_key?(result, :suggestions)
      assert result.file == "test.ex"
    end

    test "quality check signal maintains backward compatibility" do
      signal = %{
        type: "code.quality.check",
        data: %{
          target: "test.ex",
          metrics: [:complexity, :duplication]
        }
      }

      state = %{}

      assert {:ok, result, _updated_state} = CodeAnalysisSkill.handle_signal(signal, state)

      # Should have the expected QualityCheck result structure
      assert Map.has_key?(result, :status)
      assert Map.has_key?(result, :target)
      assert Map.has_key?(result, :quality_score)
      assert result.status == :completed
    end
  end

  describe "delegation verification" do
    test "quality analysis uses Quality analyzer internally" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality,
        depth: :moderate,
        auto_fix: false
      }

      context = %{
        content: """
        def test_function do
          # This function has some quality issues
          x = 1
          y = 2
          z = 3
          result = x + y + z
          result
        end
        """,
        state: %{}
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)

      # Verify that we get the comprehensive quality analysis structure
      # that only the Quality analyzer provides
      quality = result.quality
      assert Map.has_key?(quality, :maintainability_score)
      assert Map.has_key?(quality, :technical_debt_indicators)
      assert Map.has_key?(quality, :metrics)

      # Verify that metrics include the detailed metrics from Quality analyzer
      assert Map.has_key?(quality.metrics, :maintainability_index)
      assert Map.has_key?(quality.metrics, :documentation_coverage)
    end
  end
end
