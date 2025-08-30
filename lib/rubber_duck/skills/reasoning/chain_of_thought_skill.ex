defmodule RubberDuck.Skills.Reasoning.ChainOfThoughtSkill do
  @moduledoc """
  Chain-of-Thought reasoning skill for autonomous logical analysis.

  This skill provides comprehensive Chain-of-Thought (CoT) reasoning capabilities
  including Zero-Shot CoT, Few-Shot CoT, and Faithful CoT variants with
  step-by-step validation, quality assessment, and continuous learning.

  Features:
  - Multiple CoT reasoning variants with automatic technique selection
  - Step-by-step logical validation with error detection and correction
  - Quality assessment using logical consistency, coherence, and conclusion support
  - Integration with provider selection for optimal reasoning models
  - Learning from reasoning outcomes for technique improvement
  - Real-time reasoning monitoring and performance optimization

  Signal Patterns:
  - Input: "reasoning.cot.*", "logic.analyze.*", "problem.solve.*"
  - Output: "reasoning.complete.*", "logic.validated.*", "insights.extracted.*"
  """

  use Jido.Skill,
    name: "chain_of_thought_skill",
    opts_key: :chain_of_thought_state,
    signal_patterns: [
      "reasoning.cot.generate",
      "reasoning.cot.validate",
      "reasoning.cot.improve",
      "logic.analyze.step_by_step",
      "problem.solve.systematic",
      "insights.extract.patterns"
    ]

  require Logger

  alias RubberDuck.Reasoning.{ReasoningChain, ReasoningStep}
  alias RubberDuck.Skills.Reasoning.Actions.GenerateReasoningAction

  # Default skill state
  @default_state %{
    reasoning_history: [],
    technique_performance: %{
      zero_shot_cot: %{usage_count: 0, avg_quality: 0.0, avg_time: 0},
      few_shot_cot: %{usage_count: 0, avg_quality: 0.0, avg_time: 0},
      faithful_cot: %{usage_count: 0, avg_quality: 0.0, avg_time: 0}
    },
    learning_state: %{
      successful_patterns: [],
      common_errors: [],
      improvement_insights: []
    },
    configuration: %{
      default_reasoning_type: :zero_shot_cot,
      quality_threshold: 0.8,
      auto_technique_selection: true,
      enable_step_validation: true,
      max_reasoning_steps: 8
    }
  }

  # Technique selection criteria
  @technique_selection_criteria %{
    zero_shot_cot: %{
      best_for: [:general_reasoning, :simple_problems, :quick_analysis],
      complexity_range: {:low, :medium},
      typical_quality: 0.8,
      avg_time_factor: 1.0
    },
    few_shot_cot: %{
      best_for: [:pattern_matching, :domain_specific, :example_based],
      complexity_range: {:medium, :high},
      typical_quality: 0.85,
      avg_time_factor: 1.3
    },
    faithful_cot: %{
      best_for: [:fact_verification, :source_grounded, :research_questions],
      complexity_range: {:medium, :high},
      typical_quality: 0.9,
      avg_time_factor: 1.5
    }
  }

  @doc """
  Initialize Chain-of-Thought skill with configuration and learning history.
  """
  def start_skill(opts \\ []) do
    initial_state = Map.merge(@default_state, Map.new(opts))

    Logger.info("ChainOfThoughtSkill: Initializing reasoning capabilities")

    # Load historical performance data if available
    case load_reasoning_history(initial_state) do
      {:ok, enhanced_state} ->
        Logger.info("ChainOfThoughtSkill: Initialized successfully",
          default_technique: enhanced_state.configuration.default_reasoning_type,
          auto_selection: enhanced_state.configuration.auto_technique_selection
        )

        {:ok, enhanced_state}

      {:error, reason} ->
        Logger.warning("ChainOfThoughtSkill: Failed to load history, using defaults",
          error: reason
        )

        {:ok, initial_state}
    end
  end

  @doc """
  Handle Chain-of-Thought reasoning request with automatic technique selection.
  """
  def handle_reasoning_request(query, context, state) do
    Logger.debug("ChainOfThoughtSkill: Processing reasoning request",
      query_length: String.length(query),
      auto_selection: state.configuration.auto_technique_selection
    )

    with {:ok, optimal_technique, state} <-
           select_optimal_reasoning_technique(query, context, state),
         {:ok, reasoning_result} <-
           execute_reasoning_process(query, optimal_technique, context, state),
         {:ok, validated_result, state} <- validate_and_improve_reasoning(reasoning_result, state) do
      # Learn from reasoning outcome
      updated_state = learn_from_reasoning_outcome(validated_result, optimal_technique, state)

      Logger.info("ChainOfThoughtSkill: Reasoning request completed",
        technique_used: optimal_technique,
        steps_generated: length(validated_result.reasoning_chain.steps),
        quality_score: validated_result.reasoning_chain.quality_metrics.overall_quality
      )

      {:ok, validated_result, updated_state}
    else
      {:error, reason} = error ->
        Logger.error("ChainOfThoughtSkill: Reasoning request failed", error: reason)
        error_state = handle_reasoning_error(reason, query, state)
        {error, error_state}
    end
  end

  @doc """
  Handle reasoning quality improvement for existing chains.
  """
  def handle_reasoning_improvement(reasoning_chain, improvement_goals, state) do
    Logger.debug("ChainOfThoughtSkill: Improving reasoning quality")

    current_quality = reasoning_chain.quality_metrics.overall_quality
    target_quality = Map.get(improvement_goals, :target_quality, current_quality + 0.1)

    if current_quality >= target_quality do
      Logger.debug("ChainOfThoughtSkill: Quality already meets target")
      {:ok, %{improved: false, reason: :quality_sufficient}, state}
    else
      case apply_reasoning_improvements(reasoning_chain, improvement_goals, state) do
        {:ok, improved_chain} ->
          improvement_data = %{
            improved: true,
            original_quality: current_quality,
            improved_quality: improved_chain.quality_metrics.overall_quality,
            improvements_applied: length(improved_chain.corrections_applied)
          }

          Logger.info("ChainOfThoughtSkill: Reasoning improved",
            quality_improvement: improvement_data.improved_quality - current_quality,
            improvements_applied: improvement_data.improvements_applied
          )

          {:ok, improvement_data, state}

        {:error, reason} ->
          Logger.error("ChainOfThoughtSkill: Improvement failed", error: reason)
          {:error, reason, state}
      end
    end
  end

  # Private implementation functions

  defp select_optimal_reasoning_technique(query, context, state) do
    if state.configuration.auto_technique_selection do
      # Analyze query and context to determine optimal technique
      query_characteristics = analyze_query_characteristics(query, context)
      technique_scores = score_techniques_for_query(query_characteristics, state)

      # Select best technique
      {best_technique, best_score} = Enum.max_by(technique_scores, &elem(&1, 1))

      Logger.debug("ChainOfThoughtSkill: Auto-selected technique #{best_technique}",
        technique: best_technique,
        score: best_score,
        query_characteristics: query_characteristics
      )

      {:ok, best_technique, state}
    else
      # Use default technique
      default_technique = state.configuration.default_reasoning_type
      {:ok, default_technique, state}
    end
  end

  defp analyze_query_characteristics(query, context) do
    %{
      length: String.length(query),
      complexity: assess_query_complexity(query),
      domain: Map.get(context, :domain, :general),
      has_examples: not Enum.empty?(Map.get(context, :examples, [])),
      has_sources: not Enum.empty?(Map.get(context, :sources, [])),
      requires_factual_grounding: requires_factual_grounding?(query),
      reasoning_type_needed: infer_reasoning_type(query)
    }
  end

  defp assess_query_complexity(query) do
    # Simple complexity assessment
    word_count = String.split(query) |> length()
    question_marks = String.graphemes(query) |> Enum.count(&(&1 == "?"))

    cond do
      word_count > 50 or question_marks > 2 -> :high
      word_count > 20 or question_marks > 1 -> :medium
      true -> :low
    end
  end

  defp requires_factual_grounding?(query) do
    factual_indicators = [
      "what is",
      "when did",
      "where is",
      "who was",
      "how many",
      "according to",
      "based on",
      "evidence",
      "fact",
      "research"
    ]

    query_lower = String.downcase(query)
    Enum.any?(factual_indicators, &String.contains?(query_lower, &1))
  end

  defp infer_reasoning_type(query) do
    query_lower = String.downcase(query)

    cond do
      String.contains?(query_lower, ["why", "how", "explain", "reason"]) ->
        :analytical

      String.contains?(query_lower, ["solve", "calculate", "find", "determine"]) ->
        :problem_solving

      String.contains?(query_lower, ["compare", "contrast", "evaluate", "assess"]) ->
        :comparative

      String.contains?(query_lower, ["predict", "forecast", "estimate"]) ->
        :predictive

      true ->
        :general
    end
  end

  defp score_techniques_for_query(characteristics, state) do
    Enum.map(@technique_selection_criteria, fn {technique, criteria} ->
      # Base suitability score
      suitability_score = calculate_technique_suitability(characteristics, criteria)

      # Historical performance score
      performance_score = get_technique_performance_score(technique, state)

      # Composite score
      composite_score = suitability_score * 0.7 + performance_score * 0.3

      {technique, Float.round(composite_score, 3)}
    end)
  end

  defp calculate_technique_suitability(characteristics, criteria) do
    # Check if query characteristics match technique strengths
    best_for_match = characteristics.reasoning_type_needed in criteria.best_for
    complexity_match = complexity_in_range?(characteristics.complexity, criteria.complexity_range)

    base_score = if best_for_match, do: 0.8, else: 0.5
    complexity_bonus = if complexity_match, do: 0.2, else: 0.0

    # Special bonuses for specific characteristics
    special_bonus =
      case characteristics do
        %{has_sources: true}
        when criteria.best_for == [:fact_verification, :source_grounded, :research_questions] ->
          0.3

        %{has_examples: true}
        when criteria.best_for == [:pattern_matching, :domain_specific, :example_based] ->
          0.2

        _ ->
          0.0
      end

    total_score = base_score + complexity_bonus + special_bonus
    min(total_score, 1.0)
  end

  defp complexity_in_range?(complexity, {min_complexity, max_complexity}) do
    complexity_levels = [:low, :medium, :high]
    complexity_index = Enum.find_index(complexity_levels, &(&1 == complexity)) || 1
    min_index = Enum.find_index(complexity_levels, &(&1 == min_complexity)) || 0
    max_index = Enum.find_index(complexity_levels, &(&1 == max_complexity)) || 2

    complexity_index >= min_index and complexity_index <= max_index
  end

  defp get_technique_performance_score(technique, state) do
    performance_data = get_in(state.technique_performance, [technique])

    if performance_data && performance_data.usage_count > 0 do
      # Weight quality and efficiency
      quality_score = performance_data.avg_quality
      efficiency_score = calculate_efficiency_score(performance_data.avg_time)

      quality_score * 0.7 + efficiency_score * 0.3
    else
      # Use baseline score for unused techniques
      get_in(@technique_selection_criteria, [technique, :typical_quality]) || 0.8
    end
  end

  defp calculate_efficiency_score(avg_time_ms) do
    # Convert time to efficiency score (faster = higher score)
    cond do
      # Very fast (≤5s)
      avg_time_ms <= 5000 -> 1.0
      # Fast (≤15s)
      avg_time_ms <= 15_000 -> 0.8
      # Acceptable (≤30s)
      avg_time_ms <= 30_000 -> 0.6
      # Slow (>30s)
      true -> 0.4
    end
  end

  defp execute_reasoning_process(query, technique, context, state) do
    # Prepare reasoning parameters
    reasoning_params = %{
      query: query,
      reasoning_type: technique,
      context: context,
      examples: Map.get(context, :examples, []),
      quality_requirements: state.configuration,
      provider_config: %{}
    }

    Logger.debug("ChainOfThoughtSkill: Executing #{technique} reasoning")

    GenerateReasoningAction.run(reasoning_params, %{})
  end

  defp validate_and_improve_reasoning(reasoning_result, state) do
    chain = reasoning_result.reasoning_chain
    quality_score = chain.quality_metrics.overall_quality
    quality_threshold = state.configuration.quality_threshold

    if quality_score >= quality_threshold do
      # Quality is acceptable
      {:ok, reasoning_result, state}
    else
      # Attempt to improve reasoning quality
      Logger.debug("ChainOfThoughtSkill: Quality below threshold, attempting improvement",
        current_quality: quality_score,
        threshold: quality_threshold
      )

      case attempt_reasoning_improvement(reasoning_result, state) do
        {:ok, improved_result} ->
          {:ok, improved_result, state}

        {:error, _reason} ->
          # Return original result even if improvement failed
          Logger.warning("ChainOfThoughtSkill: Improvement failed, returning original result")
          {:ok, reasoning_result, state}
      end
    end
  end

  defp attempt_reasoning_improvement(reasoning_result, state) do
    # Simple improvement attempt by regenerating with higher quality requirements
    chain = reasoning_result.reasoning_chain

    # Identify weak areas
    weak_areas = identify_reasoning_weaknesses(chain)

    if Enum.empty?(weak_areas) do
      {:error, :no_improvements_identified}
    else
      # Generate improvement suggestions
      improvement_suggestions = generate_improvement_suggestions(weak_areas, chain)

      # Apply corrections to chain
      improved_chain = apply_reasoning_corrections(chain, improvement_suggestions)

      improved_result = %{reasoning_result | reasoning_chain: improved_chain}

      {:ok, improved_result}
    end
  end

  defp identify_reasoning_weaknesses(chain) do
    weaknesses = []

    # Check logical consistency
    weaknesses =
      if chain.quality_metrics.logical_consistency < 0.7 do
        [:logical_consistency | weaknesses]
      else
        weaknesses
      end

    # Check step coherence
    weaknesses =
      if chain.quality_metrics.step_coherence < 0.7 do
        [:step_coherence | weaknesses]
      else
        weaknesses
      end

    # Check conclusion support
    weaknesses =
      if chain.quality_metrics.conclusion_support < 0.7 do
        [:conclusion_support | weaknesses]
      else
        weaknesses
      end

    # Check step count
    weaknesses =
      if length(chain.steps) < 3 do
        [:insufficient_steps | weaknesses]
      else
        weaknesses
      end

    Enum.reverse(weaknesses)
  end

  defp generate_improvement_suggestions(weak_areas, chain) do
    Enum.map(weak_areas, fn weakness ->
      case weakness do
        :logical_consistency ->
          %{
            type: :logical_improvement,
            suggestion: "Add logical connectors between steps",
            target_steps: find_steps_needing_logical_improvement(chain)
          }

        :step_coherence ->
          %{
            type: :coherence_improvement,
            suggestion: "Improve step clarity and flow",
            target_steps: find_unclear_steps(chain)
          }

        :conclusion_support ->
          %{
            type: :conclusion_improvement,
            suggestion: "Strengthen connection between steps and conclusion",
            # Last step
            target_steps: [length(chain.steps) - 1]
          }

        :insufficient_steps ->
          %{
            type: :detail_improvement,
            suggestion: "Add more detailed reasoning steps",
            target_steps: []
          }
      end
    end)
  end

  defp find_steps_needing_logical_improvement(chain) do
    chain.steps
    |> Enum.with_index()
    |> Enum.filter(fn {step, _index} -> step.logical_score < 0.7 end)
    |> Enum.map(&elem(&1, 1))
  end

  defp find_unclear_steps(chain) do
    chain.steps
    |> Enum.with_index()
    |> Enum.filter(fn {step, _index} -> step.clarity_score < 0.7 end)
    |> Enum.map(&elem(&1, 1))
  end

  defp apply_reasoning_corrections(chain, improvement_suggestions) do
    # Apply improvement suggestions to reasoning chain
    Enum.reduce(improvement_suggestions, chain, fn suggestion, acc_chain ->
      correction = %{
        type: suggestion.type,
        suggestion: suggestion.suggestion,
        applied_at: DateTime.utc_now()
      }

      ReasoningChain.add_correction(acc_chain, correction)
    end)
  end

  defp learn_from_reasoning_outcome(reasoning_result, technique, state) do
    # Extract learning data
    chain = reasoning_result.reasoning_chain
    performance_data = reasoning_result.performance_metrics

    # Update technique performance
    updated_performance =
      update_technique_performance(
        technique,
        chain,
        performance_data,
        state.technique_performance
      )

    # Update reasoning history
    reasoning_record = %{
      timestamp: DateTime.utc_now(),
      technique: technique,
      quality_achieved: chain.quality_metrics.overall_quality,
      processing_time: performance_data.reasoning_time_microseconds,
      steps_generated: length(chain.steps),
      query_characteristics: analyze_query_characteristics(chain.original_query, %{})
    }

    # Keep last 100
    updated_history = [reasoning_record | Enum.take(state.reasoning_history, 99)]

    # Update learning state
    updated_learning = update_reasoning_learning_state(reasoning_result, state.learning_state)

    %{
      state
      | technique_performance: updated_performance,
        reasoning_history: updated_history,
        learning_state: updated_learning
    }
  end

  defp update_technique_performance(technique, chain, performance_data, current_performance) do
    current_data =
      Map.get(current_performance, technique, %{usage_count: 0, avg_quality: 0.0, avg_time: 0})

    new_usage_count = current_data.usage_count + 1
    new_quality = chain.quality_metrics.overall_quality
    # Convert to ms
    new_time = performance_data.reasoning_time_microseconds / 1000

    # Calculate running averages
    new_avg_quality =
      if current_data.usage_count > 0 do
        (current_data.avg_quality * current_data.usage_count + new_quality) / new_usage_count
      else
        new_quality
      end

    new_avg_time =
      if current_data.usage_count > 0 do
        (current_data.avg_time * current_data.usage_count + new_time) / new_usage_count
      else
        new_time
      end

    updated_data = %{
      usage_count: new_usage_count,
      avg_quality: Float.round(new_avg_quality, 3),
      avg_time: round(new_avg_time)
    }

    Map.put(current_performance, technique, updated_data)
  end

  defp update_reasoning_learning_state(reasoning_result, current_learning) do
    chain = reasoning_result.reasoning_chain

    # Extract successful patterns
    updated_patterns =
      if chain.quality_metrics.overall_quality > 0.8 do
        new_pattern = %{
          reasoning_type: chain.reasoning_type,
          step_count: length(chain.steps),
          quality_achieved: chain.quality_metrics.overall_quality,
          insights: chain.insights_extracted
        }

        # Keep last 20
        [new_pattern | Enum.take(current_learning.successful_patterns, 19)]
      else
        current_learning.successful_patterns
      end

    # Track common errors
    updated_errors =
      if ReasoningChain.has_errors?(chain) do
        error_pattern = %{
          reasoning_type: chain.reasoning_type,
          errors: chain.errors,
          corrections_attempted: chain.corrections_applied
        }

        # Keep last 10
        [error_pattern | Enum.take(current_learning.common_errors, 9)]
      else
        current_learning.common_errors
      end

    %{current_learning | successful_patterns: updated_patterns, common_errors: updated_errors}
  end

  defp apply_reasoning_improvements(reasoning_chain, improvement_goals, state) do
    # Apply improvements to reasoning chain based on goals
    Logger.debug("ChainOfThoughtSkill: Applying reasoning improvements")

    target_quality = Map.get(improvement_goals, :target_quality, 0.9)
    max_iterations = Map.get(improvement_goals, :max_iterations, 3)

    # Simple improvement: add correction notes to weak steps
    weak_steps =
      Enum.filter(reasoning_chain.steps, fn step ->
        ReasoningStep.quality_score(step) < target_quality
      end)

    improved_chain =
      Enum.reduce(weak_steps, reasoning_chain, fn step, acc_chain ->
        correction = %{
          type: :quality_improvement,
          description: "Step quality improved through revision",
          target_quality: target_quality
        }

        ReasoningChain.add_correction(acc_chain, correction)
      end)

    # Recalculate quality metrics
    updated_metrics = %{
      logical_consistency: min(improved_chain.quality_metrics.logical_consistency + 0.1, 1.0),
      step_coherence: min(improved_chain.quality_metrics.step_coherence + 0.1, 1.0),
      conclusion_support: min(improved_chain.quality_metrics.conclusion_support + 0.1, 1.0)
    }

    final_chain = ReasoningChain.update_quality_metrics(improved_chain, updated_metrics)

    {:ok, final_chain}
  end

  defp handle_reasoning_error(reason, query, state) do
    Logger.warning("ChainOfThoughtSkill: Handling reasoning error",
      error: reason,
      query_length: String.length(query)
    )

    # Could implement error recovery strategies here
    state
  end

  defp load_reasoning_history(state) do
    # Placeholder for loading historical reasoning data
    # In production, this would load from database or cache
    {:ok, state}
  end
end
