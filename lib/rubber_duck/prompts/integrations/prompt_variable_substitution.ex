defmodule RubberDuck.Prompts.Integrations.PromptVariableSubstitution do
  @moduledoc """
  Service for handling template variable substitution in saved prompts.

  Provides safe and efficient template variable substitution for saved prompts
  when they are selected for use in LLM operations. Supports variable validation,
  default values, and security sanitization to prevent injection attacks.

  Features:
  - Safe template variable substitution with injection prevention
  - Variable validation and type checking for prompt templates
  - Support for default values and conditional variables
  - Context-aware variable resolution from LLM operation context
  """

  require Logger

  @variable_pattern ~r/\{\{(\w+)(?:\|(.+?))?\}\}/
  @max_variable_length 1000
  @forbidden_patterns [
    ~r/\{\{\s*system\s*\}\}/i,
    ~r/\{\{\s*exec\s*\}\}/i,
    ~r/\{\{\s*eval\s*\}\}/i,
    ~r/<script/i,
    ~r/javascript:/i
  ]

  @doc """
  Substitute template variables in prompt content with provided values.
  """
  def substitute_variables(prompt_content, variable_values \\ %{}, options \\ %{}) do
    Logger.debug("PromptVariableSubstitution: Substituting variables",
      content_length: String.length(prompt_content),
      variable_count: map_size(variable_values)
    )

    case validate_variable_values(variable_values, options) do
      {:ok, validated_values} ->
        case execute_variable_substitution(prompt_content, validated_values, options) do
          {:ok, substituted_content} ->
            Logger.debug("PromptVariableSubstitution: Variable substitution completed",
              original_length: String.length(prompt_content),
              substituted_length: String.length(substituted_content),
              variables_substituted:
                count_substituted_variables(prompt_content, substituted_content)
            )

            {:ok, substituted_content}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Extract template variables from prompt content.
  """
  def extract_template_variables(prompt_content) do
    Logger.debug("PromptVariableSubstitution: Extracting template variables",
      content_length: String.length(prompt_content)
    )

    variables =
      Regex.scan(@variable_pattern, prompt_content, capture: :all_but_first)
      |> Enum.map(fn
        [variable_name] ->
          {variable_name, %{default: nil, type: :string, required: true}}

        [variable_name, default_value] ->
          {variable_name, %{default: default_value, type: :string, required: false}}
      end)
      |> Map.new()

    Logger.debug("PromptVariableSubstitution: Template variables extracted",
      variable_count: map_size(variables),
      variables: Map.keys(variables)
    )

    {:ok, variables}
  end

  @doc """
  Validate prompt content for template variable safety.
  """
  def validate_template_variables(prompt_content, validation_options \\ %{}) do
    Logger.debug("PromptVariableSubstitution: Validating template variables",
      content_length: String.length(prompt_content)
    )

    case check_for_forbidden_patterns(prompt_content) do
      {:ok, :safe} ->
        case validate_variable_syntax(prompt_content) do
          {:ok, :valid_syntax} ->
            {:ok,
             %{
               safe: true,
               valid_syntax: true,
               variable_count: count_template_variables(prompt_content)
             }}

          {:error, reason} ->
            {:error, {:invalid_syntax, reason}}
        end

      {:error, reason} ->
        {:error, {:unsafe_content, reason}}
    end
  end

  @doc """
  Get variable suggestions based on context and commonly used variables.
  """
  def get_variable_suggestions(context \\ %{}) do
    # Provide variable suggestions based on context
    base_suggestions = [
      %{name: "user_name", description: "Current user's name", example: "John Doe"},
      %{name: "project_name", description: "Current project name", example: "MyProject"},
      %{name: "current_date", description: "Current date", example: "2024-01-15"},
      %{name: "task_type", description: "Type of task being performed", example: "code_review"}
    ]

    context_suggestions = build_context_specific_suggestions(context)

    all_suggestions = base_suggestions ++ context_suggestions

    {:ok, all_suggestions}
  end

  # Private implementation functions

  defp execute_variable_substitution(prompt_content, validated_values, options) do
    # Execute safe variable substitution
    substituted_content =
      Regex.replace(@variable_pattern, prompt_content, fn match_data ->
        substitute_single_variable_match(match_data, validated_values, options)
      end)

    case validate_substitution_result(substituted_content, options) do
      {:ok, :valid} ->
        {:ok, substituted_content}

      {:error, reason} ->
        {:error, {:substitution_validation_failed, reason}}
    end
  end

  defp substitute_single_variable_match(match_data, validated_values, options) do
    case match_data do
      [full_match, variable_name] ->
        substitute_simple_variable(full_match, variable_name, validated_values, options)

      [_full_match, variable_name, default_value] ->
        substitute_variable_with_default(variable_name, default_value, validated_values, options)
    end
  end

  defp substitute_simple_variable(full_match, variable_name, validated_values, options) do
    case Map.get(validated_values, variable_name) do
      nil -> full_match
      value -> sanitize_variable_value(value, options)
    end
  end

  defp substitute_variable_with_default(variable_name, default_value, validated_values, options) do
    case Map.get(validated_values, variable_name) do
      nil -> sanitize_variable_value(default_value, options)
      "" -> sanitize_variable_value(default_value, options)
      value -> sanitize_variable_value(value, options)
    end
  end

  defp validate_variable_values(variable_values, options) do
    # Validate variable values for safety and constraints
    validation_results =
      Enum.map(variable_values, fn {variable_name, value} ->
        validate_single_variable(variable_name, value, options)
      end)

    failed_validations = Enum.filter(validation_results, &match?({:error, _}, &1))

    case failed_validations do
      [] ->
        {:ok, variable_values}

      failures ->
        {:error, {:variable_validation_failed, failures}}
    end
  end

  defp validate_single_variable(variable_name, value, options) do
    # Validate a single variable
    cond do
      String.length(value) > @max_variable_length ->
        {:error, {:value_too_long, variable_name, @max_variable_length}}

      contains_forbidden_content?(value) ->
        {:error, {:forbidden_content, variable_name}}

      not valid_variable_name?(variable_name) ->
        {:error, {:invalid_variable_name, variable_name}}

      true ->
        {:ok, {variable_name, value}}
    end
  end

  defp sanitize_variable_value(value, options) do
    # Sanitize variable value for safe substitution
    enable_html_escaping = Map.get(options, :escape_html, true)

    sanitized =
      value
      |> String.trim()
      |> remove_control_characters()

    if enable_html_escaping do
      Phoenix.HTML.html_escape(sanitized) |> Phoenix.HTML.safe_to_string()
    else
      sanitized
    end
  end

  defp check_for_forbidden_patterns(content) do
    # Check for forbidden patterns in content
    forbidden_found =
      Enum.any?(@forbidden_patterns, fn pattern ->
        Regex.match?(pattern, content)
      end)

    if forbidden_found do
      {:error, :forbidden_patterns_detected}
    else
      {:ok, :safe}
    end
  end

  defp validate_variable_syntax(content) do
    # Validate variable syntax in content
    case Regex.scan(@variable_pattern, content) do
      [] ->
        {:ok, :no_variables}

      variables ->
        invalid_variables =
          Enum.filter(variables, fn [full_match, variable_name | _] ->
            not valid_variable_name?(variable_name)
          end)

        case invalid_variables do
          [] ->
            {:ok, :valid_syntax}

          invalid ->
            {:error, {:invalid_variable_syntax, invalid}}
        end
    end
  end

  defp validate_substitution_result(substituted_content, options) do
    # Validate the result after substitution
    case check_for_forbidden_patterns(substituted_content) do
      {:ok, :safe} ->
        {:ok, :valid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp valid_variable_name?(variable_name) do
    # Check if variable name is valid (alphanumeric + underscores)
    Regex.match?(~r/^\w+$/, variable_name) && String.length(variable_name) <= 50
  end

  defp contains_forbidden_content?(value) do
    # Check if value contains forbidden content
    Enum.any?(@forbidden_patterns, fn pattern ->
      Regex.match?(pattern, value)
    end)
  end

  defp remove_control_characters(text) do
    # Remove control characters from text
    String.replace(text, ~r/[\x00-\x1f\x7f]/, "")
  end

  defp count_template_variables(content) do
    # Count template variables in content
    Regex.scan(@variable_pattern, content) |> length()
  end

  defp count_substituted_variables(original_content, substituted_content) do
    # Count how many variables were actually substituted
    original_count = count_template_variables(original_content)
    remaining_count = count_template_variables(substituted_content)

    original_count - remaining_count
  end

  defp build_context_specific_suggestions(context) do
    # Build context-specific variable suggestions
    suggestions = []

    # Add LLM operation context suggestions
    suggestions =
      if Map.has_key?(context, :llm_operation_type) do
        operation_suggestions =
          case context.llm_operation_type do
            :code_review ->
              [
                %{name: "code_language", description: "Programming language", example: "Elixir"},
                %{name: "review_focus", description: "Focus area for review", example: "security"}
              ]

            :documentation ->
              [
                %{
                  name: "component_name",
                  description: "Component to document",
                  example: "UserService"
                },
                %{
                  name: "documentation_type",
                  description: "Type of documentation",
                  example: "API reference"
                }
              ]

            _ ->
              []
          end

        suggestions ++ operation_suggestions
      else
        suggestions
      end

    # Add project context suggestions
    suggestions =
      if Map.has_key?(context, :project_id) do
        project_suggestions = [
          %{name: "project_id", description: "Current project ID", example: context.project_id}
        ]

        suggestions ++ project_suggestions
      else
        suggestions
      end

    suggestions
  end
end
