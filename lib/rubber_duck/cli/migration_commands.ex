defmodule RubberDuck.CLI.MigrationCommands do
  @moduledoc """
  CLI commands for preference migration operations.

  Provides comprehensive migration functionality including schema migrations,
  data transformations, rollback operations, and migration management.
  """

  alias RubberDuck.Preferences.Migration.{SchemaMigrator, VersionManager}
  alias RubberDuck.Preferences.Backup.BackupManager

  require Logger

  @doc """
  Execute a schema migration to target version.
  """
  def migrate_to_version(opts) do
    target_version = Map.get(opts, :version)
    dry_run = Map.get(opts, :dry_run, false)
    force = Map.get(opts, :force, false)

    if target_version do
      execute_migration(target_version, dry_run, force, opts)
    else
      IO.puts("❌ Target version required. Use --version to specify.")
      System.halt(1)
    end
  end

  @doc """
  Rollback to a previous schema version.
  """
  def rollback_to_version(opts) do
    target_version = Map.get(opts, :version)
    dry_run = Map.get(opts, :dry_run, false)

    if target_version do
      execute_rollback(target_version, dry_run, opts)
    else
      IO.puts("❌ Target version required. Use --version to specify.")
      System.halt(1)
    end
  end

  @doc """
  Show current schema version and migration status.
  """
  def show_migration_status(opts) do
    verbose = Map.get(opts, :verbose, false)

    case VersionManager.current_version() do
      {:ok, current} ->
        IO.puts("📋 Current Schema Version: #{current}")

        case VersionManager.up_to_date?() do
          {:ok, true} ->
            IO.puts("✅ Schema is up to date")

          {:ok, false} ->
            IO.puts("⚠️  Schema updates available")
            if verbose, do: show_available_updates()

          {:error, reason} ->
            IO.puts("❌ Could not check update status: #{reason}")
        end

        if verbose, do: show_detailed_status()

      {:error, reason} ->
        IO.puts("❌ Could not determine current version: #{reason}")
        System.halt(1)
    end
  end

  @doc """
  List available schema versions.
  """
  def list_schema_versions(opts) do
    format = Map.get(opts, :format, "table")

    case VersionManager.list_versions() do
      {:ok, versions} ->
        display_versions(versions, format)

      {:error, reason} ->
        IO.puts("❌ Could not list versions: #{reason}")
        System.halt(1)
    end
  end

  @doc """
  Validate migration safety for target version.
  """
  def validate_migration(opts) do
    target_version = Map.get(opts, :version)

    if target_version do
      case SchemaMigrator.validate_migration_safety(target_version) do
        {:ok, %{safe: true}} ->
          IO.puts("✅ Migration to #{target_version} is safe")

        {:ok, %{safe: false, warnings: warnings}} ->
          IO.puts("⚠️  Migration to #{target_version} has warnings:")
          Enum.each(warnings, &IO.puts("  - #{&1}"))
          System.halt(1)

        {:error, reason} ->
          IO.puts("❌ Migration validation failed: #{reason}")
          System.halt(1)
      end
    else
      IO.puts("❌ Target version required. Use --version to specify.")
      System.halt(1)
    end
  end

  ## Private Functions

  defp execute_migration(target_version, dry_run, force, opts) do
    if dry_run do
      IO.puts("🔍 Dry run: Migration to #{target_version}")
    else
      IO.puts("🔄 Migrating to schema version #{target_version}...")
    end

    case SchemaMigrator.migrate_to_version(target_version, dry_run: dry_run, force: force) do
      {:ok, result} ->
        if dry_run do
          IO.puts("✅ Dry run completed")
          IO.puts("  Migration ID: #{result.migration_id}")
          IO.puts("  Steps: #{length(result.executed_steps)}")
        else
          IO.puts("✅ Migration completed successfully")
          IO.puts("  Migration ID: #{result.migration_id}")
          IO.puts("  Backup ID: #{result[:backup_id]}")

          if Map.get(opts, :verbose) do
            IO.puts("  Executed steps:")
            Enum.each(result.executed_steps, &IO.puts("    - #{&1}"))
          end
        end

      {:error, reason} ->
        IO.puts("❌ Migration failed: #{reason}")
        System.halt(1)
    end
  end

  defp execute_rollback(target_version, dry_run, opts) do
    if dry_run do
      IO.puts("🔍 Dry run: Rollback to #{target_version}")
    else
      IO.puts("🔄 Rolling back to schema version #{target_version}...")
    end

    case SchemaMigrator.rollback_to_version(target_version, dry_run: dry_run) do
      {:ok, result} ->
        if dry_run do
          IO.puts("✅ Dry run completed")
        else
          IO.puts("✅ Rollback completed successfully")
          IO.puts("  Rollback ID: #{result.rollback_id}")
          IO.puts("  Restored items: #{result.restored_items}")
        end

      {:error, reason} ->
        IO.puts("❌ Rollback failed: #{reason}")
        System.halt(1)
    end
  end

  defp show_available_updates do
    # This would show available schema versions
    IO.puts("  Available updates: Check with 'list-versions' command")
  end

  defp show_detailed_status do
    # This would show detailed migration status
    IO.puts("  Run with --verbose for detailed status")
  end

  defp display_versions(versions, "table") do
    IO.puts("\n" <>
      String.pad_trailing("VERSION", 15) <>
      " | " <>
      String.pad_trailing("NAME", 25) <>
      " | " <>
      String.pad_trailing("STATUS", 12) <>
      " | DESCRIPTION")

    IO.puts(String.duplicate("-", 80))

    Enum.each(versions, fn version ->
      status = if version.applied_at, do: "APPLIED", else: "AVAILABLE"
      status = if version.deprecated, do: "DEPRECATED", else: status

      version_str = String.pad_trailing(version.version, 15)
      name_str = String.pad_trailing(version.version_name || "N/A", 25)
      status_str = String.pad_trailing(status, 12)
      description = String.slice(version.description || "", 0, 40)

      IO.puts("#{version_str} | #{name_str} | #{status_str} | #{description}")
    end)

    IO.puts("\nTotal: #{length(versions)} versions")
  end

  defp display_versions(versions, "json") do
    simplified_versions = Enum.map(versions, fn version ->
      %{
        version: version.version,
        name: version.version_name,
        applied: not is_nil(version.applied_at),
        deprecated: version.deprecated,
        breaking_changes: version.breaking_changes,
        migration_required: version.migration_required
      }
    end)

    case Jason.encode(simplified_versions, pretty: true) do
      {:ok, json} -> IO.puts(json)
      {:error, _} -> IO.puts("❌ Could not format as JSON")
    end
  end
end