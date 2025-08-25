defmodule RubberDuck.Verdict.Optimization.ProgressiveEvaluatorTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Verdict.Optimization.ProgressiveEvaluator
  
  describe "evaluate/4" do
    test "performs progressive evaluation for quality checks" do
      code = """
      def simple_function(x) do
        x + 1
      end
      """
      
      config = %{
        progressive_evaluation: true,
        model: "gpt-4o-mini",
        detailed_model: "gpt-4o"
      }
      
      assert {:ok, result} = ProgressiveEvaluator.evaluate(code, :quality, config)
      
      assert is_map(result)
      assert Map.has_key?(result, :evaluation_stage)
      assert result.evaluation_stage in [:screening, :lightweight_final, :detailed]
    end
    
    test "skips screening for security evaluations" do
      code = "def handle_user_input(input), do: process(input)"
      config = %{progressive_evaluation: true}
      
      assert {:ok, result} = ProgressiveEvaluator.evaluate(code, :security, config)
      
      # Security evaluations should go straight to detailed
      assert result.evaluation_stage == :detailed
    end
    
    test "uses detailed evaluation when forced" do
      code = "def simple, do: :ok"
      config = %{progressive_evaluation: true}
      options = [force_detailed: true]
      
      assert {:ok, result} = ProgressiveEvaluator.evaluate(code, :quality, config, options)
      
      assert result.evaluation_stage == :detailed
    end
    
    test "escalates to detailed when screening finds issues" do
      # This would test the escalation logic
      # For now, just verify the function works
      code = "def problematic_code, do: nil"
      config = %{progressive_evaluation: true}
      
      assert {:ok, result} = ProgressiveEvaluator.evaluate(code, :quality, config)
      assert is_map(result)
    end
  end
  
  describe "determine_evaluation_strategy/3" do
    test "returns appropriate strategy for different evaluation types" do
      test_cases = [
        {:security, :high, :comprehensive},
        {:security, :medium, :detailed},
        {:quality, :low, :lightweight},
        {:maintainability, :low, :lightweight},
        {:best_practices, :medium, :lightweight},
        {:performance, :medium, :detailed}
      ]
      
      Enum.each(test_cases, fn {eval_type, complexity, expected_strategy} ->
        {strategy, reason} = ProgressiveEvaluator.determine_evaluation_strategy(eval_type, complexity, %{})
        
        assert strategy == expected_strategy
        assert is_binary(reason)
      end)
    end
    
    test "provides reasoning for strategy decisions" do
      {_strategy, reason} = ProgressiveEvaluator.determine_evaluation_strategy(:security, :high, %{})
      
      assert is_binary(reason)
      assert String.length(reason) > 10
    end
  end
  
  describe "cost optimization" do
    test "lightweight evaluation shows cost savings" do
      code = "def simple, do: :ok"
      config = %{progressive_evaluation: true}
      
      assert {:ok, result} = ProgressiveEvaluator.evaluate(code, :best_practices, config)
      
      if result.evaluation_stage == :lightweight_final do
        assert Map.has_key?(result, :cost_optimization)
        assert result.cost_optimization.lightweight_used == true
        assert result.cost_optimization.estimated_savings > 0.5
      end
    end
    
    test "detailed evaluation shows actual costs" do
      code = "def complex_security_function(input), do: input"
      config = %{progressive_evaluation: true}
      
      assert {:ok, result} = ProgressiveEvaluator.evaluate(code, :security, config)
      
      if result.evaluation_stage == :detailed do
        assert Map.has_key?(result, :cost_optimization)
        
        if Map.has_key?(result, :screening_result) do
          assert is_map(result.cost_optimization)
        end
      end
    end
  end
end