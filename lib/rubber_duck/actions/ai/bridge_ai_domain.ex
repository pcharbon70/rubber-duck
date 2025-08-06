defmodule RubberDuck.Actions.AI.BridgeAIDomain do
  @moduledoc """
  Bridge action connecting the AIAnalysisAgent with the AI domain.

  Provides seamless integration between autonomous agent operations
  and the existing AI domain resources.
  """

  use Jido.Action,
    name: "bridge_ai_domain",
    description: "Bridge AI agent operations with AI domain",
    schema: [
      operation: [type: :atom, required: true],
      params: [type: :map, default: %{}],
      actor: [type: :any, default: nil]
    ]

  alias RubberDuck.AI
  require Logger

  @impl true
  def run(%{operation: :list_analyses} = params, context) do
    filters = build_filters(params.params)
    actor = params.actor || context[:actor]

    case apply_filters(filters, actor) do
      {:ok, results} ->
        {:ok, %{
          analyses: results,
          count: length(results),
          filters_applied: filters
        }}
      error ->
        error
    end
  end

  def run(%{operation: :get_analysis} = params, context) do
    actor = params.actor || context[:actor]

    case AI.get_analysis_result(params.params.id, actor: actor) do
      {:ok, result} ->
        {:ok, %{
          analysis: result,
          enriched: enrich_analysis(result)
        }}
      error ->
        error
    end
  end

  def run(%{operation: :create_analysis} = params, context) do
    actor = params.actor || context[:actor]

    case AI.create_analysis_result(params.params, actor: actor) do
      {:ok, result} ->
        emit_analysis_created_signal(result)
        {:ok, %{
          analysis: result,
          created: true
        }}
      error ->
        error
    end
  end

  def run(%{operation: :update_analysis} = params, context) do
    actor = params.actor || context[:actor]

    with {:ok, analysis} <- AI.get_analysis_result(params.params.id, actor: actor),
         {:ok, updated} <- AI.update_analysis_result(analysis, params.params.updates, actor: actor) do
      {:ok, %{
        analysis: updated,
        changes: calculate_changes(analysis, updated)
      }}
    end
  end

  def run(%{operation: :list_prompts} = params, context) do
    actor = params.actor || context[:actor]

    prompts = case params.params do
      %{public: true} ->
        AI.list_public_prompts(actor: actor)
      %{category: category} ->
        AI.list_prompts_by_category(category, actor: actor)
      _ ->
        AI.list_prompts(actor: actor)
    end

    case prompts do
      {:ok, results} ->
        {:ok, %{
          prompts: results,
          count: length(results),
          categories: extract_categories(results)
        }}
      error ->
        error
    end
  end

  def run(%{operation: :aggregate_metrics} = params, _context) do
    with {:ok, analyses} <- gather_analyses_for_aggregation(params.params),
         metrics <- aggregate_analysis_metrics(analyses) do
      {:ok, metrics}
    end
  end

  def run(%{operation: :search_analyses} = params, context) do
    actor = params.actor || context[:actor]
    search_params = params.params

    with {:ok, all_analyses} <- AI.list_analysis_results(actor: actor),
         filtered <- search_analyses(all_analyses, search_params) do
      {:ok, %{
        results: filtered,
        count: length(filtered),
        search_criteria: search_params
      }}
    end
  end

  def run(%{operation: operation}, _context) do
    {:error, "Unknown operation: #{operation}"}
  end

  # Private helper functions

  defp build_filters(params) do
    filters = []

    filters = if params[:project_id] do
      [{:project_id, params.project_id} | filters]
    else
      filters
    end

    filters = if params[:analysis_type] do
      [{:analysis_type, params.analysis_type} | filters]
    else
      filters
    end

    filters = if params[:status] do
      [{:status, params.status} | filters]
    else
      filters
    end

    filters
  end

  defp apply_filters(filters, actor) do
    # Start with all analyses
    case AI.list_analysis_results(actor: actor) do
      {:ok, results} ->
        filtered = Enum.reduce(filters, results, &apply_single_filter/2)
        {:ok, filtered}
      error ->
        error
    end
  end

  defp apply_single_filter({key, value}, acc) do
    Enum.filter(acc, fn analysis ->
      Map.get(analysis, key) == value
    end)
  end

  defp enrich_analysis(analysis) do
    %{
      quality_rating: rate_analysis_quality(analysis),
      completeness: calculate_completeness(analysis),
      actionability: assess_actionability(analysis),
      age: calculate_age(analysis)
    }
  end

  defp rate_analysis_quality(analysis) do
    cond do
      analysis.score && analysis.score > 80 -> :excellent
      analysis.score && analysis.score > 60 -> :good
      analysis.score && analysis.score > 40 -> :fair
      analysis.score -> :poor
      true -> :unknown
    end
  end

  defp calculate_completeness(analysis) do
    required_fields = [:summary, :details, :score, :suggestions]
    present_fields = Enum.filter(required_fields, fn field ->
      value = Map.get(analysis, field)
      value != nil && value != "" && value != []
    end)

    (length(present_fields) / length(required_fields)) * 100
  end

  defp assess_actionability(analysis) do
    suggestions = analysis.suggestions || []

    cond do
      length(suggestions) >= 5 -> :high
      length(suggestions) >= 3 -> :medium
      length(suggestions) >= 1 -> :low
      true -> :none
    end
  end

  defp calculate_age(analysis) do
    if analysis.inserted_at do
      DateTime.diff(DateTime.utc_now(), analysis.inserted_at, :hour)
    else
      0
    end
  end

  defp calculate_changes(original, updated) do
    changes = []

    Enum.reduce([:summary, :score, :suggestions, :status], changes, fn field, acc ->
      if Map.get(original, field) != Map.get(updated, field) do
        [{field, %{from: Map.get(original, field), to: Map.get(updated, field)}} | acc]
      else
        acc
      end
    end)
  end

  defp extract_categories(prompts) do
    prompts
    |> Enum.map(& &1.category)
    |> Enum.uniq()
    |> Enum.filter(& &1)
  end

  defp gather_analyses_for_aggregation(params) do
    cond do
      params[:project_id] ->
        AI.list_analysis_results_by_project(params.project_id)
      params[:analysis_type] ->
        AI.list_analysis_results_by_type(params.analysis_type)
      true ->
        AI.list_completed_analysis_results()
    end
  end

  defp aggregate_analysis_metrics(analyses) do
    %{
      total_count: length(analyses),
      average_score: calculate_average_score(analyses),
      score_distribution: calculate_score_distribution(analyses),
      type_breakdown: calculate_type_breakdown(analyses),
      status_breakdown: calculate_status_breakdown(analyses),
      suggestion_frequency: analyze_suggestion_frequency(analyses),
      quality_trend: analyze_quality_trend(analyses)
    }
  end

  defp calculate_average_score(analyses) do
    scores = analyses
      |> Enum.map(& &1.score)
      |> Enum.filter(& &1)

    if length(scores) > 0 do
      Enum.sum(scores) / length(scores)
    else
      0
    end
  end

  defp calculate_score_distribution(analyses) do
    analyses
    |> Enum.map(& &1.score)
    |> Enum.filter(& &1)
    |> Enum.group_by(fn score ->
      cond do
        score >= 90 -> :excellent
        score >= 70 -> :good
        score >= 50 -> :fair
        score >= 30 -> :poor
        true -> :critical
      end
    end)
    |> Enum.map(fn {rating, scores} ->
      {rating, length(scores)}
    end)
    |> Map.new()
  end

  defp calculate_type_breakdown(analyses) do
    analyses
    |> Enum.group_by(& &1.analysis_type)
    |> Enum.map(fn {type, items} ->
      {type, %{
        count: length(items),
        percentage: (length(items) / length(analyses)) * 100,
        average_score: calculate_average_score(items)
      }}
    end)
    |> Map.new()
  end

  defp calculate_status_breakdown(analyses) do
    analyses
    |> Enum.group_by(& &1.status)
    |> Enum.map(fn {status, items} ->
      {status, length(items)}
    end)
    |> Map.new()
  end

  defp analyze_suggestion_frequency(analyses) do
    all_suggestions = analyses
      |> Enum.flat_map(& &1.suggestions || [])

    if length(all_suggestions) > 0 do
      # Categorize and count suggestions
      all_suggestions
      |> Enum.map(&categorize_suggestion/1)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_, count} -> count end, :desc)
      |> Enum.take(10)
    else
      []
    end
  end

  defp categorize_suggestion(suggestion) when is_binary(suggestion) do
    cond do
      String.contains?(suggestion, ["refactor", "simplify"]) -> :refactoring
      String.contains?(suggestion, ["document", "comment"]) -> :documentation
      String.contains?(suggestion, ["test", "coverage"]) -> :testing
      String.contains?(suggestion, ["performance", "optimize"]) -> :performance
      String.contains?(suggestion, ["security", "vulnerability"]) -> :security
      true -> :general
    end
  end
  defp categorize_suggestion(_), do: :general

  defp analyze_quality_trend(analyses) do
    # Sort by insertion date
    sorted = Enum.sort_by(analyses, & &1.inserted_at)

    if length(sorted) >= 2 do
      recent = Enum.take(sorted, -10)
      older = Enum.take(sorted, 10)

      recent_avg = calculate_average_score(recent)
      older_avg = calculate_average_score(older)

      cond do
        recent_avg > older_avg + 5 -> :improving
        recent_avg < older_avg - 5 -> :declining
        true -> :stable
      end
    else
      :insufficient_data
    end
  end

  defp search_analyses(analyses, search_params) do
    analyses
    |> filter_by_score_range(search_params[:min_score], search_params[:max_score])
    |> filter_by_date_range(search_params[:start_date], search_params[:end_date])
    |> filter_by_text_search(search_params[:query])
    |> filter_by_suggestions(search_params[:has_suggestions])
  end

  defp filter_by_score_range(analyses, nil, nil), do: analyses
  defp filter_by_score_range(analyses, min_score, max_score) do
    Enum.filter(analyses, fn analysis ->
      score = analysis.score || 0
      (min_score == nil or score >= min_score) and
      (max_score == nil or score <= max_score)
    end)
  end

  defp filter_by_date_range(analyses, nil, nil), do: analyses
  defp filter_by_date_range(analyses, start_date, end_date) do
    Enum.filter(analyses, fn analysis ->
      date = analysis.inserted_at
      (start_date == nil or DateTime.compare(date, start_date) != :lt) and
      (end_date == nil or DateTime.compare(date, end_date) != :gt)
    end)
  end

  defp filter_by_text_search(analyses, nil), do: analyses
  defp filter_by_text_search(analyses, query) do
    query_lower = String.downcase(query)

    Enum.filter(analyses, fn analysis ->
      summary = String.downcase(analysis.summary || "")
      suggestions = analysis.suggestions || []
      suggestions_text = suggestions |> Enum.join(" ") |> String.downcase()

      String.contains?(summary, query_lower) or
      String.contains?(suggestions_text, query_lower)
    end)
  end

  defp filter_by_suggestions(analyses, nil), do: analyses
  defp filter_by_suggestions(analyses, true) do
    Enum.filter(analyses, fn analysis ->
      suggestions = analysis.suggestions || []
      not Enum.empty?(suggestions)
    end)
  end
  defp filter_by_suggestions(analyses, false) do
    Enum.filter(analyses, fn analysis ->
      suggestions = analysis.suggestions || []
      Enum.empty?(suggestions)
    end)
  end

  defp emit_analysis_created_signal(analysis) do
    RubberDuck.Signal.emit("analysis.created", %{
      analysis_id: analysis.id,
      type: analysis.analysis_type,
      project_id: analysis.project_id,
      timestamp: DateTime.utc_now()
    })
  end
end
