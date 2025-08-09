defmodule RubberDuck.Telemetry.ActionTelemetry do
  @moduledoc """
  Telemetry helpers for instrumenting Jido.Action modules.
  
  Provides functions to emit telemetry events for action lifecycle:
  - action.start - Emitted when an action begins execution
  - action.stop - Emitted when an action completes successfully
  - action.exception - Emitted when an action fails with an exception
  """

  require Logger

  @doc """
  Wraps an action execution with telemetry events.
  
  Emits start event before execution, stop event on success,
  and exception event on failure. Automatically measures duration.
  
  ## Examples
  
      ActionTelemetry.span(
        [:rubber_duck, :action],
        %{action_type: "update_entity", resource: "user"},
        fn ->
          # Your action logic here
          {:ok, result}
        end
      )
  """
  def span(event_prefix, metadata, fun) when is_function(fun, 0) do
    start_time = System.monotonic_time()
    start_metadata = Map.merge(metadata, %{system_time: System.system_time()})
    
    # Emit start event
    :telemetry.execute(
      event_prefix ++ [:start],
      %{monotonic_time: start_time},
      start_metadata
    )
    
    try do
      result = fun.()
      
      # Emit stop event on success
      stop_time = System.monotonic_time()
      duration = stop_time - start_time
      
      stop_metadata = Map.merge(metadata, %{
        duration: duration,
        status: determine_status(result)
      })
      
      :telemetry.execute(
        event_prefix ++ [:stop],
        %{duration: duration, monotonic_time: stop_time},
        stop_metadata
      )
      
      result
    rescue
      exception ->
        # Emit exception event on failure
        stop_time = System.monotonic_time()
        duration = stop_time - start_time
        
        exception_metadata = Map.merge(metadata, %{
          duration: duration,
          error: inspect(exception),
          kind: :error
        })
        
        :telemetry.execute(
          event_prefix ++ [:exception],
          %{duration: duration, monotonic_time: stop_time},
          exception_metadata
        )
        
        reraise exception, __STACKTRACE__
    end
  end

  @doc """
  Emits a simple telemetry event for an action.
  
  Use this for fire-and-forget telemetry events that don't need
  duration tracking.
  
  ## Examples
  
      ActionTelemetry.event(
        [:rubber_duck, :action, :validation],
        %{fields_validated: 5},
        %{action_type: "update_entity", resource: "user"}
      )
  """
  def event(event_name, measurements, metadata \\ %{}) do
    :telemetry.execute(event_name, measurements, metadata)
  end

  @doc """
  Attaches telemetry handlers for action events.
  
  This should be called during application startup to set up
  handlers that will process action telemetry events.
  """
  def attach_handlers do
    events = [
      [:rubber_duck, :action, :start],
      [:rubber_duck, :action, :stop],
      [:rubber_duck, :action, :exception]
    ]
    
    :telemetry.attach_many(
      "rubber-duck-action-telemetry",
      events,
      &handle_event/4,
      nil
    )
  end

  @doc false
  def handle_event([:rubber_duck, :action, :start], _measurements, metadata, _config) do
    Logger.debug(
      "Action started: #{metadata[:action_type]} on #{metadata[:resource]}",
      metadata: metadata
    )
    
    # Emit counter for action start
    :telemetry.execute(
      [:rubber_duck, :action, :count],
      %{value: 1},
      Map.merge(metadata, %{status: :started})
    )
  end

  def handle_event([:rubber_duck, :action, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    
    Logger.debug(
      "Action completed: #{metadata[:action_type]} on #{metadata[:resource]} in #{duration_ms}ms",
      metadata: metadata
    )
    
    # Emit metrics for successful completion
    :telemetry.execute(
      [:rubber_duck, :action, :count],
      %{value: 1},
      Map.merge(metadata, %{status: metadata[:status] || :success})
    )
    
    :telemetry.execute(
      [:rubber_duck, :action, :duration],
      %{value: duration_ms},
      metadata
    )
    
    :telemetry.execute(
      [:rubber_duck, :action, :execution_time],
      %{value: duration_ms},
      metadata
    )
  end

  def handle_event([:rubber_duck, :action, :exception], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    
    Logger.error(
      "Action failed: #{metadata[:action_type]} on #{metadata[:resource]} after #{duration_ms}ms - #{metadata[:error]}",
      metadata: metadata
    )
    
    # Emit metrics for failure
    :telemetry.execute(
      [:rubber_duck, :action, :count],
      %{value: 1},
      Map.merge(metadata, %{status: :failure})
    )
    
    :telemetry.execute(
      [:rubber_duck, :action, :duration],
      %{value: duration_ms},
      Map.merge(metadata, %{status: :failure})
    )
  end

  # Helper to determine status from result
  defp determine_status({:ok, _}), do: :success
  defp determine_status({:error, _}), do: :error
  defp determine_status(:ok), do: :success
  defp determine_status(:error), do: :error
  defp determine_status(_), do: :unknown
end