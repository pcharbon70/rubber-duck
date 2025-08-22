defmodule RubberDuck.Agents.CodeFileAgent do
  @moduledoc """
  Code file agent for self-analyzing code changes with quality assessment.

  This agent analyzes code changes, updates documentation, performs dependency
  impact analysis, and recommends performance optimizations.
  """

  use Jido.Agent,
    name: "code_file_agent",
    description: "Self-analyzing code changes with quality assessment",
    category: "domain",
    tags: ["code", "analysis", "quality"],
    vsn: "1.0.0",
    actions: [
      RubberDuck.Actions.CreateEntity
    ]

  alias RubberDuck.Skills.CodeAnalysisSkill

  @doc """
  Create a new CodeFileAgent instance for a file.
  """
  def create_for_file(file_path) do
    with {:ok, agent} <- __MODULE__.new(),
         {:ok, agent} <-
           __MODULE__.set(agent,
             file_path: file_path,
             file_content: read_file_safely(file_path),
             analysis_history: [],
             quality_metrics: %{},
             optimization_suggestions: [],
             last_analysis: nil
           ) do
      {:ok, agent}
    end
  end

  @doc """
  Analyze code changes and update quality metrics.
  """
  def analyze_changes(agent, changes) do
    file_path = agent.file_path

    case CodeAnalysisSkill.analyze_changes(%{file_path: file_path, changes: changes}, agent) do
      {:ok, analysis, updated_agent} ->
        {:ok, final_agent} =
          __MODULE__.set(updated_agent,
            analysis_history: [analysis | agent.analysis_history] |> Enum.take(100),
            last_analysis: DateTime.utc_now()
          )

        {:ok, analysis, final_agent}

      error ->
        error
    end
  end

  @doc """
  Update documentation based on code changes.
  """
  def update_documentation(agent, changes) do
    file_path = agent.file_path

    case CodeAnalysisSkill.update_documentation(%{file_path: file_path, changes: changes}, agent) do
      {:ok, doc_updates, updated_agent} ->
        {:ok, final_agent} =
          __MODULE__.set(updated_agent,
            last_doc_update: DateTime.utc_now(),
            pending_doc_updates: doc_updates.suggested_updates
          )

        {:ok, doc_updates, final_agent}

      error ->
        error
    end
  end

  @doc """
  Analyze dependency impact of changes.
  """
  def analyze_dependency_impact(agent, changes) do
    file_path = agent.file_path

    case CodeAnalysisSkill.analyze_dependencies(%{file_path: file_path, changes: changes}, agent) do
      {:ok, impact_analysis, updated_agent} ->
        {:ok, final_agent} =
          __MODULE__.set(updated_agent,
            dependency_impact: impact_analysis,
            last_dependency_analysis: DateTime.utc_now()
          )

        {:ok, impact_analysis, final_agent}

      error ->
        error
    end
  end

  @doc """
  Detect performance optimization opportunities.
  """
  def detect_optimizations(agent) do
    file_path = agent.file_path

    case CodeAnalysisSkill.detect_optimizations(%{file_path: file_path}, agent) do
      {:ok, optimizations, updated_agent} ->
        {:ok, final_agent} =
          __MODULE__.set(updated_agent,
            optimization_suggestions: optimizations,
            last_optimization_scan: DateTime.utc_now()
          )

        {:ok, optimizations, final_agent}

      error ->
        error
    end
  end

  @doc """
  Get comprehensive file health report.
  """
  def get_file_health(agent) do
    health_report = %{
      file_path: agent.file_path,
      quality_score: calculate_quality_score(agent),
      optimization_opportunities: length(Map.get(agent, :optimization_suggestions, [])),
      documentation_status: assess_documentation_status(agent),
      dependency_risk: calculate_dependency_risk(agent),
      overall_health: calculate_overall_file_health(agent),
      last_analyzed: agent.last_analysis
    }

    {:ok, health_report}
  end

  @doc """
  Watch file for changes and trigger automatic analysis.
  """
  def start_watching(agent) do
    file_path = agent.file_path

    # TODO: Implement actual file watching with FileSystem
    # For now, return success with watching enabled flag
    {:ok, updated_agent} =
      __MODULE__.set(agent,
        watching_enabled: true,
        watch_started: DateTime.utc_now()
      )

    {:ok, "File watching enabled for #{file_path}", updated_agent}
  end

  @doc """
  Stop watching file for changes.
  """
  def stop_watching(agent) do
    {:ok, updated_agent} =
      __MODULE__.set(agent,
        watching_enabled: false,
        watch_stopped: DateTime.utc_now()
      )

    {:ok, "File watching disabled", updated_agent}
  end

  # Private helper functions

  defp read_file_safely(file_path) do
    case File.read(file_path) do
      {:ok, content} -> content
      {:error, _} -> ""
    end
  end

  defp calculate_quality_score(agent) do
    quality_metrics = Map.get(agent, :quality_metrics, %{})

    case quality_metrics do
      %{maintainability_index: maintainability} when is_number(maintainability) ->
        maintainability

      _ ->
        # Default quality score if no metrics available
        0.75
    end
  end

  defp assess_documentation_status(agent) do
    pending_updates = Map.get(agent, :pending_doc_updates, [])

    cond do
      Enum.empty?(pending_updates) -> :up_to_date
      length(pending_updates) < 3 -> :minor_updates_needed
      true -> :major_updates_needed
    end
  end

  defp calculate_dependency_risk(agent) do
    dependency_impact = Map.get(agent, :dependency_impact, %{})
    breaking_changes = Map.get(dependency_impact, :breaking_changes, [])

    cond do
      Enum.empty?(breaking_changes) -> :low
      length(breaking_changes) < 3 -> :medium
      true -> :high
    end
  end

  defp calculate_overall_file_health(agent) do
    quality_score = calculate_quality_score(agent)
    doc_status = assess_documentation_status(agent)
    dependency_risk = calculate_dependency_risk(agent)

    base_score = quality_score * 100
    doc_penalty = calculate_documentation_penalty(doc_status)
    risk_penalty = calculate_risk_penalty(dependency_risk)
    final_score = base_score - doc_penalty - risk_penalty

    determine_health_level(final_score)
  end

  defp calculate_documentation_penalty(:up_to_date), do: 0
  defp calculate_documentation_penalty(:minor_updates_needed), do: 5
  defp calculate_documentation_penalty(:major_updates_needed), do: 15

  defp calculate_risk_penalty(:low), do: 0
  defp calculate_risk_penalty(:medium), do: 10
  defp calculate_risk_penalty(:high), do: 20

  defp determine_health_level(final_score) do
    cond do
      final_score > 85 -> :excellent
      final_score > 70 -> :good
      final_score > 50 -> :fair
      true -> :poor
    end
  end
end
