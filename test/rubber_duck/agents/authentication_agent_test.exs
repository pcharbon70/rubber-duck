defmodule RubberDuck.Agents.AuthenticationAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.AuthenticationAgent

  describe "AuthenticationAgent" do
    test "creates authentication agent" do
      assert {:ok, agent} = AuthenticationAgent.create_authentication_agent()
      assert agent.active_sessions == %{}
      assert agent.user_profiles == %{}
      assert agent.security_policies == %{}
      assert is_list(agent.security_events)
    end

    test "enhances user session" do
      {:ok, agent} = AuthenticationAgent.create_authentication_agent()

      session_data = %{age_hours: 2, mfa_verified: false}
      request_context = %{ip_address: "192.168.1.1", device_new: false}

      assert {:ok, enhancement_result, updated_agent} =
               AuthenticationAgent.enhance_session(
                 agent,
                 "user123",
                 session_data,
                 request_context
               )

      assert Map.has_key?(enhancement_result, :session)
      assert Map.has_key?(enhancement_result, :analysis)
      assert map_size(updated_agent.active_sessions) > 0
    end

    test "analyzes user behavior" do
      {:ok, agent} = AuthenticationAgent.create_authentication_agent()

      behavior_data = %{
        rapid_requests: false,
        unusual_timing: false,
        new_location: true
      }

      assert {:ok, behavior_analysis, updated_agent} =
               AuthenticationAgent.analyze_user_behavior(agent, "user123", behavior_data)

      assert Map.has_key?(behavior_analysis, :behavior_pattern)
      assert Map.has_key?(behavior_analysis, :trust_score)
      assert map_size(updated_agent.user_profiles) > 0
    end

    test "adjusts security policies" do
      {:ok, agent} = AuthenticationAgent.create_authentication_agent()

      risk_context = %{threat_level: :high, recent_incidents: 2}

      assert {:ok, adjusted_policies, updated_agent} =
               AuthenticationAgent.adjust_security_policies(agent, :high, risk_context)

      assert is_map(adjusted_policies)
      assert Map.has_key?(updated_agent, :security_policies)
    end

    test "gets authentication status" do
      {:ok, agent} = AuthenticationAgent.create_authentication_agent()

      assert {:ok, status_report} = AuthenticationAgent.get_authentication_status(agent)
      assert Map.has_key?(status_report, :active_session_count)
      assert Map.has_key?(status_report, :overall_security_health)
    end
  end
end
