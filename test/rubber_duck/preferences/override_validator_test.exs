defmodule RubberDuck.Preferences.OverrideValidatorTest do
  use RubberDuck.DataCase, async: true

  alias RubberDuck.Preferences
  alias RubberDuck.Preferences.OverrideValidator

  describe "override validation" do
    setup do
      user = create_test_user()
      project_id = generate_uuid()

      # Create system default with constraints
      {:ok, system_default} =
        Preferences.SystemDefault.seed_default(%{
          preference_key: "validate.test",
          default_value: Jason.encode!("default"),
          data_type: :string,
          category: "test",
          description: "Test preference with validation",
          constraints: %{"allowed_values" => ["option1", "option2", "option3"]}
        })

      # Enable project overrides
      {:ok, _} =
        Preferences.ProjectPreferenceEnabled.enable_overrides(
          project_id,
          ["test"],
          "Testing validation",
          user.id,
          # Max 5 overrides
          5
        )

      %{user: user, project_id: project_id, system_default: system_default}
    end

    test "validates existing preference keys", %{project_id: project_id} do
      assert {:ok, :valid} =
               OverrideValidator.validate_override(project_id, "validate.test", "option1")

      assert {:error, _} =
               OverrideValidator.validate_override(project_id, "nonexistent.key", "value")
    end

    test "validates value compatibility with data type", %{project_id: project_id} do
      # String preference should accept string values
      assert {:ok, :valid} =
               OverrideValidator.validate_override(project_id, "validate.test", "option1")

      # Create integer preference for type testing
      {:ok, _} = create_system_default("validate.int", 42, "integer")
      {:ok, _} = Preferences.ProjectPreferenceEnabled.update_categories(project_id, ["test"], [])

      assert {:ok, :valid} = OverrideValidator.validate_override(project_id, "validate.int", 100)

      assert {:error, _} =
               OverrideValidator.validate_override(project_id, "validate.int", "not_a_number")
    end

    test "validates against preference constraints", %{project_id: project_id} do
      # Valid constraint value
      assert {:ok, :valid} =
               OverrideValidator.validate_override(project_id, "validate.test", "option1")

      # Invalid constraint value
      assert {:error, _} =
               OverrideValidator.validate_override(project_id, "validate.test", "invalid_option")
    end

    test "validates permissions and access levels", %{user: user, project_id: project_id} do
      # Create admin-level preference
      {:ok, _} =
        Preferences.SystemDefault.seed_default(%{
          preference_key: "validate.admin",
          default_value: Jason.encode!("admin_default"),
          data_type: :string,
          category: "test",
          description: "Admin-only preference",
          access_level: :admin
        })

      # Should require approval for admin-level preferences
      assert {:ok, :valid} =
               OverrideValidator.validate_override(
                 project_id,
                 "validate.admin",
                 "new_value",
                 approved_by: user.id
               )

      assert {:error, _} =
               OverrideValidator.validate_override(
                 project_id,
                 "validate.admin",
                 "new_value",
                 # No approval
                 []
               )
    end

    test "validates project override limits", %{user: user, project_id: project_id} do
      # Create 5 overrides to reach the limit
      Enum.each(1..5, fn i ->
        {:ok, _} = create_system_default("limit.test#{i}", "default#{i}", "string")

        {:ok, _} =
          Preferences.ProjectPreference.create_override(
            project_id,
            "limit.test#{i}",
            Jason.encode!("value#{i}"),
            "Limit test",
            user.id,
            false,
            nil
          )
      end)

      # 6th override should fail due to limit
      {:ok, _} = create_system_default("limit.test6", "default6", "string")

      assert {:error, _} =
               OverrideValidator.validate_override(project_id, "limit.test6", "value6")
    end
  end

  describe "constraint validation" do
    test "validates numeric ranges" do
      # Create preference with range constraints
      {:ok, _} =
        Preferences.SystemDefault.seed_default(%{
          preference_key: "range.test",
          default_value: Jason.encode!(50),
          data_type: :integer,
          category: "test",
          description: "Range test preference",
          constraints: %{"min" => 1, "max" => 100}
        })

      project_id = setup_test_project()

      # Valid range
      assert {:ok, :within_constraints} = OverrideValidator.validate_constraints("range.test", 75)

      # Below minimum
      assert {:error, _} = OverrideValidator.validate_constraints("range.test", 0)

      # Above maximum  
      assert {:error, _} = OverrideValidator.validate_constraints("range.test", 150)
    end

    test "validates enumeration constraints" do
      # Valid enumeration value
      assert {:ok, :within_constraints} =
               OverrideValidator.validate_constraints("validate.test", "option1")

      # Invalid enumeration value
      assert {:error, _} = OverrideValidator.validate_constraints("validate.test", "invalid")
    end

    test "validates regex patterns" do
      # Create preference with regex constraint
      {:ok, _} =
        Preferences.SystemDefault.seed_default(%{
          preference_key: "regex.test",
          default_value: Jason.encode!("test123"),
          data_type: :string,
          category: "test",
          description: "Regex test preference",
          constraints: %{"pattern" => "^[a-z]+[0-9]+$"}
        })

      # Valid pattern
      assert {:ok, :within_constraints} =
               OverrideValidator.validate_constraints("regex.test", "abc123")

      # Invalid pattern
      assert {:error, _} = OverrideValidator.validate_constraints("regex.test", "invalid-format")
    end
  end

  describe "preference existence validation" do
    test "validates existing preferences" do
      {:ok, _} = create_system_default("exists.test", "value", "string")

      assert {:ok, :exists} = OverrideValidator.validate_preference_exists("exists.test")
      assert {:error, _} = OverrideValidator.validate_preference_exists("nonexistent.preference")
    end

    test "rejects deprecated preferences" do
      # Create and deprecate a preference
      {:ok, default} = create_system_default("deprecated.test", "value", "string")
      {:ok, _} = Preferences.SystemDefault.deprecate(default, "replacement.key")

      assert {:error, _} = OverrideValidator.validate_preference_exists("deprecated.test")
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

  defp setup_test_project do
    user = create_test_user()
    project_id = generate_uuid()

    {:ok, _} =
      Preferences.ProjectPreferenceEnabled.enable_overrides(
        project_id,
        ["test"],
        "Testing",
        user.id,
        nil
      )

    project_id
  end

  defp generate_uuid, do: Ash.UUID.generate()
end
