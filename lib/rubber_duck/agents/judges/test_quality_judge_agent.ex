defmodule RubberDuck.Agents.Judges.TestQualityJudgeAgent do
  @moduledoc """
  Specialized judge agent for evaluating test quality and coverage.

  Focuses on test coverage, test design quality, test maintainability,
  mocking practices, and overall testing strategy assessment.
  """

  use Jido.Agent, name: "TestQualityJudge"

  require Logger

  @judgment_criteria [
    :test_coverage,
    :test_design_quality,
    :test_maintainability,
    :assertion_quality,
    :mock_usage,
    :test_organization,
    :edge_case_coverage,
    :integration_testing
  ]

  @test_patterns [
    :unit_tests,
    :integration_tests,
    :property_based_tests,
    :contract_tests,
    :performance_tests
  ]

  @impl true
  def init(opts \\ []) do
    state = %{
      specialization: :test_quality,
      criteria_weights: get_default_weights(),
      evaluation_history: [],
      test_frameworks: identify_test_frameworks(),
      testing_best_practices: load_testing_best_practices(),
      performance_metrics: %{
        evaluations_completed: 0,
        avg_evaluation_time: 0.0,
        confidence_trend: [],
        tests_analyzed: 0
      },
      configuration: Keyword.get(opts, :config, %{})
    }

    {:ok, state}
  end

  @doc """
  Evaluate test quality for given code and tests.

  ## Parameters
  - `agent` - The judge agent instance
  - `code` - Production code to evaluate
  - `tests` - Test code to evaluate
  - `context` - Additional context including test results
  - `options` - Evaluation options

  ## Returns
  - `{:ok, evaluation_result, updated_agent}` - Evaluation successful
  - `{:error, reason, agent}` - Evaluation failed
  """
  def evaluate_test_quality(agent, code, tests, context \\ %{}, options \\ []) do
    start_time = System.monotonic_time(:millisecond)

    Logger.info("Starting test quality evaluation")

    case perform_test_analysis(code, tests, context, options, agent.state) do
      {:ok, analysis} ->
        evaluation_result = build_evaluation_result(analysis, agent.state.criteria_weights)
        end_time = System.monotonic_time(:millisecond)
        evaluation_time = end_time - start_time

        updated_agent = update_performance_metrics(agent, evaluation_result, evaluation_time)

        Logger.info("Test quality evaluation completed (#{evaluation_time}ms)")
        {:ok, evaluation_result, updated_agent}

      {:error, reason} ->
        Logger.error("Test quality evaluation failed: #{reason}")
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
      test_patterns: @test_patterns,
      strengths: [
        "Test coverage analysis",
        "Test design quality assessment",
        "Testing best practices evaluation",
        "Mock and stub usage review",
        "Test maintainability analysis"
      ],
      limitations: [
        "No runtime test execution",
        "Limited performance testing analysis",
        "No UI/E2E testing evaluation"
      ]
    }
  end

  @doc """
  Configure test evaluation criteria weights.
  """
  def configure_weights(agent, new_weights) do
    merged_weights = Map.merge(agent.state.criteria_weights, new_weights)
    updated_state = %{agent.state | criteria_weights: merged_weights}

    {:ok, %{agent | state: updated_state}}
  end

  ## Private Helper Functions

  defp perform_test_analysis(code, tests, context, options, agent_state) do
    analysis_results = %{
      test_coverage: analyze_test_coverage(code, tests, context),
      test_design_quality: analyze_test_design(tests, context),
      test_maintainability: analyze_test_maintainability(tests),
      assertion_quality: analyze_assertion_quality(tests),
      mock_usage: analyze_mock_usage(tests, context),
      test_organization: analyze_test_organization(tests, context),
      edge_case_coverage: analyze_edge_case_coverage(code, tests, context),
      integration_testing: analyze_integration_testing(tests, context)
    }

    test_issues = collect_test_issues(analysis_results)
    coverage_summary = summarize_coverage(analysis_results, context)
    recommendations = generate_test_recommendations(analysis_results, coverage_summary)

    {:ok,
     %{
       criteria_scores: analysis_results,
       identified_issues: test_issues,
       coverage_summary: coverage_summary,
       recommendations: recommendations,
       analysis_metadata: %{
         production_lines: count_lines(code),
         test_lines: count_lines(tests),
         test_files_analyzed: count_test_files(tests),
         test_functions: count_test_functions(tests),
         test_coverage_metrics: calculate_coverage_metrics(code, tests, context)
       }
     }}
  end

  defp analyze_test_coverage(code, tests, context) do
    issues = []

    # Analyze line coverage
    line_coverage = calculate_line_coverage(code, tests, context)

    issues =
      if line_coverage < 0.8 do
        ["Low line coverage: #{Float.round(line_coverage * 100, 1)}%" | issues]
      else
        issues
      end

    # Analyze branch coverage
    branch_coverage = calculate_branch_coverage(code, tests, context)

    issues =
      if branch_coverage < 0.7 do
        ["Low branch coverage: #{Float.round(branch_coverage * 100, 1)}%" | issues]
      else
        issues
      end

    # Check for untested functions
    untested_functions = find_untested_functions(code, tests)

    issues =
      if length(untested_functions) > 0 do
        ["#{length(untested_functions)} functions lack tests" | issues]
      else
        issues
      end

    score = calculate_coverage_score(line_coverage, branch_coverage, untested_functions)

    %{
      score: score,
      issues: issues,
      confidence: 0.9,
      metrics: %{
        line_coverage: line_coverage,
        branch_coverage: branch_coverage,
        untested_functions: length(untested_functions)
      }
    }
  end

  defp analyze_test_design(tests, context) do
    issues = []

    # Check for test naming conventions
    naming_issues = check_test_naming(tests)
    issues = issues ++ naming_issues

    # Check for test structure (Arrange-Act-Assert)
    structure_issues = check_test_structure(tests)
    issues = issues ++ structure_issues

    # Check for test independence
    independence_issues = check_test_independence(tests, context)
    issues = issues ++ independence_issues

    # Check for test readability
    readability_issues = check_test_readability(tests)
    issues = issues ++ readability_issues

    score =
      calculate_design_score(
        naming_issues,
        structure_issues,
        independence_issues,
        readability_issues
      )

    %{
      score: score,
      issues: issues,
      confidence: 0.8
    }
  end

  defp analyze_test_maintainability(tests) do
    issues = []

    # Check for test code duplication
    duplication_issues = find_test_duplication(tests)
    issues = issues ++ duplication_issues

    # Check for complex test setup
    complex_setup = detect_complex_test_setup(tests)
    issues = issues ++ complex_setup

    # Check for brittle tests
    brittle_tests = detect_brittle_tests(tests)
    issues = issues ++ brittle_tests

    # Check test helper usage
    helper_issues = analyze_test_helper_usage(tests)
    issues = issues ++ helper_issues

    score =
      calculate_maintainability_score(
        duplication_issues,
        complex_setup,
        brittle_tests,
        helper_issues
      )

    %{
      score: score,
      issues: issues,
      confidence: 0.7
    }
  end

  defp analyze_assertion_quality(tests) do
    issues = []

    # Check for meaningful assertions
    weak_assertions = find_weak_assertions(tests)
    issues = issues ++ weak_assertions

    # Check for assertion count per test
    assertion_count_issues = analyze_assertion_counts(tests)
    issues = issues ++ assertion_count_issues

    # Check for assertion specificity
    specificity_issues = check_assertion_specificity(tests)
    issues = issues ++ specificity_issues

    score = calculate_assertion_score(weak_assertions, assertion_count_issues, specificity_issues)

    %{
      score: score,
      issues: issues,
      confidence: 0.8
    }
  end

  defp analyze_mock_usage(tests, context) do
    issues = []

    # Check for appropriate mock usage
    inappropriate_mocking = find_inappropriate_mocks(tests, context)
    issues = issues ++ inappropriate_mocking

    # Check for over-mocking
    over_mocking = detect_over_mocking(tests)
    issues = issues ++ over_mocking

    # Check for mock verification
    mock_verification_issues = check_mock_verification(tests)
    issues = issues ++ mock_verification_issues

    score = calculate_mock_score(inappropriate_mocking, over_mocking, mock_verification_issues)

    %{
      score: score,
      issues: issues,
      confidence: 0.7
    }
  end

  defp analyze_test_organization(tests, context) do
    issues = []

    # Check for logical test grouping
    grouping_issues = check_test_grouping(tests, context)
    issues = issues ++ grouping_issues

    # Check for test file organization
    file_organization_issues = check_test_file_organization(tests, context)
    issues = issues ++ file_organization_issues

    # Check for test categorization
    categorization_issues = check_test_categorization(tests)
    issues = issues ++ categorization_issues

    score =
      calculate_organization_score(
        grouping_issues,
        file_organization_issues,
        categorization_issues
      )

    %{
      score: score,
      issues: issues,
      confidence: 0.6
    }
  end

  defp analyze_edge_case_coverage(code, tests, context) do
    issues = []

    # Identify potential edge cases in code
    potential_edge_cases = identify_edge_cases(code)

    # Check if edge cases are tested
    untested_edge_cases = find_untested_edge_cases(potential_edge_cases, tests)

    issues =
      if length(untested_edge_cases) > 0 do
        ["#{length(untested_edge_cases)} edge cases lack tests" | issues]
      else
        issues
      end

    # Check for boundary value testing
    boundary_testing_issues = check_boundary_testing(code, tests)
    issues = issues ++ boundary_testing_issues

    # Check for error condition testing
    error_condition_issues = check_error_condition_testing(code, tests)
    issues = issues ++ error_condition_issues

    score =
      calculate_edge_case_score(
        untested_edge_cases,
        boundary_testing_issues,
        error_condition_issues
      )

    %{
      score: score,
      issues: issues,
      confidence: 0.7
    }
  end

  defp analyze_integration_testing(tests, context) do
    issues = []

    # Check for integration test presence
    integration_tests = find_integration_tests(tests, context)

    issues =
      if Enum.empty?(integration_tests) do
        ["No integration tests found" | issues]
      else
        issues
      end

    # Check for contract testing
    contract_testing_issues = check_contract_testing(tests, context)
    issues = issues ++ contract_testing_issues

    # Check for end-to-end scenario coverage
    e2e_coverage_issues = check_e2e_coverage(tests, context)
    issues = issues ++ e2e_coverage_issues

    score =
      calculate_integration_score(integration_tests, contract_testing_issues, e2e_coverage_issues)

    %{
      score: score,
      issues: issues,
      confidence: 0.6
    }
  end

  # Scoring helper functions

  defp calculate_coverage_score(line_coverage, branch_coverage, untested_functions) do
    base_score = (line_coverage + branch_coverage) / 2
    function_penalty = length(untested_functions) * 0.05
    max(0.0, base_score - function_penalty)
  end

  defp calculate_design_score(naming, structure, independence, readability) do
    base_score = 1.0
    deductions = 0.0

    deductions = deductions + length(naming) * 0.1
    deductions = deductions + length(structure) * 0.15
    deductions = deductions + length(independence) * 0.2
    deductions = deductions + length(readability) * 0.1

    max(0.0, base_score - deductions)
  end

  defp calculate_maintainability_score(duplication, complex_setup, brittle, helpers) do
    base_score = 1.0
    deductions = 0.0

    deductions = deductions + length(duplication) * 0.15
    deductions = deductions + length(complex_setup) * 0.2
    deductions = deductions + length(brittle) * 0.25
    deductions = deductions + length(helpers) * 0.1

    max(0.0, base_score - deductions)
  end

  defp calculate_assertion_score(weak, assertion_count, specificity) do
    base_score = 1.0
    deductions = 0.0

    deductions = deductions + length(weak) * 0.2
    deductions = deductions + length(assertion_count) * 0.1
    deductions = deductions + length(specificity) * 0.15

    max(0.0, base_score - deductions)
  end

  defp calculate_mock_score(inappropriate, over_mocking, verification) do
    base_score = 1.0
    deductions = 0.0

    deductions = deductions + length(inappropriate) * 0.2
    deductions = deductions + length(over_mocking) * 0.15
    deductions = deductions + length(verification) * 0.1

    max(0.0, base_score - deductions)
  end

  defp calculate_organization_score(grouping, file_org, categorization) do
    base_score = 1.0
    deductions = 0.0

    deductions = deductions + length(grouping) * 0.15
    deductions = deductions + length(file_org) * 0.1
    deductions = deductions + length(categorization) * 0.1

    max(0.0, base_score - deductions)
  end

  defp calculate_edge_case_score(untested_edge, boundary, error_conditions) do
    base_score = 1.0
    deductions = 0.0

    deductions = deductions + length(untested_edge) * 0.2
    deductions = deductions + length(boundary) * 0.15
    deductions = deductions + length(error_conditions) * 0.1

    max(0.0, base_score - deductions)
  end

  defp calculate_integration_score(integration_tests, contract, e2e) do
    base_score = if length(integration_tests) > 0, do: 0.8, else: 0.3
    deductions = 0.0

    deductions = deductions + length(contract) * 0.1
    deductions = deductions + length(e2e) * 0.1

    max(0.0, base_score - deductions)
  end

  # Analysis implementation stubs (simplified for demo)

  defp calculate_line_coverage(_code, _tests, _context), do: 0.75
  defp calculate_branch_coverage(_code, _tests, _context), do: 0.68
  defp find_untested_functions(_code, _tests), do: []
  defp check_test_naming(_tests), do: []
  defp check_test_structure(_tests), do: []
  defp check_test_independence(_tests, _context), do: []
  defp check_test_readability(_tests), do: []
  defp find_test_duplication(_tests), do: []
  defp detect_complex_test_setup(_tests), do: []
  defp detect_brittle_tests(_tests), do: []
  defp analyze_test_helper_usage(_tests), do: []
  defp find_weak_assertions(_tests), do: []
  defp analyze_assertion_counts(_tests), do: []
  defp check_assertion_specificity(_tests), do: []
  defp find_inappropriate_mocks(_tests, _context), do: []
  defp detect_over_mocking(_tests), do: []
  defp check_mock_verification(_tests), do: []
  defp check_test_grouping(_tests, _context), do: []
  defp check_test_file_organization(_tests, _context), do: []
  defp check_test_categorization(_tests), do: []
  defp identify_edge_cases(_code), do: []
  defp find_untested_edge_cases(_potential_edge_cases, _tests), do: []
  defp check_boundary_testing(_code, _tests), do: []
  defp check_error_condition_testing(_code, _tests), do: []
  defp find_integration_tests(_tests, _context), do: []
  defp check_contract_testing(_tests, _context), do: []
  defp check_e2e_coverage(_tests, _context), do: []

  defp count_lines(code), do: length(String.split(code, "\n"))
  defp count_test_files(_tests), do: 3
  defp count_test_functions(_tests), do: 12

  defp calculate_coverage_metrics(_code, _tests, _context) do
    %{
      line_coverage: 0.75,
      branch_coverage: 0.68,
      function_coverage: 0.85
    }
  end

  defp identify_test_frameworks do
    # Would identify based on dependencies
    ["ExUnit", "PropCheck", "Mox"]
  end

  defp load_testing_best_practices do
    [
      "Follow AAA pattern (Arrange-Act-Assert)",
      "One assertion per test when possible",
      "Descriptive test names",
      "Independent tests",
      "Fast test execution"
    ]
  end

  defp build_evaluation_result(analysis, weights) do
    weighted_score = calculate_weighted_score(analysis.criteria_scores, weights)
    overall_confidence = calculate_overall_confidence(analysis.criteria_scores)

    %{
      score: weighted_score,
      confidence: overall_confidence,
      specialization: :test_quality,
      issues: analysis.identified_issues,
      coverage_summary: analysis.coverage_summary,
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

  defp collect_test_issues(analysis_results) do
    Enum.flat_map(analysis_results, fn {criterion, result} ->
      issues = Map.get(result, :issues, [])

      Enum.map(issues, fn issue ->
        %{
          criterion: criterion,
          description: issue,
          severity: determine_test_severity(issue, criterion),
          category: :test_quality
        }
      end)
    end)
  end

  defp summarize_coverage(analysis_results, context) do
    coverage_result = Map.get(analysis_results, :test_coverage, %{})
    metrics = Map.get(coverage_result, :metrics, %{})

    %{
      line_coverage: Map.get(metrics, :line_coverage, 0.0),
      branch_coverage: Map.get(metrics, :branch_coverage, 0.0),
      untested_functions: Map.get(metrics, :untested_functions, 0),
      overall_grade: calculate_coverage_grade(metrics)
    }
  end

  defp calculate_coverage_grade(metrics) do
    line_coverage = Map.get(metrics, :line_coverage, 0.0)

    cond do
      line_coverage >= 0.9 -> :excellent
      line_coverage >= 0.8 -> :good
      line_coverage >= 0.7 -> :fair
      true -> :poor
    end
  end

  defp generate_test_recommendations(analysis_results, coverage_summary) do
    base_recommendations = [
      "Improve test coverage for untested functions",
      "Follow consistent test naming conventions",
      "Ensure test independence and repeatability",
      "Add edge case and error condition testing"
    ]

    # Add coverage-specific recommendations
    coverage_recs =
      case coverage_summary.overall_grade do
        :poor -> ["URGENT: Significantly increase test coverage"]
        :fair -> ["Increase test coverage to at least 80%"]
        _ -> []
      end

    base_recommendations ++ coverage_recs
  end

  defp determine_test_severity(issue, criterion) do
    cond do
      String.contains?(issue, ["No integration tests", "lack tests"]) -> :high
      String.contains?(issue, ["Low coverage", "untested"]) -> :medium
      String.contains?(issue, ["naming", "organization", "duplication"]) -> :low
      true -> :low
    end
  end

  defp get_default_weights do
    %{
      # Highest weight
      test_coverage: 1.5,
      test_design_quality: 1.2,
      test_maintainability: 1.1,
      assertion_quality: 1.0,
      mock_usage: 0.8,
      test_organization: 0.7,
      edge_case_coverage: 1.3,
      integration_testing: 1.0
    }
  end

  defp update_performance_metrics(agent, evaluation_result, evaluation_time) do
    metrics = agent.state.performance_metrics

    new_count = metrics.evaluations_completed + 1

    new_avg_time =
      (metrics.avg_evaluation_time * metrics.evaluations_completed + evaluation_time) / new_count

    new_confidence_trend = [evaluation_result.confidence | Enum.take(metrics.confidence_trend, 9)]
    new_tests_analyzed = metrics.tests_analyzed + evaluation_result.metadata.test_functions

    updated_metrics = %{
      evaluations_completed: new_count,
      avg_evaluation_time: new_avg_time,
      confidence_trend: new_confidence_trend,
      tests_analyzed: new_tests_analyzed
    }

    %{agent | state: %{agent.state | performance_metrics: updated_metrics}}
  end
end
