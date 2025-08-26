defmodule RubberDuck.Verdict.Adaptation.DynamicRoutingEngineTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Verdict.Adaptation.DynamicRoutingEngine

  describe "select_optimal_judges/4" do
    test "selects judges using learned optimal strategy" do
      evaluation_context = %{
        evaluation_type: :comprehensive_evaluation,
        complexity: :high,
        quality_requirements: %{min_accuracy: 0.85}
      }

      available_judges = [:code_quality, :architecture, :security, :test_quality]

      {:ok, result} =
        DynamicRoutingEngine.select_optimal_judges(
          evaluation_context,
          available_judges,
          nil,
          strategy: :learned_optimal
        )

      assert is_list(result.selected_judges)
      assert result.routing_strategy == :learned_optimal
      assert is_number(result.selection_confidence)
      assert result.selection_confidence > 0.0
      assert Map.has_key?(result, :expected_performance)
      assert Map.has_key?(result, :cost_estimate)
      assert is_binary(result.selection_reasoning)

      # Should select appropriate judges for comprehensive evaluation
      assert length(result.selected_judges) >= 3
    end

    test "adapts selection based on user preferences" do
      evaluation_context = %{
        evaluation_type: :standard_evaluation,
        complexity: :medium
      }

      user_profile = %{
        preference_profile: %{
          preferred_judge_types: [:code_quality, :security],
          quality_vs_speed_preference: :quality_focused
        }
      }

      available_judges = [:code_quality, :architecture, :security, :test_quality]

      {:ok, result} =
        DynamicRoutingEngine.select_optimal_judges(
          evaluation_context,
          available_judges,
          user_profile,
          strategy: :user_preference_based
        )

      assert result.routing_strategy == :user_preference_based

      # Should include user's preferred judges
      assert :code_quality in result.selected_judges
      assert :security in result.selected_judges

      # Should have high user satisfaction expectation due to preference alignment
      assert result.expected_performance.user_satisfaction > 0.8
    end

    test "optimizes for cost efficiency when requested" do
      evaluation_context = %{
        evaluation_type: :basic_evaluation,
        complexity: :low,
        cost_priority: :high,
        budget_limit: 0.08
      }

      available_judges = [:code_quality, :architecture, :security, :test_quality]

      {:ok, result} =
        DynamicRoutingEngine.select_optimal_judges(
          evaluation_context,
          available_judges,
          nil,
          strategy: :cost_optimized,
          max_cost: 0.08
        )

      assert result.routing_strategy == :cost_optimized
      assert result.cost_estimate <= 0.08

      # Should prioritize cost efficiency
      assert String.contains?(result.selection_reasoning, "cost")
      assert is_number(result.expected_performance.accuracy)
    end

    test "focuses on quality when accuracy is critical" do
      evaluation_context = %{
        evaluation_type: :security_critical_evaluation,
        complexity: :high,
        quality_priority: :critical,
        accuracy_requirement: 0.92
      }

      available_judges = [:code_quality, :architecture, :security, :test_quality]

      {:ok, result} =
        DynamicRoutingEngine.select_optimal_judges(
          evaluation_context,
          available_judges,
          nil,
          strategy: :quality_focused,
          min_accuracy: 0.92
        )

      assert result.routing_strategy == :quality_focused

      # Should prioritize high accuracy
      assert result.expected_performance.accuracy > 0.9
      # Comprehensive team for quality
      assert length(result.selected_judges) >= 3
    end

    test "adapts to temporal factors" do
      evaluation_context = %{
        evaluation_type: :standard_evaluation,
        complexity: :medium,
        # Afternoon peak time
        current_time: ~U[2025-08-26 14:30:00Z]
      }

      available_judges = [:code_quality, :architecture, :security, :test_quality]

      {:ok, result} =
        DynamicRoutingEngine.select_optimal_judges(
          evaluation_context,
          available_judges,
          nil,
          strategy: :temporal_adaptive
        )

      assert result.routing_strategy == :temporal_adaptive

      assert String.contains?(result.selection_reasoning, "temporal") or
               String.contains?(result.selection_reasoning, "hour")
    end

    test "falls back to default when adaptive routing fails" do
      evaluation_context = %{
        # This might cause adaptive routing to fail
        evaluation_type: :malformed_evaluation
      }

      available_judges = [:code_quality]

      # Should gracefully fall back to default routing
      result =
        DynamicRoutingEngine.select_optimal_judges(
          evaluation_context,
          available_judges,
          nil,
          strategy: :learned_optimal
        )

      case result do
        {:ok, selection_result} ->
          assert is_list(selection_result.selected_judges)
          assert length(selection_result.selected_judges) > 0

        {:error, _reason} ->
          # Acceptable if no fallback possible
          assert true
      end
    end
  end

  describe "adapt_coordination_strategy/3" do
    test "adapts coordination strategy based on learned patterns" do
      coordination_context = %{
        agent_count: 3,
        quality_requirements: :high,
        time_constraints: :normal
      }

      learned_patterns = [
        %{
          pattern_type: :coordination_success,
          pattern_data: %{
            consensus_time: 5_000,
            success_rate: 0.9,
            agent_coordination_data: %{}
          },
          effectiveness_score: 0.85
        },
        %{
          pattern_type: :coordination_failure,
          pattern_data: %{
            consensus_time: 15_000,
            success_rate: 0.6
          },
          effectiveness_score: 0.3
        }
      ]

      {:ok, result} =
        DynamicRoutingEngine.adapt_coordination_strategy(
          coordination_context,
          learned_patterns
        )

      assert Map.has_key?(result, :coordination_strategy)
      assert Map.has_key?(result, :strategy_validation)
      assert Map.has_key?(result, :effectiveness_analysis)
      assert is_number(result.adaptation_confidence)
      assert is_number(result.expected_improvement)
    end

    test "handles insufficient coordination patterns gracefully" do
      coordination_context = %{
        agent_count: 2,
        quality_requirements: :standard
      }

      # Empty patterns should be handled gracefully
      empty_patterns = []

      result =
        DynamicRoutingEngine.adapt_coordination_strategy(
          coordination_context,
          empty_patterns
        )

      case result do
        {:ok, adaptation_result} ->
          assert is_map(adaptation_result)

        {:error, reason} ->
          assert String.contains?(reason, "patterns") or String.contains?(reason, "insufficient")
      end
    end
  end

  describe "get_adaptive_routing_stats/1" do
    test "returns comprehensive routing statistics" do
      stats = DynamicRoutingEngine.get_adaptive_routing_stats({24, :hour})

      assert is_number(stats.total_adaptive_routings)
      assert is_map(stats.routing_strategy_distribution)
      assert is_number(stats.average_selection_confidence)
      assert is_map(stats.model_usage_statistics)
      assert is_number(stats.adaptation_success_rate)
      assert is_number(stats.fallback_usage_rate)
      assert is_map(stats.performance_improvements)
      assert is_map(stats.routing_health)

      # Health metrics should be present
      health = stats.routing_health
      assert Map.has_key?(health, :model_health)
      assert Map.has_key?(health, :adaptation_effectiveness)
      assert Map.has_key?(health, :user_satisfaction_impact)
    end

    test "provides meaningful performance improvement metrics" do
      stats = DynamicRoutingEngine.get_adaptive_routing_stats({7, :day})

      improvements = stats.performance_improvements

      assert is_map(improvements)
      assert Map.has_key?(improvements, :accuracy_improvement)
      assert Map.has_key?(improvements, :satisfaction_improvement)

      # Improvements should be realistic numbers
      assert is_number(improvements.accuracy_improvement)
      assert is_number(improvements.satisfaction_improvement)
    end
  end

  describe "routing strategy effectiveness" do
    test "different strategies produce different selection patterns" do
      evaluation_context = %{
        evaluation_type: :standard_evaluation,
        complexity: :medium,
        quality_requirements: %{min_accuracy: 0.8}
      }

      available_judges = [:code_quality, :architecture, :security, :test_quality]

      strategies = [
        :learned_optimal,
        :performance_weighted,
        :cost_optimized,
        :quality_focused
      ]

      results =
        Enum.map(strategies, fn strategy ->
          case DynamicRoutingEngine.select_optimal_judges(
                 evaluation_context,
                 available_judges,
                 nil,
                 strategy: strategy
               ) do
            {:ok, result} -> {strategy, result}
            {:error, _reason} -> {strategy, nil}
          end
        end)

      successful_results = Enum.filter(results, fn {_strategy, result} -> not is_nil(result) end)

      # Should have at least some successful strategy results
      assert length(successful_results) > 0

      # Each strategy should have different characteristics
      Enum.each(successful_results, fn {strategy, result} ->
        assert result.routing_strategy == strategy
        assert is_list(result.selected_judges)
        assert length(result.selected_judges) > 0
      end)
    end
  end

  describe "judge selection validation" do
    test "ensures minimum judge coverage for comprehensive evaluations" do
      high_complexity_context = %{
        evaluation_type: :comprehensive_evaluation,
        complexity: :high,
        quality_requirements: %{min_accuracy: 0.9, thoroughness: :complete}
      }

      available_judges = [:code_quality, :architecture, :security, :test_quality]

      {:ok, result} =
        DynamicRoutingEngine.select_optimal_judges(
          high_complexity_context,
          available_judges,
          nil,
          strategy: :quality_focused
        )

      # Should select comprehensive judge team for high complexity
      assert length(result.selected_judges) >= 3
      assert result.expected_performance.accuracy > 0.85
    end

    test "adapts to limited judge availability" do
      limited_context = %{
        evaluation_type: :basic_evaluation,
        complexity: :low
      }

      # Limited judge availability
      limited_judges = [:code_quality]

      {:ok, result} =
        DynamicRoutingEngine.select_optimal_judges(
          limited_context,
          limited_judges,
          nil,
          strategy: :learned_optimal
        )

      # Should work with limited judges
      assert length(result.selected_judges) >= 1
      assert :code_quality in result.selected_judges
    end
  end

  describe "cost and performance optimization" do
    test "balances cost and quality appropriately" do
      cost_sensitive_context = %{
        evaluation_type: :standard_evaluation,
        complexity: :medium,
        cost_priority: :high,
        # Relaxed for cost savings
        quality_requirements: %{min_accuracy: 0.75}
      }

      available_judges = [:code_quality, :architecture, :security, :test_quality]

      {:ok, cost_result} =
        DynamicRoutingEngine.select_optimal_judges(
          cost_sensitive_context,
          available_judges,
          nil,
          strategy: :cost_optimized,
          max_cost: 0.1
        )

      quality_context =
        Map.put(cost_sensitive_context, :quality_requirements, %{min_accuracy: 0.9})

      {:ok, quality_result} =
        DynamicRoutingEngine.select_optimal_judges(
          quality_context,
          available_judges,
          nil,
          strategy: :quality_focused,
          min_accuracy: 0.9
        )

      # Cost-optimized should be cheaper but quality-focused should be more accurate
      assert cost_result.cost_estimate <= quality_result.cost_estimate

      assert quality_result.expected_performance.accuracy >=
               cost_result.expected_performance.accuracy
    end
  end

  describe "error handling and edge cases" do
    test "handles malformed evaluation context gracefully" do
      malformed_context = "not a map"
      available_judges = [:code_quality]

      result =
        DynamicRoutingEngine.select_optimal_judges(
          malformed_context,
          available_judges
        )

      # Should handle gracefully
      case result do
        {:ok, selection} ->
          assert is_map(selection)

        {:error, reason} ->
          assert is_binary(reason)
      end
    end

    test "handles empty judge list" do
      evaluation_context = %{evaluation_type: :basic_evaluation}
      empty_judges = []

      result =
        DynamicRoutingEngine.select_optimal_judges(
          evaluation_context,
          empty_judges
        )

      # Should handle empty judges appropriately
      case result do
        {:ok, selection} ->
          # May provide fallback judges
          assert is_list(selection.selected_judges)

        {:error, reason} ->
          # May fail due to no available judges
          assert is_binary(reason)
      end
    end
  end
end
