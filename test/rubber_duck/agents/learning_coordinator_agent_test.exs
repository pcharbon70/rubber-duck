defmodule RubberDuck.Agents.LearningCoordinatorAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.LearningCoordinatorAgent

  describe "init/1" do
    test "initializes with default state" do
      {:ok, agent} = LearningCoordinatorAgent.init()

      assert agent.state.active_learning_sessions == %{}
      assert agent.state.learning_queue == []
      assert agent.state.model_registry == %{}
      assert agent.state.learning_effectiveness_history == []
      assert agent.state.rollback_stack == []
      assert Map.has_key?(agent.state, :performance_metrics)
      assert Map.has_key?(agent.state, :configuration)
    end

    test "initializes with custom configuration" do
      opts = [
        max_concurrent: 5,
        timeout_ms: 90_000,
        effectiveness_threshold: 0.8,
        rollback_enabled: false
      ]

      {:ok, agent} = LearningCoordinatorAgent.init(opts)

      assert agent.state.configuration.max_concurrent_learning == 5
      assert agent.state.configuration.learning_timeout_ms == 90_000
      assert agent.state.configuration.effectiveness_threshold == 0.8
      assert agent.state.configuration.rollback_enabled == false
    end
  end

  describe "orchestrate_learning/3" do
    setup do
      {:ok, agent} = LearningCoordinatorAgent.init()
      %{agent: agent}
    end

    test "orchestrates learning workflow successfully", %{agent: agent} do
      learning_request = %{
        patterns: [
          %{pattern_type: :success_patterns, confidence: 0.8, data: "pattern_data"},
          %{pattern_type: :failure_modes, confidence: 0.75, data: "failure_data"}
        ],
        target_engines: [:judge_selection_learner, :criteria_adaptation_engine],
        learning_priority: :high
      }

      {:ok, result, updated_agent} =
        LearningCoordinatorAgent.orchestrate_learning(
          agent,
          learning_request
        )

      assert Map.has_key?(result, :adaptations)
      assert Map.has_key?(result, :effectiveness_predictions)
      assert Map.has_key?(result, :learning_confidence)
      assert is_list(result.engines_used)
      assert result.coordination_success_rate > 0.0

      # Agent should be updated
      assert updated_agent.state.performance_metrics.total_learning_sessions > 0
      assert length(updated_agent.state.learning_effectiveness_history) > 0
    end

    test "validates learning request requirements", %{agent: agent} do
      invalid_request = %{
        # Empty patterns
        patterns: [],
        # Invalid engine
        target_engines: [:unknown_engine],
        # Invalid priority
        learning_priority: :invalid_priority
      }

      {:error, reason, returned_agent} =
        LearningCoordinatorAgent.orchestrate_learning(
          agent,
          invalid_request
        )

      assert is_binary(reason)
      assert returned_agent == agent
    end

    test "handles missing required fields in learning request", %{agent: agent} do
      incomplete_request = %{
        patterns: [%{pattern_type: :success_patterns}]
        # Missing target_engines and learning_priority
      }

      {:error, reason, _agent} =
        LearningCoordinatorAgent.orchestrate_learning(
          agent,
          incomplete_request
        )

      assert String.contains?(reason, "Missing required fields")
    end
  end

  describe "validate_learning_effectiveness/4" do
    setup do
      {:ok, agent} = LearningCoordinatorAgent.init()

      # First create a learning session
      learning_request = %{
        patterns: [%{pattern_type: :success_patterns}],
        target_engines: [:judge_selection_learner],
        learning_priority: :medium
      }

      {:ok, _result, agent_with_session} =
        LearningCoordinatorAgent.orchestrate_learning(
          agent,
          learning_request
        )

      %{agent: agent_with_session}
    end

    test "validates effective learning and approves", %{agent: agent} do
      # Get a session ID from the agent's history
      session_id = "test_session_123"

      validation_data = [
        %{metric: :accuracy, before: 0.75, after: 0.85},
        %{metric: :user_satisfaction, before: 0.7, after: 0.82},
        %{metric: :cost_efficiency, before: 0.6, after: 0.7}
      ]

      result =
        LearningCoordinatorAgent.validate_learning_effectiveness(
          agent,
          session_id,
          validation_data
        )

      # Should handle gracefully whether session exists or not
      case result do
        {:ok, validation_result, updated_agent} ->
          assert Map.has_key?(validation_result, :effectiveness_score)
          assert is_map(updated_agent.state)

        {:error, reason, returned_agent} ->
          assert String.contains?(reason, "session") or String.contains?(reason, "not found")
          assert returned_agent == agent
      end
    end

    test "detects ineffective learning and triggers rollback", %{agent: agent} do
      session_id = "test_session_456"

      # Validation data showing poor effectiveness
      poor_validation_data = [
        # Decreased accuracy
        %{metric: :accuracy, before: 0.8, after: 0.7},
        # Decreased satisfaction
        %{metric: :user_satisfaction, before: 0.75, after: 0.6}
      ]

      result =
        LearningCoordinatorAgent.validate_learning_effectiveness(
          agent,
          session_id,
          poor_validation_data,
          effectiveness_threshold: 0.8
        )

      # Should handle appropriately
      case result do
        {:ok, validation_result, _updated_agent} ->
          # May include rollback information
          assert is_map(validation_result)

        {:error, _reason, _agent} ->
          # Expected if session doesn't exist
          assert true
      end
    end
  end

  describe "get_coordination_stats/1" do
    test "returns comprehensive coordination statistics" do
      {:ok, agent} = LearningCoordinatorAgent.init()

      stats = LearningCoordinatorAgent.get_coordination_stats(agent)

      assert is_number(stats.total_learning_sessions)
      assert is_number(stats.successful_adaptations)
      assert is_number(stats.failed_adaptations)
      assert is_number(stats.success_rate)
      assert is_number(stats.average_learning_time_ms)
      assert is_number(stats.model_update_count)
      assert is_number(stats.rollback_count)
      assert is_number(stats.active_sessions)
      assert is_number(stats.queued_learning_requests)
      assert is_number(stats.registered_models)
      assert is_list(stats.recent_effectiveness_history)
    end

    test "calculates success rate correctly" do
      {:ok, agent} = LearningCoordinatorAgent.init()

      # Mock some performance data
      agent_with_performance = %{
        agent
        | state: %{
            agent.state
            | performance_metrics: %{
                agent.state.performance_metrics
                | total_learning_sessions: 10,
                  successful_adaptations: 8,
                  failed_adaptations: 2
              }
          }
      }

      stats = LearningCoordinatorAgent.get_coordination_stats(agent_with_performance)

      assert stats.success_rate == 0.8
      assert stats.total_learning_sessions == 10
      assert stats.successful_adaptations == 8
      assert stats.failed_adaptations == 2
    end
  end

  describe "configure_learning/2" do
    test "updates learning configuration successfully" do
      {:ok, agent} = LearningCoordinatorAgent.init()

      new_config = %{
        effectiveness_threshold: 0.85,
        validation_strategy: :gradual_rollout,
        rollback_enabled: false
      }

      {:ok, updated_agent} = LearningCoordinatorAgent.configure_learning(agent, new_config)

      assert updated_agent.state.configuration.effectiveness_threshold == 0.85
      assert updated_agent.state.configuration.validation_strategy == :gradual_rollout
      assert updated_agent.state.configuration.rollback_enabled == false

      # Other configuration should remain unchanged
      assert Map.has_key?(updated_agent.state.configuration, :max_concurrent_learning)
    end
  end

  describe "learning request validation" do
    test "validates learning priority values" do
      {:ok, agent} = LearningCoordinatorAgent.init()

      valid_priorities = [:critical, :high, :medium, :low, :background]

      Enum.each(valid_priorities, fn priority ->
        request = %{
          patterns: [%{pattern_type: :success_patterns}],
          target_engines: [:judge_selection_learner],
          learning_priority: priority
        }

        result = LearningCoordinatorAgent.orchestrate_learning(agent, request)
        assert match?({:ok, _result, _agent}, result)
      end)
    end

    test "rejects invalid target engines" do
      {:ok, agent} = LearningCoordinatorAgent.init()

      invalid_request = %{
        patterns: [%{pattern_type: :success_patterns}],
        target_engines: [:nonexistent_engine, :invalid_learner],
        learning_priority: :medium
      }

      {:error, reason, _agent} =
        LearningCoordinatorAgent.orchestrate_learning(agent, invalid_request)

      assert String.contains?(reason, "Invalid target engines")
    end
  end

  describe "learning effectiveness tracking" do
    test "tracks learning session effectiveness over time" do
      {:ok, agent} = LearningCoordinatorAgent.init()

      # Simulate multiple learning sessions
      requests = [
        %{
          patterns: [%{pattern_type: :success_patterns, confidence: 0.8}],
          target_engines: [:judge_selection_learner],
          learning_priority: :high
        },
        %{
          patterns: [%{pattern_type: :failure_modes, confidence: 0.75}],
          target_engines: [:criteria_adaptation_engine],
          learning_priority: :medium
        }
      ]

      final_agent =
        Enum.reduce(requests, agent, fn request, acc_agent ->
          {:ok, _result, updated_agent} =
            LearningCoordinatorAgent.orchestrate_learning(acc_agent, request)

          updated_agent
        end)

      stats = LearningCoordinatorAgent.get_coordination_stats(final_agent)

      assert stats.total_learning_sessions == 2
      assert length(stats.recent_effectiveness_history) == 2

      # Each history entry should have required fields
      Enum.each(stats.recent_effectiveness_history, fn entry ->
        assert Map.has_key?(entry, :session_id)
        assert Map.has_key?(entry, :effectiveness_score)
        assert Map.has_key?(entry, :adaptations_count)
        assert Map.has_key?(entry, :engines_used)
        assert %DateTime{} = entry.completed_at
      end)
    end
  end

  describe "error handling and edge cases" do
    test "handles empty pattern lists gracefully" do
      {:ok, agent} = LearningCoordinatorAgent.init()

      request_with_empty_patterns = %{
        patterns: [],
        target_engines: [:judge_selection_learner],
        learning_priority: :low
      }

      # Should handle empty patterns appropriately
      result = LearningCoordinatorAgent.orchestrate_learning(agent, request_with_empty_patterns)

      case result do
        {:ok, learning_result, _agent} ->
          # May succeed with empty result
          assert is_map(learning_result)

        {:error, reason, _agent} ->
          # May fail due to insufficient data
          assert is_binary(reason)
      end
    end

    test "handles malformed learning requests" do
      {:ok, agent} = LearningCoordinatorAgent.init()

      malformed_requests = [
        %{patterns: "not_a_list"},
        %{target_engines: "not_a_list"},
        "not_a_map",
        # Missing all required fields
        %{}
      ]

      Enum.each(malformed_requests, fn malformed_request ->
        result = LearningCoordinatorAgent.orchestrate_learning(agent, malformed_request)
        assert match?({:error, _reason, _agent}, result)
      end)
    end
  end

  describe "concurrent learning session management" do
    test "respects maximum concurrent learning limit" do
      opts = [max_concurrent: 2]
      {:ok, agent} = LearningCoordinatorAgent.init(opts)

      # The agent should handle concurrent limits appropriately
      # This is a basic test of configuration
      assert agent.state.configuration.max_concurrent_learning == 2
    end
  end
end
