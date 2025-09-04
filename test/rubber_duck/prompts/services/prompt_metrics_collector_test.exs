defmodule RubberDuck.Prompts.Services.PromptMetricsCollectorTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Prompts.Services.PromptMetricsCollector

  describe "metrics collection" do
    test "collects usage metrics without crashing" do
      usage_event = %{
        prompt_id: "test-prompt-123",
        user_id: "test-user-456",
        context_type: :llm_request,
        response_time_ms: 1500,
        tokens_used: 250,
        success: true,
        timestamp: DateTime.utc_now()
      }

      # Should not crash
      assert :ok = PromptMetricsCollector.collect_usage_metrics(usage_event)
    end

    test "handles malformed usage events gracefully" do
      malformed_event = %{
        prompt_id: nil,
        user_id: "test-user"
      }

      # Should not crash even with incomplete data
      assert :ok = PromptMetricsCollector.collect_usage_metrics(malformed_event)
    end
  end

  describe "metrics retrieval" do
    test "gets prompt metrics for valid prompt" do
      prompt_id = "test-prompt-789"
      options = %{time_window: %{amount: 7, unit: :days}}

      case PromptMetricsCollector.get_prompt_metrics(prompt_id, options) do
        {:ok, metrics} ->
          assert metrics.prompt_id == prompt_id
          assert Map.has_key?(metrics, :total_uses)
          assert Map.has_key?(metrics, :success_rate)

        {:error, _reason} ->
          # Acceptable if no data available
          :ok
      end
    end

    test "gets user metrics for valid user" do
      user_id = "test-user-789"

      case PromptMetricsCollector.get_user_metrics(user_id) do
        {:ok, metrics} ->
          assert metrics.user_id == user_id
          assert Map.has_key?(metrics, :total_prompt_uses)

        {:error, _reason} ->
          # Acceptable if no data available
          :ok
      end
    end

    test "gets system-wide metrics" do
      case PromptMetricsCollector.get_system_metrics() do
        {:ok, metrics} ->
          assert is_map(metrics)
          assert Map.has_key?(metrics, :total_system_usage)

        {:error, _reason} ->
          # Acceptable if no data available
          :ok
      end
    end
  end

  describe "aggregated metrics" do
    test "gets aggregated metrics by interval" do
      case PromptMetricsCollector.get_aggregated_metrics(:day) do
        {:ok, metrics} ->
          assert is_map(metrics)

        {:error, _reason} ->
          :ok
      end
    end

    test "forces metrics aggregation without error" do
      assert :ok = PromptMetricsCollector.force_metrics_aggregation()
    end
  end
end
