defmodule RubberDuck.Workflows.Actions.ConvertAgentActionTest do
  @moduledoc """
  Comprehensive tests for ConvertAgentAction module.

  Tests all agent action conversion functionality including validation,
  conversion strategies, workflow step creation, and performance monitoring.
  """

  use ExUnit.Case, async: true

  alias RubberDuck.Workflows.Actions.ConvertAgentAction

  @moduletag :unit
  @moduletag :workflows
  @moduletag :actions

  # Mock action module for testing
  defmodule MockAgentAction do
    use Jido.Action,
      name: "mock_agent_action",
      schema: [
        input: [type: :string, required: true, doc: "Test input"],
        config: [type: :map, default: %{}, doc: "Test configuration"]
      ]

    def run(%{input: input, config: config}, _context) do
      {:ok, %{output: "Processed: #{input}", config: config}}
    end
  end

  describe "agent action conversion with direct type" do
    test "converts valid agent action to workflow step" do
      params = %{
        agent_action: MockAgentAction,
        conversion_type: :direct,
        validation_mode: :standard
      }

      assert {:ok, result} = ConvertAgentAction.run(params, %{})

      # Validate conversion result structure
      assert Map.has_key?(result, :workflow_step)
      assert Map.has_key?(result, :original_action)
      assert Map.has_key?(result, :conversion_strategy)
      assert Map.has_key?(result, :validation_result)
      assert Map.has_key?(result, :conversion_metadata)

      # Validate workflow step
      workflow_step = result.workflow_step
      assert Map.has_key?(workflow_step, :name)
      assert Map.has_key?(workflow_step, :action)
      assert Map.has_key?(workflow_step, :type)
      assert workflow_step.conversion_type == :direct
      assert workflow_step.original_action == MockAgentAction

      # Validate conversion metadata
      metadata = result.conversion_metadata
      assert metadata.conversion_type == :direct
      assert metadata.validation_mode == :standard
      assert is_integer(metadata.conversion_time_microseconds)
    end

    test "validates conversion result successfully" do
      params = %{
        agent_action: MockAgentAction,
        conversion_type: :enhanced,
        validation_mode: :strict,
        conversion_config: %{
          preserve_error_handling: true,
          enable_performance_tracking: true
        }
      }

      assert {:ok, result} = ConvertAgentAction.run(params, %{})

      validation_result = result.validation_result
      assert validation_result.validation_passed == true
      assert validation_result.validation_score > 0.0
      assert is_list(validation_result.recommendations)
    end

    test "handles different conversion types" do
      conversion_types = [:direct, :enhanced, :composed, :monitored]

      Enum.each(conversion_types, fn conversion_type ->
        params = %{
          agent_action: MockAgentAction,
          conversion_type: conversion_type,
          validation_mode: :permissive
        }

        assert {:ok, result} = ConvertAgentAction.run(params, %{})
        assert result.workflow_step.conversion_type == conversion_type
        assert result.conversion_strategy.type == conversion_type
      end)
    end

    test "applies conversion configuration correctly" do
      custom_config = %{
        preserve_error_handling: false,
        enable_performance_tracking: true,
        maintain_action_semantics: false,
        add_workflow_metadata: true
      }

      params = %{
        agent_action: MockAgentAction,
        conversion_type: :monitored,
        conversion_config: custom_config,
        validation_mode: :standard
      }

      assert {:ok, result} = ConvertAgentAction.run(params, %{})

      # Check that configuration was applied
      applied_config = result.conversion_metadata.config_applied
      assert applied_config.preserve_error_handling == false
      assert applied_config.enable_performance_tracking == true
      assert applied_config.maintain_action_semantics == false
      assert applied_config.add_workflow_metadata == true
    end
  end

  describe "validation modes" do
    test "strict validation mode performs comprehensive checks" do
      params = %{
        agent_action: MockAgentAction,
        conversion_type: :direct,
        validation_mode: :strict
      }

      assert {:ok, result} = ConvertAgentAction.run(params, %{})

      original_action = result.original_action
      assert original_action.validation_level == :strict
      assert original_action.compliance_score == 1.0
      assert Map.has_key?(original_action, :validation_results)
    end

    test "standard validation mode checks basic requirements" do
      params = %{
        agent_action: MockAgentAction,
        conversion_type: :direct,
        validation_mode: :standard
      }

      assert {:ok, result} = ConvertAgentAction.run(params, %{})

      original_action = result.original_action
      assert original_action.validation_level == :standard
      assert original_action.compliance_score == 0.8
      assert original_action.has_run_function == true
    end

    test "permissive validation mode allows basic modules" do
      params = %{
        agent_action: MockAgentAction,
        conversion_type: :direct,
        validation_mode: :permissive
      }

      assert {:ok, result} = ConvertAgentAction.run(params, %{})

      original_action = result.original_action
      assert original_action.validation_level == :permissive
      assert original_action.compliance_score == 0.6
      assert original_action.basic_requirements_met == true
    end

    test "rejects invalid validation mode" do
      params = %{
        agent_action: MockAgentAction,
        conversion_type: :direct,
        validation_mode: :invalid_mode
      }

      assert {:error, {:invalid_validation_mode, :invalid_mode}} =
               ConvertAgentAction.run(params, %{})
    end
  end

  describe "conversion strategies" do
    test "direct conversion creates simple workflow step" do
      params = %{
        agent_action: MockAgentAction,
        conversion_type: :direct
      }

      assert {:ok, result} = ConvertAgentAction.run(params, %{})

      workflow_step = result.workflow_step
      assert workflow_step.type == :agent_action_step
      assert workflow_step.conversion_type == :direct
      assert is_list(workflow_step.workflow_features)
    end

    test "enhanced conversion adds workflow capabilities" do
      params = %{
        agent_action: MockAgentAction,
        conversion_type: :enhanced
      }

      assert {:ok, result} = ConvertAgentAction.run(params, %{})

      workflow_step = result.workflow_step
      assert workflow_step.type == :enhanced_agent_action_step
      assert Map.has_key?(workflow_step, :enhancements)
      assert is_list(workflow_step.enhancements)
      assert :performance_monitoring in workflow_step.enhancements
    end

    test "composed conversion enables coordination" do
      params = %{
        agent_action: MockAgentAction,
        conversion_type: :composed,
        workflow_context: %{
          requires_coordination: true,
          multi_step_operation: true
        }
      }

      assert {:ok, result} = ConvertAgentAction.run(params, %{})

      workflow_step = result.workflow_step
      assert workflow_step.type == :composed_agent_action_step
      assert workflow_step.dependency_management == true
      assert workflow_step.sequencing_enabled == true
      assert Map.has_key?(workflow_step, :composition_pattern)
    end

    test "monitored conversion includes comprehensive analytics" do
      params = %{
        agent_action: MockAgentAction,
        conversion_type: :monitored
      }

      assert {:ok, result} = ConvertAgentAction.run(params, %{})

      workflow_step = result.workflow_step
      assert workflow_step.type == :monitored_agent_action_step
      assert Map.has_key?(workflow_step, :monitoring_config)

      monitoring_config = workflow_step.monitoring_config
      assert monitoring_config.track_performance == true
      assert monitoring_config.collect_analytics == true
      assert monitoring_config.enable_health_checks == true
    end
  end

  describe "error handling and edge cases" do
    test "handles non-existent agent action" do
      params = %{
        agent_action: NonExistentAction,
        conversion_type: :direct
      }

      assert {:error, {:action_not_loadable, NonExistentAction, _reason}} =
               ConvertAgentAction.run(params, %{})
    end

    test "handles invalid conversion type" do
      params = %{
        agent_action: MockAgentAction,
        conversion_type: :invalid_type
      }

      assert {:error, {:unsupported_conversion_type, :invalid_type}} =
               ConvertAgentAction.run(params, %{})
    end

    test "handles workflow context correctly" do
      workflow_context = %{
        requires_coordination: true,
        performance_critical: true,
        error_recovery_needed: true
      }

      params = %{
        agent_action: MockAgentAction,
        conversion_type: :composed,
        workflow_context: workflow_context
      }

      assert {:ok, result} = ConvertAgentAction.run(params, %{})

      # Context should be preserved in metadata
      step_metadata = result.workflow_step.metadata
      assert step_metadata.workflow_context == workflow_context
    end

    test "generates meaningful step names" do
      params = %{
        agent_action: MockAgentAction,
        conversion_type: :enhanced
      }

      assert {:ok, result} = ConvertAgentAction.run(params, %{})

      step_name = result.workflow_step.name
      assert is_atom(step_name)

      # Should contain action name and conversion type
      step_name_string = to_string(step_name)
      assert String.contains?(step_name_string, "mock_agent")
      assert String.contains?(step_name_string, "enhanced")
    end
  end

  describe "performance and reliability" do
    test "conversion completes within reasonable time" do
      params = %{
        agent_action: MockAgentAction,
        conversion_type: :monitored
      }

      start_time = System.monotonic_time(:microsecond)

      assert {:ok, result} = ConvertAgentAction.run(params, %{})

      end_time = System.monotonic_time(:microsecond)
      total_duration = end_time - start_time

      # Should complete within 50ms
      assert total_duration < 50_000

      # Recorded time should be reasonable
      recorded_time = result.conversion_metadata.conversion_time_microseconds
      assert recorded_time > 0
      # Allow small measurement variance
      assert recorded_time < total_duration + 1000
    end

    test "handles concurrent conversions safely" do
      # Test concurrent agent action conversions
      tasks =
        Enum.map(1..5, fn i ->
          Task.async(fn ->
            params = %{
              agent_action: MockAgentAction,
              conversion_type: Enum.random([:direct, :enhanced, :composed, :monitored]),
              validation_mode: Enum.random([:strict, :standard, :permissive])
            }

            ConvertAgentAction.run(params, %{})
          end)
        end)

      results = Task.await_many(tasks, 10_000)

      # All conversions should succeed
      Enum.each(results, fn result ->
        assert match?({:ok, _}, result)
      end)

      # Each should have unique workflow step names
      step_names =
        Enum.map(results, fn {:ok, result} ->
          result.workflow_step.name
        end)

      unique_names = Enum.uniq(step_names)
      assert length(unique_names) == length(step_names)
    end

    test "validates conversion results thoroughly" do
      params = %{
        agent_action: MockAgentAction,
        conversion_type: :enhanced,
        conversion_config: %{validate_compatibility: true}
      }

      assert {:ok, result} = ConvertAgentAction.run(params, %{})

      validation_result = result.validation_result
      assert is_map(validation_result)
      assert Map.has_key?(validation_result, :validation_passed)
      assert Map.has_key?(validation_result, :validation_score)
      assert Map.has_key?(validation_result, :validation_details)
      assert Map.has_key?(validation_result, :recommendations)

      # Validation score should be reasonable
      assert validation_result.validation_score >= 0.0
      assert validation_result.validation_score <= 1.0

      # Recommendations should be helpful
      assert is_list(validation_result.recommendations)
      assert length(validation_result.recommendations) > 0
    end
  end
end
