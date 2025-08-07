defmodule RubberDuck.Telemetry.BatchingTelemetry do
  @moduledoc """
  Telemetry events for the GenStage batching pipeline.
  
  Provides comprehensive metrics for:
  - Producer buffer status and operations
  - Batch creation and processing
  - Consumer demand and back-pressure
  - Adaptive sizing changes
  """
  
  require Logger
  
  @doc """
  Emits telemetry when the message producer starts.
  """
  def emit_producer_started(config) do
    :telemetry.execute(
      [:rubber_duck, :batching, :producer, :started],
      %{count: 1},
      %{config: config}
    )
  end
  
  @doc """
  Emits telemetry when a message is enqueued.
  """
  def emit_message_enqueued(message_type, buffer_size) do
    :telemetry.execute(
      [:rubber_duck, :batching, :producer, :message_enqueued],
      %{
        buffer_size: buffer_size,
        count: 1
      },
      %{message_type: message_type}
    )
  end
  
  @doc """
  Emits telemetry when buffer overflow occurs.
  """
  def emit_buffer_overflow(buffer_size) do
    :telemetry.execute(
      [:rubber_duck, :batching, :producer, :buffer_overflow],
      %{
        buffer_size: buffer_size,
        count: 1
      },
      %{}
    )
  end
  
  @doc """
  Emits telemetry when demand is received from consumers.
  """
  def emit_demand_received(demand, buffer_size) do
    :telemetry.execute(
      [:rubber_duck, :batching, :producer, :demand_received],
      %{
        demand: demand,
        buffer_size: buffer_size
      },
      %{}
    )
  end
  
  @doc """
  Emits telemetry when a batch is created.
  """
  def emit_batch_created(batch_size, trigger, remaining_buffer) do
    :telemetry.execute(
      [:rubber_duck, :batching, :batch, :created],
      %{
        batch_size: batch_size,
        remaining_buffer: remaining_buffer,
        count: 1
      },
      %{trigger: trigger}
    )
  end
  
  @doc """
  Emits telemetry when a batch is processed by a consumer.
  """
  def emit_batch_processed(batch_size, processing_time_us, priority) do
    :telemetry.execute(
      [:rubber_duck, :batching, :batch, :processed],
      %{
        batch_size: batch_size,
        processing_time_us: processing_time_us,
        count: 1
      },
      %{priority: priority}
    )
  end
  
  @doc """
  Emits telemetry when a batch processing fails.
  """
  def emit_batch_failed(batch_size, error, priority) do
    :telemetry.execute(
      [:rubber_duck, :batching, :batch, :failed],
      %{
        batch_size: batch_size,
        count: 1
      },
      %{
        priority: priority,
        error: inspect(error)
      }
    )
  end
  
  @doc """
  Emits telemetry when consumer demands more events.
  """
  def emit_consumer_demand(consumer, demand, priority) do
    :telemetry.execute(
      [:rubber_duck, :batching, :consumer, :demand],
      %{
        demand: demand,
        count: 1
      },
      %{
        consumer: consumer,
        priority: priority
      }
    )
  end
  
  @doc """
  Emits telemetry when back-pressure is applied.
  """
  def emit_backpressure_applied(buffer_size, rejected_count) do
    :telemetry.execute(
      [:rubber_duck, :batching, :backpressure, :applied],
      %{
        buffer_size: buffer_size,
        rejected_count: rejected_count
      },
      %{}
    )
  end
  
  @doc """
  Emits telemetry when adaptive batch size changes.
  """
  def emit_adaptive_size_changed(new_size, old_size \\ nil) do
    measurements = %{
      new_size: new_size,
      count: 1
    }
    
    measurements = if old_size do
      Map.put(measurements, :size_delta, new_size - old_size)
    else
      measurements
    end
    
    :telemetry.execute(
      [:rubber_duck, :batching, :adaptive, :size_changed],
      measurements,
      %{}
    )
  end
  
  @doc """
  Emits telemetry when configuration is updated.
  """
  def emit_config_updated(config) do
    :telemetry.execute(
      [:rubber_duck, :batching, :config, :updated],
      %{count: 1},
      %{config: config}
    )
  end
  
  @doc """
  Returns all telemetry event names for the batching system.
  """
  def events do
    [
      [:rubber_duck, :batching, :producer, :started],
      [:rubber_duck, :batching, :producer, :message_enqueued],
      [:rubber_duck, :batching, :producer, :buffer_overflow],
      [:rubber_duck, :batching, :producer, :demand_received],
      [:rubber_duck, :batching, :batch, :created],
      [:rubber_duck, :batching, :batch, :processed],
      [:rubber_duck, :batching, :batch, :failed],
      [:rubber_duck, :batching, :consumer, :demand],
      [:rubber_duck, :batching, :backpressure, :applied],
      [:rubber_duck, :batching, :adaptive, :size_changed],
      [:rubber_duck, :batching, :config, :updated]
    ]
  end
  
  @doc """
  Attaches default handlers for batching telemetry events.
  """
  def attach_default_handlers do
    events()
    |> Enum.each(fn event ->
      handler_id = "#{__MODULE__}-#{Enum.join(event, "-")}"
      
      :telemetry.attach(
        handler_id,
        event,
        &handle_event/4,
        nil
      )
    end)
  end
  
  # Default handler for logging telemetry events
  defp handle_event(event, measurements, metadata, _config) do
    event_name = Enum.join(event, ".")
    
    Logger.debug(
      "Telemetry event: #{event_name}",
      measurements: measurements,
      metadata: metadata
    )
  end
end