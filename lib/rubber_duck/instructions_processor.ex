defmodule RubberDuck.InstructionsProcessor do
  @moduledoc """
  Workflow composition and instruction processing system for autonomous agents.

  Provides capabilities for:
  - Instruction normalization and validation
  - Workflow composition from Instructions
  - Error handling and compensation
  - Instruction optimization and caching
  """

  use GenServer
  require Logger

  @type instruction_id :: String.t()
  @type workflow_id :: String.t()
  @type agent_id :: String.t()
  @type instruction :: %{
          id: instruction_id(),
          type: atom(),
          action: String.t(),
          parameters: map(),
          dependencies: [instruction_id()],
          timeout: integer(),
          retry_policy: map(),
          compensation: map() | nil,
          created_at: DateTime.t()
        }
  @type workflow :: %{
          id: workflow_id(),
          name: String.t(),
          instructions: [instruction()],
          execution_order: [instruction_id()],
          status: atom(),
          created_at: DateTime.t(),
          metadata: map()
        }

  defstruct [
    :active_workflows,
    :instruction_cache,
    :execution_history,
    :optimization_rules,
    :compensation_handlers,
    :normalization_rules
  ]

  ## Client API

  @doc """
  Start the Instructions Processor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Process a single instruction.
  """
  def process_instruction(instruction_spec, agent_id) do
    GenServer.call(__MODULE__, {:process_instruction, instruction_spec, agent_id})
  end

  @doc """
  Compose a workflow from multiple instructions.
  """
  def compose_workflow(workflow_spec) do
    GenServer.call(__MODULE__, {:compose_workflow, workflow_spec})
  end

  @doc """
  Execute a composed workflow.
  """
  def execute_workflow(workflow_id, agent_id) do
    GenServer.call(__MODULE__, {:execute_workflow, workflow_id, agent_id})
  end

  @doc """
  Normalize an instruction to standard format.
  """
  def normalize_instruction(raw_instruction) do
    GenServer.call(__MODULE__, {:normalize_instruction, raw_instruction})
  end

  @doc """
  Optimize a workflow for better performance.
  """
  def optimize_workflow(workflow_id) do
    GenServer.call(__MODULE__, {:optimize_workflow, workflow_id})
  end

  @doc """
  Get execution status of a workflow.
  """
  def get_workflow_status(workflow_id) do
    GenServer.call(__MODULE__, {:get_workflow_status, workflow_id})
  end

  @doc """
  Cancel a running workflow.
  """
  def cancel_workflow(workflow_id) do
    GenServer.call(__MODULE__, {:cancel_workflow, workflow_id})
  end

  @doc """
  Get cached instruction if available.
  """
  def get_cached_instruction(instruction_hash) do
    GenServer.call(__MODULE__, {:get_cached_instruction, instruction_hash})
  end

  ## Server Implementation

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      active_workflows: %{},
      instruction_cache: %{},
      execution_history: [],
      optimization_rules: initialize_optimization_rules(),
      compensation_handlers: initialize_compensation_handlers(),
      normalization_rules: initialize_normalization_rules()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:process_instruction, instruction_spec, agent_id}, _from, state) do
    case normalize_and_validate_instruction(instruction_spec, state) do
      {:ok, normalized_instruction} ->
        {:ok, result, new_state} =
          execute_single_instruction(normalized_instruction, agent_id, state)

        {:reply, {:ok, result}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:compose_workflow, workflow_spec}, _from, state) do
    case compose_workflow_internal(workflow_spec, state) do
      {:ok, workflow, new_state} ->
        {:reply, {:ok, workflow.id}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:execute_workflow, workflow_id, agent_id}, _from, state) do
    case execute_workflow_internal(workflow_id, agent_id, state) do
      {:ok, execution_result, new_state} ->
        {:reply, {:ok, execution_result}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:normalize_instruction, raw_instruction}, _from, state) do
    case normalize_instruction_internal(raw_instruction, state) do
      {:ok, normalized} ->
        {:reply, {:ok, normalized}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:optimize_workflow, workflow_id}, _from, state) do
    case optimize_workflow_internal(workflow_id, state) do
      {:ok, optimized_workflow, new_state} ->
        {:reply, {:ok, optimized_workflow}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_workflow_status, workflow_id}, _from, state) do
    case Map.get(state.active_workflows, workflow_id) do
      nil ->
        {:reply, {:error, :workflow_not_found}, state}

      workflow ->
        {:reply, {:ok, workflow.status}, state}
    end
  end

  @impl true
  def handle_call({:cancel_workflow, workflow_id}, _from, state) do
    case cancel_workflow_internal(workflow_id, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_cached_instruction, instruction_hash}, _from, state) do
    case Map.get(state.instruction_cache, instruction_hash) do
      nil ->
        {:reply, {:error, :not_cached}, state}

      cached_instruction ->
        {:reply, {:ok, cached_instruction}, state}
    end
  end

  ## Internal Functions

  defp normalize_and_validate_instruction(instruction_spec, state) do
    with {:ok, normalized} <- normalize_instruction_internal(instruction_spec, state),
         :ok <- validate_instruction(normalized) do
      {:ok, normalized}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_instruction_internal(raw_instruction, state) do
    # Apply normalization rules
    Enum.reduce(state.normalization_rules, {:ok, raw_instruction}, fn rule, {:ok, acc} ->
      apply_normalization_rule(rule, acc)
    end)
  end

  defp apply_normalization_rule(rule, instruction) do
    case rule.type do
      :ensure_id ->
        if Map.has_key?(instruction, :id) do
          {:ok, instruction}
        else
          {:ok, Map.put(instruction, :id, generate_instruction_id())}
        end

      :ensure_timeout ->
        if Map.has_key?(instruction, :timeout) do
          {:ok, instruction}
        else
          {:ok, Map.put(instruction, :timeout, rule.default_timeout)}
        end

      :normalize_action ->
        normalized_action = normalize_action_format(instruction[:action])
        {:ok, Map.put(instruction, :action, normalized_action)}

      :ensure_retry_policy ->
        if Map.has_key?(instruction, :retry_policy) do
          {:ok, instruction}
        else
          {:ok, Map.put(instruction, :retry_policy, rule.default_retry_policy)}
        end

      _ ->
        {:ok, instruction}
    end
  end

  defp normalize_action_format(action) when is_binary(action) do
    action
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_.]/, "_")
  end

  defp normalize_action_format(action), do: action

  defp validate_instruction(instruction) do
    required_fields = [:id, :type, :action, :parameters]
    missing_fields = Enum.reject(required_fields, &Map.has_key?(instruction, &1))

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, {:missing_required_fields, missing_fields}}
    end
  end

  defp execute_single_instruction(instruction, agent_id, state) do
    # Check cache first
    instruction_hash = generate_instruction_hash(instruction)

    case check_instruction_cache(instruction_hash, state) do
      {:hit, cached_result} ->
        Logger.info("Cache hit for instruction #{instruction.id}")
        {:ok, cached_result, state}

      :miss ->
        case perform_instruction_execution(instruction, agent_id, state) do
          {:ok, result, new_state} ->
            # Cache the result
            final_state = cache_instruction_result(instruction_hash, result, new_state)
            {:ok, result, final_state}
        end
    end
  end

  defp check_instruction_cache(instruction_hash, state) do
    case Map.get(state.instruction_cache, instruction_hash) do
      nil ->
        :miss

      cached_data ->
        if cache_entry_valid?(cached_data) do
          {:hit, cached_data.result}
        else
          :miss
        end
    end
  end

  defp cache_entry_valid?(cached_data) do
    expiry_time = DateTime.add(cached_data.cached_at, cached_data.ttl, :second)
    DateTime.compare(DateTime.utc_now(), expiry_time) == :lt
  end

  defp perform_instruction_execution(instruction, agent_id, _state) do
    # Simulate instruction execution
    Logger.info("Executing instruction #{instruction.id} for agent #{agent_id}")

    case instruction.type do
      :skill_invocation ->
        execute_skill_instruction(instruction, agent_id)

      :data_operation ->
        execute_data_instruction(instruction, agent_id)

      :control_flow ->
        execute_control_instruction(instruction, agent_id)

      :communication ->
        execute_communication_instruction(instruction, agent_id)

      _ ->
        {:ok, %{status: :completed, result: "Instruction executed successfully"}, %{}}
    end
  end

  defp execute_skill_instruction(instruction, agent_id) do
    skill_id = instruction.parameters[:skill_id]
    _skill_params = instruction.parameters[:skill_params] || %{}

    # Simulate skill execution
    result = %{
      skill_id: skill_id,
      agent_id: agent_id,
      execution_time: :rand.uniform(1000),
      status: :completed,
      output: "Skill execution result"
    }

    {:ok, result, %{}}
  end

  defp execute_data_instruction(instruction, agent_id) do
    operation = instruction.parameters[:operation]

    # Simulate data operation
    result = %{
      operation: operation,
      agent_id: agent_id,
      affected_records: :rand.uniform(100),
      status: :completed
    }

    {:ok, result, %{}}
  end

  defp execute_control_instruction(instruction, agent_id) do
    control_type = instruction.parameters[:control_type]

    # Simulate control flow instruction
    result = %{
      control_type: control_type,
      agent_id: agent_id,
      status: :completed,
      next_instruction: instruction.parameters[:next_instruction]
    }

    {:ok, result, %{}}
  end

  defp execute_communication_instruction(instruction, agent_id) do
    message_type = instruction.parameters[:message_type]
    target = instruction.parameters[:target]

    # Simulate communication instruction
    result = %{
      message_type: message_type,
      source_agent: agent_id,
      target: target,
      status: :sent,
      timestamp: DateTime.utc_now()
    }

    {:ok, result, %{}}
  end

  defp cache_instruction_result(instruction_hash, result, state) do
    cache_entry = %{
      result: result,
      cached_at: DateTime.utc_now(),
      # 1 hour TTL
      ttl: 3600
    }

    new_cache = Map.put(state.instruction_cache, instruction_hash, cache_entry)
    %{state | instruction_cache: new_cache}
  end

  defp compose_workflow_internal(workflow_spec, state) do
    with :ok <- validate_workflow_spec(workflow_spec),
         {:ok, normalized_instructions} <-
           normalize_workflow_instructions(workflow_spec.instructions, state),
         {:ok, execution_order} <- calculate_execution_order(normalized_instructions),
         {:ok, workflow} <-
           create_workflow(workflow_spec, normalized_instructions, execution_order) do
      new_state = %{
        state
        | active_workflows: Map.put(state.active_workflows, workflow.id, workflow)
      }

      {:ok, workflow, new_state}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_workflow_spec(workflow_spec) do
    required_fields = [:name, :instructions]
    missing_fields = Enum.reject(required_fields, &Map.has_key?(workflow_spec, &1))

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, {:missing_workflow_fields, missing_fields}}
    end
  end

  defp normalize_workflow_instructions(instructions, state) do
    Enum.reduce_while(instructions, {:ok, []}, fn instruction, {:ok, acc} ->
      case normalize_instruction_internal(instruction, state) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized_instructions} -> {:ok, Enum.reverse(normalized_instructions)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp calculate_execution_order(instructions) do
    # Simple topological sort based on dependencies
    instruction_map = Map.new(instructions, fn inst -> {inst.id, inst} end)

    case topological_sort(instructions, instruction_map) do
      {:ok, sorted_ids} -> {:ok, sorted_ids}
      {:error, reason} -> {:error, reason}
    end
  end

  defp topological_sort(instructions, instruction_map) do
    # Simple implementation - in production would use proper topological sort
    sorted_ids =
      instructions
      |> Enum.sort_by(fn inst -> length(inst[:dependencies] || []) end)
      |> Enum.map(& &1.id)

    # Check for circular dependencies
    case detect_circular_dependencies(instructions, instruction_map) do
      :ok -> {:ok, sorted_ids}
      {:error, reason} -> {:error, reason}
    end
  end

  defp detect_circular_dependencies(instructions, instruction_map) do
    # Simple cycle detection
    Enum.reduce_while(instructions, :ok, fn instruction, :ok ->
      case check_instruction_cycles(instruction.id, instruction_map, MapSet.new()) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp check_instruction_cycles(instruction_id, instruction_map, visited) do
    if MapSet.member?(visited, instruction_id) do
      {:error, {:circular_dependency, instruction_id}}
    else
      check_dependencies_for_cycles(instruction_id, instruction_map, visited)
    end
  end

  defp check_dependencies_for_cycles(instruction_id, instruction_map, visited) do
    instruction = Map.get(instruction_map, instruction_id)
    dependencies = instruction[:dependencies] || []
    new_visited = MapSet.put(visited, instruction_id)

    Enum.reduce_while(dependencies, :ok, fn dep_id, :ok ->
      case check_instruction_cycles(dep_id, instruction_map, new_visited) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp create_workflow(workflow_spec, instructions, execution_order) do
    workflow = %{
      id: generate_workflow_id(),
      name: workflow_spec.name,
      instructions: instructions,
      execution_order: execution_order,
      status: :ready,
      created_at: DateTime.utc_now(),
      metadata: Map.get(workflow_spec, :metadata, %{})
    }

    {:ok, workflow}
  end

  defp execute_workflow_internal(workflow_id, agent_id, state) do
    case Map.get(state.active_workflows, workflow_id) do
      nil ->
        {:error, :workflow_not_found}

      workflow ->
        case workflow.status do
          :ready ->
            execute_workflow_instructions(workflow, agent_id, state)

          :running ->
            {:error, :workflow_already_running}

          :completed ->
            {:error, :workflow_already_completed}

          :failed ->
            {:error, :workflow_previously_failed}
        end
    end
  end

  defp execute_workflow_instructions(workflow, agent_id, state) do
    # Mark workflow as running
    updated_workflow = %{workflow | status: :running}

    state_with_running = %{
      state
      | active_workflows: Map.put(state.active_workflows, workflow.id, updated_workflow)
    }

    instruction_map = Map.new(workflow.instructions, fn inst -> {inst.id, inst} end)

    case execute_instructions_in_order(
           workflow.execution_order,
           instruction_map,
           agent_id,
           state_with_running
         ) do
      {:ok, execution_results, final_state} ->
        # Mark workflow as completed
        completed_workflow = %{updated_workflow | status: :completed}

        final_state_with_completed = %{
          final_state
          | active_workflows:
              Map.put(final_state.active_workflows, workflow.id, completed_workflow)
        }

        execution_result = %{
          workflow_id: workflow.id,
          status: :completed,
          instruction_results: execution_results,
          completed_at: DateTime.utc_now()
        }

        {:ok, execution_result, final_state_with_completed}

      {:error, reason} ->
        # Mark workflow as failed
        failed_workflow = %{updated_workflow | status: :failed}

        failed_state = %{
          state_with_running
          | active_workflows:
              Map.put(state_with_running.active_workflows, workflow.id, failed_workflow)
        }

        {:error, reason, failed_state}
    end
  end

  defp execute_instructions_in_order(execution_order, instruction_map, agent_id, state) do
    Enum.reduce(execution_order, {:ok, %{}, state}, fn instruction_id,
                                                       {:ok, results, acc_state} ->
      instruction = Map.get(instruction_map, instruction_id)

      {:ok, result, new_state} = execute_single_instruction(instruction, agent_id, acc_state)
      new_results = Map.put(results, instruction_id, result)
      {:ok, new_results, new_state}
    end)
  end

  defp optimize_workflow_internal(workflow_id, state) do
    case Map.get(state.active_workflows, workflow_id) do
      nil ->
        {:error, :workflow_not_found}

      workflow ->
        case apply_optimization_rules(workflow, state) do
          {:ok, optimized_workflow} ->
            new_state = %{
              state
              | active_workflows: Map.put(state.active_workflows, workflow_id, optimized_workflow)
            }

            {:ok, optimized_workflow, new_state}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp apply_optimization_rules(workflow, state) do
    Enum.reduce(state.optimization_rules, {:ok, workflow}, fn rule, {:ok, acc_workflow} ->
      apply_optimization_rule(rule, acc_workflow)
    end)
  end

  defp apply_optimization_rule(rule, workflow) do
    case rule.type do
      :remove_redundant_instructions ->
        remove_redundant_instructions(workflow)

      :parallelize_independent_instructions ->
        parallelize_independent_instructions(workflow)

      :optimize_execution_order ->
        optimize_execution_order(workflow)

      _ ->
        {:ok, workflow}
    end
  end

  defp remove_redundant_instructions(workflow) do
    # Simple redundancy removal based on identical actions
    unique_instructions =
      workflow.instructions
      |> Enum.uniq_by(fn inst -> {inst.action, inst.parameters} end)

    updated_workflow = %{workflow | instructions: unique_instructions}
    {:ok, updated_workflow}
  end

  defp parallelize_independent_instructions(workflow) do
    # Mark independent instructions for parallel execution
    # This is a simplified implementation
    {:ok, workflow}
  end

  defp optimize_execution_order(workflow) do
    # Reorder instructions for better performance
    # This is a simplified implementation
    {:ok, workflow}
  end

  defp cancel_workflow_internal(workflow_id, state) do
    case Map.get(state.active_workflows, workflow_id) do
      nil ->
        {:error, :workflow_not_found}

      workflow ->
        cancelled_workflow = %{workflow | status: :cancelled}

        new_state = %{
          state
          | active_workflows: Map.put(state.active_workflows, workflow_id, cancelled_workflow)
        }

        {:ok, new_state}
    end
  end

  defp generate_instruction_id do
    "inst_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp generate_workflow_id do
    "wf_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp generate_instruction_hash(instruction) do
    content = %{
      type: instruction.type,
      action: instruction.action,
      parameters: instruction.parameters
    }

    :crypto.hash(:sha256, :erlang.term_to_binary(content))
    |> Base.encode16(case: :lower)
  end

  defp initialize_optimization_rules do
    [
      %{type: :remove_redundant_instructions, priority: 1},
      %{type: :parallelize_independent_instructions, priority: 2},
      %{type: :optimize_execution_order, priority: 3}
    ]
  end

  defp initialize_compensation_handlers do
    [
      %{type: :retry, handler: &retry_compensation/3},
      %{type: :alternative_action, handler: &alternative_action_compensation/3},
      %{type: :rollback, handler: &rollback_compensation/3}
    ]
  end

  defp initialize_normalization_rules do
    [
      %{type: :ensure_id, priority: 1},
      %{type: :ensure_timeout, priority: 2, default_timeout: 30_000},
      %{type: :normalize_action, priority: 3},
      %{
        type: :ensure_retry_policy,
        priority: 4,
        default_retry_policy: %{max_retries: 3, backoff: :exponential}
      }
    ]
  end

  # Compensation handler functions
  defp retry_compensation(_instruction, _agent_id, _state) do
    {:ok, %{compensation_type: :retry}}
  end

  defp alternative_action_compensation(_instruction, _agent_id, _state) do
    {:ok, %{compensation_type: :alternative_action}}
  end

  defp rollback_compensation(_instruction, _agent_id, _state) do
    {:ok, %{compensation_type: :rollback}}
  end
end
