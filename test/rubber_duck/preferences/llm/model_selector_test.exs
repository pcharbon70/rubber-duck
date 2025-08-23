defmodule RubberDuck.Preferences.Llm.ModelSelectorTest do
  use RubberDuck.DataCase, async: true

  alias RubberDuck.Accounts.User
  alias RubberDuck.Preferences.Llm.ModelSelector
  alias RubberDuck.Preferences.Seeders.LlmDefaultsSeeder

  describe "model selection" do
    setup do
      user = create_test_user()

      # Seed LLM defaults
      :ok = LlmDefaultsSeeder.seed_all()

      %{user: user}
    end

    test "selects appropriate model based on requirements", %{user: user} do
      # Basic selection without special requirements
      assert {:ok, selection} = ModelSelector.select_model(user.id, [])

      assert selection.provider in [:openai, :anthropic, :google]
      assert is_binary(selection.model)
      assert is_map(selection.config)
    end

    test "respects context window requirements", %{user: user} do
      # Request large context window
      assert {:ok, selection} =
               ModelSelector.select_model(user.id,
                 min_context_window: 100_000
               )

      capabilities = ModelSelector.get_model_capabilities(selection.provider, selection.model)
      assert capabilities.context_window >= 100_000
    end

    test "respects cost constraints", %{user: user} do
      # Request low-cost model
      assert {:ok, selection} =
               ModelSelector.select_model(user.id,
                 max_cost_per_token: 0.000001
               )

      capabilities = ModelSelector.get_model_capabilities(selection.provider, selection.model)
      assert capabilities.cost_per_input_token <= 0.000001
    end

    test "respects function calling requirements", %{user: user} do
      # Request function calling capability
      assert {:ok, selection} =
               ModelSelector.select_model(user.id,
                 requires_functions: true
               )

      capabilities = ModelSelector.get_model_capabilities(selection.provider, selection.model)
      assert capabilities.supports_functions == true
    end

    test "respects vision requirements", %{user: user} do
      # Request vision capability
      assert {:ok, selection} =
               ModelSelector.select_model(user.id,
                 requires_vision: true
               )

      capabilities = ModelSelector.get_model_capabilities(selection.provider, selection.model)
      assert capabilities.supports_vision == true
    end

    test "returns error when no model meets requirements", %{user: user} do
      # Impossible requirements
      assert {:error, _} =
               ModelSelector.select_model(user.id,
                 # Impossibly large
                 min_context_window: 10_000_000,
                 # Impossibly cheap
                 max_cost_per_token: 0.0000000001
               )
    end
  end

  describe "model capabilities" do
    test "returns accurate capabilities for OpenAI models" do
      capabilities = ModelSelector.get_model_capabilities(:openai, "gpt-4")

      assert capabilities.context_window == 8192
      assert capabilities.max_output_tokens == 4096
      assert capabilities.supports_functions == true
      assert capabilities.supports_vision == false
      assert is_float(capabilities.cost_per_input_token)
      assert is_float(capabilities.cost_per_output_token)
    end

    test "returns accurate capabilities for Anthropic models" do
      capabilities =
        ModelSelector.get_model_capabilities(:anthropic, "claude-3-5-sonnet-20241022")

      assert capabilities.context_window == 200_000
      assert capabilities.max_output_tokens == 8192
      assert capabilities.supports_functions == true
      assert capabilities.supports_vision == true
    end

    test "returns accurate capabilities for Google models" do
      capabilities = ModelSelector.get_model_capabilities(:google, "gemini-1.5-pro")

      assert capabilities.context_window == 1_000_000
      assert capabilities.supports_functions == true
      assert capabilities.supports_vision == true
    end

    test "returns default capabilities for unknown models" do
      capabilities = ModelSelector.get_model_capabilities(:unknown, "unknown-model")

      assert capabilities.context_window == 4096
      assert capabilities.max_output_tokens == 2048
      assert capabilities.supports_functions == false
      assert capabilities.supports_vision == false
    end
  end

  describe "requirement checking" do
    test "correctly validates context window requirements" do
      assert ModelSelector.meets_requirements?(:anthropic, "claude-3-5-sonnet-20241022", %{
               min_context_window: 100_000
             }) == true

      assert ModelSelector.meets_requirements?(:openai, "gpt-4", %{
               min_context_window: 100_000
             }) == false
    end

    test "correctly validates cost requirements" do
      assert ModelSelector.meets_requirements?(:anthropic, "claude-3-5-haiku-20241022", %{
               max_cost_per_token: 0.000001
             }) == true

      assert ModelSelector.meets_requirements?(:openai, "gpt-4", %{
               max_cost_per_token: 0.000001
             }) == false
    end

    test "correctly validates function requirements" do
      assert ModelSelector.meets_requirements?(:openai, "gpt-4", %{
               requires_functions: true
             }) == true

      assert ModelSelector.meets_requirements?(:openai, "gpt-3.5-turbo", %{
               requires_functions: false
             }) == true
    end
  end

  describe "cost estimation" do
    test "estimates cost accurately" do
      cost = ModelSelector.estimate_cost(:openai, "gpt-4", 1000, 500)

      assert is_float(cost)
      assert cost > 0.0
    end

    test "different models have different costs" do
      gpt4_cost = ModelSelector.estimate_cost(:openai, "gpt-4", 1000, 500)
      haiku_cost = ModelSelector.estimate_cost(:anthropic, "claude-3-5-haiku-20241022", 1000, 500)

      # Haiku should be significantly cheaper
      assert haiku_cost < gpt4_cost
    end
  end

  describe "alternative models" do
    test "returns alternative models for providers" do
      openai_models = ModelSelector.get_alternative_models(:openai)
      assert "gpt-4" in openai_models
      assert "gpt-4-turbo" in openai_models

      anthropic_models = ModelSelector.get_alternative_models(:anthropic)
      assert "claude-3-5-sonnet-20241022" in anthropic_models
      assert "claude-3-5-haiku-20241022" in anthropic_models
    end

    test "returns empty list for unknown providers" do
      assert ModelSelector.get_alternative_models(:unknown) == []
    end
  end

  describe "default models" do
    test "returns appropriate default models" do
      assert ModelSelector.get_default_model(:openai) == "gpt-4"
      assert ModelSelector.get_default_model(:anthropic) == "claude-3-5-sonnet-20241022"
      assert ModelSelector.get_default_model(:google) == "gemini-1.5-pro"
      assert ModelSelector.get_default_model(:unknown) == "unknown"
    end
  end

  # Helper functions

  defp create_test_user do
    {:ok, user} =
      User.register_with_password(%{
        email: "test#{System.unique_integer()}@example.com",
        password: "password123"
      })

    user
  end

  defp generate_uuid, do: Ash.UUID.generate()
end
