defmodule RubberDuck.HealthCheck.StatusAggregator do
  @moduledoc """
  Aggregates health status from all monitors and provides unified health reporting.

  Collects status from:
  - Database Monitor
  - Resource Monitor  
  - Service Monitor
  - Agent Monitor
  """

  use GenServer
  require Logger

  # 5 seconds
  @update_interval 5_000

  defstruct [
    :timer_ref,
    :last_update,
    :overall_status,
    :component_statuses,
    :status_history
  ]

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_overall_status do
    GenServer.call(__MODULE__, :get_overall_status)
  end

  def get_detailed_status do
    GenServer.call(__MODULE__, :get_detailed_status)
  end

  def get_status_history(limit \\ 10) do
    GenServer.call(__MODULE__, {:get_status_history, limit})
  end

  ## Server Implementation

  @impl true
  def init(_opts) do
    Logger.info("Starting Health Status Aggregator")

    # Perform initial aggregation
    send(self(), :aggregate_status)

    state = %__MODULE__{
      timer_ref: nil,
      last_update: nil,
      overall_status: :unknown,
      component_statuses: %{},
      status_history: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_overall_status, _from, state) do
    {:reply, state.overall_status, state}
  end

  @impl true
  def handle_call(:get_detailed_status, _from, state) do
    detailed_status = %{
      overall_status: state.overall_status,
      last_update: state.last_update,
      components: state.component_statuses,
      summary: generate_status_summary(state.component_statuses)
    }

    {:reply, detailed_status, state}
  end

  @impl true
  def handle_call({:get_status_history, limit}, _from, state) do
    history = Enum.take(state.status_history, limit)
    {:reply, history, state}
  end

  @impl true
  def handle_info(:aggregate_status, state) do
    new_state = perform_status_aggregation(state)

    # Schedule next aggregation
    timer_ref = Process.send_after(self(), :aggregate_status, @update_interval)
    final_state = %{new_state | timer_ref: timer_ref}

    {:noreply, final_state}
  end

  ## Internal Functions

  defp perform_status_aggregation(state) do
    case safe_status_aggregation(state) do
      {:ok, result} ->
        result

      {:error, error} ->
        Logger.error("Failed to aggregate health status: #{inspect(error)}")
        %{state | overall_status: :critical, last_update: DateTime.utc_now()}
    end
  end

  defp safe_status_aggregation(state) do
    # Collect status from all monitors
    component_statuses = collect_component_statuses()

    # Determine overall status
    overall_status = determine_overall_status(component_statuses)

    # Check if status changed
    status_changed = overall_status != state.overall_status

    # Update history if status changed
    updated_history =
      if status_changed do
        history_entry = %{
          status: overall_status,
          timestamp: DateTime.utc_now(),
          components: component_statuses
        }

        [history_entry | state.status_history]
        # Keep last 100 status changes
        |> Enum.take(100)
      else
        state.status_history
      end

    # Emit telemetry
    emit_aggregated_telemetry(overall_status, component_statuses)

    # Log status changes
    if status_changed do
      Logger.info("Overall health status changed: #{state.overall_status} -> #{overall_status}")
    end

    result = %{
      state
      | last_update: DateTime.utc_now(),
        overall_status: overall_status,
        component_statuses: component_statuses,
        status_history: updated_history
    }

    {:ok, result}
  rescue
    error -> {:error, error}
  end

  defp collect_component_statuses do
    %{
      database: get_component_status(RubberDuck.HealthCheck.DatabaseMonitor),
      resources: get_component_status(RubberDuck.HealthCheck.ResourceMonitor),
      services: get_component_status(RubberDuck.HealthCheck.ServiceMonitor),
      agents: get_component_status(RubberDuck.HealthCheck.AgentMonitor)
    }
  end

  defp get_component_status(monitor_module) do
    case safe_component_status_check(monitor_module) do
      {:ok, result} ->
        result

      {:error, error} ->
        %{status: :error, error: inspect(error), monitor: monitor_module}

      {:exit, reason} ->
        %{status: :error, error: "Monitor exit: #{inspect(reason)}", monitor: monitor_module}
    end
  end

  defp safe_component_status_check(monitor_module) do
    case GenServer.whereis(monitor_module) do
      nil ->
        {:ok, %{status: :unavailable, error: "Monitor not running"}}

      _pid ->
        case GenServer.call(monitor_module, :get_health_status, 2000) do
          health_status when is_map(health_status) ->
            {:ok, Map.put(health_status, :monitor, monitor_module)}

          status when is_atom(status) ->
            {:ok, %{status: status, monitor: monitor_module}}

          _ ->
            {:ok, %{status: :unknown, monitor: monitor_module}}
        end
    end
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:exit, reason}
  end

  defp determine_overall_status(component_statuses) do
    statuses =
      component_statuses
      |> Map.values()
      |> Enum.map(fn component -> Map.get(component, :status, :unknown) end)

    cond do
      :critical in statuses -> :critical
      :error in statuses -> :critical
      :degraded in statuses -> :degraded
      :warning in statuses -> :warning
      :unavailable in statuses -> :degraded
      Enum.all?(statuses, &(&1 == :healthy)) -> :healthy
      true -> :unknown
    end
  end

  defp generate_status_summary(component_statuses) do
    healthy_count = count_components_with_status(component_statuses, :healthy)
    warning_count = count_components_with_status(component_statuses, :warning)
    degraded_count = count_components_with_status(component_statuses, :degraded)
    critical_count = count_components_with_status(component_statuses, [:critical, :error])
    unavailable_count = count_components_with_status(component_statuses, :unavailable)

    total_count = map_size(component_statuses)

    %{
      total_components: total_count,
      healthy: healthy_count,
      warning: warning_count,
      degraded: degraded_count,
      critical: critical_count,
      unavailable: unavailable_count,
      health_percentage: if(total_count > 0, do: healthy_count / total_count * 100, else: 0)
    }
  end

  defp count_components_with_status(component_statuses, target_status)
       when is_list(target_status) do
    component_statuses
    |> Map.values()
    |> Enum.count(fn component -> Map.get(component, :status) in target_status end)
  end

  defp count_components_with_status(component_statuses, target_status) do
    count_components_with_status(component_statuses, [target_status])
  end

  defp emit_aggregated_telemetry(overall_status, component_statuses) do
    summary = generate_status_summary(component_statuses)

    :telemetry.execute(
      [:rubber_duck, :health_check, :overall],
      %{
        status_numeric: status_to_numeric(overall_status),
        health_percentage: summary.health_percentage,
        total_components: summary.total_components
      },
      %{
        status: overall_status,
        components: component_statuses,
        summary: summary
      }
    )
  end

  defp status_to_numeric(:healthy), do: 1
  defp status_to_numeric(:warning), do: 2
  defp status_to_numeric(:degraded), do: 3
  defp status_to_numeric(:critical), do: 4
  defp status_to_numeric(:error), do: 4
  defp status_to_numeric(:unavailable), do: 3
  defp status_to_numeric(_), do: 0
end
