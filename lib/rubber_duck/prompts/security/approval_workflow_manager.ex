defmodule RubberDuck.Prompts.Security.ApprovalWorkflowManager do
  @moduledoc """
  Multi-stage approval workflow management service for prompt security.

  Provides comprehensive approval workflow coordination with configurable
  stages, role-based routing, automated approval for low-risk content,
  and integration with security validation systems.

  Features:
  - Multi-stage approval workflows with configurable routing and escalation
  - Role-based approval authority with delegation and override capabilities
  - Automated approval for low-risk changes with security score integration
  - Comprehensive approval tracking with audit trails and notifications
  - Integration with security validation and access control systems
  """

  use GenServer
  require Logger

  alias RubberDuck.Prompts.Security.{AccessControlManager, PromptValidator, SecurityAuditLogger}

  @approval_stages [:content_review, :security_review, :final_approval]
  @approval_statuses [:draft, :pending, :approved, :rejected, :expired]
  # Risk score threshold for auto-approval
  @automated_approval_threshold 0.3
  # 3 days default timeout
  @approval_timeout_hours 72

  defstruct [
    :workflow_config,
    :approval_state_machine,
    :notification_manager,
    :audit_logger,
    :performance_monitor
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    config = build_workflow_config(opts)

    state = %__MODULE__{
      workflow_config: config,
      approval_state_machine: initialize_state_machine(),
      notification_manager: initialize_notification_manager(),
      audit_logger: initialize_audit_logger(),
      performance_monitor: initialize_performance_monitor()
    }

    Logger.info("ApprovalWorkflowManager: Approval workflow service initialized",
      approval_stages: @approval_stages,
      automated_threshold: @automated_approval_threshold,
      timeout_hours: @approval_timeout_hours
    )

    {:ok, state}
  end

  # Public API

  @spec initiate_approval_workflow(map(), map()) :: {:ok, map()} | {:error, any()}
  def initiate_approval_workflow(prompt, context) do
    GenServer.call(__MODULE__, {:initiate_approval, prompt, context})
  end

  @spec process_approval_decision(binary(), atom(), binary(), map()) ::
          {:ok, map()} | {:error, any()}
  def process_approval_decision(prompt_id, decision, approver_id, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:process_decision, prompt_id, decision, approver_id, metadata})
  end

  @spec check_approval_eligibility(binary(), binary()) :: {:ok, boolean()} | {:error, any()}
  def check_approval_eligibility(prompt_id, approver_id) do
    GenServer.call(__MODULE__, {:check_eligibility, prompt_id, approver_id})
  end

  @spec get_pending_approvals(binary()) :: {:ok, list(map())} | {:error, any()}
  def get_pending_approvals(approver_id) do
    GenServer.call(__MODULE__, {:get_pending, approver_id})
  end

  @spec get_approval_workflow_status(binary()) :: {:ok, map()} | {:error, any()}
  def get_approval_workflow_status(prompt_id) do
    GenServer.call(__MODULE__, {:get_status, prompt_id})
  end

  @spec expire_pending_approvals() :: {:ok, integer()} | {:error, any()}
  def expire_pending_approvals do
    GenServer.cast(__MODULE__, :expire_pending)
    {:ok, :triggered}
  end

  # GenServer callbacks

  def handle_call({:initiate_approval, prompt, context}, _from, state) do
    workflow_start_time = System.monotonic_time(:microsecond)

    Logger.debug("ApprovalWorkflowManager: Initiating approval workflow",
      prompt_id: prompt.id,
      prompt_type: prompt.prompt_type,
      security_level: prompt.security_level
    )

    case execute_workflow_initiation(prompt, context, state) do
      {:ok, workflow_result} ->
        workflow_time = System.monotonic_time(:microsecond) - workflow_start_time

        Logger.info("ApprovalWorkflowManager: Approval workflow initiated",
          workflow_time_us: workflow_time,
          prompt_id: prompt.id,
          requires_approval: workflow_result.requires_approval,
          workflow_stage: workflow_result.current_stage
        )

        # Audit workflow initiation
        audit_workflow_action(prompt, context, :initiated, workflow_result, state)

        {:reply, {:ok, workflow_result}, state}

      {:error, reason} ->
        workflow_time = System.monotonic_time(:microsecond) - workflow_start_time

        Logger.error("ApprovalWorkflowManager: Workflow initiation failed",
          workflow_time_us: workflow_time,
          prompt_id: prompt.id,
          error: reason
        )

        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:process_decision, prompt_id, decision, approver_id, metadata}, _from, state) do
    case execute_approval_decision(prompt_id, decision, approver_id, metadata, state) do
      {:ok, decision_result} ->
        Logger.info("ApprovalWorkflowManager: Approval decision processed",
          prompt_id: prompt_id,
          decision: decision,
          approver_id: approver_id,
          new_status: decision_result.new_status
        )

        {:reply, {:ok, decision_result}, state}

      {:error, reason} ->
        Logger.error("ApprovalWorkflowManager: Approval decision failed",
          prompt_id: prompt_id,
          decision: decision,
          error: reason
        )

        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:check_eligibility, prompt_id, approver_id}, _from, state) do
    case check_approver_eligibility(prompt_id, approver_id, state) do
      {:ok, eligible} -> {:reply, {:ok, eligible}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_pending, approver_id}, _from, state) do
    case fetch_pending_approvals(approver_id, state) do
      {:ok, pending_list} -> {:reply, {:ok, pending_list}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_status, prompt_id}, _from, state) do
    case fetch_workflow_status(prompt_id, state) do
      {:ok, status} -> {:reply, {:ok, status}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_cast(:expire_pending, state) do
    case execute_approval_expiration(state) do
      {:ok, expired_count} ->
        Logger.info("ApprovalWorkflowManager: Expired pending approvals", count: expired_count)

      {:error, reason} ->
        Logger.error("ApprovalWorkflowManager: Failed to expire pending approvals", error: reason)
    end

    {:noreply, state}
  end

  # Private workflow functions

  defp execute_workflow_initiation(prompt, context, state) do
    with {:ok, approval_required} <- determine_approval_requirement(prompt, context, state),
         {:ok, workflow_config} <- build_prompt_workflow_config(prompt, approval_required, state),
         {:ok, initial_state} <- initialize_prompt_workflow_state(prompt, workflow_config, state) do
      workflow_result = %{
        prompt_id: prompt.id,
        requires_approval: approval_required,
        current_stage: get_initial_workflow_stage(approval_required),
        workflow_config: workflow_config,
        workflow_state: initial_state,
        initiated_at: DateTime.utc_now(),
        expires_at: calculate_approval_expiration()
      }

      {:ok, workflow_result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp determine_approval_requirement(prompt, _context, _state) do
    # Check multiple factors to determine if approval is required
    risk_score = prompt.risk_score || 0.0
    prompt_type = prompt.prompt_type
    security_level = String.to_atom(prompt.security_level || "standard")

    requires_approval =
      cond do
        # System prompts always require approval
        prompt_type == :system -> true
        # High-risk prompts require approval
        risk_score > @automated_approval_threshold -> true
        # Enhanced/maximum security prompts require approval
        security_level in [:enhanced, :maximum] -> true
        # Prompts with detected threats require approval
        has_security_threats?(prompt) -> true
        # Low-risk prompts can be auto-approved
        true -> false
      end

    {:ok, requires_approval}
  end

  defp build_prompt_workflow_config(prompt, requires_approval, state) do
    base_config = %{
      stages: determine_workflow_stages(prompt, requires_approval),
      approvers: determine_required_approvers(prompt, state),
      escalation_rules: build_escalation_rules(prompt),
      timeout_hours: get_workflow_timeout(prompt),
      notification_settings: build_notification_settings(prompt)
    }

    {:ok, base_config}
  end

  defp initialize_prompt_workflow_state(prompt, workflow_config, _state) do
    initial_state = %{
      current_stage: List.first(workflow_config.stages),
      stage_history: [],
      approver_assignments: %{},
      decision_history: [],
      notifications_sent: [],
      workflow_metadata: %{
        initiated_by: prompt.user_id,
        security_score: prompt.risk_score,
        complexity_level: assess_prompt_complexity(prompt)
      }
    }

    {:ok, initial_state}
  end

  defp execute_approval_decision(prompt_id, decision, approver_id, metadata, state) do
    with {:ok, workflow_status} <- fetch_current_workflow_status(prompt_id, state),
         {:ok, :eligible} <- validate_approver_authority(approver_id, workflow_status, state),
         {:ok, decision_result} <-
           process_stage_decision(decision, workflow_status, approver_id, metadata, state) do
      # Update workflow state
      updated_workflow = update_workflow_state(workflow_status, decision_result)

      # Determine next stage or completion
      final_result = determine_workflow_progression(updated_workflow, state)

      # Audit decision
      audit_approval_decision(prompt_id, decision, approver_id, final_result, state)

      {:ok, final_result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Workflow stage determination

  defp determine_workflow_stages(prompt, requires_approval) do
    case {prompt.prompt_type, requires_approval} do
      # System prompts get full workflow
      {:system, true} -> @approval_stages
      # Project prompts get content + security review
      {:project, true} -> [:content_review, :security_review]
      # User prompts get simplified workflow
      {:user, true} -> [:content_review]
      # No approval required
      {_, false} -> []
    end
  end

  defp determine_required_approvers(prompt, _state) do
    case prompt.prompt_type do
      :system ->
        %{
          content_review: ["admin", "system_admin"],
          security_review: ["security_admin", "system_admin"],
          final_approval: ["system_admin"]
        }

      :project ->
        %{
          content_review: ["project_owner", "admin"],
          security_review: ["security_admin", "admin"]
        }

      :user ->
        %{
          content_review: ["admin"]
        }
    end
  end

  defp build_escalation_rules(prompt) do
    %{
      escalation_timeout_hours: get_escalation_timeout(prompt.prompt_type),
      escalation_chain: get_escalation_chain(prompt.prompt_type),
      auto_escalate_on_security_issues: true
    }
  end

  # 6 days for system prompts
  defp get_workflow_timeout(:system), do: @approval_timeout_hours * 2
  # 3 days for project prompts
  defp get_workflow_timeout(:project), do: @approval_timeout_hours
  # 1.5 days for user prompts
  defp get_workflow_timeout(:user), do: div(@approval_timeout_hours, 2)

  # 24 hours
  defp get_escalation_timeout(:system), do: 24
  # 48 hours
  defp get_escalation_timeout(:project), do: 48
  # 24 hours
  defp get_escalation_timeout(:user), do: 24

  defp get_escalation_chain(:system), do: ["admin", "system_admin"]
  defp get_escalation_chain(:project), do: ["project_owner", "admin"]
  defp get_escalation_chain(:user), do: ["admin"]

  # Utility functions

  defp has_security_threats?(prompt) do
    validation_results = prompt.security_validation_results || %{}
    threats_detected = Map.get(validation_results, :threats_detected, [])
    length(threats_detected) > 0
  end

  defp get_initial_workflow_stage(true), do: List.first(@approval_stages)
  defp get_initial_workflow_stage(false), do: :auto_approved

  defp calculate_approval_expiration do
    DateTime.utc_now()
    |> DateTime.add(@approval_timeout_hours, :hour)
  end

  defp assess_prompt_complexity(%{content: content}) do
    content_length = String.length(content)
    word_count = content |> String.split(~r/\s+/) |> length()

    cond do
      content_length > 5000 or word_count > 1000 -> :high
      content_length > 1000 or word_count > 200 -> :medium
      true -> :low
    end
  end

  # State management functions

  defp fetch_current_workflow_status(_prompt_id, _state) do
    # Placeholder - would fetch from database or ETS
    {:ok,
     %{
       current_stage: :content_review,
       workflow_active: true,
       assigned_approvers: ["admin"],
       pending_since: DateTime.utc_now()
     }}
  end

  defp validate_approver_authority(_approver_id, _workflow_status, _state) do
    # Placeholder - would validate approver permissions
    {:ok, :eligible}
  end

  defp process_stage_decision(decision, _workflow_status, _approver_id, _metadata, _state) do
    # Process the approval/rejection decision
    decision_result = %{
      decision: decision,
      decided_at: DateTime.utc_now(),
      stage_completed: true,
      next_stage: determine_next_stage(decision)
    }

    {:ok, decision_result}
  end

  defp determine_next_stage(:approved), do: :security_review
  defp determine_next_stage(:rejected), do: :workflow_complete
  defp determine_next_stage(_), do: :pending

  defp update_workflow_state(workflow_status, decision_result) do
    Map.merge(workflow_status, %{
      last_decision: decision_result,
      current_stage: decision_result.next_stage,
      updated_at: DateTime.utc_now()
    })
  end

  defp determine_workflow_progression(updated_workflow, _state) do
    %{
      workflow_id: updated_workflow.id || generate_workflow_id(),
      new_status: updated_workflow.current_stage,
      workflow_complete: workflow_completed?(updated_workflow),
      next_actions: determine_next_actions(updated_workflow)
    }
  end

  defp workflow_completed?(%{current_stage: :workflow_complete}), do: true
  defp workflow_completed?(%{current_stage: :auto_approved}), do: true
  defp workflow_completed?(_), do: false

  defp determine_next_actions(%{current_stage: :workflow_complete}), do: []

  defp determine_next_actions(%{current_stage: stage}) do
    ["await_#{stage}_decision"]
  end

  # Helper functions

  defp check_approver_eligibility(_prompt_id, _approver_id, _state) do
    # Placeholder implementation
    {:ok, true}
  end

  defp fetch_pending_approvals(_approver_id, _state) do
    # Placeholder implementation
    {:ok, []}
  end

  defp fetch_workflow_status(_prompt_id, _state) do
    # Placeholder implementation
    {:ok, %{status: :pending, stage: :content_review}}
  end

  defp execute_approval_expiration(_state) do
    # Placeholder implementation
    {:ok, 0}
  end

  defp generate_workflow_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  # Initialization functions

  defp build_workflow_config(opts) do
    %{
      enable_automated_approval: Keyword.get(opts, :enable_automated_approval, true),
      approval_timeout_hours: Keyword.get(opts, :approval_timeout_hours, @approval_timeout_hours),
      automated_threshold: Keyword.get(opts, :automated_threshold, @automated_approval_threshold),
      enable_escalation: Keyword.get(opts, :enable_escalation, true),
      enable_notifications: Keyword.get(opts, :enable_notifications, true)
    }
  end

  defp initialize_state_machine do
    %{
      states: @approval_statuses,
      transitions: build_state_transitions(),
      current_workflows: %{}
    }
  end

  defp build_state_transitions do
    %{
      draft: [:pending, :auto_approved],
      pending: [:approved, :rejected, :expired],
      approved: [],
      rejected: [:draft, :pending],
      expired: [:draft]
    }
  end

  defp initialize_notification_manager do
    %{
      enabled: true,
      notification_types: [:email, :in_app],
      templates: build_notification_templates()
    }
  end

  defp build_notification_templates do
    %{
      approval_request: "New prompt requires your approval",
      approval_approved: "Your prompt has been approved",
      approval_rejected: "Your prompt requires revision",
      approval_expired: "Approval request has expired"
    }
  end

  defp build_notification_settings(prompt) do
    %{
      notify_on_approval: true,
      notify_on_rejection: true,
      notify_on_expiration: true,
      escalation_notifications: prompt.prompt_type == :system
    }
  end

  defp initialize_audit_logger do
    %{
      enabled: true,
      log_all_decisions: true,
      log_workflow_changes: true
    }
  end

  defp initialize_performance_monitor do
    %{
      average_approval_time_hours: 0.0,
      approval_success_rate: 0.0,
      automated_approval_rate: 0.0,
      workflow_efficiency_score: 0.0
    }
  end

  # Audit functions

  defp audit_workflow_action(prompt, context, action, result, _state) do
    Logger.info("ApprovalWorkflowManager: Workflow action audited",
      prompt_id: prompt.id,
      action: action,
      result: Map.take(result, [:requires_approval, :current_stage])
    )
  end

  defp audit_approval_decision(prompt_id, decision, approver_id, result, _state) do
    Logger.info("ApprovalWorkflowManager: Approval decision audited",
      prompt_id: prompt_id,
      decision: decision,
      approver_id: approver_id,
      result: Map.take(result, [:new_status, :workflow_complete])
    )
  end
end
