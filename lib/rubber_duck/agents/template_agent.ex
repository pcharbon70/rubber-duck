defmodule RubberDuck.Agents.TemplateAgent do
  @moduledoc """
  Template agent for autonomous preference template management.

  This agent manages template application, handles template versioning,
  tracks template usage analytics, and provides intelligent template
  recommendations based on user preferences and team patterns.
  """

  use Jido.Agent,
    name: "template_agent",
    description:
      "Autonomous template management with intelligent recommendations and usage analytics",
    category: "preferences",
    tags: ["templates", "recommendations", "analytics", "versioning"],
    vsn: "1.0.0"

  require Logger

  alias RubberDuck.Preferences.TemplateManager

  # Agent state fields are managed through direct state setting

  @doc """
  Create a new TemplateAgent.
  """
  def create_template_agent do
    with {:ok, agent} <- __MODULE__.new(),
         {:ok, agent} <-
           __MODULE__.set(agent,
             template_usage_stats: %{},
             recommendation_history: [],
             application_results: [],
             template_analytics: %{},
             version_tracking: %{},
             last_recommendation: DateTime.utc_now()
           ) do
      {:ok, agent}
    end
  end

  @doc """
  Apply template with intelligent conflict resolution and tracking.
  """
  def apply_template_intelligently(agent, template_id, target_id, target_type, applied_by_user_id) do
    start_time = System.monotonic_time(:millisecond)

    application_result =
      case target_type do
        :user ->
          TemplateManager.apply_template_to_user(template_id, target_id)

        :project ->
          TemplateManager.apply_template_to_project(template_id, target_id, applied_by_user_id)
      end

    application_time = System.monotonic_time(:millisecond) - start_time

    case application_result do
      {:ok, result} ->
        updated_agent =
          record_successful_application(
            agent,
            template_id,
            target_id,
            target_type,
            result,
            application_time
          )

        {:ok, result, updated_agent}

      {:error, reason} ->
        updated_agent =
          record_failed_application(agent, template_id, target_id, target_type, reason)

        {:error, reason, updated_agent}
    end
  end

  @doc """
  Generate intelligent template recommendations for a user.
  """
  def recommend_templates_for_user(agent, user_id) do
    case TemplateManager.get_template_recommendations(user_id) do
      {:ok, recommendations} ->
        enhanced_recommendations = enhance_recommendations_with_analytics(recommendations, agent)
        updated_agent = record_recommendation_generation(agent, user_id, enhanced_recommendations)

        {:ok, enhanced_recommendations, updated_agent}

      {:error, reason} ->
        Logger.warning("Failed to generate template recommendations: #{inspect(reason)}")
        {:error, reason, agent}
    end
  end

  @doc """
  Track template usage and update analytics.
  """
  def track_template_usage(agent, template_id, usage_context) do
    usage_entry = %{
      template_id: template_id,
      usage_context: usage_context,
      timestamp: DateTime.utc_now()
    }

    updated_agent = record_template_usage(agent, usage_entry)
    update_template_analytics(updated_agent, template_id)
  end

  @doc """
  Handle template versioning and migration.
  """
  def handle_template_version_update(agent, template_id, old_version, new_version) do
    version_entry = %{
      template_id: template_id,
      old_version: old_version,
      new_version: new_version,
      migration_timestamp: DateTime.utc_now(),
      affected_users: []
    }

    updated_tracking = Map.put(agent.version_tracking, template_id, version_entry)

    migration_suggestions = generate_migration_suggestions(template_id, old_version, new_version)

    {:ok, migration_suggestions, %{agent | version_tracking: updated_tracking}}
  end

  @doc """
  Generate template analytics and insights.
  """
  def generate_template_insights(agent) do
    insights = %{
      most_popular_templates: find_most_popular_templates(agent),
      application_success_rate: calculate_application_success_rate(agent),
      recommendation_effectiveness: analyze_recommendation_effectiveness(agent),
      template_categories_usage: analyze_template_categories(agent)
    }

    updated_analytics = Map.merge(agent.template_analytics, insights)

    {:ok, insights, %{agent | template_analytics: updated_analytics}}
  end

  # Private helper functions

  defp record_successful_application(
         agent,
         template_id,
         target_id,
         target_type,
         result,
         application_time
       ) do
    application_entry = %{
      template_id: template_id,
      target_id: target_id,
      target_type: target_type,
      result: result,
      application_time: application_time,
      timestamp: DateTime.utc_now(),
      status: :success
    }

    updated_results = add_to_application_results(agent.application_results, application_entry)
    updated_stats = update_template_usage_stats(agent.template_usage_stats, template_id, :success)

    %{agent | application_results: updated_results, template_usage_stats: updated_stats}
  end

  defp record_failed_application(agent, template_id, target_id, target_type, reason) do
    application_entry = %{
      template_id: template_id,
      target_id: target_id,
      target_type: target_type,
      reason: reason,
      timestamp: DateTime.utc_now(),
      status: :failed
    }

    updated_results = add_to_application_results(agent.application_results, application_entry)
    updated_stats = update_template_usage_stats(agent.template_usage_stats, template_id, :failed)

    %{agent | application_results: updated_results, template_usage_stats: updated_stats}
  end

  defp record_recommendation_generation(agent, user_id, recommendations) do
    recommendation_entry = %{
      user_id: user_id,
      recommendations: recommendations,
      timestamp: DateTime.utc_now(),
      count: length(recommendations)
    }

    updated_history =
      add_to_recommendation_history(agent.recommendation_history, recommendation_entry)

    %{agent | recommendation_history: updated_history, last_recommendation: DateTime.utc_now()}
  end

  defp enhance_recommendations_with_analytics(recommendations, agent) do
    Enum.map(recommendations, fn rec ->
      template_stats = Map.get(agent.template_usage_stats, rec.template.template_id, %{})

      Map.merge(rec, %{
        agent_confidence: calculate_recommendation_confidence(rec, template_stats),
        usage_analytics: template_stats,
        trending: template_trending?(rec.template.template_id, agent)
      })
    end)
  end

  defp record_template_usage(agent, usage_entry) do
    template_id = usage_entry.template_id

    current_stats =
      Map.get(agent.template_usage_stats, template_id, %{usage_count: 0, last_used: nil})

    updated_stats = %{
      usage_count: current_stats.usage_count + 1,
      last_used: usage_entry.timestamp,
      recent_contexts:
        [usage_entry.usage_context | Map.get(current_stats, :recent_contexts, [])] |> Enum.take(5)
    }

    updated_template_stats = Map.put(agent.template_usage_stats, template_id, updated_stats)

    %{agent | template_usage_stats: updated_template_stats}
  end

  defp update_template_analytics(agent, template_id) do
    current_analytics = Map.get(agent.template_analytics, template_id, %{})

    updated_analytics = %{
      total_applications: Map.get(current_analytics, :total_applications, 0) + 1,
      last_analysis: DateTime.utc_now(),
      performance_metrics: calculate_template_performance_metrics(agent, template_id)
    }

    updated_template_analytics = Map.put(agent.template_analytics, template_id, updated_analytics)

    %{agent | template_analytics: updated_template_analytics}
  end

  defp add_to_application_results(results, new_entry) do
    [new_entry | results] |> Enum.take(100)
  end

  defp add_to_recommendation_history(history, new_entry) do
    [new_entry | history] |> Enum.take(50)
  end

  defp update_template_usage_stats(stats, template_id, result) do
    current = Map.get(stats, template_id, %{success: 0, failed: 0, total: 0})

    updated =
      case result do
        :success -> %{current | success: current.success + 1, total: current.total + 1}
        :failed -> %{current | failed: current.failed + 1, total: current.total + 1}
      end

    Map.put(stats, template_id, updated)
  end

  defp calculate_recommendation_confidence(_recommendation, template_stats) do
    success_rate =
      if Map.get(template_stats, :total, 0) > 0 do
        Map.get(template_stats, :success, 0) / template_stats.total
      else
        0.5
      end

    min(success_rate + 0.3, 1.0)
  end

  defp template_trending?(template_id, agent) do
    recent_applications =
      agent.application_results
      |> Enum.filter(&(&1.template_id == template_id))
      |> Enum.filter(&(DateTime.diff(DateTime.utc_now(), &1.timestamp) < 86_400))

    length(recent_applications) >= 3
  end

  defp generate_migration_suggestions(_template_id, _old_version, _new_version) do
    [
      %{
        type: :version_migration,
        priority: :medium,
        message: "Template version updated",
        suggested_action: "Review changes and migrate affected applications"
      }
    ]
  end

  defp find_most_popular_templates(agent) do
    agent.template_usage_stats
    |> Enum.sort_by(fn {_id, stats} -> Map.get(stats, :usage_count, 0) end, :desc)
    |> Enum.take(5)
    |> Enum.map(&elem(&1, 0))
  end

  defp calculate_application_success_rate(agent) do
    if length(agent.application_results) > 0 do
      successful = Enum.count(agent.application_results, &(&1.status == :success))
      successful / length(agent.application_results)
    else
      1.0
    end
  end

  defp analyze_recommendation_effectiveness(agent) do
    if length(agent.recommendation_history) > 0 do
      avg_recommendations =
        agent.recommendation_history
        |> Enum.map(& &1.count)
        |> Enum.sum()
        |> div(length(agent.recommendation_history))

      %{average_recommendations_per_request: avg_recommendations}
    else
      %{average_recommendations_per_request: 0}
    end
  end

  defp analyze_template_categories(_agent) do
    # Placeholder for category analysis
    %{most_used_category: "system"}
  end

  defp calculate_template_performance_metrics(_agent, _template_id) do
    # Placeholder for performance metrics
    %{avg_application_time: 50, success_rate: 0.95}
  end
end
