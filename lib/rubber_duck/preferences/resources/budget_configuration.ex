defmodule RubberDuck.Preferences.Resources.BudgetConfiguration do
  @moduledoc """
  BudgetConfiguration resource for managing budget settings across different scopes.

  This resource enables flexible budget configuration at global, user, project, and
  category levels, supporting the hierarchical preference system. Budget configurations
  define the scope and basic parameters for budget management including enablement
  flags, period settings, and currency preferences.
  """

  use Ash.Resource,
    domain: RubberDuck.Preferences,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "budget_configurations"
    repo RubberDuck.Repo

    references do
      # reference :user, on_delete: :delete
      # reference :project, on_delete: :delete
    end
  end

  resource do
    description """
    BudgetConfiguration manages budget settings across different organizational scopes.

    Key features:
    - Multi-scope budget management (global, user, project, category)
    - Flexible period configuration (daily, weekly, monthly)
    - Currency support for international usage
    - Integration with preference hierarchy system
    - Audit tracking and change management
    """

    short_name :budget_configuration
    plural_name :budget_configurations
  end

  code_interface do
    define :create, action: :create
    define :read, action: :read
    define :update, action: :update
    define :destroy, action: :destroy
    define :by_scope, args: [:scope_type, :scope_id]
    define :by_category, args: [:category]
    define :enabled_configs
    define :global_configs
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    read :by_scope do
      description "Get budget configurations for a specific scope"
      argument :scope_type, :atom, allow_nil?: false
      argument :scope_id, :uuid, allow_nil?: true

      filter expr(scope_type == ^arg(:scope_type) and scope_id == ^arg(:scope_id))
      prepare build(sort: [:category, :inserted_at])
    end

    read :by_category do
      description "Get all budget configurations for a specific category"
      argument :category, :string, allow_nil?: false

      filter expr(category == ^arg(:category))
      prepare build(sort: [:scope_type, :inserted_at])
    end

    read :enabled_configs do
      description "Get all enabled budget configurations"

      filter expr(enabled == true)
      prepare build(sort: [:scope_type, :category])
    end

    read :global_configs do
      description "Get all global budget configurations"

      filter expr(scope_type == :global)
      prepare build(sort: [:category])
    end

    update :enable do
      description "Enable budget tracking for this configuration"
      change set_attribute(:enabled, true)
    end

    update :disable do
      description "Disable budget tracking for this configuration"
      change set_attribute(:enabled, false)
    end
  end

  validations do
    validate match(:category, ~r/^[a-z][a-z0-9_]*$/),
      message: "Category must be lowercase with underscores"

    validate present(:scope_id, when: [scope_type: [:user, :project]]),
      message: "User and project scopes must specify scope_id"

    validate absent(:scope_id, when: [scope_type: [:global, :category]]),
      message: "Global and category scopes cannot specify scope_id"

    validate one_of(:period_type, [:daily, :weekly, :monthly]),
      message: "Period type must be daily, weekly, or monthly"

    validate one_of(:currency, ["USD", "EUR", "GBP", "CAD", "AUD"]),
      message: "Currency must be a supported currency code"
  end

  attributes do
    uuid_primary_key :id

    attribute :scope_type, :atom do
      allow_nil? false
      constraints one_of: [:global, :user, :project, :category]
      description "Scope of budget configuration (global, user, project, category)"
    end

    attribute :scope_id, :uuid do
      allow_nil? true
      description "ID of user or project when scope_type is :user or :project"
    end

    attribute :category, :string do
      allow_nil? true
      description "Preference category for category-specific budgets (llm, ml, etc.)"
    end

    attribute :enabled, :boolean do
      allow_nil? false
      default false
      description "Whether budget tracking is enabled for this scope"
    end

    attribute :period_type, :atom do
      allow_nil? false
      constraints one_of: [:daily, :weekly, :monthly]
      default :monthly
      description "Budget period duration"
    end

    attribute :period_start, :date do
      allow_nil? true
      description "Start date for custom budget periods"
    end

    attribute :currency, :string do
      allow_nil? false
      default "USD"
      description "Currency for budget amounts"
    end

    attribute :timezone, :string do
      allow_nil? false
      default "UTC"
      description "Timezone for budget period calculations"
    end

    timestamps()
  end

  relationships do
    # belongs_to :user, RubberDuck.Accounts.User do
    #   allow_nil? true
    #   description "User when scope_type is :user"
    # end

    # Project relationship will be established when Projects domain is implemented
    # belongs_to :project, RubberDuck.Projects.Project do
    #   allow_nil? true
    #   description "Project when scope_type is :project"
    # end

    has_many :budget_limits, RubberDuck.Preferences.Resources.BudgetLimit do
      description "Budget limits associated with this configuration"
    end

    has_many :budget_alerts, RubberDuck.Preferences.Resources.BudgetAlert do
      description "Alert configurations for this budget"
    end

    has_many :budget_usage, RubberDuck.Preferences.Resources.BudgetUsage do
      description "Usage tracking for this budget configuration"
    end

    has_many :budget_events, RubberDuck.Preferences.Resources.BudgetEvent do
      description "Audit events for this budget configuration"
    end

    has_many :budget_overrides, RubberDuck.Preferences.Resources.BudgetOverride do
      description "Emergency overrides for this budget"
    end
  end

  calculations do
    calculate :current_utilization, :float, expr(0.0) do
      description "Current budget utilization percentage"
    end

    calculate :is_over_budget, :boolean, expr(false) do
      description "Whether current usage exceeds budget limits"
    end
  end

  identities do
    identity :unique_scope_category, [:scope_type, :scope_id, :category] do
      description "Each scope+category combination must be unique"
    end
  end
end
