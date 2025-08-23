defmodule RubberDuck.Preferences.Resources.BudgetAlert do
  @moduledoc """
  BudgetAlert resource for managing budget alert configurations.

  This resource defines alert settings for budget thresholds including
  notification preferences, escalation policies, and delivery methods.
  Supports multiple alert types and customizable threshold percentages.
  """

  use Ash.Resource,
    domain: RubberDuck.Preferences,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "budget_alerts"
    repo RubberDuck.Repo

    references do
      reference :budget_configuration, on_delete: :delete
    end
  end

  resource do
    description """
    BudgetAlert manages alert configurations for budget monitoring and notifications.

    Key features:
    - Configurable threshold percentages (50%, 75%, 90%)
    - Multiple alert delivery methods (email, Slack, webhook, in-app)
    - Escalation policies with time delays
    - Rich recipient configuration
    - Alert frequency controls to prevent spam
    """

    short_name :budget_alert
    plural_name :budget_alerts
  end

  code_interface do
    define :create, action: :create
    define :read, action: :read
    define :update, action: :update
    define :destroy, action: :destroy
    define :by_configuration, args: [:budget_configuration_id]
    define :by_threshold, args: [:threshold_percentage]
    define :active_alerts
    define :escalation_enabled
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    read :by_configuration do
      description "Get all alerts for a specific budget configuration"
      argument :budget_configuration_id, :uuid, allow_nil?: false

      filter expr(budget_configuration_id == ^arg(:budget_configuration_id))
      prepare build(sort: [:threshold_percentage])
    end

    read :by_threshold do
      description "Get all alerts for a specific threshold percentage"
      argument :threshold_percentage, :integer, allow_nil?: false

      filter expr(threshold_percentage == ^arg(:threshold_percentage))
      prepare build(sort: [:alert_type])
    end

    read :active_alerts do
      description "Get all active budget alerts"

      filter expr(enabled == true)
      prepare build(sort: [:threshold_percentage, :alert_type])
    end

    read :escalation_enabled do
      description "Get all alerts with escalation enabled"

      filter expr(escalation_enabled == true)
      prepare build(sort: [:escalation_delay_minutes])
    end

    update :enable do
      description "Enable this alert"
      change set_attribute(:enabled, true)
    end

    update :disable do
      description "Disable this alert"
      change set_attribute(:enabled, false)
    end

    update :enable_escalation do
      description "Enable escalation for this alert"
      argument :delay_minutes, :integer, allow_nil?: false

      change set_attribute(:escalation_enabled, true)
      change set_attribute(:escalation_delay_minutes, arg(:delay_minutes))
    end

    update :disable_escalation do
      description "Disable escalation for this alert"
      change set_attribute(:escalation_enabled, false)
      change set_attribute(:escalation_delay_minutes, nil)
    end
  end

  validations do
    validate compare(:threshold_percentage, greater_than: 0),
      message: "Threshold percentage must be positive"

    validate compare(:threshold_percentage, less_than_or_equal_to: 100),
      message: "Threshold percentage cannot exceed 100"

    validate one_of(:alert_type, [:email, :slack, :webhook, :in_app]),
      message: "Alert type must be email, slack, webhook, or in_app"

    validate compare(:escalation_delay_minutes, greater_than: 0, when: [escalation_enabled: true]),
      message: "Escalation delay must be positive when escalation is enabled"

    validate compare(:max_alerts_per_hour, greater_than: 0),
      message: "Max alerts per hour must be positive"

    validate present(:recipient_config),
      message: "Recipient configuration must be specified"
  end

  attributes do
    uuid_primary_key :id

    attribute :budget_configuration_id, :uuid do
      allow_nil? false
      description "Associated budget configuration"
    end

    attribute :threshold_percentage, :integer do
      allow_nil? false
      constraints min: 1, max: 100
      description "Budget utilization percentage that triggers alert"
    end

    attribute :alert_type, :atom do
      allow_nil? false
      constraints one_of: [:email, :slack, :webhook, :in_app]
      description "Method for delivering the alert"
    end

    attribute :recipient_config, :map do
      allow_nil? false
      description "Configuration for alert recipients (email addresses, Slack channels, etc.)"
    end

    attribute :enabled, :boolean do
      allow_nil? false
      default true
      description "Whether this alert is currently active"
    end

    attribute :escalation_enabled, :boolean do
      allow_nil? false
      default false
      description "Whether to escalate if threshold remains exceeded"
    end

    attribute :escalation_delay_minutes, :integer do
      allow_nil? true
      constraints min: 1
      description "Minutes to wait before escalating alert"
    end

    attribute :escalation_config, :map do
      allow_nil? true
      description "Configuration for escalation recipients (managers, teams, etc.)"
    end

    attribute :max_alerts_per_hour, :integer do
      allow_nil? false
      default 4
      constraints min: 1, max: 60
      description "Maximum alerts to send per hour to prevent spam"
    end

    attribute :message_template, :string do
      allow_nil? true
      description "Custom message template for this alert"
    end

    attribute :include_forecast, :boolean do
      allow_nil? false
      default false
      description "Whether to include budget exhaustion forecast in alert"
    end

    attribute :include_recommendations, :boolean do
      allow_nil? false
      default true
      description "Whether to include cost optimization recommendations"
    end

    timestamps()
  end

  relationships do
    belongs_to :budget_configuration, RubberDuck.Preferences.Resources.BudgetConfiguration do
      allow_nil? false
      description "Parent budget configuration"
    end
  end

  calculations do
    calculate :alert_frequency_per_day, :float, expr(max_alerts_per_hour * 24.0) do
      description "Expected alerts per day at current rate"
    end

    calculate :is_high_frequency, :boolean, expr(max_alerts_per_hour > 10) do
      description "Whether this alert has high frequency settings"
    end

    calculate :has_custom_template, :boolean, expr(not is_nil(message_template)) do
      description "Whether this alert uses a custom message template"
    end
  end

  identities do
    identity :unique_config_threshold_type, [
      :budget_configuration_id,
      :threshold_percentage,
      :alert_type
    ] do
      description "Each configuration can have only one alert per threshold/type combination"
    end
  end
end
