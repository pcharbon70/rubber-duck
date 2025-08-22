defmodule RubberDuck.Telemetry.Supervisor do
  @moduledoc """
  Enhanced Telemetry Supervisor for RubberDuck Application.

  Manages telemetry collection, metrics aggregation, and monitoring
  for the entire application ecosystem including agents, skills,
  and infrastructure components.
  """

  use Supervisor
  require Logger

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    Logger.info("Starting Enhanced Telemetry System...")

    children =
      [
        # Core telemetry system (existing Phoenix telemetry)
        RubberDuckWeb.Telemetry,

        # VM and Application Metrics Collector
        {RubberDuck.Telemetry.VMMetrics, []},

        # Agent Performance Metrics
        {RubberDuck.Telemetry.AgentMetrics, []},

        # Skills Registry Metrics
        {RubberDuck.Telemetry.SkillsMetrics, []},

        # Database Performance Metrics
        {RubberDuck.Telemetry.DatabaseMetrics, []},

        # Security Event Metrics
        {RubberDuck.Telemetry.SecurityMetrics, []},

        # Prometheus Reporter (if configured)
        prometheus_reporter_child(),

        # Telemetry Event Handler
        {RubberDuck.Telemetry.EventHandler, []}
      ]
      |> Enum.reject(&is_nil/1)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp prometheus_reporter_child do
    if Application.get_env(:rubber_duck, :enable_prometheus, false) do
      {RubberDuck.Telemetry.PrometheusReporter, []}
    else
      nil
    end
  end
end
