defmodule RubberDuck.Preferences.Seeders.LlmValidationSeeder do
  @moduledoc """
  Seeds LLM-specific preference validation rules.

  Creates validation rules for all LLM preferences to ensure data integrity
  and prevent invalid configurations.
  """

  require Logger

  alias RubberDuck.Preferences.Resources.PreferenceValidation

  @doc """
  Seed all LLM preference validation rules.
  """
  @spec seed_all() :: :ok | {:error, term()}
  def seed_all do
    Logger.info("Seeding LLM preference validation rules...")

    with :ok <- seed_provider_validations(),
         :ok <- seed_openai_validations(),
         :ok <- seed_anthropic_validations(),
         :ok <- seed_google_validations(),
         :ok <- seed_cost_validations(),
         :ok <- seed_fallback_validations(),
         :ok <- seed_monitoring_validations() do
      Logger.info("Successfully seeded all LLM preference validation rules")
      :ok
    else
      error ->
        Logger.error("Failed to seed LLM validation rules: #{inspect(error)}")
        error
    end
  end

  @doc """
  Seed provider selection validation rules.
  """
  @spec seed_provider_validations() :: :ok | {:error, term()}
  def seed_provider_validations do
    validations = [
      %{
        preference_key: "llm.providers.enabled",
        validation_type: :function,
        validation_rule: %{
          "module" => "RubberDuck.Preferences.Validators.LlmPreferenceValidator",
          "function" => "validate_provider_selection"
        },
        error_message: "Invalid provider selection",
        severity: :error,
        order: 1
      },
      %{
        preference_key: "llm.providers.default_provider",
        validation_type: :enum,
        validation_rule: %{
          "allowed_values" => ["openai", "anthropic", "google", "local", "ollama"]
        },
        error_message: "Invalid default provider",
        severity: :error,
        order: 1
      },
      %{
        preference_key: "llm.providers.priority_order",
        validation_type: :function,
        validation_rule: %{
          "module" => "RubberDuck.Preferences.Validators.LlmPreferenceValidator",
          "function" => "validate_provider_selection"
        },
        error_message: "Invalid provider priority order",
        severity: :error,
        order: 1
      },
      %{
        preference_key: "llm.providers.load_balancing",
        validation_type: :enum,
        validation_rule: %{
          "allowed_values" => ["round_robin", "least_connections", "weighted", "random"]
        },
        error_message: "Invalid load balancing strategy",
        severity: :error,
        order: 1
      }
    ]

    seed_validations(validations)
  end

  @doc """
  Seed OpenAI-specific validation rules.
  """
  @spec seed_openai_validations() :: :ok | {:error, term()}
  def seed_openai_validations do
    validations = [
      %{
        preference_key: "llm.openai.model",
        validation_type: :enum,
        validation_rule: %{
          "allowed_values" => ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo", "gpt-4o", "gpt-4o-mini"]
        },
        error_message: "Invalid OpenAI model",
        severity: :error,
        order: 1
      },
      %{
        preference_key: "llm.openai.temperature",
        validation_type: :range,
        validation_rule: %{"min" => 0.0, "max" => 2.0},
        error_message: "OpenAI temperature must be between 0.0 and 2.0",
        severity: :error,
        order: 1
      },
      %{
        preference_key: "llm.openai.max_tokens",
        validation_type: :range,
        validation_rule: %{"min" => 1, "max" => 128_000},
        error_message: "OpenAI max_tokens must be between 1 and 128000",
        severity: :error,
        order: 1
      },
      %{
        preference_key: "llm.openai.timeout",
        validation_type: :range,
        validation_rule: %{"min" => 1000, "max" => 300_000},
        error_message: "OpenAI timeout must be between 1000 and 300000 milliseconds",
        severity: :warning,
        order: 1
      }
    ]

    seed_validations(validations)
  end

  @doc """
  Seed Anthropic-specific validation rules.
  """
  @spec seed_anthropic_validations() :: :ok | {:error, term()}
  def seed_anthropic_validations do
    validations = [
      %{
        preference_key: "llm.anthropic.model",
        validation_type: :enum,
        validation_rule: %{
          "allowed_values" => [
            "claude-3-5-sonnet-20241022",
            "claude-3-5-haiku-20241022",
            "claude-3-opus-20240229",
            "claude-3-sonnet-20240229",
            "claude-3-haiku-20240307"
          ]
        },
        error_message: "Invalid Anthropic model",
        severity: :error,
        order: 1
      },
      %{
        preference_key: "llm.anthropic.temperature",
        validation_type: :range,
        validation_rule: %{"min" => 0.0, "max" => 1.0},
        error_message: "Anthropic temperature must be between 0.0 and 1.0",
        severity: :error,
        order: 1
      },
      %{
        preference_key: "llm.anthropic.max_tokens",
        validation_type: :range,
        validation_rule: %{"min" => 1, "max" => 200_000},
        error_message: "Anthropic max_tokens must be between 1 and 200000",
        severity: :error,
        order: 1
      }
    ]

    seed_validations(validations)
  end

  @doc """
  Seed Google-specific validation rules.
  """
  @spec seed_google_validations() :: :ok | {:error, term()}
  def seed_google_validations do
    validations = [
      %{
        preference_key: "llm.google.model",
        validation_type: :enum,
        validation_rule: %{
          "allowed_values" => ["gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.0-pro"]
        },
        error_message: "Invalid Google model",
        severity: :error,
        order: 1
      },
      %{
        preference_key: "llm.google.safety_settings",
        validation_type: :enum,
        validation_rule: %{
          "allowed_values" => ["strict", "moderate", "permissive"]
        },
        error_message: "Invalid Google safety settings",
        severity: :error,
        order: 1
      }
    ]

    seed_validations(validations)
  end

  @doc """
  Seed cost optimization validation rules.
  """
  @spec seed_cost_validations() :: :ok | {:error, term()}
  def seed_cost_validations do
    validations = [
      %{
        preference_key: "llm.cost.quality_threshold",
        validation_type: :range,
        validation_rule: %{"min" => 0.0, "max" => 1.0},
        error_message: "Quality threshold must be between 0.0 and 1.0",
        severity: :error,
        order: 1
      },
      %{
        preference_key: "llm.cost.cost_per_token_threshold",
        validation_type: :range,
        validation_rule: %{"min" => 0.0, "max" => 0.01},
        error_message: "Cost per token threshold must be between 0.0 and 0.01",
        severity: :warning,
        order: 1
      },
      %{
        preference_key: "llm.cost.token_usage_limits",
        validation_type: :function,
        validation_rule: %{
          "module" => "RubberDuck.Preferences.Validators.LlmPreferenceValidator",
          "function" => "validate_cost_config"
        },
        error_message: "Invalid token usage limits configuration",
        severity: :error,
        order: 1
      }
    ]

    seed_validations(validations)
  end

  @doc """
  Seed fallback configuration validation rules.
  """
  @spec seed_fallback_validations() :: :ok | {:error, term()}
  def seed_fallback_validations do
    validations = [
      %{
        preference_key: "llm.fallback.chain",
        validation_type: :function,
        validation_rule: %{
          "module" => "RubberDuck.Preferences.Validators.LlmPreferenceValidator",
          "function" => "validate_fallback_chain"
        },
        error_message: "Invalid fallback provider chain",
        severity: :error,
        order: 1
      }
    ]

    seed_validations(validations)
  end

  @doc """
  Seed monitoring configuration validation rules.
  """
  @spec seed_monitoring_validations() :: :ok | {:error, term()}
  def seed_monitoring_validations do
    validations = [
      %{
        preference_key: "llm.monitoring.health_check_interval",
        validation_type: :range,
        validation_rule: %{"min" => 10000, "max" => 3_600_000},
        error_message: "Health check interval must be between 10 seconds and 1 hour",
        severity: :warning,
        order: 1
      },
      %{
        preference_key: "llm.monitoring.alert_thresholds",
        validation_type: :function,
        validation_rule: %{
          "module" => "RubberDuck.Preferences.Validators.LlmPreferenceValidator",
          "function" => "validate_monitoring_config"
        },
        error_message: "Invalid monitoring alert thresholds",
        severity: :warning,
        order: 1
      }
    ]

    seed_validations(validations)
  end

  # Private helper functions

  defp seed_validations(validations) do
    Enum.reduce_while(validations, :ok, fn validation_attrs, _acc ->
      case PreferenceValidation.create(validation_attrs) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
