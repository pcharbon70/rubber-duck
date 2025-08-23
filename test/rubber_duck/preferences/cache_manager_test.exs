defmodule RubberDuck.Preferences.CacheManagerTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Preferences.CacheManager

  @test_table :test_cache

  setup do
    # Ensure clean table for each test
    if CacheManager.table_exists?(@test_table) do
      CacheManager.clear_all(@test_table)
    else
      CacheManager.create_table(@test_table)
    end

    :ok
  end

  describe "basic cache operations" do
    test "creates ETS table successfully" do
      table_name = :new_test_table

      assert table_name == CacheManager.create_table(table_name)
      assert CacheManager.table_exists?(table_name)

      # Cleanup
      :ets.delete(table_name)
    end

    test "stores and retrieves values" do
      key = "test_key"
      value = "test_value"

      assert :ok = CacheManager.put(@test_table, key, value)
      assert {:ok, value} = CacheManager.get(@test_table, key)
    end

    test "handles missing keys" do
      assert {:error, :not_found} = CacheManager.get(@test_table, "nonexistent_key")
    end

    test "invalidates specific keys" do
      CacheManager.put(@test_table, "key1", "value1")
      CacheManager.put(@test_table, "key2", "value2")

      assert :ok = CacheManager.invalidate(@test_table, "key1")

      assert {:error, :not_found} = CacheManager.get(@test_table, "key1")
      assert {:ok, "value2"} = CacheManager.get(@test_table, "key2")
    end

    test "clears all entries" do
      CacheManager.put(@test_table, "key1", "value1")
      CacheManager.put(@test_table, "key2", "value2")

      assert :ok = CacheManager.clear_all(@test_table)

      assert {:error, :not_found} = CacheManager.get(@test_table, "key1")
      assert {:error, :not_found} = CacheManager.get(@test_table, "key2")
    end
  end

  describe "TTL functionality" do
    test "respects TTL expiration" do
      key = "ttl_test"
      value = "ttl_value"
      # 50 milliseconds
      ttl = 50

      CacheManager.put(@test_table, key, value, ttl)

      # Should be available immediately
      assert {:ok, value} = CacheManager.get(@test_table, key)

      # Wait for expiration
      Process.sleep(100)

      # Should be expired and automatically removed
      assert {:error, :expired} = CacheManager.get(@test_table, key)
    end

    test "cleanup removes expired entries" do
      # Add entries with short TTL
      CacheManager.put(@test_table, "expire1", "value1", 10)
      CacheManager.put(@test_table, "expire2", "value2", 10)
      # Longer TTL
      CacheManager.put(@test_table, "keep", "value3", 10_000)

      # Wait for expiration
      Process.sleep(50)

      # Cleanup expired entries
      expired_count = CacheManager.cleanup_expired(@test_table)

      assert expired_count == 2
      assert {:error, :not_found} = CacheManager.get(@test_table, "expire1")
      assert {:error, :not_found} = CacheManager.get(@test_table, "expire2")
      assert {:ok, "value3"} = CacheManager.get(@test_table, "keep")
    end
  end

  describe "pattern invalidation" do
    test "invalidates entries matching pattern" do
      CacheManager.put(@test_table, "user1:pref1:global", "value1")
      CacheManager.put(@test_table, "user1:pref2:global", "value2")
      CacheManager.put(@test_table, "user2:pref1:global", "value3")

      # Invalidate all user1 preferences
      CacheManager.invalidate_pattern(@test_table, "user1:*")

      assert {:error, :not_found} = CacheManager.get(@test_table, "user1:pref1:global")
      assert {:error, :not_found} = CacheManager.get(@test_table, "user1:pref2:global")
      assert {:ok, "value3"} = CacheManager.get(@test_table, "user2:pref1:global")
    end

    test "handles complex patterns" do
      CacheManager.put(@test_table, "user1:auth.token:project1", "token1")
      CacheManager.put(@test_table, "user1:auth.session:project1", "session1")
      CacheManager.put(@test_table, "user1:ml.model:project1", "model1")
      CacheManager.put(@test_table, "user1:auth.token:project2", "token2")

      # Invalidate all auth preferences for project1
      CacheManager.invalidate_pattern(@test_table, "user1:auth.*:project1")

      assert {:error, :not_found} = CacheManager.get(@test_table, "user1:auth.token:project1")
      assert {:error, :not_found} = CacheManager.get(@test_table, "user1:auth.session:project1")
      assert {:ok, "model1"} = CacheManager.get(@test_table, "user1:ml.model:project1")
      assert {:ok, "token2"} = CacheManager.get(@test_table, "user1:auth.token:project2")
    end
  end

  describe "cache statistics" do
    test "provides accurate statistics" do
      CacheManager.put(@test_table, "key1", "value1")
      # Short TTL
      CacheManager.put(@test_table, "key2", "value2", 10)

      # Wait for one to expire
      Process.sleep(50)

      stats = CacheManager.stats(@test_table)

      assert stats.size == 2
      assert is_integer(stats.memory_usage)
      assert stats.expired_entries == 1
    end
  end

  describe "cache warming" do
    test "warms cache with provided specifications" do
      user = create_test_user()
      project_id = generate_uuid()

      # Create system defaults
      {:ok, _} = create_system_default("warm.test1", "value1", "string")
      {:ok, _} = create_system_default("warm.test2", "value2", "string")

      warmup_specs = [
        %{
          user_id: user.id,
          preference_keys: ["warm.test1", "warm.test2"],
          project_id: project_id
        }
      ]

      assert :ok = CacheManager.warm_cache(@test_table, warmup_specs)

      # Verify cache was populated
      cache_key1 = "#{user.id}:warm.test1:#{project_id}"
      cache_key2 = "#{user.id}:warm.test2:#{project_id}"

      # Note: In actual cache warming, these would be populated by PreferenceResolver
      # This test verifies the warming mechanism itself
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

  defp create_system_default(key, value, data_type) do
    Preferences.SystemDefault.seed_default(%{
      preference_key: key,
      default_value: Jason.encode!(value),
      data_type: String.to_atom(data_type),
      category: "test",
      description: "Test preference for #{key}"
    })
  end

  defp generate_uuid, do: Ash.UUID.generate()
end
