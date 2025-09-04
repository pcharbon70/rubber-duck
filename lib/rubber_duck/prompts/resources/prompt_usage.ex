defmodule RubberDuck.Prompts.Resources.PromptUsage do
  @moduledoc """
  Usage analytics resource for comprehensive prompt performance tracking.

  Tracks prompt usage analytics per tenant/user with performance metrics,
  success/failure rates, and usage pattern analysis for optimization.
  """

  use Ash.Resource,
    domain: RubberDuck.Prompts.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "prompt_usages"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:create, :read]

    create :record_successful_usage do
      argument :prompt_id, :uuid, allow_nil?: false
      argument :used_by_id, :uuid, allow_nil?: false
      argument :context_type, :atom, allow_nil?: false
      argument :response_time_ms, :integer, allow_nil?: false
      argument :tokens_used, :integer, allow_nil?: false

      change set_attribute(:success, true)
      change manage_relationship(:prompt_id, :prompt, type: :append_and_remove)
      change set_attribute(:used_by_id, arg(:used_by_id))
      change set_attribute(:context_type, arg(:context_type))
      change set_attribute(:response_time_ms, arg(:response_time_ms))
      change set_attribute(:tokens_used, arg(:tokens_used))
    end

    create :record_failed_usage do
      argument :prompt_id, :uuid, allow_nil?: false
      argument :used_by_id, :uuid, allow_nil?: false
      argument :context_type, :atom, allow_nil?: false
      argument :error_type, :atom, allow_nil?: false
      argument :error_message, :string, allow_nil?: false

      change set_attribute(:success, false)
      change manage_relationship(:prompt_id, :prompt, type: :append_and_remove)
      change set_attribute(:used_by_id, arg(:used_by_id))
      change set_attribute(:context_type, arg(:context_type))
      change set_attribute(:error_type, arg(:error_type))
      change set_attribute(:error_message, arg(:error_message))
    end

    read :usage_for_prompt do
      argument :prompt_id, :uuid, allow_nil?: false
      filter expr(prompt_id == ^arg(:prompt_id))
    end

    read :failed_usages do
      filter expr(success == false)
    end

    read :analytics_summary do
      argument :time_window_days, :integer, default: 30
      argument :user_id, :uuid

      prepare build(
                expr(
                  fragment("? >= NOW() - INTERVAL '? days'", inserted_at, ^arg(:time_window_days))
                )
              )

      filter expr(
               if is_nil(^arg(:user_id)),
                 do: true,
                 else: used_by_id == ^arg(:user_id)
             )
    end

    read :effectiveness_metrics do
      argument :prompt_ids, {:array, :uuid}
      argument :time_window_days, :integer, default: 30

      prepare build(
                expr(
                  fragment("? >= NOW() - INTERVAL '? days'", inserted_at, ^arg(:time_window_days))
                )
              )

      filter expr(
               if is_nil(^arg(:prompt_ids)),
                 do: true,
                 else: prompt_id in ^arg(:prompt_ids)
             )
    end

    read :performance_trends do
      argument :time_window_days, :integer, default: 7
      argument :group_by_interval, :string, default: "day"

      prepare build(
                expr(
                  fragment("? >= NOW() - INTERVAL '? days'", inserted_at, ^arg(:time_window_days))
                )
              )
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  validations do
    validate present([:prompt_id, :used_by_id, :context_type])
    validate compare(:response_time_ms, greater_than_or_equal_to: 0)
    validate compare(:tokens_used, greater_than_or_equal_to: 0)
    validate compare(:user_satisfaction, greater_than_or_equal_to: 1)
    validate compare(:user_satisfaction, less_than_or_equal_to: 5)
  end

  attributes do
    uuid_primary_key :id

    attribute :used_by_id, :uuid, allow_nil?: false

    attribute :context_type, :atom,
      allow_nil?: false,
      constraints: [
        one_of: [:llm_request, :workflow_step, :rag_query, :template_expansion, :test_execution]
      ]

    attribute :request_id, :uuid
    attribute :response_time_ms, :integer
    attribute :tokens_used, :integer
    attribute :success, :boolean, allow_nil?: false, default: true

    attribute :error_type, :atom,
      constraints: [
        one_of: [
          :timeout,
          :validation_error,
          :security_violation,
          :provider_error,
          :content_error
        ]
      ]

    attribute :error_message, :string
    attribute :effectiveness_score, :decimal
    attribute :user_satisfaction, :integer
    attribute :performance_metrics, :map, default: %{}
    attribute :usage_metadata, :map, default: %{}
    attribute :variables_used, :map, default: %{}

    timestamps()
  end

  relationships do
    belongs_to :prompt, RubberDuck.Prompts.Resources.Prompt, allow_nil?: false
  end
end
