defmodule RubberDuck.LlmProviders.Adapters.EvaluationAdapter do
  @moduledoc """
  Domain adapter for code evaluation using universal providers.
  
  This adapter preserves all Verdict system features while enabling universal
  provider access including:
  - Constitutional AI integration for safety-critical evaluation
  - Progressive evaluation strategies (screening vs detailed analysis)
  - Evaluation-specific prompt optimization and response parsing
  - Quality thresholds and confidence scoring
  - Integration with existing three-tier configuration system
  """
  
  require Logger
  
  alias RubberDuck.LlmProviders.{UniversalProviderService, ProviderRouter}
  alias RubberDuck.LlmProviders.UniversalProviderInterface
  
  @evaluation_types [:quality, :security, :performance, :maintainability, :style]
  @constitutional_ai_types [:security, :safety_critical, :ethical_review]
  
  @doc """
  Evaluate code using universal provider system with Verdict features preserved.
  """
  def evaluate_code(code, evaluation_type, user_id, project_id \\ nil, options \\ %{}) when evaluation_type in @evaluation_types do
    Logger.debug("Evaluating code using universal provider adapter for type: #{evaluation_type}")
    
    # Build evaluation context with Constitutional AI considerations
    evaluation_context = build_evaluation_context(code, evaluation_type, user_id, project_id, options)
    
    # Determine if Constitutional AI is required
    constitutional_ai_required = evaluation_type in @constitutional_ai_types or 
                                Map.get(options, :constitutional_ai_required, false)
    
    # Select provider with Constitutional AI preference if needed
    provider_options = build_provider_selection_options(evaluation_type, constitutional_ai_required, options)
    
    case UniversalProviderService.complete(code, :evaluation, provider_options) do
      {:ok, universal_response} ->
        # Adapt universal response to Verdict evaluation format
        evaluation_response = adapt_universal_response_to_evaluation(universal_response, evaluation_context)
        
        Logger.debug("Code evaluation completed via universal provider")
        {:ok, evaluation_response}
      
      error ->
        Logger.error("Universal provider evaluation failed: #{inspect(error)}")
        error
    end
  end
  
  @doc """
  Stream code evaluation with real-time feedback using universal providers.
  """
  def evaluate_code_streaming(code, evaluation_type, callback, user_id, project_id \\ nil, options \\ %{}) 
      when evaluation_type in @evaluation_types and is_function(callback) do
    
    Logger.debug("Streaming code evaluation using universal provider adapter")
    
    evaluation_context = build_evaluation_context(code, evaluation_type, user_id, project_id, options)
    constitutional_ai_required = evaluation_type in @constitutional_ai_types
    
    # Create evaluation-aware streaming callback
    evaluation_callback = create_evaluation_streaming_callback(callback, evaluation_context)
    
    provider_options = build_provider_selection_options(evaluation_type, constitutional_ai_required, 
                                                       Map.put(options, :streaming, true))
    
    case UniversalProviderService.stream(code, :evaluation, evaluation_callback, provider_options) do
      {:ok, universal_response} ->
        evaluation_response = adapt_universal_response_to_evaluation(universal_response, evaluation_context)
        {:ok, Map.put(evaluation_response, :streaming, true)}
      
      error -> error
    end
  end
  
  @doc """
  Estimate evaluation cost using universal provider system.
  """
  def estimate_evaluation_cost(code, evaluation_type, user_id, project_id \\ nil, options \\ %{}) do
    evaluation_context = build_evaluation_context(code, evaluation_type, user_id, project_id, options)
    constitutional_ai_required = evaluation_type in @constitutional_ai_types
    
    provider_options = build_provider_selection_options(evaluation_type, constitutional_ai_required, options)
    
    UniversalProviderService.estimate_cost(code, :evaluation, provider_options)
  end
  
  @doc """
  Check if evaluation is enabled for user/project via universal provider configuration.
  """
  def evaluation_enabled?(user_id, project_id \\ nil) do
    case UniversalProviderService.resolve_provider_config(:evaluation, user_id, project_id) do
      {:ok, config} -> Map.get(config, :enabled, true)
      _ -> false
    end
  end
  
  @doc """
  Get available evaluation providers via universal system.
  """
  def get_available_evaluation_providers do
    case UniversalProviderService.get_available_providers(:evaluation) do
      {:ok, providers} -> 
        evaluation_providers = providers
        |> Enum.map(fn {type, provider_config} ->
          {type, %{
            supports_constitutional_ai: :constitutional_ai in Map.get(provider_config, :specializations, []),
            supports_streaming: true,  # Assume universal providers support streaming
            optimal_for: get_provider_evaluation_strengths(type)
          }}
        end)
        |> Enum.into(%{})
        
        {:ok, evaluation_providers}
      
      error -> error
    end
  end
  
  # Private implementation
  
  defp build_evaluation_context(code, evaluation_type, user_id, project_id, options) do
    %{
      code: code,
      evaluation_type: evaluation_type,
      user_id: user_id,
      project_id: project_id,
      quality_threshold: Map.get(options, :quality_threshold, 0.8),
      max_tokens: Map.get(options, :max_tokens, 1500),
      streaming_required: Map.get(options, :streaming, false),
      criteria: Map.get(options, :criteria, get_default_evaluation_criteria(evaluation_type)),
      specialized_features: determine_evaluation_features(evaluation_type, options)
    }
  end
  
  defp get_default_evaluation_criteria(evaluation_type) do
    case evaluation_type do
      :security -> %{
        "security" => 0.6,
        "correctness" => 0.3,
        "maintainability" => 0.1
      }
      
      :performance -> %{
        "performance" => 0.5,
        "correctness" => 0.3,
        "maintainability" => 0.2
      }
      
      :quality -> %{
        "correctness" => 0.4,
        "maintainability" => 0.3,
        "security" => 0.2,
        "style" => 0.1
      }
      
      :maintainability -> %{
        "maintainability" => 0.5,
        "correctness" => 0.3,
        "style" => 0.2
      }
      
      :style -> %{
        "style" => 0.6,
        "maintainability" => 0.4
      }
      
      _ -> %{
        "correctness" => 0.4,
        "maintainability" => 0.3,
        "security" => 0.2,
        "style" => 0.1
      }
    end
  end
  
  defp determine_evaluation_features(evaluation_type, options) do
    base_features = [:evaluation_prompts, :quality_assessment, :streaming]
    
    # Add Constitutional AI for safety-critical evaluations
    constitutional_features = if evaluation_type in @constitutional_ai_types do
      [:constitutional_ai, :safety_checks, :bias_mitigation]
    else
      []
    end
    
    # Add user-specified features
    user_features = Map.get(options, :specialized_features, [])
    
    (base_features ++ constitutional_features ++ user_features) |> Enum.uniq()
  end
  
  defp build_provider_selection_options(evaluation_type, constitutional_ai_required, options) do
    base_options = %{
      use_case: evaluation_type,
      user_id: Map.get(options, :user_id),
      project_id: Map.get(options, :project_id),
      streaming: Map.get(options, :streaming, false),
      max_tokens: Map.get(options, :max_tokens, 1500),
      temperature: 0.1,  # Low temperature for consistent evaluation
      specialized_features: determine_evaluation_features(evaluation_type, options)
    }
    
    # Add Constitutional AI routing preference
    routing_options = if constitutional_ai_required do
      Map.put(base_options, :routing_strategy, :constitutional_ai_first)
    else
      Map.put(base_options, :routing_strategy, :quality_first)
    end
    
    Map.merge(routing_options, options)
  end
  
  defp adapt_universal_response_to_evaluation(universal_response, evaluation_context) do
    # Convert universal response to Verdict evaluation format
    domain_data = universal_response.domain_specific_data
    
    %{
      # Core Verdict response fields
      success: universal_response.success,
      score: Map.get(domain_data, :score, 0.8),
      confidence: Map.get(domain_data, :confidence, 0.9),
      issues: Map.get(domain_data, :issues, []),
      recommendations: Map.get(domain_data, :recommendations, []),
      reasoning: Map.get(domain_data, :reasoning, universal_response.content),
      
      # Provider and cost information
      cost_usd: universal_response.cost_usd,
      tokens_used: universal_response.usage.total_tokens,
      response_time_ms: universal_response.response_time_ms,
      provider: universal_response.provider,
      model: universal_response.model,
      
      # Enhanced with universal provider features
      evaluation_type: evaluation_context.evaluation_type,
      quality_threshold: evaluation_context.quality_threshold,
      constitutional_ai_enhanced: Map.has_key?(domain_data, :constitutional_ai_data),
      universal_provider_used: true,
      
      # Preserve metadata
      metadata: Map.merge(universal_response.metadata, %{
        evaluation_context: evaluation_context,
        adapted_from_universal: true
      })
    }
  end
  
  defp create_evaluation_streaming_callback(original_callback, evaluation_context) do
    fn stream_event ->
      # Adapt streaming events for evaluation consumption
      evaluation_event = case Map.get(stream_event, :type) do
        :chunk ->
          %{
            type: :evaluation_progress,
            content: Map.get(stream_event, :content, ""),
            evaluation_type: evaluation_context.evaluation_type,
            timestamp: DateTime.utc_now()
          }
        
        :complete ->
          %{
            type: :evaluation_complete,
            evaluation_type: evaluation_context.evaluation_type,
            result: Map.get(stream_event, :result, %{}),
            timestamp: DateTime.utc_now()
          }
        
        _ ->
          Map.put(stream_event, :evaluation_context, evaluation_context.evaluation_type)
      end
      
      original_callback.(evaluation_event)
    end
  end
  
  defp get_provider_evaluation_strengths(provider_type) do
    case provider_type do
      :anthropic -> [:constitutional_ai, :safety_analysis, :thoughtful_evaluation, :bias_mitigation]
      :openai -> [:general_evaluation, :performance_analysis, :versatile_assessment]
      :ollama -> [:privacy_focused, :local_evaluation, :cost_free]
      _ -> [:basic_evaluation]
    end
  end
  
  # Integration with existing Verdict system
  
  @doc """
  Migrate existing Verdict evaluation to universal provider system.
  """
  def migrate_from_verdict_engine(code, evaluation_type, options) do
    Logger.info("Migrating Verdict evaluation to universal provider system")
    
    # Extract user context from options (would get from existing Verdict engine)
    user_id = Map.get(options, :user_id, "system")
    project_id = Map.get(options, :project_id)
    
    # Migrate options to universal format
    migrated_options = %{
      quality_threshold: Map.get(options, :quality_threshold, 0.8),
      max_tokens: Map.get(options, :max_tokens_per_evaluation, 1500),
      streaming: Map.get(options, :progressive_evaluation, false),
      constitutional_ai_required: evaluation_type in @constitutional_ai_types,
      migration_source: :verdict_engine
    }
    
    evaluate_code(code, evaluation_type, user_id, project_id, migrated_options)
  end
  
  @doc """
  Check compatibility with existing Verdict configuration.
  """
  def check_verdict_compatibility(user_id, project_id \\ nil) do
    case UniversalProviderService.resolve_provider_config(:evaluation, user_id, project_id) do
      {:ok, config} ->
        {:ok, %{
          constitutional_ai_available: Map.get(config, :constitutional_ai_enabled, false),
          preferred_providers: Map.get(config, :preferred_providers, []),
          quality_threshold: Map.get(config, :quality_threshold, 0.8),
          universal_provider_compatible: true
        }}
      
      error -> error
    end
  end
  
  @doc """
  Get evaluation recommendations using universal provider system.
  """
  def get_evaluation_recommendations(evaluation_type, requirements \\ %{}) do
    enhanced_requirements = Map.merge(requirements, %{
      use_case: evaluation_type,
      specialized_features: determine_evaluation_features(evaluation_type, requirements)
    })
    
    ProviderRouter.get_provider_recommendations(:evaluation, enhanced_requirements)
  end
end