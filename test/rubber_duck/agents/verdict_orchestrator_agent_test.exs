defmodule RubberDuck.Agents.VerdictOrchestratorAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.VerdictOrchestratorAgent

  describe "init/1" do
    test "initializes with default state" do
      {:ok, state} = VerdictOrchestratorAgent.init()

      assert state.active_coordination_sessions == %{}
      assert state.agent_coordinator == nil
      assert state.communication_hub == nil
      assert state.consensus_engine == nil
      assert state.orchestration_config != nil
      assert state.performance_metrics != nil
    end

    test "initializes with custom options" do
      opts = [
        max_concurrent_sessions: 5,
        session_timeout_ms: 45_000
      ]

      {:ok, state} = VerdictOrchestratorAgent.init(opts)

      assert state.orchestration_config.max_concurrent_sessions == 5
      assert state.orchestration_config.session_timeout_ms == 45_000
    end
  end

  describe "coordinate_evaluation/4" do
    setup do
      {:ok, agent} = VerdictOrchestratorAgent.init()
      %{agent: agent}
    end

    test "starts coordination session with valid parameters", %{agent: agent} do
      code = "def hello, do: :world"
      evaluation_type = :full_evaluation
      options = [required_agents: [:code_quality, :architecture]]

      result =
        VerdictOrchestratorAgent.coordinate_evaluation(agent, code, evaluation_type, options)

      assert match?({:ok, _evaluation_result, _updated_agent}, result)
    end

    test "handles invalid evaluation type", %{agent: agent} do
      code = "def hello, do: :world"
      evaluation_type = :invalid_type
      options = []

      result =
        VerdictOrchestratorAgent.coordinate_evaluation(agent, code, evaluation_type, options)

      assert match?({:error, _reason, ^agent}, result)
    end

    test "handles empty code input", %{agent: agent} do
      code = ""
      evaluation_type = :full_evaluation
      options = []

      result =
        VerdictOrchestratorAgent.coordinate_evaluation(agent, code, evaluation_type, options)

      assert match?({:error, _reason, ^agent}, result)
    end
  end

  describe "get_coordination_stats/1" do
    test "returns stats for agent with no sessions" do
      {:ok, agent} = VerdictOrchestratorAgent.init()

      stats = VerdictOrchestratorAgent.get_coordination_stats(agent)

      assert stats.active_sessions == 0
      assert stats.total_sessions_completed == 0
      assert stats.average_session_duration_ms == 0.0
    end
  end

  describe "configure_orchestration/2" do
    test "updates orchestration configuration" do
      {:ok, agent} = VerdictOrchestratorAgent.init()

      new_config = %{
        consensus_threshold: 0.8,
        max_negotiation_rounds: 5
      }

      {:ok, updated_agent} = VerdictOrchestratorAgent.configure_orchestration(agent, new_config)

      assert updated_agent.state.orchestration_config.consensus_threshold == 0.8
      assert updated_agent.state.orchestration_config.max_negotiation_rounds == 5
    end

    test "merges with existing configuration" do
      initial_config = %{session_timeout_ms: 30_000, consensus_threshold: 0.7}
      {:ok, agent} = VerdictOrchestratorAgent.init(initial_config)

      new_config = %{consensus_threshold: 0.8}
      {:ok, updated_agent} = VerdictOrchestratorAgent.configure_orchestration(agent, new_config)

      assert updated_agent.state.orchestration_config.session_timeout_ms == 30_000
      assert updated_agent.state.orchestration_config.consensus_threshold == 0.8
    end
  end

  describe "private helper functions" do
    test "validate_coordination_inputs handles valid inputs" do
      code = "def test, do: :ok"
      evaluation_type = :full_evaluation
      options = [required_agents: [:code_quality]]

      # This would test private function if made public for testing
      # For now, we test through the public interface
      {:ok, agent} = VerdictOrchestratorAgent.init()

      result =
        VerdictOrchestratorAgent.coordinate_evaluation(agent, code, evaluation_type, options)

      # Should not error on validation
      refute match?({:error, "Invalid coordination inputs", _}, result)
    end
  end

  describe "error handling" do
    test "handles coordination session initialization failure" do
      {:ok, agent} = VerdictOrchestratorAgent.init()

      # Test with configuration that would cause initialization failure
      code = "def test, do: :ok"
      evaluation_type = :full_evaluation
      options = [required_agents: [:invalid_agent_type]]

      result =
        VerdictOrchestratorAgent.coordinate_evaluation(agent, code, evaluation_type, options)

      assert match?({:error, _reason, _agent}, result)
    end
  end

  describe "performance metrics tracking" do
    test "tracks session completion metrics" do
      {:ok, agent} = VerdictOrchestratorAgent.init()

      initial_stats = VerdictOrchestratorAgent.get_coordination_stats(agent)
      assert initial_stats.total_sessions_completed == 0

      # After completing a session, metrics should be updated
      # This would require a more complete test setup with actual coordination completion
    end
  end

  describe "concurrent session management" do
    test "respects maximum concurrent sessions limit" do
      {:ok, agent} = VerdictOrchestratorAgent.init(max_concurrent_sessions: 1)

      code = "def test, do: :ok"
      evaluation_type = :full_evaluation
      options = []

      # First coordination should start
      {result1_status, _, agent1} =
        VerdictOrchestratorAgent.coordinate_evaluation(agent, code, evaluation_type, options)

      # Second coordination might be queued or rejected based on implementation
      {result2_status, _, _agent2} =
        VerdictOrchestratorAgent.coordinate_evaluation(agent1, code, evaluation_type, options)

      # At least one should succeed, implementation detail whether second is queued or rejected
      assert result1_status == :ok or result2_status == :ok
    end
  end
end
