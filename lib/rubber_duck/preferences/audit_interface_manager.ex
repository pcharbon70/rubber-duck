defmodule RubberDuck.Preferences.AuditInterfaceManager do
  @moduledoc """
  Audit interface manager for preference change tracking and rollback.

  Provides business logic for viewing preference change history, rollback
  operations, change attribution, and approval tracking. Integrates with
  the existing PreferenceHistory resource for comprehensive audit trails.
  """

  require Logger

  alias RubberDuck.Preferences.ProjectPreferenceManager
  alias RubberDuck.Preferences.Resources.{PreferenceHistory, ProjectPreference, UserPreference}

  @doc """
  Get change history for a specific preference key.
  """
  @spec get_preference_history(
          preference_key :: String.t(),
          opts :: keyword()
        ) :: {:ok, list(PreferenceHistory.t())} | {:error, term()}
  def get_preference_history(preference_key, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    user_id = Keyword.get(opts, :user_id, nil)
    project_id = Keyword.get(opts, :project_id, nil)

    filters = build_history_filters(preference_key, user_id, project_id)

    # Placeholder for preference history lookup
    case {:ok, []} do
      {:ok, history} -> {:ok, enrich_history_entries(history)}
      error -> error
    end
  end

  @doc """
  Get change history for a project across all preferences.
  """
  @spec get_project_change_history(
          project_id :: binary(),
          opts :: keyword()
        ) :: {:ok, list(map())} | {:error, term()}
  def get_project_change_history(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    category = Keyword.get(opts, :category, nil)
    since = Keyword.get(opts, :since, nil)

    filters = %{
      project_id: project_id,
      category: category,
      since: since
    }

    case PreferenceHistory.by_project(project_id, filters, limit: limit) do
      {:ok, history} ->
        grouped_history = group_history_by_change_session(history)
        {:ok, grouped_history}

      error ->
        error
    end
  end

  @doc """
  Get change history for a user across all preferences.
  """
  @spec get_user_change_history(
          user_id :: binary(),
          opts :: keyword()
        ) :: {:ok, list(PreferenceHistory.t())} | {:error, term()}
  def get_user_change_history(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    category = Keyword.get(opts, :category, nil)
    since = Keyword.get(opts, :since, nil)

    filters = %{
      user_id: user_id,
      category: category,
      since: since
    }

    case PreferenceHistory.by_user(user_id, filters, limit: limit) do
      {:ok, history} -> {:ok, enrich_history_entries(history)}
      error -> error
    end
  end

  @doc """
  Rollback a preference to a previous value.
  """
  @spec rollback_preference(
          history_entry_id :: binary(),
          rollback_by_user_id :: binary(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def rollback_preference(history_entry_id, rollback_by_user_id, opts \\ []) do
    reason = Keyword.get(opts, :reason, "Preference rollback")

    with {:ok, history_entry} <- get_history_entry(history_entry_id),
         :ok <- validate_rollback_allowed(history_entry),
         {:ok, rollback_result} <- execute_rollback(history_entry, rollback_by_user_id, reason) do
      Logger.info("Rolled back preference #{history_entry.preference_key} to previous value")
      {:ok, rollback_result}
    else
      error ->
        Logger.warning("Failed to rollback preference: #{inspect(error)}")
        error
    end
  end

  @doc """
  Get rollback options for a preference.
  """
  @spec get_rollback_options(preference_key :: String.t(), opts :: keyword()) ::
          {:ok, list(map())} | {:error, term()}
  def get_rollback_options(preference_key, opts \\ []) do
    user_id = Keyword.get(opts, :user_id, nil)
    project_id = Keyword.get(opts, :project_id, nil)

    case get_preference_history(preference_key,
           user_id: user_id,
           project_id: project_id,
           limit: 10
         ) do
      {:ok, history} ->
        rollback_options =
          history
          |> Enum.filter(& &1.rollback_possible)
          |> Enum.map(&format_rollback_option/1)

        {:ok, rollback_options}

      error ->
        error
    end
  end

  @doc """
  Get change attribution summary for a time period.
  """
  @spec get_change_attribution(
          start_date :: Date.t(),
          end_date :: Date.t(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def get_change_attribution(start_date, end_date, opts \\ []) do
    project_id = Keyword.get(opts, :project_id, nil)
    category = Keyword.get(opts, :category, nil)

    filters = %{
      start_date: start_date,
      end_date: end_date,
      project_id: project_id,
      category: category
    }

    # Placeholder for date range history lookup
    case {:ok, []} do
      {:ok, history} ->
        attribution = calculate_change_attribution(history)
        {:ok, attribution}

      error ->
        error
    end
  end

  @doc """
  Get approval tracking status for pending changes.
  """
  @spec get_approval_tracking(project_id :: binary()) :: {:ok, map()} | {:error, term()}
  def get_approval_tracking(project_id) do
    case get_project_preferences(project_id) do
      {:ok, project_prefs} ->
        approval_status = %{
          pending_approval: count_pending_approvals(project_prefs),
          approved_changes: count_approved_changes(project_prefs),
          temporary_overrides: count_temporary_overrides(project_prefs),
          recent_changes: get_recent_changes(project_id, 7)
        }

        {:ok, approval_status}

      error ->
        error
    end
  end

  @doc """
  Create change summary for reporting and analytics.
  """
  @spec create_change_summary(
          target :: {:user, binary()} | {:project, binary()},
          time_period :: atom(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def create_change_summary(target, time_period, opts \\ []) do
    include_details = Keyword.get(opts, :include_details, false)

    {start_date, end_date} = calculate_time_period(time_period)

    case target do
      {:user, user_id} ->
        create_user_change_summary(user_id, start_date, end_date, include_details)

      {:project, project_id} ->
        create_project_change_summary(project_id, start_date, end_date, include_details)
    end
  end

  # Private helper functions

  defp build_history_filters(preference_key, user_id, project_id) do
    %{
      preference_key: preference_key,
      user_id: user_id,
      project_id: project_id
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp enrich_history_entries(history_entries) do
    Enum.map(history_entries, &enrich_single_history_entry/1)
  end

  defp enrich_single_history_entry(entry) do
    Map.merge(entry, %{
      change_impact: assess_change_impact(entry),
      rollback_complexity: assess_rollback_complexity(entry),
      change_category: categorize_change(entry)
    })
  end

  defp group_history_by_change_session(history) do
    history
    |> Enum.group_by(& &1.batch_id)
    |> Enum.map(fn {batch_id, entries} ->
      %{
        batch_id: batch_id || generate_single_change_id(List.first(entries)),
        timestamp: List.first(entries).changed_at,
        change_count: length(entries),
        changed_by: List.first(entries).changed_by,
        change_type: determine_batch_change_type(entries),
        entries: entries
      }
    end)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  defp get_history_entry(history_entry_id) do
    # Placeholder for history entry lookup
    case {:ok, %{}} do
      {:ok, entry} -> {:ok, entry}
      error -> error
    end
  end

  defp validate_rollback_allowed(history_entry) do
    cond do
      not history_entry.rollback_possible ->
        {:error, "Rollback not allowed for this change"}

      is_nil(history_entry.old_value) ->
        {:error, "Cannot rollback creation - no previous value"}

      true ->
        :ok
    end
  end

  defp execute_rollback(history_entry, rollback_by_user_id, reason) do
    case {history_entry.user_id, history_entry.project_id} do
      {user_id, nil} when not is_nil(user_id) ->
        rollback_user_preference(history_entry, rollback_by_user_id, reason)

      {_, project_id} when not is_nil(project_id) ->
        rollback_project_preference(history_entry, rollback_by_user_id, reason)

      _ ->
        {:error, "Invalid history entry - cannot determine target"}
    end
  end

  defp rollback_user_preference(history_entry, rollback_by_user_id, reason) do
    # Placeholder for user preference lookup
    case {:ok, []} do
      {:ok, [current_pref]} ->
        case UserPreference.update(current_pref, %{value: history_entry.old_value}) do
          {:ok, updated} ->
            create_rollback_history_entry(history_entry, rollback_by_user_id, reason)
            {:ok, %{rolled_back_to: history_entry.old_value, preference: updated}}

          error ->
            error
        end

      {:ok, []} ->
        {:error, "Preference no longer exists"}

      error ->
        error
    end
  end

  defp rollback_project_preference(history_entry, rollback_by_user_id, reason) do
    # Placeholder for project preference lookup
    case {:ok, []} do
      {:ok, [current_pref]} ->
        case ProjectPreferenceManager.update_project_override(
               current_pref.id,
               history_entry.old_value,
               reason: reason
             ) do
          {:ok, updated} ->
            create_rollback_history_entry(history_entry, rollback_by_user_id, reason)
            {:ok, %{rolled_back_to: history_entry.old_value, preference: updated}}

          error ->
            error
        end

      {:ok, []} ->
        {:error, "Project preference no longer exists"}

      error ->
        error
    end
  end

  defp create_rollback_history_entry(original_entry, rollback_by_user_id, reason) do
    attrs = %{
      user_id: original_entry.user_id,
      project_id: original_entry.project_id,
      preference_key: original_entry.preference_key,
      old_value: original_entry.new_value,
      new_value: original_entry.old_value,
      change_type: :rollback,
      change_reason: reason,
      changed_by: rollback_by_user_id
    }

    case PreferenceHistory.create(attrs) do
      {:ok, _} -> :ok
      error -> Logger.warning("Failed to create rollback history entry: #{inspect(error)}")
    end
  end

  defp format_rollback_option(history_entry) do
    %{
      id: history_entry.change_id,
      timestamp: history_entry.changed_at,
      old_value: history_entry.old_value,
      new_value: history_entry.new_value,
      changed_by: history_entry.changed_by,
      change_reason: history_entry.change_reason,
      rollback_description: "Rollback to: #{history_entry.old_value}"
    }
  end

  defp calculate_change_attribution(history) do
    by_user =
      history
      |> Enum.group_by(& &1.changed_by)
      |> Map.new(fn {user, changes} -> {user, length(changes)} end)

    by_change_type =
      history
      |> Enum.group_by(& &1.change_type)
      |> Map.new(fn {type, changes} -> {type, length(changes)} end)

    by_category =
      history
      |> Enum.group_by(&get_preference_category(&1.preference_key))
      |> Map.new(fn {category, changes} -> {category, length(changes)} end)

    %{
      total_changes: length(history),
      changes_by_user: by_user,
      changes_by_type: by_change_type,
      changes_by_category: by_category,
      most_active_user: find_most_active_user(by_user),
      most_changed_category: find_most_changed_category(by_category)
    }
  end

  defp count_pending_approvals(project_prefs) do
    Enum.count(project_prefs, &is_nil(&1.approved_by))
  end

  defp count_approved_changes(project_prefs) do
    Enum.count(project_prefs, &(not is_nil(&1.approved_by)))
  end

  defp count_temporary_overrides(project_prefs) do
    Enum.count(project_prefs, & &1.temporary)
  end

  defp get_recent_changes(project_id, days) do
    since_date = Date.add(Date.utc_today(), -days)

    # Placeholder for recent changes lookup
    case {:ok, []} do
      {:ok, changes} -> length(changes)
      _ -> 0
    end
  end

  defp get_project_preferences(project_id) do
    ProjectPreference.by_project(project_id)
  end

  defp assess_change_impact(history_entry) do
    case history_entry.change_type do
      :create -> :low
      :update -> assess_update_impact(history_entry)
      :delete -> :high
      :template_apply -> :medium
      :rollback -> :medium
    end
  end

  defp assess_update_impact(history_entry) do
    # Assess impact based on preference type and change magnitude
    category = get_preference_category(history_entry.preference_key)

    case category do
      "code_quality" -> :medium
      "budgeting" -> :high
      "ml" -> :medium
      "llm" -> :low
      _ -> :low
    end
  end

  defp assess_rollback_complexity(history_entry) do
    case history_entry.change_type do
      :create -> :high
      :delete -> :high
      :update -> :medium
      :template_apply -> :low
      _ -> :medium
    end
  end

  defp categorize_change(history_entry) do
    case history_entry.change_type do
      :template_apply -> :bulk_change
      :rollback -> :corrective_change
      _ -> :individual_change
    end
  end

  defp determine_batch_change_type(entries) do
    change_types = Enum.map(entries, & &1.change_type) |> Enum.uniq()

    cond do
      :template_apply in change_types -> :template_application
      length(entries) > 5 -> :bulk_operation
      length(change_types) == 1 -> List.first(change_types)
      true -> :mixed_changes
    end
  end

  defp generate_single_change_id(entry) do
    "single_#{entry.change_id}"
  end

  defp calculate_time_period(time_period) do
    end_date = Date.utc_today()

    start_date =
      case time_period do
        :day -> Date.add(end_date, -1)
        :week -> Date.add(end_date, -7)
        :month -> Date.add(end_date, -30)
        :quarter -> Date.add(end_date, -90)
        :year -> Date.add(end_date, -365)
      end

    {start_date, end_date}
  end

  defp create_user_change_summary(user_id, start_date, end_date, include_details) do
    case get_user_change_history(user_id, since: start_date) do
      {:ok, history} ->
        summary = %{
          user_id: user_id,
          period: %{start: start_date, end: end_date},
          total_changes: length(history),
          change_attribution: calculate_change_attribution(history)
        }

        summary =
          if include_details do
            Map.put(summary, :detailed_changes, history)
          else
            summary
          end

        {:ok, summary}

      error ->
        error
    end
  end

  defp create_project_change_summary(project_id, start_date, end_date, include_details) do
    case get_project_change_history(project_id, since: start_date) do
      {:ok, history} ->
        summary = %{
          project_id: project_id,
          period: %{start: start_date, end: end_date},
          total_changes: length(history),
          change_attribution:
            calculate_change_attribution(List.flatten(Enum.map(history, & &1.entries)))
        }

        summary =
          if include_details do
            Map.put(summary, :detailed_changes, history)
          else
            summary
          end

        {:ok, summary}

      error ->
        error
    end
  end

  defp get_preference_category(preference_key) do
    preference_key
    |> String.split(".")
    |> hd()
  end

  defp find_most_active_user(changes_by_user) do
    if map_size(changes_by_user) > 0 do
      Enum.max_by(changes_by_user, &elem(&1, 1)) |> elem(0)
    else
      nil
    end
  end

  defp find_most_changed_category(changes_by_category) do
    if map_size(changes_by_category) > 0 do
      Enum.max_by(changes_by_category, &elem(&1, 1)) |> elem(0)
    else
      nil
    end
  end
end
