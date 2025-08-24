defmodule RubberDuckWeb.API.AnalyticsController do
  @moduledoc """
  REST API controller for preference analytics and insights.

  Provides analytics endpoints for usage statistics, trends, and recommendations.
  """

  use RubberDuckWeb, :controller

  alias RubberDuck.Preferences.Resources.UserPreference

  action_fallback(RubberDuckWeb.API.FallbackController)

  @doc """
  Get usage statistics and patterns.

  Query parameters:
  - time_range: Time range for statistics (7d, 30d, 90d, 1y)
  - user_id: Get stats for specific user (defaults to current user)
  - project_id: Include project-specific stats
  - category: Filter by preference category
  """
  def usage(conn, params) do
    with {:ok, user} <- get_current_user(conn),
         {:ok, filters} <- parse_analytics_filters(params),
         {:ok, usage_stats} <- get_usage_statistics(user, filters) do
      render(conn, :usage, stats: usage_stats)
    end
  end

  @doc """
  Get preference usage trends over time.

  Query parameters:
  - time_range: Time range for trends (7d, 30d, 90d, 1y)  
  - user_id: Get trends for specific user (defaults to current user)
  - category: Filter by preference category
  - granularity: Data point granularity (hour, day, week, month)
  """
  def trends(conn, params) do
    with {:ok, user} <- get_current_user(conn),
         {:ok, filters} <- parse_trends_filters(params),
         {:ok, trend_data} <- get_trends_data(user, filters) do
      render(conn, :trends, trends: trend_data)
    end
  end

  @doc """
  Get AI-powered preference recommendations.

  Query parameters:
  - user_id: Get recommendations for specific user (defaults to current user)
  - project_id: Include project context for recommendations
  - category: Focus recommendations on specific category
  - limit: Maximum number of recommendations (default 10, max 50)
  """
  def recommendations(conn, params) do
    with {:ok, user} <- get_current_user(conn),
         {:ok, filters} <- parse_recommendations_filters(params),
         {:ok, recommendations} <- get_recommendations(user, filters) do
      render(conn, :recommendations, recommendations: recommendations)
    end
  end

  @doc """
  Get preference inheritance hierarchy analysis.

  Query parameters:
  - user_id: Analyze hierarchy for specific user (defaults to current user)
  - project_id: Include project-level analysis
  - category: Focus on specific category
  """
  def inheritance(conn, params) do
    with {:ok, user} <- get_current_user(conn),
         {:ok, filters} <- parse_inheritance_filters(params),
         {:ok, hierarchy_data} <- get_inheritance_analysis(user, filters) do
      render(conn, :inheritance, hierarchy: hierarchy_data)
    end
  end

  # Private helper functions

  defp get_current_user(conn) do
    case conn.assigns[:current_user] do
      nil -> {:error, :unauthorized}
      user -> {:ok, user}
    end
  end

  defp parse_analytics_filters(params) do
    filters = %{
      time_range: parse_time_range(params["time_range"]),
      user_id: params["user_id"],
      project_id: params["project_id"],
      category: params["category"]
    }

    {:ok, filters}
  end

  defp parse_trends_filters(params) do
    filters = %{
      time_range: parse_time_range(params["time_range"]),
      user_id: params["user_id"],
      category: params["category"],
      granularity: parse_granularity(params["granularity"])
    }

    {:ok, filters}
  end

  defp parse_recommendations_filters(params) do
    filters = %{
      user_id: params["user_id"],
      project_id: params["project_id"],
      category: params["category"],
      limit: min(parse_integer(params["limit"], 10), 50)
    }

    {:ok, filters}
  end

  defp parse_inheritance_filters(params) do
    filters = %{
      user_id: params["user_id"],
      project_id: params["project_id"],
      category: params["category"]
    }

    {:ok, filters}
  end

  defp parse_time_range(nil), do: "30d"
  defp parse_time_range(range) when range in ["7d", "30d", "90d", "1y"], do: range
  defp parse_time_range(_), do: "30d"

  defp parse_granularity(nil), do: "day"

  defp parse_granularity(granularity) when granularity in ["hour", "day", "week", "month"],
    do: granularity

  defp parse_granularity(_), do: "day"

  defp parse_integer(nil, default), do: default

  defp parse_integer(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_integer(int, _default) when is_integer(int), do: int
  defp parse_integer(_, default), do: default

  defp get_usage_statistics(user, filters) do
    target_user_id = filters.user_id || user.id

    # Mock analytics data - would integrate with actual AnalyticsManager
    stats = %{
      summary: %{
        total_preferences: get_total_preferences_count(target_user_id),
        user_overrides: get_user_overrides_count(target_user_id),
        recent_changes: get_recent_changes_count(target_user_id, filters.time_range),
        categories_used: get_categories_used_count(target_user_id)
      },
      category_distribution: get_category_distribution(target_user_id, filters.category),
      most_changed: get_most_changed_preferences(target_user_id, filters.time_range, 10),
      usage_patterns: get_usage_patterns(target_user_id, filters.time_range),
      time_range: filters.time_range
    }

    {:ok, stats}
  end

  defp get_trends_data(user, filters) do
    target_user_id = filters.user_id || user.id

    # Mock trends data - would integrate with actual time series analytics
    trends = %{
      time_series: generate_time_series_data(filters.time_range, filters.granularity),
      change_frequency: get_change_frequency_trend(target_user_id, filters.time_range),
      category_trends: get_category_trends(target_user_id, filters.category, filters.time_range),
      granularity: filters.granularity,
      time_range: filters.time_range
    }

    {:ok, trends}
  end

  defp get_recommendations(user, filters) do
    _target_user_id = filters.user_id || user.id

    # Mock recommendations - would integrate with AI recommendation engine
    recommendations =
      [
        %{
          id: "rec_1",
          type: "optimization",
          preference_key: "code_quality.global.enabled",
          current_value: "false",
          recommended_value: "true",
          reason:
            "Based on your project type and team preferences, enabling global code quality checks would improve your code standards",
          confidence: 0.85,
          impact: "high",
          category: "code_quality"
        },
        %{
          id: "rec_2",
          type: "cost_optimization",
          preference_key: "llm.providers.primary",
          current_value: "anthropic",
          recommended_value: "openai",
          reason:
            "OpenAI models might be more cost-effective for your usage patterns while maintaining similar quality",
          confidence: 0.72,
          impact: "medium",
          category: "llm"
        },
        %{
          id: "rec_3",
          type: "performance",
          preference_key: "ml.training.batch_size",
          current_value: "32",
          recommended_value: "64",
          reason:
            "Increasing batch size could improve training performance based on your hardware specs",
          confidence: 0.68,
          impact: "low",
          category: "ml"
        }
      ]
      |> Enum.take(filters.limit)

    {:ok,
     %{
       recommendations: recommendations,
       total: length(recommendations),
       generated_at: DateTime.utc_now()
     }}
  end

  defp get_inheritance_analysis(user, filters) do
    target_user_id = filters.user_id || user.id

    # Mock inheritance analysis - would analyze actual preference hierarchy
    hierarchy = %{
      summary: %{
        system_defaults: 45,
        user_overrides: 12,
        project_overrides: 3,
        effective_preferences: 60
      },
      inheritance_tree:
        build_inheritance_tree(target_user_id, filters.project_id, filters.category),
      override_analysis: %{
        most_overridden_categories: ["code_quality", "llm", "performance"],
        override_percentage: 26.7,
        inheritance_depth: %{
          system_only: 33,
          user_override: 12,
          project_override: 3
        }
      },
      recommendations: [
        %{
          type: "consolidation",
          message: "Consider creating a template from your current user overrides",
          action: "create_template"
        }
      ]
    }

    {:ok, hierarchy}
  end

  # Mock data generation functions

  defp get_total_preferences_count(_user_id) do
    45
  end

  defp get_user_overrides_count(user_id) do
    case UserPreference.by_user_id(user_id) do
      {:ok, preferences} -> length(preferences)
      _ -> 0
    end
  end

  defp get_recent_changes_count(_user_id, time_range) do
    case time_range do
      "7d" -> 5
      "30d" -> 18
      "90d" -> 42
      "1y" -> 156
      _ -> 18
    end
  end

  defp get_categories_used_count(user_id) do
    case UserPreference.by_user_id(user_id) do
      {:ok, preferences} ->
        preferences
        |> Enum.map(& &1.category)
        |> Enum.uniq()
        |> length()

      _ ->
        0
    end
  end

  defp get_category_distribution(_user_id, _filter_category) do
    [
      %{category: "code_quality", count: 8, percentage: 33.3},
      %{category: "llm", count: 6, percentage: 25.0},
      %{category: "ml", count: 4, percentage: 16.7},
      %{category: "budgeting", count: 3, percentage: 12.5},
      %{category: "performance", count: 3, percentage: 12.5}
    ]
  end

  defp get_most_changed_preferences(_user_id, time_range, limit) do
    base_changes = [
      %{key: "code_quality.global.enabled", category: "code_quality", changes: 8},
      %{key: "llm.providers.primary", category: "llm", changes: 6},
      %{key: "ml.training.learning_rate", category: "ml", changes: 4},
      %{key: "budgeting.monthly_limit", category: "budgeting", changes: 3},
      %{key: "performance.cache.enabled", category: "performance", changes: 2}
    ]

    # Adjust based on time range
    multiplier =
      case time_range do
        "7d" -> 0.3
        "30d" -> 1.0
        "90d" -> 2.5
        "1y" -> 8.0
        _ -> 1.0
      end

    base_changes
    |> Enum.map(&Map.update!(&1, :changes, fn c -> trunc(c * multiplier) end))
    |> Enum.take(limit)
  end

  defp get_usage_patterns(_user_id, _time_range) do
    %{
      peak_hours: [9, 10, 14, 15, 16],
      most_active_days: ["monday", "tuesday", "wednesday"],
      change_triggers: ["project_start", "team_feedback", "performance_issues"]
    }
  end

  defp generate_time_series_data(time_range, granularity) do
    points = calculate_time_series_points(time_range, granularity)
    time_interval = calculate_time_interval(granularity)

    now = DateTime.utc_now()

    0..(points - 1)
    |> Enum.map(&build_time_series_point(now, &1, time_interval))
    |> Enum.reverse()
  end

  defp calculate_time_series_points(time_range, granularity) do
    case {time_range, granularity} do
      {"7d", "hour"} -> 168
      {"7d", "day"} -> 7
      {"30d", "day"} -> 30
      {"30d", "week"} -> 4
      {"90d", "week"} -> 13
      {"1y", "month"} -> 12
      _ -> 30
    end
  end

  defp calculate_time_interval(granularity) do
    case granularity do
      "hour" -> 3600
      "day" -> 86_400
      "week" -> 604_800
      "month" -> 2_592_000
      _ -> 86_400
    end
  end

  defp build_time_series_point(base_time, index, interval) do
    %{
      timestamp: DateTime.add(base_time, -index * interval, :second),
      changes: :rand.uniform(10),
      unique_preferences: :rand.uniform(25) + 5
    }
  end

  defp get_change_frequency_trend(_user_id, _time_range) do
    %{
      average_changes_per_day: 1.2,
      peak_change_day: "monday",
      # "increasing", "decreasing", "stable"
      trend_direction: "stable"
    }
  end

  defp get_category_trends(_user_id, filter_category, _time_range) do
    all_trends = %{
      "code_quality" => %{direction: "increasing", change_rate: 0.15},
      "llm" => %{direction: "stable", change_rate: 0.02},
      "ml" => %{direction: "increasing", change_rate: 0.08},
      "budgeting" => %{direction: "decreasing", change_rate: -0.05},
      "performance" => %{direction: "stable", change_rate: 0.01}
    }

    if filter_category do
      Map.take(all_trends, [filter_category])
    else
      all_trends
    end
  end

  defp build_inheritance_tree(_user_id, project_id, category_filter) do
    # Mock inheritance tree structure
    base_preferences = [
      %{
        key: "code_quality.global.enabled",
        category: "code_quality",
        system_value: false,
        user_value: true,
        project_value: nil,
        effective_value: true,
        source: "user"
      },
      %{
        key: "llm.providers.primary",
        category: "llm",
        system_value: "openai",
        user_value: "anthropic",
        project_value: project_id && "claude",
        effective_value: (project_id && "claude") || "anthropic",
        source: (project_id && "project") || "user"
      }
    ]

    if category_filter do
      Enum.filter(base_preferences, &(&1.category == category_filter))
    else
      base_preferences
    end
  end
end
