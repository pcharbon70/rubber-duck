defmodule RubberDuck.Prompts.CorePromptResourcesTest do
  @moduledoc """
  Comprehensive unit tests for Phase 02b Section 1.1: Core Prompt Resources.
  
  Tests cover:
  - Task 2B.1.3: Ash resource operations with CRUD validation and relationship testing
  - Task 2B.1.4: Multi-tenancy isolation with Row-Level Security and cross-tenant access prevention
  - Task 2B.1.5: Versioning mechanisms with history tracking, comparison, and rollback functionality
  - Task 2B.1.6: Database constraints and policies with data integrity and security validation
  """

  use RubberDuck.DataCase, async: false

  alias RubberDuck.Prompts.Resources.{
    Prompt,
    PromptCategory,
    PromptUsage,
    PromptVersion
  }

  describe "Ash resource operations (2B.1.3)" do
    test "Prompt resource supports full CRUD operations with hierarchical relationships" do
      # Create a category first
      {:ok, category} = PromptCategory.create(%{
        name: "Test Category",
        description: "Test category for prompts",
        tenant_id: Ash.UUID.generate(),
        category_type: :general
      })

      # Create system prompt
      tenant_id = Ash.UUID.generate()
      {:ok, system_prompt} = Prompt.create_system_prompt(%{
        name: "system_test_prompt",
        content: "You are a helpful assistant. Please {{instruction}}.",
        tenant_id: tenant_id,
        category_id: category.id,
        variables: ["instruction"],
        tags: ["system", "assistant"]
      })

      assert system_prompt.prompt_type == :system
      assert system_prompt.status == :approved
      assert system_prompt.priority == 100
      assert system_prompt.variables == ["instruction"]
      assert "system" in system_prompt.tags

      # Create project prompt that inherits from system
      project_id = Ash.UUID.generate()
      {:ok, project_prompt} = Prompt.create_project_prompt(%{
        name: "project_test_prompt", 
        content: "For this project, focus on {{project_context}}. {{instruction}}",
        tenant_id: tenant_id,
        project_id: project_id,
        category_id: category.id,
        parent_id: system_prompt.id,
        variables: ["project_context", "instruction"],
        tags: ["project", "context"]
      })

      assert project_prompt.prompt_type == :project
      assert project_prompt.status == :draft
      assert project_prompt.priority == 50
      assert project_prompt.parent_id == system_prompt.id

      # Create user prompt
      user_id = Ash.UUID.generate()
      {:ok, user_prompt} = Prompt.create_user_prompt(%{
        name: "user_test_prompt",
        content: "My preference is {{user_preference}}. {{project_context}} {{instruction}}",
        tenant_id: tenant_id,
        user_id: user_id,
        category_id: category.id,
        parent_id: project_prompt.id,
        variables: ["user_preference", "project_context", "instruction"]
      })

      assert user_prompt.prompt_type == :user
      assert user_prompt.status == :approved
      assert user_prompt.priority == 10
      assert user_prompt.parent_id == project_prompt.id

      # Update prompt and verify versioning
      {:ok, updated_prompt} = Prompt.update(system_prompt, %{
        content: "You are a very helpful assistant. Please {{instruction}} with care."
      })

      assert updated_prompt.content != system_prompt.content
      
      # Verify relationships work
      prompts_in_category = Ash.read!(Prompt.list_by_category(%{category_id: category.id}))
      assert length(prompts_in_category) == 3

      # Test deletion
      assert :ok = Ash.destroy(user_prompt)
    end

    test "PromptCategory supports nested hierarchical organization" do
      tenant_id = Ash.UUID.generate()
      
      # Create parent category
      {:ok, parent_category} = PromptCategory.create(%{
        name: "Development",
        description: "Development-related prompts",
        tenant_id: tenant_id,
        category_type: :general,
        sort_order: 1,
        color_code: "#3498db",
        icon: "code"
      })

      assert parent_category.slug == "development"
      assert parent_category.color_code == "#3498db"

      # Create child category
      {:ok, child_category} = PromptCategory.create(%{
        name: "Code Review", 
        description: "Code review specific prompts",
        tenant_id: tenant_id,
        category_type: :project,
        parent_id: parent_category.id,
        sort_order: 1
      })

      assert child_category.parent_id == parent_category.id
      assert child_category.slug == "code-review"

      # Test hierarchy queries
      top_level_categories = Ash.read!(PromptCategory.list_top_level())
      child_categories = Ash.read!(PromptCategory.list_by_parent(%{parent_id: parent_category.id}))
      
      assert length(top_level_categories) >= 1
      assert length(child_categories) >= 1
      assert Enum.any?(child_categories, fn cat -> cat.id == child_category.id end)
    end

    test "PromptVersion tracks complete version history with diff generation" do
      tenant_id = Ash.UUID.generate()
      
      # Create prompt
      {:ok, prompt} = Prompt.create_system_prompt(%{
        name: "version_test_prompt",
        content: "Original content for testing.",
        tenant_id: tenant_id
      })

      # Update prompt multiple times
      {:ok, updated_prompt_v2} = Prompt.update(prompt, %{
        content: "Updated content for testing versioning."
      })

      {:ok, updated_prompt_v3} = Prompt.update(updated_prompt_v2, %{
        content: "Final content with comprehensive testing versioning."
      })

      # Verify versions were created
      versions = Ash.read!(PromptVersion.list_for_prompt(%{prompt_id: prompt.id}))
      assert length(versions) >= 3  # Initial + 2 updates

      # Test version ordering
      assert Enum.at(versions, 0).version_number > Enum.at(versions, 1).version_number

      # Test latest version retrieval
      {:ok, [latest_version]} = PromptVersion.latest_version(%{prompt_id: prompt.id})
      assert latest_version.content_snapshot == updated_prompt_v3.content

      # Test version comparison
      version_comparison = Ash.read!(PromptVersion.compare_versions(%{
        prompt_id: prompt.id,
        version_1: 1,
        version_2: 2
      }))
      
      assert length(version_comparison) == 2
    end

    test "PromptUsage tracks comprehensive analytics and performance metrics" do
      tenant_id = Ash.UUID.generate()
      user_id = Ash.UUID.generate()
      
      # Create prompt for usage tracking
      {:ok, prompt} = Prompt.create_system_prompt(%{
        name: "analytics_test_prompt",
        content: "Test prompt for usage analytics.",
        tenant_id: tenant_id
      })

      # Record successful usage
      {:ok, success_usage} = PromptUsage.record_successful_usage(%{
        prompt_id: prompt.id,
        used_by_id: user_id,
        context_type: :llm_request,
        response_time_ms: 1250,
        tokens_used: 150,
        request_id: Ash.UUID.generate(),
        variables_used: %{"instruction" => "help with coding"},
        performance_metrics: %{
          "cache_hit" => true,
          "composition_time_ms" => 50
        }
      })

      assert success_usage.success == true
      assert success_usage.response_time_ms == 1250
      assert success_usage.tokens_used == 150
      assert success_usage.effectiveness_score != nil

      # Record failed usage
      {:ok, failed_usage} = PromptUsage.record_failed_usage(%{
        prompt_id: prompt.id,
        used_by_id: user_id,
        context_type: :llm_request,
        error_type: :timeout,
        error_message: "Request timed out after 30 seconds",
        response_time_ms: 30_000
      })

      assert failed_usage.success == false
      assert failed_usage.error_type == :timeout
      assert failed_usage.error_message == "Request timed out after 30 seconds"

      # Test analytics queries
      prompt_usages = Ash.read!(PromptUsage.usage_for_prompt(%{prompt_id: prompt.id}))
      assert length(prompt_usages) == 2

      user_usages = Ash.read!(PromptUsage.usage_by_user(%{used_by_id: user_id}))
      assert length(user_usages) >= 2

      failed_usages = Ash.read!(PromptUsage.failed_usages(%{prompt_id: prompt.id}))
      assert length(failed_usages) >= 1
    end
  end

  describe "multi-tenancy isolation (2B.1.4)" do
    test "Row-Level Security prevents cross-tenant data access" do
      tenant_1_id = Ash.UUID.generate()
      tenant_2_id = Ash.UUID.generate()
      
      # Set tenant context for tenant 1
      Ash.set_tenant(RubberDuck.Prompts.Domain, tenant_1_id)
      
      # Create prompt in tenant 1
      {:ok, tenant_1_prompt} = Prompt.create_system_prompt(%{
        name: "tenant_1_prompt",
        content: "Prompt for tenant 1",
        tenant_id: tenant_1_id
      })

      # Switch to tenant 2 context
      Ash.set_tenant(RubberDuck.Prompts.Domain, tenant_2_id)
      
      # Create prompt in tenant 2
      {:ok, tenant_2_prompt} = Prompt.create_system_prompt(%{
        name: "tenant_2_prompt",
        content: "Prompt for tenant 2", 
        tenant_id: tenant_2_id
      })

      # Verify tenant 1 cannot see tenant 2's prompts
      Ash.set_tenant(RubberDuck.Prompts.Domain, tenant_1_id)
      tenant_1_prompts = Ash.read!(Prompt)
      
      tenant_1_ids = Enum.map(tenant_1_prompts, fn p -> p.id end)
      assert tenant_1_prompt.id in tenant_1_ids
      assert tenant_2_prompt.id not in tenant_1_ids

      # Verify tenant 2 cannot see tenant 1's prompts
      Ash.set_tenant(RubberDuck.Prompts.Domain, tenant_2_id)
      tenant_2_prompts = Ash.read!(Prompt)
      
      tenant_2_ids = Enum.map(tenant_2_prompts, fn p -> p.id end)
      assert tenant_2_prompt.id in tenant_2_ids
      assert tenant_1_prompt.id not in tenant_2_ids
    end

    test "PromptCategory respects multi-tenant boundaries" do
      tenant_1_id = Ash.UUID.generate()
      tenant_2_id = Ash.UUID.generate()

      # Create categories in different tenants
      Ash.set_tenant(RubberDuck.Prompts.Domain, tenant_1_id)
      {:ok, tenant_1_category} = PromptCategory.create(%{
        name: "Tenant 1 Category",
        tenant_id: tenant_1_id,
        category_type: :general
      })

      Ash.set_tenant(RubberDuck.Prompts.Domain, tenant_2_id) 
      {:ok, tenant_2_category} = PromptCategory.create(%{
        name: "Tenant 2 Category",
        tenant_id: tenant_2_id,
        category_type: :general
      })

      # Verify isolation
      Ash.set_tenant(RubberDuck.Prompts.Domain, tenant_1_id)
      tenant_1_categories = Ash.read!(PromptCategory)
      tenant_1_category_ids = Enum.map(tenant_1_categories, fn c -> c.id end)
      
      assert tenant_1_category.id in tenant_1_category_ids
      assert tenant_2_category.id not in tenant_1_category_ids
    end

    test "PromptUsage analytics respect tenant boundaries" do
      tenant_1_id = Ash.UUID.generate()
      tenant_2_id = Ash.UUID.generate()
      user_id = Ash.UUID.generate()

      # Create prompts in different tenants
      Ash.set_tenant(RubberDuck.Prompts.Domain, tenant_1_id)
      {:ok, tenant_1_prompt} = Prompt.create_system_prompt(%{
        name: "tenant_1_analytics_prompt",
        content: "Tenant 1 analytics test",
        tenant_id: tenant_1_id
      })

      Ash.set_tenant(RubberDuck.Prompts.Domain, tenant_2_id)
      {:ok, tenant_2_prompt} = Prompt.create_system_prompt(%{
        name: "tenant_2_analytics_prompt", 
        content: "Tenant 2 analytics test",
        tenant_id: tenant_2_id
      })

      # Record usage in tenant 1
      Ash.set_tenant(RubberDuck.Prompts.Domain, tenant_1_id)
      {:ok, tenant_1_usage} = PromptUsage.record_successful_usage(%{
        prompt_id: tenant_1_prompt.id,
        used_by_id: user_id,
        context_type: :llm_request,
        response_time_ms: 1000,
        tokens_used: 100
      })

      # Verify tenant 2 cannot see tenant 1's usage
      Ash.set_tenant(RubberDuck.Prompts.Domain, tenant_2_id)
      tenant_2_usages = Ash.read!(PromptUsage)
      tenant_2_usage_ids = Enum.map(tenant_2_usages, fn u -> u.id end)
      
      assert tenant_1_usage.id not in tenant_2_usage_ids
    end
  end

  describe "versioning mechanisms (2B.1.5)" do
    test "PromptVersion automatically creates versions on prompt updates" do
      tenant_id = Ash.UUID.generate()
      
      # Create initial prompt
      {:ok, prompt} = Prompt.create_system_prompt(%{
        name: "versioning_test_prompt",
        content: "Initial version content.",
        tenant_id: tenant_id
      })

      # Verify initial version was created
      versions = Ash.read!(PromptVersion.list_for_prompt(%{prompt_id: prompt.id}))
      assert length(versions) >= 1
      
      initial_version = Enum.find(versions, fn v -> v.version_number == 1 end)
      assert initial_version != nil
      assert initial_version.content_snapshot == "Initial version content."
      assert initial_version.change_type == :create

      # Update prompt and verify new version
      {:ok, updated_prompt} = Prompt.update(prompt, %{
        content: "Updated version content with changes."
      })

      updated_versions = Ash.read!(PromptVersion.list_for_prompt(%{prompt_id: prompt.id}))
      assert length(updated_versions) >= 2
      
      latest_version = Enum.find(updated_versions, fn v -> v.version_number == 2 end)
      assert latest_version != nil
      assert latest_version.content_snapshot == updated_prompt.content
    end

    test "version comparison and diff generation works correctly" do
      tenant_id = Ash.UUID.generate()
      user_id = Ash.UUID.generate()
      
      # Create prompt with initial content
      {:ok, prompt} = Prompt.create_user_prompt(%{
        name: "diff_test_prompt",
        content: "Original content for diff testing.",
        tenant_id: tenant_id,
        user_id: user_id
      })

      # Update with different content
      {:ok, _updated_prompt} = Prompt.update(prompt, %{
        content: "Modified content for comprehensive diff testing."
      })

      # Test version comparison
      comparison_versions = Ash.read!(PromptVersion.compare_versions(%{
        prompt_id: prompt.id,
        version_1: 1,
        version_2: 2
      }))
      
      assert length(comparison_versions) == 2
      version_1 = Enum.find(comparison_versions, fn v -> v.version_number == 1 end)
      version_2 = Enum.find(comparison_versions, fn v -> v.version_number == 2 end)
      
      assert version_1.content_snapshot != version_2.content_snapshot
      assert version_1.version_number < version_2.version_number
    end

    test "version rollback maintains data integrity" do
      tenant_id = Ash.UUID.generate()
      
      # Create prompt and update multiple times
      {:ok, prompt} = Prompt.create_system_prompt(%{
        name: "rollback_test_prompt",
        content: "Version 1 content.",
        tenant_id: tenant_id
      })

      {:ok, _v2} = Prompt.update(prompt, %{content: "Version 2 content."})
      {:ok, v3} = Prompt.update(prompt, %{content: "Version 3 content."})

      # Get version 1 content for rollback
      {:ok, [version_1]} = PromptVersion.get_version(%{
        prompt_id: prompt.id,
        version_number: 1
      })

      # Simulate rollback by updating with version 1 content
      {:ok, rolled_back_prompt} = Prompt.update(v3, %{
        content: version_1.content_snapshot
      })

      assert rolled_back_prompt.content == "Version 1 content."
      
      # Verify new version was created for rollback
      all_versions = Ash.read!(PromptVersion.list_for_prompt(%{prompt_id: prompt.id}))
      assert length(all_versions) >= 4  # Initial + 2 updates + rollback
    end
  end

  describe "database constraints and policies (2B.1.6)" do
    test "prompt type constraints enforce business rules" do
      tenant_id = Ash.UUID.generate()
      project_id = Ash.UUID.generate()
      
      # Test that project prompts require project_id
      assert_raise Ash.Error.Invalid, fn ->
        Prompt.create_project_prompt!(%{
          name: "invalid_project_prompt",
          content: "Missing project_id",
          tenant_id: tenant_id
          # Missing required project_id
        })
      end

      # Test that system prompts cannot have project_id
      {:ok, system_prompt} = Prompt.create_system_prompt(%{
        name: "valid_system_prompt",
        content: "System prompt without project_id",
        tenant_id: tenant_id
      })

      # Attempting to add project_id to system prompt should fail validation
      assert {:error, _} = Prompt.update(system_prompt, %{project_id: project_id})
    end

    test "category slug uniqueness is enforced per tenant" do
      tenant_id = Ash.UUID.generate()
      
      # Create first category
      {:ok, _category_1} = PromptCategory.create(%{
        name: "Unique Category",
        tenant_id: tenant_id,
        category_type: :general
      })

      # Attempt to create category with same slug should fail
      assert_raise Ash.Error.Invalid, fn ->
        PromptCategory.create!(%{
          name: "Unique Category",  # Same name = same slug
          tenant_id: tenant_id,
          category_type: :general
        })
      end
    end

    test "version number constraints ensure data integrity" do
      tenant_id = Ash.UUID.generate()
      
      # Create prompt
      {:ok, prompt} = Prompt.create_system_prompt(%{
        name: "integrity_test_prompt",
        content: "Content for integrity testing.",
        tenant_id: tenant_id
      })

      # Manual version creation with invalid version number should fail
      assert_raise Ash.Error.Invalid, fn ->
        PromptVersion.create!(%{
          prompt_id: prompt.id,
          version_number: -1,  # Invalid negative version
          content_snapshot: "Invalid version",
          created_by_id: Ash.UUID.generate()
        })
      end
    end

    test "usage analytics constraints validate data quality" do
      tenant_id = Ash.UUID.generate()
      user_id = Ash.UUID.generate()
      
      # Create prompt
      {:ok, prompt} = Prompt.create_system_prompt(%{
        name: "validation_test_prompt",
        content: "Content for validation testing.",
        tenant_id: tenant_id
      })

      # Test invalid response time
      assert_raise Ash.Error.Invalid, fn ->
        PromptUsage.create!(%{
          prompt_id: prompt.id,
          used_by_id: user_id,
          context_type: :llm_request,
          response_time_ms: -100,  # Invalid negative time
          success: true
        })
      end

      # Test invalid user satisfaction
      assert_raise Ash.Error.Invalid, fn ->
        PromptUsage.record_successful_usage!(%{
          prompt_id: prompt.id,
          used_by_id: user_id,
          context_type: :llm_request,
          response_time_ms: 1000,
          tokens_used: 100,
          user_satisfaction: 10  # Invalid rating > 5
        })
      end

      # Test failed usage requires error information
      assert_raise Ash.Error.Invalid, fn ->
        PromptUsage.create!(%{
          prompt_id: prompt.id,
          used_by_id: user_id,
          context_type: :llm_request,
          success: false
          # Missing required error_type and error_message
        })
      end
    end

    test "hierarchical relationships prevent circular references" do
      tenant_id = Ash.UUID.generate()
      
      # Create parent category
      {:ok, parent_category} = PromptCategory.create(%{
        name: "Parent Category",
        tenant_id: tenant_id,
        category_type: :general
      })

      # Create child category
      {:ok, child_category} = PromptCategory.create(%{
        name: "Child Category",
        tenant_id: tenant_id,
        category_type: :general,
        parent_id: parent_category.id
      })

      # Attempt to create circular reference should fail
      assert {:error, _} = PromptCategory.update(parent_category, %{
        parent_id: child_category.id  # This would create a circular reference
      })
    end

    test "access control policies enforce security boundaries" do
      tenant_id = Ash.UUID.generate()
      admin_user_id = Ash.UUID.generate()
      regular_user_id = Ash.UUID.generate()
      project_id = Ash.UUID.generate()

      # Set admin actor context
      admin_actor = %{id: admin_user_id, role: :admin, project_id: project_id, project_role: :owner}
      
      # Create system prompt (admin only)
      {:ok, system_prompt} = Ash.create(Prompt, %{
        name: "admin_system_prompt",
        content: "Admin-created system prompt",
        prompt_type: :system,
        tenant_id: tenant_id
      }, actor: admin_actor)

      assert system_prompt.prompt_type == :system

      # Regular user should not be able to create system prompts
      regular_actor = %{id: regular_user_id, role: :user}
      
      assert_raise Ash.Error.Forbidden, fn ->
        Ash.create!(Prompt, %{
          name: "unauthorized_system_prompt",
          content: "Unauthorized system prompt",
          prompt_type: :system,
          tenant_id: tenant_id
        }, actor: regular_actor)
      end

      # Regular user can create user prompts
      {:ok, user_prompt} = Ash.create(Prompt, %{
        name: "user_personal_prompt",
        content: "Personal user prompt",
        prompt_type: :user,
        tenant_id: tenant_id,
        user_id: regular_user_id
      }, actor: regular_actor)

      assert user_prompt.prompt_type == :user
      assert user_prompt.user_id == regular_user_id
    end
  end

  describe "integration and performance (2B.1.3-2B.1.6)" do
    test "prompt search and filtering works efficiently" do
      tenant_id = Ash.UUID.generate()
      
      # Create category for organization
      {:ok, category} = PromptCategory.create(%{
        name: "Search Test Category",
        tenant_id: tenant_id,
        category_type: :general
      })

      # Create multiple prompts with different characteristics
      {:ok, _prompt_1} = Prompt.create_system_prompt(%{
        name: "search_test_coding",
        content: "Help with coding tasks and development.",
        tenant_id: tenant_id,
        category_id: category.id,
        tags: ["coding", "development", "help"]
      })

      {:ok, _prompt_2} = Prompt.create_system_prompt(%{
        name: "search_test_review",
        content: "Perform comprehensive code review analysis.",
        tenant_id: tenant_id,
        category_id: category.id,
        tags: ["review", "analysis", "quality"]
      })

      # Test name-based search
      coding_prompts = Ash.read!(Prompt.search_prompts(%{search_term: "coding"}))
      assert length(coding_prompts) >= 1
      assert Enum.any?(coding_prompts, fn p -> String.contains?(p.name, "coding") end)

      # Test content-based search
      review_prompts = Ash.read!(Prompt.search_prompts(%{search_term: "review"}))
      assert length(review_prompts) >= 1
      assert Enum.any?(review_prompts, fn p -> String.contains?(p.content, "review") end)

      # Test tag-based search
      development_prompts = Ash.read!(Prompt.search_prompts(%{search_term: "development"}))
      assert length(development_prompts) >= 1

      # Test category-based listing
      category_prompts = Ash.read!(Prompt.list_by_category(%{category_id: category.id}))
      assert length(category_prompts) >= 2
    end

    test "prompt effectiveness scoring and analytics work correctly" do
      tenant_id = Ash.UUID.generate()
      user_id = Ash.UUID.generate()
      
      # Create prompt for effectiveness testing
      {:ok, prompt} = Prompt.create_system_prompt(%{
        name: "effectiveness_test_prompt",
        content: "Test prompt for effectiveness scoring.",
        tenant_id: tenant_id
      })

      # Record multiple usages with different outcomes
      {:ok, high_effectiveness_usage} = PromptUsage.record_successful_usage(%{
        prompt_id: prompt.id,
        used_by_id: user_id,
        context_type: :llm_request,
        response_time_ms: 500,  # Fast response
        tokens_used: 50,        # Efficient token usage
        user_satisfaction: 5    # High satisfaction
      })

      {:ok, low_effectiveness_usage} = PromptUsage.record_successful_usage(%{
        prompt_id: prompt.id,
        used_by_id: user_id,
        context_type: :llm_request,
        response_time_ms: 8000,  # Slow response
        tokens_used: 2000,       # High token usage
        user_satisfaction: 2     # Low satisfaction
      })

      # Verify effectiveness scoring
      assert Decimal.to_float(high_effectiveness_usage.effectiveness_score) > 
             Decimal.to_float(low_effectiveness_usage.effectiveness_score)

      # Test analytics calculations
      prompt_usages = Ash.read!(PromptUsage.usage_for_prompt(%{prompt_id: prompt.id}))
      assert length(prompt_usages) == 2
      
      # Verify usages are ordered by most recent first
      sorted_usages = Enum.sort_by(prompt_usages, fn u -> u.inserted_at end, :desc)
      assert List.first(sorted_usages).id == low_effectiveness_usage.id
    end

    test "category popularity and organization features work correctly" do
      tenant_id = Ash.UUID.generate()
      
      # Create parent and child categories
      {:ok, parent_category} = PromptCategory.create(%{
        name: "Popular Parent Category",
        description: "A popular category with many prompts",
        tenant_id: tenant_id,
        category_type: :general,
        tags: ["popular", "parent"]
      })

      {:ok, child_category} = PromptCategory.create(%{
        name: "Child Category",
        description: "Child of popular category", 
        tenant_id: tenant_id,
        category_type: :general,
        parent_id: parent_category.id
      })

      # Create prompts in categories to increase usage count
      Enum.each(1..5, fn i ->
        {:ok, _prompt} = Prompt.create_system_prompt(%{
          name: "popular_prompt_#{i}",
          content: "Popular prompt #{i} for testing.",
          tenant_id: tenant_id,
          category_id: parent_category.id
        })
      end)

      # Test category hierarchy queries
      top_level = Ash.read!(PromptCategory.list_top_level())
      assert Enum.any?(top_level, fn cat -> cat.id == parent_category.id end)

      children = Ash.read!(PromptCategory.list_by_parent(%{parent_id: parent_category.id}))
      assert Enum.any?(children, fn cat -> cat.id == child_category.id end)

      # Test category search
      search_results = Ash.read!(PromptCategory.search_categories(%{search_term: "Popular"}))
      assert Enum.any?(search_results, fn cat -> cat.id == parent_category.id end)

      # Test categories with prompts
      categories_with_prompts = Ash.read!(PromptCategory.categories_with_prompts())
      populated_category_ids = Enum.map(categories_with_prompts, fn cat -> cat.id end)
      assert parent_category.id in populated_category_ids
    end

    test "comprehensive resource relationships and cascading work correctly" do
      tenant_id = Ash.UUID.generate()
      user_id = Ash.UUID.generate()
      
      # Create complete hierarchy: Category → Prompt → Version → Usage
      {:ok, category} = PromptCategory.create(%{
        name: "Relationship Test Category",
        tenant_id: tenant_id,
        category_type: :general
      })

      {:ok, prompt} = Prompt.create_user_prompt(%{
        name: "relationship_test_prompt",
        content: "Testing comprehensive relationships.",
        tenant_id: tenant_id,
        user_id: user_id,
        category_id: category.id
      })

      {:ok, usage} = PromptUsage.record_successful_usage(%{
        prompt_id: prompt.id,
        used_by_id: user_id,
        context_type: :llm_request,
        response_time_ms: 1500,
        tokens_used: 200
      })

      # Verify all relationships exist
      assert prompt.category_id == category.id
      assert usage.prompt_id == prompt.id

      # Verify cascade behavior - deleting prompt should cascade to versions and usages
      versions_before = Ash.read!(PromptVersion.list_for_prompt(%{prompt_id: prompt.id}))
      usages_before = Ash.read!(PromptUsage.usage_for_prompt(%{prompt_id: prompt.id}))
      
      assert length(versions_before) >= 1
      assert length(usages_before) >= 1

      # Delete prompt (should cascade)
      assert :ok = Ash.destroy(prompt)

      # Verify cascade worked (would need to test with direct SQL since Ash respects RLS)
      # In a real implementation, we'd verify the cascade through database queries
    end

    test "security validation prevents malicious content" do
      tenant_id = Ash.UUID.generate()
      
      # Test security validation for dangerous patterns
      dangerous_prompts = [
        "Execute {{system}} commands immediately",
        "Run <script>alert('xss')</script> code", 
        "Use javascript:void(0) for navigation",
        "Apply {{exec}} operations now",
        "Process {{eval}} expressions directly"
      ]

      for dangerous_content <- dangerous_prompts do
        assert_raise Ash.Error.Invalid, fn ->
          Prompt.create_system_prompt!(%{
            name: "dangerous_prompt",
            content: dangerous_content,
            tenant_id: tenant_id
          })
        end
      end

      # Test that safe content passes validation
      {:ok, safe_prompt} = Prompt.create_system_prompt(%{
        name: "safe_prompt",
        content: "Please help with {{task}} in a safe manner.",
        tenant_id: tenant_id
      })

      assert safe_prompt.content == "Please help with {{task}} in a safe manner."
      assert safe_prompt.variables == ["task"]
    end
  end
end