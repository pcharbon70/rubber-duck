defmodule RubberDuck.Preferences.Ml.TrainingController do
  @moduledoc """
  ML training controller for managing training parameters and processes.

  Controls ML training execution based on user preferences including
  learning parameters, convergence criteria, resource limits, and
  early stopping policies. Integrates with performance monitoring
  and feedback systems.
  """

  require Logger

  alias RubberDuck.Preferences.Ml.ConfigurationManager

  @doc """
  Get training configuration for a specific user and model.
  """
  @spec get_training_config(
          user_id :: binary(),
          model_info :: map(),
          project_id :: binary() | nil
        ) :: {:ok, map()} | {:error, String.t()}
  def get_training_config(user_id, model_info, project_id \\ nil) do
    with {:ok, ml_config} <- ConfigurationManager.get_ml_config(user_id, project_id),
         {:ok, optimized_config} <- optimize_training_params(ml_config, model_info) do
      {:ok, optimized_config}
    else
      error ->
        Logger.warning("Failed to get training config for user #{user_id}: #{inspect(error)}")
        {:error, "Unable to load training configuration"}
    end
  end

  @doc """
  Validate training parameters against constraints.
  """
  @spec validate_training_params(params :: map()) :: :ok | {:error, String.t()}
  def validate_training_params(params) do
    with :ok <- validate_learning_rate(params),
         :ok <- validate_iterations(params),
         :ok <- validate_convergence_threshold(params),
         :ok <- validate_regularization_params(params) do
      :ok
    end
  end

  @doc """
  Calculate estimated training time based on parameters and data size.
  """
  @spec estimate_training_time(config :: map(), data_size :: integer()) ::
          {:ok, integer()} | {:error, String.t()}
  def estimate_training_time(config, data_size) when is_integer(data_size) and data_size > 0 do
    base_time = calculate_base_training_time(config, data_size)
    parallelization_factor = config.performance.parallel_workers
    memory_factor = calculate_memory_factor(config.performance.memory_limit_mb, data_size)

    estimated_seconds = round(base_time / parallelization_factor * memory_factor)
    {:ok, estimated_seconds}
  end

  def estimate_training_time(_config, data_size) do
    {:error, "Invalid data size: #{data_size}"}
  end

  @doc """
  Check if training should use early stopping based on preferences.
  """
  @spec should_use_early_stopping?(user_id :: binary(), project_id :: binary() | nil) :: boolean()
  def should_use_early_stopping?(user_id, project_id \\ nil) do
    case ConfigurationManager.get_training_params(user_id, project_id) do
      {:ok, params} -> params.early_stopping_enabled
      {:error, _} -> true
    end
  end

  @doc """
  Get resource limits for training operations.
  """
  @spec get_resource_limits(user_id :: binary(), project_id :: binary() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def get_resource_limits(user_id, project_id \\ nil) do
    case ConfigurationManager.get_performance_settings(user_id, project_id) do
      {:ok, settings} ->
        {:ok,
         %{
           memory_limit_mb: settings.memory_limit_mb,
           cpu_limit_percent: settings.cpu_limit_percent,
           max_parallel_workers: settings.parallel_workers,
           max_training_time_hours: calculate_max_training_time(settings)
         }}

      error ->
        error
    end
  end

  @doc """
  Check if training operation is within resource limits.
  """
  @spec within_resource_limits?(
          user_id :: binary(),
          resource_usage :: map(),
          project_id :: binary() | nil
        ) :: boolean()
  def within_resource_limits?(user_id, resource_usage, project_id \\ nil) do
    case get_resource_limits(user_id, project_id) do
      {:ok, limits} ->
        check_memory_limit(resource_usage, limits) and
          check_cpu_limit(resource_usage, limits) and
          check_time_limit(resource_usage, limits)

      {:error, _} ->
        false
    end
  end

  @doc """
  Generate training recommendations based on data characteristics.
  """
  @spec get_training_recommendations(
          user_id :: binary(),
          data_characteristics :: map(),
          project_id :: binary() | nil
        ) :: {:ok, list(map())} | {:error, String.t()}
  def get_training_recommendations(user_id, data_characteristics, project_id \\ nil) do
    case ConfigurationManager.get_ml_config(user_id, project_id) do
      {:ok, config} ->
        recommendations = generate_training_recommendations(config, data_characteristics)
        {:ok, recommendations}

      error ->
        error
    end
  end

  # Private helper functions

  defp optimize_training_params(ml_config, model_info) do
    base_config = ml_config.training

    optimized_config = %{
      learning_rate: optimize_learning_rate(base_config.learning_rate, model_info),
      batch_size: optimize_batch_size(ml_config.performance.batch_size, model_info),
      max_iterations: base_config.max_iterations,
      convergence_threshold: base_config.convergence_threshold,
      early_stopping_enabled: base_config.early_stopping_enabled,
      regularization: %{
        l1: base_config.regularization_l1,
        l2: base_config.regularization_l2
      },
      resource_limits: %{
        memory_mb: ml_config.performance.memory_limit_mb,
        cpu_percent: ml_config.performance.cpu_limit_percent,
        parallel_workers: ml_config.performance.parallel_workers
      }
    }

    {:ok, optimized_config}
  end

  defp optimize_learning_rate(base_rate, model_info) do
    # Adjust learning rate based on model type
    case model_info[:framework] do
      "pytorch" -> base_rate * 0.1
      "tensorflow" -> base_rate * 0.1
      _ -> base_rate
    end
  end

  defp optimize_batch_size(base_size, model_info) do
    # Adjust batch size based on model complexity
    case model_info[:model] do
      model when model in ["transformer", "resnet", "cnn"] -> max(base_size * 2, 64)
      _ -> base_size
    end
  end

  defp validate_learning_rate(params) do
    case Map.get(params, :learning_rate) do
      nil -> {:error, "Learning rate is required"}
      rate when is_number(rate) and rate > 0 and rate <= 1.0 -> :ok
      _ -> {:error, "Learning rate must be between 0 and 1.0"}
    end
  end

  defp validate_iterations(params) do
    case Map.get(params, :max_iterations) do
      nil -> {:error, "Max iterations is required"}
      iterations when is_integer(iterations) and iterations > 0 and iterations <= 100_000 -> :ok
      _ -> {:error, "Max iterations must be between 1 and 100,000"}
    end
  end

  defp validate_convergence_threshold(params) do
    case Map.get(params, :convergence_threshold) do
      nil -> {:error, "Convergence threshold is required"}
      threshold when is_number(threshold) and threshold > 0 and threshold <= 0.1 -> :ok
      _ -> {:error, "Convergence threshold must be between 0 and 0.1"}
    end
  end

  defp validate_regularization_params(params) do
    l1 = Map.get(params, :regularization_l1, 0.0)
    l2 = Map.get(params, :regularization_l2, 0.0)

    cond do
      not is_number(l1) or l1 < 0 or l1 > 1.0 ->
        {:error, "L1 regularization must be between 0 and 1.0"}

      not is_number(l2) or l2 < 0 or l2 > 1.0 ->
        {:error, "L2 regularization must be between 0 and 1.0"}

      true ->
        :ok
    end
  end

  defp calculate_base_training_time(config, data_size) do
    # Base calculation in seconds
    base_time_per_sample = 0.01
    iteration_factor = config.training.max_iterations / 1000.0
    complexity_factor = if config.features.advanced_enabled, do: 2.0, else: 1.0

    base_time_per_sample * data_size * iteration_factor * complexity_factor
  end

  defp calculate_memory_factor(memory_limit_mb, data_size) do
    # Estimate memory pressure factor
    estimated_memory_need = data_size * 0.001
    memory_pressure = estimated_memory_need / memory_limit_mb

    cond do
      memory_pressure < 0.5 -> 1.0
      memory_pressure < 0.8 -> 1.2
      memory_pressure < 1.0 -> 1.5
      true -> 2.0
    end
  end

  defp calculate_max_training_time(settings) do
    # Calculate maximum training time based on resource limits
    base_hours = 2
    memory_factor = settings.memory_limit_mb / 2048.0
    cpu_factor = settings.cpu_limit_percent / 50.0

    round(base_hours * memory_factor * cpu_factor)
  end

  defp check_memory_limit(usage, limits) do
    Map.get(usage, :memory_mb, 0) <= limits.memory_limit_mb
  end

  defp check_cpu_limit(usage, limits) do
    Map.get(usage, :cpu_percent, 0) <= limits.cpu_limit_percent
  end

  defp check_time_limit(usage, limits) do
    Map.get(usage, :elapsed_hours, 0) <= limits.max_training_time_hours
  end

  defp generate_training_recommendations(config, data_characteristics) do
    data_size = Map.get(data_characteristics, :size, 1000)
    complexity = Map.get(data_characteristics, :complexity, :medium)

    base_recommendations = [
      %{
        type: :learning_rate,
        value: recommend_learning_rate(config, complexity),
        reason: "Optimal learning rate for #{complexity} complexity data"
      },
      %{
        type: :batch_size,
        value: recommend_batch_size(config, data_size),
        reason: "Recommended batch size for #{data_size} samples"
      },
      %{
        type: :iterations,
        value: recommend_iterations(config, data_size, complexity),
        reason: "Estimated iterations needed for convergence"
      }
    ]

    if config.features.advanced_enabled do
      base_recommendations ++ get_advanced_recommendations(config, data_characteristics)
    else
      base_recommendations
    end
  end

  defp recommend_learning_rate(_config, complexity) do
    case complexity do
      :low -> 0.01
      :medium -> 0.001
      :high -> 0.0001
    end
  end

  defp recommend_batch_size(_config, data_size) do
    cond do
      data_size < 1000 -> 16
      data_size < 10_000 -> 32
      data_size < 100_000 -> 64
      true -> 128
    end
  end

  defp recommend_iterations(_config, data_size, complexity) do
    base_iterations =
      case complexity do
        :low -> 100
        :medium -> 500
        :high -> 1000
      end

    # Adjust based on data size
    size_factor =
      cond do
        data_size < 1000 -> 2.0
        data_size < 10_000 -> 1.5
        data_size < 100_000 -> 1.0
        true -> 0.8
      end

    round(base_iterations * size_factor)
  end

  defp get_advanced_recommendations(_config, _data_characteristics) do
    [
      %{
        type: :regularization,
        value: %{l1: 0.01, l2: 0.01},
        reason: "Balanced regularization to prevent overfitting"
      },
      %{
        type: :early_stopping,
        value: true,
        reason: "Recommended for advanced models to prevent overfitting"
      }
    ]
  end
end
