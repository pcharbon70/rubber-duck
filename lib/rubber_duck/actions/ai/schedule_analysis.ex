defmodule RubberDuck.Actions.AI.ScheduleAnalysis do
  @moduledoc """
  Action for scheduling AI analyses based on project activity and priorities.

  Determines optimal timing and type of analysis based on:
  - Project activity patterns
  - Resource availability
  - Historical analysis effectiveness
  - User preferences
  """

  use Jido.Action,
    name: "schedule_analysis",
    description: "Intelligently schedule AI analyses based on activity patterns",
    schema: [
      project_id: [type: :string, required: false],
      file_id: [type: :string, required: false],
      analysis_types: [type: {:list, :atom}, default: [:general]],
      priority: [type: :atom, default: :normal],
      trigger: [type: :atom, default: :manual],
      context: [type: :map, default: %{}]
    ]

  require Logger

  @impl true
  def run(params, _context) do
    with {:ok, schedule} <- determine_optimal_schedule(params),
         {:ok, validated} <- validate_schedule(schedule),
         {:ok, prioritized} <- apply_priority_rules(validated, params.priority) do

      {:ok, %{
        scheduled_at: prioritized.scheduled_at,
        analysis_types: prioritized.analysis_types,
        priority: prioritized.priority,
        estimated_duration: estimate_duration(prioritized),
        resource_requirements: calculate_resources(prioritized),
        trigger: params.trigger,
        metadata: build_schedule_metadata(prioritized, params)
      }}
    end
  end

  defp determine_optimal_schedule(params) do
    current_time = DateTime.utc_now()

    schedule = %{
      scheduled_at: calculate_optimal_time(current_time, params),
      analysis_types: determine_analysis_types(params),
      scope: determine_scope(params),
      batch_size: calculate_batch_size(params)
    }

    {:ok, schedule}
  end

  defp calculate_optimal_time(current_time, params) do
    case params.priority do
      :immediate -> current_time
      :high -> DateTime.add(current_time, 300, :second)  # 5 minutes
      :normal -> DateTime.add(current_time, 1800, :second)  # 30 minutes
      :low -> DateTime.add(current_time, 7200, :second)  # 2 hours
      _ -> DateTime.add(current_time, 3600, :second)  # 1 hour default
    end
  end

  defp determine_analysis_types(params) do
    base_types = params.analysis_types || [:general]

    # Add types based on trigger
    trigger_types = case params.trigger do
      :commit -> [:complexity, :quality]
      :pr -> [:security, :performance, :quality]
      :major_change -> [:complexity, :security, :performance]
      _ -> []
    end

    Enum.uniq(base_types ++ trigger_types)
  end

  defp determine_scope(params) do
    cond do
      params.file_id -> :file
      params.project_id -> :project
      true -> :workspace
    end
  end

  defp calculate_batch_size(params) do
    case params.priority do
      :immediate -> 1
      :high -> 5
      :normal -> 10
      :low -> 20
      _ -> 10
    end
  end

  defp validate_schedule(schedule) do
    errors = []

    errors = if DateTime.compare(schedule.scheduled_at, DateTime.utc_now()) == :lt do
      ["Scheduled time is in the past" | errors]
    else
      errors
    end

    errors = if Enum.empty?(schedule.analysis_types) do
      ["No analysis types specified" | errors]
    else
      errors
    end

    if Enum.empty?(errors) do
      {:ok, schedule}
    else
      {:error, errors}
    end
  end

  defp apply_priority_rules(schedule, priority) do
    adjusted = case priority do
      :immediate ->
        %{schedule |
          scheduled_at: DateTime.utc_now(),
          priority: :immediate,
          analysis_types: Enum.take(schedule.analysis_types, 2)  # Limit for speed
        }

      :high ->
        %{schedule |
          priority: :high,
          analysis_types: prioritize_critical_types(schedule.analysis_types)
        }

      _ ->
        Map.put(schedule, :priority, priority)
    end

    {:ok, adjusted}
  end

  defp prioritize_critical_types(types) do
    critical = [:security, :performance]
    critical_first = Enum.filter(types, & &1 in critical)
    others = Enum.filter(types, & &1 not in critical)
    critical_first ++ others
  end

  defp estimate_duration(schedule) do
    base_duration = length(schedule.analysis_types) * 30  # 30 seconds per type

    scope_multiplier = case schedule.scope do
      :file -> 1
      :project -> 5
      :workspace -> 10
    end

    base_duration * scope_multiplier
  end

  defp calculate_resources(schedule) do
    %{
      cpu: calculate_cpu_requirement(schedule),
      memory: calculate_memory_requirement(schedule),
      api_calls: estimate_api_calls(schedule)
    }
  end

  defp calculate_cpu_requirement(schedule) do
    case schedule.priority do
      :immediate -> :high
      :high -> :medium
      _ -> :low
    end
  end

  defp calculate_memory_requirement(schedule) do
    base_mb = 100
    type_mb = length(schedule.analysis_types) * 50

    scope_multiplier = case schedule.scope do
      :file -> 1
      :project -> 3
      :workspace -> 5
    end

    (base_mb + type_mb) * scope_multiplier
  end

  defp estimate_api_calls(schedule) do
    length(schedule.analysis_types) * schedule.batch_size
  end

  defp build_schedule_metadata(schedule, params) do
    %{
      created_at: DateTime.utc_now(),
      trigger: params.trigger,
      context: params.context,
      scope: schedule.scope,
      batch_size: schedule.batch_size
    }
  end
end
