defmodule RubberDuck.Telemetry.BusinessImpactTelemetry do
  @moduledoc """
  Business impact and value tracking telemetry.
  
  Tracks ROI, efficiency improvements, cost savings, and other business metrics
  resulting from AI/ML operations.
  """

  use GenServer
  require Logger

  @calculation_interval 60_000  # 1 minute

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a business impact event.
  """
  def record_impact(impact_type, value, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:record_impact, impact_type, value, metadata})
    
    # Emit telemetry event
    :telemetry.execute(
      [:rubber_duck, :business, :impact],
      %{value: value},
      Map.merge(metadata, %{impact_type: to_string(impact_type)})
    )
  end

  @doc """
  Records efficiency improvement.
  """
  def record_efficiency_gain(process_name, before_ms, after_ms, metadata \\ %{}) do
    improvement_pct = calculate_improvement_percentage(before_ms, after_ms)
    time_saved_ms = before_ms - after_ms
    
    :telemetry.execute(
      [:rubber_duck, :business, :efficiency],
      %{
        improvement_pct: improvement_pct,
        time_saved_ms: time_saved_ms
      },
      Map.merge(metadata, %{process: to_string(process_name)})
    )
    
    # Track as impact
    record_impact(:efficiency, improvement_pct, %{
      process: process_name,
      time_saved_ms: time_saved_ms
    })
  end

  @doc """
  Records cost savings from automation.
  """
  def record_cost_savings(automation_type, amount, currency \\ "USD", metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :business, :cost_savings],
      %{amount: amount},
      Map.merge(metadata, %{
        automation_type: to_string(automation_type),
        currency: currency
      })
    )
    
    # Track as impact
    record_impact(:cost_savings, amount, %{
      automation_type: automation_type,
      currency: currency
    })
  end

  @doc """
  Records value generation from AI insights.
  """
  def record_value_generated(source, amount, confidence, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :business, :value_generated],
      %{
        amount: amount,
        confidence: confidence
      },
      Map.merge(metadata, %{source: to_string(source)})
    )
    
    # Adjust value by confidence
    adjusted_value = amount * confidence
    
    record_impact(:value_generation, adjusted_value, %{
      source: source,
      confidence: confidence,
      raw_amount: amount
    })
  end

  @doc """
  Gets current ROI calculations.
  """
  def get_roi_metrics do
    GenServer.call(__MODULE__, :get_roi)
  end

  @doc """
  Gets business impact summary.
  """
  def get_impact_summary do
    GenServer.call(__MODULE__, :get_summary)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Schedule periodic ROI calculation
    schedule_roi_calculation()
    
    state = %{
      impacts: [],  # List of impact records
      total_value: 0.0,
      total_costs: 0.0,
      efficiency_gains: %{},
      cost_savings: 0.0,
      value_generated: 0.0,
      roi_history: [],  # Historical ROI calculations
      start_time: DateTime.utc_now()
    }
    
    {:ok, state}
  end

  @impl true
  def handle_cast({:record_impact, impact_type, value, metadata}, state) do
    impact_record = %{
      type: impact_type,
      value: value,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }
    
    updated_state = state
    |> Map.update(:impacts, [impact_record], &[impact_record | &1])
    |> update_impact_totals(impact_type, value)
    
    # Keep only recent impacts (last 1000)
    trimmed_impacts = Enum.take(updated_state.impacts, 1000)
    
    {:noreply, %{updated_state | impacts: trimmed_impacts}}
  end

  @impl true
  def handle_call(:get_roi, _from, state) do
    roi_metrics = calculate_roi_metrics(state)
    {:reply, roi_metrics, state}
  end

  @impl true
  def handle_call(:get_summary, _from, state) do
    summary = build_impact_summary(state)
    {:reply, summary, state}
  end

  @impl true
  def handle_info(:calculate_roi, state) do
    # Calculate current ROI
    roi_metrics = calculate_roi_metrics(state)
    
    # Emit ROI telemetry
    :telemetry.execute(
      [:rubber_duck, :business, :roi],
      %{
        roi_percentage: roi_metrics.roi_percentage,
        total_value: roi_metrics.total_value,
        total_costs: roi_metrics.total_costs
      },
      %{}
    )
    
    # Emit high-level business value metric
    :telemetry.execute(
      [:rubber_duck, :impact, :business_value],
      %{value: roi_metrics.total_value},
      %{
        metric_type: "total_value",
        currency: "USD"
      }
    )
    
    # Update ROI history
    roi_record = Map.put(roi_metrics, :timestamp, DateTime.utc_now())
    updated_history = [roi_record | state.roi_history] |> Enum.take(100)
    
    # Schedule next calculation
    schedule_roi_calculation()
    
    {:noreply, %{state | roi_history: updated_history}}
  end

  # Private Functions

  defp schedule_roi_calculation do
    Process.send_after(self(), :calculate_roi, @calculation_interval)
  end

  defp calculate_improvement_percentage(before, after_value) when before > 0 do
    ((before - after_value) / before) * 100
  end
  defp calculate_improvement_percentage(_, _), do: 0.0

  defp update_impact_totals(state, :efficiency, value) do
    Map.update(state, :total_value, value, &(&1 + value))
  end

  defp update_impact_totals(state, :cost_savings, value) do
    state
    |> Map.update(:cost_savings, value, &(&1 + value))
    |> Map.update(:total_value, value, &(&1 + value))
  end

  defp update_impact_totals(state, :value_generation, value) do
    state
    |> Map.update(:value_generated, value, &(&1 + value))
    |> Map.update(:total_value, value, &(&1 + value))
  end

  defp update_impact_totals(state, :cost, value) do
    Map.update(state, :total_costs, value, &(&1 + value))
  end

  defp update_impact_totals(state, _, value) do
    Map.update(state, :total_value, value, &(&1 + value))
  end

  defp calculate_roi_metrics(state) do
    # Simple ROI calculation: (Value - Costs) / Costs * 100
    roi_percentage = if state.total_costs > 0 do
      ((state.total_value - state.total_costs) / state.total_costs) * 100
    else
      # If no costs recorded, use 100% ROI for any value generated
      if state.total_value > 0, do: 100.0, else: 0.0
    end
    
    # Calculate time-based metrics
    runtime_hours = calculate_runtime_hours(state.start_time)
    value_per_hour = if runtime_hours > 0 do
      state.total_value / runtime_hours
    else
      0.0
    end
    
    %{
      roi_percentage: roi_percentage,
      total_value: state.total_value,
      total_costs: state.total_costs,
      net_value: state.total_value - state.total_costs,
      cost_savings: state.cost_savings,
      value_generated: state.value_generated,
      value_per_hour: value_per_hour,
      runtime_hours: runtime_hours
    }
  end

  defp build_impact_summary(state) do
    # Group impacts by type
    impacts_by_type = Enum.group_by(state.impacts, & &1.type)
    
    # Calculate statistics per type
    type_statistics = impacts_by_type
    |> Enum.map(fn {type, impacts} ->
      values = Enum.map(impacts, & &1.value)
      {
        type,
        %{
          count: length(impacts),
          total: Enum.sum(values),
          average: if(length(values) > 0, do: Enum.sum(values) / length(values), else: 0),
          max: Enum.max(values, fn -> 0 end)
        }
      }
    end)
    |> Map.new()
    
    # Get recent trend
    recent_impacts = Enum.take(state.impacts, 10)
    trend = if length(recent_impacts) >= 2 do
      recent_values = Enum.map(recent_impacts, & &1.value)
      if List.first(recent_values) > List.last(recent_values) do
        :increasing
      else
        :stable
      end
    else
      :insufficient_data
    end
    
    %{
      total_impacts: length(state.impacts),
      impact_types: Map.keys(impacts_by_type),
      type_statistics: type_statistics,
      total_value: state.total_value,
      total_costs: state.total_costs,
      trend: trend,
      last_updated: DateTime.utc_now()
    }
  end

  defp calculate_runtime_hours(start_time) do
    DateTime.diff(DateTime.utc_now(), start_time, :second) / 3600
  end
end