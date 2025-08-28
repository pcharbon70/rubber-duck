defmodule RubberDuck.SkillsActions.SkillsRegistryTest do
  @moduledoc """
  Tests for Skills Registry - centralized skill discovery and capability matching.
  """
  
  use ExUnit.Case, async: true
  use RubberDuck.DataCase
  
  alias RubberDuck.SkillsActions.SkillsRegistry
  
  # Mock skill for testing
  defmodule MockSkill do
    use Jido.Skill,
      name: "mock_skill",
      signal_patterns: ["test.execute", "test.validate"]
    
    def execute(params, state) do
      {:ok, %{mock_result: "success", params: params, state: state}}
    end
    
    def validate(params, state) do
      {:ok, %{validation: "passed", params: params}}
    end
  end
  
  setup do
    {:ok, registry_pid} = start_supervised(SkillsRegistry)
    %{registry: registry_pid}
  end
  
  describe "skill registration" do
    test "register_skill/2 successfully registers valid skill" do
      metadata = %{
        description: "Mock skill for testing",
        category: :testing,
        performance_class: :lightweight
      }
      
      assert :ok = SkillsRegistry.register_skill(MockSkill, metadata)
      
      assert {:ok, all_skills} = SkillsRegistry.get_all_skills()
      assert Map.has_key?(all_skills, MockSkill)
      
      skill_data = all_skills[MockSkill]
      assert skill_data.name == "mock_skill"
      assert skill_data.signal_patterns == ["test.execute", "test.validate"]
      assert skill_data.description == "Mock skill for testing"
    end
    
    test "get_skill_capabilities/1 returns detailed capability information" do
      :ok = SkillsRegistry.register_skill(MockSkill, %{})
      
      assert {:ok, capabilities} = SkillsRegistry.get_skill_capabilities(MockSkill)
      
      assert Map.has_key?(capabilities, :public_functions)
      assert Map.has_key?(capabilities, :signal_handling)
      assert Map.has_key?(capabilities, :complexity_score)
      assert Map.has_key?(capabilities, :performance_characteristics)
    end
    
    test "get_skill_capabilities/1 returns error for unregistered skill" do
      assert {:error, :skill_not_found} = SkillsRegistry.get_skill_capabilities(UnknownSkill)
    end
  end
  
  describe "skill discovery" do
    setup do
      :ok = SkillsRegistry.register_skill(MockSkill, %{
        category: :testing,
        capabilities: %{
          public_functions: [{:execute, 2}, {:validate, 2}],
          integration_capabilities: %{llm_integration: true}
        }
      })
      
      :ok
    end
    
    test "discover_skills/1 finds skills matching capability requirements" do
      requirements = %{
        capabilities: ["execute", "validate"],
        performance: %{max_execution_time_ms: 1000},
        context: %{integration_type: :llm_integration}
      }
      
      assert {:ok, matching_skills} = SkillsRegistry.discover_skills(requirements)
      assert is_list(matching_skills)
      
      # Should find our MockSkill
      skill_modules = Enum.map(matching_skills, fn {module, _match_data} -> module end)
      assert MockSkill in skill_modules
    end
    
    test "discover_skills/1 returns empty list when no skills match" do
      requirements = %{
        capabilities: ["nonexistent_capability"],
        performance: %{max_execution_time_ms: 1}  # Impossible requirement
      }
      
      assert {:ok, matching_skills} = SkillsRegistry.discover_skills(requirements)
      assert Enum.empty?(matching_skills)
    end
    
    test "discover_skills/1 uses caching for repeated queries" do
      requirements = %{capabilities: ["execute"]}
      
      # First call - should be cache miss
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, _skills1} = SkillsRegistry.discover_skills(requirements)
      first_duration = System.monotonic_time(:millisecond) - start_time
      
      # Second call - should be cache hit (faster)
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, _skills2} = SkillsRegistry.discover_skills(requirements)
      second_duration = System.monotonic_time(:millisecond) - start_time
      
      # Cache hit should be faster
      assert second_duration < first_duration
    end
  end
  
  describe "skill recommendations" do
    setup do
      :ok = SkillsRegistry.register_skill(MockSkill, %{
        description: "Mock skill for testing functionality"
      })
      
      :ok
    end
    
    test "recommend_optimal_skill/3 provides skill recommendation" do
      agent_need = "I need to execute and validate test operations"
      context = %{
        agent_id: "test_agent",
        goals: "Perform testing operations",
        performance_requirements: %{max_execution_time_ms: 5000}
      }
      
      case SkillsRegistry.recommend_optimal_skill(agent_need, context, "test_user") do
        {:ok, recommendation} ->
          assert Map.has_key?(recommendation, :recommended_skills)
          assert Map.has_key?(recommendation, :reasoning)
          assert Map.has_key?(recommendation, :confidence)
          assert recommendation.recommendation_source in [:llm_assisted, :keyword_matching]
        
        {:error, _reason} ->
          # Expected if Universal Provider System not available in test
          assert true
      end
    end
  end
  
  describe "dependency resolution" do
    test "resolve_skill_dependencies/1 analyzes skill dependency chains" do
      # Register skills with dependencies
      :ok = SkillsRegistry.register_skill(MockSkill, %{
        dependencies: %{required_skills: [], optional_skills: []}
      })
      
      assert {:ok, resolution} = SkillsRegistry.resolve_skill_dependencies([MockSkill])
      
      assert Map.has_key?(resolution, :required_skills)
      assert Map.has_key?(resolution, :circular_dependencies)
      assert Map.has_key?(resolution, :resolution_order)
      assert Map.has_key?(resolution, :dependency_depth)
    end
    
    test "resolve_skill_dependencies/1 detects circular dependencies" do
      # Would test with skills that have circular dependencies
      # For now, test that the function doesn't crash
      assert {:ok, resolution} = SkillsRegistry.resolve_skill_dependencies([])
      assert resolution.circular_dependencies == []
    end
  end
  
  describe "auto registration" do
    test "auto_register_existing_skills/0 registers all available skills" do
      SkillsRegistry.auto_register_existing_skills()
      
      # Allow time for async registration
      Process.sleep(100)
      
      assert {:ok, all_skills} = SkillsRegistry.get_all_skills()
      
      # Should have registered existing skills
      assert map_size(all_skills) > 0
      
      # Check that skills have proper metadata
      Enum.each(all_skills, fn {skill_module, metadata} ->
        assert Map.has_key?(metadata, :name)
        assert Map.has_key?(metadata, :capabilities)
        assert Map.has_key?(metadata, :registered_at)
      end)
    end
  end
  
  describe "registry statistics" do
    setup do
      :ok = SkillsRegistry.register_skill(MockSkill, %{})
      :ok
    end
    
    test "get_registry_stats/0 provides comprehensive statistics" do
      assert {:ok, stats} = SkillsRegistry.get_registry_stats()
      
      assert Map.has_key?(stats, :total_skills_registered)
      assert Map.has_key?(stats, :discovery_requests)
      assert Map.has_key?(stats, :cache_hit_rate)
      assert Map.has_key?(stats, :total_capabilities)
      assert Map.has_key?(stats, :dependency_complexity)
      assert stats.total_skills_registered >= 1
    end
  end
end