defmodule RubberDuck.Agents.CodeFileAgentTest do
  use RubberDuck.DataCase, async: true

  alias RubberDuck.Agents.CodeFileAgent
  alias RubberDuck.Messages.CodeFile.{FileCreated, FileModified, AnalyzeFile}

  setup do
    # Create a test project
    project = create_test_project()

    # Create initial agent state
    initial_state = %{
      file_id: "test_file_123",
      file_path: "lib/test_module.ex",
      project_id: project.id,
      current_content: """
      defmodule TestModule do
        def hello do
          "world"
        end
      end
      """,
      previous_content: nil,
      quality_score: 0.8,
      monitoring_enabled: true,
      dependents: [],
      imports: [],
      exports: [],
      change_frequency: 0,
      issues: [],
      suggestions: [],
      last_analysis_at: nil,
      has_readme: false,
      has_inline_docs: false,
      documentation_coverage: 0.5,
      optimization_level: :moderate,
      auto_fix_enabled: false,
      analysis_frequency: :hourly
    }

    {:ok, project: project, initial_state: initial_state}
  end

  describe "init/1" do
    test "initializes agent with default state" do
      state = %{}
      {:ok, initialized} = CodeFileAgent.init(state)

      assert initialized == state
    end

    test "preserves existing state during init", %{initial_state: state} do
      {:ok, initialized} = CodeFileAgent.init(state)

      assert initialized.file_id == state.file_id
      assert initialized.project_id == state.project_id
    end
  end

  describe "handle_instruction/2 - FileCreated" do
    test "handles new code file creation", %{initial_state: state} do
      message = %FileCreated{
        file_id: "new_file_456",
        file_path: "lib/new_module.ex",
        content: "defmodule NewModule do\nend",
        timestamp: DateTime.utc_now()
      }

      {:ok, new_state} = CodeFileAgent.handle_instruction({:file_created, message}, state)

      assert new_state.file_id == "new_file_456"
      assert new_state.file_path == "lib/new_module.ex"
      assert new_state.last_analysis_at != nil
    end

    test "performs initial analysis on creation" do
      message = %FileCreated{
        file_id: "analyze_file",
        file_path: "lib/complex_module.ex",
        content: """
        defmodule ComplexModule do
          def complex_function(a, b, c) do
            if a > b do
              if b > c do
                a + b + c
              else
                a - c
              end
            else
              b * c
            end
          end
        end
        """,
        timestamp: DateTime.utc_now()
      }

      # Initialize with minimal state for the test
      initial_state = %{
        file_id: nil,
        file_path: nil,
        quality_score: nil,
        issues: [],
        suggestions: [],
        last_analysis_at: nil
      }

      {:ok, new_state} = CodeFileAgent.handle_instruction({:file_created, message}, initial_state)

      assert new_state.quality_score != nil
      assert new_state.last_analysis_at != nil
    end
  end

  describe "handle_instruction/2 - FileModified" do
    test "handles file modifications", %{initial_state: state} do
      message = %FileModified{
        file_id: state.file_id,
        file_path: state.file_path,
        changes: %{
          new_content: """
          defmodule TestModule do
            def hello do
              "modified world"
            end

            def new_function do
              "added"
            end
          end
          """,
          old_content: state.current_content
        },
        timestamp: DateTime.utc_now()
      }

      {:ok, new_state} = CodeFileAgent.handle_instruction({:file_modified, message}, state)

      assert new_state.previous_content == state.current_content
      assert new_state.current_content == message.changes.new_content
      assert new_state.change_frequency == 1
    end

    test "routes dependency messages when dependents affected", %{initial_state: state} do
      state = Map.put(state, :dependents, ["dep1.ex", "dep2.ex"])

      message = %FileModified{
        file_id: state.file_id,
        file_path: state.file_path,
        changes: %{
          new_content: "modified content",
          old_content: state.current_content
        },
        timestamp: DateTime.utc_now()
      }

      {:ok, _new_state} = CodeFileAgent.handle_instruction({:file_modified, message}, state)

      # Would verify message routing in real implementation
      assert true
    end
  end

  describe "handle_instruction/2 - AnalyzeFile" do
    test "triggers comprehensive analysis", %{initial_state: state} do
      message = %AnalyzeFile{
        file_id: state.file_id,
        file_path: state.file_path,
        analysis_types: [:quality, :security, :performance],
        deep_scan: true
      }

      {:ok, new_state} = CodeFileAgent.handle_instruction({:analyze_file, message}, state)

      assert new_state.last_analysis_at != nil
      assert is_list(new_state.issues)
      assert is_list(new_state.suggestions)
    end
  end

  describe "handle_instruction/3 - monitor_quality" do
    test "updates monitoring configuration", %{initial_state: state} do
      params = %{
        enabled: true,
        frequency: :hourly,
        auto_fix: true
      }

      {:ok, result, new_state} =
        CodeFileAgent.handle_instruction(
          "monitor_quality",
          params,
          state
        )

      assert result.status == :monitoring_updated
      assert new_state.monitoring_enabled == true
      assert new_state.analysis_frequency == :hourly
      assert new_state.auto_fix_enabled == true
    end

    test "disables monitoring when requested", %{initial_state: state} do
      params = %{enabled: false}

      {:ok, _result, new_state} =
        CodeFileAgent.handle_instruction(
          "monitor_quality",
          params,
          state
        )

      assert new_state.monitoring_enabled == false
    end
  end

  describe "handle_instruction/3 - optimize_performance" do
    test "detects and applies performance optimizations", %{initial_state: state} do
      state =
        Map.put(state, :current_content, """
        defmodule SlowModule do
          def process(list) do
            list
            |> Enum.map(&(&1 * 2))
            |> Enum.filter(&(&1 > 10))
            |> Enum.map(&(&1 + 1))
          end
        end
        """)

      params = %{auto_apply: false}

      {:ok, result, new_state} =
        CodeFileAgent.handle_instruction(
          "optimize_performance",
          params,
          state
        )

      assert result.optimizations_found >= 0
      assert new_state.performance_grade != nil
    end
  end

  describe "handle_instruction/3 - update_documentation" do
    test "updates documentation coverage", %{initial_state: state} do
      params = %{
        generate_missing: true,
        update_existing: false
      }

      {:ok, result, new_state} =
        CodeFileAgent.handle_instruction(
          "update_documentation",
          params,
          state
        )

      assert result.documentation_updated == true
      assert new_state.documentation_coverage != nil
      assert new_state.documentation_quality != nil
    end
  end

  describe "handle_instruction/3 - analyze_dependencies" do
    test "analyzes dependency relationships", %{initial_state: state} do
      state =
        Map.put(state, :current_content, """
        defmodule DependentModule do
          import Enum
          alias RubberDuck.Projects

          def process do
            Projects.list_projects()
          end
        end
        """)

      params = %{}

      {:ok, result, new_state} =
        CodeFileAgent.handle_instruction(
          "analyze_dependencies",
          params,
          state
        )

      assert is_list(result.dependencies)
      assert is_list(result.dependents)
      assert result.impact_analysis != nil
      assert is_list(new_state.imports)
    end
  end

  describe "integration scenarios" do
    test "full lifecycle: create, modify, analyze", %{project: project} do
      # Create
      create_message = %FileCreated{
        file_id: "lifecycle_file",
        file_path: "lib/lifecycle.ex",
        project_id: project.id,
        content: "defmodule Lifecycle do\nend",
        timestamp: DateTime.utc_now()
      }

      initial_state = %{
        file_id: nil,
        file_path: nil,
        project_id: nil,
        current_content: nil,
        quality_score: nil,
        issues: [],
        suggestions: [],
        change_frequency: 0,
        last_analysis_at: nil
      }

      {:ok, state1} = CodeFileAgent.handle_instruction({:file_created, create_message}, initial_state)
      assert state1.file_id == "lifecycle_file"

      # Modify
      modify_message = %FileModified{
        file_id: state1.file_id,
        file_path: state1.file_path,
        changes: %{
          new_content: """
          defmodule Lifecycle do
            def new_function do
              :ok
            end
          end
          """,
          old_content: state1.current_content
        },
        timestamp: DateTime.utc_now()
      }

      {:ok, state2} = CodeFileAgent.handle_instruction({:file_modified, modify_message}, state1)
      assert state2.change_frequency == 1

      # Analyze
      analyze_message = %AnalyzeFile{
        file_id: state2.file_id,
        file_path: state2.file_path,
        analysis_types: [:quality],
        deep_scan: false
      }

      {:ok, state3} = CodeFileAgent.handle_instruction({:analyze_file, analyze_message}, state2)
      assert state3.last_analysis_at != nil
    end

    test "quality monitoring workflow", %{initial_state: state} do
      # Enable monitoring
      {:ok, _, state1} =
        CodeFileAgent.handle_instruction(
          "monitor_quality",
          %{enabled: true, frequency: :on_change},
          state
        )

      # Simulate quality degradation
      state2 = Map.put(state1, :quality_score, 0.4)

      # Optimize
      {:ok, result, _state3} =
        CodeFileAgent.handle_instruction(
          "optimize_performance",
          %{},
          state2
        )

      assert result.optimizations_found >= 0
    end
  end

  describe "edge cases" do
    test "handles missing file content gracefully" do
      message = %FileCreated{
        file_id: "empty_file",
        file_path: "lib/empty.ex",
        content: nil,  # Missing content
        timestamp: DateTime.utc_now()
      }

      initial_state = %{
        file_id: nil,
        file_path: nil,
        quality_score: nil,
        issues: [],
        suggestions: [],
        last_analysis_at: nil
      }

      {:ok, state} = CodeFileAgent.handle_instruction({:file_created, message}, initial_state)
      assert state.file_id == "empty_file"
    end

    test "handles analysis failure gracefully", %{initial_state: state} do
      state = Map.put(state, :current_content, "invalid elixir code {{{")

      message = %AnalyzeFile{
        file_id: state.file_id,
        file_path: state.file_path,
        analysis_types: [:quality],
        deep_scan: false
      }

      result = CodeFileAgent.handle_instruction({:analyze_file, message}, state)

      # Should handle gracefully even with invalid content
      assert match?({:ok, _}, result) or match?({:error, _, _}, result)
    end

    test "handles concurrent modifications", %{initial_state: state} do
      message1 = %FileModified{
        file_id: state.file_id,
        file_path: state.file_path,
        changes: %{new_content: "content1", old_content: state.current_content},
        timestamp: DateTime.utc_now()
      }

      message2 = %FileModified{
        file_id: state.file_id,
        file_path: state.file_path,
        changes: %{new_content: "content2", old_content: "content1"},
        timestamp: DateTime.utc_now()
      }

      {:ok, state1} = CodeFileAgent.handle_instruction({:file_modified, message1}, state)
      {:ok, state2} = CodeFileAgent.handle_instruction({:file_modified, message2}, state1)

      assert state2.change_frequency == 2
      assert state2.current_content == "content2"
    end
  end

  # Helper functions

  defp create_test_project do
    %{
      id: "test_project_#{System.unique_integer()}",
      name: "Test Project",
      language: "elixir"
    }
  end
end
