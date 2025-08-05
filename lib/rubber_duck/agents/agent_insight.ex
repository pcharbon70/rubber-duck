defmodule RubberDuck.Agents.AgentInsight do
  @moduledoc """
  Resource for storing learned insights from agent experiences.
  
  Insights are patterns, correlations, and optimizations that agents
  discover through analyzing their experiences over time.
  """

  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Agents,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "agent_insights"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:agent_state_id, :insight_type, :insights, :confidence, :applicable_scenarios]
      validate one_of(:insight_type, ["pattern", "correlation", "optimization"])
      change set_attribute(:learned_at, &DateTime.utc_now/0)
    end

    update :update do
      primary? true
      accept [:insights, :confidence, :applicable_scenarios]
    end

    read :latest do
      argument :agent_state_id, :uuid, allow_nil?: false
      argument :insight_type, :string, allow_nil?: true
      
      filter expr(
        agent_state_id == ^arg(:agent_state_id) and
        if(is_nil(^arg(:insight_type)), true, insight_type == ^arg(:insight_type))
      )
      prepare build(sort: [learned_at: :desc], limit: 10)
    end

    read :by_type do
      argument :agent_state_id, :uuid, allow_nil?: false
      argument :insight_type, :string, allow_nil?: false
      
      filter expr(
        agent_state_id == ^arg(:agent_state_id) and
        insight_type == ^arg(:insight_type)
      )
      prepare build(sort: [learned_at: :desc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :insight_type, :string do
      description "Type of insight (pattern, correlation, optimization)"
      allow_nil? false
      public? true
    end

    attribute :insights, :map do
      description "The actual insights discovered"
      allow_nil? false
      public? true
    end

    attribute :confidence, :float do
      description "Confidence level in the insight (0.0 to 1.0)"
      allow_nil? false
      public? true
      constraints [min: 0.0, max: 1.0]
    end

    attribute :applicable_scenarios, {:array, :string} do
      description "Scenarios where this insight applies"
      default []
      public? true
    end

    attribute :learned_at, :utc_datetime do
      description "When this insight was learned"
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :agent_state, RubberDuck.Agents.AgentState do
      allow_nil? false
      attribute_writable? true
    end
  end

  postgres do
    references do
      reference :agent_state do
        on_delete :delete
      end
    end
  end
end