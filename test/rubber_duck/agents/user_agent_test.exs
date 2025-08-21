defmodule RubberDuck.Agents.UserAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.UserAgent

  describe "UserAgent" do
    test "creates agent for user" do
      user_id = "test_user_123"

      assert {:ok, agent} = UserAgent.create_for_user(user_id)
      assert agent.user_id == user_id
      assert agent.session_data == %{}
      assert agent.behavior_patterns == %{}
      assert agent.preferences == %{}
      assert is_list(agent.proactive_suggestions)
    end

    test "records user activity" do
      user_id = "test_user_123"
      {:ok, agent} = UserAgent.create_for_user(user_id)

      assert {:ok, updated_agent} =
               UserAgent.record_activity(agent, :code_analysis, %{file: "test.ex"})

      assert map_size(updated_agent.behavior_patterns) > 0
    end

    test "gets behavior patterns" do
      user_id = "test_user_123"
      {:ok, agent} = UserAgent.create_for_user(user_id)
      {:ok, agent} = UserAgent.record_activity(agent, :code_analysis, %{})

      assert {:ok, patterns} = UserAgent.get_behavior_patterns(agent)
      assert is_map(patterns)
    end

    test "updates preferences" do
      user_id = "test_user_123"
      {:ok, agent} = UserAgent.create_for_user(user_id)

      assert {:ok, updated_agent} = UserAgent.update_preference(agent, :theme, :dark)
      assert updated_agent.preferences[:theme] == :dark
    end

    test "gets suggestions" do
      user_id = "test_user_123"
      {:ok, agent} = UserAgent.create_for_user(user_id)

      assert {:ok, suggestions} = UserAgent.get_suggestions(agent)
      assert is_list(suggestions)
    end
  end
end
