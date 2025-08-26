defmodule RubberDuck.Agents.FeedbackProcessorAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.FeedbackProcessorAgent

  describe "init/1" do
    test "initializes with default state" do
      {:ok, agent} = FeedbackProcessorAgent.init()

      assert agent.state.processing_queue == []
      assert agent.state.active_processing == %{}
      assert agent.state.learning_models == %{}
      assert Map.has_key?(agent.state, :processing_stats)
      assert Map.has_key?(agent.state, :configuration)
    end

    test "initializes with custom configuration" do
      opts = [
        max_concurrent: 3,
        timeout_ms: 20_000,
        learning_threshold: 0.8
      ]

      {:ok, agent} = FeedbackProcessorAgent.init(opts)

      assert agent.state.configuration.max_concurrent_processing == 3
      assert agent.state.configuration.processing_timeout_ms == 20_000
      assert agent.state.configuration.learning_threshold == 0.8
    end
  end

  describe "process_feedback_batch/3" do
    setup do
      {:ok, agent} = FeedbackProcessorAgent.init()
      %{agent: agent}
    end

    test "processes valid feedback batch successfully", %{agent: agent} do
      feedback_batch = [
        %{
          evaluation_id: "eval_1",
          feedback_type: :explicit_rating,
          rating: 4,
          confidence: 0.8,
          learning_value: 0.7
        },
        %{
          evaluation_id: "eval_2",
          feedback_type: :implicit_acceptance,
          acceptance_time_ms: 3_000,
          confidence: 0.75,
          learning_value: 0.6
        }
      ]

      {:ok, results, updated_agent} =
        FeedbackProcessorAgent.process_feedback_batch(agent, feedback_batch)

      assert length(results) == 2
      assert updated_agent.state.processing_stats.total_processed > 0

      Enum.each(results, fn result ->
        assert Map.has_key?(result, :learning_category)
        assert Map.has_key?(result, :processing_priority)
        assert Map.has_key?(result, :extracted_insights)
        assert Map.has_key?(result, :learning_actions)
        assert Map.has_key?(result, :routing_targets)
      end)
    end

    test "handles invalid feedback batch", %{agent: agent} do
      invalid_batch = "not a list"

      {:error, reason, returned_agent} =
        FeedbackProcessorAgent.process_feedback_batch(agent, invalid_batch)

      assert String.contains?(reason, "Invalid feedback batch")
      # Agent unchanged on error
      assert returned_agent == agent
    end

    test "processes different feedback types appropriately", %{agent: agent} do
      diverse_feedback = [
        %{
          evaluation_id: "eval_a",
          feedback_type: :explicit_correction,
          correction_details: %{score_issue: true},
          confidence: 0.9,
          learning_value: 0.95
        },
        %{
          evaluation_id: "eval_b",
          feedback_type: :judge_agreement,
          consensus_data: %{agreement_score: 0.6},
          confidence: 0.85,
          learning_value: 0.8
        }
      ]

      {:ok, results, _updated_agent} =
        FeedbackProcessorAgent.process_feedback_batch(agent, diverse_feedback)

      correction_result =
        Enum.find(results, fn r ->
          r.original_feedback.feedback_type == :explicit_correction
        end)

      agreement_result =
        Enum.find(results, fn r ->
          r.original_feedback.feedback_type == :judge_agreement
        end)

      assert correction_result.learning_category == :evaluation_criteria_adjustment
      assert agreement_result.learning_category == :judge_selection_optimization

      # Different priorities based on feedback type
      assert correction_result.processing_priority == :high
      assert agreement_result.processing_priority in [:high, :medium]
    end
  end

  describe "analyze_learning_opportunities/3" do
    setup do
      {:ok, agent} = FeedbackProcessorAgent.init()
      %{agent: agent}
    end

    test "analyzes comprehensive learning opportunities", %{agent: agent} do
      feedback_data = %{
        evaluation_id: "eval_learn",
        feedback_type: :explicit_correction,
        correction_details: %{
          accuracy_issues: ["missed edge case", "incorrect scoring"],
          suggested_improvements: ["add boundary testing", "adjust weights"]
        },
        confidence: 0.9,
        learning_value: 0.85
      }

      {:ok, insights, updated_agent} =
        FeedbackProcessorAgent.analyze_learning_opportunities(
          agent,
          feedback_data,
          :comprehensive
        )

      assert Map.has_key?(insights, :base_insights)
      assert Map.has_key?(insights, :focused_insights)
      assert Map.has_key?(insights, :learning_confidence)
      assert Map.has_key?(insights, :recommended_actions)

      # Agent should have updated learning models
      assert map_size(updated_agent.state.learning_models) > 0
    end

    test "focuses analysis on specific learning aspects", %{agent: agent} do
      feedback_data = %{
        evaluation_id: "eval_judge",
        feedback_type: :judge_agreement,
        consensus_data: %{low_agreement: true},
        confidence: 0.8,
        learning_value: 0.7
      }

      {:ok, insights, _updated_agent} =
        FeedbackProcessorAgent.analyze_learning_opportunities(
          agent,
          feedback_data,
          :judge_selection
        )

      assert insights.focused_insights == %{judge_optimization: "improve_routing"}
      assert insights.analysis_focus == :judge_selection
    end
  end

  describe "route_feedback_to_learners/3" do
    setup do
      {:ok, agent} = FeedbackProcessorAgent.init()
      %{agent: agent}
    end

    test "routes processed feedback to appropriate learners", %{agent: agent} do
      processed_feedback = [
        %{
          learning_category: :judge_selection_optimization,
          processing_priority: :high,
          routing_targets: [:judge_selection_learner, :coordination_optimizer],
          learning_actions: ["optimize_routing", "update_weights"]
        },
        %{
          learning_category: :cost_optimization,
          processing_priority: :medium,
          routing_targets: [:cost_optimization_learner],
          learning_actions: ["reduce_costs", "improve_efficiency"]
        }
      ]

      {:ok, routing_results, updated_agent} =
        FeedbackProcessorAgent.route_feedback_to_learners(
          agent,
          processed_feedback
        )

      assert Map.has_key?(routing_results, :successful_routes)
      assert Map.has_key?(routing_results, :total_routed)
      assert Map.has_key?(routing_results, :routing_summary)

      assert routing_results.total_routed > 0
      # Agent should be updated
      assert updated_agent != agent
    end

    test "handles routing failures gracefully", %{agent: agent} do
      # Test with empty processed feedback
      {:ok, routing_results, _updated_agent} =
        FeedbackProcessorAgent.route_feedback_to_learners(
          agent,
          []
        )

      assert routing_results.total_routed == 0
    end
  end

  describe "get_processing_stats/1" do
    test "returns comprehensive processing statistics" do
      {:ok, agent} = FeedbackProcessorAgent.init()

      stats = FeedbackProcessorAgent.get_processing_stats(agent)

      assert is_number(stats.total_processed)
      assert is_number(stats.average_processing_time_ms)
      assert is_number(stats.success_rate)
      assert is_number(stats.learning_actions_generated)
      assert is_number(stats.current_queue_size)
      assert is_number(stats.active_processing_count)
      assert is_number(stats.learning_model_count)
    end
  end

  describe "configure_processing/2" do
    test "updates processing configuration successfully" do
      {:ok, agent} = FeedbackProcessorAgent.init()

      new_config = %{
        learning_threshold: 0.85,
        batch_size: 15
      }

      {:ok, updated_agent} = FeedbackProcessorAgent.configure_processing(agent, new_config)

      assert updated_agent.state.configuration.learning_threshold == 0.85
      assert updated_agent.state.configuration.batch_size == 15

      # Other configuration should remain unchanged
      assert Map.has_key?(updated_agent.state.configuration, :max_concurrent_processing)
    end
  end

  describe "learning category determination" do
    test "categorizes feedback appropriately" do
      feedback_items = [
        %{feedback_type: :explicit_correction, evaluation_id: "eval_1"},
        %{feedback_type: :judge_agreement, evaluation_id: "eval_2"},
        %{feedback_type: :cost_efficiency, evaluation_id: "eval_3"},
        %{feedback_type: :implicit_rejection, evaluation_id: "eval_4"}
      ]

      {:ok, agent} = FeedbackProcessorAgent.init()

      {:ok, results, _updated_agent} =
        FeedbackProcessorAgent.process_feedback_batch(agent, feedback_items)

      correction_result =
        Enum.find(results, fn r -> r.original_feedback.feedback_type == :explicit_correction end)

      agreement_result =
        Enum.find(results, fn r -> r.original_feedback.feedback_type == :judge_agreement end)

      cost_result =
        Enum.find(results, fn r -> r.original_feedback.feedback_type == :cost_efficiency end)

      rejection_result =
        Enum.find(results, fn r -> r.original_feedback.feedback_type == :implicit_rejection end)

      assert correction_result.learning_category == :evaluation_criteria_adjustment
      assert agreement_result.learning_category == :judge_selection_optimization
      assert cost_result.learning_category == :cost_optimization
      assert rejection_result.learning_category == :quality_enhancement
    end
  end

  describe "processing performance tracking" do
    test "tracks processing metrics over time" do
      {:ok, agent} = FeedbackProcessorAgent.init()

      feedback_batch = [
        %{evaluation_id: "eval_perf_1", feedback_type: :explicit_rating, rating: 4},
        %{
          evaluation_id: "eval_perf_2",
          feedback_type: :implicit_acceptance,
          acceptance_time_ms: 2_000
        }
      ]

      initial_stats = FeedbackProcessorAgent.get_processing_stats(agent)

      {:ok, _results, updated_agent} =
        FeedbackProcessorAgent.process_feedback_batch(agent, feedback_batch)

      updated_stats = FeedbackProcessorAgent.get_processing_stats(updated_agent)

      assert updated_stats.total_processed > initial_stats.total_processed
      assert is_number(updated_stats.average_processing_time_ms)
      assert updated_stats.success_rate > 0.0
    end
  end

  describe "edge cases and error scenarios" do
    test "handles feedback with missing required fields" do
      {:ok, agent} = FeedbackProcessorAgent.init()

      incomplete_feedback = [
        # Missing evaluation_id, rating, etc.
        %{feedback_type: :explicit_rating}
      ]

      result = FeedbackProcessorAgent.process_feedback_batch(agent, incomplete_feedback)

      assert match?({:error, _reason, _agent}, result)
    end

    test "handles feedback with invalid data types" do
      {:ok, agent} = FeedbackProcessorAgent.init()

      invalid_type_feedback = [
        %{
          # Should be string
          evaluation_id: 12345,
          # Should be atom
          feedback_type: "not_atom",
          # Should be number
          rating: "five"
        }
      ]

      result = FeedbackProcessorAgent.process_feedback_batch(agent, invalid_type_feedback)

      assert match?({:error, _reason, _agent}, result)
    end
  end
end

