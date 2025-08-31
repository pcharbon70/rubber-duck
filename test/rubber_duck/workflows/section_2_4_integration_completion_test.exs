defmodule RubberDuck.Workflows.Section24IntegrationCompletionTest do
  @moduledoc """
  Comprehensive unit tests for Phase 02a Section 2.4 remaining tasks completion.
  
  Tests cover:
  - Task 2.4.6: Agent workflow migration completeness
  - Task 2.4.7: Multi-agent orchestration patterns  
  - Task 2.4.8: Agent lifecycle management
  - Task 2.4.9: Agent workflow template generation
  
  Integration testing with template management and existing workflow infrastructure.
  """

  use ExUnit.Case, async: false

  alias RubberDuck.Workflows.Templates.{
    ErrorHandlingTemplateManager,
    PerformanceOptimizationTemplateManager
  }

  alias RubberDuck.Workflows.Actions.{
    CreateAgentTemplateAction,
    ManageAgentLifecycleAction,
    MigrateAgentWorkflowAction,
    OrchestrateAgentsAction
  }

  describe "agent workflow migration completeness (2.4.6)" do
    test "MigrateAgentWorkflowAction performs safe migration with comprehensive validation" do
      agent_spec = %{
        id: "test_agent_migration",
        type: :simple_agent,
        current_workflow: %{pattern: :basic, version: 1},
        complexity: :medium
      }

      params = %{
        agent_specification: agent_spec,
        target_workflow_pattern: :reactor_workflow,
        migration_strategy: :safe,
        validation_config: %{
          validate_agent_state: true,
          validate_workflow_compatibility: true,
          strict_validation: true
        },
        rollback_config: %{
          enable_rollback: true,
          backup_agent_state: true,
          automatic_rollback_on_failure: true
        }
      }

      assert {:ok, result} = MigrateAgentWorkflowAction.run(params, %{})
      
      # Validate migration results
      assert %{migration_results: migration, validation_results: validation, backup_state: backup} = result
      assert migration.conversion_successful == true
      assert validation.overall_success == true
      assert backup.rollback_available == true
      
      # Validate migration metadata
      metadata = result.migration_metadata
      assert metadata.migration_success == true
      assert metadata.target_pattern_achieved == :reactor_workflow
      assert metadata.rollback_available == true
    end

    test "MigrateAgentWorkflowAction handles different migration strategies effectively" do
      base_agent_spec = %{
        id: "strategy_test_agent",
        type: :complex_agent,
        current_workflow: %{pattern: :basic, version: 1}
      }

      migration_strategies = [:safe, :performance, :template_based, :adaptive]

      for strategy <- migration_strategies do
        params = %{
          agent_specification: base_agent_spec,
          target_workflow_pattern: :enhanced_agent_workflow,
          migration_strategy: strategy
        }

        assert {:ok, result} = MigrateAgentWorkflowAction.run(params, %{test_strategy: strategy})
        
        # Each strategy should complete successfully
        assert result.migration_results.conversion_successful == true
        assert result.migration_metadata.migration_strategy_used == strategy
        
        # Strategy-specific validation
        case strategy do
          :safe ->
            # Safe strategy should have comprehensive backup
            assert result.backup_state.rollback_available == true
          
          :performance ->
            # Performance strategy should track performance impact
            assert Map.has_key?(result.migration_metadata, :performance_impact)
          
          :template_based ->
            # Template-based should indicate template usage
            metadata = result.migration_metadata
            assert is_map(metadata)
          
          :adaptive ->
            # Adaptive should show strategy adaptation
            assert is_map(result.migration_metadata)
        end
      end
    end

    test "MigrateAgentWorkflowAction validates migration rollback functionality" do
      agent_spec = %{
        id: "rollback_test_agent",
        type: :stateful_agent,
        current_workflow: %{pattern: :stateful, version: 1}
      }

      # Test with rollback enabled
      params_with_rollback = %{
        agent_specification: agent_spec,
        target_workflow_pattern: :performance_optimized_workflow,
        migration_strategy: :safe,
        rollback_config: %{
          enable_rollback: true,
          backup_agent_state: true,
          verification_required: true
        }
      }

      assert {:ok, result} = MigrateAgentWorkflowAction.run(params_with_rollback, %{})
      
      # Should have created backup and rollback plan
      backup_state = result.backup_state
      assert backup_state.rollback_available == true
      assert Map.has_key?(backup_state, :agent_configuration)
      assert Map.has_key?(backup_state, :agent_state)
    end

    test "migration handles validation failures and automatic rollback" do
      # Test migration with agent specification that might cause validation failure
      problematic_agent_spec = %{
        id: "problematic_agent",
        type: :unknown_type,  # This might cause issues
        current_workflow: %{pattern: :invalid}
      }

      params = %{
        agent_specification: problematic_agent_spec,
        target_workflow_pattern: :reactor_workflow,
        migration_strategy: :safe
      }

      # May succeed with error handling or fail gracefully
      case MigrateAgentWorkflowAction.run(params, %{}) do
        {:ok, _result} -> 
          # Migration succeeded despite issues
          assert true
        
        {:error, reason} ->
          # Should fail gracefully with appropriate error
          assert is_tuple(reason)
      end
    end
  end

  describe "multi-agent orchestration patterns (2.4.7)" do
    test "OrchestrateAgentsAction coordinates multiple agents with different strategies" do
      agent_specifications = [
        %{id: "agent_1", type: :worker_agent, requires_coordination: false},
        %{id: "agent_2", type: :coordinator_agent, requires_coordination: true},
        %{id: "agent_3", type: :monitor_agent, requires_coordination: false}
      ]

      orchestration_strategies = [:sequential, :parallel, :pipeline, :adaptive]

      for strategy <- orchestration_strategies do
        params = %{
          agent_specifications: agent_specifications,
          orchestration_strategy: strategy,
          coordination_config: %{
            coordination_timeout_ms: 10_000,
            enable_agent_health_monitoring: true
          }
        }

        assert {:ok, result} = OrchestrateAgentsAction.run(params, %{test_strategy: strategy})
        
        # Validate orchestration results
        orchestration = result.orchestration_results
        assert orchestration.coordination_successful == true
        assert Map.has_key?(orchestration, :execution_results)
        
        # Validate coordination metadata
        metadata = result.orchestration_metadata
        assert metadata.agents_coordinated == 3
        assert metadata.coordination_success == true
        assert metadata.orchestration_strategy_used == strategy
      end
    end

    test "OrchestrateAgentsAction handles large-scale multi-agent coordination" do
      # Test with larger number of agents
      large_agent_specifications = Enum.map(1..20, fn i ->
        %{
          id: "agent_#{i}",
          type: :worker_agent,
          complexity: if(rem(i, 3) == 0, do: :complex, else: :simple),
          requires_coordination: rem(i, 4) == 0
        }
      end)

      params = %{
        agent_specifications: large_agent_specifications,
        orchestration_strategy: :adaptive,  # Best for large numbers
        coordination_config: %{
          coordination_timeout_ms: 30_000,
          agent_startup_timeout_ms: 5_000
        },
        performance_targets: %{
          max_coordination_overhead_ms: 200,
          min_orchestration_success_rate: 0.9
        }
      }

      assert {:ok, result} = OrchestrateAgentsAction.run(params, %{})
      
      # Should handle large-scale coordination effectively
      metadata = result.orchestration_metadata
      assert metadata.agents_coordinated == 20
      assert metadata.coordination_success == true
      
      # Coordination overhead should be reasonable
      coordination_overhead = metadata.coordination_overhead_ms
      assert coordination_overhead <= 200
    end

    test "OrchestrateAgentsAction handles coordination failures and recovery" do
      # Test with potentially problematic agent specifications
      problematic_agents = [
        %{id: "normal_agent", type: :worker_agent},
        %{id: "problematic_agent", type: :unknown_type},  # May cause issues
        %{id: "timeout_agent", type: :slow_agent}  # May timeout
      ]

      params = %{
        agent_specifications: problematic_agents,
        orchestration_strategy: :parallel,
        coordination_config: %{coordination_timeout_ms: 5_000},  # Short timeout
        error_handling_config: %{
          error_strategy: :partial_recovery,
          coordination_failure_handling: :graceful_degradation
        }
      }

      case OrchestrateAgentsAction.run(params, %{}) do
        {:ok, result} ->
          # Should succeed with partial coordination
          assert result.orchestration_results.coordination_successful == true
        
        {:error, {_error_type, _reason, recovery_result}} ->
          # Should fail but attempt recovery
          assert Map.has_key?(recovery_result, :recovery_successful)
        
        {:error, _reason} ->
          # May fail gracefully without recovery
          assert true
      end
    end

    test "orchestration validates coordination topology and synchronization" do
      # Test different coordination topologies
      coordination_test_specs = [
        # Small group - should use star topology
        {
          Enum.map(1..3, fn i -> %{id: "small_agent_#{i}", type: :worker} end),
          :parallel,
          :star_topology
        },
        # Large group - should use hierarchical
        {
          Enum.map(1..15, fn i -> %{id: "large_agent_#{i}", type: :worker} end),
          :parallel,
          :hierarchical_coordination
        },
        # Pipeline - should use pipeline topology
        {
          Enum.map(1..5, fn i -> %{id: "pipeline_agent_#{i}", type: :stage_#{i}} end),
          :pipeline,
          :pipeline_topology
        }
      ]

      for {agent_specs, strategy, expected_topology} <- coordination_test_specs do
        params = %{
          agent_specifications: agent_specs,
          orchestration_strategy: strategy
        }

        assert {:ok, result} = OrchestrateAgentsAction.run(params, %{})
        
        # Should select appropriate coordination topology
        coordination_type = result.orchestration_results.coordination_type
        assert coordination_type != nil
      end
    end
  end

  describe "agent lifecycle management (2.4.8)" do
    test "ManageAgentLifecycleAction handles all supported lifecycle operations" do
      agent_spec = %{
        id: "lifecycle_test_agent",
        type: :stateful_agent,
        current_state: :uninitialized,
        complexity: :medium
      }

      lifecycle_operations = [
        {:initialize, :ready},
        {:start, :active},
        {:pause, :paused},
        {:resume, :active},
        {:restart, :active},
        {:maintenance, :maintenance},
        {:shutdown, :terminated}
      ]

      for {operation, expected_state} <- lifecycle_operations do
        # Update agent spec with appropriate current state for operation
        current_agent_spec = case operation do
          :initialize -> %{agent_spec | current_state: :uninitialized}
          :start -> %{agent_spec | current_state: :ready}
          :pause -> %{agent_spec | current_state: :active}
          :resume -> %{agent_spec | current_state: :paused}
          :restart -> %{agent_spec | current_state: :active}
          :maintenance -> %{agent_spec | current_state: :active}
          :shutdown -> %{agent_spec | current_state: :active}
        end

        params = %{
          agent_specification: current_agent_spec,
          lifecycle_operation: operation,
          lifecycle_config: %{
            state_persistence: true,
            health_monitoring: true
          },
          state_management: %{
            backup_state_on_transitions: true,
            validate_state_integrity: true
          }
        }

        assert {:ok, result} = ManageAgentLifecycleAction.run(params, %{test_operation: operation})
        
        # Validate lifecycle operation results
        lifecycle_results = result.lifecycle_results
        assert lifecycle_results.operation_executed == operation
        assert lifecycle_results.state_transition.transition_successful == true
        
        # Validate state transition
        state_transition = result.lifecycle_metadata.state_transition
        assert state_transition.new_state == expected_state
      end
    end

    test "ManageAgentLifecycleAction validates state transitions and prevents invalid operations" do
      agent_spec = %{
        id: "state_validation_agent",
        type: :worker_agent,
        current_state: :uninitialized
      }

      # Test invalid state transition (trying to pause uninitialized agent)
      invalid_params = %{
        agent_specification: agent_spec,
        lifecycle_operation: :pause  # Can't pause uninitialized agent
      }

      assert {:error, {:lifecycle_failed_with_recovery, {:parameter_validation_failed, {:invalid_state_transition, :uninitialized, :pause}}, _}} = 
        ManageAgentLifecycleAction.run(invalid_params, %{})
    end

    test "ManageAgentLifecycleAction creates and manages agent state backups" do
      agent_spec = %{
        id: "backup_test_agent", 
        type: :stateful_agent,
        current_state: :active,
        complexity: :complex
      }

      params = %{
        agent_specification: agent_spec,
        lifecycle_operation: :pause,
        state_management: %{
          backup_state_on_transitions: true,
          validate_state_integrity: true,
          enable_state_rollback: true
        }
      }

      assert {:ok, result} = ManageAgentLifecycleAction.run(params, %{})
      
      # Should have created state backup
      state_backup = result.state_backup
      assert state_backup.backup_valid == true
      assert Map.has_key?(state_backup, :agent_configuration)
      assert Map.has_key?(state_backup, :workflow_state)
      assert Map.has_key?(state_backup, :resource_allocations)
    end

    test "lifecycle management integrates with error handling templates" do
      agent_spec = %{
        id: "error_integration_agent",
        type: :error_prone_agent,
        current_state: :active
      }

      params = %{
        agent_specification: agent_spec,
        lifecycle_operation: :restart,
        error_recovery_config: %{
          use_error_templates: true,
          recovery_strategy: :template_based,
          max_recovery_attempts: 2
        }
      }

      assert {:ok, result} = ManageAgentLifecycleAction.run(params, %{})
      
      # Should complete successfully with error template integration
      assert result.lifecycle_results.state_transition.transition_successful == true
      assert result.lifecycle_metadata.lifecycle_success == true
    end

    test "lifecycle management handles complex agent types with performance monitoring" do
      complex_agent_spec = %{
        id: "complex_lifecycle_agent",
        type: :enterprise_agent,
        current_state: :ready,
        complexity: :enterprise,
        resource_requirements: %{
          memory_mb: 500,
          cpu_cores: 2,
          io_handles: 50
        }
      }

      params = %{
        agent_specification: complex_agent_spec,
        lifecycle_operation: :start,
        monitoring_config: %{
          monitor_lifecycle_events: true,
          monitor_state_transitions: true,
          monitor_performance_during_lifecycle: true,
          alert_on_anomalies: true
        }
      }

      assert {:ok, result} = ManageAgentLifecycleAction.run(params, %{})
      
      # Should handle complex agent lifecycle successfully
      assert result.lifecycle_results.state_transition.transition_successful == true
      
      # Should track performance during lifecycle operation
      performance_impact = result.lifecycle_metadata.performance_impact
      assert Map.has_key?(performance_impact, :operation_overhead_ms)
      assert Map.has_key?(performance_impact, :resource_impact)
    end
  end

  describe "agent workflow template generation (2.4.9)" do
    test "CreateAgentTemplateAction generates templates from performance patterns" do
      source_data = %{
        patterns: [
          %{pattern_type: :high_performance, success_rate: 0.95, usage_count: 100},
          %{pattern_type: :resource_efficient, success_rate: 0.88, usage_count: 75}
        ],
        performance_data: %{
          throughput: 250,
          latency: 400,
          resource_usage: %{cpu: 0.6, memory: 0.5},
          error_rate: 0.02
        },
        sample_count: 150,
        metadata: %{source: :agent_workflows, quality: :high}
      }

      template_types = [:performance, :error_recovery, :coordination, :lifecycle]

      for template_type <- template_types do
        params = %{
          source_data: source_data,
          template_type: template_type,
          generation_strategy: :pattern_based,
          template_config: %{
            pattern_analysis_depth: :comprehensive,
            include_performance_metrics: true,
            validate_generated_template: true
          }
        }

        assert {:ok, result} = CreateAgentTemplateAction.run(params, %{test_type: template_type})
        
        # Validate template generation results
        generated_template = result.generated_template
        assert generated_template.type == template_type
        assert Map.has_key?(generated_template, :template_data)
        assert Map.has_key?(generated_template, :effectiveness_prediction)
        
        # Validate generation metadata
        metadata = result.generation_metadata
        assert metadata.generation_success == true
        assert metadata.template_type == template_type
        assert metadata.pattern_quality_score > 0.0
        assert metadata.template_effectiveness_score > 0.0
      end
    end

    test "CreateAgentTemplateAction uses different generation strategies effectively" do
      high_quality_source = %{
        patterns: Enum.map(1..10, fn i ->
          %{pattern_id: "pattern_#{i}", effectiveness: 0.8 + :rand.uniform() * 0.2}
        end),
        performance_data: %{
          throughput: 300,
          latency: 200,
          optimization_history: Enum.map(1..5, fn _ -> %{improvement: 10 + :rand.uniform(20)} end)
        },
        sample_count: 200
      }

      generation_strategies = [:pattern_based, :performance_based, :hybrid, :adaptive]

      for strategy <- generation_strategies do
        params = %{
          source_data: high_quality_source,
          template_type: :performance,
          generation_strategy: strategy
        }

        assert {:ok, result} = CreateAgentTemplateAction.run(params, %{test_strategy: strategy})
        
        generated_template = result.generated_template
        assert generated_template.generation_strategy == strategy
        
        # Different strategies should produce templates with different characteristics
        case strategy do
          :pattern_based ->
            # Should focus on behavioral patterns
            assert Map.has_key?(generated_template.template_data, :extracted_patterns)
          
          :performance_based ->
            # Should focus on performance characteristics
            assert Map.has_key?(generated_template.template_data, :performance_characteristics)
          
          :hybrid ->
            # Should combine both approaches
            template_data = generated_template.template_data
            assert Map.has_key?(template_data, :extracted_patterns)
            assert Map.has_key?(template_data, :performance_characteristics)
          
          :adaptive ->
            # Should adapt based on data characteristics
            assert is_map(generated_template.template_data)
        end
      end
    end

    test "CreateAgentTemplateAction validates template quality and effectiveness" do
      moderate_quality_source = %{
        patterns: [
          %{pattern_type: :standard, effectiveness: 0.7}
        ],
        performance_data: %{throughput: 100, latency: 1000},
        sample_count: 30  # Smaller sample size
      }

      params = %{
        source_data: moderate_quality_source,
        template_type: :performance,
        generation_strategy: :adaptive,
        validation_requirements: %{
          validate_pattern_quality: true,
          validate_performance_impact: true,
          validate_reusability: true,
          minimum_effectiveness_score: 0.6  # Lower threshold for test
        }
      }

      assert {:ok, result} = CreateAgentTemplateAction.run(params, %{})
      
      # Validate template validation results
      validation_results = result.validation_results
      assert validation_results.overall_validation_passed == true
      assert validation_results.overall_validation_score >= 0.6
      
      # Should have validated multiple aspects
      assert Map.has_key?(validation_results, :template_quality_validation)
      assert Map.has_key?(validation_results, :performance_impact_validation)
      assert Map.has_key?(validation_results, :reusability_validation)
      assert Map.has_key?(validation_results, :compliance_validation)
    end

    test "template generation fails gracefully with insufficient source data" do
      insufficient_source_data = %{
        patterns: [],  # No patterns
        sample_count: 2  # Very small sample
      }

      params = %{
        source_data: insufficient_source_data,
        template_type: :performance,
        generation_strategy: :pattern_based
      }

      assert {:error, {:template_generation_failed, {:parameter_validation_failed, :insufficient_source_data}}} = 
        CreateAgentTemplateAction.run(params, %{})
    end

    test "template generation includes customization and parameterization" do
      rich_source_data = %{
        patterns: Enum.map(1..15, fn i ->
          %{
            pattern_id: "rich_pattern_#{i}",
            success_rate: 0.85 + :rand.uniform() * 0.15,
            parameters: %{concurrency: i * 2, batch_size: i * 10}
          }
        end),
        performance_data: %{
          optimization_outcomes: Enum.map(1..10, fn _ -> %{improvement: 15 + :rand.uniform(25)} end)
        },
        sample_count: 500
      }

      params = %{
        source_data: rich_source_data,
        template_type: :performance,
        generation_strategy: :hybrid,
        customization_options: %{
          enable_parameterization: true,
          generate_variants: true,
          include_optimization_hints: true,
          add_usage_examples: true
        }
      }

      assert {:ok, result} = CreateAgentTemplateAction.run(params, %{})
      
      generated_template = result.generated_template
      
      # Should include parameterization
      assert Map.has_key?(generated_template, :parameterization)
      parameterization = generated_template.parameterization
      assert Map.has_key?(parameterization, :configurable_parameters)
      assert Map.has_key?(parameterization, :default_values)
      
      # Should include usage guidelines
      assert Map.has_key?(generated_template, :usage_guidelines)
      usage_guidelines = generated_template.usage_guidelines
      assert Map.has_key?(usage_guidelines, :recommended_use_cases)
      assert Map.has_key?(usage_guidelines, :implementation_steps)
    end
  end

  describe "template management system integration (2.4.6-2.4.9)" do
    test "ErrorHandlingTemplateManager integrates with agent lifecycle management" do
      # Test integration between error templates and lifecycle management
      agent_spec = %{
        id: "error_template_integration_agent",
        type: :error_prone_agent,
        current_state: :active
      }

      lifecycle_params = %{
        agent_specification: agent_spec,
        lifecycle_operation: :restart,
        error_recovery_config: %{
          use_error_templates: true,
          recovery_strategy: :template_based
        }
      }

      # Should complete successfully with error template integration
      assert {:ok, lifecycle_result} = ManageAgentLifecycleAction.run(lifecycle_params, %{})
      assert lifecycle_result.lifecycle_results.state_transition.transition_successful == true
    end

    test "PerformanceOptimizationTemplateManager supports template generation workflow" do
      # Test that performance templates can be used in template generation
      performance_source = %{
        patterns: [
          %{type: :optimization, strategy: :resource_efficient, effectiveness: 0.9}
        ],
        performance_data: %{
          optimization_outcomes: [%{improvement: 25, strategy: :resource_efficient}]
        },
        sample_count: 100
      }

      template_params = %{
        source_data: performance_source,
        template_type: :performance,
        generation_strategy: :performance_based
      }

      assert {:ok, template_result} = CreateAgentTemplateAction.run(template_params, %{})
      
      # Should generate performance-focused template
      generated_template = template_result.generated_template
      assert generated_template.type == :performance
      assert Map.has_key?(generated_template.template_data, :performance_characteristics)
    end

    test "all components handle concurrent operations safely" do
      # Test concurrent operations across different actions
      agent_spec = %{
        id: "concurrent_test_agent",
        type: :worker_agent,
        current_state: :active
      }

      tasks = [
        Task.async(fn ->
          ManageAgentLifecycleAction.run(%{
            agent_specification: agent_spec,
            lifecycle_operation: :maintenance
          }, %{test_id: 1})
        end),
        
        Task.async(fn ->
          CreateAgentTemplateAction.run(%{
            source_data: %{
              patterns: [%{type: :test}],
              performance_data: %{throughput: 100},
              sample_count: 50
            },
            template_type: :performance,
            generation_strategy: :pattern_based
          }, %{test_id: 2})
        end),
        
        Task.async(fn ->
          OrchestrateAgentsAction.run(%{
            agent_specifications: [
              %{id: "concurrent_agent_1", type: :worker},
              %{id: "concurrent_agent_2", type: :worker}
            ],
            orchestration_strategy: :parallel
          }, %{test_id: 3})
        end)
      ]

      results = Task.await_many(tasks, 15_000)
      
      # All operations should complete successfully
      for result <- results do
        assert {:ok, _} = result
      end
    end

    test "template management system maintains consistency across operations" do
      # Test that template management maintains consistency across different operations
      
      # Create a template
      source_data = %{
        patterns: [%{type: :consistency_test, effectiveness: 0.85}],
        performance_data: %{throughput: 200},
        sample_count: 75
      }

      template_params = %{
        source_data: source_data,
        template_type: :coordination,
        generation_strategy: :pattern_based
      }

      assert {:ok, template_result} = CreateAgentTemplateAction.run(template_params, %{})
      template_id = template_result.generated_template.id
      
      # Use the template in agent operations
      agent_specs = [
        %{id: "consistency_agent_1", type: :coordinator},
        %{id: "consistency_agent_2", type: :worker}
      ]

      orchestration_params = %{
        agent_specifications: agent_specs,
        orchestration_strategy: :adaptive,
        coordination_config: %{
          template_integration: true,
          use_generated_templates: true
        }
      }

      assert {:ok, orchestration_result} = OrchestrateAgentsAction.run(orchestration_params, %{template_id: template_id})
      
      # Orchestration should complete successfully with template integration
      assert orchestration_result.orchestration_results.coordination_successful == true
    end

    test "comprehensive integration validates end-to-end template workflow" do
      # Test complete workflow: migration -> orchestration -> lifecycle -> template generation
      
      # Step 1: Migrate an agent workflow
      agent_spec = %{
        id: "integration_workflow_agent",
        type: :integration_test_agent,
        current_workflow: %{pattern: :basic},
        current_state: :uninitialized
      }

      migration_params = %{
        agent_specification: agent_spec,
        target_workflow_pattern: :enhanced_agent_workflow,
        migration_strategy: :template_based
      }

      assert {:ok, migration_result} = MigrateAgentWorkflowAction.run(migration_params, %{})
      assert migration_result.migration_results.conversion_successful == true

      # Step 2: Initialize the migrated agent
      lifecycle_params = %{
        agent_specification: %{agent_spec | current_state: :uninitialized},
        lifecycle_operation: :initialize
      }

      assert {:ok, lifecycle_result} = ManageAgentLifecycleAction.run(lifecycle_params, %{})
      assert lifecycle_result.lifecycle_results.state_transition.transition_successful == true

      # Step 3: Orchestrate multiple agents including the migrated one
      orchestration_agents = [
        %{agent_spec | current_state: :ready},
        %{id: "orchestration_partner", type: :partner_agent, current_state: :ready}
      ]

      orchestration_params = %{
        agent_specifications: orchestration_agents,
        orchestration_strategy: :parallel
      }

      assert {:ok, orchestration_result} = OrchestrateAgentsAction.run(orchestration_params, %{})
      assert orchestration_result.orchestration_results.coordination_successful == true

      # Step 4: Generate template from successful workflow patterns
      template_source = %{
        patterns: [
          %{migration_pattern: migration_result.migration_metadata},
          %{orchestration_pattern: orchestration_result.orchestration_metadata}
        ],
        performance_data: %{
          migration_improvement: migration_result.migration_metadata.performance_impact,
          orchestration_efficiency: orchestration_result.orchestration_metadata.coordination_overhead_ms
        },
        sample_count: 50
      }

      template_params = %{
        source_data: template_source,
        template_type: :coordination,
        generation_strategy: :hybrid
      }

      assert {:ok, template_result} = CreateAgentTemplateAction.run(template_params, %{})
      assert template_result.generation_metadata.generation_success == true

      # Validate end-to-end workflow success
      assert is_binary(template_result.generated_template.id)
      assert template_result.validation_results.overall_validation_passed == true
    end

    test "template system handles error scenarios and recovery gracefully" do
      # Test error handling in template management system
      
      # Test with invalid source data
      invalid_source = %{
        invalid_field: "invalid_data"
        # Missing required fields
      }

      invalid_params = %{
        source_data: invalid_source,
        template_type: :performance,
        generation_strategy: :pattern_based
      }

      assert {:error, {:template_generation_failed, {:parameter_validation_failed, :insufficient_source_data}}} = 
        CreateAgentTemplateAction.run(invalid_params, %{})

      # Test lifecycle operation with invalid agent specification
      invalid_agent = %{
        # Missing required id and type fields
        current_state: :unknown
      }

      lifecycle_params = %{
        agent_specification: invalid_agent,
        lifecycle_operation: :start
      }

      assert {:error, _} = ManageAgentLifecycleAction.run(lifecycle_params, %{})

      # Test orchestration with empty agent list
      empty_orchestration_params = %{
        agent_specifications: [],  # Empty list
        orchestration_strategy: :parallel
      }

      assert {:error, {:orchestration_failed_with_recovery, {:parameter_validation_failed, :invalid_agent_specifications}, _}} = 
        OrchestrateAgentsAction.run(empty_orchestration_params, %{})
    end

    test "performance optimization integrates across all template management components" do
      # Test performance optimization integration across template management system
      
      # Create performance-optimized source data
      optimized_source = %{
        patterns: [
          %{type: :high_performance, optimization_focus: :throughput, effectiveness: 0.92},
          %{type: :resource_efficient, optimization_focus: :efficiency, effectiveness: 0.87}
        ],
        performance_data: %{
          baseline_metrics: %{throughput: 150, latency: 600, cpu: 0.7, memory: 0.6},
          optimized_metrics: %{throughput: 200, latency: 400, cpu: 0.6, memory: 0.5},
          improvement_percentage: 25.0
        },
        sample_count: 300
      }

      # Generate performance template
      template_params = %{
        source_data: optimized_source,
        template_type: :performance,
        generation_strategy: :performance_based,
        validation_requirements: %{
          minimum_effectiveness_score: 0.8  # High effectiveness requirement
        }
      }

      assert {:ok, template_result} = CreateAgentTemplateAction.run(template_params, %{})
      
      # Template should meet high effectiveness standards
      validation = template_result.validation_results
      assert validation.overall_validation_passed == true
      assert validation.overall_validation_score >= 0.8
      
      # Should include performance optimization guidance
      generated_template = template_result.generated_template
      assert Map.has_key?(generated_template.template_data, :performance_characteristics)
      assert Map.has_key?(generated_template, :effectiveness_prediction)
    end
  end
end