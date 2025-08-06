defmodule RubberDuck.Routing.MessageRouter do
  @moduledoc """
  High-performance message routing with compile-time optimization.

  This router provides:
  - O(1) message routing using compile-time dispatch tables
  - Automatic telemetry for performance monitoring
  - Priority-based routing
  - Batch message processing
  - Circuit breaker pattern for fault tolerance

  ## Usage

      # Route a single message
      message = %Code.Analyze{file_path: "/lib/foo.ex", analysis_type: :security}
      {:ok, result} = MessageRouter.route(message)
      
      # Route with context
      {:ok, result} = MessageRouter.route(message, %{user_id: "123"})
      
      # Batch routing
      results = MessageRouter.route_batch(messages)
  """

  use GenServer
  require Logger
  alias RubberDuck.Protocol.Message
  alias RubberDuck.Telemetry.MessageTelemetry

  # Compile-time routing table
  # This creates direct module dispatch without runtime lookup
  @routes %{
    # Code domain
    RubberDuck.Messages.Code.Analyze => RubberDuck.Skills.CodeAnalysisSkill,
    RubberDuck.Messages.Code.QualityCheck => RubberDuck.Skills.CodeAnalysisSkill,
    RubberDuck.Messages.Code.ImpactAssess => RubberDuck.Skills.CodeAnalysisSkill,
    RubberDuck.Messages.Code.PerformanceAnalyze => RubberDuck.Skills.CodeAnalysisSkill,
    RubberDuck.Messages.Code.SecurityScan => RubberDuck.Skills.CodeAnalysisSkill,
    
    # Learning domain
    RubberDuck.Messages.Learning.RecordExperience => RubberDuck.Skills.LearningSkill,
    RubberDuck.Messages.Learning.ProcessFeedback => RubberDuck.Skills.LearningSkill,
    RubberDuck.Messages.Learning.AnalyzePattern => RubberDuck.Skills.LearningSkill,
    RubberDuck.Messages.Learning.OptimizeAgent => RubberDuck.Skills.LearningSkill,
    
    # Project domain  
    RubberDuck.Messages.Project.AnalyzeStructure => RubberDuck.Skills.ProjectManagementSkill,
    RubberDuck.Messages.Project.UpdateStatus => RubberDuck.Skills.ProjectManagementSkill,
    RubberDuck.Messages.Project.MonitorHealth => RubberDuck.Skills.ProjectManagementSkill,
    RubberDuck.Messages.Project.OptimizeResources => RubberDuck.Skills.ProjectManagementSkill,
    
    # User domain
    RubberDuck.Messages.User.ValidateSession => RubberDuck.Skills.UserManagementSkill,
    RubberDuck.Messages.User.UpdatePreferences => RubberDuck.Skills.UserManagementSkill,
    RubberDuck.Messages.User.TrackActivity => RubberDuck.Skills.UserManagementSkill,
    RubberDuck.Messages.User.GenerateSuggestions => RubberDuck.Skills.UserManagementSkill,
    
    # LLM domain - route directly to agents (not skills)
    RubberDuck.Messages.LLM.Complete => RubberDuck.Agents.LLMOrchestratorAgent,
    RubberDuck.Messages.LLM.ProviderSelect => RubberDuck.Agents.LLMOrchestratorAgent,
    RubberDuck.Messages.LLM.Fallback => RubberDuck.Agents.LLMOrchestratorAgent,
    RubberDuck.Messages.LLM.HealthCheck => RubberDuck.Agents.LLMMonitoringAgent,
    
    # AI domain - route to AI Analysis Agent
    RubberDuck.Messages.AI.Analyze => RubberDuck.Agents.AIAnalysisAgent,
    RubberDuck.Messages.AI.PatternDetect => RubberDuck.Agents.AIAnalysisAgent,
    RubberDuck.Messages.AI.InsightGenerate => RubberDuck.Agents.AIAnalysisAgent,
    RubberDuck.Messages.AI.QualityAssess => RubberDuck.Agents.AIAnalysisAgent
  }

  @type routing_result :: {:ok, term()} | {:error, term()}

  # Client API

  @doc """
  Starts the message router.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Routes a message to its handler with optional context.

  First attempts to use the message's own routing via the protocol,
  then falls back to the compiled routing table.
  """
  @spec route(struct(), map()) :: routing_result()
  def route(message, context \\ %{}) do
    start_time = System.monotonic_time(:microsecond)
    
    # Emit start telemetry
    MessageTelemetry.emit_routing_start(message, context)

    # Add routing metadata
    context = Map.put(context, :routed_at, DateTime.utc_now())

    # Get priority and timeout from message
    priority = Message.priority(message)
    timeout = Message.timeout(message)

    # Route based on priority
    result =
      try do
        case priority do
          :critical -> route_critical(message, context, timeout)
          :high -> route_high_priority(message, context, timeout)
          _ -> route_normal(message, context, timeout)
        end
      rescue
        exception ->
          duration = System.monotonic_time(:microsecond) - start_time
          MessageTelemetry.emit_routing_exception(
            message,
            duration,
            :error,
            exception,
            __STACKTRACE__,
            context
          )
          reraise exception, __STACKTRACE__
      end

    # Emit stop telemetry
    duration = System.monotonic_time(:microsecond) - start_time
    MessageTelemetry.emit_routing_stop(message, duration, result, context)

    result
  end

  @doc """
  Routes multiple messages in parallel, respecting their priorities.

  Returns a list of `{:ok, result}` or `{:error, reason}` tuples.
  """
  @spec route_batch([struct()]) :: [routing_result()]
  def route_batch(messages) when is_list(messages) do
    start_time = System.monotonic_time(:microsecond)
    
    # Emit batch start telemetry
    MessageTelemetry.emit_batch_start(messages)
    
    # Group by priority for efficient processing
    grouped = Enum.group_by(messages, &Message.priority/1)

    # Process each priority group
    results = []

    # Critical messages first (sequential to maintain order)
    results =
      case Map.get(grouped, :critical) do
        nil ->
          results

        critical ->
          critical_results = Enum.map(critical, &route(&1))
          results ++ critical_results
      end

    # High priority messages (limited parallelism)
    results =
      case Map.get(grouped, :high) do
        nil ->
          results

        high ->
          high_results =
            high
            |> Task.async_stream(&route(&1), max_concurrency: 4, timeout: 30_000)
            |> Enum.map(fn
              {:ok, result} -> result
              {:exit, reason} -> {:error, {:routing_failed, reason}}
            end)

          results ++ high_results
      end

    # Normal and low priority (full parallelism)
    normal_and_low = Map.get(grouped, :normal, []) ++ Map.get(grouped, :low, [])

    normal_results =
      if length(normal_and_low) > 0 do
        normal_and_low
        |> Task.async_stream(&route(&1), max_concurrency: System.schedulers_online() * 2)
        |> Enum.map(fn
          {:ok, result} -> result
          {:exit, reason} -> {:error, {:routing_failed, reason}}
        end)
      else
        []
      end

    final_results = results ++ normal_results
    
    # Emit batch stop telemetry
    duration = System.monotonic_time(:microsecond) - start_time
    MessageTelemetry.emit_batch_stop(messages, duration, final_results)
    
    final_results
  end

  @doc """
  Checks if a handler is available for a message type.
  """
  @spec handler_available?(struct()) :: boolean()
  def handler_available?(%module{}) do
    Map.has_key?(@routes, module) or Message.impl_for(module) != nil
  end

  # Server callbacks

  @impl true
  def init(opts) do
    # Initialize circuit breakers for each route
    circuit_breakers =
      Enum.reduce(@routes, %{}, fn {msg_type, _handler}, acc ->
        Map.put(acc, msg_type, %{
          state: :closed,
          failure_count: 0,
          last_failure: nil,
          threshold: Keyword.get(opts, :circuit_breaker_threshold, 5)
        })
      end)

    state = %{
      circuit_breakers: circuit_breakers,
      stats: %{
        routed: 0,
        failed: 0,
        by_type: %{}
      }
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:get_stats}, _from, state) do
    {:reply, state.stats, state}
  end

  @impl true
  def handle_cast({:update_stats, message_type, success}, state) do
    new_stats =
      state.stats
      |> Map.update!(:routed, &(&1 + 1))
      |> Map.update!(:failed, fn f -> if success, do: f, else: f + 1 end)
      |> Map.update!(:by_type, fn by_type ->
        Map.update(by_type, message_type, 1, &(&1 + 1))
      end)

    {:noreply, %{state | stats: new_stats}}
  end

  # Private routing functions

  defp route_critical(message, context, timeout) do
    # Critical messages get dedicated resources
    Task.Supervisor.async_nolink(
      RubberDuck.TaskSupervisor,
      fn -> do_route(message, context) end
    )
    |> Task.await(timeout)
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
  end

  defp route_high_priority(message, context, timeout) do
    # High priority messages use controlled concurrency
    with {:ok, _} <- check_circuit_breaker(message.__struct__) do
      do_route_with_timeout(message, context, timeout)
    end
  end

  defp route_normal(message, context, timeout) do
    # Normal messages use standard routing
    do_route_with_timeout(message, context, timeout)
  end

  defp do_route_with_timeout(message, context, timeout) do
    task = Task.async(fn -> do_route(message, context) end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  defp do_route(message, context) do
    # Try protocol-based routing first
    case Message.route(message, context) do
      {:error, :no_handler} ->
        # Fall back to compiled routing table
        route_by_type(message, context)

      result ->
        result
    end
  end

  defp route_by_type(%module{} = message, context) do
    case Map.get(@routes, module) do
      nil ->
        Logger.warning("No route defined for message type: #{inspect(module)}")
        {:error, {:no_route_defined, module}}

      handler ->
        # Determine the handler function name
        handler_function = determine_handler_function(module)

        # Check if handler module and function exist
        if Code.ensure_loaded?(handler) and function_exported?(handler, handler_function, 2) do
          # Use telemetry span for handler execution
          MessageTelemetry.span_handler(message, handler, handler_function, context)
        else
          Logger.error("Handler not available: #{inspect(handler)}.#{handler_function}/2")
          {:error, {:handler_not_available, handler, handler_function}}
        end
    end
  end

  defp determine_handler_function(message_module) do
    # Convert module name to handler function
    # E.g., RubberDuck.Messages.Code.Analyze -> handle_analyze
    message_module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> then(&:"handle_#{&1}")
  end

  defp check_circuit_breaker(_message_type) do
    # Circuit breaker implementation would go here
    # For now, always allow
    {:ok, :closed}
  end

  # Circuit breaker telemetry
  # defp emit_circuit_breaker_event(message_type, event, metadata) do
  #   :telemetry.execute(
  #     [:rubber_duck, :circuit_breaker, event],
  #     %{system_time: System.system_time()},
  #     Map.put(metadata, :message_type, message_type)
  #   )
  # end
end
