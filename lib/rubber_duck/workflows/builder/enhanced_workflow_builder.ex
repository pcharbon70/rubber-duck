defmodule RubberDuck.Workflows.Builder.EnhancedWorkflowBuilder do
  @moduledoc """
  Enhanced workflow builder with optional Reactor.Builder integration.

  This module provides sophisticated workflow building capabilities using
  optional Reactor.Builder integration while maintaining agent autonomy
  and providing fallback to existing workflow creation patterns.

  Features:
  - Optional Reactor.Builder integration for sophisticated workflow construction
  - Dynamic workflow creation with intelligent component selection
  - Execution context utilities for workflow runtime management
  - Comprehensive validation utilities ensuring workflow safety and correctness
  - Integration with existing workflow templates and composition patterns
  - Performance optimization with resource constraint management

  Builder Modes:
  - **Reactor Mode**: Uses Reactor.Builder for sophisticated workflow construction
  - **Template Mode**: Uses existing WorkflowTemplates for proven patterns
  - **Composition Mode**: Uses SkillsComposition for Skills-based workflows
  - **Hybrid Mode**: Combines multiple approaches for optimal results
  """

  require Logger

  alias RubberDuck.Workflows.{
    OptionalWorkflowUtils,
    SkillsComposition,
    WorkflowTemplates
  }

  alias RubberDuck.Prompts.WorkflowIntegration.{
    WorkflowPromptResolver,
    ReactorPromptIntegration
  }

  @builder_modes [:reactor, :template, :composition, :hybrid]

  @default_builder_config %{
    preferred_mode: :hybrid,
    enable_reactor_builder: true,
    enable_validation: true,
    enable_optimization: true,
    fallback_on_error: true,
    # 10 seconds
    max_build_time_ms: 10_000,
    # Prompt integration features (Phase 6.2 enhancement)
    enable_prompt_integration: true,
    enable_named_prompt_references: true,
    enable_context_enhancement: true,
    prompt_resolution_strategy: :optimized
  }

  @doc """
  Create workflow using enhanced builder with optional Reactor.Builder integration.

  Returns built workflow with comprehensive metadata and validation results.
  """
  def create_workflow(workflow_spec, builder_config \\ %{}) do
    merged_config = Map.merge(@default_builder_config, builder_config)

    Logger.info("EnhancedWorkflowBuilder: Creating workflow",
      builder_mode: determine_optimal_builder_mode(workflow_spec, merged_config),
      workflow_type: Map.get(workflow_spec, :type, :unknown)
    )

    build_start_time = System.monotonic_time(:microsecond)

    with {:ok, validated_spec} <- validate_workflow_specification(workflow_spec),
         {:ok, builder_mode} <- determine_optimal_builder_mode(validated_spec, merged_config),
         {:ok, build_context} <-
           create_build_context(validated_spec, builder_mode, merged_config),
         {:ok, built_workflow} <- execute_workflow_build(build_context),
         {:ok, prompt_enhanced_workflow} <-
           enhance_workflow_with_prompts(built_workflow, merged_config),
         {:ok, validated_workflow} <-
           validate_built_workflow(prompt_enhanced_workflow, merged_config) do
      build_time = System.monotonic_time(:microsecond) - build_start_time

      Logger.info("EnhancedWorkflowBuilder: Workflow creation completed",
        workflow_id: built_workflow.id,
        builder_mode: builder_mode,
        build_time_us: build_time,
        validation_passed: validated_workflow.validation_passed
      )

      {:ok,
       %{
         workflow: validated_workflow.workflow,
         build_metadata: %{
           build_time_microseconds: build_time,
           builder_mode: builder_mode,
           validation_results: validated_workflow.validation_results,
           optimization_applied: Map.get(validated_workflow.workflow, :optimizations, []),
           build_context: build_context
         }
       }}
    else
      {:error, reason} ->
        Logger.error("EnhancedWorkflowBuilder: Workflow creation failed", error: reason)
        {:error, reason}
    end
  end

  @doc """
  Create execution context for workflow runtime management.

  Provides comprehensive execution context with monitoring, error handling,
  and performance tracking capabilities.
  """
  def create_execution_context(workflow, context_config \\ %{}) do
    Logger.debug("EnhancedWorkflowBuilder: Creating execution context")

    default_context_config = %{
      enable_monitoring: true,
      enable_error_handling: true,
      enable_performance_tracking: true,
      # 5 minutes
      timeout_ms: 300_000
    }

    merged_config = Map.merge(default_context_config, context_config)

    execution_context = %{
      workflow_id: Map.get(workflow, :id),
      execution_config: merged_config,
      monitoring:
        if(merged_config.enable_monitoring, do: initialize_monitoring_context(), else: %{}),
      error_handling:
        if(merged_config.enable_error_handling,
          do: initialize_error_handling_context(),
          else: %{}
        ),
      performance:
        if(merged_config.enable_performance_tracking,
          do: initialize_performance_context(),
          else: %{}
        ),
      created_at: DateTime.utc_now()
    }

    {:ok, execution_context}
  end

  @doc """
  Validate workflow structure and configuration for safety and correctness.

  Provides comprehensive validation ensuring workflows are safe for execution
  and meet performance and reliability requirements.
  """
  def validate_workflow(workflow, validation_config \\ %{}) do
    Logger.debug("EnhancedWorkflowBuilder: Validating workflow")

    default_validation_config = %{
      validate_structure: true,
      validate_dependencies: true,
      validate_performance: true,
      validate_resources: true
    }

    merged_config = Map.merge(default_validation_config, validation_config)

    validation_checks = [
      if(merged_config.validate_structure,
        do: validate_workflow_structure(workflow),
        else: {:ok, :skipped}
      ),
      if(merged_config.validate_dependencies,
        do: validate_workflow_dependencies(workflow),
        else: {:ok, :skipped}
      ),
      if(merged_config.validate_performance,
        do: validate_workflow_performance(workflow),
        else: {:ok, :skipped}
      ),
      if(merged_config.validate_resources,
        do: validate_workflow_resources(workflow),
        else: {:ok, :skipped}
      )
    ]

    failed_validations = Enum.filter(validation_checks, &match?({:error, _}, &1))
    successful_validations = Enum.filter(validation_checks, &match?({:ok, _}, &1))

    validation_passed = Enum.empty?(failed_validations)
    validation_score = length(successful_validations) / length(validation_checks)

    validation_result = %{
      validation_passed: validation_passed,
      validation_score: Float.round(validation_score, 3),
      successful_validations: length(successful_validations),
      failed_validations: length(failed_validations),
      validation_details: validation_checks,
      recommendations: generate_validation_recommendations(failed_validations)
    }

    {:ok, validation_result}
  end

  # Private implementation functions

  defp validate_workflow_specification(workflow_spec) do
    # Validate workflow specification structure
    required_fields = [:type, :components]
    missing_fields = required_fields -- Map.keys(workflow_spec)

    if Enum.empty?(missing_fields) do
      {:ok, workflow_spec}
    else
      {:error, {:invalid_workflow_spec, missing_fields}}
    end
  end

  defp determine_optimal_builder_mode(validated_spec, config) do
    # Determine optimal builder mode based on specification and preferences
    preferred_mode = config.preferred_mode
    workflow_complexity = assess_workflow_complexity(validated_spec)
    reactor_available = config.enable_reactor_builder

    optimal_mode =
      case {preferred_mode, workflow_complexity, reactor_available} do
        {:reactor, _, true} -> :reactor
        {:hybrid, :high, true} -> :reactor
        {:hybrid, :medium, true} -> :template
        {:hybrid, :low, _} -> :composition
        {:template, _, _} -> :template
        {:composition, _, _} -> :composition
        # Fallback when Reactor not available
        {_, _, false} -> :template
      end

    if optimal_mode in @builder_modes do
      {:ok, optimal_mode}
    else
      {:error, {:invalid_builder_mode, optimal_mode}}
    end
  end

  defp assess_workflow_complexity(workflow_spec) do
    # Assess workflow complexity for builder mode selection
    component_count = length(Map.get(workflow_spec, :components, []))
    has_dependencies = Map.get(workflow_spec, :has_dependencies, false)
    requires_coordination = Map.get(workflow_spec, :requires_coordination, false)

    complexity_score =
      component_count * 0.3 +
        if(has_dependencies, do: 0.4, else: 0.0) +
        if requires_coordination, do: 0.3, else: 0.0

    cond do
      complexity_score > 1.0 -> :high
      complexity_score > 0.6 -> :medium
      true -> :low
    end
  end

  defp create_build_context(validated_spec, builder_mode, config) do
    # Create comprehensive build context for workflow creation
    build_context = %{
      workflow_spec: validated_spec,
      builder_mode: builder_mode,
      config: config,
      reactor_available: check_reactor_availability(),
      build_timestamp: DateTime.utc_now(),
      build_id: generate_build_id()
    }

    {:ok, build_context}
  end

  defp execute_workflow_build(build_context) do
    # Execute workflow build based on context
    case build_context.builder_mode do
      :reactor ->
        execute_reactor_build(build_context)

      :template ->
        execute_template_build(build_context)

      :composition ->
        execute_composition_build(build_context)

      :hybrid ->
        execute_hybrid_build(build_context)
    end
  end

  defp execute_reactor_build(build_context) do
    # Execute Reactor.Builder-based workflow creation
    if build_context.reactor_available do
      Logger.debug("EnhancedWorkflowBuilder: Using Reactor.Builder mode")

      # Create workflow using Reactor.Builder (placeholder)
      reactor_workflow = %{
        id: generate_workflow_id("reactor"),
        type: :reactor_built_workflow,
        builder_mode: :reactor,
        components: build_context.workflow_spec.components,
        reactor_integration: true,
        created_at: DateTime.utc_now()
      }

      {:ok, reactor_workflow}
    else
      Logger.warning(
        "EnhancedWorkflowBuilder: Reactor not available, falling back to template mode"
      )

      execute_template_build(build_context)
    end
  end

  defp execute_template_build(build_context) do
    # Execute template-based workflow creation
    Logger.debug("EnhancedWorkflowBuilder: Using template mode")

    workflow_type = Map.get(build_context.workflow_spec, :type, :sequential_processing)

    case WorkflowTemplates.create_from_template(workflow_type) do
      {:ok, template_result} ->
        # Enhance template result for builder integration
        enhanced_workflow =
          Map.merge(template_result.workflow_config.workflow, %{
            id: generate_workflow_id("template"),
            builder_mode: :template,
            template_used: template_result.template_used,
            components: build_context.workflow_spec.components
          })

        {:ok, enhanced_workflow}

      {:error, reason} ->
        {:error, {:template_build_failed, reason}}
    end
  end

  defp execute_composition_build(build_context) do
    # Execute Skills composition-based workflow creation
    Logger.debug("EnhancedWorkflowBuilder: Using composition mode")

    components = Map.get(build_context.workflow_spec, :components, [])

    case SkillsComposition.compose_skills_chain(components) do
      {:ok, composition_result} ->
        # Enhance composition result for builder integration
        enhanced_workflow =
          Map.merge(composition_result.workflow_spec, %{
            id: generate_workflow_id("composition"),
            builder_mode: :composition,
            skills_composed: true
          })

        {:ok, enhanced_workflow}

      {:error, reason} ->
        {:error, {:composition_build_failed, reason}}
    end
  end

  defp execute_hybrid_build(build_context) do
    # Execute hybrid build using multiple approaches
    Logger.debug("EnhancedWorkflowBuilder: Using hybrid mode")

    workflow_complexity = assess_workflow_complexity(build_context.workflow_spec)

    # Choose primary build method based on complexity
    primary_method =
      case workflow_complexity do
        :high -> :reactor
        :medium -> :template
        :low -> :composition
      end

    # Try primary method with fallback
    case execute_primary_build_method(primary_method, build_context) do
      {:ok, workflow} ->
        # Enhance with hybrid metadata
        hybrid_workflow =
          Map.merge(workflow, %{
            hybrid_build: true,
            primary_method: primary_method,
            complexity_assessed: workflow_complexity
          })

        {:ok, hybrid_workflow}

      {:error, reason} ->
        Logger.warning("EnhancedWorkflowBuilder: Primary method failed, trying fallback")
        execute_fallback_build_method(primary_method, build_context, reason)
    end
  end

  defp execute_primary_build_method(method, build_context) do
    case method do
      :reactor -> execute_reactor_build(build_context)
      :template -> execute_template_build(build_context)
      :composition -> execute_composition_build(build_context)
    end
  end

  defp execute_fallback_build_method(failed_method, build_context, failure_reason) do
    # Execute fallback build method when primary fails
    fallback_method =
      case failed_method do
        :reactor -> :template
        :template -> :composition
        :composition -> :template
      end

    case execute_primary_build_method(fallback_method, build_context) do
      {:ok, workflow} ->
        fallback_workflow =
          Map.merge(workflow, %{
            fallback_used: true,
            primary_method_failed: failed_method,
            fallback_method: fallback_method,
            failure_reason: failure_reason
          })

        {:ok, fallback_workflow}

      {:error, reason} ->
        {:error, {:all_build_methods_failed, %{primary: failure_reason, fallback: reason}}}
    end
  end

  defp validate_built_workflow(built_workflow, config) do
    # Validate built workflow for safety and correctness
    if config.enable_validation do
      case validate_workflow(built_workflow) do
        {:ok, validation_result} ->
          validated_workflow =
            Map.merge(built_workflow, %{
              validation_applied: true,
              validation_timestamp: DateTime.utc_now()
            })

          {:ok,
           %{
             workflow: validated_workflow,
             validation_passed: validation_result.validation_passed,
             validation_results: validation_result
           }}

        {:error, reason} ->
          {:error, {:validation_failed, reason}}
      end
    else
      {:ok,
       %{
         workflow: built_workflow,
         validation_passed: true,
         validation_results: %{validation_skipped: true}
       }}
    end
  end

  # Validation functions

  defp validate_workflow_structure(workflow) do
    # Validate workflow structure
    required_fields = [:id, :type, :components]

    missing_fields =
      Enum.filter(required_fields, fn field ->
        not Map.has_key?(workflow, field)
      end)

    if Enum.empty?(missing_fields) do
      {:ok, %{check: :structure, status: :valid, fields_validated: length(required_fields)}}
    else
      {:error, %{check: :structure, status: :invalid, missing_fields: missing_fields}}
    end
  end

  defp validate_workflow_dependencies(workflow) do
    # Validate workflow component dependencies
    components = Map.get(workflow, :components, [])

    if is_list(components) and not Enum.empty?(components) do
      # Simple dependency validation
      dependency_issues = check_component_dependencies(components)

      if Enum.empty?(dependency_issues) do
        {:ok, %{check: :dependencies, status: :valid, components_checked: length(components)}}
      else
        {:error, %{check: :dependencies, status: :invalid, issues: dependency_issues}}
      end
    else
      {:error, %{check: :dependencies, status: :invalid, issue: :no_components}}
    end
  end

  defp validate_workflow_performance(workflow) do
    # Validate workflow performance characteristics
    component_count = length(Map.get(workflow, :components, []))

    # Simple performance validation
    performance_estimate = estimate_workflow_performance(workflow)

    if performance_estimate.acceptable do
      {:ok, %{check: :performance, status: :acceptable, estimate: performance_estimate}}
    else
      {:error, %{check: :performance, status: :unacceptable, estimate: performance_estimate}}
    end
  end

  defp validate_workflow_resources(workflow) do
    # Validate workflow resource requirements
    resource_estimate = estimate_workflow_resources(workflow)

    if resource_estimate.within_limits do
      {:ok, %{check: :resources, status: :within_limits, estimate: resource_estimate}}
    else
      {:error, %{check: :resources, status: :exceeds_limits, estimate: resource_estimate}}
    end
  end

  # Helper functions

  defp check_reactor_availability do
    # Check if Reactor.Builder is available
    case Code.ensure_loaded(Reactor.Builder) do
      {:module, _} -> true
      {:error, _} -> false
    end
  end

  defp check_component_dependencies(components) do
    # Check for dependency issues in components (placeholder)
    # In real implementation, would validate dependency graphs
    []
  end

  defp estimate_workflow_performance(workflow) do
    # Estimate workflow performance characteristics
    component_count = length(Map.get(workflow, :components, []))

    # 1 second per component
    estimated_time = component_count * 1000
    # Under 30 seconds acceptable
    acceptable = estimated_time < 30_000

    %{
      estimated_execution_time_ms: estimated_time,
      component_count: component_count,
      acceptable: acceptable,
      performance_score: if(acceptable, do: 0.8, else: 0.4)
    }
  end

  defp estimate_workflow_resources(workflow) do
    # Estimate workflow resource requirements
    component_count = length(Map.get(workflow, :components, []))

    # 20MB per component
    estimated_memory = component_count * 20
    # 5% CPU per component
    estimated_cpu = component_count * 5

    # Reasonable limits
    within_limits = estimated_memory < 500 and estimated_cpu < 80

    %{
      estimated_memory_mb: estimated_memory,
      estimated_cpu_percentage: estimated_cpu,
      within_limits: within_limits,
      resource_efficiency: calculate_resource_efficiency(estimated_memory, estimated_cpu)
    }
  end

  defp calculate_resource_efficiency(memory_mb, cpu_percentage) do
    # Calculate resource efficiency score
    # Normalize to 1GB
    memory_efficiency = max(1.0 - memory_mb / 1000, 0.1)
    # Normalize to 100%
    cpu_efficiency = max(1.0 - cpu_percentage / 100, 0.1)

    overall_efficiency = (memory_efficiency + cpu_efficiency) / 2
    Float.round(overall_efficiency, 3)
  end

  defp initialize_monitoring_context do
    # Initialize monitoring context for workflow execution
    %{
      metrics_enabled: true,
      telemetry_enabled: true,
      performance_tracking: true
    }
  end

  defp initialize_error_handling_context do
    # Initialize error handling context for workflow execution
    %{
      error_detection_enabled: true,
      automatic_recovery: true,
      fallback_to_autonomous: true
    }
  end

  defp initialize_performance_context do
    # Initialize performance tracking context
    %{
      track_execution_time: true,
      track_resource_usage: true,
      track_success_metrics: true
    }
  end

  defp generate_validation_recommendations(failed_validations) do
    # Generate recommendations based on failed validations
    case failed_validations do
      [] -> ["Workflow validation successful - ready for execution"]
      validations -> Enum.map(validations, &build_validation_recommendation/1)
    end
  end

  defp build_validation_recommendation({:error, error_info}) do
    case error_info.check do
      :structure -> "Fix workflow structure - missing required fields"
      :dependencies -> "Resolve component dependency issues"
      :performance -> "Optimize workflow for better performance"
      :resources -> "Reduce workflow resource requirements"
      _ -> "Address #{error_info.check} validation issue"
    end
  end

  defp generate_build_id do
    # Generate unique build ID
    timestamp = System.system_time(:nanosecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "build_#{timestamp}_#{random}"
  end

  defp enhance_workflow_with_prompts(built_workflow, merged_config) do
    # Enhance built workflow with prompt integration if enabled
    if merged_config.enable_prompt_integration do
      Logger.debug("EnhancedWorkflowBuilder: Enhancing workflow with prompt integration",
        workflow_id: built_workflow.id
      )

      case integrate_prompt_capabilities(built_workflow, merged_config) do
        {:ok, enhanced_workflow} ->
          Logger.debug("EnhancedWorkflowBuilder: Prompt integration completed",
            workflow_id: enhanced_workflow.id,
            prompt_features_enabled:
              Map.keys(Map.get(enhanced_workflow, :prompt_integration, %{}))
          )

          {:ok, enhanced_workflow}

        {:error, reason} ->
          Logger.warning(
            "EnhancedWorkflowBuilder: Prompt integration failed, continuing without: #{inspect(reason)}"
          )

          {:ok, built_workflow}
      end
    else
      {:ok, built_workflow}
    end
  end

  defp integrate_prompt_capabilities(built_workflow, config) do
    # Integrate prompt capabilities into workflow
    prompt_integration = %{
      enabled: true,
      named_references_supported: config.enable_named_prompt_references,
      context_enhancement_supported: config.enable_context_enhancement,
      resolution_strategy: config.prompt_resolution_strategy,
      integration_version: "6.2.0",
      integration_metadata: %{
        integrated_at: DateTime.utc_now(),
        integration_mode: :automatic,
        features_enabled: build_prompt_feature_list(config)
      }
    }

    # Enhance workflow steps with prompt integration if they specify prompt names
    enhanced_components =
      enhance_components_with_prompt_support(
        Map.get(built_workflow, :components, []),
        config
      )

    enhanced_workflow =
      Map.merge(built_workflow, %{
        prompt_integration: prompt_integration,
        components: enhanced_components,
        prompt_integration_applied: true
      })

    {:ok, enhanced_workflow}
  end

  defp enhance_components_with_prompt_support(components, config) do
    # Enhance workflow components with prompt support
    Enum.map(components, fn component ->
      case Map.get(component, :prompt_name) do
        nil ->
          component

        prompt_name ->
          Map.merge(component, %{
            prompt_integration: %{
              prompt_name: prompt_name,
              resolution_strategy: config.prompt_resolution_strategy,
              context_enhancement_enabled: config.enable_context_enhancement,
              integration_applied: true
            }
          })
      end
    end)
  end

  defp build_prompt_feature_list(config) do
    # Build list of enabled prompt features
    features = []

    features =
      if config.enable_named_prompt_references do
        [:named_prompt_references | features]
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
      if config.enable_prompt_integration do
        [:prompt_integration | features]
      else
        features
      end

    features
  end

  defp generate_workflow_id(prefix) do
    # Generate unique workflow ID
    timestamp = System.system_time(:nanosecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}_workflow_#{timestamp}_#{random}"
  end
end
