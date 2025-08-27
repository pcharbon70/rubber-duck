defmodule RubberDuck.LlmProviders.Adapters.OrchestrationAdapter do
  @moduledoc """
  Domain adapter for agent orchestration using universal providers.
  
  This adapter preserves all Preferences LLM system features while enabling
  universal provider access including:
  - Cost optimization for agent communication and bulk operations
  - Multi-turn conversation support for agent coordination
  - Performance optimization for orchestration workloads
  - Integration with existing cost tracking and budget management
  - Agent communication patterns and coordination strategies
  """
  
  require Logger
  
  alias RubberDuck.LlmProviders.{UniversalProviderService, ProviderRouter}
  
  @orchestration_types [:agent_communication, :task_coordination, :planning_assistance, :cost_optimization]
  @cost_sensitive_types [:bulk_operations, :frequent_coordination, :background_processing]
  
  @doc """
  Perform agent orchestration using universal provider system with cost optimization.
  """
  def orchestrate(prompt, orchestration_type, user_id, project_id \\ nil, options \\ %{}) when orchestration_type in @orchestration_types do
    Logger.debug("Orchestrating agents using universal provider adapter for type: #{orchestration_type}")
    
    # Build orchestration context with cost optimization
    orchestration_context = build_orchestration_context(prompt, orchestration_type, user_id, project_id, options)
    
    # Determine cost optimization requirements
    cost_optimization_required = orchestration_type in @cost_sensitive_types or
                                Map.get(options, :cost_optimization_required, true)
    
    # Select provider with cost optimization preference
    provider_options = build_orchestration_provider_options(orchestration_type, cost_optimization_required, options)
    
    case UniversalProviderService.complete(prompt, :orchestration, provider_options) do
      {:ok, universal_response} ->
        # Adapt universal response to orchestration format
        orchestration_response = adapt_universal_response_to_orchestration(universal_response, orchestration_context)
        
        Logger.debug("Agent orchestration completed via universal provider")
        {:ok, orchestration_response}
      
      error ->
        Logger.error("Universal provider orchestration failed: #{inspect(error)}")
        error
    end
  end
  
  @doc """
  Multi-turn agent conversation using universal providers with cost optimization.
  """
  def agent_conversation(conversation_history, user_id, project_id \\ nil, options \\ %{}) do
    Logger.debug("Managing agent conversation using universal provider adapter")
    
    # Build multi-turn context
    conversation_context = build_conversation_context(conversation_history, user_id, project_id, options)
    
    provider_options = build_conversation_provider_options(conversation_history, options)
    
    case UniversalProviderService.complete(conversation_history, :orchestration, provider_options) do
      {:ok, universal_response} ->
        conversation_response = adapt_universal_response_to_conversation(universal_response, conversation_context)
        
        {:ok, conversation_response}
      
      error -> error
    end
  end
  
  @doc """
  Stream agent orchestration with real-time coordination feedback.
  """
  def orchestrate_streaming(prompt, orchestration_type, callback, user_id, project_id \\ nil, options \\ %{})
      when is_function(callback) do
    
    Logger.debug("Streaming agent orchestration using universal provider adapter")
    
    orchestration_context = build_orchestration_context(prompt, orchestration_type, user_id, project_id, options)
    
    # Create orchestration-aware streaming callback
    orchestration_callback = create_orchestration_streaming_callback(callback, orchestration_context)
    
    provider_options = build_orchestration_provider_options(orchestration_type, true, 
                                                           Map.put(options, :streaming, true))
    
    case UniversalProviderService.stream(prompt, :orchestration, orchestration_callback, provider_options) do
      {:ok, universal_response} ->
        orchestration_response = adapt_universal_response_to_orchestration(universal_response, orchestration_context)
        {:ok, Map.put(orchestration_response, :streaming, true)}
      
      error -> error
    end
  end
  
  @doc """
  Estimate orchestration cost with bulk operation discounts.
  """
  def estimate_orchestration_cost(prompt, orchestration_type, user_id, project_id \\ nil, options \\ %{}) do
    orchestration_context = build_orchestration_context(prompt, orchestration_type, user_id, project_id, options)
    cost_optimization_required = orchestration_type in @cost_sensitive_types
    
    provider_options = build_orchestration_provider_options(orchestration_type, cost_optimization_required, options)
    
    case UniversalProviderService.estimate_cost(prompt, :orchestration, provider_options) do
      {:ok, base_cost} ->
        # Apply orchestration discounts for bulk operations
        optimized_cost = apply_orchestration_cost_optimization(base_cost, orchestration_type, options)
        {:ok, optimized_cost}
      
      error -> error
    end
  end
  
  # Private implementation
  
  defp build_orchestration_context(prompt, orchestration_type, user_id, project_id, options) do
    %{
      prompt: prompt,
      orchestration_type: orchestration_type,
      user_id: user_id,
      project_id: project_id,
      cost_priority: Map.get(options, :cost_priority, 0.6),  # Higher cost focus for orchestration
      quality_threshold: Map.get(options, :quality_threshold, 0.7),  # Lower quality threshold for efficiency
      max_tokens: Map.get(options, :max_tokens, 1000),  # Shorter responses for orchestration
      agent_context: Map.get(options, :agent_context, %{}),
      specialized_features: determine_orchestration_features(orchestration_type, options)
    }
  end
  
  defp determine_orchestration_features(orchestration_type, options) do
    base_features = [:cost_optimization, :agent_communication, :efficiency_focus]
    
    type_specific_features = case orchestration_type do
      :agent_communication -> [:multi_turn_support, :context_preservation]
      :task_coordination -> [:planning_assistance, :workflow_optimization]
      :cost_optimization -> [:bulk_operation_discount, :resource_efficiency]
      _ -> []
    end
    
    user_features = Map.get(options, :specialized_features, [])
    
    (base_features ++ type_specific_features ++ user_features) |> Enum.uniq()
  end
  
  defp build_orchestration_provider_options(orchestration_type, cost_optimization_required, options) do
    base_options = %{
      use_case: orchestration_type,
      user_id: Map.get(options, :user_id),
      project_id: Map.get(options, :project_id),
      streaming: Map.get(options, :streaming, false),
      max_tokens: Map.get(options, :max_tokens, 1000),
      temperature: Map.get(options, :temperature, 0.3),  # Medium temperature for orchestration
      specialized_features: determine_orchestration_features(orchestration_type, options)
    }
    
    # Add cost optimization routing preference
    routing_options = if cost_optimization_required do
      Map.put(base_options, :routing_strategy, :cost_optimized)
    else
      Map.put(base_options, :routing_strategy, :balanced)
    end
    
    Map.merge(routing_options, options)
  end
  
  defp build_conversation_context(conversation_history, user_id, project_id, options) do
    %{
      conversation_history: conversation_history,
      user_id: user_id,
      project_id: project_id,
      conversation_length: length(conversation_history),
      cost_optimization: Map.get(options, :cost_optimization, true),
      context_preservation: Map.get(options, :context_preservation, true)
    }
  end
  
  defp build_conversation_provider_options(conversation_history, options) do
    # Optimize for multi-turn conversations
    conversation_length = length(conversation_history)
    
    # Adjust parameters based on conversation complexity
    max_tokens = case conversation_length do
      length when length > 10 -> 800   # Shorter responses for long conversations
      length when length > 5 -> 1000   # Medium responses
      _ -> 1200                        # Longer responses for short conversations
    end
    
    %{
      use_case: :agent_communication,
      user_id: Map.get(options, :user_id),
      project_id: Map.get(options, :project_id),
      max_tokens: max_tokens,
      temperature: 0.4,  # Balanced creativity for conversation
      routing_strategy: :cost_optimized,  # Optimize for conversation efficiency
      specialized_features: [:multi_turn_support, :context_preservation, :cost_optimization]
    }
  end
  
  defp adapt_universal_response_to_orchestration(universal_response, orchestration_context) do
    # Convert universal response to orchestration format
    domain_data = universal_response.domain_specific_data
    
    %{
      # Core orchestration response fields
      content: universal_response.content,
      success: universal_response.success,
      orchestration_type: orchestration_context.orchestration_type,
      
      # Cost and efficiency metrics
      cost_usd: universal_response.cost_usd,
      completion_quality: Map.get(domain_data, :completion_quality, 0.8),
      cost_efficiency: Map.get(domain_data, :cost_efficiency, 0.9),
      
      # Provider information
      provider: universal_response.provider,
      model: universal_response.model,
      response_time_ms: universal_response.response_time_ms,
      
      # Orchestration-specific metrics
      agent_communication_optimized: Map.has_key?(domain_data, :agent_communication_data),
      cost_optimized: :cost_optimization in orchestration_context.specialized_features,
      universal_provider_used: true,
      
      # Preserve metadata
      metadata: Map.merge(universal_response.metadata, %{
        orchestration_context: orchestration_context,
        adapted_from_universal: true
      })
    }
  end
  
  defp adapt_universal_response_to_conversation(universal_response, conversation_context) do
    # Convert universal response to conversation format
    %{
      content: universal_response.content,
      success: universal_response.success,
      conversation_length: conversation_context.conversation_length,
      cost_usd: universal_response.cost_usd,
      cost_optimized: conversation_context.cost_optimization,
      context_preserved: conversation_context.context_preservation,
      provider: universal_response.provider,
      model: universal_response.model,
      universal_provider_used: true
    }
  end
  
  defp create_orchestration_streaming_callback(original_callback, orchestration_context) do
    fn stream_event ->
      # Adapt streaming events for orchestration consumption
      orchestration_event = case Map.get(stream_event, :type) do
        :chunk ->
          %{
            type: :orchestration_progress,
            content: Map.get(stream_event, :content, ""),
            orchestration_type: orchestration_context.orchestration_type,
            cost_tracking: true,
            timestamp: DateTime.utc_now()
          }
        
        :complete ->
          %{
            type: :orchestration_complete,
            orchestration_type: orchestration_context.orchestration_type,
            result: Map.get(stream_event, :result, %{}),
            cost_optimized: true,
            timestamp: DateTime.utc_now()
          }
        
        _ ->
          Map.put(stream_event, :orchestration_context, orchestration_context.orchestration_type)
      end
      
      original_callback.(orchestration_event)
    end
  end
  
  defp apply_orchestration_cost_optimization(base_cost, orchestration_type, options) do
    # Apply cost optimization based on orchestration type
    optimization_factor = case orchestration_type do
      :bulk_operations -> 0.8        # 20% discount for bulk operations
      :frequent_coordination -> 0.9  # 10% discount for frequent use
      :background_processing -> 0.85 # 15% discount for background tasks
      _ -> 1.0                       # No discount
    end
    
    # Additional optimization for high-volume users
    volume_factor = case Map.get(options, :volume_tier, :standard) do
      :high_volume -> 0.9    # Additional 10% discount
      :enterprise -> 0.8     # Additional 20% discount
      _ -> 1.0
    end
    
    base_cost * optimization_factor * volume_factor
  end
  
  # Integration with existing Preferences LLM system
  
  @doc """
  Migrate existing Preferences LLM orchestration to universal provider system.
  """
  def migrate_from_preferences_system(prompt, user_id, project_id, options) do
    Logger.info("Migrating Preferences LLM orchestration to universal provider system")
    
    # Migrate options to universal format
    migrated_options = %{
      cost_optimization_required: true,
      routing_strategy: :cost_optimized,
      max_tokens: Map.get(options, :max_tokens, 1000),
      temperature: Map.get(options, :temperature, 0.3),
      migration_source: :preferences_system
    }
    
    orchestrate(prompt, :agent_communication, user_id, project_id, migrated_options)
  end
  
  @doc """
  Check compatibility with existing Preferences LLM configuration.
  """
  def check_preferences_compatibility(user_id, project_id \\ nil) do
    case UniversalProviderService.resolve_provider_config(:orchestration, user_id, project_id) do
      {:ok, config} ->
        {:ok, %{
          cost_optimization_available: Map.get(config, :cost_optimization_enabled, false),
          preferred_providers: Map.get(config, :preferred_providers, []),
          routing_strategy: Map.get(config, :routing_strategy, :cost_optimized),
          universal_provider_compatible: true
        }}
      
      error -> error
    end
  end
  
  @doc """
  Get orchestration recommendations using universal provider system.
  """
  def get_orchestration_recommendations(orchestration_type, requirements \\ %{}) do
    enhanced_requirements = Map.merge(requirements, %{
      use_case: orchestration_type,
      cost_optimization: true,
      specialized_features: determine_orchestration_features(orchestration_type, requirements)
    })
    
    ProviderRouter.get_provider_recommendations(:orchestration, enhanced_requirements)
  end
end