defmodule RubberDuck.DirectivesEngineTest do
  use ExUnit.Case, async: true
  alias RubberDuck.DirectivesEngine

  setup do
    {:ok, pid} = DirectivesEngine.start_link([])
    %{engine: pid}
  end

  describe "directive issuance" do
    test "issues a valid directive successfully" do
      directive_spec = %{
        type: :behavior_modification,
        target: "agent1",
        parameters: %{behavior_type: :learning_rate, modification_type: :increase}
      }

      assert {:ok, directive_id} = DirectivesEngine.issue_directive(directive_spec)
      assert is_binary(directive_id)
    end

    test "rejects directive with missing required fields" do
      directive_spec = %{
        type: :behavior_modification
        # Missing target and parameters
      }

      assert {:error, {:missing_required_fields, missing_fields}} =
               DirectivesEngine.issue_directive(directive_spec)

      assert :target in missing_fields
      assert :parameters in missing_fields
    end

    test "rejects directive with invalid type" do
      directive_spec = %{
        type: :invalid_type,
        target: "agent1",
        parameters: %{}
      }

      assert {:error, {:invalid_directive_type, :invalid_type}} =
               DirectivesEngine.issue_directive(directive_spec)
    end

    test "rejects directive targeting non-existent agent" do
      directive_spec = %{
        type: :behavior_modification,
        target: "nonexistent_agent",
        parameters: %{behavior_type: :learning_rate, modification_type: :increase}
      }

      assert {:error, {:target_agent_not_found, "nonexistent_agent"}} =
               DirectivesEngine.issue_directive(directive_spec)
    end
  end

  describe "directive validation" do
    test "validates behavior modification parameters" do
      valid_spec = %{
        type: :behavior_modification,
        target: :all,
        parameters: %{behavior_type: :learning_rate, modification_type: :increase}
      }

      assert :ok = DirectivesEngine.validate_directive(valid_spec)
    end

    test "rejects invalid behavior modification parameters" do
      invalid_spec = %{
        type: :behavior_modification,
        target: :all,
        parameters: %{invalid_param: :value}
      }

      assert {:error, :invalid_behavior_modification_parameters} =
               DirectivesEngine.validate_directive(invalid_spec)
    end

    test "validates capability update parameters" do
      valid_spec = %{
        type: :capability_update,
        target: :all,
        parameters: %{capabilities: [:new_capability]}
      }

      assert :ok = DirectivesEngine.validate_directive(valid_spec)
    end

    test "validates skill configuration parameters" do
      valid_spec = %{
        type: :skill_configuration,
        target: :all,
        parameters: %{skill_id: :test_skill, configuration: %{timeout: 5000}}
      }

      assert :ok = DirectivesEngine.validate_directive(valid_spec)
    end
  end

  describe "agent capabilities management" do
    test "updates agent capabilities" do
      capabilities = [:capability1, :capability2]

      assert :ok = DirectivesEngine.update_agent_capabilities("agent1", capabilities)
    end

    test "allows targeting agent after capabilities are registered" do
      DirectivesEngine.update_agent_capabilities("agent1", [:test_capability])

      directive_spec = %{
        type: :behavior_modification,
        target: "agent1",
        parameters: %{behavior_type: :learning_rate, modification_type: :increase}
      }

      assert {:ok, _directive_id} = DirectivesEngine.issue_directive(directive_spec)
    end
  end

  describe "directive retrieval" do
    setup do
      DirectivesEngine.update_agent_capabilities("agent1", [:test_capability])
      :ok
    end

    test "retrieves active directives for agent" do
      directive_spec = %{
        type: :behavior_modification,
        target: "agent1",
        parameters: %{behavior_type: :learning_rate, modification_type: :increase}
      }

      {:ok, _directive_id} = DirectivesEngine.issue_directive(directive_spec)

      {:ok, directives} = DirectivesEngine.get_agent_directives("agent1")

      assert length(directives) == 1
      assert hd(directives).type == :behavior_modification
      assert hd(directives).target == "agent1"
    end

    test "retrieves directives for all agents" do
      directive_spec = %{
        type: :behavior_modification,
        target: :all,
        parameters: %{behavior_type: :learning_rate, modification_type: :increase}
      }

      {:ok, _directive_id} = DirectivesEngine.issue_directive(directive_spec)

      {:ok, directives} = DirectivesEngine.get_agent_directives("agent1")

      assert length(directives) == 1
      assert hd(directives).target == :all
    end

    test "returns empty list for agent with no directives" do
      {:ok, directives} = DirectivesEngine.get_agent_directives("agent_without_directives")

      assert directives == []
    end
  end

  describe "directive revocation" do
    setup do
      DirectivesEngine.update_agent_capabilities("agent1", [:test_capability])

      directive_spec = %{
        type: :behavior_modification,
        target: "agent1",
        parameters: %{behavior_type: :learning_rate, modification_type: :increase}
      }

      {:ok, directive_id} = DirectivesEngine.issue_directive(directive_spec)
      %{directive_id: directive_id}
    end

    test "revokes an active directive", %{directive_id: directive_id} do
      assert :ok = DirectivesEngine.revoke_directive(directive_id)

      # Verify directive is no longer active
      {:ok, directives} = DirectivesEngine.get_agent_directives("agent1")
      assert directives == []
    end

    test "returns error for non-existent directive" do
      assert {:error, :directive_not_found} =
               DirectivesEngine.revoke_directive("nonexistent_directive")
    end
  end

  describe "rollback functionality" do
    setup do
      DirectivesEngine.update_agent_capabilities("agent1", [:test_capability])
      :ok
    end

    test "creates rollback point" do
      assert {:ok, rollback_id} = DirectivesEngine.create_rollback_point("test_checkpoint")
      assert is_binary(rollback_id)
    end

    test "rolls back to previous state" do
      # Create initial state
      directive_spec1 = %{
        type: :behavior_modification,
        target: "agent1",
        parameters: %{behavior_type: :learning_rate, modification_type: :increase}
      }

      {:ok, _directive_id1} = DirectivesEngine.issue_directive(directive_spec1)

      # Create rollback point
      {:ok, rollback_id} = DirectivesEngine.create_rollback_point("before_second_directive")

      # Add another directive
      directive_spec2 = %{
        type: :capability_update,
        target: "agent1",
        parameters: %{capabilities: [:new_capability]}
      }

      {:ok, _directive_id2} = DirectivesEngine.issue_directive(directive_spec2)

      # Verify two directives exist
      {:ok, directives_before} = DirectivesEngine.get_agent_directives("agent1")
      assert length(directives_before) == 2

      # Rollback
      assert :ok = DirectivesEngine.rollback_to_point(rollback_id)

      # Verify only first directive remains
      {:ok, directives_after} = DirectivesEngine.get_agent_directives("agent1")
      assert length(directives_after) == 1
      assert hd(directives_after).type == :behavior_modification
    end

    test "returns error for non-existent rollback point" do
      assert {:error, :rollback_point_not_found} =
               DirectivesEngine.rollback_to_point("nonexistent_rollback")
    end
  end

  describe "directive history" do
    setup do
      DirectivesEngine.update_agent_capabilities("agent1", [:test_capability])

      directive_spec = %{
        type: :behavior_modification,
        target: "agent1",
        parameters: %{behavior_type: :learning_rate, modification_type: :increase}
      }

      {:ok, directive_id} = DirectivesEngine.issue_directive(directive_spec)
      DirectivesEngine.revoke_directive(directive_id)

      :ok
    end

    test "retrieves execution history" do
      {:ok, history} = DirectivesEngine.get_directive_history()

      assert length(history) >= 1

      # Should contain both issuance and revocation entries
      execution_entries =
        Enum.filter(history, fn entry -> Map.has_key?(entry, :execution_result) end)

      revocation_entries =
        Enum.filter(history, fn entry -> Map.has_key?(entry, :revocation_result) end)

      assert length(execution_entries) >= 1
      assert length(revocation_entries) >= 1
    end

    test "filters history by directive type" do
      {:ok, history} =
        DirectivesEngine.get_directive_history(%{directive_type: :behavior_modification})

      Enum.each(history, fn entry ->
        if Map.has_key?(entry, :directive) do
          assert entry.directive.type == :behavior_modification
        end
      end)
    end

    test "filters history by target agent" do
      {:ok, history} = DirectivesEngine.get_directive_history(%{target_agent: "agent1"})

      Enum.each(history, fn entry ->
        if Map.has_key?(entry, :directive) do
          assert entry.directive.target == "agent1"
        end
      end)
    end
  end

  describe "priority handling" do
    setup do
      DirectivesEngine.update_agent_capabilities("agent1", [:test_capability])
      :ok
    end

    test "processes high priority directive immediately" do
      directive_spec = %{
        type: :emergency_response,
        target: "agent1",
        parameters: %{emergency_type: :security_breach},
        priority: 9
      }

      assert {:ok, _directive_id} = DirectivesEngine.issue_directive(directive_spec)
    end

    test "queues normal priority directive" do
      directive_spec = %{
        type: :behavior_modification,
        target: "agent1",
        parameters: %{behavior_type: :learning_rate, modification_type: :increase},
        priority: 5
      }

      assert {:ok, _directive_id} = DirectivesEngine.issue_directive(directive_spec)
    end
  end

  describe "expiration handling" do
    setup do
      DirectivesEngine.update_agent_capabilities("agent1", [:test_capability])
      :ok
    end

    test "accepts directive with expiration time" do
      # 1 hour from now
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      directive_spec = %{
        type: :behavior_modification,
        target: "agent1",
        parameters: %{behavior_type: :learning_rate, modification_type: :increase},
        expires_at: expires_at
      }

      assert {:ok, _directive_id} = DirectivesEngine.issue_directive(directive_spec)
    end

    test "processes directive without expiration time" do
      directive_spec = %{
        type: :behavior_modification,
        target: "agent1",
        parameters: %{behavior_type: :learning_rate, modification_type: :increase}
      }

      assert {:ok, _directive_id} = DirectivesEngine.issue_directive(directive_spec)
    end
  end
end
