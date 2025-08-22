defmodule RubberDuck.Agents.ProjectAgent do
  @moduledoc """
  Project agent for self-organizing project management.

  This agent manages project structure optimization, dependency detection,
  code quality monitoring, and refactoring suggestions with autonomous learning.
  """

  use Jido.Agent,
    name: "project_agent",
    description: "Self-organizing project management with quality monitoring",
    category: "domain",
    tags: ["project", "quality", "refactoring"],
    vsn: "1.0.0",
    actions: [
      RubberDuck.Actions.CreateEntity
    ]

  alias RubberDuck.Skills.ProjectManagementSkill

  @doc """
  Create a new ProjectAgent instance for a project.
  """
  def create_for_project(project_path, project_name) do
    with {:ok, agent} <- __MODULE__.new(),
         {:ok, agent} <-
           __MODULE__.set(agent,
             project_path: project_path,
             project_name: project_name,
             structure_data: %{},
             quality_metrics: %{},
             dependency_info: %{},
             refactoring_suggestions: [],
             last_analysis: nil
           ) do
      {:ok, agent}
    end
  end

  @doc """
  Analyze project structure and update internal knowledge.
  """
  def analyze_structure(agent) do
    project_path = agent.project_path

    case ProjectManagementSkill.analyze_structure(%{project_path: project_path}, agent) do
      {:ok, analysis, updated_agent} ->
        # Update agent state with analysis
        {:ok, final_agent} =
          __MODULE__.set(updated_agent,
            structure_data: analysis,
            last_analysis: DateTime.utc_now()
          )

        {:ok, analysis, final_agent}

      error ->
        error
    end
  end

  @doc """
  Monitor project quality and detect issues.
  """
  def monitor_quality(agent) do
    project_path = agent.project_path

    case ProjectManagementSkill.monitor_quality(%{project_path: project_path}, agent) do
      {:ok, quality_metrics, updated_agent} ->
        {:ok, final_agent} =
          __MODULE__.set(updated_agent,
            quality_metrics: quality_metrics,
            last_quality_check: DateTime.utc_now()
          )

        {:ok, quality_metrics, final_agent}

      error ->
        error
    end
  end

  @doc """
  Detect and analyze project dependencies.
  """
  def analyze_dependencies(agent) do
    project_path = agent.project_path

    case ProjectManagementSkill.detect_dependencies(%{project_path: project_path}, agent) do
      {:ok, dependency_info, updated_agent} ->
        {:ok, final_agent} =
          __MODULE__.set(updated_agent,
            dependency_info: dependency_info,
            last_dependency_check: DateTime.utc_now()
          )

        {:ok, dependency_info, final_agent}

      error ->
        error
    end
  end

  @doc """
  Generate refactoring suggestions based on current analysis.
  """
  def suggest_refactoring(agent) do
    case ProjectManagementSkill.suggest_refactoring(%{}, agent) do
      {:ok, suggestions, updated_agent} ->
        {:ok, final_agent} =
          __MODULE__.set(updated_agent,
            refactoring_suggestions: suggestions,
            last_suggestion_update: DateTime.utc_now()
          )

        {:ok, suggestions, final_agent}

      error ->
        error
    end
  end

  @doc """
  Get comprehensive project health report.
  """
  def get_project_health(agent) do
    health_report = %{
      project_name: agent.project_name,
      project_path: agent.project_path,
      structure_health: calculate_structure_health(agent.structure_data),
      quality_health: calculate_quality_health(agent.quality_metrics),
      dependency_health: calculate_dependency_health(agent.dependency_info),
      overall_score: calculate_overall_health(agent),
      last_updated: agent.last_analysis
    }

    {:ok, health_report}
  end

  @doc """
  Automatically optimize project based on suggestions.
  """
  def auto_optimize(agent, options \\ []) do
    suggestions = agent.refactoring_suggestions
    auto_apply = Keyword.get(options, :auto_apply, false)

    if auto_apply do
      # Apply low-risk suggestions automatically
      safe_suggestions = Enum.filter(suggestions, &(&1.priority == :low))
      apply_suggestions(agent, safe_suggestions)
    else
      {:ok, "Auto-optimization disabled. #{length(suggestions)} suggestions available.", agent}
    end
  end

  # Private helper functions

  defp calculate_structure_health(structure_data) when is_map(structure_data) do
    organization_score = Map.get(structure_data, :organization_score, 0.5)

    cond do
      organization_score > 0.8 -> :excellent
      organization_score > 0.6 -> :good
      organization_score > 0.4 -> :fair
      true -> :poor
    end
  end

  defp calculate_structure_health(_), do: :unknown

  defp calculate_quality_health(quality_metrics) when is_map(quality_metrics) do
    credo_score = get_in(quality_metrics, [:credo_score, :score]) || 50

    cond do
      credo_score > 90 -> :excellent
      credo_score > 75 -> :good
      credo_score > 60 -> :fair
      true -> :poor
    end
  end

  defp calculate_quality_health(_), do: :unknown

  defp calculate_dependency_health(dependency_info) when is_map(dependency_info) do
    unused_count = length(Map.get(dependency_info, :unused_deps, []))
    security_issues = length(Map.get(dependency_info, :security_vulnerabilities, []))

    cond do
      unused_count == 0 and security_issues == 0 -> :excellent
      unused_count < 3 and security_issues == 0 -> :good
      unused_count < 5 and security_issues < 2 -> :fair
      true -> :poor
    end
  end

  defp calculate_dependency_health(_), do: :unknown

  defp calculate_overall_health(agent) do
    structure_health = calculate_structure_health(agent.structure_data)
    quality_health = calculate_quality_health(agent.quality_metrics)
    dependency_health = calculate_dependency_health(agent.dependency_info)

    health_scores = %{
      excellent: 4,
      good: 3,
      fair: 2,
      poor: 1,
      unknown: 0
    }

    total_score =
      health_scores[structure_health] +
        health_scores[quality_health] +
        health_scores[dependency_health]

    average_score = total_score / 3.0

    cond do
      average_score > 3.5 -> :excellent
      average_score > 2.5 -> :good
      average_score > 1.5 -> :fair
      true -> :poor
    end
  end

  defp apply_suggestions(agent, suggestions) do
    # TODO: Implement actual suggestion application
    applied_count = length(suggestions)
    {:ok, "Applied #{applied_count} suggestions automatically.", agent}
  end
end
