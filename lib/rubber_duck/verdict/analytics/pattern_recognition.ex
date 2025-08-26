defmodule RubberDuck.Verdict.Analytics.PatternRecognition do
  @moduledoc """
  Ash resource for storing identified patterns and their effectiveness tracking.

  Persists machine learning-identified patterns from success analysis, failure detection,
  user preference profiling, and temporal trend analysis to enable pattern evolution
  tracking and continuous learning system improvement.
  """

  use Ash.Resource,
    domain: RubberDuck.Verdict,
    data_layer: AshPostgres.DataLayer

  import Ash.Expr
  require Ash.Query
  require Logger

  postgres do
    table "verdict_pattern_recognitions"
    repo RubberDuck.Repo
  end

  resource do
    description "Machine learning identified patterns for continuous system improvement"
  end

  code_interface do
    define :create
    define :validate_pattern
    define :apply_pattern
    define :update_effectiveness
    define :deprecate_pattern
    define :archive_pattern
    define :read
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :pattern_type,
        :pattern_name,
        :pattern_description,
        :pattern_data,
        :confidence_score,
        :pattern_strength,
        :data_points_used,
        :statistical_significance,
        :actionable_insights,
        :recommended_actions,
        :application_contexts,
        :learning_priority,
        :user_segment_applicability,
        :temporal_applicability,
        :identified_by
      ]

      change set_attribute(:pattern_status, :identified)
    end

    update :validate_pattern do
      accept [:validation_results, :effectiveness_score]
      require_atomic? false

      change set_attribute(:pattern_status, :validated)
      change set_attribute(:last_validated, &DateTime.utc_now/0)
    end

    update :apply_pattern do
      require_atomic? false

      change set_attribute(:pattern_status, :applied)
      change set_attribute(:last_applied, &DateTime.utc_now/0)
      change increment(:application_count, amount: 1)
    end

    update :update_effectiveness do
      accept [:effectiveness_score, :success_rate, :evolution_history]
      require_atomic? false
    end

    update :deprecate_pattern do
      require_atomic? false

      change set_attribute(:pattern_status, :deprecated)
    end

    update :archive_pattern do
      require_atomic? false

      change set_attribute(:pattern_status, :archived)
    end
  end

  preparations do
    prepare build(sort: [confidence_score: :desc, pattern_strength: :desc])
  end

  changes do
    change before_action(&set_pattern_defaults/2) do
      on [:create]
    end

    change after_action(&log_pattern_identification/3) do
      on [:create]
    end

    change after_action(&update_evolution_history/3) do
      on [:update]
    end
  end

  validations do
    validate present([:pattern_type, :pattern_name, :confidence_score, :data_points_used])

    validate numericality(:confidence_score,
               greater_than_or_equal_to: 0.0,
               less_than_or_equal_to: 1.0
             )

    validate numericality(:pattern_strength,
               greater_than_or_equal_to: 0.0,
               less_than_or_equal_to: 1.0
             )

    validate numericality(:data_points_used, greater_than: 0)
  end

  attributes do
    uuid_primary_key :id

    attribute :pattern_type, :atom do
      description "Type of pattern identified"

      constraints one_of: [
                    :success_patterns,
                    :failure_modes,
                    :user_preferences,
                    :temporal_trends,
                    :judge_performance,
                    :system_optimization,
                    :bias_patterns,
                    :coordination_patterns
                  ]

      allow_nil? false
    end

    attribute :pattern_name, :string do
      description "Human-readable name for the pattern"
      allow_nil? false
    end

    attribute :pattern_description, :string do
      description "Detailed description of the identified pattern"
    end

    attribute :pattern_data, :map do
      description "Structured pattern data and characteristics"
      default %{}
    end

    attribute :confidence_score, :decimal do
      description "Confidence in the pattern identification (0.0 to 1.0)"
      constraints min: 0.0, max: 1.0
      allow_nil? false
    end

    attribute :pattern_strength, :decimal do
      description "Strength/distinctiveness of the pattern (0.0 to 1.0)"
      constraints min: 0.0, max: 1.0
      default 0.5
    end

    attribute :data_points_used, :integer do
      description "Number of data points used to identify this pattern"
      constraints min: 1
      allow_nil? false
    end

    attribute :statistical_significance, :decimal do
      description "Statistical significance of the pattern (p-value)"
      constraints min: 0.0, max: 1.0
    end

    attribute :actionable_insights, :map do
      description "Extracted actionable insights from this pattern"
      default %{}
    end

    attribute :recommended_actions, {:array, :string} do
      description "Recommended actions based on this pattern"
      default []
    end

    attribute :effectiveness_score, :decimal do
      description "Measured effectiveness of applying this pattern (0.0 to 1.0)"
      constraints min: 0.0, max: 1.0
    end

    attribute :application_count, :integer do
      description "Number of times this pattern has been applied"
      default 0
    end

    attribute :success_rate, :decimal do
      description "Success rate when this pattern is applied (0.0 to 1.0)"
      constraints min: 0.0, max: 1.0
    end

    attribute :pattern_status, :atom do
      description "Current status of the pattern"
      constraints one_of: [:identified, :validated, :applied, :deprecated, :archived]
      default :identified
    end

    attribute :validation_results, :map do
      description "Results from pattern validation testing"
      default %{}
    end

    attribute :application_contexts, {:array, :string} do
      description "Contexts where this pattern is most effective"
      default []
    end

    attribute :evolution_history, :map do
      description "Historical evolution of the pattern over time"
      default %{}
    end

    attribute :learning_priority, :atom do
      description "Priority level for learning from this pattern"
      constraints one_of: [:critical, :high, :medium, :low, :background]
      default :medium
    end

    attribute :user_segment_applicability, {:array, :atom} do
      description "User segments where this pattern applies"
      default []
    end

    attribute :temporal_applicability, :map do
      description "Temporal contexts where pattern is most effective"
      default %{}
    end

    attribute :identified_by, :string do
      description "ML analyzer that identified this pattern"
    end

    attribute :identified_at, :utc_datetime_usec do
      description "When this pattern was first identified"
      default &DateTime.utc_now/0
    end

    attribute :last_validated, :utc_datetime_usec do
      description "When this pattern was last validated"
    end

    attribute :last_applied, :utc_datetime_usec do
      description "When this pattern was last applied"
    end

    timestamps()
  end

  relationships do
    # Would add relationships to other learning resources when implemented
  end

  calculations do
    calculate :is_high_confidence, :boolean, expr(confidence_score > 0.8)
    calculate :is_validated, :boolean, expr(pattern_status in [:validated, :applied])
    calculate :is_effective, :boolean, expr(effectiveness_score > 0.7)

    calculate :pattern_age_days,
              :integer,
              expr(fragment("EXTRACT(DAY FROM (? - ?))", now(), identified_at))

    calculate :days_since_last_application,
              :integer,
              expr(fragment("EXTRACT(DAY FROM (? - ?))", now(), last_applied))

    calculate :validation_status,
              :string,
              expr(
                cond do
                  is_nil(last_validated) -> "unvalidated"
                  pattern_status == :validated -> "validated"
                  pattern_status == :applied -> "in_use"
                  true -> "unknown"
                end
              )
  end

  # Custom change functions

  def set_pattern_defaults(changeset, _opts) do
    pattern_type = Ash.Changeset.get_attribute(changeset, :pattern_type)

    # Set default learning priority based on pattern type
    default_priority =
      case pattern_type do
        :failure_modes -> :high
        :bias_patterns -> :critical
        :success_patterns -> :medium
        _ -> :medium
      end

    changeset =
      if is_nil(Ash.Changeset.get_attribute(changeset, :learning_priority)) do
        Ash.Changeset.change_attribute(changeset, :learning_priority, default_priority)
      else
        changeset
      end

    # Set default temporal applicability
    if is_nil(Ash.Changeset.get_attribute(changeset, :temporal_applicability)) do
      Ash.Changeset.change_attribute(changeset, :temporal_applicability, %{
        applicable_hours: [],
        applicable_days: [],
        seasonal_factor: :none
      })
    else
      changeset
    end
  end

  def log_pattern_identification(_changeset, result, _opts) do
    pattern_type = result.pattern_type
    confidence = result.confidence_score
    data_points = result.data_points_used

    require Logger

    Logger.info(
      "Pattern identified: #{pattern_type} with confidence #{confidence} from #{data_points} data points"
    )

    {:ok, result}
  end

  def update_evolution_history(changeset, result, _opts) do
    action_name = changeset.action.name
    current_history = result.evolution_history || %{}

    evolution_entry = %{
      action: action_name,
      timestamp: DateTime.utc_now(),
      previous_status: changeset.data.pattern_status,
      new_status: result.pattern_status
    }

    updated_history =
      Map.put(current_history, DateTime.to_iso8601(DateTime.utc_now()), evolution_entry)

    # Update the result with new evolution history
    updated_result = %{result | evolution_history: updated_history}

    {:ok, updated_result}
  end

  # Helper functions for pattern management

  @doc """
  Get high-confidence patterns for immediate application.
  """
  def get_high_confidence_patterns(pattern_type \\ nil) do
    query =
      __MODULE__
      |> Ash.Query.filter(is_high_confidence: true)
      |> Ash.Query.filter(pattern_status: [:validated, :applied])
      |> Ash.Query.sort(confidence_score: :desc, pattern_strength: :desc)

    query =
      if pattern_type do
        Ash.Query.filter(query, pattern_type: pattern_type)
      else
        query
      end

    query |> Ash.read!()
  end

  @doc """
  Get patterns ready for validation testing.
  """
  def get_patterns_for_validation do
    __MODULE__
    |> Ash.Query.filter(pattern_status: :identified)
    |> Ash.Query.filter(confidence_score > 0.7)
    |> Ash.Query.sort(learning_priority: :asc, confidence_score: :desc)
    |> Ash.read!()
  end

  @doc """
  Get patterns that have been successfully applied.
  """
  def get_effective_patterns(effectiveness_threshold \\ 0.7) do
    __MODULE__
    |> Ash.Query.filter(pattern_status: :applied)
    |> Ash.Query.filter(effectiveness_score > effectiveness_threshold)
    |> Ash.Query.filter(application_count > 0)
    |> Ash.Query.sort(effectiveness_score: :desc)
    |> Ash.read!()
  end

  @doc """
  Get pattern analytics and usage statistics.
  """
  def get_pattern_analytics(days_back \\ 30) do
    recent_patterns =
      __MODULE__
      |> Ash.Query.filter(pattern_age_days <= days_back)
      |> Ash.read!()

    by_type = Enum.group_by(recent_patterns, & &1.pattern_type)
    by_status = Enum.group_by(recent_patterns, & &1.pattern_status)

    %{
      total_patterns: length(recent_patterns),
      high_confidence_count: Enum.count(recent_patterns, & &1.is_high_confidence),
      validated_count: Enum.count(recent_patterns, & &1.is_validated),
      effective_count: Enum.count(recent_patterns, & &1.is_effective),
      by_type: calculate_type_distribution(by_type),
      by_status: calculate_status_distribution(by_status),
      average_confidence: calculate_average_confidence(recent_patterns),
      average_effectiveness: calculate_average_effectiveness(recent_patterns),
      application_statistics: calculate_application_statistics(recent_patterns)
    }
  end

  @doc """
  Clean up deprecated and low-effectiveness patterns.
  """
  def cleanup_ineffective_patterns(effectiveness_threshold \\ 0.3) do
    # Find patterns that should be deprecated
    ineffective_patterns =
      __MODULE__
      |> Ash.Query.filter(pattern_status: :applied)
      |> Ash.Query.filter(effectiveness_score < effectiveness_threshold)
      # Only deprecate if tried multiple times
      |> Ash.Query.filter(application_count > 5)
      |> Ash.read!()

    # Deprecate ineffective patterns
    Enum.each(ineffective_patterns, fn pattern ->
      deprecate_pattern(pattern)
    end)

    Logger.info("Deprecated #{length(ineffective_patterns)} ineffective patterns")
    {:ok, length(ineffective_patterns)}
  end

  @doc """
  Find similar patterns for cross-validation and consolidation.
  """
  def find_similar_patterns(target_pattern, similarity_threshold \\ 0.8) do
    all_patterns =
      __MODULE__
      |> Ash.Query.filter(pattern_type: target_pattern.pattern_type)
      |> Ash.Query.filter(id != target_pattern.id)
      |> Ash.read!()

    similar_patterns =
      Enum.filter(all_patterns, fn pattern ->
        similarity = calculate_pattern_similarity(target_pattern, pattern)
        similarity >= similarity_threshold
      end)

    Enum.map(similar_patterns, fn pattern ->
      %{
        pattern: pattern,
        similarity_score: calculate_pattern_similarity(target_pattern, pattern),
        consolidation_potential: assess_consolidation_potential(target_pattern, pattern)
      }
    end)
  end

  # Private helper functions

  defp calculate_type_distribution(patterns_by_type) do
    Enum.map(patterns_by_type, fn {type, patterns} ->
      {type, length(patterns)}
    end)
    |> Map.new()
  end

  defp calculate_status_distribution(patterns_by_status) do
    Enum.map(patterns_by_status, fn {status, patterns} ->
      {status, length(patterns)}
    end)
    |> Map.new()
  end

  defp calculate_average_confidence([]), do: 0.0

  defp calculate_average_confidence(patterns) do
    confidences = Enum.map(patterns, & &1.confidence_score)
    Enum.sum(confidences) / length(confidences)
  end

  defp calculate_average_effectiveness([]), do: 0.0

  defp calculate_average_effectiveness(patterns) do
    effectiveness_scores =
      Enum.map(patterns, fn pattern ->
        Map.get(pattern, :effectiveness_score, 0.0)
      end)
      |> Enum.filter(fn score -> score > 0 end)

    if Enum.empty?(effectiveness_scores) do
      0.0
    else
      Enum.sum(effectiveness_scores) / length(effectiveness_scores)
    end
  end

  defp calculate_application_statistics(patterns) do
    applied_patterns =
      Enum.filter(patterns, fn pattern ->
        pattern.pattern_status in [:applied] and pattern.application_count > 0
      end)

    if Enum.empty?(applied_patterns) do
      %{
        total_applications: 0,
        average_applications_per_pattern: 0.0,
        most_applied_pattern_type: :none
      }
    else
      total_applications = Enum.sum(Enum.map(applied_patterns, & &1.application_count))
      average_applications = total_applications / length(applied_patterns)

      most_applied_type =
        applied_patterns
        |> Enum.group_by(& &1.pattern_type)
        |> Enum.max_by(fn {_type, patterns} ->
          Enum.sum(Enum.map(patterns, & &1.application_count))
        end)
        |> elem(0)

      %{
        total_applications: total_applications,
        average_applications_per_pattern: average_applications,
        most_applied_pattern_type: most_applied_type
      }
    end
  end

  defp calculate_pattern_similarity(pattern1, pattern2) do
    # Calculate similarity between two patterns
    type_similarity = if pattern1.pattern_type == pattern2.pattern_type, do: 1.0, else: 0.0

    confidence_similarity = 1.0 - abs(pattern1.confidence_score - pattern2.confidence_score)
    strength_similarity = 1.0 - abs(pattern1.pattern_strength - pattern2.pattern_strength)

    # Data similarity (simplified)
    data_similarity = calculate_data_similarity(pattern1.pattern_data, pattern2.pattern_data)

    # Weighted average
    type_similarity * 0.4 + confidence_similarity * 0.2 + strength_similarity * 0.2 +
      data_similarity * 0.2
  end

  defp calculate_data_similarity(data1, data2) when is_map(data1) and is_map(data2) do
    # Simplified data similarity calculation
    common_keys = (Map.keys(data1) ++ Map.keys(data2)) |> Enum.uniq()

    if Enum.empty?(common_keys) do
      0.0
    else
      similarities =
        Enum.map(common_keys, fn key ->
          val1 = Map.get(data1, key)
          val2 = Map.get(data2, key)

          if val1 == val2 do
            1.0
          else
            0.0
          end
        end)

      Enum.sum(similarities) / length(similarities)
    end
  end

  defp calculate_data_similarity(_, _), do: 0.0

  defp assess_consolidation_potential(pattern1, pattern2) do
    similarity = calculate_pattern_similarity(pattern1, pattern2)

    case similarity do
      score when score > 0.9 -> :high_consolidation_potential
      score when score > 0.7 -> :medium_consolidation_potential
      score when score > 0.5 -> :low_consolidation_potential
      _ -> :no_consolidation_potential
    end
  end
end
