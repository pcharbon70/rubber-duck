defmodule RubberDuck.Actions.Agent.SaveAgentState do
  @moduledoc """
  Action for persisting agent state to the database.

  This action handles saving the current agent state, including
  experiences, insights, and performance metrics.
  """

  use Jido.Action,
    name: "save_agent_state",
    description: "Persist agent state to database",
    schema: [
      agent: [type: :map, required: true],
      include_experiences: [type: :boolean, default: true],
      experience_batch_size: [type: :integer, default: 100]
    ]

  alias RubberDuck.Agents
  require Logger

  @impl true
  def run(params, _context) do
    case validate_save_params(params) do
      :ok ->
        execute_save_process(params)

      {:error, reason} ->
        {:error, %{reason: reason, stage: :validation}}
    end
  end

  defp execute_save_process(params) do
    agent = params.agent
    {:ok, agent_state} = get_or_create_agent_state(agent)

    results = build_save_results(agent_state, agent, params)
    update_checkpoint(agent_state)

    {:ok, results}
  rescue
    exception ->
      Logger.error("Failed to save agent state: #{inspect(exception)}\n#{Exception.format_stacktrace()}")
      {:error, %{
        reason: {:exception, exception},
        message: Exception.message(exception),
        agent_name: params.agent[:name]
      }}
  end

  defp build_save_results(agent_state, agent, params) do
    %{state_saved: true, agent_state_id: agent_state.id}
    |> maybe_save_experiences(agent_state, agent, params)
    |> save_insights_to_results(agent_state, agent)
    |> maybe_save_provider_performance(agent_state, agent)
  end

  defp maybe_save_experiences(results, agent_state, agent, params) do
    if params.include_experiences do
      case save_experiences(agent_state, agent, params.experience_batch_size) do
        {:ok, count} ->
          Map.put(results, :experiences_saved, count)
      end
    else
      results
    end
  end

  defp save_insights_to_results(results, agent_state, agent) do
    case save_insights(agent_state, agent) do
      {:ok, count} ->
        Map.put(results, :insights_saved, count)
    end
  end

  defp maybe_save_provider_performance(results, agent_state, agent) do
    if Map.has_key?(agent.state, :provider_performance) do
      case save_provider_performance(agent_state, agent) do
        {:ok, count} ->
          Map.put(results, :provider_performance_saved, count)
      end
    else
      results
    end
  end

  defp update_checkpoint(agent_state) do
    case Agents.checkpoint_agent_state!(agent_state) do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.warning("Failed to update checkpoint: #{inspect(reason)}")
    end
  end

  defp validate_save_params(params) do
    cond do
      not is_map(params) ->
        {:error, :invalid_params}
      not is_map(params[:agent]) ->
        {:error, :invalid_agent}
      not is_map(params[:agent][:state]) ->
        {:error, :invalid_agent_state}
      true ->
        :ok
    end
  end

  defp get_or_create_agent_state(agent) do
    case Agents.get_agent_state_by_name(agent.name) do
      {:ok, existing} ->
        # Update metadata
        Agents.update_agent_state(existing, %{
          metadata: extract_metadata(agent),
          last_checkpoint: DateTime.utc_now()
        })

      {:error, _} ->
        # Create new
        Agents.create_agent_state(%{
          agent_name: agent.name,
          agent_type: agent.__struct__ |> Module.split() |> List.last() |> Macro.underscore(),
          metadata: extract_metadata(agent),
          last_checkpoint: DateTime.utc_now()
        })
    end
  end

  defp extract_metadata(agent) do
    # Extract relevant metadata, excluding transient data
    agent.state
    |> Map.drop([:experience, :request_cache, :provider_performance, :learned_insights])
    |> Map.take([:goals, :completed_goals, :learning_enabled, :performance_metrics,
                 :monitoring_active, :auto_recovery_enabled, :alert_threshold,
                 :optimization_preference, :quality_threshold, :cost_budget])
  end

  defp save_experiences(agent_state, agent, batch_size) do
    experiences = agent.state[:experience] || []

    # Save in batches
    results = experiences
    |> Enum.take(1000)  # Only save most recent 1000
    |> Enum.chunk_every(batch_size)
    |> Enum.map(fn batch ->
      Enum.map(batch, fn exp ->
        Agents.create_experience(%{
          agent_state_id: agent_state.id,
          experience_type: determine_experience_type(exp),
          goal: exp[:goal],
          result: exp[:result],
          metadata: Map.drop(exp, [:goal, :result, :timestamp]),
          timestamp: exp[:timestamp] || DateTime.utc_now()
        })
      end)
    end)
    |> List.flatten()

    successful = Enum.count(results, &match?({:ok, _}, &1))

    {:ok, successful}
  end

  defp determine_experience_type(experience) do
    cond do
      experience[:type] -> to_string(experience.type)
      experience[:goal] -> "goal_related"
      experience[:result] -> "result"
      true -> "general"
    end
  end

  defp save_insights(agent_state, agent) do
    insights = agent.state[:learned_insights] || %{}

    results = Enum.map(insights, fn {type, insight_data} ->
      Agents.create_insight(%{
        agent_state_id: agent_state.id,
        insight_type: to_string(type),
        insights: insight_data,
        confidence: calculate_confidence(insight_data),
        applicable_scenarios: extract_scenarios(insight_data)
      })
    end)

    successful = Enum.count(results, &match?({:ok, _}, &1))

    {:ok, successful}
  end

  defp calculate_confidence(insight_data) do
    cond do
      is_number(insight_data[:confidence]) -> insight_data.confidence
      is_number(insight_data[:pattern_confidence]) -> insight_data.pattern_confidence
      is_number(insight_data[:prediction_accuracy]) -> insight_data.prediction_accuracy
      true -> 0.7
    end
  end

  defp extract_scenarios(insight_data) do
    case insight_data[:applicable_scenarios] do
      scenarios when is_list(scenarios) -> scenarios
      _ -> []
    end
  end

  defp save_provider_performance(agent_state, agent) do
    performances = agent.state[:provider_performance] || %{}

    results = Enum.map(performances, fn {provider_name, stats} ->
      Agents.upsert_performance(%{
        agent_state_id: agent_state.id,
        provider_name: to_string(provider_name),
        success_count: stats[:success_count] || 0,
        failure_count: stats[:failure_count] || 0,
        total_duration: stats[:total_duration] || 0,
        total_tokens: stats[:total_tokens] || 0,
        quality_sum: stats[:quality_sum] || 0.0
      })
    end)

    successful = Enum.count(results, &match?({:ok, _}, &1))

    {:ok, successful}
  end
end
