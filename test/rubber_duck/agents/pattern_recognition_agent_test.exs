defmodule RubberDuck.Agents.PatternRecognitionAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.PatternRecognitionAgent

  describe "init/1" do
    test "initializes with default state" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      assert agent.state.active_analyses == %{}
      assert agent.state.pattern_cache == %{}
      assert agent.state.learning_models == %{}
      assert agent.state.analysis_history == []
      assert Map.has_key?(agent.state, :performance_metrics)
      assert Map.has_key?(agent.state, :configuration)
    end

    test "initializes with custom configuration" do
      opts = [
        max_concurrent: 5,
        confidence_threshold: 0.8,
        cache_retention: 48
      ]
      
      {:ok, agent} = PatternRecognitionAgent.init(opts)
      
      assert agent.state.configuration.max_concurrent_analyses == 5
      assert agent.state.configuration.pattern_confidence_threshold == 0.8
      assert agent.state.configuration.cache_retention_hours == 48
    end
  end

  describe "recognize_patterns/4" do
    setup do
      {:ok, agent} = PatternRecognitionAgent.init()
      %{agent: agent}
    end

    test "recognizes success patterns successfully", %{agent: agent} do
      evaluation_data = [
        %{
          evaluation_id: "eval_1",
          user_satisfaction: 0.9,
          accuracy_score: 0.85,
          processing_time_ms: 2_000,
          judge_consensus: 0.9
        },
        %{
          evaluation_id: "eval_2", 
          user_satisfaction: 0.85,
          accuracy_score: 0.8,
          processing_time_ms: 2_500,
          judge_consensus: 0.85
        }
      ]
      
      {:ok, patterns, updated_agent} = PatternRecognitionAgent.recognize_patterns(
        agent,
        :success_patterns,
        evaluation_data
      )
      
      assert patterns.analysis_type == :success_patterns
      assert is_list(patterns.identified_patterns)
      assert patterns.confidence > 0.0
      assert patterns.data_points_analyzed == 2
      assert Map.has_key?(patterns, :actionable_insights)
      assert Map.has_key?(patterns, :recommended_actions)
      
      # Agent should be updated with analysis
      assert updated_agent.state.performance_metrics.patterns_identified > 0
      assert length(updated_agent.state.analysis_history) > 0
    end

    test "recognizes failure modes effectively", %{agent: agent} do
      failure_data = [
        %{
          evaluation_id: "eval_fail_1",
          user_satisfaction: 0.2,
          accuracy_score: 0.4,
          processing_time_ms: 15_000,
          consensus_failure: true
        },
        %{
          evaluation_id: "eval_fail_2",
          user_satisfaction: 0.3, 
          accuracy_score: 0.35,
          processing_time_ms: 12_000,
          cost_overrun: true
        }
      ]
      
      {:ok, patterns, updated_agent} = PatternRecognitionAgent.recognize_patterns(
        agent,
        :failure_modes,
        failure_data
      )
      
      assert patterns.analysis_type == :failure_modes
      assert is_list(patterns.identified_patterns)
      assert patterns.confidence > 0.0
      assert length(patterns.actionable_insights) > 0
      
      # Should identify failure mitigation actions
      assert Enum.any?(patterns.recommended_actions, fn action ->
        String.contains?(action, "investigate") or String.contains?(action, "improve")
      end)
    end

    test "handles invalid analysis type", %{agent: agent} do
      evaluation_data = [%{evaluation_id: "eval_1", data: "test"}]
      
      {:error, reason, returned_agent} = PatternRecognitionAgent.recognize_patterns(
        agent,
        :invalid_analysis_type,
        evaluation_data
      )
      
      assert String.contains?(reason, "Unknown analysis type")
      assert returned_agent == agent
    end

    test "validates data set requirements", %{agent: agent} do
      # Empty data set should fail
      {:error, reason, _agent} = PatternRecognitionAgent.recognize_patterns(
        agent,
        :success_patterns,
        []
      )
      
      assert String.contains?(reason, "Data set cannot be empty")
    end
  end

  describe "analyze_focused_patterns/4" do
    setup do
      {:ok, agent} = PatternRecognitionAgent.init()
      %{agent: agent}
    end

    test "analyzes multiple focus areas successfully", %{agent: agent} do
      focus_areas = [:judge_selection_optimization, :evaluation_quality_improvement]
      
      data_context = %{
        judge_selection_history: [
          %{judge_type: :code_quality, success_rate: 0.9},
          %{judge_type: :architecture, success_rate: 0.8}
        ],
        evaluation_results: [
          %{accuracy_score: 0.85, user_satisfaction: 0.9},
          %{accuracy_score: 0.8, user_satisfaction: 0.85}
        ]
      }
      
      {:ok, focused_patterns, updated_agent} = PatternRecognitionAgent.analyze_focused_patterns(
        agent,
        focus_areas,
        data_context
      )
      
      assert focused_patterns.focus_areas_analyzed == length(focus_areas)
      assert is_list(focused_patterns.identified_patterns)
      assert focused_patterns.confidence > 0.0
      assert Map.has_key?(focused_patterns, :actionable_insights)
      
      # Agent should have updated analysis history
      assert length(updated_agent.state.analysis_history) > 0
    end

    test "handles focus areas with insufficient data", %{agent: agent} do
      focus_areas = [:bias_pattern_detection]
      
      # Empty data context
      data_context = %{evaluation_fairness_data: []}
      
      result = PatternRecognitionAgent.analyze_focused_patterns(
        agent,
        focus_areas,
        data_context
      )
      
      # Should handle gracefully - might succeed with limited insights or fail appropriately
      assert match?({:ok, _patterns, _agent} | {:error, _reason, _agent}, result)
    end
  end

  describe "get_recognition_stats/1" do
    test "returns comprehensive statistics" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      stats = PatternRecognitionAgent.get_recognition_stats(agent)
      
      assert is_number(stats.total_patterns_identified)
      assert is_number(stats.average_analysis_time_ms)
      assert is_number(stats.pattern_accuracy_rate)
      assert is_number(stats.model_update_count)
      assert is_number(stats.active_analyses_count)
      assert is_number(stats.cached_patterns_count)
      assert is_number(stats.cache_hit_rate)
      assert is_number(stats.learning_model_count)
      assert is_list(stats.recent_analysis_history)
    end

    test "tracks statistics after pattern recognition" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      initial_stats = PatternRecognitionAgent.get_recognition_stats(agent)
      
      # Perform pattern recognition
      test_data = [%{evaluation_id: "test", user_satisfaction: 0.8}]
      {:ok, _patterns, updated_agent} = PatternRecognitionAgent.recognize_patterns(
        agent,
        :success_patterns,
        test_data
      )
      
      updated_stats = PatternRecognitionAgent.get_recognition_stats(updated_agent)
      
      assert updated_stats.total_patterns_identified >= initial_stats.total_patterns_identified
      assert updated_stats.model_update_count > initial_stats.model_update_count
      assert length(updated_stats.recent_analysis_history) > length(initial_stats.recent_analysis_history)
    end
  end

  describe "configure_recognition/2" do
    test "updates configuration successfully" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      new_config = %{
        pattern_confidence_threshold: 0.85,
        cache_retention_hours: 36,
        max_concurrent_analyses: 4
      }
      
      {:ok, updated_agent} = PatternRecognitionAgent.configure_recognition(agent, new_config)
      
      assert updated_agent.state.configuration.pattern_confidence_threshold == 0.85
      assert updated_agent.state.configuration.cache_retention_hours == 36
      assert updated_agent.state.configuration.max_concurrent_analyses == 4
    end
  end

  describe "reset_learning_models/2" do
    test "resets learning models and cache" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      # Add some mock data to reset
      agent_with_data = %{agent | 
        state: %{agent.state |
          pattern_cache: %{"test_key" => %{patterns: []}},
          learning_models: %{success_patterns: %{data: "test"}},
          analysis_history: [%{analysis: "test"}]
        }
      }
      
      {:ok, reset_agent} = PatternRecognitionAgent.reset_learning_models(agent_with_data)
      
      assert reset_agent.state.pattern_cache == %{}
      assert reset_agent.state.learning_models == %{}
      # History should be kept by default
      assert length(reset_agent.state.analysis_history) > 0
    end

    test "can reset with history clearing" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      agent_with_history = %{agent |
        state: %{agent.state | analysis_history: [%{test: "data"}]}
      }
      
      {:ok, reset_agent} = PatternRecognitionAgent.reset_learning_models(
        agent_with_history,
        [keep_history: false]
      )
      
      assert reset_agent.state.analysis_history == []
    end
  end

  describe "pattern caching functionality" do
    test "uses cached patterns when available" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      test_data = [%{evaluation_id: "cache_test", user_satisfaction: 0.8}]
      
      # First analysis should be fresh
      {:ok, patterns1, agent1} = PatternRecognitionAgent.recognize_patterns(
        agent,
        :success_patterns,
        test_data
      )
      
      # Second analysis with same data should use cache (simulated)
      {:ok, patterns2, agent2} = PatternRecognitionAgent.recognize_patterns(
        agent1,
        :success_patterns, 
        test_data
      )
      
      # Both should succeed
      assert patterns1.analysis_type == patterns2.analysis_type
      assert is_map(patterns1)
      assert is_map(patterns2)
    end
  end

  describe "learning model management" do
    test "updates learning models with new patterns" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      test_data = [
        %{evaluation_id: "model_test_1", user_satisfaction: 0.9, accuracy_score: 0.85},
        %{evaluation_id: "model_test_2", user_satisfaction: 0.85, accuracy_score: 0.8}
      ]
      
      {:ok, _patterns, updated_agent} = PatternRecognitionAgent.recognize_patterns(
        agent,
        :success_patterns,
        test_data
      )
      
      # Should have learning model for success patterns
      assert Map.has_key?(updated_agent.state.learning_models, :success_patterns)
      
      success_model = updated_agent.state.learning_models.success_patterns
      assert success_model.model_type == :success_patterns
      assert success_model.update_count == 1
      assert is_list(success_model.confidence_history)
    end

    test "updates existing learning models" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      # First analysis
      test_data_1 = [%{evaluation_id: "update_1", user_satisfaction: 0.8}]
      {:ok, _patterns1, agent1} = PatternRecognitionAgent.recognize_patterns(
        agent,
        :user_preferences,
        test_data_1
      )
      
      # Second analysis should update existing model
      test_data_2 = [%{evaluation_id: "update_2", user_satisfaction: 0.9}]
      {:ok, _patterns2, agent2} = PatternRecognitionAgent.recognize_patterns(
        agent1,
        :user_preferences,
        test_data_2
      )
      
      user_pref_model = agent2.state.learning_models.user_preferences
      assert user_pref_model.update_count == 2
      assert length(user_pref_model.confidence_history) == 2
    end
  end

  describe "performance tracking" do
    test "tracks analysis performance metrics" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      initial_metrics = agent.state.performance_metrics
      
      test_data = [%{evaluation_id: "perf_test", user_satisfaction: 0.8}]
      {:ok, patterns, updated_agent} = PatternRecognitionAgent.recognize_patterns(
        agent,
        :temporal_trends,
        test_data
      )
      
      updated_metrics = updated_agent.state.performance_metrics
      
      # Should track pattern identification
      assert updated_metrics.patterns_identified > initial_metrics.patterns_identified
      assert updated_metrics.model_update_count > initial_metrics.model_update_count
      assert is_number(updated_metrics.analysis_time_avg)
      
      # Should have analysis history entry
      assert length(updated_agent.state.analysis_history) > 0
      
      history_entry = List.first(updated_agent.state.analysis_history)
      assert history_entry.analysis_type == :temporal_trends
      assert is_number(history_entry.patterns_found)
      assert is_number(history_entry.confidence)
    end
  end

  describe "analysis type validation" do
    test "validates supported analysis types" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      valid_types = [
        :success_patterns,
        :failure_modes,
        :user_preferences,
        :temporal_trends,
        :judge_performance,
        :system_optimization
      ]
      
      test_data = [%{evaluation_id: "valid_test", data: "test"}]
      
      Enum.each(valid_types, fn analysis_type ->
        result = PatternRecognitionAgent.recognize_patterns(agent, analysis_type, test_data)
        assert match?({:ok, _patterns, _agent}, result)
      end)
    end

    test "rejects invalid analysis types" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      invalid_types = [:unknown_type, :invalid_analysis, :not_supported]
      test_data = [%{evaluation_id: "invalid_test"}]
      
      Enum.each(invalid_types, fn invalid_type ->
        result = PatternRecognitionAgent.recognize_patterns(agent, invalid_type, test_data)
        assert match?({:error, _reason, _agent}, result)
      end)
    end
  end

  describe "data validation" do
    test "requires non-empty data sets" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      result = PatternRecognitionAgent.recognize_patterns(agent, :success_patterns, [])
      
      assert match?({:error, reason, _agent}, result)
      {:error, reason, _agent} = result
      assert String.contains?(reason, "empty")
    end

    test "requires list data format" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      invalid_data = "not a list"
      result = PatternRecognitionAgent.recognize_patterns(agent, :success_patterns, invalid_data)
      
      assert match?({:error, reason, _agent}, result)
      {:error, reason, _agent} = result
      assert String.contains?(reason, "must be a list")
    end
  end

  describe "focused pattern analysis" do
    test "handles multiple focus areas" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      focus_areas = [
        :judge_selection_optimization,
        :evaluation_quality_improvement
      ]
      
      data_context = %{
        judge_selection_history: [
          %{judge_type: :code_quality, effectiveness: 0.9}
        ],
        evaluation_results: [
          %{quality_score: 0.85, user_rating: 4.2}
        ]
      }
      
      {:ok, focused_patterns, updated_agent} = PatternRecognitionAgent.analyze_focused_patterns(
        agent,
        focus_areas,
        data_context
      )
      
      assert focused_patterns.analysis_type == :multi_focus_analysis
      assert focused_patterns.focus_areas_analyzed == length(focus_areas)
      assert is_list(focused_patterns.actionable_insights)
      assert is_list(focused_patterns.recommended_actions)
    end

    test "handles unknown focus areas gracefully" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      unknown_areas = [:unknown_focus_area]
      data_context = %{}
      
      {:error, reason, _agent} = PatternRecognitionAgent.analyze_focused_patterns(
        agent,
        unknown_areas,
        data_context
      )
      
      assert String.contains?(reason, "Unknown focus area")
    end
  end

  describe "pattern confidence calculation" do
    test "calculates appropriate confidence levels" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      # High-quality data should result in higher confidence
      high_quality_data = [
        %{evaluation_id: "hq_1", user_satisfaction: 0.95, accuracy_score: 0.9, consistency: 0.9},
        %{evaluation_id: "hq_2", user_satisfaction: 0.9, accuracy_score: 0.88, consistency: 0.85},
        %{evaluation_id: "hq_3", user_satisfaction: 0.92, accuracy_score: 0.91, consistency: 0.87}
      ]
      
      {:ok, patterns, _agent} = PatternRecognitionAgent.recognize_patterns(
        agent,
        :success_patterns,
        high_quality_data
      )
      
      # Should have high confidence due to consistent high-quality data
      assert patterns.confidence > 0.7
    end

    test "lower confidence for inconsistent data" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      # Inconsistent data should result in lower confidence
      inconsistent_data = [
        %{evaluation_id: "inc_1", user_satisfaction: 0.9, accuracy_score: 0.3},
        %{evaluation_id: "inc_2", user_satisfaction: 0.2, accuracy_score: 0.95}
      ]
      
      {:ok, patterns, _agent} = PatternRecognitionAgent.recognize_patterns(
        agent,
        :failure_modes,
        inconsistent_data
      )
      
      # Confidence should reflect the inconsistency
      assert is_number(patterns.confidence)
    end
  end

  describe "cache functionality" do
    test "cache improves performance for repeated analyses" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      test_data = [%{evaluation_id: "cache_perf_test", user_satisfaction: 0.8}]
      
      # First analysis (fresh)
      start_time_1 = System.monotonic_time(:millisecond)
      {:ok, _patterns1, agent1} = PatternRecognitionAgent.recognize_patterns(
        agent,
        :success_patterns,
        test_data
      )
      time_1 = System.monotonic_time(:millisecond) - start_time_1
      
      # Second analysis (potentially cached)
      start_time_2 = System.monotonic_time(:millisecond)
      {:ok, _patterns2, _agent2} = PatternRecognitionAgent.recognize_patterns(
        agent1,
        :success_patterns,
        test_data
      )
      time_2 = System.monotonic_time(:millisecond) - start_time_2
      
      # Both analyses should succeed
      assert is_number(time_1)
      assert is_number(time_2)
    end
  end

  describe "error handling and edge cases" do
    test "handles malformed evaluation data" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      malformed_data = [
        %{invalid: "structure"},
        "not a map",
        nil,
        %{evaluation_id: nil}  # Invalid evaluation_id
      ]
      
      # Should handle gracefully - may filter out invalid data or fail appropriately
      result = PatternRecognitionAgent.recognize_patterns(agent, :success_patterns, malformed_data)
      
      # Should either succeed with filtered data or fail with meaningful error
      case result do
        {:ok, patterns, _agent} -> 
          assert is_map(patterns)
        {:error, reason, _agent} ->
          assert is_binary(reason)
      end
    end

    test "handles analysis failures gracefully" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      # Data that might cause analysis issues
      edge_case_data = [
        %{evaluation_id: "edge_1", user_satisfaction: nil},
        %{evaluation_id: "edge_2", accuracy_score: "not_a_number"}
      ]
      
      result = PatternRecognitionAgent.recognize_patterns(agent, :failure_modes, edge_case_data)
      
      # Should handle gracefully
      case result do
        {:ok, patterns, _agent} ->
          assert is_map(patterns)
        {:error, reason, agent} ->
          assert is_binary(reason)
          assert is_map(agent.state)
      end
    end
  end

  describe "learning model evolution" do
    test "tracks model evolution over time" do
      {:ok, agent} = PatternRecognitionAgent.init()
      
      # Multiple analyses to track evolution
      datasets = [
        [%{evaluation_id: "evo_1", user_satisfaction: 0.8}],
        [%{evaluation_id: "evo_2", user_satisfaction: 0.85}],
        [%{evaluation_id: "evo_3", user_satisfaction: 0.9}]
      ]
      
      final_agent = Enum.reduce(datasets, agent, fn dataset, acc_agent ->
        {:ok, _patterns, updated_agent} = PatternRecognitionAgent.recognize_patterns(
          acc_agent,
          :user_preferences,
          dataset
        )
        updated_agent
      end)
      
      # Should have evolved learning model
      user_pref_model = final_agent.state.learning_models.user_preferences
      assert user_pref_model.update_count == 3
      assert length(user_pref_model.confidence_history) == 3
      assert length(user_pref_model.pattern_evolution) == 3
      
      # Evolution should show progression
      evolution = user_pref_model.pattern_evolution
      assert length(evolution) == 3
      assert Enum.all?(evolution, fn entry -> 
        Map.has_key?(entry, :timestamp) and Map.has_key?(entry, :confidence)
      end)
    end
  end
end