defmodule RubberDuck.Verdict.VerdictSystemConfiguration do
  @moduledoc """
  System-level Verdict configuration resource that defines global defaults
  and policies for the LLM judge evaluation system.
  
  This resource manages system-wide settings including:
  - Default models and provider preferences
  - Global budget constraints and cost optimization parameters
  - Quality thresholds and evaluation criteria defaults
  - Bias mitigation and security policies
  
  Integrates with the three-tier preference hierarchy as the system-level
  foundation that can be overridden by user and project configurations.
  """
  
  use Ash.Resource,
    domain: RubberDuck.Verdict,
    data_layer: AshPostgres.DataLayer
  
  require Logger
  
  postgres do
    table "verdict_system_configurations"
    repo RubberDuck.Repo
  end
  
  attributes do
    uuid_primary_key :id
    
    # Core configuration settings
    attribute :enabled, :boolean do
      description "Global enablement of Verdict evaluation system"
      default true
      allow_nil? false
    end
    
    attribute :default_screening_model, :string do
      description "Default model for lightweight screening evaluations"
      constraints min_length: 1, max_length: 100
      default "gpt-4o-mini"
      allow_nil? false
    end
    
    attribute :default_detailed_model, :string do
      description "Default model for detailed analysis evaluations"
      constraints min_length: 1, max_length: 100
      default "gpt-4o"
      allow_nil? false
    end
    
    # Budget and cost settings
    attribute :global_daily_budget, :decimal do
      description "System-wide daily budget limit for evaluations"
      constraints greater_than: 0
      default Decimal.new("100.00")
      allow_nil? false
    end
    
    attribute :cost_optimization_enabled, :boolean do
      description "Enable progressive evaluation and cost optimization"
      default true
    end
    
    attribute :max_tokens_per_evaluation, :integer do
      description "Maximum tokens allowed per single evaluation"
      constraints min: 100, max: 10_000
      default 1500
    end
    
    # Quality and evaluation settings
    attribute :default_quality_threshold, :decimal do
      description "Default minimum quality threshold for evaluations"
      constraints min: 0, max: 1
      default Decimal.new("0.8")
    end
    
    attribute :progressive_evaluation_enabled, :boolean do
      description "Enable progressive evaluation (screening then detailed)"
      default true
    end
    
    attribute :escalation_threshold, :decimal do
      description "Confidence threshold below which evaluations are escalated"
      constraints min: 0, max: 1
      default Decimal.new("0.6")
    end
    
    # Provider and model settings
    attribute :preferred_providers, {:array, :string} do
      description "Ordered list of preferred LLM providers"
      default ["openai", "anthropic"]
    end
    
    attribute :provider_fallback_enabled, :boolean do
      description "Enable automatic fallback to alternative providers"
      default true
    end
    
    # Security and compliance settings
    attribute :bias_mitigation_enabled, :boolean do
      description "Enable bias mitigation strategies during evaluation"
      default true
    end
    
    attribute :audit_all_evaluations, :boolean do
      description "Audit and log all evaluation requests and results"
      default true
    end
    
    attribute :data_retention_days, :integer do
      description "Days to retain evaluation data for compliance"
      constraints min: 1, max: 3650
      default 90
    end
    
    # Advanced configuration
    attribute :evaluation_criteria_weights, :map do
      description "Default weights for evaluation criteria categories"
      default %{
        "correctness" => 0.3,
        "security" => 0.25,
        "maintainability" => 0.2,
        "performance" => 0.15,
        "style" => 0.1
      }
    end
    
    attribute :cache_ttl_seconds, :integer do
      description "Cache time-to-live for evaluation results in seconds"
      constraints min: 60, max: 86_400
      default 3600
    end
    
    attribute :concurrent_evaluations_limit, :integer do
      description "Maximum concurrent evaluations per system instance"
      constraints min: 1, max: 100
      default 10
    end
    
    # Metadata
    attribute :configuration_version, :string do
      description "Version of the configuration schema"
      constraints min_length: 1, max_length: 50
      default "1.0.0"
    end
    
    attribute :description, :string do
      description "Human-readable description of this configuration"
      constraints max_length: 500
    end
    
    timestamps()
  end
  
  actions do
    defaults [:read]
    
    create :create do
      description "Create new system-level Verdict configuration"
      primary? true
      
      accept [
        :enabled, :default_screening_model, :default_detailed_model,
        :global_daily_budget, :cost_optimization_enabled, :max_tokens_per_evaluation,
        :default_quality_threshold, :progressive_evaluation_enabled, :escalation_threshold,
        :preferred_providers, :provider_fallback_enabled,
        :bias_mitigation_enabled, :audit_all_evaluations, :data_retention_days,
        :evaluation_criteria_weights, :cache_ttl_seconds, :concurrent_evaluations_limit,
        :configuration_version, :description
      ]
      
      validate present([:enabled, :default_screening_model, :default_detailed_model])
      validate match(:default_screening_model, ~r/^[a-z0-9\-]+$/)
      validate match(:default_detailed_model, ~r/^[a-z0-9\-]+$/)
    end
    
    update :update do
      description "Update system-level Verdict configuration"
      primary? true
      
      accept [
        :enabled, :default_screening_model, :default_detailed_model,
        :global_daily_budget, :cost_optimization_enabled, :max_tokens_per_evaluation,
        :default_quality_threshold, :progressive_evaluation_enabled, :escalation_threshold,
        :preferred_providers, :provider_fallback_enabled,
        :bias_mitigation_enabled, :audit_all_evaluations, :data_retention_days,
        :evaluation_criteria_weights, :cache_ttl_seconds, :concurrent_evaluations_limit,
        :configuration_version, :description
      ]
      
      validate match(:default_screening_model, ~r/^[a-z0-9\-]+$/)
      validate match(:default_detailed_model, ~r/^[a-z0-9\-]+$/)
    end
    
    destroy :destroy do
      description "Delete system-level Verdict configuration"
      primary? true
    end
    
    read :get_active_configuration do
      description "Get the currently active system configuration"
      
      filter expr(enabled == true)
      prepare build(sort: [created_at: :desc])
      get? true
    end
    
    read :get_by_version do
      description "Get system configuration by version"
      
      argument :version, :string do
        allow_nil? false
      end
      filter expr(configuration_version == ^arg(:version))
      get? true
    end
  end
  
  validations do
    validate match(:default_screening_model, ~r/^[a-z0-9\-]+$/),
      message: "Screening model name must be lowercase alphanumeric with hyphens"
    
    validate match(:default_detailed_model, ~r/^[a-z0-9\-]+$/),
      message: "Detailed model name must be lowercase alphanumeric with hyphens"
    
    validate present([:enabled, :default_screening_model, :default_detailed_model]),
      message: "Core configuration fields are required"
  end
  
  code_interface do
    define :create
    define :update
    define :destroy
    define :read
    define :get_active_configuration
    define :get_by_version, args: [:version]
  end
  
  def get_default_configuration do
    %{
      enabled: true,
      default_screening_model: "gpt-4o-mini",
      default_detailed_model: "gpt-4o", 
      global_daily_budget: Decimal.new("100.00"),
      cost_optimization_enabled: true,
      max_tokens_per_evaluation: 1500,
      default_quality_threshold: Decimal.new("0.8"),
      progressive_evaluation_enabled: true,
      escalation_threshold: Decimal.new("0.6"),
      preferred_providers: ["openai", "anthropic"],
      provider_fallback_enabled: true,
      bias_mitigation_enabled: true,
      audit_all_evaluations: true,
      data_retention_days: 90,
      evaluation_criteria_weights: %{
        "correctness" => 0.3,
        "security" => 0.25,
        "maintainability" => 0.2, 
        "performance" => 0.15,
        "style" => 0.1
      },
      cache_ttl_seconds: 3600,
      concurrent_evaluations_limit: 10,
      configuration_version: "1.0.0"
    }
  end
  
  def validate_configuration(config) when is_map(config) do
    with :ok <- validate_required_fields(config),
         :ok <- validate_budget_values(config),
         :ok <- validate_thresholds(config),
         :ok <- validate_providers(config),
         :ok <- validate_criteria_weights(config) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp validate_required_fields(config) do
    required = [:enabled, :default_screening_model, :default_detailed_model]
    missing = Enum.filter(required, &(!Map.has_key?(config, &1)))
    
    case missing do
      [] -> :ok
      fields -> {:error, "Missing required fields: #{inspect(fields)}"}
    end
  end
  
  defp validate_budget_values(config) do
    case Map.get(config, :global_daily_budget) do
      budget when is_number(budget) and budget > 0 -> :ok
      %Decimal{} = budget -> if Decimal.positive?(budget), do: :ok, else: {:error, "Budget must be positive"}
      _ -> {:error, "Invalid budget value"}
    end
  end
  
  defp validate_thresholds(config) do
    quality = Map.get(config, :default_quality_threshold, 0.8)
    escalation = Map.get(config, :escalation_threshold, 0.6)
    
    cond do
      escalation >= quality -> {:error, "Escalation threshold must be less than quality threshold"}
      quality < 0 or quality > 1 -> {:error, "Quality threshold must be between 0 and 1"}
      escalation < 0 or escalation > 1 -> {:error, "Escalation threshold must be between 0 and 1"}
      true -> :ok
    end
  end
  
  defp validate_providers(config) do
    case Map.get(config, :preferred_providers, []) do
      providers when is_list(providers) ->
        if Enum.empty?(providers) do
          {:error, "Preferred providers must be a non-empty list"}
        else
          valid_providers = ["openai", "anthropic", "ollama", "azure", "vertex"]
          if Enum.all?(providers, &(&1 in valid_providers)) do
            :ok
          else
            {:error, "Invalid provider in list"}
          end
        end
      _ -> {:error, "Preferred providers must be a non-empty list"}
    end
  end
  
  defp validate_criteria_weights(config) do
    case Map.get(config, :evaluation_criteria_weights, %{}) do
      weights when is_map(weights) ->
        total = weights |> Map.values() |> Enum.sum()
        if abs(total - 1.0) < 0.001 do
          :ok
        else
          {:error, "Evaluation criteria weights must sum to 1.0"}
        end
      _ -> {:error, "Evaluation criteria weights must be a map"}
    end
  end
end