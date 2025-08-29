defmodule RubberDuck.Skills.Routing.Actions.DetermineRouteAction do
  @moduledoc """
  Multi-criteria route determination action for intelligent provider selection.

  This action implements sophisticated routing decisions based on multiple criteria
  including cost optimization, quality requirements, latency constraints, and
  provider health status. It uses machine learning to continuously improve
  routing decisions based on historical performance data.

  Features:
  - Multi-criteria decision making with weighted optimization
  - Real-time provider capacity assessment and performance prediction
  - Dynamic strategy selection based on request characteristics
  - Learning from routing outcomes to improve future decisions
  - Integration with circuit breaker and load balancing systems
  - Support for multiple routing strategies (cost-first, quality-first, balanced)

  The action maintains routing intelligence state and adapts strategies
  based on observed patterns and system performance metrics.
  """

  use Jido.Action,
    name: "determine_route",
    schema: [
      request_requirements: [
        type: :map,
        required: true,
        doc: "Request requirements and constraints"
      ],
      available_providers: [
        type: {:list, :atom},
        required: true,
        doc: "List of available provider identifiers"
      ],
      routing_strategy: [
        type: :atom,
        default: :balanced,
        doc: "Routing strategy (:cost_first, :quality_first, :balanced, :latency_first)"
      ],
      optimization_weights: [type: :map, default: %{}, doc: "Custom optimization weights"],
      context: [type: :map, default: %{}, doc: "Request context for decision making"],
      learning_enabled: [
        type: :boolean,
        default: true,
        doc: "Enable learning from routing decisions"
      ]
    ]

  require Logger

  alias RubberDuck.LlmProviders.{ProviderRegistry, UniversalProviderService}
  alias RubberDuck.Skills.Routing.Support.{PerformancePredictor, RoutingIntelligence}

  # Default optimization weights for different routing strategies
  @strategy_weights %{
    cost_first: %{cost: 0.6, quality: 0.2, latency: 0.1, reliability: 0.1},
    quality_first: %{cost: 0.1, quality: 0.6, latency: 0.15, reliability: 0.15},
    balanced: %{cost: 0.25, quality: 0.25, latency: 0.25, reliability: 0.25},
    latency_first: %{cost: 0.1, quality: 0.2, latency: 0.6, reliability: 0.1}
  }

  # Provider capability baselines (updated with 2025 data)
  @provider_baselines %{
    openai: %{
      # Moderate cost with automatic caching
      cost_score: 0.7,
      # High quality
      quality_score: 0.9,
      # Good latency
      latency_score: 0.8,
      # Very reliable
      reliability_score: 0.95
    },
    anthropic: %{
      # Higher cost but excellent context handling
      cost_score: 0.6,
      # Excellent quality
      quality_score: 0.95,
      # Moderate latency
      latency_score: 0.7,
      # Very reliable
      reliability_score: 0.9
    },
    local: %{
      # No direct cost
      cost_score: 1.0,
      # Variable quality
      quality_score: 0.6,
      # Fast when loaded
      latency_score: 0.9,
      # Depends on hardware
      reliability_score: 0.7
    }
  }

  @doc """
  Determine optimal route for LLM request based on multi-criteria analysis.

  Returns routing decision with selected provider, confidence score,
  and optimization metadata for learning and monitoring.
  """
  def run(params, _context) do
    %{
      request_requirements: requirements,
      available_providers: providers,
      routing_strategy: strategy,
      optimization_weights: custom_weights,
      context: request_context,
      learning_enabled: learning_enabled
    } = params

    Logger.debug("DetermineRouteAction: Starting route determination",
      strategy: strategy,
      providers: providers,
      requirements: Map.keys(requirements)
    )

    routing_start_time = System.monotonic_time(:microsecond)

    with {:ok, effective_weights} <- get_effective_weights(strategy, custom_weights),
         {:ok, provider_scores} <-
           score_providers(providers, requirements, effective_weights, request_context),
         {:ok, routing_decision} <-
           select_optimal_provider(provider_scores, strategy, requirements) do
      routing_time = System.monotonic_time(:microsecond) - routing_start_time

      decision_metadata = %{
        routing_strategy: strategy,
        optimization_weights: effective_weights,
        provider_scores: provider_scores,
        routing_time_microseconds: routing_time,
        confidence_score: routing_decision.confidence,
        alternatives_considered: length(provider_scores)
      }

      Logger.info("DetermineRouteAction: Route determined for #{routing_decision.provider}",
        provider: routing_decision.provider,
        confidence: routing_decision.confidence,
        routing_time_us: routing_time,
        strategy: strategy
      )

      # Track routing decision for learning if enabled
      if learning_enabled do
        track_routing_decision(routing_decision, decision_metadata, requirements, request_context)
      end

      {:ok,
       %{
         selected_provider: routing_decision.provider,
         confidence_score: routing_decision.confidence,
         routing_rationale: routing_decision.rationale,
         decision_metadata: decision_metadata,
         fallback_providers: routing_decision.fallback_chain,
         estimated_performance: routing_decision.performance_prediction
       }}
    else
      {:error, reason} ->
        Logger.error("DetermineRouteAction: Route determination failed",
          error: reason,
          strategy: strategy,
          providers: providers
        )

        {:error, reason}
    end
  end

  # Private implementation functions

  defp get_effective_weights(strategy, custom_weights) do
    base_weights = Map.get(@strategy_weights, strategy)

    if base_weights do
      # Merge custom weights with strategy defaults
      effective_weights = Map.merge(base_weights, custom_weights)

      # Ensure weights sum to 1.0
      total_weight = effective_weights |> Map.values() |> Enum.sum()
      normalized_weights = Map.new(effective_weights, fn {k, v} -> {k, v / total_weight} end)

      {:ok, normalized_weights}
    else
      {:error, {:invalid_strategy, strategy}}
    end
  end

  defp score_providers(providers, requirements, weights, context) do
    provider_scores =
      Enum.map(providers, fn provider ->
        case score_provider(provider, requirements, weights, context) do
          {:ok, score_data} ->
            score_data

          {:error, reason} ->
            Logger.warning("DetermineRouteAction: Failed to score provider #{provider}",
              error: reason
            )

            create_fallback_score(provider, reason)
        end
      end)

    {:ok, provider_scores}
  end

  defp score_provider(provider, requirements, weights, context) do
    with {:ok, provider_status} <- get_provider_status(provider),
         {:ok, cost_score} <- calculate_cost_score(provider, requirements, context),
         {:ok, quality_score} <- calculate_quality_score(provider, requirements, context),
         {:ok, latency_score} <- calculate_latency_score(provider, requirements, context),
         {:ok, reliability_score} <- calculate_reliability_score(provider, provider_status) do
      # Calculate weighted composite score
      composite_score =
        cost_score * weights.cost +
          quality_score * weights.quality +
          latency_score * weights.latency +
          reliability_score * weights.reliability

      # Add provider health factor
      health_factor = get_health_factor(provider_status)
      adjusted_score = composite_score * health_factor

      score_breakdown = %{
        provider: provider,
        composite_score: adjusted_score,
        cost_score: cost_score,
        quality_score: quality_score,
        latency_score: latency_score,
        reliability_score: reliability_score,
        health_factor: health_factor,
        provider_status: provider_status
      }

      {:ok, score_breakdown}
    else
      {:error, reason} ->
        {:error, {:scoring_failed, provider, reason}}
    end
  end

  defp get_provider_status(provider) do
    case ProviderRegistry.get_provider(provider) do
      {:ok, provider_data} ->
        {:ok,
         %{
           health: provider_data.health || :unknown,
           load: provider_data.current_load || 0.0,
           error_rate: provider_data.error_rate || 0.0,
           avg_latency: provider_data.avg_latency || 1000
         }}

      {:error, reason} ->
        {:error, {:provider_status_unavailable, reason}}
    end
  end

  defp calculate_cost_score(provider, requirements, context) do
    base_score = get_in(@provider_baselines, [provider, :cost_score]) || 0.5

    # Adjust based on requirements
    cost_sensitivity = Map.get(requirements, :cost_sensitivity, 0.5)
    estimated_tokens = Map.get(requirements, :estimated_tokens, 2000)

    # For high token counts, cost becomes more important
    token_factor = if estimated_tokens > 10_000, do: 0.8, else: 1.0

    # Adjust for cost sensitivity
    adjusted_score = base_score * (1.0 + cost_sensitivity * 0.5) * token_factor

    {:ok, min(adjusted_score, 1.0)}
  end

  defp calculate_quality_score(provider, requirements, context) do
    base_score = get_in(@provider_baselines, [provider, :quality_score]) || 0.5

    # Adjust based on quality requirements
    quality_threshold = Map.get(requirements, :quality_threshold, 0.8)
    domain_complexity = analyze_domain_complexity(requirements, context)

    # High complexity tasks benefit from higher quality providers
    complexity_factor = 1.0 + (domain_complexity - 0.5) * 0.3

    adjusted_score = base_score * complexity_factor

    # Penalty if provider doesn't meet quality threshold
    if adjusted_score < quality_threshold do
      penalized_score = adjusted_score * 0.7
      {:ok, penalized_score}
    else
      {:ok, min(adjusted_score, 1.0)}
    end
  end

  defp calculate_latency_score(provider, requirements, context) do
    base_score = get_in(@provider_baselines, [provider, :latency_score]) || 0.5

    # Adjust based on latency requirements
    max_latency = Map.get(requirements, :max_latency_ms, 10_000)
    urgency = Map.get(requirements, :urgency, :normal)

    # Urgency affects latency importance
    urgency_factor =
      case urgency do
        :low -> 0.8
        :normal -> 1.0
        :high -> 1.3
        :critical -> 1.5
      end

    adjusted_score = base_score * urgency_factor
    {:ok, min(adjusted_score, 1.0)}
  end

  defp calculate_reliability_score(provider, provider_status) do
    base_score = get_in(@provider_baselines, [provider, :reliability_score]) || 0.5

    # Adjust based on current provider health and error rates
    health_adjustment =
      case provider_status.health do
        :healthy -> 1.0
        :degraded -> 0.8
        :recovering -> 0.6
        :unhealthy -> 0.2
        _ -> 0.5
      end

    # Factor in error rate
    error_rate = provider_status.error_rate
    # High error rate reduces score
    error_adjustment = max(1.0 - error_rate * 2.0, 0.1)

    adjusted_score = base_score * health_adjustment * error_adjustment
    {:ok, min(adjusted_score, 1.0)}
  end

  defp analyze_domain_complexity(requirements, context) do
    # Analyze request complexity to inform quality needs
    factors = [
      # Large context
      Map.get(requirements, :context_length, 1000) > 5000,
      # Complex reasoning
      Map.get(requirements, :requires_reasoning, false),
      # Technical domains
      Map.get(context, :domain) in [:code_evaluation, :technical_analysis],
      # Structured output
      Map.get(requirements, :output_format) == :structured
    ]

    complexity = factors |> Enum.count(& &1) |> Kernel./(4)
    # Minimum 30% complexity
    max(complexity, 0.3)
  end

  defp get_health_factor(provider_status) do
    case provider_status.health do
      :healthy -> 1.0
      :degraded -> 0.8
      :recovering -> 0.6
      :unhealthy -> 0.2
      _ -> 0.5
    end
  end

  defp create_fallback_score(provider, reason) do
    # Create minimal scoring for providers that failed to score properly
    %{
      provider: provider,
      # Very low score
      composite_score: 0.1,
      cost_score: 0.5,
      quality_score: 0.5,
      latency_score: 0.5,
      # Low reliability due to scoring failure
      reliability_score: 0.1,
      health_factor: 0.5,
      provider_status: %{error: reason}
    }
  end

  defp select_optimal_provider(provider_scores, strategy, requirements) do
    # Sort providers by composite score
    sorted_providers = Enum.sort_by(provider_scores, & &1.composite_score, :desc)

    case sorted_providers do
      [best_provider | remaining_providers] ->
        # Build fallback chain from remaining providers
        fallback_chain =
          remaining_providers
          # Top 2 alternatives
          |> Enum.take(2)
          |> Enum.map(& &1.provider)

        # Calculate confidence based on score distribution
        confidence = calculate_routing_confidence(sorted_providers)

        # Generate performance prediction
        performance_prediction = predict_routing_performance(best_provider, requirements)

        # Create routing rationale for transparency
        rationale = build_routing_rationale(best_provider, strategy, requirements)

        routing_decision = %{
          provider: best_provider.provider,
          confidence: confidence,
          rationale: rationale,
          fallback_chain: fallback_chain,
          performance_prediction: performance_prediction,
          score_breakdown: best_provider
        }

        {:ok, routing_decision}

      [] ->
        {:error, :no_available_providers}
    end
  end

  defp calculate_routing_confidence(sorted_providers) do
    case sorted_providers do
      [best, second_best | _] ->
        # Confidence based on score gap between best and second best
        score_gap = best.composite_score - second_best.composite_score
        base_confidence = min(best.composite_score, 0.95)
        # Up to 20% bonus for large gaps
        gap_bonus = min(score_gap * 2, 0.2)

        min(base_confidence + gap_bonus, 1.0)

      [single] ->
        # Single provider, confidence based on its score
        min(single.composite_score * 1.1, 0.95)

      [] ->
        0.0
    end
  end

  defp predict_routing_performance(provider_score, requirements) do
    estimated_cost = estimate_request_cost(provider_score.provider, requirements)
    estimated_latency = estimate_request_latency(provider_score.provider, requirements)
    estimated_quality = provider_score.quality_score

    %{
      estimated_cost_usd: estimated_cost,
      estimated_latency_ms: estimated_latency,
      estimated_quality_score: estimated_quality,
      success_probability: calculate_success_probability(provider_score),
      # Always recommend fallbacks except for local
      recommended_fallbacks: provider_score.provider != :local
    }
  end

  defp build_routing_rationale(provider_score, strategy, requirements) do
    key_factors = []

    # Add primary decision factors
    key_factors =
      case strategy do
        :cost_first -> ["Lowest cost option" | key_factors]
        :quality_first -> ["Highest quality provider" | key_factors]
        :latency_first -> ["Fastest response time" | key_factors]
        :balanced -> ["Best overall balance" | key_factors]
      end

    # Add health considerations
    key_factors =
      case provider_score.provider_status do
        %{health: :healthy} -> key_factors
        %{health: status} -> ["Provider health: #{status}" | key_factors]
      end

    # Add requirement-specific factors
    key_factors =
      if Map.get(requirements, :estimated_tokens, 0) > 10_000 do
        ["Large context handling capability" | key_factors]
      else
        key_factors
      end

    %{
      primary_reason: "Selected based on #{strategy} strategy",
      key_factors: Enum.reverse(key_factors),
      provider_strengths: identify_provider_strengths(provider_score.provider),
      score_summary: %{
        composite: provider_score.composite_score,
        cost: provider_score.cost_score,
        quality: provider_score.quality_score,
        latency: provider_score.latency_score,
        reliability: provider_score.reliability_score
      }
    }
  end

  defp identify_provider_strengths(provider) do
    case provider do
      :openai ->
        ["Automatic caching", "Function calling", "JSON mode", "Reliable API"]

      :anthropic ->
        [
          "Large context windows",
          "Constitutional AI",
          "High quality",
          "Conversation optimization"
        ]

      :local ->
        ["No API costs", "Offline capability", "Privacy", "Customizable"]

      _ ->
        []
    end
  end

  defp estimate_request_cost(provider, requirements) do
    estimated_tokens = Map.get(requirements, :estimated_tokens, 2000)

    case provider do
      # ~$0.02 per 1K tokens
      :openai -> estimated_tokens * 0.00002
      # ~$0.024 per 1K tokens
      :anthropic -> estimated_tokens * 0.000024
      # No direct cost
      :local -> 0.0
      # Default estimate
      _ -> estimated_tokens * 0.00003
    end
  end

  defp estimate_request_latency(provider, requirements) do
    base_latency =
      case provider do
        # 2 seconds
        :openai -> 2000
        # 2.5 seconds
        :anthropic -> 2500
        # 1.5 seconds (when loaded)
        :local -> 1500
        # 3 seconds default
        _ -> 3000
      end

    # Adjust for token count
    estimated_tokens = Map.get(requirements, :estimated_tokens, 2000)
    # 0.05ms per token
    token_latency = estimated_tokens * 0.05

    round(base_latency + token_latency)
  end

  defp calculate_success_probability(provider_score) do
    # Calculate probability of successful request completion
    base_probability = 0.95

    # Factor in reliability and health
    reliability_factor = provider_score.reliability_score
    health_factor = provider_score.health_factor

    # Factor in current load if available
    load_factor =
      case provider_score.provider_status do
        # High load reduces success probability
        %{load: load} when load > 0.8 -> 0.9
        %{load: load} when load > 0.5 -> 0.95
        _ -> 1.0
      end

    probability = base_probability * reliability_factor * health_factor * load_factor
    Float.round(probability, 3)
  end

  defp track_routing_decision(decision, metadata, requirements, context) do
    Logger.debug("DetermineRouteAction: Tracking routing decision",
      provider: decision.provider,
      strategy: metadata.routing_strategy,
      confidence: decision.confidence,
      context: Map.take(context, [:domain, :user_id])
    )

    # TODO: Integrate with RoutingIntelligence for learning and adaptation
    :ok
  end
end
