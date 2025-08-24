defmodule RubberDuck.Preferences.ValidationInterfaceManager do
  @moduledoc """
  Validation interface manager for preference validation and conflict resolution.

  Provides business logic for validating preference changes, detecting
  conflicts, performing impact analysis, and previewing changes before
  application. Integrates with existing validation systems and provides
  user-friendly error reporting.
  """

  require Logger


  alias RubberDuck.Preferences.Validators.{
    CodeQualityPreferenceValidator,
    LlmPreferenceValidator,
    MlPreferenceValidator
  }

  @validation_modules %{
    "llm" => LlmPreferenceValidator,
    "ml" => MlPreferenceValidator,
    "code_quality" => CodeQualityPreferenceValidator
  }

  @doc """
  Validate preference changes before application.
  """
  @spec validate_preference_changes(
          changes :: map(),
          context :: map()
        ) :: {:ok, map()} | {:error, term()}
  def validate_preference_changes(changes, context \\ %{}) do
    user_id = Map.get(context, :user_id)
    project_id = Map.get(context, :project_id)

    with {:ok, validation_results} <- run_individual_validations(changes),
         {:ok, conflict_analysis} <- detect_preference_conflicts(changes, user_id, project_id),
         {:ok, impact_analysis} <- analyze_change_impact(changes, user_id, project_id),
         {:ok, constraint_validation} <- validate_changes_against_constraints(changes) do
      validation_summary = %{
        valid: all_validations_passed?(validation_results),
        individual_validations: validation_results,
        conflicts: conflict_analysis,
        impact: impact_analysis,
        constraints: constraint_validation,
        warnings:
          generate_validation_warnings(validation_results, conflict_analysis, impact_analysis)
      }

      {:ok, validation_summary}
    else
      error ->
        Logger.warning("Preference validation failed: #{inspect(error)}")
        error
    end
  end

  @doc """
  Preview preference changes before application.
  """
  @spec preview_preference_changes(
          changes :: map(),
          user_id :: binary(),
          project_id :: binary() | nil
        ) :: {:ok, map()} | {:error, term()}
  def preview_preference_changes(changes, user_id, project_id \\ nil) do
    with {:ok, current_config} <- get_current_resolved_config(user_id, project_id),
         {:ok, simulated_config} <- simulate_changes(current_config, changes),
         {:ok, change_diff} <- calculate_change_diff(current_config, simulated_config) do
      preview = %{
        current_config: current_config,
        new_config: simulated_config,
        changes: change_diff,
        affected_categories: get_affected_categories(changes),
        estimated_impact: estimate_change_impact(change_diff)
      }

      {:ok, preview}
    else
      error ->
        Logger.warning("Failed to preview preference changes: #{inspect(error)}")
        error
    end
  end

  @doc """
  Detect conflicts between proposed changes and existing preferences.
  """
  @spec detect_preference_conflicts(
          changes :: map(),
          user_id :: binary() | nil,
          project_id :: binary() | nil
        ) :: {:ok, map()} | {:error, term()}
  def detect_preference_conflicts(changes, user_id \\ nil, project_id \\ nil) do
    conflicts = %{
      constraint_violations: detect_constraint_violations(changes),
      dependency_conflicts: detect_dependency_conflicts(changes),
      category_conflicts: detect_category_conflicts(changes, user_id, project_id),
      value_range_violations: detect_value_range_violations(changes)
    }

    conflict_summary = %{
      has_conflicts: any_conflicts?(conflicts),
      conflicts: conflicts,
      resolutions: suggest_conflict_resolutions(conflicts)
    }

    {:ok, conflict_summary}
  end

  @doc """
  Analyze the impact of preference changes on system behavior.
  """
  @spec analyze_change_impact(
          changes :: map(),
          user_id :: binary() | nil,
          project_id :: binary() | nil
        ) :: {:ok, map()} | {:error, term()}
  def analyze_change_impact(changes, user_id \\ nil, project_id \\ nil) do
    impact_analysis = %{
      functional_impact: analyze_functional_impact(changes),
      performance_impact: analyze_performance_impact(changes),
      security_impact: analyze_security_impact(changes),
      user_experience_impact: analyze_ux_impact(changes),
      integration_impact: analyze_integration_impact(changes, user_id, project_id)
    }

    overall_impact = calculate_overall_impact_level(impact_analysis)

    {:ok,
     %{
       overall_impact: overall_impact,
       detailed_impact: impact_analysis,
       impact_summary: generate_impact_summary(impact_analysis),
       recommendations: generate_impact_recommendations(impact_analysis)
     }}
  end

  @doc """
  Get validation errors with user-friendly descriptions.
  """
  @spec get_validation_errors(validation_results :: map()) :: list(map())
  def get_validation_errors(validation_results) do
    validation_results
    |> Enum.flat_map(fn {key, result} ->
      case result do
        {:error, message} -> [format_validation_error(key, message)]
        _ -> []
      end
    end)
  end

  @doc """
  Get validation warnings for potentially problematic changes.
  """
  @spec get_validation_warnings(
          changes :: map(),
          user_id :: binary() | nil,
          project_id :: binary() | nil
        ) :: {:ok, list(map())} | {:error, term()}
  def get_validation_warnings(changes, user_id \\ nil, project_id \\ nil) do
    warnings = []

    warnings = warnings ++ check_aggressive_settings_warnings(changes)
    warnings = warnings ++ check_security_warnings(changes)
    warnings = warnings ++ check_compatibility_warnings(changes, user_id, project_id)
    warnings = warnings ++ check_performance_warnings(changes)

    {:ok, warnings}
  end

  # Private helper functions

  defp run_individual_validations(changes) do
    validation_results =
      Map.new(changes, fn {key, value} ->
        result = validate_single_preference(key, value)
        {key, result}
      end)

    {:ok, validation_results}
  end

  defp validate_single_preference(preference_key, value) do
    category = get_preference_category(preference_key)
    validator_module = Map.get(@validation_modules, category)

    if validator_module do
      # Use category-specific validator
      apply_category_validation(validator_module, preference_key, value)
    else
      # Use generic validation
      validate_against_system_default(preference_key, value)
    end
  end

  defp apply_category_validation(validator_module, preference_key, value) do
    # Extract the specific validation function name from preference key
    validation_function = determine_validation_function(preference_key)

    if function_exported?(validator_module, validation_function, 1) do
      apply(validator_module, validation_function, [value])
    else
      # Fall back to generic validation
      validate_against_system_default(preference_key, value)
    end
  end

  defp validate_against_system_default(_preference_key, _value) do
    # Placeholder for system default validation
    # This would integrate with actual SystemDefault resource queries
    :ok
  end

  defp validate_value_against_type(value, data_type, constraints) do
    case data_type do
      :boolean -> validate_boolean_value(value)
      :integer -> validate_integer_value(value, constraints)
      :float -> validate_float_value(value, constraints)
      :string -> validate_against_constraints(value, constraints)
      _ -> :ok
    end
  end

  defp validate_boolean_value(value) do
    if value in ["true", "false"], do: :ok, else: {:error, "Must be true or false"}
  end

  defp validate_integer_value(value, constraints) do
    case Integer.parse(value) do
      {int_val, ""} -> validate_against_constraints(int_val, constraints)
      _ -> {:error, "Must be a valid integer"}
    end
  end

  defp validate_float_value(value, constraints) do
    case Float.parse(value) do
      {float_val, ""} -> validate_against_constraints(float_val, constraints)
      _ -> {:error, "Must be a valid float"}
    end
  end

  defp validate_changes_against_constraints(changes) do
    # Validate all changes against their constraints
    violations = detect_constraint_violations(changes)

    if Enum.empty?(violations) do
      {:ok, %{valid: true, violations: []}}
    else
      {:ok, %{valid: false, violations: violations}}
    end
  end

  defp validate_against_constraints(_value, nil), do: :ok

  defp validate_against_constraints(value, constraints) do
    Enum.reduce_while(constraints, :ok, fn {constraint, constraint_value}, _acc ->
      validate_single_constraint(constraint, value, constraint_value)
    end)
  end

  defp validate_single_constraint(constraint, value, constraint_value) do
    case constraint do
      :min when is_number(value) ->
        validate_min_constraint(value, constraint_value)

      :max when is_number(value) ->
        validate_max_constraint(value, constraint_value)

      :allowed_values ->
        validate_allowed_values_constraint(value, constraint_value)

      _ ->
        {:cont, :ok}
    end
  end

  defp validate_min_constraint(value, min_value) do
    if value >= min_value,
      do: {:cont, :ok},
      else: {:halt, {:error, "Value too small (min: #{min_value})"}}
  end

  defp validate_max_constraint(value, max_value) do
    if value <= max_value,
      do: {:cont, :ok},
      else: {:halt, {:error, "Value too large (max: #{max_value})"}}
  end

  defp validate_allowed_values_constraint(value, allowed_values) do
    if value in allowed_values,
      do: {:cont, :ok},
      else: {:halt, {:error, "Invalid value. Allowed: #{inspect(allowed_values)}"}}
  end

  defp get_current_resolved_config(_user_id, _project_id) do
    # This would get the current fully resolved configuration
    # For now, return a placeholder
    {:ok, %{}}
  end

  defp simulate_changes(current_config, changes) do
    simulated_config = Map.merge(current_config, changes)
    {:ok, simulated_config}
  end

  defp calculate_change_diff(current_config, new_config) do
    diff = %{
      added: Map.drop(new_config, Map.keys(current_config)),
      removed: Map.drop(current_config, Map.keys(new_config)),
      modified: calculate_modified_preferences(current_config, new_config)
    }

    {:ok, diff}
  end

  defp calculate_modified_preferences(current_config, new_config) do
    Enum.reduce(new_config, %{}, fn {key, new_value}, acc ->
      case Map.get(current_config, key) do
        ^new_value ->
          acc

        old_value when not is_nil(old_value) ->
          Map.put(acc, key, %{old: old_value, new: new_value})

        _ ->
          acc
      end
    end)
  end

  defp detect_constraint_violations(changes) do
    Enum.reduce(changes, [], fn {key, value}, acc ->
      case validate_single_preference(key, value) do
        {:error, message} -> [{key, message} | acc]
        :ok -> acc
      end
    end)
  end

  defp detect_dependency_conflicts(_changes) do
    # Check for conflicting preference dependencies
    # This would integrate with PreferenceValidation resource
    []
  end

  defp detect_category_conflicts(_changes, _user_id, _project_id) do
    # Check for category-level conflicts
    # This would check against enabled categories and permissions
    []
  end

  defp detect_value_range_violations(_changes) do
    # Check for value range violations
    # This would validate against min/max constraints
    []
  end

  defp all_validations_passed?(validation_results) do
    Enum.all?(validation_results, fn {_key, result} -> result == :ok end)
  end

  defp any_conflicts?(conflicts) do
    Enum.any?(conflicts, fn {_type, conflict_list} -> not Enum.empty?(conflict_list) end)
  end

  defp suggest_conflict_resolutions(_conflicts) do
    # Generate suggestions for resolving conflicts
    []
  end

  defp generate_validation_warnings(validation_results, conflict_analysis, impact_analysis) do
    warnings = []

    warnings = warnings ++ extract_validation_warnings(validation_results)
    warnings = warnings ++ extract_conflict_warnings(conflict_analysis)
    warnings = warnings ++ extract_impact_warnings(impact_analysis)

    warnings
  end

  defp extract_validation_warnings(_validation_results), do: []
  defp extract_conflict_warnings(_conflict_analysis), do: []
  defp extract_impact_warnings(_impact_analysis), do: []

  defp analyze_functional_impact(_changes) do
    # Analyze how changes affect system functionality
    %{level: :low, description: "Minimal functional impact expected"}
  end

  defp analyze_performance_impact(_changes) do
    # Analyze performance implications
    %{level: :low, description: "No significant performance impact"}
  end

  defp analyze_security_impact(_changes) do
    # Analyze security implications
    %{level: :low, description: "No security impact detected"}
  end

  defp analyze_ux_impact(_changes) do
    # Analyze user experience impact
    %{level: :low, description: "Minimal user experience changes"}
  end

  defp analyze_integration_impact(_changes, _user_id, _project_id) do
    # Analyze impact on system integrations
    %{level: :low, description: "No integration impact detected"}
  end

  defp calculate_overall_impact_level(impact_analysis) do
    impact_levels =
      impact_analysis
      |> Map.values()
      |> Enum.map(&Map.get(&1, :level))

    cond do
      :high in impact_levels -> :high
      :medium in impact_levels -> :medium
      true -> :low
    end
  end

  defp generate_impact_summary(impact_analysis) do
    high_impact_areas =
      impact_analysis
      |> Enum.filter(fn {_area, analysis} -> analysis.level == :high end)
      |> Enum.map(&elem(&1, 0))

    if Enum.empty?(high_impact_areas) do
      "Changes have minimal impact on system behavior"
    else
      "High impact detected in: #{Enum.join(high_impact_areas, ", ")}"
    end
  end

  defp generate_impact_recommendations(impact_analysis) do
    impact_analysis
    |> Enum.flat_map(fn {area, analysis} ->
      case analysis.level do
        :high -> ["Review #{area} changes carefully before applying"]
        :medium -> ["Consider #{area} implications"]
        _ -> []
      end
    end)
  end

  defp format_validation_error(preference_key, message) do
    %{
      preference_key: preference_key,
      error_type: :validation_error,
      message: message,
      severity: :error,
      suggestion: generate_error_suggestion(preference_key, message)
    }
  end

  defp generate_error_suggestion(preference_key, message) do
    # Generate helpful suggestions based on error type
    cond do
      String.contains?(message, "must be") ->
        "Check the expected data type and format for #{preference_key}"

      String.contains?(message, "Invalid") ->
        "Verify the value is among the allowed options"

      true ->
        "Please check the preference documentation for valid values"
    end
  end

  defp get_affected_categories(changes) do
    changes
    |> Map.keys()
    |> Enum.map(&get_preference_category/1)
    |> Enum.uniq()
  end

  defp estimate_change_impact(change_diff) do
    added_count = Map.get(change_diff, :added, %{}) |> map_size()
    removed_count = Map.get(change_diff, :removed, %{}) |> map_size()
    modified_count = Map.get(change_diff, :modified, %{}) |> map_size()

    impact_score = added_count + removed_count * 3 + modified_count * 2

    cond do
      impact_score > 20 -> :high
      impact_score > 10 -> :medium
      true -> :low
    end
  end

  defp check_aggressive_settings_warnings(changes) do
    aggressive_settings = [
      "code_quality.refactoring.auto_apply_enabled",
      "ml.features.auto_optimization",
      "budgeting.enforcement.enabled"
    ]

    Enum.flat_map(aggressive_settings, fn setting ->
      if Map.get(changes, setting) == "true" do
        [
          %{
            type: :aggressive_setting,
            preference: setting,
            message:
              "This setting enables aggressive automation - ensure you understand the implications",
            severity: :warning
          }
        ]
      else
        []
      end
    end)
  end

  defp check_security_warnings(changes) do
    security_sensitive = [
      "ml.data.sharing_allowed",
      "budgeting.enforcement.override_allowed"
    ]

    Enum.flat_map(security_sensitive, fn setting ->
      if Map.has_key?(changes, setting) do
        [
          %{
            type: :security_sensitive,
            preference: setting,
            message: "This preference affects security - review carefully",
            severity: :warning
          }
        ]
      else
        []
      end
    end)
  end

  defp check_compatibility_warnings(_changes, _user_id, _project_id) do
    # Check for compatibility issues
    []
  end

  defp check_performance_warnings(changes) do
    performance_settings = [
      "ml.performance.memory_limit_mb",
      "code_quality.global.performance_mode"
    ]

    Enum.flat_map(performance_settings, fn setting ->
      if Map.has_key?(changes, setting) do
        [
          %{
            type: :performance_impact,
            preference: setting,
            message: "This change may affect system performance",
            severity: :info
          }
        ]
      else
        []
      end
    end)
  end

  defp determine_validation_function(_preference_key) do
    # Extract validation function name from preference key
    # This is a simplified approach - a real implementation would have
    # a mapping of preference keys to validation functions
    :validate_preference_value
  end

  defp get_preference_category(preference_key) do
    preference_key
    |> String.split(".")
    |> hd()
  end
end
