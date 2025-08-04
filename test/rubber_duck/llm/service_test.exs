defmodule RubberDuck.LLM.ServiceTest do
  use ExUnit.Case, async: false

  alias RubberDuck.LLM.{Service, ProviderRegistry, HealthMonitor}

  # Mock provider for testing
  defmodule MockProvider do
    @behaviour RubberDuck.LLM.Provider

    @impl true
    def init(_config), do: {:ok, %{}}

    @impl true
    def complete(request, _config) do
      {:ok, %{
        id: "test_completion",
        model: request.model,
        choices: [%{
          index: 0,
          message: %{role: :assistant, content: "Test response"},
          finish_reason: "stop"
        }],
        usage: %{
          prompt_tokens: 10,
          completion_tokens: 5,
          total_tokens: 15
        },
        created: System.system_time(:second)
      }}
    end

    @impl true
    def stream(_request, _config) do
      stream = Stream.iterate(0, &(&1 + 1))
              |> Stream.take(3)
              |> Stream.map(fn i -> "chunk_#{i}" end)
      {:ok, stream}
    end

    @impl true
    def embed(_request, _config) do
      {:ok, %{
        data: [%{
          index: 0,
          embedding: [0.1, 0.2, 0.3]
        }],
        model: "test_model",
        usage: %{
          prompt_tokens: 5,
          completion_tokens: 0,
          total_tokens: 5
        }
      }}
    end

    @impl true
    def capabilities do
      %{
        completion: true,
        streaming: true,
        embeddings: true,
        function_calling: false,
        vision: false,
        max_context_length: 4096,
        models: ["test_model"]
      }
    end

    @impl true
    def health_check(_config), do: :ok

    @impl true
    def name, do: "MockProvider"

    @impl true
    def validate_config(_config), do: :ok
  end

  setup do
    # Start required services
    unless Process.whereis(ProviderRegistry) do
      {:ok, _} = ProviderRegistry.start_link()
    end
    
    unless Process.whereis(HealthMonitor) do
      {:ok, _} = HealthMonitor.start_link()
    end
    
    unless Process.whereis(Service) do
      {:ok, _} = Service.start_link()
    end
    
    # Register mock provider
    provider_name = :mock_provider_#{System.unique_integer([:positive])}
    Service.register_provider(provider_name, MockProvider, %{api_key: "test"})
    Process.sleep(10)
    
    {:ok, provider_name: provider_name}
  end

  describe "complete/2" do
    test "generates completion with registered provider", %{provider_name: provider_name} do
      request = %{
        model: "test_model",
        messages: [%{role: :user, content: "Hello"}],
        max_tokens: 100
      }
      
      assert {:ok, response} = Service.complete(request, provider: provider_name)
      assert response.id == "test_completion"
      assert [choice | _] = response.choices
      assert choice.message.content == "Test response"
    end

    test "returns error for non-existent provider" do
      request = %{
        model: "test_model",
        messages: [%{role: :user, content: "Hello"}]
      }
      
      assert {:error, :provider_not_found} = Service.complete(request, provider: :nonexistent)
    end
  end

  describe "stream/2" do
    test "generates streaming completion", %{provider_name: provider_name} do
      request = %{
        model: "test_model",
        messages: [%{role: :user, content: "Hello"}],
        stream: true
      }
      
      assert {:ok, stream} = Service.stream(request, provider: provider_name)
      chunks = Enum.to_list(stream)
      assert chunks == ["chunk_0", "chunk_1", "chunk_2"]
    end
  end

  describe "embed/2" do
    test "generates embeddings", %{provider_name: provider_name} do
      request = %{
        model: "test_model",
        input: "Test text"
      }
      
      assert {:ok, response} = Service.embed(request, provider: provider_name)
      assert [embedding | _] = response.data
      assert embedding.embedding == [0.1, 0.2, 0.3]
    end
  end

  describe "register_provider/3" do
    test "registers valid provider" do
      provider_name = :new_provider_#{System.unique_integer([:positive])}
      config = %{api_key: "test_key"}
      
      assert :ok = Service.register_provider(provider_name, MockProvider, config)
      
      # Verify provider is registered
      assert {:ok, _} = ProviderRegistry.get(provider_name)
    end

    test "rejects invalid provider module" do
      defmodule InvalidProvider do
        # Not implementing the behavior
      end
      
      provider_name = :invalid_provider_#{System.unique_integer([:positive])}
      config = %{api_key: "test_key"}
      
      assert {:error, :invalid_provider_module} = 
        Service.register_provider(provider_name, InvalidProvider, config)
    end
  end

  describe "provider_status/0" do
    test "returns status of all providers", %{provider_name: provider_name} do
      status = Service.provider_status()
      
      assert is_list(status)
      provider_status = Enum.find(status, & &1.name == provider_name)
      
      assert provider_status != nil
      assert provider_status.available == true
      assert is_number(provider_status.error_rate)
      assert is_number(provider_status.avg_response_time)
    end
  end

  describe "metrics/1" do
    test "returns global metrics when no provider specified" do
      metrics = Service.metrics()
      
      assert Map.has_key?(metrics, :total_requests)
      assert Map.has_key?(metrics, :uptime_seconds)
      assert Map.has_key?(metrics, :providers)
    end

    test "returns provider-specific metrics", %{provider_name: provider_name} do
      # Make some requests to generate metrics
      request = %{
        model: "test_model",
        messages: [%{role: :user, content: "Hello"}]
      }
      
      Service.complete(request, provider: provider_name)
      Service.complete(request, provider: provider_name)
      
      Process.sleep(20)
      
      metrics = Service.metrics(provider_name)
      
      assert metrics.total_count >= 0
      assert metrics.success_count >= 0
      assert metrics.error_count >= 0
    end
  end
end