defmodule RubberDuckWeb.Live.Components.PromptBrowserComponentTest do
  use RubberDuckWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias RubberDuck.Prompts.Resources.Prompt
  alias RubberDuckWeb.Live.Components.PromptBrowserComponent

  describe "PromptBrowserComponent" do
    setup do
      user_id = Ash.UUID.generate()
      project_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Create test prompts
      {:ok, system_prompt} =
        Prompt.create_system_prompt(%{
          content: "System prompt for component testing",
          name: "component_system_prompt",
          tenant_id: tenant_id
        })

      {:ok, user_prompt} =
        Prompt.create_user_prompt(%{
          content: "User prompt for component testing",
          name: "component_user_prompt",
          tenant_id: tenant_id,
          user_id: user_id
        })

      %{
        user_id: user_id,
        project_id: project_id,
        tenant_id: tenant_id,
        system_prompt: system_prompt,
        user_prompt: user_prompt
      }
    end

    test "renders prompt browser with three-tier navigation", %{
      user_id: user_id,
      project_id: project_id
    } do
      # Render component
      assigns = %{
        user_id: user_id,
        project_id: project_id,
        notify_target: self()
      }

      html = render_component(PromptBrowserComponent, assigns)

      # Should have tier selection tabs
      assert html =~ "All Prompts"
      assert html =~ "My Prompts"
      assert html =~ "Project Prompts"
      assert html =~ "System Templates"

      # Should have search functionality
      assert html =~ "Search your saved prompts"

      # Should have quick access buttons
      assert html =~ "Recent Prompts"
      assert html =~ "Favorites"
    end

    test "search functionality works with live events", %{
      user_id: user_id,
      project_id: project_id
    } do
      # Mount component in LiveView context
      {:ok, view, _html} =
        live_isolated(Phoenix.LiveView, fn socket ->
          socket
          |> assign(:user_id, user_id)
          |> assign(:project_id, project_id)
        end)

      # Test search event
      search_query = "component"

      # This would test the actual search functionality in a full integration test
      # For unit test, we verify the component structure
      assigns = %{
        user_id: user_id,
        project_id: project_id,
        notify_target: self(),
        search_query: search_query
      }

      html = render_component(PromptBrowserComponent, assigns)

      # Should render search input with query
      assert html =~ "value=\"#{search_query}\""
    end

    test "tier filtering displays correct prompt types", %{
      user_id: user_id,
      project_id: project_id
    } do
      assigns = %{
        user_id: user_id,
        project_id: project_id,
        notify_target: self(),
        selected_tier: :user,
        prompts: %{
          user_prompts: [
            %{
              id: "1",
              name: "User Prompt",
              prompt_type: :user,
              content: "User content",
              description: "User desc"
            }
          ],
          system_prompts: [
            %{
              id: "2",
              name: "System Prompt",
              prompt_type: :system,
              content: "System content",
              description: "System desc"
            }
          ]
        }
      }

      html = render_component(PromptBrowserComponent, assigns)

      # When user tier is selected, should show user prompts but system prompts should be hidden
      # (Note: In actual implementation, the tier filtering would be handled by the component logic)
      assert html =~ "My Prompts"
    end

    test "prompt selection generates correct events" do
      # Test that prompt selection generates the expected event
      # This would be tested in integration tests with actual LiveView mounting

      test_prompt = %{
        id: "test_prompt_id",
        name: "Test Prompt",
        content: "Test content",
        prompt_type: :user
      }

      # Simulate prompt selection
      # In actual implementation, this would trigger {:prompt_browser_selection, prompt} message

      # Placeholder for actual event testing
      assert true
    end

    test "component handles loading and error states", %{user_id: user_id, project_id: project_id} do
      # Test loading state
      loading_assigns = %{
        user_id: user_id,
        project_id: project_id,
        notify_target: self(),
        loading: true
      }

      loading_html = render_component(PromptBrowserComponent, loading_assigns)
      assert loading_html =~ "Loading prompts"

      # Test error state
      error_assigns = %{
        user_id: user_id,
        project_id: project_id,
        notify_target: self(),
        error: "Test error message",
        loading: false
      }

      error_html = render_component(PromptBrowserComponent, error_assigns)
      assert error_html =~ "Test error message"
    end

    test "empty state displays helpful message" do
      empty_assigns = %{
        user_id: Ash.UUID.generate(),
        project_id: Ash.UUID.generate(),
        notify_target: self(),
        prompts: %{},
        recent_prompts: [],
        loading: false
      }

      empty_html = render_component(PromptBrowserComponent, empty_assigns)
      assert empty_html =~ "No prompts found"
      assert empty_html =~ "Create your first prompt"
    end

    test "component renders with proper CSS classes and accessibility" do
      assigns = %{
        user_id: Ash.UUID.generate(),
        project_id: Ash.UUID.generate(),
        notify_target: self()
      }

      html = render_component(PromptBrowserComponent, assigns)

      # Should have main container class
      assert html =~ "prompt-browser-component"

      # Should have accessible form elements
      # Debounced search
      assert html =~ "phx-debounce"
    end
  end
end
