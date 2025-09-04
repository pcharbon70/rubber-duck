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

  alias RubberDuck.Prompts.Security.{AccessControlManager, PromptValidator}

  alias RubberDuck.Prompts.Policies.{
    PromptAccessPolicy,
    PromptApprovalPolicy,
    PromptSharingPolicy
  }

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

    update :share_prompt do
      argument :shared_with_user_id, :uuid, allow_nil?: false
      argument :permissions, {:array, :string}, default: ["read"]
      argument :expires_at, :utc_datetime

      change {RubberDuck.Prompts.Changes.SharePromptChange, []}
    end

    update :approve_prompt do
      argument :approval_comments, :string

      change set_attribute(:approval_status, "approved")
      change set_attribute(:approved_at, &DateTime.utc_now/0)
      change {RubberDuck.Prompts.Changes.ApprovalChange, []}
    end

    update :reject_prompt do
      argument :rejection_reason, :string, allow_nil?: false

      change set_attribute(:approval_status, "rejected")
      change {RubberDuck.Prompts.Changes.RejectionChange, []}
    end
  end

  policies do
    # System-level bypass for internal operations
    bypass actor_attribute_equals(:role, :system) do
      authorize_if always()
    end

    # Access control policy for read operations
    policy action_type(:read) do
      authorize_if PromptAccessPolicy
    end

    # Creation policies with approval workflow integration
    policy action_type(:create) do
      authorize_if PromptAccessPolicy
      authorize_if PromptApprovalPolicy
    end

    # Update policies with security validation
    policy action_type(:update) do
      authorize_if PromptAccessPolicy
      authorize_if PromptApprovalPolicy
    end

    # Destroy policies with enhanced authorization
    policy action_type(:destroy) do
      authorize_if PromptAccessPolicy
      authorize_if PromptApprovalPolicy
    end
  end

  validations do
    validate present([:name, :content, :prompt_type, :tenant_id])
    validate match(:name, ~r/^[a-zA-Z0-9_.-]+$/)
    validate string_length(:content, min: 10, max: 50_000)
    validate string_length(:name, min: 2, max: 100)

    # Security validations
    validate one_of(:approval_status, ["draft", "pending", "approved", "rejected", "expired"])
    validate one_of(:security_level, ["minimal", "standard", "enhanced", "maximum"])
    validate numericality(:risk_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)

    # Custom security validation
    validate RubberDuck.Prompts.Validations.SecurityValidator
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

    # Security and access control attributes
    attribute :approval_status, :string, default: "approved"
    attribute :approval_required, :boolean, default: false
    attribute :approved_by, :uuid
    attribute :approved_at, :utc_datetime
    attribute :approval_comments, :string

    attribute :security_level, :string, default: "standard"
    attribute :risk_score, :decimal, default: 0.0
    attribute :last_security_check, :utc_datetime

    attribute :access_policy, :map, default: %{}
    attribute :security_validation_results, :map, default: %{}
    attribute :content_security_hash, :string

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
