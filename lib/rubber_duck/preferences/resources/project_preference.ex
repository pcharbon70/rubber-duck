defmodule RubberDuck.Preferences.Resources.ProjectPreference do
  @moduledoc """
  ProjectPreference resource for storing project-specific preference overrides.

  This resource enables projects to optionally override user preferences for
  team consistency while maintaining selective inheritance. Projects can
  override specific preferences while inheriting others from user settings.
  """

  use Ash.Resource,
    domain: RubberDuck.Preferences,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "project_preferences"
    repo RubberDuck.Repo

    references do
      # reference :project, on_delete: :delete
      reference :system_default, on_delete: :delete
      reference :approved_by_user, on_delete: :nilify
    end
  end

  resource do
    description """
    ProjectPreference enables projects to optionally override user preferences
    for team consistency. Projects can selectively override specific preferences
    while inheriting others from user settings, providing maximum flexibility
    with team coordination.

    Key features:
    - Selective inheritance from user preferences
    - Approval workflow for project overrides
    - Temporary overrides with expiration
    - Priority-based conflict resolution
    - Complete audit trail for project changes
    """

    short_name :project_preference
    plural_name :project_preferences
  end

  # Note: Policies will be implemented in Phase 1A.10 Security & Authorization

  code_interface do
    define :create, action: :create
    define :read, action: :read
    define :update, action: :update
    define :destroy, action: :destroy
    define :by_project, args: [:project_id]
    define :active_for_project, args: [:project_id]
    define :by_project_and_category, args: [:project_id, :category]
    define :expiring_soon, args: [:project_id, :days]
    define :create_override, action: :create_override
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    read :by_project do
      description "Get all preferences for a specific project"
      argument :project_id, :uuid, allow_nil?: false

      filter expr(project_id == ^arg(:project_id))
      prepare build(sort: [:category, :preference_key])
    end

    read :active_for_project do
      description "Get currently active project preferences"
      argument :project_id, :uuid, allow_nil?: false

      prepare build(load: [:is_active])
      filter expr(project_id == ^arg(:project_id) and is_active == true)
    end

    read :by_project_and_category do
      description "Get project preferences in a specific category"
      argument :project_id, :uuid, allow_nil?: false
      argument :category, :string, allow_nil?: false

      filter expr(project_id == ^arg(:project_id) and category == ^arg(:category))
      prepare build(sort: [:preference_key])
    end

    read :expiring_soon do
      description "Get temporary overrides expiring within specified days"
      argument :project_id, :uuid, allow_nil?: false
      argument :days, :integer, allow_nil?: false, default: 7

      prepare build(load: [:days_until_expiration])

      filter expr(
               project_id == ^arg(:project_id) and
                 temporary == true and
                 days_until_expiration <= ^arg(:days) and
                 days_until_expiration > 0
             )
    end

    create :create_override do
      description "Create a project preference override"
      argument :project_id, :uuid, allow_nil?: false
      argument :preference_key, :string, allow_nil?: false
      argument :value, :string, allow_nil?: false
      argument :override_reason, :string, allow_nil?: false
      argument :approved_by, :uuid, allow_nil?: true
      argument :temporary, :boolean, allow_nil?: false, default: false
      argument :effective_until, :utc_datetime_usec, allow_nil?: true

      change set_attribute(:project_id, arg(:project_id))
      change set_attribute(:preference_key, arg(:preference_key))
      change set_attribute(:value, arg(:value))
      change set_attribute(:override_reason, arg(:override_reason))
      change set_attribute(:approved_by, arg(:approved_by))
      change set_attribute(:temporary, arg(:temporary))
      change set_attribute(:effective_until, arg(:effective_until))

      # Note: Custom change modules will be implemented in future sections
      # change {RubberDuck.Preferences.Changes.SetApprovalTimestamp, []}
      # change {RubberDuck.Preferences.Changes.PopulateCategoryFromDefault, []}
    end

    update :approve_override do
      description "Approve a pending project override"
      argument :approved_by, :uuid, allow_nil?: false

      change set_attribute(:approved_by, arg(:approved_by))
      change set_attribute(:approved_at, &DateTime.utc_now/0)
    end

    update :extend_temporary do
      description "Extend expiration of temporary override"
      argument :new_expiration, :utc_datetime_usec, allow_nil?: false

      filter expr(temporary == true)
      change set_attribute(:effective_until, arg(:new_expiration))
    end

    destroy :expire_temporary do
      description "Remove expired temporary overrides"
      argument :project_id, :uuid, allow_nil?: false

      filter expr(
               project_id == ^arg(:project_id) and
                 temporary == true and
                 effective_until < ^DateTime.utc_now()
             )
    end
  end

  preparations do
    prepare build(load: [:is_active])
  end

  validations do
    validate match(:preference_key, ~r/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$/),
      message: "Preference key must be dot-notation lowercase with underscores"

    validate compare(:priority, greater_than: 0, less_than_or_equal: 10),
      message: "Priority must be between 1 and 10"

    validate compare(:effective_from,
               less_than_or_equal: :effective_until,
               when: present(:effective_until)
             ),
             message: "Effective from date must be before effective until date"

    validate present(:approved_by, when: [temporary: false]),
      message: "Permanent project overrides must be approved"

    validate present(:effective_until, when: [temporary: true]),
      message: "Temporary overrides must have expiration date"

    validate absent(:inherits_user, when: present(:value)),
      message: "Cannot inherit user preference when project value is specified"
  end

  attributes do
    uuid_primary_key :id

    attribute :project_id, :uuid do
      allow_nil? false
      description "Link to project entity"
    end

    attribute :preference_key, :string do
      allow_nil? false
      description "Links to SystemDefault.preference_key"
    end

    attribute :value, :string do
      allow_nil? false
      description "Project's preferred value (stored as JSON)"
    end

    attribute :inherits_user, :boolean do
      allow_nil? false
      default false
      description "Whether this preference inherits from user preferences"
    end

    attribute :override_reason, :string do
      allow_nil? false
      description "Justification for project override"
    end

    attribute :approved_by, :uuid do
      allow_nil? true
      description "Who approved the project override"
    end

    attribute :approved_at, :utc_datetime_usec do
      allow_nil? true
      description "When override was approved"
    end

    attribute :effective_from, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      description "When override becomes active"
    end

    attribute :effective_until, :utc_datetime_usec do
      allow_nil? true
      description "Optional expiration for temporary overrides"
    end

    attribute :priority, :integer do
      allow_nil? false
      default 5
      description "Priority for resolving conflicting overrides (1-10, higher wins)"
    end

    attribute :category, :string do
      allow_nil? false
      description "Inherited from SystemDefault for denormalized querying"
    end

    attribute :temporary, :boolean do
      allow_nil? false
      default false
      description "Whether this is a temporary override with expiration"
    end

    timestamps()
  end

  relationships do
    # Note: Project relationship will be implemented when Projects domain is created
    # belongs_to :project, RubberDuck.Projects.Project do
    #   allow_nil? false
    #   attribute_writable? true
    # end

    belongs_to :system_default, RubberDuck.Preferences.Resources.SystemDefault do
      source_attribute :preference_key
      destination_attribute :preference_key
      define_attribute? false
    end

    belongs_to :approved_by_user, RubberDuck.Accounts.User do
      source_attribute :approved_by
      destination_attribute :id
      define_attribute? false
    end

    has_many :history_entries, RubberDuck.Preferences.Resources.PreferenceHistory do
      destination_attribute :project_id
      source_attribute :project_id
      filter expr(preference_key == parent_expr(preference_key))
    end
  end

  calculations do
    calculate :is_active, :boolean, expr(effective_from <= ^DateTime.utc_now()) do
      description "Whether this override is currently active based on effective dates"
    end

    # Note: Complex calculations simplified for initial implementation
  end

  identities do
    identity :unique_project_preference, [:project_id, :preference_key] do
      description "Each project can have only one override per preference key"
    end
  end
end
