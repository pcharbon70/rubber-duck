defmodule RubberDuck.LLM.HealthMonitor do
  @moduledoc """
  Health monitoring for LLM providers.

  Performs periodic health checks, tracks response times, error rates,
  and automatically disables unhealthy providers.
  """

  use GenServer
  require Logger

  alias RubberDuck.LLM.ProviderRegistry

  @check_interval 30_000  # 30 seconds
  @error_threshold 0.5    # 50% error rate threshold
  @min_samples 10         # Minimum samples for error rate calculation

  # Client API

  @doc """
  Start the health monitor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Perform an immediate health check for a specific provider.
  """
  def check_provider(provider_name) do
    GenServer.call(__MODULE__, {:check_provider, provider_name})
  end

  @doc """
  Perform health checks for all providers.
  """
  def check_all do
    GenServer.call(__MODULE__, :check_all)
  end

  @doc """
  Record a successful request for metrics.
  """
  def record_success(provider_name, response_time_ms) do
    GenServer.cast(__MODULE__, {:record_success, provider_name, response_time_ms})
  end

  @doc """
  Record a failed request for metrics.
  """
  def record_failure(provider_name, error) do
    GenServer.cast(__MODULE__, {:record_failure, provider_name, error})
  end

  @doc """
  Get health metrics for a provider.
  """
  def get_metrics(provider_name) do
    GenServer.call(__MODULE__, {:get_metrics, provider_name})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Schedule first health check
    Process.send_after(self(), :periodic_health_check, @check_interval)

    state = %{
      metrics: %{},
      check_interval: @check_interval
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:check_provider, provider_name}, _from, state) do
    result = perform_health_check(provider_name)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:check_all, _from, state) do
    results =
      ProviderRegistry.list()
      |> Enum.map(fn provider ->
        {provider.name, perform_health_check(provider.name)}
      end)
      |> Map.new()

    {:reply, results, state}
  end

  @impl true
  def handle_call({:get_metrics, provider_name}, _from, state) do
    metrics = Map.get(state.metrics, provider_name, default_metrics())
    {:reply, metrics, state}
  end

  @impl true
  def handle_cast({:record_success, provider_name, response_time_ms}, state) do
    metrics = get_or_init_metrics(state, provider_name)

    updated_metrics =
      metrics
      |> Map.update!(:success_count, &(&1 + 1))
      |> Map.update!(:total_count, &(&1 + 1))
      |> update_response_times(response_time_ms)
      |> calculate_error_rate()

    new_state = put_in(state, [:metrics, provider_name], updated_metrics)

    # Check if provider should be marked as healthy
    if updated_metrics.error_rate < @error_threshold && !updated_metrics.available do
      ProviderRegistry.mark_available(provider_name)
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_failure, provider_name, error}, state) do
    metrics = get_or_init_metrics(state, provider_name)

    updated_metrics =
      metrics
      |> Map.update!(:error_count, &(&1 + 1))
      |> Map.update!(:total_count, &(&1 + 1))
      |> Map.put(:last_error, error)
      |> Map.put(:last_error_at, DateTime.utc_now())
      |> calculate_error_rate()

    new_state = put_in(state, [:metrics, provider_name], updated_metrics)

    # Check if provider should be marked as unhealthy
    if should_disable_provider?(updated_metrics) do
      Logger.error("Disabling provider #{provider_name} due to high error rate: #{updated_metrics.error_rate}")
      ProviderRegistry.mark_unavailable(provider_name)
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:periodic_health_check, state) do
    # Perform health checks for all providers
    ProviderRegistry.list()
    |> Enum.each(fn provider ->
      Task.start(fn ->
        perform_health_check(provider.name)
      end)
    end)

    # Schedule next check
    Process.send_after(self(), :periodic_health_check, @check_interval)

    {:noreply, state}
  end

  # Private functions

  defp perform_health_check(provider_name) do
    case ProviderRegistry.get(provider_name) do
      {:ok, provider} ->
        start_time = System.monotonic_time(:millisecond)

        result = provider.module.health_check(provider.config)

        response_time = System.monotonic_time(:millisecond) - start_time

        case result do
          :ok ->
            record_success(provider_name, response_time)
            ProviderRegistry.update_health(provider_name, %{
              available: true,
              last_error: nil,
              response_time_ms: response_time
            })
            :ok

          {:error, reason} ->
            record_failure(provider_name, reason)
            ProviderRegistry.update_health(provider_name, %{
              available: false,
              last_error: reason,
              response_time_ms: response_time
            })
            {:error, reason}
        end

      {:error, :provider_not_found} ->
        {:error, :provider_not_found}
    end
  rescue
    error ->
      record_failure(provider_name, error)
      ProviderRegistry.update_health(provider_name, %{
        available: false,
        last_error: error,
        response_time_ms: 0
      })
      {:error, error}
  end

  defp get_or_init_metrics(state, provider_name) do
    Map.get(state.metrics, provider_name, default_metrics())
  end

  defp default_metrics do
    %{
      success_count: 0,
      error_count: 0,
      total_count: 0,
      error_rate: 0.0,
      response_times: [],
      avg_response_time: 0,
      max_response_time: 0,
      available: true,
      last_error: nil,
      last_error_at: nil
    }
  end

  defp update_response_times(metrics, response_time_ms) do
    # Keep last 100 response times
    response_times =
      [response_time_ms | metrics.response_times]
      |> Enum.take(100)

    avg_response_time =
      if Enum.empty?(response_times) do
        0
      else
        Enum.sum(response_times) / length(response_times)
      end

    max_response_time =
      if Enum.empty?(response_times) do
        0
      else
        Enum.max(response_times)
      end

    metrics
    |> Map.put(:response_times, response_times)
    |> Map.put(:avg_response_time, avg_response_time)
    |> Map.put(:max_response_time, max_response_time)
  end

  defp calculate_error_rate(metrics) do
    if metrics.total_count >= @min_samples do
      error_rate = metrics.error_count / metrics.total_count
      Map.put(metrics, :error_rate, error_rate)
    else
      metrics
    end
  end

  defp should_disable_provider?(metrics) do
    metrics.total_count >= @min_samples &&
      metrics.error_rate > @error_threshold
  end
end
