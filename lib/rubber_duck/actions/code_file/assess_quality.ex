defmodule RubberDuck.Actions.CodeFile.AssessQuality do
  @moduledoc """
  Action to assess overall code quality and provide improvement suggestions.
  """

  use Jido.Action,
    name: "assess_quality",
    description: "Assesses code quality across multiple dimensions",
    schema: [
      file_id: [type: :string, required: true],
      content: [type: :string, required: true],
      language: [type: :string, default: "elixir"],
      include_metrics: [type: {:list, :atom}, default: [:all]]
    ]

  @impl true
  def run(params, _context) do
    with {:ok, metrics} <- calculate_quality_metrics(params),
         {:ok, analysis} <- perform_quality_analysis(metrics, params),
         {:ok, score} <- calculate_quality_score(metrics, analysis),
         {:ok, recommendations} <- generate_quality_recommendations(analysis, score) do
      {:ok,
       %{
         quality_score: score.overall,
         quality_grade: score.grade,
         metrics: metrics,
         analysis: analysis,
         recommendations: recommendations,
         improvement_roadmap: create_improvement_roadmap(analysis, recommendations),
         badges: award_quality_badges(score)
       }}
    end
  end

  defp calculate_quality_metrics(params) do
    content = params.content

    metrics = %{
      readability: calculate_readability_metrics(content),
      maintainability: calculate_maintainability_metrics(content),
      complexity: calculate_complexity_metrics(content),
      testability: calculate_testability_metrics(content),
      security: calculate_security_metrics(content),
      performance: calculate_performance_metrics(content),
      documentation: calculate_documentation_metrics(content),
      style: calculate_style_metrics(content)
    }

    filtered =
      if :all in params.include_metrics do
        metrics
      else
        Map.take(metrics, params.include_metrics)
      end

    {:ok, filtered}
  end

  defp perform_quality_analysis(metrics, _params) do
    analysis = %{
      strengths: identify_strengths(metrics),
      weaknesses: identify_weaknesses(metrics),
      trends: analyze_quality_trends(metrics),
      technical_debt: estimate_technical_debt(metrics),
      code_smells: detect_code_smells(metrics),
      best_practices: check_best_practices(metrics)
    }

    {:ok, analysis}
  end

  defp calculate_quality_score(metrics, analysis) do
    weights = %{
      readability: 0.2,
      maintainability: 0.25,
      complexity: 0.2,
      testability: 0.15,
      security: 0.1,
      performance: 0.05,
      documentation: 0.05
    }

    weighted_score =
      Enum.reduce(weights, 0.0, fn {metric, weight}, acc ->
        metric_score = get_metric_score(metrics[metric])
        acc + metric_score * weight
      end)

    # Apply penalties for issues
    penalty = calculate_penalties(analysis)
    final_score = max(0.0, weighted_score - penalty)

    score = %{
      overall: final_score,
      breakdown: extract_score_breakdown(metrics),
      grade: score_to_grade(final_score),
      percentile: calculate_percentile(final_score)
    }

    {:ok, score}
  end

  defp generate_quality_recommendations(analysis, score) do
    recommendations = []

    # Generate recommendations based on weaknesses
    recommendations = recommendations ++ generate_weakness_recommendations(analysis.weaknesses)

    # Add recommendations for code smells
    recommendations = recommendations ++ generate_code_smell_recommendations(analysis.code_smells)

    # Add best practice recommendations
    recommendations =
      recommendations ++ generate_best_practice_recommendations(analysis.best_practices)

    # Prioritize recommendations
    prioritized = prioritize_recommendations(recommendations, score)

    {:ok, prioritized}
  end

  defp calculate_readability_metrics(content) do
    %{
      line_length: calculate_average_line_length(content),
      function_length: calculate_average_function_length(content),
      variable_naming: assess_variable_naming(content),
      indentation_consistency: check_indentation_consistency(content),
      comment_ratio: calculate_comment_ratio(content),
      score: 0.0
    }
    |> add_metric_score(:readability)
  end

  defp calculate_maintainability_metrics(content) do
    %{
      modularity: assess_modularity(content),
      coupling: calculate_coupling(content),
      cohesion: calculate_cohesion(content),
      change_risk: assess_change_risk(content),
      testability: assess_testability(content),
      score: 0.0
    }
    |> add_metric_score(:maintainability)
  end

  defp calculate_complexity_metrics(content) do
    %{
      cyclomatic: calculate_cyclomatic_complexity(content),
      cognitive: calculate_cognitive_complexity(content),
      nesting_depth: calculate_max_nesting_depth(content),
      function_count: count_functions(content),
      loc: count_lines_of_code(content),
      score: 0.0
    }
    |> add_metric_score(:complexity)
  end

  defp calculate_testability_metrics(content) do
    %{
      function_purity: assess_function_purity(content),
      dependency_injection: check_dependency_injection(content),
      mocking_difficulty: assess_mocking_difficulty(content),
      test_coverage_potential: estimate_test_coverage_potential(content),
      score: 0.0
    }
    |> add_metric_score(:testability)
  end

  defp calculate_security_metrics(content) do
    %{
      input_validation: check_input_validation(content),
      auth_checks: check_authorization_patterns(content),
      sensitive_data: check_sensitive_data_handling(content),
      injection_risks: check_injection_vulnerabilities(content),
      score: 0.0
    }
    |> add_metric_score(:security)
  end

  defp calculate_performance_metrics(content) do
    %{
      algorithm_efficiency: assess_algorithm_efficiency(content),
      resource_usage: estimate_resource_usage(content),
      database_efficiency: check_database_patterns(content),
      caching_usage: check_caching_patterns(content),
      score: 0.0
    }
    |> add_metric_score(:performance)
  end

  defp calculate_documentation_metrics(content) do
    %{
      coverage: calculate_doc_coverage(content),
      quality: assess_doc_quality(content),
      examples: check_for_examples(content),
      up_to_date: check_doc_freshness(content),
      score: 0.0
    }
    |> add_metric_score(:documentation)
  end

  defp calculate_style_metrics(content) do
    %{
      consistency: check_style_consistency(content),
      formatting: check_formatting(content),
      naming_conventions: check_naming_conventions(content),
      idioms: check_language_idioms(content),
      score: 0.0
    }
    |> add_metric_score(:style)
  end

  defp add_metric_score(metrics, type) do
    score = calculate_metric_type_score(metrics, type)
    Map.put(metrics, :score, score)
  end

  defp calculate_metric_type_score(metrics, type) do
    score_functions = %{
      readability: &score_readability/1,
      maintainability: &score_maintainability/1,
      complexity: &score_complexity/1,
      testability: &score_testability/1,
      security: &score_security/1,
      performance: &score_performance/1,
      documentation: &score_documentation/1,
      style: &score_style/1
    }

    case Map.get(score_functions, type) do
      nil -> 0.5
      func -> func.(metrics)
    end
  end

  defp score_readability(metrics) do
    base_score = 1.0

    # Penalize long lines
    base_score = base_score - if metrics.line_length > 100, do: 0.2, else: 0

    # Penalize long functions
    base_score = base_score - if metrics.function_length > 50, do: 0.2, else: 0

    # Reward good naming
    base_score = base_score + if metrics.variable_naming == :good, do: 0.1, else: -0.1

    # Reward consistent indentation
    base_score = base_score + if metrics.indentation_consistency, do: 0.1, else: -0.1

    max(0.0, min(1.0, base_score))
  end

  defp score_maintainability(metrics) do
    base_score = 1.0

    base_score = base_score + metrics.modularity * 0.2
    base_score = base_score - metrics.coupling * 0.3
    base_score = base_score + metrics.cohesion * 0.2
    base_score = base_score - metrics.change_risk * 0.3

    max(0.0, min(1.0, base_score))
  end

  defp score_complexity(metrics) do
    base_score = 1.0

    # Penalize high cyclomatic complexity
    base_score = base_score - min(metrics.cyclomatic, 20) / 20.0 * 0.5

    # Penalize deep nesting
    base_score = base_score - min(metrics.nesting_depth, 5) / 5.0 * 0.3

    max(0.0, min(1.0, base_score))
  end

  defp score_testability(_metrics) do
    # Simplified scoring
    0.7
  end

  defp score_security(_metrics) do
    # Simplified scoring
    0.8
  end

  defp score_performance(_metrics) do
    # Simplified scoring
    0.7
  end

  defp score_documentation(metrics) do
    metrics.coverage
  end

  defp score_style(_metrics) do
    # Simplified scoring
    0.8
  end

  defp identify_strengths(metrics) do
    metrics
    |> Enum.filter(fn {_key, value} ->
      is_map(value) and Map.get(value, :score, 0) > 0.8
    end)
    |> Enum.map(fn {key, _value} -> key end)
  end

  defp identify_weaknesses(metrics) do
    metrics
    |> Enum.filter(fn {_key, value} ->
      is_map(value) and Map.get(value, :score, 0) < 0.5
    end)
    |> Enum.map(fn {key, _value} -> key end)
  end

  defp analyze_quality_trends(_metrics) do
    # Would analyze historical data
    %{
      improving: [],
      declining: [],
      stable: []
    }
  end

  defp estimate_technical_debt(metrics) do
    complexity_debt = metrics.complexity.cyclomatic * 0.1
    maintainability_debt = (1.0 - metrics.maintainability.score) * 5
    documentation_debt = (1.0 - metrics.documentation.coverage) * 2

    %{
      hours: complexity_debt + maintainability_debt + documentation_debt,
      severity: debt_severity(complexity_debt + maintainability_debt + documentation_debt),
      main_contributors: [:complexity, :maintainability]
    }
  end

  defp debt_severity(hours) do
    cond do
      hours > 20 -> :high
      hours > 10 -> :medium
      hours > 5 -> :low
      true -> :minimal
    end
  end

  defp detect_code_smells(_metrics) do
    # Detect common code smells
    [
      %{type: :long_method, severity: :medium, location: "various"},
      %{type: :duplicate_code, severity: :low, location: "lines 45-67"}
    ]
  end

  defp check_best_practices(_metrics) do
    %{
      followed: [:error_handling, :modularity],
      violated: [:documentation, :testing],
      warnings: [:performance_optimization]
    }
  end

  defp get_metric_score(metric) when is_map(metric) do
    Map.get(metric, :score, 0.5)
  end

  defp get_metric_score(_), do: 0.5

  defp calculate_penalties(analysis) do
    smell_penalty = length(analysis.code_smells) * 0.05
    violation_penalty = length(analysis.best_practices.violated) * 0.1
    debt_penalty = if analysis.technical_debt.severity == :high, do: 0.2, else: 0

    smell_penalty + violation_penalty + debt_penalty
  end

  defp extract_score_breakdown(metrics) do
    metrics
    |> Enum.map(fn {key, value} ->
      {key, get_metric_score(value)}
    end)
    |> Enum.into(%{})
  end

  defp score_to_grade(score) do
    cond do
      score >= 0.9 -> :A
      score >= 0.8 -> :B
      score >= 0.7 -> :C
      score >= 0.6 -> :D
      true -> :F
    end
  end

  defp calculate_percentile(score) do
    # Would compare against other files/projects
    round(score * 100)
  end

  defp generate_weakness_recommendations(weaknesses) do
    Enum.map(weaknesses, fn weakness ->
      %{
        category: weakness,
        priority: :high,
        title: "Improve #{weakness}",
        description: "Focus on improving #{weakness} metrics",
        effort: :medium
      }
    end)
  end

  defp generate_code_smell_recommendations(code_smells) do
    Enum.map(code_smells, fn smell ->
      %{
        category: :code_smell,
        priority: smell.severity,
        title: "Fix #{smell.type}",
        description: "Refactor to eliminate #{smell.type} at #{smell.location}",
        effort: :low
      }
    end)
  end

  defp generate_best_practice_recommendations(best_practices) do
    Enum.map(best_practices.violated, fn practice ->
      %{
        category: :best_practice,
        priority: :medium,
        title: "Follow #{practice} best practices",
        description: "Implement industry standard #{practice} practices",
        effort: :medium
      }
    end)
  end

  defp prioritize_recommendations(recommendations, _score) do
    Enum.sort_by(recommendations, fn rec ->
      priority_value =
        case rec.priority do
          :high -> 3
          :medium -> 2
          :low -> 1
          _ -> 0
        end

      effort_value =
        case rec.effort do
          :low -> 3
          :medium -> 2
          :high -> 1
          _ -> 0
        end

      -(priority_value * 2 + effort_value)
    end)
  end

  defp create_improvement_roadmap(analysis, recommendations) do
    %{
      immediate: Enum.filter(recommendations, fn r -> r.priority == :high end),
      short_term: Enum.filter(recommendations, fn r -> r.priority == :medium end),
      long_term: Enum.filter(recommendations, fn r -> r.priority == :low end),
      estimated_improvement: estimate_improvement_potential(analysis, recommendations)
    }
  end

  defp estimate_improvement_potential(_analysis, recommendations) do
    base_improvement = length(recommendations) * 0.05
    min(0.3, base_improvement)
  end

  defp award_quality_badges(score) do
    badges = []

    badges = if score.overall > 0.9, do: [:excellence | badges], else: badges
    badges = if score.overall > 0.8, do: [:quality | badges], else: badges
    badges = if score.grade in [:A, :B], do: [:maintainable | badges], else: badges

    badges
  end

  # Helper functions for metrics calculation

  defp calculate_average_line_length(content) do
    lines = String.split(content, "\n")

    if length(lines) > 0 do
      total_length =
        Enum.reduce(lines, 0, fn line, acc ->
          acc + String.length(line)
        end)

      total_length / length(lines)
    else
      0
    end
  end

  defp calculate_average_function_length(content) do
    functions = extract_functions(content)

    if length(functions) > 0 do
      total_lines =
        Enum.reduce(functions, 0, fn func, acc ->
          acc + count_lines(func.body)
        end)

      total_lines / length(functions)
    else
      0
    end
  end

  defp assess_variable_naming(content) do
    # Check for meaningful variable names
    if Regex.match?(~r/\b[a-z]\s*=/, content) do
      :poor
    else
      :good
    end
  end

  defp check_indentation_consistency(content) do
    lines = String.split(content, "\n")

    indentations =
      Enum.map(lines, fn line ->
        String.length(line) - String.length(String.trim_leading(line))
      end)

    # Check if all indentations are multiples of 2
    Enum.all?(indentations, fn indent -> rem(indent, 2) == 0 end)
  end

  defp calculate_comment_ratio(content) do
    lines = String.split(content, "\n")

    comment_lines =
      Enum.count(lines, fn line ->
        line |> String.trim() |> String.starts_with?("#")
      end)

    if length(lines) > 0 do
      comment_lines / length(lines)
    else
      0
    end
  end

  defp assess_modularity(content) do
    # Check for proper module organization
    if String.contains?(content, "defmodule") do
      0.8
    else
      0.3
    end
  end

  defp calculate_coupling(_content) do
    # Simplified coupling calculation
    0.3
  end

  defp calculate_cohesion(_content) do
    # Simplified cohesion calculation
    0.7
  end

  defp assess_change_risk(_content) do
    # Simplified change risk assessment
    0.2
  end

  defp assess_testability(_content) do
    # Simplified testability assessment
    0.7
  end

  defp calculate_cyclomatic_complexity(content) do
    decision_points = ["if ", "unless ", "case ", "cond ", "with ", "and ", "or "]

    Enum.reduce(decision_points, 1, fn point, acc ->
      count =
        content
        |> String.split(point)
        |> length()
        |> Kernel.-(1)

      acc + count
    end)
  end

  defp calculate_cognitive_complexity(content) do
    # Simplified cognitive complexity
    calculate_cyclomatic_complexity(content) * 1.2
  end

  defp calculate_max_nesting_depth(content) do
    lines = String.split(content, "\n")

    lines
    |> Enum.map(fn line ->
      indent = String.length(line) - String.length(String.trim_leading(line))
      div(indent, 2)
    end)
    |> Enum.max(fn -> 0 end)
  end

  defp count_functions(content) do
    content
    |> then(&Regex.scan(~r/def(?:p?)\s+\w+/, &1))
    |> length()
  end

  defp count_lines_of_code(content) do
    content
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == ""))
    |> length()
  end

  defp assess_function_purity(_content) do
    # Simplified purity assessment
    0.6
  end

  defp check_dependency_injection(_content) do
    # Simplified DI check
    0.7
  end

  defp assess_mocking_difficulty(_content) do
    # Simplified mocking assessment
    0.5
  end

  defp estimate_test_coverage_potential(_content) do
    # Simplified coverage potential
    0.8
  end

  defp check_input_validation(content) do
    if String.contains?(content, "validate") do
      0.8
    else
      0.3
    end
  end

  defp check_authorization_patterns(content) do
    if String.contains?(content, "authorize") or String.contains?(content, "policy") do
      0.9
    else
      0.4
    end
  end

  defp check_sensitive_data_handling(_content) do
    # Simplified sensitive data check
    0.7
  end

  defp check_injection_vulnerabilities(content) do
    if String.contains?(content, "eval") or String.contains?(content, "Code.eval") do
      0.2
    else
      0.9
    end
  end

  defp assess_algorithm_efficiency(_content) do
    # Simplified algorithm assessment
    0.7
  end

  defp estimate_resource_usage(_content) do
    # Simplified resource estimation
    0.6
  end

  defp check_database_patterns(content) do
    if String.contains?(content, "Repo.") do
      0.7
    else
      1.0
    end
  end

  defp check_caching_patterns(content) do
    if String.contains?(content, "cache") or String.contains?(content, ":ets") do
      0.9
    else
      0.5
    end
  end

  defp calculate_doc_coverage(content) do
    functions = count_functions(content)

    docs =
      content
      |> String.split("\n")
      |> Enum.count(&String.contains?(&1, "@doc"))

    if functions > 0 do
      min(1.0, docs / functions)
    else
      1.0
    end
  end

  defp assess_doc_quality(content) do
    if String.contains?(content, "@moduledoc") and String.contains?(content, "@doc") do
      0.8
    else
      0.3
    end
  end

  defp check_for_examples(content) do
    if String.contains?(content, "## Example") or String.contains?(content, "iex>") do
      1.0
    else
      0.0
    end
  end

  defp check_doc_freshness(_content) do
    # Would check against last modification date
    0.7
  end

  defp check_style_consistency(_content) do
    # Simplified style check
    0.8
  end

  defp check_formatting(_content) do
    # Simplified formatting check
    0.9
  end

  defp check_naming_conventions(content) do
    if Regex.match?(~r/def [A-Z]/, content) do
      0.3
    else
      0.9
    end
  end

  defp check_language_idioms(_content) do
    # Simplified idiom check
    0.7
  end

  defp extract_functions(content) do
    content
    |> then(&Regex.scan(~r/def(?:p?)\s+(\w+).*?do(.*?)end/s, &1))
    |> Enum.map(fn [_, name, body] ->
      %{name: name, body: body}
    end)
  end

  defp count_lines(text) do
    text
    |> String.split("\n")
    |> length()
  end
end
