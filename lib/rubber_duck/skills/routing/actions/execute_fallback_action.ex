defmodule RubberDuck.Skills.Routing.Actions.ExecuteFallbackAction do
  @moduledoc """
  Quality-preserving fallback execution action for seamless provider failover.

  This action implements intelligent fallback coordination that preserves response
  quality during provider failures, optimizes costs across fallback chains, and
  ensures transparent user experiences during provider transitions.

  Features:
  - Intelligent fallback chain selection with quality preservation algorithms
  - Quality degradation minimization through provider capability matching
  - Cost optimization across fallback chains with budget awareness
  - Seamless transition management with context preservation
  - User experience preservation through transparent failovers
  - Learning from fallback outcomes to improve future chain selection

  Fallback Strategies:
  - **Quality Preservation**: Maintain response quality standards during failover
  - **Cost Optimization**: Minimize cost impact while ensuring acceptable quality
  - **Latency Minimization**: Fastest possible failover with quality constraints
  - **Capability Matching**: Match request requirements to provider capabilities
  """

  use Jido.Action,
    name: "execute_fallback",
    schema: [
      primary_provider: [type: :atom, required: true, doc: "Primary provider that failed"],
      failure_reason: [
        type: :atom,
        required: true,
        doc: "Reason for fallback (:timeout, :error, :circuit_open, etc.)"
      ],
      request_params: [type: :map, required: true, doc: "Original request parameters"],
      fallback_chain: [
        type: {:list, :atom},
        default: [],
        doc: "Ordered list of fallback providers"
      ],
      quality_requirements: [type: :map, default: %{}, doc: "Quality preservation requirements"],
      cost_constraints: [type: :map, default: %{}, doc: "Cost optimization constraints"],
      context: [type: :map, default: %{}, doc: "Request context for preservation"]
    ]

  require Logger

  alias RubberDuck.LlmProviders.{ProviderRegistry, UniversalProviderService}
  alias RubberDuck.Skills.Actions.CallAPIAction
  alias RubberDuck.Skills.Routing.Actions.DetermineRouteAction

  # Fallback strategy configurations
  @fallback_strategies %{
    quality_preservation: %{
      description: "Maintain quality at reasonable cost",
      quality_weight: 0.6,
      cost_weight: 0.2,
      latency_weight: 0.2
    },
    cost_optimization: %{
      description: "Minimize cost while preserving acceptable quality",
      quality_weight: 0.3,
      cost_weight: 0.5,
      latency_weight: 0.2
    },
    latency_minimization: %{
      description: "Fastest failover with quality constraints",
      quality_weight: 0.3,
      cost_weight: 0.1,
      latency_weight: 0.6
    },
    capability_matching: %{
      description: "Match provider capabilities to request needs",
      quality_weight: 0.4,
      cost_weight: 0.3,
      latency_weight: 0.3
    }
  }

  # Quality degradation thresholds
  @quality_thresholds %{
    # <5% quality loss acceptable
    minimal_degradation: 0.95,
    # <15% quality loss acceptable
    acceptable_degradation: 0.85,
    # <30% quality loss limit
    significant_degradation: 0.70
  }

  # Provider capability matching for quality preservation
  @provider_capabilities %{
    openai: %{
      # Good context handling
      context_handling: 0.85,
      # Excellent reasoning
      reasoning_quality: 0.9,
      # Excellent structured output
      structured_output: 0.95,
      # Moderate cost efficiency
      cost_efficiency: 0.7
    },
    anthropic: %{
      # Excellent context handling
      context_handling: 0.98,
      # Outstanding reasoning
      reasoning_quality: 0.95,
      # Good structured output
      structured_output: 0.8,
      # Higher cost
      cost_efficiency: 0.6
    },
    local: %{
      # Limited context handling
      context_handling: 0.6,
      # Decent reasoning
      reasoning_quality: 0.7,
      # Variable structured output
      structured_output: 0.5,
      # No direct cost
      cost_efficiency: 1.0
    }
  }

  @doc """
  Execute intelligent fallback with quality preservation and cost optimization.

  Returns fallback execution result with quality analysis, cost impact,
  and learning data for continuous improvement of fallback strategies.
  """
  def run(params, _context) do
    %{
      primary_provider: primary_provider,
      failure_reason: failure_reason,
      request_params: request_params,
      fallback_chain: fallback_chain,
      quality_requirements: quality_reqs,
      cost_constraints: cost_constraints,
      context: request_context
    } = params

    Logger.info("ExecuteFallbackAction: Executing fallback from #{primary_provider}",
      primary_provider: primary_provider,
      failure_reason: failure_reason,
      fallback_chain: fallback_chain
    )

    fallback_start_time = System.monotonic_time(:microsecond)

    with {:ok, fallback_strategy} <-
           determine_fallback_strategy(failure_reason, quality_reqs, cost_constraints),
         {:ok, optimized_chain} <-
           optimize_fallback_chain(
             fallback_chain,
             request_params,
             fallback_strategy,
             request_context
           ),
         {:ok, execution_result} <-
           execute_fallback_chain(
             optimized_chain,
             request_params,
             fallback_strategy,
             request_context
           ) do
      fallback_time = System.monotonic_time(:microsecond) - fallback_start_time

      # Analyze fallback outcome
      outcome_analysis =
        analyze_fallback_outcome(execution_result, primary_provider, fallback_strategy)

      # Calculate quality preservation metrics
      quality_metrics = calculate_quality_preservation(execution_result, quality_reqs)

      # Calculate cost impact
      cost_impact =
        calculate_fallback_cost_impact(primary_provider, execution_result, cost_constraints)

      Logger.info("ExecuteFallbackAction: Fallback execution complete",
        successful_provider: execution_result.successful_provider,
        fallback_time_us: fallback_time,
        quality_preservation: quality_metrics.preservation_score,
        attempts_made: execution_result.attempts_made
      )

      # Track fallback outcome for learning
      track_fallback_outcome(
        primary_provider,
        execution_result,
        outcome_analysis,
        request_context
      )

      {:ok,
       %{
         fallback_successful: execution_result.success,
         successful_provider: execution_result.successful_provider,
         response: execution_result.response,
         quality_preservation_metrics: quality_metrics,
         cost_impact_analysis: cost_impact,
         fallback_metadata: %{
           primary_provider: primary_provider,
           failure_reason: failure_reason,
           strategy_used: fallback_strategy,
           attempts_made: execution_result.attempts_made,
           fallback_time_microseconds: fallback_time,
           chain_optimization_applied: execution_result.chain_was_optimized
         },
         outcome_analysis: outcome_analysis
       }}
    else
      {:error, reason} ->
        Logger.error("ExecuteFallbackAction: Fallback execution failed",
          primary_provider: primary_provider,
          failure_reason: failure_reason,
          error: reason
        )

        {:error, reason}
    end
  end

  # Private implementation functions

  defp determine_fallback_strategy(failure_reason, quality_reqs, cost_constraints) do
    # Determine optimal fallback strategy based on failure and requirements
    quality_threshold = Map.get(quality_reqs, :min_quality_score, 0.8)
    # 2x cost increase limit
    cost_budget = Map.get(cost_constraints, :max_cost_increase, 2.0)
    latency_tolerance = Map.get(quality_reqs, :max_latency_increase_ms, 5000)

    strategy =
      cond do
        # High quality requirements
        quality_threshold > 0.9 ->
          :quality_preservation

        # Tight cost constraints
        cost_budget < 1.5 ->
          :cost_optimization

        # Latency sensitive
        latency_tolerance < 2000 ->
          :latency_minimization

        # Rate limit or capacity issues
        failure_reason in [:rate_limit, :quota_exceeded] ->
          :capability_matching

        # Default balanced approach
        true ->
          :quality_preservation
      end

    strategy_config = Map.get(@fallback_strategies, strategy)

    {:ok,
     %{
       strategy: strategy,
       config: strategy_config,
       selection_reason:
         explain_strategy_selection(strategy, failure_reason, quality_threshold, cost_budget)
     }}
  end

  defp optimize_fallback_chain(fallback_chain, request_params, fallback_strategy, context) do
    if Enum.empty?(fallback_chain) do
      # No predefined chain, build optimal one
      build_optimal_fallback_chain(request_params, fallback_strategy, context)
    else
      # Optimize existing chain
      optimize_existing_chain(fallback_chain, request_params, fallback_strategy, context)
    end
  end

  defp build_optimal_fallback_chain(request_params, fallback_strategy, context) do
    Logger.debug("ExecuteFallbackAction: Building optimal fallback chain",
      strategy: fallback_strategy.strategy
    )

    # Get all available providers
    case ProviderRegistry.get_providers() do
      {:ok, available_providers} ->
        # Score providers for fallback suitability
        provider_scores =
          score_providers_for_fallback(
            available_providers,
            request_params,
            fallback_strategy,
            context
          )

        # Build chain based on scores
        optimal_chain =
          provider_scores
          |> Enum.sort_by(& &1.fallback_score, :desc)
          # Maximum 3 fallback attempts
          |> Enum.take(3)
          |> Enum.map(& &1.provider)

        {:ok, optimal_chain}

      {:error, reason} ->
        {:error, {:chain_building_failed, reason}}
    end
  end

  defp optimize_existing_chain(fallback_chain, request_params, fallback_strategy, context) do
    Logger.debug("ExecuteFallbackAction: Optimizing existing fallback chain")

    # Filter and reorder chain based on current provider states and strategy
    optimized_chain =
      fallback_chain
      |> Enum.filter(&provider_available_for_fallback?/1)
      |> Enum.sort_by(&calculate_fallback_priority(&1, request_params, fallback_strategy), :desc)

    if optimized_chain != [] do
      {:ok, optimized_chain}
    else
      # Original chain not viable, build new one
      build_optimal_fallback_chain(request_params, fallback_strategy, context)
    end
  end

  defp score_providers_for_fallback(providers, request_params, fallback_strategy, context) do
    Enum.map(providers, fn provider ->
      # Skip if provider not available for fallback
      if provider_available_for_fallback?(provider) do
        # Calculate fallback suitability score
        capability_match = calculate_capability_match(provider, request_params)
        cost_impact = calculate_cost_impact_score(provider, request_params)
        availability_score = calculate_availability_score(provider)

        # Weight scores based on strategy
        weights = fallback_strategy.config

        fallback_score =
          capability_match * weights.quality_weight +
            cost_impact * weights.cost_weight +
            availability_score * weights.latency_weight

        %{
          provider: provider,
          fallback_score: fallback_score,
          capability_match: capability_match,
          cost_impact: cost_impact,
          availability_score: availability_score
        }
      else
        # Provider not available, give very low score
        %{
          provider: provider,
          fallback_score: 0.0,
          available: false
        }
      end
    end)
    # Filter out very low scores
    |> Enum.filter(&(Map.get(&1, :fallback_score, 0) > 0.1))
  end

  defp execute_fallback_chain(fallback_chain, request_params, fallback_strategy, context) do
    Logger.info("ExecuteFallbackAction: Executing fallback chain",
      chain: fallback_chain,
      strategy: fallback_strategy.strategy
    )

    # Try each provider in the chain until success
    execute_chain_attempts(fallback_chain, request_params, fallback_strategy, context, 1, [])
  end

  defp execute_chain_attempts([], _request_params, _strategy, _context, attempts, attempt_history) do
    # All fallback providers failed
    Logger.error("ExecuteFallbackAction: All fallback providers failed")

    {:ok,
     %{
       success: false,
       attempts_made: attempts - 1,
       attempt_history: Enum.reverse(attempt_history),
       final_error: :all_fallbacks_failed
     }}
  end

  defp execute_chain_attempts(
         [provider | remaining],
         request_params,
         strategy,
         context,
         attempt_num,
         attempt_history
       ) do
    Logger.debug(
      "ExecuteFallbackAction: Attempting fallback to #{provider} (attempt #{attempt_num})"
    )

    # Adapt request parameters for this provider if needed
    adapted_params = adapt_params_for_provider(request_params, provider, strategy)

    # Execute request with fallback provider
    case execute_fallback_request(provider, adapted_params, context) do
      {:ok, response} ->
        # Success! Analyze quality preservation
        quality_analysis = analyze_response_quality(response, request_params, provider)

        Logger.info("ExecuteFallbackAction: Fallback successful with #{provider}",
          provider: provider,
          attempt: attempt_num,
          quality_score: quality_analysis.quality_score
        )

        attempt_record = %{
          provider: provider,
          attempt_number: attempt_num,
          success: true,
          quality_analysis: quality_analysis,
          response_metadata: extract_response_metadata(response)
        }

        {:ok,
         %{
           success: true,
           successful_provider: provider,
           response: response,
           attempts_made: attempt_num,
           attempt_history: Enum.reverse([attempt_record | attempt_history]),
           quality_analysis: quality_analysis,
           chain_was_optimized: length(remaining) + 1 != attempt_num
         }}

      {:error, reason} ->
        # This fallback failed, try next
        Logger.warning("ExecuteFallbackAction: Fallback to #{provider} failed",
          provider: provider,
          attempt: attempt_num,
          error: reason
        )

        attempt_record = %{
          provider: provider,
          attempt_number: attempt_num,
          success: false,
          error: reason,
          timestamp: System.system_time(:second)
        }

        # Continue with remaining providers
        execute_chain_attempts(remaining, request_params, strategy, context, attempt_num + 1, [
          attempt_record | attempt_history
        ])
    end
  end

  defp provider_available_for_fallback?(provider) do
    case ProviderRegistry.get_provider(provider) do
      {:ok, provider_data} ->
        health = Map.get(provider_data, :health, :unknown)
        circuit_state = Map.get(provider_data, :circuit_state, :closed)

        health in [:healthy, :degraded] and circuit_state in [:closed, :half_open]

      {:error, _reason} ->
        false
    end
  end

  defp calculate_capability_match(provider, request_params) do
    provider_caps = Map.get(@provider_capabilities, provider, %{})

    # Analyze request requirements
    estimated_tokens = Map.get(request_params, :estimated_tokens, 2000)
    requires_reasoning = Map.get(request_params, :requires_reasoning, false)
    output_structured = Map.get(request_params, :response_format) != nil

    # Calculate match scores
    context_score =
      if estimated_tokens > 10_000 do
        Map.get(provider_caps, :context_handling, 0.5)
      else
        # All providers handle small contexts well
        1.0
      end

    reasoning_score =
      if requires_reasoning do
        Map.get(provider_caps, :reasoning_quality, 0.5)
      else
        # Not required
        1.0
      end

    structure_score =
      if output_structured do
        Map.get(provider_caps, :structured_output, 0.5)
      else
        # Not required
        1.0
      end

    # Weighted average of capability matches
    context_score * 0.4 + reasoning_score * 0.4 + structure_score * 0.2
  end

  defp calculate_cost_impact_score(provider, request_params) do
    # Calculate cost impact of using this provider as fallback
    estimated_tokens = Map.get(request_params, :estimated_tokens, 2000)

    cost_per_token =
      case provider do
        # ~$0.02 per 1K tokens
        :openai -> 0.00002
        # ~$0.024 per 1K tokens
        :anthropic -> 0.000024
        # No direct cost
        :local -> 0.0
      end

    estimated_cost = estimated_tokens * cost_per_token
    # $0.10 max for cost scoring
    max_reasonable_cost = 0.10

    # Invert cost for scoring (lower cost = higher score)
    cost_score = max(1.0 - estimated_cost / max_reasonable_cost, 0.1)
    Float.round(cost_score, 3)
  end

  defp calculate_availability_score(provider) do
    case ProviderRegistry.get_provider(provider) do
      {:ok, provider_data} ->
        health = Map.get(provider_data, :health, :unknown)
        current_load = Map.get(provider_data, :current_load, 0.0)
        error_rate = Map.get(provider_data, :error_rate, 0.0)

        # Health score
        health_score =
          case health do
            :healthy -> 1.0
            :degraded -> 0.7
            :recovering -> 0.5
            _ -> 0.3
          end

        # Load score (lower load = higher availability)
        load_score = max(1.0 - current_load, 0.1)

        # Error rate score
        error_score = max(1.0 - error_rate * 2, 0.1)

        # Composite availability score
        availability = health_score * 0.5 + load_score * 0.3 + error_score * 0.2
        Float.round(availability, 3)

      {:error, _reason} ->
        # Very low availability if can't get provider data
        0.1
    end
  end

  defp calculate_fallback_priority(provider, request_params, fallback_strategy) do
    # Calculate priority for fallback ordering
    capability_match = calculate_capability_match(provider, request_params)
    cost_impact = calculate_cost_impact_score(provider, request_params)
    availability = calculate_availability_score(provider)

    weights = fallback_strategy.config

    priority_score =
      capability_match * weights.quality_weight +
        cost_impact * weights.cost_weight +
        availability * weights.latency_weight

    Float.round(priority_score, 3)
  end

  defp adapt_params_for_provider(request_params, provider, strategy) do
    # Adapt request parameters for specific provider characteristics
    base_params = request_params

    # Provider-specific adaptations
    adapted_params =
      case provider do
        :openai ->
          # OpenAI optimizations
          base_params
          |> maybe_enable_openai_caching()
          |> optimize_for_openai_models()

        :anthropic ->
          # Anthropic optimizations
          base_params
          |> optimize_for_large_context()
          |> adjust_anthropic_conversation_structure()

        :local ->
          # Local model optimizations
          base_params
          |> optimize_for_local_efficiency()
          |> reduce_token_usage_for_local()

        _ ->
          base_params
      end

    # Strategy-specific adaptations
    case strategy.strategy do
      :cost_optimization ->
        # Reduce token usage to minimize cost
        reduce_max_tokens_for_cost(adapted_params)

      :quality_preservation ->
        # Ensure parameters maximize quality
        optimize_for_quality(adapted_params, provider)

      :latency_minimization ->
        # Minimize processing time
        optimize_for_speed(adapted_params)

      _ ->
        adapted_params
    end
  end

  defp execute_fallback_request(provider, adapted_params, context) do
    # Execute request with fallback provider using adapted parameters
    fallback_context =
      Map.merge(context, %{
        fallback_request: true,
        fallback_provider: provider,
        original_context: context
      })

    case CallAPIAction.run(
           %{
             provider: provider,
             # Assume completion for fallback
             operation: :complete,
             request_params: adapted_params,
             context: fallback_context,
             # Limited retries for fallback
             retry_config: %{max_attempts: 2, base_backoff: 1000}
           },
           %{}
         ) do
      {:ok, result} ->
        {:ok, result.response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp analyze_fallback_outcome(execution_result, primary_provider, fallback_strategy) do
    case execution_result.success do
      true ->
        %{
          outcome: :success,
          provider_used: execution_result.successful_provider,
          strategy_effectiveness: :high,
          attempts_required: execution_result.attempts_made,
          quality_preserved: execution_result.quality_analysis.preservation_score > 0.85,
          lessons_learned:
            extract_success_lessons(execution_result, primary_provider, fallback_strategy)
        }

      false ->
        %{
          outcome: :failure,
          strategy_effectiveness: :low,
          attempts_made: execution_result.attempts_made,
          failure_analysis: execution_result.attempt_history,
          lessons_learned:
            extract_failure_lessons(execution_result, primary_provider, fallback_strategy)
        }
    end
  end

  defp calculate_quality_preservation(execution_result, quality_requirements) do
    if execution_result.success do
      expected_quality = Map.get(quality_requirements, :expected_quality_score, 0.8)
      actual_quality = execution_result.quality_analysis.quality_score

      preservation_score = actual_quality / expected_quality
      degradation_amount = max(expected_quality - actual_quality, 0.0)

      degradation_level =
        cond do
          preservation_score >= @quality_thresholds.minimal_degradation -> :minimal
          preservation_score >= @quality_thresholds.acceptable_degradation -> :acceptable
          preservation_score >= @quality_thresholds.significant_degradation -> :significant
          true -> :severe
        end

      %{
        preservation_score: Float.round(preservation_score, 3),
        quality_degradation: Float.round(degradation_amount, 3),
        degradation_level: degradation_level,
        quality_acceptable: degradation_level in [:minimal, :acceptable],
        original_quality_target: expected_quality,
        achieved_quality: actual_quality
      }
    else
      %{
        preservation_score: 0.0,
        quality_degradation: 1.0,
        degradation_level: :complete_failure,
        quality_acceptable: false
      }
    end
  end

  defp calculate_fallback_cost_impact(primary_provider, execution_result, cost_constraints) do
    if execution_result.success do
      # Calculate cost difference between primary and fallback provider
      primary_cost = estimate_provider_cost(primary_provider, execution_result.request_params)

      fallback_cost =
        estimate_provider_cost(
          execution_result.successful_provider,
          execution_result.request_params
        )

      cost_increase = fallback_cost - primary_cost
      cost_increase_ratio = if primary_cost > 0, do: cost_increase / primary_cost, else: 0.0

      max_allowed_increase = Map.get(cost_constraints, :max_cost_increase, 2.0)
      cost_acceptable = cost_increase_ratio <= max_allowed_increase

      %{
        primary_provider_cost: primary_cost,
        fallback_provider_cost: fallback_cost,
        cost_increase: cost_increase,
        cost_increase_ratio: Float.round(cost_increase_ratio, 3),
        cost_acceptable: cost_acceptable,
        max_allowed_increase: max_allowed_increase,
        cost_efficiency:
          calculate_cost_efficiency(cost_increase_ratio, execution_result.quality_analysis)
      }
    else
      %{
        cost_impact: :na_due_to_failure,
        cost_acceptable: false
      }
    end
  end

  # Analysis and calculation helper functions

  defp analyze_response_quality(response, original_params, provider) do
    # Analyze quality of fallback response compared to expected quality
    base_quality = get_provider_base_quality(provider)

    # Simple quality indicators (placeholder for more sophisticated analysis)
    response_completeness = calculate_response_completeness(response)
    response_relevance = calculate_response_relevance(response, original_params)

    composite_quality =
      base_quality * 0.4 + response_completeness * 0.3 + response_relevance * 0.3

    %{
      quality_score: Float.round(composite_quality, 3),
      base_provider_quality: base_quality,
      response_completeness: response_completeness,
      response_relevance: response_relevance,
      quality_factors: identify_quality_factors(response, provider)
    }
  end

  defp get_provider_base_quality(provider) do
    case provider do
      :openai -> 0.88
      :anthropic -> 0.92
      :local -> 0.75
      _ -> 0.7
    end
  end

  defp calculate_response_completeness(response) do
    # Simple completeness check
    case response do
      %{choices: [%{finish_reason: "stop"} | _]} -> 1.0
      %{choices: [%{finish_reason: "length"} | _]} -> 0.8
      %{content: content} when is_binary(content) and byte_size(content) > 50 -> 0.9
      _ -> 0.5
    end
  end

  defp calculate_response_relevance(response, original_params) do
    # Placeholder relevance calculation
    # In production, this would use semantic similarity or other techniques
    # Assume good relevance for placeholder
    0.85
  end

  defp identify_quality_factors(response, provider) do
    factors = []

    # Provider-specific quality factors
    factors =
      case provider do
        :openai -> ["Reliable completion", "Good reasoning" | factors]
        :anthropic -> ["Large context handling", "Constitutional AI" | factors]
        :local -> ["Fast processing", "Privacy preserved" | factors]
        _ -> factors
      end

    # Response-specific factors
    factors =
      case response do
        %{usage: %{completion_tokens: tokens}} when tokens > 100 ->
          ["Substantial response" | factors]

        _ ->
          factors
      end

    Enum.reverse(factors)
  end

  defp estimate_provider_cost(provider, request_params) do
    estimated_tokens = Map.get(request_params, :estimated_tokens, 2000)

    case provider do
      :openai -> estimated_tokens * 0.00002
      :anthropic -> estimated_tokens * 0.000024
      :local -> 0.0
      _ -> estimated_tokens * 0.00003
    end
  end

  defp calculate_cost_efficiency(cost_increase_ratio, quality_analysis) do
    # Calculate cost efficiency of fallback (quality gained per cost increase)
    if cost_increase_ratio > 0 do
      quality_score = quality_analysis.quality_score
      efficiency = quality_score / (1.0 + cost_increase_ratio)
      Float.round(efficiency, 3)
    else
      # No cost increase, efficiency = quality
      quality_analysis.quality_score
    end
  end

  defp explain_strategy_selection(strategy, failure_reason, quality_threshold, cost_budget) do
    case strategy do
      :quality_preservation ->
        "High quality threshold (#{quality_threshold}) requires quality preservation"

      :cost_optimization ->
        "Tight cost budget (#{cost_budget}x) requires cost optimization"

      :latency_minimization ->
        "Latency sensitive request requires fast failover"

      :capability_matching ->
        "Failure type (#{failure_reason}) requires capability matching"
    end
  end

  defp extract_success_lessons(execution_result, primary_provider, strategy) do
    [
      "#{execution_result.successful_provider} successful fallback from #{primary_provider}",
      "Strategy #{strategy.strategy} effective with #{execution_result.attempts_made} attempts",
      "Quality preserved at #{execution_result.quality_analysis.quality_score} level"
    ]
  end

  defp extract_failure_lessons(execution_result, primary_provider, strategy) do
    failed_providers =
      execution_result.attempt_history
      |> Enum.map(&Map.get(&1, :provider))

    [
      "All fallback providers failed: #{inspect(failed_providers)}",
      "Strategy #{strategy.strategy} ineffective for this failure scenario",
      "Primary failure from #{primary_provider} cascaded through entire chain"
    ]
  end

  defp extract_response_metadata(response) do
    %{
      response_type: determine_response_type(response),
      token_usage: extract_token_usage(response),
      completion_reason: extract_completion_reason(response)
    }
  end

  defp determine_response_type(response) do
    cond do
      Map.has_key?(response, :choices) -> :completion
      Map.has_key?(response, :data) -> :embedding
      true -> :unknown
    end
  end

  defp extract_token_usage(response) do
    case response do
      %{usage: usage} -> usage
      _ -> %{total_tokens: 0}
    end
  end

  defp extract_completion_reason(response) do
    case response do
      %{choices: [%{finish_reason: reason} | _]} -> reason
      _ -> :unknown
    end
  end

  defp track_fallback_outcome(primary_provider, execution_result, outcome_analysis, context) do
    Logger.debug("ExecuteFallbackAction: Tracking fallback outcome",
      primary_provider: primary_provider,
      successful_provider: execution_result.successful_provider,
      outcome: outcome_analysis.outcome,
      attempts: execution_result.attempts_made
    )

    # TODO: Integrate with learning system for fallback optimization
    :ok
  end

  # Provider-specific parameter adaptation functions

  defp maybe_enable_openai_caching(params) do
    # Optimize for OpenAI's automatic caching
    params
  end

  defp optimize_for_openai_models(params) do
    # Optimize parameters for OpenAI model characteristics
    params
  end

  defp optimize_for_large_context(params) do
    # Optimize for Anthropic's large context handling
    params
  end

  defp adjust_anthropic_conversation_structure(params) do
    # Adjust conversation structure for Anthropic
    params
  end

  defp optimize_for_local_efficiency(params) do
    # Optimize for local model efficiency
    params
  end

  defp reduce_token_usage_for_local(params) do
    # Reduce token usage for local model efficiency
    current_max = Map.get(params, :max_tokens, 4000)
    # Cap for local efficiency
    optimized_max = min(current_max, 2000)
    Map.put(params, :max_tokens, optimized_max)
  end

  defp reduce_max_tokens_for_cost(params) do
    current_max = Map.get(params, :max_tokens, 4000)
    # 20% reduction
    cost_optimized_max = round(current_max * 0.8)
    Map.put(params, :max_tokens, max(cost_optimized_max, 100))
  end

  defp optimize_for_quality(params, provider) do
    # Optimize parameters for maximum quality from provider
    case provider do
      :anthropic ->
        # Lower temperature for more precise responses
        Map.put(params, :temperature, 0.3)

      :openai ->
        # Enable JSON mode if structured output expected
        if Map.has_key?(params, :response_format) do
          params
        else
          params
        end

      _ ->
        params
    end
  end

  defp optimize_for_speed(params) do
    # Optimize for faster response times
    current_max = Map.get(params, :max_tokens, 4000)
    # Shorter responses are faster
    speed_optimized_max = min(current_max, 1500)
    Map.put(params, :max_tokens, speed_optimized_max)
  end
end
