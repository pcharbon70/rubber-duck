defmodule RubberDuck.Verdict.Resources.EvaluationRun do
  @moduledoc """
  Evaluation run resource for tracking Verdict evaluation sessions.

  Tracks evaluation session metadata including user context, project settings,
  configuration snapshots, and timing information. Provides audit trail for
  evaluation decisions and enables performance analysis.
  """

  use Ash.Resource,
    domain: RubberDuck.Verdict,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "evaluation_runs"
    repo RubberDuck.Repo
  end

  code_interface do
    define :create, action: :create
    define :read, action: :read
    define :update, action: :update
    define :destroy, action: :destroy
    define :start_evaluation, action: :start_evaluation
    define :complete_evaluation, action: :complete_evaluation
    define :fail_evaluation, action: :fail_evaluation
    define :cancel_evaluation, action: :cancel_evaluation
    define :by_user, args: [:user_id], action: :read
    define :by_project, args: [:project_id], action: :read
    define :by_evaluation_type, args: [:evaluation_type], action: :read
    define :completed_runs, action: :read
    define :failed_runs, action: :read
    define :recent_runs, action: :read
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      description "Create a new evaluation run"

      accept [
        :user_id,
        :project_id,
        :evaluation_type,
        :code_hash,
        :code_size_bytes,
        :configuration_snapshot,
        :judge_units_used,
        :evaluation_strategy,
        :cache_hit,
        :similar_evaluation_id,
        :metadata
      ]

      validate present([:evaluation_type, :code_hash, :code_size_bytes, :configuration_snapshot])
    end

    update :start_evaluation do
      description "Mark evaluation as started"
      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :complete_evaluation do
      description "Mark evaluation as completed with results"

      accept [:total_cost_usd, :total_tokens_used, :total_latency_ms]

      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :fail_evaluation do
      description "Mark evaluation as failed with error"

      accept [:error_message]

      change set_attribute(:status, :failed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :cancel_evaluation do
      description "Cancel a running evaluation"
      change set_attribute(:status, :cancelled)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end
  end

  # Authorization policies for evaluation runs
  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      description "Users can read their own evaluation runs, admins can read all"

      authorize_if expr(user_id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :security_admin)
    end

    policy action_type(:create) do
      description "Authenticated users can create evaluation runs"

      authorize_if actor_attribute_equals(:role, :user)
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action_type([:update, :destroy]) do
      description "Users can update their own runs, admins can update any"

      authorize_if expr(user_id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  preparations do
    prepare build(sort: [started_at: :desc])
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      description "ID of user who initiated the evaluation"
      allow_nil? true
    end

    attribute :project_id, :uuid do
      description "ID of project context for the evaluation"
      allow_nil? true
    end

    attribute :evaluation_type, :atom do
      description "Type of evaluation performed"

      constraints one_of: [
                    :quality,
                    :security,
                    :performance,
                    :maintainability,
                    :best_practices,
                    :comprehensive
                  ]

      allow_nil? false
    end

    attribute :code_hash, :string do
      description "SHA256 hash of evaluated code for deduplication"
      constraints max_length: 64
      allow_nil? false
    end

    attribute :code_size_bytes, :integer do
      description "Size of evaluated code in bytes"
      constraints min: 0
      allow_nil? false
    end

    attribute :configuration_snapshot, :map do
      description "Complete configuration used for this evaluation"
      allow_nil? false
    end

    attribute :judge_units_used, {:array, :string} do
      description "List of judge units used in this evaluation"
      default []
    end

    attribute :evaluation_strategy, :atom do
      description "Strategy used for this evaluation"
      constraints one_of: [:lightweight, :detailed, :comprehensive, :progressive]
      default :progressive
    end

    attribute :cache_hit, :boolean do
      description "Whether this evaluation was served from cache"
      default false
    end

    attribute :similar_evaluation_id, :uuid do
      description "ID of similar evaluation if cache hit via similarity"
      allow_nil? true
    end

    attribute :total_cost_usd, :decimal do
      description "Total cost of this evaluation in USD"
      constraints precision: 10, scale: 6
      allow_nil? true
    end

    attribute :total_tokens_used, :integer do
      description "Total tokens consumed by this evaluation"
      constraints min: 0
      allow_nil? true
    end

    attribute :total_latency_ms, :integer do
      description "Total evaluation latency in milliseconds"
      constraints min: 0
      allow_nil? true
    end

    attribute :started_at, :utc_datetime do
      description "When the evaluation started"
      allow_nil? false
      default &DateTime.utc_now/0
    end

    attribute :completed_at, :utc_datetime do
      description "When the evaluation completed"
      allow_nil? true
    end

    attribute :status, :atom do
      description "Current status of the evaluation run"
      constraints one_of: [:pending, :running, :completed, :failed, :cancelled]
      default :pending
    end

    attribute :error_message, :string do
      description "Error message if evaluation failed"
      constraints max_length: 1000
      allow_nil? true
    end

    attribute :metadata, :map do
      description "Additional metadata for the evaluation run"
      default %{}
    end

    timestamps()
  end

  relationships do
    belongs_to :user, RubberDuck.Accounts.User do
      attribute_writable? false
      source_attribute :user_id
      destination_attribute :id
    end

    belongs_to :similar_evaluation, __MODULE__ do
      attribute_writable? false
      source_attribute :similar_evaluation_id
      destination_attribute :id
    end

    has_many :evaluation_results, RubberDuck.Verdict.Resources.EvaluationResult do
      destination_attribute :evaluation_run_id
    end

    has_many :feedback_entries, RubberDuck.Verdict.Resources.EvaluationFeedback do
      destination_attribute :evaluation_run_id
    end
  end

  calculations do
    calculate :duration_ms, :integer, expr(
      if is_nil(completed_at) do
        nil
      else
        fragment("EXTRACT(epoch FROM (? - ?)) * 1000", completed_at, started_at)
      end
    )

    calculate :is_completed, :boolean, expr(status == :completed)
    calculate :is_cached, :boolean, expr(cache_hit or not is_nil(similar_evaluation_id))
    calculate :cost_per_token, :decimal, expr(total_cost_usd / total_tokens_used)
  end
end
