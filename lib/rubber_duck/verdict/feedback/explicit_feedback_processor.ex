defmodule RubberDuck.Verdict.Feedback.ExplicitFeedbackProcessor do
  @moduledoc """
  Processor for explicit user feedback including ratings, corrections, and detailed comments.
  
  Handles direct user input with high confidence and learning value, extracting
  actionable insights for immediate system improvement and long-term learning.
  """

  require Logger

  @doc """
  Process explicit user feedback for learning insights.
  
  ## Parameters
  - `evaluation_id` - The evaluation this feedback relates to
  - `feedback_type` - Type of explicit feedback
  - `feedback_data` - The actual feedback content
  - `options` - Processing options
  
  ## Returns
  - `{:ok, processed_feedback}` - Processing successful
  - `{:error, reason}` - Processing failed
  """
  def process_feedback(evaluation_id, feedback_type, feedback_data, options \\ []) do
    Logger.debug("Processing #{feedback_type} feedback for evaluation #{evaluation_id}")
    
    case feedback_type do
      :explicit_rating ->
        process_rating_feedback(evaluation_id, feedback_data, options)
        
      :explicit_correction ->
        process_correction_feedback(evaluation_id, feedback_data, options)
        
      :explicit_comment ->
        process_comment_feedback(evaluation_id, feedback_data, options)
        
      _ ->
        {:error, "Unsupported explicit feedback type: #{feedback_type}"}
    end
  end

  ## Private Processing Functions

  defp process_rating_feedback(evaluation_id, feedback_data, options) do
    rating = Map.get(feedback_data, :rating)
    context = Map.get(feedback_data, :context, %{})
    
    case validate_rating(rating) do
      :ok ->
        processed_feedback = %{
          evaluation_id: evaluation_id,
          feedback_type: :explicit_rating,
          confidence: calculate_rating_confidence(rating, context),
          learning_value: calculate_rating_learning_value(rating, context),
          insights: extract_rating_insights(rating, context),
          learning_actions: generate_rating_actions(rating, context),
          processed_at: DateTime.utc_now(),
          processing_metadata: %{
            processor: :explicit_rating_processor,
            version: "1.0.0",
            options: options
          }
        }
        
        {:ok, processed_feedback}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_correction_feedback(evaluation_id, feedback_data, options) do
    correction_details = Map.get(feedback_data, :correction_details)
    user_explanation = Map.get(feedback_data, :user_explanation)
    suggested_score = Map.get(feedback_data, :suggested_score)
    
    case validate_correction_data(correction_details, user_explanation) do
      :ok ->
        processed_feedback = %{
          evaluation_id: evaluation_id,
          feedback_type: :explicit_correction,
          confidence: 0.9,  # High confidence for explicit corrections
          learning_value: calculate_correction_learning_value(correction_details, user_explanation),
          insights: extract_correction_insights(correction_details, user_explanation, suggested_score),
          learning_actions: generate_correction_actions(correction_details, user_explanation),
          processed_at: DateTime.utc_now(),
          correction_metadata: %{
            has_explanation: not is_nil(user_explanation),
            has_suggested_score: not is_nil(suggested_score),
            correction_complexity: assess_correction_complexity(correction_details)
          },
          processing_metadata: %{
            processor: :explicit_correction_processor,
            version: "1.0.0",
            options: options
          }
        }
        
        {:ok, processed_feedback}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_comment_feedback(evaluation_id, feedback_data, options) do
    comment_text = Map.get(feedback_data, :comment)
    sentiment = Map.get(feedback_data, :sentiment)
    categories = Map.get(feedback_data, :categories, [])
    
    case validate_comment_data(comment_text) do
      :ok ->
        processed_feedback = %{
          evaluation_id: evaluation_id,
          feedback_type: :explicit_comment,
          confidence: calculate_comment_confidence(comment_text, sentiment),
          learning_value: calculate_comment_learning_value(comment_text, categories),
          insights: extract_comment_insights(comment_text, sentiment, categories),
          learning_actions: generate_comment_actions(comment_text, sentiment, categories),
          processed_at: DateTime.utc_now(),
          comment_metadata: %{
            text_length: String.length(comment_text || ""),
            detected_sentiment: sentiment,
            category_count: length(categories),
            language_detected: detect_comment_language(comment_text)
          },
          processing_metadata: %{
            processor: :explicit_comment_processor,
            version: "1.0.0",
            options: options
          }
        }
        
        {:ok, processed_feedback}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Validation helpers

  defp validate_rating(rating) when is_number(rating) and rating >= 1 and rating <= 5, do: :ok
  defp validate_rating(_rating), do: {:error, "Rating must be a number between 1 and 5"}

  defp validate_correction_data(correction_details, _explanation) when is_map(correction_details), do: :ok
  defp validate_correction_data(nil, explanation) when is_binary(explanation) and byte_size(explanation) > 10, do: :ok
  defp validate_correction_data(_correction, _explanation), do: {:error, "Invalid correction data"}

  defp validate_comment_data(comment) when is_binary(comment) and byte_size(comment) > 5, do: :ok
  defp validate_comment_data(_comment), do: {:error, "Comment must be a non-empty string"}

  # Confidence calculation helpers

  defp calculate_rating_confidence(rating, context) do
    base_confidence = 0.8
    
    # Higher confidence for extreme ratings (very positive or negative)
    rating_adjustment = case rating do
      r when r == 1 or r == 5 -> 0.1
      r when r == 2 or r == 4 -> 0.05
      _ -> 0.0
    end
    
    # Bonus for additional context
    context_bonus = if map_size(context) > 0, do: 0.05, else: 0.0
    
    min(1.0, base_confidence + rating_adjustment + context_bonus)
  end

  defp calculate_comment_confidence(comment_text, sentiment) do
    base_confidence = 0.7
    
    # Longer comments generally have higher confidence
    length_bonus = min(0.15, String.length(comment_text || "") / 1000.0)
    
    # Sentiment analysis adds confidence
    sentiment_bonus = case sentiment do
      s when s in [:positive, :negative] -> 0.1
      :neutral -> 0.05
      _ -> 0.0
    end
    
    min(1.0, base_confidence + length_bonus + sentiment_bonus)
  end

  # Learning value calculation helpers

  defp calculate_rating_learning_value(rating, context) do
    # Extreme ratings have higher learning value
    base_value = case rating do
      r when r in [1, 5] -> 0.8
      r when r in [2, 4] -> 0.6
      _ -> 0.4
    end
    
    # Additional context increases learning value
    context_bonus = min(0.15, map_size(context) * 0.05)
    
    min(1.0, base_value + context_bonus)
  end

  defp calculate_correction_learning_value(correction_details, user_explanation) do
    base_value = 0.9  # Corrections are always high value
    
    # Detailed explanations increase value
    explanation_bonus = if is_binary(user_explanation) and String.length(user_explanation) > 50 do
      0.05
    else
      0.0
    end
    
    # Structured correction data increases value
    structure_bonus = if is_map(correction_details) and map_size(correction_details) > 2 do
      0.05
    else
      0.0
    end
    
    min(1.0, base_value + explanation_bonus + structure_bonus)
  end

  defp calculate_comment_learning_value(comment_text, categories) do
    base_value = 0.6
    
    # Longer, more detailed comments have higher value
    length_bonus = min(0.2, String.length(comment_text || "") / 500.0)
    
    # Categorized feedback has higher value
    category_bonus = min(0.1, length(categories) * 0.03)
    
    min(1.0, base_value + length_bonus + category_bonus)
  end

  # Insight extraction helpers

  defp extract_rating_insights(rating, context) do
    satisfaction_level = case rating do
      r when r >= 4 -> :high
      r when r == 3 -> :medium
      _ -> :low
    end
    
    %{
      satisfaction_level: satisfaction_level,
      rating_value: rating,
      context_provided: map_size(context) > 0,
      improvement_areas: identify_rating_improvement_areas(rating, context)
    }
  end

  defp extract_correction_insights(correction_details, user_explanation, suggested_score) do
    %{
      correction_type: categorize_correction_type(correction_details),
      user_reasoning_quality: assess_reasoning_quality(user_explanation),
      score_adjustment: calculate_score_adjustment(suggested_score),
      affected_evaluation_areas: identify_affected_areas(correction_details),
      correction_complexity: assess_correction_complexity(correction_details)
    }
  end

  defp extract_comment_insights(comment_text, sentiment, categories) do
    %{
      comment_sentiment: sentiment,
      text_analysis: analyze_comment_text(comment_text),
      category_insights: extract_category_insights(categories),
      actionable_suggestions: extract_suggestions_from_comment(comment_text)
    }
  end

  # Action generation helpers

  defp generate_rating_actions(rating, context) do
    case rating do
      r when r <= 2 -> ["investigate_low_satisfaction", "improve_evaluation_quality", "check_judge_selection"]
      r when r >= 4 -> ["reinforce_current_approach", "identify_success_patterns"]
      _ -> ["general_quality_monitoring"]
    end
  end

  defp generate_correction_actions(correction_details, user_explanation) do
    base_actions = ["update_evaluation_criteria", "adjust_scoring_weights"]
    
    explanation_actions = if is_binary(user_explanation) and String.length(user_explanation) > 20 do
      ["incorporate_user_reasoning", "update_explanation_templates"]
    else
      []
    end
    
    base_actions ++ explanation_actions
  end

  defp generate_comment_actions(comment_text, sentiment, categories) do
    sentiment_actions = case sentiment do
      :negative -> ["investigate_user_concerns", "improve_user_experience"]
      :positive -> ["identify_success_factors", "replicate_positive_patterns"]
      _ -> []
    end
    
    category_actions = Enum.flat_map(categories, fn category ->
      case category do
        :accuracy -> ["improve_evaluation_accuracy"]
        :speed -> ["optimize_evaluation_performance"]
        :usability -> ["enhance_user_interface"]
        _ -> []
      end
    end)
    
    sentiment_actions ++ category_actions
  end

  # Helper stubs (would be implemented with actual analysis logic)

  defp identify_rating_improvement_areas(rating, _context) do
    if rating <= 2, do: [:accuracy, :relevance, :speed], else: []
  end

  defp categorize_correction_type(_correction_details), do: :score_adjustment
  defp assess_reasoning_quality(explanation) when is_binary(explanation), do: :good
  defp assess_reasoning_quality(_), do: :unknown
  defp calculate_score_adjustment(suggested_score) when is_number(suggested_score), do: suggested_score - 0.5
  defp calculate_score_adjustment(_), do: 0.0
  defp identify_affected_areas(_correction_details), do: [:evaluation_criteria]
  defp assess_correction_complexity(_correction_details), do: :medium

  defp analyze_comment_text(comment_text) do
    %{
      word_count: length(String.split(comment_text || "", " ")),
      contains_suggestions: String.contains?(comment_text || "", ["suggest", "recommend", "should"]),
      contains_criticism: String.contains?(comment_text || "", ["wrong", "bad", "poor", "terrible"])
    }
  end

  defp extract_category_insights(categories) do
    Enum.map(categories, fn category ->
      %{category: category, relevance: :high}
    end)
  end

  defp extract_suggestions_from_comment(comment_text) do
    # Would implement NLP processing to extract actionable suggestions
    if String.contains?(comment_text || "", ["suggest", "recommend"]) do
      ["user_provided_suggestions_detected"]
    else
      []
    end
  end

  defp detect_comment_language(_comment_text), do: :english
end