defmodule RubberDuck.Preferences.Seeders.MlDefaultsSeeder do
  @moduledoc """
  Seeds machine learning preference defaults into the system.

  Creates comprehensive default configurations for ML feature enablement,
  model selection, training parameters, data management policies, and
  performance monitoring settings.
  """

  require Logger

  alias RubberDuck.Preferences.Resources.SystemDefault

  @doc """
  Seed all ML preference defaults.
  """
  @spec seed_all() :: :ok | {:error, term()}
  def seed_all do
    Logger.info("Seeding ML preference defaults...")

    with :ok <- seed_ml_enablement_defaults(),
         :ok <- seed_model_selection_defaults(),
         :ok <- seed_performance_settings_defaults(),
         :ok <- seed_training_parameters_defaults(),
         :ok <- seed_data_management_defaults(),
         :ok <- seed_monitoring_feedback_defaults(),
         :ok <- seed_experiment_defaults() do
      Logger.info("Successfully seeded all ML preference defaults")
      :ok
    else
      error ->
        Logger.error("Failed to seed ML defaults: #{inspect(error)}")
        error
    end
  end

  @doc """
  Seed ML enablement preference defaults.
  """
  @spec seed_ml_enablement_defaults() :: :ok | {:error, term()}
  def seed_ml_enablement_defaults do
    defaults = [
      %{
        preference_key: "ml.global.enabled",
        default_value: "false",
        data_type: :boolean,
        category: "ml",
        subcategory: "global",
        description: "Enable machine learning features globally",
        access_level: :admin,
        display_order: 1
      },
      %{
        preference_key: "ml.features.naive_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "ml",
        subcategory: "features",
        description: "Enable basic ML features with simple algorithms",
        access_level: :user,
        display_order: 2
      },
      %{
        preference_key: "ml.features.advanced_enabled",
        default_value: "false",
        data_type: :boolean,
        category: "ml",
        subcategory: "features",
        description: "Enable advanced ML features with complex algorithms",
        access_level: :admin,
        display_order: 3
      },
      %{
        preference_key: "ml.features.experiment_tracking",
        default_value: "false",
        data_type: :boolean,
        category: "ml",
        subcategory: "features",
        description: "Enable ML experiment tracking and logging",
        access_level: :user,
        display_order: 4
      },
      %{
        preference_key: "ml.features.auto_optimization",
        default_value: "false",
        data_type: :boolean,
        category: "ml",
        subcategory: "features",
        description: "Enable automatic ML model optimization",
        access_level: :admin,
        display_order: 5
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed model selection preference defaults.
  """
  @spec seed_model_selection_defaults() :: :ok | {:error, term()}
  def seed_model_selection_defaults do
    defaults = [
      %{
        preference_key: "ml.models.default_framework",
        default_value: "sklearn",
        data_type: :string,
        category: "ml",
        subcategory: "models",
        description: "Default ML framework for model training",
        constraints: %{allowed_values: ["sklearn", "pytorch", "tensorflow", "xgboost"]},
        access_level: :user,
        display_order: 10
      },
      %{
        preference_key: "ml.models.selection_criteria",
        default_value: "balanced",
        data_type: :string,
        category: "ml",
        subcategory: "models",
        description: "Primary model selection criteria",
        constraints: %{allowed_values: ["accuracy", "speed", "memory", "balanced"]},
        access_level: :user,
        display_order: 11
      },
      %{
        preference_key: "ml.models.fallback_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "ml",
        subcategory: "models",
        description: "Enable fallback to simpler models on failure",
        access_level: :user,
        display_order: 12
      },
      %{
        preference_key: "ml.models.versioning_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "ml",
        subcategory: "models",
        description: "Enable model versioning and rollback capabilities",
        access_level: :user,
        display_order: 13
      },
      %{
        preference_key: "ml.models.auto_update_policy",
        default_value: "manual",
        data_type: :string,
        category: "ml",
        subcategory: "models",
        description: "Automatic model update policy",
        constraints: %{allowed_values: ["disabled", "manual", "automatic", "scheduled"]},
        access_level: :admin,
        display_order: 14
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed performance settings preference defaults.
  """
  @spec seed_performance_settings_defaults() :: :ok | {:error, term()}
  def seed_performance_settings_defaults do
    defaults = [
      %{
        preference_key: "ml.performance.accuracy_threshold",
        default_value: "0.85",
        data_type: :float,
        category: "ml",
        subcategory: "performance",
        description: "Minimum acceptable model accuracy (0.0-1.0)",
        constraints: %{min: 0.0, max: 1.0},
        access_level: :user,
        display_order: 20
      },
      %{
        preference_key: "ml.performance.speed_priority",
        default_value: "0.5",
        data_type: :float,
        category: "ml",
        subcategory: "performance",
        description: "Speed vs accuracy trade-off (0.0=accuracy, 1.0=speed)",
        constraints: %{min: 0.0, max: 1.0},
        access_level: :user,
        display_order: 21
      },
      %{
        preference_key: "ml.performance.memory_limit_mb",
        default_value: "2048",
        data_type: :integer,
        category: "ml",
        subcategory: "performance",
        description: "Memory usage limit in megabytes",
        constraints: %{min: 512, max: 32_768},
        access_level: :user,
        display_order: 22
      },
      %{
        preference_key: "ml.performance.cpu_limit_percent",
        default_value: "50",
        data_type: :integer,
        category: "ml",
        subcategory: "performance",
        description: "CPU usage limit percentage",
        constraints: %{min: 10, max: 100},
        access_level: :user,
        display_order: 23
      },
      %{
        preference_key: "ml.performance.batch_size",
        default_value: "32",
        data_type: :integer,
        category: "ml",
        subcategory: "performance",
        description: "Default batch size for ML training",
        constraints: %{min: 1, max: 1024},
        access_level: :user,
        display_order: 24
      },
      %{
        preference_key: "ml.performance.parallel_workers",
        default_value: "4",
        data_type: :integer,
        category: "ml",
        subcategory: "performance",
        description: "Number of parallel workers for ML operations",
        constraints: %{min: 1, max: 32},
        access_level: :user,
        display_order: 25
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed training parameters preference defaults.
  """
  @spec seed_training_parameters_defaults() :: :ok | {:error, term()}
  def seed_training_parameters_defaults do
    defaults = [
      %{
        preference_key: "ml.training.learning_rate",
        default_value: "0.001",
        data_type: :float,
        category: "ml",
        subcategory: "training",
        description: "Default learning rate for model training",
        constraints: %{min: 0.000_001, max: 1.0},
        access_level: :user,
        display_order: 30
      },
      %{
        preference_key: "ml.training.max_iterations",
        default_value: "1000",
        data_type: :integer,
        category: "ml",
        subcategory: "training",
        description: "Maximum training iterations",
        constraints: %{min: 10, max: 100_000},
        access_level: :user,
        display_order: 31
      },
      %{
        preference_key: "ml.training.convergence_threshold",
        default_value: "0.001",
        data_type: :float,
        category: "ml",
        subcategory: "training",
        description: "Convergence threshold for training completion",
        constraints: %{min: 0.000_001, max: 0.1},
        access_level: :user,
        display_order: 32
      },
      %{
        preference_key: "ml.training.early_stopping_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "ml",
        subcategory: "training",
        description: "Enable early stopping to prevent overfitting",
        access_level: :user,
        display_order: 33
      },
      %{
        preference_key: "ml.training.regularization_l1",
        default_value: "0.01",
        data_type: :float,
        category: "ml",
        subcategory: "training",
        description: "L1 regularization parameter",
        constraints: %{min: 0.0, max: 1.0},
        access_level: :user,
        display_order: 34
      },
      %{
        preference_key: "ml.training.regularization_l2",
        default_value: "0.01",
        data_type: :float,
        category: "ml",
        subcategory: "training",
        description: "L2 regularization parameter",
        constraints: %{min: 0.0, max: 1.0},
        access_level: :user,
        display_order: 35
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed data management preference defaults.
  """
  @spec seed_data_management_defaults() :: :ok | {:error, term()}
  def seed_data_management_defaults do
    defaults = [
      %{
        preference_key: "ml.data.retention_days",
        default_value: "365",
        data_type: :integer,
        category: "ml",
        subcategory: "data",
        description: "Data retention period in days for ML training data",
        constraints: %{min: 30, max: 2555},
        access_level: :admin,
        display_order: 40
      },
      %{
        preference_key: "ml.data.auto_cleanup_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "ml",
        subcategory: "data",
        description: "Enable automatic cleanup of expired training data",
        access_level: :admin,
        display_order: 41
      },
      %{
        preference_key: "ml.data.privacy_mode",
        default_value: "strict",
        data_type: :string,
        category: "ml",
        subcategory: "data",
        description: "Privacy protection mode for ML training data",
        constraints: %{allowed_values: ["strict", "moderate", "permissive"]},
        access_level: :admin,
        display_order: 42
      },
      %{
        preference_key: "ml.data.anonymization_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "ml",
        subcategory: "data",
        description: "Enable data anonymization for ML training",
        access_level: :admin,
        display_order: 43
      },
      %{
        preference_key: "ml.data.user_consent_required",
        default_value: "true",
        data_type: :boolean,
        category: "ml",
        subcategory: "data",
        description: "Require explicit user consent for training data usage",
        access_level: :admin,
        display_order: 44
      },
      %{
        preference_key: "ml.data.opt_out_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "ml",
        subcategory: "data",
        description: "Enable user opt-out mechanism for ML training",
        access_level: :admin,
        display_order: 45
      },
      %{
        preference_key: "ml.data.sharing_allowed",
        default_value: "false",
        data_type: :boolean,
        category: "ml",
        subcategory: "data",
        description: "Allow sharing ML training data with external systems",
        access_level: :superadmin,
        sensitive: true,
        display_order: 46
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed monitoring and feedback preference defaults.
  """
  @spec seed_monitoring_feedback_defaults() :: :ok | {:error, term()}
  def seed_monitoring_feedback_defaults do
    defaults = [
      %{
        preference_key: "ml.monitoring.accuracy_tracking",
        default_value: "true",
        data_type: :boolean,
        category: "ml",
        subcategory: "monitoring",
        description: "Enable model accuracy tracking and reporting",
        access_level: :user,
        display_order: 50
      },
      %{
        preference_key: "ml.monitoring.latency_tracking",
        default_value: "true",
        data_type: :boolean,
        category: "ml",
        subcategory: "monitoring",
        description: "Enable model latency monitoring",
        access_level: :user,
        display_order: 51
      },
      %{
        preference_key: "ml.monitoring.drift_detection",
        default_value: "true",
        data_type: :boolean,
        category: "ml",
        subcategory: "monitoring",
        description: "Enable model drift detection and alerts",
        access_level: :user,
        display_order: 52
      },
      %{
        preference_key: "ml.monitoring.resource_alerts",
        default_value: "true",
        data_type: :boolean,
        category: "ml",
        subcategory: "monitoring",
        description: "Enable resource usage alerts for ML operations",
        access_level: :user,
        display_order: 53
      },
      %{
        preference_key: "ml.feedback.user_feedback_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "ml",
        subcategory: "feedback",
        description: "Enable collection of user feedback on ML predictions",
        access_level: :user,
        display_order: 54
      },
      %{
        preference_key: "ml.feedback.auto_retrain_threshold",
        default_value: "0.1",
        data_type: :float,
        category: "ml",
        subcategory: "feedback",
        description: "Accuracy drop threshold for automatic retraining (0.0-1.0)",
        constraints: %{min: 0.01, max: 0.5},
        access_level: :user,
        display_order: 55
      },
      %{
        preference_key: "ml.feedback.learning_curve_enabled",
        default_value: "true",
        data_type: :boolean,
        category: "ml",
        subcategory: "feedback",
        description: "Enable learning curve visualization and analysis",
        access_level: :user,
        display_order: 56
      }
    ]

    seed_defaults(defaults)
  end

  @doc """
  Seed A/B testing and experiment preference defaults.
  """
  @spec seed_experiment_defaults() :: :ok | {:error, term()}
  def seed_experiment_defaults do
    defaults = [
      %{
        preference_key: "ml.experiments.ab_testing_enabled",
        default_value: "false",
        data_type: :boolean,
        category: "ml",
        subcategory: "experiments",
        description: "Enable A/B testing for ML models",
        access_level: :admin,
        display_order: 60
      },
      %{
        preference_key: "ml.experiments.traffic_split_ratio",
        default_value: "0.1",
        data_type: :float,
        category: "ml",
        subcategory: "experiments",
        description: "Traffic split ratio for A/B testing (0.0-1.0)",
        constraints: %{min: 0.01, max: 0.5},
        access_level: :admin,
        display_order: 61
      },
      %{
        preference_key: "ml.experiments.experiment_duration_days",
        default_value: "7",
        data_type: :integer,
        category: "ml",
        subcategory: "experiments",
        description: "Default experiment duration in days",
        constraints: %{min: 1, max: 90},
        access_level: :admin,
        display_order: 62
      },
      %{
        preference_key: "ml.experiments.statistical_significance",
        default_value: "0.05",
        data_type: :float,
        category: "ml",
        subcategory: "experiments",
        description: "Required statistical significance level for experiments",
        constraints: %{min: 0.01, max: 0.1},
        access_level: :admin,
        display_order: 63
      },
      %{
        preference_key: "ml.experiments.min_sample_size",
        default_value: "1000",
        data_type: :integer,
        category: "ml",
        subcategory: "experiments",
        description: "Minimum sample size for valid experiments",
        constraints: %{min: 100, max: 100_000},
        access_level: :admin,
        display_order: 64
      }
    ]

    seed_defaults(defaults)
  end

  # Private helper function to seed defaults
  defp seed_defaults(defaults) do
    Enum.each(defaults, fn default_attrs ->
      case SystemDefault.seed_default(default_attrs) do
        {:ok, _} ->
          :ok

        {:error, error} ->
          Logger.warning(
            "Failed to seed ML default #{default_attrs.preference_key}: #{inspect(error)}"
          )
      end
    end)

    :ok
  rescue
    error ->
      Logger.error("Error seeding ML defaults: #{inspect(error)}")
      {:error, error}
  end
end
