defmodule RubberDuck.Skills.ThreatDetectionSkillTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Skills.ThreatDetectionSkill

  describe "ThreatDetectionSkill" do
    test "detects threats in request data" do
      state = %{threat_patterns: [], baseline_patterns: %{}}

      params = %{
        request_data: %{suspicious_content: "script injection"},
        user_context: %{user_id: "user123", ip_address: "192.168.1.1"}
      }

      assert {:ok, threat_analysis, new_state} = ThreatDetectionSkill.detect_threat(params, state)
      assert Map.has_key?(threat_analysis, :threat_level)
      assert Map.has_key?(threat_analysis, :anomaly_score)
      assert Map.has_key?(threat_analysis, :confidence)
      assert length(new_state.threat_patterns) > 0
    end

    test "analyzes attack patterns" do
      state = %{attack_patterns: %{}, ip_reputation: %{}}

      params = %{
        attack_data: %{type: "brute force", attempts: 10},
        source_ip: "10.0.0.1"
      }

      assert {:ok, pattern_analysis, new_state} =
               ThreatDetectionSkill.analyze_pattern(params, state)

      assert Map.has_key?(pattern_analysis, :attack_type)
      assert Map.has_key?(pattern_analysis, :sophistication_level)
      assert map_size(new_state.attack_patterns) > 0
    end

    test "assesses risk level" do
      state = %{
        threat_patterns: [],
        risk_history: []
      }

      params = %{
        context: %{baseline_risk: 0.3, off_hours: true}
      }

      assert {:ok, risk_assessment, new_state} = ThreatDetectionSkill.assess_risk(params, state)
      assert Map.has_key?(risk_assessment, :current_risk_level)
      assert Map.has_key?(risk_assessment, :recommended_security_level)
      assert length(new_state.risk_history) > 0
    end

    test "coordinates threat response" do
      state = %{
        coordination_history: [],
        active_coordinations: []
      }

      params = %{
        threat_data: %{type: "sql_injection", severity: :high},
        response_type: :immediate
      }

      assert {:ok, coordination_plan, new_state} =
               ThreatDetectionSkill.coordinate_response(params, state)

      assert Map.has_key?(coordination_plan, :threat_id)
      assert Map.has_key?(coordination_plan, :coordinated_actions)
      assert length(new_state.coordination_history) > 0
    end
  end
end
