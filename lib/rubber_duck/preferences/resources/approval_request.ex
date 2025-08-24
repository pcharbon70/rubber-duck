defmodule RubberDuck.Preferences.Resources.ApprovalRequest do
  @moduledoc """
  Approval request resource for managing preference change approvals.

  Handles workflow-based approval processes for sensitive preference changes,
  delegated access requests, and other security-sensitive operations.
  """

  use Ash.Resource,
    domain: RubberDuck.Preferences,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "approval_requests"
    repo RubberDuck.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :request_type, :atom do
      description "Type of approval request"
      constraints one_of: [:preference_change, :delegation_grant, :policy_override, :emergency_access]
      allow_nil? false
    end

    attribute :requester_id, :uuid do
      description "ID of user requesting the approval"
      allow_nil? false
    end

    attribute :target_resource_type, :string do
      description "Type of resource being accessed"
      constraints max_length: 100
      allow_nil? false
    end

    attribute :target_resource_id, :string do
      description "ID of specific resource (if applicable)"
      constraints max_length: 255
      allow_nil? true
    end

    attribute :preference_key, :string do
      description "Preference key for preference change requests"
      constraints max_length: 500
      allow_nil? true
    end

    attribute :requested_action, :string do
      description "Action being requested (create, update, delete, read)"
      constraints max_length: 50
      allow_nil? false
    end

    attribute :current_value, :string do
      description "Current value of the preference (if applicable)"
      constraints max_length: 5000
      allow_nil? true
    end

    attribute :requested_value, :string do
      description "Requested new value (for changes)"
      constraints max_length: 5000
      allow_nil? true
    end

    attribute :justification, :string do
      description "Business justification for the request"
      constraints max_length: 2000
      allow_nil? false
    end

    attribute :status, :atom do
      description "Current status of the approval request"
      constraints one_of: [:pending, :approved, :rejected, :expired, :cancelled]
      default :pending
    end

    attribute :priority, :atom do
      description "Priority level of the request"
      constraints one_of: [:low, :medium, :high, :critical]
      default :medium
    end

    attribute :approver_id, :uuid do
      description "ID of user who approved/rejected the request"
      allow_nil? true
    end

    attribute :approval_notes, :string do
      description "Notes from the approver"
      constraints max_length: 2000
      allow_nil? true
    end

    attribute :expires_at, :utc_datetime do
      description "When this approval request expires"
      allow_nil? true
    end

    attribute :approved_at, :utc_datetime do
      description "When the request was approved"
      allow_nil? true
    end

    attribute :metadata, :map do
      description "Additional request metadata"
      default %{}
    end

    timestamps()
  end

  relationships do
    belongs_to :requester, RubberDuck.Accounts.User do
      attribute_writable? false
      source_attribute :requester_id
      destination_attribute :id
    end

    belongs_to :approver, RubberDuck.Accounts.User do
      attribute_writable? false
      source_attribute :approver_id
      destination_attribute :id
    end
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      description "Create a new approval request"

      accept [
        :request_type, :requester_id, :target_resource_type, :target_resource_id,
        :preference_key, :requested_action, :current_value, :requested_value,
        :justification, :priority, :expires_at, :metadata
      ]

      validate present([:request_type, :requester_id, :target_resource_type, :requested_action, :justification])

      change fn changeset, _context ->
        # Set default expiration if not provided
        if is_nil(Ash.Changeset.get_attribute(changeset, :expires_at)) do
          default_expiry = DateTime.add(DateTime.utc_now(), 7 * 24 * 3600, :second)  # 7 days
          Ash.Changeset.change_attribute(changeset, :expires_at, default_expiry)
        else
          changeset
        end
      end
    end

    update :approve do
      description "Approve an approval request"

      accept [:approver_id, :approval_notes]

      validate present(:approver_id)

      change set_attribute(:status, :approved)
      change set_attribute(:approved_at, &DateTime.utc_now/0)
    end

    update :reject do
      description "Reject an approval request"

      accept [:approver_id, :approval_notes]

      validate present([:approver_id, :approval_notes])

      change set_attribute(:status, :rejected)
      change set_attribute(:approved_at, &DateTime.utc_now/0)
    end

    update :cancel do
      description "Cancel an approval request"
      change set_attribute(:status, :cancelled)
    end
  end

  preparations do
    prepare build(sort: [inserted_at: :desc])
  end

  code_interface do
    define :create, action: :create
    define :read, action: :read
    define :update, action: :update
    define :destroy, action: :destroy
    define :approve, action: :approve
    define :reject, action: :reject
    define :cancel, action: :cancel
    define :by_requester, args: [:requester_id], action: :read
    define :by_status, args: [:status], action: :read
    define :pending_requests, action: :read
    define :expired_requests, action: :read
  end

  calculations do
    calculate :is_expired, :boolean, expr(not is_nil(expires_at) and expires_at < ^DateTime.utc_now())
    calculate :days_since_request, :integer, expr(0)
    calculate :request_summary, :string, expr(requested_action)
  end


  # Authorization policies for approval requests
  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      description "Users can see their own requests, approvers can see requests they can approve"

      authorize_if expr(requester_id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :security_admin)
      authorize_if actor_attribute_equals(:role, :project_admin)
    end

    policy action_type(:create) do
      description "Authenticated users can create approval requests"

      authorize_if actor_attribute_equals(:role, :user)
      authorize_if actor_attribute_equals(:role, :project_admin)
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action([:approve, :reject]) do
      description "Only designated approvers can approve/reject requests"

      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :security_admin)
      authorize_if actor_attribute_equals(:role, :project_admin)
    end

    policy action(:cancel) do
      description "Requesters can cancel their own requests"

      authorize_if expr(requester_id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action_type(:destroy) do
      description "Only security admins can delete approval requests"
      authorize_if actor_attribute_equals(:role, :security_admin)
    end
  end

end
