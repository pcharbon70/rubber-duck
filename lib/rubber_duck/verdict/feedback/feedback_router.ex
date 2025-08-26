defmodule RubberDuck.Verdict.Feedback.FeedbackRouter do
  @moduledoc """
  Intelligent feedback routing system for directing feedback to appropriate learning engines.

  Routes validated feedback to specialized learning components based on feedback type,
  learning categories, priority levels, and current system state to optimize learning
  efficiency and prevent overloading any single learning component.
  """

  require Logger

  @learning_engine_targets %{
    judge_selection_learner: [:judge_selection_optimization, :coordination_optimization],
    criteria_adaptation_engine: [:evaluation_criteria_adjustment, :quality_enhancement],
    cost_optimization_learner: [:cost_optimization, :resource_efficiency],
    bias_detection_agent: [:bias_pattern_detection, :fairness_improvement],
    performance_learning_agent: [:performance_optimization, :system_improvement],
    user_preference_modeler: [:personalization, :user_experience_optimization]
  }

  @routing_strategies [
    :round_robin,
    :weighted_priority,
    :load_balanced,
    :category_specialized,
    :adaptive_routing
  ]

  @engine_capacity_limits %{
    judge_selection_learner: 50,
    criteria_adaptation_engine: 30,
    cost_optimization_learner: 40,
    bias_detection_agent: 25,
    performance_learning_agent: 35,
    user_preference_modeler: 45
  }

  @doc """
  Route feedback batch to appropriate learning engines.

  ## Parameters
  - `target_engine` - Primary target learning engine
  - `feedback_batch` - Batch of validated feedback items
  - `priority` - Routing priority level
  - `options` - Routing options and configuration

  ## Returns
  - `{:ok, routing_result}` - Routing successful
  - `{:error, reason}` - Routing failed
  """
  def route_feedback_batch(target_engine, feedback_batch, priority, options \\ []) do
    Logger.info(
      "Routing #{length(feedback_batch)} items to #{target_engine} with priority #{priority}"
    )

    routing_strategy = Keyword.get(options, :strategy, :category_specialized)

    case validate_routing_request(target_engine, feedback_batch, priority) do
      :ok ->
        case execute_routing_strategy(
               target_engine,
               feedback_batch,
               priority,
               routing_strategy,
               options
             ) do
          {:ok, routing_result} ->
            log_routing_success(target_engine, routing_result)
            {:ok, routing_result}

          {:error, reason} ->
            log_routing_failure(target_engine, reason)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Route individual feedback item with intelligent target selection.

  ## Parameters
  - `feedback_item` - Single validated feedback item
  - `options` - Routing options

  ## Returns
  - `{:ok, routing_result}` - Routing successful with target information
  - `{:error, reason}` - Routing failed
  """
  def route_feedback_item(feedback_item, options \\ []) do
    case determine_optimal_targets(feedback_item, options) do
      {:ok, target_engines} ->
        case route_to_multiple_targets(feedback_item, target_engines, options) do
          {:ok, routing_results} ->
            consolidate_routing_results(routing_results, feedback_item)

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get current routing statistics and engine load information.

  ## Parameters
  - `time_window` - Analysis time window (default: last hour)

  ## Returns
  - Comprehensive routing statistics map
  """
  def get_routing_stats(time_window \\ {1, :hour}) do
    {amount, unit} = time_window

    %{
      total_routed: get_total_routed_since(time_window),
      routing_by_engine: get_routing_distribution_by_engine(time_window),
      routing_by_priority: get_routing_distribution_by_priority(time_window),
      average_routing_latency_ms: calculate_average_routing_latency(time_window),
      engine_load_status: get_engine_load_status(),
      routing_success_rate: calculate_routing_success_rate(time_window),
      failed_routing_reasons: get_failed_routing_reasons(time_window),
      routing_health: %{
        overall_health: assess_overall_routing_health(),
        bottleneck_engines: identify_bottleneck_engines(),
        underutilized_engines: identify_underutilized_engines()
      }
    }
  end

  @doc """
  Configure routing parameters and engine capacities.

  ## Parameters
  - `routing_config` - New routing configuration

  ## Returns
  - `{:ok, updated_config}` - Configuration updated
  - `{:error, reason}` - Configuration failed
  """
  def configure_routing(routing_config) do
    case validate_routing_config(routing_config) do
      :ok ->
        # Would update persistent configuration
        Logger.info("Routing configuration updated")
        {:ok, routing_config}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Private Routing Functions

  defp validate_routing_request(target_engine, feedback_batch, priority) do
    cond do
      not is_atom(target_engine) ->
        {:error, "Target engine must be an atom"}

      not is_list(feedback_batch) or Enum.empty?(feedback_batch) ->
        {:error, "Feedback batch must be non-empty list"}

      not is_atom(priority) ->
        {:error, "Priority must be an atom"}

      not engine_exists?(target_engine) ->
        {:error, "Unknown target engine: #{target_engine}"}

      engine_over_capacity?(target_engine, length(feedback_batch)) ->
        {:error, "Target engine #{target_engine} over capacity"}

      true ->
        :ok
    end
  end

  defp execute_routing_strategy(target_engine, feedback_batch, priority, strategy, options) do
    case strategy do
      :round_robin ->
        route_round_robin(target_engine, feedback_batch, priority, options)

      :weighted_priority ->
        route_weighted_priority(target_engine, feedback_batch, priority, options)

      :load_balanced ->
        route_load_balanced(target_engine, feedback_batch, priority, options)

      :category_specialized ->
        route_category_specialized(target_engine, feedback_batch, priority, options)

      :adaptive_routing ->
        route_adaptive(target_engine, feedback_batch, priority, options)

      _ ->
        {:error, "Unknown routing strategy: #{strategy}"}
    end
  end

  defp determine_optimal_targets(feedback_item, options) do
    learning_categories = Map.get(feedback_item, :learning_categories, [])
    feedback_type = Map.get(feedback_item, :feedback_type)
    priority = Map.get(feedback_item, :priority_level, :medium)

    # Find engines that handle these learning categories
    potential_targets =
      Enum.filter(@learning_engine_targets, fn {_engine, categories} ->
        not Enum.empty?(learning_categories -- (learning_categories -- categories))
      end)

    if Enum.empty?(potential_targets) do
      # Fallback to general learning engine
      {:ok, [:general_learning_engine]}
    else
      # Select optimal targets based on current load and priority
      optimal_targets = select_optimal_targets(potential_targets, priority, options)
      {:ok, optimal_targets}
    end
  end

  defp route_to_multiple_targets(feedback_item, target_engines, options) do
    routing_tasks =
      Enum.map(target_engines, fn engine ->
        Task.async(fn ->
          route_to_single_target(feedback_item, engine, options)
        end)
      end)

    routing_results = Task.await_many(routing_tasks, 10_000)

    successful_routes = Enum.filter(routing_results, &match?({:ok, _}, &1))
    failed_routes = Enum.filter(routing_results, &match?({:error, _}, &1))

    if length(successful_routes) > 0 do
      {:ok,
       %{
         successful_routes: successful_routes,
         failed_routes: failed_routes,
         success_rate: length(successful_routes) / length(target_engines)
       }}
    else
      {:error, "All routing attempts failed"}
    end
  end

  # Routing strategy implementations

  defp route_round_robin(target_engine, feedback_batch, priority, options) do
    # Simple round-robin distribution
    batch_size = get_optimal_batch_size(target_engine, length(feedback_batch))
    batches = Enum.chunk_every(feedback_batch, batch_size)

    routing_results =
      Enum.map(batches, fn batch ->
        route_batch_to_engine(target_engine, batch, priority, options)
      end)

    consolidate_batch_routing_results(routing_results, :round_robin)
  end

  defp route_weighted_priority(target_engine, feedback_batch, priority, options) do
    # Sort by learning value and confidence, route highest priority first
    sorted_feedback =
      Enum.sort_by(feedback_batch, fn item ->
        learning_value = Map.get(item, :calculated_learning_value, 0.5)
        confidence = Map.get(item, :calculated_confidence_score, 0.5)
        # Negative for descending sort
        -(learning_value * confidence)
      end)

    route_batch_to_engine(target_engine, sorted_feedback, priority, options)
  end

  defp route_load_balanced(target_engine, feedback_batch, priority, options) do
    # Distribute based on current engine load
    current_load = get_engine_current_load(target_engine)
    max_capacity = Map.get(@engine_capacity_limits, target_engine, 30)

    available_capacity = max(0, max_capacity - current_load)

    if available_capacity >= length(feedback_batch) do
      route_batch_to_engine(target_engine, feedback_batch, priority, options)
    else
      # Route what we can, queue the rest
      {immediate_batch, queued_batch} = Enum.split(feedback_batch, available_capacity)

      immediate_result = route_batch_to_engine(target_engine, immediate_batch, priority, options)
      queue_result = queue_feedback_for_later_routing(target_engine, queued_batch, priority)

      combine_routing_results(immediate_result, queue_result)
    end
  end

  defp route_category_specialized(target_engine, feedback_batch, priority, options) do
    # Group by learning categories and route to specialized engines
    feedback_by_category = group_feedback_by_learning_category(feedback_batch)

    routing_results =
      Enum.map(feedback_by_category, fn {category, category_feedback} ->
        specialized_engine = find_specialized_engine_for_category(category, target_engine)
        route_batch_to_engine(specialized_engine, category_feedback, priority, options)
      end)

    consolidate_batch_routing_results(routing_results, :category_specialized)
  end

  defp route_adaptive(target_engine, feedback_batch, priority, options) do
    # Use machine learning to optimize routing decisions
    routing_decision = make_adaptive_routing_decision(target_engine, feedback_batch, priority)

    case routing_decision.strategy do
      :direct_route -> route_batch_to_engine(target_engine, feedback_batch, priority, options)
      :split_route -> execute_split_routing(routing_decision.split_plan, options)
      :defer_route -> queue_feedback_for_optimal_timing(target_engine, feedback_batch, priority)
    end
  end

  # Routing execution helpers

  defp route_to_single_target(feedback_item, engine, options) do
    # Simulate routing to learning engine
    # 50-150ms
    routing_latency = :rand.uniform(100) + 50

    :timer.sleep(routing_latency)

    success_probability = calculate_routing_success_probability(engine, feedback_item)

    if :rand.uniform() < success_probability do
      {:ok,
       %{
         target_engine: engine,
         feedback_id: Map.get(feedback_item, :id, "unknown"),
         routed_at: DateTime.utc_now(),
         routing_latency_ms: routing_latency,
         estimated_processing_time: estimate_processing_time(engine, feedback_item)
       }}
    else
      {:error, "Routing failed for engine #{engine}"}
    end
  end

  defp route_batch_to_engine(engine, feedback_batch, priority, options) do
    # Simulate batch routing
    batch_size = length(feedback_batch)
    # Rough estimate
    estimated_time = batch_size * 75

    routing_result = %{
      target_engine: engine,
      batch_size: batch_size,
      priority: priority,
      routed_at: DateTime.utc_now(),
      estimated_completion_time: DateTime.add(DateTime.utc_now(), estimated_time, :millisecond),
      routing_metadata: %{
        routing_strategy: Map.get(options, :strategy, :default),
        options: options
      }
    }

    {:ok, routing_result}
  end

  # Helper functions for routing decisions

  defp engine_exists?(engine_name) do
    Map.has_key?(@learning_engine_targets, engine_name) or engine_name == :general_learning_engine
  end

  defp engine_over_capacity?(engine, batch_size) do
    current_load = get_engine_current_load(engine)
    capacity_limit = Map.get(@engine_capacity_limits, engine, 30)

    current_load + batch_size > capacity_limit
  end

  defp get_optimal_batch_size(engine, total_items) do
    engine_capacity = Map.get(@engine_capacity_limits, engine, 30)
    current_load = get_engine_current_load(engine)
    available_capacity = max(1, engine_capacity - current_load)

    min(available_capacity, total_items)
  end

  defp select_optimal_targets(potential_targets, priority, options) do
    max_targets = Keyword.get(options, :max_targets, 2)

    # Score targets based on capacity, specialization, and current load
    scored_targets =
      Enum.map(potential_targets, fn {engine, _categories} ->
        score = calculate_target_score(engine, priority)
        {engine, score}
      end)

    # Select top scoring targets
    scored_targets
    |> Enum.sort_by(fn {_engine, score} -> -score end)
    |> Enum.take(max_targets)
    |> Enum.map(fn {engine, _score} -> engine end)
  end

  defp calculate_target_score(engine, priority) do
    base_score = 0.5

    # Lower current load = higher score
    current_load = get_engine_current_load(engine)
    capacity = Map.get(@engine_capacity_limits, engine, 30)
    load_score = (capacity - current_load) / capacity

    # Higher priority gets priority routing
    priority_multiplier =
      case priority do
        :critical -> 1.5
        :high -> 1.2
        :medium -> 1.0
        :low -> 0.8
        _ -> 0.6
      end

    (base_score + load_score) * priority_multiplier
  end

  defp group_feedback_by_learning_category(feedback_batch) do
    Enum.group_by(feedback_batch, fn feedback_item ->
      categories = Map.get(feedback_item, :learning_categories, [:general_improvement])
      # Use primary category for grouping
      List.first(categories)
    end)
  end

  defp find_specialized_engine_for_category(category, fallback_engine) do
    specialized_engine =
      Enum.find(@learning_engine_targets, fn {_engine, categories} ->
        category in categories
      end)

    case specialized_engine do
      {engine, _} -> engine
      nil -> fallback_engine
    end
  end

  defp make_adaptive_routing_decision(target_engine, feedback_batch, priority) do
    # Simplified adaptive decision making - would use ML in production
    current_load = get_engine_current_load(target_engine)
    batch_size = length(feedback_batch)

    cond do
      current_load + batch_size <= Map.get(@engine_capacity_limits, target_engine, 30) ->
        %{strategy: :direct_route}

      batch_size > 20 ->
        split_point = div(batch_size, 2)

        %{
          strategy: :split_route,
          split_plan: %{primary: split_point, secondary: batch_size - split_point}
        }

      priority in [:low, :background] ->
        %{strategy: :defer_route}

      true ->
        %{strategy: :direct_route}
    end
  end

  defp execute_split_routing(split_plan, options) do
    # Would implement intelligent split routing
    Logger.info("Executing split routing: #{inspect(split_plan)}")
    {:ok, %{strategy: :split_route, executed: true}}
  end

  # Result consolidation helpers

  defp consolidate_routing_results(routing_results, feedback_item) do
    successful_routes = Enum.filter(routing_results.successful_routes, &match?({:ok, _}, &1))

    result = %{
      feedback_id: Map.get(feedback_item, :id, "unknown"),
      routing_targets: Enum.map(successful_routes, fn {:ok, result} -> result.target_engine end),
      routing_success_rate: routing_results.success_rate,
      total_targets: length(successful_routes) + length(routing_results.failed_routes),
      routed_at: DateTime.utc_now(),
      routing_metadata: %{
        multi_target_routing: true,
        success_count: length(successful_routes),
        failure_count: length(routing_results.failed_routes)
      }
    }

    {:ok, result}
  end

  defp consolidate_batch_routing_results(routing_results, strategy) do
    successful_results = Enum.filter(routing_results, &match?({:ok, _}, &1))
    failed_results = Enum.filter(routing_results, &match?({:error, _}, &1))

    total_routed =
      Enum.reduce(successful_results, 0, fn {:ok, result}, acc ->
        acc + Map.get(result, :batch_size, 0)
      end)

    consolidated_result = %{
      routing_strategy: strategy,
      total_items_routed: total_routed,
      successful_batches: length(successful_results),
      failed_batches: length(failed_results),
      overall_success_rate: length(successful_results) / length(routing_results),
      consolidation_metadata: %{
        consolidated_at: DateTime.utc_now(),
        batch_count: length(routing_results)
      }
    }

    {:ok, consolidated_result}
  end

  defp combine_routing_results(immediate_result, queue_result) do
    case {immediate_result, queue_result} do
      {{:ok, immediate}, {:ok, queued}} ->
        {:ok,
         %{
           immediate_routing: immediate,
           queued_routing: queued,
           total_handled: Map.get(immediate, :batch_size, 0) + Map.get(queued, :count, 0)
         }}

      {{:ok, immediate}, {:error, queue_error}} ->
        {:ok, %{immediate_routing: immediate, queue_error: queue_error}}

      {{:error, immediate_error}, {:ok, queued}} ->
        {:ok, %{queued_routing: queued, immediate_error: immediate_error}}

      _ ->
        {:error, "Both immediate and queue routing failed"}
    end
  end

  # Logging and monitoring helpers

  defp log_routing_success(target_engine, routing_result) do
    batch_size = Map.get(routing_result, :batch_size, 1)
    Logger.info("Successfully routed #{batch_size} items to #{target_engine}")
  end

  defp log_routing_failure(target_engine, reason) do
    Logger.warning("Routing to #{target_engine} failed: #{reason}")
  end

  # Engine status and capacity helpers (stubs for integration with actual engines)

  # Simulate current load
  defp get_engine_current_load(_engine), do: :rand.uniform(20)
  defp calculate_routing_success_probability(_engine, _feedback_item), do: 0.95
  defp estimate_processing_time(_engine, _feedback_item), do: 2_000 + :rand.uniform(3_000)

  defp queue_feedback_for_later_routing(engine, feedback_batch, priority) do
    queued_result = %{
      target_engine: engine,
      count: length(feedback_batch),
      priority: priority,
      queued_at: DateTime.utc_now(),
      estimated_processing_delay: calculate_queue_delay(engine)
    }

    {:ok, queued_result}
  end

  defp queue_feedback_for_optimal_timing(engine, feedback_batch, priority) do
    optimal_delay = calculate_optimal_processing_delay(engine, priority)

    queued_result = %{
      target_engine: engine,
      count: length(feedback_batch),
      priority: priority,
      queued_at: DateTime.utc_now(),
      optimal_processing_time: DateTime.add(DateTime.utc_now(), optimal_delay, :second)
    }

    {:ok, queued_result}
  end

  # Statistics and monitoring helpers (stubs)

  defp get_total_routed_since(_time_window), do: 156

  defp get_routing_distribution_by_engine(_time_window),
    do: %{judge_selection_learner: 45, criteria_adaptation_engine: 32}

  defp get_routing_distribution_by_priority(_time_window), do: %{high: 67, medium: 89}
  defp calculate_average_routing_latency(_time_window), do: 85.5

  defp get_engine_load_status,
    do: %{judge_selection_learner: 0.6, criteria_adaptation_engine: 0.4}

  defp calculate_routing_success_rate(_time_window), do: 0.94

  defp get_failed_routing_reasons(_time_window),
    do: %{capacity_exceeded: 3, engine_unavailable: 1}

  defp assess_overall_routing_health, do: :healthy
  defp identify_bottleneck_engines, do: []
  defp identify_underutilized_engines, do: [:performance_learning_agent]

  defp validate_routing_config(config) when is_map(config), do: :ok
  defp validate_routing_config(_), do: {:error, "Config must be a map"}

  # 30 seconds default delay
  defp calculate_queue_delay(_engine), do: 30_000

  defp calculate_optimal_processing_delay(_engine, priority) do
    case priority do
      :critical -> 0
      :high -> 10
      :medium -> 60
      :low -> 300
      _ -> 600
    end
  end
end
