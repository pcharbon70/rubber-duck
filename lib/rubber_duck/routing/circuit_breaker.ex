defmodule RubberDuck.Routing.CircuitBreaker do
  @moduledoc """
  Circuit breaker implementation for message routing.

  Provides fault tolerance by monitoring failures and preventing
  cascading failures. Each message type gets its own circuit breaker
  instance to isolate failures.

  ## States

  - **Closed**: Normal operation, requests pass through
  - **Open**: Circuit tripped, requests fail fast
  - **Half-Open**: Testing recovery, limited requests allowed

  ## Configuration

      config :rubber_duck, :circuit_breaker,
        error_threshold: 5,      # Failures before opening
        timeout: 60_000,         # Time in open state (ms)
        half_open_requests: 3,   # Test requests in half-open
        success_threshold: 2     # Successes to close from half-open
  """

  use GenServer
  require Logger

  @default_config %{
    error_threshold: 5,
    timeout: 60_000,
    half_open_requests: 3,
    success_threshold: 2
  }

  defstruct [
    :message_type,
    :state,
    :config,
    :error_count,
    :success_count,
    :half_open_requests,
    :last_failure_time,
    :state_changed_at,
    :timer_ref
  ]

  # Client API

  @doc """
  Starts a circuit breaker for a specific message type.
  """
  def start_link(opts) do
    message_type = Keyword.fetch!(opts, :message_type)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(message_type))
  end

  @doc """
  Checks if the circuit allows a request to proceed.

  Returns:
  - `:ok` if the request can proceed
  - `{:error, :circuit_open}` if the circuit is open
  - `{:error, :circuit_half_open_limit}` if half-open limit reached
  """
  @spec call(module()) :: :ok | {:error, :circuit_open | :circuit_half_open_limit}
  def call(message_type) do
    GenServer.call(via_tuple(message_type), :call)
  catch
    :exit, {:noproc, _} ->
      # Circuit breaker doesn't exist yet, allow the request
      :ok
  end

  @doc """
  Records a successful request.
  """
  @spec record_success(module()) :: :ok
  def record_success(message_type) do
    GenServer.cast(via_tuple(message_type), :success)
  catch
    :exit, {:noproc, _} ->
      # Circuit breaker doesn't exist, ignore
      :ok
  end

  @doc """
  Records a failed request.
  """
  @spec record_failure(module()) :: :ok
  def record_failure(message_type) do
    GenServer.cast(via_tuple(message_type), :failure)
  catch
    :exit, {:noproc, _} ->
      # Circuit breaker doesn't exist, ignore
      :ok
  end

  @doc """
  Gets the current state of a circuit breaker.
  """
  @spec get_state(module()) :: {:ok, map()} | {:error, :not_found}
  def get_state(message_type) do
    GenServer.call(via_tuple(message_type), :get_state)
  catch
    :exit, {:noproc, _} ->
      {:error, :not_found}
  end

  @doc """
  Resets a circuit breaker to closed state.
  """
  @spec reset(module()) :: :ok
  def reset(message_type) do
    GenServer.call(via_tuple(message_type), :reset)
  catch
    :exit, {:noproc, _} ->
      :ok
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    message_type = Keyword.fetch!(opts, :message_type)
    config = get_config(opts)

    state = %__MODULE__{
      message_type: message_type,
      state: :closed,
      config: config,
      error_count: 0,
      success_count: 0,
      half_open_requests: 0,
      last_failure_time: nil,
      state_changed_at: System.monotonic_time(:millisecond),
      timer_ref: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:call, _from, %{state: :closed} = state) do
    # Circuit is closed, allow request
    {:reply, :ok, state}
  end

  def handle_call(:call, _from, %{state: :open} = state) do
    # Circuit is open, reject request
    {:reply, {:error, :circuit_open}, state}
  end

  def handle_call(:call, _from, %{state: :half_open} = state) do
    if state.half_open_requests < state.config.half_open_requests do
      # Allow limited requests in half-open state
      new_state = %{state | half_open_requests: state.half_open_requests + 1}
      {:reply, :ok, new_state}
    else
      # Half-open limit reached
      {:reply, {:error, :circuit_half_open_limit}, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    state_info = %{
      state: state.state,
      error_count: state.error_count,
      success_count: state.success_count,
      half_open_requests: state.half_open_requests,
      last_failure_time: state.last_failure_time,
      state_changed_at: state.state_changed_at
    }

    {:reply, {:ok, state_info}, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    new_state = reset_to_closed(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast(:success, %{state: :closed} = state) do
    # Success in closed state, reset error count
    {:noreply, %{state | error_count: 0}}
  end

  def handle_cast(:success, %{state: :open} = state) do
    # Success in open state shouldn't happen, ignore
    {:noreply, state}
  end

  def handle_cast(:success, %{state: :half_open} = state) do
    new_success_count = state.success_count + 1

    if new_success_count >= state.config.success_threshold do
      # Enough successes, close the circuit
      new_state = transition_to_closed(state)
      {:noreply, new_state}
    else
      # Track success but stay in half-open
      {:noreply, %{state | success_count: new_success_count}}
    end
  end

  @impl true
  def handle_cast(:failure, %{state: :closed} = state) do
    new_error_count = state.error_count + 1
    now = System.monotonic_time(:millisecond)

    if new_error_count >= state.config.error_threshold do
      # Threshold reached, open the circuit
      new_state = transition_to_open(state, now)
      {:noreply, new_state}
    else
      # Track failure but stay closed
      {:noreply, %{state | error_count: new_error_count, last_failure_time: now}}
    end
  end

  def handle_cast(:failure, %{state: :open} = state) do
    # Already open, update last failure time
    {:noreply, %{state | last_failure_time: System.monotonic_time(:millisecond)}}
  end

  def handle_cast(:failure, %{state: :half_open} = state) do
    # Failure in half-open, immediately go back to open
    new_state = transition_to_open(state, System.monotonic_time(:millisecond))
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:timeout_expired, %{state: :open} = state) do
    # Timeout expired, transition to half-open
    new_state = transition_to_half_open(state)
    {:noreply, new_state}
  end

  def handle_info(:timeout_expired, state) do
    # Timeout in non-open state, ignore
    {:noreply, state}
  end

  # Private Functions

  defp via_tuple(message_type) do
    {:via, Registry, {RubberDuck.CircuitBreakerRegistry, message_type}}
  end

  defp get_config(opts) do
    app_config = Application.get_env(:rubber_duck, :circuit_breaker, %{})
    custom_config = Keyword.get(opts, :config, %{})

    @default_config
    |> Map.merge(app_config)
    |> Map.merge(custom_config)
  end

  defp transition_to_open(state, now) do
    cancel_timer(state.timer_ref)

    # Schedule transition to half-open
    timer_ref = Process.send_after(self(), :timeout_expired, state.config.timeout)

    # Emit telemetry
    emit_state_change(state.message_type, :opened, %{
      error_count: state.error_count,
      threshold: state.config.error_threshold
    })

    Logger.warning("Circuit breaker opened for #{inspect(state.message_type)}")

    %{state | state: :open, state_changed_at: now, timer_ref: timer_ref, last_failure_time: now}
  end

  defp transition_to_half_open(state) do
    cancel_timer(state.timer_ref)

    # Emit telemetry
    emit_state_change(state.message_type, :half_open, %{
      open_duration_ms: System.monotonic_time(:millisecond) - state.state_changed_at
    })

    Logger.info("Circuit breaker half-open for #{inspect(state.message_type)}")

    %{
      state
      | state: :half_open,
        state_changed_at: System.monotonic_time(:millisecond),
        timer_ref: nil,
        success_count: 0,
        half_open_requests: 0
    }
  end

  defp transition_to_closed(state) do
    cancel_timer(state.timer_ref)

    # Emit telemetry
    emit_state_change(state.message_type, :closed, %{
      recovery_time_ms: System.monotonic_time(:millisecond) - state.state_changed_at
    })

    Logger.info("Circuit breaker closed for #{inspect(state.message_type)}")

    reset_to_closed(state)
  end

  defp reset_to_closed(state) do
    cancel_timer(state.timer_ref)

    %{
      state
      | state: :closed,
        state_changed_at: System.monotonic_time(:millisecond),
        timer_ref: nil,
        error_count: 0,
        success_count: 0,
        half_open_requests: 0
    }
  end

  defp cancel_timer(nil), do: :ok

  defp cancel_timer(ref) do
    Process.cancel_timer(ref)
    :ok
  end

  defp emit_state_change(message_type, event, metadata) do
    :telemetry.execute(
      [:rubber_duck, :circuit_breaker, event],
      %{system_time: System.system_time()},
      Map.merge(metadata, %{message_type: message_type})
    )
  end
end
