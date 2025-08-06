defmodule RubberDuck.Agents.AgentExperience do
  @moduledoc """
  Resource for storing individual agent experience entries.

  Experiences are learning opportunities that agents accumulate
  during their operation, including goal completions, failures,
  and other significant events.
  """

  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Agents,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "agent_experiences"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:agent_state_id, :experience_type, :goal, :result, :metadata]
      change set_attribute(:timestamp, &DateTime.utc_now/0)
    end

    destroy :prune do
      argument :retention_days, :integer, allow_nil?: false, default: 30

      filter expr(timestamp < datetime_add(now(), ^(-1) * arg(:retention_days), :day))
    end

    read :by_agent do
      argument :agent_state_id, :uuid, allow_nil?: false
      argument :limit, :integer, default: 1000

      filter expr(agent_state_id == ^arg(:agent_state_id))
      prepare build(sort: [timestamp: :desc], limit: arg(:limit))
    end

    read :recent do
      argument :agent_state_id, :uuid, allow_nil?: false
      argument :hours, :integer, default: 24

      filter expr(
               agent_state_id == ^arg(:agent_state_id) and
                 timestamp > datetime_add(now(), ^(-1) * arg(:hours), :hour)
             )

      prepare build(sort: [timestamp: :desc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :experience_type, :string do
      description "Type of experience (e.g., goal_completion, failure, learning)"
      allow_nil? false
      public? true
    end

    attribute :goal, :map do
      description "The goal associated with this experience"
      allow_nil? true
      public? true
    end

    attribute :result, :map do
      description "The result or outcome of the experience"
      allow_nil? true
      public? true
    end

    attribute :timestamp, :utc_datetime do
      description "When this experience occurred"
      allow_nil? false
      public? true
    end

    attribute :metadata, :map do
      description "Additional experience-specific data"
      default %{}
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
