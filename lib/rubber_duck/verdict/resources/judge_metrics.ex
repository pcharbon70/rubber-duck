defmodule RubberDuck.Verdict.Resources.JudgeMetrics do
  @moduledoc """
  Judge metrics resource for tracking judge performance over time.

  Tracks judge accuracy, cost efficiency, bias indicators, and performance
  trends to enable continuous improvement and optimization of judge selection.
  Provides analytics for cost optimization and quality assurance.
  """

  use Ash.Resource,
    domain: RubberDuck.Verdict,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "judge_metrics"
    repo RubberDuck.Repo
  end

  code_interface do
    define :create, action: :create
    define :read, action: :read
    define :update_metrics, action: :update_metrics
    define :add_alert, action: :add_alert
    define :destroy, action: :destroy
    define :by_judge_unit, args: [:judge_unit_type], action: :read
    define :by_model, args: [:model_name], action: :read
    define :by_evaluation_type, args: [:evaluation_type], action: :read
    define :by_time_period, args: [:time_period], action: :read
    define :recent_metrics, action: :read
    define :performance_summary, action: :read
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      description "Create a new judge metrics record"

      accept [
        :judge_unit_type,
        :model_name,
        :evaluation_type,
        :time_period,
        :period_start,
        :period_end,
        :total_evaluations,
        :successful_evaluations,
        :failed_evaluations,
        :average_score,
        :average_confidence,
        :total_cost_usd,
        :total_tokens_used,
        :average_latency_ms,
        :cache_hit_rate,
        :progressive_efficiency,
        :bias_indicators,
        :quality_trends,
        :performance_alerts
      ]

      validate present([
                 :judge_unit_type,
                 :model_name,
                 :evaluation_type,
                 :period_start,
                 :period_end
               ])
    end

    update :update_metrics do
      description "Update metrics with new evaluation data"

      accept [
        :total_evaluations,
        :successful_evaluations,
        :failed_evaluations,
        :average_score,
        :average_confidence,
        :total_cost_usd,
        :total_tokens_used,
        :average_latency_ms,
        :cache_hit_rate,
        :progressive_efficiency,
        :bias_indicators,
        :quality_trends,
        :performance_alerts
      ]
    end

    update :add_alert do
      description "Add a performance alert"
      accept [:performance_alerts]
    end
  end

  # Authorization policies for judge metrics
  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      description "Admins and users with analytics permissions can read metrics"

      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :security_admin)

      # Users can see basic metrics
      authorize_if actor_attribute_equals(:role, :user)
    end

    policy action([:create, :update_metrics, :add_alert]) do
      description "Only system can create/update metrics"

      # System-level operations
      authorize_if always()
    end

    policy action_type(:destroy) do
      description "Only security admins can delete metrics"
      authorize_if actor_attribute_equals(:role, :security_admin)
    end
  end

  preparations do
    prepare build(sort: [period_start: :desc])
  end

  attributes do
    uuid_primary_key :id

    attribute :judge_unit_type, :string do
      description "Type of judge unit being tracked"
      constraints max_length: 100
      allow_nil? false
    end

    attribute :model_name, :string do
      description "LLM model being tracked"
      constraints max_length: 100
      allow_nil? false
    end

    attribute :evaluation_type, :atom do
      description "Type of evaluations this metric covers"

      constraints one_of: [
                    :quality,
                    :security,
                    :performance,
                    :maintainability,
                    :best_practices,
                    :comprehensive,
                    :all
                  ]

      allow_nil? false
    end

    attribute :time_period, :atom do
      description "Time period for these metrics"
      constraints one_of: [:hourly, :daily, :weekly, :monthly]
      default :daily
    end

    attribute :period_start, :utc_datetime do
      description "Start of the measurement period"
      allow_nil? false
    end

    attribute :period_end, :utc_datetime do
      description "End of the measurement period"
      allow_nil? false
    end

    attribute :total_evaluations, :integer do
      description "Total number of evaluations in this period"
      constraints min: 0
      default 0
    end

    attribute :successful_evaluations, :integer do
      description "Number of successful evaluations"
      constraints min: 0
      default 0
    end

    attribute :failed_evaluations, :integer do
      description "Number of failed evaluations"
      constraints min: 0
      default 0
    end

    attribute :average_score, :decimal do
      description "Average evaluation score for this period"
      constraints precision: 3, scale: 2, min: 0.0, max: 1.0
      allow_nil? true
    end

    attribute :average_confidence, :decimal do
      description "Average confidence rating for this period"
      constraints precision: 3, scale: 2, min: 0.0, max: 1.0
      allow_nil? true
    end

    attribute :total_cost_usd, :decimal do
      description "Total cost for evaluations in this period"
      constraints precision: 10, scale: 6, min: 0.0
      default 0.0
    end

    attribute :total_tokens_used, :integer do
      description "Total tokens consumed in this period"
      constraints min: 0
      default 0
    end

    attribute :average_latency_ms, :integer do
      description "Average evaluation latency in milliseconds"
      constraints min: 0
      allow_nil? true
    end

    attribute :cache_hit_rate, :decimal do
      description "Cache hit rate for this period"
      constraints precision: 3, scale: 2, min: 0.0, max: 1.0
      allow_nil? true
    end

    attribute :progressive_efficiency, :decimal do
      description "Efficiency of progressive evaluation strategy"
      constraints precision: 3, scale: 2, min: 0.0, max: 1.0
      allow_nil? true
    end

    attribute :bias_indicators, :map do
      description "Detected bias patterns and indicators"
      default %{}
    end

    attribute :quality_trends, :map do
      description "Quality trend analysis for this period"
      default %{}
    end

    attribute :performance_alerts, {:array, :string} do
      description "Performance alerts triggered during this period"
      default []
    end

    timestamps()
  end

  calculations do
    calculate :success_rate, :decimal, expr(successful_evaluations / total_evaluations)
    calculate :failure_rate, :decimal, expr(failed_evaluations / total_evaluations)
    calculate :cost_per_evaluation, :decimal, expr(total_cost_usd / total_evaluations)
    calculate :tokens_per_evaluation, :decimal, expr(total_tokens_used / total_evaluations)
    calculate :has_alerts, :boolean, expr(fragment("array_length(?, 1) > 0", performance_alerts))
    calculate :efficiency_score, :decimal, expr((cache_hit_rate + progressive_efficiency) / 2)
  end
end
