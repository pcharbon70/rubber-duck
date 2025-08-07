defmodule RubberDuck.Pipeline.SideEffectProcessor do
  @moduledoc """
  GenStage consumer for processing side effects of entity updates.
  
  This stage handles non-critical path operations like change propagation
  and learning tracking. These operations are processed asynchronously
  after the core update has completed.
  
  ## Features
  
  - Asynchronous propagation to dependent entities
  - Learning and outcome tracking
  - Error isolation for side effects
  - Configurable processing concurrency
  - Dead letter queue for failed side effects
  
  ## Side Effects Handled
  
  1. Change Propagation (via UpdateEntity.Propagator)
  2. Learning Tracking (via UpdateEntity.Learner)
  """
  
  use GenStage
  require Logger
  
  alias RubberDuck.Actions.Core.UpdateEntity.{
    Propagator,
    Learner
  }
  
  @default_concurrency 4
  @default_max_demand 5
  
  # Client API
  
  @doc """
  Starts the side effect processor linked to the current process.
  """
  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Returns the current processor status including dead letter queue.
  """
  def get_status do
    GenStage.call(__MODULE__, :get_status)
  end
  
  @doc """
  Retrieves failed side effects from the dead letter queue.
  """
  def get_dead_letters(limit \\ 10) do
    GenStage.call(__MODULE__, {:get_dead_letters, limit})
  end
  
  @doc """
  Retries failed side effects from the dead letter queue.
  """
  def retry_dead_letters(count \\ 10) do
    GenStage.call(__MODULE__, {:retry_dead_letters, count})
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    concurrency = Keyword.get(opts, :concurrency, @default_concurrency)
    max_demand = Keyword.get(opts, :max_demand, @default_max_demand)
    
    # Subscribe to the processor
    producer = Keyword.get(opts, :producer, RubberDuck.Pipeline.EntityUpdateProcessor)
    
    state = %{
      concurrency: concurrency,
      max_demand: max_demand,
      dead_letter_queue: :queue.new(),
      max_dead_letters: 1000,
      stats: %{
        processed: 0,
        propagated: 0,
        learned: 0,
        failed: 0
      }
    }
    
    Logger.info("SideEffectProcessor started with concurrency: #{concurrency}")
    
    # Subscribe to processor with max_demand
    subscription_opts = [
      to: producer,
      max_demand: max_demand,
      min_demand: 0
    ]
    
    {:consumer, state, subscribe_to: [subscription_opts]}
  end
  
  @impl true
  def handle_events(events, _from, state) do
    start_time = System.monotonic_time(:millisecond)
    
    # Filter events that need side effect processing
    events_needing_processing = 
      events
      |> Enum.filter(&needs_side_effects?/1)
    
    if length(events_needing_processing) > 0 do
      # Process side effects concurrently
      results = 
        events_needing_processing
        |> Task.async_stream(
          &process_side_effects(&1, state),
          max_concurrency: state.concurrency,
          timeout: 60_000,
          on_timeout: :kill_task
        )
        |> Enum.map(&handle_task_result/1)
      
      # Update statistics
      updated_state = update_statistics(state, results)
      
      # Add failures to dead letter queue
      final_state = add_failures_to_dlq(updated_state, results)
      
      # Emit telemetry
      processing_time = System.monotonic_time(:millisecond) - start_time
      emit_telemetry(:batch_processed, %{
        count: length(events_needing_processing),
        processing_time_ms: processing_time
      })
      
      {:noreply, [], final_state}
    else
      # No events need processing
      {:noreply, [], state}
    end
  end
  
  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      concurrency: state.concurrency,
      dead_letter_queue_size: :queue.len(state.dead_letter_queue),
      stats: state.stats
    }
    
    {:reply, status, [], state}
  end
  
  @impl true
  def handle_call({:get_dead_letters, limit}, _from, state) do
    dead_letters = get_queue_items(state.dead_letter_queue, limit)
    {:reply, dead_letters, [], state}
  end
  
  @impl true
  def handle_call({:retry_dead_letters, count}, _from, state) do
    {to_retry, remaining_queue} = extract_from_queue(state.dead_letter_queue, count)
    
    # Process retries asynchronously
    Task.start(fn ->
      Enum.each(to_retry, fn {event, _error, _timestamp} ->
        process_side_effects(event, state)
      end)
    end)
    
    updated_state = %{state | dead_letter_queue: remaining_queue}
    
    {:reply, {:ok, length(to_retry)}, [], updated_state}
  end
  
  # Private Functions
  
  defp needs_side_effects?(nil), do: false
  defp needs_side_effects?(%{propagation_needed: true}), do: true
  defp needs_side_effects?(%{learning_enabled: true}), do: true
  defp needs_side_effects?(_), do: false
  
  defp process_side_effects(event, _state) do
    results = %{
      event_id: event.event_id,
      propagation: nil,
      learning: nil,
      errors: []
    }
    
    # Process propagation if needed
    results = 
      if event.propagation_needed do
        process_propagation(event, results)
      else
        results
      end
    
    # Process learning if enabled
    results = 
      if event.learning_enabled do
        process_learning(event, results)
      else
        results
      end
    
    # Determine overall success
    if length(results.errors) > 0 do
      {:error, event, results}
    else
      {:ok, results}
    end
  end
  
  defp process_propagation(event, results) do
    try do
      propagator_params = %{
        entity_id: event.entity_id,
        entity_type: event.entity_type,
        changes_applied: event.changes_applied,
        affected_entities: event.affected_entities,
        impact_score: event.impact_score
      }
      
      case Propagator.propagate(propagator_params, event.context) do
        {:ok, propagation_result} ->
          emit_telemetry(:propagation_completed, %{
            entity_type: event.entity_type,
            affected_count: length(event.affected_entities)
          })
          
          %{results | propagation: propagation_result}
        
        {:error, reason} ->
          Logger.error("Propagation failed for #{event.event_id}: #{inspect(reason)}")
          
          emit_telemetry(:propagation_failed, %{
            entity_type: event.entity_type,
            reason: inspect(reason)
          })
          
          %{results | errors: [{:propagation, reason} | results.errors]}
      end
    rescue
      error ->
        Logger.error("Propagation crashed for #{event.event_id}: #{inspect(error)}")
        %{results | errors: [{:propagation, {:crash, error}} | results.errors]}
    end
  end
  
  defp process_learning(event, results) do
    try do
      learner_params = %{
        entity_id: event.entity_id,
        entity_type: event.entity_type,
        changes_applied: event.changes_applied,
        impact_score: event.impact_score,
        updated_entity: event.updated_entity,
        timestamp: event.processed_at
      }
      
      case Learner.learn(learner_params, event.context) do
        {:ok, learning_result} ->
          emit_telemetry(:learning_completed, %{
            entity_type: event.entity_type,
            confidence_score: learning_result[:confidence_score]
          })
          
          %{results | learning: learning_result}
        
        {:error, reason} ->
          Logger.error("Learning failed for #{event.event_id}: #{inspect(reason)}")
          
          emit_telemetry(:learning_failed, %{
            entity_type: event.entity_type,
            reason: inspect(reason)
          })
          
          %{results | errors: [{:learning, reason} | results.errors]}
      end
    rescue
      error ->
        Logger.error("Learning crashed for #{event.event_id}: #{inspect(error)}")
        %{results | errors: [{:learning, {:crash, error}} | results.errors]}
    end
  end
  
  defp handle_task_result({:ok, result}), do: result
  defp handle_task_result({:exit, :timeout}) do
    Logger.error("Side effect processing timeout")
    {:error, nil, :timeout}
  end
  defp handle_task_result({:exit, reason}) do
    Logger.error("Side effect processing crashed: #{inspect(reason)}")
    {:error, nil, {:crash, reason}}
  end
  
  defp update_statistics(state, results) do
    stats = 
      Enum.reduce(results, state.stats, fn
        {:ok, result}, acc ->
          acc
          |> Map.update!(:processed, &(&1 + 1))
          |> update_if_present(:propagated, result.propagation, 1)
          |> update_if_present(:learned, result.learning, 1)
        
        {:error, _, _}, acc ->
          acc
          |> Map.update!(:processed, &(&1 + 1))
          |> Map.update!(:failed, &(&1 + 1))
        
        _, acc -> acc
      end)
    
    %{state | stats: stats}
  end
  
  defp update_if_present(map, _key, nil, _increment), do: map
  defp update_if_present(map, key, _value, increment) do
    Map.update!(map, key, &(&1 + increment))
  end
  
  defp add_failures_to_dlq(state, results) do
    failures = 
      results
      |> Enum.filter(fn
        {:error, event, _} when not is_nil(event) -> true
        _ -> false
      end)
      |> Enum.map(fn {:error, event, error} ->
        {event, error, DateTime.utc_now()}
      end)
    
    if length(failures) > 0 do
      updated_queue = 
        Enum.reduce(failures, state.dead_letter_queue, fn failure, queue ->
          add_to_bounded_queue(queue, failure, state.max_dead_letters)
        end)
      
      %{state | dead_letter_queue: updated_queue}
    else
      state
    end
  end
  
  defp add_to_bounded_queue(queue, item, max_size) do
    if :queue.len(queue) >= max_size do
      # Remove oldest item and add new one
      {_, smaller_queue} = :queue.out(queue)
      :queue.in(item, smaller_queue)
    else
      :queue.in(item, queue)
    end
  end
  
  defp get_queue_items(queue, limit) do
    queue
    |> :queue.to_list()
    |> Enum.take(limit)
  end
  
  defp extract_from_queue(queue, count) do
    extract_from_queue(queue, count, [])
  end
  
  defp extract_from_queue(queue, 0, acc), do: {Enum.reverse(acc), queue}
  defp extract_from_queue(queue, count, acc) do
    case :queue.out(queue) do
      {{:value, item}, new_queue} ->
        extract_from_queue(new_queue, count - 1, [item | acc])
      
      {:empty, new_queue} ->
        {Enum.reverse(acc), new_queue}
    end
  end
  
  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:rubber_duck, :pipeline, :side_effects, event],
      %{count: 1},
      metadata
    )
  end
end