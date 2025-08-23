defmodule RubberDuck.Preferences.Validators.LlmPreferenceValidator do
  @moduledoc """
  LLM-specific preference validation rules.

  Implements validation logic specific to LLM provider preferences,
  including provider availability, model compatibility, configuration
  consistency, and performance constraints.
  """

  alias RubberDuck.Preferences.Llm.ModelSelector

  @supported_providers ["openai", "anthropic", "google", "local", "ollama"]
  @openai_models ["gpt-4", "gpt-4-turbo", "gpt-4o", "gpt-4o-mini", "gpt-3.5-turbo"]
  @anthropic_models [
    "claude-3-5-sonnet-20241022",
    "claude-3-5-haiku-20241022",
    "claude-3-opus-20240229",
    "claude-3-sonnet-20240229",
    "claude-3-haiku-20240307"
  ]
  @google_models ["gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.0-pro"]

  @doc """
  Validate LLM provider selection preference.
  """
  @spec validate_provider_selection(value :: any()) :: :ok | {:error, String.t()}
  def validate_provider_selection(value) when is_list(value) do
    case Enum.all?(value, &(&1 in @supported_providers)) do
      true ->
        :ok

      false ->
        invalid = Enum.filter(value, &(&1 not in @supported_providers))

        {:error,
         "Invalid providers: #{inspect(invalid)}. Supported: #{inspect(@supported_providers)}"}
    end
  end

  def validate_provider_selection(value) when is_binary(value) do
    if value in @supported_providers do
      :ok
    else
      {:error, "Invalid provider: #{value}. Supported: #{inspect(@supported_providers)}"}
    end
  end

  def validate_provider_selection(_value) do
    {:error, "Provider selection must be a string or list of strings"}
  end

  @doc """
  Validate model selection for a specific provider.
  """
  @spec validate_model_selection(provider :: String.t(), model :: String.t()) ::
          :ok | {:error, String.t()}
  def validate_model_selection("openai", model) do
    if model in @openai_models do
      :ok
    else
      {:error, "Invalid OpenAI model: #{model}. Supported: #{inspect(@openai_models)}"}
    end
  end

  def validate_model_selection("anthropic", model) do
    if model in @anthropic_models do
      :ok
    else
      {:error, "Invalid Anthropic model: #{model}. Supported: #{inspect(@anthropic_models)}"}
    end
  end

  def validate_model_selection("google", model) do
    if model in @google_models do
      :ok
    else
      {:error, "Invalid Google model: #{model}. Supported: #{inspect(@google_models)}"}
    end
  end

  def validate_model_selection("local", _model) do
    # Local models can have custom names
    :ok
  end

  def validate_model_selection(provider, _model) do
    {:error, "Unknown provider: #{provider}"}
  end

  @doc """
  Validate temperature setting for a provider.
  """
  @spec validate_temperature(provider :: String.t(), temperature :: float()) ::
          :ok | {:error, String.t()}
  def validate_temperature("openai", temp) when temp >= 0.0 and temp <= 2.0, do: :ok
  def validate_temperature("anthropic", temp) when temp >= 0.0 and temp <= 1.0, do: :ok
  def validate_temperature("google", temp) when temp >= 0.0 and temp <= 2.0, do: :ok
  def validate_temperature("local", temp) when temp >= 0.0 and temp <= 2.0, do: :ok

  def validate_temperature(provider, _temp) do
    max_temp =
      case provider do
        p when p in ["openai", "google", "local"] -> 2.0
        "anthropic" -> 1.0
        _ -> 1.0
      end

    {:error, "Temperature must be between 0.0 and #{max_temp} for #{provider}"}
  end

  @doc """
  Validate token limits for a provider/model combination.
  """
  @spec validate_token_limit(provider :: String.t(), model :: String.t(), limit :: integer()) ::
          :ok | {:error, String.t()}
  def validate_token_limit(provider, model, limit) when is_integer(limit) and limit > 0 do
    provider_atom = String.to_existing_atom(provider)
    capabilities = ModelSelector.get_model_capabilities(provider_atom, model)
    max_tokens = capabilities.max_output_tokens

    if limit <= max_tokens do
      :ok
    else
      {:error,
       "Token limit #{limit} exceeds model maximum of #{max_tokens} for #{provider}/#{model}"}
    end
  end

  def validate_token_limit(_provider, _model, limit) do
    {:error, "Token limit must be a positive integer, got: #{inspect(limit)}"}
  end

  @doc """
  Validate fallback chain configuration.
  """
  @spec validate_fallback_chain(chain :: [String.t()]) :: :ok | {:error, String.t()}
  def validate_fallback_chain(chain) when is_list(chain) do
    case validate_providers_in_chain(chain) do
      :ok -> validate_chain_order(chain)
      error -> error
    end
  end

  def validate_fallback_chain(_chain) do
    {:error, "Fallback chain must be a list of provider names"}
  end

  @doc """
  Validate cost optimization configuration.
  """
  @spec validate_cost_config(config :: map()) :: :ok | {:error, String.t()}
  def validate_cost_config(config) when is_map(config) do
    with :ok <- validate_quality_threshold(Map.get(config, "quality_threshold")),
         :ok <- validate_cost_threshold(Map.get(config, "cost_per_token_threshold")),
         :ok <- validate_token_limits(Map.get(config, "token_usage_limits")) do
      :ok
    else
      error -> error
    end
  end

  def validate_cost_config(_config) do
    {:error, "Cost configuration must be a map"}
  end

  @doc """
  Validate monitoring configuration.
  """
  @spec validate_monitoring_config(config :: map()) :: :ok | {:error, String.t()}
  def validate_monitoring_config(config) when is_map(config) do
    with :ok <- validate_health_check_interval(Map.get(config, "health_check_interval")),
         :ok <- validate_alert_thresholds(Map.get(config, "alert_thresholds")) do
      :ok
    else
      error -> error
    end
  end

  def validate_monitoring_config(_config) do
    {:error, "Monitoring configuration must be a map"}
  end

  # Private validation functions

  defp validate_providers_in_chain(chain) do
    case Enum.all?(chain, &(&1 in @supported_providers)) do
      true ->
        :ok

      false ->
        invalid = Enum.filter(chain, &(&1 not in @supported_providers))
        {:error, "Invalid providers in fallback chain: #{inspect(invalid)}"}
    end
  end

  defp validate_chain_order(chain) do
    # Check for circular references
    if length(chain) == length(Enum.uniq(chain)) do
      :ok
    else
      {:error, "Fallback chain contains duplicate providers"}
    end
  end

  defp validate_quality_threshold(threshold)
       when is_number(threshold) and threshold >= 0.0 and threshold <= 1.0 do
    :ok
  end

  defp validate_quality_threshold(threshold) do
    {:error, "Quality threshold must be a number between 0.0 and 1.0, got: #{inspect(threshold)}"}
  end

  defp validate_cost_threshold(threshold) when is_number(threshold) and threshold > 0.0 do
    :ok
  end

  defp validate_cost_threshold(threshold) do
    {:error, "Cost threshold must be a positive number, got: #{inspect(threshold)}"}
  end

  defp validate_token_limits(limits) when is_map(limits) do
    required_keys = ["daily_limit", "weekly_limit", "monthly_limit"]

    case Enum.all?(required_keys, &Map.has_key?(limits, &1)) do
      true ->
        case Enum.all?(Map.values(limits), &(is_integer(&1) and &1 > 0)) do
          true -> :ok
          false -> {:error, "All token limits must be positive integers"}
        end

      false ->
        missing = Enum.filter(required_keys, &(not Map.has_key?(limits, &1)))
        {:error, "Missing required token limit keys: #{inspect(missing)}"}
    end
  end

  defp validate_token_limits(_limits) do
    {:error, "Token limits must be a map with daily_limit, weekly_limit, monthly_limit"}
  end

  defp validate_health_check_interval(interval)
       when is_integer(interval) and interval >= 10000 and interval <= 3_600_000 do
    :ok
  end

  defp validate_health_check_interval(interval) do
    {:error,
     "Health check interval must be between 10000 and 3600000 milliseconds, got: #{inspect(interval)}"}
  end

  defp validate_alert_thresholds(thresholds) when is_map(thresholds) do
    # Validate individual threshold values
    validations = [
      validate_threshold_value(Map.get(thresholds, "error_rate"), 0.0, 1.0, "error_rate"),
      validate_threshold_value(
        Map.get(thresholds, "response_time_ms"),
        100,
        60000,
        "response_time_ms"
      ),
      validate_threshold_value(Map.get(thresholds, "availability"), 0.0, 1.0, "availability")
    ]

    case Enum.find(validations, &match?({:error, _}, &1)) do
      nil -> :ok
      error -> error
    end
  end

  defp validate_alert_thresholds(_thresholds) do
    {:error, "Alert thresholds must be a map"}
  end

  # Optional thresholds
  defp validate_threshold_value(nil, _min, _max, _name), do: :ok

  defp validate_threshold_value(value, min, max, name) when is_number(value) do
    if value >= min and value <= max do
      :ok
    else
      {:error, "#{name} threshold must be between #{min} and #{max}, got: #{value}"}
    end
  end

  defp validate_threshold_value(value, _min, _max, name) do
    {:error, "#{name} threshold must be a number, got: #{inspect(value)}"}
  end
end
