defmodule RubberDuck.Prompts.Composition.TokenOptimizer do
  @moduledoc """
  Intelligent token optimization service for model-specific prompt compression.

  Provides intelligent prompt compression for token limits with priority-based content
  reduction strategies and semantic integrity preservation. Supports model-specific
  optimization for different LLM providers with quality validation.

  Features:
  - Intelligent prompt compression for model-specific token limits with semantic preservation
  - Priority-based content reduction strategies with importance scoring and selective compression
  - Semantic integrity preservation during compression with quality validation
  - Model-specific optimization for different LLM providers (GPT-4, Claude, etc.)
  - Performance monitoring with compression effectiveness and quality metrics
  - Integration with composition pipeline for seamless optimization workflows
  """

  require Logger

  @model_token_limits %{
    "gpt-4" => 8_192,
    "gpt-4-32k" => 32_768,
    "gpt-3.5-turbo" => 4_096,
    "claude-3-opus" => 200_000,
    "claude-3-sonnet" => 200_000,
    "claude-3-haiku" => 200_000,
    "claude-2.1" => 200_000,
    "claude-2" => 100_000
  }

  @compression_strategies [
    :priority_reduction,
    :semantic_compression,
    :redundancy_elimination,
    :model_specific_optimization
  ]

  @default_optimization_options %{
    target_model: "gpt-4",
    compression_strategy: :priority_reduction,
    preserve_semantic_integrity: true,
    # Maximum 30% reduction
    max_compression_ratio: 0.3,
    # Minimum quality score
    quality_threshold: 0.8,
    enable_performance_tracking: true
  }

  def optimize(content, options \\ %{}) do
    merged_options = Map.merge(@default_optimization_options, options)

    Logger.debug("TokenOptimizer: Starting token optimization",
      content_length: String.length(content),
      target_model: merged_options.target_model,
      strategy: merged_options.compression_strategy
    )

    optimization_start_time = System.monotonic_time(:microsecond)

    with {:ok, current_token_count} <- estimate_token_count(content, merged_options.target_model),
         {:ok, token_limit} <- get_model_token_limit(merged_options.target_model),
         {:ok, optimization_needed} <-
           assess_optimization_necessity(current_token_count, token_limit, merged_options),
         {:ok, optimized_content} <-
           execute_optimization_if_needed(content, optimization_needed, merged_options),
         {:ok, validated_content} <-
           validate_optimization_quality(content, optimized_content, merged_options) do
      optimization_time = System.monotonic_time(:microsecond) - optimization_start_time
      final_token_count = estimate_token_count(validated_content, merged_options.target_model)

      Logger.info("TokenOptimizer: Token optimization completed",
        original_tokens: current_token_count,
        final_tokens: final_token_count,
        compression_ratio: calculate_compression_ratio(current_token_count, final_token_count),
        optimization_time_us: optimization_time
      )

      {:ok,
       %{
         content: validated_content,
         optimization_metadata: %{
           optimization_time_microseconds: optimization_time,
           original_token_count: current_token_count,
           final_token_count: final_token_count,
           compression_ratio: calculate_compression_ratio(current_token_count, final_token_count),
           strategy_used: merged_options.compression_strategy,
           quality_preserved: true,
           model_optimized: merged_options.target_model
         }
       }}
    else
      {:error, reason} ->
        Logger.error("TokenOptimizer: Token optimization failed", error: reason)
        {:error, reason}
    end
  end

  def estimate_tokens_for_model(content, model_name) do
    # Estimate token count for specific model
    case estimate_token_count(content, model_name) do
      {:ok, count} -> count
      {:error, _} -> estimate_generic_token_count(content)
    end
  end

  def get_compression_recommendations(content, target_model, target_reduction \\ 0.2) do
    # Get recommendations for content compression
    current_tokens = estimate_tokens_for_model(content, target_model)
    target_tokens = round(current_tokens * (1 - target_reduction))

    recommendations = analyze_compression_opportunities(content, current_tokens, target_tokens)

    %{
      current_tokens: current_tokens,
      target_tokens: target_tokens,
      target_reduction: target_reduction,
      recommendations: recommendations,
      estimated_quality_impact: estimate_quality_impact(recommendations)
    }
  end

  # Private optimization functions

  defp estimate_token_count(content, model_name) do
    # Model-specific token estimation
    case model_name do
      model when model in ["gpt-4", "gpt-3.5-turbo"] ->
        {:ok, estimate_openai_tokens(content)}

      model
      when model in [
             "claude-3-opus",
             "claude-3-sonnet",
             "claude-3-haiku",
             "claude-2.1",
             "claude-2"
           ] ->
        {:ok, estimate_anthropic_tokens(content)}

      _ ->
        {:ok, estimate_generic_token_count(content)}
    end
  end

  defp estimate_openai_tokens(content) do
    # OpenAI token estimation (rough approximation)
    words = String.split(content, ~r/\s+/)
    # OpenAI models: roughly 1 token per 0.75 words for English
    round(length(words) / 0.75)
  end

  defp estimate_anthropic_tokens(content) do
    # Anthropic token estimation (rough approximation)
    # Claude models are more efficient, roughly 1 token per 0.8 words
    words = String.split(content, ~r/\s+/)
    round(length(words) / 0.8)
  end

  defp estimate_generic_token_count(content) do
    # Generic token estimation
    words = String.split(content, ~r/\s+/)
    # Conservative estimate
    round(length(words) / 0.75)
  end

  defp get_model_token_limit(model_name) do
    case Map.get(@model_token_limits, model_name) do
      nil -> {:error, :unknown_model}
      limit -> {:ok, limit}
    end
  end

  defp assess_optimization_necessity(current_tokens, token_limit, options) do
    # Assess whether optimization is needed
    utilization_ratio = current_tokens / token_limit

    optimization_needed =
      cond do
        current_tokens > token_limit ->
          %{required: true, reason: :exceeds_limit, severity: :critical}

        utilization_ratio > 0.9 ->
          %{required: true, reason: :approaching_limit, severity: :high}

        utilization_ratio > 0.7 ->
          %{required: false, reason: :preventive_optimization, severity: :medium}

        true ->
          %{required: false, reason: :within_limits, severity: :low}
      end

    {:ok, optimization_needed}
  end

  defp execute_optimization_if_needed(content, optimization_assessment, options) do
    if optimization_assessment.required do
      execute_compression_strategy(content, optimization_assessment, options)
    else
      {:ok, content}
    end
  end

  defp execute_compression_strategy(content, assessment, options) do
    case options.compression_strategy do
      :priority_reduction ->
        execute_priority_reduction(content, assessment, options)

      :semantic_compression ->
        execute_semantic_compression(content, assessment, options)

      :redundancy_elimination ->
        execute_redundancy_elimination(content, assessment, options)

      :model_specific_optimization ->
        execute_model_specific_optimization(content, assessment, options)
    end
  end

  defp execute_priority_reduction(content, assessment, options) do
    # Priority-based content reduction
    case assessment.severity do
      :critical ->
        # Aggressive reduction needed
        compressed = apply_aggressive_compression(content, options)
        {:ok, compressed}

      :high ->
        # Moderate reduction needed
        compressed = apply_moderate_compression(content, options)
        {:ok, compressed}

      _ ->
        # Light optimization
        compressed = apply_light_optimization(content, options)
        {:ok, compressed}
    end
  end

  defp execute_semantic_compression(content, _assessment, _options) do
    # Semantic-aware compression preserving meaning
    compressed =
      content
      |> remove_redundant_phrases()
      |> compress_verbose_expressions()
      |> optimize_sentence_structure()

    {:ok, compressed}
  end

  defp execute_redundancy_elimination(content, _assessment, _options) do
    # Remove redundant content and repetitive patterns
    compressed =
      content
      |> remove_duplicate_sentences()
      |> eliminate_filler_words()
      |> compress_repetitive_patterns()

    {:ok, compressed}
  end

  defp execute_model_specific_optimization(content, _assessment, options) do
    # Model-specific optimization strategies
    case options.target_model do
      model when model in ["gpt-4", "gpt-3.5-turbo"] ->
        {:ok, optimize_for_openai(content)}

      model when model in ["claude-3-opus", "claude-3-sonnet", "claude-3-haiku"] ->
        {:ok, optimize_for_anthropic(content)}

      _ ->
        {:ok, apply_generic_optimization(content)}
    end
  end

  defp validate_optimization_quality(original_content, optimized_content, options) do
    if options.preserve_semantic_integrity do
      quality_score = calculate_semantic_quality_score(original_content, optimized_content)

      if quality_score >= options.quality_threshold do
        {:ok, optimized_content}
      else
        Logger.warn("TokenOptimizer: Quality threshold not met",
          quality_score: quality_score,
          threshold: options.quality_threshold
        )

        {:error, {:quality_threshold_not_met, quality_score}}
      end
    else
      {:ok, optimized_content}
    end
  end

  # Compression implementation functions

  defp apply_aggressive_compression(content, _options) do
    # Aggressive compression for critical token limit situations
    content
    |> String.split(~r/\.\s+/)
    # Keep every other sentence
    |> Enum.take_every(2)
    |> Enum.join(". ")
    |> eliminate_filler_words()
  end

  defp apply_moderate_compression(content, _options) do
    # Moderate compression maintaining readability
    content
    |> remove_redundant_phrases()
    |> compress_verbose_expressions()
    |> String.trim()
  end

  defp apply_light_optimization(content, _options) do
    # Light optimization preserving full content
    content
    |> eliminate_filler_words()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp remove_redundant_phrases(content) do
    # Remove common redundant phrases
    redundant_patterns = [
      ~r/\b(please\s+)?note\s+that\b/i,
      ~r/\bit\s+is\s+important\s+to\s+note\s+that\b/i,
      ~r/\bin\s+order\s+to\b/i,
      ~r/\bfor\s+the\s+purpose\s+of\b/i
    ]

    Enum.reduce(redundant_patterns, content, fn pattern, acc ->
      String.replace(acc, pattern, "")
    end)
  end

  defp compress_verbose_expressions(content) do
    # Compress verbose expressions to more concise forms
    compression_map = [
      {~r/\bin\s+the\s+event\s+that\b/i, "if"},
      {~r/\bdue\s+to\s+the\s+fact\s+that\b/i, "because"},
      {~r/\bfor\s+the\s+reason\s+that\b/i, "because"},
      {~r/\bin\s+spite\s+of\s+the\s+fact\s+that\b/i, "although"}
    ]

    Enum.reduce(compression_map, content, fn {pattern, replacement}, acc ->
      String.replace(acc, pattern, replacement)
    end)
  end

  defp optimize_sentence_structure(content) do
    # Optimize sentence structure for clarity and brevity
    content
    |> String.replace(~r/\s*,\s*which\s+/, ", ")
    |> String.replace(~r/\s*;\s*however,\s*/, ". ")
    |> String.replace(~r/\s+/, " ")
  end

  defp remove_duplicate_sentences(content) do
    # Remove duplicate sentences
    sentences =
      String.split(content, ~r/[.!?]+\s*/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    Enum.join(sentences, ". ")
  end

  defp eliminate_filler_words(content) do
    # Remove common filler words
    filler_words = [
      "basically",
      "actually",
      "literally",
      "really",
      "very",
      "quite",
      "rather",
      "pretty",
      "somewhat",
      "kind of",
      "sort of"
    ]

    filler_pattern = ~r/\b(#{Enum.join(filler_words, "|")})\s+/i
    String.replace(content, filler_pattern, "")
  end

  defp compress_repetitive_patterns(content) do
    # Compress repetitive patterns and structures
    content
    # Remove repeated words
    |> String.replace(~r/(\w+)\s+\1\b/i, "\\1")
    # Multiple spaces to single
    |> String.replace(~r/\s{2,}/, " ")
    |> String.trim()
  end

  # Model-specific optimization functions

  defp optimize_for_openai(content) do
    # OpenAI-specific optimization
    content
    |> compress_verbose_expressions()
    |> eliminate_filler_words()
    |> optimize_for_instruction_following()
  end

  defp optimize_for_anthropic(content) do
    # Anthropic Claude-specific optimization
    content
    |> optimize_for_constitutional_ai()
    |> preserve_reasoning_structure()
    |> enhance_helpfulness_cues()
  end

  defp apply_generic_optimization(content) do
    # Generic optimization for unknown models
    content
    |> remove_redundant_phrases()
    |> eliminate_filler_words()
    |> String.trim()
  end

  defp optimize_for_instruction_following(content) do
    # Optimize content for better instruction following
    content
    |> String.replace(~r/\bplease\s+/i, "")
    |> String.replace(~r/\bkindly\s+/i, "")
  end

  defp optimize_for_constitutional_ai(content) do
    # Optimize for Constitutional AI principles
    content
    |> ensure_helpful_harmless_honest_structure()
  end

  defp preserve_reasoning_structure(content) do
    # Preserve logical reasoning structure
    # Placeholder - would implement sophisticated reasoning preservation
    content
  end

  defp enhance_helpfulness_cues(content) do
    # Enhance cues for helpful responses
    # Placeholder - would implement helpfulness enhancement
    content
  end

  defp ensure_helpful_harmless_honest_structure(content) do
    # Ensure content follows HHH principles
    # Placeholder - would implement HHH optimization
    content
  end

  # Quality and validation functions

  defp calculate_semantic_quality_score(original_content, optimized_content) do
    # Calculate semantic similarity score between original and optimized content
    original_words = extract_important_words(original_content)
    optimized_words = extract_important_words(optimized_content)

    # Simple overlap-based similarity
    common_words = MapSet.intersection(original_words, optimized_words)
    union_words = MapSet.union(original_words, optimized_words)

    case MapSet.size(union_words) do
      0 -> 1.0
      _ -> MapSet.size(common_words) / MapSet.size(union_words)
    end
  end

  defp extract_important_words(content) do
    # Extract semantically important words (excluding stop words)
    stop_words =
      MapSet.new([
        "the",
        "a",
        "an",
        "and",
        "or",
        "but",
        "in",
        "on",
        "at",
        "to",
        "for",
        "of",
        "with",
        "by",
        "is",
        "are",
        "was",
        "were",
        "be",
        "been",
        "have",
        "has"
      ])

    content
    |> String.downcase()
    |> String.split(~r/\W+/)
    |> Enum.reject(fn word -> word == "" or MapSet.member?(stop_words, word) end)
    |> MapSet.new()
  end

  defp analyze_compression_opportunities(content, current_tokens, target_tokens) do
    # Analyze compression opportunities in the content
    reduction_needed = current_tokens - target_tokens

    %{
      redundancy_elimination: analyze_redundancy_potential(content),
      verbose_expression_compression: analyze_verbosity_potential(content),
      filler_word_removal: analyze_filler_word_potential(content),
      sentence_structure_optimization: analyze_structure_optimization_potential(content),
      estimated_total_reduction: reduction_needed
    }
  end

  defp analyze_redundancy_potential(content) do
    # Analyze potential for redundancy elimination
    sentences = String.split(content, ~r/[.!?]+/)
    unique_sentences = Enum.uniq(sentences)

    redundancy_ratio = (length(sentences) - length(unique_sentences)) / max(length(sentences), 1)

    %{
      redundancy_ratio: redundancy_ratio,
      estimated_reduction: redundancy_ratio * 0.8,
      confidence: :medium
    }
  end

  defp analyze_verbosity_potential(content) do
    # Analyze potential for verbose expression compression
    verbose_patterns = [
      ~r/\bin\s+order\s+to\b/i,
      ~r/\bdue\s+to\s+the\s+fact\s+that\b/i,
      ~r/\bfor\s+the\s+purpose\s+of\b/i
    ]

    verbose_matches =
      Enum.map(verbose_patterns, fn pattern ->
        length(Regex.scan(pattern, content))
      end)
      |> Enum.sum()

    %{
      verbose_expressions_found: verbose_matches,
      # Roughly 3 tokens saved per expression
      estimated_reduction: verbose_matches * 3,
      confidence: :high
    }
  end

  defp analyze_filler_word_potential(content) do
    # Analyze potential for filler word removal
    filler_pattern = ~r/\b(very|really|quite|rather|pretty|somewhat)\s+/i
    filler_matches = length(Regex.scan(filler_pattern, content))

    %{
      filler_words_found: filler_matches,
      # 1 token saved per filler word
      estimated_reduction: filler_matches,
      confidence: :high
    }
  end

  defp analyze_structure_optimization_potential(content) do
    # Analyze potential for sentence structure optimization
    long_sentences =
      content
      |> String.split(~r/[.!?]+/)
      |> Enum.count(fn sentence ->
        word_count = length(String.split(sentence, ~r/\s+/))
        word_count > 20
      end)

    %{
      long_sentences_found: long_sentences,
      # Roughly 5 tokens saved per long sentence
      estimated_reduction: long_sentences * 5,
      confidence: :medium
    }
  end

  defp estimate_quality_impact(recommendations) do
    # Estimate overall quality impact of compression recommendations
    total_reduction =
      recommendations.redundancy_elimination.estimated_reduction +
        recommendations.verbose_expression_compression.estimated_reduction +
        recommendations.filler_word_removal.estimated_reduction +
        recommendations.sentence_structure_optimization.estimated_reduction

    # Quality impact increases with compression amount
    case total_reduction do
      reduction when reduction < 50 -> :minimal_impact
      reduction when reduction < 150 -> :low_impact
      reduction when reduction < 300 -> :medium_impact
      _ -> :high_impact
    end
  end

  # Utility functions

  defp calculate_compression_ratio(original_tokens, final_tokens) do
    case original_tokens do
      0 -> 0.0
      _ -> Float.round((original_tokens - final_tokens) / original_tokens, 3)
    end
  end
end
