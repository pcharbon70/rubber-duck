defmodule RubberDuck.Preferences.OverrideAnalytics do
  @moduledoc """
  Analytics and reporting for preference override usage patterns.

  Provides insights into override patterns, suggests template creation,
  and identifies optimization opportunities for preference management.
  """

  require Logger

  alias RubberDuck.Preferences.Resources.{ProjectPreference, SystemDefault, UserPreference}

  @doc """
  Generate comprehensive analytics report for preference override usage.
  """
  @spec generate_analytics_report() :: map()
  def generate_analytics_report do
    %{
      overview: generate_overview_stats(),
      most_overridden: get_most_overridden_preferences(),
      category_analysis: analyze_category_overrides(),
      temporal_analysis: analyze_temporal_patterns(),
      template_suggestions: suggest_template_creation(),
      efficiency_metrics: calculate_efficiency_metrics(),
      generated_at: DateTime.utc_now()
    }
  end

  @doc """
  Analyze override patterns for a specific project.
  """
  @spec analyze_project_patterns(project_id :: binary()) :: map()
  def analyze_project_patterns(project_id) do
    case ProjectPreference.by_project(project_id) do
      {:ok, preferences} ->
        %{
          project_id: project_id,
          total_overrides: length(preferences),
          active_overrides: count_active_overrides(preferences),
          category_breakdown: group_by_category(preferences),
          temporal_breakdown: group_by_time_period(preferences),
          override_complexity: calculate_override_complexity(preferences),
          recommended_actions: generate_project_recommendations(preferences),
          last_analyzed: DateTime.utc_now()
        }

      {:error, _} ->
        %{
          project_id: project_id,
          error: "Unable to analyze project patterns",
          last_analyzed: DateTime.utc_now()
        }
    end
  end

  @doc """
  Identify preferences that would benefit from template creation.
  """
  @spec suggest_template_creation() :: [map()]
  def suggest_template_creation do
    case ProjectPreference.read() do
      {:ok, all_preferences} ->
        all_preferences
        |> group_by_preference_key()
        |> Enum.filter(&template_worthy?/1)
        |> Enum.map(&format_template_suggestion/1)
        |> Enum.sort_by(& &1.recommendation_score, :desc)

      {:error, _} ->
        []
    end
  end

  @doc """
  Track override usage patterns for optimization.
  """
  @spec track_usage_pattern(
          user_id :: binary(),
          project_id :: binary() | nil,
          preference_key :: String.t(),
          access_type :: atom()
        ) :: :ok
  def track_usage_pattern(user_id, project_id, preference_key, access_type) do
    :telemetry.execute(
      [:rubber_duck, :preferences, :usage_tracked],
      %{count: 1},
      %{
        user_id: user_id,
        project_id: project_id,
        preference_key: preference_key,
        access_type: access_type,
        timestamp: DateTime.utc_now()
      }
    )

    :ok
  end

  @doc """
  Generate optimization recommendations based on usage patterns.
  """
  @spec generate_optimization_recommendations() :: [map()]
  def generate_optimization_recommendations do
    recommendations = []

    # Check for commonly overridden system defaults
    recommendations = recommendations ++ suggest_default_adjustments()

    # Check for unused project overrides
    recommendations = recommendations ++ suggest_override_cleanup()

    # Check for template consolidation opportunities
    recommendations = recommendations ++ suggest_template_consolidation()

    # Check for permission optimization
    recommendations = recommendations ++ suggest_permission_optimization()

    recommendations
  end

  # Private functions

  defp generate_overview_stats do
    with {:ok, all_user_prefs} <- UserPreference.read(),
         {:ok, all_project_prefs} <- ProjectPreference.read(),
         {:ok, all_system_defaults} <- SystemDefault.read() do
      total_users_with_overrides =
        all_user_prefs
        |> Enum.map(& &1.user_id)
        |> Enum.uniq()
        |> length()

      total_projects_with_overrides =
        all_project_prefs
        |> Enum.map(& &1.project_id)
        |> Enum.uniq()
        |> length()

      %{
        total_system_defaults: length(all_system_defaults),
        total_user_preferences: length(all_user_prefs),
        total_project_preferences: length(all_project_prefs),
        users_with_overrides: total_users_with_overrides,
        projects_with_overrides: total_projects_with_overrides
      }
    else
      _ -> %{error: "Unable to generate overview statistics"}
    end
  end

  defp get_most_overridden_preferences do
    case ProjectPreference.read() do
      {:ok, all_preferences} ->
        all_preferences
        |> Enum.group_by(& &1.preference_key)
        |> Enum.map(fn {key, prefs} ->
          {key, length(prefs), get_preference_description(key)}
        end)
        |> Enum.sort_by(fn {_key, count, _desc} -> count end, :desc)
        |> Enum.take(10)
        |> Enum.map(fn {key, count, description} ->
          %{
            preference_key: key,
            override_count: count,
            description: description
          }
        end)

      {:error, _} ->
        []
    end
  end

  defp analyze_category_overrides do
    case ProjectPreference.read() do
      {:ok, all_preferences} ->
        all_preferences
        |> Enum.group_by(& &1.category)
        |> Enum.map(fn {category, prefs} ->
          %{
            category: category,
            total_overrides: length(prefs),
            active_overrides: count_active_overrides(prefs),
            average_per_project: calculate_average_per_project(prefs)
          }
        end)
        |> Enum.sort_by(& &1.total_overrides, :desc)

      {:error, _} ->
        []
    end
  end

  defp analyze_temporal_patterns do
    case ProjectPreference.read() do
      {:ok, all_preferences} ->
        now = DateTime.utc_now()

        last_30_days =
          all_preferences
          |> Enum.filter(&(DateTime.diff(now, &1.inserted_at, :day) <= 30))
          |> length()

        last_7_days =
          all_preferences
          |> Enum.filter(&(DateTime.diff(now, &1.inserted_at, :day) <= 7))
          |> length()

        %{
          overrides_last_30_days: last_30_days,
          overrides_last_7_days: last_7_days,
          daily_average: last_30_days / 30,
          weekly_trend: if(last_7_days > 0, do: :increasing, else: :stable)
        }

      {:error, _} ->
        %{error: "Unable to analyze temporal patterns"}
    end
  end

  defp calculate_efficiency_metrics do
    with {:ok, user_prefs} <- UserPreference.read(),
         {:ok, project_prefs} <- ProjectPreference.read() do
      total_preference_operations = length(user_prefs) + length(project_prefs)

      cache_hits = get_cache_hit_rate()
      resolution_time = get_average_resolution_time()

      %{
        total_operations: total_preference_operations,
        cache_hit_rate: cache_hits,
        average_resolution_time_ms: resolution_time,
        efficiency_score: calculate_efficiency_score(cache_hits, resolution_time)
      }
    else
      _ -> %{error: "Unable to calculate efficiency metrics"}
    end
  end

  defp group_by_preference_key(preferences) do
    preferences
    |> Enum.group_by(& &1.preference_key)
    |> Enum.map(fn {key, prefs} -> {key, prefs} end)
  end

  defp template_worthy?({_key, preferences}) do
    # A preference is template-worthy if it's overridden by multiple projects
    # with similar values
    length(preferences) >= 3 && has_similar_values?(preferences)
  end

  defp has_similar_values?(preferences) do
    values = Enum.map(preferences, & &1.value)
    unique_values = Enum.uniq(values)

    # Consider template-worthy if most projects use the same override value
    length(unique_values) <= 2 && length(values) >= 3
  end

  defp format_template_suggestion({preference_key, preferences}) do
    most_common_value = get_most_common_value(preferences)

    %{
      preference_key: preference_key,
      suggested_template_name: "Common #{preference_key} Override",
      override_count: length(preferences),
      suggested_value: most_common_value,
      projects_using: Enum.map(preferences, & &1.project_id),
      recommendation_score: calculate_recommendation_score(preferences)
    }
  end

  defp get_most_common_value(preferences) do
    preferences
    |> Enum.group_by(& &1.value)
    |> Enum.max_by(fn {_value, prefs} -> length(prefs) end)
    |> elem(0)
  end

  defp calculate_recommendation_score(preferences) do
    base_score = length(preferences) * 10

    # Bonus for recent activity
    recent_bonus =
      preferences
      |> Enum.count(&(DateTime.diff(DateTime.utc_now(), &1.updated_at, :day) <= 30))
      |> Kernel.*(5)

    base_score + recent_bonus
  end

  defp suggest_default_adjustments do
    # Analyze which system defaults are commonly overridden
    case get_most_overridden_preferences() do
      preferences when preferences != [] ->
        preferences
        |> Enum.filter(&(&1.override_count >= 5))
        |> Enum.map(fn pref ->
          %{
            type: :adjust_system_default,
            preference_key: pref.preference_key,
            current_override_count: pref.override_count,
            recommendation: "Consider adjusting system default based on common overrides",
            priority: :medium
          }
        end)

      _ ->
        []
    end
  end

  defp suggest_override_cleanup do
    # Find overrides that haven't been used recently
    case ProjectPreference.read() do
      {:ok, all_prefs} ->
        cutoff_date = DateTime.add(DateTime.utc_now(), -90, :day)

        all_prefs
        |> Enum.filter(&(DateTime.compare(&1.updated_at, cutoff_date) == :lt))
        |> Enum.map(fn pref ->
          %{
            type: :cleanup_override,
            project_id: pref.project_id,
            preference_key: pref.preference_key,
            last_modified: pref.updated_at,
            recommendation: "Consider removing unused override",
            priority: :low
          }
        end)

      {:error, _} ->
        []
    end
  end

  defp suggest_template_consolidation do
    # Find groups of similar overrides that could be templated
    suggest_template_creation()
    |> Enum.filter(&(&1.recommendation_score >= 50))
    |> Enum.map(fn suggestion ->
      %{
        type: :create_template,
        preference_key: suggestion.preference_key,
        template_name: suggestion.suggested_template_name,
        project_count: length(suggestion.projects_using),
        recommendation: "Create template for common override pattern",
        priority: :high
      }
    end)
  end

  defp suggest_permission_optimization do
    # Analyze permission patterns for optimization opportunities
    # Placeholder for permission optimization analysis
    []
  end

  defp count_active_overrides(preferences) do
    Enum.count(preferences, fn pref ->
      # Check if override is currently active based on effective dates
      now = DateTime.utc_now()

      DateTime.compare(pref.effective_from, now) != :gt &&
        (is_nil(pref.effective_until) || DateTime.compare(pref.effective_until, now) == :gt)
    end)
  end

  defp group_by_category(preferences) do
    preferences
    |> Enum.group_by(& &1.category)
    |> Enum.map(fn {category, prefs} -> {category, length(prefs)} end)
    |> Enum.into(%{})
  end

  defp group_by_time_period(preferences) do
    now = DateTime.utc_now()

    %{
      last_24_hours: count_in_period(preferences, now, :hour, 24),
      last_7_days: count_in_period(preferences, now, :day, 7),
      last_30_days: count_in_period(preferences, now, :day, 30)
    }
  end

  defp count_in_period(preferences, reference_time, unit, amount) do
    cutoff = DateTime.add(reference_time, -amount, unit)

    Enum.count(preferences, fn pref ->
      DateTime.compare(pref.inserted_at, cutoff) != :lt
    end)
  end

  defp calculate_override_complexity(preferences) do
    # Simple complexity metric based on number of overrides and categories
    category_count =
      preferences
      |> Enum.map(& &1.category)
      |> Enum.uniq()
      |> length()

    cond do
      length(preferences) < 5 -> :low
      length(preferences) < 15 && category_count < 4 -> :medium
      true -> :high
    end
  end

  defp generate_project_recommendations(preferences) do
    recommendations = []

    # Check for excessive overrides
    recommendations =
      if length(preferences) > 20 do
        recommendations ++
          [
            %{
              type: :excessive_overrides,
              message: "Consider using templates to reduce override count",
              priority: :medium
            }
          ]
      else
        recommendations
      end

    # Check for temporary overrides that should be permanent
    old_temporary =
      preferences
      |> Enum.filter(& &1.temporary)
      |> Enum.filter(&(DateTime.diff(DateTime.utc_now(), &1.inserted_at, :day) > 30))

    recommendations =
      if length(old_temporary) > 0 do
        recommendations ++
          [
            %{
              type: :promote_temporary,
              message: "Consider making long-running temporary overrides permanent",
              count: length(old_temporary),
              priority: :low
            }
          ]
      else
        recommendations
      end

    recommendations
  end

  defp get_preference_description(preference_key) do
    case SystemDefault.read() do
      {:ok, defaults} ->
        case Enum.find(defaults, &(&1.preference_key == preference_key)) do
          %{description: description} -> description
          nil -> "Unknown preference"
        end

      {:error, _} ->
        "Unable to retrieve description"
    end
  end

  defp calculate_average_per_project(preferences) do
    project_counts =
      preferences
      |> Enum.group_by(& &1.project_id)
      |> Enum.map(fn {_project_id, prefs} -> length(prefs) end)

    if length(project_counts) > 0 do
      Enum.sum(project_counts) / length(project_counts)
    else
      0.0
    end
  end

  # Placeholder functions for telemetry data (would be implemented with actual telemetry storage)
  # Would get from actual cache metrics
  defp get_cache_hit_rate, do: 85.5
  # Would get from telemetry data
  defp get_average_resolution_time, do: 1.2

  defp calculate_efficiency_score(cache_hit_rate, avg_resolution_time) do
    # Simple efficiency score calculation
    cache_score = cache_hit_rate
    # Lower time = higher score
    time_score = max(0, 100 - avg_resolution_time * 10)

    (cache_score + time_score) / 2
  end
end
