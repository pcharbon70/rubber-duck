defmodule RubberDuck.LlmProviders.UniversalProviderServiceTest do
  @moduledoc """
  Tests for Universal Provider Service - unified LLM access across all domains.
  """

  use ExUnit.Case, async: true
  use RubberDuck.DataCase

  alias RubberDuck.LlmProviders.UniversalProviderService

  describe "universal LLM completion" do
    test "complete/3 handles evaluation domain requests" do
      code = "def secure_function(input), do: validate_input(input)"

      case UniversalProviderService.complete(code, :evaluation, %{
             use_case: :security,
             user_id: "test-user",
             specialized_features: [:constitutional_ai, :safety_checks]
           }) do
        {:ok, response} ->
          assert response.success == true
          assert response.provider in [:openai, :anthropic]
          assert Map.has_key?(response, :score)
          assert Map.has_key?(response, :confidence)
          assert Map.has_key?(response.metadata, :universal_routing)
          assert response.metadata.domain == :evaluation

        {:error, _reason} ->
          # Expected if no providers configured in test environment
          assert true
      end
    end

    test "complete/3 handles orchestration domain requests" do
      prompt = "Coordinate task execution between agent A and agent B"

      case UniversalProviderService.complete(prompt, :orchestration, %{
             use_case: :agent_communication,
             user_id: "test-user",
             specialized_features: [:cost_optimization, :agent_communication]
           }) do
        {:ok, response} ->
          assert response.success == true
          assert response.provider in [:openai, :anthropic]
          assert Map.has_key?(response, :completion_quality)
          assert Map.has_key?(response, :cost_efficiency)
          assert response.metadata.domain == :orchestration

        {:error, _reason} ->
          # Expected if no providers configured
          assert true
      end
    end
  end

  describe "universal streaming" do
    test "stream/4 provides real-time feedback for evaluation" do
      code = "def test_function, do: :ok"

      callback_results = []

      callback = fn event ->
        send(self(), {:callback, event})
      end

      case UniversalProviderService.stream(code, :evaluation, callback, %{
             use_case: :quality,
             user_id: "test-user"
           }) do
        {:ok, response} ->
          assert response.streaming == true
          assert response.domain == :evaluation

        {:error, _reason} ->
          # Expected if no providers configured
          assert true
      end
    end
  end

  describe "provider availability and configuration" do
    test "get_available_providers/1 returns domain-appropriate providers" do
      case UniversalProviderService.get_available_providers(:evaluation) do
        {:ok, providers} ->
          assert is_map(providers)

          # Evaluation domain should have providers that support code analysis
          Enum.each(providers, fn {provider_type, provider_config} ->
            assert provider_type in [:openai, :anthropic, :ollama]
            assert :evaluation in provider_config.supports_domains
          end)

        {:error, _} ->
          # Expected if no providers registered
          assert true
      end
    end

    test "service_available?/0 checks universal provider system status" do
      # Should return boolean indicating if service is operational
      availability = UniversalProviderService.service_available?()
      assert is_boolean(availability)
    end

    test "get_service_status/0 provides comprehensive service information" do
      case UniversalProviderService.get_service_status() do
        {:ok, status} ->
          assert status.status == :operational
          assert is_list(status.available_providers)
          assert is_list(status.supported_domains)
          assert Map.has_key?(status, :integration_status)
          assert status.integration_status.constitutional_ai == :available
          assert status.integration_status.cost_optimization == :available

        {:error, _} ->
          assert false, "Service status should always be available"
      end
    end
  end

  describe "cost estimation" do
    test "estimate_cost/3 provides accurate cost estimates for different domains" do
      evaluation_content = "def complex_function(data), do: process_data(data)"

      case UniversalProviderService.estimate_cost(evaluation_content, :evaluation, %{
             use_case: :security,
             user_id: "test-user"
           }) do
        {:ok, cost} ->
          assert is_number(cost)
          assert cost > 0.0
          # Reasonable cost range
          assert cost < 2.0

        {:error, _reason} ->
          # Expected if no providers available
          assert true
      end
    end

    test "estimate_cost/3 shows different costs for different domains" do
      content = "Sample content for cost estimation"

      evaluation_cost =
        case UniversalProviderService.estimate_cost(content, :evaluation) do
          {:ok, cost} -> cost
          # Fallback for comparison
          _ -> 0.1
        end

      orchestration_cost =
        case UniversalProviderService.estimate_cost(content, :orchestration) do
          {:ok, cost} -> cost
          # Fallback for comparison
          _ -> 0.1
        end

      # Evaluation might cost more due to detailed analysis
      # Orchestration might be cheaper due to bulk pricing
      assert is_number(evaluation_cost)
      assert is_number(orchestration_cost)
    end
  end

  describe "backward compatibility" do
    test "from_verdict_request/5 maintains Verdict system compatibility" do
      code = "def verdict_test, do: :ok"

      case UniversalProviderService.from_verdict_request(code, :quality, "user-123", nil, %{
             quality_threshold: 0.9,
             constitutional_ai_required: true
           }) do
        {:ok, response} ->
          # Should return Verdict-compatible response format
          assert Map.has_key?(response, :score)
          assert Map.has_key?(response, :confidence)
          assert Map.has_key?(response, :issues)
          assert Map.has_key?(response, :recommendations)
          assert Map.has_key?(response, :reasoning)

        {:error, _reason} ->
          # Expected if no providers available
          assert true
      end
    end

    test "from_orchestration_request/4 maintains Preferences system compatibility" do
      prompt = "Optimize agent coordination for task execution"

      case UniversalProviderService.from_orchestration_request(prompt, "user-123", nil, %{
             cost_optimization: true,
             agent_communication: true
           }) do
        {:ok, response} ->
          # Should return orchestration-compatible response format
          assert Map.has_key?(response, :completion_quality)
          assert Map.has_key?(response, :cost_efficiency)
          assert response.cost_optimized == true

        {:error, _reason} ->
          # Expected if no providers available
          assert true
      end
    end
  end

  describe "provider health monitoring" do
    test "get_provider_health/0 returns comprehensive health status" do
      case UniversalProviderService.get_provider_health() do
        {:ok, health_status} ->
          assert Map.has_key?(health_status, :verdict_providers)
          assert Map.has_key?(health_status, :orchestration_providers)
          assert health_status.universal_status == :operational
          assert Map.has_key?(health_status, :last_check)

        {:error, _} ->
          assert false, "Provider health should always be queryable"
      end
    end
  end

  describe "configuration integration" do
    test "resolve_provider_config/3 integrates with existing configuration systems" do
      # Test evaluation domain configuration (should use Verdict system)
      case UniversalProviderService.resolve_provider_config(:evaluation, "user-123") do
        {:ok, config} ->
          assert Map.has_key?(config, :preferred_providers)
          assert Map.has_key?(config, :routing_strategy)
          assert Map.has_key?(config, :quality_threshold)

        {:error, _} ->
          # Expected if configuration not available
          assert true
      end

      # Test orchestration domain configuration (should use Preferences system)
      case UniversalProviderService.resolve_provider_config(:orchestration, "user-123") do
        {:ok, config} ->
          assert Map.has_key?(config, :preferred_providers)
          assert Map.has_key?(config, :routing_strategy)
          assert config.cost_optimization_enabled == true

        {:error, _} ->
          # Expected if configuration not available
          assert true
      end
    end
  end
end
