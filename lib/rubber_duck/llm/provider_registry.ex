defmodule RubberDuck.LLM.ProviderRegistry do
  @moduledoc """
  Registry for managing LLM providers using ETS for fast lookups.

  Maintains a registry of available providers, their configurations,
  and health status.
  """

  use GenServer
  require Logger

  @table_name :llm_provider_registry
  @cleanup_interval 60_000

  # Client API

  @doc """
  Start the provider registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a provider with the registry.
  """
  def register(provider_name, provider_module, config) do
    GenServer.call(__MODULE__, {:register, provider_name, provider_module, config})
  end

  @doc """
  Unregister a provider from the registry.
  """
  def unregister(provider_name) do
    GenServer.call(__MODULE__, {:unregister, provider_name})
  end

  @doc """
  Get a provider by name.
  """
  def get(provider_name) do
    case :ets.lookup(@table_name, provider_name) do
      [{^provider_name, provider_data}] -> {:ok, provider_data}
      [] -> {:error, :provider_not_found}
    end
  end

  @doc """
  List all registered providers.
  """
  def list do
    @table_name
    |> :ets.tab2list()
    |> Enum.map(fn {_name, data} -> data end)
  end

  @doc """
  List all available (healthy) providers.
  """
  def list_available do
    list()
    |> Enum.filter(& &1.available)
  end

  @doc """
  Update provider health status.
  """
  def update_health(provider_name, health_status) do
    GenServer.cast(__MODULE__, {:update_health, provider_name, health_status})
  end

  @doc """
  Mark a provider as unavailable.
  """
  def mark_unavailable(provider_name) do
    update_health(provider_name, %{available: false, last_error: :marked_unavailable})
  end

  @doc """
  Mark a provider as available.
  """
  def mark_available(provider_name) do
    update_health(provider_name, %{available: true, last_error: nil})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for provider storage
    :ets.new(@table_name, [:named_table, :public, :set, read_concurrency: true])

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup_stale_providers, @cleanup_interval)

    state = %{
      table: @table_name,
      registered_count: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:register, provider_name, provider_module, config}, _from, state) do
    provider_data = %{
      name: provider_name,
      module: provider_module,
      config: config,
      available: true,
      registered_at: DateTime.utc_now(),
      last_health_check: nil,
      last_error: nil,
      request_count: 0,
      error_count: 0
    }

    :ets.insert(@table_name, {provider_name, provider_data})

    Logger.info("Registered LLM provider: #{provider_name}")

    new_state = %{state | registered_count: state.registered_count + 1}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unregister, provider_name}, _from, state) do
    :ets.delete(@table_name, provider_name)

    Logger.info("Unregistered LLM provider: #{provider_name}")

    new_state = %{state | registered_count: max(0, state.registered_count - 1)}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:update_health, provider_name, health_status}, state) do
    case :ets.lookup(@table_name, provider_name) do
      [{^provider_name, provider_data}] ->
        updated_data =
          provider_data
          |> Map.merge(health_status)
          |> Map.put(:last_health_check, DateTime.utc_now())

        :ets.insert(@table_name, {provider_name, updated_data})

        if health_status[:available] == false do
          Logger.warning(
            "Provider #{provider_name} marked as unavailable: #{inspect(health_status[:last_error])}"
          )
        end

      [] ->
        Logger.warning("Attempted to update health for unknown provider: #{provider_name}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_stale_providers, state) do
    # Clean up providers that haven't had a health check in over 5 minutes
    stale_threshold = DateTime.add(DateTime.utc_now(), -300, :second)

    @table_name
    |> :ets.tab2list()
    |> Enum.each(fn {name, data} ->
      if data.last_health_check &&
           DateTime.compare(data.last_health_check, stale_threshold) == :lt do
        Logger.warning("Marking provider #{name} as stale (no health check for 5+ minutes)")
        update_health(name, %{available: false, last_error: :stale})
      end
    end)

    # Schedule next cleanup
    Process.send_after(self(), :cleanup_stale_providers, @cleanup_interval)

    {:noreply, state}
  end
end
