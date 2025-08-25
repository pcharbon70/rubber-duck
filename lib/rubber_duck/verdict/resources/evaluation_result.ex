defmodule RubberDuck.Verdict.Resources.EvaluationResult do
  @moduledoc """
  Evaluation result resource for storing individual Verdict evaluation outcomes.

  Stores detailed evaluation results including scores, confidence ratings,
  issues found, recommendations, and detailed reasoning. Links to evaluation
  runs for complete audit trails and performance analysis.
  """

  use Ash.Resource,
    domain: RubberDuck.Verdict,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "evaluation_results"
    repo RubberDuck.Repo
  end

  code_interface do
    define :create, action: :create
    define :read, action: :read
    define :update_metadata, action: :update_metadata
    define :destroy, action: :destroy
    define :add_feedback_summary, action: :add_feedback_summary
    define :by_evaluation_run, args: [:evaluation_run_id], action: :read
    define :by_judge_unit_type, args: [:judge_unit_type], action: :read
    define :by_model, args: [:model_used], action: :read
    define :by_evaluation_stage, args: [:evaluation_stage], action: :read
    define :high_confidence_results, action: :read
    define :low_confidence_results, action: :read
    define :recent_results, action: :read
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      description "Create a new evaluation result"

      accept [
        :evaluation_run_id,
        :judge_unit_type,
        :model_used,
        :score,
        :confidence,
        :issues_found,
        :recommendations,
        :reasoning,
        :evaluation_stage,
        :tokens_used,
        :cost_usd,
        :latency_ms,
        :prompt_template,
        :llm_request_metadata,
        :validation_errors,
        :bias_indicators,
        :quality_metrics
      ]

      validate present([
                 :evaluation_run_id,
                 :judge_unit_type,
                 :model_used,
                 :score,
                 :confidence,
                 :evaluation_stage,
                 :tokens_used,
                 :cost_usd,
                 :latency_ms
               ])
    end

    update :update_metadata do
      description "Update evaluation result metadata"

      accept [:bias_indicators, :quality_metrics, :validation_errors]
    end

    update :add_feedback_summary do
      description "Add feedback summary metrics to the result"
      accept [:quality_metrics]
    end
  end

  # Authorization policies for evaluation results
  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      description "Users can read results from their evaluation runs"

      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :security_admin)
    end

    policy action_type(:create) do
      description "System can create evaluation results"

      # System-level creation
      authorize_if always()
    end

    policy action_type([:update, :destroy]) do
      description "Only admins can modify evaluation results"
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :security_admin)
    end
  end

  preparations do
    prepare build(sort: [inserted_at: :desc])
  end

  attributes do
    uuid_primary_key :id

    attribute :evaluation_run_id, :uuid do
      description "ID of the evaluation run this result belongs to"
      allow_nil? false
    end

    attribute :judge_unit_type, :string do
      description "Type of judge unit that produced this result"
      constraints max_length: 100
      allow_nil? false
    end

    attribute :model_used, :string do
      description "LLM model used for this evaluation"
      constraints max_length: 100
      allow_nil? false
    end

    attribute :score, :decimal do
      description "Overall evaluation score (0.0 to 1.0)"
      constraints precision: 3, scale: 2, min: 0.0, max: 1.0
      allow_nil? false
    end

    attribute :confidence, :decimal do
      description "Confidence in the evaluation result (0.0 to 1.0)"
      constraints precision: 3, scale: 2, min: 0.0, max: 1.0
      allow_nil? false
    end

    attribute :issues_found, {:array, :string} do
      description "List of issues identified in the code"
      default []
    end

    attribute :recommendations, {:array, :string} do
      description "List of improvement recommendations"
      default []
    end

    attribute :reasoning, :string do
      description "Detailed reasoning for the evaluation result"
      constraints max_length: 5000
      allow_nil? true
    end

    attribute :evaluation_stage, :atom do
      description "Stage of evaluation (screening, detailed, comprehensive)"
      constraints one_of: [:screening, :lightweight_final, :detailed, :comprehensive]
      allow_nil? false
    end

    attribute :tokens_used, :integer do
      description "Number of tokens consumed for this evaluation"
      constraints min: 0
      allow_nil? false
    end

    attribute :cost_usd, :decimal do
      description "Cost of this evaluation in USD"
      constraints precision: 10, scale: 6, min: 0.0
      allow_nil? false
    end

    attribute :latency_ms, :integer do
      description "Evaluation latency in milliseconds"
      constraints min: 0
      allow_nil? false
    end

    attribute :prompt_template, :string do
      description "Template used for the evaluation prompt"
      constraints max_length: 10_000
      allow_nil? true
    end

    attribute :llm_request_metadata, :map do
      description "Metadata from the LLM API request/response"
      default %{}
    end

    attribute :validation_errors, {:array, :string} do
      description "Any validation errors encountered during result processing"
      default []
    end

    attribute :bias_indicators, :map do
      description "Detected bias indicators in the evaluation"
      default %{}
    end

    attribute :quality_metrics, :map do
      description "Additional quality metrics for this evaluation"
      default %{}
    end

    timestamps()
  end

  relationships do
    belongs_to :evaluation_run, RubberDuck.Verdict.Resources.EvaluationRun do
      attribute_writable? false
      source_attribute :evaluation_run_id
      destination_attribute :id
    end

    has_many :feedback_entries, RubberDuck.Verdict.Resources.EvaluationFeedback do
      destination_attribute :evaluation_result_id
    end
  end

  calculations do
    calculate :cost_per_token, :decimal, expr(cost_usd / tokens_used)
    calculate :is_high_confidence, :boolean, expr(confidence >= 0.8)
    calculate :is_cost_effective, :boolean, expr(cost_usd <= 0.05)
    calculate :issue_count, :integer, expr(fragment("array_length(?, 1)", issues_found))

    calculate :recommendation_count,
              :integer,
              expr(fragment("array_length(?, 1)", recommendations))
  end
end
