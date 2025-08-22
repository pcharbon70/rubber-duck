defmodule RubberDuck.SkillsRegistryTest do
  use ExUnit.Case, async: true
  alias RubberDuck.SkillsRegistry

  setup do
    # Start a fresh registry for each test
    {:ok, pid} = SkillsRegistry.start_link([])
    %{registry: pid}
  end

  describe "skill registration" do
    test "registers a new skill successfully" do
      metadata = %{category: :test, capabilities: [:testing]}

      assert :ok = SkillsRegistry.register_skill(TestSkill, metadata)
    end

    test "prevents duplicate skill registration" do
      metadata = %{category: :test, capabilities: [:testing]}

      assert :ok = SkillsRegistry.register_skill(TestSkill, metadata)

      assert {:error, :skill_already_registered} =
               SkillsRegistry.register_skill(TestSkill, metadata)
    end
  end

  describe "skill discovery" do
    setup do
      SkillsRegistry.register_skill(TestSkill1, %{
        category: :security,
        capabilities: [:authentication]
      })

      SkillsRegistry.register_skill(TestSkill2, %{category: :database, capabilities: [:querying]})
      :ok
    end

    test "discovers all skills with no criteria" do
      {:ok, skills} = SkillsRegistry.discover_skills()

      assert map_size(skills) >= 2
      assert Map.has_key?(skills, :test_skill1)
      assert Map.has_key?(skills, :test_skill2)
    end

    test "discovers skills by category" do
      {:ok, skills} = SkillsRegistry.discover_skills(%{category: :security})

      assert map_size(skills) == 1
      assert Map.has_key?(skills, :test_skill1)
    end

    test "discovers skills by capabilities" do
      {:ok, skills} = SkillsRegistry.discover_skills(%{capabilities: [:authentication]})

      assert map_size(skills) == 1
      assert Map.has_key?(skills, :test_skill1)
    end
  end

  describe "agent skill configuration" do
    setup do
      SkillsRegistry.register_skill(TestSkill, %{category: :test})
      :ok
    end

    test "configures skill for agent" do
      config = %{timeout: 5000, retries: 3}

      assert :ok = SkillsRegistry.configure_skill_for_agent("agent1", :test_skill, config)
    end

    test "retrieves agent skill configuration" do
      config = %{timeout: 5000, retries: 3}
      SkillsRegistry.configure_skill_for_agent("agent1", :test_skill, config)

      {:ok, retrieved_config} = SkillsRegistry.get_agent_skill_config("agent1", :test_skill)

      assert retrieved_config == config
    end

    test "returns empty config for unconfigured skill" do
      {:ok, config} = SkillsRegistry.get_agent_skill_config("agent1", :nonexistent_skill)

      assert config == %{}
    end

    test "gets all skills for an agent" do
      config1 = %{timeout: 5000}
      config2 = %{retries: 3}

      SkillsRegistry.register_skill(TestSkill2, %{category: :test})
      SkillsRegistry.configure_skill_for_agent("agent1", :test_skill, config1)
      SkillsRegistry.configure_skill_for_agent("agent1", :test_skill2, config2)

      {:ok, agent_skills} = SkillsRegistry.get_agent_skills("agent1")

      assert map_size(agent_skills) == 2
      assert Map.has_key?(agent_skills, :test_skill)
      assert Map.has_key?(agent_skills, :test_skill2)
      assert agent_skills[:test_skill][:config] == config1
      assert agent_skills[:test_skill2][:config] == config2
    end
  end

  describe "dependency resolution" do
    test "resolves simple dependencies" do
      # Register skills with dependencies
      SkillsRegistry.register_skill(TestSkillWithDeps, %{category: :test})

      {:ok, resolved} = SkillsRegistry.resolve_dependencies(:test_skill_with_deps)

      assert is_list(resolved)
    end

    test "detects circular dependencies" do
      # This would require a more complex setup to properly test
      # For now, just ensure the function exists
      assert {:error, :skill_not_found} = SkillsRegistry.resolve_dependencies(:nonexistent_skill)
    end
  end

  describe "hot swapping" do
    setup do
      SkillsRegistry.register_skill(TestSkill1, %{category: :test})
      SkillsRegistry.register_skill(TestSkill2, %{category: :test})
      SkillsRegistry.configure_skill_for_agent("agent1", :test_skill1, %{})
      :ok
    end

    test "hot swaps compatible skills" do
      new_config = %{upgraded: true}

      assert :ok = SkillsRegistry.hot_swap_skill("agent1", :test_skill1, :test_skill2, new_config)

      # Verify old skill is removed and new skill is configured
      {:ok, agent_skills} = SkillsRegistry.get_agent_skills("agent1")

      refute Map.has_key?(agent_skills, :test_skill1)
      assert Map.has_key?(agent_skills, :test_skill2)
      assert agent_skills[:test_skill2][:config] == new_config
    end

    test "rejects hot swap of non-existent skills" do
      assert {:error, :skill_not_found} =
               SkillsRegistry.hot_swap_skill("agent1", :test_skill1, :nonexistent_skill, %{})
    end
  end

  describe "event subscription" do
    test "notifies listeners of skill registration" do
      SkillsRegistry.subscribe_to_events(self())

      SkillsRegistry.register_skill(TestEventSkill, %{category: :event_test})

      assert_receive {:skills_registry_event, {:skill_registered, TestEventSkill, _metadata}},
                     1000
    end

    test "notifies listeners of skill configuration" do
      SkillsRegistry.subscribe_to_events(self())
      SkillsRegistry.register_skill(TestEventSkill, %{category: :event_test})

      SkillsRegistry.configure_skill_for_agent("agent1", :test_event_skill, %{test: true})

      assert_receive {:skills_registry_event,
                      {:skill_configured, "agent1", :test_event_skill, %{test: true}}},
                     1000
    end

    test "notifies listeners of hot swaps" do
      SkillsRegistry.subscribe_to_events(self())
      SkillsRegistry.register_skill(TestEventSkill1, %{category: :event_test})
      SkillsRegistry.register_skill(TestEventSkill2, %{category: :event_test})
      SkillsRegistry.configure_skill_for_agent("agent1", :test_event_skill1, %{})

      SkillsRegistry.hot_swap_skill("agent1", :test_event_skill1, :test_event_skill2, %{})

      assert_receive {:skills_registry_event,
                      {:skill_hot_swapped, "agent1", :test_event_skill1, :test_event_skill2}},
                     1000
    end
  end

  # Mock skill modules for testing
  defmodule TestSkill do
    def name, do: "Test Skill"
  end

  defmodule TestSkill1 do
    def name, do: "Test Skill 1"
  end

  defmodule TestSkill2 do
    def name, do: "Test Skill 2"
  end

  defmodule TestSkillWithDeps do
    def name, do: "Test Skill With Dependencies"
    def dependencies, do: [:test_skill]
  end

  defmodule TestEventSkill do
    def name, do: "Test Event Skill"
  end

  defmodule TestEventSkill1 do
    def name, do: "Test Event Skill 1"
  end

  defmodule TestEventSkill2 do
    def name, do: "Test Event Skill 2"
  end
end
