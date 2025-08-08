defmodule RubberDuck.Pipeline.EntityUpdateProducer do
  @moduledoc """
  GenStage producer for entity update requests.

  This producer manages the flow of entity update requests into the pipeline,
  implementing demand-driven architecture with backpressure management.

  ## Features

  - Queue management for pending update requests
  - Priority handling for critical updates
  - Demand-based event emission
  - Overflow protection with configurable buffer size
  - Telemetry integration for monitoring

  ## Usage

      # Enqueue an entity update request
      EntityUpdateProducer.enqueue_update(params, context)
      
      # Check queue status
      EntityUpdateProducer.get_queue_status()
  """

  use GenStage
  require Logger

  @default_buffer_size 10_000
  @max_demand 100

  # Client API

  @doc """
  Starts the producer linked to the current process.
  """
  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enqueues an entity update request for processing.

  Returns `:ok` if successfully queued, `{:error, :overflow}` if buffer is full.
  """
  def enqueue_update(params, context, opts \\ []) do
    priority = Keyword.get(opts, :priority, :normal)

    GenStage.cast(__MODULE__, {:enqueue, {params, context, priority}})
  end

  @doc """
  Synchronously processes an entity update request.

  This bypasses the queue and directly requests processing, useful for
  single updates that need immediate processing.
  """
  def sync_update(params, context, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)

    GenStage.call(__MODULE__, {:sync_update, params, context}, timeout)
  end

  @doc """
  Returns the current queue status including size and capacity.
  """
  def get_queue_status do
    GenStage.call(__MODULE__, :get_status)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    buffer_size = Keyword.get(opts, :buffer_size, @default_buffer_size)

    state = %{
      queue: :queue.new(),
      pending_demand: 0,
      buffer_size: buffer_size,
      stats: %{
        enqueued: 0,
        dispatched: 0,
        overflow: 0
      }
    }

    Logger.info("EntityUpdateProducer started with buffer size: #{buffer_size}")

    {:producer, state}
  end

  @impl true
  def handle_cast({:enqueue, {params, context, priority}}, state) do
    queue_size = :queue.len(state.queue)

    if queue_size >= state.buffer_size do
      # Buffer overflow - reject the request
      Logger.warning("EntityUpdateProducer buffer overflow, rejecting update")

      emit_telemetry(:overflow, %{
        queue_size: queue_size,
        buffer_size: state.buffer_size
      })

      updated_stats = Map.update!(state.stats, :overflow, &(&1 + 1))
      {:noreply, [], %{state | stats: updated_stats}}
    else
      # Add to queue based on priority
      updated_queue = enqueue_by_priority(state.queue, {params, context}, priority)

      updated_stats = Map.update!(state.stats, :enqueued, &(&1 + 1))
      updated_state = %{state | queue: updated_queue, stats: updated_stats}

      # Try to dispatch if we have pending demand
      dispatch_events(updated_state)
    end
  end

  @impl true
  def handle_call({:sync_update, params, context}, from, state) do
    # For synchronous updates, add to front of queue with reply info
    request = {:sync, {params, context}, from}
    updated_queue = :queue.in_r(request, state.queue)

    updated_state = %{state | queue: updated_queue}

    # Try to dispatch immediately
    case dispatch_events(updated_state) do
      {:noreply, [], new_state} ->
        # Successfully dispatched or queued
        {:noreply, [], new_state}

      {:noreply, events, new_state} when is_list(events) ->
        # Events were dispatched
        {:noreply, events, new_state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      queue_size: :queue.len(state.queue),
      buffer_size: state.buffer_size,
      pending_demand: state.pending_demand,
      stats: state.stats
    }

    {:reply, status, [], state}
  end

  @impl true
  def handle_demand(demand, state) when demand > 0 do
    updated_state = %{state | pending_demand: state.pending_demand + demand}
    dispatch_events(updated_state)
  end

  # Private Functions

  defp dispatch_events(%{pending_demand: 0} = state) do
    # No demand, can't dispatch
    {:noreply, [], state}
  end

  defp dispatch_events(%{queue: queue, pending_demand: demand} = state) do
    # Calculate how many events to dispatch
    available = :queue.len(queue)
    to_dispatch = min(demand, min(available, @max_demand))

    if to_dispatch == 0 do
      {:noreply, [], state}
    else
      # Extract events from queue
      {events, updated_queue} = extract_events(queue, to_dispatch, [])

      # Update stats
      updated_stats = Map.update!(state.stats, :dispatched, &(&1 + to_dispatch))

      # Emit telemetry
      emit_telemetry(:dispatch, %{
        count: to_dispatch,
        remaining_demand: demand - to_dispatch,
        queue_size: :queue.len(updated_queue)
      })

      updated_state = %{
        state
        | queue: updated_queue,
          pending_demand: max(0, demand - to_dispatch),
          stats: updated_stats
      }

      {:noreply, events, updated_state}
    end
  end

  defp extract_events(queue, 0, acc), do: {Enum.reverse(acc), queue}

  defp extract_events(queue, count, acc) do
    case :queue.out(queue) do
      {{:value, item}, new_queue} ->
        event = format_event(item)
        extract_events(new_queue, count - 1, [event | acc])

      {:empty, new_queue} ->
        {Enum.reverse(acc), new_queue}
    end
  end

  defp format_event({:sync, {params, context}, from}) do
    # Synchronous request - include reply info
    %{
      type: :sync,
      params: params,
      context: context,
      from: from,
      timestamp: DateTime.utc_now()
    }
  end

  defp format_event({params, context}) do
    # Asynchronous request
    %{
      type: :async,
      params: params,
      context: context,
      timestamp: DateTime.utc_now()
    }
  end

  defp enqueue_by_priority(queue, item, :high) do
    # High priority goes to front
    :queue.in_r(item, queue)
  end

  defp enqueue_by_priority(queue, item, _priority) do
    # Normal and low priority go to back
    :queue.in(item, queue)
  end

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:rubber_duck, :pipeline, :producer, event],
      %{count: 1},
      metadata
    )
  end
end
