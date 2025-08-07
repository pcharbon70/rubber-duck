defmodule RubberDuck.Routing.PipelineRouter do
  @moduledoc """
  Integrates GenStage pipeline with compile-time routing.
  
  This module provides the connection between the batching pipeline
  and the compile-time optimized router, enabling high-throughput
  message processing with back-pressure management.
  """
  
  use RubberDuck.Routing.CompileTimeRouter
  
  alias RubberDuck.Messages.{
    Code,
    AI,
    Project,
    System,
    User
  }
  
  # Define compile-time routes for all message types
  
  # Code messages
  route Code.Analyze, to: RubberDuck.Skills.CodeAnalysisSkill, function: :handle_analyze
  route Code.QualityCheck, to: RubberDuck.Skills.CodeAnalysisSkill, function: :handle_quality_check
  route Code.ImpactAssess, to: RubberDuck.Skills.CodeAnalysisSkill, function: :handle_impact_assess
  route Code.PerformanceAnalyze, to: RubberDuck.Skills.CodeAnalysisSkill, function: :handle_performance_analyze
  route Code.SecurityScan, to: RubberDuck.Skills.CodeAnalysisSkill, function: :handle_security_scan
  
  # AI messages
  route AI.ModelQuery, to: RubberDuck.Skills.AIAssistantSkill, function: :handle_model_query
  route AI.AgentSpawned, to: RubberDuck.Skills.AIAssistantSkill, function: :handle_agent_spawned
  route AI.ModelResponse, to: RubberDuck.Skills.AIAssistantSkill, function: :handle_model_response
  route AI.TrainingCompleted, to: RubberDuck.Skills.AIAssistantSkill, function: :handle_training_completed
  route AI.InferenceRequest, to: RubberDuck.Skills.AIAssistantSkill, function: :handle_inference_request
  
  # Project messages
  route Project.Created, to: RubberDuck.Skills.ProjectManagementSkill, function: :handle_project_created
  route Project.Updated, to: RubberDuck.Skills.ProjectManagementSkill, function: :handle_project_updated
  route Project.HealthChecked, to: RubberDuck.Skills.ProjectManagementSkill, function: :handle_health_checked
  route Project.DependenciesAnalyzed, to: RubberDuck.Skills.ProjectManagementSkill, function: :handle_dependencies_analyzed
  route Project.AlertTriggered, to: RubberDuck.Skills.ProjectManagementSkill, function: :handle_alert_triggered
  
  # System messages
  route System.ResourceThreshold, to: RubberDuck.Skills.MonitoringSkill, function: :handle_resource_threshold
  route System.PerformanceAlert, to: RubberDuck.Skills.MonitoringSkill, function: :handle_performance_alert
  route System.ErrorOccurred, to: RubberDuck.Skills.MonitoringSkill, function: :handle_error_occurred
  route System.HealthCheck, to: RubberDuck.Skills.MonitoringSkill, function: :handle_health_check
  route System.ConfigChanged, to: RubberDuck.Skills.MonitoringSkill, function: :handle_config_changed
  
  # User messages
  route User.SessionStarted, to: RubberDuck.Skills.UserManagementSkill, function: :handle_session_started
  route User.SessionEnded, to: RubberDuck.Skills.UserManagementSkill, function: :handle_session_ended
  route User.PreferenceChanged, to: RubberDuck.Skills.UserManagementSkill, function: :handle_preference_changed
  route User.BehaviorTracked, to: RubberDuck.Skills.UserManagementSkill, function: :handle_behavior_tracked
  route User.FeedbackProvided, to: RubberDuck.Skills.UserManagementSkill, function: :handle_feedback_provided
  
  @doc """
  Routes a message through the pipeline.
  
  This function enqueues the message into the GenStage pipeline
  for batched processing with back-pressure management.
  """
  def route_through_pipeline(message, context \\ %{}) do
    case RubberDuck.Routing.PipelineSupervisor.enqueue(message, context) do
      :ok -> {:ok, :enqueued}
      {:error, :buffer_overflow} = error -> error
      error -> error
    end
  end
  
  @doc """
  Routes a message directly without pipeline buffering.
  
  Uses compile-time optimized dispatch for immediate processing.
  """
  def route_direct(message, context \\ %{}) do
    dispatch(message, context)
  end
  
  @doc """
  Routes a message with priority through the pipeline.
  """
  def route_with_priority(message, context, priority) when priority in [:critical, :high, :normal, :low] do
    enriched_context = Map.put(context, :priority, priority)
    route_through_pipeline(message, enriched_context)
  end
  
  @doc """
  Processes a batch of messages directly.
  
  This is called by the consumer pool to process batches
  using compile-time optimized routing.
  """
  def process_batch(batch) do
    batch
    |> Enum.map(fn {message, context} ->
      {message, dispatch_fast(message, context)}
    end)
  end
end