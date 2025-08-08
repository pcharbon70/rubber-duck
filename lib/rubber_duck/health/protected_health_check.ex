defmodule RubberDuck.Health.ProtectedHealthCheck do
  @moduledoc """
  Enhanced health check system with circuit breaker protection.

  This module extends the basic HealthCheck with circuit breaker protection
  to prevent health check storms and cascading failures during outages.

  Features:
  - Circuit breaker per health check type
  - Cached results during circuit open state
  - Prioritized health checks
  - Graceful degradation
  - Configurable check intervals
  """

  use GenServer
  require Logger

  alias RubberDuck.Health.CircuitBreaker

  # 30 seconds default interval
  @default_check_interval 30_000
  # 5 second timeout for individual checks
  @default_timeout 5_000
  # Minimum interval during degraded state
  @degraded_check_interval 60_000

  defstruct [
    :status,
    :last_check,
    :checks,
    :timer_ref,
    :check_interval,
    :degraded_mode,
    :consecutive_failures,
    :config
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  @doc """
  Get the current health status with circuit breaker information.
  """
  def get_status(server \\ __MODULE__) do
    GenServer.call(server, :get_status)
  end

  @doc """
  Get health status as JSON-compatible map for API endpoints.
  Includes circuit breaker status for transparency.
  """
  def get_health_json(server \\ __MODULE__) do
    status = get_status(server)
    circuit_status = CircuitBreaker.get_status()

    %{
      status: overall_status(status),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      checks: status.checks,
      circuit_breakers: format_circuit_status(circuit_status),
      degraded_mode: status.degraded_mode,
      uptime: :wall_clock |> :erlang.statistics() |> elem(0) |> div(1000)
    }
  end

  @doc """
  Force an immediate health check (if circuits allow).
  """
  def check_now(server \\ __MODULE__) do
    GenServer.cast(server, :check_now)
  end

  @doc """
  Enable or disable degraded mode.
  In degraded mode, checks run less frequently and use more caching.
  """
  def set_degraded_mode(enabled, server \\ __MODULE__) do
    GenServer.call(server, {:set_degraded_mode, enabled})
  end

  @doc """
  Get circuit breaker status for all health checks.
  """
  def get_circuit_status do
    CircuitBreaker.get_status()
  end

  @doc """
  Reset specific health check circuit breaker.
  """
  def reset_circuit(check_type) do
    CircuitBreaker.reset(check_type)
  end

  @doc """
  Reset all health check circuit breakers.
  """
  def reset_all_circuits do
    CircuitBreaker.reset_all()
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config = build_config(opts)

    state = %__MODULE__{
      status: :initializing,
      last_check: nil,
      checks: %{},
      timer_ref: nil,
      check_interval: config.check_interval,
      degraded_mode: false,
      consecutive_failures: 0,
      config: config
    }

    # Schedule first check immediately
    {:ok, schedule_check(state, 0)}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    # Include circuit breaker information in status
    enhanced_state = enhance_with_circuit_info(state)
    {:reply, enhanced_state, state}
  end

  @impl true
  def handle_call({:set_degraded_mode, enabled}, _from, state) do
    Logger.info("Health check degraded mode #{if enabled, do: "enabled", else: "disabled"}")

    new_interval =
      if enabled do
        @degraded_check_interval
      else
        state.config.check_interval
      end

    new_state = %{state | degraded_mode: enabled, check_interval: new_interval}

    # Reschedule with new interval
    new_state = schedule_check(new_state, new_interval)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast(:check_now, state) do
    if state.degraded_mode do
      Logger.warning("Skipping immediate check in degraded mode")
      {:noreply, state}
    else
      new_state = perform_protected_health_check(state)
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:perform_check, state) do
    new_state =
      state
      |> perform_protected_health_check()
      |> adjust_check_interval()
      |> schedule_check(state.check_interval)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp build_config(opts) do
    %{
      check_interval: Keyword.get(opts, :check_interval, @default_check_interval),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      enable_circuit_breaker: Keyword.get(opts, :enable_circuit_breaker, true),
      priority_checks: Keyword.get(opts, :priority_checks, [:database, :repo_pool]),
      skip_on_degraded: Keyword.get(opts, :skip_on_degraded, [:external_service])
    }
  end

  defp schedule_check(state, delay) do
    # Cancel existing timer if present
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    timer_ref = Process.send_after(self(), :perform_check, delay)
    %{state | timer_ref: timer_ref}
  end

  defp perform_protected_health_check(state) do
    Logger.debug("Performing protected health check...")

    checks =
      if state.config.enable_circuit_breaker do
        perform_checks_with_circuit_breaker(state)
      else
        perform_checks_without_protection(state)
      end

    status = determine_overall_status(checks)

    # Track consecutive failures for auto-degradation
    new_consecutive_failures =
      if status == :unhealthy do
        state.consecutive_failures + 1
      else
        0
      end

    # Auto-enable degraded mode after multiple failures
    new_degraded_mode =
      if new_consecutive_failures >= 3 and not state.degraded_mode do
        Logger.warning(
          "Auto-enabling degraded mode after #{new_consecutive_failures} consecutive failures"
        )

        true
      else
        state.degraded_mode
      end

    # Emit telemetry events
    emit_health_telemetry(checks)

    %{
      state
      | status: status,
        last_check: DateTime.utc_now(),
        checks: checks,
        consecutive_failures: new_consecutive_failures,
        degraded_mode: new_degraded_mode
    }
  end

  defp perform_checks_with_circuit_breaker(state) do
    check_funs = build_check_functions(state)

    # Perform priority checks first
    priority_results = perform_priority_checks(check_funs, state.config.priority_checks)

    # Skip non-priority checks if in degraded mode
    other_results =
      if state.degraded_mode do
        skip_non_priority_checks(
          check_funs,
          state.config.priority_checks,
          state.config.skip_on_degraded
        )
      else
        perform_remaining_checks(check_funs, state.config.priority_checks)
      end

    Map.merge(priority_results, other_results)
  end

  defp perform_checks_without_protection(_state) do
    %{
      database: check_database(),
      memory: check_memory_usage(),
      processes: check_process_count(),
      atoms: check_atom_usage(),
      ash_authentication: check_ash_authentication(),
      repo_pool: check_repo_pool()
    }
  end

  defp build_check_functions(_state) do
    %{
      database: fn -> check_database() end,
      memory: fn -> check_memory_usage() end,
      processes: fn -> check_process_count() end,
      atoms: fn -> check_atom_usage() end,
      ash_authentication: fn -> check_ash_authentication() end,
      repo_pool: fn -> check_repo_pool() end
    }
  end

  defp perform_priority_checks(check_funs, priority_checks) do
    priority_checks
    |> Enum.map(fn check_type ->
      check_fun = Map.get(check_funs, check_type)

      if check_fun do
        {check_type, CircuitBreaker.check_with_breaker(check_type, check_fun)}
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp perform_remaining_checks(check_funs, priority_checks) do
    check_funs
    |> Enum.reject(fn {check_type, _} -> check_type in priority_checks end)
    |> Enum.map(fn {check_type, check_fun} ->
      {check_type, CircuitBreaker.check_with_breaker(check_type, check_fun)}
    end)
    |> Map.new()
  end

  defp skip_non_priority_checks(check_funs, priority_checks, skip_types) do
    check_funs
    |> Enum.reject(fn {check_type, _} -> check_type in priority_checks end)
    |> Enum.map(fn {check_type, _check_fun} ->
      if check_type in skip_types do
        {check_type, %{status: :skipped, message: "Skipped in degraded mode"}}
      else
        # Use cached result from circuit breaker
        {check_type, CircuitBreaker.get_cached_result(check_type, [])}
      end
    end)
    |> Map.new()
  end

  defp adjust_check_interval(state) do
    cond do
      # Many circuit breakers open - increase interval
      many_circuits_open?() ->
        # Max 5 minutes
        %{state | check_interval: min(state.check_interval * 2, 300_000)}

      # Everything healthy - return to normal interval
      state.status == :healthy and state.consecutive_failures == 0 ->
        %{state | check_interval: state.config.check_interval}

      # Otherwise keep current interval
      true ->
        state
    end
  end

  defp many_circuits_open? do
    circuit_status = CircuitBreaker.get_status()

    open_count =
      circuit_status
      |> Map.values()
      |> Enum.count(fn status ->
        Map.get(status, :state) in [:open, :half_open]
      end)

    open_count >= 2
  end

  defp enhance_with_circuit_info(state) do
    circuit_status = CircuitBreaker.get_status()

    enhanced_checks =
      state.checks
      |> Enum.map(fn {check_type, check_result} ->
        circuit_info = Map.get(circuit_status, check_type, %{})

        enhanced_result =
          Map.merge(check_result, %{
            circuit_state: Map.get(circuit_info, :state, :unknown),
            cached: Map.get(check_result, :cached, false)
          })

        {check_type, enhanced_result}
      end)
      |> Map.new()

    %{state | checks: enhanced_checks}
  end

  defp format_circuit_status(circuit_status) do
    circuit_status
    |> Enum.map(fn {check_type, status} ->
      {check_type,
       %{
         state: Map.get(status, :state, :unknown),
         error_count: Map.get(status, :error_count, 0),
         consecutive_failures: Map.get(status, :consecutive_failures, 0)
       }}
    end)
    |> Map.new()
  end

  # Health Check Functions (reused from original)

  defp check_database do
    case RubberDuck.Repo.query("SELECT 1", [], timeout: @default_timeout) do
      {:ok, _result} ->
        %{status: :healthy, message: "Database connection successful"}

      {:error, reason} ->
        %{status: :unhealthy, message: "Database error: #{inspect(reason)}"}
    end
  rescue
    _e ->
      %{status: :unhealthy, message: "Database check failed"}
  end

  defp check_memory_usage do
    memory = :erlang.memory()
    total_mb = memory[:total] / 1_048_576
    process_mb = memory[:processes] / 1_048_576

    if total_mb > 4000 do
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
    usage_percent = count / limit * 100

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
    usage_percent = count / limit * 100

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
      :skipped in statuses -> :degraded
      true -> :healthy
    end
  end

  defp overall_status(%{status: status}), do: status

  defp emit_health_telemetry(checks) do
    # Emit individual check results
    Enum.each(checks, fn {check_type, result} ->
      value =
        case result.status do
          :healthy -> 1
          :warning -> 0.5
          :skipped -> 0.5
          _ -> 0
        end

      :telemetry.execute(
        [:rubber_duck, :health, check_type],
        %{value: value},
        %{
          cached: Map.get(result, :cached, false),
          circuit_state: Map.get(result, :circuit_state, :unknown)
        }
      )
    end)

    # Emit overall health
    overall_value =
      case determine_overall_status(checks) do
        :healthy -> 1
        :degraded -> 0.5
        _ -> 0
      end

    :telemetry.execute(
      [:rubber_duck, :health, :overall],
      %{value: overall_value},
      %{}
    )
  end
end
