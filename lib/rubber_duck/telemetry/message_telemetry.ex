defmodule RubberDuck.Telemetry.MessageTelemetry do
  @moduledoc """
  Telemetry module for tracking typed message routing and processing.

  Provides comprehensive metrics for:
  - Message routing performance
  - Handler execution times
  - Success/failure rates
  - Message type distribution
  - Priority-based metrics
  - Circuit breaker states

  ## Metrics Emitted

  ### Routing Metrics
  - `[:rubber_duck, :routing, :message, :start]` - Message routing started
  - `[:rubber_duck, :routing, :message, :stop]` - Message routing completed
  - `[:rubber_duck, :routing, :message, :exception]` - Message routing failed

  ### Handler Metrics  
  - `[:rubber_duck, :handler, :execute, :start]` - Handler execution started
  - `[:rubber_duck, :handler, :execute, :stop]` - Handler execution completed
  - `[:rubber_duck, :handler, :execute, :exception]` - Handler execution failed

  ### Batch Metrics
  - `[:rubber_duck, :routing, :batch, :start]` - Batch routing started
  - `[:rubber_duck, :routing, :batch, :stop]` - Batch routing completed

  ### Circuit Breaker Metrics
  - `[:rubber_duck, :circuit_breaker, :opened]` - Circuit breaker opened
  - `[:rubber_duck, :circuit_breaker, :closed]` - Circuit breaker closed
  - `[:rubber_duck, :circuit_breaker, :half_open]` - Circuit breaker half-open

  ## Usage

      # Attach default handlers
      MessageTelemetry.attach_handlers()
      
      # Custom handler attachment
      :telemetry.attach(
        "my-handler",
        [:rubber_duck, :routing, :message, :stop],
        &MyHandler.handle_event/4
      )
  """

  require Logger

  @doc """
  Attaches default telemetry handlers for logging and metrics collection.
  """
  def attach_handlers do
    handlers = [
      {[:rubber_duck, :routing, :message, :start], &handle_routing_start/4},
      {[:rubber_duck, :routing, :message, :stop], &handle_routing_stop/4},
      {[:rubber_duck, :routing, :message, :exception], &handle_routing_exception/4},
      {[:rubber_duck, :handler, :execute, :start], &handle_handler_start/4},
      {[:rubber_duck, :handler, :execute, :stop], &handle_handler_stop/4},
      {[:rubber_duck, :handler, :execute, :exception], &handle_handler_exception/4},
      {[:rubber_duck, :routing, :batch, :start], &handle_batch_start/4},
      {[:rubber_duck, :routing, :batch, :stop], &handle_batch_stop/4},
      {[:rubber_duck, :circuit_breaker, :opened], &handle_circuit_breaker_opened/4},
      {[:rubber_duck, :circuit_breaker, :closed], &handle_circuit_breaker_closed/4}
    ]

    Enum.each(handlers, fn {event, handler} ->
      handler_id = "message-telemetry-#{inspect(event)}"

      :telemetry.attach(
        handler_id,
        event,
        handler,
        nil
      )
    end)

    :ok
  end

  @doc """
  Detaches all default telemetry handlers.
  """
  def detach_handlers do
    events = [
      [:rubber_duck, :routing, :message, :start],
      [:rubber_duck, :routing, :message, :stop],
      [:rubber_duck, :routing, :message, :exception],
      [:rubber_duck, :handler, :execute, :start],
      [:rubber_duck, :handler, :execute, :stop],
      [:rubber_duck, :handler, :execute, :exception],
      [:rubber_duck, :routing, :batch, :start],
      [:rubber_duck, :routing, :batch, :stop],
      [:rubber_duck, :circuit_breaker, :opened],
      [:rubber_duck, :circuit_breaker, :closed]
    ]

    Enum.each(events, fn event ->
      handler_id = "message-telemetry-#{inspect(event)}"
      :telemetry.detach(handler_id)
    end)

    :ok
  end

  @doc """
  Emits telemetry for message routing start.
  """
  def emit_routing_start(message, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :routing, :message, :start],
      %{system_time: System.system_time()},
      Map.merge(
        %{
          message_type: message.__struct__,
          message_id: generate_message_id(message),
          priority: get_priority(message)
        },
        metadata
      )
    )
  end

  @doc """
  Emits telemetry for successful message routing.
  """
  def emit_routing_stop(message, duration, result, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :routing, :message, :stop],
      %{
        duration: duration,
        system_time: System.system_time()
      },
      Map.merge(
        %{
          message_type: message.__struct__,
          message_id: generate_message_id(message),
          priority: get_priority(message),
          success: match?({:ok, _}, result),
          result_type: classify_result(result)
        },
        metadata
      )
    )
  end

  @doc """
  Emits telemetry for message routing exceptions.
  """
  def emit_routing_exception(message, duration, kind, reason, stacktrace, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :routing, :message, :exception],
      %{
        duration: duration,
        system_time: System.system_time()
      },
      Map.merge(
        %{
          message_type: message.__struct__,
          message_id: generate_message_id(message),
          priority: get_priority(message),
          kind: kind,
          reason: inspect(reason),
          stacktrace: Exception.format_stacktrace(stacktrace)
        },
        metadata
      )
    )
  end

  @doc """
  Emits telemetry for batch routing operations.
  """
  def emit_batch_start(messages) do
    :telemetry.execute(
      [:rubber_duck, :routing, :batch, :start],
      %{
        system_time: System.system_time(),
        batch_size: length(messages)
      },
      %{
        message_types: Enum.frequencies_by(messages, & &1.__struct__),
        priorities: Enum.frequencies_by(messages, &get_priority/1)
      }
    )
  end

  def emit_batch_stop(messages, duration, results) do
    success_count = Enum.count(results, &match?({:ok, _}, &1))
    failure_count = length(results) - success_count

    :telemetry.execute(
      [:rubber_duck, :routing, :batch, :stop],
      %{
        duration: duration,
        system_time: System.system_time(),
        batch_size: length(messages),
        success_count: success_count,
        failure_count: failure_count,
        success_rate: if(length(results) > 0, do: success_count / length(results), else: 0)
      },
      %{
        message_types: Enum.frequencies_by(messages, & &1.__struct__),
        failed_types: extract_failed_types(messages, results)
      }
    )
  end

  @doc """
  Emits telemetry for handler execution.
  """
  def span_handler(message, handler_module, handler_function, context) do
    metadata = %{
      message_type: message.__struct__,
      message_id: generate_message_id(message),
      handler_module: handler_module,
      handler_function: handler_function,
      context_keys: Map.keys(context)
    }

    :telemetry.span(
      [:rubber_duck, :handler, :execute],
      metadata,
      fn ->
        result = apply(handler_module, handler_function, [message, context])
        {result, Map.put(metadata, :success, match?({:ok, _}, result))}
      end
    )
  end

  # Default event handlers

  defp handle_routing_start(_event, _measurements, metadata, _config) do
    if Application.get_env(:rubber_duck, :log_telemetry, false) do
      Logger.debug(
        "Message routing started",
        message_type: metadata.message_type,
        priority: metadata.priority,
        message_id: metadata[:message_id]
      )
    end
  end

  defp handle_routing_stop(_event, measurements, metadata, _config) do
    if metadata.success do
      # 5 seconds in microseconds
      if measurements.duration > 5_000_000 do
        Logger.warning(
          "Slow message routing detected",
          message_type: metadata.message_type,
          duration_ms: div(measurements.duration, 1_000),
          priority: metadata.priority
        )
      end
    else
      Logger.error(
        "Message routing failed",
        message_type: metadata.message_type,
        result_type: metadata.result_type,
        duration_ms: div(measurements.duration, 1_000)
      )
    end
  end

  defp handle_routing_exception(_event, measurements, metadata, _config) do
    Logger.error(
      "Message routing exception",
      message_type: metadata.message_type,
      kind: metadata.kind,
      reason: metadata.reason,
      duration_ms: div(measurements.duration, 1_000)
    )
  end

  defp handle_handler_start(_event, _measurements, metadata, _config) do
    if Application.get_env(:rubber_duck, :log_telemetry, false) do
      Logger.debug(
        "Handler execution started",
        handler: "#{metadata.handler_module}.#{metadata.handler_function}",
        message_type: metadata.message_type
      )
    end
  end

  defp handle_handler_stop(_event, measurements, metadata, _config) do
    # 10 seconds in microseconds
    if measurements.duration > 10_000_000 do
      Logger.warning(
        "Slow handler execution detected",
        handler: "#{metadata.handler_module}.#{metadata.handler_function}",
        message_type: metadata.message_type,
        duration_ms: div(measurements.duration, 1_000),
        success: metadata.success
      )
    end
  end

  defp handle_handler_exception(_event, measurements, metadata, _config) do
    Logger.error(
      "Handler execution failed",
      handler: "#{metadata.handler_module}.#{metadata.handler_function}",
      message_type: metadata.message_type,
      kind: metadata.kind,
      reason: metadata.reason,
      duration_ms: div(measurements.duration, 1_000)
    )
  end

  defp handle_batch_start(_event, measurements, metadata, _config) do
    if Application.get_env(:rubber_duck, :log_telemetry, false) do
      Logger.info(
        "Batch routing started",
        batch_size: measurements.batch_size,
        message_types: Map.keys(metadata.message_types),
        priorities: metadata.priorities
      )
    end
  end

  defp handle_batch_stop(_event, measurements, metadata, _config) do
    Logger.info(
      "Batch routing completed",
      batch_size: measurements.batch_size,
      duration_ms: div(measurements.duration, 1_000),
      success_rate: Float.round(measurements.success_rate * 100, 1),
      failed_types: metadata.failed_types
    )
  end

  defp handle_circuit_breaker_opened(_event, _measurements, metadata, _config) do
    Logger.warning(
      "Circuit breaker opened",
      message_type: metadata.message_type,
      failure_count: metadata.failure_count,
      threshold: metadata.threshold
    )
  end

  defp handle_circuit_breaker_closed(_event, _measurements, metadata, _config) do
    Logger.info(
      "Circuit breaker closed",
      message_type: metadata.message_type,
      recovery_time_ms: metadata[:recovery_time_ms]
    )
  end

  # Helper functions

  defp generate_message_id(message) do
    # Generate a unique ID for tracking
    hash = :erlang.phash2({message.__struct__, System.unique_integer()})
    Base.encode16(<<hash::32>>, case: :lower)
  end

  defp get_priority(message) do
    if function_exported?(RubberDuck.Protocol.Message, :priority, 1) do
      RubberDuck.Protocol.Message.priority(message)
    else
      :normal
    end
  rescue
    _ -> :normal
  end

  defp classify_result({:ok, _}), do: :success
  defp classify_result({:error, :timeout}), do: :timeout
  defp classify_result({:error, :no_handler}), do: :no_handler
  defp classify_result({:error, :no_route_defined}), do: :no_route
  defp classify_result({:error, {:handler_not_available, _, _}}), do: :handler_unavailable
  defp classify_result({:error, _}), do: :error
  defp classify_result(_), do: :unknown

  defp extract_failed_types(messages, results) do
    messages
    |> Enum.zip(results)
    |> Enum.filter(fn {_, result} -> not match?({:ok, _}, result) end)
    |> Enum.map(fn {msg, _} -> msg.__struct__ end)
    |> Enum.frequencies()
  end
end
