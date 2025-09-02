defmodule RubberDuck.Workflows.Enhancements.WorkflowStepPromptInjector do
  @moduledoc """
  Prompt injection service for workflow steps with intelligent integration.
  
  Provides sophisticated prompt injection capabilities for Reactor workflow steps,
  enabling automatic prompt resolution, context enhancement, and seamless
  integration of composed prompts into workflow execution with performance
  optimization and validation.
  
  Features:
  - Prompt injection into workflow steps with automatic resolution and composition
  - Context-aware prompt enhancement during step execution with optimization
  - Step-specific prompt optimization with performance monitoring and analytics
  - Integration with Reactor step execution pipeline with minimal overhead
  - Dynamic prompt resolution with caching and performance coordination
  - Validation and error handling for prompt injection with comprehensive recovery
  """

  require Logger

  alias RubberDuck.Prompts.WorkflowIntegration.{
    WorkflowPromptResolver,
    WorkflowContextEnhancer,
    ReactorPromptIntegration
  }

  @injection_strategies [:parameter_injection, :context_injection, :metadata_injection, :comprehensive]
  @injection_timing [:before_step, :during_step, :after_step, :conditional]

  def inject_prompt_into_step(step_config, prompt_injection_spec, injection_options \\ %{}) do
    injection_start_time = System.monotonic_time(:microsecond)

    Logger.debug("WorkflowStepPromptInjector: Injecting prompt into workflow step",
      step_name: Map.get(step_config, :name, "unknown"),
      prompt_name: Map.get(prompt_injection_spec, :prompt_name, "unknown"),
      injection_strategy: Map.get(injection_options, :injection_strategy, :parameter_injection)
    )

    case execute_prompt_injection(step_config, prompt_injection_spec, injection_options) do
      {:ok, injection_result} ->
        injection_time = System.monotonic_time(:microsecond) - injection_start_time

        Logger.info("WorkflowStepPromptInjector: Prompt injection completed",
          step_name: injection_result.enhanced_step.name,
          prompt_name: injection_result.prompt_name,
          injection_time_us: injection_time,
          injection_successful: injection_result.injection_successful
        )

        {:ok, injection_result}

      {:error, reason} ->
        injection_time = System.monotonic_time(:microsecond) - injection_start_time

        Logger.error("WorkflowStepPromptInjector: Prompt injection failed",
          step_name: Map.get(step_config, :name, "unknown"),
          error: reason,
          injection_time_us: injection_time
        )

        {:error, reason}
    end
  end

  def enhance_step_with_context_aware_prompts(step_config, context_enhancement_spec, options \\ %{}) do
    Logger.debug("WorkflowStepPromptInjector: Enhancing step with context-aware prompts",
      step_name: Map.get(step_config, :name, "unknown"),
      context_enhancement_enabled: Map.get(options, :enable_context_enhancement, true)
    )

    case execute_context_aware_enhancement(step_config, context_enhancement_spec, options) do
      {:ok, enhanced_step} ->
        Logger.info("WorkflowStepPromptInjector: Context-aware enhancement completed",
          step_name: enhanced_step.name,
          context_enhancement_level: enhanced_step.context_enhancement_level
        )

        {:ok, enhanced_step}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def batch_inject_prompts_into_steps(steps_config, batch_injection_spec, options \\ %{}) do
    Logger.debug("WorkflowStepPromptInjector: Batch injecting prompts into steps",
      steps_count: length(steps_config),
      batch_size: length(Map.get(batch_injection_spec, :prompt_injections, []))
    )

    case execute_batch_prompt_injection(steps_config, batch_injection_spec, options) do
      {:ok, batch_result} ->
        Logger.info("WorkflowStepPromptInjector: Batch injection completed",
          steps_enhanced: batch_result.steps_enhanced,
          successful_injections: batch_result.successful_injections
        )

        {:ok, batch_result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private implementation functions

  defp execute_prompt_injection(step_config, prompt_injection_spec, injection_options) do
    # Execute comprehensive prompt injection
    injection_strategy = determine_injection_strategy(prompt_injection_spec, injection_options)

    case injection_strategy do
      :parameter_injection ->
        execute_parameter_injection(step_config, prompt_injection_spec, injection_options)

      :context_injection ->
        execute_context_injection(step_config, prompt_injection_spec, injection_options)

      :metadata_injection ->
        execute_metadata_injection(step_config, prompt_injection_spec, injection_options)

      :comprehensive ->
        execute_comprehensive_injection(step_config, prompt_injection_spec, injection_options)
    end
  end

  defp execute_parameter_injection(step_config, prompt_injection_spec, injection_options) do
    # Execute parameter-based prompt injection
    with {:ok, resolved_prompt} <- resolve_prompt_for_injection(prompt_injection_spec, injection_options),
         {:ok, enhanced_step} <- inject_prompt_as_parameter(step_config, resolved_prompt, injection_options) do
      
      injection_result = %{
        enhanced_step: enhanced_step,
        prompt_name: prompt_injection_spec.prompt_name,
        injection_strategy: :parameter_injection,
        injection_successful: true,
        resolved_prompt: resolved_prompt
      }

      {:ok, injection_result}
    else
      {:error, reason} -> {:error, {:parameter_injection_failed, reason}}
    end
  end

  defp execute_context_injection(step_config, prompt_injection_spec, injection_options) do
    # Execute context-based prompt injection
    with {:ok, resolved_prompt} <- resolve_prompt_for_injection(prompt_injection_spec, injection_options),
         {:ok, enhanced_context} <- enhance_step_context_with_prompt(step_config, resolved_prompt, injection_options),
         {:ok, enhanced_step} <- apply_context_enhancement_to_step(step_config, enhanced_context) do
      
      injection_result = %{
        enhanced_step: enhanced_step,
        prompt_name: prompt_injection_spec.prompt_name,
        injection_strategy: :context_injection,
        injection_successful: true,
        enhanced_context: enhanced_context
      }

      {:ok, injection_result}
    else
      {:error, reason} -> {:error, {:context_injection_failed, reason}}
    end
  end

  defp execute_metadata_injection(step_config, prompt_injection_spec, injection_options) do
    # Execute metadata-based prompt injection
    with {:ok, resolved_prompt} <- resolve_prompt_for_injection(prompt_injection_spec, injection_options),
         {:ok, enhanced_step} <- inject_prompt_as_metadata(step_config, resolved_prompt, injection_options) do
      
      injection_result = %{
        enhanced_step: enhanced_step,
        prompt_name: prompt_injection_spec.prompt_name,
        injection_strategy: :metadata_injection,
        injection_successful: true,
        metadata_enhanced: true
      }

      {:ok, injection_result}
    else
      {:error, reason} -> {:error, {:metadata_injection_failed, reason}}
    end
  end

  defp execute_comprehensive_injection(step_config, prompt_injection_spec, injection_options) do
    # Execute comprehensive injection using all strategies
    with {:ok, param_result} <- execute_parameter_injection(step_config, prompt_injection_spec, injection_options),
         {:ok, context_result} <- execute_context_injection(param_result.enhanced_step, prompt_injection_spec, injection_options),
         {:ok, metadata_result} <- execute_metadata_injection(context_result.enhanced_step, prompt_injection_spec, injection_options) do
      
      comprehensive_result = %{
        enhanced_step: metadata_result.enhanced_step,
        prompt_name: prompt_injection_spec.prompt_name,
        injection_strategy: :comprehensive,
        injection_successful: true,
        comprehensive_injection_metadata: %{
          parameter_injection: param_result,
          context_injection: context_result,
          metadata_injection: metadata_result,
          comprehensive_complete: true
        }
      }

      {:ok, comprehensive_result}
    else
      {:error, reason} -> {:error, {:comprehensive_injection_failed, reason}}
    end
  end

  defp execute_context_aware_enhancement(step_config, context_enhancement_spec, options) do
    # Execute context-aware step enhancement
    workflow_id = Map.get(options, :workflow_id, generate_temporary_workflow_id())
    
    with {:ok, enhanced_context} <- enhance_step_execution_context(step_config, context_enhancement_spec, options),
         {:ok, context_integrated_step} <- integrate_enhanced_context_with_step(step_config, enhanced_context) do
      
      context_aware_step = Map.merge(context_integrated_step, %{
        context_enhancement_level: determine_context_enhancement_level(context_enhancement_spec, options),
        context_aware_metadata: %{
          context_enhancement_applied: true,
          enhancement_timestamp: DateTime.utc_now(),
          workflow_id: workflow_id
        }
      })

      {:ok, context_aware_step}
    else
      {:error, reason} -> {:error, {:context_aware_enhancement_failed, reason}}
    end
  end

  defp execute_batch_prompt_injection(steps_config, batch_injection_spec, options) do
    # Execute batch prompt injection for multiple steps
    prompt_injections = Map.get(batch_injection_spec, :prompt_injections, [])
    
    injection_results = Enum.zip(steps_config, prompt_injections)
    |> Enum.map(fn {step_config, injection_spec} ->
      inject_prompt_into_step(step_config, injection_spec, options)
    end)

    successful_injections = Enum.filter(injection_results, &match?({:ok, _}, &1))
    failed_injections = Enum.filter(injection_results, &match?({:error, _}, &1))

    batch_result = %{
      total_steps: length(steps_config),
      successful_injections: length(successful_injections),
      failed_injections: length(failed_injections),
      steps_enhanced: Enum.map(successful_injections, fn {:ok, result} -> result.enhanced_step end),
      injection_success_rate: length(successful_injections) / length(steps_config),
      batch_injection_metadata: %{
        batch_completed_at: DateTime.utc_now(),
        injection_results: injection_results
      }
    }

    {:ok, batch_result}
  end

  # Helper functions

  defp determine_injection_strategy(prompt_injection_spec, injection_options) do
    case {
      Map.get(injection_options, :injection_strategy),
      Map.get(prompt_injection_spec, :injection_type, :parameter),
      Map.get(injection_options, :comprehensive_injection, false)
    } do
      {strategy, _, _} when strategy in @injection_strategies -> strategy
      {nil, :parameter, false} -> :parameter_injection
      {nil, :context, false} -> :context_injection
      {nil, :metadata, false} -> :metadata_injection
      {nil, _, true} -> :comprehensive
      _ -> :parameter_injection
    end
  end

  defp resolve_prompt_for_injection(prompt_injection_spec, injection_options) do
    # Resolve prompt for injection
    workflow_id = Map.get(injection_options, :workflow_id, generate_temporary_workflow_id())
    prompt_name = prompt_injection_spec.prompt_name
    context = Map.get(injection_options, :context, %{})

    case WorkflowPromptResolver.resolve_workflow_prompt(workflow_id, prompt_name, context, injection_options) do
      {:ok, resolution_result} ->
        {:ok, resolution_result}

      {:error, reason} ->
        {:error, {:prompt_resolution_failed, reason}}
    end
  end

  defp inject_prompt_as_parameter(step_config, resolved_prompt, injection_options) do
    # Inject resolved prompt as step parameter
    parameter_name = Map.get(injection_options, :parameter_name, :injected_prompt)
    
    current_parameters = Map.get(step_config, :parameters, %{})
    updated_parameters = Map.put(current_parameters, parameter_name, resolved_prompt.resolved_prompt)
    
    enhanced_step = Map.merge(step_config, %{
      parameters: updated_parameters,
      parameter_injection_metadata: %{
        injected_parameter: parameter_name,
        prompt_name: resolved_prompt.prompt_name,
        injection_timestamp: DateTime.utc_now()
      }
    })

    {:ok, enhanced_step}
  end

  defp enhance_step_context_with_prompt(step_config, resolved_prompt, injection_options) do
    # Enhance step context with prompt information
    base_context = Map.get(step_config, :context, %{})
    workflow_id = Map.get(injection_options, :workflow_id, "temp")

    case WorkflowContextEnhancer.enhance_context(base_context, workflow_id, injection_options) do
      {:ok, enhanced_context} ->
        # Add prompt-specific context
        prompt_enhanced_context = Map.merge(enhanced_context, %{
          prompt_content: resolved_prompt.resolved_prompt,
          prompt_metadata: resolved_prompt,
          prompt_context_enhanced: true
        })

        {:ok, prompt_enhanced_context}

      {:error, reason} ->
        {:error, {:context_enhancement_failed, reason}}
    end
  end

  defp apply_context_enhancement_to_step(step_config, enhanced_context) do
    # Apply enhanced context to step configuration
    enhanced_step = Map.merge(step_config, %{
      context: enhanced_context,
      context_enhanced: true,
      context_enhancement_metadata: %{
        context_keys: Map.keys(enhanced_context),
        enhancement_applied: true,
        enhanced_at: DateTime.utc_now()
      }
    })

    {:ok, enhanced_step}
  end

  defp inject_prompt_as_metadata(step_config, resolved_prompt, injection_options) do
    # Inject resolved prompt as step metadata
    metadata_key = Map.get(injection_options, :metadata_key, :prompt_injection)
    
    current_metadata = Map.get(step_config, :metadata, %{})
    prompt_metadata = %{
      resolved_prompt: resolved_prompt.resolved_prompt,
      prompt_name: resolved_prompt.prompt_name,
      resolution_metadata: resolved_prompt,
      injection_timestamp: DateTime.utc_now()
    }
    
    updated_metadata = Map.put(current_metadata, metadata_key, prompt_metadata)
    
    enhanced_step = Map.merge(step_config, %{
      metadata: updated_metadata,
      metadata_injection_applied: true
    })

    {:ok, enhanced_step}
  end

  defp enhance_step_execution_context(step_config, context_enhancement_spec, options) do
    # Enhance step execution context
    base_context = Map.get(step_config, :execution_context, %{})
    enhancement_config = Map.get(context_enhancement_spec, :enhancement_config, %{})

    enhanced_context = Map.merge(base_context, %{
      step_name: Map.get(step_config, :name, "unknown"),
      enhancement_spec: context_enhancement_spec,
      enhancement_options: options,
      context_enhancement_applied: true,
      enhanced_at: DateTime.utc_now()
    })

    case WorkflowContextEnhancer.optimize_context_for_workflow(
      enhanced_context,
      Map.get(options, :workflow_type, :general),
      enhancement_config
    ) do
      {:ok, optimization_result} ->
        {:ok, optimization_result.optimized_context}

      {:error, reason} ->
        Logger.warning("Context optimization failed, using basic enhancement: #{inspect(reason)}")
        {:ok, enhanced_context}
    end
  end

  defp integrate_enhanced_context_with_step(step_config, enhanced_context) do
    # Integrate enhanced context back into step configuration
    integrated_step = Map.merge(step_config, %{
      execution_context: enhanced_context,
      context_integration_applied: true,
      context_integration_metadata: %{
        context_keys: Map.keys(enhanced_context),
        integration_successful: true,
        integrated_at: DateTime.utc_now()
      }
    })

    {:ok, integrated_step}
  end

  defp determine_context_enhancement_level(context_enhancement_spec, options) do
    # Determine context enhancement level
    case {
      Map.get(options, :enhancement_level),
      Map.get(context_enhancement_spec, :complexity, :medium),
      Map.get(options, :performance_priority, :balanced)
    } do
      {:high, _, _} -> :high
      {:medium, :high, _} -> :high
      {:medium, _, :performance} -> :medium
      {:low, _, _} -> :low
      {nil, :high, :quality} -> :high
      {nil, :medium, _} -> :medium
      _ -> :standard
    end
  end

  # Utility functions for workflow integration

  def create_prompt_injection_specification(prompt_name, injection_config \\ %{}) do
    # Create prompt injection specification
    injection_spec = %{
      prompt_name: prompt_name,
      injection_type: Map.get(injection_config, :injection_type, :parameter),
      injection_timing: Map.get(injection_config, :injection_timing, :before_step),
      validation_required: Map.get(injection_config, :validation_required, true),
      optimization_enabled: Map.get(injection_config, :optimization_enabled, true),
      cache_enabled: Map.get(injection_config, :cache_enabled, true),
      created_at: DateTime.utc_now()
    }

    {:ok, injection_spec}
  end

  def validate_prompt_injection_compatibility(step_config, prompt_injection_spec) do
    # Validate compatibility between step and prompt injection
    step_type = Map.get(step_config, :type, :unknown)
    injection_type = Map.get(prompt_injection_spec, :injection_type, :parameter)

    compatibility_analysis = %{
      step_type: step_type,
      injection_type: injection_type,
      compatible: check_injection_compatibility(step_type, injection_type),
      compatibility_score: calculate_compatibility_score(step_config, prompt_injection_spec),
      recommendations: generate_compatibility_recommendations(step_type, injection_type)
    }

    if compatibility_analysis.compatible do
      {:ok, compatibility_analysis}
    else
      {:error, {:incompatible_injection, compatibility_analysis}}
    end
  end

  defp check_injection_compatibility(step_type, injection_type) do
    # Check if injection type is compatible with step type
    compatibility_matrix = %{
      {:action, :parameter} => true,
      {:action, :context} => true,
      {:action, :metadata} => true,
      {:transform, :parameter} => true,
      {:transform, :context} => true,
      {:map, :context} => true,
      {:map, :metadata} => true,
      {:reduce, :context} => true
    }

    Map.get(compatibility_matrix, {step_type, injection_type}, false)
  end

  defp calculate_compatibility_score(step_config, prompt_injection_spec) do
    # Calculate compatibility score
    base_score = 0.7

    # Adjust based on step complexity
    complexity_adjustment = case Map.get(step_config, :complexity, :medium) do
      :low -> 0.2
      :medium -> 0.1
      :high -> 0.0
    end

    # Adjust based on injection requirements
    injection_adjustment = case Map.get(prompt_injection_spec, :injection_type) do
      :parameter -> 0.1
      :context -> 0.05
      :metadata -> 0.0
    end

    total_score = base_score + complexity_adjustment + injection_adjustment
    min(1.0, total_score)
  end

  defp generate_compatibility_recommendations(step_type, injection_type) do
    # Generate compatibility recommendations
    case {step_type, injection_type} do
      {:action, :parameter} ->
        ["Optimal compatibility - prompt will be available as step parameter"]

      {:action, :context} ->
        ["Good compatibility - prompt will be available in execution context"]

      {:transform, :parameter} ->
        ["Good compatibility - prompt can guide transformation logic"]

      {:map, :context} ->
        ["Suitable compatibility - prompt context will be available during mapping"]

      _ ->
        ["Consider alternative injection strategy for better compatibility"]
    end
  end

  defp generate_temporary_workflow_id do
    # Generate temporary workflow ID for injection
    timestamp = System.system_time(:nanosecond)
    "temp_workflow_#{timestamp}"
  end
end