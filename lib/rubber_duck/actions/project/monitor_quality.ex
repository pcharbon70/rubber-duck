defmodule RubberDuck.Actions.Project.MonitorQuality do
  @moduledoc """
  Action to monitor code quality metrics for a project.
  """

  use Jido.Action,
    name: "monitor_quality",
    description: "Monitors code quality metrics and identifies issues",
    schema: [
      project_id: [type: :string, required: true],
      include_patterns: [type: {:list, :string}, default: ["**/*.ex", "**/*.exs"]],
      exclude_patterns: [type: {:list, :string}, default: ["deps/", "_build/", "test/"]],
      metrics_config: [
        type: :map,
        default: %{
          max_complexity: 10,
          max_nesting: 4,
          max_line_length: 120,
          max_function_length: 50
        }
      ]
    ]

  alias RubberDuck.Projects

  @impl true
  def run(params, _context) do
    with {:ok, project} <- Projects.get_project(params.project_id),
         {:ok, files} <- get_project_files(project, params),
         file_metrics <- analyze_files(files, params.metrics_config),
         project_metrics <- aggregate_metrics(file_metrics),
         issues <- detect_quality_issues(file_metrics, params.metrics_config) do
      {:ok,
       %{
         project_metrics: project_metrics,
         file_metrics: file_metrics,
         issues: issues,
         quality_score: calculate_quality_score(project_metrics, issues),
         analyzed_at: DateTime.utc_now()
       }}
    end
  end

  defp get_project_files(project, params) do
    case Projects.list_code_files_by_project(project.id) do
      {:ok, files} ->
        filtered =
          files
          |> Enum.filter(&matches_patterns?(&1.path, params.include_patterns))
          |> Enum.reject(&matches_patterns?(&1.path, params.exclude_patterns))
          # Only files with content
          |> Enum.filter(& &1.content)

        {:ok, filtered}

      error ->
        error
    end
  end

  defp matches_patterns?(path, patterns) do
    Enum.any?(patterns, fn pattern ->
      # Simple pattern matching using wildcards
      pattern_regex =
        pattern
        |> String.replace("*", ".*")
        |> String.replace("?", ".")
        |> Regex.compile!()

      Regex.match?(pattern_regex, path)
    end)
  end

  defp analyze_files(files, metrics_config) do
    Enum.map(files, fn file ->
      %{
        path: file.path,
        metrics: analyze_file_content(file, metrics_config),
        issues: []
      }
    end)
  end

  defp analyze_file_content(file, _metrics_config) do
    lines = String.split(file.content, "\n")

    %{
      total_lines: length(lines),
      code_lines: count_code_lines(lines),
      comment_lines: count_comment_lines(lines),
      blank_lines: count_blank_lines(lines),
      functions: analyze_functions(file.content),
      complexity: calculate_complexity(file.content),
      nesting_depth: calculate_max_nesting(lines),
      duplication: detect_duplication(lines),
      line_lengths: analyze_line_lengths(lines)
    }
  end

  defp count_code_lines(lines) do
    lines
    |> Enum.reject(&blank_or_comment?/1)
    |> length()
  end

  defp count_comment_lines(lines) do
    lines
    |> Enum.count(&comment_line?/1)
  end

  defp count_blank_lines(lines) do
    lines
    |> Enum.count(&(String.trim(&1) == ""))
  end

  defp blank_or_comment?(line) do
    trimmed = String.trim(line)
    trimmed == "" || comment_line?(line)
  end

  defp comment_line?(line) do
    trimmed = String.trim(line)
    String.starts_with?(trimmed, "#")
  end

  defp analyze_functions(content) do
    # Extract function definitions
    def_regex = ~r/def(?:p?)\s+(\w+)/

    functions =
      content
      |> then(&Regex.scan(def_regex, &1))
      |> Enum.map(fn [_, name] -> name end)
      |> Enum.map(fn name ->
        %{
          name: name,
          length: estimate_function_length(content, name),
          complexity: estimate_function_complexity(content, name)
        }
      end)

    %{
      count: length(functions),
      functions: functions,
      average_length: calculate_average_length(functions),
      max_length: calculate_max_length(functions)
    }
  end

  defp estimate_function_length(content, function_name) do
    # Simple heuristic: count lines from function def to next def or end of module
    lines = String.split(content, "\n")

    start_index =
      Enum.find_index(lines, fn line ->
        line =~ ~r/def(?:p?)\s+#{function_name}/
      end)

    if start_index do
      end_index = find_function_end(lines, start_index)
      end_index - start_index + 1
    else
      0
    end
  end

  defp find_function_end(lines, start_index) do
    # Look for the matching 'end' or next 'def'
    indent_level = get_indent_level(Enum.at(lines, start_index))

    # Search from start_index + 1 to end of lines
    result =
      lines
      |> Enum.slice((start_index + 1)..(length(lines) - 1))
      |> Enum.find_index(fn line ->
        current_indent = get_indent_level(line)
        trimmed = String.trim(line)

        (current_indent <= indent_level && trimmed == "end") ||
          line =~ ~r/^\s*def(?:p?)\s+/
      end)

    case result do
      nil -> length(lines) - 1
      idx -> idx + start_index + 1
    end
  end

  defp get_indent_level(line) do
    line
    |> String.replace(~r/[^\s].*/, "")
    |> String.length()
  end

  defp estimate_function_complexity(content, function_name) do
    # Count control flow statements within the function
    function_body = extract_function_body(content, function_name)

    # Base complexity
    complexity = 1

    # Count control flow keywords
    control_flow = ["if", "unless", "case", "cond", "with", "for", "while"]

    Enum.reduce(control_flow, complexity, fn keyword, acc ->
      matches = Regex.scan(~r/\b#{keyword}\b/, function_body)
      acc + length(matches)
    end)
  end

  defp extract_function_body(content, function_name) do
    # Simple extraction - would be more sophisticated in production
    lines = String.split(content, "\n")

    start_index =
      Enum.find_index(lines, fn line ->
        line =~ ~r/def(?:p?)\s+#{function_name}/
      end)

    if start_index do
      end_index = find_function_end(lines, start_index)

      lines
      |> Enum.slice(start_index..end_index)
      |> Enum.join("\n")
    else
      ""
    end
  end

  defp calculate_average_length(functions) do
    if length(functions) > 0 do
      total = Enum.sum(Enum.map(functions, & &1.length))
      total / length(functions)
    else
      0
    end
  end

  defp calculate_max_length(functions) do
    if length(functions) > 0 do
      functions
      |> Enum.map(& &1.length)
      |> Enum.max()
    else
      0
    end
  end

  defp calculate_complexity(content) do
    # Cyclomatic complexity calculation
    base_complexity = 1

    # Count decision points
    decision_patterns = [
      ~r/\bif\b/,
      ~r/\bunless\b/,
      ~r/\bcase\b.*\bdo\b/,
      ~r/\bcond\b.*\bdo\b/,
      ~r/\band\b/,
      ~r/\bor\b/,
      ~r/\&\&/,
      ~r/\|\|/,
      # Function clauses
      ~r/->/
    ]

    Enum.reduce(decision_patterns, base_complexity, fn pattern, acc ->
      matches = Regex.scan(pattern, content)
      acc + length(matches)
    end)
  end

  defp calculate_max_nesting(lines) do
    lines
    |> Enum.map(&calculate_nesting_level/1)
    |> Enum.max(fn -> 0 end)
  end

  defp calculate_nesting_level(line) do
    # Count nesting based on indentation and keywords
    indent = get_indent_level(line)
    # Assuming 2-space indentation
    indent_nesting = div(indent, 2)

    # Additional nesting for certain keywords
    keyword_nesting =
      cond do
        line =~ ~r/\bdo\b/ -> 1
        line =~ ~r/->/ -> 1
        true -> 0
      end

    indent_nesting + keyword_nesting
  end

  defp detect_duplication(lines) do
    # Simple duplication detection - count repeated lines
    line_counts =
      lines
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.frequencies()

    duplicated_lines =
      line_counts
      |> Enum.filter(fn {_, count} -> count > 1 end)
      |> Enum.map(fn {line, count} -> %{line: line, count: count} end)

    %{
      duplicated_line_count: length(duplicated_lines),
      duplication_ratio: calculate_duplication_ratio(line_counts),
      # Top 5
      duplicated_lines: Enum.take(duplicated_lines, 5)
    }
  end

  defp calculate_duplication_ratio(line_counts) do
    total_lines =
      line_counts
      |> Enum.map(fn {_, count} -> count end)
      |> Enum.sum()

    unique_lines = map_size(line_counts)

    if total_lines > 0 do
      1.0 - unique_lines / total_lines
    else
      0.0
    end
  end

  defp analyze_line_lengths(lines) do
    lengths = Enum.map(lines, &String.length/1)

    %{
      max_length: Enum.max(lengths, fn -> 0 end),
      average_length:
        if length(lengths) > 0 do
          Enum.sum(lengths) / length(lengths)
        else
          0
        end,
      long_lines: Enum.count(lengths, &(&1 > 120))
    }
  end

  defp aggregate_metrics(file_metrics) do
    total_files = length(file_metrics)

    if total_files == 0 do
      default_metrics()
    else
      %{
        total_files: total_files,
        total_lines: sum_metric(file_metrics, [:metrics, :total_lines]),
        total_code_lines: sum_metric(file_metrics, [:metrics, :code_lines]),
        total_comment_lines: sum_metric(file_metrics, [:metrics, :comment_lines]),
        total_functions: sum_metric(file_metrics, [:metrics, :functions, :count]),
        average_file_length: average_metric(file_metrics, [:metrics, :total_lines]),
        average_complexity: average_metric(file_metrics, [:metrics, :complexity]),
        max_complexity: max_metric(file_metrics, [:metrics, :complexity]),
        average_nesting: average_metric(file_metrics, [:metrics, :nesting_depth]),
        max_nesting: max_metric(file_metrics, [:metrics, :nesting_depth]),
        duplication_ratio:
          average_metric(file_metrics, [:metrics, :duplication, :duplication_ratio])
      }
    end
  end

  defp default_metrics do
    %{
      total_files: 0,
      total_lines: 0,
      total_code_lines: 0,
      total_comment_lines: 0,
      total_functions: 0,
      average_file_length: 0,
      average_complexity: 0,
      max_complexity: 0,
      average_nesting: 0,
      max_nesting: 0,
      duplication_ratio: 0
    }
  end

  defp sum_metric(file_metrics, path) do
    file_metrics
    |> Enum.map(&get_in(&1, path))
    |> Enum.filter(& &1)
    |> Enum.sum()
  end

  defp average_metric(file_metrics, path) do
    values =
      file_metrics
      |> Enum.map(&get_in(&1, path))
      |> Enum.filter(& &1)

    if length(values) > 0 do
      Enum.sum(values) / length(values)
    else
      0
    end
  end

  defp max_metric(file_metrics, path) do
    file_metrics
    |> Enum.map(&get_in(&1, path))
    |> Enum.filter(& &1)
    |> Enum.max(fn -> 0 end)
  end

  defp detect_quality_issues(file_metrics, metrics_config) do
    file_metrics
    |> Enum.flat_map(fn file ->
      detect_file_issues(file, metrics_config)
    end)
    |> Enum.sort_by(& &1.severity, &severity_order/2)
  end

  defp detect_file_issues(file, config) do
    issues = []
    metrics = file.metrics

    # Complexity issues
    issues =
      if metrics.complexity > config.max_complexity do
        [
          {:high_complexity,
           %{
             file: file.path,
             complexity: metrics.complexity,
             threshold: config.max_complexity,
             severity: :high,
             message:
               "File complexity (#{metrics.complexity}) exceeds threshold (#{config.max_complexity})"
           }}
          | issues
        ]
      else
        issues
      end

    # Nesting depth issues
    issues =
      if metrics.nesting_depth > config.max_nesting do
        [
          {:deep_nesting,
           %{
             file: file.path,
             nesting: metrics.nesting_depth,
             threshold: config.max_nesting,
             severity: :medium,
             message:
               "Maximum nesting depth (#{metrics.nesting_depth}) exceeds threshold (#{config.max_nesting})"
           }}
          | issues
        ]
      else
        issues
      end

    # Long lines
    issues =
      if metrics.line_lengths.max_length > config.max_line_length do
        [
          {:long_lines,
           %{
             file: file.path,
             max_length: metrics.line_lengths.max_length,
             threshold: config.max_line_length,
             severity: :low,
             message: "Found lines longer than #{config.max_line_length} characters"
           }}
          | issues
        ]
      else
        issues
      end

    # Long functions
    issues =
      if metrics.functions.max_length > config.max_function_length do
        [
          {:long_functions,
           %{
             file: file.path,
             max_length: metrics.functions.max_length,
             threshold: config.max_function_length,
             severity: :medium,
             message: "Found functions longer than #{config.max_function_length} lines"
           }}
          | issues
        ]
      else
        issues
      end

    # Duplication
    issues =
      if metrics.duplication.duplication_ratio > 0.1 do
        [
          {:code_duplication,
           %{
             file: file.path,
             ratio: metrics.duplication.duplication_ratio,
             severity: :medium,
             message:
               "High code duplication ratio: #{Float.round(metrics.duplication.duplication_ratio * 100, 1)}%"
           }}
          | issues
        ]
      else
        issues
      end

    Enum.map(issues, fn {type, data} ->
      Map.merge(data, %{type: type})
    end)
  end

  defp severity_order(:high, :high), do: true
  defp severity_order(:high, _), do: true
  defp severity_order(:medium, :low), do: true
  defp severity_order(:medium, :medium), do: true
  defp severity_order(_, _), do: false

  defp calculate_quality_score(metrics, issues) do
    base_score = 100.0

    # Deduct points based on issues
    issue_deductions = %{
      high: 10,
      medium: 5,
      low: 2
    }

    total_deduction =
      issues
      |> Enum.map(&Map.get(issue_deductions, &1.severity, 0))
      |> Enum.sum()

    # Additional deductions based on metrics
    complexity_deduction = if metrics.average_complexity > 15, do: 10, else: 0
    duplication_deduction = metrics.duplication_ratio * 20

    score = base_score - total_deduction - complexity_deduction - duplication_deduction

    max(0, min(100, score))
  end
end
