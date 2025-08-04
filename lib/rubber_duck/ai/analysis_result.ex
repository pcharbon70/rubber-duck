defmodule RubberDuck.AI.AnalysisResult do
  @moduledoc """
  AnalysisResult resource storing results from AI-powered code analysis.
  
  Contains analysis results including type (complexity, security, style, etc.),
  summary, detailed findings, score, and suggestions. Analysis results are
  linked to projects and optionally to specific code files.
  """

  use Ash.Resource,
    domain: RubberDuck.AI,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "analysis_results"
    repo RubberDuck.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :analysis_type, :atom do
      allow_nil? false
      constraints one_of: [:complexity, :security, :style, :performance, :general]
    end

    attribute :summary, :string do
      allow_nil? true
      constraints max_length: 1000
    end

    attribute :details, :map do
      allow_nil? true
    end

    attribute :score, :decimal do
      allow_nil? true
      constraints min: 0, max: 100
    end

    attribute :suggestions, {:array, :string} do
      allow_nil? true
      default []
    end

    attribute :status, :atom do
      allow_nil? false
      default :completed
      constraints one_of: [:pending, :processing, :completed, :failed]
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, RubberDuck.Projects.Project do
      allow_nil? false
      attribute_type :uuid
    end

    belongs_to :code_file, RubberDuck.Projects.CodeFile do
      allow_nil? true
      attribute_type :uuid
    end

    belongs_to :analyzer, RubberDuck.Accounts.User do
      allow_nil? true
      attribute_type :uuid
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:analysis_type, :summary, :details, :score, :suggestions, :project_id, :code_file_id]

      change relate_actor(:analyzer)
    end

    update :update do
      accept [:summary, :details, :score, :suggestions, :status]
    end

    destroy :destroy

    read :by_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id))
    end

    read :by_code_file do
      argument :code_file_id, :uuid, allow_nil?: false
      filter expr(code_file_id == ^arg(:code_file_id))
    end

    read :by_analysis_type do
      argument :analysis_type, :atom, allow_nil?: false
      filter expr(analysis_type == ^arg(:analysis_type))
    end

    read :completed do
      filter expr(status == :completed)
    end
  end

  policies do
    # Bypass for system/admin operations
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Users can create analysis results
    policy action_type(:create) do
      authorize_if always()
    end

    # Users can only see and manage analysis results for their own projects
    policy action_type(:read) do
      authorize_if relates_to_actor_via([:project, :owner])
    end

    policy action_type([:update, :destroy]) do
      authorize_if relates_to_actor_via([:project, :owner])
    end
  end

end