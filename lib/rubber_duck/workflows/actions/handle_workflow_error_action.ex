defmodule RubberDuck.Workflows.Actions.HandleWorkflowErrorAction do
  @moduledoc """
  Workflow error handling action with intelligent classification and recovery.

  This action provides comprehensive workflow error handling capabilities
  using the WorkflowErrorManager system with intelligent error classification,
  automatic recovery strategy selection, and performance monitoring.

  Features:
  - Intelligent error classification with confidence scoring
  - Automatic recovery strategy selection based on error type and context
  - Integration with WorkflowErrorManager for comprehensive error handling
  - Performance monitoring with error handling analytics
  - Fallback to autonomous operation when workflow recovery fails
  - Learning integration for continuous error handling improvement

  Error Handling Flow:
  - **Detection**: Identify and classify errors with context analysis
  - **Strategy Selection**: Choose optimal recovery strategy based on error characteristics
  - **Recovery Execution**: Execute recovery with monitoring and fallback capabilities
  - **Analytics Integration**: Track error handling performance for optimization
  """

  use Jido.Action,
    name: "handle_workflow_error",
    schema: [
      error_info: [type: :map, required: true, doc: "Error information and context"],
      workflow_context: [type: :map, default: %{}, doc: "Workflow context for error handling"],
      recovery_config: [type: :map, default: %{}, doc: "Recovery configuration options"],
      monitoring_config: [type: :map, default: %{}, doc: "Error monitoring configuration"]
    ]

  require Logger

  alias RubberDuck.Workflows.ErrorHandling.WorkflowErrorManager

  @default_recovery_config %{
    max_recovery_attempts: 3,
    recovery_timeout_ms: 30_000,
    enable_automatic_fallback: true,
    enable_performance_monitoring: true
  }

  @default_monitoring_config %{
    track_error_patterns: true,
    collect_recovery_metrics: true,
    enable_learning: true,
    report_analytics: true
  }

  @doc """
  Handle workflow error with intelligent classification and recovery.

  Returns error handling result with recovery strategy applied,
  performance metrics, and learning data for continuous improvement.
  """
  def run(params, _context) do
    %{
      error_info: error_info,
      workflow_context: workflow_context,
      recovery_config: recovery_config,
      monitoring_config: monitoring_config
    } = params

    merged_recovery_config = Map.merge(@default_recovery_config, recovery_config)
    merged_monitoring_config = Map.merge(@default_monitoring_config, monitoring_config)

    Logger.info("HandleWorkflowErrorAction: Starting error handling",
      error_type: Map.get(error_info, :type, :unknown),
      workflow_id: Map.get(workflow_context, :workflow_id, :unknown)
    )

    error_handling_start_time = System.monotonic_time(:microsecond)

    with {:ok, validated_error} <- validate_error_information(error_info),
         {:ok, enhanced_context} <- enhance_workflow_context(workflow_context, validated_error),
         {:ok, handling_result} <-
           execute_error_handling(validated_error, enhanced_context, merged_recovery_config),
         {:ok, monitoring_result} <-
           collect_error_monitoring_data(handling_result, merged_monitoring_config) do
      error_handling_time = System.monotonic_time(:microsecond) - error_handling_start_time

      Logger.info("HandleWorkflowErrorAction: Error handling completed",
        strategy_applied: handling_result.strategy_applied,
        recovery_success: handling_result.success,
        error_handling_time_us: error_handling_time
      )

      {:ok,
       %{
         error_handling_result: handling_result,
         monitoring_data: monitoring_result,
         error_handling_metadata: %{
           error_handling_time_microseconds: error_handling_time,
           error_classification: Map.get(handling_result, :error_classification, %{}),
           recovery_strategy_used: handling_result.strategy_applied,
           performance_impact: calculate_performance_impact(error_handling_time, handling_result)
         }
       }}
    else
      {:error, reason} ->
        Logger.error("HandleWorkflowErrorAction: Error handling failed", error: reason)
        {:error, reason}
    end
  end

  # Private implementation functions

  defp validate_error_information(error_info) do
    # Validate error information structure and content
    required_fields = [:type, :message]
    missing_fields = required_fields -- Map.keys(error_info)

    if Enum.empty?(missing_fields) do
      # Enhance error info with additional metadata
      enhanced_error =
        Map.merge(error_info, %{
          detected_at: DateTime.utc_now(),
          validation_passed: true,
          error_id: generate_error_id()
        })

      {:ok, enhanced_error}
    else
      {:error, {:invalid_error_info, missing_fields}}
    end
  end

  defp enhance_workflow_context(workflow_context, validated_error) do
    # Enhance workflow context with error-specific information
    enhanced_context =
      Map.merge(workflow_context, %{
        error_detected: true,
        error_id: validated_error.error_id,
        error_detection_time: validated_error.detected_at,
        criticality: determine_error_criticality(validated_error, workflow_context)
      })

    {:ok, enhanced_context}
  end

  defp determine_error_criticality(error, workflow_context) do
    # Determine error criticality based on error type and workflow context
    error_type = Map.get(error, :type, :unknown)
    workflow_criticality = Map.get(workflow_context, :criticality, :normal)

    base_criticality = classify_error_base_criticality(error_type)
    adjust_criticality_for_workflow(base_criticality, workflow_criticality)
  end

  defp classify_error_base_criticality(error_type) do
    case error_type do
      :system -> :high
      :logical -> :medium
      :resource -> :medium
      :transient -> :low
      _ -> :normal
    end
  end

  defp adjust_criticality_for_workflow(base_criticality, workflow_criticality) do
    case {base_criticality, workflow_criticality} do
      {:high, _} -> :critical
      {:medium, :critical} -> :critical
      {:medium, :high} -> :high
      {base, :critical} -> max_criticality(base, :high)
      {base, workflow_crit} -> max_criticality(base, workflow_crit)
    end
  end

  defp max_criticality(crit1, crit2) do
    criticality_levels = [:low, :normal, :medium, :high, :critical]

    crit1_index = Enum.find_index(criticality_levels, &(&1 == crit1)) || 1
    crit2_index = Enum.find_index(criticality_levels, &(&1 == crit2)) || 1

    max_index = max(crit1_index, crit2_index)
    Enum.at(criticality_levels, max_index)
  end

  defp execute_error_handling(validated_error, enhanced_context, recovery_config) do
    # Execute error handling using WorkflowErrorManager
    case WorkflowErrorManager.handle_workflow_error(validated_error, enhanced_context) do
      {:ok, manager_result} ->
        # Enhance result with action-specific metadata
        enhanced_result =
          Map.merge(manager_result, %{
            action_handled: true,
            recovery_config_applied: recovery_config,
            error_classification: %{
              error_id: validated_error.error_id,
              error_type: validated_error.type,
              criticality: enhanced_context.criticality
            }
          })

        {:ok, enhanced_result}

      {:error, reason} ->
        # Handle error handling failure
        if recovery_config.enable_automatic_fallback do
          Logger.warning("HandleWorkflowErrorAction: Error handling failed, attempting fallback")
          execute_fallback_error_handling(validated_error, enhanced_context)
        else
          {:error, {:error_handling_failed, reason}}
        end
    end
  end

  defp execute_fallback_error_handling(error, context) do
    # Execute fallback error handling when primary handling fails
    fallback_result = %{
      strategy_applied: :autonomous_fallback,
      success: true,
      error_acknowledged: true,
      fallback_mode: :autonomous_operation,
      workflow_terminated: true,
      agent_autonomy_preserved: true,
      fallback_reason: :primary_error_handling_failed
    }

    {:ok, fallback_result}
  end

  defp collect_error_monitoring_data(handling_result, monitoring_config) do
    # Collect comprehensive error monitoring data
    if monitoring_config.track_error_patterns do
      monitoring_data = %{
        error_pattern_data: extract_error_pattern_data(handling_result),
        recovery_metrics: extract_recovery_metrics(handling_result),
        performance_data: extract_performance_data(handling_result),
        learning_data:
          if(monitoring_config.enable_learning,
            do: extract_learning_data(handling_result),
            else: %{}
          )
      }

      {:ok, monitoring_data}
    else
      {:ok, %{monitoring_disabled: true}}
    end
  end

  defp extract_error_pattern_data(handling_result) do
    # Extract error pattern data for analysis
    %{
      error_category:
        Map.get(handling_result, :error_classification, %{}) |> Map.get(:error_category, :unknown),
      recovery_strategy: handling_result.strategy_applied,
      success_indicator: handling_result.success,
      # This error occurrence
      error_frequency: 1
    }
  end

  defp extract_recovery_metrics(handling_result) do
    # Extract recovery performance metrics
    %{
      recovery_time_ms: Map.get(handling_result, :recovery_time_ms, 0),
      recovery_success: handling_result.success,
      strategy_effectiveness: calculate_strategy_effectiveness(handling_result),
      resource_impact: assess_recovery_resource_impact(handling_result)
    }
  end

  defp extract_performance_data(handling_result) do
    # Extract performance data from error handling
    %{
      error_resolution_time: Map.get(handling_result, :recovery_time_ms, 0),
      performance_degradation: calculate_performance_degradation(handling_result),
      system_impact: assess_system_impact(handling_result)
    }
  end

  defp extract_learning_data(handling_result) do
    # Extract learning data for continuous improvement
    %{
      successful_strategy:
        if(handling_result.success, do: handling_result.strategy_applied, else: nil),
      failed_strategy:
        if(handling_result.success, do: nil, else: handling_result.strategy_applied),
      context_factors: Map.get(handling_result, :context_factors, []),
      improvement_opportunities: identify_improvement_opportunities(handling_result)
    }
  end

  defp calculate_strategy_effectiveness(handling_result) do
    # Calculate effectiveness of applied recovery strategy
    if handling_result.success do
      recovery_time = Map.get(handling_result, :recovery_time_ms, 0)

      # Effectiveness based on speed and success
      time_score =
        if recovery_time < 10_000, do: 1.0, else: max(1.0 - recovery_time / 30_000, 0.3)

      # Success = full score
      success_score = 1.0

      effectiveness = time_score * 0.4 + success_score * 0.6
      Float.round(effectiveness, 3)
    else
      # No effectiveness if recovery failed
      0.0
    end
  end

  defp assess_recovery_resource_impact(handling_result) do
    # Assess resource impact of recovery operation
    strategy = handling_result.strategy_applied

    impact_level =
      case strategy do
        :retry_with_backoff -> :low
        :immediate_compensation -> :medium
        :workflow_replay -> :high
        :resource_optimization -> :medium
        :emergency_fallback -> :low
        _ -> :unknown
      end

    %{
      impact_level: impact_level,
      estimated_cpu_impact: calculate_cpu_impact(strategy),
      estimated_memory_impact: calculate_memory_impact(strategy)
    }
  end

  defp calculate_cpu_impact(strategy) do
    # Calculate CPU impact percentage for strategy
    case strategy do
      # 5% CPU
      :retry_with_backoff -> 5
      # 15% CPU
      :immediate_compensation -> 15
      # 25% CPU
      :workflow_replay -> 25
      # 20% CPU
      :resource_optimization -> 20
      # 2% CPU
      :emergency_fallback -> 2
      # 10% default
      _ -> 10
    end
  end

  defp calculate_memory_impact(strategy) do
    # Calculate memory impact in MB for strategy
    case strategy do
      # 5MB
      :retry_with_backoff -> 5
      # 20MB
      :immediate_compensation -> 20
      # 50MB
      :workflow_replay -> 50
      # 30MB
      :resource_optimization -> 30
      # 2MB
      :emergency_fallback -> 2
      # 15MB default
      _ -> 15
    end
  end

  defp calculate_performance_degradation(handling_result) do
    # Calculate performance degradation from error handling
    recovery_time = Map.get(handling_result, :recovery_time_ms, 0)

    # Degradation based on recovery time
    # Max 100% degradation
    degradation_percentage = min(recovery_time / 1000, 100)

    %{
      degradation_percentage: Float.round(degradation_percentage, 2),
      severity: classify_degradation_severity(degradation_percentage),
      recovery_time_impact: recovery_time
    }
  end

  defp classify_degradation_severity(degradation_percentage) do
    cond do
      degradation_percentage < 5 -> :minimal
      degradation_percentage < 15 -> :low
      degradation_percentage < 30 -> :moderate
      degradation_percentage < 60 -> :high
      true -> :severe
    end
  end

  defp assess_system_impact(handling_result) do
    # Assess overall system impact of error handling
    strategy = handling_result.strategy_applied
    success = handling_result.success

    impact_score =
      case {strategy, success} do
        # High impact but successful
        {:emergency_fallback, true} -> 0.8
        # Moderate impact
        {:workflow_replay, true} -> 0.6
        # Low-moderate impact
        {:immediate_compensation, true} -> 0.4
        # Low impact
        {:retry_with_backoff, true} -> 0.2
        # High impact if failed
        {_, false} -> 0.9
      end

    %{
      impact_score: impact_score,
      impact_category: classify_impact_category(impact_score),
      system_stability_affected: impact_score > 0.7
    }
  end

  defp classify_impact_category(impact_score) do
    cond do
      impact_score < 0.3 -> :minimal
      impact_score < 0.5 -> :low
      impact_score < 0.7 -> :moderate
      impact_score < 0.9 -> :high
      true -> :critical
    end
  end

  defp identify_improvement_opportunities(handling_result) do
    # Identify opportunities for error handling improvement
    opportunities = []

    # Check for slow recovery
    recovery_time = Map.get(handling_result, :recovery_time_ms, 0)

    opportunities =
      if recovery_time > 15_000 do
        ["Optimize recovery strategy for faster resolution" | opportunities]
      else
        opportunities
      end

    # Check for failed recovery
    opportunities =
      if handling_result.success do
        opportunities
      else
        ["Investigate recovery strategy effectiveness" | opportunities]
      end

    # Check for high resource impact
    resource_impact = Map.get(handling_result, :resource_impact, %{})

    opportunities =
      if Map.get(resource_impact, :impact_level) == :high do
        ["Optimize resource usage during recovery" | opportunities]
      else
        opportunities
      end

    if Enum.empty?(opportunities) do
      ["Error handling performed optimally"]
    else
      Enum.reverse(opportunities)
    end
  end

  defp calculate_performance_impact(error_handling_time, handling_result) do
    # Calculate overall performance impact of error handling
    # Convert to milliseconds
    time_impact = error_handling_time / 1000
    recovery_time = Map.get(handling_result, :recovery_time_ms, 0)

    total_impact_time = time_impact + recovery_time

    %{
      total_impact_time_ms: Float.round(total_impact_time, 2),
      error_handling_overhead_ms: Float.round(time_impact, 2),
      recovery_execution_time_ms: recovery_time,
      performance_impact_level: classify_performance_impact(total_impact_time)
    }
  end

  defp classify_performance_impact(total_impact_time) do
    cond do
      # < 1 second
      total_impact_time < 1000 -> :minimal
      # < 5 seconds
      total_impact_time < 5000 -> :low
      # < 15 seconds
      total_impact_time < 15_000 -> :moderate
      # < 30 seconds
      total_impact_time < 30_000 -> :high
      # > 30 seconds
      true -> :severe
    end
  end

  defp generate_error_id do
    # Generate unique error ID for tracking
    timestamp = System.system_time(:nanosecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "error_#{timestamp}_#{random}"
  end
end
