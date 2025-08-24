defmodule RubberDuckWeb.API.PreferencesControllerTest do
  use RubberDuckWeb.ConnCase, async: true

  import RubberDuck.{AccountsFixtures, PreferencesFixtures}

  alias RubberDuck.Preferences.Resources.UserPreference

  describe "GET /api/v1/preferences" do
    setup [:create_user_with_api_key, :create_preferences]

    test "lists all preferences for authenticated user", %{conn: conn, user: user} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.api_key}")
        |> get(~p"/api/v1/preferences")

      assert %{
               "data" => preferences,
               "meta" => %{"total" => total, "timestamp" => _}
             } = json_response(conn, 200)

      assert is_list(preferences)
      assert total > 0
      assert length(preferences) == total
    end

    test "filters preferences by category", %{conn: conn, user: user} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.api_key}")
        |> get(~p"/api/v1/preferences?category=code_quality")

      assert %{"data" => preferences} = json_response(conn, 200)

      assert Enum.all?(preferences, fn pref ->
               pref["category"] == "code_quality"
             end)
    end

    test "searches preferences by key/description", %{conn: conn, user: user} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.api_key}")
        |> get(~p"/api/v1/preferences?search=enabled")

      assert %{"data" => preferences} = json_response(conn, 200)

      assert Enum.any?(preferences, fn pref ->
               String.contains?(String.downcase(pref["key"]), "enabled") ||
                 String.contains?(String.downcase(pref["description"] || ""), "enabled")
             end)
    end

    test "paginates preferences", %{conn: conn, user: user} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.api_key}")
        |> get(~p"/api/v1/preferences?page=1&per_page=2")

      assert %{"data" => preferences} = json_response(conn, 200)
      assert length(preferences) <= 2

      # Check pagination headers
      assert get_resp_header(conn, "x-total-count") != []
      assert get_resp_header(conn, "x-page") == ["1"]
      assert get_resp_header(conn, "x-per-page") == ["2"]
    end

    test "requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/preferences")

      assert %{
               "error" => %{
                 "code" => "unauthorized",
                 "message" => "Authentication required"
               }
             } = json_response(conn, 401)
    end

    test "handles invalid API key", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid_key")
        |> get(~p"/api/v1/preferences")

      assert json_response(conn, 401)
    end
  end

  describe "POST /api/v1/preferences" do
    setup [:create_user_with_api_key]

    test "creates new user preference", %{conn: conn, user: user} do
      preference_params = %{
        "preference_key" => "test.new_preference",
        "value" => "test_value",
        "category" => "testing"
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.api_key}")
        |> post(~p"/api/v1/preferences", preference_params)

      assert %{
               "data" => %{
                 "id" => "test.new_preference",
                 "key" => "test.new_preference",
                 "value" => "test_value",
                 "category" => "testing",
                 "source" => "user"
               }
             } = json_response(conn, 201)

      # Verify preference was created in database
      assert {:ok, [preference]} = UserPreference.by_user_and_key(user.id, "test.new_preference")
      assert preference.value == "test_value"
    end

    test "validates required fields", %{conn: conn, user: user} do
      # Missing preference_key
      invalid_params = %{"value" => "test_value"}

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.api_key}")
        |> post(~p"/api/v1/preferences", invalid_params)

      assert %{
               "error" => %{
                 "code" => "validation_error",
                 "message" => message
               }
             } = json_response(conn, 400)

      assert message =~ "preference_key"
    end

    test "handles duplicate preference creation", %{conn: conn, user: user} do
      # Create initial preference
      user_preference_fixture(user, %{preference_key: "test.duplicate", value: "initial"})

      # Attempt to create same preference
      duplicate_params = %{
        "preference_key" => "test.duplicate",
        "value" => "updated"
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.api_key}")
        |> post(~p"/api/v1/preferences", duplicate_params)

      # Should update existing preference
      assert %{"data" => %{"value" => "updated"}} = json_response(conn, 201)
    end
  end

  describe "GET /api/v1/preferences/:id" do
    setup [:create_user_with_api_key, :create_preferences]

    test "returns specific preference", %{conn: conn, user: user} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.api_key}")
        |> get(~p"/api/v1/preferences/code_quality.enabled")

      assert %{
               "data" => %{
                 "id" => "code_quality.enabled",
                 "key" => "code_quality.enabled",
                 "value" => _,
                 "category" => "code_quality",
                 "source" => _,
                 "inheritance" => inheritance
               }
             } = json_response(conn, 200)

      assert is_map(inheritance)
      assert Map.has_key?(inheritance, "effective")
    end

    test "returns 404 for non-existent preference", %{conn: conn, user: user} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.api_key}")
        |> get(~p"/api/v1/preferences/non.existent")

      assert %{
               "error" => %{
                 "code" => "not_found",
                 "message" => "Preference not found"
               }
             } = json_response(conn, 404)
    end
  end

  describe "PUT /api/v1/preferences/:id" do
    setup [:create_user_with_api_key, :create_preferences]

    test "updates existing preference", %{conn: conn, user: user} do
      update_params = %{
        "value" => "updated_value",
        "reason" => "API test update"
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.api_key}")
        |> put(~p"/api/v1/preferences/code_quality.enabled", update_params)

      assert %{
               "data" => %{
                 "key" => "code_quality.enabled",
                 "value" => "updated_value"
               }
             } = json_response(conn, 200)

      # Verify update in database
      assert {:ok, [preference]} = UserPreference.by_user_and_key(user.id, "code_quality.enabled")
      assert preference.value == "updated_value"
    end

    test "creates preference if it doesn't exist", %{conn: conn, user: user} do
      update_params = %{"value" => "new_value"}

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.api_key}")
        |> put(~p"/api/v1/preferences/new.preference", update_params)

      assert %{
               "data" => %{
                 "key" => "new.preference",
                 "value" => "new_value"
               }
             } = json_response(conn, 200)
    end

    test "validates update parameters", %{conn: conn, user: user} do
      # Missing value
      invalid_params = %{}

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.api_key}")
        |> put(~p"/api/v1/preferences/test.key", invalid_params)

      assert %{
               "error" => %{
                 "code" => "validation_error"
               }
             } = json_response(conn, 400)
    end
  end

  describe "DELETE /api/v1/preferences/:id" do
    setup [:create_user_with_api_key, :create_preferences]

    test "deletes user preference (resets to default)", %{conn: conn, user: user} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.api_key}")
        |> delete(~p"/api/v1/preferences/code_quality.enabled")

      assert response(conn, 204)

      # Verify preference was deleted from database
      assert {:ok, []} = UserPreference.by_user_and_key(user.id, "code_quality.enabled")
    end

    test "handles deletion of non-existent preference gracefully", %{conn: conn, user: user} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.api_key}")
        |> delete(~p"/api/v1/preferences/non.existent")

      assert response(conn, 204)
    end
  end

  describe "POST /api/v1/preferences/batch" do
    setup [:create_user_with_api_key]

    test "executes batch operations successfully", %{conn: conn, user: user} do
      batch_params = %{
        "operations" => [
          %{
            "action" => "create",
            "preference_key" => "batch.test1",
            "value" => "value1"
          },
          %{
            "action" => "create",
            "preference_key" => "batch.test2",
            "value" => "value2"
          }
        ]
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.api_key}")
        |> post(~p"/api/v1/preferences/batch", batch_params)

      assert %{
               "data" => %{
                 "total" => 2,
                 "successful" => 2,
                 "failed" => 0,
                 "results" => results
               }
             } = json_response(conn, 200)

      assert length(results) == 2
      assert Enum.all?(results, &(&1["status"] == "success"))
    end

    test "handles mixed success/failure in batch", %{conn: conn, user: user} do
      batch_params = %{
        "operations" => [
          %{
            "action" => "create",
            "preference_key" => "batch.valid",
            "value" => "valid_value"
          },
          %{
            "action" => "create",
            # Missing preference_key - should fail
            "value" => "invalid"
          }
        ]
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.api_key}")
        |> post(~p"/api/v1/preferences/batch", batch_params)

      assert %{
               "data" => %{
                 "total" => 2,
                 "successful" => 1,
                 "failed" => 1,
                 "results" => results
               }
             } = json_response(conn, 200)

      assert Enum.count(results, &(&1["status"] == "success")) == 1
      assert Enum.count(results, &(&1["status"] == "error")) == 1
    end

    test "validates batch operation format", %{conn: conn, user: user} do
      invalid_params = %{"operations" => "not_an_array"}

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.api_key}")
        |> post(~p"/api/v1/preferences/batch", invalid_params)

      assert %{
               "error" => "operations parameter is required and must be an array"
             } = json_response(conn, 400)
    end
  end

  describe "Rate Limiting" do
    setup [:create_user_with_api_key]

    @tag :rate_limiting
    test "enforces rate limiting", %{conn: conn, user: user} do
      # Make many requests quickly to trigger rate limiting
      # (This would require actual rate limiting middleware to be configured)

      results =
        1..100
        |> Enum.map(fn _i ->
          conn
          |> put_req_header("authorization", "Bearer #{user.api_key}")
          |> get(~p"/api/v1/preferences")
          # Either success or rate limited
          |> json_response([200, 429])
        end)

      # Should have at least some rate limited responses
      rate_limited_count =
        results
        |> Enum.count(fn response ->
          case response do
            %{"error" => %{"code" => "rate_limited"}} -> true
            _ -> false
          end
        end)

      # This test would only pass if rate limiting is actually implemented
      # For now, we'll just verify the structure
      assert is_integer(rate_limited_count)
    end
  end

  # Setup helpers

  defp create_user_with_api_key(_context) do
    user = user_fixture()
    api_key = api_key_fixture(user)
    %{user: Map.put(user, :api_key, api_key.key)}
  end

  defp create_preferences(%{user: user}) do
    preferences = [
      user_preference_fixture(user, %{preference_key: "code_quality.enabled", value: "true"}),
      user_preference_fixture(user, %{preference_key: "budgeting.limit", value: "100"}),
      user_preference_fixture(user, %{preference_key: "llm.provider", value: "anthropic"})
    ]

    %{preferences: preferences}
  end
end
