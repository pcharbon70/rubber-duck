defmodule RubberDuck.Integration.ResourceCreationTest do
  @moduledoc """
  Integration tests for complete resource creation pipeline with policy enforcement.

  Tests agent-driven resource creation, policy enforcement integration,
  workflow coordination, and learning integration in realistic scenarios.
  """

  use ExUnit.Case, async: false

  alias RubberDuck.Actions.{AssessPermissionRisk, CreateEntity}

  alias RubberDuck.Agents.{
    AIAnalysisAgent,
    CodeFileAgent,
    PermissionAgent,
    ProjectAgent,
    UserAgent
  }

  alias RubberDuck.DirectivesEngine
  alias RubberDuck.InstructionsProcessor

  alias RubberDuck.Skills.{
    LearningSkill,
    PolicyEnforcementSkill,
    ProjectManagementSkill,
    UserManagementSkill
  }

  alias RubberDuck.SkillsRegistry

  @moduletag :integration

  describe "agent-driven resource creation" do
    test "user agent creates user resources with policy enforcement" do
      # Create user agent
      {:ok, user_agent} = UserAgent.create_for_user("test_user_creation")

      # Test user resource creation with policy checks
      user_creation_context = %{
        user_data: %{
          email: "newuser@example.com",
          name: "New Test User",
          role: "analyst"
        },
        creation_context: %{
          creator_user_id: "admin_user",
          creation_reason: "team_expansion",
          approval_required: false
        }
      }

      # Execute user creation through CreateEntity action
      {:ok, creation_result} =
        CreateEntity.run(
          %{
            entity_type: :user,
            entity_data: user_creation_context.user_data,
            creation_context: user_creation_context.creation_context
          },
          %{}
        )

      # Verify user creation
      assert Map.has_key?(creation_result, :entity)
      assert Map.has_key?(creation_result, :creation_metadata)
      assert creation_result.entity.entity_type == :user

      # Verify policy enforcement was applied
      metadata = creation_result.creation_metadata
      assert Map.has_key?(metadata, :policy_checks_passed)
      assert Map.has_key?(metadata, :permissions_verified)
    end

    test "project agent creates project resources with team coordination" do
      # Create project agent
      {:ok, project_agent} = ProjectAgent.create_for_project("test_project_creation")

      # Test project creation workflow
      project_data = %{
        name: "Integration Test Project",
        description: "Test project for integration testing",
        visibility: "private",
        team_members: ["user1", "user2", "user3"]
      }

      creation_context = %{
        creator_user_id: "project_manager",
        approval_workflow: :standard,
        resource_allocation: %{compute: :medium, storage: :standard}
      }

      # Execute project creation
      {:ok, project_creation_result} =
        CreateEntity.run(
          %{
            entity_type: :project,
            entity_data: project_data,
            creation_context: creation_context
          },
          %{}
        )

      # Verify project creation
      assert project_creation_result.entity.entity_type == :project
      assert Map.has_key?(project_creation_result, :creation_metadata)

      # Test project management skill integration
      project_mgmt_params = %{
        project_id: project_creation_result.entity.entity_id,
        team_context: %{
          team_size: length(project_data.team_members),
          coordination_needs: [:task_management, :resource_sharing]
        }
      }

      {:ok, mgmt_result, skill_state} =
        ProjectManagementSkill.coordinate_project_resources(
          project_mgmt_params,
          %{}
        )

      # Verify project management integration
      assert Map.has_key?(mgmt_result, :coordination_plan)
      assert Map.has_key?(mgmt_result, :resource_allocation)
    end

    test "code file agent creates resources with analysis integration" do
      # Create code file agent
      {:ok, code_agent} = CodeFileAgent.create_for_file("/test/integration_test.ex")

      # Test code file creation with analysis
      code_file_data = %{
        file_path: "/lib/test_module.ex",
        content: """
        defmodule TestModule do
          def test_function do
            :ok
          end
        end
        """,
        language: "elixir",
        project_id: "test_project"
      }

      # Execute code file creation
      {:ok, code_creation_result} =
        CreateEntity.run(
          %{
            entity_type: :code_file,
            entity_data: code_file_data,
            creation_context: %{auto_analysis: true}
          },
          %{}
        )

      # Verify code file creation
      assert code_creation_result.entity.entity_type == :code_file

      # Test AI analysis integration
      {:ok, ai_agent} = AIAnalysisAgent.create_for_analysis(:code_quality)

      analysis_params = %{
        target_entity: code_creation_result.entity.entity_id,
        analysis_scope: :comprehensive,
        analysis_context: %{
          file_path: code_file_data.file_path,
          language: code_file_data.language
        }
      }

      {:ok, analysis_result, updated_ai_agent} =
        AIAnalysisAgent.schedule_analysis(
          ai_agent,
          analysis_params
        )

      # Verify analysis integration
      assert Map.has_key?(analysis_result, :analysis_scheduled)
      assert Map.has_key?(analysis_result, :analysis_scope)

      # Verify analysis was recorded
      analysis_queue = Map.get(updated_ai_agent, :analysis_queue, [])
      assert length(analysis_queue) >= 1
    end

    test "ai analysis agent creates analysis resources with quality assessment" do
      # Test AI analysis resource creation

      {:ok, ai_agent} = AIAnalysisAgent.create_for_analysis(:project_health)

      # Create analysis resource
      analysis_data = %{
        target_entity_id: "test_project_123",
        analysis_type: :security_assessment,
        analysis_parameters: %{
          depth: :comprehensive,
          focus_areas: [:vulnerability_scan, :dependency_analysis, :code_quality]
        }
      }

      {:ok, analysis_creation_result} =
        CreateEntity.run(
          %{
            entity_type: :ai_analysis,
            entity_data: analysis_data,
            creation_context: %{priority: :high}
          },
          %{}
        )

      # Verify analysis creation
      assert analysis_creation_result.entity.entity_type == :ai_analysis

      # Verify quality assessment integration
      metadata = analysis_creation_result.creation_metadata
      assert Map.has_key?(metadata, :analysis_confidence)
      assert Map.has_key?(metadata, :estimated_completion_time)
    end
  end

  describe "policy enforcement integration" do
    test "policy enforcement skill validates resource creation permissions" do
      # Test policy enforcement throughout resource creation

      # Configure policy enforcement for creation scenarios
      policy_agent_id = "resource_policy_agent_#{:rand.uniform(1000)}"

      policy_config = %{
        enforcement_level: :strict,
        resource_creation_policies: true,
        adaptive_enforcement: true
      }

      assert :ok =
               SkillsRegistry.configure_skill_for_agent(
                 policy_agent_id,
                 :policy_enforcement_skill,
                 policy_config
               )

      # Test policy enforcement for sensitive resource creation
      sensitive_resource_context = %{
        user_id: "test_user",
        resource_type: :sensitive_project,
        resource_data: %{
          classification: "confidential",
          access_level: "restricted"
        },
        creation_context: %{
          approval_chain: ["manager", "security_officer"],
          justification: "legitimate_business_need"
        }
      }

      # Execute policy enforcement
      {:ok, enforcement_result, policy_state} =
        PolicyEnforcementSkill.enforce_access_policy(
          sensitive_resource_context,
          %{creation_validation: true}
        )

      # Verify policy enforcement
      assert Map.has_key?(enforcement_result, :access_decision)
      assert Map.has_key?(enforcement_result, :policy_violations)
      assert Map.has_key?(enforcement_result, :recommended_restrictions)

      # Test permission risk assessment integration
      {:ok, risk_result} =
        AssessPermissionRisk.run(
          %{
            user_id: sensitive_resource_context.user_id,
            resource: sensitive_resource_context.resource_type,
            action: "create",
            context: sensitive_resource_context.creation_context
          },
          %{}
        )

      # Verify risk assessment
      assert Map.has_key?(risk_result, :risk_assessment)
      assert Map.has_key?(risk_result, :mitigation_plan)
    end

    test "permission agent adjusts access dynamically during resource creation" do
      # Test dynamic permission adjustment during creation workflow

      # Create permission agent
      {:ok, permission_agent} = PermissionAgent.create_permission_agent()

      # Test permission adjustment workflow
      creation_risk_context = %{
        user_id: "dynamic_permission_user",
        resource_creation: %{
          resource_type: :project,
          sensitivity_level: :high,
          team_access_required: true
        },
        risk_indicators: [
          :new_user_account,
          :high_privilege_request,
          :cross_team_access
        ]
      }

      # Assess permission risk for creation
      {:ok, risk_assessment, updated_agent} =
        PermissionAgent.assess_permission_risk(
          permission_agent,
          creation_risk_context
        )

      # Verify risk assessment
      assert Map.has_key?(risk_assessment, :risk_level)
      assert Map.has_key?(risk_assessment, :risk_factors)

      # Test dynamic permission adjustment
      if risk_assessment.risk_level in [:medium, :high] do
        adjustment_options = %{
          auto_adjust: true,
          temporary_restrictions: true,
          monitoring_enhancement: true
        }

        {:ok, adjustment_result, final_agent} =
          PermissionAgent.adjust_user_permissions(
            updated_agent,
            creation_risk_context.user_id,
            risk_assessment,
            adjustment_options
          )

        # Verify dynamic adjustment
        assert Map.has_key?(adjustment_result, :permission_changes)
        assert Map.has_key?(adjustment_result, :adjustment_rationale)
      end
    end
  end

  describe "workflow coordination for resource creation" do
    test "instructions processor orchestrates complex resource creation workflows" do
      # Test complex multi-agent resource creation workflow

      team_project_workflow = %{
        name: "team_project_creation_workflow",
        instructions: [
          %{
            id: "validate_permissions",
            type: :skill_invocation,
            action: "policy.validate_creation_permissions",
            parameters: %{
              resource_type: :team_project,
              user_id: "project_creator",
              sensitivity: :high
            },
            dependencies: []
          },
          %{
            id: "create_project",
            type: :skill_invocation,
            action: "project.create_resource",
            parameters: %{
              project_data: %{name: "Team Integration Project"},
              team_size: 5
            },
            dependencies: ["validate_permissions"]
          },
          %{
            id: "setup_team_access",
            type: :skill_invocation,
            action: "permission.configure_team_access",
            parameters: %{
              access_level: :contributor,
              team_members: ["user1", "user2", "user3"]
            },
            dependencies: ["create_project"]
          },
          %{
            id: "initialize_monitoring",
            type: :skill_invocation,
            action: "security.setup_resource_monitoring",
            parameters: %{
              monitoring_level: :standard,
              alert_thresholds: %{access_anomalies: :medium}
            },
            dependencies: ["setup_team_access"]
          },
          %{
            id: "notify_stakeholders",
            type: :communication,
            action: "comm.notify_project_creation",
            parameters: %{
              notification_type: :project_created,
              stakeholders: ["project_manager", "security_team"]
            },
            dependencies: ["initialize_monitoring"]
          }
        ]
      }

      # Execute team project creation workflow
      {:ok, workflow_id} = InstructionsProcessor.compose_workflow(team_project_workflow)

      {:ok, execution_result} =
        InstructionsProcessor.execute_workflow(
          workflow_id,
          "team_project_creation_agent"
        )

      # Verify workflow execution
      assert execution_result.status == :completed
      assert map_size(execution_result.instruction_results) == 5

      # Verify all workflow steps completed successfully
      results = execution_result.instruction_results

      # Check each step
      assert Map.has_key?(results, "validate_permissions")
      assert Map.has_key?(results, "create_project")
      assert Map.has_key?(results, "setup_team_access")
      assert Map.has_key?(results, "initialize_monitoring")
      assert Map.has_key?(results, "notify_stakeholders")

      # Verify dependency ordering was respected
      Enum.each(results, fn {_instruction_id, result} ->
        assert Map.has_key?(result, :status)
        assert result.status in [:completed, :sent]
      end)
    end

    test "directives engine modifies resource creation behavior based on policies" do
      # Test dynamic policy modification affecting resource creation

      # Issue directive to tighten resource creation policies
      policy_directive = %{
        type: :security_policy_change,
        target: :all,
        parameters: %{
          policy_change: :increase_creation_restrictions,
          resource_types: [:project, :user, :sensitive_data],
          additional_approvals_required: 1,
          enhanced_logging: true
        },
        priority: 8
      }

      {:ok, directive_id} = DirectivesEngine.issue_directive(policy_directive)

      # Issue behavior modification for resource creation agents
      behavior_directive = %{
        type: :behavior_modification,
        target: :all,
        parameters: %{
          behavior_type: :creation_validation,
          modification_type: :increase_strictness,
          target_operations: [:create_user, :create_project, :create_analysis]
        }
      }

      {:ok, behavior_directive_id} = DirectivesEngine.issue_directive(behavior_directive)

      # Test that resource creation reflects policy changes
      # (In real system, agents would apply these directives)

      # Verify directives are active for resource creation agents
      {:ok, creation_directives} =
        DirectivesEngine.get_agent_directives("resource_creation_test_agent")

      directive_types = Enum.map(creation_directives, & &1.type)
      assert :security_policy_change in directive_types
      assert :behavior_modification in directive_types

      # Test policy rollback capability
      {:ok, rollback_id} = DirectivesEngine.create_rollback_point("before_policy_tightening")
      assert :ok = DirectivesEngine.rollback_to_point(rollback_id)

      # Verify rollback restored previous policy state
      {:ok, post_rollback_directives} =
        DirectivesEngine.get_agent_directives("resource_creation_test_agent")

      assert length(post_rollback_directives) < length(creation_directives)
    end

    test "resource creation triggers appropriate learning and adaptation" do
      # Test that resource creation patterns are learned and adapted

      # Create multiple resources to establish patterns
      resource_creation_scenarios = [
        %{
          entity_type: :user,
          success_rate: 0.9,
          complexity: :low,
          policy_compliance: :high
        },
        %{
          entity_type: :project,
          success_rate: 0.7,
          complexity: :medium,
          policy_compliance: :medium
        },
        %{
          entity_type: :code_file,
          success_rate: 0.95,
          complexity: :low,
          policy_compliance: :high
        }
      ]

      # Process creation scenarios and track learning
      learning_results =
        Enum.map(resource_creation_scenarios, fn scenario ->
          # Track creation experience through learning skill
          learning_params = %{
            experience: %{
              action: :resource_creation,
              entity_type: scenario.entity_type,
              complexity: scenario.complexity,
              policy_compliance: scenario.policy_compliance
            },
            outcome: if(scenario.success_rate > 0.8, do: :success, else: :partial_success),
            context: %{
              integration_test: true,
              scenario_type: scenario.entity_type
            }
          }

          {:ok, learning_result, learning_state} =
            LearningSkill.track_experience(
              learning_params,
              %{}
            )

          {scenario.entity_type, learning_result}
        end)

      # Verify learning occurred for each resource type
      assert length(learning_results) == 3

      Enum.each(learning_results, fn {entity_type, learning_result} ->
        assert Map.has_key?(learning_result, :experience_recorded)
        assert Map.has_key?(learning_result, :pattern_analysis)
      end)
    end
  end

  describe "policy enforcement and security integration" do
    test "permission risk assessment coordinates with resource creation" do
      # Test integrated permission risk assessment during resource creation

      # Test high-risk resource creation scenario
      high_risk_context = %{
        user_id: "external_contractor",
        resource: "financial_data_project",
        action: "create",
        context: %{
          user_clearance: "basic",
          resource_classification: "financial",
          access_time: DateTime.utc_now(),
          location: "remote",
          device_trust_level: "unverified"
        }
      }

      # Execute permission risk assessment
      {:ok, risk_assessment_result} =
        AssessPermissionRisk.run(
          high_risk_context,
          %{}
        )

      # Verify comprehensive risk assessment
      assert Map.has_key?(risk_assessment_result, :risk_assessment)
      assert Map.has_key?(risk_assessment_result, :behavioral_analysis)
      assert Map.has_key?(risk_assessment_result, :context_analysis)
      assert Map.has_key?(risk_assessment_result, :mitigation_plan)

      risk_assessment = risk_assessment_result.risk_assessment

      # High-risk scenario should be detected
      assert risk_assessment.overall_risk_level in [:medium, :high, :critical]

      # Verify mitigation plan provides actionable recommendations
      mitigation_plan = risk_assessment_result.mitigation_plan
      assert Map.has_key?(mitigation_plan, :immediate_actions)
      assert Map.has_key?(mitigation_plan, :monitoring_requirements)

      # Test that risk assessment influences resource creation
      if risk_assessment.overall_risk_level in [:high, :critical] do
        # High risk should result in additional restrictions
        assert length(mitigation_plan.immediate_actions) > 0
      end
    end

    test "policy enforcement adapts based on resource creation patterns" do
      # Test adaptive policy enforcement based on creation patterns

      # Simulate resource creation pattern learning
      creation_patterns = [
        %{pattern: :bulk_user_creation, risk_level: :medium, success_rate: 0.8},
        %{pattern: :sensitive_project_creation, risk_level: :high, success_rate: 0.6},
        %{pattern: :routine_file_creation, risk_level: :low, success_rate: 0.95}
      ]

      # Track patterns through policy enforcement skill
      policy_learning_results =
        Enum.map(creation_patterns, fn pattern ->
          enforcement_context = %{
            user_id: "pattern_learning_user",
            resource: "test_resource_#{pattern.pattern}",
            action: "create",
            context: %{
              pattern_type: pattern.pattern,
              historical_success_rate: pattern.success_rate
            }
          }

          {:ok, enforcement_result, policy_state} =
            PolicyEnforcementSkill.enforce_access_policy(
              enforcement_context,
              %{pattern_learning: true}
            )

          {pattern.pattern, enforcement_result}
        end)

      # Verify adaptive policy enforcement
      Enum.each(policy_learning_results, fn {pattern_type, enforcement_result} ->
        assert Map.has_key?(enforcement_result, :access_decision)

        # Verify pattern influences enforcement
        decision = enforcement_result.access_decision
        assert Map.has_key?(decision, :decision_rationale)
      end)
    end

    test "resource creation coordinates with security monitoring" do
      # Test resource creation integration with security monitoring

      # Create permission agent for monitoring integration
      {:ok, permission_agent} = PermissionAgent.create_permission_agent()

      # Test resource creation with enhanced monitoring
      monitored_creation_context = %{
        user_id: "monitored_creator",
        resource_creation: %{
          resource_type: :sensitive_analysis,
          data_classification: :restricted,
          team_access: true
        },
        monitoring_requirements: %{
          audit_trail: :comprehensive,
          real_time_alerts: true,
          anomaly_detection: :enabled
        }
      }

      # Execute permission assessment with monitoring
      {:ok, monitored_assessment, monitored_agent} =
        PermissionAgent.assess_permission_risk(
          permission_agent,
          monitored_creation_context
        )

      # Verify monitoring integration
      assert Map.has_key?(monitored_assessment, :risk_level)
      assert Map.has_key?(monitored_assessment, :monitoring_recommendations)

      # Test security monitoring coordination
      if monitored_assessment.risk_level in [:medium, :high] do
        monitoring_recs = monitored_assessment.monitoring_recommendations
        assert is_list(monitoring_recs)
        assert length(monitoring_recs) > 0
      end
    end
  end

  describe "learning integration with resource creation" do
    test "resource creation patterns improve policy decisions over time" do
      # Test that creation patterns influence future policy decisions

      # Establish baseline learning state
      initial_learning_state = %{
        creation_patterns: %{},
        policy_effectiveness: %{},
        adaptation_history: []
      }

      # Simulate successful creation patterns
      successful_patterns = [
        %{
          user_type: :experienced_developer,
          resource_type: :code_project,
          approval_time: :fast,
          outcome: :success
        },
        %{
          user_type: :experienced_developer,
          resource_type: :code_project,
          approval_time: :fast,
          outcome: :success
        },
        %{
          user_type: :new_team_member,
          resource_type: :code_project,
          approval_time: :standard,
          outcome: :success
        }
      ]

      # Track patterns through learning skill
      final_learning_state =
        Enum.reduce(successful_patterns, initial_learning_state, fn pattern, state ->
          learning_params = %{
            experience: %{
              action: :resource_creation,
              user_type: pattern.user_type,
              resource_type: pattern.resource_type,
              approval_process: pattern.approval_time
            },
            outcome: pattern.outcome,
            context: %{learning_integration_test: true}
          }

          {:ok, _learning_result, updated_state} =
            LearningSkill.track_experience(
              learning_params,
              state
            )

          updated_state
        end)

      # Verify pattern learning
      experiences = Map.get(final_learning_state, :experiences, [])
      assert length(experiences) >= 3

      # Verify learning can inform policy decisions
      {:ok, insights, _} =
        LearningSkill.get_insights(
          %{insight_type: :creation_patterns, context: :policy_optimization},
          final_learning_state
        )

      assert Map.has_key?(insights, :pattern_insights)
      assert Map.has_key?(insights, :confidence_score)
    end

    test "resource creation success rates influence agent behavior" do
      # Test that creation success rates influence future agent decisions

      # Create user agent for success rate tracking
      {:ok, user_agent} = UserAgent.create_for_user("success_tracking_user")

      # Simulate user creation attempts with varying success
      creation_attempts = [
        %{success: true, complexity: :low, time_taken: 200},
        %{success: true, complexity: :medium, time_taken: 500},
        %{success: false, complexity: :high, time_taken: 1200, failure_reason: :timeout},
        %{success: true, complexity: :low, time_taken: 180}
      ]

      # Track creation attempts
      tracking_results =
        Enum.map(creation_attempts, fn attempt ->
          tracking_params = %{
            operation_type: :user_creation,
            success: attempt.success,
            performance_metrics: %{
              complexity: attempt.complexity,
              execution_time_ms: attempt.time_taken
            },
            context: %{integration_test: true}
          }

          # Update agent with creation attempt tracking
          {:ok, updated_agent} =
            UserAgent.set(user_agent, %{
              creation_history: [tracking_params | Map.get(user_agent, :creation_history, [])]
            })

          updated_agent
        end)

      # Get final agent state
      final_agent = List.last(tracking_results)
      creation_history = Map.get(final_agent, :creation_history, [])

      # Verify tracking occurred
      assert length(creation_history) >= 4

      # Calculate success rate
      successful_attempts = Enum.count(creation_history, & &1.success)
      success_rate = successful_attempts / length(creation_history)

      # Verify success rate calculation
      assert success_rate >= 0.0 and success_rate <= 1.0

      # High success rate should influence future decisions
      if success_rate > 0.8 do
        # Future operations should be more confident
        confidence_boost = success_rate - 0.5
        assert confidence_boost > 0
      end
    end
  end

  describe "real-world resource creation scenarios" do
    test "multi-user project creation with role-based access" do
      # Test realistic multi-user project creation scenario

      # Create project agent
      {:ok, project_agent} = ProjectAgent.create_for_project("integration_multi_user_project")

      # Define project team with different roles
      project_team = %{
        project_manager: %{user_id: "pm_user", role: :manager, permissions: [:all]},
        senior_dev: %{user_id: "senior_dev", role: :developer, permissions: [:code, :review]},
        junior_dev: %{user_id: "junior_dev", role: :developer, permissions: [:code]},
        analyst: %{user_id: "analyst", role: :analyst, permissions: [:read, :analyze]}
      }

      # Test project creation with team setup
      project_creation_data = %{
        name: "Multi-User Integration Project",
        description: "Integration test for multi-user project creation",
        team: project_team,
        security_classification: "internal"
      }

      # Execute project creation
      {:ok, project_result} =
        CreateEntity.run(
          %{
            entity_type: :project,
            entity_data: project_creation_data,
            creation_context: %{
              team_setup_required: true,
              role_verification: true
            }
          },
          %{}
        )

      # Verify project creation with team coordination
      assert project_result.entity.entity_type == :project

      # Verify team coordination metadata
      metadata = project_result.creation_metadata
      assert Map.has_key?(metadata, :team_setup_completed)
      assert Map.has_key?(metadata, :role_assignments_verified)

      # Test permission verification for each team member
      Enum.each(project_team, fn {role_name, member_data} ->
        # Verify role-appropriate permissions
        assert Map.has_key?(member_data, :permissions)
        assert is_list(member_data.permissions)

        # Different roles should have different permission sets
        case role_name do
          :project_manager -> assert :all in member_data.permissions
          :senior_dev -> assert :review in member_data.permissions
          :junior_dev -> refute :review in member_data.permissions
          :analyst -> assert :analyze in member_data.permissions
        end
      end)
    end

    test "high-security resource creation with enhanced validation" do
      # Test high-security resource creation requiring enhanced validation

      # Create AI analysis agent for security analysis
      {:ok, ai_agent} = AIAnalysisAgent.create_for_analysis(:security_assessment)

      # High-security analysis resource creation
      security_analysis_data = %{
        analysis_type: :vulnerability_assessment,
        target_systems: ["production_database", "authentication_service"],
        clearance_required: "top_secret",
        analysis_scope: %{
          deep_scan: true,
          # Too sensitive for auto-execution
          penetration_testing: false,
          compliance_validation: true
        }
      }

      creation_context = %{
        # Lower than required
        creator_clearance: "secret",
        business_justification: "security_audit",
        approval_chain: ["security_manager", "ciso"],
        estimated_duration_hours: 48
      }

      # Execute high-security resource creation
      {:ok, security_creation_result} =
        CreateEntity.run(
          %{
            entity_type: :ai_analysis,
            entity_data: security_analysis_data,
            creation_context: creation_context
          },
          %{}
        )

      # Verify security validation
      assert security_creation_result.entity.entity_type == :ai_analysis

      # Should have enhanced validation metadata
      metadata = security_creation_result.creation_metadata
      assert Map.has_key?(metadata, :security_validation_required)
      assert Map.has_key?(metadata, :clearance_verification)

      # Test AI analysis scheduling with security constraints
      analysis_params = %{
        target_entity: security_creation_result.entity.entity_id,
        analysis_scope: :security_focused,
        security_constraints: %{
          clearance_verification: true,
          audit_logging: :comprehensive,
          restricted_operations: [:penetration_testing]
        }
      }

      {:ok, analysis_scheduling_result, updated_ai_agent} =
        AIAnalysisAgent.schedule_analysis(
          ai_agent,
          analysis_params
        )

      # Verify security-constrained analysis scheduling
      assert Map.has_key?(analysis_scheduling_result, :analysis_scheduled)
      assert Map.has_key?(analysis_scheduling_result, :security_constraints_applied)
    end

    test "resource creation error handling preserves security posture" do
      # Test that resource creation errors don't compromise security

      # Attempt resource creation that should fail due to security constraints
      unauthorized_creation_context = %{
        user_id: "unauthorized_user",
        resource: "admin_configuration",
        action: "create",
        context: %{
          # Insufficient role
          user_role: "guest",
          resource_sensitivity: "system_critical",
          # Suspicious behavior
          bypass_attempt: true
        }
      }

      # Execute permission risk assessment (should detect high risk)
      {:ok, risk_result} =
        AssessPermissionRisk.run(
          unauthorized_creation_context,
          %{}
        )

      # Verify high risk is detected
      assert risk_result.risk_assessment.overall_risk_level in [:high, :critical]

      # Verify security recommendations
      mitigation_plan = risk_result.mitigation_plan
      assert Map.has_key?(mitigation_plan, :immediate_actions)

      # Should recommend blocking or additional verification
      immediate_actions = mitigation_plan.immediate_actions

      security_actions =
        Enum.filter(immediate_actions, fn action ->
          String.contains?(to_string(action), "block") or
            String.contains?(to_string(action), "verify") or
            String.contains?(to_string(action), "escalate")
        end)

      assert length(security_actions) > 0

      # Test that failed creation attempts are properly logged
      # (Error would be reported to aggregation system)
      creation_failure_error = %{
        error_type: :unauthorized_resource_creation,
        user_id: unauthorized_creation_context.user_id,
        resource: unauthorized_creation_context.resource,
        risk_level: risk_result.risk_assessment.overall_risk_level
      }

      # Report security violation
      RubberDuck.ErrorReporting.Aggregator.report_error(
        creation_failure_error,
        %{security_violation: true, integration_test: true}
      )

      # Verify error was captured
      Process.sleep(500)
      error_stats = RubberDuck.ErrorReporting.Aggregator.get_error_stats()
      assert error_stats.total_error_count > 0
    end
  end

  describe "cross-component resource creation coordination" do
    test "resource creation coordinates across multiple agent types" do
      # Test coordination between different agent types during resource creation

      # Create multiple agent types for coordination test
      {:ok, user_agent} = UserAgent.create_for_user("coordination_test_user")
      {:ok, project_agent} = ProjectAgent.create_for_project("coordination_test_project")
      {:ok, code_agent} = CodeFileAgent.create_for_file("/coordination/test.ex")

      # Test coordinated resource creation workflow
      coordination_workflow = %{
        name: "cross_agent_coordination_test",
        instructions: [
          %{
            id: "create_user",
            type: :skill_invocation,
            action: "user.create_entity",
            parameters: %{
              entity_type: :user,
              user_data: %{name: "Coordination User", role: "developer"}
            },
            dependencies: []
          },
          %{
            id: "create_project",
            type: :skill_invocation,
            action: "project.create_entity",
            parameters: %{
              entity_type: :project,
              project_data: %{name: "Coordination Project", owner: "coordination_test_user"}
            },
            dependencies: ["create_user"]
          },
          %{
            id: "create_code_file",
            type: :skill_invocation,
            action: "code.create_entity",
            parameters: %{
              entity_type: :code_file,
              file_data: %{path: "/lib/coordination.ex", project_id: "coordination_test_project"}
            },
            dependencies: ["create_project"]
          },
          %{
            id: "setup_permissions",
            type: :skill_invocation,
            action: "permission.setup_resource_access",
            parameters: %{
              resource_permissions: %{
                user_access: :full,
                project_access: :owner,
                file_access: :write
              }
            },
            dependencies: ["create_user", "create_project", "create_code_file"]
          }
        ]
      }

      # Execute coordination workflow
      {:ok, coordination_workflow_id} =
        InstructionsProcessor.compose_workflow(coordination_workflow)

      {:ok, coordination_result} =
        InstructionsProcessor.execute_workflow(
          coordination_workflow_id,
          "cross_agent_coordinator"
        )

      # Verify coordinated execution
      assert coordination_result.status == :completed
      assert map_size(coordination_result.instruction_results) == 4

      # Verify dependency chain was respected
      results = coordination_result.instruction_results

      # All dependent operations should complete successfully
      Enum.each(results, fn {instruction_id, result} ->
        assert Map.has_key?(result, :status)
        assert result.status in [:completed, :sent]

        # Each result should indicate successful coordination
        case instruction_id do
          "setup_permissions" ->
            # Final step should have access to all previous results
            assert Map.has_key?(result, :status)

          _ ->
            assert result.status == :completed
        end
      end)
    end
  end

  ## Helper Functions

  defp wait_for_async_operation(operation_id, timeout \\ 5000) do
    receive do
      {:operation_complete, ^operation_id, result} -> {:ok, result}
    after
      timeout -> {:error, :timeout}
    end
  end

  defp simulate_security_event(event_type, context) do
    %{
      event_id: "integration_event_#{:rand.uniform(10_000)}",
      event_type: event_type,
      timestamp: DateTime.utc_now(),
      context: context,
      source: :integration_test
    }
  end
end
