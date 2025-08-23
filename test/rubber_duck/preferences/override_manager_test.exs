defmodule RubberDuck.Preferences.OverrideManagerTest do
  use RubberDuck.DataCase, async: true

  alias RubberDuck.Preferences
  alias RubberDuck.Preferences.OverrideManager

  describe "project override management" do
    setup do
      user = create_test_user()
      project_id = generate_uuid()

      # Create system default for testing
      {:ok, _} = create_system_default("override.test", "default_value", "string")

      %{user: user, project_id: project_id}
    end

    test "enables project overrides successfully", %{user: user, project_id: project_id} do
      assert {:ok, result} =
               OverrideManager.enable_project_overrides(project_id,
                 enabled_by: user.id,
                 reason: "Enable for testing",
                 categories: ["test"],
                 max_overrides: 10
               )

      assert result.project_id == project_id
      assert result.enabled == true
      assert result.enabled_categories == ["test"]
      assert result.max_overrides == 10
    end

    test "requires enabled_by parameter", %{project_id: project_id} do
      assert {:error, "enabled_by user ID is required"} =
               OverrideManager.enable_project_overrides(project_id,
                 reason: "Testing without user"
               )
    end

    test "disables project overrides", %{user: user, project_id: project_id} do
      # Enable first
      {:ok, _} =
        OverrideManager.enable_project_overrides(project_id,
          enabled_by: user.id,
          reason: "Enable for testing"
        )

      # Then disable
      assert {:ok, result} =
               OverrideManager.disable_project_overrides(project_id, "Testing disable")

      assert result.project_id == project_id
      assert result.enabled == false
      assert result.disable_reason == "Testing disable"
    end

    test "creates override with validation", %{user: user, project_id: project_id} do
      # Enable overrides first
      {:ok, _} =
        OverrideManager.enable_project_overrides(project_id,
          enabled_by: user.id,
          reason: "Enable for testing"
        )

      # Create override
      assert {:ok, result} =
               OverrideManager.create_override(
                 project_id,
                 "override.test",
                 "new_value",
                 reason: "Test override",
                 approved_by: user.id
               )

      assert result.project_id == project_id
      assert result.preference_key == "override.test"
      assert result.value == "new_value"
      assert result.approved_by == user.id
    end

    test "prevents override creation when not enabled", %{project_id: project_id} do
      assert {:error, "Project overrides are disabled"} =
               OverrideManager.create_override(
                 project_id,
                 "override.test",
                 "new_value",
                 reason: "Should fail"
               )
    end

    test "removes override successfully", %{user: user, project_id: project_id} do
      # Enable and create override
      {:ok, _} =
        OverrideManager.enable_project_overrides(project_id,
          enabled_by: user.id,
          reason: "Testing"
        )

      {:ok, _} =
        OverrideManager.create_override(project_id, "override.test", "test_value",
          approved_by: user.id
        )

      # Remove override
      assert {:ok, result} = OverrideManager.remove_override(project_id, "override.test")

      assert result.project_id == project_id
      assert result.preference_key == "override.test"
    end

    test "generates override statistics", %{user: user, project_id: project_id} do
      # Enable overrides and create some test data
      {:ok, _} =
        OverrideManager.enable_project_overrides(project_id,
          enabled_by: user.id,
          reason: "Testing"
        )

      {:ok, _} = create_system_default("override.test2", "default2", "string")

      {:ok, _} =
        OverrideManager.create_override(project_id, "override.test", "value1",
          approved_by: user.id
        )

      {:ok, _} =
        OverrideManager.create_override(project_id, "override.test2", "value2",
          approved_by: user.id,
          temporary: true,
          effective_until: DateTime.add(DateTime.utc_now(), 1, :day)
        )

      stats = OverrideManager.get_override_statistics(project_id)

      assert stats.project_id == project_id
      assert stats.total_overrides == 2
      assert stats.active_overrides == 2
      assert stats.temporary_overrides == 1
      assert stats.overrides_by_category["test"] == 2
    end
  end

  describe "override analytics" do
    test "analyzes override patterns across projects" do
      user = create_test_user()
      project1 = generate_uuid()
      project2 = generate_uuid()

      # Create system defaults
      {:ok, _} = create_system_default("pattern.test1", "default1", "string")
      {:ok, _} = create_system_default("pattern.test2", "default2", "string")

      # Enable overrides for both projects
      Enum.each([project1, project2], fn project_id ->
        {:ok, _} =
          OverrideManager.enable_project_overrides(project_id,
            enabled_by: user.id,
            reason: "Testing"
          )
      end)

      # Create overrides with same preference key to test pattern detection
      {:ok, _} =
        OverrideManager.create_override(project1, "pattern.test1", "override1",
          approved_by: user.id
        )

      {:ok, _} =
        OverrideManager.create_override(project2, "pattern.test1", "override1",
          approved_by: user.id
        )

      patterns = OverrideManager.analyze_override_patterns()

      assert patterns.total_overrides == 2
      assert is_list(patterns.most_overridden_preferences)
      assert is_map(patterns.overrides_by_category)
      assert is_number(patterns.temporary_override_percentage)
      assert is_number(patterns.average_overrides_per_project)
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
