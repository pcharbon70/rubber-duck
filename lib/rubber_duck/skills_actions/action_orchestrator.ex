defmodule RubberDuck.SkillsActions.ActionOrchestrator do
  @moduledoc """
  Action orchestration engine for coordinating complex multi-skill workflows.

  This orchestrator enables sophisticated coordination of skills and actions
  including:
  - Parallel, sequential, and conditional workflow execution
  - Dynamic skill-action binding and dependency resolution
  - Integration with Universal LLM Provider System for intelligent coordination
  - Performance optimization for distributed execution
  - Error handling and recovery for complex workflows
  - Integration with existing Jido framework patterns
  """

  use GenServer
  require Logger

  alias RubberDuck.LlmProviders.UniversalProviderService
  alias RubberDuck.SkillsActions.SkillsRegistry

  @orchestrator_name __MODULE__
  @execution_patterns [:parallel, :sequential, :conditional, :pipeline, :scatter_gather]
  @default_timeout 30_000

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @orchestrator_name)
  end

  @doc """
  Execute workflow with specified pattern and coordination strategy.
  """
  def execute_workflow(workflow_definition, execution_context, options \\ []) do
    GenServer.call(
      @orchestrator_name,
      {:execute_workflow, workflow_definition, execution_context, options},
      Keyword.get(options, :timeout, @default_timeout)
    )
  end

  @doc """
  Execute skills in parallel with result aggregation.
  """
  def execute_parallel_workflow(skills_actions, execution_context, options \\ []) do
    workflow_definition = %{
      pattern: :parallel,
      skills_actions: skills_actions,
      aggregation_strategy: Keyword.get(options, :aggregation, :merge_results)
    }

    execute_workflow(workflow_definition, execution_context, options)
  end

  @doc """
  Execute skills sequentially with context passing between stages.
  """
  def execute_sequential_workflow(skills_actions, execution_context, options \\ []) do
    workflow_definition = %{
      pattern: :sequential,
      skills_actions: skills_actions,
      context_passing: Keyword.get(options, :context_passing, :accumulate)
    }

    execute_workflow(workflow_definition, execution_context, options)
  end

  @doc """
  Execute conditional workflow based on dynamic decision criteria.
  """
  def execute_conditional_workflow(workflow_tree, execution_context, options \\ []) do
    workflow_definition = %{
      pattern: :conditional,
      workflow_tree: workflow_tree,
      decision_strategy: Keyword.get(options, :decision_strategy, :rule_based)
    }

    execute_workflow(workflow_definition, execution_context, options)
  end

  @doc """
  Build and validate workflow definition from skills and actions.
  """
  def build_workflow(skills_actions, pattern, options \\ []) do
    GenServer.call(@orchestrator_name, {:build_workflow, skills_actions, pattern, options})
  end

  @doc """
  Get orchestration statistics and performance metrics.
  """
  def get_orchestration_stats do
    GenServer.call(@orchestrator_name, :get_stats)
  end

  @doc """
  Optimize workflow definition using LLM-assisted analysis.
  """
  def optimize_workflow(workflow_definition, performance_history, user_id \\ nil) do
    GenServer.call(
      @orchestrator_name,
      {:optimize_workflow, workflow_definition, performance_history, user_id}
    )
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    # Subscribe to skills registry and configuration changes
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "skills_registry_events")
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "workflow_events")

    state = %{
      active_workflows: %{},
      workflow_templates: %{},
      execution_history: %{},
      performance_cache: %{},
      stats: %{
        workflows_executed: 0,
        successful_workflows: 0,
        parallel_executions: 0,
        sequential_executions: 0,
        avg_execution_time_ms: 0,
        active_workflow_count: 0
      },
      config: %{
        max_parallel_workflows: Keyword.get(opts, :max_parallel, 20),
        workflow_timeout_ms: Keyword.get(opts, :timeout, @default_timeout),
        llm_optimization_enabled: Keyword.get(opts, :llm_optimization, true),
        performance_monitoring_enabled: Keyword.get(opts, :performance_monitoring, true)
      }
    }

    Logger.info("Action Orchestrator started successfully")
    {:ok, state}
  end

  @impl true
  def handle_call(
        {:execute_workflow, workflow_definition, execution_context, options},
        from,
        state
      ) do
    workflow_id = generate_workflow_id()
    Logger.debug("Executing workflow #{workflow_id} with pattern: #{workflow_definition.pattern}")

    # Validate workflow before execution
    case validate_workflow_definition(workflow_definition) do
      :ok ->
        # Start asynchronous workflow execution
        task =
          Task.async(fn ->
            execute_workflow_async(workflow_id, workflow_definition, execution_context, options)
          end)

        # Track active workflow
        workflow_info = %{
          id: workflow_id,
          definition: workflow_definition,
          context: execution_context,
          started_at: DateTime.utc_now(),
          task: task,
          from: from
        }

        updated_active = Map.put(state.active_workflows, workflow_id, workflow_info)

        updated_stats =
          state.stats
          |> Map.update!(:workflows_executed, &(&1 + 1))
          |> Map.update!(:active_workflow_count, &(&1 + 1))

        new_state = %{state | active_workflows: updated_active, stats: updated_stats}

        # Return immediately with workflow ID, result will come via handle_info
        {:reply, {:ok, %{workflow_id: workflow_id, status: :started}}, new_state}

      {:error, reason} ->
        Logger.error("Workflow validation failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:build_workflow, skills_actions, pattern, options}, _from, state) do
    case build_workflow_definition(skills_actions, pattern, options) do
      {:ok, workflow_definition} ->
        {:reply, {:ok, workflow_definition}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(
        {:optimize_workflow, workflow_definition, performance_history, user_id},
        _from,
        state
      ) do
    if state.config.llm_optimization_enabled do
      case get_llm_workflow_optimization(workflow_definition, performance_history, user_id) do
        {:ok, optimization} ->
          {:reply, {:ok, optimization}, state}

        error ->
          fallback_optimization =
            generate_fallback_optimization(workflow_definition, performance_history)

          {:reply, {:ok, fallback_optimization}, state}
      end
    else
      optimization = generate_fallback_optimization(workflow_definition, performance_history)
      {:reply, {:ok, optimization}, state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    enhanced_stats =
      Map.merge(state.stats, %{
        success_rate: calculate_workflow_success_rate(state.stats),
        avg_workflow_completion_time: calculate_avg_completion_time(state.execution_history),
        most_used_patterns: get_most_used_patterns(state.execution_history),
        performance_trends: analyze_performance_trends(state.execution_history)
      })

    {:reply, {:ok, enhanced_stats}, state}
  end

  @impl true
  def handle_info({ref, workflow_result}, state) when is_reference(ref) do
    # Handle completed workflow task
    case find_workflow_by_task_ref(state.active_workflows, ref) do
      {workflow_id, workflow_info} ->
        Logger.debug("Workflow #{workflow_id} completed")

        # Reply to original caller
        GenServer.reply(workflow_info.from, {:ok, workflow_result})

        # Update statistics and history
        updated_active = Map.delete(state.active_workflows, workflow_id)

        updated_history =
          record_workflow_completion(
            state.execution_history,
            workflow_id,
            workflow_info,
            workflow_result
          )

        success_increment = if workflow_result.success, do: 1, else: 0

        updated_stats =
          state.stats
          |> Map.update!(:successful_workflows, &(&1 + success_increment))
          |> Map.update!(:active_workflow_count, &(&1 - 1))
          |> update_pattern_stats(workflow_info.definition.pattern)

        new_state = %{
          state
          | active_workflows: updated_active,
            execution_history: updated_history,
            stats: updated_stats
        }

        # Clean up completed task
        Process.demonitor(ref, [:flush])

        {:noreply, new_state}

      nil ->
        # Unknown task reference
        Process.demonitor(ref, [:flush])
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Handle failed workflow task
    case find_workflow_by_task_ref(state.active_workflows, ref) do
      {workflow_id, workflow_info} ->
        Logger.error("Workflow #{workflow_id} failed: #{inspect(reason)}")

        # Reply to original caller with error
        GenServer.reply(
          workflow_info.from,
          {:error, "Workflow execution failed: #{inspect(reason)}"}
        )

        # Update statistics
        updated_active = Map.delete(state.active_workflows, workflow_id)

        updated_stats =
          state.stats
          |> Map.update!(:active_workflow_count, &(&1 - 1))

        {:noreply, %{state | active_workflows: updated_active, stats: updated_stats}}

      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # Private implementation

  defp execute_workflow_async(workflow_id, workflow_definition, execution_context, options) do
    start_time = System.monotonic_time(:millisecond)

    case workflow_definition.pattern do
      :parallel ->
        execute_parallel_pattern(workflow_definition, execution_context, options)

      :sequential ->
        execute_sequential_pattern(workflow_definition, execution_context, options)

      :conditional ->
        execute_conditional_pattern(workflow_definition, execution_context, options)

      :pipeline ->
        execute_pipeline_pattern(workflow_definition, execution_context, options)

      :scatter_gather ->
        execute_scatter_gather_pattern(workflow_definition, execution_context, options)

      _ ->
        {:error, "Unknown workflow pattern: #{workflow_definition.pattern}"}
    end
    |> case do
      {:ok, results} ->
        execution_time = System.monotonic_time(:millisecond) - start_time

        %{
          workflow_id: workflow_id,
          success: true,
          results: results,
          execution_time_ms: execution_time,
          pattern: workflow_definition.pattern,
          metadata: %{
            skills_executed: count_skills_in_workflow(workflow_definition),
            actions_executed: count_actions_in_workflow(workflow_definition)
          }
        }

      {:error, reason} ->
        execution_time = System.monotonic_time(:millisecond) - start_time

        %{
          workflow_id: workflow_id,
          success: false,
          error: reason,
          execution_time_ms: execution_time,
          pattern: workflow_definition.pattern
        }
    end
  end

  defp execute_parallel_pattern(workflow_definition, execution_context, options) do
    skills_actions = Map.get(workflow_definition, :skills_actions, [])
    aggregation_strategy = Map.get(workflow_definition, :aggregation_strategy, :merge_results)

    Logger.debug("Executing parallel workflow with #{length(skills_actions)} components")

    # Execute all skills/actions in parallel
    tasks =
      skills_actions
      |> Enum.map(fn skill_action ->
        Task.async(fn ->
          execute_single_skill_action(skill_action, execution_context)
        end)
      end)

    # Wait for all tasks to complete
    results = Task.await_many(tasks, Keyword.get(options, :timeout, @default_timeout))

    # Aggregate results based on strategy
    aggregated_results = aggregate_parallel_results(results, aggregation_strategy)

    {:ok, aggregated_results}
  end

  defp execute_sequential_pattern(workflow_definition, execution_context, options) do
    skills_actions = Map.get(workflow_definition, :skills_actions, [])
    context_passing = Map.get(workflow_definition, :context_passing, :accumulate)

    Logger.debug("Executing sequential workflow with #{length(skills_actions)} components")

    # Execute skills/actions sequentially, passing context between stages
    case execute_sequential_chain(skills_actions, execution_context, context_passing) do
      {:ok, final_result, execution_chain} ->
        {:ok,
         %{
           final_result: final_result,
           execution_chain: execution_chain,
           context_evolution: extract_context_evolution(execution_chain)
         }}

      error ->
        error
    end
  end

  defp execute_conditional_pattern(workflow_definition, execution_context, options) do
    workflow_tree = Map.get(workflow_definition, :workflow_tree, %{})
    decision_strategy = Map.get(workflow_definition, :decision_strategy, :rule_based)

    Logger.debug("Executing conditional workflow with #{decision_strategy} decisions")

    case evaluate_workflow_condition(workflow_tree, execution_context, decision_strategy) do
      {:ok, selected_branch} ->
        execute_workflow_branch(selected_branch, execution_context, options)

      error ->
        error
    end
  end

  defp execute_pipeline_pattern(workflow_definition, execution_context, options) do
    # Pipeline: each stage's output becomes the next stage's input
    pipeline_stages = Map.get(workflow_definition, :pipeline_stages, [])

    Logger.debug("Executing pipeline workflow with #{length(pipeline_stages)} stages")

    Enum.reduce_while(pipeline_stages, {:ok, execution_context}, fn stage,
                                                                    {:ok, current_context} ->
      case execute_single_skill_action(stage, current_context) do
        {:ok, stage_result} ->
          # Pass result as context to next stage
          next_context = merge_context_with_result(current_context, stage_result)
          {:cont, {:ok, next_context}}

        {:error, reason} ->
          {:halt, {:error, "Pipeline failed at stage #{stage}: #{reason}"}}
      end
    end)
  end

  defp execute_scatter_gather_pattern(workflow_definition, execution_context, options) do
    # Scatter-Gather: distribute work, then gather and consolidate results
    scatter_tasks = Map.get(workflow_definition, :scatter_tasks, [])
    gather_strategy = Map.get(workflow_definition, :gather_strategy, :consolidate_all)

    Logger.debug("Executing scatter-gather workflow with #{length(scatter_tasks)} scatter tasks")

    # Scatter phase: distribute tasks
    scatter_results =
      scatter_tasks
      |> Enum.map(fn task ->
        Task.async(fn ->
          execute_single_skill_action(task, execution_context)
        end)
      end)
      |> Task.await_many(Keyword.get(options, :timeout, @default_timeout))

    # Gather phase: consolidate results
    case gather_scattered_results(scatter_results, gather_strategy, execution_context) do
      {:ok, consolidated_result} ->
        {:ok,
         %{
           scatter_results: scatter_results,
           consolidated_result: consolidated_result,
           gather_strategy: gather_strategy
         }}

      error ->
        error
    end
  end

  defp execute_single_skill_action(skill_action, execution_context) do
    case skill_action do
      %{type: :skill, module: skill_module, params: params} ->
        execute_skill(skill_module, params, execution_context)

      %{type: :action, module: action_module, params: params} ->
        execute_action(action_module, params, execution_context)

      %{type: :llm_assisted, description: description, params: params} ->
        execute_llm_assisted_task(description, params, execution_context)

      _ ->
        {:error, "Unknown skill/action type: #{inspect(skill_action)}"}
    end
  end

  defp execute_skill(skill_module, params, execution_context) do
    Logger.debug("Executing skill: #{skill_module}")

    try do
      # Create skill state from execution context
      skill_state = build_skill_state(execution_context)

      # Execute skill with appropriate function
      case determine_skill_function(skill_module, params) do
        {:ok, function_name} ->
          result = apply(skill_module, function_name, [params, skill_state])

          {:ok,
           %{
             skill_module: skill_module,
             function: function_name,
             result: result,
             execution_type: :skill,
             timestamp: DateTime.utc_now()
           }}

        {:error, reason} ->
          {:error, "Skill execution failed: #{reason}"}
      end
    rescue
      error ->
        {:error, "Skill execution error: #{Exception.message(error)}"}
    end
  end

  defp execute_action(action_module, params, execution_context) do
    Logger.debug("Executing action: #{action_module}")

    try do
      # Execute action using Jido.Action patterns
      case action_module.execute(params, execution_context) do
        {:ok, result} ->
          {:ok,
           %{
             action_module: action_module,
             result: result,
             execution_type: :action,
             timestamp: DateTime.utc_now()
           }}

        error ->
          error
      end
    rescue
      error ->
        {:error, "Action execution error: #{Exception.message(error)}"}
    end
  end

  defp execute_llm_assisted_task(description, params, execution_context) do
    Logger.debug("Executing LLM-assisted task: #{description}")

    # Use Universal LLM Provider System for task execution
    task_prompt = build_task_prompt(description, params, execution_context)

    case UniversalProviderService.complete(task_prompt, :orchestration, %{
           use_case: :task_execution,
           user_id: Map.get(execution_context, :user_id),
           specialized_features: [:cost_optimization, :agent_communication],
           max_tokens: 800,
           temperature: 0.4
         }) do
      {:ok, llm_response} ->
        {:ok,
         %{
           description: description,
           llm_result: llm_response.content,
           cost_usd: llm_response.cost_usd,
           execution_type: :llm_assisted,
           timestamp: DateTime.utc_now()
         }}

      error ->
        error
    end
  end

  defp validate_workflow_definition(workflow_definition) do
    required_fields = [:pattern]
    missing_fields = Enum.filter(required_fields, &(!Map.has_key?(workflow_definition, &1)))

    case missing_fields do
      [] ->
        if workflow_definition.pattern in @execution_patterns do
          validate_pattern_specific_fields(workflow_definition)
        else
          {:error, "Unknown execution pattern: #{workflow_definition.pattern}"}
        end

      fields ->
        {:error, "Missing required workflow fields: #{inspect(fields)}"}
    end
  end

  defp validate_pattern_specific_fields(workflow_definition) do
    pattern = workflow_definition.pattern

    case pattern do
      :parallel -> validate_skills_actions_field(workflow_definition, "Parallel")
      :sequential -> validate_skills_actions_field(workflow_definition, "Sequential")
      :conditional -> validate_workflow_tree_field(workflow_definition)
      :pipeline -> validate_pipeline_stages_field(workflow_definition)
      :scatter_gather -> validate_scatter_tasks_field(workflow_definition)
      _ -> :ok
    end
  end

  defp validate_skills_actions_field(workflow_definition, pattern_name) do
    if Map.has_key?(workflow_definition, :skills_actions) do
      :ok
    else
      {:error, "#{pattern_name} workflow missing skills_actions"}
    end
  end

  defp validate_workflow_tree_field(workflow_definition) do
    if Map.has_key?(workflow_definition, :workflow_tree) do
      :ok
    else
      {:error, "Conditional workflow missing workflow_tree"}
    end
  end

  defp validate_pipeline_stages_field(workflow_definition) do
    if Map.has_key?(workflow_definition, :pipeline_stages) do
      :ok
    else
      {:error, "Pipeline workflow missing pipeline_stages"}
    end
  end

  defp validate_scatter_tasks_field(workflow_definition) do
    if Map.has_key?(workflow_definition, :scatter_tasks) do
      :ok
    else
      {:error, "Scatter-gather workflow missing scatter_tasks"}
    end
  end

  defp build_workflow_definition(skills_actions, pattern, options) do
    base_definition = %{
      pattern: pattern,
      created_at: DateTime.utc_now(),
      timeout_ms: Keyword.get(options, :timeout, @default_timeout)
    }

    case pattern do
      :parallel ->
        {:ok,
         Map.merge(base_definition, %{
           skills_actions: skills_actions,
           aggregation_strategy: Keyword.get(options, :aggregation, :merge_results)
         })}

      :sequential ->
        {:ok,
         Map.merge(base_definition, %{
           skills_actions: skills_actions,
           context_passing: Keyword.get(options, :context_passing, :accumulate)
         })}

      _ ->
        {:ok, Map.put(base_definition, :skills_actions, skills_actions)}
    end
  end

  defp aggregate_parallel_results(results, aggregation_strategy) do
    case aggregation_strategy do
      :merge_results ->
        # Merge all successful results
        successful_results =
          Enum.filter(results, fn
            {:ok, _} -> true
            _ -> false
          end)

        merged_data =
          successful_results
          |> Enum.map(fn {:ok, result} -> result end)
          |> Enum.reduce(%{}, &Map.merge(&2, &1, fn _k, v1, v2 -> [v1, v2] end))

        %{
          aggregation_strategy: :merge_results,
          successful_count: length(successful_results),
          total_count: length(results),
          merged_results: merged_data
        }

      :collect_all ->
        # Collect all results including failures
        %{
          aggregation_strategy: :collect_all,
          all_results: results,
          successful_count: Enum.count(results, fn result -> match?({:ok, _}, result) end),
          total_count: length(results)
        }

      _ ->
        %{aggregation_strategy: aggregation_strategy, results: results}
    end
  end

  defp execute_sequential_chain(skills_actions, initial_context, context_passing) do
    {final_result, execution_chain} =
      Enum.reduce_while(
        skills_actions,
        {initial_context, []},
        &process_sequential_skill_action(&1, &2, context_passing)
      )

    case final_result do
      {:error, reason, chain} -> {:error, reason}
      {final_context, chain} -> {:ok, final_context, chain}
    end
  end

  defp process_sequential_skill_action(skill_action, {current_context, chain}, context_passing) do
    case execute_single_skill_action(skill_action, current_context) do
      {:ok, result} ->
        updated_chain = chain ++ [result]
        next_context = apply_context_passing_strategy(current_context, result, context_passing)
        {:cont, {next_context, updated_chain}}

      {:error, reason} ->
        {:halt, {:error, reason, chain}}
    end
  end

  defp apply_context_passing_strategy(current_context, result, context_passing) do
    case context_passing do
      :accumulate -> Map.merge(current_context, result)
      :replace -> result
      :pass_through -> current_context
      _ -> current_context
    end
  end

  defp evaluate_workflow_condition(workflow_tree, execution_context, decision_strategy) do
    condition = Map.get(workflow_tree, :condition)
    true_branch = Map.get(workflow_tree, :true_branch)
    false_branch = Map.get(workflow_tree, :false_branch)

    case decision_strategy do
      :rule_based ->
        if evaluate_rule_condition(condition, execution_context) do
          {:ok, true_branch}
        else
          {:ok, false_branch}
        end

      :llm_assisted ->
        # Use LLM for dynamic decision making
        get_llm_workflow_decision(condition, execution_context, workflow_tree)

      _ ->
        {:error, "Unknown decision strategy: #{decision_strategy}"}
    end
  end

  defp evaluate_rule_condition(condition, execution_context) do
    # Simple rule evaluation
    case condition do
      %{field: field, operator: operator, value: value} ->
        context_value = Map.get(execution_context, field)
        apply_operator(context_value, operator, value)

      _ ->
        false
    end
  end

  defp apply_operator(context_value, operator, expected_value) do
    case operator do
      :equals -> context_value == expected_value
      :greater_than -> context_value > expected_value
      :less_than -> context_value < expected_value
      :contains -> String.contains?(to_string(context_value), to_string(expected_value))
      _ -> false
    end
  end

  defp get_llm_workflow_decision(condition, execution_context, workflow_tree) do
    decision_prompt = """
    Workflow Decision Required:
    Condition: #{inspect(condition)}
    Context: #{inspect(execution_context)}

    Available branches:
    - True branch: #{inspect(Map.get(workflow_tree, :true_branch))}
    - False branch: #{inspect(Map.get(workflow_tree, :false_branch))}

    Please evaluate the condition and select the appropriate branch.
    Respond with: {"selected_branch": "true_branch" | "false_branch", "reasoning": "explanation"}
    """

    case UniversalProviderService.complete(decision_prompt, :orchestration, %{
           use_case: :workflow_decision,
           specialized_features: [:cost_optimization],
           max_tokens: 300,
           temperature: 0.2
         }) do
      {:ok, llm_response} ->
        parse_llm_decision(llm_response.content, workflow_tree)

      error ->
        error
    end
  end

  defp parse_llm_decision(llm_content, workflow_tree) do
    case Jason.decode(llm_content) do
      {:ok, %{"selected_branch" => "true_branch"}} ->
        {:ok, Map.get(workflow_tree, :true_branch)}

      {:ok, %{"selected_branch" => "false_branch"}} ->
        {:ok, Map.get(workflow_tree, :false_branch)}

      _ ->
        # Default to true branch if parsing fails
        {:ok, Map.get(workflow_tree, :true_branch)}
    end
  end

  defp execute_workflow_branch(branch_definition, execution_context, options) do
    case branch_definition do
      %{type: :skill_action} = skill_action ->
        execute_single_skill_action(skill_action, execution_context)

      %{type: :sub_workflow} = sub_workflow ->
        execute_workflow_async(generate_workflow_id(), sub_workflow, execution_context, options)

      _ ->
        {:error, "Unknown branch definition type"}
    end
  end

  defp gather_scattered_results(scatter_results, gather_strategy, execution_context) do
    case gather_strategy do
      :consolidate_all ->
        successful_results =
          Enum.filter(scatter_results, fn
            {:ok, _} -> true
            _ -> false
          end)

        {:ok,
         %{
           strategy: :consolidate_all,
           successful_results: successful_results,
           total_results: length(scatter_results),
           success_rate: length(successful_results) / length(scatter_results)
         }}

      :best_result ->
        best_result =
          scatter_results
          |> Enum.filter(fn result -> match?({:ok, _}, result) end)
          |> Enum.max_by(
            fn {:ok, result} ->
              Map.get(result, :score, 0) + Map.get(result, :confidence, 0)
            end,
            fn -> {:error, "No successful results"} end
          )

        case best_result do
          {:ok, result} -> {:ok, %{strategy: :best_result, best_result: result}}
          error -> error
        end

      _ ->
        {:ok, %{strategy: gather_strategy, raw_results: scatter_results}}
    end
  end

  # Helper functions

  defp generate_workflow_id do
    "wf_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp build_skill_state(execution_context) do
    %{
      agent_id: Map.get(execution_context, :agent_id, "orchestrator"),
      user_id: Map.get(execution_context, :user_id),
      project_id: Map.get(execution_context, :project_id),
      orchestration_context: execution_context
    }
  end

  defp determine_skill_function(skill_module, params) do
    # Determine appropriate function to call on skill module
    param_keys = Map.keys(params)

    # Simple heuristic based on parameter names
    cond do
      "experience" in param_keys -> {:ok, :track_experience}
      "entity" in param_keys -> {:ok, :analyze_entity}
      "threat" in param_keys -> {:ok, :detect_threat}
      "project" in param_keys -> {:ok, :manage_project}
      # Default function
      true -> {:ok, :execute}
    end
  end

  defp build_task_prompt(description, params, execution_context) do
    """
    Task: #{description}

    Parameters: #{inspect(params)}
    Context: #{inspect(Map.take(execution_context, [:user_id, :project_id, :agent_id]))}

    Please execute this task and provide the result in a structured format.
    """
  end

  defp merge_context_with_result(context, result) do
    case result do
      result when is_map(result) -> Map.merge(context, result)
      _ -> Map.put(context, :previous_result, result)
    end
  end

  defp extract_context_evolution(execution_chain) do
    execution_chain
    |> Enum.with_index()
    |> Enum.map(fn {step_result, index} ->
      %{
        step: index,
        timestamp: Map.get(step_result, :timestamp),
        execution_type: Map.get(step_result, :execution_type),
        context_changes: extract_context_changes(step_result)
      }
    end)
  end

  defp extract_context_changes(step_result) do
    # Extract what changed in the context from this step
    case step_result.execution_type do
      :skill -> %{skill_executed: step_result.skill_module}
      :action -> %{action_executed: step_result.action_module}
      :llm_assisted -> %{llm_task: step_result.description}
      _ -> %{}
    end
  end

  defp find_workflow_by_task_ref(active_workflows, ref) do
    active_workflows
    |> Enum.find(fn {_id, workflow_info} ->
      workflow_info.task.ref == ref
    end)
  end

  defp record_workflow_completion(history, workflow_id, workflow_info, result) do
    completion_record = %{
      workflow_id: workflow_id,
      definition: workflow_info.definition,
      started_at: workflow_info.started_at,
      completed_at: DateTime.utc_now(),
      execution_time_ms: result.execution_time_ms,
      success: result.success,
      pattern: result.pattern
    }

    # Keep last 1000 workflow executions
    updated_history =
      [completion_record | Map.get(history, :recent_executions, [])]
      |> Enum.take(1000)

    Map.put(history, :recent_executions, updated_history)
  end

  defp update_pattern_stats(stats, pattern) do
    pattern_key =
      case pattern do
        :parallel -> :parallel_executions
        :sequential -> :sequential_executions
        _ -> :other_pattern_executions
      end

    Map.update(stats, pattern_key, 1, &(&1 + 1))
  end

  defp count_skills_in_workflow(workflow_definition) do
    skills_actions = Map.get(workflow_definition, :skills_actions, [])
    Enum.count(skills_actions, &(Map.get(&1, :type) == :skill))
  end

  defp count_actions_in_workflow(workflow_definition) do
    skills_actions = Map.get(workflow_definition, :skills_actions, [])
    Enum.count(skills_actions, &(Map.get(&1, :type) == :action))
  end

  defp calculate_workflow_success_rate(stats) do
    if stats.workflows_executed > 0 do
      stats.successful_workflows / stats.workflows_executed
    else
      0.0
    end
  end

  defp calculate_avg_completion_time(execution_history) do
    recent_executions = Map.get(execution_history, :recent_executions, [])

    if Enum.empty?(recent_executions) do
      0
    else
      total_time = Enum.reduce(recent_executions, 0, &(&1.execution_time_ms + &2))
      div(total_time, length(recent_executions))
    end
  end

  defp get_most_used_patterns(execution_history) do
    recent_executions = Map.get(execution_history, :recent_executions, [])

    recent_executions
    |> Enum.map(& &1.pattern)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_pattern, count} -> count end, :desc)
    |> Enum.take(3)
  end

  defp analyze_performance_trends(execution_history) do
    recent_executions = Map.get(execution_history, :recent_executions, [])

    if length(recent_executions) < 5 do
      %{trend: :insufficient_data}
    else
      recent_times = Enum.take(recent_executions, 5) |> Enum.map(& &1.execution_time_ms)
      older_times = Enum.slice(recent_executions, 5, 5) |> Enum.map(& &1.execution_time_ms)

      recent_avg = Enum.sum(recent_times) / length(recent_times)

      older_avg =
        if Enum.empty?(older_times),
          do: recent_avg,
          else: Enum.sum(older_times) / length(older_times)

      trend =
        cond do
          recent_avg < older_avg * 0.9 -> :improving
          recent_avg > older_avg * 1.1 -> :degrading
          true -> :stable
        end

      %{
        trend: trend,
        recent_avg_ms: recent_avg,
        older_avg_ms: older_avg
      }
    end
  end

  defp get_llm_workflow_optimization(workflow_definition, performance_history, user_id) do
    optimization_prompt = """
    Workflow Optimization Analysis:

    Current Workflow: #{inspect(workflow_definition)}
    Performance History: #{inspect(performance_history)}

    Please analyze this workflow and suggest optimizations for:
    1. Execution time reduction
    2. Resource efficiency improvement
    3. Error handling enhancement
    4. Parallel execution opportunities

    Respond with: {"optimizations": [...], "expected_improvement": 0.25, "reasoning": "..."}
    """

    case UniversalProviderService.complete(optimization_prompt, :orchestration, %{
           use_case: :workflow_optimization,
           user_id: user_id,
           specialized_features: [:cost_optimization],
           max_tokens: 800,
           temperature: 0.3
         }) do
      {:ok, llm_response} ->
        parse_llm_optimization(llm_response.content)

      error ->
        error
    end
  end

  defp parse_llm_optimization(llm_content) do
    case Jason.decode(llm_content) do
      {:ok,
       %{
         "optimizations" => optimizations,
         "expected_improvement" => improvement,
         "reasoning" => reasoning
       }} ->
        {:ok,
         %{
           optimizations: optimizations,
           expected_improvement: improvement,
           reasoning: reasoning,
           optimization_source: :llm_assisted
         }}

      _ ->
        {:ok,
         %{
           optimizations: ["Consider parallel execution where possible"],
           expected_improvement: 0.1,
           reasoning: llm_content,
           optimization_source: :llm_text_fallback
         }}
    end
  end

  defp generate_fallback_optimization(workflow_definition, performance_history) do
    # Simple fallback optimization
    pattern = workflow_definition.pattern

    optimizations =
      case pattern do
        :sequential -> ["Consider converting independent steps to parallel execution"]
        :parallel -> ["Consider reducing number of parallel tasks if resource-constrained"]
        _ -> ["Monitor execution times and optimize bottlenecks"]
      end

    %{
      optimizations: optimizations,
      expected_improvement: 0.05,
      reasoning: "Simple rule-based optimization suggestions",
      optimization_source: :rule_based
    }
  end
end
