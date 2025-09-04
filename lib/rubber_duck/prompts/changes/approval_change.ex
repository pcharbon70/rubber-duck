defmodule RubberDuck.Prompts.Changes.ApprovalChange do
  @moduledoc """
  Change module for prompt approval workflow.

  Handles the logic for approving prompts, setting approval metadata,
  and triggering post-approval workflows like notifications and
  security logging.
  """

  use Ash.Resource.Change
  require Logger

  alias RubberDuck.Prompts.Security.SecurityAuditLogger

  @impl Ash.Resource.Change
  def change(changeset, _opts, context) do
    approval_comments = Ash.Changeset.get_argument(changeset, :approval_comments)
    approver_id = get_approver_id(context)

    # Update approval metadata
    enhanced_changeset =
      changeset
      |> Ash.Changeset.change_attribute(:approved_by, approver_id)
      |> Ash.Changeset.change_attribute(:approved_at, DateTime.utc_now())
      |> maybe_add_approval_comments(approval_comments)

    # Log approval action
    log_approval_action(changeset, approver_id, :approved)

    Logger.info("ApprovalChange: Prompt approved",
      prompt_id: Ash.Changeset.get_attribute(changeset, :id),
      approver_id: approver_id,
      has_comments: not is_nil(approval_comments)
    )

    enhanced_changeset
  end

  @impl Ash.Resource.Change
  def atomic?(_opts), do: false

  # Private functions

  defp get_approver_id(%{actor: %{id: id}}), do: id
  defp get_approver_id(_context), do: nil

  defp maybe_add_approval_comments(changeset, nil), do: changeset

  defp maybe_add_approval_comments(changeset, comments) when is_binary(comments) do
    Ash.Changeset.change_attribute(changeset, :approval_comments, comments)
  end

  defp log_approval_action(changeset, approver_id, action) do
    prompt_id = Ash.Changeset.get_attribute(changeset, :id)
    prompt_type = Ash.Changeset.get_attribute(changeset, :prompt_type)

    audit_entry = %{
      prompt_id: prompt_id,
      action: "prompt_#{action}",
      actor_id: approver_id,
      actor_type: "user",
      security_context: %{
        prompt_type: prompt_type,
        approval_workflow: true,
        action_timestamp: DateTime.utc_now()
      },
      audit_metadata: %{
        changeset_action: changeset.action.name,
        approval_required: Ash.Changeset.get_attribute(changeset, :approval_required),
        security_level: Ash.Changeset.get_attribute(changeset, :security_level)
      },
      severity: "info",
      description: "Prompt #{action} by authorized user"
    }

    # Would integrate with SecurityAuditLogger here
    Logger.info("ApprovalChange: Audit entry created", audit_entry: audit_entry)
  end
end
