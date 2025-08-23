defmodule RubberDuck.Preferences.PreferenceResolverTest do
  use RubberDuck.DataCase, async: true

  alias RubberDuck.Accounts.User
  alias RubberDuck.Preferences
  alias RubberDuck.Preferences.{CacheManager, PreferenceResolver}

  describe "preference resolution" do
    setup do
      # Create test user
      user = create_test_user()

      # Create system default
      {:ok, system_default} = create_system_default("test.preference", "default_value", "string")

      %{user: user, system_default: system_default}
    end

    test "resolves system default when no overrides exist", %{user: user} do
      assert {:ok, "default_value"} = PreferenceResolver.resolve(user.id, "test.preference")
    end

    test "resolves user preference when it exists", %{user: user} do
      # Create user preference
      {:ok, _user_pref} =
        Preferences.UserPreference.set_preference(
          user.id,
          "test.preference",
          Jason.encode!("user_value"),
          "Test override"
        )

      assert {:ok, "user_value"} = PreferenceResolver.resolve(user.id, "test.preference")
    end

    test "resolves project preference when project overrides enabled", %{user: user} do
      project_id = generate_uuid()

      # Enable project overrides
      {:ok, _enablement} =
        Preferences.ProjectPreferenceEnabled.enable_overrides(
          project_id,
          [],
          "Testing",
          user.id,
          nil
        )

      # Create project preference
      {:ok, _project_pref} =
        Preferences.ProjectPreference.create_override(
          project_id,
          "test.preference",
          Jason.encode!("project_value"),
          "Test project override",
          user.id,
          false,
          nil
        )

      assert {:ok, "project_value"} =
               PreferenceResolver.resolve(user.id, "test.preference", project_id)
    end

    test "follows correct hierarchy: project > user > system", %{user: user} do
      project_id = generate_uuid()

      # Create user preference
      {:ok, _user_pref} =
        Preferences.UserPreference.set_preference(
          user.id,
          "test.preference",
          Jason.encode!("user_value"),
          "User override"
        )

      # Enable project overrides
      {:ok, _enablement} =
        Preferences.ProjectPreferenceEnabled.enable_overrides(
          project_id,
          [],
          "Testing",
          user.id,
          nil
        )

      # Create project preference
      {:ok, _project_pref} =
        Preferences.ProjectPreference.create_override(
          project_id,
          "test.preference",
          Jason.encode!("project_value"),
          "Project override",
          user.id,
          false,
          nil
        )

      # Should resolve to project value (highest precedence)
      assert {:ok, "project_value"} =
               PreferenceResolver.resolve(user.id, "test.preference", project_id)

      # Without project context, should resolve to user value
      assert {:ok, "user_value"} = PreferenceResolver.resolve(user.id, "test.preference", nil)
    end

    test "handles missing preferences gracefully", %{user: user} do
      assert {:error, :not_found} = PreferenceResolver.resolve(user.id, "nonexistent.preference")
    end

    test "batch resolution works correctly", %{user: user} do
      # Create multiple system defaults
      {:ok, _} = create_system_default("test.pref1", "value1", "string")
      {:ok, _} = create_system_default("test.pref2", "value2", "string")
      {:ok, _} = create_system_default("test.pref3", "value3", "string")

      # Create user override for one preference
      {:ok, _} =
        Preferences.UserPreference.set_preference(
          user.id,
          "test.pref2",
          Jason.encode!("user_override"),
          "Override"
        )

      result =
        PreferenceResolver.resolve_batch(user.id, ["test.pref1", "test.pref2", "test.pref3"])

      assert result["test.pref1"] == "value1"
      assert result["test.pref2"] == "user_override"
      assert result["test.pref3"] == "value3"
    end

    test "resolve_all returns complete preference set", %{user: user} do
      # Create additional system defaults
      {:ok, _} = create_system_default("test.other", "other_value", "string")

      result = PreferenceResolver.resolve_all(user.id)

      assert result["test.preference"] == "default_value"
      assert result["test.other"] == "other_value"
    end
  end

  describe "caching behavior" do
    setup do
      user = create_test_user()
      {:ok, _} = create_system_default("cache.test", "cached_value", "string")

      %{user: user}
    end

    test "caches resolved preferences", %{user: user} do
      # First resolution should populate cache
      assert {:ok, "cached_value"} = PreferenceResolver.resolve(user.id, "cache.test")

      # Verify cache contains the value
      cache_key = "#{user.id}:cache.test:global"
      assert {:ok, "cached_value"} = CacheManager.get(:preference_cache, cache_key)
    end

    test "cache invalidation works", %{user: user} do
      # Resolve to populate cache
      assert {:ok, "cached_value"} = PreferenceResolver.resolve(user.id, "cache.test")

      # Invalidate cache
      PreferenceResolver.invalidate_cache(user.id, "cache.test")

      # Verify cache is empty
      cache_key = "#{user.id}:cache.test:global"
      assert {:error, :not_found} = CacheManager.get(:preference_cache, cache_key)
    end

    test "cache invalidation with pattern works", %{user: user} do
      # Resolve multiple preferences to populate cache
      {:ok, _} = create_system_default("cache.test2", "value2", "string")

      assert {:ok, "cached_value"} = PreferenceResolver.resolve(user.id, "cache.test")
      assert {:ok, "value2"} = PreferenceResolver.resolve(user.id, "cache.test2")

      # Invalidate all user caches
      PreferenceResolver.invalidate_cache(user.id, :all)

      # Verify both caches are empty
      cache_key1 = "#{user.id}:cache.test:global"
      cache_key2 = "#{user.id}:cache.test2:global"
      assert {:error, :not_found} = CacheManager.get(:preference_cache, cache_key1)
      assert {:error, :not_found} = CacheManager.get(:preference_cache, cache_key2)
    end
  end

  describe "source tracking" do
    setup do
      user = create_test_user()
      {:ok, system_default} = create_system_default("source.test", "system_value", "string")

      %{user: user, system_default: system_default}
    end

    test "tracks system default source", %{user: user} do
      {source, _details} = PreferenceResolver.get_preference_source(user.id, "source.test")
      assert source == :system_default
    end

    test "tracks user preference source", %{user: user} do
      {:ok, _} =
        Preferences.UserPreference.set_preference(
          user.id,
          "source.test",
          Jason.encode!("user_value"),
          "User override"
        )

      {source, _details} = PreferenceResolver.get_preference_source(user.id, "source.test")
      assert source == :user_preference
    end

    test "tracks project preference source", %{user: user} do
      project_id = generate_uuid()

      # Enable project overrides
      {:ok, _} =
        Preferences.ProjectPreferenceEnabled.enable_overrides(
          project_id,
          [],
          "Testing",
          user.id,
          nil
        )

      # Create project preference
      {:ok, _} =
        Preferences.ProjectPreference.create_override(
          project_id,
          "source.test",
          Jason.encode!("project_value"),
          "Project override",
          user.id,
          false,
          nil
        )

      {source, _details} =
        PreferenceResolver.get_preference_source(user.id, "source.test", project_id)

      assert source == :project_preference
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

  defp create_system_default(key, value, data_type) do
    Preferences.SystemDefault.seed_default(%{
      preference_key: key,
      default_value: Jason.encode!(value),
      data_type: String.to_atom(data_type),
      category: "test",
      description: "Test preference"
    })
  end

  defp generate_uuid, do: Ash.UUID.generate()
end
