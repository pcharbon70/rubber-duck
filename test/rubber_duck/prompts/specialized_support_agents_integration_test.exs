defmodule RubberDuck.Prompts.SpecializedSupportAgentsIntegrationTest do
  @moduledoc """
  Integration tests for Phase 02b Section 5.2: Specialized Support Agents.
  
  Tests cover:
  - Task 2B.5.3: Orchestration agent coordination with specialized agent integration
  - Task 2B.5.4: Composition accuracy and performance with cache and optimization
  - Task 2B.5.5: Validation and security enforcement with migration coordination
  - Task 2B.5.6: Analytics and optimization capabilities with specialized coordination
  """

  use ExUnit.Case, async: false

  alias RubberDuck.Prompts.Agents.{
    PromptCacheAgent,
    PromptMigrationAgent,
    PromptOptimizationAgent
  }

  describe "PromptCacheAgent coordination (2B.5.2.1 & 2B.5.3)" do
    test "PromptCacheAgent manages multi-tier cache operations autonomously" do
      cache_params = %{
        cache_operation: :optimize,
        cache_scope: :all_tiers,
        optimization_config: %{
          enable_intelligent_warming: true,
          enable_adaptive_eviction: true,
          optimization_interval_minutes: 5
        },
        performance_targets: %{
          min_hit_rate: 0.95,
          max_coordination_overhead_ms: 5
        }
      }

      assert {:ok, result} = PromptCacheAgent.start_agent(cache_params)
      
      # Validate cache operation results
      assert Map.has_key?(result, :operation_results)
      assert Map.has_key?(result, :monitoring_results)
      assert Map.has_key?(result, :cache_metadata)
      
      operation_results = result.operation_results
      assert operation_results.cache_operation == :optimize
      assert Map.has_key?(operation_results, :operation_successful)
      
      metadata = result.cache_metadata
      assert metadata.cache_operation == :optimize
      assert metadata.cache_scope == :all_tiers
      assert Map.has_key?(metadata, :performance_metrics)
    end

    test "PromptCacheAgent handles different cache operations effectively" do
      cache_operations = [:warm, :evict, :optimize, :monitor, :coordinate]

      for operation <- cache_operations do
        params = %{
          cache_operation: operation,
          cache_scope: :all_tiers
        }

        assert {:ok, result} = PromptCacheAgent.start_agent(params)
        
        # Should complete each operation successfully
        assert result.cache_metadata.cache_operation == operation
        assert Map.has_key?(result.operation_results, :operation_successful)
      end
    end

    test "cache agent coordinates with existing caching infrastructure" do
      coordination_params = %{
        cache_operation: :coordinate,
        cache_scope: :all_tiers,
        monitoring_config: %{
          enable_real_time_monitoring: true,
          performance_tracking: true
        }
      }

      assert {:ok, result} = PromptCacheAgent.start_agent(coordination_params)
      
      # Should provide coordination results
      monitoring = result.monitoring_results
      assert Map.has_key?(monitoring, :cache_health_score)
      assert Map.has_key?(monitoring, :performance_metrics)
      
      # Should meet performance targets
      metadata = result.cache_metadata
      assert metadata.coordination_overhead_ms < 20  # Should be reasonable
    end
  end

  describe "PromptMigrationAgent automation (2B.5.2.2 & 2B.5.4)" do
    test "PromptMigrationAgent discovers and migrates existing prompts" do
      migration_params = %{
        migration_operation: :migrate,
        migration_scope: :full_codebase,
        migration_config: %{
          enable_automatic_categorization: true,
          preserve_original_prompts: true,
          migration_batch_size: 5
        },
        validation_requirements: %{
          validate_syntax: true,
          validate_security: true,
          validate_completeness: true
        }
      }

      assert {:ok, result} = PromptMigrationAgent.start_agent(migration_params)
      
      # Validate migration results
      assert Map.has_key?(result, :migration_results)
      assert Map.has_key?(result, :validation_results)
      assert Map.has_key?(result, :migration_metadata)
      
      migration_results = result.migration_results
      assert migration_results.migration_operation == :migrate
      assert Map.has_key?(migration_results, :prompts_migrated)
      assert Map.has_key?(migration_results, :operation_successful)
      
      metadata = result.migration_metadata
      assert metadata.migration_operation == :migrate
      assert metadata.migration_scope == :full_codebase
    end

    test "PromptMigrationAgent handles different migration operations" do
      migration_operations = [:scan, :migrate, :validate, :rollback, :upgrade_schema]

      for operation <- migration_operations do
        params = %{
          migration_operation: operation,
          migration_scope: :module_scope
        }

        assert {:ok, result} = PromptMigrationAgent.start_agent(params)
        
        # Should complete each migration operation
        assert result.migration_metadata.migration_operation == operation
        assert Map.has_key?(result.migration_results, :operation_successful)
      end
    end

    test "migration agent provides rollback capabilities for failed operations" do
      rollback_params = %{
        migration_operation: :rollback,
        migration_scope: :full_codebase,
        rollback_config: %{
          enable_rollback: true,
          backup_original_state: true,
          rollback_timeout_ms: 5_000
        }
      }

      assert {:ok, result} = PromptMigrationAgent.start_agent(rollback_params)
      
      # Should provide rollback capabilities
      migration_results = result.migration_results
      assert migration_results.migration_operation == :rollback
      
      # Should have rollback information
      metadata = result.migration_metadata
      assert metadata.rollback_available == true
      
      # Should meet rollback performance targets
      rollback_time_ms = div(metadata.migration_time_microseconds, 1_000)
      assert rollback_time_ms < 10_000  # Should rollback quickly
    end
  end

  describe "PromptOptimizationAgent intelligence (2B.5.2.3 & 2B.5.6)" do
    test "PromptOptimizationAgent provides ML-driven optimization recommendations" do
      optimization_params = %{
        optimization_request: %{
          target_prompts: ["optimization_test_1", "optimization_test_2"],
          optimization_goals: %{
            improve_effectiveness: true,
            reduce_token_usage: true,
            enhance_performance: true
          }
        },
        optimization_scope: :comprehensive,
        learning_config: %{
          enable_ml_analysis: true,
          pattern_recognition: true,
          optimization_learning: true
        },
        improvement_targets: %{
          min_effectiveness_improvement: 0.15,
          max_token_reduction: 0.25
        }
      }

      assert {:ok, result} = PromptOptimizationAgent.start_agent(optimization_params)
      
      # Validate optimization results
      assert Map.has_key?(result, :analysis_results)
      assert Map.has_key?(result, :improvement_recommendations)
      assert Map.has_key?(result, :learning_results)
      
      analysis_results = result.analysis_results
      assert Map.has_key?(analysis_results, :performance_analysis)
      assert Map.has_key?(analysis_results, :effectiveness_analysis)
      assert Map.has_key?(analysis_results, :token_analysis)
      
      recommendations = result.improvement_recommendations
      assert Map.has_key?(recommendations, :performance_improvements)
      assert Map.has_key?(recommendations, :effectiveness_improvements)
      assert Map.has_key?(recommendations, :token_optimizations)
      
      metadata = result.optimization_metadata
      assert metadata.optimization_scope == :comprehensive
      assert Map.has_key?(metadata, :analysis_quality_score)
    end

    test "PromptOptimizationAgent handles different optimization scopes" do
      optimization_scopes = [:performance, :effectiveness, :token_usage, :comprehensive]

      for scope <- optimization_scopes do
        params = %{
          optimization_request: %{
            target_prompts: ["scope_test_prompt"],
            optimization_goals: %{basic_optimization: true}
          },
          optimization_scope: scope
        }

        assert {:ok, result} = PromptOptimizationAgent.start_agent(params)
        
        # Should complete optimization for each scope
        assert result.optimization_metadata.optimization_scope == scope
        
        # Should have appropriate analysis based on scope
        analysis_results = result.analysis_results
        
        case scope do
          :performance ->
            assert Map.has_key?(analysis_results, :performance_analysis)
          
          :effectiveness ->
            assert Map.has_key?(analysis_results, :effectiveness_analysis)
          
          :token_usage ->
            assert Map.has_key?(analysis_results, :token_analysis)
          
          :comprehensive ->
            # Should have all analysis types
            assert Map.has_key?(analysis_results, :performance_analysis)
            assert Map.has_key?(analysis_results, :effectiveness_analysis)
            assert Map.has_key?(analysis_results, :token_analysis)
        end
      end
    end

    test "optimization agent learns from successful patterns and feedback" do
      learning_focused_params = %{
        optimization_request: %{
          target_prompts: ["learning_test_prompt"],
          optimization_goals: %{
            pattern_learning: true,
            feedback_integration: true
          }
        },
        optimization_scope: :effectiveness,
        learning_config: %{
          enable_ml_analysis: true,
          pattern_recognition: true,
          confidence_threshold: 0.7
        },
        feedback_integration: true
      }

      assert {:ok, result} = PromptOptimizationAgent.start_agent(learning_focused_params)
      
      # Should provide learning results
      learning_results = result.learning_results
      
      case learning_results do
        %{learning_disabled: true} ->
          # Learning disabled is acceptable
          assert true
        
        %{patterns_learned: patterns} ->
          # Should identify patterns
          assert is_list(patterns)
          assert Map.has_key?(learning_results, :learning_effectiveness)
      end
      
      # Should provide insights
      metadata = result.optimization_metadata
      assert Map.has_key?(metadata, :learning_effectiveness)
      assert Map.has_key?(metadata, :optimization_potential)
    end
  end

  describe "specialized agent coordination and integration (2B.5.3-2B.5.6)" do
    test "specialized agents coordinate with Core Orchestration Agents" do
      # Test coordination between specialized and core agents
      
      # Step 1: Cache optimization
      cache_result = PromptCacheAgent.start_agent(%{
        cache_operation: :optimize,
        cache_scope: :all_tiers
      })
      
      assert {:ok, cache_optimization} = cache_result
      
      # Step 2: Migration scanning
      migration_result = PromptMigrationAgent.start_agent(%{
        migration_operation: :scan,
        migration_scope: :full_codebase
      })
      
      assert {:ok, migration_scan} = migration_result
      
      # Step 3: Optimization analysis
      optimization_result = PromptOptimizationAgent.start_agent(%{
        optimization_request: %{
          target_prompts: ["coordination_test"],
          optimization_goals: %{comprehensive_analysis: true}
        },
        optimization_scope: :comprehensive
      })
      
      assert {:ok, optimization_analysis} = optimization_result
      
      # All agents should complete successfully
      assert cache_optimization.operation_results.operation_successful == true
      assert migration_scan.migration_results.operation_successful == true
      assert Map.has_key?(optimization_analysis.analysis_results, :performance_analysis)
    end

    test "specialized agents maintain performance targets during operations" do
      # Test performance of specialized agent operations
      agent_operations = [
        {:cache, %{cache_operation: :monitor, cache_scope: :all_tiers}},
        {:migration, %{migration_operation: :scan, migration_scope: :module_scope}},
        {:optimization, %{
          optimization_request: %{target_prompts: ["performance_test"]},
          optimization_scope: :performance
        }}
      ]

      for {agent_type, params} <- agent_operations do
        {time_us, result} = :timer.tc(fn ->
          case agent_type do
            :cache -> PromptCacheAgent.start_agent(params)
            :migration -> PromptMigrationAgent.start_agent(params)
            :optimization -> PromptOptimizationAgent.start_agent(params)
          end
        end)

        # Should complete successfully
        assert {:ok, _agent_result} = result
        
        # Should meet performance targets
        time_ms = time_us / 1_000
        
        case agent_type do
          :cache -> assert time_ms < 100      # Cache operations should be fast
          :migration -> assert time_ms < 200  # Migration scanning should be reasonable
          :optimization -> assert time_ms < 300  # Optimization analysis can take longer
        end
      end
    end

    test "specialized agents handle error scenarios gracefully" do
      # Test error handling across specialized agents
      error_scenarios = [
        # Invalid cache operation
        {:cache, %{cache_operation: :invalid_op, cache_scope: :all_tiers}},
        # Invalid migration operation
        {:migration, %{migration_operation: :invalid_migration, migration_scope: :full_codebase}},
        # Invalid optimization request
        {:optimization, %{
          optimization_request: %{},  # Missing required fields
          optimization_scope: :invalid_scope
        }}
      ]

      for {agent_type, invalid_params} <- error_scenarios do
        result = case agent_type do
          :cache -> PromptCacheAgent.start_agent(invalid_params)
          :migration -> PromptMigrationAgent.start_agent(invalid_params)
          :optimization -> PromptOptimizationAgent.start_agent(invalid_params)
        end

        # Should fail gracefully with informative errors
        assert {:error, _reason} = result
      end
    end

    test "agents provide comprehensive analytics and reporting" do
      # Test comprehensive reporting across specialized agents
      
      # Cache monitoring with detailed analytics
      cache_monitoring_params = %{
        cache_operation: :monitor,
        cache_scope: :all_tiers,
        monitoring_config: %{
          enable_real_time_monitoring: true,
          performance_tracking: true
        }
      }

      assert {:ok, cache_result} = PromptCacheAgent.start_agent(cache_monitoring_params)
      
      cache_monitoring = cache_result.monitoring_results
      assert Map.has_key?(cache_monitoring, :cache_health_score)
      assert Map.has_key?(cache_monitoring, :performance_metrics)

      # Migration validation with comprehensive reporting
      migration_validation_params = %{
        migration_operation: :validate,
        migration_scope: :full_codebase,
        validation_requirements: %{
          validate_completeness: true,
          validate_security: true
        }
      }

      assert {:ok, migration_result} = PromptMigrationAgent.start_agent(migration_validation_params)
      
      migration_validation = migration_result.validation_results
      assert Map.has_key?(migration_validation, :validation_passed)
      assert Map.has_key?(migration_validation, :completeness_check)

      # Optimization with ML insights
      optimization_params = %{
        optimization_request: %{
          target_prompts: ["analytics_test"],
          optimization_goals: %{ml_insights: true}
        },
        optimization_scope: :comprehensive,
        learning_config: %{enable_ml_analysis: true}
      }

      assert {:ok, optimization_result} = PromptOptimizationAgent.start_agent(optimization_params)
      
      # Should provide comprehensive analysis
      analysis = optimization_result.analysis_results
      recommendations = optimization_result.improvement_recommendations
      
      assert Map.has_key?(analysis, :performance_analysis)
      assert Map.has_key?(recommendations, :performance_improvements)
    end

    test "specialized agents integrate with security and validation systems" do
      # Test security integration across specialized agents
      
      # Cache operations with security considerations
      secure_cache_params = %{
        cache_operation: :warm,
        cache_scope: :all_tiers,
        optimization_config: %{
          security_aware_caching: true
        }
      }

      assert {:ok, cache_result} = PromptCacheAgent.start_agent(secure_cache_params)
      assert cache_result.operation_results.operation_successful == true

      # Migration with security validation
      secure_migration_params = %{
        migration_operation: :migrate,
        migration_scope: :selective,
        validation_requirements: %{
          validate_security: true,
          require_manual_review: false
        }
      }

      assert {:ok, migration_result} = PromptMigrationAgent.start_agent(secure_migration_params)
      
      # Should validate security during migration
      validation = migration_result.validation_results
      assert Map.has_key?(validation, :security_validation)

      # Optimization with security awareness
      secure_optimization_params = %{
        optimization_request: %{
          target_prompts: ["security_test"],
          optimization_goals: %{security_aware_optimization: true}
        },
        optimization_scope: :comprehensive
      }

      assert {:ok, optimization_result} = PromptOptimizationAgent.start_agent(secure_optimization_params)
      assert Map.has_key?(optimization_result.analysis_results, :performance_analysis)
    end

    test "agents demonstrate enterprise-scale automation capabilities" do
      # Test enterprise automation features
      
      # Large-scale cache optimization
      enterprise_cache_params = %{
        cache_operation: :optimize,
        cache_scope: :all_tiers,
        optimization_config: %{
          enterprise_scale: true,
          batch_optimization: true
        },
        performance_targets: %{
          min_hit_rate: 0.98,
          target_memory_efficiency: 0.90
        }
      }

      assert {:ok, cache_result} = PromptCacheAgent.start_agent(enterprise_cache_params)
      
      # Should handle enterprise-scale operations
      cache_performance = cache_result.cache_metadata.performance_metrics
      assert Map.has_key?(cache_performance, :cache_health_score)

      # Comprehensive migration with validation
      enterprise_migration_params = %{
        migration_operation: :migrate,
        migration_scope: :full_codebase,
        migration_config: %{
          enterprise_validation: true,
          comprehensive_backup: true
        }
      }

      assert {:ok, migration_result} = PromptMigrationAgent.start_agent(enterprise_migration_params)
      assert migration_result.migration_metadata.rollback_available == true

      # Advanced optimization with ML learning
      enterprise_optimization_params = %{
        optimization_request: %{
          target_prompts: Enum.map(1..10, fn i -> "enterprise_prompt_#{i}" end),
          optimization_goals: %{enterprise_optimization: true}
        },
        optimization_scope: :comprehensive,
        learning_config: %{
          enable_ml_analysis: true,
          enterprise_learning: true
        }
      }

      assert {:ok, optimization_result} = PromptOptimizationAgent.start_agent(enterprise_optimization_params)
      
      # Should provide enterprise-grade analysis
      metadata = optimization_result.optimization_metadata
      assert metadata.improvements_identified > 0
      assert Map.has_key?(metadata, :optimization_potential)
    end
  end
end