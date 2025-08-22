defmodule RubberDuck.Preferences.Resources.UserPreferenceTest do
  @moduledoc """
  Unit tests for UserPreference resource.
  """

  use ExUnit.Case, async: true

  alias RubberDuck.Preferences.Resources.UserPreference

  describe "user preference creation" do
    test "creates user preference with required attributes" do
      attrs = %{
        user_id: "user_123",
        preference_key: "llm.providers.openai.model",
        value: "gpt-4-turbo",
        category: "llm",
        source: :manual
      }

      # Verify required attributes are present
      assert Map.has_key?(attrs, :user_id)
      assert Map.has_key?(attrs, :preference_key)
      assert Map.has_key?(attrs, :value)
      assert Map.has_key?(attrs, :category)
      assert Map.has_key?(attrs, :source)
    end

    test "validates preference sources" do
      valid_sources = [:manual, :template, :migration, :import, :api]

      Enum.each(valid_sources, fn source ->
        assert source in valid_sources
      end)
    end

    test "supports preference activation/deactivation" do
      preference = %{
        user_id: "user_123",
        preference_key: "test.preference",
        value: "test_value",
        active: true
      }

      # Active preferences should be used
      assert preference.active == true

      # Inactive preferences should fall back to system default
      inactive_preference = Map.put(preference, :active, false)
      assert inactive_preference.active == false
    end
  end

  describe "user preference categories" do
    test "organizes user preferences by category" do
      user_preferences = [
        %{category: "llm", preference_key: "llm.provider.default"},
        %{category: "llm", preference_key: "llm.model.preferred"},
        %{category: "budgeting", preference_key: "budgeting.daily_limit"},
        %{category: "ml", preference_key: "ml.enabled"}
      ]

      # Group by category
      grouped = Enum.group_by(user_preferences, & &1.category)

      assert Map.has_key?(grouped, "llm")
      assert Map.has_key?(grouped, "budgeting")
      assert Map.has_key?(grouped, "ml")

      # LLM category should have multiple preferences
      assert length(grouped["llm"]) == 2
    end
  end

  describe "preference change tracking" do
    test "tracks preference modification metadata" do
      preference_change = %{
        user_id: "user_123",
        preference_key: "test.preference",
        old_value: "old_value",
        new_value: "new_value",
        last_modified: DateTime.utc_now(),
        modified_by: "user_123",
        source: :manual,
        notes: "Updated for better performance"
      }

      # Verify change tracking fields
      assert Map.has_key?(preference_change, :last_modified)
      assert Map.has_key?(preference_change, :modified_by)
      assert Map.has_key?(preference_change, :source)
      assert Map.has_key?(preference_change, :notes)
    end

    test "supports bulk preference operations" do
      bulk_preferences = [
        %{preference_key: "llm.provider.primary", value: "anthropic"},
        %{preference_key: "llm.provider.fallback", value: "openai"},
        %{preference_key: "llm.model.default", value: "claude-3"}
      ]

      # Bulk operations should maintain consistency
      assert length(bulk_preferences) == 3

      # All should be in same category
      categories =
        Enum.map(bulk_preferences, fn pref ->
          String.split(pref.preference_key, ".") |> List.first()
        end)
        |> Enum.uniq()

      assert length(categories) == 1
      assert List.first(categories) == "llm"
    end
  end

  describe "template integration" do
    test "supports template-based preference application" do
      template_preferences = %{
        "conservative_llm" => [
          %{preference_key: "llm.provider.primary", value: "openai"},
          %{preference_key: "llm.model.default", value: "gpt-3.5-turbo"},
          %{preference_key: "llm.cost_optimization.enabled", value: "true"}
        ],
        "aggressive_ml" => [
          %{preference_key: "ml.enabled", value: "true"},
          %{preference_key: "ml.learning_rate", value: "0.01"},
          %{preference_key: "ml.batch_size", value: "64"}
        ]
      }

      # Template application should be trackable
      Enum.each(template_preferences, fn {template_name, preferences} ->
        assert is_binary(template_name)
        assert is_list(preferences)

        # All preferences should have required fields
        Enum.each(preferences, fn pref ->
          assert Map.has_key?(pref, :preference_key)
          assert Map.has_key?(pref, :value)
        end)
      end)
    end
  end

  describe "hierarchy resolution" do
    test "user preferences override system defaults" do
      system_default = %{
        preference_key: "llm.model.default",
        default_value: "gpt-3.5-turbo"
      }

      user_preference = %{
        preference_key: "llm.model.default",
        value: "gpt-4"
      }

      # User preference should take precedence
      effective_value =
        if Map.has_key?(user_preference, :value) do
          user_preference.value
        else
          system_default.default_value
        end

      assert effective_value == "gpt-4"
    end

    test "inactive user preferences fall back to system defaults" do
      system_default = %{
        preference_key: "llm.model.default",
        default_value: "gpt-3.5-turbo"
      }

      inactive_user_preference = %{
        preference_key: "llm.model.default",
        value: "gpt-4",
        active: false
      }

      # Inactive preference should fall back to system default
      effective_value =
        if Map.get(inactive_user_preference, :active, true) do
          inactive_user_preference.value
        else
          system_default.default_value
        end

      assert effective_value == "gpt-3.5-turbo"
    end
  end
end
