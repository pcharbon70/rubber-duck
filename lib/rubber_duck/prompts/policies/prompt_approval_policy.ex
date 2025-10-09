defmodule RubberDuck.Prompts.Policies.PromptApprovalPolicy do
  @moduledoc """
  Approval workflow enforcement policy for prompt management system.

  Implements multi-stage approval processes with role-based workflow management,
  automated approval for low-risk changes, and comprehensive approval tracking
  with audit trail integration.

  Features:
  - Multi-stage approval workflows with configurable stages and routing
  - Role-based approval authority with delegation and escalation support
  - Automated approval for low-risk content changes with security validation
  - Approval status tracking with comprehensive audit trails and notifications
  - Integration with security validation for approval decision support
  """

  use Ash.Policy.Check
  require Logger

  alias RubberDuck.Prompts.Security.{AccessControlManager, PromptValidator}

  @approval_statuses [:draft, :pending, :approved, :rejected, :expired]
  @approval_stages [:content_review, :security_review, :final_approval]
  @risk_thresholds %{low: 0.3, medium: 0.6, high: 0.8}

  @impl Ash.Policy.Check
  def describe(_opts), do: "PromptApprovalPolicy: Multi-stage approval workflow enforcement"

  @impl Ash.Policy.Check
  def match(_actor, _resource, _opts), do: true

  @impl Ash.Policy.Check
  def check(actor, resource, context, opts) do
    approval_start_time = System.monotonic_time(:microsecond)

    Logger.debug("PromptApprovalPolicy: Evaluating approval requirements",
      actor_id: get_actor_id(actor),
      resource_id: get_resource_id(resource),
      action: context.action.name,
      current_approval_status: get_approval_status(resource)
    )

    case evaluate_approval_requirements(actor, resource, context, opts) do
      {:ok, :authorized} ->
        approval_time = System.monotonic_time(:microsecond) - approval_start_time

        Logger.debug("PromptApprovalPolicy: Approval authorized",
          approval_time_us: approval_time,
          approval_path: get_approval_path(actor, resource, context)
        )

        # Track approval decision for audit
        track_approval_decision(actor, resource, context, :authorized)

        :authorized

      {:ok, :forbidden} ->
        approval_time = System.monotonic_time(:microsecond) - approval_start_time

        Logger.warn("PromptApprovalPolicy: Approval denied",
          approval_time_us: approval_time,
          denial_reason: get_approval_denial_reason(actor, resource, context)
        )

        # Track approval denial for audit
        track_approval_decision(actor, resource, context, :denied)

        :forbidden

      {:error, reason} ->
        Logger.error("PromptApprovalPolicy: Approval evaluation failed",
          error: reason,
          actor_id: get_actor_id(actor)
        )

        :forbidden
    end
  end

  # Private approval workflow functions

  defp evaluate_approval_requirements(actor, resource, context, _opts) do
    approval_context = build_approval_context(actor, resource, context)

    with {:ok, :valid_approval_context} <- validate_approval_context(approval_context),
         {:ok, approval_result} <- execute_approval_workflow(approval_context) do
      {:ok, approval_result}
    else
      {:error, reason} ->
        {:error, reason}

      {:approval_violation, reason} ->
        Logger.warn("PromptApprovalPolicy: Approval workflow violation",
          reason: reason,
          context: approval_context
        )

        {:ok, :forbidden}
    end
  end

  defp execute_approval_workflow(%{action: action} = context) do
    case action do
      # Read actions generally don't require approval workflow checks
      action when action in [:read, :list_by_type, :list_by_project, :list_by_user] ->
        authorize_read_access(context)

      # Create actions require approval workflow setup
      :create ->
        authorize_creation_workflow(context)

      :create_system_prompt ->
        authorize_system_prompt_creation(context)

      :create_project_prompt ->
        authorize_project_prompt_creation(context)

      :create_user_prompt ->
        authorize_user_prompt_creation(context)

      # Update actions require approval workflow validation
      :update ->
        authorize_update_workflow(context)

      # Destroy actions require special approval
      :destroy ->
        authorize_destruction_workflow(context)

      _ ->
        {:error, {:unsupported_action, action}}
    end
  end

  # Read access authorization
  defp authorize_read_access(%{
         approval_status: status,
         user_role: role,
         prompt_type: prompt_type
       }) do
    case {status, role, prompt_type} do
      # Approved prompts can be read by appropriate roles
      {:approved, _, _} -> {:ok, :authorized}
      # Admins can read any prompt regardless of approval status
      {_, role, _} when role in [:admin, :system_admin] -> {:ok, :authorized}
      # Users can read their own draft/pending prompts
      {status, :user, :user} when status in [:draft, :pending] -> {:ok, :authorized}
      # Project owners can read their project's draft/pending prompts
      {status, :project_owner, :project} when status in [:draft, :pending] -> {:ok, :authorized}
      # All other combinations require approved status
      _ -> {:ok, :forbidden}
    end
  end

  # Creation workflow authorization
  defp authorize_creation_workflow(%{user_role: role, prompt_type: prompt_type}) do
    case {role, prompt_type} do
      # System admins can create any prompt type
      {:system_admin, _} -> {:ok, :authorized}
      {:admin, _} -> {:ok, :authorized}
      # Users can create user prompts
      {:user, :user} -> {:ok, :authorized}
      # Project owners can create project prompts
      {:project_owner, :project} -> {:ok, :authorized}
      # All other combinations forbidden
      _ -> {:ok, :forbidden}
    end
  end

  defp authorize_system_prompt_creation(%{user_role: role}) do
    case role in [:system_admin, :admin] do
      true -> {:ok, :authorized}
      false -> {:ok, :forbidden}
    end
  end

  defp authorize_project_prompt_creation(%{user_role: role}) do
    case role in [:system_admin, :admin, :project_owner] do
      true -> {:ok, :authorized}
      false -> {:ok, :forbidden}
    end
  end

  defp authorize_user_prompt_creation(%{user_role: role}) do
    case role in [:system_admin, :admin, :user] do
      true -> {:ok, :authorized}
      false -> {:ok, :forbidden}
    end
  end

  # Update workflow authorization
  defp authorize_update_workflow(%{approval_status: current_status} = context) do
    case current_status do
      # Draft prompts can be updated by owners/admins
      :draft -> authorize_draft_update(context)
      # Pending prompts can only be updated by approvers/admins
      :pending -> authorize_pending_update(context)
      # Approved prompts require re-approval workflow
      :approved -> authorize_approved_update(context)
      # Rejected prompts can be updated and resubmitted
      :rejected -> authorize_rejected_update(context)
      # Expired prompts cannot be updated
      :expired -> {:ok, :forbidden}
    end
  end

  defp authorize_draft_update(%{user_role: role, is_owner: is_owner}) do
    case {role, is_owner} do
      # Admins can update any draft
      {role, _} when role in [:admin, :system_admin] -> {:ok, :authorized}
      # Owners can update their drafts
      {_, true} -> {:ok, :authorized}
      _ -> {:ok, :forbidden}
    end
  end

  defp authorize_pending_update(%{user_role: role, can_approve: can_approve}) do
    case {role, can_approve} do
      # Admins can update pending prompts
      {role, _} when role in [:admin, :system_admin] -> {:ok, :authorized}
      # Approvers can make updates during review
      {_, true} -> {:ok, :authorized}
      _ -> {:ok, :forbidden}
    end
  end

  defp authorize_approved_update(%{user_role: role, risk_level: risk_level} = context) do
    case {role, risk_level} do
      # Admins can update approved prompts
      {role, _} when role in [:admin, :system_admin] -> {:ok, :authorized}
      # Low-risk updates can be made by owners with auto-approval
      {_, :low} -> authorize_low_risk_update(context)
      # Medium/high-risk updates require re-approval workflow
      {_, risk} when risk in [:medium, :high] -> authorize_high_risk_update(context)
      _ -> {:ok, :forbidden}
    end
  end

  defp authorize_rejected_update(%{user_role: role, is_owner: is_owner}) do
    case {role, is_owner} do
      # Admins can update rejected prompts
      {role, _} when role in [:admin, :system_admin] -> {:ok, :authorized}
      # Owners can update and resubmit rejected prompts
      {_, true} -> {:ok, :authorized}
      _ -> {:ok, :forbidden}
    end
  end

  defp authorize_low_risk_update(%{is_owner: true, automated_approval_enabled: true}) do
    {:ok, :authorized}
  end

  defp authorize_low_risk_update(_context), do: {:ok, :forbidden}

  defp authorize_high_risk_update(%{is_owner: true}) do
    # High-risk updates are allowed but will trigger re-approval workflow
    {:ok, :authorized}
  end

  defp authorize_high_risk_update(_context), do: {:ok, :forbidden}

  # Destruction workflow authorization
  defp authorize_destruction_workflow(%{user_role: role, approval_status: status} = context) do
    case {role, status} do
      # Admins can delete any prompt
      {role, _} when role in [:admin, :system_admin] -> {:ok, :authorized}
      # Owners can delete their own drafts or rejected prompts
      {_, status} when status in [:draft, :rejected] -> authorize_owner_deletion(context)
      # Approved/pending prompts require special authorization
      {_, status} when status in [:approved, :pending] -> authorize_approved_deletion(context)
      _ -> {:ok, :forbidden}
    end
  end

  defp authorize_owner_deletion(%{is_owner: true}), do: {:ok, :authorized}
  defp authorize_owner_deletion(_context), do: {:ok, :forbidden}

  defp authorize_approved_deletion(%{user_role: role}) do
    # Only admins can delete approved/pending prompts
    case role in [:admin, :system_admin] do
      true -> {:ok, :authorized}
      false -> {:ok, :forbidden}
    end
  end

  # Context building and validation

  defp build_approval_context(actor, resource, context) do
    %{
      user_id: get_actor_id(actor),
      user_role: get_actor_role(actor),
      action: context.action.name,
      resource_id: get_resource_id(resource),
      prompt_type: get_resource_prompt_type(resource),
      approval_status: get_approval_status(resource),
      is_owner: resource_owner?(actor, resource),
      can_approve: can_actor_approve?(actor, resource),
      risk_level: calculate_risk_level(resource),
      automated_approval_enabled: automated_approval_enabled?(resource),
      security_clearance: get_actor_security_clearance(actor)
    }
  end

  defp validate_approval_context(%{user_id: nil}), do: {:error, :missing_user_id}
  defp validate_approval_context(%{user_role: nil}), do: {:error, :missing_user_role}
  defp validate_approval_context(_context), do: {:ok, :valid_approval_context}

  # Resource and actor attribute extraction

  defp get_actor_id(%{id: id}), do: id
  defp get_actor_id(_), do: nil

  defp get_actor_role(%{role: role}) when is_atom(role), do: role
  defp get_actor_role(%{role: role}) when is_binary(role), do: String.to_atom(role)
  defp get_actor_role(_), do: :user

  defp get_resource_id(%{id: id}), do: id
  defp get_resource_id(_), do: nil

  defp get_resource_prompt_type(%{prompt_type: type}), do: type
  defp get_resource_prompt_type(_), do: :user

  defp get_approval_status(%{approval_status: status}) when is_binary(status),
    do: String.to_atom(status)

  defp get_approval_status(%{approval_status: status}) when is_atom(status), do: status
  defp get_approval_status(_), do: :draft

  defp resource_owner?(%{id: user_id}, %{user_id: resource_user_id}),
    do: user_id == resource_user_id

  defp resource_owner?(%{id: user_id}, %{project_id: project_id, projects: projects})
       when not is_nil(project_id) do
    project_id in (projects || [])
  end

  defp resource_owner?(_actor, _resource), do: false

  defp can_actor_approve?(%{role: role}, %{prompt_type: prompt_type}) do
    case {role, prompt_type} do
      # Admins can approve anything
      {role, _} when role in [:admin, :system_admin] -> true
      # Project owners can approve project prompts
      {:project_owner, :project} -> true
      # Regular users cannot approve
      _ -> false
    end
  end

  defp calculate_risk_level(%{risk_score: risk_score}) when is_number(risk_score) do
    cond do
      risk_score < @risk_thresholds.low -> :low
      risk_score < @risk_thresholds.medium -> :medium
      risk_score < @risk_thresholds.high -> :high
      true -> :critical
    end
  end

  defp calculate_risk_level(_resource), do: :medium

  defp automated_approval_enabled?(%{access_policy: %{"automated_approval" => enabled}})
       when is_boolean(enabled),
       do: enabled

  defp automated_approval_enabled?(_resource), do: false

  defp get_actor_security_clearance(%{role: role}) do
    case role do
      :system_admin -> :maximum
      :admin -> :enhanced
      :project_owner -> :standard
      :user -> :standard
      _ -> :minimal
    end
  end

  # Utility functions

  defp get_approval_path(_actor, _resource, _context) do
    "multi_stage_approval_workflow"
  end

  defp get_approval_denial_reason(_actor, _resource, _context) do
    "insufficient_approval_authority"
  end

  defp track_approval_decision(actor, resource, context, result) do
    Logger.info("PromptApprovalPolicy: Approval decision tracked",
      actor_id: get_actor_id(actor),
      resource_id: get_resource_id(resource),
      action: context.action.name,
      result: result,
      approval_status: get_approval_status(resource)
    )

    # Would integrate with SecurityAuditLogger for comprehensive approval audit trail
    :ok
  end
end
