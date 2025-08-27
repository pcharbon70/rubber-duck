defmodule RubberDuck.LlmProviders.UniversalProviderRouter do
  @moduledoc """
  Universal provider routing system for intelligent AI provider selection across all domains.

  This module unifies routing logic from both the Verdict system and Preferences LLM system
  into a single, sophisticated router that supports:
  - Domain-aware provider selection (evaluation, orchestration, planning, etc.)
  - Multi-criteria optimization (cost, quality, speed, availability)
  - Constitutional AI routing for safety-critical evaluations
  - Cost optimization for agent orchestration and bulk operations
  - Cross-domain provider sharing and resource optimization
  - Integration with existing three-tier configuration system
  """

  require Logger

  alias RubberDuck.LlmProviders.{UniversalProviderRegistry, UniversalProviderInterface}
  alias RubberDuck.Verdict.Configuration.VerdictConfigurationResolver
  alias RubberDuck.Preferences.Llm.{CostOptimizer, RoutingIntegration}

  @routing_strategies [
    # Minimize cost (from both systems)
    :cost_optimized,
    # Maximize quality (from Verdict system)
    :quality_first,
    # Balance cost/quality/speed (from both systems)
    :balanced,
    # Minimize response time (from Verdict system)
    :fastest,
    # Maximize uptime/success rate (from Verdict system)  
    :most_reliable,
    # Prioritize Constitutional AI (from Verdict system)
    :constitutional_ai_first,
    # Optimize for agent communication (from Preferences system)
    :orchestration_optimized,
    # Optimize for cross-domain usage (new unified feature)
    :cross_domain_efficient
  ]

  @default_strategy :balanced
  @fallback_order [:openai, :anthropic, :ollama]

  @doc """
  Select optimal provider for universal request across any domain.

  Returns provider selection with comprehensive routing metadata.
  """
  def select_universal_provider(universal_request, options \\ []) do
    Logger.debug("Selecting universal provider for domain: #{universal_request.context.domain}")

    with {:ok, routing_config} <- get_universal_routing_configuration(universal_request.context),
         {:ok, available_providers} <- get_domain_available_providers(universal_request),
         {:ok, routing_decision} <-
           apply_universal_routing_strategy(
             available_providers,
             universal_request,
             routing_config,
             options
           ) do
      Logger.debug(
        "Selected universal provider: #{routing_decision.provider} for #{universal_request.context.domain}"
      )

      {:ok, routing_decision}
    else
      error ->
        Logger.error("Universal provider selection failed: #{inspect(error)}")
        apply_universal_fallback_selection(universal_request, options)
    end
  end

  @doc """
  Get provider recommendations for universal request with detailed analysis.

  Returns ranked list of providers with domain-specific scoring.
  """
  def get_universal_provider_recommendations(universal_request) do
    Logger.debug(
      "Getting universal provider recommendations for #{universal_request.context.domain}"
    )

    with {:ok, routing_config} <- get_universal_routing_configuration(universal_request.context),
         {:ok, available_providers} <- get_domain_available_providers(universal_request) do
      recommendations =
        available_providers
        |> Enum.map(
          &build_universal_provider_recommendation(&1, universal_request, routing_config)
        )
        |> Enum.sort_by(& &1.overall_score, :desc)

      {:ok, recommendations}
    else
      error -> error
    end
  end

  @doc """
  Validate universal routing decision and check cross-domain compatibility.
  """
  def validate_universal_routing_decision(routing_decision, universal_request) do
    provider_type = routing_decision.provider
    domain = universal_request.context.domain

    with {:ok, provider_info} <- UniversalProviderRegistry.get_provider(provider_type),
         :ok <- validate_domain_support(provider_info, domain, universal_request),
         :ok <- validate_provider_health(provider_info, domain),
         :ok <- validate_specialized_feature_support(provider_info, universal_request) do
      {:ok, routing_decision}
    else
      error -> error
    end
  end

  @doc """
  Route request considering cross-domain provider efficiency.
  """
  def route_with_cross_domain_optimization(universal_request, recent_provider_usage \\ %{}) do
    # Consider which providers user/system has been using recently for efficiency
    cross_domain_context = build_cross_domain_context(universal_request, recent_provider_usage)

    # Apply cross-domain optimized routing
    options = [
      strategy: :cross_domain_efficient,
      cross_domain_context: cross_domain_context
    ]

    select_universal_provider(universal_request, options)
  end

  # Private implementation

  defp get_universal_routing_configuration(context) do
    # Integrate with both existing configuration systems
    case context do
      %{domain: :evaluation, user_id: user_id, project_id: project_id} when not is_nil(user_id) ->
        # Use Verdict configuration resolution for evaluation
        case VerdictConfigurationResolver.resolve_configuration(user_id, project_id) do
          {:ok, verdict_config} ->
            {:ok, adapt_verdict_config_for_universal_routing(verdict_config)}

          error ->
            error
        end

      %{domain: :orchestration, user_id: user_id, project_id: project_id}
      when not is_nil(user_id) ->
        # Use Preferences system for orchestration
        case RoutingIntegration.select_provider_with_preferences(user_id, [], project_id) do
          {:ok, routing_result} ->
            {:ok, adapt_preferences_config_for_universal_routing(routing_result)}

          error ->
            error
        end

      _ ->
        # Use default universal configuration
        {:ok, get_default_universal_routing_config()}
    end
  end

  defp adapt_verdict_config_for_universal_routing(verdict_config) do
    %{
      strategy: Map.get(verdict_config, :routing_strategy, :balanced),
      preferred_providers: Map.get(verdict_config, :preferred_providers, ["openai", "anthropic"]),
      # Verdict focuses more on quality
      cost_weight: 0.3,
      quality_weight: 0.5,
      speed_weight: 0.2,
      specialized_features: [:constitutional_ai, :safety_checks, :streaming],
      max_cost_per_request: Map.get(verdict_config, :max_cost_per_evaluation, 1.0),
      quality_threshold: Map.get(verdict_config, :default_quality_threshold, 0.8),
      domain_priority: :evaluation
    }
  end

  defp adapt_preferences_config_for_universal_routing(preferences_result) do
    %{
      # Preferences system focuses on cost optimization
      strategy: :cost_optimized,
      preferred_providers: [to_string(preferences_result.provider)],
      # Higher cost focus for orchestration
      cost_weight: 0.6,
      quality_weight: 0.3,
      speed_weight: 0.1,
      specialized_features: [:cost_optimization, :agent_communication],
      # Lower cost tolerance for orchestration
      max_cost_per_request: 0.5,
      domain_priority: :orchestration
    }
  end

  defp get_default_universal_routing_config do
    %{
      strategy: @default_strategy,
      preferred_providers: ["openai", "anthropic"],
      cost_weight: 0.4,
      quality_weight: 0.4,
      speed_weight: 0.2,
      specialized_features: [],
      max_cost_per_request: 1.0,
      quality_threshold: 0.8,
      domain_priority: :general
    }
  end

  defp get_domain_available_providers(universal_request) do
    domain = universal_request.context.domain
    requirements = UniversalProviderInterface.extract_domain_requirements(universal_request)

    UniversalProviderRegistry.get_available_providers_for_domain(domain, requirements)
  end

  defp apply_universal_routing_strategy(
         available_providers,
         universal_request,
         routing_config,
         options
       ) do
    strategy = Keyword.get(options, :strategy, routing_config.strategy)

    case strategy do
      :cost_optimized ->
        select_cost_optimized_universal_provider(
          available_providers,
          universal_request,
          routing_config
        )

      :quality_first ->
        select_quality_first_universal_provider(
          available_providers,
          universal_request,
          routing_config
        )

      :balanced ->
        select_balanced_universal_provider(available_providers, universal_request, routing_config)

      :fastest ->
        select_fastest_universal_provider(available_providers, universal_request, routing_config)

      :most_reliable ->
        select_most_reliable_universal_provider(
          available_providers,
          universal_request,
          routing_config
        )

      :constitutional_ai_first ->
        select_constitutional_ai_universal_provider(
          available_providers,
          universal_request,
          routing_config
        )

      :orchestration_optimized ->
        select_orchestration_optimized_provider(
          available_providers,
          universal_request,
          routing_config
        )

      :cross_domain_efficient ->
        select_cross_domain_efficient_provider(
          available_providers,
          universal_request,
          routing_config,
          options
        )

      _ ->
        {:error, "Unknown universal routing strategy: #{strategy}"}
    end
  end

  # Routing strategy implementations

  defp select_cost_optimized_universal_provider(providers, request, config) do
    provider_scores =
      providers
      |> Enum.map(&score_provider_for_universal_cost(&1, request, config))
      |> Enum.filter(&(&1.cost_estimate <= config.max_cost_per_request))
      |> Enum.sort_by(& &1.cost_estimate)

    case provider_scores do
      [best_provider | _] ->
        {:ok,
         build_universal_routing_decision(
           best_provider,
           :cost_optimized,
           "Lowest cost universal provider"
         )}

      [] ->
        {:error, "No providers within cost budget for domain #{request.context.domain}"}
    end
  end

  defp select_quality_first_universal_provider(providers, request, config) do
    provider_scores =
      providers
      |> Enum.map(&score_provider_for_universal_quality(&1, request, config))
      |> Enum.filter(&(&1.quality_score >= config.quality_threshold))
      |> Enum.sort_by(& &1.quality_score, :desc)

    case provider_scores do
      [best_provider | _] ->
        {:ok,
         build_universal_routing_decision(
           best_provider,
           :quality_first,
           "Highest quality universal provider"
         )}

      [] ->
        {:error, "No providers meet quality threshold for domain #{request.context.domain}"}
    end
  end

  defp select_balanced_universal_provider(providers, request, config) do
    provider_scores =
      providers
      |> Enum.map(&score_provider_universal_balanced(&1, request, config))
      |> Enum.sort_by(& &1.overall_score, :desc)

    case provider_scores do
      [best_provider | _] ->
        {:ok,
         build_universal_routing_decision(
           best_provider,
           :balanced,
           "Best universal cost/quality/speed balance"
         )}

      [] ->
        {:error, "No providers available for balanced universal routing"}
    end
  end

  defp select_constitutional_ai_universal_provider(providers, request, config) do
    # Prioritize providers with Constitutional AI capabilities for safety-critical operations
    constitutional_providers =
      providers
      |> Enum.filter(fn {_type, provider_info} ->
        capabilities = provider_info.capabilities
        specialized_features = Map.get(capabilities, :specialized_features, [])
        :constitutional_ai in specialized_features
      end)

    case constitutional_providers do
      [] ->
        Logger.warning("No Constitutional AI providers available, falling back to quality-first")
        select_quality_first_universal_provider(providers, request, config)

      constitutional_providers ->
        provider_scores =
          constitutional_providers
          |> Enum.map(&score_provider_for_constitutional_ai(&1, request, config))
          |> Enum.sort_by(
            fn score ->
              # Prioritize Constitutional AI capability + quality
              score.constitutional_ai_score * 0.6 + score.quality_score * 0.4
            end,
            :desc
          )

        case provider_scores do
          [best_provider | _] ->
            {:ok,
             build_universal_routing_decision(
               best_provider,
               :constitutional_ai_first,
               "Constitutional AI optimized provider"
             )}

          [] ->
            {:error, "No Constitutional AI providers meet requirements"}
        end
    end
  end

  defp select_orchestration_optimized_provider(providers, request, config) do
    # Optimize for agent orchestration and communication use cases
    provider_scores =
      providers
      |> Enum.map(&score_provider_for_orchestration(&1, request, config))
      |> Enum.sort_by(
        fn score ->
          # Prioritize cost efficiency and communication optimization
          score.cost_efficiency * 0.5 + score.communication_score * 0.3 + score.speed_score * 0.2
        end,
        :desc
      )

    case provider_scores do
      [best_provider | _] ->
        {:ok,
         build_universal_routing_decision(
           best_provider,
           :orchestration_optimized,
           "Orchestration optimized provider"
         )}

      [] ->
        {:error, "No providers suitable for orchestration optimization"}
    end
  end

  defp select_cross_domain_efficient_provider(providers, request, config, options) do
    # Consider cross-domain usage patterns for efficiency
    cross_domain_context = Keyword.get(options, :cross_domain_context, %{})

    provider_scores =
      providers
      |> Enum.map(
        &score_provider_for_cross_domain_efficiency(&1, request, config, cross_domain_context)
      )
      |> Enum.sort_by(& &1.cross_domain_efficiency_score, :desc)

    case provider_scores do
      [best_provider | _] ->
        {:ok,
         build_universal_routing_decision(
           best_provider,
           :cross_domain_efficient,
           "Cross-domain efficient provider"
         )}

      [] ->
        {:error, "No providers available for cross-domain efficiency"}
    end
  end

  # Provider scoring algorithms

  defp score_provider_for_universal_cost({provider_type, provider_info}, request, _config) do
    cost_estimate = estimate_universal_provider_cost(provider_info, request)

    %{
      provider_type: provider_type,
      provider_info: provider_info,
      cost_estimate: cost_estimate,
      # Inverse for scoring
      cost_score: 1.0 / max(cost_estimate, 0.001),
      domain: request.context.domain
    }
  end

  defp score_provider_for_universal_quality({provider_type, provider_info}, request, _config) do
    quality_score = get_universal_provider_quality_score(provider_info, request.context)
    domain_specialization = get_domain_specialization_score(provider_type, request.context.domain)

    %{
      provider_type: provider_type,
      provider_info: provider_info,
      quality_score: quality_score,
      domain_specialization: domain_specialization,
      combined_quality_score: quality_score * 0.7 + domain_specialization * 0.3
    }
  end

  defp score_provider_universal_balanced({provider_type, provider_info}, request, config) do
    cost_estimate = estimate_universal_provider_cost(provider_info, request)
    quality_score = get_universal_provider_quality_score(provider_info, request.context)
    speed_score = get_universal_provider_speed_score(provider_info, request.context.domain)
    domain_specialization = get_domain_specialization_score(provider_type, request.context.domain)

    # Normalize cost score
    normalized_cost_score = 1.0 / max(cost_estimate, 0.001)
    max_reasonable_cost = 2.0
    cost_score = min(normalized_cost_score / max_reasonable_cost, 1.0)

    # Slight bonus for domain specialization
    overall_score =
      cost_score * config.cost_weight +
        quality_score * config.quality_weight +
        speed_score * config.speed_weight +
        domain_specialization * 0.1

    %{
      provider_type: provider_type,
      provider_info: provider_info,
      cost_estimate: cost_estimate,
      quality_score: quality_score,
      speed_score: speed_score,
      domain_specialization: domain_specialization,
      overall_score: overall_score
    }
  end

  defp score_provider_for_constitutional_ai({provider_type, provider_info}, request, config) do
    capabilities = provider_info.capabilities

    # Score Constitutional AI capabilities
    constitutional_ai_score =
      if :constitutional_ai in Map.get(capabilities, :specialized_features, []) do
        # Full Constitutional AI support
        1.0
      else
        # No Constitutional AI support
        0.0
      end

    # Consider safety-related capabilities
    safety_features = [:safety_checks, :bias_mitigation, :content_filtering]

    safety_score =
      safety_features
      |> Enum.count(&(&1 in Map.get(capabilities, :specialized_features, [])))
      |> then(&(&1 / length(safety_features)))

    quality_score = get_universal_provider_quality_score(provider_info, request.context)

    %{
      provider_type: provider_type,
      provider_info: provider_info,
      constitutional_ai_score: constitutional_ai_score,
      safety_score: safety_score,
      quality_score: quality_score,
      overall_constitutional_score:
        constitutional_ai_score * 0.5 + safety_score * 0.3 + quality_score * 0.2
    }
  end

  defp score_provider_for_orchestration({provider_type, provider_info}, request, _config) do
    capabilities = provider_info.capabilities

    # Score orchestration-specific features
    cost_efficiency = get_provider_cost_efficiency(provider_type, :orchestration)
    communication_score = get_communication_optimization_score(provider_info)
    speed_score = get_universal_provider_speed_score(provider_info, :orchestration)

    %{
      provider_type: provider_type,
      provider_info: provider_info,
      cost_efficiency: cost_efficiency,
      communication_score: communication_score,
      speed_score: speed_score,
      orchestration_optimization_score:
        cost_efficiency * 0.4 + communication_score * 0.4 + speed_score * 0.2
    }
  end

  defp score_provider_for_cross_domain_efficiency(
         {provider_type, provider_info},
         request,
         _config,
         cross_domain_context
       ) do
    # Score based on cross-domain usage efficiency
    recent_usage = Map.get(cross_domain_context, :recent_provider_usage, %{})
    provider_usage = Map.get(recent_usage, provider_type, %{})

    # Efficiency bonuses for providers already in use
    connection_reuse_bonus = if map_size(provider_usage) > 0, do: 0.2, else: 0.0

    # Efficiency bonus for providers supporting multiple domains user needs
    user_domains = Map.get(cross_domain_context, :user_domains, [])

    multi_domain_bonus =
      if length(Enum.filter(user_domains, &(&1 in provider_info.supported_domains))) > 1 do
        0.15
      else
        0.0
      end

    base_efficiency = get_provider_cross_domain_efficiency(provider_type, provider_info)

    cross_domain_efficiency_score = base_efficiency + connection_reuse_bonus + multi_domain_bonus

    %{
      provider_type: provider_type,
      provider_info: provider_info,
      connection_reuse_bonus: connection_reuse_bonus,
      multi_domain_bonus: multi_domain_bonus,
      base_efficiency: base_efficiency,
      cross_domain_efficiency_score: min(1.0, cross_domain_efficiency_score)
    }
  end

  # Helper functions for provider scoring

  defp estimate_universal_provider_cost(provider_info, request) do
    domain = request.context.domain
    estimated_tokens = estimate_universal_token_count(request, domain)

    # Get cost rate based on domain and use case
    cost_rate = get_domain_cost_rate(provider_info, domain, request.context.use_case)

    UniversalProviderInterface.calculate_universal_cost_estimate(
      estimated_tokens,
      cost_rate,
      request.context
    )
  end

  defp estimate_universal_token_count(request, domain) do
    content_length =
      case request.content do
        content when is_binary(content) ->
          String.length(content)

        content when is_list(content) ->
          Enum.reduce(content, 0, fn msg, acc ->
            acc + String.length(Map.get(msg, :content, ""))
          end)

        _ ->
          100
      end

    # Base tokens from content (~4 chars per token)
    base_tokens = div(content_length, 4)

    # Domain-specific token overhead
    domain_tokens =
      case domain do
        # Evaluation context and structured response
        :evaluation -> 800
        # Agent communication overhead
        :orchestration -> 400
        # Planning context and reasoning
        :planning -> 600
        # Simple communication overhead
        :communication -> 200
        _ -> 300
      end

    base_tokens + domain_tokens
  end

  defp get_domain_cost_rate(provider_info, domain, use_case) do
    provider_type = get_provider_type_from_info(provider_info)

    # Get base cost rate
    base_rate =
      case provider_type do
        # Average GPT cost
        :openai -> 0.02
        # Average Claude cost
        :anthropic -> 0.015
        # Local models
        :ollama -> 0.0
        _ -> 0.015
      end

    # Apply domain-specific adjustments
    domain_multiplier =
      case {domain, use_case} do
        # Security analysis needs detailed models
        {:evaluation, :security} -> 1.2
        # Standard evaluation
        {:evaluation, :quality} -> 1.0
        # Planning needs reasoning
        {:orchestration, :planning} -> 1.1
        # Communication is simpler
        {:orchestration, :communication} -> 0.8
        # Planning is complex
        {:planning, _} -> 1.3
        _ -> 1.0
      end

    base_rate * domain_multiplier
  end

  defp get_universal_provider_quality_score(provider_info, context) do
    provider_type = get_provider_type_from_info(provider_info)
    domain = context.domain
    use_case = context.use_case

    # Base quality scores by provider and domain
    base_quality =
      case {provider_type, domain} do
        # Claude excellent for evaluation
        {:anthropic, :evaluation} -> 0.95
        # Claude good for orchestration
        {:anthropic, :orchestration} -> 0.90
        # GPT good for evaluation
        {:openai, :evaluation} -> 0.90
        # GPT excellent for orchestration
        {:openai, :orchestration} -> 0.92
        # Local models decent
        {:ollama, :evaluation} -> 0.80
        # Local models good for simple communication
        {:ollama, :communication} -> 0.85
        _ -> 0.85
      end

    # Adjust for specialized use cases
    use_case_modifier =
      case {provider_type, use_case} do
        # Claude excels at security
        {:anthropic, :security} -> 0.05
        # GPT good at performance analysis
        {:openai, :performance} -> 0.03
        # Local models excellent for privacy
        {:ollama, :privacy} -> 0.10
        _ -> 0.0
      end

    min(1.0, base_quality + use_case_modifier)
  end

  defp get_universal_provider_speed_score(provider_info, domain) do
    provider_type = get_provider_type_from_info(provider_info)

    # Base speed scores adjusted for domain requirements
    base_speed =
      case provider_type do
        # Local models fastest
        :ollama -> 0.9
        # OpenAI generally fast
        :openai -> 0.8
        # Claude thoughtful but slower
        :anthropic -> 0.7
        _ -> 0.6
      end

    # Domain-specific speed requirements
    domain_speed_modifier =
      case domain do
        # Communication needs speed
        :communication -> 0.1
        # Orchestration values speed
        :orchestration -> 0.05
        # Evaluation can wait for quality
        :evaluation -> 0.0
        # Planning can be slower
        :planning -> -0.1
        _ -> 0.0
      end

    min(1.0, base_speed + domain_speed_modifier)
  end

  defp get_domain_specialization_score(provider_type, domain) do
    case {provider_type, domain} do
      # Claude specialized for thoughtful evaluation
      {:anthropic, :evaluation} -> 0.9
      # Claude good at reasoning/planning
      {:anthropic, :planning} -> 0.85
      # GPT excellent for orchestration
      {:openai, :orchestration} -> 0.9
      # GPT good for communication
      {:openai, :communication} -> 0.8
      # Local models decent for simple communication
      {:ollama, :communication} -> 0.7
      _ -> 0.6
    end
  end

  defp get_provider_cost_efficiency(provider_type, domain) do
    # Historical cost efficiency (would integrate with actual tracking)
    case {provider_type, domain} do
      # Local models most cost efficient
      {:ollama, _} -> 1.0
      # OpenAI decent efficiency for orchestration
      {:openai, :orchestration} -> 0.8
      # Claude expensive but valuable for evaluation
      {:anthropic, :evaluation} -> 0.7
      # OpenAI good balance for evaluation
      {:openai, :evaluation} -> 0.75
      _ -> 0.6
    end
  end

  defp get_communication_optimization_score(provider_info) do
    capabilities = provider_info.capabilities

    base_score = 0.7

    # Bonus for function calling (important for agent communication)
    function_calling_bonus =
      if Map.get(capabilities, :supports_function_calling, false), do: 0.15, else: 0.0

    # Bonus for streaming (important for real-time communication)
    streaming_bonus = if Map.get(capabilities, :supports_streaming, false), do: 0.10, else: 0.0

    min(1.0, base_score + function_calling_bonus + streaming_bonus)
  end

  defp get_provider_cross_domain_efficiency(provider_type, provider_info) do
    # Base efficiency for handling multiple domains
    supported_domains = length(provider_info.supported_domains)

    base_efficiency =
      case provider_type do
        # GPT handles multiple domains well
        :openai -> 0.85
        # Claude good across domains
        :anthropic -> 0.80
        # Local models more limited
        :ollama -> 0.70
        _ -> 0.65
      end

    # Bonus for supporting more domains
    multi_domain_bonus = min(0.15, (supported_domains - 1) * 0.05)

    min(1.0, base_efficiency + multi_domain_bonus)
  end

  defp build_universal_routing_decision(provider_score, strategy, reasoning) do
    %{
      provider: provider_score.provider_type,
      model:
        select_optimal_model_for_domain(provider_score.provider_info, provider_score[:domain]),
      strategy: strategy,
      reasoning: reasoning,
      confidence: calculate_universal_decision_confidence(provider_score),
      cost_estimate: Map.get(provider_score, :cost_estimate, 0.0),
      quality_prediction: Map.get(provider_score, :quality_score, 0.8),
      domain_specialization: Map.get(provider_score, :domain_specialization, 0.6),
      expected_response_time_ms:
        get_expected_response_time(provider_score.provider_type, provider_score[:domain]),
      specialized_features_available:
        get_available_specialized_features(provider_score.provider_info),
      metadata: %{
        routing_timestamp: DateTime.utc_now(),
        universal_routing: true,
        # Would include other viable options
        alternative_providers: []
      }
    }
  end

  defp select_optimal_model_for_domain(provider_info, domain) do
    models = Map.get(provider_info.config, :models, %{})

    # Select model based on domain requirements
    case domain do
      :evaluation ->
        Map.get(models, :evaluation_detailed, Map.get(models, :detailed, "default"))

      :orchestration ->
        Map.get(models, :orchestration_standard, Map.get(models, :screening, "default"))

      :planning ->
        Map.get(models, :orchestration_planning, Map.get(models, :detailed, "default"))

      _ ->
        Map.get(models, :screening, Map.values(models) |> List.first() || "default")
    end
  end

  defp calculate_universal_decision_confidence(provider_score) do
    base_confidence = 0.8

    # Boost confidence based on available scoring metrics
    confidence = base_confidence

    confidence =
      if Map.has_key?(provider_score, :cost_estimate) do
        confidence + 0.05
      else
        confidence
      end

    confidence =
      if Map.has_key?(provider_score, :quality_score) do
        confidence + 0.05
      else
        confidence
      end

    confidence =
      if Map.has_key?(provider_score, :domain_specialization) do
        confidence + 0.05
      else
        confidence
      end

    confidence =
      if Map.has_key?(provider_score, :constitutional_ai_score) do
        confidence + 0.05
      else
        confidence
      end

    min(1.0, confidence)
  end

  defp get_expected_response_time(provider_type, domain) do
    base_time =
      case provider_type do
        # Fast local inference
        :ollama -> 1200
        # Generally fast API
        :openai -> 2000
        # Thoughtful but slower
        :anthropic -> 3000
        _ -> 2500
      end

    # Adjust for domain complexity
    domain_modifier =
      case domain do
        # Evaluation can take longer
        :evaluation -> 1.5
        # Planning is complex
        :planning -> 2.0
        # Standard orchestration
        :orchestration -> 1.0
        # Communication should be fast
        :communication -> 0.7
        _ -> 1.0
      end

    trunc(base_time * domain_modifier)
  end

  defp get_available_specialized_features(provider_info) do
    Map.get(provider_info.capabilities, :specialized_features, [])
  end

  defp apply_universal_fallback_selection(universal_request, options) do
    Logger.warning("Applying universal fallback provider selection")

    fallback_order = Keyword.get(options, :fallback_order, @fallback_order)
    domain = universal_request.context.domain

    case UniversalProviderRegistry.get_available_providers_for_domain(domain) do
      {:ok, all_providers} ->
        available_fallback =
          fallback_order
          |> Enum.find(fn provider_type ->
            Map.has_key?(all_providers, provider_type) and
              provider_supports_domain(all_providers[provider_type], domain)
          end)

        case available_fallback do
          nil ->
            {:error, "No fallback providers available for domain #{domain}"}

          provider_type ->
            {:ok,
             %{
               provider: provider_type,
               model: "default",
               strategy: :universal_fallback,
               reasoning: "Universal fallback provider due to routing failure",
               confidence: 0.6,
               cost_estimate: 0.5,
               quality_prediction: 0.7,
               expected_response_time_ms: 5000,
               metadata: %{
                 universal_fallback: true,
                 selected_at: DateTime.utc_now(),
                 original_domain: domain
               }
             }}
        end

      {:error, reason} ->
        {:error, "Universal provider registry unavailable: #{inspect(reason)}"}
    end
  end

  defp provider_supports_domain(provider_info, domain) do
    domain in provider_info.supported_domains
  end

  defp get_provider_type_from_info(provider_info) do
    case to_string(provider_info.module) do
      "Elixir.RubberDuck.LlmProviders.OpenAI." <> _ -> :openai
      "Elixir.RubberDuck.LlmProviders.Anthropic." <> _ -> :anthropic
      "Elixir.RubberDuck.LlmProviders.Ollama." <> _ -> :ollama
      _ -> :unknown
    end
  end

  # Validation helpers

  defp validate_domain_support(provider_info, domain, universal_request) do
    if domain in provider_info.supported_domains do
      :ok
    else
      {:error, "Provider does not support domain: #{domain}"}
    end
  end

  defp validate_provider_health(provider_info, domain) do
    domain_health_status = Map.get(provider_info, :domain_health_status, %{})
    domain_health = Map.get(domain_health_status, domain, %{status: :unknown})

    case domain_health.status do
      :healthy -> :ok
      # Accept degraded for now
      :degraded -> :ok
      _ -> {:error, "Provider unhealthy for domain #{domain}"}
    end
  end

  defp validate_specialized_feature_support(provider_info, universal_request) do
    required_features = Map.get(universal_request.context, :specialized_features, [])
    available_features = Map.get(provider_info.capabilities, :specialized_features, [])

    missing_features = required_features -- available_features

    case missing_features do
      [] -> :ok
      missing -> {:error, "Provider missing required features: #{inspect(missing)}"}
    end
  end

  # Cross-domain context building

  defp build_cross_domain_context(universal_request, recent_provider_usage) do
    %{
      current_domain: universal_request.context.domain,
      user_domains: get_user_recent_domains(universal_request.context, recent_provider_usage),
      recent_provider_usage: recent_provider_usage,
      cross_domain_optimization_enabled: true
    }
  end

  defp get_user_recent_domains(context, recent_usage) do
    user_id = context.user_id

    if user_id do
      # Extract domains from recent usage for this user
      recent_usage
      |> Map.values()
      |> List.flatten()
      |> Enum.filter(&(Map.get(&1, :user_id) == user_id))
      |> Enum.map(&Map.get(&1, :domain))
      |> Enum.uniq()
    else
      [context.domain]
    end
  end

  # Recommendation building

  defp build_universal_provider_recommendation({provider_type, provider_info}, request, config) do
    cost_estimate = estimate_universal_provider_cost(provider_info, request)
    quality_score = get_universal_provider_quality_score(provider_info, request.context)
    speed_score = get_universal_provider_speed_score(provider_info, request.context.domain)
    domain_specialization = get_domain_specialization_score(provider_type, request.context.domain)

    # Universal scoring
    overall_score =
      (quality_score * config.quality_weight +
         1.0 / max(cost_estimate, 0.001) * 0.1 * config.cost_weight +
         speed_score * config.speed_weight +
         domain_specialization * 0.2) / 2.0

    %{
      provider: provider_type,
      overall_score: min(1.0, overall_score),
      cost_estimate: cost_estimate,
      quality_prediction: quality_score,
      speed_score: speed_score,
      domain_specialization: domain_specialization,
      specialized_features: get_available_specialized_features(provider_info),
      recommendation_reason:
        generate_universal_recommendation_reason(
          provider_type,
          request.context.domain,
          quality_score,
          cost_estimate,
          speed_score,
          domain_specialization
        )
    }
  end

  defp generate_universal_recommendation_reason(
         provider_type,
         domain,
         quality_score,
         cost_estimate,
         speed_score,
         domain_specialization
       ) do
    strengths = []

    strengths = if quality_score > 0.9, do: ["excellent quality"] ++ strengths, else: strengths
    strengths = if cost_estimate < 0.1, do: ["very cost effective"] ++ strengths, else: strengths
    strengths = if speed_score > 0.8, do: ["fast response"] ++ strengths, else: strengths

    strengths =
      if domain_specialization > 0.8, do: ["#{domain} specialized"] ++ strengths, else: strengths

    provider_description =
      case provider_type do
        :anthropic -> "Claude provider - Constitutional AI and safety focus"
        :openai -> "OpenAI provider - versatile and reliable"
        :ollama -> "Local model - privacy and cost benefits"
        type -> "#{type} provider"
      end

    case strengths do
      [] -> "#{provider_description} - standard capabilities for #{domain}"
      strengths -> "#{provider_description} - #{Enum.join(strengths, ", ")} for #{domain}"
    end
  end
end
