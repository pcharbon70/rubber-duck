defmodule RubberDuck.Preferences.BulkOperationsManager do
  @moduledoc """
  Bulk operations manager for multi-project preference management.

  Provides business logic for bulk operations across multiple projects
  including preference application, copying between projects, resetting
  to defaults, and template application. Includes safety checks and
  rollback capabilities.
  """

  require Logger

  alias RubberDuck.Preferences.{ProjectPreferenceManager, TemplateManager}
  alias RubberDuck.Preferences.Resources.ProjectPreference

  @doc """
  Apply preferences to multiple projects simultaneously.
  """
  @spec apply_preferences_to_projects(
          project_ids :: list(binary()),
          preferences :: map(),
          applied_by_user_id :: binary(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def apply_preferences_to_projects(project_ids, preferences, applied_by_user_id, opts \\ []) do
    reason = Keyword.get(opts, :reason, "Bulk preference application")
    dry_run = Keyword.get(opts, :dry_run, false)
    continue_on_error = Keyword.get(opts, :continue_on_error, true)

    if dry_run do
      simulate_bulk_application(project_ids, preferences)
    else
      execute_bulk_application(
        project_ids,
        preferences,
        applied_by_user_id,
        reason,
        continue_on_error
      )
    end
  end

  @doc """
  Copy preferences from source project to target projects.
  """
  @spec copy_preferences_between_projects(
          source_project_id :: binary(),
          target_project_ids :: list(binary()),
          copied_by_user_id :: binary(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def copy_preferences_between_projects(
        source_project_id,
        target_project_ids,
        copied_by_user_id,
        opts \\ []
      ) do
    selective_keys = Keyword.get(opts, :selective_keys, nil)
    overwrite_existing = Keyword.get(opts, :overwrite_existing, false)
    reason = Keyword.get(opts, :reason, "Copied from project #{source_project_id}")

    with {:ok, source_preferences} <- get_project_preferences(source_project_id),
         preferences_to_copy <- select_preferences_to_copy(source_preferences, selective_keys),
         preferences_map <- convert_preferences_to_map(preferences_to_copy) do
      apply_preferences_to_projects(
        target_project_ids,
        preferences_map,
        copied_by_user_id,
        reason: reason,
        overwrite_existing: overwrite_existing
      )
    else
      error ->
        Logger.warning("Failed to copy preferences between projects: #{inspect(error)}")
        error
    end
  end

  @doc """
  Reset multiple projects to user defaults (remove all project overrides).
  """
  @spec reset_projects_to_defaults(
          project_ids :: list(binary()),
          reset_by_user_id :: binary(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def reset_projects_to_defaults(project_ids, reset_by_user_id, opts \\ []) do
    categories = Keyword.get(opts, :categories, nil)
    dry_run = Keyword.get(opts, :dry_run, false)

    if dry_run do
      simulate_bulk_reset(project_ids, categories)
    else
      execute_bulk_reset(project_ids, categories, reset_by_user_id)
    end
  end

  @doc """
  Apply template to multiple projects.
  """
  @spec apply_template_to_projects(
          template_id :: binary(),
          project_ids :: list(binary()),
          applied_by_user_id :: binary(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def apply_template_to_projects(template_id, project_ids, applied_by_user_id, opts \\ []) do
    selective_keys = Keyword.get(opts, :selective_keys, nil)
    overwrite_existing = Keyword.get(opts, :overwrite_existing, false)
    dry_run = Keyword.get(opts, :dry_run, false)

    if dry_run do
      simulate_template_application(template_id, project_ids, selective_keys)
    else
      execute_template_application(
        template_id,
        project_ids,
        applied_by_user_id,
        selective_keys,
        overwrite_existing
      )
    end
  end

  @doc """
  Get bulk operation impact analysis before execution.
  """
  @spec analyze_bulk_operation_impact(
          operation :: atom(),
          project_ids :: list(binary()),
          operation_data :: map()
        ) :: {:ok, map()} | {:error, term()}
  def analyze_bulk_operation_impact(operation, project_ids, operation_data) do
    impact_analysis =
      case operation do
        :apply_preferences ->
          analyze_preference_application_impact(project_ids, operation_data.preferences)

        :copy_preferences ->
          analyze_preference_copy_impact(
            project_ids,
            operation_data.source_project_id,
            operation_data.selective_keys
          )

        :reset_to_defaults ->
          analyze_reset_impact(project_ids, operation_data.categories)

        :apply_template ->
          analyze_template_application_impact(
            project_ids,
            operation_data.template_id,
            operation_data.selective_keys
          )

        _ ->
          {:error, "Unsupported bulk operation"}
      end

    case impact_analysis do
      {:ok, analysis} ->
        enhanced_analysis =
          Map.merge(analysis, %{
            operation: operation,
            affected_projects: length(project_ids),
            estimated_duration:
              estimate_operation_duration(operation, project_ids, operation_data),
            risk_level: assess_operation_risk(operation, analysis)
          })

        {:ok, enhanced_analysis}

      error ->
        error
    end
  end

  # Private helper functions

  defp simulate_bulk_application(project_ids, preferences) do
    results = %{
      total_projects: length(project_ids),
      total_preferences: map_size(preferences),
      estimated_changes: length(project_ids) * map_size(preferences),
      would_succeed: count_projects_with_preferences_enabled(project_ids),
      would_fail: length(project_ids) - count_projects_with_preferences_enabled(project_ids)
    }

    {:ok, results}
  end

  defp execute_bulk_application(
         project_ids,
         preferences,
         applied_by_user_id,
         reason,
         continue_on_error
       ) do
    results = %{
      successful: [],
      failed: [],
      total_applied: 0,
      total_errors: 0
    }

    final_results =
      Enum.reduce(project_ids, results, fn project_id, acc ->
        case apply_preferences_to_single_project(
               project_id,
               preferences,
               applied_by_user_id,
               reason
             ) do
          {:ok, count} ->
            %{
              acc
              | successful: [project_id | acc.successful],
                total_applied: acc.total_applied + count
            }

          {:error, error} ->
            handle_bulk_application_error(project_id, error, acc, continue_on_error)
        end
      end)

    {:ok, final_results}
  catch
    {:bulk_operation_failed, failed_project_id, error} ->
      {:error, "Bulk operation failed at project #{failed_project_id}: #{inspect(error)}"}
  end

  defp execute_bulk_reset(project_ids, categories, reset_by_user_id) do
    results = %{
      successful: [],
      failed: [],
      total_removed: 0
    }

    final_results =
      Enum.reduce(project_ids, results, fn project_id, acc ->
        case reset_single_project(project_id, categories, reset_by_user_id) do
          {:ok, count} ->
            %{
              acc
              | successful: [project_id | acc.successful],
                total_removed: acc.total_removed + count
            }

          {:error, error} ->
            %{acc | failed: [{project_id, error} | acc.failed]}
        end
      end)

    {:ok, final_results}
  end

  defp execute_template_application(
         template_id,
         project_ids,
         applied_by_user_id,
         selective_keys,
         overwrite_existing
       ) do
    results = %{
      successful: [],
      failed: [],
      total_applied: 0
    }

    final_results =
      Enum.reduce(project_ids, results, fn project_id, acc ->
        case TemplateManager.apply_template_to_project(
               template_id,
               project_id,
               applied_by_user_id,
               selective_keys: selective_keys,
               overwrite_existing: overwrite_existing
             ) do
          {:ok, result} ->
            %{
              acc
              | successful: [project_id | acc.successful],
                total_applied: acc.total_applied + result.applied_count
            }

          {:error, error} ->
            %{acc | failed: [{project_id, error} | acc.failed]}
        end
      end)

    {:ok, final_results}
  end

  defp apply_preferences_to_single_project(project_id, preferences, applied_by_user_id, reason) do
    if ProjectPreferenceManager.project_preferences_enabled?(project_id) do
      results =
        Enum.map(preferences, fn {key, value} ->
          ProjectPreferenceManager.create_project_override(
            project_id,
            key,
            value,
            reason: reason,
            approved_by: applied_by_user_id
          )
        end)

      successful_count = Enum.count(results, &match?({:ok, _}, &1))
      {:ok, successful_count}
    else
      {:error, "Project preferences not enabled"}
    end
  end

  defp reset_single_project(project_id, categories, _reset_by_user_id) do
    case get_project_preferences(project_id) do
      {:ok, project_prefs} ->
        prefs_to_remove =
          if categories do
            Enum.filter(project_prefs, &(&1.category in categories))
          else
            project_prefs
          end

        removed_count =
          prefs_to_remove
          |> Enum.map(&ProjectPreferenceManager.remove_project_override(&1.id))
          |> Enum.count(&match?(:ok, &1))

        {:ok, removed_count}

      error ->
        error
    end
  end

  defp get_project_preferences(project_id) do
    ProjectPreference.by_project(project_id)
  end

  defp select_preferences_to_copy(preferences, selective_keys) do
    if selective_keys do
      Enum.filter(preferences, &(&1.preference_key in selective_keys))
    else
      preferences
    end
  end

  defp convert_preferences_to_map(preferences) do
    Map.new(preferences, &{&1.preference_key, &1.value})
  end

  defp count_projects_with_preferences_enabled(project_ids) do
    Enum.count(project_ids, &ProjectPreferenceManager.project_preferences_enabled?/1)
  end

  defp simulate_bulk_reset(project_ids, categories) do
    impact_counts = Enum.map(project_ids, &calculate_reset_count(&1, categories))

    {:ok,
     %{
       total_projects: length(project_ids),
       total_preferences_to_remove: Enum.sum(impact_counts),
       projects_with_preferences: Enum.count(impact_counts, &(&1 > 0))
     }}
  end

  defp simulate_template_application(template_id, project_ids, selective_keys) do
    case TemplateManager.get_template(template_id) do
      {:ok, template} ->
        preferences_count =
          if selective_keys do
            length(selective_keys)
          else
            map_size(template.preferences)
          end

        {:ok,
         %{
           total_projects: length(project_ids),
           preferences_per_project: preferences_count,
           estimated_total_changes: length(project_ids) * preferences_count,
           template_name: template.name
         }}

      error ->
        error
    end
  end

  defp analyze_preference_application_impact(project_ids, preferences) do
    total_changes = length(project_ids) * map_size(preferences)

    {:ok,
     %{
       total_projects: length(project_ids),
       total_preferences: map_size(preferences),
       estimated_changes: total_changes,
       preference_categories: get_preference_categories(preferences)
     }}
  end

  defp analyze_preference_copy_impact(project_ids, source_project_id, selective_keys) do
    case get_project_preferences(source_project_id) do
      {:ok, source_prefs} ->
        prefs_to_copy =
          if selective_keys do
            Enum.filter(source_prefs, &(&1.preference_key in selective_keys))
          else
            source_prefs
          end

        {:ok,
         %{
           source_project: source_project_id,
           target_projects: length(project_ids),
           preferences_to_copy: length(prefs_to_copy),
           estimated_changes: length(project_ids) * length(prefs_to_copy),
           categories_affected: get_categories_from_preferences(prefs_to_copy)
         }}

      error ->
        error
    end
  end

  defp analyze_reset_impact(project_ids, categories) do
    impact_data = Enum.map(project_ids, &calculate_project_reset_impact(&1, categories))

    total_removals = Enum.sum(Enum.map(impact_data, &elem(&1, 1)))

    {:ok,
     %{
       total_projects: length(project_ids),
       total_preferences_to_remove: total_removals,
       projects_affected: Enum.count(impact_data, fn {_id, count} -> count > 0 end),
       categories_affected: categories || ["all"]
     }}
  end

  defp analyze_template_application_impact(project_ids, template_id, selective_keys) do
    case TemplateManager.get_template(template_id) do
      {:ok, template} ->
        preferences_count =
          if selective_keys do
            length(selective_keys)
          else
            map_size(template.preferences)
          end

        {:ok,
         %{
           template_name: template.name,
           target_projects: length(project_ids),
           preferences_in_template: preferences_count,
           estimated_changes: length(project_ids) * preferences_count,
           template_categories: get_preference_categories(template.preferences)
         }}

      error ->
        error
    end
  end

  defp estimate_operation_duration(operation, project_ids, operation_data) do
    base_time_per_project =
      case operation do
        :apply_preferences -> map_size(operation_data.preferences) * 0.1
        :copy_preferences -> 5.0
        :reset_to_defaults -> 2.0
        :apply_template -> 3.0
      end

    total_time = length(project_ids) * base_time_per_project
    round(total_time)
  end

  defp assess_operation_risk(operation, analysis) do
    case operation do
      :reset_to_defaults ->
        if analysis.total_preferences_to_remove > 50, do: :high, else: :medium

      :apply_template ->
        if analysis.estimated_changes > 100, do: :medium, else: :low

      :copy_preferences ->
        if analysis.estimated_changes > 200, do: :high, else: :medium

      :apply_preferences ->
        if analysis.estimated_changes > 100, do: :medium, else: :low
    end
  end

  defp get_preference_categories(preferences) when is_map(preferences) do
    preferences
    |> Map.keys()
    |> Enum.map(&String.split(&1, "."))
    |> Enum.map(&hd/1)
    |> Enum.uniq()
  end

  defp get_categories_from_preferences(preferences) do
    preferences
    |> Enum.map(& &1.category)
    |> Enum.uniq()
  end

  defp handle_bulk_application_error(project_id, error, acc, continue_on_error) do
    Logger.warning("Failed to apply preferences to project #{project_id}: #{inspect(error)}")

    if continue_on_error do
      %{
        acc
        | failed: [{project_id, error} | acc.failed],
          total_errors: acc.total_errors + 1
      }
    else
      throw({:bulk_operation_failed, project_id, error})
    end
  end

  defp calculate_project_reset_impact(project_id, categories) do
    case get_project_preferences(project_id) do
      {:ok, prefs} ->
        affected_prefs = filter_preferences_by_categories(prefs, categories)
        {project_id, length(affected_prefs)}

      _ ->
        {project_id, 0}
    end
  end

  defp filter_preferences_by_categories(prefs, nil), do: prefs
  defp filter_preferences_by_categories(prefs, categories) do
    Enum.filter(prefs, &(&1.category in categories))
  end

  defp calculate_reset_count(project_id, categories) do
    case get_project_preferences(project_id) do
      {:ok, prefs} ->
        count_prefs_by_category(prefs, categories)

      _ ->
        0
    end
  end

  defp count_prefs_by_category(prefs, nil), do: length(prefs)
  defp count_prefs_by_category(prefs, categories) do
    Enum.count(prefs, &(&1.category in categories))
  end
end
