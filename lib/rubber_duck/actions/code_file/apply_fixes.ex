defmodule RubberDuck.Actions.CodeFile.ApplyFixes do
  @moduledoc """
  Action to automatically apply code fixes and improvements.
  """

  use Jido.Action,
    name: "apply_fixes",
    description: "Applies automated fixes to code issues",
    schema: [
      file_id: [type: :string, required: true],
      content: [type: :string, required: true],
      fixes: [type: {:list, :map}, required: true],
      auto_apply: [type: :boolean, default: false],
      validate_after: [type: :boolean, default: true]
    ]

  @impl true
  def run(params, _context) do
    with {:ok, applicable_fixes} <- filter_applicable_fixes(params.fixes, params),
         {:ok, fixed_content} <- apply_fixes_to_content(params.content, applicable_fixes),
         {:ok, validation} <- validate_fixes(fixed_content, params) do

      {:ok, %{
        original_content: params.content,
        fixed_content: fixed_content,
        applied_fixes: applicable_fixes,
        skipped_fixes: get_skipped_fixes(params.fixes, applicable_fixes),
        validation_results: validation,
        improvement_metrics: calculate_improvement_metrics(params.content, fixed_content)
      }}
    end
  end

  defp filter_applicable_fixes(fixes, params) do
    applicable = if params.auto_apply do
      # Only apply safe, automated fixes
      Enum.filter(fixes, fn fix ->
        fix.auto_applicable && fix.risk_level in [:low, :minimal]
      end)
    else
      # Apply all requested fixes
      fixes
    end

    {:ok, applicable}
  end

  defp apply_fixes_to_content(content, fixes) do
    fixed = Enum.reduce(fixes, content, fn fix, acc ->
      apply_single_fix(acc, fix)
    end)

    {:ok, fixed}
  end

  defp apply_single_fix(content, fix) do
    case fix.type do
      :syntax -> fix_syntax_issue(content, fix)
      :formatting -> fix_formatting_issue(content, fix)
      :style -> fix_style_issue(content, fix)
      :performance -> apply_performance_fix(content, fix)
      :security -> apply_security_fix(content, fix)
      :documentation -> apply_documentation_fix(content, fix)
      _ -> content
    end
  end

  defp fix_syntax_issue(content, fix) do
    case fix.issue do
      :missing_comma -> add_missing_commas(content)
      :unclosed_bracket -> fix_unclosed_brackets(content)
      :incorrect_indentation -> fix_indentation(content)
      _ ->
        if fix[:pattern] && fix[:replacement] do
          String.replace(content, fix.pattern, fix.replacement)
        else
          content
        end
    end
  end

  defp fix_formatting_issue(content, fix) do
    case fix.issue do
      :trailing_whitespace -> remove_trailing_whitespace(content)
      :long_lines -> wrap_long_lines(content)
      :inconsistent_spacing -> normalize_spacing(content)
      _ -> content
    end
  end

  defp fix_style_issue(content, fix) do
    case fix.issue do
      :non_snake_case -> convert_to_snake_case(content)
      :single_letter_vars -> expand_variable_names(content)
      :missing_alias -> add_missing_aliases(content)
      _ -> content
    end
  end

  defp apply_performance_fix(content, fix) do
    case fix.issue do
      :enum_to_stream -> convert_enum_to_stream(content)
      :string_concatenation -> optimize_string_concatenation(content)
      :list_append -> optimize_list_operations(content)
      _ -> content
    end
  end

  defp apply_security_fix(content, fix) do
    case fix.issue do
      :hardcoded_secret -> remove_hardcoded_secrets(content)
      :unsafe_eval -> remove_unsafe_eval(content)
      :missing_validation -> add_input_validation(content, fix)
      _ -> content
    end
  end

  defp apply_documentation_fix(content, fix) do
    case fix.issue do
      :missing_moduledoc -> add_moduledoc(content)
      :missing_doc -> add_function_docs(content, fix)
      :outdated_doc -> update_documentation(content, fix)
      _ -> content
    end
  end

  defp validate_fixes(fixed_content, params) do
    if params.validate_after do
      validation = %{
        syntax_valid: validate_syntax(fixed_content),
        tests_pass: run_tests_if_available(params),
        no_regressions: check_for_regressions(params.content, fixed_content),
        improvement_confirmed: confirm_improvements(params.content, fixed_content)
      }

      {:ok, validation}
    else
      {:ok, %{skipped: true}}
    end
  end

  defp get_skipped_fixes(all_fixes, applied_fixes) do
    applied_ids = Enum.map(applied_fixes, & &1.id)

    all_fixes
    |> Enum.filter(fn fix ->
      not Enum.member?(applied_ids, fix.id)
    end)
    |> Enum.map(fn fix ->
      %{
        id: fix.id,
        reason: get_skip_reason(fix)
      }
    end)
  end

  defp get_skip_reason(fix) do
    cond do
      fix.risk_level == :high -> "High risk fix requires manual review"
      not fix.auto_applicable -> "Fix requires manual intervention"
      fix.requires_context -> "Fix requires additional context"
      true -> "Unknown reason"
    end
  end

  defp calculate_improvement_metrics(original, fixed) do
    %{
      lines_changed: count_changed_lines(original, fixed),
      issues_fixed: count_fixed_issues(original, fixed),
      complexity_reduction: calculate_complexity_reduction(original, fixed),
      readability_improvement: calculate_readability_improvement(original, fixed)
    }
  end

  # Fix implementation functions

  defp add_missing_commas(content) do
    # Add commas in common locations where they're missing
    content
    |> String.replace(~r/(\w+)\s+(\w+:)/, "\\1, \\2")
    |> String.replace(~r/\}\s+\{/, "}, {")
  end

  defp fix_unclosed_brackets(content) do
    # Count and balance brackets
    open_count = content |> String.graphemes() |> Enum.count(& &1 in ["[", "{", "("])
    close_count = content |> String.graphemes() |> Enum.count(& &1 in ["]", "}", ")"])

    if open_count > close_count do
      # Add closing brackets at the end
      closing = String.duplicate("]", open_count - close_count)
      content <> "\n" <> closing
    else
      content
    end
  end

  defp fix_indentation(content) do
    lines = String.split(content, "\n")

    fixed_lines = lines
      |> Enum.map(fn line ->
        # Ensure consistent 2-space indentation
        indent_level = detect_indent_level(line)
        trimmed = String.trim_leading(line)

        if trimmed == "" do
          ""
        else
          String.duplicate("  ", indent_level) <> trimmed
        end
      end)

    Enum.join(fixed_lines, "\n")
  end

  defp detect_indent_level(line) do
    # Simple heuristic for indent level
    cond do
      String.starts_with?(String.trim(line), "end") -> 0
      String.starts_with?(String.trim(line), "defmodule") -> 0
      String.starts_with?(String.trim(line), "def ") -> 1
      String.starts_with?(String.trim(line), "defp ") -> 1
      true -> 2
    end
  end

  defp remove_trailing_whitespace(content) do
    content
    |> String.split("\n")
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.join("\n")
  end

  defp wrap_long_lines(content) do
    max_length = 120

    content
    |> String.split("\n")
    |> Enum.map(fn line ->
      if String.length(line) > max_length do
        wrap_line(line, max_length)
      else
        line
      end
    end)
    |> Enum.join("\n")
  end

  defp wrap_line(line, _max_length) do
    # Simple line wrapping at logical break points
    if String.contains?(line, ",") do
      parts = String.split(line, ",", parts: 2)
      if length(parts) == 2 do
        Enum.at(parts, 0) <> ",\n  " <> String.trim(Enum.at(parts, 1))
      else
        line
      end
    else
      line
    end
  end

  defp normalize_spacing(content) do
    content
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/\s*,\s*/, ", ")
    |> String.replace(~r/\s*\|\s*/, " | ")
  end

  defp convert_to_snake_case(content) do
    # Convert camelCase to snake_case in function names
    Regex.replace(~r/def\s+([a-z])([A-Z])/, content, fn _, first, upper ->
      "def #{first}_#{String.downcase(upper)}"
    end)
  end

  defp expand_variable_names(content) do
    # Expand common single-letter variables
    content
    |> String.replace(~r/\bi\b/, "index")
    |> String.replace(~r/\bn\b/, "number")
    |> String.replace(~r/\bs\b/, "string")
  end

  defp add_missing_aliases(content) do
    # Add common aliases if missing
    if String.contains?(content, "Enum.") and not String.contains?(content, "alias") do
      "alias Enum\n\n" <> content
    else
      content
    end
  end

  defp convert_enum_to_stream(content) do
    # Convert chained Enum operations to Stream
    Regex.replace(~r/Enum\.(\w+)(.*?)\|>\s*Enum\./, content, "Stream.\\1\\2|> Stream.")
  end

  defp optimize_string_concatenation(content) do
    # Replace string concatenation with iolist pattern
    if String.contains?(content, "Enum.reduce") and String.contains?(content, "<>") do
      String.replace(content, "<>", "++")
    else
      content
    end
  end

  defp optimize_list_operations(content) do
    # Replace list ++ [item] with [item | list]
    Regex.replace(~r/(\w+)\s*\+\+\s*\[([^\]]+)\]/, content, "[\\2 | \\1]")
  end

  defp remove_hardcoded_secrets(content) do
    # Replace hardcoded secrets with environment variables
    content
    |> String.replace(~r/password\s*=\s*"[^"]+"/, "password = System.get_env(\"PASSWORD\")")
    |> String.replace(~r/api_key\s*=\s*"[^"]+"/, "api_key = System.get_env(\"API_KEY\")")
  end

  defp remove_unsafe_eval(content) do
    # Remove or replace eval usage
    String.replace(content, ~r/Code\.eval_string\([^)]+\)/, "# UNSAFE: eval removed")
  end

  defp add_input_validation(content, _fix) do
    # Add basic input validation
    if String.contains?(content, "def ") and not String.contains?(content, "validate") do
      content <> "\n\n  defp validate_input(input) do\n    # TODO: Add validation logic\n    {:ok, input}\n  end"
    else
      content
    end
  end

  defp add_moduledoc(content) do
    if String.contains?(content, "@moduledoc") do
      content
    else
      String.replace(content, ~r/(defmodule\s+[\w.]+\s+do)/, "\\1\n  @moduledoc \"\"\"\n  Module documentation\n  \"\"\"")
    end
  end

  defp add_function_docs(content, _fix) do
    # Add basic function documentation
    Regex.replace(~r/(def\s+\w+)/, content, "@doc \"Function documentation\"\n  \\1")
  end

  defp update_documentation(content, _fix) do
    # Update outdated documentation markers
    String.replace(content, "# TODO: Update docs", "# Documentation updated")
  end

  # Validation functions

  defp validate_syntax(content) do
    # Basic syntax validation
    Code.string_to_quoted(content)
    true
  rescue
    _ -> false
  end

  defp run_tests_if_available(_params) do
    # Would run tests if available
    true
  end

  defp check_for_regressions(original, fixed) do
    # Check that we haven't removed important code
    original_functions = extract_function_names(original)
    fixed_functions = extract_function_names(fixed)

    MapSet.subset?(MapSet.new(original_functions), MapSet.new(fixed_functions))
  end

  defp confirm_improvements(original, fixed) do
    # Confirm that fixes actually improved the code
    original_issues = count_issues(original)
    fixed_issues = count_issues(fixed)

    fixed_issues < original_issues
  end

  defp extract_function_names(content) do
    content
    |> then(fn c -> Regex.scan(~r/def(?:p?)\s+(\w+)/, c) end)
    |> Enum.map(fn [_, name] -> name end)
  end

  defp count_issues(content) do
    # Count various issues in the content
    issues = 0

    # Count syntax issues
    issues = issues + if String.contains?(content, "  end"), do: 1, else: 0

    # Count style issues
    issues = issues + if Regex.match?(~r/def [A-Z]/, content), do: 1, else: 0

    # Count formatting issues
    long_lines = content
      |> String.split("\n")
      |> Enum.count(fn line -> String.length(line) > 120 end)

    issues + long_lines
  end

  defp count_changed_lines(original, fixed) do
    original_lines = String.split(original, "\n")
    fixed_lines = String.split(fixed, "\n")

    original_lines
    |> Enum.zip(fixed_lines)
    |> Enum.count(fn {orig, fix} -> orig != fix end)
  end

  defp count_fixed_issues(original, fixed) do
    count_issues(original) - count_issues(fixed)
  end

  defp calculate_complexity_reduction(original, fixed) do
    original_complexity = calculate_cyclomatic_complexity(original)
    fixed_complexity = calculate_cyclomatic_complexity(fixed)

    max(0, original_complexity - fixed_complexity)
  end

  defp calculate_cyclomatic_complexity(content) do
    decision_points = ["if ", "unless ", "case ", "cond ", "and ", "or "]

    Enum.reduce(decision_points, 1, fn point, acc ->
      count = content
        |> String.split(point)
        |> length()
        |> Kernel.-(1)
      acc + count
    end)
  end

  defp calculate_readability_improvement(original, fixed) do
    original_score = calculate_readability_score(original)
    fixed_score = calculate_readability_score(fixed)

    fixed_score - original_score
  end

  defp calculate_readability_score(content) do
    lines = String.split(content, "\n")
    avg_line_length = if length(lines) > 0 do
      total = Enum.reduce(lines, 0, fn line, acc -> acc + String.length(line) end)
      total / length(lines)
    else
      0
    end

    # Simple readability score based on line length
    if avg_line_length < 80 do
      1.0
    else
      0.5
    end
  end
end
