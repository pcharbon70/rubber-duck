defmodule RubberDuck.Preferences.Resources.PreferenceHistory do
  @moduledoc """
  PreferenceHistory resource for tracking all preference changes.

  This resource provides a complete audit trail for all preference changes,
  enabling rollback capabilities, change attribution, and compliance reporting.
  All preference modifications are automatically tracked through this resource.
  """

  use Ash.Resource,
    domain: RubberDuck.Preferences,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "preference_history"
    repo RubberDuck.Repo

    references do
      reference :user, on_delete: :delete
      # reference :project, on_delete: :delete
      reference :changed_by_user, on_delete: :nilify
      reference :source_template, on_delete: :nilify
    end
  end

  resource do
    description """
    PreferenceHistory provides a complete audit trail for all preference changes,
    enabling rollback capabilities, change attribution, and compliance reporting.

    Key features:
    - Automatic change tracking for all preference modifications
    - Support for batch operations with grouped change tracking
    - Rollback capability with safety checks
    - Change attribution and reason tracking
    - Template application tracking
    - IP and user agent tracking for security
    """

    short_name :preference_history
    plural_name :preference_history_entries
  end

  # Note: Policies will be implemented in Phase 1A.10 Security & Authorization

  code_interface do
    define :create, action: :create
    define :read, action: :read
    define :by_user, args: [:user_id]
    define :by_project, args: [:project_id]
    define :by_preference, args: [:preference_key]
    define :recent_changes, args: [:days]
    define :by_batch, args: [:batch_id]
    define :rollback_candidates
    define :rollback_candidates_for_user, args: [:user_id]
    define :rollback_candidates_for_project, args: [:project_id]
    define :record_change, action: :record_change
  end

  actions do
    defaults [:create, :read]

    read :by_user do
      description "Get change history for a specific user"
      argument :user_id, :uuid, allow_nil?: false

      filter expr(user_id == ^arg(:user_id))
      prepare build(sort: [desc: :changed_at])
    end

    read :by_project do
      description "Get change history for a specific project"
      argument :project_id, :uuid, allow_nil?: false

      filter expr(project_id == ^arg(:project_id))
      prepare build(sort: [desc: :changed_at])
    end

    read :by_preference do
      description "Get change history for a specific preference"
      argument :preference_key, :string, allow_nil?: false

      filter expr(preference_key == ^arg(:preference_key))
      prepare build(sort: [desc: :changed_at])
    end

    read :recent_changes do
      description "Get recent preference changes across the system"
      argument :days, :integer, allow_nil?: false, default: 7

      filter expr(changed_at >= fragment("NOW() - INTERVAL '? days'", ^arg(:days)))
      prepare build(sort: [desc: :changed_at])
    end

    read :by_batch do
      description "Get all changes in a specific batch"
      argument :batch_id, :uuid, allow_nil?: false

      filter expr(batch_id == ^arg(:batch_id))
      prepare build(sort: [:changed_at])
    end

    read :rollback_candidates do
      description "Get changes that can be rolled back"

      filter expr(rollback_possible == true)
      prepare build(sort: [desc: :changed_at])
    end

    read :rollback_candidates_for_user do
      description "Get rollback candidates for specific user"
      argument :user_id, :uuid, allow_nil?: false

      filter expr(rollback_possible == true and user_id == ^arg(:user_id))
      prepare build(sort: [desc: :changed_at])
    end

    read :rollback_candidates_for_project do
      description "Get rollback candidates for specific project"
      argument :project_id, :uuid, allow_nil?: false

      filter expr(rollback_possible == true and project_id == ^arg(:project_id))
      prepare build(sort: [desc: :changed_at])
    end

    create :record_change do
      description "Record a preference change in history"

      accept [
        :user_id,
        :project_id,
        :preference_key,
        :old_value,
        :new_value,
        :change_type,
        :change_reason,
        :changed_by,
        :rollback_possible,
        :source_template_id,
        :batch_id,
        :ip_address,
        :user_agent
      ]

      change set_attribute(:changed_at, &DateTime.utc_now/0)
    end

    create :record_batch_change do
      description "Record multiple preference changes as a batch"
      argument :changes, {:array, :map}, allow_nil?: false
      argument :batch_reason, :string, allow_nil?: false

      # Note: Custom change modules will be implemented in future sections
      # change {RubberDuck.Preferences.Changes.RecordBatchChanges,
      #         changes: arg(:changes),
      #         reason: arg(:batch_reason)}
    end
  end

  preparations do
    prepare build(load: [:is_user_change, :is_project_change, :is_recent])
  end

  validations do
    validate match(:preference_key, ~r/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$/),
      message: "Preference key must be dot-notation lowercase with underscores"

    validate present(:old_value, when: [change_type: [:update, :delete]]),
      message: "Updates and deletions must record the old value"

    validate present(:new_value, when: [change_type: [:create, :update]]),
      message: "Creates and updates must record the new value"

    validate present(:source_template_id, when: [change_type: :template_apply]),
      message: "Template applications must reference the source template"

    validate {Ash.Resource.Validation.AtLeastOneOf, fields: [:user_id, :project_id]},
      message: "Change must be associated with either a user or project"
  end

  attributes do
    uuid_primary_key :change_id

    attribute :user_id, :uuid do
      allow_nil? true
      description "User whose preference was changed"
    end

    attribute :project_id, :uuid do
      allow_nil? true
      description "Project if this was a project preference change"
    end

    attribute :preference_key, :string do
      allow_nil? false
      description "Which preference was changed"
    end

    attribute :old_value, :string do
      allow_nil? true
      description "Previous value (null for new preferences)"
    end

    attribute :new_value, :string do
      allow_nil? true
      description "New value (null for deleted preferences)"
    end

    attribute :change_type, :atom do
      allow_nil? false

      constraints one_of: [
                    :create,
                    :update,
                    :delete,
                    :template_apply,
                    :reset,
                    :migration,
                    :bulk_update
                  ]

      description "Type of change that occurred"
    end

    attribute :change_reason, :string do
      allow_nil? true
      description "Why the change was made"
    end

    attribute :changed_by, :uuid do
      allow_nil? false
      description "User who made the change (may differ from user_id for admin changes)"
    end

    attribute :changed_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      description "When change occurred"
    end

    attribute :rollback_possible, :boolean do
      allow_nil? false
      default true
      description "Whether change can be rolled back"
    end

    attribute :source_template_id, :uuid do
      allow_nil? true
      description "Template ID if change was applied from template"
    end

    attribute :batch_id, :uuid do
      allow_nil? true
      description "Batch identifier for grouped changes"
    end

    attribute :ip_address, :string do
      allow_nil? true
      description "IP address where change originated"
    end

    attribute :user_agent, :string do
      allow_nil? true
      description "User agent string for web-based changes"
    end

    timestamps()
  end

  relationships do
    belongs_to :user, RubberDuck.Accounts.User do
      allow_nil? true
      attribute_writable? true
    end

    # Note: Project relationship will be implemented when Projects domain is created
    # belongs_to :project, RubberDuck.Projects.Project do
    #   allow_nil? true
    #   attribute_writable? true
    # end

    belongs_to :changed_by_user, RubberDuck.Accounts.User do
      source_attribute :changed_by
      destination_attribute :id
      define_attribute? false
    end

    belongs_to :source_template, RubberDuck.Preferences.Resources.PreferenceTemplate do
      source_attribute :source_template_id
      destination_attribute :template_id
      define_attribute? false
    end

    belongs_to :system_default, RubberDuck.Preferences.Resources.SystemDefault do
      source_attribute :preference_key
      destination_attribute :preference_key
      define_attribute? false
    end
  end

  calculations do
    calculate :is_user_change, :boolean, expr(not is_nil(user_id)) do
      description "Whether this was a user preference change"
    end

    calculate :is_project_change, :boolean, expr(not is_nil(project_id)) do
      description "Whether this was a project preference change"
    end

    calculate :is_recent,
              :boolean,
              expr(changed_at >= ^DateTime.add(DateTime.utc_now(), -7, :day)) do
      description "Whether change occurred within the last 7 days"
    end

    # Note: Complex calculations simplified for initial implementation
  end
end
