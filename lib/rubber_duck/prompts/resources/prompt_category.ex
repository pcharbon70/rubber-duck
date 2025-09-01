defmodule RubberDuck.Prompts.Resources.PromptCategory do
  @moduledoc """
  Category organization resource for hierarchical prompt management.
  
  Organizes prompts by functional categories with nested hierarchy support,
  category-based access control, and usage tracking.
  """

  use Ash.Resource,
    domain: RubberDuck.Prompts.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "prompt_categories"
    repo RubberDuck.Repo
  end

  attributes do
    uuid_primary_key :id
    
    attribute :name, :string, allow_nil?: false
    attribute :description, :string
    attribute :slug, :string, allow_nil?: false
    attribute :tenant_id, :uuid, allow_nil?: false
    attribute :category_type, :atom, allow_nil?: false, default: :general, constraints: [one_of: [:system, :project, :user, :general, :template]]
    attribute :access_level, :atom, allow_nil?: false, default: :public, constraints: [one_of: [:public, :private, :restricted, :admin_only]]
    attribute :sort_order, :integer, default: 0
    attribute :color_code, :string
    attribute :icon, :string
    attribute :metadata, :map, default: %{}
    attribute :usage_count, :integer, default: 0
    attribute :popularity_score, :decimal
    attribute :is_template_category, :boolean, default: false
    attribute :tags, {:array, :string}, default: []
    
    timestamps()
  end

  relationships do
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, destination_attribute: :parent_id
    has_many :prompts, RubberDuck.Prompts.Resources.Prompt, destination_attribute: :category_id
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    read :list_top_level do
      filter expr(is_nil(parent_id))
    end

    read :list_by_parent do
      argument :parent_id, :uuid, allow_nil?: false
      filter expr(parent_id == ^arg(:parent_id))
    end

    read :list_by_type do
      argument :category_type, :atom, allow_nil?: false
      filter expr(category_type == ^arg(:category_type))
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  validations do
    validate present([:name, :slug, :tenant_id, :category_type, :access_level])
    validate match(:name, ~r/^[a-zA-Z0-9\s_.-]+$/)
    validate match(:slug, ~r/^[a-z0-9-]+$/)
    validate string_length(:name, min: 2, max: 100)
    validate string_length(:slug, min: 2, max: 100)
  end

  identities do
    identity :unique_slug_per_tenant, [:slug, :tenant_id]
  end
end