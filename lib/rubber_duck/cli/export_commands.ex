defmodule RubberDuck.CLI.ExportCommands do
  @moduledoc """
  CLI commands for preference export/import operations.

  Provides comprehensive export and import functionality with multiple formats,
  conflict resolution, and backup management capabilities.
  """

  alias RubberDuck.Preferences.Backup.BackupManager
  alias RubberDuck.Preferences.Export.{ExportEngine, ImportEngine}

  require Logger

  @doc """
  Export preferences to file.
  """
  def export_preferences(opts) do
    format = Map.get(opts, :format, "json")
    output_file = Map.get(opts, :output, generate_export_filename(format))
    scope = Map.get(opts, :scope, "all")

    IO.puts("📤 Exporting preferences (#{scope}) to #{output_file}...")

    export_opts = [
      format: String.to_atom(format),
      scope: String.to_atom(scope),
      encrypt_sensitive: Map.get(opts, :encrypt, true),
      compression: Map.get(opts, :compress, false)
    ]

    case ExportEngine.export_preferences(export_opts) do
      {:ok, result} ->
        case write_export_file(output_file, result.data) do
          :ok ->
            IO.puts("✅ Export completed successfully")
            IO.puts("  File: #{output_file}")
            IO.puts("  Size: #{format_bytes(byte_size(result.data))}")
            IO.puts("  Format: #{format}")

            if Map.get(opts, :verbose) do
              display_export_metadata(result.metadata)
            end

          {:error, reason} ->
            IO.puts("❌ Failed to write export file: #{reason}")
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts("❌ Export failed: #{reason}")
        System.halt(1)
    end
  end

  @doc """
  Import preferences from file.
  """
  def import_preferences(opts) do
    input_file = Map.get(opts, :input)
    format = Map.get(opts, :format, "json")
    merge_strategy = Map.get(opts, :merge, "merge")
    dry_run = Map.get(opts, :dry_run, false)

    unless input_file do
      IO.puts("❌ Input file required. Use --input to specify.")
      System.halt(1)
    end

    if dry_run do
      IO.puts("🔍 Dry run: Importing preferences from #{input_file}...")
    else
      IO.puts("📥 Importing preferences from #{input_file}...")
    end

    case read_import_file(input_file) do
      {:ok, data} ->
        import_opts = [
          format: String.to_atom(format),
          merge_strategy: String.to_atom(merge_strategy),
          dry_run: dry_run,
          validate_schema: Map.get(opts, :validate_schema, true)
        ]

        case ImportEngine.import_preferences(data, import_opts) do
          {:ok, result} ->
            display_import_results(result, dry_run)

          {:error, reason} ->
            IO.puts("❌ Import failed: #{reason}")
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts("❌ Could not read import file: #{reason}")
        System.halt(1)
    end
  end

  @doc """
  Preview import operation without applying changes.
  """
  def preview_import(opts) do
    input_file = Map.get(opts, :input)
    format = Map.get(opts, :format, "json")

    unless input_file do
      IO.puts("❌ Input file required. Use --input to specify.")
      System.halt(1)
    end

    IO.puts("🔍 Previewing import from #{input_file}...")

    case read_import_file(input_file) do
      {:ok, data} ->
        case ImportEngine.preview_import(data, String.to_atom(format)) do
          {:ok, preview} ->
            display_import_preview(preview)

          {:error, reason} ->
            IO.puts("❌ Preview failed: #{reason}")
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts("❌ Could not read import file: #{reason}")
        System.halt(1)
    end
  end

  @doc """
  Create a backup.
  """
  def create_backup(opts) do
    format = Map.get(opts, :format, "binary")
    output_file = Map.get(opts, :output, generate_backup_filename())

    IO.puts("💾 Creating backup...")

    backup_opts = [
      format: String.to_atom(format),
      compression: Map.get(opts, :compress, true),
      encryption: Map.get(opts, :encrypt, true)
    ]

    case BackupManager.create_backup(backup_opts) do
      {:ok, result} ->
        # Copy backup to specified location if needed
        if output_file != result.path do
          case File.cp(result.path, output_file) do
            :ok ->
              IO.puts("✅ Backup created successfully")
              IO.puts("  Backup ID: #{result.backup_id}")
              IO.puts("  File: #{output_file}")
              IO.puts("  Size: #{format_bytes(result.size_bytes)}")

            {:error, reason} ->
              IO.puts("❌ Failed to copy backup to #{output_file}: #{reason}")
              IO.puts("  Backup available at: #{result.path}")
          end
        else
          IO.puts("✅ Backup created successfully")
          IO.puts("  Backup ID: #{result.backup_id}")
          IO.puts("  File: #{result.path}")
          IO.puts("  Size: #{format_bytes(result.size_bytes)}")
        end

      {:error, reason} ->
        IO.puts("❌ Backup failed: #{reason}")
        System.halt(1)
    end
  end

  @doc """
  Restore from backup.
  """
  def restore_backup(opts) do
    backup_file = Map.get(opts, :backup)
    dry_run = Map.get(opts, :dry_run, false)

    unless backup_file do
      IO.puts("❌ Backup file required. Use --backup to specify.")
      System.halt(1)
    end

    if dry_run do
      IO.puts("🔍 Dry run: Restoring from #{backup_file}...")
    else
      IO.puts("🔄 Restoring from backup #{backup_file}...")
    end

    case read_import_file(backup_file) do
      {:ok, backup_data} ->
        restore_opts = [
          dry_run: dry_run,
          merge_strategy: :overwrite
        ]

        case ImportEngine.restore_from_backup(backup_data, restore_opts) do
          {:ok, result} ->
            if dry_run do
              IO.puts("✅ Dry run completed")
            else
              IO.puts("✅ Backup restored successfully")
              IO.puts("  Restored items: #{result.restored_count}")
            end

          {:error, reason} ->
            IO.puts("❌ Restore failed: #{reason}")
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts("❌ Could not read backup file: #{reason}")
        System.halt(1)
    end
  end

  @doc """
  List available backups.
  """
  def list_backups(opts) do
    limit = Map.get(opts, :limit, 20)
    format = Map.get(opts, :format, "table")

    case BackupManager.list_backups(limit: limit) do
      {:ok, backups} ->
        display_backups(backups, format)

      {:error, reason} ->
        IO.puts("❌ Could not list backups: #{reason}")
        System.halt(1)
    end
  end

  ## Private Functions

  defp generate_export_filename(format) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)
    "preferences_export_#{timestamp}.#{format}"
  end

  defp generate_backup_filename do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)
    "preferences_backup_#{timestamp}.backup"
  end

  defp write_export_file(filename, data) do
    File.write(filename, data)
  end

  defp read_import_file(filename) do
    File.read(filename)
  end

  defp display_export_metadata(metadata) do
    IO.puts("\n📋 Export Details:")
    IO.puts("  Export Version: #{metadata.export_version}")
    IO.puts("  Schema Version: #{metadata.schema_version}")
    IO.puts("  Exported At: #{metadata.exported_at}")
    IO.puts("  Encryption: #{metadata.encryption_used}")
    IO.puts("  Compression: #{metadata.compression_used}")
  end

  defp display_import_results(result, dry_run) do
    if dry_run do
      IO.puts("✅ Dry run completed")
      IO.puts("  Would import: #{result.imported_count} items")
    else
      IO.puts("✅ Import completed successfully")
      IO.puts("  Imported: #{result.imported_count} items")
    end

    unless Enum.empty?(result.conflicts) do
      IO.puts("  Conflicts: #{length(result.conflicts)}")
      Enum.each(result.conflicts, fn conflict ->
        IO.puts("    - #{conflict.type}: #{conflict.preference_key}")
      end)
    end

    unless Enum.empty?(result.warnings) do
      IO.puts("  Warnings:")
      Enum.each(result.warnings, &IO.puts("    - #{&1}"))
    end
  end

  defp display_import_preview(preview) do
    IO.puts("📋 Import Preview:")
    IO.puts("  Total items: #{preview.preview.total_items}")
    IO.puts("  System defaults: #{preview.preview.system_defaults_count}")
    IO.puts("  User preferences: #{preview.preview.user_preferences_count}")
    IO.puts("  Project preferences: #{preview.preview.project_preferences_count}")
    IO.puts("  Templates: #{preview.preview.templates_count}")

    unless Enum.empty?(preview.conflicts) do
      IO.puts("\n⚠️  Conflicts detected:")
      Enum.each(preview.conflicts, fn conflict ->
        IO.puts("  - #{conflict.type}: #{conflict.preference_key}")
      end)
    end

    unless Enum.empty?(preview.changes) do
      IO.puts("\n📝 Changes to be made:")
      Enum.take(preview.changes, 10) |> Enum.each(fn change ->
        IO.puts("  - #{change.action}: #{change.preference_key}")
      end)

      if length(preview.changes) > 10 do
        IO.puts("  ... and #{length(preview.changes) - 10} more")
      end
    end
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
      status = cond do
        version.applied_at -> "CURRENT"
        version.deprecated -> "DEPRECATED"
        true -> "AVAILABLE"
      end

      version_str = String.pad_trailing(version.version, 15)
      name_str = String.pad_trailing(version.version_name || "N/A", 25)
      status_str = String.pad_trailing(status, 12)
      description = String.slice(version.description || "", 0, 40)

      IO.puts("#{version_str} | #{name_str} | #{status_str} | #{description}")
    end)
  end

  defp display_backups(backups, "table") do
    if Enum.empty?(backups) do
      IO.puts("No backups found.")
    else
      IO.puts("\n" <>
        String.pad_trailing("BACKUP ID", 30) <>
        " | " <>
        String.pad_trailing("CREATED", 20) <>
        " | SIZE")

      IO.puts(String.duplicate("-", 60))

      Enum.each(backups, fn backup ->
        backup_id = String.pad_trailing(backup.backup_id, 30)
        created = String.pad_trailing(format_datetime(backup.created_at), 20)
        size = format_bytes(backup.size_bytes)

        IO.puts("#{backup_id} | #{created} | #{size}")
      end)
    end
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024, do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"

  defp format_datetime(datetime) do
    DateTime.to_string(datetime) |> String.slice(0, 19)
  end
end
