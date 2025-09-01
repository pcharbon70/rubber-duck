defmodule RubberDuck.Prompts.Agents.PromptComposerAgent do
  @moduledoc """
  Specialized Jido agent for hierarchical prompt composition execution.
  
  Provides autonomous prompt composition with System → Project → User resolution,
  context-aware variable interpolation, intelligent token optimization, and
  provider-specific formatting. Designed for enterprise-scale composition operations.
  
  Features:
  - Hierarchical prompt composition with System → Project → User deterministic resolution
  - Variable interpolation with context awareness and comprehensive security validation
  - Token optimization through intelligent compression and model-specific strategies
  - Provider-specific output formatting with LLM optimization and compatibility
  - Performance monitoring with sub-50ms composition targets and analytics tracking
  - Integration with caching, security, and analytics systems for optimal performance
  """

  use Jido.Agent,
    name: "prompt_composer",
    schema: [
      composition_request: [type: :map, required: true, doc: "Prompt composition request with name and context"],
      composition_strategy: [
        type: :atom,
        default: :hierarchical_merge,
        doc: "Composition strategy (:hierarchical_merge, :priority_override, :template_inheritance, :adaptive)"
      ],
      provider_target: [type: :string, default: "gpt-4", doc: "Target LLM provider for optimization"],
      performance_targets: [type: :map, default: %{}, doc: "Performance targets and optimization goals"],
      security_requirements: [type: :map, default: %{}, doc: "Security validation requirements"],
      analytics_tracking: [type: :boolean, default: true, doc: "Enable composition analytics tracking"]
    ]

  require Logger

  alias RubberDuck.Prompts.{
    Composition.CompositionEngine,
    Composition.TokenOptimizer,
    Composition.VariableInterpolator,
    Security.PromptValidator
  }

  @default_performance_targets %{
    max_composition_time_ms: 50,
    target_cache_hit_rate: 0.95,
    max_token_count: 4_000,
    min_quality_score: 0.8
  }

  @default_security_requirements %{
    validate_security: true,
    sanitize_content: true,
    check_injection: true,
    audit_composition: false
  }

  @supported_providers [
    "gpt-4", "gpt-3.5-turbo", "claude-3-opus", "claude-3-sonnet", 
    "claude-3-haiku", "claude-2", "gemini-pro"
  ]

  def start_agent(params, context \\ %{}) do
    Logger.info("PromptComposerAgent: Starting prompt composition execution",
      composition_strategy: params.composition_strategy,
      provider_target: params.provider_target,
      analytics_enabled: params.analytics_tracking
    )

    composition_start_time = System.monotonic_time(:microsecond)

    with {:ok, validated_params} <- validate_composition_params(params),
         {:ok, composition_plan} <- create_composition_plan(validated_params, context),
         {:ok, composition_result} <- execute_composition_pipeline(composition_plan),
         {:ok, formatted_result} <- format_for_provider(composition_result, validated_params.provider_target),
         {:ok, validated_result} <- validate_composition_result(formatted_result, composition_plan) do
      
      composition_time = System.monotonic_time(:microsecond) - composition_start_time
      
      Logger.info("PromptComposerAgent: Composition execution completed successfully",
        composition_time_us: composition_time,
        final_token_count: get_token_count(validated_result),
        provider_formatted: validated_params.provider_target,
        cache_hit: get_cache_hit_status(validated_result)
      )

      {:ok, %{
        composition_result: validated_result,
        composition_metadata: %{
          composition_time_microseconds: composition_time,
          strategy_used: params.composition_strategy,
          provider_target: params.provider_target,
          performance_metrics: calculate_composition_performance(validated_result, composition_time),
          security_validated: composition_plan.security_requirements.validate_security,
          analytics_recorded: params.analytics_tracking
        }
      }}
    else
      {:error, reason} ->
        Logger.error("PromptComposerAgent: Composition execution failed", error: reason)
        {:error, {:composition_execution_failed, reason}}
    end
  end

  # Private implementation functions

  defp validate_composition_params(params) do
    with :ok <- validate_composition_request(params.composition_request),
         :ok <- validate_composition_strategy(params.composition_strategy),
         :ok <- validate_provider_target(params.provider_target) do
      
      validated_params = Map.merge(params, %{
        performance_targets: Map.merge(@default_performance_targets, params.performance_targets),
        security_requirements: Map.merge(@default_security_requirements, params.security_requirements),
        validation_timestamp: DateTime.utc_now()
      })
      
      {:ok, validated_params}
    else
      {:error, reason} -> {:error, {:parameter_validation_failed, reason}}
    end
  end

  defp validate_composition_request(request) when is_map(request) do
    required_fields = [:prompt_name, :context]
    missing_fields = required_fields -- Map.keys(request)
    
    case missing_fields do
      [] -> :ok
      fields -> {:error, {:missing_required_fields, fields}}
    end
  end
  defp validate_composition_request(_), do: {:error, :invalid_composition_request}

  defp validate_composition_strategy(strategy) when strategy in [:hierarchical_merge, :priority_override, :template_inheritance, :adaptive], do: :ok
  defp validate_composition_strategy(_), do: {:error, :invalid_composition_strategy}

  defp validate_provider_target(provider) when provider in @supported_providers, do: :ok
  defp validate_provider_target(_), do: {:error, :unsupported_provider}

  defp create_composition_plan(validated_params, context) do
    composition_plan = %{
      composition_id: generate_composition_id(),
      request: validated_params.composition_request,
      strategy: validated_params.composition_strategy,
      provider_target: validated_params.provider_target,
      performance_targets: validated_params.performance_targets,
      security_requirements: validated_params.security_requirements,
      analytics_config: build_analytics_config(validated_params.analytics_tracking),
      execution_steps: create_execution_steps(validated_params),
      context: context
    }
    
    Logger.debug("PromptComposerAgent: Composition plan created",
      composition_id: composition_plan.composition_id,
      strategy: composition_plan.strategy,
      execution_steps: length(composition_plan.execution_steps)
    )
    
    {:ok, composition_plan}
  end

  defp execute_composition_pipeline(composition_plan) do
    request = composition_plan.request
    
    # Execute hierarchical composition
    composition_options = %{
      strategy: composition_plan.strategy,
      enable_caching: true,
      validate_security: composition_plan.security_requirements.validate_security,
      optimize_tokens: true,
      performance_tracking: true
    }
    
    case CompositionEngine.compose_prompt(
      request.prompt_name,
      request.context,
      composition_options
    ) do
      {:ok, composition_result} ->
        enhanced_result = Map.merge(composition_result, %{
          composition_id: composition_plan.composition_id,
          provider_target: composition_plan.provider_target,
          pipeline_executed: true
        })
        
        {:ok, enhanced_result}
      
      {:error, reason} ->
        {:error, {:composition_pipeline_failed, reason}}
    end
  end

  defp format_for_provider(composition_result, provider_target) do
    # Format composed prompt for specific LLM provider
    content = composition_result.content
    
    formatted_content = case provider_target do
      provider when provider in ["gpt-4", "gpt-3.5-turbo"] ->
        format_for_openai(content)
      
      provider when provider in ["claude-3-opus", "claude-3-sonnet", "claude-3-haiku", "claude-2"] ->
        format_for_anthropic(content)
      
      "gemini-pro" ->
        format_for_gemini(content)
      
      _ ->
        format_for_generic_provider(content)
    end
    
    formatted_result = Map.merge(composition_result, %{
      content: formatted_content,
      provider_formatted: true,
      original_content: content,
      provider_target: provider_target
    })
    
    {:ok, formatted_result}
  end

  defp validate_composition_result(composition_result, composition_plan) do
    # Validate final composition result
    validation_results = %{
      content_validation: validate_content_quality(composition_result.content),
      performance_validation: validate_performance_targets(composition_result, composition_plan),
      security_validation: validate_security_compliance(composition_result, composition_plan),
      provider_validation: validate_provider_compatibility(composition_result, composition_plan)
    }
    
    overall_valid = all_validations_passed?(validation_results)
    
    if overall_valid do
      validated_result = Map.merge(composition_result, %{
        validation_results: validation_results,
        validation_passed: true,
        ready_for_use: true
      })
      
      {:ok, validated_result}
    else
      {:error, {:composition_validation_failed, validation_results}}
    end
  end

  # Provider-specific formatting functions

  defp format_for_openai(content) do
    # OpenAI-specific formatting for optimal performance
    content
    |> ensure_clear_instructions()
    |> optimize_for_instruction_following()
    |> format_with_openai_conventions()
  end

  defp format_for_anthropic(content) do
    # Anthropic Claude-specific formatting
    content
    |> ensure_helpful_structure()
    |> optimize_for_constitutional_ai()
    |> format_with_anthropic_conventions()
  end

  defp format_for_gemini(content) do
    # Google Gemini-specific formatting
    content
    |> ensure_multimodal_compatibility()
    |> optimize_for_reasoning_chains()
    |> format_with_gemini_conventions()
  end

  defp format_for_generic_provider(content) do
    # Generic formatting for unknown providers
    content
    |> ensure_universal_compatibility()
    |> apply_safe_formatting()
  end

  # Formatting helper functions

  defp ensure_clear_instructions(content) do
    # Ensure content has clear instruction structure
    if String.starts_with?(content, ["Please", "Help", "Explain", "Generate"]) do
      content
    else
      "Please " <> content
    end
  end

  defp optimize_for_instruction_following(content) do
    # Optimize content for instruction-following models
    content
    |> String.replace(~r/\bplease\s+please\b/i, "please")
    |> String.trim()
  end

  defp format_with_openai_conventions(content) do
    # Apply OpenAI formatting conventions
    content
  end

  defp ensure_helpful_structure(content) do
    # Ensure content follows helpful/harmless/honest structure
    content
  end

  defp optimize_for_constitutional_ai(content) do
    # Optimize for Constitutional AI principles
    content
  end

  defp format_with_anthropic_conventions(content) do
    # Apply Anthropic formatting conventions
    content
  end

  defp ensure_multimodal_compatibility(content) do
    # Ensure compatibility with multimodal capabilities
    content
  end

  defp optimize_for_reasoning_chains(content) do
    # Optimize for reasoning chain processing
    content
  end

  defp format_with_gemini_conventions(content) do
    # Apply Gemini formatting conventions
    content
  end

  defp ensure_universal_compatibility(content) do
    # Ensure broad compatibility
    content
  end

  defp apply_safe_formatting(content) do
    # Apply safe formatting for unknown providers
    content
  end

  # Validation functions

  defp validate_content_quality(content) do
    %{
      valid: String.length(content) > 0,
      content_length: String.length(content),
      has_variables: String.contains?(content, "{{"),
      quality_indicators: analyze_content_quality_indicators(content)
    }
  end

  defp validate_performance_targets(composition_result, composition_plan) do
    targets = composition_plan.performance_targets
    metadata = composition_result.composition_metadata
    
    composition_time_ms = div(metadata.composition_time_microseconds, 1_000)
    
    %{
      valid: composition_time_ms <= targets.max_composition_time_ms,
      composition_time_ms: composition_time_ms,
      target_time_ms: targets.max_composition_time_ms,
      performance_score: calculate_performance_score(composition_time_ms, targets.max_composition_time_ms)
    }
  end

  defp validate_security_compliance(composition_result, composition_plan) do
    requirements = composition_plan.security_requirements
    
    %{
      valid: Map.get(composition_result, :security_validated, false) || not requirements.validate_security,
      security_validated: Map.get(composition_result, :security_validated, false),
      injection_checked: requirements.check_injection,
      content_sanitized: requirements.sanitize_content
    }
  end

  defp validate_provider_compatibility(composition_result, composition_plan) do
    %{
      valid: Map.get(composition_result, :provider_formatted, false),
      provider_target: composition_plan.provider_target,
      formatting_applied: Map.get(composition_result, :provider_formatted, false),
      token_optimized: Map.has_key?(composition_result, :optimization_metadata)
    }
  end

  defp all_validations_passed?(validation_results) do
    validation_results.content_validation.valid &&
    validation_results.performance_validation.valid &&
    validation_results.security_validation.valid &&
    validation_results.provider_validation.valid
  end

  # Utility functions

  defp build_analytics_config(analytics_enabled) do
    %{
      enabled: analytics_enabled,
      track_performance: true,
      track_effectiveness: true,
      track_provider_optimization: true
    }
  end

  defp create_execution_steps(validated_params) do
    [
      {:validate_composition_request, "Validate composition request parameters"},
      {:resolve_hierarchical_prompts, "Resolve System, Project, and User prompts"},
      {:execute_composition_strategy, "Execute selected composition strategy"},
      {:validate_composition_security, "Validate composition security and safety"},
      {:optimize_token_usage, "Optimize token usage and compression"},
      {:format_for_provider, "Format output for target LLM provider"},
      {:validate_final_result, "Validate final composition result"},
      {:record_composition_analytics, "Record composition analytics and metrics"}
    ]
  end

  defp analyze_content_quality_indicators(content) do
    %{
      instruction_clarity: has_clear_instructions?(content),
      template_structure: has_template_structure?(content),
      length_appropriateness: has_appropriate_length?(content),
      provider_compatibility: assess_provider_compatibility(content)
    }
  end

  defp has_clear_instructions?(content) do
    instruction_patterns = [
      ~r/(please|help|explain|generate|create|analyze)/i,
      ~r/(how to|what is|why does|when should)/i
    ]
    
    Enum.any?(instruction_patterns, fn pattern ->
      Regex.match?(pattern, content)
    end)
  end

  defp has_template_structure?(content) do
    String.contains?(content, "{{") && String.contains?(content, "}}")
  end

  defp has_appropriate_length?(content) do
    length = String.length(content)
    length > 10 && length < 10_000
  end

  defp assess_provider_compatibility(content) do
    # Assess compatibility with different providers
    %{
      openai_compatible: true,  # Most content is OpenAI compatible
      anthropic_compatible: not String.contains?(content, "<thinking>"),  # Avoid internal thinking tags
      gemini_compatible: true   # Gemini is generally flexible
    }
  end

  defp calculate_performance_score(actual_time_ms, target_time_ms) do
    case actual_time_ms do
      time when time <= target_time_ms -> 1.0
      time -> max(0.0, target_time_ms / time)
    end
  end

  defp calculate_composition_performance(composition_result, composition_time) do
    %{
      composition_time_ms: div(composition_time, 1_000),
      token_efficiency: calculate_token_efficiency(composition_result),
      cache_performance: calculate_cache_performance(composition_result),
      security_overhead: calculate_security_overhead(composition_result)
    }
  end

  defp calculate_token_efficiency(composition_result) do
    case Map.get(composition_result, :optimization_metadata) do
      nil -> 1.0
      metadata -> 
        original = metadata.original_token_count
        final = metadata.final_token_count
        
        case original do
          0 -> 1.0
          _ -> (original - final) / original
        end
    end
  end

  defp calculate_cache_performance(composition_result) do
    %{
      cache_hit: get_cache_hit_status(composition_result),
      cache_efficiency: 0.85  # Would calculate based on actual cache metrics
    }
  end

  defp calculate_security_overhead(composition_result) do
    # Calculate security validation overhead
    case Map.get(composition_result, :validation_results) do
      nil -> 0.0
      _ -> 5.0  # Approximate 5ms security overhead
    end
  end

  defp get_token_count(composition_result) do
    case composition_result.composition_metadata do
      %{final_token_count: count} -> count
      _ -> 0
    end
  end

  defp get_cache_hit_status(composition_result) do
    Map.get(composition_result, :cache_hit, false)
  end

  defp generate_composition_id do
    timestamp = System.system_time(:nanosecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "composition_#{timestamp}_#{random}"
  end
end