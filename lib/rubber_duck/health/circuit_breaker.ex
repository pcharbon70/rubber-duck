defmodule RubberDuck.Health.CircuitBreaker do
  @moduledoc """
  Circuit breaker for health check operations.

  Prevents health check storms during outages and protects against:
  - Cascading health check failures
  - Resource exhaustion from repeated failing checks
  - Thundering herd during recovery
  - External service check overload

  Features:
  - Per-check-type circuit breakers
  - Cached results during circuit open state
  - Gradual recovery with exponential backoff
  - Priority-based health checks
  """

  require Logger

  alias RubberDuck.Routing.{CircuitBreaker, CircuitBreakerSupervisor}

  @default_config %{
    # Fewer failures for health checks
    error_threshold: 3,
    # 1 minute recovery
    timeout: 60_000,
    # Single test request
    half_open_requests: 1,
    # Need 2 successes to recover
    success_threshold: 2,
    # Cache results for 30 seconds
    cache_duration: 30_000
  }

  @check_types [
    :database,
    :memory,
    :processes,
    :atoms,
    :ash_authentication,
    :repo_pool,
    :external_service
  ]

  # Client API

  @doc """
  Execute a health check with circuit breaker protection.

  Returns cached results when circuit is open to prevent repeated failures.

  ## Examples

      # Database health check
      CircuitBreaker.check_with_breaker(:database, fn ->
        check_database_health()
      end)
      
      # External service check with custom timeout
      CircuitBreaker.check_with_breaker(:external_service, fn ->
        check_external_api()
      end, timeout: 10_000)
  """
  @spec check_with_breaker(atom(), function(), keyword()) :: map()
  def check_with_breaker(check_type, check_fun, opts \\ []) when check_type in @check_types do
    circuit_name = circuit_breaker_name(check_type)

    # Ensure circuit breaker exists
    ensure_circuit_breaker(check_type)

    # Check if circuit allows request
    case CircuitBreaker.call(circuit_name) do
      :ok ->
        execute_health_check(check_type, check_fun, opts)

      {:error, :circuit_open} ->
        Logger.warning("Health check circuit open for #{check_type}, returning cached result")
        do_get_cached_result(check_type, opts)

      {:error, :circuit_half_open_limit} ->
        Logger.debug("Health check circuit half-open limit reached for #{check_type}")
        do_get_cached_result(check_type, opts)
    end
  end

  @doc """
  Perform multiple health checks with circuit breaker protection.

  Executes checks in parallel where possible, respecting circuit states.
  """
  @spec check_multiple(list({atom(), function()}), keyword()) :: map()
  def check_multiple(checks, opts \\ []) do
    checks
    |> Enum.map(fn {check_type, check_fun} ->
      task =
        Task.async(fn ->
          {check_type, check_with_breaker(check_type, check_fun, opts)}
        end)

      {check_type, task}
    end)
    |> Enum.map(fn {check_type, task} ->
      case Task.yield(task, 5000) || Task.shutdown(task) do
        {:ok, {^check_type, result}} ->
          {check_type, result}

        _ ->
          {check_type, %{status: :unknown, message: "Check timed out"}}
      end
    end)
    |> Map.new()
  end

  @doc """
  Get the circuit breaker status for all health check types.
  """
  @spec get_status() :: map()
  def get_status do
    Map.new(@check_types, fn check_type ->
      circuit_name = circuit_breaker_name(check_type)

      status =
        case CircuitBreaker.get_state(circuit_name) do
          {:ok, state} ->
            Map.merge(state, %{
              cached_result: do_get_cached_result(check_type, []),
              last_check_time: get_last_check_time(check_type),
              consecutive_failures: get_consecutive_failures(check_type)
            })

          {:error, :not_found} ->
            %{state: :unknown, available: true}
        end

      {check_type, status}
    end)
  end

  @doc """
  Reset a specific health check circuit breaker.
  """
  @spec reset(atom()) :: :ok
  def reset(check_type) when check_type in @check_types do
    circuit_name = circuit_breaker_name(check_type)
    CircuitBreaker.reset(circuit_name)
    clear_cache(check_type)
    :ok
  end

  @doc """
  Reset all health check circuit breakers.
  """
  @spec reset_all() :: :ok
  def reset_all do
    Enum.each(@check_types, &reset/1)
    :ok
  end

  @doc """
  Force a specific health check to fail (for testing).
  """
  @spec force_failure(atom(), pos_integer()) :: :ok
  def force_failure(check_type, count \\ 3) when check_type in @check_types do
    circuit_name = circuit_breaker_name(check_type)
    ensure_circuit_breaker(check_type)

    for _ <- 1..count do
      CircuitBreaker.record_failure(circuit_name)
    end

    cache_result(check_type, %{
      status: :unhealthy,
      message: "Circuit breaker forced open",
      circuit_open: true
    })

    :ok
  end

  @doc """
  Check if a health check circuit is currently open.
  """
  @spec circuit_open?(atom()) :: boolean()
  def circuit_open?(check_type) when check_type in @check_types do
    circuit_name = circuit_breaker_name(check_type)

    case CircuitBreaker.get_state(circuit_name) do
      {:ok, %{state: :open}} -> true
      {:ok, %{state: :half_open}} -> true
      _ -> false
    end
  end

  # Private Functions

  defp circuit_breaker_name(check_type) do
    :"health_#{check_type}"
  end

  defp ensure_circuit_breaker(check_type) do
    config = get_check_config(check_type)

    CircuitBreakerSupervisor.ensure_circuit_breaker(
      circuit_breaker_name(check_type),
      config: config
    )
  end

  defp get_check_config(check_type) do
    base_config = Application.get_env(:rubber_duck, :health_circuit_breaker, %{})

    # Check-specific overrides
    check_configs = %{
      # Critical, strict
      database: %{error_threshold: 2, timeout: 120_000},
      # System resource, lenient
      memory: %{error_threshold: 10, timeout: 30_000},
      # System resource, lenient
      processes: %{error_threshold: 10, timeout: 30_000},
      # System resource, lenient
      atoms: %{error_threshold: 10, timeout: 30_000},
      # Service, moderate
      ash_authentication: %{error_threshold: 3, timeout: 60_000},
      # Critical, strict
      repo_pool: %{error_threshold: 2, timeout: 120_000},
      # External, moderate
      external_service: %{error_threshold: 5, timeout: 90_000}
    }

    Map.merge(
      @default_config,
      Map.merge(base_config, Map.get(check_configs, check_type, %{}))
    )
  end

  defp execute_health_check(check_type, check_fun, opts) do
    start_time = System.monotonic_time(:millisecond)
    circuit_name = circuit_breaker_name(check_type)

    timeout = Keyword.get(opts, :timeout, 5_000)

    result =
      try do
        # Execute with timeout
        task = Task.async(check_fun)

        case Task.yield(task, timeout) || Task.shutdown(task) do
          {:ok, check_result} -> check_result
          nil -> %{status: :unhealthy, message: "Health check timed out"}
        end
      rescue
        error ->
          %{status: :unhealthy, message: "Check failed: #{inspect(error)}"}
      catch
        :exit, {:timeout, _} ->
          %{status: :unhealthy, message: "Health check timed out"}

        :exit, reason ->
          %{status: :unhealthy, message: "Check exited: #{inspect(reason)}"}
      end

    elapsed_time = System.monotonic_time(:millisecond) - start_time

    # Add timing information
    result = Map.put(result, :check_time_ms, elapsed_time)

    # Record success or failure with circuit breaker
    case result.status do
      :healthy ->
        CircuitBreaker.record_success(circuit_name)
        cache_result(check_type, result)
        clear_consecutive_failures(check_type)

      :warning ->
        # Warnings don't affect circuit breaker
        cache_result(check_type, result)

      :unhealthy ->
        CircuitBreaker.record_failure(circuit_name)
        cache_result(check_type, result)
        increment_consecutive_failures(check_type)

      _ ->
        # Unknown status, treat as warning
        cache_result(check_type, result)
    end

    # Record check time
    record_check_time(check_type)

    result
  end

  @doc false
  def get_cached_result(check_type, opts \\ []) do
    do_get_cached_result(check_type, opts)
  end

  defp cache_result(check_type, result) do
    key = {:health_cache, check_type}
    timestamp = DateTime.utc_now()
    Process.put(key, {result, timestamp})
    result
  end

  defp do_get_cached_result(check_type, opts) do
    key = {:health_cache, check_type}
    cache_duration = Keyword.get(opts, :cache_duration, @default_config.cache_duration)

    case Process.get(key) do
      {result, timestamp} ->
        age_ms = DateTime.diff(DateTime.utc_now(), timestamp, :millisecond)

        if age_ms <= cache_duration do
          Map.merge(result, %{
            cached: true,
            cache_age_ms: age_ms,
            circuit_open: true
          })
        else
          # Cache expired, return degraded status
          %{
            status: :unknown,
            message: "Circuit open, cache expired",
            cached: true,
            circuit_open: true
          }
        end

      nil ->
        # No cache available
        %{
          status: :unknown,
          message: "Circuit open, no cached result",
          circuit_open: true
        }
    end
  end

  defp clear_cache(check_type) do
    Process.delete({:health_cache, check_type})
    Process.delete({:last_check_time, check_type})
    Process.delete({:consecutive_failures, check_type})
  end

  defp record_check_time(check_type) do
    Process.put({:last_check_time, check_type}, DateTime.utc_now())
  end

  defp get_last_check_time(check_type) do
    Process.get({:last_check_time, check_type})
  end

  defp increment_consecutive_failures(check_type) do
    key = {:consecutive_failures, check_type}
    current = Process.get(key, 0)
    Process.put(key, current + 1)
  end

  defp clear_consecutive_failures(check_type) do
    Process.delete({:consecutive_failures, check_type})
  end

  defp get_consecutive_failures(check_type) do
    Process.get({:consecutive_failures, check_type}, 0)
  end
end
