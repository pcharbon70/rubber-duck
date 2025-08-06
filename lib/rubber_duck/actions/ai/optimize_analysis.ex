defmodule RubberDuck.Actions.AI.OptimizeAnalysis do
  @moduledoc """
  Action for optimizing AI analysis processes.

  Optimizes:
  - Analysis parameters
  - Resource usage
  - Processing time
  - Result quality
  """

  use Jido.Action,
    name: "optimize_analysis",
    description: "Optimize AI analysis processes for better performance",
    schema: [
      current_config: [type: :map, required: true],
      performance_data: [type: :map, default: %{}],
      optimization_goals: [type: {:list, :atom}, default: [:quality, :speed]],
      constraints: [type: :map, default: %{}]
    ]

  require Logger

  @impl true
  def run(params, _context) do
    with {:ok, metrics} <- analyze_current_performance(params.current_config, params.performance_data),
         {:ok, bottlenecks} <- identify_bottlenecks(metrics),
         {:ok, optimizations} <- generate_optimizations(bottlenecks, params.optimization_goals),
         {:ok, validated} <- validate_optimizations(optimizations, params.constraints),
         {:ok, config} <- apply_optimizations(params.current_config, validated) do

      {:ok, %{
        optimized_config: config,
        improvements: calculate_improvements(metrics, config),
        applied_optimizations: validated,
        performance_forecast: forecast_performance(config, metrics),
        recommendations: generate_optimization_recommendations(validated)
      }}
    end
  end

  defp analyze_current_performance(config, performance_data) do
    metrics = %{
      average_duration: calculate_average_duration(performance_data),
      success_rate: calculate_success_rate(performance_data),
      resource_usage: analyze_resource_usage(config, performance_data),
      quality_scores: extract_quality_scores(performance_data),
      throughput: calculate_throughput(performance_data),
      error_patterns: identify_error_patterns(performance_data)
    }

    {:ok, metrics}
  end

  defp calculate_average_duration(performance_data) do
    durations = Map.get(performance_data, :durations, [])

    if length(durations) > 0 do
      Enum.sum(durations) / length(durations)
    else
      0
    end
  end

  defp calculate_success_rate(performance_data) do
    total = Map.get(performance_data, :total_analyses, 0)
    successful = Map.get(performance_data, :successful_analyses, 0)

    if total > 0 do
      (successful / total) * 100
    else
      0
    end
  end

  defp analyze_resource_usage(config, performance_data) do
    %{
      cpu_usage: performance_data[:cpu_usage] || estimate_cpu_usage(config),
      memory_usage: performance_data[:memory_usage] || estimate_memory_usage(config),
      api_calls: performance_data[:api_calls] || config[:max_api_calls] || 100
    }
  end

  defp estimate_cpu_usage(config) do
    base_usage = 20  # Base CPU percentage

    # Adjust based on config
    adjustments = 0
    adjustments = if config[:parallel_processing], do: adjustments + 30, else: adjustments
    adjustments = if config[:deep_analysis], do: adjustments + 20, else: adjustments

    min(100, base_usage + adjustments)
  end

  defp estimate_memory_usage(config) do
    base_mb = 256

    # Adjust based on config
    adjustments = 0
    adjustments = if config[:cache_enabled], do: adjustments + 512, else: adjustments
    adjustments = if config[:batch_size] do
      adjustments + (config.batch_size * 10)
    else
      adjustments
    end

    base_mb + adjustments
  end

  defp extract_quality_scores(performance_data) do
    Map.get(performance_data, :quality_scores, [])
  end

  defp calculate_throughput(performance_data) do
    time_window = Map.get(performance_data, :time_window_seconds, 3600)
    analyses_count = Map.get(performance_data, :total_analyses, 0)

    if time_window > 0 do
      analyses_count / (time_window / 3600)  # Analyses per hour
    else
      0
    end
  end

  defp identify_error_patterns(performance_data) do
    errors = Map.get(performance_data, :errors, [])

    errors
    |> Enum.group_by(& &1[:type])
    |> Enum.map(fn {type, occurrences} ->
      %{
        type: type,
        frequency: length(occurrences),
        last_occurrence: List.last(occurrences)[:timestamp]
      }
    end)
    |> Enum.sort_by(& &1.frequency, :desc)
  end

  defp identify_bottlenecks(metrics) do
    bottlenecks = []

    # Duration bottleneck
    bottlenecks = if metrics.average_duration > 30_000 do  # 30 seconds
      [%{type: :duration, severity: :high, value: metrics.average_duration} | bottlenecks]
    else
      bottlenecks
    end

    # Success rate bottleneck
    bottlenecks = if metrics.success_rate < 80 do
      [%{type: :success_rate, severity: :critical, value: metrics.success_rate} | bottlenecks]
    else
      bottlenecks
    end

    # Resource bottlenecks
    bottlenecks = if metrics.resource_usage.cpu_usage > 80 do
      [%{type: :cpu, severity: :high, value: metrics.resource_usage.cpu_usage} | bottlenecks]
    else
      bottlenecks
    end

    bottlenecks = if metrics.resource_usage.memory_usage > 2048 do
      [%{type: :memory, severity: :medium, value: metrics.resource_usage.memory_usage} | bottlenecks]
    else
      bottlenecks
    end

    # Throughput bottleneck
    bottlenecks = if metrics.throughput < 10 do
      [%{type: :throughput, severity: :medium, value: metrics.throughput} | bottlenecks]
    else
      bottlenecks
    end

    {:ok, bottlenecks}
  end

  defp generate_optimizations(bottlenecks, goals) do
    optimizations = Enum.flat_map(bottlenecks, fn bottleneck ->
      generate_bottleneck_optimizations(bottleneck, goals)
    end)

    # Add goal-specific optimizations
    goal_optimizations = Enum.flat_map(goals, &generate_goal_optimizations/1)

    {:ok, Enum.uniq(optimizations ++ goal_optimizations)}
  end

  defp generate_bottleneck_optimizations(bottleneck, goals) do
    case bottleneck.type do
      :duration ->
        duration_optimizations(bottleneck, goals)
      :success_rate ->
        success_rate_optimizations(bottleneck)
      :cpu ->
        cpu_optimizations(bottleneck)
      :memory ->
        memory_optimizations(bottleneck)
      :throughput ->
        throughput_optimizations(bottleneck, goals)
      _ ->
        []
    end
  end

  defp duration_optimizations(bottleneck, goals) do
    optimizations = []

    optimizations = if :speed in goals do
      [
        %{
          type: :config,
          key: :timeout,
          action: :reduce,
          value: 20_000,
          impact: :high
        },
        %{
          type: :config,
          key: :analysis_depth,
          action: :reduce,
          value: :shallow,
          impact: :medium
        }
      | optimizations]
    else
      optimizations
    end

    optimizations = if bottleneck.severity == :high do
      [%{
        type: :config,
        key: :parallel_processing,
        action: :enable,
        value: true,
        impact: :high
      } | optimizations]
    else
      optimizations
    end

    optimizations
  end

  defp success_rate_optimizations(_bottleneck) do
    [
      %{
        type: :config,
        key: :retry_count,
        action: :increase,
        value: 3,
        impact: :medium
      },
      %{
        type: :config,
        key: :fallback_strategy,
        action: :enable,
        value: :progressive,
        impact: :high
      },
      %{
        type: :config,
        key: :validation_level,
        action: :increase,
        value: :strict,
        impact: :medium
      }
    ]
  end

  defp cpu_optimizations(_bottleneck) do
    [
      %{
        type: :config,
        key: :batch_size,
        action: :reduce,
        value: 5,
        impact: :medium
      },
      %{
        type: :config,
        key: :parallel_workers,
        action: :reduce,
        value: 2,
        impact: :high
      },
      %{
        type: :runtime,
        key: :cpu_throttling,
        action: :enable,
        value: 70,  # Max 70% CPU
        impact: :medium
      }
    ]
  end

  defp memory_optimizations(_bottleneck) do
    [
      %{
        type: :config,
        key: :cache_size,
        action: :reduce,
        value: 100,
        impact: :medium
      },
      %{
        type: :config,
        key: :result_retention,
        action: :reduce,
        value: 3600,  # 1 hour
        impact: :low
      },
      %{
        type: :runtime,
        key: :garbage_collection,
        action: :aggressive,
        value: true,
        impact: :medium
      }
    ]
  end

  defp throughput_optimizations(_bottleneck, goals) do
    optimizations = []

    optimizations = if :speed in goals do
      [
        %{
          type: :config,
          key: :batch_processing,
          action: :enable,
          value: true,
          impact: :high
        },
        %{
          type: :config,
          key: :queue_size,
          action: :increase,
          value: 100,
          impact: :medium
        }
      | optimizations]
    else
      optimizations
    end

    optimizations
  end

  defp generate_goal_optimizations(:quality) do
    [
      %{
        type: :config,
        key: :analysis_depth,
        action: :set,
        value: :deep,
        impact: :high
      },
      %{
        type: :config,
        key: :validation_level,
        action: :set,
        value: :comprehensive,
        impact: :medium
      }
    ]
  end

  defp generate_goal_optimizations(:speed) do
    [
      %{
        type: :config,
        key: :caching,
        action: :enable,
        value: true,
        impact: :high
      },
      %{
        type: :config,
        key: :async_processing,
        action: :enable,
        value: true,
        impact: :medium
      }
    ]
  end

  defp generate_goal_optimizations(:cost) do
    [
      %{
        type: :config,
        key: :api_call_batching,
        action: :enable,
        value: true,
        impact: :high
      },
      %{
        type: :config,
        key: :result_caching,
        action: :aggressive,
        value: true,
        impact: :medium
      }
    ]
  end

  defp generate_goal_optimizations(_), do: []

  defp validate_optimizations(optimizations, constraints) do
    validated = Enum.filter(optimizations, fn opt ->
      validate_single_optimization(opt, constraints)
    end)

    # Resolve conflicts
    resolved = resolve_optimization_conflicts(validated)

    {:ok, resolved}
  end

  defp validate_single_optimization(optimization, constraints) do
    case optimization.type do
      :config ->
        validate_config_optimization(optimization, constraints)
      :runtime ->
        validate_runtime_optimization(optimization, constraints)
      _ ->
        true
    end
  end

  defp validate_config_optimization(optimization, constraints) do
    # Check if the optimization violates any constraints
    case optimization.key do
      :batch_size ->
        min_batch = Map.get(constraints, :min_batch_size, 1)
        optimization.value >= min_batch

      :timeout ->
        min_timeout = Map.get(constraints, :min_timeout, 5000)
        optimization.value >= min_timeout

      _ ->
        true
    end
  end

  defp validate_runtime_optimization(optimization, constraints) do
    case optimization.key do
      :cpu_throttling ->
        max_cpu = Map.get(constraints, :max_cpu_usage, 100)
        optimization.value <= max_cpu

      _ ->
        true
    end
  end

  defp resolve_optimization_conflicts(optimizations) do
    # Group by key to find conflicts
    grouped = Enum.group_by(optimizations, & &1.key)

    # Resolve conflicts by choosing highest impact
    Enum.map(grouped, fn {_key, opts} ->
      Enum.max_by(opts, & impact_score(&1.impact))
    end)
  end

  defp impact_score(:critical), do: 4
  defp impact_score(:high), do: 3
  defp impact_score(:medium), do: 2
  defp impact_score(:low), do: 1
  defp impact_score(_), do: 0

  defp apply_optimizations(current_config, optimizations) do
    config = Enum.reduce(optimizations, current_config, fn opt, acc ->
      apply_single_optimization(acc, opt)
    end)

    {:ok, config}
  end

  defp apply_single_optimization(config, optimization) do
    case optimization.action do
      :set ->
        Map.put(config, optimization.key, optimization.value)

      :increase ->
        current = Map.get(config, optimization.key, 0)
        Map.put(config, optimization.key, max(current, optimization.value))

      :reduce ->
        current = Map.get(config, optimization.key, 100)
        Map.put(config, optimization.key, min(current, optimization.value))

      :enable ->
        Map.put(config, optimization.key, optimization.value)

      _ ->
        config
    end
  end

  defp calculate_improvements(metrics, optimized_config) do
    %{
      expected_duration_reduction: estimate_duration_improvement(metrics, optimized_config),
      expected_success_rate_increase: estimate_success_improvement(metrics, optimized_config),
      expected_resource_savings: estimate_resource_savings(metrics, optimized_config),
      expected_throughput_increase: estimate_throughput_improvement(metrics, optimized_config)
    }
  end

  defp estimate_duration_improvement(_metrics, config) do
    base_improvement = 0

    # Parallel processing improvement
    base_improvement = if config[:parallel_processing] do
      base_improvement + 30
    else
      base_improvement
    end

    # Caching improvement
    base_improvement = if config[:caching] do
      base_improvement + 20
    else
      base_improvement
    end

    # Depth reduction improvement
    base_improvement = if config[:analysis_depth] == :shallow do
      base_improvement + 25
    else
      base_improvement
    end

    min(70, base_improvement)  # Cap at 70% improvement
  end

  defp estimate_success_improvement(_metrics, config) do
    base_improvement = 0

    base_improvement = if config[:retry_count] && config.retry_count > 1 do
      base_improvement + 10
    else
      base_improvement
    end

    base_improvement = if config[:fallback_strategy] do
      base_improvement + 15
    else
      base_improvement
    end

    min(30, base_improvement)
  end

  defp estimate_resource_savings(_metrics, config) do
    cpu_savings = if config[:cpu_throttling] do
      100 - (config[:cpu_throttling] || 100)
    else
      0
    end

    memory_savings = if config[:cache_size] && config.cache_size < 500 do
      20
    else
      0
    end

    %{
      cpu_percentage: cpu_savings,
      memory_percentage: memory_savings
    }
  end

  defp estimate_throughput_improvement(_metrics, config) do
    base_improvement = 0

    base_improvement = if config[:batch_processing] do
      base_improvement + 50
    else
      base_improvement
    end

    base_improvement = if config[:async_processing] do
      base_improvement + 30
    else
      base_improvement
    end

    min(100, base_improvement)
  end

  defp forecast_performance(config, metrics) do
    %{
      estimated_duration: forecast_duration(config, metrics),
      estimated_success_rate: forecast_success_rate(config, metrics),
      estimated_throughput: forecast_throughput(config, metrics),
      confidence: 0.75
    }
  end

  defp forecast_duration(config, metrics) do
    current = metrics.average_duration
    improvement = estimate_duration_improvement(metrics, config)

    current * (1 - improvement / 100)
  end

  defp forecast_success_rate(config, metrics) do
    current = metrics.success_rate
    improvement = estimate_success_improvement(metrics, config)

    min(100, current + improvement)
  end

  defp forecast_throughput(config, metrics) do
    current = metrics.throughput
    improvement = estimate_throughput_improvement(metrics, config)

    current * (1 + improvement / 100)
  end

  defp generate_optimization_recommendations(optimizations) do
    Enum.map(optimizations, fn opt ->
      "Apply #{opt.action} to #{opt.key}: #{inspect(opt.value)} (Impact: #{opt.impact})"
    end)
  end
end
