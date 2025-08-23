defmodule RubberDuck.Preferences.Llm.ProviderConfig do
  @moduledoc """
  LLM provider configuration management using the preference hierarchy system.

  Provides functions to retrieve and manage LLM provider configurations
  based on user and project preferences with fallback to system defaults.
  """

  require Logger

  alias RubberDuck.Preferences.PreferenceResolver

  @supported_providers [:openai, :anthropic, :google, :local, :ollama]

  @doc """
  Get the enabled LLM providers for a user/project.
  """
  @spec get_enabled_providers(user_id :: binary(), project_id :: binary() | nil) :: [atom()]
  def get_enabled_providers(user_id, project_id \\ nil) do
    case PreferenceResolver.resolve(user_id, "llm.providers.enabled", project_id) do
      {:ok, providers} when is_list(providers) ->
        providers
        |> Enum.map(&String.to_existing_atom/1)
        |> Enum.filter(&(&1 in @supported_providers))

      # Safe default
      {:ok, _} ->
        [:anthropic, :openai]

      # Safe default
      {:error, _} ->
        [:anthropic, :openai]
    end
  end

  @doc """
  Get the provider priority order for a user/project.
  """
  @spec get_provider_priority(user_id :: binary(), project_id :: binary() | nil) :: [atom()]
  def get_provider_priority(user_id, project_id \\ nil) do
    case PreferenceResolver.resolve(user_id, "llm.providers.priority_order", project_id) do
      {:ok, priorities} when is_list(priorities) ->
        priorities
        |> Enum.map(&String.to_existing_atom/1)
        |> Enum.filter(&(&1 in @supported_providers))

      # Safe default
      {:ok, _} ->
        [:anthropic, :openai, :google]

      # Safe default
      {:error, _} ->
        [:anthropic, :openai, :google]
    end
  end

  @doc """
  Get the default provider for a user/project.
  """
  @spec get_default_provider(user_id :: binary(), project_id :: binary() | nil) :: atom()
  def get_default_provider(user_id, project_id \\ nil) do
    case PreferenceResolver.resolve(user_id, "llm.providers.default_provider", project_id) do
      {:ok, provider} when is_binary(provider) ->
        provider_atom = String.to_existing_atom(provider)
        if provider_atom in @supported_providers, do: provider_atom, else: :anthropic

      # Safe default
      {:ok, _} ->
        :anthropic

      # Safe default
      {:error, _} ->
        :anthropic
    end
  end

  @doc """
  Get provider-specific configuration for a provider.
  """
  @spec get_provider_config(user_id :: binary(), provider :: atom(), project_id :: binary() | nil) ::
          map()
  def get_provider_config(user_id, provider, project_id \\ nil) do
    case provider do
      :openai -> get_openai_config(user_id, project_id)
      :anthropic -> get_anthropic_config(user_id, project_id)
      :google -> get_google_config(user_id, project_id)
      :local -> get_local_config(user_id, project_id)
      _ -> %{}
    end
  end

  @doc """
  Get complete LLM configuration for a user/project.
  """
  @spec get_complete_config(user_id :: binary(), project_id :: binary() | nil) :: map()
  def get_complete_config(user_id, project_id \\ nil) do
    enabled_providers = get_enabled_providers(user_id, project_id)

    provider_configs =
      enabled_providers
      |> Enum.map(fn provider ->
        {provider, get_provider_config(user_id, provider, project_id)}
      end)
      |> Enum.into(%{})

    %{
      enabled_providers: enabled_providers,
      provider_priority: get_provider_priority(user_id, project_id),
      default_provider: get_default_provider(user_id, project_id),
      fallback_enabled: get_fallback_enabled(user_id, project_id),
      provider_configs: provider_configs,
      cost_optimization: get_cost_optimization_config(user_id, project_id),
      fallback_config: get_fallback_config(user_id, project_id),
      monitoring_config: get_monitoring_config(user_id, project_id)
    }
  end

  @doc """
  Validate provider configuration for consistency.
  """
  @spec validate_config(config :: map()) :: {:ok, :valid} | {:error, String.t()}
  def validate_config(config) do
    with {:ok, :providers_valid} <- validate_providers(config),
         {:ok, :priority_valid} <- validate_priority(config),
         {:ok, :fallback_valid} <- validate_fallback(config) do
      {:ok, :valid}
    else
      error -> error
    end
  end

  # Private configuration retrieval functions

  defp get_openai_config(user_id, project_id) do
    %{
      model: resolve_preference(user_id, "llm.openai.model", project_id, "gpt-4"),
      temperature: resolve_preference(user_id, "llm.openai.temperature", project_id, 0.7),
      max_tokens: resolve_preference(user_id, "llm.openai.max_tokens", project_id, 4096),
      timeout: resolve_preference(user_id, "llm.openai.timeout", project_id, 30000),
      retry_attempts: resolve_preference(user_id, "llm.openai.retry_attempts", project_id, 3)
    }
  end

  defp get_anthropic_config(user_id, project_id) do
    %{
      model:
        resolve_preference(
          user_id,
          "llm.anthropic.model",
          project_id,
          "claude-3-5-sonnet-20241022"
        ),
      temperature: resolve_preference(user_id, "llm.anthropic.temperature", project_id, 0.7),
      max_tokens: resolve_preference(user_id, "llm.anthropic.max_tokens", project_id, 4096),
      timeout: resolve_preference(user_id, "llm.anthropic.timeout", project_id, 60000),
      stream_enabled:
        resolve_preference(user_id, "llm.anthropic.stream_enabled", project_id, true)
    }
  end

  defp get_google_config(user_id, project_id) do
    %{
      model: resolve_preference(user_id, "llm.google.model", project_id, "gemini-1.5-pro"),
      temperature: resolve_preference(user_id, "llm.google.temperature", project_id, 0.7),
      max_tokens: resolve_preference(user_id, "llm.google.max_tokens", project_id, 8192),
      safety_settings:
        resolve_preference(user_id, "llm.google.safety_settings", project_id, "moderate")
    }
  end

  defp get_local_config(user_id, project_id) do
    %{
      enabled: resolve_preference(user_id, "llm.local.enabled", project_id, false),
      model_path: resolve_preference(user_id, "llm.local.model_path", project_id, ""),
      gpu_enabled: resolve_preference(user_id, "llm.local.gpu_enabled", project_id, true),
      context_window: resolve_preference(user_id, "llm.local.context_window", project_id, 4096)
    }
  end

  defp get_fallback_enabled(user_id, project_id) do
    resolve_preference(user_id, "llm.providers.fallback_enabled", project_id, true)
  end

  defp get_cost_optimization_config(user_id, project_id) do
    %{
      optimization_enabled:
        resolve_preference(user_id, "llm.cost.optimization_enabled", project_id, true),
      quality_threshold:
        resolve_preference(user_id, "llm.cost.quality_threshold", project_id, 0.8),
      budget_aware_selection:
        resolve_preference(user_id, "llm.cost.budget_aware_selection", project_id, true),
      token_usage_limits:
        resolve_preference(user_id, "llm.cost.token_usage_limits", project_id, %{}),
      cost_per_token_threshold:
        resolve_preference(user_id, "llm.cost.cost_per_token_threshold", project_id, 0.00001)
    }
  end

  defp get_fallback_config(user_id, project_id) do
    %{
      chain:
        resolve_preference(user_id, "llm.fallback.chain", project_id, ["anthropic", "openai"]),
      trigger_conditions:
        resolve_preference(user_id, "llm.fallback.trigger_conditions", project_id, %{}),
      retry_policy: resolve_preference(user_id, "llm.fallback.retry_policy", project_id, %{}),
      graceful_degradation:
        resolve_preference(user_id, "llm.fallback.graceful_degradation", project_id, true),
      circuit_breaker_enabled:
        resolve_preference(user_id, "llm.fallback.circuit_breaker_enabled", project_id, true)
    }
  end

  defp get_monitoring_config(user_id, project_id) do
    %{
      health_check_enabled:
        resolve_preference(user_id, "llm.monitoring.health_check_enabled", project_id, true),
      health_check_interval:
        resolve_preference(user_id, "llm.monitoring.health_check_interval", project_id, 300_000),
      performance_tracking:
        resolve_preference(user_id, "llm.monitoring.performance_tracking", project_id, true),
      analytics_enabled:
        resolve_preference(user_id, "llm.monitoring.analytics_enabled", project_id, true),
      alert_thresholds:
        resolve_preference(user_id, "llm.monitoring.alert_thresholds", project_id, %{})
    }
  end

  # Validation functions

  defp validate_providers(config) do
    enabled = Map.get(config, :enabled_providers, [])

    if Enum.all?(enabled, &(&1 in @supported_providers)) do
      {:ok, :providers_valid}
    else
      invalid = Enum.filter(enabled, &(&1 not in @supported_providers))
      {:error, "Invalid providers: #{inspect(invalid)}"}
    end
  end

  defp validate_priority(config) do
    priority = Map.get(config, :provider_priority, [])
    enabled = Map.get(config, :enabled_providers, [])

    # All providers in priority list should be enabled
    if Enum.all?(priority, &(&1 in enabled)) do
      {:ok, :priority_valid}
    else
      invalid = Enum.filter(priority, &(&1 not in enabled))
      {:error, "Priority list contains disabled providers: #{inspect(invalid)}"}
    end
  end

  defp validate_fallback(config) do
    fallback_config = Map.get(config, :fallback_config, %{})
    chain = Map.get(fallback_config, :chain, [])
    enabled = Map.get(config, :enabled_providers, [])

    # All providers in fallback chain should be enabled
    if Enum.all?(chain, &(String.to_existing_atom(&1) in enabled)) do
      {:ok, :fallback_valid}
    else
      invalid = Enum.filter(chain, &(String.to_existing_atom(&1) not in enabled))
      {:error, "Fallback chain contains disabled providers: #{inspect(invalid)}"}
    end
  end

  # Helper function for preference resolution with fallback
  defp resolve_preference(user_id, preference_key, project_id, default_value) do
    case PreferenceResolver.resolve(user_id, preference_key, project_id) do
      {:ok, value} -> value
      {:error, _} -> default_value
    end
  end
end
