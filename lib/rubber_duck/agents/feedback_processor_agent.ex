defmodule RubberDuck.Agents.FeedbackProcessorAgent do
  @moduledoc """
  Intelligent feedback analysis and processing agent for the continuous learning system.

  Analyzes collected feedback, categorizes it by type and urgency, extracts actionable
  insights, and routes feedback to appropriate learning engines for system improvement.
  """

  use Jido.Agent, name: "FeedbackProcessor"

  require Logger

  alias RubberDuck.Verdict.Feedback.{FeedbackCollector, FeedbackRouter, FeedbackValidator}

  @processing_priorities %{
    critical: 1,
    high: 2,
    medium: 3,
    low: 4,
    background: 5
  }

  @learning_categories [
    :judge_selection_optimization,
    :evaluation_criteria_adjustment,
    :bias_pattern_detection,
    :cost_efficiency_improvement,
    :quality_enhancement,
    :coordination_optimization
  ]

  @impl true
  def init(opts \\ []) do
    state = %{
      processing_queue: [],
      active_processing: %{},
      learning_models: %{},
      processing_stats: %{
        total_processed: 0,
        processing_time_avg: 0.0,
        success_rate: 1.0,
        learning_actions_generated: 0
      },
      configuration: %{
        max_concurrent_processing: Keyword.get(opts, :max_concurrent, 5),
        processing_timeout_ms: Keyword.get(opts, :timeout_ms, 30_000),
        learning_threshold: Keyword.get(opts, :learning_threshold, 0.7),
        batch_size: Keyword.get(opts, :batch_size, 10)
      }
    }

    {:ok, state}
  end

  @doc """
  Process feedback batch for learning insights extraction.

  ## Parameters
  - `agent` - The feedback processor agent instance
  - `feedback_batch` - Batch of feedback items to process
  - `processing_options` - Options for processing configuration

  ## Returns
  - `{:ok, processing_results, updated_agent}` - Processing successful
  - `{:error, reason, agent}` - Processing failed
  """
  def process_feedback_batch(agent, feedback_batch, processing_options \\ []) do
    start_time = System.monotonic_time(:millisecond)

    Logger.info("Processing feedback batch of #{length(feedback_batch)} items")

    case validate_feedback_batch(feedback_batch) do
      {:ok, validated_batch} ->
        case execute_batch_processing(agent, validated_batch, processing_options) do
          {:ok, results, updated_agent} ->
            processing_time = System.monotonic_time(:millisecond) - start_time
            final_agent = update_processing_stats(updated_agent, results, processing_time)

            Logger.info("Feedback batch processed in #{processing_time}ms")
            {:ok, results, final_agent}

          {:error, reason} ->
            Logger.error("Feedback batch processing failed: #{reason}")
            {:error, reason, agent}
        end

      {:error, reason} ->
        Logger.error("Feedback batch validation failed: #{reason}")
        {:error, reason, agent}
    end
  end

  @doc """
  Analyze feedback for specific learning opportunities.

  ## Parameters
  - `agent` - The feedback processor agent instance
  - `feedback_data` - Individual feedback item
  - `analysis_focus` - Specific learning aspect to focus on

  ## Returns
  - `{:ok, learning_insights, updated_agent}` - Analysis successful
  - `{:error, reason, agent}` - Analysis failed
  """
  def analyze_learning_opportunities(agent, feedback_data, analysis_focus \\ :comprehensive) do
    Logger.debug("Analyzing learning opportunities with focus: #{analysis_focus}")

    case categorize_feedback_for_learning(feedback_data, analysis_focus) do
      {:ok, categorized_feedback} ->
        learning_insights =
          extract_learning_insights(
            categorized_feedback,
            analysis_focus,
            agent.state.learning_models
          )

        updated_models = update_learning_models(agent.state.learning_models, learning_insights)
        updated_agent = %{agent | state: %{agent.state | learning_models: updated_models}}

        {:ok, learning_insights, updated_agent}

      {:error, reason} ->
        {:error, reason, agent}
    end
  end

  @doc """
  Route processed feedback to appropriate learning engines.

  ## Parameters
  - `agent` - The feedback processor agent instance
  - `processed_feedback` - Feedback items ready for routing
  - `routing_options` - Options for routing configuration

  ## Returns
  - `{:ok, routing_results, updated_agent}` - Routing successful
  - `{:error, reason, agent}` - Routing failed
  """
  def route_feedback_to_learners(agent, processed_feedback, routing_options \\ []) do
    Logger.info("Routing #{length(processed_feedback)} feedback items to learning engines")

    routing_plan = create_routing_plan(processed_feedback, routing_options)

    case execute_routing_plan(agent, routing_plan) do
      {:ok, routing_results} ->
        updated_agent = record_routing_success(agent, routing_results)
        {:ok, routing_results, updated_agent}

      {:error, reason} ->
        updated_agent = record_routing_failure(agent, reason)
        {:error, reason, updated_agent}
    end
  end

  @doc """
  Get feedback processing statistics and performance metrics.
  """
  def get_processing_stats(agent) do
    stats = agent.state.processing_stats

    %{
      total_processed: stats.total_processed,
      average_processing_time_ms: stats.processing_time_avg,
      success_rate: stats.success_rate,
      learning_actions_generated: stats.learning_actions_generated,
      current_queue_size: length(agent.state.processing_queue),
      active_processing_count: map_size(agent.state.active_processing),
      learning_model_count: map_size(agent.state.learning_models)
    }
  end

  @doc """
  Configure feedback processing parameters.
  """
  def configure_processing(agent, new_config) do
    merged_config = Map.merge(agent.state.configuration, new_config)
    updated_agent = put_in(agent.state.configuration, merged_config)

    Logger.info("Updated feedback processing configuration")
    {:ok, updated_agent}
  end

  ## Private Helper Functions

  defp validate_feedback_batch(feedback_batch) do
    case validate_batch_structure(feedback_batch) do
      :ok ->
        process_batch_validation(feedback_batch)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_batch_structure(feedback_batch) do
    if is_list(feedback_batch) and length(feedback_batch) > 0 do
      :ok
    else
      {:error, "Invalid feedback batch: must be non-empty list"}
    end
  end

  defp process_batch_validation(feedback_batch) do
    validation_results = Enum.map(feedback_batch, &FeedbackValidator.validate_feedback_item/1)
    errors = Enum.filter(validation_results, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      validated_items = Enum.map(validation_results, fn {:ok, item} -> item end)
      {:ok, validated_items}
    else
      {:error, "Batch validation failed: #{length(errors)} invalid items"}
    end
  end

  defp execute_batch_processing(agent, validated_batch, options) do
    batch_size = agent.state.configuration.batch_size
    processing_batches = Enum.chunk_every(validated_batch, batch_size)

    processing_results =
      Enum.map(processing_batches, fn batch ->
        process_feedback_chunk(batch, options)
      end)

    errors = Enum.filter(processing_results, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      all_results = Enum.flat_map(processing_results, fn {:ok, results} -> results end)
      {:ok, all_results, agent}
    else
      {:error, "Batch processing failed: #{length(errors)} chunks failed"}
    end
  end

  defp process_feedback_chunk(feedback_chunk, options) do
    processed_items =
      Enum.map(feedback_chunk, fn feedback_item ->
        %{
          original_feedback: feedback_item,
          processing_timestamp: DateTime.utc_now(),
          learning_category: determine_learning_category(feedback_item),
          processing_priority: calculate_processing_priority(feedback_item),
          extracted_insights: extract_feedback_insights(feedback_item),
          learning_actions: generate_learning_actions(feedback_item),
          routing_targets: determine_routing_targets(feedback_item),
          processing_metadata: %{
            processor_version: "1.0.0",
            processing_options: options,
            chunk_size: length(feedback_chunk)
          }
        }
      end)

    {:ok, processed_items}
  end

  defp categorize_feedback_for_learning(feedback_data, analysis_focus) do
    category =
      case analysis_focus do
        :judge_selection -> categorize_for_judge_selection(feedback_data)
        :evaluation_quality -> categorize_for_quality_improvement(feedback_data)
        :cost_optimization -> categorize_for_cost_optimization(feedback_data)
        :bias_detection -> categorize_for_bias_analysis(feedback_data)
        :comprehensive -> categorize_comprehensively(feedback_data)
      end

    {:ok,
     %{
       feedback_data: feedback_data,
       learning_category: category,
       analysis_focus: analysis_focus,
       categorization_confidence: calculate_categorization_confidence(category, feedback_data)
     }}
  end

  defp extract_learning_insights(categorized_feedback, analysis_focus, learning_models) do
    base_insights = extract_base_insights(categorized_feedback)

    focused_insights =
      case analysis_focus do
        :judge_selection ->
          extract_judge_selection_insights(categorized_feedback, learning_models)

        :evaluation_quality ->
          extract_quality_insights(categorized_feedback, learning_models)

        :cost_optimization ->
          extract_cost_insights(categorized_feedback, learning_models)

        :comprehensive ->
          extract_comprehensive_insights(categorized_feedback, learning_models)

        _ ->
          base_insights
      end

    %{
      base_insights: base_insights,
      focused_insights: focused_insights,
      learning_confidence: calculate_insight_confidence(focused_insights),
      recommended_actions: generate_insight_actions(focused_insights),
      insight_metadata: %{
        extracted_at: DateTime.utc_now(),
        analysis_focus: analysis_focus,
        model_versions: get_model_versions(learning_models)
      }
    }
  end

  defp create_routing_plan(processed_feedback, options) do
    routing_strategy = Keyword.get(options, :routing_strategy, :balanced)

    routing_groups =
      Enum.group_by(processed_feedback, fn feedback ->
        primary_target = List.first(feedback.routing_targets)
        {primary_target, feedback.processing_priority}
      end)

    %{
      routing_strategy: routing_strategy,
      routing_groups: routing_groups,
      total_feedback_count: length(processed_feedback),
      routing_metadata: %{
        created_at: DateTime.utc_now(),
        options: options
      }
    }
  end

  defp execute_routing_plan(agent, routing_plan) do
    routing_results =
      Enum.map(routing_plan.routing_groups, fn {{target, priority}, feedback_list} ->
        case FeedbackRouter.route_feedback_batch(target, feedback_list, priority) do
          {:ok, result} ->
            {:ok, {target, result}}

          {:error, reason} ->
            Logger.warning("Routing failed for #{target}: #{reason}")
            {:error, {target, reason}}
        end
      end)

    successful_routes = Enum.filter(routing_results, &match?({:ok, _}, &1))
    failed_routes = Enum.filter(routing_results, &match?({:error, _}, &1))

    if Enum.empty?(failed_routes) do
      results = Enum.map(successful_routes, fn {:ok, result} -> result end)

      {:ok,
       %{
         successful_routes: results,
         total_routed: length(successful_routes),
         routing_summary: summarize_routing_results(results)
       }}
    else
      {:error, "Routing failed for #{length(failed_routes)} targets"}
    end
  end

  # Learning categorization helpers

  defp determine_learning_category(feedback_item) do
    feedback_type = Map.get(feedback_item, :feedback_type)

    case feedback_type do
      :explicit_correction -> :evaluation_criteria_adjustment
      :judge_agreement -> :judge_selection_optimization
      :cost_efficiency -> :cost_optimization
      :implicit_rejection -> :quality_enhancement
      _ -> :general_improvement
    end
  end

  defp calculate_processing_priority(feedback_item) do
    urgency = Map.get(feedback_item, :urgency, :normal)
    learning_value = Map.get(feedback_item, :learning_value, 0.5)

    case {urgency, learning_value > 0.8} do
      {:high, true} -> :critical
      {:high, false} -> :high
      {:medium, true} -> :high
      {:medium, false} -> :medium
      {_, true} -> :medium
      {_, false} -> :low
    end
  end

  defp extract_feedback_insights(feedback_item) do
    # Extract actionable insights based on feedback type and content
    case Map.get(feedback_item, :feedback_type) do
      :explicit_correction ->
        extract_correction_insights(feedback_item)

      :implicit_rejection ->
        extract_rejection_insights(feedback_item)

      :judge_agreement ->
        extract_consensus_insights(feedback_item)

      _ ->
        extract_general_insights(feedback_item)
    end
  end

  defp generate_learning_actions(feedback_item) do
    insights = extract_feedback_insights(feedback_item)
    learning_category = determine_learning_category(feedback_item)

    case learning_category do
      :evaluation_criteria_adjustment ->
        ["adjust_evaluation_weights", "update_quality_thresholds", "refine_scoring_algorithms"]

      :judge_selection_optimization ->
        ["optimize_judge_routing", "update_specialization_weights", "improve_agent_selection"]

      :cost_optimization ->
        ["adjust_cost_thresholds", "optimize_agent_utilization", "improve_budget_allocation"]

      _ ->
        ["general_pattern_analysis", "update_user_preferences", "improve_system_defaults"]
    end
  end

  defp determine_routing_targets(feedback_item) do
    learning_category = determine_learning_category(feedback_item)
    priority = calculate_processing_priority(feedback_item)

    primary_targets =
      case learning_category do
        :judge_selection_optimization ->
          [:judge_selection_learner, :coordination_optimizer]

        :evaluation_criteria_adjustment ->
          [:criteria_adaptation_engine, :quality_improvement_engine]

        :cost_optimization ->
          [:cost_optimization_learner, :budget_optimization_engine]

        :bias_pattern_detection ->
          [:bias_detection_agent, :pattern_recognition_agent]

        _ ->
          [:general_learning_engine]
      end

    # Add secondary targets based on priority
    secondary_targets =
      if priority in [:critical, :high] do
        [:learning_coordinator_agent]
      else
        []
      end

    primary_targets ++ secondary_targets
  end

  # Insight extraction helpers

  defp extract_correction_insights(feedback_item) do
    %{
      correction_type: determine_correction_type(feedback_item),
      affected_criteria: identify_affected_criteria(feedback_item),
      user_reasoning: extract_user_reasoning(feedback_item),
      confidence_in_correction: assess_correction_confidence(feedback_item),
      learning_priority: :high
    }
  end

  defp extract_rejection_insights(feedback_item) do
    %{
      rejection_pattern: analyze_rejection_pattern(feedback_item),
      alternative_preferences: identify_alternative_preferences(feedback_item),
      judge_performance_impact: assess_judge_impact(feedback_item),
      system_improvement_areas: identify_improvement_areas(feedback_item),
      learning_priority: :medium
    }
  end

  defp extract_consensus_insights(feedback_item) do
    %{
      consensus_quality: assess_consensus_quality(feedback_item),
      disagreement_patterns: analyze_disagreement_patterns(feedback_item),
      coordination_effectiveness: evaluate_coordination_effectiveness(feedback_item),
      optimization_opportunities: identify_coordination_optimizations(feedback_item),
      learning_priority: :high
    }
  end

  defp extract_general_insights(feedback_item) do
    %{
      general_satisfaction: assess_general_satisfaction(feedback_item),
      usage_patterns: extract_usage_patterns(feedback_item),
      system_performance_indicators: extract_performance_indicators(feedback_item),
      learning_priority: :low
    }
  end

  # Learning model management

  defp update_learning_models(current_models, learning_insights) do
    insights = learning_insights.focused_insights

    Enum.reduce(insights, current_models, fn {category, insight_data}, models ->
      case Map.get(models, category) do
        nil ->
          Map.put(models, category, initialize_learning_model(category, insight_data))

        existing_model ->
          Map.put(models, category, update_existing_model(existing_model, insight_data))
      end
    end)
  end

  defp initialize_learning_model(category, insight_data) do
    %{
      category: category,
      created_at: DateTime.utc_now(),
      update_count: 1,
      confidence: Map.get(insight_data, :confidence, 0.5),
      pattern_data: Map.get(insight_data, :patterns, []),
      effectiveness_score: 0.5,
      last_updated: DateTime.utc_now()
    }
  end

  defp update_existing_model(existing_model, insight_data) do
    new_confidence = calculate_updated_confidence(existing_model.confidence, insight_data)
    updated_patterns = merge_pattern_data(existing_model.pattern_data, insight_data)

    %{
      existing_model
      | update_count: existing_model.update_count + 1,
        confidence: new_confidence,
        pattern_data: updated_patterns,
        last_updated: DateTime.utc_now()
    }
  end

  defp calculate_updated_confidence(current_confidence, insight_data) do
    new_evidence_weight = Map.get(insight_data, :confidence, 0.5)
    # Conservative learning rate
    learning_rate = 0.1

    # Weighted average with learning rate
    current_confidence * (1 - learning_rate) + new_evidence_weight * learning_rate
  end

  defp merge_pattern_data(existing_patterns, insight_data) do
    new_patterns = Map.get(insight_data, :patterns, [])

    # Simple merge - in production would be more sophisticated
    (existing_patterns ++ new_patterns)
    # Limit pattern storage
    |> Enum.take(100)
  end

  # Performance tracking

  defp update_processing_stats(agent, processing_results, processing_time_ms) do
    current_stats = agent.state.processing_stats

    new_total = current_stats.total_processed + length(processing_results)

    new_avg_time =
      (current_stats.processing_time_avg * current_stats.total_processed + processing_time_ms) /
        new_total

    successful_results =
      Enum.count(processing_results, fn result ->
        Map.get(result, :success, false)
      end)

    new_success_rate =
      (current_stats.success_rate * current_stats.total_processed + successful_results) /
        new_total

    learning_actions =
      Enum.sum(
        Enum.map(processing_results, fn result ->
          length(Map.get(result, :learning_actions, []))
        end)
      )

    updated_stats = %{
      total_processed: new_total,
      processing_time_avg: new_avg_time,
      success_rate: new_success_rate,
      learning_actions_generated: current_stats.learning_actions_generated + learning_actions
    }

    %{agent | state: %{agent.state | processing_stats: updated_stats}}
  end

  defp record_routing_success(agent, routing_results) do
    # Update internal metrics for successful routing
    agent
  end

  defp record_routing_failure(agent, _reason) do
    # Update internal metrics for failed routing
    agent
  end

  # Insight categorization helpers

  defp categorize_for_judge_selection(feedback_data) do
    %{
      judge_performance_feedback: extract_judge_performance_data(feedback_data),
      selection_accuracy: assess_selection_accuracy(feedback_data),
      user_judge_preferences: extract_judge_preferences(feedback_data)
    }
  end

  defp categorize_for_quality_improvement(feedback_data) do
    %{
      quality_indicators: extract_quality_indicators(feedback_data),
      accuracy_feedback: extract_accuracy_feedback(feedback_data),
      criteria_effectiveness: assess_criteria_effectiveness(feedback_data)
    }
  end

  defp categorize_for_cost_optimization(feedback_data) do
    %{
      cost_effectiveness: assess_cost_effectiveness(feedback_data),
      efficiency_patterns: extract_efficiency_patterns(feedback_data),
      budget_optimization_opportunities: identify_budget_optimizations(feedback_data)
    }
  end

  defp categorize_for_bias_analysis(feedback_data) do
    %{
      potential_bias_indicators: detect_bias_indicators(feedback_data),
      fairness_concerns: extract_fairness_concerns(feedback_data),
      demographic_patterns: analyze_demographic_patterns(feedback_data)
    }
  end

  defp categorize_comprehensively(feedback_data) do
    %{
      judge_selection: categorize_for_judge_selection(feedback_data),
      quality_improvement: categorize_for_quality_improvement(feedback_data),
      cost_optimization: categorize_for_cost_optimization(feedback_data),
      bias_analysis: categorize_for_bias_analysis(feedback_data)
    }
  end

  # Insight extraction stubs (would be implemented with actual analysis logic)

  defp extract_base_insights(_categorized_feedback), do: %{base_learning_value: 0.7}

  defp extract_judge_selection_insights(_categorized_feedback, _models),
    do: %{judge_optimization: "improve_routing"}

  defp extract_quality_insights(_categorized_feedback, _models),
    do: %{quality_improvement: "enhance_criteria"}

  defp extract_cost_insights(_categorized_feedback, _models),
    do: %{cost_optimization: "reduce_overhead"}

  defp extract_comprehensive_insights(_categorized_feedback, _models),
    do: %{comprehensive: "multi_aspect_improvement"}

  defp calculate_categorization_confidence(_category, _feedback_data), do: 0.8
  defp calculate_insight_confidence(_insights), do: 0.75
  defp generate_insight_actions(_insights), do: ["analyze_patterns", "update_models"]
  defp get_model_versions(_models), do: %{default: "1.0.0"}

  defp determine_correction_type(_feedback), do: :evaluation_criteria
  defp identify_affected_criteria(_feedback), do: [:accuracy, :completeness]
  defp extract_user_reasoning(_feedback), do: "User provided correction feedback"
  defp assess_correction_confidence(_feedback), do: 0.85

  defp analyze_rejection_pattern(_feedback), do: :quality_concerns
  defp identify_alternative_preferences(_feedback), do: []
  defp assess_judge_impact(_feedback), do: :moderate
  defp identify_improvement_areas(_feedback), do: [:evaluation_accuracy]

  defp assess_consensus_quality(_feedback), do: 0.7
  defp analyze_disagreement_patterns(_feedback), do: []
  defp evaluate_coordination_effectiveness(_feedback), do: 0.8
  defp identify_coordination_optimizations(_feedback), do: []

  defp assess_general_satisfaction(_feedback), do: 0.75
  defp extract_usage_patterns(_feedback), do: %{pattern_type: :standard_usage}
  defp extract_performance_indicators(_feedback), do: %{performance: :acceptable}

  defp extract_judge_performance_data(_feedback), do: %{performance: :good}
  defp assess_selection_accuracy(_feedback), do: 0.8
  defp extract_judge_preferences(_feedback), do: %{preferred_judges: [:code_quality]}

  defp extract_quality_indicators(_feedback), do: %{quality_level: :high}
  defp extract_accuracy_feedback(_feedback), do: %{accuracy: :good}
  defp assess_criteria_effectiveness(_feedback), do: 0.8

  defp assess_cost_effectiveness(_feedback), do: 0.75
  defp extract_efficiency_patterns(_feedback), do: %{efficiency: :optimal}
  defp identify_budget_optimizations(_feedback), do: []

  defp detect_bias_indicators(_feedback), do: []
  defp extract_fairness_concerns(_feedback), do: []
  defp analyze_demographic_patterns(_feedback), do: %{patterns: :none_detected}

  defp summarize_routing_results(results) do
    %{
      targets_reached: length(results),
      total_feedback_routed:
        Enum.sum(Enum.map(results, fn {_target, result} -> Map.get(result, :count, 0) end))
    }
  end
end
