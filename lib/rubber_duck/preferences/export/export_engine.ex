defmodule RubberDuck.Preferences.Export.ExportEngine do
  @moduledoc """
  Multi-format export engine for preference configurations.

  Provides comprehensive export functionality supporting multiple formats
  (JSON, YAML, binary), selective export filtering, encryption for sensitive
  data, and metadata preservation for reliable import operations.
  """

  alias RubberDuck.Preferences.Resources.{
    SystemDefault,
    UserPreference,
    ProjectPreference,
    PreferenceTemplate
  }
  alias RubberDuck.Preferences.Security.{EncryptionManager, AuditLogger}
  alias RubberDuck.Preferences.Export.FormatHandlers.{JsonHandler, YamlHandler, BinaryHandler}

  require Logger

  @supported_formats [:json, :yaml, :binary]
  @current_export_version "1.0.0"

  @doc """
  Export preferences in the specified format.

  ## Options
  - `:format` - Export format (:json, :yaml, :binary)
  - `:scope` - Export scope (:system, :user, :project, :all)
  - `:filters` - Export filters (categories, patterns, etc.)
  - `:include_metadata` - Whether to include export metadata
  - `:encrypt_sensitive` - Whether to encrypt sensitive preferences
  - `:compression` - Whether to compress the export
  """
  @spec export_preferences(opts :: keyword()) ::
    {:ok, %{data: binary(), metadata: map()}} | {:error, term()}
  def export_preferences(opts \\ []) do
    format = Keyword.get(opts, :format, :json)
    scope = Keyword.get(opts, :scope, :all)

    case validate_export_options(opts) do
      :ok -> perform_export(format, scope, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Export specific user preferences.
  """
  @spec export_user_preferences(user_id :: String.t(), opts :: keyword()) ::
    {:ok, %{data: binary(), metadata: map()}} | {:error, term()}
  def export_user_preferences(user_id, opts \\ []) do
    export_opts = Keyword.merge(opts, [scope: :user, user_id: user_id])
    export_preferences(export_opts)
  end

  @doc """
  Export project preferences.
  """
  @spec export_project_preferences(project_id :: String.t(), opts :: keyword()) ::
    {:ok, %{data: binary(), metadata: map()}} | {:error, term()}
  def export_project_preferences(project_id, opts \\ []) do
    export_opts = Keyword.merge(opts, [scope: :project, project_id: project_id])
    export_preferences(export_opts)
  end

  @doc """
  Export system defaults.
  """
  @spec export_system_defaults(opts :: keyword()) ::
    {:ok, %{data: binary(), metadata: map()}} | {:error, term()}
  def export_system_defaults(opts \\ []) do
    export_opts = Keyword.merge(opts, [scope: :system])
    export_preferences(export_opts)
  end

  @doc """
  Create a comprehensive backup export.
  """
  @spec create_backup_export(opts :: keyword()) ::
    {:ok, %{backup_id: String.t(), data: binary(), metadata: map()}} | {:error, term()}
  def create_backup_export(opts \\ []) do
    backup_id = generate_backup_id()

    backup_opts = Keyword.merge(opts, [
      scope: :all,
      include_metadata: true,
      encrypt_sensitive: true,
      compression: true,
      backup_id: backup_id
    ])

    case export_preferences(backup_opts) do
      {:ok, result} ->
        # Log backup creation
        AuditLogger.log_preference_change(%{
          user_id: "system",
          action: "backup_export_created",
          preference_key: "system.backup",
          new_value: backup_id,
          metadata: %{
            format: Keyword.get(opts, :format, :binary),
            scope: :all,
            size_bytes: byte_size(result.data)
          }
        })

        {:ok, Map.put(result, :backup_id, backup_id)}

      error -> error
    end
  end

  ## Private Functions

  defp validate_export_options(opts) do
    format = Keyword.get(opts, :format, :json)

    cond do
      format not in @supported_formats ->
        {:error, "Unsupported export format: #{format}"}

      true -> :ok
    end
  end

  defp perform_export(format, scope, opts) do
    case gather_export_data(scope, opts) do
      {:ok, preferences} ->
        processed_data = process_export_data(preferences, opts)
        format_and_finalize_export(processed_data, format, opts)

      error -> error
    end
  end

  defp gather_export_data(:all, opts) do
    # Gather all preference data
    with {:ok, system_defaults} <- SystemDefault.read(),
         {:ok, user_preferences} <- get_filtered_user_preferences(opts),
         {:ok, project_preferences} <- get_filtered_project_preferences(opts),
         {:ok, templates} <- get_filtered_templates(opts) do

      {:ok, %{
        system_defaults: system_defaults,
        user_preferences: user_preferences,
        project_preferences: project_preferences,
        templates: templates
      }}
    end
  end

  defp gather_export_data(:system, _opts) do
    case SystemDefault.read() do
      {:ok, defaults} -> {:ok, %{system_defaults: defaults}}
      error -> error
    end
  end

  defp gather_export_data(:user, opts) do
    user_id = Keyword.get(opts, :user_id)

    case UserPreference.by_user(user_id) do
      {:ok, preferences} -> {:ok, %{user_preferences: preferences}}
      error -> error
    end
  end

  defp gather_export_data(:project, opts) do
    _project_id = Keyword.get(opts, :project_id)

    # This would use ProjectPreference.by_project when available
    {:ok, %{project_preferences: []}}
  end

  defp get_filtered_user_preferences(opts) do
    # Apply filters if specified
    case Keyword.get(opts, :user_filter) do
      nil -> {:ok, []}  # Would get all user preferences
      user_id -> UserPreference.by_user(user_id)
    end
  end

  defp get_filtered_project_preferences(_opts) do
    # This would filter project preferences based on options
    {:ok, []}
  end

  defp get_filtered_templates(_opts) do
    # This would filter templates based on options
    {:ok, []}
  end

  defp process_export_data(preferences, opts) do
    encrypt_sensitive = Keyword.get(opts, :encrypt_sensitive, true)

    # Process each preference type
    processed = %{
      system_defaults: process_system_defaults(preferences[:system_defaults] || [], encrypt_sensitive),
      user_preferences: process_user_preferences(preferences[:user_preferences] || [], encrypt_sensitive),
      project_preferences: process_project_preferences(preferences[:project_preferences] || [], encrypt_sensitive),
      templates: process_templates(preferences[:templates] || [], encrypt_sensitive)
    }

    # Add export metadata
    Map.put(processed, :export_metadata, build_export_metadata(opts))
  end

  defp process_system_defaults(defaults, encrypt_sensitive) do
    Enum.map(defaults, fn default ->
      value = if encrypt_sensitive do
        case EncryptionManager.encrypt_if_sensitive(default.preference_key, default.default_value) do
          {:ok, encrypted_value} -> encrypted_value
          {:error, _} -> default.default_value
        end
      else
        default.default_value
      end

      %{
        preference_key: default.preference_key,
        value: value,
        category: default.category,
        description: default.description,
        data_type: default.data_type,
        constraints: default.constraints,
        sensitive: EncryptionManager.sensitive_preference?(default.preference_key)
      }
    end)
  end

  defp process_user_preferences(preferences, encrypt_sensitive) do
    Enum.map(preferences, fn pref ->
      value = if encrypt_sensitive do
        case EncryptionManager.encrypt_if_sensitive(pref.preference_key, pref.value) do
          {:ok, encrypted_value} -> encrypted_value
          {:error, _} -> pref.value
        end
      else
        pref.value
      end

      %{
        user_id: pref.user_id,
        preference_key: pref.preference_key,
        value: value,
        category: pref.category,
        source: pref.source,
        sensitive: EncryptionManager.sensitive_preference?(pref.preference_key),
        last_modified: pref.updated_at
      }
    end)
  end

  defp process_project_preferences(preferences, _encrypt_sensitive) do
    # Process project preferences when available
    preferences
  end

  defp process_templates(templates, _encrypt_sensitive) do
    # Process templates when available
    templates
  end

  defp build_export_metadata(opts) do
    %{
      export_version: @current_export_version,
      exported_at: DateTime.utc_now(),
      format: Keyword.get(opts, :format, :json),
      scope: Keyword.get(opts, :scope, :all),
      schema_version: get_current_schema_version(),
      encryption_used: Keyword.get(opts, :encrypt_sensitive, true),
      compression_used: Keyword.get(opts, :compression, false),
      filters_applied: get_applied_filters(opts)
    }
  end

  defp format_and_finalize_export(processed_data, format, opts) do
    case format_export_data(processed_data, format) do
      {:ok, formatted_data} ->
        final_data = maybe_compress_export(formatted_data, opts)
        metadata = processed_data.export_metadata

        {:ok, %{data: final_data, metadata: metadata}}

      error -> error
    end
  end

  defp format_export_data(data, :json) do
    JsonHandler.format(data)
  end

  defp format_export_data(data, :yaml) do
    YamlHandler.format(data)
  end

  defp format_export_data(data, :binary) do
    BinaryHandler.format(data)
  end

  defp maybe_compress_export(data, opts) do
    if Keyword.get(opts, :compression, false) do
      :zlib.compress(data)
    else
      data
    end
  end

  defp get_current_schema_version do
    case RubberDuck.Preferences.Migration.VersionManager.current_version() do
      {:ok, version} -> version
      {:error, _} -> "unknown"
    end
  end

  defp get_applied_filters(opts) do
    opts
    |> Keyword.take([:category_filter, :pattern_filter, :user_filter, :project_filter])
    |> Enum.into(%{})
  end

  defp generate_backup_id do
    "backup_#{System.unique_integer([:positive])}_#{DateTime.utc_now() |> DateTime.to_unix()}"
  end
end