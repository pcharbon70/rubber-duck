defmodule RubberDuck.Workflows.Actions.ComposeReactorWorkflowAction do
  @moduledoc """
  Reactor workflow composition action with goal decomposition and optimization.

  This action provides comprehensive workflow composition capabilities using
  the Reactor framework with intelligent goal decomposition, component selection,
  and performance optimization for sophisticated agent coordination.

  Features:
  - Goal-driven workflow composition with intelligent component selection
  - Performance optimization with resource constraint management
  - Integration with existing DynamicWorkflowComposer capabilities
  - Template-based composition with customization and learning
  - Validation and error handling with rollback capabilities
  - Monitoring integration with performance tracking and analytics

  Composition Strategies:
  - **Goal Decomposition**: Break down complex goals into executable workflow components
  - **Component Optimization**: Select optimal components based on agent capabilities
  - **Performance Tuning**: Optimize workflow for execution efficiency and resource usage
  - **Template Integration**: Use existing templates with goal-specific customization
  """

  use Jido.Action,
    name: "compose_reactor_workflow",
    schema: [
      composition_goal: [
        type: :map,
        required: true,
        doc: "Goal specification for workflow composition"
      ],
      agent_capabilities: [
        type: {:list, :atom},
        default: [],
        doc: "Agent capabilities for component selection"
      ],
      composition_strategy: [type: :atom, default: :goal_driven, doc: "Composition strategy"],
      optimization_config: [type: :map, default: %{}, doc: "Optimization configuration"],
      context: [type: :map, default: %{}, doc: "Composition context"]
    ]

  require Logger

  alias RubberDuck.Workflows.{Dynamic.DynamicWorkflowComposer, WorkflowTemplates}

  @composition_strategies [:goal_driven, :performance_optimized, :resource_aware, :template_based]

  @default_optimization_config %{
    enable_performance_optimization: true,
    enable_resource_optimization: true,
    enable_template_integration: true,
    max_composition_time_ms: 5000,
    target_performance_improvement: 0.2
  }

  @doc """
  Compose Reactor workflow based on goal specification with optimization.

  Returns composed workflow with performance metadata and optimization insights.
  """
  def run(params, _context) do
    %{
      composition_goal: goal,
      agent_capabilities: capabilities,
      composition_strategy: strategy,
      optimization_config: opt_config,
      context: composition_context
    } = params

    merged_opt_config = Map.merge(@default_optimization_config, opt_config)

    Logger.info("ComposeReactorWorkflowAction: Starting workflow composition",
      goal_type: Map.get(goal, :type, :unknown),
      strategy: strategy,
      capabilities_count: length(capabilities)
    )

    composition_start_time = System.monotonic_time(:microsecond)

    with {:ok, decomposed_goal} <- decompose_composition_goal(goal, capabilities),
         {:ok, composition_plan} <-
           create_composition_plan(decomposed_goal, strategy, merged_opt_config),
         {:ok, workflow_spec} <-
           build_workflow_specification(composition_plan, composition_context),
         {:ok, composed_workflow} <-
           execute_workflow_composition(workflow_spec, merged_opt_config) do
      composition_time = System.monotonic_time(:microsecond) - composition_start_time

      Logger.info("ComposeReactorWorkflowAction: Workflow composition completed",
        composition_time_us: composition_time,
        workflow_id: composed_workflow.workflow_id,
        components_composed: length(composed_workflow.components)
      )

      {:ok,
       %{
         composed_workflow: composed_workflow,
         composition_metadata: %{
           composition_time_microseconds: composition_time,
           goal_decomposition: decomposed_goal,
           composition_plan: composition_plan,
           strategy_used: strategy,
           optimization_applied: composed_workflow.optimizations_applied
         }
       }}
    else
      {:error, reason} ->
        Logger.error("ComposeReactorWorkflowAction: Workflow composition failed", error: reason)
        {:error, reason}
    end
  end

  # Private implementation functions

  defp decompose_composition_goal(goal, agent_capabilities) do
    # Decompose complex goal into manageable workflow components
    goal_type = Map.get(goal, :type, :generic)
    goal_complexity = Map.get(goal, :complexity, :medium)
    goal_requirements = Map.get(goal, :requirements, [])

    decomposed_components =
      case goal_type do
        :sequential_processing ->
          decompose_sequential_goal(goal, agent_capabilities)

        :parallel_coordination ->
          decompose_parallel_goal(goal, agent_capabilities)

        :orchestration ->
          decompose_orchestration_goal(goal, agent_capabilities)

        _ ->
          decompose_generic_goal(goal, agent_capabilities)
      end

    decomposed_goal = %{
      original_goal: goal,
      goal_type: goal_type,
      complexity: goal_complexity,
      requirements: goal_requirements,
      decomposed_components: decomposed_components,
      agent_capabilities_used:
        capabilities_for_components(decomposed_components, agent_capabilities)
    }

    {:ok, decomposed_goal}
  end

  defp decompose_sequential_goal(goal, capabilities) do
    # Decompose sequential processing goal
    goal_steps = Map.get(goal, :steps, [])

    if Enum.empty?(goal_steps) do
      # Default sequential decomposition
      [
        %{name: :initialize, type: :setup, capability_required: :basic_execution},
        %{name: :process, type: :main_logic, capability_required: :processing},
        %{name: :finalize, type: :cleanup, capability_required: :basic_execution}
      ]
    else
      # Use provided steps with capability mapping
      Enum.map(goal_steps, fn step ->
        Map.merge(step, %{
          capability_required: determine_capability_requirement(step, capabilities)
        })
      end)
    end
  end

  defp decompose_parallel_goal(goal, capabilities) do
    # Decompose parallel coordination goal
    parallel_tasks = Map.get(goal, :parallel_tasks, [])

    if Enum.empty?(parallel_tasks) do
      # Default parallel decomposition
      [
        %{name: :task_coordinator, type: :orchestrator, capability_required: :coordination},
        %{
          name: :parallel_task_1,
          type: :worker,
          capability_required: :processing,
          parallel_group: :main
        },
        %{
          name: :parallel_task_2,
          type: :worker,
          capability_required: :processing,
          parallel_group: :main
        },
        %{name: :result_aggregator, type: :aggregator, capability_required: :aggregation}
      ]
    else
      # Use provided tasks with parallel grouping
      coordinator = %{name: :coordinator, type: :orchestrator, capability_required: :coordination}

      workers =
        Enum.with_index(parallel_tasks, fn task, index ->
          Map.merge(task, %{
            name: String.to_atom("worker_#{index}"),
            type: :worker,
            parallel_group: :main_execution,
            capability_required: determine_capability_requirement(task, capabilities)
          })
        end)

      aggregator = %{name: :aggregator, type: :aggregator, capability_required: :aggregation}

      [coordinator] ++ workers ++ [aggregator]
    end
  end

  defp decompose_orchestration_goal(goal, capabilities) do
    # Decompose orchestration goal
    orchestration_components = Map.get(goal, :components, [])

    if Enum.empty?(orchestration_components) do
      # Default orchestration decomposition
      [
        %{name: :orchestrator, type: :orchestrator, capability_required: :orchestration},
        %{name: :coordinator, type: :coordinator, capability_required: :coordination},
        %{name: :executor, type: :executor, capability_required: :execution},
        %{name: :monitor, type: :monitor, capability_required: :monitoring}
      ]
    else
      # Use provided components with orchestration roles
      Enum.map(orchestration_components, fn component ->
        Map.merge(component, %{
          capability_required: determine_capability_requirement(component, capabilities),
          orchestration_role: determine_orchestration_role(component)
        })
      end)
    end
  end

  defp decompose_generic_goal(goal, capabilities) do
    # Decompose generic goal into basic components
    [
      %{name: :goal_analyzer, type: :analyzer, capability_required: :analysis},
      %{name: :goal_executor, type: :executor, capability_required: :execution},
      %{name: :goal_validator, type: :validator, capability_required: :validation}
    ]
  end

  defp determine_capability_requirement(component, available_capabilities) do
    # Determine required capability for component
    component_name = to_string(Map.get(component, :name, ""))

    cond do
      String.contains?(component_name, ["orchestrat", "coordinat"]) and
          :orchestration in available_capabilities ->
        :orchestration

      String.contains?(component_name, ["process", "execut"]) and
          :processing in available_capabilities ->
        :processing

      String.contains?(component_name, ["monitor", "track"]) and
          :monitoring in available_capabilities ->
        :monitoring

      true ->
        :basic_execution
    end
  end

  defp determine_orchestration_role(component) do
    # Determine orchestration role for component
    component_type = Map.get(component, :type, :worker)

    case component_type do
      :orchestrator -> :primary_orchestrator
      :coordinator -> :coordination_manager
      :executor -> :execution_worker
      :monitor -> :monitoring_observer
      _ -> :general_worker
    end
  end

  defp capabilities_for_components(components, agent_capabilities) do
    # Map agent capabilities to components
    used_capabilities =
      components
      |> Enum.map(&Map.get(&1, :capability_required))
      |> Enum.uniq()
      |> Enum.filter(&(&1 in agent_capabilities))

    %{
      total_capabilities_available: length(agent_capabilities),
      capabilities_used: used_capabilities,
      capability_utilization: length(used_capabilities) / max(length(agent_capabilities), 1)
    }
  end

  defp create_composition_plan(decomposed_goal, strategy, optimization_config) do
    # Create comprehensive composition plan
    plan = %{
      composition_strategy: strategy,
      goal_decomposition: decomposed_goal,
      component_selection_criteria: build_selection_criteria(strategy, optimization_config),
      optimization_targets: build_optimization_targets(optimization_config),
      validation_requirements: build_validation_requirements(decomposed_goal),
      execution_plan: build_execution_plan(decomposed_goal.decomposed_components)
    }

    {:ok, plan}
  end

  defp build_selection_criteria(strategy, optimization_config) do
    # Build component selection criteria based on strategy
    base_criteria = %{
      compatibility_threshold: 0.7,
      performance_requirement: :moderate
    }

    strategy_criteria =
      case strategy do
        :goal_driven -> %{priority: :goal_alignment, weight: 0.8}
        :performance_optimized -> %{priority: :performance, weight: 0.9}
        :resource_aware -> %{priority: :resource_efficiency, weight: 0.7}
        :template_based -> %{priority: :template_compatibility, weight: 0.6}
      end

    Map.merge(base_criteria, strategy_criteria)
  end

  defp build_optimization_targets(optimization_config) do
    # Build optimization targets from configuration
    %{
      performance_improvement_target:
        Map.get(optimization_config, :target_performance_improvement, 0.15),
      resource_efficiency_target: 0.8,
      composition_time_target: Map.get(optimization_config, :max_composition_time_ms, 3000)
    }
  end

  defp build_validation_requirements(decomposed_goal) do
    # Build validation requirements
    %{
      component_validation: :required,
      compatibility_validation: :required,
      performance_validation:
        if(decomposed_goal.complexity == :high, do: :required, else: :optional),
      integration_validation: :recommended
    }
  end

  defp build_execution_plan(components) do
    # Build execution plan for components
    %{
      execution_order: determine_execution_order(components),
      dependency_resolution: resolve_component_dependencies(components),
      parallel_opportunities: identify_parallel_opportunities(components)
    }
  end

  defp determine_execution_order(components) do
    # Determine optimal execution order for components
    components
    |> Enum.with_index()
    |> Enum.map(fn {component, index} ->
      %{
        component: component.name,
        execution_index: index,
        dependency_level: calculate_dependency_level(component, components)
      }
    end)
  end

  defp calculate_dependency_level(component, all_components) do
    # Calculate dependency level for component
    component_type = Map.get(component, :type, :worker)

    case component_type do
      # No dependencies
      :setup -> 0
      # Depends on setup
      :orchestrator -> 1
      # Depends on orchestrator
      :worker -> 2
      # Depends on workers
      :aggregator -> 3
      # Depends on everything
      :cleanup -> 4
      # Default worker level
      _ -> 2
    end
  end

  defp resolve_component_dependencies(components) do
    # Resolve dependencies between components
    Enum.map(components, fn component ->
      dependencies = find_component_dependencies(component, components)
      Map.put(component, :dependencies, dependencies)
    end)
  end

  defp find_component_dependencies(component, all_components) do
    # Find dependencies for specific component
    component_type = Map.get(component, :type, :worker)

    case component_type do
      :aggregator ->
        # Depends on all workers
        all_components
        |> Enum.filter(&(Map.get(&1, :type) == :worker))
        |> Enum.map(&Map.get(&1, :name))

      :worker ->
        # Depends on orchestrator
        all_components
        |> Enum.filter(&(Map.get(&1, :type) == :orchestrator))
        |> Enum.map(&Map.get(&1, :name))

      _ ->
        # No dependencies
        []
    end
  end

  defp identify_parallel_opportunities(components) do
    # Identify components that can execute in parallel
    workers = Enum.filter(components, &(Map.get(&1, :type) == :worker))

    if length(workers) > 1 do
      [
        %{
          parallel_group: :worker_execution,
          components: Enum.map(workers, &Map.get(&1, :name)),
          parallelization_benefit: estimate_parallelization_benefit(workers)
        }
      ]
    else
      []
    end
  end

  defp estimate_parallelization_benefit(workers) do
    # Estimate benefit of parallel execution
    worker_count = length(workers)

    # Simple benefit estimation
    # Up to 80% benefit
    benefit_score = min(worker_count * 0.2, 0.8)
    Float.round(benefit_score, 2)
  end

  defp build_workflow_specification(composition_plan, context) do
    # Build complete workflow specification
    workflow_spec = %{
      id: generate_workflow_id("composed"),
      type: :reactor_composed_workflow,
      composition_plan: composition_plan,
      components: composition_plan.goal_decomposition.decomposed_components,
      execution_plan: composition_plan.execution_plan,
      optimization_targets: composition_plan.optimization_targets,
      context: context,
      created_at: DateTime.utc_now()
    }

    {:ok, workflow_spec}
  end

  defp execute_workflow_composition(workflow_spec, optimization_config) do
    # Execute workflow composition using DynamicWorkflowComposer
    composition_spec = %{
      goal: workflow_spec.composition_plan.goal_decomposition.original_goal,
      components: workflow_spec.components,
      strategy: workflow_spec.composition_plan.composition_strategy,
      agent_capabilities:
        workflow_spec.composition_plan.goal_decomposition.agent_capabilities_used
    }

    case DynamicWorkflowComposer.compose_workflow(composition_spec, optimization_config) do
      {:ok, composition_result} ->
        # Enhance result with action-specific metadata
        enhanced_workflow =
          Map.merge(composition_result.composed_workflow, %{
            workflow_id: workflow_spec.id,
            action_composed: true,
            goal_decomposition_applied: true,
            optimizations_applied: composition_result.composition_metadata.optimization_applied
          })

        {:ok, enhanced_workflow}

      {:error, reason} ->
        {:error, {:composition_execution_failed, reason}}
    end
  end

  defp generate_workflow_id(prefix) do
    timestamp = System.system_time(:nanosecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}_workflow_#{timestamp}_#{random}"
  end
end
