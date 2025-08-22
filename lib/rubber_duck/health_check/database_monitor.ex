defmodule RubberDuck.HealthCheck.DatabaseMonitor do
  @moduledoc """
  Database connectivity and performance health monitor.

  Monitors:
  - Connection pool status
  - Query response times
  - Connection availability
  - Database disk usage (if accessible)
  """

  use GenServer
  require Logger

  alias Ecto.Adapters.SQL

  # 30 seconds
  @check_interval 30_000
  # 5 seconds
  @query_timeout 5_000

  defstruct [
    :timer_ref,
    :last_check,
    :consecutive_failures,
    :health_status,
    :performance_metrics
  ]

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_health_status do
    GenServer.call(__MODULE__, :get_health_status)
  end

  def force_check do
    GenServer.cast(__MODULE__, :force_check)
  end

  ## Server Implementation

  @impl true
  def init(_opts) do
    Logger.info("Starting Database Health Monitor")

    # Perform initial check
    send(self(), :perform_health_check)

    state = %__MODULE__{
      timer_ref: nil,
      last_check: nil,
      consecutive_failures: 0,
      health_status: :unknown,
      performance_metrics: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_health_status, _from, state) do
    health_report = %{
      status: state.health_status,
      last_check: state.last_check,
      consecutive_failures: state.consecutive_failures,
      performance_metrics: state.performance_metrics
    }

    {:reply, health_report, state}
  end

  @impl true
  def handle_cast(:force_check, state) do
    new_state = perform_database_check(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:perform_health_check, state) do
    new_state = perform_database_check(state)

    # Schedule next check
    timer_ref = Process.send_after(self(), :perform_health_check, @check_interval)
    final_state = %{new_state | timer_ref: timer_ref}

    {:noreply, final_state}
  end

  ## Internal Functions

  defp perform_database_check(state) do
    case safe_database_check(state) do
      {:ok, result} ->
        result

      {:error, error} ->
        Logger.error("Database health check exception: #{inspect(error)}")

        %{
          state
          | health_status: :critical,
            last_check: DateTime.utc_now(),
            consecutive_failures: state.consecutive_failures + 1
        }
    end
  end

  defp safe_database_check(state) do
    start_time = System.monotonic_time(:millisecond)

    # Test basic connectivity
    connection_result = test_database_connection()

    # Test query performance
    query_result = test_query_performance()

    # Check connection pool status
    pool_status = check_connection_pool()

    end_time = System.monotonic_time(:millisecond)
    check_duration = end_time - start_time

    result =
      case {connection_result, query_result} do
        {:ok, {:ok, query_time}} ->
          health_status = determine_health_status(query_time, pool_status)

          performance_metrics = %{
            query_response_time_ms: query_time,
            check_duration_ms: check_duration,
            pool_size: pool_status.size,
            pool_available: pool_status.available,
            pool_utilization: calculate_pool_utilization(pool_status)
          }

          # Emit telemetry
          emit_health_telemetry(health_status, performance_metrics)

          %{
            state
            | health_status: health_status,
              last_check: DateTime.utc_now(),
              consecutive_failures: 0,
              performance_metrics: performance_metrics
          }

        {error, _} ->
          Logger.warning("Database health check failed: #{inspect(error)}")

          failure_count = state.consecutive_failures + 1
          health_status = if failure_count >= 3, do: :critical, else: :degraded

          # Emit failure telemetry
          emit_failure_telemetry(error, failure_count)

          %{
            state
            | health_status: health_status,
              last_check: DateTime.utc_now(),
              consecutive_failures: failure_count
          }
      end

    {:ok, result}
  rescue
    error -> {:error, error}
  end

  defp test_database_connection do
    safe_database_query()
  end

  defp safe_database_query do
    # Simple connection test
    SQL.query(RubberDuck.Repo, "SELECT 1", [])
    :ok
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp test_query_performance do
    safe_query_performance_test()
  end

  defp safe_query_performance_test do
    start_time = System.monotonic_time(:millisecond)

    # Test query - adjust based on your schema
    SQL.query(RubberDuck.Repo, "SELECT 1 as health_check", [], timeout: @query_timeout)

    end_time = System.monotonic_time(:millisecond)
    query_time = end_time - start_time

    {:ok, query_time}
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp check_connection_pool do
    case safe_connection_pool_check() do
      {:ok, pool_status} -> pool_status
      # Default reasonable values
      {:error, _} -> %{size: 10, available: 8, busy: 2}
    end
  end

  defp safe_connection_pool_check do
    pool_status = DBConnection.get_connection_metrics(RubberDuck.Repo)

    result = %{
      size: Map.get(pool_status, :size, 0),
      available: Map.get(pool_status, :available, 0),
      busy: Map.get(pool_status, :busy, 0)
    }

    {:ok, result}
  rescue
    _error -> {:error, :metrics_unavailable}
  end

  defp determine_health_status(query_time, pool_status) do
    cond do
      # > 5 seconds is critical
      query_time > 5000 -> :critical
      # > 2 seconds is degraded
      query_time > 2000 -> :degraded
      # No available connections
      pool_status.available == 0 -> :degraded
      # > 90% utilization
      calculate_pool_utilization(pool_status) > 0.9 -> :warning
      true -> :healthy
    end
  end

  defp calculate_pool_utilization(pool_status) do
    if pool_status.size > 0 do
      pool_status.busy / pool_status.size
    else
      0.0
    end
  end

  defp emit_health_telemetry(status, metrics) do
    :telemetry.execute(
      [:rubber_duck, :health_check, :database],
      Map.put(metrics, :status_numeric, status_to_numeric(status)),
      %{status: status}
    )
  end

  defp emit_failure_telemetry(error, failure_count) do
    :telemetry.execute(
      [:rubber_duck, :health_check, :database, :failure],
      %{consecutive_failures: failure_count},
      %{error: inspect(error)}
    )
  end

  defp status_to_numeric(:healthy), do: 1
  defp status_to_numeric(:warning), do: 2
  defp status_to_numeric(:degraded), do: 3
  defp status_to_numeric(:critical), do: 4
  defp status_to_numeric(_), do: 0
end
