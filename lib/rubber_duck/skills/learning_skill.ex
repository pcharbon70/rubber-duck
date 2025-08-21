defmodule RubberDuck.Skills.LearningSkill do
  @moduledoc """
  Learning skill for experience tracking and pattern recognition.
  
  This skill provides foundational learning capabilities that enable agents
  to track experiences, identify patterns, and improve their behavior over time.
  """
  
  use Jido.Skill,
    name: "learning_skill",
    opts_key: :learning_state,
    signal_patterns: [
      "learning.track_experience",
      "learning.get_insights",
      "learning.assess_learning"
    ]
  
  alias RubberDuck.Repo
  
  @doc """
  Track an experience with outcome and context.
  """
  def track_experience(%{experience: experience, outcome: outcome, context: context} = _params, state) do
    experience_data = %{
      experience: experience,
      outcome: outcome,
      context: context,
      timestamp: DateTime.utc_now(),
      agent_id: state.agent_id
    }
    
    # Store experience in agent state
    experiences = Map.get(state, :experiences, [])
    updated_experiences = [experience_data | experiences] |> Enum.take(1000) # Keep last 1000
    
    # Update learning patterns
    patterns = analyze_patterns(updated_experiences)
    
    new_state = state
    |> Map.put(:experiences, updated_experiences)
    |> Map.put(:learning_patterns, patterns)
    |> Map.put(:last_learning_update, DateTime.utc_now())
    
    {:ok, new_state}
  end
  
  @doc """
  Get learning insights for decision making.
  """
  def get_insights(%{context: context} = _params, state) do
    patterns = Map.get(state, :learning_patterns, %{})
    experiences = Map.get(state, :experiences, [])
    
    relevant_patterns = find_relevant_patterns(patterns, context)
    confidence_score = calculate_confidence(relevant_patterns, experiences)
    
    insights = %{
      patterns: relevant_patterns,
      confidence: confidence_score,
      recommendation: generate_recommendation(relevant_patterns, confidence_score),
      context_match_count: length(filter_by_context(experiences, context))
    }
    
    {:ok, insights, state}
  end
  
  @doc """
  Analyze current learning effectiveness.
  """
  def assess_learning(_params, state) do
    experiences = Map.get(state, :experiences, [])
    patterns = Map.get(state, :learning_patterns, %{})
    
    assessment = %{
      total_experiences: length(experiences),
      pattern_count: map_size(patterns),
      learning_rate: calculate_learning_rate(experiences),
      effectiveness_score: calculate_effectiveness(experiences),
      last_update: Map.get(state, :last_learning_update)
    }
    
    {:ok, assessment, state}
  end
  
  # Private helper functions
  
  defp analyze_patterns(experiences) do
    experiences
    |> Enum.group_by(& &1.context)
    |> Enum.map(fn {context, context_experiences} ->
      success_rate = calculate_success_rate(context_experiences)
      common_factors = extract_common_factors(context_experiences)
      
      {context, %{
        success_rate: success_rate,
        sample_size: length(context_experiences),
        common_factors: common_factors,
        last_updated: DateTime.utc_now()
      }}
    end)
    |> Enum.into(%{})
  end
  
  defp find_relevant_patterns(patterns, context) do
    patterns
    |> Enum.filter(fn {pattern_context, _data} ->
      context_similarity(pattern_context, context) > 0.5
    end)
    |> Enum.take(5) # Top 5 most relevant patterns
  end
  
  defp calculate_confidence(patterns, _experiences) do
    if length(patterns) == 0 do
      0.0
    else
      total_samples = patterns |> Enum.map(fn {_ctx, data} -> data.sample_size end) |> Enum.sum()
      min(total_samples / 50.0, 1.0) # Max confidence at 50+ samples
    end
  end
  
  defp generate_recommendation(_patterns, confidence) when confidence < 0.3 do
    "Insufficient data for reliable recommendation. Continue gathering experience."
  end
  
  defp generate_recommendation(patterns, _confidence) do
    best_pattern = patterns
    |> Enum.max_by(fn {_ctx, data} -> data.success_rate end, fn -> {nil, %{success_rate: 0}} end)
    
    case best_pattern do
      {_ctx, %{success_rate: rate}} when rate > 0.7 ->
        "High confidence recommendation: Follow established successful pattern."
      {_ctx, %{success_rate: rate}} when rate > 0.4 ->
        "Moderate confidence: Consider established pattern with caution."
      _ ->
        "Low success pattern identified. Consider alternative approaches."
    end
  end
  
  defp calculate_success_rate(experiences) do
    successful = Enum.count(experiences, & &1.outcome == :success)
    total = length(experiences)
    if total > 0, do: successful / total, else: 0.0
  end
  
  defp extract_common_factors(experiences) do
    experiences
    |> Enum.flat_map(fn exp -> Map.keys(exp.context) end)
    |> Enum.frequencies()
    |> Enum.filter(fn {_key, count} -> count > length(experiences) * 0.5 end)
    |> Enum.map(fn {key, _count} -> key end)
  end
  
  defp context_similarity(context1, context2) when is_map(context1) and is_map(context2) do
    keys1 = MapSet.new(Map.keys(context1))
    keys2 = MapSet.new(Map.keys(context2))
    
    intersection = MapSet.intersection(keys1, keys2) |> MapSet.size()
    union = MapSet.union(keys1, keys2) |> MapSet.size()
    
    if union > 0, do: intersection / union, else: 0.0
  end
  
  defp context_similarity(_context1, _context2), do: 0.0
  
  defp filter_by_context(experiences, context) do
    Enum.filter(experiences, fn exp ->
      context_similarity(exp.context, context) > 0.3
    end)
  end
  
  defp calculate_learning_rate(experiences) do
    if length(experiences) < 10, do: 0.0
    
    recent = Enum.take(experiences, 50)
    older = Enum.slice(experiences, 50, 50)
    
    recent_success = calculate_success_rate(recent)
    older_success = calculate_success_rate(older)
    
    recent_success - older_success
  end
  
  defp calculate_effectiveness(experiences) do
    if length(experiences) < 5, do: 0.0
    
    success_rate = calculate_success_rate(experiences)
    learning_trend = calculate_learning_rate(experiences)
    
    # Combine success rate with learning trend for overall effectiveness
    success_rate * 0.7 + max(learning_trend, 0) * 0.3
  end
end