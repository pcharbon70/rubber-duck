defmodule RubberDuck.Preferences.Resources.AuditLog do
  @moduledoc """
  Audit log resource for tracking all preference operations and security events.

  Stores comprehensive audit information including user actions, system changes,
  security events, and access patterns for compliance and security monitoring.
  """

  use Ash.Resource,
    domain: RubberDuck.Preferences,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "audit_logs"
    repo RubberDuck.Repo
  end

  code_interface do
    define :create, action: :create
    define :update, action: :update
    define :read, action: :read
    define :destroy, action: :destroy
    define :by_user_id, args: [:user_id], action: :read
    define :by_preference_key, args: [:preference_key], action: :read
    define :by_event_type, args: [:event_type], action: :read
    define :recent_events, action: :read
  end

  actions do
    # Default actions
    defaults [:read, :destroy]

    create :create do
      description "Create a new audit log entry"

      accept [
        :event_type,
        :event_data,
        :user_id,
        :preference_key,
        :action,
        :ip_address,
        :user_agent,
        :session_id,
        :event_id,
        :severity,
        :metadata
      ]

      change fn changeset, _context ->
        # Automatically set severity based on event type and action
        changeset
        |> Ash.Changeset.change_attribute(:severity, determine_severity(changeset))
      end
    end

    update :update do
      description "Update audit log metadata (limited fields)"
      accept [:metadata, :severity]
    end
  end

  # Read policies for audit logs
  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      description "Users can read their own audit logs, admins can read all"

      authorize_if expr(user_id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :security_admin)
    end

    policy action_type(:create) do
      description "Only the system can create audit logs"

      # System-level creation
      authorize_if always()
    end

    policy action_type([:update, :destroy]) do
      description "Only security admins can modify audit logs"
      authorize_if actor_attribute_equals(:role, :security_admin)
    end
  end

  preparations do
    prepare build(sort: [inserted_at: :desc])
  end

  attributes do
    uuid_primary_key :id

    attribute :event_type, :string do
      description "Type of audit event (preference_change, security_event, access_event, etc.)"
      constraints max_length: 100
      allow_nil? false
    end

    attribute :event_data, :map do
      description "Complete event data as JSON"
      allow_nil? false
    end

    attribute :user_id, :uuid do
      description "ID of user who performed the action"
      allow_nil? true
    end

    attribute :preference_key, :string do
      description "Preference key affected (if applicable)"
      constraints max_length: 500
      allow_nil? true
    end

    attribute :action, :string do
      description "Action performed (create, update, delete, read, etc.)"
      constraints max_length: 50
      allow_nil? false
    end

    attribute :ip_address, :string do
      description "IP address of the request origin"

      # IPv6 length
      constraints max_length: 45
      allow_nil? true
    end

    attribute :user_agent, :string do
      description "User agent string from the request"
      constraints max_length: 1000
      allow_nil? true
    end

    attribute :session_id, :string do
      description "Session ID for request correlation"
      constraints max_length: 255
      allow_nil? true
    end

    attribute :event_id, :string do
      description "Unique event identifier for correlation"
      constraints max_length: 255
      allow_nil? false
    end

    attribute :severity, :atom do
      description "Event severity level"
      constraints one_of: [:info, :warning, :error, :critical]
      default :info
    end

    attribute :metadata, :map do
      description "Additional metadata for the event"
      default %{}
    end

    timestamps()
  end

  calculations do
    calculate :is_security_critical, :boolean, expr(severity in [:error, :critical])
    calculate :event_summary, :string, expr(event_type)
  end

  ## Private Functions

  defp determine_severity(changeset) do
    event_type = Ash.Changeset.get_attribute(changeset, :event_type)
    action = Ash.Changeset.get_attribute(changeset, :action)
    event_data = Ash.Changeset.get_attribute(changeset, :event_data) || %{}

    case {event_type, action} do
      {"security_event", _} -> determine_security_severity(event_data)
      {"preference_change", "delete"} -> :warning
      {"authorization_event", "denied"} -> :warning
      {"access_event", "failed"} -> :warning
      _ -> :info
    end
  end

  defp determine_security_severity(%{threat_level: level}) when level in ["high", "critical"],
    do: :critical

  defp determine_security_severity(%{threat_level: "medium"}), do: :error
  defp determine_security_severity(%{threat_level: "low"}), do: :warning
  defp determine_security_severity(%{unauthorized_access: true}), do: :error
  defp determine_security_severity(%{suspicious_activity: true}), do: :warning
  defp determine_security_severity(_), do: :info
end
