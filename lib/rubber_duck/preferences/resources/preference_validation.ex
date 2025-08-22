defmodule RubberDuck.Preferences.Resources.PreferenceValidation do
  @moduledoc """
  PreferenceValidation resource for storing validation rules.

  This resource defines validation rules for preference values, including
  range checks, enumeration validation, regex patterns, and cross-preference
  dependency validation.
  """

  use Ash.Resource,
    domain: RubberDuck.Preferences,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "preference_validations"
    repo RubberDuck.Repo

    references do
      reference :system_default, on_delete: :delete
    end
  end

  resource do
    description """
    PreferenceValidation defines validation rules for preference values,
    ensuring data integrity and preventing invalid configurations.

    Supports multiple validation types:
    - Range validation for numeric values
    - Enumeration validation for predefined choices
    - Regex validation for pattern matching
    - Function validation for custom logic
    - Dependency validation for cross-preference rules

    Features:
    - Configurable validation severity (error, warning, info)
    - Execution order control for multiple validations
    - Conditional validation based on other preferences
    - Custom error messages for user-friendly feedback
    """

    short_name :preference_validation
    plural_name :preference_validations
  end

  # Note: Policies will be implemented in Phase 1A.10 Security & Authorization

  code_interface do
    define :create, action: :create
    define :read, action: :read
    define :update, action: :update
    define :destroy, action: :destroy
    define :by_preference, args: [:preference_key]
    define :by_type, args: [:validation_type]
    define :by_severity, args: [:severity]
    define :create_range_validation, action: :create_range_validation
    define :create_enum_validation, action: :create_enum_validation
    define :create_regex_validation, action: :create_regex_validation
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    read :by_preference do
      description "Get all validations for a specific preference"
      argument :preference_key, :string, allow_nil?: false

      filter expr(preference_key == ^arg(:preference_key) and active == true)
      prepare build(sort: [:order, :validation_id])
    end

    read :by_type do
      description "Get validations of a specific type"
      argument :validation_type, :atom, allow_nil?: false

      filter expr(validation_type == ^arg(:validation_type) and active == true)
      prepare build(sort: [:preference_key, :order])
    end

    read :by_severity do
      description "Get validations of a specific severity"
      argument :severity, :atom, allow_nil?: false

      filter expr(severity == ^arg(:severity) and active == true)
      prepare build(sort: [:preference_key, :order])
    end

    create :create_range_validation do
      description "Create a range validation rule"
      argument :preference_key, :string, allow_nil?: false
      argument :min_value, :string, allow_nil?: false
      argument :max_value, :string, allow_nil?: false
      argument :error_message, :string, allow_nil?: true

      change set_attribute(:preference_key, arg(:preference_key))
      change set_attribute(:validation_type, :range)

      change set_attribute(:validation_rule, %{
               min: arg(:min_value),
               max: arg(:max_value)
             })

      change set_attribute(
               :error_message,
               arg(:error_message) ||
                 "Value must be between #{arg(:min_value)} and #{arg(:max_value)}"
             )
    end

    create :create_enum_validation do
      description "Create an enumeration validation rule"
      argument :preference_key, :string, allow_nil?: false
      argument :allowed_values, {:array, :string}, allow_nil?: false
      argument :error_message, :string, allow_nil?: true

      change set_attribute(:preference_key, arg(:preference_key))
      change set_attribute(:validation_type, :enum)

      change set_attribute(:validation_rule, %{
               allowed_values: arg(:allowed_values)
             })

      change set_attribute(
               :error_message,
               arg(:error_message) || "Value must be one of the allowed values"
             )
    end

    create :create_regex_validation do
      description "Create a regex pattern validation rule"
      argument :preference_key, :string, allow_nil?: false
      argument :pattern, :string, allow_nil?: false
      argument :error_message, :string, allow_nil?: false

      change set_attribute(:preference_key, arg(:preference_key))
      change set_attribute(:validation_type, :regex)

      change set_attribute(:validation_rule, %{
               pattern: arg(:pattern)
             })

      change set_attribute(:error_message, arg(:error_message))
    end

    update :activate do
      description "Activate validation rule"

      change set_attribute(:active, true)
    end

    update :deactivate do
      description "Deactivate validation rule"

      change set_attribute(:active, false)
    end
  end

  preparations do
    prepare build(load: [:is_system_validation])
  end

  validations do
    validate match(:preference_key, ~r/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$/),
      message: "Preference key must be dot-notation lowercase with underscores"

    validate present(:validation_rule),
      message: "Validation rule is required"

    validate present(:error_message),
      message: "Error message is required"

    validate compare(:order, greater_than_or_equal: 0),
      message: "Order must be non-negative"

    # Note: Custom validations will be implemented in future sections
    # validate {RubberDuck.Preferences.Validations.ValidationRuleStructureValidation, []},
    #   message: "Validation rule structure must match validation type"
  end

  attributes do
    uuid_primary_key :validation_id

    attribute :preference_key, :string do
      allow_nil? false
      description "Which preference this validates"
    end

    attribute :validation_type, :atom do
      allow_nil? false
      constraints one_of: [:range, :enum, :regex, :function, :dependency, :custom]
      description "Type of validation to perform"
    end

    attribute :validation_rule, :map do
      allow_nil? false
      description "The validation rule definition (structure varies by type)"
    end

    attribute :error_message, :string do
      allow_nil? false
      description "Custom error message for validation failure"
    end

    attribute :severity, :atom do
      allow_nil? false
      constraints one_of: [:error, :warning, :info]
      default :error
      description "Validation failure severity"
    end

    attribute :active, :boolean do
      allow_nil? false
      default true
      description "Enable/disable validation rule"
    end

    attribute :order, :integer do
      allow_nil? false
      default 0
      description "Execution order for multiple validations (lower executes first)"
    end

    attribute :stop_on_failure, :boolean do
      allow_nil? false
      default true
      description "Whether to stop validation chain on failure"
    end

    timestamps()
  end

  relationships do
    belongs_to :system_default, RubberDuck.Preferences.Resources.SystemDefault do
      source_attribute :preference_key
      destination_attribute :preference_key
      define_attribute? false
    end

    # Note: ValidationResult relationship will be implemented in future sections
    # has_many :validation_results, RubberDuck.Preferences.Resources.ValidationResult do
    #   destination_attribute :validation_id
    #   source_attribute :validation_id
    # end
  end

  calculations do
    calculate :is_system_validation, :boolean, expr(not is_nil(system_default)) do
      description "Whether this validates a system default preference"
      load [:system_default]
    end

    # Note: Complex calculations simplified for initial implementation
  end
end
