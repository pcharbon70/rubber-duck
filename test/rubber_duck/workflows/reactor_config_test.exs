defmodule RubberDuck.Workflows.ReactorConfigTest do
  @moduledoc """
  Comprehensive tests for ReactorConfig module and Reactor framework integration.

  Tests all configuration, validation, middleware, telemetry, and error reporting
  functionality to ensure reliable optional workflow capabilities for agents.
  """

  use ExUnit.Case, async: true

  alias RubberDuck.Workflows.ReactorConfig

  @moduletag :unit
  @moduletag :workflows

  describe "default_config/0" do
    test "returns valid default configuration" do
      config = ReactorConfig.default_config()

      assert is_map(config)
      assert Map.has_key?(config, :execution_timeout)
      assert Map.has_key?(config, :max_iterations)
      assert Map.has_key?(config, :enable_telemetry)
      assert Map.has_key?(config, :middleware)

      # Validate default values
      # 5 minutes
      assert config.execution_timeout == 300_000
      assert config.max_iterations == 100
      assert config.enable_telemetry == true
      assert is_list(config.middleware)
    end
  end

  describe "middleware_config/1" do
    test "returns configuration for valid middleware types" do
      # Test each middleware type
      telemetry_config = ReactorConfig.middleware_config(:telemetry)
      assert is_map(telemetry_config)
      assert Map.has_key?(telemetry_config, :event_prefix)

      error_config = ReactorConfig.middleware_config(:error_handling)
      assert is_map(error_config)
      assert Map.has_key?(error_config, :retry_attempts)

      timeout_config = ReactorConfig.middleware_config(:timeout_management)
      assert is_map(timeout_config)
      assert Map.has_key?(timeout_config, :default_step_timeout)

      cleanup_config = ReactorConfig.middleware_config(:resource_cleanup)
      assert is_map(cleanup_config)
      assert Map.has_key?(cleanup_config, :auto_cleanup)
    end

    test "returns empty map for unknown middleware type" do
      config = ReactorConfig.middleware_config(:unknown_middleware)
      assert config == %{}
    end
  end

  describe "create_reactor_config/1" do
    test "creates valid configuration with defaults" do
      assert {:ok, config} = ReactorConfig.create_reactor_config()

      assert is_map(config)
      assert config.execution_timeout == 300_000
      assert config.max_iterations == 100
      assert config.enable_telemetry == true
      assert is_list(config.middleware)
    end

    test "creates configuration with custom options" do
      custom_opts = [
        execution_timeout: 600_000,
        max_iterations: 200,
        enable_telemetry: false
      ]

      assert {:ok, config} = ReactorConfig.create_reactor_config(custom_opts)

      assert config.execution_timeout == 600_000
      assert config.max_iterations == 200
      assert config.enable_telemetry == false
    end

    test "validates configuration parameters" do
      # Test invalid timeout
      assert {:error, {:invalid_timeout, _}} =
               ReactorConfig.create_reactor_config(execution_timeout: -1000)

      # Test invalid iterations
      assert {:error, {:invalid_max_iterations, _}} =
               ReactorConfig.create_reactor_config(max_iterations: -10)

      # Test invalid middleware
      assert {:error, {:invalid_middleware, _}} =
               ReactorConfig.create_reactor_config(middleware: "not_a_list")
    end
  end

  describe "configure_middleware_stack/1" do
    test "configures default middleware stack" do
      assert {:ok, middleware_configs} = ReactorConfig.configure_middleware_stack()

      assert is_list(middleware_configs)
      assert length(middleware_configs) > 0

      # Check that each middleware has configuration
      Enum.each(middleware_configs, fn {middleware_name, config} ->
        assert is_atom(middleware_name)
        assert is_map(config)
      end)
    end

    test "configures custom middleware list" do
      custom_middleware = [:telemetry, :error_handling]

      assert {:ok, middleware_configs} =
               ReactorConfig.configure_middleware_stack(custom_middleware)

      assert length(middleware_configs) == 2

      middleware_names = Enum.map(middleware_configs, &elem(&1, 0))
      assert :telemetry in middleware_names
      assert :error_handling in middleware_names
    end

    test "handles empty middleware list" do
      assert {:ok, middleware_configs} = ReactorConfig.configure_middleware_stack([])
      assert middleware_configs == []
    end
  end

  describe "validate_reactor_config/1" do
    test "validates correct configuration" do
      valid_config = %{
        execution_timeout: 300_000,
        max_iterations: 100,
        enable_telemetry: true,
        middleware: [:telemetry, :error_handling]
      }

      assert {:ok, ^valid_config} = ReactorConfig.validate_reactor_config(valid_config)
    end

    test "rejects invalid timeout" do
      invalid_config = %{
        execution_timeout: -1000,
        max_iterations: 100,
        enable_telemetry: true,
        middleware: [:telemetry]
      }

      assert {:error, {:invalid_timeout, -1000}} =
               ReactorConfig.validate_reactor_config(invalid_config)
    end

    test "rejects invalid max_iterations" do
      invalid_config = %{
        execution_timeout: 300_000,
        max_iterations: 0,
        enable_telemetry: true,
        middleware: [:telemetry]
      }

      assert {:error, {:invalid_max_iterations, 0}} =
               ReactorConfig.validate_reactor_config(invalid_config)
    end

    test "rejects invalid telemetry setting" do
      invalid_config = %{
        execution_timeout: 300_000,
        max_iterations: 100,
        enable_telemetry: "invalid",
        middleware: [:telemetry]
      }

      assert {:error, {:invalid_telemetry_setting, "invalid"}} =
               ReactorConfig.validate_reactor_config(invalid_config)
    end

    test "rejects invalid middleware" do
      invalid_config = %{
        execution_timeout: 300_000,
        max_iterations: 100,
        enable_telemetry: true,
        # Too many middleware (>10)
        middleware: Enum.to_list(1..15)
      }

      assert {:error, {:invalid_middleware, _}} =
               ReactorConfig.validate_reactor_config(invalid_config)
    end
  end

  describe "execution_options/1" do
    test "returns default execution options" do
      options = ReactorConfig.execution_options()

      assert is_map(options)
      assert Map.has_key?(options, :timeout)
      assert Map.has_key?(options, :max_iterations)
      assert Map.has_key?(options, :telemetry_enabled)

      # Validate default values
      assert options.timeout == 300_000
      assert options.max_iterations == 100
      assert options.telemetry_enabled == true
    end

    test "returns workflow-type specific options" do
      # Test long_running workflow type
      long_options = ReactorConfig.execution_options(:long_running)
      # 10 minutes
      assert long_options.timeout == 600_000
      assert long_options.max_iterations == 200

      # Test quick_task workflow type
      quick_options = ReactorConfig.execution_options(:quick_task)
      # 1 minute
      assert quick_options.timeout == 60_000
      assert quick_options.max_iterations == 50

      # Test complex_orchestration workflow type
      complex_options = ReactorConfig.execution_options(:complex_orchestration)
      # 15 minutes
      assert complex_options.timeout == 900_000
      assert complex_options.max_iterations == 500
    end

    test "returns default options for unknown workflow type" do
      options = ReactorConfig.execution_options(:unknown_type)

      # Should return default options
      assert options.timeout == 300_000
      assert options.max_iterations == 100
      assert options.telemetry_enabled == true
    end
  end

  describe "reactor_available?/0" do
    test "correctly identifies Reactor availability" do
      # This test depends on whether Reactor is actually available
      availability = ReactorConfig.reactor_available?()
      assert is_boolean(availability)

      # If Reactor is available, it should be true
      # If not available, it should be false
      # We just verify the function returns a boolean
    end
  end

  describe "initialize_reactor_integration/0" do
    test "handles Reactor initialization when available" do
      # Test integration initialization
      case ReactorConfig.initialize_reactor_integration() do
        {:ok, status} when status in [:initialized, :partial_initialization] ->
          # Success case - Reactor is available
          assert status in [:initialized, :partial_initialization]

        {:error, :reactor_not_available} ->
          # Expected when Reactor is not available
          assert true

        {:error, reason} ->
          # Other errors should be properly structured
          assert is_map(reason) or is_atom(reason)
      end
    end
  end

  describe "edge cases and error handling" do
    test "handles nil configuration gracefully" do
      # Should handle nil input
      assert {:error, _reason} = ReactorConfig.validate_reactor_config(nil)
    end

    test "handles empty configuration" do
      assert {:error, _reason} = ReactorConfig.validate_reactor_config(%{})
    end

    test "handles configuration with extra keys" do
      config_with_extra = %{
        execution_timeout: 300_000,
        max_iterations: 100,
        enable_telemetry: true,
        middleware: [:telemetry],
        extra_key: "should_be_ignored",
        another_extra: 12345
      }

      # Should accept extra keys without error
      assert {:ok, validated_config} = ReactorConfig.validate_reactor_config(config_with_extra)
      assert Map.has_key?(validated_config, :extra_key)
      assert Map.has_key?(validated_config, :another_extra)
    end

    test "handles boundary values correctly" do
      # Test minimum valid values
      min_config = %{
        execution_timeout: 1,
        max_iterations: 1,
        enable_telemetry: false,
        middleware: []
      }

      assert {:ok, _} = ReactorConfig.validate_reactor_config(min_config)

      # Test maximum valid values
      max_config = %{
        # 1 hour
        execution_timeout: 3_600_000,
        max_iterations: 1000,
        enable_telemetry: true,
        # Exactly 10 middleware
        middleware: Enum.to_list(1..10)
      }

      assert {:ok, _} = ReactorConfig.validate_reactor_config(max_config)
    end
  end

  describe "performance and reliability" do
    test "configuration creation is fast" do
      start_time = System.monotonic_time(:microsecond)

      assert {:ok, _config} = ReactorConfig.create_reactor_config()

      end_time = System.monotonic_time(:microsecond)
      duration = end_time - start_time

      # Should complete within 10ms
      assert duration < 10_000
    end

    test "validation handles large configurations efficiently" do
      # Create large but valid configuration
      large_config = %{
        execution_timeout: 300_000,
        max_iterations: 500,
        enable_telemetry: true,
        middleware: [:telemetry, :error_handling, :timeout_management, :resource_cleanup],
        large_metadata: Map.new(1..100, fn i -> {"key_#{i}", "value_#{i}"} end)
      }

      start_time = System.monotonic_time(:microsecond)

      assert {:ok, _validated} = ReactorConfig.validate_reactor_config(large_config)

      end_time = System.monotonic_time(:microsecond)
      duration = end_time - start_time

      # Should complete within 50ms even with large config
      assert duration < 50_000
    end

    test "middleware configuration handles concurrent access" do
      # Test concurrent middleware configuration
      tasks =
        Enum.map(1..10, fn _i ->
          Task.async(fn ->
            ReactorConfig.configure_middleware_stack([:telemetry, :error_handling])
          end)
        end)

      results = Task.await_many(tasks, 5000)

      # All should succeed
      Enum.each(results, fn result ->
        assert match?({:ok, _}, result)
      end)
    end
  end
end
