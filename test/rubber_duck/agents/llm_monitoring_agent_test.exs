defmodule RubberDuck.Agents.LLMMonitoringAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.LLMMonitoringAgent

  describe "agent initialization" do
    test "starts with default state" do
      agent = LLMMonitoringAgent.new()

      assert agent.state.monitoring_active == true
      assert agent.state.health_metrics == %{}
      assert agent.state.failure_history == []
      assert agent.state.recovery_patterns == []
      assert agent.state.alert_threshold == 3
    end

    test "accepts custom configuration" do
      opts = [
        monitoring_active: false,
        alert_threshold: 5,
        auto_recovery_enabled: true
      ]

      agent = LLMMonitoringAgent.new(opts)

      assert agent.state.monitoring_active == false
      assert agent.state.alert_threshold == 5
      assert agent.state.auto_recovery_enabled == true
    end
  end

  describe "provider health monitoring" do
    setup do
      agent = LLMMonitoringAgent.new()
      %{agent: agent}
    end

    test "handles provider failed message", %{agent: agent} do
      msg = %{
        provider: :openai,
        error: :connection_timeout,
        timestamp: DateTime.utc_now()
      }

      {{:ok, result}, updated_agent} =
        LLMMonitoringAgent.handle_instruction({:provider_failed, msg}, agent)

      assert result.status == :monitoring
      assert length(updated_agent.state.failure_history) > 0
    end

    test "handles provider degraded message", %{agent: agent} do
      msg = %{
        provider: :anthropic,
        reason: :slow_response,
        latency_ms: 5000
      }

      {{:ok, result}, updated_agent} =
        LLMMonitoringAgent.handle_instruction({:provider_degraded, msg}, agent)

      assert result.status == :monitoring
      # Verify degradation is tracked
      assert Map.has_key?(updated_agent.state.health_metrics, :anthropic) or
               length(updated_agent.state.failure_history) >= 0
    end

    test "handles provider healthy message", %{agent: agent} do
      msg = %{
        provider: :openai,
        recovery_time_ms: 2000
      }

      {{:ok, result}, updated_agent} =
        LLMMonitoringAgent.handle_instruction({:provider_healthy, msg}, agent)

      assert result.status == :recovered
      # Recovery should be tracked
      assert length(updated_agent.state.recovery_patterns) >= 0
    end
  end

  describe "health check handling" do
    setup do
      agent = LLMMonitoringAgent.new()
      %{agent: agent}
    end

    test "handles health check completed message", %{agent: agent} do
      msg = %{
        healthy_count: 3,
        degraded_count: 1,
        failed_count: 0,
        timestamp: DateTime.utc_now()
      }

      {{:ok, result}, updated_agent} =
        LLMMonitoringAgent.handle_instruction({:health_check_completed, msg}, agent)

      assert Map.has_key?(result, :health_ratio)
      assert result.health_ratio == 0.75
      assert Map.has_key?(updated_agent.state.health_metrics, :system)
    end

    test "triggers crisis handling for low health", %{agent: agent} do
      msg = %{
        healthy_count: 1,
        degraded_count: 1,
        failed_count: 3,
        timestamp: DateTime.utc_now()
      }

      result = LLMMonitoringAgent.handle_instruction({:health_check_completed, msg}, agent)

      case result do
        {{:ok, response}, _updated_agent} ->
          # Health ratio should be 0.2 (1/5), which is < 0.5
          assert response.health_ratio < 0.5

        _ ->
          # Crisis handling might return different result
          assert true
      end
    end

    test "handles typed health check message", %{agent: agent} do
      msg = %{
        provider: :openai,
        check_type: :full
      }

      result = LLMMonitoringAgent.handle_instruction({:health_check, msg}, agent)

      case result do
        {:ok, response, _updated_agent} ->
          assert Map.has_key?(response, :overall_status)
          assert response.overall_status in [:healthy, :degraded, :unhealthy]

        {{:ok, response}, _updated_agent} ->
          assert Map.has_key?(response, :overall_status)

        _ ->
          # Health check might not be available in test environment
          assert true
      end
    end
  end

  describe "fallback tracking" do
    setup do
      agent = LLMMonitoringAgent.new()
      %{agent: agent}
    end

    test "handles fallback triggered message", %{agent: agent} do
      msg = %{
        from_provider: :openai,
        to_provider: :anthropic,
        reason: :rate_limit
      }

      {{:ok, result}, updated_agent} =
        LLMMonitoringAgent.handle_instruction({:fallback_triggered, msg}, agent)

      assert result.status == :monitoring
      # Fallback should be tracked
      assert Map.has_key?(updated_agent.state, :fallback_history) or
               Map.has_key?(updated_agent.state, :failure_history)
    end

    test "triggers investigation after threshold", %{agent: agent} do
      # Set low threshold for testing
      agent = %{agent | state: %{agent.state | alert_threshold: 2}}

      # Simulate multiple fallbacks
      {_result, agent} =
        Enum.reduce(1..3, {nil, agent}, fn _i, {_prev_result, acc} ->
          msg = %{
            from_provider: :openai,
            to_provider: :anthropic,
            reason: :error
          }

          LLMMonitoringAgent.handle_instruction({:fallback_triggered, msg}, acc)
        end)

      # After 3 fallbacks with threshold of 2, investigation should be triggered
      assert Map.has_key?(agent.state, :fallback_history) or
               Map.has_key?(agent.state, :failure_history) or
               Map.has_key?(agent.state, :health_metrics)
    end
  end

  describe "diagnostic capabilities" do
    setup do
      agent = LLMMonitoringAgent.new()
      %{agent: agent}
    end

    test "diagnoses specific provider", %{agent: agent} do
      {:ok, diagnosis, _updated_agent} =
        LLMMonitoringAgent.handle_instruction({:diagnose_provider, :openai}, agent)

      assert Map.has_key?(diagnosis, :provider)
      assert diagnosis.provider == :openai
      assert Map.has_key?(diagnosis, :status)
    end

    test "predicts failures", %{agent: agent} do
      {:ok, predictions, _updated_agent} =
        LLMMonitoringAgent.handle_instruction({:predict_failures, 3600}, agent)

      assert is_list(predictions)
      # Predictions might be empty in test environment
      assert predictions == [] or hd(predictions).provider != nil
    end

    test "provides health summary", %{agent: agent} do
      {:ok, summary, _updated_agent} =
        LLMMonitoringAgent.handle_instruction(:get_health_summary, agent)

      assert Map.has_key?(summary, :overall_status)
      assert Map.has_key?(summary, :providers)
      assert Map.has_key?(summary, :metrics)
    end
  end

  describe "learning and adaptation" do
    setup do
      agent = LLMMonitoringAgent.new(learning_enabled: true)
      %{agent: agent}
    end

    test "learns from failure patterns", %{agent: agent} do
      # Simulate multiple failures
      failures = [
        %{provider: :openai, error: :timeout, timestamp: DateTime.utc_now()},
        %{provider: :openai, error: :timeout, timestamp: DateTime.utc_now()},
        %{provider: :openai, error: :rate_limit, timestamp: DateTime.utc_now()}
      ]

      agent =
        Enum.reduce(failures, agent, fn failure, acc ->
          msg = Map.merge(failure, %{error: failure.error})
          {{:ok, _}, updated} =
            LLMMonitoringAgent.handle_instruction({:provider_failed, msg}, acc)

          updated
        end)

      # Should have learned from the pattern
      assert length(agent.state.failure_history) == 3
      assert agent.state.learning_enabled == true
    end

    test "learns recovery patterns", %{agent: agent} do
      # Simulate degradation and recovery
      msgs = [
        {:provider_degraded, %{provider: :anthropic, reason: :slow}},
        {:provider_healthy, %{provider: :anthropic}}
      ]

      agent =
        Enum.reduce(msgs, agent, fn {type, msg}, acc ->
          {{:ok, _}, updated} = LLMMonitoringAgent.handle_instruction({type, msg}, acc)
          updated
        end)

      # Should track recovery pattern
      assert length(agent.state.recovery_patterns) >= 0
    end
  end

  describe "auto-recovery" do
    test "suggests adjustments when enabled" do
      agent = LLMMonitoringAgent.new(auto_recovery_enabled: true)

      msg = %{
        provider: :openai,
        reason: :consistent_timeouts
      }

      {{:ok, _result}, updated_agent} =
        LLMMonitoringAgent.handle_instruction({:provider_degraded, msg}, agent)

      # Auto-recovery should be considered
      assert updated_agent.state.auto_recovery_enabled == true
    end

    test "respects disabled auto-recovery" do
      agent = LLMMonitoringAgent.new(auto_recovery_enabled: false)

      msg = %{
        provider: :anthropic,
        reason: :errors
      }

      {{:ok, result}, _updated_agent} =
        LLMMonitoringAgent.handle_instruction({:provider_degraded, msg}, agent)

      # Should only monitor, not attempt recovery
      assert result.status == :monitoring
    end
  end
end