defmodule RubberDuck.Agents.AgentState do
  @moduledoc """
  Resource for persisting core agent state.

  Stores the essential state information for agents that needs to
  persist across restarts, including metadata specific to each agent type.
  """

  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Agents,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "agent_states"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:agent_name, :agent_type, :metadata]
    end

    update :update do
      primary? true
      accept [:metadata, :last_checkpoint]
    end

    update :checkpoint do
      accept []
      change set_attribute(:last_checkpoint, &DateTime.utc_now/0)
    end

    read :by_name do
      argument :agent_name, :string, allow_nil?: false
      get? true
      filter expr(agent_name == ^arg(:agent_name))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :agent_name, :string do
      description "Unique name of the agent instance"
      allow_nil? false
      public? true
    end

    attribute :agent_type, :string do
      description "Type of agent (e.g., llm_orchestrator, llm_monitoring)"
      allow_nil? false
      public? true
    end

    attribute :last_checkpoint, :utc_datetime do
      description "Last time the agent state was checkpointed"
      allow_nil? true
      public? true
    end

    attribute :metadata, :map do
      description "Agent-specific metadata and state"
      default %{}
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_agent_name, [:agent_name]
  end

  relationships do
    has_many :experiences, RubberDuck.Agents.AgentExperience do
      destination_attribute :agent_state_id
    end

    has_many :insights, RubberDuck.Agents.AgentInsight do
      destination_attribute :agent_state_id
    end

    has_many :provider_performances, RubberDuck.Agents.ProviderPerformance do
      destination_attribute :agent_state_id
    end
  end
end
