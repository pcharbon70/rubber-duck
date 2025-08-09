defmodule RubberDuck.Telemetry.ActionTracker do
  @moduledoc """
  Tracks action performance metrics for ML/AI operations.
  
  Monitors:
  - Action execution count and duration
  - Success/failure rates
  - Resource utilization per action type
  - Performance trends over time
  """

  use GenServer
  require Logger

  @doc "Start the Action Tracker GenServer"
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Record action start event"
  def action_start(action_type, resource, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :action, :start],
      %{count: 1, timestamp: System.monotonic_time()},
      Map.merge(metadata, %{action_type: action_type, resource: resource})
    )
  end

  @doc "Record action completion event"
  def action_complete(action_type, resource, duration_ms, status, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :action, :complete],
      %{
        count: 1,
        duration: duration_ms,
        timestamp: System.monotonic_time()
      },
      Map.merge(metadata, %{
        action_type: action_type,
        resource: resource,
        status: status
      })
    )
  end

  @doc "Record action error event"
  def action_error(action_type, resource, error_type, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :action, :error],
      %{count: 1, timestamp: System.monotonic_time()},
      Map.merge(metadata, %{
        action_type: action_type,
        resource: resource,
        error_type: error_type
      })
    )
  end

  @doc "Dispatch periodic action statistics"
  def dispatch_action_stats do
    GenServer.cast(__MODULE__, :dispatch_action_stats)
  end

  ## GenServer Implementation

  @impl true
  def init(_opts) do
    Logger.info("Starting Action Tracker for telemetry")
    
    # Attach to action events
    attach_handlers()
    
    {:ok, %{
      action_counts: %{},
      action_durations: %{},
      error_counts: %{},
      last_reset: System.monotonic_time()
    }}
  end

  @impl true
  def handle_cast(:dispatch_action_stats, state) do
    try do
      # Dispatch aggregated action statistics
      dispatch_action_aggregates(state)
      
      # Reset counters periodically (every hour)
      state = maybe_reset_counters(state)
      
      {:noreply, state}
    rescue
      error ->
        Logger.warning("Failed to dispatch action stats: #{inspect(error)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:action_event, event_type, measurements, metadata}, state) do
    # Process action events and update internal state
    new_state = process_action_event(state, event_type, measurements, metadata)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Action Tracker received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private Functions

  defp attach_handlers do
    events = [
      [:rubber_duck, :action, :start],
      [:rubber_duck, :action, :complete],
      [:rubber_duck, :action, :error]
    ]

    :telemetry.attach_many(
      "action-tracker-handler",
      events,
      &handle_action_event/4,
      self()
    )
  end

  defp handle_action_event(event, measurements, metadata, pid) do
    send(pid, {:action_event, event, measurements, metadata})
  end

  defp process_action_event(state, [:rubber_duck, :action, :start], _measurements, metadata) do
    action_key = action_key(metadata)
    
    %{
      state |
      action_counts: Map.update(state.action_counts, action_key, 1, &(&1 + 1))
    }
  end

  defp process_action_event(state, [:rubber_duck, :action, :complete], measurements, metadata) do
    action_key = action_key(metadata)
    duration = Map.get(measurements, :duration, 0)
    
    current_durations = Map.get(state.action_durations, action_key, [])
    new_durations = [duration | current_durations] |> Enum.take(100)  # Keep last 100
    
    %{
      state |
      action_durations: Map.put(state.action_durations, action_key, new_durations)
    }
  end

  defp process_action_event(state, [:rubber_duck, :action, :error], _measurements, metadata) do
    error_key = {action_key(metadata), Map.get(metadata, :error_type, :unknown)}
    
    %{
      state |
      error_counts: Map.update(state.error_counts, error_key, 1, &(&1 + 1))
    }
  end

  defp action_key(metadata) do
    {Map.get(metadata, :action_type, :unknown), Map.get(metadata, :resource, :unknown)}
  end

  defp dispatch_action_aggregates(state) do
    # Dispatch action count metrics
    for {{action_type, resource}, count} <- state.action_counts do
      :telemetry.execute(
        [:rubber_duck, :action, :count],
        %{value: count},
        %{action_type: action_type, resource: resource}
      )
    end

    # Dispatch action duration statistics
    for {{action_type, resource}, durations} <- state.action_durations do
      if length(durations) > 0 do
        avg_duration = Enum.sum(durations) / length(durations)
        max_duration = Enum.max(durations)
        min_duration = Enum.min(durations)
        p95_duration = calculate_percentile(durations, 95)
        
        :telemetry.execute(
          [:rubber_duck, :action, :duration, :stats],
          %{
            average: avg_duration,
            max: max_duration,
            min: min_duration,
            p95: p95_duration,
            count: length(durations)
          },
          %{action_type: action_type, resource: resource}
        )
      end
    end

    # Dispatch error rate metrics
    for {{action_key, error_type}, error_count} <- state.error_counts do
      {action_type, resource} = action_key
      total_count = Map.get(state.action_counts, action_key, 1)
      error_rate = error_count / total_count
      
      :telemetry.execute(
        [:rubber_duck, :action, :error, :rate],
        %{rate: error_rate, count: error_count},
        %{action_type: action_type, resource: resource, error_type: error_type}
      )
    end
  end

  defp maybe_reset_counters(state) do
    current_time = System.monotonic_time()
    hour_in_native = System.convert_time_unit(1, :hour, :native)
    
    if current_time - state.last_reset > hour_in_native do
      Logger.info("Resetting action tracker counters")
      %{
        state |
        action_counts: %{},
        action_durations: %{},
        error_counts: %{},
        last_reset: current_time
      }
    else
      state
    end
  end

  defp calculate_percentile(values, percentile) do
    sorted = Enum.sort(values)
    count = length(sorted)
    index = max(0, ceil(percentile / 100 * count) - 1)
    Enum.at(sorted, index, 0)
  end
end