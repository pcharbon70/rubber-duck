defmodule RubberDuck.Telemetry.ImpactTracker do
  @moduledoc """
  Tracks business impact and value metrics from AI operations.
  
  Monitors:
  - Business impact scores from analysis
  - Value generation metrics
  - High-impact action identification
  - ROI and efficiency measurements
  """

  use GenServer
  require Logger

  @doc "Start the Impact Tracker GenServer"
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Record impact score event"
  def record_impact(analysis_type, impact_score, domain, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :impact, :score],
      %{score: impact_score, count: 1},
      Map.merge(metadata, %{analysis_type: analysis_type, domain: domain})
    )
  end

  @doc "Record high-impact action identification"
  def record_high_impact(threshold_level, action_type, impact_score, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :impact, :high_impact],
      %{score: impact_score, count: 1},
      Map.merge(metadata, %{threshold_level: threshold_level, action_type: action_type})
    )
  end

  @doc "Record business value generated"
  def record_business_value(value_amount, currency, metric_type, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :impact, :business_value],
      %{value: value_amount, count: 1},
      Map.merge(metadata, %{currency: currency, metric_type: metric_type})
    )
  end

  @doc "Record efficiency measurement"
  def record_efficiency(efficiency_score, process_type, improvement_ratio, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :impact, :efficiency],
      %{
        score: efficiency_score,
        improvement_ratio: improvement_ratio,
        count: 1
      },
      Map.merge(metadata, %{process_type: process_type})
    )
  end

  ## GenServer Implementation

  @impl true
  def init(_opts) do
    Logger.info("Starting Impact Tracker for telemetry")
    
    # Attach to impact events
    attach_handlers()
    
    {:ok, %{
      impact_scores: %{},
      business_values: %{},
      efficiency_scores: %{},
      high_impact_counts: %{},
      last_aggregation: System.monotonic_time()
    }}
  end

  @impl true
  def handle_cast(:dispatch_impact_metrics, state) do
    try do
      # Dispatch aggregated impact metrics
      dispatch_impact_aggregates(state)
      
      # Dispatch ROI calculations
      dispatch_roi_metrics(state)
      
      # Dispatch trend analysis
      dispatch_trend_analysis(state)
      
      {:noreply, state}
    rescue
      error ->
        Logger.warning("Failed to dispatch impact metrics: #{inspect(error)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:impact_event, event_type, measurements, metadata}, state) do
    # Process impact events and update internal state
    new_state = process_impact_event(state, event_type, measurements, metadata)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Impact Tracker received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private Functions

  defp attach_handlers do
    events = [
      [:rubber_duck, :impact, :score],
      [:rubber_duck, :impact, :high_impact],
      [:rubber_duck, :impact, :business_value],
      [:rubber_duck, :impact, :efficiency]
    ]

    :telemetry.attach_many(
      "impact-tracker-handler",
      events,
      &handle_impact_event/4,
      self()
    )
  end

  defp handle_impact_event(event, measurements, metadata, pid) do
    send(pid, {:impact_event, event, measurements, metadata})
  end

  defp process_impact_event(state, [:rubber_duck, :impact, :score], measurements, metadata) do
    analysis_type = Map.get(metadata, :analysis_type, :unknown)
    domain = Map.get(metadata, :domain, :unknown)
    score = Map.get(measurements, :score, 0.0)
    
    key = {analysis_type, domain}
    current_scores = Map.get(state.impact_scores, key, [])
    new_scores = [score | current_scores] |> Enum.take(100)  # Keep last 100
    
    %{state | impact_scores: Map.put(state.impact_scores, key, new_scores)}
  end

  defp process_impact_event(state, [:rubber_duck, :impact, :high_impact], _measurements, metadata) do
    threshold_level = Map.get(metadata, :threshold_level, :unknown)
    action_type = Map.get(metadata, :action_type, :unknown)
    
    key = {threshold_level, action_type}
    current_count = Map.get(state.high_impact_counts, key, 0)
    
    %{state | high_impact_counts: Map.put(state.high_impact_counts, key, current_count + 1)}
  end

  defp process_impact_event(state, [:rubber_duck, :impact, :business_value], measurements, metadata) do
    metric_type = Map.get(metadata, :metric_type, :unknown)
    currency = Map.get(metadata, :currency, :usd)
    value = Map.get(measurements, :value, 0.0)
    
    key = {metric_type, currency}
    current_values = Map.get(state.business_values, key, [])
    new_values = [value | current_values] |> Enum.take(50)  # Keep last 50
    
    %{state | business_values: Map.put(state.business_values, key, new_values)}
  end

  defp process_impact_event(state, [:rubber_duck, :impact, :efficiency], measurements, metadata) do
    process_type = Map.get(metadata, :process_type, :unknown)
    efficiency_score = Map.get(measurements, :score, 0.0)
    improvement_ratio = Map.get(measurements, :improvement_ratio, 0.0)
    
    current_data = Map.get(state.efficiency_scores, process_type, [])
    new_entry = {efficiency_score, improvement_ratio, System.monotonic_time()}
    new_data = [new_entry | current_data] |> Enum.take(30)  # Keep last 30
    
    %{state | efficiency_scores: Map.put(state.efficiency_scores, process_type, new_data)}
  end

  defp dispatch_impact_aggregates(state) do
    # Dispatch impact score statistics
    for {{analysis_type, domain}, scores} <- state.impact_scores do
      if length(scores) > 0 do
        avg_score = Enum.sum(scores) / length(scores)
        max_score = Enum.max(scores)
        min_score = Enum.min(scores)
        p95_score = calculate_percentile(scores, 95)
        
        :telemetry.execute(
          [:rubber_duck, :impact, :aggregates],
          %{
            average: avg_score,
            max: max_score,
            min: min_score,
            p95: p95_score,
            count: length(scores)
          },
          %{analysis_type: analysis_type, domain: domain}
        )
      end
    end

    # Dispatch high-impact action counts
    for {{threshold_level, action_type}, count} <- state.high_impact_counts do
      :telemetry.execute(
        [:rubber_duck, :impact, :high_impact_count],
        %{count: count},
        %{threshold_level: threshold_level, action_type: action_type}
      )
    end
  end

  defp dispatch_roi_metrics(state) do
    # Calculate ROI based on business values and efficiency scores
    total_value = calculate_total_business_value(state.business_values)
    avg_efficiency = calculate_average_efficiency(state.efficiency_scores)
    
    if total_value > 0 do
      # Simple ROI calculation (this could be enhanced with cost data)
      estimated_cost = total_value * 0.3  # Assume 30% cost ratio
      roi = if estimated_cost > 0, do: (total_value - estimated_cost) / estimated_cost, else: 0.0
      
      :telemetry.execute(
        [:rubber_duck, :impact, :roi],
        %{
          roi: roi,
          total_value: total_value,
          estimated_cost: estimated_cost,
          efficiency: avg_efficiency
        },
        %{}
      )
    end
  end

  defp dispatch_trend_analysis(state) do
    # Analyze trends in impact scores
    for {{analysis_type, domain}, scores} <- state.impact_scores do
      if length(scores) >= 10 do
        trend = calculate_score_trend(scores)
        volatility = calculate_volatility(scores)
        
        :telemetry.execute(
          [:rubber_duck, :impact, :trend],
          %{
            trend: trend,
            volatility: volatility,
            sample_size: length(scores)
          },
          %{analysis_type: analysis_type, domain: domain}
        )
      end
    end
  end

  defp calculate_percentile(values, percentile) do
    sorted = Enum.sort(values)
    count = length(sorted)
    index = max(0, ceil(percentile / 100 * count) - 1)
    Enum.at(sorted, index, 0)
  end

  defp calculate_total_business_value(business_values) do
    business_values
    |> Map.values()
    |> List.flatten()
    |> Enum.sum()
  end

  defp calculate_average_efficiency(efficiency_scores) do
    all_scores = efficiency_scores
    |> Map.values()
    |> List.flatten()
    |> Enum.map(&elem(&1, 0))  # Extract efficiency scores
    
    if length(all_scores) > 0 do
      Enum.sum(all_scores) / length(all_scores)
    else
      0.0
    end
  end

  defp calculate_score_trend(scores) when length(scores) < 3, do: 0.0
  defp calculate_score_trend(scores) do
    # Simple trend calculation: compare first third vs last third
    count = length(scores)
    third_size = div(count, 3)
    
    if third_size > 0 do
      first_third = Enum.take(scores, third_size)
      last_third = Enum.take(scores, -third_size)
      
      first_avg = Enum.sum(first_third) / length(first_third)
      last_avg = Enum.sum(last_third) / length(last_third)
      
      last_avg - first_avg
    else
      0.0
    end
  end

  defp calculate_volatility(scores) when length(scores) < 2, do: 0.0
  defp calculate_volatility(scores) do
    # Calculate standard deviation as a measure of volatility
    mean = Enum.sum(scores) / length(scores)
    variance = scores
    |> Enum.map(&((&1 - mean) * (&1 - mean)))
    |> Enum.sum()
    |> Kernel./(length(scores))
    
    :math.sqrt(variance)
  end
end