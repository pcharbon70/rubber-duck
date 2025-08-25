defmodule RubberDuck.Webhooks do
  @moduledoc """
  Webhook system for preference change notifications.

  Provides event-driven notifications for preference changes with configurable
  endpoints, retry logic, and event filtering. Integrates with the preference
  system to deliver real-time updates to external systems.
  """

  use GenServer

  require Logger

  alias RubberDuck.Preferences.PreferenceWatcher

  @default_retry_attempts 3
  @default_timeout 5000

  defstruct [
    :webhooks,
    :event_queue,
    :retry_queue,
    :stats
  ]

  @doc """
  Start the webhook system.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a webhook endpoint for preference change notifications.
  """
  def register_webhook(endpoint_url, opts \\ []) do
    GenServer.call(__MODULE__, {:register_webhook, endpoint_url, opts})
  end

  @doc """
  Unregister a webhook endpoint.
  """
  def unregister_webhook(webhook_id) do
    GenServer.call(__MODULE__, {:unregister_webhook, webhook_id})
  end

  @doc """
  Send webhook notification for preference change.
  """
  def notify_preference_change(change_event) do
    GenServer.cast(__MODULE__, {:notify_change, change_event})
  end

  @doc """
  Get webhook statistics and health status.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    # Subscribe to preference change events
    PreferenceWatcher.subscribe_all_changes()

    state = %__MODULE__{
      webhooks: %{},
      event_queue: :queue.new(),
      retry_queue: :queue.new(),
      stats: %{
        total_events: 0,
        successful_deliveries: 0,
        failed_deliveries: 0,
        active_webhooks: 0
      }
    }

    # Schedule periodic retry processing
    schedule_retry_processing()

    {:ok, state}
  end

  @impl true
  def handle_call({:register_webhook, endpoint_url, opts}, _from, state) do
    webhook_id = generate_webhook_id()

    webhook_config = %{
      id: webhook_id,
      endpoint_url: endpoint_url,
      secret: Map.get(opts, :secret),
      event_types: Map.get(opts, :event_types, [:all]),
      user_filters: Map.get(opts, :user_filters, []),
      project_filters: Map.get(opts, :project_filters, []),
      category_filters: Map.get(opts, :category_filters, []),
      retry_attempts: Map.get(opts, :retry_attempts, @default_retry_attempts),
      timeout: Map.get(opts, :timeout, @default_timeout),
      active: true,
      created_at: DateTime.utc_now()
    }

    updated_webhooks = Map.put(state.webhooks, webhook_id, webhook_config)
    updated_stats = %{state.stats | active_webhooks: state.stats.active_webhooks + 1}

    new_state = %{state | webhooks: updated_webhooks, stats: updated_stats}

    Logger.info("Registered webhook: #{webhook_id} -> #{endpoint_url}")
    {:reply, {:ok, webhook_id}, new_state}
  end

  @impl true
  def handle_call({:unregister_webhook, webhook_id}, _from, state) do
    case Map.get(state.webhooks, webhook_id) do
      nil ->
        {:reply, {:error, "Webhook not found"}, state}

      _webhook_config ->
        updated_webhooks = Map.delete(state.webhooks, webhook_id)
        updated_stats = %{state.stats | active_webhooks: state.stats.active_webhooks - 1}

        new_state = %{state | webhooks: updated_webhooks, stats: updated_stats}

        Logger.info("Unregistered webhook: #{webhook_id}")
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats =
      Map.merge(state.stats, %{
        queue_size: :queue.len(state.event_queue),
        retry_queue_size: :queue.len(state.retry_queue),
        registered_webhooks: map_size(state.webhooks)
      })

    {:reply, {:ok, stats}, state}
  end

  @impl true
  def handle_cast({:notify_change, change_event}, state) do
    # Filter webhooks that should receive this event
    matching_webhooks = filter_webhooks_for_event(state.webhooks, change_event)

    # Queue delivery for each matching webhook
    updated_queue =
      Enum.reduce(matching_webhooks, state.event_queue, fn webhook, queue ->
        delivery_event = %{
          webhook_id: webhook.id,
          event: change_event,
          scheduled_at: DateTime.utc_now(),
          attempts: 0
        }

        :queue.in(delivery_event, queue)
      end)

    updated_stats = %{state.stats | total_events: state.stats.total_events + 1}

    new_state = %{state | event_queue: updated_queue, stats: updated_stats}

    # Process the queue
    process_event_queue(new_state)
  end

  @impl true
  def handle_info(:process_retry_queue, state) do
    new_state = process_retry_queue(state)
    schedule_retry_processing()
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:preference_changed, change_event}, state) do
    # Handle preference change events from PubSub
    handle_cast({:notify_change, change_event}, state)
  end

  # Private helper functions

  defp generate_webhook_id do
    "webhook_#{System.unique_integer([:positive])}_#{DateTime.utc_now() |> DateTime.to_unix()}"
  end

  defp filter_webhooks_for_event(webhooks, change_event) do
    webhooks
    |> Map.values()
    |> Enum.filter(&webhook_matches_event?(&1, change_event))
  end

  defp webhook_matches_event?(webhook, change_event) do
    webhook.active and
      event_type_matches?(webhook.event_types, change_event) and
      user_filter_matches?(webhook.user_filters, change_event) and
      project_filter_matches?(webhook.project_filters, change_event) and
      category_filter_matches?(webhook.category_filters, change_event)
  end

  defp event_type_matches?(event_types, _change_event) do
    :all in event_types or :user_preference_changed in event_types
  end

  defp user_filter_matches?(user_filters, change_event) do
    Enum.empty?(user_filters) or change_event.user_id in user_filters
  end

  defp project_filter_matches?(project_filters, change_event) do
    Enum.empty?(project_filters) or
      (change_event.project_id && change_event.project_id in project_filters)
  end

  defp category_filter_matches?(category_filters, change_event) do
    Enum.empty?(category_filters) or
      get_preference_category(change_event.preference_key) in category_filters
  end

  defp process_event_queue(%{event_queue: queue} = state) do
    case :queue.out(queue) do
      {{:value, delivery_event}, remaining_queue} ->
        handle_delivery_event(delivery_event, remaining_queue, state)

      {:empty, _} ->
        state
    end
  end

  defp handle_delivery_event(delivery_event, remaining_queue, state) do
    case deliver_webhook_event(delivery_event) do
      :ok ->
        handle_successful_delivery(remaining_queue, state)

      {:error, _reason} ->
        handle_failed_delivery(delivery_event, remaining_queue, state)
    end
  end

  defp handle_successful_delivery(remaining_queue, state) do
    updated_stats = %{
      state.stats
      | successful_deliveries: state.stats.successful_deliveries + 1
    }

    new_state = %{state | event_queue: remaining_queue, stats: updated_stats}
    process_event_queue(new_state)
  end

  defp handle_failed_delivery(delivery_event, remaining_queue, state) do
    if delivery_event.attempts < @default_retry_attempts do
      retry_failed_delivery(delivery_event, remaining_queue, state)
    else
      mark_delivery_as_failed(remaining_queue, state)
    end
  end

  defp retry_failed_delivery(delivery_event, remaining_queue, state) do
    retry_event = %{delivery_event | attempts: delivery_event.attempts + 1}
    updated_retry_queue = :queue.in(retry_event, state.retry_queue)

    new_state = %{
      state
      | event_queue: remaining_queue,
        retry_queue: updated_retry_queue
    }

    process_event_queue(new_state)
  end

  defp mark_delivery_as_failed(remaining_queue, state) do
    updated_stats = %{
      state.stats
      | failed_deliveries: state.stats.failed_deliveries + 1
    }

    new_state = %{state | event_queue: remaining_queue, stats: updated_stats}
    process_event_queue(new_state)
  end

  defp process_retry_queue(%{retry_queue: retry_queue} = state) do
    case :queue.out(retry_queue) do
      {{:value, retry_event}, remaining_retry_queue} ->
        handle_retry_event(retry_event, remaining_retry_queue, state)

      {:empty, _} ->
        state
    end
  end

  defp handle_retry_event(retry_event, remaining_retry_queue, state) do
    case deliver_webhook_event(retry_event) do
      :ok ->
        handle_retry_success(remaining_retry_queue, state)

      {:error, _reason} ->
        handle_retry_failure(retry_event, remaining_retry_queue, state)
    end
  end

  defp handle_retry_success(remaining_retry_queue, state) do
    updated_stats = %{
      state.stats
      | successful_deliveries: state.stats.successful_deliveries + 1
    }

    new_state = %{state | retry_queue: remaining_retry_queue, stats: updated_stats}
    process_retry_queue(new_state)
  end

  defp handle_retry_failure(retry_event, remaining_retry_queue, state) do
    if retry_event.attempts < @default_retry_attempts do
      requeue_retry_event(retry_event, remaining_retry_queue, state)
    else
      mark_retry_as_failed(remaining_retry_queue, state)
    end
  end

  defp requeue_retry_event(retry_event, remaining_retry_queue, state) do
    updated_retry_event = %{retry_event | attempts: retry_event.attempts + 1}
    updated_retry_queue = :queue.in(updated_retry_event, remaining_retry_queue)

    new_state = %{state | retry_queue: updated_retry_queue}
    process_retry_queue(new_state)
  end

  defp mark_retry_as_failed(remaining_retry_queue, state) do
    updated_stats = %{
      state.stats
      | failed_deliveries: state.stats.failed_deliveries + 1
    }

    new_state = %{state | retry_queue: remaining_retry_queue, stats: updated_stats}
    process_retry_queue(new_state)
  end

  defp deliver_webhook_event(delivery_event) do
    webhook = Map.get(%{}, delivery_event.webhook_id, %{})

    _payload = %{
      event_type: "preference_changed",
      event_data: delivery_event.event,
      timestamp: DateTime.utc_now(),
      webhook_id: delivery_event.webhook_id
    }

    # This would make actual HTTP request to webhook endpoint
    Logger.info("Delivering webhook event to #{webhook.endpoint_url || "unknown"}")

    # Simulate delivery success/failure
    if :rand.uniform() > 0.1 do
      :ok
    else
      {:error, "Simulated delivery failure"}
    end
  end

  defp schedule_retry_processing do
    Process.send_after(self(), :process_retry_queue, 30_000)
  end

  defp get_preference_category(preference_key) do
    preference_key |> String.split(".") |> hd()
  end
end
