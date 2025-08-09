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

  # Removed unused function check_quality_thresholds/2

  # Removed unused function generate_refactoring_suggestions/2

  # Removed unused function update_structure_metrics/4
  # Removed unused function analyze_file_impact/3
  # Removed unused function detect_dependency_changes/2
  # Removed unused function analyze_change_impact/2
  # Removed unused function apply_change_impact/2
  # Removed unused function update_quality_trend/2
  # Removed unused function suggest_optimizations/4
  # Removed unused function check_project_dependencies/1
  # Removed unused function analyze_project_quality/2
  # Removed unused function determine_quality_trend/2
  # Removed unused function check_quality_violations/2
  # Removed unused function suggest_project_refactoring/2
  # Removed unused function suggest_module_refactoring/3
  # Removed unused function suggest_file_refactoring/3
  # Removed unused function rank_refactoring_suggestions/1
  # Removed unused function assess_quality_impact/1
  # Removed unused function estimate_file_complexity/1
  # Removed unused function lines_count/1

  # Removed unused function _generate_refactoring_suggestions/2

  # Removed unused function update_structure_metrics/4

  # Removed unused functions:
  # - analyze_file_impact/3
  # - detect_dependency_changes/2
  # - analyze_change_impact/2
  # - apply_change_impact/2
  # - update_quality_trend/2

  # Removed unused functions:
  # - suggest_optimizations/4
  # - check_project_dependencies/1
  # - analyze_project_quality/2
  # - determine_quality_trend/2
  # - check_quality_violations/2
  # - suggest_project_refactoring/2
  # - suggest_module_refactoring/3
  # - suggest_file_refactoring/3
  # - rank_refactoring_suggestions/1
  # - assess_quality_impact/1
  # - estimate_file_complexity/1
  # - lines_count/1

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
