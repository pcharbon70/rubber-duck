defmodule RubberDuck.Application do
  @moduledoc """
  The RubberDuck OTP Application.

  Configures the supervision tree for the application including:
  - Database repository
  - Authentication supervisor
  - Telemetry and monitoring
  - Health checks
  - Error reporting
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Tower starts automatically when configured

    children = [
      # Database connection pool
      RubberDuck.Repo,

      # Event Store for event sourcing
      RubberDuck.EventStore,

      # Authentication system
      {AshAuthentication.Supervisor, [otp_app: :rubber_duck]},

      # Telemetry and monitoring
      RubberDuck.Telemetry,

      # Health check monitoring
      RubberDuck.HealthCheck,

      # Phoenix PubSub for legacy compatibility
      {Phoenix.PubSub, name: RubberDuck.PubSub},

      # Circuit Breaker Registry for message type tracking
      {Registry, keys: :unique, name: RubberDuck.CircuitBreakerRegistry},

      # Circuit Breaker Supervisor for fault tolerance
      RubberDuck.Routing.CircuitBreakerSupervisor,

      # Message Router for typed message dispatch
      RubberDuck.Routing.MessageRouter,

      # Task Supervisor for async message processing
      {Task.Supervisor, name: RubberDuck.TaskSupervisor},

      # Message telemetry reporter
      RubberDuck.Telemetry.MessageReporter,

      # LLM Provider Registry (needed by agents)
      RubberDuck.LLM.ProviderRegistry,

      # Agent Supervisor for dynamic agent management
      {DynamicSupervisor, name: RubberDuck.AgentSupervisor, strategy: :one_for_one},

      # Sensor Supervisor for monitoring sensors
      {DynamicSupervisor, name: RubberDuck.SensorSupervisor, strategy: :one_for_one},

      # LLM Health Sensor
      # Note: The sensor requires a target PID but we'll use DynamicSupervisor for now
      # {RubberDuck.Sensors.LLMHealthSensor, target: RubberDuck.SensorSupervisor},

      # Core Agents
      {RubberDuck.Agents.LLMOrchestratorAgent, id: "llm_orchestrator"},
      {RubberDuck.Agents.LLMMonitoringAgent, id: "llm_monitoring"},

      # Web interface
      RubberDuckWeb.Telemetry,
      RubberDuckWeb.Endpoint
    ]

    # Add GenStage pipeline components if enabled
    children =
      if Application.get_env(:rubber_duck, :pipeline_mode, :sequential) == :genstage do
        Logger.info("GenStage pipeline mode enabled, starting pipeline components...")

        pipeline_children = [
          # Start pipeline components with rest_for_one strategy
          # so if producer fails, all downstream stages restart
          {RubberDuck.Pipeline.EntityUpdateProducer, []},
          {RubberDuck.Pipeline.EntityUpdateProcessor, []},
          {RubberDuck.Pipeline.SideEffectProcessor, []}
        ]

        children ++ pipeline_children
      else
        children
      end

    # Using rest_for_one: if a child process terminates,
    # all processes started after it are also terminated and restarted
    opts = [strategy: :rest_for_one, name: RubberDuck.Supervisor]

    Logger.info("Starting RubberDuck application supervision tree...")

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("RubberDuck application started successfully")
        configure_message_telemetry()
        configure_jido_signal_system()
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("Failed to start RubberDuck application: #{inspect(reason)}")
        error
    end
  end

  # Configure message telemetry handlers
  defp configure_message_telemetry do
    RubberDuck.Telemetry.MessageTelemetry.attach_handlers()
    Logger.info("Message telemetry handlers attached")
  end

  # Configure Jido signal system if needed
  defp configure_jido_signal_system do
    # Any global Jido configuration can go here
    Logger.info("Jido signal system configured")
  end
end
