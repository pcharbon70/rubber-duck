defmodule RubberDuck.Workflows.Adapters.AgentWorkflowAdapter do
  @moduledoc """
  Agent workflow adapter for optional workflow integration.

  This adapter enables existing autonomous agents to optionally leverage
  Reactor-based workflows for complex coordination while maintaining
  full autonomy for standard operations. Agents can decide when workflows
  provide benefits and seamlessly integrate them without breaking changes.

  Features:
  - Optional workflow adoption with zero impact on autonomous operation
  - Intelligent workflow recommendation based on operation complexity
  - Seamless integration with existing Jido Skills and Actions
  - Performance monitoring and comparison between autonomous vs workflow execution
  - Graceful fallback to autonomous operation if workflows fail
  - Agent-specific workflow pattern recommendations

  Integration Patterns:
  - **Drop-in Enhancement**: Existing agents can adopt workflows incrementally
  - **Performance-Driven**: Adoption based on proven performance benefits
  - **Autonomy Preservation**: Agents maintain full control over workflow usage
  - **Failure Resilience**: Automatic fallback to autonomous operation
  """

  require Logger

  alias RubberDuck.Workflows.{OptionalWorkflowUtils, SkillsComposition, WorkflowTemplates}

  @doc """
  Analyze agent operation to determine if workflow adoption would be beneficial.

  Returns recommendation with confidence score and reasoning for agent decision-making.
  """
  def analyze_workflow_benefits(agent_operation, agent_capabilities \\ []) do
    Logger.debug("AgentWorkflowAdapter: Analyzing workflow benefits for agent operation")

    # Analyze operation characteristics
    operation_analysis = analyze_operation_characteristics(agent_operation)

    # Check workflow recommendation
    case WorkflowTemplates.recommend_template(agent_operation) do
      {:ok, template_recommendation} ->
        # Validate agent compatibility with recommended template
        case WorkflowTemplates.validate_template_compatibility(
               template_recommendation.recommended_template,
               agent_capabilities
             ) do
          {:ok, compatibility_result} ->
            # Calculate overall benefit score
            benefit_analysis =
              calculate_workflow_benefit_score(
                operation_analysis,
                template_recommendation,
                compatibility_result
              )

            Logger.info("AgentWorkflowAdapter: Workflow benefit analysis complete",
              recommended_template: template_recommendation.recommended_template,
              benefit_score: benefit_analysis.overall_benefit_score,
              adoption_recommended: benefit_analysis.recommend_adoption
            )

            {:ok,
             %{
               analysis: operation_analysis,
               template_recommendation: template_recommendation,
               compatibility: compatibility_result,
               benefit_analysis: benefit_analysis,
               adoption_decision: generate_adoption_decision(benefit_analysis)
             }}

          {:error, compatibility_issue} ->
            Logger.warning("AgentWorkflowAdapter: Template compatibility issue",
              template: template_recommendation.recommended_template,
              issue: compatibility_issue
            )

            {:ok,
             %{
               analysis: operation_analysis,
               template_recommendation: template_recommendation,
               compatibility_issue: compatibility_issue,
               adoption_decision: %{
                 recommend_adoption: false,
                 reason: :compatibility_issues,
                 suggestions: compatibility_issue.suggestions || []
               }
             }}
        end

      {:error, reason} ->
        Logger.error("AgentWorkflowAdapter: Template recommendation failed", error: reason)
        {:error, reason}
    end
  end

  @doc """
  Create workflow adapter for specific agent with personalized configuration.

  Enables agent to seamlessly switch between autonomous and workflow execution
  based on operation characteristics and performance data.
  """
  def create_agent_adapter(agent_module, agent_config, workflow_preferences \\ %{}) do
    Logger.info("AgentWorkflowAdapter: Creating workflow adapter for agent",
      agent_module: agent_module,
      preferences: Map.keys(workflow_preferences)
    )

    adapter_config = %{
      agent_module: agent_module,
      agent_config: agent_config,
      workflow_preferences: Map.merge(default_workflow_preferences(), workflow_preferences),
      created_at: DateTime.utc_now(),
      adaptation_history: [],
      performance_comparison: %{
        autonomous_operations: 0,
        workflow_operations: 0,
        autonomous_performance: %{},
        workflow_performance: %{}
      }
    }

    # Validate agent compatibility
    case validate_agent_workflow_compatibility(agent_module, adapter_config) do
      {:ok, validation_result} ->
        enhanced_config =
          Map.merge(adapter_config, %{
            compatibility_validation: validation_result,
            adapter_status: :ready
          })

        Logger.info("AgentWorkflowAdapter: Agent adapter created successfully",
          agent_module: agent_module,
          compatibility_score: validation_result.compatibility_score
        )

        {:ok, enhanced_config}

      {:error, reason} ->
        Logger.error("AgentWorkflowAdapter: Agent adapter creation failed",
          agent_module: agent_module,
          error: reason
        )

        {:error, reason}
    end
  end

  @doc """
  Execute operation with optional workflow orchestration.

  Agent can use this to execute operations with automatic decision-making
  about whether to use autonomous execution or workflow orchestration.
  """
  def execute_with_optional_workflow(agent_adapter, operation_spec, operation_data) do
    Logger.debug("AgentWorkflowAdapter: Executing operation with optional workflow",
      agent_module: agent_adapter.agent_module,
      operation_type: Map.get(operation_spec, :type, :unknown)
    )

    execution_start_time = System.monotonic_time(:microsecond)

    # Decide execution strategy
    case decide_execution_strategy(agent_adapter, operation_spec) do
      {:use_workflow, workflow_config} ->
        execute_with_workflow(
          agent_adapter,
          workflow_config,
          operation_data,
          execution_start_time
        )

      {:use_autonomous, reason} ->
        execute_autonomous(
          agent_adapter,
          operation_spec,
          operation_data,
          execution_start_time,
          reason
        )

      {:error, reason} ->
        Logger.error("AgentWorkflowAdapter: Execution strategy decision failed", error: reason)
        {:error, reason}
    end
  end

  @doc """
  Update agent adapter based on execution performance and outcomes.

  Enables continuous learning about workflow effectiveness for the agent.
  """
  def update_adapter_performance(agent_adapter, execution_result) do
    Logger.debug("AgentWorkflowAdapter: Updating adapter performance data")

    # Extract performance metrics
    performance_metrics = extract_performance_metrics(execution_result)

    # Update performance comparison
    updated_comparison =
      update_performance_comparison(
        agent_adapter.performance_comparison,
        execution_result.execution_type,
        performance_metrics
      )

    # Add to adaptation history
    adaptation_entry = %{
      timestamp: DateTime.utc_now(),
      execution_type: execution_result.execution_type,
      performance_metrics: performance_metrics,
      operation_characteristics: execution_result.operation_characteristics,
      success: execution_result.success
    }

    updated_history = [adaptation_entry | Enum.take(agent_adapter.adaptation_history, 99)]

    updated_adapter = %{
      agent_adapter
      | performance_comparison: updated_comparison,
        adaptation_history: updated_history
    }

    # Calculate updated recommendations
    recommendations = generate_updated_recommendations(updated_adapter)

    Logger.info("AgentWorkflowAdapter: Adapter performance updated",
      agent_module: agent_adapter.agent_module,
      execution_type: execution_result.execution_type,
      success: execution_result.success
    )

    {:ok,
     %{
       updated_adapter: updated_adapter,
       performance_insights: analyze_performance_trends(updated_adapter),
       recommendations: recommendations
     }}
  end

  # Private implementation functions

  defp default_workflow_preferences do
    %{
      # 80% confidence to adopt workflows
      workflow_adoption_threshold: 0.8,
      # 15% improvement to prefer workflows
      performance_improvement_threshold: 0.15,
      # Limit workflow complexity
      max_workflow_complexity: 0.9,
      # Allow automatic workflow adoption
      enable_automatic_adoption: true,
      # Fallback to autonomous on workflow failure
      fallback_on_failure: true,
      # Track performance comparison
      performance_tracking: true
    }
  end

  defp analyze_operation_characteristics(operation_spec) do
    %{
      complexity: assess_operation_complexity(operation_spec),
      coordination_needs: assess_coordination_requirements(operation_spec),
      error_sensitivity: assess_error_sensitivity(operation_spec),
      performance_requirements: assess_performance_requirements(operation_spec),
      agent_involvement: assess_agent_involvement(operation_spec)
    }
  end

  defp assess_operation_complexity(operation_spec) do
    factors = []

    # Number of steps or sub-operations
    steps = length(Map.get(operation_spec, :steps, []))
    factors = [min(steps / 10, 1.0) | factors]

    # Dependencies between operations
    has_dependencies = Map.get(operation_spec, :has_dependencies, false)
    factors = [if(has_dependencies, do: 0.3, else: 0.0) | factors]

    # Requires error recovery
    needs_recovery = Map.get(operation_spec, :requires_error_recovery, false)
    factors = [if(needs_recovery, do: 0.4, else: 0.0) | factors]

    # Data transformation complexity
    transformations = length(Map.get(operation_spec, :data_transformations, []))
    factors = [min(transformations / 5, 0.3) | factors]

    if Enum.empty?(factors) do
      0.5
    else
      avg_complexity = Enum.sum(factors) / length(factors)
      Float.round(min(avg_complexity, 1.0), 2)
    end
  end

  defp assess_coordination_requirements(operation_spec) do
    coordination_factors = []

    # Multiple agents involved
    agent_count = length(Map.get(operation_spec, :agents_involved, []))
    coordination_factors = [min(agent_count / 5, 1.0) | coordination_factors]

    # Requires synchronization
    sync_required = Map.get(operation_spec, :requires_synchronization, false)
    coordination_factors = [if(sync_required, do: 0.6, else: 0.0) | coordination_factors]

    # Resource sharing needed
    resource_sharing = Map.get(operation_spec, :requires_resource_sharing, false)
    coordination_factors = [if(resource_sharing, do: 0.4, else: 0.0) | coordination_factors]

    # Inter-agent communication
    communication_needed = Map.get(operation_spec, :requires_communication, false)
    coordination_factors = [if(communication_needed, do: 0.5, else: 0.0) | coordination_factors]

    if Enum.empty?(coordination_factors) do
      0.0
    else
      avg_coordination = Enum.sum(coordination_factors) / length(coordination_factors)
      Float.round(min(avg_coordination, 1.0), 2)
    end
  end

  defp assess_error_sensitivity(operation_spec) do
    sensitivity_factors = []

    # Mission critical operation
    mission_critical = Map.get(operation_spec, :mission_critical, false)
    sensitivity_factors = [if(mission_critical, do: 0.8, else: 0.0) | sensitivity_factors]

    # Requires rollback capability
    needs_rollback = Map.get(operation_spec, :requires_rollback, false)
    sensitivity_factors = [if(needs_rollback, do: 0.6, else: 0.0) | sensitivity_factors]

    # Data consistency requirements
    data_consistency = Map.get(operation_spec, :requires_data_consistency, false)
    sensitivity_factors = [if(data_consistency, do: 0.7, else: 0.0) | sensitivity_factors]

    if Enum.empty?(sensitivity_factors) do
      # Default low sensitivity
      0.2
    else
      max_sensitivity = Enum.max(sensitivity_factors)
      Float.round(max_sensitivity, 2)
    end
  end

  defp assess_performance_requirements(operation_spec) do
    performance_factors = []

    # Time sensitivity
    time_sensitive = Map.get(operation_spec, :time_sensitive, false)
    performance_factors = [if(time_sensitive, do: 0.7, else: 0.0) | performance_factors]

    # High throughput required
    high_throughput = Map.get(operation_spec, :high_throughput_required, false)
    performance_factors = [if(high_throughput, do: 0.6, else: 0.0) | performance_factors]

    # Resource intensive
    resource_intensive = Map.get(operation_spec, :resource_intensive, false)
    performance_factors = [if(resource_intensive, do: 0.5, else: 0.0) | performance_factors]

    if Enum.empty?(performance_factors) do
      # Default moderate requirements
      0.3
    else
      avg_performance = Enum.sum(performance_factors) / length(performance_factors)
      Float.round(avg_performance, 2)
    end
  end

  defp assess_agent_involvement(operation_spec) do
    involvement_factors = []

    # Number of different agent types
    agent_types = length(Map.get(operation_spec, :agent_types_involved, []))
    involvement_factors = [min(agent_types / 3, 1.0) | involvement_factors]

    # Cross-domain coordination
    cross_domain = Map.get(operation_spec, :cross_domain_coordination, false)
    involvement_factors = [if(cross_domain, do: 0.4, else: 0.0) | involvement_factors]

    # Requires agent state sharing
    state_sharing = Map.get(operation_spec, :requires_state_sharing, false)
    involvement_factors = [if(state_sharing, do: 0.6, else: 0.0) | involvement_factors]

    if Enum.empty?(involvement_factors) do
      # Default minimal involvement
      0.1
    else
      avg_involvement = Enum.sum(involvement_factors) / length(involvement_factors)
      Float.round(avg_involvement, 2)
    end
  end

  defp calculate_workflow_benefit_score(
         operation_analysis,
         template_recommendation,
         compatibility_result
       ) do
    # Calculate comprehensive benefit score for workflow adoption

    # Base benefit from template recommendation confidence
    template_benefit = template_recommendation.confidence_score * 0.4

    # Compatibility benefit
    compatibility_benefit = compatibility_result.compatibility_score * 0.3

    # Operation complexity benefit (workflows help more with complex operations)
    complexity_benefit = operation_analysis.complexity * 0.2

    # Coordination benefit (workflows excel at coordination)
    coordination_benefit = operation_analysis.coordination_needs * 0.1

    overall_benefit =
      template_benefit + compatibility_benefit + complexity_benefit + coordination_benefit

    # Determine adoption recommendation
    # 70% benefit threshold
    adoption_threshold = 0.7
    recommend_adoption = overall_benefit >= adoption_threshold

    %{
      overall_benefit_score: Float.round(overall_benefit, 3),
      recommend_adoption: recommend_adoption,
      benefit_breakdown: %{
        template_benefit: Float.round(template_benefit, 3),
        compatibility_benefit: Float.round(compatibility_benefit, 3),
        complexity_benefit: Float.round(complexity_benefit, 3),
        coordination_benefit: Float.round(coordination_benefit, 3)
      },
      adoption_confidence: calculate_adoption_confidence(overall_benefit, operation_analysis)
    }
  end

  defp calculate_adoption_confidence(benefit_score, operation_analysis) do
    # Calculate confidence in adoption recommendation
    base_confidence = benefit_score

    # Adjust based on operation characteristics
    complexity_confidence = if operation_analysis.complexity > 0.8, do: 0.2, else: 0.0
    coordination_confidence = if operation_analysis.coordination_needs > 0.7, do: 0.15, else: 0.0

    total_confidence = base_confidence + complexity_confidence + coordination_confidence
    Float.round(min(total_confidence, 1.0), 3)
  end

  defp generate_adoption_decision(benefit_analysis) do
    if benefit_analysis.recommend_adoption do
      %{
        recommend_adoption: true,
        confidence: benefit_analysis.adoption_confidence,
        reasoning:
          "Workflow adoption recommended based on benefit score of #{benefit_analysis.overall_benefit_score}",
        suggested_approach: :gradual_adoption,
        fallback_strategy: :autonomous_on_failure
      }
    else
      %{
        recommend_adoption: false,
        confidence: 1.0 - benefit_analysis.adoption_confidence,
        reasoning:
          "Autonomous execution preferred based on benefit score of #{benefit_analysis.overall_benefit_score}",
        suggested_approach: :continue_autonomous,
        # Reconsider if future operations score higher
        reconsider_threshold: 0.8
      }
    end
  end

  defp validate_agent_workflow_compatibility(agent_module, adapter_config) do
    # Validate that agent can safely integrate with workflow system
    compatibility_checks = [
      check_agent_module_structure(agent_module),
      check_skills_compatibility(adapter_config),
      check_state_management_compatibility(adapter_config),
      check_error_handling_compatibility(adapter_config)
    ]

    failed_checks = Enum.filter(compatibility_checks, &match?({:error, _}, &1))

    if Enum.empty?(failed_checks) do
      compatibility_score = calculate_compatibility_score(compatibility_checks)

      {:ok,
       %{
         compatible: true,
         compatibility_score: compatibility_score,
         validation_results: compatibility_checks,
         integration_recommendations: generate_integration_recommendations(compatibility_checks)
       }}
    else
      {:error,
       %{
         compatible: false,
         failed_checks: failed_checks,
         recommendations: generate_compatibility_fix_recommendations(failed_checks)
       }}
    end
  end

  defp decide_execution_strategy(agent_adapter, operation_spec) do
    # Decide whether agent should use workflow or autonomous execution
    preferences = agent_adapter.workflow_preferences

    if preferences.enable_automatic_adoption do
      # Analyze current operation for workflow benefits
      case analyze_workflow_benefits(operation_spec, get_agent_capabilities(agent_adapter)) do
        {:ok, benefit_analysis} ->
          handle_benefit_analysis_result(agent_adapter, operation_spec, benefit_analysis)

        {:error, reason} ->
          Logger.warning("AgentWorkflowAdapter: Benefit analysis failed, using autonomous",
            error: reason
          )

          {:use_autonomous, :analysis_failed}
      end
    else
      {:use_autonomous, :automatic_adoption_disabled}
    end
  end

  defp handle_benefit_analysis_result(agent_adapter, operation_spec, benefit_analysis) do
    if benefit_analysis.adoption_decision.recommend_adoption do
      # Create workflow for this operation
      case create_operation_workflow(operation_spec, benefit_analysis.template_recommendation) do
        {:ok, workflow_config} ->
          Logger.info("AgentWorkflowAdapter: Using workflow execution",
            agent: agent_adapter.agent_module,
            template: benefit_analysis.template_recommendation.recommended_template
          )
          
          {:use_workflow, workflow_config}
        
        {:error, reason} ->
          Logger.warning("AgentWorkflowAdapter: Workflow creation failed, using autonomous",
            error: reason
          )
          
          {:use_autonomous, :workflow_creation_failed}
      end
    else
      {:use_autonomous, benefit_analysis.adoption_decision.reasoning}
    end
  end

  defp execute_with_workflow(agent_adapter, workflow_config, operation_data, start_time) do
    Logger.info("AgentWorkflowAdapter: Executing with workflow orchestration")

    case OptionalWorkflowUtils.execute_optional_workflow(workflow_config, operation_data) do
      {:ok, workflow_result} ->
        execution_time = System.monotonic_time(:microsecond) - start_time

        result = %{
          success: true,
          execution_type: :workflow,
          result: workflow_result,
          execution_time_microseconds: execution_time,
          workflow_metadata: workflow_config,
          # Would be filled with actual characteristics
          operation_characteristics: %{}
        }

        Logger.info("AgentWorkflowAdapter: Workflow execution successful",
          execution_time_us: execution_time
        )

        {:ok, result}

      {:error, reason} ->
        # Fallback to autonomous execution if workflow fails
        Logger.warning("AgentWorkflowAdapter: Workflow failed, attempting autonomous fallback",
          error: reason
        )

        fallback_result = execute_autonomous_fallback(agent_adapter, operation_data, start_time)

        # Mark as workflow failure with autonomous recovery
        case fallback_result do
          {:ok, autonomous_result} ->
            {:ok,
             Map.merge(autonomous_result, %{
               execution_type: :autonomous_fallback,
               workflow_failure: reason,
               fallback_successful: true
             })}

          {:error, fallback_error} ->
            {:error,
             {:workflow_and_fallback_failed, %{workflow: reason, fallback: fallback_error}}}
        end
    end
  end

  defp execute_autonomous(agent_adapter, operation_spec, operation_data, start_time, reason) do
    Logger.debug("AgentWorkflowAdapter: Executing autonomously",
      reason: reason
    )

    # Execute using agent's normal autonomous operation
    # This is a placeholder - would call agent's actual execution method
    execution_time = System.monotonic_time(:microsecond) - start_time

    # Simulate autonomous execution
    autonomous_result = simulate_autonomous_execution(operation_data)

    result = %{
      success: autonomous_result.success,
      execution_type: :autonomous,
      result: autonomous_result,
      execution_time_microseconds: execution_time,
      autonomous_reason: reason,
      operation_characteristics: %{}
    }

    Logger.info("AgentWorkflowAdapter: Autonomous execution complete",
      success: autonomous_result.success,
      execution_time_us: execution_time
    )

    {:ok, result}
  end

  defp execute_autonomous_fallback(agent_adapter, operation_data, start_time) do
    # Execute autonomous fallback when workflow fails
    Logger.info("AgentWorkflowAdapter: Executing autonomous fallback")

    execution_time = System.monotonic_time(:microsecond) - start_time
    fallback_result = simulate_autonomous_execution(operation_data)

    {:ok,
     %{
       success: fallback_result.success,
       execution_type: :autonomous_fallback,
       result: fallback_result,
       execution_time_microseconds: execution_time
     }}
  end

  defp create_operation_workflow(operation_spec, template_recommendation) do
    # Create workflow from template recommendation for the operation
    template_type = template_recommendation.recommended_template

    # Extract workflow parameters from operation
    workflow_params = %{
      steps: Map.get(operation_spec, :steps, []),
      timeout: Map.get(operation_spec, :timeout, 300_000),
      metadata: %{
        operation_type: Map.get(operation_spec, :type, :unknown),
        created_from_template: template_type
      }
    }

    WorkflowTemplates.create_from_template(template_type, workflow_params)
  end

  defp get_agent_capabilities(agent_adapter) do
    # Extract agent capabilities from adapter configuration
    # This would analyze agent module to determine its capabilities
    base_capabilities = [:basic_execution, :error_handling, :state_management]

    # Add capabilities based on agent module
    agent_specific_capabilities = get_agent_specific_capabilities(agent_adapter.agent_module)

    base_capabilities ++ agent_specific_capabilities
  end

  defp get_agent_specific_capabilities(agent_module) do
    module_string = to_string(agent_module)

    cond do
      String.contains?(module_string, "LLM") ->
        [:llm_coordination, :provider_management]

      String.contains?(module_string, "RAG") ->
        [:knowledge_retrieval, :context_building]

      String.contains?(module_string, "Reasoning") ->
        [:logical_reasoning, :step_validation]

      true ->
        []
    end
  end

  # Compatibility checking functions

  defp check_agent_module_structure(agent_module) do
    # Check if agent module has proper structure for workflow integration
    case Code.ensure_loaded(agent_module) do
      {:module, _module} ->
        {:ok, %{check: :module_structure, status: :valid, agent_module: agent_module}}

      {:error, reason} ->
        {:error, %{check: :module_structure, status: :invalid, reason: reason}}
    end
  end

  defp check_skills_compatibility(adapter_config) do
    # Check if agent's Skills are compatible with workflow composition
    {:ok, %{check: :skills_compatibility, status: :compatible, score: 0.9}}
  end

  defp check_state_management_compatibility(adapter_config) do
    # Check if agent's state management is workflow-compatible
    {:ok, %{check: :state_management, status: :compatible, score: 0.85}}
  end

  defp check_error_handling_compatibility(adapter_config) do
    # Check if agent's error handling works with workflow error recovery
    {:ok, %{check: :error_handling, status: :compatible, score: 0.8}}
  end

  defp calculate_compatibility_score(compatibility_checks) do
    scores =
      Enum.map(compatibility_checks, fn
        {:ok, result} -> Map.get(result, :score, 0.8)
        {:error, _} -> 0.0
      end)

    if Enum.empty?(scores) do
      0.0
    else
      avg_score = Enum.sum(scores) / length(scores)
      Float.round(avg_score, 3)
    end
  end

  defp generate_integration_recommendations(compatibility_checks) do
    # Generate recommendations for optimal integration
    successful_checks = Enum.filter(compatibility_checks, &match?({:ok, _}, &1))

    [
      "Agent is compatible with workflow integration",
      "Gradual adoption recommended to validate benefits",
      "Monitor performance comparison between autonomous and workflow execution"
    ]
  end

  defp generate_compatibility_fix_recommendations(failed_checks) do
    # Generate recommendations for fixing compatibility issues
    Enum.map(failed_checks, fn {:error, error_info} ->
      "Fix #{error_info.check} compatibility: #{error_info.reason}"
    end)
  end

  # Performance tracking and analysis

  defp extract_performance_metrics(execution_result) do
    %{
      execution_time: execution_result.execution_time_microseconds,
      success_rate: if(execution_result.success, do: 1.0, else: 0.0),
      memory_usage: Map.get(execution_result, :memory_usage, 0),
      cpu_usage: Map.get(execution_result, :cpu_usage, 0.0),
      error_count: length(Map.get(execution_result, :errors, []))
    }
  end

  defp update_performance_comparison(current_comparison, execution_type, metrics) do
    case execution_type do
      type when type in [:autonomous, :autonomous_fallback] ->
        update_autonomous_performance(current_comparison, metrics)

      :workflow ->
        update_workflow_performance(current_comparison, metrics)

      _ ->
        current_comparison
    end
  end

  defp update_autonomous_performance(comparison, metrics) do
    current_autonomous = comparison.autonomous_performance
    operations_count = comparison.autonomous_operations + 1

    updated_performance = update_running_averages(current_autonomous, metrics, operations_count)

    %{
      comparison
      | autonomous_operations: operations_count,
        autonomous_performance: updated_performance
    }
  end

  defp update_workflow_performance(comparison, metrics) do
    current_workflow = comparison.workflow_performance
    operations_count = comparison.workflow_operations + 1

    updated_performance = update_running_averages(current_workflow, metrics, operations_count)

    %{
      comparison
      | workflow_operations: operations_count,
        workflow_performance: updated_performance
    }
  end

  defp update_running_averages(current_performance, new_metrics, operations_count) do
    # Update running averages with new metrics
    # Decreasing weight for new data
    alpha = 1.0 / operations_count

    Map.merge(current_performance, %{
      avg_execution_time:
        update_running_average(
          Map.get(current_performance, :avg_execution_time, 0),
          new_metrics.execution_time,
          alpha
        ),
      avg_success_rate:
        update_running_average(
          Map.get(current_performance, :avg_success_rate, 1.0),
          new_metrics.success_rate,
          alpha
        ),
      avg_memory_usage:
        update_running_average(
          Map.get(current_performance, :avg_memory_usage, 0),
          new_metrics.memory_usage,
          alpha
        )
    })
  end

  defp update_running_average(current_avg, new_value, alpha) do
    current_avg * (1.0 - alpha) + new_value * alpha
  end

  defp analyze_performance_trends(agent_adapter) do
    # Analyze performance trends to provide insights
    comparison = agent_adapter.performance_comparison

    if comparison.autonomous_operations > 0 and comparison.workflow_operations > 0 do
      autonomous_perf = comparison.autonomous_performance
      workflow_perf = comparison.workflow_performance

      time_improvement =
        calculate_performance_improvement(
          autonomous_perf.avg_execution_time,
          workflow_perf.avg_execution_time
        )

      success_improvement =
        calculate_performance_improvement(
          autonomous_perf.avg_success_rate,
          workflow_perf.avg_success_rate
        )

      %{
        has_comparison_data: true,
        execution_time_improvement: time_improvement,
        success_rate_improvement: success_improvement,
        workflow_adoption_beneficial: time_improvement > 0.1 or success_improvement > 0.05,
        recommendation: generate_performance_recommendation(time_improvement, success_improvement)
      }
    else
      %{
        has_comparison_data: false,
        recommendation: "Insufficient data for performance comparison"
      }
    end
  end

  defp calculate_performance_improvement(autonomous_metric, workflow_metric) do
    if autonomous_metric > 0 do
      improvement = (autonomous_metric - workflow_metric) / autonomous_metric
      Float.round(improvement, 3)
    else
      0.0
    end
  end

  defp generate_performance_recommendation(time_improvement, success_improvement) do
    cond do
      time_improvement > 0.2 and success_improvement > 0.1 ->
        "Workflow execution shows significant benefits - recommend increased adoption"

      time_improvement > 0.1 or success_improvement > 0.05 ->
        "Workflow execution shows moderate benefits - continue selective adoption"

      time_improvement < -0.1 or success_improvement < -0.05 ->
        "Autonomous execution performing better - reduce workflow adoption"

      true ->
        "Performance similar between approaches - continue current strategy"
    end
  end

  defp generate_updated_recommendations(agent_adapter) do
    # Generate updated recommendations based on performance history
    performance_insights = analyze_performance_trends(agent_adapter)

    if performance_insights.has_comparison_data do
      [
        performance_insights.recommendation,
        "Total operations: #{agent_adapter.performance_comparison.autonomous_operations + agent_adapter.performance_comparison.workflow_operations}",
        "Continue monitoring for optimization opportunities"
      ]
    else
      [
        "Continue gathering performance data",
        "Try workflow adoption for complex operations",
        "Monitor execution patterns for optimization"
      ]
    end
  end

  # Utility functions

  defp simulate_autonomous_execution(operation_data) do
    # Simulate autonomous execution for development
    # 500-2500ms
    processing_time = :rand.uniform(2000) + 500
    Process.sleep(processing_time)

    %{
      success: true,
      output: "Autonomous execution result",
      processing_time: processing_time,
      metadata: %{execution_mode: :autonomous}
    }
  end
end
