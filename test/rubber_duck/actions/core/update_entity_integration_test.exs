defmodule RubberDuck.Actions.Core.UpdateEntityIntegrationTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Actions.Core.UpdateEntity
  alias RubberDuck.Actions.Core.Entity
  
  @moduledoc """
  Integration tests for the refactored UpdateEntity action framework.
  
  These tests verify that all specialized modules work together correctly:
  - Entity wrapper
  - Validator
  - ImpactAnalyzer
  - Executor
  - Learner
  - Propagator
  """
  
  describe "end-to-end update pipeline" do
    test "complete update flow with all features enabled" do
      params = %{
        entity_id: "integration-test-1",
        entity_type: :project,
        changes: %{
          name: "Updated Project Name",
          description: "New description for integration test"
        },
        impact_analysis: true,
        auto_propagate: true,
        learning_enabled: true,
        agent_goals: [
          %{type: :quality, priority: :high},
          %{type: :performance, priority: :medium}
        ],
        rollback_on_failure: true,
        validation_config: %{
          constraints: %{
            name: %{min: 3, max: 100},
            description: %{max: 500}
          }
        }
      }
      
      assert {:ok, result} = UpdateEntity.run(params, %{})
      
      # Verify all pipeline stages executed
      assert result.entity.name == "Updated Project Name"
      assert result.entity.description == "New description for integration test"
      
      # Validation was performed
      assert result.changes_applied.validations != nil
      assert result.changes_applied.validations.field_validation.valid == true
      assert result.changes_applied.validations.constraint_validation.valid == true
      
      # Impact analysis was performed
      assert result.impact_assessment.impact_score != nil
      assert result.impact_assessment.impact_details != nil
      assert is_list(result.impact_assessment.recommendations)
      
      # Goal alignment was checked
      assert result.goal_alignment_score > 0
      assert result.goal_alignment_score <= 1.0
      
      # Propagation was attempted
      assert result.propagation_results.propagated == true
      assert result.propagation_results.entities_updated >= 0
      
      # Learning was captured
      assert result.learning_data.learned == true
      assert result.learning_data.learning_id != nil
    end
    
    test "update flow with minimal configuration" do
      params = %{
        entity_id: "minimal-test-1",
        entity_type: :user,
        changes: %{preferences: %{theme: "dark"}},
        impact_analysis: false,
        auto_propagate: false,
        learning_enabled: false,
        agent_goals: [],
        rollback_on_failure: false,
        validation_config: %{}
      }
      
      assert {:ok, result} = UpdateEntity.run(params, %{})
      
      # Basic update completed
      assert result.entity.preferences == %{theme: "dark"}
      
      # Optional features were skipped
      assert result.impact_assessment.skipped == true
      assert result.propagation_results.propagated == false
      assert result.learning_data.learned == false
      assert result.goal_alignment_score == 1.0
    end
  end
  
  describe "error handling and recovery" do
    test "validation failure stops pipeline" do
      params = %{
        entity_id: "validation-fail-1",
        entity_type: :project,
        changes: %{
          unknown_field: "should fail",
          another_invalid: 123
        },
        impact_analysis: true,
        auto_propagate: true,
        learning_enabled: true,
        agent_goals: [],
        rollback_on_failure: true,
        validation_config: %{}
      }
      
      assert {:error, error} = UpdateEntity.run(params, %{})
      assert error.step == :validation
      assert error.entity_id == "validation-fail-1"
    end
    
    test "handles constraint violations correctly" do
      params = %{
        entity_id: "constraint-test-1",
        entity_type: :project,
        changes: %{
          name: "A"  # Too short
        },
        impact_analysis: false,
        auto_propagate: false,
        learning_enabled: false,
        agent_goals: [],
        rollback_on_failure: false,
        validation_config: %{
          constraints: %{
            name: %{min: 3, max: 100}
          }
        }
      }
      
      assert {:error, error} = UpdateEntity.run(params, %{})
      assert error.step == :validation
    end
    
    test "goal misalignment prevents update when configured" do
      params = %{
        entity_id: "goal-test-1",
        entity_type: :code_file,
        changes: %{
          content: "// This is a risky change",
          path: "/critical/system/file.ex"
        },
        impact_analysis: true,
        auto_propagate: false,
        learning_enabled: false,
        agent_goals: [
          %{type: :stability, priority: :critical}
        ],
        rollback_on_failure: true,
        validation_config: %{}
      }
      
      # This may or may not fail based on impact assessment
      result = UpdateEntity.run(params, %{})
      
      case result do
        {:ok, success} ->
          # If it succeeds, goal alignment should be reasonable
          assert success.goal_alignment_score >= 0.6
          
        {:error, error} ->
          # If it fails, it should be due to goal misalignment
          assert error.step == :goal_alignment
      end
    end
    
    test "unknown entity type is handled gracefully" do
      params = %{
        entity_id: "unknown-1",
        entity_type: :invalid_type,
        changes: %{},
        impact_analysis: false,
        auto_propagate: false,
        learning_enabled: false,
        agent_goals: [],
        rollback_on_failure: false,
        validation_config: %{}
      }
      
      assert {:error, error} = UpdateEntity.run(params, %{})
      assert error.step == :fetch_entity
      assert error.reason == {:error, :unknown_entity_type}
    end
  end
  
  describe "cross-module integration" do
    test "validator output feeds into impact analyzer correctly" do
      params = %{
        entity_id: "cross-module-1",
        entity_type: :project,
        changes: %{
          status: :archived,
          name: "Archived Project"
        },
        impact_analysis: true,
        auto_propagate: false,
        learning_enabled: false,
        agent_goals: [],
        rollback_on_failure: false,
        validation_config: %{}
      }
      
      assert {:ok, result} = UpdateEntity.run(params, %{})
      
      # Validator identified the changes
      assert :status in result.changes_applied.validations.field_validation.validated_fields
      assert :name in result.changes_applied.validations.field_validation.validated_fields
      
      # Impact analyzer assessed the severity
      assert result.impact_assessment.impact_details.direct_impact.fields_affected == 2
      assert result.impact_assessment.impact_details.direct_impact.severity in [:low, :medium, :high]
    end
    
    test "executor uses impact assessment for version management" do
      params = %{
        entity_id: "executor-test-1",
        entity_type: :user,
        changes: %{
          username: "new_username_v2"
        },
        impact_analysis: true,
        auto_propagate: false,
        learning_enabled: false,
        agent_goals: [],
        rollback_on_failure: true,
        validation_config: %{}
      }
      
      assert {:ok, result} = UpdateEntity.run(params, %{})
      
      # Check that version was incremented
      assert result.entity.version >= 1
      assert result.entity.updated_at != nil
      
      # Previous state was captured
      assert result.previous_state != nil
      assert result.previous_state.entity_id == "executor-test-1"
    end
    
    test "learner captures execution metrics" do
      params = %{
        entity_id: "learner-test-1",
        entity_type: :analysis,
        changes: %{
          status: :completed,
          results: %{score: 95}
        },
        impact_analysis: true,
        auto_propagate: false,
        learning_enabled: true,
        agent_goals: [],
        rollback_on_failure: false,
        validation_config: %{}
      }
      
      assert {:ok, result} = UpdateEntity.run(params, %{})
      
      # Learning data was captured
      assert result.learning_data.learned == true
      assert result.learning_data.learning_id != nil
      assert result.learning_data.confidence_score > 0
      
      # Pattern analysis was performed
      assert result.learning_data.learning_data.pattern_analysis != nil
      assert result.learning_data.learning_data.outcome_tracking != nil
    end
    
    test "propagator respects impact assessment dependencies" do
      params = %{
        entity_id: "propagator-test-1",
        entity_type: :project,
        changes: %{
          status: :deleted
        },
        impact_analysis: true,
        auto_propagate: true,
        learning_enabled: false,
        agent_goals: [],
        rollback_on_failure: false,
        validation_config: %{}
      }
      
      assert {:ok, result} = UpdateEntity.run(params, %{})
      
      # Propagation was performed based on impact assessment
      assert result.propagation_results.propagated == true
      
      # Propagation strategy was determined
      assert result.propagation_results.strategy in [:immediate, :queued, :lazy]
      
      # Affected entities were identified
      affected_types = result.impact_assessment.impact_details.affected_entities
      assert is_list(affected_types)
      assert length(affected_types) > 0
    end
  end
  
  describe "entity wrapper integration" do
    test "entity wrapper correctly transforms Ash resources" do
      # Fetch an entity through the wrapper
      assert {:ok, entity} = Entity.fetch(:user, "wrapper-test-1")
      
      # Verify entity structure
      assert entity.id == "wrapper-test-1"
      assert entity.type == :user
      assert entity.source == :ash  # Would be :ash when using real Ash resources
      assert entity.metadata != nil
      assert entity.version >= 1
    end
    
    test "entity wrapper handles external data sources" do
      # Create entity from external data
      external_data = %{
        name: "External Resource",
        source: "third_party_api",
        data: %{key: "value"}
      }
      
      entity = Entity.from_external(external_data, :code_file, "external-1")
      
      assert entity.id == "external-1"
      assert entity.type == :code_file
      assert entity.source == :external
      assert entity.resource == external_data
    end
    
    test "entity changes are applied correctly" do
      assert {:ok, entity} = Entity.fetch(:project, "apply-test-1")
      
      changes = %{
        name: "Modified Name",
        description: "Modified Description"
      }
      
      assert {:ok, updated} = Entity.apply_changes(entity, changes)
      
      assert Entity.to_map(updated).name == "Modified Name"
      assert Entity.to_map(updated).description == "Modified Description"
      assert updated.version == entity.version + 1
    end
    
    test "entity snapshots work for rollback" do
      assert {:ok, entity} = Entity.fetch(:user, "snapshot-test-1")
      assert {:ok, entity_with_snapshot} = Entity.create_snapshot(entity)
      
      # Make changes
      changes = %{username: "modified_username"}
      assert {:ok, modified} = Entity.apply_changes(entity_with_snapshot, changes)
      
      # Restore from snapshot
      assert {:ok, restored} = Entity.restore_from_snapshot(modified)
      
      # Should be back to original state
      assert Entity.to_map(restored).username == "testuser"
    end
  end
  
  describe "performance characteristics" do
    test "handles rapid sequential updates" do
      entity_id = "perf-test-1"
      
      results = for i <- 1..10 do
        params = %{
          entity_id: entity_id,
          entity_type: :user,
          changes: %{preferences: %{counter: i}},
          impact_analysis: false,
          auto_propagate: false,
          learning_enabled: false,
          agent_goals: [],
          rollback_on_failure: false,
          validation_config: %{}
        }
        
        UpdateEntity.run(params, %{})
      end
      
      # All updates should succeed
      assert Enum.all?(results, fn {status, _} -> status == :ok end)
      
      # Last update should have counter = 10
      {:ok, last_result} = List.last(results)
      assert last_result.entity.preferences.counter == 10
    end
    
    test "handles large change sets" do
      # Create a large change set
      large_changes = for i <- 1..50, into: %{} do
        {"field_#{i}", "value_#{i}"}
      end
      
      params = %{
        entity_id: "large-change-1",
        entity_type: :project,
        changes: large_changes,
        impact_analysis: true,
        auto_propagate: false,
        learning_enabled: false,
        agent_goals: [],
        rollback_on_failure: false,
        validation_config: %{}
      }
      
      assert {:ok, result} = UpdateEntity.run(params, %{})
      
      # Verify changes were applied
      result_map = result.entity
      for i <- 1..50 do
        field = "field_#{i}"
        assert Map.get(result_map, String.to_atom(field)) == "value_#{i}"
      end
    end
    
    test "impact analysis scales with complexity" do
      params = %{
        entity_id: "complex-impact-1",
        entity_type: :code_file,
        changes: %{
          path: "/new/path/file.ex",
          content: String.duplicate("code", 1000),
          language: :elixir
        },
        impact_analysis: true,
        auto_propagate: true,
        learning_enabled: true,
        agent_goals: [
          %{type: :quality},
          %{type: :performance},
          %{type: :stability}
        ],
        rollback_on_failure: true,
        validation_config: %{
          constraints: %{
            path: %{pattern: ~r/\.ex$/}
          }
        }
      }
      
      {time_microseconds, result} = :timer.tc(fn ->
        UpdateEntity.run(params, %{})
      end)
      
      assert elem(result, 0) == :ok
      
      # Should complete in reasonable time (< 1 second)
      assert time_microseconds < 1_000_000
      
      # All analysis dimensions should be present
      {:ok, success} = result
      impact = success.impact_assessment.impact_details
      
      assert impact.direct_impact != nil
      assert impact.dependency_impact != nil
      assert impact.performance_impact != nil
      assert impact.system_impact != nil
      assert impact.risk_assessment != nil
    end
  end
  
  describe "concurrent update handling" do
    test "parallel updates to different entities" do
      tasks = for i <- 1..5 do
        Task.async(fn ->
          params = %{
            entity_id: "concurrent-#{i}",
            entity_type: :user,
            changes: %{username: "user_#{i}"},
            impact_analysis: false,
            auto_propagate: false,
            learning_enabled: false,
            agent_goals: [],
            rollback_on_failure: false,
            validation_config: %{}
          }
          
          UpdateEntity.run(params, %{})
        end)
      end
      
      results = Task.await_many(tasks)
      
      # All should succeed
      assert Enum.all?(results, fn {status, _} -> status == :ok end)
      
      # Each should have unique username
      usernames = Enum.map(results, fn {:ok, r} -> r.entity.username end)
      assert length(Enum.uniq(usernames)) == 5
    end
  end
end