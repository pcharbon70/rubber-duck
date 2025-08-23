defmodule RubberDuck.Preferences.Llm.FallbackManagerTest do
  use RubberDuck.DataCase, async: true

  alias RubberDuck.Preferences.Llm.FallbackManager
  alias RubberDuck.Preferences.Seeders.LlmDefaultsSeeder

  describe "fallback chain management" do
    setup do
      user = create_test_user()

      # Seed LLM defaults
      :ok = LlmDefaultsSeeder.seed_all()

      %{user: user}
    end

    test "gets fallback chain from preferences", %{user: user} do
      chain = FallbackManager.get_fallback_chain(user.id)

      assert is_list(chain)
      # Should have at least 2 providers for fallback
      assert length(chain) >= 2
      assert Enum.all?(chain, &is_atom/1)
    end

    test "filters fallback chain by enabled providers", %{user: user} do
      # Disable some providers
      {:ok, _} =
        RubberDuck.Preferences.UserPreference.set_preference(
          user.id,
          "llm.providers.enabled",
          # Only Anthropic enabled
          Jason.encode!(["anthropic"]),
          "Limit providers"
        )

      chain = FallbackManager.get_fallback_chain(user.id)

      # Should only contain enabled providers
      assert chain == [:anthropic]
    end

    test "determines fallback trigger conditions", %{user: user} do
      # Test different error types
      assert FallbackManager.should_trigger_fallback?(
               user.id,
               {:timeout, "Request timeout"},
               :openai
             ) == true

      assert FallbackManager.should_trigger_fallback?(
               user.id,
               {:rate_limit, "Rate limited"},
               :openai
             ) == true

      assert FallbackManager.should_trigger_fallback?(
               user.id,
               {:server_error, "Internal error"},
               :openai
             ) == true

      # Non-triggering errors
      assert FallbackManager.should_trigger_fallback?(
               user.id,
               {:auth_error, "Invalid API key"},
               :openai
             ) == false
    end

    test "gets next provider in fallback chain", %{user: user} do
      # Should get next provider after current
      assert {:ok, next} = FallbackManager.get_next_provider(user.id, :anthropic, [])
      assert next in [:openai, :google]

      # Should skip failed providers
      assert {:ok, next} = FallbackManager.get_next_provider(user.id, :anthropic, [:openai])
      assert next != :openai
    end

    test "returns error when no fallback available", %{user: user} do
      # All providers failed
      all_providers = [:anthropic, :openai, :google]

      assert {:error, :no_fallback_available} =
               FallbackManager.get_next_provider(user.id, :anthropic, all_providers)
    end

    test "executes fallback with retry logic", %{user: user} do
      success_fn = fn provider ->
        if provider == :anthropic do
          {:error, {:timeout, "Anthropic timeout"}}
        else
          {:ok, "Success from #{provider}"}
        end
      end

      assert {:ok, result} =
               FallbackManager.execute_fallback(
                 user.id,
                 success_fn,
                 :anthropic,
                 {:timeout, "Original timeout"}
               )

      assert result =~ "Success from"
    end

    test "returns original error when fallback disabled", %{user: user} do
      # Disable fallback
      {:ok, _} =
        RubberDuck.Preferences.UserPreference.set_preference(
          user.id,
          "llm.providers.fallback_enabled",
          Jason.encode!(false),
          "Disable fallback"
        )

      error_fn = fn _provider -> {:error, "Always fails"} end
      original_error = {:timeout, "Original error"}

      assert {:error, ^original_error} =
               FallbackManager.execute_fallback(
                 user.id,
                 error_fn,
                 :anthropic,
                 original_error
               )
    end
  end

  describe "provider health monitoring" do
    test "checks provider health status", %{user: user} do
      health = FallbackManager.check_provider_health(user.id, :anthropic)
      assert health in [:healthy, :degraded, :failed]
    end

    test "returns healthy for local provider", %{user: user} do
      health = FallbackManager.check_provider_health(user.id, :local)
      # Local should generally be healthy
      assert health in [:healthy, :degraded]
    end

    test "health check respects monitoring preferences", %{user: user} do
      # Disable health monitoring
      {:ok, _} =
        RubberDuck.Preferences.UserPreference.set_preference(
          user.id,
          "llm.monitoring.health_check_enabled",
          Jason.encode!(false),
          "Disable monitoring"
        )

      health = FallbackManager.check_provider_health(user.id, :anthropic)
      # Should assume healthy when disabled
      assert health == :healthy
    end
  end

  describe "fallback statistics" do
    test "generates fallback statistics", %{user: user} do
      stats = FallbackManager.get_fallback_statistics(user.id)

      assert stats.user_id == user.id
      assert is_boolean(stats.fallback_enabled)
      assert is_integer(stats.total_fallback_events)
      assert is_list(stats.most_common_failures)
      assert is_float(stats.fallback_success_rate)
      assert is_float(stats.average_fallback_time)
      assert %DateTime{} = stats.generated_at
    end

    test "includes project context in statistics", %{user: user} do
      project_id = generate_uuid()
      stats = FallbackManager.get_fallback_statistics(user.id, project_id)

      assert stats.project_id == project_id
    end
  end

  # Helper functions

  defp create_test_user do
    {:ok, user} =
      RubberDuck.Accounts.User.register_with_password(%{
        email: "test#{System.unique_integer()}@example.com",
        password: "password123"
      })

    user
  end

  defp generate_uuid, do: Ash.UUID.generate()
end
