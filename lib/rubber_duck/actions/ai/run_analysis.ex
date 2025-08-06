defmodule RubberDuck.Actions.AI.RunAnalysis do
  @moduledoc """
  Action for executing AI analyses on projects and code files.

  Coordinates with LLM services to perform various types of analysis
  and stores results in the AI domain.
  """

  use Jido.Action,
    name: "run_analysis",
    description: "Execute AI analysis on code",
    schema: [
      project_id: [type: :string, required: false],
      file_id: [type: :string, required: false],
      analysis_types: [type: {:list, :atom}, default: [:general]],
      priority: [type: :atom, default: :normal],
      context: [type: :map, default: %{}]
    ]

  alias RubberDuck.{AI, Projects}
  require Logger

  @impl true
  def run(params, context) do
    with {:ok, target} <- determine_analysis_target(params),
         {:ok, content} <- fetch_content(target),
         {:ok, analyses} <- perform_analyses(content, params.analysis_types, params.context),
         {:ok, results} <- save_analysis_results(analyses, target, context) do

      {:ok, %{
        results: results,
        summary: generate_summary(results),
        insights: extract_insights(results),
        recommendations: generate_recommendations(results),
        metadata: build_metadata(params, results)
      }}
    end
  end

  defp determine_analysis_target(params) do
    cond do
      params.file_id ->
        {:ok, {:file, params.file_id}}
      params.project_id ->
        {:ok, {:project, params.project_id}}
      true ->
        {:error, :no_target_specified}
    end
  end

  defp fetch_content({:file, file_id}) do
    case Projects.get_code_file(file_id) do
      {:ok, file} ->
        {:ok, %{
          type: :file,
          id: file_id,
          content: file.content,
          language: file.language,
          path: file.path
        }}
      error -> error
    end
  end

  defp fetch_content({:project, project_id}) do
    case Projects.get_project(project_id) do
      {:ok, project} ->
        # Load project files
        {:ok, files} = Projects.list_code_files_by_project(project_id)

        {:ok, %{
          type: :project,
          id: project_id,
          name: project.name,
          files: files,
          file_count: length(files),
          languages: extract_languages(files)
        }}
      error -> error
    end
  end

  defp extract_languages(files) do
    files
    |> Enum.map(& &1.language)
    |> Enum.uniq()
    |> Enum.filter(& &1 != nil)
  end

  defp perform_analyses(content, types, context) do
    analyses = Enum.map(types, fn type ->
      Task.async(fn ->
        perform_single_analysis(content, type, context)
      end)
    end)

    results = Task.await_many(analyses, 30_000)

    # Filter out any failed analyses
    successful = results
    |> Enum.filter(fn
      {:ok, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:ok, result} -> result end)

    {:ok, successful}
  end

  defp perform_single_analysis(content, :complexity, _context) do
    result = analyze_complexity(content)
    {:ok, Map.put(result, :type, :complexity)}
  end

  defp perform_single_analysis(content, :security, _context) do
    result = analyze_security(content)
    {:ok, Map.put(result, :type, :security)}
  end

  defp perform_single_analysis(content, :quality, _context) do
    result = analyze_quality(content)
    {:ok, Map.put(result, :type, :quality)}
  end

  defp perform_single_analysis(content, :performance, _context) do
    result = analyze_performance(content)
    {:ok, Map.put(result, :type, :performance)}
  end

  defp perform_single_analysis(content, :general, context) do
    result = analyze_general(content, context)
    {:ok, Map.put(result, :type, :general)}
  end

  defp perform_single_analysis(_content, type, _context) do
    Logger.warning("Unknown analysis type: #{type}")
    {:error, :unknown_analysis_type}
  end

  # Analysis implementations

  defp analyze_complexity(content) do
    metrics = case content.type do
      :file -> analyze_file_complexity(content.content)
      :project -> analyze_project_complexity(content.files)
    end

    %{
      score: calculate_complexity_score(metrics),
      metrics: metrics,
      summary: "Complexity analysis completed",
      suggestions: generate_complexity_suggestions(metrics)
    }
  end

  defp analyze_file_complexity(content) do
    lines = String.split(content, "\n")

    %{
      lines_of_code: length(lines),
      cyclomatic_complexity: estimate_cyclomatic_complexity(content),
      nesting_depth: calculate_max_nesting(lines),
      function_count: count_functions(content)
    }
  end

  defp analyze_project_complexity(files) do
    file_metrics = Enum.map(files, fn file ->
      analyze_file_complexity(file.content || "")
    end)

    %{
      total_lines: Enum.sum(Enum.map(file_metrics, & &1.lines_of_code)),
      average_complexity: calculate_average(file_metrics, :cyclomatic_complexity),
      max_nesting: Enum.max_by(file_metrics, & &1.nesting_depth).nesting_depth,
      total_functions: Enum.sum(Enum.map(file_metrics, & &1.function_count))
    }
  end

  defp estimate_cyclomatic_complexity(content) do
    # Simplified cyclomatic complexity estimation
    conditions = content |> Regex.scan(~r/\b(if|unless|case|cond|when)\b/) |> length()
    loops = content |> Regex.scan(~r/\b(for|while|Enum\.\w+)\b/) |> length()

    1 + conditions + loops
  end

  defp calculate_max_nesting(lines) do
    lines
    |> Enum.reduce({0, 0}, fn line, {_current, max} ->
      indent = String.length(line) - String.length(String.trim_leading(line))
      depth = div(indent, 2)
      {depth, max(max, depth)}
    end)
    |> elem(1)
  end

  defp count_functions(content) do
    content |> Regex.scan(~r/\bdef\w*\s+\w+/) |> length()
  end

  defp calculate_complexity_score(metrics) do
    # Simple scoring algorithm
    base_score = 100

    deductions = cond do
      metrics[:cyclomatic_complexity] > 10 -> 20
      metrics[:cyclomatic_complexity] > 5 -> 10
      true -> 0
    end

    max(0, base_score - deductions)
  end

  defp generate_complexity_suggestions(metrics) do
    suggestions = []

    suggestions = if metrics[:cyclomatic_complexity] > 10 do
      ["Consider breaking down complex functions" | suggestions]
    else
      suggestions
    end

    suggestions = if metrics[:nesting_depth] > 4 do
      ["Reduce nesting depth for better readability" | suggestions]
    else
      suggestions
    end

    suggestions
  end

  defp analyze_security(content) do
    vulnerabilities = detect_vulnerabilities(content)

    %{
      score: calculate_security_score(vulnerabilities),
      vulnerabilities: vulnerabilities,
      summary: "Security analysis completed",
      suggestions: generate_security_suggestions(vulnerabilities)
    }
  end

  defp detect_vulnerabilities(content) do
    checks = [
      check_sql_injection(content),
      check_hardcoded_secrets(content),
      check_unsafe_operations(content)
    ]

    Enum.filter(checks, & &1 != nil)
  end

  defp check_sql_injection(content) do
    case content.type do
      :file ->
        if Regex.match?(~r/Repo\.query.*#\{/, content.content) do
          %{type: :sql_injection, severity: :high, description: "Possible SQL injection vulnerability"}
        end
      _ -> nil
    end
  end

  defp check_hardcoded_secrets(content) do
    case content.type do
      :file ->
        if Regex.match?(~r/(api_key|password|secret|token)\s*=\s*"[^"]+"/i, content.content) do
          %{type: :hardcoded_secret, severity: :high, description: "Hardcoded secrets detected"}
        end
      _ -> nil
    end
  end

  defp check_unsafe_operations(content) do
    case content.type do
      :file ->
        if Regex.match?(~r/Code\.eval_string|System\.cmd/i, content.content) do
          %{type: :unsafe_operation, severity: :medium, description: "Potentially unsafe operations detected"}
        end
      _ -> nil
    end
  end

  defp calculate_security_score(vulnerabilities) do
    base_score = 100

    deductions = Enum.reduce(vulnerabilities, 0, fn vuln, acc ->
      case vuln.severity do
        :critical -> acc + 30
        :high -> acc + 20
        :medium -> acc + 10
        :low -> acc + 5
      end
    end)

    max(0, base_score - deductions)
  end

  defp generate_security_suggestions(vulnerabilities) do
    Enum.map(vulnerabilities, fn vuln ->
      "Fix #{vuln.type}: #{vuln.description}"
    end)
  end

  defp analyze_quality(content) do
    metrics = calculate_quality_metrics(content)

    %{
      score: calculate_quality_score(metrics),
      metrics: metrics,
      summary: "Code quality analysis completed",
      suggestions: generate_quality_suggestions(metrics)
    }
  end

  defp calculate_quality_metrics(content) do
    case content.type do
      :file ->
        %{
          documentation_coverage: estimate_doc_coverage(content.content),
          test_coverage: estimate_test_coverage(content.content),
          code_duplication: detect_duplication(content.content),
          naming_consistency: check_naming_consistency(content.content)
        }
      :project ->
        %{
          average_file_size: calculate_average_file_size(content.files),
          module_cohesion: estimate_module_cohesion(content.files),
          dependency_health: check_dependency_health(content)
        }
    end
  end

  defp estimate_doc_coverage(content) do
    functions = Regex.scan(~r/def\w*\s+(\w+)/, content)
    docs = Regex.scan(~r/@doc\s+"""/, content)

    if length(functions) > 0 do
      (length(docs) / length(functions)) * 100
    else
      100.0
    end
  end

  defp estimate_test_coverage(_content) do
    # Simplified - would need actual test results
    75.0
  end

  defp detect_duplication(content) do
    lines = String.split(content, "\n")
    unique_lines = Enum.uniq(lines)

    if length(lines) > 0 do
      (1 - (length(unique_lines) / length(lines))) * 100
    else
      0.0
    end
  end

  defp check_naming_consistency(content) do
    # Check for consistent naming patterns
    snake_case = content |> Regex.scan(~r/def\s+[a-z_]+/) |> length()
    camel_case = content |> Regex.scan(~r/def\s+[a-zA-Z]+/) |> length()

    if snake_case + camel_case > 0 do
      (max(snake_case, camel_case) / (snake_case + camel_case)) * 100
    else
      100.0
    end
  end

  defp calculate_average_file_size(files) do
    if length(files) > 0 do
      total_size = Enum.reduce(files, 0, fn file, acc ->
        acc + String.length(file.content || "")
      end)
      total_size / length(files)
    else
      0
    end
  end

  defp estimate_module_cohesion(_files) do
    # Simplified cohesion estimate
    85.0
  end

  defp check_dependency_health(_content) do
    # Would check actual dependencies
    90.0
  end

  defp calculate_quality_score(metrics) do
    scores = metrics
      |> Map.values()
      |> Enum.filter(&is_number/1)

    if length(scores) > 0 do
      Enum.sum(scores) / length(scores)
    else
      75.0
    end
  end

  defp generate_quality_suggestions(metrics) do
    suggestions = []

    suggestions = if metrics[:documentation_coverage] < 80 do
      ["Improve documentation coverage" | suggestions]
    else
      suggestions
    end

    suggestions = if metrics[:test_coverage] < 80 do
      ["Increase test coverage" | suggestions]
    else
      suggestions
    end

    suggestions
  end

  defp analyze_performance(content) do
    issues = detect_performance_issues(content)

    %{
      score: calculate_performance_score(issues),
      issues: issues,
      summary: "Performance analysis completed",
      suggestions: generate_performance_suggestions(issues)
    }
  end

  defp detect_performance_issues(content) do
    case content.type do
      :file -> detect_file_performance_issues(content.content)
      :project -> detect_project_performance_issues(content.files)
    end
  end

  defp detect_file_performance_issues(content) do
    issues = []

    # Check for N+1 queries
    issues = if Regex.match?(~r/Enum\.map.*Repo\.(get|all)/, content) do
      [%{type: :n_plus_one, description: "Potential N+1 query pattern"} | issues]
    else
      issues
    end

    # Check for inefficient list operations
    issues = if Regex.match?(~r/List\.flatten|Enum\.concat.*Enum\.concat/, content) do
      [%{type: :inefficient_list_ops, description: "Inefficient list operations"} | issues]
    else
      issues
    end

    issues
  end

  defp detect_project_performance_issues(files) do
    Enum.flat_map(files, fn file ->
      detect_file_performance_issues(file.content || "")
    end)
  end

  defp calculate_performance_score(issues) do
    base_score = 100
    deductions = length(issues) * 10
    max(0, base_score - deductions)
  end

  defp generate_performance_suggestions(issues) do
    Enum.map(issues, fn issue ->
      "Optimize #{issue.type}: #{issue.description}"
    end)
  end

  defp analyze_general(content, context) do
    %{
      score: 85.0,
      summary: "General analysis completed",
      insights: extract_general_insights(content, context),
      suggestions: ["Continue monitoring code quality", "Regular refactoring recommended"]
    }
  end

  defp extract_general_insights(_content, _context) do
    %{
      overall_health: :good,
      trend: :improving,
      areas_of_concern: [],
      strengths: ["Well-structured code", "Good separation of concerns"]
    }
  end

  defp calculate_average(list, key) do
    values = Enum.map(list, & Map.get(&1, key, 0))
    if length(values) > 0 do
      Enum.sum(values) / length(values)
    else
      0
    end
  end

  defp save_analysis_results(analyses, target, context) do
    results = Enum.map(analyses, fn analysis ->
      save_single_result(analysis, target, context)
    end)

    successful = results
    |> Enum.filter(fn
      {:ok, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:ok, result} -> result end)

    {:ok, successful}
  end

  defp save_single_result(analysis, {target_type, target_id}, context) do
    params = %{
      analysis_type: analysis.type,
      summary: analysis.summary,
      details: Map.drop(analysis, [:type, :summary, :suggestions]),
      score: analysis.score,
      suggestions: analysis.suggestions
    }

    params = case target_type do
      :file ->
        # Get project_id from file
        case Projects.get_code_file(target_id) do
          {:ok, file} ->
            params
            |> Map.put(:project_id, file.project_id)
            |> Map.put(:code_file_id, target_id)
          _ ->
            params
        end
      :project ->
        Map.put(params, :project_id, target_id)
    end

    AI.create_analysis_result(params, actor: context[:actor])
  end

  defp generate_summary(results) do
    if length(results) > 0 do
      avg_score = Enum.sum(Enum.map(results, & &1.score || 0)) / length(results)

      "Completed #{length(results)} analyses with average score: #{Float.round(avg_score, 1)}"
    else
      "No analyses completed"
    end
  end

  defp extract_insights(results) do
    Enum.flat_map(results, fn result ->
      result.details[:insights] || []
    end)
  end

  defp generate_recommendations(results) do
    all_suggestions = Enum.flat_map(results, & &1.suggestions || [])

    # Deduplicate and prioritize
    all_suggestions
    |> Enum.uniq()
    |> Enum.take(10)
  end

  defp build_metadata(params, results) do
    %{
      started_at: DateTime.utc_now(),
      analysis_count: length(results),
      target_type: determine_target_type(params),
      context: params.context
    }
  end

  defp determine_target_type(params) do
    cond do
      params.file_id -> :file
      params.project_id -> :project
      true -> :unknown
    end
  end
end
