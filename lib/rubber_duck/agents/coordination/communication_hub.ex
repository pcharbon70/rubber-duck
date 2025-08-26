defmodule RubberDuck.Agents.Coordination.CommunicationHub do
  @moduledoc """
  Central communication hub for coordinating message passing between judge agents.

  Facilitates negotiation, information sharing, and coordination protocols
  between multiple judge agents during collaborative evaluations.
  """

  use Jido.Agent, name: "CommunicationHub"

  require Logger

  @max_message_queue_size 100

  @impl true
  def init(opts \\ []) do
    state = %{
      coordination_session: nil,
      agent_registry: %{},
      message_queues: %{},
      message_history: [],
      pending_negotiations: %{},
      max_queue_size: Keyword.get(opts, :max_queue_size, @max_message_queue_size)
    }

    {:ok, state}
  end

  @doc """
  Register agents for inter-agent communication.

  ## Parameters
  - `agent` - The hub agent instance
  - `session_id` - Coordination session identifier
  - `agent_registry` - Map of agent_type -> agent_pid

  ## Returns
  - `{:ok, updated_agent}` - Agents registered successfully
  - `{:error, reason, agent}` - Registration failed
  """
  def register_agents(agent, session_id, agent_registry) do
    Logger.info("Registering #{map_size(agent_registry)} agents for session: #{session_id}")

    message_queues =
      Enum.reduce(agent_registry, %{}, fn {agent_type, _pid}, acc ->
        Map.put(acc, agent_type, [])
      end)

    updated_state = %{
      agent.state
      | coordination_session: session_id,
        agent_registry: agent_registry,
        message_queues: message_queues
    }

    {:ok, %{agent | state: updated_state}}
  end

  @doc """
  Send message from one agent to another through the hub.

  ## Parameters
  - `agent` - The hub agent instance  
  - `from_agent` - Source agent type
  - `to_agent` - Target agent type
  - `message` - Message payload

  ## Returns
  - `{:ok, updated_agent}` - Message queued successfully
  - `{:error, reason, agent}` - Message delivery failed
  """
  def send_message(agent, from_agent, to_agent, message) do
    case validate_message_send(agent, from_agent, to_agent, message) do
      :ok ->
        queue_message(agent, from_agent, to_agent, message)

      {:error, reason} ->
        Logger.warning("Message send failed: #{reason}")
        {:error, reason, agent}
    end
  end

  @doc """
  Retrieve messages for a specific agent.

  ## Parameters
  - `agent` - The hub agent instance
  - `agent_type` - Type of agent requesting messages

  ## Returns
  - `{:ok, messages, updated_agent}` - Messages retrieved successfully
  - `{:error, reason, agent}` - Message retrieval failed
  """
  def get_messages(agent, agent_type) do
    case Map.get(agent.state.message_queues, agent_type) do
      nil ->
        {:error, "Agent not registered: #{agent_type}", agent}

      messages ->
        updated_queues = Map.put(agent.state.message_queues, agent_type, [])
        updated_agent = put_in(agent.state.message_queues, updated_queues)

        Logger.debug("Retrieved #{length(messages)} messages for #{agent_type}")
        {:ok, messages, updated_agent}
    end
  end

  @doc """
  Initiate negotiation between disagreeing agents.

  ## Parameters
  - `agent` - The hub agent instance
  - `negotiation_config` - Configuration for negotiation process

  ## Returns
  - `{:ok, negotiation_id, updated_agent}` - Negotiation started
  - `{:error, reason, agent}` - Negotiation failed to start
  """
  def start_negotiation(agent, negotiation_config) do
    negotiation_id = generate_negotiation_id()
    disagreeing_agents = Map.get(negotiation_config, :agents)

    Logger.info(
      "Starting negotiation #{negotiation_id} between agents: #{inspect(disagreeing_agents)}"
    )

    negotiation = %{
      id: negotiation_id,
      agents: disagreeing_agents,
      started_at: DateTime.utc_now(),
      config: negotiation_config,
      rounds: 0,
      max_rounds: Map.get(negotiation_config, :max_rounds, 3),
      status: :active
    }

    updated_negotiations = Map.put(agent.state.pending_negotiations, negotiation_id, negotiation)
    updated_agent = put_in(agent.state.pending_negotiations, updated_negotiations)

    case initialize_negotiation_round(updated_agent, negotiation) do
      {:ok, final_agent} -> {:ok, negotiation_id, final_agent}
      {:error, reason, final_agent} -> {:error, reason, final_agent}
    end
  end

  @doc """
  Process negotiation round and check for resolution.
  """
  def process_negotiation_round(agent, negotiation_id, agent_responses) do
    case Map.get(agent.state.pending_negotiations, negotiation_id) do
      nil ->
        {:error, "Negotiation not found: #{negotiation_id}", agent}

      negotiation ->
        updated_negotiation = %{negotiation | rounds: negotiation.rounds + 1}

        case evaluate_negotiation_progress(updated_negotiation, agent_responses) do
          {:resolved, resolution} ->
            complete_negotiation(agent, negotiation_id, resolution)

          {:continue, next_round_config} ->
            continue_negotiation(agent, negotiation_id, updated_negotiation, next_round_config)

          {:failed, reason} ->
            fail_negotiation(agent, negotiation_id, reason)
        end
    end
  end

  @doc """
  Broadcast message to all agents in coordination session.
  """
  def broadcast_message(agent, message) do
    case agent.state.coordination_session do
      nil ->
        {:error, "No active coordination session", agent}

      _session ->
        results =
          Enum.map(agent.state.agent_registry, fn {agent_type, _pid} ->
            queue_message(agent, :hub, agent_type, message)
          end)

        if Enum.all?(results, &match?({:ok, _}, &1)) do
          {:ok, List.last(results) |> elem(1)}
        else
          failed_count = Enum.count(results, &match?({:error, _, _}, &1))
          {:error, "Failed to broadcast to #{failed_count} agents", agent}
        end
    end
  end

  ## Private Helper Functions

  defp validate_message_send(agent, from_agent, to_agent, message) do
    cond do
      agent.state.coordination_session == nil ->
        {:error, "No active coordination session"}

      not Map.has_key?(agent.state.agent_registry, to_agent) ->
        {:error, "Target agent not registered: #{to_agent}"}

      not is_map(message) ->
        {:error, "Invalid message format"}

      true ->
        :ok
    end
  end

  defp queue_message(agent, from_agent, to_agent, message) do
    current_queue = Map.get(agent.state.message_queues, to_agent, [])

    if length(current_queue) >= agent.state.max_queue_size do
      {:error, "Message queue full for agent: #{to_agent}", agent}
    else
      stamped_message = %{
        from: from_agent,
        to: to_agent,
        payload: message,
        timestamp: DateTime.utc_now(),
        id: generate_message_id()
      }

      updated_queue = [stamped_message | current_queue]
      updated_queues = Map.put(agent.state.message_queues, to_agent, updated_queue)
      updated_agent = put_in(agent.state.message_queues, updated_queues)

      # Add to message history for audit trail
      updated_history = [stamped_message | agent.state.message_history]
      final_agent = put_in(updated_agent.state.message_history, updated_history)

      {:ok, final_agent}
    end
  end

  defp initialize_negotiation_round(agent, negotiation) do
    initial_message = %{
      type: :negotiation_start,
      negotiation_id: negotiation.id,
      round: negotiation.rounds + 1,
      participants: negotiation.agents,
      config: negotiation.config
    }

    case broadcast_to_agents(agent, negotiation.agents, initial_message) do
      {:ok, updated_agent} -> {:ok, updated_agent}
      {:error, reason} -> {:error, reason, agent}
    end
  end

  defp broadcast_to_agents(agent, target_agents, message) do
    results =
      Enum.map(target_agents, fn agent_type ->
        queue_message(agent, :hub, agent_type, message)
      end)

    case List.last(results) do
      {:ok, updated_agent} -> {:ok, updated_agent}
      {:error, reason, _agent} -> {:error, reason}
    end
  end

  defp evaluate_negotiation_progress(negotiation, agent_responses) do
    if negotiation.rounds >= negotiation.max_rounds do
      {:failed, :max_rounds_exceeded}
    else
      case check_for_consensus(agent_responses) do
        {:consensus, resolution} -> {:resolved, resolution}
        :no_consensus -> {:continue, prepare_next_round(agent_responses)}
      end
    end
  end

  defp check_for_consensus(agent_responses) do
    scores = Enum.map(agent_responses, & &1.score)
    score_variance = calculate_variance(scores)

    if score_variance < 0.1 do
      average_score = Enum.sum(scores) / length(scores)
      {:consensus, %{consensus_score: average_score, method: :negotiation}}
    else
      :no_consensus
    end
  end

  defp calculate_variance(values) do
    mean = Enum.sum(values) / length(values)

    Enum.reduce(values, 0.0, fn val, acc ->
      acc + :math.pow(val - mean, 2)
    end) / length(values)
  end

  defp prepare_next_round(agent_responses) do
    disagreement_analysis = analyze_disagreements(agent_responses)

    %{
      focus_areas: disagreement_analysis.main_differences,
      mediation_prompts: generate_mediation_prompts(disagreement_analysis),
      previous_round_summary: summarize_round_results(agent_responses)
    }
  end

  defp analyze_disagreements(agent_responses) do
    %{
      main_differences: identify_key_differences(agent_responses),
      outlier_agents: find_outlier_positions(agent_responses)
    }
  end

  defp identify_key_differences(agent_responses) do
    # Simplified - in practice would analyze reasoning differences
    ["scoring methodology", "priority weighting", "issue severity assessment"]
  end

  defp find_outlier_positions(agent_responses) do
    scores = Enum.map(agent_responses, & &1.score)
    mean_score = Enum.sum(scores) / length(scores)

    Enum.filter(agent_responses, fn response ->
      abs(response.score - mean_score) > 0.2
    end)
  end

  defp generate_mediation_prompts(disagreement_analysis) do
    Enum.map(disagreement_analysis.main_differences, fn difference ->
      "Please reconsider your evaluation focusing on #{difference} and explain your reasoning."
    end)
  end

  defp summarize_round_results(agent_responses) do
    %{
      agent_count: length(agent_responses),
      score_range: calculate_score_range(agent_responses),
      avg_confidence: calculate_avg_confidence(agent_responses)
    }
  end

  defp calculate_score_range(agent_responses) do
    scores = Enum.map(agent_responses, & &1.score)
    Enum.max(scores) - Enum.min(scores)
  end

  defp calculate_avg_confidence(agent_responses) do
    confidences = Enum.map(agent_responses, & &1.confidence)
    Enum.sum(confidences) / length(confidences)
  end

  defp complete_negotiation(agent, negotiation_id, resolution) do
    Logger.info("Negotiation #{negotiation_id} resolved: #{inspect(resolution)}")

    updated_negotiations = Map.delete(agent.state.pending_negotiations, negotiation_id)
    updated_agent = put_in(agent.state.pending_negotiations, updated_negotiations)

    {:ok, resolution, updated_agent}
  end

  defp continue_negotiation(agent, negotiation_id, negotiation, next_round_config) do
    updated_negotiation = Map.merge(negotiation, next_round_config)

    updated_negotiations =
      Map.put(agent.state.pending_negotiations, negotiation_id, updated_negotiation)

    updated_agent = put_in(agent.state.pending_negotiations, updated_negotiations)

    Logger.info("Continuing negotiation #{negotiation_id}, round #{negotiation.rounds}")
    {:continue, next_round_config, updated_agent}
  end

  defp fail_negotiation(agent, negotiation_id, reason) do
    Logger.warning("Negotiation #{negotiation_id} failed: #{reason}")

    updated_negotiations = Map.delete(agent.state.pending_negotiations, negotiation_id)
    updated_agent = put_in(agent.state.pending_negotiations, updated_negotiations)

    {:error, reason, updated_agent}
  end

  defp generate_negotiation_id do
    :crypto.strong_rand_bytes(6) |> Base.encode16() |> String.downcase()
  end

  defp generate_message_id do
    :crypto.strong_rand_bytes(4) |> Base.encode16() |> String.downcase()
  end
end
