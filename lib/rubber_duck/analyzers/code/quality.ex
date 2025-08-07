defmodule RubberDuck.Analyzers.Code.Quality do
  @moduledoc """
  Quality-focused code analysis.
  
  Analyzes code quality metrics including complexity, maintainability,
  documentation coverage, naming conventions, and provides improvement suggestions.
  
  ## Supported Analysis Types
  
  - Code quality scoring and metrics
  - Issue detection (complexity, length, patterns)
  - Maintainability assessments
  - Documentation coverage analysis
  - Improvement suggestion generation
  - Testing coverage recommendations
  
  ## Integration
  
  This analyzer extracts quality-specific logic from CodeAnalysisSkill
  while maintaining the same analysis capabilities in a focused module.
  """
  
  @behaviour RubberDuck.Analyzer
  
  alias RubberDuck.Messages.Code.{Analyze, QualityCheck}
  
  @impl true
  def analyze(%Analyze{analysis_type: :quality} = msg, context) do
    content = get_content_from_context(msg, context)
    data = build_analysis_data(msg, context, content)
    
    quality_analysis = %{
      quality_score: calculate_quality_score(data),
      metrics: extract_metrics(data),
      issues: detect_issues(data, msg.depth),
      suggestions: generate_suggestions(data, msg.depth),
      recommendations: build_recommendations(data),
      maintainability_score: calculate_maintainability_score(data),
      technical_debt_indicators: detect_technical_debt(data),
      analyzed_at: DateTime.utc_now(),
      file_path: msg.file_path
    }
    
    {:ok, quality_analysis}
  end
  
  def analyze(%Analyze{analysis_type: :comprehensive} = msg, context) do
    # For comprehensive analysis, return quality subset
    analyze(%{msg | analysis_type: :quality}, context)
  end
  
  def analyze(%QualityCheck{} = msg, _context) do
    # Convert QualityCheck to analysis data
    data = %{
      target: msg.target,
      metrics: msg.metrics,
      thresholds: msg.thresholds,
      complexity: get_complexity_from_target(msg.target),
      lines: get_lines_from_target(msg.target),
      coverage: get_coverage_from_target(msg.target),
      duplication: get_duplication_from_target(msg.target)
    }
    
    quality_check_result = %{
      status: :completed,
      metrics: extract_metrics(data),
      recommendations: build_recommendations(data),
      passed: check_thresholds(data.metrics, data.thresholds),
      quality_score: calculate_quality_score(data),
      analyzed_at: DateTime.utc_now(),
      target: msg.target
    }
    
    {:ok, quality_check_result}
  end
  
  def analyze(message, _context) do
    {:error, {:unsupported_message_type, message.__struct__}}
  end
  
  @impl true
  def supported_types do
    [Analyze, QualityCheck]
  end
  
  @impl true
  def priority, do: :normal
  
  @impl true  
  def timeout, do: 10_000
  
  @impl true
  def metadata do
    %{
      name: "Quality Analyzer",
      description: "Analyzes code quality metrics and provides improvement suggestions",
      version: "1.0.0",
      categories: [:quality, :code],
      tags: ["quality", "metrics", "maintainability", "documentation", "suggestions"]
    }
  end
  
  # Core quality analysis functions extracted from CodeAnalysisSkill
  
  defp calculate_quality_score(data) do
    # Simplified quality score calculation
    base_score = 100

    deductions = [
      {data[:complexity] && data[:complexity] > 10, 25},
      {data[:complexity] && data[:complexity] > 15, 15},  # Additional penalty for very high complexity
      {data[:lines] && data[:lines] > 100, 15},
      {data[:duplication] && data[:duplication] > 0.2, 20},
      {data[:doc_coverage] && data[:doc_coverage] < 0.5, 15},
      {data[:test_coverage] && data[:test_coverage] < 0.8, 20}
    ]

    final_score = Enum.reduce(deductions, base_score, fn {condition, penalty}, score ->
      if condition, do: score - penalty, else: score
    end)
    
    max(0, final_score) / 100.0
  end
  
  defp extract_metrics(data) do
    %{
      loc: data[:lines] || 0,
      complexity: data[:complexity] || 0,
      coverage: data[:coverage] || 0.0,
      duplication: data[:duplication] || 0.0,
      maintainability_index: calculate_maintainability_index(data),
      documentation_coverage: data[:doc_coverage] || 0.0
    }
  end
  
  defp detect_issues(data, depth) do
    issues = []

    issues =
      if data[:complexity] && data[:complexity] > 8 do
        [
          %{
            type: :complexity,
            severity: :high,
            message: "High complexity detected (#{data[:complexity]})",
            line: data[:line],
            suggestion: "Consider breaking down complex functions"
          }
          | issues
        ]
      else
        issues
      end

    issues =
      if data[:lines] && data[:lines] > 100 do
        [%{
          type: :length, 
          severity: :medium, 
          message: "File is too long (#{data[:lines]} lines)",
          suggestion: "Consider splitting into smaller modules"
        } | issues]
      else
        issues
      end
      
    issues =
      if data[:duplication] && data[:duplication] > 0.1 do
        [%{
          type: :duplication,
          severity: :medium,
          message: "High code duplication detected (#{Float.round(data[:duplication] * 100, 1)}%)",
          suggestion: "Extract common patterns into shared functions"
        } | issues]
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
        |> detect_maintainability_issues(data)
      else
        issues
      end

    issues
  end

  defp generate_suggestions(data, depth) do
    suggestions = []

    suggestions =
      if data[:complexity] && data[:complexity] > 10 do
        [
          %{
            type: :refactor,
            priority: :high,
            action: "Consider breaking down complex functions",
            impact: :high,
            effort: :medium,
            details: "Functions with cyclomatic complexity > 10 are harder to test and maintain"
          }
          | suggestions
        ]
      else
        suggestions
      end
      
    suggestions =
      if data[:duplication] && data[:duplication] > 0.1 do
        [
          %{
            type: :refactor,
            priority: :medium,
            action: "Reduce code duplication",
            impact: :medium,
            effort: :low,
            details: "Extract common patterns into reusable functions or modules"
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
        |> add_maintainability_suggestions(data)
        |> add_testing_suggestions(data)
        |> add_documentation_suggestions(data)
        |> add_performance_suggestions(data)
      else
        suggestions
      end

    suggestions
  end
  
  defp build_recommendations(data) do
    recs = []

    recs =
      if data[:coverage] && data[:coverage] < 0.8 do
        ["Increase test coverage to at least 80%" | recs]
      else
        recs
      end

    recs =
      if data[:duplication] && data[:duplication] > 0.1 do
        ["Reduce code duplication through refactoring" | recs]
      else
        recs
      end
        
    recs =
      if data[:complexity] && data[:complexity] > 15 do
        ["Break down complex functions for better maintainability" | recs]
      else
        recs
      end
        
    recs =
      if data[:doc_coverage] && data[:doc_coverage] < 0.6 do
        ["Improve documentation coverage for better maintainability" | recs]
      else
        recs
      end

    recs
  end
  
  # Quality-specific analysis functions
  
  defp calculate_maintainability_score(data) do
    # Maintainability index calculation (simplified)
    complexity_factor = if data[:complexity], do: min(data[:complexity] / 10.0, 1.0), else: 0.1
    length_factor = if data[:lines], do: min(data[:lines] / 200.0, 1.0), else: 0.1
    duplication_factor = data[:duplication] || 0.0
    doc_factor = 1.0 - (data[:doc_coverage] || 0.8)
    
    base_score = 1.0
    penalty = complexity_factor * 0.4 + length_factor * 0.2 + duplication_factor * 0.3 + doc_factor * 0.1
    
    max(0.0, base_score - penalty)
  end
  
  defp calculate_maintainability_index(data) do
    # Microsoft's Maintainability Index (simplified version)
    complexity = data[:complexity] || 1
    loc = data[:lines] || 10
    
    # Simplified formula: MI = max(0, (171 - 5.2 * ln(Halstead Volume) - 0.23 * (Cyclomatic Complexity) - 16.2 * ln(Lines of Code)) * 100 / 171)
    # Using simplified approximation since we don't have Halstead volume
    raw_mi = 171 - (0.23 * complexity) - (16.2 * :math.log(max(loc, 1)))
    
    max(0, (raw_mi * 100) / 171) |> Float.round(1)
  end
  
  defp detect_technical_debt(data) do
    indicators = []
    
    indicators =
      if data[:complexity] && data[:complexity] > 10 do
        [%{type: :high_complexity, severity: :high, impact: "Difficult to test and maintain"} | indicators]
      else
        indicators
      end
        
    indicators =
      if data[:duplication] && data[:duplication] > 0.2 do
        [%{type: :code_duplication, severity: :medium, impact: "Increases maintenance effort"} | indicators]
      else
        indicators
      end
        
    indicators =
      if data[:doc_coverage] && data[:doc_coverage] < 0.3 do
        [%{type: :poor_documentation, severity: :low, impact: "Reduces code understandability"} | indicators]
      else
        indicators
      end
        
    indicators =
      if data[:test_coverage] && data[:test_coverage] < 0.5 do
        [%{type: :low_test_coverage, severity: :high, impact: "Increases risk of regressions"} | indicators]
      else
        indicators
      end
    
    indicators
  end

  # Issue detection helper functions
  
  defp detect_naming_issues(issues, data) do
    if data[:poor_naming] do
      [%{
        type: :naming, 
        severity: :low, 
        message: "Improve variable/function naming",
        suggestion: "Use descriptive names that clearly express intent"
      } | issues]
    else
      issues
    end
  end

  defp detect_documentation_issues(issues, data) do
    if data[:doc_coverage] && data[:doc_coverage] < 0.5 do
      [%{
        type: :documentation, 
        severity: :medium, 
        message: "Insufficient documentation (#{Float.round(data[:doc_coverage] * 100, 1)}%)",
        suggestion: "Add module and function documentation"
      } | issues]
    else
      issues
    end
  end

  defp detect_pattern_violations(issues, data) do
    if data[:pattern_violations] do
      [
        %{
          type: :pattern, 
          severity: :medium, 
          message: "Design pattern violations detected",
          suggestion: "Review code structure and apply appropriate patterns"
        }
        | issues
      ]
    else
      issues
    end
  end
  
  defp detect_maintainability_issues(issues, data) do
    maintainability_score = calculate_maintainability_score(data)
    
    if maintainability_score < 0.6 do
      [%{
        type: :maintainability,
        severity: :medium,
        message: "Low maintainability score (#{Float.round(maintainability_score * 100, 1)}%)",
        suggestion: "Improve code structure, reduce complexity, and add documentation"
      } | issues]
    else
      issues
    end
  end

  # Suggestion generation helper functions

  defp add_maintainability_suggestions(suggestions, data) do
    maintainability_score = calculate_maintainability_score(data)
    
    if maintainability_score < 0.6 do
      [
        %{
          type: :maintainability,
          priority: :medium,
          action: "Improve code maintainability",
          impact: :medium,
          effort: :low,
          details: "Focus on reducing complexity, improving naming, and adding documentation"
        }
        | suggestions
      ]
    else
      suggestions
    end
  end

  defp add_testing_suggestions(suggestions, data) do
    if data[:test_coverage] && data[:test_coverage] < 0.8 do
      [
        %{
          type: :testing,
          priority: :high,
          action: "Increase test coverage",
          impact: :high,
          effort: :medium,
          details: "Add unit tests for uncovered code paths, especially edge cases"
        }
        | suggestions
      ]
    else
      suggestions
    end
  end
  
  defp add_documentation_suggestions(suggestions, data) do
    if data[:doc_coverage] && data[:doc_coverage] < 0.6 do
      [
        %{
          type: :documentation,
          priority: :medium,
          action: "Improve documentation coverage",
          impact: :medium,
          effort: :low,
          details: "Add @moduledoc and @doc attributes to modules and public functions"
        }
        | suggestions
      ]
    else
      suggestions
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
          effort: :medium,
          details: "Address identified performance issues for better runtime efficiency"
        }
        | suggestions
      ]
    else
      suggestions
    end
  end
  
  # Helper functions
  
  defp get_content_from_context(%{file_path: file_path}, context) do
    # Try to get content from context first, then read file
    case Map.get(context, :content) do
      nil -> read_file_content(file_path)
      content -> content
    end
  end
  
  defp read_file_content(file_path) do
    case File.read(file_path) do
      {:ok, content} -> content
      {:error, _} -> ""
    end
  end
  
  defp build_analysis_data(msg, context, content) do
    %{
      file_path: msg.file_path,
      content: content,
      complexity: calculate_complexity_from_content(content),
      lines: count_lines(content),
      duplication: estimate_duplication(content),
      doc_coverage: estimate_doc_coverage(content),
      test_coverage: Map.get(context, :test_coverage, 0.0),
      poor_naming: detect_poor_naming(content),
      pattern_violations: detect_pattern_violations_in_content(content),
      performance_issues: detect_performance_issues(content)
    }
  end
  
  defp calculate_complexity_from_content(content) when is_binary(content) do
    # Count decision points in the code
    conditionals = count_pattern(content, ~r/\b(if|unless|case|cond|when)\b/)
    loops = count_pattern(content, ~r/\b(for|while|Enum\.\w+|Stream\.\w+)\b/)

    1 + conditionals + loops
  end
  
  defp calculate_complexity_from_content(_), do: 1
  
  defp count_lines(content) when is_binary(content) do
    content
    |> String.split(["\n", "\r\n"])
    |> Enum.reject(&(String.trim(&1) == ""))
    |> length()
  end
  
  defp count_lines(_), do: 0
  
  defp estimate_duplication(content) when is_binary(content) do
    lines = String.split(content, ["\n", "\r\n"])
    unique_lines = lines |> Enum.map(&String.trim/1) |> Enum.uniq() |> length()
    total_lines = length(lines)
    
    if total_lines > 0 do
      1.0 - (unique_lines / total_lines)
    else
      0.0
    end
  end
  
  defp estimate_duplication(_), do: 0.0
  
  defp estimate_doc_coverage(content) when is_binary(content) do
    # Count @doc, @moduledoc, and # comment lines
    doc_patterns = [~r/@doc/, ~r/@moduledoc/, ~r/^\s*#/]
    total_doc_lines = Enum.reduce(doc_patterns, 0, fn pattern, acc ->
      acc + count_pattern(content, pattern)
    end)
    
    # Count functions and modules that should be documented
    functions = count_pattern(content, ~r/def\s+\w+/)
    modules = count_pattern(content, ~r/defmodule\s+\w+/)
    
    total_documentable = functions + modules
    
    if total_documentable > 0 do
      min(1.0, total_doc_lines / total_documentable)
    else
      1.0
    end
  end
  
  defp estimate_doc_coverage(_), do: 1.0
  
  defp detect_poor_naming(content) when is_binary(content) do
    # Simple heuristics for poor naming
    poor_names = [~r/\b[a-z]\b/, ~r/\bdata\d+\b/, ~r/\btemp\w*\b/, ~r/\bx\d*\b/]
    
    Enum.any?(poor_names, fn pattern ->
      String.match?(content, pattern)
    end)
  end
  
  defp detect_poor_naming(_), do: false
  
  defp detect_pattern_violations_in_content(content) when is_binary(content) do
    # Check for common anti-patterns
    violations = [
      String.contains?(content, "God."),  # God object pattern
      Regex.match?(~r/def\s+\w+.*do\s*$.*end$/s, content) && String.length(content) > 1000,  # Long methods
      count_pattern(content, ~r/if.*else.*if.*else/) > 2  # Deep nesting
    ]
    
    Enum.any?(violations)
  end
  
  defp detect_pattern_violations_in_content(_), do: false
  
  defp detect_performance_issues(content) when is_binary(content) do
    # Simple performance issue detection
    issues = [
      String.contains?(content, "Enum.") && String.contains?(content, "|> Enum."),  # Multiple enumerations
      String.contains?(content, "length(") && String.contains?(content, "== 0"),   # Inefficient empty check
      count_pattern(content, ~r/for.*do.*for/) > 0  # Nested loops
    ]
    
    Enum.any?(issues)
  end
  
  defp detect_performance_issues(_), do: false
  
  defp count_pattern(content, pattern) do
    content
    |> String.split(pattern)
    |> length()
    |> Kernel.-(1)
    |> max(0)
  end
  
  # QualityCheck-specific helper functions
  
  defp get_complexity_from_target(_target) do
    # In a real implementation, this would analyze the target
    # For now, return a default value
    5
  end
  
  defp get_lines_from_target(target) do
    # In a real implementation, this would count lines in the target
    case File.read(target) do
      {:ok, content} -> count_lines(content)
      {:error, _} -> 50
    end
  end
  
  defp get_coverage_from_target(_target) do
    # In a real implementation, this would get coverage metrics
    0.75
  end
  
  defp get_duplication_from_target(target) do
    # In a real implementation, this would analyze duplication
    case File.read(target) do
      {:ok, content} -> estimate_duplication(content)
      {:error, _} -> 0.1
    end
  end
  
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
      :complexity -> threshold <= 15  # Pass if threshold allows higher complexity
      :coverage -> threshold <= 80    # Pass if threshold allows lower coverage  
      :duplication -> threshold >= 5  # Pass if threshold allows higher duplication
      _ -> true
    end
  end
end