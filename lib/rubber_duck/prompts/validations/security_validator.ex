defmodule RubberDuck.Prompts.Validations.SecurityValidator do
  @moduledoc """
  Custom security validation for prompt content and metadata.

  Integrates with the security infrastructure to validate prompt content
  for security threats, injection attempts, and policy compliance during
  resource creation and updates.
  """

  use Ash.Resource.Validation
  require Logger

  alias RubberDuck.Prompts.Security.{ContentSanitizer, PromptValidator}

  @impl Ash.Resource.Validation
  def validate(changeset, _opts, _context) do
    content = Ash.Changeset.get_attribute(changeset, :content)
    prompt_type = Ash.Changeset.get_attribute(changeset, :prompt_type)
    security_level = Ash.Changeset.get_attribute(changeset, :security_level) || "standard"

    validation_context = %{
      prompt_type: prompt_type,
      security_level: String.to_atom(security_level),
      changeset_action: changeset.action.name
    }

    case validate_content_security(content, validation_context) do
      {:ok, validation_results} ->
        # Update changeset with security validation results
        enhanced_changeset =
          changeset
          |> Ash.Changeset.change_attribute(:security_validation_results, validation_results)
          |> Ash.Changeset.change_attribute(:risk_score, validation_results.risk_score)
          |> Ash.Changeset.change_attribute(:last_security_check, DateTime.utc_now())
          |> Ash.Changeset.change_attribute(
            :content_security_hash,
            generate_content_hash(content)
          )

        # Determine if approval is required based on security analysis
        approval_required = requires_approval?(validation_results, validation_context)

        final_changeset =
          Ash.Changeset.change_attribute(
            enhanced_changeset,
            :approval_required,
            approval_required
          )

        Logger.debug("SecurityValidator: Content security validation completed",
          risk_score: validation_results.risk_score,
          approval_required: approval_required,
          threats_detected: length(validation_results.threats_detected)
        )

        {:ok, final_changeset}

      {:error, reason} ->
        Logger.error("SecurityValidator: Security validation failed", error: reason)
        {:error, field: :content, message: "Security validation failed: #{inspect(reason)}"}
    end
  end

  @impl Ash.Resource.Validation
  def atomic?(_opts), do: false

  @impl Ash.Resource.Validation
  def describe(_opts), do: "validates content security and sets security metadata"

  # Private validation functions

  defp validate_content_security(content, context) when is_binary(content) do
    validation_options = %{
      check_composition_integrity: true,
      validate_template_variables: true,
      enable_ml_classification: true
    }

    with {:ok, content_validation} <-
           PromptValidator.validate_prompt_content(content, context, validation_options),
         {:ok, sanitization_analysis} <- ContentSanitizer.analyze_content_safety(content, context) do
      combined_results = %{
        overall_security_score: content_validation.overall_security_score,
        risk_score: calculate_risk_score(content_validation, sanitization_analysis),
        threats_detected: content_validation.threats_detected,
        security_recommendations:
          extract_security_recommendations(content_validation, sanitization_analysis),
        sanitization_needed: sanitization_analysis.sanitization_needed,
        validation_timestamp: DateTime.utc_now(),
        security_context: context
      }

      {:ok, combined_results}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_content_security(_content, _context) do
    {:error, :invalid_content_type}
  end

  defp calculate_risk_score(content_validation, sanitization_analysis) do
    # Combine security scores to calculate overall risk
    base_risk = 1.0 - content_validation.overall_security_score
    sanitization_risk = if sanitization_analysis.sanitization_needed, do: 0.3, else: 0.0
    threat_risk = length(content_validation.threats_detected) * 0.1

    total_risk = base_risk + sanitization_risk + threat_risk
    min(1.0, total_risk) |> Float.round(3)
  end

  defp extract_security_recommendations(content_validation, sanitization_analysis) do
    recommendations = []

    # Add content validation recommendations
    recommendations =
      if content_validation.overall_security_score < 0.7 do
        ["Review content for security issues", "Consider content sanitization" | recommendations]
      else
        recommendations
      end

    # Add sanitization recommendations
    recommendations =
      if sanitization_analysis.sanitization_needed do
        [
          "Content requires sanitization",
          "Remove potentially dangerous patterns" | recommendations
        ]
      else
        recommendations
      end

    # Add threat-specific recommendations
    threat_recommendations =
      content_validation.threats_detected
      |> Enum.flat_map(fn threat -> Map.get(threat, :recommendations, []) end)
      |> Enum.uniq()

    recommendations ++ threat_recommendations
  end

  defp requires_approval?(validation_results, context) do
    risk_threshold = get_approval_risk_threshold(context.prompt_type, context.security_level)

    cond do
      # High risk always requires approval
      validation_results.risk_score > risk_threshold -> true
      # System prompts always require approval
      context.prompt_type == :system -> true
      # Enhanced/maximum security prompts require approval
      context.security_level in [:enhanced, :maximum] -> true
      # Threats detected require approval
      length(validation_results.threats_detected) > 0 -> true
      # Otherwise no approval required
      true -> false
    end
  end

  # System prompts always require approval
  defp get_approval_risk_threshold(:system, _security_level), do: 0.0
  defp get_approval_risk_threshold(:project, :maximum), do: 0.2
  defp get_approval_risk_threshold(:project, :enhanced), do: 0.3
  defp get_approval_risk_threshold(:project, _security_level), do: 0.5
  defp get_approval_risk_threshold(:user, :maximum), do: 0.3
  defp get_approval_risk_threshold(:user, :enhanced), do: 0.4
  defp get_approval_risk_threshold(:user, _security_level), do: 0.6

  defp generate_content_hash(content) when is_binary(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end

  defp generate_content_hash(_content), do: nil
end
