defmodule RubberDuck.Agents.VerdictOrchestratorAgent do
  @moduledoc """
  Central orchestrator agent for coordinating multi-agent Verdict evaluations.

  Coordinates specialized judge agents for comprehensive code evaluation using
  consensus mechanisms, conflict resolution, and intelligent routing. Extends
  the existing Verdict framework with sophisticated multi-agent capabilities.
  """

  alias RubberDuck.Verdict.Adaptation.DynamicRoutingEngine
  alias RubberDuck.Verdict.Coordination.ConsensusEngine

  require Logger

  @doc """
  Coordinate multi-agent evaluation for complex code assessment.

  ## Parameters
  - `agent` - Current orchestrator agent state
  - `code` - Code to evaluate
  - `evaluation_type` - Type of evaluation requested
  - `options` - Evaluation options and configuration

  ## Returns
  - `{:ok, consensus_result, updated_agent}` - Successful coordinated evaluation
  - `{:error, reason, agent}` - Coordination failed with reason
  """
  def coordinate_evaluation(agent, code, evaluation_type, options \\ []) do
    coordination_id = generate_coordination_id()

    Logger.info("Starting multi-agent evaluation coordination: #{coordination_id}")

    case initialize_coordination_session(agent, coordination_id, code, evaluation_type, options) do
      {:ok, session, updated_agent} ->
        execute_coordinated_evaluation(updated_agent, session)

      {:error, reason} ->
        {:error, reason, agent}
    end
  end

  @doc """
  Get orchestrator agent state and coordination statistics.
  """
  def get_coordination_stats(agent) do
    stats = %{
      active_coordinations: get_active_coordination_count(agent),
      total_coordinations: get_total_coordination_count(agent),
      average_consensus_time: get_average_consensus_time(agent),
      agent_performance: get_agent_performance_summary(agent),
      coordination_success_rate: calculate_coordination_success_rate(agent)
    }

    {:ok, stats, agent}
  end

  @doc """
  Configure orchestrator agent with evaluation preferences.
  """
  def configure_orchestration(agent, config) do
    merged_config = Map.merge(agent.orchestration_config, config)
    updated_agent = %{agent | orchestration_config: merged_config}

    Logger.info("Updated orchestrator configuration")
    {:ok, updated_agent}
  end

  @doc """
  Initialize orchestrator agent with default configuration.
  """
  def create_verdict_orchestrator_agent(initial_context \\ %{}) do
    agent = %{
      agent_type: :verdict_orchestrator,
      coordination_sessions: %{},
      agent_pool: %{},
      orchestration_config: %{
        max_concurrent_coordinations: 5,
        default_consensus_threshold: 0.7,
        agent_timeout_ms: 15_000,
        enable_parallel_evaluation: true,
        fallback_to_single_judge: true
      },
      performance_metrics: %{
        total_coordinations: 0,
        successful_coordinations: 0,
        failed_coordinations: 0,
        average_consensus_time_ms: 0,
        agent_utilization: %{}
      },
      context: initial_context
    }

    Logger.info("Created VerdictOrchestratorAgent")
    {:ok, agent}
  end

  ## Private Functions

  defp initialize_coordination_session(agent, coordination_id, code, evaluation_type, options) do
    session = %{
      coordination_id: coordination_id,
      code: code,
      evaluation_type: evaluation_type,
      options: options,
      started_at: DateTime.utc_now(),
      status: :initializing,
      selected_agents: [],
      evaluation_results: %{},
      consensus_state: nil,
      metadata: %{
        user_id: Keyword.get(options, :user_id),
        project_id: Keyword.get(options, :project_id)
      }
    }

    # Select appropriate judge agents for this evaluation
    case select_judge_agents(agent, evaluation_type, options) do
      {:ok, selected_agents} ->
        updated_session = %{
          session
          | selected_agents: selected_agents,
            status: :agent_selection_complete
        }

        updated_agent = add_coordination_session(agent, coordination_id, updated_session)

        {:ok, updated_session, updated_agent}

      {:error, reason} ->
        {:error, "Agent selection failed: #{reason}"}
    end
  end

  defp execute_coordinated_evaluation(agent, session) do
    case orchestrate_parallel_evaluation(agent, session) do
      {:ok, evaluation_results, updated_agent} ->
        case reach_consensus(updated_agent, session, evaluation_results) do
          {:ok, consensus_result, final_agent} ->
            # Record successful coordination
            coordination_result = finalize_coordination(final_agent, session, consensus_result)
            {:ok, coordination_result, final_agent}

          {:error, reason} ->
            # Handle consensus failure
            handle_consensus_failure(updated_agent, session, reason)
        end

      {:error, reason} ->
        # Handle evaluation failure
        handle_evaluation_failure(agent, session, reason)
    end
  end

  defp select_judge_agents(_agent, evaluation_type, options) do
    # Use adaptive routing for intelligent judge selection
    evaluation_context = build_evaluation_context(evaluation_type, options)
    available_judges = [:code_quality, :architecture, :test_quality, :security]
    user_profile = extract_user_profile(options)

    case DynamicRoutingEngine.select_optimal_judges(
           evaluation_context,
           available_judges,
           user_profile,
           options
         ) do
      {:ok, judge_selection} ->
        Logger.info(
          "Adaptive judge selection: #{inspect(judge_selection.selected_judges)} (confidence: #{judge_selection.selection_confidence})"
        )

        {:ok, judge_selection.selected_judges}

      {:error, reason} ->
        Logger.warning("Adaptive routing failed, using fallback: #{reason}")
        fallback_judge_selection(evaluation_type, options)
    end
  end

  defp orchestrate_parallel_evaluation(agent, session) do
    # Execute evaluations in parallel using selected agents
    agent_tasks =
      Enum.map(session.selected_agents, fn agent_type ->
        Task.async(fn ->
          execute_single_agent_evaluation(
            agent_type,
            session.code,
            session.evaluation_type,
            session.options
          )
        end)
      end)

    # Wait for all agents to complete with timeout
    timeout = get_agent_timeout(agent)

    try do
      results = Task.await_many(agent_tasks, timeout)

      # Process results and update agent state
      evaluation_results = process_agent_results(results, session.selected_agents)
      updated_agent = record_agent_completion(agent, session.coordination_id, evaluation_results)

      {:ok, evaluation_results, updated_agent}
    rescue
      error ->
        Logger.error("Parallel evaluation failed: #{inspect(error)}")
        {:error, "Parallel evaluation timeout or failure"}
    end
  end

  defp reach_consensus(agent, session, evaluation_results) do
    consensus_config = get_consensus_config(agent)

    case ConsensusEngine.compute_consensus(evaluation_results, consensus_config) do
      {:ok, consensus_result} ->
        # Record consensus success
        updated_agent = record_consensus_success(agent, session.coordination_id, consensus_result)
        {:ok, consensus_result, updated_agent}

      {:error, :no_consensus} ->
        # Conflict resolution not yet implemented - use fallback
        # TODO: Implement ConflictResolver.resolve_evaluation_conflicts/2
        Logger.warning("Consensus failed, using fallback strategy")
        handle_consensus_failure(agent, session, :no_consensus)

      error ->
        error
    end
  end

  defp finalize_coordination(agent, session, consensus_result) do
    # Create final coordination result
    coordination_result = %{
      coordination_id: session.coordination_id,
      evaluation_type: session.evaluation_type,
      consensus_result: consensus_result,
      agents_used: session.selected_agents,
      coordination_time_ms: calculate_coordination_time(session),
      consensus_confidence: consensus_result.consensus_confidence,
      individual_results: length(Map.keys(session.evaluation_results || %{})),
      cost_distribution: calculate_cost_distribution(consensus_result),
      metadata: session.metadata
    }

    # Update performance metrics
    _updated_agent = update_coordination_metrics(agent, :success, coordination_result)

    coordination_result
  end

  defp handle_consensus_failure(agent, session, reason) do
    Logger.warning("Consensus failed for coordination #{session.coordination_id}: #{reason}")

    # Fall back to single best evaluation if configured
    case get_fallback_strategy(agent) do
      :single_best ->
        fallback_result = select_best_individual_result(session.evaluation_results)
        updated_agent = update_coordination_metrics(agent, :fallback, %{reason: reason})
        {:ok, fallback_result, updated_agent}

      :fail ->
        updated_agent = update_coordination_metrics(agent, :failed, %{reason: reason})
        {:error, "Consensus failed: #{reason}", updated_agent}
    end
  end

  defp handle_evaluation_failure(agent, session, reason) do
    Logger.error("Evaluation failed for coordination #{session.coordination_id}: #{reason}")

    updated_agent = update_coordination_metrics(agent, :failed, %{reason: reason})
    {:error, "Evaluation failed: #{reason}", updated_agent}
  end

  # Helper functions

  defp generate_coordination_id do
    "coord_#{System.unique_integer([:positive])}_#{DateTime.utc_now() |> DateTime.to_unix()}"
  end

  defp determine_agent_strategy(evaluation_type, options) do
    force_comprehensive = Keyword.get(options, :force_comprehensive, false)
    budget_tier = Keyword.get(options, :budget_tier, :standard)

    strategy =
      cond do
        force_comprehensive -> :comprehensive
        evaluation_type == :security -> :security_focused
        evaluation_type == :quality -> :quality_focused
        evaluation_type == :performance -> :performance_focused
        budget_tier == :premium -> :comprehensive
        true -> :quality_focused
      end

    {:ok, strategy}
  end

  defp execute_single_agent_evaluation(agent_type, code, evaluation_type, _options) do
    # Execute evaluation using specific judge agent
    case agent_type do
      :code_quality ->
        # Would use CodeQualityJudgeAgent.evaluate
        simulate_agent_evaluation("code_quality", code, evaluation_type)

      :architecture ->
        # Would use ArchitectureJudgeAgent.evaluate
        simulate_agent_evaluation("architecture", code, evaluation_type)

      :test_quality ->
        # Would use TestQualityJudgeAgent.evaluate
        simulate_agent_evaluation("test_quality", code, evaluation_type)

      :security ->
        # Would use SecurityJudgeAgent.evaluate
        simulate_agent_evaluation("security", code, evaluation_type)

      _ ->
        {:error, "Unknown agent type: #{agent_type}"}
    end
  end

  defp simulate_agent_evaluation(agent_name, _code, _evaluation_type) do
    # Mock agent evaluation for now
    {:ok,
     %{
       agent_type: agent_name,
       score: 0.75 + (:rand.uniform() * 0.2 - 0.1),
       confidence: 0.8 + (:rand.uniform() * 0.15 - 0.075),
       issues: ["#{agent_name}: Issue found in code"],
       recommendations: ["#{agent_name}: Recommendation for improvement"],
       reasoning: "#{agent_name} evaluation reasoning",
       tokens_used: 200 + :rand.uniform(300),
       cost_usd: 0.01 + :rand.uniform() * 0.02,
       latency_ms: 1_000 + :rand.uniform(2_000)
     }}
  end

  defp process_agent_results(results, agent_types) do
    # Process parallel agent results into structured format
    Enum.zip(agent_types, results)
    |> Enum.reduce(%{}, fn {agent_type, result}, acc ->
      case result do
        {:ok, evaluation_result} ->
          Map.put(acc, agent_type, evaluation_result)

        {:error, reason} ->
          Logger.warning("Agent #{agent_type} failed: #{reason}")
          acc
      end
    end)
  end

  defp get_agent_timeout(agent) do
    Map.get(agent.orchestration_config, :agent_timeout_ms, 15_000)
  end

  defp get_consensus_config(agent) do
    %{
      consensus_threshold: Map.get(agent.orchestration_config, :default_consensus_threshold, 0.7),
      voting_method: :weighted_average,
      conflict_resolution: :negotiation
    }
  end

  defp get_fallback_strategy(agent) do
    if Map.get(agent.orchestration_config, :fallback_to_single_judge, true) do
      :single_best
    else
      :fail
    end
  end

  defp add_coordination_session(agent, coordination_id, session) do
    sessions = Map.put(agent.coordination_sessions, coordination_id, session)
    Map.put(agent, :coordination_sessions, sessions)
  end

  defp record_agent_completion(agent, coordination_id, results) do
    session = Map.get(agent.coordination_sessions, coordination_id)
    updated_session = Map.put(session, :evaluation_results, results)

    add_coordination_session(agent, coordination_id, updated_session)
  end

  defp record_consensus_success(agent, _coordination_id, _consensus_result) do
    # Update performance metrics
    metrics = agent.performance_metrics

    updated_metrics = %{
      metrics
      | successful_coordinations: metrics.successful_coordinations + 1,
        total_coordinations: metrics.total_coordinations + 1
    }

    Map.put(agent, :performance_metrics, updated_metrics)
  end

  defp update_coordination_metrics(agent, outcome, _metadata) do
    metrics = agent.performance_metrics

    updated_metrics =
      case outcome do
        :success ->
          %{
            metrics
            | successful_coordinations: metrics.successful_coordinations + 1,
              total_coordinations: metrics.total_coordinations + 1
          }

        :fallback ->
          %{metrics | total_coordinations: metrics.total_coordinations + 1}

        :failed ->
          %{
            metrics
            | failed_coordinations: metrics.failed_coordinations + 1,
              total_coordinations: metrics.total_coordinations + 1
          }
      end

    Map.put(agent, :performance_metrics, updated_metrics)
  end

  defp calculate_coordination_time(session) do
    DateTime.diff(DateTime.utc_now(), session.started_at, :millisecond)
  end

  defp calculate_cost_distribution(consensus_result) do
    # Calculate how costs were distributed across agents
    %{
      total_cost: consensus_result.total_cost || 0.0,
      agent_costs: consensus_result.agent_cost_breakdown || %{},
      # Small overhead for coordination
      coordination_overhead: 0.001
    }
  end

  defp select_best_individual_result(evaluation_results) do
    # Select the best individual result as fallback
    case Enum.max_by(
           evaluation_results,
           fn {_agent, result} ->
             result.confidence * result.score
           end,
           fn -> nil end
         ) do
      {agent_type, result} ->
        %{
          fallback_used: true,
          selected_agent: agent_type,
          score: result.score,
          confidence: result.confidence,
          issues: result.issues,
          recommendations: result.recommendations,
          reasoning: "Fallback result from #{agent_type} agent: #{result.reasoning}"
        }

      nil ->
        %{
          fallback_used: true,
          error: "No valid results available for fallback"
        }
    end
  end

  # Performance metrics helpers

  defp get_active_coordination_count(agent) do
    agent.coordination_sessions
    |> Enum.count(fn {_id, session} ->
      session.status in [:initializing, :evaluating, :consensus]
    end)
  end

  defp get_total_coordination_count(agent) do
    agent.performance_metrics.total_coordinations
  end

  defp get_average_consensus_time(agent) do
    agent.performance_metrics.average_consensus_time_ms
  end

  defp get_agent_performance_summary(agent) do
    agent.performance_metrics.agent_utilization || %{}
  end

  defp calculate_coordination_success_rate(agent) do
    metrics = agent.performance_metrics

    if metrics.total_coordinations > 0 do
      metrics.successful_coordinations / metrics.total_coordinations
    else
      0.0
    end
  end

  # Integration helper functions

  defp build_evaluation_context(evaluation_type, options) do
    %{
      evaluation_type: evaluation_type,
      complexity: determine_evaluation_complexity(evaluation_type, options),
      quality_requirements: extract_quality_requirements(options),
      cost_constraints: extract_cost_constraints(options),
      urgency: Keyword.get(options, :urgency, :normal),
      user_context: extract_user_context(options)
    }
  end

  defp extract_user_profile(options) do
    # Extract user profile from options if available
    Keyword.get(options, :user_profile, nil)
  end

  defp fallback_judge_selection(evaluation_type, options) do
    # Fallback to original strategy-based selection
    case determine_agent_strategy(evaluation_type, options) do
      {:ok, strategy} ->
        selected_agents =
          case strategy do
            :comprehensive -> [:code_quality, :architecture, :test_quality, :security]
            :security_focused -> [:security, :code_quality, :architecture]
            :quality_focused -> [:code_quality, :test_quality, :architecture]
            :performance_focused -> [:architecture, :code_quality]
            _ -> [:code_quality]
          end

        {:ok, selected_agents}

      error ->
        error
    end
  end

  defp determine_evaluation_complexity(evaluation_type, options) do
    # Determine complexity based on evaluation type and options
    base_complexity =
      case evaluation_type do
        :comprehensive_evaluation -> :high
        :security_evaluation -> :high
        :performance_evaluation -> :medium
        :basic_evaluation -> :low
        _ -> :medium
      end

    # Adjust based on options
    complexity_override = Keyword.get(options, :complexity_override, nil)
    complexity_override || base_complexity
  end

  defp extract_quality_requirements(options) do
    %{
      min_accuracy: Keyword.get(options, :min_accuracy, 0.8),
      thoroughness: Keyword.get(options, :thoroughness, :standard),
      quality_priority: Keyword.get(options, :quality_priority, :medium)
    }
  end

  defp extract_cost_constraints(options) do
    %{
      max_cost: Keyword.get(options, :max_cost, 0.15),
      cost_priority: Keyword.get(options, :cost_priority, :medium),
      budget_limit: Keyword.get(options, :budget_limit, 0.2)
    }
  end

  defp extract_user_context(options) do
    %{
      user_id: Keyword.get(options, :user_id, nil),
      user_preferences: Keyword.get(options, :user_preferences, %{}),
      session_context: Keyword.get(options, :session_context, %{})
    }
  end
end
