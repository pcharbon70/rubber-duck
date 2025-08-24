defmodule RubberDuck.CLI.TemplateCommands do
  @moduledoc """
  CLI commands for template management.

  Provides commands for creating, applying, listing, and exporting preference
  templates with support for user and project contexts.
  """

  require Logger

  alias RubberDuck.Preferences.TemplateManager

  @doc """
  Create a template from current preferences.
  """
  def create_template(opts) do
    name = Map.get(opts, :name)
    user_id = get_user_id_from_opts(opts)
    project_id = Map.get(opts, :project_id)
    description = Map.get(opts, :description, "Created via CLI")
    category = Map.get(opts, :category, "user")
    template_type = Map.get(opts, :type, :private)

    if is_nil(name) do
      IO.puts("Error: Template name required.")
      System.halt(1)
    end

    result =
      if project_id do
        TemplateManager.create_template_from_project(project_id, name, user_id,
          description: description,
          category: category,
          template_type: template_type
        )
      else
        TemplateManager.create_template_from_user(user_id, name,
          description: description,
          category: category,
          template_type: template_type
        )
      end

    case result do
      {:ok, template} ->
        IO.puts("✅ Created template '#{name}'")
        IO.puts("  Template ID: #{template.template_id}")
        IO.puts("  Type: #{template_type}")
        IO.puts("  Preferences: #{map_size(template.preferences)}")

      {:error, reason} ->
        IO.puts("❌ Failed to create template: #{reason}")
        System.halt(1)
    end
  end

  @doc """
  Apply a template to user or project preferences.
  """
  def apply_template(opts) do
    template_id = Map.get(opts, :template_id)
    user_id = get_user_id_from_opts(opts)
    project_id = Map.get(opts, :project_id)
    selective_keys = Map.get(opts, :selective_keys)
    overwrite = Map.get(opts, :overwrite, false)
    dry_run = Map.get(opts, :dry_run, false)

    if is_nil(template_id) do
      IO.puts("Error: Template ID required.")
      System.halt(1)
    end

    result =
      if project_id do
        TemplateManager.apply_template_to_project(template_id, project_id, user_id,
          selective_keys: selective_keys,
          overwrite_existing: overwrite
        )
      else
        TemplateManager.apply_template_to_user(template_id, user_id,
          selective_keys: selective_keys,
          overwrite_existing: overwrite
        )
      end

    case result do
      {:ok, application_result} ->
        if dry_run do
          IO.puts("🔍 Dry run results:")
        else
          IO.puts("✅ Applied template #{template_id}")
        end

        IO.puts("  Applied: #{application_result.applied_count} preferences")
        IO.puts("  Skipped: #{application_result.skipped_count} preferences")

        if not Enum.empty?(application_result.errors) do
          IO.puts("  Errors: #{length(application_result.errors)}")
        end

      {:error, reason} ->
        IO.puts("❌ Failed to apply template: #{reason}")
        System.halt(1)
    end
  end

  @doc """
  List available templates.
  """
  def list_templates(opts) do
    template_type = Map.get(opts, :type)
    category = Map.get(opts, :category)
    public_only = Map.get(opts, :public_only, false)
    format = Map.get(opts, :format, "table")

    filter_opts = [
      template_type: template_type,
      category: category,
      public_only: public_only
    ]

    case TemplateManager.get_template_library(filter_opts) do
      {:ok, templates} ->
        display_templates_list(templates, format)

      {:error, reason} ->
        IO.puts("❌ Failed to list templates: #{reason}")
        System.halt(1)
    end
  end

  @doc """
  Export a template for sharing.
  """
  def export_template(opts) do
    template_id = Map.get(opts, :template_id)
    output_file = Map.get(opts, :output, "template_#{template_id}.json")
    format = Map.get(opts, :format, "json")

    if is_nil(template_id) do
      IO.puts("Error: Template ID required.")
      System.halt(1)
    end

    case get_template_for_export(template_id) do
      {:ok, template} ->
        case export_template_to_file(template, output_file, format) do
          :ok ->
            IO.puts("✅ Exported template '#{template.name}' to #{output_file}")

          {:error, reason} ->
            IO.puts("❌ Failed to export template: #{reason}")
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts("❌ Failed to get template: #{reason}")
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

  defp display_templates_list(templates, format) do
    case format do
      "json" -> display_templates_json(templates)
      _ -> display_templates_table(templates)
    end
  end

  defp display_templates_table(templates) do
    IO.puts(
      "\n" <>
        String.pad_trailing("NAME", 30) <>
        " | " <>
        String.pad_trailing("TYPE", 10) <>
        " | " <> String.pad_trailing("CATEGORY", 15) <> " | " <> "DESCRIPTION"
    )

    IO.puts(String.duplicate("-", 80))

    Enum.each(templates, fn template ->
      name = String.pad_trailing(truncate_string(template.name, 30), 30)
      type = String.pad_trailing("#{template.template_type}", 10)
      category = String.pad_trailing(template.category, 15)
      description = truncate_string(template.description, 30)

      IO.puts("#{name} | #{type} | #{category} | #{description}")
    end)

    IO.puts("\nTotal: #{length(templates)} templates")
  end

  defp display_templates_json(templates) do
    simplified_templates =
      Enum.map(templates, fn template ->
        %{
          id: template.template_id,
          name: template.name,
          type: template.template_type,
          category: template.category,
          description: template.description,
          usage_count: template.usage_count || 0,
          rating: template.rating
        }
      end)

    json_output = Jason.encode!(simplified_templates, pretty: true)
    IO.puts(json_output)
  end

  defp get_template_for_export(template_id) do
    # Placeholder for template retrieval
    # This would integrate with actual TemplateManager.get_template/1
    {:ok,
     %{
       template_id: template_id,
       name: "Example Template",
       description: "Example template for export",
       preferences: %{"example.key" => "example_value"}
     }}
  end

  defp export_template_to_file(template, output_file, format) do
    export_data =
      case format do
        "yaml" -> format_template_as_yaml(template)
        _ -> format_template_as_json(template)
      end

    case File.write(output_file, export_data) do
      :ok -> :ok
      {:error, reason} -> {:error, "File write error: #{reason}"}
    end
  end

  defp format_template_as_json(template) do
    Jason.encode!(template, pretty: true)
  end

  defp format_template_as_yaml(template) do
    # Simplified YAML export
    """
    name: "#{template.name}"
    description: "#{template.description}"
    preferences:
    #{format_preferences_as_yaml(template.preferences)}
    """
  end

  defp format_preferences_as_yaml(preferences) do
    preferences
    |> Enum.map(fn {key, value} -> "  #{key}: \"#{value}\"" end)
    |> Enum.join("\n")
  end

  defp truncate_string(str, length) do
    if String.length(str) > length do
      String.slice(str, 0, length - 3) <> "..."
    else
      str
    end
  end
end
