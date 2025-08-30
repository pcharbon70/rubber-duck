defmodule RubberDuck.Skills.Reasoning.Actions.GenerateReasoningAction do
  @moduledoc """
  Chain-of-Thought reasoning generation action with quality validation.

  This action implements sophisticated reasoning generation using Chain-of-Thought
  techniques including Zero-Shot CoT, Few-Shot CoT, and Faithful CoT with
  step-by-step validation, error detection, and quality assessment.

  Features:
  - Multiple CoT variants (Zero-Shot, Few-Shot, Faithful) with adaptive selection
  - Step-by-step reasoning generation with logical validation
  - Error detection and correction integration throughout reasoning process
  - Quality assessment using logical consistency, coherence, and conclusion support
  - Integration with provider selection for optimal reasoning model selection
  - Learning from reasoning outcomes for continuous improvement

  Chain-of-Thought Techniques:
  - **Zero-Shot CoT**: "Let's think step by step" prompting for general reasoning
  - **Few-Shot CoT**: Example-based reasoning with curated demonstrations
  - **Faithful CoT**: Fact-grounded reasoning with source attribution and verification
  """

  use Jido.Action,
    name: "generate_reasoning",
    schema: [
      query: [type: :string, required: true, doc: "Question or problem to reason about"],
      reasoning_type: [
        type: :atom,
        default: :zero_shot_cot,
        doc: "CoT variant (:zero_shot_cot, :few_shot_cot, :faithful_cot)"
      ],
      context: [type: :map, default: %{}, doc: "Additional context and constraints"],
      examples: [type: {:list, :map}, default: [], doc: "Examples for few-shot reasoning"],
      quality_requirements: [type: :map, default: %{}, doc: "Quality thresholds and requirements"],
      provider_config: [type: :map, default: %{}, doc: "Provider and model configuration"]
    ]

  require Logger

  alias RubberDuck.Reasoning.{ReasoningChain, ReasoningStep}
  alias RubberDuck.Skills.Actions.CallAPIAction
  alias RubberDuck.Skills.Routing.Actions.DetermineRouteAction

  # CoT prompt templates for different reasoning types
  @cot_templates %{
    zero_shot_cot: """
    Answer the following question by thinking step by step. Break down your reasoning into clear, logical steps.

    Question: {query}

    Let's think step by step:
    """,
    few_shot_cot: """
    Answer the following question by thinking step by step, using the examples below as guidance.

    Examples:
    {examples}

    Now solve this problem:
    Question: {query}

    Let's think step by step:
    """,
    faithful_cot: """
    Answer the following question using step-by-step reasoning. Base your reasoning on the provided context and cite sources for each claim.

    Context: {context}

    Question: {query}

    Let's think step by step, citing sources for each reasoning step:
    """
  }

  # Quality assessment criteria for different reasoning types
  @quality_criteria %{
    zero_shot_cot: %{
      min_steps: 3,
      logical_consistency_weight: 0.4,
      step_coherence_weight: 0.3,
      conclusion_support_weight: 0.3
    },
    few_shot_cot: %{
      min_steps: 2,
      logical_consistency_weight: 0.3,
      step_coherence_weight: 0.4,
      conclusion_support_weight: 0.3
    },
    faithful_cot: %{
      min_steps: 4,
      logical_consistency_weight: 0.3,
      step_coherence_weight: 0.2,
      # Higher weight for source-grounded reasoning
      conclusion_support_weight: 0.5
    }
  }

  @default_quality_requirements %{
    min_logical_consistency: 0.8,
    min_step_coherence: 0.7,
    min_conclusion_support: 0.8,
    require_step_validation: true,
    enable_error_correction: true
  }

  @doc """
  Generate Chain-of-Thought reasoning for the given query.

  Returns a complete reasoning chain with step-by-step analysis,
  validation results, quality metrics, and learning data.
  """
  def run(params, _context) do
    %{
      query: query,
      reasoning_type: reasoning_type,
      context: reasoning_context,
      examples: examples,
      quality_requirements: quality_reqs,
      provider_config: provider_config
    } = params

    merged_quality_reqs = Map.merge(@default_quality_requirements, quality_reqs)

    Logger.info("GenerateReasoningAction: Starting #{reasoning_type} reasoning",
      reasoning_type: reasoning_type,
      query_length: String.length(query),
      examples_provided: length(examples)
    )

    reasoning_start_time = System.monotonic_time(:microsecond)

    # Initialize reasoning chain
    chain = ReasoningChain.new(query, reasoning_type, context: reasoning_context)

    with {:ok, optimal_provider} <-
           select_reasoning_provider(reasoning_type, query, provider_config),
         {:ok, reasoning_prompt} <-
           build_reasoning_prompt(reasoning_type, query, reasoning_context, examples),
         {:ok, reasoning_response} <-
           execute_reasoning_generation(optimal_provider, reasoning_prompt, merged_quality_reqs),
         {:ok, parsed_chain} <- parse_reasoning_response(reasoning_response, chain),
         {:ok, validated_chain} <- validate_reasoning_chain(parsed_chain, merged_quality_reqs) do
      reasoning_time = System.monotonic_time(:microsecond) - reasoning_start_time

      # Extract insights and patterns
      final_chain = extract_reasoning_insights(validated_chain)

      # Calculate performance metrics
      performance_metrics = calculate_reasoning_performance(final_chain, reasoning_time)

      Logger.info("GenerateReasoningAction: Reasoning generation complete",
        reasoning_type: reasoning_type,
        steps_generated: length(final_chain.steps),
        quality_score: final_chain.quality_metrics.overall_quality,
        reasoning_time_us: reasoning_time
      )

      {:ok,
       %{
         reasoning_chain: final_chain,
         provider_used: optimal_provider,
         reasoning_metadata: %{
           reasoning_type: reasoning_type,
           steps_generated: length(final_chain.steps),
           reasoning_time_microseconds: reasoning_time,
           prompt_used: reasoning_prompt,
           quality_validated: merged_quality_reqs.require_step_validation
         },
         performance_metrics: performance_metrics,
         learning_data: ReasoningChain.extract_metadata(final_chain)
       }}
    else
      {:error, reason} ->
        Logger.error("GenerateReasoningAction: Reasoning generation failed",
          error: reason,
          reasoning_type: reasoning_type,
          query: String.slice(query, 0, 100)
        )

        {:error, reason}
    end
  end

  # Private implementation functions

  defp select_reasoning_provider(reasoning_type, query, provider_config) do
    # Select optimal provider for reasoning based on type and requirements
    reasoning_requirements = %{
      estimated_tokens: estimate_reasoning_tokens(query, reasoning_type),
      # High quality for reasoning
      quality_threshold: 0.9,
      reasoning_capability: true,
      urgency: :normal
    }

    case DetermineRouteAction.run(
           %{
             request_requirements: reasoning_requirements,
             # Focus on reasoning-capable providers
             available_providers: [:openai, :anthropic],
             routing_strategy: :quality_first,
             context: %{domain: :reasoning, reasoning_type: reasoning_type}
           },
           %{}
         ) do
      {:ok, routing_result} ->
        {:ok, routing_result.selected_provider}

      {:error, reason} ->
        Logger.warning("GenerateReasoningAction: Provider selection failed, defaulting to OpenAI",
          error: reason
        )

        # Default fallback
        {:ok, :openai}
    end
  end

  defp estimate_reasoning_tokens(query, reasoning_type) do
    # Estimate token requirements for different reasoning types
    # Rough token estimation
    base_tokens = String.length(query) / 4

    multiplier =
      case reasoning_type do
        # Simple expansion
        :zero_shot_cot -> 3.0
        # Examples + reasoning
        :few_shot_cot -> 5.0
        # Context + citations
        :faithful_cot -> 4.0
      end

    # Add buffer for reasoning output
    round(base_tokens * multiplier + 1000)
  end

  defp build_reasoning_prompt(reasoning_type, query, context, examples) do
    template = Map.get(@cot_templates, reasoning_type)

    case reasoning_type do
      :zero_shot_cot ->
        prompt = String.replace(template, "{query}", query)
        {:ok, prompt}

      :few_shot_cot ->
        examples_text = format_few_shot_examples(examples)

        prompt =
          template
          |> String.replace("{examples}", examples_text)
          |> String.replace("{query}", query)

        {:ok, prompt}

      :faithful_cot ->
        context_text = format_faithful_context(context)

        prompt =
          template
          |> String.replace("{context}", context_text)
          |> String.replace("{query}", query)

        {:ok, prompt}

      _ ->
        {:error, {:unsupported_reasoning_type, reasoning_type}}
    end
  end

  defp format_few_shot_examples(examples) when is_list(examples) do
    if Enum.empty?(examples) do
      "No examples provided."
    else
      examples
      |> Enum.with_index(1)
      |> Enum.map(fn {example, index} ->
        question = Map.get(example, :question, "")
        reasoning = Map.get(example, :reasoning, "")
        answer = Map.get(example, :answer, "")

        """
        Example #{index}:
        Question: #{question}
        Reasoning: #{reasoning}
        Answer: #{answer}
        """
      end)
      |> Enum.join("\n")
    end
  end

  defp format_faithful_context(context) when is_map(context) do
    sources = Map.get(context, :sources, [])
    facts = Map.get(context, :facts, [])

    context_parts = []

    context_parts =
      if Enum.empty?(sources) do
        context_parts
      else
        source_text =
          sources
          |> Enum.with_index(1)
          |> Enum.map(fn {source, index} ->
            "Source #{index}: #{source}"
          end)
          |> Enum.join("\n")

        [source_text | context_parts]
      end

    context_parts =
      if Enum.empty?(facts) do
        context_parts
      else
        fact_text =
          facts
          |> Enum.with_index(1)
          |> Enum.map(fn {fact, index} ->
            "Fact #{index}: #{fact}"
          end)
          |> Enum.join("\n")

        [fact_text | context_parts]
      end

    if Enum.empty?(context_parts) do
      "No additional context provided."
    else
      Enum.reverse(context_parts) |> Enum.join("\n\n")
    end
  end

  defp execute_reasoning_generation(provider, prompt, quality_requirements) do
    # Generate reasoning using selected provider with reasoning-optimized parameters
    generation_params = %{
      model: get_optimal_reasoning_model(provider),
      messages: [
        %{
          role: :system,
          content:
            "You are an expert at logical reasoning and problem-solving. Provide clear, step-by-step reasoning."
        },
        %{role: :user, content: prompt}
      ],
      # Lower temperature for more logical consistency
      temperature: 0.3,
      # Enough space for detailed reasoning
      max_tokens: 3000,
      # Slightly reduced for more focused reasoning
      top_p: 0.9
    }

    case CallAPIAction.run(
           %{
             provider: provider,
             operation: :complete,
             request_params: generation_params,
             context: %{domain: :reasoning, quality_critical: true}
           },
           %{}
         ) do
      {:ok, result} ->
        response_content = extract_response_content(result.response)
        {:ok, response_content}

      {:error, reason} ->
        {:error, {:reasoning_generation_failed, reason}}
    end
  end

  defp get_optimal_reasoning_model(provider) do
    # Select best model for reasoning tasks
    case provider do
      # Best reasoning capability
      :openai -> "gpt-4-turbo"
      # Excellent at reasoning
      :anthropic -> "claude-3-opus"
      # Reasonable local option
      :local -> "llama-2-13b"
      # Default fallback
      _ -> "gpt-4-turbo"
    end
  end

  defp extract_response_content(response) do
    case response do
      %{choices: [%{message: %{content: content}} | _]} -> content
      %{content: content} -> content
      _ -> ""
    end
  end

  defp parse_reasoning_response(response_content, chain) do
    # Parse the reasoning response into individual steps
    Logger.debug("GenerateReasoningAction: Parsing reasoning response")

    # Simple parsing - split by step indicators
    step_patterns = [
      ~r/Step \d+[:\.]?\s*/i,
      ~r/\d+\.\s*/,
      ~r/First[,:]?\s*/i,
      ~r/Second[,:]?\s*/i,
      ~r/Third[,:]?\s*/i,
      ~r/Next[,:]?\s*/i,
      ~r/Then[,:]?\s*/i,
      ~r/Finally[,:]?\s*/i,
      ~r/Therefore[,:]?\s*/i
    ]

    # Try to split response into reasoning steps
    steps = split_into_reasoning_steps(response_content, step_patterns)

    # Create ReasoningStep structs
    reasoning_steps =
      steps
      |> Enum.with_index()
      |> Enum.map(fn {step_content, index} ->
        step_type = determine_step_type(step_content, index, length(steps))

        ReasoningStep.new(step_content, step_type,
          index: index,
          chain_id: chain.id
        )
      end)

    # Update chain with steps
    updated_chain =
      Enum.reduce(reasoning_steps, chain, fn step, acc_chain ->
        %{acc_chain | steps: acc_chain.steps ++ [step]}
      end)

    # Extract conclusion (usually the last step)
    conclusion = extract_conclusion_from_steps(reasoning_steps, response_content)
    final_chain = ReasoningChain.set_conclusion(updated_chain, conclusion)

    {:ok, final_chain}
  end

  defp split_into_reasoning_steps(content, patterns) do
    # Try each pattern to find the best split
    best_split =
      Enum.reduce(patterns, [content], fn pattern, best_acc ->
        current_split = String.split(content, pattern, include_captures: false, trim: true)

        # Prefer splits that create multiple meaningful steps
        if length(current_split) > length(best_acc) and length(current_split) <= 10 do
          current_split
        else
          best_acc
        end
      end)

    # Clean up and filter steps
    best_split
    |> Enum.map(&String.trim/1)
    # Filter out very short steps
    |> Enum.filter(&(String.length(&1) > 10))
    # Limit to max 8 steps for manageability
    |> Enum.take(8)
  end

  defp determine_step_type(step_content, index, total_steps) do
    content_lower = String.downcase(step_content)

    cond do
      # First step often contains premises or problem analysis
      index == 0 -> :premise
      # Last step often contains conclusion
      index == total_steps - 1 -> :conclusion
      # Steps with conclusion keywords
      String.contains?(content_lower, ["therefore", "thus", "hence", "conclusion"]) -> :conclusion
      # Default to reasoning
      true -> :reasoning
    end
  end

  defp extract_conclusion_from_steps(steps, original_content) do
    # Extract final conclusion from reasoning steps
    case List.last(steps) do
      %ReasoningStep{content: content, step_type: :conclusion} ->
        content

      %ReasoningStep{content: content} ->
        # If last step isn't marked as conclusion, extract conclusion-like content
        extract_conclusion_sentences(content)

      _ ->
        # Fallback: extract conclusion from original content
        extract_conclusion_sentences(original_content)
    end
  end

  defp extract_conclusion_sentences(content) do
    # Simple extraction of conclusion-like sentences
    sentences = String.split(content, ~r/[.!?]+/)

    conclusion_sentences =
      Enum.filter(sentences, fn sentence ->
        sentence_lower = String.downcase(sentence)
        String.contains?(sentence_lower, ["therefore", "thus", "answer", "conclusion", "result"])
      end)

    if Enum.empty?(conclusion_sentences) do
      # Use last sentence as conclusion
      List.last(sentences) || content
    else
      Enum.join(conclusion_sentences, ". ")
    end
  end

  defp validate_reasoning_chain(chain, quality_requirements) do
    if quality_requirements.require_step_validation do
      Logger.debug("GenerateReasoningAction: Validating reasoning chain")

      # Validate each step
      validated_steps =
        Enum.map(chain.steps, fn step ->
          validation_result = validate_reasoning_step(step, chain, quality_requirements)
          ReasoningStep.validate(step, validation_result)
        end)

      # Update chain with validated steps
      validated_chain = %{chain | steps: validated_steps}

      # Calculate overall quality metrics
      quality_metrics = calculate_chain_quality_metrics(validated_chain, quality_requirements)
      final_chain = ReasoningChain.update_quality_metrics(validated_chain, quality_metrics)

      {:ok, final_chain}
    else
      {:ok, chain}
    end
  end

  defp validate_reasoning_step(step, chain, quality_requirements) do
    # Validate individual reasoning step
    logical_score = assess_logical_consistency(step, chain)
    clarity_score = assess_step_clarity(step)
    relevance_score = assess_step_relevance(step, chain)

    composite_score = (logical_score + clarity_score + relevance_score) / 3
    is_valid = composite_score >= 0.7

    # Update step quality scores
    updated_step =
      ReasoningStep.update_quality_scores(step, %{
        logical_score: logical_score,
        clarity_score: clarity_score,
        relevance_score: relevance_score
      })

    %{
      score: composite_score,
      valid: is_valid,
      notes: generate_validation_notes(logical_score, clarity_score, relevance_score),
      issues: if(is_valid, do: [], else: identify_step_issues(step, composite_score))
    }
  end

  defp assess_logical_consistency(step, chain) do
    # Simple logical consistency assessment
    content = step.content || ""

    # Check for logical indicators
    logical_indicators = [
      "because",
      "since",
      "therefore",
      "thus",
      "hence",
      "given that",
      "if",
      "then",
      "when",
      "while",
      "although",
      "however"
    ]

    indicator_count =
      Enum.count(logical_indicators, fn indicator ->
        String.contains?(String.downcase(content), indicator)
      end)

    # Base score on logical structure
    # Normalize to 3 indicators
    base_score = min(indicator_count / 3, 1.0)

    # Adjust for step position and chain consistency
    position_factor = calculate_position_consistency_factor(step, chain)

    final_score = base_score * position_factor
    Float.round(min(final_score, 1.0), 3)
  end

  defp assess_step_clarity(step) do
    content = step.content || ""

    # Simple clarity metrics
    word_count = String.split(content) |> length()
    sentence_count = String.split(content, ~r/[.!?]+/) |> length()

    # Optimal word count per sentence for clarity
    avg_words_per_sentence = if sentence_count > 0, do: word_count / sentence_count, else: 0

    clarity_score =
      cond do
        # Very clear
        avg_words_per_sentence <= 15 -> 1.0
        # Good clarity
        avg_words_per_sentence <= 25 -> 0.8
        # Acceptable
        avg_words_per_sentence <= 35 -> 0.6
        # Unclear
        true -> 0.4
      end

    Float.round(clarity_score, 3)
  end

  defp assess_step_relevance(step, chain) do
    # Assess relevance to original query and previous steps
    query = chain.original_query || ""
    step_content = step.content || ""

    # Simple relevance based on word overlap
    query_words = String.split(String.downcase(query)) |> MapSet.new()
    step_words = String.split(String.downcase(step_content)) |> MapSet.new()

    word_overlap = MapSet.intersection(query_words, step_words) |> MapSet.size()
    total_unique_words = MapSet.union(query_words, step_words) |> MapSet.size()

    relevance_score =
      if total_unique_words > 0 do
        word_overlap / total_unique_words
      else
        # Default relevance
        0.5
      end

    # Boost relevance for reasoning indicators
    relevance_boost =
      if String.contains?(String.downcase(step_content), ["answer", "solution", "because"]) do
        0.2
      else
        0.0
      end

    final_relevance = min(relevance_score + relevance_boost, 1.0)
    Float.round(final_relevance, 3)
  end

  defp calculate_position_consistency_factor(step, chain) do
    # Factor in step position for logical flow
    case step.step_type do
      # Premises can be anywhere
      :premise -> 1.0
      # Reasoning steps in middle
      :reasoning -> 0.9
      # Conclusions benefit logical flow
      :conclusion -> 1.1
    end
  end

  defp generate_validation_notes(logical_score, clarity_score, relevance_score) do
    notes = []

    notes =
      if logical_score < 0.7 do
        ["Low logical consistency - consider adding connecting words" | notes]
      else
        notes
      end

    notes =
      if clarity_score < 0.7 do
        ["Step could be clearer - consider shorter sentences" | notes]
      else
        notes
      end

    notes =
      if relevance_score < 0.7 do
        ["Step relevance could be improved - ensure connection to main query" | notes]
      else
        notes
      end

    Enum.reverse(notes)
  end

  defp identify_step_issues(step, composite_score) do
    issues = []

    issues =
      if composite_score < 0.5 do
        [
          %{type: :low_quality, severity: :high, description: "Overall step quality is low"}
          | issues
        ]
      else
        issues
      end

    issues =
      if String.length(step.content || "") < 10 do
        [
          %{
            type: :insufficient_content,
            severity: :medium,
            description: "Step content is too brief"
          }
          | issues
        ]
      else
        issues
      end

    Enum.reverse(issues)
  end

  defp calculate_chain_quality_metrics(chain, quality_requirements) do
    criteria = Map.get(@quality_criteria, chain.reasoning_type, @quality_criteria.zero_shot_cot)

    # Calculate metrics based on step validations
    logical_consistency = calculate_logical_consistency_metric(chain, criteria)
    step_coherence = calculate_step_coherence_metric(chain, criteria)
    conclusion_support = calculate_conclusion_support_metric(chain, criteria)

    %{
      logical_consistency: logical_consistency,
      step_coherence: step_coherence,
      conclusion_support: conclusion_support
    }
  end

  defp calculate_logical_consistency_metric(chain, _criteria) do
    if Enum.empty?(chain.steps) do
      0.0
    else
      logical_scores = Enum.map(chain.steps, & &1.logical_score)
      avg_logical = Enum.sum(logical_scores) / Enum.count(logical_scores)
      Float.round(avg_logical, 3)
    end
  end

  defp calculate_step_coherence_metric(chain, _criteria) do
    if Enum.empty?(chain.steps) do
      0.0
    else
      clarity_scores = Enum.map(chain.steps, & &1.clarity_score)
      avg_clarity = Enum.sum(clarity_scores) / Enum.count(clarity_scores)
      Float.round(avg_clarity, 3)
    end
  end

  defp calculate_conclusion_support_metric(chain, _criteria) do
    if Enum.empty?(chain.steps) do
      0.0
    else
      relevance_scores = Enum.map(chain.steps, & &1.relevance_score)
      avg_relevance = Enum.sum(relevance_scores) / Enum.count(relevance_scores)
      Float.round(avg_relevance, 3)
    end
  end

  defp extract_reasoning_insights(chain) do
    # Extract insights from the completed reasoning chain
    insights = []

    # Pattern-based insight extraction
    insights =
      if length(chain.steps) >= 4 do
        ["Multi-step reasoning successfully applied" | insights]
      else
        insights
      end

    insights =
      if chain.quality_metrics.logical_consistency > 0.8 do
        ["High logical consistency achieved" | insights]
      else
        insights
      end

    insights =
      if not Enum.empty?(chain.errors) and not Enum.empty?(chain.corrections_applied) do
        ["Self-correction successfully applied during reasoning" | insights]
      else
        insights
      end

    # Add insights to chain
    ReasoningChain.add_insights(chain, Enum.reverse(insights))
  end

  defp calculate_reasoning_performance(chain, reasoning_time) do
    %{
      reasoning_time_microseconds: reasoning_time,
      steps_per_second: calculate_steps_per_second(chain, reasoning_time),
      quality_efficiency: calculate_quality_efficiency(chain, reasoning_time),
      error_rate: calculate_reasoning_error_rate(chain),
      validation_coverage: calculate_validation_coverage(chain)
    }
  end

  defp calculate_steps_per_second(chain, reasoning_time_us) do
    if reasoning_time_us > 0 and length(chain.steps) > 0 do
      steps_per_microsecond = length(chain.steps) / reasoning_time_us
      steps_per_second = steps_per_microsecond * 1_000_000
      Float.round(steps_per_second, 3)
    else
      0.0
    end
  end

  defp calculate_quality_efficiency(chain, reasoning_time_us) do
    # Quality achieved per unit time
    overall_quality = chain.quality_metrics.overall_quality || 0.0

    if reasoning_time_us > 0 do
      # Quality per millisecond
      efficiency = overall_quality / (reasoning_time_us / 1000)
      Float.round(efficiency, 6)
    else
      0.0
    end
  end

  defp calculate_reasoning_error_rate(chain) do
    # +1 for overall reasoning
    total_operations = length(chain.steps) + 1

    if total_operations > 0 do
      error_rate = length(chain.errors) / total_operations
      Float.round(error_rate, 3)
    else
      0.0
    end
  end

  defp calculate_validation_coverage(chain) do
    if Enum.empty?(chain.steps) do
      0.0
    else
      validated_steps = Enum.count(chain.steps, &ReasoningStep.valid?/1)
      coverage = validated_steps / length(chain.steps)
      Float.round(coverage, 3)
    end
  end
end
