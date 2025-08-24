defmodule RubberDuck.CLI do
  @moduledoc """
  Main CLI interface for RubberDuck preference management.

  Provides a comprehensive command-line interface for managing user preferences,
  project configurations, templates, and system administration. Follows modern
  CLI design patterns with progressive discovery and intelligent context awareness.
  """

  alias RubberDuck.CLI.{ConfigCommands, ProjectCommands, TemplateCommands, UtilityCommands}

  @doc """
  Main CLI entry point.
  """
  def main(args) do
    args
    |> parse_args()
    |> execute_command()
  end

  @doc """
  Parse command line arguments into structured commands.
  """
  def parse_args(args) do
    case args do
      ["config" | rest] -> parse_config_command(rest)
      ["help" | _] -> {:help, :general}
      ["--help" | _] -> {:help, :general}
      ["-h" | _] -> {:help, :general}
      [] -> {:help, :general}
      [unknown | _] -> {:error, "Unknown command: #{unknown}"}
    end
  end

  @doc """
  Execute parsed CLI command.
  """
  def execute_command(command) do
    case command do
      {:help, :general} -> show_general_help()
      {:help, subcommand} -> show_command_help(subcommand)
      {:config, action, opts} -> execute_config_command(action, opts)
      {:error, message} -> show_error_and_help(message)
    end
  end

  # Private helper functions

  defp parse_config_command([]) do
    {:help, :config}
  end

  defp parse_config_command([command | rest]) do
    case get_command_parser(command) do
      {parser_func, command_atom} -> apply(__MODULE__, parser_func, [command_atom, rest])
      :help -> parse_help_command(rest)
      :unknown -> {:error, "Unknown config command: #{command}"}
    end
  end

  defp get_command_parser(command) do
    command_map = %{
      "set" => {:parse_basic_command, :set},
      "get" => {:parse_basic_command, :get},
      "list" => {:parse_basic_command, :list},
      "reset" => {:parse_basic_command, :reset},
      "enable-project" => {:parse_project_command, :enable_project},
      "project-set" => {:parse_project_command, :project_set},
      "project-diff" => {:parse_project_command, :project_diff},
      "project-reset" => {:parse_project_command, :project_reset},
      "template-create" => {:parse_template_command, :template_create},
      "template-apply" => {:parse_template_command, :template_apply},
      "template-list" => {:parse_template_command, :template_list},
      "template-export" => {:parse_template_command, :template_export},
      "validate" => {:parse_utility_command, :validate},
      "migrate" => {:parse_utility_command, :migrate},
      "backup" => {:parse_utility_command, :backup},
      "restore" => {:parse_utility_command, :restore},
      "help" => :help
    }

    Map.get(command_map, command, :unknown)
  end

  # Parser functions for command-specific logic
  defp parse_basic_command(:set, [key, value | opts]) do
    {:config, :set, %{key: key, value: value, opts: parse_options(opts)}}
  end

  defp parse_basic_command(:get, [key | opts]) do
    {:config, :get, %{key: key, opts: parse_options(opts)}}
  end

  defp parse_basic_command(:list, opts) do
    {:config, :list, %{opts: parse_options(opts)}}
  end

  defp parse_basic_command(:reset, [key | opts]) do
    {:config, :reset, %{key: key, opts: parse_options(opts)}}
  end

  defp parse_basic_command(command, _args) do
    {:error, "Invalid arguments for #{command} command"}
  end

  defp parse_help_command([subcommand]) do
    {:help, String.to_atom(subcommand)}
  end

  defp parse_help_command([]) do
    {:help, :config}
  end

  defp parse_help_command(_args) do
    {:help, :config}
  end

  defp parse_options(opts) do
    opts
    |> Enum.chunk_every(2)
    |> Enum.reduce(%{}, fn
      ["--" <> key, value], acc ->
        Map.put(acc, String.to_atom(key), value)

      ["-" <> key, value], acc ->
        Map.put(acc, parse_short_flag(key), value)

      [flag], acc ->
        cond do
          String.starts_with?(flag, "--") ->
            Map.put(acc, String.to_atom(String.slice(flag, 2..-1//1)), true)

          String.starts_with?(flag, "-") ->
            Map.put(acc, parse_short_flag(String.slice(flag, 1..-1//1)), true)

          true ->
            acc
        end

      _, acc ->
        acc
    end)
  end

  defp parse_short_flag("u"), do: :user_id
  defp parse_short_flag("p"), do: :project_id
  defp parse_short_flag("c"), do: :category
  defp parse_short_flag("v"), do: :verbose
  defp parse_short_flag("h"), do: :help
  defp parse_short_flag(flag), do: String.to_atom(flag)

  defp execute_config_command(action, opts) do
    case action do
      action when action in [:set, :get, :list, :reset] ->
        execute_basic_command(action, opts)

      action when action in [:enable_project, :project_set, :project_diff, :project_reset] ->
        execute_project_command(action, opts)

      action
      when action in [:template_create, :template_apply, :template_list, :template_export] ->
        execute_template_command(action, opts)

      action when action in [:validate, :migrate, :backup, :restore] ->
        execute_utility_command(action, opts)

      _ ->
        show_error_and_help("Unknown command: #{action}")
    end
  end

  defp execute_basic_command(:set, opts), do: ConfigCommands.set_preference(opts)
  defp execute_basic_command(:get, opts), do: ConfigCommands.get_preference(opts)

  defp execute_basic_command(:list, opts),
    do: ConfigCommands.list_preferences(opts)

  defp execute_basic_command(:reset, opts),
    do: ConfigCommands.reset_preference(opts)

  defp execute_project_command(:enable_project, opts),
    do: ProjectCommands.enable_project(opts)

  defp execute_project_command(:project_set, opts),
    do: ProjectCommands.set_project_preference(opts)

  defp execute_project_command(:project_diff, opts),
    do: ProjectCommands.show_project_diff(opts)

  defp execute_project_command(:project_reset, opts),
    do: ProjectCommands.reset_project(opts)

  defp execute_template_command(:template_create, opts),
    do: TemplateCommands.create_template(opts)

  defp execute_template_command(:template_apply, opts),
    do: TemplateCommands.apply_template(opts)

  defp execute_template_command(:template_list, opts),
    do: TemplateCommands.list_templates(opts)

  defp execute_template_command(:template_export, opts),
    do: TemplateCommands.export_template(opts)

  defp execute_utility_command(:validate, opts),
    do: UtilityCommands.validate_config(opts)

  defp execute_utility_command(:migrate, opts),
    do: UtilityCommands.migrate_config(opts)

  defp execute_utility_command(:backup, opts),
    do: UtilityCommands.backup_config(opts)

  defp execute_utility_command(:restore, opts),
    do: UtilityCommands.restore_config(opts)

  defp show_general_help do
    IO.puts("""
    RubberDuck Configuration Management

    USAGE:
        rubber_duck config [COMMAND] [OPTIONS]

    COMMANDS:
        Basic Configuration:
          set <key> <value>     Set a preference value
          get <key>             Get a preference value  
          list                  List all preferences
          reset <key>           Reset preference to default

        Project Management:
          enable-project <id>   Enable project preference overrides
          project-set <id> <key> <value>  Set project preference
          project-diff <id>     Show project vs user preferences
          project-reset <id>    Reset project to user defaults

        Templates:
          template-create <name>  Create template from current preferences
          template-apply <id>     Apply template to preferences
          template-list           List available templates
          template-export <id>    Export template for sharing

        Utilities:
          validate              Validate current configuration
          migrate               Migrate preferences to latest schema
          backup                Create configuration backup
          restore <backup_id>   Restore from backup

    OPTIONS:
        -u, --user-id <id>     Target user ID
        -p, --project-id <id>  Target project ID
        -c, --category <cat>   Filter by category
        -v, --verbose          Verbose output
        -h, --help             Show help

    For more information on a specific command:
        rubber_duck config help <command>
    """)
  end

  defp show_command_help(subcommand) do
    case subcommand do
      :set -> show_set_help()
      :get -> show_get_help()
      :list -> show_list_help()
      :template_create -> show_template_create_help()
      _ -> IO.puts("Help not available for #{subcommand}")
    end
  end

  defp show_set_help do
    IO.puts("""
    Set a preference value

    USAGE:
        rubber_duck config set <key> <value> [OPTIONS]

    EXAMPLES:
        rubber_duck config set code_quality.global.enabled true
        rubber_duck config set ml.training.learning_rate 0.001 --user-id user123
        rubber_duck config set llm.providers.primary openai --project-id proj456

    OPTIONS:
        -u, --user-id <id>     Set for specific user
        -p, --project-id <id>  Set as project override
        --reason <text>        Reason for change (required for project overrides)
    """)
  end

  defp show_get_help do
    IO.puts("""
    Get a preference value

    USAGE:
        rubber_duck config get <key> [OPTIONS]

    EXAMPLES:
        rubber_duck config get code_quality.global.enabled
        rubber_duck config get ml.training.learning_rate --user-id user123

    OPTIONS:
        -u, --user-id <id>     Get for specific user
        -p, --project-id <id>  Get resolved value for project context
        --source               Show preference source (system/user/project)
    """)
  end

  defp show_list_help do
    IO.puts("""
    List preferences

    USAGE:
        rubber_duck config list [OPTIONS]

    EXAMPLES:
        rubber_duck config list
        rubber_duck config list --category ml
        rubber_duck config list --user-id user123 --verbose

    OPTIONS:
        -c, --category <cat>   Filter by category (llm, ml, code_quality, budgeting)
        -u, --user-id <id>     List for specific user
        -p, --project-id <id>  Include project overrides
        -v, --verbose          Show detailed information
        --format <format>      Output format (table, json, yaml)
    """)
  end

  defp show_template_create_help do
    IO.puts("""
    Create a template from current preferences

    USAGE:
        rubber_duck config template-create <name> [OPTIONS]

    EXAMPLES:
        rubber_duck config template-create "My Development Setup"
        ruby_duck config template-create "Team Standards" --project-id proj123
        rubber_duck config template-create "ML Config" --category ml

    OPTIONS:
        -u, --user-id <id>     Create from user preferences
        -p, --project-id <id>  Create from project preferences
        -c, --category <cat>   Include only specific category
        --description <text>   Template description
        --type <type>          Template type (private, team, public)
    """)
  end

  defp show_error_and_help(message) do
    IO.puts("Error: #{message}\n")
    show_general_help()
  end
end
