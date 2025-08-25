defmodule RubberDuck.Preferences.Migration.VersionManager do
  @moduledoc """
  Schema version management for the preference system.

  Manages schema versioning, compatibility checking, and upgrade path
  determination for the preference management system. Provides automated
  detection of schema changes and calculation of migration requirements.
  """

  alias RubberDuck.Preferences.Resources.PreferenceSchemaVersion
  alias RubberDuck.Preferences.Security.AuditLogger

  require Logger

  @current_schema_version "1.0.0"

  @doc """
  Get the current schema version of the preference system.
  """
  @spec current_version() :: {:ok, String.t()} | {:error, term()}
  def current_version do
    case PreferenceSchemaVersion.current_version() do
      {:ok, [version]} -> {:ok, version.version}
      {:ok, []} -> {:ok, @current_schema_version}
      error -> error
    end
  end

  @doc """
  Check if a migration is required from current version to target version.
  """
  @spec migration_required?(target_version :: String.t()) ::
          {:ok, boolean()} | {:error, term()}
  def migration_required?(target_version) do
    case current_version() do
      {:ok, current} ->
        case compare_versions(current, target_version) do
          :equal -> {:ok, false}
          :older -> {:ok, true}
          # Downgrade scenario
          :newer -> {:ok, false}
          :incomparable -> {:error, "Version comparison failed"}
        end

      error ->
        error
    end
  end

  @doc """
  Get the upgrade path from current version to target version.
  """
  @spec get_upgrade_path(target_version :: String.t()) ::
          {:ok, [PreferenceSchemaVersion.t()]} | {:error, term()}
  def get_upgrade_path(target_version) do
    case current_version() do
      {:ok, current} ->
        case calculate_upgrade_path(current, target_version) do
          {:ok, path} -> {:ok, path}
          {:error, reason} -> {:error, reason}
        end

      error ->
        error
    end
  end

  @doc """
  Check compatibility between two schema versions.
  """
  @spec versions_compatible?(version1 :: String.t(), version2 :: String.t()) :: boolean()
  def versions_compatible?(version1, version2) do
    case compare_versions(version1, version2) do
      :equal -> true
      _ -> check_compatibility_matrix(version1, version2)
    end
  end

  @doc """
  Register a new schema version in the system.
  """
  @spec register_version(version_params :: map()) ::
          {:ok, PreferenceSchemaVersion.t()} | {:error, term()}
  def register_version(version_params) do
    case PreferenceSchemaVersion.create(version_params) do
      {:ok, version} ->
        Logger.info("Registered new schema version: #{version.version}")

        AuditLogger.log_preference_change(%{
          user_id: "system",
          action: "schema_version_registered",
          preference_key: "system.schema_version",
          new_value: version.version,
          metadata: %{
            breaking_changes: version.breaking_changes,
            migration_required: version.migration_required
          }
        })

        {:ok, version}

      error ->
        error
    end
  end

  @doc """
  Apply a schema version to mark it as current.
  """
  @spec apply_version(version :: String.t()) ::
          {:ok, PreferenceSchemaVersion.t()} | {:error, term()}
  def apply_version(version) do
    case PreferenceSchemaVersion.by_version(version) do
      {:ok, [schema_version]} ->
        case PreferenceSchemaVersion.mark_applied(schema_version) do
          {:ok, updated_version} ->
            Logger.info("Applied schema version: #{version}")

            AuditLogger.log_preference_change(%{
              user_id: "system",
              action: "schema_version_applied",
              preference_key: "system.schema_version",
              new_value: version,
              metadata: %{applied_at: updated_version.applied_at}
            })

            {:ok, updated_version}

          error ->
            error
        end

      {:ok, []} ->
        {:error, "Schema version not found: #{version}"}

      error ->
        error
    end
  end

  @doc """
  Get all available schema versions ordered by version number.
  """
  @spec list_versions() :: {:ok, [PreferenceSchemaVersion.t()]} | {:error, term()}
  def list_versions do
    PreferenceSchemaVersion.read()
  end

  @doc """
  Check if the current system is at the latest schema version.
  """
  @spec up_to_date?() :: {:ok, boolean()} | {:error, term()}
  def up_to_date? do
    case get_latest_version() do
      {:ok, latest} ->
        case current_version() do
          {:ok, current} -> {:ok, current == latest.version}
          error -> error
        end

      error ->
        error
    end
  end

  @doc """
  Validate a schema version format.
  """
  @spec valid_version?(version :: String.t()) :: boolean()
  def valid_version?(version) when is_binary(version) do
    Regex.match?(~r/^\d+\.\d+\.\d+(?:-[a-zA-Z0-9\-\.]+)?$/, version)
  end

  def valid_version?(_), do: false

  ## Private Functions

  defp compare_versions(version1, version2) do
    case {parse_version(version1), parse_version(version2)} do
      {{:ok, v1}, {:ok, v2}} -> compare_parsed_versions(v1, v2)
      _ -> :incomparable
    end
  end

  defp parse_version(version) do
    case Regex.run(~r/^(\d+)\.(\d+)\.(\d+)(?:-(.+))?$/, version) do
      [_, major, minor, patch] ->
        {:ok,
         %{
           major: String.to_integer(major),
           minor: String.to_integer(minor),
           patch: String.to_integer(patch),
           pre_release: nil
         }}

      [_, major, minor, patch, pre_release] ->
        {:ok,
         %{
           major: String.to_integer(major),
           minor: String.to_integer(minor),
           patch: String.to_integer(patch),
           pre_release: pre_release
         }}

      _ ->
        {:error, "Invalid version format"}
    end
  end

  defp compare_parsed_versions(v1, v2) do
    cond do
      v1.major > v2.major -> :newer
      v1.major < v2.major -> :older
      v1.minor > v2.minor -> :newer
      v1.minor < v2.minor -> :older
      v1.patch > v2.patch -> :newer
      v1.patch < v2.patch -> :older
      true -> :equal
    end
  end

  defp calculate_upgrade_path(current_version, target_version) do
    # This would calculate the series of versions to upgrade through
    # For now, return a simple path
    case PreferenceSchemaVersion.read() do
      {:ok, all_versions} ->
        path =
          Enum.filter(all_versions, fn version ->
            version_between?(version.version, current_version, target_version)
          end)

        {:ok, Enum.sort_by(path, &parse_version_for_sort/1)}

      error ->
        error
    end
  end

  defp version_between?(version, start_version, end_version) do
    case {compare_versions(version, start_version), compare_versions(version, end_version)} do
      {:newer, :older} -> true
      {:newer, :equal} -> true
      {:equal, :older} -> true
      {:equal, :equal} -> true
      _ -> false
    end
  end

  defp parse_version_for_sort(version) do
    case parse_version(version.version) do
      {:ok, parsed} -> {parsed.major, parsed.minor, parsed.patch}
      _ -> {0, 0, 0}
    end
  end

  defp check_compatibility_matrix(version1, version2) do
    # This would check the compatibility matrix stored in the schema versions
    # For now, assume versions are compatible within the same major version
    case {parse_version(version1), parse_version(version2)} do
      {{:ok, v1}, {:ok, v2}} -> v1.major == v2.major
      _ -> false
    end
  end

  defp get_latest_version do
    case PreferenceSchemaVersion.read() do
      {:ok, versions} ->
        latest = Enum.max_by(versions, &parse_version_for_sort/1, fn -> nil end)
        if latest, do: {:ok, latest}, else: {:error, "No versions found"}

      error ->
        error
    end
  end
end
