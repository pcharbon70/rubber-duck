defmodule RubberDuckWeb.API.AnalyticsJSON do
  @moduledoc """
  JSON views for the Analytics API controller.
  """

  @doc """
  Renders usage statistics.
  """
  def usage(%{stats: stats}) do
    %{
      data: %{
        summary: stats.summary,
        category_distribution: stats.category_distribution,
        most_changed: stats.most_changed,
        usage_patterns: stats.usage_patterns,
        time_range: stats.time_range
      },
      meta: %{
        generated_at: DateTime.utc_now(),
        type: "usage_statistics"
      }
    }
  end

  @doc """
  Renders trend data.
  """
  def trends(%{trends: trends}) do
    %{
      data: %{
        time_series: trends.time_series,
        change_frequency: trends.change_frequency,
        category_trends: trends.category_trends,
        granularity: trends.granularity,
        time_range: trends.time_range
      },
      meta: %{
        generated_at: DateTime.utc_now(),
        type: "trend_analysis",
        data_points: length(trends.time_series)
      }
    }
  end

  @doc """
  Renders AI recommendations.
  """
  def recommendations(%{recommendations: recommendations}) do
    %{
      data: %{
        recommendations: recommendations.recommendations,
        total: recommendations.total,
        generated_at: recommendations.generated_at
      },
      meta: %{
        type: "ai_recommendations",
        timestamp: DateTime.utc_now()
      }
    }
  end

  @doc """
  Renders inheritance hierarchy analysis.
  """
  def inheritance(%{hierarchy: hierarchy}) do
    %{
      data: %{
        summary: hierarchy.summary,
        inheritance_tree: hierarchy.inheritance_tree,
        override_analysis: hierarchy.override_analysis,
        recommendations: hierarchy.recommendations
      },
      meta: %{
        generated_at: DateTime.utc_now(),
        type: "inheritance_analysis"
      }
    }
  end
end
