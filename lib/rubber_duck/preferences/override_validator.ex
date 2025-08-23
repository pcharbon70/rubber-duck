defmodule RubberDuck.Preferences.OverrideValidator do
  @moduledoc """
  Validation logic for project preference overrides.

  Ensures override compatibility, permission levels, constraint validation,
  and prevention of invalid preference combinations.
  """

  require Logger

  alias RubberDuck.Preferences.Resources.{
    PreferenceValidation,
    ProjectPreference,
    ProjectPreferenceEnabled,
    SystemDefault
  }

  @doc """
  Validate a project preference override before creation.
  """
  @spec validate_override(
          project_id :: binary(),
          preference_key :: String.t(),
          value :: any(),
          opts :: keyword()
        ) ::
          {:ok, :valid} | {:error, String.t()}
  def validate_override(project_id, preference_key, value, opts \\ []) do
    with {:ok, :exists} <- validate_preference_exists(preference_key),
         {:ok, :compatible} <- validate_value_compatibility(preference_key, value),
         {:ok, :within_constraints} <- validate_constraints(preference_key, value),
         {:ok, :permission_granted} <- validate_permissions(project_id, preference_key, opts),
         {:ok, :no_conflicts} <- validate_no_conflicts(project_id, preference_key, value, opts) do
      {:ok, :valid}
    else
      error -> error
    end
  end

  @doc """
  Validate that a preference key exists in system defaults.
  """
  @spec validate_preference_exists(preference_key :: String.t()) ::
          {:ok, :exists} | {:error, String.t()}
  def validate_preference_exists(preference_key) do
    case SystemDefault.read() do
      {:ok, defaults} ->
        case Enum.find(defaults, &(&1.preference_key == preference_key && !&1.deprecated)) do
          %{} -> {:ok, :exists}
          nil -> {:error, "Preference key '#{preference_key}' does not exist or is deprecated"}
        end

      {:error, _} ->
        {:error, "Unable to validate preference existence"}
    end
  end

  @doc """
  Validate that the provided value is compatible with the preference data type.
  """
  @spec validate_value_compatibility(preference_key :: String.t(), value :: any()) ::
          {:ok, :compatible} | {:error, String.t()}
  def validate_value_compatibility(preference_key, value) do
    case get_preference_data_type(preference_key) do
      {:ok, data_type} ->
        if value_matches_type?(value, data_type) do
          {:ok, :compatible}
        else
          {:error, "Value type incompatible with preference data type '#{data_type}'"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Validate value against preference constraints.
  """
  @spec validate_constraints(preference_key :: String.t(), value :: any()) ::
          {:ok, :within_constraints} | {:error, String.t()}
  def validate_constraints(preference_key, value) do
    case get_preference_constraints(preference_key) do
      # No constraints defined
      {:ok, nil} ->
        {:ok, :within_constraints}

      {:ok, constraints} ->
        case validate_against_constraints(value, constraints) do
          :ok -> {:ok, :within_constraints}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Validate user has permission to create this override.
  """
  @spec validate_permissions(
          project_id :: binary(),
          preference_key :: String.t(),
          opts :: keyword()
        ) ::
          {:ok, :permission_granted} | {:error, String.t()}
  def validate_permissions(project_id, preference_key, opts) do
    approved_by = Keyword.get(opts, :approved_by)

    with {:ok, enablement} <- get_project_enablement(project_id),
         {:ok, :authorized} <- check_user_authorization(approved_by, preference_key),
         {:ok, :within_limits} <- check_override_limits(project_id, enablement) do
      {:ok, :permission_granted}
    else
      error -> error
    end
  end

  @doc """
  Validate that the override doesn't conflict with other constraints.
  """
  @spec validate_no_conflicts(
          project_id :: binary(),
          preference_key :: String.t(),
          value :: any(),
          opts :: keyword()
        ) ::
          {:ok, :no_conflicts} | {:error, String.t()}
  def validate_no_conflicts(project_id, preference_key, value, _opts) do
    # Check for dependency conflicts
    case get_preference_dependencies(preference_key) do
      {:ok, dependencies} ->
        case validate_dependency_compatibility(project_id, dependencies, value) do
          :ok -> {:ok, :no_conflicts}
          {:error, reason} -> {:error, reason}
        end

      # No dependencies to validate
      {:error, _} ->
        {:ok, :no_conflicts}
    end
  end

  # Private validation functions

  defp get_preference_data_type(preference_key) do
    case SystemDefault.read() do
      {:ok, defaults} ->
        case Enum.find(defaults, &(&1.preference_key == preference_key)) do
          %{data_type: data_type} -> {:ok, data_type}
          nil -> {:error, "Preference not found"}
        end

      {:error, _} ->
        {:error, "Unable to retrieve preference data type"}
    end
  end

  defp value_matches_type?(value, :string) when is_binary(value), do: true
  defp value_matches_type?(value, :integer) when is_integer(value), do: true
  defp value_matches_type?(value, :float) when is_float(value), do: true
  defp value_matches_type?(value, :boolean) when is_boolean(value), do: true
  defp value_matches_type?(value, :json) when is_map(value) or is_list(value), do: true
  # Encrypted values are strings
  defp value_matches_type?(_value, :encrypted), do: true
  defp value_matches_type?(_, _), do: false

  defp get_preference_constraints(preference_key) do
    case SystemDefault.read() do
      {:ok, defaults} ->
        case Enum.find(defaults, &(&1.preference_key == preference_key)) do
          %{constraints: constraints} -> {:ok, constraints}
          nil -> {:error, "Preference not found"}
        end

      {:error, _} ->
        {:error, "Unable to retrieve preference constraints"}
    end
  end

  defp validate_against_constraints(value, constraints) when is_map(constraints) do
    Enum.reduce_while(constraints, :ok, fn {constraint_type, constraint_value}, _acc ->
      case apply_constraint_validation(value, constraint_type, constraint_value) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_against_constraints(_value, _constraints), do: :ok

  defp apply_constraint_validation(value, "min", min_value)
       when is_number(value) and is_number(min_value) do
    if value >= min_value, do: :ok, else: {:error, "Value must be >= #{min_value}"}
  end

  defp apply_constraint_validation(value, "max", max_value)
       when is_number(value) and is_number(max_value) do
    if value <= max_value, do: :ok, else: {:error, "Value must be <= #{max_value}"}
  end

  defp apply_constraint_validation(value, "allowed_values", allowed) when is_list(allowed) do
    if value in allowed, do: :ok, else: {:error, "Value must be one of: #{inspect(allowed)}"}
  end

  defp apply_constraint_validation(value, "pattern", pattern)
       when is_binary(value) and is_binary(pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} ->
        if Regex.match?(regex, value),
          do: :ok,
          else: {:error, "Value must match pattern: #{pattern}"}

      {:error, _} ->
        {:error, "Invalid pattern constraint"}
    end
  end

  defp apply_constraint_validation(_value, _constraint_type, _constraint_value) do
    # Unknown constraint types are ignored for forward compatibility
    :ok
  end

  defp get_project_enablement(project_id) do
    case ProjectPreferenceEnabled.by_project(project_id) do
      {:ok, [enablement]} -> {:ok, enablement}
      {:ok, []} -> {:error, "Project overrides not configured"}
      error -> error
    end
  end

  defp check_user_authorization(approved_by, preference_key) do
    # Basic authorization check - in production this would integrate with
    # the full authorization system
    case get_preference_access_level(preference_key) do
      # User-level preferences don't need special auth
      {:ok, :user} -> {:ok, :authorized}
      {:ok, :admin} when not is_nil(approved_by) -> {:ok, :authorized}
      {:ok, :superadmin} when not is_nil(approved_by) -> {:ok, :authorized}
      {:ok, level} -> {:error, "Insufficient permissions for #{level} preference"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_preference_access_level(preference_key) do
    case SystemDefault.read() do
      {:ok, defaults} ->
        case Enum.find(defaults, &(&1.preference_key == preference_key)) do
          %{access_level: level} -> {:ok, level}
          nil -> {:error, "Preference not found"}
        end

      {:error, _} ->
        {:error, "Unable to check access level"}
    end
  end

  defp check_override_limits(project_id, enablement) do
    case enablement.max_overrides do
      # No limit set
      nil ->
        {:ok, :within_limits}

      max_overrides ->
        case count_active_overrides(project_id) do
          count when count < max_overrides -> {:ok, :within_limits}
          count -> {:error, "Override limit reached (#{count}/#{max_overrides})"}
        end
    end
  end

  defp count_active_overrides(project_id) do
    case ProjectPreference.active_for_project(project_id) do
      {:ok, preferences} -> length(preferences)
      {:error, _} -> 0
    end
  end

  defp get_preference_dependencies(preference_key) do
    case PreferenceValidation.by_preference(preference_key) do
      {:ok, validations} ->
        dependencies =
          validations
          |> Enum.filter(&(&1.validation_type == :dependency))
          |> Enum.map(& &1.validation_rule)

        {:ok, dependencies}

      {:error, _} ->
        {:error, "Unable to check dependencies"}
    end
  end

  defp validate_dependency_compatibility(_project_id, [], _value), do: :ok

  defp validate_dependency_compatibility(project_id, dependencies, value) do
    # Simplified dependency validation - in production this would be more sophisticated
    Enum.reduce_while(dependencies, :ok, fn dependency, _acc ->
      case validate_single_dependency(project_id, dependency, value) do
        :ok -> {:cont, :ok}
        error when is_tuple(error) -> {:halt, error}
      end
    end)
  end

  defp validate_single_dependency(_project_id, _dependency, _value) do
    # Placeholder for complex dependency validation logic
    # Return :ok or {:error, reason}
    :ok
  end
end
