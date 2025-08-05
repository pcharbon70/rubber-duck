defmodule RubberDuck.Projects.CodeFile do
  @moduledoc """
  CodeFile resource representing individual code files within a project.

  Stores information about code files including their path, content,
  programming language, size, and status. Code files belong to a project
  and can have associated analysis results.
  """

  use Ash.Resource,
    domain: RubberDuck.Projects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "code_files"
    repo RubberDuck.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :path, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 500
    end

    attribute :content, :string do
      allow_nil? true
    end

    attribute :language, :string do
      allow_nil? true
      constraints max_length: 50
    end

    attribute :size_bytes, :integer do
      allow_nil? true
      constraints min: 0
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      constraints one_of: [:active, :modified, :deleted]
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, RubberDuck.Projects.Project do
      allow_nil? false
      attribute_type :uuid
    end

    has_many :analysis_results, RubberDuck.AI.AnalysisResult
  end

  actions do
    defaults [:read]

    create :create do
      accept [:path, :content, :language, :size_bytes, :project_id]
    end

    update :update do
      accept [:path, :content, :language, :status]
    end

    destroy :destroy do
      change set_attribute(:status, :deleted)
      soft? true
    end

    read :by_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id))
    end

    read :active do
      filter expr(status == :active)
    end
  end

  policies do
    # Bypass for system/admin operations
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Users can create code files if they own the project
    policy action_type(:create) do
      authorize_if always()
    end

    # Users can only see and manage code files in their own projects
    policy action_type(:read) do
      authorize_if relates_to_actor_via([:project, :owner])
    end

    policy action_type([:update, :destroy]) do
      authorize_if relates_to_actor_via([:project, :owner])
    end
  end

end
