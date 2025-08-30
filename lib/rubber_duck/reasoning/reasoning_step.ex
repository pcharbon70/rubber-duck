defmodule RubberDuck.Reasoning.ReasoningStep do
  @moduledoc """
  Individual reasoning step structure for Chain-of-Thought processing.

  This module defines the structure and operations for individual reasoning steps
  within a reasoning chain, including validation, error tracking, and quality assessment.
  """

  @type step_type :: :premise | :reasoning | :conclusion | :validation | :correction

  @type validation_status :: :pending | :valid | :invalid | :corrected

  defstruct [
    # Step identification
    id: nil,
    index: 0,
    chain_id: nil,

    # Step content
    content: nil,
    step_type: :reasoning,

    # Validation
    validation_status: :pending,
    validation_score: 0.0,
    validation_notes: [],

    # Quality metrics
    logical_score: 0.0,
    clarity_score: 0.0,
    relevance_score: 0.0,

    # Dependencies and relationships
    depends_on: [],
    supports: [],

    # Error and correction tracking
    errors: [],
    corrections: [],

    # Metadata
    created_at: nil,
    processing_time_ms: 0,
    confidence: 0.8
  ]

  @type t :: %__MODULE__{
          id: binary() | nil,
          index: non_neg_integer(),
          chain_id: binary() | nil,
          content: binary() | nil,
          step_type: step_type(),
          validation_status: validation_status(),
          validation_score: float(),
          validation_notes: [binary()],
          logical_score: float(),
          clarity_score: float(),
          relevance_score: float(),
          depends_on: [non_neg_integer()],
          supports: [non_neg_integer()],
          errors: [map()],
          corrections: [map()],
          created_at: DateTime.t() | nil,
          processing_time_ms: non_neg_integer(),
          confidence: float()
        }

  @doc """
  Create a new reasoning step.
  """
  def new(content, step_type \\ :reasoning, opts \\ []) do
    %__MODULE__{
      id: generate_step_id(),
      content: content,
      step_type: step_type,
      index: Keyword.get(opts, :index, 0),
      chain_id: Keyword.get(opts, :chain_id),
      created_at: DateTime.utc_now(),
      validation_status: :pending,
      confidence: Keyword.get(opts, :confidence, 0.8),
      depends_on: Keyword.get(opts, :depends_on, []),
      supports: Keyword.get(opts, :supports, [])
    }
  end

  @doc """
  Validate the reasoning step and update validation status.
  """
  def validate(step, validation_result) do
    validation_score = Map.get(validation_result, :score, 0.0)
    # 70% threshold for validity
    is_valid = validation_score >= 0.7

    status =
      cond do
        is_valid -> :valid
        Map.get(validation_result, :corrected, false) -> :corrected
        true -> :invalid
      end

    %{
      step
      | validation_status: status,
        validation_score: validation_score,
        validation_notes: Map.get(validation_result, :notes, [])
    }
  end

  @doc """
  Update quality scores for the reasoning step.
  """
  def update_quality_scores(step, scores) do
    %{
      step
      | logical_score: Map.get(scores, :logical_score, step.logical_score),
        clarity_score: Map.get(scores, :clarity_score, step.clarity_score),
        relevance_score: Map.get(scores, :relevance_score, step.relevance_score)
    }
  end

  @doc """
  Add error to the reasoning step.
  """
  def add_error(step, error) when is_map(error) do
    error_entry =
      Map.merge(error, %{
        timestamp: DateTime.utc_now(),
        step_id: step.id
      })

    %{step | errors: [error_entry | step.errors]}
  end

  def add_error(step, error) when is_atom(error) or is_binary(error) do
    add_error(step, %{error: error, type: :general})
  end

  @doc """
  Add correction to the reasoning step.
  """
  def add_correction(step, correction) do
    correction_entry =
      Map.merge(correction, %{
        timestamp: DateTime.utc_now(),
        step_id: step.id
      })

    %{step | corrections: [correction_entry | step.corrections], validation_status: :corrected}
  end

  @doc """
  Check if the step is valid.
  """
  def valid?(step) do
    step.validation_status in [:valid, :corrected]
  end

  @doc """
  Check if the step has errors.
  """
  def has_errors?(step) do
    not Enum.empty?(step.errors)
  end

  @doc """
  Calculate composite quality score for the step.
  """
  def quality_score(step) do
    # Weighted combination of quality dimensions
    logical_weight = 0.4
    clarity_weight = 0.3
    relevance_weight = 0.3

    composite =
      step.logical_score * logical_weight +
        step.clarity_score * clarity_weight +
        step.relevance_score * relevance_weight

    Float.round(composite, 3)
  end

  @doc """
  Get step summary for logging and analysis.
  """
  def summary(step) do
    %{
      id: step.id,
      index: step.index,
      type: step.step_type,
      content_length: if(step.content, do: String.length(step.content), else: 0),
      validation_status: step.validation_status,
      quality_score: quality_score(step),
      has_errors: has_errors?(step),
      confidence: step.confidence
    }
  end

  @doc """
  Extract learning data from the reasoning step.
  """
  def extract_learning_data(step) do
    %{
      step_characteristics: %{
        type: step.step_type,
        content_length: if(step.content, do: String.length(step.content), else: 0),
        complexity: assess_step_complexity(step.content)
      },
      validation_outcome: %{
        status: step.validation_status,
        score: step.validation_score,
        issues_found: length(step.errors)
      },
      quality_metrics: %{
        logical_score: step.logical_score,
        clarity_score: step.clarity_score,
        relevance_score: step.relevance_score,
        overall_quality: quality_score(step)
      },
      correction_data: %{
        corrections_applied: length(step.corrections),
        correction_effectiveness: assess_correction_effectiveness(step)
      }
    }
  end

  # Private helper functions

  defp generate_step_id do
    # Generate unique ID for reasoning step
    timestamp = System.system_time(:nanosecond)
    random = :crypto.strong_rand_bytes(2) |> Base.encode16(case: :lower)
    "step_#{timestamp}_#{random}"
  end

  defp assess_step_complexity(content) when is_binary(content) do
    # Simple complexity assessment based on content characteristics
    word_count = String.split(content) |> length()

    cond do
      word_count > 50 -> :high
      word_count > 20 -> :medium
      word_count > 0 -> :low
      true -> :minimal
    end
  end

  defp assess_step_complexity(_), do: :minimal

  defp assess_correction_effectiveness(step) do
    if Enum.empty?(step.corrections) do
      :no_corrections
    else
      # Simple effectiveness assessment
      case step.validation_status do
        :corrected -> :effective
        :valid -> :effective
        _ -> :ineffective
      end
    end
  end
end
