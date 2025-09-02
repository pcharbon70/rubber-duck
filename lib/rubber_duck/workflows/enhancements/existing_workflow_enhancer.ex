defmodule RubberDuck.Workflows.Enhancements.ExistingWorkflowEnhancer do
  @moduledoc """
  Enhancement service for existing workflows with project-specific prompt customization.
  
  Enhances existing Code Review, Documentation Generation, and Refactoring workflows
  with sophisticated prompt integration, enabling project-specific analysis prompts,
  customizable documentation styles, and team-specific refactoring preferences
  while maintaining backward compatibility and performance.
  
  Features:
  - Code Review workflows with project-specific analysis prompts and customization
  - Documentation Generation workflows with customizable documentation styles and formats
  - Refactoring Suggestion workflows with team-specific refactoring preferences and standards  
  - User context and preference integration with dynamic customization and inheritance
  - Backward compatibility with existing workflow definitions and execution patterns
  - Performance optimization for enhanced workflows with monitoring and analytics
  """

  require Logger

  alias RubberDuck.Workflows.Enhancements.{
    PromptAwareWorkflowBuilder,
    WorkflowStepPromptInjector
  }

  alias RubberDuck.Prompts.WorkflowIntegration.WorkflowPromptResolver

  @supported_workflows [:code_review, :documentation_generation, :refactoring_suggestions]
  @enhancement_levels [:basic, :standard, :advanced, :comprehensive]

  def enhance_code_review_workflow(workflow_config, enhancement_spec, options \\ %{}) do
    Logger.info("ExistingWorkflowEnhancer: Enhancing Code Review workflow",
      workflow_id: Map.get(workflow_config, :id, "unknown"),
      enhancement_level: Map.get(options, :enhancement_level, :standard)
    )

    case execute_code_review_enhancement(workflow_config, enhancement_spec, options) do
      {:ok, enhanced_workflow} ->
        Logger.info("ExistingWorkflowEnhancer: Code Review workflow enhanced successfully",
          workflow_id: enhanced_workflow.id,
          prompts_integrated: enhanced_workflow.code_review_integration.prompts_integrated,
          customization_level: enhanced_workflow.code_review_integration.customization_level
        )

        {:ok, enhanced_workflow}

      {:error, reason} ->
        Logger.error("ExistingWorkflowEnhancer: Code Review enhancement failed", error: reason)
        {:error, reason}
    end
  end

  def enhance_documentation_workflow(workflow_config, enhancement_spec, options \\ %{}) do
    Logger.info("ExistingWorkflowEnhancer: Enhancing Documentation Generation workflow",
      workflow_id: Map.get(workflow_config, :id, "unknown"),
      documentation_styles: length(Map.get(enhancement_spec, :documentation_styles, []))
    )

    case execute_documentation_enhancement(workflow_config, enhancement_spec, options) do
      {:ok, enhanced_workflow} ->
        Logger.info("ExistingWorkflowEnhancer: Documentation workflow enhanced successfully",
          workflow_id: enhanced_workflow.id,
          styles_available: enhanced_workflow.documentation_integration.styles_count,
          customization_enabled: enhanced_workflow.documentation_integration.customization_enabled
        )

        {:ok, enhanced_workflow}

      {:error, reason} ->
        Logger.error("ExistingWorkflowEnhancer: Documentation enhancement failed", error: reason)
        {:error, reason}
    end
  end

  def enhance_refactoring_workflow(workflow_config, enhancement_spec, options \\ %{}) do
    Logger.info("ExistingWorkflowEnhancer: Enhancing Refactoring Suggestions workflow",
      workflow_id: Map.get(workflow_config, :id, "unknown"),
      team_preferences: Map.has_key?(enhancement_spec, :team_preferences)
    )

    case execute_refactoring_enhancement(workflow_config, enhancement_spec, options) do
      {:ok, enhanced_workflow} ->
        Logger.info("ExistingWorkflowEnhancer: Refactoring workflow enhanced successfully",
          workflow_id: enhanced_workflow.id,
          preferences_integrated: enhanced_workflow.refactoring_integration.preferences_integrated,
          team_standards_applied: enhanced_workflow.refactoring_integration.team_standards_applied
        )

        {:ok, enhanced_workflow}

      {:error, reason} ->
        Logger.error("ExistingWorkflowEnhancer: Refactoring enhancement failed", error: reason)
        {:error, reason}
    end
  end

  def enhance_all_existing_workflows(workflows_config, global_enhancement_spec, options \\ %{}) do
    Logger.info("ExistingWorkflowEnhancer: Enhancing all existing workflows",
      workflows_count: length(workflows_config)
    )

    case execute_bulk_workflow_enhancement(workflows_config, global_enhancement_spec, options) do
      {:ok, enhancement_results} ->
        Logger.info("ExistingWorkflowEnhancer: Bulk enhancement completed",
          workflows_enhanced: enhancement_results.successful_enhancements,
          enhancement_success_rate: enhancement_results.success_rate
        )

        {:ok, enhancement_results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private implementation functions

  defp execute_code_review_enhancement(workflow_config, enhancement_spec, options) do
    # Execute Code Review workflow enhancement
    code_review_prompts = build_code_review_prompt_spec(enhancement_spec, options)

    with {:ok, prompt_enhanced_workflow} <- integrate_code_review_prompts(workflow_config, code_review_prompts, options),
         {:ok, analysis_enhanced_workflow} <- enhance_code_analysis_capabilities(prompt_enhanced_workflow, enhancement_spec),
         {:ok, customization_enhanced_workflow} <- apply_project_specific_customizations(analysis_enhanced_workflow, enhancement_spec) do
      
      code_review_integration = %{
        prompts_integrated: length(code_review_prompts),
        analysis_capabilities_enhanced: true,
        customization_level: determine_customization_level(enhancement_spec, options),
        project_specific_prompts: %{
          quality_analysis_prompt: "project_code_quality_analysis_prompt",
          security_analysis_prompt: "project_security_analysis_prompt",
          architecture_review_prompt: "project_architecture_review_prompt",
          style_compliance_prompt: "project_style_compliance_prompt"
        },
        enhancement_metadata: %{
          enhancement_version: "6.2.0",
          enhanced_at: DateTime.utc_now(),
          enhancement_successful: true
        }
      }

      final_workflow = Map.merge(customization_enhanced_workflow, %{
        workflow_type: :enhanced_code_review,
        code_review_integration: code_review_integration
      })

      {:ok, final_workflow}
    else
      {:error, reason} -> {:error, {:code_review_enhancement_failed, reason}}
    end
  end

  defp execute_documentation_enhancement(workflow_config, enhancement_spec, options) do
    # Execute Documentation Generation workflow enhancement
    documentation_styles = Map.get(enhancement_spec, :documentation_styles, ["technical", "user_guide", "api_reference"])

    with {:ok, style_enhanced_workflow} <- integrate_documentation_styles(workflow_config, documentation_styles, options),
         {:ok, format_enhanced_workflow} <- enhance_documentation_formats(style_enhanced_workflow, enhancement_spec),
         {:ok, customization_enhanced_workflow} <- apply_documentation_customizations(format_enhanced_workflow, enhancement_spec) do
      
      documentation_integration = %{
        styles_count: length(documentation_styles),
        available_styles: documentation_styles,
        customization_enabled: true,
        format_flexibility: Map.get(enhancement_spec, :format_flexibility, :high),
        project_specific_prompts: %{
          technical_documentation_prompt: "project_technical_documentation_prompt",
          user_guide_prompt: "project_user_guide_prompt",
          api_documentation_prompt: "project_api_documentation_prompt",
          readme_generation_prompt: "project_readme_generation_prompt"
        },
        enhancement_metadata: %{
          enhancement_version: "6.2.0",
          enhanced_at: DateTime.utc_now(),
          styles_integrated: true
        }
      }

      final_workflow = Map.merge(customization_enhanced_workflow, %{
        workflow_type: :enhanced_documentation_generation,
        documentation_integration: documentation_integration
      })

      {:ok, final_workflow}
    else
      {:error, reason} -> {:error, {:documentation_enhancement_failed, reason}}
    end
  end

  defp execute_refactoring_enhancement(workflow_config, enhancement_spec, options) do
    # Execute Refactoring Suggestions workflow enhancement
    team_preferences = Map.get(enhancement_spec, :team_preferences, %{})

    with {:ok, preferences_enhanced_workflow} <- integrate_team_preferences(workflow_config, team_preferences, options),
         {:ok, standards_enhanced_workflow} <- enhance_refactoring_standards(preferences_enhanced_workflow, enhancement_spec),
         {:ok, pattern_enhanced_workflow} <- integrate_refactoring_patterns(standards_enhanced_workflow, enhancement_spec) do
      
      refactoring_integration = %{
        preferences_integrated: not Enum.empty?(team_preferences),
        team_standards_applied: true,
        refactoring_patterns_enabled: true,
        project_specific_prompts: %{
          code_analysis_prompt: "project_refactoring_analysis_prompt",
          pattern_suggestion_prompt: "project_refactoring_patterns_prompt",
          optimization_prompt: "project_code_optimization_prompt",
          cleanup_suggestion_prompt: "project_code_cleanup_prompt"
        },
        enhancement_metadata: %{
          enhancement_version: "6.2.0",
          enhanced_at: DateTime.utc_now(),
          team_preferences_count: map_size(team_preferences)
        }
      }

      final_workflow = Map.merge(pattern_enhanced_workflow, %{
        workflow_type: :enhanced_refactoring_suggestions,
        refactoring_integration: refactoring_integration
      })

      {:ok, final_workflow}
    else
      {:error, reason} -> {:error, {:refactoring_enhancement_failed, reason}}
    end
  end

  defp execute_bulk_workflow_enhancement(workflows_config, global_enhancement_spec, options) do
    # Execute bulk enhancement for all workflows
    enhancement_results = Enum.map(workflows_config, fn workflow_config ->
      workflow_type = Map.get(workflow_config, :type, :unknown)
      enhance_single_workflow_by_type(workflow_config, workflow_type, global_enhancement_spec, options)
    end)

    successful_enhancements = Enum.filter(enhancement_results, &match?({:ok, _}, &1))
    failed_enhancements = Enum.filter(enhancement_results, &match?({:error, _}, &1))

    bulk_result = %{
      total_workflows: length(workflows_config),
      successful_enhancements: length(successful_enhancements),
      failed_enhancements: length(failed_enhancements),
      success_rate: length(successful_enhancements) / length(workflows_config),
      enhanced_workflows: Enum.map(successful_enhancements, fn {:ok, result} -> result end),
      enhancement_summary: %{
        bulk_enhancement_completed: true,
        enhancement_timestamp: DateTime.utc_now()
      }
    }

    {:ok, bulk_result}
  end

  # Workflow-specific enhancement helpers

  defp build_code_review_prompt_spec(enhancement_spec, options) do
    # Build prompt specification for code review
    base_prompts = [
      %{name: "project_code_quality_analysis_prompt", type: :analysis, priority: :high},
      %{name: "project_security_analysis_prompt", type: :security, priority: :high},
      %{name: "project_architecture_review_prompt", type: :architecture, priority: :medium},
      %{name: "project_style_compliance_prompt", type: :style, priority: :medium}
    ]

    # Add custom prompts if specified
    custom_prompts = Map.get(enhancement_spec, :custom_analysis_prompts, [])
    
    base_prompts ++ custom_prompts
  end

  defp integrate_code_review_prompts(workflow_config, code_review_prompts, options) do
    # Integrate code review prompts into workflow
    prompt_injection_specs = Enum.map(code_review_prompts, fn prompt ->
      %{
        prompt_name: prompt.name,
        injection_type: :context,
        injection_timing: :before_step,
        validation_required: true
      }
    end)

    enhanced_workflow = Map.merge(workflow_config, %{
      code_review_prompts: code_review_prompts,
      prompt_injection_specs: prompt_injection_specs,
      code_review_enhancement_applied: true
    })

    {:ok, enhanced_workflow}
  end

  defp enhance_code_analysis_capabilities(workflow, enhancement_spec) do
    # Enhance code analysis capabilities
    analysis_capabilities = %{
      quality_analysis_enhanced: true,
      security_analysis_enhanced: true,
      architecture_analysis_enhanced: true,
      style_analysis_enhanced: true,
      custom_analysis_rules: Map.get(enhancement_spec, :custom_analysis_rules, [])
    }

    enhanced_workflow = Map.put(workflow, :analysis_capabilities, analysis_capabilities)

    {:ok, enhanced_workflow}
  end

  defp integrate_documentation_styles(workflow_config, documentation_styles, options) do
    # Integrate documentation styles into workflow
    style_configurations = Enum.map(documentation_styles, fn style ->
      %{
        style_name: style,
        prompt_name: "project_#{style}_documentation_prompt",
        format_requirements: get_style_format_requirements(style),
        customization_options: get_style_customization_options(style)
      }
    end)

    enhanced_workflow = Map.merge(workflow_config, %{
      documentation_styles: style_configurations,
      style_flexibility_enabled: true,
      documentation_enhancement_applied: true
    })

    {:ok, enhanced_workflow}
  end

  defp enhance_documentation_formats(workflow, enhancement_spec) do
    # Enhance documentation format capabilities
    format_capabilities = %{
      markdown_enhanced: true,
      html_generation: Map.get(enhancement_spec, :html_generation, true),
      pdf_generation: Map.get(enhancement_spec, :pdf_generation, false),
      confluence_integration: Map.get(enhancement_spec, :confluence_integration, false),
      custom_formats: Map.get(enhancement_spec, :custom_formats, [])
    }

    enhanced_workflow = Map.put(workflow, :format_capabilities, format_capabilities)

    {:ok, enhanced_workflow}
  end

  defp integrate_team_preferences(workflow_config, team_preferences, options) do
    # Integrate team preferences into refactoring workflow
    preferences_integration = %{
      team_preferences: team_preferences,
      preference_inheritance: Map.get(options, :preference_inheritance, :hierarchical),
      preference_validation: Map.get(options, :preference_validation, true),
      custom_refactoring_rules: Map.get(team_preferences, :custom_rules, []),
      preference_integration_metadata: %{
        preferences_count: map_size(team_preferences),
        integrated_at: DateTime.utc_now()
      }
    }

    enhanced_workflow = Map.merge(workflow_config, %{
      team_preferences_integration: preferences_integration,
      preferences_enhancement_applied: true
    })

    {:ok, enhanced_workflow}
  end

  defp enhance_refactoring_standards(workflow, enhancement_spec) do
    # Enhance refactoring standards
    refactoring_standards = %{
      code_quality_standards: Map.get(enhancement_spec, :code_quality_standards, %{}),
      performance_standards: Map.get(enhancement_spec, :performance_standards, %{}),
      style_standards: Map.get(enhancement_spec, :style_standards, %{}),
      team_conventions: Map.get(enhancement_spec, :team_conventions, %{}),
      standards_enforcement_level: Map.get(enhancement_spec, :enforcement_level, :moderate)
    }

    enhanced_workflow = Map.put(workflow, :refactoring_standards, refactoring_standards)

    {:ok, enhanced_workflow}
  end

  defp integrate_refactoring_patterns(workflow, enhancement_spec) do
    # Integrate refactoring patterns
    refactoring_patterns = %{
      enabled_patterns: Map.get(enhancement_spec, :enabled_patterns, get_default_refactoring_patterns()),
      custom_patterns: Map.get(enhancement_spec, :custom_patterns, []),
      pattern_priority: Map.get(enhancement_spec, :pattern_priority, :quality_focused),
      pattern_suggestion_level: Map.get(enhancement_spec, :suggestion_level, :moderate)
    }

    enhanced_workflow = Map.put(workflow, :refactoring_patterns, refactoring_patterns)

    {:ok, enhanced_workflow}
  end

  defp apply_project_specific_customizations(workflow, enhancement_spec) do
    # Apply project-specific customizations
    project_customizations = %{
      project_id: Map.get(enhancement_spec, :project_id),
      project_type: Map.get(enhancement_spec, :project_type, :elixir),
      project_conventions: Map.get(enhancement_spec, :project_conventions, %{}),
      custom_analysis_rules: Map.get(enhancement_spec, :custom_analysis_rules, []),
      quality_thresholds: Map.get(enhancement_spec, :quality_thresholds, %{})
    }

    customized_workflow = Map.put(workflow, :project_customizations, project_customizations)

    {:ok, customized_workflow}
  end

  defp apply_documentation_customizations(workflow, enhancement_spec) do
    # Apply documentation-specific customizations
    documentation_customizations = %{
      project_branding: Map.get(enhancement_spec, :project_branding, %{}),
      documentation_standards: Map.get(enhancement_spec, :documentation_standards, %{}),
      output_preferences: Map.get(enhancement_spec, :output_preferences, %{}),
      template_customizations: Map.get(enhancement_spec, :template_customizations, %{})
    }

    customized_workflow = Map.put(workflow, :documentation_customizations, documentation_customizations)

    {:ok, customized_workflow}
  end

  defp enhance_single_workflow_by_type(workflow_config, workflow_type, enhancement_spec, options) do
    # Enhance single workflow based on its type
    case workflow_type do
      :code_review ->
        enhance_code_review_workflow(workflow_config, enhancement_spec, options)

      :documentation_generation ->
        enhance_documentation_workflow(workflow_config, enhancement_spec, options)

      :refactoring_suggestions ->
        enhance_refactoring_workflow(workflow_config, enhancement_spec, options)

      _ ->
        enhance_generic_workflow(workflow_config, enhancement_spec, options)
    end
  end

  defp enhance_generic_workflow(workflow_config, enhancement_spec, options) do
    # Enhance generic workflow with basic prompt integration
    generic_enhancement = %{
      workflow_type: :enhanced_generic,
      prompt_integration_enabled: true,
      generic_enhancement_applied: true,
      enhancement_level: Map.get(options, :enhancement_level, :basic),
      generic_integration_metadata: %{
        enhanced_at: DateTime.utc_now(),
        enhancement_type: :generic
      }
    }

    enhanced_workflow = Map.merge(workflow_config, generic_enhancement)

    {:ok, enhanced_workflow}
  end

  # Helper functions

  defp determine_customization_level(enhancement_spec, options) do
    # Determine customization level based on specification
    custom_rules_count = length(Map.get(enhancement_spec, :custom_analysis_rules, []))
    project_conventions_count = map_size(Map.get(enhancement_spec, :project_conventions, %{}))
    enhancement_level = Map.get(options, :enhancement_level, :standard)

    case {custom_rules_count, project_conventions_count, enhancement_level} do
      {rules, conventions, :comprehensive} when rules > 5 or conventions > 10 -> :comprehensive
      {rules, conventions, _} when rules > 2 or conventions > 5 -> :advanced
      {rules, conventions, _} when rules > 0 or conventions > 0 -> :standard
      _ -> :basic
    end
  end

  defp get_style_format_requirements(style) do
    # Get format requirements for documentation style
    case style do
      "technical" -> %{format: :markdown, sections: [:overview, :technical_details, :examples]}
      "user_guide" -> %{format: :markdown, sections: [:introduction, :getting_started, :usage_examples]}
      "api_reference" -> %{format: :markdown, sections: [:endpoints, :parameters, :examples, :responses]}
      _ -> %{format: :markdown, sections: [:content]}
    end
  end

  defp get_style_customization_options(style) do
    # Get customization options for documentation style
    case style do
      "technical" -> %{code_examples: true, diagrams: true, deep_explanations: true}
      "user_guide" -> %{step_by_step: true, screenshots: true, troubleshooting: true}
      "api_reference" -> %{request_examples: true, response_schemas: true, error_codes: true}
      _ -> %{basic_formatting: true}
    end
  end

  defp get_default_refactoring_patterns do
    # Get default refactoring patterns
    [
      :extract_function,
      :inline_variable,
      :rename_variable,
      :simplify_conditional,
      :remove_dead_code,
      :optimize_performance,
      :improve_readability,
      :reduce_complexity
    ]
  end
end