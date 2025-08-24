defmodule RubberDuck.Agents.UserConfigAgent do
  @moduledoc """
  User configuration agent for autonomous user preference management.

  This agent manages user preferences, tracks preference usage patterns,
  suggests optimizations, and provides intelligent default recommendations
  based on user behavior and system analytics.
  """

  use Jido.Agent,
    name: "user_config_agent",
    description:
      "Autonomous user preference management with usage tracking and optimization suggestions",
    category: "preferences",
    tags: ["user", "configuration", "optimization", "personalization"],
    vsn: "1.0.0"

  require Logger

  # Agent state fields are managed through direct state setting

  @doc """
  Create a new UserConfigAgent for a user.
  """
  def create_for_user(user_id) do
    with {:ok, agent} <- __MODULE__.new(),
         {:ok, agent} <-
           __MODULE__.set(agent,
             user_id: user_id,
             preference_usage: %{},
             optimization_history: [],
             personalization_insights: %{},
             default_suggestions: [],
             last_optimization: DateTime.utc_now(),
             usage_patterns: %{}
           ) do
      {:ok, agent}
    end
  end

  @doc """
  Track user preference access and learn usage patterns.
  """
  def track_preference_usage(agent, preference_key, access_context \\ %{}) do
    usage_entry = %{
      preference_key: preference_key,
      access_time: DateTime.utc_now(),
      context: access_context
    }

    updated_agent = record_preference_usage(agent, usage_entry)
    analyze_usage_patterns(updated_agent)
  end

  @doc """
  Generate personalized preference suggestions for user.
  """
  def generate_user_suggestions(agent) do
    suggestions = []

    suggestions = suggestions ++ analyze_missing_preferences(agent)
    suggestions = suggestions ++ suggest_commonly_used_defaults(agent)
    suggestions = suggestions ++ recommend_optimization_opportunities(agent)

    updated_agent = %{agent | default_suggestions: suggestions}
    {:ok, suggestions, updated_agent}
  end

  @doc """
  Suggest optimal default values based on user patterns.
  """
  def suggest_optimal_defaults(agent, category \\ nil) do
    usage_data = filter_usage_by_category(agent.preference_usage, category)

    optimal_defaults = calculate_optimal_defaults(usage_data)
    confidence_scores = calculate_suggestion_confidence(optimal_defaults, usage_data)

    suggestions = format_default_suggestions(optimal_defaults, confidence_scores)

    {:ok, suggestions, agent}
  end

  @doc """
  Analyze user preference consistency and suggest improvements.
  """
  def analyze_preference_consistency(agent) do
    consistency_analysis = %{
      contradictory_preferences: find_contradictory_preferences(agent),
      unused_preferences: find_unused_preferences(agent),
      optimization_opportunities: find_optimization_opportunities(agent)
    }

    improvements = generate_consistency_improvements(consistency_analysis)

    {:ok, %{analysis: consistency_analysis, improvements: improvements}, agent}
  end

  @doc """
  Learn from user behavior and update personalization insights.
  """
  def update_personalization_insights(agent, behavior_data) do
    insight_entry = %{
      behavior_type: behavior_data.type,
      patterns: behavior_data.patterns,
      timestamp: DateTime.utc_now()
    }

    updated_insights =
      add_to_personalization_insights(agent.personalization_insights, insight_entry)

    %{agent | personalization_insights: updated_insights}
  end

  # Private helper functions

  defp record_preference_usage(agent, usage_entry) do
    preference_key = usage_entry.preference_key

    current_usage =
      Map.get(agent.preference_usage, preference_key, %{count: 0, last_access: nil, contexts: []})

    updated_usage = %{
      count: current_usage.count + 1,
      last_access: usage_entry.access_time,
      contexts: [usage_entry.context | current_usage.contexts] |> Enum.take(10)
    }

    updated_preference_usage = Map.put(agent.preference_usage, preference_key, updated_usage)

    %{agent | preference_usage: updated_preference_usage}
  end

  defp analyze_usage_patterns(agent) do
    patterns = %{
      most_accessed: find_most_accessed_preferences(agent.preference_usage),
      access_frequency: calculate_access_frequency(agent.preference_usage),
      category_distribution: calculate_category_distribution(agent.preference_usage),
      temporal_patterns: analyze_temporal_patterns(agent.preference_usage)
    }

    %{agent | usage_patterns: patterns}
  end

  defp analyze_missing_preferences(agent) do
    # Analyze which common preferences the user hasn't configured
    common_preferences = get_common_preference_keys()
    user_preferences = Map.keys(agent.preference_usage)

    missing = common_preferences -- user_preferences

    Enum.map(missing, fn pref_key ->
      %{
        type: :missing_preference,
        preference_key: pref_key,
        priority: :low,
        message: "Consider configuring #{pref_key} for better experience",
        suggested_action: "Set up #{get_preference_category(pref_key)} preferences"
      }
    end)
  end

  defp suggest_commonly_used_defaults(agent) do
    frequently_used =
      agent.preference_usage
      |> Enum.filter(fn {_key, usage} -> usage.count >= 5 end)
      |> Enum.map(&elem(&1, 0))

    if length(frequently_used) > 5 do
      [
        %{
          type: :template_suggestion,
          priority: :medium,
          message: "You have #{length(frequently_used)} frequently used preferences",
          suggested_action: "Consider creating a personal template with your common preferences"
        }
      ]
    else
      []
    end
  end

  defp recommend_optimization_opportunities(agent) do
    slow_categories = find_slow_resolving_categories(agent.preference_usage)

    Enum.map(slow_categories, fn category ->
      %{
        type: :performance_optimization,
        category: category,
        priority: :medium,
        message: "#{category} preferences resolving slowly",
        suggested_action: "Consider caching or simplifying #{category} preference hierarchy"
      }
    end)
  end

  defp filter_usage_by_category(usage_data, nil), do: usage_data

  defp filter_usage_by_category(usage_data, category) do
    Enum.filter(usage_data, fn {key, _usage} ->
      get_preference_category(key) == category
    end)
  end

  defp calculate_optimal_defaults(usage_data) do
    # Calculate optimal default values based on usage patterns
    usage_data
    |> Enum.map(fn {key, usage} ->
      # This would analyze actual preference values to suggest optimal defaults
      {key, suggest_default_for_preference(key, usage)}
    end)
    |> Map.new()
  end

  defp calculate_suggestion_confidence(optimal_defaults, usage_data) do
    Map.new(optimal_defaults, fn {key, _value} ->
      usage = Map.get(usage_data, key, %{count: 0})
      confidence = min(usage.count / 10.0, 1.0)
      {key, confidence}
    end)
  end

  defp format_default_suggestions(optimal_defaults, confidence_scores) do
    Enum.map(optimal_defaults, fn {key, value} ->
      confidence = Map.get(confidence_scores, key, 0.0)

      %{
        preference_key: key,
        suggested_value: value,
        confidence: confidence,
        reason: "Based on your usage patterns"
      }
    end)
  end

  defp find_contradictory_preferences(_agent), do: []
  defp find_unused_preferences(_agent), do: []
  defp find_optimization_opportunities(_agent), do: []
  defp generate_consistency_improvements(_analysis), do: []

  defp add_to_personalization_insights(insights, new_entry) do
    behavior_type = new_entry.behavior_type
    current_insights = Map.get(insights, behavior_type, [])
    updated_insights = [new_entry | current_insights] |> Enum.take(20)

    Map.put(insights, behavior_type, updated_insights)
  end

  defp find_most_accessed_preferences(usage_data) do
    usage_data
    |> Enum.sort_by(fn {_key, usage} -> usage.count end, :desc)
    |> Enum.take(5)
    |> Enum.map(&elem(&1, 0))
  end

  defp calculate_access_frequency(usage_data) do
    if map_size(usage_data) > 0 do
      total_accesses = usage_data |> Map.values() |> Enum.map(& &1.count) |> Enum.sum()
      total_accesses / map_size(usage_data)
    else
      0.0
    end
  end

  defp calculate_category_distribution(usage_data) do
    usage_data
    |> Enum.group_by(fn {key, _usage} -> get_preference_category(key) end)
    |> Map.new(fn {category, prefs} -> {category, length(prefs)} end)
  end

  defp analyze_temporal_patterns(_usage_data) do
    # Placeholder for temporal pattern analysis
    %{peak_hours: [], quiet_hours: []}
  end

  defp get_common_preference_keys do
    # Common preferences users typically configure
    [
      "code_quality.global.enabled",
      "ml.global.enabled",
      "budgeting.enforcement.enabled",
      "llm.providers.primary"
    ]
  end

  defp find_slow_resolving_categories(_usage_data) do
    # Placeholder for performance analysis
    []
  end

  defp suggest_default_for_preference(preference_key, _usage) do
    # Suggest optimal default based on preference type and usage
    category = get_preference_category(preference_key)

    case category do
      "code_quality" -> "true"
      "ml" -> "false"
      "budgeting" -> "true"
      _ -> "default"
    end
  end

  defp get_preference_category(preference_key) do
    preference_key
    |> String.split(".")
    |> hd()
  end
end
