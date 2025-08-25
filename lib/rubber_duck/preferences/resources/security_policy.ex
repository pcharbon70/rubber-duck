defmodule RubberDuck.Preferences.Resources.SecurityPolicy do
  @moduledoc """
  Security policy resource for managing access control rules and permissions.

  Defines and manages security policies for preference access, including role-based
  access control rules, permission requirements, and security constraints for
  different types of preference operations.
  """

  use Ash.Resource,
    domain: RubberDuck.Preferences,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "security_policies"
    repo RubberDuck.Repo
  end

  code_interface do
    define :create, action: :create
    define :update, action: :update
    define :read, action: :read
    define :destroy, action: :destroy
    define :activate, action: :activate
    define :deactivate, action: :deactivate
    define :by_resource_type, args: [:resource_type], action: :read
    define :active_policies, action: :read
    define :by_priority, action: :read
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create a new security policy"

      accept [
        :policy_name,
        :policy_type,
        :resource_type,
        :preference_pattern,
        :required_permissions,
        :required_roles,
        :approval_required,
        :approval_roles,
        :encryption_required,
        :audit_level,
        :conditions,
        :priority,
        :active,
        :description
      ]

      validate present([:policy_name, :policy_type, :resource_type])

      change fn changeset, _context ->
        # Validate policy consistency
        changeset
        |> validate_policy_consistency()
        |> validate_pattern_syntax()
      end
    end

    update :update do
      description "Update an existing security policy"

      accept [
        :policy_name,
        :preference_pattern,
        :required_permissions,
        :required_roles,
        :approval_required,
        :approval_roles,
        :encryption_required,
        :audit_level,
        :conditions,
        :priority,
        :active,
        :description
      ]

      change fn changeset, _context ->
        changeset
        |> validate_policy_consistency()
        |> validate_pattern_syntax()
      end
    end

    update :activate do
      description "Activate a security policy"
      change set_attribute(:active, true)
    end

    update :deactivate do
      description "Deactivate a security policy"
      change set_attribute(:active, false)
    end
  end

  # Authorization policies for security policy management
  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      description "Security admins and system can read policies"
      authorize_if actor_attribute_equals(:role, :security_admin)
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action_type([:create, :update, :destroy]) do
      description "Only security admins can manage security policies"
      authorize_if actor_attribute_equals(:role, :security_admin)
    end

    policy action([:activate, :deactivate]) do
      description "Security admins can activate/deactivate policies"
      authorize_if actor_attribute_equals(:role, :security_admin)
    end
  end

  validations do
    validate fn changeset, _context ->
      validate_approval_roles_consistency(changeset)
    end

    validate fn changeset, _context ->
      validate_encryption_pattern_consistency(changeset)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :policy_name, :string do
      description "Human-readable name for the security policy"
      constraints max_length: 255
      allow_nil? false
    end

    attribute :policy_type, :atom do
      description "Type of security policy"

      constraints one_of: [
                    :access_control,
                    :approval_required,
                    :encryption_required,
                    :audit_required
                  ]

      allow_nil? false
    end

    attribute :resource_type, :string do
      description "Resource type this policy applies to (user_preference, project_preference, etc.)"
      constraints max_length: 100
      allow_nil? false
    end

    attribute :preference_pattern, :string do
      description "Pattern matching for preference keys (supports wildcards)"
      constraints max_length: 500
      allow_nil? true
    end

    attribute :required_permissions, {:array, :string} do
      description "List of permissions required to perform actions"
      default []
    end

    attribute :required_roles, {:array, :atom} do
      description "Roles that can perform actions under this policy"
      constraints items: [one_of: [:user, :admin, :security_admin, :project_admin, :read_only]]
      default []
    end

    attribute :approval_required, :boolean do
      description "Whether approval is required for actions under this policy"
      default false
    end

    attribute :approval_roles, {:array, :atom} do
      description "Roles that can approve actions under this policy"
      constraints items: [one_of: [:admin, :security_admin, :project_admin]]
      default []
    end

    attribute :encryption_required, :boolean do
      description "Whether encryption is required for values under this policy"
      default false
    end

    attribute :audit_level, :atom do
      description "Level of audit logging required"
      constraints one_of: [:none, :basic, :detailed, :full]
      default :basic
    end

    attribute :conditions, :map do
      description "Additional conditions for policy enforcement (JSON)"
      default %{}
    end

    attribute :priority, :integer do
      description "Priority for policy evaluation (higher numbers = higher priority)"
      constraints min: 1, max: 1000
      default 100
    end

    attribute :active, :boolean do
      description "Whether this policy is currently active"
      default true
    end

    attribute :description, :string do
      description "Detailed description of what this policy controls"
      constraints max_length: 1000
      allow_nil? true
    end

    timestamps()
  end

  calculations do
    calculate :policy_scope, :string, expr(resource_type)

    calculate :effective_permissions,
              :map,
              expr(%{
                roles: required_roles,
                permissions: required_permissions,
                approval_needed: approval_required,
                encryption_needed: encryption_required
              })
  end

  ## Private Validation Functions

  defp validate_policy_consistency(changeset) do
    approval_required = Ash.Changeset.get_attribute(changeset, :approval_required)
    approval_roles = Ash.Changeset.get_attribute(changeset, :approval_roles) || []

    if approval_required and Enum.empty?(approval_roles) do
      Ash.Changeset.add_error(
        changeset,
        :approval_roles,
        "Approval roles required when approval is enabled"
      )
    else
      changeset
    end
  end

  defp validate_pattern_syntax(changeset) do
    pattern = Ash.Changeset.get_attribute(changeset, :preference_pattern)

    case pattern do
      nil ->
        changeset

      "" ->
        changeset

      pattern when is_binary(pattern) ->
        try do
          # Validate that pattern can be compiled as regex if it contains wildcards
          if String.contains?(pattern, ["*", "?", "[", "]"]) do
            _compiled_regex = pattern
              |> String.replace("*", ".*")
              |> String.replace("?", ".")
              |> Regex.compile!()
          end

          changeset
        rescue
          _ -> Ash.Changeset.add_error(changeset, :preference_pattern, "Invalid pattern syntax")
        end

      _ ->
        Ash.Changeset.add_error(changeset, :preference_pattern, "Pattern must be a string")
    end
  end

  defp validate_approval_roles_consistency(changeset) do
    required_roles = Ash.Changeset.get_attribute(changeset, :required_roles) || []
    approval_roles = Ash.Changeset.get_attribute(changeset, :approval_roles) || []

    # Approval roles should be equal or higher privilege than required roles
    role_hierarchy = [:read_only, :user, :project_admin, :admin, :security_admin]

    invalid_approvers =
      Enum.filter(approval_roles, fn approval_role ->
        Enum.any?(required_roles, fn required_role ->
          get_role_level(approval_role, role_hierarchy) <
            get_role_level(required_role, role_hierarchy)
        end)
      end)

    if Enum.empty?(invalid_approvers) do
      changeset
    else
      Ash.Changeset.add_error(
        changeset,
        :approval_roles,
        "Approval roles must have equal or higher privilege than required roles"
      )
    end
  end

  defp validate_encryption_pattern_consistency(changeset) do
    encryption_required = Ash.Changeset.get_attribute(changeset, :encryption_required)
    pattern = Ash.Changeset.get_attribute(changeset, :preference_pattern)

    # If encryption is required, pattern should target sensitive data
    if encryption_required and pattern do
      if RubberDuck.Preferences.Security.EncryptionManager.sensitive_preference?(pattern) do
        changeset
      else
        Ash.Changeset.add_error(
          changeset,
          :preference_pattern,
          "Pattern should target sensitive preferences when encryption is required"
        )
      end
    else
      changeset
    end
  end

  defp get_role_level(role, hierarchy) do
    Enum.find_index(hierarchy, &(&1 == role)) || 0
  end
end
