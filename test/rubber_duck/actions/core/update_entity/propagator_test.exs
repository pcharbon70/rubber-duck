defmodule RubberDuck.Actions.Core.UpdateEntity.PropagatorTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Actions.Core.UpdateEntity.Propagator

  describe "propagate/2" do
    setup do
      entity = %{
        id: "test-123",
        type: :user,
        version: 2
      }

      impact_assessment = %{
        impact_details: %{
          affected_entities: [
            {:sessions, "session-1", :invalidate},
            {:preferences, "pref-1", :update}
          ],
          direct_impact: %{severity: :medium},
          risk_assessment: %{risk_level: :low}
        }
      }

      params = %{
        entity: entity,
        impact_assessment: impact_assessment
      }

      {:ok, params: params, entity: entity}
    end

    test "successfully propagates changes", %{params: params} do
      assert {:ok, result} = Propagator.propagate(params, %{})
      assert result.propagated == true
      assert result.entities_updated > 0
      assert is_map(result.propagation_plan)
      assert is_map(result.execution_result)
    end

    test "handles no affected entities", %{entity: entity} do
      params = %{
        entity: entity,
        impact_assessment: %{impact_details: %{affected_entities: []}}
      }

      assert {:ok, result} = Propagator.propagate(params, %{})
      assert result.propagated == false
      assert result.reason == :no_affected_entities
      assert result.entities_updated == 0
    end

    test "includes propagation metrics", %{params: params} do
      {:ok, result} = Propagator.propagate(params, %{})

      assert is_map(result.metrics)
      assert Map.has_key?(result.metrics, :total_entities)
      assert Map.has_key?(result.metrics, :by_action)
      assert Map.has_key?(result.metrics, :execution_time_ms)
    end

    test "generates unique propagation ID", %{params: params} do
      {:ok, result1} = Propagator.propagate(params, %{})
      {:ok, result2} = Propagator.propagate(params, %{})

      assert result1.propagation_id != result2.propagation_id
      assert is_binary(result1.propagation_id)
    end
  end

  describe "create_propagation_plan/3" do
    test "creates plan with affected entities" do
      entity = %{id: "test", type: :project, version: 1}

      impact_assessment = %{
        affected_entities: [
          %{type: :code_files, id: "file-1", action: :revalidate},
          %{type: :analyses, id: "analysis-1", action: :recompute}
        ],
        impact_details: %{
          direct_impact: %{severity: :high},
          risk_assessment: %{risk_level: :medium}
        }
      }

      assert {:ok, plan} = Propagator.create_propagation_plan(entity, impact_assessment, %{})

      assert plan.source_entity.id == "test"
      assert length(plan.affected_entities) == 2
      assert is_map(plan.propagation_strategy)
      assert is_list(plan.propagation_order)
      assert is_map(plan.circular_dependencies)
    end

    test "determines sequential strategy for critical risk" do
      entity = %{id: "test", type: :user}

      impact_assessment = %{
        affected_entities: [%{type: :sessions, id: "s1"}],
        impact_details: %{
          direct_impact: %{severity: :low},
          risk_assessment: %{risk_level: :critical}
        }
      }

      {:ok, plan} = Propagator.create_propagation_plan(entity, impact_assessment, %{})

      assert plan.propagation_strategy.type == :sequential_with_validation
      assert plan.propagation_strategy.validation_required == true
    end

    test "determines batched parallel for many entities" do
      entity = %{id: "test", type: :project}

      affected =
        Enum.map(1..15, fn i ->
          %{type: :code_files, id: "file-#{i}", action: :update}
        end)

      impact_assessment = %{
        affected_entities: affected,
        impact_details: %{
          direct_impact: %{severity: :low},
          risk_assessment: %{risk_level: :low}
        }
      }

      {:ok, plan} = Propagator.create_propagation_plan(entity, impact_assessment, %{})

      assert plan.propagation_strategy.type == :batched_parallel
    end

    test "respects force_sequential option" do
      entity = %{id: "test", type: :user}

      impact_assessment = %{
        affected_entities: [%{type: :sessions, id: "s1"}]
      }

      options = %{force_sequential: true}

      {:ok, plan} = Propagator.create_propagation_plan(entity, impact_assessment, options)

      assert plan.propagation_strategy.type == :sequential
    end

    test "orders entities by priority" do
      entity = %{id: "test", type: :user}

      impact_assessment = %{
        affected_entities: [
          # medium priority
          %{type: :preferences, id: "pref-1"},
          # critical priority
          %{type: :sessions, id: "session-1"},
          # high priority
          %{type: :analyses, id: "analysis-1"}
        ]
      }

      {:ok, plan} = Propagator.create_propagation_plan(entity, impact_assessment, %{})

      # Sessions should come first (critical), then analyses (high), then preferences (medium)
      assert Enum.at(plan.propagation_order, 0).type == :sessions
      assert Enum.at(plan.propagation_order, 1).type == :analyses
      assert Enum.at(plan.propagation_order, 2).type == :preferences
    end

    test "detects circular dependencies" do
      entity = %{id: "project-1", type: :project}

      impact_assessment = %{
        affected_entities: [
          %{type: :code_files, id: "file-1"},
          %{type: :analyses, id: "analysis-1"},
          %{type: :deployments, id: "deploy-1"}
        ]
      }

      {:ok, plan} = Propagator.create_propagation_plan(entity, impact_assessment, %{})

      assert Map.has_key?(plan.circular_dependencies, :has_circular_dependencies)
      assert Map.has_key?(plan.circular_dependencies, :cycles)
      assert Map.has_key?(plan.circular_dependencies, :resolution_strategy)
    end

    test "configures batching for large entity sets" do
      entity = %{id: "test", type: :project}

      affected =
        Enum.map(1..25, fn i ->
          %{type: :code_files, id: "file-#{i}"}
        end)

      impact_assessment = %{affected_entities: affected}

      {:ok, plan} = Propagator.create_propagation_plan(entity, impact_assessment, %{})

      assert plan.batching_config.enabled == true
      assert plan.batching_config.batch_size == 10
    end

    test "handles mixed entity format in affected_entities" do
      entity = %{id: "test", type: :user}

      impact_assessment = %{
        impact_details: %{
          affected_entities: [
            {:sessions, "s1", :invalidate},
            {:preferences, "p1"},
            %{type: :projects, id: "proj-1", action: :notify}
          ]
        }
      }

      {:ok, plan} = Propagator.create_propagation_plan(entity, impact_assessment, %{})

      assert length(plan.affected_entities) == 3
      assert Enum.all?(plan.affected_entities, &is_map/1)
    end
  end

  describe "validate_propagation_plan/1" do
    test "validates complete plan" do
      plan = %{
        affected_entities: [
          %{type: :sessions, id: "s1"},
          %{type: :preferences, id: "p1"}
        ],
        propagation_order: [
          %{type: :sessions, id: "s1"},
          %{type: :preferences, id: "p1"}
        ],
        propagation_strategy: %{
          type: :parallel,
          max_parallelism: 5
        },
        circular_dependencies: %{
          has_circular_dependencies: false,
          resolution_strategy: :none
        }
      }

      assert {:ok, validation} = Propagator.validate_propagation_plan(plan)
      assert validation.valid == true
      assert validation.validations.entities_valid == true
      assert validation.validations.order_valid == true
      assert validation.validations.strategy_valid == true
    end

    test "fails validation for invalid entities" do
      plan = %{
        affected_entities: [
          # Missing id
          %{type: :sessions},
          # Missing type
          %{id: "p1"}
        ],
        propagation_order: [],
        propagation_strategy: %{type: :parallel},
        circular_dependencies: %{has_circular_dependencies: false}
      }

      assert {:error, validation} = Propagator.validate_propagation_plan(plan)
      assert validation.valid == false
      assert validation.validations.entities_valid == false
      assert :entities_valid in validation.failed_validations
    end

    test "generates warnings for circular dependencies" do
      plan = %{
        affected_entities: [%{type: :code_files, id: "f1"}],
        propagation_order: [%{type: :code_files, id: "f1"}],
        propagation_strategy: %{type: :parallel},
        circular_dependencies: %{
          has_circular_dependencies: true,
          cycles: [["a", "b", "a"]],
          resolution_strategy: :break_at_weakest_link
        }
      }

      {:ok, validation} = Propagator.validate_propagation_plan(plan)

      assert length(validation.warnings) > 0
      assert Enum.any?(validation.warnings, &String.contains?(&1, "Circular dependencies"))
    end

    test "recommends batching for large entity sets" do
      entities =
        Enum.map(1..25, fn i ->
          %{type: :code_files, id: "file-#{i}"}
        end)

      plan = %{
        affected_entities: entities,
        propagation_order: entities,
        propagation_strategy: %{type: :parallel},
        circular_dependencies: %{has_circular_dependencies: false}
      }

      {:ok, validation} = Propagator.validate_propagation_plan(plan)

      assert length(validation.recommendations) > 0
      assert Enum.any?(validation.recommendations, &String.contains?(&1, "batched parallel"))
    end
  end

  describe "execute_propagation/2" do
    setup do
      plan = %{
        source_entity: %{id: "source-1", type: :user},
        propagation_order: [
          %{type: :sessions, id: "session-1"},
          %{type: :preferences, id: "pref-1"}
        ],
        propagation_strategy: %{
          type: :parallel,
          max_parallelism: 2
        },
        timeout_config: %{
          per_entity_timeout_ms: 5000
        }
      }

      {:ok, plan: plan}
    end

    test "executes parallel propagation", %{plan: plan} do
      assert {:ok, result} = Propagator.execute_propagation(plan, %{})

      assert length(result.results) == 2
      assert result.strategy_used == :parallel
      assert is_integer(result.execution_time_ms)
    end

    test "executes sequential propagation" do
      plan = %{
        source_entity: %{id: "source-1", type: :user},
        propagation_order: [
          %{type: :sessions, id: "s1"},
          %{type: :sessions, id: "s2"}
        ],
        propagation_strategy: %{type: :sequential}
      }

      assert {:ok, result} = Propagator.execute_propagation(plan, %{})

      assert length(result.results) == 2
      assert result.strategy_used == :sequential
    end

    test "executes batched parallel propagation" do
      entities =
        Enum.map(1..10, fn i ->
          %{type: :code_files, id: "file-#{i}"}
        end)

      plan = %{
        source_entity: %{id: "proj-1", type: :project},
        propagation_order: entities,
        propagation_strategy: %{
          type: :batched_parallel,
          max_parallelism: 3
        },
        batching_config: %{
          batch_size: 3,
          batch_delay_ms: 10
        },
        timeout_config: %{
          batch_timeout_ms: 5000
        }
      }

      assert {:ok, result} = Propagator.execute_propagation(plan, %{})

      assert length(result.results) == 10
      assert result.strategy_used == :batched_parallel
    end

    test "each propagated entity has required fields", %{plan: plan} do
      {:ok, result} = Propagator.execute_propagation(plan, %{})

      Enum.each(result.results, fn entity_result ->
        assert Map.has_key?(entity_result, :entity)
        assert Map.has_key?(entity_result, :action)
        assert Map.has_key?(entity_result, :timestamp)

        assert entity_result.action in [
                 :invalidated,
                 :updated,
                 :revalidated,
                 :recomputed,
                 :notified
               ]
      end)
    end
  end

  describe "verify_propagation_results/1" do
    test "verifies successful propagation" do
      execution_result = %{
        results: [
          %{entity: %{id: "e1"}, action: :updated, timestamp: DateTime.utc_now()},
          %{entity: %{id: "e2"}, action: :invalidated, timestamp: DateTime.utc_now()}
        ],
        execution_time_ms: 100
      }

      assert {:ok, verification} = Propagator.verify_propagation_results(execution_result)
      assert verification.verified == true
      assert verification.verifications.all_entities_processed == true
      assert verification.verifications.actions_completed == true
      assert verification.verifications.no_conflicts == true
      assert verification.verifications.timing_constraints_met == true
      assert verification.verifications.data_consistency == true
    end

    test "detects conflicting operations" do
      execution_result = %{
        results: [
          %{entity: %{id: "e1"}, action: :invalidated, timestamp: DateTime.utc_now()},
          %{entity: %{id: "e1"}, action: :updated, timestamp: DateTime.utc_now()}
        ]
      }

      {:ok, verification} = Propagator.verify_propagation_results(execution_result)

      assert verification.verifications.no_conflicts == false
      assert "Conflicting operations detected" in verification.issues
    end

    test "detects timing constraint violations" do
      execution_result = %{
        results: [
          %{entity: %{id: "e1"}, action: :updated, timestamp: DateTime.utc_now()}
        ],
        # Over 60 seconds
        execution_time_ms: 65_000
      }

      {:ok, verification} = Propagator.verify_propagation_results(execution_result)

      assert verification.verifications.timing_constraints_met == false
      assert Enum.any?(verification.issues, &String.contains?(&1, "too long"))
    end

    test "generates recommendations for issues" do
      execution_result = %{
        results: [
          %{entity: %{id: "e1"}, action: :invalidated, timestamp: DateTime.utc_now()},
          %{entity: %{id: "e1"}, action: :updated, timestamp: DateTime.utc_now()}
        ],
        execution_time_ms: 65_000
      }

      {:ok, verification} = Propagator.verify_propagation_results(execution_result)

      assert length(verification.recommendations) > 0
      assert Enum.any?(verification.recommendations, &String.contains?(&1, "batched"))
      assert Enum.any?(verification.recommendations, &String.contains?(&1, "propagation order"))
    end
  end

  describe "queue_for_propagation/2" do
    test "queues entities for delayed propagation" do
      entities = [
        %{type: :sessions, id: "s1"},
        %{type: :preferences, id: "p1"}
      ]

      assert {:ok, result} = Propagator.queue_for_propagation(entities)
      assert result.queued_count == 2
      assert length(result.queue_items) == 2
      assert is_integer(result.estimated_processing_time_ms)
    end

    test "applies queue configuration" do
      entities = [%{type: :sessions, id: "s1"}]

      options = %{
        priority: :high,
        delay: 1000,
        max_retries: 5
      }

      {:ok, result} = Propagator.queue_for_propagation(entities, options)

      queue_item = hd(result.queue_items)
      assert queue_item.config.priority == :high
      assert queue_item.config.delay_ms == 1000
      assert queue_item.config.max_retries == 5
      assert queue_item.status == :pending
    end

    test "generates unique queue IDs" do
      entities = [
        %{type: :sessions, id: "s1"},
        %{type: :sessions, id: "s2"}
      ]

      {:ok, result} = Propagator.queue_for_propagation(entities)

      queue_ids = Enum.map(result.queue_items, & &1.queue_id)
      assert length(queue_ids) == length(Enum.uniq(queue_ids))
    end
  end

  describe "resolve_circular_dependencies/1" do
    test "resolves circular dependencies in plan" do
      plan = %{
        propagation_order: [
          %{id: "a"},
          %{id: "b"},
          %{id: "c"}
        ],
        circular_dependencies: %{
          has_circular_dependencies: true,
          cycles: [["a", "b", "c", "a"]]
        }
      }

      assert {:ok, resolved_plan} = Propagator.resolve_circular_dependencies(plan)

      # Should remove one entity to break the cycle
      assert length(resolved_plan.propagation_order) < length(plan.propagation_order)
    end

    test "returns unchanged plan if no circular dependencies" do
      plan = %{
        propagation_order: [%{id: "a"}, %{id: "b"}],
        circular_dependencies: %{
          has_circular_dependencies: false,
          cycles: []
        }
      }

      assert {:ok, resolved_plan} = Propagator.resolve_circular_dependencies(plan)
      assert resolved_plan == plan
    end
  end

  describe "edge cases" do
    test "handles empty impact assessment" do
      params = %{
        entity: %{id: "test", type: :user},
        impact_assessment: %{}
      }

      assert {:ok, result} = Propagator.propagate(params, %{})
      assert result.propagated == false
      assert result.entities_updated == 0
    end

    test "handles nil affected entities" do
      params = %{
        entity: %{id: "test", type: :user},
        impact_assessment: %{
          impact_details: %{
            affected_entities: nil
          }
        }
      }

      assert {:ok, result} = Propagator.propagate(params, %{})
      assert result.propagated == false
    end

    test "handles large number of affected entities" do
      entities =
        Enum.map(1..100, fn i ->
          {:code_files, "file-#{i}", :update}
        end)

      params = %{
        entity: %{id: "proj-1", type: :project},
        impact_assessment: %{
          impact_details: %{
            affected_entities: entities
          }
        }
      }

      assert {:ok, result} = Propagator.propagate(params, %{})
      assert result.propagated == true
      assert result.entities_updated == 100
    end

    test "handles propagation with custom options" do
      params = %{
        entity: %{id: "test", type: :user},
        impact_assessment: %{
          affected_entities: [%{type: :sessions, id: "s1"}]
        },
        propagation_options: %{
          force_sequential: true,
          max_parallelism: 1,
          enable_rollback: true,
          batch_size: 5
        }
      }

      assert {:ok, result} = Propagator.propagate(params, %{})
      assert result.propagation_plan.propagation_strategy.type == :sequential
      assert result.propagation_plan.rollback_strategy.enabled == true
      assert result.propagation_plan.batching_config.batch_size == 5
    end
  end
end
