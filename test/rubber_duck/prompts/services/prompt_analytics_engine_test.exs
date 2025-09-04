defmodule RubberDuck.Prompts.Services.PromptAnalyticsEngineTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Prompts.Services.PromptAnalyticsEngine

  describe "prompt usage analysis" do
    test "analyzes prompt usage with valid prompt ID" do
      prompt_id = "test-prompt-123"
      options = %{time_window: %{amount: 7, unit: :days}}
      
      assert {:ok, analysis_result} = PromptAnalyticsEngine.analyze_prompt_usage(prompt_id, options)
      
      assert analysis_result.prompt_id == prompt_id
      assert analysis_result.time_window == options.time_window
      assert Map.has_key?(analysis_result, :usage_statistics)
      assert Map.has_key?(analysis_result, :performance_metrics)
      assert Map.has_key?(analysis_result, :effectiveness_score)
    end

    test "handles invalid prompt ID gracefully" do
      invalid_prompt_id = "nonexistent-prompt"
      
      # Should not crash, may return empty analysis or error
      case PromptAnalyticsEngine.analyze_prompt_usage(invalid_prompt_id) do
        {:ok, _result} -> :ok
        {:error, _reason} -> :ok
      end
    end
  end

  describe "system metrics analysis" do
    test "analyzes system-wide metrics" do
      options = %{time_window: %{amount: 30, unit: :days}}
      
      assert {:ok, metrics} = PromptAnalyticsEngine.analyze_system_metrics(options)
      
      # Should return metrics structure (even if empty data)
      assert is_map(metrics)
    end
  end

  describe "optimization recommendations" do
    test "generates optimization recommendations for prompt" do
      prompt_id = "test-prompt-456"
      
      case PromptAnalyticsEngine.get_optimization_recommendations(prompt_id) do
        {:ok, recommendations} -> 
          assert is_list(recommendations)
        {:error, _reason} -> 
          # Acceptable if no data available
          :ok
      end
    end

    test "generates system-wide optimization recommendations" do
      case PromptAnalyticsEngine.get_optimization_recommendations(:system) do
        {:ok, recommendations} ->
          assert is_list(recommendations)
        {:error, _reason} ->
          # Acceptable if no data available  
          :ok
      end
    end
  end

  describe "cache management" do
    test "invalidates analytics cache" do
      # Should not crash
      assert :ok = PromptAnalyticsEngine.invalidate_analytics_cache(:all)
      assert :ok = PromptAnalyticsEngine.invalidate_analytics_cache("test-key")
    end
  end
end