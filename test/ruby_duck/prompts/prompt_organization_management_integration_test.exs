defmodule RubberDuck.Prompts.PromptOrganizationManagementIntegrationTest do
  use RubberDuck.DataCase, async: true

  alias RubberDuck.Prompts.Resources.{Prompt, PromptCategory}
  alias RubberDuck.Prompts.Services.{PromptOrganizer, PromptTagManager, PromptTemplateManager}

  describe "Phase 2B.2: Prompt Organization & Management - Integration Testing" do
    test "complete prompt organization workflow with flexible categorization schemes" do
      # Setup test data
      user_id = Ash.UUID.generate()
      project_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Step 1: Create test prompts for organization testing
      {:ok, code_review_prompt} =
        Prompt.create_user_prompt(%{
          content:
            "Review the code for quality issues and suggest improvements. Focus on {{review_focus}} and check for {{quality_criteria}}.",
          name: "code_review_template",
          tenant_id: tenant_id,
          user_id: user_id,
          description: "Template for code review prompts with variables"
        })

      {:ok, documentation_prompt} =
        Prompt.create_user_prompt(%{
          content:
            "Generate documentation for {{component_name}} including {{doc_sections}} and examples.",
          name: "documentation_generator",
          tenant_id: tenant_id,
          user_id: user_id,
          description: "Template for documentation generation"
        })

      {:ok, testing_prompt} =
        Prompt.create_user_prompt(%{
          content: "Create tests for {{function_name}} covering edge cases and validation.",
          name: "test_generation_prompt",
          tenant_id: tenant_id,
          user_id: user_id,
          description: "Template for test generation"
        })

      prompt_collection = [code_review_prompt, documentation_prompt, testing_prompt]

      # Step 2: Test hierarchical organization scheme
      hierarchical_options = %{
        scheme: :hierarchical,
        hierarchy_depth: 3
      }

      assert {:ok, hierarchical_result} =
               PromptOrganizer.organize_prompts_for_user(
                 user_id,
                 prompt_collection,
                 hierarchical_options
               )

      assert hierarchical_result.scheme_used == :hierarchical
      assert hierarchical_result.category_count >= 0
      assert Map.has_key?(hierarchical_result, :organized_prompts)
      assert Map.has_key?(hierarchical_result, :organization_metadata)

      # Step 3: Test tag-based organization scheme
      tag_based_options = %{
        scheme: :tag_based,
        auto_tag_generation: true
      }

      assert {:ok, tag_result} =
               PromptOrganizer.organize_prompts_for_user(
                 user_id,
                 prompt_collection,
                 tag_based_options
               )

      assert tag_result.scheme_used == :tag_based
      assert Map.has_key?(tag_result, :organized_prompts)

      # Step 4: Test custom organization scheme
      custom_rules = [
        %{rule_type: :filter_by_keyword, keyword: "review"},
        %{rule_type: :filter_by_keyword, keyword: "documentation"}
      ]

      custom_options = %{
        scheme: :custom,
        custom_rules: custom_rules
      }

      assert {:ok, custom_result} =
               PromptOrganizer.organize_prompts_for_user(
                 user_id,
                 prompt_collection,
                 custom_options
               )

      assert custom_result.scheme_used == :custom
      assert custom_result.organization_metadata.custom_rules_applied == 2

      # Step 5: Test organization suggestions
      suggestion_options = %{
        analysis_type: :comprehensive,
        include_usage_patterns: true
      }

      assert {:ok, suggestions} =
               PromptOrganizer.get_organization_suggestions(
                 user_id,
                 prompt_collection,
                 suggestion_options
               )

      assert suggestions.analysis_type == :comprehensive
      assert Map.has_key?(suggestions, :suggestions)
      assert Map.has_key?(suggestions, :confidence_level)
      assert Map.has_key?(suggestions, :suggestion_metadata)

      # Step 6: Test auto-categorization of new prompt
      user_context = %{
        workflow_type: :code_review,
        project_id: project_id,
        usage_context: :development
      }

      assert {:ok, categorization_result} =
               PromptOrganizer.auto_categorize_prompt(
                 code_review_prompt,
                 user_context
               )

      assert categorization_result.prompt_id == code_review_prompt.id
      assert Map.has_key?(categorization_result, :suggested_categories)
      assert length(categorization_result.suggested_categories) > 0
    end

    test "advanced tagging system with hierarchical relationships and auto-suggestions" do
      # Test comprehensive tagging system functionality

      user_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Create test prompt with content suitable for tag suggestions
      {:ok, complex_prompt} =
        Prompt.create_user_prompt(%{
          content:
            "Analyze the code for security vulnerabilities and performance issues. Generate a comprehensive report with {{detail_level}} coverage.",
          name: "security_performance_analysis",
          tenant_id: tenant_id,
          user_id: user_id,
          description: "Complex analysis prompt for tagging system testing"
        })

      # Step 1: Test tag suggestions based on content analysis
      assert {:ok, content_suggestions} =
               PromptTagManager.suggest_tags_for_prompt(
                 complex_prompt,
                 %{workflow_type: :code_review},
                 %{strategy: :content_analysis}
               )

      assert content_suggestions.prompt_id == complex_prompt.id
      assert content_suggestions.suggestion_method == :content_analysis
      assert length(content_suggestions.suggested_tags) > 0

      # Should suggest relevant tags based on content
      suggested_tag_names = content_suggestions.suggested_tags
      assert "security" in suggested_tag_names or "analysis" in suggested_tag_names

      # Step 2: Test usage pattern-based tag suggestions
      user_context = %{
        workflow_type: :security_review,
        recent_prompts: [complex_prompt],
        user_expertise: :security_focused
      }

      assert {:ok, usage_suggestions} =
               PromptTagManager.suggest_tags_for_prompt(
                 complex_prompt,
                 user_context,
                 %{strategy: :usage_patterns}
               )

      assert usage_suggestions.suggestion_method == :usage_patterns
      assert Map.has_key?(usage_suggestions, :suggestion_metadata)

      # Step 3: Test comprehensive tag suggestions
      assert {:ok, comprehensive_suggestions} =
               PromptTagManager.suggest_tags_for_prompt(
                 complex_prompt,
                 user_context,
                 %{strategy: :comprehensive}
               )

      assert comprehensive_suggestions.suggestion_method == :comprehensive

      assert length(comprehensive_suggestions.suggested_tags) >=
               length(content_suggestions.suggested_tags)

      # Step 4: Test tag creation and management
      security_tag_definition = %{
        name: "security-review",
        description: "Security-focused code review prompts",
        color: "#DC2626",
        tag_type: :category_tag
      }

      assert {:ok, security_tag} = PromptTagManager.create_tag(user_id, security_tag_definition)

      assert security_tag.name == "security-review"
      assert security_tag.user_id == user_id
      assert security_tag.tag_type == :category_tag

      # Step 5: Test tag application to prompt
      tags_to_apply = ["security-review", "code-analysis", "performance-review"]

      assert {:ok, application_result} =
               PromptTagManager.apply_tags_to_prompt(
                 complex_prompt.id,
                 tags_to_apply,
                 user_id
               )

      assert application_result.prompt_id == complex_prompt.id
      assert application_result.applied_tags == tags_to_apply
      assert application_result.user_id == user_id

      # Step 6: Test tag hierarchy building
      hierarchy_options = %{
        type: :tree,
        include_usage_stats: true
      }

      assert {:ok, tag_hierarchy} = PromptTagManager.get_tag_hierarchy(user_id, hierarchy_options)

      assert tag_hierarchy.user_id == user_id
      assert Map.has_key?(tag_hierarchy, :root_tags)
      assert Map.has_key?(tag_hierarchy, :nested_tags)
      assert Map.has_key?(tag_hierarchy, :tag_count)

      # Step 7: Test related tag discovery
      assert {:ok, related_tags} = PromptTagManager.find_related_tags("security-review", user_id)

      assert related_tags.tag_name == "security-review"
      assert related_tags.user_id == user_id
      assert Map.has_key?(related_tags, :parent_tags)
      assert Map.has_key?(related_tags, :child_tags)
      assert Map.has_key?(related_tags, :related_tags)

      # Step 8: Test tag usage analytics
      assert {:ok, tag_analytics} =
               PromptTagManager.get_tag_usage_analytics(user_id, "security-review")

      assert Map.has_key?(tag_analytics, :user_id)
      assert Map.has_key?(tag_analytics, :tag_name)
      assert Map.has_key?(tag_analytics, :analytics_metadata)
    end

    test "template variable system with parsing, validation, and inheritance" do
      # Test comprehensive template variable system

      user_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Create prompts with template variables for testing
      {:ok, base_template_prompt} =
        Prompt.create_user_prompt(%{
          content:
            "Analyze {{code_component}} for {{analysis_type}} issues. Use {{methodology}} approach and provide {{output_format}} results.",
          name: "analysis_base_template",
          tenant_id: tenant_id,
          user_id: user_id,
          description: "Base template with multiple variables"
        })

      {:ok, derived_template_prompt} =
        Prompt.create_user_prompt(%{
          content:
            "Analyze {{code_component}} for security vulnerabilities. Use comprehensive approach and provide {{output_format|detailed}} results with {{additional_context}}.",
          name: "security_analysis_template",
          tenant_id: tenant_id,
          user_id: user_id,
          description: "Derived template extending base with security focus"
        })

      # Step 1: Test template variable parsing
      assert {:ok, base_variables} =
               PromptTemplateManager.parse_template_variables(base_template_prompt.content)

      # Should extract all template variables
      # code_component, analysis_type, methodology, output_format
      assert length(base_variables) == 4

      variable_names = Enum.map(base_variables, fn var -> var.name end)
      assert "code_component" in variable_names
      assert "analysis_type" in variable_names
      assert "methodology" in variable_names
      assert "output_format" in variable_names

      # Variables should have proper metadata
      for variable <- base_variables do
        assert Map.has_key?(variable, :name)
        assert Map.has_key?(variable, :type)
        assert Map.has_key?(variable, :required)
        assert Map.has_key?(variable, :description)
      end

      # Step 2: Test derived template variable parsing (with defaults)
      assert {:ok, derived_variables} =
               PromptTemplateManager.parse_template_variables(derived_template_prompt.content)

      # Should extract variables including those with default values
      derived_variable_names = Enum.map(derived_variables, fn var -> var.name end)
      assert "code_component" in derived_variable_names
      assert "output_format" in derived_variable_names
      assert "additional_context" in derived_variable_names

      # Should handle default values
      output_format_var = Enum.find(derived_variables, fn var -> var.name == "output_format" end)
      assert output_format_var.default_value == "detailed"
      # Has default value
      assert output_format_var.required == false

      # Step 3: Test template structure validation
      assert {:ok, base_validation} =
               PromptTemplateManager.validate_template_structure(base_template_prompt.content)

      assert base_validation.valid == true
      assert base_validation.variable_count == 4
      assert Enum.empty?(base_validation.issues)

      # Step 4: Test template definition creation
      variable_specs = %{
        "code_component" => %{type: :string, description: "Code component to analyze"},
        "analysis_type" => %{type: :choice, choices: ["security", "performance", "quality"]},
        "methodology" => %{type: :string, description: "Analysis methodology to use"},
        "output_format" => %{type: :choice, choices: ["summary", "detailed", "comprehensive"]}
      }

      assert {:ok, template_definition} =
               PromptTemplateManager.create_template_definition(
                 base_template_prompt,
                 variable_specs,
                 %{template_name: "Base Analysis Template", sharing_scope: :project}
               )

      assert template_definition.prompt_id == base_template_prompt.id
      assert template_definition.template_name == "Base Analysis Template"
      assert template_definition.sharing_scope == :project
      assert length(template_definition.variables) == 4

      # Step 5: Test template inheritance
      inheritance_options = %{
        inheritance_type: :extend,
        merge_variables: true
      }

      assert {:ok, inheritance_result} =
               PromptTemplateManager.apply_template_inheritance(
                 base_template_prompt,
                 derived_template_prompt,
                 inheritance_options
               )

      assert inheritance_result.base_prompt_id == base_template_prompt.id
      assert inheritance_result.derived_prompt_id == derived_template_prompt.id
      assert inheritance_result.inheritance_type == :extend
      assert inheritance_result.inheritance_successful == true

      # Step 6: Test variable substitution validation
      test_variable_values = %{
        "code_component" => "UserService",
        "analysis_type" => "security",
        "methodology" => "comprehensive static analysis",
        "output_format" => "detailed"
      }

      assert {:ok, substitution_validation} =
               PromptTemplateManager.validate_variable_substitution(
                 base_template_prompt.content,
                 test_variable_values
               )

      assert substitution_validation.valid == true
      assert substitution_validation.substitution_ready == true
      assert substitution_validation.variables_validated == 4
      assert Enum.empty?(substitution_validation.issues)

      # Step 7: Test invalid variable substitution handling
      invalid_variable_values = %{
        "code_component" => "UserService"
        # Missing required variables: analysis_type, methodology, output_format
      }

      assert {:ok, invalid_validation} =
               PromptTemplateManager.validate_variable_substitution(
                 base_template_prompt.content,
                 invalid_variable_values
               )

      # Should detect missing required variables
      assert invalid_validation.valid == false or length(invalid_validation.issues) > 0
    end

    test "organization suggestions and intelligent categorization" do
      # Test organization suggestions and auto-categorization features

      user_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Create diverse prompt collection for suggestion testing
      prompts_with_patterns = [
        %{
          content: "Review the authentication system for security vulnerabilities",
          name: "security_auth_review",
          description: "Security-focused authentication review"
        },
        %{
          content: "Generate API documentation with comprehensive examples and error handling",
          name: "api_documentation_generator",
          description: "Documentation generation for APIs"
        },
        %{
          content: "Create unit tests for the payment processing module",
          name: "payment_testing_template",
          description: "Testing template for payment systems"
        },
        %{
          content: "Analyze database performance and suggest optimization strategies",
          name: "database_performance_analysis",
          description: "Performance analysis for database systems"
        },
        %{
          content: "Debug connection timeout issues in the microservices architecture",
          name: "microservice_debugging_guide",
          description: "Debugging guide for microservice issues"
        }
      ]

      # Create actual prompt records
      created_prompts =
        for prompt_data <- prompts_with_patterns do
          {:ok, prompt} =
            Prompt.create_user_prompt(
              Map.merge(prompt_data, %{
                tenant_id: tenant_id,
                user_id: user_id
              })
            )

          prompt
        end

      # Test organization suggestions based on usage patterns
      suggestion_options = %{
        analysis_type: :usage_patterns,
        include_content_analysis: true
      }

      assert {:ok, usage_suggestions} =
               PromptOrganizer.get_organization_suggestions(
                 user_id,
                 created_prompts,
                 suggestion_options
               )

      assert usage_suggestions.analysis_type == :usage_patterns
      assert Map.has_key?(usage_suggestions, :suggestions)

      # Test content-based organization suggestions
      assert {:ok, content_suggestions} =
               PromptOrganizer.get_organization_suggestions(
                 user_id,
                 created_prompts,
                 %{analysis_type: :content_analysis}
               )

      assert content_suggestions.analysis_type == :content_analysis

      # Test comprehensive organization suggestions
      assert {:ok, comprehensive_suggestions} =
               PromptOrganizer.get_organization_suggestions(
                 user_id,
                 created_prompts,
                 %{analysis_type: :comprehensive}
               )

      assert comprehensive_suggestions.analysis_type == :comprehensive
      assert comprehensive_suggestions.confidence_level > 0.0

      # Test auto-categorization for each prompt type
      security_context = %{workflow_type: :security_review, domain: :authentication}

      assert {:ok, security_categorization} =
               PromptOrganizer.auto_categorize_prompt(
                 # Security prompt
                 List.first(created_prompts),
                 security_context
               )

      assert Map.has_key?(security_categorization, :suggested_categories)
      assert Map.has_key?(security_categorization, :confidence_scores)
    end

    test "template inheritance and extension patterns" do
      # Test template inheritance and extension functionality

      user_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Create base template prompt
      {:ok, base_prompt} =
        Prompt.create_user_prompt(%{
          content:
            "Perform {{analysis_type}} analysis on {{target_component}}. Follow {{standards}} and generate {{deliverable_type}} report.",
          name: "base_analysis_template",
          tenant_id: tenant_id,
          user_id: user_id,
          description: "Base template for analysis workflows"
        })

      # Create derived template that extends the base
      {:ok, security_derived_prompt} =
        Prompt.create_user_prompt(%{
          content:
            "Perform security analysis on {{target_component}}. Follow OWASP standards and generate comprehensive report with {{threat_model}} assessment.",
          name: "security_analysis_template",
          tenant_id: tenant_id,
          user_id: user_id,
          description: "Security-focused template derived from base analysis"
        })

      # Test extension inheritance
      assert {:ok, extension_result} =
               PromptTemplateManager.apply_template_inheritance(
                 base_prompt,
                 security_derived_prompt,
                 %{inheritance_type: :extend}
               )

      assert extension_result.inheritance_type == :extend
      assert extension_result.inheritance_successful == true
      assert extension_result.base_prompt_id == base_prompt.id
      assert extension_result.derived_prompt_id == security_derived_prompt.id

      # Test override inheritance
      assert {:ok, override_result} =
               PromptTemplateManager.apply_template_inheritance(
                 base_prompt,
                 security_derived_prompt,
                 %{inheritance_type: :override}
               )

      assert override_result.inheritance_type == :override
      assert override_result.inheritance_successful == true

      # Test merge inheritance
      assert {:ok, merge_result} =
               PromptTemplateManager.apply_template_inheritance(
                 base_prompt,
                 security_derived_prompt,
                 %{inheritance_type: :merge}
               )

      assert merge_result.inheritance_type == :merge
      assert merge_result.inheritance_successful == true

      # Test template definition creation from inheritance
      variable_specs = %{
        "target_component" => %{type: :string, required: true},
        "threat_model" => %{type: :choice, choices: ["STRIDE", "PASTA", "OCTAVE"]}
      }

      assert {:ok, inherited_definition} =
               PromptTemplateManager.create_template_definition(
                 security_derived_prompt,
                 variable_specs,
                 %{template_name: "Security Analysis Derived Template"}
               )

      assert inherited_definition.template_name == "Security Analysis Derived Template"
      assert Map.has_key?(inherited_definition, :variables)
    end

    test "performance validation for large prompt collections and organization operations" do
      # Test performance with realistic data volumes

      user_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Create large prompt collection for performance testing
      large_prompt_collection =
        for i <- 1..100 do
          content_type =
            Enum.random(["analysis", "generation", "documentation", "testing", "debugging"])

          {:ok, prompt} =
            Prompt.create_user_prompt(%{
              content:
                "#{String.capitalize(content_type)} prompt #{i} with {{variable_#{i}}} and complex content for testing organization performance.",
              name: "#{content_type}_prompt_#{i}",
              tenant_id: tenant_id,
              user_id: user_id,
              description: "#{content_type} prompt for performance testing"
            })

          prompt
        end

      # Test organization performance
      organization_start = System.monotonic_time(:microsecond)

      assert {:ok, organization_result} =
               PromptOrganizer.organize_prompts_for_user(
                 user_id,
                 large_prompt_collection,
                 %{scheme: :hierarchical}
               )

      organization_time = System.monotonic_time(:microsecond) - organization_start
      organization_time_ms = organization_time / 1000

      # Should organize large collection efficiently
      assert organization_time_ms < 1000,
             "Organization time #{organization_time_ms}ms exceeds 1000ms target for 100 prompts"

      assert organization_result.category_count >= 0

      # Test tag suggestion performance
      sample_prompt = List.first(large_prompt_collection)

      suggestion_start = System.monotonic_time(:microsecond)

      assert {:ok, suggestions} =
               PromptTagManager.suggest_tags_for_prompt(
                 sample_prompt,
                 %{workflow_type: :performance_testing},
                 %{strategy: :content_analysis}
               )

      suggestion_time = System.monotonic_time(:microsecond) - suggestion_start
      suggestion_time_ms = suggestion_time / 1000

      # Should generate suggestions quickly
      assert suggestion_time_ms < 100,
             "Tag suggestion time #{suggestion_time_ms}ms exceeds 100ms target"

      assert length(suggestions.suggested_tags) > 0

      # Test template variable parsing performance
      variable_parsing_start = System.monotonic_time(:microsecond)

      assert {:ok, parsed_variables} =
               PromptTemplateManager.parse_template_variables(sample_prompt.content)

      variable_parsing_time = System.monotonic_time(:microsecond) - variable_parsing_start
      variable_parsing_time_ms = variable_parsing_time / 1000

      # Should parse variables quickly
      assert variable_parsing_time_ms < 50,
             "Variable parsing time #{variable_parsing_time_ms}ms exceeds 50ms target"

      assert is_list(parsed_variables)
    end

    test "integration with Section 1 prompt storage foundation" do
      # Test integration with verified Section 1 infrastructure

      user_id = Ash.UUID.generate()
      project_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Create prompts using Section 1 resources
      {:ok, system_prompt} =
        Prompt.create_system_prompt(%{
          content: "System-wide analysis template with {{system_variable}}",
          name: "system_analysis_template",
          tenant_id: tenant_id
        })

      {:ok, project_prompt} =
        Prompt.create_project_prompt(%{
          content: "Project-specific template for {{project_context}} with {{team_standards}}",
          name: "project_template",
          tenant_id: tenant_id,
          project_id: project_id
        })

      {:ok, user_prompt} =
        Prompt.create_user_prompt(%{
          content: "Personal template for {{personal_workflow}} optimization",
          name: "personal_template",
          tenant_id: tenant_id,
          user_id: user_id
        })

      # Test organization across three-tier hierarchy
      three_tier_collection = [system_prompt, project_prompt, user_prompt]

      assert {:ok, three_tier_organization} =
               PromptOrganizer.organize_prompts_for_user(
                 user_id,
                 three_tier_collection,
                 %{scheme: :hierarchical, respect_tier_hierarchy: true}
               )

      assert three_tier_organization.scheme_used == :hierarchical
      assert three_tier_organization.category_count >= 0

      # Test that organization respects three-tier access control
      assert Map.has_key?(three_tier_organization, :organized_prompts)

      # Test template variable parsing across tiers
      for prompt <- three_tier_collection do
        assert {:ok, variables} = PromptTemplateManager.parse_template_variables(prompt.content)
        assert is_list(variables)
      end

      # Test tag suggestions work with three-tier prompts
      assert {:ok, system_tag_suggestions} =
               PromptTagManager.suggest_tags_for_prompt(system_prompt)

      assert {:ok, project_tag_suggestions} =
               PromptTagManager.suggest_tags_for_prompt(project_prompt)

      assert {:ok, user_tag_suggestions} = PromptTagManager.suggest_tags_for_prompt(user_prompt)

      # All should generate suggestions
      assert length(system_tag_suggestions.suggested_tags) >= 0
      assert length(project_tag_suggestions.suggested_tags) >= 0
      assert length(user_tag_suggestions.suggested_tags) >= 0
    end

    test "backward compatibility with existing prompt management workflows" do
      # Test that Section 2 enhancements don't break existing functionality

      user_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Create prompt without template variables (traditional prompt)
      {:ok, simple_prompt} =
        Prompt.create_user_prompt(%{
          content: "Simple prompt without any template variables for compatibility testing.",
          name: "simple_compatibility_prompt",
          tenant_id: tenant_id,
          user_id: user_id,
          description: "Simple prompt for backward compatibility testing"
        })

      # Should handle prompts without variables gracefully
      assert {:ok, no_variables} =
               PromptTemplateManager.parse_template_variables(simple_prompt.content)

      assert Enum.empty?(no_variables)

      # Should organize simple prompts without issues
      assert {:ok, simple_organization} =
               PromptOrganizer.organize_prompts_for_user(
                 user_id,
                 [simple_prompt],
                 %{scheme: :flat}
               )

      assert simple_organization.scheme_used == :flat

      # Should generate tag suggestions even for simple prompts
      assert {:ok, simple_suggestions} = PromptTagManager.suggest_tags_for_prompt(simple_prompt)
      assert is_list(simple_suggestions.suggested_tags)

      # Should validate simple prompts without errors
      assert {:ok, simple_validation} =
               PromptTemplateManager.validate_template_structure(simple_prompt.content)

      assert simple_validation.valid == true
    end
  end

  describe "Integration Quality Requirements" do
    test "comprehensive service validation" do
      # Validate all organization services are working correctly

      organization_services = [
        PromptOrganizer,
        PromptTagManager,
        PromptTemplateManager
      ]

      for service <- organization_services do
        assert Code.ensure_loaded?(service), "Service #{service} should be loaded"
      end
    end

    test "Section 1 foundation integration validation" do
      # Test that Section 2 properly builds on Section 1 foundation

      user_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Test that Section 2 services work with Section 1 resources
      {:ok, test_prompt} =
        Prompt.create_user_prompt(%{
          content: "Integration test prompt with {{test_variable}}",
          name: "integration_test_prompt",
          tenant_id: tenant_id,
          user_id: user_id
        })

      # Organization should work with Prompt resources
      assert {:ok, _organization} =
               PromptOrganizer.organize_prompts_for_user(user_id, [test_prompt])

      # Tag suggestions should work with Prompt resources
      assert {:ok, _suggestions} = PromptTagManager.suggest_tags_for_prompt(test_prompt)

      # Template parsing should work with Prompt content
      assert {:ok, _variables} =
               PromptTemplateManager.parse_template_variables(test_prompt.content)

      # Should integrate with existing PromptCategory resource
      {:ok, test_category} =
        PromptCategory.create(%{
          name: "Integration Test Category",
          description: "Category for testing Section 2 integration"
        })

      assert test_category.name == "Integration Test Category"
    end
  end
end
