defmodule RubberDuck.Verdict.VerdictSystemConfigurationTest do
  @moduledoc """
  Tests for VerdictSystemConfiguration resource.
  """

  use ExUnit.Case, async: true
  use RubberDuck.DataCase

  alias RubberDuck.Verdict.VerdictSystemConfiguration

  describe "default configuration" do
    test "get_default_configuration/0 returns complete default configuration" do
      defaults = VerdictSystemConfiguration.get_default_configuration()

      assert defaults[:enabled] == true
      assert defaults[:default_screening_model] == "gpt-4o-mini"
      assert defaults[:default_detailed_model] == "gpt-4o"
      assert Decimal.equal?(defaults[:global_daily_budget], Decimal.new("100.00"))
      assert Decimal.equal?(defaults[:default_quality_threshold], Decimal.new("0.8"))
      assert defaults[:preferred_providers] == ["openai", "anthropic"]

      # Validate that default criteria weights sum to 1.0
      weights = defaults[:evaluation_criteria_weights]
      total_weight = weights |> Map.values() |> Enum.sum()
      assert abs(total_weight - 1.0) < 0.001
    end
  end

  describe "configuration validation" do
    test "validate_configuration/1 validates complete configuration map" do
      valid_config = %{
        enabled: true,
        default_screening_model: "gpt-4o-mini",
        default_detailed_model: "gpt-4o",
        global_daily_budget: 100.00,
        default_quality_threshold: 0.8,
        escalation_threshold: 0.6,
        preferred_providers: ["openai", "anthropic"],
        evaluation_criteria_weights: %{
          "correctness" => 0.3,
          "security" => 0.3,
          "maintainability" => 0.2,
          "performance" => 0.1,
          "style" => 0.1
        }
      }

      assert :ok = VerdictSystemConfiguration.validate_configuration(valid_config)
    end

    test "validate_configuration/1 rejects invalid budget" do
      config = %{
        enabled: true,
        default_screening_model: "gpt-4o-mini",
        default_detailed_model: "gpt-4o",
        # Invalid
        global_daily_budget: -50.00
      }

      assert {:error, "Invalid budget value"} =
               VerdictSystemConfiguration.validate_configuration(config)
    end

    test "validate_configuration/1 rejects invalid thresholds" do
      config = %{
        enabled: true,
        default_screening_model: "gpt-4o-mini",
        default_detailed_model: "gpt-4o",
        default_quality_threshold: 0.5,
        # Higher than quality threshold
        escalation_threshold: 0.7
      }

      assert {:error, "Escalation threshold must be less than quality threshold"} =
               VerdictSystemConfiguration.validate_configuration(config)
    end

    test "validate_configuration/1 rejects invalid criteria weights" do
      config = %{
        enabled: true,
        default_screening_model: "gpt-4o-mini",
        default_detailed_model: "gpt-4o",
        evaluation_criteria_weights: %{
          "correctness" => 0.5,
          "security" => 0.3
          # Sum = 0.8, not 1.0
        }
      }

      assert {:error, "Evaluation criteria weights must sum to 1.0"} =
               VerdictSystemConfiguration.validate_configuration(config)
    end
  end
end
