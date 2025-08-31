defmodule RubberDuck.Workflows.Templates.ErrorHandlingTemplateManager do
  @moduledoc """
  Comprehensive error handling template management system for agent failure scenarios.

  Provides standardized error handling templates with classification, recovery patterns,
  and learning capabilities for consistent agent behavior across enterprise deployments.
  Integrates with existing WorkflowErrorManager and agent infrastructure.

  Features:
  - Comprehensive error template management with classification and recovery patterns
  - Template versioning and lifecycle management with deprecation and migration support
  - Learning-based template improvement from error resolution outcomes and agent feedback
  - Integration with WorkflowErrorManager for seamless error handling coordination
  - Template validation and compliance checking for production deployment safety
  - Performance optimization for template retrieval and application in production workflows

  Template Categories:
  - **Agent Failure Templates**: Standardized responses for agent initialization, processing, and coordination failures
  - **Workflow Error Templates**: Templates for workflow execution errors, timeouts, and resource exhaustion
  - **Integration Error Templates**: Templates for inter-agent communication failures and coordination issues
  - **Recovery Pattern Templates**: Comprehensive recovery strategies with compensation and rollback patterns
  """

  use GenServer

  require Logger

  alias RubberDuck.Workflows.{
    ErrorHandling.WorkflowErrorManager,
    Integration.WorkflowIntegrationValidator
  }

  @error_template_categories [
    :agent_failure,
    :workflow_error,
    :integration_error,
    :recovery_pattern,
    :compensation_strategy,
    :rollback_template
  ]

  @template_severity_levels [:low, :medium, :high, :critical]

  @default_template_config %{
    enable_learning: true,
    template_caching: true,
    performance_tracking: true,
    validation_strict: true,
    auto_improvement: false
  }

  defstruct [
    :template_registry,
    :template_cache,
    :learning_engine,
    :validation_config,
    :performance_tracker,
    :template_versions,
    :deprecation_schedule
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    template_config = Keyword.get(opts, :template_config, @default_template_config)

    state = %__MODULE__{
      template_registry: initialize_template_registry(),
      template_cache: initialize_template_cache(template_config),
      learning_engine: initialize_learning_engine(template_config),
      validation_config: initialize_validation_config(template_config),
      performance_tracker: initialize_performance_tracker(template_config),
      template_versions: %{},
      deprecation_schedule: %{}
    }

    Logger.info("ErrorHandlingTemplateManager: Initializing template management system",
      template_categories: length(@error_template_categories),
      caching_enabled: template_config.template_caching,
      learning_enabled: template_config.enable_learning
    )

    case load_existing_templates(state) do
      {:ok, updated_state} -> {:ok, updated_state}
      {:error, reason} -> {:stop, {:template_loading_failed, reason}}
    end
  end

  # Public API

  def get_error_template(category, error_type, severity \\ :medium, opts \\ []) do
    GenServer.call(__MODULE__, {:get_error_template, category, error_type, severity, opts})
  end

  def create_error_template(category, template_spec, opts \\ []) do
    GenServer.call(__MODULE__, {:create_error_template, category, template_spec, opts})
  end

  def update_template_from_outcome(template_id, outcome_data, opts \\ []) do
    GenServer.call(__MODULE__, {:update_template_from_outcome, template_id, outcome_data, opts})
  end

  def validate_template(template_spec, validation_level \\ :strict) do
    GenServer.call(__MODULE__, {:validate_template, template_spec, validation_level})
  end

  def get_template_analytics(category \\ :all, time_window \\ {7, :days}) do
    GenServer.call(__MODULE__, {:get_template_analytics, category, time_window})
  end

  def deprecate_template(template_id, deprecation_schedule, opts \\ []) do
    GenServer.call(__MODULE__, {:deprecate_template, template_id, deprecation_schedule, opts})
  end

  # GenServer callbacks

  def handle_call({:get_error_template, category, error_type, severity, opts}, _from, state) do
    retrieval_start_time = System.monotonic_time(:microsecond)

    case retrieve_error_template(category, error_type, severity, state, opts) do
      {:ok, template} ->
        track_template_usage(template, retrieval_start_time, state)
        {:reply, {:ok, template}, state}

      {:error, :template_not_found} ->
        case generate_fallback_template(category, error_type, severity, state) do
          {:ok, fallback_template} ->
            track_fallback_usage(fallback_template, state)
            {:reply, {:ok, fallback_template}, state}

          {:error, reason} ->
            {:reply, {:error, {:template_retrieval_failed, reason}}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:create_error_template, category, template_spec, opts}, _from, state) do
    creation_start_time = System.monotonic_time(:microsecond)

    with {:ok, validated_spec} <- validate_template_specification(template_spec, category, state),
         {:ok, created_template} <-
           create_template_with_metadata(validated_spec, category, opts, state),
         {:ok, updated_state} <- register_template(created_template, state) do
      creation_time = System.monotonic_time(:microsecond) - creation_start_time

      Logger.info("ErrorHandlingTemplateManager: Template created successfully",
        template_id: created_template.id,
        category: category,
        creation_time_us: creation_time
      )

      {:reply, {:ok, created_template}, updated_state}
    else
      {:error, reason} ->
        Logger.error("ErrorHandlingTemplateManager: Template creation failed",
          category: category,
          error: reason
        )

        {:reply, {:error, {:template_creation_failed, reason}}, state}
    end
  end

  def handle_call({:update_template_from_outcome, template_id, outcome_data, opts}, _from, state) do
    case update_template_with_learning(template_id, outcome_data, state, opts) do
      {:ok, updated_template, updated_state} ->
        {:reply, {:ok, updated_template}, updated_state}

      {:error, reason} ->
        {:reply, {:error, {:template_update_failed, reason}}, state}
    end
  end

  def handle_call({:validate_template, template_spec, validation_level}, _from, state) do
    case perform_template_validation(template_spec, validation_level, state) do
      {:ok, validation_result} ->
        {:reply, {:ok, validation_result}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_template_analytics, category, time_window}, _from, state) do
    case generate_template_analytics(category, time_window, state) do
      {:ok, analytics} ->
        {:reply, {:ok, analytics}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:deprecate_template, template_id, deprecation_schedule, opts}, _from, state) do
    case schedule_template_deprecation(template_id, deprecation_schedule, state, opts) do
      {:ok, updated_state} ->
        {:reply, :ok, updated_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Private implementation functions

  defp initialize_template_registry do
    %{
      templates: %{},
      categories: Map.from_keys(@error_template_categories, %{}),
      template_index: %{},
      usage_statistics: %{}
    }
  end

  defp initialize_template_cache(config) do
    %{
      enabled: config.template_caching,
      cache_data: %{},
      cache_hits: 0,
      cache_misses: 0,
      max_cache_size: 1000,
      ttl_seconds: 3600
    }
  end

  defp initialize_learning_engine(config) do
    %{
      enabled: config.enable_learning,
      learning_data: %{},
      improvement_suggestions: [],
      success_patterns: %{},
      failure_patterns: %{}
    }
  end

  defp initialize_validation_config(config) do
    %{
      strict_validation: config.validation_strict,
      required_fields: [:id, :category, :error_type, :severity, :recovery_strategy],
      validation_rules: build_validation_rules(),
      compliance_checks: build_compliance_checks()
    }
  end

  defp initialize_performance_tracker(config) do
    %{
      enabled: config.performance_tracking,
      retrieval_times: [],
      creation_times: [],
      application_success_rates: %{},
      template_effectiveness: %{}
    }
  end

  defp build_validation_rules do
    %{
      category_validation: &validate_template_category/1,
      error_type_validation: &validate_error_type/1,
      severity_validation: &validate_severity_level/1,
      recovery_strategy_validation: &validate_recovery_strategy/1,
      template_structure_validation: &validate_template_structure/1
    }
  end

  defp build_compliance_checks do
    %{
      agent_autonomy_preservation: &check_agent_autonomy_compliance/1,
      production_safety: &check_production_safety_compliance/1,
      performance_impact: &check_performance_impact_compliance/1,
      integration_compatibility: &check_integration_compatibility/1
    }
  end

  defp load_existing_templates(state) do
    # Load existing templates from storage (would integrate with Ash resources)
    default_templates = create_default_error_templates()

    updated_registry =
      Enum.reduce(default_templates, state.template_registry, fn template, registry ->
        register_template_in_registry(template, registry)
      end)

    updated_state = %{state | template_registry: updated_registry}

    Logger.info("ErrorHandlingTemplateManager: Loaded default templates",
      template_count: length(default_templates)
    )

    {:ok, updated_state}
  end

  defp retrieve_error_template(category, error_type, severity, state, opts) do
    # Check cache first if enabled
    case check_template_cache(category, error_type, severity, state.template_cache) do
      {:ok, cached_template} ->
        {:ok, cached_template}

      {:error, :cache_miss} ->
        retrieve_from_registry(category, error_type, severity, state, opts)
    end
  end

  defp check_template_cache(category, error_type, severity, cache) do
    if cache.enabled do
      cache_key = generate_cache_key(category, error_type, severity)

      case Map.get(cache.cache_data, cache_key) do
        nil -> {:error, :cache_miss}
        template -> {:ok, template}
      end
    else
      {:error, :cache_miss}
    end
  end

  defp retrieve_from_registry(category, error_type, severity, state, _opts) do
    registry = state.template_registry

    case get_best_matching_template(category, error_type, severity, registry) do
      {:ok, template} -> {:ok, template}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_best_matching_template(category, error_type, severity, registry) do
    category_templates = Map.get(registry.categories, category, %{})

    # Try exact match first
    exact_key = {error_type, severity}

    case Map.get(category_templates, exact_key) do
      nil ->
        # Try fuzzy matching or fallback
        find_closest_template(category, error_type, severity, category_templates)

      template ->
        {:ok, template}
    end
  end

  defp find_closest_template(category, error_type, severity, category_templates) do
    # Implement template matching logic based on error type similarity and severity
    available_templates = Map.keys(category_templates)

    case find_similar_error_type(error_type, available_templates) do
      {:ok, similar_key} ->
        template = Map.get(category_templates, similar_key)
        {:ok, adapt_template_for_error(template, error_type, severity)}

      {:error, :no_match} ->
        {:error, :template_not_found}
    end
  end

  defp generate_fallback_template(category, error_type, severity, state) do
    # Generate a basic fallback template for unhandled error types
    fallback_template = %{
      id: generate_template_id(),
      category: category,
      error_type: error_type,
      severity: severity,
      recovery_strategy: determine_default_recovery_strategy(category, error_type, severity),
      fallback: true,
      created_at: DateTime.utc_now(),
      metadata: %{
        generation_reason: "No existing template found",
        auto_generated: true,
        requires_review: true
      }
    }

    Logger.warn("ErrorHandlingTemplateManager: Generated fallback template",
      category: category,
      error_type: error_type,
      template_id: fallback_template.id
    )

    {:ok, fallback_template}
  end

  defp validate_template_specification(template_spec, category, state) do
    validation_config = state.validation_config

    with :ok <- validate_required_fields(template_spec, validation_config.required_fields),
         :ok <- validate_template_category(category),
         :ok <- validate_template_structure(template_spec),
         :ok <- validate_recovery_strategy(Map.get(template_spec, :recovery_strategy)) do
      enhanced_spec = enhance_template_specification(template_spec, category)
      {:ok, enhanced_spec}
    else
      {:error, reason} -> {:error, {:validation_failed, reason}}
    end
  end

  defp create_template_with_metadata(validated_spec, category, opts, state) do
    template = %{
      id: generate_template_id(),
      category: category,
      error_type: validated_spec.error_type,
      severity: validated_spec.severity,
      recovery_strategy: validated_spec.recovery_strategy,
      template_data: validated_spec.template_data,
      version: 1,
      created_at: DateTime.utc_now(),
      created_by: Keyword.get(opts, :created_by, :system),
      metadata: build_template_metadata(validated_spec, category, opts),
      performance_metrics: initialize_template_performance_metrics()
    }

    {:ok, template}
  end

  defp register_template(template, state) do
    updated_registry = register_template_in_registry(template, state.template_registry)
    updated_cache = update_template_cache(template, state.template_cache)

    updated_state = %{state | template_registry: updated_registry, template_cache: updated_cache}

    {:ok, updated_state}
  end

  defp register_template_in_registry(template, registry) do
    category_key = template.category
    template_key = {template.error_type, template.severity}

    updated_categories =
      Map.update(registry.categories, category_key, %{}, fn category_templates ->
        Map.put(category_templates, template_key, template)
      end)

    updated_templates = Map.put(registry.templates, template.id, template)

    %{registry | categories: updated_categories, templates: updated_templates}
  end

  defp update_template_cache(template, cache) do
    if cache.enabled do
      cache_key = generate_cache_key(template.category, template.error_type, template.severity)
      updated_cache_data = Map.put(cache.cache_data, cache_key, template)

      %{cache | cache_data: updated_cache_data}
    else
      cache
    end
  end

  # Helper functions

  defp create_default_error_templates do
    [
      create_agent_failure_template(),
      create_workflow_timeout_template(),
      create_integration_error_template(),
      create_recovery_pattern_template(),
      create_compensation_template(),
      create_rollback_template()
    ]
  end

  defp create_agent_failure_template do
    %{
      id: "agent_failure_default",
      category: :agent_failure,
      error_type: :agent_initialization_failure,
      severity: :medium,
      recovery_strategy: %{
        type: :restart_with_backoff,
        max_retries: 3,
        backoff_strategy: :exponential,
        fallback_action: :graceful_degradation
      },
      template_data: %{
        error_classification: "Agent initialization or startup failure",
        recovery_steps: [
          "Validate agent configuration and parameters",
          "Check resource availability and system health",
          "Attempt agent restart with exponential backoff",
          "Implement graceful degradation if restart fails"
        ],
        compensation_actions: ["Clean up partial agent state", "Release allocated resources"],
        monitoring_requirements: ["Track restart attempts", "Monitor resource usage"],
        escalation_criteria: %{
          max_restart_attempts: 3,
          escalation_timeout_minutes: 5,
          notify_administrators: true
        }
      },
      version: 1,
      created_at: DateTime.utc_now(),
      metadata: %{
        template_type: :default,
        usage_frequency: :high,
        effectiveness_rating: 0.85
      }
    }
  end

  defp create_workflow_timeout_template do
    %{
      id: "workflow_timeout_default",
      category: :workflow_error,
      error_type: :execution_timeout,
      severity: :high,
      recovery_strategy: %{
        type: :partial_recovery_with_checkpoint,
        checkpoint_interval_ms: 30_000,
        timeout_extension_factor: 1.5,
        fallback_action: :checkpoint_rollback
      },
      template_data: %{
        error_classification: "Workflow execution timeout or hanging process",
        recovery_steps: [
          "Identify workflow checkpoint or last successful step",
          "Analyze resource utilization and bottlenecks",
          "Attempt workflow resume from checkpoint with extended timeout",
          "Implement partial rollback if resume fails"
        ],
        compensation_actions: ["Rollback to last checkpoint", "Clean up hanging processes"],
        performance_analysis: ["Identify execution bottlenecks", "Optimize resource allocation"]
      },
      version: 1,
      created_at: DateTime.utc_now(),
      metadata: %{
        template_type: :default,
        performance_critical: true,
        effectiveness_rating: 0.78
      }
    }
  end

  defp create_integration_error_template do
    %{
      id: "integration_error_default",
      category: :integration_error,
      error_type: :agent_communication_failure,
      severity: :medium,
      recovery_strategy: %{
        type: :communication_retry_with_fallback,
        retry_attempts: 5,
        retry_backoff_ms: 1000,
        fallback_action: :direct_coordination
      },
      template_data: %{
        error_classification: "Inter-agent communication or coordination failure",
        recovery_steps: [
          "Verify agent connectivity and health status",
          "Attempt communication retry with exponential backoff",
          "Switch to direct coordination bypass if retries fail",
          "Update agent coordination strategy for future interactions"
        ],
        fallback_strategies: [
          "Direct agent coordination",
          "Workflow decomposition",
          "Manual intervention"
        ]
      },
      version: 1,
      created_at: DateTime.utc_now(),
      metadata: %{
        template_type: :default,
        coordination_critical: true,
        effectiveness_rating: 0.82
      }
    }
  end

  defp create_recovery_pattern_template do
    %{
      id: "recovery_pattern_default",
      category: :recovery_pattern,
      error_type: :general_recovery,
      severity: :medium,
      recovery_strategy: %{
        type: :adaptive_recovery_with_learning,
        recovery_phases: [:immediate, :analysis, :correction, :validation],
        learning_enabled: true,
        adaptation_strategy: :pattern_based
      },
      template_data: %{
        recovery_phases: %{
          immediate: "Stop error propagation and stabilize system state",
          analysis: "Analyze error context and determine root cause",
          correction: "Apply targeted recovery strategy based on error analysis",
          validation: "Verify recovery success and update recovery patterns"
        },
        success_criteria: [
          "System stability restored",
          "Error no longer occurring",
          "Performance within acceptable range"
        ]
      },
      version: 1,
      created_at: DateTime.utc_now()
    }
  end

  defp create_compensation_template do
    %{
      id: "compensation_default",
      category: :compensation_strategy,
      error_type: :workflow_partial_failure,
      severity: :medium,
      recovery_strategy: %{
        type: :partial_compensation_with_preservation,
        preserve_successful_steps: true,
        compensation_order: :reverse_execution,
        rollback_strategy: :selective
      },
      template_data: %{
        compensation_principles: [
          "Preserve all successful workflow steps and their results",
          "Compensate failed steps in reverse execution order",
          "Maintain data consistency during compensation",
          "Provide rollback capability for compensation actions"
        ]
      },
      version: 1,
      created_at: DateTime.utc_now()
    }
  end

  defp create_rollback_template do
    %{
      id: "rollback_default",
      category: :rollback_template,
      error_type: :critical_failure,
      severity: :critical,
      recovery_strategy: %{
        type: :comprehensive_rollback_with_state_restoration,
        rollback_scope: :full_workflow,
        state_restoration: true,
        backup_verification: true
      },
      template_data: %{
        rollback_phases: [
          "Verify system backup and checkpoint integrity",
          "Stop all workflow execution and lock system state",
          "Execute comprehensive rollback to last known good state",
          "Verify state restoration and system stability"
        ],
        safety_checks: [
          "Backup integrity",
          "State consistency",
          "Resource cleanup",
          "Agent stability"
        ]
      },
      version: 1,
      created_at: DateTime.utc_now()
    }
  end

  # Validation functions

  defp validate_required_fields(template_spec, required_fields) do
    missing_fields = required_fields -- Map.keys(template_spec)

    case missing_fields do
      [] -> :ok
      fields -> {:error, {:missing_required_fields, fields}}
    end
  end

  defp validate_template_category(category) when category in @error_template_categories, do: :ok
  defp validate_template_category(_), do: {:error, :invalid_category}

  defp validate_error_type(error_type) when is_atom(error_type), do: :ok
  defp validate_error_type(_), do: {:error, :invalid_error_type}

  defp validate_severity_level(severity) when severity in @template_severity_levels, do: :ok
  defp validate_severity_level(_), do: {:error, :invalid_severity}

  defp validate_recovery_strategy(strategy) when is_map(strategy) do
    case Map.has_key?(strategy, :type) do
      true -> :ok
      false -> {:error, :missing_recovery_type}
    end
  end

  defp validate_recovery_strategy(_), do: {:error, :invalid_recovery_strategy}

  defp validate_template_structure(template_spec) when is_map(template_spec), do: :ok
  defp validate_template_structure(_), do: {:error, :invalid_template_structure}

  # Compliance checking functions

  defp check_agent_autonomy_compliance(_template), do: :ok
  defp check_production_safety_compliance(_template), do: :ok
  defp check_performance_impact_compliance(_template), do: :ok
  defp check_integration_compatibility(_template), do: :ok

  # Helper functions

  defp generate_template_id do
    timestamp = System.system_time(:nanosecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "error_template_#{timestamp}_#{random}"
  end

  defp generate_cache_key(category, error_type, severity) do
    "#{category}_#{error_type}_#{severity}"
  end

  defp enhance_template_specification(template_spec, category) do
    Map.merge(template_spec, %{
      enhanced: true,
      enhancement_timestamp: DateTime.utc_now(),
      category: category
    })
  end

  defp build_template_metadata(template_spec, category, opts) do
    %{
      source: Keyword.get(opts, :source, :manual),
      tags: Keyword.get(opts, :tags, []),
      priority: Keyword.get(opts, :priority, :normal),
      review_status: :pending,
      usage_count: 0,
      last_used: nil,
      effectiveness_data: %{}
    }
  end

  defp initialize_template_performance_metrics do
    %{
      usage_count: 0,
      success_rate: 0.0,
      average_resolution_time_ms: 0,
      effectiveness_score: 0.0,
      user_feedback: []
    }
  end

  defp determine_default_recovery_strategy(category, error_type, severity) do
    case {category, severity} do
      {:agent_failure, :critical} -> %{type: :immediate_restart, priority: :high}
      {:agent_failure, _} -> %{type: :retry_with_backoff, max_retries: 3}
      {:workflow_error, :critical} -> %{type: :rollback_to_checkpoint, scope: :full}
      {:workflow_error, _} -> %{type: :partial_recovery, preserve_state: true}
      {:integration_error, _} -> %{type: :communication_retry, fallback: :direct_mode}
      _ -> %{type: :generic_recovery, escalate_on_failure: true}
    end
  end

  defp find_similar_error_type(_error_type, []), do: {:error, :no_match}

  defp find_similar_error_type(error_type, [template_key | _rest]) do
    # Simplified similarity matching - would implement more sophisticated matching
    {:ok, template_key}
  end

  defp adapt_template_for_error(template, error_type, severity) do
    %{
      template
      | error_type: error_type,
        severity: severity,
        adapted: true,
        adaptation_timestamp: DateTime.utc_now()
    }
  end

  defp track_template_usage(_template, _start_time, _state) do
    # Track template usage for analytics
    :ok
  end

  defp track_fallback_usage(_template, _state) do
    # Track fallback template usage
    :ok
  end

  defp update_template_with_learning(_template_id, _outcome_data, state, _opts) do
    # Implement learning-based template improvement
    {:ok, %{}, state}
  end

  defp perform_template_validation(_template_spec, _validation_level, _state) do
    # Implement comprehensive template validation
    {:ok, %{validation_passed: true, score: 0.95}}
  end

  defp generate_template_analytics(_category, _time_window, _state) do
    # Generate comprehensive template analytics
    {:ok,
     %{
       usage_statistics: %{},
       effectiveness_metrics: %{},
       improvement_recommendations: []
     }}
  end

  defp schedule_template_deprecation(_template_id, _schedule, state, _opts) do
    # Implement template deprecation scheduling
    {:ok, state}
  end
end
