defmodule RubberDuck.Skills.ProjectManagementSkill do
  @moduledoc """
  Project management skill with quality monitoring and structure optimization.

  Provides capabilities for managing project structure, dependency detection,
  quality monitoring, and refactoring suggestions.
  """

  use Jido.Skill,
    name: "project_management_skill",
    opts_key: :project_management_state,
    signal_patterns: [
      "project.analyze_structure",
      "project.detect_dependencies",
      "project.monitor_quality",
      "project.suggest_refactoring"
    ]

  @doc """
  Analyze project structure and identify optimization opportunities.
  """
  def analyze_structure(%{project_path: project_path} = _params, state) do
    structure_analysis = %{
      total_files: count_files(project_path),
      directory_depth: calculate_depth(project_path),
      file_types: analyze_file_types(project_path),
      organization_score: calculate_organization_score(project_path),
      suggestions: generate_structure_suggestions(project_path)
    }

    # Store analysis in state
    analyses = Map.get(state, :structure_analyses, [])
    updated_analyses = [structure_analysis | analyses] |> Enum.take(50)

    new_state = Map.put(state, :structure_analyses, updated_analyses)

    {:ok, structure_analysis, new_state}
  end

  @doc """
  Detect project dependencies and potential issues.
  """
  def detect_dependencies(%{project_path: project_path} = _params, state) do
    dependency_analysis = %{
      mix_deps: read_mix_dependencies(project_path),
      unused_deps: detect_unused_dependencies(project_path),
      outdated_deps: check_outdated_dependencies(project_path),
      dependency_conflicts: analyze_dependency_conflicts(project_path),
      security_vulnerabilities: scan_security_issues(project_path)
    }

    new_state = Map.put(state, :last_dependency_analysis, dependency_analysis)

    {:ok, dependency_analysis, new_state}
  end

  @doc """
  Monitor code quality metrics across the project.
  """
  def monitor_quality(%{project_path: project_path} = _params, state) do
    quality_metrics = %{
      credo_score: run_credo_analysis(project_path),
      test_coverage: calculate_test_coverage(project_path),
      cyclomatic_complexity: analyze_complexity(project_path),
      documentation_coverage: check_documentation(project_path),
      code_duplication: detect_duplication(project_path)
    }

    # Track quality trends
    quality_history = Map.get(state, :quality_history, [])
    updated_history = [quality_metrics | quality_history] |> Enum.take(100)

    new_state =
      state
      |> Map.put(:quality_history, updated_history)
      |> Map.put(:current_quality, quality_metrics)

    {:ok, quality_metrics, new_state}
  end

  @doc """
  Suggest refactoring opportunities based on analysis.
  """
  def suggest_refactoring(_params, state) do
    quality_data = Map.get(state, :current_quality, %{})
    structure_data = Map.get(state, :structure_analyses, []) |> List.first(%{})

    suggestions =
      []
      |> add_complexity_suggestions(quality_data)
      |> add_structure_suggestions(structure_data)
      |> add_dependency_suggestions(Map.get(state, :last_dependency_analysis, %{}))
      |> prioritize_suggestions()

    {:ok, suggestions, state}
  end

  # Private helper functions

  defp count_files(project_path) do
    case File.ls(project_path) do
      {:ok, files} -> length(files)
      {:error, _} -> 0
    end
  end

  defp calculate_depth(project_path) do
    case File.ls(project_path) do
      {:ok, files} ->
        files
        |> Enum.map(&calculate_file_depth(project_path, &1))
        |> Enum.max(fn -> 0 end)

      {:error, _} ->
        0
    end
  end

  defp calculate_file_depth(project_path, file) do
    full_path = Path.join(project_path, file)
    if File.dir?(full_path), do: 1 + calculate_depth(full_path), else: 1
  end

  defp analyze_file_types(project_path) do
    case File.ls(project_path) do
      {:ok, files} ->
        files
        |> Enum.map(&Path.extname/1)
        |> Enum.frequencies()

      {:error, _} ->
        %{}
    end
  end

  defp calculate_organization_score(_project_path) do
    # Simple scoring based on conventional Phoenix structure
    # TODO: Implement actual directory structure analysis
    0.75
  end

  defp generate_structure_suggestions(_project_path) do
    [
      %{
        type: :organization,
        priority: :medium,
        description: "Consider organizing related modules into subdirectories",
        impact: :maintainability
      }
    ]
  end

  defp read_mix_dependencies(project_path) do
    mix_file = Path.join(project_path, "mix.exs")

    case File.read(mix_file) do
      {:ok, content} ->
        # Simple regex to extract dependencies - could be more sophisticated
        Regex.scan(~r/{:(\w+),/, content)
        |> Enum.map(fn [_, dep] -> dep end)

      {:error, _} ->
        []
    end
  end

  defp detect_unused_dependencies(_project_path) do
    # TODO: Implement actual unused dependency detection
    []
  end

  defp check_outdated_dependencies(_project_path) do
    # TODO: Implement dependency version checking
    []
  end

  defp analyze_dependency_conflicts(_project_path) do
    # TODO: Implement conflict detection
    []
  end

  defp scan_security_issues(_project_path) do
    # TODO: Implement security scanning
    []
  end

  defp run_credo_analysis(_project_path) do
    # TODO: Integrate with actual credo analysis
    %{score: 85, issues: 5}
  end

  defp calculate_test_coverage(_project_path) do
    # TODO: Integrate with actual test coverage tools
    %{percentage: 80, missing_files: []}
  end

  defp analyze_complexity(_project_path) do
    # TODO: Implement cyclomatic complexity analysis
    %{average: 5.2, high_complexity_files: []}
  end

  defp check_documentation(_project_path) do
    # TODO: Implement documentation coverage analysis
    %{percentage: 70, missing_docs: []}
  end

  defp detect_duplication(_project_path) do
    # TODO: Implement code duplication detection
    %{duplicated_lines: 0, duplicate_blocks: []}
  end

  defp add_complexity_suggestions(suggestions, quality_data) do
    credo_score = get_in(quality_data, [:credo_score, :score]) || 100

    if credo_score < 80 do
      suggestion = %{
        type: :quality,
        priority: :high,
        description: "Code quality score is below threshold. Consider addressing Credo issues.",
        impact: :maintainability,
        action: :fix_credo_issues
      }

      [suggestion | suggestions]
    else
      suggestions
    end
  end

  defp add_structure_suggestions(suggestions, structure_data) do
    depth = Map.get(structure_data, :directory_depth, 0)

    if depth > 6 do
      suggestion = %{
        type: :structure,
        priority: :medium,
        description:
          "Directory structure is deeply nested. Consider flattening for better navigation.",
        impact: :usability,
        action: :flatten_structure
      }

      [suggestion | suggestions]
    else
      suggestions
    end
  end

  defp add_dependency_suggestions(suggestions, dependency_data) do
    unused_count = length(Map.get(dependency_data, :unused_deps, []))

    if unused_count > 0 do
      suggestion = %{
        type: :dependencies,
        priority: :low,
        description:
          "#{unused_count} unused dependencies detected. Consider removing for cleaner builds.",
        impact: :performance,
        action: :remove_unused_deps
      }

      [suggestion | suggestions]
    else
      suggestions
    end
  end

  defp prioritize_suggestions(suggestions) do
    priority_order = %{high: 3, medium: 2, low: 1}

    suggestions
    |> Enum.sort_by(
      fn suggestion ->
        priority_order[suggestion.priority] || 0
      end,
      :desc
    )
  end
end
