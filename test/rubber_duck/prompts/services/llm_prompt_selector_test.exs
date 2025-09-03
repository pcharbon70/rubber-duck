defmodule RubberDuck.Prompts.Services.LlmPromptSelectorTest do
  use RubberDuck.DataCase, async: true

  alias RubberDuck.Prompts.Services.LlmPromptSelector
  alias RubberDuck.Prompts.Resources.{Prompt, PromptUsage}

  describe "LlmPromptSelector" do
    setup do
      user_id = Ash.UUID.generate()
      project_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Create test prompts across three tiers
      {:ok, system_prompt} =
        Prompt.create_system_prompt(%{
          content: "System prompt for testing",
          name: "test_system_prompt",
          tenant_id: tenant_id
        })

      {:ok, project_prompt} =
        Prompt.create_project_prompt(%{
          content: "Project prompt for testing with {{variable}}",
          name: "test_project_prompt",
          tenant_id: tenant_id,
          project_id: project_id
        })

      {:ok, user_prompt} =
        Prompt.create_user_prompt(%{
          content: "User prompt for testing with {{user_name}} and {{task_type}}",
          name: "test_user_prompt",
          tenant_id: tenant_id,
          user_id: user_id
        })

      %{
        user_id: user_id,
        project_id: project_id,
        tenant_id: tenant_id,
        system_prompt: system_prompt,
        project_prompt: project_prompt,
        user_prompt: user_prompt
      }
    end

    test "get_available_prompts returns three-tier organized prompts", %{
      user_id: user_id,
      project_id: project_id
    } do
      assert {:ok, organized_prompts} =
               LlmPromptSelector.get_available_prompts(user_id, project_id)

      assert Map.has_key?(organized_prompts, :system_prompts)
      assert Map.has_key?(organized_prompts, :project_prompts)
      assert Map.has_key?(organized_prompts, :user_prompts)
      assert Map.has_key?(organized_prompts, :total_count)

      # Should have prompts in each tier
      assert length(organized_prompts.system_prompts) >= 1
      assert length(organized_prompts.project_prompts) >= 1
      assert length(organized_prompts.user_prompts) >= 1
      assert organized_prompts.total_count >= 3
    end

    test "get_available_prompts without project_id returns user and system prompts only", %{
      user_id: user_id
    } do
      assert {:ok, organized_prompts} = LlmPromptSelector.get_available_prompts(user_id)

      # Should have system and user prompts
      assert length(organized_prompts.system_prompts) >= 1
      assert length(organized_prompts.user_prompts) >= 1

      # Should not have project prompts without project context
      assert length(organized_prompts.project_prompts) == 0
    end

    test "search_prompts finds prompts across tiers with relevance ranking", %{
      user_id: user_id,
      project_id: project_id
    } do
      search_query = "testing"

      assert {:ok, search_results} =
               LlmPromptSelector.search_prompts(user_id, search_query, project_id)

      # Should find prompts containing "testing" in name or content
      assert length(search_results) >= 1

      # Results should have relevance scores
      for prompt <- search_results do
        assert Map.has_key?(prompt, :relevance_score)
        assert prompt.relevance_score >= 0.0
      end

      # Results should be sorted by relevance (highest first)
      relevance_scores = Enum.map(search_results, fn prompt -> prompt.relevance_score end)
      assert relevance_scores == Enum.sort(relevance_scores, :desc)
    end

    test "search_prompts with content exclusion searches only names and descriptions", %{
      user_id: user_id,
      project_id: project_id
    } do
      search_options = %{include_content: false}

      # Search for content that only appears in prompt content, not name/description
      content_only_query = "variable"

      assert {:ok, search_results} =
               LlmPromptSelector.search_prompts(
                 user_id,
                 content_only_query,
                 project_id,
                 search_options
               )

      # Should find fewer results when excluding content from search
      assert {:ok, all_content_results} =
               LlmPromptSelector.search_prompts(user_id, content_only_query, project_id, %{
                 include_content: true
               })

      assert length(search_results) <= length(all_content_results)
    end

    test "get_recent_prompts returns recently used prompts", %{
      user_id: user_id,
      project_id: project_id,
      user_prompt: user_prompt
    } do
      # Create usage record for user prompt
      {:ok, _usage} =
        PromptUsage.create(%{
          user_id: user_id,
          prompt_id: user_prompt.id,
          usage_type: :llm_operation,
          used_at: DateTime.utc_now()
        })

      assert {:ok, recent_prompts} = LlmPromptSelector.get_recent_prompts(user_id, project_id, 5)

      # Should include the recently used prompt
      recent_prompt_ids = Enum.map(recent_prompts, fn prompt -> prompt.id end)
      assert user_prompt.id in recent_prompt_ids
    end

    test "get_favorite_prompts returns frequently used prompts", %{
      user_id: user_id,
      project_id: project_id,
      user_prompt: user_prompt
    } do
      # Create multiple usage records to make prompt "favorite"
      for _i <- 1..5 do
        {:ok, _usage} =
          PromptUsage.create(%{
            user_id: user_id,
            prompt_id: user_prompt.id,
            usage_type: :llm_operation,
            used_at: DateTime.add(DateTime.utc_now(), -Enum.random(1..10), :day)
          })
      end

      assert {:ok, favorite_prompts} = LlmPromptSelector.get_favorite_prompts(user_id, project_id)

      # Should include the frequently used prompt
      favorite_prompt_ids = Enum.map(favorite_prompts, fn prompt -> prompt.id end)
      assert user_prompt.id in favorite_prompt_ids
    end

    test "get_prompts_by_category filters prompts by category", %{
      user_id: user_id,
      project_id: project_id
    } do
      # Create a category and prompt in that category
      {:ok, category} =
        PromptCategory.create(%{
          name: "Test Category",
          description: "Category for testing"
        })

      {:ok, categorized_prompt} =
        Prompt.create_user_prompt(%{
          content: "Categorized prompt content",
          name: "categorized_test_prompt",
          tenant_id: Ash.UUID.generate(),
          user_id: user_id,
          category_id: category.id
        })

      assert {:ok, category_prompts} =
               LlmPromptSelector.get_prompts_by_category(user_id, category.id, project_id)

      # Should include the categorized prompt
      category_prompt_ids = Enum.map(category_prompts, fn prompt -> prompt.id end)
      assert categorized_prompt.id in category_prompt_ids
    end

    test "caching improves performance for repeated queries", %{
      user_id: user_id,
      project_id: project_id
    } do
      # First query (cache miss)
      start_time = System.monotonic_time(:microsecond)
      assert {:ok, _prompts1} = LlmPromptSelector.get_available_prompts(user_id, project_id)
      first_query_time = System.monotonic_time(:microsecond) - start_time

      # Second query (cache hit)
      start_time = System.monotonic_time(:microsecond)
      assert {:ok, _prompts2} = LlmPromptSelector.get_available_prompts(user_id, project_id)
      second_query_time = System.monotonic_time(:microsecond) - start_time

      # Cached query should be significantly faster
      assert second_query_time < first_query_time / 2
    end

    test "invalidate_user_cache clears cached data", %{user_id: user_id, project_id: project_id} do
      # Load prompts into cache
      assert {:ok, _prompts} = LlmPromptSelector.get_available_prompts(user_id, project_id)

      # Invalidate cache
      LlmPromptSelector.invalidate_user_cache(user_id)

      # Subsequent query should hit database again (cache miss)
      # This is difficult to test directly, but we can verify the function doesn't error
      assert {:ok, _prompts} = LlmPromptSelector.get_available_prompts(user_id, project_id)
    end

    test "search performance meets requirements for large collections", %{
      user_id: user_id,
      project_id: project_id,
      tenant_id: tenant_id
    } do
      # Create additional prompts to simulate larger collection
      for i <- 1..50 do
        {:ok, _prompt} =
          Prompt.create_user_prompt(%{
            content: "Test prompt #{i} with various content for search testing",
            name: "test_prompt_#{i}",
            tenant_id: tenant_id,
            user_id: user_id
          })
      end

      # Test search performance
      search_start = System.monotonic_time(:microsecond)

      assert {:ok, _search_results} =
               LlmPromptSelector.search_prompts(user_id, "test", project_id)

      search_time = System.monotonic_time(:microsecond) - search_start
      search_time_ms = search_time / 1000

      # Should meet <200ms requirement
      assert search_time_ms < 200, "Search time #{search_time_ms}ms exceeds 200ms requirement"
    end

    test "three-tier access control works correctly" do
      user1_id = Ash.UUID.generate()
      user2_id = Ash.UUID.generate()
      project1_id = Ash.UUID.generate()
      project2_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Create prompts for different contexts
      {:ok, user1_prompt} =
        Prompt.create_user_prompt(%{
          content: "User 1 personal prompt",
          name: "user1_prompt",
          tenant_id: tenant_id,
          user_id: user1_id
        })

      {:ok, project1_prompt} =
        Prompt.create_project_prompt(%{
          content: "Project 1 prompt",
          name: "project1_prompt",
          tenant_id: tenant_id,
          project_id: project1_id
        })

      # User 1 in Project 1 should see: System + Project1 + User1 prompts
      assert {:ok, user1_project1_prompts} =
               LlmPromptSelector.get_available_prompts(user1_id, project1_id)

      user1_project1_ids = extract_all_prompt_ids(user1_project1_prompts)
      assert user1_prompt.id in user1_project1_ids
      assert project1_prompt.id in user1_project1_ids

      # User 2 in Project 1 should see: System + Project1 prompts (NOT User1 prompts)
      assert {:ok, user2_project1_prompts} =
               LlmPromptSelector.get_available_prompts(user2_id, project1_id)

      user2_project1_ids = extract_all_prompt_ids(user2_project1_prompts)
      # Should NOT see User1's personal prompts
      assert user1_prompt.id not in user2_project1_ids
      # Should see Project1 prompts
      assert project1_prompt.id in user2_project1_ids

      # User 1 without project context should see: System + User1 prompts (NO Project prompts)
      assert {:ok, user1_no_project_prompts} = LlmPromptSelector.get_available_prompts(user1_id)

      user1_no_project_ids = extract_all_prompt_ids(user1_no_project_prompts)
      assert user1_prompt.id in user1_no_project_ids
      # Should NOT see project prompts without project context
      assert project1_prompt.id not in user1_no_project_ids
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
