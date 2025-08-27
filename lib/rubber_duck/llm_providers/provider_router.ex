defmodule RubberDuck.LlmProviders.ProviderRouter do
  @moduledoc """
  Clean universal provider router for intelligent provider selection.
  
  Routes LLM requests to optimal providers based on domain requirements and preferences.
  """
  
  require Logger
  
  alias RubberDuck.LlmProviders.ProviderRegistry
  
  @routing_strategies [:cost_optimized, :quality_first, :balanced, :constitutional_ai_first]
  @default_strategy :balanced
  
  @doc """
  Select optimal provider for domain and requirements.
  """
  def select_provider(domain, requirements \\ %{}) do
    Logger.debug("Selecting provider for domain: #{domain}")
    
    with {:ok, available_providers} <- ProviderRegistry.get_providers_for_domain(domain),
         {:ok, routing_decision} <- apply_routing_strategy(available_providers, domain, requirements) do
      
      Logger.debug("Selected provider: #{routing_decision.provider}")
      {:ok, routing_decision}
    else
      error ->
        Logger.error("Provider selection failed: #{inspect(error)}")
        apply_fallback_selection(domain, requirements)
    end
  end
  
  @doc """
  Get provider recommendations for domain.
  """
  def get_provider_recommendations(domain, requirements \\ %{}) do
    case ProviderRegistry.get_providers_for_domain(domain) do
      {:ok, available_providers} ->
        recommendations = available_providers
        |> Enum.map(&build_provider_recommendation(&1, domain, requirements))
        |> Enum.sort_by(& &1.overall_score, :desc)
        
        {:ok, recommendations}
      
      error -> error
    end
  end
  
  # Private implementation
  
  defp apply_routing_strategy(available_providers, domain, requirements) when map_size(available_providers) > 0 do
    strategy = Map.get(requirements, :routing_strategy, @default_strategy)
    
    case strategy do
      :constitutional_ai_first ->
        select_constitutional_ai_provider(available_providers, domain, requirements)
      
      :cost_optimized ->
        select_cost_optimized_provider(available_providers, domain, requirements)
      
      :quality_first ->
        select_quality_first_provider(available_providers, domain, requirements)
      
      _ ->
        select_balanced_provider(available_providers, domain, requirements)
    end
  end
  
  defp apply_routing_strategy(_empty_providers, domain, _requirements) do
    {:error, "No providers available for domain: #{domain}"}
  end
  
  defp select_constitutional_ai_provider(providers, domain, requirements) do
    # Prefer Anthropic for Constitutional AI
    case Map.get(providers, :anthropic) do
      nil -> 
        select_quality_first_provider(providers, domain, requirements)
      
      anthropic_provider ->
        {:ok, build_routing_decision(:anthropic, anthropic_provider, :constitutional_ai_first, "Constitutional AI provider selected")}
    end
  end
  
  defp select_cost_optimized_provider(providers, domain, requirements) do
    # Simple cost optimization: prefer OpenAI for general use
    case Map.get(providers, :openai) do
      nil ->
        # Fallback to first available provider
        {provider_type, provider_info} = Enum.at(providers, 0)
        {:ok, build_routing_decision(provider_type, provider_info, :cost_optimized, "Cost optimized fallback")}
      
      openai_provider ->
        {:ok, build_routing_decision(:openai, openai_provider, :cost_optimized, "Cost optimized provider")}
    end
  end
  
  defp select_quality_first_provider(providers, domain, requirements) do
    # Quality preference based on domain
    preferred_provider = case domain do
      :evaluation -> :anthropic  # Claude excels at evaluation
      :orchestration -> :openai  # GPT good at orchestration
      _ -> :openai
    end
    
    case Map.get(providers, preferred_provider) do
      nil ->
        # Fallback to first available
        {provider_type, provider_info} = Enum.at(providers, 0)
        {:ok, build_routing_decision(provider_type, provider_info, :quality_first, "Quality first fallback")}
      
      provider_info ->
        {:ok, build_routing_decision(preferred_provider, provider_info, :quality_first, "Quality first provider")}
    end
  end
  
  defp select_balanced_provider(providers, domain, requirements) do
    # Balanced selection considering multiple factors
    scored_providers = providers
    |> Enum.map(&score_provider_balanced(&1, domain, requirements))
    |> Enum.sort_by(& &1.score, :desc)
    
    case scored_providers do
      [best_provider | _] ->
        {:ok, build_routing_decision(best_provider.provider_type, best_provider.provider_info, :balanced, "Balanced selection")}
      
      [] ->
        {:error, "No providers available for balanced routing"}
    end
  end
  
  defp score_provider_balanced({provider_type, provider_info}, domain, requirements) do
    # Simple scoring algorithm
    domain_bonus = if domain in provider_info.supported_domains, do: 0.5, else: 0.0
    
    provider_bonus = case {provider_type, domain} do
      {:anthropic, :evaluation} -> 0.3  # Claude good for evaluation
      {:openai, :orchestration} -> 0.3  # GPT good for orchestration
      _ -> 0.0
    end
    
    total_score = domain_bonus + provider_bonus
    
    %{
      provider_type: provider_type,
      provider_info: provider_info,
      score: total_score
    }
  end
  
  defp build_routing_decision(provider_type, provider_info, strategy, reasoning) do
    %{
      provider: provider_type,
      module: provider_info.module,
      strategy: strategy,
      reasoning: reasoning,
      confidence: 0.8,
      selected_at: DateTime.utc_now(),
      supported_domains: provider_info.supported_domains
    }
  end
  
  defp build_provider_recommendation({provider_type, provider_info}, domain, requirements) do
    score = calculate_simple_score(provider_type, domain)
    
    %{
      provider: provider_type,
      overall_score: score,
      recommendation_reason: generate_recommendation_reason(provider_type, domain, score),
      supported_domains: provider_info.supported_domains
    }
  end
  
  defp calculate_simple_score(provider_type, domain) do
    case {provider_type, domain} do
      {:anthropic, :evaluation} -> 0.95   # Excellent for evaluation
      {:anthropic, :planning} -> 0.90     # Good for planning
      {:openai, :orchestration} -> 0.95   # Excellent for orchestration
      {:openai, :evaluation} -> 0.85      # Good for evaluation
      {:ollama, :communication} -> 0.80   # Good for simple communication
      _ -> 0.75
    end
  end
  
  defp generate_recommendation_reason(provider_type, domain, score) do
    quality_desc = case score do
      s when s >= 0.9 -> "excellent"
      s when s >= 0.8 -> "very good"
      s when s >= 0.7 -> "good"
      _ -> "adequate"
    end
    
    provider_desc = case provider_type do
      :anthropic -> "Claude - Constitutional AI and safety focus"
      :openai -> "OpenAI - versatile and reliable"
      :ollama -> "Local model - privacy and cost benefits"
    end
    
    "#{provider_desc} - #{quality_desc} for #{domain} domain"
  end
  
  defp apply_fallback_selection(domain, requirements) do
    Logger.warning("Applying fallback selection for domain: #{domain}")
    
    # Simple fallback: return OpenAI as default
    {:ok, %{
      provider: :openai,
      module: RubberDuck.Verdict.Providers.OpenAI.OpenAIProvider,
      strategy: :fallback,
      reasoning: "Fallback provider selection",
      confidence: 0.6,
      selected_at: DateTime.utc_now()
    }}
  end
end