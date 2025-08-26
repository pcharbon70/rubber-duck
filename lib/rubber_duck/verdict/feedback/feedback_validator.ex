defmodule RubberDuck.Verdict.Feedback.FeedbackValidator do
  @moduledoc """
  Comprehensive feedback validation for quality assurance and learning optimization.

  Validates feedback data quality, consistency, and learning potential to ensure
  high-quality input for the continuous learning system and prevent noise
  from degrading learning model performance.
  """

  require Logger

  @required_fields_by_type %{
    explicit_rating: [:rating, :evaluation_id],
    explicit_correction: [:correction_details, :evaluation_id],
    explicit_comment: [:comment, :evaluation_id],
    implicit_acceptance: [:acceptance_time_ms, :evaluation_id],
    implicit_rejection: [:rejection_reason, :evaluation_id],
    implicit_retry: [:retry_count, :evaluation_id],
    implicit_edit: [:edit_count, :edit_types, :evaluation_id],
    system_performance: [:performance_data, :evaluation_id],
    judge_agreement: [:agreement_data, :evaluation_id],
    cost_efficiency: [:cost_data, :evaluation_id]
  }

  @quality_thresholds %{
    min_learning_value: 0.3,
    min_confidence_score: 0.4,
    max_processing_age_hours: 72,
    min_data_completeness: 0.6
  }

  @doc """
  Validate individual feedback item for quality and learning potential.

  ## Parameters
  - `feedback_item` - Feedback item to validate

  ## Returns
  - `{:ok, validated_feedback}` - Validation successful with enhanced metadata
  - `{:error, reason}` - Validation failed with specific reason
  """
  def validate_feedback_item(feedback_item) do
    with {:ok, structured_feedback} <- validate_feedback_structure(feedback_item),
         {:ok, quality_validated} <- validate_feedback_quality(structured_feedback),
         {:ok, learning_validated} <- validate_learning_potential(quality_validated) do
      enhanced_feedback = enhance_feedback_metadata(learning_validated)
      {:ok, enhanced_feedback}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validate feedback data for a specific source type.

  ## Parameters
  - `feedback_data` - Raw feedback data
  - `source_type` - Type of feedback source

  ## Returns
  - `{:ok, validated_data}` - Validation successful
  - `{:error, reason}` - Validation failed
  """
  def validate_feedback_data(feedback_data, source_type) do
    case validate_source_specific_requirements(feedback_data, source_type) do
      :ok ->
        case validate_data_integrity(feedback_data) do
          :ok ->
            validated_data = %{
              original_data: feedback_data,
              source_type: source_type,
              validation_timestamp: DateTime.utc_now(),
              data_quality_score: calculate_data_quality_score(feedback_data),
              completeness_score: calculate_completeness_score(feedback_data),
              reliability_indicators: assess_reliability_indicators(feedback_data, source_type)
            }

            {:ok, validated_data}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Batch validate multiple feedback items with performance optimization.

  ## Parameters
  - `feedback_batch` - List of feedback items to validate
  - `validation_options` - Options for batch validation

  ## Returns
  - `{:ok, validation_results}` - Batch validation results
  - `{:error, reason}` - Batch validation failed
  """
  def validate_feedback_batch(feedback_batch, validation_options \\ []) do
    if is_list(feedback_batch) and length(feedback_batch) > 0 do
      parallel_validation = Keyword.get(validation_options, :parallel, true)

      validation_results =
        if parallel_validation do
          validate_batch_parallel(feedback_batch)
        else
          validate_batch_sequential(feedback_batch)
        end

      successful_validations = Enum.filter(validation_results, &match?({:ok, _}, &1))
      failed_validations = Enum.filter(validation_results, &match?({:error, _}, &1))

      batch_results = %{
        total_items: length(feedback_batch),
        successful_count: length(successful_validations),
        failed_count: length(failed_validations),
        success_rate: length(successful_validations) / length(feedback_batch),
        validated_items: Enum.map(successful_validations, fn {:ok, item} -> item end),
        validation_errors: Enum.map(failed_validations, fn {:error, reason} -> reason end),
        batch_quality_score: calculate_batch_quality_score(validation_results),
        validation_metadata: %{
          validated_at: DateTime.utc_now(),
          validation_method: if(parallel_validation, do: :parallel, else: :sequential),
          options: validation_options
        }
      }

      {:ok, batch_results}
    else
      {:error, "Invalid feedback batch: must be non-empty list"}
    end
  end

  ## Private Validation Functions

  defp validate_feedback_structure(feedback_item) do
    required_base_fields = [:feedback_type, :evaluation_id]

    missing_fields =
      Enum.filter(required_base_fields, fn field ->
        not Map.has_key?(feedback_item, field) or is_nil(Map.get(feedback_item, field))
      end)

    if Enum.empty?(missing_fields) do
      feedback_type = Map.get(feedback_item, :feedback_type)

      case validate_type_specific_fields(feedback_item, feedback_type) do
        :ok ->
          {:ok, Map.put(feedback_item, :structure_validated, true)}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, "Missing required fields: #{Enum.join(missing_fields, ", ")}"}
    end
  end

  defp validate_type_specific_fields(feedback_item, feedback_type) do
    required_fields = Map.get(@required_fields_by_type, feedback_type, [])

    missing_type_fields =
      Enum.filter(required_fields, fn field ->
        not Map.has_key?(feedback_item, field) or is_nil(Map.get(feedback_item, field))
      end)

    if Enum.empty?(missing_type_fields) do
      case validate_field_values(feedback_item, feedback_type) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, "Missing #{feedback_type} fields: #{Enum.join(missing_type_fields, ", ")}"}
    end
  end

  defp validate_field_values(feedback_item, feedback_type) do
    case feedback_type do
      :explicit_rating ->
        validate_rating_values(feedback_item)

      :explicit_correction ->
        validate_correction_values(feedback_item)

      :explicit_comment ->
        validate_comment_values(feedback_item)

      _ ->
        # For other types, basic validation is sufficient
        :ok
    end
  end

  defp validate_feedback_quality(feedback_item) do
    quality_checks = [
      check_data_completeness(feedback_item),
      check_temporal_validity(feedback_item),
      check_content_quality(feedback_item),
      check_consistency(feedback_item)
    ]

    failed_checks = Enum.filter(quality_checks, &match?({:error, _}, &1))

    if Enum.empty?(failed_checks) do
      quality_metadata = %{
        quality_validated: true,
        quality_score: calculate_overall_quality_score(quality_checks),
        validation_timestamp: DateTime.utc_now()
      }

      {:ok, Map.merge(feedback_item, quality_metadata)}
    else
      error_reasons = Enum.map(failed_checks, fn {:error, reason} -> reason end)
      {:error, "Quality validation failed: #{Enum.join(error_reasons, "; ")}"}
    end
  end

  defp validate_learning_potential(feedback_item) do
    learning_value = calculate_feedback_learning_value(feedback_item)
    confidence_score = calculate_feedback_confidence_score(feedback_item)

    if learning_value >= @quality_thresholds.min_learning_value and
         confidence_score >= @quality_thresholds.min_confidence_score do
      learning_metadata = %{
        learning_validated: true,
        calculated_learning_value: learning_value,
        calculated_confidence_score: confidence_score,
        learning_categories: determine_learning_categories(feedback_item),
        priority_level: calculate_priority_level(learning_value, confidence_score)
      }

      {:ok, Map.merge(feedback_item, learning_metadata)}
    else
      {:error,
       "Insufficient learning potential: value=#{learning_value}, confidence=#{confidence_score}"}
    end
  end

  # Specific validation helpers

  defp validate_rating_values(feedback_item) do
    rating = Map.get(feedback_item, :rating)

    if is_number(rating) and rating >= 1 and rating <= 5 do
      :ok
    else
      {:error, "Rating must be a number between 1 and 5"}
    end
  end

  defp validate_correction_values(feedback_item) do
    correction_details = Map.get(feedback_item, :correction_details)

    if is_map(correction_details) and map_size(correction_details) > 0 do
      :ok
    else
      {:error, "Correction details must be a non-empty map"}
    end
  end

  defp validate_comment_values(feedback_item) do
    comment = Map.get(feedback_item, :comment)

    if is_binary(comment) and String.length(comment) >= 5 do
      :ok
    else
      {:error, "Comment must be a string with at least 5 characters"}
    end
  end

  # Quality check functions

  defp check_data_completeness(feedback_item) do
    completeness_score = calculate_completeness_score(feedback_item)

    if completeness_score >= @quality_thresholds.min_data_completeness do
      {:ok, completeness_score}
    else
      {:error, "Data completeness below threshold: #{completeness_score}"}
    end
  end

  defp check_temporal_validity(feedback_item) do
    if Map.has_key?(feedback_item, :timestamp) do
      timestamp = Map.get(feedback_item, :timestamp)
      hours_ago = DateTime.diff(DateTime.utc_now(), timestamp, :hour)

      if hours_ago <= @quality_thresholds.max_processing_age_hours do
        {:ok, :temporal_valid}
      else
        {:error, "Feedback too old: #{hours_ago} hours ago"}
      end
    else
      # No timestamp provided, assume recent
      {:ok, :temporal_assumed_valid}
    end
  end

  defp check_content_quality(feedback_item) do
    content_quality_score = assess_content_quality(feedback_item)

    if content_quality_score > 0.5 do
      {:ok, content_quality_score}
    else
      {:error, "Content quality insufficient: #{content_quality_score}"}
    end
  end

  defp check_consistency(feedback_item) do
    consistency_checks = [
      check_internal_consistency(feedback_item),
      check_type_consistency(feedback_item),
      check_value_consistency(feedback_item)
    ]

    failed_consistency = Enum.filter(consistency_checks, &match?({:error, _}, &1))

    if Enum.empty?(failed_consistency) do
      {:ok, :consistent}
    else
      {:error, "Consistency checks failed: #{length(failed_consistency)} issues"}
    end
  end

  # Batch validation helpers

  defp validate_batch_parallel(feedback_batch) do
    feedback_batch
    |> Enum.map(&Task.async(fn -> validate_feedback_item(&1) end))
    |> Enum.map(&Task.await(&1, 10_000))
  end

  defp validate_batch_sequential(feedback_batch) do
    Enum.map(feedback_batch, &validate_feedback_item/1)
  end

  defp calculate_batch_quality_score(validation_results) do
    successful_results = Enum.filter(validation_results, &match?({:ok, _}, &1))

    if Enum.empty?(successful_results) do
      0.0
    else
      quality_scores =
        Enum.map(successful_results, fn {:ok, item} ->
          Map.get(item, :quality_score, 0.5)
        end)

      Enum.sum(quality_scores) / length(quality_scores)
    end
  end

  # Quality calculation helpers

  defp calculate_completeness_score(feedback_item) do
    # Rough estimate of comprehensive feedback
    total_possible_fields = 10

    present_fields =
      Enum.count(feedback_item, fn {_key, value} ->
        not is_nil(value) and value != ""
      end)

    min(1.0, present_fields / total_possible_fields)
  end

  defp calculate_feedback_learning_value(feedback_item) do
    feedback_type = Map.get(feedback_item, :feedback_type)

    base_value =
      case feedback_type do
        :explicit_correction -> 0.9
        :explicit_rating -> 0.7
        :judge_agreement -> 0.8
        :implicit_rejection -> 0.75
        _ -> 0.6
      end

    # Adjust based on data quality
    quality_adjustment = calculate_quality_adjustment(feedback_item)
    min(1.0, base_value + quality_adjustment)
  end

  defp calculate_feedback_confidence_score(feedback_item) do
    feedback_type = Map.get(feedback_item, :feedback_type)

    base_confidence =
      case feedback_type do
        type when type in [:explicit_correction, :explicit_rating] -> 0.85
        type when type in [:judge_agreement, :system_performance] -> 0.8
        type when type in [:implicit_rejection, :implicit_retry] -> 0.7
        _ -> 0.6
      end

    # Adjust based on data completeness and quality
    completeness_bonus = calculate_completeness_score(feedback_item) * 0.1
    quality_bonus = assess_content_quality(feedback_item) * 0.05

    min(1.0, base_confidence + completeness_bonus + quality_bonus)
  end

  defp calculate_quality_adjustment(feedback_item) do
    completeness = calculate_completeness_score(feedback_item)
    content_quality = assess_content_quality(feedback_item)

    adjustment = (completeness + content_quality) / 2 * 0.1
    max(-0.2, min(0.2, adjustment))
  end

  defp assess_content_quality(feedback_item) do
    # Assess the quality of the actual feedback content
    case Map.get(feedback_item, :feedback_type) do
      :explicit_comment ->
        assess_comment_quality(Map.get(feedback_item, :comment))

      :explicit_correction ->
        assess_correction_quality(Map.get(feedback_item, :correction_details))

      :explicit_rating ->
        assess_rating_quality(Map.get(feedback_item, :rating), Map.get(feedback_item, :context))

      _ ->
        # Default moderate quality for other types
        0.7
    end
  end

  defp calculate_overall_quality_score(quality_checks) do
    successful_checks = Enum.filter(quality_checks, &match?({:ok, _}, &1))

    if Enum.empty?(successful_checks) do
      0.0
    else
      scores =
        Enum.map(successful_checks, fn
          {:ok, score} when is_number(score) -> score
          # Default score for non-numeric results
          {:ok, _} -> 0.8
        end)

      Enum.sum(scores) / length(scores)
    end
  end

  # Content quality assessment helpers

  defp assess_comment_quality(nil), do: 0.0

  defp assess_comment_quality(comment) when is_binary(comment) do
    base_score = 0.5

    # Length indicates thoughtfulness
    length_bonus = min(0.3, String.length(comment) / 200.0)

    # Presence of specific terms indicates quality
    quality_indicators = [
      String.contains?(comment, ["because", "should", "could", "suggest"]),
      String.contains?(comment, ["improve", "better", "enhance", "fix"]),
      # Constructive vs destructive
      not String.contains?(comment, ["bad", "terrible", "awful"])
    ]

    indicator_bonus = Enum.count(quality_indicators, & &1) * 0.05

    min(1.0, base_score + length_bonus + indicator_bonus)
  end

  defp assess_comment_quality(_), do: 0.2

  defp assess_correction_quality(nil), do: 0.0

  defp assess_correction_quality(correction_details) when is_map(correction_details) do
    base_score = 0.7

    # More detailed corrections are higher quality
    detail_bonus = min(0.2, map_size(correction_details) / 10.0)

    # Specific correction types indicate quality
    quality_fields = [:suggested_score, :reasoning, :specific_issues, :recommendations]

    present_quality_fields =
      Enum.count(quality_fields, fn field ->
        Map.has_key?(correction_details, field) and not is_nil(correction_details[field])
      end)

    field_bonus = present_quality_fields * 0.05

    min(1.0, base_score + detail_bonus + field_bonus)
  end

  defp assess_correction_quality(_), do: 0.1

  defp assess_rating_quality(rating, context) when is_number(rating) do
    base_score = 0.6

    # Context provided with rating increases quality
    context_bonus =
      if is_map(context) and map_size(context) > 0 do
        min(0.2, map_size(context) / 5.0)
      else
        0.0
      end

    # Extreme ratings (1, 5) often indicate strong feelings and are valuable
    extremity_bonus = if rating in [1, 5], do: 0.1, else: 0.0

    min(1.0, base_score + context_bonus + extremity_bonus)
  end

  defp assess_rating_quality(_, _), do: 0.3

  # Source-specific validation

  defp validate_source_specific_requirements(feedback_data, source_type) do
    case source_type do
      :user_interface ->
        validate_ui_feedback_requirements(feedback_data)

      :api ->
        validate_api_feedback_requirements(feedback_data)

      :system_automated ->
        validate_system_feedback_requirements(feedback_data)

      _ ->
        # Generic validation for unknown sources
        :ok
    end
  end

  defp validate_ui_feedback_requirements(feedback_data) do
    # UI feedback should have user interaction context
    if Map.has_key?(feedback_data, :user_id) or Map.has_key?(feedback_data, :session_id) do
      :ok
    else
      {:error, "UI feedback requires user_id or session_id"}
    end
  end

  defp validate_api_feedback_requirements(feedback_data) do
    # API feedback should have proper authentication context
    if Map.has_key?(feedback_data, :api_key) or Map.has_key?(feedback_data, :user_id) do
      :ok
    else
      {:error, "API feedback requires api_key or user_id"}
    end
  end

  defp validate_system_feedback_requirements(feedback_data) do
    # System feedback should have system context
    if Map.has_key?(feedback_data, :system_component) do
      :ok
    else
      {:error, "System feedback requires system_component"}
    end
  end

  defp validate_data_integrity(feedback_data) do
    # Check for data corruption, malformed JSON, etc.
    case Jason.encode(feedback_data) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, "Data integrity check failed: cannot serialize feedback"}
    end
  end

  # Consistency check helpers

  defp check_internal_consistency(feedback_item) do
    # Check that feedback values are internally consistent
    feedback_type = Map.get(feedback_item, :feedback_type)

    case feedback_type do
      :explicit_rating ->
        check_rating_consistency(feedback_item)

      _ ->
        {:ok, :consistent}
    end
  end

  defp check_type_consistency(feedback_item) do
    feedback_type = Map.get(feedback_item, :feedback_type)

    if feedback_type in Map.keys(@required_fields_by_type) do
      {:ok, :type_consistent}
    else
      {:error, "Unknown feedback type: #{feedback_type}"}
    end
  end

  defp check_value_consistency(feedback_item) do
    # Check that values make sense in context
    case Map.get(feedback_item, :feedback_type) do
      :explicit_rating ->
        rating = Map.get(feedback_item, :rating)
        comment = Map.get(feedback_item, :comment, "")

        # Check if rating matches comment sentiment (simplified)
        sentiment = infer_comment_sentiment(comment)
        rating_sentiment = infer_rating_sentiment(rating)

        if sentiment == :unknown or rating_sentiment == :unknown or sentiment == rating_sentiment do
          {:ok, :value_consistent}
        else
          {:error, "Rating and comment sentiment mismatch"}
        end

      _ ->
        {:ok, :value_consistent}
    end
  end

  defp check_rating_consistency(feedback_item) do
    rating = Map.get(feedback_item, :rating)
    context = Map.get(feedback_item, :context, %{})

    # Check if rating makes sense with provided context
    if rating in [1, 2] and Map.get(context, :satisfaction, :unknown) == :high do
      {:error, "Low rating with high satisfaction context"}
    else
      {:ok, :rating_consistent}
    end
  end

  # Enhanced metadata generation

  defp enhance_feedback_metadata(feedback_item) do
    enhanced_metadata = %{
      validation_complete: true,
      validation_timestamp: DateTime.utc_now(),
      data_quality_indicators: generate_quality_indicators(feedback_item),
      learning_recommendations: generate_learning_recommendations(feedback_item),
      processing_recommendations: generate_processing_recommendations(feedback_item)
    }

    Map.merge(feedback_item, enhanced_metadata)
  end

  defp generate_quality_indicators(feedback_item) do
    %{
      data_richness: assess_data_richness(feedback_item),
      temporal_relevance: assess_temporal_relevance(feedback_item),
      user_engagement: assess_user_engagement_level(feedback_item),
      learning_potential: Map.get(feedback_item, :calculated_learning_value, 0.5)
    }
  end

  defp generate_learning_recommendations(feedback_item) do
    learning_value = Map.get(feedback_item, :calculated_learning_value, 0.5)
    confidence = Map.get(feedback_item, :calculated_confidence_score, 0.5)

    case {learning_value > 0.8, confidence > 0.8} do
      {true, true} -> [:high_priority_learning, :immediate_processing]
      {true, false} -> [:cautious_learning, :validation_required]
      {false, true} -> [:low_priority_learning, :batch_processing]
      {false, false} -> [:monitoring_only, :quality_improvement_needed]
    end
  end

  defp generate_processing_recommendations(feedback_item) do
    priority_level = Map.get(feedback_item, :priority_level, :medium)

    case priority_level do
      :critical -> [:immediate_processing, :high_resource_allocation]
      :high -> [:priority_processing, :standard_resources]
      :medium -> [:standard_processing, :batch_eligible]
      :low -> [:batch_processing, :resource_efficient]
    end
  end

  # Helper calculation functions

  defp calculate_data_quality_score(feedback_data) do
    completeness = calculate_completeness_score(feedback_data)
    content_quality = assess_content_quality(feedback_data)

    (completeness + content_quality) / 2
  end

  defp assess_reliability_indicators(feedback_data, source_type) do
    %{
      source_reliability: assess_source_reliability(source_type),
      data_consistency: assess_data_consistency(feedback_data),
      temporal_validity: assess_temporal_validity(feedback_data)
    }
  end

  defp determine_learning_categories(feedback_item) do
    feedback_type = Map.get(feedback_item, :feedback_type)

    case feedback_type do
      :explicit_correction -> [:evaluation_criteria_adjustment, :quality_enhancement]
      :judge_agreement -> [:judge_selection_optimization, :coordination_optimization]
      :cost_efficiency -> [:cost_optimization, :resource_efficiency]
      _ -> [:general_improvement]
    end
  end

  defp calculate_priority_level(learning_value, confidence_score) do
    combined_score = (learning_value + confidence_score) / 2

    cond do
      combined_score >= 0.9 -> :critical
      combined_score >= 0.8 -> :high
      combined_score >= 0.6 -> :medium
      combined_score >= 0.4 -> :low
      true -> :background
    end
  end

  # Assessment helper stubs (would implement comprehensive analysis)

  defp assess_source_reliability(:user_interface), do: 0.8
  defp assess_source_reliability(:api), do: 0.85
  defp assess_source_reliability(:system_automated), do: 0.9
  defp assess_source_reliability(_), do: 0.6

  defp assess_data_consistency(_feedback_data), do: 0.85
  defp assess_temporal_validity(_feedback_data), do: 0.9
  defp assess_data_richness(_feedback_item), do: 0.75
  defp assess_temporal_relevance(_feedback_item), do: 0.8
  defp assess_user_engagement_level(_feedback_item), do: 0.7

  defp infer_comment_sentiment(comment) when is_binary(comment) do
    cond do
      String.contains?(comment, ["good", "great", "excellent", "love"]) -> :positive
      String.contains?(comment, ["bad", "terrible", "awful", "hate"]) -> :negative
      true -> :unknown
    end
  end

  defp infer_comment_sentiment(_), do: :unknown

  defp infer_rating_sentiment(rating) when is_number(rating) do
    cond do
      rating >= 4 -> :positive
      rating <= 2 -> :negative
      true -> :neutral
    end
  end

  defp infer_rating_sentiment(_), do: :unknown
end
