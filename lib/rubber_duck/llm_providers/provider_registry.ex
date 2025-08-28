defmodule RubberDuck.LlmProviders.ProviderRegistry do
  @moduledoc """
  Clean universal provider registry for managing AI providers across all domains.

  This registry consolidates provider management while maintaining simplicity and reliability.
  """

  use GenServer
  require Logger

  @provider_types [:openai, :anthropic, :ollama]
  @supported_domains [:evaluation, :orchestration, :planning, :communication]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a provider for specific domains.
  """
  def register_provider(provider_type, module, config, supported_domains \\ @supported_domains)
      when provider_type in @provider_types do
    GenServer.call(
      __MODULE__,
      {:register_provider, provider_type, module, config, supported_domains}
    )
  end

  @doc """
  Get all registered providers.
  """
  def get_providers do
    GenServer.call(__MODULE__, :get_providers)
  end

  @doc """
  Get provider by type.
  """
  def get_provider(provider_type) when provider_type in @provider_types do
    GenServer.call(__MODULE__, {:get_provider, provider_type})
  end

  @doc """
  Get providers supporting specific domain.
  """
  def get_providers_for_domain(domain) when domain in @supported_domains do
    GenServer.call(__MODULE__, {:get_providers_for_domain, domain})
  end

  # GenServer implementation

  @impl true
  def init(_opts) do
    state = %{
      providers: %{},
      domain_mappings: %{}
    }

    Logger.info("Universal Provider Registry started")
    {:ok, state}
  end

  @impl true
  def handle_call(
        {:register_provider, provider_type, module, config, supported_domains},
        _from,
        state
      ) do
    Logger.info(
      "Registering provider: #{provider_type} for domains: #{inspect(supported_domains)}"
    )

    provider_info = %{
      module: module,
      config: config,
      supported_domains: supported_domains,
      registered_at: DateTime.utc_now()
    }

    updated_providers = Map.put(state.providers, provider_type, provider_info)

    # Update domain mappings
    updated_domain_mappings =
      Enum.reduce(supported_domains, state.domain_mappings, fn domain, acc ->
        current_providers = Map.get(acc, domain, [])
        Map.put(acc, domain, [provider_type | current_providers] |> Enum.uniq())
      end)

    new_state = %{state | providers: updated_providers, domain_mappings: updated_domain_mappings}

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_providers, _from, state) do
    {:reply, {:ok, state.providers}, state}
  end

  @impl true
  def handle_call({:get_provider, provider_type}, _from, state) do
    case Map.get(state.providers, provider_type) do
      nil -> {:reply, {:error, :not_found}, state}
      provider_info -> {:reply, {:ok, provider_info}, state}
    end
  end

  @impl true
  def handle_call({:get_providers_for_domain, domain}, _from, state) do
    provider_types = Map.get(state.domain_mappings, domain, [])

    providers =
      provider_types
      |> Enum.map(fn type -> {type, Map.get(state.providers, type)} end)
      |> Enum.filter(fn {_type, provider_info} -> not is_nil(provider_info) end)
      |> Enum.into(%{})

    {:reply, {:ok, providers}, state}
  end
end
