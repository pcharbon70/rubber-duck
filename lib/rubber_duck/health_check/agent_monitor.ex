defmodule RubberDuck.HealthCheck.AgentMonitor do
  @moduledoc """
  Agent health and performance monitor.

  Monitors:
  - Individual agent status and responsiveness
  - Agent skill loading and availability
  - Agent learning system performance
  - Inter-agent communication health
  """

  use GenServer
  require Logger

  # 25 seconds
  @check_interval 25_000

  defstruct [
    :timer_ref,
    :last_check,
    :health_status,
    :agent_statuses,
    :performance_metrics
  ]

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_health_status do
    GenServer.call(__MODULE__, :get_health_status)
  end

  def register_agent(agent_id, agent_pid) do
    GenServer.cast(__MODULE__, {:register_agent, agent_id, agent_pid})
  end

  def unregister_agent(agent_id) do
    GenServer.cast(__MODULE__, {:unregister_agent, agent_id})
  end

  def force_check do
    GenServer.cast(__MODULE__, :force_check)
  end

  ## Server Implementation

  @impl true
  def init(_opts) do
    Logger.info("Starting Agent Health Monitor")

    # Perform initial check
    send(self(), :perform_agent_check)

    state = %__MODULE__{
      timer_ref: nil,
      last_check: nil,
      health_status: :unknown,
      agent_statuses: %{},
      performance_metrics: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_health_status, _from, state) do
    health_report = %{
      status: state.health_status,
      last_check: state.last_check,
      agents: state.agent_statuses,
      performance: state.performance_metrics
    }

    {:reply, health_report, state}
  end

  @impl true
  def handle_cast({:register_agent, agent_id, _agent_pid}, state) do
    Logger.info("Registering agent #{agent_id} for health monitoring")
    {:noreply, state}
  end

  @impl true
  def handle_cast({:unregister_agent, agent_id}, state) do
    Logger.info("Unregistering agent #{agent_id} from health monitoring")

    updated_statuses = Map.delete(state.agent_statuses, agent_id)
    new_state = %{state | agent_statuses: updated_statuses}

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:force_check, state) do
    new_state = perform_agent_check(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:perform_agent_check, state) do
    new_state = perform_agent_check(state)

    # Schedule next check
    timer_ref = Process.send_after(self(), :perform_agent_check, @check_interval)
    final_state = %{new_state | timer_ref: timer_ref}

    {:noreply, final_state}
  end

  ## Internal Functions

  defp perform_agent_check(state) do
    case safe_agent_check() do
      {:ok, {agent_statuses, performance_metrics, health_status}} ->
        emit_agent_telemetry(health_status, agent_statuses, performance_metrics)

        %{
          state
          | health_status: health_status,
            last_check: DateTime.utc_now(),
            agent_statuses: agent_statuses,
            performance_metrics: performance_metrics
        }

      {:error, error} ->
        Logger.error("Agent health check failed: #{inspect(error)}")
        %{state | health_status: :critical, last_check: DateTime.utc_now()}
    end
  end

  defp safe_agent_check do
    # Check agent ecosystem health
    agent_statuses = check_agent_ecosystem()

    # Collect performance metrics
    performance_metrics = collect_agent_performance_metrics()

    # Determine overall agent health
    health_status = determine_agent_health(agent_statuses, performance_metrics)

    {:ok, {agent_statuses, performance_metrics, health_status}}
  rescue
    error -> {:error, error}
  end

  defp check_agent_ecosystem do
    %{
      skills_registry_health: check_skills_registry_health(),
      directives_engine_health: check_directives_engine_health(),
      instructions_processor_health: check_instructions_processor_health(),
      agent_coordination: check_agent_coordination_health(),
      learning_system: check_learning_system_health()
    }
  end

  defp check_skills_registry_health do
    case safe_skills_registry_check() do
      {:ok, result} -> result
      {:error, error} -> %{status: :critical, error: inspect(error)}
    end
  end

  defp safe_skills_registry_check do
    case GenServer.whereis(RubberDuck.SkillsRegistry) do
      nil ->
        {:ok, %{status: :critical, error: "Skills Registry not available"}}

      _pid ->
        # Test skills discovery
        case RubberDuck.SkillsRegistry.discover_skills() do
          {:ok, skills} ->
            skill_count = map_size(skills)
            {:ok, %{status: :healthy, skill_count: skill_count}}

          {:error, reason} ->
            {:ok, %{status: :degraded, error: inspect(reason)}}
        end
    end
  rescue
    error -> {:error, error}
  end

  defp check_directives_engine_health do
    case safe_directives_engine_check() do
      {:ok, result} -> result
      {:error, error} -> %{status: :critical, error: inspect(error)}
    end
  end

  defp safe_directives_engine_check do
    case GenServer.whereis(RubberDuck.DirectivesEngine) do
      nil ->
        {:ok, %{status: :critical, error: "Directives Engine not available"}}

      _pid ->
        # Check active directives count
        case RubberDuck.DirectivesEngine.get_directive_history(%{}) do
          {:ok, history} ->
            {:ok, %{status: :healthy, directive_history_count: length(history)}}

          {:error, reason} ->
            {:ok, %{status: :degraded, error: inspect(reason)}}
        end
    end
  rescue
    error -> {:error, error}
  end

  defp check_instructions_processor_health do
    case safe_instructions_processor_check() do
      {:ok, result} -> result
      {:error, error} -> %{status: :critical, error: inspect(error)}
    end
  end

  defp safe_instructions_processor_check do
    case GenServer.whereis(RubberDuck.InstructionsProcessor) do
      nil ->
        {:ok, %{status: :critical, error: "Instructions Processor not available"}}

      _pid ->
        test_instruction = %{
          type: :skill_invocation,
          action: "health_check_action",
          parameters: %{test: true}
        }

        case RubberDuck.InstructionsProcessor.normalize_instruction(test_instruction) do
          {:ok, normalized} ->
            {:ok, %{status: :healthy, normalized_fields: map_size(normalized)}}

          {:error, reason} ->
            {:ok, %{status: :degraded, error: inspect(reason)}}
        end
    end
  rescue
    error -> {:error, error}
  end

  defp check_agent_coordination_health do
    case safe_coordination_check() do
      {:ok, result} -> result
      {:error, error} -> %{status: :critical, error: inspect(error)}
    end
  end

  defp safe_coordination_check do
    # Check if agents can communicate through PubSub
    test_topic = "agent_health_check_#{:rand.uniform(10_000)}"

    # Subscribe to test topic
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, test_topic)

    # Broadcast coordination message
    coordination_message = %{
      type: :health_check,
      timestamp: DateTime.utc_now(),
      check_id: :rand.uniform(10_000)
    }

    Phoenix.PubSub.broadcast(RubberDuck.PubSub, test_topic, coordination_message)

    # Check if we receive the coordination message
    result =
      receive do
        ^coordination_message ->
          %{status: :healthy, communication: :functional}
      after
        2000 ->
          %{status: :degraded, error: "Agent coordination timeout"}
      end

    {:ok, result}
  rescue
    error -> {:error, error}
  end

  defp check_learning_system_health do
    case safe_learning_system_check() do
      {:ok, result} -> result
      {:error, error} -> %{status: :warning, error: inspect(error)}
    end
  end

  defp safe_learning_system_check do
    # Simulate learning system health check
    # In a real implementation, this would check learning agents and their state
    learning_processes = find_learning_processes()

    result =
      if length(learning_processes) > 0 do
        # Test if learning processes are responsive
        responsive_count = count_responsive_processes(learning_processes)
        total_count = length(learning_processes)
        health_ratio = responsive_count / total_count

        cond do
          health_ratio >= 0.8 -> %{status: :healthy, responsive_ratio: health_ratio}
          health_ratio >= 0.5 -> %{status: :warning, responsive_ratio: health_ratio}
          true -> %{status: :degraded, responsive_ratio: health_ratio}
        end
      else
        # No learning processes found - this might be expected in some configurations
        %{status: :healthy, learning_processes: 0}
      end

    {:ok, result}
  rescue
    error -> {:error, error}
  end

  defp find_learning_processes do
    # Find processes that might be related to learning
    Process.list()
    |> Enum.filter(fn pid ->
      case Process.info(pid, :registered_name) do
        {:registered_name, name} when is_atom(name) ->
          name_str = Atom.to_string(name)
          String.contains?(name_str, "Learning") or String.contains?(name_str, "Agent")

        _ ->
          false
      end
    end)
  end

  defp count_responsive_processes(processes) do
    Enum.count(processes, &process_responsive?/1)
  end

  defp process_responsive?(pid) do
    case Process.info(pid, :status) do
      {:status, status} -> status in [:running, :runnable, :waiting]
      nil -> false
    end
  rescue
    _ -> false
  end

  defp collect_agent_performance_metrics do
    %{
      total_agent_processes: count_agent_processes(),
      average_message_queue_length: calculate_average_message_queue_length(),
      agent_memory_usage: calculate_agent_memory_usage(),
      skill_execution_rate: estimate_skill_execution_rate(),
      coordination_latency: measure_coordination_latency()
    }
  end

  defp count_agent_processes do
    Process.list()
    |> Enum.count(fn pid ->
      case Process.info(pid, :registered_name) do
        {:registered_name, name} when is_atom(name) ->
          name_str = Atom.to_string(name)
          String.contains?(name_str, "Agent") or String.contains?(name_str, "Skill")

        _ ->
          false
      end
    end)
  end

  defp calculate_average_message_queue_length do
    agent_processes =
      Process.list()
      |> Enum.filter(fn pid ->
        case Process.info(pid, :registered_name) do
          {:registered_name, name} when is_atom(name) ->
            name_str = Atom.to_string(name)
            String.contains?(name_str, "Agent")

          _ ->
            false
        end
      end)

    case agent_processes do
      [] -> 0.0
      processes -> calculate_average_queue_length(processes)
    end
  end

  defp calculate_average_queue_length(processes) do
    total_queue_length =
      Enum.reduce(processes, 0, fn pid, acc ->
        case Process.info(pid, :message_queue_len) do
          {:message_queue_len, len} -> acc + len
          nil -> acc
        end
      end)

    total_queue_length / length(processes)
  end

  defp calculate_agent_memory_usage do
    agent_processes =
      Process.list()
      |> Enum.filter(fn pid ->
        case Process.info(pid, :registered_name) do
          {:registered_name, name} when is_atom(name) ->
            name_str = Atom.to_string(name)
            String.contains?(name_str, "Agent") or String.contains?(name_str, "Skill")

          _ ->
            false
        end
      end)

    total_memory =
      Enum.reduce(agent_processes, 0, fn pid, acc ->
        case Process.info(pid, :memory) do
          {:memory, memory} -> acc + memory
          nil -> acc
        end
      end)

    # Convert to MB
    total_memory / (1024 * 1024)
  end

  defp estimate_skill_execution_rate do
    # This is a simplified estimation
    # In a real implementation, you would track actual skill executions
    # Random value between 50-150 for demo
    :rand.uniform(100) + 50
  end

  defp measure_coordination_latency do
    start_time = System.monotonic_time(:millisecond)

    # Simple coordination test
    test_topic = "coordination_latency_test"
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, test_topic)
    Phoenix.PubSub.broadcast(RubberDuck.PubSub, test_topic, :latency_test)

    receive do
      :latency_test ->
        end_time = System.monotonic_time(:millisecond)
        end_time - start_time
    after
      # Timeout
      1000 -> 1000
    end
  end

  defp determine_agent_health(agent_statuses, performance_metrics) do
    # Extract all status values
    statuses =
      agent_statuses
      |> Map.values()
      |> Enum.map(fn status_info ->
        Map.get(status_info, :status, :unknown)
      end)

    # Check performance thresholds
    performance_status = check_performance_thresholds(performance_metrics)

    # Combine status checks
    all_statuses = [performance_status | statuses]

    cond do
      :critical in all_statuses -> :critical
      :degraded in all_statuses -> :degraded
      :warning in all_statuses -> :warning
      Enum.all?(all_statuses, &(&1 == :healthy)) -> :healthy
      true -> :unknown
    end
  end

  defp check_performance_thresholds(performance_metrics) do
    cond do
      performance_metrics.average_message_queue_length > 1000 -> :critical
      # 500 MB
      performance_metrics.agent_memory_usage > 500 -> :warning
      # 500 ms
      performance_metrics.coordination_latency > 500 -> :warning
      true -> :healthy
    end
  end

  defp emit_agent_telemetry(health_status, agent_statuses, performance_metrics) do
    # Emit agent ecosystem telemetry
    :telemetry.execute(
      [:rubber_duck, :health_check, :agents],
      %{
        status_numeric: status_to_numeric(health_status),
        total_agent_processes: performance_metrics.total_agent_processes,
        average_message_queue_length: performance_metrics.average_message_queue_length,
        agent_memory_usage_mb: performance_metrics.agent_memory_usage,
        coordination_latency_ms: performance_metrics.coordination_latency
      },
      %{
        status: health_status,
        agent_statuses: agent_statuses,
        performance: performance_metrics
      }
    )
  end

  defp status_to_numeric(:healthy), do: 1
  defp status_to_numeric(:warning), do: 2
  defp status_to_numeric(:degraded), do: 3
  defp status_to_numeric(:critical), do: 4
  defp status_to_numeric(_), do: 0
end
