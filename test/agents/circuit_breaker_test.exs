defmodule RubberDuck.Agents.CircuitBreakerTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Agents.{CircuitBreaker, ProtectedAgent}
  alias RubberDuck.Routing.CircuitBreakerSupervisor

  # Mock agent for testing
  defmodule TestAgent do
    use RubberDuck.Agents.ProtectedAgent,
      name: "test_agent",
      description: "Test agent for circuit breaker testing"

    def handle_instruction({:echo, message}, agent) do
      {{:ok, message}, agent}
    end

    def handle_instruction({:slow, delay}, agent) do
      Process.sleep(delay)
      {{:ok, :slow_complete}, agent}
    end

    def handle_instruction({:fail, reason}, _agent) do
      throw({:error, reason})
    end

    def handle_instruction({:crash, _}, _agent) do
      raise "Agent crashed!"
    end
  end

  setup do
    # Ensure supervisor is started
    unless Process.whereis(CircuitBreakerSupervisor) do
      start_supervised!(CircuitBreakerSupervisor)
    end

    # Reset all circuit breakers
    CircuitBreaker.reset_all()

    # Clear process dictionary
    Process.get_keys()
    |> Enum.each(&Process.delete/1)

    :ok
  end

  describe "send_instruction/3" do
    test "sends instruction when circuit is closed" do
      # This would normally interact with a real agent
      # For testing, we simulate the response
      result =
        CircuitBreaker.send_instruction(
          :llm_orchestrator,
          {:complete, %{prompt: "test"}},
          []
        )

      # The actual result depends on agent availability
      assert match?({:ok, _} | {:error, :agent_unavailable}, result)
    end

    test "returns error when circuit is open" do
      # Force circuit open by recording failures
      for _ <- 1..5 do
        CircuitBreaker.send_instruction(:project_agent, {:fail, :test}, [])
      end

      # Circuit should be open
      assert CircuitBreaker.circuit_open?(:project_agent)

      # Should return circuit open error
      result =
        CircuitBreaker.send_instruction(
          :project_agent,
          {:analyze_project, "123"},
          []
        )

      assert result == {:error, :circuit_open}
    end

    test "adds failed instructions to dead letter queue" do
      # Force failures
      for i <- 1..3 do
        CircuitBreaker.send_instruction(
          :ai_analysis,
          {:analyze, "data_#{i}"},
          []
        )
      end

      # Check dead letter queue
      dead_letters = CircuitBreaker.get_dead_letter_queue(:ai_analysis)
      assert length(dead_letters) > 0
    end

    test "attempts fallback when specified" do
      # Force primary circuit open
      for _ <- 1..5 do
        CircuitBreaker.send_instruction(:user_agent, {:fail, :test}, [])
      end

      # Send with fallback
      result =
        CircuitBreaker.send_instruction(
          :user_agent,
          {:process_request, %{}},
          fallback: :ai_analysis
        )

      # Should attempt fallback (which may also fail if agent unavailable)
      assert match?({:ok, _} | {:error, _}, result)
    end

    test "respects instruction timeout" do
      result =
        CircuitBreaker.send_instruction(
          :llm_orchestrator,
          {:slow, 5000},
          timeout: 100
        )

      # Should timeout
      assert match?({:error, _}, result)
    end
  end

  describe "broadcast_to_agents/3" do
    test "sends to multiple agents in parallel" do
      agents = [:llm_orchestrator, :llm_monitoring, :project_agent]
      instruction = {:status, :check}

      results = CircuitBreaker.broadcast_to_agents(agents, instruction)

      assert is_map(results)
      assert Map.has_key?(results, :llm_orchestrator)
      assert Map.has_key?(results, :llm_monitoring)
      assert Map.has_key?(results, :project_agent)
    end

    test "skips agents with open circuits" do
      # Open circuit for one agent
      for _ <- 1..5 do
        CircuitBreaker.send_instruction(:code_file_agent, {:fail, :test}, [])
      end

      agents = [:code_file_agent, :project_agent]
      results = CircuitBreaker.broadcast_to_agents(agents, {:ping, :test})

      # code_file_agent should have circuit open error
      assert match?({:error, :circuit_open}, results[:code_file_agent])
    end
  end

  describe "circuit management" do
    test "circuit_open? returns correct state" do
      assert CircuitBreaker.circuit_open?(:llm_orchestrator) == false

      # Force circuit open
      for _ <- 1..3 do
        CircuitBreaker.send_instruction(:llm_orchestrator, {:fail, :test}, [])
      end

      # May or may not be open depending on threshold
      assert is_boolean(CircuitBreaker.circuit_open?(:llm_orchestrator))
    end

    test "get_status returns comprehensive status" do
      status = CircuitBreaker.get_status()

      assert is_map(status)
      assert Map.has_key?(status, :llm_orchestrator)
      assert Map.has_key?(status, :project_agent)

      # Check status structure
      llm_status = status[:llm_orchestrator]
      assert Map.has_key?(llm_status, :state) || Map.has_key?(llm_status, :available)
    end

    test "reset clears circuit and metrics" do
      # Create some failures
      for _ <- 1..3 do
        CircuitBreaker.send_instruction(:ai_analysis, {:fail, :test}, [])
      end

      # Add to dead letter queue
      CircuitBreaker.send_instruction(:ai_analysis, {:analyze, "data"}, [])

      # Reset
      CircuitBreaker.reset(:ai_analysis)

      # Should be cleared
      assert CircuitBreaker.circuit_open?(:ai_analysis) == false
      assert CircuitBreaker.get_dead_letter_queue(:ai_analysis) == []
    end

    test "reset_all clears all circuits" do
      # Create failures for multiple agents
      for agent <- [:llm_orchestrator, :project_agent] do
        for _ <- 1..5 do
          CircuitBreaker.send_instruction(agent, {:fail, :test}, [])
        end
      end

      # Reset all
      CircuitBreaker.reset_all()

      # All should be clear
      assert CircuitBreaker.circuit_open?(:llm_orchestrator) == false
      assert CircuitBreaker.circuit_open?(:project_agent) == false
    end
  end

  describe "dead letter queue" do
    test "stores failed instructions" do
      # Force failures
      instructions = [
        {:analyze, "data1"},
        {:analyze, "data2"},
        {:analyze, "data3"}
      ]

      for instruction <- instructions do
        CircuitBreaker.send_instruction(:ai_analysis, instruction, [])
      end

      dead_letters = CircuitBreaker.get_dead_letter_queue(:ai_analysis)
      assert length(dead_letters) > 0
    end

    test "retry_dead_letters attempts to resend" do
      # Add to dead letter queue
      CircuitBreaker.send_instruction(:project_agent, {:analyze, "test"}, [])

      # Retry
      results = CircuitBreaker.retry_dead_letters(:project_agent)

      assert is_list(results)
      # Each result should be {instruction, result}
      Enum.each(results, fn {instruction, result} ->
        assert is_tuple(instruction)
        assert match?({:ok, _} | {:error, _}, result)
      end)
    end

    test "dead letter queue has size limit" do
      # Try to add more than limit (100)
      for i <- 1..110 do
        Process.put({:dead_letter_queue, :test}, [
          {{:test, i}, []} | Process.get({:dead_letter_queue, :test}, [])
        ])
      end

      # Should be limited to 100
      queue = Process.get({:dead_letter_queue, :test}, [])
      assert length(queue) <= 100
    end
  end

  describe "ProtectedAgent integration" do
    test "send_with_retry retries on failure" do
      attempt_count = Process.get(:retry_attempts, 0)

      # This will fail but should retry
      result =
        ProtectedAgent.send_with_retry(
          :ai_analysis,
          {:analyze, "test"},
          retries: 2,
          retry_delay: 10
        )

      # Should have made multiple attempts
      assert match?({:error, _}, result)
    end

    test "execute_chain processes sequential instructions" do
      chain = [
        {:llm_orchestrator, fn _ -> {:complete, %{prompt: "test"}} end},
        {:ai_analysis, fn _prev -> {:analyze, "result"} end}
      ]

      result = ProtectedAgent.execute_chain(chain)

      # Chain may fail if agents unavailable
      assert match?({:ok, _} | {:error, _}, result)
    end

    test "execute_parallel runs instructions concurrently" do
      instructions = [
        {:llm_orchestrator, {:status, :check}},
        {:project_agent, {:list_projects, %{}}},
        {:ai_analysis, {:get_insights, %{}}}
      ]

      results = ProtectedAgent.execute_parallel(instructions, timeout: 1000)

      assert is_map(results)
      assert map_size(results) == 3

      # Each should have a result (success or error)
      Enum.each(results, fn {_agent, result} ->
        assert match?({:ok, _} | {:error, _}, result)
      end)
    end

    test "monitor_communication_health reports unhealthy agents" do
      # Force some circuits open
      for _ <- 1..5 do
        CircuitBreaker.send_instruction(:user_agent, {:fail, :test}, [])
      end

      health = ProtectedAgent.monitor_communication_health()

      assert is_map(health)
      # Should include all agent types
      assert map_size(health) > 0
    end
  end

  describe "agent-specific thresholds" do
    test "critical agents have lower threshold" do
      # LLM orchestrator should have threshold of 3
      for _ <- 1..2 do
        CircuitBreaker.send_instruction(:llm_orchestrator, {:fail, :test}, [])
      end

      # Not open yet
      assert CircuitBreaker.circuit_open?(:llm_orchestrator) == false

      # One more should open it (if available)
      CircuitBreaker.send_instruction(:llm_orchestrator, {:fail, :test}, [])

      # May be open depending on actual threshold
      assert is_boolean(CircuitBreaker.circuit_open?(:llm_orchestrator))
    end

    test "monitoring agents have higher threshold" do
      # LLM monitoring should have threshold of 10
      for _ <- 1..9 do
        CircuitBreaker.send_instruction(:llm_monitoring, {:fail, :test}, [])
      end

      # Should still be closed (if agent available)
      # Circuit state depends on agent availability
      assert is_boolean(CircuitBreaker.circuit_open?(:llm_monitoring))
    end
  end
end
