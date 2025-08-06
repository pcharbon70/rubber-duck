defmodule RubberDuck.Actions.AI.DiscoverPatterns do
  @moduledoc """
  Action for discovering patterns in code and analysis results.

  Identifies:
  - Recurring code patterns
  - Common issue types
  - Usage patterns
  - Quality trends
  """

  use Jido.Action,
    name: "discover_patterns",
    description: "Discover patterns in code and analyses",
    schema: [
      scope: [type: :atom, required: true],
      existing_patterns: [type: {:list, :map}, default: []],
      confidence_threshold: [type: :float, default: 0.7],
      min_occurrences: [type: :integer, default: 3]
    ]

  alias RubberDuck.{AI, Projects}
  require Logger

  @impl true
  def run(params, _context) do
    with {:ok, data} <- gather_data_for_scope(params.scope),
         {:ok, raw_patterns} <- extract_patterns(data, params),
         {:ok, validated} <- validate_patterns(raw_patterns, params.existing_patterns),
         {:ok, enriched} <- enrich_patterns(validated, data) do

      {:ok, %{
        patterns: enriched,
        new_patterns: identify_new_patterns(enriched, params.existing_patterns),
        pattern_count: length(enriched),
        scope: params.scope,
        confidence_scores: calculate_confidence_scores(enriched),
        insights: generate_pattern_insights(enriched)
      }}
    end
  end

  defp gather_data_for_scope(:project) do
    # Gather all analysis results for projects
    case AI.list_analysis_results() do
      {:ok, results} -> {:ok, %{type: :project, data: results}}
      error -> error
    end
  end

  defp gather_data_for_scope(:workspace) do
    # Gather all available data
    with {:ok, analyses} <- AI.list_analysis_results(),
         {:ok, projects} <- Projects.list_projects() do
      {:ok, %{
        type: :workspace,
        analyses: analyses,
        projects: projects,
        file_count: count_all_files(projects)
      }}
    end
  end

  defp gather_data_for_scope(scope) do
    {:error, "Unknown scope: #{scope}"}
  end

  defp count_all_files(projects) do
    Enum.reduce(projects, 0, fn project, acc ->
      case Projects.list_code_files_by_project(project.id) do
        {:ok, files} -> acc + length(files)
        _ -> acc
      end
    end)
  end

  defp extract_patterns(data, params) do
    patterns = case data.type do
      :project -> extract_project_patterns(data.data, params)
      :workspace -> extract_workspace_patterns(data, params)
      _ -> []
    end

    {:ok, patterns}
  end

  defp extract_project_patterns(analyses, params) do
    # Group analyses by type and extract patterns
    grouped = Enum.group_by(analyses, & &1.analysis_type)

    patterns = Enum.flat_map(grouped, fn {type, type_analyses} ->
      extract_type_patterns(type, type_analyses, params)
    end)

    # Add cross-type patterns
    cross_patterns = extract_cross_type_patterns(analyses, params)

    patterns ++ cross_patterns
  end

  defp extract_type_patterns(:complexity, analyses, params) do
    # Look for complexity patterns
    scores = analyses |> Enum.map(& &1.score) |> Enum.filter(& &1)

    patterns = []

    # High complexity pattern
    high_complexity = Enum.filter(scores, & &1 < 50)
    patterns = if length(high_complexity) >= params.min_occurrences do
      [%{
        type: :high_complexity,
        signature: "complexity_score_below_50",
        occurrences: length(high_complexity),
        confidence: 0.8,
        category: :quality
      } | patterns]
    else
      patterns
    end

    patterns
  end

  defp extract_type_patterns(:security, analyses, params) do
    # Look for security patterns
    vulnerabilities = analyses
      |> Enum.flat_map(fn analysis ->
        analysis.details[:vulnerabilities] || []
      end)

    # Group by vulnerability type
    grouped = Enum.group_by(vulnerabilities, & &1[:type])

    Enum.flat_map(grouped, fn {vuln_type, occurrences} ->
      if length(occurrences) >= params.min_occurrences do
        [%{
          type: :security_vulnerability,
          signature: "vuln_#{vuln_type}",
          occurrences: length(occurrences),
          confidence: 0.9,
          category: :security,
          details: %{vulnerability_type: vuln_type}
        }]
      else
        []
      end
    end)
  end

  defp extract_type_patterns(:quality, analyses, params) do
    # Extract quality patterns
    suggestions = analyses
      |> Enum.flat_map(& &1.suggestions || [])

    # Find common suggestions
    grouped = Enum.group_by(suggestions, &categorize_suggestion/1)

    Enum.flat_map(grouped, fn {category, items} ->
      if length(items) >= params.min_occurrences do
        [%{
          type: :quality_issue,
          signature: "quality_#{category}",
          occurrences: length(items),
          confidence: 0.75,
          category: :quality,
          examples: Enum.take(items, 3)
        }]
      else
        []
      end
    end)
  end

  defp extract_type_patterns(_type, _analyses, _params), do: []

  defp categorize_suggestion(suggestion) when is_binary(suggestion) do
    cond do
      String.contains?(suggestion, ["document", "comment"]) -> :documentation
      String.contains?(suggestion, ["test", "coverage"]) -> :testing
      String.contains?(suggestion, ["refactor", "simplify"]) -> :refactoring
      String.contains?(suggestion, ["performance", "optimize"]) -> :performance
      true -> :general
    end
  end
  defp categorize_suggestion(_), do: :general

  defp extract_cross_type_patterns(analyses, params) do
    # Look for patterns across different analysis types
    patterns = []

    # Group by project
    by_project = Enum.group_by(analyses, & &1.project_id)

    # Find projects with consistent issues
    problem_projects = Enum.flat_map(by_project, fn {project_id, project_analyses} ->
      avg_score = calculate_average_score(project_analyses)

      if avg_score < 60 && length(project_analyses) >= params.min_occurrences do
        [%{
          type: :problematic_project,
          signature: "project_quality_issues_#{project_id}",
          occurrences: length(project_analyses),
          confidence: 0.7,
          category: :project,
          details: %{
            project_id: project_id,
            average_score: avg_score
          }
        }]
      else
        []
      end
    end)

    patterns ++ problem_projects
  end

  defp calculate_average_score(analyses) do
    scores = analyses
      |> Enum.map(& &1.score)
      |> Enum.filter(& &1)

    if length(scores) > 0 do
      Enum.sum(scores) / length(scores)
    else
      100.0
    end
  end

  defp extract_workspace_patterns(data, params) do
    # Extract patterns across entire workspace
    project_patterns = extract_project_patterns(data.analyses, params)

    # Add workspace-specific patterns
    workspace_patterns = []

    # Language distribution pattern
    if data[:projects] do
      language_stats = analyze_language_distribution(data.projects)

      _workspace_patterns = if language_stats[:dominant_language] do
        [%{
          type: :language_dominance,
          signature: "lang_#{language_stats.dominant_language}",
          occurrences: language_stats.count,
          confidence: 0.85,
          category: :workspace,
          details: language_stats
        } | workspace_patterns]
      else
        workspace_patterns
      end
    end

    project_patterns ++ workspace_patterns
  end

  defp analyze_language_distribution(projects) do
    languages = projects
      |> Enum.map(& &1.language)
      |> Enum.filter(& &1)

    if length(languages) > 0 do
      grouped = Enum.group_by(languages, & &1)
      {dominant, count} = grouped
        |> Enum.map(fn {lang, items} -> {lang, length(items)} end)
        |> Enum.max_by(&elem(&1, 1))

      %{
        dominant_language: dominant,
        count: count,
        percentage: (count / length(languages)) * 100
      }
    else
      %{}
    end
  end

  defp validate_patterns(raw_patterns, existing_patterns) do
    # Remove duplicates and validate confidence
    validated = raw_patterns
      |> Enum.uniq_by(& &1.signature)
      |> Enum.filter(& &1.confidence >= 0.5)
      |> merge_with_existing(existing_patterns)

    {:ok, validated}
  end

  defp merge_with_existing(new_patterns, existing_patterns) do
    existing_map = Map.new(existing_patterns, & {&1.signature, &1})

    Enum.map(new_patterns, fn pattern ->
      case Map.get(existing_map, pattern.signature) do
        nil ->
          pattern
        existing ->
          # Merge and update confidence
          %{pattern |
            occurrences: pattern.occurrences + existing.occurrences,
            confidence: min(1.0, (pattern.confidence + existing.confidence) / 2 + 0.1)
          }
      end
    end)
  end

  defp enrich_patterns(patterns, data) do
    enriched = Enum.map(patterns, fn pattern ->
      pattern
      |> add_context(data)
      |> add_impact_assessment()
      |> add_recommendations()
    end)

    {:ok, enriched}
  end

  defp add_context(pattern, data) do
    context = case pattern.category do
      :quality -> build_quality_context(pattern, data)
      :security -> build_security_context(pattern, data)
      :project -> build_project_context(pattern, data)
      _ -> %{}
    end

    Map.put(pattern, :context, context)
  end

  defp build_quality_context(pattern, _data) do
    %{
      severity: determine_severity(pattern),
      frequency: categorize_frequency(pattern.occurrences),
      trend: :stable  # Would calculate from historical data
    }
  end

  defp build_security_context(pattern, _data) do
    %{
      risk_level: determine_risk_level(pattern),
      affected_components: [],  # Would identify from data
      mitigation_priority: :high
    }
  end

  defp build_project_context(pattern, _data) do
    %{
      project_id: pattern.details[:project_id],
      impact_scope: :project_wide
    }
  end

  defp determine_severity(pattern) do
    cond do
      pattern.occurrences > 10 -> :high
      pattern.occurrences > 5 -> :medium
      true -> :low
    end
  end

  defp categorize_frequency(occurrences) do
    cond do
      occurrences > 20 -> :very_frequent
      occurrences > 10 -> :frequent
      occurrences > 5 -> :occasional
      true -> :rare
    end
  end

  defp determine_risk_level(pattern) do
    if pattern.details[:vulnerability_type] in [:sql_injection, :xss, :rce] do
      :critical
    else
      :high
    end
  end

  defp add_impact_assessment(pattern) do
    impact = %{
      scope: determine_impact_scope(pattern),
      urgency: determine_urgency(pattern),
      effort: estimate_effort(pattern)
    }

    Map.put(pattern, :impact, impact)
  end

  defp determine_impact_scope(pattern) do
    case pattern.category do
      :workspace -> :global
      :project -> :project
      :security -> :critical
      _ -> :local
    end
  end

  defp determine_urgency(pattern) do
    cond do
      pattern.category == :security -> :immediate
      pattern.confidence > 0.9 && pattern.occurrences > 10 -> :high
      pattern.confidence > 0.7 -> :medium
      true -> :low
    end
  end

  defp estimate_effort(pattern) do
    case pattern.type do
      :security_vulnerability -> :high
      :high_complexity -> :medium
      :quality_issue -> :low
      _ -> :unknown
    end
  end

  defp add_recommendations(pattern) do
    recommendations = generate_pattern_recommendations(pattern)
    Map.put(pattern, :recommendations, recommendations)
  end

  defp generate_pattern_recommendations(pattern) do
    base_recommendations = case pattern.type do
      :high_complexity ->
        ["Refactor complex code sections", "Break down large functions"]
      :security_vulnerability ->
        ["Perform security audit", "Apply security patches"]
      :quality_issue ->
        ["Improve code quality metrics", "Add documentation"]
      :problematic_project ->
        ["Review project architecture", "Conduct code review"]
      _ ->
        []
    end

    # Add specific recommendations based on pattern details
    specific = if pattern.details[:vulnerability_type] do
      ["Fix #{pattern.details.vulnerability_type} vulnerabilities"]
    else
      []
    end

    base_recommendations ++ specific
  end

  defp identify_new_patterns(enriched, existing_patterns) do
    existing_signatures = MapSet.new(existing_patterns, & &1.signature)

    Enum.filter(enriched, fn pattern ->
      not MapSet.member?(existing_signatures, pattern.signature)
    end)
  end

  defp calculate_confidence_scores(patterns) do
    Enum.reduce(patterns, %{}, fn pattern, acc ->
      Map.put(acc, pattern.signature, pattern.confidence)
    end)
  end

  defp generate_pattern_insights(patterns) do
    insights = []

    # Category distribution
    by_category = Enum.group_by(patterns, & &1.category)
    insights = ["Found patterns in #{map_size(by_category)} categories" | insights]

    # High confidence patterns
    high_confidence = Enum.filter(patterns, & &1.confidence > 0.8)
    insights = if length(high_confidence) > 0 do
      ["#{length(high_confidence)} high-confidence patterns identified" | insights]
    else
      insights
    end

    # Critical patterns
    critical = Enum.filter(patterns, fn p ->
      p[:impact] && p.impact.urgency == :immediate
    end)

    insights = if length(critical) > 0 do
      ["#{length(critical)} patterns require immediate attention" | insights]
    else
      insights
    end

    insights
  end
end
