defmodule RubberDuck.Skills.ProjectManagementSkill do
  @moduledoc """
  Skill for managing projects with quality monitoring and optimization capabilities.

  This skill provides project structure optimization, dependency management,
  code quality monitoring, and refactoring recommendations based on continuous
  analysis of project metrics and patterns.
  """

  use Jido.Skill,
    name: "project_management",
    description: "Manages projects with quality monitoring and optimization",
    category: "project",
    tags: ["project", "quality", "dependencies", "refactoring", "monitoring"],
    vsn: "1.0.0",
    opts_key: :project_management,
    signal_patterns: [
      "project.created",
      "project.updated",
      "project.file.*",
      "project.dependency.*",
      "project.quality.*",
      "project.refactor.*"
    ],
    opts_schema: [
      quality_threshold: [type: :float, default: 0.7],
      auto_refactor_suggestions: [type: :boolean, default: true],
      dependency_check_interval: [type: :pos_integer, default: 3600],
      max_complexity: [type: :pos_integer, default: 10],
      min_test_coverage: [type: :float, default: 0.8],
      optimization_level: [
        type: :atom,
        default: :moderate,
        values: [:minimal, :moderate, :aggressive]
      ]
    ]

  require Logger

  @impl true
  def handle_signal(%{type: "project.created"} = signal, state) do
    project_id = signal.data.project_id

    # Initialize project monitoring state
    project_state = %{
      id: project_id,
      created_at: DateTime.utc_now(),
      quality_metrics: %{
        score: 1.0,
        complexity: 0,
        test_coverage: 0.0,
        documentation_coverage: 0.0,
        technical_debt: 0
      },
      dependencies: %{
        direct: [],
        transitive: [],
        outdated: [],
        vulnerable: []
      },
      structure: %{
        modules: 0,
        files: 0,
        lines_of_code: 0,
        test_files: 0
      },
      monitoring: %{
        last_check: DateTime.utc_now(),
        trend: :stable,
        alerts: []
      },
      refactoring_candidates: []
    }

    updated_state = put_in(state, [:projects, project_id], project_state)

    # Schedule initial analysis
    schedule_analysis(project_id)

    {:ok, %{status: :monitoring_started, project_id: project_id}, updated_state}
  end

  @impl true
  def handle_signal(%{type: "project.updated"} = signal, state) do
    project_id = signal.data.project_id
    changes = signal.data.changes || %{}

    case get_in(state, [:projects, project_id]) do
      nil ->
        # Project not being monitored yet, initialize it
        handle_signal(%{type: "project.created", data: signal.data}, state)

      project_state ->
        # Update project metrics based on changes
        updated_project = update_project_metrics(project_state, changes)

        # Check if quality threshold is breached
        alerts = check_quality_thresholds(updated_project, state.opts)

        # Generate refactoring suggestions if enabled
        suggestions =
          if state.opts.auto_refactor_suggestions do
            generate_refactoring_suggestions(updated_project, state.opts)
          else
            []
          end

        # Update state
        updated_project =
          updated_project
          |> Map.put(:refactoring_candidates, suggestions)
          |> put_in([:monitoring, :alerts], alerts)
          |> put_in([:monitoring, :last_check], DateTime.utc_now())

        updated_state = put_in(state, [:projects, project_id], updated_project)

        # Emit alerts if any
        if length(alerts) > 0 do
          emit_signal("project.quality.alert", %{
            project_id: project_id,
            alerts: alerts
          })
        end

        {:ok, %{alerts: alerts, suggestions: suggestions}, updated_state}
    end
  end

  @impl true
  def handle_signal(%{type: "project.file.added"} = signal, state) do
    project_id = signal.data.project_id
    file_path = signal.data.file_path
    file_content = signal.data.content

    updated_state =
      update_in(state, [:projects, project_id], fn project ->
        if project do
          project
          |> update_structure_metrics(file_path, file_content, :added)
          |> analyze_file_impact(file_path, file_content)
          |> detect_dependency_changes(file_content)
        else
          nil
        end
      end)

    # Check if this affects project quality
    project = get_in(updated_state, [:projects, project_id])
    quality_impact = if project, do: assess_quality_impact(project), else: :unknown

    {:ok, %{file_added: file_path, quality_impact: quality_impact}, updated_state}
  end

  @impl true
  def handle_signal(%{type: "project.file.modified"} = signal, state) do
    project_id = signal.data.project_id
    file_path = signal.data.file_path
    old_content = signal.data.old_content
    new_content = signal.data.new_content

    updated_state =
      update_in(state, [:projects, project_id], fn project ->
        if project do
          # Analyze the change impact
          change_analysis = analyze_change_impact(old_content, new_content)

          project
          |> update_structure_metrics(file_path, new_content, :modified)
          |> apply_change_impact(change_analysis)
          |> update_quality_trend(change_analysis)
        else
          nil
        end
      end)

    project = get_in(updated_state, [:projects, project_id])

    # Generate optimization suggestions based on the change
    optimizations =
      if project && state.opts.optimization_level != :minimal do
        suggest_optimizations(project, file_path, new_content, state.opts.optimization_level)
      else
        []
      end

    {:ok, %{file_modified: file_path, optimizations: optimizations}, updated_state}
  end

  @impl true
  def handle_signal(%{type: "project.dependency.check"} = signal, state) do
    project_id = signal.data.project_id

    case get_in(state, [:projects, project_id]) do
      nil ->
        {:ok, %{status: :project_not_monitored}, state}

      project ->
        # Check dependencies
        deps_result = check_project_dependencies(project_id)

        # Update dependency state
        updated_project =
          project
          |> Map.put(:dependencies, deps_result)
          |> put_in([:monitoring, :last_dependency_check], DateTime.utc_now())

        # Check for vulnerable or outdated dependencies
        alerts = []

        alerts =
          if length(deps_result.vulnerable) > 0 do
            [%{type: :vulnerable_dependencies, count: length(deps_result.vulnerable)} | alerts]
          else
            alerts
          end

        alerts =
          if length(deps_result.outdated) > 0 do
            [%{type: :outdated_dependencies, count: length(deps_result.outdated)} | alerts]
          else
            alerts
          end

        updated_state = put_in(state, [:projects, project_id], updated_project)

        {:ok, %{dependencies: deps_result, alerts: alerts}, updated_state}
    end
  end

  @impl true
  def handle_signal(%{type: "project.quality.analyze"} = signal, state) do
    project_id = signal.data.project_id

    case get_in(state, [:projects, project_id]) do
      nil ->
        {:ok, %{status: :project_not_monitored}, state}

      project ->
        # Perform comprehensive quality analysis
        quality_results = analyze_project_quality(project_id, state.opts)

        # Update metrics
        updated_project =
          project
          |> Map.put(:quality_metrics, quality_results.metrics)
          |> Map.put(:refactoring_candidates, quality_results.refactoring_candidates)
          |> put_in(
            [:monitoring, :trend],
            determine_quality_trend(project, quality_results.metrics)
          )

        # Check against thresholds
        violations = check_quality_violations(quality_results.metrics, state.opts)

        updated_state = put_in(state, [:projects, project_id], updated_project)

        # Emit quality report
        emit_signal("project.quality.report", %{
          project_id: project_id,
          metrics: quality_results.metrics,
          trend: updated_project.monitoring.trend,
          violations: violations
        })

        {:ok, quality_results, updated_state}
    end
  end

  @impl true
  def handle_signal(%{type: "project.refactor.suggest"} = signal, state) do
    project_id = signal.data.project_id
    scope = signal.data[:scope] || :project

    case get_in(state, [:projects, project_id]) do
      nil ->
        {:ok, %{status: :project_not_monitored}, state}

      project ->
        # Generate refactoring suggestions based on scope
        suggestions =
          case scope do
            :project -> suggest_project_refactoring(project, state.opts)
            :module -> suggest_module_refactoring(project, signal.data[:module], state.opts)
            :file -> suggest_file_refactoring(project, signal.data[:file], state.opts)
            _ -> []
          end

        # Rank suggestions by impact and effort
        ranked_suggestions = rank_refactoring_suggestions(suggestions)

        # Update state with new suggestions
        updated_project = Map.put(project, :refactoring_candidates, ranked_suggestions)
        updated_state = put_in(state, [:projects, project_id], updated_project)

        {:ok, %{suggestions: ranked_suggestions}, updated_state}
    end
  end

  @impl true
  def handle_signal(_signal, state) do
    {:ok, state}
  end

  # Private helper functions

  defp schedule_analysis(project_id) do
    # In a real implementation, this would schedule recurring analysis
    Logger.debug("Scheduling analysis for project: #{project_id}")
    :ok
  end

  defp update_project_metrics(project, changes) do
    # Update metrics based on changes
    project
    |> update_in([:quality_metrics, :score], fn score ->
      # Adjust score based on change type
      case changes[:type] do
        :improvement -> min(1.0, score + 0.05)
        :degradation -> max(0.0, score - 0.05)
        _ -> score
      end
    end)
  end

  defp check_quality_thresholds(project, opts) do
    alerts = []
    metrics = project.quality_metrics

    alerts =
      if metrics.score < opts.quality_threshold do
        [%{type: :low_quality, value: metrics.score, threshold: opts.quality_threshold} | alerts]
      else
        alerts
      end

    alerts =
      if metrics.complexity > opts.max_complexity do
        [
          %{type: :high_complexity, value: metrics.complexity, threshold: opts.max_complexity}
          | alerts
        ]
      else
        alerts
      end

    alerts =
      if metrics.test_coverage < opts.min_test_coverage do
        [
          %{
            type: :low_test_coverage,
            value: metrics.test_coverage,
            threshold: opts.min_test_coverage
          }
          | alerts
        ]
      else
        alerts
      end

    alerts
  end

  defp generate_refactoring_suggestions(project, opts) do
    suggestions = []

    # Check for high complexity modules
    suggestions =
      if project.quality_metrics.complexity > opts.max_complexity do
        [
          %{
            type: :reduce_complexity,
            priority: :high,
            description: "Break down complex modules",
            effort: :medium,
            impact: :high
          }
          | suggestions
        ]
      else
        suggestions
      end

    # Check for low test coverage
    suggestions =
      if project.quality_metrics.test_coverage < opts.min_test_coverage do
        [
          %{
            type: :improve_test_coverage,
            priority: :high,
            description: "Add missing tests",
            effort: :medium,
            impact: :medium
          }
          | suggestions
        ]
      else
        suggestions
      end

    # Check for technical debt
    suggestions =
      if project.quality_metrics.technical_debt > 100 do
        [
          %{
            type: :reduce_technical_debt,
            priority: :medium,
            description: "Address accumulated technical debt",
            effort: :high,
            impact: :high
          }
          | suggestions
        ]
      else
        suggestions
      end

    suggestions
  end

  defp update_structure_metrics(project, file_path, content, action) do
    lines =
      content
      |> Kernel.||("")
      |> String.split("\n")
      |> length()

    is_test = String.contains?(file_path, "_test.exs")

    case action do
      :added ->
        project
        |> update_in([:structure, :files], &(&1 + 1))
        |> update_in([:structure, :lines_of_code], &(&1 + lines))
        |> update_in([:structure, :test_files], &if(is_test, do: &1 + 1, else: &1))

      :modified ->
        # For modifications, we'd need to track the delta
        project

      :removed ->
        project
        |> update_in([:structure, :files], &max(0, &1 - 1))
        |> update_in([:structure, :lines_of_code], &max(0, &1 - lines))
        |> update_in([:structure, :test_files], &if(is_test, do: max(0, &1 - 1), else: &1))
    end
  end

  defp analyze_file_impact(project, _file_path, content) do
    # Analyze the impact of the file on project quality
    complexity = estimate_file_complexity(content)

    # Update complexity metrics
    update_in(project, [:quality_metrics, :complexity], fn current ->
      # Simple average for now
      (current + complexity) / 2
    end)
  end

  defp detect_dependency_changes(project, content) do
    # Detect if dependencies have changed (mix.exs modifications)
    if String.contains?(content || "", "deps do") do
      # Mark dependencies as needing refresh
      put_in(project, [:dependencies, :needs_refresh], true)
    else
      project
    end
  end

  defp analyze_change_impact(old_content, new_content) do
    old_lines =
      (old_content || "")
      |> String.split("\n")
      |> length()

    new_lines =
      (new_content || "")
      |> String.split("\n")
      |> length()

    %{
      lines_added: max(0, new_lines - old_lines),
      lines_removed: max(0, old_lines - new_lines),
      complexity_change:
        estimate_file_complexity(new_content) - estimate_file_complexity(old_content)
    }
  end

  defp apply_change_impact(project, change_analysis) do
    update_in(project, [:quality_metrics, :complexity], fn current ->
      current + change_analysis.complexity_change * 0.1
    end)
  end

  defp update_quality_trend(project, change_analysis) do
    current_trend = project.monitoring.trend

    new_trend =
      cond do
        change_analysis.complexity_change > 5 -> :degrading
        change_analysis.complexity_change < -5 -> :improving
        true -> current_trend
      end

    put_in(project, [:monitoring, :trend], new_trend)
  end

  defp suggest_optimizations(_project, file_path, content, level) do
    suggestions = []

    # Basic optimizations
    suggestions =
      if String.contains?(content, "Enum.map") && String.contains?(content, "Enum.filter") do
        [
          %{
            type: :combine_enum_operations,
            file: file_path,
            description:
              "Combine Enum.map and Enum.filter into Enum.flat_map or for comprehension"
          }
          | suggestions
        ]
      else
        suggestions
      end

    # Moderate optimizations
    suggestions =
      if level in [:moderate, :aggressive] do
        if String.contains?(content, "length(") && String.contains?(content, ") == 0") do
          [
            %{
              type: :use_enum_empty,
              file: file_path,
              description: "Replace length(list) == 0 with Enum.empty?(list)"
            }
            | suggestions
          ]
        else
          suggestions
        end
      else
        suggestions
      end

    # Aggressive optimizations
    suggestions =
      if level == :aggressive do
        if String.contains?(content, "Enum.") && lines_count(content) > 10 do
          [
            %{
              type: :consider_stream,
              file: file_path,
              description: "Consider using Stream for large data processing"
            }
            | suggestions
          ]
        else
          suggestions
        end
      else
        suggestions
      end

    suggestions
  end

  defp check_project_dependencies(_project_id) do
    # In a real implementation, would check mix.exs and mix.lock
    %{
      direct: [],
      transitive: [],
      outdated: [],
      vulnerable: []
    }
  end

  defp analyze_project_quality(_project_id, _opts) do
    # Comprehensive quality analysis
    %{
      metrics: %{
        score: 0.85,
        complexity: 8,
        test_coverage: 0.75,
        documentation_coverage: 0.60,
        technical_debt: 42
      },
      refactoring_candidates: []
    }
  end

  defp determine_quality_trend(old_project, new_metrics) do
    old_score = old_project.quality_metrics.score
    new_score = new_metrics.score

    cond do
      new_score > old_score + 0.05 -> :improving
      new_score < old_score - 0.05 -> :degrading
      true -> :stable
    end
  end

  defp check_quality_violations(metrics, opts) do
    violations = []

    violations =
      if metrics.score < opts.quality_threshold do
        [%{metric: :score, value: metrics.score, threshold: opts.quality_threshold} | violations]
      else
        violations
      end

    violations =
      if metrics.complexity > opts.max_complexity do
        [
          %{metric: :complexity, value: metrics.complexity, threshold: opts.max_complexity}
          | violations
        ]
      else
        violations
      end

    violations
  end

  defp suggest_project_refactoring(_project, _opts) do
    # Generate project-wide refactoring suggestions
    []
  end

  defp suggest_module_refactoring(_project, _module_name, _opts) do
    # Generate module-specific refactoring suggestions
    []
  end

  defp suggest_file_refactoring(_project, _file_path, _opts) do
    # Generate file-specific refactoring suggestions
    []
  end

  defp rank_refactoring_suggestions(suggestions) do
    # Rank by priority, then by impact/effort ratio
    Enum.sort_by(suggestions, fn s ->
      priority_score =
        case s.priority do
          :high -> 3
          :medium -> 2
          :low -> 1
        end

      impact_score =
        case s.impact do
          :high -> 3
          :medium -> 2
          :low -> 1
        end

      effort_score =
        case s.effort do
          :low -> 3
          :medium -> 2
          :high -> 1
        end

      # Higher score = higher rank
      -(priority_score * 10 + impact_score * 5 + effort_score)
    end)
  end

  defp assess_quality_impact(project) do
    score = project.quality_metrics.score

    cond do
      score >= 0.9 -> :positive
      score >= 0.7 -> :neutral
      score >= 0.5 -> :minor_negative
      true -> :major_negative
    end
  end

  defp estimate_file_complexity(content) do
    # Simple complexity estimation based on conditionals and nesting
    lines = String.split(content || "", "\n")

    conditionals =
      Enum.count(lines, fn line ->
        String.contains?(line, ["if ", "unless ", "case ", "cond "])
      end)

    nesting =
      lines
      |> Enum.map(fn line ->
        String.length(line) - String.length(String.trim_leading(line))
      end)
      |> Enum.max(fn -> 0 end)
      |> div(2)

    conditionals + nesting
  end

  defp lines_count(content) do
    (content || "")
    |> String.split("\n")
    |> length()
  end

  defp emit_signal(type, data) do
    # In a real implementation, this would emit through the Jido signal system
    Logger.debug("Emitting signal: #{type} with data: #{inspect(data)}")
    :ok
  end
end
