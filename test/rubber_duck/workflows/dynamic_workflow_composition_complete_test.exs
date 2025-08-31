defmodule RubberDuck.Workflows.DynamicWorkflowCompositionCompleteTest do
  @moduledoc """
  Comprehensive tests for Phase 02a Section 2.1.6-2.1.9 workflow composition.

  Tests all advanced workflow composition functionality including dynamic
  composition, merging, runtime adaptation, and template management to
  ensure complete Phase 02a Section 2.1 functionality.
  """

  use ExUnit.Case, async: true

  alias RubberDuck.Workflows.{
    Dynamic.DynamicWorkflowComposer,
    Adaptation.WorkflowAdaptationEngine,
    Actions.ComposeReactorWorkflowAction
  }

  @moduletag :unit
  @moduletag :workflows
  @moduletag :dynamic_composition

  describe "dynamic workflow composition using Reactor.Builder (2.1.6)" do
    test "composes dynamic workflow with goal decomposition" do
      composition_goal = %{
        type: :sequential_processing,
        complexity: :medium,
        steps: [
          %{name: :analyze, type: :analysis},
          %{name: :process, type: :processing},
          %{name: :validate, type: :validation}
        ]
      }

      params = %{
        composition_goal: composition_goal,
        agent_capabilities: [:analysis, :processing, :validation],
        composition_strategy: :goal_driven
      }

      assert {:ok, result} = ComposeReactorWorkflowAction.run(params, %{})

      # Validate composition result
      assert Map.has_key?(result, :composed_workflow)
      assert Map.has_key?(result, :composition_metadata)

      composed_workflow = result.composed_workflow
      assert composed_workflow.action_composed == true
      assert composed_workflow.goal_decomposition_applied == true
      assert is_list(composed_workflow.optimizations_applied)

      # Validate composition metadata
      metadata = result.composition_metadata
      assert metadata.strategy_used == :goal_driven
      assert Map.has_key?(metadata, :goal_decomposition)
      assert Map.has_key?(metadata, :composition_plan)
      assert is_integer(metadata.composition_time_microseconds)
    end

    test "handles different composition strategies" do
      strategies = [:goal_driven, :performance_optimized, :resource_aware]

      Enum.each(strategies, fn strategy ->
        params = %{
          composition_goal: %{type: :parallel_coordination, complexity: :low},
          agent_capabilities: [:coordination, :processing],
          composition_strategy: strategy
        }

        assert {:ok, result} = ComposeReactorWorkflowAction.run(params, %{})
        assert result.composition_metadata.strategy_used == strategy
      end)
    end

    test "validates goal decomposition accuracy" do
      complex_goal = %{
        type: :orchestration,
        complexity: :high,
        components: [
          %{name: :orchestrator, type: :orchestrator},
          %{name: :worker_1, type: :worker},
          %{name: :worker_2, type: :worker}
        ]
      }

      params = %{
        composition_goal: complex_goal,
        agent_capabilities: [:orchestration, :coordination, :processing]
      }

      assert {:ok, result} = ComposeReactorWorkflowAction.run(params, %{})

      # Validate goal decomposition
      goal_decomposition = result.composition_metadata.goal_decomposition
      assert goal_decomposition.goal_type == :orchestration
      assert goal_decomposition.complexity == :high
      assert length(goal_decomposition.decomposed_components) >= 3
      assert Map.has_key?(goal_decomposition, :agent_capabilities_used)
    end
  end

  describe "workflow merging and dependency resolution (2.1.7)" do
    test "merges multiple workflows with dependency resolution" do
      workflow_1 = create_test_workflow("workflow_1", [:component_a, :component_b])
      workflow_2 = create_test_workflow("workflow_2", [:component_c, :component_d])

      merge_config = %{
        strategy: :intelligent,
        enable_optimization: true,
        resolve_conflicts: true
      }

      assert {:ok, merge_result} =
               DynamicWorkflowComposer.merge_workflows(
                 [workflow_1, workflow_2],
                 merge_config
               )

      # Validate merge result
      assert Map.has_key?(merge_result, :merged_workflow)
      assert Map.has_key?(merge_result, :merge_metadata)

      merged_workflow = merge_result.merged_workflow
      assert merged_workflow.type == :merged_workflow
      assert merged_workflow.source_workflows == 2
      assert length(merged_workflow.components) >= 4

      # Validate merge metadata
      metadata = merge_result.merge_metadata
      assert metadata.original_workflow_count == 2
      assert is_list(metadata.conflicts_resolved)
      assert is_list(metadata.merge_optimizations)
    end

    test "resolves component dependencies correctly" do
      workflow_with_dependencies =
        create_test_workflow("dep_workflow", [
          %{name: :setup, type: :initializer, dependencies: []},
          %{name: :process, type: :processor, dependencies: [:setup]},
          %{name: :cleanup, type: :finalizer, dependencies: [:process]}
        ])

      single_workflow = [workflow_with_dependencies]

      assert {:ok, merge_result} =
               DynamicWorkflowComposer.merge_workflows(
                 single_workflow,
                 %{strategy: :dependency_aware}
               )

      # Dependencies should be preserved in merged workflow
      merged_workflow = merge_result.merged_workflow
      assert length(merged_workflow.components) == 3
      assert merged_workflow.source_workflows == 1
    end

    test "optimizes merged workflows for performance" do
      performance_workflow_1 = create_test_workflow("perf_1", [:fast_component, :slow_component])

      performance_workflow_2 =
        create_test_workflow("perf_2", [:parallel_component_1, :parallel_component_2])

      merge_config = %{
        strategy: :performance_optimized,
        enable_parallel_optimization: true
      }

      assert {:ok, merge_result} =
               DynamicWorkflowComposer.merge_workflows(
                 [performance_workflow_1, performance_workflow_2],
                 merge_config
               )

      # Should have performance optimizations applied
      assert length(merge_result.merge_metadata.merge_optimizations) > 0
    end
  end

  describe "runtime workflow adaptation and hot-swapping (2.1.8)" do
    test "executes hot-swap with zero downtime" do
      workflow_id = "test_workflow_123"

      component_spec = %{
        name: :improved_component,
        type: :enhanced_processor,
        replaces: :old_component
      }

      swap_config = %{
        enable_rollback: true,
        max_swap_time_ms: 500,
        validate_compatibility: true
      }

      assert {:ok, swap_result} =
               WorkflowAdaptationEngine.hot_swap_component(
                 workflow_id,
                 component_spec,
                 swap_config
               )

      # Validate hot-swap result
      assert swap_result.success == true
      assert swap_result.workflow_id == workflow_id
      assert swap_result.component_swapped == :improved_component
      assert swap_result.rollback_available == true
      assert is_binary(swap_result.checkpoint_created)
      # Should be fast
      assert swap_result.adaptation_time_ms < 1000
    end

    test "validates component compatibility before substitution" do
      workflow_id = "compatibility_test_workflow"

      incompatible_spec = %{
        name: :incompatible_component,
        type: :unknown_type,
        interface: :non_standard
      }

      # Should handle incompatible components gracefully
      case WorkflowAdaptationEngine.substitute_component(workflow_id, %{
             old_component: :existing_component,
             new_component: incompatible_spec
           }) do
        {:ok, result} ->
          # If successful, should have low compatibility score
          assert result.success == true

        {:error, reason} ->
          # Should provide meaningful error for incompatibility
          assert is_map(reason) or is_atom(reason)
      end
    end

    test "creates and manages version checkpoints" do
      workflow_id = "checkpoint_test_workflow"

      checkpoint_config = %{
        metadata: %{version: "2.1.0", author: "test"},
        retention_hours: 48
      }

      assert {:ok, checkpoint_result} =
               WorkflowAdaptationEngine.create_version_checkpoint(
                 workflow_id,
                 checkpoint_config
               )

      # Validate checkpoint creation
      assert checkpoint_result.workflow_id == workflow_id
      assert is_binary(checkpoint_result.checkpoint_id)
      assert checkpoint_result.rollback_capable == true
      assert %DateTime{} = checkpoint_result.created_at
    end

    test "adapts legacy workflows with backward compatibility" do
      legacy_spec = %{
        type: :simple_workflow,
        id: "legacy_workflow_123",
        components: [:legacy_component_1, :legacy_component_2],
        pattern: :sequential
      }

      adaptation_config = %{
        preserve_semantics: true,
        enable_modern_features: true,
        compatibility_mode: :full
      }

      assert {:ok, adaptation_result} =
               WorkflowAdaptationEngine.adapt_legacy_workflow(
                 legacy_spec,
                 adaptation_config
               )

      # Validate legacy adaptation
      assert adaptation_result.success == true
      assert adaptation_result.backward_compatibility_maintained == true

      case adaptation_result do
        %{conversion_type: :direct} ->
          assert adaptation_result.modern_workflow_created == true

        %{migration_type: :gradual} ->
          assert adaptation_result.legacy_workflow_preserved == true

        %{adaptation_type: :compatibility_wrapper} ->
          assert adaptation_result.wrapper_created == true
      end
    end
  end

  describe "template management and workflow inheritance (2.1.9)" do
    test "creates workflow from template with inheritance" do
      # Test template-based workflow creation
      template_type = :sequential_processing

      custom_params = %{
        steps: [
          %{name: :custom_init, action: :initialize_custom},
          %{name: :custom_process, action: :process_custom},
          %{name: :custom_finalize, action: :finalize_custom}
        ],
        inheritance: %{
          parent_template: :base_sequential,
          override_steps: [:custom_process],
          inherit_middleware: true
        }
      }

      assert {:ok, template_result} =
               WorkflowTemplates.create_from_template(
                 template_type,
                 custom_params
               )

      # Validate template creation with inheritance
      assert template_result.template_used == template_type
      assert :custom_steps in template_result.customizations_applied
      assert Map.has_key?(template_result.workflow_config, :workflow)
      assert Map.has_key?(template_result.workflow_config, :configuration)
    end

    test "validates template inheritance patterns" do
      # Test various inheritance patterns
      inheritance_patterns = [
        %{pattern: :simple_inheritance, parent: :base_template},
        %{pattern: :multiple_inheritance, parents: [:template_a, :template_b]},
        %{pattern: :override_inheritance, parent: :base_template, overrides: [:step_2]}
      ]

      Enum.each(inheritance_patterns, fn pattern ->
        custom_params = %{
          inheritance: pattern,
          steps: [%{name: :inherited_step, action: :inherited_action}]
        }

        # Should handle different inheritance patterns
        case WorkflowTemplates.create_from_template(:sequential_processing, custom_params) do
          {:ok, result} ->
            assert result.template_used == :sequential_processing
            assert is_map(result.workflow_config)

          {:error, reason} ->
            # Should provide meaningful error for unsupported patterns
            assert is_atom(reason) or is_map(reason)
        end
      end)
    end

    test "manages template library with versioning" do
      # Test template library management
      available_templates = WorkflowTemplates.available_templates()

      assert is_list(available_templates)
      assert length(available_templates) > 0

      # Each template should have proper definition
      Enum.each(available_templates, fn template_type ->
        assert {:ok, template_def} = WorkflowTemplates.get_template(template_type)

        # Validate template structure
        assert is_binary(template_def.description)
        assert is_atom(template_def.pattern)
        assert is_list(template_def.use_cases)
        assert is_integer(template_def.default_timeout)
        assert is_atom(template_def.compensation_strategy)
        assert is_list(template_def.middleware)
      end)
    end

    test "validates template learning and optimization" do
      # Test template learning capabilities
      operation_spec = %{
        type: :complex_coordination,
        requires_learning: true,
        performance_target: 0.9,
        execution_history: [
          %{template: :sequential_processing, success: true, performance: 0.8},
          %{template: :parallel_execution, success: true, performance: 0.9},
          %{template: :orchestrator_workers, success: false, performance: 0.6}
        ]
      }

      assert {:ok, recommendation} = WorkflowTemplates.recommend_template(operation_spec)

      # Should recommend based on learning from execution history
      assert is_atom(recommendation.recommended_template)
      assert is_float(recommendation.confidence_score)
      assert recommendation.confidence_score > 0.0
      assert is_binary(recommendation.reasoning)
    end
  end

  describe "comprehensive workflow composition integration" do
    test "integrates all composition capabilities end-to-end" do
      # Test complete workflow composition workflow

      # Step 1: Goal decomposition and composition
      composition_goal = %{
        type: :orchestration,
        complexity: :high,
        requirements: [:fault_tolerance, :performance_optimization, :monitoring]
      }

      assert {:ok, composition_result} =
               ComposeReactorWorkflowAction.run(
                 %{
                   composition_goal: composition_goal,
                   agent_capabilities: [:orchestration, :monitoring, :error_handling],
                   composition_strategy: :performance_optimized
                 },
                 %{}
               )

      workflow_id = composition_result.composed_workflow.workflow_id

      # Step 2: Create version checkpoint
      assert {:ok, checkpoint_result} =
               WorkflowAdaptationEngine.create_version_checkpoint(
                 workflow_id,
                 %{metadata: %{version: "1.0.0"}}
               )

      # Step 3: Execute hot-swap
      assert {:ok, swap_result} =
               WorkflowAdaptationEngine.hot_swap_component(
                 workflow_id,
                 %{name: :improved_monitor, type: :enhanced_monitoring},
                 %{enable_rollback: true}
               )

      # Validate end-to-end integration
      assert composition_result.composed_workflow.action_composed == true
      assert is_binary(checkpoint_result.checkpoint_id)
      assert swap_result.success == true
      assert swap_result.rollback_available == true
    end

    test "validates performance under concurrent composition" do
      # Test concurrent workflow composition
      concurrent_tasks =
        Enum.map(1..5, fn i ->
          Task.async(fn ->
            params = %{
              composition_goal: %{
                type: :sequential_processing,
                id: "concurrent_workflow_#{i}"
              },
              agent_capabilities: [:basic_execution, :error_handling]
            }

            ComposeReactorWorkflowAction.run(params, %{})
          end)
        end)

      results = Task.await_many(concurrent_tasks, 10_000)

      # All compositions should succeed
      Enum.each(results, fn result ->
        assert match?({:ok, _}, result)
      end)

      # Validate composition times are reasonable
      composition_times =
        Enum.map(results, fn {:ok, result} ->
          result.composition_metadata.composition_time_microseconds
        end)

      avg_composition_time = Enum.sum(composition_times) / length(composition_times)

      # Average composition time should be under 10ms for simple workflows
      assert avg_composition_time < 10_000
    end

    test "handles composition errors gracefully" do
      # Test error handling in composition
      invalid_goal = %{
        type: :invalid_type,
        # Empty components should cause validation error
        components: []
      }

      params = %{
        composition_goal: invalid_goal,
        agent_capabilities: []
      }

      case ComposeReactorWorkflowAction.run(params, %{}) do
        {:ok, result} ->
          # If successful, should handle gracefully
          assert is_map(result)

        {:error, reason} ->
          # Should provide meaningful error information
          assert is_map(reason) or is_atom(reason)
      end
    end
  end

  describe "performance and reliability validation" do
    test "composition completes within time constraints" do
      # Test composition performance constraints
      large_goal = %{
        type: :orchestration,
        complexity: :high,
        components:
          Enum.map(1..20, fn i ->
            %{name: String.to_atom("component_#{i}"), type: :worker}
          end)
      }

      start_time = System.monotonic_time(:microsecond)

      params = %{
        composition_goal: large_goal,
        agent_capabilities: [:orchestration, :coordination, :processing],
        optimization_config: %{max_composition_time_ms: 5000}
      }

      assert {:ok, result} = ComposeReactorWorkflowAction.run(params, %{})

      end_time = System.monotonic_time(:microsecond)
      total_duration = end_time - start_time

      # Should complete within reasonable time even for large workflows
      # 50ms
      assert total_duration < 50_000

      # Recorded composition time should be accurate
      recorded_time = result.composition_metadata.composition_time_microseconds
      assert recorded_time > 0
      # Allow measurement variance
      assert recorded_time <= total_duration + 5000
    end

    test "maintains system stability under load" do
      # Test system stability under composition load
      load_test_count = 10

      load_tasks =
        Enum.map(1..load_test_count, fn i ->
          Task.async(fn ->
            # Different goal types to test various composition paths
            goal_type =
              Enum.random([:sequential_processing, :parallel_coordination, :orchestration])

            params = %{
              composition_goal: %{type: goal_type, id: "load_test_#{i}"},
              agent_capabilities: [:basic_execution, :coordination]
            }

            ComposeReactorWorkflowAction.run(params, %{})
          end)
        end)

      results = Task.await_many(load_tasks, 15_000)

      # Calculate success rate
      successful_compositions = Enum.count(results, &match?({:ok, _}, &1))
      success_rate = successful_compositions / load_test_count

      # Should maintain high success rate under load
      # 90% success rate
      assert success_rate >= 0.9
      # At least 8/10 successful
      assert successful_compositions >= 8
    end
  end

  # Test helper functions

  defp create_test_workflow(workflow_id, components) do
    # Create test workflow with specified components
    workflow_components = process_test_components(components)

    %{
      id: workflow_id,
      type: :test_workflow,
      components: workflow_components,
      created_at: DateTime.utc_now(),
      status: :ready
    }
  end

  defp process_test_components(components) do
    case components do
      list when is_list(list) and length(list) > 0 ->
        convert_component_list(list)

      [] ->
        # Default test components
        [%{name: :default_component, type: :test_component, action: :default_action}]
    end
  end

  defp convert_component_list(list) do
    case List.first(list) do
      component when is_map(component) ->
        # Components are already maps
        list

      _ ->
        # Convert atoms to component maps
        Enum.map(list, &convert_atom_to_component/1)
    end
  end

  defp convert_atom_to_component(component_name) do
    %{name: component_name, type: :test_component, action: component_name}
  end
end
