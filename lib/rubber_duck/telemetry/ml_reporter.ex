defmodule RubberDuck.Telemetry.MLReporter do
  @moduledoc """
  ML/AI specific telemetry reporter for monitoring machine learning operations.
  
  Handles specialized metrics for:
  - Agent performance and health
  - Model accuracy and improvements
  - Business impact measurements
  - System resource utilization
  """

  use GenServer
  require Logger

  @doc "Start the ML reporter GenServer"
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Dispatch periodic system metrics for ML operations"
  def dispatch_system_metrics do
    GenServer.cast(__MODULE__, :dispatch_system_metrics)
  end

  @doc "Record ML model prediction event"
  def record_prediction(model_type, accuracy, duration, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :ml, :prediction],
      %{
        accuracy: accuracy,
        duration: duration,
        count: 1
      },
      Map.merge(metadata, %{model_type: model_type})
    )
  end

  @doc "Record agent performance metrics"
  def record_agent_performance(agent_id, success_rate, response_time, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :agent, :performance],
      %{
        success_rate: success_rate,
        response_time: response_time,
        count: 1
      },
      Map.merge(metadata, %{agent_id: agent_id})
    )
  end

  @doc "Record business impact event"
  def record_business_impact(impact_score, value_generated, analysis_type, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :impact, :business],
      %{
        score: impact_score,
        value: value_generated,
        count: 1
      },
      Map.merge(metadata, %{analysis_type: analysis_type})
    )
  end

  ## GenServer Implementation

  @impl true
  def init(_opts) do
    Logger.info("Starting ML Reporter for telemetry")
    
    # Attach telemetry handlers
    attach_handlers()
    
    {:ok, %{
      start_time: System.monotonic_time(),
      metrics_count: 0,
      last_dispatch: nil
    }}
  end

  @impl true
  def handle_cast(:dispatch_system_metrics, state) do
    try do
      # Agent health metrics
      dispatch_agent_health_metrics()
      
      # System resource metrics for ML operations
      dispatch_ml_resource_metrics()
      
      # Model performance aggregates
      dispatch_model_performance_metrics()
      
      new_state = %{
        state |
        metrics_count: state.metrics_count + 1,
        last_dispatch: DateTime.utc_now()
      }
      
      {:noreply, new_state}
    rescue
      error ->
        Logger.warning("Failed to dispatch ML system metrics: #{inspect(error)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("ML Reporter received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private Functions

  defp attach_handlers do
    # Attach to ML-specific telemetry events
    events = [
      [:rubber_duck, :ml, :prediction],
      [:rubber_duck, :agent, :performance],
      [:rubber_duck, :impact, :business]
    ]

    :telemetry.attach_many(
      "ml-reporter-handler",
      events,
      &handle_telemetry_event/4,
      nil
    )
  end

  defp handle_telemetry_event([:rubber_duck, :ml, :prediction], measurements, metadata, _config) do
    Logger.debug("ML Prediction event: #{inspect(measurements)} with metadata: #{inspect(metadata)}")
  end

  defp handle_telemetry_event([:rubber_duck, :agent, :performance], measurements, metadata, _config) do
    Logger.debug("Agent Performance event: #{inspect(measurements)} with metadata: #{inspect(metadata)}")
  end

  defp handle_telemetry_event([:rubber_duck, :impact, :business], measurements, metadata, _config) do
    Logger.debug("Business Impact event: #{inspect(measurements)} with metadata: #{inspect(metadata)}")
  end

  defp dispatch_agent_health_metrics do
    # Get current agent status from supervision tree
    agent_count = count_active_agents()
    
    :telemetry.execute(
      [:rubber_duck, :ml, :system, :agents],
      %{active_count: agent_count},
      %{}
    )
  end

  defp dispatch_ml_resource_metrics do
    # Memory usage specific to ML operations
    {memory_mb, cpu_percent} = get_ml_resource_usage()
    
    :telemetry.execute(
      [:rubber_duck, :ml, :system, :resources],
      %{
        memory_mb: memory_mb,
        cpu_percent: cpu_percent
      },
      %{}
    )
  end

  defp dispatch_model_performance_metrics do
    # Aggregate model performance metrics
    # This would typically query recent performance data
    avg_accuracy = calculate_average_model_accuracy()
    
    :telemetry.execute(
      [:rubber_duck, :ml, :system, :performance],
      %{average_accuracy: avg_accuracy},
      %{}
    )
  end

  defp count_active_agents do
    # Count active agents in the supervision tree
    case Process.whereis(RubberDuck.AgentSupervisor) do
      nil -> 0
      pid ->
        pid
        |> DynamicSupervisor.count_children()
        |> Map.get(:active, 0)
    end
  rescue
    _error -> 0
  end

  defp get_ml_resource_usage do
    # Get memory and CPU usage for the current process/system
    memory_bytes = :erlang.memory(:total)
    memory_mb = div(memory_bytes, 1_024 * 1_024)
    
    # CPU usage is more complex to calculate accurately in BEAM
    # For now, return a placeholder that could be enhanced later
    cpu_percent = 0.0
    
    {memory_mb, cpu_percent}
  end

  defp calculate_average_model_accuracy do
    # Placeholder for model accuracy calculation
    # This would typically aggregate recent prediction accuracies
    # For now, return a default value that indicates the metric is being tracked
    0.85
  end
end