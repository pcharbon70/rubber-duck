defmodule RubberDuck.Preferences.Resources.PreferenceSchemaVersion do
  @moduledoc """
  Schema version tracking resource for preference system migrations.

  Tracks schema versions, compatibility information, and migration paths
  for the preference management system. Enables automated detection of
  required migrations and safe upgrade/downgrade operations.
  """

  use Ash.Resource,
    domain: RubberDuck.Preferences,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "preference_schema_versions"
    repo RubberDuck.Repo
  end

  code_interface do
    define :create, action: :create
    define :read, action: :read
    define :update, action: :update
    define :destroy, action: :destroy
    define :mark_applied, action: :mark_applied
    define :deprecate, action: :deprecate
    define :by_version, args: [:version], action: :read
    define :current_version, action: :read
    define :breaking_versions, action: :read
    define :deprecated_versions, action: :read
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create a new schema version record"

      accept [
        :version,
        :version_name,
        :description,
        :migration_required,
        :breaking_changes,
        :compatibility_matrix,
        :migration_scripts,
        :rollback_scripts,
        :data_transformations,
        :validation_rules,
        :minimum_app_version,
        :metadata
      ]

      validate present([:version])
      validate match(:version, ~r/^\d+\.\d+\.\d+(?:-[a-zA-Z0-9\-\.]+)?$/)
    end

    update :update do
      description "Update schema version metadata"

      accept [
        :version_name,
        :description,
        :compatibility_matrix,
        :deprecation_notice,
        :metadata
      ]
    end

    update :mark_applied do
      description "Mark schema version as applied to the system"
      change set_attribute(:applied_at, &DateTime.utc_now/0)
    end

    update :deprecate do
      description "Mark schema version as deprecated"
      accept [:deprecation_notice]
      change set_attribute(:deprecated, true)
    end
  end

  # Authorization policies for schema version management
  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      description "All authenticated users can read schema versions"
      authorize_if actor_attribute_equals(:role, :user)
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :security_admin)
    end

    policy action_type([:create, :update, :destroy]) do
      description "Only admins can manage schema versions"
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :security_admin)
    end

    policy action([:mark_applied, :deprecate]) do
      description "Only security admins can mark versions as applied or deprecated"
      authorize_if actor_attribute_equals(:role, :security_admin)
    end
  end

  preparations do
    prepare build(sort: [version: :desc])
  end

  attributes do
    uuid_primary_key :id

    attribute :version, :string do
      description "Semantic version of the preference schema (e.g., '1.2.3')"
      constraints max_length: 20
      allow_nil? false
    end

    attribute :version_name, :string do
      description "Human-readable name for this schema version"
      constraints max_length: 100
      allow_nil? true
    end

    attribute :description, :string do
      description "Description of changes in this schema version"
      constraints max_length: 1000
      allow_nil? true
    end

    attribute :migration_required, :boolean do
      description "Whether data migration is required for this version"
      default false
    end

    attribute :breaking_changes, :boolean do
      description "Whether this version contains breaking changes"
      default false
    end

    attribute :compatibility_matrix, :map do
      description "Compatibility information with other versions"
      default %{}
    end

    attribute :migration_scripts, {:array, :string} do
      description "List of migration script identifiers for this version"
      default []
    end

    attribute :rollback_scripts, {:array, :string} do
      description "List of rollback script identifiers for this version"
      default []
    end

    attribute :data_transformations, :map do
      description "Data transformation rules for this version"
      default %{}
    end

    attribute :validation_rules, :map do
      description "Validation rules for data in this schema version"
      default %{}
    end

    attribute :deprecated, :boolean do
      description "Whether this schema version is deprecated"
      default false
    end

    attribute :deprecation_notice, :string do
      description "Notice about deprecation and migration path"
      constraints max_length: 500
      allow_nil? true
    end

    attribute :minimum_app_version, :string do
      description "Minimum application version required for this schema"
      constraints max_length: 20
      allow_nil? true
    end

    attribute :applied_at, :utc_datetime do
      description "When this schema version was applied to the system"
      allow_nil? true
    end

    attribute :metadata, :map do
      description "Additional metadata for this schema version"
      default %{}
    end

    timestamps()
  end

  calculations do
    calculate :is_current, :boolean, expr(not is_nil(applied_at))

    # Would parse semantic version
    calculate :version_number, :integer, expr(0)
    calculate :requires_migration, :boolean, expr(migration_required and not deprecated)
  end
end
