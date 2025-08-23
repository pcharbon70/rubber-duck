defmodule RubberDuck.Preferences.Seeders.LlmDefaultsSeeder do
  @moduledoc """
  Seeds LLM provider preference defaults into the system.

  Creates comprehensive default configurations for all supported LLM providers,
  including provider selection, model preferences, cost optimization, and
  fallback configuration.
  """

  require Logger

  alias RubberDuck.Preferences.Resources.SystemDefault

  @doc """
  Seed all LLM provider preference defaults.
  """
  @spec seed_all() :: :ok | {:error, term()}
  def seed_all do
    Logger.info("Seeding LLM provider preference defaults...")

    with :ok <- seed_provider_selection_defaults(),
         :ok <- seed_openai_defaults(),
         :ok <- seed_anthropic_defaults(),
         :ok <- seed_google_defaults(),
         :ok <- seed_local_model_defaults(),
         :ok <- seed_cost_optimization_defaults(),
         :ok <- seed_fallback_configuration_defaults(),
         :ok <- seed_monitoring_defaults() do
      Logger.info("Successfully seeded all LLM provider preference defaults")
      :ok
    else
      error ->
        Logger.error("Failed to seed LLM provider defaults: #{inspect(error)}")
        error
    end
  end

  @doc """
  Seed provider selection preference defaults.
  """
  @spec seed_provider_selection_defaults() :: :ok | {:error, term()}
  def seed_provider_selection_defaults do
    defaults = [
      %{
        preference_key: "llm.providers.enabled",
        default_value: Jason.encode!(["openai", "anthropic"]),
        data_type: :json,
        category: "llm",
        subcategory: "providers",
        description: "List of enabled LLM providers",
        constraints: %{
          "allowed_values" => ["openai", "anthropic", "google", "local", "ollama"]
        }
      },
      %{
        preference_key: "llm.providers.priority_order",
        default_value: Jason.encode!(["anthropic", "openai", "google"]),
        data_type: :json,
        category: "llm",
        subcategory: "providers",
        description: "Provider selection priority order (first = highest priority)"
      },
      %{
        preference_key: "llm.providers.default_provider",
        default_value: Jason.encode!("anthropic"),
        data_type: :string,
        category: "llm",
        subcategory: "providers",
        description: "Default LLM provider for new requests",
        constraints: %{
          "allowed_values" => ["openai", "anthropic", "google", "local", "ollama"]
        }
      },
      %{
        preference_key: "llm.providers.fallback_enabled",
        default_value: Jason.encode!(true),
        data_type: :boolean,
        category: "llm",
        subcategory: "providers",
        description: "Enable automatic fallback to secondary providers on failure"
      },
      %{
        preference_key: "llm.providers.load_balancing",
        default_value: Jason.encode!("round_robin"),
        data_type: :string,
        category: "llm",
        subcategory: "providers",
        description: "Load balancing strategy across providers",
        constraints: %{
          "allowed_values" => ["round_robin", "least_connections", "weighted", "random"]
        }
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed OpenAI provider defaults.
  """
  @spec seed_openai_defaults() :: :ok | {:error, term()}
  def seed_openai_defaults do
    defaults = [
      %{
        preference_key: "llm.openai.model",
        default_value: Jason.encode!("gpt-4"),
        data_type: :string,
        category: "llm",
        subcategory: "openai",
        description: "Default OpenAI model",
        constraints: %{
          "allowed_values" => ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo", "gpt-4o", "gpt-4o-mini"]
        }
      },
      %{
        preference_key: "llm.openai.temperature",
        default_value: Jason.encode!(0.7),
        data_type: :float,
        category: "llm",
        subcategory: "openai",
        description: "OpenAI temperature setting (0.0-2.0)",
        constraints: %{"min" => 0.0, "max" => 2.0}
      },
      %{
        preference_key: "llm.openai.max_tokens",
        default_value: Jason.encode!(4096),
        data_type: :integer,
        category: "llm",
        subcategory: "openai",
        description: "Maximum tokens for OpenAI requests",
        constraints: %{"min" => 1, "max" => 128_000}
      },
      %{
        preference_key: "llm.openai.timeout",
        default_value: Jason.encode!(30_000),
        data_type: :integer,
        category: "llm",
        subcategory: "openai",
        description: "Request timeout in milliseconds",
        constraints: %{"min" => 1000, "max" => 300_000}
      },
      %{
        preference_key: "llm.openai.retry_attempts",
        default_value: Jason.encode!(3),
        data_type: :integer,
        category: "llm",
        subcategory: "openai",
        description: "Number of retry attempts on failure",
        constraints: %{"min" => 0, "max" => 10}
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed Anthropic provider defaults.
  """
  @spec seed_anthropic_defaults() :: :ok | {:error, term()}
  def seed_anthropic_defaults do
    defaults = [
      %{
        preference_key: "llm.anthropic.model",
        default_value: Jason.encode!("claude-3-5-sonnet-20241022"),
        data_type: :string,
        category: "llm",
        subcategory: "anthropic",
        description: "Default Anthropic model",
        constraints: %{
          "allowed_values" => [
            "claude-3-5-sonnet-20241022",
            "claude-3-5-haiku-20241022",
            "claude-3-opus-20240229",
            "claude-3-sonnet-20240229",
            "claude-3-haiku-20240307"
          ]
        }
      },
      %{
        preference_key: "llm.anthropic.temperature",
        default_value: Jason.encode!(0.7),
        data_type: :float,
        category: "llm",
        subcategory: "anthropic",
        description: "Anthropic temperature setting (0.0-1.0)",
        constraints: %{"min" => 0.0, "max" => 1.0}
      },
      %{
        preference_key: "llm.anthropic.max_tokens",
        default_value: Jason.encode!(4096),
        data_type: :integer,
        category: "llm",
        subcategory: "anthropic",
        description: "Maximum tokens for Anthropic requests",
        constraints: %{"min" => 1, "max" => 200_000}
      },
      %{
        preference_key: "llm.anthropic.timeout",
        default_value: Jason.encode!(60_000),
        data_type: :integer,
        category: "llm",
        subcategory: "anthropic",
        description: "Request timeout in milliseconds",
        constraints: %{"min" => 5000, "max" => 300_000}
      },
      %{
        preference_key: "llm.anthropic.stream_enabled",
        default_value: Jason.encode!(true),
        data_type: :boolean,
        category: "llm",
        subcategory: "anthropic",
        description: "Enable streaming responses for Anthropic"
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed Google provider defaults.
  """
  @spec seed_google_defaults() :: :ok | {:error, term()}
  def seed_google_defaults do
    defaults = [
      %{
        preference_key: "llm.google.model",
        default_value: Jason.encode!("gemini-1.5-pro"),
        data_type: :string,
        category: "llm",
        subcategory: "google",
        description: "Default Google Gemini model",
        constraints: %{
          "allowed_values" => ["gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.0-pro"]
        }
      },
      %{
        preference_key: "llm.google.temperature",
        default_value: Jason.encode!(0.7),
        data_type: :float,
        category: "llm",
        subcategory: "google",
        description: "Google model temperature setting",
        constraints: %{"min" => 0.0, "max" => 2.0}
      },
      %{
        preference_key: "llm.google.max_tokens",
        default_value: Jason.encode!(8192),
        data_type: :integer,
        category: "llm",
        subcategory: "google",
        description: "Maximum tokens for Google requests",
        constraints: %{"min" => 1, "max" => 1_000_000}
      },
      %{
        preference_key: "llm.google.safety_settings",
        default_value: Jason.encode!("moderate"),
        data_type: :string,
        category: "llm",
        subcategory: "google",
        description: "Google safety filter settings",
        constraints: %{
          "allowed_values" => ["strict", "moderate", "permissive"]
        }
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed local model defaults.
  """
  @spec seed_local_model_defaults() :: :ok | {:error, term()}
  def seed_local_model_defaults do
    defaults = [
      %{
        preference_key: "llm.local.enabled",
        default_value: Jason.encode!(false),
        data_type: :boolean,
        category: "llm",
        subcategory: "local",
        description: "Enable local model serving"
      },
      %{
        preference_key: "llm.local.model_path",
        default_value: Jason.encode!(""),
        data_type: :string,
        category: "llm",
        subcategory: "local",
        description: "Path to local model files"
      },
      %{
        preference_key: "llm.local.gpu_enabled",
        default_value: Jason.encode!(true),
        data_type: :boolean,
        category: "llm",
        subcategory: "local",
        description: "Enable GPU acceleration for local models"
      },
      %{
        preference_key: "llm.local.context_window",
        default_value: Jason.encode!(4096),
        data_type: :integer,
        category: "llm",
        subcategory: "local",
        description: "Context window size for local models",
        constraints: %{"min" => 512, "max" => 32_768}
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed cost optimization defaults.
  """
  @spec seed_cost_optimization_defaults() :: :ok | {:error, term()}
  def seed_cost_optimization_defaults do
    defaults = [
      %{
        preference_key: "llm.cost.optimization_enabled",
        default_value: Jason.encode!(true),
        data_type: :boolean,
        category: "llm",
        subcategory: "cost",
        description: "Enable cost optimization for provider selection"
      },
      %{
        preference_key: "llm.cost.quality_threshold",
        default_value: Jason.encode!(0.8),
        data_type: :float,
        category: "llm",
        subcategory: "cost",
        description: "Minimum quality threshold for cost optimization",
        constraints: %{"min" => 0.0, "max" => 1.0}
      },
      %{
        preference_key: "llm.cost.budget_aware_selection",
        default_value: Jason.encode!(true),
        data_type: :boolean,
        category: "llm",
        subcategory: "cost",
        description: "Consider budget constraints in provider selection"
      },
      %{
        preference_key: "llm.cost.token_usage_limits",
        default_value:
          Jason.encode!(%{
            "daily_limit" => 100_000,
            "weekly_limit" => 500_000,
            "monthly_limit" => 2_000_000
          }),
        data_type: :json,
        category: "llm",
        subcategory: "cost",
        description: "Token usage limits for cost control"
      },
      %{
        preference_key: "llm.cost.cost_per_token_threshold",
        default_value: Jason.encode!(0.00001),
        data_type: :float,
        category: "llm",
        subcategory: "cost",
        description: "Maximum cost per token threshold",
        constraints: %{"min" => 0.0, "max" => 0.01}
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed fallback configuration defaults.
  """
  @spec seed_fallback_configuration_defaults() :: :ok | {:error, term()}
  def seed_fallback_configuration_defaults do
    defaults = [
      %{
        preference_key: "llm.fallback.chain",
        default_value: Jason.encode!(["anthropic", "openai", "google"]),
        data_type: :json,
        category: "llm",
        subcategory: "fallback",
        description: "Fallback provider chain in order of preference"
      },
      %{
        preference_key: "llm.fallback.trigger_conditions",
        default_value:
          Jason.encode!(%{
            "error_types" => ["timeout", "rate_limit", "server_error"],
            "consecutive_failures" => 2,
            "failure_rate_threshold" => 0.3
          }),
        data_type: :json,
        category: "llm",
        subcategory: "fallback",
        description: "Conditions that trigger fallback to next provider"
      },
      %{
        preference_key: "llm.fallback.retry_policy",
        default_value:
          Jason.encode!(%{
            "max_retries" => 3,
            "base_delay_ms" => 1000,
            "max_delay_ms" => 30_000,
            "backoff_multiplier" => 2.0
          }),
        data_type: :json,
        category: "llm",
        subcategory: "fallback",
        description: "Retry policy configuration for failed requests"
      },
      %{
        preference_key: "llm.fallback.graceful_degradation",
        default_value: Jason.encode!(true),
        data_type: :boolean,
        category: "llm",
        subcategory: "fallback",
        description: "Enable graceful degradation to simpler models on failure"
      },
      %{
        preference_key: "llm.fallback.circuit_breaker_enabled",
        default_value: Jason.encode!(true),
        data_type: :boolean,
        category: "llm",
        subcategory: "fallback",
        description: "Enable circuit breaker pattern for failing providers"
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed monitoring preference defaults.
  """
  @spec seed_monitoring_defaults() :: :ok | {:error, term()}
  def seed_monitoring_defaults do
    defaults = [
      %{
        preference_key: "llm.monitoring.health_check_enabled",
        default_value: Jason.encode!(true),
        data_type: :boolean,
        category: "llm",
        subcategory: "monitoring",
        description: "Enable provider health monitoring"
      },
      %{
        preference_key: "llm.monitoring.health_check_interval",
        default_value: Jason.encode!(300_000),
        data_type: :integer,
        category: "llm",
        subcategory: "monitoring",
        description: "Health check interval in milliseconds",
        constraints: %{"min" => 10_000, "max" => 3_600_000}
      },
      %{
        preference_key: "llm.monitoring.performance_tracking",
        default_value: Jason.encode!(true),
        data_type: :boolean,
        category: "llm",
        subcategory: "monitoring",
        description: "Track provider performance metrics"
      },
      %{
        preference_key: "llm.monitoring.analytics_enabled",
        default_value: Jason.encode!(true),
        data_type: :boolean,
        category: "llm",
        subcategory: "monitoring",
        description: "Enable provider usage analytics"
      },
      %{
        preference_key: "llm.monitoring.alert_thresholds",
        default_value:
          Jason.encode!(%{
            "error_rate" => 0.1,
            "response_time_ms" => 10_000,
            "availability" => 0.95
          }),
        data_type: :json,
        category: "llm",
        subcategory: "monitoring",
        description: "Alert thresholds for provider monitoring"
      }
    ]

    seed_defaults(defaults)
  end

  # Private helper functions

  defp seed_defaults(defaults) do
    Enum.reduce_while(defaults, :ok, fn default_attrs, _acc ->
      case SystemDefault.seed_default(default_attrs) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
