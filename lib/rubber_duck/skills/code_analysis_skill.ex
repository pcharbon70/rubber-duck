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
  
  alias RubberDuck.Analyzers.Code.{Security, Performance, Quality}

  @impl true
  def handle_signal(%{type: "code.analyze.file"} = signal, state) do
    # Comprehensive file analysis with impact assessment
    analysis_depth = state.opts.depth || :moderate

    quality_analysis = perform_quality_analysis(signal.data, analysis_depth)
    
    result = %{
      file: signal.data.file_path,
      quality_score: quality_analysis.quality_score,
      issues: quality_analysis.issues,
      suggestions: quality_analysis.suggestions
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
        performance_analysis = perform_performance_analysis(signal.data)
        Map.put(result, :performance, performance_analysis)
      else
        result
      end

    # Add security scan if enabled
    result =
      if state.opts.security_scan do
        security_analysis = perform_security_analysis(signal.data)
        Map.put(result, :security, security_analysis)
      else
        result
      end

    # Update state with analysis history
    updated_state = track_analysis_history(state, signal.data.file_path, result)

    {:ok, result, updated_state}
  end

  @impl true
  def handle_signal(%{type: "code.quality.check"} = signal, state) do
    # Create a QualityCheck message for the Quality analyzer
    quality_check_msg = %QualityCheck{
      target: signal.data.target || signal.data.file_path || "unknown",
      metrics: signal.data.metrics || [:complexity, :coverage, :duplication],
      thresholds: signal.data.thresholds || %{}
    }
    
    # Delegate to Quality analyzer
    case Quality.analyze(quality_check_msg, %{}) do
      {:ok, quality_result} ->
        # Convert to expected legacy format with quality_score in root
        legacy_result = Map.put(quality_result, :quality_score, quality_result.quality_score)
        {:ok, legacy_result, state}
        
      {:error, reason} ->
        Logger.error("Quality check failed: #{inspect(reason)}")
        {:error, reason, state}
    end
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
    # Create a PerformanceAnalyze message for the Performance analyzer
    performance_analyze_msg = %PerformanceAnalyze{
      content: signal.data.content,
      metrics: signal.data.metrics || [:complexity, :hotspots, :optimizations]
    }
    
    # Delegate to Performance analyzer
    case Performance.analyze(performance_analyze_msg, %{}) do
      {:ok, performance_analysis} ->
        {:ok, performance_analysis, state}
        
      {:error, reason} ->
        Logger.error("Performance analysis failed: #{inspect(reason)}")
        {:error, reason, state}
    end
  end

  @impl true
  def handle_signal(%{type: "code.security.scan"} = signal, state) do
    # Create a SecurityScan message for the Security analyzer
    security_scan_msg = %SecurityScan{
      content: signal.data.content,
      file_type: signal.data.file_type || detect_file_type(signal.data.file_path)
    }
    
    # Delegate to Security analyzer
    case Security.analyze(security_scan_msg, %{}) do
      {:ok, security_scan} ->
        # Track security issues in state
        updated_state =
          if Enum.empty?(security_scan.vulnerabilities) do
            state
          else
            track_security_issues(state, signal.data.file_path, security_scan.vulnerabilities)
          end

        # Return the security scan result in the expected format
        {:ok, security_scan, updated_state}
        
      {:error, reason} ->
        Logger.error("Security scan failed: #{inspect(reason)}")
        {:error, reason, state}
    end
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
      content: context[:content],
      complexity: context[:complexity],
      lines: context[:lines],
      duplication: context[:duplication]
    }

    # Use quality analyzer for basic analysis
    quality_analysis = perform_quality_analysis(data, msg.depth)
    
    result = %{
      file: msg.file_path,
      quality_score: quality_analysis.quality_score,
      issues: quality_analysis.issues,
      suggestions: quality_analysis.suggestions
    }

    # Add specialized analysis based on type
    result =
      case msg.analysis_type do
        :comprehensive ->
          security_analysis = perform_security_analysis(data)
          performance_analysis = perform_performance_analysis(data)
          result
          |> Map.put(:impact, assess_change_impact(data, state))
          |> Map.put(:performance, performance_analysis)
          |> Map.put(:security, security_analysis)
          |> Map.put(:quality, quality_analysis)

        :security ->
          security_analysis = perform_security_analysis(data)
          Map.put(result, :security, security_analysis)

        :performance ->
          performance_analysis = perform_performance_analysis(data)
          Map.put(result, :performance, performance_analysis)

        :quality ->
          Map.put(result, :quality, quality_analysis)
      end

    {:ok, result}
  end

  @doc """
  Handle typed QualityCheck message
  """
  def handle_quality_check(%QualityCheck{} = msg, context) do
    # Delegate to Quality analyzer
    case Quality.analyze(msg, context) do
      {:ok, quality_result} ->
        {:ok, quality_result}
      
      {:error, reason} ->
        Logger.error("Quality check failed: #{inspect(reason)}")
        {:error, reason}
    end
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
  def handle_performance_analyze(%PerformanceAnalyze{} = msg, context) do
    # Delegate to Performance analyzer
    case Performance.analyze(msg, context) do
      {:ok, performance_analysis} ->
        {:ok, performance_analysis}
      
      {:error, reason} ->
        Logger.error("Performance analysis failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Handle typed SecurityScan message
  """
  def handle_security_scan(%SecurityScan{} = msg, context) do
    # Delegate to Security analyzer
    case Security.analyze(msg, context) do
      {:ok, security_scan} ->
        # Track security issues if any found
        if length(security_scan.vulnerabilities) > 0 do
          Logger.warning("Security vulnerabilities found: #{inspect(security_scan.vulnerabilities)}")
        end
        
        {:ok, security_scan}
      
      {:error, reason} ->
        Logger.error("Security analysis failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Quality analysis delegation helper
  
  defp perform_quality_analysis(data, depth \\ :moderate) do
    # Create an Analyze message for the Quality analyzer
    analyze_msg = %Analyze{
      file_path: data[:file_path] || "unknown",
      analysis_type: :quality,
      depth: depth,
      auto_fix: false
    }
    
    # Prepare context with the analysis data
    context = %{
      content: data[:content],
      test_coverage: data[:test_coverage] || 0.0,
      complexity: data[:complexity],
      lines: data[:lines],
      duplication: data[:duplication],
      state: %{}
    }
    
    case Quality.analyze(analyze_msg, context) do
      {:ok, quality_analysis} ->
        # Convert to legacy format for compatibility
        %{
          quality_score: quality_analysis.quality_score,
          metrics: quality_analysis.metrics,
          issues: quality_analysis.issues,
          suggestions: quality_analysis.suggestions,
          recommendations: quality_analysis.recommendations || [],
          maintainability_score: quality_analysis.maintainability_score,
          technical_debt_indicators: quality_analysis.technical_debt_indicators
        }
      
      {:error, reason} ->
        Logger.error("Quality analysis failed: #{inspect(reason)}")
        # Return empty analysis on error for backward compatibility
        %{
          quality_score: 0.5,
          metrics: %{loc: 0, complexity: 1, coverage: 0.0, duplication: 0.0, maintainability_index: 50.0, documentation_coverage: 0.0},
          issues: [],
          suggestions: [],
          recommendations: [],
          maintainability_score: 0.5,
          technical_debt_indicators: []
        }
    end
  end

  # Performance analysis delegation helper
  
  defp perform_performance_analysis(data) do
    # Create an Analyze message for the Performance analyzer
    analyze_msg = %Analyze{
      file_path: data[:file_path] || "unknown",
      analysis_type: :performance,
      depth: :moderate,
      auto_fix: false
    }
    
    # Prepare context with the analysis data
    context = %{
      content: data[:content],
      state: %{}
    }
    
    case Performance.analyze(analyze_msg, context) do
      {:ok, performance_analysis} ->
        # Convert to legacy format for compatibility
        %{
          time_complexity: performance_analysis.time_complexity,
          space_complexity: performance_analysis.space_complexity,
          database_operations: performance_analysis.database_operations,
          bottlenecks: performance_analysis.bottlenecks,
          optimization_opportunities: performance_analysis.optimization_opportunities,
          optimization_potential: performance_analysis.optimization_potential
        }
      
      {:error, reason} ->
        Logger.error("Performance analysis failed: #{inspect(reason)}")
        # Return empty analysis on error for backward compatibility
        %{
          time_complexity: :linear,
          space_complexity: :constant,
          database_operations: [],
          bottlenecks: [],
          optimization_opportunities: [],
          optimization_potential: 0
        }
    end
  end

  # Security analysis delegation helper
  
  defp perform_security_analysis(data) do
    # Create an Analyze message for the Security analyzer
    analyze_msg = %Analyze{
      file_path: data[:file_path] || "unknown",
      analysis_type: :security,
      depth: :moderate,
      auto_fix: false
    }
    
    # Prepare context with the analysis data
    context = %{
      content: data[:content],
      state: %{}
    }
    
    case Security.analyze(analyze_msg, context) do
      {:ok, security_analysis} ->
        # Convert to legacy format for compatibility
        %{
          vulnerabilities: security_analysis.vulnerabilities,
          risk_level: security_analysis.risk_level,
          recommendations: build_security_recommendations(security_analysis)
        }
      
      {:error, reason} ->
        Logger.error("Security analysis failed: #{inspect(reason)}")
        # Return empty analysis on error for backward compatibility
        %{
          vulnerabilities: [],
          risk_level: :unknown,
          recommendations: []
        }
    end
  end
  
  defp build_security_recommendations(security_analysis) do
    recommendations = []
    
    # Add recommendations based on vulnerabilities
    recommendations =
      if length(security_analysis.vulnerabilities) > 0 do
        ["Address security vulnerabilities found in code" | recommendations]
      else
        recommendations
      end
    
    # Add recommendations based on unsafe operations
    recommendations =
      if length(security_analysis.unsafe_operations) > 0 do
        ["Review unsafe operations for potential security risks" | recommendations]
      else
        recommendations
      end
    
    # Add recommendations based on input validation
    recommendations =
      if length(security_analysis.input_validation.unvalidated_risks) > 0 do
        ["Improve input validation to prevent security issues" | recommendations]
      else
        recommendations
      end
    
    # Add recommendations based on authentication issues
    recommendations =
      if length(security_analysis.authentication_issues) > 0 do
        ["Review authentication bypasses and security controls" | recommendations]
      else
        recommendations
      end
    
    recommendations
  end
  
  # Quality analysis functions moved to RubberDuck.Analyzers.Code.Quality
  # This skill now delegates all quality analysis to the dedicated analyzer

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

  # Performance Analysis Functions (delegating to Performance analyzer)

  # Performance functions moved to RubberDuck.Analyzers.Code.Performance
  # This skill now delegates all performance analysis to the dedicated analyzer

  # Security Analysis Functions (delegating to Security analyzer)

  # Security functions have been extracted to RubberDuck.Analyzers.Code.Security
  # This skill now delegates all security analysis to the dedicated analyzer

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

  # Quality helper functions moved to RubberDuck.Analyzers.Code.Quality

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


  defp count_pattern(content, pattern) do
    content
    |> String.split(pattern)
    |> length()
    |> Kernel.-(1)
  end

  # Input validation functions moved to Security analyzer

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

  # Performance analysis helper functions moved to RubberDuck.Analyzers.Code.Performance

  # Additional helper functions for typed messages

  # Threshold checking functions moved to RubberDuck.Analyzers.Code.Quality

  defp calculate_impact_risk_score(changes) when is_map(changes) do
    # Calculate risk based on the nature and scope of changes
    base_risk = map_size(changes) * 10

    # Add risk for critical file changes
    change_keys = Map.keys(changes)
    has_critical_changes = 
      change_keys
      |> Enum.any?(fn key ->
        key_str = to_string(key)
        String.contains?(key_str, ["auth", "security", "payment"])
      end)
    
    critical_risk = if has_critical_changes, do: 50, else: 0

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

  # CWE mapping functions moved to Security analyzer
end
