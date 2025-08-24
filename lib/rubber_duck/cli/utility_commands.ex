defmodule RubberDuck.CLI.UtilityCommands do
  @moduledoc """
  CLI utility commands for configuration management.

  Provides commands for validation, migration, backup, and restore operations
  with comprehensive error handling and progress reporting.
  """

  require Logger

  alias RubberDuck.Agents.PreferenceMigrationAgent
  alias RubberDuck.Preferences.ValidationInterfaceManager

  @doc """
  Validate current configuration.
  """
  def validate_config(opts) do
    user_id = get_user_id_from_opts(opts)
    project_id = Map.get(opts, :project_id)
    category = Map.get(opts, :category)
    verbose = Map.get(opts, :verbose, false)

    IO.puts("🔍 Validating configuration...")

    case get_current_preferences(user_id, project_id, category) do
      {:ok, preferences} -> validate_preferences(preferences, verbose)
      {:error, reason} -> handle_preference_fetch_error(reason)
    end
  end

  defp validate_preferences(preferences, verbose) do
    case ValidationInterfaceManager.validate_preference_changes(preferences) do
      {:ok, validation_result} -> handle_validation_result(validation_result, verbose)
      {:error, reason} -> handle_validation_error(reason)
    end
  end

  defp handle_validation_result(validation_result, verbose) do
    display_validation_results(validation_result, verbose)
    exit_code = if validation_result.valid, do: 0, else: 1
    System.halt(exit_code)
  end

  defp handle_validation_error(reason) do
    IO.puts("❌ Validation failed: #{reason}")
    System.halt(1)
  end

  defp handle_preference_fetch_error(reason) do
    IO.puts("❌ Failed to get preferences: #{reason}")
    System.halt(1)
  end

  defp handle_migration_success(result, dry_run, verbose) do
    if dry_run do
      IO.puts("🔍 Dry run results:")
      IO.puts("  Migration would be performed")
    else
      IO.puts("✅ Migration completed successfully")
      if verbose, do: show_migration_details(result)
    end
  end

  defp show_migration_details(result) do
    IO.puts("  Migration ID: #{result.migration_id}")
    IO.puts("  Execution time: #{result.result.execution_time}ms")
  end

  @doc """
  Migrate preferences to latest schema.
  """
  def migrate_config(opts) do
    target_version = Map.get(opts, :version, "latest")
    dry_run = Map.get(opts, :dry_run, false)
    verbose = Map.get(opts, :verbose, false)

    IO.puts("🔄 Migrating preferences to #{target_version}...")

    {:ok, migration_agent} = PreferenceMigrationAgent.create_preference_migration_agent()

    migration_rules = get_migration_rules(target_version)

    case PreferenceMigrationAgent.migrate_preferences_to_version(
           migration_agent,
           target_version,
           migration_rules
         ) do
      {:ok, result} ->
        handle_migration_success(result, dry_run, verbose)

      {:error, %{reason: reason, rollback: rollback_result}} ->
        IO.puts("❌ Migration failed: #{reason}")
        IO.puts("🔄 Automatic rollback completed")

        if verbose do
          IO.puts("  Rollback time: #{rollback_result.rollback_time}ms")
          IO.puts("  Restored items: #{rollback_result.restored_items}")
        end

        System.halt(1)

      {:error, reason} ->
        IO.puts("❌ Migration failed: #{reason}")
        System.halt(1)
    end
  end

  @doc """
  Create configuration backup.
  """
  def backup_config(opts) do
    backup_name = Map.get(opts, :name, "cli_backup_#{DateTime.utc_now() |> DateTime.to_unix()}")
    include_templates = Map.get(opts, :include_templates, true)
    verbose = Map.get(opts, :verbose, false)

    IO.puts("💾 Creating configuration backup...")

    {:ok, migration_agent} = PreferenceMigrationAgent.create_preference_migration_agent()

    backup_context = %{
      name: backup_name,
      include_templates: include_templates,
      created_via: "cli"
    }

    case PreferenceMigrationAgent.create_preference_backup(migration_agent, backup_context) do
      {:ok, backup_id, _updated_agent} ->
        IO.puts("✅ Backup created successfully")
        IO.puts("  Backup ID: #{backup_id}")

        if verbose do
          IO.puts("  Includes templates: #{include_templates}")
          IO.puts("  Created at: #{DateTime.utc_now()}")
        end

      {:error, reason, _agent} ->
        IO.puts("❌ Backup failed: #{reason}")
        System.halt(1)
    end
  end

  @doc """
  Restore configuration from backup.
  """
  def restore_config(opts) do
    backup_id = Map.get(opts, :backup_id)
    confirm = Map.get(opts, :confirm, false)
    verbose = Map.get(opts, :verbose, false)

    if is_nil(backup_id) do
      IO.puts("Error: Backup ID required.")
      System.halt(1)
    end

    if not confirm do
      IO.puts("⚠️  This will overwrite your current configuration.")
      IO.puts("Use --confirm to proceed with restoration.")
      System.halt(1)
    end

    IO.puts("🔄 Restoring configuration from backup #{backup_id}...")

    {:ok, migration_agent} = PreferenceMigrationAgent.create_preference_migration_agent()

    case PreferenceMigrationAgent.restore_from_backup(migration_agent, backup_id) do
      {:ok, restoration_result, _updated_agent} ->
        IO.puts("✅ Configuration restored successfully")

        if verbose do
          IO.puts("  Restored items: #{restoration_result.restored_items}")
          IO.puts("  Restoration time: #{restoration_result.restoration_time}ms")
        end

      {:error, reason, _agent} ->
        IO.puts("❌ Restoration failed: #{reason}")
        System.halt(1)
    end
  end

  # Private helper functions

  defp get_user_id_from_opts(opts) do
    case Map.get(opts, :user_id, System.get_env("RUBBER_DUCK_USER_ID")) do
      nil ->
        IO.puts(
          "Error: User ID required. Use --user-id or set RUBBER_DUCK_USER_ID environment variable."
        )

        System.halt(1)

      user_id ->
        user_id
    end
  end

  defp get_current_preferences(_user_id, _project_id, _category) do
    # Placeholder for getting current preferences
    {:ok, %{"example.key" => "example_value"}}
  end

  defp display_validation_results(validation_result, verbose) do
    show_validation_status(validation_result.valid)

    if verbose or not validation_result.valid do
      show_detailed_results(validation_result)
    end
  end

  defp show_validation_status(true), do: IO.puts("✅ Configuration is valid")
  defp show_validation_status(false), do: IO.puts("❌ Configuration has validation errors")

  defp show_detailed_results(validation_result) do
    if validation_result.conflicts.has_conflicts do
      IO.puts("\n🚨 Conflicts detected:")
      display_conflicts(validation_result.conflicts)
    end

    unless Enum.empty?(validation_result.warnings) do
      show_warnings(validation_result.warnings)
    end
  end

  defp show_warnings(warnings) do
    IO.puts("\n⚠️  Warnings:")
    Enum.each(warnings, &IO.puts("  - #{&1.message}"))
  end

  defp display_conflicts(conflicts) do
    Enum.each(conflicts.constraint_violations, fn {key, message} ->
      IO.puts("  - #{key}: #{message}")
    end)
  end

  defp get_migration_rules(_target_version) do
    # Placeholder for migration rules
    %{
      preference_transformations: [],
      new_preferences: [],
      deprecated_preferences: []
    }
  end
end
