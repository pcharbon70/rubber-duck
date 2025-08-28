defmodule RubberDuck.LlmProviders.Resources.ProviderHealthStatus do
  @moduledoc """
  Provider health status tracking for universal LLM providers.
  """

  use Ash.Resource,
    domain: RubberDuck.LlmProviders,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "provider_health_status"
    repo RubberDuck.Repo
  end

  code_interface do
    define :create
    define :read
    define :update
    define :destroy
    define :by_provider_and_domain, args: [:provider_type, :domain]
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    read :by_provider_and_domain do
      description "Get health status by provider and domain"

      argument :provider_type, :atom do
        allow_nil? false
      end

      argument :domain, :atom do
        allow_nil? false
      end

      filter expr(provider_type == ^arg(:provider_type) and domain == ^arg(:domain))
      get? true
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider_type, :atom do
      description "Type of LLM provider"
      constraints one_of: [:openai, :anthropic, :ollama]
      allow_nil? false
    end

    attribute :domain, :atom do
      description "Domain for this health status"
      constraints one_of: [:evaluation, :orchestration, :planning, :communication]
      allow_nil? false
    end

    attribute :status, :atom do
      description "Current health status"
      constraints one_of: [:healthy, :degraded, :unhealthy, :unknown]
      default :unknown
    end

    attribute :success_rate, :decimal do
      description "Success rate for this provider/domain combination"
      constraints min: 0, max: 1
      default Decimal.new("0.0")
    end

    attribute :avg_response_time_ms, :integer do
      description "Average response time in milliseconds"
      constraints min: 0
      default 0
    end

    attribute :last_check, :utc_datetime do
      description "Timestamp of last health check"
    end

    attribute :error_count, :integer do
      description "Number of consecutive errors"
      constraints min: 0
      default 0
    end

    timestamps()
  end
end
