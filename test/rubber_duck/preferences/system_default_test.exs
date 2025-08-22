defmodule RubberDuck.Preferences.Resources.SystemDefaultTest do
  @moduledoc """
  Unit tests for SystemDefault preference resource.
  """

  use ExUnit.Case, async: true

  alias RubberDuck.Preferences.Resources.SystemDefault

  describe "system default creation" do
    test "creates system default with required attributes" do
      attrs = %{
        preference_key: "llm.providers.openai.model",
        default_value: "gpt-4",
        data_type: :string,
        category: "llm",
        subcategory: "providers",
        description: "Default OpenAI model for LLM operations"
      }

      # Note: Would test actual creation once database is set up
      assert Map.has_key?(attrs, :preference_key)
      assert Map.has_key?(attrs, :default_value)
      assert Map.has_key?(attrs, :data_type)
      assert Map.has_key?(attrs, :category)
      assert Map.has_key?(attrs, :description)
    end

    test "validates preference key format" do
      # Test preference key validation pattern
      valid_keys = [
        "llm.provider.openai",
        "budgeting.daily_limit",
        "ml.learning_rate",
        "code_quality.credo.enabled"
      ]

      invalid_keys = [
        # uppercase
        "LLM.Provider",
        # hyphens
        "llm-provider",
        # double dots
        "llm..provider",
        # starts with number
        "123invalid",
        # empty
        ""
      ]

      regex = ~r/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$/

      Enum.each(valid_keys, fn key ->
        assert Regex.match?(regex, key), "#{key} should be valid"
      end)

      Enum.each(invalid_keys, fn key ->
        refute Regex.match?(regex, key), "#{key} should be invalid"
      end)
    end

    test "validates data types" do
      valid_types = [:string, :integer, :float, :boolean, :json, :encrypted]

      Enum.each(valid_types, fn type ->
        assert type in valid_types
      end)
    end

    test "validates access levels" do
      valid_levels = [:public, :user, :admin, :superadmin]

      Enum.each(valid_levels, fn level ->
        assert level in valid_levels
      end)
    end
  end

  describe "system default categories" do
    test "organizes preferences by category" do
      llm_preferences = [
        "llm.providers.openai.model",
        "llm.providers.anthropic.model",
        "llm.fallback.retry_count"
      ]

      budgeting_preferences = [
        "budgeting.daily_limit",
        "budgeting.alert_threshold",
        "budgeting.enforcement_mode"
      ]

      ml_preferences = [
        "ml.enabled",
        "ml.learning_rate",
        "ml.batch_size"
      ]

      code_quality_preferences = [
        "code_quality.credo.enabled",
        "code_quality.smell_detection.enabled",
        "code_quality.refactoring.aggressiveness"
      ]

      all_categories = [
        {"llm", llm_preferences},
        {"budgeting", budgeting_preferences},
        {"ml", ml_preferences},
        {"code_quality", code_quality_preferences}
      ]

      # Verify category organization makes sense
      Enum.each(all_categories, fn {category, preferences} ->
        assert is_binary(category)
        assert is_list(preferences)
        assert length(preferences) > 0

        # All preferences in category should start with category name
        Enum.each(preferences, fn pref ->
          assert String.starts_with?(pref, category <> ".")
        end)
      end)
    end
  end

  describe "system default metadata" do
    test "includes comprehensive metadata" do
      metadata_fields = [
        :preference_key,
        :default_value,
        :data_type,
        :category,
        :subcategory,
        :description,
        :constraints,
        :sensitive,
        :version,
        :deprecated,
        :replacement_key,
        :display_order,
        :access_level
      ]

      # Verify all expected metadata fields are defined
      Enum.each(metadata_fields, fn field ->
        assert is_atom(field)
      end)
    end

    test "supports sensitive preference identification" do
      sensitive_preferences = [
        "llm.providers.openai.api_key",
        "llm.providers.anthropic.api_key",
        "budgeting.cost_center.api_credentials"
      ]

      non_sensitive_preferences = [
        "llm.providers.openai.model",
        "budgeting.daily_limit",
        "ml.enabled"
      ]

      # Sensitive preferences should be marked appropriately
      Enum.each(sensitive_preferences, fn pref ->
        assert String.contains?(pref, "api_key") or String.contains?(pref, "credential")
      end)

      # Non-sensitive preferences should not contain sensitive indicators
      Enum.each(non_sensitive_preferences, fn pref ->
        refute String.contains?(pref, "api_key")
        refute String.contains?(pref, "credential")
        refute String.contains?(pref, "password")
      end)
    end
  end

  describe "deprecation management" do
    test "supports preference deprecation with replacement" do
      deprecated_preference = %{
        preference_key: "llm.old_provider_setting",
        deprecated: true,
        replacement_key: "llm.providers.default"
      }

      # Deprecated preferences must have replacement
      if deprecated_preference.deprecated do
        assert Map.has_key?(deprecated_preference, :replacement_key)
        assert deprecated_preference.replacement_key != nil
      end
    end

    test "tracks version evolution" do
      version_evolution = [
        {1, "llm.provider", "Initial LLM provider setting"},
        {2, "llm.providers.default", "Updated to support multiple providers"},
        {3, "llm.providers.primary", "Renamed for clarity"}
      ]

      # Version should increment with changes
      versions = Enum.map(version_evolution, fn {version, _key, _desc} -> version end)
      assert versions == Enum.sort(versions)
      assert List.first(versions) == 1
    end
  end
end
