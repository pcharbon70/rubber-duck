defmodule RubberDuck.DirectivesEngine do
  @moduledoc """
  Runtime behavior modification system for autonomous agents.

  Provides capabilities for:
  - Directive validation and routing
  - Runtime behavior modification
  - Agent capability management
  - Directive history and rollback
  """

  use GenServer
  require Logger

  @type directive_id :: String.t()
  @type agent_id :: String.t()
  @type directive :: %{
          id: directive_id(),
          type: atom(),
          target: agent_id() | :all,
          parameters: map(),
          priority: integer(),
          expires_at: DateTime.t() | nil,
          created_at: DateTime.t(),
          created_by: String.t()
        }
  @type directive_result :: {:ok, map()} | {:error, term()}

  defstruct [
    :active_directives,
    :directive_history,
    :agent_capabilities,
    :routing_rules,
    :rollback_points,
    :validation_rules
  ]

  ## Client API

  @doc """
  Start the Directives Engine.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Issue a directive to modify agent behavior.
  """
  def issue_directive(directive_spec) do
    GenServer.call(__MODULE__, {:issue_directive, directive_spec})
  end

  @doc """
  Revoke an active directive.
  """
  def revoke_directive(directive_id) do
    GenServer.call(__MODULE__, {:revoke_directive, directive_id})
  end

  @doc """
  Get active directives for a specific agent.
  """
  def get_agent_directives(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_directives, agent_id})
  end

  @doc """
  Update agent capabilities.
  """
  def update_agent_capabilities(agent_id, capabilities) do
    GenServer.call(__MODULE__, {:update_agent_capabilities, agent_id, capabilities})
  end

  @doc """
  Create a rollback point for current directive state.
  """
  def create_rollback_point(label) do
    GenServer.call(__MODULE__, {:create_rollback_point, label})
  end

  @doc """
  Rollback to a previous directive state.
  """
  def rollback_to_point(rollback_id) do
    GenServer.call(__MODULE__, {:rollback_to_point, rollback_id})
  end

  @doc """
  Validate a directive before issuing.
  """
  def validate_directive(directive_spec) do
    GenServer.call(__MODULE__, {:validate_directive, directive_spec})
  end

  @doc """
  Get directive execution history.
  """
  def get_directive_history(filters \\ %{}) do
    GenServer.call(__MODULE__, {:get_directive_history, filters})
  end

  ## Server Implementation

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      active_directives: %{},
      directive_history: [],
      agent_capabilities: %{},
      routing_rules: initialize_routing_rules(),
      rollback_points: %{},
      validation_rules: initialize_validation_rules()
    }

    # Schedule periodic cleanup of expired directives
    schedule_cleanup()

    {:ok, state}
  end

  @impl true
  def handle_call({:issue_directive, directive_spec}, _from, state) do
    case validate_and_create_directive(directive_spec, state) do
      {:ok, directive} ->
        {:ok, execution_result, new_state} = route_and_execute_directive(directive, state)
        final_state = record_directive_execution(directive, execution_result, new_state)
        {:reply, {:ok, directive.id}, final_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:revoke_directive, directive_id}, _from, state) do
    case revoke_directive_internal(directive_id, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_agent_directives, agent_id}, _from, state) do
    directives = get_agent_directives_internal(agent_id, state)
    {:reply, {:ok, directives}, state}
  end

  @impl true
  def handle_call({:update_agent_capabilities, agent_id, capabilities}, _from, state) do
    new_state = %{
      state
      | agent_capabilities: Map.put(state.agent_capabilities, agent_id, capabilities)
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:create_rollback_point, label}, _from, state) do
    rollback_id = generate_rollback_id()

    rollback_point = %{
      id: rollback_id,
      label: label,
      timestamp: DateTime.utc_now(),
      active_directives: state.active_directives,
      agent_capabilities: state.agent_capabilities
    }

    new_state = %{
      state
      | rollback_points: Map.put(state.rollback_points, rollback_id, rollback_point)
    }

    {:reply, {:ok, rollback_id}, new_state}
  end

  @impl true
  def handle_call({:rollback_to_point, rollback_id}, _from, state) do
    case Map.get(state.rollback_points, rollback_id) do
      nil ->
        {:reply, {:error, :rollback_point_not_found}, state}

      rollback_point ->
        {:ok, new_state} = execute_rollback(rollback_point, state)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:validate_directive, directive_spec}, _from, state) do
    case validate_directive_internal(directive_spec, state) do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_directive_history, filters}, _from, state) do
    filtered_history = filter_directive_history(state.directive_history, filters)
    {:reply, {:ok, filtered_history}, state}
  end

  @impl true
  def handle_info(:cleanup_expired_directives, state) do
    new_state = cleanup_expired_directives(state)
    schedule_cleanup()
    {:noreply, new_state}
  end

  ## Internal Functions

  defp validate_and_create_directive(directive_spec, state) do
    with :ok <- validate_directive_internal(directive_spec, state),
         {:ok, directive} <- create_directive(directive_spec) do
      {:ok, directive}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_directive_internal(directive_spec, state) do
    with :ok <- validate_required_fields(directive_spec),
         :ok <- validate_directive_type(directive_spec),
         :ok <- validate_target_agent(directive_spec, state),
         :ok <- validate_parameters(directive_spec, state),
         :ok <- validate_custom_rules(directive_spec, state) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_required_fields(directive_spec) do
    required_fields = [:type, :target, :parameters]
    missing_fields = Enum.reject(required_fields, &Map.has_key?(directive_spec, &1))

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, {:missing_required_fields, missing_fields}}
    end
  end

  defp validate_directive_type(directive_spec) do
    valid_types = [
      :behavior_modification,
      :capability_update,
      :skill_configuration,
      :monitoring_adjustment,
      :learning_parameter_update,
      :security_policy_change,
      :performance_optimization,
      :emergency_response
    ]

    if directive_spec.type in valid_types do
      :ok
    else
      {:error, {:invalid_directive_type, directive_spec.type}}
    end
  end

  defp validate_target_agent(directive_spec, state) do
    case directive_spec.target do
      :all ->
        :ok

      agent_id when is_binary(agent_id) ->
        if Map.has_key?(state.agent_capabilities, agent_id) do
          :ok
        else
          {:error, {:target_agent_not_found, agent_id}}
        end

      _ ->
        {:error, :invalid_target_format}
    end
  end

  defp validate_parameters(directive_spec, state) do
    case directive_spec.type do
      :behavior_modification ->
        validate_behavior_modification_params(directive_spec.parameters)

      :capability_update ->
        validate_capability_update_params(directive_spec.parameters, state)

      :skill_configuration ->
        validate_skill_configuration_params(directive_spec.parameters)

      _ ->
        # Generic validation passed
        :ok
    end
  end

  defp validate_behavior_modification_params(parameters) do
    required_params = [:behavior_type, :modification_type]

    if Enum.all?(required_params, &Map.has_key?(parameters, &1)) do
      :ok
    else
      {:error, :invalid_behavior_modification_parameters}
    end
  end

  defp validate_capability_update_params(parameters, _state) do
    if Map.has_key?(parameters, :capabilities) and is_list(parameters.capabilities) do
      :ok
    else
      {:error, :invalid_capability_update_parameters}
    end
  end

  defp validate_skill_configuration_params(parameters) do
    required_params = [:skill_id, :configuration]

    if Enum.all?(required_params, &Map.has_key?(parameters, &1)) do
      :ok
    else
      {:error, :invalid_skill_configuration_parameters}
    end
  end

  defp validate_custom_rules(directive_spec, state) do
    # Apply custom validation rules from state.validation_rules
    Enum.reduce_while(state.validation_rules, :ok, fn rule, :ok ->
      case apply_validation_rule(rule, directive_spec, state) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp apply_validation_rule(rule, directive_spec, _state) do
    # Apply specific validation rule
    case rule.type do
      :priority_limit ->
        if Map.get(directive_spec, :priority, 5) <= rule.max_priority do
          :ok
        else
          {:error, {:priority_too_high, rule.max_priority}}
        end

      :target_restriction ->
        if directive_spec.target in rule.allowed_targets do
          :ok
        else
          {:error, {:target_not_allowed, directive_spec.target}}
        end

      _ ->
        :ok
    end
  end

  defp create_directive(directive_spec) do
    directive = %{
      id: generate_directive_id(),
      type: directive_spec.type,
      target: directive_spec.target,
      parameters: directive_spec.parameters,
      priority: Map.get(directive_spec, :priority, 5),
      expires_at: Map.get(directive_spec, :expires_at),
      created_at: DateTime.utc_now(),
      created_by: Map.get(directive_spec, :created_by, "system")
    }

    {:ok, directive}
  end

  defp route_and_execute_directive(directive, state) do
    case determine_execution_strategy(directive, state) do
      {:immediate, target_agents} ->
        execute_immediate_directive(directive, target_agents, state)

      {:queued, target_agents} ->
        queue_directive_for_execution(directive, target_agents, state)

      {:broadcast, target_agents} ->
        broadcast_directive_to_agents(directive, target_agents, state)
    end
  end

  defp determine_execution_strategy(directive, state) do
    target_agents = resolve_target_agents(directive.target, state)

    cond do
      directive.type in [:emergency_response] ->
        {:immediate, target_agents}

      directive.priority >= 8 ->
        {:immediate, target_agents}

      directive.target == :all ->
        {:broadcast, target_agents}

      true ->
        {:queued, target_agents}
    end
  end

  defp resolve_target_agents(:all, state) do
    Map.keys(state.agent_capabilities)
  end

  defp resolve_target_agents(agent_id, _state) when is_binary(agent_id) do
    [agent_id]
  end

  defp execute_immediate_directive(directive, target_agents, state) do
    execution_results =
      Enum.map(target_agents, fn agent_id ->
        {agent_id, execute_directive_on_agent(directive, agent_id, state)}
      end)
      |> Map.new()

    new_state = add_active_directive(directive, state)

    {:ok, execution_results, new_state}
  end

  defp queue_directive_for_execution(directive, _target_agents, state) do
    # In a real implementation, this would add to an execution queue
    new_state = add_active_directive(directive, state)
    {:ok, %{status: :queued}, new_state}
  end

  defp broadcast_directive_to_agents(directive, target_agents, state) do
    # Broadcast directive to all target agents
    broadcast_results =
      Enum.map(target_agents, fn agent_id ->
        {agent_id, {:ok, :directive_received}}
      end)
      |> Map.new()

    new_state = add_active_directive(directive, state)

    {:ok, broadcast_results, new_state}
  end

  defp execute_directive_on_agent(directive, agent_id, state) do
    agent_capabilities = Map.get(state.agent_capabilities, agent_id, [])

    case directive.type do
      :behavior_modification ->
        modify_agent_behavior(agent_id, directive.parameters, agent_capabilities)

      :capability_update ->
        update_agent_capabilities_internal(agent_id, directive.parameters.capabilities)

      :skill_configuration ->
        configure_agent_skill(agent_id, directive.parameters)

      _ ->
        {:ok, :directive_acknowledged}
    end
  end

  defp modify_agent_behavior(agent_id, parameters, _capabilities) do
    # Simulate behavior modification
    Logger.info("Modifying behavior for agent #{agent_id}: #{inspect(parameters)}")
    {:ok, :behavior_modified}
  end

  defp update_agent_capabilities_internal(agent_id, new_capabilities) do
    # Simulate capability update
    Logger.info("Updating capabilities for agent #{agent_id}: #{inspect(new_capabilities)}")
    {:ok, :capabilities_updated}
  end

  defp configure_agent_skill(agent_id, parameters) do
    # Simulate skill configuration
    Logger.info("Configuring skill for agent #{agent_id}: #{inspect(parameters)}")
    {:ok, :skill_configured}
  end

  defp add_active_directive(directive, state) do
    %{state | active_directives: Map.put(state.active_directives, directive.id, directive)}
  end

  defp record_directive_execution(directive, execution_result, state) do
    history_entry = %{
      directive: directive,
      execution_result: execution_result,
      executed_at: DateTime.utc_now()
    }

    %{state | directive_history: [history_entry | state.directive_history]}
  end

  defp revoke_directive_internal(directive_id, state) do
    case Map.get(state.active_directives, directive_id) do
      nil ->
        {:error, :directive_not_found}

      directive ->
        # Execute revocation logic
        revocation_result = execute_directive_revocation(directive, state)

        new_state = %{
          state
          | active_directives: Map.delete(state.active_directives, directive_id)
        }

        # Record revocation in history
        history_entry = %{
          directive: directive,
          revocation_result: revocation_result,
          revoked_at: DateTime.utc_now()
        }

        final_state = %{
          new_state
          | directive_history: [history_entry | new_state.directive_history]
        }

        {:ok, final_state}
    end
  end

  defp execute_directive_revocation(directive, _state) do
    # Simulate directive revocation
    Logger.info("Revoking directive #{directive.id}")
    {:ok, :directive_revoked}
  end

  defp get_agent_directives_internal(agent_id, state) do
    state.active_directives
    |> Enum.filter(fn {_id, directive} ->
      directive.target == agent_id or directive.target == :all
    end)
    |> Enum.map(fn {_id, directive} -> directive end)
  end

  defp execute_rollback(rollback_point, state) do
    # Restore previous directive state
    new_state = %{
      state
      | active_directives: rollback_point.active_directives,
        agent_capabilities: rollback_point.agent_capabilities
    }

    # Record rollback in history
    history_entry = %{
      rollback_point: rollback_point,
      executed_at: DateTime.utc_now(),
      previous_directives_count: map_size(state.active_directives),
      restored_directives_count: map_size(rollback_point.active_directives)
    }

    final_state = %{new_state | directive_history: [history_entry | new_state.directive_history]}

    {:ok, final_state}
  end

  defp filter_directive_history(history, filters) do
    Enum.filter(history, &matches_all_filters?(&1, filters))
  end

  defp matches_all_filters?(entry, filters) do
    Enum.all?(filters, &matches_filter?(entry, &1))
  end

  defp matches_filter?(entry, {key, value}) do
    case key do
      :directive_type ->
        get_in(entry, [:directive, :type]) == value

      :target_agent ->
        get_in(entry, [:directive, :target]) == value

      :after_date ->
        entry_date = get_in(entry, [:directive, :created_at]) || get_in(entry, [:executed_at])
        DateTime.compare(entry_date, value) != :lt

      _ ->
        true
    end
  end

  defp cleanup_expired_directives(state) do
    now = DateTime.utc_now()

    {expired, active} =
      Enum.split_with(state.active_directives, fn {_id, directive} ->
        directive.expires_at && DateTime.compare(directive.expires_at, now) == :lt
      end)

    # Log expired directives
    Enum.each(expired, fn {id, directive} ->
      Logger.info("Directive #{id} expired at #{directive.expires_at}")
    end)

    %{state | active_directives: Map.new(active)}
  end

  defp schedule_cleanup do
    # Every minute
    Process.send_after(self(), :cleanup_expired_directives, 60_000)
  end

  defp generate_directive_id do
    "dir_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp generate_rollback_id do
    "rb_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp initialize_routing_rules do
    [
      %{type: :emergency_response, strategy: :immediate},
      %{type: :behavior_modification, strategy: :queued},
      %{type: :capability_update, strategy: :immediate}
    ]
  end

  defp initialize_validation_rules do
    [
      %{type: :priority_limit, max_priority: 10},
      %{type: :target_restriction, allowed_targets: [:all]}
    ]
  end
end
