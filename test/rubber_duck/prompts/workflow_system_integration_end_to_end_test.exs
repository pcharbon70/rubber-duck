defmodule RubberDuck.Prompts.WorkflowSystemIntegrationEndToEndTest do
  use RubberDuck.DataCase, async: true

  alias RubberDuck.Prompts.Resources.{Prompt, PromptUsage}
  alias RubberDuck.Prompts.Services.{WorkflowPromptSelector, PromptUsageTracker}

  describe "Phase 6.2: Workflow System Integration - End-to-End Testing" do
    test "complete saved prompt selection and usage workflow in Reactor workflow contexts" do
      # Setup test data
      user_id = Ash.UUID.generate()
      project_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Step 1: Create workflow-specific prompt library
      {:ok, code_review_system_prompt} =
        Prompt.create_system_prompt(%{
          content:
            "Review the {{code_component}} for {{review_focus}} issues. Consider {{team_standards}} when evaluating.",
          name: "code_review_system_template",
          tenant_id: tenant_id,
          description: "System-wide code review template for workflow steps"
        })

      {:ok, documentation_project_prompt} =
        Prompt.create_project_prompt(%{
          content:
            "Generate {{doc_type}} documentation for {{component_name}}. Target audience: {{target_audience}}.",
          name: "project_documentation_template",
          tenant_id: tenant_id,
          project_id: project_id,
          description: "Project-specific documentation generation template"
        })

      {:ok, testing_user_prompt} =
        Prompt.create_user_prompt(%{
          content:
            "Create {{test_type}} tests for {{function_name}} covering {{test_scenarios}}. Use {{test_framework}}.",
          name: "user_testing_template",
          tenant_id: tenant_id,
          user_id: user_id,
          description: "Personal testing prompt for workflow automation"
        })

      # Step 2: Test workflow context-aware prompt selection
      code_review_context = %{
        workflow_type: :code_review,
        step_name: "quality_analysis_step",
        project_id: project_id,
        workflow_id: "test_workflow_#{System.system_time(:nanosecond)}"
      }

      assert {:ok, code_review_suitable} =
               WorkflowPromptSelector.get_workflow_suitable_prompts(user_id, code_review_context)

      # Should include all prompts but rank code review related higher
      assert code_review_suitable.workflow_optimized == true
      assert code_review_suitable.workflow_type == :code_review
      assert code_review_suitable.total_count >= 3

      # Code review prompt should have high workflow relevance
      system_prompts = code_review_suitable.system_prompts

      code_review_prompt =
        Enum.find(system_prompts, fn p -> p.id == code_review_system_prompt.id end)

      assert code_review_prompt != nil
      assert Map.has_key?(code_review_prompt, :workflow_relevance_score)

      # Step 3: Test workflow-aware search functionality
      assert {:ok, review_search_results} =
               WorkflowPromptSelector.search_workflow_prompts(
                 user_id,
                 "review",
                 code_review_context
               )

      # Should find review-related prompts with workflow relevance ranking
      assert length(review_search_results) >= 1

      for prompt <- review_search_results do
        assert Map.has_key?(prompt, :combined_relevance_score)

        assert String.contains?(prompt.name, "review") or
                 String.contains?(prompt.content, "review")
      end

      # Step 4: Test step-specific prompt recommendations
      assert {:ok, analysis_recommendations} =
               WorkflowPromptSelector.get_recommended_prompts_for_step(
                 user_id,
                 :analysis,
                 code_review_context
               )

      assert analysis_recommendations.step_type == :analysis
      assert analysis_recommendations.recommendation_count >= 0

      # Step 5: Test workflow context variable extraction and substitution
      documentation_context = %{
        workflow_type: :documentation,
        step_name: "api_doc_generation",
        project_id: project_id,
        doc_type: "API reference",
        component_name: "UserService",
        target_audience: "developers"
      }

      assert {:ok, available_variables} =
               WorkflowPromptSelector.get_available_workflow_variables(documentation_context)

      # Should include both base workflow variables and workflow-specific variables
      assert Map.has_key?(available_variables, "workflow_type")
      assert Map.has_key?(available_variables, "step_name")
      assert Map.has_key?(available_variables, "doc_type")
      assert available_variables["workflow_type"].value == "documentation"
      assert available_variables["doc_type"].value == "API reference"

      # Step 6: Test prompt preparation for workflow execution
      workflow_variable_values = %{
        "component_name" => "UserAuthService",
        "target_audience" => "frontend developers"
      }

      assert {:ok, preparation_result} =
               WorkflowPromptSelector.prepare_prompt_for_workflow(
                 documentation_project_prompt.content,
                 documentation_context,
                 workflow_variable_values
               )

      # Variables should be substituted with workflow context and user values
      assert String.contains?(preparation_result.prepared_content, "UserAuthService")
      assert String.contains?(preparation_result.prepared_content, "frontend developers")
      assert String.contains?(preparation_result.prepared_content, "API reference")
      assert preparation_result.workflow_context_applied == true

      # Template variables should be substituted
      assert not String.contains?(preparation_result.prepared_content, "{{component_name}}")
      assert not String.contains?(preparation_result.prepared_content, "{{doc_type}}")

      # Step 7: Test testing workflow context and variables
      testing_context = %{
        workflow_type: :testing,
        step_name: "unit_test_generation",
        project_id: project_id,
        test_type: "unit",
        test_framework: "ExUnit"
      }

      testing_variable_values = %{
        "function_name" => "calculate_user_score",
        "test_scenarios" => "valid input, edge cases, error conditions"
      }

      assert {:ok, testing_preparation} =
               WorkflowPromptSelector.prepare_prompt_for_workflow(
                 testing_user_prompt.content,
                 testing_context,
                 testing_variable_values
               )

      # Should substitute both workflow context and user variables
      # From workflow context
      assert String.contains?(testing_preparation.prepared_content, "unit")
      # From workflow context
      assert String.contains?(testing_preparation.prepared_content, "ExUnit")
      # From user variables
      assert String.contains?(testing_preparation.prepared_content, "calculate_user_score")
      # From user variables
      assert String.contains?(testing_preparation.prepared_content, "valid input, edge cases")

      # Step 8: Test workflow prompt usage tracking
      workflow_usage_context = %{
        usage_type: :workflow_step,
        workflow_id: code_review_context.workflow_id,
        step_id: code_review_context.step_name,
        workflow_type: code_review_context.workflow_type
      }

      workflow_usage_metadata = %{
        workflow_integration: true,
        step_configured: true,
        context_variables_used: true,
        prompt_preparation_successful: true
      }

      # Track usage of code review prompt in workflow context
      PromptUsageTracker.track_llm_usage(
        user_id,
        code_review_system_prompt.id,
        workflow_usage_context,
        workflow_usage_metadata
      )

      # Allow time for async tracking
      Process.sleep(100)

      # Step 9: Test workflow-specific usage analytics
      assert {:ok, workflow_usage_stats} =
               PromptUsageTracker.get_prompt_usage_stats(code_review_system_prompt.id, user_id)

      assert workflow_usage_stats.total_uses >= 1

      # Test user analytics with workflow context
      assert {:ok, user_workflow_analytics} = PromptUsageTracker.get_user_usage_analytics(user_id)

      assert user_workflow_analytics.total_usage_count >= 1
      assert Map.has_key?(user_workflow_analytics, :usage_by_type)

      # Step 10: Test performance requirements for workflow integration
      # Test prompt selection performance in workflow context
      workflow_selection_start = System.monotonic_time(:microsecond)

      assert {:ok, _workflow_prompts} =
               WorkflowPromptSelector.get_workflow_suitable_prompts(user_id, code_review_context)

      workflow_selection_time = System.monotonic_time(:microsecond) - workflow_selection_start
      workflow_selection_time_ms = workflow_selection_time / 1000

      # Should maintain Section 6.1 performance standards
      assert workflow_selection_time_ms < 250,
             "Workflow prompt selection #{workflow_selection_time_ms}ms exceeds 250ms target"

      # Test workflow search performance
      workflow_search_start = System.monotonic_time(:microsecond)

      assert {:ok, _search_results} =
               WorkflowPromptSelector.search_workflow_prompts(
                 user_id,
                 "review",
                 code_review_context
               )

      workflow_search_time = System.monotonic_time(:microsecond) - workflow_search_start
      workflow_search_time_ms = workflow_search_time / 1000

      # Should maintain search performance with workflow context
      assert workflow_search_time_ms < 200,
             "Workflow search #{workflow_search_time_ms}ms exceeds 200ms requirement"

      # Final integration validation
      assert is_binary(user_id)
      assert is_binary(project_id)
      assert preparation_result.variables_substituted > 0
    end

    test "workflow context variable extraction and substitution" do
      # Test comprehensive workflow context variable handling

      user_id = Ash.UUID.generate()
      project_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Create prompt with complex variable structure
      {:ok, complex_prompt} =
        Prompt.create_user_prompt(%{
          content: """
          Workflow: {{workflow_type}}
          Step: {{step_name}}
          Project: {{project_id}}
          Custom Analysis: {{analysis_type}}
          Focus Areas: {{focus_areas}}
          Quality Threshold: {{quality_threshold|0.8}}
          """,
          name: "complex_workflow_template",
          tenant_id: tenant_id,
          user_id: user_id
        })

      # Create comprehensive workflow context
      complex_workflow_context = %{
        workflow_type: :code_review,
        step_name: "comprehensive_quality_analysis",
        project_id: project_id,
        workflow_id: "complex_workflow_#{System.system_time(:nanosecond)}",
        custom_variables: %{
          "analysis_type" => "security and performance",
          "focus_areas" => "authentication, data validation, performance optimization"
        }
      }

      # Test variable extraction
      assert {:ok, available_variables} =
               WorkflowPromptSelector.get_available_workflow_variables(complex_workflow_context)

      # Should include base workflow variables
      assert Map.has_key?(available_variables, "workflow_type")
      assert Map.has_key?(available_variables, "step_name")
      assert Map.has_key?(available_variables, "project_id")

      # Should include custom variables
      assert Map.has_key?(available_variables, "analysis_type")
      assert Map.has_key?(available_variables, "focus_areas")

      # Variable metadata should be informative
      assert available_variables["workflow_type"].source == :workflow_context
      assert available_variables["analysis_type"].type == :string

      # Test complex variable substitution
      user_variable_values = %{
        # Override default
        "quality_threshold" => "0.9"
      }

      assert {:ok, complex_preparation} =
               WorkflowPromptSelector.prepare_prompt_for_workflow(
                 complex_prompt.content,
                 complex_workflow_context,
                 user_variable_values
               )

      # All variables should be substituted
      prepared_content = complex_preparation.prepared_content

      # workflow_type
      assert String.contains?(prepared_content, "code_review")
      # step_name
      assert String.contains?(prepared_content, "comprehensive_quality_analysis")
      # project_id
      assert String.contains?(prepared_content, project_id)
      # analysis_type
      assert String.contains?(prepared_content, "security and performance")
      # focus_areas
      assert String.contains?(prepared_content, "authentication, data validation")
      # quality_threshold (user override)
      assert String.contains?(prepared_content, "0.9")

      # No template variables should remain
      assert not String.contains?(prepared_content, "{{")
      assert not String.contains?(prepared_content, "}}")

      # Metadata should indicate successful preparation
      assert complex_preparation.workflow_context_applied == true
      assert complex_preparation.variables_substituted >= 5
      assert Map.has_key?(complex_preparation.workflow_metadata, :workflow_type)
    end

    test "workflow step recommendations and context awareness" do
      # Test step-specific recommendations and context awareness

      user_id = Ash.UUID.generate()
      project_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Create prompts for different step types
      {:ok, analysis_prompt} =
        Prompt.create_user_prompt(%{
          content:
            "Analyze the code structure and identify potential issues in {{component_name}}",
          name: "code_analysis_prompt",
          tenant_id: tenant_id,
          user_id: user_id,
          description: "Analysis-focused prompt for code evaluation"
        })

      {:ok, generation_prompt} =
        Prompt.create_user_prompt(%{
          content:
            "Generate comprehensive {{output_type}} for {{input_component}} following {{style_guide}}",
          name: "content_generation_prompt",
          tenant_id: tenant_id,
          user_id: user_id,
          description: "Generation-focused prompt for content creation"
        })

      {:ok, validation_prompt} =
        Prompt.create_user_prompt(%{
          content:
            "Validate {{validation_target}} against {{validation_criteria}} and verify {{compliance_requirements}}",
          name: "validation_checkpoint_prompt",
          tenant_id: tenant_id,
          user_id: user_id,
          description: "Validation-focused prompt for quality assurance"
        })

      # Test analysis step recommendations
      analysis_context = %{
        workflow_type: :code_review,
        step_name: "code_analysis_step",
        project_id: project_id
      }

      assert {:ok, analysis_recommendations} =
               WorkflowPromptSelector.get_recommended_prompts_for_step(
                 user_id,
                 :analysis,
                 analysis_context
               )

      # Should recommend analysis-focused prompts
      analysis_prompt_ids =
        Enum.map(analysis_recommendations.recommended_prompts, fn p -> p.id end)

      assert analysis_prompt.id in analysis_prompt_ids

      # Analysis prompt should have high step relevance
      recommended_analysis =
        Enum.find(analysis_recommendations.recommended_prompts, fn p ->
          p.id == analysis_prompt.id
        end)

      assert recommended_analysis.step_relevance_score > 0.5

      # Test generation step recommendations
      documentation_context = %{
        workflow_type: :documentation,
        step_name: "doc_generation_step",
        project_id: project_id
      }

      assert {:ok, generation_recommendations} =
               WorkflowPromptSelector.get_recommended_prompts_for_step(
                 user_id,
                 :generation,
                 documentation_context
               )

      # Should recommend generation-focused prompts
      generation_prompt_ids =
        Enum.map(generation_recommendations.recommended_prompts, fn p -> p.id end)

      assert generation_prompt.id in generation_prompt_ids

      # Test validation step recommendations
      testing_context = %{
        workflow_type: :testing,
        step_name: "test_validation_step",
        project_id: project_id
      }

      assert {:ok, validation_recommendations} =
               WorkflowPromptSelector.get_recommended_prompts_for_step(
                 user_id,
                 :validation,
                 testing_context
               )

      # Should recommend validation-focused prompts
      validation_prompt_ids =
        Enum.map(validation_recommendations.recommended_prompts, fn p -> p.id end)

      assert validation_prompt.id in validation_prompt_ids
    end

    test "workflow-specific search with relevance ranking" do
      # Test workflow-aware search with proper relevance ranking

      user_id = Ash.UUID.generate()
      project_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Create prompts with different workflow relevance levels
      {:ok, high_relevance_prompt} =
        Prompt.create_user_prompt(%{
          content:
            "Comprehensive code review focusing on security vulnerabilities and performance optimization",
          name: "security_performance_code_review",
          tenant_id: tenant_id,
          user_id: user_id,
          description: "High-relevance code review prompt"
        })

      {:ok, medium_relevance_prompt} =
        Prompt.create_user_prompt(%{
          content:
            "Review the implementation for basic code quality and readability improvements",
          name: "basic_code_review",
          tenant_id: tenant_id,
          user_id: user_id,
          description: "Medium-relevance code review prompt"
        })

      {:ok, low_relevance_prompt} =
        Prompt.create_user_prompt(%{
          content:
            "Generate documentation for the user interface components and styling guidelines",
          name: "ui_documentation_prompt",
          tenant_id: tenant_id,
          user_id: user_id,
          description: "Low-relevance prompt for code review context"
        })

      # Test search in code review workflow context
      code_review_context = %{
        workflow_type: :code_review,
        step_name: "security_review_step",
        project_id: project_id
      }

      assert {:ok, code_review_search} =
               WorkflowPromptSelector.search_workflow_prompts(
                 user_id,
                 "review",
                 code_review_context
               )

      # Should find all review-related prompts
      search_prompt_ids = Enum.map(code_review_search, fn p -> p.id end)
      assert high_relevance_prompt.id in search_prompt_ids
      assert medium_relevance_prompt.id in search_prompt_ids

      # Should rank by combined relevance (search + workflow context)
      relevance_scores =
        Enum.map(code_review_search, fn prompt ->
          {prompt.id, prompt.combined_relevance_score}
        end)
        |> Map.new()

      # High relevance prompt should score higher than medium relevance
      if Map.has_key?(relevance_scores, high_relevance_prompt.id) and
           Map.has_key?(relevance_scores, medium_relevance_prompt.id) do
        assert relevance_scores[high_relevance_prompt.id] >
                 relevance_scores[medium_relevance_prompt.id]
      end

      # Test search in documentation workflow context
      documentation_context = %{
        workflow_type: :documentation,
        step_name: "user_guide_creation",
        project_id: project_id
      }

      assert {:ok, doc_search} =
               WorkflowPromptSelector.search_workflow_prompts(
                 user_id,
                 "documentation",
                 documentation_context
               )

      # Documentation-related prompts should rank higher in documentation context
      doc_prompt_ids = Enum.map(doc_search, fn p -> p.id end)
      # UI documentation prompt should be found
      assert low_relevance_prompt.id in doc_prompt_ids
    end

    test "performance validation with workflow integration overhead" do
      # Test performance requirements with workflow integration

      user_id = Ash.UUID.generate()
      project_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Create realistic workflow prompt collection
      workflow_prompts =
        for i <- 1..200 do
          workflow_type =
            Enum.random([:code_review, :documentation, :testing, :refactoring, :debugging])

          {:ok, prompt} =
            Prompt.create_user_prompt(%{
              content:
                "Workflow prompt #{i} for #{workflow_type} with {{parameter_#{i}}} and {{context_#{i}}}",
              name: "workflow_prompt_#{workflow_type}_#{i}",
              tenant_id: tenant_id,
              user_id: user_id,
              description: "#{workflow_type} workflow prompt for performance testing"
            })

          prompt
        end

      # Test workflow-suitable prompts performance
      performance_context = %{
        workflow_type: :code_review,
        step_name: "performance_test_step",
        project_id: project_id
      }

      workflow_suitable_start = System.monotonic_time(:microsecond)

      assert {:ok, suitable_prompts} =
               WorkflowPromptSelector.get_workflow_suitable_prompts(user_id, performance_context)

      workflow_suitable_time = System.monotonic_time(:microsecond) - workflow_suitable_start
      workflow_suitable_time_ms = workflow_suitable_time / 1000

      # Should filter and optimize prompts efficiently
      assert workflow_suitable_time_ms < 300,
             "Workflow suitable prompts #{workflow_suitable_time_ms}ms exceeds 300ms target"

      assert suitable_prompts.total_count > 0

      # Test workflow search performance with large collection
      workflow_search_start = System.monotonic_time(:microsecond)

      assert {:ok, search_results} =
               WorkflowPromptSelector.search_workflow_prompts(
                 user_id,
                 "code_review",
                 performance_context
               )

      workflow_search_time = System.monotonic_time(:microsecond) - workflow_search_start
      workflow_search_time_ms = workflow_search_time / 1000

      # Should maintain search performance with workflow ranking
      assert workflow_search_time_ms < 250,
             "Workflow search #{workflow_search_time_ms}ms exceeds 250ms target"

      assert length(search_results) > 0

      # Test step recommendations performance  
      step_recommendations_start = System.monotonic_time(:microsecond)

      assert {:ok, step_recs} =
               WorkflowPromptSelector.get_recommended_prompts_for_step(
                 user_id,
                 :analysis,
                 performance_context
               )

      step_recommendations_time = System.monotonic_time(:microsecond) - step_recommendations_start
      step_recommendations_time_ms = step_recommendations_time / 1000

      # Should provide recommendations efficiently
      assert step_recommendations_time_ms < 150,
             "Step recommendations #{step_recommendations_time_ms}ms exceeds 150ms target"

      # Test variable extraction and substitution performance
      variable_substitution_start = System.monotonic_time(:microsecond)

      sample_prompt = List.first(workflow_prompts)

      assert {:ok, _preparation_result} =
               WorkflowPromptSelector.prepare_prompt_for_workflow(
                 sample_prompt.content,
                 performance_context,
                 %{"parameter_1" => "test_value", "context_1" => "test_context"}
               )

      variable_substitution_time =
        System.monotonic_time(:microsecond) - variable_substitution_start

      variable_substitution_time_ms = variable_substitution_time / 1000

      # Variable substitution should be fast
      assert variable_substitution_time_ms < 50,
             "Variable substitution #{variable_substitution_time_ms}ms exceeds 50ms target"
    end

    test "workflow integration with Section 6.1 infrastructure reuse" do
      # Test that Section 6.2 properly reuses and extends Section 6.1 infrastructure

      user_id = Ash.UUID.generate()
      project_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      {:ok, shared_prompt} =
        Prompt.create_user_prompt(%{
          content:
            "Shared prompt for both LLM operations and workflow steps with {{shared_variable}}",
          name: "shared_llm_workflow_prompt",
          tenant_id: tenant_id,
          user_id: user_id
        })

      # Test that WorkflowPromptSelector uses LlmPromptSelector infrastructure
      workflow_context = %{
        workflow_type: :general,
        step_name: "shared_functionality_test",
        project_id: project_id
      }

      # Should reuse caching from Section 6.1
      assert {:ok, workflow_prompts} =
               WorkflowPromptSelector.get_workflow_suitable_prompts(user_id, workflow_context)

      workflow_prompt_ids =
        (workflow_prompts.user_prompts || [])
        |> Enum.map(fn p -> p.id end)

      assert shared_prompt.id in workflow_prompt_ids

      # Test that same prompt can be used in both LLM and workflow contexts
      # LLM context (from Section 6.1)
      llm_context = %{
        llm_provider: "gpt-4",
        operation_type: :general_assistance
      }

      PromptUsageTracker.track_llm_usage(user_id, shared_prompt.id, llm_context, %{success: true})

      # Workflow context (from Section 6.2)
      workflow_usage_context = %{
        usage_type: :workflow_step,
        workflow_type: :general,
        step_name: "shared_test"
      }

      PromptUsageTracker.track_llm_usage(user_id, shared_prompt.id, workflow_usage_context, %{
        workflow_integration: true
      })

      # Allow tracking to process
      Process.sleep(100)

      # Should track usage in both contexts
      assert {:ok, shared_usage_stats} =
               PromptUsageTracker.get_prompt_usage_stats(shared_prompt.id, user_id)

      # Both LLM and workflow usage
      assert shared_usage_stats.total_uses >= 2
    end

    test "backward compatibility with existing workflow patterns" do
      # Test that workflow integration doesn't break existing workflow functionality

      user_id = Ash.UUID.generate()
      project_id = Ash.UUID.generate()

      # Test workflow context creation without prompt selection
      basic_workflow_context = %{
        workflow_type: :general,
        step_name: "basic_step",
        project_id: project_id
      }

      # Should work without any saved prompts
      assert {:ok, empty_prompts} =
               WorkflowPromptSelector.get_workflow_suitable_prompts(
                 user_id,
                 basic_workflow_context
               )

      # Should handle empty prompt library gracefully
      assert empty_prompts.total_count == 0
      assert empty_prompts.workflow_optimized == true

      # Should provide empty recommendations without errors
      assert {:ok, empty_recommendations} =
               WorkflowPromptSelector.get_recommended_prompts_for_step(
                 user_id,
                 :analysis,
                 basic_workflow_context
               )

      assert empty_recommendations.recommendation_count == 0

      # Should handle variable extraction from workflow context even without prompts
      assert {:ok, context_variables} =
               WorkflowPromptSelector.get_available_workflow_variables(basic_workflow_context)

      # Should still provide base workflow variables
      assert Map.has_key?(context_variables, "workflow_type")
      assert Map.has_key?(context_variables, "step_name")
      assert context_variables["workflow_type"].value == "general"
    end
  end

  describe "Integration Quality Requirements" do
    test "comprehensive workflow integration component validation" do
      # Validate all workflow integration components

      # Test workflow prompt selector service
      assert Code.ensure_loaded?(WorkflowPromptSelector),
             "WorkflowPromptSelector should be loaded"

      # Test workflow components
      workflow_components = [
        RubberDuckWeb.Live.Components.WorkflowPromptBrowserComponent,
        RubberDuckWeb.Live.Workflows.WorkflowStepConfigurationLive
      ]

      for component <- workflow_components do
        assert Code.ensure_loaded?(component), "Component #{component} should be loaded"
      end
    end

    test "workflow integration maintains Section 6.1 performance standards" do
      # Validate that workflow integration doesn't degrade Section 6.1 performance

      user_id = Ash.UUID.generate()
      project_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Create moderate-sized prompt collection
      for i <- 1..100 do
        {:ok, _prompt} =
          Prompt.create_user_prompt(%{
            content: "Performance test prompt #{i} with workflow context support",
            name: "workflow_perf_prompt_#{i}",
            tenant_id: tenant_id,
            user_id: user_id
          })
      end

      workflow_context = %{
        workflow_type: :performance_testing,
        step_name: "performance_validation",
        project_id: project_id
      }

      # Test that workflow-suitable prompts maintains performance
      workflow_perf_start = System.monotonic_time(:microsecond)

      assert {:ok, _workflow_prompts} =
               WorkflowPromptSelector.get_workflow_suitable_prompts(user_id, workflow_context)

      workflow_perf_time = System.monotonic_time(:microsecond) - workflow_perf_start
      workflow_perf_time_ms = workflow_perf_time / 1000

      # Should maintain Section 6.1 performance standards even with workflow optimization
      assert workflow_perf_time_ms < 300,
             "Workflow prompt selection #{workflow_perf_time_ms}ms degrades Section 6.1 performance"

      # Test that workflow search doesn't significantly impact performance
      workflow_search_perf_start = System.monotonic_time(:microsecond)

      assert {:ok, _search_results} =
               WorkflowPromptSelector.search_workflow_prompts(
                 user_id,
                 "performance",
                 workflow_context
               )

      workflow_search_perf_time = System.monotonic_time(:microsecond) - workflow_search_perf_start
      workflow_search_perf_time_ms = workflow_search_perf_time / 1000

      # Workflow search should maintain Section 6.1 performance with additional ranking
      assert workflow_search_perf_time_ms < 250,
             "Workflow search #{workflow_search_perf_time_ms}ms degrades Section 6.1 performance"
    end
  end
end
