defmodule RubberDuck.Integration.DatabaseOperationsTest do
  @moduledoc """
  Integration tests for complete database agent ecosystem working together.

  Tests database agents coordination, skills integration, instructions processing,
  and health monitoring in realistic database operation scenarios.
  """

  use ExUnit.Case, async: false

  alias RubberDuck.Agents.{
    DataHealthSensor,
    DataPersistenceAgent,
    MigrationAgent,
    QueryOptimizerAgent
  }

  alias RubberDuck.DirectivesEngine
  alias RubberDuck.ErrorReporting.Aggregator
  alias RubberDuck.HealthCheck.{AgentMonitor, DatabaseMonitor, StatusAggregator}
  alias RubberDuck.InstructionsProcessor
  alias RubberDuck.Skills.{LearningSkill, QueryOptimizationSkill}
  alias RubberDuck.SkillsRegistry

  @moduletag :integration

  describe "database agent ecosystem coordination" do
    test "data persistence agent optimizes queries with learning integration" do
      # Create a DataPersistenceAgent
      {:ok, agent} = DataPersistenceAgent.create_persistence_agent()

      # Test query optimization workflow
      test_query = "SELECT * FROM users WHERE email = $1"

      optimization_params = %{
        query: test_query,
        execution_context: %{
          table: :users,
          estimated_rows: 1000,
          user_context: %{optimization_enabled: true}
        }
      }

      # Execute query optimization
      {:ok, optimization_result, updated_agent} =
        DataPersistenceAgent.optimize_query_performance(agent, optimization_params)

      # Verify optimization results
      assert Map.has_key?(optimization_result, :original_query)
      assert Map.has_key?(optimization_result, :optimization_applied)
      assert Map.has_key?(optimization_result, :performance_prediction)

      # Verify agent learning integration
      optimization_history = Map.get(updated_agent, :optimization_history, [])
      assert length(optimization_history) >= 1
    end

    test "migration agent coordinates with query optimizer for schema changes" do
      # Create agents
      {:ok, migration_agent} = MigrationAgent.create_migration_agent()
      {:ok, optimizer_agent} = QueryOptimizerAgent.create_optimizer_agent()

      # Test migration analysis workflow
      test_migration = TestMigration.AddUserPreferences

      # Analyze migration impact
      {:ok, impact_analysis, updated_migration_agent} =
        MigrationAgent.predict_performance_impact(migration_agent, [test_migration])

      # Verify impact analysis
      assert Map.has_key?(impact_analysis, :migrations_analyzed)
      assert Map.has_key?(impact_analysis, :total_estimated_impact)
      assert Map.has_key?(impact_analysis, :risk_assessment)

      # Test query optimization coordination for new schema
      test_query_with_new_column =
        "SELECT user_id, preferences FROM users WHERE preferences IS NOT NULL"

      {:ok, optimization_analysis, updated_optimizer_agent} =
        QueryOptimizerAgent.analyze_query_patterns(optimizer_agent, %{
          queries: [test_query_with_new_column],
          schema_context: %{recent_migration: test_migration}
        })

      # Verify coordination between agents
      assert Map.has_key?(optimization_analysis, :pattern_analysis)
      assert length(updated_optimizer_agent.query_patterns) >= 1
    end

    test "data health sensor monitors performance across all database agents" do
      # Create DataHealthSensor
      {:ok, health_sensor} = DataHealthSensor.create_health_sensor()

      # Monitor performance during database operations
      {:ok, health_monitoring_result, updated_sensor} =
        DataHealthSensor.monitor_performance(health_sensor)

      # Verify comprehensive monitoring
      assert Map.has_key?(health_monitoring_result, :current_metrics)
      assert Map.has_key?(health_monitoring_result, :anomaly_analysis)
      assert Map.has_key?(health_monitoring_result, :health_assessment)
      assert Map.has_key?(health_monitoring_result, :scaling_assessment)

      # Test capacity prediction
      {:ok, capacity_prediction, final_sensor} =
        DataHealthSensor.predict_capacity_issues(updated_sensor, 24)

      # Verify capacity prediction integration
      assert Map.has_key?(capacity_prediction, :cpu_utilization_forecast)
      assert Map.has_key?(capacity_prediction, :memory_utilization_forecast)
      assert Map.has_key?(capacity_prediction, :recommended_actions)

      # Verify sensor maintains prediction history
      predictions = Map.get(final_sensor, :capacity_predictions, %{})
      assert map_size(predictions) >= 1
    end
  end

  describe "skills integration with database operations" do
    test "query optimization skill integrates with agents through skills registry" do
      # Test skill discovery for database operations
      {:ok, database_skills} = SkillsRegistry.discover_skills(%{category: :database})

      # Should find query optimization skill
      assert Map.has_key?(database_skills, :query_optimization_skill)

      # Test skill configuration for database agent
      test_agent_id = "db_integration_agent_#{:rand.uniform(1000)}"

      skill_config = %{
        optimization_threshold: 0.7,
        learning_enabled: true,
        cache_recommendations: true
      }

      assert :ok =
               SkillsRegistry.configure_skill_for_agent(
                 test_agent_id,
                 :query_optimization_skill,
                 skill_config
               )

      # Verify configuration retrieval
      {:ok, retrieved_config} =
        SkillsRegistry.get_agent_skill_config(
          test_agent_id,
          :query_optimization_skill
        )

      assert retrieved_config == skill_config
    end

    test "learning skill tracks database operation experiences" do
      # Test learning integration across database operations

      # Create learning context for database operations
      learning_context = %{
        agent_id: "db_learning_test",
        operation_type: :query_optimization,
        system_context: %{load_level: :normal}
      }

      # Track successful optimization experience
      success_params = %{
        experience: %{
          action: :query_optimization,
          query_complexity: 0.6,
          optimization_applied: true
        },
        outcome: :success,
        context: learning_context
      }

      {:ok, success_result, learning_state} =
        LearningSkill.track_experience(success_params, %{})

      # Verify learning integration
      assert Map.has_key?(success_result, :experience_recorded)
      assert Map.has_key?(success_result, :pattern_analysis)

      # Track failure experience
      failure_params = %{
        experience: %{
          action: :query_optimization,
          query_complexity: 0.9,
          optimization_applied: false
        },
        outcome: :failure,
        context: learning_context
      }

      {:ok, failure_result, updated_learning_state} =
        LearningSkill.track_experience(failure_params, learning_state)

      # Verify learning adaptation
      experiences = Map.get(updated_learning_state, :experiences, [])
      assert length(experiences) >= 2

      # Verify pattern recognition
      assert Map.has_key?(failure_result, :pattern_analysis)
    end

    test "skills can be hot-swapped during database operations" do
      # Test hot-swapping database skills without interrupting operations

      test_agent_id = "hot_swap_db_agent_#{:rand.uniform(1000)}"

      # Configure initial skill
      initial_config = %{version: "1.0", optimization_level: :standard}

      assert :ok =
               SkillsRegistry.configure_skill_for_agent(
                 test_agent_id,
                 :query_optimization_skill,
                 initial_config
               )

      # Perform hot swap (simulating upgrade)
      enhanced_config = %{version: "2.0", optimization_level: :enhanced}

      assert :ok =
               SkillsRegistry.hot_swap_skill(
                 test_agent_id,
                 :query_optimization_skill,
                 :query_optimization_skill,
                 enhanced_config
               )

      # Verify configuration was updated
      {:ok, final_config} =
        SkillsRegistry.get_agent_skill_config(
          test_agent_id,
          :query_optimization_skill
        )

      assert final_config == enhanced_config
    end
  end

  describe "instructions and directives coordination" do
    test "instructions processor orchestrates complex database workflows" do
      # Test complex multi-step database workflow

      complex_workflow = %{
        name: "database_maintenance_workflow",
        instructions: [
          %{
            id: "health_check",
            type: :skill_invocation,
            action: "health.monitor_performance",
            parameters: %{monitoring_scope: :comprehensive},
            dependencies: []
          },
          %{
            id: "optimize_queries",
            type: :skill_invocation,
            action: "query.optimize_patterns",
            parameters: %{optimization_mode: :aggressive},
            dependencies: ["health_check"]
          },
          %{
            id: "update_statistics",
            type: :data_operation,
            action: "maintenance.update_stats",
            parameters: %{tables: :all},
            dependencies: ["optimize_queries"]
          },
          %{
            id: "verify_integrity",
            type: :skill_invocation,
            action: "integrity.validate_data",
            parameters: %{validation_scope: :recent_changes},
            dependencies: ["update_statistics"]
          }
        ]
      }

      # Compose and execute workflow
      {:ok, workflow_id} = InstructionsProcessor.compose_workflow(complex_workflow)

      {:ok, execution_result} =
        InstructionsProcessor.execute_workflow(
          workflow_id,
          "database_maintenance_agent"
        )

      # Verify workflow execution
      assert execution_result.status == :completed
      assert map_size(execution_result.instruction_results) == 4

      # Verify instruction dependencies were respected
      instruction_results = execution_result.instruction_results
      assert Map.has_key?(instruction_results, "health_check")
      assert Map.has_key?(instruction_results, "optimize_queries")
      assert Map.has_key?(instruction_results, "update_statistics")
      assert Map.has_key?(instruction_results, "verify_integrity")
    end

    test "directives engine modifies database agent behavior dynamically" do
      # Test runtime behavior modification for database agents

      # Issue directive to enhance database monitoring
      monitoring_directive = %{
        type: :behavior_modification,
        target: :all,
        parameters: %{
          behavior_type: :monitoring_sensitivity,
          modification_type: :increase,
          target_category: :database
        },
        priority: 7
      }

      {:ok, directive_id} = DirectivesEngine.issue_directive(monitoring_directive)

      # Issue directive to adjust query optimization aggressiveness
      optimization_directive = %{
        type: :skill_configuration,
        target: :all,
        parameters: %{
          skill_id: :query_optimization_skill,
          configuration: %{
            # More aggressive
            optimization_threshold: 0.5,
            learning_rate: 0.8
          }
        },
        priority: 6
      }

      {:ok, optimization_directive_id} = DirectivesEngine.issue_directive(optimization_directive)

      # Verify directives are active
      {:ok, active_directives} = DirectivesEngine.get_agent_directives("database_test_agent")
      active_directive_ids = Enum.map(active_directives, & &1.id)

      assert directive_id in active_directive_ids
      assert optimization_directive_id in active_directive_ids

      # Test directive rollback
      {:ok, rollback_id} = DirectivesEngine.create_rollback_point("before_database_directives")
      assert :ok = DirectivesEngine.rollback_to_point(rollback_id)

      # Verify rollback worked
      {:ok, post_rollback_directives} =
        DirectivesEngine.get_agent_directives("database_test_agent")

      assert length(post_rollback_directives) < length(active_directives)
    end
  end

  describe "health monitoring integration with database operations" do
    test "database health monitoring reflects agent activity" do
      # Test that database health monitoring captures agent activity

      # Force database health checks
      DatabaseMonitor.force_check()
      Process.sleep(100)

      # Get database health status
      db_health = DatabaseMonitor.get_health_status()

      # Verify health monitoring provides meaningful data
      assert Map.has_key?(db_health, :status)
      assert db_health.status in [:healthy, :warning, :degraded, :critical]

      if Map.has_key?(db_health, :performance_metrics) do
        metrics = db_health.performance_metrics
        assert Map.has_key?(metrics, :query_response_time_ms)
        assert is_number(metrics.query_response_time_ms)
      end
    end

    test "agent health monitoring captures database agent ecosystem" do
      # Test agent health monitoring for database agents

      # Force agent health check
      AgentMonitor.force_check()
      Process.sleep(100)

      # Get agent health status
      agent_health = AgentMonitor.get_health_status()

      # Verify agent ecosystem monitoring
      assert Map.has_key?(agent_health, :status)
      assert Map.has_key?(agent_health, :agents)
      assert Map.has_key?(agent_health, :performance)

      # Verify database-related agent monitoring
      agents_status = agent_health.agents
      assert Map.has_key?(agents_status, :skills_registry_health)
      assert Map.has_key?(agents_status, :directives_engine_health)
      assert Map.has_key?(agents_status, :instructions_processor_health)
    end

    test "overall health status reflects database system health" do
      # Test that overall health aggregation includes database components

      # Get overall system health
      overall_status = StatusAggregator.get_overall_status()
      detailed_status = StatusAggregator.get_detailed_status()

      # Verify database components are included in health assessment
      components = detailed_status.components
      assert Map.has_key?(components, :database)
      # Includes database services
      assert Map.has_key?(components, :services)

      # Verify summary reflects database health
      summary = detailed_status.summary
      assert summary.total_components >= 4
      assert is_number(summary.health_percentage)
    end
  end

  describe "end-to-end database workflows" do
    test "complete migration workflow with monitoring and rollback" do
      # Test full migration workflow with all components

      # 1. Create migration agent
      {:ok, migration_agent} = MigrationAgent.create_migration_agent()

      # 2. Queue a test migration
      test_migration = TestMigration.AddIndexToUsers

      {:ok, migration_item, updated_agent} =
        MigrationAgent.queue_migration(
          migration_agent,
          test_migration,
          :normal,
          %{auto_execute: false}
        )

      # Verify migration was queued
      assert migration_item.migration_module == test_migration
      assert migration_item.priority == :normal
      assert length(updated_agent.migration_queue) >= 1

      # 3. Analyze migration with health monitoring
      {:ok, impact_prediction, final_agent} =
        MigrationAgent.predict_performance_impact(
          updated_agent,
          [test_migration]
        )

      # Verify impact analysis
      assert Map.has_key?(impact_prediction, :risk_assessment)
      assert Map.has_key?(impact_prediction, :recommended_execution_order)

      # 4. Test migration coordination with health monitoring
      # Note: Actual migration execution would be integration with Ecto
      # For integration test, verify the coordination mechanisms work

      # Verify health sensor can monitor migration impact
      {:ok, health_sensor} = DataHealthSensor.create_health_sensor()
      {:ok, baseline_health, _} = DataHealthSensor.establish_baselines(health_sensor, 1)

      assert Map.has_key?(baseline_health, :performance_baselines)
    end

    test "query optimization workflow with pattern learning" do
      # Test complete query optimization workflow

      # 1. Create query optimizer agent
      {:ok, optimizer_agent} = QueryOptimizerAgent.create_optimizer_agent()

      # 2. Analyze query patterns
      test_queries = [
        "SELECT * FROM users WHERE email = $1",
        "SELECT u.id, u.name FROM users u JOIN profiles p ON u.id = p.user_id",
        "SELECT COUNT(*) FROM users WHERE created_at > $1"
      ]

      {:ok, pattern_analysis, updated_optimizer} =
        QueryOptimizerAgent.analyze_query_patterns(
          optimizer_agent,
          %{queries: test_queries, analysis_depth: :comprehensive}
        )

      # Verify pattern analysis
      assert Map.has_key?(pattern_analysis, :pattern_analysis)
      assert Map.has_key?(pattern_analysis, :optimization_recommendations)

      # 3. Test optimization coordination with Skills Registry
      {:ok, optimization_skills} = SkillsRegistry.discover_skills(%{category: :database})
      assert Map.has_key?(optimization_skills, :query_optimization_skill)

      # 4. Execute query optimization through skills
      optimization_params = %{
        query: List.first(test_queries),
        execution_context: %{performance_target: :high}
      }

      {:ok, optimization_result, skill_state} =
        QueryOptimizationSkill.optimize_query(
          optimization_params,
          %{}
        )

      # Verify optimization results
      assert Map.has_key?(optimization_result, :optimized_query)
      assert Map.has_key?(optimization_result, :optimization_applied)

      # Verify learning integration
      optimization_history = Map.get(skill_state, :optimization_history, [])
      assert length(optimization_history) >= 1
    end

    test "database agent coordination through instructions processor" do
      # Test coordinated database operations through instruction workflows

      # Create database maintenance workflow
      maintenance_workflow = %{
        name: "database_agent_coordination_test",
        instructions: [
          %{
            id: "monitor_health",
            type: :skill_invocation,
            action: "health.establish_baselines",
            parameters: %{baseline_period_hours: 1},
            dependencies: []
          },
          %{
            id: "optimize_performance",
            type: :skill_invocation,
            action: "query.analyze_patterns",
            parameters: %{analysis_depth: :standard},
            dependencies: ["monitor_health"]
          },
          %{
            id: "assess_migration_readiness",
            type: :skill_invocation,
            action: "migration.analyze_impact",
            parameters: %{migration_scope: :pending},
            dependencies: ["optimize_performance"]
          }
        ]
      }

      # Execute coordination workflow
      {:ok, workflow_id} = InstructionsProcessor.compose_workflow(maintenance_workflow)

      {:ok, execution_result} =
        InstructionsProcessor.execute_workflow(
          workflow_id,
          "database_coordination_agent"
        )

      # Verify coordinated execution
      assert execution_result.status == :completed
      assert map_size(execution_result.instruction_results) == 3

      # Verify instruction dependency ordering was respected
      results = execution_result.instruction_results
      assert Map.has_key?(results, "monitor_health")
      assert Map.has_key?(results, "optimize_performance")
      assert Map.has_key?(results, "assess_migration_readiness")
    end
  end

  describe "database performance and scaling integration" do
    test "automatic scaling triggers based on database agent analysis" do
      # Test that database agents can trigger scaling decisions

      # Create data health sensor with scaling triggers
      {:ok, health_sensor} = DataHealthSensor.create_health_sensor()

      # Simulate high-load scenario
      scaling_action = :scale_up_cpu

      scaling_params = %{
        trigger_reason: :high_cpu_utilization,
        current_utilization: 0.85,
        # Don't actually scale in test
        auto_execute: false
      }

      {:ok, scaling_analysis, updated_sensor} =
        DataHealthSensor.trigger_scaling(
          health_sensor,
          scaling_action,
          scaling_params
        )

      # Verify scaling analysis
      assert Map.has_key?(scaling_analysis, :scaling_action)
      assert Map.has_key?(scaling_analysis, :estimated_impact)
      assert Map.has_key?(scaling_analysis, :rollback_plan)

      # Verify scaling was recorded in history
      scaling_history = Map.get(updated_sensor, :scaling_history, [])
      assert length(scaling_history) >= 1

      # Verify learning integration
      latest_scaling = List.first(scaling_history)
      assert Map.has_key?(latest_scaling, :scaling_justification)
    end

    test "database performance metrics feed into overall system health" do
      # Test integration between database performance and system health

      # Generate database activity
      {:ok, persistence_agent} = DataPersistenceAgent.create_persistence_agent()

      # Simulate database operations
      test_operations = [
        %{operation_type: :query, complexity: :medium},
        %{operation_type: :insert, volume: :high},
        %{operation_type: :update, complexity: :low}
      ]

      Enum.each(test_operations, fn operation ->
        # Simulate operation monitoring
        {:ok, _monitoring_result, persistence_agent} =
          DataPersistenceAgent.monitor_query_performance(
            persistence_agent,
            operation
          )
      end)

      # Wait for health monitoring to capture the activity
      Process.sleep(2000)

      # Verify database health reflects the activity
      db_health = DatabaseMonitor.get_health_status()

      # Should have recent performance data
      if Map.has_key?(db_health, :performance_metrics) do
        assert is_number(db_health.performance_metrics.query_response_time_ms)
      end

      # Verify overall system health includes database health
      overall_status = StatusAggregator.get_detailed_status()
      assert Map.has_key?(overall_status.components, :database)
    end
  end

  describe "error handling in database operations" do
    test "database agent error handling coordinates with error reporting" do
      # Test that database agent errors are properly aggregated and handled

      # Create migration agent for error testing
      {:ok, migration_agent} = MigrationAgent.create_migration_agent()

      # Attempt invalid migration (will trigger error handling)
      invalid_migration = TestMigration.InvalidOperation

      # Execute migration with high risk (should trigger rollback)
      execution_result =
        MigrationAgent.execute_migration(
          migration_agent,
          invalid_migration,
          %{force_execute: false}
        )

      # Should either succeed with rollback or fail gracefully
      case execution_result do
        {:ok, result, _updated_agent} ->
          # If execution succeeded, rollback should have been triggered
          assert Map.has_key?(result, :rollback_triggered)

        {:error, {:migration_risk_too_high, _risk_analysis}} ->
          # Risk assessment prevented execution - this is correct behavior
          :ok

        {:error, _reason} ->
          # Other error - verify it was reported
          # Allow error reporting
          Process.sleep(500)
          error_stats = Aggregator.get_error_stats()
          assert error_stats.total_error_count > 0
      end
    end

    test "database health monitoring detects and reports anomalies" do
      # Test anomaly detection and reporting integration

      # Create health sensor
      {:ok, health_sensor} = DataHealthSensor.create_health_sensor()

      # Establish baselines
      {:ok, baseline_result, sensor_with_baselines} =
        DataHealthSensor.establish_baselines(health_sensor, 1)

      # Verify baselines were established
      assert Map.has_key?(baseline_result, :performance_baselines)

      # Monitor performance (will detect anomalies against baselines)
      {:ok, monitoring_result, final_sensor} =
        DataHealthSensor.monitor_performance(sensor_with_baselines)

      # Verify monitoring captures anomaly detection
      assert Map.has_key?(monitoring_result, :anomaly_analysis)
      anomaly_analysis = monitoring_result.anomaly_analysis

      assert Map.has_key?(anomaly_analysis, :anomalies_detected)
      assert Map.has_key?(anomaly_analysis, :baseline_available)

      # If anomalies were detected, verify they're in agent history
      if anomaly_analysis.anomalies_detected do
        anomaly_history = Map.get(final_sensor, :anomaly_history, [])
        assert length(anomaly_history) >= 1
      end
    end
  end

  describe "real-world database scenarios" do
    test "high-volume query optimization scenario" do
      # Test system behavior under high query volume

      # Create persistence agent
      {:ok, persistence_agent} = DataPersistenceAgent.create_persistence_agent()

      # Simulate high-volume query optimization
      high_volume_queries =
        Enum.map(1..20, fn i ->
          %{
            query: "SELECT * FROM table_#{rem(i, 5)} WHERE id = $1",
            execution_context: %{volume: :high, iteration: i}
          }
        end)

      # Process queries through optimization
      optimization_results =
        Enum.map(high_volume_queries, fn query_params ->
          {:ok, result, persistence_agent} =
            DataPersistenceAgent.optimize_query_performance(persistence_agent, query_params)

          result
        end)

      # Verify all optimizations completed
      assert length(optimization_results) == 20

      # Verify optimization patterns were learned
      final_history = Map.get(persistence_agent, :optimization_history, [])
      assert length(final_history) >= 20

      # Verify system health remains stable under load
      final_health = StatusAggregator.get_overall_status()
      # Should not degrade to critical
      assert final_health in [:healthy, :warning]
    end

    test "complex migration coordination scenario" do
      # Test complex migration scenario with multiple agents

      # Create migration agent
      {:ok, migration_agent} = MigrationAgent.create_migration_agent()

      # Create multiple test migrations
      test_migrations = [
        TestMigration.AddUserPreferences,
        TestMigration.AddIndexToUsers,
        TestMigration.AlterUserTable
      ]

      # Queue migrations
      queued_agent =
        Enum.reduce(test_migrations, migration_agent, fn migration, agent ->
          {:ok, _migration_item, updated_agent} =
            MigrationAgent.queue_migration(
              agent,
              migration,
              :normal,
              %{}
            )

          updated_agent
        end)

      # Verify all migrations queued
      assert length(queued_agent.migration_queue) == 3

      # Analyze coordinated impact
      {:ok, impact_analysis, final_agent} =
        MigrationAgent.predict_performance_impact(
          queued_agent,
          test_migrations
        )

      # Verify comprehensive impact analysis
      assert impact_analysis.migrations_analyzed == 3
      assert Map.has_key?(impact_analysis, :total_estimated_impact)
      assert Map.has_key?(impact_analysis, :recommended_execution_order)
      assert Map.has_key?(impact_analysis, :performance_monitoring_plan)

      # Verify migration ordering optimization
      execution_order = impact_analysis.recommended_execution_order
      assert length(execution_order) == 3
    end
  end

  ## Helper Functions and Mock Modules

  # Mock migration modules for testing
  defmodule TestMigration do
    defmodule AddUserPreferences do
      def up, do: "ALTER TABLE users ADD COLUMN preferences JSON"
      def down, do: "ALTER TABLE users DROP COLUMN preferences"
    end

    defmodule AddIndexToUsers do
      def up, do: "CREATE INDEX idx_users_email ON users(email)"
      def down, do: "DROP INDEX idx_users_email"
    end

    defmodule AlterUserTable do
      def up, do: "ALTER TABLE users ALTER COLUMN email TYPE VARCHAR(320)"
      def down, do: "ALTER TABLE users ALTER COLUMN email TYPE VARCHAR(255)"
    end

    defmodule InvalidOperation do
      def up, do: "INVALID SQL STATEMENT"
      def down, do: "ALSO INVALID"
    end
  end
end
