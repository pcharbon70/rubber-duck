defmodule RubberDuck.Workflows.Actions.ExecuteParallelAction do
  @moduledoc """
  Action for efficient parallel execution using ReactorMapReduceAgent integration.

  Provides intelligent parallel processing with comprehensive error handling,
  batch optimization, and seamless integration with existing workflow infrastructure.
  Leverages ReactorMapReduceAgent for sophisticated parallel data processing patterns.

  Features:
  - Intelligent parallel processing with optimal batch size determination
  - Comprehensive error handling with partial failure recovery strategies
  - Performance optimization through dynamic batch sizing and concurrency tuning
  - Integration with ReactorMapReduceAgent for advanced parallel processing capabilities
  - Resource-aware processing with automatic backpressure and memory management
  - Detailed performance analytics and optimization recommendations

  Usage Patterns:
  - **Batch Processing**: Parallel processing of large datasets with optimal batching
  - **Data Transformation**: Concurrent transformation of data collections with error recovery
  - **Workflow Acceleration**: Speed up workflow execution through intelligent parallelization
  - **Resource Optimization**: Efficient resource utilization with adaptive concurrency control
  """

  use Jido.Action,
    name: "execute_parallel",
    schema: [
      data_items: [type: {:list, :any}, required: true, doc: "Items to process in parallel"],
      processing_function: [
        type: :any,
        required: true,
        doc: "Function to apply to each data item"
      ],
      parallel_config: [type: :map, default: %{}, doc: "Parallel processing configuration"],
      error_strategy: [
        type: :atom,
        default: :partial_recovery,
        doc: "Error handling strategy (:fail_fast, :partial_recovery, :ignore_errors)"
      ],
      performance_targets: [type: :map, default: %{}, doc: "Performance targets for optimization"],
      monitoring_enabled: [type: :boolean, default: true, doc: "Enable performance monitoring"]
    ]

  require Logger

  alias RubberDuck.Agents.Workflow.ReactorMapReduceAgent
  alias RubberDuck.Workflows.WorkflowMonitor

  @supported_error_strategies [:fail_fast, :partial_recovery, :ignore_errors]

  @default_parallel_config %{
    batch_size: :auto,
    max_concurrency: :auto,
    timeout_ms: 30_000,
    optimization_strategy: :adaptive,
    enable_backpressure: true,
    memory_limit_mb: 500
  }

  @default_performance_targets %{
    target_throughput_per_second: 100,
    max_processing_time_ms: 60_000,
    min_success_rate: 0.95,
    max_memory_usage_mb: 1000
  }

  def run(params, context) do
    %{
      data_items: items,
      processing_function: func,
      parallel_config: config,
      error_strategy: error_strategy,
      performance_targets: targets,
      monitoring_enabled: monitoring
    } = params

    merged_config = Map.merge(@default_parallel_config, config)
    merged_targets = Map.merge(@default_performance_targets, targets)

    Logger.info("ExecuteParallelAction: Starting parallel execution",
      item_count: length(items),
      error_strategy: error_strategy,
      monitoring_enabled: monitoring
    )

    execution_start_time = System.monotonic_time(:microsecond)

    with {:ok, validated_params} <-
           validate_parallel_params(items, func, error_strategy, merged_config),
         {:ok, optimized_config} <-
           optimize_parallel_configuration(items, merged_config, merged_targets, context),
         {:ok, agent_params} <-
           prepare_map_reduce_agent_params(validated_params, optimized_config, context),
         {:ok, processing_results} <-
           execute_parallel_processing_with_agent(agent_params, context),
         {:ok, final_results} <-
           finalize_parallel_results(processing_results, optimized_config, monitoring) do
      execution_time = System.monotonic_time(:microsecond) - execution_start_time

      Logger.info("ExecuteParallelAction: Parallel execution completed successfully",
        items_processed: get_processed_count(final_results),
        execution_time_ms: div(execution_time, 1000),
        success_rate: calculate_success_rate(final_results)
      )

      {:ok,
       %{
         results: final_results,
         execution_metadata: %{
           execution_time_microseconds: execution_time,
           items_processed: get_processed_count(final_results),
           success_rate: calculate_success_rate(final_results),
           optimization_applied: optimized_config,
           performance_metrics: calculate_execution_metrics(final_results, execution_time)
         }
       }}
    else
      {:error, reason} ->
        Logger.error("ExecuteParallelAction: Parallel execution failed", error: reason)
        {:error, {:parallel_execution_failed, reason}}
    end
  end

  # Private implementation functions

  defp validate_parallel_params(items, func, error_strategy, config) do
    with :ok <- validate_data_items(items),
         :ok <- validate_processing_function(func),
         :ok <- validate_error_strategy(error_strategy),
         :ok <- validate_parallel_configuration(config) do
      validated_params = %{
        data_items: items,
        processing_function: func,
        error_strategy: error_strategy,
        config: config,
        validation_timestamp: DateTime.utc_now()
      }

      {:ok, validated_params}
    else
      {:error, reason} -> {:error, {:parameter_validation_failed, reason}}
    end
  end

  defp validate_data_items(items) when is_list(items) and length(items) > 0, do: :ok
  defp validate_data_items(_), do: {:error, :invalid_data_items}

  defp validate_processing_function(func) when is_function(func, 1), do: :ok
  defp validate_processing_function(_), do: {:error, :invalid_processing_function}

  defp validate_error_strategy(strategy) when strategy in @supported_error_strategies, do: :ok
  defp validate_error_strategy(_), do: {:error, :invalid_error_strategy}

  defp validate_parallel_configuration(config) when is_map(config) do
    # Validate key configuration parameters
    case {config.timeout_ms, config.memory_limit_mb} do
      {timeout, _} when is_integer(timeout) and timeout > 0 -> :ok
      {_, memory} when is_integer(memory) and memory > 0 -> :ok
      _ -> {:error, :invalid_configuration_parameters}
    end
  end

  defp validate_parallel_configuration(_), do: {:error, :invalid_parallel_configuration}

  defp optimize_parallel_configuration(items, config, targets, context) do
    item_count = length(items)

    optimized_batch_size =
      case config.batch_size do
        :auto -> determine_optimal_batch_size(item_count, config, targets)
        size when is_integer(size) and size > 0 -> size
        # Default fallback
        _ -> 100
      end

    optimized_concurrency =
      case config.max_concurrency do
        :auto -> determine_optimal_concurrency(item_count, optimized_batch_size, config, targets)
        concurrency when is_integer(concurrency) and concurrency > 0 -> concurrency
        # Default fallback
        _ -> :erlang.system_info(:schedulers_online)
      end

    optimized_config = %{
      batch_size: optimized_batch_size,
      max_concurrency: optimized_concurrency,
      timeout_ms: config.timeout_ms,
      optimization_strategy: config.optimization_strategy,
      enable_backpressure: config.enable_backpressure,
      memory_limit_mb: config.memory_limit_mb,
      optimization_metadata: %{
        original_batch_size: config.batch_size,
        original_concurrency: config.max_concurrency,
        optimization_applied: true,
        optimization_timestamp: DateTime.utc_now()
      }
    }

    Logger.debug("ExecuteParallelAction: Configuration optimized",
      batch_size: optimized_batch_size,
      max_concurrency: optimized_concurrency,
      optimization_strategy: config.optimization_strategy
    )

    {:ok, optimized_config}
  end

  defp determine_optimal_batch_size(item_count, config, targets) do
    # Determine optimal batch size based on data characteristics and targets
    base_batch_size =
      case item_count do
        count when count < 100 -> 10
        count when count < 1000 -> 50
        count when count < 10_000 -> 100
        _ -> 200
      end

    # Adjust based on memory limits
    memory_adjusted =
      case config.memory_limit_mb do
        limit when limit < 100 -> div(base_batch_size, 2)
        limit when limit > 500 -> min(base_batch_size * 2, 500)
        _ -> base_batch_size
      end

    # Ensure batch size doesn't exceed total items
    min(memory_adjusted, item_count)
  end

  defp determine_optimal_concurrency(item_count, batch_size, config, targets) do
    # Calculate number of batches
    batch_count = div(item_count, batch_size) + if rem(item_count, batch_size) > 0, do: 1, else: 0

    # Base concurrency on available schedulers and batch count
    max_schedulers = :erlang.system_info(:schedulers_online)
    optimal_concurrency = min(batch_count, max_schedulers)

    # Adjust based on memory limits and targets
    memory_adjusted =
      case config.memory_limit_mb do
        limit when limit < 200 -> max(1, div(optimal_concurrency, 2))
        limit when limit > 800 -> min(optimal_concurrency * 2, batch_count)
        _ -> optimal_concurrency
      end

    # Adjust based on performance targets
    target_adjusted =
      case targets.target_throughput_per_second do
        throughput when throughput > 200 -> min(memory_adjusted * 2, batch_count)
        throughput when throughput < 50 -> max(1, div(memory_adjusted, 2))
        _ -> memory_adjusted
      end

    max(1, target_adjusted)
  end

  defp prepare_map_reduce_agent_params(validated_params, optimized_config, context) do
    # Prepare parameters for ReactorMapReduceAgent
    agent_params = %{
      data_source: validated_params.data_items,
      map_function: validated_params.processing_function,
      # No reduction needed for this action
      reduce_function: nil,
      batch_size: optimized_config.batch_size,
      max_concurrency: optimized_config.max_concurrency,
      error_handling: validated_params.error_strategy,
      timeout_ms: optimized_config.timeout_ms,
      resource_limits: %{
        max_memory_mb: optimized_config.memory_limit_mb,
        enable_backpressure: optimized_config.enable_backpressure
      }
    }

    {:ok, agent_params}
  end

  defp execute_parallel_processing_with_agent(agent_params, context) do
    # Use ReactorMapReduceAgent for actual parallel processing
    case ReactorMapReduceAgent.start_agent(agent_params, context) do
      {:ok, agent_results} ->
        # Extract processing results from agent response
        case extract_processing_results(agent_results) do
          {:ok, results} -> {:ok, results}
          {:error, reason} -> {:error, {:result_extraction_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:map_reduce_agent_failed, reason}}
    end
  end

  defp extract_processing_results(agent_results) do
    # Extract the actual processing results from the agent response
    case agent_results do
      %{results: results, processing_metadata: metadata} ->
        processing_results = %{
          processed_data: results.data,
          processing_summary: results.processing_summary,
          performance_analysis: results.performance_analysis,
          resource_utilization: results.resource_utilization,
          agent_metadata: metadata
        }

        {:ok, processing_results}

      _ ->
        {:error, :invalid_agent_results_format}
    end
  end

  defp finalize_parallel_results(processing_results, optimized_config, monitoring_enabled) do
    final_results = %{
      processed_items: processing_results.processed_data,
      processing_summary:
        enhance_processing_summary(processing_results.processing_summary, optimized_config),
      performance_analysis: processing_results.performance_analysis,
      resource_utilization: processing_results.resource_utilization,
      optimization_details: build_optimization_details(optimized_config),
      recommendations: generate_optimization_recommendations(processing_results, optimized_config)
    }

    if monitoring_enabled do
      case notify_execution_completion(final_results) do
        :ok -> {:ok, final_results}
        {:error, reason} -> {:error, {:monitoring_notification_failed, reason}}
      end
    else
      {:ok, final_results}
    end
  end

  defp enhance_processing_summary(original_summary, optimized_config) do
    Map.merge(original_summary, %{
      configuration_used: %{
        batch_size: optimized_config.batch_size,
        max_concurrency: optimized_config.max_concurrency,
        optimization_applied: optimized_config.optimization_metadata.optimization_applied
      },
      execution_strategy: "Parallel execution with ReactorMapReduceAgent integration"
    })
  end

  defp build_optimization_details(optimized_config) do
    %{
      batch_optimization: %{
        applied: optimized_config.optimization_metadata.optimization_applied,
        batch_size_used: optimized_config.batch_size,
        original_batch_size: optimized_config.optimization_metadata.original_batch_size
      },
      concurrency_optimization: %{
        concurrency_used: optimized_config.max_concurrency,
        original_concurrency: optimized_config.optimization_metadata.original_concurrency,
        optimization_strategy: optimized_config.optimization_strategy
      },
      resource_management: %{
        memory_limit_mb: optimized_config.memory_limit_mb,
        backpressure_enabled: optimized_config.enable_backpressure
      }
    }
  end

  defp generate_optimization_recommendations(processing_results, optimized_config) do
    recommendations = []

    # Analyze performance and generate recommendations
    recommendations = add_performance_recommendations(recommendations, processing_results)

    recommendations =
      add_memory_recommendations(recommendations, processing_results, optimized_config)

    recommendations = add_concurrency_recommendations(recommendations, optimized_config)

    case recommendations do
      [] -> ["Current configuration appears optimal for the given workload"]
      _ -> recommendations
    end
  end

  defp add_performance_recommendations(recommendations, processing_results) do
    performance_metrics = processing_results.agent_metadata.performance_metrics

    if Map.has_key?(performance_metrics, :items_per_second) do
      add_throughput_recommendations(recommendations, performance_metrics.items_per_second)
    else
      recommendations
    end
  end

  defp add_throughput_recommendations(recommendations, throughput) do
    cond do
      throughput < 50 ->
        ["Consider increasing batch size or concurrency for better throughput" | recommendations]

      throughput > 500 ->
        [
          "Current configuration is highly efficient - consider maintaining settings"
          | recommendations
        ]

      true ->
        recommendations
    end
  end

  defp add_memory_recommendations(recommendations, processing_results, optimized_config) do
    resource_usage = processing_results.resource_utilization

    if Map.has_key?(resource_usage, :peak_memory_mb) do
      memory_usage = resource_usage.peak_memory_mb
      memory_limit = optimized_config.memory_limit_mb
      add_memory_usage_recommendations(recommendations, memory_usage, memory_limit)
    else
      recommendations
    end
  end

  defp add_memory_usage_recommendations(recommendations, memory_usage, memory_limit) do
    cond do
      memory_usage > memory_limit * 0.9 ->
        [
          "Consider increasing memory limits or reducing batch size to prevent memory pressure"
          | recommendations
        ]

      memory_usage < memory_limit * 0.3 ->
        [
          "Memory usage is low - consider increasing batch size for better efficiency"
          | recommendations
        ]

      true ->
        recommendations
    end
  end

  defp add_concurrency_recommendations(recommendations, optimized_config) do
    if optimized_config.max_concurrency == 1 do
      [
        "Single-threaded execution detected - consider increasing concurrency for parallel processing"
        | recommendations
      ]
    else
      recommendations
    end
  end

  # Helper functions

  defp get_processed_count(%{processed_items: items}) when is_list(items), do: length(items)
  defp get_processed_count(_), do: 0

  defp calculate_success_rate(%{processing_summary: summary}) do
    case {summary[:items_processed], summary[:errors_encountered]} do
      {processed, errors} when is_integer(processed) and is_integer(errors) ->
        total_attempted = processed + errors

        if total_attempted > 0 do
          Float.round(processed / total_attempted, 3)
        else
          0.0
        end

      # Default to success if no error information
      _ ->
        1.0
    end
  end

  defp calculate_success_rate(_), do: 1.0

  defp calculate_execution_metrics(final_results, execution_time_us) do
    items_processed = get_processed_count(final_results)
    execution_time_ms = div(execution_time_us, 1_000)

    %{
      throughput_per_second: calculate_throughput(items_processed, execution_time_ms),
      average_item_processing_time_us:
        calculate_average_item_time(execution_time_us, items_processed),
      total_execution_time_ms: execution_time_ms,
      efficiency_score: calculate_efficiency_score(final_results),
      resource_efficiency: calculate_resource_efficiency(final_results)
    }
  end

  defp calculate_throughput(items, time_ms) when time_ms > 0 do
    Float.round(items * 1000 / time_ms, 2)
  end

  defp calculate_throughput(_, _), do: 0.0

  defp calculate_average_item_time(total_time_us, items) when items > 0 do
    div(total_time_us, items)
  end

  defp calculate_average_item_time(_, _), do: 0

  defp calculate_efficiency_score(%{performance_analysis: analysis}) do
    Map.get(analysis, :efficiency_score, 0.85)
  end

  defp calculate_efficiency_score(_), do: 0.85

  defp calculate_resource_efficiency(%{resource_utilization: resource_util}) do
    case resource_util do
      %{memory_efficiency: efficiency} when is_number(efficiency) -> efficiency
      # Default efficiency estimate
      _ -> 0.80
    end
  end

  defp calculate_resource_efficiency(_), do: 0.80

  defp notify_execution_completion(final_results) do
    case WorkflowMonitor.notify_parallel_execution_completion(
           :execute_parallel_action,
           %{
             items_processed: get_processed_count(final_results),
             success_rate: calculate_success_rate(final_results)
           }
         ) do
      :ok -> :ok
      error -> error
    end
  end
end
