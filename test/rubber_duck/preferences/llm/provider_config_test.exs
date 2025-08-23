defmodule RubberDuck.Preferences.Llm.ProviderConfigTest do
  use RubberDuck.DataCase, async: true

  alias RubberDuck.Preferences
  alias RubberDuck.Preferences.Llm.ProviderConfig
  alias RubberDuck.Preferences.Seeders.LlmDefaultsSeeder

  describe "provider configuration" do
    setup do
      user = create_test_user()
      project_id = generate_uuid()

      # Seed LLM defaults
      :ok = LlmDefaultsSeeder.seed_all()

      %{user: user, project_id: project_id}
    end

    test "gets enabled providers from preferences", %{user: user} do
      # Should get default enabled providers
      enabled = ProviderConfig.get_enabled_providers(user.id)
      assert :anthropic in enabled
      assert :openai in enabled
    end

    test "respects user preferences for enabled providers", %{user: user} do
      # Override user preference
      {:ok, _} =
        Preferences.UserPreference.set_preference(
          user.id,
          "llm.providers.enabled",
          Jason.encode!(["google", "anthropic"]),
          "Custom provider selection"
        )

      enabled = ProviderConfig.get_enabled_providers(user.id)
      assert enabled == [:google, :anthropic]
    end

    test "gets provider priority order", %{user: user} do
      priority = ProviderConfig.get_provider_priority(user.id)
      assert is_list(priority)
      assert :anthropic in priority
    end

    test "gets default provider", %{user: user} do
      default = ProviderConfig.get_default_provider(user.id)
      assert default == :anthropic
    end

    test "gets provider-specific configuration", %{user: user} do
      openai_config = ProviderConfig.get_provider_config(user.id, :openai)

      assert openai_config.model == "gpt-4"
      assert openai_config.temperature == 0.7
      assert openai_config.max_tokens == 4096
      assert is_integer(openai_config.timeout)
    end

    test "gets complete configuration", %{user: user} do
      config = ProviderConfig.get_complete_config(user.id)

      assert is_list(config.enabled_providers)
      assert is_list(config.provider_priority)
      assert is_atom(config.default_provider)
      assert is_boolean(config.fallback_enabled)
      assert is_map(config.provider_configs)
      assert is_map(config.cost_optimization)
      assert is_map(config.fallback_config)
      assert is_map(config.monitoring_config)
    end

    test "validates configuration consistency", %{user: user} do
      config = ProviderConfig.get_complete_config(user.id)

      assert {:ok, :valid} = ProviderConfig.validate_config(config)
    end

    test "project preferences override user preferences", %{user: user, project_id: project_id} do
      # Set user preference
      {:ok, _} =
        Preferences.UserPreference.set_preference(
          user.id,
          "llm.providers.default_provider",
          Jason.encode!("openai"),
          "User preference"
        )

      # Enable project overrides
      {:ok, _} =
        Preferences.ProjectPreferenceEnabled.enable_overrides(%{
          project_id: project_id,
          enabled_categories: ["llm"],
          enablement_reason: "Testing",
          enabled_by: user.id,
          max_overrides: nil
        })

      # Set project preference
      {:ok, _} =
        Preferences.ProjectPreference.create_override(%{
          project_id: project_id,
          preference_key: "llm.providers.default_provider",
          value: Jason.encode!("google"),
          override_reason: "Project requirement",
          approved_by: user.id,
          temporary: false,
          effective_until: nil
        })

      # Without project context, should get user preference
      assert ProviderConfig.get_default_provider(user.id, nil) == :openai

      # With project context, should get project preference
      assert ProviderConfig.get_default_provider(user.id, project_id) == :google
    end
  end

  describe "configuration validation" do
    test "validates provider consistency" do
      valid_config = %{
        enabled_providers: [:openai, :anthropic],
        provider_priority: [:anthropic, :openai],
        fallback_config: %{chain: ["anthropic", "openai"]}
      }

      assert {:ok, :valid} = ProviderConfig.validate_config(valid_config)
    end

    test "rejects invalid provider configurations" do
      invalid_config = %{
        enabled_providers: [:openai],
        # Contains disabled provider
        provider_priority: [:anthropic, :openai],
        fallback_config: %{chain: ["anthropic"]}
      }

      assert {:error, _} = ProviderConfig.validate_config(invalid_config)
    end

    test "validates fallback chain consistency" do
      config_with_invalid_fallback = %{
        enabled_providers: [:openai],
        provider_priority: [:openai],
        # Contains disabled providers
        fallback_config: %{chain: ["anthropic", "google"]}
      }

      assert {:error, _} = ProviderConfig.validate_config(config_with_invalid_fallback)
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
