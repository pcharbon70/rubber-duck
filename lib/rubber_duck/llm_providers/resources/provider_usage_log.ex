defmodule RubberDuck.LlmProviders.Resources.ProviderUsageLog do
  @moduledoc """
  Usage logging for universal LLM provider analytics and cost tracking.
  """

  use Ash.Resource,
    domain: RubberDuck.LlmProviders,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "provider_usage_logs"
    repo RubberDuck.Repo
  end

  code_interface do
    define :create
    define :read
    define :by_domain, args: [:domain]
    define :by_provider, args: [:provider_type]
    define :recent_usage, args: [:hours_back]
  end

  actions do
    defaults [:read, :create]

    read :by_domain do
      description "Get usage logs by domain"

      argument :domain, :atom do
        allow_nil? false
      end

      filter expr(domain == ^arg(:domain))
      prepare build(sort: [inserted_at: :desc])
    end

    read :by_provider do
      description "Get usage logs by provider"

      argument :provider_type, :atom do
        allow_nil? false
      end

      filter expr(provider_type == ^arg(:provider_type))
      prepare build(sort: [inserted_at: :desc])
    end

    read :recent_usage do
      description "Get recent usage logs"

      argument :hours_back, :integer do
        default 24
      end

      filter expr(inserted_at > ago(^arg(:hours_back), :hour))
      prepare build(sort: [inserted_at: :desc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider_type, :atom do
      description "Type of LLM provider used"
      constraints one_of: [:openai, :anthropic, :ollama]
      allow_nil? false
    end

    attribute :domain, :atom do
      description "Domain where provider was used"
      constraints one_of: [:evaluation, :orchestration, :planning, :communication]
      allow_nil? false
    end

    attribute :use_case, :atom do
      description "Specific use case within domain"
      default :general
    end

    attribute :model_used, :string do
      description "Specific model used for this request"
    end

    attribute :success, :boolean do
      description "Whether the request was successful"
      default false
    end

    attribute :cost_usd, :decimal do
      description "Cost of this request in USD"
      constraints min: 0
      default Decimal.new("0.0")
    end

    attribute :tokens_used, :integer do
      description "Number of tokens used"
      constraints min: 0
      default 0
    end

    attribute :response_time_ms, :integer do
      description "Response time in milliseconds"
      constraints min: 0
      default 0
    end

    attribute :specialized_features_used, {:array, :atom} do
      description "List of specialized features used"
      default []
    end

    attribute :request_metadata, :map do
      description "Additional request metadata"
      default %{}
    end

    timestamps()
  end
end
