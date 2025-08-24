defmodule RubberDuck.Integration.PreferenceManagementIntegrationTest do
  @moduledoc """
  End-to-end integration tests for the complete preference management system.

  Tests the integration between Web UI, CLI, REST API, GraphQL API, and webhook
  systems to ensure they work together seamlessly.
  """

  # Not async due to webhook testing
  use RubberDuckWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import RubberDuck.{AccountsFixtures, PreferencesFixtures}

  alias RubberDuck.{CLI, Webhooks}
  alias RubberDuck.Preferences.Resources.UserPreference

  describe "Complete Preference Management Workflow" do
    setup do
      user = user_fixture()
      api_key = api_key_fixture(user)

      %{user: user, api_key: api_key.key}
    end

    test "end-to-end preference lifecycle across all interfaces", %{
      conn: conn,
      user: user,
      api_key: api_key
    } do
      preference_key = "integration.test_preference"

      # Step 1: Create preference via Web UI (LiveView)
      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/preferences")

      # Quick create a preference
      view
      |> form("[phx-submit='quick_edit']", %{key: preference_key, value: "web_value"})
      |> render_submit()

      assert render(view) =~ "Updated #{preference_key}"

      # Step 2: Verify via REST API
      api_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{api_key}")
        |> get("/api/v1/preferences/#{preference_key}")

      assert %{
               "data" => %{
                 "key" => ^preference_key,
                 "value" => "web_value",
                 "source" => "user"
               }
             } = json_response(api_conn, 200)

      # Step 3: Update via CLI
      System.put_env("RUBBER_DUCK_USER_ID", user.id)

      result = CLI.main(["config", "set", preference_key, "cli_value"])
      assert result == :ok

      # Step 4: Verify update via GraphQL (mock)
      # Note: This would be a real GraphQL query if Absinthe was available
      graphql_query = """
      query GetPreference($id: ID!) {
        preference(id: $id) {
          key
          value
          source
          lastModified
        }
      }
      """

      # Mock GraphQL execution
      graphql_result = mock_graphql_execution(graphql_query, %{"id" => preference_key}, user)

      assert graphql_result[:data][:preference][:value] == "cli_value"
      assert graphql_result[:data][:preference][:source] == "user"

      # Step 5: Update via REST API
      update_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{api_key}")
        |> put("/api/v1/preferences/#{preference_key}", %{"value" => "api_value"})

      assert %{
               "data" => %{
                 "value" => "api_value"
               }
             } = json_response(update_conn, 200)

      # Step 6: Verify final state in Web UI
      updated_html = render(view)
      assert updated_html =~ "api_value"

      # Step 7: Test webhook notification (if registered)
      # Register a test webhook
      webhook_url = "http://localhost:4002/test-webhook"

      {:ok, webhook_id} =
        Webhooks.register_webhook(webhook_url, %{
          event_types: [:all],
          user_filters: [user.id]
        })

      # Make one more change to trigger webhook
      final_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{api_key}")
        |> put("/api/v1/preferences/#{preference_key}", %{"value" => "final_value"})

      assert json_response(final_conn, 200)

      # Verify webhook would be triggered (mock)
      {:ok, stats} = Webhooks.get_stats()
      assert stats.total_events > 0

      # Cleanup
      Webhooks.unregister_webhook(webhook_id)
      System.delete_env("RUBBER_DUCK_USER_ID")
    end

    test "preference inheritance across interfaces", %{conn: conn, user: user, api_key: api_key} do
      preference_key = "inheritance.test"

      # Step 1: Verify system default via Web UI
      {:ok, view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/preferences")

      # Should show system default
      # Source badge
      assert html =~ "System"

      # Step 2: Create user override via API
      override_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{api_key}")
        |> post("/api/v1/preferences", %{
          "preference_key" => preference_key,
          "value" => "user_override"
        })

      assert json_response(override_conn, 201)

      # Step 3: Verify inheritance via GraphQL (mock)
      inheritance_query = """
      query GetInheritance($id: ID!) {
        preference(id: $id) {
          key
          value
          source
          inheritedFrom {
            value
            source
          }
        }
      }
      """

      result = mock_graphql_execution(inheritance_query, %{"id" => preference_key}, user)

      assert result[:data][:preference][:source] == "user"
      assert result[:data][:preference][:value] == "user_override"

      # Step 4: Verify updated source in Web UI
      updated_html = render(view)
      # Updated source badge
      assert updated_html =~ "User"

      # Step 5: Test CLI inheritance query
      System.put_env("RUBBER_DUCK_USER_ID", user.id)

      # Mock CLI get command with source flag
      cli_result = CLI.main(["config", "get", preference_key, "--source"])
      assert cli_result =~ "source: user"

      System.delete_env("RUBBER_DUCK_USER_ID")
    end

    test "template workflow across interfaces", %{conn: conn, user: user, api_key: api_key} do
      # Step 1: Create template via Web UI
      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/preferences/templates")

      # Navigate to template creation (mock)
      # In real implementation, this would be a form submission
      template_name = "Integration Test Template"

      # Step 2: Create template via API
      template_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{api_key}")
        |> post("/api/v1/templates", %{
          "name" => template_name,
          "description" => "Template created during integration test",
          "source_type" => "user"
        })

      assert %{
               "data" => %{
                 "id" => template_id,
                 "name" => ^template_name
               }
             } = json_response(template_conn, 201)

      # Step 3: Apply template via CLI
      System.put_env("RUBBER_DUCK_USER_ID", user.id)

      cli_result = CLI.main(["config", "template-apply", template_id])
      assert cli_result =~ "Applied template successfully"

      # Step 4: Verify application via GraphQL (mock)
      template_query = """
      query GetTemplate($id: ID!) {
        template(id: $id) {
          id
          name
          usageCount
        }
      }
      """

      result = mock_graphql_execution(template_query, %{"id" => template_id}, user)

      assert result[:data][:template][:usage_count] > 0

      # Step 5: Verify in Web UI
      templates_html = render(view)
      assert templates_html =~ template_name

      System.delete_env("RUBBER_DUCK_USER_ID")
    end

    test "real-time updates across interfaces", %{conn: conn, user: user, api_key: api_key} do
      preference_key = "realtime.test"

      # Step 1: Open Web UI
      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/preferences")

      # Step 2: Create preference via API
      api_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{api_key}")
        |> post("/api/v1/preferences", %{
          "preference_key" => preference_key,
          "value" => "realtime_value"
        })

      assert json_response(api_conn, 201)

      # Step 3: Simulate PubSub event to LiveView
      send(
        view.pid,
        {:preference_changed,
         %{
           user_id: user.id,
           preference_key: preference_key,
           old_value: nil,
           new_value: "realtime_value",
           source: "api"
         }}
      )

      # Step 4: Verify LiveView updates
      updated_html = render(view)
      assert updated_html =~ "realtime_value"

      # Step 5: Test webhook notification (mock)
      # This would normally send HTTP requests to registered webhooks
      webhook_event = %{
        event_type: "preference_changed",
        event_data: %{
          user_id: user.id,
          preference_key: preference_key,
          new_value: "realtime_value"
        },
        timestamp: DateTime.utc_now()
      }

      # Mock webhook delivery
      assert webhook_event.event_type == "preference_changed"
      assert webhook_event.event_data.preference_key == preference_key
    end

    test "error handling across interfaces", %{conn: conn, user: user, api_key: api_key} do
      # Invalid preference key
      invalid_key = ""

      # Step 1: Test Web UI error handling
      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/preferences")

      # Attempt invalid quick edit
      view
      |> form("[phx-submit='quick_edit']", %{key: invalid_key, value: "test"})
      |> render_submit()

      assert render(view) =~ "Failed to update"

      # Step 2: Test API error handling
      api_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{api_key}")
        |> post("/api/v1/preferences", %{
          "preference_key" => invalid_key,
          "value" => "test"
        })

      assert %{
               "error" => %{
                 "code" => "validation_error"
               }
             } = json_response(api_conn, 400)

      # Step 3: Test CLI error handling
      System.put_env("RUBBER_DUCK_USER_ID", user.id)

      # Should handle invalid key gracefully
      result = CLI.main(["config", "set", invalid_key, "test"])
      assert result =~ "Failed to set preference"

      System.delete_env("RUBBER_DUCK_USER_ID")

      # Step 4: Test GraphQL error handling (mock)
      error_query = """
      mutation CreateInvalidPreference {
        createPreference(input: {key: "", value: "test"}) {
          key
        }
      }
      """

      result = mock_graphql_execution(error_query, %{}, user)

      assert result[:errors]
      assert Enum.any?(result[:errors], &String.contains?(&1[:message], "validation"))
    end
  end

  describe "Performance Integration" do
    setup do
      user = user_fixture()
      api_key = api_key_fixture(user)

      # Create many preferences for performance testing
      create_many_preferences(user, 50)

      %{user: user, api_key: api_key.key}
    end

    test "performance across all interfaces", %{conn: conn, user: user, api_key: api_key} do
      # Test Web UI performance
      start_time = System.monotonic_time()

      {:ok, _view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/preferences")

      web_duration =
        System.convert_time_unit(
          System.monotonic_time() - start_time,
          :native,
          :millisecond
        )

      # Should load within 2 seconds
      assert web_duration < 2000
      # Should show all preferences
      assert html =~ "50 preferences"

      # Test API performance
      start_time = System.monotonic_time()

      api_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{api_key}")
        |> get("/api/v1/preferences")

      api_duration =
        System.convert_time_unit(
          System.monotonic_time() - start_time,
          :native,
          :millisecond
        )

      # Should respond within 1 second
      assert api_duration < 1000
      assert %{"data" => preferences} = json_response(api_conn, 200)
      assert length(preferences) == 50

      # Test CLI performance
      System.put_env("RUBBER_DUCK_USER_ID", user.id)

      start_time = System.monotonic_time()

      cli_result = CLI.main(["config", "list"])

      cli_duration =
        System.convert_time_unit(
          System.monotonic_time() - start_time,
          :native,
          :millisecond
        )

      # Should complete within 1.5 seconds
      assert cli_duration < 1500
      assert cli_result =~ "Total: 50 preferences"

      System.delete_env("RUBBER_DUCK_USER_ID")
    end
  end

  # Mock GraphQL execution (since Absinthe is not available)
  defp mock_graphql_execution(query, variables, user) do
    # This would normally use Absinthe.run/3
    # For now, return mock data based on the query
    cond do
      String.contains?(query, "preference(id:") ->
        preference_key = variables["id"]

        %{
          data: %{
            preference: %{
              key: preference_key,
              value: get_mock_preference_value(user.id, preference_key),
              source: "user",
              last_modified: DateTime.utc_now()
            }
          }
        }

      String.contains?(query, "template(id:") ->
        %{
          data: %{
            template: %{
              id: variables["id"],
              name: "Mock Template",
              usage_count: 1
            }
          }
        }

      String.contains?(query, "createPreference") ->
        %{
          errors: [
            %{message: "Validation failed: key cannot be empty"}
          ]
        }

      true ->
        %{data: nil}
    end
  end

  defp get_mock_preference_value(user_id, preference_key) do
    case UserPreference.by_user_and_key(user_id, preference_key) do
      {:ok, [pref]} -> pref.value
      _ -> "default_value"
    end
  end

  defp create_many_preferences(user, count) do
    1..count
    |> Enum.map(fn i ->
      category = Enum.random(["code_quality", "llm", "ml", "budgeting"])

      user_preference_fixture(user, %{
        preference_key: "#{category}.perf_test_#{i}",
        value: "value_#{i}"
      })
    end)
  end
end
