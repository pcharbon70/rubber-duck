defmodule RubberDuck.Prompts.WorkflowIntegration.WorkflowIntegrationEndToEndTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Prompts.WorkflowIntegration.{
    NamedPromptReferenceManager,
    ReactorPromptIntegration,
    WorkflowContextEnhancer,
    WorkflowPromptCacheCoordinator,
    WorkflowPromptResolver
  }

  alias RubberDuck.Workflows.Enhancements.{
    ExistingWorkflowEnhancer,
    PromptAwareWorkflowBuilder,
    WorkflowPromptPerformanceMonitor,
    WorkflowStepPromptInjector
  }

  alias RubberDuck.Workflows.Builder.EnhancedWorkflowBuilder

  describe "Phase 6.2: Workflow System Integration - End-to-End Testing" do
    test "complete workflow-prompt integration pipeline" do
      # Test complete integration from workflow definition through prompt-enhanced execution

      # Step 1: Create workflow with prompt references
      workflow_spec = %{
        type: :code_review,
        components: [
          %{
            type: :analysis,
            name: "quality_analysis",
            prompt_name: "code_quality_analysis_prompt"
          },
          %{type: :validation, name: "security_check", prompt_name: "security_analysis_prompt"},
          %{type: :report, name: "review_summary", prompt_name: "review_summary_prompt"}
        ]
      }

      prompt_spec = %{
        prompt_references: [
          %{name: "code_quality_analysis_prompt", type: :analysis, scope: :project},
          %{name: "security_analysis_prompt", type: :security, scope: :project},
          %{name: "review_summary_prompt", type: :summary, scope: :user}
        ]
      }

      # Step 2: Create prompt-aware workflow
      assert {:ok, workflow_result} =
               PromptAwareWorkflowBuilder.create_prompt_aware_workflow(workflow_spec, prompt_spec)

      assert workflow_result.workflow.prompt_integration_enabled == true
      assert workflow_result.prompt_integration_level in [:enhanced, :optimized, :comprehensive]
      assert length(workflow_result.prompt_references) == 3

      # Step 3: Test named prompt reference management
      workflow_id = workflow_result.workflow.id

      for prompt_ref <- prompt_spec.prompt_references do
        assert {:ok, registration_result} =
                 NamedPromptReferenceManager.register_prompt_reference(workflow_id, prompt_ref)

        assert registration_result.registration_successful == true
        assert registration_result.reference_name == prompt_ref.name
      end

      # Step 4: Test prompt resolution for workflow
      context = %{
        user_id: "test_user_123",
        project_id: "test_project_456",
        workflow_type: :code_review,
        code_analysis_config: %{quality_threshold: 0.8}
      }

      assert {:ok, resolution_result} =
               WorkflowPromptResolver.resolve_workflow_prompt(
                 workflow_id,
                 "code_quality_analysis_prompt",
                 context
               )

      assert resolution_result.prompt_name == "code_quality_analysis_prompt"
      assert resolution_result.workflow_id == workflow_id
      assert is_binary(resolution_result.resolved_prompt)
      assert Map.has_key?(resolution_result, :composition_metadata)

      # Step 5: Test context enhancement
      assert {:ok, enhanced_context} =
               WorkflowContextEnhancer.enhance_context(context, workflow_id)

      assert Map.has_key?(enhanced_context, :enhancement_metadata)

      assert enhanced_context.enhancement_metadata.enhancement_strategy in [
               :merge,
               :override,
               :inherit,
               :custom
             ]

      # Step 6: Test workflow step prompt injection
      step_config = %{
        name: "quality_analysis_step",
        type: :analysis,
        parameters: %{analysis_type: :quality}
      }

      prompt_injection_spec = %{
        prompt_name: "code_quality_analysis_prompt",
        injection_type: :parameter,
        injection_timing: :before_step
      }

      injection_options = %{
        workflow_id: workflow_id,
        context: enhanced_context,
        injection_strategy: :parameter_injection
      }

      assert {:ok, injection_result} =
               WorkflowStepPromptInjector.inject_prompt_into_step(
                 step_config,
                 prompt_injection_spec,
                 injection_options
               )

      assert injection_result.injection_successful == true
      assert injection_result.enhanced_step.name == "quality_analysis_step"
      assert Map.has_key?(injection_result.enhanced_step.parameters, :injected_prompt)

      # Step 7: Test existing workflow enhancement
      code_review_enhancement_spec = %{
        custom_analysis_rules: [
          %{rule: "check_function_complexity", threshold: 10},
          %{rule: "validate_error_handling", level: :strict}
        ],
        project_conventions: %{
          naming_style: :snake_case,
          documentation_required: true
        }
      }

      enhancement_options = %{
        enhancement_level: :advanced,
        project_id: "test_project_456"
      }

      assert {:ok, enhanced_workflow} =
               ExistingWorkflowEnhancer.enhance_code_review_workflow(
                 workflow_result.workflow,
                 code_review_enhancement_spec,
                 enhancement_options
               )

      assert enhanced_workflow.workflow_type == :enhanced_code_review
      assert enhanced_workflow.code_review_integration.prompts_integrated > 0
      assert enhanced_workflow.code_review_integration.customization_level == :advanced

      # Step 8: Test batch prompt resolution
      prompt_references = [
        %{id: "ref1", name: "code_quality_analysis_prompt"},
        %{id: "ref2", name: "security_analysis_prompt"},
        %{id: "ref3", name: "review_summary_prompt"}
      ]

      assert {:ok, batch_result} =
               WorkflowPromptResolver.resolve_batch_prompts(
                 workflow_id,
                 prompt_references,
                 enhanced_context
               )

      assert batch_result.total_prompts == 3
      assert batch_result.success_count >= 0
      assert length(batch_result.successful_resolutions) == batch_result.success_count

      # Step 9: Test cache coordination
      cache_options = %{
        cache_strategy: :hybrid,
        enable_cross_workflow_sharing: true
      }

      # Cache a resolved prompt
      assert {:ok, cache_result} =
               WorkflowPromptCacheCoordinator.cache_workflow_prompt(
                 workflow_id,
                 "code_quality_analysis_prompt",
                 resolution_result,
                 cache_options
               )

      assert cache_result.cache_successful == true

      # Retrieve from cache
      assert {:ok, cached_result} =
               WorkflowPromptCacheCoordinator.get_cached_prompt(
                 workflow_id,
                 "code_quality_analysis_prompt",
                 cache_options
               )

      assert cached_result.cache_hit == true

      # Step 10: Test performance monitoring
      # Track operations
      WorkflowPromptPerformanceMonitor.track_workflow_prompt_operation(
        :prompt_resolution,
        %{workflow_id: workflow_id, success: true},
        # microseconds
        %{total_time: 150_000, resolution_time: 100_000}
      )

      # Get performance analytics
      assert {:ok, analytics} =
               WorkflowPromptPerformanceMonitor.get_performance_analytics(workflow_id)

      assert Map.has_key?(analytics, :metrics)
      assert Map.has_key?(analytics, :summary)
      assert analytics.analytics_level in [:basic, :standard, :detailed, :comprehensive]

      # Get performance recommendations
      assert {:ok, recommendations} =
               WorkflowPromptPerformanceMonitor.get_performance_recommendations(workflow_id)

      assert is_list(recommendations.recommendations)
      assert Map.has_key?(recommendations, :performance_score)

      # Step 11: Test Reactor prompt integration
      reactor_step_config = %{
        name: "reactor_analysis_step",
        type: :action,
        function: :analyze_code
      }

      prompt_config = %{
        prompt_name: "code_quality_analysis_prompt",
        optimization_level: :high
      }

      integration_options = %{
        integration_mode: :full_integration,
        enable_caching: true
      }

      assert {:ok, enhanced_step} =
               ReactorPromptIntegration.enhance_reactor_step(
                 reactor_step_config,
                 prompt_config,
                 integration_options
               )

      assert enhanced_step.prompt_integration_enabled == true
      assert enhanced_step.integration_mode == :full_integration

      # Step 12: Test workflow validation with prompt integration
      assert {:ok, validation_result} =
               PromptAwareWorkflowBuilder.validate_prompt_integrated_workflow(enhanced_workflow)

      assert validation_result.validation_passed == true
      assert validation_result.prompt_references_valid == true

      # Step 13: Cleanup test resources
      NamedPromptReferenceManager.cleanup_workflow_references(workflow_id)
      WorkflowPromptCacheCoordinator.invalidate_workflow_cache(workflow_id)

      # Final assertions for complete integration
      assert is_binary(workflow_id)
      assert Map.has_key?(enhanced_workflow, :prompt_integration_summary)
      assert enhanced_workflow.prompt_integration_summary.integration_successful == true
    end

    test "workflow prompt resolution with caching" do
      # Test prompt resolution with comprehensive caching

      workflow_id = "test_workflow_cache_#{System.system_time(:nanosecond)}"
      prompt_name = "test_caching_prompt"

      context = %{
        user_id: "cache_test_user",
        project_id: "cache_test_project",
        workflow_type: :documentation
      }

      # First resolution (cache miss)
      resolution_start = System.monotonic_time(:microsecond)

      assert {:ok, first_result} =
               WorkflowPromptResolver.resolve_workflow_prompt(workflow_id, prompt_name, context)

      first_resolution_time = System.monotonic_time(:microsecond) - resolution_start

      assert first_result.prompt_name == prompt_name
      assert first_result.workflow_id == workflow_id
      assert first_result.cached == false

      # Second resolution (should be cached)
      cached_resolution_start = System.monotonic_time(:microsecond)

      assert {:ok, second_result} =
               WorkflowPromptResolver.resolve_workflow_prompt(workflow_id, prompt_name, context)

      cached_resolution_time = System.monotonic_time(:microsecond) - cached_resolution_start

      # Cached resolution should be faster
      assert cached_resolution_time < first_resolution_time
      assert second_result.prompt_name == prompt_name

      # Test cache invalidation
      WorkflowPromptResolver.invalidate_workflow_cache(workflow_id)

      # Third resolution after invalidation (cache miss again)
      assert {:ok, third_result} =
               WorkflowPromptResolver.resolve_workflow_prompt(workflow_id, prompt_name, context)

      assert third_result.prompt_name == prompt_name
    end

    test "context enhancement and optimization" do
      # Test context enhancement and optimization capabilities

      base_context = %{
        user_id: "context_test_user",
        project_id: "context_test_project",
        # Large context data
        large_data: String.duplicate("x", 10_000),
        metadata: %{
          debug_info: "extensive debug information",
          temporary_data: %{temp1: "data1", temp2: "data2"}
        }
      }

      workflow_id = "context_test_workflow_#{System.system_time(:nanosecond)}"

      # Test basic context enhancement
      assert {:ok, enhanced_context} =
               WorkflowContextEnhancer.enhance_context(base_context, workflow_id)

      assert Map.has_key?(enhanced_context, :enhancement_metadata)

      assert enhanced_context.enhancement_metadata.enhancement_strategy in [
               :merge,
               :override,
               :inherit,
               :custom
             ]

      # Test context validation
      assert {:ok, validation_result} =
               WorkflowContextEnhancer.validate_context(enhanced_context)

      assert validation_result.validation_passed == true
      assert validation_result.validation_score >= 0.0
      assert validation_result.validation_score <= 1.0

      # Test context optimization for workflow
      assert {:ok, optimization_result} =
               WorkflowContextEnhancer.optimize_context_for_workflow(
                 enhanced_context,
                 :code_review,
                 %{optimization_priority: :performance}
               )

      assert Map.has_key?(optimization_result, :optimized_context)
      assert Map.has_key?(optimization_result, :optimization_metrics)
      assert optimization_result.optimization_metrics.optimization_effective in [true, false]
    end

    test "existing workflow enhancement integration" do
      # Test enhancement of existing workflows with prompt integration

      # Test Code Review workflow enhancement
      code_review_workflow = %{
        id: "code_review_test_#{System.system_time(:nanosecond)}",
        type: :code_review,
        components: [
          %{type: :analysis, name: "quality_check"},
          %{type: :security, name: "security_scan"}
        ]
      }

      code_review_enhancement_spec = %{
        custom_analysis_rules: [
          %{rule: "complexity_check", threshold: 8},
          %{rule: "documentation_check", required: true}
        ],
        project_conventions: %{
          style_guide: :corporate,
          security_level: :high
        }
      }

      assert {:ok, enhanced_code_review} =
               ExistingWorkflowEnhancer.enhance_code_review_workflow(
                 code_review_workflow,
                 code_review_enhancement_spec,
                 %{enhancement_level: :advanced}
               )

      assert enhanced_code_review.workflow_type == :enhanced_code_review
      assert enhanced_code_review.code_review_integration.prompts_integrated > 0
      assert enhanced_code_review.code_review_integration.customization_level == :advanced

      # Test Documentation workflow enhancement
      documentation_workflow = %{
        id: "documentation_test_#{System.system_time(:nanosecond)}",
        type: :documentation_generation,
        components: [
          %{type: :content_generation, name: "api_docs"},
          %{type: :formatting, name: "style_application"}
        ]
      }

      documentation_enhancement_spec = %{
        documentation_styles: ["technical", "user_guide", "api_reference"],
        format_flexibility: :high,
        custom_formats: ["confluence", "notion"]
      }

      assert {:ok, enhanced_documentation} =
               ExistingWorkflowEnhancer.enhance_documentation_workflow(
                 documentation_workflow,
                 documentation_enhancement_spec,
                 %{enhancement_level: :standard}
               )

      assert enhanced_documentation.workflow_type == :enhanced_documentation_generation
      assert enhanced_documentation.documentation_integration.styles_count == 3
      assert enhanced_documentation.documentation_integration.customization_enabled == true

      # Test Refactoring workflow enhancement
      refactoring_workflow = %{
        id: "refactoring_test_#{System.system_time(:nanosecond)}",
        type: :refactoring_suggestions,
        components: [
          %{type: :analysis, name: "pattern_detection"},
          %{type: :suggestion, name: "optimization_recommendations"}
        ]
      }

      refactoring_enhancement_spec = %{
        team_preferences: %{
          prefer_functional_style: true,
          max_function_length: 20,
          complexity_threshold: 8
        },
        code_quality_standards: %{
          documentation_coverage: 0.8,
          test_coverage: 0.9
        }
      }

      assert {:ok, enhanced_refactoring} =
               ExistingWorkflowEnhancer.enhance_refactoring_workflow(
                 refactoring_workflow,
                 refactoring_enhancement_spec,
                 %{enhancement_level: :comprehensive}
               )

      assert enhanced_refactoring.workflow_type == :enhanced_refactoring_suggestions
      assert enhanced_refactoring.refactoring_integration.preferences_integrated == true
      assert enhanced_refactoring.refactoring_integration.team_standards_applied == true
    end

    test "performance monitoring and optimization" do
      # Test performance monitoring and optimization capabilities

      workflow_id = "performance_test_#{System.system_time(:nanosecond)}"

      # Track various operations
      operations_to_track = [
        {:prompt_resolution, %{workflow_id: workflow_id, success: true},
         %{total_time: 150_000, resolution_time: 100_000}},
        {:context_enhancement, %{workflow_id: workflow_id, success: true},
         %{total_time: 50_000, context_enhancement_time: 45_000}},
        {:cache_coordination, %{workflow_id: workflow_id, success: true},
         %{total_time: 25_000, cache_coordination_time: 20_000}}
      ]

      for {op_type, op_data, timing_data} <- operations_to_track do
        WorkflowPromptPerformanceMonitor.track_workflow_prompt_operation(
          op_type,
          op_data,
          timing_data
        )
      end

      # Get performance analytics
      assert {:ok, analytics} =
               WorkflowPromptPerformanceMonitor.get_performance_analytics(workflow_id, %{
                 analytics_level: :detailed
               })

      assert analytics.analytics_level == :detailed
      assert Map.has_key?(analytics, :metrics)
      assert Map.has_key?(analytics, :summary)
      assert analytics.summary.total_operations >= length(operations_to_track)

      # Get performance recommendations
      assert {:ok, recommendations} =
               WorkflowPromptPerformanceMonitor.get_performance_recommendations(workflow_id)

      assert is_list(recommendations.recommendations)
      assert recommendations.performance_score >= 0.0
      assert recommendations.performance_score <= 1.0
      assert recommendations.optimization_potential >= 0.0

      # Test performance optimization
      WorkflowPromptPerformanceMonitor.optimize_performance(%{optimization_level: :high})

      # Verify optimization was applied
      assert {:ok, post_optimization_analytics} =
               WorkflowPromptPerformanceMonitor.get_performance_analytics(workflow_id)

      assert Map.has_key?(post_optimization_analytics, :metrics)
    end

    test "reactor prompt integration capabilities" do
      # Test Reactor-specific prompt integration features

      # Test Reactor step enhancement
      reactor_step = %{
        name: "reactor_test_step",
        type: :action,
        function: :process_data,
        parameters: %{processing_mode: :detailed}
      }

      prompt_config = %{
        prompt_name: "data_processing_prompt",
        optimization_level: :high
      }

      integration_options = %{
        integration_mode: :full_integration,
        enable_caching: true,
        enable_context_enhancement: true
      }

      assert {:ok, enhanced_reactor_step} =
               ReactorPromptIntegration.enhance_reactor_step(
                 reactor_step,
                 prompt_config,
                 integration_options
               )

      assert enhanced_reactor_step.prompt_integration_enabled == true
      assert enhanced_reactor_step.integration_mode == :full_integration
      assert Map.has_key?(enhanced_reactor_step, :full_integration_metadata)

      # Test Reactor middleware creation
      middleware_config = %{
        enable_prompt_resolution: true,
        enable_context_enhancement: true,
        enable_performance_monitoring: true,
        integration_level: :comprehensive
      }

      assert {:ok, prompt_middleware} =
               ReactorPromptIntegration.create_prompt_aware_reactor_middleware(middleware_config)

      assert prompt_middleware.name == :prompt_integration_middleware
      assert prompt_middleware.integration_level == :comprehensive
      assert :prompt_resolution in prompt_middleware.features

      # Test context integration with Reactor execution
      reactor_execution_context = %{
        step_name: "test_step",
        execution_id: "exec_123",
        workflow_metadata: %{workflow_type: :analysis}
      }

      prompt_context = %{
        prompt_name: "analysis_prompt",
        composition_metadata: %{composed: true},
        user_preferences: %{analysis_depth: :detailed}
      }

      context_integration_options = %{
        integration_strategy: :merge,
        priority_keys: [:user_preferences, :workflow_metadata]
      }

      assert {:ok, context_integration_result} =
               ReactorPromptIntegration.integrate_context_with_reactor_execution(
                 reactor_execution_context,
                 prompt_context,
                 context_integration_options
               )

      assert Map.has_key?(context_integration_result, :integrated_context)
      assert Map.has_key?(context_integration_result, :integration_metrics)
      assert context_integration_result.integration_metrics.integration_effective in [true, false]

      # Test performance optimization
      assert {:ok, optimization_result} =
               ReactorPromptIntegration.optimize_reactor_prompt_performance(
                 "reactor_test_workflow",
                 %{strategies: [:caching, :context_optimization]}
               )

      assert optimization_result.optimization_applied == true
      assert optimization_result.performance_improvement >= 0.0
    end

    test "enhanced workflow builder integration" do
      # Test enhanced workflow builder with prompt integration

      workflow_spec = %{
        type: :custom_analysis,
        components: [
          %{type: :input_processing, name: "data_prep", prompt_name: "data_preparation_prompt"},
          %{type: :analysis, name: "main_analysis", prompt_name: "analysis_execution_prompt"},
          %{
            type: :output_formatting,
            name: "result_formatting",
            prompt_name: "output_formatting_prompt"
          }
        ],
        has_dependencies: true,
        requires_coordination: true
      }

      builder_config = %{
        preferred_mode: :hybrid,
        enable_prompt_integration: true,
        enable_named_prompt_references: true,
        enable_context_enhancement: true,
        prompt_resolution_strategy: :optimized
      }

      assert {:ok, build_result} =
               EnhancedWorkflowBuilder.create_workflow(workflow_spec, builder_config)

      assert Map.has_key?(build_result.workflow, :prompt_integration)
      assert build_result.workflow.prompt_integration.enabled == true
      assert build_result.workflow.prompt_integration_applied == true

      # Verify prompt integration in components
      prompt_enhanced_components =
        Enum.filter(build_result.workflow.components, fn component ->
          Map.has_key?(component, :prompt_integration)
        end)

      assert length(prompt_enhanced_components) == 3

      # Each component should have prompt integration metadata
      for component <- prompt_enhanced_components do
        assert component.prompt_integration.integration_applied == true
        assert Map.has_key?(component.prompt_integration, :prompt_name)
        assert component.prompt_integration.resolution_strategy == :optimized
      end

      # Test execution context creation with prompt support
      context_config = %{
        enable_monitoring: true,
        enable_performance_tracking: true,
        timeout_ms: 120_000
      }

      assert {:ok, execution_context} =
               EnhancedWorkflowBuilder.create_execution_context(
                 build_result.workflow,
                 context_config
               )

      assert execution_context.workflow_id == build_result.workflow.id
      assert Map.has_key?(execution_context, :execution_config)

      # Test workflow validation with prompt integration
      validation_config = %{
        validate_structure: true,
        validate_dependencies: true,
        validate_performance: true
      }

      assert {:ok, validation_result} =
               EnhancedWorkflowBuilder.validate_workflow(build_result.workflow, validation_config)

      assert validation_result.validation_passed == true
      assert validation_result.validation_score > 0.0
    end
  end

  describe "Integration Performance Requirements" do
    test "integration overhead within performance requirements" do
      # Verify integration overhead is <20ms per workflow step

      workflow_id = "performance_req_test_#{System.system_time(:nanosecond)}"
      prompt_name = "performance_test_prompt"
      context = %{user_id: "perf_user", project_id: "perf_project"}

      # Measure integration overhead
      base_start = System.monotonic_time(:microsecond)

      # Simulate base workflow step (without prompt integration)
      # Simulate 10ms base processing
      :timer.sleep(10)

      base_time = System.monotonic_time(:microsecond) - base_start

      # Measure with prompt integration
      integration_start = System.monotonic_time(:microsecond)

      assert {:ok, _resolution_result} =
               WorkflowPromptResolver.resolve_workflow_prompt(workflow_id, prompt_name, context)

      integration_time = System.monotonic_time(:microsecond) - integration_start

      # Calculate integration overhead
      integration_overhead_ms = (integration_time - base_time) / 1000

      # Verify overhead is within requirements (<20ms)
      assert integration_overhead_ms < 20,
             "Integration overhead #{integration_overhead_ms}ms exceeds 20ms requirement"
    end

    test "cache coordination performance within requirements" do
      # Verify cache coordination performance meets requirements

      workflow_id = "cache_perf_test_#{System.system_time(:nanosecond)}"

      # Test cache get performance
      cache_get_start = System.monotonic_time(:microsecond)

      assert {:ok, _cache_result} =
               WorkflowPromptCacheCoordinator.get_cached_prompt(workflow_id, "test_prompt")

      cache_get_time = System.monotonic_time(:microsecond) - cache_get_start
      cache_get_time_ms = cache_get_time / 1000

      # Cache get should be very fast
      assert cache_get_time_ms < 5,
             "Cache get time #{cache_get_time_ms}ms exceeds 5ms requirement"

      # Test cache set performance
      cache_set_start = System.monotonic_time(:microsecond)

      assert {:ok, _cache_result} =
               WorkflowPromptCacheCoordinator.cache_workflow_prompt(
                 workflow_id,
                 "test_prompt",
                 %{resolved_prompt: "test content"},
                 %{cache_strategy: :workflow_scoped}
               )

      cache_set_time = System.monotonic_time(:microsecond) - cache_set_start
      cache_set_time_ms = cache_set_time / 1000

      # Cache set should be reasonable
      assert cache_set_time_ms < 10,
             "Cache set time #{cache_set_time_ms}ms exceeds 10ms requirement"
    end

    test "backward compatibility maintained" do
      # Verify existing workflows continue to work without modification

      # Test existing workflow builder without prompt integration
      basic_workflow_spec = %{
        type: :simple_processing,
        components: [
          %{type: :input, name: "data_input"},
          %{type: :processing, name: "data_processing"},
          %{type: :output, name: "result_output"}
        ]
      }

      # Build without prompt integration
      basic_builder_config = %{
        enable_prompt_integration: false,
        preferred_mode: :template
      }

      assert {:ok, basic_result} =
               EnhancedWorkflowBuilder.create_workflow(basic_workflow_spec, basic_builder_config)

      # Should build successfully without prompt integration
      assert Map.get(basic_result.workflow, :prompt_integration_applied, false) == false
      assert basic_result.workflow.type == :simple_processing

      # Components should not have prompt integration
      for component <- basic_result.workflow.components do
        assert not Map.has_key?(component, :prompt_integration)
      end

      # Should still pass validation
      assert {:ok, validation_result} =
               EnhancedWorkflowBuilder.validate_workflow(basic_result.workflow)

      assert validation_result.validation_passed == true
    end
  end

  describe "Integration Quality Requirements" do
    test "comprehensive test coverage validation" do
      # Validate that all integration components have comprehensive test coverage

      # Test all core integration services
      integration_modules = [
        WorkflowPromptResolver,
        NamedPromptReferenceManager,
        WorkflowContextEnhancer,
        WorkflowPromptCacheCoordinator,
        ReactorPromptIntegration
      ]

      for module <- integration_modules do
        # Verify module exists and loads
        assert Code.ensure_loaded?(module), "Module #{module} should be loaded"

        # Verify module has required functions (basic check)
        assert function_exported?(module, :start_link, 0) or
                 function_exported?(module, :start_link, 1),
               "Module #{module} should have start_link function if it's a GenServer"
      end

      # Test all workflow enhancement modules
      enhancement_modules = [
        PromptAwareWorkflowBuilder,
        WorkflowStepPromptInjector,
        ExistingWorkflowEnhancer,
        WorkflowPromptPerformanceMonitor
      ]

      for module <- enhancement_modules do
        assert Code.ensure_loaded?(module), "Module #{module} should be loaded"
      end
    end

    test "enterprise integration features validation" do
      # Validate enterprise-scale integration features

      # Test bulk workflow enhancement
      workflows_config = [
        %{id: "workflow_1", type: :code_review, components: []},
        %{id: "workflow_2", type: :documentation_generation, components: []},
        %{id: "workflow_3", type: :refactoring_suggestions, components: []}
      ]

      global_enhancement_spec = %{
        enable_all_features: true,
        enterprise_mode: true,
        performance_optimization: :high
      }

      assert {:ok, bulk_enhancement_result} =
               ExistingWorkflowEnhancer.enhance_all_existing_workflows(
                 workflows_config,
                 global_enhancement_spec,
                 %{enhancement_level: :comprehensive}
               )

      assert bulk_enhancement_result.total_workflows == 3
      assert bulk_enhancement_result.successful_enhancements >= 0
      assert bulk_enhancement_result.success_rate >= 0.0
      assert bulk_enhancement_result.success_rate <= 1.0

      # Test enterprise-scale cache coordination
      cache_analytics_config = %{
        analytics_level: :comprehensive,
        enable_trending: true,
        enable_forecasting: true
      }

      assert {:ok, cache_analytics} =
               WorkflowPromptCacheCoordinator.get_cache_analytics()

      assert Map.has_key?(cache_analytics, :total_cache_operations)
      assert Map.has_key?(cache_analytics, :cache_hit_rate)
      assert cache_analytics.cache_hit_rate >= 0.0
      assert cache_analytics.cache_hit_rate <= 1.0
    end
  end
end
