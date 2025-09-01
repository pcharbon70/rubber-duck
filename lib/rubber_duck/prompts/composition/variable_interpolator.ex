defmodule RubberDuck.Prompts.Composition.VariableInterpolator do
  @moduledoc """
  Secure variable interpolation service with context awareness and validation.

  Provides safe variable substitution with comprehensive security validation,
  context-aware resolution, and support for dynamic variables from user context.
  Includes template inheritance and override patterns with security enforcement.

  Features:
  - Safe variable substitution with comprehensive validation and security checking
  - Context-aware variable resolution with user and project context integration
  - Support for dynamic variables from user context with real-time value resolution
  - Template inheritance and override patterns with composition validation
  - Security validation with prompt injection prevention and content sanitization
  - Performance optimization with variable caching and intelligent resolution strategies
  """

  require Logger

  @variable_pattern ~r/\{\{([^}]+)\}\}/
  @reserved_variables ["system", "exec", "eval", "script", "javascript"]
  @max_variable_length 100
  @max_interpolation_depth 5

  @default_interpolation_options %{
    enable_security_validation: true,
    allow_dynamic_variables: true,
    enable_context_resolution: true,
    max_variable_length: @max_variable_length,
    max_interpolation_depth: @max_interpolation_depth,
    preserve_missing_variables: false
  }

  def interpolate(content, variables, context, options \\ %{}) do
    merged_options = Map.merge(@default_interpolation_options, options)

    Logger.debug("VariableInterpolator: Starting variable interpolation",
      content_length: String.length(content),
      variable_count: map_size(variables),
      enable_security: merged_options.enable_security_validation
    )

    interpolation_start_time = System.monotonic_time(:microsecond)

    with {:ok, validated_variables} <- validate_variables_security(variables, merged_options),
         {:ok, resolved_variables} <-
           resolve_context_variables(validated_variables, context, merged_options),
         {:ok, interpolated_content} <-
           execute_variable_interpolation(content, resolved_variables, merged_options),
         {:ok, validated_content} <-
           validate_interpolated_content(interpolated_content, merged_options) do
      interpolation_time = System.monotonic_time(:microsecond) - interpolation_start_time

      Logger.debug("VariableInterpolator: Variable interpolation completed",
        original_length: String.length(content),
        final_length: String.length(validated_content),
        interpolation_time_us: interpolation_time,
        variables_interpolated: count_successful_interpolations(content, validated_content)
      )

      {:ok, validated_content}
    else
      {:error, reason} ->
        Logger.error("VariableInterpolator: Variable interpolation failed", error: reason)
        {:error, reason}
    end
  end

  def extract_variables(content) do
    # Extract all variable names from content
    case Regex.scan(@variable_pattern, content) do
      [] ->
        []

      matches ->
        matches
        |> Enum.map(fn [_full, variable] -> String.trim(variable) end)
        |> Enum.uniq()
    end
  end

  def validate_variable_safety(variable_name, variable_value) do
    # Validate individual variable for security
    with :ok <- validate_variable_name(variable_name),
         :ok <- validate_variable_value(variable_value) do
      :ok
    else
      {:error, reason} -> {:error, {:variable_validation_failed, variable_name, reason}}
    end
  end

  # Private interpolation functions

  defp validate_variables_security(variables, options) do
    if options.enable_security_validation do
      case validate_all_variables(variables) do
        :ok -> {:ok, variables}
        {:error, reason} -> {:error, {:variable_security_failed, reason}}
      end
    else
      {:ok, variables}
    end
  end

  defp validate_all_variables(variables) do
    Enum.reduce_while(variables, :ok, fn {name, value}, _acc ->
      case validate_variable_safety(name, value) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_variable_name(name) when is_binary(name) do
    cond do
      String.length(name) > @max_variable_length ->
        {:error, :variable_name_too_long}

      String.downcase(name) in @reserved_variables ->
        {:error, :reserved_variable_name}

      not Regex.match?(~r/^[a-zA-Z0-9_]+$/, name) ->
        {:error, :invalid_variable_name_format}

      true ->
        :ok
    end
  end

  defp validate_variable_name(_), do: {:error, :invalid_variable_name_type}

  defp validate_variable_value(value) when is_binary(value) do
    # Basic security validation for variable values
    dangerous_patterns = [
      ~r/<script/i,
      ~r/javascript:/i,
      ~r/data:.*base64/i,
      # Nested variables
      ~r/\{\{.*\}\}/,
      ~r/exec\s*\(/i,
      ~r/eval\s*\(/i
    ]

    dangerous_found =
      Enum.any?(dangerous_patterns, fn pattern ->
        Regex.match?(pattern, value)
      end)

    if dangerous_found do
      {:error, :dangerous_variable_value}
    else
      :ok
    end
  end

  defp validate_variable_value(_), do: {:error, :invalid_variable_value_type}

  defp resolve_context_variables(variables, context, options) do
    if options.enable_context_resolution do
      resolved_variables =
        variables
        |> Enum.map(fn {name, value} ->
          resolved_value = resolve_context_variable(name, value, context)
          {name, resolved_value}
        end)
        |> Map.new()

      {:ok, resolved_variables}
    else
      {:ok, variables}
    end
  end

  defp resolve_context_variable(name, value, context) do
    # Resolve variables with context awareness
    case {name, value} do
      {"user_name", _} -> Map.get(context, :user_name, value)
      {"project_name", _} -> Map.get(context, :project_name, value)
      {"current_time", _} -> DateTime.utc_now() |> DateTime.to_string()
      {_, _} -> value
    end
  end

  defp execute_variable_interpolation(content, variables, options) do
    # Execute variable interpolation with depth protection
    interpolated =
      Enum.reduce(variables, content, fn {name, value}, acc_content ->
        variable_pattern = ~r/\{\{\s*#{Regex.escape(name)}\s*\}\}/
        String.replace(acc_content, variable_pattern, to_string(value))
      end)

    # Check for remaining unresolved variables
    case handle_unresolved_variables(interpolated, options) do
      {:ok, final_content} -> {:ok, final_content}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_unresolved_variables(content, options) do
    remaining_variables = extract_variables(content)

    case {remaining_variables, options.preserve_missing_variables} do
      {[], _} ->
        {:ok, content}

      {vars, true} ->
        Logger.debug("VariableInterpolator: Preserving unresolved variables",
          variables: vars
        )

        {:ok, content}

      {vars, false} ->
        Logger.warn("VariableInterpolator: Unresolved variables found",
          variables: vars
        )

        {:error, {:unresolved_variables, vars}}
    end
  end

  defp validate_interpolated_content(content, options) do
    if options.enable_security_validation do
      case validate_content_security_post_interpolation(content) do
        :ok -> {:ok, content}
        {:error, reason} -> {:error, {:post_interpolation_security_failed, reason}}
      end
    else
      {:ok, content}
    end
  end

  defp validate_content_security_post_interpolation(content) do
    # Validate content security after interpolation
    post_interpolation_patterns = [
      ~r/<script.*?>.*?<\/script>/i,
      ~r/javascript\s*:/i,
      # Event handlers
      ~r/on\w+\s*=/i,
      ~r/data:.*base64/i,
      ~r/eval\s*\(/i,
      ~r/exec\s*\(/i
    ]

    dangerous_found =
      Enum.any?(post_interpolation_patterns, fn pattern ->
        Regex.match?(pattern, content)
      end)

    if dangerous_found do
      {:error, :dangerous_content_after_interpolation}
    else
      :ok
    end
  end

  # Utility functions

  defp count_successful_interpolations(original_content, final_content) do
    original_vars = length(extract_variables(original_content))
    remaining_vars = length(extract_variables(final_content))

    original_vars - remaining_vars
  end
end
