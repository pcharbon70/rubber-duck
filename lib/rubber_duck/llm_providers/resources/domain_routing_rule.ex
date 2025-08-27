defmodule RubberDuck.LlmProviders.Resources.DomainRoutingRule do
  @moduledoc """
  Domain-specific routing rules for universal LLM provider selection.
  """
  
  use Ash.Resource,
    domain: RubberDuck.LlmProviders,
    data_layer: AshPostgres.DataLayer
  
  postgres do
    table "domain_routing_rules"
    repo RubberDuck.Repo
  end
  
  attributes do
    uuid_primary_key :id
    
    attribute :domain, :atom do
      description "Domain this routing rule applies to"
      constraints one_of: [:evaluation, :orchestration, :planning, :communication]
      allow_nil? false
    end
    
    attribute :use_case, :atom do
      description "Specific use case within domain"
      default :general
    end
    
    attribute :preferred_provider, :atom do
      description "Preferred provider for this domain/use_case"
      constraints one_of: [:openai, :anthropic, :ollama]
    end
    
    attribute :routing_strategy, :atom do
      description "Routing strategy to use"
      constraints one_of: [:cost_optimized, :quality_first, :balanced, :constitutional_ai_first]
      default :balanced
    end
    
    attribute :required_features, {:array, :atom} do
      description "Required features for this routing rule"
      default []
    end
    
    attribute :cost_weight, :decimal do
      description "Cost weighting for routing decisions"
      constraints min: 0, max: 1
      default Decimal.new("0.4")
    end
    
    attribute :quality_weight, :decimal do
      description "Quality weighting for routing decisions"
      constraints min: 0, max: 1
      default Decimal.new("0.4")
    end
    
    attribute :speed_weight, :decimal do
      description "Speed weighting for routing decisions"
      constraints min: 0, max: 1
      default Decimal.new("0.2")
    end
    
    attribute :active, :boolean do
      description "Whether this routing rule is active"
      default true
    end
    
    timestamps()
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
    
    read :by_domain do
      description "Get routing rules by domain"
      
      argument :domain, :atom do
        allow_nil? false
      end
      filter expr(domain == ^arg(:domain) and active == true)
    end
    
    read :by_domain_and_use_case do
      description "Get routing rule by domain and use case"
      
      argument :domain, :atom do
        allow_nil? false
      end
      argument :use_case, :atom do
        allow_nil? false
      end
      
      filter expr(domain == ^arg(:domain) and use_case == ^arg(:use_case) and active == true)
      get? true
    end
  end
  
  code_interface do
    define :create
    define :read
    define :update
    define :destroy
    define :by_domain, args: [:domain]
    define :by_domain_and_use_case, args: [:domain, :use_case]
  end
end