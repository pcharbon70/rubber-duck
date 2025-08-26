defmodule RubberDuck.Agents.CoordinationMessage do
  @moduledoc """
  Ash resource for tracking inter-agent communication messages during coordination sessions.

  Stores messages exchanged between judge agents including negotiation communications,
  information sharing, and coordination protocol messages.
  """

  use Ash.Resource,
    domain: RubberDuck.Agents,
    data_layer: AshPostgres.DataLayer

  import Ash.Expr
  require Ash.Query

  postgres do
    table "agent_coordination_messages"
    repo RubberDuck.Repo

    references do
      reference :coordination_session, on_delete: :delete, on_update: :update
    end
  end

  resource do
    description "Inter-agent communication messages during coordination"
  end

  code_interface do
    define :create
    define :deliver_message
    define :process_message
    define :fail_message
    define :expire_message
    define :read
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :coordination_session_id,
        :message_id,
        :from_agent,
        :to_agent,
        :message_type,
        :message_payload,
        :negotiation_id,
        :negotiation_round,
        :priority
      ]

      change after_action({__MODULE__, :set_expiration_time})
    end

    update :deliver_message do
      change set_attribute(:message_status, :delivered)
      change set_attribute(:delivered_at, &DateTime.utc_now/0)
    end

    update :process_message do
      change set_attribute(:message_status, :processed)
      change set_attribute(:processed_at, &DateTime.utc_now/0)
    end

    update :fail_message do
      accept [:error_message]

      change set_attribute(:message_status, :failed)
      change before_action({__MODULE__, :increment_retry_count})
    end

    update :expire_message do
      change set_attribute(:message_status, :expired)
    end
  end

  preparations do
    prepare build(load: [:coordination_session])
  end

  changes do
    change before_action({__MODULE__, :generate_message_id}) do
      on [:create]
    end

    change after_action({__MODULE__, :log_message_activity}) do
      on [:update]
    end
  end

  validations do
    validate present([
               :coordination_session_id,
               :message_id,
               :from_agent,
               :to_agent,
               :message_type
             ])
  end

  attributes do
    uuid_primary_key :id

    attribute :coordination_session_id, :uuid do
      description "Associated coordination session"
      allow_nil? false
    end

    attribute :message_id, :string do
      description "Unique message identifier"
      allow_nil? false
    end

    attribute :from_agent, :atom do
      description "Agent type that sent the message"

      constraints one_of: [
                    :code_quality,
                    :architecture,
                    :security,
                    :test_quality,
                    :hub,
                    :orchestrator
                  ]

      allow_nil? false
    end

    attribute :to_agent, :atom do
      description "Agent type that should receive the message"

      constraints one_of: [
                    :code_quality,
                    :architecture,
                    :security,
                    :test_quality,
                    :hub,
                    :orchestrator,
                    :all
                  ]

      allow_nil? false
    end

    attribute :message_type, :atom do
      description "Type of message being sent"

      constraints one_of: [
                    :coordination_start,
                    :evaluation_request,
                    :evaluation_response,
                    :disagreement_notice,
                    :negotiation_start,
                    :negotiation_round,
                    :negotiation_response,
                    :consensus_proposal,
                    :information_sharing,
                    :status_update,
                    :error_notification,
                    :session_complete
                  ]

      allow_nil? false
    end

    attribute :message_payload, :map do
      description "The actual message content and data"
      default %{}
    end

    attribute :negotiation_id, :string do
      description "Associated negotiation ID if this is a negotiation message"
    end

    attribute :negotiation_round, :integer do
      description "Negotiation round number if applicable"
    end

    attribute :priority, :atom do
      description "Message priority level"
      constraints one_of: [:low, :normal, :high, :urgent]
      default :normal
    end

    attribute :message_status, :atom do
      description "Processing status of the message"
      constraints one_of: [:queued, :delivered, :processed, :failed, :expired]
      default :queued
    end

    attribute :sent_at, :utc_datetime_usec do
      description "When the message was sent"
      default &DateTime.utc_now/0
    end

    attribute :delivered_at, :utc_datetime_usec do
      description "When the message was delivered to recipient"
    end

    attribute :processed_at, :utc_datetime_usec do
      description "When the message was processed by recipient"
    end

    attribute :expires_at, :utc_datetime_usec do
      description "When this message expires"
    end

    attribute :retry_count, :integer do
      description "Number of delivery retry attempts"
      default 0
    end

    attribute :error_message, :string do
      description "Error message if delivery failed"
    end

    timestamps()
  end

  relationships do
    belongs_to :coordination_session, RubberDuck.Agents.CoordinationSession
  end

  calculations do
    calculate :is_expired, :boolean, expr(expires_at < now())
    calculate :is_pending, :boolean, expr(message_status in [:queued, :delivered])

    calculate :message_age_seconds,
              :integer,
              expr(fragment("EXTRACT(EPOCH FROM (? - ?))", now(), sent_at))

    calculate :delivery_time_ms,
              :integer,
              expr(fragment("EXTRACT(EPOCH FROM (? - ?)) * 1000", delivered_at, sent_at))

    calculate :processing_time_ms,
              :integer,
              expr(fragment("EXTRACT(EPOCH FROM (? - ?)) * 1000", processed_at, delivered_at))
  end

  # Custom validation functions

  def validate_agent_communication(changeset, _opts) do
    from_agent = Ash.Changeset.get_attribute(changeset, :from_agent)
    to_agent = Ash.Changeset.get_attribute(changeset, :to_agent)

    if from_agent == to_agent do
      Ash.Changeset.add_error(changeset,
        field: :to_agent,
        message: "Agent cannot send message to itself"
      )
    else
      changeset
    end
  end

  def validate_negotiation_fields(changeset, _opts) do
    message_type = Ash.Changeset.get_attribute(changeset, :message_type)
    negotiation_types = [:negotiation_start, :negotiation_round, :negotiation_response]

    if message_type in negotiation_types do
      negotiation_round = Ash.Changeset.get_attribute(changeset, :negotiation_round)

      if is_nil(negotiation_round) do
        Ash.Changeset.add_error(changeset,
          field: :negotiation_round,
          message: "Negotiation round required for negotiation messages"
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  # Custom change functions

  def generate_message_id(changeset, _opts) do
    message_id = :crypto.strong_rand_bytes(8) |> Base.encode16() |> String.downcase()
    Ash.Changeset.change_attribute(changeset, :message_id, message_id)
  end

  def set_expiration_time(changeset, _opts) do
    priority = Ash.Changeset.get_attribute(changeset, :priority) || :normal

    expiration_minutes =
      case priority do
        :urgent -> 5
        :high -> 15
        :normal -> 60
        :low -> 240
      end

    expires_at = DateTime.utc_now() |> DateTime.add(expiration_minutes, :minute)
    Ash.Changeset.change_attribute(changeset, :expires_at, expires_at)
  end

  def increment_retry_count(changeset, _opts) do
    current_retry = changeset.data.retry_count || 0
    Ash.Changeset.change_attribute(changeset, :retry_count, current_retry + 1)
  end

  def log_message_activity(changeset, result, _opts) do
    action_name = changeset.action.name
    message_type = result.message_type
    from_agent = result.from_agent
    to_agent = result.to_agent

    require Logger
    Logger.debug("Message #{action_name}: #{message_type} from #{from_agent} to #{to_agent}")

    {:ok, result}
  end

  # Helper functions for message management

  @doc """
  Get messages for a specific agent in a coordination session.
  """
  def get_agent_messages(coordination_session_id, agent_type) do
    __MODULE__
    |> Ash.Query.filter(coordination_session_id: coordination_session_id)
    |> Ash.Query.filter(to_agent: agent_type)
    |> Ash.Query.filter(message_status: [:queued, :delivered])
    |> Ash.Query.sort(sent_at: :asc)
    |> Ash.read!()
  end

  @doc """
  Get negotiation messages for a specific negotiation.
  """
  def get_negotiation_messages(negotiation_id) do
    __MODULE__
    |> Ash.Query.filter(negotiation_id: negotiation_id)
    |> Ash.Query.sort(negotiation_round: :asc, sent_at: :asc)
    |> Ash.read!()
  end

  @doc """
  Get coordination session message statistics.
  """
  def get_session_message_stats(coordination_session_id) do
    messages =
      __MODULE__
      |> Ash.Query.filter(coordination_session_id: coordination_session_id)
      |> Ash.read!()

    by_type = Enum.group_by(messages, & &1.message_type)
    by_status = Enum.group_by(messages, & &1.message_status)
    by_agent = Enum.group_by(messages, & &1.from_agent)

    %{
      total_messages: length(messages),
      by_type: Enum.map(by_type, fn {type, msgs} -> {type, length(msgs)} end) |> Map.new(),
      by_status:
        Enum.map(by_status, fn {status, msgs} -> {status, length(msgs)} end) |> Map.new(),
      by_agent: Enum.map(by_agent, fn {agent, msgs} -> {agent, length(msgs)} end) |> Map.new(),
      message_flow: calculate_message_flow(messages)
    }
  end

  @doc """
  Clean up expired messages.
  """
  def cleanup_expired_messages do
    expired_messages =
      __MODULE__
      |> Ash.read!()

    Enum.each(expired_messages, fn message ->
      expire_message(message)
    end)

    length(expired_messages)
  end

  @doc """
  Get messages that need retry.
  """
  def get_retry_messages(_max_retries \\ 3) do
    __MODULE__
    |> Ash.Query.filter(message_status: :failed)
    |> Ash.read!()
  end

  # Private helper functions

  defp calculate_message_flow(messages) do
    flows = Enum.map(messages, fn msg -> "#{msg.from_agent}->#{msg.to_agent}" end)

    Enum.reduce(flows, %{}, fn flow, acc ->
      Map.update(acc, flow, 1, &(&1 + 1))
    end)
  end
end
