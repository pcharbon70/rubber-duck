defmodule RubberDuck.Workflows.WorkflowTemplates do
  @moduledoc """
  Workflow template system for common agent coordination patterns.

  This module provides pre-built workflow templates that agents can optionally
  use for complex coordination tasks. Templates encapsulate common patterns
  like sequential processing, parallel execution, and error recovery.

  Features:
  - Pre-built templates for common coordination patterns
  - Skills-based workflow composition preserving agent autonomy
  - Integration with existing Jido Skills and Actions
  - Customizable templates with parameter injection
  - Performance-optimized patterns for specific use cases
  - Error recovery and compensation patterns built-in

  Template Categories:
  - **Sequential Processing**: Step-by-step coordination with dependencies
  - **Parallel Execution**: Concurrent operations with synchronization
  - **Orchestrator-Workers**: Central coordinator with specialized workers
  - **Error Recovery**: Sophisticated rollback and compensation patterns
  """

  require Logger

  alias RubberDuck.Workflows.{OptionalWorkflowUtils, ReactorConfig}

  # Pre-defined workflow templates
  @workflow_templates %{
    sequential_processing: %{
      description: "Step-by-step processing with error handling",
      pattern: :sequential,
      use_cases: [:feature_implementation, :data_processing, :validation_pipeline],
      # 5 minutes
      default_timeout: 300_000,
      compensation_strategy: :rollback_on_error,
      middleware: [:telemetry, :error_handling, :timeout_management]
    },
    parallel_execution: %{
      description: "Concurrent execution with result aggregation",
      pattern: :parallel,
      use_cases: [:batch_processing, :concurrent_analysis, :multi_provider_requests],
      # 3 minutes
      default_timeout: 180_000,
      compensation_strategy: :partial_rollback,
      middleware: [:telemetry, :error_handling, :resource_cleanup]
    },
    orchestrator_workers: %{
      description: "Central orchestrator coordinating specialized workers",
      pattern: :orchestrator_workers,
      use_cases: [:complex_rag_pipeline, :multi_agent_coordination, :provider_orchestration],
      # 10 minutes
      default_timeout: 600_000,
      compensation_strategy: :coordinator_managed,
      middleware: [:telemetry, :error_handling, :timeout_management, :resource_cleanup]
    },
    error_recovery: %{
      description: "Sophisticated error recovery with compensation",
      pattern: :error_recovery,
      use_cases: [:mission_critical_operations, :transactional_workflows, :data_consistency],
      # 15 minutes
      default_timeout: 900_000,
      compensation_strategy: :full_compensation,
      middleware: [:telemetry, :error_handling, :timeout_management, :resource_cleanup]
    },
    rag_orchestration: %{
      description: "RAG pipeline workflow optimization",
      pattern: :rag_pipeline,
      use_cases: [:knowledge_retrieval, :document_processing, :context_building],
      # 4 minutes
      default_timeout: 240_000,
      compensation_strategy: :pipeline_rollback,
      middleware: [:telemetry, :error_handling, :timeout_management]
    },
    provider_coordination: %{
      description: "Multi-provider coordination with fallbacks",
      pattern: :provider_coordination,
      use_cases: [:llm_requests, :embedding_generation, :quality_assessment],
      # 2 minutes
      default_timeout: 120_000,
      compensation_strategy: :provider_fallback,
      middleware: [:telemetry, :error_handling, :resource_cleanup]
    }
  }

  @doc """
  Get available workflow templates.
  """
  def available_templates do
    Map.keys(@workflow_templates)
  end

  @doc """
  Get template definition for a specific template type.
  """
  def get_template(template_type) do
    case Map.get(@workflow_templates, template_type) do
      nil -> {:error, {:unknown_template, template_type}}
      template -> {:ok, template}
    end
  end

  @doc """
  Create a workflow from a template with custom parameters.

  Agents can use this to create workflows based on proven patterns
  while customizing for their specific needs.
  """
  def create_from_template(template_type, custom_params \\ %{}) do
    Logger.debug("WorkflowTemplates: Creating workflow from template",
      template_type: template_type,
      custom_params_count: map_size(custom_params)
    )

    with {:ok, template} <- get_template(template_type),
         {:ok, workflow_spec} <- build_workflow_from_template(template, custom_params),
         {:ok, workflow_config} <- OptionalWorkflowUtils.create_optional_workflow(workflow_spec) do
      Logger.info("WorkflowTemplates: Workflow created from template",
        template_type: template_type,
        workflow_id: workflow_config.workflow_id
      )

      {:ok,
       %{
         workflow_config: workflow_config,
         template_used: template_type,
         template_metadata: template,
         customizations_applied: extract_customizations(custom_params, template)
       }}
    else
      {:error, reason} ->
        Logger.error("WorkflowTemplates: Failed to create workflow from template",
          template_type: template_type,
          error: reason
        )

        {:error, reason}
    end
  end

  @doc """
  Recommend optimal template for a given operation specification.

  Analyzes operation requirements and suggests the most suitable template.
  """
  def recommend_template(operation_spec) do
    Logger.debug("WorkflowTemplates: Analyzing operation for template recommendation")

    # Analyze operation characteristics
    operation_analysis = analyze_operation_characteristics(operation_spec)

    # Score each template for suitability
    template_scores =
      Enum.map(@workflow_templates, fn {template_type, template} ->
        suitability_score = calculate_template_suitability(operation_analysis, template)
        {template_type, suitability_score}
      end)

    # Find best match
    {best_template, best_score} = Enum.max_by(template_scores, &elem(&1, 1))

    recommendation = %{
      recommended_template: best_template,
      confidence_score: best_score,
      operation_analysis: operation_analysis,
      template_scores: Map.new(template_scores),
      reasoning: generate_recommendation_reasoning(best_template, best_score, operation_analysis)
    }

    Logger.info("WorkflowTemplates: Template recommendation generated",
      recommended: best_template,
      confidence: best_score
    )

    {:ok, recommendation}
  end

  @doc """
  Validate template compatibility with agent capabilities.

  Ensures agent can successfully use the recommended template.
  """
  def validate_template_compatibility(template_type, agent_capabilities) do
    case get_template(template_type) do
      {:ok, template} ->
        compatibility_check = check_agent_compatibility(template, agent_capabilities)

        if compatibility_check.compatible do
          {:ok,
           %{
             compatible: true,
             template: template_type,
             compatibility_score: compatibility_check.score,
             recommendations: compatibility_check.recommendations
           }}
        else
          {:error,
           %{
             compatible: false,
             template: template_type,
             issues: compatibility_check.issues,
             suggestions: compatibility_check.suggestions
           }}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private implementation functions

  defp build_workflow_from_template(template, custom_params) do
    # Build workflow specification from template and customizations
    base_workflow_spec = %{
      type: template.pattern,
      steps: build_template_steps(template.pattern, custom_params),
      compensation_strategy: template.compensation_strategy,
      error_handling: :comprehensive,
      timeout: Map.get(custom_params, :timeout, template.default_timeout),
      middleware: template.middleware
    }

    # Apply customizations
    customized_spec = apply_template_customizations(base_workflow_spec, custom_params)

    {:ok, customized_spec}
  end

  defp build_template_steps(pattern, custom_params) do
    case pattern do
      :sequential ->
        build_sequential_steps(custom_params)

      :parallel ->
        build_parallel_steps(custom_params)

      :orchestrator_workers ->
        build_orchestrator_worker_steps(custom_params)

      :error_recovery ->
        build_error_recovery_steps(custom_params)

      :rag_pipeline ->
        build_rag_pipeline_steps(custom_params)

      :provider_coordination ->
        build_provider_coordination_steps(custom_params)

      _ ->
        # Default empty steps
        []
    end
  end

  defp build_sequential_steps(custom_params) do
    # Build sequential processing steps
    steps = Map.get(custom_params, :steps, [])

    if Enum.empty?(steps) do
      # Default sequential steps
      [
        %{name: :initialize, action: :setup_context},
        %{name: :process, action: :execute_main_logic},
        %{name: :validate, action: :validate_results},
        %{name: :finalize, action: :cleanup_and_complete}
      ]
    else
      # Use provided steps with sequential dependencies
      steps
      |> Enum.with_index()
      |> Enum.map(fn {step, index} ->
        Map.merge(step, %{
          sequence: index,
          depends_on: if(index > 0, do: [index - 1], else: [])
        })
      end)
    end
  end

  defp build_parallel_steps(custom_params) do
    # Build parallel execution steps
    concurrent_tasks = Map.get(custom_params, :concurrent_tasks, [])

    if Enum.empty?(concurrent_tasks) do
      # Default parallel steps
      [
        %{name: :initialize, action: :setup_parallel_context},
        %{name: :task_1, action: :execute_task_1, parallel_group: :main},
        %{name: :task_2, action: :execute_task_2, parallel_group: :main},
        %{name: :task_3, action: :execute_task_3, parallel_group: :main},
        %{name: :aggregate, action: :combine_results, depends_on: [:task_1, :task_2, :task_3]}
      ]
    else
      # Build parallel steps from provided tasks
      initialize_step = %{name: :initialize, action: :setup_parallel_context}

      parallel_steps =
        concurrent_tasks
        |> Enum.with_index()
        |> Enum.map(fn {task, index} ->
          Map.merge(task, %{
            name: String.to_atom("parallel_task_#{index}"),
            parallel_group: :concurrent_execution
          })
        end)

      aggregate_step = %{
        name: :aggregate,
        action: :combine_parallel_results,
        depends_on: Enum.map(parallel_steps, &Map.get(&1, :name))
      }

      [initialize_step] ++ parallel_steps ++ [aggregate_step]
    end
  end

  defp build_orchestrator_worker_steps(custom_params) do
    # Build orchestrator-worker pattern steps
    workers = Map.get(custom_params, :workers, [:worker_1, :worker_2])

    [
      %{name: :orchestrator_init, action: :initialize_orchestrator},
      %{name: :distribute_work, action: :distribute_to_workers, workers: workers},
      %{name: :coordinate_workers, action: :coordinate_execution, workers: workers},
      %{name: :collect_results, action: :collect_worker_results, workers: workers},
      %{name: :orchestrator_finalize, action: :finalize_coordination}
    ]
  end

  defp build_error_recovery_steps(custom_params) do
    # Build error recovery pattern steps
    [
      %{name: :setup_checkpoints, action: :create_recovery_points},
      %{name: :execute_with_monitoring, action: :monitored_execution},
      %{name: :error_detection, action: :detect_and_classify_errors},
      %{name: :compensation_execution, action: :execute_compensation},
      %{name: :recovery_validation, action: :validate_recovery_success}
    ]
  end

  defp build_rag_pipeline_steps(custom_params) do
    # Build RAG-specific workflow steps
    [
      %{name: :query_analysis, action: :analyze_query_intent},
      %{name: :embedding_generation, action: :generate_query_embedding},
      %{name: :retrieval_coordination, action: :coordinate_multi_retrieval},
      %{name: :context_building, action: :build_intelligent_context},
      %{name: :response_generation, action: :generate_rag_response},
      %{name: :quality_validation, action: :validate_response_quality}
    ]
  end

  defp build_provider_coordination_steps(custom_params) do
    # Build provider coordination steps
    providers = Map.get(custom_params, :providers, [:openai, :anthropic])

    [
      %{name: :provider_analysis, action: :analyze_provider_capabilities},
      %{name: :request_distribution, action: :distribute_to_providers, providers: providers},
      %{name: :response_collection, action: :collect_provider_responses},
      %{name: :quality_comparison, action: :compare_response_quality},
      %{name: :result_selection, action: :select_optimal_response}
    ]
  end

  defp apply_template_customizations(base_spec, custom_params) do
    # Apply custom parameters to base template specification
    customizations = [
      apply_timeout_customization(base_spec, custom_params),
      apply_middleware_customization(base_spec, custom_params),
      apply_step_customization(base_spec, custom_params),
      apply_metadata_customization(base_spec, custom_params)
    ]

    Enum.reduce(customizations, base_spec, fn customization, acc_spec ->
      Map.merge(acc_spec, customization)
    end)
  end

  defp apply_timeout_customization(base_spec, custom_params) do
    case Map.get(custom_params, :custom_timeout) do
      nil -> %{}
      timeout -> %{timeout: timeout}
    end
  end

  defp apply_middleware_customization(base_spec, custom_params) do
    case Map.get(custom_params, :additional_middleware) do
      nil -> %{}
      additional -> %{middleware: base_spec.middleware ++ additional}
    end
  end

  defp apply_step_customization(base_spec, custom_params) do
    case Map.get(custom_params, :custom_steps) do
      nil -> %{}
      steps -> %{steps: steps}
    end
  end

  defp apply_metadata_customization(base_spec, custom_params) do
    case Map.get(custom_params, :metadata) do
      nil -> %{}
      metadata -> %{metadata: metadata}
    end
  end

  # Template recommendation logic

  defp analyze_operation_characteristics(operation_spec) do
    %{
      complexity: assess_operation_complexity(operation_spec),
      concurrency_needs: assess_concurrency_needs(operation_spec),
      error_sensitivity: assess_error_sensitivity(operation_spec),
      coordination_requirements: assess_coordination_requirements(operation_spec),
      performance_requirements: assess_performance_requirements(operation_spec)
    }
  end

  defp assess_operation_complexity(operation_spec) do
    factors = []

    # Number of steps
    step_count = length(Map.get(operation_spec, :steps, []))
    factors = [min(step_count / 10, 1.0) | factors]

    # Dependencies between steps
    has_dependencies = Map.get(operation_spec, :has_dependencies, false)
    factors = [if(has_dependencies, do: 0.3, else: 0.0) | factors]

    # Error recovery requirements
    needs_recovery = Map.get(operation_spec, :requires_error_recovery, false)
    factors = [if(needs_recovery, do: 0.4, else: 0.0) | factors]

    if Enum.empty?(factors) do
      # Default moderate complexity
      0.5
    else
      avg_complexity = Enum.sum(factors) / length(factors)
      min(avg_complexity, 1.0)
    end
  end

  defp assess_concurrency_needs(operation_spec) do
    parallel_tasks = length(Map.get(operation_spec, :parallel_tasks, []))
    concurrent_agents = length(Map.get(operation_spec, :concurrent_agents, []))

    # Normalize concurrency indicators
    concurrency_score = (min(parallel_tasks / 5, 1.0) + min(concurrent_agents / 3, 1.0)) / 2
    Float.round(concurrency_score, 2)
  end

  defp assess_error_sensitivity(operation_spec) do
    mission_critical = Map.get(operation_spec, :mission_critical, false)
    requires_rollback = Map.get(operation_spec, :requires_rollback, false)
    data_consistency = Map.get(operation_spec, :requires_data_consistency, false)

    sensitivity_factors = [mission_critical, requires_rollback, data_consistency]
    sensitivity_count = Enum.count(sensitivity_factors, & &1)

    sensitivity_count / length(sensitivity_factors)
  end

  defp assess_coordination_requirements(operation_spec) do
    multi_agent = Map.get(operation_spec, :involves_multiple_agents, false)
    synchronization = Map.get(operation_spec, :requires_synchronization, false)
    resource_sharing = Map.get(operation_spec, :requires_resource_sharing, false)

    coordination_factors = [multi_agent, synchronization, resource_sharing]
    coordination_count = Enum.count(coordination_factors, & &1)

    coordination_count / length(coordination_factors)
  end

  defp assess_performance_requirements(operation_spec) do
    time_sensitive = Map.get(operation_spec, :time_sensitive, false)
    high_throughput = Map.get(operation_spec, :high_throughput_required, false)
    resource_intensive = Map.get(operation_spec, :resource_intensive, false)

    performance_factors = [time_sensitive, high_throughput, resource_intensive]
    performance_count = Enum.count(performance_factors, & &1)

    performance_count / length(performance_factors)
  end

  defp calculate_template_suitability(operation_analysis, template) do
    # Calculate how well template matches operation characteristics
    use_cases = template.use_cases
    pattern = template.pattern

    # Base suitability from use case matching
    base_score = calculate_use_case_match(operation_analysis, use_cases)

    # Pattern-specific adjustments
    pattern_adjustment = calculate_pattern_suitability(operation_analysis, pattern)

    # Final suitability score
    suitability = base_score * 0.6 + pattern_adjustment * 0.4
    Float.round(min(suitability, 1.0), 3)
  end

  defp calculate_use_case_match(operation_analysis, use_cases) do
    # Simple use case matching (placeholder for more sophisticated analysis)
    if :general in use_cases or :multi_agent_coordination in use_cases do
      # Default good match
      0.7
    else
      # Moderate match
      0.5
    end
  end

  defp calculate_pattern_suitability(operation_analysis, pattern) do
    case pattern do
      :sequential when operation_analysis.complexity > 0.6 -> 0.8
      :parallel when operation_analysis.concurrency_needs > 0.7 -> 0.9
      :orchestrator_workers when operation_analysis.coordination_requirements > 0.8 -> 0.9
      :error_recovery when operation_analysis.error_sensitivity > 0.8 -> 0.9
      :rag_pipeline when operation_analysis.complexity > 0.5 -> 0.8
      :provider_coordination when operation_analysis.performance_requirements > 0.6 -> 0.8
      # Default moderate suitability
      _ -> 0.6
    end
  end

  defp generate_recommendation_reasoning(template, score, analysis) do
    case template do
      :sequential ->
        "Sequential template recommended for step-by-step processing with complexity #{analysis.complexity}"

      :parallel ->
        "Parallel template recommended for concurrent execution with concurrency needs #{analysis.concurrency_needs}"

      :orchestrator_workers ->
        "Orchestrator-workers template recommended for multi-agent coordination with requirements #{analysis.coordination_requirements}"

      :error_recovery ->
        "Error recovery template recommended for mission-critical operations with sensitivity #{analysis.error_sensitivity}"

      :rag_pipeline ->
        "RAG pipeline template recommended for knowledge operations with complexity #{analysis.complexity}"

      :provider_coordination ->
        "Provider coordination template recommended for performance-critical operations with requirements #{analysis.performance_requirements}"

      _ ->
        "Template selected based on overall suitability score of #{score}"
    end
  end

  defp check_agent_compatibility(template, agent_capabilities) do
    # Check if agent has required capabilities for template
    required_capabilities = get_template_required_capabilities(template.pattern)

    missing_capabilities = required_capabilities -- agent_capabilities

    compatibility_score =
      (length(agent_capabilities) - length(missing_capabilities)) /
        max(length(required_capabilities), 1)

    %{
      compatible: Enum.empty?(missing_capabilities),
      score: Float.round(max(compatibility_score, 0.0), 3),
      missing_capabilities: missing_capabilities,
      recommendations: generate_compatibility_recommendations(missing_capabilities),
      issues:
        if(Enum.empty?(missing_capabilities), do: [], else: ["Missing required capabilities"])
    }
  end

  defp get_template_required_capabilities(pattern) do
    case pattern do
      :sequential -> [:step_execution, :error_handling]
      :parallel -> [:concurrent_execution, :result_aggregation]
      :orchestrator_workers -> [:coordination, :worker_management, :result_collection]
      :error_recovery -> [:checkpoint_management, :compensation_execution, :rollback]
      :rag_pipeline -> [:embedding_generation, :retrieval_coordination, :context_building]
      :provider_coordination -> [:provider_management, :response_comparison, :fallback_handling]
      _ -> []
    end
  end

  defp generate_compatibility_recommendations(missing_capabilities) do
    if Enum.empty?(missing_capabilities) do
      ["Agent is fully compatible with template"]
    else
      Enum.map(missing_capabilities, fn capability ->
        "Consider implementing #{capability} capability for optimal template usage"
      end)
    end
  end

  defp extract_customizations(custom_params, template) do
    # Extract what customizations were applied vs template defaults
    customizations = []

    customizations =
      if Map.has_key?(custom_params, :timeout) do
        [:custom_timeout | customizations]
      else
        customizations
      end

    customizations =
      if Map.has_key?(custom_params, :steps) do
        [:custom_steps | customizations]
      else
        customizations
      end

    customizations =
      if Map.has_key?(custom_params, :middleware) do
        [:custom_middleware | customizations]
      else
        customizations
      end

    Enum.reverse(customizations)
  end
end
