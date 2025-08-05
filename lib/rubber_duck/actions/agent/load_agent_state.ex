defmodule RubberDuck.Actions.Agent.LoadAgentState do
  @moduledoc """
  Action for loading persisted agent state from the database.

  This action retrieves saved agent state, experiences, insights,
  and performance metrics to restore an agent's learned knowledge.
  """

  use Jido.Action,
    name: "load_agent_state",
    description: "Load persisted agent state from database",
    schema: [
      agent_name: [type: :string, required: true],
      load_experiences: [type: :boolean, default: true],
      experience_limit: [type: :integer, default: 1000],
      load_all_insights: [type: :boolean, default: false]
    ]

  alias RubberDuck.Agents
  require Logger

  @impl true
  def run(params, _context) do
    case validate_load_params(params) do
      :ok ->
        try do
          case Agents.get_agent_state_by_name(params.agent_name) do
            {:ok, agent_state} ->
              # Build the restored state
              restored_state = %{
                agent_state_id: agent_state.id,
                metadata: agent_state.metadata,
                last_checkpoint: agent_state.last_checkpoint
              }

              # Load experiences if requested
              restored_state = if params.load_experiences do
                experiences = load_experiences(agent_state, params.experience_limit)
                Map.put(restored_state, :experiences, experiences)
              else
                restored_state
              end

              # Load insights
              insights = load_insights(agent_state, params.load_all_insights)
              restored_state = Map.put(restored_state, :insights, insights)

              # Load provider performance
              provider_performance = load_provider_performance(agent_state)
              restored_state = if map_size(provider_performance) > 0 do
                Map.put(restored_state, :provider_performance, provider_performance)
              else
                restored_state
              end

              {:ok, restored_state}

            {:error, _} ->
              # No persisted state found
              {:ok, %{agent_state_id: nil, new_agent: true}}
          end
        rescue
          exception ->
            Logger.error("Failed to load agent state: #{inspect(exception)}\n#{Exception.format_stacktrace()}")
            {:error, %{
              reason: {:exception, exception},
              message: Exception.message(exception),
              agent_name: params.agent_name
            }}
        end

      {:error, reason} ->
        {:error, %{reason: reason, stage: :validation}}
    end
  end

  defp validate_load_params(params) do
    cond do
      not is_map(params) ->
        {:error, :invalid_params}
      not is_binary(params[:agent_name]) ->
        {:error, :invalid_agent_name}
      true ->
        :ok
    end
  end

  defp load_experiences(agent_state, limit) do
    case Agents.list_experiences(%{agent_state_id: agent_state.id, limit: limit}) do
      {:ok, experiences} ->
        # Convert back to the format agents expect
        Enum.map(experiences, fn exp ->
          base = %{
            type: String.to_atom(exp.experience_type),
            timestamp: exp.timestamp
          }

          base
          |> maybe_add_field(:goal, exp.goal)
          |> maybe_add_field(:result, exp.result)
          |> Map.merge(exp.metadata || %{})
        end)

      {:error, reason} ->
        Logger.warning("Failed to load experiences: #{inspect(reason)}")
        []
    end
  end

  defp maybe_add_field(map, _key, nil), do: map
  defp maybe_add_field(map, key, value), do: Map.put(map, key, value)

  defp load_insights(agent_state, load_all) do
    insights_query = if load_all do
      Agents.list_insights(%{agent_state_id: agent_state.id})
    else
      Agents.get_latest_insights(%{agent_state_id: agent_state.id})
    end

    case insights_query do
      {:ok, insights} ->
        # Group by type and take the latest for each type
        insights
        |> Enum.group_by(&String.to_atom(&1.insight_type))
        |> Enum.map(fn {type, type_insights} ->
          # Take the most recent insight for each type
          latest = Enum.max_by(type_insights, & &1.learned_at)
          {type, latest.insights}
        end)
        |> Map.new()

      {:error, reason} ->
        Logger.warning("Failed to load insights: #{inspect(reason)}")
        %{}
    end
  end

  defp load_provider_performance(agent_state) do
    case Agents.get_performance(%{agent_state_id: agent_state.id}) do
      {:ok, performances} ->
        performances
        |> Enum.map(fn perf ->
          {
            String.to_atom(perf.provider_name),
            %{
              success_count: perf.success_count,
              failure_count: perf.failure_count,
              total_duration: perf.total_duration,
              total_tokens: perf.total_tokens,
              quality_sum: perf.quality_sum
            }
          }
        end)
        |> Map.new()

      {:error, reason} ->
        Logger.warning("Failed to load provider performance: #{inspect(reason)}")
        %{}
    end
  end
end
