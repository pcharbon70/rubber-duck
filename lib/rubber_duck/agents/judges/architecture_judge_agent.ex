defmodule RubberDuck.Agents.Judges.ArchitectureJudgeAgent do
  @moduledoc """
  Specialized judge agent for evaluating architectural aspects of code.

  Focuses on design patterns, modularity, separation of concerns,
  dependency management, and overall system architecture quality.
  """

  use Jido.Agent, name: "ArchitectureJudge"

  require Logger

  @judgment_criteria [
    :modularity,
    :separation_of_concerns,
    :dependency_management,
    :design_patterns,
    :interface_design,
    :abstraction_levels,
    :coupling_cohesion,
    :scalability_indicators
  ]

  @impl true
  def init(opts \\ []) do
    state = %{
      specialization: :architecture,
      criteria_weights: get_default_weights(),
      evaluation_history: [],
      architectural_patterns: load_known_patterns(),
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
  Evaluate architectural aspects of code.

  ## Parameters
  - `agent` - The judge agent instance
  - `code` - Code to evaluate
  - `context` - Additional context including project structure
  - `options` - Evaluation options

  ## Returns
  - `{:ok, evaluation_result, updated_agent}` - Evaluation successful
  - `{:error, reason, agent}` - Evaluation failed
  """
  def evaluate_architecture(agent, code, context \\ %{}, options \\ []) do
    start_time = System.monotonic_time(:millisecond)

    Logger.info("Starting architectural evaluation")

    case perform_architectural_analysis(
           code,
           context,
           options,
           agent.state.architectural_patterns
         ) do
      {:ok, analysis} ->
        evaluation_result = build_evaluation_result(analysis, agent.state.criteria_weights)
        end_time = System.monotonic_time(:millisecond)
        evaluation_time = end_time - start_time

        updated_agent = update_performance_metrics(agent, evaluation_result, evaluation_time)

        Logger.info("Architectural evaluation completed (#{evaluation_time}ms)")
        {:ok, evaluation_result, updated_agent}

      {:error, reason} ->
        Logger.error("Architectural evaluation failed: #{reason}")
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
        "Design pattern recognition",
        "Modularity assessment",
        "Dependency analysis",
        "Interface design evaluation",
        "Architectural smell detection"
      ],
      limitations: [
        "No runtime behavior analysis",
        "Limited performance assessment",
        "No security-specific architectural review"
      ]
    }
  end

  @doc """
  Configure evaluation criteria weights for architectural focus.
  """
  def configure_weights(agent, new_weights) do
    merged_weights = Map.merge(agent.state.criteria_weights, new_weights)
    updated_state = %{agent.state | criteria_weights: merged_weights}

    {:ok, %{agent | state: updated_state}}
  end

  ## Private Helper Functions

  defp perform_architectural_analysis(code, context, options, known_patterns) do
    analysis_results = %{
      modularity: analyze_modularity(code, context),
      separation_of_concerns: analyze_separation_of_concerns(code, context),
      dependency_management: analyze_dependencies(code, context),
      design_patterns: analyze_design_patterns(code, known_patterns),
      interface_design: analyze_interface_design(code),
      abstraction_levels: analyze_abstraction(code, context),
      coupling_cohesion: analyze_coupling_cohesion(code, context),
      scalability_indicators: analyze_scalability_indicators(code, context)
    }

    architectural_issues = collect_architectural_issues(analysis_results)
    recommendations = generate_architectural_recommendations(analysis_results, context)

    {:ok,
     %{
       criteria_scores: analysis_results,
       identified_issues: architectural_issues,
       recommendations: recommendations,
       analysis_metadata: %{
         modules_analyzed: count_modules(code),
         functions_analyzed: count_functions(code),
         detected_patterns: extract_detected_patterns(analysis_results),
         architectural_metrics: calculate_architectural_metrics(code, context)
       }
     }}
  end

  defp analyze_modularity(code, context) do
    issues = []

    # Check module size and responsibilities
    oversized_modules = find_oversized_modules(code, context)

    issues =
      if length(oversized_modules) > 0, do: ["Oversized modules detected" | issues], else: issues

    # Check module cohesion
    low_cohesion = find_low_cohesion_modules(code, context)

    issues =
      if length(low_cohesion) > 0, do: ["Low cohesion modules found" | issues], else: issues

    # Check for god objects/modules
    god_modules = detect_god_modules(code, context)
    issues = if length(god_modules) > 0, do: ["God modules detected" | issues], else: issues

    score = calculate_modularity_score(oversized_modules, low_cohesion, god_modules)

    %{
      score: score,
      issues: issues,
      confidence: 0.8
    }
  end

  defp analyze_separation_of_concerns(code, context) do
    issues = []

    # Check for mixed responsibilities
    mixed_concerns = detect_mixed_concerns(code, context)
    issues = issues ++ mixed_concerns

    # Check layer violations
    layer_violations = detect_layer_violations(code, context)
    issues = issues ++ layer_violations

    # Check business logic separation
    business_logic_issues = analyze_business_logic_separation(code, context)
    issues = issues ++ business_logic_issues

    score = calculate_separation_score(issues)

    %{
      score: score,
      issues: issues,
      confidence: 0.7
    }
  end

  defp analyze_dependencies(code, context) do
    issues = []

    # Check circular dependencies
    circular_deps = detect_circular_dependencies(code, context)

    issues =
      if length(circular_deps) > 0, do: ["Circular dependencies found" | issues], else: issues

    # Check dependency direction violations
    direction_violations = check_dependency_directions(code, context)
    issues = issues ++ direction_violations

    # Check for excessive dependencies
    excessive_deps = find_excessive_dependencies(code, context)

    issues =
      if length(excessive_deps) > 0,
        do: ["Modules with excessive dependencies" | issues],
        else: issues

    score = calculate_dependency_score(circular_deps, direction_violations, excessive_deps)

    %{
      score: score,
      issues: issues,
      confidence: 0.9
    }
  end

  defp analyze_design_patterns(code, known_patterns) do
    issues = []
    recommendations = []

    # Detect implemented patterns
    detected_patterns = detect_patterns_in_code(code, known_patterns)

    # Check for anti-patterns
    anti_patterns = detect_anti_patterns(code)
    issues = issues ++ Enum.map(anti_patterns, &"Anti-pattern detected: #{&1}")

    # Check for missing beneficial patterns
    beneficial_patterns = suggest_beneficial_patterns(code, detected_patterns)
    recommendations = recommendations ++ beneficial_patterns

    score = calculate_pattern_score(detected_patterns, anti_patterns)

    %{
      score: score,
      issues: issues,
      recommendations: recommendations,
      confidence: 0.6,
      detected_patterns: detected_patterns
    }
  end

  defp analyze_interface_design(code) do
    issues = []

    # Check interface consistency
    consistency_issues = check_interface_consistency(code)
    issues = issues ++ consistency_issues

    # Check for leaky abstractions
    leaky_abstractions = detect_leaky_abstractions(code)

    issues =
      if length(leaky_abstractions) > 0,
        do: ["Leaky abstractions detected" | issues],
        else: issues

    # Check interface granularity
    granularity_issues = analyze_interface_granularity(code)
    issues = issues ++ granularity_issues

    score = calculate_interface_score(issues)

    %{
      score: score,
      issues: issues,
      confidence: 0.8
    }
  end

  defp analyze_abstraction(code, context) do
    issues = []

    # Check abstraction levels
    level_violations = check_abstraction_levels(code, context)
    issues = issues ++ level_violations

    # Check for premature abstraction
    premature_abstraction = detect_premature_abstraction(code)

    issues =
      if length(premature_abstraction) > 0,
        do: ["Premature abstraction detected" | issues],
        else: issues

    # Check for missing abstractions
    missing_abstractions = find_missing_abstractions(code, context)
    issues = issues ++ missing_abstractions

    score = calculate_abstraction_score(issues)

    %{
      score: score,
      issues: issues,
      confidence: 0.7
    }
  end

  defp analyze_coupling_cohesion(code, context) do
    issues = []

    # Calculate coupling metrics
    coupling_metrics = calculate_coupling_metrics(code, context)

    issues =
      if coupling_metrics.high_coupling_count > 0 do
        ["High coupling detected in #{coupling_metrics.high_coupling_count} modules" | issues]
      else
        issues
      end

    # Calculate cohesion metrics
    cohesion_metrics = calculate_cohesion_metrics(code, context)

    issues =
      if cohesion_metrics.low_cohesion_count > 0 do
        ["Low cohesion detected in #{cohesion_metrics.low_cohesion_count} modules" | issues]
      else
        issues
      end

    score = calculate_coupling_cohesion_score(coupling_metrics, cohesion_metrics)

    %{
      score: score,
      issues: issues,
      confidence: 0.8,
      metrics: %{coupling: coupling_metrics, cohesion: cohesion_metrics}
    }
  end

  defp analyze_scalability_indicators(code, context) do
    issues = []

    # Check for scalability anti-patterns
    scalability_issues = detect_scalability_issues(code, context)
    issues = issues ++ scalability_issues

    # Check resource usage patterns
    resource_issues = analyze_resource_usage_patterns(code)
    issues = issues ++ resource_issues

    # Check for bottleneck indicators
    bottleneck_indicators = detect_potential_bottlenecks(code, context)
    issues = issues ++ bottleneck_indicators

    score = calculate_scalability_score(issues)

    %{
      score: score,
      issues: issues,
      confidence: 0.6
    }
  end

  # Scoring helper functions

  defp calculate_modularity_score(oversized, low_cohesion, god_modules) do
    base_score = 1.0
    deductions = 0.0

    deductions = deductions + length(oversized) * 0.15
    deductions = deductions + length(low_cohesion) * 0.2
    deductions = deductions + length(god_modules) * 0.3

    max(0.0, base_score - deductions)
  end

  defp calculate_separation_score(issues) do
    base_score = 1.0
    deduction = length(issues) * 0.2
    max(0.0, base_score - deduction)
  end

  defp calculate_dependency_score(circular, direction_violations, excessive) do
    base_score = 1.0
    deductions = 0.0

    # Circular deps are serious
    deductions = deductions + length(circular) * 0.4
    deductions = deductions + length(direction_violations) * 0.2
    deductions = deductions + length(excessive) * 0.1

    max(0.0, base_score - deductions)
  end

  defp calculate_pattern_score(detected_patterns, anti_patterns) do
    # Neutral starting point
    base_score = 0.7

    # Bonus for good patterns
    pattern_bonus = length(detected_patterns) * 0.1

    # Penalty for anti-patterns
    anti_pattern_penalty = length(anti_patterns) * 0.2

    score = base_score + pattern_bonus - anti_pattern_penalty
    max(0.0, min(1.0, score))
  end

  defp calculate_interface_score(issues) do
    base_score = 1.0
    deduction = length(issues) * 0.15
    max(0.0, base_score - deduction)
  end

  defp calculate_abstraction_score(issues) do
    base_score = 1.0
    deduction = length(issues) * 0.18
    max(0.0, base_score - deduction)
  end

  defp calculate_coupling_cohesion_score(coupling_metrics, cohesion_metrics) do
    base_score = 1.0

    coupling_penalty = coupling_metrics.average_coupling * 0.1
    cohesion_bonus = cohesion_metrics.average_cohesion * 0.1

    score = base_score - coupling_penalty + cohesion_bonus
    max(0.0, min(1.0, score))
  end

  defp calculate_scalability_score(issues) do
    base_score = 1.0
    deduction = length(issues) * 0.25
    max(0.0, base_score - deduction)
  end

  # Analysis implementation stubs (simplified for demo)

  defp find_oversized_modules(code, _context), do: []
  defp find_low_cohesion_modules(code, _context), do: []
  defp detect_god_modules(code, _context), do: []
  defp detect_mixed_concerns(code, _context), do: []
  defp detect_layer_violations(code, _context), do: []
  defp analyze_business_logic_separation(code, _context), do: []
  defp detect_circular_dependencies(code, _context), do: []
  defp check_dependency_directions(code, _context), do: []
  defp find_excessive_dependencies(code, _context), do: []
  defp detect_patterns_in_code(code, _patterns), do: ["Observer", "Strategy"]
  defp detect_anti_patterns(code), do: []
  defp suggest_beneficial_patterns(code, _detected), do: ["Consider Factory pattern"]
  defp check_interface_consistency(code), do: []
  defp detect_leaky_abstractions(code), do: []
  defp analyze_interface_granularity(code), do: []
  defp check_abstraction_levels(code, _context), do: []
  defp detect_premature_abstraction(code), do: []
  defp find_missing_abstractions(code, _context), do: []
  defp detect_scalability_issues(code, _context), do: []
  defp analyze_resource_usage_patterns(code), do: []
  defp detect_potential_bottlenecks(code, _context), do: []

  defp calculate_coupling_metrics(code, _context) do
    %{high_coupling_count: 0, average_coupling: 0.3}
  end

  defp calculate_cohesion_metrics(code, _context) do
    %{low_cohesion_count: 0, average_cohesion: 0.7}
  end

  defp count_modules(code), do: 1
  defp count_functions(code), do: 5

  defp extract_detected_patterns(analysis_results) do
    analysis_results
    |> Map.get(:design_patterns, %{})
    |> Map.get(:detected_patterns, [])
  end

  defp calculate_architectural_metrics(code, context) do
    %{
      module_count: count_modules(code),
      function_count: count_functions(code),
      dependency_count: 3,
      abstraction_level: 0.6
    }
  end

  defp load_known_patterns do
    [
      "Observer",
      "Strategy",
      "Factory",
      "Singleton",
      "Command",
      "Decorator",
      "Adapter",
      "Facade",
      "Template Method",
      "State"
    ]
  end

  defp build_evaluation_result(analysis, weights) do
    weighted_score = calculate_weighted_score(analysis.criteria_scores, weights)
    overall_confidence = calculate_overall_confidence(analysis.criteria_scores)

    %{
      score: weighted_score,
      confidence: overall_confidence,
      specialization: :architecture,
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

  defp collect_architectural_issues(analysis_results) do
    Enum.flat_map(analysis_results, fn {criterion, result} ->
      issues = Map.get(result, :issues, [])

      Enum.map(issues, fn issue ->
        %{
          criterion: criterion,
          description: issue,
          severity: determine_architectural_severity(issue),
          category: :architectural
        }
      end)
    end)
  end

  defp generate_architectural_recommendations(analysis_results, context) do
    base_recommendations = [
      "Consider applying SOLID principles more consistently",
      "Review module boundaries and responsibilities",
      "Consider introducing abstraction layers where appropriate"
    ]

    # Add pattern-specific recommendations
    pattern_recs =
      analysis_results
      |> Map.get(:design_patterns, %{})
      |> Map.get(:recommendations, [])

    base_recommendations ++ pattern_recs
  end

  defp determine_architectural_severity(issue) do
    cond do
      String.contains?(issue, ["circular", "god", "violation"]) -> :high
      String.contains?(issue, ["coupling", "cohesion", "abstraction"]) -> :medium
      true -> :low
    end
  end

  defp get_default_weights do
    %{
      modularity: 1.2,
      separation_of_concerns: 1.3,
      dependency_management: 1.4,
      design_patterns: 0.8,
      interface_design: 1.0,
      abstraction_levels: 1.1,
      coupling_cohesion: 1.3,
      scalability_indicators: 0.9
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
