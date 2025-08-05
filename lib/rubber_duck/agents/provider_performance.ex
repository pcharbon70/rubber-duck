defmodule RubberDuck.Agents.ProviderPerformance do
  @moduledoc """
  Resource for tracking LLM provider performance metrics.

  Stores performance statistics for each provider to help the
  orchestrator agent make informed decisions about provider selection.
  """

  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Agents,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "provider_performances"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:agent_state_id, :provider_name, :success_count, :failure_count,
              :total_duration, :total_tokens, :quality_sum]
      change set_attribute(:last_updated, &DateTime.utc_now/0)
    end

    update :update do
      accept [:success_count, :failure_count, :total_duration, :total_tokens, :quality_sum]
      change set_attribute(:last_updated, &DateTime.utc_now/0)
    end

    create :upsert do
      accept [:agent_state_id, :provider_name, :success_count, :failure_count,
              :total_duration, :total_tokens, :quality_sum]
      upsert? true
      upsert_identity :unique_provider_per_agent
      upsert_fields [:success_count, :failure_count, :total_duration, :total_tokens,
                     :quality_sum, :last_updated]
      change set_attribute(:last_updated, &DateTime.utc_now/0)
    end

    read :by_provider do
      argument :agent_state_id, :uuid, allow_nil?: false
      argument :provider_name, :string, allow_nil?: false
      get? true

      filter expr(
        agent_state_id == ^arg(:agent_state_id) and
        provider_name == ^arg(:provider_name)
      )
    end

    read :for_agent do
      argument :agent_state_id, :uuid, allow_nil?: false

      filter expr(agent_state_id == ^arg(:agent_state_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider_name, :string do
      description "Name of the LLM provider"
      allow_nil? false
      public? true
    end

    attribute :success_count, :integer do
      description "Number of successful requests"
      default 0
      public? true
    end

    attribute :failure_count, :integer do
      description "Number of failed requests"
      default 0
      public? true
    end

    attribute :total_duration, :integer do
      description "Total duration of all requests in milliseconds"
      default 0
      public? true
    end

    attribute :total_tokens, :integer do
      description "Total tokens used across all requests"
      default 0
      public? true
    end

    attribute :quality_sum, :float do
      description "Sum of quality scores for averaging"
      default 0.0
      public? true
    end

    attribute :last_updated, :utc_datetime do
      description "Last time these metrics were updated"
      allow_nil? false
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_provider_per_agent, [:agent_state_id, :provider_name]
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
