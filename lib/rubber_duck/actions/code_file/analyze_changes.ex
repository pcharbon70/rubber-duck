defmodule RubberDuck.Actions.CodeFile.AnalyzeChanges do
  @moduledoc """
  Action to analyze code changes and assess their impact.
  """

  use Jido.Action,
    name: "analyze_changes",
    description: "Analyzes code changes for quality and impact assessment",
    schema: [
      file_id: [type: :string, required: true],
      content: [type: :string, required: true],
      previous_content: [type: :string, required: false],
      analyze_depth: [type: :atom, default: :normal, values: [:shallow, :normal, :deep]]
    ]

  @impl true
  def run(params, _context) do
    with {:ok, changes} <- detect_changes(params),
         {:ok, metrics} <- calculate_quality_metrics(params.content),
         {:ok, issues} <- detect_issues(params.content, params.analyze_depth),
         {:ok, impact} <- assess_change_impact(changes, params.content) do

      {:ok, %{
        changes: changes,
        quality_score: calculate_quality_score(metrics, issues),
        complexity_score: metrics.complexity,
        maintainability_index: metrics.maintainability,
        issues: issues,
        impact: impact,
        lines_of_code: count_lines(params.content),
        analysis_timestamp: DateTime.utc_now()
      }}
    end
  end

  defp detect_changes(params) do
    if params.previous_content do
      changes = %{
        additions: count_additions(params.previous_content, params.content),
        deletions: count_deletions(params.previous_content, params.content),
        modifications: count_modifications(params.previous_content, params.content)
      }
      {:ok, changes}
    else
      {:ok, %{additions: count_lines(params.content), deletions: 0, modifications: 0}}
    end
  end

  defp calculate_quality_metrics(content) do
    metrics = %{
      complexity: calculate_cyclomatic_complexity(content),
      maintainability: calculate_maintainability_index(content),
      duplication: detect_duplication_ratio(content),
      nesting_depth: calculate_max_nesting(content)
    }
    {:ok, metrics}
  end

  defp detect_issues(content, depth) do
    issues = []

    # Basic issues (always checked)
    issues = issues ++ detect_syntax_issues(content)
    issues = issues ++ detect_formatting_issues(content)

    # Normal depth checks
    if depth in [:normal, :deep] do
      issues = issues ++ detect_complexity_issues(content)
      issues = issues ++ detect_naming_issues(content)
    end

    # Deep analysis
    if depth == :deep do
      issues = issues ++ detect_security_issues(content)
      issues = issues ++ detect_performance_issues(content)
    end

    {:ok, issues}
  end

  defp assess_change_impact(changes, content) do
    impact = %{
      risk_level: calculate_risk_level(changes),
      affected_functions: extract_modified_functions(content),
      breaking_changes: detect_breaking_changes(content),
      performance_impact: estimate_performance_impact(changes)
    }
    {:ok, impact}
  end

  defp calculate_quality_score(metrics, issues) do
    base_score = 100.0

    # Deduct for complexity
    complexity_penalty = min(metrics.complexity * 2, 30)

    # Deduct for issues
    issue_penalty = length(issues) * 5

    # Deduct for duplication
    duplication_penalty = metrics.duplication * 20

    score = base_score - complexity_penalty - issue_penalty - duplication_penalty
    max(0.0, min(100.0, score)) / 100.0
  end

  defp count_lines(content) do
    content
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == ""))
    |> length()
  end

  defp count_additions(old_content, new_content) do
    old_lines = String.split(old_content, "\n")
    new_lines = String.split(new_content, "\n")

    max(0, length(new_lines) - length(old_lines))
  end

  defp count_deletions(old_content, new_content) do
    old_lines = String.split(old_content, "\n")
    new_lines = String.split(new_content, "\n")

    max(0, length(old_lines) - length(new_lines))
  end

  defp count_modifications(_old_content, _new_content) do
    # Simplified for now
    0
  end

  defp calculate_cyclomatic_complexity(content) do
    # Count decision points
    decision_keywords = ~w(if unless case cond with and or && ||)

    Enum.reduce(decision_keywords, 1, fn keyword, acc ->
      count = content
        |> String.split()
        |> Enum.count(&(&1 == keyword))
      acc + count
    end)
  end

  defp calculate_maintainability_index(content) do
    loc = count_lines(content)
    complexity = calculate_cyclomatic_complexity(content)

    # Simplified maintainability index
    base = 171.0
    loc_factor = 5.2 * :math.log(max(1, loc))
    complexity_factor = 0.23 * complexity

    index = base - loc_factor - complexity_factor
    max(0.0, min(100.0, index))
  end

  defp detect_duplication_ratio(content) do
    lines = String.split(content, "\n")
    unique_lines = Enum.uniq(lines)

    if length(lines) > 0 do
      1.0 - (length(unique_lines) / length(lines))
    else
      0.0
    end
  end

  defp calculate_max_nesting(content) do
    lines = String.split(content, "\n")

    lines
    |> Enum.map(&calculate_line_nesting/1)
    |> Enum.max(fn -> 0 end)
  end

  defp calculate_line_nesting(line) do
    indent = String.length(line) - String.length(String.trim_leading(line))
    div(indent, 2)
  end

  defp detect_syntax_issues(content) do
    issues = []

    # Check for common syntax issues
    if String.contains?(content, "  end") do
      issues = [%{
        type: :syntax,
        severity: :minor,
        message: "Inconsistent indentation before 'end'"
      } | issues]
    end

    issues
  end

  defp detect_formatting_issues(content) do
    issues = []
    lines = String.split(content, "\n")

    # Check line length
    long_lines = lines
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _} -> String.length(line) > 120 end)

    if length(long_lines) > 0 do
      issues = [%{
        type: :formatting,
        severity: :minor,
        message: "#{length(long_lines)} lines exceed 120 characters"
      } | issues]
    end

    issues
  end

  defp detect_complexity_issues(content) do
    issues = []
    complexity = calculate_cyclomatic_complexity(content)

    if complexity > 10 do
      issues = [%{
        type: :complexity,
        severity: if(complexity > 20, do: :major, else: :moderate),
        message: "High cyclomatic complexity: #{complexity}"
      } | issues]
    end

    issues
  end

  defp detect_naming_issues(content) do
    issues = []

    # Check for non-snake_case function names
    if Regex.match?(~r/def\s+[A-Z]/, content) do
      issues = [%{
        type: :naming,
        severity: :minor,
        message: "Function names should use snake_case"
      } | issues]
    end

    issues
  end

  defp detect_security_issues(content) do
    issues = []

    # Check for potential security issues
    if String.contains?(content, "eval(") do
      issues = [%{
        type: :security,
        severity: :critical,
        message: "Potential code injection vulnerability: eval() usage"
      } | issues]
    end

    if Regex.match?(~r/password\s*=\s*"[^"]+"/i, content) do
      issues = [%{
        type: :security,
        severity: :critical,
        message: "Hardcoded password detected"
      } | issues]
    end

    issues
  end

  defp detect_performance_issues(content) do
    issues = []

    # Check for performance anti-patterns
    if String.contains?(content, "Enum.map") && String.contains?(content, "|> Enum.filter") do
      issues = [%{
        type: :performance,
        severity: :minor,
        message: "Consider using Stream for chained operations"
      } | issues]
    end

    issues
  end

  defp calculate_risk_level(changes) do
    total_changes = changes.additions + changes.deletions + changes.modifications

    cond do
      total_changes > 100 -> :high
      total_changes > 50 -> :medium
      total_changes > 10 -> :low
      true -> :minimal
    end
  end

  defp extract_modified_functions(content) do
    content
    |> then(&Regex.scan(~r/def(?:p?)\s+(\w+)/, &1))
    |> Enum.map(fn [_, name] -> name end)
  end

  defp detect_breaking_changes(content) do
    # Check for removed public functions or changed signatures
    []
  end

  defp estimate_performance_impact(changes) do
    if changes.additions > changes.deletions do
      :potential_degradation
    else
      :neutral
    end
  end
end
