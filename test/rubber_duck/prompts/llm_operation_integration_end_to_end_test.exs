defmodule RubberDuck.Prompts.LlmOperationIntegrationEndToEndTest do
  use RubberDuck.DataCase, async: true

  alias RubberDuck.Prompts.Resources.{Prompt, PromptUsage}
  alias RubberDuck.Prompts.Services.{LlmPromptSelector, PromptUsageTracker}
  alias RubberDuck.Prompts.Integrations.PromptVariableSubstitution

  describe "Phase 6.1: LLM Operation Integration - End-to-End Testing" do
    test "complete saved prompt selection and usage workflow in LLM operations" do
      # Setup test data
      user_id = Ash.UUID.generate()
      project_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Step 1: Create comprehensive prompt library across three tiers
      {:ok, system_prompt} =
        Prompt.create_system_prompt(%{
          content:
            "Analyze the provided {{code_type}} code for {{analysis_focus}} issues. Provide detailed recommendations.",
          name: "code_analysis_system_template",
          tenant_id: tenant_id,
          description: "System-wide code analysis template with variables"
        })

      {:ok, project_prompt} =
        Prompt.create_project_prompt(%{
          content:
            "Review {{code_component}} following our team standards: {{team_standards}}. Focus on {{quality_aspects}}.",
          name: "team_code_review_prompt",
          tenant_id: tenant_id,
          project_id: project_id,
          description: "Project-specific code review prompt with team standards"
        })

      {:ok, user_prompt} =
        Prompt.create_user_prompt(%{
          content:
            "Help me understand {{concept}} in the context of {{application_domain}}. Explain with practical examples.",
          name: "concept_learning_prompt",
          tenant_id: tenant_id,
          user_id: user_id,
          description: "Personal learning prompt for concept understanding"
        })

      # Step 2: Test three-tier prompt access in LLM operations
      assert {:ok, available_prompts} =
               LlmPromptSelector.get_available_prompts(user_id, project_id)

      # Should have prompts from all three tiers
      assert length(available_prompts.system_prompts) >= 1
      assert length(available_prompts.project_prompts) >= 1
      assert length(available_prompts.user_prompts) >= 1
      assert available_prompts.total_count >= 3

      # Verify specific prompts are accessible
      all_prompt_ids = extract_all_prompt_ids(available_prompts)
      assert system_prompt.id in all_prompt_ids
      assert project_prompt.id in all_prompt_ids
      assert user_prompt.id in all_prompt_ids

      # Step 3: Test prompt search functionality for LLM operations
      # Search for code-related prompts
      assert {:ok, code_search_results} =
               LlmPromptSelector.search_prompts(user_id, "code", project_id)

      # Should find prompts with "code" in name or content
      # system and project prompts contain "code"
      assert length(code_search_results) >= 2

      # Results should be ranked by relevance
      for prompt <- code_search_results do
        assert Map.has_key?(prompt, :relevance_score)
        assert prompt.relevance_score > 0.0
      end

      # Step 4: Test template variable extraction and substitution
      # Test system prompt variables
      assert {:ok, system_variables} =
               PromptVariableSubstitution.extract_template_variables(system_prompt.content)

      assert Map.has_key?(system_variables, "code_type")
      assert Map.has_key?(system_variables, "analysis_focus")

      # Test variable substitution
      variable_values = %{
        "code_type" => "Elixir",
        "analysis_focus" => "performance"
      }

      assert {:ok, substituted_system} =
               PromptVariableSubstitution.substitute_variables(
                 system_prompt.content,
                 variable_values
               )

      # Variables should be substituted
      assert String.contains?(substituted_system, "Elixir")
      assert String.contains?(substituted_system, "performance")
      assert not String.contains?(substituted_system, "{{code_type}}")

      # Step 5: Test project prompt with more complex variables
      project_variable_values = %{
        "code_component" => "UserService",
        "team_standards" => "functional programming principles",
        "quality_aspects" => "performance and maintainability"
      }

      assert {:ok, substituted_project} =
               PromptVariableSubstitution.substitute_variables(
                 project_prompt.content,
                 project_variable_values
               )

      assert String.contains?(substituted_project, "UserService")
      assert String.contains?(substituted_project, "functional programming principles")

      # Step 6: Test user prompt variable substitution
      user_variable_values = %{
        "concept" => "GenServer supervision trees",
        "application_domain" => "distributed systems"
      }

      assert {:ok, substituted_user} =
               PromptVariableSubstitution.substitute_variables(
                 user_prompt.content,
                 user_variable_values
               )

      assert String.contains?(substituted_user, "GenServer supervision trees")
      assert String.contains?(substituted_user, "distributed systems")

      # Step 7: Test usage tracking in LLM operations context
      llm_context = %{
        llm_provider: "gpt-4",
        operation_type: :code_analysis,
        request_id: Ash.UUID.generate()
      }

      usage_metadata = %{
        success: true,
        response_quality: 0.85,
        tokens_used: 150,
        response_time_ms: 2500
      }

      # Track usage of system prompt in LLM operation
      PromptUsageTracker.track_llm_usage(user_id, system_prompt.id, llm_context, usage_metadata)

      # Track usage of user prompt
      PromptUsageTracker.track_llm_usage(user_id, user_prompt.id, llm_context, usage_metadata)

      # Step 8: Test prompt selection tracking
      selection_context = %{
        interface: :prompt_browser,
        search_query: "code",
        selection_method: :search_result
      }

      PromptUsageTracker.track_prompt_selection(user_id, system_prompt.id, selection_context)

      # Step 9: Test recent prompts functionality
      # Allow time for usage tracking to be processed
      Process.sleep(100)

      assert {:ok, recent_prompts} = LlmPromptSelector.get_recent_prompts(user_id, project_id, 10)

      # Should include recently used prompts
      recent_prompt_ids = Enum.map(recent_prompts, fn prompt -> prompt.id end)
      assert system_prompt.id in recent_prompt_ids
      assert user_prompt.id in recent_prompt_ids

      # Step 10: Test usage analytics retrieval
      assert {:ok, usage_stats} =
               PromptUsageTracker.get_prompt_usage_stats(system_prompt.id, user_id)

      assert Map.has_key?(usage_stats, :total_uses)
      assert Map.has_key?(usage_stats, :last_used)
      assert usage_stats.total_uses >= 1

      # Test user analytics
      assert {:ok, user_analytics} = PromptUsageTracker.get_user_usage_analytics(user_id)

      assert user_analytics.user_id == user_id
      # System + user prompt usage
      assert user_analytics.total_usage_count >= 2
      assert user_analytics.unique_prompts_used >= 2

      # Step 11: Test variable validation and security
      # Test safe variable substitution
      safe_variables = %{
        "safe_variable" => "safe value",
        "another_var" => "another safe value"
      }

      safe_content = "Test prompt with {{safe_variable}} and {{another_var}}"

      assert {:ok, safe_result} =
               PromptVariableSubstitution.substitute_variables(safe_content, safe_variables)

      assert String.contains?(safe_result, "safe value")

      # Test variable validation catches unsafe content
      unsafe_variables = %{
        "script_injection" => "<script>alert('test')</script>"
      }

      unsafe_content = "Test prompt with {{script_injection}}"

      # Should either sanitize or reject unsafe content
      case PromptVariableSubstitution.substitute_variables(unsafe_content, unsafe_variables) do
        {:ok, sanitized_result} ->
          # If substitution succeeds, content should be sanitized
          assert not String.contains?(sanitized_result, "<script>")

        {:error, _reason} ->
          # If substitution fails, that's also acceptable for security
          assert true
      end

      # Step 12: Test performance requirements validation
      # Create larger prompt collection for performance testing
      for i <- 1..100 do
        {:ok, _prompt} =
          Prompt.create_user_prompt(%{
            content: "Performance test prompt #{i} for load testing",
            name: "perf_test_prompt_#{i}",
            tenant_id: tenant_id,
            user_id: user_id
          })
      end

      # Test search performance with larger collection
      search_start = System.monotonic_time(:microsecond)

      assert {:ok, _large_search_results} =
               LlmPromptSelector.search_prompts(user_id, "performance", project_id)

      search_time = System.monotonic_time(:microsecond) - search_start
      search_time_ms = search_time / 1000

      # Should meet <200ms requirement even with larger collection
      assert search_time_ms < 200, "Search time #{search_time_ms}ms exceeds 200ms requirement"

      # Test prompt retrieval performance
      retrieval_start = System.monotonic_time(:microsecond)

      assert {:ok, _large_collection} =
               LlmPromptSelector.get_available_prompts(user_id, project_id)

      retrieval_time = System.monotonic_time(:microsecond) - retrieval_start
      retrieval_time_ms = retrieval_time / 1000

      # Should retrieve prompts efficiently
      assert retrieval_time_ms < 300,
             "Prompt retrieval time #{retrieval_time_ms}ms exceeds 300ms target"

      # Final assertion: Integration is complete and functional
      assert is_binary(user_id)
      assert is_binary(project_id)
      assert length(recent_prompts) > 0
    end

    test "template variable security validation" do
      # Test comprehensive template variable security

      # Test valid template content
      valid_content =
        "Process {{data_input}} and generate {{output_format}} results for {{target_audience}}."

      assert {:ok, validation_result} =
               PromptVariableSubstitution.validate_template_variables(valid_content)

      assert validation_result.safe == true
      assert validation_result.valid_syntax == true
      assert validation_result.variable_count == 3

      # Test content with forbidden patterns
      forbidden_contents = [
        "Execute {{system}} command",
        "Run {{exec}} operation",
        "Evaluate {{eval}} expression",
        "Load <script>alert('test')</script>"
      ]

      for forbidden_content <- forbidden_contents do
        case PromptVariableSubstitution.validate_template_variables(forbidden_content) do
          {:ok, result} ->
            # If validation passes, should mark as unsafe
            assert result.safe == false

          {:error, {:unsafe_content, _reason}} ->
            # Expected: validation should catch unsafe content
            assert true

          {:error, _other_reason} ->
            # Other validation errors are also acceptable
            assert true
        end
      end

      # Test variable extraction
      complex_template =
        "Hello {{user_name|Anonymous}}, please {{action_verb}} the {{object_type|document}} for {{purpose}}."

      assert {:ok, extracted_vars} =
               PromptVariableSubstitution.extract_template_variables(complex_template)

      # Should extract all variables with their metadata
      assert Map.has_key?(extracted_vars, "user_name")
      assert Map.has_key?(extracted_vars, "action_verb")
      assert Map.has_key?(extracted_vars, "object_type")
      assert Map.has_key?(extracted_vars, "purpose")

      # Variables with defaults should be marked as not required
      assert extracted_vars["user_name"].default == "Anonymous"
      assert extracted_vars["object_type"].default == "document"
    end

    test "cross-tier access control validation" do
      # Test that three-tier access control works correctly in LLM operations

      # Create separate users and projects for isolation testing
      user1_id = Ash.UUID.generate()
      user2_id = Ash.UUID.generate()
      project1_id = Ash.UUID.generate()
      project2_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Create prompts with different access levels
      {:ok, private_user1_prompt} =
        Prompt.create_user_prompt(%{
          content: "User 1's private prompt",
          name: "private_user1_prompt",
          tenant_id: tenant_id,
          user_id: user1_id
        })

      {:ok, project1_shared_prompt} =
        Prompt.create_project_prompt(%{
          content: "Project 1 shared prompt",
          name: "project1_shared_prompt",
          tenant_id: tenant_id,
          project_id: project1_id
        })

      # Test User 1 access in Project 1 context
      assert {:ok, user1_project1_prompts} =
               LlmPromptSelector.get_available_prompts(user1_id, project1_id)

      user1_project1_ids = extract_all_prompt_ids(user1_project1_prompts)

      # User 1 should see their private prompt and project 1 shared prompt
      assert private_user1_prompt.id in user1_project1_ids
      assert project1_shared_prompt.id in user1_project1_ids

      # Test User 2 access in Project 1 context
      assert {:ok, user2_project1_prompts} =
               LlmPromptSelector.get_available_prompts(user2_id, project1_id)

      user2_project1_ids = extract_all_prompt_ids(user2_project1_prompts)

      # User 2 should see project 1 shared prompt but NOT User 1's private prompt
      assert project1_shared_prompt.id in user2_project1_ids
      assert private_user1_prompt.id not in user2_project1_ids

      # Test User 1 access without project context
      assert {:ok, user1_no_project_prompts} = LlmPromptSelector.get_available_prompts(user1_id)

      user1_no_project_ids = extract_all_prompt_ids(user1_no_project_prompts)

      # Without project context, should see personal and system prompts only
      assert private_user1_prompt.id in user1_no_project_ids
      # No project prompts without project context
      assert project1_shared_prompt.id not in user1_no_project_ids

      # Test User 1 access in different project context (Project 2)
      assert {:ok, user1_project2_prompts} =
               LlmPromptSelector.get_available_prompts(user1_id, project2_id)

      user1_project2_ids = extract_all_prompt_ids(user1_project2_prompts)

      # Should see personal prompts but not Project 1's prompts in Project 2 context
      assert private_user1_prompt.id in user1_project2_ids
      # Different project's prompts not visible
      assert project1_shared_prompt.id not in user1_project2_ids
    end

    test "prompt search and filtering across tiers" do
      # Test advanced search and filtering functionality

      user_id = Ash.UUID.generate()
      project_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Create prompts with different characteristics for search testing
      {:ok, code_review_prompt} =
        Prompt.create_user_prompt(%{
          content:
            "Comprehensive code review focusing on security vulnerabilities and performance optimizations",
          name: "security_performance_code_review",
          tenant_id: tenant_id,
          user_id: user_id,
          description: "Security-focused code review template"
        })

      {:ok, documentation_prompt} =
        Prompt.create_user_prompt(%{
          content: "Generate comprehensive API documentation with examples and error handling",
          name: "api_documentation_generator",
          tenant_id: tenant_id,
          user_id: user_id,
          description: "API documentation template with examples"
        })

      # Test content-inclusive search
      assert {:ok, security_search} =
               LlmPromptSelector.search_prompts(user_id, "security", project_id, %{
                 include_content: true
               })

      # Should find prompts with "security" in content
      security_prompt_ids = Enum.map(security_search, fn p -> p.id end)
      assert code_review_prompt.id in security_prompt_ids

      # Test name/description only search
      assert {:ok, api_name_search} =
               LlmPromptSelector.search_prompts(user_id, "api", project_id, %{
                 include_content: false
               })

      # Should find prompts with "api" in name or description
      api_prompt_ids = Enum.map(api_name_search, fn p -> p.id end)
      assert documentation_prompt.id in api_prompt_ids

      # Test search scope filtering
      assert {:ok, user_only_search} =
               LlmPromptSelector.search_prompts(user_id, "code", project_id, %{
                 search_scope: :user_only
               })

      # Should only return user prompts
      for prompt <- user_only_search do
        assert prompt.prompt_type == :user
      end
    end

    test "prompt usage analytics and tracking integration" do
      # Test comprehensive usage analytics integration

      user_id = Ash.UUID.generate()
      project_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      {:ok, analytics_test_prompt} =
        Prompt.create_user_prompt(%{
          content: "Analytics test prompt with {{parameter}}",
          name: "analytics_test_prompt",
          tenant_id: tenant_id,
          user_id: user_id
        })

      # Simulate multiple LLM operations using the prompt
      llm_operations = [
        %{
          llm_context: %{
            llm_provider: "gpt-4",
            operation_type: :code_review,
            request_id: Ash.UUID.generate()
          },
          metadata: %{success: true, response_quality: 0.9, tokens_used: 200}
        },
        %{
          llm_context: %{
            llm_provider: "claude-3",
            operation_type: :documentation,
            request_id: Ash.UUID.generate()
          },
          metadata: %{success: true, response_quality: 0.85, tokens_used: 300}
        },
        %{
          llm_context: %{
            llm_provider: "gpt-4",
            operation_type: :analysis,
            request_id: Ash.UUID.generate()
          },
          metadata: %{success: false, response_quality: 0.6, tokens_used: 100}
        }
      ]

      # Track all operations
      for operation <- llm_operations do
        PromptUsageTracker.track_llm_usage(
          user_id,
          analytics_test_prompt.id,
          operation.llm_context,
          operation.metadata
        )
      end

      # Allow time for async tracking to complete
      Process.sleep(200)

      # Test usage statistics
      assert {:ok, prompt_stats} =
               PromptUsageTracker.get_prompt_usage_stats(analytics_test_prompt.id, user_id)

      assert prompt_stats.total_uses >= 3
      assert Map.has_key?(prompt_stats, :average_success_rate)
      assert Map.has_key?(prompt_stats, :last_used)

      # Test user analytics
      assert {:ok, user_analytics} = PromptUsageTracker.get_user_usage_analytics(user_id)

      assert user_analytics.total_usage_count >= 3
      assert user_analytics.unique_prompts_used >= 1
      assert Map.has_key?(user_analytics, :usage_by_type)
      assert Map.has_key?(user_analytics, :most_used_prompts)
    end

    test "template variable security validation prevents injection attacks" do
      # Test security validation for template variables

      # Test injection prevention in variable values
      injection_attempts = [
        %{"malicious_var" => "<script>alert('xss')</script>"},
        %{"system_var" => "{{system}}"},
        %{"exec_var" => "{{exec}}"},
        %{"eval_var" => "{{eval}}"}
      ]

      safe_template = "Process {{malicious_var}} safely"

      for injection_vars <- injection_attempts do
        case PromptVariableSubstitution.substitute_variables(safe_template, injection_vars) do
          {:ok, result} ->
            # If substitution succeeds, dangerous content should be sanitized
            assert not String.contains?(result, "<script>")
            assert not String.contains?(result, "{{system}}")

          {:error, _reason} ->
            # If substitution fails due to security, that's also correct
            assert true
        end
      end

      # Test template validation catches dangerous patterns
      dangerous_templates = [
        "Execute {{system}} command",
        "Run {{exec}} with parameters",
        "Evaluate {{eval}} expression"
      ]

      for dangerous_template <- dangerous_templates do
        assert {:error, {:unsafe_content, _reason}} =
                 PromptVariableSubstitution.validate_template_variables(dangerous_template)
      end

      # Test valid templates pass validation
      safe_template = "Analyze {{code_input}} for {{quality_focus}} issues"

      assert {:ok, validation_result} =
               PromptVariableSubstitution.validate_template_variables(safe_template)

      assert validation_result.safe == true
      assert validation_result.valid_syntax == true
    end

    test "performance requirements are met with realistic data volumes" do
      # Test performance with realistic data volumes

      user_id = Ash.UUID.generate()
      project_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Create realistic prompt library (500 prompts across tiers)
      system_prompts =
        for i <- 1..50 do
          {:ok, prompt} =
            Prompt.create_system_prompt(%{
              content:
                "System prompt #{i} for performance testing with various content lengths and complexity",
              name: "system_perf_prompt_#{i}",
              tenant_id: tenant_id
            })

          prompt
        end

      project_prompts =
        for i <- 1..150 do
          {:ok, prompt} =
            Prompt.create_project_prompt(%{
              content:
                "Project prompt #{i} for team collaboration and performance testing with {{variable_#{i}}}",
              name: "project_perf_prompt_#{i}",
              tenant_id: tenant_id,
              project_id: project_id
            })

          prompt
        end

      user_prompts =
        for i <- 1..300 do
          {:ok, prompt} =
            Prompt.create_user_prompt(%{
              content:
                "User prompt #{i} for personal productivity and performance testing with {{param_#{i}}} and {{context_#{i}}}",
              name: "user_perf_prompt_#{i}",
              tenant_id: tenant_id,
              user_id: user_id
            })

          prompt
        end

      # Test retrieval performance with full collection
      full_retrieval_start = System.monotonic_time(:microsecond)
      assert {:ok, full_collection} = LlmPromptSelector.get_available_prompts(user_id, project_id)
      full_retrieval_time = System.monotonic_time(:microsecond) - full_retrieval_start
      full_retrieval_time_ms = full_retrieval_time / 1000

      # Should handle 500+ prompts efficiently
      assert full_collection.total_count >= 500

      assert full_retrieval_time_ms < 500,
             "Full collection retrieval #{full_retrieval_time_ms}ms exceeds 500ms target"

      # Test search performance with large collection
      large_search_start = System.monotonic_time(:microsecond)

      assert {:ok, search_results} =
               LlmPromptSelector.search_prompts(user_id, "performance", project_id)

      large_search_time = System.monotonic_time(:microsecond) - large_search_start
      large_search_time_ms = large_search_time / 1000

      # Should search large collection within performance requirements
      assert large_search_time_ms < 200,
             "Large collection search #{large_search_time_ms}ms exceeds 200ms requirement"

      # Should find results
      assert length(search_results) > 0
    end

    # Helper functions

    defp extract_all_prompt_ids(organized_prompts) do
      ((organized_prompts.system_prompts || []) ++
         (organized_prompts.project_prompts || []) ++
         (organized_prompts.user_prompts || []))
      |> Enum.map(fn prompt -> prompt.id end)
    end
  end
end
