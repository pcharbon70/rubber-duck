defmodule RubberDuck.Preferences.OverrideManager do
  @moduledoc """
  Project preference override management with validation and analytics.

  Handles enabling/disabling project overrides, managing partial overrides,
  and providing analytics on override usage patterns.
  """

  require Logger

  alias RubberDuck.Preferences.{OverrideValidator, PreferenceWatcher}

  alias RubberDuck.Preferences.Resources.{
    ProjectPreference,
    ProjectPreferenceEnabled,
    SystemDefault
  }

  @doc """
  Enable project preference overrides for specified categories.
  """
  @spec enable_project_overrides(project_id :: binary(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def enable_project_overrides(project_id, opts \\ []) do
    enabled_categories = Keyword.get(opts, :categories, [])
    enablement_reason = Keyword.get(opts, :reason, "Project customization requested")
    enabled_by = Keyword.get(opts, :enabled_by)
    max_overrides = Keyword.get(opts, :max_overrides)

    if is_nil(enabled_by) do
      {:error, "enabled_by user ID is required"}
    else
      case ProjectPreferenceEnabled.enable_overrides(%{
             project_id: project_id,
             enabled_categories: enabled_categories,
             enablement_reason: enablement_reason,
             enabled_by: enabled_by,
             max_overrides: max_overrides
           }) do
        {:ok, _enablement} ->
          PreferenceWatcher.notify_project_overrides_toggled(project_id, true)

          Logger.info("Enabled project overrides for project #{project_id} by user #{enabled_by}")

          {:ok,
           %{
             project_id: project_id,
             enabled: true,
             enabled_categories: enabled_categories,
             max_overrides: max_overrides,
             enabled_at: DateTime.utc_now()
           }}

        error ->
          error
      end
    end
  end

  @doc """
  Disable project preference overrides.
  """
  @spec disable_project_overrides(project_id :: binary(), disable_reason :: String.t()) ::
          {:ok, map()} | {:error, term()}
  def disable_project_overrides(project_id, disable_reason) do
    case get_project_enablement(project_id) do
      {:ok, enablement} ->
        case ProjectPreferenceEnabled.update(enablement, %{
               enabled: false,
               disable_reason: disable_reason
             }) do
          {:ok, _updated} ->
            PreferenceWatcher.notify_project_overrides_toggled(project_id, false)

            Logger.info("Disabled project overrides for project #{project_id}")

            {:ok,
             %{
               project_id: project_id,
               enabled: false,
               disabled_at: DateTime.utc_now(),
               disable_reason: disable_reason
             }}

          error ->
            error
        end

      error ->
        error
    end
  end

  @doc """
  Create a project preference override with validation.
  """
  @spec create_override(
          project_id :: binary(),
          preference_key :: String.t(),
          value :: any(),
          opts :: keyword()
        ) ::
          {:ok, map()} | {:error, term()}
  def create_override(project_id, preference_key, value, opts \\ []) do
    override_reason = Keyword.get(opts, :reason, "Project-specific configuration")
    approved_by = Keyword.get(opts, :approved_by)
    temporary = Keyword.get(opts, :temporary, false)
    effective_until = Keyword.get(opts, :effective_until)

    with {:ok, :enabled} <- check_overrides_enabled(project_id),
         {:ok, :valid} <-
           OverrideValidator.validate_override(project_id, preference_key, value, opts),
         {:ok, :authorized} <- check_override_permission(project_id, preference_key, approved_by) do
      json_value = Jason.encode!(value)

      case ProjectPreference.create_override(%{
             project_id: project_id,
             preference_key: preference_key,
             value: json_value,
             override_reason: override_reason,
             approved_by: approved_by,
             temporary: temporary,
             effective_until: effective_until
           }) do
        {:ok, preference} ->
          # Update activity timestamp
          update_override_activity(project_id)

          # Notify watchers
          PreferenceWatcher.notify_preference_change(nil, project_id, preference_key, nil, value)

          # Record analytics
          record_override_creation(project_id, preference_key, value)

          Logger.info("Created project override: #{preference_key} for project #{project_id}")

          {:ok,
           %{
             preference_id: preference.id,
             project_id: project_id,
             preference_key: preference_key,
             value: value,
             temporary: temporary,
             approved_by: approved_by,
             created_at: preference.inserted_at
           }}

        error ->
          error
      end
    else
      error -> error
    end
  end

  @doc """
  Remove a project preference override.
  """
  @spec remove_override(project_id :: binary(), preference_key :: String.t()) ::
          {:ok, map()} | {:error, term()}
  def remove_override(project_id, preference_key) do
    case get_project_preference(project_id, preference_key) do
      {:ok, preference} ->
        case ProjectPreference.destroy(preference) do
          :ok ->
            PreferenceWatcher.notify_preference_change(
              nil,
              project_id,
              preference_key,
              preference.value,
              nil
            )

            Logger.info("Removed project override: #{preference_key} for project #{project_id}")

            {:ok,
             %{
               project_id: project_id,
               preference_key: preference_key,
               removed_at: DateTime.utc_now()
             }}

          error ->
            error
        end

      error ->
        error
    end
  end

  @doc """
  Get override statistics for a project.
  """
  @spec get_override_statistics(project_id :: binary()) :: map()
  def get_override_statistics(project_id) do
    case ProjectPreference.by_project(project_id) do
      {:ok, preferences} ->
        active_count = Enum.count(preferences, & &1.active)
        temporary_count = Enum.count(preferences, & &1.temporary)

        categories =
          preferences
          |> Enum.group_by(& &1.category)
          |> Enum.map(fn {category, prefs} -> {category, length(prefs)} end)
          |> Enum.into(%{})

        %{
          project_id: project_id,
          total_overrides: length(preferences),
          active_overrides: active_count,
          temporary_overrides: temporary_count,
          overrides_by_category: categories,
          last_modified: get_last_override_time(preferences),
          generated_at: DateTime.utc_now()
        }

      {:error, _} ->
        %{
          project_id: project_id,
          total_overrides: 0,
          active_overrides: 0,
          temporary_overrides: 0,
          overrides_by_category: %{},
          last_modified: nil,
          generated_at: DateTime.utc_now()
        }
    end
  end

  @doc """
  Analyze override patterns across all projects for optimization insights.
  """
  @spec analyze_override_patterns() :: map()
  def analyze_override_patterns do
    case ProjectPreference.read() do
      {:ok, all_preferences} ->
        total_count = length(all_preferences)

        by_key =
          all_preferences
          |> Enum.group_by(& &1.preference_key)
          |> Enum.map(fn {key, prefs} -> {key, length(prefs)} end)
          |> Enum.sort_by(fn {_key, count} -> count end, :desc)

        by_category =
          all_preferences
          |> Enum.group_by(& &1.category)
          |> Enum.map(fn {category, prefs} -> {category, length(prefs)} end)
          |> Enum.into(%{})

        %{
          total_overrides: total_count,
          most_overridden_preferences: Enum.take(by_key, 10),
          overrides_by_category: by_category,
          temporary_override_percentage: calculate_temporary_percentage(all_preferences),
          average_overrides_per_project: calculate_average_per_project(all_preferences),
          generated_at: DateTime.utc_now()
        }

      {:error, _} ->
        %{error: "Unable to analyze override patterns", generated_at: DateTime.utc_now()}
    end
  end

  # Private helper functions

  defp check_overrides_enabled(project_id) do
    case ProjectPreferenceEnabled.by_project(project_id) do
      {:ok, [%{enabled: true}]} -> {:ok, :enabled}
      {:ok, [%{enabled: false}]} -> {:error, "Project overrides are disabled"}
      {:ok, []} -> {:error, "Project overrides not configured"}
      {:error, _} -> {:error, "Unable to check override status"}
    end
  end

  defp check_override_permission(project_id, preference_key, _approved_by) do
    with {:ok, enablement} <- get_project_enablement(project_id),
         {:ok, category} <- get_preference_category(preference_key) do
      if category_override_allowed?(enablement, category) do
        {:ok, :authorized}
      else
        {:error, "Category '#{category}' not enabled for overrides"}
      end
    else
      {:error, _} -> {:error, "Invalid preference key or project configuration"}
      error -> error
    end
  end

  defp category_override_allowed?(enablement, category) do
    cond do
      # If enabled_categories is empty, all categories are allowed
      enablement.enabled_categories == [] -> true
      # Check if category is explicitly enabled
      category in enablement.enabled_categories -> true
      # Check if category is explicitly disabled
      category in enablement.disabled_categories -> false
      # Default to not allowed
      true -> false
    end
  end

  defp get_project_enablement(project_id) do
    case ProjectPreferenceEnabled.by_project(project_id) do
      {:ok, [enablement]} -> {:ok, enablement}
      {:ok, []} -> {:error, "Project overrides not configured"}
      error -> error
    end
  end

  defp get_project_preference(project_id, preference_key) do
    case ProjectPreference.by_project(project_id) do
      {:ok, preferences} ->
        case Enum.find(preferences, &(&1.preference_key == preference_key)) do
          %{} = pref -> {:ok, pref}
          nil -> {:error, :not_found}
        end

      error ->
        error
    end
  end

  defp get_preference_category(preference_key) do
    case SystemDefault.read() do
      {:ok, defaults} ->
        case Enum.find(defaults, &(&1.preference_key == preference_key)) do
          %{category: category} -> {:ok, category}
          nil -> {:error, :not_found}
        end

      error ->
        error
    end
  end

  defp update_override_activity(project_id) do
    case get_project_enablement(project_id) do
      {:ok, enablement} ->
        ProjectPreferenceEnabled.update(enablement, %{
          last_override_at: DateTime.utc_now()
        })

      _ ->
        :ok
    end
  end

  defp record_override_creation(project_id, preference_key, value) do
    :telemetry.execute(
      [:rubber_duck, :preferences, :override_created],
      %{count: 1},
      %{
        project_id: project_id,
        preference_key: preference_key,
        value_type: get_value_type(value)
      }
    )
  end

  defp get_value_type(value) when is_binary(value), do: :string
  defp get_value_type(value) when is_integer(value), do: :integer
  defp get_value_type(value) when is_float(value), do: :float
  defp get_value_type(value) when is_boolean(value), do: :boolean
  defp get_value_type(value) when is_map(value), do: :map
  defp get_value_type(value) when is_list(value), do: :list
  defp get_value_type(_), do: :unknown

  defp get_last_override_time(preferences) do
    preferences
    |> Enum.map(& &1.updated_at)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp calculate_temporary_percentage(preferences) do
    total = length(preferences)
    temporary = Enum.count(preferences, & &1.temporary)

    if total > 0 do
      temporary / total * 100
    else
      0.0
    end
  end

  defp calculate_average_per_project(preferences) do
    project_counts =
      preferences
      |> Enum.group_by(& &1.project_id)
      |> Enum.map(fn {_project_id, prefs} -> length(prefs) end)

    if length(project_counts) > 0 do
      Enum.sum(project_counts) / length(project_counts)
    else
      0.0
    end
  end
end
