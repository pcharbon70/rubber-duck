defmodule RubberDuck.Actions.Core.UpdateEntity.Validator do
  @moduledoc """
  Validation module for UpdateEntity action.

  Handles all validation concerns including:
  - Field validation and type checking
  - Constraint validation
  - Compatibility checking
  - Security validation
  - Change sanitization
  """

  require Logger

  @doc """
  Main validation entry point that orchestrates all validation checks.

  Returns validated and sanitized changes or an error with validation details.
  """
  def validate(params, context) do
    current_entity = params.current_entity
    changes = params.changes
    validation_config = params[:validation_config] || %{}

    validation_results = %{
      field_validation: validate_field_changes(changes, current_entity),
      constraint_validation: validate_constraints(changes, validation_config),
      compatibility_check: check_compatibility(changes, current_entity),
      security_check: perform_security_validation(changes, current_entity.type)
    }

    all_valid =
      validation_results
      |> Map.values()
      |> Enum.all?(& &1.valid)

    if all_valid do
      {:ok,
       %{
         entity: current_entity,
         changes: sanitize_changes(changes),
         validations: validation_results,
         change_count: map_size(changes),
         change_severity: assess_change_severity(changes, current_entity),
         metadata: Map.get(context, :metadata, %{})
       }}
    else
      {:error,
       %{
         reason: :validation_failed,
         validations: validation_results,
         failed_checks: get_failed_checks(validation_results)
       }}
    end
  end

  @doc """
  Validates that field changes are allowed for the entity type.
  """
  def validate_field_changes(changes, entity) do
    invalid_fields =
      changes
      |> Map.keys()
      |> Enum.filter(fn field ->
        not Map.has_key?(entity, field) and field not in allowed_new_fields(entity.type)
      end)

    %{
      valid: Enum.empty?(invalid_fields),
      invalid_fields: invalid_fields,
      validated_fields: Map.keys(changes) -- invalid_fields
    }
  end

  @doc """
  Returns allowed new fields for each entity type.
  """
  def allowed_new_fields(entity_type) do
    case entity_type do
      :user -> [:preferences, :settings, :metadata]
      :project -> [:tags, :metadata, :collaborators]
      :code_file -> [:annotations, :metadata, :dependencies]
      :analysis -> [:metadata, :recommendations]
      _ -> [:metadata]
    end
  end

  @doc """
  Validates changes against defined constraints.
  """
  def validate_constraints(changes, config) do
    constraints = config[:constraints] || %{}

    violations =
      Enum.reduce(changes, [], fn {field, value}, acc ->
        check_field_constraint(acc, field, value, constraints)
      end)

    %{
      valid: Enum.empty?(violations),
      violations: violations,
      constraints_checked: map_size(constraints)
    }
  end

  defp check_field_constraint(acc, field, value, constraints) do
    case constraints[field] do
      nil ->
        acc

      constraint ->
        if violates_constraint?(value, constraint) do
          [{field, constraint, value} | acc]
        else
          acc
        end
    end
  end

  defp violates_constraint?(value, %{type: type}) when is_binary(value) do
    type != :string
  end

  defp violates_constraint?(value, %{min: min}) when is_binary(value) do
    String.length(value) < min
  end

  defp violates_constraint?(value, %{min: min}) when is_number(value) do
    value < min
  end

  defp violates_constraint?(value, %{max: max}) when is_binary(value) do
    String.length(value) > max
  end

  defp violates_constraint?(value, %{max: max}) when is_number(value) do
    value > max
  end

  defp violates_constraint?(value, %{pattern: pattern}) when is_binary(value) do
    not Regex.match?(pattern, value)
  end

  defp violates_constraint?(value, %{required: true}) do
    is_nil(value) or (is_binary(value) and value == "")
  end

  defp violates_constraint?(_, _), do: false

  @doc """
  Checks type compatibility between old and new values.
  """
  def check_compatibility(changes, entity) do
    compatibility_issues = []

    # Check for type mismatches
    compatibility_issues =
      Enum.reduce(changes, compatibility_issues, fn {field, new_value}, acc ->
        if old_value = Map.get(entity, field) do
          if incompatible_types?(old_value, new_value) do
            [{field, :type_mismatch, {old_value, new_value}} | acc]
          else
            acc
          end
        else
          acc
        end
      end)

    %{
      valid: Enum.empty?(compatibility_issues),
      issues: compatibility_issues,
      compatibility_score: calculate_compatibility_score(compatibility_issues, changes)
    }
  end

  defp incompatible_types?(old, new) when is_binary(old), do: not is_binary(new)
  defp incompatible_types?(old, new) when is_number(old), do: not is_number(new)
  defp incompatible_types?(old, new) when is_map(old), do: not is_map(new)
  defp incompatible_types?(old, new) when is_list(old), do: not is_list(new)
  defp incompatible_types?(old, new) when is_boolean(old), do: not is_boolean(new)
  defp incompatible_types?(old, new) when is_atom(old), do: not is_atom(new)
  defp incompatible_types?(_, _), do: false

  defp calculate_compatibility_score(issues, changes) do
    if map_size(changes) > 0 do
      1.0 - length(issues) / map_size(changes)
    else
      1.0
    end
  end

  @doc """
  Performs security validation on changes.
  """
  def perform_security_validation(changes, entity_type) do
    security_risks = []

    # Check for sensitive field modifications
    sensitive_fields = get_sensitive_fields(entity_type)

    security_risks =
      Enum.reduce(changes, security_risks, fn {field, value}, acc ->
        cond do
          field in sensitive_fields ->
            [{field, :sensitive_field_modification} | acc]

          contains_sensitive_data?(value) ->
            [{field, :potential_sensitive_data} | acc]

          true ->
            acc
        end
      end)

    %{
      valid: Enum.empty?(security_risks),
      risks: security_risks,
      risk_level: assess_security_risk_level(security_risks)
    }
  end

  defp get_sensitive_fields(entity_type) do
    case entity_type do
      :user -> [:email, :password_hash, :permissions, :role, :api_key]
      :project -> [:owner_id, :permissions, :api_keys, :secrets]
      :code_file -> [:security_tokens, :credentials, :api_endpoints]
      :analysis -> [:sensitive_findings, :vulnerability_data]
      _ -> []
    end
  end

  defp contains_sensitive_data?(value) when is_binary(value) do
    patterns = [
      ~r/password/i,
      ~r/secret/i,
      ~r/api[_-]?key/i,
      ~r/token/i,
      ~r/bearer/i,
      ~r/private[_-]?key/i
    ]

    Enum.any?(patterns, &Regex.match?(&1, value))
  end

  defp contains_sensitive_data?(_), do: false

  defp assess_security_risk_level(risks) do
    cond do
      length(risks) == 0 -> :none
      length(risks) == 1 -> :low
      length(risks) <= 3 -> :medium
      true -> :high
    end
  end

  @doc """
  Sanitizes changes by removing or cleaning potentially harmful data.
  """
  def sanitize_changes(changes) do
    Enum.reduce(changes, %{}, fn {field, value}, acc ->
      sanitized_value = sanitize_value(value)
      Map.put(acc, field, sanitized_value)
    end)
  end

  defp sanitize_value(value) when is_binary(value) do
    value
    |> String.trim()
    |> remove_control_characters()
    |> truncate_if_needed()
  end

  defp sanitize_value(value) when is_list(value) do
    Enum.map(value, &sanitize_value/1)
  end

  defp sanitize_value(value) when is_map(value) do
    Map.new(value, fn {k, v} -> {k, sanitize_value(v)} end)
  end

  defp sanitize_value(value), do: value

  defp remove_control_characters(string) do
    String.replace(string, ~r/[\x00-\x1F\x7F]/, "")
  end

  defp truncate_if_needed(string, max_length \\ 10_000) do
    if String.length(string) > max_length do
      String.slice(string, 0, max_length)
    else
      string
    end
  end

  @doc """
  Assesses the severity of changes based on their impact.
  """
  def assess_change_severity(changes, entity) do
    severity_scores =
      Enum.map(changes, fn {field, new_value} ->
        old_value = Map.get(entity, field)
        calculate_field_severity(field, old_value, new_value, entity.type)
      end)

    if Enum.empty?(severity_scores) do
      :none
    else
      max_severity = Enum.max(severity_scores)

      cond do
        max_severity >= 0.8 -> :critical
        max_severity >= 0.6 -> :high
        max_severity >= 0.4 -> :medium
        max_severity >= 0.2 -> :low
        true -> :minimal
      end
    end
  end

  defp calculate_field_severity(field, old_value, new_value, entity_type) do
    base_score = get_field_importance(field, entity_type)
    change_magnitude = calculate_change_magnitude(old_value, new_value)

    base_score * change_magnitude
  end

  defp get_field_importance(field, entity_type) do
    importance_map = %{
      user: %{
        email: 0.9,
        username: 0.8,
        password_hash: 1.0,
        permissions: 1.0,
        role: 0.9,
        preferences: 0.3,
        metadata: 0.2
      },
      project: %{
        name: 0.7,
        owner_id: 1.0,
        status: 0.8,
        permissions: 0.9,
        description: 0.4,
        metadata: 0.2
      },
      code_file: %{
        path: 0.9,
        content: 0.8,
        language: 0.6,
        dependencies: 0.7,
        metadata: 0.2
      },
      analysis: %{
        results: 0.9,
        score: 0.8,
        findings: 0.9,
        metadata: 0.2
      }
    }

    get_in(importance_map, [entity_type, field]) || 0.5
  end

  defp calculate_change_magnitude(nil, _new), do: 1.0
  defp calculate_change_magnitude(old, new) when old == new, do: 0.0

  defp calculate_change_magnitude(old, new) when is_binary(old) and is_binary(new) do
    # Simple string similarity check
    if String.length(old) == 0 or String.length(new) == 0 do
      1.0
    else
      # Basic change ratio based on length difference
      length_diff = abs(String.length(old) - String.length(new))
      max_length = max(String.length(old), String.length(new))
      min(1.0, length_diff / max_length)
    end
  end

  defp calculate_change_magnitude(old, new) when is_number(old) and is_number(new) do
    if old == 0 do
      1.0
    else
      min(1.0, abs(new - old) / abs(old))
    end
  end

  defp calculate_change_magnitude(_old, _new), do: 0.5

  defp get_failed_checks(validation_results) do
    validation_results
    |> Enum.filter(fn {_key, result} -> not result.valid end)
    |> Enum.map(fn {key, _result} -> key end)
  end
end
