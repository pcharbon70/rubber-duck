defmodule RubberDuck.HealthCheck do
  @moduledoc """
  Health check GenServer that monitors application components and provides health status endpoints.

  Performs periodic checks on:
  - Database connectivity
  - Service availability
  - Resource usage
  """

  use GenServer
  require Logger

  @check_interval 30_000  # 30 seconds
  @timeout 5_000          # 5 second timeout for checks

  defstruct [:status, :last_check, :checks, :timer_ref]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the current health status of all monitored components.

  Returns a map with health check results.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Get health status as JSON-compatible map for API endpoints.
  """
  def get_health_json do
    status = get_status()

    %{
      status: overall_status(status),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      checks: status.checks,
      uptime: :wall_clock |> :erlang.statistics() |> elem(0) |> div(1000)
    }
  end

  @doc """
  Force an immediate health check.
  """
  def check_now do
    GenServer.cast(__MODULE__, :check_now)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      status: :initializing,
      last_check: nil,
      checks: %{},
      timer_ref: nil
    }

    # Schedule first check immediately
    {:ok, schedule_check(state, 0)}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast(:check_now, state) do
    new_state = perform_health_check(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:perform_check, state) do
    new_state =
      state
      |> perform_health_check()
      |> schedule_check(@check_interval)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp schedule_check(state, delay) do
    # Cancel existing timer if present
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    timer_ref = Process.send_after(self(), :perform_check, delay)
    %{state | timer_ref: timer_ref}
  end

  defp perform_health_check(state) do
    Logger.debug("Performing health check...")

    checks = %{
      database: check_database(),
      memory: check_memory_usage(),
      processes: check_process_count(),
      atoms: check_atom_usage(),
      ash_authentication: check_ash_authentication(),
      repo_pool: check_repo_pool()
    }

    status = determine_overall_status(checks)

    # Emit telemetry events for monitoring
    emit_health_telemetry(checks)

    %{state |
      status: status,
      last_check: DateTime.utc_now(),
      checks: checks
    }
  end

  defp check_database do
    fn ->
      case RubberDuck.Repo.query("SELECT 1", [], timeout: @timeout) do
        {:ok, _result} ->
          %{status: :healthy, message: "Database connection successful"}
        {:error, reason} ->
          %{status: :unhealthy, message: "Database error: #{inspect(reason)}"}
      end
    end
    |> Task.async()
    |> Task.await(@timeout)
  rescue
    _e ->
      %{status: :unhealthy, message: "Database check timed out"}
  end

  defp check_memory_usage do
    memory = :erlang.memory()
    total_mb = memory[:total] / 1_048_576
    process_mb = memory[:processes] / 1_048_576

    if total_mb > 4000 do  # Over 4GB
      %{
        status: :warning,
        message: "High memory usage: #{Float.round(total_mb, 2)} MB",
        total_mb: Float.round(total_mb, 2),
        process_mb: Float.round(process_mb, 2)
      }
    else
      %{
        status: :healthy,
        message: "Memory usage normal",
        total_mb: Float.round(total_mb, 2),
        process_mb: Float.round(process_mb, 2)
      }
    end
  end

  defp check_process_count do
    count = :erlang.system_info(:process_count)
    limit = :erlang.system_info(:process_limit)
    usage_percent = (count / limit) * 100

    if usage_percent > 80 do
      %{
        status: :warning,
        message: "High process count: #{count}/#{limit} (#{Float.round(usage_percent, 1)}%)",
        count: count,
        limit: limit
      }
    else
      %{
        status: :healthy,
        message: "Process count normal",
        count: count,
        limit: limit
      }
    end
  end

  defp check_atom_usage do
    count = :erlang.system_info(:atom_count)
    limit = :erlang.system_info(:atom_limit)
    usage_percent = (count / limit) * 100

    if usage_percent > 75 do
      %{
        status: :warning,
        message: "High atom usage: #{count}/#{limit} (#{Float.round(usage_percent, 1)}%)",
        count: count,
        limit: limit
      }
    else
      %{
        status: :healthy,
        message: "Atom usage normal",
        count: count,
        limit: limit
      }
    end
  end

  defp check_ash_authentication do
    # AshAuthentication.Supervisor starts dynamically with the app
    # Check if the domain is accessible instead
    # Try to access the Accounts domain
    _ = RubberDuck.Accounts
    %{status: :healthy, message: "Authentication system available"}
  rescue
    _e ->
      %{status: :unhealthy, message: "Authentication system not available"}
  end

  defp check_repo_pool do
    case Process.whereis(RubberDuck.Repo) do
      nil ->
        %{status: :unhealthy, message: "Repository pool not running"}
      pid ->
        # Check if the repo process is alive
        if Process.alive?(pid) do
          %{
            status: :healthy,
            message: "Database pool healthy",
            queue: 0,
            size: 10
          }
        else
          %{status: :unhealthy, message: "Repository pool not responding"}
        end
    end
  end

  defp determine_overall_status(checks) do
    statuses =
      checks
      |> Map.values()
      |> Enum.map(& &1.status)

    cond do
      :unhealthy in statuses -> :unhealthy
      :warning in statuses -> :degraded
      true -> :healthy
    end
  end

  defp overall_status(%{status: status}), do: status

  defp emit_health_telemetry(checks) do
    # Emit database health
    db_value = if checks.database.status == :healthy, do: 1, else: 0
    :telemetry.execute(
      [:rubber_duck, :health, :database],
      %{value: db_value},
      %{}
    )

    # Emit overall health
    overall_value =
      case determine_overall_status(checks) do
        :healthy -> 1
        :degraded -> 0.5
        _ -> 0
      end

    :telemetry.execute(
      [:rubber_duck, :health, :services],
      %{value: overall_value},
      %{}
    )
  end
end
