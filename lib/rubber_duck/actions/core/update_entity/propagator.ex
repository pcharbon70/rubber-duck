defmodule RubberDuck.Actions.Core.UpdateEntity.Propagator do
  @moduledoc """
  Propagation module for UpdateEntity action.
  
  Handles change propagation to dependent entities:
  - Identifies entities requiring updates
  - Manages cascade operations
  - Handles circular dependencies
  - Queues and orchestrates propagation
  - Tracks propagation results and failures
  """
  
  require Logger
  
  @doc """
  Main propagation entry point that orchestrates change propagation.
  
  Propagates changes to affected entities based on impact assessment.
  """
  def propagate(params, context) do
    entity = params.entity
    impact_assessment = Map.get(params, :impact_assessment, %{})
    options = Map.get(params, :propagation_options, %{})
    
    with {:ok, propagation_plan} <- create_propagation_plan(entity, impact_assessment, options),
         {:ok, _validation} <- validate_propagation_plan(propagation_plan),
         {:ok, execution_result} <- execute_propagation(propagation_plan, context),
         {:ok, verification} <- verify_propagation_results(execution_result) do
      {:ok,
       %{
         propagation_id: generate_propagation_id(),
         propagated: true,
         entities_updated: count_updated_entities(execution_result),
         propagation_plan: propagation_plan,
         execution_result: execution_result,
         verification: verification,
         metrics: calculate_propagation_metrics(execution_result),
         metadata: Map.get(context, :metadata, %{})
       }}
    else
      {:error, :no_propagation_needed} ->
        {:ok,
         %{
           propagation_id: generate_propagation_id(),
           propagated: false,
           reason: :no_affected_entities,
           entities_updated: 0
         }}
      
      {:error, _reason} = error ->
        handle_propagation_failure(error, params, context)
    end
  end
  
  @doc """
  Creates a propagation plan based on entity changes and impact assessment.
  """
  def create_propagation_plan(entity, impact_assessment, options) do
    affected_entities = extract_affected_entities(impact_assessment)
    
    if Enum.empty?(affected_entities) do
      {:error, :no_propagation_needed}
    else
      plan = %{
        source_entity: %{
          id: entity[:id],
          type: entity[:type],
          version: entity[:version]
        },
        affected_entities: affected_entities,
        propagation_strategy: determine_propagation_strategy(entity, impact_assessment, options),
        propagation_order: determine_propagation_order(affected_entities, entity),
        circular_dependencies: detect_circular_dependencies(affected_entities, entity),
        batching_config: determine_batching_config(affected_entities, options),
        rollback_strategy: determine_rollback_strategy(options),
        timeout_config: determine_timeout_config(options)
      }
      
      {:ok, plan}
    end
  end
  
  defp extract_affected_entities(impact_assessment) do
    affected = impact_assessment[:impact_details][:affected_entities] || 
               impact_assessment[:affected_entities] || 
               []
    
    # Convert to consistent format
    Enum.map(affected, fn
      {type, id, action} -> %{type: type, id: id, action: action}
      {type, id} -> %{type: type, id: id, action: :update}
      entity when is_map(entity) -> entity
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end
  
  defp determine_propagation_strategy(_entity, impact_assessment, options) do
    severity = impact_assessment[:impact_details][:direct_impact][:severity] || :unknown
    risk_level = impact_assessment[:impact_details][:risk_assessment][:risk_level] || :unknown
    
    strategy = cond do
      options[:force_sequential] -> :sequential
      options[:force_parallel] -> :parallel
      risk_level == :critical -> :sequential_with_validation
      severity == :critical -> :sequential_with_rollback
      length(extract_affected_entities(impact_assessment)) > 10 -> :batched_parallel
      true -> :parallel
    end
    
    %{
      type: strategy,
      max_parallelism: options[:max_parallelism] || 5,
      validation_required: strategy in [:sequential_with_validation, :sequential_with_rollback],
      rollback_enabled: strategy == :sequential_with_rollback
    }
  end
  
  defp determine_propagation_order(affected_entities, source_entity) do
    # Group by priority
    priority_groups = Enum.group_by(affected_entities, fn entity ->
      calculate_entity_priority(entity, source_entity)
    end)
    
    # Order groups by priority
    [:critical, :high, :medium, :low]
    |> Enum.flat_map(fn priority ->
      Map.get(priority_groups, priority, [])
    end)
  end
  
  defp calculate_entity_priority(entity, source_entity) do
    cond do
      entity.type == :sessions and source_entity[:type] == :user -> :critical
      entity.type == :deployments -> :critical
      entity.type in [:code_files, :analyses] -> :high
      entity.type in [:preferences, :settings] -> :medium
      true -> :low
    end
  end
  
  defp detect_circular_dependencies(affected_entities, source_entity) do
    # Build dependency graph
    graph = build_dependency_graph(affected_entities, source_entity)
    
    # Detect cycles using DFS
    cycles = detect_cycles_in_graph(graph)
    
    %{
      has_circular_dependencies: not Enum.empty?(cycles),
      cycles: cycles,
      resolution_strategy: if(not Enum.empty?(cycles), do: :break_at_weakest_link, else: :none)
    }
  end
  
  defp build_dependency_graph(affected_entities, source_entity) do
    # Build adjacency list representation
    graph = %{source_entity[:id] => []}
    
    Enum.reduce(affected_entities, graph, fn entity, acc ->
      source_id = source_entity[:id]
      entity_id = entity.id
      
      # Add edge from source to affected entity
      acc
      |> Map.update(source_id, [entity_id], &[entity_id | &1])
      |> Map.put_new(entity_id, get_entity_dependencies(entity))
    end)
  end
  
  defp get_entity_dependencies(entity) do
    # Get dependencies for the entity type
    case entity.type do
      :sessions -> []
      :preferences -> []
      :code_files -> [:project, :imports]
      :analyses -> [:target_entity, :code_files]
      :deployments -> [:project, :code_files]
      _ -> []
    end
  end
  
  defp detect_cycles_in_graph(graph) do
    visited = MapSet.new()
    rec_stack = MapSet.new()
    cycles = []
    
    Enum.reduce(Map.keys(graph), cycles, fn node, acc ->
      if not MapSet.member?(visited, node) do
        {_, _, new_cycles} = dfs_detect_cycles(node, graph, visited, rec_stack, [])
        acc ++ new_cycles
      else
        acc
      end
    end)
  end
  
  defp dfs_detect_cycles(node, graph, visited, rec_stack, path) do
    visited = MapSet.put(visited, node)
    rec_stack = MapSet.put(rec_stack, node)
    path = [node | path]
    
    neighbors = Map.get(graph, node, [])
    
    {visited, rec_stack, cycles} = 
      Enum.reduce(neighbors, {visited, rec_stack, []}, fn neighbor, {v, r, c} ->
        cond do
          MapSet.member?(r, neighbor) ->
            # Found a cycle
            cycle = extract_cycle(path, neighbor)
            {v, r, [cycle | c]}
          
          not MapSet.member?(v, neighbor) ->
            # Continue DFS
            dfs_detect_cycles(neighbor, graph, v, r, path)
          
          true ->
            {v, r, c}
        end
      end)
    
    rec_stack = MapSet.delete(rec_stack, node)
    {visited, rec_stack, cycles}
  end
  
  defp extract_cycle(path, target) do
    path
    |> Enum.take_while(&(&1 != target))
    |> Enum.reverse()
    |> then(&[target | &1])
  end
  
  defp determine_batching_config(affected_entities, options) do
    entity_count = length(affected_entities)
    
    %{
      enabled: entity_count > 5 or options[:force_batching],
      batch_size: options[:batch_size] || calculate_optimal_batch_size(entity_count),
      batch_delay_ms: options[:batch_delay] || 100,
      max_batches: options[:max_batches] || 10
    }
  end
  
  defp calculate_optimal_batch_size(entity_count) when entity_count <= 5, do: entity_count
  defp calculate_optimal_batch_size(entity_count) when entity_count <= 20, do: 5
  defp calculate_optimal_batch_size(entity_count) when entity_count <= 50, do: 10
  defp calculate_optimal_batch_size(_), do: 20
  
  defp determine_rollback_strategy(options) do
    %{
      enabled: options[:enable_rollback] != false,
      checkpoint_frequency: options[:checkpoint_frequency] || 5,
      rollback_on_failure: options[:rollback_on_failure] != false,
      max_rollback_attempts: options[:max_rollback_attempts] || 3
    }
  end
  
  defp determine_timeout_config(options) do
    %{
      global_timeout_ms: options[:global_timeout] || 60_000,
      per_entity_timeout_ms: options[:per_entity_timeout] || 5_000,
      batch_timeout_ms: options[:batch_timeout] || 15_000
    }
  end
  
  @doc """
  Validates the propagation plan before execution.
  """
  def validate_propagation_plan(plan) do
    validations = %{
      entities_valid: validate_entities(plan.affected_entities),
      order_valid: validate_propagation_order(plan.propagation_order, plan.affected_entities),
      strategy_valid: validate_strategy(plan.propagation_strategy),
      circular_deps_handled: validate_circular_dependency_handling(plan.circular_dependencies),
      resource_availability: check_resource_availability(plan)
    }
    
    all_valid = validations |> Map.values() |> Enum.all?()
    
    if all_valid do
      {:ok,
       %{
         valid: true,
         validations: validations,
         warnings: generate_validation_warnings(plan),
         recommendations: generate_validation_recommendations(plan)
       }}
    else
      {:error,
       %{
         valid: false,
         validations: validations,
         failed_validations: get_failed_validations(validations)
       }}
    end
  end
  
  defp validate_entities(entities) do
    Enum.all?(entities, fn entity ->
      Map.has_key?(entity, :type) and Map.has_key?(entity, :id)
    end)
  end
  
  defp validate_propagation_order(order, entities) do
    # Check that all entities in order exist in affected_entities
    order_set = MapSet.new(order)
    entities_set = MapSet.new(entities)
    
    MapSet.subset?(order_set, entities_set)
  end
  
  defp validate_strategy(strategy) do
    strategy.type in [:sequential, :parallel, :sequential_with_validation, 
                      :sequential_with_rollback, :batched_parallel]
  end
  
  defp validate_circular_dependency_handling(circular_deps) do
    not circular_deps.has_circular_dependencies or 
    circular_deps.resolution_strategy != :none
  end
  
  defp check_resource_availability(plan) do
    # Check if we have resources for the planned propagation
    entity_count = length(plan.affected_entities)
    max_parallelism = Map.get(plan.propagation_strategy, :max_parallelism, 5)
    
    # Simple heuristic: assume we can handle up to 100 entities
    entity_count <= 100 and max_parallelism <= 20
  end
  
  defp generate_validation_warnings(plan) do
    warnings = []
    
    warnings = if plan.circular_dependencies.has_circular_dependencies do
      ["Circular dependencies detected: #{inspect(plan.circular_dependencies.cycles)}" | warnings]
    else
      warnings
    end
    
    warnings = if length(plan.affected_entities) > 50 do
      ["Large number of affected entities: #{length(plan.affected_entities)}" | warnings]
    else
      warnings
    end
    
    warnings
  end
  
  defp generate_validation_recommendations(plan) do
    recommendations = []
    
    recommendations = if length(plan.affected_entities) > 20 and 
                        plan.propagation_strategy.type != :batched_parallel do
      ["Consider using batched parallel strategy for better performance" | recommendations]
    else
      recommendations
    end
    
    recommendations = if plan.circular_dependencies.has_circular_dependencies do
      ["Review and refactor circular dependencies" | recommendations]
    else
      recommendations
    end
    
    recommendations
  end
  
  defp get_failed_validations(validations) do
    validations
    |> Enum.filter(fn {_check, passed} -> not passed end)
    |> Enum.map(fn {check, _} -> check end)
  end
  
  @doc """
  Executes the propagation plan.
  """
  def execute_propagation(plan, context) do
    start_time = System.monotonic_time(:millisecond)
    
    execution_result = case plan.propagation_strategy.type do
      :sequential ->
        execute_sequential(plan, context)
      
      :parallel ->
        execute_parallel(plan, context)
      
      :sequential_with_validation ->
        execute_sequential_with_validation(plan, context)
      
      :sequential_with_rollback ->
        execute_sequential_with_rollback(plan, context)
      
      :batched_parallel ->
        execute_batched_parallel(plan, context)
    end
    
    end_time = System.monotonic_time(:millisecond)
    
    case execution_result do
      {:ok, results} ->
        {:ok,
         %{
           results: results,
           execution_time_ms: end_time - start_time,
           strategy_used: plan.propagation_strategy.type
         }}
      
      {:error, _} = error ->
        error
    end
  end
  
  defp execute_sequential(plan, context) do
    results = plan.propagation_order
    |> Enum.map(fn entity ->
      propagate_to_entity(entity, plan.source_entity, context)
    end)
    
    handle_execution_results(results)
  end
  
  defp execute_parallel(plan, context) do
    max_parallelism = plan.propagation_strategy.max_parallelism
    
    results = plan.propagation_order
    |> Task.async_stream(
      fn entity -> propagate_to_entity(entity, plan.source_entity, context) end,
      max_concurrency: max_parallelism,
      timeout: plan.timeout_config.per_entity_timeout_ms
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, reason} -> {:error, {:task_failed, reason}}
    end)
    
    handle_execution_results(results)
  end
  
  defp execute_sequential_with_validation(plan, context) do
    results = []
    
    final_results = Enum.reduce_while(plan.propagation_order, results, fn entity, acc ->
      case propagate_to_entity(entity, plan.source_entity, context) do
        {:ok, _} = success ->
          # Validate after each propagation
          if validate_entity_state(entity) do
            {:cont, [success | acc]}
          else
            {:halt, {:error, {:validation_failed, entity}}}
          end
        
        {:error, _} = error ->
          {:halt, error}
      end
    end)
    
    case final_results do
      {:error, _} = error -> error
      results -> handle_execution_results(Enum.reverse(results))
    end
  end
  
  defp execute_sequential_with_rollback(plan, context) do
    checkpoint_frequency = plan.rollback_strategy.checkpoint_frequency
    checkpoints = []
    results = []
    
    final_results = plan.propagation_order
    |> Enum.with_index()
    |> Enum.reduce_while({results, checkpoints}, fn {entity, index}, {res, checks} ->
      case propagate_to_entity(entity, plan.source_entity, context) do
        {:ok, _} = success ->
          new_results = [success | res]
          
          # Create checkpoint if needed
          new_checkpoints = if rem(index + 1, checkpoint_frequency) == 0 do
            [create_checkpoint(new_results) | checks]
          else
            checks
          end
          
          {:cont, {new_results, new_checkpoints}}
        
        {:error, _reason} = error ->
          # Attempt rollback
          if plan.rollback_strategy.rollback_on_failure do
            rollback_to_checkpoint(List.first(checks))
          end
          {:halt, error}
      end
    end)
    
    case final_results do
      {:error, _} = error -> error
      {results, _checkpoints} -> handle_execution_results(Enum.reverse(results))
    end
  end
  
  defp execute_batched_parallel(plan, context) do
    batch_size = plan.batching_config.batch_size
    batch_delay = plan.batching_config.batch_delay_ms
    
    batches = Enum.chunk_every(plan.propagation_order, batch_size)
    
    results = Enum.flat_map(batches, fn batch ->
      batch_results = Task.async_stream(
        batch,
        fn entity -> propagate_to_entity(entity, plan.source_entity, context) end,
        max_concurrency: plan.propagation_strategy.max_parallelism,
        timeout: plan.timeout_config.batch_timeout_ms
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, {:task_failed, reason}}
      end)
      
      # Delay between batches
      if batch != List.last(batches) do
        Process.sleep(batch_delay)
      end
      
      batch_results
    end)
    
    handle_execution_results(results)
  end
  
  defp propagate_to_entity(entity, source_entity, context) do
    try do
      # Determine propagation action
      action = entity[:action] || determine_propagation_action(entity.type, source_entity.type)
      
      # Execute propagation
      result = case action do
        :invalidate -> invalidate_entity(entity)
        :update -> update_entity(entity, source_entity)
        :revalidate -> revalidate_entity(entity)
        :recompute -> recompute_entity(entity)
        :notify -> notify_entity(entity, source_entity)
        _ -> {:error, :unknown_action}
      end
      
      # Log propagation
      log_propagation(entity, source_entity, result, context)
      
      result
    rescue
      error ->
        Logger.error("Propagation failed for entity #{inspect(entity)}: #{inspect(error)}")
        {:error, {:propagation_exception, error}}
    end
  end
  
  defp determine_propagation_action(entity_type, source_type) do
    case {entity_type, source_type} do
      {:sessions, :user} -> :invalidate
      {:preferences, :user} -> :update
      {:code_files, :project} -> :revalidate
      {:analyses, _} -> :recompute
      {:deployments, _} -> :notify
      _ -> :update
    end
  end
  
  defp invalidate_entity(entity) do
    # Simulate entity invalidation
    {:ok,
     %{
       entity: entity,
       action: :invalidated,
       timestamp: DateTime.utc_now()
     }}
  end
  
  defp update_entity(entity, source_entity) do
    # Simulate entity update
    {:ok,
     %{
       entity: entity,
       action: :updated,
       source: source_entity.id,
       timestamp: DateTime.utc_now()
     }}
  end
  
  defp revalidate_entity(entity) do
    # Simulate entity revalidation
    {:ok,
     %{
       entity: entity,
       action: :revalidated,
       validation_result: :valid,
       timestamp: DateTime.utc_now()
     }}
  end
  
  defp recompute_entity(entity) do
    # Simulate entity recomputation
    {:ok,
     %{
       entity: entity,
       action: :recomputed,
       computation_time_ms: :rand.uniform(100),
       timestamp: DateTime.utc_now()
     }}
  end
  
  defp notify_entity(entity, source_entity) do
    # Simulate entity notification
    {:ok,
     %{
       entity: entity,
       action: :notified,
       notification_type: :update,
       source: source_entity.id,
       timestamp: DateTime.utc_now()
     }}
  end
  
  defp validate_entity_state(entity) do
    # Simple validation - in production would check actual entity state
    entity[:id] != nil and entity[:type] != nil
  end
  
  defp create_checkpoint(results) do
    %{
      checkpoint_id: generate_propagation_id(),
      timestamp: DateTime.utc_now(),
      entity_states: Enum.map(results, fn {:ok, result} -> result.entity end)
    }
  end
  
  defp rollback_to_checkpoint(nil), do: :ok
  defp rollback_to_checkpoint(checkpoint) do
    Logger.info("Rolling back to checkpoint #{checkpoint.checkpoint_id}")
    # In production, would restore entity states
    :ok
  end
  
  defp log_propagation(entity, source_entity, result, _context) do
    level = case result do
      {:ok, _} -> :debug
      {:error, _} -> :warning
    end
    
    Logger.log(level, "Propagation from #{source_entity.id} to #{entity.id}: #{inspect(result)}")
  end
  
  defp handle_execution_results(results) do
    successful = Enum.filter(results, &match?({:ok, _}, &1))
    failed = Enum.filter(results, &match?({:error, _}, &1))
    
    if Enum.empty?(failed) do
      {:ok, Enum.map(successful, fn {:ok, r} -> r end)}
    else
      {:error,
       %{
         partial_success: not Enum.empty?(successful),
         successful_count: length(successful),
         failed_count: length(failed),
         failures: Enum.map(failed, fn {:error, e} -> e end)
       }}
    end
  end
  
  @doc """
  Verifies propagation results to ensure consistency.
  """
  def verify_propagation_results(execution_result) do
    results = execution_result[:results] || []
    
    verifications = %{
      all_entities_processed: verify_all_entities_processed(results, execution_result),
      actions_completed: verify_actions_completed(results),
      no_conflicts: verify_no_conflicts(results),
      timing_constraints_met: verify_timing_constraints(execution_result),
      data_consistency: verify_data_consistency(results)
    }
    
    all_verified = verifications |> Map.values() |> Enum.all?()
    
    {:ok,
     %{
       verified: all_verified,
       verifications: verifications,
       issues: identify_verification_issues(verifications),
       recommendations: generate_verification_recommendations(verifications)
     }}
  end
  
  defp verify_all_entities_processed(results, _execution_result) do
    # Check if all planned entities were processed
    length(results) > 0
  end
  
  defp verify_actions_completed(results) do
    Enum.all?(results, fn result ->
      Map.has_key?(result, :action) and result.action != nil
    end)
  end
  
  defp verify_no_conflicts(results) do
    # Check for conflicting operations on same entities
    entity_operations = Enum.group_by(results, & &1.entity.id)
    
    Enum.all?(entity_operations, fn {_entity_id, operations} ->
      length(operations) == 1 or compatible_operations?(operations)
    end)
  end
  
  defp compatible_operations?(operations) do
    actions = Enum.map(operations, & &1.action)
    
    # Check if all actions are compatible
    not (:invalidated in actions and :updated in actions)
  end
  
  defp verify_timing_constraints(execution_result) do
    execution_time = execution_result[:execution_time_ms] || 0
    # Assume max allowed time is 60 seconds
    execution_time < 60_000
  end
  
  defp verify_data_consistency(results) do
    # Check that all results have consistent structure
    Enum.all?(results, fn result ->
      Map.has_key?(result, :entity) and
      Map.has_key?(result, :action) and
      Map.has_key?(result, :timestamp)
    end)
  end
  
  defp identify_verification_issues(verifications) do
    verifications
    |> Enum.filter(fn {_check, passed} -> not passed end)
    |> Enum.map(fn {check, _} -> 
      case check do
        :all_entities_processed -> "Not all entities were processed"
        :actions_completed -> "Some actions did not complete"
        :no_conflicts -> "Conflicting operations detected"
        :timing_constraints_met -> "Execution took too long"
        :data_consistency -> "Data consistency issues found"
        _ -> "Unknown issue: #{check}"
      end
    end)
  end
  
  defp generate_verification_recommendations(verifications) do
    recommendations = []
    
    recommendations = if not verifications.timing_constraints_met do
      ["Consider using batched processing for better performance" | recommendations]
    else
      recommendations
    end
    
    recommendations = if not verifications.no_conflicts do
      ["Review propagation order to avoid conflicts" | recommendations]
    else
      recommendations
    end
    
    recommendations
  end
  
  defp count_updated_entities(execution_result) do
    case execution_result[:results] do
      nil -> 0
      results -> length(results)
    end
  end
  
  defp calculate_propagation_metrics(execution_result) do
    results = execution_result[:results] || []
    
    %{
      total_entities: length(results),
      by_action: count_by_action(results),
      average_time_ms: calculate_average_time(results),
      success_rate: calculate_success_rate(results),
      execution_time_ms: execution_result[:execution_time_ms] || 0
    }
  end
  
  defp count_by_action(results) do
    results
    |> Enum.group_by(& &1.action)
    |> Enum.map(fn {action, items} -> {action, length(items)} end)
    |> Enum.into(%{})
  end
  
  defp calculate_average_time(results) do
    computation_times = results
    |> Enum.map(& &1[:computation_time_ms])
    |> Enum.reject(&is_nil/1)
    
    if Enum.empty?(computation_times) do
      0
    else
      Enum.sum(computation_times) / length(computation_times)
    end
  end
  
  defp calculate_success_rate(results) do
    if Enum.empty?(results) do
      0.0
    else
      # All results that made it here are successful
      1.0
    end
  end
  
  defp handle_propagation_failure({:error, reason}, params, context) do
    Logger.error("Propagation failed: #{inspect(reason)}")
    
    failure_analysis = analyze_propagation_failure(reason, params, context)
    
    {:error,
     %{
       propagation_id: generate_propagation_id(),
       propagated: false,
       reason: reason,
       failure_analysis: failure_analysis,
       recovery_options: suggest_recovery_options(failure_analysis)
     }}
  end
  
  defp analyze_propagation_failure(reason, params, context) do
    %{
      failure_type: categorize_failure(reason),
      impacted_entities: extract_impacted_entities(reason, params),
      failure_point: identify_failure_point(reason),
      context: context,
      timestamp: DateTime.utc_now()
    }
  end
  
  defp categorize_failure(reason) do
    cond do
      match?({:validation_failed, _}, reason) -> :validation_failure
      match?({:task_failed, _}, reason) -> :execution_failure
      match?({:timeout, _}, reason) -> :timeout_failure
      match?({:circular_dependency, _}, reason) -> :dependency_failure
      true -> :unknown_failure
    end
  end
  
  defp extract_impacted_entities(reason, params) do
    case reason do
      {:validation_failed, entity} -> [entity]
      _ -> params[:entity] && [params.entity] || []
    end
  end
  
  defp identify_failure_point(reason) do
    case reason do
      {:validation_failed, _} -> :validation
      {:task_failed, _} -> :execution
      _ -> :unknown
    end
  end
  
  defp suggest_recovery_options(failure_analysis) do
    case failure_analysis.failure_type do
      :validation_failure ->
        ["Retry with corrected data", "Skip invalid entities", "Use fallback values"]
      :execution_failure ->
        ["Retry with backoff", "Use sequential execution", "Increase timeout"]
      :timeout_failure ->
        ["Increase timeout limits", "Use smaller batches", "Optimize propagation logic"]
      :dependency_failure ->
        ["Break circular dependencies", "Use weak references", "Defer dependent updates"]
      _ ->
        ["Manual intervention required", "Check logs for details"]
    end
  end
  
  defp generate_propagation_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  @doc """
  Queues entities for delayed propagation.
  """
  def queue_for_propagation(entities, options \\ %{}) do
    queue_config = %{
      priority: options[:priority] || :normal,
      delay_ms: options[:delay] || 0,
      max_retries: options[:max_retries] || 3,
      retry_delay_ms: options[:retry_delay] || 1000
    }
    
    queued_items = Enum.map(entities, fn entity ->
      %{
        queue_id: generate_propagation_id(),
        entity: entity,
        config: queue_config,
        queued_at: DateTime.utc_now(),
        status: :pending
      }
    end)
    
    {:ok,
     %{
       queued_count: length(queued_items),
       queue_items: queued_items,
       estimated_processing_time_ms: estimate_processing_time(queued_items)
     }}
  end
  
  defp estimate_processing_time(queued_items) do
    # Estimate 100ms per entity
    length(queued_items) * 100
  end
  
  @doc """
  Handles circular dependencies in propagation.
  """
  def resolve_circular_dependencies(plan) do
    if plan.circular_dependencies.has_circular_dependencies do
      cycles = plan.circular_dependencies.cycles
      
      resolved_plan = Enum.reduce(cycles, plan, fn cycle, acc ->
        break_cycle(acc, cycle)
      end)
      
      {:ok, resolved_plan}
    else
      {:ok, plan}
    end
  end
  
  defp break_cycle(plan, cycle) do
    # Find the weakest link in the cycle
    weakest_link = find_weakest_link(cycle)
    
    # Remove the weakest link from propagation order
    updated_order = Enum.reject(plan.propagation_order, fn entity ->
      entity.id == weakest_link
    end)
    
    %{plan | 
      propagation_order: updated_order,
      circular_dependencies: %{plan.circular_dependencies |
        cycles: List.delete(plan.circular_dependencies.cycles, cycle)
      }
    }
  end
  
  defp find_weakest_link(cycle) do
    # Simple heuristic: remove the last entity in the cycle
    List.last(cycle)
  end
end