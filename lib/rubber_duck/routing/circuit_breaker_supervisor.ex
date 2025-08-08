defmodule RubberDuck.Routing.CircuitBreakerSupervisor do
  @moduledoc """
  Supervisor for circuit breaker instances.

  Manages individual circuit breakers for each message type,
  creating them on demand and supervising their lifecycle.
  """

  use DynamicSupervisor

  @doc """
  Starts the circuit breaker supervisor.
  """
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Ensures a circuit breaker exists for the given message type.

  Creates one if it doesn't exist, or returns :ok if it already does.
  """
  @spec ensure_circuit_breaker(module(), keyword()) :: :ok | {:error, term()}
  def ensure_circuit_breaker(message_type, opts \\ []) do
    case start_circuit_breaker(message_type, opts) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      error -> error
    end
  end

  @doc """
  Starts a circuit breaker for a specific message type.
  """
  @spec start_circuit_breaker(module(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_circuit_breaker(message_type, opts \\ []) do
    child_spec = %{
      id: {RubberDuck.Routing.CircuitBreaker, message_type},
      start:
        {RubberDuck.Routing.CircuitBreaker, :start_link, [[message_type: message_type] ++ opts]},
      restart: :permanent
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Stops a circuit breaker for a specific message type.
  """
  @spec stop_circuit_breaker(module()) :: :ok | {:error, :not_found}
  def stop_circuit_breaker(message_type) do
    case Registry.lookup(RubberDuck.CircuitBreakerRegistry, message_type) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all active circuit breakers.
  """
  @spec list_circuit_breakers() :: [module()]
  def list_circuit_breakers do
    Registry.select(RubberDuck.CircuitBreakerRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @doc """
  Gets statistics for all circuit breakers.
  """
  @spec get_all_stats() :: %{module() => map()}
  def get_all_stats do
    list_circuit_breakers()
    |> Enum.map(fn message_type ->
      case RubberDuck.Routing.CircuitBreaker.get_state(message_type) do
        {:ok, state} -> {message_type, state}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
