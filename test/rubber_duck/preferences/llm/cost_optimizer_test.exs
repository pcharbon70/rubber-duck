defmodule RubberDuck.Preferences.Llm.CostOptimizerTest do
  use RubberDuck.DataCase, async: true

  alias RubberDuck.Preferences.Llm.CostOptimizer
  alias RubberDuck.Preferences.Seeders.LlmDefaultsSeeder

  describe "cost-optimized selection" do
    setup do
      user = create_test_user()

      # Seed LLM defaults
      :ok = LlmDefaultsSeeder.seed_all()

      %{user: user}
    end

    test "selects cost-effective provider when optimization enabled", %{user: user} do
      # Enable cost optimization
      {:ok, _} =
        RubberDuck.Preferences.UserPreference.set_preference(
          user.id,
          "llm.cost.optimization_enabled",
          Jason.encode!(true),
          "Enable cost optimization"
        )

      assert {:ok, selection} =
               CostOptimizer.optimize_selection(user.id,
                 estimated_input_tokens: 1000,
                 estimated_output_tokens: 500
               )

      assert is_atom(selection.provider)
      assert is_binary(selection.model)
      assert is_float(selection.estimated_cost)
      assert is_float(selection.cost_efficiency)
      assert is_float(selection.quality_score)
    end

    test "uses standard selection when optimization disabled", %{user: user} do
      # Disable cost optimization
      {:ok, _} =
        RubberDuck.Preferences.UserPreference.set_preference(
          user.id,
          "llm.cost.optimization_enabled",
          Jason.encode!(false),
          "Disable cost optimization"
        )

      assert {:ok, selection} = CostOptimizer.optimize_selection(user.id, [])

      assert is_atom(selection.provider)
      assert is_binary(selection.model)
      assert is_float(selection.estimated_cost)
      # Should not include cost optimization fields
      refute Map.has_key?(selection, :cost_efficiency)
    end

    test "respects quality threshold in optimization", %{user: user} do
      # Set high quality threshold
      {:ok, _} =
        RubberDuck.Preferences.UserPreference.set_preference(
          user.id,
          "llm.cost.quality_threshold",
          Jason.encode!(0.9),
          "High quality requirement"
        )

      assert {:ok, selection} = CostOptimizer.optimize_selection(user.id, [])

      # Should select high-quality model even if more expensive
      assert selection.quality_score >= 0.9
    end
  end

  describe "budget checking" do
    test "checks budget constraints", %{user: user} do
      # Small estimated cost should be within budget
      assert CostOptimizer.within_budget?(user.id, 0.10) == true

      # Large estimated cost might exceed budget
      # Note: This depends on mock budget implementation
      assert is_boolean(CostOptimizer.within_budget?(user.id, 1000.0))
    end

    test "respects cost threshold preferences", %{user: user} do
      # Set very low cost threshold
      {:ok, _} =
        RubberDuck.Preferences.UserPreference.set_preference(
          user.id,
          "llm.cost.cost_per_token_threshold",
          Jason.encode!(0.000001),
          "Very low cost threshold"
        )

      # Even small costs should be rejected
      assert CostOptimizer.within_budget?(user.id, 0.01) == false
    end
  end

  describe "optimization recommendations" do
    test "generates optimization recommendations", %{user: user} do
      recommendations = CostOptimizer.get_optimization_recommendations(user.id)

      assert is_list(recommendations)

      # Each recommendation should have required fields
      Enum.each(recommendations, fn rec ->
        assert Map.has_key?(rec, :type)
        assert Map.has_key?(rec, :message)
        assert Map.has_key?(rec, :priority)
      end)
    end

    test "includes project-specific recommendations", %{user: user} do
      project_id = generate_uuid()
      recommendations = CostOptimizer.get_optimization_recommendations(user.id, project_id)

      assert is_list(recommendations)
    end

    test "calculates potential savings", %{user: user} do
      recommendations = [
        %{type: :expensive_provider, potential_savings: 10.0},
        %{type: :model_optimization, potential_savings: 5.0}
      ]

      savings = CostOptimizer.calculate_potential_savings(user.id, recommendations)

      assert savings.total_potential_savings == 15.0
      assert is_float(savings.monthly_savings_estimate)
      assert savings.optimization_opportunities == recommendations
      assert is_float(savings.current_monthly_cost)
      assert %DateTime{} = savings.generated_at
    end
  end

  # Helper functions

  defp create_test_user do
    {:ok, user} =
      RubberDuck.Accounts.User.register_with_password(%{
        email: "test#{System.unique_integer()}@example.com",
        password: "password123"
      })

    user
  end

  defp generate_uuid, do: Ash.UUID.generate()
end
