defmodule RubberDuck.Telemetry.MessageReporter do
  @moduledoc """
  Telemetry reporter that aggregates and reports message routing metrics.

  This GenServer collects telemetry events and provides:
  - Real-time metrics aggregation
  - Performance statistics by message type
  - Success/failure rate tracking
  - Slow operation detection
  - Periodic reporting to logs or external systems

  ## Usage

      # Start the reporter
      {:ok, _pid} = MessageReporter.start_link()
      
      # Get current stats
      stats = MessageReporter.get_stats()
      
      # Get stats for specific message type
      type_stats = MessageReporter.get_type_stats(RubberDuck.Messages.Code.Analyze)
  """

  use GenServer
  require Logger

  @report_interval :timer.minutes(5)
  @slow_threshold_ms 1_000
  # @very_slow_threshold_ms 5_000

  defstruct [
    :start_time,
    :total_routed,
    :total_succeeded,
    :total_failed,
    :total_duration_us,
    :by_type,
    :by_priority,
    :slow_operations,
    :circuit_breaker_events,
    :last_report_at
  ]

  # Client API

  @doc """
  Starts the telemetry reporter.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets current aggregated statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Gets statistics for a specific message type.
  """
  def get_type_stats(message_type) do
    GenServer.call(__MODULE__, {:get_type_stats, message_type})
  end

  @doc """
  Resets all collected statistics.
  """
  def reset_stats do
    GenServer.cast(__MODULE__, :reset_stats)
  end

  @doc """
  Forces an immediate report of current statistics.
  """
  def report_now do
    GenServer.cast(__MODULE__, :report_now)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    # Attach to telemetry events
    attach_telemetry_handlers()

    # Schedule periodic reporting
    report_interval = Keyword.get(opts, :report_interval, @report_interval)
    schedule_report(report_interval)

    state = %__MODULE__{
      start_time: System.system_time(:second),
      total_routed: 0,
      total_succeeded: 0,
      total_failed: 0,
      total_duration_us: 0,
      by_type: %{},
      by_priority: %{},
      slow_operations: [],
      circuit_breaker_events: [],
      last_report_at: System.system_time(:second)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = compile_stats(state)
    {:reply, stats, state}
  end

  @impl true
  def handle_call({:get_type_stats, message_type}, _from, state) do
    type_stats = Map.get(state.by_type, message_type, default_type_stats())
    {:reply, type_stats, state}
  end

  @impl true
  def handle_cast(:reset_stats, state) do
    new_state = %{
      state
      | total_routed: 0,
        total_succeeded: 0,
        total_failed: 0,
        total_duration_us: 0,
        by_type: %{},
        by_priority: %{},
        slow_operations: [],
        circuit_breaker_events: []
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:report_now, state) do
    generate_report(state)
    {:noreply, %{state | last_report_at: System.system_time(:second)}}
  end

  @impl true
  def handle_info(:report, state) do
    generate_report(state)
    schedule_report(@report_interval)
    {:noreply, %{state | last_report_at: System.system_time(:second)}}
  end

  @impl true
  def handle_info({:telemetry_event, event, measurements, metadata}, state) do
    new_state = process_telemetry_event(event, measurements, metadata, state)
    {:noreply, new_state}
  end

  # Telemetry event processing

  defp process_telemetry_event(
         [:rubber_duck, :routing, :message, :stop],
         measurements,
         metadata,
         state
       ) do
    duration_ms = measurements.duration / 1_000

    # Update totals
    state = %{
      state
      | total_routed: state.total_routed + 1,
        total_succeeded:
          if(metadata.success, do: state.total_succeeded + 1, else: state.total_succeeded),
        total_failed:
          if(metadata.success, do: state.total_failed, else: state.total_failed + 1),
        total_duration_us: state.total_duration_us + measurements.duration
    }

    # Update by type
    type_stats = Map.get(state.by_type, metadata.message_type, default_type_stats())

    updated_type_stats = %{
      type_stats
      | count: type_stats.count + 1,
        succeeded: if(metadata.success, do: type_stats.succeeded + 1, else: type_stats.succeeded),
        failed: if(metadata.success, do: type_stats.failed, else: type_stats.failed + 1),
        total_duration_us: type_stats.total_duration_us + measurements.duration,
        min_duration_us: min(type_stats.min_duration_us, measurements.duration),
        max_duration_us: max(type_stats.max_duration_us, measurements.duration)
    }

    state = %{state | by_type: Map.put(state.by_type, metadata.message_type, updated_type_stats)}

    # Update by priority
    priority_stats = Map.get(state.by_priority, metadata.priority, default_priority_stats())

    updated_priority_stats = %{
      priority_stats
      | count: priority_stats.count + 1,
        total_duration_us: priority_stats.total_duration_us + measurements.duration
    }

    state = %{
      state
      | by_priority: Map.put(state.by_priority, metadata.priority, updated_priority_stats)
    }

    # Track slow operations
    if duration_ms > @slow_threshold_ms do
      slow_op = %{
        message_type: metadata.message_type,
        duration_ms: duration_ms,
        priority: metadata.priority,
        timestamp: System.system_time(:second)
      }

      # Keep only last 100 slow operations
      slow_operations = [slow_op | state.slow_operations] |> Enum.take(100)

      %{state | slow_operations: slow_operations}
    else
      state
    end
  end

  defp process_telemetry_event(
         [:rubber_duck, :circuit_breaker, event],
         _measurements,
         metadata,
         state
       ) do
    cb_event = %{
      event: event,
      message_type: metadata.message_type,
      timestamp: System.system_time(:second),
      metadata: metadata
    }

    # Keep only last 50 circuit breaker events
    cb_events = [cb_event | state.circuit_breaker_events] |> Enum.take(50)

    %{state | circuit_breaker_events: cb_events}
  end

  defp process_telemetry_event(_event, _measurements, _metadata, state) do
    state
  end

  # Reporting

  defp generate_report(state) do
    stats = compile_stats(state)

    Logger.info("""

    ====== Message Routing Performance Report ======
    Period: #{format_duration(stats.period_seconds)}

    Overall Statistics:
      Total Routed: #{stats.total_routed}
      Success Rate: #{Float.round(stats.success_rate * 100, 2)}%
      Average Duration: #{Float.round(stats.avg_duration_ms, 2)}ms
      
    By Priority:
    #{format_priority_stats(stats.by_priority)}

    Top Message Types by Volume:
    #{format_top_types(stats.top_types_by_volume)}

    Slowest Message Types:
    #{format_slowest_types(stats.slowest_types)}

    Recent Slow Operations: #{length(state.slow_operations)}
    Circuit Breaker Events: #{length(state.circuit_breaker_events)}
    ================================================
    """)

    # Send to external monitoring if configured
    if Application.get_env(:rubber_duck, :send_telemetry_to_external, false) do
      send_to_external_monitoring(stats)
    end
  end

  defp compile_stats(state) do
    period_seconds = System.system_time(:second) - state.start_time

    %{
      period_seconds: period_seconds,
      total_routed: state.total_routed,
      total_succeeded: state.total_succeeded,
      total_failed: state.total_failed,
      success_rate:
        if(state.total_routed > 0, do: state.total_succeeded / state.total_routed, else: 0),
      avg_duration_ms:
        if(state.total_routed > 0,
          do: state.total_duration_us / state.total_routed / 1_000,
          else: 0
        ),
      by_type: state.by_type,
      by_priority: state.by_priority,
      top_types_by_volume: get_top_types_by_volume(state.by_type, 5),
      slowest_types: get_slowest_types(state.by_type, 5),
      slow_operations_count: length(state.slow_operations),
      circuit_breaker_events_count: length(state.circuit_breaker_events)
    }
  end

  defp get_top_types_by_volume(by_type, limit) do
    by_type
    |> Enum.sort_by(fn {_type, stats} -> -stats.count end)
    |> Enum.take(limit)
    |> Enum.map(fn {type, stats} ->
      %{
        type: inspect(type),
        count: stats.count,
        success_rate: if(stats.count > 0, do: stats.succeeded / stats.count, else: 0),
        avg_duration_ms:
          if(stats.count > 0, do: stats.total_duration_us / stats.count / 1_000, else: 0)
      }
    end)
  end

  defp get_slowest_types(by_type, limit) do
    by_type
    |> Enum.filter(fn {_type, stats} -> stats.count > 0 end)
    |> Enum.sort_by(fn {_type, stats} -> -(stats.total_duration_us / stats.count) end)
    |> Enum.take(limit)
    |> Enum.map(fn {type, stats} ->
      %{
        type: inspect(type),
        avg_duration_ms: stats.total_duration_us / stats.count / 1_000,
        max_duration_ms: stats.max_duration_us / 1_000,
        count: stats.count
      }
    end)
  end

  # Formatting helpers

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) when seconds < 3600,
    do: "#{div(seconds, 60)}m #{rem(seconds, 60)}s"

  defp format_duration(seconds), do: "#{div(seconds, 3600)}h #{rem(div(seconds, 60), 60)}m"

  defp format_priority_stats(by_priority) do
    by_priority
    |> Enum.sort_by(fn {priority, _} -> priority_order(priority) end)
    |> Enum.map(fn {priority, stats} ->
      avg_ms =
        if(stats.count > 0,
          do: Float.round(stats.total_duration_us / stats.count / 1_000, 2),
          else: 0
        )

      "    #{String.pad_trailing(to_string(priority), 10)} Count: #{String.pad_leading(to_string(stats.count), 6)}  Avg: #{avg_ms}ms"
    end)
    |> Enum.join("\n")
  end

  defp format_top_types(types) do
    types
    |> Enum.with_index(1)
    |> Enum.map(fn {type, idx} ->
      "    #{idx}. #{type.type} (#{type.count} calls, #{Float.round(type.success_rate * 100, 1)}% success, #{Float.round(type.avg_duration_ms, 2)}ms avg)"
    end)
    |> Enum.join("\n")
  end

  defp format_slowest_types(types) do
    types
    |> Enum.with_index(1)
    |> Enum.map(fn {type, idx} ->
      "    #{idx}. #{type.type} (#{Float.round(type.avg_duration_ms, 2)}ms avg, #{Float.round(type.max_duration_ms, 2)}ms max)"
    end)
    |> Enum.join("\n")
  end

  defp priority_order(:critical), do: 0
  defp priority_order(:high), do: 1
  defp priority_order(:normal), do: 2
  defp priority_order(:low), do: 3
  defp priority_order(_), do: 4

  # Default structures

  defp default_type_stats do
    %{
      count: 0,
      succeeded: 0,
      failed: 0,
      total_duration_us: 0,
      min_duration_us: :infinity,
      max_duration_us: 0
    }
  end

  defp default_priority_stats do
    %{
      count: 0,
      total_duration_us: 0
    }
  end

  # External monitoring integration

  defp send_to_external_monitoring(_stats) do
    # This would integrate with DataDog, New Relic, etc.
    # For now, just a placeholder
    :ok
  end

  # Telemetry attachment

  defp attach_telemetry_handlers do
    events = [
      [:rubber_duck, :routing, :message, :stop],
      [:rubber_duck, :circuit_breaker, :opened],
      [:rubber_duck, :circuit_breaker, :closed],
      [:rubber_duck, :circuit_breaker, :half_open]
    ]

    Enum.each(events, fn event ->
      handler_id = "message-reporter-#{inspect(event)}"

      :telemetry.attach(
        handler_id,
        event,
        &handle_telemetry_event/4,
        self()
      )
    end)
  end

  defp handle_telemetry_event(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end

  defp schedule_report(interval) do
    Process.send_after(self(), :report, interval)
  end
end
