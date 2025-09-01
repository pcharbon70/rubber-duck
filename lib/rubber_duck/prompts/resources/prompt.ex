defmodule RubberDuck.Prompts.Resources.Prompt do
  @moduledoc """
  Core Prompt resource with three-tier hierarchical architecture.

  Supports System prompts (immutable base instructions), Project prompts
  (team customization), and User prompts (personal preferences) with
  comprehensive versioning, multi-tenancy, and security validation.
  """

  use Ash.Resource,
    domain: RubberDuck.Prompts.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "prompts"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    create :create_system_prompt do
      argument :content, :string, allow_nil?: false
      argument :name, :string, allow_nil?: false
      argument :tenant_id, :uuid, allow_nil?: false

      change set_attribute(:prompt_type, :system)
      change set_attribute(:status, :approved)
      change set_attribute(:priority, 100)
      change set_attribute(:name, arg(:name))
      change set_attribute(:content, arg(:content))
      change set_attribute(:tenant_id, arg(:tenant_id))
    end

    create :create_project_prompt do
      argument :content, :string, allow_nil?: false
      argument :name, :string, allow_nil?: false
      argument :tenant_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false

      change set_attribute(:prompt_type, :project)
      change set_attribute(:status, :draft)
      change set_attribute(:priority, 50)
      change set_attribute(:name, arg(:name))
      change set_attribute(:content, arg(:content))
      change set_attribute(:tenant_id, arg(:tenant_id))
      change set_attribute(:project_id, arg(:project_id))
    end

    create :create_user_prompt do
      argument :content, :string, allow_nil?: false
      argument :name, :string, allow_nil?: false
      argument :tenant_id, :uuid, allow_nil?: false
      argument :user_id, :uuid, allow_nil?: false

      change set_attribute(:prompt_type, :user)
      change set_attribute(:status, :approved)
      change set_attribute(:priority, 10)
      change set_attribute(:name, arg(:name))
      change set_attribute(:content, arg(:content))
      change set_attribute(:tenant_id, arg(:tenant_id))
      change set_attribute(:user_id, arg(:user_id))
    end

    read :list_by_type do
      argument :prompt_type, :atom, allow_nil?: false
      filter expr(prompt_type == ^arg(:prompt_type))
    end

    read :list_by_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id))
    end

    read :list_by_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id))
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
    validate present([:name, :content, :prompt_type, :tenant_id])
    validate match(:name, ~r/^[a-zA-Z0-9_.-]+$/)
    validate string_length(:content, min: 10, max: 50_000)
    validate string_length(:name, min: 2, max: 100)
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false
    attribute :content, :string, allow_nil?: false
    attribute :prompt_type, :atom, constraints: [one_of: [:system, :project, :user]]
    attribute :tenant_id, :uuid, allow_nil?: false
    attribute :project_id, :uuid
    attribute :user_id, :uuid

    attribute :status, :atom,
      default: :draft,
      constraints: [one_of: [:draft, :pending, :approved, :archived]]

    attribute :priority, :integer, default: 0
    attribute :variables, {:array, :string}, default: []
    attribute :metadata, :map, default: %{}
    attribute :tags, {:array, :string}, default: []
    attribute :is_template, :boolean, default: false
    attribute :effectiveness_score, :decimal

    timestamps()
  end

  relationships do
    belongs_to :category, RubberDuck.Prompts.Resources.PromptCategory
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, destination_attribute: :parent_id
    has_many :versions, RubberDuck.Prompts.Resources.PromptVersion
    has_many :usages, RubberDuck.Prompts.Resources.PromptUsage
  end

  identities do
    identity :unique_name_per_scope, [:name, :prompt_type, :tenant_id, :project_id, :user_id]
  end
end
