defmodule RubberDuck.Integration.Performance.ConcurrentEvaluationsTest do
  @moduledoc """
  Performance and load testing for concurrent evaluations across all Phase 1B systems.
  
  Validates that:
  - System handles 50+ concurrent evaluations without performance degradation
  - Provider routing maintains performance under load
  - Configuration resolution remains fast with concurrent access
  - Memory usage stays stable under sustained concurrent load
  - Agent coordination scales effectively with concurrent evaluations
  """
  
  use RubberDuck.IntegrationCase, async: false
  
  @moduletag :integration
  @moduletag :performance
  @moduletag timeout: 60_000  # Extended timeout for load testing
  
  describe "concurrent evaluation performance" do
    test "handles 50+ concurrent evaluations without degradation", %{integration_context: context} do
      # Set up performance test scenario
      users = 1..10
      |> Enum.map(fn index ->
        create_integration_test_user(%{
          preferred_providers: Enum.random([["openai"], ["anthropic"], ["openai", "anthropic"]]),
          cost_quality_balance: :rand.uniform() * 0.4 + 0.3,  # Varied preferences
          constitutional_ai_enabled: rem(index, 3) == 0  # Every 3rd user
        })
      end)
      
      projects = users
      |> Enum.map(fn user ->
        create_integration_test_project(user, %{
          quality_threshold: :rand.uniform() * 0.3 + 0.7,  # 0.7-1.0
          team_size: :rand.uniform(10) + 1,
          constitutional_ai_required: user.preferences.constitutional_ai_enabled
        })
      end)
      
      # Create 50 diverse evaluation requests
      evaluation_requests = create_evaluation_requests(50, %{
        varied_users: true,
        varied_projects: true
      })
      |> Enum.with_index()
      |> Enum.map(fn {request, index} ->
        user = Enum.at(users, rem(index, 10))
        project = Enum.at(projects, rem(index, 10))
        
        %{request | 
          user_id: user.id,
          project_id: project.id,
          metadata: Map.put(request.metadata, :performance_test_index, index)
        }
      end)
      
      # Capture baseline system metrics
      baseline_metrics = capture_system_metrics()
      
      Logger.info("Starting concurrent evaluation performance test with #{length(evaluation_requests)} requests")
      
      # Execute all evaluations concurrently
      start_time = System.monotonic_time(:millisecond)
      
      results = evaluate_concurrently(evaluation_requests, timeout: 45_000)
      
      total_execution_time = System.monotonic_time(:millisecond) - start_time
      
      # Capture final system metrics
      final_metrics = capture_system_metrics()
      
      # Validate performance requirements
      assert total_execution_time < 20_000,
             "Concurrent evaluations took #{total_execution_time}ms (limit: 20s)"
      
      # Validate success rate
      successful_results = Enum.filter(results, fn
        {:ok, _result} -> true
        _ -> false
      end)
      
      success_rate = length(successful_results) / length(results)
      
      assert success_rate >= 0.95,
             "Success rate #{Float.round(success_rate * 100, 1)}% below required 95%"
      
      # Validate system resource stability
      assert_memory_usage_stable(baseline_metrics, final_metrics)
      assert_no_resource_leaks(baseline_metrics, final_metrics)
      
      # Validate provider distribution and performance
      assert_providers_balanced_across_evaluations(successful_results)
      assert_configuration_resolution_performant(successful_results)
      
      # Validate individual evaluation performance
      evaluation_times = successful_results
      |> Enum.map(fn {:ok, result} -> result.execution_time_ms end)
      
      avg_eval_time = Enum.sum(evaluation_times) / length(evaluation_times)
      p95_eval_time = evaluation_times |> Enum.sort() |> Enum.at(trunc(length(evaluation_times) * 0.95))
      
      assert avg_eval_time < 8_000,
             "Average evaluation time #{avg_eval_time}ms too slow (limit: 8s)"
      
      assert p95_eval_time < 15_000,
             "P95 evaluation time #{p95_eval_time}ms too slow (limit: 15s)"
      
      Logger.info("""
      Performance test results:
      - Total execution time: #{total_execution_time}ms
      - Success rate: #{Float.round(success_rate * 100, 1)}%
      - Average evaluation time: #{Float.round(avg_eval_time)}ms
      - P95 evaluation time: #{p95_eval_time}ms
      - Memory growth: #{calculate_memory_growth(baseline_metrics, final_metrics)}%
      """)
    end
    
    test "validates provider routing performance under load", %{integration_context: context} do
      # Test that provider routing decisions remain fast under concurrent load
      users = 1..5
      |> Enum.map(&create_integration_test_user(%{user_index: &1}))
      
      # Create routing-intensive scenario with varied preferences
      routing_test_requests = 1..30
      |> Enum.map(fn index ->
        user = Enum.at(users, rem(index, 5))
        
        %{
          user_id: user.id,
          evaluation_type: Enum.random([:security, :quality, :performance]),
          provider_preferences: %{
            routing_strategy: Enum.random([:cost_optimized, :quality_first, :balanced]),
            constitutional_ai_preference: rem(index, 4) == 0
          },
          test_index: index
        }
      end)
      
      # Execute routing decisions concurrently
      routing_tasks = routing_test_requests
      |> Enum.map(fn request ->
        Task.async(fn ->
          start_time = System.monotonic_time(:millisecond)
          
          # Simulate provider routing decision
          routing_result = RubberDuck.LlmProviders.ProviderRouter.select_provider(
            :evaluation,
            %{
              user_id: request.user_id,
              evaluation_type: request.evaluation_type,
              routing_strategy: request.provider_preferences.routing_strategy
            }
          )
          
          routing_time = System.monotonic_time(:millisecond) - start_time
          
          case routing_result do
            {:ok, routing_decision} ->
              {:ok, %{
                routing_decision: routing_decision,
                routing_time_ms: routing_time,
                request: request
              }}
            
            error ->
              {:error, error, routing_time}
          end
        end)
      end)
      
      routing_results = Task.await_many(routing_tasks, 10_000)
      
      # Validate routing performance
      successful_routings = Enum.filter(routing_results, fn
        {:ok, _} -> true
        _ -> false
      end)
      
      routing_success_rate = length(successful_routings) / length(routing_results)
      
      assert routing_success_rate >= 0.95,
             "Routing success rate #{Float.round(routing_success_rate * 100, 1)}% below 95%"
      
      # Validate routing decision times
      routing_times = successful_routings
      |> Enum.map(fn {:ok, result} -> result.routing_time_ms end)
      
      avg_routing_time = Enum.sum(routing_times) / length(routing_times)
      max_routing_time = Enum.max(routing_times)
      
      assert avg_routing_time < 50,
             "Average routing time #{avg_routing_time}ms exceeds limit (50ms)"
      
      assert max_routing_time < 100,
             "Maximum routing time #{max_routing_time}ms exceeds limit (100ms)"
      
      # Validate routing decisions were appropriate
      successful_routings
      |> Enum.each(fn {:ok, result} ->
        routing_decision = result.routing_decision
        request = result.request
        
        # Constitutional AI requests should prefer Anthropic
        if request.provider_preferences.constitutional_ai_preference do
          assert routing_decision.provider == :anthropic,
                 "Constitutional AI preference not respected in routing"
        end
        
        # Cost optimized strategy should select accordingly
        if request.provider_preferences.routing_strategy == :cost_optimized do
          assert routing_decision.strategy == :cost_optimized,
                 "Cost optimized strategy not applied"
        end
      end)
    end
    
    test "validates skills registry and orchestration performance under load", %{integration_context: context} do
      # Test Skills & Actions architecture performance under concurrent load
      user = create_integration_test_user(%{
        skills_preferences: %{
          preferred_skills: ["code_analysis_skill", "learning_skill"],
          orchestration_enabled: true
        }
      })
      
      project = create_integration_test_project(user)
      
      # Create diverse skill recommendation requests
      skill_requests = 1..25
      |> Enum.map(fn index ->
        %{
          agent_need: "I need to perform code analysis and learning task #{index}",
          context: %{
            agent_id: "test_agent_#{index}",
            goals: "Analyze code quality and track learning patterns",
            performance_requirements: %{max_execution_time_ms: 5000}
          },
          user_id: user.id
        }
      end)
      
      # Execute skill recommendations concurrently
      skill_recommendation_tasks = skill_requests
      |> Enum.map(fn request ->
        Task.async(fn ->
          start_time = System.monotonic_time(:millisecond)
          
          recommendation_result = RubberDuck.SkillsActions.SkillsRegistry.recommend_optimal_skill(
            request.agent_need,
            request.context,
            request.user_id
          )
          
          recommendation_time = System.monotonic_time(:millisecond) - start_time
          
          case recommendation_result do
            {:ok, recommendation} ->
              {:ok, %{
                recommendation: recommendation,
                recommendation_time_ms: recommendation_time,
                request: request
              }}
            
            error ->
              {:error, error, recommendation_time}
          end
        end)
      end)
      
      recommendation_results = Task.await_many(skill_recommendation_tasks, 15_000)
      
      # Validate skills registry performance
      successful_recommendations = Enum.filter(recommendation_results, fn
        {:ok, _} -> true
        _ -> false
      end)
      
      recommendation_success_rate = length(successful_recommendations) / length(recommendation_results)
      
      assert recommendation_success_rate >= 0.90,
             "Skill recommendation success rate #{Float.round(recommendation_success_rate * 100, 1)}% below 90%"
      
      # Validate recommendation performance
      recommendation_times = successful_recommendations
      |> Enum.map(fn {:ok, result} -> result.recommendation_time_ms end)
      
      avg_recommendation_time = Enum.sum(recommendation_times) / length(recommendation_times)
      
      assert avg_recommendation_time < 200,
             "Average skill recommendation time #{avg_recommendation_time}ms too slow (limit: 200ms)"
      
      # Test action orchestration performance
      workflow_requests = 1..10
      |> Enum.map(fn index ->
        %{
          skills_actions: [
            %{type: :skill, module: RubberDuck.Skills.CodeAnalysisSkill, params: %{code: "test code #{index}"}},
            %{type: :skill, module: RubberDuck.Skills.LearningSkill, params: %{experience: "test experience #{index}"}},
            %{type: :llm_assisted, description: "Analyze and learn from code #{index}", params: %{}}
          ],
          execution_context: %{
            agent_id: "test_agent_#{index}",
            user_id: user.id,
            workflow_test: true
          }
        }
      end)
      
      # Execute workflow orchestration concurrently
      workflow_tasks = workflow_requests
      |> Enum.map(fn request ->
        Task.async(fn ->
          start_time = System.monotonic_time(:millisecond)
          
          workflow_result = RubberDuck.SkillsActions.ActionOrchestrator.execute_parallel_workflow(
            request.skills_actions,
            request.execution_context
          )
          
          workflow_time = System.monotonic_time(:millisecond) - start_time
          
          case workflow_result do
            {:ok, result} ->
              {:ok, %{
                workflow_result: result,
                workflow_time_ms: workflow_time,
                request: request
              }}
            
            error ->
              {:error, error, workflow_time}
          end
        end)
      end)
      
      workflow_results = Task.await_many(workflow_tasks, 20_000)
      
      # Validate workflow orchestration performance
      successful_workflows = Enum.filter(workflow_results, fn
        {:ok, result} -> result.workflow_result.status == :started
        _ -> false
      end)
      
      workflow_success_rate = length(successful_workflows) / length(workflow_results)
      
      assert workflow_success_rate >= 0.80,
             "Workflow orchestration success rate #{Float.round(workflow_success_rate * 100, 1)}% below 80%"
      
      # Validate orchestration performance
      orchestration_times = successful_workflows
      |> Enum.map(fn {:ok, result} -> result.workflow_time_ms end)
      
      if not Enum.empty?(orchestration_times) do
        avg_orchestration_time = Enum.sum(orchestration_times) / length(orchestration_times)
        
        assert avg_orchestration_time < 1000,
               "Average workflow orchestration time #{avg_orchestration_time}ms too slow (limit: 1s)"
      end
    end
    
    test "validates system scalability with mixed workload", %{integration_context: context} do
      # Test system with mixed workload: evaluations + skill discovery + configuration resolution
      users = 1..5 |> Enum.map(&create_integration_test_user(%{user_index: &1}))
      projects = users |> Enum.map(&create_integration_test_project/1)
      
      baseline_metrics = capture_system_metrics()
      
      # Mixed workload tasks
      mixed_tasks = [
        # Evaluation tasks (60% of workload)
        (1..15 |> Enum.map(fn index ->
          user = Enum.at(users, rem(index, 5))
          project = Enum.at(projects, rem(index, 5))
          
          Task.async(fn ->
            code = load_test_code_sample(Enum.random(["simple_elixir_function.ex", "complex_elixir_module.ex"]))
            eval_type = Enum.random([:quality, :security, :performance])
            
            RubberDuck.Verdict.Engine.evaluate_code(
              code,
              eval_type,
              user_id: user.id,
              project_id: project.id,
              metadata: %{mixed_workload_test: true, task_type: :evaluation}
            )
          end)
        end)),
        
        # Skill discovery tasks (25% of workload)
        (1..6 |> Enum.map(fn index ->
          Task.async(fn ->
            RubberDuck.SkillsActions.SkillsRegistry.discover_skills(%{
              capabilities: ["analyze", "learn", "detect"],
              performance: %{max_execution_time_ms: 5000}
            })
          end)
        end)),
        
        # Configuration resolution tasks (15% of workload)
        (1..4 |> Enum.map(fn index ->
          user = Enum.at(users, rem(index, 5))
          project = Enum.at(projects, rem(index, 5))
          
          Task.async(fn ->
            test_configuration_resolution(user.id, project.id, :verdict)
          end)
        end))
      ]
      |> List.flatten()
      
      # Execute mixed workload
      Logger.info("Executing mixed workload with #{length(mixed_tasks)} concurrent tasks")
      
      mixed_results = Task.await_many(mixed_tasks, 30_000)
      
      execution_time = System.monotonic_time(:millisecond) - baseline_metrics.timestamp.microsecond / 1000
      final_metrics = capture_system_metrics()
      
      # Validate mixed workload performance
      successful_tasks = Enum.count(mixed_results, fn
        {:ok, _} -> true
        _ -> false
      end)
      
      overall_success_rate = successful_tasks / length(mixed_results)
      
      assert overall_success_rate >= 0.90,
             "Mixed workload success rate #{Float.round(overall_success_rate * 100, 1)}% below 90%"
      
      # Validate system stability under mixed load
      assert_memory_usage_stable(baseline_metrics, final_metrics)
      assert_no_resource_leaks(baseline_metrics, final_metrics)
      
      # Validate performance distribution
      evaluation_results = mixed_results
      |> Enum.filter(fn result ->
        case result do
          {:ok, %{success: true, score: _}} -> true  # Evaluation result
          _ -> false
        end
      end)
      
      if length(evaluation_results) > 5 do
        assert_performance_within_bounds(evaluation_results, 15_000)
      end
      
      Logger.info("""
      Mixed workload test results:
      - Tasks completed: #{successful_tasks}/#{length(mixed_results)}
      - Overall success rate: #{Float.round(overall_success_rate * 100, 1)}%
      - Evaluation results: #{length(evaluation_results)}
      - System stability: Maintained
      """)
    end
  end
  
  describe "configuration system performance under load" do
    test "validates configuration resolution performance with concurrent access", %{integration_context: context} do
      # Test configuration system performance with many concurrent resolution requests
      users = 1..8 |> Enum.map(&create_integration_test_user(%{user_index: &1}))
      projects = users |> Enum.map(&create_integration_test_project/1)
      
      # Create configuration scenarios
      config_scenarios = [
        :balanced, :cost_focused, :quality_focused, :constitutional_ai_focused
      ]
      
      # Apply varied configurations
      Enum.with_index(users)
      |> Enum.each(fn {user, index} ->
        scenario = Enum.at(config_scenarios, rem(index, 4))
        config = create_three_tier_configuration_scenario(scenario)
        
        # Apply user-level configuration
        apply_user_configuration(user.id, config.user)
      end)
      
      # Create concurrent configuration resolution requests
      config_resolution_tasks = 1..40
      |> Enum.map(fn index ->
        user = Enum.at(users, rem(index, 8))
        project = Enum.at(projects, rem(index, 8))
        domain = Enum.random([:verdict, :skills_actions, :universal_providers])
        
        Task.async(fn ->
          test_configuration_resolution(user.id, project.id, domain)
        end)
      end)
      
      Logger.info("Testing concurrent configuration resolution with #{length(config_resolution_tasks)} requests")
      
      start_time = System.monotonic_time(:millisecond)
      config_results = Task.await_many(config_resolution_tasks, 10_000)
      total_time = System.monotonic_time(:millisecond) - start_time
      
      # Validate configuration resolution performance
      successful_resolutions = Enum.filter(config_results, fn
        {:ok, _} -> true
        _ -> false
      end)
      
      config_success_rate = length(successful_resolutions) / length(config_results)
      
      assert config_success_rate >= 0.95,
             "Configuration resolution success rate #{Float.round(config_success_rate * 100, 1)}% below 95%"
      
      # Validate resolution times
      resolution_times = successful_resolutions
      |> Enum.map(fn {:ok, result} -> result.resolution_time_ms end)
      
      avg_resolution_time = Enum.sum(resolution_times) / length(resolution_times)
      p95_resolution_time = resolution_times |> Enum.sort() |> Enum.at(trunc(length(resolution_times) * 0.95))
      
      assert avg_resolution_time < 15,
             "Average configuration resolution time #{avg_resolution_time}ms too slow (limit: 15ms)"
      
      assert p95_resolution_time < 30,
             "P95 configuration resolution time #{p95_resolution_time}ms too slow (limit: 30ms)"
      
      Logger.info("""
      Configuration performance test results:
      - Total resolution time: #{total_time}ms for #{length(config_results)} requests
      - Success rate: #{Float.round(config_success_rate * 100, 1)}%
      - Average resolution time: #{Float.round(avg_resolution_time, 1)}ms
      - P95 resolution time: #{p95_resolution_time}ms
      """)
    end
  end
  
  # Helper functions for performance testing
  
  defp apply_user_configuration(user_id, user_config) do
    # Apply user configuration for testing
    Logger.debug("Applying user configuration for #{user_id}")
    Process.put({:user_config, user_id}, {user_config, DateTime.utc_now()})
  end
  
  defp calculate_memory_growth(baseline_metrics, final_metrics) do
    baseline_memory = baseline_metrics.memory_usage[:total]
    final_memory = final_metrics.memory_usage[:total]
    
    ((final_memory - baseline_memory) / baseline_memory * 100)
    |> Float.round(2)
  end
end