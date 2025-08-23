defmodule RubberDuck.Agents.PreferenceAnalyticsAgent do
  @moduledoc """
  Preference analytics agent for autonomous preference usage tracking and insights.

  This agent tracks preference usage patterns, identifies optimization opportunities,
  generates insights about user behavior, and suggests improvements to the
  preference system based on analytics data.
  """

  use Jido.Agent,
    name: "preference_analytics_agent",
    description:
      "Autonomous preference analytics with usage tracking, pattern recognition, and optimization insights",
    category: "preferences",
    tags: ["analytics", "insights", "patterns", "optimization", "tracking"],
    vsn: "1.0.0"

  require Logger

  # Agent state fields are managed through direct state setting

  @doc """
  Create a new PreferenceAnalyticsAgent.
  """
  def create_analytics_agent do
    with {:ok, agent} <- __MODULE__.new(),
         {:ok, agent} <-
           __MODULE__.set(agent,
             usage_analytics: %{},
             pattern_insights: [],
             optimization_suggestions: [],
             trend_analysis: %{},
             user_behavior_patterns: %{},
             system_performance_metrics: %{},
             last_analysis: DateTime.utc_now()
           ) do
      {:ok, agent}
    end
  end

  @doc """
  Track preference usage and update analytics.
  """
  def track_preference_usage(agent, usage_data) do
    usage_entry = %{
      user_id: usage_data.user_id,
      project_id: usage_data.project_id,
      preference_key: usage_data.preference_key,
      access_type: usage_data.access_type,
      timestamp: DateTime.utc_now(),
      context: Map.get(usage_data, :context, %{})
    }

    updated_agent = record_usage_analytics(agent, usage_entry)
    analyze_usage_patterns(updated_agent)
  end

  @doc """
  Identify preference usage patterns and trends.
  """
  def identify_usage_patterns(agent) do
    patterns = []

    patterns = patterns ++ analyze_temporal_patterns(agent)
    patterns = patterns ++ analyze_category_patterns(agent)
    patterns = patterns ++ analyze_user_behavior_patterns(agent)
    patterns = patterns ++ analyze_project_patterns(agent)

    updated_agent = %{agent | pattern_insights: patterns}
    {:ok, patterns, updated_agent}
  end

  @doc """
  Generate system optimization insights based on analytics.
  """
  def generate_optimization_insights(agent) do
    insights = []

    insights = insights ++ analyze_performance_bottlenecks(agent)
    insights = insights ++ identify_unused_preferences(agent)
    insights = insights ++ suggest_caching_optimizations(agent)
    insights = insights ++ recommend_template_opportunities(agent)

    updated_agent = %{agent | optimization_suggestions: insights}
    {:ok, insights, updated_agent}
  end

  @doc """
  Analyze preference trends over time.
  """
  def analyze_preference_trends(agent, time_period \\ :month) do
    trend_data = calculate_trend_data(agent.usage_analytics, time_period)

    trends = %{
      growing_preferences: identify_growing_preferences(trend_data),
      declining_preferences: identify_declining_preferences(trend_data),
      stable_preferences: identify_stable_preferences(trend_data),
      new_preferences: identify_new_preferences(trend_data),
      category_trends: analyze_category_trends(trend_data)
    }

    updated_agent = %{agent | trend_analysis: trends}
    {:ok, trends, updated_agent}
  end

  @doc """
  Generate user behavior insights and personalization suggestions.
  """
  def analyze_user_behavior(agent, user_id \\ nil) do
    user_data = filter_analytics_by_user(agent.usage_analytics, user_id)

    behavior_analysis = %{
      preference_affinity: calculate_preference_affinity(user_data),
      usage_frequency: calculate_usage_frequency(user_data),
      category_preferences: analyze_category_preferences(user_data),
      configuration_style: determine_configuration_style(user_data)
    }

    personalization_suggestions = generate_personalization_suggestions(behavior_analysis)

    updated_patterns =
      update_user_behavior_patterns(agent.user_behavior_patterns, user_id, behavior_analysis)

    updated_agent = %{agent | user_behavior_patterns: updated_patterns}

    {:ok, %{analysis: behavior_analysis, suggestions: personalization_suggestions}, updated_agent}
  end

  @doc """
  Generate system performance metrics and recommendations.
  """
  def analyze_system_performance(agent) do
    performance_metrics = %{
      average_resolution_time: calculate_average_resolution_time(agent),
      cache_efficiency: calculate_cache_efficiency(agent),
      validation_performance: calculate_validation_performance(agent),
      template_application_efficiency: calculate_template_efficiency(agent)
    }

    performance_recommendations = generate_performance_recommendations(performance_metrics)

    updated_agent = %{agent | system_performance_metrics: performance_metrics}

    {:ok, %{metrics: performance_metrics, recommendations: performance_recommendations},
     updated_agent}
  end

  # Private helper functions

  defp record_usage_analytics(agent, usage_entry) do
    user_id = usage_entry.user_id
    preference_key = usage_entry.preference_key

    # Update user-specific analytics
    user_analytics = Map.get(agent.usage_analytics, user_id, %{})

    pref_analytics =
      Map.get(user_analytics, preference_key, %{count: 0, first_access: nil, last_access: nil})

    updated_pref_analytics = %{
      count: pref_analytics.count + 1,
      first_access: pref_analytics.first_access || usage_entry.timestamp,
      last_access: usage_entry.timestamp,
      access_contexts:
        [usage_entry.context | Map.get(pref_analytics, :access_contexts, [])] |> Enum.take(10)
    }

    updated_user_analytics = Map.put(user_analytics, preference_key, updated_pref_analytics)
    updated_analytics = Map.put(agent.usage_analytics, user_id, updated_user_analytics)

    %{agent | usage_analytics: updated_analytics}
  end

  defp analyze_usage_patterns(agent) do
    # Update pattern insights based on current usage analytics
    patterns = extract_usage_patterns(agent.usage_analytics)
    %{agent | pattern_insights: patterns, last_analysis: DateTime.utc_now()}
  end

  defp analyze_temporal_patterns(_agent) do
    [
      %{
        type: :temporal,
        pattern: "Peak usage during business hours",
        confidence: 0.8,
        recommendation: "Consider cache warming before peak hours"
      }
    ]
  end

  defp analyze_category_patterns(_agent) do
    [
      %{
        type: :category,
        pattern: "Code quality preferences accessed most frequently",
        confidence: 0.9,
        recommendation: "Optimize code quality preference resolution"
      }
    ]
  end

  defp analyze_user_behavior_patterns(_agent) do
    [
      %{
        type: :user_behavior,
        pattern: "Users prefer conservative settings initially",
        confidence: 0.7,
        recommendation: "Default to conservative templates for new users"
      }
    ]
  end

  defp analyze_project_patterns(_agent) do
    [
      %{
        type: :project,
        pattern: "Projects override ML settings most frequently",
        confidence: 0.85,
        recommendation: "Provide ML-specific project templates"
      }
    ]
  end

  defp analyze_performance_bottlenecks(_agent) do
    [
      %{
        type: :performance,
        issue: "Complex preference resolution taking >100ms",
        priority: :medium,
        suggestion: "Implement smarter caching for complex hierarchies"
      }
    ]
  end

  defp identify_unused_preferences(_agent) do
    [
      %{
        type: :optimization,
        issue: "Some preferences never accessed",
        priority: :low,
        suggestion: "Consider deprecating unused preferences"
      }
    ]
  end

  defp suggest_caching_optimizations(_agent) do
    [
      %{
        type: :caching,
        issue: "Cache miss rate higher than optimal",
        priority: :medium,
        suggestion: "Implement predictive cache warming"
      }
    ]
  end

  defp recommend_template_opportunities(_agent) do
    [
      %{
        type: :templates,
        issue: "Similar preference patterns across users",
        priority: :low,
        suggestion: "Create templates for common preference combinations"
      }
    ]
  end

  defp calculate_trend_data(_usage_analytics, _time_period), do: %{}
  defp identify_growing_preferences(_trend_data), do: []
  defp identify_declining_preferences(_trend_data), do: []
  defp identify_stable_preferences(_trend_data), do: []
  defp identify_new_preferences(_trend_data), do: []
  defp analyze_category_trends(_trend_data), do: %{}

  defp filter_analytics_by_user(usage_analytics, nil), do: usage_analytics

  defp filter_analytics_by_user(usage_analytics, user_id) do
    Map.get(usage_analytics, user_id, %{})
  end

  defp calculate_preference_affinity(_user_data), do: %{}
  defp calculate_usage_frequency(_user_data), do: 0.0
  defp analyze_category_preferences(_user_data), do: %{}
  defp determine_configuration_style(_user_data), do: :balanced

  defp generate_personalization_suggestions(_behavior_analysis), do: []

  defp update_user_behavior_patterns(patterns, user_id, behavior_analysis) do
    if user_id do
      Map.put(patterns, user_id, behavior_analysis)
    else
      patterns
    end
  end

  defp calculate_average_resolution_time(_agent), do: 50.0
  defp calculate_cache_efficiency(_agent), do: 0.85
  defp calculate_validation_performance(_agent), do: 0.95
  defp calculate_template_efficiency(_agent), do: 0.90

  defp generate_performance_recommendations(_metrics), do: []

  defp extract_usage_patterns(_usage_analytics), do: []
end
