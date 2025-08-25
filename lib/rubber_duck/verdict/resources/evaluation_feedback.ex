defmodule RubberDuck.Verdict.Resources.EvaluationFeedback do
  @moduledoc """
  Evaluation feedback resource for capturing user input on evaluation quality.

  Enables users to provide feedback on evaluation results to improve judge
  selection and evaluation accuracy over time. Supports the learning and
  optimization aspects of the Verdict framework.
  """

  use Ash.Resource,
    domain: RubberDuck.Verdict,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "evaluation_feedback"
    repo RubberDuck.Repo
  end

  code_interface do
    define :create, action: :create
    define :read, action: :read
    define :update_details, action: :update_details
    define :destroy, action: :destroy
    define :mark_processed, action: :mark_processed
    define :by_evaluation_run, args: [:evaluation_run_id], action: :read
    define :by_user, args: [:user_id], action: :read
    define :by_feedback_type, args: [:feedback_type], action: :read
    define :unprocessed_feedback, action: :read
    define :recent_feedback, action: :read
    define :positive_feedback, action: :read
    define :negative_feedback, action: :read
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      description "Create new evaluation feedback"

      accept [
        :evaluation_run_id,
        :evaluation_result_id,
        :user_id,
        :feedback_type,
        :rating,
        :agreed_with_result,
        :comments,
        :suggested_score,
        :issues_missed,
        :false_positives,
        :bias_indicators,
        :helpful_recommendations,
        :unhelpful_recommendations,
        :context_information
      ]

      validate present([:evaluation_run_id, :user_id, :feedback_type])
    end

    update :update_details do
      description "Update feedback details"

      accept [
        :rating,
        :comments,
        :suggested_score,
        :issues_missed,
        :false_positives,
        :bias_indicators,
        :helpful_recommendations,
        :unhelpful_recommendations,
        :context_information
      ]
    end

    update :mark_processed do
      description "Mark feedback as processed with notes"

      accept [:processing_notes]
      change set_attribute(:processed, true)
    end
  end

  # Authorization policies for evaluation feedback
  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      description "Users can read their own feedback, admins can read all"

      authorize_if expr(user_id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :security_admin)
    end

    policy action_type(:create) do
      description "Authenticated users can create feedback"

      authorize_if actor_attribute_equals(:role, :user)
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action_type(:update) do
      description "Users can update their own feedback"

      authorize_if expr(user_id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action(:mark_processed) do
      description "Only system can mark feedback as processed"
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :security_admin)
    end

    policy action_type(:destroy) do
      description "Only admins can delete feedback"
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  preparations do
    prepare build(sort: [inserted_at: :desc])
  end

  attributes do
    uuid_primary_key :id

    attribute :evaluation_run_id, :uuid do
      description "ID of the evaluation run this feedback relates to"
      allow_nil? false
    end

    attribute :evaluation_result_id, :uuid do
      description "ID of the specific evaluation result being reviewed"
      allow_nil? true
    end

    attribute :user_id, :uuid do
      description "ID of user providing the feedback"
      allow_nil? false
    end

    attribute :feedback_type, :atom do
      description "Type of feedback provided"

      constraints one_of: [
                    :accuracy,
                    :usefulness,
                    :bias_report,
                    :improvement_suggestion,
                    :general
                  ]

      allow_nil? false
    end

    attribute :rating, :integer do
      description "Rating from 1-5 for the evaluation quality"
      constraints min: 1, max: 5
      allow_nil? true
    end

    attribute :agreed_with_result, :boolean do
      description "Whether user agreed with the evaluation result"
      allow_nil? true
    end

    attribute :comments, :string do
      description "Detailed feedback comments from the user"
      constraints max_length: 2000
      allow_nil? true
    end

    attribute :suggested_score, :decimal do
      description "User's suggested score if different from evaluation"
      constraints precision: 3, scale: 2, min: 0.0, max: 1.0
      allow_nil? true
    end

    attribute :issues_missed, {:array, :string} do
      description "Issues that the evaluation missed according to user"
      default []
    end

    attribute :false_positives, {:array, :string} do
      description "Issues incorrectly identified by the evaluation"
      default []
    end

    attribute :bias_indicators, {:array, :string} do
      description "Bias indicators identified by the user"
      default []
    end

    attribute :helpful_recommendations, {:array, :string} do
      description "Recommendations user found helpful"
      default []
    end

    attribute :unhelpful_recommendations, {:array, :string} do
      description "Recommendations user found unhelpful"
      default []
    end

    attribute :context_information, :map do
      description "Additional context about the feedback"
      default %{}
    end

    attribute :processed, :boolean do
      description "Whether this feedback has been processed for learning"
      default false
    end

    attribute :processing_notes, :string do
      description "Notes from feedback processing"
      constraints max_length: 1000
      allow_nil? true
    end

    timestamps()
  end

  relationships do
    belongs_to :evaluation_run, RubberDuck.Verdict.Resources.EvaluationRun do
      attribute_writable? false
      source_attribute :evaluation_run_id
      destination_attribute :id
    end

    belongs_to :evaluation_result, RubberDuck.Verdict.Resources.EvaluationResult do
      attribute_writable? false
      source_attribute :evaluation_result_id
      destination_attribute :id
    end

    belongs_to :user, RubberDuck.Accounts.User do
      attribute_writable? false
      source_attribute :user_id
      destination_attribute :id
    end
  end

  calculations do
    calculate :is_positive, :boolean, expr(rating >= 4)
    calculate :is_negative, :boolean, expr(rating <= 2)

    calculate :has_bias_report,
              :boolean,
              expr(fragment("array_length(?, 1) > 0", bias_indicators))

    calculate :has_improvement_suggestions,
              :boolean,
              expr(not is_nil(comments) and comments != "")

    calculate :feedback_value_score,
              :decimal,
              expr(
                cond do
                  rating >= 4 and agreed_with_result and
                      fragment("array_length(?, 1)", issues_missed) == 0 ->
                    1.0

                  rating <= 2 and not agreed_with_result ->
                    0.8

                  true ->
                    0.5
                end
              )
  end
end
