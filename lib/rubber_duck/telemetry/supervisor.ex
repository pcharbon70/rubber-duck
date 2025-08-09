defmodule RubberDuck.Telemetry.Supervisor do
  @moduledoc """
  Advanced telemetry supervision tree for ML/AI focused metrics.
  
  Manages Prometheus integration, ML reporters, and action tracking
  with fault tolerance and proper supervision strategy.
  """

  use Supervisor
  require Logger

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    # Attach action telemetry handlers
    RubberDuck.Telemetry.ActionTelemetry.attach_handlers()
    
    # Get telemetry configuration
    config = Application.get_env(:rubber_duck, :telemetry, [])
    prometheus_enabled = Keyword.get(config, :prometheus_enabled, true)
    prometheus_port = Keyword.get(config, :prometheus_port, 9568)

    children = [
      # ML/AI specific metrics reporter
      RubberDuck.Telemetry.MLReporter,

      # Action performance tracker
      RubberDuck.Telemetry.ActionTracker,

      # Learning metrics tracker
      RubberDuck.Telemetry.LearningTracker,

      # Impact scoring tracker
      RubberDuck.Telemetry.ImpactTracker
    ]

    # Add Prometheus reporter if enabled
    children = if prometheus_enabled do
      prometheus_child = {
        TelemetryMetricsPrometheus,
        [
          metrics: RubberDuck.Telemetry.metrics(),
          port: prometheus_port,
          name: :rubber_duck_prometheus
        ]
      }
      [prometheus_child | children]
    else
      Logger.info("Prometheus telemetry disabled in configuration")
      children
    end

    Logger.info("Starting RubberDuck telemetry supervision tree with #{length(children)} children")
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end