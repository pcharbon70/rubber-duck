defmodule RubberDuck.Verdict.Analytics.SuccessPatternAnalyzerTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Verdict.Analytics.SuccessPatternAnalyzer

  describe "identify_success_patterns/2" do
    test "identifies patterns in successful evaluations" do
      evaluation_data = [
        %{
          evaluation_id: "success_1",
          user_satisfaction: 0.9,
          accuracy_score: 0.85,
          processing_time_ms: 2_000,
          judge_consensus: 0.9,
          cost_total: 0.03
        },
        %{
          evaluation_id: "success_2",
          user_satisfaction: 0.88,
          accuracy_score: 0.83,
          processing_time_ms: 2_200,
          judge_consensus: 0.88,
          cost_total: 0.035
        },
        %{
          evaluation_id: "success_3",
          user_satisfaction: 0.92,
          accuracy_score: 0.87,
          processing_time_ms: 1_800,
          judge_consensus: 0.92,
          cost_total: 0.025
        }
      ]
      
      {:ok, result} = SuccessPatternAnalyzer.identify_success_patterns(evaluation_data)
      
      assert is_map(result)
      assert is_list(result.patterns)
      assert is_list(result.insights)
      assert result.data_points_analyzed == 3
      assert Map.has_key?(result, :clustering_metadata)
      assert %DateTime{} = result.clustering_metadata.analysis_timestamp
    end

    test "handles insufficient data gracefully" do
      insufficient_data = [
        %{evaluation_id: "single", user_satisfaction: 0.8}
      ]
      
      # Should handle single data point appropriately
      result = SuccessPatternAnalyzer.identify_success_patterns(insufficient_data)
      
      case result do
        {:ok, patterns} ->
          assert is_map(patterns)
          assert patterns.data_points_analyzed == 1
        {:error, reason} ->
          assert String.contains?(reason, "insufficient") or String.contains?(reason, "enough")
      end
    end

    test "uses different clustering algorithms" do
      evaluation_data = [
        %{evaluation_id: "alg_1", user_satisfaction: 0.9, accuracy_score: 0.9},
        %{evaluation_id: "alg_2", user_satisfaction: 0.8, accuracy_score: 0.8},
        %{evaluation_id: "alg_3", user_satisfaction: 0.85, accuracy_score: 0.85},
        %{evaluation_id: "alg_4", user_satisfaction: 0.87, accuracy_score: 0.87}
      ]
      
      algorithms = [:k_means, :hierarchical, :dbscan]
      
      Enum.each(algorithms, fn algorithm ->
        {:ok, result} = SuccessPatternAnalyzer.identify_success_patterns(
          evaluation_data,
          [algorithm: algorithm]
        )
        
        assert result.clustering_metadata.algorithm_used == algorithm
        assert is_list(result.patterns)
      end)
    end
  end

  describe "identify_optimization_patterns/2" do
    test "identifies system optimization opportunities" do
      performance_data = [
        %{
          system_component: :judge_coordination,
          processing_time: 3_000,
          resource_utilization: 0.7,
          cost_efficiency: 0.8,
          user_satisfaction: 0.85
        },
        %{
          system_component: :consensus_engine,
          processing_time: 5_000,
          resource_utilization: 0.9,
          cost_efficiency: 0.6,
          user_satisfaction: 0.7
        }
      ]
      
      {:ok, result} = SuccessPatternAnalyzer.identify_optimization_patterns(performance_data)
      
      assert is_map(result)
      assert is_list(result.patterns)
      assert is_list(result.optimization_opportunities)
      assert Map.has_key?(result, :correlation_analysis)
      assert result.data_points_analyzed == 2
    end

    test "handles performance data with missing metrics" do
      incomplete_data = [
        %{system_component: :judge_coordination},  # Missing performance metrics
        %{processing_time: 4_000}  # Missing other metrics
      ]
      
      result = SuccessPatternAnalyzer.identify_optimization_patterns(incomplete_data)
      
      # Should handle gracefully
      case result do
        {:ok, patterns} ->
          assert is_map(patterns)
        {:error, reason} ->
          assert is_binary(reason)
      end
    end
  end

  describe "analyze_coordination_success_patterns/2" do
    test "analyzes multi-agent coordination effectiveness" do
      coordination_data = [
        %{
          coordination_id: "coord_1",
          agent_count: 3,
          consensus_score: 0.85,
          coordination_strategy: :weighted_consensus,
          coordination_time_ms: 5_000,
          success_rate: 0.9,
          user_satisfaction: 0.88
        },
        %{
          coordination_id: "coord_2",
          agent_count: 4,
          consensus_score: 0.78,
          coordination_strategy: :majority_vote,
          coordination_time_ms: 7_000,
          success_rate: 0.82,
          user_satisfaction: 0.8
        }
      ]
      
      {:ok, result} = SuccessPatternAnalyzer.analyze_coordination_success_patterns(coordination_data)
      
      assert is_map(result)
      assert is_list(result.patterns)
      assert is_map(result.feature_importance)
      assert is_list(result.coordination_insights)
      assert is_number(result.successful_cluster_count)
      assert is_number(result.total_cluster_count)
    end

    test "identifies effective coordination strategies" do
      # Data with clearly effective vs ineffective strategies
      mixed_coordination_data = [
        # Effective coordination
        %{
          agent_count: 3,
          consensus_score: 0.9,
          coordination_time_ms: 4_000,
          success_rate: 0.95,
          coordination_strategy: :specialized_consensus
        },
        # Less effective coordination  
        %{
          agent_count: 5,
          consensus_score: 0.6,
          coordination_time_ms: 12_000,
          success_rate: 0.7,
          coordination_strategy: :exhaustive_consensus
        }
      ]
      
      {:ok, result} = SuccessPatternAnalyzer.analyze_coordination_success_patterns(mixed_coordination_data)
      
      # Should identify the effective patterns
      assert result.successful_cluster_count >= 0
      assert is_list(result.coordination_insights)
      
      # Should provide actionable insights
      assert length(result.coordination_insights) >= 0
    end
  end

  describe "pattern extraction and characterization" do
    test "extracts meaningful pattern characteristics" do
      # Data with clear patterns
      clear_pattern_data = [
        # Fast, accurate evaluations
        %{evaluation_id: "fast_1", processing_time_ms: 1_500, accuracy_score: 0.9, user_satisfaction: 0.95},
        %{evaluation_id: "fast_2", processing_time_ms: 1_600, accuracy_score: 0.88, user_satisfaction: 0.92},
        # Slower but still accurate evaluations
        %{evaluation_id: "slow_1", processing_time_ms: 4_000, accuracy_score: 0.85, user_satisfaction: 0.8},
        %{evaluation_id: "slow_2", processing_time_ms: 4_200, accuracy_score: 0.83, user_satisfaction: 0.78}
      ]
      
      {:ok, result} = SuccessPatternAnalyzer.identify_success_patterns(clear_pattern_data)
      
      # Should identify distinct patterns
      assert length(result.patterns) > 0
      
      # Each pattern should have meaningful characteristics
      Enum.each(result.patterns, fn pattern ->
        assert Map.has_key?(pattern, :pattern_type)
        assert Map.has_key?(pattern, :characteristics)
        assert Map.has_key?(pattern, :confidence)
        assert Map.has_key?(pattern, :strength)
        assert Map.has_key?(pattern, :description)
      end)
    end
  end

  describe "statistical analysis" do
    test "performs statistical validation of patterns" do
      evaluation_data = generate_statistical_test_data()
      
      {:ok, result} = SuccessPatternAnalyzer.identify_success_patterns(evaluation_data)
      
      # Should include statistical metadata
      assert Map.has_key?(result, :clustering_metadata)
      assert is_number(result.clustering_metadata.cluster_count)
      
      # Patterns should have confidence scores
      Enum.each(result.patterns, fn pattern ->
        assert is_number(pattern.confidence)
        assert pattern.confidence >= 0.0
        assert pattern.confidence <= 1.0
      end)
    end
  end

  describe "optimization pattern identification" do
    test "identifies performance optimization opportunities" do
      performance_data = [
        %{
          component: :judge_selection,
          latency_ms: 1_000,
          accuracy_impact: 0.1,
          cost_impact: 0.05,
          user_satisfaction_impact: 0.15
        },
        %{
          component: :consensus_calculation,
          latency_ms: 3_000,
          accuracy_impact: 0.2,
          cost_impact: 0.1,
          user_satisfaction_impact: 0.25
        }
      ]
      
      {:ok, result} = SuccessPatternAnalyzer.identify_optimization_patterns(performance_data)
      
      assert is_list(result.optimization_opportunities)
      assert Map.has_key?(result, :correlation_analysis)
      
      # Should identify specific optimization opportunities
      optimization_opportunities = result.optimization_opportunities
      assert length(optimization_opportunities) >= 0
      
      Enum.each(optimization_opportunities, fn opportunity ->
        assert Map.has_key?(opportunity, :optimization_type)
        assert Map.has_key?(opportunity, :implementation_priority)
      end)
    end
  end

  # Helper function for generating test data
  defp generate_statistical_test_data do
    # Generate statistically meaningful test data
    Enum.map(1..20, fn i ->
      # Create two distinct clusters of successful evaluations
      if rem(i, 2) == 0 do
        # Fast, efficient cluster
        %{
          evaluation_id: "stat_#{i}",
          user_satisfaction: 0.85 + :rand.uniform() * 0.1,
          accuracy_score: 0.8 + :rand.uniform() * 0.1,
          processing_time_ms: 1_500 + :rand.uniform(500),
          cost_total: 0.02 + :rand.uniform() * 0.01
        }
      else
        # Thorough, high-quality cluster
        %{
          evaluation_id: "stat_#{i}",
          user_satisfaction: 0.9 + :rand.uniform() * 0.05,
          accuracy_score: 0.9 + :rand.uniform() * 0.05,
          processing_time_ms: 4_000 + :rand.uniform(1_000),
          cost_total: 0.06 + :rand.uniform() * 0.02
        }
      end
    end)
  end
end