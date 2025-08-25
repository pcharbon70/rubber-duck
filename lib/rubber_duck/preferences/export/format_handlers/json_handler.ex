defmodule RubberDuck.Preferences.Export.FormatHandlers.JsonHandler do
  @moduledoc """
  JSON format handler for preference exports.

  Handles encoding and decoding of preference data in JSON format with
  proper type preservation and human-readable structure.
  """

  @doc """
  Format preference data as JSON.
  """
  @spec format(data :: map()) :: {:ok, binary()} | {:error, term()}
  def format(data) do
    try do
      json_data = Jason.encode!(data, pretty: true)
      {:ok, json_data}
    rescue
      error -> {:error, "JSON encoding failed: #{inspect(error)}"}
    end
  end

  @doc """
  Parse JSON preference data.
  """
  @spec parse(json_data :: binary()) :: {:ok, map()} | {:error, term()}
  def parse(json_data) when is_binary(json_data) do
    case Jason.decode(json_data) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, "JSON parsing failed: #{inspect(reason)}"}
    end
  end

  def parse(_), do: {:error, "Input must be binary JSON data"}

  @doc """
  Validate JSON structure for preference import.
  """
  @spec validate_structure(data :: map()) :: {:ok, map()} | {:error, [String.t()]}
  def validate_structure(data) when is_map(data) do
    errors = []

    # Validate export metadata
    errors = validate_export_metadata(data, errors)

    # Validate preference sections
    errors = validate_preference_sections(data, errors)

    if Enum.empty?(errors) do
      {:ok, data}
    else
      {:error, errors}
    end
  end

  def validate_structure(_), do: {:error, ["Data must be a map"]}

  ## Private Functions

  defp validate_export_metadata(data, errors) do
    case Map.get(data, "export_metadata") do
      nil -> ["Missing export_metadata section" | errors]
      metadata when is_map(metadata) -> validate_metadata_fields(metadata, errors)
      _ -> ["export_metadata must be a map" | errors]
    end
  end

  defp validate_metadata_fields(metadata, errors) do
    required_fields = ["export_version", "exported_at", "format", "schema_version"]

    missing_fields =
      Enum.filter(required_fields, fn field ->
        not Map.has_key?(metadata, field)
      end)

    case missing_fields do
      [] -> errors
      fields -> ["Missing metadata fields: #{Enum.join(fields, ", ")}" | errors]
    end
  end

  defp validate_preference_sections(data, errors) do
    sections = ["system_defaults", "user_preferences", "project_preferences", "templates"]

    Enum.reduce(sections, errors, fn section, acc ->
      case Map.get(data, section) do
        # Optional sections
        nil -> acc
        list when is_list(list) -> validate_preference_list(section, list, acc)
        _ -> ["#{section} must be a list" | acc]
      end
    end)
  end

  defp validate_preference_list(section, preferences, errors) do
    case section do
      "system_defaults" -> validate_system_defaults(preferences, errors)
      "user_preferences" -> validate_user_preferences(preferences, errors)
      "project_preferences" -> validate_project_preferences(preferences, errors)
      "templates" -> validate_templates(preferences, errors)
      _ -> errors
    end
  end

  defp validate_system_defaults(defaults, errors) do
    required_fields = ["preference_key", "value", "category", "data_type"]

    invalid_defaults =
      Enum.filter(defaults, fn default ->
        not is_map(default) or
          Enum.any?(required_fields, fn field -> not Map.has_key?(default, field) end)
      end)

    case invalid_defaults do
      [] -> errors
      _ -> ["Invalid system defaults found" | errors]
    end
  end

  defp validate_user_preferences(preferences, errors) do
    required_fields = ["user_id", "preference_key", "value", "category"]

    invalid_prefs =
      Enum.filter(preferences, fn pref ->
        not is_map(pref) or
          Enum.any?(required_fields, fn field -> not Map.has_key?(pref, field) end)
      end)

    case invalid_prefs do
      [] -> errors
      _ -> ["Invalid user preferences found" | errors]
    end
  end

  defp validate_project_preferences(preferences, errors) do
    # Validate project preferences structure
    # For now, just check if it's a list
    if is_list(preferences), do: errors, else: ["Invalid project preferences" | errors]
  end

  defp validate_templates(templates, errors) do
    # Validate template structure
    # For now, just check if it's a list
    if is_list(templates), do: errors, else: ["Invalid templates" | errors]
  end
end
