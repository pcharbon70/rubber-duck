defmodule RubberDuck.Telemetry.VMMetrics do
  @moduledoc """
  VM and Application Metrics Collector.

  Collects and reports VM statistics including:
  - Memory usage (processes, ETS, atoms)
  - Process counts and message queue lengths
  - Garbage collection statistics
  - Scheduler utilization
  """

  use GenServer
  require Logger

  # 10 seconds
  @collect_interval 10_000
  @telemetry_prefix [:rubber_duck, :vm]

  defstruct [
    :timer_ref,
    :last_collection,
    :collection_count
  ]

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_current_metrics do
    GenServer.call(__MODULE__, :get_current_metrics)
  end

  def force_collection do
    GenServer.cast(__MODULE__, :force_collection)
  end

  ## Server Implementation

  @impl true
  def init(_opts) do
    Logger.info("Starting VM Metrics Collector with #{@collect_interval}ms interval")

    # Start immediate collection
    send(self(), :collect_metrics)

    state = %__MODULE__{
      timer_ref: nil,
      last_collection: nil,
      collection_count: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_current_metrics, _from, state) do
    metrics = collect_vm_metrics()
    {:reply, metrics, state}
  end

  @impl true
  def handle_cast(:force_collection, state) do
    new_state = perform_collection(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:collect_metrics, state) do
    new_state = perform_collection(state)

    # Schedule next collection
    timer_ref = Process.send_after(self(), :collect_metrics, @collect_interval)
    final_state = %{new_state | timer_ref: timer_ref}

    {:noreply, final_state}
  end

  ## Internal Functions

  defp perform_collection(state) do
    case safe_vm_metrics_collection(state) do
      {:ok, new_state} ->
        new_state

      {:error, error} ->
        Logger.error("Failed to collect VM metrics: #{inspect(error)}")
        state
    end
  end

  defp safe_vm_metrics_collection(state) do
    metrics = collect_vm_metrics()

    # Emit telemetry events
    emit_vm_telemetry(metrics)

    result = %{
      state
      | last_collection: DateTime.utc_now(),
        collection_count: state.collection_count + 1
    }

    {:ok, result}
  rescue
    error -> {:error, error}
  end

  defp collect_vm_metrics do
    %{
      # Memory metrics
      memory: collect_memory_metrics(),

      # Process metrics
      processes: collect_process_metrics(),

      # Atom metrics
      atoms: collect_atom_metrics(),

      # ETS metrics
      ets: collect_ets_metrics(),

      # Scheduler metrics
      schedulers: collect_scheduler_metrics(),

      # System metrics
      system: collect_system_metrics(),

      # Garbage collection metrics
      garbage_collection: collect_gc_metrics()
    }
  end

  defp collect_memory_metrics do
    memory_info = :erlang.memory()

    %{
      total: Keyword.get(memory_info, :total, 0),
      processes: Keyword.get(memory_info, :processes, 0),
      processes_used: Keyword.get(memory_info, :processes_used, 0),
      system: Keyword.get(memory_info, :system, 0),
      atom: Keyword.get(memory_info, :atom, 0),
      atom_used: Keyword.get(memory_info, :atom_used, 0),
      binary: Keyword.get(memory_info, :binary, 0),
      code: Keyword.get(memory_info, :code, 0),
      ets: Keyword.get(memory_info, :ets, 0)
    }
  end

  defp collect_process_metrics do
    %{
      count: :erlang.system_info(:process_count),
      limit: :erlang.system_info(:process_limit),
      utilization: :erlang.system_info(:process_count) / :erlang.system_info(:process_limit),
      message_queue_len: get_total_message_queue_len(),
      heap_size: get_total_heap_size(),
      reductions: get_total_reductions()
    }
  end

  defp collect_atom_metrics do
    %{
      count: :erlang.system_info(:atom_count),
      limit: :erlang.system_info(:atom_limit),
      utilization: :erlang.system_info(:atom_count) / :erlang.system_info(:atom_limit)
    }
  end

  defp collect_ets_metrics do
    ets_tables = :ets.all()
    ets_count = length(ets_tables)

    total_memory =
      Enum.reduce(ets_tables, 0, fn table, acc ->
        try do
          info = :ets.info(table, :memory)
          if is_integer(info), do: acc + info, else: acc
        rescue
          _ -> acc
        end
      end)

    %{
      table_count: ets_count,
      total_memory: total_memory * :erlang.system_info(:wordsize)
    }
  end

  defp collect_scheduler_metrics do
    scheduler_usage = :scheduler.utilization(1)

    %{
      utilization: parse_scheduler_usage(scheduler_usage),
      online: :erlang.system_info(:schedulers_online),
      total: :erlang.system_info(:schedulers)
    }
  end

  defp collect_system_metrics do
    %{
      uptime: :erlang.statistics(:wall_clock) |> elem(0),
      run_queue: :erlang.statistics(:run_queue),
      io_input: :erlang.statistics(:io) |> elem(0),
      io_output: :erlang.statistics(:io) |> elem(1),
      logical_processors: :erlang.system_info(:logical_processors),
      logical_processors_online: :erlang.system_info(:logical_processors_online)
    }
  end

  defp collect_gc_metrics do
    {num_gcs, words_reclaimed, _} = :erlang.statistics(:garbage_collection)

    %{
      number_of_gcs: num_gcs,
      words_reclaimed: words_reclaimed,
      bytes_reclaimed: words_reclaimed * :erlang.system_info(:wordsize)
    }
  end

  defp get_total_message_queue_len do
    processes = Process.list()

    Enum.reduce(processes, 0, fn pid, acc ->
      case Process.info(pid, :message_queue_len) do
        {:message_queue_len, len} -> acc + len
        nil -> acc
      end
    end)
  end

  defp get_total_heap_size do
    processes = Process.list()

    Enum.reduce(processes, 0, fn pid, acc ->
      case Process.info(pid, :heap_size) do
        {:heap_size, size} -> acc + size
        nil -> acc
      end
    end)
  end

  defp get_total_reductions do
    processes = Process.list()

    Enum.reduce(processes, 0, fn pid, acc ->
      case Process.info(pid, :reductions) do
        {:reductions, reds} -> acc + reds
        nil -> acc
      end
    end)
  end

  defp parse_scheduler_usage(usage) when is_list(usage) do
    # Calculate average utilization across all schedulers
    {total_active, total_time} =
      Enum.reduce(usage, {0, 0}, fn
        {_scheduler_id, active, total}, {acc_active, acc_total} ->
          {acc_active + active, acc_total + total}

        _, acc ->
          acc
      end)

    if total_time > 0 do
      total_active / total_time
    else
      0.0
    end
  end

  defp parse_scheduler_usage(_), do: 0.0

  defp emit_vm_telemetry(metrics) do
    # Emit individual metric events
    :telemetry.execute(@telemetry_prefix ++ [:memory], metrics.memory, %{})
    :telemetry.execute(@telemetry_prefix ++ [:processes], metrics.processes, %{})
    :telemetry.execute(@telemetry_prefix ++ [:atoms], metrics.atoms, %{})
    :telemetry.execute(@telemetry_prefix ++ [:ets], metrics.ets, %{})
    :telemetry.execute(@telemetry_prefix ++ [:schedulers], metrics.schedulers, %{})
    :telemetry.execute(@telemetry_prefix ++ [:system], metrics.system, %{})

    :telemetry.execute(
      @telemetry_prefix ++ [:garbage_collection],
      metrics.garbage_collection,
      %{}
    )

    # Emit comprehensive metrics event
    :telemetry.execute(
      @telemetry_prefix ++ [:all],
      %{collection_time: DateTime.utc_now()},
      metrics
    )
  end
end
