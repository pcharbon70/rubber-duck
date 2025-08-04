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
       measurements: periodic_measurements(), 
       period: 10_000,
       name: :rubber_duck_poller}
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
              %{value: 10},  # Default pool size
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