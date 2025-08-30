defmodule RubberDuck.Reasoning.ReasoningChain do
  @moduledoc """
  Core reasoning chain structure for Chain-of-Thought processing.

  This module defines the data structure and operations for managing
  step-by-step reasoning chains used in Chain-of-Thought (CoT) processing,
  with support for validation, error detection, and quality assessment.

  Reasoning Chain Features:
  - Step-by-step logical progression with validation
  - Error detection and correction tracking
  - Quality assessment with confidence scoring
  - Insight extraction and pattern recognition
  - Integration with learning and improvement systems
  """

  alias RubberDuck.Reasoning.ReasoningStep

  @type reasoning_type :: :zero_shot_cot | :few_shot_cot | :faithful_cot | :custom

  @type validation_result :: %{
          valid: boolean(),
          confidence_score: float(),
          issues: [map()],
          suggestions: [binary()]
        }

  @type quality_metrics :: %{
          logical_consistency: float(),
          step_coherence: float(),
          conclusion_support: float(),
          overall_quality: float()
        }

  defstruct [
    # Chain identification
    id: nil,
    reasoning_type: :zero_shot_cot,

    # Input and context
    original_query: nil,
    context: %{},

    # Reasoning steps
    steps: [],
    current_step_index: 0,

    # Validation and quality
    validation_results: [],
    quality_metrics: %{},

    # Final output
    conclusion: nil,
    confidence_score: 0.0,

    # Metadata and tracking
    created_at: nil,
    completed_at: nil,
    processing_time_ms: 0,
    provider_used: nil,
    model_used: nil,

    # Error tracking
    errors: [],
    corrections_applied: [],

    # Learning data
    insights_extracted: [],
    patterns_identified: []
  ]

  @type t :: %__MODULE__{
          id: binary() | nil,
          reasoning_type: reasoning_type(),
          original_query: binary() | nil,
          context: map(),
          steps: [ReasoningStep.t()],
          current_step_index: non_neg_integer(),
          validation_results: [validation_result()],
          quality_metrics: quality_metrics(),
          conclusion: binary() | nil,
          confidence_score: float(),
          created_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          processing_time_ms: non_neg_integer(),
          provider_used: atom() | nil,
          model_used: binary() | nil,
          errors: [map()],
          corrections_applied: [map()],
          insights_extracted: [map()],
          patterns_identified: [map()]
        }

  @doc """
  Create a new reasoning chain for the given query and type.
  """
  def new(query, reasoning_type \\ :zero_shot_cot, opts \\ []) do
    %__MODULE__{
      id: generate_chain_id(),
      reasoning_type: reasoning_type,
      original_query: query,
      context: Keyword.get(opts, :context, %{}),
      created_at: DateTime.utc_now(),
      steps: [],
      current_step_index: 0,
      validation_results: [],
      quality_metrics: %{
        logical_consistency: 0.0,
        step_coherence: 0.0,
        conclusion_support: 0.0,
        overall_quality: 0.0
      },
      confidence_score: 0.0,
      errors: [],
      corrections_applied: [],
      insights_extracted: [],
      patterns_identified: []
    }
  end

  @doc """
  Add a reasoning step to the chain.
  """
  def add_step(chain, step_content, step_type \\ :reasoning) do
    step =
      ReasoningStep.new(step_content, step_type, %{
        index: chain.current_step_index,
        chain_id: chain.id
      })

    %{chain | steps: chain.steps ++ [step], current_step_index: chain.current_step_index + 1}
  end

  @doc """
  Add validation result for a specific step or the entire chain.
  """
  def add_validation(chain, validation_result) do
    %{chain | validation_results: [validation_result | chain.validation_results]}
  end

  @doc """
  Set the final conclusion for the reasoning chain.
  """
  def set_conclusion(chain, conclusion, confidence_score \\ 0.8) do
    %{
      chain
      | conclusion: conclusion,
        confidence_score: confidence_score,
        completed_at: DateTime.utc_now(),
        processing_time_ms: calculate_processing_time(chain)
    }
  end

  @doc """
  Add error information to the reasoning chain.
  """
  def add_error(chain, error) when is_map(error) do
    error_entry =
      Map.merge(error, %{
        timestamp: DateTime.utc_now(),
        step_index: chain.current_step_index
      })

    %{chain | errors: [error_entry | chain.errors]}
  end

  def add_error(chain, error) when is_atom(error) or is_binary(error) do
    add_error(chain, %{error: error, type: :general})
  end

  @doc """
  Add correction information to the reasoning chain.
  """
  def add_correction(chain, correction) do
    correction_entry =
      Map.merge(correction, %{
        timestamp: DateTime.utc_now(),
        step_index: chain.current_step_index
      })

    %{chain | corrections_applied: [correction_entry | chain.corrections_applied]}
  end

  @doc """
  Update quality metrics for the reasoning chain.
  """
  def update_quality_metrics(chain, metrics) do
    updated_metrics = Map.merge(chain.quality_metrics, metrics)

    # Calculate overall quality score
    overall_quality = calculate_overall_quality(updated_metrics)
    final_metrics = Map.put(updated_metrics, :overall_quality, overall_quality)

    %{chain | quality_metrics: final_metrics}
  end

  @doc """
  Add insights extracted from the reasoning process.
  """
  def add_insights(chain, insights) when is_list(insights) do
    insight_entries =
      Enum.map(insights, fn insight ->
        %{
          insight: insight,
          extracted_at: DateTime.utc_now(),
          step_index: chain.current_step_index
        }
      end)

    %{chain | insights_extracted: insight_entries ++ chain.insights_extracted}
  end

  def add_insights(chain, insight) when is_binary(insight) do
    add_insights(chain, [insight])
  end

  @doc """
  Add patterns identified during reasoning.
  """
  def add_patterns(chain, patterns) when is_list(patterns) do
    pattern_entries =
      Enum.map(patterns, fn pattern ->
        %{
          pattern: pattern,
          identified_at: DateTime.utc_now(),
          confidence: Map.get(pattern, :confidence, 0.8)
        }
      end)

    %{chain | patterns_identified: pattern_entries ++ chain.patterns_identified}
  end

  @doc """
  Check if the reasoning chain is complete.
  """
  def complete?(chain) do
    not is_nil(chain.conclusion) and not is_nil(chain.completed_at)
  end

  @doc """
  Check if the reasoning chain has errors.
  """
  def has_errors?(chain) do
    not Enum.empty?(chain.errors)
  end

  @doc """
  Get the current reasoning step.
  """
  def current_step(chain) do
    if chain.current_step_index > 0 and chain.current_step_index <= length(chain.steps) do
      Enum.at(chain.steps, chain.current_step_index - 1)
    else
      nil
    end
  end

  @doc """
  Get all validation issues for the chain.
  """
  def validation_issues(chain) do
    chain.validation_results
    |> Enum.flat_map(&Map.get(&1, :issues, []))
  end

  @doc """
  Calculate chain progress as a percentage (0.0 to 1.0).
  """
  def progress(chain) do
    if complete?(chain) do
      1.0
    else
      # Estimate progress based on steps and validation
      # Assume 5 steps average
      step_progress = min(length(chain.steps) / 5, 0.8)
      validation_progress = if Enum.empty?(chain.validation_results), do: 0.0, else: 0.1
      conclusion_progress = if is_nil(chain.conclusion), do: 0.0, else: 0.1

      step_progress + validation_progress + conclusion_progress
    end
  end

  @doc """
  Extract comprehensive metadata for learning and analysis.
  """
  def extract_metadata(chain) do
    %{
      reasoning_performance: %{
        total_steps: length(chain.steps),
        processing_time_ms: chain.processing_time_ms,
        completion_rate: if(complete?(chain), do: 1.0, else: progress(chain))
      },
      quality_assessment: chain.quality_metrics,
      validation_summary: %{
        validations_performed: length(chain.validation_results),
        total_issues: length(validation_issues(chain)),
        avg_confidence: calculate_avg_validation_confidence(chain)
      },
      error_analysis: %{
        error_count: length(chain.errors),
        correction_count: length(chain.corrections_applied),
        error_rate: calculate_error_rate(chain)
      },
      learning_data: %{
        insights_count: length(chain.insights_extracted),
        patterns_count: length(chain.patterns_identified),
        learning_value: assess_learning_value(chain)
      },
      provider_usage: %{
        provider: chain.provider_used,
        model: chain.model_used
      }
    }
  end

  # Private helper functions

  defp generate_chain_id do
    # Generate unique ID for reasoning chain
    timestamp = System.system_time(:nanosecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "chain_#{timestamp}_#{random}"
  end

  defp calculate_processing_time(chain) do
    if chain.created_at and chain.completed_at do
      DateTime.diff(chain.completed_at, chain.created_at, :millisecond)
    else
      0
    end
  end

  defp calculate_overall_quality(metrics) do
    # Weighted average of quality dimensions
    logical = Map.get(metrics, :logical_consistency, 0.0)
    coherence = Map.get(metrics, :step_coherence, 0.0)
    support = Map.get(metrics, :conclusion_support, 0.0)

    # Weighted combination
    overall = logical * 0.4 + coherence * 0.3 + support * 0.3
    Float.round(overall, 3)
  end

  defp calculate_avg_validation_confidence(chain) do
    if Enum.empty?(chain.validation_results) do
      0.0
    else
      confidences = Enum.map(chain.validation_results, &Map.get(&1, :confidence_score, 0.0))
      avg = Enum.sum(confidences) / Enum.count(confidences)
      Float.round(avg, 3)
    end
  end

  defp calculate_error_rate(chain) do
    # +1 for conclusion
    total_operations = length(chain.steps) + length(chain.validation_results) + 1

    if total_operations > 0 do
      error_rate = length(chain.errors) / total_operations
      Float.round(error_rate, 3)
    else
      0.0
    end
  end

  defp assess_learning_value(chain) do
    # Assess how valuable this chain is for learning
    # Normalize to 3 insights
    insight_value = min(length(chain.insights_extracted) / 3, 1.0)
    # Normalize to 2 patterns
    pattern_value = min(length(chain.patterns_identified) / 2, 1.0)
    # Corrections are valuable
    error_learning_value = min(length(chain.corrections_applied) / 2, 1.0)

    # Weighted combination
    learning_value = insight_value * 0.4 + pattern_value * 0.4 + error_learning_value * 0.2
    Float.round(learning_value, 3)
  end
end
