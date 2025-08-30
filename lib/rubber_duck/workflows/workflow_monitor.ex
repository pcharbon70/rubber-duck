defmodule RubberDuck.Workflows.WorkflowMonitor do
  @moduledoc """
  Workflow execution monitoring for agent performance tracking and optimization.

  This module provides comprehensive monitoring of workflow adoption and performance
  across agents, enabling data-driven decisions about workflow effectiveness and
  optimization opportunities for agent coordination patterns.

  Features:
  - Real-time workflow execution monitoring with performance metrics
  - Agent adoption pattern tracking and analysis
  - Performance comparison between autonomous and workflow execution
  - Workflow template effectiveness measurement and optimization
  - Agent-specific workflow recommendations based on historical data
  - System-wide workflow health and performance dashboard data

  Monitoring Dimensions:
  - **Execution Performance**: Time, success rate, resource usage
  - **Adoption Patterns**: Which agents adopt workflows and why
  - **Template Effectiveness**: How well different templates perform
  - **System Impact**: Overall system performance with workflow adoption
  """

  use GenServer
  require Logger

  alias RubberDuck.Workflows.{OptionalWorkflowUtils, WorkflowTemplates}

  @default_state %{
    active_workflows: %{},
    execution_history: [],
    agent_adoption_patterns: %{},
    template_performance: %{},
    system_metrics: %{
      total_executions: 0,
      workflow_executions: 0,
      autonomous_executions: 0,
      avg_workflow_performance: %{},
      avg_autonomous_performance: %{}
    },
    monitoring_config: %{
      # 3 days
      history_retention_hours: 72,
      performance_sample_size: 1000,
      alert_thresholds: %{
        # Alert if >10% failure rate
        workflow_failure_rate: 0.1,
        # Alert if >20% performance drop
        performance_degradation: 0.2
      }
    }
  }

  # Public API

  @doc """
  Start the workflow monitor with optional configuration.
  """
  def start_link(opts \\ []) do
    initial_state = Map.merge(@default_state, Map.new(opts))
    GenServer.start_link(__MODULE__, initial_state, name: __MODULE__)
  end

  @doc """
  Record workflow execution start for monitoring.
  """
  def record_workflow_start(workflow_id, agent_module, workflow_config) do
    GenServer.cast(__MODULE__, {:workflow_start, workflow_id, agent_module, workflow_config})
  end

  @doc """
  Record workflow execution completion with results.
  """
  def record_workflow_completion(workflow_id, execution_result) do
    GenServer.cast(__MODULE__, {:workflow_completion, workflow_id, execution_result})
  end

  @doc """
  Record autonomous execution for performance comparison.
  """
  def record_autonomous_execution(agent_module, execution_result) do
    GenServer.cast(__MODULE__, {:autonomous_execution, agent_module, execution_result})
  end

  @doc """
  Get workflow adoption statistics for analysis.
  """
  def get_adoption_statistics do
    GenServer.call(__MODULE__, :get_adoption_statistics)
  end

  @doc """
  Get performance comparison between autonomous and workflow execution.
  """
  def get_performance_comparison(agent_module \\ :all) do
    GenServer.call(__MODULE__, {:get_performance_comparison, agent_module})
  end

  @doc """
  Get workflow template effectiveness metrics.
  """
  def get_template_effectiveness do
    GenServer.call(__MODULE__, :get_template_effectiveness)
  end

  @doc """
  Get recommendations for agent workflow adoption.
  """
  def get_adoption_recommendations(agent_module) do
    GenServer.call(__MODULE__, {:get_adoption_recommendations, agent_module})
  end

  # GenServer implementation

  @impl true
  def init(initial_state) do
    Logger.info("WorkflowMonitor: Starting workflow monitoring system")

    # Schedule periodic cleanup and analysis
    schedule_periodic_tasks()

    {:ok, initial_state}
  end

  @impl true
  def handle_cast({:workflow_start, workflow_id, agent_module, workflow_config}, state) do
    Logger.debug("WorkflowMonitor: Recording workflow start",
      workflow_id: workflow_id,
      agent_module: agent_module
    )

    # Record active workflow
    workflow_info = %{
      workflow_id: workflow_id,
      agent_module: agent_module,
      workflow_config: workflow_config,
      started_at: System.monotonic_time(:microsecond),
      status: :running
    }

    updated_active = Map.put(state.active_workflows, workflow_id, workflow_info)
    updated_state = %{state | active_workflows: updated_active}

    {:noreply, updated_state}
  end

  @impl true
  def handle_cast({:workflow_completion, workflow_id, execution_result}, state) do
    Logger.debug("WorkflowMonitor: Recording workflow completion",
      workflow_id: workflow_id,
      success: execution_result.success
    )

    case Map.get(state.active_workflows, workflow_id) do
      nil ->
        Logger.warning("WorkflowMonitor: Workflow not found in active list",
          workflow_id: workflow_id
        )

        {:noreply, state}

      workflow_info ->
        # Calculate execution metrics
        completion_time = System.monotonic_time(:microsecond)
        total_execution_time = completion_time - workflow_info.started_at

        # Create execution record
        execution_record = %{
          workflow_id: workflow_id,
          agent_module: workflow_info.agent_module,
          template_type: get_in(workflow_info.workflow_config, [:template_metadata, :pattern]),
          execution_time_microseconds: total_execution_time,
          success: execution_result.success,
          completed_at: DateTime.utc_now(),
          execution_type: :workflow,
          result_metadata: Map.take(execution_result, [:result, :workflow_metadata])
        }

        # Update state
        updated_state =
          state
          |> update_execution_history(execution_record)
          |> update_agent_adoption_patterns(workflow_info.agent_module, execution_record)
          |> update_template_performance(execution_record)
          |> update_system_metrics(execution_record)
          |> remove_active_workflow(workflow_id)

        {:noreply, updated_state}
    end
  end

  @impl true
  def handle_cast({:autonomous_execution, agent_module, execution_result}, state) do
    Logger.debug("WorkflowMonitor: Recording autonomous execution",
      agent_module: agent_module,
      success: execution_result.success
    )

    # Create autonomous execution record
    execution_record = %{
      agent_module: agent_module,
      execution_time_microseconds: execution_result.execution_time_microseconds,
      success: execution_result.success,
      completed_at: DateTime.utc_now(),
      execution_type: :autonomous,
      result_metadata: Map.take(execution_result, [:result])
    }

    # Update state
    updated_state =
      state
      |> update_execution_history(execution_record)
      |> update_agent_adoption_patterns(agent_module, execution_record)
      |> update_system_metrics(execution_record)

    {:noreply, updated_state}
  end

  @impl true
  def handle_call(:get_adoption_statistics, _from, state) do
    statistics = calculate_adoption_statistics(state)
    {:reply, {:ok, statistics}, state}
  end

  @impl true
  def handle_call({:get_performance_comparison, agent_module}, _from, state) do
    comparison = calculate_performance_comparison(state, agent_module)
    {:reply, {:ok, comparison}, state}
  end

  @impl true
  def handle_call(:get_template_effectiveness, _from, state) do
    effectiveness = calculate_template_effectiveness(state)
    {:reply, {:ok, effectiveness}, state}
  end

  @impl true
  def handle_call({:get_adoption_recommendations, agent_module}, _from, state) do
    recommendations = generate_agent_recommendations(state, agent_module)
    {:reply, {:ok, recommendations}, state}
  end

  @impl true
  def handle_info(:periodic_cleanup, state) do
    Logger.debug("WorkflowMonitor: Performing periodic cleanup")

    updated_state = perform_periodic_cleanup(state)
    # Schedule next cleanup
    schedule_periodic_tasks()

    {:noreply, updated_state}
  end

  @impl true
  def handle_info(:performance_analysis, state) do
    Logger.debug("WorkflowMonitor: Performing performance analysis")

    # Analyze system performance and generate insights
    analysis_result = perform_performance_analysis(state)

    if analysis_result.alerts_generated > 0 do
      Logger.warning("WorkflowMonitor: Performance alerts generated",
        alerts: analysis_result.alerts_generated
      )
    end

    {:noreply, state}
  end

  # Private implementation functions

  defp schedule_periodic_tasks do
    # Schedule cleanup every hour
    Process.send_after(self(), :periodic_cleanup, 3_600_000)

    # Schedule performance analysis every 30 minutes
    Process.send_after(self(), :performance_analysis, 1_800_000)
  end

  defp update_execution_history(state, execution_record) do
    # Add to execution history with size limit
    # Keep last 1000 executions
    history_limit = 1000
    updated_history = [execution_record | Enum.take(state.execution_history, history_limit - 1)]

    %{state | execution_history: updated_history}
  end

  defp update_agent_adoption_patterns(state, agent_module, execution_record) do
    # Update adoption patterns for specific agent
    current_patterns =
      Map.get(state.agent_adoption_patterns, agent_module, %{
        total_executions: 0,
        workflow_executions: 0,
        autonomous_executions: 0,
        adoption_rate: 0.0,
        performance_preference: :unknown
      })

    execution_type = execution_record.execution_type

    updated_patterns =
      case execution_type do
        :workflow ->
          %{
            current_patterns
            | total_executions: current_patterns.total_executions + 1,
              workflow_executions: current_patterns.workflow_executions + 1,
              adoption_rate:
                (current_patterns.workflow_executions + 1) /
                  (current_patterns.total_executions + 1)
          }

        type when type in [:autonomous, :autonomous_fallback] ->
          %{
            current_patterns
            | total_executions: current_patterns.total_executions + 1,
              autonomous_executions: current_patterns.autonomous_executions + 1,
              adoption_rate:
                current_patterns.workflow_executions / (current_patterns.total_executions + 1)
          }
      end

    updated_adoption_patterns =
      Map.put(state.agent_adoption_patterns, agent_module, updated_patterns)

    %{state | agent_adoption_patterns: updated_adoption_patterns}
  end

  defp update_template_performance(state, execution_record) do
    template_type = execution_record.template_type

    if template_type do
      current_performance =
        Map.get(state.template_performance, template_type, %{
          usage_count: 0,
          success_count: 0,
          avg_execution_time: 0.0,
          success_rate: 0.0
        })

      new_usage_count = current_performance.usage_count + 1

      new_success_count =
        current_performance.success_count + if(execution_record.success, do: 1, else: 0)

      new_success_rate = new_success_count / new_usage_count

      # Update running average execution time
      new_avg_time =
        if current_performance.usage_count > 0 do
          (current_performance.avg_execution_time * current_performance.usage_count +
             execution_record.execution_time_microseconds) / new_usage_count
        else
          execution_record.execution_time_microseconds
        end

      updated_performance = %{
        usage_count: new_usage_count,
        success_count: new_success_count,
        success_rate: Float.round(new_success_rate, 3),
        avg_execution_time: Float.round(new_avg_time, 1)
      }

      updated_template_performance =
        Map.put(state.template_performance, template_type, updated_performance)

      %{state | template_performance: updated_template_performance}
    else
      state
    end
  end

  defp update_system_metrics(state, execution_record) do
    current_metrics = state.system_metrics
    execution_type = execution_record.execution_type

    updated_metrics = %{
      current_metrics
      | total_executions: current_metrics.total_executions + 1,
        workflow_executions:
          current_metrics.workflow_executions + if(execution_type == :workflow, do: 1, else: 0),
        autonomous_executions:
          current_metrics.autonomous_executions +
            if(execution_type in [:autonomous, :autonomous_fallback], do: 1, else: 0)
    }

    %{state | system_metrics: updated_metrics}
  end

  defp remove_active_workflow(state, workflow_id) do
    updated_active = Map.delete(state.active_workflows, workflow_id)
    %{state | active_workflows: updated_active}
  end

  defp calculate_adoption_statistics(state) do
    # Calculate comprehensive adoption statistics
    total_agents = map_size(state.agent_adoption_patterns)

    if total_agents > 0 do
      adoption_rates =
        state.agent_adoption_patterns
        |> Map.values()
        |> Enum.map(&Map.get(&1, :adoption_rate, 0.0))

      avg_adoption_rate = Enum.sum(adoption_rates) / length(adoption_rates)

      # >10% adoption
      agents_using_workflows = Enum.count(adoption_rates, &(&1 > 0.1))
      workflow_adoption_percentage = agents_using_workflows / total_agents

      %{
        total_agents_monitored: total_agents,
        agents_using_workflows: agents_using_workflows,
        workflow_adoption_percentage: Float.round(workflow_adoption_percentage, 3),
        average_adoption_rate: Float.round(avg_adoption_rate, 3),
        system_wide_metrics: state.system_metrics,
        top_adopting_agents: get_top_adopting_agents(state.agent_adoption_patterns),
        adoption_trends: analyze_adoption_trends(state.execution_history)
      }
    else
      %{
        total_agents_monitored: 0,
        agents_using_workflows: 0,
        workflow_adoption_percentage: 0.0,
        average_adoption_rate: 0.0,
        system_wide_metrics: state.system_metrics
      }
    end
  end

  defp calculate_performance_comparison(state, agent_module) do
    # Calculate performance comparison for specific agent or all agents
    if agent_module == :all do
      calculate_system_wide_performance_comparison(state)
    else
      calculate_agent_specific_performance_comparison(state, agent_module)
    end
  end

  defp calculate_system_wide_performance_comparison(state) do
    # Aggregate performance across all agents
    workflow_executions = Enum.filter(state.execution_history, &(&1.execution_type == :workflow))

    autonomous_executions =
      Enum.filter(
        state.execution_history,
        &(&1.execution_type in [:autonomous, :autonomous_fallback])
      )

    workflow_performance = calculate_execution_performance(workflow_executions)
    autonomous_performance = calculate_execution_performance(autonomous_executions)

    %{
      scope: :system_wide,
      workflow_performance: workflow_performance,
      autonomous_performance: autonomous_performance,
      performance_improvement:
        calculate_improvement_metrics(autonomous_performance, workflow_performance),
      sample_sizes: %{
        workflow_executions: length(workflow_executions),
        autonomous_executions: length(autonomous_executions)
      }
    }
  end

  defp calculate_agent_specific_performance_comparison(state, agent_module) do
    # Performance comparison for specific agent
    agent_executions = Enum.filter(state.execution_history, &(&1.agent_module == agent_module))

    workflow_executions = Enum.filter(agent_executions, &(&1.execution_type == :workflow))

    autonomous_executions =
      Enum.filter(agent_executions, &(&1.execution_type in [:autonomous, :autonomous_fallback]))

    workflow_performance = calculate_execution_performance(workflow_executions)
    autonomous_performance = calculate_execution_performance(autonomous_executions)

    %{
      scope: :agent_specific,
      agent_module: agent_module,
      workflow_performance: workflow_performance,
      autonomous_performance: autonomous_performance,
      performance_improvement:
        calculate_improvement_metrics(autonomous_performance, workflow_performance),
      adoption_pattern: Map.get(state.agent_adoption_patterns, agent_module, %{}),
      sample_sizes: %{
        workflow_executions: length(workflow_executions),
        autonomous_executions: length(autonomous_executions)
      }
    }
  end

  defp calculate_execution_performance(executions) do
    if Enum.empty?(executions) do
      %{
        avg_execution_time: 0.0,
        success_rate: 0.0,
        total_executions: 0,
        performance_score: 0.0
      }
    else
      execution_times = Enum.map(executions, & &1.execution_time_microseconds)
      successes = Enum.count(executions, & &1.success)

      avg_time = Enum.sum(execution_times) / length(execution_times)
      success_rate = successes / length(executions)
      performance_score = calculate_performance_score(avg_time, success_rate)

      %{
        avg_execution_time: Float.round(avg_time, 1),
        success_rate: Float.round(success_rate, 3),
        total_executions: length(executions),
        performance_score: performance_score
      }
    end
  end

  defp calculate_performance_score(avg_time_us, success_rate) do
    # Normalize execution time (assume 10 seconds is baseline)
    time_score = max(1.0 - avg_time_us / 10_000_000, 0.1)

    # Combine time and success rate
    performance_score = time_score * 0.4 + success_rate * 0.6
    Float.round(performance_score, 3)
  end

  defp calculate_improvement_metrics(autonomous_perf, workflow_perf) do
    # Calculate improvement metrics comparing workflow to autonomous
    if autonomous_perf.total_executions > 0 and workflow_perf.total_executions > 0 do
      time_improvement =
        (autonomous_perf.avg_execution_time - workflow_perf.avg_execution_time) /
          max(autonomous_perf.avg_execution_time, 1.0)

      success_improvement = workflow_perf.success_rate - autonomous_perf.success_rate

      overall_improvement =
        (workflow_perf.performance_score - autonomous_perf.performance_score) /
          max(autonomous_perf.performance_score, 0.1)

      %{
        time_improvement: Float.round(time_improvement, 3),
        success_rate_improvement: Float.round(success_improvement, 3),
        overall_performance_improvement: Float.round(overall_improvement, 3),
        # 10% improvement threshold
        workflow_preferred: overall_improvement > 0.1
      }
    else
      %{
        time_improvement: 0.0,
        success_rate_improvement: 0.0,
        overall_performance_improvement: 0.0,
        workflow_preferred: false,
        insufficient_data: true
      }
    end
  end

  defp calculate_template_effectiveness(state) do
    # Calculate effectiveness metrics for each template type
    template_stats =
      Map.new(state.template_performance, fn {template_type, performance} ->
        effectiveness_score = calculate_template_effectiveness_score(performance)

        effectiveness_data =
          Map.merge(performance, %{
            effectiveness_score: effectiveness_score,
            recommendation: generate_template_recommendation(effectiveness_score, performance)
          })

        {template_type, effectiveness_data}
      end)

    # Overall template system effectiveness
    if map_size(template_stats) > 0 do
      avg_effectiveness =
        template_stats
        |> Map.values()
        |> Enum.map(&Map.get(&1, :effectiveness_score, 0.0))
        |> Enum.sum()
        |> Kernel./(map_size(template_stats))

      %{
        template_statistics: template_stats,
        overall_effectiveness: Float.round(avg_effectiveness, 3),
        most_effective_template: find_most_effective_template(template_stats),
        least_effective_template: find_least_effective_template(template_stats)
      }
    else
      %{
        template_statistics: %{},
        overall_effectiveness: 0.0,
        message: "No template usage data available"
      }
    end
  end

  defp calculate_template_effectiveness_score(performance) do
    # Calculate effectiveness score based on usage and performance
    # Normalize to 10 uses
    usage_score = min(performance.usage_count / 10, 1.0)
    success_score = performance.success_rate
    efficiency_score = calculate_efficiency_score(performance.avg_execution_time)

    # Weighted effectiveness score
    effectiveness = usage_score * 0.2 + success_score * 0.5 + efficiency_score * 0.3
    Float.round(effectiveness, 3)
  end

  defp calculate_efficiency_score(avg_time_us) do
    # Convert execution time to efficiency score (faster = higher score)
    # 5 seconds baseline
    baseline_time = 5_000_000

    if avg_time_us <= baseline_time do
      1.0
    else
      efficiency = baseline_time / avg_time_us
      Float.round(min(efficiency, 1.0), 3)
    end
  end

  defp generate_template_recommendation(effectiveness_score, performance) do
    cond do
      effectiveness_score > 0.8 ->
        "Highly effective template - recommend for similar operations"

      effectiveness_score > 0.6 ->
        "Effective template - good for appropriate use cases"

      effectiveness_score > 0.4 ->
        "Moderately effective - consider optimization or alternative templates"

      true ->
        "Low effectiveness - investigate issues or consider alternative approaches"
    end
  end

  defp find_most_effective_template(template_stats) do
    if map_size(template_stats) > 0 do
      {template, _stats} =
        Enum.max_by(template_stats, fn {_template, stats} ->
          Map.get(stats, :effectiveness_score, 0.0)
        end)

      template
    else
      :none
    end
  end

  defp find_least_effective_template(template_stats) do
    if map_size(template_stats) > 0 do
      {template, _stats} =
        Enum.min_by(template_stats, fn {_template, stats} ->
          Map.get(stats, :effectiveness_score, 1.0)
        end)

      template
    else
      :none
    end
  end

  defp get_top_adopting_agents(adoption_patterns) do
    # Get agents with highest workflow adoption rates
    adoption_patterns
    |> Enum.sort_by(fn {_agent, patterns} -> patterns.adoption_rate end, :desc)
    |> Enum.take(5)
    |> Enum.map(fn {agent, patterns} ->
      %{
        agent_module: agent,
        adoption_rate: patterns.adoption_rate,
        total_executions: patterns.total_executions
      }
    end)
  end

  defp analyze_adoption_trends(execution_history) do
    # Analyze adoption trends over time
    # Last 100 executions
    recent_executions = Enum.take(execution_history, 100)

    if length(recent_executions) > 10 do
      workflow_executions = Enum.count(recent_executions, &(&1.execution_type == :workflow))
      recent_adoption_rate = workflow_executions / length(recent_executions)

      %{
        recent_adoption_rate: Float.round(recent_adoption_rate, 3),
        trend: determine_adoption_trend(execution_history),
        sample_size: length(recent_executions)
      }
    else
      %{
        recent_adoption_rate: 0.0,
        trend: :insufficient_data,
        sample_size: length(recent_executions)
      }
    end
  end

  defp determine_adoption_trend(execution_history) do
    # Simple trend analysis comparing recent vs older adoption rates
    if length(execution_history) > 50 do
      recent_50 = Enum.take(execution_history, 50)
      older_50 = execution_history |> Enum.drop(50) |> Enum.take(50)

      recent_workflow_rate =
        Enum.count(recent_50, &(&1.execution_type == :workflow)) / length(recent_50)

      older_workflow_rate =
        if length(older_50) > 0 do
          Enum.count(older_50, &(&1.execution_type == :workflow)) / length(older_50)
        else
          0.0
        end

      rate_change = recent_workflow_rate - older_workflow_rate

      cond do
        rate_change > 0.1 -> :increasing
        rate_change < -0.1 -> :decreasing
        true -> :stable
      end
    else
      :insufficient_data
    end
  end

  defp generate_agent_recommendations(state, agent_module) do
    # Generate workflow adoption recommendations for specific agent
    agent_patterns = Map.get(state.agent_adoption_patterns, agent_module)

    if agent_patterns && agent_patterns.total_executions > 5 do
      current_adoption = agent_patterns.adoption_rate

      recommendations = []

      recommendations =
        cond do
          current_adoption < 0.1 ->
            ["Consider trying workflow orchestration for complex operations" | recommendations]

          current_adoption > 0.8 ->
            [
              "High workflow adoption - monitor performance for optimization opportunities"
              | recommendations
            ]

          true ->
            ["Balanced adoption pattern - continue selective workflow usage" | recommendations]
        end

      # Add performance-based recommendations
      recommendations = add_performance_recommendations(state, agent_module, recommendations)

      Enum.reverse(recommendations)
    else
      ["Insufficient execution data - continue current approach and monitor performance"]
    end
  end

  defp add_performance_recommendations(state, agent_module, recommendations) do
    case calculate_performance_comparison(state, agent_module) do
      {:ok, comparison} ->
        add_comparison_recommendations(comparison, recommendations)

      _ ->
        ["Gather more performance data for better recommendations" | recommendations]
    end
  end

  defp add_comparison_recommendations(comparison, recommendations) do
    if Map.has_key?(comparison.performance_improvement, :insufficient_data) do
      ["Gather more performance data for better recommendations" | recommendations]
    else
      if comparison.performance_improvement.workflow_preferred do
        ["Performance data suggests workflows provide benefits" | recommendations]
      else
        ["Autonomous execution performing well - continue current approach" | recommendations]
      end
    end
  end

  defp perform_periodic_cleanup(state) do
    # Clean up old execution history based on retention policy
    retention_hours = state.monitoring_config.history_retention_hours
    cutoff_time = DateTime.utc_now() |> DateTime.add(-retention_hours, :hour)

    updated_history =
      Enum.filter(state.execution_history, fn record ->
        DateTime.compare(record.completed_at, cutoff_time) == :gt
      end)

    # Clean up old active workflows (those running too long)
    current_time = System.monotonic_time(:microsecond)
    # 1 hour in microseconds
    max_workflow_time = 3_600_000_000

    updated_active =
      Map.filter(state.active_workflows, fn {_id, workflow_info} ->
        current_time - workflow_info.started_at < max_workflow_time
      end)

    Logger.debug("WorkflowMonitor: Cleanup completed",
      history_entries_removed: length(state.execution_history) - length(updated_history),
      stale_workflows_removed: map_size(state.active_workflows) - map_size(updated_active)
    )

    %{state | execution_history: updated_history, active_workflows: updated_active}
  end

  defp perform_performance_analysis(state) do
    # Perform comprehensive performance analysis and generate alerts
    alert_thresholds = state.monitoring_config.alert_thresholds
    alerts_generated = 0

    # Check workflow failure rate
    recent_workflow_executions =
      state.execution_history
      |> Enum.filter(&(&1.execution_type == :workflow))
      |> Enum.take(100)

    alerts_generated =
      if length(recent_workflow_executions) > 10 do
        failure_rate =
          Enum.count(recent_workflow_executions, &(!&1.success)) /
            length(recent_workflow_executions)

        if failure_rate > alert_thresholds.workflow_failure_rate do
          Logger.warning("WorkflowMonitor: High workflow failure rate detected",
            failure_rate: failure_rate,
            threshold: alert_thresholds.workflow_failure_rate
          )

          alerts_generated + 1
        else
          alerts_generated
        end
      else
        alerts_generated
      end

    %{
      analysis_completed_at: DateTime.utc_now(),
      alerts_generated: alerts_generated,
      system_health: assess_system_health(state)
    }
  end

  defp assess_system_health(state) do
    # Assess overall system health regarding workflow adoption
    metrics = state.system_metrics

    if metrics.total_executions > 0 do
      workflow_percentage = metrics.workflow_executions / metrics.total_executions

      health_score =
        cond do
          # Balanced adoption
          workflow_percentage > 0.3 and workflow_percentage < 0.7 -> 0.9
          # Some adoption
          workflow_percentage > 0.1 -> 0.8
          # Limited adoption
          true -> 0.6
        end

      %{
        health_score: health_score,
        workflow_adoption_percentage: Float.round(workflow_percentage, 3),
        status: determine_health_status(health_score),
        recommendations: generate_system_health_recommendations(health_score, workflow_percentage)
      }
    else
      %{
        health_score: 0.5,
        status: :unknown,
        message: "Insufficient execution data for health assessment"
      }
    end
  end

  defp determine_health_status(health_score) do
    cond do
      health_score > 0.8 -> :excellent
      health_score > 0.6 -> :good
      health_score > 0.4 -> :fair
      true -> :poor
    end
  end

  defp generate_system_health_recommendations(health_score, workflow_percentage) do
    cond do
      workflow_percentage < 0.1 ->
        [
          "Consider promoting workflow adoption for complex operations",
          "Investigate barriers to workflow adoption"
        ]

      workflow_percentage > 0.8 ->
        ["Monitor for over-reliance on workflows", "Ensure autonomous capabilities remain strong"]

      health_score < 0.6 ->
        ["Investigate workflow performance issues", "Consider template optimization"]

      true ->
        ["System health is good", "Continue monitoring adoption patterns"]
    end
  end
end
