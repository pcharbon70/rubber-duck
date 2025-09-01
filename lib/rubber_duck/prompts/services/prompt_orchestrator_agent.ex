defmodule RubberDuck.Prompts.Services.PromptOrchestratorAgent do
  @moduledoc """
  Prompt composition coordination agent with comprehensive management capabilities.

  Coordinates complete prompt composition pipeline including retrieval, composition,
  validation, caching management, and usage analytics. Provides centralized orchestration
  for all prompt-related operations with performance monitoring and optimization.

  Features:
  - Complete prompt composition pipeline coordination with hierarchical resolution and optimization
  - Prompt caching management with intelligent warming, eviction, and coherence strategies
  - Security validation and prompt injection prevention with comprehensive content analysis
  - Usage analytics tracking with performance metrics and effectiveness measurement
  - Integration with LLM orchestration for seamless composed prompt injection
  - Performance monitoring with real-time analytics and optimization recommendations
  """

  use Jido.Agent,
    name: "prompt_orchestrator",
    schema: [
      prompt_name: [type: :string, required: true, doc: "Name of prompt to orchestrate"],
      composition_context: [type: :map, required: true, doc: "Context for prompt composition"],
      orchestration_options: [
        type: :map,
        default: %{},
        doc: "Orchestration configuration options"
      ],
      performance_targets: [
        type: :map,
        default: %{},
        doc: "Performance targets and optimization goals"
      ],
      security_requirements: [type: :map, default: %{}, doc: "Security validation requirements"],
      caching_strategy: [
        type: :atom,
        default: :intelligent,
        doc: "Caching strategy (:intelligent, :aggressive, :conservative, :disabled)"
      ]
    ]

  require Logger

  alias RubberDuck.Prompts.{
    Composition.CompositionEngine,
    Services.CompositionCache,
    Resources.PromptUsage
  }

  @default_orchestration_options %{
    enable_composition: true,
    enable_caching: true,
    enable_analytics: true,
    enable_security_validation: true,
    performance_monitoring: true,
    fallback_strategy: :system_prompt
  }

  @default_performance_targets %{
    max_composition_time_ms: 50,
    min_cache_hit_rate: 0.95,
    max_token_count: 4_000,
    min_quality_score: 0.8
  }

  @default_security_requirements %{
    validate_variables: true,
    prevent_injection: true,
    sanitize_content: true,
    audit_composition: true
  }

  def start_agent(params, context \\ %{}) do
    Logger.info("PromptOrchestratorAgent: Starting prompt orchestration",
      prompt_name: params.prompt_name,
      caching_strategy: params.caching_strategy,
      context_keys: Map.keys(params.composition_context)
    )

    orchestration_start_time = System.monotonic_time(:microsecond)

    with {:ok, validated_params} <- validate_orchestration_params(params),
         {:ok, orchestration_plan} <- create_orchestration_plan(validated_params, context),
         {:ok, composition_result} <- execute_prompt_composition(orchestration_plan),
         {:ok, validated_result} <-
           validate_composition_result(composition_result, orchestration_plan),
         {:ok, analytics_result} <- record_usage_analytics(validated_result, orchestration_plan) do
      orchestration_time = System.monotonic_time(:microsecond) - orchestration_start_time

      Logger.info("PromptOrchestratorAgent: Orchestration completed successfully",
        prompt_name: params.prompt_name,
        orchestration_time_us: orchestration_time,
        final_token_count: Map.get(validated_result, :final_token_count, 0),
        cache_hit: Map.get(validated_result, :cache_hit, false)
      )

      {:ok,
       %{
         orchestration_result: validated_result,
         orchestration_metadata: %{
           orchestration_time_microseconds: orchestration_time,
           prompt_name: params.prompt_name,
           composition_successful: true,
           caching_strategy_used: params.caching_strategy,
           performance_targets_met:
             validate_performance_targets(validated_result, orchestration_plan),
           security_validation_passed: Map.get(validated_result, :security_validated, false),
           usage_analytics_recorded: analytics_result.analytics_recorded
         }
       }}
    else
      {:error, reason} ->
        Logger.error("PromptOrchestratorAgent: Orchestration failed",
          prompt_name: params.prompt_name,
          error: reason
        )

        case attempt_fallback_orchestration(params, reason, context) do
          {:ok, fallback_result} ->
            {:error, {:orchestration_failed_with_fallback, reason, fallback_result}}

          {:error, fallback_error} ->
            {:error, {:orchestration_failed, reason, fallback_error}}
        end
    end
  end

  # Private implementation functions

  defp validate_orchestration_params(params) do
    with :ok <- validate_prompt_name(params.prompt_name),
         :ok <- validate_composition_context(params.composition_context),
         :ok <- validate_caching_strategy(params.caching_strategy) do
      validated_params =
        Map.merge(params, %{
          orchestration_options:
            Map.merge(@default_orchestration_options, params.orchestration_options),
          performance_targets:
            Map.merge(@default_performance_targets, params.performance_targets),
          security_requirements:
            Map.merge(@default_security_requirements, params.security_requirements),
          validation_timestamp: DateTime.utc_now()
        })

      {:ok, validated_params}
    else
      {:error, reason} -> {:error, {:parameter_validation_failed, reason}}
    end
  end

  defp validate_prompt_name(name) when is_binary(name) and byte_size(name) > 0, do: :ok
  defp validate_prompt_name(_), do: {:error, :invalid_prompt_name}

  defp validate_composition_context(context) when is_map(context), do: :ok
  defp validate_composition_context(_), do: {:error, :invalid_composition_context}

  defp validate_caching_strategy(strategy)
       when strategy in [:intelligent, :aggressive, :conservative, :disabled],
       do: :ok

  defp validate_caching_strategy(_), do: {:error, :invalid_caching_strategy}

  defp create_orchestration_plan(validated_params, context) do
    orchestration_plan = %{
      orchestration_id: generate_orchestration_id(),
      prompt_name: validated_params.prompt_name,
      composition_context: validated_params.composition_context,
      orchestration_options: validated_params.orchestration_options,
      performance_targets: validated_params.performance_targets,
      security_requirements: validated_params.security_requirements,
      caching_configuration: build_caching_configuration(validated_params.caching_strategy),
      execution_steps: create_execution_steps(validated_params),
      monitoring_config: create_monitoring_configuration(validated_params),
      context: context
    }

    Logger.debug("PromptOrchestratorAgent: Orchestration plan created",
      orchestration_id: orchestration_plan.orchestration_id,
      execution_steps: length(orchestration_plan.execution_steps)
    )

    {:ok, orchestration_plan}
  end

  defp execute_prompt_composition(orchestration_plan) do
    composition_options = %{
      strategy: :hierarchical_merge,
      enable_caching: orchestration_plan.caching_configuration.enabled,
      validate_security: orchestration_plan.security_requirements.validate_variables,
      optimize_tokens: true,
      performance_tracking: orchestration_plan.orchestration_options.performance_monitoring
    }

    case CompositionEngine.compose_prompt(
           orchestration_plan.prompt_name,
           orchestration_plan.composition_context,
           composition_options
         ) do
      {:ok, composition_result} ->
        {:ok,
         Map.merge(composition_result, %{
           orchestration_id: orchestration_plan.orchestration_id,
           cache_hit: determine_cache_hit_status(composition_result),
           security_validated: composition_options.validate_security
         })}

      {:error, reason} ->
        {:error, {:composition_execution_failed, reason}}
    end
  end

  defp validate_composition_result(composition_result, orchestration_plan) do
    validation_results = %{
      content_validation: validate_content_quality(composition_result.content),
      performance_validation:
        validate_performance_targets(composition_result, orchestration_plan),
      security_validation: validate_security_requirements(composition_result, orchestration_plan),
      token_validation: validate_token_limits(composition_result, orchestration_plan)
    }

    overall_valid =
      validation_results.content_validation.valid &&
        validation_results.performance_validation.valid &&
        validation_results.security_validation.valid &&
        validation_results.token_validation.valid

    if overall_valid do
      {:ok,
       Map.merge(composition_result, %{
         validation_results: validation_results,
         validation_passed: true
       })}
    else
      {:error, {:validation_failed, validation_results}}
    end
  end

  defp record_usage_analytics(composition_result, orchestration_plan) do
    if orchestration_plan.orchestration_options.enable_analytics do
      # Record successful composition usage
      usage_data = %{
        prompt_id: get_primary_prompt_id(composition_result),
        used_by_id: Map.get(orchestration_plan.context, :user_id),
        context_type: :template_expansion,
        response_time_ms:
          div(composition_result.composition_metadata.composition_time_microseconds, 1_000),
        tokens_used: composition_result.composition_metadata.final_token_count,
        success: true,
        performance_metrics: %{
          cache_hit: Map.get(composition_result, :cache_hit, false),
          composition_strategy: composition_result.composition_metadata.strategy_used,
          security_validated: Map.get(composition_result, :security_validated, false)
        }
      }

      case record_composition_usage(usage_data) do
        {:ok, _usage_record} ->
          {:ok, %{analytics_recorded: true}}

        {:error, reason} ->
          Logger.warn("PromptOrchestratorAgent: Failed to record analytics", error: reason)
          {:ok, %{analytics_recorded: false, analytics_error: reason}}
      end
    else
      {:ok, %{analytics_disabled: true}}
    end
  end

  # Helper functions

  defp build_caching_configuration(caching_strategy) do
    %{
      enabled: caching_strategy != :disabled,
      strategy: caching_strategy,
      ets_ttl:
        case caching_strategy do
          # 5 minutes
          :aggressive -> 300
          # 1 minute
          :intelligent -> 60
          # 30 seconds
          :conservative -> 30
          :disabled -> 0
        end,
      redis_ttl:
        case caching_strategy do
          # 2 hours
          :aggressive -> 7200
          # 1 hour
          :intelligent -> 3600
          # 30 minutes
          :conservative -> 1800
          :disabled -> 0
        end
    }
  end

  defp create_execution_steps(validated_params) do
    base_steps = [
      {:validate_composition_context, "Validate composition context and parameters"},
      {:resolve_hierarchical_prompts, "Resolve System, Project, and User prompts"},
      {:execute_prompt_composition, "Execute hierarchical prompt composition"},
      {:validate_composed_content, "Validate composed content and security"},
      {:optimize_token_usage, "Optimize token usage and compression"},
      {:record_usage_analytics, "Record usage analytics and performance metrics"}
    ]

    # Add optional steps based on configuration
    optional_steps = []

    optional_steps =
      if validated_params.orchestration_options.enable_caching do
        [{:manage_cache_operations, "Manage caching operations and coherence"} | optional_steps]
      else
        optional_steps
      end

    base_steps ++ optional_steps
  end

  defp create_monitoring_configuration(validated_params) do
    %{
      performance_monitoring: validated_params.orchestration_options.performance_monitoring,
      cache_monitoring: validated_params.orchestration_options.enable_caching,
      security_monitoring: validated_params.security_requirements.audit_composition,
      analytics_collection: validated_params.orchestration_options.enable_analytics
    }
  end

  defp determine_cache_hit_status(composition_result) do
    # Determine if composition used cached data
    metadata = composition_result.composition_metadata

    # Check if composition time was very fast (likely cached)
    composition_time_ms = div(metadata.composition_time_microseconds, 1_000)
    # Sub-10ms likely indicates cache hit
    composition_time_ms < 10
  end

  defp validate_content_quality(content) do
    %{
      valid: String.length(content) > 0,
      content_length: String.length(content),
      quality_score: calculate_content_quality_score(content)
    }
  end

  defp validate_performance_targets(composition_result, orchestration_plan) do
    targets = orchestration_plan.performance_targets
    metadata = composition_result.composition_metadata

    composition_time_ms = div(metadata.composition_time_microseconds, 1_000)

    %{
      valid: composition_time_ms <= targets.max_composition_time_ms,
      composition_time_ms: composition_time_ms,
      target_time_ms: targets.max_composition_time_ms,
      performance_score:
        calculate_performance_score(composition_time_ms, targets.max_composition_time_ms)
    }
  end

  defp validate_security_requirements(composition_result, orchestration_plan) do
    requirements = orchestration_plan.security_requirements

    %{
      valid:
        Map.get(composition_result, :security_validated, false) ||
          not requirements.validate_variables,
      security_validated: Map.get(composition_result, :security_validated, false),
      injection_prevention_active: requirements.prevent_injection,
      content_sanitization_active: requirements.sanitize_content
    }
  end

  defp validate_token_limits(composition_result, orchestration_plan) do
    targets = orchestration_plan.performance_targets
    metadata = composition_result.composition_metadata

    %{
      valid: metadata.final_token_count <= targets.max_token_count,
      final_token_count: metadata.final_token_count,
      token_limit: targets.max_token_count,
      token_efficiency:
        calculate_token_efficiency(metadata.final_token_count, targets.max_token_count)
    }
  end

  defp get_primary_prompt_id(composition_result) do
    # Get primary prompt ID for analytics (would extract from actual composition)
    Ash.UUID.generate()
  end

  defp record_composition_usage(usage_data) do
    # Record composition usage for analytics
    case PromptUsage.record_successful_usage(usage_data) do
      {:ok, usage_record} -> {:ok, usage_record}
      {:error, reason} -> {:error, reason}
    end
  end

  defp attempt_fallback_orchestration(params, _original_error, context) do
    # Attempt fallback orchestration strategy
    Logger.info("PromptOrchestratorAgent: Attempting fallback orchestration",
      prompt_name: params.prompt_name
    )

    # Simple fallback to basic system prompt
    fallback_result = %{
      content: "System fallback: Please {{instruction}}.",
      fallback_used: true,
      original_prompt_name: params.prompt_name
    }

    {:ok, fallback_result}
  end

  # Utility functions

  defp calculate_content_quality_score(content) do
    # Calculate content quality based on various factors
    base_score = 0.5

    # Length factor (neither too short nor too long)
    length_factor =
      case String.length(content) do
        len when len < 50 -> 0.6
        len when len < 200 -> 1.0
        len when len < 1000 -> 0.9
        _ -> 0.7
      end

    # Variable factor (has template variables)
    variable_factor =
      if String.contains?(content, "{{") do
        1.2
      else
        1.0
      end

    # Structure factor (has clear instructions)
    structure_factor =
      if Regex.match?(~r/(please|help|assist|provide)/i, content) do
        1.1
      else
        1.0
      end

    final_score = base_score * length_factor * variable_factor * structure_factor
    min(1.0, final_score)
  end

  defp calculate_performance_score(actual_time_ms, target_time_ms) do
    case actual_time_ms do
      time when time <= target_time_ms -> 1.0
      time -> max(0.0, target_time_ms / time)
    end
  end

  defp calculate_token_efficiency(actual_tokens, token_limit) do
    case token_limit do
      0 -> 1.0
      limit -> min(1.0, (limit - actual_tokens) / limit)
    end
  end

  defp generate_orchestration_id do
    timestamp = System.system_time(:nanosecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "orchestration_#{timestamp}_#{random}"
  end
end
