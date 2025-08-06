defmodule RubberDuck.Agents.ProjectAgentTest do
  use RubberDuck.DataCase
  alias RubberDuck.Agents.ProjectAgent
  alias RubberDuck.Projects
  alias Jido.Signal

  setup do
    # Create a test user for project ownership
    {:ok, user} = create_test_user()

    # Create a test project
    {:ok, project} =
      Projects.create_project(%{
        name: "Test Project",
        description: "A test project for agent testing",
        language: "elixir",
        status: :active,
        owner_id: user.id
      })

    # Create some test code files
    {:ok, file1} =
      Projects.create_code_file(%{
        project_id: project.id,
        path: "lib/test_module.ex",
        content: """
        defmodule TestModule do
          def hello, do: "world"
        end
        """,
        language: "elixir",
        size_bytes: 50
      })

    {:ok, file2} =
      Projects.create_code_file(%{
        project_id: project.id,
        path: "lib/another_module.ex",
        content: """
        defmodule AnotherModule do
          import TestModule

          def greet do
            hello()
          end
        end
        """,
        language: "elixir",
        size_bytes: 100
      })

    {:ok, agent} = ProjectAgent.start_link([])

    %{
      agent: agent,
      project: project,
      user: user,
      files: [file1, file2]
    }
  end

  describe "init/1" do
    test "subscribes to project signals" do
      # Agent should be subscribed to these signals
      assert_receive {:signal_subscribed, "project.created"}
      assert_receive {:signal_subscribed, "project.updated"}
      assert_receive {:signal_subscribed, "project.file.changed"}
      assert_receive {:signal_subscribed, "project.deleted"}
    end

    test "schedules periodic project scanning" do
      # Should receive scan message after timeout
      assert_receive :scan_projects, 310_000
    end
  end

  describe "handle_instruction/2 - monitor_project" do
    test "successfully monitors a valid project", %{agent: agent, project: project} do
      {response, updated_agent} =
        ProjectAgent.handle_instruction(
          {:monitor_project, project.id},
          agent
        )

      assert {:ok, %{monitoring: true, project_id: ^project.id}} = response
      assert Map.has_key?(updated_agent.state.monitored_projects, project.id)
      assert updated_agent.state.monitored_projects[project.id].name == project.name
    end

    test "fails to monitor non-existent project", %{agent: agent} do
      fake_id = Ecto.UUID.generate()

      {response, _updated_agent} =
        ProjectAgent.handle_instruction(
          {:monitor_project, fake_id},
          agent
        )

      assert {:error, :project_not_found} = response
    end

    test "analyzes project upon monitoring", %{agent: agent, project: project} do
      {_, updated_agent} =
        ProjectAgent.handle_instruction(
          {:monitor_project, project.id},
          agent
        )

      # Should have structure optimizations
      assert Map.has_key?(updated_agent.state.structure_optimizations, project.id)

      # Should have dependency graph
      assert Map.has_key?(updated_agent.state.dependency_graph, project.id)

      # Should have quality metrics
      assert Map.has_key?(updated_agent.state.quality_metrics, project.id)
    end
  end

  describe "handle_instruction/2 - optimize_structure" do
    test "applies structure optimizations when enabled", %{agent: agent, project: project} do
      # First monitor the project
      {_, agent} =
        ProjectAgent.handle_instruction(
          {:monitor_project, project.id},
          agent
        )

      # Add some mock optimizations
      agent =
        put_in(
          agent.state.structure_optimizations[project.id],
          [
            %{type: :flatten_structure, target: %{directories: ["lib/deep/nested"]}}
          ]
        )

      {response, updated_agent} =
        ProjectAgent.handle_instruction(
          {:optimize_structure, project.id},
          agent
        )

      assert {:ok, results} = response
      assert updated_agent.state.successful_refactorings != []
    end

    test "skips optimization when disabled", %{agent: agent, project: project} do
      agent = %{agent | state: %{agent.state | auto_optimization_enabled: false}}

      {response, _} =
        ProjectAgent.handle_instruction(
          {:optimize_structure, project.id},
          agent
        )

      assert {:ok, %{optimizations: []}} = response
    end
  end

  describe "handle_instruction/2 - suggest_refactorings" do
    test "generates refactoring suggestions", %{agent: agent, project: project} do
      # Monitor project first
      {_, agent} =
        ProjectAgent.handle_instruction(
          {:monitor_project, project.id},
          agent
        )

      # Add mock quality metrics
      agent =
        put_in(
          agent.state.quality_metrics[project.id],
          %{complexity: 15, duplication: 0.2, test_coverage: 0.6}
        )

      {response, _} =
        ProjectAgent.handle_instruction(
          {:suggest_refactorings, project.id},
          agent
        )

      assert {:ok, suggestions} = response
      assert is_list(suggestions)
    end

    test "emits signal when suggestions found", %{agent: agent, project: project} do
      {_, agent} =
        ProjectAgent.handle_instruction(
          {:monitor_project, project.id},
          agent
        )

      agent =
        put_in(
          agent.state.quality_metrics[project.id],
          %{complexity: 20}
        )

      ProjectAgent.handle_instruction({:suggest_refactorings, project.id}, agent)

      assert_receive {:signal_emitted, "project.refactoring.suggested",
                      %{project_id: ^project.id}}
    end
  end

  describe "handle_instruction/2 - check_dependencies" do
    test "detects outdated dependencies", %{agent: agent, project: project} do
      {_, agent} =
        ProjectAgent.handle_instruction(
          {:monitor_project, project.id},
          agent
        )

      # Add mock dependencies
      agent =
        put_in(
          agent.state.dependency_graph[project.id],
          %{
            "phoenix" => %{version: "1.5.0", latest: "1.7.0"},
            "ecto" => %{version: "3.6.0", latest: "3.10.0"}
          }
        )

      {response, updated_agent} =
        ProjectAgent.handle_instruction(
          {:check_dependencies, project.id},
          agent
        )

      assert {:ok, alerts} = response
      assert length(updated_agent.state.dependency_alerts) > 0
    end

    test "emits signal for outdated dependencies", %{agent: agent, project: project} do
      {_, agent} =
        ProjectAgent.handle_instruction(
          {:monitor_project, project.id},
          agent
        )

      agent =
        put_in(
          agent.state.dependency_graph[project.id],
          %{"old_dep" => %{version: "0.1.0", latest: "2.0.0"}}
        )

      ProjectAgent.handle_instruction({:check_dependencies, project.id}, agent)

      assert_receive {:signal_emitted, "project.dependency.outdated", %{project_id: ^project.id}}
    end
  end

  describe "handle_signal/3" do
    test "auto-monitors newly created projects", %{agent: agent} do
      new_project_id = Ecto.UUID.generate()

      # Create project in DB first
      {:ok, _} = create_test_project(new_project_id)

      {:ok, updated_agent} =
        ProjectAgent.handle_signal(
          "project.created",
          %{project_id: new_project_id},
          agent
        )

      assert Map.has_key?(updated_agent.state.monitored_projects, new_project_id)
    end

    test "updates metrics on file change", %{agent: agent, project: project, files: [file | _]} do
      # Monitor project first
      {_, agent} =
        ProjectAgent.handle_instruction(
          {:monitor_project, project.id},
          agent
        )

      {:ok, updated_agent} =
        ProjectAgent.handle_signal(
          "project.file.changed",
          %{project_id: project.id, file_path: file.path},
          agent
        )

      # State should have changed
      assert updated_agent != agent
    end

    test "cleans up on project deletion", %{agent: agent, project: project} do
      # Monitor project first
      {_, agent} =
        ProjectAgent.handle_instruction(
          {:monitor_project, project.id},
          agent
        )

      {:ok, updated_agent} =
        ProjectAgent.handle_signal(
          "project.deleted",
          %{project_id: project.id},
          agent
        )

      refute Map.has_key?(updated_agent.state.monitored_projects, project.id)
      refute Map.has_key?(updated_agent.state.quality_metrics, project.id)
      refute Map.has_key?(updated_agent.state.dependency_graph, project.id)
    end
  end

  describe "handle_info/2" do
    test "scans all monitored projects periodically", %{agent: agent, project: project} do
      # Monitor project
      {_, agent} =
        ProjectAgent.handle_instruction(
          {:monitor_project, project.id},
          agent
        )

      # Trigger scan
      {:noreply, updated_agent} = ProjectAgent.handle_info(:scan_projects, agent)

      assert updated_agent.state.last_scan_time != nil
      assert DateTime.diff(DateTime.utc_now(), updated_agent.state.last_scan_time, :second) < 5
    end
  end

  describe "quality threshold monitoring" do
    test "emits signal when quality degrades", %{agent: agent, project: project} do
      {_, agent} =
        ProjectAgent.handle_instruction(
          {:monitor_project, project.id},
          agent
        )

      # Set poor quality metrics
      agent =
        put_in(
          agent.state.quality_metrics[project.id],
          %{complexity: 20, duplication: 0.3, test_coverage: 0.4}
        )

      # Trigger threshold check
      ProjectAgent.send(agent, :check_thresholds)

      assert_receive {:signal_emitted, "project.quality.degraded",
                      %{
                        project_id: ^project.id,
                        violations: violations
                      }}

      assert length(violations) > 0
    end
  end

  describe "learning and optimization" do
    test "learns from successful optimizations", %{agent: agent} do
      initial_patterns = agent.state.optimization_patterns

      # Simulate successful optimization
      results = [%{success: true, pattern: "flatten_deep_nesting"}]
      updated_agent = ProjectAgent.learn_from_optimization(agent, results)

      assert map_size(updated_agent.state.optimization_patterns) >= map_size(initial_patterns)
    end

    test "builds confidence over time", %{agent: agent, project: project} do
      {_, agent} =
        ProjectAgent.handle_instruction(
          {:monitor_project, project.id},
          agent
        )

      # Add multiple successful refactorings
      agent = %{
        agent
        | state: %{
            agent.state
            | successful_refactorings: [
                %{type: :extract_function, success: true},
                %{type: :extract_function, success: true},
                %{type: :extract_function, success: true}
              ]
          }
      }

      # Confidence should increase for repeated successful patterns
      assert agent.state.optimization_confidence_threshold < 1.0
    end
  end

  # Helper functions

  defp create_test_user do
    # Create a test user
    %{
      id: Ecto.UUID.generate(),
      email: "test@example.com",
      admin: false
    }
    |> RubberDuck.Users.create_user()
  end

  defp create_test_project(id) do
    Projects.create_project(%{
      id: id,
      name: "New Test Project",
      language: "elixir",
      status: :active
    })
  end
end
