defmodule RubberDuck.WorkSummaries.Resources.CodingAssistant do
  @moduledoc """
  Coding Assistant resource for tracking assistant metadata and capabilities.

  This resource stores information about coding assistants including their
  capabilities, performance metrics, and configuration details for comprehensive
  work tracking and performance analysis.
  """

  use Ash.Resource,
    domain: RubberDuck.WorkSummaries,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "coding_assistants"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create a new coding assistant record"

      accept [
        :name,
        :version,
        :capabilities,
        :provider_preferences,
        :performance_metrics,
        :configuration
      ]

      validate present([:name])
    end

    update :update do
      description "Update coding assistant information"

      accept [
        :version,
        :capabilities,
        :provider_preferences,
        :performance_metrics,
        :configuration,
        :is_active
      ]
    end

    read :active_assistants do
      description "Get only active assistants"
      filter expr(is_active == true)
    end

    read :by_name do
      description "Find assistant by name"

      argument :assistant_name, :string do
        allow_nil? false
      end

      filter expr(name == ^arg(:assistant_name))
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      # Will be restricted based on user context in production
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      description "Name of the coding assistant"
      allow_nil? false
      constraints min_length: 1, max_length: 100
    end

    attribute :version, :string do
      description "Version of the coding assistant"
      allow_nil? true
      constraints max_length: 50
    end

    attribute :capabilities, {:array, :string} do
      description "List of assistant capabilities"
      allow_nil? false
      default []
      constraints items: [max_length: 100], max_length: 50
    end

    attribute :provider_preferences, :map do
      description "Preferred LLM providers and models"
      allow_nil? false
      default %{}
    end

    attribute :performance_metrics, :map do
      description "Performance tracking data"
      allow_nil? false
      default %{}
    end

    attribute :configuration, :map do
      description "Assistant configuration and settings"
      allow_nil? false
      default %{}
    end

    attribute :is_active, :boolean do
      description "Whether assistant is currently active"
      allow_nil? false
      default true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :work_summaries, RubberDuck.WorkSummaries.Resources.WorkSummary do
      description "Work summaries created by this assistant"
    end

    has_many :work_sessions, RubberDuck.WorkSummaries.Resources.WorkSession do
      description "Work sessions for this assistant"
    end
  end

  calculations do
    calculate :total_summaries_count, :integer, expr(count(work_summaries, field: :id)) do
      description "Total number of summaries created by this assistant"
    end

    calculate :avg_summary_quality, :decimal, expr(avg(work_summaries, field: :quality_score)) do
      description "Average quality score of summaries"
    end

    calculate :total_work_time,
              :integer,
              expr(sum(work_summaries, field: :work_duration_minutes)) do
      description "Total work time in minutes"
    end
  end

  aggregates do
    count :summary_count, :work_summaries

    avg :average_quality, :work_summaries, :quality_score do
      description "Average quality across all summaries"
    end

    sum :total_duration, :work_summaries, :work_duration_minutes do
      description "Total work duration across all summaries"
    end
  end
end
