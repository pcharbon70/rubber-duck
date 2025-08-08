defmodule RubberDuck.Pipeline do
  @moduledoc """
  Main orchestrator for the GenStage-based entity update pipeline.

  This module provides the high-level interface for processing entity updates
  through the pipeline, managing the flow between producers, processors, and
  consumers.

  ## Architecture

  The pipeline consists of three main stages:

  1. **EntityUpdateProducer** - Manages incoming update requests with backpressure
  2. **EntityUpdateProcessor** - Processes core update logic concurrently
  3. **SideEffectProcessor** - Handles propagation and learning asynchronously

  ## Usage

      # Process an entity update through the pipeline
      Pipeline.process_entity_update(params, context)
      
      # Get pipeline status
      Pipeline.get_status()
      
      # Check pipeline health
      Pipeline.health_check()
  """

  require Logger

  alias RubberDuck.Pipeline.{
    EntityUpdateProducer,
    EntityUpdateProcessor,
    SideEffectProcessor
  }

  @timeout 30_000

  # Client API

  @doc """
  Processes an entity update through the GenStage pipeline.

  This is the main entry point for pipeline-based entity updates.
  Returns the result of the update operation.

  ## Options

  - `:timeout` - Maximum time to wait for processing (default: 30 seconds)
  - `:priority` - Priority level (:high, :normal, :low)
  - `:async` - If true, returns immediately without waiting for result
  """
  def process_entity_update(params, context, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @timeout)
    async = Keyword.get(opts, :async, false)

    if async do
      # Asynchronous processing - enqueue and return
      case EntityUpdateProducer.enqueue_update(params, context, opts) do
        :ok ->
          {:ok, :enqueued}

        {:error, reason} ->
          {:error, reason}
      end
    else
      # Synchronous processing - wait for result
      EntityUpdateProducer.sync_update(params, context, timeout: timeout)
    end
  end

  @doc """
  Processes multiple entity updates in batch.

  This is optimized for bulk operations and leverages the pipeline's
  concurrent processing capabilities.
  """
  def process_batch_updates(updates, opts \\ []) do
    priority = Keyword.get(opts, :priority, :normal)

    # Enqueue all updates
    results =
      Enum.map(updates, fn {params, context} ->
        EntityUpdateProducer.enqueue_update(params, context, priority: priority)
      end)

    # Check if all enqueued successfully
    failed = Enum.count(results, fn r -> r != :ok end)

    if failed == 0 do
      {:ok, %{enqueued: length(updates)}}
    else
      {:partial,
       %{
         enqueued: length(updates) - failed,
         failed: failed
       }}
    end
  end

  @doc """
  Returns comprehensive status of all pipeline stages.
  """
  def get_status do
    %{
      producer: get_producer_status(),
      processor: get_processor_status(),
      side_effects: get_side_effects_status(),
      health: calculate_health(),
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Performs a health check on the pipeline.

  Returns `:healthy`, `:degraded`, or `:unhealthy` based on
  the status of pipeline components.
  """
  def health_check do
    status = get_status()

    cond do
      is_unhealthy?(status) -> :unhealthy
      is_degraded?(status) -> :degraded
      true -> :healthy
    end
  end

  @doc """
  Retrieves metrics for the pipeline.

  Returns telemetry data and performance metrics for monitoring.
  """
  def get_metrics do
    %{
      throughput: calculate_throughput(),
      latency: calculate_latency(),
      error_rate: calculate_error_rate(),
      backpressure: check_backpressure(),
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Clears the dead letter queue for side effects.
  """
  def clear_dead_letters do
    SideEffectProcessor.get_dead_letters(1000)
  end

  @doc """
  Retries failed side effects from the dead letter queue.
  """
  def retry_dead_letters(count \\ 10) do
    SideEffectProcessor.retry_dead_letters(count)
  end

  # Private Functions

  defp get_producer_status do
    try do
      EntityUpdateProducer.get_queue_status()
    rescue
      _ -> %{error: "Producer unavailable"}
    end
  end

  defp get_processor_status do
    try do
      EntityUpdateProcessor.get_status()
    rescue
      _ -> %{error: "Processor unavailable"}
    end
  end

  defp get_side_effects_status do
    try do
      SideEffectProcessor.get_status()
    rescue
      _ -> %{error: "Side effects processor unavailable"}
    end
  end

  defp calculate_health do
    producer = get_producer_status()
    processor = get_processor_status()
    side_effects = get_side_effects_status()

    errors =
      [
        Map.get(producer, :error),
        Map.get(processor, :error),
        Map.get(side_effects, :error)
      ]
      |> Enum.filter(&(&1 != nil))

    if length(errors) > 0 do
      %{
        status: :unhealthy,
        errors: errors
      }
    else
      queue_size = get_in(producer, [:queue_size]) || 0
      buffer_size = get_in(producer, [:buffer_size]) || 10_000
      dlq_size = get_in(side_effects, [:dead_letter_queue_size]) || 0

      cond do
        queue_size > buffer_size * 0.9 ->
          %{status: :degraded, reason: "Queue near capacity"}

        dlq_size > 100 ->
          %{status: :degraded, reason: "High dead letter queue size"}

        true ->
          %{status: :healthy}
      end
    end
  end

  defp is_unhealthy?(%{health: %{status: :unhealthy}}), do: true
  defp is_unhealthy?(_), do: false

  defp is_degraded?(%{health: %{status: :degraded}}), do: true
  defp is_degraded?(_), do: false

  defp calculate_throughput do
    producer = get_producer_status()
    processor = get_processor_status()

    %{
      enqueued: get_in(producer, [:stats, :enqueued]) || 0,
      dispatched: get_in(producer, [:stats, :dispatched]) || 0,
      processed: get_in(processor, [:stats, :processed]) || 0,
      succeeded: get_in(processor, [:stats, :succeeded]) || 0
    }
  end

  defp calculate_latency do
    processor = get_processor_status()

    %{
      avg_processing_time_ms: get_in(processor, [:stats, :avg_processing_time_ms]) || 0
    }
  end

  defp calculate_error_rate do
    processor = get_processor_status()
    side_effects = get_side_effects_status()

    processor_processed = get_in(processor, [:stats, :processed]) || 0
    processor_failed = get_in(processor, [:stats, :failed]) || 0

    side_effects_processed = get_in(side_effects, [:stats, :processed]) || 0
    side_effects_failed = get_in(side_effects, [:stats, :failed]) || 0

    %{
      processor_error_rate: safe_divide(processor_failed, processor_processed),
      side_effects_error_rate: safe_divide(side_effects_failed, side_effects_processed)
    }
  end

  defp check_backpressure do
    producer = get_producer_status()

    queue_size = get_in(producer, [:queue_size]) || 0
    buffer_size = get_in(producer, [:buffer_size]) || 10_000
    pending_demand = get_in(producer, [:pending_demand]) || 0

    %{
      queue_utilization: safe_divide(queue_size, buffer_size),
      pending_demand: pending_demand,
      backpressure_active: queue_size > buffer_size * 0.8
    }
  end

  defp safe_divide(_numerator, 0), do: 0.0

  defp safe_divide(numerator, denominator) do
    numerator / denominator
  end
end
