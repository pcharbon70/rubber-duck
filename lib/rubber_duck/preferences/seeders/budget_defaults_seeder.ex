defmodule RubberDuck.Preferences.Seeders.BudgetDefaultsSeeder do
  @moduledoc """
  Seeds budget and cost control preference defaults into the system.

  Creates comprehensive default configurations for budget management including
  global budget controls, project-level budgets, alert thresholds, and
  enforcement policies.
  """

  require Logger

  alias RubberDuck.Preferences.Resources.SystemDefault

  @doc """
  Seed all budget preference defaults.
  """
  @spec seed_all() :: :ok | {:error, term()}
  def seed_all do
    Logger.info("Seeding budget preference defaults...")

    with :ok <- seed_global_budget_defaults(),
         :ok <- seed_budget_limit_defaults(),
         :ok <- seed_alert_defaults(),
         :ok <- seed_enforcement_defaults(),
         :ok <- seed_integration_defaults(),
         :ok <- seed_reporting_defaults() do
      Logger.info("Successfully seeded all budget preference defaults")
      :ok
    else
      error ->
        Logger.error("Failed to seed budget defaults: #{inspect(error)}")
        error
    end
  end

  @doc """
  Seed global budget control preference defaults.
  """
  @spec seed_global_budget_defaults() :: :ok | {:error, term()}
  def seed_global_budget_defaults do
    defaults = [
      %{
        preference_key: "budgeting.global.enabled",
        default_value: "false",
        data_type: :boolean,
        category: "budgeting",
        subcategory: "global",
        description: "Enable global budget tracking and enforcement",
        access_level: :admin,
        display_order: 1
      },
      %{
        preference_key: "budgeting.global.currency",
        default_value: "USD",
        data_type: :string,
        category: "budgeting",
        subcategory: "global",
        description: "Default currency for budget calculations",
        constraints: %{allowed_values: ["USD", "EUR", "GBP", "CAD", "AUD"]},
        access_level: :admin,
        display_order: 2
      },
      %{
        preference_key: "budgeting.global.period_type",
        default_value: "monthly",
        data_type: :string,
        category: "budgeting",
        subcategory: "global",
        description: "Default budget period type",
        constraints: %{allowed_values: ["daily", "weekly", "monthly"]},
        access_level: :admin,
        display_order: 3
      },
      %{
        preference_key: "budgeting.project.enabled_by_default",
        default_value: "false",
        data_type: :boolean,
        category: "budgeting",
        subcategory: "project",
        description: "Enable project budget overrides by default",
        access_level: :admin,
        display_order: 4
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed budget limit preference defaults.
  """
  @spec seed_budget_limit_defaults() :: :ok | {:error, term()}
  def seed_budget_limit_defaults do
    defaults = [
      %{
        preference_key: "budgeting.limits.cost.monthly",
        default_value: "100.00",
        data_type: :float,
        category: "budgeting",
        subcategory: "limits",
        description: "Default monthly cost limit in USD",
        constraints: %{min: 0.01, max: 10_000.00},
        access_level: :user,
        display_order: 10
      },
      %{
        preference_key: "budgeting.limits.tokens.monthly",
        default_value: "1000000",
        data_type: :integer,
        category: "budgeting",
        subcategory: "limits",
        description: "Default monthly token limit",
        constraints: %{min: 1000, max: 100_000_000},
        access_level: :user,
        display_order: 11
      },
      %{
        preference_key: "budgeting.limits.operations.monthly",
        default_value: "10000",
        data_type: :integer,
        category: "budgeting",
        subcategory: "limits",
        description: "Default monthly operation count limit",
        constraints: %{min: 100, max: 1_000_000},
        access_level: :user,
        display_order: 12
      },
      %{
        preference_key: "budgeting.limits.grace_period_minutes",
        default_value: "30",
        data_type: :integer,
        category: "budgeting",
        subcategory: "limits",
        description: "Grace period in minutes after limit exceeded",
        constraints: %{min: 0, max: 1440},
        access_level: :user,
        display_order: 13
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed alert preference defaults.
  """
  @spec seed_alert_defaults() :: :ok | {:error, term()}
  def seed_alert_defaults do
    defaults = [
      %{
        preference_key: "budgeting.alerts.enabled",
        default_value: "true",
        data_type: :boolean,
        category: "budgeting",
        subcategory: "alerts",
        description: "Enable budget alert notifications",
        access_level: :user,
        display_order: 20
      },
      %{
        preference_key: "budgeting.alerts.threshold_50_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "budgeting",
        subcategory: "alerts",
        description: "Send alert at 50% budget utilization",
        access_level: :user,
        display_order: 21
      },
      %{
        preference_key: "budgeting.alerts.threshold_75_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "budgeting",
        subcategory: "alerts",
        description: "Send alert at 75% budget utilization",
        access_level: :user,
        display_order: 22
      },
      %{
        preference_key: "budgeting.alerts.threshold_90_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "budgeting",
        subcategory: "alerts",
        description: "Send alert at 90% budget utilization",
        access_level: :user,
        display_order: 23
      },
      %{
        preference_key: "budgeting.alerts.delivery_method",
        default_value: "in_app",
        data_type: :string,
        category: "budgeting",
        subcategory: "alerts",
        description: "Primary alert delivery method",
        constraints: %{allowed_values: ["email", "slack", "webhook", "in_app"]},
        access_level: :user,
        display_order: 24
      },
      %{
        preference_key: "budgeting.alerts.max_per_hour",
        default_value: "4",
        data_type: :integer,
        category: "budgeting",
        subcategory: "alerts",
        description: "Maximum alerts per hour to prevent spam",
        constraints: %{min: 1, max: 60},
        access_level: :user,
        display_order: 25
      },
      %{
        preference_key: "budgeting.alerts.escalation_enabled",
        default_value: "false",
        data_type: :boolean,
        category: "budgeting",
        subcategory: "alerts",
        description: "Enable alert escalation for critical overages",
        access_level: :user,
        display_order: 26
      },
      %{
        preference_key: "budgeting.alerts.escalation_delay_minutes",
        default_value: "60",
        data_type: :integer,
        category: "budgeting",
        subcategory: "alerts",
        description: "Minutes to wait before escalating alerts",
        constraints: %{min: 15, max: 1440},
        access_level: :user,
        display_order: 27
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed enforcement policy preference defaults.
  """
  @spec seed_enforcement_defaults() :: :ok | {:error, term()}
  def seed_enforcement_defaults do
    defaults = [
      %{
        preference_key: "budgeting.enforcement.enabled",
        default_value: "false",
        data_type: :boolean,
        category: "budgeting",
        subcategory: "enforcement",
        description: "Enable budget enforcement (blocking operations when exceeded)",
        access_level: :admin,
        display_order: 30
      },
      %{
        preference_key: "budgeting.enforcement.mode",
        default_value: "soft_warning",
        data_type: :string,
        category: "budgeting",
        subcategory: "enforcement",
        description: "Budget enforcement mode",
        constraints: %{allowed_values: ["soft_warning", "hard_stop"]},
        access_level: :admin,
        display_order: 31
      },
      %{
        preference_key: "budgeting.enforcement.override_allowed",
        default_value: "true",
        data_type: :boolean,
        category: "budgeting",
        subcategory: "enforcement",
        description: "Allow authorized users to override budget limits",
        access_level: :admin,
        display_order: 32
      },
      %{
        preference_key: "budgeting.enforcement.emergency_allocation_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "budgeting",
        subcategory: "enforcement",
        description: "Enable emergency budget allocation for critical operations",
        access_level: :admin,
        display_order: 33
      },
      %{
        preference_key: "budgeting.enforcement.emergency_allocation_amount",
        default_value: "25.00",
        data_type: :float,
        category: "budgeting",
        subcategory: "enforcement",
        description: "Emergency allocation amount in default currency",
        constraints: %{min: 1.00, max: 1000.00},
        access_level: :admin,
        display_order: 34
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed Phase 11 integration preference defaults.
  """
  @spec seed_integration_defaults() :: :ok | {:error, term()}
  def seed_integration_defaults do
    defaults = [
      %{
        preference_key: "budgeting.integration.phase11_enabled",
        default_value: "false",
        data_type: :boolean,
        category: "budgeting",
        subcategory: "integration",
        description: "Enable integration with Phase 11 autonomous cost management",
        access_level: :admin,
        display_order: 40
      },
      %{
        preference_key: "budgeting.integration.sync_frequency_minutes",
        default_value: "15",
        data_type: :integer,
        category: "budgeting",
        subcategory: "integration",
        description: "Frequency in minutes for syncing budget data with Phase 11",
        constraints: %{min: 5, max: 1440},
        access_level: :admin,
        display_order: 41
      },
      %{
        preference_key: "budgeting.integration.cost_attribution_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "budgeting",
        subcategory: "integration",
        description: "Enable detailed cost attribution tracking",
        access_level: :admin,
        display_order: 42
      },
      %{
        preference_key: "budgeting.integration.predictive_modeling_enabled",
        default_value: "false",
        data_type: :boolean,
        category: "budgeting",
        subcategory: "integration",
        description: "Enable predictive budget modeling and forecasting",
        access_level: :admin,
        display_order: 43
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed reporting preference defaults.
  """
  @spec seed_reporting_defaults() :: :ok | {:error, term()}
  def seed_reporting_defaults do
    defaults = [
      %{
        preference_key: "budgeting.reporting.enabled",
        default_value: "true",
        data_type: :boolean,
        category: "budgeting",
        subcategory: "reporting",
        description: "Enable budget reporting and analytics",
        access_level: :user,
        display_order: 50
      },
      %{
        preference_key: "budgeting.reporting.frequency",
        default_value: "weekly",
        data_type: :string,
        category: "budgeting",
        subcategory: "reporting",
        description: "Frequency for automated budget reports",
        constraints: %{allowed_values: ["daily", "weekly", "monthly"]},
        access_level: :user,
        display_order: 51
      },
      %{
        preference_key: "budgeting.reporting.include_forecasts",
        default_value: "true",
        data_type: :boolean,
        category: "budgeting",
        subcategory: "reporting",
        description: "Include budget forecasts in reports",
        access_level: :user,
        display_order: 52
      },
      %{
        preference_key: "budgeting.reporting.include_recommendations",
        default_value: "true",
        data_type: :boolean,
        category: "budgeting",
        subcategory: "reporting",
        description: "Include cost optimization recommendations in reports",
        access_level: :user,
        display_order: 53
      },
      %{
        preference_key: "budgeting.reporting.retention_months",
        default_value: "12",
        data_type: :integer,
        category: "budgeting",
        subcategory: "reporting",
        description: "Months to retain detailed budget reporting data",
        constraints: %{min: 3, max: 60},
        access_level: :admin,
        display_order: 54
      }
    ]

    seed_defaults(defaults)
  end

  # Private helper function to seed defaults
  defp seed_defaults(defaults) do
    Enum.each(defaults, fn default_attrs ->
      case SystemDefault.seed_default(default_attrs) do
        {:ok, _} ->
          :ok

        {:error, error} ->
          Logger.warning(
            "Failed to seed budget default #{default_attrs.preference_key}: #{inspect(error)}"
          )
      end
    end)

    :ok
  rescue
    error ->
      Logger.error("Error seeding budget defaults: #{inspect(error)}")
      {:error, error}
  end
end
