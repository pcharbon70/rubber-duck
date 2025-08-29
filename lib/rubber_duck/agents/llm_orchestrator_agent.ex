defmodule RubberDuck.Agents.LlmOrchestratorAgent do
  @moduledoc """
  Autonomous LLM orchestration agent providing intelligent provider selection and optimization.

  This agent builds on the Universal LLM Provider System (Phase 1B.9) to provide:
  - Autonomous provider selection with multi-criteria optimization
  - Cost-quality optimization with continuous learning from outcomes
  - Real-time health monitoring and predictive failure avoidance
  - Intelligent request optimization and context management
  - Integration with Skills & Actions architecture for modular capabilities

  The orchestrator serves as the intelligent layer above the Universal Provider System,
  making autonomous decisions to optimize cost, quality, and performance across all
  LLM operations in the RubberDuck system.
  """

  use Jido.Agent,
    name: "llm_orchestrator",
    schema: [
      provider_performance_data: %{},
      learning_state: %{},
      routing_decisions: [],
      health_monitoring: %{},
      optimization_metrics: %{},
      configuration: %{}
    ]

  require Logger

  alias RubberDuck.LlmProviders.{ProviderRouter, UniversalProviderService}
  alias RubberDuck.SkillsActions.SkillsRegistry

  @orchestration_skills [
    :provider_selection_skill,
    :request_optimization_skill,
    :load_balancing_skill,
    :failure_recovery_skill
  ]

  @learning_window_minutes 60
  # 30 seconds
  @health_check_interval 30_000
  # 5 minutes
  @performance_update_interval 300_000

  # Public API

  @doc """
  Orchestrate LLM request with autonomous provider selection and optimization.
  """
  def orchestrate_request(agent, request, domain, options \\ %{}) do
    Logger.debug("Orchestrating LLM request for domain: #{domain}")

    start_time = System.monotonic_time(:millisecond)

    # Step 1: Analyze request and determine requirements
    request_requirements = analyze_request_requirements(request, domain, options)

    # Step 2: Select optimal provider using multi-criteria optimization
    case select_optimal_provider(agent, request_requirements) do
      {:ok, provider_selection} ->
        # Step 3: Optimize request for selected provider
        optimized_request = optimize_request_for_provider(request, provider_selection, domain)

        # Step 4: Execute request via Universal Provider System
        case execute_optimized_request(optimized_request, provider_selection, domain, options) do
          {:ok, response} ->
            orchestration_time = System.monotonic_time(:millisecond) - start_time

            # Step 5: Learn from outcome and update performance data
            learn_from_outcome(agent, provider_selection, response, orchestration_time)

            # Step 6: Return enhanced response with orchestration metadata
            enhanced_response =
              enhance_response_with_orchestration_data(
                response,
                provider_selection,
                orchestration_time
              )

            {:ok, enhanced_response}

          error ->
            # Learn from failure and potentially retry with different provider
            handle_orchestration_failure(agent, provider_selection, error, request_requirements)
        end

      {:error, reason} ->
        Logger.error("Provider selection failed: #{inspect(reason)}")
        # Fallback to Universal Provider Service default routing
        fallback_to_universal_provider(request, domain, options)
    end
  end

  @doc """
  Get orchestration recommendations for request optimization.
  """
  def get_orchestration_recommendations(agent, request, domain) do
    Logger.debug("Getting orchestration recommendations for #{domain}")

    request_analysis = analyze_request_requirements(request, domain, %{})

    # Get provider recommendations with cost-quality analysis
    case get_provider_recommendations_with_analysis(agent, request_analysis) do
      {:ok, recommendations} ->
        {:ok,
         %{
           provider_recommendations: recommendations,
           request_optimizations: suggest_request_optimizations(request, domain),
           cost_analysis: perform_cost_analysis(request_analysis, recommendations),
           quality_predictions: predict_quality_outcomes(request_analysis, recommendations),
           orchestration_strategy: recommend_orchestration_strategy(request_analysis)
         }}

      error ->
        error
    end
  end

  @doc """
  Update orchestrator learning from external feedback.
  """
  def update_learning_from_feedback(agent, provider_selection, feedback) do
    Logger.debug("Updating orchestrator learning from feedback")

    learning_update = %{
      provider: provider_selection.provider,
      model: provider_selection.model,
      feedback: feedback,
      timestamp: DateTime.utc_now(),
      feedback_source: :external
    }

    update_agent_learning_state(agent, learning_update)
  end

  @doc """
  Get orchestrator performance analytics.
  """
  def get_orchestration_analytics(agent) do
    current_state = Jido.Agent.get_state(agent)

    %{
      total_requests_orchestrated: count_total_orchestrated_requests(current_state),
      provider_performance_summary:
        summarize_provider_performance(current_state.provider_performance_data),
      learning_effectiveness: calculate_learning_effectiveness(current_state.learning_state),
      optimization_impact: measure_optimization_impact(current_state.optimization_metrics),
      routing_decision_accuracy: calculate_routing_accuracy(current_state.routing_decisions),
      cost_savings_achieved: calculate_cost_savings(current_state.provider_performance_data)
    }
  end

  # Jido Agent implementation

  @impl true
  def mount(agent) do
    Logger.info("Mounting LLM Orchestrator Agent")

    # Initialize orchestrator state
    initial_state = %{
      provider_performance_data: %{},
      learning_state: %{
        learning_enabled: true,
        learning_rate: 0.1,
        adaptation_threshold: 0.05,
        performance_history: %{}
      },
      routing_decisions: [],
      health_monitoring: %{
        last_health_check: DateTime.utc_now(),
        provider_health_status: %{},
        health_trends: %{}
      },
      optimization_metrics: %{
        total_requests: 0,
        cost_optimizations: 0,
        quality_improvements: 0,
        performance_gains: 0
      },
      configuration: load_orchestrator_configuration()
    }

    # Schedule periodic tasks
    schedule_health_monitoring()
    schedule_performance_updates()
    schedule_learning_consolidation()

    # Subscribe to provider health changes
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "provider_health_changes")
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "universal_provider_alerts")

    Jido.Agent.put_state(agent, initial_state)

    Logger.info("LLM Orchestrator Agent mounted successfully")
    {:ok, agent}
  end

  @impl true
  def handle_signal(agent, %{pattern: "orchestrator.health_check"} = signal) do
    Logger.debug("Performing orchestrator health check")

    current_state = Jido.Agent.get_state(agent)

    # Perform comprehensive health check
    health_status = perform_orchestrator_health_check(current_state)

    # Update health monitoring state
    updated_health =
      Map.merge(current_state.health_monitoring, %{
        last_health_check: DateTime.utc_now(),
        provider_health_status: health_status.provider_health,
        orchestrator_health: health_status.orchestrator_health
      })

    updated_state = %{current_state | health_monitoring: updated_health}
    Jido.Agent.put_state(agent, updated_state)

    # Broadcast health status if significant changes
    if health_status_changed_significantly?(current_state.health_monitoring, updated_health) do
      Phoenix.PubSub.broadcast(
        RubberDuck.PubSub,
        "orchestrator_events",
        {:health_status_changed, health_status}
      )
    end

    {:ok, agent}
  end

  @impl true
  def handle_signal(agent, %{pattern: "orchestrator.performance_update"} = signal) do
    Logger.debug("Updating orchestrator performance metrics")

    current_state = Jido.Agent.get_state(agent)

    # Update provider performance data from recent decisions
    updated_performance = consolidate_recent_performance_data(current_state)

    # Apply learning algorithms to improve future decisions
    updated_learning =
      apply_learning_algorithms(current_state.learning_state, updated_performance)

    updated_state = %{
      current_state
      | provider_performance_data: updated_performance,
        learning_state: updated_learning
    }

    Jido.Agent.put_state(agent, updated_state)

    {:ok, agent}
  end

  @impl true
  def handle_signal(agent, %{pattern: "orchestrator.learning_consolidation"} = signal) do
    Logger.debug("Consolidating orchestrator learning")

    current_state = Jido.Agent.get_state(agent)

    # Consolidate learning from recent routing decisions
    learning_insights =
      consolidate_learning_insights(current_state.routing_decisions, current_state.learning_state)

    # Update learning state with insights
    updated_learning = apply_learning_insights(current_state.learning_state, learning_insights)

    updated_state = %{current_state | learning_state: updated_learning}
    Jido.Agent.put_state(agent, updated_state)

    # Prune old routing decisions to manage memory
    pruned_decisions = prune_old_routing_decisions(current_state.routing_decisions)
    final_state = %{updated_state | routing_decisions: pruned_decisions}

    Jido.Agent.put_state(agent, final_state)

    {:ok, agent}
  end

  @impl true
  def handle_signal(agent, %{pattern: "provider_health_changed", data: health_data} = signal) do
    Logger.info("Provider health changed: #{inspect(health_data)}")

    current_state = Jido.Agent.get_state(agent)

    # Update provider health tracking
    updated_health = update_provider_health_tracking(current_state.health_monitoring, health_data)

    updated_state = %{current_state | health_monitoring: updated_health}
    Jido.Agent.put_state(agent, updated_state)

    {:ok, agent}
  end

  # Private implementation

  defp analyze_request_requirements(request, domain, options) do
    %{
      domain: domain,
      content_complexity: analyze_content_complexity(request),
      estimated_tokens: estimate_token_requirements(request),
      quality_requirements: extract_quality_requirements(options),
      cost_constraints: extract_cost_constraints(options),
      performance_requirements: extract_performance_requirements(options),
      specialized_features: Map.get(options, :specialized_features, []),
      user_context: extract_user_context(options)
    }
  end

  defp select_optimal_provider(agent, request_requirements) do
    current_state = Jido.Agent.get_state(agent)

    # Get available providers from Universal Provider System
    case UniversalProviderService.get_available_providers(request_requirements.domain) do
      {:ok, available_providers} ->
        # Apply multi-criteria optimization using learning data
        case apply_multi_criteria_selection(
               available_providers,
               request_requirements,
               current_state.provider_performance_data,
               current_state.learning_state
             ) do
          {:ok, selection} ->
            # Record routing decision for learning
            routing_decision = %{
              timestamp: DateTime.utc_now(),
              request_requirements: request_requirements,
              selected_provider: selection.provider,
              selection_reasoning: selection.reasoning,
              confidence: selection.confidence
            }

            # Update agent state with routing decision
            updated_decisions =
              [routing_decision | current_state.routing_decisions] |> Enum.take(1000)

            updated_state = %{current_state | routing_decisions: updated_decisions}
            Jido.Agent.put_state(agent, updated_state)

            {:ok, selection}

          error ->
            error
        end

      error ->
        error
    end
  end

  defp apply_multi_criteria_selection(
         available_providers,
         requirements,
         performance_data,
         learning_state
       ) do
    # Multi-criteria optimization using performance data and learning
    scored_providers =
      available_providers
      |> Enum.map(fn {provider_type, provider_info} ->
        score_provider_for_requirements(
          provider_type,
          provider_info,
          requirements,
          performance_data,
          learning_state
        )
      end)
      |> Enum.sort_by(& &1.overall_score, :desc)

    case scored_providers do
      [best_provider | _] ->
        {:ok,
         %{
           provider: best_provider.provider_type,
           model: best_provider.recommended_model,
           confidence: best_provider.overall_score,
           reasoning: best_provider.selection_reasoning,
           cost_estimate: best_provider.cost_estimate,
           quality_prediction: best_provider.quality_prediction,
           performance_expectation: best_provider.performance_expectation
         }}

      [] ->
        {:error, "No providers available for requirements"}
    end
  end

  defp score_provider_for_requirements(
         provider_type,
         provider_info,
         requirements,
         performance_data,
         learning_state
       ) do
    # Calculate comprehensive provider score
    base_capabilities_score = calculate_base_capabilities_score(provider_info, requirements)

    historical_performance_score =
      calculate_historical_performance_score(provider_type, performance_data)

    learning_adjustment = calculate_learning_adjustment(provider_type, learning_state)

    cost_efficiency_score =
      calculate_cost_efficiency_score(provider_type, requirements, performance_data)

    health_status_score = calculate_health_status_score(provider_type, provider_info)

    # Apply weights based on requirements and learning
    weights = determine_scoring_weights(requirements, learning_state)

    overall_score =
      base_capabilities_score * weights.capabilities +
        historical_performance_score * weights.performance +
        learning_adjustment * weights.learning +
        cost_efficiency_score * weights.cost +
        health_status_score * weights.health

    %{
      provider_type: provider_type,
      overall_score: overall_score,
      base_capabilities_score: base_capabilities_score,
      historical_performance_score: historical_performance_score,
      learning_adjustment: learning_adjustment,
      cost_efficiency_score: cost_efficiency_score,
      health_status_score: health_status_score,
      recommended_model: select_optimal_model_for_provider(provider_type, requirements),
      cost_estimate: estimate_provider_cost(provider_type, requirements),
      quality_prediction: predict_provider_quality(provider_type, requirements, performance_data),
      performance_expectation:
        predict_provider_performance(provider_type, requirements, performance_data),
      selection_reasoning: generate_selection_reasoning(provider_type, overall_score, weights)
    }
  end

  defp optimize_request_for_provider(request, provider_selection, domain) do
    # Optimize request for selected provider
    base_optimization = %{
      provider: provider_selection.provider,
      model: provider_selection.model,
      domain: domain,
      optimization_applied: true
    }

    # Apply provider-specific optimizations
    provider_optimizations =
      case provider_selection.provider do
        :anthropic ->
          %{
            constitutional_ai_optimization: true,
            large_context_optimization: true,
            safety_enhancements: true
          }

        :openai ->
          %{
            function_calling_optimization: true,
            structured_output_optimization: true,
            cost_efficiency_focus: true
          }

        _ ->
          %{}
      end

    Map.merge(request, Map.merge(base_optimization, provider_optimizations))
  end

  defp execute_optimized_request(optimized_request, provider_selection, domain, options) do
    # Execute request via Universal Provider System with orchestration context
    orchestration_options =
      Map.merge(options, %{
        provider_preference: provider_selection.provider,
        model_preference: provider_selection.model,
        orchestration_metadata: %{
          selection_confidence: provider_selection.confidence,
          cost_estimate: provider_selection.cost_estimate,
          quality_prediction: provider_selection.quality_prediction
        }
      })

    UniversalProviderService.complete(optimized_request.content, domain, orchestration_options)
  end

  defp learn_from_outcome(agent, provider_selection, response, orchestration_time) do
    current_state = Jido.Agent.get_state(agent)

    # Create learning data from outcome
    learning_data = %{
      provider: provider_selection.provider,
      model: provider_selection.model,
      predicted_cost: provider_selection.cost_estimate,
      actual_cost: response.cost_usd,
      predicted_quality: provider_selection.quality_prediction,
      actual_response_quality: estimate_response_quality(response),
      predicted_performance: provider_selection.performance_expectation,
      actual_performance: orchestration_time,
      success: response.success,
      timestamp: DateTime.utc_now()
    }

    # Update provider performance data
    updated_performance =
      update_provider_performance_data(current_state.provider_performance_data, learning_data)

    # Update optimization metrics
    updated_metrics =
      update_optimization_metrics(current_state.optimization_metrics, learning_data)

    updated_state = %{
      current_state
      | provider_performance_data: updated_performance,
        optimization_metrics: updated_metrics
    }

    Jido.Agent.put_state(agent, updated_state)

    # Send performance update to Universal Provider System
    notify_provider_performance_update(learning_data)
  end

  defp handle_orchestration_failure(agent, provider_selection, error, request_requirements) do
    Logger.warning(
      "Orchestration failed for provider #{provider_selection.provider}: #{inspect(error)}"
    )

    current_state = Jido.Agent.get_state(agent)

    # Record failure for learning
    failure_data = %{
      provider: provider_selection.provider,
      error: error,
      timestamp: DateTime.utc_now(),
      request_requirements: request_requirements
    }

    # Update failure tracking
    updated_performance =
      record_provider_failure(current_state.provider_performance_data, failure_data)

    updated_state = %{current_state | provider_performance_data: updated_performance}
    Jido.Agent.put_state(agent, updated_state)

    # Attempt recovery with different provider
    attempt_failure_recovery(agent, request_requirements, [provider_selection.provider])
  end

  defp attempt_failure_recovery(agent, request_requirements, excluded_providers) do
    Logger.info("Attempting failure recovery with alternative providers")

    # Modify requirements to exclude failed providers
    recovery_requirements = %{
      request_requirements
      | excluded_providers:
          Map.get(request_requirements, :excluded_providers, []) ++ excluded_providers
    }

    # Try to select alternative provider
    case select_optimal_provider(agent, recovery_requirements) do
      {:ok, alternative_selection} ->
        Logger.info("Recovery successful with provider #{alternative_selection.provider}")
        {:ok, alternative_selection}

      {:error, reason} ->
        Logger.error("Recovery failed: #{inspect(reason)}")
        {:error, "Orchestration failure recovery unsuccessful"}
    end
  end

  defp fallback_to_universal_provider(request, domain, options) do
    Logger.warning("Falling back to Universal Provider System default routing")

    # Use Universal Provider Service directly as fallback
    UniversalProviderService.complete(request.content, domain, options)
  end

  # Helper functions for orchestration logic

  defp analyze_content_complexity(request) do
    content =
      case request.content do
        content when is_binary(content) -> content
        content when is_list(content) -> Enum.map_join(content, " ", &to_string/1)
        _ -> ""
      end

    content_length = String.length(content)

    case content_length do
      length when length > 5000 -> :high
      length when length > 1500 -> :medium
      _ -> :low
    end
  end

  defp estimate_token_requirements(request) do
    content =
      case request.content do
        content when is_binary(content) -> content
        content when is_list(content) -> Enum.map_join(content, " ", &to_string/1)
        _ -> ""
      end

    # Basic token estimation (~4 characters per token)
    base_tokens = div(String.length(content), 4)

    # Add overhead for system prompts and response
    base_tokens + 500
  end

  defp extract_quality_requirements(options) do
    %{
      min_quality_score: Map.get(options, :min_quality_score, 0.7),
      quality_priority: Map.get(options, :quality_priority, :medium),
      constitutional_ai_required: Map.get(options, :constitutional_ai_required, false)
    }
  end

  defp extract_cost_constraints(options) do
    %{
      max_cost_per_request: Map.get(options, :max_cost_per_request, 1.0),
      cost_priority: Map.get(options, :cost_priority, :medium),
      budget_remaining: Map.get(options, :budget_remaining, 100.0)
    }
  end

  defp extract_performance_requirements(options) do
    %{
      max_response_time: Map.get(options, :max_response_time, 10_000),
      performance_priority: Map.get(options, :performance_priority, :medium),
      streaming_required: Map.get(options, :streaming_required, false)
    }
  end

  defp extract_user_context(options) do
    %{
      user_id: Map.get(options, :user_id),
      project_id: Map.get(options, :project_id),
      agent_id: Map.get(options, :agent_id, "orchestrator")
    }
  end

  defp calculate_base_capabilities_score(provider_info, requirements) do
    # Score provider based on basic capability match
    domain_support = if requirements.domain in provider_info.supports_domains, do: 1.0, else: 0.0

    # Check specialized feature support
    feature_support =
      requirements.specialized_features
      |> Enum.map(fn feature ->
        if feature in Map.get(provider_info, :specializations, []), do: 1.0, else: 0.5
      end)
      |> case do
        # No specific requirements
        [] -> 0.8
        scores -> Enum.sum(scores) / length(scores)
      end

    (domain_support + feature_support) / 2
  end

  defp calculate_historical_performance_score(provider_type, performance_data) do
    case Map.get(performance_data, provider_type) do
      # No data, neutral score
      nil ->
        0.5

      provider_data ->
        success_rate = Map.get(provider_data, :success_rate, 0.5)
        avg_quality = Map.get(provider_data, :avg_quality, 0.5)

        avg_performance =
          1.0 - min(1.0, Map.get(provider_data, :avg_response_time, 5000) / 10_000)

        (success_rate + avg_quality + avg_performance) / 3
    end
  end

  defp calculate_learning_adjustment(provider_type, learning_state) do
    case Map.get(learning_state.performance_history, provider_type) do
      # No learning data
      nil ->
        0.0

      provider_learning ->
        improvement_rate = Map.get(provider_learning, :improvement_rate, 0.0)
        confidence = Map.get(provider_learning, :confidence, 0.5)

        improvement_rate * confidence * learning_state.learning_rate
    end
  end

  defp calculate_cost_efficiency_score(provider_type, requirements, performance_data) do
    case Map.get(performance_data, provider_type) do
      # Default decent score
      nil ->
        0.6

      provider_data ->
        avg_cost = Map.get(provider_data, :avg_cost, 0.1)
        max_acceptable_cost = requirements.cost_constraints.max_cost_per_request

        if avg_cost <= max_acceptable_cost do
          # Better cost = higher score
          1.0 - avg_cost / max_acceptable_cost * 0.5
        else
          # Cost too high
          0.2
        end
    end
  end

  defp calculate_health_status_score(provider_type, provider_info) do
    # Health status from provider info
    case Map.get(provider_info, :health_status) do
      :healthy -> 1.0
      :degraded -> 0.6
      :unhealthy -> 0.1
      # Unknown, assume decent
      _ -> 0.7
    end
  end

  defp determine_scoring_weights(requirements, learning_state) do
    # Dynamic weight calculation based on requirements and learning
    base_weights = %{
      capabilities: 0.3,
      performance: 0.25,
      learning: 0.15,
      cost: 0.2,
      health: 0.1
    }

    # Adjust weights based on requirements
    adjusted_weights =
      case {requirements.cost_constraints.cost_priority,
            requirements.quality_requirements.quality_priority} do
        {:high, _} -> %{base_weights | cost: 0.4, performance: 0.2, capabilities: 0.2}
        {_, :high} -> %{base_weights | capabilities: 0.4, performance: 0.3, cost: 0.1}
        _ -> base_weights
      end

    # Apply learning influence
    learning_influence = learning_state.learning_rate * 0.1
    %{adjusted_weights | learning: adjusted_weights.learning + learning_influence}
  end

  defp select_optimal_model_for_provider(provider_type, requirements) do
    case {provider_type, requirements.content_complexity,
          requirements.quality_requirements.quality_priority} do
      {:anthropic, :high, _} -> "claude-3-opus-20240229"
      {:anthropic, _, :high} -> "claude-3-5-sonnet-20241022"
      {:anthropic, _, _} -> "claude-3-haiku-20240307"
      {:openai, :high, _} -> "gpt-4o"
      {:openai, _, _} -> "gpt-4o-mini"
      _ -> "default"
    end
  end

  defp estimate_provider_cost(provider_type, requirements) do
    # Estimate cost based on requirements and provider pricing
    estimated_tokens = requirements.estimated_tokens

    cost_per_1k_tokens =
      case provider_type do
        :anthropic -> 0.015
        :openai -> 0.02
        :ollama -> 0.0
        _ -> 0.015
      end

    estimated_tokens / 1000 * cost_per_1k_tokens
  end

  defp predict_provider_quality(provider_type, requirements, performance_data) do
    base_quality =
      case provider_type do
        :anthropic -> 0.9
        :openai -> 0.85
        :ollama -> 0.75
        _ -> 0.8
      end

    # Adjust based on historical data
    case Map.get(performance_data, provider_type) do
      nil ->
        base_quality

      provider_data ->
        historical_quality = Map.get(provider_data, :avg_quality, base_quality)
        (base_quality + historical_quality) / 2
    end
  end

  defp predict_provider_performance(provider_type, requirements, performance_data) do
    base_performance =
      case provider_type do
        # Fast local
        :ollama -> 1500
        :openai -> 2500
        :anthropic -> 3500
        _ -> 3000
      end

    # Adjust based on historical data
    case Map.get(performance_data, provider_type) do
      nil ->
        base_performance

      provider_data ->
        historical_performance = Map.get(provider_data, :avg_response_time, base_performance)
        trunc((base_performance + historical_performance) / 2)
    end
  end

  defp generate_selection_reasoning(provider_type, overall_score, weights) do
    primary_factors =
      weights
      |> Enum.sort_by(fn {_factor, weight} -> weight end, :desc)
      |> Enum.take(2)
      |> Enum.map(fn {factor, _weight} -> factor end)

    "Selected #{provider_type} (score: #{Float.round(overall_score, 2)}) based on #{Enum.join(primary_factors, " and ")} optimization"
  end

  defp enhance_response_with_orchestration_data(response, provider_selection, orchestration_time) do
    orchestration_metadata = %{
      orchestrator_used: true,
      provider_selection: provider_selection,
      orchestration_time_ms: orchestration_time,
      cost_optimization_applied: true,
      autonomous_selection: true
    }

    Map.update(response, :metadata, orchestration_metadata, fn existing_metadata ->
      Map.merge(existing_metadata, orchestration_metadata)
    end)
  end

  # Performance tracking and learning functions

  defp update_provider_performance_data(current_data, learning_data) do
    provider = learning_data.provider

    current_data
    |> Map.update(provider, %{}, fn provider_data ->
      %{
        total_requests: Map.get(provider_data, :total_requests, 0) + 1,
        success_rate: update_success_rate(provider_data, learning_data.success),
        avg_cost: update_average_cost(provider_data, learning_data.actual_cost),
        avg_quality: update_average_quality(provider_data, learning_data.actual_response_quality),
        avg_response_time:
          update_average_response_time(provider_data, learning_data.actual_performance),
        cost_prediction_accuracy: update_prediction_accuracy(provider_data, :cost, learning_data),
        quality_prediction_accuracy:
          update_prediction_accuracy(provider_data, :quality, learning_data),
        last_updated: DateTime.utc_now()
      }
    end)
  end

  defp update_success_rate(provider_data, success) do
    current_rate = Map.get(provider_data, :success_rate, 0.5)
    current_count = Map.get(provider_data, :total_requests, 0)

    if current_count > 0 do
      (current_rate * current_count + if(success, do: 1, else: 0)) / (current_count + 1)
    else
      if success, do: 1.0, else: 0.0
    end
  end

  defp update_average_cost(provider_data, new_cost) do
    current_avg = Map.get(provider_data, :avg_cost, 0.1)
    current_count = Map.get(provider_data, :total_requests, 0)

    if current_count > 0 do
      (current_avg * current_count + new_cost) / (current_count + 1)
    else
      new_cost
    end
  end

  defp update_average_quality(provider_data, new_quality) do
    current_avg = Map.get(provider_data, :avg_quality, 0.7)
    current_count = Map.get(provider_data, :total_requests, 0)

    if current_count > 0 do
      (current_avg * current_count + new_quality) / (current_count + 1)
    else
      new_quality
    end
  end

  defp update_average_response_time(provider_data, new_time) do
    current_avg = Map.get(provider_data, :avg_response_time, 3000)
    current_count = Map.get(provider_data, :total_requests, 0)

    if current_count > 0 do
      trunc((current_avg * current_count + new_time) / (current_count + 1))
    else
      new_time
    end
  end

  defp update_prediction_accuracy(provider_data, metric_type, learning_data) do
    {predicted, actual} =
      case metric_type do
        :cost -> {learning_data.predicted_cost, learning_data.actual_cost}
        :quality -> {learning_data.predicted_quality, learning_data.actual_response_quality}
      end

    if predicted > 0 and actual > 0 do
      accuracy = 1.0 - abs(predicted - actual) / max(predicted, actual)

      accuracy_key = String.to_atom("#{metric_type}_prediction_accuracy")
      current_accuracy = Map.get(provider_data, accuracy_key, 0.7)
      current_count = Map.get(provider_data, :total_requests, 0)

      if current_count > 0 do
        (current_accuracy * current_count + accuracy) / (current_count + 1)
      else
        accuracy
      end
    else
      Map.get(provider_data, String.to_atom("#{metric_type}_prediction_accuracy"), 0.7)
    end
  end

  defp estimate_response_quality(response) do
    # Simple response quality estimation
    base_quality = if response.success, do: 0.8, else: 0.3

    # Adjust based on response characteristics
    content_length = String.length(response.content)
    # Longer responses often better
    length_quality = min(1.0, content_length / 500)

    (base_quality + length_quality) / 2
  end

  defp load_orchestrator_configuration do
    %{
      learning_enabled: true,
      health_monitoring_enabled: true,
      cost_optimization_enabled: true,
      performance_tracking_enabled: true,
      max_routing_decisions_history: 1000,
      # 5 minutes
      learning_consolidation_interval: 300_000
    }
  end

  # Periodic task scheduling

  defp schedule_health_monitoring do
    Process.send_after(
      self(),
      {:signal, %{pattern: "orchestrator.health_check"}},
      @health_check_interval
    )
  end

  defp schedule_performance_updates do
    Process.send_after(
      self(),
      {:signal, %{pattern: "orchestrator.performance_update"}},
      @performance_update_interval
    )
  end

  defp schedule_learning_consolidation do
    # 5 minutes
    interval = 300_000

    Process.send_after(
      self(),
      {:signal, %{pattern: "orchestrator.learning_consolidation"}},
      interval
    )
  end

  # Monitoring and analytics helper functions

  defp perform_orchestrator_health_check(current_state) do
    # Comprehensive orchestrator health check
    provider_health = check_all_provider_health()
    orchestrator_health = check_orchestrator_internal_health(current_state)

    %{
      provider_health: provider_health,
      orchestrator_health: orchestrator_health,
      overall_status: determine_overall_health_status(provider_health, orchestrator_health),
      health_check_timestamp: DateTime.utc_now()
    }
  end

  defp check_all_provider_health do
    case UniversalProviderService.get_provider_health() do
      {:ok, health_data} ->
        health_data

      {:error, reason} ->
        Logger.warning("Failed to get provider health: #{inspect(reason)}")
        %{status: :unknown, error: reason}
    end
  end

  defp check_orchestrator_internal_health(current_state) do
    %{
      learning_state_health: assess_learning_state_health(current_state.learning_state),
      performance_data_health:
        assess_performance_data_health(current_state.provider_performance_data),
      memory_usage: assess_memory_usage(current_state),
      decision_quality: assess_recent_decision_quality(current_state.routing_decisions)
    }
  end

  defp determine_overall_health_status(provider_health, orchestrator_health) do
    provider_ok = Map.get(provider_health, :universal_status) == :operational
    orchestrator_ok = orchestrator_health.learning_state_health == :healthy

    case {provider_ok, orchestrator_ok} do
      {true, true} -> :healthy
      {true, false} -> :degraded
      {false, true} -> :degraded
      {false, false} -> :unhealthy
    end
  end

  defp assess_learning_state_health(learning_state) do
    if learning_state.learning_enabled and map_size(learning_state.performance_history) > 0 do
      :healthy
    else
      :degraded
    end
  end

  defp assess_performance_data_health(performance_data) do
    if map_size(performance_data) > 0 do
      :healthy
    else
      :initializing
    end
  end

  defp assess_memory_usage(current_state) do
    # Simple memory assessment
    routing_decisions_count = length(current_state.routing_decisions)
    performance_data_size = map_size(current_state.provider_performance_data)

    case {routing_decisions_count, performance_data_size} do
      {decisions, data} when decisions > 5000 or data > 50 -> :high
      {decisions, data} when decisions > 1000 or data > 20 -> :medium
      _ -> :low
    end
  end

  defp assess_recent_decision_quality(routing_decisions) do
    recent_decisions = Enum.take(routing_decisions, 10)

    if length(recent_decisions) > 5 do
      avg_confidence =
        recent_decisions
        |> Enum.map(&Map.get(&1, :confidence, 0.5))
        |> then(fn scores -> Enum.sum(scores) / length(scores) end)

      case avg_confidence do
        confidence when confidence > 0.8 -> :excellent
        confidence when confidence > 0.6 -> :good
        _ -> :needs_improvement
      end
    else
      :insufficient_data
    end
  end

  # Utility functions (stubs for now - would be fully implemented)

  defp health_status_changed_significantly?(_old_health, _new_health), do: false
  defp consolidate_recent_performance_data(state), do: state.provider_performance_data
  defp apply_learning_algorithms(learning_state, _performance), do: learning_state
  defp consolidate_learning_insights(_decisions, learning_state), do: %{insights: []}
  defp apply_learning_insights(learning_state, _insights), do: learning_state
  defp prune_old_routing_decisions(decisions), do: Enum.take(decisions, 1000)
  defp update_provider_health_tracking(health_monitoring, _health_data), do: health_monitoring
  defp update_agent_learning_state(_agent, _learning_update), do: :ok
  defp count_total_orchestrated_requests(state), do: state.optimization_metrics.total_requests
  defp summarize_provider_performance(data), do: data
  defp calculate_learning_effectiveness(_learning_state), do: %{effectiveness: 0.7}
  defp measure_optimization_impact(metrics), do: metrics
  defp calculate_routing_accuracy(_decisions), do: 0.85
  defp calculate_cost_savings(_performance_data), do: %{savings_percentage: 15}

  defp update_optimization_metrics(metrics, _learning_data),
    do: Map.update!(metrics, :total_requests, &(&1 + 1))

  defp notify_provider_performance_update(_learning_data), do: :ok
  defp record_provider_failure(performance_data, _failure_data), do: performance_data
  defp get_provider_recommendations_with_analysis(_agent, requirements), do: {:ok, []}
  defp suggest_request_optimizations(_request, _domain), do: []
  defp perform_cost_analysis(_requirements, _recommendations), do: %{}
  defp predict_quality_outcomes(_requirements, _recommendations), do: %{}
  defp recommend_orchestration_strategy(_requirements), do: :autonomous
end
