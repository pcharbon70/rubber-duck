defmodule RubberDuck.LLM.Config do
  @moduledoc """
  Configuration management for LLM providers.

  Handles loading, validation, and access to provider configurations
  from application environment and runtime configuration.
  """

  @default_timeout 30_000
  @default_max_tokens 2048
  @default_temperature 0.7

  @doc """
  Load configuration for all providers from application environment.
  """
  def load_providers do
    :rubber_duck
    |> Application.get_env(:llm_providers, [])
    |> Enum.map(&normalize_provider_config/1)
    |> Enum.filter(&valid_provider_config?/1)
  end

  @doc """
  Load configuration for a specific provider.
  """
  def load_provider(provider_name) when is_atom(provider_name) do
    providers = load_providers()

    Enum.find(providers, fn config ->
      config.name == provider_name
    end)
  end

  @doc """
  Get the default provider configuration.
  """
  def default_provider do
    Application.get_env(:rubber_duck, :default_llm_provider, :openai)
  end

  @doc """
  Get rate limit configuration for a provider.
  """
  def rate_limits(provider_name) when is_atom(provider_name) do
    :rubber_duck
    |> Application.get_env(:llm_rate_limits, %{})
    |> Map.get(provider_name, default_rate_limits())
  end

  @doc """
  Get circuit breaker configuration for a provider.
  """
  def circuit_breaker_config(provider_name) when is_atom(provider_name) do
    %{
      fuse_name: :"llm_#{provider_name}_fuse",
      fuse_strategy: {:standard, 5, 60_000},
      fuse_refresh: 60_000,
      fuse_opts: [
        log_level: :info,
        telemetry_enabled: true
      ]
    }
  end

  @doc """
  Validate that a provider configuration has all required fields.
  """
  def validate_config(config) when is_map(config) do
    required_fields = [:name, :module, :api_key]

    missing_fields =
      required_fields
      |> Enum.reject(fn field -> Map.has_key?(config, field) end)

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, {:missing_fields, missing_fields}}
    end
  end

  # Private functions

  defp normalize_provider_config({name, config}) when is_atom(name) and is_map(config) do
    config
    |> Map.put(:name, name)
    |> Map.put_new(:timeout, @default_timeout)
    |> Map.put_new(:max_tokens, @default_max_tokens)
    |> Map.put_new(:temperature, @default_temperature)
    |> Map.update(:api_key, nil, &load_api_key/1)
    |> Map.put_new(:enabled, true)
  end

  defp normalize_provider_config(config) when is_map(config) do
    config
    |> Map.put_new(:timeout, @default_timeout)
    |> Map.put_new(:max_tokens, @default_max_tokens)
    |> Map.put_new(:temperature, @default_temperature)
    |> Map.update(:api_key, nil, &load_api_key/1)
    |> Map.put_new(:enabled, true)
  end

  defp normalize_provider_config(_), do: nil

  defp valid_provider_config?(nil), do: false
  defp valid_provider_config?(config) do
    Map.get(config, :enabled, false) &&
      Map.has_key?(config, :name) &&
      Map.has_key?(config, :module) &&
      Map.has_key?(config, :api_key) &&
      config.api_key != nil
  end

  defp load_api_key({:system, env_var}) when is_binary(env_var) do
    System.get_env(env_var)
  end

  defp load_api_key({:system, env_var}) when is_atom(env_var) do
    System.get_env(Atom.to_string(env_var))
  end

  defp load_api_key(api_key) when is_binary(api_key) do
    api_key
  end

  defp load_api_key(_), do: nil

  defp default_rate_limits do
    %{
      max_requests: 100,
      window_ms: 60_000,
      bucket_name: :default_llm_rate_limit
    }
  end
end
