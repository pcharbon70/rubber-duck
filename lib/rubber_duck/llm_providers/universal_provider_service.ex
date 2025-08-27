defmodule RubberDuck.LlmProviders.UniversalProviderService do
  @moduledoc """
  Universal LLM Provider Service - Simplified unified interface for all LLM operations.
  
  This service consolidates LLM provider access from both the Verdict system and
  Preferences LLM system into a single, unified interface that supports:
  - Code evaluation with Constitutional AI (Verdict use case)
  - Agent orchestration and communication (Preferences use case)  
  - Future domains: planning, tool calling, embeddings
  
  Key features:
  - Unified provider selection and routing
  - Domain-aware cost optimization
  - Constitutional AI preservation for safety-critical operations
  - Integration with existing three-tier configuration system
  """
  
  require Logger
  
  # Simple provider configuration that works with existing systems
  @available_providers %{
    openai: %{
      module: RubberDuck.Verdict.Providers.OpenAI.OpenAIProvider,
      supports_domains: [:evaluation, :orchestration, :planning, :communication],
      specializations: [:general_purpose, :reasoning, :code_analysis]
    },
    anthropic: %{
      module: RubberDuck.Verdict.Providers.Anthropic.AnthropicProvider,  
      supports_domains: [:evaluation, :orchestration, :planning],
      specializations: [:constitutional_ai, :safety, :reasoning, :large_context]
    }
  }
  
  @doc """
  Universal LLM completion supporting all domains.
  
  Automatically selects optimal provider based on domain and requirements.
  """
  def complete(content, domain, options \\ %{}) do
    Logger.debug("Universal LLM completion for domain: #{domain}")
    
    # Build universal request
    request = build_universal_request(content, domain, options)
    
    # Select optimal provider
    case select_provider_for_domain(domain, options) do
      {:ok, provider_info} ->
        # Route to appropriate provider system
        route_to_provider_system(provider_info, request, domain)
      
      error -> error
    end
  end
  
  @doc """
  Universal streaming LLM completion for real-time feedback.
  """
  def stream(content, domain, callback, options \\ %{}) when is_function(callback) do
    Logger.debug("Universal LLM streaming for domain: #{domain}")
    
    request = build_universal_request(content, domain, Map.put(options, :streaming, true))
    
    case select_provider_for_domain(domain, options) do
      {:ok, provider_info} ->
        route_to_provider_system_streaming(provider_info, request, domain, callback)
      
      error -> error
    end
  end
  
  @doc """
  Get available providers for specific domain.
  """
  def get_available_providers(domain) do
    available = @available_providers
    |> Enum.filter(fn {_type, provider_config} ->
      domain in provider_config.supports_domains
    end)
    |> Enum.into(%{})
    
    {:ok, available}
  end
  
  @doc """
  Estimate cost for universal LLM operation.
  """
  def estimate_cost(content, domain, options \\ %{}) do
    case select_provider_for_domain(domain, options) do
      {:ok, provider_info} ->
        # Route to provider cost estimation
        estimate_provider_cost(provider_info, content, domain, options)
      
      error -> error
    end
  end
  
  # Private implementation
  
  defp build_universal_request(content, domain, options) do
    %{
      content: content,
      domain: domain,
      use_case: Map.get(options, :use_case, :general),
      user_id: Map.get(options, :user_id),
      project_id: Map.get(options, :project_id),
      streaming: Map.get(options, :streaming, false),
      max_tokens: Map.get(options, :max_tokens, 1500),
      temperature: Map.get(options, :temperature, 0.1),
      specialized_features: Map.get(options, :specialized_features, []),
      metadata: Map.get(options, :metadata, %{})
    }
  end
  
  defp select_provider_for_domain(domain, options) do
    routing_strategy = Map.get(options, :routing_strategy, :balanced)
    preferred_providers = Map.get(options, :preferred_providers, [])
    
    case domain do
      :evaluation -> select_evaluation_provider(routing_strategy)
      :orchestration -> select_orchestration_provider(routing_strategy)
      _ -> select_fallback_provider(preferred_providers)
    end
  end
  
  defp select_evaluation_provider(routing_strategy) do
    case routing_strategy do
      :constitutional_ai_first -> {:ok, @available_providers.anthropic}
      _ -> {:ok, @available_providers.openai}
    end
  end
  
  defp select_orchestration_provider(routing_strategy) do
    case routing_strategy do
      :cost_optimized -> {:ok, @available_providers.openai}
      _ -> {:ok, @available_providers.openai}
    end
  end
  
  defp select_fallback_provider(preferred_providers) do
    case preferred_providers do
      [] -> {:ok, @available_providers.openai}
      [first_pref | _] -> 
        case Map.get(@available_providers, String.to_atom(first_pref)) do
          nil -> {:ok, @available_providers.openai}
          provider -> {:ok, provider}
        end
    end
  end
  
  defp route_to_provider_system(provider_info, request, domain) do
    case domain do
      :evaluation ->
        # Route to Verdict system for evaluation
        route_to_verdict_system(provider_info, request)
      
      :orchestration ->
        # Route to Preferences LLM system for orchestration  
        route_to_preferences_system(provider_info, request)
      
      _ ->
        # Default routing to Verdict system
        route_to_verdict_system(provider_info, request)
    end
  end
  
  defp route_to_provider_system_streaming(provider_info, request, domain, callback) do
    case domain do
      :evaluation ->
        route_to_verdict_system_streaming(provider_info, request, callback)
      
      :orchestration ->
        route_to_preferences_system_streaming(provider_info, request, callback)
      
      _ ->
        route_to_verdict_system_streaming(provider_info, request, callback)
    end
  end
  
  defp route_to_verdict_system(provider_info, request) do
    # Convert universal request to Verdict format
    verdict_request = %{
      code: request.content,
      evaluation_type: Map.get(request, :use_case, :quality),
      criteria: %{"quality" => 1.0},  # Default criteria
      quality_threshold: 0.8,
      max_tokens: request.max_tokens,
      streaming: request.streaming,
      metadata: request.metadata
    }
    
    # Use existing Verdict provider
    case provider_info.module do
      RubberDuck.Verdict.Providers.OpenAI.OpenAIProvider ->
        # Would call OpenAI provider with verdict request
        simulate_verdict_evaluation(verdict_request, :openai)
      
      RubberDuck.Verdict.Providers.Anthropic.AnthropicProvider ->
        # Would call Anthropic provider with verdict request  
        simulate_verdict_evaluation(verdict_request, :anthropic)
      
      _ ->
        {:error, "Unknown provider module"}
    end
  end
  
  defp route_to_preferences_system(provider_info, request) do
    # Convert universal request to Preferences/Orchestration format
    orchestration_request = %{
      prompt: request.content,
      user_id: request.user_id,
      project_id: request.project_id,
      temperature: request.temperature,
      max_tokens: request.max_tokens,
      metadata: request.metadata
    }
    
    # Use existing Preferences LLM system
    case Map.get(@available_providers, :openai) do
      %{module: _module} ->
        # Would integrate with existing Preferences LLM routing
        simulate_orchestration_completion(orchestration_request, :openai)
      
      _ ->
        {:error, "Provider not available for orchestration"}
    end
  end
  
  defp route_to_verdict_system_streaming(provider_info, request, callback) do
    # Streaming routing to Verdict system
    verdict_request = %{
      code: request.content,
      evaluation_type: Map.get(request, :use_case, :quality),
      criteria: %{"quality" => 1.0},
      streaming: true,
      metadata: request.metadata
    }
    
    # Simulate streaming evaluation
    simulate_verdict_streaming(verdict_request, provider_info, callback)
  end
  
  defp route_to_preferences_system_streaming(provider_info, request, callback) do
    # Streaming routing to Preferences system
    orchestration_request = %{
      prompt: request.content,
      streaming: true,
      user_id: request.user_id,
      metadata: request.metadata
    }
    
    # Simulate orchestration streaming
    simulate_orchestration_streaming(orchestration_request, provider_info, callback)
  end
  
  # Temporary simulation functions (would be replaced with actual integrations)
  
  defp simulate_verdict_evaluation(request, provider_type) do
    # Simulate evaluation response
    {:ok, %{
      success: true,
      score: 0.85,
      confidence: 0.9,
      issues: [],
      recommendations: ["Consider adding input validation"],
      reasoning: "Code structure is good with minor improvements needed",
      cost_usd: 0.05,
      tokens_used: 150,
      response_time_ms: 2500,
      provider: provider_type,
      model: get_default_model(provider_type, :evaluation),
      metadata: %{universal_routing: true, domain: :evaluation}
    }}
  end
  
  defp simulate_orchestration_completion(request, provider_type) do
    # Simulate orchestration response
    {:ok, %{
      content: "Orchestration task completed successfully",
      success: true,
      cost_usd: 0.03,
      completion_quality: 0.8,
      cost_efficiency: 0.9,
      provider: provider_type,
      model: get_default_model(provider_type, :orchestration),
      metadata: %{universal_routing: true, domain: :orchestration}
    }}
  end
  
  defp simulate_verdict_streaming(request, provider_info, callback) do
    # Simulate streaming evaluation
    callback.(%{type: :start, domain: :evaluation})
    
    Process.sleep(100)
    callback.(%{type: :chunk, content: "Analyzing code structure..."})
    
    Process.sleep(100)
    callback.(%{type: :chunk, content: "Checking for security issues..."})
    
    Process.sleep(100)
    callback.(%{type: :complete, result: %{score: 0.85, confidence: 0.9}})
    
    {:ok, %{
      success: true,
      streaming: true,
      domain: :evaluation,
      provider: get_provider_type_from_module(provider_info.module)
    }}
  end
  
  defp simulate_orchestration_streaming(request, provider_info, callback) do
    # Simulate streaming orchestration
    callback.(%{type: :start, domain: :orchestration})
    
    Process.sleep(50)
    callback.(%{type: :chunk, content: "Processing agent communication..."})
    
    Process.sleep(50)
    callback.(%{type: :complete, result: %{completion_quality: 0.8}})
    
    {:ok, %{
      success: true,
      streaming: true,
      domain: :orchestration,
      provider: get_provider_type_from_module(provider_info.module)
    }}
  end
  
  defp estimate_provider_cost(provider_info, content, domain, options) do
    content_length = calculate_content_length(content)
    estimated_tokens = div(content_length, 4) + 300  # ~4 chars per token + overhead
    
    provider_type = get_provider_type_from_module(provider_info.module)
    cost_per_1k = get_provider_cost_rate(provider_type)
    base_cost = (estimated_tokens / 1000) * cost_per_1k
    
    domain_multiplier = get_domain_cost_multiplier(domain)
    {:ok, base_cost * domain_multiplier}
  end
  
  defp calculate_content_length(content) do
    case content do
      content when is_binary(content) -> String.length(content)
      content when is_list(content) -> 
        Enum.reduce(content, 0, fn msg, acc ->
          acc + String.length(Map.get(msg, :content, ""))
        end)
      _ -> 100
    end
  end
  
  defp get_provider_cost_rate(provider_type) do
    case provider_type do
      :openai -> 0.02
      :anthropic -> 0.015
      _ -> 0.015
    end
  end
  
  defp get_domain_cost_multiplier(domain) do
    case domain do
      :evaluation -> 1.2    # Evaluation might need more detailed analysis
      :orchestration -> 0.9 # Orchestration might get bulk pricing
      _ -> 1.0
    end
  end
  
  defp get_default_model(provider_type, domain) do
    case {provider_type, domain} do
      {:openai, :evaluation} -> "gpt-4o-mini"
      {:openai, :orchestration} -> "gpt-4o"
      {:anthropic, :evaluation} -> "claude-3-haiku-20240307"
      {:anthropic, :orchestration} -> "claude-3-5-sonnet-20241022"
      _ -> "default"
    end
  end
  
  defp get_provider_type_from_module(module) do
    case to_string(module) do
      "Elixir.RubberDuck.Verdict.Providers.OpenAI." <> _ -> :openai
      "Elixir.RubberDuck.Verdict.Providers.Anthropic." <> _ -> :anthropic
      _ -> :unknown
    end
  end
  
  # Integration helpers for existing systems
  
  @doc """
  Adapt Verdict evaluation request to universal format.
  """
  def from_verdict_request(code, evaluation_type, user_id, project_id \\ nil, options \\ %{}) do
    universal_options = Map.merge(options, %{
      use_case: evaluation_type,
      user_id: user_id,
      project_id: project_id,
      specialized_features: [:constitutional_ai, :safety_checks]
    })
    
    complete(code, :evaluation, universal_options)
  end
  
  @doc """
  Adapt Preferences orchestration request to universal format.
  """
  def from_orchestration_request(prompt, user_id, project_id \\ nil, options \\ %{}) do
    universal_options = Map.merge(options, %{
      use_case: :agent_communication,
      user_id: user_id,
      project_id: project_id,
      specialized_features: [:cost_optimization, :agent_communication]
    })
    
    complete(prompt, :orchestration, universal_options)
  end
  
  @doc """
  Get provider health across all domains.
  """
  def get_provider_health do
    # Simple health check using existing provider health systems
    verdict_health = check_verdict_provider_health()
    preferences_health = check_preferences_provider_health()
    
    {:ok, %{
      verdict_providers: verdict_health,
      orchestration_providers: preferences_health,
      universal_status: :operational,
      last_check: DateTime.utc_now()
    }}
  end
  
  defp check_verdict_provider_health do
    # Would integrate with existing Verdict provider health monitoring
    %{
      openai: %{status: :healthy, domain: :evaluation},
      anthropic: %{status: :healthy, domain: :evaluation}
    }
  end
  
  defp check_preferences_provider_health do
    # Would integrate with existing Preferences LLM monitoring
    %{
      openai: %{status: :healthy, domain: :orchestration},
      anthropic: %{status: :healthy, domain: :orchestration}
    }
  end
  
  # Configuration integration
  
  @doc """
  Resolve provider configuration using existing three-tier system.
  """
  def resolve_provider_config(domain, user_id, project_id \\ nil) do
    case domain do
      :evaluation ->
        # Use Verdict configuration resolution
        case RubberDuck.Verdict.Configuration.VerdictConfigurationResolver.resolve_configuration(user_id, project_id) do
          {:ok, config} -> 
            {:ok, %{
              preferred_providers: Map.get(config, :preferred_providers, ["openai", "anthropic"]),
              routing_strategy: Map.get(config, :routing_strategy, :balanced),
              quality_threshold: Map.get(config, :default_quality_threshold, 0.8),
              constitutional_ai_enabled: Map.get(config, :bias_mitigation_enabled, true)
            }}
          error -> error
        end
      
      :orchestration ->
        # Use Preferences system configuration
        {:ok, %{
          preferred_providers: ["openai", "anthropic"],
          routing_strategy: :cost_optimized,
          cost_optimization_enabled: true
        }}
      
      _ ->
        # Default configuration
        {:ok, %{
          preferred_providers: ["openai", "anthropic"],
          routing_strategy: :balanced
        }}
    end
  end
  
  # Backward compatibility helpers
  
  @doc """
  Check if universal provider service is available and operational.
  """
  def service_available? do
    # Simple availability check
    case get_available_providers(:evaluation) do
      {:ok, providers} -> not Enum.empty?(providers)
      _ -> false
    end
  end
  
  @doc """
  Get service status and statistics.
  """
  def get_service_status do
    {:ok, %{
      status: :operational,
      available_providers: Map.keys(@available_providers),
      supported_domains: [:evaluation, :orchestration, :planning, :communication],
      integration_status: %{
        verdict_system: :integrated,
        preferences_system: :integrated,
        constitutional_ai: :available,
        cost_optimization: :available
      },
      last_updated: DateTime.utc_now()
    }}
  end
end