defmodule RubberDuck.CLI.ProjectCommands do
  @moduledoc """
  CLI commands for project preference management.

  Provides commands for enabling project preferences, setting project overrides,
  viewing diffs, and resetting project configurations.
  """

  require Logger

  alias RubberDuck.Preferences.{BulkOperationsManager, ProjectPreferenceManager}

  @doc """
  Enable project preference overrides for a project.
  """
  def enable_project(opts) do
    project_id = Map.get(opts, :project_id)
    user_id = get_user_id_from_opts(opts)
    reason = Map.get(opts, :reason, "Enabled via CLI")
    categories = Map.get(opts, :categories, [])

    if is_nil(project_id) do
      IO.puts("Error: Project ID required.")
      System.halt(1)
    end

    case ProjectPreferenceManager.enable_project_preferences(project_id, user_id,
           reason: reason,
           enabled_categories: categories
         ) do
      {:ok, _config} ->
        IO.puts("✅ Enabled project preferences for project #{project_id}")

        if not Enum.empty?(categories) do
          IO.puts("  Enabled categories: #{Enum.join(categories, ", ")}")
        end

      {:error, reason} ->
        IO.puts("❌ Failed to enable project preferences: #{reason}")
        System.halt(1)
    end
  end

  @doc """
  Set a project preference override.
  """
  def set_project_preference(opts) do
    project_id = Map.get(opts, :project_id)
    key = Map.get(opts, :key)
    value = Map.get(opts, :value)
    user_id = get_user_id_from_opts(opts)
    reason = Map.get(opts, :reason, "Set via CLI")

    if is_nil(project_id) or is_nil(key) or is_nil(value) do
      IO.puts("Error: Project ID, key, and value are required.")
      System.halt(1)
    end

    case ProjectPreferenceManager.create_project_override(project_id, key, value,
           reason: reason,
           approved_by: user_id
         ) do
      {:ok, _preference} ->
        IO.puts("✅ Set project preference #{key} = #{value} for project #{project_id}")

      {:error, reason} ->
        IO.puts("❌ Failed to set project preference: #{reason}")
        System.halt(1)
    end
  end

  @doc """
  Show differences between user and project preferences.
  """
  def show_project_diff(opts) do
    project_id = Map.get(opts, :project_id)
    user_id = get_user_id_from_opts(opts)
    categories = Map.get(opts, :categories)

    if is_nil(project_id) do
      IO.puts("Error: Project ID required.")
      System.halt(1)
    end

    case ProjectPreferenceManager.get_preference_diff(user_id, project_id, categories) do
      {:ok, diff} ->
        display_preference_diff(diff, project_id)

      {:error, reason} ->
        IO.puts("❌ Failed to get preference diff: #{reason}")
        System.halt(1)
    end
  end

  @doc """
  Reset project preferences to user defaults.
  """
  def reset_project(opts) do
    project_id = Map.get(opts, :project_id)
    user_id = get_user_id_from_opts(opts)
    categories = Map.get(opts, :categories)
    dry_run = Map.get(opts, :dry_run, false)

    if is_nil(project_id) do
      IO.puts("Error: Project ID required.")
      System.halt(1)
    end

    case BulkOperationsManager.reset_projects_to_defaults([project_id], user_id,
           categories: categories,
           dry_run: dry_run
         ) do
      {:ok, results} ->
        if dry_run do
          IO.puts("🔍 Dry run results:")
          IO.puts("  Would remove #{results.total_preferences_to_remove} preferences")
        else
          IO.puts("✅ Reset project #{project_id}")
          IO.puts("  Removed #{results.total_removed} preferences")
        end

      {:error, reason} ->
        IO.puts("❌ Failed to reset project: #{reason}")
        System.halt(1)
    end
  end

  # Private helper functions

  defp get_user_id_from_opts(opts) do
    Map.get(opts, :user_id, get_current_user_id())
  end

  defp get_current_user_id do
    case System.get_env("RUBBER_DUCK_USER_ID") do
      nil ->
        IO.puts(
          "Error: User ID required. Use --user-id or set RUBBER_DUCK_USER_ID environment variable."
        )

        System.halt(1)

      user_id ->
        user_id
    end
  end

  defp display_preference_diff(diff, project_id) do
    IO.puts("\nPreference Differences for Project #{project_id}")
    IO.puts(String.duplicate("=", 60))

    if not Enum.empty?(diff.project_only) do
      IO.puts("\n📊 Project-Only Preferences:")

      Enum.each(diff.project_only, fn {key, value} ->
        IO.puts("  + #{key} = #{value}")
      end)
    end

    if not Enum.empty?(diff.different_values) do
      IO.puts("\n🔄 Different Values:")

      Enum.each(diff.different_values, fn {key, values} ->
        IO.puts("  ~ #{key}")
        IO.puts("    User:    #{values.user}")
        IO.puts("    Project: #{values.project}")
      end)
    end

    if not Enum.empty?(diff.same_values) do
      IO.puts("\n✅ Matching Values:")

      Enum.each(diff.same_values, fn {key, value} ->
        IO.puts("  = #{key} = #{value}")
      end)
    end

    IO.puts("\nSummary:")
    IO.puts("  Project overrides: #{map_size(diff.project_only)}")
    IO.puts("  Different values: #{map_size(diff.different_values)}")
    IO.puts("  Matching values: #{map_size(diff.same_values)}")
  end
end
