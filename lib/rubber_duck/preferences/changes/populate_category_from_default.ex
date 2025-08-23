defmodule RubberDuck.Preferences.Changes.PopulateCategoryFromDefault do
  @moduledoc """
  Change module to automatically populate category from SystemDefault.

  When creating or updating UserPreference or ProjectPreference records,
  this change automatically populates the category field from the
  corresponding SystemDefault record for denormalized querying.
  """

  use Ash.Resource.Change

  alias RubberDuck.Preferences.Resources.SystemDefault

  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :preference_key) do
      nil ->
        changeset

      preference_key ->
        case get_system_default_category(preference_key) do
          {:ok, category} ->
            Ash.Changeset.change_attribute(changeset, :category, category)

          {:error, _} ->
            handle_missing_system_default(changeset)
        end
    end
  end

  defp handle_missing_system_default(changeset) do
    # If system default not found, keep existing category or set to "custom"
    existing_category = Ash.Changeset.get_attribute(changeset, :category)

    if existing_category do
      changeset
    else
      Ash.Changeset.change_attribute(changeset, :category, "custom")
    end
  end

  defp get_system_default_category(preference_key) do
    case SystemDefault.read(%{preference_key: preference_key}) do
      {:ok, [system_default]} ->
        {:ok, system_default.category}

      {:ok, []} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
