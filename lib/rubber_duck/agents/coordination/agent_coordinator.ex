defmodule RubberDuck.Agents.Coordination.AgentCoordinator do
  @moduledoc """
  Manages lifecycle and coordination of multiple judge agents.

  Handles agent spawning, monitoring, cleanup, and failure recovery
  for judge agents participating in collaborative evaluations.
  """

  use Jido.Agent, name: "AgentCoordinator"

  require Logger

  @agent_types [:code_quality, :architecture, :security, :test_quality]
  @default_timeout 30_000
  @max_concurrent_agents 4

  @impl true
  def init(opts \\ []) do
    state = %{
      active_agents: %{},
      agent_registry: %{},
      coordination_session: nil,
      max_agents: Keyword.get(opts, :max_agents, @max_concurrent_agents),
      agent_timeout: Keyword.get(opts, :agent_timeout, @default_timeout)
    }

    {:ok, state}
  end

  @doc """
  Start a coordination session with specified judge agents.

  ## Parameters
  - `agent` - The coordinator agent instance
  - `session_config` - Configuration for the coordination session

  ## Returns
  - `{:ok, session_id, updated_agent}` - Session started successfully
  - `{:error, reason, agent}` - Failed to start session
  """
  def start_coordination_session(agent, session_config) do
    session_id = generate_session_id()
    required_agents = Map.get(session_config, :required_agents, @agent_types)

    Logger.info("Starting coordination session: #{session_id}")

    case spawn_required_agents(agent, required_agents, session_config) do
      {:ok, spawned_agents, updated_agent} ->
        session = %{
          id: session_id,
          required_agents: required_agents,
          active_agents: spawned_agents,
          started_at: DateTime.utc_now(),
          config: session_config
        }

        final_agent = put_in(updated_agent.state.coordination_session, session)
        {:ok, session_id, final_agent}

      {:error, reason, agent} ->
        {:error, reason, agent}
    end
  end

  @doc """
  Terminate a coordination session and cleanup agents.
  """
  def end_coordination_session(agent, session_id) do
    case agent.state.coordination_session do
      %{id: ^session_id} = session ->
        Logger.info("Ending coordination session: #{session_id}")

        cleanup_result = cleanup_session_agents(agent, session.active_agents)

        updated_agent = %{
          agent
          | state: %{agent.state | coordination_session: nil, active_agents: %{}}
        }

        case cleanup_result do
          :ok -> {:ok, updated_agent}
          {:error, reason} -> {:error, reason, updated_agent}
        end

      _ ->
        {:error, "No active session with ID: #{session_id}", agent}
    end
  end

  @doc """
  Get status of all agents in current coordination session.
  """
  def get_agent_status(agent) do
    case agent.state.coordination_session do
      nil ->
        %{status: :no_active_session}

      session ->
        agent_statuses = build_agent_statuses(session.active_agents)

        %{
          session_id: session.id,
          agents: agent_statuses,
          started_at: session.started_at,
          session_duration: DateTime.diff(DateTime.utc_now(), session.started_at, :second)
        }
    end
  end

  @doc """
  Monitor agent health and restart failed agents.
  """
  def monitor_agents(agent) do
    case agent.state.coordination_session do
      nil ->
        {:ok, agent}

      session ->
        {failed_agents, surviving_agents} = check_agent_health(session.active_agents)

        if length(failed_agents) > 0 do
          Logger.warning(
            "Detected #{length(failed_agents)} failed agents: #{inspect(failed_agents)}"
          )

          restart_failed_agents(agent, failed_agents, session.config)
        else
          {:ok, agent}
        end
    end
  end

  ## Private Functions

  defp spawn_required_agents(agent, required_agents, config) do
    if length(required_agents) > agent.state.max_agents do
      {:error, "Too many agents requested: #{length(required_agents)}", agent}
    else
      spawn_agents_sequentially(agent, required_agents, config, %{})
    end
  end

  defp spawn_agents_sequentially(agent, [], _config, spawned_agents) do
    updated_state = %{agent.state | active_agents: spawned_agents}
    {:ok, spawned_agents, %{agent | state: updated_state}}
  end

  defp spawn_agents_sequentially(agent, [agent_type | rest], config, spawned_agents) do
    case spawn_judge_agent(agent_type, config) do
      {:ok, agent_pid} ->
        new_spawned = Map.put(spawned_agents, agent_type, agent_pid)
        spawn_agents_sequentially(agent, rest, config, new_spawned)

      {:error, reason} ->
        cleanup_spawned_agents(spawned_agents)
        {:error, "Failed to spawn #{agent_type} agent: #{reason}", agent}
    end
  end

  defp spawn_judge_agent(agent_type, config) do
    agent_module = get_agent_module(agent_type)
    agent_config = Map.get(config, agent_type, %{})

    case agent_module.start_link(agent_config) do
      {:ok, pid} ->
        Logger.debug("Spawned #{agent_type} judge agent: #{inspect(pid)}")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to spawn #{agent_type} judge agent: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_agent_module(agent_type) do
    case agent_type do
      :code_quality -> RubberDuck.Agents.Judges.CodeQualityJudgeAgent
      :architecture -> RubberDuck.Agents.Judges.ArchitectureJudgeAgent
      :security -> RubberDuck.Agents.Judges.SecurityJudgeAgent
      :test_quality -> RubberDuck.Agents.Judges.TestQualityJudgeAgent
    end
  end

  defp cleanup_session_agents(agent, active_agents) do
    cleanup_results =
      Enum.map(active_agents, fn {agent_type, agent_pid} ->
        case terminate_agent(agent_pid) do
          :ok ->
            Logger.debug("Cleaned up #{agent_type} agent: #{inspect(agent_pid)}")
            :ok

          {:error, reason} ->
            Logger.warning("Failed to cleanup #{agent_type} agent: #{reason}")
            {:error, reason}
        end
      end)

    failed_cleanups = Enum.filter(cleanup_results, &match?({:error, _}, &1))

    if length(failed_cleanups) > 0 do
      {:error, "Failed to cleanup #{length(failed_cleanups)} agents"}
    else
      :ok
    end
  end

  defp cleanup_spawned_agents(spawned_agents) do
    Enum.each(spawned_agents, fn {_agent_type, agent_pid} ->
      terminate_agent(agent_pid)
    end)
  end

  defp terminate_agent(agent_pid) do
    if Process.alive?(agent_pid) do
      Process.exit(agent_pid, :shutdown)

      receive do
        {:EXIT, ^agent_pid, _reason} -> :ok
      after
        5_000 -> {:error, "Agent termination timeout"}
      end
    else
      :ok
    end
  end

  defp check_agent_health(active_agents) do
    Enum.split_with(active_agents, fn {_agent_type, agent_pid} ->
      not Process.alive?(agent_pid)
    end)
  end

  defp restart_failed_agents(agent, failed_agents, config) do
    restart_attempts =
      Enum.map(failed_agents, fn {agent_type, _dead_pid} ->
        case spawn_judge_agent(agent_type, config) do
          {:ok, new_pid} ->
            Logger.info("Successfully restarted #{agent_type} agent: #{inspect(new_pid)}")
            {:ok, agent_type, new_pid}

          {:error, reason} ->
            Logger.error("Failed to restart #{agent_type} agent: #{reason}")
            {:error, agent_type, reason}
        end
      end)

    successful_restarts = Enum.filter(restart_attempts, &match?({:ok, _, _}, &1))
    failed_restarts = Enum.filter(restart_attempts, &match?({:error, _, _}, &1))

    if length(failed_restarts) > 0 do
      Logger.error("Failed to restart #{length(failed_restarts)} agents")
      {:error, "Agent restart failures", agent}
    else
      new_agents =
        Enum.reduce(successful_restarts, agent.state.active_agents, fn {:ok, agent_type, pid},
                                                                       acc ->
          Map.put(acc, agent_type, pid)
        end)

      updated_session = put_in(agent.state.coordination_session.active_agents, new_agents)
      updated_agent = %{agent | state: %{agent.state | coordination_session: updated_session}}

      {:ok, updated_agent}
    end
  end

  defp build_agent_statuses(active_agents) do
    Enum.reduce(active_agents, %{}, fn {agent_type, agent_pid}, acc ->
      status = if Process.alive?(agent_pid), do: :alive, else: :dead
      Map.put(acc, agent_type, status)
    end)
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16() |> String.downcase()
  end
end
