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
  
  alias RubberDuck.Analyzers.Code.{Security, Performance, Quality, Impact}
  alias RubberDuck.Analyzers.Orchestrator

  @impl true
  def handle_signal(%{type: "code.analyze.file"} = signal, state) do
    # Use Orchestrator for comprehensive file analysis
    data = signal[:data] || %{}
    opts = state[:opts] || %{}
    
    request = %{
      file_path: data[:file_path] || "unknown",
      content: data[:content],
      analyzers: determine_analyzers_from_opts(opts),
      strategy: determine_strategy_from_depth(opts[:depth] || :moderate),
      context: %{
        state: state,
        signal_data: data
      },
      options: %{
        timeout: 30000
      }
    }
    
    case Orchestrator.orchestrate(request) do
      {:ok, orchestrated_result} ->
        # Convert orchestrator result to expected format
        result = convert_orchestrator_result(orchestrated_result)
        
        # Update state with analysis history
        updated_state = track_analysis_history(state, data[:file_path] || "unknown", result)
        
        {:ok, result, updated_state}
        
      {:error, reason} ->
        Logger.error("Orchestrated analysis failed: #{inspect(reason)}")
        {:error, reason, state}
    end
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
    # Create an ImpactAssess message for the Impact analyzer
    impact_assess_msg = %ImpactAssess{
      file_path: signal.data.file_path,
      changes: signal.data.changes || %{}
    }
    
    # Delegate to Impact analyzer
    case Impact.analyze(impact_assess_msg, %{state: state}) do
      {:ok, impact_result} ->
        # Convert to expected legacy format
        legacy_result = %{
          file: impact_result.file_path,
          direct_impact: impact_result.direct_impact,
          dependency_impact: impact_result.dependency_impact,
          performance_impact: impact_result.performance_impact,
          risk_assessment: impact_result.risk_assessment,
          affected_files: impact_result.affected_files,
          test_coverage_impact: impact_result.test_coverage_impact
        }
        
        # Emit warning if high risk detected
        if impact_result.risk_assessment.level == :high do
          emit_signal("code.impact.high_risk", %{
            file: impact_result.file_path,
            risk: impact_result.risk_assessment
          })
        end
        
        {:ok, legacy_result, state}
        
      {:error, reason} ->
        Logger.error("Impact assessment failed: #{inspect(reason)}")
        {:error, reason, state}
    end
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
    # Use Orchestrator for all analysis types
    analyzers = case msg.analysis_type do
      :comprehensive -> :all
      other -> [other]
    end
    
    strategy = case msg.depth do
      :shallow -> :quick
      :moderate -> :standard
      :deep -> :deep
      _ -> :standard
    end
    
    request = %{
      file_path: msg.file_path,
      content: context[:content],
      analyzers: analyzers,
      strategy: strategy,
      context: context,
      options: %{
        auto_fix: msg.auto_fix,
        timeout: 30000
      }
    }
    
    case Orchestrator.orchestrate(request) do
      {:ok, orchestrated_result} ->
        # Convert to expected format based on analysis type
        result = format_analyze_result(orchestrated_result, msg.analysis_type)
        {:ok, result}
        
      {:error, reason} ->
        Logger.error("Orchestrated analysis failed: #{inspect(reason)}")
        {:error, reason}
    end
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
    # Delegate to Impact analyzer
    case Impact.analyze(msg, context) do
      {:ok, impact_result} ->
        {:ok, impact_result}
      
      {:error, reason} ->
        Logger.error("Impact assessment failed: #{inspect(reason)}")
        {:error, reason}
    end
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

  # Helper functions for Orchestrator integration
  
  defp determine_analyzers_from_opts(opts) do
    analyzers = []
    
    # Check if options are explicitly enabled (default is true per opts_schema)
    analyzers = if Map.get(opts, :security_scan, true), do: analyzers ++ [:security], else: analyzers
    analyzers = if Map.get(opts, :performance_check, true), do: analyzers ++ [:performance], else: analyzers
    analyzers = if Map.get(opts, :impact_analysis, true), do: analyzers ++ [:impact], else: analyzers
    
    # Always include quality analysis
    [:quality | analyzers]
  end
  
  defp determine_strategy_from_depth(depth) do
    case depth do
      :shallow -> :quick
      :moderate -> :standard
      :deep -> :deep
      _ -> :standard
    end
  end
  
  defp convert_orchestrator_result(orchestrated_result) do
    results = orchestrated_result.results
    
    base_result = %{
      file: orchestrated_result.file_path,
      quality_score: results[:quality][:quality_score] || 0.5,
      issues: extract_all_issues(results),
      suggestions: extract_all_suggestions(orchestrated_result),
      overall_health: orchestrated_result.overall_health
    }
    
    # Add individual analysis results if present
    base_result
    |> maybe_add_result(:security, results[:security])
    |> maybe_add_result(:performance, results[:performance])
    |> maybe_add_result(:impact, results[:impact])
    |> maybe_add_result(:quality, results[:quality])
  end
  
  defp format_analyze_result(orchestrated_result, analysis_type) do
    results = orchestrated_result.results
    
    base = %{
      file: orchestrated_result.file_path,
      quality_score: results[:quality][:quality_score] || 0.5,
      issues: results[:quality][:issues] || [],
      suggestions: orchestrated_result.recommendations |> Enum.map(& &1.action)
    }
    
    case analysis_type do
      :comprehensive ->
        base
        |> Map.put(:quality, results[:quality])
        |> Map.put(:security, format_security_result(results[:security]))
        |> Map.put(:performance, format_performance_result(results[:performance]))
        |> Map.put(:impact, format_impact_result(results[:impact]))
        |> Map.put(:insights, orchestrated_result.insights)
        |> Map.put(:overall_health, orchestrated_result.overall_health)
        
      type when type in [:security, :performance, :quality, :impact] ->
        Map.put(base, type, results[type])
        
      _ ->
        base
    end
  end
  
  defp extract_all_issues(results) do
    issues = []
    
    issues = issues ++ (results[:quality][:issues] || [])
    issues = issues ++ (results[:security][:vulnerabilities] || [])
    
    if results[:performance][:bottlenecks] do
      issues ++ Enum.map(results[:performance][:bottlenecks], fn bottleneck ->
        %{type: :performance, description: bottleneck}
      end)
    else
      issues
    end
  end
  
  defp extract_all_suggestions(orchestrated_result) do
    orchestrated_result.recommendations
    |> Enum.take(5)
    |> Enum.map(& &1.action)
  end
  
  defp maybe_add_result(result, _key, nil), do: result
  defp maybe_add_result(result, key, value), do: Map.put(result, key, value)
  
  defp format_security_result(nil), do: %{vulnerabilities: [], risk_level: :none}
  defp format_security_result(security) do
    %{
      vulnerabilities: security[:vulnerabilities] || [],
      risk_level: security[:risk_level] || :none,
      recommendations: build_security_recommendations(security)
    }
  end
  
  defp format_performance_result(nil), do: %{optimization_potential: 0}
  defp format_performance_result(performance) do
    %{
      time_complexity: performance[:time_complexity] || :linear,
      space_complexity: performance[:space_complexity] || :constant,
      database_operations: performance[:database_operations] || [],
      bottlenecks: performance[:bottlenecks] || [],
      optimization_opportunities: performance[:optimization_opportunities] || [],
      optimization_potential: performance[:optimization_potential] || 0
    }
  end
  
  defp format_impact_result(nil), do: %{scope: :minimal, severity: :low}
  defp format_impact_result(impact) do
    %{
      scope: impact[:scope] || :minimal,
      severity: impact[:severity] || :low,
      dependencies: %{
        direct: impact[:dependency_impact][:direct_dependencies] || 0,
        transitive: impact[:dependency_impact][:transitive_dependencies] || 0,
        affected_modules: impact[:dependency_impact][:affected_modules] || []
      },
      estimated_effort: impact[:estimated_effort] || :trivial,
      rollback_complexity: impact[:rollback_complexity] || :simple
    }
  end
  
  # Quality analysis delegation helper (for backward compatibility)
  
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

  # Impact analysis delegation helper
  
  defp perform_impact_analysis(data, state, _context) do
    # Create an Analyze message for the Impact analyzer
    analyze_msg = %Analyze{
      file_path: data[:file_path] || "unknown",
      analysis_type: :impact,
      depth: :moderate,
      auto_fix: false
    }
    
    # Prepare context with the analysis data
    impact_context = %{
      lines_changed: data[:lines_changed] || data[:lines] || 0,
      functions_modified: data[:functions_modified] || [],
      modules_affected: data[:modules_affected] || [],
      complexity_delta: data[:complexity_delta] || 0,
      test_coverage_delta: data[:test_coverage_delta] || 0.0,
      breaking_changes: data[:breaking_changes],
      api_changes: data[:api_changes],
      internal_only: data[:internal_only],
      database_changes: data[:database_changes],
      external_api_changes: data[:external_api_changes],
      state: state
    }
    
    case Impact.analyze(analyze_msg, impact_context) do
      {:ok, impact_analysis} ->
        # Convert to legacy format for compatibility
        %{
          scope: impact_analysis.scope,
          severity: impact_analysis.severity,
          dependencies: %{
            direct: impact_analysis.dependency_impact.direct_dependencies,
            transitive: impact_analysis.dependency_impact.transitive_dependencies,
            affected_modules: impact_analysis.dependency_impact.affected_modules
          },
          estimated_effort: impact_analysis.estimated_effort,
          rollback_complexity: impact_analysis.rollback_complexity
        }
      
      {:error, reason} ->
        Logger.error("Impact analysis failed: #{inspect(reason)}")
        # Return empty analysis on error for backward compatibility
        %{
          scope: :minimal,
          severity: :low,
          dependencies: %{direct: 0, transitive: 0, affected_modules: []},
          estimated_effort: :trivial,
          rollback_complexity: :simple
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

  # Impact assessment functions moved to RubberDuck.Analyzers.Code.Impact
  # This skill now delegates all impact analysis to the dedicated analyzer

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
  # Impact helper functions moved to RubberDuck.Analyzers.Code.Impact

  # Impact-related helper functions moved to RubberDuck.Analyzers.Code.Impact


  defp count_pattern(content, pattern) do
    content
    |> String.split(pattern)
    |> length()
    |> Kernel.-(1)
  end

  # Input validation functions moved to Security analyzer


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

  # Impact risk calculation functions moved to RubberDuck.Analyzers.Code.Impact

  # CWE mapping functions moved to Security analyzer
end
