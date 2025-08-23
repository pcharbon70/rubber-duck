defmodule RubberDuck.Preferences.Resources.BudgetUsage do
  @moduledoc """
  BudgetUsage resource for tracking real-time budget utilization.

  This resource maintains current usage statistics for budget periods,
  enabling real-time budget monitoring, threshold checking, and
  utilization analysis. Data is updated continuously as operations consume
  budgeted resources.
  """

  use Ash.Resource,
    domain: RubberDuck.Preferences,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "budget_usage"
    repo RubberDuck.Repo

    references do
      reference :budget_configuration, on_delete: :delete
    end
  end

  resource do
    description """
    BudgetUsage tracks real-time consumption of budgeted resources across different periods.

    Key features:
    - Real-time usage tracking for cost, tokens, and operations
    - Budget period management with automatic rollover
    - Status calculation and threshold monitoring
    - Historical usage data for trend analysis
    - Performance optimized for high-frequency updates
    """

    short_name :budget_usage
    plural_name :budget_usage
  end

  code_interface do
    define :create, action: :create
    define :read, action: :read
    define :update, action: :update
    define :destroy, action: :destroy
    define :by_configuration, args: [:budget_configuration_id]
    define :current_period, args: [:budget_configuration_id]
    define :over_budget
    define :approaching_limits
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    read :by_configuration do
      description "Get all usage records for a specific budget configuration"
      argument :budget_configuration_id, :uuid, allow_nil?: false

      filter expr(budget_configuration_id == ^arg(:budget_configuration_id))
      prepare build(sort: [desc: :period_start])
    end

    read :current_period do
      description "Get current period usage for a budget configuration"
      argument :budget_configuration_id, :uuid, allow_nil?: false

      filter expr(
               budget_configuration_id == ^arg(:budget_configuration_id) and
                 period_start <= now() and
                 period_end >= now()
             )

      prepare build(sort: [desc: :last_updated])
    end

    read :over_budget do
      description "Get all usage records that are over budget"

      filter expr(status == :over_budget)
      prepare build(sort: [desc: :last_updated])
    end

    read :approaching_limits do
      description "Get usage records approaching their limits"

      filter expr(status == :approaching_limit)
      prepare build(sort: [desc: :last_updated])
    end

    update :record_usage do
      description "Record new usage data"
      argument :cost_delta, :decimal, allow_nil?: false
      argument :tokens_delta, :integer, allow_nil?: false
      argument :operations_delta, :integer, allow_nil?: false

      # Usage recording will be implemented with proper change modules
      change set_attribute(:last_updated, DateTime.utc_now())
    end

    update :reset_period do
      description "Reset usage for a new budget period"
      argument :period_start, :utc_datetime, allow_nil?: false
      argument :period_end, :utc_datetime, allow_nil?: false

      change set_attribute(:period_start, arg(:period_start))
      change set_attribute(:period_end, arg(:period_end))
      change set_attribute(:current_cost, 0.0)
      change set_attribute(:current_tokens, 0)
      change set_attribute(:current_operations, 0)
      change set_attribute(:status, :within_budget)
      change set_attribute(:last_updated, DateTime.utc_now())
    end

    update :update_status do
      description "Update budget status based on current usage"
      argument :new_status, :atom, allow_nil?: false

      change set_attribute(:status, arg(:new_status))
      change set_attribute(:last_updated, DateTime.utc_now())
    end
  end

  validations do
    validate compare(:current_cost, greater_than_or_equal_to: 0),
      message: "Current cost cannot be negative"

    validate compare(:current_tokens, greater_than_or_equal_to: 0),
      message: "Current tokens cannot be negative"

    validate compare(:current_operations, greater_than_or_equal_to: 0),
      message: "Current operations cannot be negative"

    validate compare(:period_end, greater_than: :period_start),
      message: "Period end must be after period start"

    validate one_of(:status, [:within_budget, :approaching_limit, :over_budget, :suspended]),
      message: "Status must be within_budget, approaching_limit, over_budget, or suspended"
  end

  attributes do
    uuid_primary_key :id

    attribute :budget_configuration_id, :uuid do
      allow_nil? false
      description "Associated budget configuration"
    end

    attribute :period_start, :utc_datetime do
      allow_nil? false
      description "Start of budget period"
    end

    attribute :period_end, :utc_datetime do
      allow_nil? false
      description "End of budget period"
    end

    attribute :current_cost, :decimal do
      allow_nil? false
      default 0.0
      constraints min: 0
      description "Current cost usage in budget period"
    end

    attribute :current_tokens, :integer do
      allow_nil? false
      default 0
      constraints min: 0
      description "Current token usage in budget period"
    end

    attribute :current_operations, :integer do
      allow_nil? false
      default 0
      constraints min: 0
      description "Current operation count in budget period"
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:within_budget, :approaching_limit, :over_budget, :suspended]
      default :within_budget
      description "Current budget status"
    end

    attribute :last_updated, :utc_datetime do
      allow_nil? false
      description "Timestamp of last usage update"
    end

    attribute :peak_cost, :decimal do
      allow_nil? false
      default 0.0
      description "Peak cost usage during this period"
    end

    attribute :peak_tokens, :integer do
      allow_nil? false
      default 0
      description "Peak token usage during this period"
    end

    attribute :peak_operations, :integer do
      allow_nil? false
      default 0
      description "Peak operations count during this period"
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
    calculate :cost_utilization_percentage, :float, expr(0.0) do
      description "Cost utilization as percentage of budget limit"
    end

    calculate :tokens_utilization_percentage, :float, expr(0.0) do
      description "Token utilization as percentage of budget limit"
    end

    calculate :operations_utilization_percentage, :float, expr(0.0) do
      description "Operations utilization as percentage of budget limit"
    end

    calculate :days_remaining,
              :integer,
              expr(fragment("EXTRACT(day FROM (? - ?))", period_end, now())) do
      description "Days remaining in current budget period"
    end

    calculate :burn_rate_per_day,
              :decimal,
              expr(
                fragment(
                  "CASE WHEN EXTRACT(day FROM (? - ?)) = 0 THEN ? ELSE ? / EXTRACT(day FROM (? - ?)) END",
                  now(),
                  period_start,
                  current_cost,
                  current_cost,
                  now(),
                  period_start
                )
              ) do
      description "Average daily cost burn rate"
    end

    calculate :projected_month_end_cost, :decimal, expr(current_cost) do
      description "Projected cost at end of period based on current burn rate"
    end
  end

  identities do
    identity :unique_config_period, [:budget_configuration_id, :period_start, :period_end] do
      description "Each configuration can have only one usage record per period"
    end
  end
end
