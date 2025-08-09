defmodule RubberDuck.Telemetry.LearningTracker do
  @moduledoc """
  Tracks learning and adaptation metrics for AI agents.
  
  Monitors:
  - Learning accuracy and improvement rates
  - Feedback processing metrics
  - Model adaptation performance
  - Knowledge retention metrics
  """

  use GenServer
  require Logger

  @doc "Start the Learning Tracker GenServer"
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Record learning accuracy measurement"
  def record_accuracy(agent_type, accuracy, context, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :learning, :accuracy],
      %{accuracy: accuracy, count: 1},
      Map.merge(metadata, %{agent_type: agent_type, context: context})
    )
  end

  @doc "Record feedback processing event"
  def record_feedback(agent_id, feedback_type, improvement_score, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :learning, :feedback],
      %{improvement_score: improvement_score, count: 1},
      Map.merge(metadata, %{agent_id: agent_id, feedback_type: feedback_type})
    )
  end

  @doc "Record model adaptation event"
  def record_adaptation(agent_type, adaptation_type, success, duration_ms, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :learning, :adaptation],
      %{
        success: if(success, do: 1, else: 0),
        duration: duration_ms,
        count: 1
      },
      Map.merge(metadata, %{agent_type: agent_type, adaptation_type: adaptation_type})
    )
  end

  @doc "Record knowledge retention measurement"
  def record_retention(agent_id, retention_score, time_period, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :learning, :retention],
      %{retention_score: retention_score, count: 1},
      Map.merge(metadata, %{agent_id: agent_id, time_period: time_period})
    )
  end

  @doc "Dispatch periodic learning metrics"
  def dispatch_learning_metrics do
    GenServer.cast(__MODULE__, :dispatch_learning_metrics)
  end

  ## GenServer Implementation

  @impl true
  def init(_opts) do
    Logger.info("Starting Learning Tracker for telemetry")
    
    # Attach to learning events
    attach_handlers()
    
    {:ok, %{
      accuracy_history: %{},
      feedback_counts: %{},
      adaptation_success_rates: %{},
      retention_scores: %{},
      last_calculation: System.monotonic_time()
    }}
  end

  @impl true
  def handle_cast(:dispatch_learning_metrics, state) do
    try do
      # Calculate and dispatch learning trend metrics
      dispatch_learning_trends(state)
      
      # Dispatch improvement rate metrics
      dispatch_improvement_rates(state)
      
      # Calculate agent performance comparisons
      dispatch_agent_comparisons(state)
      
      {:noreply, state}
    rescue
      error ->
        Logger.warning("Failed to dispatch learning metrics: #{inspect(error)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:learning_event, event_type, measurements, metadata}, state) do
    # Process learning events and update internal state
    new_state = process_learning_event(state, event_type, measurements, metadata)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Learning Tracker received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private Functions

  defp attach_handlers do
    events = [
      [:rubber_duck, :learning, :accuracy],
      [:rubber_duck, :learning, :feedback],
      [:rubber_duck, :learning, :adaptation],
      [:rubber_duck, :learning, :retention]
    ]

    :telemetry.attach_many(
      "learning-tracker-handler",
      events,
      &handle_learning_event/4,
      self()
    )
  end

  defp handle_learning_event(event, measurements, metadata, pid) do
    send(pid, {:learning_event, event, measurements, metadata})
  end

  defp process_learning_event(state, [:rubber_duck, :learning, :accuracy], measurements, metadata) do
    agent_type = Map.get(metadata, :agent_type, :unknown)
    accuracy = Map.get(measurements, :accuracy, 0.0)
    timestamp = System.monotonic_time()
    
    history = Map.get(state.accuracy_history, agent_type, [])
    new_entry = {timestamp, accuracy}
    new_history = [new_entry | history] |> Enum.take(50)  # Keep last 50 measurements
    
    %{state | accuracy_history: Map.put(state.accuracy_history, agent_type, new_history)}
  end

  defp process_learning_event(state, [:rubber_duck, :learning, :feedback], _measurements, metadata) do
    feedback_type = Map.get(metadata, :feedback_type, :unknown)
    agent_id = Map.get(metadata, :agent_id, :unknown)
    
    key = {agent_id, feedback_type}
    current_count = Map.get(state.feedback_counts, key, 0)
    
    %{state | feedback_counts: Map.put(state.feedback_counts, key, current_count + 1)}
  end

  defp process_learning_event(state, [:rubber_duck, :learning, :adaptation], measurements, metadata) do
    agent_type = Map.get(metadata, :agent_type, :unknown)
    success = Map.get(measurements, :success, 0)
    
    current_data = Map.get(state.adaptation_success_rates, agent_type, {0, 0})
    {total, successful} = current_data
    new_data = {total + 1, successful + success}
    
    %{state | adaptation_success_rates: Map.put(state.adaptation_success_rates, agent_type, new_data)}
  end

  defp process_learning_event(state, [:rubber_duck, :learning, :retention], measurements, metadata) do
    agent_id = Map.get(metadata, :agent_id, :unknown)
    retention_score = Map.get(measurements, :retention_score, 0.0)
    
    current_scores = Map.get(state.retention_scores, agent_id, [])
    new_scores = [retention_score | current_scores] |> Enum.take(20)  # Keep last 20
    
    %{state | retention_scores: Map.put(state.retention_scores, agent_id, new_scores)}
  end

  defp dispatch_learning_trends(state) do
    # Calculate and dispatch accuracy trends for each agent type
    for {agent_type, history} <- state.accuracy_history do
      if length(history) >= 2 do
        trend = calculate_trend(history)
        current_accuracy = get_latest_accuracy(history)
        
        :telemetry.execute(
          [:rubber_duck, :learning, :trend],
          %{
            current_accuracy: current_accuracy,
            trend: trend,
            data_points: length(history)
          },
          %{agent_type: agent_type}
        )
      end
    end
  end

  defp dispatch_improvement_rates(state) do
    # Calculate improvement rates based on accuracy history
    for {agent_type, history} <- state.accuracy_history do
      if length(history) >= 5 do
        improvement_rate = calculate_improvement_rate(history)
        
        :telemetry.execute(
          [:rubber_duck, :learning, :improvement_rate],
          %{rate: improvement_rate},
          %{agent_type: agent_type}
        )
      end
    end
  end

  defp dispatch_agent_comparisons(state) do
    # Compare agent performance metrics
    agent_accuracies = for {agent_type, history} <- state.accuracy_history do
      current_accuracy = get_latest_accuracy(history)
      {agent_type, current_accuracy}
    end
    
    if length(agent_accuracies) > 1 do
      accuracies = Enum.map(agent_accuracies, &elem(&1, 1))
      avg_accuracy = Enum.sum(accuracies) / length(accuracies)
      best_accuracy = Enum.max(accuracies)
      worst_accuracy = Enum.min(accuracies)
      
      :telemetry.execute(
        [:rubber_duck, :learning, :comparison],
        %{
          average_accuracy: avg_accuracy,
          best_accuracy: best_accuracy,
          worst_accuracy: worst_accuracy,
          agent_count: length(agent_accuracies)
        },
        %{}
      )
    end
  end

  defp calculate_trend(history) when length(history) < 2, do: 0.0
  defp calculate_trend(history) do
    # Simple linear trend calculation
    sorted_history = Enum.sort_by(history, &elem(&1, 0))  # Sort by timestamp
    
    if length(sorted_history) >= 2 do
      {_, first_accuracy} = List.first(sorted_history)
      {_, last_accuracy} = List.last(sorted_history)
      
      last_accuracy - first_accuracy
    else
      0.0
    end
  end

  defp get_latest_accuracy(history) when length(history) == 0, do: 0.0
  defp get_latest_accuracy(history) do
    # Get the most recent accuracy measurement
    history
    |> Enum.max_by(&elem(&1, 0))  # Max by timestamp
    |> elem(1)  # Get accuracy value
  end

  defp calculate_improvement_rate(history) when length(history) < 5, do: 0.0
  defp calculate_improvement_rate(history) do
    # Calculate rate of improvement over recent measurements
    sorted_history = Enum.sort_by(history, &elem(&1, 0))  # Sort by timestamp
    recent_five = Enum.take(sorted_history, -5)  # Last 5 measurements
    
    if length(recent_five) == 5 do
      accuracies = Enum.map(recent_five, &elem(&1, 1))
      first_accuracy = List.first(accuracies)
      last_accuracy = List.last(accuracies)
      
      # Rate of change per measurement
      (last_accuracy - first_accuracy) / 4
    else
      0.0
    end
  end
end