defmodule RubberDuck.Preferences.Resources.PreferenceCategory do
  @moduledoc """
  PreferenceCategory resource for organizing preferences into hierarchical groups.

  This resource defines preference categories and subcategories for organized
  preference management, UI display, and bulk operations.
  """

  use Ash.Resource,
    domain: RubberDuck.Preferences,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "preference_categories"
    repo RubberDuck.Repo

    references do
      reference :parent_category, on_delete: :delete
    end
  end

  resource do
    description """
    PreferenceCategory organizes preferences into hierarchical groups for
    better organization, UI display, and bulk operations.

    Features:
    - Hierarchical category structure with unlimited nesting
    - UI-friendly display with icons and colors
    - Access level control per category
    - Bulk operations on category preferences
    - Usage analytics and override tracking
    - Search and filtering capabilities
    """

    short_name :preference_category
    plural_name :preference_categories
  end

  # Note: Policies will be implemented in Phase 1A.10 Security & Authorization

  code_interface do
    define :create, action: :create
    define :read, action: :read
    define :update, action: :update
    define :destroy, action: :destroy
    define :root_categories
    define :subcategories, args: [:parent_id]
    define :by_access_level, args: [:access_level]
    define :search_categories, args: [:search_term]
    define :with_preferences
    define :create_root_category, action: :create_root_category
    define :create_subcategory, action: :create_subcategory
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    read :root_categories do
      description "Get all top-level categories"

      filter expr(is_nil(parent_category_id))
      prepare build(sort: [:display_order, :name])
    end

    read :subcategories do
      description "Get subcategories of a parent category"
      argument :parent_id, :uuid, allow_nil?: false

      filter expr(parent_category_id == ^arg(:parent_id))
      prepare build(sort: [:display_order, :name])
    end

    read :by_access_level do
      description "Get categories by access level"
      argument :access_level, :atom, allow_nil?: false

      filter expr(default_access_level == ^arg(:access_level))
      prepare build(sort: [:display_order, :name])
    end

    read :search_categories do
      description "Search categories by name, description, or tags"
      argument :search_term, :string, allow_nil?: false

      filter expr(
               ilike(name, ^arg(:search_term)) or
                 ilike(display_name, ^arg(:search_term)) or
                 ilike(description, ^arg(:search_term)) or
                 ^arg(:search_term) = any(tags)
             )

      prepare build(sort: [:name])
    end

    read :with_preferences do
      description "Get categories that have preferences defined"

      prepare build(load: [:preferences_count])
      filter expr(preferences_count > 0)
      prepare build(sort: [:display_order, :name])
    end

    create :create_root_category do
      description "Create a new root category"

      accept [
        :name,
        :display_name,
        :description,
        :display_order,
        :icon,
        :color,
        :default_access_level,
        :documentation_url,
        :tags
      ]

      change set_attribute(:parent_category_id, nil)
    end

    create :create_subcategory do
      description "Create a subcategory under a parent"
      argument :parent_id, :uuid, allow_nil?: false

      accept [
        :name,
        :display_name,
        :description,
        :display_order,
        :icon,
        :color,
        :default_access_level,
        :documentation_url,
        :tags
      ]

      change set_attribute(:parent_category_id, arg(:parent_id))
    end

    update :reorder_categories do
      description "Update display order for categories"
      argument :category_orders, {:array, :map}, allow_nil?: false

      # Note: Custom change modules will be implemented in future sections
      # change {RubberDuck.Preferences.Changes.ReorderCategories,
      #         orders: arg(:category_orders)}
    end

    update :move_to_parent do
      description "Move category to different parent"
      argument :new_parent_id, :uuid, allow_nil?: true

      change set_attribute(:parent_category_id, arg(:new_parent_id))

      # Note: Custom validations will be implemented in future sections
      # validate {RubberDuck.Preferences.Validations.CircularCategoryValidation, []}
    end
  end

  preparations do
    prepare build(load: [:preferences_count, :is_root_category])
  end

  validations do
    validate match(:name, ~r/^[a-z][a-z0-9_]*$/),
      message: "Category name must be lowercase with underscores"

    validate present(:display_name),
      message: "Display name is required"

    validate present(:description),
      message: "Category description is required"

    validate compare(:display_order, greater_than_or_equal: 0),
      message: "Display order must be non-negative"

    validate {Ash.Resource.Validation.Match, attribute: :color, match: ~r/^#[0-9A-Fa-f]{6}$/},
      where: [present(:color)],
      message: "Color must be a valid hex color code"

    # Note: Custom validations will be implemented in future sections
    # validate {RubberDuck.Preferences.Validations.CircularCategoryValidation, []},
    #   message: "Category cannot be its own parent (circular reference)"
  end

  attributes do
    uuid_primary_key :category_id

    attribute :name, :string do
      allow_nil? false
      description "Category name (lowercase with underscores)"
    end

    attribute :display_name, :string do
      allow_nil? false
      description "Human-readable category name for UI"
    end

    attribute :parent_category_id, :uuid do
      allow_nil? true
      description "Parent category for nested hierarchies"
    end

    attribute :description, :string do
      allow_nil? false
      description "Category description"
    end

    attribute :display_order, :integer do
      allow_nil? false
      default 0
      description "Sort order in UI"
    end

    attribute :icon, :string do
      allow_nil? true
      description "Icon name/class for UI display"
    end

    attribute :color, :string do
      allow_nil? true
      description "Color hex code for UI theming"
    end

    attribute :default_access_level, :atom do
      allow_nil? false
      constraints one_of: [:public, :user, :admin, :superadmin]
      default :user
      description "Default access level for preferences in this category"
    end

    attribute :documentation_url, :string do
      allow_nil? true
      description "URL to documentation for this category"
    end

    attribute :tags, {:array, :string} do
      allow_nil? false
      default []
      description "Tags for categorization and search"
    end

    timestamps()
  end

  relationships do
    belongs_to :parent_category, RubberDuck.Preferences.Resources.PreferenceCategory do
      source_attribute :parent_category_id
      destination_attribute :category_id
      define_attribute? false
    end

    has_many :child_categories, RubberDuck.Preferences.Resources.PreferenceCategory do
      destination_attribute :parent_category_id
      source_attribute :category_id
    end

    has_many :system_defaults, RubberDuck.Preferences.Resources.SystemDefault do
      destination_attribute :category
      source_attribute :name
    end

    has_many :user_preferences, RubberDuck.Preferences.Resources.UserPreference do
      destination_attribute :category
      source_attribute :name
    end

    has_many :project_preferences, RubberDuck.Preferences.Resources.ProjectPreference do
      destination_attribute :category
      source_attribute :name
    end
  end

  calculations do
    calculate :preferences_count,
              :integer,
              expr(count(system_defaults, query: [filter: [deprecated: false]])) do
      description "Number of non-deprecated preferences in this category"
      load [:system_defaults]
    end

    calculate :is_root_category, :boolean, expr(is_nil(parent_category_id)) do
      description "Whether this is a top-level category"
    end

    # Note: Complex calculations simplified for initial implementation
  end

  identities do
    identity :unique_category_name, [:name] do
      description "Category names must be unique across the system"
    end

    identity :unique_display_name, [:display_name] do
      description "Display names must be unique for UI clarity"
    end
  end
end
