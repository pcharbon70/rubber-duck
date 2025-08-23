defmodule RubberDuck.Preferences.Ml.ModelRegistry do
  @moduledoc """
  ML model registry for managing model selection and versioning.

  Manages available ML models, their capabilities, versioning information,
  and selection logic based on user preferences and performance requirements.
  Integrates with the preference system for model selection criteria.
  """

  require Logger

  alias RubberDuck.Preferences.Ml.ConfigurationManager

  # Model definitions with capabilities and constraints
  @available_models %{
    "sklearn" => %{
      naive_models: ["linear_regression", "logistic_regression", "decision_tree"],
      advanced_models: ["random_forest", "gradient_boosting", "svm"],
      capabilities: [:classification, :regression, :clustering],
      memory_efficient: true,
      training_speed: :fast,
      inference_speed: :fast
    },
    "pytorch" => %{
      naive_models: ["linear", "mlp"],
      advanced_models: ["resnet", "transformer", "lstm"],
      capabilities: [:classification, :regression, :deep_learning],
      memory_efficient: false,
      training_speed: :slow,
      inference_speed: :medium
    },
    "tensorflow" => %{
      naive_models: ["linear", "dnn"],
      advanced_models: ["cnn", "transformer", "autoencoder"],
      capabilities: [:classification, :regression, :deep_learning, :computer_vision],
      memory_efficient: false,
      training_speed: :slow,
      inference_speed: :medium
    },
    "xgboost" => %{
      naive_models: ["xgb_classifier", "xgb_regressor"],
      advanced_models: ["xgb_rf", "xgb_dart"],
      capabilities: [:classification, :regression, :ranking],
      memory_efficient: true,
      training_speed: :medium,
      inference_speed: :fast
    }
  }

  @doc """
  Get available models for a specific framework.
  """
  @spec get_available_models(framework :: String.t()) :: {:ok, map()} | {:error, String.t()}
  def get_available_models(framework)
      when framework in ["sklearn", "pytorch", "tensorflow", "xgboost"] do
    {:ok, Map.get(@available_models, framework)}
  end

  def get_available_models(framework) do
    {:error, "Unsupported framework: #{framework}"}
  end

  @doc """
  Select the best model for a user based on their preferences and requirements.
  """
  @spec select_model(
          user_id :: binary(),
          task_requirements :: map(),
          project_id :: binary() | nil
        ) :: {:ok, map()} | {:error, String.t()}
  def select_model(user_id, task_requirements, project_id \\ nil) do
    with {:ok, config} <- ConfigurationManager.get_ml_config(user_id, project_id),
         {:ok, framework_models} <- get_available_models(config.models.default_framework),
         {:ok, selected_model} <- select_best_model(config, framework_models, task_requirements) do
      {:ok, selected_model}
    else
      error ->
        Logger.warning("Failed to select model for user #{user_id}: #{inspect(error)}")
        {:error, "Unable to select appropriate model"}
    end
  end

  @doc """
  Check if a model supports the required task type.
  """
  @spec model_supports_task?(framework :: String.t(), task_type :: atom()) :: boolean()
  def model_supports_task?(framework, task_type) do
    case get_available_models(framework) do
      {:ok, models} -> task_type in models.capabilities
      {:error, _} -> false
    end
  end

  @doc """
  Get model version information.
  """
  @spec get_model_version(framework :: String.t(), model_name :: String.t()) ::
          {:ok, map()} | {:error, String.t()}
  def get_model_version(framework, model_name) do
    # Placeholder for model versioning system
    # This would integrate with actual model registry/versioning system
    {:ok,
     %{
       framework: framework,
       model: model_name,
       version: "1.0.0",
       created_at: DateTime.utc_now(),
       checksum: "placeholder_checksum",
       performance_metrics: %{
         accuracy: 0.85,
         latency_ms: 100,
         memory_mb: 512
       }
     }}
  end

  @doc """
  Check if model update is available.
  """
  @spec update_available?(framework :: String.t(), model_name :: String.t()) :: boolean()
  def update_available?(framework, model_name) do
    # Placeholder for model update checking
    # This would check against model registry for newer versions
    case get_model_version(framework, model_name) do
      {:ok, _version_info} -> false
    end
  end

  @doc """
  Get recommended models based on user preferences and task requirements.
  """
  @spec get_recommendations(
          user_id :: binary(),
          task_requirements :: map(),
          project_id :: binary() | nil
        ) :: {:ok, list(map())} | {:error, String.t()}
  def get_recommendations(user_id, task_requirements, project_id \\ nil) do
    case ConfigurationManager.get_ml_config(user_id, project_id) do
      {:ok, config} ->
        recommendations = generate_model_recommendations(config, task_requirements)
        {:ok, recommendations}

      error ->
        error
    end
  end

  # Private functions

  defp select_best_model(config, framework_models, task_requirements) do
    available_models =
      if config.features.advanced_enabled do
        framework_models.naive_models ++ framework_models.advanced_models
      else
        framework_models.naive_models
      end

    # Filter models by task capability
    suitable_models =
      case Map.get(task_requirements, :task_type) do
        nil ->
          available_models

        task_type ->
          if task_type in framework_models.capabilities do
            available_models
          else
            []
          end
      end

    case suitable_models do
      [] ->
        {:error, "No suitable models found for requirements"}

      [model | _] ->
        # Select first suitable model (could be enhanced with scoring)
        {:ok,
         %{
           framework: config.models.default_framework,
           model: model,
           selection_criteria: config.models.selection_criteria,
           estimated_performance: estimate_model_performance(model, framework_models)
         }}
    end
  end

  defp generate_model_recommendations(config, task_requirements) do
    # Generate recommendations based on selection criteria
    case config.models.selection_criteria do
      "accuracy" ->
        get_accuracy_optimized_recommendations(config, task_requirements)

      "speed" ->
        get_speed_optimized_recommendations(config, task_requirements)

      "memory" ->
        get_memory_optimized_recommendations(config, task_requirements)

      "balanced" ->
        get_balanced_recommendations(config, task_requirements)

      _ ->
        []
    end
  end

  defp get_accuracy_optimized_recommendations(_config, _requirements) do
    [
      %{
        framework: "tensorflow",
        model: "transformer",
        priority: 1,
        reason: "Best accuracy for complex tasks"
      },
      %{
        framework: "pytorch",
        model: "resnet",
        priority: 2,
        reason: "High accuracy with good flexibility"
      },
      %{
        framework: "xgboost",
        model: "xgb_classifier",
        priority: 3,
        reason: "Strong accuracy for tabular data"
      }
    ]
  end

  defp get_speed_optimized_recommendations(_config, _requirements) do
    [
      %{
        framework: "sklearn",
        model: "linear_regression",
        priority: 1,
        reason: "Fastest training and inference"
      },
      %{
        framework: "xgboost",
        model: "xgb_classifier",
        priority: 2,
        reason: "Fast with good performance"
      },
      %{
        framework: "sklearn",
        model: "decision_tree",
        priority: 3,
        reason: "Very fast and interpretable"
      }
    ]
  end

  defp get_memory_optimized_recommendations(_config, _requirements) do
    [
      %{
        framework: "sklearn",
        model: "linear_regression",
        priority: 1,
        reason: "Minimal memory usage"
      },
      %{
        framework: "sklearn",
        model: "logistic_regression",
        priority: 2,
        reason: "Low memory footprint"
      },
      %{
        framework: "xgboost",
        model: "xgb_classifier",
        priority: 3,
        reason: "Memory efficient with good performance"
      }
    ]
  end

  defp get_balanced_recommendations(_config, _requirements) do
    [
      %{
        framework: "xgboost",
        model: "xgb_classifier",
        priority: 1,
        reason: "Best overall balance"
      },
      %{
        framework: "sklearn",
        model: "random_forest",
        priority: 2,
        reason: "Good balance and interpretability"
      },
      %{
        framework: "sklearn",
        model: "gradient_boosting",
        priority: 3,
        reason: "Solid performance across metrics"
      }
    ]
  end

  defp estimate_model_performance(model, framework_models) do
    # Placeholder performance estimation
    # This would use historical performance data or model benchmarks
    %{
      accuracy: estimate_accuracy(model, framework_models),
      speed: estimate_speed(model, framework_models),
      memory: estimate_memory(model, framework_models)
    }
  end

  defp estimate_accuracy(model, framework_models) do
    cond do
      model in framework_models.advanced_models -> 0.85
      model in framework_models.naive_models -> 0.75
      true -> 0.70
    end
  end

  defp estimate_speed(_model, framework_models) do
    case framework_models.training_speed do
      :fast -> 0.9
      :medium -> 0.7
      :slow -> 0.5
    end
  end

  defp estimate_memory(_model, framework_models) do
    if framework_models.memory_efficient do
      0.8
    else
      0.5
    end
  end
end
