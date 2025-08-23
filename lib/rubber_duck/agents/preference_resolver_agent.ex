defmodule RubberDuck.Agents.PreferenceResolverAgent do
  @moduledoc """
  Preference resolver agent for autonomous preference resolution with hierarchy management.

  This agent provides intelligent preference resolution with caching optimization,
  missing preference handling, and proactive cache warming based on usage patterns.
  Integrates with the existing PreferenceResolver while adding autonomous intelligence.
  """

  use Jido.Agent,
    name: "preference_resolver_agent",
    description:
      "Autonomous preference resolution with hierarchy management and caching optimization",
    category: "preferences",
    tags: ["resolution", "caching", "hierarchy", "optimization"],
    vsn: "1.0.0"

  require Logger

  alias RubberDuck.Preferences.{CacheManager, PreferenceResolver}

  # Agent state fields are managed through direct state setting

  @doc """
  Create a new PreferenceResolverAgent for a user and optional project.
  """
  def create_for_context(user_id, project_id \\ nil) do
    with {:ok, agent} <- __MODULE__.new(),
         {:ok, agent} <-
           __MODULE__.set(agent,
             user_id: user_id,
             project_id: project_id,
             cache_stats: %{hits: 0, misses: 0, total_requests: 0},
             resolution_history: [],
             optimization_suggestions: [],
             cache_warming_patterns: %{},
             last_activity: DateTime.utc_now()
           ) do
      {:ok, agent}
    end
  end

  @doc """
  Resolve a preference with intelligent caching and optimization.
  """
  def resolve_preference(agent, preference_key) do
    start_time = System.monotonic_time(:millisecond)

    case PreferenceResolver.resolve(agent.user_id, preference_key, agent.project_id) do
      {:ok, value} ->
        resolution_time = System.monotonic_time(:millisecond) - start_time

        updated_agent =
          record_successful_resolution(agent, preference_key, value, resolution_time)

        {:ok, value, updated_agent}

      {:error, reason} ->
        updated_agent = record_failed_resolution(agent, preference_key, reason)
        {:error, reason, updated_agent}
    end
  end

  @doc """
  Resolve multiple preferences in batch with optimization.
  """
  def resolve_preferences_batch(agent, preference_keys) do
    start_time = System.monotonic_time(:millisecond)

    case PreferenceResolver.resolve_batch(agent.user_id, preference_keys, agent.project_id) do
      {:ok, resolved_preferences} ->
        resolution_time = System.monotonic_time(:millisecond) - start_time

        updated_agent =
          record_batch_resolution(agent, preference_keys, resolved_preferences, resolution_time)

        {:ok, resolved_preferences, updated_agent}

      {:error, reason} ->
        updated_agent = record_batch_failure(agent, preference_keys, reason)
        {:error, reason, updated_agent}
    end
  end

  @doc """
  Perform intelligent cache warming based on usage patterns.
  """
  def warm_cache(agent) do
    warming_candidates = identify_cache_warming_candidates(agent)

    if length(warming_candidates) > 0 do
      Logger.info(
        "PreferenceResolverAgent warming cache for #{length(warming_candidates)} preferences"
      )

      case CacheManager.warm_cache(agent.user_id, warming_candidates, agent.project_id) do
        :ok ->
          updated_agent = record_cache_warming(agent, warming_candidates)
          {:ok, updated_agent}

        {:error, reason} ->
          Logger.warning("Cache warming failed: #{inspect(reason)}")
          {:error, reason, agent}
      end
    else
      {:ok, agent}
    end
  end

  @doc """
  Generate optimization suggestions based on usage patterns.
  """
  def generate_optimization_suggestions(agent) do
    suggestions = []

    suggestions = suggestions ++ analyze_cache_performance(agent)
    suggestions = suggestions ++ analyze_resolution_patterns(agent)
    suggestions = suggestions ++ analyze_preference_usage(agent)

    updated_agent = %{agent | optimization_suggestions: suggestions}
    {:ok, suggestions, updated_agent}
  end

  @doc """
  Handle missing preference by suggesting defaults or alternatives.
  """
  def handle_missing_preference(agent, preference_key) do
    suggestion = generate_missing_preference_suggestion(preference_key)

    updated_agent = record_missing_preference_handling(agent, preference_key, suggestion)
    {:ok, suggestion, updated_agent}
  end

  # Private helper functions

  defp record_successful_resolution(agent, preference_key, value, resolution_time) do
    new_stats = update_cache_stats(agent.cache_stats, :hit)

    new_history_entry = %{
      preference_key: preference_key,
      value: value,
      resolution_time: resolution_time,
      timestamp: DateTime.utc_now(),
      status: :success
    }

    updated_history = add_to_resolution_history(agent.resolution_history, new_history_entry)

    %{
      agent
      | cache_stats: new_stats,
        resolution_history: updated_history,
        last_activity: DateTime.utc_now()
    }
  end

  defp record_failed_resolution(agent, preference_key, reason) do
    new_stats = update_cache_stats(agent.cache_stats, :miss)

    new_history_entry = %{
      preference_key: preference_key,
      reason: reason,
      timestamp: DateTime.utc_now(),
      status: :failed
    }

    updated_history = add_to_resolution_history(agent.resolution_history, new_history_entry)

    %{
      agent
      | cache_stats: new_stats,
        resolution_history: updated_history,
        last_activity: DateTime.utc_now()
    }
  end

  defp record_batch_resolution(agent, preference_keys, resolved_preferences, resolution_time) do
    successful_count = map_size(resolved_preferences)
    failed_count = length(preference_keys) - successful_count

    new_stats =
      agent.cache_stats
      |> update_cache_stats_count(:hit, successful_count)
      |> update_cache_stats_count(:miss, failed_count)

    new_history_entry = %{
      batch_keys: preference_keys,
      resolved_count: successful_count,
      failed_count: failed_count,
      resolution_time: resolution_time,
      timestamp: DateTime.utc_now(),
      status: :batch_success
    }

    updated_history = add_to_resolution_history(agent.resolution_history, new_history_entry)

    %{
      agent
      | cache_stats: new_stats,
        resolution_history: updated_history,
        last_activity: DateTime.utc_now()
    }
  end

  defp record_batch_failure(agent, preference_keys, reason) do
    new_stats = update_cache_stats_count(agent.cache_stats, :miss, length(preference_keys))

    new_history_entry = %{
      batch_keys: preference_keys,
      reason: reason,
      timestamp: DateTime.utc_now(),
      status: :batch_failed
    }

    updated_history = add_to_resolution_history(agent.resolution_history, new_history_entry)

    %{
      agent
      | cache_stats: new_stats,
        resolution_history: updated_history,
        last_activity: DateTime.utc_now()
    }
  end

  defp update_cache_stats(stats, result) do
    case result do
      :hit ->
        %{stats | hits: stats.hits + 1, total_requests: stats.total_requests + 1}

      :miss ->
        %{stats | misses: stats.misses + 1, total_requests: stats.total_requests + 1}
    end
  end

  defp update_cache_stats_count(stats, result, count) do
    case result do
      :hit ->
        %{stats | hits: stats.hits + count, total_requests: stats.total_requests + count}

      :miss ->
        %{stats | misses: stats.misses + count, total_requests: stats.total_requests + count}
    end
  end

  defp add_to_resolution_history(history, new_entry) do
    updated_history = [new_entry | history]

    # Keep only last 100 entries for performance
    Enum.take(updated_history, 100)
  end

  defp identify_cache_warming_candidates(agent) do
    # Analyze resolution history to find frequently accessed preferences
    agent.resolution_history
    |> Enum.filter(&(&1.status == :success))
    |> Enum.map(& &1.preference_key)
    |> Enum.frequencies()
    |> Enum.filter(fn {_key, count} -> count >= 3 end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.take(10)
  end

  defp record_cache_warming(agent, warmed_keys) do
    new_warming_entry = %{
      keys: warmed_keys,
      timestamp: DateTime.utc_now(),
      count: length(warmed_keys)
    }

    updated_patterns =
      Map.put(agent.cache_warming_patterns, DateTime.utc_now(), new_warming_entry)

    %{agent | cache_warming_patterns: updated_patterns}
  end

  defp analyze_cache_performance(agent) do
    stats = agent.cache_stats

    if stats.total_requests > 10 do
      hit_rate = stats.hits / stats.total_requests

      if hit_rate < 0.8 do
        [
          %{
            type: :cache_performance,
            priority: :medium,
            message:
              "Cache hit rate is #{Float.round(hit_rate * 100, 1)}%, consider cache warming",
            suggested_action: "Enable automatic cache warming for frequently accessed preferences"
          }
        ]
      else
        []
      end
    else
      []
    end
  end

  defp analyze_resolution_patterns(agent) do
    recent_history =
      agent.resolution_history
      |> Enum.take(50)
      |> Enum.filter(&(&1.status == :success))

    if length(recent_history) > 20 do
      avg_resolution_time =
        recent_history
        |> Enum.map(&Map.get(&1, :resolution_time, 0))
        |> Enum.sum()
        |> div(length(recent_history))

      if avg_resolution_time > 100 do
        [
          %{
            type: :performance,
            priority: :high,
            message: "Average resolution time is #{avg_resolution_time}ms, consider optimization",
            suggested_action:
              "Review preference hierarchy complexity or enable additional caching"
          }
        ]
      else
        []
      end
    else
      []
    end
  end

  defp analyze_preference_usage(agent) do
    # Analyze preference usage patterns for optimization suggestions
    frequently_used =
      agent.resolution_history
      |> Enum.filter(&(&1.status == :success))
      |> Enum.map(& &1.preference_key)
      |> Enum.frequencies()
      |> Enum.filter(fn {_key, count} -> count >= 5 end)

    if length(frequently_used) > 10 do
      [
        %{
          type: :usage_pattern,
          priority: :low,
          message: "#{length(frequently_used)} preferences accessed frequently",
          suggested_action: "Consider creating a custom template with your most-used preferences"
        }
      ]
    else
      []
    end
  end

  defp generate_missing_preference_suggestion(preference_key) do
    category = get_preference_category(preference_key)

    %{
      preference_key: preference_key,
      suggestion_type: :missing_preference,
      suggested_action: "Create #{category} preference or use system default",
      priority: :medium,
      timestamp: DateTime.utc_now()
    }
  end

  defp record_missing_preference_handling(agent, preference_key, suggestion) do
    new_history_entry = %{
      preference_key: preference_key,
      suggestion: suggestion,
      timestamp: DateTime.utc_now(),
      status: :missing_handled
    }

    updated_history = add_to_resolution_history(agent.resolution_history, new_history_entry)

    %{agent | resolution_history: updated_history}
  end

  defp get_preference_category(preference_key) do
    preference_key
    |> String.split(".")
    |> hd()
  end
end
