defmodule RubberDuck.Preferences.Security.AccessControl do
  @moduledoc """
  Role-based access control system for preference management.
  
  Provides comprehensive RBAC functionality including role assignment,
  permission checking, policy evaluation, and access decision logic.
  Integrates with Ash Framework's authorization system for declarative
  access control.
  """
  
  alias RubberDuck.Preferences.Resources.SecurityPolicy
  alias RubberDuck.Preferences.Security.AuditLogger
  
  require Logger
  
  @doc """
  Check if a user has permission to perform an action on a preference.
  
  ## Examples
  
      AccessControl.authorize_preference_access(
        user,
        "read",
        "llm.api_key",
        %{resource_type: "user_preference"}
      )
  """
  @spec authorize_preference_access(
    actor :: map(),
    action :: String.t(),
    preference_key :: String.t(),
    context :: map()
  ) :: {:ok, :authorized} | {:error, :unauthorized} | {:error, :approval_required}
  def authorize_preference_access(actor, action, preference_key, context \\ %{}) do
    # Log access attempt
    AuditLogger.log_access_event(%{
      user_id: actor.id,
      action: action,
      preference_key: preference_key,
      resource_type: context[:resource_type],
      timestamp: DateTime.utc_now()
    })
    
    case get_applicable_policies(preference_key, context[:resource_type]) do
      {:ok, policies} ->
        evaluate_policies(actor, action, preference_key, policies, context)
      
      {:error, reason} ->
        Logger.warning("Failed to get security policies: #{inspect(reason)}")
        {:error, :unauthorized}
    end
  end
  
  @doc """
  Check if a user has a specific role.
  """
  @spec has_role?(actor :: map(), role :: atom()) :: boolean()
  def has_role?(%{role: user_role}, required_role) when is_atom(required_role) do
    user_role == required_role or is_higher_role?(user_role, required_role)
  end
  
  def has_role?(_actor, _role), do: false
  
  @doc """
  Check if a user has any of the specified roles.
  """
  @spec has_any_role?(actor :: map(), roles :: [atom()]) :: boolean()
  def has_any_role?(actor, roles) when is_list(roles) do
    Enum.any?(roles, &has_role?(actor, &1))
  end
  
  @doc """
  Check if a user has a specific permission.
  """
  @spec has_permission?(actor :: map(), permission :: String.t()) :: boolean()
  def has_permission?(actor, permission) do
    actor_permissions = get_actor_permissions(actor)
    permission in actor_permissions
  end
  
  @doc """
  Get all permissions for an actor based on their role.
  """
  @spec get_actor_permissions(actor :: map()) :: [String.t()]
  def get_actor_permissions(%{role: role} = actor) do
    base_permissions = get_role_permissions(role)
    
    # Add any additional permissions from delegation or temporary grants
    additional_permissions = get_delegated_permissions(actor)
    
    Enum.uniq(base_permissions ++ additional_permissions)
  end
  
  def get_actor_permissions(_actor), do: []
  
  @doc """
  Evaluate security policies for a specific preference access attempt.
  """
  @spec evaluate_policies(
    actor :: map(),
    action :: String.t(), 
    preference_key :: String.t(),
    policies :: [map()],
    context :: map()
  ) :: {:ok, :authorized} | {:error, :unauthorized} | {:error, :approval_required}
  def evaluate_policies(actor, action, preference_key, policies, context) do
    # Sort policies by priority (highest first)
    sorted_policies = Enum.sort_by(policies, & &1.priority, :desc)
    
    case evaluate_policy_chain(actor, action, preference_key, sorted_policies, context) do
      :authorized -> {:ok, :authorized}
      :approval_required -> {:error, :approval_required}
      :unauthorized -> {:error, :unauthorized}
    end
  end
  
  ## Private Functions
  
  defp get_applicable_policies(preference_key, resource_type) do
    case SecurityPolicy.active_policies() do
      {:ok, policies} ->
        applicable = Enum.filter(policies, fn policy ->
          matches_resource_type?(policy, resource_type) and
          matches_preference_pattern?(policy, preference_key)
        end)
        
        {:ok, applicable}
      
      error -> error
    end
  end
  
  defp matches_resource_type?(policy, resource_type) do
    policy.resource_type == "all" or policy.resource_type == resource_type
  end
  
  defp matches_preference_pattern?(policy, preference_key) do
    case policy.preference_pattern do
      nil -> true
      "" -> true
      pattern -> pattern_matches?(pattern, preference_key)
    end
  end
  
  defp pattern_matches?(pattern, preference_key) do
    if String.contains?(pattern, ["*", "?", "[", "]"]) do
      regex_pattern = pattern
        |> String.replace("*", ".*")
        |> String.replace("?", ".")
      
      case Regex.compile(regex_pattern) do
        {:ok, regex} -> Regex.match?(regex, preference_key)
        {:error, _} -> false
      end
    else
      pattern == preference_key
    end
  end
  
  defp evaluate_policy_chain(_actor, _action, _preference_key, [], _context) do
    # No applicable policies - default to unauthorized for security
    :unauthorized
  end
  
  defp evaluate_policy_chain(actor, action, preference_key, [policy | remaining], context) do
    case evaluate_single_policy(actor, action, preference_key, policy, context) do
      :authorized -> :authorized
      :approval_required -> :approval_required
      :unauthorized -> evaluate_policy_chain(actor, action, preference_key, remaining, context)
      :not_applicable -> evaluate_policy_chain(actor, action, preference_key, remaining, context)
    end
  end
  
  defp evaluate_single_policy(actor, action, _preference_key, policy, _context) do
    cond do
      not policy.active ->
        :not_applicable
      
      not policy_applies_to_action?(policy, action) ->
        :not_applicable
      
      has_required_roles?(actor, policy.required_roles) ->
        if policy.approval_required do
          :approval_required
        else
          :authorized
        end
      
      has_required_permissions?(actor, policy.required_permissions) ->
        if policy.approval_required do
          :approval_required
        else
          :authorized
        end
      
      true ->
        :unauthorized
    end
  end
  
  defp policy_applies_to_action?(_policy, _action) do
    # For now, all policies apply to all actions
    # This could be extended to have action-specific policies
    true
  end
  
  defp has_required_roles?(actor, required_roles) when is_list(required_roles) do
    Enum.empty?(required_roles) or has_any_role?(actor, required_roles)
  end
  
  defp has_required_permissions?(actor, required_permissions) when is_list(required_permissions) do
    Enum.empty?(required_permissions) or 
    Enum.all?(required_permissions, &has_permission?(actor, &1))
  end
  
  defp is_higher_role?(user_role, required_role) do
    role_hierarchy = [:read_only, :user, :project_admin, :admin, :security_admin]
    
    user_level = Enum.find_index(role_hierarchy, &(&1 == user_role)) || 0
    required_level = Enum.find_index(role_hierarchy, &(&1 == required_role)) || 0
    
    user_level > required_level
  end
  
  defp get_role_permissions(:read_only), do: ["read_preferences"]
  defp get_role_permissions(:user), do: [
    "read_preferences", "write_own_preferences", "read_own_preferences"
  ]
  defp get_role_permissions(:project_admin), do: [
    "read_preferences", "write_own_preferences", "read_own_preferences",
    "write_project_preferences", "read_project_preferences", "manage_project_overrides"
  ]
  defp get_role_permissions(:admin), do: [
    "read_preferences", "write_preferences", "read_all_preferences", 
    "write_project_preferences", "manage_overrides", "manage_templates"
  ]
  defp get_role_permissions(:security_admin), do: [
    "read_preferences", "write_preferences", "read_all_preferences",
    "write_project_preferences", "manage_overrides", "manage_templates",
    "manage_security_policies", "access_audit_logs", "manage_delegations"
  ]
  defp get_role_permissions(_), do: []
  
  defp get_delegated_permissions(_actor) do
    # TODO: Implement delegation system
    # This would fetch temporary permissions granted via delegation
    []
  end
end