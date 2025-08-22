defmodule RubberDuck.ErrorReporting.Aggregator do
  @moduledoc """
  Error aggregation system for collecting and processing errors across the application.

  Features:
  - Error deduplication and grouping
  - Error rate limiting
  - Context enrichment integration
  - Pattern detection integration
  - Telemetry integration
  """

  use GenServer
  require Logger

  alias RubberDuck.ErrorReporting.TowerReporter

  @batch_size 50
  # 5 seconds
  @batch_timeout 5_000
  @max_error_history 1000

  defstruct [
    :error_buffer,
    :error_history,
    :error_counts,
    :batch_timer,
    :last_flush
  ]

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def report_error(error, context \\ %{}) do
    GenServer.cast(__MODULE__, {:report_error, error, context, DateTime.utc_now()})
  end

  def get_error_stats do
    GenServer.call(__MODULE__, :get_error_stats)
  end

  def get_recent_errors(limit \\ 20) do
    GenServer.call(__MODULE__, {:get_recent_errors, limit})
  end

  def flush_errors do
    GenServer.cast(__MODULE__, :flush_errors)
  end

  ## Server Implementation

  @impl true
  def init(_opts) do
    Logger.info("Starting Error Reporting Aggregator")

    state = %__MODULE__{
      error_buffer: [],
      error_history: [],
      error_counts: %{},
      batch_timer: nil,
      last_flush: DateTime.utc_now()
    }

    # Schedule initial flush
    schedule_batch_flush()

    {:ok, state}
  end

  @impl true
  def handle_call(:get_error_stats, _from, state) do
    stats = %{
      buffered_errors: length(state.error_buffer),
      total_error_count: Enum.sum(Map.values(state.error_counts)),
      unique_error_types: map_size(state.error_counts),
      last_flush: state.last_flush,
      error_rates: calculate_error_rates(state.error_history)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:get_recent_errors, limit}, _from, state) do
    recent_errors = Enum.take(state.error_history, limit)
    {:reply, recent_errors, state}
  end

  @impl true
  def handle_cast({:report_error, error, context, timestamp}, state) do
    # Create enriched error entry
    error_entry = %{
      error: error,
      context: context,
      timestamp: timestamp,
      error_id: generate_error_id(error),
      error_type: classify_error(error)
    }

    # Add to buffer
    updated_buffer = [error_entry | state.error_buffer]

    # Update error counts
    updated_counts = Map.update(state.error_counts, error_entry.error_type, 1, &(&1 + 1))

    new_state = %{state | error_buffer: updated_buffer, error_counts: updated_counts}

    # Check if we should flush immediately
    if length(updated_buffer) >= @batch_size do
      final_state = flush_error_batch(new_state)
      {:noreply, final_state}
    else
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast(:flush_errors, state) do
    new_state = flush_error_batch(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:batch_flush_timeout, state) do
    new_state = flush_error_batch(state)

    # Schedule next flush
    schedule_batch_flush()

    {:noreply, new_state}
  end

  ## Internal Functions

  defp flush_error_batch(state) when state.error_buffer == [] do
    # No errors to flush
    state
  end

  defp flush_error_batch(state) do
    # Reverse buffer to get chronological order
    errors_to_process = Enum.reverse(state.error_buffer)

    # Enrich errors with context
    enriched_errors = enrich_error_batch(errors_to_process)

    # Detect patterns
    pattern_analysis = detect_error_patterns(enriched_errors)

    # Update error history
    updated_history =
      (enriched_errors ++ state.error_history)
      |> Enum.take(@max_error_history)

    # Emit telemetry
    emit_error_telemetry(enriched_errors, pattern_analysis)

    # Process through external systems (Tower, etc.)
    process_external_reporting(enriched_errors)

    Logger.info("Processed batch of #{length(errors_to_process)} errors")

    %{state | error_buffer: [], error_history: updated_history, last_flush: DateTime.utc_now()}
  end

  defp enrich_error_batch(errors) do
    Enum.map(errors, fn error_entry ->
      # Add system context
      system_context = %{
        node: Node.self(),
        vm_memory: :erlang.memory(:total),
        process_count: :erlang.system_info(:process_count),
        scheduler_utilization: get_scheduler_utilization()
      }

      # Merge with existing context
      enriched_context = Map.merge(error_entry.context, system_context)

      %{error_entry | context: enriched_context}
    end)
  end

  defp detect_error_patterns(errors) do
    # Group errors by type and analyze patterns
    grouped_errors = Enum.group_by(errors, & &1.error_type)

    patterns =
      Map.new(grouped_errors, fn {error_type, error_list} ->
        pattern_info = %{
          count: length(error_list),
          frequency: calculate_frequency(error_list),
          first_occurrence: List.last(error_list).timestamp,
          last_occurrence: List.first(error_list).timestamp,
          trend: analyze_error_trend(error_list)
        }

        {error_type, pattern_info}
      end)

    # Detect anomalies
    anomalies = detect_error_anomalies(patterns)

    %{
      patterns: patterns,
      anomalies: anomalies,
      total_errors: length(errors),
      analysis_timestamp: DateTime.utc_now()
    }
  end

  defp calculate_frequency(error_list) do
    if length(error_list) < 2 do
      0.0
    else
      first_time = List.last(error_list).timestamp
      last_time = List.first(error_list).timestamp

      time_diff_seconds = DateTime.diff(last_time, first_time, :second)

      if time_diff_seconds > 0 do
        length(error_list) / time_diff_seconds
      else
        0.0
      end
    end
  end

  defp analyze_error_trend(error_list) when length(error_list) < 3, do: :insufficient_data

  defp analyze_error_trend(error_list) do
    # Simple trend analysis based on time intervals
    intervals =
      error_list
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [newer, older] ->
        DateTime.diff(newer.timestamp, older.timestamp, :second)
      end)

    if length(intervals) > 0 do
      avg_interval = Enum.sum(intervals) / length(intervals)

      cond do
        # Errors within 1 minute
        avg_interval < 60 -> :increasing
        # Errors within 5 minutes
        avg_interval < 300 -> :moderate
        # Sparse errors
        true -> :decreasing
      end
    else
      :stable
    end
  end

  defp detect_error_anomalies(patterns) do
    Enum.filter(patterns, fn {_error_type, pattern_info} ->
      # Detect anomalous patterns
      # More than 1 error per second
      # Rapidly increasing errors
      pattern_info.frequency > 1.0 or
        pattern_info.trend == :increasing
    end)
    |> Map.new()
  end

  defp emit_error_telemetry(errors, pattern_analysis) do
    # Emit batch telemetry
    :telemetry.execute(
      [:rubber_duck, :error_reporting, :batch_processed],
      %{
        error_count: length(errors),
        unique_types: map_size(pattern_analysis.patterns),
        anomaly_count: map_size(pattern_analysis.anomalies)
      },
      %{
        patterns: pattern_analysis.patterns,
        anomalies: pattern_analysis.anomalies
      }
    )

    # Emit individual error type telemetries
    Enum.each(pattern_analysis.patterns, fn {error_type, pattern_info} ->
      :telemetry.execute(
        [:rubber_duck, :error_reporting, :error_type],
        %{
          count: pattern_info.count,
          frequency: pattern_info.frequency
        },
        %{
          error_type: error_type,
          trend: pattern_info.trend
        }
      )
    end)
  end

  defp process_external_reporting(errors) do
    # Send to Tower if configured and available
    if Application.get_env(:rubber_duck, :enable_tower, false) do
      TowerReporter.report_batch(errors)
    end

    # Send to other external systems
    # Add additional integrations here
  end

  defp calculate_error_rates(error_history) do
    now = DateTime.utc_now()

    # Calculate rates for different time windows
    %{
      last_minute: count_errors_in_window(error_history, now, 60),
      last_5_minutes: count_errors_in_window(error_history, now, 300),
      last_hour: count_errors_in_window(error_history, now, 3600)
    }
  end

  defp count_errors_in_window(error_history, now, window_seconds) do
    cutoff_time = DateTime.add(now, -window_seconds, :second)

    Enum.count(error_history, fn error ->
      DateTime.compare(error.timestamp, cutoff_time) == :gt
    end)
  end

  defp generate_error_id(error) do
    # Generate a hash-based ID for error deduplication
    error_content = %{
      type: classify_error(error),
      message: extract_error_message(error),
      module: extract_error_module(error)
    }

    :crypto.hash(:sha256, :erlang.term_to_binary(error_content))
    |> Base.encode16(case: :lower)
    # First 16 characters
    |> String.slice(0, 16)
  end

  defp classify_error(error) do
    case error do
      %{__exception__: true, __struct__: module} -> module
      {error_type, _} when is_atom(error_type) -> error_type
      error when is_atom(error) -> error
      _ -> :unknown_error
    end
  end

  defp extract_error_message(error) do
    case error do
      %{message: message} -> message
      {_, message} when is_binary(message) -> message
      _ -> inspect(error)
    end
  end

  defp extract_error_module(error) do
    case error do
      %{__struct__: module} -> module
      _ -> :unknown
    end
  end

  defp get_scheduler_utilization do
    case safe_scheduler_utilization() do
      {:ok, utilization} -> utilization
      {:error, _} -> 0.0
    end
  end

  defp safe_scheduler_utilization do
    case :scheduler.utilization(1) do
      usage when is_list(usage) ->
        {total_active, total_time} =
          Enum.reduce(usage, {0, 0}, fn
            {_scheduler_id, active, total}, {acc_active, acc_total} ->
              {acc_active + active, acc_total + total}

            _, acc ->
              acc
          end)

        utilization = if total_time > 0, do: total_active / total_time, else: 0.0
        {:ok, utilization}

      _ ->
        {:ok, 0.0}
    end
  rescue
    _ -> {:error, :scheduler_unavailable}
  end

  defp schedule_batch_flush do
    Process.send_after(self(), :batch_flush_timeout, @batch_timeout)
  end
end
