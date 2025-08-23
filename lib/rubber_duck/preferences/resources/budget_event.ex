defmodule RubberDuck.Preferences.Resources.BudgetEvent do
  @moduledoc """
  BudgetEvent resource for audit trail and event logging.

  This resource tracks all significant budget-related events including
  threshold crossings, limit breaches, alert deliveries, and administrative
  actions. Provides comprehensive audit trail for compliance and analysis.
  """

  use Ash.Resource,
    domain: RubberDuck.Preferences,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "budget_events"
    repo RubberDuck.Repo

    references do
      reference :budget_configuration, on_delete: :delete
      # reference :user, on_delete: :nilify
    end
  end

  resource do
    description """
    BudgetEvent provides comprehensive audit logging for all budget-related activities.

    Key features:
    - Complete audit trail of budget events
    - Rich event data with context information
    - User attribution for administrative actions
    - Searchable event history
    - Automatic event classification and tagging
    """

    short_name :budget_event
    plural_name :budget_events
  end

  code_interface do
    define :create, action: :create
    define :read, action: :read
    define :update, action: :update
    define :destroy, action: :destroy
    define :by_configuration, args: [:budget_configuration_id]
    define :by_event_type, args: [:event_type]
    define :recent_events, args: [:hours]
    define :by_user, args: [:user_id]
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    read :by_configuration do
      description "Get all events for a specific budget configuration"
      argument :budget_configuration_id, :uuid, allow_nil?: false

      filter expr(budget_configuration_id == ^arg(:budget_configuration_id))
      prepare build(sort: [desc: :occurred_at])
    end

    read :by_event_type do
      description "Get all events of a specific type"
      argument :event_type, :atom, allow_nil?: false

      filter expr(event_type == ^arg(:event_type))
      prepare build(sort: [desc: :occurred_at])
    end

    read :recent_events do
      description "Get events from the last N hours"
      argument :hours, :integer, allow_nil?: false, default: 24

      filter expr(occurred_at >= ago(^arg(:hours), :hour))
      prepare build(sort: [desc: :occurred_at])
    end

    read :by_user do
      description "Get all events triggered by a specific user"
      argument :user_id, :uuid, allow_nil?: false

      filter expr(triggered_by_user_id == ^arg(:user_id))
      prepare build(sort: [desc: :occurred_at])
    end

    create :log_threshold_crossed do
      description "Log a budget threshold crossing event"
      argument :threshold_percentage, :integer, allow_nil?: false
      argument :current_usage, :decimal, allow_nil?: false
      argument :limit_value, :decimal, allow_nil?: false

      change set_attribute(:event_type, :threshold_crossed)

      change set_attribute(:event_data, %{
               threshold_percentage: arg(:threshold_percentage),
               current_usage: arg(:current_usage),
               limit_value: arg(:limit_value)
             })

      change set_attribute(:occurred_at, DateTime.utc_now())
    end

    create :log_budget_exceeded do
      description "Log a budget limit exceeded event"
      argument :limit_type, :atom, allow_nil?: false
      argument :current_usage, :decimal, allow_nil?: false
      argument :limit_value, :decimal, allow_nil?: false

      change set_attribute(:event_type, :budget_exceeded)

      change set_attribute(:event_data, %{
               limit_type: arg(:limit_type),
               current_usage: arg(:current_usage),
               limit_value: arg(:limit_value)
             })

      change set_attribute(:severity, :high)
      change set_attribute(:occurred_at, DateTime.utc_now())
    end

    create :log_alert_sent do
      description "Log an alert delivery event"
      argument :alert_type, :atom, allow_nil?: false
      argument :recipients, {:array, :string}, allow_nil?: false
      argument :delivery_status, :atom, allow_nil?: false

      change set_attribute(:event_type, :alert_sent)

      change set_attribute(:event_data, %{
               alert_type: arg(:alert_type),
               recipients: arg(:recipients),
               delivery_status: arg(:delivery_status)
             })

      change set_attribute(:occurred_at, DateTime.utc_now())
    end
  end

  validations do
    validate one_of(:event_type, [
               :threshold_crossed,
               :budget_exceeded,
               :alert_sent,
               :budget_reset,
               :limit_updated,
               :configuration_changed,
               :override_granted,
               :override_expired,
               :period_rollover,
               :enforcement_action,
               :usage_spike,
               :usage_anomaly
             ]),
             message: "Invalid event type"

    validate one_of(:severity, [:low, :medium, :high, :critical]),
      message: "Severity must be low, medium, high, or critical"

    validate present(:event_data),
      message: "Event data must be provided"
  end

  attributes do
    uuid_primary_key :id

    attribute :budget_configuration_id, :uuid do
      allow_nil? false
      description "Associated budget configuration"
    end

    attribute :event_type, :atom do
      allow_nil? false

      constraints one_of: [
                    :threshold_crossed,
                    :budget_exceeded,
                    :alert_sent,
                    :budget_reset,
                    :limit_updated,
                    :configuration_changed,
                    :override_granted,
                    :override_expired,
                    :period_rollover,
                    :enforcement_action,
                    :usage_spike,
                    :usage_anomaly
                  ]

      description "Type of budget event"
    end

    attribute :event_data, :map do
      allow_nil? false
      description "Event-specific data and context"
    end

    attribute :severity, :atom do
      allow_nil? false
      constraints one_of: [:low, :medium, :high, :critical]
      default :medium
      description "Event severity level"
    end

    attribute :triggered_by, :string do
      allow_nil? true
      description "System component or process that triggered the event"
    end

    attribute :triggered_by_user_id, :uuid do
      allow_nil? true
      description "User who triggered the event (for administrative actions)"
    end

    attribute :occurred_at, :utc_datetime do
      allow_nil? false
      description "When the event occurred"
    end

    attribute :correlation_id, :string do
      allow_nil? true
      description "Correlation ID for tracking related events"
    end

    attribute :tags, {:array, :string} do
      allow_nil? true
      description "Tags for categorizing and searching events"
    end

    attribute :resolved, :boolean do
      allow_nil? false
      default false
      description "Whether this event has been resolved or acknowledged"
    end

    attribute :resolved_at, :utc_datetime do
      allow_nil? true
      description "When the event was resolved"
    end

    attribute :resolved_by_user_id, :uuid do
      allow_nil? true
      description "User who resolved the event"
    end

    timestamps()
  end

  relationships do
    belongs_to :budget_configuration, RubberDuck.Preferences.Resources.BudgetConfiguration do
      allow_nil? false
      description "Parent budget configuration"
    end

    # belongs_to :triggered_by_user, RubberDuck.Accounts.User do
    #   allow_nil? true
    #   description "User who triggered the event"
    # end

    # belongs_to :resolved_by_user, RubberDuck.Accounts.User do
    #   allow_nil? true
    #   description "User who resolved the event"
    # end
  end

  calculations do
    calculate :age_in_hours,
              :integer,
              expr(fragment("EXTRACT(epoch FROM (? - ?)) / 3600", now(), occurred_at)) do
      description "Hours since the event occurred"
    end

    calculate :is_recent, :boolean, expr(occurred_at >= ago(24, :hour)) do
      description "Whether event occurred within last 24 hours"
    end

    calculate :is_critical_unresolved,
              :boolean,
              expr(severity == :critical and resolved == false) do
      description "Whether this is an unresolved critical event"
    end
  end

  # aggregates do
  #   # Aggregates will be implemented after core functionality is working
  # end

  identities do
    # No unique constraints - events can be duplicated for audit purposes
  end
end
