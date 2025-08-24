defmodule RubberDuck.Preferences.Resources.UserPreference do
  @moduledoc """
  UserPreference resource for storing user-specific preference overrides.

  This resource allows individual users to customize their RubberDuck experience
  by overriding system defaults for LLM providers, budgeting, ML features,
  code quality tools, and agent behaviors.
  """

  use Ash.Resource,
    domain: RubberDuck.Preferences,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "user_preferences"
    repo RubberDuck.Repo

    references do
      reference :user, on_delete: :delete
      reference :system_default, on_delete: :delete
    end
  end

  resource do
    description """
    UserPreference allows individual users to customize their RubberDuck experience
    by overriding system defaults. Users can set preferences for LLM providers,
    budgeting controls, ML features, code quality tools, and agent behaviors.

    The preference system supports:
    - Hierarchical inheritance from system defaults
    - Template-based preference application
    - Change tracking with audit trails
    - Security controls for sensitive preferences
    - Bulk operations for efficiency
    """

    short_name :user_preference
    plural_name :user_preferences
  end

  # Security policies for preference access control
  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
    
    policy action_type(:read) do
      description "Users can read their own preferences, admins can read any"
      
      authorize_if expr(user_id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :security_admin)
      authorize_if relating_to_actor(:user)
    end
    
    policy action_type(:create) do
      description "Users can create their own preferences"
      
      authorize_if expr(user_id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :admin)
    end
    
    policy action_type(:update) do
      description "Users can update their own preferences, with approval for sensitive ones"
      
      authorize_if expr(user_id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :admin)
      
      # Additional check for sensitive preferences would be added here
      # This would integrate with the SecurityPolicy resource
    end
    
    policy action_type(:destroy) do
      description "Users can delete their own preferences, admins can delete any"
      
      authorize_if expr(user_id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :security_admin)
    end
  end

  code_interface do
    define :create, action: :create
    define :read, action: :read
    define :update, action: :update
    define :destroy, action: :destroy
    define :by_user, args: [:user_id]
    define :by_user_and_category, args: [:user_id, :category]
    define :effective_for_user, args: [:user_id, :preference_key]
    define :overridden_by_user, args: [:user_id]
    define :recently_modified, args: [:user_id, :days]
    define :set_preference, args: [:user_id, :preference_key, :value, :notes]
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    read :by_user do
      description "Get all preferences for a specific user"
      argument :user_id, :uuid, allow_nil?: false

      filter expr(user_id == ^arg(:user_id))
      prepare build(sort: [:category, :preference_key])
    end

    read :by_user_and_category do
      description "Get user preferences in a specific category"
      argument :user_id, :uuid, allow_nil?: false
      argument :category, :string, allow_nil?: false

      filter expr(user_id == ^arg(:user_id) and category == ^arg(:category))
      prepare build(sort: [:preference_key])
    end

    read :effective_for_user do
      description "Get effective preference value for user (with system default fallback)"
      argument :user_id, :uuid, allow_nil?: false
      argument :preference_key, :string, allow_nil?: false

      prepare build(load: [:effective_value, :system_default])
      filter expr(user_id == ^arg(:user_id) and preference_key == ^arg(:preference_key))
    end

    read :overridden_by_user do
      description "Get all preferences a user has overridden"
      argument :user_id, :uuid, allow_nil?: false

      prepare build(load: [:is_overridden])
      filter expr(user_id == ^arg(:user_id) and is_overridden == true)
    end

    read :recently_modified do
      description "Get recently modified preferences for a user"
      argument :user_id, :uuid, allow_nil?: false
      argument :days, :integer, allow_nil?: false, default: 7

      filter expr(
               user_id == ^arg(:user_id) and
                 last_modified >= fragment("NOW() - INTERVAL '? days'", ^arg(:days))
             )

      prepare build(sort: [desc: :last_modified])
    end

    create :set_preference do
      description "Set or update a user preference"
      argument :user_id, :uuid, allow_nil?: false
      argument :preference_key, :string, allow_nil?: false
      argument :value, :string, allow_nil?: false
      argument :notes, :string, allow_nil?: true

      upsert? true
      upsert_identity :unique_user_preference

      change set_attribute(:user_id, arg(:user_id))
      change set_attribute(:preference_key, arg(:preference_key))
      change set_attribute(:value, arg(:value))
      change set_attribute(:notes, arg(:notes))
      change set_attribute(:last_modified, &DateTime.utc_now/0)
      change set_attribute(:source, :manual)

      # Preference system integrations
      change {RubberDuck.Preferences.Changes.PopulateCategoryFromDefault, []}
      change {RubberDuck.Preferences.Changes.InvalidatePreferenceCache, []}
      change {RubberDuck.Preferences.Changes.TrackPreferenceSource, []}
    end

    update :apply_template do
      description "Apply template preferences to user"
      argument :template_preferences, {:array, :map}, allow_nil?: false
      argument :overwrite_existing, :boolean, allow_nil?: false, default: false

      # Note: Custom change modules will be implemented in future sections
      # change {RubberDuck.Preferences.Changes.ApplyTemplate,
      #         preferences: arg(:template_preferences),
      #         overwrite: arg(:overwrite_existing)}
      change set_attribute(:source, :template)
      change set_attribute(:last_modified, &DateTime.utc_now/0)
    end

    update :reset_to_defaults do
      description "Reset user preferences to system defaults"
      argument :categories, {:array, :string}, allow_nil?: true

      # Note: Custom change modules will be implemented in future sections
      # change {RubberDuck.Preferences.Changes.ResetToDefaults,
      #         categories: arg(:categories)}
    end

    destroy :clear_category do
      description "Remove all user preferences in a category"
      argument :user_id, :uuid, allow_nil?: false
      argument :category, :string, allow_nil?: false

      filter expr(user_id == ^arg(:user_id) and category == ^arg(:category))
    end
  end

  preparations do
    prepare build(load: [:is_overridden])
  end

  validations do
    validate match(:preference_key, ~r/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$/),
      message: "Preference key must be dot-notation lowercase with underscores"

    validate match(:category, ~r/^[a-z][a-z0-9_]*$/),
      message: "Category must be lowercase with underscores"

    validate present(:modified_by, when: [source: [:api, :migration]]),
      message: "API and migration changes must specify who made the change"

    validate absent(:notes, when: [auto_generated: true]),
      message: "Auto-generated preferences cannot have user notes"
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
      description "Link to user identity"
    end

    attribute :preference_key, :string do
      allow_nil? false
      description "Links to SystemDefault.preference_key"
    end

    attribute :value, :string do
      allow_nil? false
      description "User's preferred value (stored as JSON for flexibility)"
    end

    attribute :category, :string do
      allow_nil? false
      description "Inherited from SystemDefault for denormalized querying"
    end

    attribute :source, :atom do
      allow_nil? false
      constraints one_of: [:manual, :template, :migration, :import, :api]
      default :manual
      description "How this preference was set"
    end

    attribute :last_modified, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      description "When preference was last changed"
    end

    attribute :modified_by, :string do
      allow_nil? true
      description "Who made the change (for admin modifications)"
    end

    attribute :active, :boolean do
      allow_nil? false
      default true
      description "Enable/disable specific user preferences"
    end

    attribute :notes, :string do
      allow_nil? true
      description "Optional user notes about preference choice"
    end

    attribute :auto_generated, :boolean do
      allow_nil? false
      default false
      description "Whether this preference was auto-generated from usage patterns"
    end

    timestamps()
  end

  relationships do
    belongs_to :user, RubberDuck.Accounts.User do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :system_default, RubberDuck.Preferences.Resources.SystemDefault do
      source_attribute :preference_key
      destination_attribute :preference_key
      define_attribute? false
    end

    has_many :history_entries, RubberDuck.Preferences.Resources.PreferenceHistory do
      destination_attribute :user_id
      source_attribute :user_id
      filter expr(preference_key == parent_expr(preference_key))
    end
  end

  calculations do
    calculate :is_overridden, :boolean, expr(value != system_default.default_value) do
      description "Whether user has overridden the system default"
      load [:system_default]
    end

    # Note: Complex calculations simplified for initial implementation
  end

  identities do
    identity :unique_user_preference, [:user_id, :preference_key] do
      description "Each user can have only one value per preference key"
    end
  end
end
