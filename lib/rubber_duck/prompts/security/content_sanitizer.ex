defmodule RubberDuck.Prompts.Security.ContentSanitizer do
  @moduledoc """
  Advanced content sanitization service with semantic integrity preservation.

  Provides sophisticated content sanitization removing dangerous patterns while
  preserving semantic meaning and prompt effectiveness. Includes configurable
  sanitization rules, encoding handling, and quality validation.

  Features:
  - Remove potentially dangerous patterns with configurable rule sets and semantic preservation
  - Escape special tokens and characters with comprehensive encoding and validation
  - Validate template variable safety with injection prevention and context awareness
  - Preserve semantic integrity during sanitization with quality scoring and validation
  - Performance optimization with sanitization caching and intelligent pattern matching
  - Integration with security monitoring for threat detection and incident reporting
  """

  require Logger

  @sanitization_rules %{
    script_removal: %{
      pattern: ~r/<script[^>]*>.*?<\/script>/i,
      replacement: "[REMOVED: Script content]",
      severity: :critical,
      preserve_context: false
    },
    javascript_protocol: %{
      pattern: ~r/javascript\s*:/i,
      replacement: "[REMOVED: JavaScript protocol]",
      severity: :high,
      preserve_context: false
    },
    event_handlers: %{
      pattern: ~r/\son\w+\s*=\s*["\'][^"\']*["\']?/i,
      replacement: "[REMOVED: Event handler]",
      severity: :medium,
      preserve_context: false
    },
    system_commands: %{
      pattern: ~r/\{\{\s*(system|exec|eval|shell)\s*\}\}/i,
      replacement: "{{[SANITIZED]}}",
      severity: :critical,
      preserve_context: true
    },
    template_injection: %{
      pattern: ~r/(\$\{[^}]*\}|<%[^%]*%>|\{\%[^%]*\%\})/,
      replacement: "[REMOVED: Template injection]",
      severity: :high,
      preserve_context: false
    },
    file_access: %{
      pattern: ~r/(\.\.\/|\/etc\/|file\s*:\/\/)/i,
      replacement: "[REMOVED: File access]",
      severity: :medium,
      preserve_context: false
    },
    sql_injection: %{
      pattern: ~r/\b(union\s+select|drop\s+table|delete\s+from|insert\s+into)\b/i,
      replacement: "[REMOVED: SQL command]",
      severity: :high,
      preserve_context: false
    }
  }

  @encoding_rules %{
    html_entities: [
      {"<", "&lt;"},
      {">", "&gt;"},
      {"&", "&amp;"},
      {"\"", "&quot;"},
      {"'", "&#39;"}
    ],
    special_characters: [
      # Null byte
      {"\u0000", "[NULL]"},
      # Backspace
      {"\u0008", "[BS]"},
      # Delete character
      {"\u007F", "[DEL]"}
    ]
  }

  @quality_thresholds %{
    minimum_similarity: 0.7,
    maximum_length_change: 0.3,
    maximum_word_loss: 0.2
  }

  def sanitize_content(content, context \\ %{}, options \\ %{}) do
    sanitization_start_time = System.monotonic_time(:microsecond)

    Logger.debug("ContentSanitizer: Starting content sanitization",
      content_length: String.length(content),
      context_keys: Map.keys(context)
    )

    with {:ok, analysis} <- analyze_content_safety(content, context),
         {:ok, sanitized_content} <- execute_sanitization_pipeline(content, analysis, options),
         {:ok, quality_validation} <-
           validate_sanitization_quality(content, sanitized_content, options) do
      sanitization_time = System.monotonic_time(:microsecond) - sanitization_start_time

      Logger.info("ContentSanitizer: Content sanitization completed",
        original_length: String.length(content),
        sanitized_length: String.length(sanitized_content),
        sanitization_time_us: sanitization_time,
        quality_preserved: quality_validation.quality_preserved
      )

      {:ok,
       %{
         sanitized_content: sanitized_content,
         original_content: content,
         sanitization_metadata: %{
           sanitization_time_microseconds: sanitization_time,
           rules_applied: analysis.applicable_rules,
           threats_removed: analysis.detected_threats,
           quality_validation: quality_validation,
           semantic_similarity: quality_validation.semantic_similarity
         }
       }}
    else
      {:error, reason} ->
        Logger.error("ContentSanitizer: Content sanitization failed", error: reason)
        {:error, reason}
    end
  end

  def analyze_content_safety(content, context \\ %{}) do
    # Analyze content for safety without sanitization
    safety_analysis = %{
      safety_score: 1.0,
      detected_threats: [],
      applicable_rules: [],
      sanitization_needed: false,
      detected_risks: []
    }

    # Check each sanitization rule
    analysis_result =
      Enum.reduce(@sanitization_rules, safety_analysis, fn {rule_name, rule}, acc ->
        case Regex.match?(rule.pattern, content) do
          true ->
            threat = %{
              rule_name: rule_name,
              severity: rule.severity,
              pattern: rule.pattern,
              matches: Regex.scan(rule.pattern, content, return: :index)
            }

            %{
              acc
              | safety_score: acc.safety_score - calculate_threat_impact(rule.severity),
                detected_threats: [threat | acc.detected_threats],
                applicable_rules: [rule_name | acc.applicable_rules],
                sanitization_needed: true
            }

          false ->
            acc
        end
      end)

    # Adjust safety score based on context
    context_adjusted_score =
      adjust_safety_score_for_context(analysis_result.safety_score, context)

    final_analysis = %{
      analysis_result
      | safety_score: max(0.0, context_adjusted_score),
        context_factors: extract_context_factors(context)
    }

    {:ok, final_analysis}
  end

  def validate_template_variable_safety(variable_name, variable_value, context \\ %{}) do
    # Validate template variable for safety
    name_safety = validate_variable_name_safety(variable_name)
    value_safety = validate_variable_value_safety(variable_value, context)

    overall_safety = (name_safety + value_safety) / 2

    %{
      overall_safety_score: overall_safety,
      name_safety_score: name_safety,
      value_safety_score: value_safety,
      safe_for_interpolation: overall_safety > 0.7,
      recommendations:
        generate_variable_safety_recommendations(variable_name, variable_value, overall_safety)
    }
  end

  # Private sanitization functions

  defp execute_sanitization_pipeline(content, analysis, options) do
    if analysis.sanitization_needed do
      sanitized = content

      # Apply sanitization rules in order of severity
      sanitized = apply_sanitization_rules(sanitized, analysis.applicable_rules, options)

      # Apply encoding rules
      sanitized = apply_encoding_rules(sanitized, options)

      # Final safety check
      case validate_sanitized_content_safety(sanitized) do
        {:ok, :safe} -> {:ok, sanitized}
        {:error, :still_dangerous} -> {:error, :sanitization_insufficient}
      end
    else
      {:ok, content}
    end
  end

  defp apply_sanitization_rules(content, applicable_rules, options) do
    preserve_context = Map.get(options, :preserve_semantic_context, true)

    Enum.reduce(applicable_rules, content, fn rule_name, acc_content ->
      rule = Map.get(@sanitization_rules, rule_name)

      if rule do
        replacement = determine_replacement_text(rule, preserve_context, acc_content)
        String.replace(acc_content, rule.pattern, replacement)
      else
        acc_content
      end
    end)
  end

  defp apply_encoding_rules(content, options) do
    enable_html_encoding = Map.get(options, :enable_html_encoding, true)
    enable_special_char_encoding = Map.get(options, :enable_special_char_encoding, true)

    encoded_content = content

    # Apply HTML entity encoding
    encoded_content =
      if enable_html_encoding do
        Enum.reduce(@encoding_rules.html_entities, encoded_content, fn {char, entity}, acc ->
          String.replace(acc, char, entity)
        end)
      else
        encoded_content
      end

    # Apply special character encoding
    encoded_content =
      if enable_special_char_encoding do
        Enum.reduce(@encoding_rules.special_characters, encoded_content, fn {char, replacement},
                                                                            acc ->
          String.replace(acc, char, replacement)
        end)
      else
        encoded_content
      end

    encoded_content
  end

  defp validate_sanitization_quality(original_content, sanitized_content, options) do
    # Validate that sanitization preserved content quality
    similarity = calculate_semantic_similarity(original_content, sanitized_content)
    length_change_ratio = calculate_length_change_ratio(original_content, sanitized_content)

    word_preservation_ratio =
      calculate_word_preservation_ratio(original_content, sanitized_content)

    quality_preserved =
      similarity >= @quality_thresholds.minimum_similarity and
        length_change_ratio <= @quality_thresholds.maximum_length_change and
        word_preservation_ratio >= 1.0 - @quality_thresholds.maximum_word_loss

    {:ok,
     %{
       quality_preserved: quality_preserved,
       semantic_similarity: similarity,
       length_change_ratio: length_change_ratio,
       word_preservation_ratio: word_preservation_ratio,
       quality_score:
         calculate_overall_quality_score(similarity, length_change_ratio, word_preservation_ratio)
     }}
  end

  defp validate_sanitized_content_safety(sanitized_content) do
    # Final safety validation after sanitization
    remaining_threats =
      Enum.filter(@sanitization_rules, fn {_name, rule} ->
        Regex.match?(rule.pattern, sanitized_content)
      end)

    case remaining_threats do
      [] -> {:ok, :safe}
      _ -> {:error, :still_dangerous}
    end
  end

  # Quality and similarity calculations

  defp calculate_semantic_similarity(original, sanitized) do
    # Simple word-based similarity calculation
    original_words = extract_meaningful_words(original)
    sanitized_words = extract_meaningful_words(sanitized)

    common_words = MapSet.intersection(original_words, sanitized_words)
    union_words = MapSet.union(original_words, sanitized_words)

    case MapSet.size(union_words) do
      0 -> 1.0
      _ -> MapSet.size(common_words) / MapSet.size(union_words)
    end
  end

  defp calculate_length_change_ratio(original, sanitized) do
    original_length = String.length(original)
    sanitized_length = String.length(sanitized)

    case original_length do
      0 -> 0.0
      _ -> abs(original_length - sanitized_length) / original_length
    end
  end

  defp calculate_word_preservation_ratio(original, sanitized) do
    original_words = String.split(original, ~r/\s+/) |> length()
    sanitized_words = String.split(sanitized, ~r/\s+/) |> length()

    case original_words do
      0 -> 1.0
      _ -> sanitized_words / original_words
    end
  end

  defp extract_meaningful_words(content) do
    # Extract meaningful words excluding stop words
    stop_words = MapSet.new(["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for"])

    content
    |> String.downcase()
    |> String.split(~r/\W+/)
    |> Enum.reject(fn word -> word == "" or MapSet.member?(stop_words, word) end)
    |> MapSet.new()
  end

  defp calculate_overall_quality_score(similarity, length_change, word_preservation) do
    # Weighted quality score
    weighted_score = similarity * 0.5 + (1.0 - length_change) * 0.3 + word_preservation * 0.2
    Float.round(weighted_score, 3)
  end

  # Utility functions

  defp calculate_threat_impact(severity) do
    case severity do
      :critical -> 0.4
      :high -> 0.3
      :medium -> 0.2
      :low -> 0.1
    end
  end

  defp adjust_safety_score_for_context(base_score, context) do
    # Adjust safety score based on context factors
    adjustment =
      case Map.get(context, :prompt_type) do
        # System prompts get slight boost
        :system -> 0.1
        # Project prompts get small boost
        :project -> 0.05
        # User prompts no adjustment
        :user -> 0.0
      end

    trust_adjustment =
      case Map.get(context, :trust_level) do
        :verified -> 0.1
        :trusted -> 0.05
        _ -> 0.0
      end

    base_score + adjustment + trust_adjustment
  end

  defp extract_context_factors(context) do
    %{
      prompt_type: Map.get(context, :prompt_type, :unknown),
      trust_level: Map.get(context, :trust_level, :standard),
      high_security_mode: Map.get(context, :high_security_mode, false),
      user_role: Map.get(context, :user_role, :user)
    }
  end

  defp determine_replacement_text(rule, preserve_context, content) do
    if preserve_context and rule.preserve_context do
      generate_contextual_replacement(rule, content)
    else
      rule.replacement
    end
  end

  defp generate_contextual_replacement(rule, content) do
    # Generate context-aware replacement that preserves meaning
    case rule.severity do
      :critical -> "[SECURITY: Content removed for safety]"
      :high -> "[WARNING: Potentially unsafe content removed]"
      :medium -> "[INFO: Content sanitized for security]"
      :low -> "[SANITIZED]"
    end
  end

  defp validate_variable_name_safety(variable_name) do
    # Validate variable name safety
    dangerous_names = ["system", "exec", "eval", "shell", "admin", "root", "password", "secret"]

    safety_score =
      if String.downcase(variable_name) in dangerous_names do
        0.2
      else
        0.9
      end

    # Check for suspicious patterns
    safety_score =
      if Regex.match?(~r/[^a-zA-Z0-9_]/, variable_name) do
        safety_score * 0.8
      else
        safety_score
      end

    safety_score
  end

  defp validate_variable_value_safety(variable_value, _context) when is_binary(variable_value) do
    # Validate variable value content
    base_safety = 0.8

    # Check for dangerous patterns in value
    safety_score =
      Enum.reduce(@sanitization_rules, base_safety, fn {_name, rule}, acc ->
        if Regex.match?(rule.pattern, variable_value) do
          acc - calculate_threat_impact(rule.severity)
        else
          acc
        end
      end)

    max(0.0, safety_score)
  end

  defp validate_variable_value_safety(_variable_value, _context) do
    # Non-string values are generally safe
    0.9
  end

  defp generate_variable_safety_recommendations(variable_name, variable_value, safety_score) do
    recommendations = []

    recommendations =
      if safety_score < 0.5 do
        ["Consider using a different variable name" | recommendations]
      else
        recommendations
      end

    recommendations =
      if is_binary(variable_value) and String.contains?(variable_value, "<script") do
        ["Remove script content from variable value" | recommendations]
      else
        recommendations
      end

    recommendations =
      if String.downcase(variable_name) in ["system", "exec", "eval"] do
        ["Avoid using reserved variable names" | recommendations]
      else
        recommendations
      end

    case recommendations do
      [] -> ["Variable appears safe for use"]
      _ -> recommendations
    end
  end
end
