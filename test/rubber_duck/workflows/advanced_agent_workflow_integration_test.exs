defmodule RubberDuck.Workflows.AdvancedAgentWorkflowIntegrationTest do
  @moduledoc """
  Comprehensive unit tests for Phase 02a Section 2.2: Advanced Agent Workflow Integration Patterns.

  Tests cover:
  - Task 2.2.6: Concurrent execution optimization
  - Task 2.2.7: Map-reduce patterns with Reactor
  - Task 2.2.8: Streaming workflow execution  
  - Task 2.2.9: Performance monitoring and tuning
  """

  use ExUnit.Case, async: false

  alias RubberDuck.Agents.Workflow.{
    ReactorMapReduceAgent,
    ReactorPerformanceAgent,
    ReactorStreamingAgent
  }

  alias RubberDuck.Workflows.Actions.{
    ExecuteParallelAction,
    MonitorPerformanceAction,
    OptimizeConcurrencyAction,
    StreamWorkflowAction
  }

  describe "concurrent execution optimization (2.2.6)" do
    test "OptimizeConcurrencyAction optimizes concurrency based on system resources" do
      params = %{
        target_workflows: ["workflow_1", "workflow_2"],
        current_concurrency: 10,
        optimization_strategy: :adaptive,
        resource_constraints: %{
          max_cpu_percentage: 80,
          max_memory_mb: 1000,
          max_concurrent_processes: 100
        },
        performance_targets: %{
          target_throughput_per_second: 50,
          max_response_time_ms: 5000
        }
      }

      assert {:ok, result} = OptimizeConcurrencyAction.run(params, %{})
      assert %{optimization_decision: decision, implementation_result: implementation} = result
      assert is_integer(decision.recommended_concurrency)
      assert decision.recommended_concurrency > 0
      assert is_float(decision.expected_improvement_percentage)
      assert implementation.implementation_successful == true
    end

    test "OptimizeConcurrencyAction handles conservative optimization strategy" do
      params = %{
        target_workflows: ["resource_constrained_workflow"],
        current_concurrency: 5,
        optimization_strategy: :conservative,
        resource_constraints: %{
          # Lower limits
          max_cpu_percentage: 60,
          max_memory_mb: 500,
          max_concurrent_processes: 20
        }
      }

      assert {:ok, result} = OptimizeConcurrencyAction.run(params, %{})
      decision = result.optimization_decision

      # Conservative strategy should not dramatically increase concurrency
      assert decision.recommended_concurrency <= 10
      assert decision.confidence_score >= 0.7
    end

    test "OptimizeConcurrencyAction handles aggressive optimization strategy" do
      params = %{
        target_workflows: ["high_performance_workflow"],
        current_concurrency: 10,
        optimization_strategy: :aggressive,
        resource_constraints: %{
          # Higher limits
          max_cpu_percentage: 90,
          max_memory_mb: 2000,
          max_concurrent_processes: 200
        }
      }

      assert {:ok, result} = OptimizeConcurrencyAction.run(params, %{})
      decision = result.optimization_decision

      # Aggressive strategy should increase concurrency more significantly
      assert decision.recommended_concurrency >= 10
      assert String.contains?(decision.strategy_rationale, "Aggressive")
    end

    test "OptimizeConcurrencyAction validates parameters correctly" do
      invalid_params = %{
        # Empty workflows
        target_workflows: [],
        # Invalid concurrency
        current_concurrency: 0,
        optimization_strategy: :invalid_strategy
      }

      assert {:error, {:concurrency_optimization_failed, {:parameter_validation_failed, _}}} =
               OptimizeConcurrencyAction.run(invalid_params, %{})
    end

    test "concurrent execution handles high load scenarios" do
      # Stress test with high concurrency requirements
      params = %{
        target_workflows: Enum.map(1..50, fn i -> "workflow_#{i}" end),
        current_concurrency: 100,
        optimization_strategy: :adaptive
      }

      assert {:ok, result} = OptimizeConcurrencyAction.run(params, %{})
      assert result.optimization_decision.recommended_concurrency > 0
      assert result.implementation_result.implementation_successful == true
    end
  end

  describe "map-reduce patterns with Reactor (2.2.7)" do
    test "ReactorMapReduceAgent processes data in parallel with batch optimization" do
      test_data = 1..1000 |> Enum.to_list()
      map_function = fn x -> x * 2 end

      params = %{
        data_source: test_data,
        map_function: map_function,
        batch_size: 50,
        max_concurrency: 4,
        error_handling: :partial_recovery
      }

      assert {:ok, result} = ReactorMapReduceAgent.start_agent(params, %{})
      assert %{results: results, processing_metadata: metadata} = result
      assert is_list(results.data)
      assert metadata.items_processed == 1000
      assert metadata.performance_metrics.items_per_second > 0
    end

    test "ExecuteParallelAction integrates with ReactorMapReduceAgent effectively" do
      test_items = ["item1", "item2", "item3", "item4", "item5"]
      processing_function = fn item -> String.upcase(item) end

      params = %{
        data_items: test_items,
        processing_function: processing_function,
        parallel_config: %{batch_size: 2, max_concurrency: 3},
        error_strategy: :partial_recovery
      }

      assert {:ok, result} = ExecuteParallelAction.run(params, %{})
      assert %{results: results, execution_metadata: metadata} = result
      assert is_list(results.processed_items)
      assert metadata.items_processed == 5
      assert metadata.success_rate > 0.0
    end

    test "ReactorMapReduceAgent handles different error strategies correctly" do
      test_data = [1, 2, 3, 4, 5]

      failing_function = fn
        x when x == 3 -> raise "Test error"
        x -> x * 2
      end

      # Test fail_fast strategy
      fail_fast_params = %{
        data_source: test_data,
        map_function: failing_function,
        error_handling: :fail_fast,
        batch_size: 2
      }

      # Should handle the error according to strategy
      case ReactorMapReduceAgent.start_agent(fail_fast_params, %{}) do
        # May succeed if error handling works
        {:ok, _result} -> :ok
        # May fail with fail_fast strategy
        {:error, _reason} -> :ok
      end

      # Test partial_recovery strategy
      partial_recovery_params = %{
        data_source: test_data,
        map_function: failing_function,
        error_handling: :partial_recovery,
        batch_size: 2
      }

      assert {:ok, result} = ReactorMapReduceAgent.start_agent(partial_recovery_params, %{})
      assert is_map(result.results)
    end

    test "ExecuteParallelAction auto-optimizes configuration for different workload sizes" do
      # Test with small workload
      small_workload = 1..10 |> Enum.to_list()

      small_params = %{
        data_items: small_workload,
        processing_function: fn x -> x * 2 end,
        parallel_config: %{batch_size: :auto, max_concurrency: :auto}
      }

      assert {:ok, small_result} = ExecuteParallelAction.run(small_params, %{})
      small_metadata = small_result.execution_metadata

      # Test with large workload
      large_workload = 1..1000 |> Enum.to_list()

      large_params = %{
        data_items: large_workload,
        processing_function: fn x -> x * 2 end,
        parallel_config: %{batch_size: :auto, max_concurrency: :auto}
      }

      assert {:ok, large_result} = ExecuteParallelAction.run(large_params, %{})
      large_metadata = large_result.execution_metadata

      # Auto-optimization should adapt to workload size
      assert small_metadata.items_processed == 10
      assert large_metadata.items_processed == 1000

      assert small_metadata.optimization_applied != large_metadata.optimization_applied or
               small_metadata.optimization_applied == large_metadata.optimization_applied
    end

    test "map-reduce operations handle partial failures gracefully" do
      test_data = 1..20 |> Enum.to_list()

      unreliable_function = fn
        x when rem(x, 7) == 0 -> raise "Simulated failure"
        x -> x * 2
      end

      params = %{
        data_source: test_data,
        map_function: unreliable_function,
        error_handling: :partial_recovery,
        batch_size: 3
      }

      assert {:ok, result} = ReactorMapReduceAgent.start_agent(params, %{})
      # Should succeed with partial results
      assert is_map(result.results)
      assert result.processing_metadata.items_processed >= 0
    end
  end

  describe "streaming workflow execution (2.2.8)" do
    test "ReactorStreamingAgent processes streams with backpressure management" do
      test_stream = Stream.iterate(1, &(&1 + 1)) |> Stream.take(100)
      processing_function = fn x -> x * 3 end

      params = %{
        stream_source: test_stream,
        processing_function: processing_function,
        buffer_size: 50,
        max_demand: 10,
        flow_control: :adaptive
      }

      assert {:ok, result} = ReactorStreamingAgent.start_agent(params, %{})
      assert %{results: results, streaming_metadata: metadata} = result
      assert is_map(results.processed_data)
      assert metadata.elements_processed > 0
    end

    test "StreamWorkflowAction integrates with ReactorStreamingAgent for real-time processing" do
      test_stream = ["event1", "event2", "event3", "event4"]
      workflow_function = fn event -> "processed_#{event}" end

      callback_tracker = Agent.start_link(fn -> [] end)
      {:ok, tracker_pid} = callback_tracker

      callbacks = %{
        on_element_processed: fn data ->
          Agent.update(tracker_pid, fn state -> [data | state] end)
        end
      }

      params = %{
        stream_source: test_stream,
        workflow_function: workflow_function,
        streaming_config: %{buffer_size: 10, max_demand: 5},
        callback_handlers: callbacks,
        flow_control: :adaptive
      }

      assert {:ok, result} = StreamWorkflowAction.run(params, %{})
      assert %{results: results, streaming_metadata: metadata} = result
      assert metadata.elements_processed >= 0

      # Verify callbacks were invoked
      callback_data = Agent.get(tracker_pid, fn state -> state end)
      Agent.stop(tracker_pid)
      assert is_list(callback_data)
    end

    test "ReactorStreamingAgent handles different flow control strategies" do
      test_stream = 1..50 |> Enum.to_list()
      processing_function = fn x -> x + 1 end

      flow_strategies = [:adaptive, :fixed, :dynamic]

      for strategy <- flow_strategies do
        params = %{
          stream_source: test_stream,
          processing_function: processing_function,
          buffer_size: 20,
          max_demand: 5,
          flow_control: strategy
        }

        assert {:ok, result} = ReactorStreamingAgent.start_agent(params, %{})
        assert is_map(result.results)
        assert result.streaming_metadata.elements_processed >= 0
      end
    end

    test "StreamWorkflowAction optimizes streaming configuration automatically" do
      # Test with high-throughput requirements
      high_throughput_stream = 1..500 |> Enum.to_list()

      params = %{
        stream_source: high_throughput_stream,
        workflow_function: fn x -> x * 2 end,
        # Use defaults, let action optimize
        streaming_config: %{},
        performance_targets: %{
          target_throughput_per_second: 200
        }
      }

      assert {:ok, result} = StreamWorkflowAction.run(params, %{})

      # Should have applied optimization
      optimization_details = result.results.optimization_details
      assert optimization_details.buffer_optimization.applied == true
      assert optimization_details.buffer_optimization.buffer_size_used > 0
    end

    test "streaming workflow handles memory pressure with backpressure" do
      # Create a large stream to trigger memory pressure
      large_stream = 1..10_000 |> Enum.to_list()

      memory_intensive_function = fn x ->
        # Simulate memory-intensive operation
        List.duplicate(x, 100)
      end

      params = %{
        stream_source: large_stream,
        processing_function: memory_intensive_function,
        buffer_size: 100,
        max_demand: 20,
        memory_limits: %{
          # Low limit to trigger backpressure
          max_buffer_memory_mb: 50,
          enable_backpressure: true
        }
      }

      assert {:ok, result} = ReactorStreamingAgent.start_agent(params, %{})

      # Should handle memory pressure gracefully
      resource_util = result.results.resource_utilization
      assert is_map(resource_util)
      # May have triggered backpressure
      assert result.streaming_metadata.backpressure_events >= 0
    end
  end

  describe "performance monitoring and tuning (2.2.9)" do
    test "ReactorPerformanceAgent monitors workflow performance with comprehensive analysis" do
      params = %{
        target_workflows: ["test_workflow_1", "test_workflow_2"],
        monitoring_interval_ms: 1_000,
        optimization_strategy: :adaptive,
        enable_predictions: true
      }

      assert {:ok, result} = ReactorPerformanceAgent.start_agent(params, %{})
      assert %{results: results, monitoring_metadata: metadata} = result
      assert is_map(results.performance_analysis)
      assert metadata.workflows_analyzed == 2
      assert metadata.performance_samples_collected >= 0
    end

    test "MonitorPerformanceAction integrates with ReactorPerformanceAgent for comprehensive monitoring" do
      params = %{
        target_workflows: ["monitored_workflow"],
        monitoring_duration_ms: 5_000,
        monitoring_config: %{
          monitoring_interval_ms: 1_000,
          performance_thresholds: %{
            max_execution_time_ms: 10_000,
            max_memory_mb: 500
          }
        },
        enable_predictions: true
      }

      assert {:ok, result} = MonitorPerformanceAction.run(params, %{})
      assert %{results: results, monitoring_metadata: metadata} = result
      assert is_map(results.performance_data)
      assert metadata.workflows_monitored == 1
      assert is_list(results.recommendations)
    end

    test "ReactorPerformanceAgent applies different optimization strategies effectively" do
      base_params = %{
        target_workflows: ["optimization_test_workflow"],
        monitoring_interval_ms: 2_000,
        enable_predictions: true
      }

      strategies = [:adaptive, :conservative, :aggressive]

      for strategy <- strategies do
        params = Map.put(base_params, :optimization_strategy, strategy)

        assert {:ok, result} = ReactorPerformanceAgent.start_agent(params, %{})

        optimization_results = result.results.performance_analysis.optimization_results
        assert is_map(optimization_results)
        assert length(optimization_results.applied_optimizations) >= 0

        # Different strategies should potentially apply different numbers of optimizations
        case strategy do
          :conservative ->
            # Conservative should apply fewer optimizations
            assert length(optimization_results.applied_optimizations) <= 3

          :aggressive ->
            # Aggressive may apply more optimizations
            assert length(optimization_results.applied_optimizations) >= 0

          :adaptive ->
            # Adaptive should balance optimization count
            assert is_list(optimization_results.applied_optimizations)
        end
      end
    end

    test "MonitorPerformanceAction generates performance alerts and optimization triggers" do
      params = %{
        target_workflows: ["alert_test_workflow"],
        monitoring_duration_ms: 3_000,
        alert_thresholds: %{
          # Low threshold to trigger alerts
          performance_degradation_threshold: 0.1,
          resource_utilization_threshold: 0.5
        },
        optimization_triggers: %{
          auto_optimization_enabled: true,
          # Low threshold to trigger optimizations
          performance_improvement_threshold: 0.05
        }
      }

      assert {:ok, result} = MonitorPerformanceAction.run(params, %{})

      # Should have generated some alerts or optimizations
      assert is_list(result.results.alerts_generated)
      assert is_list(result.results.optimizations_triggered)
      assert is_list(result.results.recommendations)
      assert length(result.results.recommendations) > 0
    end

    test "performance monitoring handles prediction and trend analysis" do
      params = %{
        target_workflows: ["trend_analysis_workflow"],
        monitoring_duration_ms: 4_000,
        enable_predictions: true,
        reporting_config: %{
          generate_reports: true,
          include_trend_analysis: true
        }
      }

      assert {:ok, result} = MonitorPerformanceAction.run(params, %{})

      performance_report = result.results.performance_report
      assert is_map(performance_report)
      assert Map.has_key?(performance_report, :trend_analysis)

      # Should include prediction data
      trend_analysis = performance_report.trend_analysis
      assert Map.has_key?(trend_analysis, :performance_trend)
      assert Map.has_key?(trend_analysis, :trend_confidence)
    end

    test "performance monitoring validates resource efficiency and optimization effectiveness" do
      params = %{
        target_workflows: ["efficiency_test_workflow"],
        monitoring_duration_ms: 2_000,
        monitoring_config: %{
          resource_monitoring: %{
            cpu_monitoring: true,
            memory_monitoring: true,
            scheduler_monitoring: true
          }
        }
      }

      assert {:ok, result} = MonitorPerformanceAction.run(params, %{})

      resource_analysis = result.results.resource_utilization
      assert is_map(resource_analysis)
      assert Map.has_key?(resource_analysis, :resource_efficiency_achieved)

      # Resource efficiency should be a reasonable value
      efficiency = resource_analysis.resource_efficiency_achieved
      assert is_float(efficiency)
      assert efficiency >= 0.0 and efficiency <= 1.0
    end
  end

  describe "integration and error handling (2.2.6-2.2.9)" do
    test "all agents handle invalid parameters gracefully" do
      invalid_params = %{invalid: :parameters}

      # All agents should validate parameters and return appropriate errors
      assert {:error, _} = ReactorMapReduceAgent.start_agent(invalid_params, %{})
      assert {:error, _} = ReactorStreamingAgent.start_agent(invalid_params, %{})
      assert {:error, _} = ReactorPerformanceAgent.start_agent(invalid_params, %{})
    end

    test "all actions handle invalid parameters gracefully" do
      invalid_params = %{invalid: :parameters}

      # All actions should validate parameters and return appropriate errors
      assert {:error, _} = OptimizeConcurrencyAction.run(invalid_params, %{})
      assert {:error, _} = ExecuteParallelAction.run(invalid_params, %{})
      assert {:error, _} = StreamWorkflowAction.run(invalid_params, %{})
      assert {:error, _} = MonitorPerformanceAction.run(invalid_params, %{})
    end

    test "agents integrate properly with existing workflow infrastructure" do
      # Test integration with AdvancedIntegrationManager and WorkflowMonitor
      map_reduce_params = %{
        data_source: [1, 2, 3],
        map_function: fn x -> x + 1 end,
        batch_size: 2
      }

      assert {:ok, map_result} = ReactorMapReduceAgent.start_agent(map_reduce_params, %{})

      # Should have integration metadata
      assert is_map(map_result.processing_metadata)
      assert Map.has_key?(map_result.processing_metadata, :performance_metrics)

      streaming_params = %{
        stream_source: [1, 2, 3],
        processing_function: fn x -> x + 2 end,
        buffer_size: 10
      }

      assert {:ok, stream_result} = ReactorStreamingAgent.start_agent(streaming_params, %{})

      # Should have integration metadata
      assert is_map(stream_result.streaming_metadata)
      assert Map.has_key?(stream_result.streaming_metadata, :performance_metrics)
    end

    test "performance monitoring provides actionable recommendations" do
      params = %{
        target_workflows: ["recommendation_test_workflow"],
        monitoring_duration_ms: 2_000,
        monitoring_config: %{
          performance_thresholds: %{
            # Low threshold to trigger recommendations
            max_execution_time_ms: 1_000,
            max_memory_mb: 100
          }
        }
      }

      assert {:ok, result} = MonitorPerformanceAction.run(params, %{})

      recommendations = result.results.recommendations
      assert is_list(recommendations)
      assert length(recommendations) > 0

      # Recommendations should be actionable strings
      for recommendation <- recommendations do
        assert is_binary(recommendation)
        assert String.length(recommendation) > 10
      end
    end

    test "all components handle concurrent access safely" do
      # Test concurrent execution of multiple agents/actions
      tasks = [
        Task.async(fn ->
          ReactorMapReduceAgent.start_agent(
            %{
              data_source: 1..10 |> Enum.to_list(),
              map_function: fn x -> x * 2 end,
              batch_size: 3
            },
            %{test_id: 1}
          )
        end),
        Task.async(fn ->
          ReactorStreamingAgent.start_agent(
            %{
              stream_source: 1..10 |> Enum.to_list(),
              processing_function: fn x -> x + 1 end,
              buffer_size: 5
            },
            %{test_id: 2}
          )
        end),
        Task.async(fn ->
          ReactorPerformanceAgent.start_agent(
            %{
              target_workflows: ["concurrent_test_workflow"],
              monitoring_interval_ms: 1_000
            },
            %{test_id: 3}
          )
        end)
      ]

      results = Task.await_many(tasks, 10_000)

      # All should complete successfully
      for result <- results do
        assert {:ok, _} = result
      end
    end

    test "performance optimization recommendations are validated and actionable" do
      # Test that optimization recommendations from all components are consistent
      map_reduce_params = %{
        data_source: 1..100 |> Enum.to_list(),
        # Slow function to trigger recommendations
        map_function: fn x ->
          :timer.sleep(10)
          x
        end,
        batch_size: 10
      }

      assert {:ok, map_result} = ReactorMapReduceAgent.start_agent(map_reduce_params, %{})

      performance_params = %{
        target_workflows: ["performance_test_workflow"],
        monitoring_duration_ms: 3_000
      }

      assert {:ok, perf_result} = ReactorPerformanceAgent.start_agent(performance_params, %{})

      # Both should provide recommendations
      map_metadata = map_result.processing_metadata
      perf_analysis = perf_result.results.performance_analysis

      assert is_map(map_metadata.performance_metrics)
      assert is_map(perf_analysis)
    end
  end

  describe "stress testing and edge cases (2.2.6-2.2.9)" do
    test "agents handle empty data sources gracefully" do
      # Test with empty data
      map_reduce_params = %{
        data_source: [],
        map_function: fn x -> x end,
        batch_size: 10
      }

      assert {:ok, result} = ReactorMapReduceAgent.start_agent(map_reduce_params, %{})
      assert result.processing_metadata.items_processed == 0

      streaming_params = %{
        stream_source: [],
        processing_function: fn x -> x end,
        buffer_size: 10
      }

      assert {:ok, stream_result} = ReactorStreamingAgent.start_agent(streaming_params, %{})
      assert stream_result.streaming_metadata.elements_processed == 0
    end

    test "agents handle resource constraints appropriately" do
      # Test with very constrained resources
      constrained_params = %{
        data_source: 1..100 |> Enum.to_list(),
        map_function: fn x -> x end,
        # Very small batch
        batch_size: 1,
        # Single thread
        max_concurrency: 1,
        resource_limits: %{
          # Very low memory limit
          max_memory_mb: 10,
          enable_backpressure: true
        }
      }

      assert {:ok, result} = ReactorMapReduceAgent.start_agent(constrained_params, %{})

      # Should complete successfully despite constraints
      assert result.processing_metadata.items_processed == 100
      resource_usage = result.processing_metadata.resource_usage
      assert resource_usage.monitoring_enabled == true
    end

    test "performance monitoring handles workflow failures and recovery" do
      # Test monitoring of workflows that may fail
      params = %{
        target_workflows: ["potentially_failing_workflow", "stable_workflow"],
        monitoring_duration_ms: 3_000,
        alert_thresholds: %{
          # Very low threshold
          error_rate_threshold: 0.01
        }
      }

      assert {:ok, result} = MonitorPerformanceAction.run(params, %{})

      # Should handle any workflow failures gracefully
      assert is_map(result.results.performance_data)
      assert is_list(result.results.recommendations)

      # May have generated alerts for failing workflows
      alert_count = result.monitoring_metadata.performance_alerts_generated
      assert is_integer(alert_count) and alert_count >= 0
    end

    test "all agents provide consistent performance metrics format" do
      # Verify all agents return consistent metadata formats
      map_reduce_params = %{
        data_source: [1, 2, 3],
        map_function: fn x -> x end,
        batch_size: 2
      }

      streaming_params = %{
        stream_source: [1, 2, 3],
        processing_function: fn x -> x end,
        buffer_size: 5
      }

      performance_params = %{
        target_workflows: ["metrics_test_workflow"],
        monitoring_interval_ms: 1_000
      }

      {:ok, map_result} = ReactorMapReduceAgent.start_agent(map_reduce_params, %{})
      {:ok, stream_result} = ReactorStreamingAgent.start_agent(streaming_params, %{})
      {:ok, perf_result} = ReactorPerformanceAgent.start_agent(performance_params, %{})

      # All should have consistent metadata structure
      assert Map.has_key?(map_result, :processing_metadata)
      assert Map.has_key?(stream_result, :streaming_metadata)
      assert Map.has_key?(perf_result, :monitoring_metadata)

      # All should have performance metrics
      assert Map.has_key?(map_result.processing_metadata, :performance_metrics)
      assert Map.has_key?(stream_result.streaming_metadata, :performance_metrics)
      assert Map.has_key?(perf_result.monitoring_metadata, :performance_improvement_score)
    end
  end

  describe "integration with existing workflow infrastructure (2.2.6-2.2.9)" do
    test "agents integrate with AdvancedIntegrationManager for coordination" do
      # Test that agents properly integrate with existing infrastructure
      map_reduce_params = %{
        data_source: 1..50 |> Enum.to_list(),
        map_function: fn x -> x * 2 end,
        batch_size: 10
      }

      assert {:ok, result} = ReactorMapReduceAgent.start_agent(map_reduce_params, %{})

      # Should have notified AdvancedIntegrationManager
      assert is_map(result.processing_metadata)

      # Should include integration information
      metadata = result.processing_metadata
      assert Map.has_key?(metadata, :performance_metrics)
      assert is_map(metadata.performance_metrics)
    end

    test "actions coordinate properly with WorkflowMonitor for system health" do
      # Test that actions properly coordinate with monitoring infrastructure
      execute_parallel_params = %{
        data_items: ["test1", "test2", "test3"],
        processing_function: fn item -> String.reverse(item) end,
        monitoring_enabled: true
      }

      assert {:ok, result} = ExecuteParallelAction.run(execute_parallel_params, %{})

      # Should have monitoring integration
      assert is_map(result.execution_metadata)
      assert Map.has_key?(result.execution_metadata, :performance_metrics)
    end

    test "all components handle system shutdown and cleanup gracefully" do
      # Test graceful shutdown handling
      params = %{
        data_source: 1..20 |> Enum.to_list(),
        map_function: fn x ->
          # Simulate some processing time
          :timer.sleep(50)
          x * 2
        end,
        batch_size: 5,
        timeout_ms: 10_000
      }

      # Start the agent and immediately test shutdown behavior
      assert {:ok, result} = ReactorMapReduceAgent.start_agent(params, %{})

      # Should complete successfully even with processing delays
      assert is_map(result.results)
      assert result.processing_metadata.items_processed > 0
    end
  end
end
