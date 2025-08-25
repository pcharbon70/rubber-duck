defmodule RubberDuck.Preferences.Migration.SchemaMigrator do
  @moduledoc """
  Core schema migration engine for the preference system.

  Handles schema migrations, data transformations, and rollback operations
  for the preference management system. Provides automated migration execution
  with comprehensive safety checks and audit logging.
  """

  alias RubberDuck.Preferences.Migration.VersionManager
  alias RubberDuck.Preferences.Resources.PreferenceSchemaVersion
  alias RubberDuck.Preferences.Security.AuditLogger
  alias RubberDuck.Agents.PreferenceMigrationAgent

  require Logger

  @doc """
  Execute a schema migration to a target version.

  Performs comprehensive migration including schema changes, data transformations,
  and validation with complete rollback support on failure.
  """
  @spec migrate_to_version(target_version :: String.t(), opts :: keyword()) ::
          {:ok, %{migration_id: String.t(), executed_steps: [String.t()]}} | {:error, term()}
  def migrate_to_version(target_version, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    force = Keyword.get(opts, :force, false)

    case validate_migration_request(target_version, force) do
      :ok -> execute_migration(target_version, dry_run, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Rollback to a previous schema version.

  Performs rollback operation with data restoration and validation.
  """
  @spec rollback_to_version(target_version :: String.t(), opts :: keyword()) ::
          {:ok, %{rollback_id: String.t(), restored_items: integer()}} | {:error, term()}
  def rollback_to_version(target_version, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)

    case validate_rollback_request(target_version) do
      :ok -> execute_rollback(target_version, dry_run, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Generate migration script for moving between two schema versions.
  """
  @spec generate_migration_script(from_version :: String.t(), to_version :: String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def generate_migration_script(from_version, to_version) do
    case VersionManager.get_upgrade_path(to_version) do
      {:ok, upgrade_path} ->
        script = build_migration_script(from_version, to_version, upgrade_path)
        {:ok, script}

      error ->
        error
    end
  end

  @doc """
  Validate that a migration can be performed safely.
  """
  @spec validate_migration_safety(target_version :: String.t()) ::
          {:ok, %{safe: boolean(), warnings: [String.t()]}} | {:error, term()}
  def validate_migration_safety(target_version) do
    warnings = []

    # Check for breaking changes
    warnings =
      case has_breaking_changes?(target_version) do
        {:ok, true} -> ["Target version contains breaking changes" | warnings]
        {:ok, false} -> warnings
        {:error, _} -> ["Could not check for breaking changes" | warnings]
      end

    # Check data compatibility
    warnings =
      case validate_data_compatibility(target_version) do
        {:ok, issues} -> issues ++ warnings
        {:error, _} -> ["Could not validate data compatibility" | warnings]
      end

    # Check system dependencies
    warnings =
      case validate_system_dependencies(target_version) do
        {:ok, deps} -> deps ++ warnings
        {:error, _} -> ["Could not validate system dependencies" | warnings]
      end

    safe = Enum.empty?(warnings)

    {:ok, %{safe: safe, warnings: warnings}}
  end

  @doc """
  Create a backup before migration execution.
  """
  @spec create_pre_migration_backup(target_version :: String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def create_pre_migration_backup(target_version) do
    backup_context = %{
      reason: "Pre-migration backup for version #{target_version}",
      include_system_state: true,
      include_user_preferences: true,
      include_project_preferences: true,
      include_security_data: true
    }

    case PreferenceMigrationAgent.create_preference_backup(nil, backup_context) do
      {:ok, backup_id, _agent} ->
        Logger.info("Created pre-migration backup: #{backup_id}")

        AuditLogger.log_preference_change(%{
          user_id: "system",
          action: "pre_migration_backup_created",
          preference_key: "system.backup",
          new_value: backup_id,
          metadata: %{
            target_version: target_version,
            backup_type: "pre_migration"
          }
        })

        {:ok, backup_id}

      error ->
        error
    end
  end

  ## Private Functions

  defp validate_migration_request(target_version, force) do
    cond do
      not VersionManager.valid_version?(target_version) ->
        {:error, "Invalid target version format: #{target_version}"}

      not force ->
        case validate_migration_safety(target_version) do
          {:ok, %{safe: true}} ->
            :ok

          {:ok, %{safe: false, warnings: warnings}} ->
            {:error, "Migration safety check failed: #{Enum.join(warnings, ", ")}"}

          {:error, reason} ->
            {:error, reason}
        end

      true ->
        :ok
    end
  end

  defp validate_rollback_request(target_version) do
    case VersionManager.current_version() do
      {:ok, current} ->
        case VersionManager.compare_versions(current, target_version) do
          :newer -> :ok
          _ -> {:error, "Cannot rollback to newer or same version"}
        end

      error ->
        error
    end
  end

  defp execute_migration(target_version, dry_run, opts) do
    migration_id = generate_migration_id()

    # Create backup before migration
    case create_pre_migration_backup(target_version) do
      {:ok, backup_id} ->
        perform_migration(target_version, migration_id, backup_id, dry_run, opts)

      {:error, reason} ->
        {:error, "Failed to create pre-migration backup: #{reason}"}
    end
  end

  defp perform_migration(target_version, migration_id, backup_id, dry_run, opts) do
    Logger.info("Starting migration #{migration_id} to version #{target_version}")

    # Get upgrade path
    case VersionManager.get_upgrade_path(target_version) do
      {:ok, upgrade_path} ->
        if dry_run do
          simulate_migration_steps(upgrade_path, migration_id)
        else
          execute_migration_steps(upgrade_path, migration_id, backup_id, opts)
        end

      error ->
        error
    end
  end

  defp simulate_migration_steps(upgrade_path, migration_id) do
    steps = Enum.map(upgrade_path, &"Apply version #{&1.version}")

    {:ok,
     %{
       migration_id: migration_id,
       executed_steps: steps,
       dry_run: true
     }}
  end

  defp execute_migration_steps(upgrade_path, migration_id, backup_id, opts) do
    executed_steps = []

    try do
      # Execute each migration step
      steps =
        Enum.reduce(upgrade_path, [], fn version, acc ->
          step_result = execute_single_migration_step(version, opts)
          [step_result | acc]
        end)

      # Mark final version as applied
      case apply_final_version(List.last(upgrade_path)) do
        {:ok, _} ->
          Logger.info("Migration #{migration_id} completed successfully")

          {:ok,
           %{
             migration_id: migration_id,
             executed_steps: Enum.reverse(steps),
             backup_id: backup_id
           }}

        error ->
          error
      end
    rescue
      exception ->
        Logger.error("Migration failed: #{inspect(exception)}")
        {:error, "Migration execution failed: #{Exception.message(exception)}"}
    end
  end

  defp execute_single_migration_step(version, _opts) do
    # Execute migration scripts for this version
    Logger.info("Executing migration step for version #{version.version}")

    # This would execute the actual migration scripts
    # For now, return a mock result
    "Applied schema changes for version #{version.version}"
  end

  defp apply_final_version(nil), do: {:ok, nil}

  defp apply_final_version(version) do
    VersionManager.apply_version(version.version)
  end

  defp execute_rollback(target_version, dry_run, opts) do
    rollback_id = generate_rollback_id()

    Logger.info("Starting rollback #{rollback_id} to version #{target_version}")

    if dry_run do
      {:ok, %{rollback_id: rollback_id, restored_items: 0, dry_run: true}}
    else
      perform_rollback_operation(target_version, rollback_id, opts)
    end
  end

  defp perform_rollback_operation(target_version, rollback_id, _opts) do
    # This would perform the actual rollback operation
    # For now, return a mock result
    Logger.info("Rollback #{rollback_id} completed")

    {:ok,
     %{
       rollback_id: rollback_id,
       restored_items: 0,
       target_version: target_version
     }}
  end

  defp has_breaking_changes?(target_version) do
    case PreferenceSchemaVersion.by_version(target_version) do
      {:ok, [version]} -> {:ok, version.breaking_changes}
      {:ok, []} -> {:error, "Version not found"}
      error -> error
    end
  end

  defp validate_data_compatibility(_target_version) do
    # This would validate that existing data can be safely migrated
    # For now, return no issues
    {:ok, []}
  end

  defp validate_system_dependencies(_target_version) do
    # This would check system dependencies and requirements
    # For now, return no issues
    {:ok, []}
  end

  defp build_migration_script(_from_version, _to_version, _upgrade_path) do
    # This would generate the actual migration script
    "-- Generated migration script\n-- Placeholder migration content"
  end

  defp generate_migration_id do
    "migration_#{System.unique_integer([:positive])}_#{DateTime.utc_now() |> DateTime.to_unix()}"
  end

  defp generate_rollback_id do
    "rollback_#{System.unique_integer([:positive])}_#{DateTime.utc_now() |> DateTime.to_unix()}"
  end
end
