defmodule RubberDuck.Agents.Judges.CodeQualityJudgeAgent do
  @moduledoc """
  Specialized judge agent for evaluating code quality aspects.

  Focuses on readability, maintainability, code organization,
  naming conventions, and general programming best practices.
  """

  use Jido.Agent, name: "CodeQualityJudge"

  require Logger

  @judgment_criteria [
    :readability,
    :maintainability,
    :naming_conventions,
    :code_organization,
    :complexity,
    :documentation,
    :error_handling,
    :code_duplication
  ]

  @impl true
  def init(opts \\ []) do
    state = %{
      specialization: :code_quality,
      criteria_weights: get_default_weights(),
      evaluation_history: [],
      performance_metrics: %{
        evaluations_completed: 0,
        avg_evaluation_time: 0.0,
        confidence_trend: []
      },
      configuration: Keyword.get(opts, :config, %{})
    }

    {:ok, state}
  end

  @doc """
  Evaluate code quality for given code snippet.

  ## Parameters
  - `agent` - The judge agent instance
  - `code` - Code to evaluate
  - `context` - Additional context for evaluation
  - `options` - Evaluation options

  ## Returns
  - `{:ok, evaluation_result, updated_agent}` - Evaluation successful
  - `{:error, reason, agent}` - Evaluation failed
  """
  def evaluate_code(agent, code, context \\ %{}, options \\ []) do
    start_time = System.monotonic_time(:millisecond)

    Logger.info("Starting code quality evaluation")

    case perform_quality_analysis(code, context, options) do
      {:ok, analysis} ->
        evaluation_result = build_evaluation_result(analysis, agent.state.criteria_weights)
        end_time = System.monotonic_time(:millisecond)
        evaluation_time = end_time - start_time

        updated_agent = update_performance_metrics(agent, evaluation_result, evaluation_time)

        Logger.info("Code quality evaluation completed (#{evaluation_time}ms)")
        {:ok, evaluation_result, updated_agent}

      {:error, reason} ->
        Logger.error("Code quality evaluation failed: #{reason}")
        {:error, reason, agent}
    end
  end

  @doc """
  Get judge agent capabilities and specialization info.
  """
  def get_capabilities(agent) do
    %{
      specialization: agent.state.specialization,
      criteria: @judgment_criteria,
      strengths: [
        "Code readability assessment",
        "Maintainability analysis",
        "Best practices evaluation",
        "Code organization review"
      ],
      limitations: [
        "Limited security analysis",
        "No performance profiling",
        "Architecture evaluation is basic"
      ]
    }
  end

  @doc """
  Configure evaluation criteria weights.
  """
  def configure_weights(agent, new_weights) do
    merged_weights = Map.merge(agent.state.criteria_weights, new_weights)
    updated_state = %{agent.state | criteria_weights: merged_weights}

    {:ok, %{agent | state: updated_state}}
  end

  ## Private Helper Functions

  defp perform_quality_analysis(code, context, options) do
    analysis_results = %{
      readability: analyze_readability(code),
      maintainability: analyze_maintainability(code, context),
      naming_conventions: analyze_naming(code),
      code_organization: analyze_organization(code, context),
      complexity: analyze_complexity(code),
      documentation: analyze_documentation(code),
      error_handling: analyze_error_handling(code),
      code_duplication: analyze_duplication(code, context)
    }

    overall_issues = collect_issues(analysis_results)
    recommendations = generate_recommendations(analysis_results)

    {:ok,
     %{
       criteria_scores: analysis_results,
       identified_issues: overall_issues,
       recommendations: recommendations,
       analysis_metadata: %{
         lines_analyzed: count_lines(code),
         functions_analyzed: count_functions(code),
         complexity_metrics: calculate_complexity_metrics(code)
       }
     }}
  end

  defp analyze_readability(code) do
    issues = []

    # Check line length
    long_lines = find_long_lines(code)
    issues = if length(long_lines) > 0, do: ["Long lines detected" | issues], else: issues

    # Check nesting depth
    deep_nesting = find_deep_nesting(code)
    issues = if length(deep_nesting) > 0, do: ["Deep nesting found" | issues], else: issues

    # Check function length
    long_functions = find_long_functions(code)
    issues = if length(long_functions) > 0, do: ["Long functions detected" | issues], else: issues

    score = calculate_readability_score(long_lines, deep_nesting, long_functions)

    %{
      score: score,
      issues: issues,
      confidence: 0.8
    }
  end

  defp analyze_maintainability(code, context) do
    issues = []

    # Check for code smells
    code_smells = detect_code_smells(code)
    issues = issues ++ code_smells

    # Check coupling indicators
    coupling_issues = analyze_coupling(code, context)
    issues = issues ++ coupling_issues

    # Check for magic numbers
    magic_numbers = find_magic_numbers(code)
    issues = if length(magic_numbers) > 0, do: ["Magic numbers found" | issues], else: issues

    score = calculate_maintainability_score(issues)

    %{
      score: score,
      issues: issues,
      confidence: 0.7
    }
  end

  defp analyze_naming(code) do
    issues = []

    # Check variable naming
    naming_issues = find_naming_issues(code)
    issues = issues ++ naming_issues

    # Check consistency
    consistency_issues = check_naming_consistency(code)
    issues = issues ++ consistency_issues

    score = calculate_naming_score(issues)

    %{
      score: score,
      issues: issues,
      confidence: 0.9
    }
  end

  defp analyze_organization(code, context) do
    issues = []

    # Check function ordering
    issues =
      if has_poor_function_ordering?(code) do
        ["Functions not logically ordered" | issues]
      else
        issues
      end

    # Check module structure
    structure_issues = analyze_module_structure(code, context)
    issues = issues ++ structure_issues

    score = calculate_organization_score(issues)

    %{
      score: score,
      issues: issues,
      confidence: 0.6
    }
  end

  defp analyze_complexity(code) do
    cyclomatic = calculate_cyclomatic_complexity(code)
    cognitive = calculate_cognitive_complexity(code)

    issues = []
    issues = if cyclomatic > 10, do: ["High cyclomatic complexity" | issues], else: issues
    issues = if cognitive > 15, do: ["High cognitive complexity" | issues], else: issues

    score = calculate_complexity_score(cyclomatic, cognitive)

    %{
      score: score,
      issues: issues,
      confidence: 0.8,
      metrics: %{cyclomatic: cyclomatic, cognitive: cognitive}
    }
  end

  defp analyze_documentation(code) do
    issues = []

    # Check for module docs
    issues =
      if has_module_docs?(code) do
        issues
      else
        ["Missing module documentation" | issues]
      end

    # Check for function docs
    undocumented_functions = find_undocumented_functions(code)

    issues =
      if length(undocumented_functions) > 0 do
        ["Undocumented public functions" | issues]
      else
        issues
      end

    score = calculate_documentation_score(issues, code)

    %{
      score: score,
      issues: issues,
      confidence: 0.9
    }
  end

  defp analyze_error_handling(code) do
    issues = []

    # Check for proper error handling
    error_issues = find_error_handling_issues(code)
    issues = issues ++ error_issues

    # Check for raise vs errors
    exception_issues = analyze_exception_usage(code)
    issues = issues ++ exception_issues

    score = calculate_error_handling_score(issues)

    %{
      score: score,
      issues: issues,
      confidence: 0.7
    }
  end

  defp analyze_duplication(code, context) do
    duplicated_blocks = find_code_duplication(code)
    similar_patterns = find_similar_patterns(code, context)

    issues = []

    issues =
      if length(duplicated_blocks) > 0, do: ["Code duplication detected" | issues], else: issues

    issues =
      if length(similar_patterns) > 0, do: ["Similar patterns found" | issues], else: issues

    score = calculate_duplication_score(duplicated_blocks, similar_patterns)

    %{
      score: score,
      issues: issues,
      confidence: 0.6
    }
  end

  # Scoring helper functions

  defp calculate_readability_score(long_lines, deep_nesting, long_functions) do
    base_score = 1.0
    deductions = 0.0

    deductions = deductions + length(long_lines) * 0.1
    deductions = deductions + length(deep_nesting) * 0.15
    deductions = deductions + length(long_functions) * 0.2

    max(0.0, base_score - deductions)
  end

  defp calculate_maintainability_score(issues) do
    base_score = 1.0
    deduction = length(issues) * 0.1
    max(0.0, base_score - deduction)
  end

  defp calculate_naming_score(issues) do
    base_score = 1.0
    deduction = length(issues) * 0.15
    max(0.0, base_score - deduction)
  end

  defp calculate_organization_score(issues) do
    base_score = 1.0
    deduction = length(issues) * 0.2
    max(0.0, base_score - deduction)
  end

  defp calculate_complexity_score(cyclomatic, cognitive) do
    base_score = 1.0

    cyclomatic_penalty = if cyclomatic > 10, do: (cyclomatic - 10) * 0.05, else: 0.0
    cognitive_penalty = if cognitive > 15, do: (cognitive - 15) * 0.03, else: 0.0

    max(0.0, base_score - cyclomatic_penalty - cognitive_penalty)
  end

  defp calculate_documentation_score(issues, code) do
    base_score = 1.0
    deduction = length(issues) * 0.2

    # Bonus for good documentation
    if has_comprehensive_docs?(code) do
      min(1.0, base_score - deduction + 0.1)
    else
      max(0.0, base_score - deduction)
    end
  end

  defp calculate_error_handling_score(issues) do
    base_score = 1.0
    deduction = length(issues) * 0.25
    max(0.0, base_score - deduction)
  end

  defp calculate_duplication_score(duplicated_blocks, similar_patterns) do
    base_score = 1.0
    duplication_penalty = length(duplicated_blocks) * 0.2
    similarity_penalty = length(similar_patterns) * 0.1
    max(0.0, base_score - duplication_penalty - similarity_penalty)
  end

  # Analysis implementation stubs (simplified for demo)

  # Would implement actual line length checking
  defp find_long_lines(code), do: []
  # Would implement nesting depth analysis
  defp find_deep_nesting(code), do: []
  # Would implement function length checking
  defp find_long_functions(code), do: []
  # Would implement code smell detection
  defp detect_code_smells(code), do: []
  # Would analyze coupling
  defp analyze_coupling(code, _context), do: []
  # Would find hardcoded numbers
  defp find_magic_numbers(code), do: []
  # Would check naming conventions
  defp find_naming_issues(code), do: []
  # Would check consistency
  defp check_naming_consistency(code), do: []
  # Would check organization
  defp has_poor_function_ordering?(code), do: false
  # Would analyze structure
  defp analyze_module_structure(code, _context), do: []
  # Would calculate actual complexity
  defp calculate_cyclomatic_complexity(code), do: 5
  # Would calculate cognitive load
  defp calculate_cognitive_complexity(code), do: 8
  defp has_module_docs?(code), do: String.contains?(code, "@moduledoc")
  # Would find undocumented functions
  defp find_undocumented_functions(code), do: []
  # Would analyze error patterns
  defp find_error_handling_issues(code), do: []
  # Would check exception usage
  defp analyze_exception_usage(code), do: []
  # Would detect duplicated code
  defp find_code_duplication(code), do: []
  # Would find similar patterns
  defp find_similar_patterns(code, _context), do: []
  # Would check doc coverage
  defp has_comprehensive_docs?(code), do: false
  defp count_lines(code), do: length(String.split(code, "\n"))
  # Would count actual functions
  defp count_functions(code), do: 3
  defp calculate_complexity_metrics(code), do: %{average: 5.0, max: 8}

  defp build_evaluation_result(analysis, weights) do
    weighted_score = calculate_weighted_score(analysis.criteria_scores, weights)
    overall_confidence = calculate_overall_confidence(analysis.criteria_scores)

    %{
      score: weighted_score,
      confidence: overall_confidence,
      specialization: :code_quality,
      issues: analysis.identified_issues,
      recommendations: analysis.recommendations,
      detailed_analysis: analysis.criteria_scores,
      metadata: analysis.analysis_metadata,
      evaluation_timestamp: DateTime.utc_now()
    }
  end

  defp calculate_weighted_score(criteria_scores, weights) do
    total_weight = Enum.reduce(weights, 0.0, fn {_criterion, weight}, acc -> acc + weight end)

    if total_weight > 0 do
      Enum.reduce(criteria_scores, 0.0, fn {criterion, result}, acc ->
        weight = Map.get(weights, criterion, 0.1)
        normalized_weight = weight / total_weight
        acc + result.score * normalized_weight
      end)
    else
      0.5
    end
  end

  defp calculate_overall_confidence(criteria_scores) do
    confidences = Enum.map(criteria_scores, fn {_criterion, result} -> result.confidence end)
    if length(confidences) > 0, do: Enum.sum(confidences) / length(confidences), else: 0.5
  end

  defp collect_issues(analysis_results) do
    Enum.flat_map(analysis_results, fn {_criterion, result} ->
      Enum.map(result.issues, fn issue ->
        %{
          criterion: _criterion,
          description: issue,
          severity: determine_issue_severity(issue)
        }
      end)
    end)
  end

  defp generate_recommendations(analysis_results) do
    # Generate specific recommendations based on analysis
    base_recommendations = [
      "Review code for readability improvements",
      "Consider refactoring complex functions",
      "Add documentation for public functions"
    ]

    # Would add more sophisticated recommendation logic
    base_recommendations
  end

  defp determine_issue_severity(issue) do
    cond do
      String.contains?(issue, ["complexity", "duplication"]) -> :high
      String.contains?(issue, ["documentation", "naming"]) -> :medium
      true -> :low
    end
  end

  defp get_default_weights do
    %{
      readability: 1.0,
      maintainability: 1.0,
      naming_conventions: 0.8,
      code_organization: 0.7,
      complexity: 1.2,
      documentation: 0.6,
      error_handling: 1.1,
      code_duplication: 0.9
    }
  end

  defp update_performance_metrics(agent, evaluation_result, evaluation_time) do
    metrics = agent.state.performance_metrics

    new_count = metrics.evaluations_completed + 1

    new_avg_time =
      (metrics.avg_evaluation_time * metrics.evaluations_completed + evaluation_time) / new_count

    new_confidence_trend = [evaluation_result.confidence | Enum.take(metrics.confidence_trend, 9)]

    updated_metrics = %{
      evaluations_completed: new_count,
      avg_evaluation_time: new_avg_time,
      confidence_trend: new_confidence_trend
    }

    %{agent | state: %{agent.state | performance_metrics: updated_metrics}}
  end
end
