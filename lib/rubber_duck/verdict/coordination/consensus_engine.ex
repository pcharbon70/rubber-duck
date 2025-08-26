defmodule RubberDuck.Verdict.Coordination.ConsensusEngine do
  @moduledoc """
  Consensus engine for coordinating agreement between judge agents.

  Implements sophisticated consensus mechanisms including voting protocols,
  confidence-weighted aggregation, and negotiation for handling disagreements
  between multiple judge agents in collaborative evaluations.
  """

  require Logger

  @default_consensus_threshold 0.7
  @min_agents_for_consensus 2

  @doc """
  Compute consensus from multiple agent evaluation results.

  ## Parameters
  - `agent_results` - Map of agent_type -> evaluation_result
  - `consensus_config` - Configuration for consensus mechanisms

  ## Returns
  - `{:ok, consensus_result}` - Successfully reached consensus
  - `{:error, :no_consensus}` - Could not reach consensus
  - `{:error, reason}` - Consensus computation failed
  """
  @spec compute_consensus(agent_results :: map(), consensus_config :: map()) ::
          {:ok, map()} | {:error, term()}
  def compute_consensus(agent_results, consensus_config \\ %{}) do
    case validate_consensus_inputs(agent_results, consensus_config) do
      :ok -> execute_consensus_algorithm(agent_results, consensus_config)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Analyze agreement level between judge agents.

  ## Returns
  - Agreement score (0.0 to 1.0)
  - Disagreement areas and severity
  - Confidence distribution analysis
  """
  @spec analyze_agreement(agent_results :: map()) :: map()
  def analyze_agreement(agent_results) do
    scores = extract_scores(agent_results)
    confidences = extract_confidences(agent_results)

    %{
      agreement_score: calculate_score_agreement(scores),
      confidence_alignment: calculate_confidence_alignment(confidences),
      disagreement_areas: identify_disagreement_areas(agent_results),
      consensus_feasibility: assess_consensus_feasibility(agent_results)
    }
  end

  @doc """
  Determine if consensus is achievable given current agent results.
  """
  @spec consensus_achievable?(agent_results :: map(), threshold :: float()) :: boolean()
  def consensus_achievable?(agent_results, threshold \\ @default_consensus_threshold) do
    agreement_analysis = analyze_agreement(agent_results)
    agreement_analysis.agreement_score >= threshold
  end

  ## Private Functions

  defp validate_consensus_inputs(agent_results, _config) do
    cond do
      map_size(agent_results) < @min_agents_for_consensus ->
        {:error, "Insufficient agents for consensus (minimum #{@min_agents_for_consensus})"}

      not all_results_valid?(agent_results) ->
        {:error, "Invalid agent results detected"}

      true ->
        :ok
    end
  end

  defp execute_consensus_algorithm(agent_results, config) do
    voting_method = Map.get(config, :voting_method, :weighted_average)
    consensus_threshold = Map.get(config, :consensus_threshold, @default_consensus_threshold)

    case voting_method do
      :weighted_average ->
        compute_weighted_consensus(agent_results, consensus_threshold)

      :majority_vote ->
        compute_majority_consensus(agent_results, consensus_threshold)

      :confidence_weighted ->
        compute_confidence_weighted_consensus(agent_results, consensus_threshold)

      _ ->
        {:error, "Unsupported voting method: #{voting_method}"}
    end
  end

  defp compute_weighted_consensus(agent_results, threshold) do
    # Compute weighted average based on agent confidence and specialization
    weights = calculate_agent_weights(agent_results)

    weighted_score = compute_weighted_score(agent_results, weights)
    consensus_confidence = compute_consensus_confidence(agent_results, weights)

    if consensus_confidence >= threshold do
      consensus_result =
        build_consensus_result(
          agent_results,
          weighted_score,
          consensus_confidence,
          :weighted_average
        )

      {:ok, consensus_result}
    else
      {:error, :no_consensus}
    end
  end

  defp compute_majority_consensus(agent_results, _threshold) do
    # Simple majority voting on score ranges
    score_ranges = categorize_scores(agent_results)
    majority_range = find_majority_range(score_ranges)

    if majority_range do
      consensus_result = build_majority_consensus_result(agent_results, majority_range)
      {:ok, consensus_result}
    else
      {:error, :no_consensus}
    end
  end

  defp compute_confidence_weighted_consensus(agent_results, threshold) do
    # Weight by confidence levels of individual agents
    total_confidence_weight =
      Enum.reduce(agent_results, 0.0, fn {_agent, result}, acc ->
        acc + result.confidence
      end)

    if total_confidence_weight > 0 do
      weighted_score =
        Enum.reduce(agent_results, 0.0, fn {_agent, result}, acc ->
          weight = result.confidence / total_confidence_weight
          acc + result.score * weight
        end)

      average_confidence = total_confidence_weight / map_size(agent_results)

      if average_confidence >= threshold do
        consensus_result =
          build_consensus_result(
            agent_results,
            weighted_score,
            average_confidence,
            :confidence_weighted
          )

        {:ok, consensus_result}
      else
        {:error, :no_consensus}
      end
    else
      {:error, :insufficient_confidence}
    end
  end

  defp build_consensus_result(agent_results, final_score, consensus_confidence, method) do
    all_issues = collect_all_issues(agent_results)
    all_recommendations = collect_all_recommendations(agent_results)

    %{
      consensus_score: final_score,
      consensus_confidence: consensus_confidence,
      consensus_method: method,
      participating_agents: Map.keys(agent_results),
      agent_count: map_size(agent_results),
      consolidated_issues: deduplicate_and_rank_issues(all_issues),
      consolidated_recommendations: deduplicate_and_rank_recommendations(all_recommendations),
      consensus_reasoning: build_consensus_reasoning(agent_results, method),
      individual_agent_results: agent_results,
      total_cost: calculate_total_cost(agent_results),
      total_tokens: calculate_total_tokens(agent_results),
      agent_cost_breakdown: calculate_agent_cost_breakdown(agent_results)
    }
  end

  # Helper calculation functions

  defp all_results_valid?(agent_results) do
    Enum.all?(agent_results, fn {_agent, result} ->
      is_map(result) and
        Map.has_key?(result, :score) and
        Map.has_key?(result, :confidence)
    end)
  end

  defp extract_scores(agent_results) do
    Enum.map(agent_results, fn {_agent, result} -> result.score end)
  end

  defp extract_confidences(agent_results) do
    Enum.map(agent_results, fn {_agent, result} -> result.confidence end)
  end

  defp calculate_score_agreement(scores) do
    if length(scores) <= 1 do
      1.0
    else
      mean = Enum.sum(scores) / length(scores)

      variance =
        Enum.reduce(scores, 0.0, fn score, acc ->
          acc + :math.pow(score - mean, 2)
        end) / length(scores)

      # Convert variance to agreement score (lower variance = higher agreement)
      max(0.0, 1.0 - variance)
    end
  end

  defp calculate_confidence_alignment(confidences) do
    calculate_score_agreement(confidences)
  end

  defp identify_disagreement_areas(agent_results) do
    # Identify areas where agents significantly disagree
    scores = extract_scores(agent_results)
    score_range = Enum.max(scores) - Enum.min(scores)

    if score_range > 0.3 do
      %{
        severity: :high,
        score_range: score_range,
        disagreeing_agents: find_outlier_agents(agent_results)
      }
    else
      %{severity: :low, score_range: score_range}
    end
  end

  defp assess_consensus_feasibility(agent_results) do
    agreement_analysis = %{
      score_agreement: calculate_score_agreement(extract_scores(agent_results)),
      confidence_agreement: calculate_confidence_alignment(extract_confidences(agent_results)),
      agent_count: map_size(agent_results)
    }

    # Simple feasibility assessment
    if agreement_analysis.score_agreement > 0.6 and agreement_analysis.confidence_agreement > 0.5 do
      :high
    else
      :low
    end
  end

  defp calculate_agent_weights(agent_results) do
    # Calculate weights based on agent specialization and confidence
    Enum.reduce(agent_results, %{}, fn {agent_type, result}, acc ->
      specialization_weight = get_specialization_weight(agent_type)
      confidence_weight = result.confidence

      final_weight = (specialization_weight + confidence_weight) / 2
      Map.put(acc, agent_type, final_weight)
    end)
  end

  defp get_specialization_weight(agent_type) do
    # Weight based on agent specialization expertise
    case agent_type do
      # High weight for security assessments
      :security -> 1.0
      # High weight for architectural analysis
      :architecture -> 0.9
      # Standard weight for general quality
      :code_quality -> 0.8
      # Lower weight for test-specific issues
      :test_quality -> 0.7
      # Default weight for unknown agents
      _ -> 0.6
    end
  end

  defp compute_weighted_score(agent_results, weights) do
    total_weight = Enum.reduce(weights, 0.0, fn {_agent, weight}, acc -> acc + weight end)

    if total_weight > 0 do
      Enum.reduce(agent_results, 0.0, fn {agent_type, result}, acc ->
        weight = Map.get(weights, agent_type, 0.5)
        normalized_weight = weight / total_weight
        acc + result.score * normalized_weight
      end)
    else
      # Default score if no valid weights
      0.5
    end
  end

  defp compute_consensus_confidence(agent_results, weights) do
    total_weight = Enum.reduce(weights, 0.0, fn {_agent, weight}, acc -> acc + weight end)

    if total_weight > 0 do
      Enum.reduce(agent_results, 0.0, fn {agent_type, result}, acc ->
        weight = Map.get(weights, agent_type, 0.5)
        normalized_weight = weight / total_weight
        acc + result.confidence * normalized_weight
      end)
    else
      # Default confidence if no valid weights
      0.5
    end
  end

  defp categorize_scores(agent_results) do
    scores = extract_scores(agent_results)

    Enum.group_by(scores, fn score ->
      cond do
        score >= 0.8 -> :excellent
        score >= 0.6 -> :good
        score >= 0.4 -> :fair
        true -> :poor
      end
    end)
  end

  defp find_majority_range(score_ranges) do
    max_category =
      Enum.max_by(score_ranges, fn {_category, scores} -> length(scores) end, fn -> nil end)

    case max_category do
      {category, scores} when length(scores) > 1 -> category
      _ -> nil
    end
  end

  defp build_majority_consensus_result(agent_results, majority_range) do
    majority_agents = filter_agents_by_score_range(agent_results, majority_range)
    average_score = calculate_average_score(majority_agents)
    average_confidence = calculate_average_confidence(majority_agents)

    build_consensus_result(majority_agents, average_score, average_confidence, :majority_vote)
  end

  defp filter_agents_by_score_range(agent_results, range) do
    Enum.filter(agent_results, fn {_agent, result} ->
      score_in_range?(result.score, range)
    end)
    |> Map.new()
  end

  defp score_in_range?(score, range) do
    case range do
      :excellent -> score >= 0.8
      :good -> score >= 0.6 and score < 0.8
      :fair -> score >= 0.4 and score < 0.6
      :poor -> score < 0.4
    end
  end

  defp calculate_average_score(agent_results) do
    scores = extract_scores(agent_results)
    if length(scores) > 0, do: Enum.sum(scores) / length(scores), else: 0.0
  end

  defp calculate_average_confidence(agent_results) do
    confidences = extract_confidences(agent_results)
    if length(confidences) > 0, do: Enum.sum(confidences) / length(confidences), else: 0.0
  end

  defp find_outlier_agents(agent_results) do
    scores = extract_scores(agent_results)
    mean_score = Enum.sum(scores) / length(scores)

    Enum.filter(agent_results, fn {_agent_type, result} ->
      abs(result.score - mean_score) > 0.25
    end)
    |> Enum.map(fn {agent_type, _result} -> agent_type end)
  end

  defp collect_all_issues(agent_results) do
    Enum.flat_map(agent_results, fn {agent_type, result} ->
      Enum.map(result.issues || [], fn issue ->
        %{agent: agent_type, issue: issue}
      end)
    end)
  end

  defp collect_all_recommendations(agent_results) do
    Enum.flat_map(agent_results, fn {agent_type, result} ->
      Enum.map(result.recommendations || [], fn rec ->
        %{agent: agent_type, recommendation: rec}
      end)
    end)
  end

  defp deduplicate_and_rank_issues(issues) do
    # Group similar issues and rank by frequency/importance
    issues
    |> Enum.group_by(& &1.issue)
    |> Enum.map(fn {issue_text, occurrences} ->
      %{
        issue: issue_text,
        frequency: length(occurrences),
        reporting_agents: Enum.map(occurrences, & &1.agent),
        importance: calculate_issue_importance(occurrences)
      }
    end)
    |> Enum.sort_by(& &1.importance, :desc)
  end

  defp deduplicate_and_rank_recommendations(recommendations) do
    # Group similar recommendations and rank by consensus
    recommendations
    |> Enum.group_by(& &1.recommendation)
    |> Enum.map(fn {rec_text, occurrences} ->
      %{
        recommendation: rec_text,
        consensus_level: length(occurrences),
        supporting_agents: Enum.map(occurrences, & &1.agent),
        priority: calculate_recommendation_priority(occurrences)
      }
    end)
    |> Enum.sort_by(& &1.priority, :desc)
  end

  defp calculate_issue_importance(occurrences) do
    # Higher importance for issues reported by multiple agents
    base_importance = length(occurrences)

    # Bonus for security agents reporting issues
    security_bonus =
      if Enum.any?(occurrences, fn occ -> occ.agent == :security end), do: 0.5, else: 0.0

    base_importance + security_bonus
  end

  defp calculate_recommendation_priority(occurrences) do
    # Higher priority for recommendations from multiple agents
    length(occurrences)
  end

  defp build_consensus_reasoning(agent_results, method) do
    agent_summaries =
      Enum.map(agent_results, fn {agent_type, result} ->
        "#{agent_type}: score=#{result.score}, confidence=#{result.confidence}"
      end)

    "Consensus reached using #{method} method. Agent results: #{Enum.join(agent_summaries, "; ")}"
  end

  defp calculate_total_cost(agent_results) do
    Enum.reduce(agent_results, 0.0, fn {_agent, result}, acc ->
      acc + (result.cost_usd || 0.0)
    end)
  end

  defp calculate_total_tokens(agent_results) do
    Enum.reduce(agent_results, 0, fn {_agent, result}, acc ->
      acc + (result.tokens_used || 0)
    end)
  end

  defp calculate_agent_cost_breakdown(agent_results) do
    Enum.reduce(agent_results, %{}, fn {agent_type, result}, acc ->
      Map.put(acc, agent_type, %{
        cost_usd: result.cost_usd || 0.0,
        tokens_used: result.tokens_used || 0
      })
    end)
  end
end
