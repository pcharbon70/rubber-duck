defmodule RubberDuck.Preferences.Resources.SystemDefault do
  @moduledoc """
  SystemDefault resource for storing intelligent system defaults.

  This resource stores the foundational configuration defaults for all
  configurable options in the RubberDuck system, including LLM providers,
  budgeting controls, ML features, code quality tools, and agent behaviors.
  """

  use Ash.Resource,
    domain: RubberDuck.Preferences,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "system_defaults"
    repo RubberDuck.Repo

    references do
      # reference :preference_category, on_delete: :nilify
    end

    skip_unique_indexes [:unique_replacement]
  end

  resource do
    description """
    SystemDefault stores intelligent system defaults for all configurable options
    in the RubberDuck system. This resource serves as the foundation for the
    hierarchical preference system, providing sensible defaults that users and
    projects can selectively override.

    Key features:
    - Hierarchical category organization
    - Type-safe value storage with validation
    - Version tracking for schema evolution  
    - Deprecation management with replacement tracking
    - Security classification for sensitive preferences
    - Usage analytics for optimization
    """

    short_name :system_default
    plural_name :system_defaults
  end

  code_interface do
    define :create, action: :create
    define :read, action: :read
    define :update, action: :update
    define :destroy, action: :destroy
    define :by_category, args: [:category]
    define :by_subcategory, args: [:category, :subcategory]
    define :search_keys, args: [:pattern]
    define :non_deprecated
    define :sensitive_preferences
    define :seed_default, action: :seed_default
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    read :by_category do
      description "Get all preferences in a specific category"
      argument :category, :string, allow_nil?: false

      filter expr(category == ^arg(:category))
      prepare build(sort: [:display_order, :preference_key])
    end

    read :by_subcategory do
      description "Get all preferences in a specific subcategory"
      argument :category, :string, allow_nil?: false
      argument :subcategory, :string, allow_nil?: false

      filter expr(category == ^arg(:category) and subcategory == ^arg(:subcategory))
      prepare build(sort: [:display_order, :preference_key])
    end

    read :search_keys do
      description "Search preferences by key pattern"
      argument :pattern, :string, allow_nil?: false

      filter expr(ilike(preference_key, ^arg(:pattern)))
      prepare build(sort: [:preference_key])
    end

    read :non_deprecated do
      description "Get all non-deprecated preferences"

      filter expr(deprecated == false)
      prepare build(sort: [:category, :subcategory, :display_order, :preference_key])
    end

    read :sensitive_preferences do
      description "Get all preferences that contain sensitive data"

      filter expr(sensitive == true)
      prepare build(sort: [:category, :preference_key])
    end

    update :deprecate do
      description "Mark a preference as deprecated"
      argument :replacement_key, :string, allow_nil?: false

      change set_attribute(:deprecated, true)
      change set_attribute(:replacement_key, arg(:replacement_key))
    end

    update :bulk_update_category do
      description "Update multiple preferences in a category"
      argument :category, :string, allow_nil?: false
      argument :updates, {:array, :map}, allow_nil?: false

      filter expr(category == ^arg(:category))
      # Custom bulk update logic would be implemented in a change module
    end

    create :seed_default do
      description "Seed a system default (for initial setup)"

      # Accept all attributes for seeding
      accept [
        :preference_key,
        :default_value,
        :data_type,
        :category,
        :subcategory,
        :description,
        :constraints,
        :sensitive,
        :access_level,
        :display_order
      ]

      # Ensure seeding is idempotent
      upsert? true
      upsert_identity :unique_preference_key
    end
  end

  preparations do
    prepare build(load: [:usage_count, :is_deprecated])
  end

  validations do
    validate compare(:version, greater_than: 0), message: "Version must be positive"

    validate match(:preference_key, ~r/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$/),
      message: "Preference key must be dot-notation lowercase with underscores"

    validate match(:category, ~r/^[a-z][a-z0-9_]*$/),
      message: "Category must be lowercase with underscores"

    validate absent(:replacement_key, when: [deprecated: {true, false}]),
      message: "Non-deprecated preferences cannot have replacement keys"

    validate present(:replacement_key, when: [deprecated: true]),
      message: "Deprecated preferences must specify a replacement key"
  end

  attributes do
    uuid_primary_key :id

    attribute :preference_key, :string do
      allow_nil? false
      description "Dot-notation preference identifier (e.g., 'llm.providers.openai.model')"
    end

    attribute :default_value, :string do
      allow_nil? false
      description "The default value stored as JSON for flexibility"
    end

    attribute :data_type, :atom do
      allow_nil? false
      constraints one_of: [:string, :integer, :float, :boolean, :json, :encrypted]
      default :string
      description "Data type for value validation and UI rendering"
    end

    attribute :category, :string do
      allow_nil? false
      description "Primary category (llm, budgeting, ml, code_quality, etc.)"
    end

    attribute :subcategory, :string do
      allow_nil? true
      description "Optional subcategory for organization"
    end

    attribute :description, :string do
      allow_nil? false
      description "Human-readable description of the preference"
    end

    attribute :constraints, :map do
      allow_nil? true
      description "Validation constraints (min/max, allowed values, etc.)"
    end

    attribute :sensitive, :boolean do
      allow_nil? false
      default false
      description "Whether this preference contains sensitive data requiring encryption"
    end

    attribute :version, :integer do
      allow_nil? false
      default 1
      description "Version for schema evolution and migration"
    end

    attribute :deprecated, :boolean do
      allow_nil? false
      default false
      description "Mark deprecated preferences for migration"
    end

    attribute :replacement_key, :string do
      allow_nil? true
      description "Preference key that replaces this deprecated preference"
    end

    attribute :display_order, :integer do
      allow_nil? true
      description "Sort order for UI display within category"
    end

    attribute :access_level, :atom do
      allow_nil? false
      constraints one_of: [:public, :user, :admin, :superadmin]
      default :user
      description "Minimum access level required to modify this preference"
    end

    timestamps()
  end

  relationships do
    # Note: PreferenceCategory relationship will be implemented when categories are finalized
    # belongs_to :preference_category, RubberDuck.Preferences.Resources.PreferenceCategory do
    #   allow_nil? true
    #   attribute_writable? true
    # end

    has_many :user_preferences, RubberDuck.Preferences.Resources.UserPreference do
      destination_attribute :preference_key
      source_attribute :preference_key
    end

    has_many :project_preferences, RubberDuck.Preferences.Resources.ProjectPreference do
      destination_attribute :preference_key
      source_attribute :preference_key
    end

    has_many :validations, RubberDuck.Preferences.Resources.PreferenceValidation do
      destination_attribute :preference_key
      source_attribute :preference_key
    end
  end

  calculations do
    calculate :usage_count, :integer, expr(count(user_preferences, query: [])) do
      description "Number of users who have overridden this preference"
    end

    calculate :is_deprecated, :boolean, expr(deprecated == true) do
      description "Whether this preference is deprecated"
    end

    # Note: Complex calculations simplified for initial implementation
  end

  identities do
    identity :unique_preference_key, [:preference_key] do
      description "Each preference key must be unique across the system"
    end

    identity :unique_replacement, [:replacement_key] do
      where expr(not is_nil(replacement_key))
      description "Replacement keys must be unique when specified"
    end
  end
end
