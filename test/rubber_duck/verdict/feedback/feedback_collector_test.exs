defmodule RubberDuck.Verdict.Feedback.FeedbackCollectorTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Verdict.Feedback.FeedbackCollector

  describe "collect_feedback/3" do
    test "successfully collects and aggregates multi-source feedback" do
      evaluation_id = "eval_123"
      
      feedback_sources = %{
        explicit_rating: %{
          rating: 4,
          context: %{user_satisfaction: :high}
        },
        implicit_acceptance: %{
          acceptance_time_ms: 2_000,
          interaction_count: 1
        },
        judge_agreement: %{
          consensus_score: 0.85,
          participating_judges: [:code_quality, :architecture]
        }
      }
      
      {:ok, result} = FeedbackCollector.collect_feedback(evaluation_id, feedback_sources)
      
      assert result.evaluation_id == evaluation_id
      assert result.total_feedback_count == 3
      assert result.overall_confidence > 0.0
      assert result.learning_value > 0.0
      assert is_map(result.feedback_distribution)
      assert is_list(result.actionable_insights)
    end

    test "handles validation errors gracefully" do
      evaluation_id = "eval_456"
      
      invalid_feedback = %{
        invalid_type: %{some: :data}
      }
      
      {:error, reason} = FeedbackCollector.collect_feedback(evaluation_id, invalid_feedback)
      
      assert String.contains?(reason, "Validation errors")
      assert String.contains?(reason, "Unknown source type")
    end

    test "filters low-confidence feedback when threshold is set" do
      evaluation_id = "eval_789"
      
      mixed_confidence_sources = %{
        explicit_rating: %{rating: 5, context: %{}},  # High confidence
        implicit_retry: %{retry_count: 1}              # Lower confidence
      }
      
      {:ok, result} = FeedbackCollector.collect_feedback(
        evaluation_id, 
        mixed_confidence_sources,
        [min_confidence: 0.8]
      )
      
      # Should filter out lower confidence feedback
      assert result.high_confidence_count <= result.total_feedback_count
    end
  end

  describe "collect_realtime_feedback/3" do
    test "processes real-time feedback successfully" do
      session_id = "session_abc"
      
      feedback_data = %{
        feedback_type: :explicit_rating,
        data: %{rating: 5, immediate: true},
        user_id: "user_123"
      }
      
      {:ok, result} = FeedbackCollector.collect_realtime_feedback(session_id, feedback_data)
      
      assert result.session_id == session_id
      assert result.feedback_type == :explicit_rating
      assert result.confidence > 0.0
      assert result.learning_value > 0.0
      assert %DateTime{} = result.processed_at
    end

    test "validates real-time feedback requirements" do
      session_id = "session_def"
      
      invalid_data = %{
        # Missing feedback_type
        data: %{rating: 3}
      }
      
      {:error, reason} = FeedbackCollector.collect_realtime_feedback(session_id, invalid_data)
      
      assert String.contains?(reason, "Missing required fields")
      assert String.contains?(reason, "feedback_type")
    end
  end

  describe "aggregate_historical_feedback/3" do
    test "aggregates feedback over time window successfully" do
      time_window = {7, :day}
      filters = %{min_confidence: 0.7}
      
      {:ok, result} = FeedbackCollector.aggregate_historical_feedback(time_window, filters)
      
      assert result.time_window == time_window
      assert is_number(result.total_feedback_count)
      assert is_map(result.patterns)
      assert is_map(result.trends)
      assert is_list(result.insights)
      assert %DateTime{} = result.aggregation_metadata.aggregated_at
      assert result.aggregation_metadata.filters_applied == filters
    end

    test "handles empty historical data gracefully" do
      time_window = {1, :hour}  # Very recent, likely empty
      
      {:ok, result} = FeedbackCollector.aggregate_historical_feedback(time_window)
      
      assert result.total_feedback_count >= 0
      assert is_map(result.patterns)
      assert is_map(result.trends)
    end
  end

  describe "get_collection_stats/1" do
    test "returns comprehensive collection statistics" do
      stats = FeedbackCollector.get_collection_stats({24, :hour})
      
      assert is_number(stats.total_feedback_collected)
      assert is_map(stats.feedback_by_type)
      assert is_map(stats.feedback_by_source)
      assert is_number(stats.average_confidence)
      assert is_map(stats.learning_value_distribution)
      assert is_map(stats.processing_performance)
      assert is_map(stats.collection_health)
      
      # Health metrics should be present
      health = stats.collection_health
      assert is_number(health.success_rate)
      assert is_number(health.error_rate)
      assert is_number(health.latency_p95)
    end

    test "uses default time window when not specified" do
      default_stats = FeedbackCollector.get_collection_stats()
      custom_stats = FeedbackCollector.get_collection_stats({24, :hour})
      
      # Should return similar structure
      assert Map.keys(default_stats) == Map.keys(custom_stats)
    end
  end

  describe "feedback confidence calculation" do
    test "assigns appropriate confidence based on feedback type" do
      high_confidence_data = %{
        feedback_type: :explicit_correction,
        data: %{
          correction_details: %{score: 0.9, reasoning: "Detailed explanation"},
          user_explanation: "This evaluation missed key architectural concerns"
        }
      }
      
      {:ok, result} = FeedbackCollector.collect_realtime_feedback("session_1", high_confidence_data)
      
      assert result.confidence > 0.8
      assert result.learning_value > 0.8
    end

    test "lower confidence for implicit feedback" do
      implicit_data = %{
        feedback_type: :implicit_retry,
        data: %{retry_count: 2}
      }
      
      {:ok, result} = FeedbackCollector.collect_realtime_feedback("session_2", implicit_data)
      
      assert result.confidence < 0.9  # Should be lower than explicit feedback
      assert result.learning_value > 0.0
    end
  end

  describe "learning value assessment" do
    test "high learning value for explicit corrections" do
      correction_data = %{
        feedback_type: :explicit_correction,
        data: %{
          correction_details: %{
            issues_found: ["incorrect scoring", "missed security concerns"],
            suggested_improvements: ["update criteria weights", "add security check"]
          },
          user_explanation: "The evaluation completely missed critical security vulnerabilities"
        }
      }
      
      {:ok, result} = FeedbackCollector.collect_realtime_feedback("session_3", correction_data)
      
      assert result.learning_value > 0.8
      assert result.urgency in [:high, :critical]
    end

    test "moderate learning value for ratings with context" do
      rating_data = %{
        feedback_type: :explicit_rating,
        data: %{
          rating: 2,
          context: %{
            dissatisfaction_reason: "too slow",
            expected_time: "under 10 seconds"
          }
        }
      }
      
      {:ok, result} = FeedbackCollector.collect_realtime_feedback("session_4", rating_data)
      
      assert result.learning_value > 0.6
      assert result.learning_value < 0.9
    end
  end

  describe "feedback source validation" do
    test "validates known feedback source types" do
      valid_sources = %{
        explicit_rating: %{rating: 5},
        implicit_acceptance: %{acceptance_time_ms: 1_500},
        system_performance: %{latency_ms: 800, cost_usd: 0.02}
      }
      
      {:ok, result} = FeedbackCollector.collect_feedback("eval_valid", valid_sources)
      
      assert result.total_feedback_count == 3
      assert result.overall_confidence > 0.0
    end

    test "rejects unknown feedback source types" do
      invalid_sources = %{
        unknown_source_type: %{some: :data}
      }
      
      {:error, reason} = FeedbackCollector.collect_feedback("eval_invalid", invalid_sources)
      
      assert String.contains?(reason, "Unknown source type")
    end
  end

  describe "actionable insights extraction" do
    test "extracts insights from high-value feedback" do
      high_value_sources = %{
        explicit_correction: %{
          correction_details: %{
            score_correction: 0.3,  # Significant correction
            criteria_issues: ["accuracy", "completeness"]
          },
          user_explanation: "The evaluation missed several important architectural patterns"
        }
      }
      
      {:ok, result} = FeedbackCollector.collect_feedback("eval_insights", high_value_sources)
      
      assert length(result.actionable_insights) > 0
      
      first_insight = List.first(result.actionable_insights)
      assert Map.has_key?(first_insight, :type)
      assert Map.has_key?(first_insight, :confidence)
      assert Map.has_key?(first_insight, :recommended_action)
    end

    test "suggests appropriate learning actions" do
      agreement_feedback = %{
        judge_agreement: %{
          consensus_score: 0.4,  # Low consensus
          disagreement_areas: ["scoring methodology", "criteria interpretation"],
          participating_judges: [:code_quality, :architecture, :security]
        }
      }
      
      {:ok, result} = FeedbackCollector.collect_feedback("eval_agreement", agreement_feedback)
      
      insights = result.actionable_insights
      
      # Should suggest consensus mechanism improvements
      assert Enum.any?(insights, fn insight ->
        insight.recommended_action == :improve_consensus_mechanism
      end)
    end
  end

  describe "error handling and edge cases" do
    test "handles empty feedback sources" do
      {:error, reason} = FeedbackCollector.collect_feedback("eval_empty", %{})
      
      assert String.contains?(reason, "Validation errors")
    end

    test "handles malformed feedback data gracefully" do
      malformed_sources = %{
        explicit_rating: "not a map"  # Should be a map
      }
      
      {:error, reason} = FeedbackCollector.collect_feedback("eval_malformed", malformed_sources)
      
      assert is_binary(reason)
    end

    test "provides meaningful error messages for debugging" do
      complex_invalid_sources = %{
        explicit_rating: %{rating: 10},  # Invalid rating range
        explicit_comment: %{comment: ""},  # Empty comment
        unknown_type: %{data: "anything"}  # Unknown type
      }
      
      {:error, reason} = FeedbackCollector.collect_feedback("eval_debug", complex_invalid_sources)
      
      # Error should be descriptive and help with debugging
      assert is_binary(reason)
      assert String.length(reason) > 20
    end
  end
end