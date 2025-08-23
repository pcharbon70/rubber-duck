defmodule RubberDuck.Preferences.ProjectPreferenceManager do
  @moduledoc """
  Project preference management for controlling project-level preference overrides.

  Provides business logic for managing project preference enablement,
  category-specific controls, inheritance visualization, and diff operations.
  Integrates with existing ProjectPreference and ProjectPreferenceEnabled
  resources while providing high-level management functions.
  """

  require Logger

  alias RubberDuck.Preferences.Resources.{
    ProjectPreference,
    ProjectPreferenceEnabled,
    SystemDefault,
    UserPreference
  }

  # alias RubberDuck.Preferences.PreferenceResolver

  @doc """
  Enable project preferences for a project with optional category restrictions.
  """
  @spec enable_project_preferences(
          project_id :: binary(),
          enabled_by_user_id :: binary(),
          opts :: keyword()
        ) :: {:ok, ProjectPreferenceEnabled.t()} | {:error, term()}
  def enable_project_preferences(project_id, enabled_by_user_id, opts \\ []) do
    enabled_categories = Keyword.get(opts, :enabled_categories, [])
    disabled_categories = Keyword.get(opts, :disabled_categories, [])
    reason = Keyword.get(opts, :reason, "Enable project preference overrides")

    attrs = %{
      project_id: project_id,
      enabled: true,
      enabled_categories: enabled_categories,
      disabled_categories: disabled_categories,
      enablement_reason: reason,
      enabled_by: enabled_by_user_id
    }

    case ProjectPreferenceEnabled.create(attrs) do
      {:ok, result} ->
        Logger.info("Enabled project preferences for project #{project_id}")
        {:ok, result}

      error ->
        Logger.warning("Failed to enable project preferences: #{inspect(error)}")
        error
    end
  end

  @doc """
  Disable project preferences for a project.
  """
  @spec disable_project_preferences(project_id :: binary()) :: :ok | {:error, term()}
  def disable_project_preferences(project_id) do
    case ProjectPreferenceEnabled.by_project(project_id) do
      {:ok, [enabled_config]} ->
        case ProjectPreferenceEnabled.update(enabled_config, %{enabled: false}) do
          {:ok, _} ->
            Logger.info("Disabled project preferences for project #{project_id}")
            :ok

          error ->
            Logger.warning("Failed to disable project preferences: #{inspect(error)}")
            error
        end

      {:ok, []} ->
        {:error, "Project preferences not enabled for project"}

      error ->
        error
    end
  end

  @doc """
  Check if project preferences are enabled for a project.
  """
  @spec project_preferences_enabled?(project_id :: binary()) :: boolean()
  def project_preferences_enabled?(project_id) do
    case ProjectPreferenceEnabled.by_project(project_id) do
      {:ok, [config]} -> config.enabled
      _ -> false
    end
  end

  @doc """
  Get project preference override status for all categories.
  """
  @spec get_override_status(project_id :: binary()) :: {:ok, map()} | {:error, term()}
  def get_override_status(project_id) do
    with {:ok, enabled_config} <- get_project_enabled_config(project_id),
         {:ok, current_overrides} <- get_current_project_overrides(project_id) do
      override_counts = count_overrides_by_category(current_overrides)

      status = %{
        enabled: enabled_config.enabled,
        enabled_categories: enabled_config.enabled_categories,
        disabled_categories: enabled_config.disabled_categories,
        override_counts: override_counts,
        total_overrides: length(current_overrides),
        last_override_at: enabled_config.last_override_at
      }

      {:ok, status}
    else
      error -> error
    end
  end

  @doc """
  Get preference diff between user and project settings.
  """
  @spec get_preference_diff(
          user_id :: binary(),
          project_id :: binary(),
          categories :: list(String.t()) | nil
        ) :: {:ok, map()} | {:error, term()}
  def get_preference_diff(user_id, project_id, categories \\ nil) do
    with {:ok, user_prefs} <- get_user_preferences(user_id, categories),
         {:ok, project_prefs} <- get_project_preferences(project_id, categories) do
      diff = calculate_preference_diff(user_prefs, project_prefs)
      {:ok, diff}
    else
      error -> error
    end
  end

  @doc """
  Create project preference override with validation.
  """
  @spec create_project_override(
          project_id :: binary(),
          preference_key :: String.t(),
          value :: String.t(),
          opts :: keyword()
        ) :: {:ok, ProjectPreference.t()} | {:error, term()}
  def create_project_override(project_id, preference_key, value, opts \\ []) do
    override_reason = Keyword.get(opts, :reason, "Project-specific override")
    approved_by = Keyword.get(opts, :approved_by)
    temporary = Keyword.get(opts, :temporary, false)
    priority = Keyword.get(opts, :priority, 5)

    with :ok <- validate_project_override_allowed(project_id, preference_key),
         {:ok, system_default} <- get_system_default(preference_key),
         :ok <- validate_preference_value(system_default, value) do
      attrs = %{
        project_id: project_id,
        preference_key: preference_key,
        value: value,
        override_reason: override_reason,
        approved_by: approved_by,
        temporary: temporary,
        priority: priority,
        category: system_default.category
      }

      case ProjectPreference.create(attrs) do
        {:ok, result} ->
          update_last_override_timestamp(project_id)
          Logger.info("Created project override for #{preference_key} in project #{project_id}")
          {:ok, result}

        error ->
          Logger.warning("Failed to create project override: #{inspect(error)}")
          error
      end
    end
  end

  @doc """
  Update existing project preference override.
  """
  @spec update_project_override(
          project_preference_id :: binary(),
          new_value :: String.t(),
          opts :: keyword()
        ) :: {:ok, ProjectPreference.t()} | {:error, term()}
  def update_project_override(project_preference_id, new_value, opts \\ []) do
    reason = Keyword.get(opts, :reason, "Update project override")

    # Placeholder implementation for update_project_override
    with {:ok, project_pref} <- {:ok, %{preference_key: "test", project_id: "test"}},
         {:ok, system_default} <- get_system_default(project_pref.preference_key),
         :ok <- validate_preference_value(system_default, new_value) do
      attrs = %{
        value: new_value,
        override_reason: reason
      }

      case ProjectPreference.update(project_pref, attrs) do
        {:ok, result} ->
          update_last_override_timestamp(project_pref.project_id)
          Logger.info("Updated project override for #{project_pref.preference_key}")
          {:ok, result}

        error ->
          Logger.warning("Failed to update project override: #{inspect(error)}")
          error
      end
    end
  end

  @doc """
  Remove project preference override (revert to user preference).
  """
  @spec remove_project_override(project_preference_id :: binary()) :: :ok | {:error, term()}
  def remove_project_override(project_preference_id) do
    # Placeholder for project preference lookup
    case {:ok, %{preference_key: "test", project_id: "test"}} do
      {:ok, project_pref} ->
        case ProjectPreference.destroy(project_pref) do
          :ok ->
            Logger.info("Removed project override for #{project_pref.preference_key}")
            :ok

          error ->
            Logger.warning("Failed to remove project override: #{inspect(error)}")
            error
        end

      error ->
        error
    end
  end

  @doc """
  Get inheritance visualization data for a project.
  """
  @spec get_inheritance_visualization(project_id :: binary()) :: {:ok, map()} | {:error, term()}
  def get_inheritance_visualization(project_id) do
    with {:ok, project_prefs} <- get_all_project_preferences(project_id),
         {:ok, system_defaults} <- get_all_system_defaults() do
      visualization = build_inheritance_tree(system_defaults, project_prefs)
      {:ok, visualization}
    else
      error -> error
    end
  end

  @doc """
  Get project preference statistics and analytics.
  """
  @spec get_project_statistics(project_id :: binary()) :: {:ok, map()} | {:error, term()}
  def get_project_statistics(project_id) do
    with {:ok, project_prefs} <- get_all_project_preferences(project_id),
         {:ok, enabled_config} <- get_project_enabled_config(project_id) do
      stats = %{
        total_preferences_available: count_available_preferences(),
        total_overrides: length(project_prefs),
        override_percentage: calculate_override_percentage(project_prefs),
        overrides_by_category: count_overrides_by_category(project_prefs),
        most_common_overrides: find_most_common_overrides(project_prefs),
        last_activity: enabled_config.last_override_at,
        temporary_overrides: count_temporary_overrides(project_prefs)
      }

      {:ok, stats}
    else
      error -> error
    end
  end

  # Private helper functions

  defp validate_project_override_allowed(project_id, preference_key) do
    case get_project_enabled_config(project_id) do
      {:ok, config} ->
        if config.enabled do
          validate_category_allowed(preference_key, config)
        else
          {:error, "Project preferences not enabled for this project"}
        end

      error ->
        error
    end
  end

  defp validate_category_allowed(preference_key, config) do
    case get_system_default(preference_key) do
      {:ok, system_default} ->
        category = system_default.category

        cond do
          category in config.disabled_categories ->
            {:error, "Category #{category} is disabled for project overrides"}

          not Enum.empty?(config.enabled_categories) and category not in config.enabled_categories ->
            {:error, "Category #{category} is not enabled for project overrides"}

          true ->
            :ok
        end

      error ->
        error
    end
  end

  defp get_project_enabled_config(project_id) do
    case ProjectPreferenceEnabled.by_project(project_id) do
      {:ok, [config]} -> {:ok, config}
      {:ok, []} -> {:error, "Project preferences not configured"}
      error -> error
    end
  end

  defp get_current_project_overrides(project_id) do
    case ProjectPreference.by_project(project_id) do
      {:ok, preferences} -> {:ok, preferences}
      error -> error
    end
  end

  defp get_user_preferences(user_id, categories) do
    case UserPreference.by_user(user_id) do
      {:ok, preferences} ->
        filtered =
          if categories, do: filter_by_categories(preferences, categories), else: preferences

        {:ok, filtered}

      error ->
        error
    end
  end

  defp get_project_preferences(project_id, categories) do
    case ProjectPreference.by_project(project_id) do
      {:ok, preferences} ->
        filtered =
          if categories, do: filter_by_categories(preferences, categories), else: preferences

        {:ok, filtered}

      error ->
        error
    end
  end

  defp get_all_project_preferences(project_id) do
    ProjectPreference.by_project(project_id)
  end

  defp get_all_system_defaults do
    SystemDefault.read()
  end

  defp get_system_default(_preference_key) do
    # Placeholder for system default lookup
    # This would integrate with actual SystemDefault resource queries
    {:ok, %{data_type: :string, category: "general", constraints: nil}}
  end

  defp validate_preference_value(system_default, value) do
    case system_default.data_type do
      :boolean -> validate_boolean_preference(value)
      :integer -> validate_integer_preference(value)
      :float -> validate_float_preference(value)
      _ -> :ok
    end
  end

  defp validate_boolean_preference(value) do
    if value in ["true", "false"], do: :ok, else: {:error, "Invalid boolean value"}
  end

  defp validate_integer_preference(value) do
    case Integer.parse(value) do
      {_int, ""} -> :ok
      _ -> {:error, "Invalid integer value"}
    end
  end

  defp validate_float_preference(value) do
    case Float.parse(value) do
      {_float, ""} -> :ok
      _ -> {:error, "Invalid float value"}
    end
  end

  defp calculate_preference_diff(user_prefs, project_prefs) do
    project_pref_map = Map.new(project_prefs, &{&1.preference_key, &1.value})
    user_pref_map = Map.new(user_prefs, &{&1.preference_key, &1.value})

    %{
      project_only: calculate_project_only_prefs(project_pref_map, user_pref_map),
      user_only: calculate_user_only_prefs(user_pref_map, project_pref_map),
      different_values: calculate_different_values(user_pref_map, project_pref_map),
      same_values: calculate_same_values(user_pref_map, project_pref_map)
    }
  end

  defp calculate_project_only_prefs(project_map, user_map) do
    Map.drop(project_map, Map.keys(user_map))
  end

  defp calculate_user_only_prefs(user_map, project_map) do
    Map.drop(user_map, Map.keys(project_map))
  end

  defp calculate_different_values(user_map, project_map) do
    Enum.reduce(project_map, %{}, fn {key, project_value}, acc ->
      case Map.get(user_map, key) do
        ^project_value ->
          acc

        user_value when not is_nil(user_value) ->
          Map.put(acc, key, %{user: user_value, project: project_value})

        _ ->
          acc
      end
    end)
  end

  defp calculate_same_values(user_map, project_map) do
    Enum.reduce(project_map, %{}, fn {key, project_value}, acc ->
      case Map.get(user_map, key) do
        ^project_value -> Map.put(acc, key, project_value)
        _ -> acc
      end
    end)
  end

  defp count_overrides_by_category(project_prefs) do
    Enum.group_by(project_prefs, & &1.category)
    |> Map.new(fn {category, prefs} -> {category, length(prefs)} end)
  end

  defp filter_by_categories(preferences, categories) do
    Enum.filter(preferences, &(&1.category in categories))
  end

  defp build_inheritance_tree(system_defaults, project_prefs) do
    project_pref_keys = MapSet.new(project_prefs, & &1.preference_key)

    Enum.group_by(system_defaults, & &1.category)
    |> Map.new(fn {category, defaults} ->
      category_info = %{
        total_preferences: length(defaults),
        overridden_count: count_overridden_in_category(defaults, project_pref_keys),
        preferences: build_preference_inheritance_info(defaults, project_prefs)
      }

      {category, category_info}
    end)
  end

  defp count_overridden_in_category(defaults, project_pref_keys) do
    defaults
    |> Enum.count(&MapSet.member?(project_pref_keys, &1.preference_key))
  end

  defp build_preference_inheritance_info(defaults, project_prefs) do
    project_pref_map = Map.new(project_prefs, &{&1.preference_key, &1})

    Enum.map(defaults, fn default ->
      case Map.get(project_pref_map, default.preference_key) do
        nil ->
          %{
            preference_key: default.preference_key,
            description: default.description,
            inheritance_source: :user,
            overridden: false,
            system_default: default.default_value
          }

        project_pref ->
          %{
            preference_key: default.preference_key,
            description: default.description,
            inheritance_source: :project,
            overridden: true,
            system_default: default.default_value,
            project_value: project_pref.value,
            override_reason: project_pref.override_reason,
            temporary: project_pref.temporary
          }
      end
    end)
  end

  defp update_last_override_timestamp(project_id) do
    case get_project_enabled_config(project_id) do
      {:ok, config} ->
        ProjectPreferenceEnabled.update(config, %{last_override_at: DateTime.utc_now()})

      error ->
        Logger.warning("Failed to update last override timestamp: #{inspect(error)}")
        error
    end
  end

  defp count_available_preferences do
    case SystemDefault.read() do
      {:ok, defaults} -> length(defaults)
      _ -> 0
    end
  end

  defp calculate_override_percentage(project_prefs) do
    total_available = count_available_preferences()

    if total_available > 0 do
      (length(project_prefs) / total_available * 100.0) |> Float.round(2)
    else
      0.0
    end
  end

  defp find_most_common_overrides(project_prefs) do
    project_prefs
    |> Enum.group_by(& &1.preference_key)
    |> Enum.map(fn {key, prefs} -> {key, length(prefs)} end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.take(10)
  end

  defp count_temporary_overrides(project_prefs) do
    Enum.count(project_prefs, & &1.temporary)
  end
end
