defmodule RubberDuck.Preferences.TemplateManager do
  @moduledoc """
  Template management for preference templates and application.

  Provides business logic for creating, managing, and applying preference
  templates. Handles template creation from existing preferences, template
  library management, application workflows, and template maintenance.
  """

  require Logger

  alias RubberDuck.Preferences.Resources.{
    PreferenceTemplate,
    ProjectPreference,
    UserPreference
  }

  alias RubberDuck.Preferences.ProjectPreferenceManager

  @predefined_templates [
    %{
      name: "Conservative",
      description: "Safe, minimal settings optimized for stability and reliability",
      category: "system",
      template_type: :system,
      preferences: %{
        "code_quality.global.enabled" => "true",
        "code_quality.refactoring.mode" => "conservative",
        "code_quality.refactoring.auto_apply_enabled" => "false",
        "ml.global.enabled" => "false",
        "budgeting.enforcement.enabled" => "true",
        "budgeting.enforcement.mode" => "hard_stop"
      }
    },
    %{
      name: "Balanced",
      description: "Balanced settings providing good functionality with reasonable safety",
      category: "system",
      template_type: :system,
      preferences: %{
        "code_quality.global.enabled" => "true",
        "code_quality.refactoring.mode" => "moderate",
        "code_quality.refactoring.auto_apply_enabled" => "false",
        "ml.global.enabled" => "true",
        "ml.features.advanced_enabled" => "false",
        "budgeting.enforcement.enabled" => "true",
        "budgeting.enforcement.mode" => "soft_warning"
      }
    },
    %{
      name: "Aggressive",
      description: "Advanced settings with full automation and cutting-edge features",
      category: "system",
      template_type: :system,
      preferences: %{
        "code_quality.global.enabled" => "true",
        "code_quality.refactoring.mode" => "aggressive",
        "code_quality.refactoring.auto_apply_enabled" => "true",
        "ml.global.enabled" => "true",
        "ml.features.advanced_enabled" => "true",
        "ml.features.auto_optimization" => "true",
        "budgeting.enforcement.enabled" => "false"
      }
    }
  ]

  @doc """
  Create a template from existing user preferences.
  """
  @spec create_template_from_user(
          user_id :: binary(),
          template_name :: String.t(),
          opts :: keyword()
        ) :: {:ok, PreferenceTemplate.t()} | {:error, term()}
  def create_template_from_user(user_id, template_name, opts \\ []) do
    description = Keyword.get(opts, :description, "User-created preference template")
    category = Keyword.get(opts, :category, "user")
    template_type = Keyword.get(opts, :template_type, :private)
    tags = Keyword.get(opts, :tags, [])

    with {:ok, user_preferences} <- get_user_preferences(user_id),
         preferences_map <- convert_preferences_to_map(user_preferences) do
      template_attrs = %{
        name: template_name,
        description: description,
        category: category,
        preferences: preferences_map,
        template_type: template_type,
        created_by: user_id,
        tags: tags
      }

      case PreferenceTemplate.create(template_attrs) do
        {:ok, template} ->
          Logger.info("Created template '#{template_name}' from user #{user_id} preferences")
          {:ok, template}

        error ->
          Logger.warning("Failed to create template from user preferences: #{inspect(error)}")
          error
      end
    else
      error -> error
    end
  end

  @doc """
  Create a template from existing project preferences.
  """
  @spec create_template_from_project(
          project_id :: binary(),
          template_name :: String.t(),
          created_by_user_id :: binary(),
          opts :: keyword()
        ) :: {:ok, PreferenceTemplate.t()} | {:error, term()}
  def create_template_from_project(project_id, template_name, created_by_user_id, opts \\ []) do
    description = Keyword.get(opts, :description, "Project-based preference template")
    category = Keyword.get(opts, :category, "project")
    template_type = Keyword.get(opts, :template_type, :team)
    tags = Keyword.get(opts, :tags, [])

    with {:ok, project_preferences} <- get_project_preferences(project_id),
         preferences_map <- convert_preferences_to_map(project_preferences) do
      template_attrs = %{
        name: template_name,
        description: description,
        category: category,
        preferences: preferences_map,
        template_type: template_type,
        created_by: created_by_user_id,
        tags: tags
      }

      case PreferenceTemplate.create(template_attrs) do
        {:ok, template} ->
          Logger.info(
            "Created template '#{template_name}' from project #{project_id} preferences"
          )

          {:ok, template}

        error ->
          Logger.warning("Failed to create template from project preferences: #{inspect(error)}")
          error
      end
    else
      error -> error
    end
  end

  @doc """
  Apply template to user preferences.
  """
  @spec apply_template_to_user(
          template_id :: binary(),
          user_id :: binary(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def apply_template_to_user(template_id, user_id, opts \\ []) do
    selective_keys = Keyword.get(opts, :selective_keys, nil)
    overwrite_existing = Keyword.get(opts, :overwrite_existing, false)

    with {:ok, template} <- get_template(template_id),
         preferences_to_apply <-
           select_preferences_to_apply(template.preferences, selective_keys),
         {:ok, results} <-
           apply_preferences_to_user(user_id, preferences_to_apply, overwrite_existing) do
      update_template_usage(template_id)

      Logger.info("Applied template '#{template.name}' to user #{user_id}")
      {:ok, %{applied_count: length(results), skipped_count: 0, errors: []}}
    else
      error ->
        Logger.warning("Failed to apply template to user: #{inspect(error)}")
        error
    end
  end

  @doc """
  Apply template to project preferences.
  """
  @spec apply_template_to_project(
          template_id :: binary(),
          project_id :: binary(),
          applied_by_user_id :: binary(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def apply_template_to_project(template_id, project_id, applied_by_user_id, opts \\ []) do
    selective_keys = Keyword.get(opts, :selective_keys, nil)
    overwrite_existing = Keyword.get(opts, :overwrite_existing, false)
    reason = Keyword.get(opts, :reason, "Applied from template")

    with {:ok, template} <- get_template(template_id),
         :ok <- ensure_project_preferences_enabled(project_id),
         preferences_to_apply <-
           select_preferences_to_apply(template.preferences, selective_keys),
         {:ok, results} <-
           apply_preferences_to_project(
             project_id,
             preferences_to_apply,
             applied_by_user_id,
             reason,
             overwrite_existing
           ) do
      update_template_usage(template_id)

      Logger.info("Applied template '#{template.name}' to project #{project_id}")
      {:ok, %{applied_count: length(results), skipped_count: 0, errors: []}}
    else
      error ->
        Logger.warning("Failed to apply template to project: #{inspect(error)}")
        error
    end
  end

  @doc """
  Get template library with filtering options.
  """
  @spec get_template_library(opts :: keyword()) ::
          {:ok, list(PreferenceTemplate.t())} | {:error, term()}
  def get_template_library(opts \\ []) do
    template_type = Keyword.get(opts, :template_type, nil)
    category = Keyword.get(opts, :category, nil)
    public_only = Keyword.get(opts, :public_only, false)

    query_opts = build_query_opts(template_type, category)

    case get_templates_by_scope(public_only) do
      {:ok, templates} ->
        case filter_templates(templates, query_opts) do
          {:ok, filtered_templates} -> {:ok, sort_templates_by_popularity(filtered_templates)}
          error -> error
        end

      error ->
        error
    end
  end

  defp build_query_opts(template_type, category) do
    []
    |> add_query_opt(:template_type, template_type)
    |> add_query_opt(:category, category)
  end

  defp add_query_opt(opts, _key, nil), do: opts
  defp add_query_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp get_templates_by_scope(public_only) do
    if public_only do
      PreferenceTemplate.public_templates()
    else
      PreferenceTemplate.read()
    end
  end

  @doc """
  Search templates by name, description, or tags.
  """
  @spec search_templates(search_term :: String.t()) ::
          {:ok, list(PreferenceTemplate.t())} | {:error, term()}
  def search_templates(search_term) do
    case PreferenceTemplate.search_templates(search_term) do
      {:ok, templates} -> {:ok, sort_templates_by_relevance(templates, search_term)}
      error -> error
    end
  end

  @doc """
  Get template recommendations for a user based on their current preferences.
  """
  @spec get_template_recommendations(user_id :: binary()) :: {:ok, list(map())} | {:error, term()}
  def get_template_recommendations(user_id) do
    with {:ok, user_preferences} <- get_user_preferences(user_id),
         {:ok, available_templates} <- get_template_library(public_only: true) do
      recommendations = calculate_template_recommendations(user_preferences, available_templates)
      {:ok, recommendations}
    else
      error -> error
    end
  end

  @doc """
  Update template with new preferences or metadata.
  """
  @spec update_template(
          template_id :: binary(),
          updates :: map(),
          updated_by_user_id :: binary()
        ) :: {:ok, PreferenceTemplate.t()} | {:error, term()}
  def update_template(template_id, updates, updated_by_user_id) do
    with {:ok, template} <- get_template(template_id),
         :ok <- validate_template_update_permission(template, updated_by_user_id) do
      update_attrs = Map.merge(updates, %{version: template.version + 1})

      case PreferenceTemplate.update(template, update_attrs) do
        {:ok, updated_template} ->
          Logger.info("Updated template '#{template.name}' by user #{updated_by_user_id}")
          {:ok, updated_template}

        error ->
          Logger.warning("Failed to update template: #{inspect(error)}")
          error
      end
    else
      error -> error
    end
  end

  @doc """
  Create predefined system templates.
  """
  @spec create_predefined_templates() :: :ok | {:error, term()}
  def create_predefined_templates do
    Enum.each(@predefined_templates, fn template_def ->
      case create_system_template(template_def) do
        {:ok, _template} ->
          Logger.info("Created predefined template: #{template_def.name}")

        {:error, error} ->
          Logger.warning(
            "Failed to create predefined template #{template_def.name}: #{inspect(error)}"
          )
      end
    end)

    :ok
  end

  # Private helper functions

  defp get_template(_template_id) do
    # Placeholder for template lookup
    {:ok, %{name: "Example", preferences: %{}}}
  end

  defp get_user_preferences(user_id) do
    case UserPreference.by_user(user_id) do
      {:ok, preferences} -> {:ok, preferences}
      error -> error
    end
  end

  defp get_project_preferences(project_id) do
    case ProjectPreference.by_project(project_id) do
      {:ok, preferences} -> {:ok, preferences}
      error -> error
    end
  end

  defp convert_preferences_to_map(preferences) do
    Map.new(preferences, &{&1.preference_key, &1.value})
  end

  defp select_preferences_to_apply(template_preferences, selective_keys) do
    if selective_keys do
      Map.take(template_preferences, selective_keys)
    else
      template_preferences
    end
  end

  defp apply_preferences_to_user(user_id, preferences_map, overwrite_existing) do
    results =
      Enum.map(preferences_map, fn {key, value} ->
        apply_single_user_preference(user_id, key, value, overwrite_existing)
      end)

    {:ok, results}
  end

  defp apply_preferences_to_project(
         project_id,
         preferences_map,
         applied_by_user_id,
         reason,
         overwrite_existing
       ) do
    results =
      Enum.map(preferences_map, fn {key, value} ->
        apply_single_project_preference(
          project_id,
          key,
          value,
          applied_by_user_id,
          reason,
          overwrite_existing
        )
      end)

    {:ok, results}
  end

  defp apply_single_user_preference(user_id, preference_key, value, overwrite_existing) do
    # Placeholder for user preference lookup
    case {:ok, []} do
      {:ok, [_existing]} when not overwrite_existing ->
        {:skipped, preference_key, "Preference already exists"}

      {:ok, [existing]} ->
        case UserPreference.update(existing, %{value: value}) do
          {:ok, updated} -> {:updated, preference_key, updated}
          error -> {:error, preference_key, error}
        end

      {:ok, []} ->
        attrs = %{
          user_id: user_id,
          preference_key: preference_key,
          value: value,
          source: :template
        }

        case UserPreference.create(attrs) do
          {:ok, created} -> {:created, preference_key, created}
          error -> {:error, preference_key, error}
        end

      error ->
        {:error, preference_key, error}
    end
  end

  defp apply_single_project_preference(
         project_id,
         preference_key,
         value,
         applied_by_user_id,
         reason,
         overwrite_existing
       ) do
    # Placeholder for project preference lookup
    case {:ok, []} do
      {:ok, [_existing]} when not overwrite_existing ->
        {:skipped, preference_key, "Project preference already exists"}

      {:ok, [existing]} ->
        case ProjectPreferenceManager.update_project_override(existing.id, value, reason: reason) do
          {:ok, updated} -> {:updated, preference_key, updated}
          error -> {:error, preference_key, error}
        end

      {:ok, []} ->
        case ProjectPreferenceManager.create_project_override(project_id, preference_key, value,
               reason: reason,
               approved_by: applied_by_user_id
             ) do
          {:ok, created} -> {:created, preference_key, created}
          error -> {:error, preference_key, error}
        end

      error ->
        {:error, preference_key, error}
    end
  end

  defp ensure_project_preferences_enabled(project_id) do
    if ProjectPreferenceManager.project_preferences_enabled?(project_id) do
      :ok
    else
      {:error, "Project preferences must be enabled before applying templates"}
    end
  end

  defp filter_templates(templates, []), do: {:ok, templates}

  defp filter_templates(templates, filters) do
    filtered = Enum.filter(templates, &template_matches_filters?(&1, filters))
    {:ok, filtered}
  end

  defp template_matches_filters?(template, filters) do
    Enum.all?(filters, &filter_matches_template?(&1, template))
  end

  defp filter_matches_template?({key, value}, template) do
    case key do
      :template_type -> template.template_type == value
      :category -> template.category == value
      _ -> true
    end
  end

  defp sort_templates_by_popularity(templates) do
    Enum.sort_by(templates, &{&1.usage_count, &1.rating || 0.0}, :desc)
  end

  defp sort_templates_by_relevance(templates, search_term) do
    scored_templates =
      Enum.map(templates, fn template ->
        relevance_score = calculate_relevance_score(template, search_term)
        {template, relevance_score}
      end)

    scored_templates
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.map(&elem(&1, 0))
  end

  defp calculate_relevance_score(template, search_term) do
    name_score =
      if String.contains?(String.downcase(template.name), String.downcase(search_term)),
        do: 10,
        else: 0

    desc_score =
      if String.contains?(String.downcase(template.description), String.downcase(search_term)),
        do: 5,
        else: 0

    tag_score =
      if Enum.any?(
           template.tags,
           &String.contains?(String.downcase(&1), String.downcase(search_term))
         ),
         do: 3,
         else: 0

    name_score + desc_score + tag_score
  end

  defp calculate_template_recommendations(user_preferences, available_templates) do
    user_pref_map = convert_preferences_to_map(user_preferences)

    Enum.map(available_templates, fn template ->
      similarity_score = calculate_similarity_score(user_pref_map, template.preferences)
      missing_prefs = calculate_missing_preferences(user_pref_map, template.preferences)
      conflicting_prefs = calculate_conflicting_preferences(user_pref_map, template.preferences)

      %{
        template: template,
        similarity_score: similarity_score,
        missing_preferences: missing_prefs,
        conflicting_preferences: conflicting_prefs,
        recommendation_reason:
          generate_recommendation_reason(similarity_score, missing_prefs, conflicting_prefs)
      }
    end)
    |> Enum.filter(&(&1.similarity_score > 0.3))
    |> Enum.sort_by(& &1.similarity_score, :desc)
    |> Enum.take(5)
  end

  defp calculate_similarity_score(user_prefs, template_prefs) do
    common_keys =
      MapSet.intersection(MapSet.new(Map.keys(user_prefs)), MapSet.new(Map.keys(template_prefs)))

    if MapSet.size(common_keys) == 0 do
      0.0
    else
      matching_values =
        common_keys
        |> Enum.count(fn key ->
          Map.get(user_prefs, key) == Map.get(template_prefs, key)
        end)

      matching_values / MapSet.size(common_keys)
    end
  end

  defp calculate_missing_preferences(user_prefs, template_prefs) do
    template_keys = MapSet.new(Map.keys(template_prefs))
    user_keys = MapSet.new(Map.keys(user_prefs))

    template_keys
    |> MapSet.difference(user_keys)
    |> MapSet.to_list()
  end

  defp calculate_conflicting_preferences(user_prefs, template_prefs) do
    Enum.reduce(template_prefs, [], fn {key, template_value}, acc ->
      case Map.get(user_prefs, key) do
        ^template_value ->
          acc

        user_value when not is_nil(user_value) ->
          [{key, %{user: user_value, template: template_value}} | acc]

        _ ->
          acc
      end
    end)
  end

  defp generate_recommendation_reason(similarity_score, missing_prefs, conflicting_prefs) do
    cond do
      similarity_score > 0.8 ->
        "Very similar to your current preferences"

      length(missing_prefs) > length(conflicting_prefs) ->
        "Adds #{length(missing_prefs)} new preferences you haven't configured"

      length(conflicting_prefs) > 0 ->
        "Changes #{length(conflicting_prefs)} of your existing preferences"

      true ->
        "Partially matches your preference style"
    end
  end

  defp create_system_template(template_def) do
    attrs = %{
      name: template_def.name,
      description: template_def.description,
      category: template_def.category,
      preferences: template_def.preferences,
      template_type: template_def.template_type,
      created_by: nil,
      featured: true
    }

    PreferenceTemplate.create(attrs)
  end

  defp update_template_usage(template_id) do
    case get_template(template_id) do
      {:ok, template} ->
        PreferenceTemplate.update(template, %{usage_count: template.usage_count + 1})

      error ->
        Logger.warning("Failed to update template usage: #{inspect(error)}")
        error
    end
  end

  defp validate_template_update_permission(template, user_id) do
    cond do
      template.template_type == :system ->
        {:error, "System templates cannot be modified"}

      template.created_by == user_id ->
        :ok

      template.template_type == :public ->
        {:error, "Public templates can only be modified by their creators"}

      true ->
        {:error, "Insufficient permissions to update template"}
    end
  end
end
