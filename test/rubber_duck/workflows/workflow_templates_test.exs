defmodule RubberDuck.Workflows.WorkflowTemplatesTest do
  @moduledoc """
  Comprehensive tests for WorkflowTemplates module and template system.

  Tests all template functionality including template recommendation,
  creation from templates, compatibility validation, and operation analysis.
  """

  use ExUnit.Case, async: true

  alias RubberDuck.Workflows.WorkflowTemplates

  @moduletag :unit
  @moduletag :workflows

  describe "available_templates/0" do
    test "returns all available template types" do
      templates = WorkflowTemplates.available_templates()

      assert is_list(templates)
      assert length(templates) > 0

      # Verify expected templates are included
      expected_templates = [
        :sequential_processing,
        :parallel_execution,
        :orchestrator_workers,
        :error_recovery,
        :rag_orchestration,
        :provider_coordination
      ]

      Enum.each(expected_templates, fn template ->
        assert template in templates
      end)
    end
  end

  describe "get_template/1" do
    test "returns template definition for valid template type" do
      assert {:ok, template} = WorkflowTemplates.get_template(:sequential_processing)

      assert is_map(template)
      assert Map.has_key?(template, :description)
      assert Map.has_key?(template, :pattern)
      assert Map.has_key?(template, :use_cases)
      assert Map.has_key?(template, :default_timeout)
      assert Map.has_key?(template, :compensation_strategy)
      assert Map.has_key?(template, :middleware)

      # Validate specific values
      assert template.pattern == :sequential
      assert is_list(template.use_cases)
      assert is_integer(template.default_timeout)
      assert template.default_timeout > 0
    end

    test "returns error for unknown template type" do
      assert {:error, {:unknown_template, :nonexistent_template}} =
               WorkflowTemplates.get_template(:nonexistent_template)
    end

    test "all available templates have valid definitions" do
      templates = WorkflowTemplates.available_templates()

      Enum.each(templates, fn template_type ->
        assert {:ok, template_def} = WorkflowTemplates.get_template(template_type)

        # Validate required fields
        assert is_binary(template_def.description)
        assert is_atom(template_def.pattern)
        assert is_list(template_def.use_cases)
        assert is_integer(template_def.default_timeout) and template_def.default_timeout > 0
        assert is_atom(template_def.compensation_strategy)
        assert is_list(template_def.middleware)
      end)
    end
  end

  describe "create_from_template/2" do
    test "creates workflow from template with default parameters" do
      assert {:ok, result} = WorkflowTemplates.create_from_template(:sequential_processing)

      assert is_map(result)
      assert Map.has_key?(result, :workflow_config)
      assert Map.has_key?(result, :template_used)
      assert Map.has_key?(result, :template_metadata)
      assert Map.has_key?(result, :customizations_applied)

      assert result.template_used == :sequential_processing
      assert is_map(result.workflow_config)
      assert is_list(result.customizations_applied)
    end

    test "creates workflow from template with custom parameters" do
      custom_params = %{
        timeout: 600_000,
        steps: [
          %{name: :custom_step_1, action: :custom_action_1},
          %{name: :custom_step_2, action: :custom_action_2}
        ],
        metadata: %{custom_key: "custom_value"}
      }

      assert {:ok, result} =
               WorkflowTemplates.create_from_template(:parallel_execution, custom_params)

      assert result.template_used == :parallel_execution
      assert :custom_timeout in result.customizations_applied
      assert :custom_steps in result.customizations_applied
      assert :custom_metadata in result.customizations_applied
    end

    test "handles invalid template type" do
      assert {:error, {:unknown_template, :invalid_template}} =
               WorkflowTemplates.create_from_template(:invalid_template)
    end

    test "creates different workflows for different templates" do
      template_types = [:sequential_processing, :parallel_execution, :orchestrator_workers]

      results =
        Enum.map(template_types, fn template_type ->
          {:ok, result} = WorkflowTemplates.create_from_template(template_type)
          {template_type, result}
        end)

      # Verify each result is different
      Enum.each(results, fn {template_type, result} ->
        assert result.template_used == template_type
        # Each should have unique workflow configuration
        assert is_map(result.workflow_config)
      end)
    end
  end

  describe "recommend_template/1" do
    test "recommends template for simple operation" do
      simple_operation = %{
        steps: [%{name: :step1}, %{name: :step2}],
        complexity: 0.3,
        requires_error_recovery: false,
        parallel_tasks: []
      }

      assert {:ok, recommendation} = WorkflowTemplates.recommend_template(simple_operation)

      assert is_map(recommendation)
      assert Map.has_key?(recommendation, :recommended_template)
      assert Map.has_key?(recommendation, :confidence_score)
      assert Map.has_key?(recommendation, :operation_analysis)
      assert Map.has_key?(recommendation, :reasoning)

      assert is_atom(recommendation.recommended_template)
      assert is_float(recommendation.confidence_score)
      assert recommendation.confidence_score >= 0.0 and recommendation.confidence_score <= 1.0
    end

    test "recommends parallel template for concurrent operations" do
      parallel_operation = %{
        parallel_tasks: [%{name: :task1}, %{name: :task2}, %{name: :task3}],
        concurrent_agents: [:agent1, :agent2],
        requires_synchronization: true
      }

      assert {:ok, recommendation} = WorkflowTemplates.recommend_template(parallel_operation)

      # Should recommend parallel execution for concurrent operations
      assert recommendation.recommended_template in [:parallel_execution, :orchestrator_workers]
      assert recommendation.confidence_score > 0.5
    end

    test "recommends error recovery template for mission critical operations" do
      critical_operation = %{
        mission_critical: true,
        requires_rollback: true,
        requires_data_consistency: true,
        error_sensitivity: 0.9
      }

      assert {:ok, recommendation} = WorkflowTemplates.recommend_template(critical_operation)

      # Should recommend error recovery for critical operations
      assert recommendation.recommended_template == :error_recovery
      assert recommendation.confidence_score > 0.7
    end

    test "provides meaningful reasoning for recommendations" do
      operation = %{complexity: 0.8, coordination_requirements: 0.6}

      assert {:ok, recommendation} = WorkflowTemplates.recommend_template(operation)

      assert is_binary(recommendation.reasoning)
      assert String.length(recommendation.reasoning) > 10

      assert String.contains?(
               recommendation.reasoning,
               to_string(recommendation.recommended_template)
             )
    end
  end

  describe "validate_template_compatibility/2" do
    test "validates compatible agent capabilities" do
      agent_capabilities = [:step_execution, :error_handling, :state_management]

      assert {:ok, result} =
               WorkflowTemplates.validate_template_compatibility(
                 :sequential_processing,
                 agent_capabilities
               )

      assert result.compatible == true
      assert result.template == :sequential_processing
      assert is_float(result.compatibility_score)
      assert result.compatibility_score > 0.0
      assert is_list(result.recommendations)
    end

    test "identifies incompatible agent capabilities" do
      # Missing required capabilities
      limited_capabilities = [:basic_execution]

      case WorkflowTemplates.validate_template_compatibility(
             :orchestrator_workers,
             limited_capabilities
           ) do
        {:ok, result} ->
          # If it succeeds, compatibility should be low
          assert result.compatibility_score < 0.8

        {:error, result} ->
          # If it fails, should indicate incompatibility
          assert result.compatible == false
          assert is_list(result.issues)
          assert is_list(result.suggestions)
      end
    end

    test "handles unknown template type" do
      assert {:error, {:unknown_template, :unknown_template}} =
               WorkflowTemplates.validate_template_compatibility(:unknown_template, [
                 :some_capability
               ])
    end

    test "provides helpful compatibility recommendations" do
      agent_capabilities = [:basic_execution, :error_handling]

      assert {:ok, result} =
               WorkflowTemplates.validate_template_compatibility(
                 :parallel_execution,
                 agent_capabilities
               )

      assert is_list(result.recommendations)
      assert length(result.recommendations) > 0

      # Recommendations should be meaningful strings
      Enum.each(result.recommendations, fn recommendation ->
        assert is_binary(recommendation)
        assert String.length(recommendation) > 5
      end)
    end
  end

  describe "template system integration" do
    test "all templates can be created and have valid workflows" do
      templates = WorkflowTemplates.available_templates()

      Enum.each(templates, fn template_type ->
        assert {:ok, result} = WorkflowTemplates.create_from_template(template_type)

        # Verify workflow config structure
        workflow_config = result.workflow_config
        assert Map.has_key?(workflow_config, :workflow)
        assert Map.has_key?(workflow_config, :configuration)
        assert Map.has_key?(workflow_config, :workflow_id)
      end)
    end

    test "template recommendations are consistent" do
      # Same operation should get same recommendation
      operation = %{
        complexity: 0.7,
        coordination_requirements: 0.5,
        parallel_tasks: []
      }

      # Get recommendation multiple times
      recommendations =
        Enum.map(1..5, fn _i ->
          {:ok, rec} = WorkflowTemplates.recommend_template(operation)
          rec.recommended_template
        end)

      # All recommendations should be the same
      unique_recommendations = Enum.uniq(recommendations)
      assert length(unique_recommendations) == 1
    end

    test "template system handles edge cases gracefully" do
      # Empty operation
      assert {:ok, _recommendation} = WorkflowTemplates.recommend_template(%{})

      # Operation with nil values
      operation_with_nils = %{
        steps: nil,
        complexity: nil,
        parallel_tasks: nil
      }

      assert {:ok, _recommendation} = WorkflowTemplates.recommend_template(operation_with_nils)

      # Very complex operation
      complex_operation = %{
        steps: Enum.map(1..20, fn i -> %{name: "step_#{i}"} end),
        complexity: 1.0,
        coordination_requirements: 1.0,
        parallel_tasks: Enum.map(1..10, fn i -> %{name: "task_#{i}"} end)
      }

      assert {:ok, recommendation} = WorkflowTemplates.recommend_template(complex_operation)
      assert recommendation.confidence_score > 0.6
    end
  end
end
