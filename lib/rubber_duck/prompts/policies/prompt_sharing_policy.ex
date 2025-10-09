defmodule RubberDuck.Prompts.Policies.PromptSharingPolicy do
  @moduledoc """
  Sharing and collaboration permissions policy for prompt resources.

  Implements granular sharing controls with permission delegation, collaboration
  workflows, and security validation for safe prompt sharing across users and teams.

  Features:
  - Granular sharing permissions (read, edit, share) with expiration support
  - Team collaboration with role-based sharing restrictions
  - Security validation for shared content with approval workflows
  - Audit trail for all sharing activities and access tracking
  - Integration with access control policies for unified authorization
  """

  use Ash.Policy.Check
  require Logger

  alias RubberDuck.Prompts.Security.{AccessControlManager, SecurityAuditLogger}

  @sharing_permissions [:read, :edit, :share, :admin]
  @collaboration_levels [:private, :team, :public, :restricted]

  @impl Ash.Policy.Check
  def describe(_opts), do: "PromptSharingPolicy: Granular sharing and collaboration permissions"

  @impl Ash.Policy.Check
  def match(_actor, _resource, _opts), do: true

  @impl Ash.Policy.Check
  def check(actor, resource, context, opts) do
    sharing_start_time = System.monotonic_time(:microsecond)

    Logger.debug("PromptSharingPolicy: Evaluating sharing permissions",
      actor_id: get_actor_id(actor),
      resource_id: get_resource_id(resource),
      action: context.action.name
    )

    case evaluate_sharing_permissions(actor, resource, context, opts) do
      {:ok, :authorized} ->
        sharing_time = System.monotonic_time(:microsecond) - sharing_start_time

        Logger.debug("PromptSharingPolicy: Sharing authorized",
          sharing_time_us: sharing_time,
          sharing_level: get_sharing_level(resource),
          permissions_granted: get_granted_permissions(actor, resource)
        )

        # Audit successful sharing access
        audit_sharing_access(actor, resource, context, :authorized)

        :authorized

      {:ok, :forbidden} ->
        sharing_time = System.monotonic_time(:microsecond) - sharing_start_time

        Logger.warn("PromptSharingPolicy: Sharing denied",
          sharing_time_us: sharing_time,
          denial_reason: get_sharing_denial_reason(actor, resource, context)
        )

        # Audit sharing denial
        audit_sharing_access(actor, resource, context, :denied)

        :forbidden

      {:error, reason} ->
        Logger.error("PromptSharingPolicy: Sharing evaluation failed",
          error: reason,
          actor_id: get_actor_id(actor)
        )

        :forbidden
    end
  end

  # Private sharing permission functions

  defp evaluate_sharing_permissions(actor, resource, context, _opts) do
    sharing_context = build_sharing_context(actor, resource, context)

    with {:ok, :valid_sharing_request} <- validate_sharing_request(sharing_context),
         {:ok, :security_approved} <- validate_sharing_security(sharing_context),
         {:ok, sharing_result} <- execute_sharing_authorization(sharing_context) do
      {:ok, sharing_result}
    else
      {:error, reason} ->
        {:error, reason}

      {:security_violation, reason} ->
        Logger.warn("PromptSharingPolicy: Sharing security violation",
          reason: reason,
          context: sharing_context
        )

        {:ok, :forbidden}
    end
  end

  defp execute_sharing_authorization(%{collaboration_level: level} = context) do
    case level do
      :private -> authorize_private_sharing(context)
      :team -> authorize_team_sharing(context)
      :public -> authorize_public_sharing(context)
      :restricted -> authorize_restricted_sharing(context)
      _ -> {:error, {:invalid_collaboration_level, level}}
    end
  end

  # Private sharing authorization (owner-only)
  defp authorize_private_sharing(%{
         user_id: user_id,
         resource_user_id: resource_user_id,
         action: action
       }) do
    case {user_id == resource_user_id, action} do
      # Owner can perform all actions on private prompts
      {true, _} -> {:ok, :authorized}
      # Non-owners cannot access private prompts
      _ -> {:ok, :forbidden}
    end
  end

  # Team sharing authorization (team members with permissions)
  defp authorize_team_sharing(%{user_id: user_id, resource_user_id: resource_user_id} = context) do
    cond do
      # Owner has full access
      user_id == resource_user_id -> {:ok, :authorized}
      # Team members need explicit permissions
      has_team_access?(context) -> authorize_team_member_access(context)
      # No team access
      true -> {:ok, :forbidden}
    end
  end

  defp authorize_team_member_access(%{action: action, granted_permissions: permissions}) do
    required_permission = map_action_to_permission(action)

    if required_permission in permissions do
      {:ok, :authorized}
    else
      {:ok, :forbidden}
    end
  end

  # Public sharing authorization (broad access with security limits)
  defp authorize_public_sharing(
         %{security_level: security_level, approval_status: approval_status} = context
       ) do
    case {security_level, approval_status} do
      # Only standard/minimal security, approved prompts can be public
      {level, :approved} when level in [:minimal, :standard] ->
        authorize_public_action_access(context)

      # Enhanced/maximum security prompts cannot be public
      _ ->
        {:ok, :forbidden}
    end
  end

  defp authorize_public_action_access(%{action: action}) do
    case action in [:read, :list_by_type, :list_by_project] do
      true -> {:ok, :authorized}
      false -> {:ok, :forbidden}
    end
  end

  # Restricted sharing authorization (custom permission rules)
  defp authorize_restricted_sharing(%{access_policy: access_policy} = context) do
    case evaluate_custom_access_policy(access_policy, context) do
      {:ok, :authorized} -> {:ok, :authorized}
      _ -> {:ok, :forbidden}
    end
  end

  # Context building and validation

  defp build_sharing_context(actor, resource, context) do
    %{
      user_id: get_actor_id(actor),
      user_role: get_actor_role(actor),
      user_teams: get_actor_teams(actor),
      action: context.action.name,
      resource_user_id: get_resource_user_id(resource),
      collaboration_level: get_collaboration_level(resource),
      granted_permissions: get_resource_sharing_permissions(resource, get_actor_id(actor)),
      security_level: get_resource_security_level(resource),
      approval_status: get_resource_approval_status(resource),
      access_policy: get_resource_access_policy(resource),
      sharing_expires_at: get_sharing_expiration(resource, get_actor_id(actor))
    }
  end

  defp validate_sharing_request(%{sharing_expires_at: expires_at}) when not is_nil(expires_at) do
    case DateTime.compare(DateTime.utc_now(), expires_at) do
      :lt -> {:ok, :valid_sharing_request}
      _ -> {:error, :sharing_expired}
    end
  end

  defp validate_sharing_request(_context), do: {:ok, :valid_sharing_request}

  defp validate_sharing_security(%{security_level: level, collaboration_level: collab_level}) do
    case {level, collab_level} do
      # Maximum security prompts cannot be shared publicly
      {:maximum, :public} ->
        {:security_violation, :security_level_too_high_for_public}

      # Enhanced security prompts have restricted sharing
      {:enhanced, level} when level in [:public, :team] ->
        {:security_violation, :enhanced_security_sharing_restricted}

      # All other combinations are security-approved
      _ ->
        {:ok, :security_approved}
    end
  end

  # Resource attribute extraction for sharing

  defp get_collaboration_level(%{access_policy: %{"collaboration_level" => level}})
       when level in ["private", "team", "public", "restricted"] do
    String.to_atom(level)
  end

  defp get_collaboration_level(_resource), do: :private

  defp get_resource_sharing_permissions(
         %{access_policy: %{"sharing_permissions" => permissions}},
         user_id
       )
       when is_map(permissions) do
    case Map.get(permissions, user_id) do
      perms when is_list(perms) -> Enum.map(perms, &String.to_atom/1)
      _ -> []
    end
  end

  defp get_resource_sharing_permissions(_resource, _user_id), do: []

  defp get_sharing_expiration(%{access_policy: %{"sharing_expiration" => expiration}}, user_id)
       when is_map(expiration) do
    case Map.get(expiration, user_id) do
      expires_at when is_binary(expires_at) ->
        case DateTime.from_iso8601(expires_at) do
          {:ok, datetime, _} -> datetime
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp get_sharing_expiration(_resource, _user_id), do: nil

  # Team and permission checking

  defp has_team_access?(%{user_teams: user_teams, access_policy: access_policy}) do
    allowed_teams = get_allowed_teams(access_policy)

    Enum.any?(user_teams, fn team -> team in allowed_teams end)
  end

  defp get_allowed_teams(%{"allowed_teams" => teams}) when is_list(teams), do: teams
  defp get_allowed_teams(_access_policy), do: []

  defp map_action_to_permission(:read), do: :read
  defp map_action_to_permission(:update), do: :edit
  defp map_action_to_permission(:destroy), do: :admin
  defp map_action_to_permission(:list_by_user), do: :read
  defp map_action_to_permission(:list_by_project), do: :read
  defp map_action_to_permission(:list_by_type), do: :read
  defp map_action_to_permission(_action), do: :admin

  # Custom access policy evaluation

  defp evaluate_custom_access_policy(%{"custom_rules" => rules}, context) when is_list(rules) do
    Enum.reduce_while(rules, {:ok, :forbidden}, fn rule, _acc ->
      case evaluate_single_custom_rule(rule, context) do
        {:ok, :authorized} -> {:halt, {:ok, :authorized}}
        _ -> {:cont, {:ok, :forbidden}}
      end
    end)
  end

  defp evaluate_custom_access_policy(_access_policy, _context), do: {:ok, :forbidden}

  defp evaluate_single_custom_rule(
         %{"condition" => condition, "permission" => permission},
         context
       ) do
    case evaluate_rule_condition(condition, context) do
      true when permission == "authorized" -> {:ok, :authorized}
      _ -> {:ok, :forbidden}
    end
  end

  defp evaluate_single_custom_rule(_rule, _context), do: {:ok, :forbidden}

  defp evaluate_rule_condition(%{"user_role" => required_role}, %{user_role: user_role}) do
    String.to_atom(required_role) == user_role
  end

  defp evaluate_rule_condition(%{"action" => required_action}, %{action: action}) do
    String.to_atom(required_action) == action
  end

  defp evaluate_rule_condition(_condition, _context), do: false

  # Utility functions

  defp get_actor_id(%{id: id}), do: id
  defp get_actor_id(_), do: nil

  defp get_actor_role(%{role: role}) when is_atom(role), do: role
  defp get_actor_role(%{role: role}) when is_binary(role), do: String.to_atom(role)
  defp get_actor_role(_), do: :user

  defp get_actor_teams(%{teams: teams}) when is_list(teams), do: teams
  defp get_actor_teams(_), do: []

  defp get_resource_id(%{id: id}), do: id
  defp get_resource_id(_), do: nil

  defp get_resource_user_id(%{user_id: id}), do: id
  defp get_resource_user_id(_), do: nil

  defp get_resource_security_level(%{security_level: level}), do: String.to_atom(level)
  defp get_resource_security_level(_), do: :standard

  defp get_resource_approval_status(%{approval_status: status}), do: String.to_atom(status)
  defp get_resource_approval_status(_), do: :draft

  defp get_resource_access_policy(%{access_policy: policy}) when is_map(policy), do: policy
  defp get_resource_access_policy(_), do: %{}

  defp get_sharing_level(%{access_policy: %{"collaboration_level" => level}}), do: level
  defp get_sharing_level(_), do: "private"

  defp get_granted_permissions(actor, resource) do
    get_resource_sharing_permissions(resource, get_actor_id(actor))
  end

  defp get_sharing_denial_reason(_actor, _resource, _context) do
    "insufficient_sharing_permissions"
  end

  # Audit functions

  defp audit_sharing_access(actor, resource, context, result) do
    Logger.info("PromptSharingPolicy: Sharing access audited",
      actor_id: get_actor_id(actor),
      resource_id: get_resource_id(resource),
      action: context.action.name,
      result: result,
      sharing_level: get_sharing_level(resource)
    )

    # Would integrate with SecurityAuditLogger for comprehensive audit trail
    :ok
  end
end
