defmodule RubberDuck.Skills.CodeAnalysisSkill do
  @moduledoc """
  Skill for analyzing code quality with impact assessment and intelligent suggestions.

  This skill provides comprehensive code analysis including dependency impact,
  performance implications, security concerns, and maintainability assessments.
  Enhanced with impact assessment capabilities for understanding change propagation.

  Uses typed messages exclusively for all analysis operations.
  """

  use RubberDuck.Skills.Base,
    name: "code_analysis",
    description: "Analyzes code quality with impact assessment and improvement suggestions",
    category: "development",
    tags: ["code", "analysis", "quality", "impact", "performance", "security"],
    vsn: "3.0.0",
    opts_key: :code_analysis,
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

  # No legacy signal handlers - using typed messages exclusively

  # Typed message handlers

  @doc """
  Handle typed Analyze message for code analysis
  Called by Base module with state parameter
  """
  def handle_analyze(%Analyze{} = msg, state) when is_map(state) do
    # Check if this is being called from Base (state) or tests (context with content)
    if Map.has_key?(state, :content) do
      # This is actually a context from tests, handle differently
      handle_analyze_with_context(msg, state)
    else
      # This is the real state from Base module
      handle_analyze_with_state(msg, state)
    end
  end
  
  defp handle_analyze_with_state(msg, state) do
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
    
    # Extract context from message or use empty context
    context = msg.context || %{}
    
    request = %{
      file_path: msg.file_path,
      content: context[:content],
      analyzers: analyzers,
      strategy: strategy,
      context: Map.merge(context, %{state: state}),
      options: %{
        auto_fix: msg.auto_fix,
        timeout: 30000
      }
    }
    
    case Orchestrator.orchestrate(request) do
      {:ok, orchestrated_result} ->
        # Convert to expected format based on analysis type
        result = format_analyze_result(orchestrated_result, msg.analysis_type)
        
        # Update state if needed
        updated_state = track_analysis_history(state, msg.file_path, result)
        
        {:ok, result, updated_state}
        
      {:error, reason} ->
        Logger.error("Orchestrated analysis failed: #{inspect(reason)}")
        {:error, reason, state}
    end
  end
  
  defp handle_analyze_with_context(msg, context) do
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
  def handle_quality_check(%QualityCheck{} = msg, _state) do
    # Delegate to Quality analyzer
    case Quality.analyze(msg, %{}) do
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
  def handle_security_scan(%SecurityScan{} = msg, state) do
    # Delegate to Security analyzer
    case Security.analyze(msg, %{}) do
      {:ok, security_scan} ->
        # Track security issues if any found
        if length(security_scan.vulnerabilities) > 0 do
          Logger.warning("Security vulnerabilities found: #{inspect(security_scan.vulnerabilities)}")
        end
        
        updated_state = track_security_issues(state, security_scan.vulnerabilities)
        {:ok, security_scan, updated_state}
      
      {:error, reason} ->
        Logger.error("Security analysis failed: #{inspect(reason)}")
        {:error, reason, state}
    end
  end

  # Helper functions for Orchestrator integration
  
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
  
  # Functions moved to individual analyzers or no longer needed
  
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
  
  # Helper functions
  
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

  defp track_security_issues(state, vulnerabilities) do
    existing_issues = Map.get(state, :security_issues, [])
    updated_issues = existing_issues ++ vulnerabilities
    Map.put(state, :security_issues, updated_issues)
  end
  
  defp track_analysis_history(state, file_path, result) do
    history = Map.get(state, :analysis_history, %{})

    updated_history =
      Map.update(history, file_path, [result], fn prev ->
        [result | Enum.take(prev, 9)]
      end)

    Map.put(state, :analysis_history, updated_history)
  end

  # Legacy file_path version no longer needed - removed



  # All analyzer-specific functions have been moved to their respective analyzer modules:
  # - Security functions -> RubberDuck.Analyzers.Code.Security
  # - Performance functions -> RubberDuck.Analyzers.Code.Performance
  # - Quality functions -> RubberDuck.Analyzers.Code.Quality
  # - Impact functions -> RubberDuck.Analyzers.Code.Impact
end
