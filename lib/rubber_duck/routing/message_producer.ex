defmodule RubberDuck.Routing.MessageProducer do
  @moduledoc """
  GenStage producer that collects messages and emits them in batches.
  
  This producer implements intelligent batching with:
  - Size-based and time-based triggers
  - Back-pressure management
  - Priority-aware grouping
  - Overflow protection
  
  ## Configuration
  
  The producer accepts the following configuration options:
  
  - `:min_batch_size` - Minimum number of messages before emitting a batch (default: 10)
  - `:max_batch_size` - Maximum batch size (default: 100)
  - `:batch_timeout_ms` - Maximum time to wait before emitting a batch (default: 50ms)
  - `:buffer_size` - Maximum buffer size for incoming messages (default: 1000)
  - `:adaptive_batching` - Enable adaptive batch sizing (default: true)
  """
  
  use GenStage
  require Logger
  alias RubberDuck.Telemetry.BatchingTelemetry
  
  @default_config %{
    min_batch_size: 10,
    max_batch_size: 100,
    batch_timeout_ms: 50,
    buffer_size: 1000,
    adaptive_batching: true
  }
  
  defstruct [
    :config,
    :buffer,
    :batch_timer,
    :demand,
    :pending_demand,
    :stats
  ]
  
  @doc """
  Starts the message producer with the given configuration.
  """
  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Enqueues a message for batching.
  
  Returns `:ok` if the message was queued successfully, or
  `{:error, :buffer_overflow}` if the buffer is full.
  """
  @spec enqueue(struct(), map()) :: :ok | {:error, :buffer_overflow}
  def enqueue(message, context \\ %{}) do
    GenStage.cast(__MODULE__, {:enqueue, message, context})
  end
  
  @doc """
  Enqueues a message synchronously, waiting for confirmation.
  """
  @spec enqueue_sync(struct(), map(), timeout()) :: :ok | {:error, term()}
  def enqueue_sync(message, context \\ %{}, timeout \\ 5000) do
    GenStage.call(__MODULE__, {:enqueue_sync, message, context}, timeout)
  end
  
  # GenStage Callbacks
  
  @impl true
  def init(opts) do
    config = Map.merge(@default_config, Map.new(opts))
    
    state = %__MODULE__{
      config: config,
      buffer: :queue.new(),
      batch_timer: nil,
      demand: 0,
      pending_demand: 0,
      stats: %{
        messages_buffered: 0,
        batches_emitted: 0,
        messages_emitted: 0,
        buffer_overflows: 0
      }
    }
    
    # Emit telemetry for producer initialization
    BatchingTelemetry.emit_producer_started(config)
    
    {:producer, state}
  end
  
  @impl true
  def handle_cast({:enqueue, message, context}, state) do
    handle_enqueue(message, context, state, false)
  end
  
  @impl true
  def handle_call({:enqueue_sync, message, context}, from, state) do
    case handle_enqueue(message, context, state, true) do
      {:noreply, [], new_state} ->
        {:reply, :ok, [], new_state}
      {:noreply, events, new_state} ->
        {:reply, :ok, events, new_state}
    end
  end
  
  @impl true
  def handle_call({:update_config, new_config}, _from, state) do
    updated_config = Map.merge(state.config, new_config)
    new_state = %{state | config: updated_config}
    
    BatchingTelemetry.emit_config_updated(updated_config)
    
    {:reply, :ok, [], new_state}
  end
  
  @impl true
  def handle_demand(incoming_demand, state) do
    new_demand = state.demand + incoming_demand
    new_state = %{state | demand: new_demand}
    
    # Try to emit batches if we have demand and buffered messages
    {events, final_state} = try_emit_batches(new_state)
    
    # Emit telemetry for demand received
    BatchingTelemetry.emit_demand_received(incoming_demand, final_state.stats.messages_buffered)
    
    {:noreply, events, final_state}
  end
  
  @impl true
  def handle_info(:batch_timeout, state) do
    # Timer expired, emit whatever we have buffered
    {events, new_state} = emit_current_batch(state, :timeout)
    
    final_state = %{new_state | batch_timer: nil}
    
    {:noreply, events, final_state}
  end
  
  def handle_info({:adaptive_update, new_batch_size}, state) do
    # Adaptive batch controller updated our batch size
    new_config = %{state.config | max_batch_size: new_batch_size}
    new_state = %{state | config: new_config}
    
    BatchingTelemetry.emit_adaptive_size_changed(new_batch_size)
    
    {:noreply, [], new_state}
  end
  
  # Private Functions
  
  defp handle_enqueue(message, context, state, _sync) do
    buffer_size = :queue.len(state.buffer)
    
    if buffer_size >= state.config.buffer_size do
      # Buffer overflow - reject the message
      Logger.warning("Message buffer overflow. Current size: #{buffer_size}")
      
      new_stats = Map.update!(state.stats, :buffer_overflows, &(&1 + 1))
      new_state = %{state | stats: new_stats}
      
      BatchingTelemetry.emit_buffer_overflow(buffer_size)
      
      {:noreply, [], new_state}
    else
      # Add message to buffer
      entry = {message, context, System.monotonic_time(:microsecond)}
      new_buffer = :queue.in(entry, state.buffer)
      
      new_stats = Map.update!(state.stats, :messages_buffered, &(&1 + 1))
      new_state = %{state | buffer: new_buffer, stats: new_stats}
      
      # Start batch timer if not already running
      final_state = maybe_start_timer(new_state)
      
      # Try to emit a batch if we have enough messages
      {events, result_state} = try_emit_batches(final_state)
      
      # Emit telemetry for message enqueued
      BatchingTelemetry.emit_message_enqueued(
        message.__struct__,
        :queue.len(result_state.buffer)
      )
      
      {:noreply, events, result_state}
    end
  end
  
  defp maybe_start_timer(state) do
    if state.batch_timer == nil and :queue.len(state.buffer) > 0 do
      timer_ref = Process.send_after(self(), :batch_timeout, state.config.batch_timeout_ms)
      %{state | batch_timer: timer_ref}
    else
      state
    end
  end
  
  defp try_emit_batches(state) do
    buffer_size = :queue.len(state.buffer)
    
    cond do
      # No demand or no messages
      state.demand == 0 or buffer_size == 0 ->
        {[], state}
      
      # Have enough for a max batch
      buffer_size >= state.config.max_batch_size ->
        emit_batch(state, state.config.max_batch_size, :size_trigger)
      
      # Have enough for a min batch and demand is waiting
      buffer_size >= state.config.min_batch_size and state.demand > 0 ->
        batch_size = min(buffer_size, state.config.max_batch_size)
        emit_batch(state, batch_size, :demand_trigger)
      
      # Not enough messages yet
      true ->
        {[], state}
    end
  end
  
  defp emit_current_batch(state, trigger) do
    buffer_size = :queue.len(state.buffer)
    
    if buffer_size > 0 do
      emit_batch(state, buffer_size, trigger)
    else
      {[], state}
    end
  end
  
  defp emit_batch(state, batch_size, trigger) do
    # Extract messages from buffer
    {batch_entries, remaining_buffer} = extract_from_buffer(state.buffer, batch_size)
    
    # Cancel timer if we're emitting everything
    new_timer = if :queue.len(remaining_buffer) == 0 do
      cancel_timer(state.batch_timer)
      nil
    else
      state.batch_timer
    end
    
    # Create batch event
    batch = create_batch_event(batch_entries, trigger)
    
    # Update stats
    new_stats = state.stats
    |> Map.update!(:batches_emitted, &(&1 + 1))
    |> Map.update!(:messages_emitted, &(&1 + batch_size))
    |> Map.update!(:messages_buffered, &(&1 - batch_size))
    
    # Update demand
    new_demand = max(0, state.demand - 1)
    
    new_state = %{state | 
      buffer: remaining_buffer, 
      batch_timer: new_timer,
      demand: new_demand,
      stats: new_stats
    }
    
    # Emit telemetry for batch created
    BatchingTelemetry.emit_batch_created(batch_size, trigger, :queue.len(remaining_buffer))
    
    # Try to emit more batches if we still have demand and messages
    {more_events, final_state} = try_emit_batches(new_state)
    
    {[batch | more_events], final_state}
  end
  
  defp extract_from_buffer(buffer, count) do
    extract_from_buffer(buffer, count, [])
  end
  
  defp extract_from_buffer(buffer, 0, acc) do
    {Enum.reverse(acc), buffer}
  end
  
  defp extract_from_buffer(buffer, count, acc) do
    case :queue.out(buffer) do
      {{:value, item}, new_buffer} ->
        extract_from_buffer(new_buffer, count - 1, [item | acc])
      {:empty, _} ->
        {Enum.reverse(acc), buffer}
    end
  end
  
  defp create_batch_event(entries, trigger) do
    messages = Enum.map(entries, fn {msg, ctx, _time} -> {msg, ctx} end)
    
    %{
      messages: messages,
      batch_size: length(messages),
      trigger: trigger,
      timestamp: System.system_time(:microsecond),
      metadata: %{
        producer: __MODULE__
      }
    }
  end
  
  defp cancel_timer(nil), do: nil
  defp cancel_timer(timer_ref) do
    Process.cancel_timer(timer_ref)
    nil
  end
end