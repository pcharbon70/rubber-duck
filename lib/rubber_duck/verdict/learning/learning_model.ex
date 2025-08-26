defmodule RubberDuck.Verdict.Learning.LearningModel do
  @moduledoc """
  Ash resource for persistent learning model state and evolution tracking.
  
  Stores machine learning model states, parameters, performance metrics, and
  evolution history to enable model versioning, rollback capabilities, and
  continuous learning effectiveness measurement.
  """

  use Ash.Resource,
    domain: RubberDuck.Verdict,
    data_layer: AshPostgres.DataLayer

  import Ash.Expr
  require Ash.Query
  require Logger

  postgres do
    table "verdict_learning_models"
    repo RubberDuck.Repo
  end

  resource do
    description "Persistent learning model state for continuous system improvement"
  end

  attributes do
    uuid_primary_key :id

    attribute :model_name, :string do
      description "Human-readable name for the learning model"
      allow_nil? false
    end

    attribute :model_type, :atom do
      description "Type of learning model"
      constraints one_of: [
        :judge_selection_model, :criteria_adaptation_model, :cost_optimization_model,
        :bias_detection_model, :user_preference_model, :temporal_prediction_model
      ]
      allow_nil? false
    end

    attribute :model_version, :string do
      description "Version identifier for the model"
      default "1.0.0"
    end

    attribute :model_parameters, :map do
      description "Current model parameters and configuration"
      default %{}
    end

    attribute :model_state, :map do
      description "Current learned state and weights"
      default %{}
    end

    attribute :training_data_count, :integer do
      description "Number of data points used to train this model"
      default 0
    end

    attribute :effectiveness_score, :decimal do
      description "Measured effectiveness of this model (0.0 to 1.0)"
      constraints min: 0.0, max: 1.0
    end

    attribute :confidence_score, :decimal do
      description "Confidence in model predictions (0.0 to 1.0)"
      constraints min: 0.0, max: 1.0
      default 0.7
    end

    attribute :model_status, :atom do
      description "Current status of the learning model"
      constraints one_of: [:training, :active, :validating, :deprecated, :archived]
      default :training
    end

    attribute :performance_history, :map do
      description "Historical performance metrics and trends"
      default %{}
    end

    attribute :validation_results, :map do
      description "Results from model validation testing"
      default %{}
    end

    attribute :rollback_checkpoint, :map do
      description "Checkpoint data for model rollback"
      default %{}
    end

    attribute :last_trained, :utc_datetime_usec do
      description "When the model was last trained"
    end

    attribute :last_updated, :utc_datetime_usec do
      description "When the model state was last updated"
      default &DateTime.utc_now/0
    end

    timestamps()
  end

  actions do
    defaults [:read]

    create :create do
      accept [:model_name, :model_type, :model_parameters, :training_data_count, :confidence_score]
    end

    update :update_model do
      accept [:model_parameters, :model_state, :effectiveness_score, :confidence_score, :performance_history]
      
      change set_attribute(:last_updated, &DateTime.utc_now/0)
    end

    update :activate_model do
      change set_attribute(:model_status, :active)
      change set_attribute(:last_updated, &DateTime.utc_now/0)
    end

    update :validate_model do
      accept [:validation_results]
      require_atomic? false
      
      change set_attribute(:model_status, :validating)
    end

    update :deprecate_model do
      require_atomic? false
      
      change set_attribute(:model_status, :deprecated)
    end
  end

  code_interface do
    define :create
    define :update_model
    define :activate_model
    define :validate_model
    define :deprecate_model
    define :read
  end

  calculations do
    calculate :is_active, :boolean, expr(model_status == :active)
    calculate :is_effective, :boolean, expr(effectiveness_score > 0.7)
    calculate :model_age_days, :integer,
      expr(fragment("EXTRACT(DAY FROM (? - ?))", now(), inserted_at))
    
    calculate :days_since_update, :integer,
      expr(fragment("EXTRACT(DAY FROM (? - ?))", now(), last_updated))
  end

  validations do
    validate present([:model_name, :model_type])
    validate numericality(:effectiveness_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    validate numericality(:confidence_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end

  changes do
    change after_action(&log_model_creation/3) do
      on [:create]
    end
  end

  # Custom change functions

  def log_model_creation(_changeset, result, _opts) do
    model_name = result.model_name
    model_type = result.model_type
    
    require Logger
    Logger.info("Learning model created: #{model_name} (#{model_type})")
    
    {:ok, result}
  end

  # Helper functions for model management

  @doc """
  Get active learning models by type.
  """
  def get_active_models(model_type \\ nil) do
    query = __MODULE__
      |> Ash.Query.filter(is_active: true)
      |> Ash.Query.sort(effectiveness_score: :desc)
    
    query = if model_type do
      Ash.Query.filter(query, model_type: model_type)
    else
      query
    end
    
    query |> Ash.read!()
  end

  @doc """
  Get effective models above threshold.
  """
  def get_effective_models(effectiveness_threshold \\ 0.7) do
    __MODULE__
    |> Ash.Query.filter(is_effective: true)
    |> Ash.Query.filter(effectiveness_score > effectiveness_threshold)
    |> Ash.Query.sort(effectiveness_score: :desc)
    |> Ash.read!()
  end

  @doc """
  Get models needing updates or validation.
  """
  def get_models_needing_attention(days_since_update \\ 7) do
    __MODULE__
    |> Ash.Query.filter(model_status: [:active, :training])
    |> Ash.Query.filter(days_since_update > days_since_update)
    |> Ash.Query.sort(days_since_update: :desc)
    |> Ash.read!()
  end

  @doc """
  Get model performance statistics.
  """
  def get_model_performance_stats do
    all_models = __MODULE__ |> Ash.read!()
    
    by_type = Enum.group_by(all_models, & &1.model_type)
    by_status = Enum.group_by(all_models, & &1.model_status)
    
    %{
      total_models: length(all_models),
      active_models: length(Enum.filter(all_models, & &1.is_active)),
      effective_models: length(Enum.filter(all_models, & &1.is_effective)),
      by_type: calculate_type_distribution(by_type),
      by_status: calculate_status_distribution(by_status),
      average_effectiveness: calculate_average_effectiveness(all_models),
      average_confidence: calculate_average_confidence(all_models)
    }
  end

  # Private helper functions

  defp calculate_type_distribution(models_by_type) do
    Enum.map(models_by_type, fn {type, models} ->
      {type, length(models)}
    end) |> Map.new()
  end

  defp calculate_status_distribution(models_by_status) do
    Enum.map(models_by_status, fn {status, models} ->
      {status, length(models)}
    end) |> Map.new()
  end

  defp calculate_average_effectiveness([]), do: 0.0
  defp calculate_average_effectiveness(models) do
    effectiveness_scores = Enum.map(models, fn model ->
      model.effectiveness_score || 0.0
    end) |> Enum.filter(&(&1 > 0))
    
    if Enum.empty?(effectiveness_scores) do
      0.0
    else
      Enum.sum(effectiveness_scores) / length(effectiveness_scores)
    end
  end

  defp calculate_average_confidence([]), do: 0.0
  defp calculate_average_confidence(models) do
    confidences = Enum.map(models, & &1.confidence_score)
    Enum.sum(confidences) / length(confidences)
  end
end