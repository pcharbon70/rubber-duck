defmodule RubberDuck.Preferences.Resources.ProjectPreferenceEnabled do
  @moduledoc """
  ProjectPreferenceEnabled resource for controlling project preference override capability.

  This resource manages whether projects can override user preferences and provides
  fine-grained control over which categories can be overridden. It serves as the
  master switch for project-level preference customization.
  """

  use Ash.Resource,
    domain: RubberDuck.Preferences,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "project_preferences_enabled"
    repo RubberDuck.Repo

    references do
      # reference :project, on_delete: :delete
      reference :enabled_by_user, on_delete: :nilify
    end
  end

  resource do
    description """
    ProjectPreferenceEnabled controls whether projects can override user preferences
    and provides fine-grained control over which categories can be overridden.

    This resource serves as the master switch for project-level customization,
    allowing organizations to:
    - Enable/disable project preference overrides entirely
    - Control which preference categories can be overridden  
    - Set limits on number of overrides
    - Track override usage and activity
    - Require approval workflows for overrides

    The resource supports both permissive (override anything) and restrictive
    (specific categories only) override policies.
    """

    short_name :project_preference_enabled
    plural_name :project_preferences_enabled
  end

  # Note: Policies will be implemented in Phase 1A.10 Security & Authorization

  code_interface do
    define :create, action: :create
    define :read, action: :read
    define :update, action: :update
    define :destroy, action: :destroy
    define :by_project, args: [:project_id]
    define :enabled_projects
    define :can_override, args: [:project_id, :category]
    define :enable_overrides, action: :enable_overrides
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    read :by_project do
      description "Get enablement status for a specific project"
      argument :project_id, :uuid, allow_nil?: false

      filter expr(project_id == ^arg(:project_id))
    end

    read :enabled_projects do
      description "Get all projects with preference overrides enabled"

      filter expr(enabled == true)
      prepare build(sort: [:enabled_at])
    end

    read :can_override do
      description "Check if project can override a specific preference"
      argument :project_id, :uuid, allow_nil?: false
      argument :category, :string, allow_nil?: false

      prepare build(load: [{:can_override_category, %{category: arg(:category)}}])
      filter expr(project_id == ^arg(:project_id))
    end

    create :enable_overrides do
      description "Enable project preference overrides"
      argument :project_id, :uuid, allow_nil?: false
      argument :enabled_categories, {:array, :string}, allow_nil?: false, default: []
      argument :enablement_reason, :string, allow_nil?: false
      argument :enabled_by, :uuid, allow_nil?: false
      argument :max_overrides, :integer, allow_nil?: true

      upsert? true
      upsert_identity :unique_project

      change set_attribute(:project_id, arg(:project_id))
      change set_attribute(:enabled, true)
      change set_attribute(:enabled_categories, arg(:enabled_categories))
      change set_attribute(:enablement_reason, arg(:enablement_reason))
      change set_attribute(:enabled_by, arg(:enabled_by))
      change set_attribute(:max_overrides, arg(:max_overrides))
      change set_attribute(:enabled_at, &DateTime.utc_now/0)
    end

    update :disable_overrides do
      description "Disable project preference overrides"
      argument :disable_reason, :string, allow_nil?: false

      change set_attribute(:enabled, false)
      # Note: Custom change modules will be implemented in future sections
      # change {RubberDuck.Preferences.Changes.RecordDisablement,
      #         reason: arg(:disable_reason)}
    end

    update :update_categories do
      description "Update which categories can be overridden"
      argument :enabled_categories, {:array, :string}, allow_nil?: false
      argument :disabled_categories, {:array, :string}, allow_nil?: false

      change set_attribute(:enabled_categories, arg(:enabled_categories))
      change set_attribute(:disabled_categories, arg(:disabled_categories))
    end

    update :record_override_activity do
      description "Update last override activity timestamp"

      change set_attribute(:last_override_at, &DateTime.utc_now/0)
    end
  end

  preparations do
    prepare build(load: [:total_override_count])
  end

  validations do
    validate present(:enablement_reason),
      message: "Must provide reason for enabling project overrides"

    validate compare(:max_overrides, greater_than: 0, when: present(:max_overrides)),
      message: "Maximum overrides must be positive when specified"

    # Note: Custom validations will be implemented in future sections
    # validate {RubberDuck.Preferences.Validations.CategoryOverlapValidation, []},
    #   message: "Categories cannot be both enabled and disabled"
  end

  attributes do
    uuid_primary_key :id

    attribute :project_id, :uuid do
      allow_nil? false
      description "Link to project entity (one record per project)"
    end

    attribute :enabled, :boolean do
      allow_nil? false
      default false
      description "Master toggle for project preference overrides"
    end

    attribute :enabled_categories, {:array, :string} do
      allow_nil? false
      default []
      description "Specific categories enabled for override (empty = all categories)"
    end

    attribute :disabled_categories, {:array, :string} do
      allow_nil? false
      default []
      description "Categories explicitly disabled for override"
    end

    attribute :enablement_reason, :string do
      allow_nil? false
      description "Why project overrides were enabled"
    end

    attribute :enabled_by, :uuid do
      allow_nil? false
      description "Who enabled project overrides"
    end

    attribute :enabled_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      description "When overrides were enabled"
    end

    attribute :last_override_at, :utc_datetime_usec do
      allow_nil? true
      description "Most recent override activity"
    end

    attribute :max_overrides, :integer do
      allow_nil? true
      description "Maximum number of preferences that can be overridden (null = unlimited)"
    end

    attribute :approval_required, :boolean do
      allow_nil? false
      default true
      description "Whether project overrides require approval"
    end

    timestamps()
  end

  relationships do
    # Note: Project relationship will be implemented when Projects domain is created
    # belongs_to :project, RubberDuck.Projects.Project do
    #   allow_nil? false
    #   attribute_writable? true
    # end

    belongs_to :enabled_by_user, RubberDuck.Accounts.User do
      source_attribute :enabled_by
      destination_attribute :id
      define_attribute? false
    end

    has_many :project_preferences, RubberDuck.Preferences.Resources.ProjectPreference do
      destination_attribute :project_id
      source_attribute :project_id
    end
  end

  calculations do
    calculate :total_override_count, :integer, expr(count(project_preferences, query: [])) do
      description "Total number of preference overrides (active and inactive)"
      load [:project_preferences]
    end

    # Note: Complex calculations simplified for initial implementation
  end

  identities do
    identity :unique_project, [:project_id] do
      description "Each project can have only one preference enablement record"
    end
  end
end
