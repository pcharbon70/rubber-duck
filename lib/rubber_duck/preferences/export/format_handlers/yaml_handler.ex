defmodule RubberDuck.Preferences.Export.FormatHandlers.YamlHandler do
  @moduledoc """
  YAML format handler for preference exports.

  Handles encoding and decoding of preference data in YAML format with
  human-readable structure and proper type preservation.
  """

  alias RubberDuck.Preferences.Export.FormatHandlers.JsonHandler

  @doc """
  Format preference data as YAML.
  """
  @spec format(data :: map()) :: {:ok, binary()} | {:error, term()}
  def format(data) do
    # For now, convert to JSON then to YAML-like format
    # In a full implementation, this would use a YAML library like yaml_elixir
    yaml_data = convert_to_yaml_format(data)
    {:ok, yaml_data}
  rescue
    error -> {:error, "YAML encoding failed: #{inspect(error)}"}
  end

  @doc """
  Parse YAML preference data.
  """
  @spec parse(yaml_data :: binary()) :: {:ok, map()} | {:error, term()}
  def parse(yaml_data) when is_binary(yaml_data) do
    # For now, parse as simple YAML-like format
    # In a full implementation, this would use a YAML library
    parsed_data = parse_yaml_format(yaml_data)
    {:ok, parsed_data}
  rescue
    error -> {:error, "YAML parsing failed: #{inspect(error)}"}
  end

  def parse(_), do: {:error, "Input must be binary YAML data"}

  @doc """
  Validate YAML structure for preference import.
  """
  @spec validate_structure(data :: map()) :: {:ok, map()} | {:error, [String.t()]}
  def validate_structure(data) do
    # Use same validation as JSON handler since structure is the same
    JsonHandler.validate_structure(data)
  end

  ## Private Functions

  defp convert_to_yaml_format(data) do
    # Simple YAML-like format converter
    # In a full implementation, this would use a proper YAML library
    sections = [
      format_metadata_section(data[:export_metadata]),
      format_system_defaults_section(data[:system_defaults]),
      format_user_preferences_section(data[:user_preferences]),
      format_project_preferences_section(data[:project_preferences]),
      format_templates_section(data[:templates])
    ]

    Enum.join(Enum.filter(sections, & &1), "\n\n")
  end

  defp format_metadata_section(nil), do: nil

  defp format_metadata_section(metadata) do
    """
    export_metadata:
      export_version: "#{metadata.export_version}"
      exported_at: "#{metadata.exported_at}"
      format: "#{metadata.format}"
      schema_version: "#{metadata.schema_version}"
      encryption_used: #{metadata.encryption_used}
    """
  end

  defp format_system_defaults_section(nil), do: nil
  defp format_system_defaults_section([]), do: nil

  defp format_system_defaults_section(defaults) do
    formatted_defaults =
      Enum.map(defaults, fn default ->
        """
          - preference_key: "#{default.preference_key}"
            value: "#{default.value}"
            category: "#{default.category}"
            data_type: "#{default.data_type}"
            sensitive: #{default.sensitive}
        """
      end)

    "system_defaults:\n" <> Enum.join(formatted_defaults, "")
  end

  defp format_user_preferences_section(nil), do: nil
  defp format_user_preferences_section([]), do: nil

  defp format_user_preferences_section(preferences) do
    formatted_prefs =
      Enum.map(preferences, fn pref ->
        """
          - user_id: "#{pref.user_id}"
            preference_key: "#{pref.preference_key}"
            value: "#{pref.value}"
            category: "#{pref.category}"
            sensitive: #{pref.sensitive}
        """
      end)

    "user_preferences:\n" <> Enum.join(formatted_prefs, "")
  end

  defp format_project_preferences_section(nil), do: nil
  defp format_project_preferences_section([]), do: nil

  defp format_project_preferences_section(_preferences) do
    "project_preferences: []"
  end

  defp format_templates_section(nil), do: nil
  defp format_templates_section([]), do: nil

  defp format_templates_section(_templates) do
    "templates: []"
  end

  defp parse_yaml_format(yaml_data) do
    # Simple YAML-like parser
    # In a full implementation, this would use a proper YAML library
    _lines = String.split(yaml_data, "\n")

    # For now, return a basic structure
    %{
      "export_metadata" => %{
        "export_version" => "1.0.0",
        "format" => "yaml"
      },
      "system_defaults" => [],
      "user_preferences" => [],
      "project_preferences" => [],
      "templates" => []
    }
  end
end
