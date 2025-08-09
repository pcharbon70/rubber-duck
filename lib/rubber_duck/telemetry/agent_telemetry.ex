defmodule RubberDuck.Telemetry.AgentTelemetry do
  @moduledoc """
  Telemetry tracking for individual agent performance and health metrics.
  
  Provides comprehensive monitoring for:
  - Agent lifecycle events (start, stop, restart)
  - Goal completion tracking
  - Learning effectiveness
  - Experience accumulation
  - Cross-agent performance comparison
  """

  use GenServer
  require Logger

  @update_interval 30_000  # 30 seconds

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records an agent lifecycle event.
  """
  def record_lifecycle(agent_id, event_type, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :agent, :lifecycle, event_type],
      %{count: 1},
      Map.merge(metadata, %{agent_id: agent_id})
    )
  end

  @doc """
  Records goal completion by an agent.
  """
  def record_goal_completion(agent_id, goal_type, duration_ms, success) do
    :telemetry.execute(
      [:rubber_duck, :agent, :goal, :completed],
      %{
        duration: duration_ms,
        success: if(success, do: 1, else: 0)
      },
      %{
        agent_id: agent_id,
        goal_type: to_string(goal_type),
        status: if(success, do: :success, else: :failure)
      }
    )
    
    # Update agent performance score
    GenServer.cast(__MODULE__, {:update_performance, agent_id, success, duration_ms})
  end

  @doc """
  Records agent learning event.
  """
  def record_learning_event(agent_id, learning_type, confidence, patterns_found) do
    :telemetry.execute(
      [:rubber_duck, :agent, :learning, :event],
      %{
        confidence: confidence,
        patterns: patterns_found
      },
      %{
        agent_id: agent_id,
        learning_type: to_string(learning_type)
      }
    )
  end

  @doc """
  Records agent experience accumulation.
  """
  def record_experience_gained(agent_id, experience_type, count \\ 1) do
    :telemetry.execute(
      [:rubber_duck, :agent, :experience, :gained],
      %{count: count},
      %{
        agent_id: agent_id,
        experience_type: to_string(experience_type)
      }
    )
  end

  @doc """
  Gets current health status for an agent.
  """
  def get_agent_health(agent_id) do
    GenServer.call(__MODULE__, {:get_health, agent_id})
  end

  @doc """
  Gets performance comparison across all agents.
  """
  def get_performance_comparison do
    GenServer.call(__MODULE__, :get_comparison)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Schedule periodic health checks
    schedule_health_check()
    
    state = %{
      agents: %{},  # agent_id => %{health, performance, last_active}
      performance_history: [],  # Rolling window of performance data
      health_thresholds: %{
        inactive_warning: 300_000,  # 5 minutes
        inactive_critical: 900_000,  # 15 minutes
        success_rate_warning: 0.7,
        success_rate_critical: 0.5
      }
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:get_health, agent_id}, _from, state) do
    health = calculate_agent_health(agent_id, state)
    {:reply, health, state}
  end

  @impl true
  def handle_call(:get_comparison, _from, state) do
    comparison = build_performance_comparison(state)
    {:reply, comparison, state}
  end

  @impl true
  def handle_cast({:update_performance, agent_id, success, duration_ms}, state) do
    now = System.monotonic_time(:millisecond)
    
    agent_data = Map.get(state.agents, agent_id, %{
      total_goals: 0,
      successful_goals: 0,
      total_duration: 0,
      last_active: now,
      health: :healthy
    })
    
    updated_agent = %{
      agent_data |
      total_goals: agent_data.total_goals + 1,
      successful_goals: agent_data.successful_goals + if(success, do: 1, else: 0),
      total_duration: agent_data.total_duration + duration_ms,
      last_active: now
    }
    
    # Calculate success rate
    success_rate = if updated_agent.total_goals > 0 do
      updated_agent.successful_goals / updated_agent.total_goals
    else
      1.0
    end
    
    # Update health based on success rate
    health = determine_health(success_rate, state.health_thresholds)
    updated_agent = Map.put(updated_agent, :health, health)
    
    # Emit agent performance metric
    :telemetry.execute(
      [:rubber_duck, :agent, :performance],
      %{
        success_rate: success_rate,
        avg_duration: updated_agent.total_duration / max(updated_agent.total_goals, 1)
      },
      %{
        agent_id: agent_id,
        health: to_string(health)
      }
    )
    
    updated_agents = Map.put(state.agents, agent_id, updated_agent)
    {:noreply, %{state | agents: updated_agents}}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Check health of all agents
    now = System.monotonic_time(:millisecond)
    
    updated_agents = state.agents
    |> Enum.map(fn {agent_id, data} ->
      inactive_time = now - data.last_active
      
      # Determine health based on inactivity
      health = cond do
        inactive_time > state.health_thresholds.inactive_critical ->
          :critical
        inactive_time > state.health_thresholds.inactive_warning ->
          :warning
        true ->
          data.health
      end
      
      # Emit health metric
      :telemetry.execute(
        [:rubber_duck, :agent, :health],
        %{status: health_to_number(health)},
        %{agent_id: agent_id}
      )
      
      {agent_id, Map.put(data, :health, health)}
    end)
    |> Map.new()
    
    # Emit overall system health
    system_health = calculate_system_health(updated_agents)
    :telemetry.execute(
      [:rubber_duck, :ml, :system, :agents],
      %{value: map_size(updated_agents)},
      %{}
    )
    
    :telemetry.execute(
      [:rubber_duck, :ml, :system, :performance],
      %{value: system_health},
      %{}
    )
    
    # Schedule next check
    schedule_health_check()
    
    {:noreply, %{state | agents: updated_agents}}
  end

  # Private Functions

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @update_interval)
  end

  defp calculate_agent_health(agent_id, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        %{status: :unknown, message: "Agent not found"}
      
      agent_data ->
        success_rate = if agent_data.total_goals > 0 do
          agent_data.successful_goals / agent_data.total_goals
        else
          1.0
        end
        
        %{
          status: agent_data.health,
          success_rate: success_rate,
          total_goals: agent_data.total_goals,
          avg_duration: agent_data.total_duration / max(agent_data.total_goals, 1),
          last_active: agent_data.last_active
        }
    end
  end

  defp build_performance_comparison(state) do
    agents_with_scores = state.agents
    |> Enum.map(fn {agent_id, data} ->
      success_rate = if data.total_goals > 0 do
        data.successful_goals / data.total_goals
      else
        1.0
      end
      
      avg_duration = data.total_duration / max(data.total_goals, 1)
      
      # Calculate composite performance score
      # Higher success rate and lower duration = better score
      performance_score = success_rate * (1.0 / max(avg_duration / 1000, 0.1))
      
      %{
        agent_id: agent_id,
        success_rate: success_rate,
        avg_duration: avg_duration,
        total_goals: data.total_goals,
        performance_score: performance_score,
        health: data.health
      }
    end)
    |> Enum.sort_by(& &1.performance_score, :desc)
    
    %{
      top_performers: Enum.take(agents_with_scores, 5),
      total_agents: length(agents_with_scores),
      avg_success_rate: calculate_avg_success_rate(agents_with_scores),
      healthy_agents: Enum.count(agents_with_scores, &(&1.health == :healthy))
    }
  end

  defp determine_health(success_rate, thresholds) do
    cond do
      success_rate < thresholds.success_rate_critical -> :critical
      success_rate < thresholds.success_rate_warning -> :warning
      true -> :healthy
    end
  end

  defp health_to_number(:healthy), do: 1.0
  defp health_to_number(:warning), do: 0.5
  defp health_to_number(:critical), do: 0.0
  defp health_to_number(_), do: 0.0

  defp calculate_system_health(agents) do
    if map_size(agents) == 0 do
      1.0
    else
      healthy_count = Enum.count(agents, fn {_, data} -> data.health == :healthy end)
      healthy_count / map_size(agents)
    end
  end

  defp calculate_avg_success_rate(agents_with_scores) do
    if length(agents_with_scores) == 0 do
      0.0
    else
      total = Enum.sum(Enum.map(agents_with_scores, & &1.success_rate))
      total / length(agents_with_scores)
    end
  end
end