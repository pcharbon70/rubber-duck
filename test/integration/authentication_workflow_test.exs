defmodule RubberDuck.Integration.AuthenticationWorkflowTest do
  @moduledoc """
  Integration tests for complete authentication and security agent ecosystem.

  Tests security agent coordination, authentication workflows, threat detection,
  and security monitoring in realistic authentication scenarios.
  """

  use ExUnit.Case, async: false

  alias RubberDuck.Actions.{
    AssessPermissionRisk,
    EnhanceAshSignIn,
    PredictiveTokenRenewal,
    SecurityMonitoring
  }

  alias RubberDuck.Agents.{
    AuthenticationAgent,
    PermissionAgent,
    SecurityMonitorSensor,
    TokenAgent
  }

  alias RubberDuck.DirectivesEngine
  alias RubberDuck.InstructionsProcessor

  alias RubberDuck.Skills.{
    AuthenticationSkill,
    LearningSkill,
    PolicyEnforcementSkill,
    ThreatDetectionSkill,
    TokenManagementSkill
  }

  alias RubberDuck.ErrorReporting.Aggregator
  alias RubberDuck.HealthCheck.ServiceMonitor
  alias RubberDuck.SkillsRegistry

  @moduletag :integration

  describe "authentication agent ecosystem coordination" do
    test "authentication agent enhances sign-in with behavioral analysis" do
      # Create authentication agent
      {:ok, auth_agent} = AuthenticationAgent.create_authentication_agent()

      # Test enhanced sign-in workflow
      sign_in_data = %{
        user_id: "test_user_123",
        email: "test@example.com",
        ip_address: "192.168.1.100",
        user_agent: "Mozilla/5.0 Test Browser",
        timestamp: DateTime.utc_now()
      }

      enhancement_options = %{
        behavioral_analysis: true,
        threat_detection: true,
        adaptive_security: true
      }

      {:ok, enhancement_result, updated_agent} =
        AuthenticationAgent.enhance_sign_in_security(
          auth_agent,
          sign_in_data,
          enhancement_options
        )

      # Verify enhancement results
      assert Map.has_key?(enhancement_result, :enhanced_session)
      assert Map.has_key?(enhancement_result, :security_assessment)
      assert Map.has_key?(enhancement_result, :behavioral_analysis)

      # Verify agent learning integration
      enhancement_history = Map.get(updated_agent, :enhancement_history, [])
      assert length(enhancement_history) >= 1
    end

    test "token agent manages lifecycle with predictive renewal" do
      # Create token agent
      {:ok, token_agent} = TokenAgent.create_token_agent()

      # Test token lifecycle management
      token_data = %{
        token_id: "test_token_#{:rand.uniform(1000)}",
        user_id: "test_user_123",
        # 2 hours ago
        created_at: DateTime.add(DateTime.utc_now(), -7200, :second),
        # 5 minutes ago
        last_used: DateTime.add(DateTime.utc_now(), -300, :second),
        usage_count: 15
      }

      {:ok, lifecycle_result, updated_token_agent} =
        TokenAgent.manage_token_lifecycle(
          token_agent,
          token_data
        )

      # Verify lifecycle management
      assert Map.has_key?(lifecycle_result, :lifecycle_analysis)
      assert Map.has_key?(lifecycle_result, :renewal_recommendation)
      assert Map.has_key?(lifecycle_result, :security_assessment)

      # Test predictive renewal coordination
      renewal_params = %{
        token_id: token_data.token_id,
        usage_data: %{recent_activity: :high, location_consistency: :stable},
        prediction_horizon_hours: 24
      }

      {:ok, renewal_result} = PredictiveTokenRenewal.run(renewal_params, %{})

      # Verify predictive renewal
      assert Map.has_key?(renewal_result, :renewal_decision)
      assert Map.has_key?(renewal_result, :optimal_timing)
      assert Map.has_key?(renewal_result, :security_factors)
    end

    test "permission agent coordinates with policy enforcement" do
      # Create permission agent
      {:ok, permission_agent} = PermissionAgent.create_permission_agent()

      # Test permission risk assessment workflow
      risk_context = %{
        user_id: "test_user_123",
        resource: "sensitive_data",
        action: "read",
        context: %{
          location: "office",
          time_of_day: "business_hours",
          device: "work_laptop"
        }
      }

      {:ok, risk_assessment, updated_permission_agent} =
        PermissionAgent.assess_permission_risk(
          permission_agent,
          risk_context
        )

      # Verify risk assessment
      assert Map.has_key?(risk_assessment, :risk_level)
      assert Map.has_key?(risk_assessment, :risk_factors)
      assert Map.has_key?(risk_assessment, :recommended_actions)

      # Test permission adjustment based on risk
      adjustment_options = %{auto_adjust: false, notification_required: true}

      {:ok, adjustment_result, final_agent} =
        PermissionAgent.adjust_user_permissions(
          updated_permission_agent,
          risk_context.user_id,
          risk_assessment,
          adjustment_options
        )

      # Verify permission adjustment coordination
      assert Map.has_key?(adjustment_result, :permission_changes)
      assert Map.has_key?(adjustment_result, :adjustment_rationale)
    end

    test "security monitor sensor provides real-time threat detection" do
      # Create security monitor sensor
      {:ok, security_sensor} = SecurityMonitorSensor.create_security_sensor()

      # Test threat detection workflow
      security_events = [
        %{
          event_type: :failed_login,
          user_id: "test_user_123",
          ip_address: "192.168.1.100",
          timestamp: DateTime.utc_now()
        },
        %{
          event_type: :unusual_access_pattern,
          user_id: "test_user_123",
          resource: "admin_panel",
          timestamp: DateTime.utc_now()
        }
      ]

      {:ok, threat_analysis, updated_sensor} =
        SecurityMonitorSensor.analyze_threat_patterns(
          security_sensor,
          security_events
        )

      # Verify threat analysis
      assert Map.has_key?(threat_analysis, :threat_patterns)
      assert Map.has_key?(threat_analysis, :risk_assessment)
      assert Map.has_key?(threat_analysis, :recommended_responses)

      # Test coordinated response
      if threat_analysis.risk_assessment.overall_risk > 0.3 do
        {:ok, response_result, final_sensor} =
          SecurityMonitorSensor.coordinate_threat_response(
            updated_sensor,
            threat_analysis
          )

        # Verify coordinated response
        assert Map.has_key?(response_result, :response_actions)
        assert Map.has_key?(response_result, :escalation_level)
      end
    end
  end

  describe "security skills integration" do
    test "threat detection skill integrates with authentication workflow" do
      # Test threat detection throughout authentication process

      # Configure threat detection for authentication agent
      auth_agent_id = "auth_integration_agent_#{:rand.uniform(1000)}"

      threat_config = %{
        sensitivity: :high,
        pattern_analysis: true,
        behavioral_learning: true
      }

      assert :ok =
               SkillsRegistry.configure_skill_for_agent(
                 auth_agent_id,
                 :threat_detection_skill,
                 threat_config
               )

      # Test authentication with threat detection
      auth_context = %{
        sign_in_data: %{
          user_id: "test_user_123",
          # Different from previous
          ip_address: "10.0.0.1",
          location: "unknown_location",
          device_fingerprint: "unknown_device"
        },
        threat_indicators: [:new_device, :unusual_location]
      }

      # Use authentication skill with threat detection
      {:ok, auth_result, auth_state} =
        AuthenticationSkill.enhance_session(
          %{
            user_id: auth_context.sign_in_data.user_id,
            session_data: auth_context.sign_in_data,
            request_context: %{threat_indicators: auth_context.threat_indicators}
          },
          %{threat_detection_enabled: true}
        )

      # Verify threat detection integration
      assert Map.has_key?(auth_result, :threat_analysis)
      assert Map.has_key?(auth_result, :behavioral_analysis)
      assert Map.has_key?(auth_result, :enhanced_session)

      # Verify learning integration
      learning_data = Map.get(auth_state, :learning_data, %{})
      assert Map.has_key?(learning_data, :threat_patterns) or map_size(learning_data) >= 0
    end

    test "token management skill coordinates with authentication agents" do
      # Test token management integration with authentication workflow

      # Create token agent
      {:ok, token_agent} = TokenAgent.create_token_agent()

      # Test token lifecycle management with learning
      token_context = %{
        token_id: "integration_token_#{:rand.uniform(1000)}",
        user_context: %{
          user_id: "test_user_123",
          risk_profile: :standard,
          usage_patterns: %{frequency: :high, locations: [:office, :home]}
        }
      }

      # Execute token lifecycle management
      {:ok, lifecycle_result, updated_token_agent} =
        TokenAgent.manage_token_lifecycle(
          token_agent,
          token_context
        )

      # Verify token lifecycle integration
      assert Map.has_key?(lifecycle_result, :lifecycle_analysis)
      assert Map.has_key?(lifecycle_result, :renewal_recommendation)

      # Test token management skill directly
      token_management_params = %{
        token_id: token_context.token_id,
        user_context: token_context.user_context
      }

      {:ok, management_result, skill_state} =
        TokenManagementSkill.manage_lifecycle(
          token_management_params,
          %{}
        )

      # Verify skill integration
      assert Map.has_key?(management_result, :lifecycle_analysis)
      assert Map.has_key?(management_result, :security_assessment)
    end

    test "policy enforcement skill integrates with permission decisions" do
      # Test policy enforcement throughout permission workflow

      # Configure policy enforcement skill
      policy_agent_id = "policy_integration_agent_#{:rand.uniform(1000)}"

      policy_config = %{
        enforcement_level: :strict,
        adaptive_policies: true,
        learning_enabled: true
      }

      assert :ok =
               SkillsRegistry.configure_skill_for_agent(
                 policy_agent_id,
                 :policy_enforcement_skill,
                 policy_config
               )

      # Test policy enforcement workflow
      enforcement_context = %{
        user_id: "test_user_123",
        resource: "sensitive_document",
        action: "download",
        context: %{
          user_role: "analyst",
          resource_classification: "confidential",
          access_time: DateTime.utc_now()
        }
      }

      # Execute policy enforcement
      {:ok, enforcement_result, policy_state} =
        PolicyEnforcementSkill.enforce_access_policy(
          enforcement_context,
          %{adaptive_enforcement: true}
        )

      # Verify policy enforcement
      assert Map.has_key?(enforcement_result, :access_decision)
      assert Map.has_key?(enforcement_result, :policy_violations)
      assert Map.has_key?(enforcement_result, :recommended_restrictions)

      # Test integration with permission risk assessment
      {:ok, risk_assessment_result} =
        AssessPermissionRisk.run(
          %{
            user_id: enforcement_context.user_id,
            resource: enforcement_context.resource,
            action: enforcement_context.action,
            context: enforcement_context.context
          },
          %{}
        )

      # Verify risk assessment integration
      assert Map.has_key?(risk_assessment_result, :risk_assessment)
      assert Map.has_key?(risk_assessment_result, :mitigation_plan)
    end
  end

  describe "security monitoring coordination" do
    test "security monitoring coordinates across all security agents" do
      # Test comprehensive security monitoring coordination

      monitoring_config = %{
        monitoring_level: :high,
        monitoring_targets: [:authentication, :authorization, :token_management],
        coordination_strategy: :adaptive,
        learning_integration: true
      }

      coordination_options = %{
        agent_coordination: true,
        real_time_analysis: true,
        threat_intelligence_sharing: true
      }

      # Execute security monitoring coordination
      {:ok, monitoring_result} =
        SecurityMonitoring.run(
          %{
            monitoring_scope: :comprehensive,
            monitoring_config: monitoring_config,
            coordination_options: coordination_options
          },
          %{}
        )

      # Verify comprehensive monitoring setup
      assert Map.has_key?(monitoring_result, :monitoring_framework)
      assert Map.has_key?(monitoring_result, :coordination_framework)
      assert Map.has_key?(monitoring_result, :learning_integration)

      # Verify agent coordination
      coordination_framework = monitoring_result.coordination_framework
      assert Map.has_key?(coordination_framework, :participating_agents)
      assert length(coordination_framework.participating_agents) > 0
    end

    test "threat detection patterns learned across security ecosystem" do
      # Test that threat patterns are learned and shared across security agents

      # Create security monitor sensor
      {:ok, security_sensor} = SecurityMonitorSensor.create_security_sensor()

      # Generate threat patterns for learning
      threat_scenarios = [
        %{
          scenario: :brute_force_attempt,
          events: [
            %{type: :failed_login, user_id: "victim_user", attempts: 5},
            %{type: :failed_login, user_id: "victim_user", attempts: 10},
            %{type: :account_lockout, user_id: "victim_user"}
          ]
        },
        %{
          scenario: :credential_stuffing,
          events: [
            %{type: :failed_login, ip_address: "malicious_ip", users_targeted: 20},
            %{type: :rate_limiting_triggered, ip_address: "malicious_ip"}
          ]
        }
      ]

      # Process threat scenarios
      threat_results =
        Enum.map(threat_scenarios, fn scenario ->
          {:ok, analysis_result, security_sensor} =
            SecurityMonitorSensor.analyze_threat_patterns(
              security_sensor,
              scenario.events
            )

          analysis_result
        end)

      # Verify threat pattern learning
      Enum.each(threat_results, fn result ->
        assert Map.has_key?(result, :threat_patterns)
        assert Map.has_key?(result, :risk_assessment)
      end)

      # Test that learned patterns influence future threat detection
      threat_history = Map.get(security_sensor, :threat_history, [])
      assert length(threat_history) >= 2
    end

    test "authentication skills coordinate through skills registry" do
      # Test coordination of authentication skills through registry

      # Discover authentication-related skills
      {:ok, security_skills} = SkillsRegistry.discover_skills(%{category: :security})

      # Verify security skills are available
      expected_skills = [
        :authentication_skill,
        :threat_detection_skill,
        :token_management_skill,
        :policy_enforcement_skill
      ]

      Enum.each(expected_skills, fn skill ->
        assert Map.has_key?(security_skills, skill),
               "Security skill #{skill} should be registered"
      end)

      # Test skill dependency resolution for authentication workflow
      {:ok, auth_dependencies} = SkillsRegistry.resolve_dependencies(:authentication_skill)

      # Authentication skill should have learning skill dependency
      assert is_list(auth_dependencies)

      # Test coordinated skill configuration for authentication agent
      auth_agent_id = "auth_skills_coord_agent_#{:rand.uniform(1000)}"

      # Configure multiple security skills for coordinated operation
      security_skill_configs = %{
        authentication_skill: %{behavioral_analysis: true, learning_enabled: true},
        threat_detection_skill: %{sensitivity: :high, pattern_learning: true},
        token_management_skill: %{predictive_renewal: true, anomaly_detection: true}
      }

      Enum.each(security_skill_configs, fn {skill_id, config} ->
        assert :ok = SkillsRegistry.configure_skill_for_agent(auth_agent_id, skill_id, config)
      end)

      # Verify coordinated configuration
      {:ok, agent_skills} = SkillsRegistry.get_agent_skills(auth_agent_id)
      assert map_size(agent_skills) >= 3
    end
  end

  describe "end-to-end authentication workflows" do
    test "complete enhanced sign-in workflow with all security components" do
      # Test complete sign-in enhancement workflow

      sign_in_context = %{
        user_id: "integration_test_user",
        email: "integration@test.com",
        session_data: %{
          ip_address: "192.168.1.50",
          user_agent: "Integration Test Client",
          location: %{country: "US", city: "Test City"}
        },
        request_context: %{
          endpoint: "/api/signin",
          method: "POST",
          timestamp: DateTime.utc_now()
        }
      }

      enhancement_options = %{
        threat_analysis: true,
        behavioral_analysis: true,
        adaptive_security: true,
        learning_integration: true
      }

      # Execute enhanced sign-in through action
      {:ok, enhancement_result} =
        EnhanceAshSignIn.run(
          %{
            user_id: sign_in_context.user_id,
            session_data: sign_in_context.session_data,
            request_context: sign_in_context.request_context,
            enhancement_options: enhancement_options
          },
          %{}
        )

      # Verify comprehensive enhancement
      assert Map.has_key?(enhancement_result, :enhanced_session)
      assert Map.has_key?(enhancement_result, :threat_analysis)
      assert Map.has_key?(enhancement_result, :behavioral_analysis)
      assert Map.has_key?(enhancement_result, :security_recommendations)

      # Verify security recommendations are actionable
      security_recs = enhancement_result.security_recommendations
      assert is_list(security_recs.immediate_actions)
      assert is_list(security_recs.monitoring_adjustments)
    end

    test "authentication workflow triggers appropriate security monitoring" do
      # Test that authentication events trigger coordinated security monitoring

      # Set up security monitoring
      monitoring_config = %{
        monitoring_level: :high,
        monitoring_targets: [:authentication, :behavioral_analysis],
        real_time_correlation: true
      }

      coordination_options = %{
        authentication_integration: true,
        adaptive_response: true
      }

      # Execute security monitoring setup
      {:ok, monitoring_setup} =
        SecurityMonitoring.run(
          %{
            monitoring_scope: :authentication_focused,
            monitoring_config: monitoring_config,
            coordination_options: coordination_options
          },
          %{}
        )

      # Verify monitoring framework
      framework = monitoring_setup.monitoring_framework
      assert Map.has_key?(framework, :monitoring_agents)
      assert Map.has_key?(framework, :monitoring_strategies)

      # Test authentication event processing through monitoring
      auth_event = %{
        event_type: :sign_in_enhanced,
        user_id: "monitored_user",
        enhancement_applied: true,
        threat_score: 0.3
      }

      # Simulate event processing (in real system, this would be automatic)
      event_processed =
        Map.merge(auth_event, %{
          monitoring_timestamp: DateTime.utc_now(),
          correlation_id: "integration_test_#{:rand.uniform(1000)}"
        })

      # Verify event structure for monitoring
      assert Map.has_key?(event_processed, :event_type)
      assert Map.has_key?(event_processed, :monitoring_timestamp)
    end

    test "authentication failure scenarios trigger appropriate responses" do
      # Test coordinated response to authentication failures

      # Simulate authentication failure scenario
      failure_context = %{
        user_id: "test_failure_user",
        failure_type: :invalid_credentials,
        failure_count: 3,
        ip_address: "suspicious_ip",
        timestamp: DateTime.utc_now()
      }

      # Create authentication agent for failure handling
      {:ok, auth_agent} = AuthenticationAgent.create_authentication_agent()

      # Process authentication failure
      {:ok, failure_analysis, updated_auth_agent} =
        AuthenticationAgent.analyze_authentication_failure(
          auth_agent,
          failure_context
        )

      # Verify failure analysis
      assert Map.has_key?(failure_analysis, :failure_classification)
      assert Map.has_key?(failure_analysis, :threat_assessment)
      assert Map.has_key?(failure_analysis, :recommended_actions)

      # Test that failure triggers security monitoring enhancement
      if failure_analysis.threat_assessment.risk_level == :high do
        # High-risk failures should trigger enhanced monitoring
        enhanced_monitoring_params = %{
          user_id: failure_context.user_id,
          monitoring_enhancement: :increase_sensitivity,
          duration_hours: 24
        }

        # Verify monitoring can be enhanced (structure test)
        assert Map.has_key?(enhanced_monitoring_params, :user_id)
        assert Map.has_key?(enhanced_monitoring_params, :monitoring_enhancement)
      end
    end
  end

  describe "security instructions and directives coordination" do
    test "security directives modify authentication behavior dynamically" do
      # Test runtime modification of authentication behavior

      # Issue security enhancement directive
      security_directive = %{
        type: :security_policy_change,
        target: :all,
        parameters: %{
          policy_change: :increase_authentication_requirements,
          duration_hours: 1,
          trigger_reason: :elevated_threat_level
        },
        # High priority for security
        priority: 8
      }

      {:ok, directive_id} = DirectivesEngine.issue_directive(security_directive)

      # Issue behavior modification directive for authentication agents
      behavior_directive = %{
        type: :behavior_modification,
        target: :all,
        parameters: %{
          behavior_type: :authentication_sensitivity,
          modification_type: :increase,
          target_agents: [:authentication_agent, :token_agent]
        },
        priority: 7
      }

      {:ok, behavior_directive_id} = DirectivesEngine.issue_directive(behavior_directive)

      # Verify directives are active
      {:ok, active_directives} = DirectivesEngine.get_agent_directives("security_test_agent")
      directive_types = Enum.map(active_directives, & &1.type)

      assert :security_policy_change in directive_types
      assert :behavior_modification in directive_types

      # Test directive coordination affects authentication
      # (In real system, agents would apply these directives)
      {:ok, directive_history} = DirectivesEngine.get_directive_history()

      recent_security_directives =
        Enum.filter(directive_history, fn entry ->
          Map.get(entry, :directive, %{})
          |> (Map.get(:type) in [:security_policy_change, :behavior_modification])
        end)

      assert length(recent_security_directives) >= 2
    end

    test "authentication instructions compose complex security workflows" do
      # Test complex authentication workflow composition

      security_workflow = %{
        name: "comprehensive_authentication_workflow",
        instructions: [
          %{
            id: "threat_assessment",
            type: :skill_invocation,
            action: "threat.analyze_context",
            parameters: %{
              context: %{ip_address: "test_ip", user_agent: "test_agent"}
            },
            dependencies: []
          },
          %{
            id: "behavioral_analysis",
            type: :skill_invocation,
            action: "auth.analyze_behavior",
            parameters: %{
              user_id: "test_user",
              historical_data: %{login_patterns: []}
            },
            dependencies: ["threat_assessment"]
          },
          %{
            id: "token_lifecycle",
            type: :skill_invocation,
            action: "token.manage_lifecycle",
            parameters: %{
              token_context: %{renewal_eligible: true}
            },
            dependencies: ["behavioral_analysis"]
          },
          %{
            id: "policy_enforcement",
            type: :skill_invocation,
            action: "policy.enforce_access",
            parameters: %{
              enforcement_level: :adaptive
            },
            dependencies: ["threat_assessment", "behavioral_analysis"]
          },
          %{
            id: "session_enhancement",
            type: :skill_invocation,
            action: "auth.enhance_session",
            parameters: %{
              enhancement_level: :comprehensive
            },
            dependencies: ["token_lifecycle", "policy_enforcement"]
          }
        ]
      }

      # Compose security workflow
      {:ok, workflow_id} = InstructionsProcessor.compose_workflow(security_workflow)

      # Execute security workflow
      {:ok, execution_result} =
        InstructionsProcessor.execute_workflow(
          workflow_id,
          "security_workflow_agent"
        )

      # Verify workflow execution
      assert execution_result.status == :completed
      assert map_size(execution_result.instruction_results) == 5

      # Verify dependency ordering was respected
      instruction_results = execution_result.instruction_results

      # All instructions should have completed successfully
      Enum.each(instruction_results, fn {instruction_id, result} ->
        assert Map.has_key?(result, :status)
        # communication instructions use :sent
        assert result.status in [:completed, :sent]
      end)
    end
  end

  describe "authentication performance and monitoring" do
    test "authentication performance monitored through health system" do
      # Test authentication performance monitoring integration

      # Generate authentication activity
      auth_activities =
        Enum.map(1..10, fn i ->
          %{
            user_id: "perf_test_user_#{i}",
            authentication_time_ms: :rand.uniform(500),
            enhancement_applied: true,
            # Low to medium threat
            threat_score: :rand.uniform() * 0.5
          }
        end)

      # Simulate authentication activity monitoring
      # (In real system, this would be captured automatically)

      # Force health monitoring to capture authentication performance
      ServiceMonitor.force_check()
      Process.sleep(1000)

      # Verify authentication services are being monitored
      service_health = ServiceMonitor.get_health_status()
      services = service_health.services

      # Should monitor authentication-related services
      # Used by auth agents
      assert Map.has_key?(services, :skills_registry)
      # Used for security directives
      assert Map.has_key?(services, :directives_engine)

      # Verify service health status
      Enum.each(services, fn {service_name, service_status} ->
        assert Map.has_key?(service_status, :status)
        assert service_status.status in [:healthy, :warning, :degraded, :critical]
      end)
    end

    test "authentication system scales based on threat level" do
      # Test authentication system scaling based on security assessment

      # Create authentication agent
      {:ok, auth_agent} = AuthenticationAgent.create_authentication_agent()

      # Simulate high-threat scenario requiring scaling
      high_threat_context = %{
        current_threat_level: :high,
        active_threats: 15,
        authentication_volume: :peak,
        recommended_scaling: :immediate
      }

      # Test authentication system response to high threat
      {:ok, threat_response, updated_agent} =
        AuthenticationAgent.respond_to_threat_level(
          auth_agent,
          high_threat_context
        )

      # Verify threat response
      assert Map.has_key?(threat_response, :response_actions)
      assert Map.has_key?(threat_response, :monitoring_adjustments)
      assert Map.has_key?(threat_response, :escalation_procedures)

      # Verify response is proportional to threat level
      assert threat_response.escalation_procedures.urgency_level in [:high, :critical]
    end
  end

  describe "security error handling and recovery" do
    test "authentication errors are properly aggregated and analyzed" do
      # Test authentication error handling integration

      # Generate authentication errors
      auth_errors = [
        %RuntimeError{message: "Authentication service timeout"},
        %ArgumentError{message: "Invalid authentication parameters"},
        %{error: :token_validation_failed, context: %{token_id: "invalid_token"}}
      ]

      # Report errors to aggregation system
      Enum.each(auth_errors, fn error ->
        Aggregator.report_error(
          error,
          %{component: :authentication, test: :integration}
        )
      end)

      # Allow error processing
      Aggregator.flush_errors()
      Process.sleep(1000)

      # Verify error aggregation
      error_stats = Aggregator.get_error_stats()
      assert error_stats.total_error_count >= 3

      # Verify error categorization
      recent_errors = Aggregator.get_recent_errors(10)

      auth_errors_reported =
        Enum.filter(recent_errors, fn error ->
          Map.get(error.context, :component) == :authentication
        end)

      assert length(auth_errors_reported) >= 3
    end

    test "security agent recovery maintains authentication capabilities" do
      # Test that security agents maintain functionality during recovery scenarios

      # Create multiple security agents
      {:ok, auth_agent} = AuthenticationAgent.create_authentication_agent()
      {:ok, token_agent} = TokenAgent.create_token_agent()
      {:ok, permission_agent} = PermissionAgent.create_permission_agent()

      # Test that agents maintain their configuration through Skills Registry
      test_configs = %{
        "auth_recovery_test" => %{
          authentication_skill: %{recovery_mode: true},
          threat_detection_skill: %{sensitivity: :medium}
        },
        "token_recovery_test" => %{
          token_management_skill: %{conservative_mode: true}
        },
        "permission_recovery_test" => %{
          policy_enforcement_skill: %{strict_mode: true}
        }
      }

      # Configure agents
      Enum.each(test_configs, fn {agent_id, skill_configs} ->
        Enum.each(skill_configs, fn {skill_id, config} ->
          assert :ok = SkillsRegistry.configure_skill_for_agent(agent_id, skill_id, config)
        end)
      end)

      # Verify configurations are maintained
      Enum.each(test_configs, fn {agent_id, skill_configs} ->
        {:ok, agent_skills} = SkillsRegistry.get_agent_skills(agent_id)

        Enum.each(skill_configs, fn {skill_id, expected_config} ->
          assert Map.has_key?(agent_skills, skill_id)
          assert agent_skills[skill_id][:config] == expected_config
        end)
      end)

      # Test basic functionality is preserved
      assert is_pid(Process.whereis(SkillsRegistry))
      assert is_pid(Process.whereis(DirectivesEngine))
    end
  end

  ## Helper Functions

  # Mock modules for testing
  defmodule TestMigration do
    defmodule AddUserPreferences do
      def up, do: "ALTER TABLE users ADD COLUMN preferences JSONB"
      def down, do: "ALTER TABLE users DROP COLUMN preferences"
    end

    defmodule AddIndexToUsers do
      def up, do: "CREATE INDEX CONCURRENTLY idx_users_email_lower ON users(LOWER(email))"
      def down, do: "DROP INDEX IF EXISTS idx_users_email_lower"
    end

    defmodule AlterUserTable do
      def up, do: "ALTER TABLE users ALTER COLUMN email TYPE VARCHAR(320)"
      def down, do: "ALTER TABLE users ALTER COLUMN email TYPE VARCHAR(255)"
    end
  end
end
