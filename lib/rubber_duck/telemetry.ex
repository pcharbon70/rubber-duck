defmodule RubberDuck.Telemetry do
  @moduledoc """
  Telemetry supervisor and metrics definitions for RubberDuck application.

  Manages VM metrics collection, custom application measurements, and telemetry reporters.
  """

  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Polls VM metrics and custom measurements periodically
      {:telemetry_poller,
       measurements: periodic_measurements(), period: 10_000, name: :rubber_duck_poller}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # VM Metrics
      last_value("vm.memory.total", unit: :byte, description: "Total memory used by the VM"),
      last_value("vm.memory.processes", unit: :byte, description: "Memory used by processes"),
      last_value("vm.memory.system", unit: :byte, description: "Memory used by the system"),
      last_value("vm.memory.atom", unit: :byte, description: "Memory used by atoms"),
      last_value("vm.memory.binary", unit: :byte, description: "Memory used by binaries"),
      last_value("vm.memory.ets", unit: :byte, description: "Memory used by ETS tables"),

      # Run Queue Metrics
      last_value("vm.total_run_queue_lengths.total", description: "Total run queue length"),
      last_value("vm.total_run_queue_lengths.cpu", description: "CPU run queue length"),
      last_value("vm.total_run_queue_lengths.io", description: "IO run queue length"),

      # System Counts
      last_value("vm.system_counts.process_count", description: "Number of processes"),
      last_value("vm.system_counts.atom_count", description: "Number of atoms"),
      last_value("vm.system_counts.port_count", description: "Number of ports"),

      # Database Metrics (Ash-specific)
      summary("ash.query.duration",
        unit: {:native, :millisecond},
        tags: [:resource, :action],
        description: "Duration of Ash queries"
      ),
      counter("ash.query.count",
        tags: [:resource, :action],
        description: "Count of Ash queries"
      ),

      # Authentication Metrics
      counter("authentication.sign_in.success",
        tags: [:strategy],
        description: "Successful sign-in attempts"
      ),
      counter("authentication.sign_in.failure",
        tags: [:strategy, :reason],
        description: "Failed sign-in attempts"
      ),
      counter("authentication.registration.success",
        description: "Successful user registrations"
      ),
      counter("authentication.registration.failure",
        tags: [:reason],
        description: "Failed user registrations"
      ),

      # Application Health Metrics
      last_value("rubber_duck.health.database",
        description: "Database connectivity status (1 = healthy, 0 = unhealthy)"
      ),
      last_value("rubber_duck.health.services",
        description: "Overall service health status"
      ),

      # Process Metrics
      last_value("rubber_duck.repo.queue_size",
        description: "Database connection pool queue size"
      ),
      last_value("rubber_duck.repo.pool_size",
        description: "Database connection pool size"
      ),

      # ML/AI Action Performance Metrics
      counter("rubber_duck.action.count",
        tags: [:action_type, :resource, :status],
        description: "Count of action executions"
      ),
      summary("rubber_duck.action.duration",
        unit: {:native, :millisecond},
        tags: [:action_type, :resource],
        description: "Duration of action execution"
      ),
      distribution("rubber_duck.action.execution_time",
        unit: {:native, :millisecond},
        description: "Distribution of action execution times",
        reporter_options: [buckets: [50, 100, 250, 500, 1000, 2500, 5000, 10000]]
      ),
      
      # Learning Accuracy Metrics
      last_value("rubber_duck.learning.accuracy",
        tags: [:agent_type, :context],
        description: "Current learning accuracy for agents"
      ),
      counter("rubber_duck.learning.feedback_processed",
        tags: [:feedback_type, :agent_id],
        description: "Count of feedback events processed"
      ),
      summary("rubber_duck.learning.improvement_rate",
        tags: [:agent_type],
        description: "Rate of learning improvement"
      ),
      
      # Impact Scoring Metrics
      distribution("rubber_duck.impact.score",
        tags: [:analysis_type, :domain],
        description: "Distribution of business impact scores",
        reporter_options: [buckets: [1.0, 2.0, 3.0, 5.0, 7.0, 8.0, 9.0, 10.0]]
      ),
      counter("rubber_duck.impact.high_impact_actions",
        tags: [:threshold_level, :action_type],
        description: "Count of high-impact actions identified"
      ),
      last_value("rubber_duck.impact.business_value",
        tags: [:metric_type, :currency],
        description: "Business value generated"
      ),
      
      # ML System Health Metrics
      last_value("rubber_duck.ml.system.agents",
        description: "Number of active ML agents"
      ),
      last_value("rubber_duck.ml.system.resources",
        tags: [:resource_type],
        description: "ML system resource utilization"
      ),
      last_value("rubber_duck.ml.system.performance",
        description: "Overall ML system performance score"
      )
    ]
  end

  defp periodic_measurements do
    [
      # Custom measurements for application health
      {__MODULE__, :dispatch_health_check, []},
      {__MODULE__, :dispatch_repo_metrics, []}
    ]
  end

  @doc false
  def dispatch_health_check do
    health_status = if database_healthy?(), do: 1, else: 0

    :telemetry.execute(
      [:rubber_duck, :health, :database],
      %{value: health_status},
      %{}
    )

    :telemetry.execute(
      [:rubber_duck, :health, :services],
      %{value: health_status},
      %{}
    )
  end

  @doc false
  def dispatch_repo_metrics do
    case Process.whereis(RubberDuck.Repo) do
      nil ->
        :ok

      pid ->
        # Get pool info using DBConnection
        case :sys.get_state(pid) do
          {:ready, _, _, _} ->
            # Pool is healthy, emit default values
            :telemetry.execute(
              [:rubber_duck, :repo, :queue_size],
              %{value: 0},
              %{}
            )

            :telemetry.execute(
              [:rubber_duck, :repo, :pool_size],
              # Default pool size
              %{value: 10},
              %{}
            )

          _ ->
            :ok
        end
    end
  rescue
    _e -> :ok
  end

  defp database_healthy? do
    RubberDuck.Repo.query("SELECT 1", [])
    true
  rescue
    _e -> false
  end
end
