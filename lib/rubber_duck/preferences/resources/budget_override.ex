defmodule RubberDuck.Preferences.Resources.BudgetOverride do
  @moduledoc """
  BudgetOverride resource for managing emergency budget increases.

  This resource handles temporary budget overrides that allow operations
  to continue when budget limits are exceeded. Includes approval workflows,
  expiration management, and audit tracking for compliance.
  """

  use Ash.Resource,
    domain: RubberDuck.Preferences,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "budget_overrides"
    repo RubberDuck.Repo

    references do
      reference :budget_configuration, on_delete: :delete
      # reference :approved_by_user, on_delete: :nilify
      # reference :requested_by_user, on_delete: :nilify
    end
  end

  resource do
    description """
    BudgetOverride manages emergency budget increases with proper approval workflows.

    Key features:
    - Emergency budget allocation for critical operations
    - Approval workflow with user attribution
    - Automatic expiration with configurable timeframes
    - Audit trail for compliance and governance
    - Multiple override types for different scenarios
    """

    short_name :budget_override
    plural_name :budget_overrides
  end

  code_interface do
    define :create, action: :create
    define :read, action: :read
    define :update, action: :update
    define :destroy, action: :destroy
    define :by_configuration, args: [:budget_configuration_id]
    define :active_overrides
    define :pending_approval
    define :expired_overrides
    define :by_approver, args: [:approved_by_user_id]
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    read :by_configuration do
      description "Get all overrides for a specific budget configuration"
      argument :budget_configuration_id, :uuid, allow_nil?: false

      filter expr(budget_configuration_id == ^arg(:budget_configuration_id))
      prepare build(sort: [desc: :created_at])
    end

    read :active_overrides do
      description "Get all currently active overrides"

      filter expr(active == true and expires_at > now())
      prepare build(sort: [desc: :created_at])
    end

    read :pending_approval do
      description "Get all overrides pending approval"

      filter expr(status == :pending_approval)
      prepare build(sort: [:created_at])
    end

    read :expired_overrides do
      description "Get all expired overrides"

      filter expr(expires_at <= now() or active == false)
      prepare build(sort: [desc: :expires_at])
    end

    read :by_approver do
      description "Get all overrides approved by a specific user"
      argument :approved_by_user_id, :uuid, allow_nil?: false

      filter expr(approved_by_user_id == ^arg(:approved_by_user_id))
      prepare build(sort: [desc: :approved_at])
    end

    create :request_override do
      description "Request a budget override"
      argument :override_reason, :string, allow_nil?: false
      argument :requested_amount, :decimal, allow_nil?: false
      argument :duration_hours, :integer, allow_nil?: false, default: 24

      change set_attribute(:override_reason, arg(:override_reason))
      change set_attribute(:override_amount, arg(:requested_amount))
      # Expires at will be set manually based on duration_hours
      # change set_attribute(:expires_at, DateTime.add(DateTime.utc_now(), arg(:duration_hours), :hour))
      change set_attribute(:status, :pending_approval)
    end

    update :approve do
      description "Approve a budget override"
      argument :approved_by_user_id, :uuid, allow_nil?: false
      argument :approval_notes, :string, allow_nil?: true

      change set_attribute(:status, :approved)
      change set_attribute(:active, true)
      change set_attribute(:approved_by_user_id, arg(:approved_by_user_id))
      change set_attribute(:approved_at, DateTime.utc_now())
      change set_attribute(:approval_notes, arg(:approval_notes))
    end

    update :reject do
      description "Reject a budget override request"
      argument :rejected_by_user_id, :uuid, allow_nil?: false
      argument :rejection_reason, :string, allow_nil?: false

      change set_attribute(:status, :rejected)
      change set_attribute(:active, false)
      change set_attribute(:approved_by_user_id, arg(:rejected_by_user_id))
      change set_attribute(:approved_at, DateTime.utc_now())
      change set_attribute(:approval_notes, arg(:rejection_reason))
    end

    update :revoke do
      description "Revoke an active override"
      argument :revoked_by_user_id, :uuid, allow_nil?: false
      argument :revocation_reason, :string, allow_nil?: false

      change set_attribute(:status, :revoked)
      change set_attribute(:active, false)
      change set_attribute(:revoked_at, DateTime.utc_now())
      change set_attribute(:revocation_reason, arg(:revocation_reason))
    end

    update :expire do
      description "Mark override as expired"
      change set_attribute(:status, :expired)
      change set_attribute(:active, false)
    end

    update :extend do
      description "Extend override expiration"
      argument :additional_hours, :integer, allow_nil?: false
      argument :extended_by_user_id, :uuid, allow_nil?: false

      # Extension logic will be implemented with proper change modules
      # Extension count increment will be handled by proper change logic
    end
  end

  validations do
    validate compare(:override_amount, greater_than: 0),
      message: "Override amount must be positive"

    validate compare(:expires_at, greater_than: :created_at),
      message: "Expiration must be after creation time"

    validate one_of(:override_type, [:emergency, :planned, :temporary, :maintenance]),
      message: "Override type must be emergency, planned, temporary, or maintenance"

    validate one_of(:status, [:pending_approval, :approved, :rejected, :expired, :revoked]),
      message: "Invalid status"

    validate present(:override_reason),
      message: "Override reason must be provided"

    validate compare(:extension_count, less_than_or_equal_to: 5),
      message: "Cannot extend override more than 5 times"
  end

  attributes do
    uuid_primary_key :id

    attribute :budget_configuration_id, :uuid do
      allow_nil? false
      description "Associated budget configuration"
    end

    attribute :override_type, :atom do
      allow_nil? false
      constraints one_of: [:emergency, :planned, :temporary, :maintenance]
      default :emergency
      description "Type of budget override"
    end

    attribute :override_amount, :decimal do
      allow_nil? false
      constraints min: 0
      description "Additional budget amount granted"
    end

    attribute :override_reason, :string do
      allow_nil? false
      description "Reason for requesting the override"
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:pending_approval, :approved, :rejected, :expired, :revoked]
      default :pending_approval
      description "Current override status"
    end

    attribute :active, :boolean do
      allow_nil? false
      default false
      description "Whether this override is currently active"
    end

    attribute :expires_at, :utc_datetime do
      allow_nil? false
      description "When this override expires"
    end

    attribute :requested_by_user_id, :uuid do
      allow_nil? true
      description "User who requested the override"
    end

    attribute :approved_by_user_id, :uuid do
      allow_nil? true
      description "User who approved/rejected the override"
    end

    attribute :approved_at, :utc_datetime do
      allow_nil? true
      description "When the override was approved/rejected"
    end

    attribute :approval_notes, :string do
      allow_nil? true
      description "Notes from the approver"
    end

    attribute :revoked_at, :utc_datetime do
      allow_nil? true
      description "When the override was revoked"
    end

    attribute :revocation_reason, :string do
      allow_nil? true
      description "Reason for revoking the override"
    end

    attribute :usage_amount, :decimal do
      allow_nil? false
      default 0.0
      description "Amount of override budget actually used"
    end

    attribute :extension_count, :integer do
      allow_nil? false
      default 0
      description "Number of times this override has been extended"
    end

    timestamps()
  end

  relationships do
    belongs_to :budget_configuration, RubberDuck.Preferences.Resources.BudgetConfiguration do
      allow_nil? false
      description "Parent budget configuration"
    end

    # belongs_to :requested_by_user, RubberDuck.Accounts.User do
    #   allow_nil? true
    #   description "User who requested the override"
    # end

    # belongs_to :approved_by_user, RubberDuck.Accounts.User do
    #   allow_nil? true
    #   description "User who approved/rejected the override"
    # end
  end

  calculations do
    calculate :hours_remaining,
              :integer,
              expr(fragment("EXTRACT(epoch FROM (? - ?)) / 3600", expires_at, now())) do
      description "Hours remaining until expiration"
    end

    calculate :is_expired, :boolean, expr(expires_at <= now()) do
      description "Whether this override has expired"
    end

    calculate :utilization_percentage,
              :float,
              expr(
                fragment(
                  "CASE WHEN ? = 0 THEN 0 ELSE (? / ?) * 100 END",
                  override_amount,
                  usage_amount,
                  override_amount
                )
              ) do
      description "Percentage of override amount used"
    end

    calculate :remaining_amount, :decimal, expr(override_amount - usage_amount) do
      description "Remaining override budget"
    end

    calculate :days_since_approval,
              :integer,
              expr(
                fragment(
                  "CASE WHEN ? IS NULL THEN NULL ELSE EXTRACT(day FROM (? - ?)) END",
                  approved_at,
                  now(),
                  approved_at
                )
              ) do
      description "Days since override was approved"
    end
  end

  identities do
    # No unique constraints - multiple overrides can exist per configuration
  end
end
