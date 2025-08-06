defmodule RubberDuck.LLM.Service do
  @moduledoc """
  Main service for managing LLM provider interactions.

  Coordinates provider registration, request routing, fallback mechanisms,
  and metrics collection for all LLM operations.
  """

  use GenServer
  require Logger

  alias RubberDuck.LLM.{Config, HealthMonitor, ProviderRegistry}

  # Client API

  @doc """
  Start the LLM service.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Generate a completion using the default or specified provider.
  """
  def complete(request, opts \\ []) do
    GenServer.call(__MODULE__, {:complete, request, opts}, request_timeout(opts))
  end

  @doc """
  Generate a streaming completion.
  """
  def stream(request, opts \\ []) do
    GenServer.call(__MODULE__, {:stream, request, opts}, request_timeout(opts))
  end

  @doc """
  Generate embeddings for the given input.
  """
  def embed(request, opts \\ []) do
    GenServer.call(__MODULE__, {:embed, request, opts}, request_timeout(opts))
  end

  @doc """
  Register a new provider with the service.
  """
  def register_provider(name, module, config) do
    GenServer.call(__MODULE__, {:register_provider, name, module, config})
  end

  @doc """
  Get the current status of all providers.
  """
  def provider_status do
    GenServer.call(__MODULE__, :provider_status)
  end

  @doc """
  Get metrics for all providers or a specific provider.
  """
  def metrics(provider_name \\ nil) do
    GenServer.call(__MODULE__, {:metrics, provider_name})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Load and register providers from configuration
    Task.start_link(fn ->
      # Allow dependencies to start
      Process.sleep(100)
      load_configured_providers()
    end)

    state = %{
      default_provider: Config.default_provider(),
      request_count: 0,
      start_time: DateTime.utc_now()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:complete, request, opts}, _from, state) do
    provider_name = Keyword.get(opts, :provider, state.default_provider)

    result =
      with {:ok, provider} <- get_available_provider(provider_name),
           {:ok, response} <-
             execute_with_fallback(
               fn -> provider.module.complete(request, provider.config) end,
               :complete,
               request,
               opts
             ) do
        {:ok, response}
      else
        error -> handle_provider_error(error, provider_name)
      end

    new_state = %{state | request_count: state.request_count + 1}
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:stream, request, opts}, _from, state) do
    provider_name = Keyword.get(opts, :provider, state.default_provider)

    result =
      with {:ok, provider} <- get_available_provider(provider_name),
           true <- implements_streaming?(provider.module),
           {:ok, stream} <-
             execute_with_fallback(
               fn -> provider.module.stream(request, provider.config) end,
               :stream,
               request,
               opts
             ) do
        {:ok, stream}
      else
        false -> {:error, :streaming_not_supported}
        error -> handle_provider_error(error, provider_name)
      end

    new_state = %{state | request_count: state.request_count + 1}
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:embed, request, opts}, _from, state) do
    provider_name = Keyword.get(opts, :provider, state.default_provider)

    result =
      with {:ok, provider} <- get_available_provider(provider_name),
           true <- implements_embeddings?(provider.module),
           {:ok, response} <-
             execute_with_fallback(
               fn -> provider.module.embed(request, provider.config) end,
               :embed,
               request,
               opts
             ) do
        {:ok, response}
      else
        false -> {:error, :embeddings_not_supported}
        error -> handle_provider_error(error, provider_name)
      end

    new_state = %{state | request_count: state.request_count + 1}
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:register_provider, name, module, config}, _from, state) do
    with :ok <- validate_provider_module(module),
         :ok <- module.validate_config(config),
         :ok <- ProviderRegistry.register(name, module, config) do
      Logger.info("Successfully registered provider: #{name}")
      {:reply, :ok, state}
    else
      error ->
        Logger.error("Failed to register provider #{name}: #{inspect(error)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:provider_status, _from, state) do
    providers = ProviderRegistry.list()

    status =
      Enum.map(providers, fn provider ->
        metrics = HealthMonitor.get_metrics(provider.name)

        %{
          name: provider.name,
          available: provider.available,
          last_health_check: provider.last_health_check,
          error_rate: metrics.error_rate,
          avg_response_time: metrics.avg_response_time,
          request_count: metrics.total_count
        }
      end)

    {:reply, status, state}
  end

  @impl true
  def handle_call({:metrics, provider_name}, _from, state) do
    metrics =
      if provider_name do
        HealthMonitor.get_metrics(provider_name)
      else
        %{
          total_requests: state.request_count,
          uptime_seconds: DateTime.diff(DateTime.utc_now(), state.start_time),
          providers:
            ProviderRegistry.list()
            |> Enum.map(fn p -> {p.name, HealthMonitor.get_metrics(p.name)} end)
            |> Map.new()
        }
      end

    {:reply, metrics, state}
  end

  # Private functions

  defp load_configured_providers do
    Config.load_providers()
    |> Enum.each(fn config ->
      case load_provider_module(config.module) do
        {:ok, module} ->
          register_provider(config.name, module, config)

        {:error, reason} ->
          Logger.error("Failed to load provider #{config.name}: #{inspect(reason)}")
      end
    end)
  end

  defp load_provider_module(module) when is_atom(module) do
    if Code.ensure_loaded?(module) do
      {:ok, module}
    else
      {:error, :module_not_found}
    end
  end

  defp load_provider_module(module_name) when is_binary(module_name) do
    module = String.to_existing_atom("Elixir.#{module_name}")
    load_provider_module(module)
  rescue
    ArgumentError -> {:error, :invalid_module_name}
  end

  defp validate_provider_module(module) do
    behaviours = module.module_info(:attributes)[:behaviour] || []

    if RubberDuck.LLM.Provider in behaviours do
      :ok
    else
      {:error, :invalid_provider_module}
    end
  end

  defp get_available_provider(provider_name) do
    case ProviderRegistry.get(provider_name) do
      {:ok, provider} ->
        if provider.available do
          {:ok, provider}
        else
          {:error, :provider_unavailable}
        end

      error ->
        error
    end
  end

  defp execute_with_fallback(fun, operation, request, opts) do
    start_time = System.monotonic_time(:millisecond)

    result = fun.()
    response_time = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, _} = success ->
        provider_name = Keyword.get(opts, :provider)
        HealthMonitor.record_success(provider_name, response_time)
        success

      {:error, reason} = error ->
        provider_name = Keyword.get(opts, :provider)
        HealthMonitor.record_failure(provider_name, reason)

        if Keyword.get(opts, :fallback, true) do
          attempt_fallback(operation, request, opts, provider_name)
        else
          error
        end
    end
  rescue
    error ->
      provider_name = Keyword.get(opts, :provider)
      HealthMonitor.record_failure(provider_name, error)

      if Keyword.get(opts, :fallback, true) do
        attempt_fallback(operation, request, opts, provider_name)
      else
        {:error, error}
      end
  end

  defp attempt_fallback(operation, request, opts, failed_provider) do
    Logger.warning("Attempting fallback for #{operation} after #{failed_provider} failed")

    available_providers =
      ProviderRegistry.list_available()
      |> Enum.reject(&(&1.name == failed_provider))

    case available_providers do
      [] ->
        {:error, :no_fallback_available}

      [fallback | _] ->
        Logger.info("Using fallback provider: #{fallback.name}")

        new_opts = Keyword.put(opts, :fallback, false)

        case operation do
          :complete -> complete(request, [{:provider, fallback.name} | new_opts])
          :stream -> stream(request, [{:provider, fallback.name} | new_opts])
          :embed -> embed(request, [{:provider, fallback.name} | new_opts])
        end
    end
  end

  defp implements_streaming?(module) do
    function_exported?(module, :stream, 2)
  end

  defp implements_embeddings?(module) do
    function_exported?(module, :embed, 2)
  end

  defp handle_provider_error({:error, _} = error, _provider_name), do: error

  defp handle_provider_error(error, provider_name) do
    Logger.error("Provider #{provider_name} error: #{inspect(error)}")
    {:error, :provider_error}
  end

  defp request_timeout(opts) do
    Keyword.get(opts, :timeout, 30_000)
  end
end
