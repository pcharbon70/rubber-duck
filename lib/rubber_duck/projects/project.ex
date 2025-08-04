defmodule RubberDuck.Projects.Project do
  @moduledoc """
  Project resource representing a coding project in RubberDuck.
  
  A project contains metadata about a user's coding project including
  name, description, programming language, and status. Projects can
  contain multiple code files and analysis results.
  """

  use Ash.Resource,
    domain: RubberDuck.Projects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "projects"
    repo RubberDuck.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255
    end

    attribute :description, :string do
      allow_nil? true
      constraints max_length: 1000
    end

    attribute :language, :string do
      allow_nil? true
      constraints max_length: 50
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      constraints one_of: [:active, :archived, :deleted]
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :owner, RubberDuck.Accounts.User do
      allow_nil? false
      attribute_type :uuid
    end

    has_many :code_files, RubberDuck.Projects.CodeFile
    has_many :analysis_results, RubberDuck.AI.AnalysisResult
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :description, :language]
      
      change relate_actor(:owner)
    end

    update :update do
      accept [:name, :description, :language, :status]
    end

    destroy :destroy do
      change set_attribute(:status, :deleted)
      soft? true
    end

    read :by_owner do
      filter expr(owner_id == ^actor(:id))
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

    # Users can create projects - they will be set as owner automatically
    policy action_type(:create) do
      authorize_if always()
    end

    # Users can only see and manage their own projects
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:owner)
    end

    policy action_type([:update, :destroy]) do
      authorize_if relates_to_actor_via(:owner)
    end
  end

end