defmodule RubberDuck.Actions.Agent.PruneExperiences do
  @moduledoc """
  Action for pruning old agent experiences from the database.
  
  This action removes experiences older than the specified retention
  period to manage database size while preserving recent learning data.
  """
  
  use Jido.Action,
    name: "prune_experiences",
    description: "Remove old agent experiences beyond retention period",
    schema: [
      retention_days: [type: :integer, default: 30],
      agent_name: [type: :string, required: false],
      dry_run: [type: :boolean, default: false]
    ]
  
  alias RubberDuck.Agents
  require Logger
  
  @impl true
  def run(params, _context) do
    with :ok <- validate_prune_params(params) do
      try do
        if params.dry_run do
          # Just count what would be deleted
          perform_dry_run(params)
        else
          # Actually delete old experiences
          perform_prune(params)
        end
      rescue
        exception ->
          Logger.error("Failed to prune experiences: #{inspect(exception)}\n#{Exception.format_stacktrace()}")
          {:error, %{
            reason: {:exception, exception},
            message: Exception.message(exception)
          }}
      end
    else
      {:error, reason} -> {:error, %{reason: reason, stage: :validation}}
    end
  end
  
  defp validate_prune_params(params) do
    cond do
      not is_map(params) ->
        {:error, :invalid_params}
      params[:retention_days] && params.retention_days < 1 ->
        {:error, :invalid_retention_days}
      true ->
        :ok
    end
  end
  
  defp perform_dry_run(params) do
    cutoff_date = calculate_cutoff_date(params.retention_days)
    
    count = if params[:agent_name] do
      # Count for specific agent
      case Agents.get_agent_state_by_name(params.agent_name) do
        {:ok, agent_state} ->
          count_experiences_to_prune(agent_state.id, cutoff_date)
        {:error, _} ->
          0
      end
    else
      # Count for all agents
      count_all_experiences_to_prune(cutoff_date)
    end
    
    {:ok, %{
      dry_run: true,
      would_delete: count,
      retention_days: params.retention_days,
      cutoff_date: cutoff_date
    }}
  end
  
  defp perform_prune(params) do
    start_time = System.monotonic_time(:millisecond)
    
    result = case Agents.prune_old_experiences(%{retention_days: params.retention_days}) do
      {:ok, deleted_count} ->
        duration = System.monotonic_time(:millisecond) - start_time
        
        Logger.info("Pruned #{deleted_count} experiences older than #{params.retention_days} days in #{duration}ms")
        
        {:ok, %{
          deleted_count: deleted_count,
          retention_days: params.retention_days,
          duration_ms: duration,
          cutoff_date: calculate_cutoff_date(params.retention_days)
        }}
        
      {:error, reason} ->
        {:error, %{reason: reason, stage: :deletion}}
    end
    
    # Also clean up orphaned insights if any
    clean_orphaned_data()
    
    result
  end
  
  defp calculate_cutoff_date(retention_days) do
    DateTime.utc_now()
    |> DateTime.add(-retention_days * 24 * 60 * 60, :second)
  end
  
  defp count_experiences_to_prune(agent_state_id, cutoff_date) do
    # This is a simplified count - in production you'd use Ash aggregates
    case Agents.list_experiences(%{agent_state_id: agent_state_id}) do
      {:ok, experiences} ->
        Enum.count(experiences, fn exp ->
          DateTime.compare(exp.timestamp, cutoff_date) == :lt
        end)
      {:error, _} ->
        0
    end
  end
  
  defp count_all_experiences_to_prune(cutoff_date) do
    # This would need a custom query in production
    # For now, return a placeholder
    Logger.debug("Would count all experiences older than #{cutoff_date}")
    0
  end
  
  defp clean_orphaned_data do
    # Clean up any insights or performance data for agents that no longer exist
    # This would be implemented with custom queries in production
    :ok
  end
end