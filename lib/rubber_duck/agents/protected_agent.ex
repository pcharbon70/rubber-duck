defmodule RubberDuck.Agents.ProtectedAgent do
  @moduledoc """
  Base behavior for circuit breaker protected agents.

  This module extends RubberDuck.Agents.Base to add automatic circuit breaker
  protection for all inter-agent communication. Agents using this base will
  have resilience against communication failures, timeouts, and cascading failures.

  ## Usage

      defmodule MyApp.MyAgent do
        use RubberDuck.Agents.ProtectedAgent,
          name: "my_agent",
          description: "A protected agent",
          circuit_breaker: [
            error_threshold: 5,
            timeout: 30_000
          ]
      end

  ## Features

  - Automatic circuit breaker protection for all instructions
  - Dead letter queue for failed messages
  - Fallback agent support
  - Response time tracking
  - Graceful degradation during failures
  """

  alias RubberDuck.Agents.CircuitBreaker, as: AgentCircuitBreaker
  require Logger

  defmacro __using__(opts) do
    quote location: :keep do
      # Use the base agent functionality
      use RubberDuck.Agents.Base, unquote(opts)

      # Import circuit breaker functionality
      import RubberDuck.Agents.ProtectedAgent

      # Store circuit breaker config
      @circuit_breaker_config Keyword.get(unquote(opts), :circuit_breaker, %{})

      # Override handle_instruction to add circuit breaker protection
      def handle_protected_instruction(instruction, agent) do
        # Call the original handle_instruction
        handle_instruction(instruction, agent)
      end

      # Wrap send_to_agent with circuit breaker
      def send_to_agent(target_agent, instruction, opts \\ []) do
        AgentCircuitBreaker.send_instruction(target_agent, instruction, opts)
      end

      # Broadcast to multiple agents with protection
      def broadcast_to_agents(target_agents, instruction, opts \\ []) do
        AgentCircuitBreaker.broadcast_to_agents(target_agents, instruction, opts)
      end

      # Check if communication with an agent is available
      def can_communicate_with?(agent_type) do
        not AgentCircuitBreaker.circuit_open?(agent_type)
      end

      # Get communication health status
      def communication_health do
        AgentCircuitBreaker.get_status()
      end

      # Retry failed messages from dead letter queue
      def retry_failed_messages(agent_type, opts \\ []) do
        AgentCircuitBreaker.retry_dead_letters(agent_type, opts)
      end

      # Get failed messages for an agent
      def get_failed_messages(agent_type) do
        AgentCircuitBreaker.get_dead_letter_queue(agent_type)
      end

      # Reset communication circuit for an agent
      def reset_communication(agent_type) do
        AgentCircuitBreaker.reset(agent_type)
      end

      # Add telemetry for circuit breaker events
      def emit_circuit_event(event, metadata) do
        :telemetry.execute(
          [:rubber_duck, :agent, :circuit_breaker, event],
          %{count: 1},
          metadata
        )
      end

      # Callback for when circuit opens
      def on_circuit_open(agent_type, reason) do
        Logger.warning("Circuit opened for agent #{agent_type}: #{inspect(reason)}")
        emit_circuit_event(:circuit_opened, %{agent: agent_type, reason: reason})

        # Default behavior - can be overridden
        {:ok, :circuit_opened}
      end

      # Callback for when circuit closes
      def on_circuit_closed(agent_type) do
        Logger.info("Circuit closed for agent #{agent_type}")
        emit_circuit_event(:circuit_closed, %{agent: agent_type})

        # Default behavior - can be overridden
        {:ok, :circuit_closed}
      end

      # Enhanced initialization with circuit breaker setup
      def init(opts) do
        # Call parent init
        result = super(opts)

        # Setup circuit breaker monitoring
        schedule_circuit_health_check()

        result
      end

      # Periodic health check of communication circuits
      defp schedule_circuit_health_check do
        # Every minute
        Process.send_after(self(), :check_circuit_health, 60_000)
      end

      def handle_info(:check_circuit_health, agent) do
        health = communication_health()

        # Check for degraded communication
        degraded_agents =
          health
          |> Enum.filter(fn {_agent, status} ->
            Map.get(status, :state) in [:open, :half_open]
          end)
          |> Enum.map(fn {agent, _} -> agent end)

        if length(degraded_agents) > 0 do
          Logger.warning("Degraded communication with agents: #{inspect(degraded_agents)}")

          # Update agent state to track degraded communication
          updated_state = Map.put(agent.state, :degraded_communications, degraded_agents)
          agent = %{agent | state: updated_state}
        end

        # Schedule next check
        schedule_circuit_health_check()

        {:noreply, agent}
      end

      # Allow functions to be overridden
      defoverridable handle_protected_instruction: 2,
                     on_circuit_open: 2,
                     on_circuit_closed: 1
    end
  end

  @doc """
  Send instruction with automatic retries and circuit breaker protection.

  Options:
  - `:retries` - Number of retry attempts (default: 3)
  - `:retry_delay` - Delay between retries in ms (default: 1000)
  - `:fallback` - Fallback agent to use on failure
  - `:timeout` - Timeout for the instruction (default: 10000)
  """
  def send_with_retry(agent_type, instruction, opts \\ []) do
    retries = Keyword.get(opts, :retries, 3)
    retry_delay = Keyword.get(opts, :retry_delay, 1000)

    do_send_with_retry(agent_type, instruction, opts, retries, retry_delay)
  end

  defp do_send_with_retry(agent_type, instruction, opts, retries_left, retry_delay) do
    case AgentCircuitBreaker.send_instruction(agent_type, instruction, opts) do
      {:ok, result} ->
        {:ok, result}

      {:error, _reason} when retries_left > 0 ->
        Logger.debug("Retrying instruction to #{agent_type}, #{retries_left} attempts left")
        Process.sleep(retry_delay)

        # Exponential backoff
        new_delay = min(retry_delay * 2, 30_000)
        do_send_with_retry(agent_type, instruction, opts, retries_left - 1, new_delay)

      error ->
        error
    end
  end

  @doc """
  Execute a chain of agent instructions with circuit breaker protection.

  Each step in the chain receives the result of the previous step.
  If any step fails, the chain is broken and an error is returned.
  """
  def execute_chain(chain, initial_input \\ nil) do
    Enum.reduce_while(chain, {:ok, initial_input}, fn
      {agent_type, instruction_fn}, {:ok, prev_result} ->
        instruction =
          if is_function(instruction_fn) do
            instruction_fn.(prev_result)
          else
            instruction_fn
          end

        case AgentCircuitBreaker.send_instruction(agent_type, instruction) do
          {:ok, result} -> {:cont, {:ok, result}}
          error -> {:halt, error}
        end

      _, error ->
        {:halt, error}
    end)
  end

  @doc """
  Execute parallel agent instructions and collect results.

  Returns a map of agent_type => result.
  Failed agents will have {:error, reason} as their result.
  """
  def execute_parallel(instructions, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 10_000)

    instructions
    |> Enum.map(fn {agent_type, instruction} ->
      task =
        Task.async(fn ->
          AgentCircuitBreaker.send_instruction(agent_type, instruction, opts)
        end)

      {agent_type, task}
    end)
    |> Enum.map(fn {agent_type, task} ->
      result =
        case Task.yield(task, timeout) || Task.shutdown(task) do
          {:ok, response} -> response
          nil -> {:error, :timeout}
        end

      {agent_type, result}
    end)
    |> Map.new()
  end

  @doc """
  Monitor agent communication health and emit warnings.
  """
  def monitor_communication_health do
    health = AgentCircuitBreaker.get_status()

    unhealthy =
      health
      |> Enum.filter(fn {_agent, status} ->
        Map.get(status, :state) == :open ||
          Map.get(status, :error_count, 0) > 3
      end)

    if length(unhealthy) > 0 do
      Logger.warning("Unhealthy agent communication detected: #{inspect(unhealthy)}")

      # Emit telemetry
      :telemetry.execute(
        [:rubber_duck, :agent, :communication, :unhealthy],
        %{count: length(unhealthy)},
        %{agents: unhealthy}
      )
    end

    health
  end
end
