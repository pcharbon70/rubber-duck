defmodule RubberDuck.Verdict.Providers.ProviderRouter do
  @moduledoc """
  Intelligent provider selection and routing for the Verdict framework.

  This module implements sophisticated routing algorithms to select the optimal
  AI provider for each evaluation based on:
  - Cost optimization and budget constraints
  - Quality requirements and provider performance history
  - Provider health and availability status
  - User preferences and project settings from three-tier configuration
  """

  require Logger

  alias RubberDuck.Verdict.Configuration.VerdictConfigurationResolver
  alias RubberDuck.Verdict.Providers.ProviderRegistry

  @routing_strategies [:cost_optimized, :quality_first, :balanced, :fastest, :most_reliable]
  @default_strategy :balanced

  @doc """
  Select the optimal provider for an evaluation request.

  Returns provider type and routing metadata including decision reasoning.
  """
  def select_provider(evaluation_request, user_id, project_id \\ nil, options \\ []) do
    Logger.debug("Selecting provider for evaluation type: #{evaluation_request.evaluation_type}")

    with {:ok, config} <- get_routing_configuration(user_id, project_id),
         {:ok, available_providers} <- get_available_providers(evaluation_request),
         {:ok, routing_decision} <-
           apply_routing_strategy(available_providers, evaluation_request, config, options) do
      Logger.debug("Selected provider: #{routing_decision.provider}")
      {:ok, routing_decision}
    else
      error ->
        Logger.error("Provider selection failed: #{inspect(error)}")
        apply_fallback_provider_selection(evaluation_request, options)
    end
  end

  @doc """
  Get routing recommendations for multiple providers.

  Returns ranked list of providers with cost and quality predictions.
  """
  def get_provider_recommendations(evaluation_request, user_id, project_id \\ nil) do
    Logger.debug("Getting provider recommendations for evaluation")

    with {:ok, config} <- get_routing_configuration(user_id, project_id),
         {:ok, available_providers} <- get_available_providers(evaluation_request) do
      recommendations =
        available_providers
        |> Enum.map(&build_provider_recommendation(&1, evaluation_request, config))
        |> Enum.sort_by(& &1.overall_score, :desc)

      {:ok, recommendations}
    else
      error -> error
    end
  end

  @doc """
  Validate routing decision and check provider health before use.
  """
  def validate_routing_decision(routing_decision) do
    provider_type = routing_decision.provider

    case ProviderRegistry.get_provider(provider_type) do
      {:ok, provider_info} ->
        if provider_info.health_status == :healthy do
          {:ok, routing_decision}
        else
          {:error, "Selected provider #{provider_type} is not healthy"}
        end

      {:error, :not_found} ->
        {:error, "Selected provider #{provider_type} not registered"}

      error ->
        error
    end
  end

  # Private implementation

  defp get_routing_configuration(user_id, project_id) do
    case VerdictConfigurationResolver.resolve_configuration(user_id, project_id) do
      {:ok, config} ->
        routing_config = extract_routing_configuration(config)
        {:ok, routing_config}

      error ->
        error
    end
  end

  defp extract_routing_configuration(config) do
    %{
      strategy: Map.get(config, :routing_strategy, @default_strategy),
      preferred_providers: Map.get(config, :preferred_providers, ["openai", "anthropic"]),
      cost_weight: Map.get(config, :cost_weight, 0.4),
      quality_weight: Map.get(config, :quality_weight, 0.4),
      speed_weight: Map.get(config, :speed_weight, 0.2),
      max_cost_per_evaluation: Map.get(config, :max_cost_per_evaluation, 1.0),
      quality_threshold: Map.get(config, :default_quality_threshold, 0.8),
      budget_remaining: Map.get(config, :daily_budget_remaining, 50.0)
    }
  end

  defp get_available_providers(evaluation_request) do
    requirements = build_provider_requirements(evaluation_request)
    ProviderRegistry.get_available_providers(requirements)
  end

  defp build_provider_requirements(evaluation_request) do
    %{
      evaluation_type: evaluation_request.evaluation_type,
      max_tokens: Map.get(evaluation_request, :max_tokens, 1500),
      streaming: Map.get(evaluation_request, :streaming, false)
    }
  end

  defp apply_routing_strategy(available_providers, evaluation_request, config, options) do
    strategy = Keyword.get(options, :strategy, config.strategy)

    case strategy do
      :cost_optimized ->
        select_cost_optimized_provider(available_providers, evaluation_request, config)

      :quality_first ->
        select_quality_first_provider(available_providers, evaluation_request, config)

      :balanced ->
        select_balanced_provider(available_providers, evaluation_request, config)

      :fastest ->
        select_fastest_provider(available_providers, evaluation_request, config)

      :most_reliable ->
        select_most_reliable_provider(available_providers, evaluation_request, config)

      _ ->
        {:error, "Unknown routing strategy: #{strategy}"}
    end
  end

  defp select_cost_optimized_provider(providers, request, config) do
    provider_scores =
      providers
      |> Enum.map(&score_provider_for_cost(&1, request, config))
      |> Enum.filter(&(&1.cost_estimate <= config.max_cost_per_evaluation))
      |> Enum.sort_by(& &1.cost_estimate)

    case provider_scores do
      [best_provider | _] ->
        {:ok, build_routing_decision(best_provider, :cost_optimized, "Lowest cost provider")}

      [] ->
        {:error, "No providers within cost budget"}
    end
  end

  defp select_quality_first_provider(providers, request, config) do
    provider_scores =
      providers
      |> Enum.map(&score_provider_for_quality(&1, request, config))
      |> Enum.filter(&(&1.quality_score >= config.quality_threshold))
      |> Enum.sort_by(& &1.quality_score, :desc)

    case provider_scores do
      [best_provider | _] ->
        {:ok, build_routing_decision(best_provider, :quality_first, "Highest quality provider")}

      [] ->
        {:error, "No providers meet quality threshold"}
    end
  end

  defp select_balanced_provider(providers, request, config) do
    provider_scores =
      providers
      |> Enum.map(&score_provider_balanced(&1, request, config))
      |> Enum.sort_by(& &1.overall_score, :desc)

    case provider_scores do
      [best_provider | _] ->
        {:ok, build_routing_decision(best_provider, :balanced, "Best cost/quality/speed balance")}

      [] ->
        {:error, "No providers available for balanced routing"}
    end
  end

  defp select_fastest_provider(providers, request, config) do
    provider_scores =
      providers
      |> Enum.map(&score_provider_for_speed(&1, request, config))
      |> Enum.sort_by(& &1.speed_score, :desc)

    case provider_scores do
      [best_provider | _] ->
        {:ok, build_routing_decision(best_provider, :fastest, "Fastest response time")}

      [] ->
        {:error, "No providers available for speed optimization"}
    end
  end

  defp select_most_reliable_provider(providers, request, config) do
    provider_scores =
      providers
      |> Enum.map(&score_provider_for_reliability(&1, request, config))
      |> Enum.sort_by(& &1.reliability_score, :desc)

    case provider_scores do
      [best_provider | _] ->
        {:ok, build_routing_decision(best_provider, :most_reliable, "Most reliable provider")}

      [] ->
        {:error, "No reliable providers available"}
    end
  end

  # Provider scoring algorithms

  defp score_provider_for_cost({provider_type, provider_info}, request, _config) do
    cost_estimate = estimate_provider_cost(provider_info, request)

    %{
      provider_type: provider_type,
      provider_info: provider_info,
      cost_estimate: cost_estimate,
      # Inverse of cost
      cost_score: 1.0 / max(cost_estimate, 0.001)
    }
  end

  defp score_provider_for_quality({provider_type, provider_info}, request, _config) do
    quality_score = get_provider_quality_score(provider_info, request.evaluation_type)

    %{
      provider_type: provider_type,
      provider_info: provider_info,
      quality_score: quality_score,
      historical_accuracy: get_historical_accuracy(provider_type, request.evaluation_type)
    }
  end

  defp score_provider_balanced({provider_type, provider_info}, request, config) do
    cost_estimate = estimate_provider_cost(provider_info, request)
    quality_score = get_provider_quality_score(provider_info, request.evaluation_type)
    speed_score = get_provider_speed_score(provider_info)

    # Normalize cost score (lower cost = higher score)
    normalized_cost_score = 1.0 / max(cost_estimate, 0.001)
    # Assume max reasonable cost
    max_cost = 2.0
    cost_score = min(normalized_cost_score / max_cost, 1.0)

    overall_score =
      cost_score * config.cost_weight +
        quality_score * config.quality_weight +
        speed_score * config.speed_weight

    %{
      provider_type: provider_type,
      provider_info: provider_info,
      cost_estimate: cost_estimate,
      quality_score: quality_score,
      speed_score: speed_score,
      overall_score: overall_score
    }
  end

  defp score_provider_for_speed({provider_type, provider_info}, _request, _config) do
    speed_score = get_provider_speed_score(provider_info)
    avg_response_time = get_average_response_time(provider_type)

    %{
      provider_type: provider_type,
      provider_info: provider_info,
      speed_score: speed_score,
      avg_response_time_ms: avg_response_time
    }
  end

  defp score_provider_for_reliability({provider_type, provider_info}, _request, _config) do
    reliability_score = get_provider_reliability_score(provider_info)
    uptime_percentage = get_provider_uptime(provider_type)

    %{
      provider_type: provider_type,
      provider_info: provider_info,
      reliability_score: reliability_score,
      uptime_percentage: uptime_percentage
    }
  end

  # Provider performance metrics (would integrate with actual tracking)

  defp estimate_provider_cost(provider_info, request) do
    model = get_model_for_evaluation(provider_info, request.evaluation_type)
    estimated_tokens = estimate_token_count(request.code, request.evaluation_type)

    cost_per_1k_tokens = get_model_cost_rate(provider_info, model)
    estimated_tokens / 1000 * cost_per_1k_tokens
  end

  defp get_provider_quality_score(provider_info, evaluation_type) do
    # Would integrate with historical performance data
    # For now, return provider-specific quality estimates
    capabilities = provider_info.capabilities
    base_quality = Map.get(capabilities, :base_quality_score, 0.8)

    # Adjust for evaluation type specialization
    type_modifier =
      case {get_provider_type(provider_info), evaluation_type} do
        # Claude excels at security analysis
        {:anthropic, :security} -> 0.1
        # GPT-4 good at performance analysis
        {:openai, :performance} -> 0.05
        # Local models less sophisticated for style
        {:ollama, :style} -> -0.1
        _ -> 0.0
      end

    min(1.0, base_quality + type_modifier)
  end

  defp get_provider_speed_score(provider_info) do
    # Would integrate with historical response time data
    provider_type = get_provider_type(provider_info)

    case provider_type do
      # Local models fastest
      :ollama -> 0.9
      # OpenAI generally fast
      :openai -> 0.8
      # Claude can be slower but thoughtful
      :anthropic -> 0.7
      _ -> 0.6
    end
  end

  defp get_provider_reliability_score(provider_info) do
    # Would integrate with historical uptime and error rate data
    provider_type = get_provider_type(provider_info)

    case provider_type do
      # OpenAI generally very reliable
      :openai -> 0.95
      # Anthropic very reliable
      :anthropic -> 0.92
      # Local models depend on hardware
      :ollama -> 0.85
      _ -> 0.8
    end
  end

  defp get_model_for_evaluation(provider_info, evaluation_type) do
    models = provider_info.config.models

    # Select model based on evaluation complexity
    case evaluation_type do
      :security -> Map.get(models, :detailed, Map.get(models, :screening))
      :performance -> Map.get(models, :detailed, Map.get(models, :screening))
      :quality -> Map.get(models, :detailed, Map.get(models, :screening))
      _ -> Map.get(models, :screening, Map.values(models) |> List.first())
    end
  end

  defp estimate_token_count(code, evaluation_type) do
    # Simple token estimation: ~4 characters per token for code
    base_tokens = div(String.length(code), 4)

    # Add tokens for evaluation context and response
    context_tokens =
      case evaluation_type do
        # Security evaluations need more context
        :security -> 800
        :performance -> 600
        :quality -> 500
        :maintainability -> 400
        :style -> 300
        _ -> 400
      end

    base_tokens + context_tokens
  end

  defp get_model_cost_rate(provider_info, model) do
    # Default cost rates per 1K tokens (would be configured per provider)
    provider_type = get_provider_type(provider_info)

    case {provider_type, model} do
      {:openai, "gpt-4o"} -> 0.03
      {:openai, "gpt-4o-mini"} -> 0.01
      {:anthropic, "claude-3-5-sonnet-" <> _} -> 0.02
      {:anthropic, "claude-3-haiku-" <> _} -> 0.01
      # Local models have no API cost
      {:ollama, _} -> 0.0
      # Default fallback rate
      _ -> 0.015
    end
  end

  defp get_provider_type(provider_info) do
    # Extract provider type from module name or config
    case to_string(provider_info.module) do
      "Elixir.RubberDuck.Verdict.Providers.OpenAI." <> _ -> :openai
      "Elixir.RubberDuck.Verdict.Providers.Anthropic." <> _ -> :anthropic
      "Elixir.RubberDuck.Verdict.Providers.Ollama." <> _ -> :ollama
      _ -> :unknown
    end
  end

  defp get_historical_accuracy(provider_type, evaluation_type) do
    # Would query historical evaluation data
    # For now, return estimated accuracy scores
    base_accuracy =
      case provider_type do
        :anthropic -> 0.92
        :openai -> 0.90
        :ollama -> 0.82
        _ -> 0.85
      end

    # Adjust for evaluation type
    type_modifier =
      case {provider_type, evaluation_type} do
        {:anthropic, :security} -> 0.05
        {:openai, :performance} -> 0.03
        {_, :style} -> -0.02
        _ -> 0.0
      end

    min(1.0, base_accuracy + type_modifier)
  end

  defp get_average_response_time(provider_type) do
    # Would query historical response time data
    case provider_type do
      # Fast local inference
      :ollama -> 1500
      # Generally fast API
      :openai -> 2500
      # More thoughtful, slower
      :anthropic -> 3500
      _ -> 3000
    end
  end

  defp get_provider_uptime(provider_type) do
    # Would query historical uptime data
    case provider_type do
      :openai -> 99.5
      :anthropic -> 99.2
      # Depends on local hardware
      :ollama -> 98.0
      _ -> 98.5
    end
  end

  defp build_routing_decision(provider_score, strategy, reasoning) do
    %{
      provider: provider_score.provider_type,
      model: get_model_for_evaluation(provider_score.provider_info, :quality),
      strategy: strategy,
      reasoning: reasoning,
      confidence: calculate_decision_confidence(provider_score),
      cost_estimate: Map.get(provider_score, :cost_estimate, 0.0),
      quality_prediction: Map.get(provider_score, :quality_score, 0.8),
      expected_response_time_ms: Map.get(provider_score, :avg_response_time_ms, 3000),
      metadata: %{
        scored_at: DateTime.utc_now(),
        # Would include other viable options
        alternative_providers: []
      }
    }
  end

  defp calculate_decision_confidence(provider_score) do
    # Calculate confidence based on score completeness and provider health
    base_confidence = 0.8

    # Boost confidence if we have cost estimate
    confidence =
      if Map.has_key?(provider_score, :cost_estimate) do
        base_confidence + 0.1
      else
        base_confidence
      end

    # Boost confidence if we have quality score
    confidence =
      if Map.has_key?(provider_score, :quality_score) do
        confidence + 0.1
      else
        confidence
      end

    min(1.0, confidence)
  end

  defp build_provider_recommendation({provider_type, provider_info}, request, config) do
    cost_estimate = estimate_provider_cost(provider_info, request)
    quality_score = get_provider_quality_score(provider_info, request.evaluation_type)
    speed_score = get_provider_speed_score(provider_info)
    reliability_score = get_provider_reliability_score(provider_info)

    # Normalize
    overall_score =
      (quality_score * config.quality_weight +
         1.0 / max(cost_estimate, 0.001) * 0.1 * config.cost_weight +
         speed_score * config.speed_weight +
         reliability_score * 0.3) / 2.0

    %{
      provider: provider_type,
      overall_score: min(1.0, overall_score),
      cost_estimate: cost_estimate,
      quality_prediction: quality_score,
      speed_score: speed_score,
      reliability_score: reliability_score,
      recommendation_reason:
        generate_recommendation_reason(provider_type, quality_score, cost_estimate, speed_score)
    }
  end

  defp generate_recommendation_reason(provider_type, quality_score, cost_estimate, speed_score) do
    strengths = []

    strengths = if quality_score > 0.9, do: ["high quality"] ++ strengths, else: strengths
    strengths = if cost_estimate < 0.1, do: ["low cost"] ++ strengths, else: strengths
    strengths = if speed_score > 0.8, do: ["fast response"] ++ strengths, else: strengths

    case {provider_type, strengths} do
      {:anthropic, strengths} ->
        "Claude provider - #{Enum.join(strengths, ", ")} with safety focus"

      {:openai, strengths} ->
        "OpenAI provider - #{Enum.join(strengths, ", ")} with broad capabilities"

      {:ollama, strengths} ->
        "Local model - #{Enum.join(strengths, ", ")} with privacy benefits"

      {type, []} ->
        "#{type} provider - standard capabilities"

      {type, strengths} ->
        "#{type} provider - #{Enum.join(strengths, ", ")}"
    end
  end

  defp apply_fallback_provider_selection(evaluation_request, options) do
    Logger.warning("Applying fallback provider selection")

    # Simple fallback: try providers in order of reliability
    fallback_order = Keyword.get(options, :fallback_order, [:openai, :anthropic, :ollama])

    case ProviderRegistry.get_providers() do
      {:ok, all_providers} ->
        available_fallback =
          fallback_order
          |> Enum.find(fn provider_type ->
            Map.has_key?(all_providers, provider_type) and
              all_providers[provider_type].health_status in [:healthy, :degraded]
          end)

        case available_fallback do
          nil ->
            {:error, "No fallback providers available"}

          provider_type ->
            {:ok,
             %{
               provider: provider_type,
               model: "default",
               strategy: :fallback,
               reasoning: "Fallback provider due to routing failure",
               confidence: 0.6,
               cost_estimate: 0.5,
               quality_prediction: 0.7,
               expected_response_time_ms: 5000,
               metadata: %{fallback: true, selected_at: DateTime.utc_now()}
             }}
        end

      {:error, reason} ->
        {:error, "Provider registry unavailable: #{inspect(reason)}"}
    end
  end
end
