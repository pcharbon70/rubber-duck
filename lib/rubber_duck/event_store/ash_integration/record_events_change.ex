defmodule RubberDuck.EventStore.AshIntegration.RecordEventsChange do
  @moduledoc """
  Ash change module that automatically records events for entity changes.
  
  This change can be added to Ash Resource actions to automatically record
  events in the EventStore whenever entities are created, updated, or deleted.
  
  ## Usage
  
  Add to your Ash Resource actions:
  
      update :update do
        accept [:name, :description]
        change RecordEventsChange
      end
      
      create :create do
        accept [:name, :description]
        change RecordEventsChange
      end
      
      destroy :destroy do
        change RecordEventsChange
      end
  """

  use Ash.Resource.Change

  alias RubberDuck.EventStore

  require Logger

  @impl true
  def change(changeset, _opts, context) do
    # Record the event after the change is committed
    Ash.Changeset.after_action(changeset, fn changeset, result ->
      try do
        record_event(changeset, result, context)
        {:ok, result}
      rescue
        error ->
          Logger.error("Failed to record event: #{inspect(error)}")
          # Don't fail the main operation if event recording fails
          {:ok, result}
      end
    end)
  end

  defp record_event(changeset, result, context) do
    action_type = changeset.action.type

    case action_type do
      :create ->
        record_creation_event(result, context)
        
      :update ->
        record_update_event(changeset, result, context)
        
      :destroy ->
        record_deletion_event(result, context)
        
      _ ->
        Logger.debug("Skipping event recording for action type: #{action_type}")
        :ok
    end
  end

  defp record_creation_event(entity, context) do
    metadata = extract_metadata(context)
    
    case EventStore.record_entity_creation(entity, metadata) do
      :ok ->
        Logger.debug("Recorded entity creation event for #{inspect(entity.__struct__)} #{get_entity_id(entity)}")
        
      {:error, reason} ->
        Logger.error("Failed to record entity creation event: #{inspect(reason)}")
    end
  end

  defp record_update_event(changeset, entity, context) do
    changes = extract_changes(changeset)
    impact = calculate_impact(changeset, entity, context)
    
    case EventStore.record_entity_update(entity, changes, impact) do
      :ok ->
        Logger.debug("Recorded entity update event for #{inspect(entity.__struct__)} #{get_entity_id(entity)}")
        
      {:error, reason} ->
        Logger.error("Failed to record entity update event: #{inspect(reason)}")
    end
  end

  defp record_deletion_event(entity, context) do
    reason = extract_deletion_reason(context)
    
    case EventStore.record_entity_deletion(entity, reason) do
      :ok ->
        Logger.debug("Recorded entity deletion event for #{inspect(entity.__struct__)} #{get_entity_id(entity)}")
        
      {:error, reason} ->
        Logger.error("Failed to record entity deletion event: #{inspect(reason)}")
    end
  end

  defp extract_changes(changeset) do
    # Get the actual changed attributes
    changeset.changes
  end

  defp extract_metadata(context) do
    %{
      actor: get_actor_info(context),
      source: get_source_info(context),
      request_id: get_request_id(context),
      timestamp: DateTime.utc_now()
    }
  end

  defp calculate_impact(changeset, entity, context) do
    changed_fields = Map.keys(extract_changes(changeset))
    
    %{
      changed_fields: changed_fields,
      change_count: length(changed_fields),
      risk_level: assess_risk_level(changed_fields, entity),
      actor: get_actor_info(context),
      estimated_downstream_impact: estimate_downstream_impact(entity, changed_fields)
    }
  end

  defp extract_deletion_reason(context) do
    %{
      deleted_by: get_actor_info(context),
      deletion_source: get_source_info(context),
      timestamp: DateTime.utc_now()
    }
  end

  defp get_actor_info(context) do
    cond do
      Map.has_key?(context, :actor) and not is_nil(context.actor) ->
        %{
          id: get_entity_id(context.actor),
          type: get_entity_type_name(context.actor)
        }
        
      Map.has_key?(context, :user) and not is_nil(context.user) ->
        %{
          id: get_entity_id(context.user),
          type: "user"
        }
        
      true ->
        %{id: "system", type: "system"}
    end
  end

  defp get_source_info(context) do
    Map.get(context, :source, "ash_action")
  end

  defp get_request_id(context) do
    Map.get(context, :request_id, Ecto.UUID.generate())
  end

  defp assess_risk_level(changed_fields, entity) do
    # Basic risk assessment based on changed fields
    critical_fields = get_critical_fields(entity)
    
    cond do
      Enum.any?(changed_fields, &(&1 in critical_fields)) ->
        :high
        
      length(changed_fields) > 5 ->
        :medium
        
      true ->
        :low
    end
  end

  defp get_critical_fields(entity) do
    case get_entity_type_name(entity) do
      "user" -> [:email, :username, :hashed_password]
      "project" -> [:status, :owner_id]
      "code_file" -> [:content, :status]
      "analysis_result" -> [:status, :score]
      _ -> []
    end
  end

  defp estimate_downstream_impact(entity, changed_fields) do
    # Basic downstream impact estimation
    entity_type = get_entity_type_name(entity)
    
    impact_score = 
      case entity_type do
        "user" ->
          if Enum.member?(changed_fields, "email") or Enum.member?(changed_fields, "username") do
            0.8
          else
            0.3
          end
          
        "project" ->
          if Enum.member?(changed_fields, "status") do
            0.7
          else
            0.3
          end
          
        "code_file" ->
          if Enum.member?(changed_fields, "content") do
            0.6
          else
            0.3
          end
          
        _ ->
          0.3
      end
    
    %{
      estimated_affected_entities: estimate_affected_entity_count(entity, changed_fields),
      impact_score: impact_score,
      propagation_likely: impact_score > 0.5
    }
  end

  defp estimate_affected_entity_count(_entity, _changed_fields) do
    # Placeholder - in a real implementation, you'd query related entities
    rand_count = :rand.uniform(10)
    %{
      users: if(rand_count > 7, do: :rand.uniform(5), else: 0),
      projects: if(rand_count > 5, do: :rand.uniform(3), else: 0),
      code_files: if(rand_count > 3, do: :rand.uniform(10), else: 0)
    }
  end

  defp get_entity_id(%{id: id}), do: id
  defp get_entity_id(_), do: "unknown"

  defp get_entity_type_name(entity) do
    entity.__struct__
    |> to_string()
    |> String.split(".")
    |> List.last()
    |> String.downcase()
  end
end