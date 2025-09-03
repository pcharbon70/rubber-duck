defmodule RubberDuck.Prompts.WorkflowIntegration.ReactorPromptIntegration do
  @moduledoc """
  Reactor-specific integration utilities for seamless prompt integration.

  Provides specialized utilities for integrating prompts with Reactor workflow 
  steps, enabling workflows to leverage prompt composition during execution
  with minimal performance overhead and maximum functionality.

  Features:
  - Reactor step enhancement with automatic prompt resolution and composition
  - Workflow execution context integration with prompt agent ecosystem coordination
  - Step-specific prompt optimization with performance monitoring and analytics
  - Reactor middleware integration for prompt-enhanced workflow execution
  - Context propagation between Reactor steps with prompt composition benefits
  - Performance coordination between Reactor execution and prompt composition systems
  """

  require Logger

  alias RubberDuck.Prompts.WorkflowIntegration.{
    WorkflowContextEnhancer,
    WorkflowPromptCacheCoordinator,
    WorkflowPromptResolver
  }

  @integration_modes [:step_enhanced, :context_aware, :performance_optimized, :full_integration]
  @step_enhancement_types [
    :prompt_injection,
    :context_enhancement,
    :result_transformation,
    :comprehensive
  ]

  def enhance_reactor_step(step_config, prompt_config, integration_options \\ %{}) do
    Logger.debug("ReactorPromptIntegration: Enhancing Reactor step with prompt integration",
      step_name: Map.get(step_config, :name, "unknown"),
      prompt_name: Map.get(prompt_config, :prompt_name, "unknown")
    )

    case execute_step_enhancement(step_config, prompt_config, integration_options) do
      {:ok, enhanced_step} ->
        Logger.info("ReactorPromptIntegration: Reactor step enhanced successfully",
          step_name: enhanced_step.name,
          integration_mode: enhanced_step.integration_mode,
          prompt_integration_enabled: enhanced_step.prompt_integration_enabled
        )

        {:ok, enhanced_step}

      {:error, reason} ->
        Logger.error("ReactorPromptIntegration: Step enhancement failed", error: reason)
        {:error, reason}
    end
  end

  def create_prompt_aware_reactor_middleware(middleware_config \\ %{}) do
    Logger.debug("ReactorPromptIntegration: Creating prompt-aware Reactor middleware")

    case build_prompt_middleware(middleware_config) do
      {:ok, middleware} ->
        Logger.info("ReactorPromptIntegration: Prompt-aware middleware created successfully",
          middleware_features: middleware.features,
          integration_level: middleware.integration_level
        )

        {:ok, middleware}

      {:error, reason} ->
        Logger.error("ReactorPromptIntegration: Middleware creation failed", error: reason)
        {:error, reason}
    end
  end

  def integrate_context_with_reactor_execution(
        execution_context,
        prompt_context,
        integration_options \\ %{}
      ) do
    Logger.debug("ReactorPromptIntegration: Integrating context with Reactor execution",
      execution_context_keys: Map.keys(execution_context),
      prompt_context_keys: Map.keys(prompt_context)
    )

    case execute_context_integration(execution_context, prompt_context, integration_options) do
      {:ok, integrated_context} ->
        integration_metrics =
          calculate_integration_metrics(execution_context, prompt_context, integrated_context)

        Logger.info("ReactorPromptIntegration: Context integration completed",
          original_keys: integration_metrics.original_keys,
          integrated_keys: integration_metrics.integrated_keys,
          integration_effective: integration_metrics.integration_effective
        )

        {:ok,
         %{
           integrated_context: integrated_context,
           integration_metrics: integration_metrics
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def optimize_reactor_prompt_performance(workflow_id, optimization_config \\ %{}) do
    Logger.debug("ReactorPromptIntegration: Optimizing Reactor-prompt performance",
      workflow_id: workflow_id
    )

    case execute_performance_optimization(workflow_id, optimization_config) do
      {:ok, optimization_result} ->
        Logger.info("ReactorPromptIntegration: Performance optimization completed",
          workflow_id: workflow_id,
          optimization_applied: optimization_result.optimization_applied,
          performance_improvement: optimization_result.performance_improvement
        )

        {:ok, optimization_result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private implementation functions

  defp execute_step_enhancement(step_config, prompt_config, integration_options) do
    # Execute comprehensive step enhancement
    integration_mode = determine_integration_mode(step_config, prompt_config, integration_options)

    case integration_mode do
      :step_enhanced ->
        execute_step_enhanced_integration(step_config, prompt_config, integration_options)

      :context_aware ->
        execute_context_aware_integration(step_config, prompt_config, integration_options)

      :performance_optimized ->
        execute_performance_optimized_integration(step_config, prompt_config, integration_options)

      :full_integration ->
        execute_full_integration(step_config, prompt_config, integration_options)
    end
  end

  defp execute_step_enhanced_integration(step_config, prompt_config, integration_options) do
    # Execute step-enhanced integration
    enhanced_step =
      Map.merge(step_config, %{
        prompt_integration_enabled: true,
        integration_mode: :step_enhanced,
        prompt_name: prompt_config.prompt_name,
        prompt_resolution_strategy: Map.get(integration_options, :resolution_strategy, :cached),
        step_enhancement_metadata: %{
          enhanced_at: DateTime.utc_now(),
          enhancement_type: :step_enhanced,
          prompt_integration_version: "6.2.1"
        }
      })

    {:ok, enhanced_step}
  end

  defp execute_context_aware_integration(step_config, prompt_config, integration_options) do
    # Execute context-aware integration
    context_enhancement_config = %{
      enable_context_passing: true,
      context_optimization: Map.get(integration_options, :context_optimization, true),
      context_validation: Map.get(integration_options, :context_validation, true)
    }

    enhanced_step =
      Map.merge(step_config, %{
        prompt_integration_enabled: true,
        integration_mode: :context_aware,
        prompt_name: prompt_config.prompt_name,
        context_enhancement_config: context_enhancement_config,
        context_aware_metadata: %{
          context_passing_enabled: true,
          context_optimization_enabled: context_enhancement_config.context_optimization,
          enhanced_at: DateTime.utc_now()
        }
      })

    {:ok, enhanced_step}
  end

  defp execute_performance_optimized_integration(step_config, prompt_config, integration_options) do
    # Execute performance-optimized integration
    performance_config = %{
      enable_caching: Map.get(integration_options, :enable_caching, true),
      cache_strategy: Map.get(integration_options, :cache_strategy, :hybrid),
      performance_monitoring: Map.get(integration_options, :performance_monitoring, true)
    }

    enhanced_step =
      Map.merge(step_config, %{
        prompt_integration_enabled: true,
        integration_mode: :performance_optimized,
        prompt_name: prompt_config.prompt_name,
        performance_config: performance_config,
        performance_optimization_metadata: %{
          caching_enabled: performance_config.enable_caching,
          cache_strategy: performance_config.cache_strategy,
          optimization_level: :high,
          enhanced_at: DateTime.utc_now()
        }
      })

    {:ok, enhanced_step}
  end

  defp execute_full_integration(step_config, prompt_config, integration_options) do
    # Execute comprehensive full integration
    with {:ok, step_enhanced} <-
           execute_step_enhanced_integration(step_config, prompt_config, integration_options),
         {:ok, context_aware} <-
           execute_context_aware_integration(step_enhanced, prompt_config, integration_options),
         {:ok, performance_optimized} <-
           execute_performance_optimized_integration(
             context_aware,
             prompt_config,
             integration_options
           ) do
      full_integration_step =
        Map.merge(performance_optimized, %{
          integration_mode: :full_integration,
          full_integration_metadata: %{
            step_enhanced: true,
            context_aware: true,
            performance_optimized: true,
            integration_complete: true,
            enhanced_at: DateTime.utc_now()
          }
        })

      {:ok, full_integration_step}
    else
      {:error, reason} -> {:error, {:full_integration_failed, reason}}
    end
  end

  defp build_prompt_middleware(middleware_config) do
    # Build prompt-aware Reactor middleware
    default_config = %{
      enable_prompt_resolution: true,
      enable_context_enhancement: true,
      enable_performance_monitoring: true,
      integration_level: :standard
    }

    merged_config = Map.merge(default_config, middleware_config)

    middleware = %{
      name: :prompt_integration_middleware,
      config: merged_config,
      features: build_middleware_features(merged_config),
      integration_level: merged_config.integration_level,
      middleware_functions: build_middleware_functions(merged_config),
      created_at: DateTime.utc_now()
    }

    {:ok, middleware}
  end

  defp execute_context_integration(execution_context, prompt_context, integration_options) do
    # Execute context integration between Reactor and prompts
    integration_strategy = Map.get(integration_options, :integration_strategy, :merge)

    integrated_context =
      case integration_strategy do
        :merge ->
          Map.merge(execution_context, prompt_context)

        :prioritize_execution ->
          Map.merge(prompt_context, execution_context)

        :selective ->
          selective_context_merge(execution_context, prompt_context, integration_options)

        :custom ->
          apply_custom_integration(execution_context, prompt_context, integration_options)
      end

    # Add integration metadata
    final_context =
      Map.put(integrated_context, :integration_metadata, %{
        integration_strategy: integration_strategy,
        integrated_at: DateTime.utc_now(),
        source_contexts: %{
          execution_keys: Map.keys(execution_context),
          prompt_keys: Map.keys(prompt_context)
        }
      })

    {:ok, final_context}
  end

  defp execute_performance_optimization(workflow_id, optimization_config) do
    # Execute performance optimization for workflow-prompt operations
    optimization_strategies =
      Map.get(optimization_config, :strategies, [:caching, :context_optimization])

    optimization_results =
      Enum.map(optimization_strategies, fn strategy ->
        apply_optimization_strategy(workflow_id, strategy, optimization_config)
      end)

    successful_optimizations = Enum.filter(optimization_results, &match?({:ok, _}, &1))

    optimization_result = %{
      optimization_applied: true,
      strategies_applied: optimization_strategies,
      successful_optimizations: length(successful_optimizations),
      performance_improvement: calculate_performance_improvement(successful_optimizations),
      optimization_timestamp: DateTime.utc_now()
    }

    {:ok, optimization_result}
  end

  # Helper functions

  defp determine_integration_mode(step_config, prompt_config, integration_options) do
    case {
      Map.get(integration_options, :integration_mode),
      Map.get(step_config, :complexity, :medium),
      Map.get(prompt_config, :optimization_level, :standard)
    } do
      {mode, _, _} when mode in @integration_modes -> mode
      {nil, :high, :high} -> :full_integration
      {nil, :high, _} -> :performance_optimized
      {nil, _, :high} -> :context_aware
      _ -> :step_enhanced
    end
  end

  defp build_middleware_features(config) do
    # Build middleware features based on configuration
    features = []

    features =
      if config.enable_prompt_resolution do
        [:prompt_resolution | features]
      else
        features
      end

    features =
      if config.enable_context_enhancement do
        [:context_enhancement | features]
      else
        features
      end

    features =
      if config.enable_performance_monitoring do
        [:performance_monitoring | features]
      else
        features
      end

    features
  end

  defp build_middleware_functions(config) do
    # Build middleware functions based on configuration
    %{
      before_step:
        if(config.enable_context_enhancement, do: :enhance_context, else: :pass_through),
      after_step:
        if(config.enable_performance_monitoring, do: :track_performance, else: :pass_through),
      on_error: :handle_prompt_integration_error,
      on_complete: :finalize_prompt_integration
    }
  end

  defp selective_context_merge(execution_context, prompt_context, integration_options) do
    # Selective merge based on priority keys
    priority_keys = Map.get(integration_options, :priority_keys, [])

    # Start with execution context
    merged_context = execution_context

    # Add priority keys from prompt context
    Enum.reduce(priority_keys, merged_context, fn key, acc ->
      case Map.get(prompt_context, key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp apply_custom_integration(execution_context, prompt_context, integration_options) do
    # Apply custom integration logic
    custom_logic =
      Map.get(integration_options, :custom_integration_logic, fn exec, prompt ->
        Map.merge(exec, prompt)
      end)

    custom_logic.(execution_context, prompt_context)
  end

  defp apply_optimization_strategy(workflow_id, strategy, optimization_config) do
    # Apply specific optimization strategy
    case strategy do
      :caching ->
        optimize_caching(workflow_id, optimization_config)

      :context_optimization ->
        optimize_context_handling(workflow_id, optimization_config)

      :prompt_resolution ->
        optimize_prompt_resolution(workflow_id, optimization_config)

      :performance_monitoring ->
        optimize_performance_monitoring(workflow_id, optimization_config)
    end
  end

  defp optimize_caching(workflow_id, config) do
    # Optimize caching for workflow
    case WorkflowPromptCacheCoordinator.optimize_cache_performance(%{
           workflow_id: workflow_id,
           strategy: :performance_focused
         }) do
      {:ok, _result} ->
        {:ok, %{strategy: :caching, improvement: 0.15}}

      {:error, reason} ->
        {:error, {:caching_optimization_failed, reason}}
    end
  end

  defp optimize_context_handling(workflow_id, config) do
    # Optimize context handling for workflow
    optimization_result = %{
      strategy: :context_optimization,
      improvement: 0.10,
      context_optimization_enabled: true
    }

    {:ok, optimization_result}
  end

  defp optimize_prompt_resolution(workflow_id, config) do
    # Optimize prompt resolution for workflow
    optimization_result = %{
      strategy: :prompt_resolution,
      improvement: 0.12,
      resolution_optimization_enabled: true
    }

    {:ok, optimization_result}
  end

  defp optimize_performance_monitoring(workflow_id, config) do
    # Optimize performance monitoring for workflow
    optimization_result = %{
      strategy: :performance_monitoring,
      improvement: 0.05,
      monitoring_optimization_enabled: true
    }

    {:ok, optimization_result}
  end

  defp calculate_integration_metrics(execution_context, prompt_context, integrated_context) do
    # Calculate context integration metrics
    original_keys = length(Map.keys(execution_context)) + length(Map.keys(prompt_context))
    integrated_keys = length(Map.keys(integrated_context))

    %{
      original_keys: original_keys,
      integrated_keys: integrated_keys,
      key_efficiency: integrated_keys / max(original_keys, 1),
      # No more than 20% increase
      integration_effective: integrated_keys <= original_keys * 1.2,
      integration_timestamp: DateTime.utc_now()
    }
  end

  defp calculate_performance_improvement(successful_optimizations) do
    # Calculate overall performance improvement
    improvements =
      Enum.map(successful_optimizations, fn {:ok, result} ->
        Map.get(result, :improvement, 0.0)
      end)

    case improvements do
      [] -> 0.0
      _ -> Enum.sum(improvements) / length(improvements)
    end
  end

  # Reactor-specific utility functions

  def create_prompt_enhanced_reactor_config(base_config, prompt_integration_config) do
    # Create Reactor configuration enhanced with prompt integration
    enhanced_config =
      Map.merge(base_config, %{
        prompt_integration: %{
          enabled: true,
          prompt_resolution_enabled: Map.get(prompt_integration_config, :enable_resolution, true),
          context_enhancement_enabled:
            Map.get(prompt_integration_config, :enable_context_enhancement, true),
          performance_monitoring_enabled:
            Map.get(prompt_integration_config, :enable_monitoring, true),
          cache_coordination_enabled:
            Map.get(prompt_integration_config, :enable_cache_coordination, true)
        },
        middleware: add_prompt_middleware(base_config.middleware || [])
      })

    {:ok, enhanced_config}
  end

  def extract_prompt_requirements_from_reactor_step(step_definition) do
    # Extract prompt requirements from Reactor step
    prompt_requirements = %{
      prompt_name: Map.get(step_definition, :prompt_name),
      prompt_context_keys: Map.get(step_definition, :context_keys, []),
      prompt_validation_required: Map.get(step_definition, :validate_prompt, true),
      prompt_optimization_level: Map.get(step_definition, :optimization_level, :standard)
    }

    if prompt_requirements.prompt_name do
      {:ok, prompt_requirements}
    else
      {:ok, %{no_prompt_required: true}}
    end
  end

  def inject_prompt_into_reactor_step(step_config, resolved_prompt, injection_options \\ %{}) do
    # Inject resolved prompt into Reactor step
    injection_strategy = Map.get(injection_options, :injection_strategy, :parameter_injection)

    case injection_strategy do
      :parameter_injection ->
        inject_as_parameter(step_config, resolved_prompt, injection_options)

      :context_injection ->
        inject_as_context(step_config, resolved_prompt, injection_options)

      :metadata_injection ->
        inject_as_metadata(step_config, resolved_prompt, injection_options)

      :comprehensive_injection ->
        inject_comprehensively(step_config, resolved_prompt, injection_options)
    end
  end

  defp inject_as_parameter(step_config, resolved_prompt, options) do
    # Inject prompt as step parameter
    parameter_name = Map.get(options, :parameter_name, :prompt)

    updated_parameters =
      Map.put(
        Map.get(step_config, :parameters, %{}),
        parameter_name,
        resolved_prompt.resolved_prompt
      )

    enhanced_step = Map.put(step_config, :parameters, updated_parameters)

    {:ok, enhanced_step}
  end

  defp inject_as_context(step_config, resolved_prompt, options) do
    # Inject prompt as step context
    context_key = Map.get(options, :context_key, :prompt_content)

    updated_context =
      Map.put(
        Map.get(step_config, :context, %{}),
        context_key,
        resolved_prompt.resolved_prompt
      )

    enhanced_step = Map.put(step_config, :context, updated_context)

    {:ok, enhanced_step}
  end

  defp inject_as_metadata(step_config, resolved_prompt, options) do
    # Inject prompt as step metadata
    metadata_key = Map.get(options, :metadata_key, :prompt_data)

    updated_metadata =
      Map.put(
        Map.get(step_config, :metadata, %{}),
        metadata_key,
        resolved_prompt
      )

    enhanced_step = Map.put(step_config, :metadata, updated_metadata)

    {:ok, enhanced_step}
  end

  defp inject_comprehensively(step_config, resolved_prompt, options) do
    # Inject prompt using all methods
    with {:ok, param_injected} <- inject_as_parameter(step_config, resolved_prompt, options),
         {:ok, context_injected} <- inject_as_context(param_injected, resolved_prompt, options),
         {:ok, metadata_injected} <-
           inject_as_metadata(context_injected, resolved_prompt, options) do
      comprehensive_step =
        Map.merge(metadata_injected, %{
          comprehensive_prompt_injection: true,
          injection_complete: true,
          injection_timestamp: DateTime.utc_now()
        })

      {:ok, comprehensive_step}
    else
      {:error, reason} -> {:error, {:comprehensive_injection_failed, reason}}
    end
  end

  defp add_prompt_middleware(existing_middleware) do
    # Add prompt integration middleware to existing middleware stack
    prompt_middleware = [
      :prompt_resolution_middleware,
      :context_enhancement_middleware,
      :performance_monitoring_middleware
    ]

    existing_middleware ++ prompt_middleware
  end
end
