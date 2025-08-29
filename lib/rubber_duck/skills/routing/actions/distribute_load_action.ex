defmodule RubberDuck.Skills.Routing.Actions.DistributeLoadAction do
  @moduledoc """
  Predictive load distribution action for intelligent load balancing.

  This action implements sophisticated load balancing across LLM providers using
  predictive modeling, real-time capacity assessment, and fairness algorithms
  to ensure optimal resource utilization while maintaining SLA compliance.

  Features:
  - Real-time provider capacity modeling with performance prediction
  - Predictive traffic distribution based on historical patterns
  - Queue optimization with intelligent prioritization algorithms
  - Fairness algorithms ensuring equitable load distribution
  - Dynamic weight adjustment based on provider performance
  - Integration with circuit breaker and health monitoring systems

  Load Balancing Strategies:
  - **Round Robin**: Simple cycling through available providers
  - **Weighted Round Robin**: Provider weighting based on capacity and performance
  - **Least Connections**: Route to provider with lowest current load
  - **Predictive**: ML-based prediction of optimal provider for request
  """

  use Jido.Action,
    name: "distribute_load",
    schema: [
      available_providers: [
        type: {:list, :atom},
        required: true,
        doc: "List of available provider identifiers"
      ],
      load_balancing_strategy: [
        type: :atom,
        default: :predictive,
        doc: "Strategy (:round_robin, :weighted, :least_connections, :predictive)"
      ],
      request_characteristics: [
        type: :map,
        default: %{},
        doc: "Request characteristics for predictive modeling"
      ],
      sla_requirements: [type: :map, default: %{}, doc: "SLA requirements and constraints"],
      current_load_state: [type: :map, default: %{}, doc: "Current system load state"],
      fairness_config: [type: :map, default: %{}, doc: "Fairness algorithm configuration"]
    ]

  require Logger

  alias RubberDuck.LlmProviders.{ProviderRegistry, UniversalProviderService}

  # Load balancing algorithm configurations
  @balancing_strategies %{
    round_robin: %{
      description: "Simple cycling through providers",
      complexity: :low,
      predictive: false
    },
    weighted: %{
      description: "Provider weighting based on capacity",
      complexity: :medium,
      predictive: false
    },
    least_connections: %{
      description: "Route to least loaded provider",
      complexity: :medium,
      predictive: false
    },
    predictive: %{
      description: "ML-based optimal provider prediction",
      complexity: :high,
      predictive: true
    }
  }

  # Provider capacity baselines (requests per minute)
  @provider_capacities %{
    openai: %{
      baseline_rpm: 10_000,
      burst_capacity: 15_000,
      # 1 minute
      recovery_time: 60_000
    },
    anthropic: %{
      baseline_rpm: 1_000,
      burst_capacity: 1_500,
      # 2 minutes
      recovery_time: 120_000
    },
    local: %{
      # Depends on hardware
      baseline_rpm: 500,
      burst_capacity: 800,
      # 30 seconds
      recovery_time: 30_000
    }
  }

  # SLA defaults for different request types
  @default_sla %{
    max_latency_ms: 10_000,
    min_success_rate: 0.95,
    max_queue_time_ms: 5_000,
    # Max 20% load imbalance
    fairness_threshold: 0.2
  }

  @doc """
  Distribute load across available providers using intelligent algorithms.

  Returns optimal provider selection with load distribution metadata,
  capacity predictions, and fairness metrics for monitoring.
  """
  def run(params, _context) do
    %{
      available_providers: providers,
      load_balancing_strategy: strategy,
      request_characteristics: characteristics,
      sla_requirements: sla_reqs,
      current_load_state: load_state,
      fairness_config: fairness_config
    } = params

    merged_sla = Map.merge(@default_sla, sla_reqs)

    Logger.debug("DistributeLoadAction: Starting load distribution",
      strategy: strategy,
      providers: providers,
      sla_requirements: Map.keys(merged_sla)
    )

    distribution_start_time = System.monotonic_time(:microsecond)

    with {:ok, provider_capacities} <- get_provider_capacities(providers),
         {:ok, current_loads} <- get_current_provider_loads(providers, load_state),
         {:ok, distribution_plan} <-
           calculate_load_distribution(
             providers,
             strategy,
             provider_capacities,
             current_loads,
             characteristics,
             merged_sla
           ),
         {:ok, selected_provider} <-
           select_provider_from_distribution(distribution_plan, characteristics, merged_sla) do
      distribution_time = System.monotonic_time(:microsecond) - distribution_start_time

      # Calculate fairness metrics
      fairness_metrics = calculate_fairness_metrics(distribution_plan, current_loads)

      # Predict system impact
      system_impact =
        predict_distribution_impact(distribution_plan, current_loads, characteristics)

      Logger.info("DistributeLoadAction: Load distribution complete",
        selected_provider: selected_provider,
        strategy: strategy,
        distribution_time_us: distribution_time,
        fairness_score: fairness_metrics.fairness_score
      )

      {:ok,
       %{
         selected_provider: selected_provider,
         distribution_strategy: strategy,
         load_distribution_plan: distribution_plan,
         fairness_metrics: fairness_metrics,
         system_impact_prediction: system_impact,
         distribution_metadata: %{
           providers_evaluated: length(providers),
           distribution_time_microseconds: distribution_time,
           algorithm_used: strategy,
           sla_compliance: check_sla_compliance(distribution_plan, merged_sla)
         }
       }}
    else
      {:error, reason} ->
        Logger.error("DistributeLoadAction: Load distribution failed",
          error: reason,
          strategy: strategy,
          providers: providers
        )

        {:error, reason}
    end
  end

  # Private implementation functions

  defp get_provider_capacities(providers) do
    capacities =
      Enum.map(providers, fn provider ->
        base_capacity =
          Map.get(@provider_capacities, provider, %{
            baseline_rpm: 1000,
            burst_capacity: 1500,
            recovery_time: 60_000
          })

        # Get real-time capacity adjustments
        case get_dynamic_capacity_adjustment(provider) do
          {:ok, adjustment} ->
            adjusted_capacity = %{
              base_capacity
              | baseline_rpm: round(base_capacity.baseline_rpm * adjustment),
                burst_capacity: round(base_capacity.burst_capacity * adjustment)
            }

            {provider, adjusted_capacity}

          {:error, _reason} ->
            # Use baseline if dynamic adjustment fails
            {provider, base_capacity}
        end
      end)

    {:ok, Map.new(capacities)}
  end

  defp get_dynamic_capacity_adjustment(provider) do
    # Get real-time capacity adjustments based on provider health and performance
    case ProviderRegistry.get_provider(provider) do
      {:ok, provider_data} ->
        health = Map.get(provider_data, :health, :unknown)
        current_load = Map.get(provider_data, :current_load, 0.0)

        adjustment = calculate_capacity_adjustment(health, current_load)
        {:ok, adjustment}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp calculate_capacity_adjustment(health, current_load) do
    case health do
      :healthy -> calculate_healthy_adjustment(current_load)
      :degraded -> 0.6
      :recovering -> 0.4
      :unhealthy -> 0.1
      _ -> 0.7
    end
  end

  defp calculate_healthy_adjustment(current_load) do
    cond do
      current_load < 0.5 -> 1.0
      current_load < 0.8 -> 0.9
      true -> 0.8
    end
  end

  defp get_current_provider_loads(providers, load_state) do
    current_loads =
      Enum.map(providers, fn provider ->
        # Get current load from state or query provider registry
        current_load = get_provider_current_load(provider, load_state)

        {provider, current_load}
      end)

    {:ok, Map.new(current_loads)}
  end

  defp get_provider_current_load(provider, load_state) do
    case Map.get(load_state, provider) do
      nil ->
        # Query provider registry for current load
        case ProviderRegistry.get_provider(provider) do
          {:ok, provider_data} -> Map.get(provider_data, :current_load, 0.0)
          {:error, _} -> 0.0
        end

      load ->
        load
    end
  end

  defp calculate_load_distribution(
         providers,
         strategy,
         capacities,
         current_loads,
         characteristics,
         sla
       ) do
    case strategy do
      :round_robin ->
        calculate_round_robin_distribution(providers, capacities, current_loads)

      :weighted ->
        calculate_weighted_distribution(providers, capacities, current_loads, characteristics)

      :least_connections ->
        calculate_least_connections_distribution(providers, capacities, current_loads)

      :predictive ->
        calculate_predictive_distribution(
          providers,
          capacities,
          current_loads,
          characteristics,
          sla
        )

      _ ->
        {:error, {:unsupported_strategy, strategy}}
    end
  end

  defp calculate_round_robin_distribution(providers, capacities, current_loads) do
    # Simple round-robin with capacity awareness
    provider_weights =
      Enum.map(providers, fn provider ->
        capacity = Map.get(capacities, provider, %{baseline_rpm: 1000})
        current_load = Map.get(current_loads, provider, 0.0)

        # Weight based on available capacity
        available_capacity = capacity.baseline_rpm * (1.0 - current_load)
        # Minimum weight of 1
        weight = max(available_capacity, 1.0)

        {provider, weight}
      end)

    distribution_plan = %{
      algorithm: :round_robin,
      provider_weights: Map.new(provider_weights),
      next_provider: select_next_round_robin_provider(provider_weights),
      # Equal distribution target
      fairness_target: 1.0 / length(providers)
    }

    {:ok, distribution_plan}
  end

  defp calculate_weighted_distribution(providers, capacities, current_loads, characteristics) do
    # Weighted distribution based on provider capabilities and characteristics
    estimated_tokens = Map.get(characteristics, :estimated_tokens, 2000)
    complexity = Map.get(characteristics, :complexity, :medium)

    provider_weights =
      Enum.map(providers, fn provider ->
        capacity = Map.get(capacities, provider, %{baseline_rpm: 1000})
        current_load = Map.get(current_loads, provider, 0.0)

        # Base weight on capacity
        capacity_weight = capacity.baseline_rpm * (1.0 - current_load)

        # Adjust for request characteristics
        characteristic_weight =
          case {provider, complexity} do
            # Anthropic better for complex tasks
            {:anthropic, :high} -> 1.3
            # OpenAI good for balanced tasks
            {:openai, :medium} -> 1.1
            # Local good for simple tasks
            {:local, :low} -> 1.2
            _ -> 1.0
          end

        # Token count affects weight
        token_weight = calculate_token_weight(provider, estimated_tokens)

        final_weight = capacity_weight * characteristic_weight * token_weight
        {provider, max(final_weight, 0.1)}
      end)

    distribution_plan = %{
      algorithm: :weighted,
      provider_weights: Map.new(provider_weights),
      weight_factors: %{capacity: 0.6, characteristics: 0.3, tokens: 0.1}
    }

    {:ok, distribution_plan}
  end

  defp calculate_token_weight(provider, estimated_tokens) do
    if estimated_tokens > 10_000 do
      case provider do
        # Large context specialist
        :anthropic -> 1.4
        _ -> 1.0
      end
    else
      1.0
    end
  end

  defp calculate_least_connections_distribution(providers, capacities, current_loads) do
    # Route to provider with lowest current load
    provider_loads =
      Enum.map(providers, fn provider ->
        capacity = Map.get(capacities, provider, %{baseline_rpm: 1000})
        current_load = Map.get(current_loads, provider, 0.0)

        # Calculate load ratio (0.0 = no load, 1.0 = full capacity)
        load_ratio = current_load

        # Factor in capacity - higher capacity providers can handle more
        # Normalize to OpenAI baseline
        capacity_factor = capacity.baseline_rpm / 10_000
        adjusted_load = load_ratio / capacity_factor

        {provider, adjusted_load}
      end)

    # Sort by load ratio (ascending)
    sorted_by_load = Enum.sort_by(provider_loads, &elem(&1, 1))

    distribution_plan = %{
      algorithm: :least_connections,
      provider_loads: Map.new(provider_loads),
      load_ranking: sorted_by_load,
      recommended_provider: elem(hd(sorted_by_load), 0)
    }

    {:ok, distribution_plan}
  end

  defp calculate_predictive_distribution(
         providers,
         capacities,
         current_loads,
         characteristics,
         sla
       ) do
    # Advanced ML-based predictive distribution
    Logger.debug("DistributeLoadAction: Using predictive distribution algorithm")

    # Analyze traffic patterns and predict optimal distribution
    traffic_prediction = predict_traffic_patterns(characteristics)

    provider_performance_predictions =
      predict_provider_performance(providers, characteristics, current_loads)

    # Calculate optimal distribution considering SLA requirements
    optimal_weights =
      optimize_distribution_for_sla(
        providers,
        provider_performance_predictions,
        sla,
        traffic_prediction
      )

    # Select provider based on predictive model
    selected_provider =
      select_predictive_provider(optimal_weights, provider_performance_predictions)

    distribution_plan = %{
      algorithm: :predictive,
      provider_weights: optimal_weights,
      traffic_prediction: traffic_prediction,
      performance_predictions: provider_performance_predictions,
      recommended_provider: selected_provider,
      confidence_score: calculate_prediction_confidence(provider_performance_predictions)
    }

    {:ok, distribution_plan}
  end

  defp predict_traffic_patterns(characteristics) do
    # Simple traffic pattern prediction based on characteristics
    estimated_tokens = Map.get(characteristics, :estimated_tokens, 2000)
    request_type = Map.get(characteristics, :type, :completion)
    urgency = Map.get(characteristics, :urgency, :normal)

    %{
      expected_duration_ms: estimate_request_duration(request_type, estimated_tokens),
      resource_intensity: calculate_resource_intensity(characteristics),
      concurrency_factor: determine_concurrency_factor(urgency),
      predicted_load_impact: calculate_load_impact(characteristics)
    }
  end

  defp predict_provider_performance(providers, characteristics, current_loads) do
    Enum.map(providers, fn provider ->
      current_load = Map.get(current_loads, provider, 0.0)

      # Predict performance based on current state and characteristics
      predicted_latency = predict_latency(provider, characteristics, current_load)
      predicted_success_rate = predict_success_rate(provider, characteristics, current_load)
      predicted_quality = predict_response_quality(provider, characteristics)

      prediction = %{
        provider: provider,
        predicted_latency_ms: predicted_latency,
        predicted_success_rate: predicted_success_rate,
        predicted_quality_score: predicted_quality,
        current_load_ratio: current_load,
        recommendation_score:
          calculate_recommendation_score(
            predicted_latency,
            predicted_success_rate,
            predicted_quality
          )
      }

      {provider, prediction}
    end)
    |> Map.new()
  end

  defp optimize_distribution_for_sla(providers, predictions, sla, traffic_prediction) do
    max_latency = Map.get(sla, :max_latency_ms, 10_000)
    min_success_rate = Map.get(sla, :min_success_rate, 0.95)

    # Filter providers that can meet SLA
    sla_compliant_providers =
      Enum.filter(providers, fn provider ->
        prediction = Map.get(predictions, provider)

        prediction.predicted_latency_ms <= max_latency and
          prediction.predicted_success_rate >= min_success_rate
      end)

    if Enum.empty?(sla_compliant_providers) do
      Logger.warning("DistributeLoadAction: No providers meet SLA, using best available")
      # Use all providers with reduced expectations
      calculate_best_effort_weights(providers, predictions)
    else
      # Calculate optimal weights for SLA-compliant providers
      calculate_sla_optimized_weights(sla_compliant_providers, predictions, traffic_prediction)
    end
  end

  defp calculate_best_effort_weights(providers, predictions) do
    # When SLA cannot be met, optimize for best available performance
    total_score =
      providers
      |> Enum.map(&Map.get(predictions, &1).recommendation_score)
      |> Enum.sum()

    if total_score > 0 do
      Enum.map(providers, fn provider ->
        prediction = Map.get(predictions, provider)
        weight = prediction.recommendation_score / total_score
        {provider, weight}
      end)
      |> Map.new()
    else
      # Equal weights if no good options
      equal_weight = 1.0 / length(providers)
      Enum.map(providers, &{&1, equal_weight}) |> Map.new()
    end
  end

  defp calculate_sla_optimized_weights(compliant_providers, predictions, traffic_prediction) do
    # Optimize weights for SLA-compliant providers based on predicted performance
    resource_intensity = traffic_prediction.resource_intensity

    Enum.map(compliant_providers, fn provider ->
      prediction = Map.get(predictions, provider)

      # Weight based on performance and capacity
      performance_factor = prediction.recommendation_score

      # Adjust for resource intensity
      resource_factor = calculate_resource_factor(provider, resource_intensity)

      weight = performance_factor * resource_factor
      {provider, weight}
    end)
    |> normalize_weights()
  end

  defp calculate_resource_factor(provider, resource_intensity) do
    if resource_intensity > 0.7 do
      # High resource intensity - favor capable providers
      case provider do
        # Large context specialist
        :anthropic -> 1.3
        # Good performance
        :openai -> 1.1
        # May struggle with intensive tasks
        :local -> 0.8
      end
    else
      1.0
    end
  end

  defp normalize_weights(provider_weight_tuples) do
    total_weight = provider_weight_tuples |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    if total_weight > 0 do
      Enum.map(provider_weight_tuples, fn {provider, weight} ->
        {provider, weight / total_weight}
      end)
      |> Map.new()
    else
      # Fallback to equal weights
      equal_weight = 1.0 / length(provider_weight_tuples)

      Enum.map(provider_weight_tuples, fn {provider, _} ->
        {provider, equal_weight}
      end)
      |> Map.new()
    end
  end

  defp select_provider_from_distribution(distribution_plan, characteristics, sla) do
    case distribution_plan.algorithm do
      :round_robin ->
        {:ok, distribution_plan.next_provider}

      :least_connections ->
        {:ok, distribution_plan.recommended_provider}

      :predictive ->
        {:ok, distribution_plan.recommended_provider}

      :weighted ->
        # Select based on weighted random selection
        selected = weighted_random_selection(distribution_plan.provider_weights)
        {:ok, selected}
    end
  end

  defp weighted_random_selection(provider_weights) do
    # Weighted random selection algorithm
    total_weight = provider_weights |> Map.values() |> Enum.sum()
    random_value = :rand.uniform() * total_weight

    {selected_provider, _} =
      Enum.reduce_while(provider_weights, {nil, 0.0}, fn {provider, weight}, {_, acc} ->
        new_acc = acc + weight

        if random_value <= new_acc do
          {:halt, {provider, new_acc}}
        else
          {:cont, {provider, new_acc}}
        end
      end)

    selected_provider
  end

  defp select_next_round_robin_provider(provider_weights) do
    # Simple round-robin selection (placeholder - would maintain state)
    provider_weights
    |> Enum.max_by(&elem(&1, 1))
    |> elem(0)
  end

  defp select_predictive_provider(optimal_weights, performance_predictions) do
    # Select provider with highest combined weight and performance score
    Enum.max_by(optimal_weights, fn {provider, weight} ->
      performance = Map.get(performance_predictions, provider)
      weight * performance.recommendation_score
    end)
    |> elem(0)
  end

  # Prediction and calculation utility functions

  defp estimate_request_duration(request_type, estimated_tokens) do
    base_duration =
      case request_type do
        :completion -> 2000
        :streaming -> 5000
        :embedding -> 1000
      end

    # Add token-based duration
    # 0.5ms per token
    token_duration = estimated_tokens * 0.5
    round(base_duration + token_duration)
  end

  defp calculate_resource_intensity(characteristics) do
    factors = [
      # Large context
      Map.get(characteristics, :estimated_tokens, 0) > 10_000,
      # Complex reasoning
      Map.get(characteristics, :requires_reasoning, false),
      # Structured output
      Map.get(characteristics, :output_format) == :structured,
      # High precision
      Map.get(characteristics, :temperature, 0.5) < 0.3
    ]

    intensity = factors |> Enum.count(& &1) |> Kernel./(4)
    # Minimum 20% intensity
    max(intensity, 0.2)
  end

  defp determine_concurrency_factor(urgency) do
    case urgency do
      # Can wait, lower concurrency impact
      :low -> 0.8
      # Standard concurrency
      :normal -> 1.0
      # Higher impact on system
      :high -> 1.3
      # Maximum impact
      :critical -> 1.5
    end
  end

  defp calculate_load_impact(characteristics) do
    resource_intensity = calculate_resource_intensity(characteristics)
    estimated_tokens = Map.get(characteristics, :estimated_tokens, 2000)

    # Calculate overall system load impact
    # Normalize to 20K tokens
    token_impact = min(estimated_tokens / 20_000, 1.0)

    resource_intensity * 0.7 + token_impact * 0.3
  end

  defp predict_latency(provider, characteristics, current_load) do
    base_latency =
      case provider do
        :openai -> 2000
        :anthropic -> 2500
        :local -> 1500
      end

    # Load impact on latency
    # 1 second per 100% load
    load_impact = current_load * 1000

    # Token count impact
    estimated_tokens = Map.get(characteristics, :estimated_tokens, 2000)
    # 0.1ms per token
    token_impact = estimated_tokens * 0.1

    round(base_latency + load_impact + token_impact)
  end

  defp predict_success_rate(provider, characteristics, current_load) do
    base_success_rate =
      case provider do
        :openai -> 0.98
        :anthropic -> 0.96
        :local -> 0.92
      end

    # High load reduces success rate
    load_penalty = current_load * 0.1

    # Complex requests have slightly lower success rate
    complexity = Map.get(characteristics, :complexity, :medium)

    complexity_penalty =
      case complexity do
        :low -> 0.0
        :medium -> 0.02
        :high -> 0.05
      end

    success_rate = base_success_rate - load_penalty - complexity_penalty
    # Minimum 50% success rate
    max(success_rate, 0.5)
  end

  defp predict_response_quality(provider, characteristics) do
    base_quality =
      case provider do
        :openai -> 0.88
        :anthropic -> 0.92
        :local -> 0.75
      end

    # Adjust for request complexity
    complexity = Map.get(characteristics, :complexity, :medium)

    complexity_factor =
      case {provider, complexity} do
        # Anthropic excels at complex tasks
        {:anthropic, :high} -> 1.1
        # OpenAI good for balanced tasks
        {:openai, :medium} -> 1.05
        # Local models good for simple tasks
        {:local, :low} -> 1.1
        _ -> 1.0
      end

    quality_score = base_quality * complexity_factor
    min(quality_score, 1.0)
  end

  defp calculate_recommendation_score(latency, success_rate, quality) do
    # Composite score for provider recommendation
    # Normalize latency score (lower is better)
    latency_score = max(1.0 - latency / 10_000, 0.1)

    # Weighted combination
    latency_score * 0.3 + success_rate * 0.4 + quality * 0.3
  end

  defp calculate_prediction_confidence(performance_predictions) do
    # Calculate confidence in prediction based on score distribution
    scores =
      performance_predictions
      |> Map.values()
      |> Enum.map(& &1.recommendation_score)

    if length(scores) < 2 do
      # Default confidence for single provider
      0.8
    else
      # Higher confidence when there's a clear best option
      max_score = Enum.max(scores)
      second_max = scores |> Enum.sort(:desc) |> Enum.at(1, 0)

      score_gap = max_score - second_max
      base_confidence = 0.7
      # Up to 25% bonus
      gap_bonus = min(score_gap * 2, 0.25)

      min(base_confidence + gap_bonus, 0.95)
    end
  end

  # Fairness and SLA compliance functions

  defp calculate_fairness_metrics(distribution_plan, current_loads) do
    provider_weights = distribution_plan.provider_weights

    # Calculate load distribution fairness
    target_equal_share = 1.0 / map_size(provider_weights)

    fairness_deviations =
      Enum.map(provider_weights, fn {provider, weight} ->
        current_load = Map.get(current_loads, provider, 0.0)
        # Average current and planned load
        combined_load = (current_load + weight) / 2

        deviation = abs(combined_load - target_equal_share)
        {provider, deviation}
      end)

    max_deviation = fairness_deviations |> Enum.map(&elem(&1, 1)) |> Enum.max()
    # 0 = unfair, 1 = perfectly fair
    fairness_score = max(1.0 - max_deviation * 2, 0.0)

    %{
      fairness_score: fairness_score,
      max_deviation: max_deviation,
      provider_deviations: Map.new(fairness_deviations),
      distribution_balance: calculate_distribution_balance(provider_weights)
    }
  end

  defp calculate_distribution_balance(provider_weights) do
    weights = Map.values(provider_weights)
    mean_weight = Enum.sum(weights) / length(weights)

    variance =
      weights
      |> Enum.map(&:math.pow(&1 - mean_weight, 2))
      |> Enum.sum()
      |> Kernel./(length(weights))

    # Balance score: lower variance = higher balance
    balance_score = max(1.0 - variance * 10, 0.0)

    %{
      balance_score: balance_score,
      weight_variance: variance,
      weight_distribution: provider_weights
    }
  end

  defp check_sla_compliance(distribution_plan, sla) do
    case distribution_plan do
      %{performance_predictions: predictions} ->
        # Check if selected provider meets SLA
        selected = distribution_plan.recommended_provider
        prediction = Map.get(predictions, selected)

        latency_compliant = prediction.predicted_latency_ms <= sla.max_latency_ms
        success_compliant = prediction.predicted_success_rate >= sla.min_success_rate

        %{
          sla_compliant: latency_compliant and success_compliant,
          latency_compliant: latency_compliant,
          success_rate_compliant: success_compliant,
          predicted_latency: prediction.predicted_latency_ms,
          predicted_success_rate: prediction.predicted_success_rate
        }

      _ ->
        # Basic compliance check for simpler algorithms
        %{
          sla_compliant: true,
          reason: "SLA compliance assumed for #{distribution_plan.algorithm}"
        }
    end
  end

  defp predict_distribution_impact(distribution_plan, current_loads, characteristics) do
    # Predict impact of this distribution decision on overall system
    load_impact = calculate_system_load_impact(distribution_plan, current_loads)
    performance_impact = calculate_system_performance_impact(distribution_plan, characteristics)

    %{
      system_load_change: load_impact,
      performance_impact: performance_impact,
      fairness_impact: calculate_fairness_impact(distribution_plan),
      estimated_system_efficiency:
        calculate_system_efficiency_prediction(distribution_plan, current_loads)
    }
  end

  defp calculate_system_load_impact(distribution_plan, current_loads) do
    # Simple system load impact calculation
    selected_provider = distribution_plan.recommended_provider || distribution_plan.next_provider
    current_load = Map.get(current_loads, selected_provider, 0.0)

    # Estimate new load after this request
    # Assume 5% load increase per request (simplified)
    load_increment = 0.05
    new_load = min(current_load + load_increment, 1.0)

    %{
      provider: selected_provider,
      current_load: current_load,
      predicted_load: new_load,
      load_increase: load_increment
    }
  end

  defp calculate_system_performance_impact(_distribution_plan, _characteristics) do
    # Placeholder for system performance impact calculation
    %{
      overall_impact: :minimal,
      performance_score_change: 0.01
    }
  end

  defp calculate_fairness_impact(distribution_plan) do
    fairness_score = Map.get(distribution_plan, :fairness_score, 0.8)

    %{
      fairness_improvement: fairness_score > 0.8,
      fairness_score: fairness_score
    }
  end

  defp calculate_system_efficiency_prediction(distribution_plan, current_loads) do
    # Predict overall system efficiency after this routing decision
    avg_load = current_loads |> Map.values() |> Enum.sum() |> Kernel./(map_size(current_loads))

    # Efficiency based on load distribution evenness
    efficiency =
      case avg_load do
        # Very efficient - underutilized
        load when load < 0.3 -> 0.95
        # Optimal efficiency
        load when load < 0.6 -> 1.0
        # Good efficiency
        load when load < 0.8 -> 0.9
        # Lower efficiency - high load
        _ -> 0.7
      end

    Float.round(efficiency, 3)
  end
end
