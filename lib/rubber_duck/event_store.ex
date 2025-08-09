defmodule RubberDuck.EventStore do
  @moduledoc """
  EventStore for RubberDuck application.
  
  Provides event sourcing capabilities for tracking all entity changes,
  enabling audit trails, replay functionality, and learning from historical data.
  
  ## Usage
  
      # Record an entity update
      RubberDuck.EventStore.record_entity_update(entity, changes, impact)
      
      # Read events for an entity
      {:ok, events} = RubberDuck.EventStore.read_entity_stream(entity_id)
      
      # Subscribe to events
      :ok = RubberDuck.EventStore.subscribe_to_stream("entity-updates")
  """

  use EventStore, otp_app: :rubber_duck

  alias __MODULE__.Events.{EntityUpdated, EntityCreated, EntityDeleted}

  @doc """
  Records an entity update event.
  
  ## Parameters
  
  - `entity` - The entity struct that was updated
  - `changes` - Map of changes that were applied
  - `impact` - Impact assessment data from the update
  
  ## Returns
  
  - `:ok` - Event successfully recorded
  - `{:error, reason}` - Failed to record event
  """
  @spec record_entity_update(struct(), map(), map()) :: :ok | {:error, term()}
  def record_entity_update(entity, changes, impact) do
    stream_uuid = build_entity_stream_id(entity)
    
    event = %EntityUpdated{
      entity_id: get_entity_id(entity),
      entity_type: get_entity_type(entity),
      changes: changes,
      impact: impact,
      timestamp: DateTime.utc_now()
    }
    
    event_data = %EventStore.EventData{
      event_type: "Elixir.RubberDuck.EventStore.Events.EntityUpdated",
      data: event,
      metadata: %{
        correlation_id: generate_correlation_id(),
        causation_id: generate_causation_id(),
        created_at: DateTime.utc_now()
      }
    }
    
    append_to_stream(stream_uuid, :any_version, [event_data])
  end

  @doc """
  Records an entity creation event.
  """
  @spec record_entity_creation(struct(), map()) :: :ok | {:error, term()}
  def record_entity_creation(entity, metadata \\ %{}) do
    stream_uuid = build_entity_stream_id(entity)
    
    event = %EntityCreated{
      entity_id: get_entity_id(entity),
      entity_type: get_entity_type(entity),
      entity_data: strip_ecto_metadata(entity),
      timestamp: DateTime.utc_now()
    }
    
    event_data = %EventStore.EventData{
      event_type: "Elixir.RubberDuck.EventStore.Events.EntityCreated",
      data: event,
      metadata: Map.merge(%{
        correlation_id: generate_correlation_id(),
        causation_id: generate_causation_id(),
        created_at: DateTime.utc_now()
      }, metadata)
    }
    
    append_to_stream(stream_uuid, :no_stream, [event_data])
  end

  @doc """
  Records an entity deletion event.
  """
  @spec record_entity_deletion(struct(), map()) :: :ok | {:error, term()}
  def record_entity_deletion(entity, reason \\ %{}) do
    stream_uuid = build_entity_stream_id(entity)
    
    event = %EntityDeleted{
      entity_id: get_entity_id(entity),
      entity_type: get_entity_type(entity),
      reason: reason,
      timestamp: DateTime.utc_now()
    }
    
    event_data = %EventStore.EventData{
      event_type: "Elixir.RubberDuck.EventStore.Events.EntityDeleted",
      data: event,
      metadata: %{
        correlation_id: generate_correlation_id(),
        causation_id: generate_causation_id(),
        created_at: DateTime.utc_now()
      }
    }
    
    append_to_stream(stream_uuid, :any_version, [event_data])
  end

  @doc """
  Reads all events for a specific entity.
  """
  @spec read_entity_stream(String.t()) :: {:ok, list(EventStore.RecordedEvent.t())} | {:error, term()}
  def read_entity_stream(entity_id) do
    stream_uuid = "entity-#{entity_id}"
    read_stream_forward(stream_uuid)
  end

  @doc """
  Reads events for a specific entity type.
  """
  @spec read_entity_type_stream(atom()) :: {:ok, list(EventStore.RecordedEvent.t())} | {:error, term()}
  def read_entity_type_stream(entity_type) do
    stream_uuid = "entity-type-#{entity_type}"
    read_stream_forward(stream_uuid)
  end

  @doc """
  Subscribes to all entity update events.
  """
  @spec subscribe_to_entity_updates(pid()) :: :ok | {:error, term()}
  def subscribe_to_entity_updates(subscriber_pid) do
    subscribe_to_stream("entity-updates", "entity-updates-subscription", subscriber_pid, [])
  end

  @doc """
  Gets the event history for an entity as a list of readable events.
  """
  @spec get_entity_history(String.t()) :: {:ok, list(map())} | {:error, term()}
  def get_entity_history(entity_id) do
    case read_entity_stream(entity_id) do
      {:ok, recorded_events} ->
        history = 
          Enum.map(recorded_events, fn recorded_event ->
            %{
              event_id: recorded_event.event_id,
              event_type: recorded_event.event_type,
              data: recorded_event.data,
              metadata: recorded_event.metadata,
              stream_id: recorded_event.stream_uuid,  # Use stream_uuid
              stream_version: recorded_event.stream_version,
              created_at: recorded_event.created_at
            }
          end)
        
        {:ok, history}
        
      {:error, :stream_not_found} ->
        # Return empty history for non-existent entities
        {:ok, []}
        
      error ->
        error
    end
  end

  @doc """
  Replays events for an entity to reconstruct its state.
  This is a basic implementation - in practice you'd want more sophisticated replay logic.
  """
  @spec replay_entity(String.t()) :: {:ok, map()} | {:error, term()}
  def replay_entity(entity_id) do
    case read_entity_stream(entity_id) do
      {:ok, recorded_events} ->
        final_state = 
          Enum.reduce(recorded_events, %{}, fn recorded_event, state ->
            apply_event_to_state(state, recorded_event)
          end)
        
        {:ok, final_state}
        
      {:error, :stream_not_found} ->
        # Return empty state for non-existent entities  
        {:ok, %{}}
        
      error ->
        error
    end
  end

  # Private functions

  defp build_entity_stream_id(entity) do
    entity_id = get_entity_id(entity)
    "entity-#{entity_id}"
  end

  defp get_entity_id(%{id: id}), do: id
  defp get_entity_id(entity) do
    raise ArgumentError, "Entity #{inspect(entity)} must have an :id field"
  end

  defp get_entity_type(entity) do
    entity.__struct__
    |> to_string()
    |> String.split(".")
    |> List.last()
    |> String.downcase()
    # Keep as string to avoid atom/string JSON serialization issues
  end

  defp generate_correlation_id do
    Ecto.UUID.generate()
  end

  defp generate_causation_id do
    Ecto.UUID.generate()
  end

  defp apply_event_to_state(state, recorded_event) do
    case recorded_event.event_type do
      "Elixir.RubberDuck.EventStore.Events.EntityCreated" ->
        Map.merge(state, recorded_event.data.entity_data)
        
      "Elixir.RubberDuck.EventStore.Events.EntityUpdated" ->
        Map.merge(state, recorded_event.data.changes)
        
      "Elixir.RubberDuck.EventStore.Events.EntityDeleted" ->
        # Handle case where timestamp might be a string after JSON deserialization
        deleted_at = case recorded_event.data.timestamp do
          %DateTime{} = dt -> dt
          timestamp_string when is_binary(timestamp_string) ->
            {:ok, dt, _} = DateTime.from_iso8601(timestamp_string)
            dt
          _ -> DateTime.utc_now()
        end
        
        Map.put(state, :deleted, true)
        |> Map.put(:deleted_at, deleted_at)
        
      _ ->
        state
    end
  end

  # Helper function to strip Ecto metadata from structs
  defp strip_ecto_metadata(%{__struct__: _} = struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([:__meta__])
  end
  
  defp strip_ecto_metadata(data), do: data
end