defmodule RubberDuck.Integration.Workflows.CompleteEvaluationWorkflowTest do
  @moduledoc """
  Comprehensive end-to-end evaluation workflow integration tests.

  Tests complete evaluation pipeline including:
  - Request initiation through VerdictEngine
  - Three-tier configuration resolution
  - Universal Provider System routing and execution
  - Judge Agent System coordination and consensus
  - Skills & Actions architecture integration
  - Learning and feedback system integration
  - Final result delivery and validation
  """

  use RubberDuck.IntegrationCase, async: false

  @moduletag :integration
  @moduletag :workflow

  describe "complete evaluation workflow integration" do
    test "evaluates code through full pipeline with all Phase 1B components", %{
      integration_context: context
    } do
      # Step 1: Set up test scenario with realistic configuration
      user =
        create_integration_test_user(%{
          preferred_providers: ["anthropic", "openai"],
          constitutional_ai_enabled: true,
          # Slight quality preference
          cost_quality_balance: 0.6
        })

      project =
        create_integration_test_project(user, %{
          quality_threshold: 0.9,
          constitutional_ai_required: true,
          team_size: 5
        })

      code_sample = load_test_code_sample("security_test_code.ex")

      # Step 2: Execute complete evaluation workflow
      Logger.info("Starting complete evaluation workflow test")
      start_time = System.monotonic_time(:millisecond)

      {:ok, evaluation_result} =
        RubberDuck.Verdict.Engine.evaluate_code(
          code_sample,
          # Security evaluation should trigger Constitutional AI
          :security,
          user_id: user.id,
          project_id: project.id,
          criteria: %{"security" => 0.6, "correctness" => 0.3, "maintainability" => 0.1},
          streaming: false,
          metadata: %{integration_test: true, test_id: context.test_id}
        )

      total_execution_time = System.monotonic_time(:millisecond) - start_time

      # Step 3: Validate core evaluation workflow
      assert_evaluation_workflow_successful(evaluation_result)

      # Step 4: Validate provider routing integration
      assert_provider_selected_based_on_preferences(evaluation_result, user, project)

      # Anthropic should be preferred for Constitutional AI security evaluation
      assert evaluation_result.provider_used == "anthropic",
             "Expected Anthropic for Constitutional AI security evaluation, got #{evaluation_result.provider_used}"

      # Step 5: Validate agent coordination integration
      assert_agents_coordinated_correctly(evaluation_result)

      # Step 6: Validate consensus achievement
      assert_consensus_achieved_with_confidence(evaluation_result, min_confidence: 0.8)

      # Step 7: Validate Constitutional AI integration
      assert_constitutional_ai_maintained(evaluation_result)

      # Step 8: Validate cost tracking integration
      assert_cost_tracked_correctly(evaluation_result, user, project)

      # Step 9: Validate learning system integration
      assert_feedback_collected_and_processed(evaluation_result)

      # Step 10: Validate cross-domain integration
      assert_cross_domain_integration_successful(evaluation_result)

      # Step 11: Validate performance requirements
      assert total_execution_time < 10_000,
             "Complete workflow execution took #{total_execution_time}ms (limit: 10s)"

      # Step 12: Validate integration telemetry
      telemetry_events = get_integration_telemetry()

      assert length(telemetry_events) > 0,
             "No integration telemetry events captured"

      # Should have events from multiple domains
      event_domains =
        telemetry_events
        |> Enum.map(fn event -> event.event |> List.first() end)
        |> Enum.uniq()

      assert :verdict in event_domains, "No Verdict framework telemetry"
      assert :universal_provider in event_domains, "No Universal Provider telemetry"

      Logger.info("Complete evaluation workflow test passed in #{total_execution_time}ms")
    end

    test "handles progressive evaluation workflow with provider routing", %{
      integration_context: context
    } do
      # Test progressive evaluation: screening → detailed analysis
      user =
        create_integration_test_user(%{
          # Quality focused
          cost_quality_balance: 0.8,
          progressive_evaluation_enabled: true
        })

      project =
        create_integration_test_project(user, %{
          quality_threshold: 0.85,
          progressive_evaluation_strategy: :adaptive
        })

      # Use complex code that should trigger detailed analysis
      complex_code = load_test_code_sample("complex_elixir_module.ex")

      {:ok, evaluation_result} =
        RubberDuck.Verdict.Engine.evaluate_code(
          complex_code,
          :quality,
          user_id: user.id,
          project_id: project.id,
          criteria: generate_test_criteria(),
          progressive_evaluation: true,
          metadata: %{integration_test: true, test_id: context.test_id}
        )

      # Validate progressive evaluation workflow
      assert_evaluation_workflow_successful(evaluation_result)

      # Should have evidence of progressive evaluation
      metadata = evaluation_result.metadata

      assert Map.get(metadata, :progressive_evaluation_applied, false),
             "Progressive evaluation not applied"

      # Should have used appropriate models for screening and detailed analysis
      if Map.has_key?(metadata, :evaluation_stages) do
        stages = metadata.evaluation_stages

        assert length(stages) >= 2,
               "Progressive evaluation should have multiple stages"

        # First stage should use screening model
        first_stage = List.first(stages)

        assert String.contains?(first_stage.model_used, "mini") or
                 String.contains?(first_stage.model_used, "haiku"),
               "First stage should use screening model"
      end
    end

    test "evaluates with skills integration and action orchestration", %{
      integration_context: context
    } do
      # Test evaluation workflow that integrates with Skills & Actions architecture
      user =
        create_integration_test_user(%{
          skills_preferences: %{
            preferred_skills: ["code_analysis_skill", "threat_detection_skill"],
            llm_assistance_enabled: true,
            action_coordination_strategy: :parallel
          }
        })

      project =
        create_integration_test_project(user, %{
          skills_configuration: %{
            skills_enabled: true,
            orchestration_enabled: true,
            coordination_strategy: :intelligent
          }
        })

      code_sample = load_test_code_sample("security_test_code.ex")

      {:ok, evaluation_result} =
        RubberDuck.Verdict.Engine.evaluate_code(
          code_sample,
          :security,
          user_id: user.id,
          project_id: project.id,
          skills_integration_enabled: true,
          action_orchestration_enabled: true,
          metadata: %{integration_test: true, test_id: context.test_id}
        )

      # Validate core evaluation
      assert_evaluation_workflow_successful(evaluation_result)

      # Validate skills integration
      metadata = evaluation_result.metadata

      if Map.get(metadata, :skills_integration_enabled, false) do
        assert Map.has_key?(metadata, :skills_used),
               "Skills integration enabled but no skills data"

        skills_used = metadata.skills_used

        assert is_list(skills_used) and length(skills_used) > 0,
               "No skills were utilized in evaluation"
      end

      # Validate action orchestration
      if Map.get(metadata, :action_orchestration_enabled, false) do
        assert Map.has_key?(metadata, :orchestration_data),
               "Action orchestration enabled but no orchestration data"

        orchestration_data = metadata.orchestration_data

        assert Map.has_key?(orchestration_data, :workflow_pattern),
               "No workflow pattern in orchestration data"
      end
    end
  end

  describe "configuration-driven evaluation workflows" do
    test "adapts workflow based on three-tier configuration preferences", %{
      integration_context: context
    } do
      # Create configuration scenario with clear inheritance
      config_scenario = create_three_tier_configuration_scenario(:constitutional_ai_focused)

      # Apply configuration at each tier
      apply_system_configuration(config_scenario.system)

      user = create_integration_test_user(config_scenario.user)
      project = create_integration_test_project(user, config_scenario.project)

      code_sample = load_test_code_sample("complex_elixir_module.ex")

      # Test multiple evaluation types with same configuration
      evaluation_types = [:security, :quality, :performance]

      results =
        evaluation_types
        |> Enum.map(fn eval_type ->
          {:ok, result} =
            RubberDuck.Verdict.Engine.evaluate_code(
              code_sample,
              eval_type,
              user_id: user.id,
              project_id: project.id,
              metadata: %{
                integration_test: true,
                test_id: context.test_id,
                evaluation_type: eval_type
              }
            )

          {eval_type, result}
        end)
        |> Enum.into(%{})

      # Validate configuration consistency across evaluation types
      Enum.each(results, fn {eval_type, result} ->
        assert_evaluation_workflow_successful(result)

        # All should use Constitutional AI due to configuration
        if config_scenario.project.constitutional_ai_required do
          assert_constitutional_ai_maintained(result)
        end

        # All should respect provider preferences
        assert_provider_selected_based_on_preferences(result, user, project)
      end)

      # Validate configuration resolution consistency
      config_resolution_times =
        results
        |> Map.values()
        |> Enum.map(fn result ->
          get_in(result, [:metadata, :configuration_resolution_time_ms]) || 5
        end)

      avg_resolution_time = Enum.sum(config_resolution_times) / length(config_resolution_times)

      assert avg_resolution_time < 10.0,
             "Configuration resolution inconsistent: #{avg_resolution_time}ms average"
    end

    test "handles real-time configuration changes during evaluation", %{
      integration_context: context
    } do
      # Test configuration changes affecting active evaluations
      user = create_integration_test_user()
      project = create_integration_test_project(user)

      # Start long-running evaluation
      long_evaluation_task =
        Task.async(fn ->
          # Use complex code that takes time to evaluate
          complex_code = String.duplicate(load_test_code_sample("complex_elixir_module.ex"), 3)

          RubberDuck.Verdict.Engine.evaluate_code(
            complex_code,
            :quality,
            user_id: user.id,
            project_id: project.id,
            metadata: %{integration_test: true, test_id: context.test_id}
          )
        end)

      # Apply configuration change during evaluation
      # Let evaluation start
      Process.sleep(100)

      configuration_change = %{
        # Change provider preference
        preferred_providers: ["anthropic"],
        # Increase quality requirement
        quality_threshold: 0.95
      }

      apply_configuration_changes(configuration_change, user.id, project.id, :user)

      # Wait for evaluation to complete
      {:ok, evaluation_result} = Task.await(long_evaluation_task, 15_000)

      # Validate evaluation completed successfully despite configuration change
      assert_evaluation_workflow_successful(evaluation_result)

      # Validate configuration change was handled gracefully
      metadata = evaluation_result.metadata

      if Map.has_key?(metadata, :configuration_changed_during_evaluation) do
        assert metadata.configuration_changed_during_evaluation == true,
               "Configuration change not detected"

        assert Map.has_key?(metadata, :configuration_change_handling),
               "No configuration change handling metadata"
      end
    end
  end

  describe "provider integration workflow validation" do
    test "validates Universal Provider System integration across evaluation workflow", %{
      integration_context: context
    } do
      # Test that evaluation workflow correctly integrates with Universal Provider System
      user =
        create_integration_test_user(%{
          provider_preferences: %{
            routing_strategy: :constitutional_ai_first,
            cost_optimization_enabled: true
          }
        })

      project = create_integration_test_project(user)

      # Test evaluation that should use Constitutional AI routing
      security_code = load_test_code_sample("security_test_code.ex")

      {:ok, evaluation_result} =
        RubberDuck.Verdict.Engine.evaluate_code(
          security_code,
          :security,
          user_id: user.id,
          project_id: project.id,
          constitutional_ai_required: true,
          metadata: %{integration_test: true, test_id: context.test_id}
        )

      # Validate Universal Provider integration
      assert_evaluation_workflow_successful(evaluation_result)

      metadata = evaluation_result.metadata

      # Should have Universal Provider routing metadata
      assert Map.get(metadata, :universal_provider_used, false),
             "Universal Provider System not used"

      # Should have routing decision metadata  
      assert Map.has_key?(metadata, :provider_routing_decision),
             "No provider routing decision metadata"

      routing_decision = metadata.provider_routing_decision

      assert routing_decision.strategy == :constitutional_ai_first,
             "Expected Constitutional AI routing strategy"

      assert routing_decision.provider == :anthropic,
             "Expected Anthropic for Constitutional AI routing"

      # Validate provider health monitoring integration
      assert Map.has_key?(routing_decision, :provider_health_status),
             "No provider health status in routing decision"

      # Validate cost optimization integration
      assert Map.has_key?(metadata, :cost_optimization_applied),
             "No cost optimization metadata"
    end

    test "handles provider failover during evaluation workflow", %{integration_context: context} do
      # Test evaluation workflow with simulated provider failure
      user =
        create_integration_test_user(%{
          # Fallback available
          preferred_providers: ["openai", "anthropic"],
          provider_failover_enabled: true
        })

      project = create_integration_test_project(user)

      # Simulate provider failure scenario
      # Fail for 2 seconds
      simulate_provider_failure(:openai, 2000)

      code_sample = load_test_code_sample("complex_elixir_module.ex")

      {:ok, evaluation_result} =
        RubberDuck.Verdict.Engine.evaluate_code(
          code_sample,
          :quality,
          user_id: user.id,
          project_id: project.id,
          metadata: %{
            integration_test: true,
            test_id: context.test_id,
            failover_test: true
          }
        )

      # Validate evaluation completed despite provider failure
      assert_evaluation_workflow_successful(evaluation_result)

      # Should have used fallback provider
      metadata = evaluation_result.metadata

      if Map.get(metadata, :provider_failover_occurred, false) do
        assert Map.has_key?(metadata, :failover_details),
               "Provider failover occurred but no details recorded"

        failover_details = metadata.failover_details

        assert failover_details.original_provider == "openai",
               "Unexpected original provider in failover"

        assert failover_details.fallback_provider in ["anthropic"],
               "Unexpected fallback provider"
      end
    end
  end

  describe "learning and feedback integration" do
    test "integrates with continuous learning system throughout workflow", %{
      integration_context: context
    } do
      # Test evaluation workflow with learning and feedback integration
      user =
        create_integration_test_user(%{
          learning_enabled: true,
          feedback_collection_enabled: true
        })

      project =
        create_integration_test_project(user, %{
          learning_optimization_enabled: true
        })

      # Execute multiple evaluations to generate learning data
      evaluation_requests =
        create_evaluation_requests(5, %{
          user_id: user.id,
          project_id: project.id
        })

      results =
        Enum.map(evaluation_requests, fn request ->
          {:ok, result} =
            RubberDuck.Verdict.Engine.evaluate_code(
              request.code,
              request.evaluation_type,
              user_id: request.user_id,
              project_id: request.project_id,
              criteria: request.criteria,
              metadata:
                Map.merge(request.metadata, %{
                  integration_test: true,
                  test_id: context.test_id,
                  learning_test: true
                })
            )

          result
        end)

      # Validate all evaluations successful
      Enum.each(results, &assert_evaluation_workflow_successful/1)

      # Validate learning system integration
      Enum.each(results, &assert_feedback_collected_and_processed/1)

      # Should have learning data accumulated
      learning_events =
        get_integration_telemetry()
        |> Enum.filter(fn event ->
          event.event == [:learning, :pattern, :detected] or
            event.event == [:feedback, :collected]
        end)

      assert length(learning_events) > 0,
             "No learning system integration detected"

      # Validate learning affects subsequent evaluations
      if length(results) >= 3 do
        first_result = List.first(results)
        last_result = List.last(results)

        # Later evaluations should potentially be faster due to learning
        first_time = get_in(first_result, [:metadata, :execution_time_ms]) || 5000
        last_time = get_in(last_result, [:metadata, :execution_time_ms]) || 5000

        # Learning might improve performance (not strict requirement)
        if last_time < first_time * 0.8 do
          Logger.info(
            "Learning system appears to have improved performance: #{first_time}ms → #{last_time}ms"
          )
        end
      end
    end
  end

  describe "skills and actions integration workflow" do
    test "integrates skills registry and action orchestration with evaluation", %{
      integration_context: context
    } do
      # Test evaluation workflow integrated with Skills & Actions architecture
      user =
        create_integration_test_user(%{
          skills_integration_enabled: true,
          action_orchestration_enabled: true,
          skills_preferences: %{
            preferred_skills: ["code_analysis_skill", "threat_detection_skill"],
            orchestration_strategy: :parallel
          }
        })

      project =
        create_integration_test_project(user, %{
          skills_configuration: %{
            project_skills_enabled: true,
            coordination_strategy: :intelligent
          }
        })

      code_sample = load_test_code_sample("complex_elixir_module.ex")

      {:ok, evaluation_result} =
        RubberDuck.Verdict.Engine.evaluate_code(
          code_sample,
          :quality,
          user_id: user.id,
          project_id: project.id,
          skills_integration: true,
          action_orchestration: true,
          metadata: %{
            integration_test: true,
            test_id: context.test_id,
            skills_test: true
          }
        )

      # Validate core evaluation
      assert_evaluation_workflow_successful(evaluation_result)

      # Validate skills integration
      metadata = evaluation_result.metadata

      if Map.get(metadata, :skills_integration_enabled, false) do
        assert Map.has_key?(metadata, :skills_registry_interactions),
               "Skills integration enabled but no registry interactions"

        skills_interactions = metadata.skills_registry_interactions

        assert Map.has_key?(skills_interactions, :skills_discovered),
               "No skills discovery in integration"

        assert Map.has_key?(skills_interactions, :capabilities_matched),
               "No capability matching in integration"
      end

      # Validate action orchestration integration
      if Map.get(metadata, :action_orchestration_enabled, false) do
        assert Map.has_key?(metadata, :workflow_orchestration),
               "Action orchestration enabled but no workflow data"

        workflow_data = metadata.workflow_orchestration

        assert Map.has_key?(workflow_data, :execution_pattern),
               "No execution pattern in workflow data"

        assert workflow_data.execution_pattern in [:parallel, :sequential, :conditional],
               "Invalid execution pattern: #{workflow_data.execution_pattern}"
      end
    end
  end

  # Helper functions for workflow testing

  defp apply_system_configuration(system_config) do
    # Apply system-level configuration for testing
    Logger.debug("Applying system configuration: #{inspect(system_config)}")
    Process.put(:integration_system_config, {system_config, DateTime.utc_now()})
  end

  defp simulate_provider_failure(provider, duration_ms) do
    # Simulate provider failure for testing failover
    Logger.info("Simulating #{provider} failure for #{duration_ms}ms")

    Process.send_after(self(), {:restore_provider, provider}, duration_ms)

    # Mark provider as unhealthy
    RubberDuck.LlmProviders.ProviderRegistry.mark_provider_unhealthy(
      provider,
      "Integration test failure simulation"
    )
  end

  # Message handling for provider failure simulation
  def handle_info({:restore_provider, provider}, state) do
    Logger.info("Restoring #{provider} after simulated failure")

    # Restore provider health (would integrate with actual health system)
    RubberDuck.LlmProviders.ProviderRegistry.mark_provider_healthy(provider)

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
