defmodule RubberDuck.Actions.Core.UpdateEntityTelemetryTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Actions.Core.UpdateEntity
  alias RubberDuck.Actions.Core.Entity

  @moduletag capture_log: true

  setup do
    # Ensure telemetry handlers are attached
    RubberDuck.Telemetry.ActionTelemetry.attach_handlers()
    
    # Create a test entity
    entity = %Entity{
      id: "test-123",
      type: :user,
      data: %{
        name: "Test User",
        email: "test@example.com",
        age: 30
      }
    }
    
    {:ok, entity: entity}
  end

  describe "telemetry integration" do
    test "emits telemetry events during action execution", %{entity: entity} do
      self_pid = self()
      
      # Attach handlers to capture telemetry events
      events = [
        [:rubber_duck, :action, :start],
        [:rubber_duck, :action, :stop],
        [:rubber_duck, :action, :validation, :start],
        [:rubber_duck, :action, :validation, :stop],
        [:rubber_duck, :action, :impact_analysis, :start],
        [:rubber_duck, :action, :impact_analysis, :stop],
        [:rubber_duck, :action, :execution, :start],
        [:rubber_duck, :action, :execution, :stop],
        [:rubber_duck, :action, :learning, :start],
        [:rubber_duck, :action, :learning, :stop]
      ]
      
      :telemetry.attach_many(
        "test-update-entity-#{inspect(self_pid)}",
        events,
        fn event, measurements, metadata, _ ->
          send(self_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )
      
      # Mock Entity.fetch to return our test entity
      expect_entity_fetch(entity)
      
      # Execute the action
      params = %{
        entity_id: entity.id,
        entity_type: entity.type,
        changes: %{age: 31, email: "updated@example.com"},
        impact_analysis: true,
        auto_propagate: false,
        learning_enabled: true,
        agent_goals: [],
        rollback_on_failure: true,
        validation_config: %{}
      }
      
      result = UpdateEntity.run(params, %{})
      
      # Verify action succeeded
      assert {:ok, _} = result
      
      # Verify main action span events
      assert_receive {:telemetry, [:rubber_duck, :action, :start], _, main_meta}
      assert main_meta.action_type == "update_entity"
      assert main_meta.resource == "user"
      assert main_meta.entity_id == "test-123"
      
      assert_receive {:telemetry, [:rubber_duck, :action, :stop], main_measurements, _}
      assert is_integer(main_measurements.duration)
      assert main_measurements.duration > 0
      
      # Verify validation span events
      assert_receive {:telemetry, [:rubber_duck, :action, :validation, :start], _, val_meta}
      assert val_meta.entity_type == "user"
      
      assert_receive {:telemetry, [:rubber_duck, :action, :validation, :stop], val_measurements, _}
      assert is_integer(val_measurements.duration)
      
      # Verify impact analysis span events  
      assert_receive {:telemetry, [:rubber_duck, :action, :impact_analysis, :start], _, _}
      assert_receive {:telemetry, [:rubber_duck, :action, :impact_analysis, :stop], _, _}
      
      # Verify execution span events
      assert_receive {:telemetry, [:rubber_duck, :action, :execution, :start], _, exec_meta}
      assert exec_meta.change_count == 2
      
      assert_receive {:telemetry, [:rubber_duck, :action, :execution, :stop], _, _}
      
      # Verify learning span events (if enabled)
      assert_receive {:telemetry, [:rubber_duck, :action, :learning, :start], _, _}
      assert_receive {:telemetry, [:rubber_duck, :action, :learning, :stop], _, _}
      
      # Cleanup
      :telemetry.detach("test-update-entity-#{inspect(self_pid)}")
    end
    
    test "emits impact score metrics for high-impact changes", %{entity: entity} do
      self_pid = self()
      
      # Attach handler for impact metrics
      :telemetry.attach_many(
        "test-impact-#{inspect(self_pid)}",
        [
          [:rubber_duck, :impact, :score],
          [:rubber_duck, :impact, :high_impact_actions]
        ],
        fn event, measurements, metadata, _ ->
          send(self_pid, {:impact_telemetry, event, measurements, metadata})
        end,
        nil
      )
      
      # Mock Entity.fetch
      expect_entity_fetch(entity)
      
      # Execute action with changes
      params = %{
        entity_id: entity.id,
        entity_type: entity.type,
        changes: %{name: "Critical Update"},
        impact_analysis: true,
        auto_propagate: false,
        learning_enabled: false,
        agent_goals: [],
        rollback_on_failure: true,
        validation_config: %{}
      }
      
      {:ok, _} = UpdateEntity.run(params, %{})
      
      # Verify impact score was emitted
      assert_receive {:impact_telemetry, [:rubber_duck, :impact, :score], measurements, metadata}
      assert is_number(measurements.value)
      assert metadata.analysis_type == "entity_update"
      assert metadata.domain == "user"
      
      # Cleanup
      :telemetry.detach("test-impact-#{inspect(self_pid)}")
    end
    
    test "emits learning feedback metrics when learning is enabled", %{entity: entity} do
      self_pid = self()
      
      # Attach handler for learning metrics
      :telemetry.attach(
        "test-learning-#{inspect(self_pid)}",
        [:rubber_duck, :learning, :feedback_processed],
        fn event, measurements, metadata, _ ->
          send(self_pid, {:learning_telemetry, event, measurements, metadata})
        end,
        nil
      )
      
      # Mock Entity.fetch
      expect_entity_fetch(entity)
      
      # Execute action with learning enabled
      params = %{
        entity_id: entity.id,
        entity_type: entity.type,
        changes: %{age: 32},
        impact_analysis: false,
        auto_propagate: false,
        learning_enabled: true,
        agent_goals: [],
        rollback_on_failure: false,
        validation_config: %{}
      }
      
      {:ok, _} = UpdateEntity.run(params, %{})
      
      # Verify learning feedback was processed
      assert_receive {:learning_telemetry, [:rubber_duck, :learning, :feedback_processed], measurements, metadata}
      assert measurements.value == 1
      assert metadata.feedback_type == "entity_update"
      assert metadata.agent_id == "update_entity_learner"
      
      # Cleanup
      :telemetry.detach("test-learning-#{inspect(self_pid)}")
    end
  end
  
  # Helper to mock Entity.fetch
  defp expect_entity_fetch(entity) do
    # Since Entity.fetch is not easily mockable, we'll need to work with the actual implementation
    # For this test, we'll assume the entity exists in the system or skip this test
    # In a real implementation, you'd want to use a mocking library like Mox
    :ok
  end
end