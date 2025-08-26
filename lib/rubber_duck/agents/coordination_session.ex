defmodule RubberDuck.Agents.CoordinationSession do
  @moduledoc """
  Ash resource for tracking agent coordination sessions.

  Manages persistence of multi-agent evaluation sessions including
  session metadata, participating agents, and coordination outcomes.
  """

  use Ash.Resource,
    domain: RubberDuck.Agents,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshOban]

  require Ash.Query

  postgres do
    table "agent_coordination_sessions"
    repo RubberDuck.Repo
  end

  resource do
    description "Multi-agent coordination session tracking"
  end

  code_interface do
    define :create
    define :start_session
    define :complete_session
    define :fail_session
    define :cancel_session
    define :update_metrics
    define :read
  end

  actions do
    defaults [:read]

    create :create do
      accept [:session_id, :required_agents, :session_config]

      change set_attribute(:session_status, :initializing)
    end

    update :start_session do
      accept [:participating_agents]
      require_atomic? false

      change set_attribute(:session_status, :active)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :complete_session do
      accept [:consensus_achieved, :consensus_method, :coordination_metrics]

      change set_attribute(:session_status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
      change after_action({__MODULE__, :calculate_session_duration})
    end

    update :fail_session do
      accept [:failure_reason]

      change set_attribute(:session_status, :failed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
      change after_action({__MODULE__, :calculate_session_duration})
    end

    update :cancel_session do
      accept [:failure_reason]

      change set_attribute(:session_status, :cancelled)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
      change after_action({__MODULE__, :calculate_session_duration})
    end

    update :update_metrics do
      accept [:coordination_metrics]
    end
  end

  preparations do
    prepare build(load: [:agent_results, :coordination_messages])
  end

  changes do
    change before_action({__MODULE__, :set_session_defaults})
  end

  validations do
    validate present([:session_id, :required_agents])
  end

  attributes do
    uuid_primary_key :id

    attribute :session_id, :string do
      description "Unique session identifier for coordination"
      allow_nil? false
    end

    # attribute :evaluation_run_id, :uuid do
    #   description "Associated evaluation run"
    #   allow_nil? false
    # end

    attribute :required_agents, {:array, :atom} do
      description "List of required agent types for this session"
      allow_nil? false
    end

    attribute :participating_agents, :map do
      description "Map of agent_type -> agent_pid for active agents"
      default %{}
    end

    attribute :session_config, :map do
      description "Configuration for the coordination session"
      default %{}
    end

    attribute :session_status, :atom do
      description "Current status of the coordination session"
      constraints one_of: [:initializing, :active, :completing, :completed, :failed, :cancelled]
      default :initializing
    end

    attribute :started_at, :utc_datetime_usec do
      description "When the coordination session started"
      default &DateTime.utc_now/0
    end

    attribute :completed_at, :utc_datetime_usec do
      description "When the coordination session completed"
    end

    attribute :session_duration_ms, :integer do
      description "Total session duration in milliseconds"
    end

    attribute :coordination_metrics, :map do
      description "Metrics about the coordination process"
      default %{}
    end

    attribute :consensus_achieved, :boolean do
      description "Whether consensus was achieved between agents"
      default false
    end

    attribute :consensus_method, :atom do
      description "Method used to achieve consensus"
      constraints one_of: [:weighted_average, :majority_vote, :confidence_weighted, :negotiation]
    end

    attribute :failure_reason, :string do
      description "Reason for session failure, if applicable"
    end

    timestamps()
  end

  relationships do
    # belongs_to :evaluation_run, RubberDuck.Verdict.EvaluationRun  # Uncomment when EvaluationRun resource exists

    has_many :agent_results, RubberDuck.Agents.AgentEvaluationResult do
      destination_attribute :coordination_session_id
    end

    has_many :coordination_messages, RubberDuck.Agents.CoordinationMessage do
      destination_attribute :coordination_session_id
    end
  end

  calculations do
    calculate :is_active, :boolean, expr(session_status == :active)
    calculate :has_results, :boolean, expr(agent_count > 0)

    calculate :session_age_seconds,
              :integer,
              expr(fragment("EXTRACT(EPOCH FROM (? - ?))", now(), started_at))
  end

  aggregates do
    count :agent_count, :agent_results
    count :message_count, :coordination_messages

    max :latest_agent_result, :agent_results, :completed_at
  end

  # Custom validation functions

  def validate_agent_types(changeset, _opts) do
    case Ash.Changeset.get_attribute(changeset, :required_agents) do
      nil ->
        changeset

      agents when is_list(agents) ->
        valid_agents = [:code_quality, :architecture, :security, :test_quality]
        invalid_agents = agents -- valid_agents

        if length(invalid_agents) > 0 do
          Ash.Changeset.add_error(changeset,
            field: :required_agents,
            message: "Invalid agent types: #{inspect(invalid_agents)}"
          )
        else
          changeset
        end

      _ ->
        Ash.Changeset.add_error(changeset,
          field: :required_agents,
          message: "Required agents must be a list"
        )
    end
  end

  def validate_session_progression(changeset, _opts) do
    old_status = changeset.data.session_status
    new_status = Ash.Changeset.get_attribute(changeset, :session_status)

    valid_transitions = %{
      initializing: [:active, :cancelled, :failed],
      active: [:completing, :completed, :failed, :cancelled],
      completing: [:completed, :failed],
      completed: [],
      failed: [],
      cancelled: []
    }

    cond do
      new_status && old_status == new_status ->
        changeset

      new_status ->
        valid_next_statuses = Map.get(valid_transitions, old_status, [])

        if new_status in valid_next_statuses do
          changeset
        else
          Ash.Changeset.add_error(changeset,
            field: :session_status,
            message: "Invalid status transition from #{old_status} to #{new_status}"
          )
        end

      true ->
        changeset
    end
  end

  # Custom change functions

  def set_session_defaults(changeset, _opts) do
    changeset
    |> Ash.Changeset.change_attribute(:coordination_metrics, %{
      agents_spawned: 0,
      messages_exchanged: 0,
      consensus_attempts: 0,
      negotiation_rounds: 0
    })
  end

  def calculate_session_duration(changeset, _opts) do
    started_at = changeset.data.started_at
    completed_at = Ash.Changeset.get_attribute(changeset, :completed_at) || DateTime.utc_now()

    if started_at do
      duration_ms = DateTime.diff(completed_at, started_at, :millisecond)
      Ash.Changeset.change_attribute(changeset, :session_duration_ms, duration_ms)
    else
      changeset
    end
  end

  # Helper functions for coordination session management

  @doc """
  Find active coordination sessions for cleanup.
  """
  def get_active_sessions do
    __MODULE__
    |> Ash.Query.filter(session_status: :active)
    |> Ash.read!()
  end

  @doc """
  Get coordination session statistics.
  """
  def get_session_stats(session_id) do
    case Ash.get(__MODULE__, session_id) do
      {:ok, session} ->
        {:ok,
         %{
           session_id: session.session_id,
           status: session.session_status,
           agent_count: session.agent_count,
           message_count: session.message_count,
           duration_ms: session.session_duration_ms,
           consensus_achieved: session.consensus_achieved,
           started_at: session.started_at,
           completed_at: session.completed_at
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Clean up stale coordination sessions.
  """
  def cleanup_stale_sessions do
    stale_sessions = get_active_sessions()

    Enum.each(stale_sessions, fn session ->
      {:ok, _updated} =
        fail_session(session, %{
          failure_reason: "Session cleanup due to timeout"
        })
    end)

    length(stale_sessions)
  end
end
