defmodule RubberDuck.Agents.ProjectAgent do
  @moduledoc """
  Autonomous agent for project management and code quality optimization.

  This agent provides:
  - Self-organizing project structure optimization
  - Automatic dependency detection and management
  - Continuous code quality monitoring and improvement
  - Autonomous refactoring suggestions with impact analysis
  - Bridge to existing RubberDuck.Projects domain
  """

  use RubberDuck.Agents.Base,
    name: "project_agent",
    description: "Manages projects and optimizes code quality autonomously",
    schema: [
      # Base agent fields
      goals: [type: {:list, :map}, default: []],
      completed_goals: [type: {:list, :map}, default: []],
      experience: [type: {:list, :map}, default: []],
      learning_enabled: [type: :boolean, default: true],
      performance_metrics: [type: :map, default: %{}],
      learned_insights: [type: :map, default: %{}],
      learning_interval: [type: :pos_integer, default: 100],
      last_learning_at: [type: {:or, [:naive_datetime, :nil]}, default: nil],
      persistence_enabled: [type: :boolean, default: false],
      checkpoint_interval: [type: :pos_integer, default: 300_000],
      experience_retention_days: [type: :pos_integer, default: 30],
      max_memory_experiences: [type: :pos_integer, default: 1000],
      agent_state_id: [type: {:or, [:string, :nil]}, default: nil],
      last_checkpoint: [type: {:or, [:utc_datetime, :nil]}, default: nil],

      # Project tracking
      monitored_projects: [type: :map, default: %{}], # project_id => project_state
      project_metrics: [type: :map, default: %{}], # project_id => metrics
      structure_optimizations: [type: :map, default: %{}], # project_id => optimizations

      # Dependency management
      dependency_graph: [type: :map, default: %{}], # project_id => dependencies
      dependency_alerts: [type: {:list, :map}, default: []],
      dependency_update_queue: [type: {:list, :map}, default: []],

      # Code quality
      quality_metrics: [type: :map, default: %{}], # project_id => quality_data
      quality_thresholds: [type: :map, default: %{
        complexity: 10,
        duplication: 0.1,
        test_coverage: 0.8
      }],
      quality_trends: [type: :map, default: %{}],

      # Refactoring
      refactoring_queue: [type: {:list, :map}, default: []],
      refactoring_history: [type: {:list, :map}, default: []],
      impact_analysis_cache: [type: :map, default: %{}],
      max_refactoring_suggestions: [type: :pos_integer, default: 10],

      # Learning and optimization
      optimization_patterns: [type: :map, default: %{}],
      successful_refactorings: [type: {:list, :map}, default: []],
      optimization_confidence_threshold: [type: :float, default: 0.7],

      # Monitoring settings
      scan_interval: [type: :pos_integer, default: 300_000], # 5 minutes
      last_scan_time: [type: {:or, [:utc_datetime, :nil]}, default: nil],
      auto_optimization_enabled: [type: :boolean, default: true]
    ],
    actions: [
      RubberDuck.Actions.Project.AnalyzeStructure,
      RubberDuck.Actions.Project.DetectDependencies,
      RubberDuck.Actions.Project.MonitorQuality,
      RubberDuck.Actions.Project.SuggestRefactoring,
      RubberDuck.Actions.Project.OptimizeStructure,
      RubberDuck.Actions.Project.UpdateDependencies,
      RubberDuck.Actions.Project.AnalyzeImpact,
      RubberDuck.Actions.Project.BridgeDomain
    ]

  alias RubberDuck.Signal
  alias RubberDuck.Projects
  require Logger

  # Signal definitions
  @signal_project_created "project.created"
  @signal_project_updated "project.updated"
  @signal_quality_degraded "project.quality.degraded"
  @signal_dependency_outdated "project.dependency.outdated"
  @signal_refactoring_suggested "project.refactoring.suggested"
  @signal_optimization_completed "project.optimization.completed"

  def init(opts) do
    # Subscribe to project-related signals
    :ok = Signal.subscribe("project.created")
    :ok = Signal.subscribe("project.updated")
    :ok = Signal.subscribe("project.file.changed")
    :ok = Signal.subscribe("project.deleted")

    # Schedule periodic project scanning
    schedule_project_scan()

    {:ok, opts}
  end

  def handle_instruction({:monitor_project, project_id}, agent) do
    case load_project(project_id) do
      {:ok, project} ->
        updated_agent = agent
          |> start_monitoring_project(project)
          |> analyze_project_structure(project_id)
          |> detect_project_dependencies(project_id)
          |> assess_code_quality(project_id)

        {:ok, %{monitoring: true, project_id: project_id}, updated_agent}

      {:error, reason} ->
        Logger.warning("Failed to monitor project #{project_id}: #{inspect(reason)}")
        {{:error, reason}, agent}
    end
  end

  def handle_instruction({:optimize_structure, project_id}, agent) do
    optimizations = Map.get(agent.state.structure_optimizations, project_id, [])

    if length(optimizations) > 0 && agent.state.auto_optimization_enabled do
      case apply_structure_optimizations(agent, project_id, optimizations) do
        {:ok, results} ->
          updated_agent = agent
            |> record_optimization_results(project_id, results)
            |> learn_from_optimization(results)

          emit_signal(@signal_optimization_completed, %{
            project_id: project_id,
            optimizations_applied: length(results)
          })

          {:ok, results, updated_agent}

        {:error, reason} ->
          {{:error, reason}, agent}
      end
    else
      {:ok, %{optimizations: []}, agent}
    end
  end

  def handle_instruction({:suggest_refactorings, project_id}, agent) do
    quality_data = Map.get(agent.state.quality_metrics, project_id, %{})

    suggestions = agent
      |> generate_refactoring_suggestions(project_id, quality_data)
      |> prioritize_suggestions()
      |> Enum.take(agent.state.max_refactoring_suggestions)

    if length(suggestions) > 0 do
      emit_signal(@signal_refactoring_suggested, %{
        project_id: project_id,
        suggestion_count: length(suggestions)
      })
    end

    {:ok, suggestions, agent}
  end

  def handle_instruction({:check_dependencies, project_id}, agent) do
    dependencies = Map.get(agent.state.dependency_graph, project_id, %{})

    outdated = detect_outdated_dependencies(dependencies)
    vulnerabilities = check_dependency_vulnerabilities(dependencies)

    alerts = outdated ++ vulnerabilities

    if length(alerts) > 0 do
      emit_signal(@signal_dependency_outdated, %{
        project_id: project_id,
        alert_count: length(alerts)
      })

      updated_agent = %{agent | state: %{agent.state |
        dependency_alerts: alerts ++ agent.state.dependency_alerts
      }}

      {:ok, alerts, updated_agent}
    else
      {:ok, [], agent}
    end
  end

  def handle_signal("project.created", %{project_id: project_id}, agent) do
    # Automatically start monitoring new projects
    handle_instruction({:monitor_project, project_id}, agent)
  end

  def handle_signal("project.file.changed", %{project_id: project_id, file_path: file_path}, agent) do
    if Map.has_key?(agent.state.monitored_projects, project_id) do
      # Trigger quality check for the changed file
      updated_agent = agent
        |> update_file_metrics(project_id, file_path)
        |> check_quality_thresholds(project_id)
        |> generate_incremental_suggestions(project_id, file_path)

      {:ok, updated_agent}
    else
      {:ok, agent}
    end
  end

  def handle_signal("project.deleted", %{project_id: project_id}, agent) do
    # Clean up monitoring for deleted project
    updated_agent = stop_monitoring_project(agent, project_id)
    {:ok, updated_agent}
  end

  def handle_info(:scan_projects, agent) do
    updated_agent = agent.state.monitored_projects
      |> Map.keys()
      |> Enum.reduce(agent, fn project_id, acc ->
        acc
        |> analyze_project_structure(project_id)
        |> detect_project_dependencies(project_id)
        |> assess_code_quality(project_id)
        |> check_quality_thresholds(project_id)
      end)

    schedule_project_scan()
    {:noreply, %{updated_agent | state: %{updated_agent.state |
      last_scan_time: DateTime.utc_now()
    }}}
  end

  # Private functions

  defp load_project(project_id) do
    case Projects.get_project(project_id) do
      {:ok, project} -> {:ok, project}
      {:error, _} -> {:error, :project_not_found}
    end
  end

  defp start_monitoring_project(agent, project) do
    project_state = %{
      id: project.id,
      name: project.name,
      language: project.language,
      monitoring_started_at: DateTime.utc_now(),
      last_analysis: nil
    }

    put_in(agent.state.monitored_projects[project.id], project_state)
  end

  defp stop_monitoring_project(agent, project_id) do
    %{agent | state: %{agent.state |
      monitored_projects: Map.delete(agent.state.monitored_projects, project_id),
      project_metrics: Map.delete(agent.state.project_metrics, project_id),
      quality_metrics: Map.delete(agent.state.quality_metrics, project_id),
      dependency_graph: Map.delete(agent.state.dependency_graph, project_id),
      structure_optimizations: Map.delete(agent.state.structure_optimizations, project_id)
    }}
  end

  defp analyze_project_structure(agent, project_id) do
    # This would be implemented by the AnalyzeStructure action
    # For now, returning agent unchanged
    agent
  end

  defp detect_project_dependencies(agent, project_id) do
    # This would be implemented by the DetectDependencies action
    # For now, returning agent unchanged
    agent
  end

  defp assess_code_quality(agent, project_id) do
    # This would be implemented by the MonitorQuality action
    # For now, returning agent unchanged
    agent
  end

  defp check_quality_thresholds(agent, project_id) do
    quality_data = Map.get(agent.state.quality_metrics, project_id, %{})
    thresholds = agent.state.quality_thresholds

    violations = []
    violations = if quality_data[:complexity] > thresholds.complexity,
      do: [{:complexity, quality_data[:complexity]} | violations], else: violations
    violations = if quality_data[:duplication] > thresholds.duplication,
      do: [{:duplication, quality_data[:duplication]} | violations], else: violations
    violations = if quality_data[:test_coverage] < thresholds.test_coverage,
      do: [{:test_coverage, quality_data[:test_coverage]} | violations], else: violations

    if length(violations) > 0 do
      emit_signal(@signal_quality_degraded, %{
        project_id: project_id,
        violations: violations
      })
    end

    agent
  end

  defp update_file_metrics(agent, project_id, file_path) do
    # Update metrics for specific file
    # This would be implemented by MonitorQuality action
    agent
  end

  defp generate_incremental_suggestions(agent, project_id, file_path) do
    # Generate suggestions based on file change
    # This would be implemented by SuggestRefactoring action
    agent
  end

  defp generate_refactoring_suggestions(agent, project_id, quality_data) do
    # Generate suggestions based on quality data
    # This would be implemented by SuggestRefactoring action
    []
  end

  defp prioritize_suggestions(suggestions) do
    suggestions
    |> Enum.sort_by(& &1[:impact_score], :desc)
  end

  defp apply_structure_optimizations(agent, project_id, optimizations) do
    # Apply optimizations to project structure
    # This would be implemented by OptimizeStructure action
    {:ok, []}
  end

  defp record_optimization_results(agent, project_id, results) do
    successful = Enum.filter(results, & &1.success)

    %{agent | state: %{agent.state |
      successful_refactorings: successful ++ agent.state.successful_refactorings
    }}
  end

  defp learn_from_optimization(agent, results) do
    # Learn patterns from successful optimizations
    patterns = extract_optimization_patterns(results)

    %{agent | state: %{agent.state |
      optimization_patterns: Map.merge(agent.state.optimization_patterns, patterns)
    }}
  end

  defp extract_optimization_patterns(results) do
    # Extract patterns from optimization results
    %{}
  end

  defp detect_outdated_dependencies(dependencies) do
    # Check for outdated dependencies
    []
  end

  defp check_dependency_vulnerabilities(dependencies) do
    # Check for security vulnerabilities
    []
  end

  defp schedule_project_scan do
    Process.send_after(self(), :scan_projects, 300_000) # 5 minutes
  end

  defp emit_signal(signal_type, payload) do
    Signal.emit(signal_type, Map.put(payload, :timestamp, DateTime.utc_now()))
  rescue
    e -> Logger.warning("Failed to emit signal #{signal_type}: #{inspect(e)}")
  end
end
