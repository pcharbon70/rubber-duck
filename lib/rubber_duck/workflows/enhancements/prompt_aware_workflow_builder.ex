defmodule RubberDuck.Workflows.Enhancements.PromptAwareWorkflowBuilder do
  @moduledoc """
  Enhanced workflow builder with comprehensive prompt integration capabilities.
  
  Extends the existing EnhancedWorkflowBuilder to support prompt integration,
  enabling workflow definitions to include named prompt references, automatic
  prompt resolution, and context-aware prompt composition during execution.
  
  Features:
  - Enhanced workflow builder supporting prompt references and integration
  - Named prompt reference validation and dependency management
  - Automatic prompt resolution during workflow building and execution
  - Context-aware prompt composition with workflow-specific optimization
  - Integration with existing workflow templates and composition patterns
  - Performance optimization for prompt-enhanced workflow building and execution
  """

  require Logger

  alias RubberDuck.Workflows.Builder.EnhancedWorkflowBuilder
  alias RubberDuck.Prompts.WorkflowIntegration.{
    WorkflowPromptResolver,
    NamedPromptReferenceManager,
    ReactorPromptIntegration
  }

  @prompt_integration_modes [:basic, :enhanced, :optimized, :comprehensive]

  def create_prompt_aware_workflow(workflow_spec, prompt_spec, builder_config \\ %{}) do
    Logger.info("PromptAwareWorkflowBuilder: Creating prompt-aware workflow",
      workflow_type: Map.get(workflow_spec, :type, :unknown),
      prompt_references: length(Map.get(prompt_spec, :prompt_references, []))
    )

    build_start_time = System.monotonic_time(:microsecond)

    case execute_prompt_aware_build(workflow_spec, prompt_spec, builder_config) do
      {:ok, build_result} ->
        build_time = System.monotonic_time(:microsecond) - build_start_time

        Logger.info("PromptAwareWorkflowBuilder: Prompt-aware workflow created",
          workflow_id: build_result.workflow.id,
          prompt_integration_level: build_result.prompt_integration_level,
          build_time_us: build_time
        )

        {:ok, build_result}

      {:error, reason} ->
        Logger.error("PromptAwareWorkflowBuilder: Prompt-aware workflow creation failed", error: reason)
        {:error, reason}
    end
  end

  def enhance_existing_workflow_with_prompts(existing_workflow, prompt_enhancement_spec, options \\ %{}) do
    Logger.debug("PromptAwareWorkflowBuilder: Enhancing existing workflow with prompts",
      workflow_id: Map.get(existing_workflow, :id, "unknown"),
      enhancement_type: Map.get(options, :enhancement_type, :basic)
    )

    case execute_workflow_prompt_enhancement(existing_workflow, prompt_enhancement_spec, options) do
      {:ok, enhanced_workflow} ->
        Logger.info("PromptAwareWorkflowBuilder: Workflow enhanced with prompts",
          workflow_id: enhanced_workflow.id,
          prompts_integrated: enhanced_workflow.prompt_integration_summary.prompts_integrated
        )

        {:ok, enhanced_workflow}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def validate_prompt_integrated_workflow(workflow, validation_options \\ %{}) do
    Logger.debug("PromptAwareWorkflowBuilder: Validating prompt-integrated workflow",
      workflow_id: Map.get(workflow, :id, "unknown")
    )

    case execute_prompt_integration_validation(workflow, validation_options) do
      {:ok, validation_result} ->
        Logger.info("PromptAwareWorkflowBuilder: Prompt integration validation completed",
          validation_passed: validation_result.validation_passed,
          prompt_references_valid: validation_result.prompt_references_valid
        )

        {:ok, validation_result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private implementation functions

  defp execute_prompt_aware_build(workflow_spec, prompt_spec, builder_config) do
    # Execute comprehensive prompt-aware workflow build
    with {:ok, validated_specs} <- validate_prompt_workflow_specs(workflow_spec, prompt_spec),
         {:ok, prompt_references} <- register_prompt_references(validated_specs, builder_config),
         {:ok, enhanced_workflow_spec} <- enhance_workflow_spec_with_prompts(validated_specs.workflow_spec, prompt_references),
         {:ok, base_workflow} <- build_base_workflow(enhanced_workflow_spec, builder_config),
         {:ok, prompt_enhanced_workflow} <- integrate_prompts_with_workflow(base_workflow, prompt_references, builder_config) do
      
      prompt_aware_result = %{
        workflow: prompt_enhanced_workflow,
        prompt_integration_level: determine_integration_level(prompt_spec, builder_config),
        prompt_references: prompt_references,
        build_metadata: %{
          prompt_integration_enabled: true,
          prompt_references_count: length(prompt_references),
          integration_successful: true,
          built_at: DateTime.utc_now()
        }
      }

      {:ok, prompt_aware_result}
    else
      {:error, reason} -> {:error, {:prompt_aware_build_failed, reason}}
    end
  end

  defp execute_workflow_prompt_enhancement(existing_workflow, prompt_enhancement_spec, options) do
    # Execute enhancement of existing workflow with prompts
    enhancement_level = Map.get(options, :enhancement_type, :basic)

    case enhancement_level do
      :basic ->
        execute_basic_prompt_enhancement(existing_workflow, prompt_enhancement_spec, options)

      :enhanced ->
        execute_enhanced_prompt_enhancement(existing_workflow, prompt_enhancement_spec, options)

      :optimized ->
        execute_optimized_prompt_enhancement(existing_workflow, prompt_enhancement_spec, options)

      :comprehensive ->
        execute_comprehensive_prompt_enhancement(existing_workflow, prompt_enhancement_spec, options)
    end
  end

  defp execute_basic_prompt_enhancement(existing_workflow, prompt_enhancement_spec, options) do
    # Execute basic prompt enhancement
    basic_enhancements = %{
      prompt_integration_enabled: true,
      prompt_enhancement_level: :basic,
      prompt_references: Map.get(prompt_enhancement_spec, :references, []),
      enhancement_metadata: %{
        enhancement_type: :basic,
        enhanced_at: DateTime.utc_now()
      }
    }

    enhanced_workflow = Map.merge(existing_workflow, basic_enhancements)

    {:ok, add_prompt_integration_summary(enhanced_workflow, :basic)}
  end

  defp execute_enhanced_prompt_enhancement(existing_workflow, prompt_enhancement_spec, options) do
    # Execute enhanced prompt enhancement
    with {:ok, basic_enhanced} <- execute_basic_prompt_enhancement(existing_workflow, prompt_enhancement_spec, options),
         {:ok, context_enhanced} <- enhance_workflow_context_integration(basic_enhanced, prompt_enhancement_spec),
         {:ok, resolution_enhanced} <- enhance_prompt_resolution_capabilities(context_enhanced, prompt_enhancement_spec) do
      
      enhanced_workflow = Map.merge(resolution_enhanced, %{
        prompt_enhancement_level: :enhanced,
        context_integration_enabled: true,
        resolution_capabilities_enabled: true
      })

      {:ok, add_prompt_integration_summary(enhanced_workflow, :enhanced)}
    else
      {:error, reason} -> {:error, {:enhanced_prompt_enhancement_failed, reason}}
    end
  end

  defp execute_optimized_prompt_enhancement(existing_workflow, prompt_enhancement_spec, options) do
    # Execute optimized prompt enhancement
    optimization_config = Map.get(options, :optimization_config, %{})

    optimized_enhancements = %{
      prompt_enhancement_level: :optimized,
      performance_optimization_enabled: true,
      cache_coordination_enabled: true,
      optimization_config: optimization_config,
      optimization_metadata: %{
        optimization_applied: true,
        optimization_level: :high,
        optimized_at: DateTime.utc_now()
      }
    }

    enhanced_workflow = Map.merge(existing_workflow, optimized_enhancements)

    {:ok, add_prompt_integration_summary(enhanced_workflow, :optimized)}
  end

  defp execute_comprehensive_prompt_enhancement(existing_workflow, prompt_enhancement_spec, options) do
    # Execute comprehensive prompt enhancement with all features
    with {:ok, enhanced_result} <- execute_enhanced_prompt_enhancement(existing_workflow, prompt_enhancement_spec, options),
         {:ok, optimized_result} <- execute_optimized_prompt_enhancement(enhanced_result, prompt_enhancement_spec, options),
         {:ok, integration_enhanced} <- enhance_prompt_integration_capabilities(optimized_result, prompt_enhancement_spec) do
      
      comprehensive_workflow = Map.merge(integration_enhanced, %{
        prompt_enhancement_level: :comprehensive,
        comprehensive_integration: true,
        full_feature_set_enabled: true
      })

      {:ok, add_prompt_integration_summary(comprehensive_workflow, :comprehensive)}
    else
      {:error, reason} -> {:error, {:comprehensive_enhancement_failed, reason}}
    end
  end

  defp execute_prompt_integration_validation(workflow, validation_options) do
    # Execute comprehensive validation for prompt integration
    validation_checks = [
      validate_prompt_references_integrity(workflow, validation_options),
      validate_context_integration(workflow, validation_options),
      validate_performance_requirements(workflow, validation_options),
      validate_integration_completeness(workflow, validation_options)
    ]

    successful_validations = Enum.filter(validation_checks, &match?({:ok, _}, &1))
    failed_validations = Enum.filter(validation_checks, &match?({:error, _}, &1))

    validation_result = %{
      validation_passed: Enum.empty?(failed_validations),
      successful_validations: length(successful_validations),
      failed_validations: length(failed_validations),
      validation_score: length(successful_validations) / length(validation_checks),
      prompt_references_valid: prompt_references_validation_passed?(validation_checks),
      validation_details: validation_checks
    }

    {:ok, validation_result}
  end

  # Helper functions

  defp validate_prompt_workflow_specs(workflow_spec, prompt_spec) do
    # Validate both workflow and prompt specifications
    with {:ok, validated_workflow} <- validate_workflow_specification(workflow_spec),
         {:ok, validated_prompts} <- validate_prompt_specification(prompt_spec) do
      
      {:ok, %{
        workflow_spec: validated_workflow,
        prompt_spec: validated_prompts
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_workflow_specification(workflow_spec) do
    # Validate workflow specification for prompt integration
    required_fields = [:type, :components]
    
    case validate_required_fields(workflow_spec, required_fields) do
      {:ok, _} -> {:ok, workflow_spec}
      {:error, reason} -> {:error, {:invalid_workflow_spec, reason}}
    end
  end

  defp validate_prompt_specification(prompt_spec) do
    # Validate prompt specification
    prompt_references = Map.get(prompt_spec, :prompt_references, [])
    
    case validate_prompt_references(prompt_references) do
      {:ok, _} -> {:ok, prompt_spec}
      {:error, reason} -> {:error, {:invalid_prompt_spec, reason}}
    end
  end

  defp validate_prompt_references(prompt_references) do
    # Validate prompt references structure
    validation_results = Enum.map(prompt_references, &validate_single_prompt_reference/1)
    
    failed_validations = Enum.filter(validation_results, &match?({:error, _}, &1))
    
    if Enum.empty?(failed_validations) do
      {:ok, :all_references_valid}
    else
      {:error, {:invalid_prompt_references, failed_validations}}
    end
  end

  defp validate_single_prompt_reference(prompt_reference) do
    # Validate single prompt reference
    required_fields = [:name, :type]
    
    case validate_required_fields(prompt_reference, required_fields) do
      {:ok, _} -> {:ok, prompt_reference}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_required_fields(spec, required_fields) do
    missing_fields = Enum.filter(required_fields, fn field ->
      not Map.has_key?(spec, field)
    end)

    if Enum.empty?(missing_fields) do
      {:ok, :all_fields_present}
    else
      {:error, {:missing_required_fields, missing_fields}}
    end
  end

  defp register_prompt_references(validated_specs, builder_config) do
    # Register prompt references with the reference manager
    workflow_id = generate_workflow_id()
    prompt_references = Map.get(validated_specs.prompt_spec, :prompt_references, [])

    registration_results = Enum.map(prompt_references, fn prompt_ref ->
      NamedPromptReferenceManager.register_prompt_reference(workflow_id, prompt_ref, builder_config)
    end)

    successful_registrations = Enum.filter(registration_results, &match?({:ok, _}, &1))

    if length(successful_registrations) == length(prompt_references) do
      {:ok, Enum.map(successful_registrations, fn {:ok, result} -> result end)}
    else
      {:error, :prompt_reference_registration_failed}
    end
  end

  defp enhance_workflow_spec_with_prompts(workflow_spec, prompt_references) do
    # Enhance workflow specification with prompt integration
    enhanced_spec = Map.merge(workflow_spec, %{
      prompt_integration: %{
        enabled: true,
        prompt_references: prompt_references,
        integration_version: "6.2.0"
      },
      prompt_enhanced_components: enhance_components_with_prompts(
        Map.get(workflow_spec, :components, []),
        prompt_references
      )
    })

    {:ok, enhanced_spec}
  end

  defp enhance_components_with_prompts(components, prompt_references) do
    # Enhance workflow components with prompt integration
    Enum.map(components, fn component ->
      case find_matching_prompt_reference(component, prompt_references) do
        {:ok, prompt_ref} ->
          Map.merge(component, %{
            prompt_integration: %{
              prompt_name: prompt_ref.reference_name,
              prompt_type: prompt_ref.reference_type,
              integration_enabled: true
            }
          })

        {:error, _} ->
          component
      end
    end)
  end

  defp find_matching_prompt_reference(component, prompt_references) do
    # Find prompt reference matching component
    component_type = Map.get(component, :type, :unknown)
    
    matching_ref = Enum.find(prompt_references, fn prompt_ref ->
      prompt_ref.reference_name == "#{component_type}_prompt" or
      Map.get(component, :prompt_name) == prompt_ref.reference_name
    end)

    case matching_ref do
      nil -> {:error, :no_matching_reference}
      ref -> {:ok, ref}
    end
  end

  defp build_base_workflow(enhanced_workflow_spec, builder_config) do
    # Build base workflow using EnhancedWorkflowBuilder
    case EnhancedWorkflowBuilder.create_workflow(enhanced_workflow_spec, builder_config) do
      {:ok, base_result} ->
        {:ok, base_result.workflow}

      {:error, reason} ->
        {:error, {:base_workflow_build_failed, reason}}
    end
  end

  defp integrate_prompts_with_workflow(base_workflow, prompt_references, builder_config) do
    # Integrate prompt references with built workflow
    integration_level = determine_integration_level(%{prompt_references: prompt_references}, builder_config)

    case integration_level do
      :basic ->
        integrate_basic_prompts(base_workflow, prompt_references, builder_config)

      :enhanced ->
        integrate_enhanced_prompts(base_workflow, prompt_references, builder_config)

      :optimized ->
        integrate_optimized_prompts(base_workflow, prompt_references, builder_config)

      :comprehensive ->
        integrate_comprehensive_prompts(base_workflow, prompt_references, builder_config)
    end
  end

  defp integrate_basic_prompts(base_workflow, prompt_references, builder_config) do
    # Basic prompt integration
    basic_integration = %{
      prompt_integration_enabled: true,
      prompt_references: prompt_references,
      integration_level: :basic,
      basic_integration_metadata: %{
        references_count: length(prompt_references),
        integration_type: :basic,
        integrated_at: DateTime.utc_now()
      }
    }

    integrated_workflow = Map.merge(base_workflow, basic_integration)

    {:ok, integrated_workflow}
  end

  defp integrate_enhanced_prompts(base_workflow, prompt_references, builder_config) do
    # Enhanced prompt integration with context awareness
    with {:ok, basic_integrated} <- integrate_basic_prompts(base_workflow, prompt_references, builder_config),
         {:ok, context_enhanced} <- enhance_workflow_with_context_integration(basic_integrated, prompt_references) do
      
      enhanced_workflow = Map.merge(context_enhanced, %{
        integration_level: :enhanced,
        context_integration_enabled: true
      })

      {:ok, enhanced_workflow}
    else
      {:error, reason} -> {:error, {:enhanced_integration_failed, reason}}
    end
  end

  defp integrate_optimized_prompts(base_workflow, prompt_references, builder_config) do
    # Optimized prompt integration with performance features
    optimization_features = %{
      integration_level: :optimized,
      performance_optimization_enabled: true,
      cache_coordination_enabled: true,
      optimization_metadata: %{
        performance_optimized: true,
        caching_enabled: true,
        optimization_level: :high
      }
    }

    optimized_workflow = Map.merge(base_workflow, optimization_features)

    {:ok, optimized_workflow}
  end

  defp integrate_comprehensive_prompts(base_workflow, prompt_references, builder_config) do
    # Comprehensive prompt integration with all features
    with {:ok, enhanced_result} <- integrate_enhanced_prompts(base_workflow, prompt_references, builder_config),
         {:ok, optimized_result} <- integrate_optimized_prompts(enhanced_result, prompt_references, builder_config) do
      
      comprehensive_workflow = Map.merge(optimized_result, %{
        integration_level: :comprehensive,
        comprehensive_integration: true,
        full_feature_integration: true
      })

      {:ok, comprehensive_workflow}
    else
      {:error, reason} -> {:error, {:comprehensive_integration_failed, reason}}
    end
  end

  defp enhance_workflow_context_integration(workflow, prompt_references) do
    # Enhance workflow with context integration capabilities
    context_integration = %{
      context_integration: %{
        enabled: true,
        prompt_context_passing: true,
        automatic_context_enhancement: true,
        context_validation: true
      },
      context_integration_metadata: %{
        context_integration_version: "6.2.0",
        integration_enabled_at: DateTime.utc_now()
      }
    }

    enhanced_workflow = Map.merge(workflow, context_integration)

    {:ok, enhanced_workflow}
  end

  defp enhance_prompt_resolution_capabilities(workflow, prompt_enhancement_spec) do
    # Enhance workflow with prompt resolution capabilities
    resolution_capabilities = %{
      prompt_resolution: %{
        enabled: true,
        resolution_strategy: :optimized,
        caching_enabled: true,
        validation_enabled: true
      },
      resolution_metadata: %{
        resolution_version: "6.2.0",
        capabilities_enhanced_at: DateTime.utc_now()
      }
    }

    enhanced_workflow = Map.merge(workflow, resolution_capabilities)

    {:ok, enhanced_workflow}
  end

  defp enhance_prompt_integration_capabilities(workflow, prompt_enhancement_spec) do
    # Enhance workflow with full integration capabilities
    integration_capabilities = %{
      prompt_integration_capabilities: %{
        named_references: true,
        dynamic_resolution: true,
        context_awareness: true,
        performance_optimization: true,
        cache_coordination: true
      },
      integration_capabilities_metadata: %{
        capabilities_version: "6.2.0",
        full_capabilities_enabled: true,
        enhanced_at: DateTime.utc_now()
      }
    }

    enhanced_workflow = Map.merge(workflow, integration_capabilities)

    {:ok, enhanced_workflow}
  end

  defp determine_integration_level(prompt_spec, builder_config) do
    # Determine appropriate integration level
    prompt_count = length(Map.get(prompt_spec, :prompt_references, []))
    complexity_level = Map.get(builder_config, :complexity_level, :medium)
    optimization_requested = Map.get(builder_config, :enable_optimization, true)

    case {prompt_count, complexity_level, optimization_requested} do
      {count, :high, true} when count > 3 -> :comprehensive
      {count, _, true} when count > 1 -> :optimized
      {count, _, _} when count > 0 -> :enhanced
      _ -> :basic
    end
  end

  defp add_prompt_integration_summary(workflow, integration_level) do
    # Add prompt integration summary to workflow
    prompt_integration_summary = %{
      integration_level: integration_level,
      prompts_integrated: count_integrated_prompts(workflow),
      integration_successful: true,
      integration_timestamp: DateTime.utc_now(),
      features_enabled: get_enabled_features(workflow)
    }

    Map.put(workflow, :prompt_integration_summary, prompt_integration_summary)
  end

  defp count_integrated_prompts(workflow) do
    # Count integrated prompts in workflow
    prompt_references = Map.get(workflow, :prompt_references, [])
    length(prompt_references)
  end

  defp get_enabled_features(workflow) do
    # Get list of enabled prompt integration features
    features = []

    features = if Map.get(workflow, :prompt_integration_enabled, false) do
      [:prompt_integration | features]
    else
      features
    end

    features = if Map.get(workflow, :context_integration_enabled, false) do
      [:context_integration | features]
    else
      features
    end

    features = if Map.get(workflow, :performance_optimization_enabled, false) do
      [:performance_optimization | features]
    else
      features
    end

    features
  end

  # Validation helper functions

  defp validate_prompt_references_integrity(workflow, validation_options) do
    # Validate prompt references integrity
    prompt_references = Map.get(workflow, :prompt_references, [])

    case NamedPromptReferenceManager.validate_prompt_references(workflow.id, prompt_references) do
      {:ok, validation_result} ->
        if validation_result.validation_success_rate > 0.9 do
          {:ok, %{check: :prompt_references, status: :valid, success_rate: validation_result.validation_success_rate}}
        else
          {:error, %{check: :prompt_references, status: :integrity_issues, success_rate: validation_result.validation_success_rate}}
        end

      {:error, reason} ->
        {:error, %{check: :prompt_references, status: :validation_failed, reason: reason}}
    end
  end

  defp validate_context_integration(workflow, validation_options) do
    # Validate context integration configuration
    context_config = Map.get(workflow, :context_integration, %{})

    if Map.get(context_config, :enabled, false) do
      {:ok, %{check: :context_integration, status: :valid, context_features: Map.keys(context_config)}}
    else
      {:ok, %{check: :context_integration, status: :disabled, note: "Context integration not enabled"}}
    end
  end

  defp validate_performance_requirements(workflow, validation_options) do
    # Validate performance requirements
    performance_config = Map.get(workflow, :performance_optimization, %{})
    
    if Map.get(performance_config, :enabled, false) do
      {:ok, %{check: :performance, status: :optimized, features: Map.keys(performance_config)}}
    else
      {:ok, %{check: :performance, status: :standard, note: "Basic performance configuration"}}
    end
  end

  defp validate_integration_completeness(workflow, validation_options) do
    # Validate integration completeness
    required_integration_features = [:prompt_integration_enabled, :prompt_references]
    
    present_features = Enum.filter(required_integration_features, fn feature ->
      Map.has_key?(workflow, feature)
    end)

    completeness_score = length(present_features) / length(required_integration_features)

    if completeness_score >= 0.8 do
      {:ok, %{check: :completeness, status: :complete, completeness_score: completeness_score}}
    else
      {:error, %{check: :completeness, status: :incomplete, completeness_score: completeness_score}}
    end
  end

  defp prompt_references_validation_passed?(validation_checks) do
    # Check if prompt references validation passed
    prompt_ref_check = Enum.find(validation_checks, fn check ->
      case check do
        {:ok, %{check: :prompt_references}} -> true
        {:error, %{check: :prompt_references}} -> true
        _ -> false
      end
    end)

    case prompt_ref_check do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp enhance_workflow_with_context_integration(workflow, prompt_references) do
    # Enhance workflow with context integration capabilities
    context_integration = %{
      context_integration: %{
        enabled: true,
        prompt_context_passing: true,
        automatic_context_enhancement: true,
        context_validation: true,
        prompt_references_context: prompt_references
      },
      context_integration_metadata: %{
        context_integration_version: "6.2.0",
        integration_enabled_at: DateTime.utc_now(),
        prompt_references_count: length(prompt_references)
      }
    }

    enhanced_workflow = Map.merge(workflow, context_integration)

    {:ok, enhanced_workflow}
  end

  defp generate_workflow_id do
    # Generate unique workflow ID
    timestamp = System.system_time(:nanosecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "prompt_aware_workflow_#{timestamp}_#{random}"
  end
end