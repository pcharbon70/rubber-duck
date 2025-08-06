defmodule RubberDuck.Skills.CodeAnalysisSkill do
  @moduledoc """
  Skill for analyzing code quality and providing intelligent suggestions.

  This skill demonstrates how Skills could integrate with Jido agents to provide
  specialized code analysis capabilities.
  """

  use Jido.Skill,
    name: "code_analysis",
    description: "Analyzes code quality and provides improvement suggestions",
    category: "development",
    tags: ["code", "analysis", "quality"],
    vsn: "1.0.0",
    opts_key: :code_analysis,
    signal_patterns: [
      "code.analyze.*",
      "code.quality.*"
    ],
    opts_schema: [
      enabled: [type: :boolean, default: true],
      depth: [type: :atom, default: :moderate, values: [:shallow, :moderate, :deep]],
      auto_fix: [type: :boolean, default: false]
    ]

  @impl true
  def handle_signal(%{type: "code.analyze.file"} = signal, state) do
    # Analyze a specific file
    result = %{
      file: signal.data.file_path,
      quality_score: calculate_quality_score(signal.data),
      issues: detect_issues(signal.data),
      suggestions: generate_suggestions(signal.data)
    }

    {:ok, result, state}
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
  def handle_signal(_signal, state) do
    {:ok, state}
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

  defp detect_issues(data) do
    issues = []

    issues = if data[:complexity] > 10 do
      [%{type: :complexity, severity: :high, message: "High complexity detected"} | issues]
    else
      issues
    end

    issues = if data[:lines] > 100 do
      [%{type: :length, severity: :medium, message: "File is too long"} | issues]
    else
      issues
    end

    issues
  end

  defp generate_suggestions(data) do
    suggestions = []

    suggestions = if data[:complexity] > 10 do
      [%{
        type: :refactor,
        priority: :high,
        action: "Consider breaking down complex functions"
      } | suggestions]
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

    recs = if data[:coverage] < 0.8 do
      ["Increase test coverage to at least 80%" | recs]
    else
      recs
    end

    recs = if data[:duplication] > 0.1 do
      ["Reduce code duplication" | recs]
    else
      recs
    end

    recs
  end
end
