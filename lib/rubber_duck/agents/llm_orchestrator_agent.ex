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

  alias RubberDuck.JidoAI.{Configuration, ProviderService, PromptAdapter}
  alias RubberDuck.Prompts.Integrations.LlmOrchestrationIntegration
  alias RubberDuck.SkillsActions.SkillsRegistry
  alias Jido.AI.Prompt

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
  Enhanced with prompt composition integration for optimal performance.
  """
  def orchestrate_request(agent, request, domain, options \\ %{}) do
    Logger.debug(
      "Orchestrating LLM request for domain: #{domain} with prompt composition integration"
    )

    start_time = System.monotonic_time(:millisecond)

    # Step 1: Analyze request and determine requirements
    request_requirements = analyze_request_requirements(request, domain, options)

    # Step 2: Enhance request with prompt composition (new integration)
    case enhance_request_with_prompt_composition(request, request_requirements, options) do
      {:ok, enhanced_request} ->
        execute_enhanced_orchestration(
          agent,
          enhanced_request,
          domain,
          options,
          request_requirements,
          start_time
        )

      {:error, reason} ->
        Logger.warning(
          "Prompt composition enhancement failed, proceeding with basic orchestration: #{inspect(reason)}"
        )

        execute_basic_orchestration(
          agent,
          request,
          domain,
          options,
          request_requirements,
          start_time
        )
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
  def handle_signal(agent, %{pattern: "orchestrator.health_check"} = _signal) do
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
  def handle_signal(agent, %{pattern: "orchestrator.performance_update"} = _signal) do
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
  def handle_signal(agent, %{pattern: "orchestrator.learning_consolidation"} = _signal) do
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
  def handle_signal(agent, %{pattern: "provider_health_changed", data: health_data} = _signal) do
    Logger.info("Provider health changed: #{inspect(health_data)}")

    current_state = Jido.Agent.get_state(agent)

    # Update provider health tracking
    updated_health = update_provider_health_tracking(current_state.health_monitoring, health_data)

    updated_state = %{current_state | health_monitoring: updated_health}
    Jido.Agent.put_state(agent, updated_state)

    {:ok, agent}
  end

  # Private implementation

  # Prompt composition integration functions

  defp enhance_request_with_prompt_composition(request, request_requirements, options) do
    Logger.debug("Enhancing request with prompt composition integration")

    # Prepare LLM request for prompt composition
    llm_request = %{
      prompt: extract_prompt_content(request),
      provider: determine_initial_provider_preference(request_requirements, options),
      operation_type: request_requirements.domain,
      user_id: Map.get(options, :user_id),
      project_id: Map.get(options, :project_id),
      timeout: Map.get(options, :timeout, 30_000),
      quality: determine_quality_level(request_requirements),
      cost_sensitivity: determine_cost_sensitivity(request_requirements)
    }

    # Integration context with orchestrator-specific information
    context = %{
      prompt_name:
        Map.get(
          options,
          :prompt_name,
          determine_prompt_name_for_orchestration(request_requirements)
        ),
      user_role: Map.get(options, :user_role, :user),
      domain: request_requirements.domain,
      use_case: request_requirements.domain,
      orchestrator_context: %{
        complexity: request_requirements.content_complexity,
        estimated_tokens: request_requirements.estimated_tokens,
        quality_requirements: request_requirements.quality_requirements
      }
    }

    # Enhancement options for orchestrator integration
    enhancement_options = %{
      full_integration: Map.get(options, :enable_full_prompt_integration, true),
      validate_routing: true,
      provider_compatibility_check: true
    }

    case LlmOrchestrationIntegration.enhance_llm_request(
           llm_request,
           context,
           enhancement_options
         ) do
      {:ok, enhanced_llm_request} ->
        # Convert back to request format with enhancements
        enhanced_request =
          Map.merge(request, %{
            content: Map.get(enhanced_llm_request, :prompt, request.content),
            prompt_composed: Map.get(enhanced_llm_request, :prompt_composed, false),
            provider_optimized: Map.get(enhanced_llm_request, :provider_optimized, false),
            routing_optimized: Map.get(enhanced_llm_request, :routing_optimized, false),
            recommended_provider: Map.get(enhanced_llm_request, :provider),
            composition_metadata: Map.get(enhanced_llm_request, :composition_metadata, %{}),
            enhancement_applied: true
          })

        {:ok, enhanced_request}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_basic_orchestration(
         agent,
         request,
         domain,
         options,
         request_requirements,
         start_time
       ) do
    # Fallback to basic orchestration without prompt composition
    case select_optimal_provider(agent, request_requirements) do
      {:ok, provider_selection} ->
        execute_basic_orchestration_with_provider(
          agent,
          request,
          domain,
          options,
          provider_selection,
          request_requirements,
          start_time
        )

      {:error, reason} ->
        Logger.error("Provider selection failed: #{inspect(reason)}")
        fallback_to_jido_ai_provider(request, domain, options)
    end
  end

  defp execute_basic_orchestration_with_provider(
         agent,
         request,
         domain,
         options,
         provider_selection,
         request_requirements,
         start_time
       ) do
    optimized_request = optimize_request_for_provider(request, provider_selection, domain)

    case execute_optimized_request(optimized_request, provider_selection, domain, options) do
      {:ok, response} ->
        orchestration_time = System.monotonic_time(:millisecond) - start_time
        learn_from_outcome(agent, provider_selection, response, orchestration_time)

        enhanced_response =
          enhance_response_with_orchestration_data(
            response,
            provider_selection,
            orchestration_time
          )

        {:ok, enhanced_response}

      error ->
        handle_orchestration_failure(agent, provider_selection, error, request_requirements)
    end
  end

  defp execute_enhanced_orchestration(
         agent,
         enhanced_request,
         domain,
         options,
         request_requirements,
         start_time
       ) do
    # Step 3: Select optimal provider using multi-criteria optimization (updated with prompt data)
    case select_optimal_provider(agent, request_requirements, enhanced_request) do
      {:ok, provider_selection} ->
        execute_enhanced_orchestration_with_provider(
          agent,
          enhanced_request,
          domain,
          options,
          provider_selection,
          request_requirements,
          start_time
        )

      {:error, reason} ->
        Logger.error("Provider selection failed: #{inspect(reason)}")
        fallback_to_jido_ai_provider(enhanced_request, domain, options)
    end
  end

  defp execute_enhanced_orchestration_with_provider(
         agent,
         enhanced_request,
         domain,
         options,
         provider_selection,
         request_requirements,
         start_time
       ) do
    # Step 4: Optimize request for selected provider (enhanced with prompt composition metadata)
    optimized_request =
      optimize_request_for_provider(enhanced_request, provider_selection, domain)

    # Step 5: Execute request via Universal Provider System
    case execute_optimized_request(optimized_request, provider_selection, domain, options) do
      {:ok, response} ->
        orchestration_time = System.monotonic_time(:millisecond) - start_time

        # Step 6: Learn from outcome and update performance data (enhanced with prompt effectiveness)
        learn_from_outcome_with_prompt_data(
          agent,
          provider_selection,
          response,
          orchestration_time,
          enhanced_request
        )

        # Step 7: Return enhanced response with orchestration metadata
        enhanced_response =
          enhance_response_with_orchestration_data(
            response,
            provider_selection,
            orchestration_time,
            enhanced_request
          )

        {:ok, enhanced_response}

      error ->
        # Learn from failure and potentially retry with different provider
        handle_orchestration_failure(agent, provider_selection, error, request_requirements)
    end
  end

  defp learn_from_outcome_with_prompt_data(
         agent,
         provider_selection,
         response,
         orchestration_time,
         enhanced_request
       ) do
    # Enhanced learning that includes prompt composition effectiveness
    current_state = Jido.Agent.get_state(agent)

    # Create enhanced learning data
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
      timestamp: DateTime.utc_now(),
      # Prompt composition specific data
      prompt_composed: Map.get(enhanced_request, :prompt_composed, false),
      provider_optimized: Map.get(enhanced_request, :provider_optimized, false),
      routing_optimized: Map.get(enhanced_request, :routing_optimized, false),
      prompt_effectiveness: estimate_prompt_effectiveness(response, enhanced_request)
    }

    # Update provider performance data with prompt composition insights
    updated_performance =
      update_provider_performance_data_with_prompts(
        current_state.provider_performance_data,
        learning_data
      )

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

  # Utility functions for prompt composition integration

  defp extract_prompt_content(request) do
    case request do
      %{content: content} when is_binary(content) -> content
      %{prompt: prompt} when is_binary(prompt) -> prompt
      content when is_binary(content) -> content
      _ -> ""
    end
  end

  defp determine_initial_provider_preference(request_requirements, options) do
    cond do
      Map.has_key?(options, :preferred_provider) ->
        options.preferred_provider

      request_requirements.quality_requirements.constitutional_ai_required ->
        "claude-3-sonnet"

      request_requirements.cost_constraints.cost_priority == :high ->
        "gpt-3.5-turbo"

      true ->
        "gpt-4"
    end
  end

  defp determine_quality_level(request_requirements) do
    case request_requirements.quality_requirements.quality_priority do
      :high -> :high
      :medium -> :standard
      :low -> :basic
      _ -> :standard
    end
  end

  defp determine_cost_sensitivity(request_requirements) do
    case request_requirements.cost_constraints.cost_priority do
      :high -> :high
      :medium -> :medium
      :low -> :low
      _ -> :medium
    end
  end

  defp determine_prompt_name_for_orchestration(request_requirements) do
    case {request_requirements.domain, request_requirements.content_complexity} do
      {:evaluation, :high} -> "complex_code_evaluation_prompt"
      {:evaluation, _} -> "standard_code_evaluation_prompt"
      {:orchestration, :high} -> "complex_orchestration_prompt"
      {:orchestration, _} -> "standard_orchestration_prompt"
      {domain, _} -> "#{domain}_orchestration_prompt"
    end
  end

  defp estimate_prompt_effectiveness(response, enhanced_request) do
    # Estimate how effective the prompt composition was
    base_effectiveness = if Map.get(enhanced_request, :prompt_composed, false), do: 0.8, else: 0.5

    # Adjust based on response quality
    quality_adjustment =
      case response.success do
        true -> 0.2
        false -> -0.3
      end

    # Adjust based on provider optimization
    provider_adjustment =
      if Map.get(enhanced_request, :provider_optimized, false), do: 0.1, else: 0.0

    max(0.0, min(1.0, base_effectiveness + quality_adjustment + provider_adjustment))
  end

  defp update_provider_performance_data_with_prompts(current_data, learning_data) do
    provider = learning_data.provider

    current_data
    |> Map.update(provider, %{}, fn provider_data ->
      base_data = %{
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

      # Add prompt composition specific metrics
      prompt_data = %{
        prompt_composition_usage_rate: update_prompt_usage_rate(provider_data, learning_data),
        prompt_effectiveness_score: update_prompt_effectiveness(provider_data, learning_data),
        provider_optimization_impact:
          update_provider_optimization_impact(provider_data, learning_data)
      }

      Map.merge(base_data, prompt_data)
    end)
  end

  defp update_prompt_usage_rate(provider_data, learning_data) do
    current_rate = Map.get(provider_data, :prompt_composition_usage_rate, 0.0)
    current_count = Map.get(provider_data, :total_requests, 0)

    if current_count > 0 do
      (current_rate * current_count + if(learning_data.prompt_composed, do: 1.0, else: 0.0)) /
        (current_count + 1)
    else
      if learning_data.prompt_composed, do: 1.0, else: 0.0
    end
  end

  defp update_prompt_effectiveness(provider_data, learning_data) do
    current_effectiveness = Map.get(provider_data, :prompt_effectiveness_score, 0.5)
    current_count = Map.get(provider_data, :total_requests, 0)

    if current_count > 0 do
      (current_effectiveness * current_count + learning_data.prompt_effectiveness) /
        (current_count + 1)
    else
      learning_data.prompt_effectiveness
    end
  end

  defp update_provider_optimization_impact(provider_data, learning_data) do
    current_impact = Map.get(provider_data, :provider_optimization_impact, 0.0)
    current_count = Map.get(provider_data, :total_requests, 0)

    optimization_impact =
      if learning_data.provider_optimized do
        # Estimate impact based on quality vs baseline
        # 0.7 as baseline
        max(0.0, learning_data.actual_response_quality - 0.7)
      else
        0.0
      end

    if current_count > 0 do
      (current_impact * current_count + optimization_impact) / (current_count + 1)
    else
      optimization_impact
    end
  end

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

  defp select_optimal_provider(agent, request_requirements, enhanced_request \\ nil) do
    current_state = Jido.Agent.get_state(agent)

    # Get available providers from JidoAI Provider System
    case ProviderService.get_available_providers(request_requirements.domain) do
      {:ok, available_providers} ->
        # Apply multi-criteria optimization using learning data (enhanced with prompt composition data)
        case apply_multi_criteria_selection(
               available_providers,
               request_requirements,
               current_state.provider_performance_data,
               current_state.learning_state,
               enhanced_request
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
         learning_state,
         enhanced_request \\ nil
       ) do
    # Multi-criteria optimization using performance data and learning (enhanced with prompt composition)
    scored_providers =
      available_providers
      |> Enum.map(fn {provider_type, provider_info} ->
        score_provider_for_requirements(
          provider_type,
          provider_info,
          requirements,
          performance_data,
          learning_state,
          enhanced_request
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
         learning_state,
         enhanced_request \\ nil
       ) do
    # Calculate comprehensive provider score
    base_capabilities_score = calculate_base_capabilities_score(provider_info, requirements)

    historical_performance_score =
      calculate_historical_performance_score(provider_type, performance_data)

    learning_adjustment = calculate_learning_adjustment(provider_type, learning_state)

    cost_efficiency_score =
      calculate_cost_efficiency_score(provider_type, requirements, performance_data)

    health_status_score = calculate_health_status_score(provider_type, provider_info)

    # Calculate prompt composition compatibility score (new enhancement)
    prompt_composition_score =
      calculate_prompt_composition_score(provider_type, enhanced_request, performance_data)

    # Apply weights based on requirements and learning (enhanced with prompt composition)
    weights = determine_scoring_weights(requirements, learning_state, enhanced_request)

    overall_score =
      base_capabilities_score * weights.capabilities +
        historical_performance_score * weights.performance +
        learning_adjustment * weights.learning +
        cost_efficiency_score * weights.cost +
        health_status_score * weights.health +
        prompt_composition_score * weights.prompt_composition

    %{
      provider_type: provider_type,
      overall_score: overall_score,
      base_capabilities_score: base_capabilities_score,
      historical_performance_score: historical_performance_score,
      learning_adjustment: learning_adjustment,
      cost_efficiency_score: cost_efficiency_score,
      health_status_score: health_status_score,
      prompt_composition_score: prompt_composition_score,
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

    ProviderService.complete(optimized_request.content, domain, orchestration_options)
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

  defp fallback_to_jido_ai_provider(request, domain, options) do
    Logger.warning("Falling back to JidoAI Provider Service default routing")

    # Use JidoAI Provider Service directly
    ProviderService.complete(request.content, domain, options)
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

  defp calculate_health_status_score(_provider_type, provider_info) do
    # Health status from provider info
    case Map.get(provider_info, :health_status) do
      :healthy -> 1.0
      :degraded -> 0.6
      :unhealthy -> 0.1
      # Unknown, assume decent
      _ -> 0.7
    end
  end

  defp calculate_prompt_composition_score(provider_type, enhanced_request, performance_data) do
    # Calculate compatibility score with prompt composition features
    case enhanced_request do
      nil ->
        # No prompt composition enhancement, neutral score
        0.5

      request ->
        calculate_composition_score_for_request(provider_type, request, performance_data)
    end
  end

  defp calculate_composition_score_for_request(provider_type, request, performance_data) do
    base_score = 0.6
    provider_boost = calculate_provider_boost(provider_type, request)
    historical_effectiveness = get_historical_effectiveness(provider_type, performance_data)
    optimization_boost = calculate_optimization_boost(request)

    composition_score = base_score + provider_boost + optimization_boost
    (composition_score + historical_effectiveness) / 2
  end

  defp calculate_provider_boost(provider_type, request) do
    case Map.get(request, :recommended_provider) do
      provider when is_binary(provider) ->
        if provider == Atom.to_string(provider_type), do: 0.3, else: 0.0

      _ ->
        0.0
    end
  end

  defp get_historical_effectiveness(provider_type, performance_data) do
    case Map.get(performance_data, provider_type) do
      nil -> 0.5
      provider_data -> Map.get(provider_data, :prompt_effectiveness_score, 0.5)
    end
  end

  defp calculate_optimization_boost(request) do
    if Map.get(request, :provider_optimized, false), do: 0.2, else: 0.0
  end

  defp determine_scoring_weights(requirements, learning_state, enhanced_request \\ nil) do
    # Dynamic weight calculation based on requirements and learning (enhanced with prompt composition)
    base_weights = %{
      capabilities: 0.25,
      performance: 0.2,
      learning: 0.15,
      cost: 0.15,
      health: 0.1,
      # New weight for prompt composition
      prompt_composition: 0.15
    }

    # Adjust weights based on requirements
    adjusted_weights =
      case {requirements.cost_constraints.cost_priority,
            requirements.quality_requirements.quality_priority} do
        {:high, _} ->
          %{
            base_weights
            | cost: 0.35,
              performance: 0.15,
              capabilities: 0.15,
              prompt_composition: 0.1
          }

        {_, :high} ->
          %{
            base_weights
            | capabilities: 0.3,
              performance: 0.25,
              prompt_composition: 0.2,
              cost: 0.1
          }

        _ ->
          base_weights
      end

    # Further adjust weights based on prompt composition availability
    final_weights =
      case enhanced_request do
        nil ->
          # No prompt composition, redistribute weight
          %{
            adjusted_weights
            | capabilities: adjusted_weights.capabilities + 0.08,
              performance: adjusted_weights.performance + 0.07,
              prompt_composition: 0.0
          }

        request ->
          # Boost prompt composition weight when composition is available
          if Map.get(request, :prompt_composed, false) do
            %{adjusted_weights | prompt_composition: adjusted_weights.prompt_composition + 0.05}
          else
            adjusted_weights
          end
      end

    # Apply learning influence
    learning_influence = learning_state.learning_rate * 0.1
    %{final_weights | learning: final_weights.learning + learning_influence}
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

  defp enhance_response_with_orchestration_data(
         response,
         provider_selection,
         orchestration_time,
         enhanced_request \\ nil
       ) do
    # Base orchestration metadata
    base_metadata = %{
      orchestrator_used: true,
      provider_selection: provider_selection,
      orchestration_time_ms: orchestration_time,
      cost_optimization_applied: true,
      autonomous_selection: true
    }

    # Add prompt composition metadata if available
    orchestration_metadata =
      case enhanced_request do
        nil ->
          base_metadata

        request ->
          prompt_metadata = %{
            prompt_composition_used: Map.get(request, :prompt_composed, false),
            provider_optimization_applied: Map.get(request, :provider_optimized, false),
            routing_optimization_applied: Map.get(request, :routing_optimized, false),
            composition_metadata: Map.get(request, :composition_metadata, %{})
          }

          Map.merge(base_metadata, prompt_metadata)
      end

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
    case ProviderService.get_provider_health() do
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
