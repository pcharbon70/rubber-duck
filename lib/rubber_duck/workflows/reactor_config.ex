defmodule RubberDuck.Workflows.ReactorConfig do
  @moduledoc """
  Reactor framework configuration for RubberDuck workflows.

  This module provides configuration for optional Reactor workflow orchestration
  that agents can choose to use for complex multi-step operations. Workflows
  remain completely optional and agents continue to operate autonomously.

  Configuration includes:
  - Middleware stack for telemetry and error handling
  - Default execution options and timeouts
  - Integration with existing RubberDuck monitoring systems
  - Error reporting integration with Tower (if available)
  - RubberDuck-specific Reactor conventions and patterns
  """

  require Logger

  # Default Reactor configuration for RubberDuck workflows
  @default_reactor_config %{
    # 5 minutes default timeout
    execution_timeout: 300_000,
    # Prevent infinite loops
    max_iterations: 100,
    # Integrate with existing telemetry
    enable_telemetry: true,
    # Tower integration if available
    enable_error_reporting: true,
    middleware: [
      :telemetry,
      :error_handling,
      :timeout_management,
      :resource_cleanup,
      # Phase 6.2 enhancement: prompt integration middleware
      :prompt_integration
    ],
    # Phase 6.2 enhancement: prompt integration configuration
    prompt_integration: %{
      enabled: true,
      resolution_strategy: :optimized,
      context_enhancement: true,
      performance_monitoring: true
    }
  }

  # RubberDuck-specific Reactor middleware configurations
  @middleware_configs %{
    telemetry: %{
      event_prefix: [:rubber_duck, :workflow],
      include_metadata: true,
      track_duration: true
    },
    error_handling: %{
      retry_attempts: 3,
      backoff_strategy: :exponential,
      circuit_breaker_threshold: 5
    },
    timeout_management: %{
      # 30 seconds per step
      default_step_timeout: 30_000,
      # 5 minutes total
      total_workflow_timeout: 300_000,
      enable_warnings: true
    },
    resource_cleanup: %{
      auto_cleanup: true,
      # 10 seconds for cleanup
      cleanup_timeout: 10_000,
      preserve_on_error: false
    },
    # Phase 6.2 enhancement: prompt integration middleware configuration
    prompt_integration: %{
      enable_prompt_resolution: true,
      enable_context_enhancement: true,
      enable_performance_monitoring: true,
      resolution_cache_enabled: true,
      max_resolution_time_ms: 1000
    }
  }

  @doc """
  Get default Reactor configuration for RubberDuck workflows.
  """
  def default_config do
    @default_reactor_config
  end

  @doc """
  Get middleware configuration for a specific middleware type.
  """
  def middleware_config(middleware_type) do
    Map.get(@middleware_configs, middleware_type, %{})
  end

  @doc """
  Create Reactor configuration with RubberDuck-specific settings.
  """
  def create_reactor_config(opts \\ []) do
    base_config = @default_reactor_config
    custom_config = Map.new(opts)

    merged_config = Map.merge(base_config, custom_config)

    Logger.debug("ReactorConfig: Creating Reactor configuration",
      timeout: merged_config.execution_timeout,
      middleware_count: length(merged_config.middleware)
    )

    # Validate configuration
    case validate_reactor_config(merged_config) do
      {:ok, validated_config} ->
        Logger.info("ReactorConfig: Reactor configuration created successfully")
        {:ok, validated_config}

      {:error, reason} ->
        Logger.error("ReactorConfig: Invalid configuration", error: reason)
        {:error, reason}
    end
  end

  @doc """
  Configure Reactor middleware stack for RubberDuck workflows.
  """
  def configure_middleware_stack(middleware_list \\ nil) do
    middleware_to_configure = middleware_list || @default_reactor_config.middleware

    middleware_configs =
      Enum.map(middleware_to_configure, fn middleware ->
        config = middleware_config(middleware)
        {middleware, config}
      end)

    Logger.debug("ReactorConfig: Configuring middleware stack",
      middleware_count: length(middleware_configs)
    )

    {:ok, middleware_configs}
  end

  @doc """
  Validate Reactor configuration for RubberDuck compatibility.
  """
  def validate_reactor_config(config) do
    validation_checks = [
      validate_timeout_settings(config),
      validate_middleware_settings(config),
      validate_telemetry_settings(config),
      validate_resource_settings(config)
    ]

    case Enum.find(validation_checks, &match?({:error, _}, &1)) do
      nil ->
        {:ok, config}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get Reactor execution options for a specific workflow type.
  """
  def execution_options(workflow_type \\ :default) do
    base_options = %{
      timeout: @default_reactor_config.execution_timeout,
      max_iterations: @default_reactor_config.max_iterations,
      telemetry_enabled: @default_reactor_config.enable_telemetry
    }

    # Adjust options based on workflow type
    type_specific_options =
      case workflow_type do
        :long_running ->
          # 10 minutes, more iterations
          %{timeout: 600_000, max_iterations: 200}

        :quick_task ->
          # 1 minute, fewer iterations
          %{timeout: 60_000, max_iterations: 50}

        :complex_orchestration ->
          # 15 minutes, many iterations
          %{timeout: 900_000, max_iterations: 500}

        _ ->
          # Use defaults
          %{}
      end

    Map.merge(base_options, type_specific_options)
  end

  @doc """
  Check if Reactor is properly configured and available.
  """
  def reactor_available? do
    # Check if Reactor module is available
    case Code.ensure_loaded(Reactor) do
      {:module, Reactor} ->
        Logger.debug("ReactorConfig: Reactor framework is available")
        true

      {:error, _reason} ->
        Logger.warning("ReactorConfig: Reactor framework not available")
        false
    end
  end

  @doc """
  Initialize Reactor integration with RubberDuck telemetry and monitoring.
  """
  def initialize_reactor_integration do
    if reactor_available?() do
      Logger.info("ReactorConfig: Initializing Reactor integration")
      perform_reactor_setup()
    else
      {:error, :reactor_not_available}
    end
  end

  defp perform_reactor_setup do
    with :ok <- setup_reactor_telemetry(),
         :ok <- setup_error_reporting() do
      Logger.info("ReactorConfig: Reactor integration initialized successfully")
      {:ok, :initialized}
    else
      {:error, reason} when reason != :error_reporting_failed ->
        Logger.error("ReactorConfig: Telemetry setup failed", error: reason)
        {:error, reason}

      {:error, :error_reporting_failed} ->
        Logger.warning("ReactorConfig: Error reporting setup failed, continuing without")
        {:ok, :partial_initialization}
    end
  end

  # Private helper functions

  defp validate_timeout_settings(config) do
    timeout = Map.get(config, :execution_timeout, 0)

    # Max 1 hour
    if timeout > 0 and timeout <= 3_600_000 do
      {:ok, :timeout_valid}
    else
      {:error, {:invalid_timeout, timeout}}
    end
  end

  defp validate_middleware_settings(config) do
    middleware = Map.get(config, :middleware, [])

    # Max 10 middleware
    if is_list(middleware) and length(middleware) <= 10 do
      {:ok, :middleware_valid}
    else
      {:error, {:invalid_middleware, middleware}}
    end
  end

  defp validate_telemetry_settings(config) do
    telemetry_enabled = Map.get(config, :enable_telemetry, true)

    if is_boolean(telemetry_enabled) do
      {:ok, :telemetry_valid}
    else
      {:error, {:invalid_telemetry_setting, telemetry_enabled}}
    end
  end

  defp validate_resource_settings(config) do
    max_iterations = Map.get(config, :max_iterations, 100)

    if is_integer(max_iterations) and max_iterations > 0 and max_iterations <= 1000 do
      {:ok, :resource_valid}
    else
      {:error, {:invalid_max_iterations, max_iterations}}
    end
  end

  defp setup_reactor_telemetry do
    case safe_telemetry_setup() do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp safe_telemetry_setup do
    # Attach telemetry handlers for Reactor events
    telemetry_events = [
      [:reactor, :workflow, :start],
      [:reactor, :workflow, :stop],
      [:reactor, :workflow, :error],
      [:reactor, :step, :start],
      [:reactor, :step, :stop],
      [:reactor, :step, :error]
    ]

    Enum.each(telemetry_events, fn event ->
      :telemetry.attach(
        "rubber_duck_reactor_#{Enum.join(event, "_")}",
        event,
        &handle_reactor_telemetry/4,
        %{}
      )
    end)

    Logger.debug("ReactorConfig: Telemetry handlers attached for Reactor")
    :ok
  rescue
    error ->
      Logger.error("ReactorConfig: Failed to setup telemetry", error: error)
      {:error, {:telemetry_setup_failed, error}}
  end

  defp setup_error_reporting do
    # Setup error reporting integration (Tower if available)
    case Code.ensure_loaded(Tower) do
      {:module, Tower} ->
        Logger.debug("ReactorConfig: Tower error reporting available")
        :ok

      {:error, _reason} ->
        Logger.debug("ReactorConfig: Tower not available, skipping error reporting setup")
        # Continue without Tower
        :ok
    end
  end

  defp handle_reactor_telemetry(event, measurements, metadata, config) do
    # Handle Reactor telemetry events for monitoring and logging
    event_name = Enum.join(event, ".")

    case event do
      [:reactor, :workflow, :start] ->
        Logger.debug("Reactor workflow started",
          workflow_id: Map.get(metadata, :id),
          workflow_type: Map.get(metadata, :type)
        )

      [:reactor, :workflow, :stop] ->
        duration = Map.get(measurements, :duration, 0)

        Logger.info("Reactor workflow completed",
          workflow_id: Map.get(metadata, :id),
          duration_ms: duration / 1_000_000
        )

      [:reactor, :workflow, :error] ->
        Logger.error("Reactor workflow error",
          workflow_id: Map.get(metadata, :id),
          error: Map.get(metadata, :error)
        )

      _ ->
        Logger.debug("Reactor event: #{event_name}", metadata: metadata)
    end
  end
end
