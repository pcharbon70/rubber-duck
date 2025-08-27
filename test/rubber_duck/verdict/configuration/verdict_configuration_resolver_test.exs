defmodule RubberDuck.Verdict.Configuration.VerdictConfigurationResolverTest do
  @moduledoc """
  Tests for VerdictConfigurationResolver - three-tier configuration resolution.
  """

  use ExUnit.Case, async: true
  use RubberDuck.DataCase

  alias RubberDuck.Verdict.Configuration.VerdictConfigurationResolver
  alias RubberDuck.Verdict.VerdictSystemConfiguration

  describe "system configuration resolution" do
    test "get_system_configuration/0 returns default configuration when none exists" do
      assert {:ok, config} = VerdictConfigurationResolver.get_system_configuration()

      assert config[:enabled] == true
      assert config[:default_screening_model] == "gpt-4o-mini"
      assert config[:default_detailed_model] == "gpt-4o"
      assert Decimal.equal?(config[:global_daily_budget], Decimal.new("100.00"))
    end
  end

  describe "configuration validation" do
    test "validate_configuration_update/2 validates system configuration data" do
      valid_config = %{
        enabled: true,
        default_screening_model: "gpt-4o-mini",
        default_detailed_model: "gpt-4o",
        global_daily_budget: 100.00,
        preferred_providers: ["openai", "anthropic"]
      }

      assert :ok =
               VerdictConfigurationResolver.validate_configuration_update(:system, valid_config)
    end

    test "validate_configuration_update/2 rejects invalid system configuration" do
      invalid_config = %{
        enabled: true,
        preferred_providers: ["invalid_provider"]
      }

      assert {:error, _reason} =
               VerdictConfigurationResolver.validate_configuration_update(:system, invalid_config)
    end
  end
end
