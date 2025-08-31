defmodule RubberDuck.Workflows.Actions.StreamWorkflowAction do
  @moduledoc """
  Action for real-time workflow processing using ReactorStreamingAgent integration.

  Provides sophisticated streaming workflow execution with backpressure control,
  real-time processing capabilities, and seamless integration with existing
  workflow infrastructure. Leverages ReactorStreamingAgent for advanced streaming patterns.

  Features:
  - Real-time workflow processing with GenStage backpressure management
  - Sophisticated buffer management and flow control with memory optimization
  - Event-driven processing with configurable callback handlers and notifications
  - Integration with ReactorStreamingAgent for advanced streaming capabilities
  - Resource-aware streaming with automatic flow control and memory management
  - Comprehensive streaming analytics and performance optimization

  Usage Patterns:
  - **Real-Time Processing**: Continuous processing of streaming data with immediate results
  - **Event-Driven Workflows**: Processing of events and messages with backpressure control
  - **Live Data Pipelines**: Stream processing with buffer optimization and flow control
  - **High-Throughput Streaming**: Efficient streaming with resource management and monitoring
  """

  use Jido.Action,
    name: "stream_workflow",
    schema: [
      stream_source: [type: :any, required: true, doc: "Stream source for real-time processing"],
      workflow_function: [
        type: :any,
        required: true,
        doc: "Workflow function to apply to each stream element"
      ],
      streaming_config: [type: :map, default: %{}, doc: "Streaming configuration parameters"],
      callback_handlers: [
        type: :map,
        default: %{},
        doc: "Event callback handlers for stream events"
      ],
      flow_control: [
        type: :atom,
        default: :adaptive,
        doc: "Flow control strategy (:adaptive, :fixed, :dynamic)"
      ],
      performance_targets: [
        type: :map,
        default: %{},
        doc: "Performance targets for streaming optimization"
      ],
      monitoring_enabled: [
        type: :boolean,
        default: true,
        doc: "Enable streaming performance monitoring"
      ]
    ]

  require Logger

  alias RubberDuck.Agents.Workflow.ReactorStreamingAgent
  alias RubberDuck.Workflows.WorkflowMonitor

  @supported_flow_strategies [:adaptive, :fixed, :dynamic]

  @default_streaming_config %{
    buffer_size: 1000,
    max_demand: 100,
    timeout_ms: 30_000,
    enable_telemetry: true,
    memory_limits: %{
      max_buffer_memory_mb: 500,
      gc_threshold_mb: 100,
      enable_backpressure: true
    }
  }

  @default_performance_targets %{
    target_throughput_per_second: 200,
    max_element_processing_time_ms: 1000,
    min_buffer_utilization: 0.3,
    max_buffer_utilization: 0.9,
    max_backpressure_events: 5
  }

  @default_callback_handlers %{
    on_stream_start: nil,
    on_element_processed: nil,
    on_batch_complete: nil,
    on_stream_complete: nil,
    on_error: nil,
    on_backpressure: nil
  }

  def run(params, context) do
    %{
      stream_source: source,
      workflow_function: func,
      streaming_config: config,
      callback_handlers: callbacks,
      flow_control: flow_control,
      performance_targets: targets,
      monitoring_enabled: monitoring
    } = params

    merged_config = Map.merge(@default_streaming_config, config)
    merged_targets = Map.merge(@default_performance_targets, targets)
    merged_callbacks = Map.merge(@default_callback_handlers, callbacks)

    Logger.info("StreamWorkflowAction: Starting streaming workflow execution",
      stream_source_type: get_stream_source_type(source),
      flow_control: flow_control,
      monitoring_enabled: monitoring
    )

    streaming_start_time = System.monotonic_time(:microsecond)

    with {:ok, validated_params} <-
           validate_streaming_params(source, func, flow_control, merged_config),
         {:ok, optimized_config} <-
           optimize_streaming_configuration(merged_config, merged_targets, context),
         {:ok, agent_params} <-
           prepare_streaming_agent_params(
             validated_params,
             optimized_config,
             merged_callbacks,
             context
           ),
         {:ok, streaming_results} <- execute_streaming_workflow_with_agent(agent_params, context),
         {:ok, final_results} <-
           finalize_streaming_results(streaming_results, optimized_config, monitoring) do
      streaming_time = System.monotonic_time(:microsecond) - streaming_start_time

      Logger.info("StreamWorkflowAction: Streaming workflow completed successfully",
        elements_processed: get_elements_processed(final_results),
        streaming_time_ms: div(streaming_time, 1000),
        average_throughput: calculate_average_throughput(final_results, streaming_time)
      )

      {:ok,
       %{
         results: final_results,
         streaming_metadata: %{
           streaming_time_microseconds: streaming_time,
           elements_processed: get_elements_processed(final_results),
           buffer_utilization: get_buffer_utilization(final_results),
           backpressure_events: get_backpressure_events(final_results),
           performance_metrics:
             calculate_streaming_performance_metrics(final_results, streaming_time)
         }
       }}
    else
      {:error, reason} ->
        Logger.error("StreamWorkflowAction: Streaming workflow failed", error: reason)
        {:error, {:streaming_workflow_failed, reason}}
    end
  end

  # Private implementation functions

  defp validate_streaming_params(source, func, flow_control, config) do
    with :ok <- validate_stream_source(source),
         :ok <- validate_workflow_function(func),
         :ok <- validate_flow_control_strategy(flow_control),
         :ok <- validate_streaming_configuration(config) do
      validated_params = %{
        stream_source: source,
        workflow_function: func,
        flow_control: flow_control,
        config: config,
        validation_timestamp: DateTime.utc_now()
      }

      {:ok, validated_params}
    else
      {:error, reason} -> {:error, {:parameter_validation_failed, reason}}
    end
  end

  defp validate_stream_source(source) do
    case get_stream_source_type(source) do
      :stream -> :ok
      :enumerable -> :ok
      :gen_stage -> :ok
      :phoenix_pubsub -> :ok
      _ -> {:error, :invalid_stream_source_type}
    end
  end

  defp validate_workflow_function(func) when is_function(func, 1), do: :ok
  defp validate_workflow_function(_), do: {:error, :invalid_workflow_function}

  defp validate_flow_control_strategy(strategy) when strategy in @supported_flow_strategies,
    do: :ok

  defp validate_flow_control_strategy(_), do: {:error, :invalid_flow_control_strategy}

  defp validate_streaming_configuration(config) when is_map(config) do
    # Validate key streaming parameters
    case {config.buffer_size, config.max_demand, config.timeout_ms} do
      {buffer, demand, timeout}
      when is_integer(buffer) and buffer > 0 and
             is_integer(demand) and demand > 0 and
             is_integer(timeout) and timeout > 0 ->
        :ok

      _ ->
        {:error, :invalid_streaming_configuration}
    end
  end

  defp validate_streaming_configuration(_), do: {:error, :invalid_streaming_configuration}

  defp optimize_streaming_configuration(config, targets, context) do
    # Optimize buffer size based on performance targets
    optimized_buffer_size = determine_optimal_buffer_size(config.buffer_size, targets, context)

    # Optimize demand based on throughput targets
    optimized_max_demand =
      determine_optimal_demand(config.max_demand, targets, optimized_buffer_size)

    # Optimize memory limits based on system capacity
    optimized_memory_limits = optimize_memory_limits(config.memory_limits, targets)

    optimized_config = %{
      buffer_size: optimized_buffer_size,
      max_demand: optimized_max_demand,
      timeout_ms: config.timeout_ms,
      enable_telemetry: config.enable_telemetry,
      memory_limits: optimized_memory_limits,
      optimization_metadata: %{
        original_buffer_size: config.buffer_size,
        original_max_demand: config.max_demand,
        optimization_applied: true,
        optimization_timestamp: DateTime.utc_now(),
        optimization_reasoning: build_optimization_reasoning(config, targets)
      }
    }

    Logger.debug("StreamWorkflowAction: Streaming configuration optimized",
      buffer_size: optimized_buffer_size,
      max_demand: optimized_max_demand,
      memory_limit_mb: optimized_memory_limits.max_buffer_memory_mb
    )

    {:ok, optimized_config}
  end

  defp determine_optimal_buffer_size(current_buffer, targets, _context) do
    # Determine optimal buffer size based on throughput targets
    target_throughput = targets.target_throughput_per_second

    optimal_buffer =
      case target_throughput do
        # High throughput needs larger buffer
        throughput when throughput > 500 -> 2000
        # Medium throughput
        throughput when throughput > 200 -> 1500
        # Standard throughput
        throughput when throughput > 50 -> 1000
        # Low throughput needs smaller buffer
        _ -> 500
      end

    # Ensure buffer is reasonable size
    max(100, min(optimal_buffer, 5000))
  end

  defp determine_optimal_demand(current_demand, targets, buffer_size) do
    # Optimize demand based on buffer size and targets
    # 10% of buffer size as base
    base_demand = div(buffer_size, 10)

    # Adjust based on throughput targets
    target_throughput = targets.target_throughput_per_second

    adjusted_demand =
      case target_throughput do
        throughput when throughput > 300 -> min(base_demand * 2, div(buffer_size, 3))
        throughput when throughput < 50 -> max(base_demand, 10)
        _ -> base_demand
      end

    # Ensure demand doesn't exceed buffer size
    max(1, min(adjusted_demand, buffer_size))
  end

  defp optimize_memory_limits(current_limits, targets) do
    # Optimize memory limits based on performance targets and system capacity
    base_limits = Map.merge(@default_streaming_config.memory_limits, current_limits)

    # Adjust based on throughput requirements
    target_throughput = targets.target_throughput_per_second

    case target_throughput do
      throughput when throughput > 400 ->
        # High throughput needs more memory
        %{
          base_limits
          | max_buffer_memory_mb: min(base_limits.max_buffer_memory_mb * 2, 1000),
            gc_threshold_mb: min(base_limits.gc_threshold_mb * 2, 200)
        }

      throughput when throughput < 50 ->
        # Low throughput can use less memory
        %{
          base_limits
          | max_buffer_memory_mb: max(base_limits.max_buffer_memory_mb / 2, 100),
            gc_threshold_mb: max(base_limits.gc_threshold_mb / 2, 50)
        }

      _ ->
        base_limits
    end
  end

  defp build_optimization_reasoning(original_config, targets) do
    %{
      buffer_size_reasoning:
        "Optimized based on throughput target of #{targets.target_throughput_per_second} elements/second",
      demand_reasoning: "Adjusted demand to balance throughput and buffer utilization",
      memory_reasoning: "Memory limits optimized for target performance without resource pressure"
    }
  end

  defp prepare_streaming_agent_params(validated_params, optimized_config, callbacks, context) do
    # Prepare parameters for ReactorStreamingAgent
    agent_params = %{
      stream_source: validated_params.stream_source,
      processing_function: validated_params.workflow_function,
      callback_handlers: callbacks,
      buffer_size: optimized_config.buffer_size,
      max_demand: optimized_config.max_demand,
      flow_control: validated_params.flow_control,
      timeout_ms: optimized_config.timeout_ms,
      enable_telemetry: optimized_config.enable_telemetry,
      memory_limits: optimized_config.memory_limits
    }

    {:ok, agent_params}
  end

  defp execute_streaming_workflow_with_agent(agent_params, context) do
    # Use ReactorStreamingAgent for actual streaming execution
    case ReactorStreamingAgent.start_agent(agent_params, context) do
      {:ok, agent_results} ->
        # Extract streaming results from agent response
        case extract_streaming_results(agent_results) do
          {:ok, results} -> {:ok, results}
          {:error, reason} -> {:error, {:result_extraction_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:streaming_agent_failed, reason}}
    end
  end

  defp extract_streaming_results(agent_results) do
    # Extract the actual streaming results from the agent response
    case agent_results do
      %{results: results, streaming_metadata: metadata} ->
        streaming_results = %{
          processed_data: results.processed_data,
          streaming_summary: results.streaming_summary,
          performance_analysis: results.performance_analysis,
          resource_utilization: results.resource_utilization,
          agent_metadata: metadata
        }

        {:ok, streaming_results}

      _ ->
        {:error, :invalid_agent_results_format}
    end
  end

  defp finalize_streaming_results(streaming_results, optimized_config, monitoring_enabled) do
    final_results = %{
      streamed_data: streaming_results.processed_data,
      streaming_summary:
        enhance_streaming_summary(streaming_results.streaming_summary, optimized_config),
      performance_analysis: streaming_results.performance_analysis,
      resource_utilization: streaming_results.resource_utilization,
      optimization_details: build_streaming_optimization_details(optimized_config),
      recommendations: generate_streaming_recommendations(streaming_results, optimized_config)
    }

    if monitoring_enabled do
      case notify_streaming_completion(final_results) do
        :ok -> {:ok, final_results}
        {:error, reason} -> {:error, {:monitoring_notification_failed, reason}}
      end
    else
      {:ok, final_results}
    end
  end

  defp enhance_streaming_summary(original_summary, optimized_config) do
    Map.merge(original_summary, %{
      configuration_used: %{
        buffer_size: optimized_config.buffer_size,
        max_demand: optimized_config.max_demand,
        optimization_applied: optimized_config.optimization_metadata.optimization_applied
      },
      execution_strategy: "Real-time streaming with ReactorStreamingAgent integration",
      optimization_reasoning: optimized_config.optimization_metadata.optimization_reasoning
    })
  end

  defp build_streaming_optimization_details(optimized_config) do
    %{
      buffer_optimization: %{
        applied: optimized_config.optimization_metadata.optimization_applied,
        buffer_size_used: optimized_config.buffer_size,
        original_buffer_size: optimized_config.optimization_metadata.original_buffer_size
      },
      demand_optimization: %{
        max_demand_used: optimized_config.max_demand,
        original_max_demand: optimized_config.optimization_metadata.original_max_demand,
        optimization_reasoning:
          optimized_config.optimization_metadata.optimization_reasoning.demand_reasoning
      },
      memory_optimization: %{
        memory_limits: optimized_config.memory_limits,
        gc_optimization: optimized_config.memory_limits.gc_threshold_mb,
        backpressure_enabled: optimized_config.memory_limits.enable_backpressure
      }
    }
  end

  defp generate_streaming_recommendations(streaming_results, optimized_config) do
    recommendations = []

    # Analyze streaming performance and generate recommendations
    recommendations =
      add_streaming_performance_recommendations(recommendations, streaming_results)

    recommendations = add_buffer_utilization_recommendations(recommendations, streaming_results)
    recommendations = add_backpressure_recommendations(recommendations, streaming_results)

    case recommendations do
      [] -> ["Current streaming configuration appears optimal for the workload"]
      _ -> recommendations
    end
  end

  defp add_streaming_performance_recommendations(recommendations, streaming_results) do
    if Map.has_key?(streaming_results.agent_metadata, :performance_metrics) do
      performance_metrics = streaming_results.agent_metadata.performance_metrics
      add_throughput_performance_recommendations(recommendations, performance_metrics)
    else
      recommendations
    end
  end

  defp add_throughput_performance_recommendations(recommendations, performance_metrics) do
    if Map.has_key?(performance_metrics, :throughput_per_second) do
      throughput = performance_metrics.throughput_per_second
      generate_throughput_recommendations(recommendations, throughput)
    else
      recommendations
    end
  end

  defp generate_throughput_recommendations(recommendations, throughput) do
    cond do
      throughput < 50 ->
        [
          "Consider increasing buffer size or optimizing workflow function for better throughput"
          | recommendations
        ]

      throughput > 1000 ->
        [
          "Excellent streaming performance - current configuration is highly optimized"
          | recommendations
        ]

      true ->
        recommendations
    end
  end

  defp add_buffer_utilization_recommendations(recommendations, streaming_results) do
    buffer_utilization = get_buffer_utilization(streaming_results)
    generate_buffer_recommendations(recommendations, buffer_utilization)
  end

  defp generate_buffer_recommendations(recommendations, buffer_utilization) do
    cond do
      buffer_utilization > 0.95 ->
        [
          "Buffer utilization is very high - consider increasing buffer size to prevent backpressure"
          | recommendations
        ]

      buffer_utilization < 0.2 ->
        [
          "Buffer utilization is low - consider reducing buffer size for memory efficiency"
          | recommendations
        ]

      true ->
        recommendations
    end
  end

  defp add_backpressure_recommendations(recommendations, streaming_results) do
    backpressure_events = get_backpressure_events(streaming_results)

    if backpressure_events > 5 do
      [
        "Frequent backpressure events detected - consider optimizing memory limits or processing function"
        | recommendations
      ]
    else
      recommendations
    end
  end

  # Helper functions

  defp get_stream_source_type(%Stream{}), do: :stream
  defp get_stream_source_type(data) when is_list(data), do: :enumerable
  defp get_stream_source_type({:gen_stage, _}), do: :gen_stage
  defp get_stream_source_type({:phoenix_pubsub, _}), do: :phoenix_pubsub
  defp get_stream_source_type(_), do: :unknown

  defp get_elements_processed(%{streamed_data: %{elements_processed: count}}), do: count
  defp get_elements_processed(%{streaming_summary: %{elements_processed: count}}), do: count
  defp get_elements_processed(_), do: 0

  defp get_buffer_utilization(%{streaming_summary: %{buffer_utilization: util}}), do: util
  defp get_buffer_utilization(%{streamed_data: %{buffer_utilization: util}}), do: util
  defp get_buffer_utilization(_), do: 0.0

  defp get_backpressure_events(%{streamed_data: %{backpressure_events: events}}), do: events
  defp get_backpressure_events(%{streaming_summary: %{backpressure_events: events}}), do: events
  defp get_backpressure_events(_), do: 0

  defp calculate_average_throughput(results, streaming_time_us) do
    elements = get_elements_processed(results)
    time_seconds = streaming_time_us / 1_000_000

    case time_seconds do
      t when t > 0 -> Float.round(elements / t, 2)
      _ -> 0.0
    end
  end

  defp calculate_streaming_performance_metrics(final_results, streaming_time_us) do
    elements_processed = get_elements_processed(final_results)

    %{
      throughput_per_second: calculate_average_throughput(final_results, streaming_time_us),
      average_element_processing_time_us:
        calculate_average_element_time(streaming_time_us, elements_processed),
      total_streaming_time_ms: div(streaming_time_us, 1_000),
      buffer_efficiency: calculate_buffer_efficiency(final_results),
      resource_efficiency: calculate_streaming_resource_efficiency(final_results)
    }
  end

  defp calculate_average_element_time(total_time_us, elements) when elements > 0 do
    div(total_time_us, elements)
  end

  defp calculate_average_element_time(_, _), do: 0

  defp calculate_buffer_efficiency(results) do
    buffer_utilization = get_buffer_utilization(results)
    backpressure_events = get_backpressure_events(results)

    # Efficiency decreases with excessive backpressure
    base_efficiency =
      case buffer_utilization do
        util when util >= 0.3 and util <= 0.8 -> 1.0
        util when util > 0.8 -> 0.8
        _ -> 0.6
      end

    # Penalty for backpressure events
    backpressure_penalty = min(0.5, backpressure_events * 0.1)

    Float.round(max(0.0, base_efficiency - backpressure_penalty), 3)
  end

  defp calculate_streaming_resource_efficiency(%{resource_utilization: resource_util}) do
    case resource_util do
      %{memory_efficiency: efficiency} when is_number(efficiency) -> efficiency
      # Default efficiency estimate
      _ -> 0.85
    end
  end

  defp calculate_streaming_resource_efficiency(_), do: 0.85

  defp notify_streaming_completion(final_results) do
    case WorkflowMonitor.notify_streaming_execution_completion(
           :stream_workflow_action,
           %{
             elements_processed: get_elements_processed(final_results),
             buffer_utilization: get_buffer_utilization(final_results),
             backpressure_events: get_backpressure_events(final_results)
           }
         ) do
      :ok -> :ok
      error -> error
    end
  end
end
