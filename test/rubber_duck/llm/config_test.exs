defmodule RubberDuck.LLM.ConfigTest do
  use ExUnit.Case, async: true

  alias RubberDuck.LLM.Config

  describe "load_providers/0" do
    test "loads providers from application environment" do
      # This test depends on config being set up
      providers = Config.load_providers()
      assert is_list(providers)
    end
  end

  describe "validate_config/1" do
    test "validates required fields are present" do
      valid_config = %{
        name: :test_provider,
        module: TestProvider,
        api_key: "test_key"
      }

      assert :ok = Config.validate_config(valid_config)
    end

    test "returns error for missing fields" do
      invalid_config = %{
        name: :test_provider
      }

      assert {:error, {:missing_fields, missing}} = Config.validate_config(invalid_config)
      assert :module in missing
      assert :api_key in missing
    end
  end

  describe "default_provider/0" do
    test "returns default provider from config" do
      provider = Config.default_provider()
      assert is_atom(provider)
    end
  end

  describe "rate_limits/1" do
    test "returns rate limit configuration for provider" do
      limits = Config.rate_limits(:test_provider)

      assert is_map(limits)
      assert Map.has_key?(limits, :max_requests)
      assert Map.has_key?(limits, :window_ms)
    end
  end

  describe "circuit_breaker_config/1" do
    test "returns circuit breaker configuration" do
      config = Config.circuit_breaker_config(:test_provider)

      assert Map.has_key?(config, :fuse_name)
      assert config.fuse_name == :llm_test_provider_fuse
      assert Map.has_key?(config, :fuse_strategy)
      assert Map.has_key?(config, :fuse_refresh)
    end
  end
end