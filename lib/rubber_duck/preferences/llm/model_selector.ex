defmodule RubberDuck.Preferences.Llm.ModelSelector do
  @moduledoc """
  Intelligent model selection based on user preferences and request characteristics.

  Selects the optimal model for a given request considering user preferences,
  cost constraints, capability requirements, and performance characteristics.
  """

  require Logger

  alias RubberDuck.Preferences.Llm.ProviderConfig

  @doc """
  Select the best model for a request based on preferences and requirements.
  """
  @spec select_model(user_id :: binary(), request_opts :: keyword(), project_id :: binary() | nil) ::
          {:ok, %{provider: atom(), model: String.t(), config: map()}} | {:error, String.t()}
  def select_model(user_id, request_opts \\ [], project_id \\ nil) do
    requirements = extract_requirements(request_opts)
    config = ProviderConfig.get_complete_config(user_id, project_id)

    case find_best_provider_model(config, requirements) do
      {:ok, provider, model} ->
        provider_config = Map.get(config.provider_configs, provider, %{})

        {:ok,
         %{
           provider: provider,
           model: model,
           config: provider_config
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get model capabilities for a specific provider and model.
  """
  @spec get_model_capabilities(provider :: atom(), model :: String.t()) :: map()
  def get_model_capabilities(provider, model) do
    case {provider, model} do
      {:openai, "gpt-4"} ->
        %{
          context_window: 8192,
          max_output_tokens: 4096,
          supports_functions: true,
          supports_vision: false,
          cost_per_input_token: 0.00003,
          cost_per_output_token: 0.00006
        }

      {:openai, "gpt-4-turbo"} ->
        %{
          context_window: 128_000,
          max_output_tokens: 4096,
          supports_functions: true,
          supports_vision: true,
          cost_per_input_token: 0.00001,
          cost_per_output_token: 0.00003
        }

      {:openai, "gpt-4o"} ->
        %{
          context_window: 128_000,
          max_output_tokens: 4096,
          supports_functions: true,
          supports_vision: true,
          cost_per_input_token: 0.000005,
          cost_per_output_token: 0.000015
        }

      {:anthropic, "claude-3-5-sonnet-20241022"} ->
        %{
          context_window: 200_000,
          max_output_tokens: 8192,
          supports_functions: true,
          supports_vision: true,
          cost_per_input_token: 0.000003,
          cost_per_output_token: 0.000015
        }

      {:anthropic, "claude-3-5-haiku-20241022"} ->
        %{
          context_window: 200_000,
          max_output_tokens: 8192,
          supports_functions: true,
          supports_vision: false,
          cost_per_input_token: 0.00000025,
          cost_per_output_token: 0.00000125
        }

      {:google, "gemini-1.5-pro"} ->
        %{
          context_window: 1_000_000,
          max_output_tokens: 8192,
          supports_functions: true,
          supports_vision: true,
          cost_per_input_token: 0.00000125,
          cost_per_output_token: 0.000005
        }

      _ ->
        %{
          context_window: 4096,
          max_output_tokens: 2048,
          supports_functions: false,
          supports_vision: false,
          cost_per_input_token: 0.00001,
          cost_per_output_token: 0.00002
        }
    end
  end

  @doc """
  Check if a model meets the specified requirements.
  """
  @spec meets_requirements?(provider :: atom(), model :: String.t(), requirements :: map()) ::
          boolean()
  def meets_requirements?(provider, model, requirements) do
    capabilities = get_model_capabilities(provider, model)

    Enum.all?(requirements, fn {requirement, value} ->
      case requirement do
        :min_context_window -> capabilities.context_window >= value
        :max_cost_per_token -> capabilities.cost_per_input_token <= value
        :requires_functions -> not value or capabilities.supports_functions
        :requires_vision -> not value or capabilities.supports_vision
        :min_output_tokens -> capabilities.max_output_tokens >= value
        # Unknown requirements are ignored
        _ -> true
      end
    end)
  end

  @doc """
  Estimate cost for a request with specific provider/model.
  """
  @spec estimate_cost(
          provider :: atom(),
          model :: String.t(),
          input_tokens :: integer(),
          estimated_output_tokens :: integer()
        ) :: float()
  def estimate_cost(provider, model, input_tokens, estimated_output_tokens) do
    capabilities = get_model_capabilities(provider, model)

    input_cost = input_tokens * capabilities.cost_per_input_token
    output_cost = estimated_output_tokens * capabilities.cost_per_output_token

    input_cost + output_cost
  end

  # Private functions

  defp extract_requirements(request_opts) do
    %{
      min_context_window: Keyword.get(request_opts, :min_context_window, 4096),
      max_cost_per_token: Keyword.get(request_opts, :max_cost_per_token, 0.0001),
      requires_functions: Keyword.get(request_opts, :requires_functions, false),
      requires_vision: Keyword.get(request_opts, :requires_vision, false),
      min_output_tokens: Keyword.get(request_opts, :min_output_tokens, 1024),
      quality_preference: Keyword.get(request_opts, :quality_preference, :balanced)
    }
  end

  defp find_best_provider_model(config, requirements) do
    enabled_providers = config.enabled_providers
    priority_order = config.provider_priority

    # Sort providers by priority
    sorted_providers =
      priority_order
      |> Enum.filter(&(&1 in enabled_providers))
      |> Enum.concat(Enum.filter(enabled_providers, &(&1 not in priority_order)))

    # Find first provider/model combination that meets requirements
    case find_suitable_model(sorted_providers, config, requirements) do
      {:ok, provider, model} -> {:ok, provider, model}
      {:error, _} -> {:error, "No suitable model found for requirements"}
    end
  end

  defp find_suitable_model([], _config, _requirements), do: {:error, "No providers available"}

  defp find_suitable_model([provider | rest], config, requirements) do
    provider_config = Map.get(config.provider_configs, provider, %{})
    default_model = Map.get(provider_config, :model, __MODULE__.get_default_model(provider))

    if meets_requirements?(provider, default_model, requirements) do
      {:ok, provider, default_model}
    else
      # Try other models for this provider if available
      case try_alternative_models(provider, requirements) do
        {:ok, model} -> {:ok, provider, model}
        {:error, _} -> find_suitable_model(rest, config, requirements)
      end
    end
  end

  defp try_alternative_models(provider, requirements) do
    alternative_models = __MODULE__.get_alternative_models(provider)

    case Enum.find(alternative_models, &meets_requirements?(provider, &1, requirements)) do
      nil -> {:error, "No suitable model for provider"}
      model -> {:ok, model}
    end
  end

  @doc """
  Get alternative models for a provider (public function for external use).
  """
  @spec get_alternative_models(provider :: atom()) :: [String.t()]
  def get_alternative_models(provider) do
    case provider do
      :openai ->
        ["gpt-4o", "gpt-4-turbo", "gpt-4", "gpt-3.5-turbo"]

      :anthropic ->
        [
          "claude-3-5-sonnet-20241022",
          "claude-3-5-haiku-20241022",
          "claude-3-opus-20240229",
          "claude-3-sonnet-20240229"
        ]

      :google ->
        ["gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.0-pro"]

      _ ->
        []
    end
  end

  @doc """
  Get default model for a provider (public function for external use).
  """
  @spec get_default_model(provider :: atom()) :: String.t()
  def get_default_model(provider) do
    case provider do
      :openai -> "gpt-4"
      :anthropic -> "claude-3-5-sonnet-20241022"
      :google -> "gemini-1.5-pro"
      _ -> "unknown"
    end
  end
end
