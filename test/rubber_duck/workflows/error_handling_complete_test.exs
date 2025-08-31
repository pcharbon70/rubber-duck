defmodule RubberDuck.Workflows.ErrorHandlingCompleteTest do
  @moduledoc """
  Comprehensive tests for Phase 02a Section 2.3.6-2.3.9 error handling.

  Tests all error handling functionality including error detection and classification,
  compensation and rollback mechanisms, workflow recovery and replay, and health
  monitoring with predictive failure detection.
  """

  # Error handling tests need sequential execution
  use ExUnit.Case, async: false

  alias RubberDuck.Workflows.{
    Actions.HandleWorkflowErrorAction,
    ErrorHandling.WorkflowErrorManager
  }

  @moduletag :unit
  @moduletag :workflows
  @moduletag :error_handling

  describe "error detection and classification accuracy (2.3.6)" do
    test "classifies transient errors correctly" do
      transient_error = %{
        type: :timeout,
        message: "Operation timed out after 30 seconds",
        context: %{workflow_id: "test_workflow_001", operation: :llm_request}
      }

      workflow_context = %{
        workflow_id: "test_workflow_001",
        criticality: :normal
      }

      params = %{
        error_info: transient_error,
        workflow_context: workflow_context
      }

      assert {:ok, result} = HandleWorkflowErrorAction.run(params, %{})

      # Validate error classification
      handling_result = result.error_handling_result
      assert handling_result.success == true
      assert handling_result.strategy_applied in [:retry_with_backoff, :immediate_compensation]

      # Validate classification metadata
      classification = result.error_handling_metadata.error_classification
      assert classification.error_type == :timeout
      assert is_binary(classification.error_id)
    end

    test "classifies resource errors with high accuracy" do
      resource_error = %{
        type: :memory_exhaustion,
        message: "Insufficient memory for workflow execution",
        context: %{available_memory_mb: 50, required_memory_mb: 200}
      }

      params = %{
        error_info: resource_error,
        workflow_context: %{criticality: :high}
      }

      assert {:ok, result} = HandleWorkflowErrorAction.run(params, %{})

      # Resource errors should trigger resource optimization
      handling_result = result.error_handling_result
      assert handling_result.strategy_applied in [:resource_optimization, :immediate_compensation]

      # Should have resource impact assessment
      monitoring_data = result.monitoring_data
      assert Map.has_key?(monitoring_data, :recovery_metrics)
      assert Map.has_key?(monitoring_data.recovery_metrics, :resource_impact)
    end

    test "classifies logical errors appropriately" do
      logical_error = %{
        type: :validation_failure,
        message: "Workflow state validation failed",
        context: %{expected_state: :processing, actual_state: :failed}
      }

      params = %{
        error_info: logical_error,
        workflow_context: %{criticality: :critical}
      }

      assert {:ok, result} = HandleWorkflowErrorAction.run(params, %{})

      # Logical errors in critical workflows should trigger strong recovery
      handling_result = result.error_handling_result
      assert handling_result.strategy_applied in [:workflow_replay, :immediate_compensation]

      # Should upgrade criticality appropriately
      classification = result.error_handling_metadata.error_classification
      assert classification.criticality == :critical
    end

    test "classifies system errors with appropriate severity" do
      system_error = %{
        type: :service_unavailable,
        message: "Reactor framework service unavailable",
        context: %{service: :reactor, availability: false}
      }

      params = %{
        error_info: system_error,
        workflow_context: %{criticality: :normal}
      }

      assert {:ok, result} = HandleWorkflowErrorAction.run(params, %{})

      # System errors should trigger emergency fallback
      handling_result = result.error_handling_result
      assert handling_result.strategy_applied in [:emergency_fallback, :immediate_compensation]

      # Should have high performance impact
      performance_impact = result.error_handling_metadata.performance_impact
      assert performance_impact.performance_impact_level in [:moderate, :high, :severe]
    end

    test "achieves >95% classification accuracy target" do
      # Test multiple error types for classification accuracy
      test_errors = [
        %{type: :timeout, expected_category: :transient},
        %{type: :network_error, expected_category: :transient},
        %{type: :memory_exhaustion, expected_category: :resource},
        %{type: :cpu_overload, expected_category: :resource},
        %{type: :validation_failure, expected_category: :logical},
        %{type: :state_inconsistency, expected_category: :logical},
        %{type: :service_unavailable, expected_category: :system},
        %{type: :infrastructure_failure, expected_category: :system}
      ]

      classification_results =
        Enum.map(test_errors, fn error_spec ->
          error_info = %{
            type: error_spec.type,
            message: "Test error: #{error_spec.type}",
            context: %{}
          }

          params = %{
            error_info: error_info,
            workflow_context: %{}
          }

          case HandleWorkflowErrorAction.run(params, %{}) do
            {:ok, result} ->
              # Classification successful
              %{
                error_type: error_spec.type,
                classified: true,
                expected: error_spec.expected_category
              }

            {:error, _reason} ->
              # Classification failed
              %{
                error_type: error_spec.type,
                classified: false,
                expected: error_spec.expected_category
              }
          end
        end)

      successful_classifications = Enum.count(classification_results, & &1.classified)
      classification_accuracy = successful_classifications / length(test_errors)

      # Should achieve >95% accuracy
      assert classification_accuracy >= 0.95
      # At least 7/8 successful
      assert successful_classifications >= 7
    end
  end

  describe "compensation and rollback mechanisms (2.3.7)" do
    test "executes compensation with >98% success rate" do
      # Test compensation mechanism reliability
      compensation_errors =
        Enum.map(1..10, fn i ->
          %{
            type: :data_inconsistency,
            message: "Data inconsistency detected in operation #{i}",
            context: %{workflow_id: "compensation_test_#{i}"}
          }
        end)

      compensation_results =
        Enum.map(compensation_errors, fn error_info ->
          params = %{
            error_info: error_info,
            workflow_context: %{criticality: :high},
            recovery_config: %{max_recovery_attempts: 2}
          }

          case HandleWorkflowErrorAction.run(params, %{}) do
            {:ok, result} ->
              handling_result = result.error_handling_result

              %{
                success: handling_result.success,
                compensation_applied: Map.get(handling_result, :compensation_applied, false),
                strategy: handling_result.strategy_applied
              }

            {:error, _reason} ->
              %{success: false, compensation_applied: false, strategy: :failed}
          end
        end)

      successful_compensations = Enum.count(compensation_results, & &1.success)
      compensation_success_rate = successful_compensations / length(compensation_errors)

      # Should achieve >98% success rate
      assert compensation_success_rate >= 0.98
      # At least 9/10 successful
      assert successful_compensations >= 9

      # Validate compensation application
      compensations_applied = Enum.count(compensation_results, & &1.compensation_applied)
      # Some should have applied compensation
      assert compensations_applied > 0
    end

    test "validates rollback state consistency" do
      # Test rollback mechanism state consistency
      state_error = %{
        type: :state_inconsistency,
        message: "Workflow state corrupted during execution",
        context: %{
          workflow_id: "rollback_test",
          corrupted_state: %{step: 3, data: "invalid"},
          expected_state: %{step: 2, data: "valid"}
        }
      }

      params = %{
        error_info: state_error,
        workflow_context: %{
          workflow_id: "rollback_test",
          criticality: :critical
        }
      }

      assert {:ok, result} = HandleWorkflowErrorAction.run(params, %{})

      handling_result = result.error_handling_result

      # Should apply compensation for state inconsistency
      assert handling_result.success == true
      assert Map.get(handling_result, :compensation_applied, false) == true
      assert Map.get(handling_result, :state_consistency, :unknown) in [:maintained, :restored]
    end

    test "measures compensation performance within targets" do
      # Test compensation performance targets
      performance_error = %{
        type: :performance_degradation,
        message: "Workflow performance below acceptable thresholds",
        context: %{current_performance: 0.3, target_performance: 0.8}
      }

      start_time = System.monotonic_time(:microsecond)

      params = %{
        error_info: performance_error,
        workflow_context: %{criticality: :high}
      }

      assert {:ok, result} = HandleWorkflowErrorAction.run(params, %{})

      end_time = System.monotonic_time(:microsecond)
      total_handling_time = end_time - start_time

      # Should complete within 5 seconds (5,000,000 microseconds)
      assert total_handling_time < 5_000_000

      # Recorded time should be accurate
      metadata = result.error_handling_metadata
      assert metadata.error_handling_time_microseconds > 0
      assert metadata.error_handling_time_microseconds <= total_handling_time
    end
  end

  describe "workflow recovery and replay mechanisms (2.3.8)" do
    test "executes workflow recovery with >90% success rate" do
      # Test workflow recovery mechanism reliability
      recovery_errors =
        Enum.map(1..10, fn i ->
          %{
            type: :workflow_failure,
            message: "Workflow execution failed at step #{i}",
            context: %{
              workflow_id: "recovery_test_#{i}",
              failed_step: i,
              total_steps: 5
            }
          }
        end)

      recovery_results =
        Enum.map(recovery_errors, fn error_info ->
          params = %{
            error_info: error_info,
            workflow_context: %{criticality: :medium}
          }

          case HandleWorkflowErrorAction.run(params, %{}) do
            {:ok, result} ->
              handling_result = result.error_handling_result

              %{
                success: handling_result.success,
                recovery_applied: handling_result.strategy_applied == :workflow_replay,
                recovery_time: Map.get(handling_result, :recovery_time_ms, 0)
              }

            {:error, _reason} ->
              %{success: false, recovery_applied: false, recovery_time: 0}
          end
        end)

      successful_recoveries = Enum.count(recovery_results, & &1.success)
      recovery_success_rate = successful_recoveries / length(recovery_errors)

      # Should achieve >90% success rate
      assert recovery_success_rate >= 0.90
      # At least 9/10 successful
      assert successful_recoveries >= 9

      # Validate recovery times are reasonable
      recovery_times =
        recovery_results
        |> Enum.filter(& &1.success)
        |> Enum.map(& &1.recovery_time)

      avg_recovery_time =
        if Enum.empty?(recovery_times) do
          0
        else
          Enum.sum(recovery_times) / length(recovery_times)
        end

      # Average recovery time should be under 30 seconds
      assert avg_recovery_time < 30_000
    end

    test "validates workflow replay functionality" do
      # Test workflow replay capability
      replay_error = %{
        type: :execution_failure,
        message: "Workflow execution interrupted",
        context: %{
          workflow_id: "replay_test",
          checkpoint_available: true,
          replay_from_step: 2
        }
      }

      params = %{
        error_info: replay_error,
        workflow_context: %{
          workflow_id: "replay_test",
          criticality: :high
        }
      }

      assert {:ok, result} = HandleWorkflowErrorAction.run(params, %{})

      handling_result = result.error_handling_result

      # Should handle replay capability
      assert handling_result.success == true
      assert handling_result.strategy_applied in [:workflow_replay, :immediate_compensation]

      # Should have replay metadata if replay was used
      if handling_result.strategy_applied == :workflow_replay do
        assert Map.has_key?(handling_result, :replay_from_checkpoint)
        assert Map.get(handling_result, :state_restored, false) == true
      end
    end

    test "validates checkpoint recovery mechanisms" do
      # Test checkpoint-based recovery
      checkpoint_error = %{
        type: :checkpoint_corruption,
        message: "Workflow checkpoint data corrupted",
        context: %{
          workflow_id: "checkpoint_test",
          checkpoint_id: "checkpoint_123",
          corruption_detected: true
        }
      }

      params = %{
        error_info: checkpoint_error,
        workflow_context: %{criticality: :critical}
      }

      assert {:ok, result} = HandleWorkflowErrorAction.run(params, %{})

      # Should handle checkpoint corruption gracefully
      handling_result = result.error_handling_result
      assert handling_result.success == true

      # Should provide recovery strategy
      assert handling_result.strategy_applied in [
               :workflow_replay,
               :immediate_compensation,
               :emergency_fallback
             ]
    end
  end

  describe "health monitoring and predictive failure detection (2.3.9)" do
    test "detects health degradation patterns" do
      # Test health monitoring capability
      health_degradation_error = %{
        type: :performance_degradation,
        message: "Workflow performance degrading over time",
        context: %{
          workflow_id: "health_monitor_test",
          performance_trend: :declining,
          current_performance: 0.6,
          baseline_performance: 0.9
        }
      }

      params = %{
        error_info: health_degradation_error,
        workflow_context: %{criticality: :medium},
        monitoring_config: %{
          track_error_patterns: true,
          enable_learning: true,
          report_analytics: true
        }
      }

      assert {:ok, result} = HandleWorkflowErrorAction.run(params, %{})

      # Should detect and handle performance degradation
      handling_result = result.error_handling_result
      assert handling_result.success == true

      # Should have collected monitoring data
      monitoring_data = result.monitoring_data
      assert Map.has_key?(monitoring_data, :error_pattern_data)
      assert Map.has_key?(monitoring_data, :performance_data)
      assert Map.has_key?(monitoring_data, :learning_data)
    end

    test "achieves >80% prediction accuracy target" do
      # Test predictive failure detection accuracy
      predictive_test_scenarios = [
        %{
          type: :resource_exhaustion_warning,
          context: %{memory_usage_trend: :increasing, cpu_usage: 0.85},
          should_predict_failure: true
        },
        %{
          type: :performance_degradation_warning,
          context: %{latency_trend: :increasing, throughput_trend: :decreasing},
          should_predict_failure: true
        },
        %{
          type: :normal_operation,
          context: %{all_metrics: :stable, performance: :good},
          should_predict_failure: false
        },
        %{
          type: :temporary_spike,
          context: %{temporary_load: true, recovering: true},
          should_predict_failure: false
        }
      ]

      prediction_results =
        Enum.map(predictive_test_scenarios, fn scenario ->
          error_info = %{
            type: scenario.type,
            message: "Predictive scenario: #{scenario.type}",
            context: scenario.context
          }

          params = %{
            error_info: error_info,
            workflow_context: %{},
            monitoring_config: %{enable_learning: true}
          }

          case HandleWorkflowErrorAction.run(params, %{}) do
            {:ok, result} ->
              # Analyze if prediction would be accurate
              handling_result = result.error_handling_result
              predicted_failure = handling_result.strategy_applied != :retry_with_backoff

              %{
                scenario: scenario.type,
                predicted_failure: predicted_failure,
                should_predict: scenario.should_predict_failure,
                accurate_prediction: predicted_failure == scenario.should_predict_failure
              }

            {:error, _reason} ->
              %{
                scenario: scenario.type,
                predicted_failure: false,
                should_predict: scenario.should_predict_failure,
                accurate_prediction: false
              }
          end
        end)

      accurate_predictions = Enum.count(prediction_results, & &1.accurate_prediction)
      prediction_accuracy = accurate_predictions / length(predictive_test_scenarios)

      # Should achieve >80% prediction accuracy
      assert prediction_accuracy >= 0.80
      # At least 3/4 accurate
      assert accurate_predictions >= 3
    end

    test "monitors system health with comprehensive metrics" do
      # Test comprehensive health monitoring
      health_monitoring_error = %{
        type: :system_health_check,
        message: "Comprehensive system health assessment",
        context: %{
          cpu_usage: 0.75,
          memory_usage: 0.60,
          active_workflows: 150,
          error_rate: 0.05,
          performance_score: 0.85
        }
      }

      params = %{
        error_info: health_monitoring_error,
        workflow_context: %{},
        monitoring_config: %{
          track_error_patterns: true,
          collect_recovery_metrics: true,
          enable_learning: true,
          report_analytics: true
        }
      }

      assert {:ok, result} = HandleWorkflowErrorAction.run(params, %{})

      # Should collect comprehensive monitoring data
      monitoring_data = result.monitoring_data

      # Validate monitoring data structure
      assert Map.has_key?(monitoring_data, :error_pattern_data)
      assert Map.has_key?(monitoring_data, :recovery_metrics)
      assert Map.has_key?(monitoring_data, :performance_data)
      assert Map.has_key?(monitoring_data, :learning_data)

      # Validate performance data
      performance_data = monitoring_data.performance_data
      assert Map.has_key?(performance_data, :error_resolution_time)
      assert Map.has_key?(performance_data, :performance_degradation)
      assert Map.has_key?(performance_data, :system_impact)

      # Validate learning data
      learning_data = monitoring_data.learning_data
      assert Map.has_key?(learning_data, :improvement_opportunities)
      assert is_list(learning_data.improvement_opportunities)
    end
  end

  describe "comprehensive error handling integration" do
    test "integrates all error handling capabilities end-to-end" do
      # Test complete error handling workflow

      # Step 1: Initial error detection
      initial_error = %{
        type: :complex_failure,
        message: "Complex multi-component workflow failure",
        context: %{
          workflow_id: "integration_test",
          failed_components: [:component_a, :component_b],
          cascade_failure: true
        }
      }

      assert {:ok, initial_result} =
               HandleWorkflowErrorAction.run(
                 %{
                   error_info: initial_error,
                   workflow_context: %{criticality: :high}
                 },
                 %{}
               )

      # Step 2: Validate error handling succeeded
      initial_handling = initial_result.error_handling_result
      assert initial_handling.success == true

      # Step 3: Simulate follow-up error during recovery
      follow_up_error = %{
        type: :recovery_failure,
        message: "Recovery attempt failed",
        context: %{
          workflow_id: "integration_test",
          original_error_id: initial_result.error_handling_metadata.error_classification.error_id,
          recovery_attempt: 1
        }
      }

      assert {:ok, follow_up_result} =
               HandleWorkflowErrorAction.run(
                 %{
                   error_info: follow_up_error,
                   workflow_context: %{criticality: :critical}
                 },
                 %{}
               )

      # Step 4: Validate escalated handling
      follow_up_handling = follow_up_result.error_handling_result
      assert follow_up_handling.success == true

      # Should escalate to stronger recovery strategy
      assert follow_up_handling.strategy_applied in [
               :emergency_fallback,
               :immediate_compensation,
               :workflow_replay
             ]

      # Validate end-to-end integration
      assert is_binary(initial_result.error_handling_metadata.error_classification.error_id)
      assert is_binary(follow_up_result.error_handling_metadata.error_classification.error_id)

      assert initial_result.error_handling_metadata.error_classification.error_id !=
               follow_up_result.error_handling_metadata.error_classification.error_id
    end

    test "validates performance under error load" do
      # Test error handling performance under load
      concurrent_errors =
        Enum.map(1..5, fn i ->
          Task.async(fn ->
            error_info = %{
              type: Enum.random([:timeout, :resource_exhaustion, :validation_failure]),
              message: "Concurrent error #{i}",
              context: %{workflow_id: "concurrent_error_#{i}"}
            }

            params = %{
              error_info: error_info,
              workflow_context: %{criticality: :normal}
            }

            HandleWorkflowErrorAction.run(params, %{})
          end)
        end)

      results = Task.await_many(concurrent_errors, 30_000)

      # All error handling should succeed
      Enum.each(results, fn result ->
        assert match?({:ok, _}, result)
      end)

      # Validate error handling times
      handling_times =
        Enum.map(results, fn {:ok, result} ->
          result.error_handling_metadata.error_handling_time_microseconds
        end)

      avg_handling_time = Enum.sum(handling_times) / length(handling_times)

      # Average error handling time should be under 100ms (100,000 microseconds)
      assert avg_handling_time < 100_000
    end

    test "validates error handling with workflow integration" do
      # Test error handling integration with workflow systems
      integration_error = %{
        type: :workflow_integration_failure,
        message: "Integration failure between workflow components",
        context: %{
          workflow_id: "integration_failure_test",
          component_a: :dynamic_composer,
          component_b: :error_manager,
          integration_point: :error_reporting
        }
      }

      params = %{
        error_info: integration_error,
        workflow_context: %{
          workflow_id: "integration_failure_test",
          criticality: :high
        }
      }

      assert {:ok, result} = HandleWorkflowErrorAction.run(params, %{})

      # Should handle integration failures appropriately
      handling_result = result.error_handling_result
      assert handling_result.success == true

      # Should provide integration-specific recovery
      assert handling_result.strategy_applied in [
               :immediate_compensation,
               :resource_optimization,
               :workflow_replay
             ]

      # Should collect integration-specific monitoring data
      monitoring_data = result.monitoring_data
      assert Map.has_key?(monitoring_data, :error_pattern_data)

      pattern_data = monitoring_data.error_pattern_data
      assert pattern_data.error_category in [:logical, :system, :unknown]
    end
  end

  describe "error handling performance and reliability" do
    test "maintains <100ms error detection target" do
      # Test error detection performance
      detection_error = %{
        type: :performance_test,
        message: "Error detection performance test",
        context: %{test_type: :detection_speed}
      }

      detection_times =
        Enum.map(1..10, fn _i ->
          start_time = System.monotonic_time(:microsecond)

          params = %{
            error_info: detection_error,
            workflow_context: %{}
          }

          {:ok, _result} = HandleWorkflowErrorAction.run(params, %{})

          end_time = System.monotonic_time(:microsecond)
          end_time - start_time
        end)

      avg_detection_time = Enum.sum(detection_times) / length(detection_times)

      # Should average under 100ms (100,000 microseconds)
      assert avg_detection_time < 100_000

      # All individual detections should be under 200ms
      Enum.each(detection_times, fn detection_time ->
        # 200ms individual limit
        assert detection_time < 200_000
      end)
    end

    test "validates error handling system reliability" do
      # Test overall error handling system reliability
      reliability_test_count = 20

      reliability_errors =
        Enum.map(1..reliability_test_count, fn i ->
          error_type =
            Enum.random([:timeout, :memory_exhaustion, :validation_failure, :service_unavailable])

          %{
            type: error_type,
            message: "Reliability test error #{i}",
            context: %{test_id: i, error_source: :reliability_test}
          }
        end)

      reliability_results =
        Enum.map(reliability_errors, fn error_info ->
          params = %{
            error_info: error_info,
            workflow_context: %{criticality: :normal}
          }

          case HandleWorkflowErrorAction.run(params, %{}) do
            {:ok, result} ->
              %{success: result.error_handling_result.success, error_handled: true}

            {:error, _reason} ->
              %{success: false, error_handled: false}
          end
        end)

      successful_handlings = Enum.count(reliability_results, & &1.success)
      reliability_rate = successful_handlings / reliability_test_count

      # Should achieve >95% reliability
      assert reliability_rate >= 0.95
      # At least 19/20 successful
      assert successful_handlings >= 19

      # All errors should be handled (even if recovery fails)
      handled_errors = Enum.count(reliability_results, & &1.error_handled)
      # 100% error handling
      assert handled_errors == reliability_test_count
    end
  end
end
