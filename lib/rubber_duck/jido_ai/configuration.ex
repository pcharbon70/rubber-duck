defmodule RubberDuck.JidoAI.Configuration do
  @moduledoc """
  JidoAI configuration for RubberDuck - The unified LLM system.
  
  Provides configuration management for JidoAI provider integration,
  keyring setup, and agent LLM interface standardization. This replaces
  all legacy LLM systems and is the only LLM configuration system for
  RubberDuck, using JidoAI.Keyring for all provider management.
  """

  require Logger

  @doc """
  Initialize JidoAI configuration with provider setup and keyring integration.
  """
  def initialize_jido_ai_config do
    Logger.info("Initializing JidoAI configuration for RubberDuck")

    with :ok <- setup_provider_configurations(),
         :ok <- configure_keyring_integration(),
         :ok <- setup_session_management(),
         :ok <- initialize_provider_health_monitoring() do
      Logger.info("JidoAI configuration initialized successfully")
      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to initialize JidoAI configuration: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Configure JidoAI providers with hierarchical configuration support.
  """
  def setup_provider_configurations do
    Logger.debug("Setting up JidoAI provider configurations")

    providers = [
      {:openai, setup_openai_provider()},
      {:anthropic, setup_anthropic_provider()},
      {:google, setup_google_provider()},
      {:openrouter, setup_openrouter_provider()},
      {:cloudflare, setup_cloudflare_provider()}
    ]

    Enum.each(providers, fn {provider_name, config} ->
      case config do
        {:ok, provider_config} ->
          configure_provider_in_keyring(provider_name, provider_config)

        {:error, reason} ->
          Logger.warning("Failed to configure #{provider_name}: #{inspect(reason)}")
      end
    end)

    :ok
  end

  @doc """
  Integrate JidoAI.Keyring with existing RubberDuck configuration system.
  """
  def configure_keyring_integration do
    Logger.debug("Configuring JidoAI.Keyring integration")

    # Set up hierarchical configuration resolution
    keyring_config = %{
      # Session values (highest priority)
      session_management: %{
        enabled: true,
        timeout: 3600,
        cleanup_interval: 300
      },

      # Environment variable patterns
      environment_patterns: %{
        openai_api_key: "OPENAI_API_KEY",
        anthropic_api_key: "ANTHROPIC_API_KEY",
        google_api_key: "GOOGLE_API_KEY",
        openrouter_api_key: "OPENROUTER_API_KEY",
        cloudflare_api_key: "CLOUDFLARE_API_KEY"
      },

      # Application environment integration
      app_env_integration: %{
        namespace: :rubber_duck,
        provider_configs_key: :jido_ai_providers,
        fallback_configs_key: :llm_providers
      },

      # Default values
      defaults: %{
        timeout: 30_000,
        max_retries: 3,
        request_timeout: 60_000,
        health_check_interval: 30_000
      }
    }

    # Configure keyring with integration settings
    configure_keyring_with_settings(keyring_config)
  end

  @doc """
  Set up session management for per-agent configuration overrides.
  """
  def setup_session_management do
    Logger.debug("Setting up JidoAI session management")

    # Session configuration patterns for agent-specific overrides
    session_config = %{
      agent_session_patterns: %{
        llm_orchestrator: %{
          provider_preferences: [:anthropic, :openai],
          quality_threshold: 0.8,
          cost_sensitivity: :medium
        },
        rag_orchestrator: %{
          embedding_providers: [:openai, :google],
          chunk_size: 1000,
          overlap: 200
        },
        prompt_composer: %{
          template_engine: :eex,
          variable_validation: :strict,
          security_level: :high
        }
      },
      
      user_session_patterns: %{
        provider_overrides: %{
          enabled: true,
          scope: [:project, :global],
          validation: :required
        },
        budget_overrides: %{
          enabled: true,
          max_override_percentage: 20,
          requires_approval: true
        }
      },

      project_session_patterns: %{
        team_preferences: %{
          provider_selection_strategy: :cost_quality_balanced,
          prompt_style: :technical,
          response_format: :structured
        }
      }
    }

    # Initialize session management
    initialize_session_management(session_config)
  end

  @doc """
  Initialize provider health monitoring via JidoAI.
  """
  def initialize_provider_health_monitoring do
    Logger.debug("Initializing JidoAI provider health monitoring")

    health_config = %{
      monitoring_interval: 30_000,
      health_check_timeout: 5_000,
      failure_threshold: 3,
      recovery_threshold: 5,
      
      providers_to_monitor: [:openai, :anthropic, :google, :openrouter, :cloudflare],
      
      health_metrics: [
        :response_time,
        :success_rate,
        :error_rate,
        :cost_efficiency,
        :quality_score
      ],

      integration_with_existing: %{
        provider_health_sensor: true,
        llm_monitoring_agent: true,
        unified_provider_service: true
      }
    }

    setup_provider_health_monitoring(health_config)
  end

  # Private implementation

  defp setup_openai_provider do
    {:ok, %{
      api_key_env: "OPENAI_API_KEY",
      models: [
        "gpt-4o",
        "gpt-4o-mini", 
        "gpt-3.5-turbo"
      ],
      default_model: "gpt-4o-mini",
      specializations: [:reasoning, :code_generation, :function_calling],
      cost_per_1k_tokens: %{
        "gpt-4o" => 0.005,
        "gpt-4o-mini" => 0.00015,
        "gpt-3.5-turbo" => 0.0005
      },
      max_tokens: 128_000,
      supports_streaming: true,
      supports_embeddings: true,
      supports_images: true
    }}
  end

  defp setup_anthropic_provider do
    {:ok, %{
      api_key_env: "ANTHROPIC_API_KEY", 
      models: [
        "claude-3-5-sonnet-20241022",
        "claude-3-haiku-20240307",
        "claude-3-opus-20240229"
      ],
      default_model: "claude-3-haiku-20240307",
      specializations: [:constitutional_ai, :safety, :reasoning, :large_context],
      cost_per_1k_tokens: %{
        "claude-3-5-sonnet-20241022" => 0.003,
        "claude-3-haiku-20240307" => 0.00025,
        "claude-3-opus-20240229" => 0.015
      },
      max_tokens: 200_000,
      supports_streaming: true,
      supports_embeddings: false,
      supports_images: true
    }}
  end

  defp setup_google_provider do
    {:ok, %{
      api_key_env: "GOOGLE_API_KEY",
      models: [
        "gemini-pro",
        "gemini-pro-vision",
        "text-embedding-004"
      ],
      default_model: "gemini-pro",
      specializations: [:multimodal, :embeddings, :reasoning],
      cost_per_1k_tokens: %{
        "gemini-pro" => 0.001,
        "gemini-pro-vision" => 0.002,
        "text-embedding-004" => 0.00001
      },
      max_tokens: 32_768,
      supports_streaming: true,
      supports_embeddings: true,
      supports_images: true
    }}
  end

  defp setup_openrouter_provider do
    {:ok, %{
      api_key_env: "OPENROUTER_API_KEY",
      models: ["auto"],
      default_model: "auto",
      specializations: [:model_routing, :cost_optimization],
      cost_per_1k_tokens: %{"auto" => 0.002},
      max_tokens: 100_000,
      supports_streaming: true,
      supports_embeddings: false,
      supports_images: true
    }}
  end

  defp setup_cloudflare_provider do
    {:ok, %{
      api_key_env: "CLOUDFLARE_API_KEY",
      models: ["@cf/meta/llama-2-7b-chat-int8"],
      default_model: "@cf/meta/llama-2-7b-chat-int8",
      specializations: [:edge_computing, :low_latency],
      cost_per_1k_tokens: %{"@cf/meta/llama-2-7b-chat-int8" => 0.0001},
      max_tokens: 4_096,
      supports_streaming: true,
      supports_embeddings: false,
      supports_images: false
    }}
  end

  defp configure_provider_in_keyring(provider_name, provider_config) do
    Logger.debug("Configuring #{provider_name} in JidoAI.Keyring")

    # Set up provider configuration in keyring
    keyring_key = String.to_atom("#{provider_name}_config")
    
    case Jido.AI.set_session_value(keyring_key, provider_config) do
      :ok ->
        Logger.debug("Successfully configured #{provider_name} in keyring")
        
      error ->
        Logger.warning("Failed to configure #{provider_name} in keyring: #{inspect(error)}")
    end

    # Set up API key from environment if available
    api_key_env = provider_config.api_key_env
    if api_key = System.get_env(api_key_env) do
      api_key_keyring_key = String.to_atom("#{provider_name}_api_key")
      Jido.AI.set_session_value(api_key_keyring_key, api_key)
      Logger.debug("Configured API key for #{provider_name} from environment")
    end
  end

  defp configure_keyring_with_settings(keyring_config) do
    Logger.debug("Configuring JidoAI.Keyring with hierarchical settings")

    # Configure keyring with our integration settings
    Enum.each(keyring_config, fn {key, value} ->
      Jido.AI.set_session_value(key, value)
    end)

    :ok
  end

  defp initialize_session_management(session_config) do
    Logger.debug("Initializing JidoAI session management")

    # Set up agent session patterns
    Enum.each(session_config.agent_session_patterns, fn {agent_type, config} ->
      session_key = String.to_atom("agent_session_#{agent_type}")
      Jido.AI.set_session_value(session_key, config)
    end)

    # Set up user session patterns  
    Jido.AI.set_session_value(:user_session_config, session_config.user_session_patterns)

    # Set up project session patterns
    Jido.AI.set_session_value(:project_session_config, session_config.project_session_patterns)

    :ok
  end

  defp setup_provider_health_monitoring(health_config) do
    Logger.debug("Setting up JidoAI provider health monitoring")

    # Configure health monitoring integration
    Jido.AI.set_session_value(:health_monitoring_config, health_config)

    # Integration with existing health check system
    Jido.AI.set_session_value(:health_integration, %{
      existing_health_check_supervisor: RubberDuck.HealthCheck.Supervisor,
      provider_health_sensor_integration: true,
      llm_monitoring_agent_coordination: true,
      unified_health_reporting: true
    })

    :ok
  end

  @doc """
  Get JidoAI configuration for specific provider.
  """
  def get_provider_config(provider_name) do
    keyring_key = String.to_atom("#{provider_name}_config")
    
    case Jido.AI.get_session_value(keyring_key) do
      nil ->
        Logger.warning("No configuration found for provider #{provider_name}")
        {:error, :provider_not_configured}
        
      config ->
        {:ok, config}
    end
  end

  @doc """
  Get provider API key from keyring.
  """
  def get_provider_api_key(provider_name) do
    # Try session value first
    api_key_keyring_key = String.to_atom("#{provider_name}_api_key")
    
    case Jido.AI.get_session_value(api_key_keyring_key) do
      nil ->
        # Fallback to environment variable
        case get_provider_config(provider_name) do
          {:ok, config} ->
            case System.get_env(config.api_key_env) do
              nil ->
                {:error, :api_key_not_found}
              api_key ->
                {:ok, api_key}
            end
          
          error ->
            error
        end
        
      api_key ->
        {:ok, api_key}
    end
  end

  @doc """
  Set provider API key in keyring (session override).
  """
  def set_provider_api_key(provider_name, api_key) do
    api_key_keyring_key = String.to_atom("#{provider_name}_api_key")
    
    case Jido.AI.set_session_value(api_key_keyring_key, api_key) do
      :ok ->
        Logger.debug("Set API key override for #{provider_name}")
        :ok
        
      error ->
        Logger.error("Failed to set API key for #{provider_name}: #{inspect(error)}")
        error
    end
  end

  @doc """
  Get available JidoAI providers with capabilities.
  """
  def get_available_providers do
    provider_names = [:openai, :anthropic, :google, :openrouter, :cloudflare]
    
    providers = 
      Enum.reduce(provider_names, %{}, fn provider_name, acc ->
        case get_provider_config(provider_name) do
          {:ok, config} ->
            Map.put(acc, provider_name, config)
          
          {:error, _} ->
            acc
        end
      end)
    
    {:ok, providers}
  end

  @doc """
  Validate JidoAI configuration completeness.
  """
  def validate_configuration do
    Logger.debug("Validating JidoAI configuration")

    validations = [
      validate_provider_configurations(),
      validate_keyring_setup(),
      validate_session_management(),
      validate_health_monitoring_setup()
    ]

    case Enum.all?(validations, &(&1 == :ok)) do
      true ->
        Logger.info("JidoAI configuration validation passed")
        :ok
        
      false ->
        failed_validations = 
          validations
          |> Enum.with_index()
          |> Enum.reject(fn {result, _idx} -> result == :ok end)
          |> Enum.map(fn {error, idx} -> {idx, error} end)
        
        Logger.error("JidoAI configuration validation failed: #{inspect(failed_validations)}")
        {:error, :validation_failed}
    end
  end

  # Private validation functions

  defp validate_provider_configurations do
    required_providers = [:openai, :anthropic]
    
    case Enum.all?(required_providers, fn provider ->
      case get_provider_config(provider) do
        {:ok, _config} -> true
        {:error, _} -> false
      end
    end) do
      true -> :ok
      false -> {:error, :missing_required_providers}
    end
  end

  defp validate_keyring_setup do
    test_key = :jido_ai_validation_test
    test_value = "validation_test_value"

    case Jido.AI.set_session_value(test_key, test_value) do
      :ok ->
        case Jido.AI.get_session_value(test_key) do
          ^test_value ->
            Jido.AI.clear_session_value(test_key)
            :ok
          
          _ ->
            {:error, :keyring_get_failed}
        end
        
      error ->
        {:error, {:keyring_set_failed, error}}
    end
  end

  defp validate_session_management do
    session_configs = [
      :agent_session_config,
      :user_session_config, 
      :project_session_config
    ]

    case Enum.all?(session_configs, fn config_key ->
      case Jido.AI.get_session_value(config_key) do
        nil -> false
        _config -> true
      end
    end) do
      true -> :ok
      false -> {:error, :session_management_incomplete}
    end
  end

  defp validate_health_monitoring_setup do
    case Jido.AI.get_session_value(:health_monitoring_config) do
      nil -> {:error, :health_monitoring_not_configured}
      _config -> :ok
    end
  end

  @doc """
  Get JidoAI integration status and statistics.
  """
  def get_integration_status do
    {:ok, providers} = get_available_providers()
    
    validation_result = validate_configuration()
    
    %{
      jido_ai_version: get_jido_ai_version(),
      integration_status: validation_result,
      configured_providers: Map.keys(providers),
      provider_count: map_size(providers),
      keyring_operational: validate_keyring_setup() == :ok,
      session_management_active: validate_session_management() == :ok,
      health_monitoring_enabled: validate_health_monitoring_setup() == :ok,
      last_updated: DateTime.utc_now()
    }
  end

  defp get_jido_ai_version do
    case Application.spec(:jido_ai, :vsn) do
      nil -> "unknown"
      version -> to_string(version)
    end
  end
end