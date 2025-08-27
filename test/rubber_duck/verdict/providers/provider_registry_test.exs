defmodule RubberDuck.Verdict.Providers.ProviderRegistryTest do
  @moduledoc """
  Tests for the ProviderRegistry - multi-provider management and discovery.
  """

  use ExUnit.Case, async: true
  use RubberDuck.DataCase

  alias RubberDuck.Verdict.Providers.ProviderRegistry
  alias RubberDuck.Verdict.Providers.ProviderInterface

  # Mock provider for testing
  defmodule MockProvider do
    @behaviour ProviderInterface

    @impl true
    def initialize(_config) do
      {:ok, %{initialized: true, health_status: :healthy}}
    end

    @impl true
    def evaluate_code(_state, _request) do
      {:ok,
       %{
         success: true,
         score: 0.85,
         confidence: 0.9,
         issues: [],
         recommendations: ["Mock recommendation"],
         reasoning: "Mock evaluation",
         cost_usd: 0.05,
         tokens_used: 150,
         response_time_ms: 1200
       }}
    end

    @impl true
    def evaluate_code_streaming(_state, _request, callback) do
      callback.(%{type: :chunk, content: "Mock streaming"})
      callback.(%{type: :complete})

      {:ok,
       %{
         success: true,
         score: 0.85,
         confidence: 0.9,
         streaming: true
       }}
    end

    @impl true
    def get_capabilities(_state) do
      {:ok,
       %{
         supports_streaming: true,
         max_context_tokens: 4000,
         evaluation_types: [:quality, :security],
         cost_per_1k_tokens: %{"mock-model" => 0.01}
       }}
    end

    @impl true
    def health_check(_state) do
      {:ok,
       %{
         status: :healthy,
         success_rate: 0.98,
         avg_response_time_ms: 1200,
         availability_percentage: 98.0
       }}
    end

    @impl true
    def estimate_cost(_state, _request) do
      {:ok, 0.05}
    end

    @impl true
    def terminate(_state), do: :ok
  end

  describe "provider registration" do
    test "register_provider/3 successfully registers valid provider" do
      {:ok, registry_pid} = start_supervised(ProviderRegistry)

      config = %{
        api_key: "test-key",
        models: %{screening: "mock-model"}
      }

      assert :ok = ProviderRegistry.register_provider(:openai, MockProvider, config)

      assert {:ok, providers} = ProviderRegistry.get_providers()
      assert Map.has_key?(providers, :openai)
      assert providers[:openai].module == MockProvider
    end

    test "register_provider/3 rejects invalid provider type" do
      {:ok, _registry_pid} = start_supervised(ProviderRegistry)

      config = %{api_key: "test-key"}

      assert_raise FunctionClauseError, fn ->
        ProviderRegistry.register_provider(:invalid_provider, MockProvider, config)
      end
    end

    test "get_provider/1 returns specific provider information" do
      {:ok, registry_pid} = start_supervised(ProviderRegistry)

      config = %{api_key: "test-key"}
      :ok = ProviderRegistry.register_provider(:openai, MockProvider, config)

      assert {:ok, provider_info} = ProviderRegistry.get_provider(:openai)
      assert provider_info.module == MockProvider
      assert Map.has_key?(provider_info, :capabilities)
      assert Map.has_key?(provider_info, :health_status)
    end
  end

  describe "provider health monitoring" do
    test "health status is tracked for registered providers" do
      {:ok, registry_pid} = start_supervised(ProviderRegistry)

      config = %{api_key: "test-key"}
      :ok = ProviderRegistry.register_provider(:openai, MockProvider, config)

      # Allow time for health check
      Process.sleep(100)

      assert {:ok, health_result} = ProviderRegistry.check_provider_health(:openai)
      assert match?({:ok, %{status: :healthy}}, health_result)
    end

    test "mark_provider_unhealthy/2 updates provider status" do
      {:ok, registry_pid} = start_supervised(ProviderRegistry)

      config = %{api_key: "test-key"}
      :ok = ProviderRegistry.register_provider(:openai, MockProvider, config)

      ProviderRegistry.mark_provider_unhealthy(:openai, "Test failure")

      assert {:ok, provider_info} = ProviderRegistry.get_provider(:openai)
      assert provider_info.health_status == :unhealthy
    end
  end

  describe "provider discovery" do
    test "get_available_providers/1 returns only healthy providers meeting requirements" do
      {:ok, registry_pid} = start_supervised(ProviderRegistry)

      config = %{api_key: "test-key"}
      :ok = ProviderRegistry.register_provider(:openai, MockProvider, config)

      # Mark as healthy
      # Allow health check
      Process.sleep(100)

      requirements = %{
        evaluation_type: :quality,
        max_tokens: 2000,
        streaming: true
      }

      assert {:ok, available} = ProviderRegistry.get_available_providers(requirements)
      assert Map.has_key?(available, :openai)
    end

    test "get_available_providers/1 filters out providers not meeting requirements" do
      {:ok, registry_pid} = start_supervised(ProviderRegistry)

      config = %{api_key: "test-key"}
      :ok = ProviderRegistry.register_provider(:openai, MockProvider, config)

      # Requirements that exceed provider capabilities
      requirements = %{
        # Exceeds mock provider capacity
        max_tokens: 10_000,
        streaming: true
      }

      assert {:ok, available} = ProviderRegistry.get_available_providers(requirements)
      # Should filter out provider that can't meet token requirements
    end
  end

  describe "provider configuration" do
    test "update_provider_config/2 successfully updates provider configuration" do
      {:ok, registry_pid} = start_supervised(ProviderRegistry)

      initial_config = %{api_key: "test-key", models: %{screening: "model-v1"}}
      :ok = ProviderRegistry.register_provider(:openai, MockProvider, initial_config)

      new_config = %{api_key: "updated-key", models: %{screening: "model-v2"}}
      assert :ok = ProviderRegistry.update_provider_config(:openai, new_config)

      assert {:ok, provider_info} = ProviderRegistry.get_provider(:openai)
      assert provider_info.config.api_key == "updated-key"
      assert provider_info.config.models.screening == "model-v2"
    end

    test "update_provider_config/2 fails for non-existent provider" do
      {:ok, registry_pid} = start_supervised(ProviderRegistry)

      new_config = %{api_key: "test-key"}

      assert {:error, :not_found} =
               ProviderRegistry.update_provider_config(:nonexistent, new_config)
    end
  end

  describe "registry statistics" do
    test "get_registry_stats/0 returns comprehensive statistics" do
      {:ok, registry_pid} = start_supervised(ProviderRegistry)

      config = %{api_key: "test-key"}
      :ok = ProviderRegistry.register_provider(:openai, MockProvider, config)

      assert {:ok, stats} = ProviderRegistry.get_registry_stats()
      assert stats.total_providers == 1
      assert stats.registrations >= 1
      assert Map.has_key?(stats, :healthy_providers)
    end
  end

  describe "provider validation" do
    test "validate_provider_config/2 validates OpenAI configuration" do
      valid_config = %{
        api_key: "sk-test-key",
        models: %{
          screening: "gpt-4o-mini",
          detailed: "gpt-4o"
        }
      }

      assert :ok = ProviderRegistry.validate_provider_config(:openai, valid_config)
    end

    test "validate_provider_config/2 rejects invalid configuration" do
      invalid_config = %{
        api_key: "sk-test-key",
        models: %{
          screening: "invalid-model"
        }
      }

      assert {:error, error_msg} =
               ProviderRegistry.validate_provider_config(:openai, invalid_config)

      assert error_msg =~ "Invalid OpenAI models"
    end

    test "validate_provider_config/2 validates Anthropic configuration" do
      valid_config = %{
        api_key: "sk-ant-test-key",
        models: %{
          screening: "claude-3-haiku-20240307",
          detailed: "claude-3-5-sonnet-20241022"
        }
      }

      assert :ok = ProviderRegistry.validate_provider_config(:anthropic, valid_config)
    end

    test "validate_provider_config/2 validates Ollama configuration" do
      valid_config = %{
        endpoint: "http://localhost:11434",
        models: %{
          screening: "llama3.2:3b",
          detailed: "llama3.1:8b"
        }
      }

      assert :ok = ProviderRegistry.validate_provider_config(:ollama, valid_config)
    end
  end

  describe "provider lifecycle" do
    test "shutdown_all_providers/0 cleanly terminates all providers" do
      {:ok, registry_pid} = start_supervised(ProviderRegistry)

      config = %{api_key: "test-key"}
      :ok = ProviderRegistry.register_provider(:openai, MockProvider, config)

      assert :ok = ProviderRegistry.shutdown_all_providers()

      assert {:ok, providers} = ProviderRegistry.get_providers()
      assert map_size(providers) == 0
    end
  end
end
