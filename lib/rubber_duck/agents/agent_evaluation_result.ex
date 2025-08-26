defmodule RubberDuck.Agents.AgentEvaluationResult do
  @moduledoc """
  Ash resource for tracking individual agent evaluation results within coordination sessions.

  Stores the evaluation results from each specialized judge agent including scores,
  confidence levels, issues found, and agent-specific analysis details.
  """

  use Ash.Resource,
    domain: RubberDuck.Agents,
    data_layer: AshPostgres.DataLayer

  import Ash.Expr
  require Ash.Query

  postgres do
    table "agent_evaluation_results"
    repo RubberDuck.Repo

    references do
      reference :coordination_session, on_delete: :delete, on_update: :update
    end
  end

  resource do
    description "Individual agent evaluation results within coordination sessions"
  end

  code_interface do
    define :create
    define :start_evaluation
    define :complete_evaluation
    define :fail_evaluation
    define :timeout_evaluation
    define :read
  end

  actions do
    defaults [:read]

    create :create do
      accept [:coordination_session_id, :agent_type, :agent_specialization]

      change set_attribute(:evaluation_status, :pending)
    end

    update :start_evaluation do
      change set_attribute(:evaluation_status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :complete_evaluation do
      accept [
        :evaluation_score,
        :confidence_level,
        :issues_found,
        :recommendations,
        :detailed_analysis,
        :agent_metadata,
        :cost_usd,
        :tokens_used
      ]

      change set_attribute(:evaluation_status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
      change after_action({__MODULE__, :calculate_evaluation_duration})
    end

    update :fail_evaluation do
      accept [:error_message]

      change set_attribute(:evaluation_status, :failed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
      change after_action({__MODULE__, :calculate_evaluation_duration})
    end

    update :timeout_evaluation do
      change set_attribute(:evaluation_status, :timeout)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
      change set_attribute(:error_message, "Evaluation timed out")
      change after_action({__MODULE__, :calculate_evaluation_duration})
    end
  end

  preparations do
    prepare build(load: [:coordination_session])
  end

  changes do
    change before_action({__MODULE__, :set_agent_specialization})

    change after_action({__MODULE__, :log_evaluation_completion}) do
      on [:update]
    end
  end

  validations do
    validate present([:coordination_session_id, :agent_type, :agent_specialization])
  end

  attributes do
    uuid_primary_key :id

    attribute :coordination_session_id, :uuid do
      description "Associated coordination session"
      allow_nil? false
    end

    attribute :agent_type, :atom do
      description "Type of judge agent that performed the evaluation"
      constraints one_of: [:code_quality, :architecture, :security, :test_quality]
      allow_nil? false
    end

    attribute :agent_specialization, :atom do
      description "Agent's area of specialization (same as agent_type for consistency)"
      allow_nil? false
    end

    attribute :evaluation_score, :decimal do
      description "Overall evaluation score from this agent (0.0 to 1.0)"
      constraints min: 0.0, max: 1.0
      allow_nil? false
    end

    attribute :confidence_level, :decimal do
      description "Agent's confidence in its evaluation (0.0 to 1.0)"
      constraints min: 0.0, max: 1.0
      allow_nil? false
    end

    attribute :issues_found, {:array, :map} do
      description "List of issues identified by this agent"
      default []
    end

    attribute :recommendations, {:array, :string} do
      description "Recommendations provided by this agent"
      default []
    end

    attribute :detailed_analysis, :map do
      description "Detailed analysis breakdown by criteria"
      default %{}
    end

    attribute :agent_metadata, :map do
      description "Agent-specific metadata and metrics"
      default %{}
    end

    attribute :evaluation_duration_ms, :integer do
      description "Time taken for this agent's evaluation in milliseconds"
    end

    attribute :cost_usd, :decimal do
      description "Cost of this evaluation in USD (for LLM usage)"
      constraints min: 0.0
      default 0.0
    end

    attribute :tokens_used, :integer do
      description "Number of tokens consumed during evaluation"
      default 0
    end

    attribute :started_at, :utc_datetime_usec do
      description "When this agent started its evaluation"
      default &DateTime.utc_now/0
    end

    attribute :completed_at, :utc_datetime_usec do
      description "When this agent completed its evaluation"
    end

    attribute :evaluation_status, :atom do
      description "Status of this agent's evaluation"
      constraints one_of: [:pending, :running, :completed, :failed, :timeout]
      default :pending
    end

    attribute :error_message, :string do
      description "Error message if evaluation failed"
    end

    timestamps()
  end

  relationships do
    belongs_to :coordination_session, RubberDuck.Agents.CoordinationSession
  end

  calculations do
    calculate :is_completed, :boolean, expr(evaluation_status == :completed)
    calculate :has_issues, :boolean, expr(fragment("cardinality(?) > 0", issues_found))
    calculate :issue_count, :integer, expr(fragment("cardinality(?)", issues_found))
    calculate :recommendation_count, :integer, expr(fragment("cardinality(?)", recommendations))

    calculate :evaluation_age_seconds,
              :integer,
              expr(fragment("EXTRACT(EPOCH FROM (? - ?))", now(), started_at))
  end

  aggregates do
    # These would be calculated from the coordination_session relationship
    # if we had other related resources to aggregate from
  end

  # Custom validation functions

  def validate_agent_consistency(changeset, _opts) do
    agent_type = Ash.Changeset.get_attribute(changeset, :agent_type)
    specialization = Ash.Changeset.get_attribute(changeset, :agent_specialization)

    if agent_type && specialization && agent_type != specialization do
      Ash.Changeset.add_error(changeset,
        field: :agent_specialization,
        message: "Agent specialization must match agent type"
      )
    else
      changeset
    end
  end

  def validate_evaluation_completeness(changeset, _opts) do
    required_fields = [:evaluation_score, :confidence_level]

    missing_fields =
      Enum.filter(required_fields, fn field ->
        is_nil(Ash.Changeset.get_attribute(changeset, field))
      end)

    if length(missing_fields) > 0 do
      Ash.Changeset.add_error(changeset,
        field: :evaluation_status,
        message: "Cannot complete evaluation without: #{Enum.join(missing_fields, ", ")}"
      )
    else
      changeset
    end
  end

  # Custom change functions

  def set_agent_specialization(changeset, _opts) do
    agent_type = Ash.Changeset.get_attribute(changeset, :agent_type)

    if agent_type && is_nil(Ash.Changeset.get_attribute(changeset, :agent_specialization)) do
      Ash.Changeset.change_attribute(changeset, :agent_specialization, agent_type)
    else
      changeset
    end
  end

  def calculate_evaluation_duration(changeset, _opts) do
    started_at = changeset.data.started_at
    completed_at = Ash.Changeset.get_attribute(changeset, :completed_at) || DateTime.utc_now()

    if started_at do
      duration_ms = DateTime.diff(completed_at, started_at, :millisecond)
      Ash.Changeset.change_attribute(changeset, :evaluation_duration_ms, duration_ms)
    else
      changeset
    end
  end

  def log_evaluation_completion(changeset, result, _opts) do
    agent_type = result.agent_type
    score = result.evaluation_score
    confidence = result.confidence_level
    duration = result.evaluation_duration_ms

    require Logger

    Logger.info(
      "Agent evaluation completed: #{agent_type} - Score: #{score}, Confidence: #{confidence}, Duration: #{duration}ms"
    )

    {:ok, result}
  end

  # Helper functions for agent evaluation management

  @doc """
  Get evaluation results for a coordination session.
  """
  def get_session_results(coordination_session_id) do
    __MODULE__
    |> Ash.Query.filter(coordination_session_id: coordination_session_id)
    |> Ash.Query.filter(evaluation_status: :completed)
    |> Ash.read!()
  end

  @doc """
  Get evaluation statistics for an agent type.
  """
  def get_agent_stats(agent_type) do
    results =
      __MODULE__
      |> Ash.Query.filter(agent_type: agent_type)
      |> Ash.Query.filter(evaluation_status: :completed)
      |> Ash.read!()

    if length(results) > 0 do
      scores = Enum.map(results, & &1.evaluation_score)
      confidences = Enum.map(results, & &1.confidence_level)
      durations = Enum.map(results, & &1.evaluation_duration_ms)
      costs = Enum.map(results, & &1.cost_usd)

      %{
        total_evaluations: length(results),
        avg_score: Enum.sum(scores) / length(scores),
        avg_confidence: Enum.sum(confidences) / length(confidences),
        avg_duration_ms: Enum.sum(durations) / length(durations),
        total_cost_usd: Enum.sum(costs),
        score_distribution: calculate_score_distribution(scores)
      }
    else
      %{
        total_evaluations: 0,
        avg_score: 0.0,
        avg_confidence: 0.0,
        avg_duration_ms: 0.0,
        total_cost_usd: 0.0,
        score_distribution: %{}
      }
    end
  end

  @doc """
  Find evaluations that are taking too long.
  """
  def get_stuck_evaluations(_timeout_seconds \\ 300) do
    __MODULE__
    |> Ash.Query.filter(evaluation_status: [:pending, :running])
    |> Ash.read!()
  end

  # Private helper functions

  defp calculate_score_distribution(scores) do
    Enum.reduce(scores, %{excellent: 0, good: 0, fair: 0, poor: 0}, fn score, acc ->
      cond do
        score >= 0.8 -> Map.update!(acc, :excellent, &(&1 + 1))
        score >= 0.6 -> Map.update!(acc, :good, &(&1 + 1))
        score >= 0.4 -> Map.update!(acc, :fair, &(&1 + 1))
        true -> Map.update!(acc, :poor, &(&1 + 1))
      end
    end)
  end
end
