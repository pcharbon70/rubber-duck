defmodule RubberDuck.Actions.SecurityMonitoring do
  @moduledoc """
  Security monitoring action with adaptive strategies and intelligence coordination.

  This action provides comprehensive security monitoring coordination with
  adaptive monitoring strategies and multi-agent intelligence sharing.
  """

  use Jido.Action,
    name: "security_monitoring",
    schema: [
      monitoring_scope: [type: :atom, required: true],
      monitoring_config: [type: :map, required: true],
      coordination_options: [type: :map, default: %{}]
    ]

  alias RubberDuck.Skills.LearningSkill

  @doc """
  Coordinate comprehensive security monitoring with adaptive strategies.
  """
  def run(
        %{monitoring_scope: scope, monitoring_config: config, coordination_options: options} =
          _params,
        context
      ) do
    with {:ok, monitoring_setup} <- initialize_monitoring(scope, config, context),
         {:ok, threat_monitoring} <- setup_threat_monitoring(monitoring_setup, context),
         {:ok, behavioral_monitoring} <- setup_behavioral_monitoring(monitoring_setup, context),
         {:ok, coordination_framework} <-
           establish_coordination_framework(monitoring_setup, options, context),
         {:ok, monitoring_result} <-
           activate_monitoring_systems(
             monitoring_setup,
             threat_monitoring,
             behavioral_monitoring,
             coordination_framework
           ) do
      # Track successful monitoring coordination for learning
      learning_context = %{
        monitoring_scope: scope,
        active_monitors: map_size(monitoring_result.active_monitors),
        coordination_agents: length(coordination_framework.participating_agents),
        monitoring_complexity: monitoring_result.complexity_level
      }

      LearningSkill.track_experience(
        %{
          experience: %{
            action: :security_monitoring,
            scope: scope,
            complexity: monitoring_result.complexity_level
          },
          outcome: :success,
          context: learning_context
        },
        context
      )

      {:ok,
       %{
         monitoring_setup: monitoring_setup,
         threat_monitoring: threat_monitoring,
         behavioral_monitoring: behavioral_monitoring,
         coordination_framework: coordination_framework,
         monitoring_result: monitoring_result
       }}
    else
      {:error, reason} ->
        # Track failed monitoring setup for learning
        learning_context = %{
          monitoring_scope: scope,
          error_reason: reason,
          failure_stage: determine_monitoring_failure_stage(reason)
        }

        LearningSkill.track_experience(
          %{
            experience: %{action: :security_monitoring, failed: true},
            outcome: :failure,
            context: learning_context
          },
          context
        )

        {:error, reason}
    end
  end

  # Private helper functions

  defp initialize_monitoring(scope, config, _context) do
    monitoring_setup = %{
      scope: scope,
      monitoring_targets: determine_monitoring_targets(scope, config),
      monitoring_frequency: Map.get(config, :frequency, :standard),
      alert_thresholds: Map.get(config, :alert_thresholds, default_alert_thresholds()),
      data_retention_policy: Map.get(config, :retention_policy, default_retention_policy()),
      monitoring_level: Map.get(config, :level, :standard),
      setup_timestamp: DateTime.utc_now()
    }

    {:ok, monitoring_setup}
  end

  defp setup_threat_monitoring(monitoring_setup, _context) do
    threat_monitoring_config = %{
      threat_detection_enabled: true,
      pattern_analysis_enabled: true,
      real_time_correlation: monitoring_setup.monitoring_level in [:high, :maximum],
      threat_intelligence_sharing: true,
      automated_response: monitoring_setup.monitoring_level == :maximum,
      monitoring_targets: monitoring_setup.monitoring_targets
    }

    # Initialize threat monitoring patterns
    threat_patterns = initialize_threat_patterns(monitoring_setup.scope)

    threat_monitoring = %{
      config: threat_monitoring_config,
      active_patterns: threat_patterns,
      detection_rules: generate_detection_rules(monitoring_setup),
      correlation_rules: generate_correlation_rules(monitoring_setup),
      response_protocols: generate_response_protocols(monitoring_setup),
      monitoring_state: :active,
      last_updated: DateTime.utc_now()
    }

    {:ok, threat_monitoring}
  end

  defp setup_behavioral_monitoring(monitoring_setup, _context) do
    behavioral_monitoring_config = %{
      user_behavior_tracking: true,
      session_analysis_enabled: true,
      anomaly_detection_threshold: determine_anomaly_threshold(monitoring_setup.monitoring_level),
      baseline_learning_enabled: true,
      adaptive_thresholds: monitoring_setup.monitoring_level in [:high, :maximum]
    }

    behavioral_monitoring = %{
      config: behavioral_monitoring_config,
      active_baselines: %{},
      behavior_patterns: %{},
      anomaly_detection_rules: generate_anomaly_detection_rules(monitoring_setup),
      learning_parameters: generate_learning_parameters(monitoring_setup),
      monitoring_state: :active,
      last_updated: DateTime.utc_now()
    }

    {:ok, behavioral_monitoring}
  end

  defp establish_coordination_framework(monitoring_setup, options, _context) do
    participating_agents = determine_participating_agents(monitoring_setup.scope, options)

    coordination_framework = %{
      participating_agents: participating_agents,
      communication_protocols: setup_communication_protocols(participating_agents),
      data_sharing_rules: establish_data_sharing_rules(participating_agents, monitoring_setup),
      escalation_procedures: create_escalation_procedures(monitoring_setup),
      coordination_schedule:
        determine_coordination_schedule(monitoring_setup.monitoring_frequency),
      framework_status: :active,
      established_at: DateTime.utc_now()
    }

    {:ok, coordination_framework}
  end

  defp activate_monitoring_systems(
         monitoring_setup,
         threat_monitoring,
         behavioral_monitoring,
         coordination_framework
       ) do
    # Activate all monitoring systems and establish coordination
    active_monitors = %{
      threat_monitor: %{
        status: :active,
        detection_rules: length(threat_monitoring.detection_rules),
        last_check: DateTime.utc_now()
      },
      behavioral_monitor: %{
        status: :active,
        tracked_users: map_size(behavioral_monitoring.active_baselines),
        last_analysis: DateTime.utc_now()
      },
      coordination_monitor: %{
        status: :active,
        agent_count: length(coordination_framework.participating_agents),
        last_coordination: DateTime.utc_now()
      }
    }

    monitoring_result = %{
      active_monitors: active_monitors,
      overall_status: :fully_operational,
      complexity_level: determine_monitoring_complexity(monitoring_setup, active_monitors),
      performance_metrics: initialize_performance_metrics(),
      activation_timestamp: DateTime.utc_now()
    }

    {:ok, monitoring_result}
  end

  # Configuration helper functions

  defp determine_monitoring_targets(scope, config) do
    base_targets =
      case scope do
        :global ->
          [:all_users, :all_sessions, :all_resources]

        :user_focused ->
          [:user_sessions, :user_permissions, :user_activities]

        :resource_focused ->
          [:resource_access, :permission_usage, :data_access]

        :threat_focused ->
          [:threat_patterns, :attack_vectors, :security_events]

        _ ->
          [:basic_security_events]
      end

    # Add custom targets from config
    custom_targets = Map.get(config, :additional_targets, [])
    base_targets ++ custom_targets
  end

  defp default_alert_thresholds do
    %{
      threat_level_critical: 0.9,
      threat_level_high: 0.7,
      anomaly_score_threshold: 0.6,
      failed_attempts_threshold: 5,
      geographic_anomaly_threshold: 3,
      escalation_threshold: 2
    }
  end

  defp default_retention_policy do
    %{
      security_events_days: 90,
      threat_patterns_days: 365,
      behavioral_data_days: 180,
      # 7 years for compliance
      audit_logs_days: 2555
    }
  end

  defp initialize_threat_patterns(scope) do
    case scope do
      :global ->
        %{
          brute_force_patterns: [],
          injection_patterns: [],
          escalation_patterns: [],
          anomaly_patterns: []
        }

      :threat_focused ->
        %{
          advanced_persistent_threats: [],
          zero_day_patterns: [],
          insider_threat_patterns: [],
          automated_attack_patterns: []
        }

      _ ->
        %{
          basic_threat_patterns: [],
          common_attack_vectors: []
        }
    end
  end

  defp generate_detection_rules(monitoring_setup) do
    # Generate detection rules based on monitoring scope and level
    base_rules = [
      %{name: "failed_login_detection", threshold: 5, window_minutes: 10},
      %{name: "geographic_anomaly", threshold: 3, window_minutes: 60},
      %{name: "privilege_escalation", threshold: 1, window_minutes: 5}
    ]

    enhanced_rules =
      if monitoring_setup.monitoring_level in [:high, :maximum] do
        [
          %{name: "behavioral_deviation", threshold: 0.7, window_minutes: 30},
          %{name: "session_anomaly", threshold: 0.6, window_minutes: 15},
          %{name: "access_pattern_anomaly", threshold: 0.8, window_minutes: 45}
        ]
      else
        []
      end

    base_rules ++ enhanced_rules
  end

  defp generate_correlation_rules(monitoring_setup) do
    if monitoring_setup.monitoring_level in [:high, :maximum] do
      [
        %{name: "coordinated_attack_detection", min_sources: 3, time_window: 300},
        %{name: "distributed_brute_force", min_attempts: 20, source_threshold: 5},
        %{name: "privilege_escalation_chain", max_time_between: 600, min_steps: 2}
      ]
    else
      [
        %{name: "basic_attack_correlation", min_events: 10, time_window: 600}
      ]
    end
  end

  defp generate_response_protocols(monitoring_setup) do
    protocols = %{
      immediate_response: %{
        threat_levels: [:critical],
        response_time_seconds: 30,
        auto_execute: monitoring_setup.monitoring_level == :maximum
      },
      escalated_response: %{
        threat_levels: [:high],
        response_time_seconds: 300,
        require_approval: monitoring_setup.monitoring_level != :maximum
      },
      standard_response: %{
        threat_levels: [:medium, :low],
        response_time_seconds: 1800,
        require_approval: true
      }
    }

    protocols
  end

  defp determine_anomaly_threshold(monitoring_level) do
    case monitoring_level do
      # Very sensitive
      :maximum -> 0.3
      # Sensitive
      :high -> 0.5
      # Moderate
      :standard -> 0.7
      # Conservative
      :low -> 0.8
      _ -> 0.7
    end
  end

  defp generate_anomaly_detection_rules(monitoring_setup) do
    base_rules = [
      %{type: :login_time_anomaly, threshold: 0.7},
      %{type: :access_pattern_anomaly, threshold: 0.6},
      %{type: :session_duration_anomaly, threshold: 0.8}
    ]

    if monitoring_setup.monitoring_level in [:high, :maximum] do
      base_rules ++
        [
          %{type: :micro_behavior_anomaly, threshold: 0.5},
          %{type: :interaction_pattern_anomaly, threshold: 0.6}
        ]
    else
      base_rules
    end
  end

  defp generate_learning_parameters(monitoring_setup) do
    %{
      learning_rate:
        case monitoring_setup.monitoring_level do
          # Fast learning
          :maximum -> 0.1
          # Moderate learning
          :high -> 0.05
          # Conservative learning
          _ -> 0.01
        end,
      baseline_window_days: 30,
      pattern_memory_limit: 1000,
      adaptation_threshold: 0.1
    }
  end

  defp determine_participating_agents(scope, options) do
    base_agents = [
      :security_monitor_sensor,
      :authentication_agent,
      :token_agent,
      :permission_agent
    ]

    additional_agents =
      case scope do
        :global ->
          # Include domain agents for global monitoring
          [:user_agent, :project_agent]

        :threat_focused ->
          # Security agents only
          []

        _ ->
          Map.get(options, :additional_agents, [])
      end

    base_agents ++ additional_agents
  end

  defp setup_communication_protocols(participating_agents) do
    # Setup communication protocols between participating agents
    protocols = %{
      threat_intelligence_sharing: %{
        participants: participating_agents,
        frequency: :real_time,
        data_types: [:threat_patterns, :risk_assessments, :behavioral_anomalies]
      },
      incident_coordination: %{
        participants: participating_agents,
        # seconds
        response_time_target: 60,
        escalation_chain: build_escalation_chain(participating_agents)
      },
      status_reporting: %{
        participants: participating_agents,
        frequency: :hourly,
        report_types: [:health_status, :threat_summary, :performance_metrics]
      }
    }

    protocols
  end

  defp establish_data_sharing_rules(_participating_agents, monitoring_setup) do
    sharing_rules = %{
      threat_data: %{
        sharing_level: monitoring_setup.monitoring_level,
        # days
        retention_period: 90,
        access_control: :security_agents_only
      },
      behavioral_data: %{
        sharing_level:
          if(monitoring_setup.monitoring_level in [:high, :maximum], do: :full, else: :limited),
        # days
        retention_period: 180,
        access_control: :authenticated_agents_only
      },
      performance_data: %{
        sharing_level: :full,
        # days
        retention_period: 30,
        access_control: :all_agents
      }
    }

    sharing_rules
  end

  defp create_escalation_procedures(monitoring_setup) do
    procedures = %{
      level_1_escalation: %{
        trigger_conditions: ["Multiple failed authentications", "Geographic anomaly detected"],
        response_time_minutes: 5,
        required_approvals: 0,
        auto_execute: monitoring_setup.monitoring_level == :maximum
      },
      level_2_escalation: %{
        trigger_conditions: ["Privilege escalation detected", "Data breach indicators"],
        response_time_minutes: 15,
        required_approvals: 1,
        auto_execute: false
      },
      level_3_escalation: %{
        trigger_conditions: ["System compromise indicators", "Advanced persistent threat"],
        response_time_minutes: 30,
        required_approvals: 2,
        auto_execute: false
      }
    }

    procedures
  end

  defp determine_coordination_schedule(monitoring_frequency) do
    case monitoring_frequency do
      :real_time ->
        %{
          status_sync_seconds: 30,
          threat_sync_seconds: 10,
          coordination_review_minutes: 60
        }

      :high ->
        %{
          status_sync_seconds: 60,
          threat_sync_seconds: 30,
          coordination_review_minutes: 120
        }

      :standard ->
        %{
          # 5 minutes
          status_sync_seconds: 300,
          # 2 minutes
          threat_sync_seconds: 120,
          # 6 hours
          coordination_review_minutes: 360
        }

      _ ->
        %{
          # 10 minutes
          status_sync_seconds: 600,
          # 5 minutes
          threat_sync_seconds: 300,
          # 12 hours
          coordination_review_minutes: 720
        }
    end
  end

  defp determine_monitoring_complexity(monitoring_setup, active_monitors) do
    complexity_factors = [
      length(monitoring_setup.monitoring_targets),
      map_size(active_monitors),
      if(monitoring_setup.monitoring_level == :maximum, do: 2, else: 1)
    ]

    total_complexity = Enum.sum(complexity_factors)

    cond do
      total_complexity > 15 -> :very_high
      total_complexity > 10 -> :high
      total_complexity > 6 -> :medium
      total_complexity > 3 -> :low
      true -> :minimal
    end
  end

  defp initialize_performance_metrics do
    %{
      events_processed_per_second: 0.0,
      average_detection_latency_ms: 0.0,
      false_positive_rate: 0.0,
      threat_detection_accuracy: 0.0,
      agent_coordination_efficiency: 0.0,
      system_resource_usage: 0.0
    }
  end

  defp build_escalation_chain(participating_agents) do
    # Build escalation chain based on agent capabilities
    security_agents =
      Enum.filter(participating_agents, fn agent ->
        agent in [
          :security_monitor_sensor,
          :authentication_agent,
          :token_agent,
          :permission_agent
        ]
      end)

    domain_agents = participating_agents -- security_agents

    %{
      primary_responders: security_agents,
      secondary_responders: domain_agents,
      escalation_order: security_agents ++ domain_agents
    }
  end

  defp determine_monitoring_failure_stage(reason) do
    case reason do
      :monitoring_initialization_failed -> :initialization
      :threat_monitoring_setup_failed -> :threat_setup
      :behavioral_monitoring_setup_failed -> :behavioral_setup
      :coordination_framework_failed -> :coordination
      :activation_failed -> :activation
      _ -> :unknown_failure
    end
  end
end
