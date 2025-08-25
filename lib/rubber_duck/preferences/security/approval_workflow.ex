defmodule RubberDuck.Preferences.Security.ApprovalWorkflow do
  @moduledoc """
  Approval workflow management for sensitive preference operations.

  Manages approval workflows for preference changes that require authorization,
  including automatic approval processing, notification systems, and workflow
  state management.
  """

  alias RubberDuck.Preferences.Resources.{ApprovalRequest, SecurityPolicy}
  alias RubberDuck.Preferences.Security.{AccessControl, AuditLogger}

  require Logger

  @doc """
  Create an approval request for a preference change.

  ## Examples

      ApprovalWorkflow.request_approval(%{
        requester_id: "user123",
        preference_key: "llm.api_key",
        action: "update",
        current_value: "[REDACTED]",
        new_value: "[REDACTED]",
        justification: "Update API key for new provider integration"
      })
  """
  @spec request_approval(request_params :: map()) ::
          {:ok, ApprovalRequest.t()} | {:error, term()}
  def request_approval(request_params) do
    case ApprovalRequest.create(request_params) do
      {:ok, approval_request} ->
        # Log the approval request creation
        AuditLogger.log_authorization_event(%{
          user_id: approval_request.requester_id,
          action: "approval_requested",
          approval_request_id: approval_request.id,
          preference_key: approval_request.preference_key,
          request_type: approval_request.request_type,
          priority: approval_request.priority
        })

        # Notify appropriate approvers
        notify_approvers(approval_request)

        {:ok, approval_request}

      error ->
        error
    end
  end

  @doc """
  Approve an approval request.
  """
  @spec approve_request(
          approval_request_id :: String.t(),
          approver_id :: String.t(),
          notes :: String.t()
        ) ::
          {:ok, ApprovalRequest.t()} | {:error, term()}
  def approve_request(approval_request_id, approver_id, notes \\ "") do
    case ApprovalRequest.read(approval_request_id) do
      {:ok, [request]} ->
        case can_approve_request?(approver_id, request) do
          true ->
            case ApprovalRequest.approve(request, %{
                   approver_id: approver_id,
                   approval_notes: notes
                 }) do
              {:ok, updated_request} ->
                # Execute the approved action
                execute_approved_action(updated_request)

                # Log approval event
                AuditLogger.log_authorization_event(%{
                  user_id: approver_id,
                  action: "approval_granted",
                  approval_request_id: updated_request.id,
                  preference_key: updated_request.preference_key,
                  original_requester: updated_request.requester_id
                })

                {:ok, updated_request}

              error ->
                error
            end

          false ->
            # Log unauthorized approval attempt
            AuditLogger.log_security_event(%{
              user_id: approver_id,
              action: "unauthorized_approval_attempt",
              approval_request_id: approval_request_id,
              threat_level: "medium",
              details: "User attempted to approve request without proper authorization"
            })

            {:error, "Insufficient permissions to approve this request"}
        end

      {:ok, []} ->
        {:error, "Approval request not found"}

      error ->
        error
    end
  end

  @doc """
  Reject an approval request.
  """
  @spec reject_request(
          approval_request_id :: String.t(),
          approver_id :: String.t(),
          reason :: String.t()
        ) ::
          {:ok, ApprovalRequest.t()} | {:error, term()}
  def reject_request(approval_request_id, approver_id, reason) do
    case ApprovalRequest.read(approval_request_id) do
      {:ok, [request]} ->
        case can_approve_request?(approver_id, request) do
          true ->
            case ApprovalRequest.reject(request, %{
                   approver_id: approver_id,
                   approval_notes: reason
                 }) do
              {:ok, updated_request} ->
                # Log rejection event
                AuditLogger.log_authorization_event(%{
                  user_id: approver_id,
                  action: "approval_rejected",
                  approval_request_id: updated_request.id,
                  preference_key: updated_request.preference_key,
                  original_requester: updated_request.requester_id,
                  reason: reason
                })

                {:ok, updated_request}

              error ->
                error
            end

          false ->
            {:error, "Insufficient permissions to reject this request"}
        end

      {:ok, []} ->
        {:error, "Approval request not found"}

      error ->
        error
    end
  end

  @doc """
  Get pending approval requests that a user can approve.
  """
  @spec get_approvable_requests(approver_id :: String.t()) ::
          {:ok, [ApprovalRequest.t()]} | {:error, term()}
  def get_approvable_requests(approver_id) do
    case ApprovalRequest.pending_requests() do
      {:ok, pending_requests} ->
        approvable = Enum.filter(pending_requests, &can_approve_request?(approver_id, &1))
        {:ok, approvable}

      error ->
        error
    end
  end

  @doc """
  Check if approval is required for a preference operation.
  """
  @spec approval_required?(preference_key :: String.t(), action :: String.t(), context :: map()) ::
          boolean()
  def approval_required?(preference_key, action, context \\ %{}) do
    case get_applicable_policies(preference_key, context) do
      {:ok, policies} ->
        Enum.any?(policies, fn policy ->
          policy.approval_required and policy.active and
            matches_action?(policy, action)
        end)

      {:error, _} ->
        # Default to requiring approval for safety
        true
    end
  end

  @doc """
  Process expired approval requests.

  This function should be called periodically to clean up expired requests.
  """
  @spec process_expired_requests() :: {:ok, %{expired_count: integer()}} | {:error, term()}
  def process_expired_requests do
    case ApprovalRequest.expired_requests() do
      {:ok, expired_requests} ->
        results = Enum.map(expired_requests, &expire_request/1)
        successful = Enum.count(results, &match?({:ok, _}, &1))

        Logger.info("Processed #{successful} expired approval requests")
        {:ok, %{expired_count: successful}}

      error ->
        error
    end
  end

  ## Private Functions

  defp notify_approvers(approval_request) do
    # This would integrate with notification system
    # For now, just log the notification
    Logger.info("Approval request #{approval_request.id} created - notifying approvers")

    # In a full implementation, this would:
    # 1. Determine who can approve based on policies
    # 2. Send notifications via email/Slack/in-app
    # 3. Update notification tracking
  end

  defp can_approve_request?(approver_id, request) do
    # Check if user has approval permissions for this type of request
    case get_approver_user(approver_id) do
      {:ok, approver} ->
        has_approval_role?(approver, request) and
          not_self_approval?(approver_id, request.requester_id)

      {:error, _} ->
        false
    end
  end

  defp get_approver_user(approver_id) do
    # This would fetch the user record to check roles
    # For now, mock the user lookup
    {:ok, %{id: approver_id, role: :admin}}
  end

  defp has_approval_role?(approver, request) do
    case get_applicable_policies(request.preference_key, %{
           resource_type: request.target_resource_type
         }) do
      {:ok, policies} ->
        approval_policies = Enum.filter(policies, & &1.approval_required)

        Enum.any?(approval_policies, fn policy ->
          AccessControl.has_any_role?(approver, policy.approval_roles)
        end)

      {:error, _} ->
        # Default to admin/security_admin for safety
        AccessControl.has_any_role?(approver, [:admin, :security_admin])
    end
  end

  defp not_self_approval?(approver_id, requester_id) do
    approver_id != requester_id
  end

  defp execute_approved_action(approval_request) do
    # This would execute the actual approved action
    # For now, just log that it would be executed
    Logger.info("Executing approved action for request #{approval_request.id}")

    # In a full implementation, this would:
    # 1. Apply the approved preference change
    # 2. Grant the requested delegation
    # 3. Execute the policy override
    # 4. Update relevant resources
  end

  defp get_applicable_policies(preference_key, context) do
    case SecurityPolicy.active_policies() do
      {:ok, policies} ->
        applicable =
          Enum.filter(policies, fn policy ->
            matches_resource_type?(policy, context[:resource_type]) and
              matches_preference_key?(policy, preference_key)
          end)

        {:ok, applicable}

      error ->
        error
    end
  end

  defp matches_resource_type?(policy, resource_type) do
    policy.resource_type == "all" or policy.resource_type == resource_type
  end

  defp matches_preference_key?(policy, preference_key) do
    case policy.preference_pattern do
      nil -> true
      "" -> true
      pattern -> String.contains?(preference_key, pattern)
    end
  end

  defp matches_action?(_policy, _action) do
    # For now, all policies apply to all actions
    # This could be extended to have action-specific policies
    true
  end

  defp expire_request(request) do
    case ApprovalRequest.update(request, %{status: :expired}) do
      {:ok, updated_request} ->
        AuditLogger.log_authorization_event(%{
          user_id: "system",
          action: "approval_expired",
          approval_request_id: updated_request.id,
          preference_key: updated_request.preference_key,
          original_requester: updated_request.requester_id
        })

        {:ok, updated_request}

      error ->
        error
    end
  end
end
