defmodule RubberDuck.Preferences.Resources.BudgetLimit do
  @moduledoc """
  BudgetLimit resource for defining specific budget limits and thresholds.

  This resource stores the actual budget constraints including cost limits,
  token usage caps, operation limits, and enforcement thresholds. Each budget
  configuration can have multiple limits for different resource types.
  """

  use Ash.Resource,
    domain: RubberDuck.Preferences,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "budget_limits"
    repo RubberDuck.Repo

    references do
      reference :budget_configuration, on_delete: :delete
    end
  end

  resource do
    description """
    BudgetLimit defines specific constraints and thresholds for budget enforcement.

    Key features:
    - Multiple limit types (cost, tokens, operations)
    - Soft and hard limit thresholds
    - Grace period support for temporary overages
    - Integration with budget enforcement policies
    - Audit tracking for limit changes
    """

    short_name :budget_limit
    plural_name :budget_limits
  end

  code_interface do
    define :create, action: :create
    define :read, action: :read
    define :update, action: :update
    define :destroy, action: :destroy
    define :by_configuration, args: [:budget_configuration_id]
    define :by_limit_type, args: [:limit_type]
    define :active_limits
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    read :by_configuration do
      description "Get all budget limits for a specific configuration"
      argument :budget_configuration_id, :uuid, allow_nil?: false

      filter expr(budget_configuration_id == ^arg(:budget_configuration_id))
      prepare build(sort: [:limit_type])
    end

    read :by_limit_type do
      description "Get all budget limits of a specific type"
      argument :limit_type, :atom, allow_nil?: false

      filter expr(limit_type == ^arg(:limit_type))
      prepare build(sort: [:limit_value])
    end

    read :active_limits do
      description "Get all active budget limits"

      filter expr(active == true)
      prepare build(sort: [:limit_type, :limit_value])
    end

    update :activate do
      description "Activate this budget limit"
      change set_attribute(:active, true)
    end

    update :deactivate do
      description "Deactivate this budget limit"
      change set_attribute(:active, false)
    end

    update :update_limits do
      description "Update limit values with validation"
      argument :soft_limit, :decimal, allow_nil?: true
      argument :hard_limit, :decimal, allow_nil?: true

      change set_attribute(:soft_limit, arg(:soft_limit))
      change set_attribute(:hard_limit, arg(:hard_limit))
    end
  end

  validations do
    validate compare(:soft_limit, greater_than: 0),
      message: "Soft limit must be positive"

    validate compare(:hard_limit, greater_than: 0),
      message: "Hard limit must be positive"

    validate compare(:hard_limit, greater_than_or_equal_to: :soft_limit),
      message: "Hard limit must be greater than or equal to soft limit"

    validate compare(:grace_period_minutes, greater_than_or_equal_to: 0),
      message: "Grace period must be non-negative"

    validate one_of(:limit_type, [:cost, :tokens, :operations]),
      message: "Limit type must be cost, tokens, or operations"
  end

  attributes do
    uuid_primary_key :id

    attribute :budget_configuration_id, :uuid do
      allow_nil? false
      description "Associated budget configuration"
    end

    attribute :limit_type, :atom do
      allow_nil? false
      constraints one_of: [:cost, :tokens, :operations]
      description "Type of limit (cost, tokens, operations)"
    end

    attribute :soft_limit, :decimal do
      allow_nil? false
      constraints min: 0
      description "Warning threshold value"
    end

    attribute :hard_limit, :decimal do
      allow_nil? false
      constraints min: 0
      description "Enforcement threshold value"
    end

    attribute :grace_period_minutes, :integer do
      allow_nil? false
      default 0
      constraints min: 0
      description "Grace period after hard limit exceeded (in minutes)"
    end

    attribute :active, :boolean do
      allow_nil? false
      default true
      description "Whether this limit is currently active"
    end

    attribute :notes, :string do
      allow_nil? true
      description "Optional notes about this budget limit"
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
    calculate :utilization_percentage, :float, expr(0.0) do
      description "Current utilization as percentage of hard limit"
    end

    calculate :is_soft_limit_exceeded, :boolean, expr(false) do
      description "Whether current usage exceeds soft limit"
    end

    calculate :is_hard_limit_exceeded, :boolean, expr(false) do
      description "Whether current usage exceeds hard limit"
    end

    calculate :remaining_amount, :decimal, expr(0.0) do
      description "Remaining budget amount before hard limit"
    end
  end

  identities do
    identity :unique_config_limit_type, [:budget_configuration_id, :limit_type] do
      description "Each configuration can have only one limit per type"
    end
  end
end
