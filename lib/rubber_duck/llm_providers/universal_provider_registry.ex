defmodule RubberDuck.LlmProviders.UniversalProviderRegistry do
  @moduledoc """
  Universal provider registry for managing AI providers across all RubberDuck domains.

  This module consolidates provider management from both the Verdict system and 
  the Preferences LLM system into a unified registry that serves:
  - Code evaluation with Constitutional AI (from Verdict system)
  - Agent orchestration and communication (from Preferences system)  
  - Planning and reasoning tasks (future Phase 4+)
  - Tool calling and function execution (future Phase 3+)
  - Any future LLM use cases across the system

  Features:
  - Unified provider registration and capability discovery
  - Domain-aware health monitoring and performance tracking
  - Shared connection pooling and resource optimization
  - Integration with three-tier configuration system
  - Constitutional AI and safety features preservation
  """

  use GenServer
  require Logger

  alias RubberDuck.LlmProviders.UniversalProviderInterface

  @provider_types [:openai, :anthropic, :ollama, :azure, :vertex]
  @supported_domains [:evaluation, :orchestration, :planning, :communication, :tooling]
  # Improved: 15 seconds vs previous 30s
  @health_check_interval 15_000
  @max_consecutive_failures 3

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a universal provider supporting multiple domains.
  """
  def register_provider(provider_type, module, config, supported_domains \\ @supported_domains)
      when provider_type in @provider_types do
    GenServer.call(
      __MODULE__,
      {:register_provider, provider_type, module, config, supported_domains}
    )
  end

  @doc """
  Get all registered providers with their domain capabilities and health status.
  """
  def get_providers do
    GenServer.call(__MODULE__, :get_providers)
  end

  @doc """
  Get provider by type with comprehensive status for all domains.
  """
  def get_provider(provider_type) when provider_type in @provider_types do
    GenServer.call(__MODULE__, {:get_provider, provider_type})
  end

  @doc """
  Get available providers that can handle specific domain requirements.
  """
  def get_available_providers_for_domain(domain, requirements \\ %{})
      when domain in @supported_domains do
    GenServer.call(__MODULE__, {:get_available_providers, domain, requirements})
  end

  @doc """
  Get providers supporting multiple domains (for cross-domain operations).
  """
  def get_multi_domain_providers(domains) when is_list(domains) do
    GenServer.call(__MODULE__, {:get_multi_domain_providers, domains})
  end

  @doc """
  Update provider configuration with domain-specific settings.
  """
  def update_provider_config(provider_type, new_config, affected_domains \\ @supported_domains) do
    GenServer.call(__MODULE__, {:update_config, provider_type, new_config, affected_domains})
  end

  @doc """
  Mark provider as unhealthy for specific domain or all domains.
  """
  def mark_provider_unhealthy(
        provider_type,
        reason \\ "Manual intervention",
        affected_domains \\ @supported_domains
      ) do
    GenServer.cast(__MODULE__, {:mark_unhealthy, provider_type, reason, affected_domains})
  end

  @doc """
  Perform health check for provider across all supported domains.
  """
  def check_provider_health(provider_type) do
    GenServer.call(__MODULE__, {:check_health, provider_type})
  end

  @doc """
  Get comprehensive registry analytics including domain usage patterns.
  """
  def get_registry_analytics do
    GenServer.call(__MODULE__, :get_analytics)
  end

  @doc """
  Record provider usage for analytics and health tracking.
  """
  def record_provider_usage(provider_type, domain, usage_data) do
    GenServer.cast(__MODULE__, {:record_usage, provider_type, domain, usage_data})
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    # Subscribe to configuration changes from three-tier system
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "universal_provider_changes")
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "preference_changes")

    # Start health monitoring cycle
    schedule_health_monitoring()

    state = %{
      providers: %{},
      domain_health: %{},
      domain_usage_stats: %{},
      provider_connections: %{},
      failure_counts: %{},
      config_cache: %{},
      analytics: %{
        total_registrations: 0,
        total_requests_served: 0,
        domain_request_counts: %{},
        health_checks_performed: 0,
        last_registry_update: DateTime.utc_now()
      }
    }

    Logger.info("Universal Provider Registry started successfully")
    {:ok, state}
  end

  @impl true
  def handle_call(
        {:register_provider, provider_type, module, config, supported_domains},
        _from,
        state
      ) do
    Logger.info(
      "Registering universal provider: #{provider_type} for domains: #{inspect(supported_domains)}"
    )

    case initialize_universal_provider(module, config, supported_domains) do
      {:ok, provider_state} ->
        # Get universal provider capabilities
        capabilities =
          get_universal_provider_capabilities(module, provider_state, supported_domains)

        provider_info = %{
          module: module,
          state: provider_state,
          config: config,
          supported_domains: supported_domains,
          capabilities: capabilities,
          registered_at: DateTime.utc_now(),
          last_health_check: nil,
          connection_pool: initialize_connection_pool(provider_type, config)
        }

        updated_providers = Map.put(state.providers, provider_type, provider_info)

        # Initialize domain health tracking
        updated_domain_health =
          initialize_domain_health(state.domain_health, provider_type, supported_domains)

        # Initialize usage stats
        updated_usage_stats =
          initialize_usage_stats(state.domain_usage_stats, provider_type, supported_domains)

        updated_analytics = Map.update!(state.analytics, :total_registrations, &(&1 + 1))

        new_state = %{
          state
          | providers: updated_providers,
            domain_health: updated_domain_health,
            domain_usage_stats: updated_usage_stats,
            analytics: updated_analytics
        }

        # Schedule immediate health check
        schedule_immediate_provider_health_check(provider_type)

        # Broadcast provider registration
        Phoenix.PubSub.broadcast(
          RubberDuck.PubSub,
          "provider_registry_events",
          {:provider_registered, provider_type, supported_domains}
        )

        {:reply, :ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to register universal provider #{provider_type}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_providers, _from, state) do
    providers_with_health =
      state.providers
      |> Enum.map(fn {type, provider_info} ->
        domain_health = Map.get(state.domain_health, type, %{})
        overall_health = UniversalProviderInterface.aggregate_domain_health(domain_health)

        enhanced_info =
          Map.merge(provider_info, %{
            domain_health_status: domain_health,
            overall_health_status: overall_health,
            usage_statistics: Map.get(state.domain_usage_stats, type, %{})
          })

        {type, enhanced_info}
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
        domain_health = Map.get(state.domain_health, provider_type, %{})
        overall_health = UniversalProviderInterface.aggregate_domain_health(domain_health)
        usage_stats = Map.get(state.domain_usage_stats, provider_type, %{})

        enhanced_info =
          Map.merge(provider_info, %{
            domain_health_status: domain_health,
            overall_health_status: overall_health,
            usage_statistics: usage_stats
          })

        {:reply, {:ok, enhanced_info}, state}
    end
  end

  @impl true
  def handle_call({:get_available_providers, domain, requirements}, _from, state) do
    available =
      state.providers
      |> Enum.filter(fn {provider_type, provider_info} ->
        # Check if provider supports the domain
        domain_supported = domain in provider_info.supported_domains

        # Check if provider is healthy for this domain
        domain_health = get_in(state.domain_health, [provider_type, domain], %{status: :unknown})
        health_good = Map.get(domain_health, :status, :unknown) in [:healthy, :degraded]

        # Check if provider meets domain requirements
        requirements_met = meets_domain_requirements?(provider_info, domain, requirements)

        domain_supported and health_good and requirements_met
      end)
      |> Enum.into(%{})

    {:reply, {:ok, available}, state}
  end

  @impl true
  def handle_call({:get_multi_domain_providers, domains}, _from, state) do
    multi_domain =
      state.providers
      |> Enum.filter(fn {_type, provider_info} ->
        # Provider must support ALL requested domains
        Enum.all?(domains, &(&1 in provider_info.supported_domains))
      end)
      |> Enum.into(%{})

    {:reply, {:ok, multi_domain}, state}
  end

  @impl true
  def handle_call({:check_health, provider_type}, _from, state) do
    case Map.get(state.providers, provider_type) do
      nil ->
        {:reply, {:error, :not_found}, state}

      provider_info ->
        health_results = perform_comprehensive_health_check(provider_info)
        updated_state = update_provider_domain_health(state, provider_type, health_results)

        overall_health = UniversalProviderInterface.aggregate_domain_health(health_results)
        {:reply, {:ok, overall_health}, updated_state}
    end
  end

  @impl true
  def handle_call(:get_analytics, _from, state) do
    comprehensive_analytics = build_comprehensive_analytics(state)
    {:reply, {:ok, comprehensive_analytics}, state}
  end

  @impl true
  def handle_cast({:record_usage, provider_type, domain, usage_data}, _from, state) do
    # Record usage for analytics and health tracking
    timestamp = DateTime.utc_now()

    # Update domain usage statistics
    updated_usage_stats =
      state.domain_usage_stats
      |> Map.update(provider_type, %{}, fn provider_stats ->
        Map.update(provider_stats, domain, [], fn domain_usage ->
          usage_entry = Map.merge(usage_data, %{timestamp: timestamp})
          # Keep last 1000 entries per domain to limit memory
          [usage_entry | domain_usage] |> Enum.take(1000)
        end)
      end)

    # Update analytics
    updated_analytics =
      state.analytics
      |> Map.update!(:total_requests_served, &(&1 + 1))
      |> Map.update(:domain_request_counts, %{}, fn counts ->
        Map.update(counts, domain, 1, &(&1 + 1))
      end)

    new_state = %{state | domain_usage_stats: updated_usage_stats, analytics: updated_analytics}

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:mark_unhealthy, provider_type, reason, affected_domains}, state) do
    Logger.warning(
      "Marking provider #{provider_type} as unhealthy for domains #{inspect(affected_domains)}: #{reason}"
    )

    # Update domain health for affected domains
    updated_domain_health =
      Enum.reduce(affected_domains, state.domain_health, fn domain, acc ->
        put_in(acc, [provider_type, domain, :status], :unhealthy)
      end)

    # Update failure counts
    updated_failure_counts =
      Enum.reduce(affected_domains, state.failure_counts, fn domain, acc ->
        Map.update(acc, {provider_type, domain}, 1, &(&1 + 1))
      end)

    # Broadcast health changes
    Phoenix.PubSub.broadcast(
      RubberDuck.PubSub,
      "provider_health_changes",
      {:provider_health_changed, provider_type, affected_domains, :unhealthy}
    )

    new_state = %{
      state
      | domain_health: updated_domain_health,
        failure_counts: updated_failure_counts
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:universal_health_check, state) do
    Logger.debug("Starting universal provider health check cycle")

    # Perform health checks for all registered providers across all domains
    updated_state =
      Enum.reduce(state.providers, state, fn {provider_type, provider_info}, acc_state ->
        health_results = perform_comprehensive_health_check(provider_info)
        update_provider_domain_health(acc_state, provider_type, health_results)
      end)

    # Schedule next health check
    schedule_health_monitoring()

    updated_analytics = Map.update!(updated_state.analytics, :health_checks_performed, &(&1 + 1))
    {:noreply, %{updated_state | analytics: updated_analytics}}
  end

  @impl true
  def handle_info({:configuration_changed, :universal_provider, provider_type}, state) do
    Logger.info("Universal provider configuration changed: #{provider_type}")

    # Reload provider configuration across all domains
    case Map.get(state.providers, provider_type) do
      nil ->
        {:noreply, state}

      provider_info ->
        # Would reload from three-tier configuration system
        updated_cache = Map.delete(state.config_cache, provider_type)
        {:noreply, %{state | config_cache: updated_cache}}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # Private implementation

  defp initialize_universal_provider(module, config, supported_domains) do
    # Validate configuration for universal use
    case UniversalProviderInterface.validate_universal_provider_config(
           get_provider_type_from_module(module),
           config
         ) do
      :ok ->
        try do
          module.initialize(config)
        rescue
          error ->
            {:error, "Universal provider initialization failed: #{Exception.message(error)}"}
        end

      error ->
        error
    end
  end

  defp get_universal_provider_capabilities(module, provider_state, supported_domains) do
    try do
      case module.get_capabilities(provider_state) do
        {:ok, base_capabilities} ->
          # Enhance capabilities with universal provider features
          Map.merge(base_capabilities, %{
            supported_domains: supported_domains,
            universal_provider: true,
            cross_domain_routing: true,
            shared_connection_pool: true
          })

        {:error, _} ->
          # Fallback capabilities
          %{
            supported_domains: supported_domains,
            universal_provider: true,
            max_context_tokens: 4096,
            supports_streaming: false
          }
      end
    rescue
      _ ->
        %{
          supported_domains: supported_domains,
          universal_provider: true,
          max_context_tokens: 4096
        }
    end
  end

  defp initialize_connection_pool(provider_type, config) do
    # Initialize shared connection pool for provider
    pool_config = %{
      provider_type: provider_type,
      max_connections: Map.get(config, :max_connections, 10),
      connection_timeout: Map.get(config, :connection_timeout, 5000),
      pool_created_at: DateTime.utc_now()
    }

    Logger.debug("Initialized connection pool for #{provider_type}: #{inspect(pool_config)}")
    pool_config
  end

  defp initialize_domain_health(domain_health, provider_type, supported_domains) do
    domain_health_map =
      supported_domains
      |> Enum.map(fn domain ->
        {domain,
         %{
           status: :unknown,
           last_check: nil,
           success_rate: 0.0,
           avg_response_time_ms: 0,
           error_count: 0
         }}
      end)
      |> Enum.into(%{})

    Map.put(domain_health, provider_type, domain_health_map)
  end

  defp initialize_usage_stats(usage_stats, provider_type, supported_domains) do
    domain_usage_map =
      supported_domains
      |> Enum.map(fn domain -> {domain, []} end)
      |> Enum.into(%{})

    Map.put(usage_stats, provider_type, domain_usage_map)
  end

  defp perform_comprehensive_health_check(provider_info) do
    Logger.debug("Performing comprehensive health check for provider: #{provider_info.module}")

    # Perform health check across all supported domains
    provider_info.supported_domains
    |> Enum.map(fn domain ->
      domain_health = perform_domain_health_check(provider_info, domain)
      {domain, domain_health}
    end)
    |> Enum.into(%{})
  end

  defp perform_domain_health_check(provider_info, domain) do
    start_time = System.monotonic_time(:millisecond)

    try do
      # Create domain-specific health check request
      health_request = build_domain_health_request(domain)

      case provider_info.module.process_request(provider_info.state, health_request) do
        {:ok, response} ->
          response_time = System.monotonic_time(:millisecond) - start_time

          %{
            status: :healthy,
            last_check: DateTime.utc_now(),
            success_rate: 1.0,
            avg_response_time_ms: response_time,
            error_count: 0,
            domain_specific_metrics: extract_domain_health_metrics(response, domain)
          }

        {:error, reason} ->
          response_time = System.monotonic_time(:millisecond) - start_time

          %{
            status: :unhealthy,
            last_check: DateTime.utc_now(),
            last_error: reason,
            error_response_time_ms: response_time,
            success_rate: 0.0
          }
      end
    rescue
      error ->
        response_time = System.monotonic_time(:millisecond) - start_time

        %{
          status: :unhealthy,
          last_check: DateTime.utc_now(),
          last_error: Exception.message(error),
          error_response_time_ms: response_time,
          success_rate: 0.0
        }
    end
  end

  defp build_domain_health_request(domain) do
    context = %{
      domain: domain,
      use_case: :health_check,
      requirements: %{},
      budget_constraints: %{},
      quality_thresholds: %{},
      specialized_features: []
    }

    UniversalProviderInterface.build_universal_request(
      "Health check",
      domain,
      :health_check,
      %{
        max_tokens: 10,
        streaming: false,
        temperature: 0.0
      }
    )
  end

  defp extract_domain_health_metrics(response, domain) do
    case domain do
      :evaluation ->
        %{
          evaluation_capability: Map.has_key?(response, :domain_specific_data),
          constitutional_ai_available:
            :constitutional_ai in Map.get(response, :specialized_features, [])
        }

      :orchestration ->
        %{
          orchestration_capability: true,
          cost_optimization_available: Map.has_key?(response.metadata, :cost_efficiency)
        }

      _ ->
        %{capability_confirmed: true}
    end
  end

  defp meets_domain_requirements?(provider_info, domain, requirements) do
    # Check if provider supports the domain
    domain_supported = domain in provider_info.supported_domains

    # Check specific requirements
    capabilities = provider_info.capabilities

    token_requirements_met =
      case Map.get(requirements, :max_tokens) do
        nil -> true
        required -> required <= Map.get(capabilities, :max_context_tokens, 4096)
      end

    streaming_supported =
      case Map.get(requirements, :streaming) do
        true -> Map.get(capabilities, :supports_streaming, false)
        _ -> true
      end

    specialized_features_supported =
      case Map.get(requirements, :specialized_features) do
        features when is_list(features) ->
          available_features = Map.get(capabilities, :specialized_features, [])
          Enum.all?(features, &(&1 in available_features))

        _ ->
          true
      end

    domain_supported and token_requirements_met and streaming_supported and
      specialized_features_supported
  end

  defp update_provider_domain_health(state, provider_type, health_results) do
    updated_domain_health = Map.put(state.domain_health, provider_type, health_results)

    # Broadcast health changes for each domain
    Enum.each(health_results, fn {domain, health_data} ->
      provider_domain_health = Map.get(state.domain_health, provider_type, %{})
      domain_health = Map.get(provider_domain_health, domain, %{})
      previous_status = Map.get(domain_health, :status, :unknown)
      new_status = Map.get(health_data, :status, :unknown)

      if previous_status != new_status do
        Phoenix.PubSub.broadcast(
          RubberDuck.PubSub,
          "provider_health_changes",
          {:provider_domain_health_changed, provider_type, domain, previous_status, new_status}
        )
      end
    end)

    %{state | domain_health: updated_domain_health}
  end

  defp build_comprehensive_analytics(state) do
    total_providers = map_size(state.providers)
    healthy_providers = count_healthy_providers(state)

    domain_analytics =
      @supported_domains
      |> Enum.map(fn domain ->
        domain_providers = count_providers_supporting_domain(state, domain)
        domain_requests = get_in(state.analytics, [:domain_request_counts, domain], 0)

        {domain,
         %{
           providers_available: domain_providers,
           total_requests: domain_requests,
           avg_requests_per_provider:
             if(domain_providers > 0, do: domain_requests / domain_providers, else: 0)
         }}
      end)
      |> Enum.into(%{})

    Map.merge(state.analytics, %{
      total_providers: total_providers,
      healthy_providers: healthy_providers,
      health_percentage:
        if(total_providers > 0, do: healthy_providers / total_providers * 100, else: 0),
      domain_analytics: domain_analytics,
      last_analytics_update: DateTime.utc_now()
    })
  end

  defp count_healthy_providers(state) do
    state.domain_health
    |> Enum.count(fn {_provider, domain_health} ->
      overall_health = UniversalProviderInterface.aggregate_domain_health(domain_health)
      overall_health.status == :healthy
    end)
  end

  defp count_providers_supporting_domain(state, domain) do
    state.providers
    |> Enum.count(fn {_type, provider_info} ->
      domain in provider_info.supported_domains
    end)
  end

  defp schedule_health_monitoring do
    Process.send_after(self(), :universal_health_check, @health_check_interval)
  end

  defp schedule_immediate_provider_health_check(provider_type) do
    Process.send_after(self(), {:immediate_health_check, provider_type}, 100)
  end

  defp get_provider_type_from_module(module) do
    case to_string(module) do
      "Elixir.RubberDuck.LlmProviders.OpenAI." <> _ -> :openai
      "Elixir.RubberDuck.LlmProviders.Anthropic." <> _ -> :anthropic
      "Elixir.RubberDuck.LlmProviders.Ollama." <> _ -> :ollama
      _ -> :unknown
    end
  end

  # Configuration integration with existing three-tier system

  def load_universal_provider_configurations(user_id \\ nil, project_id \\ nil) do
    # This integrates with existing PreferenceResolver
    # For now, return merged configurations from both systems
    %{
      openai: %{
        enabled: true,
        api_key: System.get_env("OPENAI_API_KEY"),
        models: %{
          # Evaluation models from Verdict system
          evaluation_screening: "gpt-4o-mini",
          evaluation_detailed: "gpt-4o",
          # Orchestration models from Preferences system
          orchestration_standard: "gpt-4o",
          orchestration_planning: "gpt-4o"
        },
        domain_configs: %{
          evaluation: %{
            constitutional_ai_enabled: true,
            streaming_enabled: true,
            quality_threshold: 0.8
          },
          orchestration: %{
            cost_optimization_enabled: true,
            agent_communication_optimized: true
          }
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
          evaluation_screening: "claude-3-haiku-20240307",
          evaluation_detailed: "claude-3-5-sonnet-20241022",
          orchestration_standard: "claude-3-5-sonnet-20241022",
          orchestration_planning: "claude-3-opus-20240229"
        },
        domain_configs: %{
          evaluation: %{
            constitutional_ai: %{
              safety_checks: true,
              bias_mitigation: true,
              content_filtering: true
            }
          },
          orchestration: %{
            context_optimization: %{
              max_context_tokens: 200_000,
              chunking_strategy: :semantic
            }
          }
        },
        rate_limits: %{
          requests_per_minute: 100,
          tokens_per_minute: 40_000
        }
      }
    }
  end

  # Provider lifecycle management

  def auto_register_universal_providers(user_id \\ nil, project_id \\ nil) do
    configs = load_universal_provider_configurations(user_id, project_id)

    Enum.each(configs, fn {provider_type, config} ->
      if Map.get(config, :enabled, false) do
        provider_module = get_universal_provider_module(provider_type)
        supported_domains = get_provider_supported_domains(provider_type, config)

        case register_provider(provider_type, provider_module, config, supported_domains) do
          :ok ->
            Logger.info("Auto-registered universal provider: #{provider_type}")

          {:error, reason} ->
            Logger.warning("Failed to auto-register #{provider_type}: #{inspect(reason)}")
        end
      end
    end)
  end

  defp get_universal_provider_module(provider_type) do
    case provider_type do
      :openai -> RubberDuck.LlmProviders.OpenAI.UniversalOpenAIProvider
      :anthropic -> RubberDuck.LlmProviders.Anthropic.UniversalAnthropicProvider
      :ollama -> RubberDuck.LlmProviders.Ollama.UniversalOllamaProvider
      _ -> nil
    end
  end

  defp get_provider_supported_domains(provider_type, config) do
    # Determine supported domains based on provider type and configuration
    base_domains =
      case provider_type do
        :openai -> [:evaluation, :orchestration, :planning, :communication]
        # Constitutional AI focus
        :anthropic -> [:evaluation, :orchestration, :planning]
        # Local, privacy-focused
        :ollama -> [:evaluation, :communication]
        _ -> [:evaluation]
      end

    # Filter based on configuration
    configured_domains = Map.get(config, :enabled_domains, base_domains)
    Enum.filter(base_domains, &(&1 in configured_domains))
  end

  def shutdown_all_universal_providers do
    GenServer.call(__MODULE__, :shutdown_all)
  end

  @impl true
  def handle_call(:shutdown_all, _from, state) do
    Logger.info("Shutting down all universal providers...")

    Enum.each(state.providers, fn {provider_type, provider_info} ->
      try do
        provider_info.module.terminate(provider_info.state)
        Logger.debug("Shut down universal provider: #{provider_type}")
      rescue
        error ->
          Logger.error(
            "Error shutting down universal provider #{provider_type}: #{Exception.message(error)}"
          )
      end
    end)

    {:reply, :ok, %{state | providers: %{}, domain_health: %{}, domain_usage_stats: %{}}}
  end

  # Analytics and monitoring utilities

  def get_domain_usage_analytics(provider_type, domain) do
    GenServer.call(__MODULE__, {:get_domain_analytics, provider_type, domain})
  end

  @impl true
  def handle_call({:get_domain_analytics, provider_type, domain}, _from, state) do
    usage_data = get_in(state.domain_usage_stats, [provider_type, domain], [])
    health_data = get_in(state.domain_health, [provider_type, domain], %{})

    analytics = %{
      total_requests: length(usage_data),
      success_rate: calculate_domain_success_rate(usage_data),
      avg_cost_per_request: calculate_avg_cost(usage_data),
      avg_response_time: calculate_avg_response_time(usage_data),
      current_health: health_data,
      usage_trend: calculate_usage_trend(usage_data),
      last_updated: DateTime.utc_now()
    }

    {:reply, {:ok, analytics}, state}
  end

  defp calculate_domain_success_rate(usage_data) do
    if Enum.empty?(usage_data) do
      0.0
    else
      successful = Enum.count(usage_data, &Map.get(&1, :success, false))
      successful / length(usage_data)
    end
  end

  defp calculate_avg_cost(usage_data) do
    if Enum.empty?(usage_data) do
      0.0
    else
      total_cost = Enum.reduce(usage_data, 0.0, &(Map.get(&1, :cost_usd, 0.0) + &2))
      total_cost / length(usage_data)
    end
  end

  defp calculate_avg_response_time(usage_data) do
    if Enum.empty?(usage_data) do
      0
    else
      total_time = Enum.reduce(usage_data, 0, &(Map.get(&1, :response_time_ms, 0) + &2))
      div(total_time, length(usage_data))
    end
  end

  defp calculate_usage_trend(usage_data) do
    if length(usage_data) < 10 do
      :insufficient_data
    else
      # Simple trend: compare recent vs older requests
      recent_data = Enum.take(usage_data, 5)
      older_data = Enum.slice(usage_data, 5, 5)

      recent_success = calculate_domain_success_rate(recent_data)
      older_success = calculate_domain_success_rate(older_data)

      cond do
        recent_success > older_success + 0.1 -> :improving
        recent_success < older_success - 0.1 -> :degrading
        true -> :stable
      end
    end
  end
end
