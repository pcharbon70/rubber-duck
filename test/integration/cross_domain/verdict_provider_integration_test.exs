defmodule RubberDuck.Integration.CrossDomain.VerdictProviderIntegrationTest do
  @moduledoc """
  Cross-domain integration tests for Verdict framework with Universal Provider System.
  
  Validates that:
  - Verdict framework correctly uses Universal Provider System for LLM operations
  - Provider routing decisions affect evaluation quality and cost as expected
  - Constitutional AI integration works across both systems
  - Three-tier configuration resolution works consistently across domains
  - Cost optimization and budget tracking work across integrated systems
  """
  
  use RubberDuck.IntegrationCase, async: false
  
  @moduletag :integration
  @moduletag :cross_domain
  
  describe "Verdict framework with Universal Provider System" do
    test "routes evaluations across multiple providers based on configuration", %{integration_context: context} do
      # Set up three-tier configuration with clear provider preferences
      system_config = %{
        enabled_providers: ["openai", "anthropic", "ollama"],
        default_routing_strategy: :balanced
      }
      
      user_preferences = %{
        preferred_providers: ["anthropic", "openai"],  # Anthropic preferred
        constitutional_ai_enabled: true,
        cost_quality_balance: 0.3  # Quality focused
      }
      
      project_settings = %{
        quality_threshold: 0.9,
        constitutional_ai_required: true,
        budget_constraints: %{max_daily_cost: 100.0}
      }
      
      apply_system_configuration(system_config)
      user = create_integration_test_user(user_preferences)
      project = create_integration_test_project(user, project_settings)
      
      # Create diverse evaluation requests to test routing
      evaluation_requests = [
        {load_test_code_sample("security_test_code.ex"), :security, "Should use Anthropic for Constitutional AI"},
        {load_test_code_sample("simple_elixir_function.ex"), :style, "Should use cost-effective provider"},
        {load_test_code_sample("complex_elixir_module.ex"), :quality, "Should balance quality and cost"}
      ]
      
      results = Enum.map(evaluation_requests, fn {code, eval_type, test_note} ->
        {:ok, result} = RubberDuck.Verdict.Engine.evaluate_code(
          code,
          eval_type,
          user_id: user.id,
          project_id: project.id,
          metadata: %{
            integration_test: true,
            test_id: context.test_id,
            test_note: test_note,
            routing_test: true
          }
        )
        
        {eval_type, result, test_note}
      end)
      
      # Validate all evaluations successful
      Enum.each(results, fn {_type, result, _note} ->
        assert_evaluation_workflow_successful(result)
      end)
      
      # Validate provider routing logic
      provider_selections = results
      |> Enum.map(fn {eval_type, result, note} ->
        {eval_type, result.provider_used, note}
      end)
      
      # Security evaluation should use Anthropic (Constitutional AI preference)
      {_security_type, security_provider, _note} = 
        Enum.find(results, fn {type, _result, _note} -> type == :security end)
      
      assert security_provider == "anthropic",
             "Security evaluation should use Anthropic for Constitutional AI"
      
      # Validate Universal Provider System integration
      Enum.each(results, fn {_type, result, _note} ->
        metadata = result.metadata
        
        assert Map.get(metadata, :universal_provider_used, false),
               "Universal Provider System not used in integrated workflow"
        
        assert Map.has_key?(metadata, :provider_routing_metadata),
               "No provider routing metadata in integrated workflow"
      end)
      
      # Validate cost tracking across providers
      total_cost = results
      |> Enum.map(fn {_type, result, _note} -> result.cost_usd end)
      |> Enum.sum()
      
      assert total_cost > 0,
             "No cost tracking detected across provider integrations"
      
      assert total_cost < project_settings.budget_constraints.max_daily_cost,
             "Cost #{total_cost} exceeds daily budget #{project_settings.budget_constraints.max_daily_cost}"
    end
    
    test "validates Constitutional AI across Verdict and Provider systems", %{integration_context: context} do
      # Test Constitutional AI integration across both Verdict and Universal Provider systems
      user = create_integration_test_user(%{
        constitutional_ai_enabled: true,
        safety_priority: :critical
      })
      
      project = create_integration_test_project(user, %{
        constitutional_ai_required: true,
        safety_compliance: :strict
      })
      
      # Test code with potential security issues
      security_test_code = load_test_code_sample("security_test_code.ex")
      
      {:ok, evaluation_result} = RubberDuck.Verdict.Engine.evaluate_code(
        security_test_code,
        :security,
        user_id: user.id,
        project_id: project.id,
        constitutional_ai_required: true,
        safety_critical: true,
        metadata: %{
          integration_test: true,
          test_id: context.test_id,
          constitutional_ai_test: true
        }
      )
      
      # Validate Constitutional AI integration
      assert_evaluation_workflow_successful(evaluation_result)
      assert_constitutional_ai_maintained(evaluation_result)
      
      metadata = evaluation_result.metadata
      
      # Should have Constitutional AI data from both systems
      assert Map.has_key?(metadata, :constitutional_ai_verdict),
             "No Verdict system Constitutional AI data"
      
      assert Map.has_key?(metadata, :constitutional_ai_provider),
             "No Provider system Constitutional AI data"
      
      # Validate Constitutional AI principles applied
      verdict_constitutional = metadata.constitutional_ai_verdict
      provider_constitutional = metadata.constitutional_ai_provider
      
      [:helpful, :harmless, :honest]
      |> Enum.each(fn principle ->
        assert Map.get(verdict_constitutional, principle, false),
               "Verdict system missing Constitutional AI principle: #{principle}"
        
        assert Map.get(provider_constitutional, principle, false),
               "Provider system missing Constitutional AI principle: #{principle}"
      end)
      
      # Validate safety assessment
      assert Map.has_key?(metadata, :safety_assessment),
             "No safety assessment in Constitutional AI integration"
      
      safety_assessment = metadata.safety_assessment
      assert safety_assessment.safety_score >= 0.9,
             "Safety score #{safety_assessment.safety_score} below required threshold"
    end
    
    test "validates cost optimization across integrated systems", %{integration_context: context} do
      # Test cost optimization working across Verdict and Universal Provider systems
      user = create_integration_test_user(%{
        cost_optimization_enabled: true,
        budget_alerts_enabled: true,
        cost_quality_balance: 0.8  # Cost focused
      })
      
      project = create_integration_test_project(user, %{
        budget_allocation: %{daily_limit: 25.0},
        cost_optimization_strategy: :aggressive
      })
      
      # Execute multiple evaluations to test cost optimization
      evaluation_requests = create_evaluation_requests(10, %{
        user_id: user.id,
        project_id: project.id
      })
      
      results = evaluate_concurrently(evaluation_requests)
      
      # Validate all evaluations successful
      successful_results = Enum.filter(results, fn
        {:ok, _result} -> true
        _ -> false
      end)
      
      assert length(successful_results) == length(evaluation_requests),
             "#{length(successful_results)}/#{length(evaluation_requests)} evaluations succeeded"
      
      # Validate cost optimization across systems
      total_cost = successful_results
      |> Enum.map(fn {:ok, result} -> result.cost_usd end)
      |> Enum.sum()
      
      # Should be within budget
      daily_budget = project.settings.budget_allocation.daily_limit
      assert total_cost <= daily_budget,
             "Total cost #{total_cost} exceeds daily budget #{daily_budget}"
      
      # Validate cost optimization metadata
      successful_results
      |> Enum.each(fn {:ok, result} ->
        metadata = result.metadata
        
        assert Map.get(metadata, :cost_optimization_applied, false),
               "Cost optimization not applied in integrated workflow"
        
        if Map.has_key?(metadata, :cost_routing_decision) do
          cost_routing = metadata.cost_routing_decision
          
          assert cost_routing.strategy in [:cost_optimized, :balanced],
                 "Unexpected cost routing strategy: #{cost_routing.strategy}"
        end
      end)
      
      # Validate provider selection influenced by cost optimization
      provider_costs = successful_results
      |> Enum.group_by(fn {:ok, result} -> result.provider_used end)
      |> Enum.map(fn {provider, provider_results} ->
        avg_cost = provider_results
        |> Enum.map(fn {:ok, result} -> result.cost_usd end)
        |> then(fn costs -> Enum.sum(costs) / length(costs) end)
        
        {provider, avg_cost}
      end)
      |> Enum.into(%{})
      
      # Cost-focused configuration should prefer lower-cost providers
      if Map.has_key?(provider_costs, "openai") and Map.has_key?(provider_costs, "anthropic") do
        openai_cost = provider_costs["openai"]
        anthropic_cost = provider_costs["anthropic"]
        
        # OpenAI typically cheaper, should be used more with cost focus
        openai_usage = successful_results
        |> Enum.count(fn {:ok, result} -> result.provider_used == "openai" end)
        
        anthropic_usage = successful_results  
        |> Enum.count(fn {:ok, result} -> result.provider_used == "anthropic" end)
        
        if openai_cost < anthropic_cost do
          assert openai_usage >= anthropic_usage,
                 "Cost optimization should prefer cheaper provider: OpenAI(#{openai_usage}) vs Anthropic(#{anthropic_usage})"
        end
      end
    end
  end
  
  describe "performance integration validation" do
    test "validates configuration resolution performance across domains", %{integration_context: context} do
      # Test configuration resolution performance across all integrated domains
      user = create_integration_test_user()
      project = create_integration_test_project(user)
      
      domains = [:verdict, :skills_actions, :universal_providers]
      
      # Test configuration resolution for each domain
      resolution_results = domains
      |> Enum.map(fn domain ->
        {domain, test_configuration_resolution(user.id, project.id, domain)}
      end)
      |> Enum.into(%{})
      
      # Validate all resolutions successful
      Enum.each(resolution_results, fn {domain, result} ->
        case result do
          {:ok, resolution_data} ->
            assert resolution_data.resolution_time_ms < 10,
                   "#{domain} configuration resolution too slow: #{resolution_data.resolution_time_ms}ms"
          
          {:error, error, resolution_time} ->
            flunk("#{domain} configuration resolution failed: #{inspect(error)} in #{resolution_time}ms")
        end
      end)
      
      # Validate consistent resolution times
      resolution_times = resolution_results
      |> Map.values()
      |> Enum.map(fn {:ok, data} -> data.resolution_time_ms end)
      
      avg_resolution_time = Enum.sum(resolution_times) / length(resolution_times)
      max_resolution_time = Enum.max(resolution_times)
      
      assert avg_resolution_time < 8.0,
             "Average configuration resolution too slow: #{avg_resolution_time}ms"
      
      assert max_resolution_time < 15.0,
             "Maximum configuration resolution too slow: #{max_resolution_time}ms"
      
      # Validate configuration consistency across domains
      verdict_config = resolution_results[:verdict] |> elem(1) |> Map.get(:config)
      skills_config = resolution_results[:skills_actions] |> elem(1) |> Map.get(:config)
      
      # Should have consistent provider preferences
      verdict_providers = Map.get(verdict_config, :preferred_providers, [])
      skills_providers = get_in(skills_config, [:orchestration, :preferred_providers]) || []
      
      if not Enum.empty?(verdict_providers) and not Enum.empty?(skills_providers) do
        # Should have some overlap in provider preferences
        overlap = MapSet.intersection(MapSet.new(verdict_providers), MapSet.new(skills_providers))
        
        assert MapSet.size(overlap) > 0,
               "No provider preference consistency between domains: #{verdict_providers} vs #{skills_providers}"
      end
    end
  end
end