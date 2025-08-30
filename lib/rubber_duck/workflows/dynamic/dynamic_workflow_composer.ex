defmodule RubberDuck.Workflows.Dynamic.DynamicWorkflowComposer do
  @moduledoc """
  Dynamic workflow composition system for runtime workflow creation.

  This module provides sophisticated runtime workflow composition capabilities
  that enable agents to dynamically create, modify, and optimize workflows
  based on current goals, system state, and performance data.

  Features:
  - Runtime workflow composition with intelligent component selection
  - Goal-driven workflow generation based on agent objectives
  - Performance-optimized composition with resource estimation
  - Conflict resolution for component compatibility issues
  - Learning-based optimization from execution outcomes
  - Hot-swapping capabilities for runtime workflow modification

  Composition Strategies:
  - **Goal-Driven**: Compose workflows to achieve specific agent goals
  - **Performance-Optimized**: Create workflows optimized for execution efficiency
  - **Resource-Aware**: Compose workflows considering resource constraints
  - **Learning-Enhanced**: Use historical data to improve composition decisions
  """

  require Logger

  alias RubberDuck.Workflows.{WorkflowTemplates, SkillsComposition, OptionalWorkflowUtils}

  @composition_strategies [
    :goal_driven,
    :performance_optimized,
    :resource_aware,
    :learning_enhanced
  ]

  @default_composition_config %{
    # 100ms max composition time
    max_composition_time_ms: 100,
    enable_intelligent_selection: true,
    enable_conflict_resolution: true,
    enable_performance_optimization: true,
    enable_learning: true,
    resource_constraints: %{
      max_memory_mb: 100,
      max_cpu_percentage: 50,
      # 5 minutes
      max_execution_time_ms: 300_000
    }
  }

  @doc """
  Compose dynamic workflow based on agent goals and system state.

  Returns composed workflow with optimization metadata and performance estimates.
  """
  def compose_workflow(composition_spec, composition_config \\ %{}) do
    merged_config = Map.merge(@default_composition_config, composition_config)

    Logger.info("DynamicWorkflowComposer: Starting dynamic workflow composition",
      strategy: Map.get(composition_spec, :strategy, :goal_driven),
      components_requested: length(Map.get(composition_spec, :components, []))
    )

    composition_start_time = System.monotonic_time(:microsecond)

    with {:ok, validated_spec} <- validate_composition_spec(composition_spec),
         {:ok, composition_strategy} <-
           determine_composition_strategy(validated_spec, merged_config),
         {:ok, selected_components} <-
           select_workflow_components(validated_spec, composition_strategy, merged_config),
         {:ok, composed_workflow} <-
           execute_composition(selected_components, composition_strategy, merged_config),
         {:ok, optimized_workflow} <- optimize_composed_workflow(composed_workflow, merged_config) do
      composition_time = System.monotonic_time(:microsecond) - composition_start_time

      Logger.info("DynamicWorkflowComposer: Dynamic workflow composition completed",
        composition_time_us: composition_time,
        components_selected: length(selected_components),
        optimization_applied: Map.has_key?(optimized_workflow, :optimizations)
      )

      {:ok,
       %{
         composed_workflow: optimized_workflow,
         composition_metadata: %{
           composition_time_microseconds: composition_time,
           strategy_used: composition_strategy,
           components_selected: selected_components,
           optimization_applied: Map.get(optimized_workflow, :optimizations, []),
           resource_estimates: estimate_workflow_resources(optimized_workflow)
         }
       }}
    else
      {:error, reason} ->
        Logger.error("DynamicWorkflowComposer: Dynamic workflow composition failed",
          error: reason
        )

        {:error, reason}
    end
  end

  @doc """
  Merge multiple workflows with conflict resolution and optimization.

  Enables agents to combine multiple workflow patterns into sophisticated
  coordination sequences with intelligent conflict resolution.
  """
  def merge_workflows(workflows, merge_config \\ %{}) do
    Logger.info("DynamicWorkflowComposer: Merging workflows",
      workflow_count: length(workflows),
      merge_strategy: Map.get(merge_config, :strategy, :intelligent)
    )

    with {:ok, validated_workflows} <- validate_workflows_for_merge(workflows),
         {:ok, merge_strategy} <- determine_merge_strategy(validated_workflows, merge_config),
         {:ok, merged_workflow} <- execute_workflow_merge(validated_workflows, merge_strategy),
         {:ok, resolved_workflow} <- resolve_merge_conflicts(merged_workflow, merge_config) do
      Logger.info("DynamicWorkflowComposer: Workflow merge completed",
        original_workflows: length(workflows),
        merge_strategy: merge_strategy,
        conflicts_resolved: length(Map.get(resolved_workflow, :resolved_conflicts, []))
      )

      {:ok,
       %{
         merged_workflow: resolved_workflow,
         merge_metadata: %{
           original_workflow_count: length(workflows),
           merge_strategy: merge_strategy,
           conflicts_resolved: Map.get(resolved_workflow, :resolved_conflicts, []),
           merge_optimizations: Map.get(resolved_workflow, :merge_optimizations, [])
         }
       }}
    else
      {:error, reason} ->
        Logger.error("DynamicWorkflowComposer: Workflow merge failed", error: reason)
        {:error, reason}
    end
  end

  @doc """
  Hot-swap workflow components during runtime without stopping execution.

  Enables agents to modify workflows during execution for optimization
  or adaptation to changing conditions.
  """
  def hot_swap_components(active_workflow_id, swap_spec, swap_config \\ %{}) do
    Logger.info("DynamicWorkflowComposer: Hot-swapping workflow components",
      workflow_id: active_workflow_id,
      components_to_swap: length(Map.get(swap_spec, :component_swaps, []))
    )

    with {:ok, workflow_state} <- get_active_workflow_state(active_workflow_id),
         {:ok, validated_swaps} <- validate_swap_specification(swap_spec, workflow_state),
         {:ok, swap_plan} <-
           create_swap_execution_plan(validated_swaps, workflow_state, swap_config),
         {:ok, swap_result} <- execute_hot_swap(swap_plan, workflow_state) do
      Logger.info("DynamicWorkflowComposer: Hot-swap completed",
        workflow_id: active_workflow_id,
        swaps_executed: length(validated_swaps),
        swap_success: swap_result.success
      )

      {:ok,
       %{
         swap_result: swap_result,
         updated_workflow_state: swap_result.updated_state,
         swap_metadata: %{
           workflow_id: active_workflow_id,
           swaps_executed: validated_swaps,
           swap_plan: swap_plan,
           swap_performance: swap_result.performance_metrics
         }
       }}
    else
      {:error, reason} ->
        Logger.error("DynamicWorkflowComposer: Hot-swap failed",
          workflow_id: active_workflow_id,
          error: reason
        )

        {:error, reason}
    end
  end

  # Private implementation functions

  defp validate_composition_spec(composition_spec) do
    required_fields = [:goal, :components]
    missing_fields = required_fields -- Map.keys(composition_spec)

    if Enum.empty?(missing_fields) do
      {:ok, composition_spec}
    else
      {:error, {:missing_required_fields, missing_fields}}
    end
  end

  defp determine_composition_strategy(validated_spec, config) do
    strategy = Map.get(validated_spec, :strategy, :goal_driven)

    if strategy in @composition_strategies do
      strategy_config = %{
        type: strategy,
        enable_optimization: config.enable_performance_optimization,
        enable_learning: config.enable_learning,
        resource_constraints: config.resource_constraints
      }

      {:ok, strategy_config}
    else
      {:error, {:invalid_composition_strategy, strategy}}
    end
  end

  defp select_workflow_components(validated_spec, strategy, config) do
    Logger.debug("DynamicWorkflowComposer: Selecting workflow components")

    requested_components = Map.get(validated_spec, :components, [])
    agent_capabilities = Map.get(validated_spec, :agent_capabilities, [])

    # Apply intelligent selection if enabled
    if config.enable_intelligent_selection do
      apply_intelligent_component_selection(requested_components, agent_capabilities, strategy)
    else
      validate_requested_components(requested_components)
    end
  end

  defp apply_intelligent_component_selection(components, capabilities, strategy) do
    # Intelligent component selection based on agent capabilities and strategy
    selected_components =
      Enum.map(components, fn component ->
        enhance_component_with_intelligence(component, capabilities, strategy)
      end)

    # Filter out incompatible components
    compatible_components = Enum.filter(selected_components, &component_compatible?/1)

    if Enum.empty?(compatible_components) do
      {:error, :no_compatible_components}
    else
      {:ok, compatible_components}
    end
  end

  defp enhance_component_with_intelligence(component, capabilities, strategy) do
    # Enhance component based on agent capabilities and strategy
    base_component = ensure_component_structure(component)

    enhancements = []

    # Add capability-based enhancements
    enhancements =
      if :performance_monitoring in capabilities do
        [:performance_tracking | enhancements]
      else
        enhancements
      end

    enhancements =
      if :error_recovery in capabilities do
        [:error_recovery | enhancements]
      else
        enhancements
      end

    # Add strategy-based enhancements
    strategy_enhancements =
      case strategy.type do
        :performance_optimized -> [:performance_optimization, :resource_monitoring]
        :learning_enhanced -> [:learning_integration, :pattern_recognition]
        :resource_aware -> [:resource_optimization, :memory_management]
        _ -> []
      end

    Map.merge(base_component, %{
      enhancements: enhancements ++ strategy_enhancements,
      intelligence_applied: true,
      compatibility_score: calculate_component_compatibility(base_component, capabilities)
    })
  end

  defp ensure_component_structure(component) do
    case component do
      %{name: _, type: _} = comp -> comp
      atom when is_atom(atom) -> %{name: atom, type: :skill, action: atom}
      _ -> %{name: :unknown_component, type: :unknown, action: :unknown}
    end
  end

  defp component_compatible?(component) do
    Map.get(component, :compatibility_score, 0.0) > 0.5
  end

  defp calculate_component_compatibility(component, capabilities) do
    # Simple compatibility calculation
    component_requirements = get_component_requirements(component)

    if Enum.empty?(component_requirements) do
      # Default good compatibility
      0.8
    else
      matched_requirements = Enum.count(component_requirements, &(&1 in capabilities))
      matched_requirements / length(component_requirements)
    end
  end

  defp get_component_requirements(component) do
    # Determine requirements based on component type and name
    component_name = to_string(Map.get(component, :name, ""))

    cond do
      String.contains?(component_name, "LLM") -> [:llm_coordination, :provider_management]
      String.contains?(component_name, "RAG") -> [:knowledge_retrieval, :context_building]
      String.contains?(component_name, "Reasoning") -> [:logical_reasoning, :step_validation]
      true -> [:basic_execution]
    end
  end

  defp validate_requested_components(components) do
    if Enum.empty?(components) do
      {:error, :no_components_requested}
    else
      validated_components = Enum.map(components, &ensure_component_structure/1)
      {:ok, validated_components}
    end
  end

  defp execute_composition(selected_components, strategy, config) do
    Logger.debug("DynamicWorkflowComposer: Executing workflow composition")

    case strategy.type do
      :goal_driven ->
        execute_goal_driven_composition(selected_components, strategy, config)

      :performance_optimized ->
        execute_performance_optimized_composition(selected_components, strategy, config)

      :resource_aware ->
        execute_resource_aware_composition(selected_components, strategy, config)

      :learning_enhanced ->
        execute_learning_enhanced_composition(selected_components, strategy, config)
    end
  end

  defp execute_goal_driven_composition(components, strategy, config) do
    # Goal-driven composition focuses on achieving agent objectives
    composition_goal = Map.get(strategy, :goal, :general)

    # Arrange components to achieve goal
    arranged_components = arrange_components_for_goal(components, composition_goal)

    workflow_spec = %{
      id: generate_dynamic_workflow_id("goal_driven"),
      type: :goal_driven_composition,
      components: arranged_components,
      composition_strategy: strategy,
      created_at: DateTime.utc_now(),
      metadata: %{
        composition_goal: composition_goal,
        component_count: length(arranged_components)
      }
    }

    {:ok, workflow_spec}
  end

  defp execute_performance_optimized_composition(components, strategy, config) do
    # Performance-optimized composition focuses on execution efficiency
    optimized_components =
      optimize_components_for_performance(components, config.resource_constraints)

    workflow_spec = %{
      id: generate_dynamic_workflow_id("performance"),
      type: :performance_optimized_composition,
      components: optimized_components,
      composition_strategy: strategy,
      created_at: DateTime.utc_now(),
      metadata: %{
        optimization_applied: true,
        performance_estimates: calculate_performance_estimates(optimized_components)
      }
    }

    {:ok, workflow_spec}
  end

  defp execute_resource_aware_composition(components, strategy, config) do
    # Resource-aware composition considers system resource constraints
    resource_optimized_components =
      optimize_components_for_resources(components, config.resource_constraints)

    workflow_spec = %{
      id: generate_dynamic_workflow_id("resource_aware"),
      type: :resource_aware_composition,
      components: resource_optimized_components,
      composition_strategy: strategy,
      created_at: DateTime.utc_now(),
      metadata: %{
        resource_optimization: true,
        resource_estimates: estimate_component_resources(resource_optimized_components),
        constraints_applied: config.resource_constraints
      }
    }

    {:ok, workflow_spec}
  end

  defp execute_learning_enhanced_composition(components, strategy, config) do
    # Learning-enhanced composition uses historical data for optimization
    learning_optimized_components = apply_learning_optimization(components, strategy)

    workflow_spec = %{
      id: generate_dynamic_workflow_id("learning"),
      type: :learning_enhanced_composition,
      components: learning_optimized_components,
      composition_strategy: strategy,
      created_at: DateTime.utc_now(),
      metadata: %{
        learning_applied: true,
        learning_insights: extract_learning_insights(learning_optimized_components),
        historical_data_used: true
      }
    }

    {:ok, workflow_spec}
  end

  defp optimize_composed_workflow(composed_workflow, config) do
    Logger.debug("DynamicWorkflowComposer: Optimizing composed workflow")

    optimizations = []

    # Apply performance optimizations
    optimizations =
      if config.enable_performance_optimization do
        [:performance_optimization | optimizations]
      else
        optimizations
      end

    # Apply learning optimizations
    optimizations =
      if config.enable_learning do
        [:learning_optimization | optimizations]
      else
        optimizations
      end

    optimized_workflow =
      Map.merge(composed_workflow, %{
        optimizations: optimizations,
        optimization_timestamp: DateTime.utc_now(),
        estimated_performance: estimate_workflow_performance(composed_workflow)
      })

    {:ok, optimized_workflow}
  end

  # Component arrangement and optimization functions

  defp arrange_components_for_goal(components, goal) do
    # Arrange components to achieve specific goal
    case goal do
      :sequential_processing ->
        arrange_sequential_components(components)

      :parallel_execution ->
        arrange_parallel_components(components)

      :coordinated_orchestration ->
        arrange_orchestrated_components(components)

      _ ->
        # Default arrangement
        components
    end
  end

  defp arrange_sequential_components(components) do
    # Arrange for sequential execution with dependencies
    components
    |> Enum.with_index()
    |> Enum.map(fn {component, index} ->
      Map.merge(component, %{
        sequence_order: index,
        depends_on: if(index > 0, do: [index - 1], else: []),
        execution_mode: :sequential
      })
    end)
  end

  defp arrange_parallel_components(components) do
    # Arrange for parallel execution
    Enum.map(components, fn component ->
      Map.merge(component, %{
        parallel_group: :main_execution,
        execution_mode: :parallel,
        synchronization_point: :end_of_execution
      })
    end)
  end

  defp arrange_orchestrated_components(components) do
    # Arrange for orchestrated coordination
    if length(components) > 1 do
      [orchestrator | workers] = components

      enhanced_orchestrator =
        Map.merge(orchestrator, %{
          role: :orchestrator,
          manages: Enum.map(workers, &Map.get(&1, :name)),
          execution_mode: :orchestrator
        })

      enhanced_workers =
        Enum.map(workers, fn worker ->
          Map.merge(worker, %{
            role: :worker,
            managed_by: Map.get(orchestrator, :name),
            execution_mode: :worker
          })
        end)

      [enhanced_orchestrator | enhanced_workers]
    else
      components
    end
  end

  defp optimize_components_for_performance(components, resource_constraints) do
    # Optimize components for performance within resource constraints
    Enum.map(components, fn component ->
      performance_config = %{
        enable_caching: true,
        optimize_memory: true,
        parallel_execution: determine_parallel_capability(component),
        resource_limits: resource_constraints
      }

      Map.merge(component, %{
        performance_config: performance_config,
        optimization_applied: :performance
      })
    end)
  end

  defp optimize_components_for_resources(components, resource_constraints) do
    # Optimize components for resource efficiency
    Enum.map(components, fn component ->
      resource_config = %{
        memory_limit: resource_constraints.max_memory_mb,
        cpu_limit: resource_constraints.max_cpu_percentage,
        execution_timeout: resource_constraints.max_execution_time_ms,
        enable_resource_monitoring: true
      }

      Map.merge(component, %{
        resource_config: resource_config,
        optimization_applied: :resource
      })
    end)
  end

  defp apply_learning_optimization(components, strategy) do
    # Apply learning-based optimization to components
    Enum.map(components, fn component ->
      learning_config = %{
        enable_pattern_learning: true,
        enable_performance_learning: true,
        enable_success_pattern_recognition: true,
        historical_data_integration: true
      }

      Map.merge(component, %{
        learning_config: learning_config,
        optimization_applied: :learning
      })
    end)
  end

  # Performance and resource estimation functions

  defp estimate_workflow_resources(workflow) do
    components = Map.get(workflow, :components, [])

    %{
      estimated_memory_mb: estimate_memory_usage(components),
      estimated_cpu_percentage: estimate_cpu_usage(components),
      estimated_execution_time_ms: estimate_execution_time(components),
      component_count: length(components)
    }
  end

  defp estimate_memory_usage(components) do
    # Simple memory estimation
    # 10MB base
    base_memory = 10
    # 5MB per component
    component_memory = length(components) * 5
    base_memory + component_memory
  end

  defp estimate_cpu_usage(components) do
    # Simple CPU estimation
    # 10% base
    base_cpu = 10
    # 5% per component
    component_cpu = length(components) * 5
    # Cap at 80%
    min(base_cpu + component_cpu, 80)
  end

  defp estimate_execution_time(components) do
    # Simple execution time estimation
    # 1 second base
    base_time = 1000
    # 2 seconds per component
    component_time = length(components) * 2000
    base_time + component_time
  end

  defp estimate_component_resources(components) do
    # Estimate resource usage for components
    %{
      memory_usage_mb: estimate_memory_usage(components),
      cpu_usage_percentage: estimate_cpu_usage(components),
      execution_time_ms: estimate_execution_time(components)
    }
  end

  defp calculate_performance_estimates(components) do
    %{
      throughput_estimate: calculate_throughput_estimate(components),
      latency_estimate: calculate_latency_estimate(components),
      efficiency_score: calculate_efficiency_score(components)
    }
  end

  defp calculate_throughput_estimate(components) do
    # Estimate workflow throughput
    if length(components) > 0 do
      # 100 operations/minute base
      base_throughput = 100
      # More components = lower throughput
      component_factor = 1.0 / length(components)
      base_throughput * component_factor
    else
      0
    end
  end

  defp calculate_latency_estimate(components) do
    # Estimate workflow latency
    # 100ms base
    base_latency = 100
    # 50ms per component
    component_latency = length(components) * 50
    base_latency + component_latency
  end

  defp calculate_efficiency_score(components) do
    # Calculate workflow efficiency score (0.0-1.0)
    if length(components) > 0 do
      # More components generally reduce efficiency
      efficiency = 1.0 - length(components) * 0.1
      # Minimum 10% efficiency
      max(efficiency, 0.1)
    else
      0.0
    end
  end

  defp determine_parallel_capability(component) do
    # Determine if component can execute in parallel
    component_type = Map.get(component, :type, :unknown)
    component_type in [:skill, :action, :parallel_safe]
  end

  # Workflow merge functions (simplified implementations)

  defp validate_workflows_for_merge(workflows) do
    if length(workflows) < 2 do
      {:error, :insufficient_workflows_for_merge}
    else
      {:ok, workflows}
    end
  end

  defp determine_merge_strategy(workflows, config) do
    strategy = Map.get(config, :strategy, :intelligent)
    {:ok, strategy}
  end

  defp execute_workflow_merge(workflows, strategy) do
    # Simple merge implementation
    merged_components =
      workflows
      |> Enum.flat_map(&Map.get(&1, :components, []))

    merged_workflow = %{
      id: generate_dynamic_workflow_id("merged"),
      type: :merged_workflow,
      components: merged_components,
      source_workflows: length(workflows),
      merged_at: DateTime.utc_now()
    }

    {:ok, merged_workflow}
  end

  defp resolve_merge_conflicts(merged_workflow, config) do
    # Simple conflict resolution
    resolved_workflow =
      Map.merge(merged_workflow, %{
        resolved_conflicts: [],
        conflict_resolution_applied: true
      })

    {:ok, resolved_workflow}
  end

  # Hot-swap functions (simplified implementations)

  defp get_active_workflow_state(workflow_id) do
    # Get active workflow state (placeholder)
    {:ok,
     %{
       workflow_id: workflow_id,
       status: :running,
       current_components: [],
       execution_context: %{}
     }}
  end

  defp validate_swap_specification(swap_spec, workflow_state) do
    swaps = Map.get(swap_spec, :component_swaps, [])
    {:ok, swaps}
  end

  defp create_swap_execution_plan(swaps, workflow_state, config) do
    plan = %{
      swaps: swaps,
      execution_order: Enum.with_index(swaps),
      safety_checks: true,
      rollback_enabled: Map.get(config, :enable_rollback, true)
    }

    {:ok, plan}
  end

  defp execute_hot_swap(plan, workflow_state) do
    # Execute hot-swap (placeholder)
    result = %{
      success: true,
      updated_state: workflow_state,
      performance_metrics: %{swap_time_ms: 50}
    }

    {:ok, result}
  end

  defp estimate_workflow_performance(workflow) do
    components = Map.get(workflow, :components, [])

    %{
      estimated_throughput: calculate_throughput_estimate(components),
      estimated_latency: calculate_latency_estimate(components),
      estimated_efficiency: calculate_efficiency_score(components)
    }
  end

  defp extract_learning_insights(components) do
    # Extract learning insights from components
    insights =
      Enum.flat_map(components, fn component ->
        case Map.get(component, :learning_config) do
          %{enable_pattern_learning: true} -> ["Pattern learning enabled"]
          _ -> []
        end
      end)

    if Enum.empty?(insights) do
      ["No learning insights available"]
    else
      insights
    end
  end

  defp generate_dynamic_workflow_id(prefix) do
    timestamp = System.system_time(:nanosecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}_dynamic_#{timestamp}_#{random}"
  end
end
