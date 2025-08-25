defmodule RubberDuck.Verdict.Resources.VerdictConfiguration do
  @moduledoc """
  Verdict configuration resource for system-wide judge settings.

  Manages system-level configuration for the Verdict framework including
  default models, cost thresholds, performance parameters, and evaluation
  policies. Integrates with the three-tier preference system.
  """

  use Ash.Resource,
    domain: RubberDuck.Verdict,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "verdict_configurations"
    repo RubberDuck.Repo
  end

  code_interface do
    define :create, action: :create
    define :read, action: :read
    define :update_settings, action: :update_settings
    define :destroy, action: :destroy
    define :activate, action: :activate
    define :deactivate, action: :deactivate
    define :by_type, args: [:configuration_type], action: :read
    define :active_configuration, action: :read
    define :system_configurations, action: :read
    define :user_templates, action: :read
    define :project_templates, action: :read
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      description "Create a new Verdict configuration"

      accept [
        :configuration_name,
        :configuration_type,
        :enabled,
        :default_model,
        :detailed_model,
        :quality_threshold,
        :confidence_threshold,
        :max_tokens_per_evaluation,
        :budget_per_day,
        :progressive_evaluation,
        :cache_enabled,
        :cache_ttl_seconds,
        :bias_mitigation_enabled,
        :feedback_learning_enabled,
        :evaluation_timeout_ms,
        :retry_attempts,
        :supported_evaluation_types,
        :model_preferences,
        :cost_optimization_settings,
        :performance_thresholds,
        :version
      ]

      validate present([:configuration_name])
    end

    update :update_settings do
      description "Update configuration settings"

      accept [
        :enabled,
        :default_model,
        :detailed_model,
        :quality_threshold,
        :confidence_threshold,
        :max_tokens_per_evaluation,
        :budget_per_day,
        :progressive_evaluation,
        :cache_enabled,
        :cache_ttl_seconds,
        :bias_mitigation_enabled,
        :feedback_learning_enabled,
        :evaluation_timeout_ms,
        :retry_attempts,
        :supported_evaluation_types,
        :model_preferences,
        :cost_optimization_settings,
        :performance_thresholds,
        :version
      ]
    end

    update :activate do
      description "Activate this configuration"
      change set_attribute(:active, true)
    end

    update :deactivate do
      description "Deactivate this configuration"
      change set_attribute(:active, false)
    end
  end

  # Authorization policies for Verdict configurations
  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      description "All authenticated users can read configurations"

      authorize_if actor_attribute_equals(:role, :user)
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :security_admin)
    end

    policy action([:create, :update, :activate, :deactivate]) do
      description "Only admins can manage configurations"

      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :security_admin)
    end

    policy action_type(:destroy) do
      description "Only security admins can delete configurations"
      authorize_if actor_attribute_equals(:role, :security_admin)
    end
  end

  preparations do
    prepare build(sort: [updated_at: :desc])
  end

  attributes do
    uuid_primary_key :id

    attribute :configuration_name, :string do
      description "Human-readable name for this configuration"
      constraints max_length: 255
      allow_nil? false
    end

    attribute :configuration_type, :atom do
      description "Type of configuration"
      constraints one_of: [:system_default, :user_template, :project_template]
      default :system_default
    end

    attribute :enabled, :boolean do
      description "Whether Verdict evaluation is enabled"
      default true
    end

    attribute :default_model, :string do
      description "Default LLM model for evaluations"
      constraints max_length: 100
      default "gpt-4o-mini"
    end

    attribute :detailed_model, :string do
      description "Model used for detailed evaluations"
      constraints max_length: 100
      default "gpt-4o"
    end

    attribute :quality_threshold, :decimal do
      description "Quality threshold for evaluation escalation"
      constraints precision: 3, scale: 2, min: 0.0, max: 1.0
      default 0.8
    end

    attribute :confidence_threshold, :decimal do
      description "Confidence threshold for evaluation acceptance"
      constraints precision: 3, scale: 2, min: 0.0, max: 1.0
      default 0.7
    end

    attribute :max_tokens_per_evaluation, :integer do
      description "Maximum tokens allowed per evaluation"
      constraints min: 100, max: 10_000
      default 1500
    end

    attribute :budget_per_day, :decimal do
      description "Daily budget limit for evaluations in USD"
      constraints precision: 10, scale: 2, min: 0.0
      default 10.00
    end

    attribute :progressive_evaluation, :boolean do
      description "Whether to use progressive evaluation strategy"
      default true
    end

    attribute :cache_enabled, :boolean do
      description "Whether intelligent caching is enabled"
      default true
    end

    attribute :cache_ttl_seconds, :integer do
      description "Cache TTL in seconds"
      constraints min: 60, max: 86_400
      default 3600
    end

    attribute :bias_mitigation_enabled, :boolean do
      description "Whether bias mitigation strategies are enabled"
      default true
    end

    attribute :feedback_learning_enabled, :boolean do
      description "Whether to learn from user feedback"
      default true
    end

    attribute :evaluation_timeout_ms, :integer do
      description "Timeout for evaluations in milliseconds"
      constraints min: 1000, max: 60_000
      default 30_000
    end

    attribute :retry_attempts, :integer do
      description "Number of retry attempts for failed evaluations"
      constraints min: 0, max: 5
      default 2
    end

    attribute :supported_evaluation_types, {:array, :atom} do
      description "Evaluation types supported by this configuration"
      default [:quality, :security, :performance, :maintainability, :best_practices]
    end

    attribute :model_preferences, :map do
      description "Model preferences for different evaluation types"

      default %{
        quality: "gpt-4o-mini",
        security: "gpt-4o",
        performance: "gpt-4o-mini",
        maintainability: "gpt-4o-mini",
        best_practices: "gpt-4o-mini"
      }
    end

    attribute :cost_optimization_settings, :map do
      description "Settings for cost optimization strategies"

      default %{
        lightweight_threshold: 0.6,
        escalation_triggers: ["low_confidence", "many_issues", "security_keywords"],
        max_cost_per_evaluation: 0.30
      }
    end

    attribute :performance_thresholds, :map do
      description "Performance monitoring thresholds"

      default %{
        max_latency_ms: 10_000,
        min_success_rate: 0.95,
        max_cost_per_token: 0.00005
      }
    end

    attribute :active, :boolean do
      description "Whether this configuration is currently active"
      default false
    end

    attribute :version, :string do
      description "Configuration version for tracking changes"
      constraints max_length: 20
      allow_nil? true
    end

    timestamps()
  end

  calculations do
    calculate :is_cost_effective, :boolean, expr(budget_per_day > 0.0 and budget_per_day <= 50.0)

    calculate :has_progressive_optimization,
              :boolean,
              expr(progressive_evaluation and cache_enabled)

    calculate :estimated_daily_evaluations, :integer, expr(round(budget_per_day / 0.02))

    calculate :configuration_completeness,
              :decimal,
              expr(
                cond do
                  not is_nil(default_model) and not is_nil(detailed_model) and budget_per_day > 0 ->
                    1.0

                  not is_nil(default_model) and not is_nil(detailed_model) ->
                    0.8

                  not is_nil(default_model) and budget_per_day > 0 ->
                    0.7

                  true ->
                    0.5
                end
              )
  end
end
