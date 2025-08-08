defmodule RubberDuck.Analyzers.Code.Impact do
  @moduledoc """
  Impact assessment analyzer for code changes.

  Analyzes the potential impact of code changes including dependency analysis,
  risk assessment, performance implications, and change propagation effects.

  ## Supported Analysis Types

  - Direct impact assessment on modified code
  - Dependency chain analysis and impact propagation
  - Risk assessment with severity classification
  - Performance impact estimation
  - Test coverage impact analysis  
  - Breaking change detection

  ## Integration

  This analyzer extracts impact assessment logic from CodeAnalysisSkill
  while maintaining the same analysis capabilities in a focused module.
  """

  @behaviour RubberDuck.Analyzer

  alias RubberDuck.Messages.Code.{Analyze, ImpactAssess}

  @impl true
  def analyze(%Analyze{analysis_type: :impact} = msg, context) do
    state = context[:state] || %{}

    # Convert Analyze message to impact assessment data
    changes = %{
      file_path: msg.file_path,
      lines_changed: context[:lines_changed] || 0,
      functions_modified: context[:functions_modified] || [],
      modules_affected: context[:modules_affected] || [],
      complexity_delta: context[:complexity_delta] || 0,
      test_coverage_delta: context[:test_coverage_delta] || 0.0,
      breaking_changes: context[:breaking_changes],
      api_changes: context[:api_changes],
      internal_only: context[:internal_only]
    }

    impact_analysis = %{
      file_path: msg.file_path,
      direct_impact: analyze_direct_impact(changes, state),
      dependency_impact: analyze_dependency_impact(msg.file_path, state),
      performance_impact: estimate_performance_impact(changes),
      risk_assessment: assess_change_risk(changes, state),
      affected_files: find_affected_files(msg.file_path, state),
      test_coverage_impact: assess_test_coverage_impact(changes),
      scope: determine_impact_scope(changes),
      severity: calculate_impact_severity(changes),
      estimated_effort: estimate_fix_effort(changes),
      rollback_complexity: assess_rollback_complexity(changes),
      analyzed_at: DateTime.utc_now()
    }

    {:ok, impact_analysis}
  end

  def analyze(%Analyze{analysis_type: :comprehensive} = msg, context) do
    # For comprehensive analysis, return impact subset
    analyze(%{msg | analysis_type: :impact}, context)
  end

  def analyze(%ImpactAssess{} = msg, context) do
    state = context[:state] || %{}

    impact_result = %{
      file_path: msg.file_path,
      direct_impact: analyze_direct_impact(msg.changes, state),
      dependency_impact: analyze_dependency_impact(msg.file_path, state),
      performance_impact: estimate_performance_impact(msg.changes),
      risk_score: calculate_impact_risk_score(msg.changes),
      risk_assessment: assess_change_risk(msg.changes, state),
      affected_files: identify_affected_files(msg.file_path, state),
      suggested_tests: suggest_tests_for_changes(msg.changes),
      test_coverage_impact: assess_test_coverage_impact(msg.changes),
      scope: determine_impact_scope(msg.changes),
      severity: calculate_impact_severity(msg.changes),
      analyzed_at: DateTime.utc_now()
    }

    # Emit warning if high risk detected
    if impact_result.risk_assessment.level == :high do
      # Note: In a real implementation, this would use proper event emission
      # For now, we'll just log the high risk
      require Logger

      Logger.warning(
        "High risk detected for #{msg.file_path}: #{inspect(impact_result.risk_assessment)}"
      )
    end

    {:ok, impact_result}
  end

  def analyze(message, _context) do
    {:error, {:unsupported_message_type, message.__struct__}}
  end

  @impl true
  def supported_types do
    [Analyze, ImpactAssess]
  end

  @impl true
  def priority, do: :high

  @impl true
  def timeout, do: 15_000

  @impl true
  def metadata do
    %{
      name: "Impact Analyzer",
      description:
        "Analyzes code change impact including dependencies, risks, and performance implications",
      version: "1.0.0",
      categories: [:impact, :code, :risk],
      tags: ["impact", "dependencies", "risk", "performance", "changes"]
    }
  end

  # Core impact analysis functions extracted from CodeAnalysisSkill

  defp analyze_direct_impact(changes, _state) do
    %{
      lines_affected: changes[:lines_changed] || changes[:lines_affected] || 0,
      functions_modified: changes[:functions_modified] || [],
      modules_affected: changes[:modules_affected] || [],
      api_changes: detect_api_changes(changes),
      breaking_changes: detect_breaking_changes(changes)
    }
  end

  defp analyze_dependency_impact(file_path, state) do
    dependencies = get_file_dependencies(file_path, state)

    %{
      direct_dependencies: length(dependencies.direct),
      transitive_dependencies: length(dependencies.transitive),
      affected_modules: dependencies.affected_modules,
      impact_radius: calculate_impact_radius(dependencies),
      critical_paths: identify_critical_paths(dependencies)
    }
  end

  defp estimate_performance_impact(changes) do
    %{
      complexity_change: changes[:complexity_delta] || 0,
      memory_impact: estimate_memory_change(changes),
      runtime_impact: estimate_runtime_change(changes),
      database_impact: estimate_database_impact(changes),
      overall_impact: determine_overall_performance_impact(changes)
    }
  end

  defp assess_change_risk(changes, _state) do
    risk_factors = []

    risk_factors =
      if changes[:breaking_changes] == true do
        [{:breaking_changes, 0.8} | risk_factors]
      else
        risk_factors
      end

    risk_factors =
      if (changes[:complexity_delta] || 0) > 5 do
        [{:high_complexity_increase, 0.6} | risk_factors]
      else
        risk_factors
      end

    risk_factors =
      if (changes[:test_coverage_delta] || 0) < -0.1 do
        [{:reduced_test_coverage, 0.7} | risk_factors]
      else
        risk_factors
      end

    risk_factors =
      if (changes[:lines_changed] || changes[:lines_affected] || 0) > 100 do
        [{:large_change_set, 0.5} | risk_factors]
      else
        risk_factors
      end

    risk_score = Enum.reduce(risk_factors, 0.0, fn {_, weight}, acc -> acc + weight end)

    %{
      level: determine_risk_level(risk_score),
      score: risk_score,
      factors: risk_factors,
      mitigation_suggestions: suggest_risk_mitigation(risk_factors)
    }
  end

  defp find_affected_files(file_path, state) do
    # Find files that depend on the changed file
    analysis_history = Map.get(state, :analysis_history, %{})

    Enum.filter(Map.keys(analysis_history), fn path ->
      path != file_path && file_depends_on?(path, file_path, state)
    end)
  end

  defp assess_test_coverage_impact(changes) do
    %{
      coverage_delta: changes[:test_coverage_delta] || 0,
      uncovered_lines: changes[:uncovered_lines] || [],
      test_suggestions: suggest_tests_for_changes(changes),
      priority: determine_test_priority(changes)
    }
  end

  defp determine_impact_scope(data) do
    cond do
      data[:breaking_changes] == true -> :major
      data[:api_changes] == true -> :moderate
      data[:internal_only] == true -> :minor
      data[:modules_affected] && length(data[:modules_affected]) > 3 -> :moderate
      data[:functions_modified] && length(data[:functions_modified]) > 5 -> :moderate
      true -> :minimal
    end
  end

  defp calculate_impact_severity(data) do
    severity_score = 0
    severity_score = severity_score + if data[:breaking_changes] == true, do: 10, else: 0
    severity_score = severity_score + if data[:api_changes] == true, do: 5, else: 0
    severity_score = severity_score + if (data[:complexity_delta] || 0) > 5, do: 3, else: 0

    severity_score =
      severity_score +
        if (data[:lines_changed] || data[:lines_affected] || 0) > 100, do: 2, else: 0

    cond do
      severity_score >= 10 -> :critical
      severity_score >= 7 -> :high
      severity_score >= 4 -> :medium
      severity_score >= 2 -> :low
      true -> :minimal
    end
  end

  defp estimate_fix_effort(data) do
    base_effort = data[:lines_changed] || data[:lines_affected] || 0
    complexity_factor = max(data[:complexity_delta] || 0, 1)

    effort_hours = base_effort * complexity_factor / 50

    cond do
      effort_hours < 1 -> :trivial
      effort_hours < 4 -> :small
      effort_hours < 8 -> :medium
      effort_hours < 16 -> :large
      true -> :extra_large
    end
  end

  defp assess_rollback_complexity(data) do
    cond do
      data[:database_changes] == true || data[:external_api_changes] == true -> :complex
      data[:breaking_changes] == true -> :moderate
      data[:modules_affected] && length(data[:modules_affected]) > 5 -> :moderate
      true -> :simple
    end
  end

  # Helper functions

  defp detect_api_changes(changes) do
    changes[:api_changes] || false
  end

  defp detect_breaking_changes(changes) do
    changes[:breaking_changes] || false
  end

  defp get_file_dependencies(file_path, state) do
    # In a real implementation, this would use dependency tracking
    # For now, return a simplified structure based on state
    dependencies = Map.get(state, :dependencies, %{})
    file_deps = Map.get(dependencies, file_path, %{direct: [], transitive: []})

    %{
      direct: file_deps[:direct] || [],
      transitive: file_deps[:transitive] || [],
      affected_modules: extract_affected_modules(file_deps)
    }
  end

  defp extract_affected_modules(file_deps) do
    (file_deps[:direct] || [])
    |> Enum.concat(file_deps[:transitive] || [])
    |> Enum.map(&extract_module_name/1)
    |> Enum.uniq()
  end

  defp extract_module_name(file_path) do
    file_path
    |> Path.basename()
    |> Path.rootname()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("")
  end

  defp calculate_impact_radius(dependencies) do
    direct_count = length(dependencies.direct)
    transitive_count = length(dependencies.transitive)

    # Weight direct dependencies more heavily than transitive
    direct_count + transitive_count * 0.5
  end

  defp identify_critical_paths(dependencies) do
    # In a real implementation, this would identify critical dependency paths
    # For now, return a simplified list based on direct dependencies
    dependencies.direct
    |> Enum.filter(&is_critical_dependency?/1)
  end

  defp is_critical_dependency?(file_path) do
    # Simple heuristic: files with certain patterns are considered critical
    critical_patterns = ["auth", "security", "payment", "core", "base"]

    Enum.any?(critical_patterns, fn pattern ->
      String.contains?(String.downcase(file_path), pattern)
    end)
  end

  defp estimate_memory_change(changes) do
    changes[:memory_delta] || changes[:memory_impact] || 0
  end

  defp estimate_runtime_change(changes) do
    # Estimate based on complexity delta and lines changed
    complexity_impact = (changes[:complexity_delta] || 0) * 0.1
    size_impact = (changes[:lines_changed] || changes[:lines_affected] || 0) * 0.01

    complexity_impact + size_impact
  end

  defp estimate_database_impact(changes) do
    changes[:database_operations_delta] || 0
  end

  defp determine_overall_performance_impact(changes) do
    complexity_delta = changes[:complexity_delta] || 0
    memory_delta = changes[:memory_delta] || 0
    runtime_delta = estimate_runtime_change(changes)

    total_impact = complexity_delta + memory_delta + runtime_delta

    cond do
      total_impact > 5 -> :negative
      total_impact > 2 -> :slightly_negative
      total_impact > -2 -> :neutral
      total_impact > -5 -> :slightly_positive
      true -> :positive
    end
  end

  defp determine_risk_level(risk_score) do
    cond do
      risk_score >= 1.5 -> :critical
      risk_score >= 1.0 -> :high
      risk_score >= 0.5 -> :medium
      risk_score >= 0.3 -> :low
      true -> :minimal
    end
  end

  defp suggest_risk_mitigation(risk_factors) do
    Enum.map(risk_factors, fn {factor, _} ->
      case factor do
        :breaking_changes -> "Add compatibility layer or deprecation warnings"
        :high_complexity_increase -> "Break down complex changes into smaller commits"
        :reduced_test_coverage -> "Add tests before merging"
        :large_change_set -> "Split large changes into smaller, focused commits"
        _ -> "Review changes carefully and add monitoring"
      end
    end)
  end

  defp file_depends_on?(dependent_file, target_file, state) do
    # In a real implementation, this would check actual dependencies
    # For now, use a simplified heuristic based on state
    dependencies = Map.get(state, :dependencies, %{})
    deps = Map.get(dependencies, dependent_file, %{direct: [], transitive: []})

    target_file in (deps[:direct] || []) or target_file in (deps[:transitive] || [])
  end

  defp suggest_tests_for_changes(changes) do
    suggestions = []

    suggestions =
      if changes[:new_functions] do
        ["Add unit tests for new functions" | suggestions]
      else
        suggestions
      end

    suggestions =
      if changes[:modified_functions] do
        ["Update tests for modified functions" | suggestions]
      else
        suggestions
      end

    suggestions =
      if changes[:api_changes] do
        ["Add integration tests for API changes" | suggestions]
      else
        suggestions
      end

    suggestions =
      if changes[:breaking_changes] do
        ["Add regression tests for breaking changes" | suggestions]
      else
        suggestions
      end

    suggestions
  end

  defp determine_test_priority(changes) do
    cond do
      changes[:breaking_changes] -> :critical
      changes[:api_changes] -> :high
      changes[:functions_modified] && length(changes[:functions_modified]) > 3 -> :high
      (changes[:lines_changed] || changes[:lines_affected] || 0) > 50 -> :medium
      true -> :normal
    end
  end

  defp calculate_impact_risk_score(changes) when is_map(changes) do
    # Calculate risk based on the nature and scope of changes
    base_risk = map_size(changes) * 10

    # Add risk for critical file changes - check file_path in changes
    file_path = changes[:file_path] || ""

    has_critical_changes =
      String.contains?(String.downcase(file_path), ["auth", "security", "payment", "core"])

    critical_risk = if has_critical_changes, do: 40, else: 0

    # Add risk for large changes
    size_risk =
      if (changes[:lines_changed] || changes[:lines_affected] || 0) > 100, do: 30, else: 0

    # Add risk for breaking changes
    breaking_risk = if changes[:breaking_changes] == true, do: 50, else: 0

    # Add risk for many modules affected
    modules_risk =
      if changes[:modules_affected] && length(changes[:modules_affected]) > 2, do: 20, else: 0

    min(base_risk + critical_risk + size_risk + breaking_risk + modules_risk, 100) / 100.0
  end

  defp calculate_impact_risk_score(_), do: 0.0

  defp identify_affected_files(file_path, _state) do
    # In a real implementation, this would use dependency tracking
    # For now, return a sample list based on common patterns
    base_name = Path.basename(file_path, ".ex")

    [
      "#{file_path |> String.replace(".ex", "_test.exs")}",
      "test/#{base_name}_test.exs",
      "#{file_path |> String.replace(".ex", "_integration_test.exs")}",
      # Add related files based on common patterns
      String.replace(file_path, ".ex", "_behaviour.ex"),
      String.replace(file_path, ".ex", "_impl.ex")
    ]
    |> Enum.filter(&(&1 != file_path))
    # Limit to reasonable number
    |> Enum.take(5)
  end
end
