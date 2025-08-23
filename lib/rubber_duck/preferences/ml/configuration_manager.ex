defmodule RubberDuck.Preferences.Ml.ConfigurationManager do
  @moduledoc """
  ML configuration management for machine learning preferences.

  Manages ML feature enablement, model selection criteria, performance
  settings, and training parameters. Provides centralized configuration
  resolution with hierarchy support and validation.
  """

  require Logger

  alias RubberDuck.Preferences.PreferenceResolver
  alias RubberDuck.Preferences.Validators.MlPreferenceValidator

  @doc """
  Get complete ML configuration for a user and optional project.
  """
  @spec get_ml_config(user_id :: binary(), project_id :: binary() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def get_ml_config(user_id, project_id \\ nil) do
    with {:ok, raw_config} <- resolve_ml_preferences(user_id, project_id),
         {:ok, validated_config} <- validate_ml_configuration(raw_config),
         {:ok, processed_config} <- process_ml_configuration(validated_config) do
      {:ok, processed_config}
    else
      error ->
        Logger.warning("Failed to get ML configuration for user #{user_id}: #{inspect(error)}")
        {:error, "Unable to load ML configuration"}
    end
  end

  @doc """
  Check if ML features are enabled for a user/project.
  """
  @spec ml_enabled?(user_id :: binary(), project_id :: binary() | nil) :: boolean()
  def ml_enabled?(user_id, project_id \\ nil) do
    case get_ml_config(user_id, project_id) do
      {:ok, config} -> config.global.enabled
      {:error, _} -> false
    end
  end

  @doc """
  Check if specific ML feature is enabled.
  """
  @spec feature_enabled?(
          user_id :: binary(),
          feature :: atom(),
          project_id :: binary() | nil
        ) :: boolean()
  def feature_enabled?(user_id, feature, project_id \\ nil) do
    case get_ml_config(user_id, project_id) do
      {:ok, config} ->
        case feature do
          :naive -> config.features.naive_enabled
          :advanced -> config.features.advanced_enabled
          :experiment_tracking -> config.features.experiment_tracking
          :auto_optimization -> config.features.auto_optimization
          _ -> false
        end

      {:error, _} ->
        false
    end
  end

  @doc """
  Get training parameters for ML operations.
  """
  @spec get_training_params(user_id :: binary(), project_id :: binary() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def get_training_params(user_id, project_id \\ nil) do
    case get_ml_config(user_id, project_id) do
      {:ok, config} -> {:ok, config.training}
      error -> error
    end
  end

  @doc """
  Get performance settings for ML operations.
  """
  @spec get_performance_settings(user_id :: binary(), project_id :: binary() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def get_performance_settings(user_id, project_id \\ nil) do
    case get_ml_config(user_id, project_id) do
      {:ok, config} -> {:ok, config.performance}
      error -> error
    end
  end

  @doc """
  Get data management policies for ML operations.
  """
  @spec get_data_policies(user_id :: binary(), project_id :: binary() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def get_data_policies(user_id, project_id \\ nil) do
    case get_ml_config(user_id, project_id) do
      {:ok, config} -> {:ok, config.data}
      error -> error
    end
  end

  @doc """
  Check if user has consented to ML training data usage.
  """
  @spec user_consent_given?(user_id :: binary(), project_id :: binary() | nil) :: boolean()
  def user_consent_given?(user_id, project_id \\ nil) do
    case get_data_policies(user_id, project_id) do
      {:ok, policies} ->
        # If consent is not required, assume consent
        if policies.user_consent_required do
          # Check for explicit consent (would integrate with user consent system)
          check_user_consent(user_id, project_id)
        else
          true
        end

      {:error, _} ->
        false
    end
  end

  # Private functions

  defp resolve_ml_preferences(user_id, project_id) do
    ml_preference_keys = [
      # Global enablement
      "ml.global.enabled",
      # Features
      "ml.features.naive_enabled",
      "ml.features.advanced_enabled",
      "ml.features.experiment_tracking",
      "ml.features.auto_optimization",
      # Model selection
      "ml.models.default_framework",
      "ml.models.selection_criteria",
      "ml.models.fallback_enabled",
      "ml.models.versioning_enabled",
      "ml.models.auto_update_policy",
      # Performance
      "ml.performance.accuracy_threshold",
      "ml.performance.speed_priority",
      "ml.performance.memory_limit_mb",
      "ml.performance.cpu_limit_percent",
      "ml.performance.batch_size",
      "ml.performance.parallel_workers",
      # Training
      "ml.training.learning_rate",
      "ml.training.max_iterations",
      "ml.training.convergence_threshold",
      "ml.training.early_stopping_enabled",
      "ml.training.regularization_l1",
      "ml.training.regularization_l2",
      # Data management
      "ml.data.retention_days",
      "ml.data.auto_cleanup_enabled",
      "ml.data.privacy_mode",
      "ml.data.anonymization_enabled",
      "ml.data.user_consent_required",
      "ml.data.opt_out_enabled",
      "ml.data.sharing_allowed",
      # Monitoring
      "ml.monitoring.accuracy_tracking",
      "ml.monitoring.latency_tracking",
      "ml.monitoring.drift_detection",
      "ml.monitoring.resource_alerts",
      # Feedback
      "ml.feedback.user_feedback_enabled",
      "ml.feedback.auto_retrain_threshold",
      "ml.feedback.learning_curve_enabled",
      # Experiments
      "ml.experiments.ab_testing_enabled",
      "ml.experiments.traffic_split_ratio",
      "ml.experiments.experiment_duration_days",
      "ml.experiments.statistical_significance",
      "ml.experiments.min_sample_size"
    ]

    case PreferenceResolver.resolve_batch(user_id, ml_preference_keys, project_id) do
      {:ok, preferences} -> {:ok, preferences}
      error -> error
    end
  end

  defp validate_ml_configuration(raw_config) do
    case MlPreferenceValidator.validate_ml_config_consistency(raw_config) do
      :ok -> {:ok, raw_config}
      error -> error
    end
  end

  defp process_ml_configuration(raw_config) do
    processed = %{
      global: %{
        enabled: parse_boolean(raw_config["ml.global.enabled"])
      },
      features: %{
        naive_enabled: parse_boolean(raw_config["ml.features.naive_enabled"]),
        advanced_enabled: parse_boolean(raw_config["ml.features.advanced_enabled"]),
        experiment_tracking: parse_boolean(raw_config["ml.features.experiment_tracking"]),
        auto_optimization: parse_boolean(raw_config["ml.features.auto_optimization"])
      },
      models: %{
        default_framework: raw_config["ml.models.default_framework"],
        selection_criteria: raw_config["ml.models.selection_criteria"],
        fallback_enabled: parse_boolean(raw_config["ml.models.fallback_enabled"]),
        versioning_enabled: parse_boolean(raw_config["ml.models.versioning_enabled"]),
        auto_update_policy: raw_config["ml.models.auto_update_policy"]
      },
      performance: %{
        accuracy_threshold: parse_float(raw_config["ml.performance.accuracy_threshold"]),
        speed_priority: parse_float(raw_config["ml.performance.speed_priority"]),
        memory_limit_mb: parse_integer(raw_config["ml.performance.memory_limit_mb"]),
        cpu_limit_percent: parse_integer(raw_config["ml.performance.cpu_limit_percent"]),
        batch_size: parse_integer(raw_config["ml.performance.batch_size"]),
        parallel_workers: parse_integer(raw_config["ml.performance.parallel_workers"])
      },
      training: %{
        learning_rate: parse_float(raw_config["ml.training.learning_rate"]),
        max_iterations: parse_integer(raw_config["ml.training.max_iterations"]),
        convergence_threshold: parse_float(raw_config["ml.training.convergence_threshold"]),
        early_stopping_enabled: parse_boolean(raw_config["ml.training.early_stopping_enabled"]),
        regularization_l1: parse_float(raw_config["ml.training.regularization_l1"]),
        regularization_l2: parse_float(raw_config["ml.training.regularization_l2"])
      },
      data: %{
        retention_days: parse_integer(raw_config["ml.data.retention_days"]),
        auto_cleanup_enabled: parse_boolean(raw_config["ml.data.auto_cleanup_enabled"]),
        privacy_mode: raw_config["ml.data.privacy_mode"],
        anonymization_enabled: parse_boolean(raw_config["ml.data.anonymization_enabled"]),
        user_consent_required: parse_boolean(raw_config["ml.data.user_consent_required"]),
        opt_out_enabled: parse_boolean(raw_config["ml.data.opt_out_enabled"]),
        sharing_allowed: parse_boolean(raw_config["ml.data.sharing_allowed"])
      },
      monitoring: %{
        accuracy_tracking: parse_boolean(raw_config["ml.monitoring.accuracy_tracking"]),
        latency_tracking: parse_boolean(raw_config["ml.monitoring.latency_tracking"]),
        drift_detection: parse_boolean(raw_config["ml.monitoring.drift_detection"]),
        resource_alerts: parse_boolean(raw_config["ml.monitoring.resource_alerts"])
      },
      feedback: %{
        user_feedback_enabled: parse_boolean(raw_config["ml.feedback.user_feedback_enabled"]),
        auto_retrain_threshold: parse_float(raw_config["ml.feedback.auto_retrain_threshold"]),
        learning_curve_enabled: parse_boolean(raw_config["ml.feedback.learning_curve_enabled"])
      },
      experiments: %{
        ab_testing_enabled: parse_boolean(raw_config["ml.experiments.ab_testing_enabled"]),
        traffic_split_ratio: parse_float(raw_config["ml.experiments.traffic_split_ratio"]),
        experiment_duration_days:
          parse_integer(raw_config["ml.experiments.experiment_duration_days"]),
        statistical_significance:
          parse_float(raw_config["ml.experiments.statistical_significance"]),
        min_sample_size: parse_integer(raw_config["ml.experiments.min_sample_size"])
      }
    }

    {:ok, processed}
  end

  defp check_user_consent(_user_id, _project_id) do
    # Placeholder for user consent checking
    # This would integrate with actual user consent system
    true
  end

  # Helper functions for type conversion
  defp parse_boolean("true"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean(value) when is_boolean(value), do: value
  defp parse_boolean(_), do: false

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int_value, ""} -> int_value
      _ -> 0
    end
  end

  defp parse_integer(value) when is_integer(value), do: value
  defp parse_integer(_), do: 0

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float_value, ""} -> float_value
      _ -> 0.0
    end
  end

  defp parse_float(value) when is_float(value), do: value
  defp parse_float(value) when is_integer(value), do: value / 1.0
  defp parse_float(_), do: 0.0
end
