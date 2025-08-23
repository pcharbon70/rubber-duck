defmodule RubberDuck.Preferences.Validators.MlPreferenceValidator do
  @moduledoc """
  ML-specific preference validation rules.

  Implements validation logic specific to machine learning preferences,
  including framework compatibility, parameter ranges, data policy
  compliance, and performance constraints.
  """

  import Bitwise

  @supported_frameworks ["sklearn", "pytorch", "tensorflow", "xgboost"]
  @selection_criteria ["accuracy", "speed", "memory", "balanced"]
  @privacy_modes ["strict", "moderate", "permissive"]

  @doc """
  Validate ML framework selection preference.
  """
  @spec validate_framework_selection(value :: any()) :: :ok | {:error, String.t()}
  def validate_framework_selection(value) when is_binary(value) do
    if value in @supported_frameworks do
      :ok
    else
      {:error, "Invalid framework: #{value}. Supported: #{inspect(@supported_frameworks)}"}
    end
  end

  def validate_framework_selection(_value) do
    {:error, "Framework selection must be a string"}
  end

  @doc """
  Validate model selection criteria preference.
  """
  @spec validate_selection_criteria(value :: any()) :: :ok | {:error, String.t()}
  def validate_selection_criteria(value) when is_binary(value) do
    if value in @selection_criteria do
      :ok
    else
      {:error, "Invalid selection criteria: #{value}. Supported: #{inspect(@selection_criteria)}"}
    end
  end

  def validate_selection_criteria(_value) do
    {:error, "Selection criteria must be a string"}
  end

  @doc """
  Validate learning rate parameter.
  """
  @spec validate_learning_rate(value :: any()) :: :ok | {:error, String.t()}
  def validate_learning_rate(value) when is_float(value) or is_integer(value) do
    numeric_value = if is_integer(value), do: value / 1.0, else: value

    cond do
      numeric_value <= 0.0 ->
        {:error, "Learning rate must be positive"}

      numeric_value > 1.0 ->
        {:error, "Learning rate must be <= 1.0"}

      true ->
        :ok
    end
  end

  def validate_learning_rate(value) when is_binary(value) do
    case Float.parse(value) do
      {float_value, ""} -> validate_learning_rate(float_value)
      _ -> {:error, "Learning rate must be a valid number"}
    end
  end

  def validate_learning_rate(_value) do
    {:error, "Learning rate must be a number or numeric string"}
  end

  @doc """
  Validate batch size parameter.
  """
  @spec validate_batch_size(value :: any()) :: :ok | {:error, String.t()}
  def validate_batch_size(value) when is_integer(value) do
    cond do
      value <= 0 ->
        {:error, "Batch size must be positive"}

      value > 1024 ->
        {:error, "Batch size must be <= 1024"}

      # Ensure batch size is a power of 2 for optimal performance
      not power_of_two?(value) ->
        {:error, "Batch size should be a power of 2 for optimal performance"}

      true ->
        :ok
    end
  end

  def validate_batch_size(value) when is_binary(value) do
    case Integer.parse(value) do
      {int_value, ""} -> validate_batch_size(int_value)
      _ -> {:error, "Batch size must be a valid integer"}
    end
  end

  def validate_batch_size(_value) do
    {:error, "Batch size must be an integer or integer string"}
  end

  @doc """
  Validate memory limit parameter.
  """
  @spec validate_memory_limit(value :: any()) :: :ok | {:error, String.t()}
  def validate_memory_limit(value) when is_integer(value) do
    cond do
      value < 512 ->
        {:error, "Memory limit must be at least 512 MB"}

      value > 32_768 ->
        {:error, "Memory limit must be <= 32,768 MB (32 GB)"}

      true ->
        :ok
    end
  end

  def validate_memory_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {int_value, ""} -> validate_memory_limit(int_value)
      _ -> {:error, "Memory limit must be a valid integer"}
    end
  end

  def validate_memory_limit(_value) do
    {:error, "Memory limit must be an integer or integer string"}
  end

  @doc """
  Validate data retention period.
  """
  @spec validate_retention_days(value :: any()) :: :ok | {:error, String.t()}
  def validate_retention_days(value) when is_integer(value) do
    cond do
      value < 30 ->
        {:error, "Data retention must be at least 30 days for compliance"}

      value > 2555 ->
        {:error, "Data retention cannot exceed 7 years (2555 days)"}

      true ->
        :ok
    end
  end

  def validate_retention_days(value) when is_binary(value) do
    case Integer.parse(value) do
      {int_value, ""} -> validate_retention_days(int_value)
      _ -> {:error, "Retention days must be a valid integer"}
    end
  end

  def validate_retention_days(_value) do
    {:error, "Retention days must be an integer or integer string"}
  end

  @doc """
  Validate privacy mode setting.
  """
  @spec validate_privacy_mode(value :: any()) :: :ok | {:error, String.t()}
  def validate_privacy_mode(value) when is_binary(value) do
    if value in @privacy_modes do
      :ok
    else
      {:error, "Invalid privacy mode: #{value}. Supported: #{inspect(@privacy_modes)}"}
    end
  end

  def validate_privacy_mode(_value) do
    {:error, "Privacy mode must be a string"}
  end

  @doc """
  Validate A/B testing traffic split ratio.
  """
  @spec validate_traffic_split(value :: any()) :: :ok | {:error, String.t()}
  def validate_traffic_split(value) when is_float(value) or is_integer(value) do
    numeric_value = if is_integer(value), do: value / 1.0, else: value

    cond do
      numeric_value < 0.01 ->
        {:error, "Traffic split must be at least 0.01 (1%)"}

      numeric_value > 0.5 ->
        {:error, "Traffic split cannot exceed 0.5 (50%)"}

      true ->
        :ok
    end
  end

  def validate_traffic_split(value) when is_binary(value) do
    case Float.parse(value) do
      {float_value, ""} -> validate_traffic_split(float_value)
      _ -> {:error, "Traffic split must be a valid number"}
    end
  end

  def validate_traffic_split(_value) do
    {:error, "Traffic split must be a number or numeric string"}
  end

  @doc """
  Validate ML configuration consistency across related preferences.
  """
  @spec validate_ml_config_consistency(preferences :: map()) :: :ok | {:error, String.t()}
  def validate_ml_config_consistency(preferences) do
    with :ok <- validate_advanced_ml_prerequisites(preferences),
         :ok <- validate_experiment_prerequisites(preferences),
         :ok <- validate_resource_constraints(preferences),
         :ok <- validate_privacy_consistency(preferences) do
      :ok
    end
  end

  # Private helper functions

  defp validate_advanced_ml_prerequisites(preferences) do
    advanced_enabled = Map.get(preferences, "ml.features.advanced_enabled", "false")
    global_enabled = Map.get(preferences, "ml.global.enabled", "false")

    if advanced_enabled == "true" and global_enabled == "false" do
      {:error, "Advanced ML features require global ML to be enabled"}
    else
      :ok
    end
  end

  defp validate_experiment_prerequisites(preferences) do
    ab_testing = Map.get(preferences, "ml.experiments.ab_testing_enabled", "false")
    experiment_tracking = Map.get(preferences, "ml.features.experiment_tracking", "false")

    if ab_testing == "true" and experiment_tracking == "false" do
      {:error, "A/B testing requires experiment tracking to be enabled"}
    else
      :ok
    end
  end

  defp validate_resource_constraints(preferences) do
    memory_limit =
      preferences |> Map.get("ml.performance.memory_limit_mb", "2048") |> parse_integer()

    parallel_workers =
      preferences |> Map.get("ml.performance.parallel_workers", "4") |> parse_integer()

    if memory_limit && parallel_workers && memory_limit < parallel_workers * 256 do
      {:error, "Memory limit too low for number of parallel workers (need ~256MB per worker)"}
    else
      :ok
    end
  end

  defp validate_privacy_consistency(preferences) do
    privacy_mode = Map.get(preferences, "ml.data.privacy_mode", "strict")
    sharing_allowed = Map.get(preferences, "ml.data.sharing_allowed", "false")
    anonymization = Map.get(preferences, "ml.data.anonymization_enabled", "true")

    cond do
      privacy_mode == "strict" and sharing_allowed == "true" ->
        {:error, "Strict privacy mode does not allow data sharing"}

      privacy_mode == "strict" and anonymization == "false" ->
        {:error, "Strict privacy mode requires data anonymization"}

      true ->
        :ok
    end
  end

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int_value, ""} -> int_value
      _ -> nil
    end
  end

  defp parse_integer(value) when is_integer(value), do: value
  defp parse_integer(_), do: nil

  defp power_of_two?(n) when is_integer(n) and n > 0 do
    (n &&& n - 1) == 0
  end

  defp power_of_two?(_), do: false
end
