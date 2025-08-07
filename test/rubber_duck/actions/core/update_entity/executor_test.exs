defmodule RubberDuck.Actions.Core.UpdateEntity.ExecutorTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Actions.Core.UpdateEntity.Executor

  describe "execute/2" do
    setup do
      entity = %{
        id: "test-123",
        type: :user,
        email: "user@example.com",
        username: "testuser",
        version: 1,
        created_at: ~U[2024-01-01 00:00:00Z]
      }

      validated_changes = %{
        changes: %{username: "newusername", email: "new@example.com"},
        change_count: 2,
        change_severity: :medium,
        validations: %{
          constraint_validation: %{
            constraints_checked: 0,
            violations: []
          }
        }
      }

      impact_assessment = %{
        impact_score: 0.5
      }

      {:ok, entity: entity, changes: validated_changes, impact: impact_assessment}
    end

    test "successfully executes update", %{entity: entity, changes: changes, impact: impact} do
      params = %{
        entity: entity,
        validated_changes: changes,
        impact_assessment: impact
      }

      assert {:ok, result} = Executor.execute(params, %{})
      assert result.entity.username == "newusername"
      assert result.entity.email == "new@example.com"
      assert result.entity.version == 2
      assert result.previous_state.data == entity
      assert result.verification.verified == true
    end

    test "creates proper snapshot", %{entity: entity, changes: changes} do
      params = %{entity: entity, validated_changes: changes}

      {:ok, result} = Executor.execute(params, %{})
      snapshot = result.previous_state

      assert snapshot.entity_id == "test-123"
      assert snapshot.entity_type == :user
      assert snapshot.data == entity
      assert snapshot.checksum != nil
      assert snapshot.version == 1
    end

    test "includes rollback info", %{entity: entity, changes: changes} do
      params = %{entity: entity, validated_changes: changes}

      {:ok, result} = Executor.execute(params, %{})

      assert result.rollback_info.can_rollback == true
      assert result.rollback_info.snapshot_version == 1
      assert result.rollback_info.current_version == 2
    end

    test "handles execution with metadata", %{entity: entity, changes: changes} do
      params = %{entity: entity, validated_changes: changes}
      context = %{executor: :test_user}

      {:ok, result} = Executor.execute(params, context)

      assert result.execution_metadata.executor == :test_user
      assert result.execution_metadata.execution_mode == :single
    end
  end

  describe "create_snapshot/1" do
    test "creates snapshot with all required fields" do
      entity = %{
        id: "entity-123",
        type: :project,
        name: "Test Project",
        version: 5
      }

      assert {:ok, snapshot} = Executor.create_snapshot(entity)
      assert snapshot.entity_id == "entity-123"
      assert snapshot.entity_type == :project
      assert snapshot.version == 5
      assert is_binary(snapshot.checksum)
      assert %DateTime{} = snapshot.snapshot_time
    end

    test "handles entity without id" do
      entity = %{type: :user, email: "test@example.com"}

      assert {:ok, snapshot} = Executor.create_snapshot(entity)
      assert is_binary(snapshot.entity_id)
      assert String.length(snapshot.entity_id) == 32
    end

    test "detects entity type from fields" do
      entities = [
        {%{email: "test@example.com"}, :user},
        {%{project_id: "proj-123"}, :code_file},
        {%{owner_id: "user-123"}, :project},
        {%{random_field: "value"}, :unknown}
      ]

      for {entity, expected_type} <- entities do
        {:ok, snapshot} = Executor.create_snapshot(entity)
        assert snapshot.entity_type == expected_type
      end
    end

    test "performs deep copy of nested structures" do
      entity = %{
        id: "test",
        nested: %{
          list: [1, 2, %{deep: "value"}],
          map: %{key: "value"}
        }
      }

      {:ok, snapshot} = Executor.create_snapshot(entity)

      # Modify original
      entity.nested.list |> List.first()

      # Snapshot should be unaffected
      assert snapshot.data.nested.list == [1, 2, %{deep: "value"}]
    end
  end

  describe "prepare_versioned_entity/2" do
    test "increments version" do
      entity = %{id: "test", version: 3}

      {:ok, versioned} = Executor.prepare_versioned_entity(entity, %{})

      assert versioned.version == 4
      assert versioned.previous_version == 3
      assert %DateTime{} = versioned.version_timestamp
    end

    test "handles entity without version" do
      entity = %{id: "test"}

      {:ok, versioned} = Executor.prepare_versioned_entity(entity, %{})

      assert versioned.version == 2
      assert versioned.previous_version == 1
    end
  end

  describe "apply_changes/3" do
    test "applies field changes" do
      entity = %{id: "test", name: "old", value: 10}
      changes = %{changes: %{name: "new", value: 20}}

      {:ok, updated} = Executor.apply_changes(entity, changes, %{})

      assert updated.name == "new"
      assert updated.value == 20
      assert updated.id == "test"
    end

    test "applies metadata updates" do
      entity = %{id: "test"}
      changes = %{change_count: 3, change_severity: :high}
      impact = %{impact_score: 0.8}

      {:ok, updated} = Executor.apply_changes(entity, changes, impact)

      assert updated.metadata.change_count == 3
      assert updated.metadata.change_severity == :high
      assert updated.metadata.impact_score == 0.8
      assert %DateTime{} = updated.metadata.last_update
    end

    test "applies computed fields for names" do
      entity = %{first_name: "John", last_name: "Doe"}
      changes = %{changes: %{first_name: "Jane"}}

      {:ok, updated} = Executor.apply_changes(entity, changes, %{})

      assert updated.full_name == "Jane Doe"
    end

    test "applies computed fields for calculations" do
      entity = %{price: 10.0, quantity: 5}
      changes = %{changes: %{quantity: 8}}

      {:ok, updated} = Executor.apply_changes(entity, changes, %{})

      assert updated.total == 80.0
    end

    test "updates relationships" do
      entity = %{id: "test"}
      changes = %{changes: %{parent_id: "parent-123"}}

      {:ok, updated} = Executor.apply_changes(entity, changes, %{})

      assert updated.parent_id == "parent-123"
      assert %DateTime{} = updated.relationship_updated_at
    end

    test "applies timestamps" do
      entity = %{id: "test"}
      changes = %{changes: %{name: "new"}}

      {:ok, updated} = Executor.apply_changes(entity, changes, %{})

      assert %DateTime{} = updated.updated_at
      assert %DateTime{} = updated.created_at
    end
  end

  describe "verify_update/2" do
    test "verifies successful update" do
      entity = %{
        id: "test-123",
        type: :user,
        email: "new@example.com",
        username: "newuser",
        version: 2,
        previous_version: 1
      }

      changes = %{
        changes: %{email: "new@example.com", username: "newuser"},
        validations: %{
          constraint_validation: %{
            constraints_checked: 2,
            violations: []
          }
        }
      }

      assert {:ok, verification} = Executor.verify_update(entity, changes)
      assert verification.verified == true
      assert verification.checks.fields_updated == true
      assert verification.checks.integrity_maintained == true
      assert verification.checks.version_consistent == true
    end

    test "detects failed field update" do
      entity = %{
        id: "test-123",
        type: :user,
        email: "old@example.com",
        username: "newuser"
      }

      changes = %{
        changes: %{email: "new@example.com"}
      }

      assert {:error, verification} = Executor.verify_update(entity, changes)
      assert verification.verified == false
      assert :fields_updated in verification.failed_checks
    end

    test "detects missing required fields" do
      entity = %{
        id: "test-123",
        type: :user,
        username: "testuser"
        # Missing email
      }

      changes = %{changes: %{}}

      assert {:error, verification} = Executor.verify_update(entity, changes)
      assert verification.checks.integrity_maintained == false
    end

    test "handles float comparison tolerance" do
      entity = %{
        id: "test",
        price: 10.000001
      }

      changes = %{
        changes: %{price: 10.0}
      }

      assert {:ok, verification} = Executor.verify_update(entity, changes)
      assert verification.checks.fields_updated == true
    end
  end

  describe "finalize_update/2" do
    test "adds audit trail" do
      entity = %{id: "test", version: 2}
      verification = %{verified: true}

      {:ok, finalized} = Executor.finalize_update(entity, verification)

      assert [audit_entry | _] = finalized.audit_trail
      assert audit_entry.action == :update
      assert audit_entry.verified == true
      assert audit_entry.version == 2
    end

    test "clears temporary fields" do
      entity = %{
        id: "test",
        __temp__: "temp_value",
        __processing__: true,
        real_field: "keep"
      }

      {:ok, finalized} = Executor.finalize_update(entity, %{verified: true})

      assert finalized.real_field == "keep"
      refute Map.has_key?(finalized, :__temp__)
      refute Map.has_key?(finalized, :__processing__)
    end

    test "compacts metadata" do
      entity = %{
        id: "test",
        metadata: %{
          field1: "value",
          field2: nil,
          field3: "another",
          field4: nil
        }
      }

      {:ok, finalized} = Executor.finalize_update(entity, %{verified: true})

      assert map_size(finalized.metadata) == 2
      assert finalized.metadata.field1 == "value"
      assert finalized.metadata.field3 == "another"
    end
  end

  describe "rollback/2" do
    test "successfully rolls back to snapshot" do
      snapshot = %{
        entity_id: "test-123",
        snapshot_time: ~U[2024-01-01 00:00:00Z],
        data: %{
          id: "test-123",
          name: "original",
          version: 1
        },
        checksum: nil
      }

      # Fix checksum
      {_, snapshot_result} = Executor.create_snapshot(snapshot.data)
      snapshot = %{
        snapshot
        | checksum: snapshot_result |> Map.get(:checksum)
      }

      current = %{
        id: "test-123",
        name: "modified",
        version: 2
      }

      assert {:ok, result} = Executor.rollback(snapshot, current)
      assert result.entity.name == "original"
      assert result.entity.restored_at != nil
      assert result.rolled_back_from == 2
      assert result.rolled_back_to == 1
    end

    test "detects corrupted snapshot" do
      snapshot = %{
        data: %{id: "test"},
        checksum: "invalid_checksum"
      }

      current = %{id: "test", version: 2}

      assert {:error, :snapshot_corrupted} = Executor.rollback(snapshot, current)
    end
  end

  describe "batch_execute/2" do
    test "executes batch successfully" do
      batch_params = [
        %{
          entity: %{id: "1", type: :user, email: "user1@example.com", username: "user1"},
          validated_changes: %{changes: %{username: "updated1"}}
        },
        %{
          entity: %{id: "2", type: :user, email: "user2@example.com", username: "user2"},
          validated_changes: %{changes: %{username: "updated2"}}
        }
      ]

      assert {:ok, result} = Executor.batch_execute(batch_params, %{})
      assert result.total == 2
      assert result.successful == 2
      assert is_binary(result.batch_id)
      assert length(result.results) == 2
    end

    test "rolls back batch on any failure" do
      batch_params = [
        %{
          entity: %{id: "1", type: :user, email: "user1@example.com", username: "user1"},
          validated_changes: %{changes: %{username: "updated1"}}
        },
        %{
          # This will fail verification due to missing email
          entity: %{id: "2", type: :user, username: "user2"},
          validated_changes: %{changes: %{username: "updated2"}}
        }
      ]

      assert {:error, result} = Executor.batch_execute(batch_params, %{})
      assert result.total == 2
      assert result.failed == 1
      assert length(result.errors) == 1
    end
  end

  describe "edge cases" do
    test "handles entity with no changes" do
      entity = %{id: "test", name: "unchanged"}
      changes = %{changes: %{}}

      assert {:ok, result} = Executor.execute(%{entity: entity, validated_changes: changes}, %{})
      assert result.entity.name == "unchanged"
      assert result.entity.version == 2
    end

    test "handles nil metadata gracefully" do
      entity = %{id: "test", metadata: nil}
      changes = %{changes: %{name: "new"}}

      assert {:ok, result} = Executor.execute(%{entity: entity, validated_changes: changes}, %{})
      assert is_map(result.entity.metadata)
    end

    test "preserves unknown entity types" do
      entity = %{id: "test", custom_field: "value"}
      changes = %{changes: %{custom_field: "new_value"}}

      assert {:ok, result} = Executor.execute(%{entity: entity, validated_changes: changes}, %{})
      assert result.entity.custom_field == "new_value"
    end
  end
end
