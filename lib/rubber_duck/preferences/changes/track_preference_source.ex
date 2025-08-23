defmodule RubberDuck.Preferences.Changes.TrackPreferenceSource do
  @moduledoc """
  Ash change module to track preference source and inheritance information.

  This change automatically records where preference values come from
  in the resolution hierarchy for debugging and auditing purposes.
  """

  use Ash.Resource.Change

  alias RubberDuck.Preferences.InheritanceTracker

  @impl true
  def change(changeset, _opts, _context) do
    # Add after_action hook to track the preference source
    Ash.Changeset.after_action(changeset, &track_preference_resolution/2)
  end

  defp track_preference_resolution(changeset, result) do
    user_id = get_user_id(changeset, result)
    project_id = get_project_id(changeset, result)
    preference_key = get_preference_key(changeset, result)

    if user_id && preference_key do
      source_type = determine_source_type(changeset, result)
      InheritanceTracker.record_resolution(user_id, preference_key, project_id, source_type)
    end

    {:ok, result}
  end

  defp get_user_id(changeset, result) do
    changeset.attributes[:user_id] ||
      Map.get(result, :user_id) ||
      changeset.data[:user_id]
  end

  defp get_project_id(changeset, result) do
    changeset.attributes[:project_id] ||
      Map.get(result, :project_id) ||
      changeset.data[:project_id]
  end

  defp get_preference_key(changeset, result) do
    changeset.attributes[:preference_key] ||
      Map.get(result, :preference_key) ||
      changeset.data[:preference_key]
  end

  defp determine_source_type(changeset, result) do
    cond do
      has_project_id?(changeset, result) -> :project_preference
      has_user_id?(changeset, result) -> :user_preference
      true -> :system_default
    end
  end

  defp has_project_id?(changeset, result) do
    not is_nil(get_project_id(changeset, result))
  end

  defp has_user_id?(changeset, result) do
    not is_nil(get_user_id(changeset, result))
  end
end
