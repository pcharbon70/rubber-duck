defmodule RubberDuck.HealthCheck.ResourceMonitor do
  @moduledoc """
  System resource usage health monitor.

  Monitors:
  - Memory usage (processes, system, total)
  - Process count vs limits
  - Atom table usage
  - ETS table count and memory
  - Message queue lengths
  """

  use GenServer
  require Logger

  # 15 seconds
  @check_interval 15_000

  # Thresholds for health status
  # 80% memory usage
  @memory_warning_threshold 0.8
  # 95% memory usage
  @memory_critical_threshold 0.95
  # 70% of process limit
  @process_warning_threshold 0.7
  # 90% of process limit
  @process_critical_threshold 0.9
  # 80% of atom limit
  @atom_warning_threshold 0.8
  # 95% of atom limit
  @atom_critical_threshold 0.95

  defstruct [
    :timer_ref,
    :last_check,
    :health_status,
    :resource_metrics,
    :alert_history
  ]

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_health_status do
    GenServer.call(__MODULE__, :get_health_status)
  end

  def get_resource_metrics do
    GenServer.call(__MODULE__, :get_resource_metrics)
  end

  def force_check do
    GenServer.cast(__MODULE__, :force_check)
  end

  ## Server Implementation

  @impl true
  def init(_opts) do
    Logger.info("Starting Resource Health Monitor")

    # Perform initial check
    send(self(), :perform_resource_check)

    state = %__MODULE__{
      timer_ref: nil,
      last_check: nil,
      health_status: :unknown,
      resource_metrics: %{},
      alert_history: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_health_status, _from, state) do
    health_report = %{
      status: state.health_status,
      last_check: state.last_check,
      resource_metrics: state.resource_metrics,
      recent_alerts: Enum.take(state.alert_history, 10)
    }

    {:reply, health_report, state}
  end

  @impl true
  def handle_call(:get_resource_metrics, _from, state) do
    {:reply, state.resource_metrics, state}
  end

  @impl true
  def handle_cast(:force_check, state) do
    new_state = perform_resource_check(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:perform_resource_check, state) do
    new_state = perform_resource_check(state)

    # Schedule next check
    timer_ref = Process.send_after(self(), :perform_resource_check, @check_interval)
    final_state = %{new_state | timer_ref: timer_ref}

    {:noreply, final_state}
  end

  ## Internal Functions

  defp perform_resource_check(state) do
    case safe_resource_check(state) do
      {:ok, result} ->
        result

      {:error, error} ->
        Logger.error("Resource health check failed: #{inspect(error)}")
        %{state | health_status: :critical, last_check: DateTime.utc_now()}
    end
  end

  defp safe_resource_check(state) do
    # Collect resource metrics
    metrics = collect_resource_metrics()

    # Determine overall health status
    health_status = determine_resource_health(metrics)

    # Check for new alerts
    new_alerts = check_for_alerts(metrics, state.resource_metrics)

    # Update alert history
    updated_alert_history =
      (new_alerts ++ state.alert_history)
      # Keep last 50 alerts
      |> Enum.take(50)

    # Emit telemetry
    emit_resource_telemetry(health_status, metrics)

    # Log alerts if any
    Enum.each(new_alerts, fn alert ->
      Logger.warning("Resource Alert: #{alert.type} - #{alert.message}")
    end)

    result = %{
      state
      | health_status: health_status,
        last_check: DateTime.utc_now(),
        resource_metrics: metrics,
        alert_history: updated_alert_history
    }

    {:ok, result}
  rescue
    error -> {:error, error}
  end

  defp collect_resource_metrics do
    memory_info = :erlang.memory()

    %{
      memory: %{
        total: Keyword.get(memory_info, :total, 0),
        processes: Keyword.get(memory_info, :processes, 0),
        system: Keyword.get(memory_info, :system, 0),
        atom: Keyword.get(memory_info, :atom, 0),
        binary: Keyword.get(memory_info, :binary, 0),
        code: Keyword.get(memory_info, :code, 0),
        ets: Keyword.get(memory_info, :ets, 0),
        # Calculate utilization based on system memory if available
        utilization: calculate_memory_utilization(memory_info)
      },
      processes: %{
        count: :erlang.system_info(:process_count),
        limit: :erlang.system_info(:process_limit),
        utilization: :erlang.system_info(:process_count) / :erlang.system_info(:process_limit),
        message_queue_total: get_total_message_queue_length(),
        max_message_queue: get_max_message_queue_length()
      },
      atoms: %{
        count: :erlang.system_info(:atom_count),
        limit: :erlang.system_info(:atom_limit),
        utilization: :erlang.system_info(:atom_count) / :erlang.system_info(:atom_limit)
      },
      ets: %{
        table_count: length(:ets.all()),
        memory_words: get_ets_memory_usage(),
        memory_bytes: get_ets_memory_usage() * :erlang.system_info(:wordsize)
      },
      schedulers: %{
        online: :erlang.system_info(:schedulers_online),
        total: :erlang.system_info(:schedulers),
        utilization: get_scheduler_utilization()
      },
      system: %{
        uptime_ms: :erlang.statistics(:wall_clock) |> elem(0),
        run_queue: :erlang.statistics(:run_queue),
        logical_processors: :erlang.system_info(:logical_processors_online) || 1
      }
    }
  end

  defp calculate_memory_utilization(memory_info) do
    total = Keyword.get(memory_info, :total, 0)

    # If we have access to system memory info, use it
    # Otherwise, use a heuristic based on process limit
    case get_system_memory_total() do
      {:ok, system_total} when system_total > 0 ->
        total / system_total

      _ ->
        # Fallback: estimate based on process count vs limit
        _process_count = :erlang.system_info(:process_count)
        process_limit = :erlang.system_info(:process_limit)

        # Rough heuristic: assume each process uses some base memory
        # 32KB per process estimate
        estimated_max = process_limit * 32_768
        min(total / estimated_max, 1.0)
    end
  end

  defp get_system_memory_total do
    case safe_read_meminfo() do
      {:ok, meminfo} ->
        parse_meminfo_total(meminfo)

      {:error, _} ->
        {:error, :not_available}
    end
  end

  defp safe_read_meminfo do
    File.read("/proc/meminfo")
  rescue
    _ -> {:error, :not_available}
  end

  defp parse_meminfo_total(meminfo) do
    case Regex.run(~r/MemTotal:\s*(\d+)\s*kB/, meminfo) do
      [_, total_kb] ->
        # Convert to bytes
        {:ok, String.to_integer(total_kb) * 1024}

      _ ->
        {:error, :not_available}
    end
  end

  defp get_total_message_queue_length do
    Process.list()
    |> Enum.reduce(0, fn pid, acc ->
      case Process.info(pid, :message_queue_len) do
        {:message_queue_len, len} -> acc + len
        nil -> acc
      end
    end)
  end

  defp get_max_message_queue_length do
    Process.list()
    |> Enum.reduce(0, fn pid, acc ->
      case Process.info(pid, :message_queue_len) do
        {:message_queue_len, len} -> max(acc, len)
        nil -> acc
      end
    end)
  end

  defp get_ets_memory_usage do
    :ets.all()
    |> Enum.reduce(0, fn table, acc ->
      case :ets.info(table, :memory) do
        memory when is_integer(memory) -> acc + memory
        _ -> acc
      end
    end)
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
        # Calculate average utilization
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

  defp determine_resource_health(metrics) do
    # Check each resource category and determine worst case
    memory_status = determine_memory_health(metrics.memory)
    process_status = determine_process_health(metrics.processes)
    atom_status = determine_atom_health(metrics.atoms)

    # Return the worst status among all resources
    [memory_status, process_status, atom_status]
    |> Enum.max_by(&status_priority/1)
  end

  defp determine_memory_health(memory_metrics) do
    cond do
      memory_metrics.utilization >= @memory_critical_threshold -> :critical
      memory_metrics.utilization >= @memory_warning_threshold -> :warning
      true -> :healthy
    end
  end

  defp determine_process_health(process_metrics) do
    cond do
      process_metrics.utilization >= @process_critical_threshold -> :critical
      process_metrics.utilization >= @process_warning_threshold -> :warning
      # Large message queue
      process_metrics.max_message_queue > 10_000 -> :warning
      true -> :healthy
    end
  end

  defp determine_atom_health(atom_metrics) do
    cond do
      atom_metrics.utilization >= @atom_critical_threshold -> :critical
      atom_metrics.utilization >= @atom_warning_threshold -> :warning
      true -> :healthy
    end
  end

  defp status_priority(:critical), do: 4
  defp status_priority(:warning), do: 3
  defp status_priority(:degraded), do: 2
  defp status_priority(:healthy), do: 1

  defp check_for_alerts(_current_metrics, previous_metrics)
       when map_size(previous_metrics) == 0 do
    # No previous metrics, no alerts
    []
  end

  defp check_for_alerts(current_metrics, previous_metrics) do
    alerts = []

    # Check memory alerts
    alerts = check_memory_alerts(current_metrics.memory, previous_metrics[:memory], alerts)

    # Check process alerts
    alerts = check_process_alerts(current_metrics.processes, previous_metrics[:processes], alerts)

    # Check atom alerts
    alerts = check_atom_alerts(current_metrics.atoms, previous_metrics[:atoms], alerts)

    alerts
  end

  defp check_memory_alerts(_current, previous, alerts) when is_nil(previous), do: alerts

  defp check_memory_alerts(current, previous, alerts) do
    cond do
      current.utilization >= @memory_critical_threshold and
          previous.utilization < @memory_critical_threshold ->
        [
          create_alert(
            :memory,
            :critical,
            "Memory usage critical: #{trunc(current.utilization * 100)}%"
          )
          | alerts
        ]

      current.utilization >= @memory_warning_threshold and
          previous.utilization < @memory_warning_threshold ->
        [
          create_alert(
            :memory,
            :warning,
            "Memory usage high: #{trunc(current.utilization * 100)}%"
          )
          | alerts
        ]

      true ->
        alerts
    end
  end

  defp check_process_alerts(_current, previous, alerts) when is_nil(previous), do: alerts

  defp check_process_alerts(current, previous, alerts) do
    cond do
      current.utilization >= @process_critical_threshold and
          previous.utilization < @process_critical_threshold ->
        [
          create_alert(
            :processes,
            :critical,
            "Process limit critical: #{current.count}/#{current.limit}"
          )
          | alerts
        ]

      current.utilization >= @process_warning_threshold and
          previous.utilization < @process_warning_threshold ->
        [
          create_alert(
            :processes,
            :warning,
            "Process count high: #{current.count}/#{current.limit}"
          )
          | alerts
        ]

      true ->
        alerts
    end
  end

  defp check_atom_alerts(_current, previous, alerts) when is_nil(previous), do: alerts

  defp check_atom_alerts(current, previous, alerts) do
    cond do
      current.utilization >= @atom_critical_threshold and
          previous.utilization < @atom_critical_threshold ->
        [
          create_alert(
            :atoms,
            :critical,
            "Atom table critical: #{current.count}/#{current.limit}"
          )
          | alerts
        ]

      current.utilization >= @atom_warning_threshold and
          previous.utilization < @atom_warning_threshold ->
        [
          create_alert(:atoms, :warning, "Atom usage high: #{current.count}/#{current.limit}")
          | alerts
        ]

      true ->
        alerts
    end
  end

  defp create_alert(type, severity, message) do
    %{
      type: type,
      severity: severity,
      message: message,
      timestamp: DateTime.utc_now()
    }
  end

  defp emit_resource_telemetry(status, metrics) do
    # Emit individual resource telemetries
    :telemetry.execute(
      [:rubber_duck, :health_check, :resources, :memory],
      metrics.memory,
      %{status: determine_memory_health(metrics.memory)}
    )

    :telemetry.execute(
      [:rubber_duck, :health_check, :resources, :processes],
      metrics.processes,
      %{status: determine_process_health(metrics.processes)}
    )

    :telemetry.execute(
      [:rubber_duck, :health_check, :resources, :atoms],
      metrics.atoms,
      %{status: determine_atom_health(metrics.atoms)}
    )

    # Emit overall resource status
    :telemetry.execute(
      [:rubber_duck, :health_check, :resources],
      %{status_numeric: status_to_numeric(status)},
      %{status: status, metrics: metrics}
    )
  end

  defp status_to_numeric(:healthy), do: 1
  defp status_to_numeric(:warning), do: 2
  defp status_to_numeric(:degraded), do: 3
  defp status_to_numeric(:critical), do: 4
  defp status_to_numeric(_), do: 0
end
