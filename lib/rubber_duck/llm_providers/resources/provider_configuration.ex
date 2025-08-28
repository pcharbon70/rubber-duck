defmodule RubberDuck.LlmProviders.Resources.ProviderConfiguration do
  @moduledoc """
  Universal provider configuration resource for managing LLM provider settings across all domains.
  """

  use Ash.Resource,
    domain: RubberDuck.LlmProviders,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "universal_provider_configurations"
    repo RubberDuck.Repo
  end

  code_interface do
    define :create
    define :read
    define :update
    define :destroy
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end

  attributes do
    uuid_primary_key :id

    attribute :provider_type, :atom do
      description "Type of LLM provider (openai, anthropic, ollama)"
      constraints one_of: [:openai, :anthropic, :ollama, :azure, :vertex]
      allow_nil? false
    end

    attribute :enabled, :boolean do
      description "Whether this provider is enabled"
      default true
    end

    attribute :api_configuration, :map do
      description "Provider-specific API configuration (encrypted)"
      default %{}
    end

    attribute :supported_domains, {:array, :atom} do
      description "Domains this provider supports"
      default [:evaluation, :orchestration]
    end

    attribute :model_mappings, :map do
      description "Model mappings for different use cases"
      default %{}
    end

    attribute :rate_limits, :map do
      description "Rate limiting configuration"
      default %{}
    end

    attribute :cost_limits, :map do
      description "Cost limiting configuration"
      default %{}
    end

    attribute :specialized_features, {:array, :atom} do
      description "Specialized features this provider supports"
      default []
    end

    timestamps()
  end
end
