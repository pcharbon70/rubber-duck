defmodule RubberDuck.Verdict.Adaptation.AdaptationHistory do
  @moduledoc """
  Ash resource for tracking system adaptations and their effectiveness over time.
  
  Records all adaptive changes made to the system including threshold adjustments,
  routing optimizations, and learning model updates, enabling impact assessment,
  rollback capabilities, and continuous improvement validation.
  """

  use Ash.Resource,
    domain: RubberDuck.Verdict,
    data_layer: AshPostgres.DataLayer

  import Ash.Expr
  require Ash.Query
  require Logger

  postgres do
    table "verdict_adaptation_history"
    repo RubberDuck.Repo
  end

  resource do
    description "Historical tracking of system adaptations and their effectiveness"
  end

  attributes do
    uuid_primary_key :id

    attribute :adaptation_type, :atom do
      description "Type of adaptation performed"
      constraints one_of: [
        :judge_selection_optimization, :threshold_adjustment, :routing_strategy_change,
        :consensus_mechanism_update, :cost_optimization, :bias_mitigation,
        :criteria_weight_adjustment, :model_parameter_update
      ]
      allow_nil? false
    end

    attribute :adaptation_name, :string do
      description "Human-readable name for this adaptation"
      allow_nil? false
    end

    attribute :adaptation_description, :string do
      description "Detailed description of the adaptation"
    end

    attribute :adaptation_source, :atom do
      description "What triggered this adaptation"
      constraints one_of: [
        :pattern_recognition, :user_feedback, :performance_monitoring,
        :bias_detection, :cost_optimization, :manual_adjustment
      ]
      allow_nil? false
    end

    attribute :learning_engine, :string do
      description "Learning engine that generated this adaptation"
    end

    attribute :pre_adaptation_state, :map do
      description "System state before adaptation"
      default %{}
    end

    attribute :adaptation_parameters, :map do
      description "Specific parameters and changes made"
      default %{}
    end

    attribute :post_adaptation_state, :map do
      description "System state after adaptation"
      default %{}
    end

    attribute :effectiveness_score, :decimal do
      description "Measured effectiveness of this adaptation (0.0 to 1.0)"
      constraints min: 0.0, max: 1.0
    end

    attribute :user_satisfaction_impact, :decimal do
      description "Impact on user satisfaction (-1.0 to 1.0)"
      constraints min: -1.0, max: 1.0
    end

    attribute :system_performance_impact, :decimal do
      description "Impact on system performance (-1.0 to 1.0)"
      constraints min: -1.0, max: 1.0
    end

    attribute :cost_impact, :decimal do
      description "Impact on system costs (-1.0 to 1.0, negative is savings)"
      constraints min: -1.0, max: 1.0
    end

    attribute :adaptation_status, :atom do
      description "Current status of the adaptation"
      constraints one_of: [:applied, :monitoring, :validated, :rolled_back, :deprecated]
      default :applied
    end

    attribute :validation_results, :map do
      description "Results from adaptation effectiveness validation"
      default %{}
    end

    attribute :rollback_information, :map do
      description "Information needed for rollback if adaptation fails"
      default %{}
    end

    attribute :confidence_score, :decimal do
      description "Confidence in the adaptation effectiveness (0.0 to 1.0)"
      constraints min: 0.0, max: 1.0
      default 0.7
    end

    attribute :applied_at, :utc_datetime_usec do
      description "When the adaptation was applied"
      default &DateTime.utc_now/0
    end

    attribute :validated_at, :utc_datetime_usec do
      description "When the adaptation was validated"
    end

    attribute :rolled_back_at, :utc_datetime_usec do
      description "When the adaptation was rolled back (if applicable)"
    end

    attribute :monitoring_duration_hours, :integer do
      description "How long to monitor this adaptation"
      default 24
    end

    timestamps()
  end

  relationships do
    # Would add relationships to learning models and pattern recognition when available
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :adaptation_type, :adaptation_name, :adaptation_description, :adaptation_source,
        :learning_engine, :pre_adaptation_state, :adaptation_parameters, 
        :confidence_score, :monitoring_duration_hours, :rollback_information
      ]
    end

    update :record_post_state do
      accept [:post_adaptation_state, :effectiveness_score, :user_satisfaction_impact, 
              :system_performance_impact, :cost_impact]
      require_atomic? false
      
      change set_attribute(:adaptation_status, :monitoring)
    end

    update :validate_adaptation do
      accept [:validation_results, :effectiveness_score]
      require_atomic? false
      
      change set_attribute(:adaptation_status, :validated)
      change set_attribute(:validated_at, &DateTime.utc_now/0)
    end

    update :rollback_adaptation do
      require_atomic? false
      
      change set_attribute(:adaptation_status, :rolled_back)
      change set_attribute(:rolled_back_at, &DateTime.utc_now/0)
    end

    update :deprecate_adaptation do
      require_atomic? false
      
      change set_attribute(:adaptation_status, :deprecated)
    end
  end

  code_interface do
    define :create
    define :record_post_state
    define :validate_adaptation
    define :rollback_adaptation
    define :deprecate_adaptation
    define :read
  end

  calculations do
    calculate :is_effective, :boolean, expr(effectiveness_score > 0.7)
    calculate :is_active, :boolean, expr(adaptation_status in [:applied, :monitoring, :validated])
    calculate :adaptation_age_hours, :integer,
      expr(fragment("EXTRACT(EPOCH FROM (? - ?)) / 3600", now(), applied_at))
    
    calculate :time_since_validation_hours, :integer,
      expr(fragment("EXTRACT(EPOCH FROM (? - ?)) / 3600", now(), validated_at))
      
    calculate :needs_validation, :boolean,
      expr(adaptation_status == :monitoring and adaptation_age_hours >= monitoring_duration_hours)
  end

  validations do
    validate present([:adaptation_type, :adaptation_name, :adaptation_source])
    validate numericality(:effectiveness_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    validate numericality(:confidence_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end

  changes do
    change after_action(&log_adaptation_application/3) do
      on [:create]
    end
    
    change after_action(&log_adaptation_status_change/3) do
      on [:update]
    end
  end

  # Custom change functions

  def log_adaptation_application(_changeset, result, _opts) do
    adaptation_type = result.adaptation_type
    adaptation_name = result.adaptation_name
    
    require Logger
    Logger.info("Adaptation applied: #{adaptation_name} (#{adaptation_type})")
    
    {:ok, result}
  end

  def log_adaptation_status_change(changeset, result, _opts) do
    action_name = changeset.action.name
    adaptation_name = result.adaptation_name
    new_status = result.adaptation_status
    
    require Logger
    Logger.info("Adaptation #{action_name}: #{adaptation_name} -> #{new_status}")
    
    {:ok, result}
  end

  # Helper functions for adaptation management

  @doc """
  Get recent adaptations for effectiveness review.
  """
  def get_recent_adaptations(hours_back \\ 24) do
    __MODULE__
    |> Ash.Query.filter(adaptation_age_hours <= hours_back)
    |> Ash.Query.filter(is_active: true)
    |> Ash.Query.sort(applied_at: :desc)
    |> Ash.read!()
  end

  @doc """
  Get adaptations needing validation.
  """
  def get_adaptations_needing_validation do
    __MODULE__
    |> Ash.Query.filter(needs_validation: true)
    |> Ash.Query.sort(applied_at: :asc)
    |> Ash.read!()
  end

  @doc """
  Get effective adaptations for replication analysis.
  """
  def get_effective_adaptations(effectiveness_threshold \\ 0.8) do
    __MODULE__
    |> Ash.Query.filter(adaptation_status: :validated)
    |> Ash.Query.filter(effectiveness_score > effectiveness_threshold)
    |> Ash.Query.sort(effectiveness_score: :desc)
    |> Ash.read!()
  end

  @doc """
  Get adaptation statistics and trend analysis.
  """
  def get_adaptation_analytics(days_back \\ 7) do
    recent_adaptations = __MODULE__
      |> Ash.Query.filter(adaptation_age_hours <= days_back * 24)
      |> Ash.read!()
    
    by_type = Enum.group_by(recent_adaptations, & &1.adaptation_type)
    by_status = Enum.group_by(recent_adaptations, & &1.adaptation_status)
    by_source = Enum.group_by(recent_adaptations, & &1.adaptation_source)
    
    %{
      total_adaptations: length(recent_adaptations),
      effective_adaptations: length(Enum.filter(recent_adaptations, & &1.is_effective)),
      active_adaptations: length(Enum.filter(recent_adaptations, & &1.is_active)),
      rollback_rate: calculate_rollback_rate(by_status),
      adaptation_frequency: length(recent_adaptations) / days_back,
      by_type: calculate_type_distribution(by_type),
      by_status: calculate_status_distribution(by_status),
      by_source: calculate_source_distribution(by_source),
      effectiveness_trends: analyze_effectiveness_trends(recent_adaptations),
      impact_analysis: analyze_adaptation_impacts(recent_adaptations)
    }
  end

  @doc """
  Find similar adaptations for pattern analysis.
  """
  def find_similar_adaptations(target_adaptation, similarity_threshold \\ 0.8) do
    all_adaptations = __MODULE__
      |> Ash.Query.filter(adaptation_type: target_adaptation.adaptation_type)
      |> Ash.Query.filter(id != target_adaptation.id)
      |> Ash.read!()
    
    similar_adaptations = Enum.filter(all_adaptations, fn adaptation ->
      similarity = calculate_adaptation_similarity(target_adaptation, adaptation)
      similarity >= similarity_threshold
    end)
    
    Enum.map(similar_adaptations, fn adaptation ->
      %{
        adaptation: adaptation,
        similarity_score: calculate_adaptation_similarity(target_adaptation, adaptation),
        effectiveness_comparison: compare_adaptation_effectiveness(target_adaptation, adaptation)
      }
    end)
  end

  @doc """
  Clean up old adaptation records based on retention policy.
  """
  def cleanup_old_adaptations(retention_days \\ 90) do
    old_adaptations = __MODULE__
      |> Ash.Query.filter(adaptation_age_hours > retention_days * 24)
      |> Ash.Query.filter(adaptation_status: [:deprecated, :rolled_back])
      |> Ash.read!()
    
    # Archive old adaptations
    Enum.each(old_adaptations, fn adaptation ->
      # Would implement actual archival logic
      Logger.debug("Archiving old adaptation: #{adaptation.adaptation_name}")
    end)
    
    {:ok, length(old_adaptations)}
  end

  # Private helper functions

  defp calculate_rollback_rate(adaptations_by_status) do
    total_adaptations = Enum.sum(Enum.map(adaptations_by_status, fn {_status, adaptations} -> 
      length(adaptations) 
    end))
    
    rolled_back_count = length(Map.get(adaptations_by_status, :rolled_back, []))
    
    if total_adaptations > 0 do
      rolled_back_count / total_adaptations
    else
      0.0
    end
  end

  defp calculate_type_distribution(adaptations_by_type) do
    Enum.map(adaptations_by_type, fn {type, adaptations} ->
      {type, length(adaptations)}
    end) |> Map.new()
  end

  defp calculate_status_distribution(adaptations_by_status) do
    Enum.map(adaptations_by_status, fn {status, adaptations} ->
      {status, length(adaptations)}
    end) |> Map.new()
  end

  defp calculate_source_distribution(adaptations_by_source) do
    Enum.map(adaptations_by_source, fn {source, adaptations} ->
      {source, length(adaptations)}
    end) |> Map.new()
  end

  defp analyze_effectiveness_trends(adaptations) when is_list(adaptations) do
    if length(adaptations) < 3 do
      %{trend: :insufficient_data, trend_strength: 0.0}
    else
      # Sort by application time and analyze effectiveness trend
      sorted_adaptations = Enum.sort_by(adaptations, & &1.applied_at)
      
      effectiveness_scores = Enum.map(sorted_adaptations, fn adaptation ->
        adaptation.effectiveness_score || 0.5
      end) |> Enum.filter(&(&1 > 0))
      
      if length(effectiveness_scores) < 3 do
        %{trend: :insufficient_data, trend_strength: 0.0}
      else
        trend_direction = calculate_trend_direction(effectiveness_scores)
        trend_strength = calculate_trend_strength(effectiveness_scores)
        
        %{
          trend: trend_direction,
          trend_strength: trend_strength,
          effectiveness_evolution: effectiveness_scores
        }
      end
    end
  end

  defp analyze_adaptation_impacts(adaptations) when is_list(adaptations) do
    # Analyze overall impact of adaptations
    validated_adaptations = Enum.filter(adaptations, fn adaptation ->
      adaptation.adaptation_status == :validated and not is_nil(adaptation.effectiveness_score)
    end)
    
    if Enum.empty?(validated_adaptations) do
      %{
        user_satisfaction_impact: 0.0,
        system_performance_impact: 0.0,
        cost_impact: 0.0,
        overall_impact: :neutral
      }
    else
      %{
        user_satisfaction_impact: calculate_average_impact(validated_adaptations, :user_satisfaction_impact),
        system_performance_impact: calculate_average_impact(validated_adaptations, :system_performance_impact),
        cost_impact: calculate_average_impact(validated_adaptations, :cost_impact),
        overall_impact: assess_overall_impact(validated_adaptations)
      }
    end
  end

  defp calculate_adaptation_similarity(adaptation1, adaptation2) do
    # Calculate similarity between two adaptations
    type_similarity = if adaptation1.adaptation_type == adaptation2.adaptation_type, do: 1.0, else: 0.0
    
    source_similarity = if adaptation1.adaptation_source == adaptation2.adaptation_source, do: 0.5, else: 0.0
    
    # Parameter similarity (simplified)
    parameter_similarity = calculate_parameter_similarity(
      adaptation1.adaptation_parameters, 
      adaptation2.adaptation_parameters
    )
    
    # Weighted average
    (type_similarity * 0.5) + (source_similarity * 0.2) + (parameter_similarity * 0.3)
  end

  defp compare_adaptation_effectiveness(adaptation1, adaptation2) do
    # Compare effectiveness of two similar adaptations
    effectiveness1 = adaptation1.effectiveness_score || 0.5
    effectiveness2 = adaptation2.effectiveness_score || 0.5
    
    %{
      effectiveness_difference: effectiveness1 - effectiveness2,
      better_adaptation: if(effectiveness1 > effectiveness2, do: adaptation1.id, else: adaptation2.id),
      confidence_comparison: compare_adaptation_confidence(adaptation1, adaptation2)
    }
  end

  defp calculate_parameter_similarity(params1, params2) when is_map(params1) and is_map(params2) do
    # Simple parameter similarity calculation
    common_keys = Map.keys(params1) ++ Map.keys(params2) |> Enum.uniq()
    
    if Enum.empty?(common_keys) do
      0.0
    else
      similarities = Enum.map(common_keys, fn key ->
        val1 = Map.get(params1, key)
        val2 = Map.get(params2, key)
        
        if val1 == val2 do
          1.0
        else
          0.0
        end
      end)
      
      Enum.sum(similarities) / length(similarities)
    end
  end

  defp calculate_parameter_similarity(_, _), do: 0.0

  defp calculate_trend_direction(values) when is_list(values) and length(values) > 2 do
    # Calculate trend direction using simple slope
    n = length(values)
    x_values = Enum.to_list(1..n)
    
    x_mean = Enum.sum(x_values) / n
    y_mean = Enum.sum(values) / n
    
    numerator = Enum.zip(x_values, values)
      |> Enum.reduce(0.0, fn {x, y}, acc -> acc + (x - x_mean) * (y - y_mean) end)
    
    denominator = Enum.reduce(x_values, 0.0, fn x, acc -> acc + :math.pow(x - x_mean, 2) end)
    
    slope = if denominator > 0, do: numerator / denominator, else: 0.0
    
    cond do
      slope > 0.05 -> :improving
      slope < -0.05 -> :declining
      true -> :stable
    end
  end

  defp calculate_trend_direction(_), do: :stable

  defp calculate_trend_strength(values) when is_list(values) and length(values) > 2 do
    # Calculate R-squared as trend strength indicator
    mean = Enum.sum(values) / length(values)
    variance = Enum.reduce(values, 0.0, fn val, acc -> 
      acc + :math.pow(val - mean, 2) 
    end) / length(values)
    
    # Simplified trend strength calculation
    min(1.0, variance * 2)
  end

  defp calculate_trend_strength(_), do: 0.0

  defp calculate_average_impact(adaptations, impact_field) when is_list(adaptations) do
    impacts = Enum.map(adaptations, fn adaptation ->
      Map.get(adaptation, impact_field, 0.0)
    end) |> Enum.filter(&is_number/1)
    
    if Enum.empty?(impacts) do
      0.0
    else
      Enum.sum(impacts) / length(impacts)
    end
  end

  defp assess_overall_impact(validated_adaptations) when is_list(validated_adaptations) do
    # Assess overall impact across all dimensions
    satisfaction_impact = calculate_average_impact(validated_adaptations, :user_satisfaction_impact)
    performance_impact = calculate_average_impact(validated_adaptations, :system_performance_impact)
    cost_impact = calculate_average_impact(validated_adaptations, :cost_impact)
    
    # Weighted assessment (positive is good for satisfaction/performance, negative is good for cost)
    overall_score = (satisfaction_impact * 0.4) + (performance_impact * 0.4) + (-cost_impact * 0.2)
    
    cond do
      overall_score > 0.15 -> :highly_positive
      overall_score > 0.05 -> :positive
      overall_score > -0.05 -> :neutral
      overall_score > -0.15 -> :negative
      true -> :highly_negative
    end
  end

  defp compare_adaptation_confidence(adaptation1, adaptation2) do
    conf1 = adaptation1.confidence_score
    conf2 = adaptation2.confidence_score
    
    %{
      confidence_difference: conf1 - conf2,
      higher_confidence_adaptation: if(conf1 > conf2, do: adaptation1.id, else: adaptation2.id)
    }
  end
end