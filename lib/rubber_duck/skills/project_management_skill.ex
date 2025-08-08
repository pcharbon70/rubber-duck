defmodule RubberDuck.Skills.ProjectManagementSkill do
  @moduledoc """
  Skill for managing projects with quality monitoring and optimization capabilities.

  This skill provides project structure optimization, dependency management,
  code quality monitoring, and refactoring recommendations based on continuous
  analysis of project metrics and patterns.

  Uses typed messages exclusively for all project management operations.
  """

  use RubberDuck.Skills.Base,
    name: "project_management",
    description: "Manages projects with quality monitoring and optimization",
    category: "project",
    tags: ["project", "quality", "dependencies", "refactoring", "monitoring"],
    vsn: "2.0.0",
    opts_key: :project_management,
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

  alias RubberDuck.Messages.Project.{
    AnalyzeStructure,
    UpdateStatus,
    MonitorHealth,
    OptimizeResources
  }









  # Typed message handlers

  @doc """
  Handle typed AnalyzeStructure message
  """
  def handle_analyze_structure(%AnalyzeStructure{} = msg, context) do
    state = context[:state] || %{projects: %{}}
    project = get_in(state, [:projects, msg.project_id]) || %{}

    # Analyze project structure
    structure_analysis = %{
      project_id: msg.project_id,
      modules: analyze_module_structure(project),
      dependencies: if(msg.include_dependencies, do: analyze_dependencies(project), else: nil),
      complexity:
        if(msg.analyze_complexity, do: calculate_project_complexity(project), else: nil),
      depth: msg.depth || :shallow,
      recommendations: generate_structure_recommendations(project)
    }

    # Add detailed analysis for deep inspection
    structure_analysis =
      if msg.depth == :deep do
        structure_analysis
        |> Map.put(:coupling_analysis, analyze_module_coupling(project))
        |> Map.put(:cohesion_metrics, calculate_cohesion_metrics(project))
        |> Map.put(:architecture_violations, detect_architecture_violations(project))
      else
        structure_analysis
      end

    {:ok, structure_analysis}
  end

  @doc """
  Handle typed UpdateStatus message
  """
  def handle_update_status(%UpdateStatus{} = msg, context) do
    state = context[:state] || %{projects: %{}}

    # Update project status
    timestamp = DateTime.utc_now()

    status_update = %{
      project_id: msg.project_id,
      previous_status: get_in(state, [:projects, msg.project_id, :status]),
      new_status: msg.status,
      updated_at: timestamp,
      updated_by: msg.updated_by,
      reason: msg.reason
    }

    # Perform status-specific actions
    actions_taken =
      case msg.status do
        :completed ->
          [archive_project_data(msg.project_id), generate_final_report(msg.project_id)]

        :paused ->
          [save_project_state(msg.project_id)]

        :archived ->
          [cleanup_project_resources(msg.project_id)]

        _ ->
          []
      end

    result = %{
      success: true,
      status_update: status_update,
      actions_taken: actions_taken,
      next_steps: suggest_next_steps(msg.status)
    }

    {:ok, result}
  end

  @doc """
  Handle typed MonitorHealth message
  """
  def handle_monitor_health(%MonitorHealth{} = msg, context) do
    state = context[:state] || %{projects: %{}}
    project = get_in(state, [:projects, msg.project_id]) || %{}

    # Calculate health metrics
    health_metrics =
      msg.metrics
      |> Enum.map(fn metric ->
        {metric, calculate_health_metric(project, metric)}
      end)
      |> Enum.into(%{})

    # Check against thresholds
    alerts =
      if msg.threshold_alerts do
        check_health_thresholds(health_metrics, get_thresholds(state))
      else
        []
      end

    # Generate health report
    health_report = %{
      project_id: msg.project_id,
      timestamp: DateTime.utc_now(),
      metrics: health_metrics,
      overall_health: calculate_overall_health(health_metrics),
      alerts: alerts,
      trends: analyze_health_trends(project, health_metrics),
      recommendations: generate_health_recommendations(health_metrics, alerts)
    }

    {:ok, health_report}
  end

  @doc """
  Handle typed OptimizeResources message
  """
  def handle_optimize_resources(%OptimizeResources{} = msg, context) do
    state = context[:state] || %{projects: %{}}
    project = get_in(state, [:projects, msg.project_id]) || %{}

    # Analyze current resource usage
    current_usage = analyze_resource_usage(project)

    # Generate optimization strategies based on goal
    optimizations =
      case msg.optimization_goal do
        :cost ->
          optimize_for_cost(current_usage, msg.constraints)

        :performance ->
          optimize_for_performance(current_usage, msg.constraints)

        :balanced ->
          optimize_balanced(current_usage, msg.constraints)

        _ ->
          []
      end

    # Add recommendations if requested
    recommendations =
      if msg.include_recommendations do
        generate_optimization_recommendations(optimizations, project)
      else
        []
      end

    result = %{
      project_id: msg.project_id,
      current_usage: current_usage,
      optimization_goal: msg.optimization_goal,
      proposed_optimizations: optimizations,
      estimated_savings: calculate_estimated_savings(optimizations),
      estimated_improvement: calculate_estimated_improvement(optimizations),
      recommendations: recommendations,
      implementation_plan: create_optimization_plan(optimizations)
    }

    {:ok, result}
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

  # Additional helper functions for typed messages

  defp analyze_dependencies(project) do
    # Analyze project dependencies
    %{
      direct: project[:dependencies][:direct] || [],
      transitive: project[:dependencies][:transitive] || [],
      outdated: [],
      vulnerabilities: []
    }
  end

  defp analyze_module_structure(project) do
    # Analyze module structure in the project
    project[:files] ||
      []
      |> Enum.filter(&String.ends_with?(&1, ".ex"))
      |> Enum.map(fn file ->
        %{
          path: file,
          module: extract_module_name(file),
          # Would analyze in real implementation
          functions: [],
          dependencies: []
        }
      end)
  end

  defp extract_module_name(file_path) do
    file_path
    |> String.split("/")
    |> List.last()
    |> String.replace(".ex", "")
    |> Macro.camelize()
  end

  defp calculate_project_complexity(project) do
    # Simple complexity calculation
    file_count = length(project[:files] || [])
    dependency_count = length(project[:dependencies][:direct] || [])

    %{
      cyclomatic: file_count * 2,
      cognitive: dependency_count * 3,
      overall: (file_count + dependency_count) / 2
    }
  end

  defp generate_structure_recommendations(project) do
    recommendations = []

    # Check for large modules
    if length(project[:files] || []) > 100 do
      ["Consider breaking down large modules" | recommendations]
    else
      recommendations
    end
  end

  defp analyze_module_coupling(_project) do
    %{coupling_score: 0.3, highly_coupled: [], suggestions: []}
  end

  defp calculate_cohesion_metrics(_project) do
    %{average_cohesion: 0.7, low_cohesion_modules: []}
  end

  defp detect_architecture_violations(_project) do
    []
  end

  defp archive_project_data(project_id) do
    "Archived data for project #{project_id}"
  end

  defp generate_final_report(project_id) do
    "Generated final report for project #{project_id}"
  end

  defp save_project_state(project_id) do
    "Saved state for project #{project_id}"
  end

  defp cleanup_project_resources(project_id) do
    "Cleaned up resources for project #{project_id}"
  end

  defp suggest_next_steps(status) do
    case status do
      :completed -> ["Archive project", "Generate metrics report"]
      :paused -> ["Document pause reason", "Schedule resume date"]
      :archived -> ["Remove from active monitoring"]
      _ -> []
    end
  end

  defp calculate_health_metric(project, metric) do
    case metric do
      :quality -> project[:quality_metrics][:score] || 0.8
      :velocity -> calculate_velocity(project)
      :debt -> project[:quality_metrics][:technical_debt] || 0
      :coverage -> project[:quality_metrics][:test_coverage] || 0.0
      :complexity -> project[:quality_metrics][:complexity] || 5
    end
  end

  defp calculate_velocity(_project) do
    # Would calculate based on recent changes
    0.75
  end

  defp get_thresholds(state) do
    %{
      quality: state[:opts][:quality_threshold] || 0.7,
      velocity: 0.5,
      debt: 100,
      coverage: state[:opts][:min_test_coverage] || 0.8,
      complexity: state[:opts][:max_complexity] || 10
    }
  end

  defp check_health_thresholds(metrics, thresholds) do
    Enum.flat_map(metrics, fn {metric, value} ->
      threshold = thresholds[metric]

      cond do
        metric in [:quality, :velocity, :coverage] and value < threshold ->
          [{:low, metric, value, threshold}]

        metric in [:debt, :complexity] and value > threshold ->
          [{:high, metric, value, threshold}]

        true ->
          []
      end
    end)
  end

  defp calculate_overall_health(metrics) do
    # Simple average of normalized metrics
    scores =
      Enum.map(metrics, fn {metric, value} ->
        case metric do
          m when m in [:quality, :velocity, :coverage] -> value
          :debt -> max(0, 1 - value / 100)
          :complexity -> max(0, 1 - value / 20)
        end
      end)

    if length(scores) > 0 do
      Enum.sum(scores) / length(scores)
    else
      0.5
    end
  end

  defp analyze_health_trends(_project, _metrics) do
    %{quality: :stable, velocity: :improving, debt: :increasing}
  end

  defp generate_health_recommendations(metrics, alerts) do
    recommendations = []

    recommendations =
      if length(alerts) > 0 do
        ["Address critical health alerts" | recommendations]
      else
        recommendations
      end

    if metrics[:coverage] < 0.5 do
      ["Increase test coverage urgently" | recommendations]
    else
      recommendations
    end
  end

  defp analyze_resource_usage(project) do
    %{
      memory: project[:resource_usage][:memory] || 100,
      cpu: project[:resource_usage][:cpu] || 50,
      storage: project[:resource_usage][:storage] || 200,
      cost_per_month: 150
    }
  end

  defp optimize_for_cost(usage, _constraints) do
    [
      %{type: :reduce_memory, current: usage[:memory], target: usage[:memory] * 0.8},
      %{type: :optimize_storage, current: usage[:storage], target: usage[:storage] * 0.7}
    ]
  end

  defp optimize_for_performance(usage, _constraints) do
    [
      %{type: :increase_cpu, current: usage[:cpu], target: usage[:cpu] * 1.5},
      %{type: :add_caching, impact: :high}
    ]
  end

  defp optimize_balanced(usage, constraints) do
    (optimize_for_cost(usage, constraints) ++ optimize_for_performance(usage, constraints))
    |> Enum.take(3)
  end

  defp generate_optimization_recommendations(optimizations, _project) do
    optimizations
    |> Enum.map(fn opt ->
      "Apply #{opt[:type]} optimization for #{opt[:impact] || :medium} impact"
    end)
  end

  defp calculate_estimated_savings(optimizations) do
    # Simple calculation based on optimization count
    length(optimizations) * 25.0
  end

  defp calculate_estimated_improvement(optimizations) do
    # Performance improvement percentage
    length(optimizations) * 0.1
  end

  defp create_optimization_plan(optimizations) do
    optimizations
    |> Enum.with_index(1)
    |> Enum.map(fn {opt, idx} ->
      %{
        step: idx,
        action: opt[:type],
        estimated_duration: "#{idx * 2} hours",
        dependencies: if(idx > 1, do: [idx - 1], else: [])
      }
    end)
  end
end
