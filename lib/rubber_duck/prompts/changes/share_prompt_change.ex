defmodule RubberDuck.Prompts.Changes.SharePromptChange do
  @moduledoc """
  Change module for sharing prompts with other users.

  Handles the logic for setting up sharing permissions, validating
  sharing constraints, and updating the access policy for collaborative
  prompt management.
  """

  use Ash.Resource.Change
  require Logger

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    shared_with_user_id = Ash.Changeset.get_argument(changeset, :shared_with_user_id)
    permissions = Ash.Changeset.get_argument(changeset, :permissions) || ["read"]
    expires_at = Ash.Changeset.get_argument(changeset, :expires_at)

    current_access_policy = Ash.Changeset.get_attribute(changeset, :access_policy) || %{}

    case update_sharing_permissions(
           current_access_policy,
           shared_with_user_id,
           permissions,
           expires_at
         ) do
      {:ok, updated_access_policy} ->
        Logger.info("SharePromptChange: Sharing permissions updated",
          shared_with_user_id: shared_with_user_id,
          permissions: permissions,
          expires_at: expires_at
        )

        Ash.Changeset.change_attribute(changeset, :access_policy, updated_access_policy)

      {:error, reason} ->
        Logger.error("SharePromptChange: Failed to update sharing permissions", error: reason)

        Ash.Changeset.add_error(changeset,
          field: :access_policy,
          message: "Sharing update failed: #{reason}"
        )
    end
  end

  @impl Ash.Resource.Change
  def atomic?(_opts), do: false

  # Private functions

  defp update_sharing_permissions(current_policy, user_id, permissions, expires_at) do
    # Initialize sharing permissions if not exists
    sharing_permissions = Map.get(current_policy, "sharing_permissions", %{})
    sharing_expiration = Map.get(current_policy, "sharing_expiration", %{})

    # Validate permissions
    case validate_sharing_permissions(permissions) do
      :ok ->
        # Update sharing permissions for the user
        updated_sharing_permissions = Map.put(sharing_permissions, user_id, permissions)

        # Update expiration if provided
        updated_sharing_expiration =
          if expires_at do
            Map.put(sharing_expiration, user_id, DateTime.to_iso8601(expires_at))
          else
            sharing_expiration
          end

        # Set collaboration level based on sharing
        collaboration_level = determine_collaboration_level(updated_sharing_permissions)

        updated_policy =
          current_policy
          |> Map.put("sharing_permissions", updated_sharing_permissions)
          |> Map.put("sharing_expiration", updated_sharing_expiration)
          |> Map.put("collaboration_level", collaboration_level)
          |> Map.put("last_shared_at", DateTime.to_iso8601(DateTime.utc_now()))

        {:ok, updated_policy}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_sharing_permissions(permissions) when is_list(permissions) do
    valid_permissions = ["read", "edit", "share", "admin"]

    case Enum.all?(permissions, fn perm -> perm in valid_permissions end) do
      true ->
        :ok

      false ->
        {:error, "Invalid permissions. Must be one of: #{Enum.join(valid_permissions, ", ")}"}
    end
  end

  defp validate_sharing_permissions(_permissions) do
    {:error, "Permissions must be a list of strings"}
  end

  defp determine_collaboration_level(sharing_permissions)
       when map_size(sharing_permissions) == 0 do
    "private"
  end

  defp determine_collaboration_level(sharing_permissions)
       when map_size(sharing_permissions) <= 5 do
    # Small sharing group - team collaboration
    "team"
  end

  defp determine_collaboration_level(_sharing_permissions) do
    # Large sharing group - restricted collaboration
    "restricted"
  end
end
