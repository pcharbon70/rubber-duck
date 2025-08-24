defmodule RubberDuck.CLI.ConfigCommands do
  @moduledoc """
  CLI commands for basic preference configuration management.

  Provides commands for setting, getting, listing, and resetting preferences
  with support for user context and category filtering.
  """

  require Logger

  alias RubberDuck.Preferences.{PreferenceResolver, ValidationInterfaceManager}
  alias RubberDuck.Preferences.Resources.{SystemDefault, UserPreference}

  @doc """
  Set a preference value for a user.
  """
  def set_preference(opts) do
    key = Map.get(opts, :key)
    value = Map.get(opts, :value)
    user_id = Map.get(opts, :user_id, get_current_user_id())

    user_id = ensure_user_id_present(user_id)

    case validate_preference_value(key, value) do
      :ok -> handle_valid_preference(user_id, key, value, opts)
      {:error, validation_error} -> handle_validation_error(key, validation_error)
    end
  end

  defp ensure_user_id_present(user_id) do
    return_if_present(user_id, fn ->
      IO.puts("Error: User ID required. Use --user-id or set RUBBER_DUCK_USER_ID environment variable.")
      System.halt(1)
    end)
  end

  defp return_if_present(nil, error_fn), do: error_fn.()
  defp return_if_present(value, _error_fn), do: value

  defp handle_valid_preference(user_id, key, value, opts) do
    case create_or_update_user_preference(user_id, key, value) do
      {:ok, _preference} -> handle_successful_set(key, value, user_id, opts)
      {:error, reason} -> handle_set_failure(key, reason)
    end
  end

  defp handle_successful_set(key, value, user_id, opts) do
    IO.puts("✅ Set #{key} = #{value}")
    if Map.get(opts, :verbose), do: show_preference_details(key, value, user_id)
  end

  defp handle_set_failure(_key, reason) do
    IO.puts("❌ Failed to set preference: #{reason}")
    System.halt(1)
  end

  defp handle_validation_error(key, validation_error) do
    IO.puts("❌ Invalid value: #{validation_error}")
    suggest_valid_values(key)
    System.halt(1)
  end

  @doc """
  Get a preference value for a user.
  """
  def get_preference(opts) do
    key = Map.get(opts, :key)
    user_id = Map.get(opts, :user_id, get_current_user_id())
    project_id = Map.get(opts, :project_id)
    show_source = Map.get(opts, :source, false)

    if is_nil(user_id) do
      IO.puts(
        "Error: User ID required. Use --user-id or set RUBBER_DUCK_USER_ID environment variable."
      )

      System.halt(1)
    end

    case PreferenceResolver.resolve(user_id, key, project_id) do
      {:ok, value} ->
        if show_source do
          source = determine_preference_source(user_id, key, project_id)
          IO.puts("#{key} = #{value} (source: #{source})")
        else
          IO.puts("#{key} = #{value}")
        end

      {:error, reason} ->
        IO.puts("❌ Failed to get preference: #{reason}")
        suggest_similar_preferences(key)
        System.halt(1)
    end
  end

  @doc """
  List preferences for a user with optional filtering.
  """
  def list_preferences(opts) do
    user_id = Map.get(opts, :user_id, get_current_user_id())
    project_id = Map.get(opts, :project_id)
    category = Map.get(opts, :category)
    format = Map.get(opts, :format, "table")
    verbose = Map.get(opts, :verbose, false)

    if is_nil(user_id) do
      IO.puts(
        "Error: User ID required. Use --user-id or set RUBBER_DUCK_USER_ID environment variable."
      )

      System.halt(1)
    end

    case get_preferences_list(user_id, project_id, category) do
      {:ok, preferences} ->
        display_preferences_list(preferences, format, verbose)

      {:error, reason} ->
        IO.puts("❌ Failed to list preferences: #{reason}")
        System.halt(1)
    end
  end

  @doc """
  Reset a preference to its system default.
  """
  def reset_preference(opts) do
    key = Map.get(opts, :key)
    user_id = Map.get(opts, :user_id, get_current_user_id())

    if is_nil(user_id) do
      IO.puts(
        "Error: User ID required. Use --user-id or set RUBBER_DUCK_USER_ID environment variable."
      )

      System.halt(1)
    end

    case get_system_default_value(key) do
      {:ok, default_value} ->
        case remove_user_preference(user_id, key) do
          :ok ->
            IO.puts("✅ Reset #{key} to default: #{default_value}")

          {:error, reason} ->
            IO.puts("❌ Failed to reset preference: #{reason}")
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts("❌ Failed to get default value: #{reason}")
        System.halt(1)
    end
  end

  # Private helper functions

  defp get_current_user_id do
    System.get_env("RUBBER_DUCK_USER_ID")
  end

  defp validate_preference_value(key, value) do
    # Basic validation - would integrate with ValidationInterfaceManager
    changes = %{key => value}

    case ValidationInterfaceManager.validate_preference_changes(changes) do
      {:ok, validation_result} ->
        if validation_result.valid, do: :ok, else: {:error, "Validation failed"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_or_update_user_preference(user_id, key, value) do
    # Check if preference already exists
    case UserPreference.by_user_and_key(user_id, key) do
      {:ok, [existing]} ->
        UserPreference.update(existing, %{value: value})

      {:ok, []} ->
        attrs = %{
          user_id: user_id,
          preference_key: key,
          value: value,
          category: get_preference_category(key),
          source: :cli
        }

        UserPreference.create(attrs)

      error ->
        error
    end
  end

  defp determine_preference_source(user_id, key, project_id) do
    case UserPreference.by_user_and_key(user_id, key) do
      {:ok, [_user_pref]} -> determine_user_or_project_source(project_id, key)
      {:ok, []} -> "system"
      _ -> "unknown"
    end
  end

  defp determine_user_or_project_source(nil, _key), do: "user"
  defp determine_user_or_project_source(project_id, key) do
    case check_project_override(project_id, key) do
      true -> "project"
      false -> "user"
    end
  end

  defp get_preferences_list(user_id, project_id, category) do
    case get_all_system_defaults() do
      {:ok, system_defaults} ->
        filtered_defaults = filter_defaults_by_category(system_defaults, category)
        preferences = build_preferences_list(user_id, project_id, filtered_defaults)
        {:ok, preferences}

      error -> error
    end
  end

  defp filter_defaults_by_category(system_defaults, nil), do: system_defaults
  defp filter_defaults_by_category(system_defaults, category) do
    Enum.filter(system_defaults, &(&1.category == category))
  end

  defp build_preferences_list(user_id, project_id, defaults) do
    Enum.map(defaults, &build_preference_entry(user_id, project_id, &1))
  end

  defp build_preference_entry(user_id, project_id, default) do
    case PreferenceResolver.resolve(user_id, default.preference_key, project_id) do
      {:ok, value} ->
        build_resolved_preference(user_id, project_id, default, value)

      {:error, _} ->
        build_default_preference(default)
    end
  end

  defp build_resolved_preference(user_id, project_id, default, value) do
    %{
      key: default.preference_key,
      value: value,
      category: default.category,
      description: default.description,
      source: determine_preference_source(user_id, default.preference_key, project_id)
    }
  end

  defp build_default_preference(default) do
    %{
      key: default.preference_key,
      value: default.default_value,
      category: default.category,
      description: default.description,
      source: "system"
    }
  end

  defp display_preferences_list(preferences, format, verbose) do
    case format do
      "json" -> display_preferences_json(preferences)
      "yaml" -> display_preferences_yaml(preferences)
      _ -> display_preferences_table(preferences, verbose)
    end
  end

  defp display_preferences_table(preferences, verbose) do
    if verbose do
      IO.puts(
        "\n" <>
          String.pad_trailing("KEY", 40) <>
          " | " <>
          String.pad_trailing("VALUE", 20) <>
          " | " <>
          String.pad_trailing("CATEGORY", 15) <>
          " | " <> String.pad_trailing("SOURCE", 10) <> " | DESCRIPTION"
      )

      IO.puts(String.duplicate("-", 120))

      Enum.each(preferences, fn pref ->
        key = String.pad_trailing(pref.key, 40)
        value = String.pad_trailing(truncate_string(pref.value, 20), 20)
        category = String.pad_trailing(pref.category, 15)
        source = String.pad_trailing(pref.source, 10)
        description = truncate_string(pref.description, 40)

        IO.puts("#{key} | #{value} | #{category} | #{source} | #{description}")
      end)
    else
      IO.puts(
        "\n" <>
          String.pad_trailing("KEY", 50) <>
          " | " <> String.pad_trailing("VALUE", 30) <> " | CATEGORY"
      )

      IO.puts(String.duplicate("-", 90))

      Enum.each(preferences, fn pref ->
        key = String.pad_trailing(pref.key, 50)
        value = String.pad_trailing(truncate_string(pref.value, 30), 30)
        category = pref.category

        IO.puts("#{key} | #{value} | #{category}")
      end)
    end

    IO.puts("\nTotal: #{length(preferences)} preferences")
  end

  defp display_preferences_json(preferences) do
    json_output = Jason.encode!(preferences, pretty: true)
    IO.puts(json_output)
  end

  defp display_preferences_yaml(preferences) do
    # Convert to YAML format (simplified)
    Enum.each(preferences, fn pref ->
      IO.puts("#{pref.key}: \"#{pref.value}\"")
    end)
  end

  defp get_system_default_value(key) do
    case SystemDefault.by_preference_key(key) do
      {:ok, [default]} -> {:ok, default.default_value}
      {:ok, []} -> {:error, "Unknown preference key"}
      error -> error
    end
  end

  defp remove_user_preference(user_id, key) do
    case UserPreference.by_user_and_key(user_id, key) do
      {:ok, [user_pref]} ->
        case UserPreference.destroy(user_pref) do
          :ok -> :ok
          error -> error
        end

      {:ok, []} ->
        :ok

      error ->
        error
    end
  end

  defp show_preference_details(key, _value, _user_id) do
    case get_preference_metadata(key) do
      {:ok, metadata} ->
        IO.puts("  Category: #{metadata.category}")
        IO.puts("  Description: #{metadata.description}")
        IO.puts("  Data Type: #{metadata.data_type}")
        if metadata.constraints, do: IO.puts("  Constraints: #{inspect(metadata.constraints)}")

      {:error, _} ->
        IO.puts("  (No additional details available)")
    end
  end

  defp suggest_valid_values(key) do
    case get_preference_metadata(key) do
      {:ok, metadata} -> show_constraint_help(metadata.constraints)
      {:error, _} -> show_generic_help()
    end
  end

  defp show_constraint_help(nil), do: show_generic_help()
  defp show_constraint_help(constraints) do
    case constraints do
      %{allowed_values: values} when is_list(values) ->
        IO.puts("Valid values: #{Enum.join(values, ", ")}")

      %{min: min_val, max: max_val} ->
        IO.puts("Valid range: #{min_val} to #{max_val}")

      _ ->
        show_generic_help()
    end
  end

  defp show_generic_help do
    IO.puts("Check preference documentation for valid values.")
  end

  defp suggest_similar_preferences(key) do
    case get_all_system_defaults() do
      {:ok, defaults} -> show_similar_keys(defaults, key)
      {:error, _} -> :ok
    end
  end

  defp show_similar_keys(defaults, key) do
    similar = find_similar_keys(defaults, key)

    unless Enum.empty?(similar) do
      IO.puts("Did you mean one of these?")
      Enum.each(similar, &IO.puts("  #{&1}"))
    end
  end

  defp find_similar_keys(defaults, key) do
    key_prefix = String.split(key, ".") |> hd()

    defaults
    |> Enum.map(& &1.preference_key)
    |> Enum.filter(&String.contains?(&1, key_prefix))
    |> Enum.take(5)
  end

  defp get_preference_metadata(key) do
    case SystemDefault.by_preference_key(key) do
      {:ok, [default]} -> {:ok, default}
      error -> error
    end
  end

  defp get_all_system_defaults do
    SystemDefault.read()
  end

  defp check_project_override(_project_id, _key) do
    # Placeholder for project override checking
    false
  end

  defp get_preference_category(key) do
    key |> String.split(".") |> hd()
  end

  defp truncate_string(str, length) do
    if String.length(str) > length do
      String.slice(str, 0, length - 3) <> "..."
    else
      str
    end
  end
end
