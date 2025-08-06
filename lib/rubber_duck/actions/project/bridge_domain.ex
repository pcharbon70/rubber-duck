defmodule RubberDuck.Actions.Project.BridgeDomain do
  @moduledoc """
  Action to bridge ProjectAgent with the existing RubberDuck.Projects domain.
  Provides integration between the autonomous agent and the Ash-based project management.
  """

  use Jido.Action,
    name: "bridge_domain",
    description: "Bridges agent actions with the Projects domain",
    schema: [
      operation: [
        type: :atom,
        required: true,
        values: [:sync, :create, :update, :analyze, :report]
      ],
      project_id: [type: :string, required: false],
      agent_data: [type: :map, required: true],
      options: [type: :map, default: %{}]
    ]

  alias RubberDuck.Projects
  require Logger

  @impl true
  def run(params, _context) do
    case params.operation do
      :sync -> sync_agent_with_domain(params)
      :create -> create_from_agent_data(params)
      :update -> update_from_agent_data(params)
      :analyze -> analyze_and_update(params)
      :report -> generate_domain_report(params)
    end
  end

  defp sync_agent_with_domain(params) do
    agent_state = params.agent_data

    # Sync monitored projects
    {:ok, projects} = Projects.list_projects()

    synced_projects =
      Enum.map(projects, fn project ->
        agent_project_state = Map.get(agent_state.monitored_projects, project.id, %{})

        sync_result = sync_single_project(project, agent_project_state, agent_state)

        %{
          project_id: project.id,
          synced: true,
          updates: sync_result
        }
      end)

    # Find projects in agent but not in domain
    agent_only_projects =
      agent_state.monitored_projects
      |> Map.keys()
      |> Enum.reject(fn id ->
        Enum.any?(projects, &(&1.id == id))
      end)

    {:ok,
     %{
       synced_projects: synced_projects,
       agent_only_projects: agent_only_projects,
       domain_project_count: length(projects),
       agent_project_count: map_size(agent_state.monitored_projects),
       sync_completed_at: DateTime.utc_now()
     }}
  end

  defp sync_single_project(project, agent_state, full_agent_state) do
    updates = []

    # Sync quality metrics
    quality_metrics = Map.get(full_agent_state.quality_metrics, project.id, %{})

    updates =
      if map_size(quality_metrics) > 0 do
        [{:quality_metrics, store_quality_metrics(project, quality_metrics)} | updates]
      else
        updates
      end

    # Sync dependency information
    dependencies = Map.get(full_agent_state.dependency_graph, project.id, %{})

    updates =
      if map_size(dependencies) > 0 do
        [{:dependencies, store_dependencies(project, dependencies)} | updates]
      else
        updates
      end

    # Sync optimization suggestions
    optimizations = Map.get(full_agent_state.structure_optimizations, project.id, [])

    updates =
      if length(optimizations) > 0 do
        [{:optimizations, store_optimizations(project, optimizations)} | updates]
      else
        updates
      end

    # Update project status if needed
    updates =
      if should_update_project_status?(project, agent_state, quality_metrics) do
        [{:status, update_project_status(project, agent_state)} | updates]
      else
        updates
      end

    updates
  end

  defp store_quality_metrics(project, metrics) do
    # Store as project metadata or in a separate metrics resource
    metadata = %{
      quality_score: metrics[:quality_score],
      complexity: metrics[:average_complexity],
      test_coverage: metrics[:test_coverage],
      last_analyzed: DateTime.utc_now()
    }

    case Projects.update_project(project, %{metadata: metadata}) do
      {:ok, _} -> {:stored, metadata}
      error -> {:error, error}
    end
  end

  defp store_dependencies(_project, dependencies) do
    # Could create a separate Dependencies resource in the future
    # For now, store summary in project metadata
    dep_summary = %{
      total_dependencies: map_size(dependencies),
      dependency_types: count_dependency_types(dependencies),
      last_scanned: DateTime.utc_now()
    }

    {:stored, dep_summary}
  end

  defp count_dependency_types(dependencies) do
    dependencies
    |> Map.values()
    |> Enum.flat_map(&(&1[:dependencies] || []))
    |> Enum.group_by(& &1[:type])
    |> Map.keys()
  end

  defp store_optimizations(project, optimizations) do
    # Could create an Optimizations resource
    # For now, log optimization suggestions (converted from legacy signal system)
    Enum.each(optimizations, fn _opt ->
      Logger.debug("Legacy signal: project.optimization.suggested for project #{project.id}")
      # Note: Converted from legacy signal system - optimization events now handled via MessageRouter
    end)

    {:stored, length(optimizations)}
  end

  defp should_update_project_status?(project, agent_state, quality_metrics) do
    # Determine if project status should change based on metrics
    quality_score = quality_metrics[:quality_score] || 100

    cond do
      quality_score < 50 && project.status != :needs_attention -> true
      quality_score > 80 && project.status == :needs_attention -> true
      agent_state[:monitoring_started_at] && project.status == :inactive -> true
      true -> false
    end
  end

  defp update_project_status(project, agent_state) do
    new_status = determine_new_status(project, agent_state)

    case Projects.update_project(project, %{status: new_status}) do
      {:ok, _updated} -> {:updated, new_status}
      error -> {:error, error}
    end
  end

  defp determine_new_status(project, _agent_state) do
    # Logic to determine appropriate status
    cond do
      project.status == :inactive -> :active
      project.status == :needs_attention -> :active
      true -> project.status
    end
  end

  defp create_from_agent_data(params) do
    agent_data = params.agent_data

    project_attrs = %{
      name: agent_data.name || "New Project",
      description: agent_data.description,
      language: agent_data.language || detect_language(agent_data),
      status: :active,
      metadata: build_project_metadata(agent_data)
    }

    case Projects.create_project(project_attrs) do
      {:ok, project} ->
        # Create associated code files if provided
        if agent_data[:files] do
          create_code_files(project, agent_data.files)
        end

        # Log project creation (converted from legacy signal system)
        Logger.debug("Legacy signal: project.created for project #{project.id}")
        # Note: Converted from legacy signal system - project events now handled via MessageRouter

        {:ok,
         %{
           project: project,
           created: true,
           monitoring_initiated: true
         }}

      error ->
        error
    end
  end

  defp detect_language(agent_data) do
    # Simple language detection based on file extensions
    files = agent_data[:files] || []

    extensions =
      files
      |> Enum.map(&Path.extname(&1[:path] || ""))
      |> Enum.frequencies()

    detect_by_extension(extensions)
  end

  defp detect_by_extension(extensions) do
    language_map = %{
      {[".ex", ".exs"], "elixir"},
      {[".js", ".ts"], "javascript"},
      {[".py"], "python"},
      {[".rb"], "ruby"},
      {[".go"], "go"}
    }

    Enum.find_value(language_map, "unknown", fn {exts, lang} ->
      if Enum.any?(exts, &extensions[&1]), do: lang
    end)
  end

  defp build_project_metadata(agent_data) do
    %{
      created_by_agent: true,
      agent_version: agent_data[:agent_version],
      initial_metrics: agent_data[:metrics],
      created_at: DateTime.utc_now()
    }
  end

  defp create_code_files(project, files) do
    Enum.map(files, fn file_data ->
      attrs = %{
        project_id: project.id,
        path: file_data.path,
        content: file_data.content,
        language: file_data.language || project.language,
        size_bytes: byte_size(file_data.content || ""),
        status: :active
      }

      Projects.create_code_file(attrs)
    end)
  end

  defp update_from_agent_data(params) do
    project_id = params.project_id
    agent_data = params.agent_data

    with {:ok, project} <- Projects.get_project(project_id) do
      updates = build_updates_from_agent_data(project, agent_data)

      results =
        Enum.map(updates, fn {field, value} ->
          case update_project_field(project, field, value) do
            {:ok, _} -> {field, :updated}
            error -> {field, error}
          end
        end)

      {:ok,
       %{
         project_id: project_id,
         updates: Map.new(results),
         success: Enum.all?(results, fn {_, result} -> result == :updated end)
       }}
    end
  end

  defp build_updates_from_agent_data(project, agent_data) do
    updates = []

    # Update quality metrics
    updates =
      if agent_data[:quality_metrics] do
        [{:quality_metrics, agent_data.quality_metrics} | updates]
      else
        updates
      end

    # Update project metadata
    updates =
      if agent_data[:metadata] do
        current_metadata = project.metadata || %{}
        merged_metadata = Map.merge(current_metadata, agent_data.metadata)
        [{:metadata, merged_metadata} | updates]
      else
        updates
      end

    # Update status based on agent analysis
    updates =
      if agent_data[:suggested_status] && agent_data.suggested_status != project.status do
        [{:status, agent_data.suggested_status} | updates]
      else
        updates
      end

    updates
  end

  defp update_project_field(project, :quality_metrics, metrics) do
    metadata =
      Map.merge(project.metadata || %{}, %{
        quality_metrics: metrics,
        metrics_updated_at: DateTime.utc_now()
      })

    Projects.update_project(project, %{metadata: metadata})
  end

  defp update_project_field(project, field, value) do
    Projects.update_project(project, %{field => value})
  end

  defp analyze_and_update(params) do
    project_id = params.project_id
    analysis_type = params.agent_data[:analysis_type] || :full

    with {:ok, project} <- Projects.get_project(project_id),
         {:ok, files} <- Projects.list_code_files_by_project(project_id),
         analysis <- perform_analysis(project, files, analysis_type),
         {:ok, _} <- store_analysis_results(project, analysis) do
      # Emit signals for significant findings
      emit_analysis_signals(project, analysis)

      {:ok,
       %{
         project_id: project_id,
         analysis_type: analysis_type,
         findings: summarize_findings(analysis),
         recommendations: generate_recommendations(analysis),
         analyzed_at: DateTime.utc_now()
       }}
    end
  end

  defp perform_analysis(project, files, :full) do
    %{
      structure: analyze_project_structure(files),
      quality: analyze_code_quality(files),
      dependencies: analyze_dependencies(project, files),
      patterns: detect_patterns(files),
      issues: find_issues(files)
    }
  end

  defp perform_analysis(_project, files, :quality) do
    %{
      quality: analyze_code_quality(files),
      issues: find_issues(files)
    }
  end

  defp perform_analysis(_project, files, :structure) do
    %{
      structure: analyze_project_structure(files),
      patterns: detect_patterns(files)
    }
  end

  defp analyze_project_structure(files) do
    %{
      total_files: length(files),
      directory_structure: build_directory_tree(files),
      file_distribution: group_files_by_type(files),
      naming_consistency: check_naming_consistency(files)
    }
  end

  defp build_directory_tree(files) do
    files
    |> Enum.map(& &1.path)
    |> Enum.map(&Path.dirname/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp group_files_by_type(files) do
    files
    |> Enum.group_by(&Path.extname(&1.path))
    |> Enum.map(fn {ext, group} -> {ext, length(group)} end)
    |> Map.new()
  end

  defp check_naming_consistency(files) do
    # Simple check for consistent naming patterns
    naming_styles =
      files
      |> Enum.map(&Path.basename(&1.path, Path.extname(&1.path)))
      |> Enum.map(&categorize_naming_style/1)
      |> Enum.frequencies()

    %{
      styles: naming_styles,
      consistent: map_size(naming_styles) <= 2
    }
  end

  defp categorize_naming_style(name) do
    cond do
      name =~ ~r/^[a-z]+(_[a-z]+)*$/ -> :snake_case
      name =~ ~r/^[a-z]+([A-Z][a-z]+)*$/ -> :camelCase
      name =~ ~r/^[A-Z][a-z]+([A-Z][a-z]+)*$/ -> :PascalCase
      true -> :mixed
    end
  end

  defp analyze_code_quality(files) do
    elixir_files = Enum.filter(files, &(&1.language == "elixir"))

    %{
      total_lines: sum_lines(elixir_files),
      average_file_size: average_file_size(elixir_files),
      complexity_estimate: estimate_complexity(elixir_files)
    }
  end

  defp sum_lines(files) do
    files
    |> Enum.map(fn file ->
      if file.content do
        length(String.split(file.content, "\n"))
      else
        0
      end
    end)
    |> Enum.sum()
  end

  defp average_file_size(files) do
    if length(files) > 0 do
      total_size = Enum.sum(Enum.map(files, &(&1.size_bytes || 0)))
      div(total_size, length(files))
    else
      0
    end
  end

  defp estimate_complexity(files) do
    # Simple complexity estimation
    total_functions =
      files
      |> Enum.map(fn file ->
        if file.content do
          length(Regex.scan(~r/def(?:p?)\s+\w+/, file.content))
        else
          0
        end
      end)
      |> Enum.sum()

    %{
      total_functions: total_functions,
      functions_per_file:
        if length(files) > 0 do
          total_functions / length(files)
        else
          0
        end
    }
  end

  defp analyze_dependencies(project, _files) do
    # This would integrate with dependency detection
    %{
      language: project.language,
      package_manager: detect_package_manager(project.language)
    }
  end

  defp detect_package_manager("elixir"), do: "mix"
  defp detect_package_manager("javascript"), do: "npm"
  defp detect_package_manager("python"), do: "pip"
  defp detect_package_manager(_), do: "unknown"

  defp detect_patterns(files) do
    %{
      common_imports: find_common_imports(files),
      file_patterns: detect_file_patterns(files)
    }
  end

  defp find_common_imports(files) do
    files
    |> Enum.flat_map(&extract_file_imports/1)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_, count} -> -count end)
    |> Enum.take(10)
  end

  defp extract_file_imports(file) do
    if file.content && file.language == "elixir" do
      extract_module_references(file.content)
    else
      []
    end
  end

  defp extract_module_references(content) do
    content
    |> then(&Regex.scan(~r/(?:import|alias|use)\s+([\w\.]+)/, &1))
    |> Enum.map(fn [_, module] -> module end)
  end

  defp detect_file_patterns(files) do
    # Detect common file naming patterns
    files
    |> Enum.map(&Path.basename(&1.path))
    |> Enum.map(&extract_pattern/1)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_, count} -> -count end)
    |> Enum.take(5)
  end

  defp extract_pattern(filename) do
    cond do
      filename =~ ~r/_test\./ -> "test_file"
      filename =~ ~r/_spec\./ -> "spec_file"
      filename =~ ~r/^test_/ -> "test_file"
      filename =~ ~r/controller/ -> "controller"
      filename =~ ~r/view/ -> "view"
      filename =~ ~r/schema/ -> "schema"
      true -> "other"
    end
  end

  defp find_issues(files) do
    files
    |> Enum.flat_map(&find_file_issues/1)
    |> Enum.take(20)
  end

  defp find_file_issues(file) do
    issues = []

    issues =
      if file.size_bytes && file.size_bytes > 50_000 do
        [
          %{
            type: :large_file,
            file: file.path,
            size: file.size_bytes,
            severity: :medium
          }
          | issues
        ]
      else
        issues
      end

    issues =
      if file.content && String.contains?(file.content, "TODO") do
        todos = length(Regex.scan(~r/TODO/, file.content))

        [
          %{
            type: :todos,
            file: file.path,
            count: todos,
            severity: :low
          }
          | issues
        ]
      else
        issues
      end

    issues
  end

  defp store_analysis_results(project, analysis) do
    metadata =
      Map.merge(project.metadata || %{}, %{
        last_analysis: analysis,
        analysis_timestamp: DateTime.utc_now()
      })

    Projects.update_project(project, %{metadata: metadata})
  end

  defp emit_analysis_signals(project, analysis) do
    # Log significant findings (converted from legacy signal system)
    if length(analysis[:issues] || []) > 10 do
      Logger.debug("Legacy signal: project.issues.detected for project #{project.id}")
      # Note: Converted from legacy signal system - issue events now handled via MessageRouter
    end

    if get_in(analysis, [:structure, :naming_consistency, :consistent]) == false do
      Logger.debug("Legacy signal: project.inconsistency.detected for project #{project.id}")
      # Note: Converted from legacy signal system - consistency events now handled via MessageRouter
    end
  end

  defp summarize_findings(analysis) do
    %{
      structure: %{
        total_files: Kernel.get_in(analysis, [:structure, :total_files]) || 0,
        consistent_naming:
          Kernel.get_in(analysis, [:structure, :naming_consistency, :consistent]) || true
      },
      quality: %{
        total_lines: Kernel.get_in(analysis, [:quality, :total_lines]) || 0,
        complexity: Kernel.get_in(analysis, [:quality, :complexity_estimate]) || %{}
      },
      issues: %{
        total: length(analysis[:issues] || []),
        by_type: Enum.frequencies_by(analysis[:issues] || [], & &1.type)
      }
    }
  end

  defp generate_recommendations(analysis) do
    recs = []

    # Structure recommendations
    recs =
      if get_in(analysis, [:structure, :naming_consistency, :consistent]) == false do
        ["Standardize file naming conventions across the project" | recs]
      else
        recs
      end

    # Quality recommendations
    recs =
      if (Kernel.get_in(analysis, [:quality, :complexity_estimate, :functions_per_file]) || 0) >
           20 do
        ["Consider breaking up large modules into smaller, focused ones" | recs]
      else
        recs
      end

    # Issue recommendations
    issue_count = length(analysis[:issues] || [])

    recs =
      if issue_count > 20 do
        ["Address #{issue_count} identified issues to improve code quality" | recs]
      else
        recs
      end

    recs
  end

  defp generate_domain_report(params) do
    report_type = params.agent_data[:report_type] || :summary

    with {:ok, projects} <- Projects.list_projects() do
      report =
        case report_type do
          :summary -> generate_summary_report(projects, params.agent_data)
          :detailed -> generate_detailed_report(projects, params.agent_data)
          :metrics -> generate_metrics_report(projects, params.agent_data)
        end

      {:ok, report}
    end
  end

  defp generate_summary_report(projects, agent_data) do
    monitored_projects = Map.keys(agent_data[:monitored_projects] || %{})

    %{
      report_type: :summary,
      total_projects: length(projects),
      monitored_by_agent: length(monitored_projects),
      active_projects: Enum.count(projects, &(&1.status == :active)),
      projects_needing_attention: find_projects_needing_attention(projects, agent_data),
      generated_at: DateTime.utc_now()
    }
  end

  defp generate_detailed_report(projects, agent_data) do
    project_details =
      Enum.map(projects, fn project ->
        agent_state = Kernel.get_in(agent_data, [:monitored_projects, project.id]) || %{}
        metrics = Kernel.get_in(agent_data, [:quality_metrics, project.id]) || %{}

        %{
          project: %{
            id: project.id,
            name: project.name,
            status: project.status
          },
          agent_monitoring: map_size(agent_state) > 0,
          quality_score: metrics[:quality_score],
          last_analysis: agent_state[:last_analysis],
          pending_optimizations:
            length(Kernel.get_in(agent_data, [:structure_optimizations, project.id]) || [])
        }
      end)

    %{
      report_type: :detailed,
      projects: project_details,
      generated_at: DateTime.utc_now()
    }
  end

  defp generate_metrics_report(projects, agent_data) do
    aggregate_metrics =
      projects
      |> Enum.map(fn project ->
        Kernel.get_in(agent_data, [:quality_metrics, project.id]) || %{}
      end)
      |> aggregate_quality_metrics()

    %{
      report_type: :metrics,
      aggregate_metrics: aggregate_metrics,
      project_count: length(projects),
      metrics_available_for:
        Enum.count(projects, fn p ->
          map_size(Kernel.get_in(agent_data, [:quality_metrics, p.id]) || %{}) > 0
        end),
      generated_at: DateTime.utc_now()
    }
  end

  defp find_projects_needing_attention(projects, agent_data) do
    projects
    |> Enum.filter(fn project ->
      quality_score =
        Kernel.get_in(agent_data, [:quality_metrics, project.id, :quality_score]) || 100

      quality_score < 70 || project.status == :needs_attention
    end)
    |> Enum.map(& &1.id)
  end

  defp aggregate_quality_metrics(metrics_list) do
    non_empty = Enum.filter(metrics_list, &(map_size(&1) > 0))

    if length(non_empty) > 0 do
      %{
        average_quality_score: average_metric(non_empty, :quality_score),
        average_complexity: average_metric(non_empty, :average_complexity),
        average_test_coverage: average_metric(non_empty, :test_coverage)
      }
    else
      %{}
    end
  end

  defp average_metric(metrics_list, key) do
    values =
      metrics_list
      |> Enum.map(&Map.get(&1, key))
      |> Enum.filter(& &1)

    if length(values) > 0 do
      Enum.sum(values) / length(values)
    else
      nil
    end
  end
end
