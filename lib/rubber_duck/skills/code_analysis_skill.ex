defmodule RubberDuck.Skills.CodeAnalysisSkill do
  @moduledoc """
  Skill for analyzing code quality with impact assessment and intelligent suggestions.

  This skill provides comprehensive code analysis including dependency impact,
  performance implications, security concerns, and maintainability assessments.
  Enhanced with impact assessment capabilities for understanding change propagation.
  
  Supports both legacy string-based signals and new typed messages for gradual migration.
  """

  use RubberDuck.Skills.Base,
    name: "code_analysis",
    description: "Analyzes code quality with impact assessment and improvement suggestions",
    category: "development",
    tags: ["code", "analysis", "quality", "impact", "performance", "security"],
    vsn: "2.0.0",
    opts_key: :code_analysis,
    signal_patterns: [
      "code.analyze.*",
      "code.quality.*",
      "code.impact.*",
      "code.performance.*",
      "code.security.*"
    ],
    opts_schema: [
      enabled: [type: :boolean, default: true],
      depth: [type: :atom, default: :moderate, values: [:shallow, :moderate, :deep]],
      auto_fix: [type: :boolean, default: false],
      impact_analysis: [type: :boolean, default: true],
      performance_check: [type: :boolean, default: true],
      security_scan: [type: :boolean, default: true],
      dependency_tracking: [type: :boolean, default: true]
    ]

  require Logger
  
  alias RubberDuck.Messages.Code.{
    Analyze,
    QualityCheck,
    ImpactAssess,
    PerformanceAnalyze,
    SecurityScan
  }

  @impl true
  def handle_signal(%{type: "code.analyze.file"} = signal, state) do
    # Comprehensive file analysis with impact assessment
    analysis_depth = state.opts.depth || :moderate

    result = %{
      file: signal.data.file_path,
      quality_score: calculate_quality_score(signal.data),
      issues: detect_issues(signal.data, analysis_depth),
      suggestions: generate_suggestions(signal.data, analysis_depth)
    }

    # Add impact assessment if enabled
    result =
      if state.opts.impact_analysis do
        Map.put(result, :impact, assess_change_impact(signal.data, state))
      else
        result
      end

    # Add performance analysis if enabled
    result =
      if state.opts.performance_check do
        Map.put(result, :performance, analyze_performance(signal.data))
      else
        result
      end

    # Add security scan if enabled
    result =
      if state.opts.security_scan do
        Map.put(result, :security, scan_security_issues(signal.data))
      else
        result
      end

    # Update state with analysis history
    updated_state = track_analysis_history(state, signal.data.file_path, result)

    {:ok, result, updated_state}
  end

  @impl true
  def handle_signal(%{type: "code.quality.check"} = signal, state) do
    # Perform quality check
    result = %{
      status: :completed,
      metrics: extract_metrics(signal.data),
      recommendations: build_recommendations(signal.data)
    }

    {:ok, result, state}
  end

  @impl true
  def handle_signal(%{type: "code.impact.assess"} = signal, state) do
    # Assess the impact of code changes
    file_path = signal.data.file_path
    changes = signal.data.changes || %{}

    impact_result = %{
      file: file_path,
      direct_impact: analyze_direct_impact(changes, state),
      dependency_impact: analyze_dependency_impact(file_path, state),
      performance_impact: estimate_performance_impact(changes),
      risk_assessment: assess_change_risk(changes, state),
      affected_files: find_affected_files(file_path, state),
      test_coverage_impact: assess_test_coverage_impact(changes)
    }

    # Emit warning if high risk detected
    if impact_result.risk_assessment.level == :high do
      emit_signal("code.impact.high_risk", %{
        file: file_path,
        risk: impact_result.risk_assessment
      })
    end

    {:ok, impact_result, state}
  end

  @impl true
  def handle_signal(%{type: "code.performance.analyze"} = signal, state) do
    # Analyze performance characteristics
    content = signal.data.content

    perf_analysis = %{
      complexity: calculate_cyclomatic_complexity(content),
      memory_usage: estimate_memory_usage(content),
      database_queries: detect_database_queries(content),
      potential_bottlenecks: identify_bottlenecks(content),
      optimization_opportunities: suggest_performance_optimizations(content)
    }

    {:ok, perf_analysis, state}
  end

  @impl true
  def handle_signal(%{type: "code.security.scan"} = signal, state) do
    # Scan for security vulnerabilities
    content = signal.data.content
    file_type = signal.data.file_type || detect_file_type(signal.data.file_path)

    security_scan = %{
      vulnerabilities: scan_for_vulnerabilities(content, file_type),
      unsafe_operations: detect_unsafe_operations(content),
      input_validation: check_input_validation(content),
      authentication_issues: check_authentication_issues(content),
      risk_level: calculate_security_risk_level(content)
    }

    # Track security issues in state
    updated_state =
      if length(security_scan.vulnerabilities) > 0 do
        track_security_issues(state, signal.data.file_path, security_scan.vulnerabilities)
      else
        state
      end

    {:ok, security_scan, updated_state}
  end

  @impl true
  def handle_signal(_signal, state) do
    {:ok, state}
  end

  # Typed message handlers
  
  @doc """
  Handle typed Analyze message for code analysis
  """
  def handle_analyze(%Analyze{} = msg, context) do
    state = context[:state] || %{}
    
    # Convert typed message to data format expected by existing logic
    data = %{
      file_path: msg.file_path,
      depth: msg.depth,
      auto_fix: msg.auto_fix,
      content: msg.context[:content],
      complexity: msg.context[:complexity],
      lines: msg.context[:lines],
      duplication: msg.context[:duplication]
    }
    
    # Reuse existing analysis logic
    result = %{
      file: msg.file_path,
      quality_score: calculate_quality_score(data),
      issues: detect_issues(data, msg.depth),
      suggestions: generate_suggestions(data, msg.depth)
    }
    
    # Add specialized analysis based on type
    result = 
      case msg.analysis_type do
        :comprehensive ->
          result
          |> Map.put(:impact, assess_change_impact(data, state))
          |> Map.put(:performance, analyze_performance(data))
          |> Map.put(:security, scan_security_issues(data))
        
        :security ->
          Map.put(result, :security, scan_security_issues(data))
        
        :performance ->
          Map.put(result, :performance, analyze_performance(data))
        
        :quality ->
          result
      end
    
    {:ok, result}
  end
  
  @doc """
  Handle typed QualityCheck message
  """
  def handle_quality_check(%QualityCheck{} = msg, _context) do
    data = %{
      target: msg.target,
      metrics: msg.metrics,
      thresholds: msg.thresholds
    }
    
    result = %{
      status: :completed,
      metrics: extract_metrics(data),
      recommendations: build_recommendations(data),
      passed: check_thresholds(data.metrics, data.thresholds)
    }
    
    {:ok, result}
  end
  
  @doc """
  Handle typed ImpactAssess message
  """
  def handle_impact_assess(%ImpactAssess{} = msg, context) do
    state = context[:state] || %{}
    
    impact_result = %{
      file: msg.file_path,
      direct_impact: analyze_direct_impact(msg.changes, state),
      dependency_impact: analyze_dependency_impact(msg.file_path, state),
      performance_impact: estimate_performance_impact(msg.changes),
      risk_score: calculate_impact_risk_score(msg.changes),
      affected_files: identify_affected_files(msg.file_path, state),
      suggested_tests: suggest_tests_for_changes(msg.changes)
    }
    
    {:ok, impact_result}
  end
  
  @doc """
  Handle typed PerformanceAnalyze message
  """
  def handle_performance_analyze(%PerformanceAnalyze{} = msg, _context) do
    data = %{
      content: msg.content,
      metrics: msg.metrics
    }
    
    performance_result = %{
      hot_spots: identify_performance_hotspots(data.content),
      memory_usage: estimate_memory_usage(data.content),
      complexity_analysis: analyze_algorithmic_complexity(data.content),
      bottlenecks: detect_bottlenecks(data.content),
      optimizations: suggest_optimizations(data.content)
    }
    
    {:ok, performance_result}
  end
  
  @doc """
  Handle typed SecurityScan message
  """
  def handle_security_scan(%SecurityScan{} = msg, _context) do
    
    security_scan = %{
      vulnerabilities: scan_for_vulnerabilities(msg.content, msg.file_type),
      unsafe_operations: detect_unsafe_operations(msg.content),
      input_validation: check_input_validation(msg.content),
      authentication_issues: check_authentication_issues(msg.content),
      risk_level: calculate_security_risk_level(msg.content),
      cwe_mappings: map_to_cwe_categories(msg.content, msg.file_type)
    }
    
    # Track security issues if any found
    if length(security_scan.vulnerabilities) > 0 do
      Logger.warning("Security vulnerabilities found: #{inspect(security_scan.vulnerabilities)}")
    end
    
    {:ok, security_scan}
  end

  # Private helper functions

  defp calculate_quality_score(data) do
    # Simplified quality score calculation
    base_score = 100

    deductions = [
      {data[:complexity] > 10, 20},
      {data[:lines] > 100, 10},
      {data[:duplication] > 0.2, 15}
    ]

    Enum.reduce(deductions, base_score, fn {condition, penalty}, score ->
      if condition, do: score - penalty, else: score
    end) / 100.0
  end

  defp detect_issues(data, depth) do
    issues = []

    issues =
      if data[:complexity] > 10 do
        [
          %{
            type: :complexity,
            severity: :high,
            message: "High complexity detected",
            line: data[:line]
          }
          | issues
        ]
      else
        issues
      end

    issues =
      if data[:lines] > 100 do
        [%{type: :length, severity: :medium, message: "File is too long"} | issues]
      else
        issues
      end

    # Add more issues for deeper analysis
    issues =
      if depth in [:moderate, :deep] do
        issues
        |> detect_naming_issues(data)
        |> detect_documentation_issues(data)
        |> detect_pattern_violations(data)
      else
        issues
      end

    issues
  end

  defp generate_suggestions(data, depth) do
    suggestions = []

    suggestions =
      if data[:complexity] > 10 do
        [
          %{
            type: :refactor,
            priority: :high,
            action: "Consider breaking down complex functions",
            impact: :high,
            effort: :medium
          }
          | suggestions
        ]
      else
        suggestions
      end

    # Add more suggestions for deeper analysis
    suggestions =
      if depth in [:moderate, :deep] do
        suggestions
        |> add_performance_suggestions(data)
        |> add_maintainability_suggestions(data)
        |> add_testing_suggestions(data)
      else
        suggestions
      end

    suggestions
  end

  defp extract_metrics(data) do
    %{
      loc: data[:lines] || 0,
      complexity: data[:complexity] || 0,
      coverage: data[:coverage] || 0.0,
      duplication: data[:duplication] || 0.0
    }
  end

  defp build_recommendations(data) do
    recs = []

    recs =
      if data[:coverage] < 0.8 do
        ["Increase test coverage to at least 80%" | recs]
      else
        recs
      end

    recs =
      if data[:duplication] > 0.1 do
        ["Reduce code duplication" | recs]
      else
        recs
      end

    recs
  end

  # Impact Assessment Functions

  defp assess_change_impact(data, state) do
    %{
      scope: determine_impact_scope(data),
      severity: calculate_impact_severity(data),
      dependencies: analyze_dependency_chain(data, state),
      estimated_effort: estimate_fix_effort(data),
      rollback_complexity: assess_rollback_complexity(data)
    }
  end

  defp analyze_direct_impact(changes, _state) do
    %{
      lines_affected: changes[:lines_changed] || 0,
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
      overall_impact: :neutral
    }
  end

  defp assess_change_risk(changes, _state) do
    risk_factors = []

    risk_factors =
      if changes[:breaking_changes] do
        [{:breaking_changes, 0.8} | risk_factors]
      else
        risk_factors
      end

    risk_factors =
      if changes[:complexity_delta] > 5 do
        [{:high_complexity_increase, 0.6} | risk_factors]
      else
        risk_factors
      end

    risk_factors =
      if changes[:test_coverage_delta] < -0.1 do
        [{:reduced_test_coverage, 0.7} | risk_factors]
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

  # Performance Analysis Functions

  defp analyze_performance(data) do
    %{
      time_complexity: estimate_time_complexity(data),
      space_complexity: estimate_space_complexity(data),
      database_operations: count_database_operations(data),
      external_calls: count_external_calls(data),
      optimization_potential: calculate_optimization_potential(data)
    }
  end

  defp calculate_cyclomatic_complexity(content) do
    # Count decision points in the code
    conditionals = count_pattern(content, ~r/\b(if|unless|case|cond|when)\b/)
    loops = count_pattern(content, ~r/\b(for|while|Enum\.\w+|Stream\.\w+)\b/)

    1 + conditionals + loops
  end

  defp estimate_memory_usage(content) do
    # Estimate based on data structure usage
    large_structures = count_pattern(content, ~r/\b(Map\.new|List\.duplicate|:ets\.new)\b/)
    recursion = count_pattern(content, ~r/\bdef\s+\w+/)

    %{
      estimated_mb: large_structures * 10 + recursion * 5,
      risk_level: if(large_structures + recursion > 5, do: :high, else: :low)
    }
  end

  defp detect_database_queries(content) do
    queries = []

    queries =
      if String.contains?(content, "Repo.") do
        [%{type: :ecto, count: count_pattern(content, ~r/Repo\.\w+/)} | queries]
      else
        queries
      end

    queries
  end

  defp identify_bottlenecks(content) do
    bottlenecks = []

    bottlenecks =
      if String.contains?(content, "Enum.") && String.contains?(content, "|> Enum.") do
        [
          %{type: :multiple_iterations, suggestion: "Consider using Stream or single pass"}
          | bottlenecks
        ]
      else
        bottlenecks
      end

    bottlenecks =
      if count_pattern(content, ~r/\bn\+1\b|N\+1/) > 0 do
        [%{type: :n_plus_one, suggestion: "Potential N+1 query pattern detected"} | bottlenecks]
      else
        bottlenecks
      end

    bottlenecks
  end

  defp suggest_performance_optimizations(content) do
    optimizations = []

    optimizations =
      if String.contains?(content, "length(") && String.contains?(content, "== 0") do
        [
          %{
            pattern: "length() == 0",
            replacement: "Enum.empty?()",
            impact: :low
          }
          | optimizations
        ]
      else
        optimizations
      end

    optimizations
  end

  # Security Analysis Functions

  defp scan_security_issues(_data) do
    %{
      vulnerabilities: [],
      risk_level: :low,
      recommendations: []
    }
  end

  defp scan_for_vulnerabilities(content, _file_type) do
    vulnerabilities = []

    vulnerabilities =
      if String.contains?(content, "eval(") || String.contains?(content, "Code.eval_string") do
        [
          %{type: :code_injection, severity: :critical, message: "Potential code injection"}
          | vulnerabilities
        ]
      else
        vulnerabilities
      end

    vulnerabilities =
      if Regex.match?(~r/password|secret|token|key.*=.*"[^"]+"/i, content) do
        [
          %{type: :hardcoded_secret, severity: :high, message: "Potential hardcoded secret"}
          | vulnerabilities
        ]
      else
        vulnerabilities
      end

    vulnerabilities
  end

  defp detect_unsafe_operations(content) do
    unsafe_ops = []

    unsafe_ops =
      if String.contains?(content, "System.cmd") do
        [%{operation: "System.cmd", risk: :command_injection} | unsafe_ops]
      else
        unsafe_ops
      end

    unsafe_ops =
      if String.contains?(content, ":os.cmd") do
        [%{operation: ":os.cmd", risk: :command_injection} | unsafe_ops]
      else
        unsafe_ops
      end

    unsafe_ops
  end

  defp check_input_validation(content) do
    %{
      validated_inputs: count_pattern(content, ~r/validate|changeset|cast/),
      unvalidated_risks: detect_unvalidated_inputs(content),
      recommendation: suggest_validation_improvements(content)
    }
  end

  defp check_authentication_issues(content) do
    issues = []

    issues =
      if String.contains?(content, "skip_before_action :authenticate") do
        [%{type: :skipped_auth, message: "Authentication bypass detected"} | issues]
      else
        issues
      end

    issues
  end

  defp calculate_security_risk_level(content) do
    risk_score = 0

    risk_score = risk_score + if String.contains?(content, "eval"), do: 10, else: 0
    risk_score = risk_score + if String.contains?(content, "System.cmd"), do: 5, else: 0
    risk_score = risk_score + if Regex.match?(~r/password.*=.*"/i, content), do: 7, else: 0

    cond do
      risk_score >= 10 -> :critical
      risk_score >= 7 -> :high
      risk_score >= 4 -> :medium
      risk_score > 0 -> :low
      true -> :none
    end
  end

  # Helper Functions

  defp track_analysis_history(state, file_path, result) do
    history = Map.get(state, :analysis_history, %{})

    updated_history =
      Map.update(history, file_path, [result], fn prev ->
        [result | Enum.take(prev, 9)]
      end)

    Map.put(state, :analysis_history, updated_history)
  end

  defp track_security_issues(state, file_path, vulnerabilities) do
    issues = Map.get(state, :security_issues, %{})
    updated_issues = Map.put(issues, file_path, vulnerabilities)
    Map.put(state, :security_issues, updated_issues)
  end

  defp detect_naming_issues(issues, data) do
    if data[:poor_naming] do
      [%{type: :naming, severity: :low, message: "Improve variable/function naming"} | issues]
    else
      issues
    end
  end

  defp detect_documentation_issues(issues, data) do
    if data[:doc_coverage] < 0.5 do
      [%{type: :documentation, severity: :medium, message: "Insufficient documentation"} | issues]
    else
      issues
    end
  end

  defp detect_pattern_violations(issues, data) do
    if data[:pattern_violations] do
      [
        %{type: :pattern, severity: :medium, message: "Design pattern violations detected"}
        | issues
      ]
    else
      issues
    end
  end

  defp add_performance_suggestions(suggestions, data) do
    if data[:performance_issues] do
      [
        %{
          type: :performance,
          priority: :medium,
          action: "Optimize performance bottlenecks",
          impact: :medium,
          effort: :medium
        }
        | suggestions
      ]
    else
      suggestions
    end
  end

  defp add_maintainability_suggestions(suggestions, data) do
    if data[:maintainability_score] < 0.6 do
      [
        %{
          type: :maintainability,
          priority: :medium,
          action: "Improve code maintainability",
          impact: :medium,
          effort: :low
        }
        | suggestions
      ]
    else
      suggestions
    end
  end

  defp add_testing_suggestions(suggestions, data) do
    if data[:test_coverage] < 0.8 do
      [
        %{
          type: :testing,
          priority: :high,
          action: "Increase test coverage",
          impact: :high,
          effort: :medium
        }
        | suggestions
      ]
    else
      suggestions
    end
  end

  defp determine_impact_scope(data) do
    cond do
      data[:breaking_changes] -> :major
      data[:api_changes] -> :moderate
      data[:internal_only] -> :minor
      true -> :unknown
    end
  end

  defp calculate_impact_severity(data) do
    severity_score = 0
    severity_score = severity_score + if data[:breaking_changes], do: 10, else: 0
    severity_score = severity_score + if data[:api_changes], do: 5, else: 0
    severity_score = severity_score + if data[:complexity_increase], do: 3, else: 0

    cond do
      severity_score >= 10 -> :critical
      severity_score >= 5 -> :high
      severity_score >= 3 -> :medium
      true -> :low
    end
  end

  defp analyze_dependency_chain(data, state) do
    %{
      direct: data[:direct_deps] || [],
      transitive: data[:transitive_deps] || [],
      circular: detect_circular_dependencies(data, state)
    }
  end

  defp estimate_fix_effort(data) do
    base_effort = data[:lines_changed] || 0
    complexity_factor = data[:complexity] || 1

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
    if data[:database_changes] || data[:external_api_changes] do
      :complex
    else
      :simple
    end
  end

  defp detect_api_changes(changes) do
    changes[:api_changes] || false
  end

  defp detect_breaking_changes(changes) do
    changes[:breaking_changes] || false
  end

  defp get_file_dependencies(_file_path, _state) do
    # Simplified dependency tracking
    %{
      direct: [],
      transitive: [],
      affected_modules: []
    }
  end

  defp calculate_impact_radius(dependencies) do
    length(dependencies.direct) + length(dependencies.transitive) * 0.5
  end

  defp identify_critical_paths(_dependencies) do
    # Identify critical dependency paths
    []
  end

  defp estimate_memory_change(changes) do
    changes[:memory_delta] || 0
  end

  defp estimate_runtime_change(changes) do
    changes[:runtime_delta] || 0
  end

  defp estimate_database_impact(changes) do
    changes[:database_operations_delta] || 0
  end

  defp determine_risk_level(risk_score) do
    cond do
      risk_score >= 2.0 -> :critical
      risk_score >= 1.5 -> :high
      risk_score >= 1.0 -> :medium
      risk_score >= 0.5 -> :low
      true -> :minimal
    end
  end

  defp suggest_risk_mitigation(risk_factors) do
    Enum.map(risk_factors, fn {factor, _} ->
      case factor do
        :breaking_changes -> "Add compatibility layer or deprecation warnings"
        :high_complexity_increase -> "Break down complex changes into smaller commits"
        :reduced_test_coverage -> "Add tests before merging"
        _ -> "Review changes carefully"
      end
    end)
  end

  defp file_depends_on?(_dependent_file, _target_file, _state) do
    # Simplified dependency check
    false
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

    suggestions
  end

  defp determine_test_priority(changes) do
    if changes[:api_changes] || changes[:breaking_changes] do
      :critical
    else
      :normal
    end
  end

  defp estimate_time_complexity(_data) do
    # Simplified time complexity estimation
    :linear
  end

  defp estimate_space_complexity(_data) do
    # Simplified space complexity estimation
    :linear
  end

  defp count_database_operations(data) do
    data[:database_ops] || 0
  end

  defp count_external_calls(data) do
    data[:external_calls] || 0
  end

  defp calculate_optimization_potential(data) do
    potential = 0
    potential = potential + if data[:complexity] > 10, do: 30, else: 0
    potential = potential + if data[:database_ops] > 5, do: 20, else: 0
    potential = potential + if data[:external_calls] > 3, do: 15, else: 0

    min(100, potential)
  end

  defp count_pattern(content, pattern) do
    content
    |> String.split(pattern)
    |> length()
    |> Kernel.-(1)
  end

  defp detect_unvalidated_inputs(content) do
    # Check for direct parameter usage without validation
    if String.contains?(content, "params[") && not String.contains?(content, "changeset") do
      [:direct_param_usage]
    else
      []
    end
  end

  defp suggest_validation_improvements(content) do
    if String.contains?(content, "changeset") do
      nil
    else
      "Consider using changesets for input validation"
    end
  end

  defp detect_circular_dependencies(_data, _state) do
    # Simplified circular dependency detection
    []
  end

  defp detect_file_type(file_path) do
    cond do
      String.ends_with?(file_path, ".ex") -> :elixir
      String.ends_with?(file_path, ".exs") -> :elixir_script
      String.ends_with?(file_path, ".js") -> :javascript
      true -> :unknown
    end
  end

  # Performance analysis helper functions
  
  defp identify_performance_hotspots(content) when is_binary(content) do
    # Identify potential performance bottlenecks in code
    hotspots = []
    
    # Check for nested loops
    if String.contains?(content, ["for", "Enum.each"]) and 
       String.contains?(content, ["Enum.map", "Enum.filter"]) do
      [{:nested_enumeration, :high, "Nested enumerations detected"}]
    else
      hotspots
    end
  end
  
  defp identify_performance_hotspots(_), do: []
  
  defp detect_bottlenecks(content) when is_binary(content) do
    bottlenecks = []
    
    # Check for N+1 query patterns
    bottlenecks = 
      if String.contains?(content, ["Repo.all", "Repo.get"]) do
        [{:potential_n_plus_one, "Multiple database queries in loop"}| bottlenecks]
      else
        bottlenecks
      end
    
    # Check for large data operations without streaming
    if String.contains?(content, "Enum.") and not String.contains?(content, "Stream.") do
      [{:no_streaming, "Large data operations without Stream module"} | bottlenecks]
    else
      bottlenecks
    end
  end
  
  defp detect_bottlenecks(_), do: []
  
  defp analyze_algorithmic_complexity(content) when is_binary(content) do
    # Simplified complexity analysis
    nested_loops = length(Regex.scan(~r/for.*do.*for/s, content))
    recursion = String.contains?(content, ["defp", "def"]) and 
                Regex.match?(~r/def\w*\s+(\w+).*\1\(/s, content)
    
    cond do
      nested_loops > 1 -> :exponential
      nested_loops == 1 -> :quadratic
      recursion -> :logarithmic
      true -> :linear
    end
  end
  
  defp analyze_algorithmic_complexity(_), do: :unknown
  
  defp suggest_optimizations(content) when is_binary(content) do
    optimizations = []
    
    # Suggest Stream for large enumerations
    optimizations = 
      if String.contains?(content, "Enum.") and not String.contains?(content, "Stream.") do
        ["Consider using Stream for large collections" | optimizations]
      else
        optimizations
      end
    
    # Suggest pattern matching over conditionals
    optimizations = 
      if String.contains?(content, ["if", "else", "cond"]) do
        ["Consider pattern matching instead of conditionals" | optimizations]
      else
        optimizations
      end
    
    optimizations
  end
  
  defp suggest_optimizations(_), do: []

  # Additional helper functions for typed messages
  
  defp check_thresholds(metrics, thresholds) when is_list(metrics) and is_map(thresholds) do
    Enum.all?(metrics, fn metric ->
      threshold = Map.get(thresholds, metric)
      if threshold, do: metric_passes_threshold?(metric, threshold), else: true
    end)
  end
  
  defp check_thresholds(_, _), do: true
  
  defp metric_passes_threshold?(metric, threshold) do
    # Simple threshold check - would be more complex in real implementation
    case metric do
      :complexity -> threshold >= 10
      :coverage -> threshold >= 80
      :duplication -> threshold <= 5
      _ -> true
    end
  end
  
  defp calculate_impact_risk_score(changes) when is_map(changes) do
    # Calculate risk based on the nature and scope of changes
    base_risk = map_size(changes) * 10
    
    # Add risk for critical file changes
    critical_risk = 
      if Map.keys(changes) |> Enum.any?(fn key ->
        key_str = to_string(key)
        String.contains?(key_str, ["auth", "security", "payment"])
      end) do
        50
      else
        0
      end
    
    min(base_risk + critical_risk, 100) / 100.0
  end
  
  defp calculate_impact_risk_score(_), do: 0.0
  
  defp identify_affected_files(file_path, _state) do
    # In a real implementation, this would use dependency tracking
    # For now, return a sample list
    [
      "#{file_path}_test.exs",
      String.replace(file_path, ".ex", "_spec.ex")
    ]
  end
  
  
  defp map_to_cwe_categories(content, file_type) do
    # Map vulnerabilities to CWE categories
    categories = []
    
    categories = 
      if String.contains?(content, ["eval", "Code.eval"]) do
        ["CWE-94: Code Injection" | categories]
      else
        categories
      end
    
    categories = 
      if String.contains?(content, "System.cmd") and file_type == :elixir do
        ["CWE-78: OS Command Injection" | categories]
      else
        categories
      end
    
    categories
  end
end
