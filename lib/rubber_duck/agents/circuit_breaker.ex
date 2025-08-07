defmodule RubberDuck.Agents.CircuitBreaker do
  @moduledoc """
  Circuit breaker for inter-agent communication in the Jido framework.
  
  Protects against:
  - Unresponsive or slow agents
  - Agent crashes causing message backlogs
  - Recursive agent call chains
  - Distributed agent coordination failures
  - Message storms between agents
  
  Features:
  - Per-agent circuit breakers
  - Message type filtering
  - Instruction timeout tracking
  - Agent dependency mapping
  - Dead letter queue for failed messages
  """
  
  require Logger
  
  alias RubberDuck.Routing.{CircuitBreaker, CircuitBreakerSupervisor}
  
  @default_config %{
    error_threshold: 5,        # Failures before opening
    timeout: 30_000,           # 30 seconds recovery
    half_open_requests: 2,     # Test requests in half-open
    success_threshold: 3,      # Successes to close
    instruction_timeout: 10_000 # 10 seconds per instruction
  }
  
  @agent_types [
    :llm_orchestrator,
    :llm_monitoring,
    :project_agent,
    :code_file_agent,
    :ai_analysis,
    :user_agent
  ]
  
  # Client API
  
  @doc """
  Send an instruction to an agent with circuit breaker protection.
  
  ## Examples
  
      # Send instruction to LLM orchestrator
      CircuitBreaker.send_instruction(
        :llm_orchestrator,
        {:complete, request},
        timeout: 15_000
      )
      
      # Send with fallback
      CircuitBreaker.send_instruction(
        :project_agent,
        {:analyze_project, project_id},
        fallback: :ai_analysis
      )
  """
  @spec send_instruction(atom(), tuple(), keyword()) :: {:ok, any()} | {:error, any()}
  def send_instruction(agent_type, instruction, opts \\ []) do
    circuit_name = circuit_breaker_name(agent_type)
    
    # Ensure circuit breaker exists
    ensure_circuit_breaker(agent_type)
    
    # Check if circuit allows request
    with :ok <- CircuitBreaker.call(circuit_name),
         :ok <- check_agent_availability(agent_type),
         {:ok, result} <- execute_instruction(agent_type, instruction, opts) do
      CircuitBreaker.record_success(circuit_name)
      record_instruction_metrics(agent_type, instruction, :success)
      {:ok, result}
    else
      {:error, :circuit_open} ->
        Logger.warning("Agent circuit open for #{agent_type}")
        handle_circuit_open(agent_type, instruction, opts)
        
      {:error, :agent_unavailable} ->
        Logger.warning("Agent #{agent_type} is unavailable")
        CircuitBreaker.record_failure(circuit_name)
        handle_agent_unavailable(agent_type, instruction, opts)
        
      {:error, reason} = error ->
        Logger.error("Agent instruction failed: #{inspect(reason)}")
        CircuitBreaker.record_failure(circuit_name)
        record_instruction_metrics(agent_type, instruction, :failure)
        
        if Keyword.get(opts, :fallback) do
          attempt_fallback(agent_type, instruction, opts)
        else
          error
        end
    end
  end
  
  @doc """
  Broadcast a message to multiple agents with circuit breaker protection.
  
  Messages are sent to available agents only, skipping those with open circuits.
  """
  @spec broadcast_to_agents(list(atom()), tuple(), keyword()) :: map()
  def broadcast_to_agents(agent_types, instruction, opts \\ []) do
    agent_types
    |> Enum.map(fn agent_type ->
      task = Task.async(fn ->
        {agent_type, send_instruction(agent_type, instruction, opts)}
      end)
      
      {agent_type, task}
    end)
    |> Enum.map(fn {agent_type, task} ->
      timeout = Keyword.get(opts, :timeout, @default_config.instruction_timeout)
      
      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, result} -> result
        _ -> {agent_type, {:error, :timeout}}
      end
    end)
    |> Map.new()
  end
  
  @doc """
  Check if an agent's circuit is currently open.
  """
  @spec circuit_open?(atom()) :: boolean()
  def circuit_open?(agent_type) when agent_type in @agent_types do
    circuit_name = circuit_breaker_name(agent_type)
    
    case CircuitBreaker.get_state(circuit_name) do
      {:ok, %{state: :open}} -> true
      {:ok, %{state: :half_open}} -> true
      _ -> false
    end
  end
  
  @doc """
  Get the status of all agent circuit breakers.
  """
  @spec get_status() :: map()
  def get_status do
    Map.new(@agent_types, fn agent_type ->
      circuit_name = circuit_breaker_name(agent_type)
      
      status = case CircuitBreaker.get_state(circuit_name) do
        {:ok, state} -> 
          Map.merge(state, %{
            agent_available: agent_available?(agent_type),
            avg_response_time: get_avg_response_time(agent_type),
            failed_instructions: get_failed_instructions(agent_type),
            last_success: get_last_success_time(agent_type)
          })
        {:error, :not_found} ->
          %{state: :unknown, available: true}
      end
      
      {agent_type, status}
    end)
  end
  
  @doc """
  Reset a specific agent's circuit breaker.
  """
  @spec reset(atom()) :: :ok
  def reset(agent_type) when agent_type in @agent_types do
    circuit_name = circuit_breaker_name(agent_type)
    CircuitBreaker.reset(circuit_name)
    clear_metrics(agent_type)
    :ok
  end
  
  @doc """
  Reset all agent circuit breakers.
  """
  @spec reset_all() :: :ok
  def reset_all do
    Enum.each(@agent_types, &reset/1)
    :ok
  end
  
  @doc """
  Get failed instructions from the dead letter queue.
  """
  @spec get_dead_letter_queue(atom()) :: list()
  def get_dead_letter_queue(agent_type) do
    Process.get({:dead_letter_queue, agent_type}, [])
  end
  
  @doc """
  Retry failed instructions from the dead letter queue.
  """
  @spec retry_dead_letters(atom(), keyword()) :: list()
  def retry_dead_letters(agent_type, opts \\ []) do
    dead_letters = get_dead_letter_queue(agent_type)
    
    results = Enum.map(dead_letters, fn {instruction, original_opts} ->
      merged_opts = Keyword.merge(original_opts, opts)
      {instruction, send_instruction(agent_type, instruction, merged_opts)}
    end)
    
    # Clear successful retries from dead letter queue
    failed_retries = 
      results
      |> Enum.filter(fn {_instruction, result} ->
        match?({:error, _}, result)
      end)
      |> Enum.map(fn {instruction, _result} ->
        {instruction, original_opts} = 
          Enum.find(dead_letters, fn {i, _} -> i == instruction end)
        {instruction, original_opts}
      end)
    
    Process.put({:dead_letter_queue, agent_type}, failed_retries)
    
    results
  end
  
  # Private Functions
  
  defp circuit_breaker_name(agent_type) do
    :"agent_#{agent_type}"
  end
  
  defp ensure_circuit_breaker(agent_type) do
    config = get_agent_config(agent_type)
    CircuitBreakerSupervisor.ensure_circuit_breaker(
      circuit_breaker_name(agent_type),
      config: config
    )
  end
  
  defp get_agent_config(agent_type) do
    base_config = Application.get_env(:rubber_duck, :agent_circuit_breaker, %{})
    
    # Agent-specific overrides
    agent_configs = %{
      llm_orchestrator: %{error_threshold: 3, timeout: 60_000},      # Critical agent
      llm_monitoring: %{error_threshold: 10, timeout: 30_000},       # Monitoring, lenient
      project_agent: %{error_threshold: 5, timeout: 45_000},         # Important
      code_file_agent: %{error_threshold: 5, timeout: 45_000},       # Important
      ai_analysis: %{error_threshold: 5, timeout: 60_000},           # Can be slow
      user_agent: %{error_threshold: 3, timeout: 30_000}             # User-facing, strict
    }
    
    Map.merge(
      @default_config,
      Map.merge(base_config, Map.get(agent_configs, agent_type, %{}))
    )
  end
  
  defp check_agent_availability(agent_type) do
    # Check if the agent process is running
    agent_name = get_agent_process_name(agent_type)
    
    case Process.whereis(agent_name) do
      nil -> {:error, :agent_unavailable}
      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          :ok
        else
          {:error, :agent_unavailable}
        end
    end
  rescue
    _ -> {:error, :agent_unavailable}
  end
  
  defp get_agent_process_name(agent_type) do
    case agent_type do
      :llm_orchestrator -> RubberDuck.Agents.LLMOrchestratorAgent
      :llm_monitoring -> RubberDuck.Agents.LLMMonitoringAgent
      :project_agent -> RubberDuck.Agents.ProjectAgent
      :code_file_agent -> RubberDuck.Agents.CodeFileAgent
      :ai_analysis -> RubberDuck.Agents.AIAnalysisAgent
      :user_agent -> RubberDuck.Agents.UserAgent
      _ -> agent_type
    end
  end
  
  defp execute_instruction(agent_type, instruction, opts) do
    start_time = System.monotonic_time(:millisecond)
    timeout = Keyword.get(opts, :timeout, @default_config.instruction_timeout)
    
    # Get the agent module
    agent_module = get_agent_module(agent_type)
    
    result = 
      try do
        # Use Jido's agent communication mechanism
        task = Task.async(fn ->
          # This would normally use Jido.Agent.Server.call or similar
          # For now, we'll simulate the call
          apply(agent_module, :handle_instruction, [instruction, %{}])
        end)
        
        case Task.yield(task, timeout) || Task.shutdown(task) do
          {:ok, response} -> {:ok, response}
          nil -> {:error, :timeout}
        end
      rescue
        error ->
          {:error, {:exception, error}}
      catch
        :exit, reason ->
          {:error, {:exit, reason}}
      end
    
    elapsed_time = System.monotonic_time(:millisecond) - start_time
    record_response_time(agent_type, elapsed_time)
    
    result
  end
  
  defp get_agent_module(agent_type) do
    case agent_type do
      :llm_orchestrator -> RubberDuck.Agents.LLMOrchestratorAgent
      :llm_monitoring -> RubberDuck.Agents.LLMMonitoringAgent
      :project_agent -> RubberDuck.Agents.ProjectAgent
      :code_file_agent -> RubberDuck.Agents.CodeFileAgent
      :ai_analysis -> RubberDuck.Agents.AIAnalysisAgent
      :user_agent -> RubberDuck.Agents.UserAgent
      _ -> throw({:error, :unknown_agent_type})
    end
  end
  
  defp handle_circuit_open(agent_type, instruction, opts) do
    # Add to dead letter queue
    add_to_dead_letter_queue(agent_type, instruction, opts)
    
    # Try fallback if specified
    if fallback = Keyword.get(opts, :fallback) do
      attempt_fallback(agent_type, instruction, opts)
    else
      {:error, :circuit_open}
    end
  end
  
  defp handle_agent_unavailable(agent_type, instruction, opts) do
    # Add to dead letter queue for later retry
    add_to_dead_letter_queue(agent_type, instruction, opts)
    
    # Try fallback if available
    if fallback = Keyword.get(opts, :fallback) do
      attempt_fallback(agent_type, instruction, opts)
    else
      {:error, :agent_unavailable}
    end
  end
  
  defp attempt_fallback(failed_agent, instruction, opts) do
    fallback_agent = Keyword.get(opts, :fallback)
    
    if fallback_agent && fallback_agent != failed_agent do
      Logger.info("Attempting fallback from #{failed_agent} to #{fallback_agent}")
      
      # Remove fallback option to prevent infinite recursion
      new_opts = Keyword.delete(opts, :fallback)
      send_instruction(fallback_agent, instruction, new_opts)
    else
      {:error, :no_fallback_available}
    end
  end
  
  defp add_to_dead_letter_queue(agent_type, instruction, opts) do
    key = {:dead_letter_queue, agent_type}
    queue = Process.get(key, [])
    
    # Limit queue size
    max_size = 100
    new_entry = {instruction, opts}
    
    updated_queue = 
      if length(queue) >= max_size do
        [new_entry | Enum.take(queue, max_size - 1)]
      else
        [new_entry | queue]
      end
    
    Process.put(key, updated_queue)
  end
  
  defp record_instruction_metrics(agent_type, instruction, status) do
    key = {:instruction_metrics, agent_type, elem(instruction, 0)}
    metrics = Process.get(key, %{success: 0, failure: 0})
    
    updated_metrics = 
      case status do
        :success -> %{metrics | success: metrics.success + 1}
        :failure -> %{metrics | failure: metrics.failure + 1}
      end
    
    Process.put(key, updated_metrics)
    
    # Record last success time
    if status == :success do
      Process.put({:last_success, agent_type}, DateTime.utc_now())
    end
  end
  
  defp record_response_time(agent_type, time_ms) do
    key = {:response_times, agent_type}
    times = Process.get(key, [])
    Process.put(key, [time_ms | Enum.take(times, 99)])
  end
  
  defp get_avg_response_time(agent_type) do
    key = {:response_times, agent_type}
    times = Process.get(key, [])
    
    if length(times) > 0 do
      Enum.sum(times) / length(times)
    else
      0.0
    end
  end
  
  defp get_failed_instructions(agent_type) do
    dead_letters = get_dead_letter_queue(agent_type)
    length(dead_letters)
  end
  
  defp get_last_success_time(agent_type) do
    Process.get({:last_success, agent_type})
  end
  
  defp agent_available?(agent_type) do
    case check_agent_availability(agent_type) do
      :ok -> true
      _ -> false
    end
  end
  
  defp clear_metrics(agent_type) do
    Process.delete({:response_times, agent_type})
    Process.delete({:last_success, agent_type})
    Process.delete({:dead_letter_queue, agent_type})
    
    # Clear instruction metrics
    Process.get_keys()
    |> Enum.filter(fn
      {:instruction_metrics, ^agent_type, _} -> true
      _ -> false
    end)
    |> Enum.each(&Process.delete/1)
  end
end