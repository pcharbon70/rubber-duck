defmodule RubberDuck.WorkSummaries.Resources.WorkSummary do
  @moduledoc """
  Work Summary resource for persisting coding assistant work summaries.

  This resource stores comprehensive summaries of coding assistant work including
  markdown content, metadata about the assistant used, project context, provider
  and model information, and generation timestamps for historical tracking.

  Features:
  - Markdown-formatted summary content with rich formatting support
  - Comprehensive metadata tracking including assistant, project, provider/model
  - Temporal tracking with generation and modification timestamps
  - Categorization and tagging for efficient organization and retrieval
  - Integration with existing authentication and authorization systems
  - Full-text search capabilities for content discovery
  """

  use Ash.Resource,
    domain: RubberDuck.WorkSummaries,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "work_summaries"
    repo RubberDuck.Repo

    references do
      reference :coding_assistant, on_delete: :restrict
      reference :work_session, on_delete: :nilify
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :content, :string do
      description "Markdown-formatted summary content"
      allow_nil? false
      constraints min_length: 10, max_length: 50_000
    end

    attribute :summary_type, :atom do
      description "Type of work summarized"
      allow_nil? false
      constraints one_of: [
        :feature_implementation,
        :bug_fix, 
        :refactoring,
        :testing,
        :documentation,
        :performance_optimization,
        :security_enhancement,
        :integration,
        :general
      ]
      default :general
    end

    attribute :title, :string do
      description "Brief title summarizing the work"
      allow_nil? false
      constraints min_length: 5, max_length: 200
    end

    attribute :current_project, :string do
      description "Project name or identifier where work was performed"
      allow_nil? true
      constraints max_length: 100
    end

    attribute :provider_used, :string do
      description "LLM provider used for the work (e.g., openai, anthropic)"
      allow_nil? true
      constraints max_length: 50
    end

    attribute :model_used, :string do
      description "Specific model used (e.g., gpt-4-turbo, claude-3-sonnet)"
      allow_nil? true
      constraints max_length: 100
    end

    attribute :generated_at, :utc_datetime_usec do
      description "When the summary was generated"
      allow_nil? false
      default &DateTime.utc_now/0
    end

    attribute :work_duration_minutes, :integer do
      description "Duration of work session in minutes"
      allow_nil? true
      constraints min: 0, max: 10_080  # Max 1 week
    end

    attribute :metadata, :map do
      description "Additional metadata as JSON"
      allow_nil? false
      default %{}
    end

    attribute :tags, {:array, :string} do
      description "Tags for categorization and search"
      allow_nil? false
      default []
      constraints items: [max_length: 50], max_length: 20
    end

    attribute :quality_score, :decimal do
      description "Quality assessment score (0.0-1.0)"
      allow_nil? true
      constraints min: 0.0, max: 1.0, precision: 3, scale: 2
    end

    attribute :complexity_score, :decimal do
      description "Work complexity assessment (0.0-1.0)"
      allow_nil? true
      constraints min: 0.0, max: 1.0, precision: 3, scale: 2
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :coding_assistant, RubberDuck.WorkSummaries.Resources.CodingAssistant do
      description "The coding assistant that performed the work"
      allow_nil? false
    end

    belongs_to :work_session, RubberDuck.WorkSummaries.Resources.WorkSession do
      description "Work session this summary belongs to"
      allow_nil? true
    end
  end

  actions do
    defaults [:read]

    create :create do
      description "Create a new work summary"
      
      accept [
        :content,
        :summary_type,
        :title, 
        :current_project,
        :provider_used,
        :model_used,
        :work_duration_minutes,
        :metadata,
        :tags,
        :quality_score,
        :complexity_score,
        :coding_assistant_id,
        :work_session_id
      ]

      validate present([:content, :title, :coding_assistant_id])
      validate match(:summary_type, ~r/^[a-z_]+$/)
    end

    update :update do
      description "Update an existing work summary"
      
      accept [
        :content,
        :title,
        :metadata,
        :tags,
        :quality_score,
        :complexity_score
      ]
    end

    destroy :archive do
      description "Archive (soft delete) a work summary"
      soft? true
    end

    read :by_assistant do
      description "Get summaries by coding assistant"
      
      argument :assistant_id, :uuid do
        allow_nil? false
      end
      
      filter expr(coding_assistant_id == ^arg(:assistant_id))
    end

    read :by_project do
      description "Get summaries by project"
      
      argument :project_name, :string do
        allow_nil? false
      end
      
      filter expr(current_project == ^arg(:project_name))
    end

    read :by_date_range do
      description "Get summaries within date range"
      
      argument :start_date, :utc_datetime_usec do
        allow_nil? false
      end
      
      argument :end_date, :utc_datetime_usec do
        allow_nil? false
      end
      
      filter expr(generated_at >= ^arg(:start_date) and generated_at <= ^arg(:end_date))
    end

    read :by_type do
      description "Get summaries by work type"
      
      argument :summary_type, :atom do
        allow_nil? false
      end
      
      filter expr(summary_type == ^arg(:summary_type))
    end

    read :search_content do
      description "Search summaries by content"
      
      argument :search_term, :string do
        allow_nil? false
      end
      
      # Full-text search on content and title
      filter expr(
        ilike(content, ^arg(:search_term)) or 
        ilike(title, ^arg(:search_term))
      )
    end

    read :recent_summaries do
      description "Get recent summaries with pagination"
      
      argument :limit, :integer do
        allow_nil? true
        default 50
      end
      
      # Sort by generated_at descending
      pagination offset?: true, default_limit: 50
    end
  end

  calculations do
    calculate :content_word_count, :integer, expr(
      length(string_to_array(content, ~c" "))
    ) do
      description "Word count of summary content"
    end

    calculate :days_since_generated, :integer, expr(
      date_part("day", now() - generated_at)
    ) do
      description "Days since summary was generated"
    end

    calculate :has_metadata, :boolean, expr(
      jsonb_array_length(metadata) > 0
    ) do
      description "Whether summary has additional metadata"
    end
  end

  validations do
    validate present(:content, message: "Summary content is required")
    validate present(:title, message: "Summary title is required")
    
    validate string_length(:content, min: 10, max: 50_000, 
      message: "Content must be between 10 and 50,000 characters")
    
    validate string_length(:title, min: 5, max: 200,
      message: "Title must be between 5 and 200 characters")
    
    validate numericality(:quality_score, 
      greater_than_or_equal_to: 0.0, 
      less_than_or_equal_to: 1.0,
      message: "Quality score must be between 0.0 and 1.0")
    
    validate numericality(:complexity_score,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0, 
      message: "Complexity score must be between 0.0 and 1.0")
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if always()  # Will be restricted based on user context in production
    end
  end

  preparations do
    prepare build(sort: [generated_at: :desc])
  end

  # Aggregates will be defined on related resources
end