defmodule RubberDuck.Verdict.Providers.ProviderRegistry do
  @moduledoc """
  Provider registry for managing AI evaluation providers.

  This module manages the registration, discovery, and lifecycle of all
  AI providers in the Verdict framework including:
  - Provider registration and capability discovery
  - Health status monitoring and tracking
  - Provider state management and configuration
  - Integration with three-tier configuration system
  """

  use GenServer
  require Logger

  alias RubberDuck.Verdict.Providers.ProviderInterface

  @provider_types [:openai, :anthropic, :ollama, :azure, :vertex]
  # 30 seconds
  @health_check_interval 30_000
  @max_consecutive_failures 3

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new provider with the registry.
  """
  def register_provider(provider_type, module, config) when provider_type in @provider_types do
    GenServer.call(__MODULE__, {:register_provider, provider_type, module, config})
  end

  @doc """
  Get all registered providers with their current status.
  """
  def get_providers do
    GenServer.call(__MODULE__, :get_providers)
  end

  @doc """
  Get provider by type with current health status.
  """
  def get_provider(provider_type) when provider_type in @provider_types do
    GenServer.call(__MODULE__, {:get_provider, provider_type})
  end

  @doc """
  Get healthy providers that can handle the given evaluation requirements.
  """
  def get_available_providers(evaluation_requirements \\ %{}) do
    GenServer.call(__MODULE__, {:get_available_providers, evaluation_requirements})
  end

  @doc """
  Update provider configuration dynamically.
  """
  def update_provider_config(provider_type, new_config) do
    GenServer.call(__MODULE__, {:update_config, provider_type, new_config})
  end

  @doc """
  Mark provider as unhealthy (for manual intervention).
  """
  def mark_provider_unhealthy(provider_type, reason \\ "Manual intervention") do
    GenServer.cast(__MODULE__, {:mark_unhealthy, provider_type, reason})
  end

  @doc """
  Force health check for specific provider.
  """
  def check_provider_health(provider_type) do
    GenServer.call(__MODULE__, {:check_health, provider_type})
  end

  @doc """
  Get provider registry statistics.
  """
  def get_registry_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    # Subscribe to configuration changes
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "verdict_configuration_changes")

    # Schedule periodic health checks
    schedule_health_checks()

    state = %{
      providers: %{},
      health_status: %{},
      failure_counts: %{},
      config_cache: %{},
      stats: %{
        registrations: 0,
        health_checks: 0,
        failures: 0,
        last_registry_update: DateTime.utc_now()
      }
    }

    Logger.info("ProviderRegistry started successfully")
    {:ok, state}
  end

  @impl true
  def handle_call({:register_provider, provider_type, module, config}, _from, state) do
    Logger.info("Registering provider: #{provider_type}")

    case initialize_provider(module, config) do
      {:ok, provider_state} ->
        # Get provider capabilities
        capabilities = get_provider_capabilities(module, provider_state)

        provider_info = %{
          module: module,
          state: provider_state,
          config: config,
          capabilities: capabilities,
          registered_at: DateTime.utc_now(),
          last_health_check: nil,
          consecutive_failures: 0
        }

        updated_providers = Map.put(state.providers, provider_type, provider_info)
        updated_health = Map.put(state.health_status, provider_type, :unknown)
        updated_stats = Map.update!(state.stats, :registrations, &(&1 + 1))

        new_state = %{
          state
          | providers: updated_providers,
            health_status: updated_health,
            stats: updated_stats
        }

        # Schedule immediate health check for new provider
        schedule_provider_health_check(provider_type)

        {:reply, :ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to register provider #{provider_type}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_providers, _from, state) do
    providers_with_health =
      state.providers
      |> Enum.map(fn {type, provider_info} ->
        {type,
         Map.put(provider_info, :health_status, Map.get(state.health_status, type, :unknown))}
      end)
      |> Enum.into(%{})

    {:reply, {:ok, providers_with_health}, state}
  end

  @impl true
  def handle_call({:get_provider, provider_type}, _from, state) do
    case Map.get(state.providers, provider_type) do
      nil ->
        {:reply, {:error, :not_found}, state}

      provider_info ->
        health_status = Map.get(state.health_status, provider_type, :unknown)
        provider_with_health = Map.put(provider_info, :health_status, health_status)
        {:reply, {:ok, provider_with_health}, state}
    end
  end

  @impl true
  def handle_call({:get_available_providers, requirements}, _from, state) do
    available =
      state.providers
      |> Enum.filter(fn {provider_type, provider_info} ->
        health_status = Map.get(state.health_status, provider_type, :unknown)
        meets_requirements?(provider_info, requirements) and health_status == :healthy
      end)
      |> Enum.into(%{})

    {:reply, {:ok, available}, state}
  end

  @impl true
  def handle_call({:update_config, provider_type, new_config}, _from, state) do
    case Map.get(state.providers, provider_type) do
      nil ->
        {:reply, {:error, :not_found}, state}

      provider_info ->
        # Reinitialize provider with new config
        case initialize_provider(provider_info.module, new_config) do
          {:ok, new_provider_state} ->
            updated_provider_info = %{
              provider_info
              | state: new_provider_state,
                config: new_config
            }

            updated_providers = Map.put(state.providers, provider_type, updated_provider_info)

            Logger.info("Updated configuration for provider: #{provider_type}")
            {:reply, :ok, %{state | providers: updated_providers}}

          {:error, reason} ->
            Logger.error("Failed to update provider #{provider_type} config: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:check_health, provider_type}, _from, state) do
    case Map.get(state.providers, provider_type) do
      nil ->
        {:reply, {:error, :not_found}, state}

      provider_info ->
        health_result = perform_health_check(provider_info)
        updated_state = update_provider_health(state, provider_type, health_result)
        {:reply, health_result, updated_state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    enhanced_stats =
      state.stats
      |> Map.put(:healthy_providers, count_healthy_providers(state))
      |> Map.put(:total_providers, map_size(state.providers))
      |> Map.put(:last_health_check, get_last_health_check_time(state))

    {:reply, {:ok, enhanced_stats}, state}
  end

  @impl true
  def handle_cast({:mark_unhealthy, provider_type, reason}, state) do
    Logger.warning("Marking provider #{provider_type} as unhealthy: #{reason}")

    updated_health = Map.put(state.health_status, provider_type, :unhealthy)
    updated_failures = Map.update(state.failure_counts, provider_type, 1, &(&1 + 1))

    new_state = %{state | health_status: updated_health, failure_counts: updated_failures}

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:health_check_cycle, state) do
    Logger.debug("Starting provider health check cycle")

    # Perform health checks for all registered providers
    updated_state =
      Enum.reduce(state.providers, state, fn {provider_type, provider_info}, acc_state ->
        health_result = perform_health_check(provider_info)
        update_provider_health(acc_state, provider_type, health_result)
      end)

    # Schedule next health check cycle
    schedule_health_checks()

    updated_stats = Map.update!(updated_state.stats, :health_checks, &(&1 + 1))
    {:noreply, %{updated_state | stats: updated_stats}}
  end

  @impl true
  def handle_info({:configuration_changed, :provider, provider_type}, state) do
    Logger.info("Provider configuration changed: #{provider_type}")

    # Reload provider configuration
    case Map.get(state.providers, provider_type) do
      nil ->
        {:noreply, state}

      provider_info ->
        # Would reload configuration from three-tier system
        # For now, just invalidate cache
        updated_cache = Map.delete(state.config_cache, provider_type)
        {:noreply, %{state | config_cache: updated_cache}}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # Private implementation

  defp initialize_provider(module, config) do
    try do
      module.initialize(config)
    rescue
      error ->
        {:error, "Provider initialization failed: #{Exception.message(error)}"}
    end
  end

  defp get_provider_capabilities(module, provider_state) do
    try do
      case module.get_capabilities(provider_state) do
        {:ok, capabilities} -> capabilities
        {:error, _} -> %{supports_streaming: false, max_context_tokens: 4096}
      end
    rescue
      _ -> %{supports_streaming: false, max_context_tokens: 4096}
    end
  end

  defp perform_health_check(provider_info) do
    start_time = System.monotonic_time(:millisecond)

    try do
      case provider_info.module.health_check(provider_info.state) do
        {:ok, health_data} ->
          response_time = System.monotonic_time(:millisecond) - start_time
          {:ok, Map.put(health_data, :response_time_ms, response_time)}

        {:error, reason} ->
          response_time = System.monotonic_time(:millisecond) - start_time
          {:error, %{reason: reason, response_time_ms: response_time}}
      end
    rescue
      error ->
        response_time = System.monotonic_time(:millisecond) - start_time

        {:error,
         %{
           reason: Exception.message(error),
           response_time_ms: response_time
         }}
    end
  end

  defp update_provider_health(state, provider_type, health_result) do
    {new_health_status, failure_increment} =
      case health_result do
        {:ok, health_data} ->
          status = Map.get(health_data, :status, :healthy)
          {status, 0}

        {:error, _error_data} ->
          current_failures = Map.get(state.failure_counts, provider_type, 0)

          if current_failures >= @max_consecutive_failures do
            {:unhealthy, 1}
          else
            {:degraded, 1}
          end
      end

    # Update provider info with health check timestamp
    updated_providers =
      case Map.get(state.providers, provider_type) do
        nil ->
          state.providers

        provider_info ->
          updated_info = Map.put(provider_info, :last_health_check, DateTime.utc_now())
          Map.put(state.providers, provider_type, updated_info)
      end

    updated_health = Map.put(state.health_status, provider_type, new_health_status)

    updated_failures =
      Map.update(state.failure_counts, provider_type, failure_increment, fn
        # Reset on recovery
        count when new_health_status == :healthy -> 0
        count -> count + failure_increment
      end)

    # Broadcast health status changes
    if Map.get(state.health_status, provider_type) != new_health_status do
      Phoenix.PubSub.broadcast(
        RubberDuck.PubSub,
        "provider_health_changes",
        {:provider_health_changed, provider_type, new_health_status}
      )
    end

    %{
      state
      | providers: updated_providers,
        health_status: updated_health,
        failure_counts: updated_failures
    }
  end

  defp meets_requirements?(provider_info, requirements) do
    capabilities = provider_info.capabilities

    # Check if provider supports required evaluation type
    evaluation_type_supported =
      case Map.get(requirements, :evaluation_type) do
        nil ->
          true

        type ->
          type in Map.get(capabilities, :evaluation_types, [
            :quality,
            :security,
            :performance,
            :maintainability,
            :style
          ])
      end

    # Check token requirements
    token_requirements_met =
      case Map.get(requirements, :max_tokens) do
        nil -> true
        required_tokens -> required_tokens <= Map.get(capabilities, :max_context_tokens, 4096)
      end

    # Check streaming requirements
    streaming_supported =
      case Map.get(requirements, :streaming) do
        true -> Map.get(capabilities, :supports_streaming, false)
        _ -> true
      end

    evaluation_type_supported and token_requirements_met and streaming_supported
  end

  defp schedule_health_checks do
    Process.send_after(self(), :health_check_cycle, @health_check_interval)
  end

  defp schedule_provider_health_check(provider_type, delay \\ 1000) do
    Process.send_after(self(), {:check_provider_health, provider_type}, delay)
  end

  defp count_healthy_providers(state) do
    state.health_status
    |> Enum.count(fn {_type, status} -> status == :healthy end)
  end

  defp get_last_health_check_time(state) do
    state.providers
    |> Enum.map(fn {_type, provider_info} -> provider_info.last_health_check end)
    |> Enum.filter(&(!is_nil(&1)))
    |> Enum.max(DateTime, fn -> nil end)
  end

  # Configuration integration

  def load_provider_configurations do
    # This would integrate with the three-tier configuration system
    # For now, return default configurations
    %{
      openai: %{
        enabled: true,
        api_key: System.get_env("OPENAI_API_KEY"),
        models: %{
          screening: "gpt-4o-mini",
          detailed: "gpt-4o"
        },
        rate_limits: %{
          requests_per_minute: 500,
          tokens_per_minute: 10_000
        }
      },
      anthropic: %{
        enabled: true,
        api_key: System.get_env("ANTHROPIC_API_KEY"),
        models: %{
          screening: "claude-3-haiku-20240307",
          detailed: "claude-3-5-sonnet-20241022"
        },
        rate_limits: %{
          requests_per_minute: 100,
          tokens_per_minute: 40_000
        }
      },
      ollama: %{
        enabled: true,
        endpoint: "http://localhost:11434",
        models: %{
          screening: "llama3.2:3b",
          detailed: "llama3.1:8b"
        },
        rate_limits: %{
          # Local models have higher limits
          requests_per_minute: 1000,
          concurrent_requests: 4
        }
      }
    }
  end

  def validate_provider_config(provider_type, config) do
    case provider_type do
      :openai -> validate_openai_config(config)
      :anthropic -> validate_anthropic_config(config)
      :ollama -> validate_ollama_config(config)
      _ -> {:error, "Unknown provider type"}
    end
  end

  defp validate_openai_config(config) do
    required_fields = [:api_key, :models]
    missing = Enum.filter(required_fields, &(!Map.has_key?(config, &1)))

    case missing do
      [] -> validate_openai_models(config)
      fields -> {:error, "Missing OpenAI config fields: #{inspect(fields)}"}
    end
  end

  defp validate_anthropic_config(config) do
    required_fields = [:api_key, :models]
    missing = Enum.filter(required_fields, &(!Map.has_key?(config, &1)))

    case missing do
      [] -> validate_anthropic_models(config)
      fields -> {:error, "Missing Anthropic config fields: #{inspect(fields)}"}
    end
  end

  defp validate_ollama_config(config) do
    required_fields = [:endpoint, :models]
    missing = Enum.filter(required_fields, &(!Map.has_key?(config, &1)))

    case missing do
      [] -> validate_ollama_models(config)
      fields -> {:error, "Missing Ollama config fields: #{inspect(fields)}"}
    end
  end

  defp validate_openai_models(config) do
    models = Map.get(config, :models, %{})
    valid_models = ["gpt-4o", "gpt-4o-mini", "gpt-3.5-turbo"]

    invalid_models =
      models
      |> Map.values()
      |> Enum.filter(&(&1 not in valid_models))

    case invalid_models do
      [] -> :ok
      invalid -> {:error, "Invalid OpenAI models: #{inspect(invalid)}"}
    end
  end

  defp validate_anthropic_models(config) do
    models = Map.get(config, :models, %{})

    valid_models = [
      "claude-3-5-sonnet-20241022",
      "claude-3-haiku-20240307",
      "claude-3-opus-20240229"
    ]

    invalid_models =
      models
      |> Map.values()
      |> Enum.filter(&(&1 not in valid_models))

    case invalid_models do
      [] -> :ok
      invalid -> {:error, "Invalid Anthropic models: #{inspect(invalid)}"}
    end
  end

  defp validate_ollama_models(config) do
    models = Map.get(config, :models, %{})
    # Ollama models are more flexible, just validate format
    invalid_models =
      models
      |> Map.values()
      |> Enum.filter(fn model ->
        not is_binary(model) or String.length(model) == 0
      end)

    case invalid_models do
      [] -> :ok
      _ -> {:error, "Invalid Ollama model specifications"}
    end
  end

  # Provider lifecycle management

  def auto_register_providers do
    configs = load_provider_configurations()

    Enum.each(configs, fn {provider_type, config} ->
      if Map.get(config, :enabled, false) do
        register_single_provider(provider_type, config)
      end
    end)
  end

  defp register_single_provider(provider_type, config) do
    provider_module = get_provider_module(provider_type)

    case register_provider(provider_type, provider_module, config) do
      :ok ->
        Logger.info("Auto-registered provider: #{provider_type}")

      {:error, reason} ->
        Logger.warning("Failed to auto-register #{provider_type}: #{inspect(reason)}")
    end
  end

  defp get_provider_module(provider_type) do
    case provider_type do
      :openai -> RubberDuck.Verdict.Providers.OpenAI.OpenAIProvider
      :anthropic -> RubberDuck.Verdict.Providers.Anthropic.AnthropicProvider
      :ollama -> RubberDuck.Verdict.Providers.Ollama.OllamaProvider
      _ -> nil
    end
  end

  def shutdown_all_providers do
    GenServer.call(__MODULE__, :shutdown_all)
  end

  @impl true
  def handle_call(:shutdown_all, _from, state) do
    Logger.info("Shutting down all providers...")

    Enum.each(state.providers, fn {provider_type, provider_info} ->
      try do
        provider_info.module.terminate(provider_info.state)
        Logger.debug("Shut down provider: #{provider_type}")
      rescue
        error ->
          Logger.error(
            "Error shutting down provider #{provider_type}: #{Exception.message(error)}"
          )
      end
    end)

    {:reply, :ok, %{state | providers: %{}, health_status: %{}}}
  end
end
