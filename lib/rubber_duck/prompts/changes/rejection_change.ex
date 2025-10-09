defmodule RubberDuck.Prompts.Changes.RejectionChange do
  @moduledoc """
  Change module for prompt rejection workflow.

  Handles the logic for rejecting prompts, setting rejection metadata,
  and triggering post-rejection workflows like notifications and
  security logging.
  """

  use Ash.Resource.Change
  require Logger

  @impl Ash.Resource.Change
  def change(changeset, _opts, context) do
    rejection_reason = Ash.Changeset.get_argument(changeset, :rejection_reason)
    rejector_id = get_rejector_id(context)

    # Update rejection metadata
    enhanced_changeset =
      changeset
      |> Ash.Changeset.change_attribute(:approved_by, rejector_id)
      |> Ash.Changeset.change_attribute(:approved_at, DateTime.utc_now())
      |> Ash.Changeset.change_attribute(:approval_comments, rejection_reason)

    # Log rejection action
    log_rejection_action(changeset, rejector_id, rejection_reason)

    Logger.info("RejectionChange: Prompt rejected",
      prompt_id: Ash.Changeset.get_attribute(changeset, :id),
      rejector_id: rejector_id,
      rejection_reason: rejection_reason
    )

    enhanced_changeset
  end

  @impl Ash.Resource.Change
  def atomic?(_opts), do: false

  # Private functions

  defp get_rejector_id(%{actor: %{id: id}}), do: id
  defp get_rejector_id(_context), do: nil

  defp log_rejection_action(changeset, rejector_id, rejection_reason) do
    prompt_id = Ash.Changeset.get_attribute(changeset, :id)
    prompt_type = Ash.Changeset.get_attribute(changeset, :prompt_type)
    security_level = Ash.Changeset.get_attribute(changeset, :security_level)

    audit_entry = %{
      prompt_id: prompt_id,
      action: "prompt_rejected",
      actor_id: rejector_id,
      actor_type: "user",
      security_context: %{
        prompt_type: prompt_type,
        security_level: security_level,
        approval_workflow: true,
        rejection_reason: rejection_reason,
        action_timestamp: DateTime.utc_now()
      },
      audit_metadata: %{
        changeset_action: changeset.action.name,
        approval_required: Ash.Changeset.get_attribute(changeset, :approval_required),
        risk_score: Ash.Changeset.get_attribute(changeset, :risk_score)
      },
      severity: "warning",
      description: "Prompt rejected due to: #{rejection_reason}"
    }

    # Would integrate with SecurityAuditLogger here
    Logger.warn("RejectionChange: Prompt rejected - audit entry created",
      audit_entry: audit_entry
    )
  end
end
