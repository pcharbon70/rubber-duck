defmodule RubberDuck.Application do
  @moduledoc """
  RubberDuck Application with hierarchical supervision tree.

  Provides a robust supervision structure with:
  - Infrastructure layer (database, telemetry, PubSub)
  - Agentic layer (Skills Registry, Directives Engine, Instructions Processor)
  - Security layer (authentication, monitoring)
  - Application layer (web endpoint)
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting RubberDuck Application with hierarchical supervision...")

    children = [
      # Infrastructure Layer - Critical foundation services
      {Supervisor, infrastructure_children(),
       [strategy: :one_for_one, name: RubberDuck.InfrastructureSupervisor]},

      # Agentic System Layer - Core agent functionality
      {Supervisor, agentic_children(),
       [strategy: :one_for_one, name: RubberDuck.AgenticSupervisor]},

      # Security Layer - Authentication and monitoring
      {Supervisor, security_children(),
       [strategy: :one_for_one, name: RubberDuck.SecuritySupervisor]},

      # Application Layer - Web interface and external APIs
      {Supervisor, application_children(),
       [strategy: :one_for_one, name: RubberDuck.ApplicationSupervisor]},

      # Health Check System
      RubberDuck.HealthCheck.Supervisor
    ]

    # Main supervisor with :rest_for_one strategy to ensure proper shutdown ordering
    opts = [strategy: :rest_for_one, name: RubberDuck.MainSupervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("RubberDuck Application started successfully with PID #{inspect(pid)}")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start RubberDuck Application: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    RubberDuckWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Infrastructure Layer - Database, Telemetry, PubSub
  defp infrastructure_children do
    [
      # Enhanced Telemetry System
      {RubberDuck.Telemetry.Supervisor, []},

      # Database Repository
      RubberDuck.Repo,

      # DNS Cluster for distributed deployments
      {DNSCluster, query: Application.get_env(:rubber_duck, :dns_cluster_query) || :ignore},

      # Background Job Processing
      {Oban, oban_config()},

      # Inter-process Communication
      {Phoenix.PubSub, name: RubberDuck.PubSub},

      # Error Reporting System
      {RubberDuck.ErrorReporting.Supervisor, []}
    ]
  end

  # Agentic System Layer - Core AI/ML functionality
  defp agentic_children do
    [
      # Skills Registry - Central skill management
      RubberDuck.SkillsRegistry,

      # Directives Engine - Runtime behavior modification
      RubberDuck.DirectivesEngine,

      # Instructions Processor - Workflow composition
      RubberDuck.InstructionsProcessor,

      # Agent Coordination Hub
      {RubberDuck.AgentCoordinator, []},

      # Learning System Supervisor
      {RubberDuck.Learning.Supervisor, []}
    ]
  end

  # Security Layer - Authentication and monitoring
  defp security_children do
    [
      # Ash Authentication System
      {AshAuthentication.Supervisor, [otp_app: :rubber_duck]},

      # Security Monitoring
      {RubberDuck.SecurityMonitor.Supervisor, []},

      # Threat Detection System
      {RubberDuck.ThreatDetection.Supervisor, []}
    ]
  end

  # Application Layer - Web interface
  defp application_children do
    [
      # Web Endpoint - Last to start, first to stop
      RubberDuckWeb.Endpoint
    ]
  end

  # Oban Configuration with enhanced error handling
  defp oban_config do
    base_config =
      AshOban.config(
        Application.fetch_env!(:rubber_duck, :ash_domains),
        Application.fetch_env!(:rubber_duck, Oban)
      )

    # Enhanced configuration with better supervision
    Map.merge(base_config, %{
      engine: Oban.Engines.Basic,
      queues: [
        default: 10,
        agents: 5,
        learning: 3,
        security: 8,
        maintenance: 2
      ],
      plugins: [
        Oban.Plugins.Pruner,
        {Oban.Plugins.Cron, crontab: cron_jobs()}
      ]
    })
  end

  # Scheduled jobs configuration
  defp cron_jobs do
    [
      # Health check every 5 minutes
      {"*/5 * * * *", RubberDuck.Jobs.HealthCheckJob},

      # Agent maintenance every hour
      {"0 * * * *", RubberDuck.Jobs.AgentMaintenanceJob},

      # Learning system sync every 30 minutes
      {"*/30 * * * *", RubberDuck.Jobs.LearningSyncJob},

      # Security audit daily at 2 AM
      {"0 2 * * *", RubberDuck.Jobs.SecurityAuditJob}
    ]
  end
end
