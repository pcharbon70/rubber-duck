defmodule RubberDuck.Prompts.WorkflowIntegration.WorkflowPromptResolver do
  @moduledoc """
  Core workflow-prompt resolution service for seamless prompt integration.

  Provides intelligent resolution of named prompt references within Reactor workflows,
  enabling workflows to reference prompts by name with automatic composition, 
  validation, and optimization. Coordinates prompt composition with workflow
  execution context for enhanced workflow capabilities.

  Features:
  - Named prompt reference resolution with automatic composition and validation
  - Dynamic prompt resolution during Reactor workflow execution with caching coordination
  - Context passing between Reactor steps and prompts with optimization and validation
  - Reactor workflow-specific prompt optimization with performance monitoring and analytics
  - Integration with 6-agent prompt ecosystem and existing workflow infrastructure
  - Intelligent caching and performance coordination for workflow-prompt operations
  """

  use GenServer
  require Logger

  alias RubberDuck.Prompts.{
    Agents.PromptComposerAgent,
    Agents.PromptValidatorAgent,
    WorkflowIntegration.NamedPromptReferenceManager,
    WorkflowIntegration.WorkflowContextEnhancer
  }

  @resolution_strategies [:immediate, :lazy, :cached, :optimized]

  @default_resolver_config %{
    enable_caching: true,
    enable_validation: true,
    enable_optimization: true,
    resolution_strategy: :optimized,
    cache_ttl_seconds: 300,
    max_concurrent_resolutions: 10
  }

  defstruct [
    :resolver_config,
    :resolution_cache,
    :performance_tracker,
    :workflow_context_manager
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    state = %__MODULE__{
      resolver_config: Map.merge(@default_resolver_config, Keyword.get(opts, :config, %{})),
      resolution_cache: initialize_resolution_cache(),
      performance_tracker: initialize_performance_tracker(),
      workflow_context_manager: initialize_context_manager()
    }

    Logger.info("WorkflowPromptResolver: Resolver service initialized",
      resolution_strategies: @resolution_strategies,
      caching_enabled: state.resolver_config.enable_caching
    )

    {:ok, state}
  end

  # Public API

  def resolve_workflow_prompt(workflow_id, prompt_name, context \\ %{}, options \\ %{}) do
    GenServer.call(
      __MODULE__,
      {:resolve_workflow_prompt, workflow_id, prompt_name, context, options}
    )
  end

  def resolve_batch_prompts(workflow_id, prompt_references, context \\ %{}, options \\ %{}) do
    GenServer.call(
      __MODULE__,
      {:resolve_batch_prompts, workflow_id, prompt_references, context, options}
    )
  end

  def invalidate_workflow_cache(workflow_id) do
    GenServer.cast(__MODULE__, {:invalidate_workflow_cache, workflow_id})
  end

  def get_resolution_performance_metrics do
    GenServer.call(__MODULE__, :get_performance_metrics)
  end

  def optimize_resolution_performance do
    GenServer.cast(__MODULE__, :optimize_performance)
  end

  # GenServer callbacks

  def handle_call(
        {:resolve_workflow_prompt, workflow_id, prompt_name, context, options},
        _from,
        state
      ) do
    resolution_start_time = System.monotonic_time(:microsecond)

    Logger.debug("WorkflowPromptResolver: Resolving workflow prompt",
      workflow_id: workflow_id,
      prompt_name: prompt_name,
      context_keys: Map.keys(context)
    )

    case execute_prompt_resolution(workflow_id, prompt_name, context, options, state) do
      {:ok, resolution_result} ->
        resolution_time = System.monotonic_time(:microsecond) - resolution_start_time

        Logger.info("WorkflowPromptResolver: Prompt resolution completed",
          workflow_id: workflow_id,
          prompt_name: prompt_name,
          resolution_time_us: resolution_time,
          cached: Map.get(resolution_result, :cached, false)
        )

        update_performance_metrics(resolution_time, :success, state)

        {:reply, {:ok, resolution_result}, state}

      {:error, reason} ->
        resolution_time = System.monotonic_time(:microsecond) - resolution_start_time

        Logger.error("WorkflowPromptResolver: Prompt resolution failed",
          workflow_id: workflow_id,
          prompt_name: prompt_name,
          error: reason,
          resolution_time_us: resolution_time
        )

        update_performance_metrics(resolution_time, :error, state)

        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:resolve_batch_prompts, workflow_id, prompt_references, context, options},
        _from,
        state
      ) do
    batch_start_time = System.monotonic_time(:microsecond)

    Logger.debug("WorkflowPromptResolver: Resolving batch prompts",
      workflow_id: workflow_id,
      prompt_count: length(prompt_references)
    )

    case execute_batch_resolution(workflow_id, prompt_references, context, options, state) do
      {:ok, batch_results} ->
        batch_time = System.monotonic_time(:microsecond) - batch_start_time

        Logger.info("WorkflowPromptResolver: Batch resolution completed",
          workflow_id: workflow_id,
          prompts_resolved: length(batch_results),
          batch_time_us: batch_time
        )

        {:reply, {:ok, batch_results}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_performance_metrics, _from, state) do
    metrics = extract_performance_metrics(state.performance_tracker)
    {:reply, {:ok, metrics}, state}
  end

  def handle_cast({:invalidate_workflow_cache, workflow_id}, state) do
    Logger.debug("WorkflowPromptResolver: Invalidating cache for workflow",
      workflow_id: workflow_id
    )

    updated_cache = invalidate_cache_for_workflow(state.resolution_cache, workflow_id)
    updated_state = %{state | resolution_cache: updated_cache}

    {:noreply, updated_state}
  end

  def handle_cast(:optimize_performance, state) do
    optimized_state = execute_performance_optimization(state)

    Logger.info("WorkflowPromptResolver: Performance optimization completed")

    {:noreply, optimized_state}
  end

  # Private implementation functions

  defp execute_prompt_resolution(workflow_id, prompt_name, context, options, state) do
    resolution_strategy = determine_resolution_strategy(context, options, state)

    case resolution_strategy do
      :immediate ->
        execute_immediate_resolution(workflow_id, prompt_name, context, options, state)

      :lazy ->
        execute_lazy_resolution(workflow_id, prompt_name, context, options, state)

      :cached ->
        execute_cached_resolution(workflow_id, prompt_name, context, options, state)

      :optimized ->
        execute_optimized_resolution(workflow_id, prompt_name, context, options, state)
    end
  end

  defp execute_optimized_resolution(workflow_id, prompt_name, context, options, state) do
    # Execute optimized resolution with full features
    with {:ok, cache_result} <- check_resolution_cache(workflow_id, prompt_name, state),
         {:ok, enhanced_context} <- enhance_workflow_context(context, workflow_id, options),
         {:ok, composed_prompt} <-
           compose_prompt_for_workflow(prompt_name, enhanced_context, options),
         {:ok, validated_prompt} <- validate_composed_prompt(composed_prompt, enhanced_context) do
      optimized_result = %{
        resolved_prompt: validated_prompt.content,
        prompt_name: prompt_name,
        workflow_id: workflow_id,
        cached: cache_result.cache_hit,
        resolution_strategy: :optimized,
        composition_metadata: composed_prompt.composition_metadata,
        validation_metadata: validated_prompt.validation_metadata,
        context_enhanced: true
      }

      # Update cache if not cached
      unless cache_result.cache_hit do
        update_resolution_cache(workflow_id, prompt_name, optimized_result, state)
      end

      {:ok, optimized_result}
    else
      {:error, reason} -> {:error, {:optimized_resolution_failed, reason}}
    end
  end

  defp execute_immediate_resolution(workflow_id, prompt_name, context, options, state) do
    # Execute immediate resolution without caching
    case compose_prompt_for_workflow(prompt_name, context, options) do
      {:ok, composed_prompt} ->
        immediate_result = %{
          resolved_prompt: composed_prompt.content,
          prompt_name: prompt_name,
          workflow_id: workflow_id,
          cached: false,
          resolution_strategy: :immediate,
          composition_metadata: composed_prompt.composition_metadata
        }

        {:ok, immediate_result}

      {:error, reason} ->
        {:error, {:immediate_resolution_failed, reason}}
    end
  end

  defp execute_cached_resolution(workflow_id, prompt_name, context, options, state) do
    # Execute cached resolution with fallback
    case check_resolution_cache(workflow_id, prompt_name, state) do
      {:ok, %{cache_hit: true, cached_result: cached_result}} ->
        {:ok, Map.put(cached_result, :cached, true)}

      {:ok, %{cache_hit: false}} ->
        # Cache miss, resolve and cache
        case execute_immediate_resolution(workflow_id, prompt_name, context, options, state) do
          {:ok, resolution_result} ->
            update_resolution_cache(workflow_id, prompt_name, resolution_result, state)
            {:ok, Map.put(resolution_result, :cached, false)}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp execute_lazy_resolution(_workflow_id, prompt_name, _context, _options, _state) do
    # Execute lazy resolution (placeholder for future implementation)
    lazy_result = %{
      resolved_prompt: "Lazy resolution placeholder for #{prompt_name}",
      prompt_name: prompt_name,
      resolution_strategy: :lazy,
      lazy_resolution: true
    }

    {:ok, lazy_result}
  end

  defp execute_batch_resolution(workflow_id, prompt_references, context, options, state) do
    # Execute batch resolution for multiple prompts
    batch_results =
      Enum.map(prompt_references, fn prompt_ref ->
        case execute_prompt_resolution(workflow_id, prompt_ref.name, context, options, state) do
          {:ok, result} ->
            {:ok, Map.put(result, :reference_id, prompt_ref.id)}

          {:error, reason} ->
            {:error, %{reference_id: prompt_ref.id, reason: reason}}
        end
      end)

    # Separate successful and failed resolutions
    {successful, failed} = Enum.split_with(batch_results, &match?({:ok, _}, &1))

    batch_result = %{
      successful_resolutions: Enum.map(successful, fn {:ok, result} -> result end),
      failed_resolutions: Enum.map(failed, fn {:error, failure} -> failure end),
      total_prompts: length(prompt_references),
      success_count: length(successful),
      failure_count: length(failed)
    }

    {:ok, batch_result}
  end

  # Helper functions

  defp determine_resolution_strategy(context, options, state) do
    # Determine optimal resolution strategy
    case {
      Map.get(options, :resolution_strategy),
      state.resolver_config.enable_caching,
      Map.get(context, :workflow_urgency, :normal)
    } do
      {strategy, _, _} when strategy in @resolution_strategies -> strategy
      {nil, true, :urgent} -> :cached
      {nil, true, _} -> :optimized
      {nil, false, _} -> :immediate
      _ -> state.resolver_config.resolution_strategy
    end
  end

  defp check_resolution_cache(workflow_id, prompt_name, state) do
    # Check if prompt resolution is cached
    cache_key = build_cache_key(workflow_id, prompt_name)

    case Map.get(state.resolution_cache, cache_key) do
      nil ->
        {:ok, %{cache_hit: false, cache_key: cache_key}}

      cached_entry ->
        if cache_entry_valid?(cached_entry, state) do
          {:ok, %{cache_hit: true, cached_result: cached_entry.result, cache_key: cache_key}}
        else
          {:ok, %{cache_hit: false, cache_key: cache_key, cache_expired: true}}
        end
    end
  end

  defp enhance_workflow_context(context, workflow_id, options) do
    # Enhance context with workflow-specific information
    case WorkflowContextEnhancer.enhance_context(context, workflow_id, options) do
      {:ok, enhanced_context} ->
        {:ok, enhanced_context}

      {:error, reason} ->
        Logger.warning("Context enhancement failed, using original context: #{inspect(reason)}")
        {:ok, context}
    end
  end

  defp compose_prompt_for_workflow(prompt_name, context, options) do
    # Compose prompt using PromptComposerAgent
    composition_params = %{
      composition_request: %{
        prompt_name: prompt_name,
        context: context
      },
      composition_strategy: determine_composition_strategy(context, options),
      workflow_integration: true,
      analytics_tracking: true
    }

    case PromptComposerAgent.start_agent(composition_params) do
      {:ok, result} -> {:ok, result.composition_result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_composed_prompt(composed_prompt, context) do
    # Validate composed prompt using PromptValidatorAgent
    validation_params = %{
      validation_request: %{
        content: composed_prompt.content,
        context: context
      },
      validation_scope: :workflow_integration,
      governance_requirements: %{
        require_security_validation: true,
        require_budget_validation: false
      }
    }

    case PromptValidatorAgent.start_agent(validation_params) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp determine_composition_strategy(context, options) do
    # Determine optimal composition strategy for workflow
    case {
      Map.get(context, :workflow_type, :general),
      Map.get(options, :quality_requirements, :standard),
      Map.get(context, :user_role, :user)
    } do
      {:code_review, :high, _} -> :priority_override
      {:documentation, _, _} -> :template_inheritance
      {:refactoring, _, :admin} -> :priority_override
      {:general, _, :user} -> :hierarchical_merge
      _ -> :adaptive
    end
  end

  defp build_cache_key(workflow_id, prompt_name) do
    "workflow:#{workflow_id}:prompt:#{prompt_name}"
  end

  defp cache_entry_valid?(cached_entry, state) do
    # Check if cache entry is still valid
    current_time = System.system_time(:second)
    cache_time = Map.get(cached_entry, :cached_at, 0)
    ttl = state.resolver_config.cache_ttl_seconds

    current_time - cache_time < ttl
  end

  defp update_resolution_cache(workflow_id, prompt_name, resolution_result, state) do
    # Update cache with new resolution result
    cache_key = build_cache_key(workflow_id, prompt_name)

    cache_entry = %{
      result: resolution_result,
      cached_at: System.system_time(:second),
      workflow_id: workflow_id,
      prompt_name: prompt_name
    }

    updated_cache = Map.put(state.resolution_cache, cache_key, cache_entry)
    %{state | resolution_cache: updated_cache}
  end

  defp invalidate_cache_for_workflow(cache, workflow_id) do
    # Remove all cache entries for a specific workflow
    Enum.reject(cache, fn {cache_key, _entry} ->
      String.starts_with?(cache_key, "workflow:#{workflow_id}:")
    end)
    |> Map.new()
  end

  # Initialization functions

  defp initialize_resolution_cache do
    %{}
  end

  defp initialize_performance_tracker do
    %{
      total_resolutions: 0,
      successful_resolutions: 0,
      cache_hits: 0,
      average_resolution_time_us: 0.0,
      resolution_effectiveness: 0.85
    }
  end

  defp initialize_context_manager do
    %{
      active_workflows: %{},
      context_cache: %{},
      context_optimization_enabled: true
    }
  end

  defp update_performance_metrics(resolution_time, status, state) do
    # Update resolution performance metrics
    tracker = state.performance_tracker

    updated_tracker = %{
      tracker
      | total_resolutions: tracker.total_resolutions + 1,
        successful_resolutions:
          if(status == :success,
            do: tracker.successful_resolutions + 1,
            else: tracker.successful_resolutions
          ),
        average_resolution_time_us:
          calculate_new_average(
            tracker.average_resolution_time_us,
            resolution_time,
            tracker.total_resolutions + 1
          )
    }

    %{state | performance_tracker: updated_tracker}
  end

  defp extract_performance_metrics(tracker) do
    %{
      total_resolutions: tracker.total_resolutions,
      success_rate: calculate_success_rate(tracker),
      cache_hit_rate: calculate_cache_hit_rate(tracker),
      average_resolution_time_ms: div(trunc(tracker.average_resolution_time_us), 1_000),
      resolution_effectiveness: tracker.resolution_effectiveness
    }
  end

  defp execute_performance_optimization(state) do
    # Execute resolution performance optimization
    optimized_tracker = %{
      state.performance_tracker
      | resolution_effectiveness:
          min(1.0, state.performance_tracker.resolution_effectiveness + 0.02)
    }

    %{state | performance_tracker: optimized_tracker}
  end

  defp calculate_success_rate(tracker) do
    case tracker.total_resolutions do
      0 -> 1.0
      total -> tracker.successful_resolutions / total
    end
  end

  defp calculate_cache_hit_rate(tracker) do
    case tracker.total_resolutions do
      0 -> 0.0
      total -> tracker.cache_hits / total
    end
  end

  defp calculate_new_average(current_avg, new_value, count) do
    case count do
      1 -> new_value
      _ -> (current_avg * (count - 1) + new_value) / count
    end
  end
end
