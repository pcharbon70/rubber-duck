defmodule RubberDuck.Verdict.EngineTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Verdict.Engine

  describe "evaluate_code/3" do
    test "evaluates code successfully with valid input" do
      code = """
      defmodule TestModule do
        def hello(name) do
          "Hello, \#{name}!"
        end
      end
      """

      assert {:ok, result} = Engine.evaluate_code(code, :quality)

      assert is_float(result.score)
      assert result.score >= 0.0 and result.score <= 1.0
      assert is_float(result.confidence)
      assert is_list(result.issues)
      assert is_list(result.recommendations)
      assert is_binary(result.reasoning)
    end

    test "rejects empty code" do
      assert {:error, "Code cannot be empty"} = Engine.evaluate_code("", :quality)
      assert {:error, "Code cannot be empty"} = Engine.evaluate_code(nil, :quality)
    end

    test "rejects invalid evaluation type" do
      code = "def test, do: :ok"

      assert {:error, "Evaluation type must be an atom"} = Engine.evaluate_code(code, "quality")
      assert {:error, "Invalid evaluation type: invalid"} = Engine.evaluate_code(code, :invalid)
    end

    test "rejects code that is too large" do
      # > 50k chars
      large_code = String.duplicate("def test, do: :ok\n", 2000)

      assert {:error, "Code too large for evaluation (max 50,000 characters)"} =
               Engine.evaluate_code(large_code, :quality)
    end

    test "handles different evaluation types" do
      code = "def secure_function(data), do: validate_and_process(data)"

      evaluation_types = [:quality, :security, :performance, :maintainability, :best_practices]

      Enum.each(evaluation_types, fn type ->
        assert {:ok, result} = Engine.evaluate_code(code, type)
        assert result.score >= 0.0 and result.score <= 1.0
      end)
    end
  end

  describe "get_evaluation_config/2" do
    test "returns default configuration when no user preferences exist" do
      assert {:ok, config} = Engine.get_evaluation_config("user123")

      assert config.enabled == true
      assert config.default_model == "gpt-4o-mini"
      assert config.quality_threshold == 0.8
      assert is_float(config.budget_per_day)
    end

    test "handles project-specific configuration" do
      assert {:ok, config} = Engine.get_evaluation_config("user123", "project456")

      assert is_map(config)
      assert Map.has_key?(config, :enabled)
    end
  end

  describe "evaluation_enabled?/2" do
    test "returns boolean for evaluation enablement status" do
      assert is_boolean(Engine.evaluation_enabled?("user123"))
      assert is_boolean(Engine.evaluation_enabled?("user123", "project456"))
    end

    test "handles configuration errors gracefully" do
      # This would test behavior when preference resolution fails
      assert is_boolean(Engine.evaluation_enabled?("invalid_user"))
    end
  end

  describe "estimate_evaluation_cost/3" do
    test "provides cost estimates for different evaluation types" do
      code = "def simple_function, do: :ok"

      evaluation_types = [:quality, :security, :performance, :maintainability]

      Enum.each(evaluation_types, fn type ->
        assert {:ok, estimate} = Engine.estimate_evaluation_cost(code, type)

        assert is_float(estimate.estimated_cost)
        assert estimate.estimated_cost > 0.0
        assert is_integer(estimate.estimated_tokens)
        assert is_float(estimate.confidence)
        assert is_map(estimate.model)
      end)
    end

    test "estimates increase with code complexity and evaluation depth" do
      simple_code = "def simple, do: :ok"

      complex_code = """
      defmodule ComplexModule do
        def complex_function(data) when is_map(data) do
          data
          |> validate_input()
          |> transform_data()
          |> handle_edge_cases()
          |> format_output()
        end
        
        defp validate_input(data), do: data
        defp transform_data(data), do: data
        defp handle_edge_cases(data), do: data
        defp format_output(data), do: data
      end
      """

      {:ok, simple_estimate} = Engine.estimate_evaluation_cost(simple_code, :quality)
      {:ok, complex_estimate} = Engine.estimate_evaluation_cost(complex_code, :quality)

      assert complex_estimate.estimated_cost > simple_estimate.estimated_cost
      assert complex_estimate.estimated_tokens > simple_estimate.estimated_tokens
    end

    test "security evaluations cost more than basic quality checks" do
      code = "def process_user_input(input), do: input"

      {:ok, quality_estimate} = Engine.estimate_evaluation_cost(code, :quality)
      {:ok, security_estimate} = Engine.estimate_evaluation_cost(code, :security)

      assert security_estimate.estimated_cost >= quality_estimate.estimated_cost
    end
  end

  describe "list_evaluation_types/0" do
    test "returns all available evaluation types with metadata" do
      types = Engine.list_evaluation_types()

      assert is_list(types)
      assert length(types) > 0

      Enum.each(types, fn type_info ->
        assert is_atom(type_info.type)
        assert is_binary(type_info.description)
        assert type_info.cost_tier in [:low, :medium, :high]
      end)
    end

    test "includes expected evaluation types" do
      types = Engine.list_evaluation_types()
      type_atoms = Enum.map(types, & &1.type)

      expected_types = [
        :quality,
        :security,
        :performance,
        :maintainability,
        :best_practices,
        :comprehensive
      ]

      Enum.each(expected_types, fn expected_type ->
        assert expected_type in type_atoms
      end)
    end
  end

  describe "evaluation pipeline integration" do
    test "evaluation results include required metadata" do
      code = "def test_function, do: :ok"

      assert {:ok, result} = Engine.evaluate_code(code, :quality)

      # Check for required result fields
      assert Map.has_key?(result, :score)
      assert Map.has_key?(result, :confidence)
      assert Map.has_key?(result, :issues)
      assert Map.has_key?(result, :recommendations)
      assert Map.has_key?(result, :reasoning)
      assert Map.has_key?(result, :model_used)
      assert Map.has_key?(result, :tokens_used)
      assert Map.has_key?(result, :cache_hit)
    end

    test "handles evaluation configuration options" do
      code = "def configured_test, do: :configured"

      options = [
        user_id: "test_user",
        project_id: "test_project",
        model: "gpt-4o",
        force_detailed: true
      ]

      assert {:ok, result} = Engine.evaluate_code(code, :quality, options)
      assert is_map(result)
    end
  end
end
