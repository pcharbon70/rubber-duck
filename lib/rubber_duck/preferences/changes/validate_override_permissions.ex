defmodule RubberDuck.Preferences.Changes.ValidateOverridePermissions do
  @moduledoc """
  Ash change module to validate project preference override permissions.

  This change ensures that project overrides are only created when:
  - Project overrides are enabled
  - User has appropriate permissions
  - Category is allowed for overrides
  - Override limits are not exceeded
  """

  use Ash.Resource.Change

  alias RubberDuck.Preferences.OverrideValidator

  @impl true
  def change(changeset, _opts, _context) do
    # Only validate for create and update actions
    case changeset.action_type do
      :create -> validate_create_permissions(changeset)
      :update -> validate_update_permissions(changeset)
      _ -> changeset
    end
  end

  defp validate_create_permissions(changeset) do
    project_id = get_project_id(changeset)
    preference_key = get_preference_key(changeset)
    value = get_value(changeset)

    if project_id && preference_key && value do
      case OverrideValidator.validate_override(project_id, preference_key, value, []) do
        {:ok, :valid} ->
          changeset

        {:error, reason} ->
          Ash.Changeset.add_error(changeset, field: :value, message: reason)
      end
    else
      changeset
    end
  end

  defp validate_update_permissions(changeset) do
    # For updates, we mainly need to validate the new value if it's being changed
    if Map.has_key?(changeset.attributes, :value) do
      validate_create_permissions(changeset)
    else
      changeset
    end
  end

  defp get_project_id(changeset) do
    changeset.attributes[:project_id] || changeset.data[:project_id]
  end

  defp get_preference_key(changeset) do
    changeset.attributes[:preference_key] || changeset.data[:preference_key]
  end

  defp get_value(changeset) do
    changeset.attributes[:value] || changeset.data[:value]
  end
end
