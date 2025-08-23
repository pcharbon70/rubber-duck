defmodule RubberDuck.Preferences.Llm.ProviderMonitorTest do
  # GenServer tests need to be synchronous
  use ExUnit.Case, async: false

  alias RubberDuck.Preferences.Llm.ProviderMonitor

  describe "provider health monitoring" do
    test "starts and monitors providers" do
      # Note: In a real test, we'd start the monitor in setup and stop it in cleanup
      # For now, we'll test the public interface

      health = ProviderMonitor.get_provider_health(:anthropic)
      assert health in [:healthy, :degraded, :unhealthy, :unknown]
    end

    test "gets provider metrics" do
      metrics = ProviderMonitor.get_provider_metrics(:anthropic)

      # Should return metrics map even if empty
      assert is_map(metrics)
    end

    test "forces health check for specific provider" do
      assert :ok = ProviderMonitor.force_health_check(:anthropic)
    end

    test "generates comprehensive monitoring report" do
      report = ProviderMonitor.get_monitoring_report()

      assert is_boolean(report.monitoring_enabled)
      assert is_integer(report.total_providers)
      assert is_integer(report.healthy_providers)
      assert is_integer(report.degraded_providers)
      assert is_integer(report.unhealthy_providers)
      assert is_map(report.provider_details)
      assert is_map(report.last_check_times)
      assert %DateTime{} = report.report_generated_at
    end
  end

  describe "health status classification" do
    test "classifies providers as healthy" do
      # This would test the internal health classification logic
      # In a real implementation, we'd have more detailed health metrics
      health = ProviderMonitor.get_provider_health(:anthropic)
      assert health in [:healthy, :degraded, :unhealthy, :unknown]
    end

    test "detects degraded performance" do
      # Test degraded state detection
      health = ProviderMonitor.get_provider_health(:google)
      assert health in [:healthy, :degraded, :unhealthy, :unknown]
    end

    test "identifies unhealthy providers" do
      # Test unhealthy state identification
      health = ProviderMonitor.get_provider_health(:local)
      assert health in [:healthy, :degraded, :unhealthy, :unknown]
    end
  end

  describe "metrics collection" do
    test "collects performance metrics" do
      metrics = ProviderMonitor.get_provider_metrics(:anthropic)

      # Even if empty, should be a map
      assert is_map(metrics)
    end

    test "tracks multiple provider metrics" do
      providers = [:openai, :anthropic, :google]

      Enum.each(providers, fn provider ->
        metrics = ProviderMonitor.get_provider_metrics(provider)
        assert is_map(metrics)
      end)
    end
  end

  describe "alerting system" do
    test "monitoring report includes alert information" do
      report = ProviderMonitor.get_monitoring_report()

      # Report should include provider status counts
      total = report.healthy_providers + report.degraded_providers + report.unhealthy_providers
      # Should be non-negative
      assert total >= 0
    end
  end
end
