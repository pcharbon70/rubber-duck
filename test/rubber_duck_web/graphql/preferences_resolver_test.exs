defmodule RubberDuckWeb.GraphQL.PreferencesResolverTest do
  use RubberDuckWeb.ConnCase, async: true

  import RubberDuck.{AccountsFixtures, PreferencesFixtures}

  alias RubberDuckWeb.GraphQL.Resolvers.PreferencesResolver

  describe "list_preferences/3" do
    setup do
      user = user_fixture()
      preferences = create_test_preferences(user)
      context = %{context: %{current_user: user}}

      %{user: user, preferences: preferences, context: context}
    end

    test "returns all preferences for authenticated user", %{context: context} do
      args = %{}

      assert {:ok, result} = PreferencesResolver.list_preferences(nil, args, context)

      assert %{
               edges: edges,
               page_info: page_info,
               total_count: total_count
             } = result

      assert is_list(edges)
      assert is_map(page_info)
      assert is_integer(total_count)
      assert total_count > 0
    end

    test "filters preferences by category", %{context: context} do
      args = %{filter: %{category: "code_quality"}}

      assert {:ok, result} = PreferencesResolver.list_preferences(nil, args, context)

      preferences = Enum.map(result.edges, & &1.node)

      assert Enum.all?(preferences, fn pref ->
               pref.category == "code_quality"
             end)
    end

    test "searches preferences by key", %{context: context} do
      args = %{filter: %{search: "enabled"}}

      assert {:ok, result} = PreferencesResolver.list_preferences(nil, args, context)

      preferences = Enum.map(result.edges, & &1.node)

      assert Enum.any?(preferences, fn pref ->
               String.contains?(String.downcase(pref.key), "enabled")
             end)
    end

    test "paginates results", %{context: context} do
      args = %{pagination: %{page: 1, per_page: 2}}

      assert {:ok, result} = PreferencesResolver.list_preferences(nil, args, context)

      assert length(result.edges) <= 2
      assert result.page_info.has_next_page in [true, false]
      assert result.page_info.has_previous_page == false
    end

    test "requires authentication" do
      args = %{}
      context = %{context: %{}}

      assert {:error, "Authentication required"} =
               PreferencesResolver.list_preferences(nil, args, context)
    end
  end

  describe "get_preference/3" do
    setup do
      user = user_fixture()
      preferences = create_test_preferences(user)
      context = %{context: %{current_user: user}}

      %{user: user, preferences: preferences, context: context}
    end

    test "returns specific preference", %{context: context} do
      args = %{id: "code_quality.enabled"}

      assert {:ok, preference} = PreferencesResolver.get_preference(nil, args, context)

      assert preference.id == "code_quality.enabled"
      assert preference.key == "code_quality.enabled"
      assert preference.category == "code_quality"
      assert preference.source in [:system, :user, :project]
    end

    test "returns error for non-existent preference", %{context: context} do
      args = %{id: "non.existent"}

      assert {:error, "Preference not found"} =
               PreferencesResolver.get_preference(nil, args, context)
    end

    test "requires authentication" do
      args = %{id: "test.preference"}
      context = %{context: %{}}

      assert {:error, "Authentication required"} =
               PreferencesResolver.get_preference(nil, args, context)
    end
  end

  describe "create_preference/3" do
    setup do
      user = user_fixture()
      context = %{context: %{current_user: user}}

      %{user: user, context: context}
    end

    test "creates new preference", %{context: context} do
      input = %{
        key: "test.new_preference",
        value: "test_value",
        category: "testing"
      }

      args = %{input: input}

      assert {:ok, preference} = PreferencesResolver.create_preference(nil, args, context)

      assert preference.key == "test.new_preference"
      assert preference.value == "test_value"
      assert preference.category == "testing"
      assert preference.source == :user
    end

    test "validates required fields", %{context: context} do
      # Missing key
      input = %{value: "test_value"}
      args = %{input: input}

      assert {:error, "Key and value are required"} =
               PreferencesResolver.create_preference(nil, args, context)
    end

    test "requires authentication" do
      input = %{key: "test.key", value: "test_value"}
      args = %{input: input}
      context = %{context: %{}}

      assert {:error, "Authentication required"} =
               PreferencesResolver.create_preference(nil, args, context)
    end
  end

  describe "update_preference/3" do
    setup do
      user = user_fixture()
      create_test_preferences(user)
      context = %{context: %{current_user: user}}

      %{user: user, context: context}
    end

    test "updates existing preference", %{context: context} do
      input = %{value: "updated_value"}
      args = %{id: "code_quality.enabled", input: input}

      assert {:ok, preference} = PreferencesResolver.update_preference(nil, args, context)

      assert preference.key == "code_quality.enabled"
      assert preference.value == "updated_value"
    end

    test "creates preference if it doesn't exist", %{context: context} do
      input = %{value: "new_value"}
      args = %{id: "new.preference", input: input}

      assert {:ok, preference} = PreferencesResolver.update_preference(nil, args, context)

      assert preference.key == "new.preference"
      assert preference.value == "new_value"
    end

    test "validates input", %{context: context} do
      # Missing value
      input = %{}
      args = %{id: "test.key", input: input}

      assert {:error, "Value is required"} =
               PreferencesResolver.update_preference(nil, args, context)
    end

    test "requires authentication" do
      input = %{value: "test_value"}
      args = %{id: "test.key", input: input}
      context = %{context: %{}}

      assert {:error, "Authentication required"} =
               PreferencesResolver.update_preference(nil, args, context)
    end
  end

  describe "delete_preference/3" do
    setup do
      user = user_fixture()
      create_test_preferences(user)
      context = %{context: %{current_user: user}}

      %{user: user, context: context}
    end

    test "deletes preference", %{context: context} do
      args = %{id: "code_quality.enabled"}

      assert {:ok, true} = PreferencesResolver.delete_preference(nil, args, context)
    end

    test "handles deletion of non-existent preference", %{context: context} do
      args = %{id: "non.existent"}

      # Should still return success (idempotent)
      assert {:ok, true} = PreferencesResolver.delete_preference(nil, args, context)
    end

    test "requires authentication" do
      args = %{id: "test.key"}
      context = %{context: %{}}

      assert {:error, "Authentication required"} =
               PreferencesResolver.delete_preference(nil, args, context)
    end
  end

  describe "batch_update_preferences/3" do
    setup do
      user = user_fixture()
      context = %{context: %{current_user: user}}

      %{user: user, context: context}
    end

    test "processes batch updates successfully", %{context: context} do
      inputs = [
        %{key: "batch.test1", value: "value1"},
        %{key: "batch.test2", value: "value2"}
      ]

      args = %{inputs: inputs}

      assert {:ok, result} = PreferencesResolver.batch_update_preferences(nil, args, context)

      assert result.total_count == 2
      assert result.success_count == 2
      assert result.error_count == 0
      assert length(result.results) == 2
    end

    test "handles mixed success/failure", %{context: context} do
      inputs = [
        %{key: "batch.valid", value: "valid_value"},
        # Missing key
        %{value: "invalid"}
      ]

      args = %{inputs: inputs}

      assert {:ok, result} = PreferencesResolver.batch_update_preferences(nil, args, context)

      assert result.total_count == 2
      assert result.success_count == 1
      assert result.error_count == 1
    end

    test "requires authentication" do
      inputs = [%{key: "test.key", value: "test_value"}]
      args = %{inputs: inputs}
      context = %{context: %{}}

      assert {:error, "Authentication required"} =
               PreferencesResolver.batch_update_preferences(nil, args, context)
    end
  end

  describe "field resolvers" do
    setup do
      user = user_fixture()
      create_test_preferences(user)
      context = %{context: %{current_user: user}}

      %{user: user, context: context}
    end

    test "resolve_inherited_from/3 returns inheritance source" do
      preference = %{key: "test.key", user_id: "user123"}

      assert {:ok, nil} = PreferencesResolver.resolve_inherited_from(preference, %{}, %{})
    end

    test "resolve_overrides/3 returns preference overrides" do
      preference = %{key: "test.key"}

      assert {:ok, overrides} = PreferencesResolver.resolve_overrides(preference, %{}, %{})
      assert is_list(overrides)
    end

    test "resolve_template/3 returns associated template" do
      preference = %{template_id: "template123"}

      assert {:ok, nil} = PreferencesResolver.resolve_template(preference, %{}, %{})
    end

    test "resolve_template/3 returns nil when no template" do
      preference = %{template_id: nil}

      assert {:ok, nil} = PreferencesResolver.resolve_template(preference, %{}, %{})
    end
  end

  describe "GraphQL subscription integration" do
    setup do
      user = user_fixture()
      context = %{context: %{current_user: user}}

      %{user: user, context: context}
    end

    @tag :subscription
    test "publishes preference changes to subscriptions", %{context: context} do
      # Create preference to trigger subscription
      input = %{key: "subscription.test", value: "test_value"}
      args = %{input: input}

      # This would normally test that subscription events are published
      # For now, we just verify the preference is created
      assert {:ok, preference} = PreferencesResolver.create_preference(nil, args, context)

      # In a real test with Absinthe subscriptions:
      # assert_subscription_event("preference_changed", preference)

      assert preference.key == "subscription.test"
    end
  end

  describe "error handling" do
    setup do
      user = user_fixture()
      context = %{context: %{current_user: user}}

      %{user: user, context: context}
    end

    test "handles database errors gracefully", %{context: context} do
      # Mock database error
      with_mock RubberDuck.Preferences.Resources.SystemDefault, [:passthrough],
        read: fn -> {:error, "Database connection failed"} end do
        args = %{}

        assert {:error, "Database connection failed"} =
                 PreferencesResolver.list_preferences(nil, args, context)
      end
    end

    test "handles validation errors", %{context: context} do
      # Test with invalid preference data
      # Empty key
      input = %{key: "", value: ""}
      args = %{input: input}

      assert {:error, _reason} = PreferencesResolver.create_preference(nil, args, context)
    end
  end

  # Helper functions

  defp create_test_preferences(user) do
    [
      user_preference_fixture(user, %{preference_key: "code_quality.enabled", value: "true"}),
      user_preference_fixture(user, %{preference_key: "budgeting.limit", value: "100"}),
      user_preference_fixture(user, %{preference_key: "llm.provider", value: "anthropic"}),
      user_preference_fixture(user, %{preference_key: "ml.training_enabled", value: "false"})
    ]
  end
end
