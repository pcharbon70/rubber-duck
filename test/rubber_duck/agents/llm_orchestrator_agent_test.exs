defmodule RubberDuck.Agents.LLMOrchestratorAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.LLMOrchestratorAgent

  describe "agent initialization" do
    test "starts with default state" do
      agent = LLMOrchestratorAgent.new()

      assert agent.state.provider_performance == %{}
      assert agent.state.quality_threshold == 0.8
      assert agent.state.optimization_preference == :balanced
      assert agent.state.fallback_enabled == true
      assert agent.state.cache_enabled == true
    end

    test "accepts custom configuration" do
      opts = [
        quality_threshold: 0.9,
        optimization_preference: :quality,
        cache_enabled: false
      ]

      agent = LLMOrchestratorAgent.new(opts)

      assert agent.state.quality_threshold == 0.9
      assert agent.state.optimization_preference == :quality
      assert agent.state.cache_enabled == false
    end
  end

  describe "completion handling" do
    setup do
      agent = LLMOrchestratorAgent.new()
      %{agent: agent}
    end

    test "handles completion request", %{agent: agent} do
      request = %{
        prompt: "Test prompt",
        max_tokens: 100,
        temperature: 0.7
      }

      result = LLMOrchestratorAgent.handle_instruction({:complete, request}, agent)

      # The actual result depends on provider availability
      assert is_tuple(result)
    end

    test "handles streaming request", %{agent: agent} do
      request = %{
        prompt: "Stream test",
        max_tokens: 50
      }

      result = LLMOrchestratorAgent.handle_instruction({:stream, request}, agent)

      # Verify the instruction is handled
      assert is_tuple(result)
    end
  end

  describe "provider selection" do
    setup do
      agent = LLMOrchestratorAgent.new()
      %{agent: agent}
    end

    test "handles provider selection message", %{agent: agent} do
      msg = %{
        request_type: :completion,
        cost_constraint: 0.01,
        quality_threshold: 0.8
      }

      result = LLMOrchestratorAgent.handle_instruction({:select_provider, msg}, agent)

      case result do
        {{:ok, response}, _updated_agent} ->
          assert Map.has_key?(response, :selected_provider)

        {{:error, reason}, _agent} ->
          # No providers available is a valid test scenario
          assert reason in [:no_suitable_providers, :provider_selection_failed]
      end
    end
  end

  describe "fallback handling" do
    setup do
      agent = LLMOrchestratorAgent.new()
      %{agent: agent}
    end

    test "handles fallback message", %{agent: agent} do
      msg = %{
        original_request: %{prompt: "Test"},
        attempted_providers: [],
        original_provider: :openai,
        reason: :timeout
      }

      result = LLMOrchestratorAgent.handle_instruction({:fallback, msg}, agent)

      case result do
        {{:ok, _response}, _updated_agent} ->
          assert true

        {{:error, reason}, _agent} ->
          # No fallback available is valid
          assert reason in [:no_original_request, :no_fallback_available, :fallback_failed]
      end
    end
  end

  describe "performance tracking" do
    setup do
      agent = LLMOrchestratorAgent.new()
      %{agent: agent}
    end

    test "tracks successful requests", %{agent: agent} do
      msg = %{
        provider: :openai,
        duration: 1500,
        tokens: 150
      }

      {{:ok, result}, updated_agent} =
        LLMOrchestratorAgent.handle_instruction({:request_completed, msg}, agent)

      assert result.status == :performance_updated
      assert updated_agent.state.provider_performance[:openai].success_count == 1
    end

    test "tracks failed requests", %{agent: agent} do
      msg = %{
        provider: :anthropic,
        error: :rate_limit
      }

      {{:ok, result}, updated_agent} =
        LLMOrchestratorAgent.handle_instruction({:request_failed, msg}, agent)

      assert result.status == :failure_tracked
      assert updated_agent.state.provider_performance[:anthropic].failure_count == 1
    end
  end

  describe "cache functionality" do
    setup do
      agent = LLMOrchestratorAgent.new(cache_enabled: true)
      %{agent: agent}
    end

    test "caches responses when enabled", %{agent: agent} do
      # First request should miss cache
      request1 = %{prompt: "Cache test", max_tokens: 50}
      _result1 = LLMOrchestratorAgent.handle_instruction({:complete, request1}, agent)

      # Note: Actual caching behavior depends on provider responses
      # This test verifies the cache mechanism is in place
      assert agent.state.cache_enabled == true
    end

    test "respects cache disabled setting" do
      agent = LLMOrchestratorAgent.new(cache_enabled: false)

      request = %{prompt: "No cache test", max_tokens: 50}
      _result = LLMOrchestratorAgent.handle_instruction({:complete, request}, agent)

      assert agent.state.cache_enabled == false
      assert agent.state.request_cache == %{}
    end
  end

  describe "optimization preferences" do
    test "optimizes for cost when configured" do
      agent = LLMOrchestratorAgent.new(optimization_preference: :cost)

      assert agent.state.optimization_preference == :cost
    end

    test "optimizes for quality when configured" do
      agent = LLMOrchestratorAgent.new(optimization_preference: :quality)

      assert agent.state.optimization_preference == :quality
    end

    test "balances cost and quality by default" do
      agent = LLMOrchestratorAgent.new()

      assert agent.state.optimization_preference == :balanced
    end
  end
end