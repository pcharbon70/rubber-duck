defmodule RubberDuckWeb.Preferences.DashboardLiveTest do
  use RubberDuckWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import RubberDuck.{AccountsFixtures, PreferencesFixtures}

  describe "Dashboard LiveView" do
    setup do
      user = user_fixture()
      preferences = preferences_fixture(user)
      categories = categories_fixture()

      %{user: user, preferences: preferences, categories: categories}
    end

    test "renders dashboard with preferences list", %{conn: conn, user: user} do
      {:ok, _view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/preferences")

      assert html =~ "Preference Management"
      assert html =~ "Total:"
    end

    test "filters preferences by category", %{conn: conn, user: user} do
      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/preferences")

      # Click on a category filter
      view
      |> element("a", "Code Quality")
      |> render_click()

      assert_patch(view, ~p"/preferences?category=code_quality")

      # Verify filtered results
      html = render(view)
      assert html =~ "Code Quality Preferences"
    end

    test "searches preferences", %{conn: conn, user: user} do
      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/preferences")

      # Search for a specific preference
      view
      |> form("[phx-change='search']")
      |> render_change(%{search: %{query: "code_quality"}})

      html = render(view)
      assert html =~ "code_quality"
      refute html =~ "budgeting"
    end

    test "toggles project context", %{conn: conn, user: user} do
      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/preferences")

      # Switch to project context
      view
      |> form("select[name='project_id']")
      |> render_change(%{"project_id" => "proj1"})

      html = render(view)
      assert html =~ "Example Project (Project)"
    end

    test "quick edits preference value", %{conn: conn, user: user} do
      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/preferences")

      # Quick edit a preference
      view
      |> form("[phx-submit='quick_edit']", %{key: "test.preference", value: "new_value"})
      |> render_submit()

      assert render(view) =~ "Updated test.preference"
    end

    test "handles real-time preference updates", %{conn: conn, user: user} do
      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/preferences")

      # Simulate a preference change from another source
      send(
        view.pid,
        {:preference_changed,
         %{
           user_id: user.id,
           preference_key: "test.preference",
           old_value: "old",
           new_value: "new",
           source: "external"
         }}
      )

      # Should trigger a re-render with updated data
      html = render(view)
      assert html =~ "new"
    end

    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log_in"}}} =
               live(conn, ~p"/preferences")
    end

    test "handles empty preferences gracefully", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/preferences")

      assert html =~ "No preferences found"
    end

    test "displays correct preference sources", %{conn: conn, user: user} do
      # Create user preference override
      user_preference_fixture(user, %{preference_key: "test.key", value: "user_value"})

      {:ok, _view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/preferences")

      # Source badge
      assert html =~ "User"
    end
  end

  describe "Dashboard LiveView Error Handling" do
    setup do
      user = user_fixture()
      %{user: user}
    end

    test "handles preference loading errors gracefully", %{conn: conn, user: user} do
      # Mock a system error scenario
      with_mock RubberDuck.Preferences.Resources.SystemDefault, [:passthrough],
        read: fn -> {:error, "Database error"} end do
        {:ok, _view, html} =
          conn
          |> log_in_user(user)
          |> live(~p"/preferences")

        assert html =~ "No preferences found"
      end
    end

    test "handles validation errors on quick edit", %{conn: conn, user: user} do
      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/preferences")

      # Attempt invalid quick edit
      view
      |> form("[phx-submit='quick_edit']", %{key: "invalid.key", value: ""})
      |> render_submit()

      assert render(view) =~ "Failed to update"
    end
  end

  describe "Dashboard LiveView Performance" do
    setup do
      user = user_fixture()
      # Create a large number of preferences for performance testing
      preferences = create_many_preferences(user, 100)

      %{user: user, preferences: preferences}
    end

    test "handles large preference lists efficiently", %{conn: conn, user: user} do
      start_time = System.monotonic_time()

      {:ok, _view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/preferences")

      end_time = System.monotonic_time()
      duration = System.convert_time_unit(end_time - start_time, :native, :millisecond)

      # Should load within reasonable time (< 2 seconds)
      assert duration < 2000
      assert html =~ "100 preferences"
    end

    test "search performs efficiently with large datasets", %{conn: conn, user: user} do
      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/preferences")

      start_time = System.monotonic_time()

      view
      |> form("[phx-change='search']")
      |> render_change(%{search: %{query: "code"}})

      end_time = System.monotonic_time()
      duration = System.convert_time_unit(end_time - start_time, :native, :millisecond)

      # Search should be fast (< 500ms)
      assert duration < 500
    end
  end

  # Helper functions

  defp preferences_fixture(user) do
    [
      user_preference_fixture(user, %{preference_key: "code_quality.enabled", value: "true"}),
      user_preference_fixture(user, %{preference_key: "budgeting.limit", value: "100"}),
      user_preference_fixture(user, %{preference_key: "llm.provider", value: "anthropic"})
    ]
  end

  defp categories_fixture do
    [
      %{name: "code_quality", display_name: "Code Quality"},
      %{name: "budgeting", display_name: "Budgeting"},
      %{name: "llm", display_name: "LLM"}
    ]
  end

  defp create_many_preferences(user, count) do
    1..count
    |> Enum.map(fn i ->
      category = Enum.random(["code_quality", "llm", "ml", "budgeting"])

      user_preference_fixture(user, %{
        preference_key: "#{category}.test_#{i}",
        value: "value_#{i}"
      })
    end)
  end
end
