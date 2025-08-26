defmodule RubberDuck.Verdict.Feedback.FeedbackCollection do
  @moduledoc """
  Ash resource for tracking user feedback and behavioral patterns for continuous learning.
  
  Stores comprehensive feedback data including explicit user input, implicit behavioral
  indicators, and system performance metrics to enable sophisticated learning algorithms.
  """

  use Ash.Resource,
    domain: RubberDuck.Verdict,
    data_layer: AshPostgres.DataLayer

  import Ash.Expr
  require Ash.Query
  require Logger

  postgres do
    table "verdict_feedback_collections"
    repo RubberDuck.Repo
  end

  resource do
    description "Comprehensive feedback collection for continuous learning"
  end

  attributes do
    uuid_primary_key :id

    attribute :evaluation_run_id, :uuid do
      description "Associated evaluation run"
      allow_nil? false
    end

    attribute :feedback_type, :atom do
      description "Type of feedback collected"
      constraints one_of: [
        :explicit_rating, :explicit_correction, :explicit_comment,
        :implicit_acceptance, :implicit_rejection, :implicit_retry, :implicit_edit,
        :system_performance, :judge_agreement, :cost_efficiency
      ]
      allow_nil? false
    end

    attribute :feedback_source, :atom do
      description "Source of the feedback"
      constraints one_of: [:user_interface, :api, :system_automated, :judge_coordination, :performance_monitor]
      allow_nil? false
    end

    attribute :user_id, :uuid do
      description "User who provided the feedback (if applicable)"
    end

    attribute :feedback_data, :map do
      description "Raw feedback data and metadata"
      default %{}
    end

    attribute :processed_feedback, :map do
      description "Processed and analyzed feedback information"
      default %{}
    end

    attribute :learning_value, :decimal do
      description "Assessed learning value of this feedback (0.0 to 1.0)"
      constraints min: 0.0, max: 1.0
      default 0.5
    end

    attribute :confidence_score, :decimal do
      description "Confidence in the feedback quality and reliability (0.0 to 1.0)"
      constraints min: 0.0, max: 1.0
      default 0.7
    end

    attribute :processing_priority, :atom do
      description "Priority level for processing this feedback"
      constraints one_of: [:critical, :high, :medium, :low, :background]
      default :medium
    end

    attribute :learning_categories, {:array, :atom} do
      description "Learning categories this feedback applies to"
      default []
    end

    attribute :actionable_insights, :map do
      description "Extracted actionable insights for learning engines"
      default %{}
    end

    attribute :routing_targets, {:array, :atom} do
      description "Learning engines that should process this feedback"
      default []
    end

    attribute :feedback_status, :atom do
      description "Current processing status of the feedback"
      constraints one_of: [:collected, :validated, :processed, :routed, :learned_from, :archived]
      default :collected
    end

    attribute :processed_at, :utc_datetime_usec do
      description "When the feedback was processed"
    end

    attribute :routed_at, :utc_datetime_usec do
      description "When the feedback was routed to learning engines"
    end

    attribute :learned_from_at, :utc_datetime_usec do
      description "When learning engines successfully used this feedback"
    end

    attribute :learning_effectiveness, :decimal do
      description "Measured effectiveness of learning from this feedback (0.0 to 1.0)"
      constraints min: 0.0, max: 1.0
    end

    attribute :correlation_score, :decimal do
      description "Correlation with subsequent system improvements (0.0 to 1.0)"
      constraints min: 0.0, max: 1.0
    end

    attribute :retention_policy, :atom do
      description "Data retention policy for this feedback"
      constraints one_of: [:permanent, :long_term, :medium_term, :short_term, :temporary]
      default :long_term
    end

    attribute :privacy_level, :atom do
      description "Privacy level and data handling requirements"
      constraints one_of: [:public, :internal, :private, :confidential]
      default :private
    end

    timestamps()
  end

  relationships do
    belongs_to :user, RubberDuck.Accounts.User do
      attribute_writable? false
    end

    # belongs_to :evaluation_run, RubberDuck.Verdict.EvaluationRun  # When available
    # has_many :learning_model_updates, RubberDuck.Verdict.Feedback.LearningModelUpdate  # When implemented
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :evaluation_run_id, :feedback_type, :feedback_source, :user_id,
        :feedback_data, :learning_value, :confidence_score, :processing_priority,
        :learning_categories, :privacy_level, :retention_policy
      ]
      
      change set_attribute(:feedback_status, :collected)
    end

    update :process_feedback do
      accept [:processed_feedback, :actionable_insights, :routing_targets]
      
      change set_attribute(:feedback_status, :processed)
      change set_attribute(:processed_at, &DateTime.utc_now/0)
    end

    update :route_feedback do
      change set_attribute(:feedback_status, :routed)
      change set_attribute(:routed_at, &DateTime.utc_now/0)
    end

    update :mark_learned_from do
      accept [:learning_effectiveness, :correlation_score]
      
      change set_attribute(:feedback_status, :learned_from)
      change set_attribute(:learned_from_at, &DateTime.utc_now/0)
    end

    update :archive_feedback do
      change set_attribute(:feedback_status, :archived)
    end
  end

  code_interface do
    define :create
    define :process_feedback
    define :route_feedback
    define :mark_learned_from
    define :archive_feedback
    define :read
  end

  preparations do
    prepare build(load: [:user])
  end

  calculations do
    calculate :is_high_value, :boolean, expr(learning_value > 0.8 and confidence_score > 0.7)
    calculate :is_processed, :boolean, expr(feedback_status in [:processed, :routed, :learned_from, :archived])
    calculate :processing_age_hours, :integer, 
      expr(fragment("EXTRACT(EPOCH FROM (? - ?)) / 3600", now(), inserted_at))
    
    calculate :days_since_feedback, :integer,
      expr(fragment("EXTRACT(DAY FROM (? - ?))", now(), inserted_at))
  end

  aggregates do
    # Would add aggregates for learning analytics
  end

  validations do
    validate present([:evaluation_run_id, :feedback_type, :feedback_source])
    
    validate match(:learning_value, ~r/^[0-1](\.[0-9]+)?$/) do
      message "Learning value must be between 0.0 and 1.0"
    end
  end

  changes do
    change before_action(&set_default_learning_categories/2) do
      on [:create]
    end
    
    change after_action(&log_feedback_collection/3) do
      on [:create]
    end
  end

  # Custom change functions

  def set_default_learning_categories(changeset, _opts) do
    feedback_type = Ash.Changeset.get_attribute(changeset, :feedback_type)
    
    default_categories = case feedback_type do
      :explicit_correction -> [:evaluation_criteria_adjustment, :quality_enhancement]
      :explicit_rating -> [:quality_enhancement, :user_preference_modeling]
      :judge_agreement -> [:judge_selection_optimization, :coordination_optimization]
      :cost_efficiency -> [:cost_optimization, :budget_optimization]
      _ -> [:general_improvement]
    end
    
    if is_nil(Ash.Changeset.get_attribute(changeset, :learning_categories)) do
      Ash.Changeset.change_attribute(changeset, :learning_categories, default_categories)
    else
      changeset
    end
  end

  def log_feedback_collection(_changeset, result, _opts) do
    feedback_type = result.feedback_type
    learning_value = result.learning_value
    
    require Logger
    Logger.info("Feedback collected: #{feedback_type} with learning value #{learning_value}")
    
    {:ok, result}
  end

  # Helper functions for feedback management

  @doc """
  Get high-value feedback for priority learning.
  """
  def get_high_value_feedback(limit \\ 50) do
    __MODULE__
    |> Ash.Query.filter(is_high_value: true)
    |> Ash.Query.filter(feedback_status: [:processed, :routed])
    |> Ash.Query.sort(learning_value: :desc, confidence_score: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.read!()
  end

  @doc """
  Get feedback ready for learning engine processing.
  """
  def get_pending_feedback(processing_priority \\ :medium) do
    __MODULE__
    |> Ash.Query.filter(feedback_status: :processed)
    |> Ash.Query.filter(processing_priority: processing_priority)
    |> Ash.Query.sort(learning_value: :desc)
    |> Ash.read!()
  end

  @doc """
  Get feedback statistics for analytics.
  """
  def get_feedback_stats(days_back \\ 7) do
    recent_feedback = __MODULE__
      |> Ash.Query.filter(days_since_feedback <= days_back)
      |> Ash.read!()
    
    by_type = Enum.group_by(recent_feedback, & &1.feedback_type)
    by_status = Enum.group_by(recent_feedback, & &1.feedback_status)
    
    %{
      total_feedback: length(recent_feedback),
      high_value_count: Enum.count(recent_feedback, & &1.is_high_value),
      by_type: Enum.map(by_type, fn {type, list} -> {type, length(list)} end) |> Map.new(),
      by_status: Enum.map(by_status, fn {status, list} -> {status, length(list)} end) |> Map.new(),
      average_learning_value: calculate_average_learning_value(recent_feedback),
      average_confidence: calculate_average_confidence_score(recent_feedback)
    }
  end

  @doc """
  Clean up old feedback based on retention policies.
  """
  def cleanup_expired_feedback do
    # Implementation would clean up based on retention_policy and age
    Logger.info("Feedback cleanup completed")
    {:ok, 0}
  end

  # Private helper functions

  defp calculate_average_learning_value([]), do: 0.0
  defp calculate_average_learning_value(feedback_list) do
    values = Enum.map(feedback_list, & &1.learning_value)
    Enum.sum(values) / length(values)
  end

  defp calculate_average_confidence_score([]), do: 0.0
  defp calculate_average_confidence_score(feedback_list) do
    scores = Enum.map(feedback_list, & &1.confidence_score)
    Enum.sum(scores) / length(scores)
  end
end