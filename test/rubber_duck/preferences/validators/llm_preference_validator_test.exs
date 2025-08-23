defmodule RubberDuck.Preferences.Validators.LlmPreferenceValidatorTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Preferences.Validators.LlmPreferenceValidator

  describe "provider selection validation" do
    test "validates valid provider list" do
      assert :ok = LlmPreferenceValidator.validate_provider_selection(["openai", "anthropic"])
      assert :ok = LlmPreferenceValidator.validate_provider_selection(["google"])
    end

    test "validates single provider string" do
      assert :ok = LlmPreferenceValidator.validate_provider_selection("openai")
      assert :ok = LlmPreferenceValidator.validate_provider_selection("anthropic")
    end

    test "rejects invalid providers" do
      assert {:error, _} =
               LlmPreferenceValidator.validate_provider_selection(["invalid_provider"])

      assert {:error, _} = LlmPreferenceValidator.validate_provider_selection("unknown")
    end

    test "rejects non-string/non-list values" do
      assert {:error, _} = LlmPreferenceValidator.validate_provider_selection(123)
      assert {:error, _} = LlmPreferenceValidator.validate_provider_selection(%{})
    end
  end

  describe "model selection validation" do
    test "validates OpenAI models" do
      assert :ok = LlmPreferenceValidator.validate_model_selection("openai", "gpt-4")
      assert :ok = LlmPreferenceValidator.validate_model_selection("openai", "gpt-4-turbo")

      assert {:error, _} =
               LlmPreferenceValidator.validate_model_selection("openai", "invalid-model")
    end

    test "validates Anthropic models" do
      assert :ok =
               LlmPreferenceValidator.validate_model_selection(
                 "anthropic",
                 "claude-3-5-sonnet-20241022"
               )

      assert :ok =
               LlmPreferenceValidator.validate_model_selection(
                 "anthropic",
                 "claude-3-opus-20240229"
               )

      assert {:error, _} =
               LlmPreferenceValidator.validate_model_selection("anthropic", "invalid-claude")
    end

    test "validates Google models" do
      assert :ok = LlmPreferenceValidator.validate_model_selection("google", "gemini-1.5-pro")
      assert :ok = LlmPreferenceValidator.validate_model_selection("google", "gemini-1.5-flash")

      assert {:error, _} =
               LlmPreferenceValidator.validate_model_selection("google", "invalid-gemini")
    end

    test "allows any model for local provider" do
      assert :ok = LlmPreferenceValidator.validate_model_selection("local", "custom-model")
      assert :ok = LlmPreferenceValidator.validate_model_selection("local", "llama-7b")
    end

    test "rejects unknown providers" do
      assert {:error, _} = LlmPreferenceValidator.validate_model_selection("unknown", "model")
    end
  end

  describe "temperature validation" do
    test "validates OpenAI temperature range" do
      assert :ok = LlmPreferenceValidator.validate_temperature("openai", 0.0)
      assert :ok = LlmPreferenceValidator.validate_temperature("openai", 1.0)
      assert :ok = LlmPreferenceValidator.validate_temperature("openai", 2.0)
      assert {:error, _} = LlmPreferenceValidator.validate_temperature("openai", -0.1)
      assert {:error, _} = LlmPreferenceValidator.validate_temperature("openai", 2.1)
    end

    test "validates Anthropic temperature range" do
      assert :ok = LlmPreferenceValidator.validate_temperature("anthropic", 0.0)
      assert :ok = LlmPreferenceValidator.validate_temperature("anthropic", 0.5)
      assert :ok = LlmPreferenceValidator.validate_temperature("anthropic", 1.0)
      assert {:error, _} = LlmPreferenceValidator.validate_temperature("anthropic", 1.1)
    end

    test "validates Google temperature range" do
      assert :ok = LlmPreferenceValidator.validate_temperature("google", 0.0)
      assert :ok = LlmPreferenceValidator.validate_temperature("google", 2.0)
      assert {:error, _} = LlmPreferenceValidator.validate_temperature("google", 2.1)
    end
  end

  describe "token limit validation" do
    test "validates token limits within model capabilities" do
      assert :ok = LlmPreferenceValidator.validate_token_limit("openai", "gpt-4", 4000)

      assert :ok =
               LlmPreferenceValidator.validate_token_limit(
                 "anthropic",
                 "claude-3-5-sonnet-20241022",
                 8000
               )
    end

    test "rejects token limits exceeding model capabilities" do
      assert {:error, _} = LlmPreferenceValidator.validate_token_limit("openai", "gpt-4", 10_000)
    end

    test "rejects invalid token limit values" do
      assert {:error, _} = LlmPreferenceValidator.validate_token_limit("openai", "gpt-4", 0)
      assert {:error, _} = LlmPreferenceValidator.validate_token_limit("openai", "gpt-4", -100)

      assert {:error, _} =
               LlmPreferenceValidator.validate_token_limit("openai", "gpt-4", "invalid")
    end
  end

  describe "fallback chain validation" do
    test "validates valid fallback chains" do
      assert :ok = LlmPreferenceValidator.validate_fallback_chain(["anthropic", "openai"])

      assert :ok =
               LlmPreferenceValidator.validate_fallback_chain(["openai", "google", "anthropic"])
    end

    test "rejects chains with invalid providers" do
      assert {:error, _} = LlmPreferenceValidator.validate_fallback_chain(["invalid", "openai"])
    end

    test "rejects chains with duplicates" do
      assert {:error, _} = LlmPreferenceValidator.validate_fallback_chain(["openai", "openai"])
    end

    test "rejects non-list fallback chains" do
      assert {:error, _} = LlmPreferenceValidator.validate_fallback_chain("openai")
      assert {:error, _} = LlmPreferenceValidator.validate_fallback_chain(%{})
    end
  end

  describe "cost configuration validation" do
    test "validates valid cost configuration" do
      valid_config = %{
        "quality_threshold" => 0.8,
        "cost_per_token_threshold" => 0.00001,
        "token_usage_limits" => %{
          "daily_limit" => 100_000,
          "weekly_limit" => 500_000,
          "monthly_limit" => 2_000_000
        }
      }

      assert :ok = LlmPreferenceValidator.validate_cost_config(valid_config)
    end

    test "rejects invalid quality thresholds" do
      invalid_config = %{
        # > 1.0
        "quality_threshold" => 1.5,
        "cost_per_token_threshold" => 0.00001,
        "token_usage_limits" => %{
          "daily_limit" => 100_000,
          "weekly_limit" => 500_000,
          "monthly_limit" => 2_000_000
        }
      }

      assert {:error, _} = LlmPreferenceValidator.validate_cost_config(invalid_config)
    end

    test "rejects invalid token limits" do
      invalid_config = %{
        "quality_threshold" => 0.8,
        "cost_per_token_threshold" => 0.00001,
        "token_usage_limits" => %{
          # Negative limit
          "daily_limit" => -100
        }
      }

      assert {:error, _} = LlmPreferenceValidator.validate_cost_config(invalid_config)
    end

    test "rejects non-map cost configuration" do
      assert {:error, _} = LlmPreferenceValidator.validate_cost_config("invalid")
    end
  end

  describe "monitoring configuration validation" do
    test "validates valid monitoring configuration" do
      valid_config = %{
        # 5 minutes
        "health_check_interval" => 300_000,
        "alert_thresholds" => %{
          "error_rate" => 0.1,
          "response_time_ms" => 5000,
          "availability" => 0.95
        }
      }

      assert :ok = LlmPreferenceValidator.validate_monitoring_config(valid_config)
    end

    test "rejects invalid health check intervals" do
      invalid_config = %{
        # Too short (< 10 seconds)
        "health_check_interval" => 5000,
        "alert_thresholds" => %{}
      }

      assert {:error, _} = LlmPreferenceValidator.validate_monitoring_config(invalid_config)
    end

    test "rejects invalid alert thresholds" do
      invalid_config = %{
        "health_check_interval" => 300_000,
        "alert_thresholds" => %{
          # > 1.0
          "error_rate" => 1.5,
          # Negative
          "response_time_ms" => -100
        }
      }

      assert {:error, _} = LlmPreferenceValidator.validate_monitoring_config(invalid_config)
    end

    test "allows optional threshold values" do
      partial_config = %{
        "health_check_interval" => 300_000,
        "alert_thresholds" => %{
          "error_rate" => 0.1
          # Missing other thresholds - should be OK
        }
      }

      assert :ok = LlmPreferenceValidator.validate_monitoring_config(partial_config)
    end
  end
end
