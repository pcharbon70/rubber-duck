defmodule RubberDuck.EventStoreTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.EventStore
  alias RubberDuck.EventStore.Events.{EntityUpdated, EntityCreated, EntityDeleted}
  alias RubberDuck.Test.EntityFactory

  describe "EventStore" do
    setup do
      # Clean up test streams before each test
      stream_id = "test-entity-#{System.system_time(:nanosecond)}"
      entity = EntityFactory.build_user(%{id: "test-user-#{System.system_time(:nanosecond)}"})
      
      {:ok, stream_id: stream_id, entity: entity}
    end

    test "records entity creation event", %{entity: entity} do
      metadata = %{source: "test", actor: "test_user"}
      
      assert :ok = EventStore.record_entity_creation(entity, metadata)
      
      # Verify event was recorded
      assert {:ok, [recorded_event]} = EventStore.read_entity_stream(entity.id)
      assert recorded_event.event_type == "Elixir.RubberDuck.EventStore.Events.EntityCreated"
      assert recorded_event.data.entity_id == entity.id
      assert recorded_event.data.entity_type == "user"
      assert recorded_event.metadata["source"] == "test"
    end

    test "records entity update event", %{entity: entity} do
      changes = %{email: "new@example.com", username: "newusername"}
      impact = %{risk_level: "low", affected_entities: []}
      
      # First create the entity
      assert :ok = EventStore.record_entity_creation(entity)
      
      # Then update it
      assert :ok = EventStore.record_entity_update(entity, changes, impact)
      
      # Verify both events were recorded
      assert {:ok, [create_event, update_event]} = EventStore.read_entity_stream(entity.id)
      
      assert create_event.event_type == "Elixir.RubberDuck.EventStore.Events.EntityCreated"
      assert update_event.event_type == "Elixir.RubberDuck.EventStore.Events.EntityUpdated"
      assert update_event.data.changes == changes
      assert update_event.data.impact == impact
    end

    test "records entity deletion event", %{entity: entity} do
      reason = %{deleted_by: "admin", cause: "policy_violation"}
      
      assert :ok = EventStore.record_entity_deletion(entity, reason)
      
      # Verify event was recorded
      assert {:ok, [recorded_event]} = EventStore.read_entity_stream(entity.id)
      assert recorded_event.event_type == "Elixir.RubberDuck.EventStore.Events.EntityDeleted"
      assert recorded_event.data.entity_id == entity.id
      assert recorded_event.data.reason == reason
    end

    test "gets entity history in readable format", %{entity: entity} do
      # Record multiple events
      assert :ok = EventStore.record_entity_creation(entity)
      assert :ok = EventStore.record_entity_update(entity, %{email: "new@example.com"}, %{})
      assert :ok = EventStore.record_entity_deletion(entity, %{cause: "test"})
      
      assert {:ok, history} = EventStore.get_entity_history(entity.id)
      assert length(history) == 3
      
      [create_event, update_event, delete_event] = history
      
      assert create_event.event_type == "Elixir.RubberDuck.EventStore.Events.EntityCreated"
      assert update_event.event_type == "Elixir.RubberDuck.EventStore.Events.EntityUpdated"
      assert delete_event.event_type == "Elixir.RubberDuck.EventStore.Events.EntityDeleted"
      
      # All events should have proper metadata
      Enum.each(history, fn event ->
        assert is_binary(event.event_id)
        assert is_map(event.metadata)
        assert %DateTime{} = event.created_at
        assert is_integer(event.stream_version)
      end)
    end

    test "replays entity state from events", %{entity: entity} do
      initial_data = Map.from_struct(entity)
      
      # Record creation and updates
      assert :ok = EventStore.record_entity_creation(entity)
      assert :ok = EventStore.record_entity_update(entity, %{email: "updated@example.com"}, %{})
      assert :ok = EventStore.record_entity_update(entity, %{username: "updateduser"}, %{})
      
      # Replay the entity state
      assert {:ok, final_state} = EventStore.replay_entity(entity.id)
      
      # Final state should include all changes
      assert final_state.id == entity.id
      assert final_state.email == "updated@example.com"
      assert final_state.username == "updateduser"
      # Original fields should still be present
      assert final_state.hashed_password == initial_data.hashed_password
    end

    test "handles replay with deletion", %{entity: entity} do
      assert :ok = EventStore.record_entity_creation(entity)
      assert :ok = EventStore.record_entity_update(entity, %{email: "updated@example.com"}, %{})
      assert :ok = EventStore.record_entity_deletion(entity, %{cause: "test deletion"})
      
      assert {:ok, final_state} = EventStore.replay_entity(entity.id)
      
      # State should show deletion
      assert final_state.deleted == true
      assert %DateTime{} = final_state.deleted_at
      # Previous updates should still be applied
      assert final_state.email == "updated@example.com"
    end

    test "handles non-existent entity stream", %{} do
      non_existent_id = "does-not-exist-#{System.system_time(:nanosecond)}"
      
      # Non-existent streams return stream_not_found error
      assert {:error, :stream_not_found} = EventStore.read_entity_stream(non_existent_id)
      assert {:ok, %{}} = EventStore.replay_entity(non_existent_id)
      assert {:ok, []} = EventStore.get_entity_history(non_existent_id)
    end
  end

  describe "Event structs" do
    test "EntityCreated validates correctly" do
      valid_event = EntityCreated.new(
        entity_id: "123",
        entity_type: "user",
        entity_data: %{id: "123", email: "test@example.com"}
      )
      
      assert EntityCreated.valid?(valid_event)
      assert EntityCreated.describe(valid_event) == "Created user 123"
      assert EntityCreated.get_initial_value(valid_event, :email) == "test@example.com"
      assert EntityCreated.get_field_names(valid_event) == [:id, :email]
      
      # Invalid event
      invalid_event = %EntityCreated{entity_id: "", entity_type: "user", entity_data: %{}, timestamp: DateTime.utc_now()}
      refute EntityCreated.valid?(invalid_event)
    end

    test "EntityUpdated validates and provides utilities" do
      valid_event = EntityUpdated.new(
        entity_id: "123",
        entity_type: "user",
        changes: %{email: "new@example.com", username: "newuser"},
        impact: %{risk_level: "low"}
      )
      
      assert EntityUpdated.valid?(valid_event)
      assert EntityUpdated.describe(valid_event) == "Updated user 123: changed email, username"
      assert EntityUpdated.changed_fields(valid_event) == [:email, :username]
      assert EntityUpdated.field_changed?(valid_event, :email)
      assert EntityUpdated.field_changed?(valid_event, "username")
      refute EntityUpdated.field_changed?(valid_event, :password)
      assert EntityUpdated.get_new_value(valid_event, :email) == "new@example.com"
      
      # Invalid event
      invalid_event = %EntityUpdated{entity_id: "", entity_type: "user", changes: %{}, timestamp: DateTime.utc_now()}
      refute EntityUpdated.valid?(invalid_event)
    end

    test "EntityDeleted validates and provides utilities" do
      valid_event = EntityDeleted.new(
        entity_id: "123",
        entity_type: "user",
        reason: %{deleted_by: "admin", cause: "policy_violation"}
      )
      
      assert EntityDeleted.valid?(valid_event)
      assert EntityDeleted.describe(valid_event) == "Deleted user 123 (reason: policy_violation)"
      assert EntityDeleted.get_deletion_reason(valid_event) == "policy_violation"
      assert EntityDeleted.get_deleted_by(valid_event) == "admin"
      
      # Event without reason
      event_no_reason = EntityDeleted.new(entity_id: "456", entity_type: "project")
      assert EntityDeleted.describe(event_no_reason) == "Deleted project 456"
      assert EntityDeleted.get_deletion_reason(event_no_reason) == nil
    end
  end
end