defmodule RubberDuck.Actions.CodeFile.BridgeCodeDomain do
  @moduledoc """
  Action to bridge CodeFileAgent with the existing Ash-based CodeFile domain.
  """

  use Jido.Action,
    name: "bridge_code_domain",
    description: "Integrates CodeFileAgent with existing Projects domain",
    schema: [
      operation: [type: :atom, required: true, values: [:sync, :create, :update, :analyze, :list]],
      agent_state: [type: :map, required: true],
      domain_params: [type: :map, default: %{}]
    ]

  alias RubberDuck.Projects

  @impl true
  def run(params, _context) do
    case params.operation do
      :sync -> sync_with_domain(params)
      :create -> create_in_domain(params)
      :update -> update_in_domain(params)
      :analyze -> analyze_from_domain(params)
      :list -> list_from_domain(params)
    end
  end

  defp sync_with_domain(params) do
    agent_state = params.agent_state

    with {:ok, code_file} <- get_or_create_code_file(agent_state),
         {:ok, updated_file} <- sync_agent_to_domain(code_file, agent_state),
         {:ok, synced_state} <- sync_domain_to_agent(updated_file, agent_state) do

      {:ok, %{
        code_file: updated_file,
        agent_state: synced_state,
        sync_status: :completed,
        synced_at: DateTime.utc_now()
      }}
    end
  end

  defp create_in_domain(params) do
    agent_state = params.agent_state

    with {:ok, validated} <- validate_create_params(agent_state),
         {:ok, code_file} <- create_code_file(validated),
         {:ok, analysis_result} <- create_initial_analysis(code_file, agent_state) do

      {:ok, %{
        code_file: code_file,
        analysis_result: analysis_result,
        created: true,
        file_id: code_file.id
      }}
    end
  end

  defp update_in_domain(params) do
    agent_state = params.agent_state

    with {:ok, code_file} <- get_code_file(agent_state.file_id),
         {:ok, changes} <- prepare_update_changes(code_file, agent_state),
         {:ok, updated_file} <- apply_domain_update(code_file, changes),
         {:ok, _} <- trigger_dependent_updates(updated_file, agent_state) do

      {:ok, %{
        code_file: updated_file,
        changes_applied: changes,
        updated: true,
        updated_at: DateTime.utc_now()
      }}
    end
  end

  defp analyze_from_domain(params) do
    domain_params = params.domain_params

    with {:ok, code_files} <- fetch_code_files_for_analysis(domain_params),
         {:ok, aggregated} <- aggregate_code_metrics(code_files),
         {:ok, insights} <- generate_project_insights(aggregated),
         {:ok, recommendations} <- generate_project_recommendations(aggregated, insights) do

      {:ok, %{
        files_analyzed: length(code_files),
        aggregated_metrics: aggregated,
        project_insights: insights,
        recommendations: recommendations
      }}
    end
  end

  defp list_from_domain(params) do
    filters = params.domain_params[:filters] || %{}

    with {:ok, code_files} <- list_code_files(filters),
         {:ok, enriched} <- enrich_with_agent_data(code_files) do

      {:ok, %{
        code_files: enriched,
        total_count: length(enriched),
        filters_applied: filters
      }}
    end
  end

  # Sync helper functions

  defp get_or_create_code_file(agent_state) do
    if agent_state.file_id do
      get_code_file(agent_state.file_id)
    else
      create_code_file_from_agent(agent_state)
    end
  end

  defp get_code_file(file_id) do
    case Projects.get_code_file(file_id) do
      {:ok, file} -> {:ok, file}
      {:error, :not_found} -> {:error, :code_file_not_found}
      error -> error
    end
  end

  defp create_code_file_from_agent(agent_state) do
    params = %{
      path: agent_state.file_path,
      content: agent_state.current_content,
      language: agent_state.language || detect_language(agent_state.file_path),
      size_bytes: byte_size(agent_state.current_content || ""),
      project_id: agent_state.project_id
    }

    Projects.create_code_file(params)
  end

  defp sync_agent_to_domain(code_file, agent_state) do
    updates = %{}

    # Update content if changed
    updates = if agent_state.current_content != code_file.content do
      Map.put(updates, :content, agent_state.current_content)
    else
      updates
    end

    # Update status based on agent analysis
    updates = if agent_state.issues && length(agent_state.issues) > 0 do
      Map.put(updates, :status, :modified)
    else
      updates
    end

    if map_size(updates) > 0 do
      Projects.update_code_file(code_file.id, updates)
    else
      {:ok, code_file}
    end
  end

  defp sync_domain_to_agent(code_file, agent_state) do
    updated_state = agent_state
      |> Map.put(:file_id, code_file.id)
      |> Map.put(:file_path, code_file.path)
      |> Map.put(:project_id, code_file.project_id)
      |> Map.put(:size_bytes, code_file.size_bytes)
      |> Map.put(:last_synced_at, DateTime.utc_now())

    # Sync analysis results if available
    updated_state = if code_file.analysis_results do
      merge_analysis_results(updated_state, code_file.analysis_results)
    else
      updated_state
    end

    {:ok, updated_state}
  end

  # Create helper functions

  defp validate_create_params(agent_state) do
    required = [:file_path, :current_content, :project_id]

    if Enum.all?(required, fn key -> Map.has_key?(agent_state, key) end) do
      {:ok, agent_state}
    else
      {:error, :missing_required_params}
    end
  end

  defp create_code_file(validated) do
    params = %{
      path: validated.file_path,
      content: validated.current_content,
      language: validated.language || detect_language(validated.file_path),
      size_bytes: byte_size(validated.current_content),
      project_id: validated.project_id,
      status: :active
    }

    Projects.create_code_file(params)
  end

  defp create_initial_analysis(code_file, agent_state) do
    if agent_state.quality_score do
      analysis_params = %{
        code_file_id: code_file.id,
        analysis_type: "quality",
        result: %{
          quality_score: agent_state.quality_score,
          complexity_score: agent_state.complexity_score,
          issues: agent_state.issues || [],
          suggestions: agent_state.suggestions || []
        },
        status: "completed"
      }

      # Would create analysis result in AI domain
      {:ok, analysis_params}
    else
      {:ok, nil}
    end
  end

  # Update helper functions

  defp prepare_update_changes(code_file, agent_state) do
    changes = %{}

    # Check for content changes
    changes = if agent_state.current_content && agent_state.current_content != code_file.content do
      Map.put(changes, :content, agent_state.current_content)
    else
      changes
    end

    # Check for path changes
    changes = if agent_state.file_path && agent_state.file_path != code_file.path do
      Map.put(changes, :path, agent_state.file_path)
    else
      changes
    end

    # Update size if content changed
    changes = if changes[:content] do
      Map.put(changes, :size_bytes, byte_size(changes.content))
    else
      changes
    end

    # Update status based on agent analysis
    changes = if should_update_status?(agent_state) do
      Map.put(changes, :status, determine_status(agent_state))
    else
      changes
    end

    {:ok, changes}
  end

  defp apply_domain_update(code_file, changes) do
    if map_size(changes) > 0 do
      Projects.update_code_file(code_file.id, changes)
    else
      {:ok, code_file}
    end
  end

  defp trigger_dependent_updates(code_file, agent_state) do
    # Notify dependent files if there are breaking changes
    if agent_state.dependents && length(agent_state.dependents) > 0 do
      Enum.each(agent_state.dependents, fn dependent ->
        emit_update_signal(dependent, code_file)
      end)
    end

    {:ok, :triggered}
  end

  # Analyze helper functions

  defp fetch_code_files_for_analysis(params) do
    project_id = params[:project_id]

    if project_id do
      Projects.list_code_files_by_project(project_id)
    else
      {:ok, []}
    end
  end

  defp aggregate_code_metrics(code_files) do
    metrics = %{
      total_files: length(code_files),
      total_lines: calculate_total_lines(code_files),
      average_file_size: calculate_average_size(code_files),
      languages: group_by_language(code_files),
      status_distribution: group_by_status(code_files)
    }

    {:ok, metrics}
  end

  defp generate_project_insights(aggregated) do
    insights = []

    # Large project insight
    insights = if aggregated.total_files > 100 do
      [%{
        type: :scale,
        message: "Large project with #{aggregated.total_files} files",
        recommendation: "Consider modularization"
      } | insights]
    else
      insights
    end

    # Language diversity insight
    insights = if map_size(aggregated.languages) > 3 do
      [%{
        type: :diversity,
        message: "Multi-language project detected",
        recommendation: "Ensure consistent tooling across languages"
      } | insights]
    else
      insights
    end

    {:ok, insights}
  end

  defp generate_project_recommendations(aggregated, _insights) do
    recommendations = []

    # Size-based recommendations
    recommendations = if aggregated.average_file_size > 500 do
      ["Consider splitting large files" | recommendations]
    else
      recommendations
    end

    # Status-based recommendations
    recommendations = if aggregated.status_distribution[:modified] > aggregated.total_files * 0.5 do
      ["Many modified files - consider committing changes" | recommendations]
    else
      recommendations
    end

    {:ok, recommendations}
  end

  # List helper functions

  defp list_code_files(filters) do
    base_query = if filters[:project_id] do
      {:ok, files} = Projects.list_code_files_by_project(filters.project_id)
      files
    else
      []
    end

    filtered = apply_filters(base_query, filters)
    {:ok, filtered}
  end

  defp apply_filters(files, filters) do
    files
    |> filter_by_language(filters[:language])
    |> filter_by_status(filters[:status])
    |> filter_by_path_pattern(filters[:path_pattern])
  end

  defp filter_by_language(files, nil), do: files
  defp filter_by_language(files, language) do
    Enum.filter(files, fn file -> file.language == language end)
  end

  defp filter_by_status(files, nil), do: files
  defp filter_by_status(files, status) do
    Enum.filter(files, fn file -> file.status == status end)
  end

  defp filter_by_path_pattern(files, nil), do: files
  defp filter_by_path_pattern(files, pattern) do
    Enum.filter(files, fn file -> String.contains?(file.path, pattern) end)
  end

  defp enrich_with_agent_data(code_files) do
    enriched = Enum.map(code_files, fn file ->
      agent_data = fetch_agent_data_for_file(file.id)

      Map.merge(file, %{
        agent_analysis: agent_data[:analysis],
        quality_score: agent_data[:quality_score],
        last_analyzed: agent_data[:last_analyzed]
      })
    end)

    {:ok, enriched}
  end

  defp fetch_agent_data_for_file(_file_id) do
    # Would fetch from agent state storage
    %{
      analysis: nil,
      quality_score: 0.0,
      last_analyzed: nil
    }
  end

  # Utility functions

  defp detect_language(file_path) do
    ext = Path.extname(file_path)

    language_map = %{
      ".ex" => "elixir",
      ".exs" => "elixir",
      ".js" => "javascript",
      ".ts" => "typescript",
      ".py" => "python",
      ".rb" => "ruby",
      ".go" => "go",
      ".rs" => "rust"
    }

    Map.get(language_map, ext, "unknown")
  end

  defp merge_analysis_results(agent_state, analysis_results) do
    latest_result = List.first(analysis_results)

    if latest_result && latest_result.result do
      agent_state
      |> Map.put(:domain_quality_score, latest_result.result[:quality_score])
      |> Map.put(:domain_analysis_date, latest_result.inserted_at)
    else
      agent_state
    end
  end

  defp should_update_status?(agent_state) do
    agent_state.issues && length(agent_state.issues) > 0
  end

  defp determine_status(agent_state) do
    cond do
      agent_state.issues && length(agent_state.issues) > 5 -> :modified
      agent_state.quality_score && agent_state.quality_score < 0.5 -> :modified
      true -> :active
    end
  end

  defp emit_update_signal(dependent, code_file) do
    RubberDuck.Signal.emit("code_file.dependency_updated", %{
      dependent_file: dependent.file_path,
      updated_file: code_file.path,
      update_type: :dependency_change
    })
  end

  defp calculate_total_lines(code_files) do
    Enum.reduce(code_files, 0, fn file, acc ->
      if file.content do
        acc + length(String.split(file.content, "\n"))
      else
        acc
      end
    end)
  end

  defp calculate_average_size(code_files) do
    if length(code_files) > 0 do
      total = Enum.reduce(code_files, 0, fn file, acc ->
        acc + (file.size_bytes || 0)
      end)

      total / length(code_files)
    else
      0
    end
  end

  defp group_by_language(code_files) do
    code_files
    |> Enum.group_by(& &1.language)
    |> Enum.map(fn {lang, files} -> {lang, length(files)} end)
    |> Enum.into(%{})
  end

  defp group_by_status(code_files) do
    code_files
    |> Enum.group_by(& &1.status)
    |> Enum.map(fn {status, files} -> {status, length(files)} end)
    |> Enum.into(%{})
  end
end
