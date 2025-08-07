defmodule RubberDuck.Routing.PriorityConsumerPool do
  @moduledoc """
  GenStage consumer pool that processes batched messages with priority-based concurrency.

  Features:
  - Priority-based message routing
  - Configurable concurrency levels per priority
  - Automatic demand management
  - Failure recovery and retry mechanisms
  - Comprehensive telemetry
  """

  use GenStage
  require Logger
  alias RubberDuck.Telemetry.BatchingTelemetry
  alias RubberDuck.Routing.EnhancedMessageRouter
  alias RubberDuck.Protocol.Message

  @priority_configs %{
    critical: %{max_concurrency: 1, demand: 5},
    high: %{max_concurrency: 4, demand: 20},
    normal: %{max_concurrency: 8, demand: 50},
    low: %{max_concurrency: 2, demand: 100}
  }

  defstruct [
    :config,
    :subscription,
    :task_supervisor,
    :stats,
    :active_tasks
  ]

  @doc """
  Starts the priority consumer pool.
  """
  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets current statistics for the consumer pool.
  """
  def get_stats do
    GenStage.call(__MODULE__, :get_stats)
  end

  # GenStage Callbacks

  @impl true
  def init(opts) do
    config = Map.merge(@priority_configs, Map.new(opts))

    # Start a task supervisor for concurrent processing
    {:ok, task_supervisor} = Task.Supervisor.start_link()

    state = %__MODULE__{
      config: config,
      task_supervisor: task_supervisor,
      stats: init_stats(),
      active_tasks: %{}
    }

    # Subscribe to the MessageProducer
    subscription_opts = [
      to: RubberDuck.Routing.MessageProducer,
      max_demand: calculate_max_demand(config),
      min_demand: 0
    ]

    {:consumer, state, subscribe_to: [{RubberDuck.Routing.MessageProducer, subscription_opts}]}
  end

  @impl true
  def handle_events(events, _from, state) do
    # Process each batch event
    new_state = Enum.reduce(events, state, &process_batch_event/2)

    {:noreply, [], new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, [], state}
  end

  @impl true
  def handle_info({:task_completed, task_ref, result}, state) do
    # Handle task completion
    {priority, start_time} = Map.get(state.active_tasks, task_ref, {nil, nil})

    if priority do
      processing_time = System.monotonic_time(:microsecond) - start_time

      new_stats = update_stats_for_completion(state.stats, priority, processing_time, result)
      new_active_tasks = Map.delete(state.active_tasks, task_ref)

      new_state = %{state | stats: new_stats, active_tasks: new_active_tasks}

      {:noreply, [], new_state}
    else
      {:noreply, [], state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Handle task failure
    {priority, _start_time} = Map.get(state.active_tasks, ref, {nil, nil})

    if priority do
      Logger.error("Task failed for priority #{priority}: #{inspect(reason)}")

      new_stats =
        Map.update!(state.stats, priority, fn pstats ->
          Map.update!(pstats, :failures, &(&1 + 1))
        end)

      new_active_tasks = Map.delete(state.active_tasks, ref)
      new_state = %{state | stats: new_stats, active_tasks: new_active_tasks}

      {:noreply, [], new_state}
    else
      {:noreply, [], state}
    end
  end

  # Private Functions

  defp init_stats do
    Map.new([:critical, :high, :normal, :low], fn priority ->
      {priority,
       %{
         batches_processed: 0,
         messages_processed: 0,
         failures: 0,
         total_processing_time_us: 0,
         avg_processing_time_us: 0
       }}
    end)
  end

  defp calculate_max_demand(config) do
    config
    |> Map.values()
    |> Enum.map(& &1.demand)
    |> Enum.sum()
  end

  defp process_batch_event(batch_event, state) do
    # Group messages by priority
    priority_groups = group_messages_by_priority(batch_event.messages)

    # Process each priority group with appropriate concurrency
    Enum.reduce(priority_groups, state, fn {priority, messages}, acc_state ->
      process_priority_group(priority, messages, batch_event.metadata, acc_state)
    end)
  end

  defp group_messages_by_priority(messages) do
    messages
    |> Enum.group_by(fn {message, _context} ->
      Message.priority(message)
    end)
    |> Enum.map(fn {priority, msgs} ->
      # Normalize priority to our configured levels
      normalized_priority = normalize_priority(priority)
      {normalized_priority, msgs}
    end)
    |> Map.new()
  end

  defp normalize_priority(:critical), do: :critical
  defp normalize_priority(:high), do: :high
  defp normalize_priority(:normal), do: :normal
  defp normalize_priority(:low), do: :low
  defp normalize_priority(_), do: :normal

  defp process_priority_group(priority, messages, metadata, state) do
    config = Map.get(state.config, priority, state.config.normal)
    max_concurrency = config.max_concurrency

    # Split messages into chunks based on max concurrency
    chunks = Enum.chunk_every(messages, max_concurrency)

    # Process each chunk
    Enum.reduce(chunks, state, fn chunk, acc_state ->
      process_message_chunk(priority, chunk, metadata, acc_state)
    end)
  end

  defp process_message_chunk(priority, messages, _metadata, state) do
    start_time = System.monotonic_time(:microsecond)

    # Start supervised tasks for each message
    tasks =
      Enum.map(messages, fn {message, context} ->
        Task.Supervisor.async_nolink(
          state.task_supervisor,
          fn -> process_single_message(message, context, priority) end
        )
      end)

    # Track active tasks
    new_active_tasks =
      Enum.reduce(tasks, state.active_tasks, fn task, acc ->
        Map.put(acc, task.ref, {priority, start_time})
      end)

    # Wait for all tasks to complete (with timeout)
    results = Task.yield_many(tasks, 5000)

    # Process results and update stats
    {successful, failed} = partition_results(results)

    processing_time = System.monotonic_time(:microsecond) - start_time

    # Emit telemetry for batch processed
    if successful > 0 do
      BatchingTelemetry.emit_batch_processed(successful, processing_time, priority)
    end

    if failed > 0 do
      BatchingTelemetry.emit_batch_failed(failed, :timeout, priority)
    end

    # Update stats
    new_stats =
      Map.update!(state.stats, priority, fn pstats ->
        pstats
        |> Map.update!(:batches_processed, &(&1 + 1))
        |> Map.update!(:messages_processed, &(&1 + successful))
        |> Map.update!(:failures, &(&1 + failed))
        |> Map.update!(:total_processing_time_us, &(&1 + processing_time))
        |> update_avg_processing_time()
      end)

    # Clean up completed tasks from active_tasks
    final_active_tasks =
      Enum.reduce(tasks, new_active_tasks, fn task, acc ->
        Map.delete(acc, task.ref)
      end)

    %{state | stats: new_stats, active_tasks: final_active_tasks}
  end

  defp process_single_message(message, context, priority) do
    try do
      # Add priority to context for handlers
      enhanced_context = Map.put(context, :priority, priority)

      # Route through the enhanced message router
      case EnhancedMessageRouter.dispatch(message, enhanced_context) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    rescue
      exception ->
        Logger.error("Message processing failed: #{inspect(exception)}")
        {:error, exception}
    end
  end

  defp partition_results(results) do
    Enum.reduce(results, {0, 0}, fn result, {success, failure} ->
      case result do
        {_task, {:ok, {:ok, _}}} -> {success + 1, failure}
        {_task, {:ok, {:error, _}}} -> {success, failure + 1}
        {_task, {:exit, _}} -> {success, failure + 1}
        # Timeout
        {_task, nil} -> {success, failure + 1}
      end
    end)
  end

  defp update_stats_for_completion(stats, priority, processing_time, result) do
    Map.update!(stats, priority, fn pstats ->
      case result do
        {:ok, _} ->
          pstats
          |> Map.update!(:messages_processed, &(&1 + 1))
          |> Map.update!(:total_processing_time_us, &(&1 + processing_time))
          |> update_avg_processing_time()

        {:error, _} ->
          Map.update!(pstats, :failures, &(&1 + 1))
      end
    end)
  end

  defp update_avg_processing_time(stats) do
    if stats.messages_processed > 0 do
      avg = div(stats.total_processing_time_us, stats.messages_processed)
      Map.put(stats, :avg_processing_time_us, avg)
    else
      stats
    end
  end
end
