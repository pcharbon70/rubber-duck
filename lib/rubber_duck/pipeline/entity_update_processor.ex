defmodule RubberDuck.Pipeline.EntityUpdateProcessor do
  @moduledoc """
  GenStage producer-consumer for processing core entity update logic.

  This stage handles validation, impact analysis, and execution of entity updates
  using the existing business logic modules. It processes multiple updates
  concurrently while maintaining backpressure.

  ## Features

  - Concurrent processing of entity updates
  - Integration with existing business logic modules
  - Error isolation and recovery
  - Performance tracking via telemetry
  - Configurable concurrency levels

  ## Processing Pipeline

  1. Validation (via UpdateEntity.Validator)
  2. Impact Analysis (via UpdateEntity.ImpactAnalyzer)
  3. Execution (via UpdateEntity.Executor)
  """

  use GenStage
  require Logger

  alias RubberDuck.Actions.Core.Entity

  alias RubberDuck.Actions.Core.UpdateEntity.{
    Validator,
    ImpactAnalyzer,
    Executor
  }

  @default_concurrency 8
  @default_max_demand 10

  # Client API

  @doc """
  Starts the processor linked to the current process.
  """
  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the current processor status.
  """
  def get_status do
    GenStage.call(__MODULE__, :get_status)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    concurrency = Keyword.get(opts, :concurrency, @default_concurrency)
    max_demand = Keyword.get(opts, :max_demand, @default_max_demand)

    # Subscribe to the producer
    producer = Keyword.get(opts, :producer, RubberDuck.Pipeline.EntityUpdateProducer)

    state = %{
      concurrency: concurrency,
      max_demand: max_demand,
      stats: %{
        processed: 0,
        succeeded: 0,
        failed: 0,
        processing_times: []
      }
    }

    # Emit telemetry for processor startup
    :telemetry.execute(
      [:rubber_duck, :pipeline, :processor, :started],
      %{concurrency: concurrency},
      %{processor_type: :entity_update}
    )
    
    Logger.debug("EntityUpdateProcessor started with concurrency: #{concurrency}")

    # Subscribe to producer with max_demand
    subscription_opts = [
      to: producer,
      max_demand: max_demand,
      min_demand: 0
    ]

    {:producer_consumer, state, subscribe_to: [subscription_opts]}
  end

  @impl true
  def handle_events(events, _from, state) do
    start_time = System.monotonic_time(:millisecond)

    # Process events concurrently
    processed_events =
      events
      |> Task.async_stream(
        &process_entity_update(&1, state),
        max_concurrency: state.concurrency,
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.map(&handle_task_result/1)
      |> Enum.filter(&filter_valid_results/1)

    # Calculate processing time
    processing_time = System.monotonic_time(:millisecond) - start_time

    # Update statistics
    {succeeded, failed} = count_results(processed_events)

    updated_stats =
      state.stats
      |> Map.update!(:processed, &(&1 + length(events)))
      |> Map.update!(:succeeded, &(&1 + succeeded))
      |> Map.update!(:failed, &(&1 + failed))
      |> Map.update!(:processing_times, &track_timing(&1, processing_time))

    # Emit telemetry
    emit_telemetry(:batch_processed, %{
      count: length(events),
      succeeded: succeeded,
      failed: failed,
      processing_time_ms: processing_time
    })

    {:noreply, processed_events, %{state | stats: updated_stats}}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    avg_processing_time = calculate_avg_processing_time(state.stats.processing_times)

    status = %{
      concurrency: state.concurrency,
      stats: Map.put(state.stats, :avg_processing_time_ms, avg_processing_time)
    }

    {:reply, status, [], state}
  end

  # Private Functions

  defp process_entity_update(event, _state) do
    start_time = System.monotonic_time(:microsecond)

    try do
      result =
        event
        |> prepare_update_params()
        |> fetch_entity()
        |> validate_update()
        |> analyze_impact()
        |> execute_update()
        |> format_result(event)

      processing_time = System.monotonic_time(:microsecond) - start_time

      emit_telemetry(:update_processed, %{
        entity_type: get_entity_type(event),
        processing_time_us: processing_time,
        success: true
      })

      # Handle synchronous replies
      maybe_reply_to_sync(event, {:ok, result})

      {:ok, result}
    rescue
      error ->
        Logger.error("Entity update processing failed: #{inspect(error)}")

        emit_telemetry(:update_failed, %{
          entity_type: get_entity_type(event),
          error: inspect(error)
        })

        # Handle synchronous error replies
        maybe_reply_to_sync(event, {:error, error})

        {:error, %{event: event, error: error}}
    end
  end

  defp prepare_update_params(%{params: params, context: context}) do
    %{
      entity_id: params.entity_id,
      entity_type: params.entity_type,
      changes: params.changes,
      validation_config: Map.get(params, :validation_config, %{}),
      agent_goals: Map.get(params, :agent_goals, []),
      options: %{
        impact_analysis: Map.get(params, :impact_analysis, true),
        auto_propagate: Map.get(params, :auto_propagate, false),
        learning_enabled: Map.get(params, :learning_enabled, true),
        rollback_on_failure: Map.get(params, :rollback_on_failure, true)
      },
      context: context
    }
  end

  defp fetch_entity(params) do
    case Entity.fetch(params.entity_type, params.entity_id) do
      {:ok, entity} ->
        Map.put(params, :entity, entity)

      {:error, reason} ->
        raise "Failed to fetch entity: #{inspect(reason)}"
    end
  end

  defp validate_update(params) do
    validator_params = %{
      entity: params.entity,
      changes: params.changes,
      validation_config: params.validation_config,
      agent_goals: params.agent_goals
    }

    case Validator.validate(validator_params, params.context) do
      {:ok, validated} ->
        Map.merge(params, validated)

      {:error, reason} ->
        raise "Validation failed: #{inspect(reason)}"
    end
  end

  defp analyze_impact(params) when params.options.impact_analysis do
    analyzer_params = %{
      entity: params.entity,
      changes: params.changes,
      validated_changes: params.validated_changes
    }

    case ImpactAnalyzer.analyze(analyzer_params, params.context) do
      {:ok, impact} ->
        Map.merge(params, impact)
        # Note: ImpactAnalyzer.analyze/2 currently always returns {:ok, _}
        # Error handling can be added here if needed in future
    end
  end

  defp analyze_impact(params) do
    # Skip impact analysis if disabled
    Map.put(params, :impact_score, 0.0)
  end

  defp execute_update(params) do
    executor_params = %{
      entity: params.entity,
      validated_changes: params.validated_changes,
      impact_score: params.impact_score,
      rollback_on_failure: params.options.rollback_on_failure
    }

    case Executor.execute(executor_params, params.context) do
      {:ok, executed} ->
        Map.merge(params, executed)

      {:error, reason} ->
        raise "Execution failed: #{inspect(reason)}"
    end
  end

  defp format_result(processed_params, original_event) do
    %{
      event_id: generate_event_id(),
      entity_id: processed_params.entity_id,
      entity_type: processed_params.entity_type,
      updated_entity: processed_params.updated_entity,
      impact_score: processed_params.impact_score,
      changes_applied: processed_params.changes_applied,
      timestamp: original_event.timestamp,
      processed_at: DateTime.utc_now(),
      metadata: %{
        validation_passed: true,
        impact_analyzed: processed_params.options.impact_analysis,
        execution_completed: true
      },
      # Pass along data needed for side effects
      propagation_needed: processed_params.options.auto_propagate,
      learning_enabled: processed_params.options.learning_enabled,
      affected_entities: Map.get(processed_params, :affected_entities, []),
      context: processed_params.context
    }
  end

  defp handle_task_result({:ok, result}), do: result

  defp handle_task_result({:exit, :timeout}) do
    Logger.error("Entity update processing timeout")
    {:error, :timeout}
  end

  defp handle_task_result({:exit, reason}) do
    Logger.error("Entity update processing crashed: #{inspect(reason)}")
    {:error, :crashed}
  end

  defp filter_valid_results({:ok, result}), do: result
  defp filter_valid_results({:error, _}), do: nil
  defp filter_valid_results(nil), do: nil
  defp filter_valid_results(result), do: result

  defp count_results(results) do
    Enum.reduce(results, {0, 0}, fn
      nil, {succeeded, failed} -> {succeeded, failed + 1}
      %{entity_id: _}, {succeeded, failed} -> {succeeded + 1, failed}
      _, {succeeded, failed} -> {succeeded, failed}
    end)
  end

  defp track_timing(times, new_time) do
    # Keep last 100 processing times
    [new_time | Enum.take(times, 99)]
  end

  defp calculate_avg_processing_time([]), do: 0

  defp calculate_avg_processing_time(times) do
    Enum.sum(times) / length(times)
  end

  defp get_entity_type(%{params: %{entity_type: type}}), do: type
  defp get_entity_type(_), do: :unknown

  defp maybe_reply_to_sync(%{type: :sync, from: from}, result) do
    GenStage.reply(from, result)
  end

  defp maybe_reply_to_sync(_, _), do: :ok

  defp generate_event_id do
    "evt_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:rubber_duck, :pipeline, :processor, event],
      %{count: 1},
      metadata
    )
  end
end
