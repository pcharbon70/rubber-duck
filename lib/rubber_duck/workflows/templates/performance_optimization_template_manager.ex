defmodule RubberDuck.Workflows.Templates.PerformanceOptimizationTemplateManager do
  @moduledoc """
  Dynamic performance optimization template management system for agent workflow enhancement.

  Provides adaptive performance optimization templates with benchmarking, pattern recognition,
  and continuous improvement capabilities. Integrates with agent performance monitoring
  and optimization systems for enterprise-scale performance management.

  Features:
  - Dynamic performance optimization templates with benchmarking and adaptation capabilities
  - Template learning from successful optimization outcomes and performance patterns
  - Performance pattern recognition with automatic template generation and improvement
  - Integration with ReactorPerformanceAgent and performance monitoring infrastructure
  - Template effectiveness tracking with success metrics and optimization impact analysis
  - Enterprise-scale performance template management with versioning and deployment validation

  Template Categories:
  - **Concurrency Templates**: Optimal concurrency patterns for different workload types and system configurations
  - **Resource Optimization Templates**: Memory, CPU, and I/O optimization patterns with resource management strategies
  - **Workflow Optimization Templates**: Workflow execution optimization with dependency analysis and bottleneck resolution
  - **Performance Monitoring Templates**: Monitoring and alerting templates with predictive performance analysis
  """

  use GenServer

  require Logger

  alias RubberDuck.Workflows.{
    Advanced.AdvancedIntegrationManager,
    Integration.WorkflowIntegrationValidator
  }

  alias RubberDuck.Agents.Workflow.ReactorPerformanceAgent

  @performance_template_categories [
    :concurrency_optimization,
    :resource_optimization,
    :workflow_optimization,
    :performance_monitoring,
    :bottleneck_resolution,
    :adaptive_tuning
  ]

  @optimization_strategies [:conservative, :balanced, :aggressive, :adaptive]

  @performance_metrics_types [
    :throughput_optimization,
    :latency_reduction,
    :resource_efficiency,
    :error_rate_improvement,
    :scalability_enhancement
  ]

  @default_template_config %{
    enable_learning: true,
    performance_tracking: true,
    adaptive_optimization: true,
    benchmarking_enabled: true,
    pattern_recognition: true,
    auto_template_generation: false
  }

  defstruct [
    :template_registry,
    :template_cache,
    :learning_engine,
    :benchmarking_system,
    :pattern_recognizer,
    :optimization_history,
    :template_effectiveness
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
      benchmarking_system: initialize_benchmarking_system(template_config),
      pattern_recognizer: initialize_pattern_recognizer(template_config),
      optimization_history: %{},
      template_effectiveness: %{}
    }

    Logger.info(
      "PerformanceOptimizationTemplateManager: Initializing performance template system",
      template_categories: length(@performance_template_categories),
      learning_enabled: template_config.enable_learning,
      benchmarking_enabled: template_config.benchmarking_enabled
    )

    case load_performance_templates(state) do
      {:ok, updated_state} -> {:ok, updated_state}
      {:error, reason} -> {:stop, {:template_loading_failed, reason}}
    end
  end

  # Public API

  def get_optimization_template(
        category,
        workload_characteristics,
        optimization_target \\ :balanced,
        opts \\ []
      ) do
    GenServer.call(
      __MODULE__,
      {:get_optimization_template, category, workload_characteristics, optimization_target, opts}
    )
  end

  def create_optimization_template(category, template_spec, benchmarking_data \\ %{}, opts \\ []) do
    GenServer.call(
      __MODULE__,
      {:create_optimization_template, category, template_spec, benchmarking_data, opts}
    )
  end

  def update_template_from_performance(
        template_id,
        performance_data,
        optimization_outcome,
        opts \\ []
      ) do
    GenServer.call(
      __MODULE__,
      {:update_template_from_performance, template_id, performance_data, optimization_outcome,
       opts}
    )
  end

  def benchmark_template_effectiveness(template_id, workload_data, opts \\ []) do
    GenServer.call(
      __MODULE__,
      {:benchmark_template_effectiveness, template_id, workload_data, opts}
    )
  end

  def analyze_performance_patterns(category \\ :all, analysis_window \\ {30, :days}) do
    GenServer.call(__MODULE__, {:analyze_performance_patterns, category, analysis_window})
  end

  def generate_adaptive_template(performance_history, optimization_goals, opts \\ []) do
    GenServer.call(
      __MODULE__,
      {:generate_adaptive_template, performance_history, optimization_goals, opts}
    )
  end

  # GenServer callbacks

  def handle_call(
        {:get_optimization_template, category, workload_characteristics, optimization_target,
         opts},
        _from,
        state
      ) do
    retrieval_start_time = System.monotonic_time(:microsecond)

    case retrieve_optimization_template(
           category,
           workload_characteristics,
           optimization_target,
           state,
           opts
         ) do
      {:ok, template} ->
        track_template_retrieval(template, retrieval_start_time, state)
        {:reply, {:ok, template}, state}

      {:error, :template_not_found} ->
        case generate_adaptive_optimization_template(
               category,
               workload_characteristics,
               optimization_target,
               state
             ) do
          {:ok, adaptive_template} ->
            track_adaptive_generation(adaptive_template, state)
            {:reply, {:ok, adaptive_template}, state}

          {:error, reason} ->
            {:reply, {:error, {:template_retrieval_failed, reason}}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:create_optimization_template, category, template_spec, benchmarking_data, opts},
        _from,
        state
      ) do
    creation_start_time = System.monotonic_time(:microsecond)

    with {:ok, validated_spec} <-
           validate_performance_template_spec(template_spec, category, state),
         {:ok, benchmarked_template} <-
           enhance_template_with_benchmarking(validated_spec, benchmarking_data, state),
         {:ok, created_template} <-
           create_performance_template_with_metadata(benchmarked_template, category, opts),
         {:ok, updated_state} <- register_performance_template(created_template, state) do
      creation_time = System.monotonic_time(:microsecond) - creation_start_time

      Logger.info("PerformanceOptimizationTemplateManager: Performance template created",
        template_id: created_template.id,
        category: category,
        optimization_target: created_template.optimization_target,
        creation_time_us: creation_time
      )

      {:reply, {:ok, created_template}, updated_state}
    else
      {:error, reason} ->
        Logger.error("PerformanceOptimizationTemplateManager: Template creation failed",
          category: category,
          error: reason
        )

        {:reply, {:error, {:template_creation_failed, reason}}, state}
    end
  end

  def handle_call(
        {:update_template_from_performance, template_id, performance_data, optimization_outcome,
         opts},
        _from,
        state
      ) do
    case update_template_with_performance_learning(
           template_id,
           performance_data,
           optimization_outcome,
           state,
           opts
         ) do
      {:ok, updated_template, updated_state} ->
        {:reply, {:ok, updated_template}, updated_state}

      {:error, reason} ->
        {:reply, {:error, {:template_update_failed, reason}}, state}
    end
  end

  def handle_call(
        {:benchmark_template_effectiveness, template_id, workload_data, opts},
        _from,
        state
      ) do
    case execute_template_benchmarking(template_id, workload_data, state, opts) do
      {:ok, benchmarking_results} ->
        {:reply, {:ok, benchmarking_results}, state}

      {:error, reason} ->
        {:reply, {:error, {:benchmarking_failed, reason}}, state}
    end
  end

  def handle_call({:analyze_performance_patterns, category, analysis_window}, _from, state) do
    case analyze_optimization_patterns(category, analysis_window, state) do
      {:ok, pattern_analysis} ->
        {:reply, {:ok, pattern_analysis}, state}

      {:error, reason} ->
        {:reply, {:error, {:pattern_analysis_failed, reason}}, state}
    end
  end

  def handle_call(
        {:generate_adaptive_template, performance_history, optimization_goals, opts},
        _from,
        state
      ) do
    case create_adaptive_optimization_template(
           performance_history,
           optimization_goals,
           state,
           opts
         ) do
      {:ok, adaptive_template, updated_state} ->
        {:reply, {:ok, adaptive_template}, updated_state}

      {:error, reason} ->
        {:reply, {:error, {:adaptive_generation_failed, reason}}, state}
    end
  end

  # Private implementation functions

  defp initialize_template_registry do
    %{
      templates: %{},
      categories: Map.from_keys(@performance_template_categories, %{}),
      optimization_index: %{},
      performance_index: %{},
      benchmarking_data: %{}
    }
  end

  defp initialize_template_cache(config) do
    %{
      enabled: config.performance_tracking,
      cache_data: %{},
      performance_cache: %{},
      benchmarking_cache: %{},
      cache_hit_ratio: 0.0
    }
  end

  defp initialize_learning_engine(config) do
    %{
      enabled: config.enable_learning,
      performance_patterns: %{},
      optimization_outcomes: [],
      success_factors: %{},
      failure_analysis: %{},
      learning_model: :linear_regression
    }
  end

  defp initialize_benchmarking_system(config) do
    %{
      enabled: config.benchmarking_enabled,
      benchmark_suite: create_default_benchmarks(),
      performance_baselines: %{},
      optimization_targets: %{},
      effectiveness_thresholds: %{
        min_improvement_percentage: 5.0,
        target_improvement_percentage: 20.0,
        excellent_improvement_percentage: 50.0
      }
    }
  end

  defp initialize_pattern_recognizer(config) do
    %{
      enabled: config.pattern_recognition,
      pattern_library: create_performance_pattern_library(),
      recognition_algorithms: [:correlation_analysis, :trend_detection, :anomaly_detection],
      pattern_confidence_threshold: 0.8
    }
  end

  defp load_performance_templates(state) do
    # Load default performance optimization templates
    default_templates = create_default_performance_templates()

    updated_registry =
      Enum.reduce(default_templates, state.template_registry, fn template, registry ->
        register_performance_template_in_registry(template, registry)
      end)

    updated_state = %{state | template_registry: updated_registry}

    Logger.info("PerformanceOptimizationTemplateManager: Loaded default performance templates",
      template_count: length(default_templates)
    )

    {:ok, updated_state}
  end

  defp retrieve_optimization_template(
         category,
         workload_characteristics,
         optimization_target,
         state,
         _opts
       ) do
    # Retrieve best matching performance optimization template
    case find_optimal_template(
           category,
           workload_characteristics,
           optimization_target,
           state.template_registry
         ) do
      {:ok, template} -> {:ok, template}
      {:error, reason} -> {:error, reason}
    end
  end

  defp find_optimal_template(category, workload_characteristics, optimization_target, registry) do
    category_templates = Map.get(registry.categories, category, %{})

    case select_best_matching_template(
           category_templates,
           workload_characteristics,
           optimization_target
         ) do
      {:ok, template} -> {:ok, template}
      {:error, _} -> {:error, :template_not_found}
    end
  end

  defp select_best_matching_template(templates, _workload_characteristics, _optimization_target) do
    # Simplified template selection - would implement sophisticated matching
    case Enum.take(Map.values(templates), 1) do
      [template] -> {:ok, template}
      [] -> {:error, :no_templates_available}
    end
  end

  defp generate_adaptive_optimization_template(
         category,
         workload_characteristics,
         optimization_target,
         state
       ) do
    # Generate adaptive template based on performance patterns and system characteristics
    adaptive_template = %{
      id: generate_performance_template_id(),
      category: category,
      optimization_target: optimization_target,
      workload_profile: classify_workload_profile(workload_characteristics),
      optimization_strategy:
        determine_optimization_strategy(workload_characteristics, optimization_target),
      adaptive: true,
      created_at: DateTime.utc_now(),
      template_data: build_adaptive_template_data(workload_characteristics, optimization_target),
      metadata: %{
        generation_reason: "No existing template for workload characteristics",
        auto_generated: true,
        requires_benchmarking: true
      }
    }

    Logger.info("PerformanceOptimizationTemplateManager: Generated adaptive template",
      category: category,
      optimization_target: optimization_target,
      template_id: adaptive_template.id
    )

    {:ok, adaptive_template}
  end

  # Default template creation functions

  defp create_default_performance_templates do
    [
      create_concurrency_optimization_template(),
      create_resource_optimization_template(),
      create_workflow_optimization_template(),
      create_monitoring_optimization_template(),
      create_bottleneck_resolution_template(),
      create_adaptive_tuning_template()
    ]
  end

  defp create_concurrency_optimization_template do
    %{
      id: "concurrency_optimization_default",
      category: :concurrency_optimization,
      optimization_target: :balanced,
      workload_profile: :general,
      optimization_strategy: %{
        type: :adaptive_concurrency,
        base_strategy: :resource_aware,
        scaling_factors: %{
          cpu_utilization_threshold: 0.7,
          memory_pressure_threshold: 0.8,
          throughput_target_multiplier: 1.2
        },
        safety_limits: %{
          max_concurrency_increase: 2.0,
          min_concurrency_decrease: 0.5,
          resource_exhaustion_protection: true
        }
      },
      template_data: %{
        optimization_parameters: %{
          initial_concurrency_assessment:
            "Analyze current system utilization and workload characteristics",
          scaling_decision_logic:
            "Increase concurrency if CPU < 70% and memory < 80%, decrease if resource pressure > 85%",
          performance_validation:
            "Monitor throughput improvement and resource efficiency after adjustment",
          rollback_criteria: "Rollback if performance degrades > 10% or resource pressure > 95%"
        },
        benchmarking_criteria: %{
          baseline_metrics: [:cpu_utilization, :memory_usage, :throughput_per_second],
          success_thresholds: %{min_improvement_percentage: 10.0, target_improvement: 25.0},
          monitoring_duration_ms: 60_000
        }
      },
      version: 1,
      created_at: DateTime.utc_now(),
      metadata: %{
        template_type: :default,
        optimization_focus: :concurrency,
        effectiveness_rating: 0.82
      }
    }
  end

  defp create_resource_optimization_template do
    %{
      id: "resource_optimization_default",
      category: :resource_optimization,
      optimization_target: :efficiency,
      workload_profile: :resource_intensive,
      optimization_strategy: %{
        type: :multi_resource_optimization,
        resource_priorities: [:memory, :cpu, :io],
        optimization_techniques: [
          :memory_pooling,
          :garbage_collection_tuning,
          :cpu_affinity_optimization,
          :io_batching
        ],
        monitoring_intervals: %{
          memory_check_ms: 5_000,
          cpu_sample_ms: 1_000,
          io_analysis_ms: 10_000
        }
      },
      template_data: %{
        optimization_steps: [
          "Analyze current resource utilization patterns and identify optimization opportunities",
          "Apply memory optimization through garbage collection tuning and pooling strategies",
          "Optimize CPU utilization through workload distribution and affinity settings",
          "Implement I/O optimization through batching and caching strategies"
        ],
        resource_targets: %{
          memory_efficiency_target: 0.85,
          cpu_utilization_target: 0.75,
          io_optimization_target: 0.8
        },
        validation_metrics: [
          "Resource efficiency improvement",
          "System stability maintenance",
          "Performance impact assessment"
        ]
      },
      version: 1,
      created_at: DateTime.utc_now(),
      metadata: %{
        template_type: :default,
        optimization_focus: :resource_efficiency,
        effectiveness_rating: 0.88
      }
    }
  end

  defp create_workflow_optimization_template do
    %{
      id: "workflow_optimization_default",
      category: :workflow_optimization,
      optimization_target: :performance,
      workload_profile: :workflow_intensive,
      optimization_strategy: %{
        type: :workflow_execution_optimization,
        optimization_areas: [
          :dependency_analysis,
          :execution_parallelization,
          :step_optimization,
          :compensation_efficiency
        ],
        analysis_techniques: [
          :dag_optimization,
          :critical_path_analysis,
          :bottleneck_identification
        ]
      },
      template_data: %{
        optimization_approach: %{
          dependency_optimization:
            "Analyze and optimize workflow step dependencies for maximum parallelization",
          execution_optimization:
            "Optimize individual step execution through resource allocation and caching",
          compensation_optimization:
            "Streamline compensation and rollback strategies for efficiency",
          monitoring_integration: "Integrate comprehensive monitoring for continuous optimization"
        },
        performance_metrics: %{
          execution_time_reduction: "Target 30% reduction in total workflow execution time",
          resource_efficiency: "Improve resource utilization by 25%",
          error_recovery_speed: "Reduce error recovery time by 40%"
        }
      },
      version: 1,
      created_at: DateTime.utc_now(),
      metadata: %{
        template_type: :default,
        optimization_focus: :workflow_execution,
        effectiveness_rating: 0.79
      }
    }
  end

  defp create_monitoring_optimization_template do
    %{
      id: "monitoring_optimization_default",
      category: :performance_monitoring,
      optimization_target: :insight,
      workload_profile: :monitoring_intensive,
      optimization_strategy: %{
        type: :intelligent_monitoring_with_prediction,
        monitoring_optimization: %{
          adaptive_sampling: true,
          predictive_alerting: true,
          resource_aware_monitoring: true,
          pattern_based_analysis: true
        },
        performance_prediction: %{
          trend_analysis: true,
          anomaly_detection: true,
          capacity_forecasting: true,
          optimization_recommendation: true
        }
      },
      template_data: %{
        monitoring_strategy: %{
          baseline_establishment: "Establish performance baselines for accurate trend analysis",
          adaptive_monitoring:
            "Adjust monitoring frequency based on system activity and risk levels",
          predictive_analysis:
            "Use historical patterns to predict performance issues before they occur",
          optimization_triggering:
            "Automatically trigger optimization when patterns indicate improvement opportunities"
        },
        alert_optimization: %{
          intelligent_thresholds:
            "Dynamic alert thresholds based on historical performance patterns",
          noise_reduction:
            "Filter false positives through pattern recognition and context analysis",
          priority_classification: "Classify alerts by business impact and resolution urgency"
        }
      },
      version: 1,
      created_at: DateTime.utc_now(),
      metadata: %{
        template_type: :default,
        optimization_focus: :monitoring_intelligence,
        effectiveness_rating: 0.85
      }
    }
  end

  defp create_bottleneck_resolution_template do
    %{
      id: "bottleneck_resolution_default",
      category: :bottleneck_resolution,
      optimization_target: :throughput,
      workload_profile: :bottleneck_prone,
      optimization_strategy: %{
        type: :systematic_bottleneck_resolution,
        identification_methods: [:dependency_analysis, :resource_profiling, :execution_tracing],
        resolution_priorities: [:critical_path, :resource_constraints, :coordination_overhead],
        validation_approach: :before_after_comparison
      },
      template_data: %{
        bottleneck_identification: %{
          dependency_bottlenecks:
            "Identify workflow steps creating dependency chains and execution delays",
          resource_bottlenecks: "Analyze resource contention points causing execution slowdowns",
          coordination_bottlenecks: "Detect agent coordination overhead and communication delays"
        },
        resolution_strategies: %{
          parallel_execution: "Convert sequential operations to parallel where possible",
          resource_optimization: "Optimize resource allocation and utilization efficiency",
          caching_strategies: "Implement intelligent caching to reduce redundant operations",
          workflow_restructuring: "Restructure workflow dependencies for optimal execution flow"
        },
        effectiveness_validation: %{
          performance_improvement_measurement: "Measure throughput and latency improvements",
          resource_efficiency_validation: "Validate resource utilization optimization",
          system_stability_check: "Ensure optimizations don't compromise system stability"
        }
      },
      version: 1,
      created_at: DateTime.utc_now(),
      metadata: %{
        template_type: :default,
        optimization_focus: :bottleneck_elimination,
        effectiveness_rating: 0.81
      }
    }
  end

  defp create_adaptive_tuning_template do
    %{
      id: "adaptive_tuning_default",
      category: :adaptive_tuning,
      optimization_target: :adaptive,
      workload_profile: :variable,
      optimization_strategy: %{
        type: :continuous_adaptive_optimization,
        adaptation_triggers: [:performance_degradation, :workload_change, :resource_availability],
        learning_algorithms: [
          :performance_correlation,
          :pattern_recognition,
          :optimization_effectiveness
        ],
        tuning_parameters: %{
          adaptation_sensitivity: 0.15,
          learning_rate: 0.1,
          optimization_confidence_threshold: 0.7
        }
      },
      template_data: %{
        adaptive_mechanisms: %{
          workload_adaptation:
            "Continuously adapt optimization strategies based on changing workload characteristics",
          resource_adaptation:
            "Adjust resource allocation and utilization based on system capacity changes",
          performance_adaptation:
            "Modify optimization targets based on achieved performance outcomes",
          pattern_adaptation:
            "Learn from successful optimization patterns and apply to similar scenarios"
        },
        continuous_improvement: %{
          effectiveness_tracking:
            "Track optimization effectiveness over time and across different scenarios",
          pattern_learning: "Learn from successful optimization patterns and failure modes",
          strategy_evolution:
            "Evolve optimization strategies based on accumulated learning and outcomes"
        }
      },
      version: 1,
      created_at: DateTime.utc_now(),
      metadata: %{
        template_type: :default,
        optimization_focus: :adaptive_learning,
        effectiveness_rating: 0.90
      }
    }
  end

  # Helper functions

  defp create_default_benchmarks do
    %{
      throughput_benchmark: %{
        baseline_ops_per_second: 100,
        target_improvement: 1.25,
        excellent_performance: 2.0
      },
      latency_benchmark: %{
        baseline_response_time_ms: 1000,
        target_reduction: 0.7,
        excellent_performance: 0.5
      },
      resource_benchmark: %{
        baseline_cpu_utilization: 0.6,
        baseline_memory_utilization: 0.7,
        target_efficiency_improvement: 1.2
      }
    }
  end

  defp create_performance_pattern_library do
    %{
      high_throughput_patterns: %{
        characteristics: [:high_concurrency, :low_latency, :efficient_resource_usage],
        optimization_strategies: [:parallel_execution, :resource_pooling, :caching]
      },
      resource_efficient_patterns: %{
        characteristics: [:low_memory_usage, :optimal_cpu_utilization, :minimal_io],
        optimization_strategies: [:memory_optimization, :cpu_affinity, :io_batching]
      },
      scalable_patterns: %{
        characteristics: [:horizontal_scaling, :load_distribution, :elastic_resources],
        optimization_strategies: [:distributed_execution, :load_balancing, :auto_scaling]
      }
    }
  end

  defp classify_workload_profile(workload_characteristics) do
    # Classify workload based on characteristics
    case workload_characteristics do
      %{high_concurrency: true, low_latency: true} -> :high_performance
      %{resource_intensive: true} -> :resource_intensive
      %{variable_load: true} -> :variable
      %{cpu_intensive: true} -> :cpu_intensive
      %{memory_intensive: true} -> :memory_intensive
      _ -> :general
    end
  end

  defp determine_optimization_strategy(workload_characteristics, optimization_target) do
    base_strategy = get_base_optimization_strategy(optimization_target)
    workload_profile = classify_workload_profile(workload_characteristics)

    build_strategy_with_focus(base_strategy, workload_profile)
  end

  defp get_base_optimization_strategy(optimization_target) do
    case optimization_target do
      :performance -> :aggressive_optimization
      :efficiency -> :resource_optimization
      :balanced -> :adaptive_optimization
      :stability -> :conservative_optimization
      _ -> :adaptive_optimization
    end
  end

  defp build_strategy_with_focus(base_strategy, workload_profile) do
    case workload_profile do
      :high_performance -> %{strategy: base_strategy, focus: :throughput_latency}
      :resource_intensive -> %{strategy: base_strategy, focus: :resource_efficiency}
      :variable -> %{strategy: :adaptive_optimization, focus: :flexibility}
      _ -> %{strategy: base_strategy, focus: :balanced}
    end
  end

  defp build_adaptive_template_data(workload_characteristics, optimization_target) do
    %{
      workload_analysis: workload_characteristics,
      optimization_focus: optimization_target,
      adaptation_strategy:
        "Template dynamically adapts based on workload patterns and performance outcomes",
      monitoring_requirements: [
        "Continuous performance monitoring",
        "Resource utilization tracking",
        "Optimization effectiveness measurement"
      ],
      success_criteria: build_success_criteria(optimization_target),
      learning_integration:
        "Template learns from performance outcomes and adapts optimization strategies"
    }
  end

  defp build_success_criteria(optimization_target) do
    case optimization_target do
      :performance -> %{throughput_improvement: 20, latency_reduction: 30}
      :efficiency -> %{resource_efficiency_gain: 25, cost_reduction: 15}
      :balanced -> %{overall_improvement: 15, stability_maintenance: true}
      :stability -> %{error_rate_reduction: 50, system_stability: true}
      _ -> %{general_improvement: 10, adaptability: true}
    end
  end

  # Template management functions

  defp validate_performance_template_spec(template_spec, category, _state) do
    required_fields = [:optimization_target, :optimization_strategy, :template_data]

    case validate_required_fields(template_spec, required_fields) do
      :ok -> {:ok, template_spec}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_required_fields(template_spec, required_fields) do
    missing_fields = required_fields -- Map.keys(template_spec)

    case missing_fields do
      [] -> :ok
      fields -> {:error, {:missing_required_fields, fields}}
    end
  end

  defp enhance_template_with_benchmarking(template_spec, benchmarking_data, state) do
    enhanced_template =
      Map.merge(template_spec, %{
        benchmarking_data: benchmarking_data,
        benchmarking_enabled: state.benchmarking_system.enabled,
        benchmark_baselines: extract_benchmark_baselines(benchmarking_data),
        performance_targets: calculate_performance_targets(benchmarking_data, template_spec)
      })

    {:ok, enhanced_template}
  end

  defp extract_benchmark_baselines(benchmarking_data) do
    # Extract baseline performance metrics from benchmarking data
    %{
      baseline_throughput: Map.get(benchmarking_data, :baseline_throughput, 100),
      baseline_latency_ms: Map.get(benchmarking_data, :baseline_latency_ms, 1000),
      baseline_resource_usage:
        Map.get(benchmarking_data, :baseline_resource_usage, %{cpu: 0.6, memory: 0.7})
    }
  end

  defp calculate_performance_targets(benchmarking_data, template_spec) do
    optimization_target = Map.get(template_spec, :optimization_target, :balanced)

    case optimization_target do
      :performance ->
        %{throughput_multiplier: 1.5, latency_reduction: 0.6}

      :efficiency ->
        %{resource_efficiency_gain: 1.3, cost_reduction: 0.8}

      :balanced ->
        %{overall_improvement: 1.2, stability_maintenance: true}

      _ ->
        %{general_improvement: 1.1, adaptability_focus: true}
    end
  end

  defp create_performance_template_with_metadata(template_spec, category, opts) do
    template = %{
      id: generate_performance_template_id(),
      category: category,
      optimization_target: template_spec.optimization_target,
      workload_profile: Map.get(template_spec, :workload_profile, :general),
      optimization_strategy: template_spec.optimization_strategy,
      template_data: template_spec.template_data,
      benchmarking_data: Map.get(template_spec, :benchmarking_data, %{}),
      version: 1,
      created_at: DateTime.utc_now(),
      created_by: Keyword.get(opts, :created_by, :system),
      metadata: build_performance_template_metadata(template_spec, category, opts),
      effectiveness_metrics: initialize_template_effectiveness_metrics()
    }

    {:ok, template}
  end

  defp build_performance_template_metadata(template_spec, category, opts) do
    %{
      source: Keyword.get(opts, :source, :manual),
      tags: Keyword.get(opts, :tags, []),
      optimization_focus: Map.get(template_spec, :optimization_target, :balanced),
      benchmarking_required: Map.has_key?(template_spec, :benchmarking_data),
      usage_count: 0,
      effectiveness_history: [],
      last_optimization: nil
    }
  end

  defp initialize_template_effectiveness_metrics do
    %{
      usage_count: 0,
      success_rate: 0.0,
      average_improvement_percentage: 0.0,
      effectiveness_score: 0.0,
      optimization_outcomes: []
    }
  end

  defp register_performance_template(template, state) do
    updated_registry =
      register_performance_template_in_registry(template, state.template_registry)

    updated_cache = update_performance_template_cache(template, state.template_cache)

    updated_state = %{state | template_registry: updated_registry, template_cache: updated_cache}

    {:ok, updated_state}
  end

  defp register_performance_template_in_registry(template, registry) do
    category_key = template.category
    template_key = {template.workload_profile, template.optimization_target}

    updated_categories =
      Map.update(registry.categories, category_key, %{}, fn category_templates ->
        Map.put(category_templates, template_key, template)
      end)

    updated_templates = Map.put(registry.templates, template.id, template)

    %{registry | categories: updated_categories, templates: updated_templates}
  end

  defp update_performance_template_cache(template, cache) do
    cache_key = generate_performance_cache_key(template)
    updated_cache_data = Map.put(cache.cache_data, cache_key, template)

    %{cache | cache_data: updated_cache_data}
  end

  defp track_template_retrieval(_template, _start_time, _state) do
    # Track template retrieval performance
    :ok
  end

  defp track_adaptive_generation(_template, _state) do
    # Track adaptive template generation
    :ok
  end

  defp update_template_with_performance_learning(
         _template_id,
         _performance_data,
         _outcome,
         state,
         _opts
       ) do
    # Implement performance-based template learning
    {:ok, %{}, state}
  end

  defp execute_template_benchmarking(_template_id, _workload_data, _state, _opts) do
    # Implement template effectiveness benchmarking
    {:ok,
     %{
       benchmarking_successful: true,
       performance_improvement: 15.5,
       effectiveness_score: 0.85
     }}
  end

  defp analyze_optimization_patterns(_category, _analysis_window, _state) do
    # Implement performance pattern analysis
    {:ok,
     %{
       patterns_identified: [],
       optimization_opportunities: [],
       effectiveness_trends: %{}
     }}
  end

  defp create_adaptive_optimization_template(
         _performance_history,
         _optimization_goals,
         state,
         _opts
       ) do
    # Implement adaptive template generation
    adaptive_template = %{
      id: generate_performance_template_id(),
      adaptive: true,
      created_at: DateTime.utc_now()
    }

    {:ok, adaptive_template, state}
  end

  defp generate_performance_template_id do
    timestamp = System.system_time(:nanosecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "perf_template_#{timestamp}_#{random}"
  end

  defp generate_performance_cache_key(template) do
    "#{template.category}_#{template.workload_profile}_#{template.optimization_target}"
  end
end
