defmodule RubberDuck.Analyzers.Code.ImpactTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Analyzers.Code.Impact
  alias RubberDuck.Messages.Code.{Analyze, ImpactAssess}

  describe "analyze/2 with Analyze message" do
    test "analyzes impact for basic changes" do
      message = %Analyze{
        file_path: "lib/my_module.ex",
        analysis_type: :impact
      }

      context = %{
        lines_changed: 50,
        functions_modified: ["func1", "func2"],
        modules_affected: ["MyModule"],
        state: %{}
      }

      assert {:ok, result} = Impact.analyze(message, context)
      assert Map.has_key?(result, :direct_impact)
      assert Map.has_key?(result, :dependency_impact)
      assert Map.has_key?(result, :performance_impact)
      assert Map.has_key?(result, :risk_assessment)
      assert Map.has_key?(result, :scope)
      assert Map.has_key?(result, :severity)
      assert result.file_path == "lib/my_module.ex"
    end

    test "calculates risk assessment correctly" do
      message = %Analyze{
        file_path: "lib/critical.ex",
        analysis_type: :impact
      }

      context = %{
        lines_changed: 150,
        complexity_delta: 8,
        test_coverage_delta: -0.2,
        state: %{}
      }

      assert {:ok, result} = Impact.analyze(message, context)
      risk = result.risk_assessment

      assert Map.has_key?(risk, :level)
      assert Map.has_key?(risk, :score)
      assert Map.has_key?(risk, :factors)
      assert Map.has_key?(risk, :mitigation_suggestions)

      # Should detect at least medium risk due to large change and reduced coverage
      assert risk.level in [:medium, :high, :critical]
      assert risk.score > 1.0
      assert length(risk.factors) >= 2
    end

    test "handles comprehensive analysis type" do
      message = %Analyze{
        file_path: "lib/test.ex",
        analysis_type: :comprehensive
      }

      context = %{lines_changed: 10, state: %{}}

      assert {:ok, result} = Impact.analyze(message, context)
      assert Map.has_key?(result, :direct_impact)
      assert Map.has_key?(result, :risk_assessment)
    end

    test "determines impact scope correctly" do
      # Test breaking changes - major scope
      message = %Analyze{
        file_path: "lib/api.ex",
        analysis_type: :impact
      }

      context = %{
        breaking_changes: true,
        state: %{}
      }

      assert {:ok, result} = Impact.analyze(message, context)
      assert result.scope == :major

      # Test API changes - moderate scope
      context = %{
        api_changes: true,
        breaking_changes: false,
        state: %{}
      }

      assert {:ok, result} = Impact.analyze(message, context)
      assert result.scope == :moderate

      # Test minimal changes
      context = %{
        lines_changed: 5,
        functions_modified: ["small_func"],
        state: %{}
      }

      assert {:ok, result} = Impact.analyze(message, context)
      assert result.scope in [:minimal, :minor]
    end

    test "calculates impact severity based on multiple factors" do
      message = %Analyze{
        file_path: "lib/complex.ex",
        analysis_type: :impact
      }

      # Critical severity test
      context = %{
        breaking_changes: true,
        api_changes: true,
        complexity_delta: 10,
        lines_changed: 200,
        state: %{}
      }

      assert {:ok, result} = Impact.analyze(message, context)
      assert result.severity == :critical

      # Low severity test
      context = %{
        lines_changed: 10,
        functions_modified: ["simple_func"],
        state: %{}
      }

      assert {:ok, result} = Impact.analyze(message, context)
      assert result.severity in [:minimal, :low]
    end

    test "estimates fix effort correctly" do
      message = %Analyze{
        file_path: "lib/effort_test.ex",
        analysis_type: :impact
      }

      # Large effort
      context = %{
        lines_changed: 500,
        complexity_delta: 15,
        state: %{}
      }

      assert {:ok, result} = Impact.analyze(message, context)
      assert result.estimated_effort in [:large, :extra_large]

      # Trivial effort
      context = %{
        lines_changed: 5,
        complexity_delta: 1,
        state: %{}
      }

      assert {:ok, result} = Impact.analyze(message, context)
      assert result.estimated_effort in [:trivial, :small]
    end
  end

  describe "analyze/2 with ImpactAssess message" do
    test "performs impact assessment on changes" do
      changes = %{
        lines_changed: 75,
        functions_modified: ["func1", "func2", "func3"],
        breaking_changes: false,
        complexity_delta: 3
      }

      message = %ImpactAssess{
        file_path: "lib/assess_test.ex",
        changes: changes
      }

      assert {:ok, result} = Impact.analyze(message, %{state: %{}})
      assert Map.has_key?(result, :direct_impact)
      assert Map.has_key?(result, :dependency_impact)
      assert Map.has_key?(result, :performance_impact)
      assert Map.has_key?(result, :risk_score)
      assert Map.has_key?(result, :suggested_tests)
      assert result.file_path == "lib/assess_test.ex"
    end

    test "calculates risk score correctly" do
      changes = %{
        lines_changed: 200,
        breaking_changes: true,
        modules_affected: ["Auth", "Security", "Payment"],
        file_path: "lib/critical_auth.ex"
      }

      message = %ImpactAssess{
        file_path: "lib/critical_auth.ex",
        changes: changes
      }

      assert {:ok, result} = Impact.analyze(message, %{state: %{}})
      assert result.risk_score > 0.5
      assert result.risk_assessment.level in [:medium, :high, :critical]
    end

    test "provides test suggestions based on changes" do
      changes = %{
        new_functions: ["new_api_call"],
        modified_functions: ["existing_func"],
        api_changes: true,
        breaking_changes: true
      }

      message = %ImpactAssess{
        file_path: "lib/api_module.ex",
        changes: changes
      }

      assert {:ok, result} = Impact.analyze(message, %{state: %{}})

      suggestions = result.suggested_tests
      assert is_list(suggestions)
      assert length(suggestions) >= 2
      assert Enum.any?(suggestions, &String.contains?(&1, "unit tests"))
      assert Enum.any?(suggestions, &String.contains?(&1, "breaking changes"))
    end

    test "handles complex dependency impact" do
      state = %{
        dependencies: %{
          "lib/core.ex" => %{
            direct: ["lib/auth.ex", "lib/api.ex"],
            transitive: ["lib/controllers.ex", "lib/services.ex"]
          }
        }
      }

      changes = %{lines_changed: 50, api_changes: true}

      message = %ImpactAssess{
        file_path: "lib/core.ex",
        changes: changes
      }

      assert {:ok, result} = Impact.analyze(message, %{state: state})

      dep_impact = result.dependency_impact
      assert dep_impact.direct_dependencies == 2
      assert dep_impact.transitive_dependencies == 2
      assert dep_impact.impact_radius > 0
    end
  end

  describe "risk assessment" do
    test "identifies breaking changes as high risk" do
      message = %Analyze{
        file_path: "lib/breaking.ex",
        analysis_type: :impact
      }

      context = %{
        breaking_changes: true,
        state: %{}
      }

      assert {:ok, result} = Impact.analyze(message, context)
      risk_factors = result.risk_assessment.factors

      assert Enum.any?(risk_factors, fn {type, _} -> type == :breaking_changes end)
      assert result.risk_assessment.level in [:medium, :high, :critical]
    end

    test "identifies complexity increases as risk" do
      message = %Analyze{
        file_path: "lib/complex.ex",
        analysis_type: :impact
      }

      context = %{
        complexity_delta: 10,
        state: %{}
      }

      assert {:ok, result} = Impact.analyze(message, context)
      risk_factors = result.risk_assessment.factors

      assert Enum.any?(risk_factors, fn {type, _} -> type == :high_complexity_increase end)
    end

    test "identifies test coverage reduction as risk" do
      message = %Analyze{
        file_path: "lib/coverage.ex",
        analysis_type: :impact
      }

      context = %{
        test_coverage_delta: -0.3,
        state: %{}
      }

      assert {:ok, result} = Impact.analyze(message, context)
      risk_factors = result.risk_assessment.factors

      assert Enum.any?(risk_factors, fn {type, _} -> type == :reduced_test_coverage end)
    end

    test "provides appropriate mitigation suggestions" do
      message = %Analyze{
        file_path: "lib/risky.ex",
        analysis_type: :impact
      }

      context = %{
        breaking_changes: true,
        complexity_delta: 8,
        test_coverage_delta: -0.15,
        state: %{}
      }

      assert {:ok, result} = Impact.analyze(message, context)
      suggestions = result.risk_assessment.mitigation_suggestions

      assert is_list(suggestions)
      assert length(suggestions) >= 2
      assert Enum.any?(suggestions, &String.contains?(&1, "compatibility"))
      assert Enum.any?(suggestions, &String.contains?(&1, "tests"))
    end
  end

  describe "performance impact estimation" do
    test "estimates performance impact from complexity changes" do
      message = %Analyze{
        file_path: "lib/perf.ex",
        analysis_type: :impact
      }

      context = %{
        complexity_delta: 5,
        lines_changed: 100,
        memory_delta: 50,
        state: %{}
      }

      assert {:ok, result} = Impact.analyze(message, context)
      perf_impact = result.performance_impact

      assert Map.has_key?(perf_impact, :complexity_change)
      assert Map.has_key?(perf_impact, :memory_impact)
      assert Map.has_key?(perf_impact, :runtime_impact)
      assert Map.has_key?(perf_impact, :overall_impact)

      assert perf_impact.complexity_change == 5
      assert perf_impact.memory_impact == 50
      assert perf_impact.overall_impact in [:negative, :slightly_negative, :neutral]
    end

    test "determines overall performance impact correctly" do
      # Positive impact
      message = %Analyze{
        file_path: "lib/optimized.ex",
        analysis_type: :impact
      }

      context = %{
        complexity_delta: -3,
        memory_delta: -10,
        state: %{}
      }

      assert {:ok, result} = Impact.analyze(message, context)
      assert result.performance_impact.overall_impact in [:positive, :slightly_positive]

      # Negative impact
      context = %{
        complexity_delta: 10,
        memory_delta: 20,
        lines_changed: 200,
        state: %{}
      }

      assert {:ok, result} = Impact.analyze(message, context)
      assert result.performance_impact.overall_impact in [:negative, :slightly_negative]
    end
  end

  describe "dependency analysis" do
    test "analyzes dependencies with state" do
      state = %{
        dependencies: %{
          "lib/main.ex" => %{
            direct: ["lib/helper1.ex", "lib/helper2.ex"],
            transitive: ["lib/util1.ex", "lib/util2.ex", "lib/util3.ex"]
          }
        }
      }

      message = %Analyze{
        file_path: "lib/main.ex",
        analysis_type: :impact
      }

      context = %{state: state}

      assert {:ok, result} = Impact.analyze(message, context)
      dep_impact = result.dependency_impact

      assert dep_impact.direct_dependencies == 2
      assert dep_impact.transitive_dependencies == 3
      # 2 + (3 * 0.5)
      assert dep_impact.impact_radius == 3.5
      assert is_list(dep_impact.affected_modules)
    end

    test "identifies critical dependency paths" do
      state = %{
        dependencies: %{
          "lib/core.ex" => %{
            direct: ["lib/auth.ex", "lib/security.ex", "lib/payment.ex"],
            transitive: []
          }
        }
      }

      message = %Analyze{
        file_path: "lib/core.ex",
        analysis_type: :impact
      }

      context = %{state: state}

      assert {:ok, result} = Impact.analyze(message, context)
      critical_paths = result.dependency_impact.critical_paths

      # Should identify auth, security, and payment as critical
      assert length(critical_paths) >= 2
    end

    test "finds affected files" do
      state = %{
        analysis_history: %{
          "lib/dependent1.ex" => [%{}],
          "lib/dependent2.ex" => [%{}],
          "lib/independent.ex" => [%{}]
        },
        dependencies: %{
          "lib/dependent1.ex" => %{direct: ["lib/main.ex"], transitive: []},
          "lib/dependent2.ex" => %{transitive: ["lib/main.ex"], direct: []}
        }
      }

      message = %Analyze{
        file_path: "lib/main.ex",
        analysis_type: :impact
      }

      context = %{state: state}

      assert {:ok, result} = Impact.analyze(message, context)
      affected = result.affected_files

      assert is_list(affected)
      # Should find files that depend on lib/main.ex
      assert "lib/dependent1.ex" in affected
    end
  end

  describe "test impact assessment" do
    test "suggests tests based on change type" do
      changes = %{
        new_functions: ["new_api"],
        modified_functions: ["existing_api"],
        api_changes: true,
        breaking_changes: true
      }

      message = %ImpactAssess{
        file_path: "lib/api.ex",
        changes: changes
      }

      assert {:ok, result} = Impact.analyze(message, %{state: %{}})

      test_impact = result.test_coverage_impact
      suggestions = test_impact.test_suggestions

      assert is_list(suggestions)
      assert length(suggestions) >= 3
      assert Enum.any?(suggestions, &String.contains?(&1, "unit tests"))
      assert Enum.any?(suggestions, &String.contains?(&1, "integration tests"))
      assert Enum.any?(suggestions, &String.contains?(&1, "breaking changes"))
    end

    test "determines test priority correctly" do
      # Critical priority for breaking changes
      changes = %{breaking_changes: true}
      message = %ImpactAssess{file_path: "lib/critical.ex", changes: changes}

      assert {:ok, result} = Impact.analyze(message, %{state: %{}})
      assert result.test_coverage_impact.priority == :critical

      # High priority for API changes
      changes = %{api_changes: true, breaking_changes: false}
      message = %ImpactAssess{file_path: "lib/api.ex", changes: changes}

      assert {:ok, result} = Impact.analyze(message, %{state: %{}})
      assert result.test_coverage_impact.priority == :high

      # Normal priority for small changes
      changes = %{lines_changed: 10, functions_modified: ["small_func"]}
      message = %ImpactAssess{file_path: "lib/small.ex", changes: changes}

      assert {:ok, result} = Impact.analyze(message, %{state: %{}})
      assert result.test_coverage_impact.priority == :normal
    end
  end

  describe "rollback complexity assessment" do
    test "identifies complex rollback scenarios" do
      message = %Analyze{
        file_path: "lib/db_change.ex",
        analysis_type: :impact
      }

      # Complex rollback due to database changes
      context = %{
        database_changes: true,
        breaking_changes: false,
        api_changes: false,
        state: %{}
      }

      assert {:ok, result} = Impact.analyze(message, context)
      assert result.rollback_complexity in [:complex, :moderate]

      # Complex rollback due to external API changes
      context = %{
        external_api_changes: true,
        database_changes: false,
        state: %{}
      }

      assert {:ok, result} = Impact.analyze(message, context)
      assert result.rollback_complexity == :complex

      # Moderate rollback for breaking changes
      context = %{
        breaking_changes: true,
        database_changes: false,
        external_api_changes: false,
        state: %{}
      }

      assert {:ok, result} = Impact.analyze(message, context)
      assert result.rollback_complexity == :moderate
    end

    test "identifies simple rollback scenarios" do
      message = %Analyze{
        file_path: "lib/simple.ex",
        analysis_type: :impact
      }

      context = %{
        lines_changed: 20,
        functions_modified: ["helper_func"],
        state: %{}
      }

      assert {:ok, result} = Impact.analyze(message, context)
      assert result.rollback_complexity == :simple
    end
  end

  describe "behavior implementation" do
    test "implements required callbacks" do
      assert function_exported?(Impact, :analyze, 2)
      assert function_exported?(Impact, :supported_types, 0)
    end

    test "returns correct supported types" do
      types = Impact.supported_types()
      assert Analyze in types
      assert ImpactAssess in types
    end

    test "returns correct priority" do
      assert Impact.priority() == :high
    end

    test "returns appropriate timeout" do
      assert Impact.timeout() == 15_000
    end

    test "returns metadata" do
      metadata = Impact.metadata()
      assert is_map(metadata)
      assert Map.has_key?(metadata, :name)
      assert Map.has_key?(metadata, :description)
      assert :impact in metadata.categories
      assert :risk in metadata.categories
    end
  end

  describe "edge cases" do
    test "handles empty changes" do
      message = %ImpactAssess{
        file_path: "lib/empty.ex",
        changes: %{}
      }

      assert {:ok, result} = Impact.analyze(message, %{state: %{}})
      assert result.risk_score == 0.0
      assert result.risk_assessment.level == :minimal
    end

    test "handles nil state gracefully" do
      message = %Analyze{
        file_path: "lib/no_state.ex",
        analysis_type: :impact
      }

      assert {:ok, result} = Impact.analyze(message, %{})
      assert is_map(result)
      assert Map.has_key?(result, :risk_assessment)
    end

    test "returns error for unsupported message types" do
      unsupported_message = %{__struct__: :unsupported}

      assert {:error, {:unsupported_message_type, :unsupported}} =
               Impact.analyze(unsupported_message, %{})
    end
  end

  describe "affected files identification" do
    test "identifies related test files and implementations" do
      message = %ImpactAssess{
        file_path: "lib/user_service.ex",
        changes: %{lines_changed: 30}
      }

      assert {:ok, result} = Impact.analyze(message, %{state: %{}})
      affected = result.affected_files

      assert is_list(affected)
      assert length(affected) > 0

      # Should include test files
      assert Enum.any?(affected, &String.contains?(&1, "test"))

      # Should not include the original file
      refute "lib/user_service.ex" in affected
    end
  end
end
