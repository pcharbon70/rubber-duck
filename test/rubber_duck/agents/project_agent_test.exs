defmodule RubberDuck.Agents.ProjectAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.ProjectAgent

  describe "ProjectAgent" do
    test "creates agent for project" do
      project_path = "/test/project"
      project_name = "Test Project"

      assert {:ok, agent} = ProjectAgent.create_for_project(project_path, project_name)
      assert agent.project_path == project_path
      assert agent.project_name == project_name
      assert agent.structure_data == %{}
      assert agent.quality_metrics == %{}
      assert is_list(agent.refactoring_suggestions)
    end

    test "analyzes project structure" do
      {:ok, agent} = ProjectAgent.create_for_project("/test", "Test")

      assert {:ok, analysis, updated_agent} = ProjectAgent.analyze_structure(agent)
      assert is_map(analysis)
      assert Map.has_key?(analysis, :total_files)
      assert Map.has_key?(updated_agent, :structure_data)
    end

    test "monitors project quality" do
      {:ok, agent} = ProjectAgent.create_for_project("/test", "Test")

      assert {:ok, quality_metrics, updated_agent} = ProjectAgent.monitor_quality(agent)
      assert is_map(quality_metrics)
      assert Map.has_key?(quality_metrics, :credo_score)
      assert Map.has_key?(updated_agent, :quality_metrics)
    end

    test "analyzes dependencies" do
      {:ok, agent} = ProjectAgent.create_for_project("/test", "Test")

      assert {:ok, dependency_info, updated_agent} = ProjectAgent.analyze_dependencies(agent)
      assert is_map(dependency_info)
      assert Map.has_key?(dependency_info, :mix_deps)
      assert Map.has_key?(updated_agent, :dependency_info)
    end

    test "suggests refactoring" do
      {:ok, agent} = ProjectAgent.create_for_project("/test", "Test")

      assert {:ok, suggestions, updated_agent} = ProjectAgent.suggest_refactoring(agent)
      assert is_list(suggestions)
      assert Map.has_key?(updated_agent, :refactoring_suggestions)
    end

    test "gets project health report" do
      {:ok, agent} = ProjectAgent.create_for_project("/test", "Test")

      assert {:ok, health_report} = ProjectAgent.get_project_health(agent)
      assert is_map(health_report)
      assert Map.has_key?(health_report, :overall_score)
      assert Map.has_key?(health_report, :project_name)
    end
  end
end
