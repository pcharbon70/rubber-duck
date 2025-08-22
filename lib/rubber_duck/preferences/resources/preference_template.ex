defmodule RubberDuck.Preferences.Resources.PreferenceTemplate do
  @moduledoc """
  PreferenceTemplate resource for reusable preference sets.

  This resource enables creation and sharing of preference templates for common
  scenarios (Conservative, Balanced, Aggressive), team standardization, and
  configuration marketplace functionality.
  """

  use Ash.Resource,
    domain: RubberDuck.Preferences,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "preference_templates"
    repo RubberDuck.Repo

    references do
      reference :created_by_user, on_delete: :nilify
    end
  end

  resource do
    description """
    PreferenceTemplate enables creation and sharing of reusable preference sets
    for common scenarios, team standardization, and configuration marketplace.

    Templates support:
    - Creation from existing user/project preferences
    - Public marketplace with ratings and reviews
    - Team-specific template sharing
    - Version tracking and deprecation management
    - Usage analytics and popularity scoring
    - Bulk preference application
    """

    short_name :preference_template
    plural_name :preference_templates
  end

  # Note: Policies will be implemented in Phase 1A.10 Security & Authorization

  code_interface do
    define :create, action: :create
    define :read, action: :read
    define :update, action: :update
    define :destroy, action: :destroy
    define :by_category, args: [:category]
    define :by_type, args: [:template_type]
    define :public_templates
    define :featured_templates
    define :search_templates, args: [:search_term]
    define :by_creator, args: [:user_id]
    define :create_from_preferences, action: :create_from_preferences
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    read :by_category do
      description "Get templates in a specific category"
      argument :category, :string, allow_nil?: false

      filter expr(category == ^arg(:category) and deprecated == false)
      prepare build(sort: [desc: :popularity_score])
    end

    read :by_type do
      description "Get templates of a specific type"
      argument :template_type, :atom, allow_nil?: false

      filter expr(template_type == ^arg(:template_type) and deprecated == false)
      prepare build(sort: [:name])
    end

    read :public_templates do
      description "Get all publicly available templates"

      filter expr(template_type in [:public, :system] and deprecated == false)
      prepare build(sort: [desc: :popularity_score])
    end

    read :featured_templates do
      description "Get featured templates for marketplace"

      filter expr(featured == true and deprecated == false)
      prepare build(sort: [desc: :popularity_score])
    end

    read :search_templates do
      description "Search templates by name, description, or tags"
      argument :search_term, :string, allow_nil?: false

      filter expr(
               ilike(name, ^arg(:search_term)) or
                 ilike(description, ^arg(:search_term)) or
                 ^arg(:search_term) = any(tags)
             )

      prepare build(sort: [desc: :popularity_score])
    end

    read :by_creator do
      description "Get templates created by a specific user"
      argument :user_id, :uuid, allow_nil?: false

      filter expr(created_by == ^arg(:user_id))
      prepare build(sort: [desc: :created_at])
    end

    create :create_from_preferences do
      description "Create template from existing user/project preferences"
      argument :source_user_id, :uuid, allow_nil?: true
      argument :source_project_id, :uuid, allow_nil?: true
      argument :include_categories, {:array, :string}, allow_nil?: false, default: []
      argument :template_name, :string, allow_nil?: false
      argument :template_description, :string, allow_nil?: false

      # Note: Custom change modules will be implemented in future sections
      # change {RubberDuck.Preferences.Changes.CreateTemplateFromPreferences,
      #         source_user_id: arg(:source_user_id),
      #         source_project_id: arg(:source_project_id),
      #         categories: arg(:include_categories)}

      change set_attribute(:name, arg(:template_name))
      change set_attribute(:description, arg(:template_description))
    end

    update :apply_to_user do
      description "Apply template to user preferences"
      argument :user_id, :uuid, allow_nil?: false
      argument :overwrite_existing, :boolean, allow_nil?: false, default: false

      # Note: Custom change modules will be implemented in future sections
      # change {RubberDuck.Preferences.Changes.ApplyTemplateToUser,
      #         user_id: arg(:user_id),
      #         overwrite: arg(:overwrite_existing)}

      change atomic_update(:usage_count, expr(usage_count + 1))
    end

    update :apply_to_project do
      description "Apply template to project preferences"
      argument :project_id, :uuid, allow_nil?: false
      argument :approved_by, :uuid, allow_nil?: false
      argument :override_reason, :string, allow_nil?: false

      # Note: Custom change modules will be implemented in future sections
      # change {RubberDuck.Preferences.Changes.ApplyTemplateToProject,
      #         project_id: arg(:project_id),
      #         approved_by: arg(:approved_by),
      #         reason: arg(:override_reason)}

      change atomic_update(:usage_count, expr(usage_count + 1))
    end

    update :rate_template do
      description "Rate a template"
      argument :user_id, :uuid, allow_nil?: false
      argument :rating, :decimal, allow_nil?: false

      # Note: Custom change modules will be implemented in future sections
      # change {RubberDuck.Preferences.Changes.UpdateTemplateRating,
      #         user_id: arg(:user_id),
      #         rating: arg(:rating)}
    end

    update :increment_usage do
      description "Increment template usage count"

      change atomic_update(:usage_count, expr(usage_count + 1))
    end

    update :feature_template do
      description "Feature template in marketplace"

      change set_attribute(:featured, true)
    end

    update :deprecate_template do
      description "Deprecate template"
      argument :replacement_template_id, :uuid, allow_nil?: false

      change set_attribute(:deprecated, true)
      change set_attribute(:replacement_template_id, arg(:replacement_template_id))
    end
  end

  preparations do
    prepare build(load: [:popularity_score, :is_public, :can_be_shared])
  end

  validations do
    validate present(:name),
      message: "Template name is required"

    validate present(:description),
      message: "Template description is required"

    validate match(:category, ~r/^[a-z][a-z0-9_]*$/),
      message: "Category must be lowercase with underscores"

    validate compare(:rating,
               greater_than_or_equal: 1.0,
               less_than_or_equal: 5.0,
               when: present(:rating)
             ),
             message: "Rating must be between 1.0 and 5.0"

    validate compare(:version, greater_than: 0),
      message: "Version must be positive"

    # Note: Custom validations will be implemented in future sections
    # validate {RubberDuck.Preferences.Validations.TemplatePreferencesValidation, []},
    #   message: "Template preferences must reference valid system defaults"

    validate present(:replacement_template_id, when: [deprecated: true]),
      message: "Deprecated templates must specify a replacement"
  end

  attributes do
    uuid_primary_key :template_id

    attribute :name, :string do
      allow_nil? false
      description "Template name (e.g., 'Conservative LLM Usage')"
    end

    attribute :description, :string do
      allow_nil? false
      description "Detailed template description"
    end

    attribute :category, :string do
      allow_nil? false
      description "Template category (development, security, performance, etc.)"
    end

    attribute :preferences, :map do
      allow_nil? false
      description "Map of preference_key -> value defining the template"
    end

    attribute :template_type, :atom do
      allow_nil? false
      constraints one_of: [:system, :team, :public, :private]
      default :private
      description "Template visibility and sharing level"
    end

    attribute :created_by, :uuid do
      allow_nil? false
      description "Template creator"
    end

    attribute :version, :integer do
      allow_nil? false
      default 1
      description "Template version for evolution tracking"
    end

    attribute :usage_count, :integer do
      allow_nil? false
      default 0
      description "How many times template has been applied"
    end

    attribute :rating, :decimal do
      allow_nil? true
      description "Average user rating (1.0 - 5.0)"
    end

    attribute :rating_count, :integer do
      allow_nil? false
      default 0
      description "Number of ratings received"
    end

    attribute :tags, {:array, :string} do
      allow_nil? false
      default []
      description "Tags for searchability and categorization"
    end

    attribute :compatible_versions, {:array, :string} do
      allow_nil? false
      default ["*"]
      description "System versions this template is compatible with"
    end

    attribute :featured, :boolean do
      allow_nil? false
      default false
      description "Whether template is featured in marketplace"
    end

    attribute :deprecated, :boolean do
      allow_nil? false
      default false
      description "Whether template is deprecated"
    end

    attribute :replacement_template_id, :uuid do
      allow_nil? true
      description "Replacement template for deprecated templates"
    end

    timestamps()
  end

  relationships do
    belongs_to :created_by_user, RubberDuck.Accounts.User do
      source_attribute :created_by
      destination_attribute :id
      define_attribute? false
    end

    belongs_to :replacement_template, RubberDuck.Preferences.Resources.PreferenceTemplate do
      source_attribute :replacement_template_id
      destination_attribute :template_id
      define_attribute? false
    end

    has_many :history_entries, RubberDuck.Preferences.Resources.PreferenceHistory do
      destination_attribute :source_template_id
      source_attribute :template_id
    end

    # Note: TemplateRating relationship will be implemented in future sections
    # has_many :ratings, RubberDuck.Preferences.Resources.TemplateRating do
    #   destination_attribute :template_id
    #   source_attribute :template_id
    # end
  end

  calculations do
    # Note: Complex JSON calculations simplified for initial implementation
    # These would be implemented as custom functions in production

    calculate :popularity_score,
              :float,
              expr(
                if usage_count == 0 do
                  0.0
                else
                  usage_count * 0.7 + rating * rating_count * 0.3
                end
              ) do
      description "Calculated popularity score combining usage and ratings"
    end

    calculate :is_public, :boolean, expr(template_type in [:public, :system]) do
      description "Whether template is publicly accessible"
    end

    calculate :can_be_shared, :boolean, expr(template_type in [:public, :team]) do
      description "Whether template can be shared with others"
    end

    # Note: Complex query calculations simplified for initial implementation
  end

  identities do
    identity :unique_template_name, [:name, :created_by] do
      description "Each user can have only one template with a given name"
    end
  end
end
