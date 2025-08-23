defmodule RubberDuck.Preferences.Changes.InvalidatePreferenceCache do
  @moduledoc """
  Ash change module to invalidate preference cache when preferences are modified.

  This change is automatically applied to preference resources to ensure
  cache consistency when preference values are updated.
  """

  use Ash.Resource.Change

  alias RubberDuck.Preferences.{PreferenceResolver, PreferenceWatcher}

  @impl true
  def change(changeset, _opts, _context) do
    # Add after_action hook to invalidate cache
    Ash.Changeset.after_action(changeset, &invalidate_related_cache/2)
  end

  defp invalidate_related_cache(changeset, result) do
    user_id = get_user_id(changeset, result)
    project_id = get_project_id(changeset, result)
    preference_key = get_preference_key(changeset, result)

    # Invalidate cache for this specific preference
    if user_id && preference_key do
      PreferenceResolver.invalidate_cache(user_id, preference_key, project_id)
    end

    # Notify watchers of the change
    old_value = get_old_value(changeset)
    new_value = get_new_value(changeset, result)

    PreferenceWatcher.notify_preference_change(
      user_id,
      project_id,
      preference_key,
      old_value,
      new_value
    )

    {:ok, result}
  end

  defp get_user_id(changeset, result) do
    # Try to get user_id from the changeset or result
    changeset.attributes[:user_id] ||
      Map.get(result, :user_id) ||
      changeset.data[:user_id]
  end

  defp get_project_id(changeset, result) do
    # Try to get project_id from the changeset or result
    changeset.attributes[:project_id] ||
      Map.get(result, :project_id) ||
      changeset.data[:project_id]
  end

  defp get_preference_key(changeset, result) do
    # Try to get preference_key from the changeset or result
    changeset.attributes[:preference_key] ||
      Map.get(result, :preference_key) ||
      changeset.data[:preference_key]
  end

  defp get_old_value(changeset) do
    # Get the old value from the changeset data
    case changeset.data do
      %{value: old_value} -> old_value
      _ -> nil
    end
  end

  defp get_new_value(changeset, result) do
    # Get the new value from changeset attributes or result
    changeset.attributes[:value] ||
      Map.get(result, :value)
  end
end
