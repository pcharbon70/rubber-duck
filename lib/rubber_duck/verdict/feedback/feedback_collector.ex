defmodule RubberDuck.Verdict.Feedback.FeedbackCollector do
  @moduledoc """
  Multi-source feedback aggregation system for the Verdict framework.

  Collects and aggregates feedback from multiple sources including explicit user
  input (ratings, corrections), implicit behavioral patterns (acceptance rates,
  retry frequency), and system performance metrics to fuel continuous learning.
  """

  require Logger

  alias RubberDuck.Verdict.Feedback.{
    ExplicitFeedbackProcessor,
    FeedbackValidator,
    ImplicitFeedbackAnalyzer
  }

  @feedback_types [
    :explicit_rating,
    :explicit_correction,
    :explicit_comment,
    :implicit_acceptance,
    :implicit_rejection,
    :implicit_retry,
    :implicit_edit,
    :system_performance,
    :judge_agreement,
    :cost_efficiency
  ]

  @confidence_thresholds %{
    explicit_rating: 0.9,
    explicit_correction: 0.95,
    explicit_comment: 0.8,
    implicit_acceptance: 0.7,
    implicit_rejection: 0.75,
    implicit_retry: 0.6,
    implicit_edit: 0.65,
    system_performance: 0.8,
    judge_agreement: 0.85,
    cost_efficiency: 0.7
  }

  @doc """
  Collect feedback from multiple sources for a given evaluation.

  ## Parameters
  - `evaluation_id` - The evaluation to collect feedback for
  - `feedback_sources` - Map of source_type -> feedback_data
  - `options` - Collection options and configuration

  ## Returns
  - `{:ok, aggregated_feedback}` - Successfully collected and aggregated feedback
  - `{:error, reason}` - Collection failed
  """
  def collect_feedback(evaluation_id, feedback_sources, options \\ []) do
    Logger.info("Collecting feedback for evaluation #{evaluation_id}")

    start_time = System.monotonic_time(:millisecond)

    case validate_feedback_sources(feedback_sources) do
      {:ok, validated_sources} ->
        case process_feedback_sources(evaluation_id, validated_sources, options) do
          {:ok, processed_feedback} ->
            aggregated_feedback = aggregate_feedback(processed_feedback, options)
            end_time = System.monotonic_time(:millisecond)

            Logger.info("Feedback collection completed in #{end_time - start_time}ms")
            {:ok, aggregated_feedback}

          {:error, reason} ->
            Logger.error("Feedback processing failed: #{reason}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Feedback validation failed: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Collect real-time feedback during active evaluation sessions.

  ## Parameters
  - `session_id` - Active evaluation session identifier
  - `feedback_data` - Real-time feedback information
  - `options` - Collection options

  ## Returns
  - `{:ok, processed_feedback}` - Real-time feedback processed
  - `{:error, reason}` - Processing failed
  """
  def collect_realtime_feedback(session_id, feedback_data, options \\ []) do
    Logger.debug("Processing real-time feedback for session #{session_id}")

    case validate_realtime_feedback(feedback_data) do
      {:ok, validated_data} ->
        processed_feedback = %{
          session_id: session_id,
          feedback_type: determine_feedback_type(validated_data),
          confidence: calculate_feedback_confidence(validated_data),
          processed_at: DateTime.utc_now(),
          learning_value: assess_learning_value(validated_data),
          urgency: determine_feedback_urgency(validated_data),
          source_metadata: extract_source_metadata(validated_data)
        }

        {:ok, processed_feedback}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Aggregate historical feedback for pattern analysis.

  ## Parameters
  - `time_window` - Time period to analyze (e.g., {30, :days})
  - `filters` - Optional filters for feedback selection
  - `options` - Aggregation options

  ## Returns
  - `{:ok, aggregated_patterns}` - Historical feedback patterns
  - `{:error, reason}` - Aggregation failed
  """
  def aggregate_historical_feedback(time_window, filters \\ %{}, options \\ []) do
    {amount, unit} = time_window
    cutoff_time = DateTime.add(DateTime.utc_now(), -amount, unit)

    Logger.info("Aggregating historical feedback from #{cutoff_time}")

    case fetch_historical_feedback(cutoff_time, filters) do
      {:ok, feedback_data} ->
        patterns = analyze_feedback_patterns(feedback_data, options)
        trends = calculate_feedback_trends(feedback_data, time_window)
        insights = extract_insights_from_patterns(patterns, trends)

        aggregated_result = %{
          time_window: time_window,
          total_feedback_count: length(feedback_data),
          patterns: patterns,
          trends: trends,
          insights: insights,
          aggregation_metadata: %{
            aggregated_at: DateTime.utc_now(),
            cutoff_time: cutoff_time,
            filters_applied: filters
          }
        }

        {:ok, aggregated_result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get feedback collection statistics and health metrics.
  """
  def get_collection_stats(time_window \\ {24, :hour}) do
    {amount, unit} = time_window
    since_time = DateTime.add(DateTime.utc_now(), -amount, unit)

    # Would integrate with actual feedback storage
    %{
      total_feedback_collected: get_feedback_count_since(since_time),
      feedback_by_type: get_feedback_distribution_by_type(since_time),
      feedback_by_source: get_feedback_distribution_by_source(since_time),
      average_confidence: calculate_average_confidence(since_time),
      learning_value_distribution: get_learning_value_distribution(since_time),
      processing_performance: get_processing_performance_stats(since_time),
      collection_health: %{
        success_rate: calculate_collection_success_rate(since_time),
        error_rate: calculate_collection_error_rate(since_time),
        latency_p95: calculate_collection_latency_p95(since_time)
      }
    }
  end

  ## Private Helper Functions

  defp validate_feedback_sources(feedback_sources) do
    validation_results = Enum.map(feedback_sources, &validate_single_source/1)
    process_validation_results(validation_results)
  end

  defp validate_single_source({source_type, data}) do
    with :ok <- validate_source_type(source_type),
         {:ok, validated_data} <- FeedbackValidator.validate_feedback_data(data, source_type) do
      {:ok, {source_type, validated_data}}
    else
      {:error, reason} -> {:error, "#{source_type}: #{reason}"}
    end
  end

  defp process_validation_results(validation_results) do
    errors = Enum.filter(validation_results, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      validated_sources = Enum.map(validation_results, fn {:ok, source} -> source end)
      {:ok, validated_sources}
    else
      error_messages = Enum.map(errors, fn {:error, msg} -> msg end)
      {:error, "Validation errors: #{Enum.join(error_messages, "; ")}"}
    end
  end

  defp validate_source_type(source_type) when source_type in @feedback_types, do: :ok
  defp validate_source_type(source_type), do: {:error, "Unknown source type: #{source_type}"}

  defp process_feedback_sources(evaluation_id, validated_sources, options) do
    processing_results =
      Enum.map(validated_sources, fn {source_type, data} ->
        case source_type do
          type when type in [:explicit_rating, :explicit_correction, :explicit_comment] ->
            ExplicitFeedbackProcessor.process_feedback(evaluation_id, type, data, options)

          type
          when type in [
                 :implicit_acceptance,
                 :implicit_rejection,
                 :implicit_retry,
                 :implicit_edit
               ] ->
            ImplicitFeedbackAnalyzer.analyze_behavior(evaluation_id, type, data, options)

          type when type in [:system_performance, :judge_agreement, :cost_efficiency] ->
            process_system_feedback(evaluation_id, type, data, options)
        end
      end)

    errors = Enum.filter(processing_results, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      processed_feedback = Enum.map(processing_results, fn {:ok, result} -> result end)
      {:ok, processed_feedback}
    else
      error_reasons = Enum.map(errors, fn {:error, reason} -> reason end)
      {:error, "Processing errors: #{Enum.join(error_reasons, "; ")}"}
    end
  end

  defp process_system_feedback(evaluation_id, feedback_type, data, _options) do
    processed_feedback = %{
      evaluation_id: evaluation_id,
      feedback_type: feedback_type,
      confidence: Map.get(@confidence_thresholds, feedback_type, 0.7),
      learning_value: calculate_system_learning_value(feedback_type, data),
      processed_at: DateTime.utc_now(),
      system_data: data,
      processing_metadata: %{
        processor: :system_feedback_processor,
        version: "1.0.0"
      }
    }

    {:ok, processed_feedback}
  end

  defp aggregate_feedback(processed_feedback, options) do
    confidence_threshold = Keyword.get(options, :min_confidence, 0.6)

    high_confidence_feedback =
      Enum.filter(processed_feedback, fn feedback ->
        feedback.confidence >= confidence_threshold
      end)

    feedback_by_type = Enum.group_by(high_confidence_feedback, & &1.feedback_type)

    aggregated_result = %{
      evaluation_id: get_evaluation_id_from_feedback(processed_feedback),
      total_feedback_count: length(processed_feedback),
      high_confidence_count: length(high_confidence_feedback),
      feedback_distribution: calculate_distribution(feedback_by_type),
      overall_confidence: calculate_overall_confidence(high_confidence_feedback),
      learning_value: calculate_aggregated_learning_value(high_confidence_feedback),
      consensus_level: calculate_feedback_consensus(high_confidence_feedback),
      actionable_insights: extract_actionable_insights(high_confidence_feedback),
      aggregation_metadata: %{
        aggregated_at: DateTime.utc_now(),
        confidence_threshold: confidence_threshold,
        processing_summary: generate_processing_summary(processed_feedback)
      }
    }

    aggregated_result
  end

  # Calculation helper functions

  defp calculate_system_learning_value(feedback_type, data) do
    base_value =
      case feedback_type do
        :system_performance -> 0.8
        :judge_agreement -> 0.9
        :cost_efficiency -> 0.7
      end

    # Adjust based on data quality and relevance
    adjustment = calculate_data_quality_adjustment(data)
    min(1.0, base_value + adjustment)
  end

  defp calculate_data_quality_adjustment(data) when is_map(data) do
    # Rough completeness metric
    completeness = map_size(data) / 10.0
    min(0.2, completeness * 0.1)
  end

  defp calculate_data_quality_adjustment(_data), do: 0.0

  defp calculate_distribution(feedback_by_type) do
    Enum.reduce(feedback_by_type, %{}, fn {type, feedback_list}, acc ->
      Map.put(acc, type, length(feedback_list))
    end)
  end

  defp calculate_overall_confidence(feedback_list) do
    if Enum.empty?(feedback_list) do
      0.0
    else
      confidences = Enum.map(feedback_list, & &1.confidence)
      Enum.sum(confidences) / length(confidences)
    end
  end

  defp calculate_aggregated_learning_value(feedback_list) do
    if Enum.empty?(feedback_list) do
      0.0
    else
      learning_values = Enum.map(feedback_list, & &1.learning_value)
      Enum.sum(learning_values) / length(learning_values)
    end
  end

  defp calculate_feedback_consensus(feedback_list) do
    # Simple consensus calculation based on agreement
    if length(feedback_list) <= 1 do
      1.0
    else
      # Would implement more sophisticated consensus calculation
      0.8
    end
  end

  defp extract_actionable_insights(feedback_list) do
    # Extract high-value insights for learning engines
    high_learning_value =
      Enum.filter(feedback_list, fn feedback ->
        feedback.learning_value > 0.8
      end)

    insights =
      Enum.map(high_learning_value, fn feedback ->
        %{
          type: feedback.feedback_type,
          confidence: feedback.confidence,
          learning_value: feedback.learning_value,
          key_data: extract_key_feedback_data(feedback),
          recommended_action: suggest_learning_action(feedback)
        }
      end)

    insights
  end

  defp extract_key_feedback_data(feedback) do
    case feedback.feedback_type do
      :explicit_correction ->
        Map.take(feedback, [:correction_details, :user_explanation])

      :implicit_rejection ->
        Map.take(feedback, [:rejection_reason, :alternative_chosen])

      _ ->
        Map.take(feedback, [:primary_data])
    end
  end

  defp suggest_learning_action(feedback) do
    case feedback.feedback_type do
      :explicit_correction -> :update_evaluation_criteria
      :explicit_rating when feedback.confidence > 0.9 -> :reinforce_current_approach
      :implicit_rejection -> :investigate_judge_selection
      :judge_agreement when feedback.confidence < 0.6 -> :improve_consensus_mechanism
      _ -> :general_pattern_analysis
    end
  end

  defp generate_processing_summary(processed_feedback) do
    by_type = Enum.group_by(processed_feedback, & &1.feedback_type)

    %{
      types_processed: Map.keys(by_type),
      processing_distribution:
        Enum.map(by_type, fn {type, list} -> {type, length(list)} end) |> Map.new(),
      average_confidence_by_type: calculate_confidence_by_type(by_type),
      total_learning_value: Enum.sum(Enum.map(processed_feedback, & &1.learning_value))
    }
  end

  defp calculate_confidence_by_type(feedback_by_type) do
    Enum.reduce(feedback_by_type, %{}, fn {type, feedback_list}, acc ->
      avg_confidence = calculate_overall_confidence(feedback_list)
      Map.put(acc, type, avg_confidence)
    end)
  end

  # Utility functions for feedback retrieval and analysis

  defp get_evaluation_id_from_feedback([]), do: nil
  defp get_evaluation_id_from_feedback([first_feedback | _]), do: first_feedback.evaluation_id

  defp validate_realtime_feedback(feedback_data) do
    required_fields = [:feedback_type, :data]

    missing_fields =
      Enum.filter(required_fields, fn field ->
        not Map.has_key?(feedback_data, field)
      end)

    if Enum.empty?(missing_fields) do
      {:ok, feedback_data}
    else
      {:error, "Missing required fields: #{Enum.join(missing_fields, ", ")}"}
    end
  end

  defp determine_feedback_type(feedback_data) do
    Map.get(feedback_data, :feedback_type, :unknown)
  end

  defp calculate_feedback_confidence(feedback_data) do
    feedback_type = determine_feedback_type(feedback_data)
    base_confidence = Map.get(@confidence_thresholds, feedback_type, 0.5)

    # Adjust confidence based on data quality
    quality_adjustment = assess_feedback_quality(feedback_data)
    min(1.0, base_confidence + quality_adjustment)
  end

  defp assess_feedback_quality(feedback_data) do
    # Simple quality assessment - would be more sophisticated in production
    data_completeness =
      if Map.has_key?(feedback_data, :data) and not is_nil(feedback_data.data) do
        0.1
      else
        -0.1
      end

    user_context =
      if Map.has_key?(feedback_data, :user_id) do
        0.05
      else
        0.0
      end

    data_completeness + user_context
  end

  defp assess_learning_value(feedback_data) do
    base_value =
      case determine_feedback_type(feedback_data) do
        :explicit_correction -> 0.95
        :explicit_rating -> 0.8
        :implicit_rejection -> 0.7
        :judge_agreement -> 0.85
        _ -> 0.6
      end

    # Adjust based on feedback richness
    richness_bonus = calculate_feedback_richness(feedback_data)
    min(1.0, base_value + richness_bonus)
  end

  defp calculate_feedback_richness(feedback_data) do
    # More detailed feedback has higher learning value
    detail_keys = [:explanation, :correction_details, :context, :reasoning]
    present_details = Enum.count(detail_keys, fn key -> Map.has_key?(feedback_data, key) end)

    # Up to 0.2 bonus for complete detailed feedback
    present_details * 0.05
  end

  defp determine_feedback_urgency(feedback_data) do
    case determine_feedback_type(feedback_data) do
      :explicit_correction -> :high
      :implicit_rejection -> :medium
      :system_performance -> :low
      _ -> :normal
    end
  end

  defp extract_source_metadata(feedback_data) do
    %{
      timestamp: DateTime.utc_now(),
      source_system: Map.get(feedback_data, :source_system, :unknown),
      user_context: Map.get(feedback_data, :user_context, %{}),
      session_context: Map.get(feedback_data, :session_context, %{})
    }
  end

  # Stub implementations for integration with storage systems

  defp fetch_historical_feedback(_cutoff_time, _filters) do
    # Would integrate with Ash resources for feedback retrieval
    {:ok, []}
  end

  defp analyze_feedback_patterns(_feedback_data, _options) do
    # Would implement sophisticated pattern analysis
    %{
      common_patterns: [],
      emerging_trends: [],
      outlier_feedback: []
    }
  end

  defp calculate_feedback_trends(_feedback_data, _time_window) do
    %{
      volume_trend: :stable,
      confidence_trend: :improving,
      learning_value_trend: :stable
    }
  end

  defp extract_insights_from_patterns(patterns, trends) do
    # Extract actionable insights from identified patterns and trends
    pattern_insights = extract_pattern_insights(patterns)
    trend_insights = extract_trend_insights(trends)

    pattern_insights ++ trend_insights
  end

  defp extract_pattern_insights(patterns) do
    common_patterns = Map.get(patterns, :common_patterns, [])

    Enum.map(common_patterns, fn pattern ->
      %{
        type: :pattern_insight,
        pattern: pattern,
        recommended_action: :analyze_pattern_further,
        confidence: 0.7
      }
    end)
  end

  defp extract_trend_insights(trends) do
    trend_insights = []

    trend_insights =
      if trends.confidence_trend == :improving do
        [
          %{
            type: :trend_insight,
            insight: :confidence_improving,
            action: :maintain_current_approach
          }
          | trend_insights
        ]
      else
        trend_insights
      end

    trend_insights =
      if trends.volume_trend == :increasing do
        [
          %{type: :trend_insight, insight: :volume_increasing, action: :scale_processing_capacity}
          | trend_insights
        ]
      else
        trend_insights
      end

    trend_insights
  end

  defp get_feedback_count_since(_since_time), do: 42

  defp get_feedback_distribution_by_type(_since_time),
    do: %{explicit_rating: 20, implicit_acceptance: 15, judge_agreement: 7}

  defp get_feedback_distribution_by_source(_since_time),
    do: %{user_interface: 25, api: 12, system_automated: 5}

  defp calculate_average_confidence(_since_time), do: 0.82
  defp get_learning_value_distribution(_since_time), do: %{high: 15, medium: 20, low: 7}

  defp get_processing_performance_stats(_since_time),
    do: %{avg_processing_time_ms: 45, success_rate: 0.97}

  defp calculate_collection_success_rate(_since_time), do: 0.96
  defp calculate_collection_error_rate(_since_time), do: 0.04
  defp calculate_collection_latency_p95(_since_time), do: 120
end
