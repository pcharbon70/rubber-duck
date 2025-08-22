defmodule RubberDuck.SkillsRegistry do
  @moduledoc """
  Central registry for Skills discovery, registration, and management.

  Provides capabilities for:
  - Dynamic skill discovery and registration
  - Dependency resolution between skills
  - Per-agent configuration management
  - Hot-swapping of skill capabilities
  """

  use GenServer
  require Logger

  @type skill_id :: atom()
  @type agent_id :: String.t()
  @type skill_config :: map()
  @type dependency :: {skill_id(), map()}

  defstruct [
    :skills,
    :agent_configs,
    :dependencies,
    :hot_swap_queue,
    :registry_listeners
  ]

  ## Client API

  @doc """
  Start the Skills Registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a skill with the registry.
  """
  def register_skill(skill_module, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:register_skill, skill_module, metadata})
  end

  @doc """
  Discover available skills matching given criteria.
  """
  def discover_skills(criteria \\ %{}) do
    GenServer.call(__MODULE__, {:discover_skills, criteria})
  end

  @doc """
  Get skill configuration for a specific agent.
  """
  def get_agent_skill_config(agent_id, skill_id) do
    GenServer.call(__MODULE__, {:get_agent_skill_config, agent_id, skill_id})
  end

  @doc """
  Configure a skill for a specific agent.
  """
  def configure_skill_for_agent(agent_id, skill_id, config) do
    GenServer.call(__MODULE__, {:configure_skill_for_agent, agent_id, skill_id, config})
  end

  @doc """
  Resolve dependencies for a skill.
  """
  def resolve_dependencies(skill_id) do
    GenServer.call(__MODULE__, {:resolve_dependencies, skill_id})
  end

  @doc """
  Hot-swap a skill for an agent.
  """
  def hot_swap_skill(agent_id, old_skill_id, new_skill_id, config \\ %{}) do
    GenServer.call(__MODULE__, {:hot_swap_skill, agent_id, old_skill_id, new_skill_id, config})
  end

  @doc """
  Get all skills registered for an agent.
  """
  def get_agent_skills(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_skills, agent_id})
  end

  @doc """
  Subscribe to registry events (skill registration, hot-swaps, etc).
  """
  def subscribe_to_events(listener_pid) do
    GenServer.cast(__MODULE__, {:subscribe_to_events, listener_pid})
  end

  ## Server Implementation

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      skills: %{},
      agent_configs: %{},
      dependencies: %{},
      hot_swap_queue: :queue.new(),
      registry_listeners: MapSet.new()
    }

    # Discover and register built-in skills
    discover_and_register_builtin_skills(state)
  end

  @impl true
  def handle_call({:register_skill, skill_module, metadata}, _from, state) do
    case register_skill_internal(skill_module, metadata, state) do
      {:ok, new_state} ->
        notify_listeners({:skill_registered, skill_module, metadata}, new_state)
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:discover_skills, criteria}, _from, state) do
    skills = discover_skills_internal(criteria, state)
    {:reply, {:ok, skills}, state}
  end

  @impl true
  def handle_call({:get_agent_skill_config, agent_id, skill_id}, _from, state) do
    config = get_in(state.agent_configs, [agent_id, skill_id]) || %{}
    {:reply, {:ok, config}, state}
  end

  @impl true
  def handle_call({:configure_skill_for_agent, agent_id, skill_id, config}, _from, state) do
    case validate_skill_configuration(skill_id, config, state) do
      :ok ->
        new_state = put_in(state.agent_configs, [agent_id, skill_id], config)
        notify_listeners({:skill_configured, agent_id, skill_id, config}, new_state)
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:resolve_dependencies, skill_id}, _from, state) do
    case resolve_dependencies_internal(skill_id, state) do
      {:ok, resolved_deps} ->
        {:reply, {:ok, resolved_deps}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:hot_swap_skill, agent_id, old_skill_id, new_skill_id, config}, _from, state) do
    case perform_hot_swap(agent_id, old_skill_id, new_skill_id, config, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_agent_skills, agent_id}, _from, state) do
    agent_skills = Map.get(state.agent_configs, agent_id, %{})

    skills_with_metadata =
      Enum.map(agent_skills, fn {skill_id, config} ->
        skill_metadata = Map.get(state.skills, skill_id, %{})
        {skill_id, %{config: config, metadata: skill_metadata}}
      end)
      |> Map.new()

    {:reply, {:ok, skills_with_metadata}, state}
  end

  @impl true
  def handle_cast({:subscribe_to_events, listener_pid}, state) do
    new_state = %{state | registry_listeners: MapSet.put(state.registry_listeners, listener_pid)}
    {:noreply, new_state}
  end

  ## Internal Functions

  defp discover_and_register_builtin_skills(state) do
    builtin_skills = [
      RubberDuck.Skills.LearningSkill,
      RubberDuck.Skills.AuthenticationSkill,
      RubberDuck.Skills.ThreatDetectionSkill,
      RubberDuck.Skills.TokenManagementSkill,
      RubberDuck.Skills.PolicyEnforcementSkill,
      RubberDuck.Skills.QueryOptimizationSkill,
      RubberDuck.Skills.CodeAnalysisSkill,
      RubberDuck.Skills.UserManagementSkill,
      RubberDuck.Skills.ProjectManagementSkill
    ]

    Enum.reduce(builtin_skills, state, fn skill_module, acc_state ->
      case register_skill_internal(skill_module, extract_skill_metadata(skill_module), acc_state) do
        {:ok, new_state} -> new_state
        {:error, _reason} -> acc_state
      end
    end)
  end

  defp register_skill_internal(skill_module, metadata, state) do
    skill_id = extract_skill_id(skill_module)

    if Map.has_key?(state.skills, skill_id) do
      {:error, :skill_already_registered}
    else
      skill_info = %{
        module: skill_module,
        metadata: metadata,
        registered_at: DateTime.utc_now(),
        dependencies: extract_skill_dependencies(skill_module)
      }

      new_state = %{
        state
        | skills: Map.put(state.skills, skill_id, skill_info),
          dependencies: Map.put(state.dependencies, skill_id, skill_info.dependencies)
      }

      {:ok, new_state}
    end
  end

  defp discover_skills_internal(criteria, state) do
    state.skills
    |> Enum.filter(fn {_skill_id, skill_info} ->
      matches_criteria?(skill_info, criteria)
    end)
    |> Enum.map(fn {skill_id, skill_info} ->
      {skill_id, skill_info.metadata}
    end)
    |> Map.new()
  end

  defp matches_criteria?(skill_info, criteria) do
    Enum.all?(criteria, fn {key, value} ->
      case key do
        :category ->
          get_in(skill_info, [:metadata, :category]) == value

        :capabilities ->
          capabilities = get_in(skill_info, [:metadata, :capabilities]) || []
          Enum.all?(value, &(&1 in capabilities))

        :version ->
          get_in(skill_info, [:metadata, :version]) == value

        _ ->
          true
      end
    end)
  end

  defp validate_skill_configuration(skill_id, config, state) do
    case Map.get(state.skills, skill_id) do
      nil ->
        {:error, :skill_not_found}

      skill_info ->
        validate_config_against_schema(config, skill_info)
    end
  end

  defp validate_config_against_schema(config, skill_info) do
    # Extract configuration schema from skill metadata
    schema = get_in(skill_info, [:metadata, :config_schema]) || %{}

    # Basic validation - in production this would use a proper schema validator
    required_fields = Map.get(schema, :required, [])

    missing_fields = Enum.reject(required_fields, &Map.has_key?(config, &1))

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, {:missing_required_fields, missing_fields}}
    end
  end

  defp resolve_dependencies_internal(skill_id, state) do
    case Map.get(state.dependencies, skill_id) do
      nil ->
        {:error, :skill_not_found}

      dependencies ->
        resolve_dependency_chain(dependencies, state, [skill_id])
    end
  end

  defp resolve_dependency_chain(dependencies, state, visited) do
    Enum.reduce_while(dependencies, {:ok, []}, fn dependency, {:ok, acc} ->
      resolve_single_dependency(dependency, state, visited, acc)
    end)
  end

  defp resolve_single_dependency({dep_skill_id, dep_config}, state, visited, acc) do
    cond do
      dep_skill_id in visited ->
        {:halt, {:error, {:circular_dependency, dep_skill_id}}}

      not Map.has_key?(state.skills, dep_skill_id) ->
        {:halt, {:error, {:dependency_not_found, dep_skill_id}}}

      true ->
        resolve_nested_dependency(dep_skill_id, dep_config, state, visited, acc)
    end
  end

  defp resolve_nested_dependency(dep_skill_id, dep_config, state, visited, acc) do
    nested_deps = Map.get(state.dependencies, dep_skill_id, [])

    case resolve_dependency_chain(nested_deps, state, [dep_skill_id | visited]) do
      {:ok, nested_resolved} ->
        resolved_dep = %{
          skill_id: dep_skill_id,
          config: dep_config,
          dependencies: nested_resolved
        }

        {:cont, {:ok, [resolved_dep | acc]}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp perform_hot_swap(agent_id, old_skill_id, new_skill_id, config, state) do
    with {:ok, _} <- validate_skill_exists(new_skill_id, state),
         {:ok, _} <- validate_hot_swap_compatibility(old_skill_id, new_skill_id, state),
         {:ok, new_state} <- execute_hot_swap(agent_id, old_skill_id, new_skill_id, config, state) do
      notify_listeners({:skill_hot_swapped, agent_id, old_skill_id, new_skill_id}, new_state)
      {:ok, new_state}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_skill_exists(skill_id, state) do
    if Map.has_key?(state.skills, skill_id) do
      {:ok, :skill_exists}
    else
      {:error, :skill_not_found}
    end
  end

  defp validate_hot_swap_compatibility(old_skill_id, new_skill_id, state) do
    old_skill = Map.get(state.skills, old_skill_id)
    new_skill = Map.get(state.skills, new_skill_id)

    case {old_skill, new_skill} do
      {nil, _} ->
        {:error, :old_skill_not_found}

      {_, nil} ->
        {:error, :new_skill_not_found}

      {old_info, new_info} ->
        if skills_compatible?(old_info, new_info) do
          {:ok, :compatible}
        else
          {:error, :incompatible_skills}
        end
    end
  end

  defp skills_compatible?(old_info, new_info) do
    old_category = get_in(old_info, [:metadata, :category])
    new_category = get_in(new_info, [:metadata, :category])

    # Skills are compatible if they're in the same category
    old_category == new_category
  end

  defp execute_hot_swap(agent_id, old_skill_id, new_skill_id, config, state) do
    # Remove old skill configuration
    agent_configs = Map.get(state.agent_configs, agent_id, %{})

    updated_configs =
      agent_configs
      |> Map.delete(old_skill_id)
      |> Map.put(new_skill_id, config)

    new_state = %{state | agent_configs: Map.put(state.agent_configs, agent_id, updated_configs)}

    {:ok, new_state}
  end

  defp extract_skill_id(skill_module) do
    skill_module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end

  defp extract_skill_metadata(skill_module) do
    %{
      name: extract_skill_name(skill_module),
      category: extract_skill_category(skill_module),
      capabilities: extract_skill_capabilities(skill_module),
      version: "1.0.0",
      config_schema: extract_config_schema(skill_module)
    }
  end

  defp extract_skill_name(skill_module) do
    skill_module
    |> Module.split()
    |> List.last()
    |> String.replace("Skill", "")
  end

  defp extract_skill_category(skill_module) do
    module_string = to_string(skill_module)

    category_patterns()
    |> Enum.find_value(:general, fn {patterns, category} ->
      if Enum.any?(patterns, &String.contains?(module_string, &1)) do
        category
      end
    end)
  end

  defp category_patterns do
    [
      {["Authentication", "Threat", "Token", "Policy"], :security},
      {["Query"], :database},
      {["Learning"], :intelligence},
      {["Code"], :development},
      {["User", "Project"], :management}
    ]
  end

  defp extract_skill_capabilities(skill_module) do
    # In a real implementation, this would introspect the skill module
    # For now, return basic capabilities based on the module name
    case extract_skill_category(skill_module) do
      :security -> [:threat_detection, :authentication, :authorization]
      :database -> [:query_optimization, :performance_monitoring]
      :intelligence -> [:pattern_recognition, :learning, :adaptation]
      :development -> [:code_analysis, :optimization]
      :management -> [:user_management, :project_coordination]
      :general -> [:basic_operations]
    end
  end

  defp extract_skill_dependencies(skill_module) do
    # In a real implementation, this would introspect the skill module for dependencies
    # For now, assume LearningSkill is a common dependency for intelligent skills
    case extract_skill_category(skill_module) do
      :security when skill_module != RubberDuck.Skills.LearningSkill ->
        [{:learning_skill, %{}}]

      :database when skill_module != RubberDuck.Skills.LearningSkill ->
        [{:learning_skill, %{}}]

      :intelligence when skill_module != RubberDuck.Skills.LearningSkill ->
        []

      _ ->
        []
    end
  end

  defp extract_config_schema(_skill_module) do
    # In a real implementation, this would extract the actual configuration schema
    %{
      required: [],
      optional: [:timeout, :log_level, :cache_size]
    }
  end

  defp notify_listeners(event, state) do
    Enum.each(state.registry_listeners, fn listener_pid ->
      if Process.alive?(listener_pid) do
        send(listener_pid, {:skills_registry_event, event})
      end
    end)
  end
end
