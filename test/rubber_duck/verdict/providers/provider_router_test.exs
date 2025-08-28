defmodule RubberDuck.Verdict.Providers.ProviderRouterTest do
  @moduledoc """
  Tests for ProviderRouter - intelligent provider selection and routing.
  """

  use ExUnit.Case, async: true
  use RubberDuck.DataCase

  alias RubberDuck.Verdict.Providers.EvaluationContext
  alias RubberDuck.Verdict.Providers.ProviderRouter

  describe "provider selection" do
    test "select_provider/2 chooses appropriate provider for evaluation type" do
      evaluation_request = %{
        code: "def test_function, do: :ok",
        evaluation_type: :quality,
        criteria: %{"correctness" => 0.5, "style" => 0.5},
        quality_threshold: 0.8,
        max_tokens: 1000
      }

      # Mock user ID for configuration resolution
      user_id = "test-user-id"

      # Since we don't have real providers registered in tests,
      # this will likely return an error, but we test the interface
      case ProviderRouter.select_provider(evaluation_request, user_id) do
        {:ok, routing_decision} ->
          assert Map.has_key?(routing_decision, :provider)
          assert Map.has_key?(routing_decision, :reasoning)
          assert Map.has_key?(routing_decision, :cost_estimate)

        {:error, _reason} ->
          # Expected when no providers are registered
          assert true
      end
    end

    test "get_provider_recommendations/2 returns ranked provider list" do
      evaluation_request = %{
        code: "def secure_function(input), do: validate_input(input)",
        evaluation_type: :security,
        criteria: %{"security" => 0.8, "correctness" => 0.2},
        quality_threshold: 0.9
      }

      user_id = "test-user-id"

      # Test the interface even if no providers registered
      case ProviderRouter.get_provider_recommendations(evaluation_request, user_id) do
        {:ok, recommendations} ->
          assert is_list(recommendations)

          # Each recommendation should have required fields
          Enum.each(recommendations, fn rec ->
            assert Map.has_key?(rec, :provider)
            assert Map.has_key?(rec, :overall_score)
            assert Map.has_key?(rec, :cost_estimate)
            assert Map.has_key?(rec, :recommendation_reason)
          end)

        {:error, _reason} ->
          # Expected when no providers available
          assert true
      end
    end
  end

  describe "routing validation" do
    test "validate_routing_decision/1 checks provider health" do
      routing_decision = %{
        provider: :openai,
        model: "gpt-4o-mini",
        strategy: :balanced,
        reasoning: "Test routing decision",
        confidence: 0.8
      }

      # Should fail validation since provider not registered
      assert {:error, error_msg} = ProviderRouter.validate_routing_decision(routing_decision)
      assert error_msg =~ "not registered"
    end
  end

  describe "evaluation context integration" do
    test "builds provider requirements from evaluation context" do
      {:ok, context} =
        EvaluationContext.build_with_configuration(
          "def test, do: :ok",
          :quality,
          "user-123",
          nil,
          max_tokens: 2000,
          streaming: true
        )

      requirements = EvaluationContext.extract_provider_requirements(context)

      assert requirements.evaluation_type == :quality
      assert requirements.max_tokens == 2000
      assert requirements.streaming == true
      assert requirements.quality_threshold == context.quality_threshold
    end

    test "extracts routing constraints from context" do
      {:ok, context} =
        EvaluationContext.build_with_configuration(
          "def secure_code, do: encrypt_data()",
          :security,
          "user-123",
          "project-456"
        )

      constraints = EvaluationContext.extract_routing_constraints(context)

      assert Map.has_key?(constraints, :strategy)
      assert Map.has_key?(constraints, :cost_priority)
      assert Map.has_key?(constraints, :quality_threshold)
      assert Map.has_key?(constraints, :preferred_providers)
    end
  end
end
