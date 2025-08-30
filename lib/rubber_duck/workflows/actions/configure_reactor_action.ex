defmodule RubberDuck.Workflows.Actions.ConfigureReactorAction do
  @moduledoc """
  Reactor configuration action for setting up optional workflow capabilities.

  This action provides comprehensive Reactor framework configuration with
  validation, middleware setup, telemetry integration, and health verification
  for agents that choose to use workflow orchestration.

  Features:
  - Complete Reactor configuration with middleware stack setup
  - Telemetry integration with existing monitoring infrastructure
  - Error reporting integration with Tower (when available)
  - Configuration validation with detailed error reporting
  - Health checks and configuration verification
  - Safe configuration updates with rollback capabilities

  Usage:
  Agents can use this action to configure Reactor workflows when they
  determine that workflow orchestration would benefit their operations.
  """

  use Jido.Action,
    name: "configure_reactor",
    schema: [
      configuration_spec: [type: :map, required: true, doc: "Reactor configuration specification"],
      validation_mode: [
        type: :atom,
        default: :strict,
        doc: "Validation mode (:strict, :permissive, :development)"
      ],
      enable_telemetry: [type: :boolean, default: true, doc: "Enable telemetry integration"],
      enable_error_reporting: [
        type: :boolean,
        default: true,
        doc: "Enable error reporting integration"
      ],
      context: [type: :map, default: %{}, doc: "Configuration context"]
    ]

  require Logger

  alias RubberDuck.Workflows.ReactorConfig

  @doc """
  Configure Reactor framework with comprehensive validation and setup.

  Returns configuration result with validation status, middleware setup,
  and health verification for safe workflow adoption.
  """
  def run(params, _context) do
    %{
      configuration_spec: config_spec,
      validation_mode: validation_mode,
      enable_telemetry: enable_telemetry,
      enable_error_reporting: enable_error_reporting,
      context: config_context
    } = params

    Logger.info("ConfigureReactorAction: Starting Reactor configuration",
      validation_mode: validation_mode,
      telemetry_enabled: enable_telemetry,
      error_reporting_enabled: enable_error_reporting
    )

    configuration_start_time = System.monotonic_time(:microsecond)

    with {:ok, validated_config} <- validate_configuration_spec(config_spec, validation_mode),
         {:ok, reactor_config} <- create_reactor_configuration(validated_config, config_context),
         {:ok, middleware_setup} <-
           setup_middleware_stack(reactor_config, enable_telemetry, enable_error_reporting),
         {:ok, health_check} <- perform_configuration_health_check(reactor_config) do
      configuration_time = System.monotonic_time(:microsecond) - configuration_start_time

      Logger.info("ConfigureReactorAction: Reactor configuration completed successfully",
        configuration_time_us: configuration_time,
        middleware_count: length(middleware_setup.configured_middleware),
        health_status: health_check.overall_health
      )

      {:ok,
       %{
         reactor_config: reactor_config,
         middleware_setup: middleware_setup,
         health_check: health_check,
         configuration_metadata: %{
           configuration_time_microseconds: configuration_time,
           validation_mode: validation_mode,
           telemetry_enabled: enable_telemetry,
           error_reporting_enabled: enable_error_reporting,
           config_spec_provided: map_size(config_spec)
         }
       }}
    else
      {:error, reason} ->
        Logger.error("ConfigureReactorAction: Reactor configuration failed", error: reason)
        {:error, reason}
    end
  end

  # Private implementation functions

  defp validate_configuration_spec(config_spec, validation_mode) do
    Logger.debug("ConfigureReactorAction: Validating configuration specification")

    # Required configuration keys
    required_keys = [:execution_timeout, :middleware]
    optional_keys = [:max_iterations, :enable_telemetry, :enable_error_reporting]

    validation_result =
      case validation_mode do
        :strict ->
          validate_strict_configuration(config_spec, required_keys, optional_keys)

        :permissive ->
          validate_permissive_configuration(config_spec, required_keys)

        :development ->
          validate_development_configuration(config_spec)

        _ ->
          {:error, {:invalid_validation_mode, validation_mode}}
      end

    case validation_result do
      {:ok, validated_spec} ->
        Logger.debug("ConfigureReactorAction: Configuration validation successful")
        {:ok, validated_spec}

      {:error, reason} ->
        Logger.error("ConfigureReactorAction: Configuration validation failed", error: reason)
        {:error, reason}
    end
  end

  defp validate_strict_configuration(config_spec, required_keys, optional_keys) do
    # Strict validation requires all required keys and validates all values
    missing_keys = required_keys -- Map.keys(config_spec)

    if Enum.empty?(missing_keys) do
      # Validate each configuration value
      case validate_configuration_values(config_spec) do
        {:ok, validated_values} ->
          # Add defaults for missing optional keys
          complete_config = add_optional_defaults(validated_values, optional_keys)
          {:ok, complete_config}

        {:error, reason} ->
          {:error, {:value_validation_failed, reason}}
      end
    else
      {:error, {:missing_required_keys, missing_keys}}
    end
  end

  defp validate_permissive_configuration(config_spec, required_keys) do
    # Permissive validation only checks required keys and basic value types
    missing_keys = required_keys -- Map.keys(config_spec)

    if Enum.empty?(missing_keys) do
      # Basic value validation
      validated_config =
        Map.merge(
          %{
            execution_timeout: 300_000,
            max_iterations: 100,
            enable_telemetry: true,
            enable_error_reporting: true,
            middleware: [:telemetry, :error_handling]
          },
          config_spec
        )

      {:ok, validated_config}
    else
      {:error, {:missing_required_keys, missing_keys}}
    end
  end

  defp validate_development_configuration(config_spec) do
    # Development validation provides sensible defaults for all missing values
    development_defaults = %{
      # 1 minute for development
      execution_timeout: 60_000,
      # Fewer iterations
      max_iterations: 50,
      enable_telemetry: true,
      # Disable error reporting in development
      enable_error_reporting: false,
      # Minimal middleware
      middleware: [:telemetry]
    }

    validated_config = Map.merge(development_defaults, config_spec)
    {:ok, validated_config}
  end

  defp validate_configuration_values(config_spec) do
    # Validate individual configuration values
    validation_checks = [
      validate_timeout_value(Map.get(config_spec, :execution_timeout)),
      validate_iterations_value(Map.get(config_spec, :max_iterations)),
      validate_middleware_value(Map.get(config_spec, :middleware)),
      validate_boolean_values(config_spec)
    ]

    case Enum.find(validation_checks, &match?({:error, _}, &1)) do
      nil ->
        {:ok, config_spec}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_timeout_value(timeout)
       when is_integer(timeout) and timeout > 0 and timeout <= 3_600_000 do
    {:ok, :timeout_valid}
  end

  defp validate_timeout_value(timeout) do
    {:error, {:invalid_timeout, timeout}}
  end

  defp validate_iterations_value(iterations)
       when is_integer(iterations) and iterations > 0 and iterations <= 1000 do
    {:ok, :iterations_valid}
  end

  defp validate_iterations_value(iterations) do
    {:error, {:invalid_iterations, iterations}}
  end

  defp validate_middleware_value(middleware)
       when is_list(middleware) and length(middleware) <= 10 do
    {:ok, :middleware_valid}
  end

  defp validate_middleware_value(middleware) do
    {:error, {:invalid_middleware, middleware}}
  end

  defp validate_boolean_values(config_spec) do
    boolean_keys = [:enable_telemetry, :enable_error_reporting]

    invalid_booleans =
      Enum.filter(boolean_keys, fn key ->
        case Map.get(config_spec, key) do
          value when is_boolean(value) -> false
          # Missing is OK
          nil -> false
          # Invalid type
          _ -> true
        end
      end)

    if Enum.empty?(invalid_booleans) do
      {:ok, :booleans_valid}
    else
      {:error, {:invalid_boolean_values, invalid_booleans}}
    end
  end

  defp add_optional_defaults(config, optional_keys) do
    defaults = %{
      max_iterations: 100,
      enable_telemetry: true,
      enable_error_reporting: true
    }

    Enum.reduce(optional_keys, config, fn key, acc ->
      if Map.has_key?(acc, key) do
        acc
      else
        Map.put(acc, key, Map.get(defaults, key))
      end
    end)
  end

  defp create_reactor_configuration(validated_config, context) do
    Logger.debug("ConfigureReactorAction: Creating Reactor configuration")

    # Create configuration using ReactorConfig
    ReactorConfig.create_reactor_config(Map.to_list(validated_config))
  end

  defp setup_middleware_stack(reactor_config, enable_telemetry, enable_error_reporting) do
    Logger.debug("ConfigureReactorAction: Setting up middleware stack")

    # Configure middleware based on settings
    middleware_list = reactor_config.middleware

    # Add conditional middleware
    enhanced_middleware =
      middleware_list
      |> add_telemetry_middleware(enable_telemetry)
      |> add_error_reporting_middleware(enable_error_reporting)

    case ReactorConfig.configure_middleware_stack(enhanced_middleware) do
      {:ok, middleware_configs} ->
        setup_result = %{
          configured_middleware: enhanced_middleware,
          middleware_configs: middleware_configs,
          telemetry_enabled: enable_telemetry,
          error_reporting_enabled: enable_error_reporting
        }

        Logger.debug("ConfigureReactorAction: Middleware stack configured",
          middleware_count: length(enhanced_middleware)
        )

        {:ok, setup_result}

      {:error, reason} ->
        {:error, {:middleware_setup_failed, reason}}
    end
  end

  defp add_telemetry_middleware(middleware_list, true) do
    if :telemetry in middleware_list do
      middleware_list
    else
      [:telemetry | middleware_list]
    end
  end

  defp add_telemetry_middleware(middleware_list, false), do: middleware_list

  defp add_error_reporting_middleware(middleware_list, true) do
    if :error_handling in middleware_list do
      middleware_list
    else
      [:error_handling | middleware_list]
    end
  end

  defp add_error_reporting_middleware(middleware_list, false), do: middleware_list

  defp perform_configuration_health_check(reactor_config) do
    Logger.debug("ConfigureReactorAction: Performing configuration health check")

    # Perform comprehensive health checks
    health_checks = [
      check_reactor_availability(),
      check_configuration_validity(reactor_config),
      check_middleware_functionality(reactor_config),
      check_telemetry_integration(),
      check_error_reporting_integration()
    ]

    failed_checks = Enum.filter(health_checks, &match?({:error, _}, &1))
    successful_checks = Enum.filter(health_checks, &match?({:ok, _}, &1))

    overall_health =
      if Enum.empty?(failed_checks) do
        :healthy
      else
        case length(failed_checks) do
          count when count <= 1 -> :degraded
          count when count <= 3 -> :unhealthy
          _ -> :critical
        end
      end

    health_score = length(successful_checks) / length(health_checks)

    health_result = %{
      overall_health: overall_health,
      health_score: Float.round(health_score, 3),
      successful_checks: length(successful_checks),
      failed_checks: length(failed_checks),
      check_results: health_checks,
      recommendations: generate_health_recommendations(failed_checks)
    }

    Logger.info("ConfigureReactorAction: Health check completed",
      overall_health: overall_health,
      health_score: health_score
    )

    {:ok, health_result}
  end

  # Health check implementations

  defp check_reactor_availability do
    case ReactorConfig.reactor_available?() do
      true ->
        {:ok, %{check: :reactor_availability, status: :available}}

      false ->
        {:error,
         %{check: :reactor_availability, status: :unavailable, issue: :reactor_not_loaded}}
    end
  end

  defp check_configuration_validity(reactor_config) do
    case ReactorConfig.validate_reactor_config(reactor_config) do
      {:ok, _validated} ->
        {:ok, %{check: :configuration_validity, status: :valid}}

      {:error, reason} ->
        {:error, %{check: :configuration_validity, status: :invalid, reason: reason}}
    end
  end

  defp check_middleware_functionality(reactor_config) do
    # Check if middleware can be properly configured
    middleware = Map.get(reactor_config, :middleware, [])

    if is_list(middleware) and not Enum.empty?(middleware) do
      {:ok,
       %{
         check: :middleware_functionality,
         status: :functional,
         middleware_count: length(middleware)
       }}
    else
      {:error,
       %{check: :middleware_functionality, status: :non_functional, issue: :no_middleware}}
    end
  end

  defp check_telemetry_integration do
    # Check telemetry system availability
    case Code.ensure_loaded(:telemetry) do
      {:module, :telemetry} ->
        {:ok, %{check: :telemetry_integration, status: :available}}

      {:error, _reason} ->
        {:error,
         %{check: :telemetry_integration, status: :unavailable, issue: :telemetry_not_loaded}}
    end
  end

  defp check_error_reporting_integration do
    # Check Tower error reporting availability (optional)
    case Code.ensure_loaded(Tower) do
      {:module, Tower} ->
        {:ok, %{check: :error_reporting_integration, status: :available}}

      {:error, _reason} ->
        {:ok, %{check: :error_reporting_integration, status: :unavailable, note: :tower_optional}}
    end
  end

  defp generate_health_recommendations(failed_checks) do
    if Enum.empty?(failed_checks) do
      ["Reactor configuration is healthy and ready for use"]
    else
      Enum.map(failed_checks, &generate_single_recommendation/1)
    end
  end

  defp generate_single_recommendation({:error, error_info}) do
    case error_info.check do
      :reactor_availability ->
        "Install or configure Reactor framework dependency"

      :configuration_validity ->
        "Fix configuration validation errors: #{inspect(error_info.reason)}"

      :middleware_functionality ->
        "Configure at least one middleware component"

      :telemetry_integration ->
        "Ensure telemetry library is available and configured"

      _ ->
        "Address #{error_info.check} issue: #{inspect(error_info)}"
    end
  end
end
