defmodule RubberDuck.HealthCheck.Supervisor do
  @moduledoc """
  Health Check Supervisor for monitoring system health.

  Manages health checks for:
  - Database connectivity
  - Service availability
  - Resource usage monitoring
  - External dependencies
  """

  use Supervisor
  require Logger

  def start_link(init_arg \\ []) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    Logger.info("Starting Health Check System...")

    children = [
      # Database Health Monitor
      {RubberDuck.HealthCheck.DatabaseMonitor, []},

      # Resource Usage Monitor
      {RubberDuck.HealthCheck.ResourceMonitor, []},

      # Service Availability Monitor
      {RubberDuck.HealthCheck.ServiceMonitor, []},

      # Agent Health Monitor
      {RubberDuck.HealthCheck.AgentMonitor, []},

      # Health Status Aggregator
      {RubberDuck.HealthCheck.StatusAggregator, []},

      # Health Check HTTP Server
      {RubberDuck.HealthCheck.HTTPServer, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
