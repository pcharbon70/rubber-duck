defmodule RubberDuck.WorkSummaries.Resources.WorkSession do
  @moduledoc """
  Work Session resource for grouping related work summaries.

  This resource groups multiple work summaries into logical sessions,
  enabling tracking of extended work periods and related task coordination.
  """

  use Ash.Resource,
    domain: RubberDuck.WorkSummaries,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "work_sessions"
    repo RubberDuck.Repo

    references do
      reference :coding_assistant, on_delete: :restrict
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create a new work session"

      accept [
        :name,
        :description,
        :session_type,
        :started_at,
        :session_metadata,
        :coding_assistant_id
      ]

      validate present([:name, :coding_assistant_id])
    end

    update :update do
      description "Update work session information"

      accept [
        :name,
        :description,
        :ended_at,
        :is_active,
        :session_metadata
      ]
    end

    update :end_session do
      description "End an active work session"

      change set_attribute(:ended_at, &DateTime.utc_now/0)
      change set_attribute(:is_active, false)
    end

    read :active_sessions do
      description "Get only active work sessions"
      filter expr(is_active == true)
    end

    read :by_assistant do
      description "Get sessions by coding assistant"

      argument :assistant_id, :uuid do
        allow_nil? false
      end

      filter expr(coding_assistant_id == ^arg(:assistant_id))
    end

    read :recent_sessions do
      description "Get recent work sessions"

      argument :limit, :integer do
        allow_nil? true
        default 20
      end

      # Sort by started_at descending
      pagination offset?: true, default_limit: 20
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
      description "Name of the work session"
      allow_nil? false
      constraints min_length: 3, max_length: 200
    end

    attribute :description, :string do
      description "Description of the work session goals"
      allow_nil? true
      constraints max_length: 1000
    end

    attribute :session_type, :atom do
      description "Type of work session"
      allow_nil? false

      constraints one_of: [
                    :feature_development,
                    :bug_fixing_session,
                    :refactoring_session,
                    :testing_session,
                    :research_session,
                    :maintenance_session,
                    :general_session
                  ]

      default :general_session
    end

    attribute :started_at, :utc_datetime_usec do
      description "When the work session started"
      allow_nil? false
      default &DateTime.utc_now/0
    end

    attribute :ended_at, :utc_datetime_usec do
      description "When the work session ended"
      allow_nil? true
    end

    attribute :is_active, :boolean do
      description "Whether session is currently active"
      allow_nil? false
      default true
    end

    attribute :session_metadata, :map do
      description "Session-specific metadata"
      allow_nil? false
      default %{}
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :coding_assistant, RubberDuck.WorkSummaries.Resources.CodingAssistant do
      description "The coding assistant for this session"
      allow_nil? false
    end

    has_many :work_summaries, RubberDuck.WorkSummaries.Resources.WorkSummary do
      description "Work summaries in this session"
    end
  end

  calculations do
    calculate :duration_minutes,
              :integer,
              expr(
                case
                when is_nil(ended_at) do
                       date_part("minute", now() - started_at)
                     else
                       date_part("minute", ended_at - started_at)
                     end
              ) do
      description "Session duration in minutes"
    end

    calculate :summary_count, :integer, expr(count(work_summaries, field: :id)) do
      description "Number of summaries in this session"
    end
  end

  aggregates do
    count :total_summaries, :work_summaries

    avg :avg_summary_quality, :work_summaries, :quality_score do
      description "Average quality of summaries in session"
    end

    sum :total_work_duration, :work_summaries, :work_duration_minutes do
      description "Total work duration for session"
    end
  end
end
