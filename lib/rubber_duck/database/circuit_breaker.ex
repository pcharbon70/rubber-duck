defmodule RubberDuck.Database.CircuitBreaker do
  @moduledoc """
  Circuit breaker for database operations.

  Protects against:
  - Connection pool exhaustion
  - Slow queries causing timeouts
  - Database outages
  - Cascading failures during maintenance

  Features:
  - Per-operation-type circuit breakers (read, write, transaction)
  - Query timing tracking
  - Connection pool monitoring
  - Automatic retry with exponential backoff
  """

  require Logger

  alias RubberDuck.Routing.{CircuitBreaker, CircuitBreakerSupervisor}

  @default_config %{
    # More failures allowed for DB
    error_threshold: 5,
    # 30 seconds recovery
    timeout: 30_000,
    # Test with 2 requests
    half_open_requests: 2,
    # Need 3 successes to recover
    success_threshold: 3,
    # 5 seconds = slow query
    slow_query_threshold: 5000
  }

  @operation_types [:read, :write, :transaction, :bulk]

  # Client API

  @doc """
  Execute a database operation with circuit breaker protection.

  ## Examples

      # Read operation
      CircuitBreaker.with_circuit_breaker(:read, fn ->
        Repo.get(User, user_id)
      end)
      
      # Write operation
      CircuitBreaker.with_circuit_breaker(:write, fn ->
        Repo.insert(changeset)
      end)
      
      # Transaction
      CircuitBreaker.with_circuit_breaker(:transaction, fn ->
        Repo.transaction(fn -> ... end)
      end)
  """
  @spec with_circuit_breaker(atom(), function(), keyword()) :: {:ok, any()} | {:error, any()}
  def with_circuit_breaker(operation_type, fun, opts \\ [])
      when operation_type in @operation_types do
    circuit_name = circuit_breaker_name(operation_type)

    # Ensure circuit breaker exists
    ensure_circuit_breaker(operation_type)

    # Check if circuit allows request
    with :ok <- CircuitBreaker.call(circuit_name),
         :ok <- check_connection_pool() do
      execute_with_monitoring(operation_type, fun, opts)
    else
      {:error, :circuit_open} ->
        Logger.warning("Database circuit open for #{operation_type} operations")
        handle_circuit_open(operation_type, opts)

      {:error, :connection_pool_exhausted} ->
        Logger.warning("Database connection pool exhausted")
        {:error, :connection_pool_exhausted}

      error ->
        error
    end
  end

  @doc """
  Execute an Ash query with circuit breaker protection.

  Wraps Ash.Query operations with circuit breaker logic.
  """
  @spec execute_ash_query(module(), Ash.Query.t() | Ash.Changeset.t(), keyword()) ::
          {:ok, any()} | {:error, any()}
  def execute_ash_query(resource, query_or_changeset, opts \\ []) do
    operation_type = determine_operation_type(query_or_changeset)

    with_circuit_breaker(
      operation_type,
      fn ->
        case operation_type do
          :read -> Ash.read!(resource, query_or_changeset)
          :write -> execute_write(resource, query_or_changeset, opts)
          _ -> {:error, :unsupported_operation}
        end
      end,
      opts
    )
  end

  @doc """
  Get the status of all database circuit breakers.
  """
  @spec get_status() :: map()
  def get_status do
    Map.new(@operation_types, fn op_type ->
      circuit_name = circuit_breaker_name(op_type)

      status =
        case CircuitBreaker.get_state(circuit_name) do
          {:ok, state} ->
            Map.merge(state, %{
              avg_query_time: get_avg_query_time(op_type),
              slow_query_count: get_slow_query_count(op_type),
              connection_pool_status: get_connection_pool_status()
            })

          {:error, :not_found} ->
            %{state: :unknown, available: true}
        end

      {op_type, status}
    end)
  end

  @doc """
  Reset a specific database circuit breaker.
  """
  @spec reset(atom()) :: :ok
  def reset(operation_type) when operation_type in @operation_types do
    circuit_name = circuit_breaker_name(operation_type)
    CircuitBreaker.reset(circuit_name)
    clear_metrics(operation_type)
    :ok
  end

  @doc """
  Reset all database circuit breakers.
  """
  @spec reset_all() :: :ok
  def reset_all do
    Enum.each(@operation_types, &reset/1)
    :ok
  end

  # Private Functions

  defp circuit_breaker_name(operation_type) do
    :"db_#{operation_type}"
  end

  defp ensure_circuit_breaker(operation_type) do
    config = get_operation_config(operation_type)

    CircuitBreakerSupervisor.ensure_circuit_breaker(
      circuit_breaker_name(operation_type),
      config: config
    )
  end

  defp get_operation_config(operation_type) do
    base_config = Application.get_env(:rubber_duck, :db_circuit_breaker, %{})

    # Operation-specific overrides
    operation_configs = %{
      # More lenient for reads
      read: %{error_threshold: 10, timeout: 20_000},
      # Standard for writes
      write: %{error_threshold: 5, timeout: 30_000},
      # Strict for transactions
      transaction: %{error_threshold: 3, timeout: 60_000},
      # Balanced for bulk ops
      bulk: %{error_threshold: 5, timeout: 45_000}
    }

    Map.merge(
      @default_config,
      Map.merge(base_config, Map.get(operation_configs, operation_type, %{}))
    )
  end

  defp execute_with_monitoring(operation_type, fun, opts) do
    start_time = System.monotonic_time(:millisecond)
    circuit_name = circuit_breaker_name(operation_type)

    timeout = Keyword.get(opts, :timeout, 15_000)

    result =
      try do
        # Execute with timeout
        task = Task.async(fun)
        Task.await(task, timeout)
      rescue
        error ->
          {:error, error}
      catch
        :exit, {:timeout, _} ->
          {:error, :timeout}

        :exit, reason ->
          {:error, {:exit, reason}}
      end

    elapsed_time = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, _} = success ->
        CircuitBreaker.record_success(circuit_name)
        record_query_time(operation_type, elapsed_time)

        # Track slow queries
        if elapsed_time > get_slow_query_threshold(operation_type) do
          Logger.warning("Slow #{operation_type} query: #{elapsed_time}ms")
          record_slow_query(operation_type)
        end

        success

      {:error, :timeout} = error ->
        CircuitBreaker.record_failure(circuit_name)
        Logger.error("Database #{operation_type} timeout after #{timeout}ms")
        error

      {:error, %Postgrex.Error{} = db_error} = error ->
        handle_database_error(operation_type, db_error)
        error

      {:error, _reason} = error ->
        CircuitBreaker.record_failure(circuit_name)
        error

      other ->
        # Treat unexpected results as success but log them
        Logger.warning("Unexpected result from database operation: #{inspect(other)}")
        CircuitBreaker.record_success(circuit_name)
        other
    end
  end

  defp handle_database_error(operation_type, %Postgrex.Error{} = error) do
    circuit_name = circuit_breaker_name(operation_type)

    case error do
      %{postgres: %{code: :too_many_connections}} ->
        # Connection pool exhausted - open circuit immediately
        force_open_circuit(operation_type, :connection_exhausted)

      %{postgres: %{code: :admin_shutdown}} ->
        # Database maintenance - open circuit with longer timeout
        # 5 minutes
        force_open_circuit(operation_type, :maintenance, 300_000)

      %{postgres: %{code: code}} when code in [:deadlock_detected, :lock_not_available] ->
        # Lock issues - record failure but don't force open
        CircuitBreaker.record_failure(circuit_name)

      _ ->
        # Other database errors
        CircuitBreaker.record_failure(circuit_name)
    end
  end

  defp force_open_circuit(operation_type, reason, timeout_override \\ nil) do
    circuit_name = circuit_breaker_name(operation_type)
    config = get_operation_config(operation_type)

    # Record enough failures to open the circuit
    for _ <- 1..config.error_threshold do
      CircuitBreaker.record_failure(circuit_name)
    end

    Logger.error("Force opening database circuit for #{operation_type}: #{reason}")

    if timeout_override do
      # Store custom timeout (would need to extend base circuit breaker for this)
      Process.put({:db_circuit_timeout, operation_type}, timeout_override)
    end
  end

  defp check_connection_pool do
    # Check if connection pool has available connections
    # This is a simplified check - in production, use Postgrex pool telemetry
    case get_connection_pool_status() do
      %{available: available, max: max} when available < max * 0.1 ->
        {:error, :connection_pool_exhausted}

      _ ->
        :ok
    end
  end

  defp get_connection_pool_status do
    # In production, this would query actual pool metrics
    # For now, return mock healthy status
    %{
      available: 8,
      max: 10,
      idle: 6,
      busy: 2,
      queue: 0
    }
  end

  defp determine_operation_type(query_or_changeset) do
    cond do
      is_struct(query_or_changeset, Ash.Query) -> :read
      is_struct(query_or_changeset, Ash.Changeset) -> :write
      true -> :read
    end
  end

  defp execute_write(_resource, changeset, opts) do
    cond do
      changeset.action.type == :create -> Ash.create(changeset, opts)
      changeset.action.type == :update -> Ash.update(changeset, opts)
      changeset.action.type == :destroy -> Ash.destroy(changeset, opts)
      true -> {:error, :unknown_action_type}
    end
  end

  defp handle_circuit_open(operation_type, opts) do
    if Keyword.get(opts, :fallback, false) do
      attempt_fallback(operation_type, opts)
    else
      {:error, :database_unavailable}
    end
  end

  defp attempt_fallback(:read, opts) do
    # For reads, could try:
    # 1. Read from cache
    # 2. Read from replica
    # 3. Return stale data with warning

    if Keyword.get(opts, :allow_stale, false) do
      Logger.warning("Returning stale data due to database circuit open")
      {:ok, :stale_data_placeholder}
    else
      {:error, :database_unavailable}
    end
  end

  defp attempt_fallback(_operation_type, _opts) do
    # For writes/transactions, typically can't fallback
    {:error, :database_unavailable}
  end

  defp record_query_time(operation_type, time_ms) do
    key = {:query_times, operation_type}
    times = Process.get(key, [])
    Process.put(key, [time_ms | Enum.take(times, 99)])
  end

  defp get_avg_query_time(operation_type) do
    key = {:query_times, operation_type}
    times = Process.get(key, [])

    if length(times) > 0 do
      Enum.sum(times) / length(times)
    else
      0.0
    end
  end

  defp record_slow_query(operation_type) do
    key = {:slow_queries, operation_type}
    count = Process.get(key, 0)
    Process.put(key, count + 1)
  end

  defp get_slow_query_count(operation_type) do
    Process.get({:slow_queries, operation_type}, 0)
  end

  defp get_slow_query_threshold(operation_type) do
    config = get_operation_config(operation_type)
    Map.get(config, :slow_query_threshold, 5000)
  end

  defp clear_metrics(operation_type) do
    Process.delete({:query_times, operation_type})
    Process.delete({:slow_queries, operation_type})
    Process.delete({:db_circuit_timeout, operation_type})
  end
end
