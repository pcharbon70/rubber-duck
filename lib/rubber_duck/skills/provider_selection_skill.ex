defmodule RubberDuck.Skills.ProviderSelectionSkill do
  @moduledoc """
  Provider selection skill for autonomous LLM provider optimization.

  This skill provides intelligent provider selection capabilities including:
  - Multi-criteria provider optimization with cost, quality, and performance factors
  - Learning-based provider selection that improves over time
  - Real-time provider health and capability assessment
  - Integration with Universal LLM Provider System for seamless routing
  - Configuration-aware selection respecting user and project preferences

  The skill works with the LLM Orchestrator Agent to provide autonomous
  provider selection intelligence across all LLM operations.
  """

  use Jido.Skill,
    name: "provider_selection_skill",
    opts_key: :provider_selection_state,
    signal_patterns: [
      "provider_selection.select_optimal",
      "provider_selection.analyze_requirements",
      "provider_selection.learn_from_outcome",
      "provider_selection.get_recommendations"
    ]

  require Logger

  alias RubberDuck.LlmProviders.{UniversalProviderService, ProviderRouter}

  @doc """
  Select optimal provider for request based on multi-criteria optimization.
  """
  def select_optimal_provider(
        %{
          request_requirements: requirements,
          domain: domain,
          optimization_criteria: criteria
        } = _params,
        state
      ) do
    Logger.debug("Selecting optimal provider for domain: #{domain}")

    # Get available providers from Universal Provider System
    case UniversalProviderService.get_available_providers(domain) do
      {:ok, available_providers} ->
        # Apply multi-criteria optimization
        case apply_provider_optimization(available_providers, requirements, criteria, state) do
          {:ok, selection} ->
            # Update skill state with selection data
            updated_state = update_selection_state(state, selection, requirements)

            selection_result = %{
              selected_provider: selection.provider,
              model: selection.model,
              confidence: selection.confidence,
              reasoning: selection.reasoning,
              cost_estimate: selection.cost_estimate,
              quality_prediction: selection.quality_prediction,
              optimization_applied: true,
              skill_used: "provider_selection_skill"
            }

            {:ok, selection_result, updated_state}

          error ->
            Logger.error("Provider optimization failed: #{inspect(error)}")
            {:error, error, state}
        end

      error ->
        Logger.error("Failed to get available providers: #{inspect(error)}")
        {:error, error, state}
    end
  end

  @doc """
  Analyze request requirements for optimal provider selection.
  """
  def analyze_request_requirements(
        %{
          request: request,
          domain: domain,
          context: context
        } = _params,
        state
      ) do
    Logger.debug("Analyzing request requirements for provider selection")

    # Perform comprehensive request analysis
    requirements_analysis = %{
      content_complexity: analyze_content_complexity(request),
      estimated_tokens: estimate_token_requirements(request),
      quality_requirements: extract_quality_requirements(context),
      cost_constraints: extract_cost_constraints(context),
      performance_requirements: extract_performance_requirements(context),
      specialized_features: Map.get(context, :specialized_features, []),
      user_preferences: extract_user_preferences(context),
      domain_specific_needs: analyze_domain_specific_needs(domain, request)
    }

    # Enhance with historical data from skill state
    enhanced_analysis = enhance_with_historical_data(requirements_analysis, state)

    analysis_result = %{
      requirements_analysis: enhanced_analysis,
      optimization_recommendations: generate_optimization_recommendations(enhanced_analysis),
      provider_suitability: assess_provider_suitability(enhanced_analysis),
      skill_analysis_applied: true
    }

    {:ok, analysis_result, state}
  end

  @doc """
  Learn from provider selection outcome to improve future decisions.
  """
  def learn_from_selection_outcome(
        %{
          provider_selection: selection,
          actual_outcome: outcome,
          performance_data: performance
        } = _params,
        state
      ) do
    Logger.debug("Learning from provider selection outcome")

    # Create learning data from outcome
    learning_data = %{
      provider: selection.selected_provider,
      model: selection.model,
      predicted_cost: selection.cost_estimate,
      actual_cost: outcome.cost_usd,
      predicted_quality: selection.quality_prediction,
      actual_quality: estimate_outcome_quality(outcome),
      selection_confidence: selection.confidence,
      outcome_success: outcome.success,
      response_time: performance.response_time_ms,
      timestamp: DateTime.utc_now()
    }

    # Update skill learning state
    updated_state = update_learning_state(state, learning_data)

    # Calculate learning insights
    learning_insights = %{
      prediction_accuracy: calculate_prediction_accuracy(learning_data),
      provider_performance_trend: analyze_performance_trend(learning_data, updated_state),
      optimization_effectiveness: assess_optimization_effectiveness(learning_data, selection),
      recommendations_for_future: generate_future_recommendations(learning_data, updated_state)
    }

    learning_result = %{
      learning_applied: true,
      learning_insights: learning_insights,
      skill_improvement: measure_skill_improvement(state, updated_state),
      updated_provider_knowledge: get_updated_provider_knowledge(updated_state)
    }

    {:ok, learning_result, updated_state}
  end

  @doc """
  Get provider recommendations with detailed analysis.
  """
  def get_provider_recommendations(
        %{
          requirements: requirements,
          domain: domain,
          include_analysis: include_detailed_analysis
        } = _params,
        state
      ) do
    Logger.debug("Getting provider recommendations for #{domain}")

    case UniversalProviderService.get_available_providers(domain) do
      {:ok, available_providers} ->
        # Generate comprehensive recommendations
        recommendations =
          available_providers
          |> Enum.map(fn {provider_type, provider_info} ->
            generate_provider_recommendation(provider_type, provider_info, requirements, state)
          end)
          |> Enum.sort_by(& &1.overall_score, :desc)

        recommendation_result = %{
          provider_recommendations: recommendations,
          analysis_metadata:
            if(include_detailed_analysis,
              do: generate_analysis_metadata(requirements, state),
              else: %{}
            ),
          skill_confidence: calculate_skill_confidence(state),
          recommendation_timestamp: DateTime.utc_now()
        }

        {:ok, recommendation_result, state}

      error ->
        {:error, error, state}
    end
  end

  # Private implementation

  defp apply_provider_optimization(available_providers, requirements, criteria, state) do
    # Apply sophisticated provider optimization
    scored_providers =
      available_providers
      |> Enum.map(fn {provider_type, provider_info} ->
        score_provider_comprehensively(
          provider_type,
          provider_info,
          requirements,
          criteria,
          state
        )
      end)
      |> Enum.sort_by(& &1.overall_score, :desc)

    case scored_providers do
      [best_provider | _] ->
        {:ok,
         %{
           provider: best_provider.provider_type,
           model: best_provider.recommended_model,
           confidence: best_provider.overall_score,
           reasoning: best_provider.optimization_reasoning,
           cost_estimate: best_provider.cost_estimate,
           quality_prediction: best_provider.quality_prediction,
           optimization_factors: best_provider.optimization_factors
         }}

      [] ->
        {:error, "No suitable providers available for requirements"}
    end
  end

  defp score_provider_comprehensively(provider_type, provider_info, requirements, criteria, state) do
    # Comprehensive provider scoring
    capability_score = calculate_capability_match_score(provider_info, requirements)
    cost_efficiency_score = calculate_cost_efficiency_score(provider_type, requirements, state)

    quality_prediction_score =
      calculate_quality_prediction_score(provider_type, requirements, state)

    performance_score = calculate_performance_score(provider_type, requirements, state)
    reliability_score = calculate_reliability_score(provider_type, state)
    learning_adjustment = apply_learning_adjustment(provider_type, state)

    # Apply optimization criteria weights
    weighted_score =
      apply_optimization_weights(
        %{
          capability: capability_score,
          cost_efficiency: cost_efficiency_score,
          quality: quality_prediction_score,
          performance: performance_score,
          reliability: reliability_score,
          learning: learning_adjustment
        },
        criteria
      )

    %{
      provider_type: provider_type,
      overall_score: weighted_score,
      capability_score: capability_score,
      cost_efficiency_score: cost_efficiency_score,
      quality_prediction_score: quality_prediction_score,
      performance_score: performance_score,
      reliability_score: reliability_score,
      learning_adjustment: learning_adjustment,
      recommended_model: select_optimal_model_for_provider(provider_type, requirements),
      cost_estimate: estimate_provider_cost(provider_type, requirements),
      quality_prediction: predict_provider_quality(provider_type, requirements, state),
      optimization_factors: extract_optimization_factors(provider_type, requirements, criteria),
      optimization_reasoning:
        generate_optimization_reasoning(provider_type, weighted_score, criteria)
    }
  end

  defp calculate_capability_match_score(provider_info, requirements) do
    # Calculate how well provider capabilities match requirements
    domain_match = if requirements.domain in provider_info.supports_domains, do: 1.0, else: 0.0

    # Check specialized feature support
    feature_matches =
      requirements.specialized_features
      |> Enum.map(fn feature ->
        if feature in Map.get(provider_info, :specializations, []), do: 1.0, else: 0.3
      end)

    feature_score =
      case feature_matches do
        # No specific requirements
        [] -> 0.8
        matches -> Enum.sum(matches) / length(matches)
      end

    (domain_match + feature_score) / 2
  end

  defp calculate_cost_efficiency_score(provider_type, requirements, state) do
    # Calculate cost efficiency based on requirements and historical data
    estimated_cost = estimate_provider_cost(provider_type, requirements)
    max_acceptable_cost = Map.get(requirements, :max_cost_per_request, 1.0)

    base_cost_score =
      if estimated_cost <= max_acceptable_cost do
        # Better cost = higher score
        1.0 - estimated_cost / max_acceptable_cost * 0.7
      else
        # Cost too high
        0.2
      end

    # Apply historical cost efficiency data if available
    historical_efficiency = get_historical_cost_efficiency(provider_type, state)

    (base_cost_score + historical_efficiency) / 2
  end

  defp calculate_quality_prediction_score(provider_type, requirements, state) do
    # Predict quality based on provider characteristics and historical data
    base_quality =
      case provider_type do
        # High quality with Constitutional AI
        :anthropic -> 0.9
        # Good general quality
        :openai -> 0.85
        # Decent quality for local
        :ollama -> 0.75
        _ -> 0.8
      end

    # Adjust for domain specialization
    domain_bonus =
      case {provider_type, requirements.domain} do
        # Anthropic excels at evaluation
        {:anthropic, :evaluation} -> 0.05
        # OpenAI good for orchestration
        {:openai, :orchestration} -> 0.05
        _ -> 0.0
      end

    # Apply historical quality data
    historical_quality = get_historical_quality_performance(provider_type, state)

    min(1.0, base_quality + domain_bonus + (historical_quality - 0.8) * 0.5)
  end

  defp calculate_performance_score(provider_type, requirements, state) do
    # Calculate expected performance score
    base_performance =
      case provider_type do
        # Fast local models
        :ollama -> 0.9
        # Generally fast
        :openai -> 0.8
        # Slower but thorough
        :anthropic -> 0.7
        _ -> 0.75
      end

    # Adjust based on requirements
    performance_requirement = Map.get(requirements, :max_response_time, 10_000)

    if performance_requirement < 3000 and provider_type == :anthropic do
      # Penalize Anthropic for speed requirements
      base_performance * 0.8
    else
      base_performance
    end
  end

  defp calculate_reliability_score(provider_type, state) do
    # Calculate reliability based on historical data
    historical_reliability = get_historical_reliability(provider_type, state)

    base_reliability =
      case provider_type do
        :openai -> 0.95
        :anthropic -> 0.92
        :ollama -> 0.85
        _ -> 0.9
      end

    (base_reliability + historical_reliability) / 2
  end

  defp apply_learning_adjustment(provider_type, state) do
    # Apply learning-based adjustment to provider scores
    learning_data = get_provider_learning_data(provider_type, state)

    case learning_data do
      # No learning data
      nil ->
        0.0

      data ->
        improvement_rate = Map.get(data, :improvement_rate, 0.0)
        confidence = Map.get(data, :confidence, 0.5)

        # Small but meaningful adjustment
        improvement_rate * confidence * 0.1
    end
  end

  defp apply_optimization_weights(scores, criteria) do
    # Apply optimization criteria weights to scores
    weights =
      Map.get(criteria, :weights, %{
        capability: 0.25,
        cost_efficiency: 0.20,
        quality: 0.25,
        performance: 0.15,
        reliability: 0.10,
        learning: 0.05
      })

    scores.capability * weights.capability +
      scores.cost_efficiency * weights.cost_efficiency +
      scores.quality * weights.quality +
      scores.performance * weights.performance +
      scores.reliability * weights.reliability +
      scores.learning * weights.learning
  end

  defp select_optimal_model_for_provider(provider_type, requirements) do
    complexity = Map.get(requirements, :content_complexity, :medium)
    quality_priority = get_in(requirements, [:quality_requirements, :quality_priority]) || :medium

    case {provider_type, complexity, quality_priority} do
      {:anthropic, :high, _} -> "claude-3-opus-20240229"
      {:anthropic, _, :high} -> "claude-3-5-sonnet-20241022"
      {:anthropic, _, _} -> "claude-3-haiku-20240307"
      {:openai, :high, _} -> "gpt-4o"
      {:openai, _, _} -> "gpt-4o-mini"
      _ -> "default"
    end
  end

  defp estimate_provider_cost(provider_type, requirements) do
    estimated_tokens = Map.get(requirements, :estimated_tokens, 1000)

    cost_per_1k_tokens =
      case provider_type do
        :anthropic -> 0.015
        :openai -> 0.02
        :ollama -> 0.0
        _ -> 0.015
      end

    estimated_tokens / 1000 * cost_per_1k_tokens
  end

  defp predict_provider_quality(provider_type, requirements, state) do
    base_quality =
      case provider_type do
        :anthropic -> 0.9
        :openai -> 0.85
        :ollama -> 0.75
        _ -> 0.8
      end

    # Adjust based on historical learning
    historical_adjustment = get_historical_quality_adjustment(provider_type, state)

    min(1.0, max(0.0, base_quality + historical_adjustment))
  end

  defp extract_optimization_factors(provider_type, requirements, criteria) do
    # Extract key factors that influenced optimization
    %{
      provider_specialization: get_provider_specialization_factors(provider_type, requirements),
      cost_optimization: Map.get(criteria, :cost_priority, :medium),
      quality_optimization: Map.get(criteria, :quality_priority, :medium),
      performance_optimization: Map.get(criteria, :performance_priority, :medium),
      domain_fit: calculate_domain_fit_factor(provider_type, requirements.domain)
    }
  end

  defp generate_optimization_reasoning(provider_type, score, criteria) do
    primary_criteria =
      criteria
      |> Map.get(:weights, %{})
      |> Enum.sort_by(fn {_criterion, weight} -> weight end, :desc)
      |> Enum.take(2)
      |> Enum.map(fn {criterion, _weight} -> criterion end)

    "Selected #{provider_type} (score: #{Float.round(score, 2)}) optimized for #{Enum.join(primary_criteria, " and ")}"
  end

  # State management functions

  defp update_selection_state(state, selection, requirements) do
    # Update skill state with new selection data
    current_selections = Map.get(state, :recent_selections, [])

    selection_record = %{
      provider: selection.provider,
      model: selection.model,
      confidence: selection.confidence,
      requirements: requirements,
      timestamp: DateTime.utc_now()
    }

    updated_selections = [selection_record | current_selections] |> Enum.take(100)

    Map.put(state, :recent_selections, updated_selections)
  end

  defp update_learning_state(state, learning_data) do
    # Update learning state with outcome data
    provider = learning_data.provider

    provider_learning =
      state
      |> Map.get(:provider_learning, %{})
      |> Map.update(provider, %{}, fn existing_data ->
        update_provider_learning_data(existing_data, learning_data)
      end)

    Map.put(state, :provider_learning, provider_learning)
  end

  defp update_provider_learning_data(existing_data, new_learning) do
    # Update learning data for specific provider
    current_requests = Map.get(existing_data, :total_requests, 0)

    %{
      total_requests: current_requests + 1,
      avg_cost_accuracy: update_prediction_accuracy(existing_data, new_learning, :cost),
      avg_quality_accuracy: update_prediction_accuracy(existing_data, new_learning, :quality),
      success_rate: update_success_rate(existing_data, new_learning.outcome_success),
      improvement_rate: calculate_improvement_rate(existing_data, new_learning),
      last_updated: DateTime.utc_now()
    }
  end

  defp update_prediction_accuracy(existing_data, new_learning, metric_type) do
    {predicted, actual} =
      case metric_type do
        :cost -> {new_learning.predicted_cost, new_learning.actual_cost}
        :quality -> {new_learning.predicted_quality, new_learning.actual_quality}
      end

    if predicted > 0 and actual > 0 do
      accuracy = 1.0 - abs(predicted - actual) / max(predicted, actual)

      accuracy_key = String.to_atom("avg_#{metric_type}_accuracy")
      current_accuracy = Map.get(existing_data, accuracy_key, 0.7)
      current_count = Map.get(existing_data, :total_requests, 0)

      if current_count > 0 do
        (current_accuracy * current_count + accuracy) / (current_count + 1)
      else
        accuracy
      end
    else
      Map.get(existing_data, String.to_atom("avg_#{metric_type}_accuracy"), 0.7)
    end
  end

  defp update_success_rate(existing_data, outcome_success) do
    current_rate = Map.get(existing_data, :success_rate, 0.8)
    current_count = Map.get(existing_data, :total_requests, 0)

    if current_count > 0 do
      (current_rate * current_count + if(outcome_success, do: 1, else: 0)) / (current_count + 1)
    else
      if outcome_success, do: 1.0, else: 0.0
    end
  end

  defp calculate_improvement_rate(existing_data, new_learning) do
    # Calculate how much the provider is improving over time
    recent_accuracy = (new_learning.predicted_cost + new_learning.predicted_quality) / 2
    historical_accuracy = Map.get(existing_data, :avg_accuracy, 0.7)

    improvement = recent_accuracy - historical_accuracy

    # Smooth the improvement rate
    current_rate = Map.get(existing_data, :improvement_rate, 0.0)
    current_rate * 0.8 + improvement * 0.2
  end

  # Helper functions for analysis

  defp analyze_content_complexity(request) do
    content =
      case request.content do
        content when is_binary(content) -> content
        content when is_list(content) -> Enum.map_join(content, " ", &to_string/1)
        _ -> ""
      end

    content_length = String.length(content)

    case content_length do
      length when length > 5000 -> :high
      length when length > 1500 -> :medium
      _ -> :low
    end
  end

  defp estimate_token_requirements(request) do
    content =
      case request.content do
        content when is_binary(content) -> content
        content when is_list(content) -> Enum.map_join(content, " ", &to_string/1)
        _ -> ""
      end

    # Basic estimation: ~4 characters per token + overhead
    base_tokens = div(String.length(content), 4)
    # Add overhead for prompts and response
    base_tokens + 300
  end

  defp extract_quality_requirements(context) do
    %{
      min_quality_score: Map.get(context, :min_quality_score, 0.7),
      quality_priority: Map.get(context, :quality_priority, :medium),
      constitutional_ai_required: Map.get(context, :constitutional_ai_required, false)
    }
  end

  defp extract_cost_constraints(context) do
    %{
      max_cost_per_request: Map.get(context, :max_cost_per_request, 1.0),
      cost_priority: Map.get(context, :cost_priority, :medium),
      budget_remaining: Map.get(context, :budget_remaining, 100.0)
    }
  end

  defp extract_performance_requirements(context) do
    %{
      max_response_time: Map.get(context, :max_response_time, 10_000),
      performance_priority: Map.get(context, :performance_priority, :medium),
      streaming_required: Map.get(context, :streaming_required, false)
    }
  end

  defp extract_user_preferences(context) do
    %{
      preferred_providers: Map.get(context, :preferred_providers, []),
      constitutional_ai_preference: Map.get(context, :constitutional_ai_preference, false),
      cost_quality_balance: Map.get(context, :cost_quality_balance, 0.5)
    }
  end

  defp analyze_domain_specific_needs(domain, request) do
    case domain do
      :evaluation ->
        %{
          evaluation_type: Map.get(request, :evaluation_type, :quality),
          criteria_complexity: map_size(Map.get(request, :criteria, %{})),
          constitutional_ai_needs: request_needs_constitutional_ai?(request)
        }

      :orchestration ->
        %{
          coordination_complexity: analyze_coordination_complexity(request),
          agent_communication_needs: Map.get(request, :agent_communication, false),
          workflow_complexity: Map.get(request, :workflow_complexity, :standard)
        }

      :skills ->
        %{
          skill_execution_needs: Map.get(request, :skill_types, []),
          orchestration_requirements: Map.get(request, :orchestration_requirements, %{}),
          learning_integration: Map.get(request, :learning_integration, false)
        }

      _ ->
        %{domain_specific: false}
    end
  end

  defp request_needs_constitutional_ai?(request) do
    evaluation_type = Map.get(request, :evaluation_type, :quality)

    evaluation_type in [:security, :safety, :ethics] or
      Map.get(request, :constitutional_ai_required, false)
  end

  defp analyze_coordination_complexity(request) do
    # Analyze coordination complexity for orchestration requests
    content = request.content || ""

    coordination_indicators = ["coordinate", "agent", "workflow", "parallel", "sequential"]

    complexity_score =
      coordination_indicators
      |> Enum.count(&String.contains?(String.downcase(content), &1))

    case complexity_score do
      score when score >= 3 -> :high
      score when score >= 1 -> :medium
      _ -> :low
    end
  end

  # Historical data functions (would integrate with actual learning system)

  defp get_historical_cost_efficiency(provider_type, state) do
    case get_in(state, [:provider_learning, provider_type, :avg_cost_accuracy]) do
      # Default
      nil -> 0.7
      accuracy -> accuracy
    end
  end

  defp get_historical_quality_performance(provider_type, state) do
    case get_in(state, [:provider_learning, provider_type, :avg_quality_accuracy]) do
      # Default
      nil -> 0.8
      accuracy -> accuracy
    end
  end

  defp get_historical_reliability(provider_type, state) do
    case get_in(state, [:provider_learning, provider_type, :success_rate]) do
      # Default
      nil -> 0.9
      rate -> rate
    end
  end

  defp get_historical_quality_adjustment(provider_type, state) do
    improvement_rate =
      get_in(state, [:provider_learning, provider_type, :improvement_rate]) || 0.0

    # Convert to quality adjustment
    improvement_rate * 0.1
  end

  defp get_provider_learning_data(provider_type, state) do
    get_in(state, [:provider_learning, provider_type])
  end

  # Utility functions

  defp enhance_with_historical_data(requirements_analysis, state) do
    # Enhance analysis with historical performance data
    historical_insights = extract_historical_insights(state)

    Map.merge(requirements_analysis, %{
      historical_insights: historical_insights,
      learning_confidence: calculate_learning_confidence(state)
    })
  end

  defp extract_historical_insights(state) do
    provider_learning = Map.get(state, :provider_learning, %{})

    %{
      best_performing_provider: find_best_performing_provider(provider_learning),
      most_reliable_provider: find_most_reliable_provider(provider_learning),
      cost_efficient_provider: find_most_cost_efficient_provider(provider_learning),
      total_learning_data_points: count_total_learning_data_points(provider_learning)
    }
  end

  defp find_best_performing_provider(provider_learning) do
    case provider_learning do
      data when map_size(data) > 0 ->
        data
        |> Enum.max_by(fn {_provider, learning_data} ->
          (Map.get(learning_data, :avg_quality_accuracy, 0.5) +
             Map.get(learning_data, :success_rate, 0.5)) / 2
        end)
        |> elem(0)

      _ ->
        :unknown
    end
  end

  defp find_most_reliable_provider(provider_learning) do
    case provider_learning do
      data when map_size(data) > 0 ->
        data
        |> Enum.max_by(fn {_provider, learning_data} ->
          Map.get(learning_data, :success_rate, 0.5)
        end)
        |> elem(0)

      _ ->
        :unknown
    end
  end

  defp find_most_cost_efficient_provider(provider_learning) do
    case provider_learning do
      data when map_size(data) > 0 ->
        data
        |> Enum.max_by(fn {_provider, learning_data} ->
          Map.get(learning_data, :avg_cost_accuracy, 0.5)
        end)
        |> elem(0)

      _ ->
        :unknown
    end
  end

  defp count_total_learning_data_points(provider_learning) do
    provider_learning
    |> Map.values()
    |> Enum.map(&Map.get(&1, :total_requests, 0))
    |> Enum.sum()
  end

  defp calculate_learning_confidence(state) do
    total_data_points = count_total_learning_data_points(Map.get(state, :provider_learning, %{}))

    case total_data_points do
      points when points > 100 -> :high
      points when points > 30 -> :medium
      points when points > 10 -> :low
      _ -> :insufficient
    end
  end

  defp generate_optimization_recommendations(enhanced_analysis) do
    recommendations = []

    # Cost optimization recommendations
    recommendations =
      if enhanced_analysis.cost_constraints.cost_priority == :high do
        ["Consider cost-optimized providers for budget efficiency" | recommendations]
      else
        recommendations
      end

    # Quality optimization recommendations
    recommendations =
      if enhanced_analysis.quality_requirements.constitutional_ai_required do
        ["Use Constitutional AI providers for safety-critical operations" | recommendations]
      else
        recommendations
      end

    # Performance recommendations
    recommendations =
      if enhanced_analysis.performance_requirements.max_response_time < 3000 do
        ["Prioritize fast-response providers for latency-sensitive operations" | recommendations]
      else
        recommendations
      end

    case recommendations do
      [] -> ["Standard provider selection recommended"]
      recs -> recs
    end
  end

  defp assess_provider_suitability(enhanced_analysis) do
    # Assess which providers are suitable for requirements
    %{
      anthropic_suitability: assess_anthropic_suitability(enhanced_analysis),
      openai_suitability: assess_openai_suitability(enhanced_analysis),
      ollama_suitability: assess_ollama_suitability(enhanced_analysis)
    }
  end

  defp assess_anthropic_suitability(analysis) do
    # Base suitability
    score = 0.8

    # Boost for Constitutional AI requirements
    score =
      if analysis.quality_requirements.constitutional_ai_required do
        score + 0.15
      else
        score
      end

    # Reduce for strict cost constraints
    score =
      if analysis.cost_constraints.cost_priority == :high do
        score - 0.1
      else
        score
      end

    min(1.0, max(0.0, score))
  end

  defp assess_openai_suitability(analysis) do
    # Base suitability
    score = 0.85

    # Boost for performance requirements
    score =
      if analysis.performance_requirements.performance_priority == :high do
        score + 0.1
      else
        score
      end

    # Boost for cost efficiency
    score =
      if analysis.cost_constraints.cost_priority == :high do
        score + 0.05
      else
        score
      end

    min(1.0, max(0.0, score))
  end

  defp assess_ollama_suitability(analysis) do
    # Base suitability
    score = 0.7

    # Boost for cost optimization (local models are free)
    score =
      if analysis.cost_constraints.cost_priority == :high do
        score + 0.2
      else
        score
      end

    # Boost for performance (local models are fast)
    score =
      if analysis.performance_requirements.max_response_time < 3000 do
        score + 0.15
      else
        score
      end

    min(1.0, max(0.0, score))
  end

  # Additional utility functions

  defp generate_provider_recommendation(provider_type, provider_info, requirements, state) do
    suitability_score =
      case provider_type do
        :anthropic -> assess_anthropic_suitability(requirements)
        :openai -> assess_openai_suitability(requirements)
        :ollama -> assess_ollama_suitability(requirements)
        _ -> 0.6
      end

    %{
      provider: provider_type,
      overall_score: suitability_score,
      suitability_factors: get_suitability_factors(provider_type, requirements),
      recommended_model: select_optimal_model_for_provider(provider_type, requirements),
      cost_estimate: estimate_provider_cost(provider_type, requirements),
      quality_prediction: predict_provider_quality(provider_type, requirements, state),
      recommendation_reasoning:
        generate_provider_recommendation_reasoning(provider_type, suitability_score)
    }
  end

  defp get_suitability_factors(provider_type, requirements) do
    case provider_type do
      :anthropic -> ["Constitutional AI", "Large context", "Safety focus"]
      :openai -> ["Versatile", "Function calling", "Cost effective"]
      :ollama -> ["Local deployment", "Zero cost", "Privacy focused"]
      _ -> ["Standard capabilities"]
    end
  end

  defp generate_provider_recommendation_reasoning(provider_type, score) do
    quality_description =
      case score do
        s when s > 0.9 -> "excellent"
        s when s > 0.8 -> "very good"
        s when s > 0.7 -> "good"
        s when s > 0.6 -> "adequate"
        _ -> "limited"
      end

    "#{provider_type} provider - #{quality_description} suitability (#{Float.round(score, 2)})"
  end

  # Stubs for functions that would integrate with actual systems

  defp generate_analysis_metadata(_requirements, _state), do: %{}
  defp calculate_skill_confidence(_state), do: 0.8
  defp estimate_outcome_quality(outcome), do: if(outcome.success, do: 0.8, else: 0.3)
  defp calculate_prediction_accuracy(_learning_data), do: 0.75
  defp analyze_performance_trend(_learning_data, _state), do: :stable
  defp assess_optimization_effectiveness(_learning_data, _selection), do: 0.8
  defp generate_future_recommendations(_learning_data, _state), do: []
  defp measure_skill_improvement(_old_state, _new_state), do: %{improvement: 0.05}
  defp get_updated_provider_knowledge(state), do: Map.get(state, :provider_learning, %{})
  defp get_provider_specialization_factors(_provider_type, _requirements), do: []
  defp calculate_domain_fit_factor(_provider_type, _domain), do: 0.8
end
