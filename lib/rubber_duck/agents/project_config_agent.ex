defmodule RubberDuck.Agents.ProjectConfigAgent do
  @moduledoc """
  Project configuration agent for autonomous project-specific preference management.

  This agent manages project-specific settings, handles override logic validation,
  tracks project preference changes, and provides intelligent project configuration
  recommendations based on team patterns and best practices.
  """

  use Jido.Agent,
    name: "project_config_agent",
    description:
      "Autonomous project preference management with override validation and change tracking",
    category: "preferences",
    tags: ["project", "configuration", "overrides", "validation"],
    vsn: "1.0.0"

  require Logger

  alias RubberDuck.Preferences.{ProjectPreferenceManager, ValidationInterfaceManager}

  # Agent state fields are managed through direct state setting

  @doc """
  Create a new ProjectConfigAgent for a project.
  """
  def create_for_project(project_id) do
    with {:ok, agent} <- __MODULE__.new(),
         {:ok, agent} <-
           __MODULE__.set(agent,
             project_id: project_id,
             override_statistics: %{total: 0, by_category: %{}},
             validation_history: [],
             change_tracking: [],
             configuration_suggestions: [],
             last_validation: DateTime.utc_now(),
             team_patterns: %{}
           ) do
      {:ok, agent}
    end
  end

  @doc """
  Validate project preference override with intelligent suggestions.
  """
  def validate_project_override(agent, preference_key, value, user_id) do
    validation_context = %{
      user_id: user_id,
      project_id: agent.project_id
    }

    case ValidationInterfaceManager.validate_preference_changes(
           %{preference_key => value},
           validation_context
         ) do
      {:ok, validation_result} ->
        updated_agent = record_validation_success(agent, preference_key, value, validation_result)
        {:ok, validation_result, updated_agent}

      {:error, reason} ->
        updated_agent = record_validation_failure(agent, preference_key, value, reason)
        {:error, reason, updated_agent}
    end
  end

  @doc """
  Track project preference changes and learn from patterns.
  """
  def track_preference_change(agent, change_data) do
    change_entry = %{
      preference_key: change_data.preference_key,
      old_value: change_data.old_value,
      new_value: change_data.new_value,
      changed_by: change_data.changed_by,
      change_reason: change_data.reason,
      timestamp: DateTime.utc_now()
    }

    updated_agent = record_preference_change(agent, change_entry)
    learn_from_change_patterns(updated_agent, change_entry)
  end

  @doc """
  Generate project configuration recommendations.
  """
  def generate_project_recommendations(agent) do
    recommendations = []

    recommendations = recommendations ++ analyze_override_patterns(agent)
    recommendations = recommendations ++ suggest_configuration_optimizations(agent)
    recommendations = recommendations ++ identify_team_alignment_opportunities(agent)

    updated_agent = %{agent | configuration_suggestions: recommendations}
    {:ok, recommendations, updated_agent}
  end

  @doc """
  Check project preference enablement and suggest improvements.
  """
  def check_project_enablement(agent) do
    case ProjectPreferenceManager.get_override_status(agent.project_id) do
      {:ok, status} ->
        suggestions = analyze_enablement_status(status)
        updated_agent = record_enablement_check(agent, status, suggestions)
        {:ok, %{status: status, suggestions: suggestions}, updated_agent}

      {:error, reason} ->
        Logger.warning("Failed to check project enablement: #{inspect(reason)}")
        {:error, reason, agent}
    end
  end

  @doc """
  Suggest project preference optimizations based on team patterns.
  """
  def suggest_optimizations(agent) do
    optimizations = []

    optimizations = optimizations ++ suggest_category_optimizations(agent)
    optimizations = optimizations ++ suggest_template_usage(agent)
    optimizations = optimizations ++ suggest_validation_improvements(agent)

    {:ok, optimizations, agent}
  end

  # Private helper functions

  defp record_validation_success(agent, preference_key, value, validation_result) do
    validation_entry = %{
      preference_key: preference_key,
      value: value,
      validation_result: validation_result,
      timestamp: DateTime.utc_now(),
      status: :success
    }

    updated_history = add_to_validation_history(agent.validation_history, validation_entry)

    updated_stats =
      update_override_statistics(agent.override_statistics, preference_key, :success)

    %{
      agent
      | validation_history: updated_history,
        override_statistics: updated_stats,
        last_validation: DateTime.utc_now()
    }
  end

  defp record_validation_failure(agent, preference_key, value, reason) do
    validation_entry = %{
      preference_key: preference_key,
      value: value,
      reason: reason,
      timestamp: DateTime.utc_now(),
      status: :failed
    }

    updated_history = add_to_validation_history(agent.validation_history, validation_entry)

    %{agent | validation_history: updated_history, last_validation: DateTime.utc_now()}
  end

  defp record_preference_change(agent, change_entry) do
    updated_tracking = add_to_change_tracking(agent.change_tracking, change_entry)

    updated_stats =
      update_override_statistics(agent.override_statistics, change_entry.preference_key, :change)

    %{agent | change_tracking: updated_tracking, override_statistics: updated_stats}
  end

  defp learn_from_change_patterns(agent, change_entry) do
    category = get_preference_category(change_entry.preference_key)

    # Update team patterns
    updated_patterns = update_team_patterns(agent.team_patterns, category, change_entry)

    %{agent | team_patterns: updated_patterns}
  end

  defp add_to_validation_history(history, new_entry) do
    [new_entry | history] |> Enum.take(50)
  end

  defp add_to_change_tracking(tracking, new_entry) do
    [new_entry | tracking] |> Enum.take(100)
  end

  defp update_override_statistics(stats, preference_key, action) do
    category = get_preference_category(preference_key)

    updated_total = stats.total + 1
    updated_by_category = Map.update(stats.by_category, category, 1, &(&1 + 1))

    %{stats | total: updated_total, by_category: updated_by_category}
  end

  defp update_team_patterns(patterns, category, change_entry) do
    category_patterns = Map.get(patterns, category, %{changes: [], trends: %{}})

    updated_changes = [change_entry | category_patterns.changes] |> Enum.take(20)
    updated_trends = analyze_category_trends(updated_changes)

    updated_category_patterns = %{
      category_patterns
      | changes: updated_changes,
        trends: updated_trends
    }

    Map.put(patterns, category, updated_category_patterns)
  end

  defp analyze_category_trends(changes) do
    # Analyze trends in preference changes for this category
    %{
      most_changed_preference: find_most_changed_preference(changes),
      change_frequency: calculate_change_frequency(changes),
      common_values: find_common_values(changes)
    }
  end

  defp analyze_override_patterns(agent) do
    if agent.override_statistics.total > 5 do
      most_overridden_category =
        find_most_overridden_category(agent.override_statistics.by_category)

      if most_overridden_category do
        [
          %{
            type: :override_pattern,
            priority: :medium,
            message: "High override activity in #{most_overridden_category} category",
            suggested_action:
              "Consider creating a project template for #{most_overridden_category} preferences"
          }
        ]
      else
        []
      end
    else
      []
    end
  end

  defp suggest_configuration_optimizations(agent) do
    validation_failures =
      agent.validation_history
      |> Enum.filter(&(&1.status == :failed))
      |> length()

    if validation_failures > 3 do
      [
        %{
          type: :validation_optimization,
          priority: :high,
          message: "#{validation_failures} validation failures detected",
          suggested_action: "Review preference constraints and validation rules"
        }
      ]
    else
      []
    end
  end

  defp identify_team_alignment_opportunities(_agent) do
    # Placeholder for team alignment analysis
    []
  end

  defp analyze_enablement_status(status) do
    suggestions = []

    if not status.enabled do
      suggestions = [
        %{
          type: :enablement,
          priority: :medium,
          message: "Project preferences not enabled",
          suggested_action: "Enable project preferences to allow team customization"
        }
        | suggestions
      ]
    end

    if status.total_overrides == 0 and status.enabled do
      suggestions = [
        %{
          type: :usage,
          priority: :low,
          message: "No preference overrides configured",
          suggested_action:
            "Consider applying a template or configuring project-specific preferences"
        }
        | suggestions
      ]
    end

    suggestions
  end

  defp record_enablement_check(agent, status, suggestions) do
    check_entry = %{
      status: status,
      suggestions: suggestions,
      timestamp: DateTime.utc_now()
    }

    updated_history = add_to_validation_history(agent.validation_history, check_entry)
    %{agent | validation_history: updated_history}
  end

  defp suggest_category_optimizations(_agent), do: []
  defp suggest_template_usage(_agent), do: []
  defp suggest_validation_improvements(_agent), do: []

  defp find_most_changed_preference(changes) do
    changes
    |> Enum.map(& &1.preference_key)
    |> Enum.frequencies()
    |> Enum.max_by(&elem(&1, 1), fn -> {nil, 0} end)
    |> elem(0)
  end

  defp calculate_change_frequency(changes) do
    if length(changes) > 1 do
      time_span_hours = DateTime.diff(hd(changes).timestamp, List.last(changes).timestamp) / 3600
      if time_span_hours > 0, do: length(changes) / time_span_hours, else: 0.0
    else
      0.0
    end
  end

  defp find_common_values(changes) do
    changes
    |> Enum.map(& &1.new_value)
    |> Enum.frequencies()
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.take(3)
  end

  defp find_most_overridden_category(by_category) do
    if map_size(by_category) > 0 do
      Enum.max_by(by_category, &elem(&1, 1)) |> elem(0)
    else
      nil
    end
  end

  defp get_preference_category(preference_key) do
    preference_key
    |> String.split(".")
    |> hd()
  end
end
