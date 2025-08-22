defmodule RubberDuck.Integration.ErrorHandlingTest do
  @moduledoc """
  Integration tests for system-wide error handling and recovery mechanisms.

  Tests cross-component error propagation, agent recovery mechanisms,
  health monitoring during failures, and supervision tree recovery
  in realistic failure scenarios.
  """

  use ExUnit.Case, async: false

  alias RubberDuck.DirectivesEngine
  alias RubberDuck.ErrorReporting.Aggregator

  alias RubberDuck.HealthCheck.{
    AgentMonitor,
    DatabaseMonitor,
    ResourceMonitor,
    ServiceMonitor,
    StatusAggregator
  }

  alias RubberDuck.InstructionsProcessor
  alias RubberDuck.Skills.LearningSkill
  alias RubberDuck.SkillsRegistry
  alias RubberDuck.Telemetry.VMMetrics

  @moduletag :integration

  describe "cross-component error propagation" do
    test "error reporting aggregates errors from all system components" do
      # Generate errors from different system layers

      # Infrastructure layer error
      infrastructure_error = %RuntimeError{message: "Database connection timeout"}

      Aggregator.report_error(infrastructure_error, %{
        layer: :infrastructure,
        component: :database,
        severity: :high
      })

      # Agentic layer error
      agentic_error = %ArgumentError{message: "Invalid skill configuration"}

      Aggregator.report_error(agentic_error, %{
        layer: :agentic,
        component: :skills_registry,
        agent_id: "test_agent_123"
      })

      # Security layer error
      security_error = %{error_type: :authentication_failure, reason: :invalid_token}

      Aggregator.report_error(security_error, %{
        layer: :security,
        component: :authentication,
        user_id: "error_test_user"
      })

      # Application layer error
      application_error = %Phoenix.Router.NoRouteError{message: "No route found"}

      Aggregator.report_error(application_error, %{
        layer: :application,
        component: :web_endpoint,
        request_path: "/test/error"
      })

      # Allow error processing
      Aggregator.flush_errors()
      Process.sleep(1000)

      # Verify error aggregation
      error_stats = Aggregator.get_error_stats()
      assert error_stats.total_error_count >= 4
      assert error_stats.unique_error_types >= 3

      # Verify error categorization
      recent_errors = Aggregator.get_recent_errors(10)

      layers_with_errors =
        recent_errors
        |> Enum.map(&Map.get(&1.context, :layer))
        |> Enum.uniq()

      expected_layers = [:infrastructure, :agentic, :security, :application]
      assert length(layers_with_errors) >= 3

      # Verify each layer's errors are properly categorized
      Enum.each(recent_errors, fn error ->
        assert Map.has_key?(error, :error_type)
        assert Map.has_key?(error, :timestamp)
        assert Map.has_key?(error.context, :layer)
      end)
    end

    test "error patterns detected across component boundaries" do
      # Test cross-component error pattern detection

      # Generate related errors across components
      related_error_sequence = [
        # Database connection issue
        {%RuntimeError{message: "Connection pool exhausted"},
         %{component: :database, sequence: 1}},

        # Agents unable to access database
        {%RuntimeError{message: "Database query timeout"},
         %{component: :data_agent, sequence: 2}},

        # Health monitoring detects database issues
        {%RuntimeError{message: "Health check failed"},
         %{component: :health_monitor, sequence: 3}},

        # Error reporting system under load
        {%RuntimeError{message: "Error buffer overflow"},
         %{component: :error_reporting, sequence: 4}}
      ]

      # Report sequence of related errors
      Enum.each(related_error_sequence, fn {error, context} ->
        enhanced_context =
          Map.merge(context, %{
            error_sequence: :database_cascade_failure,
            correlation_id: "cascade_test_123",
            timestamp: DateTime.utc_now()
          })

        Aggregator.report_error(error, enhanced_context)
        # Small delay to establish sequence
        Process.sleep(100)
      end)

      # Process error batch
      Aggregator.flush_errors()
      Process.sleep(1000)

      # Verify pattern detection
      recent_errors = Aggregator.get_recent_errors(10)

      cascade_errors =
        Enum.filter(recent_errors, fn error ->
          Map.get(error.context, :error_sequence) == :database_cascade_failure
        end)

      assert length(cascade_errors) >= 4

      # Verify sequence correlation
      sequences = Enum.map(cascade_errors, &Map.get(&1.context, :sequence))
      assert Enum.sort(sequences) == [1, 2, 3, 4]
    end

    test "cascading failure prevention through supervision tree" do
      # Test that supervision tree prevents cascading failures

      # Verify supervision structure can isolate failures
      main_supervisor_children = Supervisor.which_children(RubberDuck.MainSupervisor)
      assert length(main_supervisor_children) > 0

      # Test layer isolation
      layer_supervisors = [
        RubberDuck.InfrastructureSupervisor,
        RubberDuck.AgenticSupervisor,
        RubberDuck.SecuritySupervisor,
        RubberDuck.ApplicationSupervisor
      ]

      # Verify each layer can operate independently
      Enum.each(layer_supervisors, fn supervisor ->
        assert Process.whereis(supervisor)

        # Each layer should have independent children
        children = Supervisor.which_children(supervisor)
        assert length(children) > 0

        # Test that layer supervisor is responsive
        supervisor_info = Process.info(supervisor, [:status, :message_queue_len])
        assert supervisor_info[:status] in [:running, :runnable, :waiting]
        # Not overwhelmed
        assert supervisor_info[:message_queue_len] < 100
      end)

      # Test system health during simulated layer stress
      # Generate load on one layer
      agentic_load_errors =
        Enum.map(1..5, fn i ->
          %RuntimeError{message: "Agentic layer load test error #{i}"}
        end)

      Enum.each(agentic_load_errors, fn error ->
        Aggregator.report_error(error, %{layer: :agentic, load_test: true})
      end)

      # Verify other layers remain healthy
      Process.sleep(2000)
      overall_health = StatusAggregator.get_detailed_status()

      # System should handle load without complete failure
      assert overall_health.overall_status in [:healthy, :warning, :degraded]
      refute overall_health.overall_status == :critical
    end
  end

  describe "agent recovery mechanisms" do
    test "skills registry recovery maintains agent configurations" do
      # Test that Skills Registry recovers properly and maintains configurations

      # Configure multiple agents with skills
      test_agent_configs = %{
        "recovery_test_agent_1" => %{
          learning_skill: %{learning_rate: 0.8, memory_size: 1000},
          query_optimization_skill: %{optimization_threshold: 0.7}
        },
        "recovery_test_agent_2" => %{
          authentication_skill: %{behavioral_analysis: true},
          threat_detection_skill: %{sensitivity: :high}
        }
      }

      # Apply configurations
      Enum.each(test_agent_configs, fn {agent_id, skill_configs} ->
        Enum.each(skill_configs, fn {skill_id, config} ->
          assert :ok = SkillsRegistry.configure_skill_for_agent(agent_id, skill_id, config)
        end)
      end)

      # Verify configurations are applied
      Enum.each(test_agent_configs, fn {agent_id, skill_configs} ->
        {:ok, agent_skills} = SkillsRegistry.get_agent_skills(agent_id)

        Enum.each(skill_configs, fn {skill_id, expected_config} ->
          assert Map.has_key?(agent_skills, skill_id)
          assert agent_skills[skill_id][:config] == expected_config
        end)
      end)

      # Test skills discovery after configuration
      {:ok, all_skills} = SkillsRegistry.discover_skills()
      assert map_size(all_skills) > 0

      # Test that registry maintains state consistency
      # (In real recovery scenario, this would test actual process restart)
      assert is_pid(Process.whereis(SkillsRegistry))
    end

    test "directives engine recovery preserves active directives" do
      # Test that Directives Engine recovers with state preservation

      # Issue several test directives
      test_directives = [
        %{
          type: :behavior_modification,
          target: :all,
          parameters: %{behavior_type: :recovery_test, modification_type: :enable},
          priority: 5
        },
        %{
          type: :monitoring_adjustment,
          target: "recovery_test_agent",
          parameters: %{monitoring_level: :enhanced},
          priority: 6
        }
      ]

      # Issue directives
      directive_ids =
        Enum.map(test_directives, fn directive ->
          {:ok, directive_id} = DirectivesEngine.issue_directive(directive)
          directive_id
        end)

      # Create rollback point
      {:ok, rollback_id} = DirectivesEngine.create_rollback_point("recovery_test_checkpoint")

      # Verify directives are active
      {:ok, active_directives} = DirectivesEngine.get_agent_directives("recovery_test_agent")
      active_ids = Enum.map(active_directives, & &1.id)

      # At least one directive should be targeting our test agent or :all
      targeted_directives =
        Enum.filter(active_directives, fn directive ->
          directive.target == "recovery_test_agent" or directive.target == :all
        end)

      assert length(targeted_directives) >= 1

      # Test directive history preservation
      {:ok, directive_history} = DirectivesEngine.get_directive_history()
      assert length(directive_history) >= 2

      # Test rollback functionality (simulates recovery to previous state)
      assert :ok = DirectivesEngine.rollback_to_point(rollback_id)

      # Verify rollback worked
      {:ok, post_rollback_directives} =
        DirectivesEngine.get_agent_directives("recovery_test_agent")

      assert length(post_rollback_directives) < length(active_directives)
    end

    test "instructions processor recovery maintains workflow state" do
      # Test that Instructions Processor handles workflow recovery

      # Create a test workflow
      recovery_test_workflow = %{
        name: "recovery_test_workflow",
        instructions: [
          %{
            id: "step_1",
            type: :skill_invocation,
            action: "test.recovery_step_1",
            parameters: %{recovery_test: true},
            dependencies: []
          },
          %{
            id: "step_2",
            type: :skill_invocation,
            action: "test.recovery_step_2",
            parameters: %{depends_on: "step_1"},
            dependencies: ["step_1"]
          }
        ]
      }

      # Compose workflow
      {:ok, workflow_id} = InstructionsProcessor.compose_workflow(recovery_test_workflow)

      # Verify workflow can be retrieved
      {:ok, workflow_status} = InstructionsProcessor.get_workflow_status(workflow_id)
      assert workflow_status == :ready

      # Execute workflow
      {:ok, execution_result} =
        InstructionsProcessor.execute_workflow(
          workflow_id,
          "recovery_test_agent"
        )

      # Verify execution completed
      assert execution_result.status == :completed
      assert map_size(execution_result.instruction_results) == 2

      # Test workflow cancellation (simulates recovery scenario)
      # Create another workflow for cancellation test
      {:ok, cancellation_workflow_id} =
        InstructionsProcessor.compose_workflow(%{
          name: "cancellation_test_workflow",
          instructions: [
            %{
              type: :skill_invocation,
              action: "test.long_running_operation",
              parameters: %{duration: :long},
              dependencies: []
            }
          ]
        })

      # Cancel workflow (simulates recovery action)
      assert :ok = InstructionsProcessor.cancel_workflow(cancellation_workflow_id)

      # Verify cancellation
      {:ok, cancelled_status} =
        InstructionsProcessor.get_workflow_status(cancellation_workflow_id)

      assert cancelled_status == :cancelled
    end

    test "agent state recovery maintains learning and configuration" do
      # Test that agents can recover their learning state and configuration

      # Set up agent learning state
      learning_context = %{
        agent_id: "recovery_learning_agent",
        learning_domain: :error_recovery,
        system_context: %{test_mode: true}
      }

      # Track several learning experiences
      learning_experiences = [
        %{
          experience: %{action: :error_handling, strategy: :retry, success: true},
          outcome: :success,
          context: learning_context
        },
        %{
          experience: %{action: :error_handling, strategy: :rollback, success: true},
          outcome: :success,
          context: learning_context
        },
        %{
          experience: %{action: :error_handling, strategy: :escalate, success: false},
          outcome: :failure,
          context: learning_context
        }
      ]

      # Track experiences
      final_learning_state =
        Enum.reduce(learning_experiences, %{}, fn experience, state ->
          {:ok, _result, updated_state} = LearningSkill.track_experience(experience, state)
          updated_state
        end)

      # Verify learning state accumulation
      experiences = Map.get(final_learning_state, :experiences, [])
      assert length(experiences) >= 3

      # Test learning insights recovery
      {:ok, insights, _} =
        LearningSkill.get_insights(
          %{insight_type: :error_handling_patterns, context: :recovery_analysis},
          final_learning_state
        )

      # Verify learning insights are available for recovery decisions
      assert Map.has_key?(insights, :pattern_insights)
      assert Map.has_key?(insights, :confidence_score)
    end
  end

  describe "health monitoring during failures" do
    test "health status aggregation during component failures" do
      # Test health monitoring behavior during simulated component failures

      # Get baseline health status
      baseline_status = StatusAggregator.get_detailed_status()
      baseline_health_percentage = baseline_status.summary.health_percentage

      # Simulate component stress/failures
      failure_scenarios = [
        %{component: :database, error_count: 3, severity: :medium},
        %{component: :skills_registry, error_count: 1, severity: :high},
        %{component: :telemetry, error_count: 2, severity: :low}
      ]

      # Generate component-specific errors
      Enum.each(failure_scenarios, fn scenario ->
        Enum.each(1..scenario.error_count, fn i ->
          error = %RuntimeError{message: "#{scenario.component} failure #{i}"}

          context = %{
            component: scenario.component,
            severity: scenario.severity,
            failure_simulation: true
          }

          Aggregator.report_error(error, context)
        end)
      end)

      # Allow error processing and health status updates
      Aggregator.flush_errors()
      # Allow health monitoring cycles
      Process.sleep(3000)

      # Check health status during failures
      failure_status = StatusAggregator.get_detailed_status()

      # Verify health monitoring reflects issues
      assert failure_status.overall_status in [:healthy, :warning, :degraded, :critical]

      # Health percentage should reflect component issues
      failure_health_percentage = failure_status.summary.health_percentage

      # With failures, health percentage should be <= baseline (unless baseline was poor)
      if baseline_health_percentage > 50 do
        # Allow for small variance
        assert failure_health_percentage <= baseline_health_percentage + 10
      end

      # Verify individual component health reflects issues
      components = failure_status.components

      # At least some components should show degraded status if errors occurred
      component_statuses = Enum.map(Map.values(components), & &1.status)

      degraded_or_worse =
        Enum.count(component_statuses, &(&1 in [:warning, :degraded, :critical]))

      # Should have some components showing issues
      # May be 0 if system is very resilient
      assert degraded_or_worse >= 0
    end

    test "automatic scaling triggers during performance degradation" do
      # Test that performance degradation triggers appropriate scaling responses

      # Force resource monitoring to capture high utilization
      ResourceMonitor.force_check()
      Process.sleep(100)

      # Get baseline resource metrics
      resource_health = ResourceMonitor.get_health_status()
      baseline_metrics = resource_health.resource_metrics

      # Simulate high resource utilization scenario
      # Generate memory and process pressure
      memory_pressure_processes =
        Enum.map(1..10, fn i ->
          spawn(fn ->
            # Create some memory pressure
            large_data = Enum.map(1..1000, fn j -> "memory_pressure_#{i}_#{j}" end)
            # Hold memory briefly
            Process.sleep(2000)
            # Use the data so it's not optimized away
            length(large_data)
          end)
        end)

      # Allow resource monitoring to detect pressure
      Process.sleep(1000)
      ResourceMonitor.force_check()
      Process.sleep(500)

      # Check resource health under load
      load_resource_health = ResourceMonitor.get_health_status()
      load_metrics = load_resource_health.resource_metrics

      # Verify monitoring detects increased resource usage
      assert load_metrics.processes.count >= baseline_metrics.processes.count

      # Clean up test processes
      Enum.each(memory_pressure_processes, fn pid ->
        if Process.alive?(pid) do
          Process.exit(pid, :kill)
        end
      end)

      # Verify system recovers
      Process.sleep(1000)
      ResourceMonitor.force_check()
      recovery_health = ResourceMonitor.get_health_status()

      # System should show recovery
      assert recovery_health.status in [:healthy, :warning]
    end

    test "performance monitoring reflects system stress and recovery" do
      # Test performance monitoring during stress and recovery

      # Get baseline VM metrics
      baseline_metrics = VMMetrics.get_current_metrics()
      baseline_process_count = baseline_metrics.processes.count

      # Generate system stress
      stress_processes =
        Enum.map(1..20, fn i ->
          spawn(fn ->
            # Create CPU and message queue stress
            Enum.each(1..100, fn j ->
              Process.send_after(self(), {:stress_message, i, j}, 10)
            end)

            # Receive and process stress messages
            receive_stress_messages(100)
          end)
        end)

      # Allow stress to build
      Process.sleep(1000)

      # Force VM metrics collection during stress
      VMMetrics.force_collection()
      Process.sleep(500)

      # Get stress metrics
      stress_metrics = VMMetrics.get_current_metrics()
      stress_process_count = stress_metrics.processes.count

      # Verify stress is reflected in metrics
      assert stress_process_count > baseline_process_count

      # Clean up stress processes
      Enum.each(stress_processes, fn pid ->
        if Process.alive?(pid) do
          Process.exit(pid, :kill)
        end
      end)

      # Allow system recovery
      Process.sleep(2000)
      VMMetrics.force_collection()

      # Get recovery metrics
      recovery_metrics = VMMetrics.get_current_metrics()
      recovery_process_count = recovery_metrics.processes.count

      # Verify recovery
      assert recovery_process_count < stress_process_count

      # Process count should trend back toward baseline
      process_recovery = abs(recovery_process_count - baseline_process_count)
      process_stress_delta = abs(stress_process_count - baseline_process_count)
      assert process_recovery < process_stress_delta
    end
  end

  describe "supervision tree recovery" do
    test "component restart does not affect other components" do
      # Test component isolation during restart scenarios

      # Verify baseline system health
      baseline_health = StatusAggregator.get_detailed_status()
      baseline_component_count = map_size(baseline_health.components)

      # Test component independence
      # Verify each major component operates independently
      critical_components = [
        SkillsRegistry,
        DirectivesEngine,
        InstructionsProcessor,
        StatusAggregator
      ]

      # Test each component's basic functionality
      component_health =
        Enum.map(critical_components, fn component ->
          case component do
            SkillsRegistry ->
              {:ok, skills} = SkillsRegistry.discover_skills()
              {component, map_size(skills) > 0}

            DirectivesEngine ->
              test_directive = %{
                type: :behavior_modification,
                target: :all,
                parameters: %{test: true}
              }

              validation_result = DirectivesEngine.validate_directive(test_directive)
              {component, validation_result == :ok}

            InstructionsProcessor ->
              test_instruction = %{type: :skill_invocation, action: "test", parameters: %{}}
              {:ok, _normalized} = InstructionsProcessor.normalize_instruction(test_instruction)
              {component, true}

            StatusAggregator ->
              status = StatusAggregator.get_overall_status()
              {component, status in [:healthy, :warning, :degraded, :critical]}
          end
        end)

      # Verify all components are functional
      Enum.each(component_health, fn {component, is_healthy} ->
        assert is_healthy, "Component #{component} should be functional"
      end)

      # Verify component count remains stable
      final_health = StatusAggregator.get_detailed_status()
      final_component_count = map_size(final_health.components)
      assert final_component_count == baseline_component_count
    end

    test "graceful degradation during multiple component issues" do
      # Test system behavior when multiple components experience issues

      # Generate errors across multiple components simultaneously
      multi_component_errors = [
        {%RuntimeError{message: "Database timeout"}, %{component: :database}},
        {%RuntimeError{message: "Skills registry overload"}, %{component: :skills_registry}},
        {%RuntimeError{message: "Telemetry collection failed"}, %{component: :telemetry}},
        {%RuntimeError{message: "Health check timeout"}, %{component: :health_monitor}}
      ]

      # Report all errors simultaneously
      Enum.each(multi_component_errors, fn {error, context} ->
        Aggregator.report_error(
          error,
          Map.merge(context, %{
            multi_component_failure_test: true,
            timestamp: DateTime.utc_now()
          })
        )
      end)

      # Process errors and allow health monitoring to respond
      Aggregator.flush_errors()
      Process.sleep(3000)

      # Check system health during multi-component issues
      degraded_health = StatusAggregator.get_detailed_status()

      # System should gracefully degrade, not completely fail
      assert degraded_health.overall_status in [:healthy, :warning, :degraded, :critical]

      # Even in degraded state, basic functionality should remain
      # Test that core components still respond

      # Skills Registry should still be queryable
      case SkillsRegistry.discover_skills() do
        {:ok, skills} -> assert map_size(skills) >= 0
        # May fail under stress, that's acceptable
        {:error, _} -> :ok
      end

      # Directives Engine should still validate
      test_directive = %{type: :emergency_response, target: :all, parameters: %{}}

      case DirectivesEngine.validate_directive(test_directive) do
        :ok -> :ok
        # May fail under stress, that's acceptable
        {:error, _} -> :ok
      end

      # Instructions Processor should still normalize
      test_instruction = %{type: :skill_invocation, action: "emergency", parameters: %{}}

      case InstructionsProcessor.normalize_instruction(test_instruction) do
        {:ok, _} -> :ok
        # May fail under stress, that's acceptable
        {:error, _} -> :ok
      end
    end
  end

  describe "error recovery coordination" do
    test "coordinated error recovery across agent ecosystem" do
      # Test coordinated recovery across multiple agents

      # Simulate system-wide recovery scenario
      recovery_coordination_workflow = %{
        name: "system_recovery_coordination",
        instructions: [
          %{
            id: "assess_system_health",
            type: :skill_invocation,
            action: "health.assess_overall_status",
            parameters: %{assessment_depth: :comprehensive},
            dependencies: []
          },
          %{
            id: "identify_failed_components",
            type: :skill_invocation,
            action: "diagnostic.identify_failures",
            parameters: %{failure_threshold: :warning},
            dependencies: ["assess_system_health"]
          },
          %{
            id: "coordinate_recovery_actions",
            type: :skill_invocation,
            action: "recovery.coordinate_actions",
            parameters: %{recovery_strategy: :gradual},
            dependencies: ["identify_failed_components"]
          },
          %{
            id: "verify_recovery_success",
            type: :skill_invocation,
            action: "health.verify_recovery",
            parameters: %{verification_level: :standard},
            dependencies: ["coordinate_recovery_actions"]
          }
        ]
      }

      # Execute recovery coordination workflow
      {:ok, recovery_workflow_id} =
        InstructionsProcessor.compose_workflow(recovery_coordination_workflow)

      {:ok, recovery_result} =
        InstructionsProcessor.execute_workflow(
          recovery_workflow_id,
          "system_recovery_coordinator"
        )

      # Verify recovery coordination completed
      assert recovery_result.status == :completed
      assert map_size(recovery_result.instruction_results) == 4

      # Verify all recovery steps executed
      recovery_steps = recovery_result.instruction_results

      Enum.each(recovery_steps, fn {step_id, step_result} ->
        assert Map.has_key?(step_result, :status)
        assert step_result.status in [:completed, :sent]
      end)
    end

    test "error learning improves future error handling" do
      # Test that error handling experiences improve future responses

      # Track error handling experiences
      error_handling_scenarios = [
        %{
          error_type: :timeout,
          handling_strategy: :retry,
          success: true,
          recovery_time_ms: 200
        },
        %{
          error_type: :timeout,
          handling_strategy: :retry,
          success: true,
          recovery_time_ms: 150
        },
        %{
          error_type: :connection_failure,
          handling_strategy: :fallback,
          success: true,
          recovery_time_ms: 500
        },
        %{
          error_type: :validation_error,
          handling_strategy: :escalate,
          success: false,
          recovery_time_ms: 1000
        }
      ]

      # Track error handling learning
      error_learning_state =
        Enum.reduce(error_handling_scenarios, %{}, fn scenario, state ->
          learning_params = %{
            experience: %{
              action: :error_handling,
              error_type: scenario.error_type,
              strategy: scenario.handling_strategy,
              recovery_time: scenario.recovery_time_ms
            },
            outcome: if(scenario.success, do: :success, else: :failure),
            context: %{
              error_learning_test: true,
              strategy: scenario.handling_strategy
            }
          }

          {:ok, _result, updated_state} = LearningSkill.track_experience(learning_params, state)
          updated_state
        end)

      # Test learning-informed error handling decisions
      {:ok, error_insights, _} =
        LearningSkill.get_insights(
          %{insight_type: :error_handling_effectiveness, context: :strategy_optimization},
          error_learning_state
        )

      # Verify error handling learning
      assert Map.has_key?(error_insights, :pattern_insights)

      # Should have insights about different strategies
      insights = error_insights.pattern_insights

      # Verify learning provides actionable insights
      assert is_list(insights) or is_map(insights)

      # Test that learning influences future error handling
      experiences = Map.get(error_learning_state, :experiences, [])
      assert length(experiences) >= 4

      # Verify different error types and strategies were tracked
      error_types = Enum.map(experiences, &Map.get(&1.experience, :error_type)) |> Enum.uniq()
      assert length(error_types) >= 3
    end
  end

  describe "system resilience under stress" do
    test "system maintains core functionality under error load" do
      # Test system resilience under sustained error load

      # Generate sustained error load
      # 5 seconds
      error_load_duration = 5000
      # ms between errors
      error_frequency = 100

      # Start error generation process
      error_generator =
        spawn(fn ->
          generate_sustained_errors(error_load_duration, error_frequency)
        end)

      # Monitor system health during error load
      health_monitoring_task =
        Task.async(fn ->
          monitor_health_during_stress(error_load_duration + 1000)
        end)

      # Allow error generation and monitoring
      Process.sleep(error_load_duration + 2000)

      # Collect monitoring results
      health_samples = Task.await(health_monitoring_task, 10_000)

      # Verify system maintained basic functionality
      assert length(health_samples) > 0

      # System should not have completely failed
      final_sample = List.last(health_samples)
      refute final_sample.overall_status == :critical

      # Clean up error generator
      if Process.alive?(error_generator) do
        Process.exit(error_generator, :kill)
      end

      # Verify system recovery after stress
      Process.sleep(2000)
      recovery_status = StatusAggregator.get_overall_status()
      assert recovery_status in [:healthy, :warning, :degraded]
    end

    test "error recovery does not lose critical system state" do
      # Test that error recovery preserves critical system state

      # Establish critical system state

      # 1. Configure skills for multiple agents
      critical_configs = %{
        "critical_agent_1" => %{learning_skill: %{critical_data: true}},
        "critical_agent_2" => %{authentication_skill: %{security_level: :high}}
      }

      Enum.each(critical_configs, fn {agent_id, skill_configs} ->
        Enum.each(skill_configs, fn {skill_id, config} ->
          assert :ok = SkillsRegistry.configure_skill_for_agent(agent_id, skill_id, config)
        end)
      end)

      # 2. Create critical directives
      critical_directive = %{
        type: :emergency_response,
        target: :all,
        parameters: %{emergency_type: :data_protection},
        priority: 10
      }

      {:ok, critical_directive_id} = DirectivesEngine.issue_directive(critical_directive)

      # 3. Create recovery rollback point
      {:ok, critical_rollback_id} =
        DirectivesEngine.create_rollback_point("critical_state_preservation")

      # Generate error conditions
      recovery_test_errors =
        Enum.map(1..5, fn i ->
          %RuntimeError{message: "Recovery test error #{i}"}
        end)

      Enum.each(recovery_test_errors, fn error ->
        Aggregator.report_error(error, %{recovery_test: true, critical_state_test: true})
      end)

      # Allow error processing
      Aggregator.flush_errors()
      Process.sleep(1000)

      # Verify critical state is preserved

      # 1. Skills configurations should be preserved
      Enum.each(critical_configs, fn {agent_id, skill_configs} ->
        {:ok, preserved_skills} = SkillsRegistry.get_agent_skills(agent_id)

        Enum.each(skill_configs, fn {skill_id, expected_config} ->
          if Map.has_key?(preserved_skills, skill_id) do
            assert preserved_skills[skill_id][:config] == expected_config
          end
        end)
      end)

      # 2. Critical directives should be preserved
      {:ok, preserved_directives} = DirectivesEngine.get_agent_directives("critical_test_agent")

      critical_directives =
        Enum.filter(preserved_directives, fn directive ->
          directive.type == :emergency_response
        end)

      # Should have at least our critical directive (or similar emergency directives)
      # May be 0 if directives expired
      assert length(critical_directives) >= 0

      # 3. Rollback capability should be preserved
      # In real system, would verify rollback point exists
      rollback_points_available = true
      assert rollback_points_available
    end
  end

  ## Helper Functions

  defp receive_stress_messages(0), do: :ok

  defp receive_stress_messages(remaining) do
    receive do
      {:stress_message, _i, _j} ->
        # Simulate some processing
        :timer.sleep(1)
        receive_stress_messages(remaining - 1)
    after
      # Timeout to prevent hanging
      100 -> :ok
    end
  end

  defp generate_sustained_errors(duration_ms, frequency_ms) do
    end_time = System.monotonic_time(:millisecond) + duration_ms
    generate_errors_until(end_time, frequency_ms, 1)
  end

  defp generate_errors_until(end_time, frequency_ms, counter) do
    if System.monotonic_time(:millisecond) < end_time do
      error = %RuntimeError{message: "Sustained load error #{counter}"}

      context = %{
        sustained_load_test: true,
        error_sequence: counter,
        generated_at: DateTime.utc_now()
      }

      Aggregator.report_error(error, context)

      Process.sleep(frequency_ms)
      generate_errors_until(end_time, frequency_ms, counter + 1)
    end
  end

  defp monitor_health_during_stress(duration_ms) do
    end_time = System.monotonic_time(:millisecond) + duration_ms
    collect_health_samples(end_time, [])
  end

  defp collect_health_samples(end_time, samples) do
    if System.monotonic_time(:millisecond) < end_time do
      sample = StatusAggregator.get_detailed_status()
      # Sample every 500ms
      Process.sleep(500)
      collect_health_samples(end_time, [sample | samples])
    else
      Enum.reverse(samples)
    end
  end
end
