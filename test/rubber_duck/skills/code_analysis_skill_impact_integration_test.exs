defmodule RubberDuck.Skills.CodeAnalysisSkillImpactIntegrationTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Skills.CodeAnalysisSkill
  alias RubberDuck.Messages.Code.{Analyze, ImpactAssess}

  describe "integration with Impact analyzer" do
    test "impact analysis via Analyze message" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :impact,
        depth: :moderate,
        auto_fix: false
      }

      context = %{
        lines_changed: 75,
        functions_modified: ["func1", "func2"],
        modules_affected: ["TestModule"],
        complexity_delta: 5,
        breaking_changes: true,
        state: %{}
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)
      assert Map.has_key?(result, :impact)
      assert is_map(result.impact)
      assert Map.has_key?(result.impact, :scope)
      assert Map.has_key?(result.impact, :severity)
      assert Map.has_key?(result.impact, :dependencies)
      assert Map.has_key?(result.impact, :estimated_effort)
    end

    test "comprehensive analysis includes impact" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :comprehensive,
        depth: :moderate,
        auto_fix: false
      }

      context = %{
        content: "defmodule SimpleModule do\n  def simple_function(x), do: x + 1\nend",
        lines_changed: 25,
        complexity_delta: 2,
        state: %{}
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)
      assert Map.has_key?(result, :impact)
      assert is_map(result.impact)
      assert Map.has_key?(result.impact, :scope)
      assert result.impact.scope in [:minimal, :minor, :moderate]
    end

    test "ImpactAssess message delegation" do
      changes = %{
        lines_changed: 50,
        functions_modified: ["update_user", "validate_data"],
        api_changes: true,
        breaking_changes: false
      }

      message = %ImpactAssess{
        file_path: "lib/user_service.ex",
        changes: changes
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_impact_assess(message, %{state: %{}})
      assert Map.has_key?(result, :file_path)
      assert result.file_path == "lib/user_service.ex"
      assert Map.has_key?(result, :direct_impact)
      assert Map.has_key?(result, :dependency_impact)
      assert Map.has_key?(result, :performance_impact)
      assert Map.has_key?(result, :risk_assessment)
    end

    test "legacy signal handler for code.impact.assess" do
      signal = %{
        type: "code.impact.assess",
        data: %{
          file_path: "lib/critical_module.ex",
          changes: %{
            lines_changed: 100,
            breaking_changes: true,
            api_changes: true,
            modules_affected: ["Auth", "Security"]
          }
        }
      }

      state = %{}

      assert {:ok, impact_result, _updated_state} = CodeAnalysisSkill.handle_signal(signal, state)
      assert Map.has_key?(impact_result, :file)
      assert impact_result.file == "lib/critical_module.ex"
      assert Map.has_key?(impact_result, :direct_impact)
      assert Map.has_key?(impact_result, :dependency_impact)
      assert Map.has_key?(impact_result, :performance_impact)
      assert Map.has_key?(impact_result, :risk_assessment)
    end

    test "file analysis includes impact when enabled" do
      signal = %{
        type: "code.analyze.file",
        data: %{
          file_path: "lib/important.ex",
          content: """
          defmodule Important do
            def critical_function(data) do
              if data.breaking_change do
                # This is a breaking change
                :new_behavior
              else
                :old_behavior
              end
            end
          end
          """,
          breaking_changes: true,
          api_changes: true
        }
      }

      state = %{
        opts: %{
          depth: :moderate,
          impact_analysis: true,
          performance_check: false,
          security_scan: false
        }
      }

      assert {:ok, analysis_result, _updated_state} =
               CodeAnalysisSkill.handle_signal(signal, state)

      assert Map.has_key?(analysis_result, :impact)
      assert is_map(analysis_result.impact)
      assert Map.has_key?(analysis_result.impact, :scope)
      assert Map.has_key?(analysis_result.impact, :severity)
    end

    test "impact analysis provides risk assessment" do
      message = %Analyze{
        file_path: "lib/risky.ex",
        analysis_type: :impact,
        depth: :deep,
        auto_fix: false
      }

      context = %{
        lines_changed: 150,
        complexity_delta: 10,
        test_coverage_delta: -0.2,
        breaking_changes: true,
        api_changes: true,
        state: %{}
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)
      impact_analysis = result.impact

      # Should detect high-risk changes
      assert impact_analysis.scope in [:major, :moderate]
      assert impact_analysis.severity in [:critical, :high, :medium]
    end

    test "impact analysis estimates effort correctly" do
      message = %Analyze{
        file_path: "lib/complex_change.ex",
        analysis_type: :impact,
        depth: :moderate,
        auto_fix: false
      }

      context = %{
        lines_changed: 200,
        complexity_delta: 8,
        functions_modified: ["func1", "func2", "func3", "func4", "func5"],
        modules_affected: ["Module1", "Module2", "Module3"],
        state: %{}
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)
      impact_analysis = result.impact

      assert Map.has_key?(impact_analysis, :estimated_effort)
      assert impact_analysis.estimated_effort in [:medium, :large, :extra_large]
    end
  end

  describe "error handling" do
    test "handles impact analyzer errors gracefully in perform_impact_analysis" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :impact,
        depth: :moderate,
        auto_fix: false
      }

      # Empty context should still work but with limited functionality
      context = %{}

      assert {:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)
      assert Map.has_key?(result, :impact)
      assert is_map(result.impact)
    end

    test "handles ImpactAssess errors gracefully" do
      # Test with minimal ImpactAssess message
      message = %ImpactAssess{
        file_path: "nonexistent.ex",
        changes: %{}
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_impact_assess(message, %{})
      assert Map.has_key?(result, :file_path)
    end
  end

  describe "backward compatibility" do
    test "maintains same interface for legacy impact assessment" do
      signal = %{
        type: "code.impact.assess",
        data: %{
          file_path: "lib/legacy.ex",
          changes: %{
            lines_changed: 30,
            api_changes: false,
            breaking_changes: false
          }
        }
      }

      state = %{}

      assert {:ok, result, _updated_state} = CodeAnalysisSkill.handle_signal(signal, state)

      # Should maintain the same structure as before
      assert Map.has_key?(result, :file)
      assert Map.has_key?(result, :direct_impact)
      assert Map.has_key?(result, :dependency_impact)
      assert Map.has_key?(result, :performance_impact)
      assert Map.has_key?(result, :risk_assessment)
      assert result.file == "lib/legacy.ex"
    end

    test "file analysis with impact disabled works correctly" do
      signal = %{
        type: "code.analyze.file",
        data: %{
          file_path: "lib/no_impact.ex",
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

      # Should not include impact analysis when disabled
      refute Map.has_key?(result, :impact)
      assert Map.has_key?(result, :quality_score)
      assert Map.has_key?(result, :issues)
      assert Map.has_key?(result, :suggestions)
    end
  end

  describe "delegation verification" do
    test "impact analysis uses Impact analyzer internally" do
      message = %Analyze{
        file_path: "lib/verify.ex",
        analysis_type: :impact,
        depth: :moderate,
        auto_fix: false
      }

      context = %{
        lines_changed: 80,
        complexity_delta: 6,
        breaking_changes: true,
        database_changes: true,
        state: %{}
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)

      # Verify that we get the comprehensive impact analysis structure
      # that only the Impact analyzer provides
      impact = result.impact
      assert Map.has_key?(impact, :scope)
      assert Map.has_key?(impact, :severity)
      assert Map.has_key?(impact, :estimated_effort)
      assert Map.has_key?(impact, :rollback_complexity)

      # Verify the dependencies structure includes detailed impact metrics
      assert Map.has_key?(impact, :dependencies)
      dependencies = impact.dependencies
      assert Map.has_key?(dependencies, :direct)
      assert Map.has_key?(dependencies, :transitive)
      assert Map.has_key?(dependencies, :affected_modules)
    end

    test "comprehensive analysis includes all analyzers" do
      message = %Analyze{
        file_path: "lib/comprehensive.ex",
        analysis_type: :comprehensive,
        depth: :moderate,
        auto_fix: false
      }

      context = %{
        content: """
        defmodule Comprehensive do
          def complex_function(x) do
            if x > 10 do
              case x do
                11 -> :eleven
                12 -> :twelve
                _ -> :other
              end
            else
              :small
            end
          end
        end
        """,
        lines_changed: 50,
        complexity_delta: 3,
        state: %{}
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)

      # Should include all analyzers for comprehensive analysis
      assert Map.has_key?(result, :quality)
      assert Map.has_key?(result, :security)
      assert Map.has_key?(result, :performance)
      assert Map.has_key?(result, :impact)

      # Verify each analyzer provides its expected structure
      assert is_map(result.quality)
      assert is_map(result.security)
      assert is_map(result.performance)
      assert is_map(result.impact)
    end
  end
end
