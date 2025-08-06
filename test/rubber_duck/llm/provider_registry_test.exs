defmodule RubberDuck.LLM.ProviderRegistryTest do
  use ExUnit.Case, async: false

  alias RubberDuck.LLM.ProviderRegistry

  setup do
    # Start the registry if not already started
    case Process.whereis(ProviderRegistry) do
      nil ->
        {:ok, pid} = ProviderRegistry.start_link()
        on_exit(fn -> Process.exit(pid, :normal) end)
      _ ->
        :ok
    end

    :ok
  end

  describe "register/3" do
    test "registers a provider successfully" do
      provider_name = :test_provider_#{System.unique_integer([:positive])}
      module = TestModule
      config = %{api_key: "test_key"}

      assert :ok = ProviderRegistry.register(provider_name, module, config)

      # Verify provider was registered
      assert {:ok, provider} = ProviderRegistry.get(provider_name)
      assert provider.name == provider_name
      assert provider.module == module
      assert provider.config == config
      assert provider.available == true
    end
  end

  describe "unregister/1" do
    test "unregisters a provider" do
      provider_name = :test_provider_#{System.unique_integer([:positive])}
      ProviderRegistry.register(provider_name, TestModule, %{})

      assert :ok = ProviderRegistry.unregister(provider_name)
      assert {:error, :provider_not_found} = ProviderRegistry.get(provider_name)
    end
  end

  describe "get/1" do
    test "returns provider data when provider exists" do
      provider_name = :test_provider_#{System.unique_integer([:positive])}
      module = TestModule
      config = %{api_key: "test_key"}

      ProviderRegistry.register(provider_name, module, config)

      assert {:ok, provider} = ProviderRegistry.get(provider_name)
      assert provider.name == provider_name
      assert provider.module == module
    end

    test "returns error when provider doesn't exist" do
      assert {:error, :provider_not_found} = ProviderRegistry.get(:nonexistent)
    end
  end

  describe "list/0" do
    test "returns all registered providers" do
      provider1 = :test_provider_#{System.unique_integer([:positive])}
      provider2 = :test_provider_#{System.unique_integer([:positive])}

      ProviderRegistry.register(provider1, TestModule, %{})
      ProviderRegistry.register(provider2, TestModule, %{})

      providers = ProviderRegistry.list()
      provider_names = Enum.map(providers, & &1.name)

      assert provider1 in provider_names
      assert provider2 in provider_names
    end
  end

  describe "list_available/0" do
    test "returns only available providers" do
      available_provider = :available_#{System.unique_integer([:positive])}
      unavailable_provider = :unavailable_#{System.unique_integer([:positive])}

      ProviderRegistry.register(available_provider, TestModule, %{})
      ProviderRegistry.register(unavailable_provider, TestModule, %{})

      # Mark one as unavailable
      ProviderRegistry.mark_unavailable(unavailable_provider)

      # Give it a moment to process
      Process.sleep(10)

      available = ProviderRegistry.list_available()
      available_names = Enum.map(available, & &1.name)

      assert available_provider in available_names
      refute unavailable_provider in available_names
    end
  end

  describe "update_health/2" do
    test "updates provider health status" do
      provider_name = :test_provider_#{System.unique_integer([:positive])}
      ProviderRegistry.register(provider_name, TestModule, %{})

      health_status = %{
        available: false,
        last_error: :connection_timeout
      }

      ProviderRegistry.update_health(provider_name, health_status)

      # Give it a moment to process the cast
      Process.sleep(10)

      {:ok, provider} = ProviderRegistry.get(provider_name)
      assert provider.available == false
      assert provider.last_error == :connection_timeout
    end
  end

  describe "mark_unavailable/1 and mark_available/1" do
    test "toggles provider availability" do
      provider_name = :test_provider_#{System.unique_integer([:positive])}
      ProviderRegistry.register(provider_name, TestModule, %{})

      # Initially available
      {:ok, provider} = ProviderRegistry.get(provider_name)
      assert provider.available == true

      # Mark unavailable
      ProviderRegistry.mark_unavailable(provider_name)
      Process.sleep(10)

      {:ok, provider} = ProviderRegistry.get(provider_name)
      assert provider.available == false

      # Mark available again
      ProviderRegistry.mark_available(provider_name)
      Process.sleep(10)

      {:ok, provider} = ProviderRegistry.get(provider_name)
      assert provider.available == true
    end
  end
end
