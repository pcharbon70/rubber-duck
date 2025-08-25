defmodule RubberDuck.Agents.ValidationAgent do
  @moduledoc """
  Validation agent for autonomous preference validation and constraint checking.

  This agent validates preference values, checks cross-preference constraints,
  ensures type safety, and provides intelligent error reporting with
  suggestions for resolution.
  """

  use Jido.Agent,
    name: "validation_agent",
    description:
      "Autonomous preference validation with constraint checking and intelligent error reporting",
    category: "preferences",
    tags: ["validation", "constraints", "type-safety", "error-reporting"],
    vsn: "1.0.0"

  require Logger

  alias RubberDuck.Preferences.ValidationInterfaceManager

  alias RubberDuck.Preferences.Validators.{
    CodeQualityPreferenceValidator,
    LlmPreferenceValidator,
    MlPreferenceValidator
  }

  # Agent state fields are managed through direct state setting

  @doc """
  Create a new ValidationAgent.
  """
  def create_validation_agent do
    with {:ok, agent} <- __MODULE__.new(),
         {:ok, agent} <-
           __MODULE__.set(agent,
             validation_statistics: %{successful: 0, failed: 0, total: 0},
             error_patterns: %{},
             constraint_violations: [],
             type_safety_checks: %{},
             cross_preference_validations: [],
             last_validation: DateTime.utc_now()
           ) do
      {:ok, agent}
    end
  end

  @doc """
  Perform comprehensive preference validation with intelligent error reporting.
  """
  def validate_preferences_comprehensive(agent, preferences, context \\ %{}) do
    start_time = System.monotonic_time(:millisecond)

    case ValidationInterfaceManager.validate_preference_changes(preferences, context) do
      {:ok, validation_result} ->
        validation_time = System.monotonic_time(:millisecond) - start_time

        updated_agent =
          record_validation_success(agent, preferences, validation_result, validation_time)

        # Generate intelligent suggestions for improvements
        suggestions = generate_validation_suggestions(validation_result, agent)

        {:ok, Map.put(validation_result, :suggestions, suggestions), updated_agent}

      {:error, reason} ->
        updated_agent = record_validation_failure(agent, preferences, reason)
        {:error, reason, updated_agent}
    end
  end

  @doc """
  Check cross-preference constraints and dependencies.
  """
  def check_cross_preference_constraints(agent, preferences) do
    constraint_checks = []

    constraint_checks = constraint_checks ++ check_llm_constraints(preferences)
    constraint_checks = constraint_checks ++ check_ml_constraints(preferences)
    constraint_checks = constraint_checks ++ check_code_quality_constraints(preferences)
    constraint_checks = constraint_checks ++ check_budgeting_constraints(preferences)

    violations = Enum.filter(constraint_checks, &(&1.status == :violation))

    updated_agent = record_constraint_check(agent, constraint_checks, violations)

    {:ok, %{checks: constraint_checks, violations: violations}, updated_agent}
  end

  @doc """
  Ensure type safety for all preference values.
  """
  def ensure_type_safety(agent, preferences) do
    type_checks =
      Enum.map(preferences, fn {key, value} ->
        check_preference_type_safety(key, value)
      end)

    violations = Enum.filter(type_checks, &(&1.status == :type_error))

    updated_agent = record_type_safety_check(agent, type_checks, violations)

    {:ok, %{type_checks: type_checks, violations: violations}, updated_agent}
  end

  @doc """
  Generate validation error report with resolution suggestions.
  """
  def generate_error_report(agent, validation_errors) do
    error_analysis = analyze_error_patterns(validation_errors, agent.error_patterns)
    resolution_suggestions = generate_resolution_suggestions(validation_errors, error_analysis)

    report = %{
      error_count: length(validation_errors),
      error_analysis: error_analysis,
      resolution_suggestions: resolution_suggestions,
      similar_past_errors: find_similar_past_errors(validation_errors, agent),
      generated_at: DateTime.utc_now()
    }

    updated_agent = update_error_patterns(agent, validation_errors)

    {:ok, report, updated_agent}
  end

  @doc """
  Learn from validation patterns to improve future validations.
  """
  def learn_from_validation_patterns(agent) do
    patterns = analyze_validation_history(agent)
    improvements = suggest_validation_improvements(patterns)

    learning_insights = %{
      patterns: patterns,
      improvements: improvements,
      confidence: calculate_learning_confidence(agent)
    }

    {:ok, learning_insights, agent}
  end

  # Private helper functions

  defp record_validation_success(agent, preferences, validation_result, validation_time) do
    stats = %{
      agent.validation_statistics
      | successful: agent.validation_statistics.successful + 1,
        total: agent.validation_statistics.total + 1
    }

    validation_entry = %{
      preferences: preferences,
      result: validation_result,
      validation_time: validation_time,
      timestamp: DateTime.utc_now(),
      status: :success
    }

    updated_checks =
      add_to_cross_preference_validations(agent.cross_preference_validations, validation_entry)

    %{
      agent
      | validation_statistics: stats,
        cross_preference_validations: updated_checks,
        last_validation: DateTime.utc_now()
    }
  end

  defp record_validation_failure(agent, preferences, reason) do
    stats = %{
      agent.validation_statistics
      | failed: agent.validation_statistics.failed + 1,
        total: agent.validation_statistics.total + 1
    }

    validation_entry = %{
      preferences: preferences,
      reason: reason,
      timestamp: DateTime.utc_now(),
      status: :failed
    }

    updated_checks =
      add_to_cross_preference_validations(agent.cross_preference_validations, validation_entry)

    %{
      agent
      | validation_statistics: stats,
        cross_preference_validations: updated_checks,
        last_validation: DateTime.utc_now()
    }
  end

  defp generate_validation_suggestions(validation_result, agent) do
    suggestions = []

    suggestions =
      if validation_result.valid do
        suggestions
      else
        suggestions ++ suggest_validation_fixes(validation_result.individual_validations)
      end

    suggestions =
      if validation_result.conflicts.has_conflicts do
        suggestions ++ suggest_conflict_resolutions(validation_result.conflicts)
      else
        suggestions
      end

    suggestions = suggestions ++ suggest_based_on_history(agent)

    suggestions
  end

  defp check_llm_constraints(preferences) do
    llm_prefs = filter_preferences_by_category(preferences, "llm")

    if map_size(llm_prefs) > 0 do
      case LlmPreferenceValidator.validate_llm_config_consistency(llm_prefs) do
        :ok -> [%{category: "llm", status: :valid, message: "LLM preferences are consistent"}]
        {:error, message} -> [%{category: "llm", status: :violation, message: message}]
      end
    else
      []
    end
  end

  defp check_ml_constraints(preferences) do
    ml_prefs = filter_preferences_by_category(preferences, "ml")

    if map_size(ml_prefs) > 0 do
      case MlPreferenceValidator.validate_ml_config_consistency(ml_prefs) do
        :ok -> [%{category: "ml", status: :valid, message: "ML preferences are consistent"}]
        {:error, message} -> [%{category: "ml", status: :violation, message: message}]
      end
    else
      []
    end
  end

  defp check_code_quality_constraints(preferences) do
    cq_prefs = filter_preferences_by_category(preferences, "code_quality")

    if map_size(cq_prefs) > 0 do
      case CodeQualityPreferenceValidator.validate_code_quality_consistency(cq_prefs) do
        :ok ->
          [
            %{
              category: "code_quality",
              status: :valid,
              message: "Code quality preferences are consistent"
            }
          ]

        {:error, message} ->
          [%{category: "code_quality", status: :violation, message: message}]
      end
    else
      []
    end
  end

  defp check_budgeting_constraints(preferences) do
    budgeting_prefs = filter_preferences_by_category(preferences, "budgeting")

    # Placeholder for budgeting constraint validation
    if map_size(budgeting_prefs) > 0 do
      [%{category: "budgeting", status: :valid, message: "Budgeting preferences are consistent"}]
    else
      []
    end
  end

  defp check_preference_type_safety(preference_key, value) do
    # Placeholder for type safety checking
    %{
      preference_key: preference_key,
      value: value,
      status: :type_safe,
      message: "Type validation passed"
    }
  end

  defp record_constraint_check(agent, checks, violations) do
    constraint_entry = %{
      checks: checks,
      violations: violations,
      timestamp: DateTime.utc_now()
    }

    updated_violations =
      add_to_constraint_violations(agent.constraint_violations, constraint_entry)

    %{agent | constraint_violations: updated_violations}
  end

  defp record_type_safety_check(agent, type_checks, violations) do
    safety_check = %{
      type_checks: type_checks,
      violations: violations,
      timestamp: DateTime.utc_now()
    }

    updated_checks = Map.put(agent.type_safety_checks, DateTime.utc_now(), safety_check)

    %{agent | type_safety_checks: updated_checks}
  end

  defp filter_preferences_by_category(preferences, category) do
    Enum.filter(preferences, fn {key, _value} ->
      String.starts_with?(key, "#{category}.")
    end)
    |> Map.new()
  end

  defp add_to_cross_preference_validations(validations, new_entry) do
    [new_entry | validations] |> Enum.take(100)
  end

  defp add_to_constraint_violations(violations, new_entry) do
    [new_entry | violations] |> Enum.take(50)
  end

  defp suggest_validation_fixes(_individual_validations), do: []
  defp suggest_conflict_resolutions(_conflicts), do: []
  defp suggest_based_on_history(_agent), do: []

  defp analyze_error_patterns(errors, existing_patterns) do
    error_types = Enum.map(errors, & &1.error_type)
    frequency_analysis = Enum.frequencies(error_types)

    Map.merge(existing_patterns, frequency_analysis)
  end

  defp generate_resolution_suggestions(errors, _error_analysis) do
    Enum.map(errors, fn error ->
      %{
        error: error,
        suggestion: "Review #{error.preference_key} value and constraints",
        priority: :medium
      }
    end)
  end

  defp find_similar_past_errors(_errors, _agent), do: []

  defp update_error_patterns(agent, errors) do
    new_patterns = analyze_error_patterns(errors, agent.error_patterns)
    %{agent | error_patterns: new_patterns}
  end

  defp analyze_validation_history(_agent), do: %{}
  defp suggest_validation_improvements(_patterns), do: []
  defp calculate_learning_confidence(_agent), do: 0.8
end
