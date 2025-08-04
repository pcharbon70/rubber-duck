defmodule RubberDuck.AI.Prompt do
  @moduledoc """
  Prompt resource for storing and managing AI prompt templates.
  
  Allows users to create, share, and manage reusable prompt templates
  with variables, categories, and usage tracking. Prompts can be
  private or public for sharing with other users.
  """

  use Ash.Resource,
    domain: RubberDuck.AI,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "prompts"
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

    attribute :template, :string do
      allow_nil? false
    end

    attribute :variables, {:array, :string} do
      allow_nil? true
      default []
    end

    attribute :category, :string do
      allow_nil? true
      constraints max_length: 50
    end

    attribute :tags, {:array, :string} do
      allow_nil? true
      default []
    end

    attribute :version, :string do
      allow_nil? false
      default "1.0.0"
      constraints max_length: 20
    end

    attribute :is_public, :boolean do
      allow_nil? false
      default false
    end

    attribute :usage_count, :integer do
      allow_nil? false
      default 0
      constraints min: 0
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :author, RubberDuck.Accounts.User do
      allow_nil? false
      attribute_type :uuid
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :description, :template, :variables, :category, :tags, :version, :is_public]

      change relate_actor(:author)
    end

    update :update do
      accept [:name, :description, :template, :variables, :category, :tags, :version, :is_public]
    end

    update :increment_usage do
      change atomic_update(:usage_count, expr(usage_count + 1))
    end

    destroy :destroy

    read :by_author do
      filter expr(author_id == ^actor(:id))
    end

    read :public do
      filter expr(is_public == true)
    end

    read :by_category do
      argument :category, :string, allow_nil?: false
      filter expr(category == ^arg(:category))
    end

    read :by_tag do
      argument :tag, :string, allow_nil?: false
      filter expr(^arg(:tag) in tags)
    end

    read :search do
      argument :search_term, :string, allow_nil?: false
      prepare build(filter: [
        or: [
          [name: [ilike: arg(:search_term)]],
          [description: [ilike: arg(:search_term)]]
        ]
      ])
    end
  end

  policies do
    # Bypass for system/admin operations
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Users can create prompts - they will be set as author automatically
    policy action_type(:create) do
      authorize_if always()
    end

    # Read policies - users can see their own prompts and public prompts
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:author)
      authorize_if expr(is_public == true)
    end

    # Update/Delete policies - users can only manage their own prompts
    policy action_type([:update, :destroy]) do
      authorize_if relates_to_actor_via(:author)
    end
  end

end