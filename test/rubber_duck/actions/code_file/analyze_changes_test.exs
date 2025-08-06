defmodule RubberDuck.Actions.CodeFile.AnalyzeChangesTest do
  use RubberDuck.DataCase, async: true

  alias RubberDuck.Actions.CodeFile.AnalyzeChanges

  describe "run/2" do
    test "analyzes new code file" do
      params = %{
        file_id: "test_file",
        content: """
        defmodule TestModule do
          def simple_function do
            :ok
          end
        end
        """,
        analyze_depth: :normal
      }

      {:ok, result} = AnalyzeChanges.run(params, %{})

      assert result.quality_score > 0
      assert result.lines_of_code == 5
      assert is_list(result.issues)
      assert result.analysis_timestamp != nil
    end

    test "detects changes between versions" do
      params = %{
        file_id: "changing_file",
        content: """
        defmodule ChangedModule do
          def function_one do
            :modified
          end

          def function_two do
            :new
          end
        end
        """,
        previous_content: """
        defmodule ChangedModule do
          def function_one do
            :original
          end
        end
        """,
        analyze_depth: :normal
      }

      {:ok, result} = AnalyzeChanges.run(params, %{})

      assert result.changes.additions > 0
      assert result.quality_score != nil
      assert result.impact != nil
    end

    test "detects quality issues" do
      params = %{
        file_id: "problematic_file",
        content: """
        defmodule ProblematicModule do
          def veryLongFunctionNameThatExceedsReasonableLengthAndMakesCodeHardToReadAndMaintain do
            if true do
              if true do
                if true do
                  if true do
                    if true do
                      :deeply_nested
                    end
                  end
                end
              end
            end
          end

          def x do
            :single_letter_function
          end
        end
        """,
        analyze_depth: :deep
      }

      {:ok, result} = AnalyzeChanges.run(params, %{})

      assert length(result.issues) > 0
      assert result.quality_score < 0.8
      assert result.complexity_score > 5
    end

    test "performs shallow analysis when requested" do
      params = %{
        file_id: "shallow_file",
        content: "defmodule Simple do\nend",
        analyze_depth: :shallow
      }

      {:ok, result} = AnalyzeChanges.run(params, %{})

      # Shallow analysis should be quick and basic
      assert result.quality_score != nil
      assert result.lines_of_code == 2
    end

    test "performs deep analysis when requested" do
      params = %{
        file_id: "deep_file",
        content: """
        defmodule DeepAnalysis do
          def potential_security_issue do
            Code.eval_string("dangerous")
          end

          def performance_issue do
            Enum.map(1..1000000, &(&1 * 2))
            |> Enum.filter(&(&1 > 10))
            |> Enum.map(&(&1 + 1))
          end
        end
        """,
        analyze_depth: :deep
      }

      {:ok, result} = AnalyzeChanges.run(params, %{})

      # Deep analysis should find security and performance issues
      security_issues = Enum.filter(result.issues, &(&1.type == :security))
      performance_issues = Enum.filter(result.issues, &(&1.type == :performance))

      assert length(security_issues) > 0
      assert length(performance_issues) > 0
    end

    test "calculates quality metrics accurately" do
      params = %{
        file_id: "metrics_file",
        content: """
        defmodule MetricsModule do
          # This is a comment

          def function_one(a, b) do
            if a > b do
              a
            else
              b
            end
          end

          def function_two do
            case something() do
              :a -> 1
              :b -> 2
              :c -> 3
              _ -> 0
            end
          end
        end
        """,
        analyze_depth: :normal
      }

      {:ok, result} = AnalyzeChanges.run(params, %{})

      assert result.complexity_score > 1
      assert result.maintainability_index > 0
      assert result.lines_of_code > 10
    end

    test "assesses change impact" do
      params = %{
        file_id: "impact_file",
        content: """
        defmodule ImpactModule do
          def public_api_changed do
            :new_implementation
          end
        end
        """,
        previous_content: """
        defmodule ImpactModule do
          def public_api_changed do
            :old_implementation
          end
        end
        """,
        analyze_depth: :normal
      }

      {:ok, result} = AnalyzeChanges.run(params, %{})

      assert result.impact.risk_level != nil
      assert is_list(result.impact.affected_functions)
      assert result.impact.performance_impact != nil
    end
  end

  describe "edge cases" do
    test "handles empty content" do
      params = %{
        file_id: "empty_file",
        content: "",
        analyze_depth: :normal
      }

      {:ok, result} = AnalyzeChanges.run(params, %{})

      assert result.lines_of_code == 0
      assert result.quality_score != nil
    end

    test "handles malformed code" do
      params = %{
        file_id: "malformed_file",
        content: "def broken do do do end",
        analyze_depth: :normal
      }

      {:ok, result} = AnalyzeChanges.run(params, %{})

      assert length(result.issues) > 0
      syntax_issues = Enum.filter(result.issues, &(&1.type == :syntax))
      assert length(syntax_issues) > 0
    end

    test "handles very large files" do
      large_content =
        1..1000
        |> Enum.map(fn i ->
          "def function_#{i} do\n  :ok\nend\n"
        end)
        |> Enum.join("\n")

      params = %{
        file_id: "large_file",
        content: "defmodule LargeModule do\n#{large_content}\nend",
        analyze_depth: :shallow
      }

      {:ok, result} = AnalyzeChanges.run(params, %{})

      assert result.lines_of_code > 3000
      assert result.quality_score != nil
    end
  end
end
