defmodule RubberDuck.Actions.EnhanceAshSignInTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Actions.EnhanceAshSignIn

  describe "EnhanceAshSignIn action" do
    test "enhances sign-in with security analysis" do
      params = %{
        user_credentials: %{email: "test@example.com", password: "secure_password"},
        request_context: %{ip_address: "192.168.1.1", user_agent: "TestAgent"},
        security_options: %{force_mfa: false}
      }

      context = %{agent_id: "test_agent"}

      assert {:ok, result} = EnhanceAshSignIn.run(params, context)
      assert Map.has_key?(result, :sign_in)
      assert Map.has_key?(result, :threat_analysis)
      assert Map.has_key?(result, :behavioral_analysis)
      assert Map.has_key?(result, :security_enhancements)
    end

    test "handles invalid credentials" do
      params = %{
        user_credentials: %{email: nil, password: nil},
        request_context: %{ip_address: "192.168.1.1"},
        security_options: %{}
      }

      context = %{agent_id: "test_agent"}

      assert {:error, :invalid_credentials} = EnhanceAshSignIn.run(params, context)
    end

    test "applies security enhancements based on threat level" do
      params = %{
        user_credentials: %{email: "test@example.com", password: "password"},
        request_context: %{
          ip_address: "unknown_ip",
          user_agent: "SuspiciousAgent",
          device_new: true
        },
        security_options: %{force_mfa: true}
      }

      context = %{agent_id: "test_agent", threat_patterns: []}

      assert {:ok, result} = EnhanceAshSignIn.run(params, context)

      enhancements = result.security_enhancements.enhancements
      assert :force_mfa in enhancements
      assert result.security_enhancements.security_level in [:elevated, :high, :maximum]
    end
  end
end
