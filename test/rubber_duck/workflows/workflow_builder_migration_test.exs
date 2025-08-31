defmodule RubberDuck.Workflows.WorkflowBuilderMigrationTest do
  @moduledoc """
  Comprehensive tests for Phase 02a Section 1.2.6-1.2.9 workflow builder and migration.

  Tests all workflow builder enhancements, component migration actions, and
  validation utilities to ensure complete Section 1.2 functionality.
  """

  use ExUnit.Case, async: true

  alias RubberDuck.Workflows.{
    Actions.ConvertStepAction,
    Builder.EnhancedWorkflowBuilder
  }

  @moduletag :unit
  @moduletag :workflows
  @moduletag :migration

  describe "step conversion accuracy and functionality (1.2.6)" do
    test "converts simple workflow steps accurately" do
      step_spec = %{
        name: :process_data,
        action: :data_processing,
        type: :processing,
        metadata: %{priority: :normal}
      }

      params = %{
        step_specification: step_spec,
        conversion_type: :direct,
        validation_config: %{validate_compatibility: true}
      }

      assert {:ok, result} = ConvertStepAction.run(params, %{})

      # Validate conversion result
      converted_step = result.converted_step
      assert converted_step.name == :process_data
      assert converted_step.action == :data_processing
      assert converted_step.type == :reactor_step
      assert converted_step.conversion_type == :direct
      assert converted_step.reactor_compatible == true

      # Validate conversion metadata
      metadata = result.conversion_metadata
      assert is_integer(metadata.conversion_time_microseconds)
      assert Map.has_key?(metadata, :validation_results)
      assert metadata.validation_results.validation_passed == true
    end

    test "handles different conversion types" do
      conversion_types = [:direct, :enhanced, :optimized, :safe]

      Enum.each(conversion_types, fn conversion_type ->
        step_spec = %{
          name: String.to_atom("test_step_#{conversion_type}"),
          action: String.to_atom("test_action_#{conversion_type}")
        }

        params = %{
          step_specification: step_spec,
          conversion_type: conversion_type
        }

        assert {:ok, result} = ConvertStepAction.run(params, %{})
        assert result.converted_step.conversion_type == conversion_type

        # Enhanced conversions should have enhancements
        if conversion_type == :enhanced do
          assert Map.has_key?(result.converted_step, :enhancements)
          assert is_list(result.converted_step.enhancements)
        end

        # Optimized conversions should have optimizations
        if conversion_type == :optimized do
          assert Map.has_key?(result.converted_step, :optimizations)
          assert Map.has_key?(result.converted_step, :performance_targets)
        end

        # Safe conversions should have safety measures
        if conversion_type == :safe do
          assert Map.has_key?(result.converted_step, :safety_measures)
          assert result.converted_step.rollback_capability == true
        end
      end)
    end

    test "validates conversion accuracy for complex steps" do
      complex_step = %{
        name: :orchestrate_workflow,
        action: :workflow_orchestration,
        type: :coordination,
        dependencies: [:init_step, :setup_step],
        parameters: %{
          coordination_strategy: :hierarchical,
          timeout_ms: 60_000,
          error_handling: :comprehensive
        }
      }

      params = %{
        step_specification: complex_step,
        conversion_type: :safe,
        validation_config: %{
          validate_compatibility: true,
          validate_performance: true,
          validate_safety: true
        }
      }

      assert {:ok, result} = ConvertStepAction.run(params, %{})

      # Complex steps should be converted with safety measures
      converted_step = result.converted_step
      assert converted_step.type == :safe_reactor_step
      assert converted_step.safety_measures != nil
      assert converted_step.validation_comprehensive == true

      # Should pass comprehensive validation
      validation_results = result.conversion_metadata.validation_results
      assert validation_results.validation_passed == true
      assert validation_results.validation_score >= 0.8
    end
  end

  describe "rule translation and conditional logic (1.2.7)" do
    test "translates conditional logic patterns" do
      # Test rule translation capabilities (simulated with step conversion)
      conditional_step = %{
        name: :conditional_processor,
        action: :process_if_condition,
        type: :conditional,
        conditions: [
          %{condition: :data_available, action: :process_data},
          %{condition: :error_detected, action: :handle_error}
        ]
      }

      params = %{
        step_specification: conditional_step,
        conversion_type: :enhanced,
        migration_context: %{translation_type: :conditional_logic}
      }

      assert {:ok, result} = ConvertStepAction.run(params, %{})

      # Should convert conditional logic appropriately
      converted_step = result.converted_step
      assert converted_step.type == :enhanced_reactor_step
      assert :dependency_resolution in converted_step.reactor_features

      # Should have conditional logic metadata
      conversion_metadata = result.conversion_metadata
      assert Map.get(conversion_metadata.context, :translation_type) == :conditional_logic
    end

    test "handles complex rule patterns" do
      # Test complex rule pattern translation
      complex_rule = %{
        name: :complex_rule_processor,
        action: :evaluate_complex_rules,
        type: :rule_evaluation,
        rule_patterns: [
          %{pattern: :sequential, rules: [:rule_a, :rule_b, :rule_c]},
          %{pattern: :parallel, rules: [:rule_x, :rule_y]},
          %{pattern: :conditional, condition: :data_valid, rules: [:validation_rule]}
        ]
      }

      params = %{
        step_specification: complex_rule,
        conversion_type: :optimized,
        validation_config: %{validate_performance: true}
      }

      assert {:ok, result} = ConvertStepAction.run(params, %{})

      # Complex rules should be optimized for performance
      converted_step = result.converted_step
      assert converted_step.type == :optimized_reactor_step
      assert Map.has_key?(converted_step, :performance_targets)

      # Should have optimization metadata
      performance_targets = converted_step.performance_targets
      assert Map.has_key?(performance_targets, :performance_improvement)
    end
  end

  describe "state machine migration and event handling (1.2.8)" do
    test "migrates state machine patterns" do
      # Test state machine migration (simulated with step conversion)
      state_machine_step = %{
        name: :state_machine_processor,
        action: :manage_workflow_state,
        type: :state_management,
        states: [:idle, :processing, :completed, :failed],
        transitions: [
          %{from: :idle, to: :processing, trigger: :start_processing},
          %{from: :processing, to: :completed, trigger: :processing_complete},
          %{from: :processing, to: :failed, trigger: :processing_error}
        ]
      }

      params = %{
        step_specification: state_machine_step,
        conversion_type: :enhanced,
        migration_context: %{migration_type: :state_machine}
      }

      assert {:ok, result} = ConvertStepAction.run(params, %{})

      # State machine should be enhanced for event handling
      converted_step = result.converted_step
      assert converted_step.type == :enhanced_reactor_step
      assert :context_management in converted_step.reactor_features

      # Should preserve state machine metadata
      migration_context = result.conversion_metadata.migration_context
      assert Map.get(migration_context, :migration_type) == :state_machine
    end

    test "handles event-driven workflows" do
      # Test event-driven workflow migration
      event_driven_step = %{
        name: :event_processor,
        action: :handle_workflow_events,
        type: :event_handling,
        events: [:workflow_started, :component_completed, :error_occurred],
        event_handlers: %{
          workflow_started: :initialize_processing,
          component_completed: :continue_workflow,
          error_occurred: :handle_error
        }
      }

      params = %{
        step_specification: event_driven_step,
        conversion_type: :safe,
        validation_config: %{enable_rollback: true}
      }

      assert {:ok, result} = ConvertStepAction.run(params, %{})

      # Event-driven steps should have comprehensive safety
      converted_step = result.converted_step
      assert converted_step.type == :safe_reactor_step
      assert converted_step.rollback_capability == true
      assert converted_step.validation_comprehensive == true
    end
  end

  describe "workflow builder with Reactor patterns (1.2.9)" do
    test "creates workflows using enhanced builder" do
      workflow_spec = %{
        type: :sequential_processing,
        components: [
          %{name: :initialize, action: :setup_workflow},
          %{name: :process, action: :execute_main_logic},
          %{name: :finalize, action: :cleanup_workflow}
        ]
      }

      builder_config = %{
        preferred_mode: :hybrid,
        enable_reactor_builder: true,
        enable_validation: true
      }

      assert {:ok, result} =
               EnhancedWorkflowBuilder.create_workflow(
                 workflow_spec,
                 builder_config
               )

      # Validate workflow creation
      workflow = result.workflow
      assert Map.has_key?(workflow, :id)
      assert Map.has_key?(workflow, :type)
      assert Map.has_key?(workflow, :components)

      # Validate build metadata
      build_metadata = result.build_metadata
      assert Map.has_key?(build_metadata, :builder_mode)
      assert build_metadata.builder_mode in [:reactor, :template, :composition, :hybrid]
      assert is_integer(build_metadata.build_time_microseconds)
    end

    test "creates execution context with comprehensive utilities" do
      test_workflow = %{
        id: "test_workflow_context",
        type: :test_workflow,
        components: []
      }

      context_config = %{
        enable_monitoring: true,
        enable_error_handling: true,
        enable_performance_tracking: true
      }

      assert {:ok, execution_context} =
               EnhancedWorkflowBuilder.create_execution_context(
                 test_workflow,
                 context_config
               )

      # Validate execution context structure
      assert execution_context.workflow_id == "test_workflow_context"
      assert Map.has_key?(execution_context, :execution_config)
      assert Map.has_key?(execution_context, :monitoring)
      assert Map.has_key?(execution_context, :error_handling)
      assert Map.has_key?(execution_context, :performance)

      # Validate context components are properly initialized
      assert execution_context.monitoring.metrics_enabled == true
      assert execution_context.error_handling.error_detection_enabled == true
      assert execution_context.performance.track_execution_time == true
    end

    test "validates workflows with comprehensive validation" do
      test_workflow = %{
        id: "validation_test_workflow",
        type: :complex_workflow,
        components: [
          %{name: :step1, action: :action1},
          %{name: :step2, action: :action2, depends_on: [:step1]},
          %{name: :step3, action: :action3, depends_on: [:step1, :step2]}
        ]
      }

      validation_config = %{
        validate_structure: true,
        validate_dependencies: true,
        validate_performance: true,
        validate_resources: true
      }

      assert {:ok, validation_result} =
               EnhancedWorkflowBuilder.validate_workflow(
                 test_workflow,
                 validation_config
               )

      # Validate validation results
      assert Map.has_key?(validation_result, :validation_passed)
      assert Map.has_key?(validation_result, :validation_score)
      assert is_list(validation_result.recommendations)

      # Should pass basic validation for well-structured workflow
      assert validation_result.validation_passed == true
      assert validation_result.validation_score > 0.0
    end

    test "handles different builder modes appropriately" do
      # Test different builder modes
      builder_modes = [:reactor, :template, :composition, :hybrid]

      workflow_spec = %{
        type: :test_workflow,
        components: [%{name: :test_component, action: :test_action}]
      }

      Enum.each(builder_modes, fn mode ->
        builder_config = %{
          preferred_mode: mode,
          enable_reactor_builder: true
        }

        case EnhancedWorkflowBuilder.create_workflow(workflow_spec, builder_config) do
          {:ok, result} ->
            # Should use requested mode or appropriate fallback
            used_mode = result.build_metadata.builder_mode
            assert used_mode in builder_modes

            # Reactor mode should use reactor integration when available
            if mode == :reactor and used_mode == :reactor do
              assert Map.get(result.workflow, :reactor_integration, false) == true
            end

            # Template mode should use template system
            if mode == :template and used_mode == :template do
              assert Map.has_key?(result.workflow, :template_used)
            end

            # Composition mode should use Skills composition
            if mode == :composition and used_mode == :composition do
              assert Map.get(result.workflow, :skills_composed, false) == true
            end

          {:error, reason} ->
            # Some modes might fail gracefully - should provide meaningful error
            assert is_map(reason) or is_atom(reason)
        end
      end)
    end
  end

  describe "comprehensive workflow migration integration" do
    test "integrates all migration capabilities end-to-end" do
      # Test complete migration workflow

      # Step 1: Define complex workflow for migration
      complex_workflow_spec = %{
        type: :complex_migration_test,
        components: [
          %{name: :init_component, action: :initialize, type: :setup},
          %{name: :rule_component, action: :evaluate_rules, type: :conditional},
          %{name: :state_component, action: :manage_state, type: :state_machine},
          %{name: :process_component, action: :process_data, type: :processing}
        ],
        has_dependencies: true,
        requires_coordination: true
      }

      # Step 2: Create workflow using enhanced builder
      assert {:ok, builder_result} =
               EnhancedWorkflowBuilder.create_workflow(
                 complex_workflow_spec,
                 %{preferred_mode: :hybrid, enable_validation: true}
               )

      workflow = builder_result.workflow

      # Step 3: Convert individual components
      conversion_results =
        Enum.map(complex_workflow_spec.components, fn component ->
          params = %{
            step_specification: component,
            conversion_type: :enhanced
          }

          ConvertStepAction.run(params, %{})
        end)

      # Step 4: Validate all conversions succeeded
      successful_conversions = Enum.count(conversion_results, &match?({:ok, _}, &1))
      assert successful_conversions == length(complex_workflow_spec.components)

      # Step 5: Create execution context
      assert {:ok, execution_context} =
               EnhancedWorkflowBuilder.create_execution_context(
                 workflow,
                 %{enable_monitoring: true}
               )

      # Validate end-to-end integration
      assert is_binary(workflow.id)
      assert workflow.validation_applied == true
      assert execution_context.monitoring.metrics_enabled == true

      # All converted components should be reactor-compatible
      Enum.each(conversion_results, fn {:ok, result} ->
        assert result.converted_step.reactor_compatible == true
      end)
    end

    test "validates migration performance under load" do
      # Test migration performance under concurrent load
      concurrent_conversions =
        Enum.map(1..5, fn i ->
          Task.async(fn ->
            step_spec = %{
              name: String.to_atom("concurrent_step_#{i}"),
              action: String.to_atom("concurrent_action_#{i}"),
              type: :processing
            }

            params = %{
              step_specification: step_spec,
              conversion_type: :direct
            }

            ConvertStepAction.run(params, %{})
          end)
        end)

      results = Task.await_many(concurrent_conversions, 10_000)

      # All conversions should succeed
      Enum.each(results, fn result ->
        assert match?({:ok, _}, result)
      end)

      # Validate conversion performance
      conversion_times =
        Enum.map(results, fn {:ok, result} ->
          result.conversion_metadata.conversion_time_microseconds
        end)

      avg_conversion_time = Enum.sum(conversion_times) / length(conversion_times)

      # Average conversion time should be under 10ms
      assert avg_conversion_time < 10_000
    end

    test "validates migration safety and rollback capabilities" do
      # Test migration safety features
      risky_step = %{
        name: :risky_operation,
        action: :potentially_unsafe_operation,
        type: :high_risk,
        safety_concerns: [:data_corruption, :resource_exhaustion]
      }

      params = %{
        step_specification: risky_step,
        conversion_type: :safe,
        validation_config: %{
          validate_safety: true,
          enable_rollback: true
        }
      }

      assert {:ok, result} = ConvertStepAction.run(params, %{})

      # Risky operations should have comprehensive safety measures
      converted_step = result.converted_step
      assert converted_step.type == :safe_reactor_step
      assert converted_step.rollback_capability == true
      assert :comprehensive_testing in converted_step.safety_measures

      # Validation should pass with safety measures
      validation_results = result.conversion_metadata.validation_results
      assert validation_results.validation_passed == true
    end

    test "handles migration errors gracefully" do
      # Test error handling in migration
      invalid_step = %{
        name: :invalid_step
        # Missing required action field
      }

      params = %{
        step_specification: invalid_step,
        conversion_type: :direct
      }

      case ConvertStepAction.run(params, %{}) do
        {:ok, result} ->
          # If successful, should handle gracefully
          assert is_map(result)

        {:error, reason} ->
          # Should provide meaningful error for invalid specifications
          assert match?({:invalid_step_specification, _}, reason)
      end
    end
  end

  describe "performance and reliability validation" do
    test "builder creation completes within time constraints" do
      # Test builder performance
      large_workflow_spec = %{
        type: :large_workflow,
        components:
          Enum.map(1..50, fn i ->
            %{name: String.to_atom("component_#{i}"), action: String.to_atom("action_#{i}")}
          end)
      }

      start_time = System.monotonic_time(:microsecond)

      builder_config = %{
        preferred_mode: :hybrid,
        max_build_time_ms: 10_000
      }

      assert {:ok, result} =
               EnhancedWorkflowBuilder.create_workflow(
                 large_workflow_spec,
                 builder_config
               )

      end_time = System.monotonic_time(:microsecond)
      total_build_time = end_time - start_time

      # Should complete within 10 seconds even for large workflows
      assert total_build_time < 10_000_000

      # Recorded build time should be accurate
      recorded_time = result.build_metadata.build_time_microseconds
      assert recorded_time > 0
      # Allow measurement variance
      assert recorded_time <= total_build_time + 5000
    end

    test "maintains high success rate across different workflow types" do
      # Test builder reliability across different workflow types
      workflow_types = [
        :sequential_processing,
        :parallel_execution,
        :orchestrator_workers,
        :error_recovery,
        :custom_workflow
      ]

      build_results =
        Enum.map(workflow_types, fn workflow_type ->
          workflow_spec = %{
            type: workflow_type,
            components: [
              %{name: :component_1, action: :action_1},
              %{name: :component_2, action: :action_2}
            ]
          }

          builder_config = %{preferred_mode: :hybrid}

          EnhancedWorkflowBuilder.create_workflow(workflow_spec, builder_config)
        end)

      successful_builds = Enum.count(build_results, &match?({:ok, _}, &1))
      success_rate = successful_builds / length(workflow_types)

      # Should achieve high success rate
      # 80% success rate
      assert success_rate >= 0.8
      # At least 4/5 successful
      assert successful_builds >= 4
    end

    test "validates system integration and compatibility" do
      # Test integration with existing workflow systems
      integration_workflow_spec = %{
        type: :integration_test,
        components: [
          %{name: :template_component, source: :workflow_templates},
          %{name: :composition_component, source: :skills_composition},
          %{name: :dynamic_component, source: :dynamic_composer}
        ],
        integration_points: [:templates, :composition, :dynamic]
      }

      builder_config = %{
        preferred_mode: :hybrid,
        enable_optimization: true,
        enable_validation: true
      }

      assert {:ok, result} =
               EnhancedWorkflowBuilder.create_workflow(
                 integration_workflow_spec,
                 builder_config
               )

      # Should successfully integrate with existing systems
      workflow = result.workflow
      build_metadata = result.build_metadata

      # Should use appropriate builder mode
      assert build_metadata.builder_mode in [:template, :composition, :hybrid]

      # Should have validation results
      assert Map.has_key?(build_metadata, :validation_results)
      validation_results = build_metadata.validation_results
      assert validation_results.validation_passed == true
    end
  end
end
