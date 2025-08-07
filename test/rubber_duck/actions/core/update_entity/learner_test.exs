defmodule RubberDuck.Actions.Core.UpdateEntity.LearnerTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Actions.Core.UpdateEntity.Learner

  describe "learn/2" do
    setup do
      entity = %{
        id: "test-123",
        type: :user,
        version: 5,
        email: "user@example.com"
      }

      impact_assessment = %{
        impact_score: 0.6,
        risk_assessment: %{
          identified_risks: [{:data_loss, :medium}, {:consistency, :low}],
          risk_level: :medium
        },
        performance_impact: %{
          expected_latency_change: "10-100ms"
        },
        affected_entities: [:sessions, :preferences]
      }

      execution_result = %{
        success: true,
        entity: entity,
        actual_impact_score: 0.65,
        execution_time: 45,
        memory_usage: 500_000,
        affected_entities: [:sessions]
      }

      params = %{
        entity: entity,
        impact_assessment: impact_assessment,
        execution_result: execution_result
      }

      {:ok, params: params, entity: entity}
    end

    test "successfully learns from update outcome", %{params: params} do
      assert {:ok, result} = Learner.learn(params, %{})
      assert result.learning_id != nil
      assert result.learning_data != nil
      assert is_float(result.confidence_score)
      assert result.confidence_score >= 0 and result.confidence_score <= 1
    end

    test "tracks outcome correctly", %{params: params} do
      {:ok, result} = Learner.learn(params, %{})
      outcome = result.learning_data.outcome_tracking

      assert outcome.entity_id == "test-123"
      assert outcome.entity_type == :user
      assert outcome.update_success == true
      assert is_map(outcome.performance_metrics)
      assert is_map(outcome.actual_impact)
    end

    test "analyzes patterns", %{params: params} do
      {:ok, result} = Learner.learn(params, %{})
      patterns = result.learning_data.pattern_analysis

      assert Map.has_key?(patterns, :success_patterns)
      assert Map.has_key?(patterns, :failure_patterns)
      assert Map.has_key?(patterns, :impact_patterns)
      assert Map.has_key?(patterns, :temporal_patterns)
      assert Map.has_key?(patterns, :correlation_analysis)
    end

    test "measures prediction accuracy", %{params: params} do
      {:ok, result} = Learner.learn(params, %{})
      accuracy = result.learning_data.accuracy_measurement

      assert Map.has_key?(accuracy, :impact_accuracy)
      assert Map.has_key?(accuracy, :risk_accuracy)
      assert Map.has_key?(accuracy, :performance_accuracy)
      assert Map.has_key?(accuracy, :overall_accuracy)
      assert accuracy.overall_accuracy >= 0 and accuracy.overall_accuracy <= 100
    end

    test "determines model updates when needed", %{params: params} do
      # Simulate poor prediction accuracy
      params = put_in(params.execution_result.actual_impact_score, 0.2)

      {:ok, result} = Learner.learn(params, %{})
      model_updates = result.learning_data.model_updates

      assert is_map(model_updates)
      assert Map.has_key?(model_updates, :prediction_model_updates)
      assert Map.has_key?(model_updates, :risk_model_updates)
    end
  end

  describe "track_outcome/2" do
    test "tracks successful update outcome" do
      entity = %{id: "test-123", type: :project}

      execution_result = %{
        success: true,
        entity: %{metadata: %{change_count: 3}},
        execution_time: 25,
        memory_usage: 100_000
      }

      outcome = Learner.track_outcome(entity, execution_result)

      assert outcome.entity_id == "test-123"
      assert outcome.entity_type == :project
      assert outcome.update_success == true
      assert outcome.changes_applied == 3
      assert outcome.performance_metrics.execution_time == 25
    end

    test "tracks failed update outcome" do
      entity = %{id: "test-456", type: :user}

      execution_result = %{
        success: false,
        errors: ["validation error", "constraint violation"]
      }

      outcome = Learner.track_outcome(entity, execution_result)

      assert outcome.update_success == false
      assert outcome.actual_impact.error_rate_change > 0
    end

    test "identifies side effects" do
      entity = %{id: "test", type: :user, audit_trail: []}

      execution_result = %{
        cache_invalidated: true,
        indexes_updated: true
      }

      outcome = Learner.track_outcome(entity, execution_result)

      assert :cache_invalidation in outcome.side_effects
      assert :index_update in outcome.side_effects
      assert :audit_logged in outcome.side_effects
    end
  end

  describe "analyze_patterns/3" do
    test "identifies success patterns" do
      entity = %{type: :user}
      impact_assessment = %{impact_score: 0.5}

      execution_result = %{
        success: true,
        validation_bypassed: false,
        batch_size: 5
      }

      patterns = Learner.analyze_patterns(entity, impact_assessment, execution_result)

      assert {:validation_success, :user} in patterns.success_patterns
      assert {:batch_success, 5} in patterns.success_patterns
      assert {:critical_entity_success, :user} in patterns.success_patterns
    end

    test "identifies failure patterns" do
      entity = %{type: :project}
      impact_assessment = %{}

      execution_result = %{
        validation_errors: ["error1", "error2"],
        constraint_violations: [:unique_constraint],
        timeout: true
      }

      patterns = Learner.analyze_patterns(entity, impact_assessment, execution_result)

      assert {:validation_failure, 2} in patterns.failure_patterns
      assert {:constraint_violation, [:unique_constraint]} in patterns.failure_patterns
      assert {:timeout_failure, :project} in patterns.failure_patterns
    end

    test "analyzes impact patterns" do
      entity = %{type: :user}

      impact_assessment = %{
        impact_score: 0.5,
        risk_assessment: %{
          identified_risks: [{:data_loss, :high}]
        }
      }

      execution_result = %{
        actual_impact_score: 0.7,
        failures: [:data_loss]
      }

      patterns = Learner.analyze_patterns(entity, impact_assessment, execution_result)

      assert_in_delta patterns.impact_patterns.prediction_delta, 0.2, 0.01
      assert patterns.impact_patterns.impact_category == :high
      assert patterns.impact_patterns.risk_materialized == true
    end

    test "detects temporal patterns" do
      entity = %{version: 75}
      patterns = Learner.analyze_patterns(entity, %{}, %{})

      assert patterns.temporal_patterns.time_of_day in [:morning, :afternoon, :evening, :night]
      assert patterns.temporal_patterns.day_of_week in 1..7
      assert patterns.temporal_patterns.update_frequency == :high
      assert is_boolean(patterns.temporal_patterns.peak_period)
    end

    test "performs correlation analysis" do
      entity = %{type: :code_file}
      entity = Map.merge(entity, Enum.into(1..60, %{}, fn i -> {:"field_#{i}", i} end))

      impact_assessment = %{
        risk_assessment: %{
          identified_risks: [{:risk1, :high}, {:risk2, :high}, {:risk3, :high}]
        }
      }

      execution_result = %{
        actual_impact_score: 0.8,
        success: true,
        execution_time: 500
      }

      patterns = Learner.analyze_patterns(entity, impact_assessment, execution_result)
      correlations = patterns.correlation_analysis

      assert correlations.size_impact_correlation == :strong_positive
      assert correlations.complexity_success_correlation == :high_complexity_success
      assert is_map(correlations.type_performance_correlation)
    end
  end

  describe "measure_prediction_accuracy/2" do
    test "measures impact prediction accuracy" do
      impact_assessment = %{impact_score: 0.5}
      execution_result = %{actual_impact_score: 0.6}

      accuracy = Learner.measure_prediction_accuracy(impact_assessment, execution_result)

      assert accuracy.impact_accuracy.predicted_score == 0.5
      assert accuracy.impact_accuracy.actual_score == 0.6
      assert_in_delta accuracy.impact_accuracy.deviation, 0.1, 0.01
      assert accuracy.impact_accuracy.accuracy_percentage == 80.0
    end

    test "measures risk prediction accuracy" do
      impact_assessment = %{
        risk_assessment: %{
          identified_risks: [{:risk1, :high}, {:risk2, :medium}, {:risk3, :low}]
        }
      }

      execution_result = %{
        materialized_risks: [:risk1, :risk4]
      }

      accuracy = Learner.measure_prediction_accuracy(impact_assessment, execution_result)
      risk_accuracy = accuracy.risk_accuracy

      assert risk_accuracy.predicted_count == 3
      assert risk_accuracy.actual_count == 2
      assert risk_accuracy.precision == 1 / 3
      assert risk_accuracy.recall == 0.5
      assert risk_accuracy.f1_score > 0
    end

    test "measures performance prediction accuracy" do
      impact_assessment = %{
        performance_impact: %{
          expected_latency_change: "1-10ms"
        }
      }

      execution_result = %{execution_time: 7}

      accuracy = Learner.measure_prediction_accuracy(impact_assessment, execution_result)
      perf_accuracy = accuracy.performance_accuracy

      assert perf_accuracy.predicted_latency_ms == 5
      assert perf_accuracy.actual_latency_ms == 7
      assert perf_accuracy.within_threshold == true
    end

    test "calculates overall accuracy" do
      impact_assessment = %{
        impact_score: 0.5,
        risk_assessment: %{identified_risks: []},
        performance_impact: %{expected_latency_change: "< 1ms"},
        affected_entities: [:entity1, :entity2]
      }

      execution_result = %{
        actual_impact_score: 0.5,
        materialized_risks: [],
        execution_time: 0.8,
        affected_entities: [:entity1, :entity2]
      }

      accuracy = Learner.measure_prediction_accuracy(impact_assessment, execution_result)

      assert_in_delta accuracy.overall_accuracy, 100.0, 0.1
    end
  end

  describe "process_feedback/2" do
    test "processes user feedback" do
      params = %{}

      context = %{
        user_feedback: %{
          satisfaction: :satisfied,
          comments: ["Great performance"],
          reported_issues: []
        }
      }

      feedback = Learner.process_feedback(params, context)

      assert feedback.user_feedback.satisfaction == :satisfied
      assert "Great performance" in feedback.user_feedback.comments
      assert feedback.feedback_score >= 0.5
    end

    test "generates automated feedback for slow execution" do
      params = %{
        execution_result: %{
          execution_time: 1500,
          success: true
        }
      }

      feedback = Learner.process_feedback(params, %{})

      assert "Consider optimization for slow execution" in feedback.automated_feedback
    end

    test "generates feedback for high memory usage" do
      params = %{
        execution_result: %{
          memory_usage: 15_000_000,
          success: true
        }
      }

      feedback = Learner.process_feedback(params, %{})

      assert "High memory usage detected" in feedback.automated_feedback
    end

    test "calculates feedback score correctly" do
      params = %{
        execution_result: %{
          success: true,
          execution_time: 50
        }
      }

      context = %{
        user_feedback: %{
          satisfaction: :satisfied
        }
      }

      feedback = Learner.process_feedback(params, context)

      # Base: 0.5 + success: 0.2 + satisfied: 0.2 + fast: 0.1 = 1.0
      assert_in_delta feedback.feedback_score, 1.0, 0.01
    end
  end

  describe "determine_model_updates/2" do
    test "determines prediction model updates" do
      entity = %{type: :user}

      execution_result = %{
        prediction_error: 0.3,
        new_patterns: [{:pattern1, :data}]
      }

      updates = Learner.determine_model_updates(entity, execution_result)

      assert {:adjust_impact_weights, :user} in updates.prediction_model_updates
      assert {:add_pattern_recognition, [{:pattern1, :data}]} in updates.prediction_model_updates
    end

    test "determines risk model updates" do
      entity = %{}

      execution_result = %{
        unexpected_risks: [:new_risk_type],
        risk_overestimated: true
      }

      updates = Learner.determine_model_updates(entity, execution_result)

      assert {:add_risk_types, [:new_risk_type]} in updates.risk_model_updates
      assert {:lower_risk_threshold, 0.1} in updates.risk_model_updates
    end

    test "determines performance model updates" do
      entity = %{type: :project}

      execution_result = %{
        performance_deviation: 75,
        entity_type: :project
      }

      updates = Learner.determine_model_updates(entity, execution_result)

      assert {:recalibrate_performance_model, :project} in updates.performance_model_updates
    end

    test "determines pattern model updates" do
      entity = %{}

      execution_result = %{
        pattern_frequency: 6,
        pattern_misses: 11,
        pattern_id: :pattern_123
      }

      updates = Learner.determine_model_updates(entity, execution_result)

      assert {:strengthen_pattern, :pattern_123} in updates.pattern_model_updates
      assert {:weaken_pattern, :pattern_123} in updates.pattern_model_updates
    end
  end

  describe "generate_improvement_suggestions/1" do
    test "suggests caching for slow operations" do
      params = %{
        execution_result: %{execution_time: 600}
      }

      suggestions = Learner.generate_improvement_suggestions(params)

      assert "Consider caching frequently accessed data" in suggestions
    end

    test "suggests model review for low accuracy" do
      params = %{
        learning_data: %{accuracy: 0.6}
      }

      suggestions = Learner.generate_improvement_suggestions(params)

      assert "Review and update prediction models" in suggestions
    end

    test "suggests pattern optimization" do
      params = %{
        learning_data: %{pattern_count: 15}
      }

      suggestions = Learner.generate_improvement_suggestions(params)

      assert "Implement pattern-based optimization" in suggestions
    end

    test "suggests risk enhancement" do
      params = %{
        execution_result: %{risk_materialized: true}
      }

      suggestions = Learner.generate_improvement_suggestions(params)

      assert "Enhance risk assessment for similar operations" in suggestions
    end
  end

  describe "should_update_models?/1" do
    test "returns true when accuracy is low" do
      learning_data = %{
        outcome_tracking: %{success: true},
        accuracy_measurement: %{overall_accuracy: 70},
        pattern_analysis: %{success_patterns: [], failure_patterns: []},
        model_updates: %{}
      }

      assert Learner.should_update_models?(learning_data) == true
    end

    test "returns true when new patterns detected" do
      learning_data = %{
        outcome_tracking: %{success: true},
        accuracy_measurement: %{overall_accuracy: 90},
        pattern_analysis: %{
          success_patterns: [{:pattern1, :data}],
          failure_patterns: []
        },
        model_updates: %{}
      }

      assert Learner.should_update_models?(learning_data) == true
    end

    test "returns false when no updates needed" do
      learning_data = %{
        outcome_tracking: %{success: true},
        accuracy_measurement: %{overall_accuracy: 95},
        pattern_analysis: %{success_patterns: [], failure_patterns: []},
        model_updates: %{}
      }

      assert Learner.should_update_models?(learning_data) == false
    end
  end

  describe "track_failure/3" do
    test "tracks validation failure" do
      reason = {:error, "validation failed: field required"}

      params = %{
        entity: %{id: "test", type: :user},
        validated_changes: %{changes: %{field: "value"}},
        impact_assessment: %{
          impact_score: 0.3,
          risk_assessment: %{risk_level: :low}
        }
      }

      assert {:ok, result} = Learner.track_failure(reason, params, %{})
      assert result.failure_tracked == true
      assert result.failure_data.failure_category == :validation
      assert is_list(result.recommendations)
    end

    test "tracks constraint failure" do
      reason = {:error, "unique constraint violation"}

      params = %{
        entity: %{id: "test", type: :project},
        validated_changes: %{changes: %{}},
        impact_assessment: %{
          impact_score: 0.5,
          risk_assessment: %{risk_level: :medium}
        }
      }

      {:ok, result} = Learner.track_failure(reason, params, %{})

      assert result.failure_data.failure_category == :constraint
      assert :relax_constraints in result.insights.recovery_options
    end

    test "generates failure recommendations" do
      reason = {:error, "timeout exceeded"}

      params = %{
        entity: %{id: "test", type: :code_file},
        validated_changes: %{changes: %{}},
        impact_assessment: %{
          impact_score: 0.7,
          risk_assessment: %{risk_level: :high}
        }
      }

      {:ok, result} = Learner.track_failure(reason, params, %{})

      assert result.failure_data.failure_category == :timeout
      assert length(result.recommendations) > 0
      assert Enum.any?(result.recommendations, &String.contains?(&1, "performance"))
    end

    test "identifies failure patterns" do
      reason = {:error, "permission denied"}

      params = %{
        entity: %{id: "test", type: :user},
        validated_changes: %{changes: %{}},
        impact_assessment: %{
          impact_score: 0.2,
          risk_assessment: %{risk_level: :low}
        },
        rollback_on_failure: true
      }

      {:ok, result} = Learner.track_failure(reason, params, %{agent: :test_agent})

      assert result.failure_data.failure_category == :permission
      assert result.failure_data.recovery_attempted == true
      assert result.insights.failure_pattern == :access_control_issue
      assert :request_permission in result.insights.recovery_options
    end
  end

  describe "edge cases" do
    test "handles missing impact assessment" do
      params = %{
        entity: %{id: "test", type: :user},
        execution_result: %{success: true}
      }

      assert {:ok, result} = Learner.learn(params, %{})
      assert result.learning_data != nil
    end

    test "handles missing execution result" do
      params = %{
        entity: %{id: "test", type: :user},
        impact_assessment: %{impact_score: 0.5}
      }

      assert {:ok, result} = Learner.learn(params, %{})
      assert result.learning_data != nil
    end

    test "handles zero prediction values" do
      impact_assessment = %{
        impact_score: 0,
        risk_assessment: %{identified_risks: []},
        performance_impact: %{expected_latency_change: "< 1ms"},
        affected_entities: []
      }

      execution_result = %{
        actual_impact_score: 0,
        execution_time: 0
      }

      accuracy = Learner.measure_prediction_accuracy(impact_assessment, execution_result)

      assert accuracy.impact_accuracy.accuracy_percentage == 100.0
      assert accuracy.overall_accuracy >= 0
    end

    test "handles empty pattern lists" do
      entity = %{type: :unknown}
      patterns = Learner.analyze_patterns(entity, %{}, %{})

      assert patterns.success_patterns == []
      assert patterns.failure_patterns == []
    end
  end
end
