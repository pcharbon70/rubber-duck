defmodule RubberDuck.Preferences.Llm.RoutingIntegrationTest do
  use RubberDuck.DataCase, async: true

  alias RubberDuck.Accounts.User
  alias RubberDuck.Preferences
  alias RubberDuck.Preferences.Llm.RoutingIntegration
  alias RubberDuck.Preferences.Resources.{SystemDefault, UserPreference}
  alias RubberDuck.Preferences.Seeders.LlmDefaultsSeeder

  describe "provider selection with preferences" do
    setup do
      user = create_test_user()

      # Seed LLM defaults
      :ok = LlmDefaultsSeeder.seed_all()

      %{user: user}
    end

    test "selects provider based on preferences", %{user: user} do
      assert {:ok, selection} = RoutingIntegration.select_provider_with_preferences(user.id, [])

      assert is_atom(selection.provider)
      assert is_binary(selection.model)
      assert is_map(selection.config)
    end

    test "uses cost optimization when enabled", %{user: user} do
      # Enable cost optimization
      {:ok, _} =
        UserPreference.set_preference(
          user.id,
          "llm.cost.optimization_enabled",
          Jason.encode!(true),
          "Enable cost optimization"
        )

      assert {:ok, selection} = RoutingIntegration.select_provider_with_preferences(user.id, [])

      # Cost-optimized selection should include cost metrics
      assert Map.has_key?(selection, :estimated_cost)
    end

    test "uses quality-first when quality priority set", %{user: user} do
      assert {:ok, selection} =
               RoutingIntegration.select_provider_with_preferences(user.id,
                 quality_priority: true
               )

      # Should select high-quality provider
      # High-quality providers
      assert selection.provider in [:anthropic, :openai]
    end
  end

  describe "request routing" do
    setup do
      user = create_test_user()
      :ok = LlmDefaultsSeeder.seed_all()
      %{user: user}
    end

    test "routes request with load balancing", %{user: user} do
      request = %{
        type: :completion,
        content: "Test request",
        estimated_tokens: 1000
      }

      assert {:ok, routing} = RoutingIntegration.route_request(user.id, request)

      assert is_atom(routing.provider)
      assert is_binary(routing.model)
      assert is_map(routing.config)
      assert is_map(routing.routing_info)
      assert is_list(routing.fallback_chain)
    end

    test "includes routing strategy in response", %{user: user} do
      request = %{type: :completion, content: "Test"}

      assert {:ok, routing} = RoutingIntegration.route_request(user.id, request)

      routing_info = routing.routing_info
      assert Map.has_key?(routing_info, :strategy)
      assert Map.has_key?(routing_info, :assigned_at)
      assert Map.has_key?(routing_info, :routing_id)
    end
  end

  describe "provider migration" do
    setup do
      user = create_test_user()
      :ok = LlmDefaultsSeeder.seed_all()
      %{user: user}
    end

    test "migrates between providers with context preservation", %{user: user} do
      context = %{
        conversation_id: "conv_123",
        messages: ["Hello", "Hi there"],
        user_preferences: %{}
      }

      assert {:ok, migration} =
               RoutingIntegration.migrate_provider(
                 user.id,
                 :openai,
                 :anthropic,
                 context
               )

      migration_info = migration.migration_info
      assert migration_info.from_provider == :openai
      assert migration_info.to_provider == :anthropic
      assert migration_info.context_preserved == true
      assert %DateTime{} = migration_info.migrated_at

      # New context should preserve original data
      new_context = migration.new_context
      assert new_context.conversation_id == "conv_123"
      assert new_context.messages == ["Hello", "Hi there"]
    end

    test "validates target provider availability", %{user: user} do
      # Disable anthropic provider
      {:ok, _} =
        UserPreference.set_preference(
          user.id,
          "llm.providers.enabled",
          # Only OpenAI enabled
          Jason.encode!(["openai"]),
          "Limit providers"
        )

      assert {:error, _} =
               RoutingIntegration.migrate_provider(
                 user.id,
                 :openai,
                 # Disabled provider
                 :anthropic,
                 %{}
               )
    end
  end

  describe "provider monitoring integration" do
    setup do
      user = create_test_user()
      :ok = LlmDefaultsSeeder.seed_all()
      %{user: user}
    end

    test "monitors provider effectiveness", %{user: user} do
      performance_data = %{
        error_rate: 0.05,
        avg_response_time: 2000,
        availability: 0.98,
        total_requests: 100
      }

      assert :ok =
               RoutingIntegration.monitor_provider_effectiveness(
                 user.id,
                 :anthropic,
                 performance_data
               )
    end

    test "respects monitoring preferences", %{user: user} do
      # Disable performance tracking
      {:ok, _} =
        UserPreference.set_preference(
          user.id,
          "llm.monitoring.performance_tracking",
          Jason.encode!(false),
          "Disable tracking"
        )

      performance_data = %{error_rate: 0.1}

      # Should not crash when monitoring disabled
      assert :ok =
               RoutingIntegration.monitor_provider_effectiveness(
                 user.id,
                 :anthropic,
                 performance_data
               )
    end
  end

  describe "A/B testing" do
    setup do
      user = create_test_user()
      :ok = LlmDefaultsSeeder.seed_all()
      %{user: user}
    end

    test "enables A/B testing with valid configuration", %{user: user} do
      test_config = %{
        test_id: "provider_test_1",
        groups: [
          %{name: "group_a", provider: :anthropic},
          %{name: "group_b", provider: :openai}
        ],
        duration_hours: 24
      }

      assert {:ok, result} = RoutingIntegration.enable_ab_testing(user.id, test_config)

      assert Map.has_key?(result, :test_group)
      assert Map.has_key?(result, :provider_override)
      assert result.test_duration == 24
      assert result.test_id == "provider_test_1"
      assert %DateTime{} = result.started_at
    end

    test "rejects A/B test with insufficient groups", %{user: user} do
      test_config = %{
        # Only one group
        groups: [%{name: "single_group", provider: :anthropic}]
      }

      assert {:error, _} = RoutingIntegration.enable_ab_testing(user.id, test_config)
    end

    test "assigns users consistently to test groups", %{user: user} do
      test_config = %{
        groups: [
          %{name: "group_a", provider: :anthropic},
          %{name: "group_b", provider: :openai}
        ]
      }

      # Same user should get same group across multiple calls
      {:ok, result1} = RoutingIntegration.enable_ab_testing(user.id, test_config)
      {:ok, result2} = RoutingIntegration.enable_ab_testing(user.id, test_config)

      assert result1.test_group == result2.test_group
    end
  end

  # Helper functions

  defp create_test_user do
    {:ok, user} =
      User.register_with_password(%{
        email: "test#{System.unique_integer()}@example.com",
        password: "password123"
      })

    user
  end

  defp generate_uuid, do: Ash.UUID.generate()
end
