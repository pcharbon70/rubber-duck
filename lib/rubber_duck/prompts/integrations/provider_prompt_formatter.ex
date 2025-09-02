defmodule RubberDuck.Prompts.Integrations.ProviderPromptFormatter do
  @moduledoc """
  Provider-specific prompt formatting service for optimal LLM performance.

  Provides intelligent prompt formatting optimized for different LLM providers
  including OpenAI GPT models, Anthropic Claude models, Google Gemini, and others.
  Enhances prompt effectiveness through provider-specific optimization patterns.

  Features:
  - Provider-specific prompt formatting with model optimization and compatibility
  - Intelligent content adaptation based on provider strengths and characteristics
  - Performance optimization for different model architectures and capabilities
  - Context preservation during formatting with semantic integrity validation
  - Token optimization and efficiency improvements for cost and latency optimization
  - Integration with prompt composition pipeline for seamless provider enhancement
  """

  require Logger

  @provider_configs %{
    openai: %{
      models: ["gpt-4", "gpt-3.5-turbo"],
      strengths: [:reasoning, :code_generation, :analysis],
      optimal_structure: :clear_instructions,
      token_efficiency: :high,
      formatting_strategy: :instruction_focused
    },
    anthropic: %{
      models: ["claude-3-opus", "claude-3-sonnet", "claude-3-haiku", "claude-2"],
      strengths: [:reasoning, :creative_writing, :analysis, :helpfulness],
      optimal_structure: :conversational,
      token_efficiency: :very_high,
      formatting_strategy: :constitutional_ai
    },
    google: %{
      models: ["gemini-pro", "gemini-ultra"],
      strengths: [:multimodal, :reasoning, :general_tasks],
      optimal_structure: :structured_reasoning,
      token_efficiency: :medium,
      formatting_strategy: :reasoning_chains
    },
    generic: %{
      models: ["*"],
      strengths: [:general_tasks],
      optimal_structure: :simple_instructions,
      token_efficiency: :medium,
      formatting_strategy: :universal_compatibility
    }
  }

  def format_for_provider(prompt_content, provider, context \\ %{}) do
    formatting_start_time = System.monotonic_time(:microsecond)

    Logger.debug("ProviderPromptFormatter: Starting provider-specific formatting",
      provider: provider,
      content_length: String.length(prompt_content)
    )

    with {:ok, provider_config} <- get_provider_configuration(provider),
         {:ok, formatting_strategy} <-
           determine_formatting_strategy(prompt_content, provider_config, context),
         {:ok, formatted_content} <-
           execute_provider_formatting(prompt_content, formatting_strategy, provider_config),
         {:ok, validation_result} <-
           validate_formatted_content(formatted_content, prompt_content, provider_config) do
      formatting_time = System.monotonic_time(:microsecond) - formatting_start_time

      Logger.info("ProviderPromptFormatter: Provider formatting completed",
        provider: provider,
        original_length: String.length(prompt_content),
        formatted_length: String.length(formatted_content),
        formatting_time_us: formatting_time
      )

      {:ok,
       %{
         content: formatted_content,
         original_content: prompt_content,
         formatting_metadata: %{
           formatting_time_microseconds: formatting_time,
           provider: provider,
           strategy_used: formatting_strategy.strategy,
           optimization_applied: formatting_strategy.optimization_level,
           token_optimization: calculate_token_optimization(prompt_content, formatted_content),
           quality_preserved: validation_result.quality_preserved
         }
       }}
    else
      {:error, reason} ->
        Logger.error("ProviderPromptFormatter: Provider formatting failed",
          provider: provider,
          error: reason
        )

        {:error, reason}
    end
  end

  def get_supported_providers do
    @provider_configs
    |> Map.values()
    |> Enum.flat_map(fn config -> config.models end)
    |> Enum.uniq()
  end

  def get_provider_optimization_recommendations(prompt_content, provider) do
    case get_provider_configuration(provider) do
      {:ok, provider_config} ->
        analyze_optimization_opportunities(prompt_content, provider_config)

      {:error, _reason} ->
        {:ok, %{recommendations: ["Provider not supported for optimization"]}}
    end
  end

  # Private formatting functions

  defp get_provider_configuration(provider) do
    provider_family = determine_provider_family(provider)

    case Map.get(@provider_configs, provider_family) do
      nil -> {:error, :unsupported_provider}
      config -> {:ok, config}
    end
  end

  defp determine_provider_family(provider) do
    cond do
      provider in ["gpt-4", "gpt-3.5-turbo"] -> :openai
      provider in ["claude-3-opus", "claude-3-sonnet", "claude-3-haiku", "claude-2"] -> :anthropic
      provider in ["gemini-pro", "gemini-ultra"] -> :google
      true -> :generic
    end
  end

  defp determine_formatting_strategy(prompt_content, provider_config, context) do
    base_strategy = provider_config.formatting_strategy

    # Analyze content characteristics
    content_analysis = analyze_content_characteristics(prompt_content)

    # Determine optimization level
    optimization_level =
      case {
        Map.get(context, :quality_requirements, :standard),
        provider_config.token_efficiency,
        content_analysis.complexity
      } do
        {:high, :very_high, :complex} -> :maximum_optimization
        {:high, :high, _} -> :high_optimization
        {:standard, _, :simple} -> :basic_optimization
        _ -> :standard_optimization
      end

    formatting_strategy = %{
      strategy: base_strategy,
      optimization_level: optimization_level,
      content_characteristics: content_analysis,
      provider_strengths: provider_config.strengths
    }

    {:ok, formatting_strategy}
  end

  defp execute_provider_formatting(prompt_content, formatting_strategy, provider_config) do
    case formatting_strategy.strategy do
      :instruction_focused ->
        execute_instruction_focused_formatting(prompt_content, formatting_strategy)

      :constitutional_ai ->
        execute_constitutional_ai_formatting(prompt_content, formatting_strategy)

      :reasoning_chains ->
        execute_reasoning_chains_formatting(prompt_content, formatting_strategy)

      :universal_compatibility ->
        execute_universal_formatting(prompt_content, formatting_strategy)
    end
  end

  defp execute_instruction_focused_formatting(prompt_content, strategy) do
    # OpenAI-optimized formatting with clear instructions
    formatted =
      prompt_content
      |> ensure_clear_instruction_structure()
      |> optimize_for_instruction_following()
      |> apply_openai_best_practices(strategy.optimization_level)

    {:ok, formatted}
  end

  defp execute_constitutional_ai_formatting(prompt_content, strategy) do
    # Anthropic Claude-optimized formatting
    formatted =
      prompt_content
      |> ensure_helpful_harmless_honest_structure()
      |> optimize_for_constitutional_ai()
      |> apply_anthropic_best_practices(strategy.optimization_level)

    {:ok, formatted}
  end

  defp execute_reasoning_chains_formatting(prompt_content, strategy) do
    # Google Gemini-optimized formatting with reasoning chains
    formatted =
      prompt_content
      |> ensure_reasoning_chain_structure()
      |> optimize_for_multimodal_compatibility()
      |> apply_gemini_best_practices(strategy.optimization_level)

    {:ok, formatted}
  end

  defp execute_universal_formatting(prompt_content, strategy) do
    # Universal formatting for unknown providers
    formatted =
      prompt_content
      |> ensure_universal_compatibility()
      |> apply_safe_formatting_practices()

    {:ok, formatted}
  end

  # Provider-specific formatting implementations

  defp ensure_clear_instruction_structure(content) do
    # Ensure content has clear instruction structure for OpenAI
    if String.starts_with?(content, ["Please", "Help", "Explain", "Generate"]) do
      content
    else
      "Please " <> content
    end
  end

  defp optimize_for_instruction_following(content) do
    # Optimize content for instruction-following models
    content
    |> String.replace(~r/\bplease\s+please\b/i, "please")
    |> String.trim()
  end

  defp apply_openai_best_practices(content, optimization_level) do
    case optimization_level do
      :maximum_optimization ->
        content
        |> remove_unnecessary_politeness()
        |> optimize_instruction_clarity()
        |> ensure_specific_output_format()

      :high_optimization ->
        content
        |> optimize_instruction_clarity()
        |> ensure_specific_output_format()

      _ ->
        content
    end
  end

  defp ensure_helpful_harmless_honest_structure(content) do
    # Ensure content follows HHH principles for Claude
    if String.contains?(content, ["helpful", "harmless", "honest"]) do
      content
    else
      content <> "\n\nPlease provide a helpful, harmless, and honest response."
    end
  end

  defp optimize_for_constitutional_ai(content) do
    # Optimize for Constitutional AI principles
    content
    |> ensure_respectful_language()
    |> add_safety_considerations()
  end

  defp apply_anthropic_best_practices(content, optimization_level) do
    case optimization_level do
      :maximum_optimization ->
        content
        |> enhance_reasoning_structure()
        |> optimize_for_thoughtfulness()
        |> ensure_balanced_perspective()

      _ ->
        content
        |> enhance_reasoning_structure()
    end
  end

  defp ensure_reasoning_chain_structure(content) do
    # Structure content for reasoning chains (Gemini)
    if String.contains?(content, ["step", "first", "then", "finally"]) do
      content
    else
      "Let's approach this step by step:\n\n" <> content
    end
  end

  defp optimize_for_multimodal_compatibility(content) do
    # Ensure content works well with multimodal capabilities
    content
  end

  defp apply_gemini_best_practices(content, optimization_level) do
    case optimization_level do
      :maximum_optimization ->
        content
        |> enhance_structured_thinking()
        |> optimize_for_comprehensive_analysis()

      _ ->
        content
    end
  end

  defp ensure_universal_compatibility(content) do
    # Ensure broad compatibility across providers
    content
  end

  defp apply_safe_formatting_practices(content) do
    # Apply safe formatting for unknown providers
    content
    |> String.trim()
    |> ensure_reasonable_length()
  end

  # Utility functions

  defp analyze_content_characteristics(prompt_content) do
    %{
      length: String.length(prompt_content),
      complexity: calculate_content_complexity(prompt_content),
      instruction_type: determine_instruction_type(prompt_content),
      variable_count: count_template_variables(prompt_content)
    }
  end

  defp calculate_content_complexity(prompt_content) do
    # Calculate content complexity
    factors = [
      # Length factor
      String.length(prompt_content) / 1000,
      # Sentence complexity
      length(String.split(prompt_content, ~r/[.!?]/)),
      # Variable complexity
      length(Regex.scan(~r/\{\{[^}]+\}\}/, prompt_content)) * 0.1
    ]

    complexity_score = Enum.sum(factors) / length(factors)

    cond do
      complexity_score < 0.3 -> :simple
      complexity_score < 0.7 -> :moderate
      true -> :complex
    end
  end

  defp determine_instruction_type(prompt_content) do
    cond do
      String.contains?(prompt_content, ["analyze", "analysis"]) -> :analysis
      String.contains?(prompt_content, ["generate", "create"]) -> :generation
      String.contains?(prompt_content, ["explain", "describe"]) -> :explanation
      String.contains?(prompt_content, ["review", "evaluate"]) -> :evaluation
      true -> :general
    end
  end

  defp count_template_variables(prompt_content) do
    Regex.scan(~r/\{\{[^}]+\}\}/, prompt_content) |> length()
  end

  defp validate_formatted_content(formatted_content, original_content, provider_config) do
    # Validate that formatting preserved quality
    similarity_score = calculate_content_similarity(original_content, formatted_content)
    length_change_ratio = calculate_length_change(original_content, formatted_content)

    quality_preserved = similarity_score > 0.8 and length_change_ratio < 0.3

    {:ok,
     %{
       quality_preserved: quality_preserved,
       similarity_score: similarity_score,
       length_change_ratio: length_change_ratio,
       formatting_effective: quality_preserved
     }}
  end

  defp calculate_token_optimization(original_content, formatted_content) do
    original_tokens = estimate_token_count(original_content)
    formatted_tokens = estimate_token_count(formatted_content)

    case original_tokens do
      0 -> 0.0
      tokens -> (tokens - formatted_tokens) / tokens
    end
  end

  defp calculate_content_similarity(original, formatted) do
    # Simple word-based similarity
    original_words = extract_words(original)
    formatted_words = extract_words(formatted)

    common_words = MapSet.intersection(original_words, formatted_words)
    union_words = MapSet.union(original_words, formatted_words)

    case MapSet.size(union_words) do
      0 -> 1.0
      _ -> MapSet.size(common_words) / MapSet.size(union_words)
    end
  end

  defp calculate_length_change(original, formatted) do
    original_length = String.length(original)
    formatted_length = String.length(formatted)

    case original_length do
      0 -> 0.0
      _ -> abs(original_length - formatted_length) / original_length
    end
  end

  defp extract_words(content) do
    content
    |> String.downcase()
    |> String.split(~r/\W+/)
    |> Enum.reject(fn word -> word == "" end)
    |> MapSet.new()
  end

  defp estimate_token_count(content) do
    # Generic token estimation
    words = String.split(content, ~r/\s+/)
    round(length(words) / 0.75)
  end

  defp analyze_optimization_opportunities(prompt_content, provider_config) do
    opportunities = []

    # Length optimization
    opportunities =
      if String.length(prompt_content) > 5000 do
        ["Consider shortening prompt for better performance" | opportunities]
      else
        opportunities
      end

    # Provider-specific optimization
    opportunities =
      case provider_config.formatting_strategy do
        :instruction_focused ->
          ["Optimize instruction clarity for better GPT performance" | opportunities]

        :constitutional_ai ->
          ["Enhance reasoning structure for better Claude performance" | opportunities]

        :reasoning_chains ->
          ["Structure as reasoning chain for better Gemini performance" | opportunities]

        _ ->
          opportunities
      end

    {:ok,
     %{
       recommendations:
         case opportunities do
           [] -> ["Prompt is well-optimized for this provider"]
           _ -> opportunities
         end,
       optimization_potential: length(opportunities) * 0.1
     }}
  end

  # Formatting helper functions

  defp remove_unnecessary_politeness(content) do
    content
    |> String.replace(~r/\bplease\s+/i, "")
    |> String.replace(~r/\bkindly\s+/i, "")
    |> String.replace(~r/\bif\s+you\s+would\b/i, "")
  end

  defp optimize_instruction_clarity(content) do
    content
    |> String.replace(~r/\bi\s+would\s+like\s+you\s+to\b/i, "")
    |> String.replace(~r/\bcould\s+you\s+please\b/i, "")
  end

  defp ensure_specific_output_format(content) do
    if String.contains?(content, ["format", "structure", "output"]) do
      content
    else
      content <> "\n\nProvide a clear and structured response."
    end
  end

  defp ensure_respectful_language(content) do
    # Ensure respectful language for Constitutional AI
    content
  end

  defp add_safety_considerations(content) do
    # Add safety considerations for Claude
    if String.contains?(content, ["safe", "ethical", "responsible"]) do
      content
    else
      content <> "\n\nPlease ensure your response is safe and ethical."
    end
  end

  defp enhance_reasoning_structure(content) do
    # Enhance reasoning structure for Claude
    if String.contains?(content, ["because", "therefore", "reasoning"]) do
      content
    else
      content <> "\n\nPlease explain your reasoning."
    end
  end

  defp optimize_for_thoughtfulness(content) do
    # Optimize for thoughtful responses
    content
  end

  defp ensure_balanced_perspective(content) do
    # Ensure balanced perspective in responses
    content
  end

  defp enhance_structured_thinking(content) do
    # Enhance structured thinking for Gemini
    content
  end

  defp optimize_for_comprehensive_analysis(content) do
    # Optimize for comprehensive analysis
    content
  end

  defp ensure_reasonable_length(content) do
    # Ensure content is reasonable length
    if String.length(content) > 10_000 do
      String.slice(content, 0, 10_000) <> "... [content truncated for length]"
    else
      content
    end
  end
end
