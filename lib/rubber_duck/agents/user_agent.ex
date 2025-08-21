defmodule RubberDuck.Agents.UserAgent do
  @moduledoc """
  User agent for autonomous user session management with behavioral learning.
  
  This agent tracks user behavior patterns, learns preferences, and provides
  proactive assistance suggestions based on usage history.
  """
  
  use Jido.Agent,
    name: "user_agent",
    description: "Autonomous user session management with behavioral learning",
    category: "domain",
    tags: ["user", "learning", "behavioral"],
    vsn: "1.0.0",
    actions: [
      RubberDuck.Actions.CreateEntity
    ]
  
  alias RubberDuck.Accounts.User
  alias RubberDuck.Skills.{LearningSkill, UserManagementSkill}
  
  @doc """
  Create a new UserAgent instance with user context.
  """
  def create_for_user(user_id) do
    with {:ok, agent} <- __MODULE__.new(),
         {:ok, agent} <- __MODULE__.set(agent, user_id: user_id, 
                                        session_data: %{},
                                        behavior_patterns: %{},
                                        preferences: %{},
                                        last_activity: DateTime.utc_now(),
                                        proactive_suggestions: []) do
      {:ok, agent}
    end
  end
  
  @doc """
  Record user activity and learn from behavior patterns.
  """
  def record_activity(agent, activity_type, activity_data) do
    activity = %{
      type: activity_type,
      data: activity_data,
      timestamp: DateTime.utc_now()
    }
    
    # Update behavior patterns
    patterns = update_behavior_patterns(agent.behavior_patterns, activity)
    
    # Generate proactive suggestions
    suggestions = generate_proactive_suggestions(patterns, activity)
    
    # Update agent state
    __MODULE__.set(agent,
      behavior_patterns: patterns,
      last_activity: DateTime.utc_now(),
      proactive_suggestions: suggestions
    )
  end
  
  @doc """
  Get proactive suggestions for the user.
  """
  def get_suggestions(agent) do
    {:ok, agent.proactive_suggestions}
  end
  
  @doc """
  Update user preferences based on feedback.
  """
  def update_preference(agent, preference_key, preference_value) do
    updated_preferences = Map.put(agent.preferences, preference_key, preference_value)
    
    __MODULE__.set(agent, preferences: updated_preferences)
  end
  
  @doc """
  Get current user behavior patterns.
  """
  def get_behavior_patterns(agent) do
    {:ok, agent.behavior_patterns}
  end
  
  # Private helper functions
  
  defp update_behavior_patterns(patterns, activity) do
    activity_key = activity.type
    current_pattern = Map.get(patterns, activity_key, %{count: 0, recent_activities: []})
    
    updated_pattern = %{
      count: current_pattern.count + 1,
      recent_activities: [activity | current_pattern.recent_activities] |> Enum.take(20),
      last_seen: DateTime.utc_now(),
      frequency: calculate_frequency(current_pattern, activity)
    }
    
    Map.put(patterns, activity_key, updated_pattern)
  end
  
  defp calculate_frequency(pattern, _activity) do
    recent_count = length(pattern.recent_activities)
    if recent_count < 2, do: 0.0
    
    # Calculate activities per hour based on recent activity timestamps
    now = DateTime.utc_now()
    hour_ago = DateTime.add(now, -3600, :second)
    
    recent_activities_in_hour = Enum.count(pattern.recent_activities, fn activity ->
      DateTime.compare(activity.timestamp, hour_ago) == :gt
    end)
    
    recent_activities_in_hour / 1.0 # activities per hour
  end
  
  defp generate_proactive_suggestions(patterns, current_activity) do
    patterns
    |> Enum.filter(fn {_type, pattern} -> pattern.frequency > 0.5 end) # Active patterns
    |> Enum.map(fn {type, pattern} ->
      generate_suggestion_for_pattern(type, pattern, current_activity)
    end)
    |> Enum.filter(& &1 != nil)
    |> Enum.take(3) # Top 3 suggestions
  end
  
  defp generate_suggestion_for_pattern(:code_analysis, pattern, _current_activity) do
    if pattern.frequency > 1.0 do
      %{
        type: :automation,
        message: "You frequently analyze code. Consider setting up automated analysis on file save.",
        priority: :medium,
        action: :enable_auto_analysis
      }
    end
  end
  
  defp generate_suggestion_for_pattern(:project_navigation, pattern, _current_activity) do
    if pattern.count > 20 do
      %{
        type: :optimization,
        message: "Based on your navigation patterns, I can learn your preferred project structure.",
        priority: :low,
        action: :learn_navigation_preferences
      }
    end
  end
  
  defp generate_suggestion_for_pattern(_type, _pattern, _current_activity), do: nil
end