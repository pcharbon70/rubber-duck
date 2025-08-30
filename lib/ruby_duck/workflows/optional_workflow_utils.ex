defmodule RubberDuck.Workflows.OptionalWorkflowUtils do
  @moduledoc """
  Optional workflow utilities for agents that choose to use Reactor orchestration.

  This module provides optional workflow capabilities that agents can use for
  complex multi-step operations requiring sophisticated coordination, compensation
  patterns, or advanced error recovery. Agents remain fully autonomous and can
  operate without workflows.

  Features:
  - Optional workflow creation and execution utilities
  - Integration with existing agent Skills and Actions
  - Compensation patterns for complex multi-agent operations
  - Advanced error recovery with rollback capabilities
  - Performance optimization for CPU-intensive coordination tasks
  - Hot-swappable workflow management through Directives

  Usage Pattern:
  Agents can optionally use workflows when they need sophisticated coordination
  beyond simple Skills composition, while maintaining full autonomy for
  standard operations.
  """

  require Logger

  alias RubberDuck.Workflows.ReactorConfig

  @doc """
  Create an optional workflow for multi-step agent coordination.

  Returns a configured Reactor workflow that agents can choose to execute
  for complex operations requiring sophisticated orchestration.
  """
  def create_optional_workflow(workflow_spec, opts \\ []) do
    Logger.debug("OptionalWorkflowUtils: Creating optional workflow",
      workflow_type: Map.get(workflow_spec, :type, :unknown)
    )

    with {:ok, reactor_config} <- ReactorConfig.create_reactor_config(opts),
         {:ok, workflow_definition} <- build_workflow_definition(workflow_spec, reactor_config),
         {:ok, configured_workflow} <-
           configure_workflow_middleware(workflow_definition, reactor_config) do
      Logger.info("OptionalWorkflowUtils: Optional workflow created",
        workflow_id: workflow_definition.id,
        steps: length(workflow_definition.steps)
      )

      {:ok,
       %{
         workflow: configured_workflow,
         configuration: reactor_config,
         workflow_id: workflow_definition.id,
         execution_options: ReactorConfig.execution_options(workflow_spec.type)
       }}
    else
      {:error, reason} ->
        Logger.error("OptionalWorkflowUtils: Failed to create workflow", error: reason)
        {:error, reason}
    end
  end

  @doc """
  Execute an optional workflow with monitoring and error recovery.

  Agents can call this to execute workflows they've chosen to create,
  with comprehensive monitoring and error handling.
  """
  def execute_optional_workflow(workflow_config, input_data, context \\ %{}) do
    Logger.info("OptionalWorkflowUtils: Executing optional workflow",
      workflow_id: workflow_config.workflow_id
    )

    execution_start_time = System.monotonic_time(:microsecond)

    # Execute the workflow using Reactor
    case execute_reactor_workflow(
           workflow_config.workflow,
           input_data,
           workflow_config.execution_options
         ) do
      {:ok, result} ->
        execution_time = System.monotonic_time(:microsecond) - execution_start_time

        Logger.info("OptionalWorkflowUtils: Workflow executed successfully",
          workflow_id: workflow_config.workflow_id,
          execution_time_us: execution_time
        )

        {:ok,
         %{
           result: result,
           workflow_id: workflow_config.workflow_id,
           execution_metadata: %{
             execution_time_microseconds: execution_time,
             workflow_type: Map.get(context, :workflow_type, :unknown),
             steps_executed: get_steps_executed(result)
           }
         }}

      {:error, reason} ->
        Logger.error("OptionalWorkflowUtils: Workflow execution failed",
          workflow_id: workflow_config.workflow_id,
          error: reason
        )

        {:error, reason}
    end
  end

  @doc """
  Check if an agent should use workflows for a given operation.

  Provides guidance to agents on whether workflow orchestration would
  benefit their specific operation based on complexity and coordination needs.
  """
  def should_use_workflow?(operation_spec) do
    complexity_score = assess_operation_complexity(operation_spec)
    coordination_needs = assess_coordination_needs(operation_spec)

    # Recommend workflows for complex, multi-step operations
    recommendation = complexity_score > 0.7 or coordination_needs > 0.8

    Logger.debug("OptionalWorkflowUtils: Workflow recommendation",
      operation_type: Map.get(operation_spec, :type, :unknown),
      complexity_score: complexity_score,
      coordination_needs: coordination_needs,
      workflow_recommended: recommendation
    )

    %{
      recommended: recommendation,
      complexity_score: complexity_score,
      coordination_needs: coordination_needs,
      reasoning: generate_recommendation_reasoning(complexity_score, coordination_needs)
    }
  end

  # Private implementation functions

  defp build_workflow_definition(workflow_spec, reactor_config) do
    # Build Reactor workflow definition from specification
    workflow_id = Map.get(workflow_spec, :id, generate_workflow_id())
    workflow_type = Map.get(workflow_spec, :type, :generic)
    steps = Map.get(workflow_spec, :steps, [])

    if Enum.empty?(steps) do
      {:error, :no_workflow_steps}
    else
      workflow_definition = %{
        id: workflow_id,
        type: workflow_type,
        steps: steps,
        compensation_strategy: Map.get(workflow_spec, :compensation_strategy, :none),
        error_handling: Map.get(workflow_spec, :error_handling, :fail_fast)
      }

      {:ok, workflow_definition}
    end
  end

  defp configure_workflow_middleware(workflow_definition, reactor_config) do
    # Configure middleware stack for the workflow
    case ReactorConfig.configure_middleware_stack(reactor_config.middleware) do
      {:ok, middleware_configs} ->
        configured_workflow = Map.put(workflow_definition, :middleware, middleware_configs)
        {:ok, configured_workflow}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_reactor_workflow(workflow, input_data, execution_options) do
    # Execute workflow using Reactor framework
    # This is a placeholder implementation - would integrate with actual Reactor execution

    Logger.debug("OptionalWorkflowUtils: Executing Reactor workflow",
      workflow_id: workflow.id,
      input_size: map_size(input_data)
    )

    # Simulate workflow execution
    execution_result = %{
      workflow_id: workflow.id,
      status: :completed,
      steps_executed: length(workflow.steps),
      output: simulate_workflow_output(workflow, input_data),
      execution_metadata: %{
        start_time: System.system_time(:second),
        # Simulate 1 second execution
        end_time: System.system_time(:second) + 1
      }
    }

    {:ok, execution_result}
  end

  defp simulate_workflow_output(workflow, input_data) do
    # Simulate workflow output for development
    %{
      workflow_type: workflow.type,
      input_processed: map_size(input_data),
      steps_completed: length(workflow.steps),
      result: "Simulated workflow output"
    }
  end

  defp get_steps_executed(result) do
    Map.get(result, :steps_executed, 0)
  end

  defp assess_operation_complexity(operation_spec) do
    # Assess operation complexity to determine workflow benefit
    factors = []

    # Check for multiple steps
    step_count = length(Map.get(operation_spec, :steps, []))
    # Normalize to 10 steps
    factors = [step_count / 10 | factors]

    # Check for error recovery needs
    error_recovery = Map.get(operation_spec, :requires_error_recovery, false)
    factors = [if(error_recovery, do: 0.3, else: 0.0) | factors]

    # Check for compensation needs
    compensation = Map.get(operation_spec, :requires_compensation, false)
    factors = [if(compensation, do: 0.4, else: 0.0) | factors]

    # Calculate average complexity
    if Enum.empty?(factors) do
      0.0
    else
      avg_complexity = Enum.sum(factors) / length(factors)
      min(avg_complexity, 1.0)
    end
  end

  defp assess_coordination_needs(operation_spec) do
    # Assess coordination complexity
    coordination_factors = []

    # Multiple agents involved
    agent_count = length(Map.get(operation_spec, :agents_involved, []))
    # Normalize to 5 agents
    coordination_factors = [min(agent_count / 5, 1.0) | coordination_factors]

    # Requires synchronization
    sync_required = Map.get(operation_spec, :requires_synchronization, false)
    coordination_factors = [if(sync_required, do: 0.5, else: 0.0) | coordination_factors]

    # Has dependencies between steps
    has_dependencies = Map.get(operation_spec, :has_step_dependencies, false)
    coordination_factors = [if(has_dependencies, do: 0.3, else: 0.0) | coordination_factors]

    if Enum.empty?(coordination_factors) do
      0.0
    else
      avg_coordination = Enum.sum(coordination_factors) / length(coordination_factors)
      min(avg_coordination, 1.0)
    end
  end

  defp generate_recommendation_reasoning(complexity_score, coordination_needs) do
    cond do
      complexity_score > 0.8 and coordination_needs > 0.8 ->
        "High complexity and coordination needs - workflow orchestration strongly recommended"

      complexity_score > 0.7 or coordination_needs > 0.7 ->
        "Moderate complexity or coordination needs - workflow orchestration recommended"

      complexity_score > 0.5 or coordination_needs > 0.5 ->
        "Some complexity - workflow orchestration may be beneficial"

      true ->
        "Low complexity - simple Skills composition likely sufficient"
    end
  end

  defp generate_workflow_id do
    # Generate unique workflow ID
    timestamp = System.system_time(:nanosecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "workflow_#{timestamp}_#{random}"
  end
end
