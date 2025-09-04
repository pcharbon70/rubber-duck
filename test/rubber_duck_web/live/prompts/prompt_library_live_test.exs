defmodule RubberDuckWeb.Live.Prompts.PromptLibraryLiveTest do
  use RubberDuckWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "PromptLibraryLive" do
    test "renders prompt library page", %{conn: conn} do
      # Note: This test assumes authentication is properly set up
      {:ok, _view, html} = live(conn, ~p"/prompts")

      assert html =~ "Prompt Library"
      assert html =~ "New Prompt"
    end

    test "handles view mode changes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/prompts")

      # Test view mode changes
      view
      |> element("button[phx-click='change_view_mode'][phx-value-mode='grid']")
      |> render_click()

      # Should not crash and should update view mode
      assert has_element?(view, ".prompt-grid")
    end

    test "handles search functionality", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/prompts")

      # Test search input
      view
      |> form("form", search: %{query: "test"})
      |> render_change()

      # Should not crash and should trigger search
      assert_receive {:prompt_search_triggered, "test"}
    end

    test "handles bulk action mode toggle", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/prompts")

      # Test bulk action toggle
      view
      |> element("button[phx-click='toggle_bulk_action_mode']")
      |> render_click()

      # Should toggle bulk action mode without crashing
      assert has_element?(view, "[data-bulk-mode='true']")
    end
  end
end