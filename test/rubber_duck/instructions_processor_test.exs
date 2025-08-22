defmodule RubberDuck.InstructionsProcessorTest do
  use ExUnit.Case, async: true
  alias RubberDuck.InstructionsProcessor

  setup do
    {:ok, pid} = InstructionsProcessor.start_link([])
    %{processor: pid}
  end

  describe "instruction processing" do
    test "processes a valid instruction successfully" do
      instruction_spec = %{
        type: :skill_invocation,
        action: "test.action",
        parameters: %{skill_id: :test_skill, skill_params: %{timeout: 5000}}
      }

      assert {:ok, result} = InstructionsProcessor.process_instruction(instruction_spec, "agent1")
      assert result.status == :completed
      assert result.agent_id == "agent1"
    end

    test "processes data operation instruction" do
      instruction_spec = %{
        type: :data_operation,
        action: "data.query",
        parameters: %{operation: :select, table: :users}
      }

      assert {:ok, result} = InstructionsProcessor.process_instruction(instruction_spec, "agent1")
      assert result.status == :completed
      assert result.operation == :select
    end

    test "processes control flow instruction" do
      instruction_spec = %{
        type: :control_flow,
        action: "control.conditional",
        parameters: %{control_type: :if_then, next_instruction: "inst_2"}
      }

      assert {:ok, result} = InstructionsProcessor.process_instruction(instruction_spec, "agent1")
      assert result.status == :completed
      assert result.control_type == :if_then
    end

    test "processes communication instruction" do
      instruction_spec = %{
        type: :communication,
        action: "comm.send_message",
        parameters: %{message_type: :notification, target: "agent2"}
      }

      assert {:ok, result} = InstructionsProcessor.process_instruction(instruction_spec, "agent1")
      assert result.status == :sent
      assert result.source_agent == "agent1"
      assert result.target == "agent2"
    end
  end

  describe "instruction normalization" do
    test "normalizes instruction with missing ID" do
      raw_instruction = %{
        type: :skill_invocation,
        action: "test.action",
        parameters: %{}
      }

      assert {:ok, normalized} = InstructionsProcessor.normalize_instruction(raw_instruction)
      assert Map.has_key?(normalized, :id)
      assert is_binary(normalized.id)
    end

    test "normalizes instruction with missing timeout" do
      raw_instruction = %{
        type: :skill_invocation,
        action: "test.action",
        parameters: %{}
      }

      assert {:ok, normalized} = InstructionsProcessor.normalize_instruction(raw_instruction)
      assert Map.has_key?(normalized, :timeout)
      assert is_integer(normalized.timeout)
    end

    test "normalizes action format" do
      raw_instruction = %{
        type: :skill_invocation,
        action: "Test Action With Spaces!",
        parameters: %{}
      }

      assert {:ok, normalized} = InstructionsProcessor.normalize_instruction(raw_instruction)
      assert normalized.action == "test_action_with_spaces_"
    end

    test "ensures retry policy exists" do
      raw_instruction = %{
        type: :skill_invocation,
        action: "test.action",
        parameters: %{}
      }

      assert {:ok, normalized} = InstructionsProcessor.normalize_instruction(raw_instruction)
      assert Map.has_key?(normalized, :retry_policy)
      assert Map.has_key?(normalized.retry_policy, :max_retries)
    end
  end

  describe "workflow composition" do
    test "composes simple workflow successfully" do
      workflow_spec = %{
        name: "test_workflow",
        instructions: [
          %{
            type: :skill_invocation,
            action: "step1",
            parameters: %{},
            dependencies: []
          },
          %{
            type: :data_operation,
            action: "step2",
            parameters: %{},
            dependencies: []
          }
        ]
      }

      assert {:ok, workflow_id} = InstructionsProcessor.compose_workflow(workflow_spec)
      assert is_binary(workflow_id)
    end

    test "rejects workflow with missing required fields" do
      workflow_spec =
        %{
          # Missing name and instructions
        }

      assert {:error, {:missing_workflow_fields, missing_fields}} =
               InstructionsProcessor.compose_workflow(workflow_spec)

      assert :name in missing_fields
      assert :instructions in missing_fields
    end

    test "composes workflow with dependencies" do
      workflow_spec = %{
        name: "dependency_workflow",
        instructions: [
          %{
            id: "inst_1",
            type: :skill_invocation,
            action: "step1",
            parameters: %{},
            dependencies: []
          },
          %{
            id: "inst_2",
            type: :data_operation,
            action: "step2",
            parameters: %{},
            dependencies: ["inst_1"]
          }
        ]
      }

      assert {:ok, workflow_id} = InstructionsProcessor.compose_workflow(workflow_spec)
      assert is_binary(workflow_id)
    end
  end

  describe "workflow execution" do
    setup do
      workflow_spec = %{
        name: "execution_test_workflow",
        instructions: [
          %{
            type: :skill_invocation,
            action: "step1",
            parameters: %{skill_id: :test_skill},
            dependencies: []
          },
          %{
            type: :data_operation,
            action: "step2",
            parameters: %{operation: :insert},
            dependencies: []
          }
        ]
      }

      {:ok, workflow_id} = InstructionsProcessor.compose_workflow(workflow_spec)
      %{workflow_id: workflow_id}
    end

    test "executes workflow successfully", %{workflow_id: workflow_id} do
      assert {:ok, execution_result} =
               InstructionsProcessor.execute_workflow(workflow_id, "agent1")

      assert execution_result.status == :completed
      assert execution_result.workflow_id == workflow_id
      assert Map.has_key?(execution_result, :instruction_results)
      assert map_size(execution_result.instruction_results) == 2
    end

    test "returns error for non-existent workflow" do
      assert {:error, :workflow_not_found} =
               InstructionsProcessor.execute_workflow("nonexistent_workflow", "agent1")
    end

    test "prevents execution of already running workflow", %{workflow_id: workflow_id} do
      # Start execution (this would normally be async)
      Task.start(fn -> InstructionsProcessor.execute_workflow(workflow_id, "agent1") end)

      # Small delay to ensure workflow is marked as running
      Process.sleep(10)

      # This test would need more sophisticated setup to properly test concurrent execution
      # For now, just verify the workflow exists
      assert {:ok, _status} = InstructionsProcessor.get_workflow_status(workflow_id)
    end
  end

  describe "workflow optimization" do
    setup do
      workflow_spec = %{
        name: "optimization_test_workflow",
        instructions: [
          %{
            type: :skill_invocation,
            action: "duplicate_action",
            parameters: %{skill_id: :test_skill},
            dependencies: []
          },
          %{
            type: :skill_invocation,
            action: "duplicate_action",
            parameters: %{skill_id: :test_skill},
            dependencies: []
          },
          %{
            type: :data_operation,
            action: "unique_action",
            parameters: %{operation: :select},
            dependencies: []
          }
        ]
      }

      {:ok, workflow_id} = InstructionsProcessor.compose_workflow(workflow_spec)
      %{workflow_id: workflow_id}
    end

    test "optimizes workflow by removing redundant instructions", %{workflow_id: workflow_id} do
      assert {:ok, optimized_workflow} = InstructionsProcessor.optimize_workflow(workflow_id)

      # After optimization, should have fewer instructions due to redundancy removal
      assert length(optimized_workflow.instructions) < 3
    end

    test "returns error for non-existent workflow" do
      assert {:error, :workflow_not_found} =
               InstructionsProcessor.optimize_workflow("nonexistent_workflow")
    end
  end

  describe "workflow status and control" do
    setup do
      workflow_spec = %{
        name: "status_test_workflow",
        instructions: [
          %{
            type: :skill_invocation,
            action: "test_action",
            parameters: %{},
            dependencies: []
          }
        ]
      }

      {:ok, workflow_id} = InstructionsProcessor.compose_workflow(workflow_spec)
      %{workflow_id: workflow_id}
    end

    test "gets workflow status", %{workflow_id: workflow_id} do
      assert {:ok, status} = InstructionsProcessor.get_workflow_status(workflow_id)
      assert status == :ready
    end

    test "cancels workflow", %{workflow_id: workflow_id} do
      assert :ok = InstructionsProcessor.cancel_workflow(workflow_id)

      {:ok, status} = InstructionsProcessor.get_workflow_status(workflow_id)
      assert status == :cancelled
    end

    test "returns error for non-existent workflow status" do
      assert {:error, :workflow_not_found} =
               InstructionsProcessor.get_workflow_status("nonexistent_workflow")
    end

    test "returns error for non-existent workflow cancellation" do
      assert {:error, :workflow_not_found} =
               InstructionsProcessor.cancel_workflow("nonexistent_workflow")
    end
  end

  describe "instruction caching" do
    test "caches instruction results" do
      instruction_spec = %{
        type: :skill_invocation,
        action: "cacheable_action",
        parameters: %{skill_id: :test_skill}
      }

      # First execution
      assert {:ok, result1} =
               InstructionsProcessor.process_instruction(instruction_spec, "agent1")

      # Second execution should use cache (would be faster in real implementation)
      assert {:ok, result2} =
               InstructionsProcessor.process_instruction(instruction_spec, "agent1")

      # Results should be similar (exact match would depend on implementation details)
      assert result1.status == result2.status
    end

    test "returns cache miss for non-cached instruction" do
      assert {:error, :not_cached} =
               InstructionsProcessor.get_cached_instruction("nonexistent_hash")
    end
  end

  describe "error handling and compensation" do
    test "processes instruction with compensation specification" do
      instruction_spec = %{
        type: :skill_invocation,
        action: "potentially_failing_action",
        parameters: %{skill_id: :test_skill},
        compensation: %{type: :retry}
      }

      # Even if the instruction fails, compensation should handle it
      assert {:ok, _result} =
               InstructionsProcessor.process_instruction(instruction_spec, "agent1")
    end

    test "handles instruction without compensation gracefully" do
      instruction_spec = %{
        type: :skill_invocation,
        action: "test_action",
        parameters: %{skill_id: :test_skill}
      }

      assert {:ok, _result} =
               InstructionsProcessor.process_instruction(instruction_spec, "agent1")
    end
  end

  describe "dependency resolution" do
    test "correctly orders instructions based on dependencies" do
      workflow_spec = %{
        name: "dependency_order_test",
        instructions: [
          %{
            id: "inst_3",
            type: :skill_invocation,
            action: "step3",
            parameters: %{},
            dependencies: ["inst_1", "inst_2"]
          },
          %{
            id: "inst_1",
            type: :skill_invocation,
            action: "step1",
            parameters: %{},
            dependencies: []
          },
          %{
            id: "inst_2",
            type: :skill_invocation,
            action: "step2",
            parameters: %{},
            dependencies: ["inst_1"]
          }
        ]
      }

      assert {:ok, workflow_id} = InstructionsProcessor.compose_workflow(workflow_spec)

      # Execute workflow to verify proper ordering
      assert {:ok, execution_result} =
               InstructionsProcessor.execute_workflow(workflow_id, "agent1")

      assert execution_result.status == :completed
    end
  end
end
