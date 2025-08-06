defmodule RubberDuck.LLM.HealthMonitorTest do
  use ExUnit.Case, async: false

  alias RubberDuck.LLM.{HealthMonitor, ProviderRegistry}

  setup do
    # Ensure services are started
    unless Process.whereis(ProviderRegistry) do
      {:ok, _} = ProviderRegistry.start_link()
    end

    unless Process.whereis(HealthMonitor) do
      {:ok, _} = HealthMonitor.start_link()
    end

    :ok
  end

  describe "record_success/2" do
    test "records successful request metrics" do
      # {System.unique_integer([:positive])}
      provider_name = :test_provider_

      HealthMonitor.record_success(provider_name, 100)
      HealthMonitor.record_success(provider_name, 150)

      # Give it a moment to process
      Process.sleep(10)

      metrics = HealthMonitor.get_metrics(provider_name)

      assert metrics.success_count == 2
      assert metrics.total_count == 2
      assert metrics.error_count == 0
      assert metrics.avg_response_time == 125.0
    end
  end

  describe "record_failure/2" do
    test "records failed request metrics" do
      # {System.unique_integer([:positive])}
      provider_name = :test_provider_

      HealthMonitor.record_failure(provider_name, :timeout)
      HealthMonitor.record_failure(provider_name, :connection_error)

      # Give it a moment to process
      Process.sleep(10)

      metrics = HealthMonitor.get_metrics(provider_name)

      assert metrics.error_count == 2
      assert metrics.total_count == 2
      assert metrics.success_count == 0
      assert metrics.last_error == :connection_error
    end
  end

  describe "get_metrics/1" do
    test "returns default metrics for unknown provider" do
      metrics = HealthMonitor.get_metrics(:unknown_provider)

      assert metrics.success_count == 0
      assert metrics.error_count == 0
      assert metrics.total_count == 0
      assert metrics.error_rate == 0.0
      assert metrics.available == true
    end

    test "calculates error rate after minimum samples" do
      # {System.unique_integer([:positive])}
      provider_name = :test_provider_

      # Record enough samples to calculate error rate
      for _ <- 1..8 do
        HealthMonitor.record_success(provider_name, 100)
      end

      for _ <- 1..2 do
        HealthMonitor.record_failure(provider_name, :error)
      end

      Process.sleep(20)

      metrics = HealthMonitor.get_metrics(provider_name)

      assert metrics.total_count == 10
      assert metrics.error_count == 2
      assert metrics.success_count == 8
      assert metrics.error_rate == 0.2
    end
  end

  describe "check_provider/1" do
    test "performs health check for registered provider" do
      # Create a mock provider module
      defmodule MockHealthProvider do
        def health_check(_config), do: :ok
      end

      # {System.unique_integer([:positive])}
      provider_name = :mock_health_provider_
      ProviderRegistry.register(provider_name, MockHealthProvider, %{})

      result = HealthMonitor.check_provider(provider_name)
      assert result == :ok
    end

    test "returns error for non-existent provider" do
      result = HealthMonitor.check_provider(:nonexistent_provider)
      assert result == {:error, :provider_not_found}
    end
  end

  describe "check_all/0" do
    test "performs health checks for all providers" do
      defmodule MockProvider1 do
        def health_check(_config), do: :ok
      end

      defmodule MockProvider2 do
        def health_check(_config), do: {:error, :unhealthy}
      end

      # {System.unique_integer([:positive])}
      provider1 = :provider1_
      # {System.unique_integer([:positive])}
      provider2 = :provider2_

      ProviderRegistry.register(provider1, MockProvider1, %{})
      ProviderRegistry.register(provider2, MockProvider2, %{})

      results = HealthMonitor.check_all()

      assert Map.get(results, provider1) == :ok
      assert Map.get(results, provider2) == {:error, :unhealthy}
    end
  end
end
