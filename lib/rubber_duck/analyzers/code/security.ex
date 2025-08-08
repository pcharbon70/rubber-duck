defmodule RubberDuck.Analyzers.Code.Security do
  @moduledoc """
  Security-focused code analysis.

  Identifies potential security vulnerabilities, unsafe patterns,
  input validation issues, and authentication problems in code files.

  ## Supported Analysis Types

  - Vulnerability detection (code injection, hardcoded secrets)
  - Unsafe operation identification (system commands, eval)
  - Input validation assessment
  - Authentication issue detection
  - Security risk level calculation

  ## Integration

  This analyzer extracts security-specific logic from CodeAnalysisSkill
  while maintaining the same analysis capabilities in a focused module.
  """

  @behaviour RubberDuck.Analyzer

  alias RubberDuck.Messages.Code.{Analyze, SecurityScan}

  @impl true
  def analyze(%Analyze{analysis_type: :security} = msg, context) do
    content = get_content_from_context(msg, context)
    file_type = detect_file_type(msg.file_path)

    security_analysis = %{
      vulnerabilities: scan_for_vulnerabilities(content, file_type),
      unsafe_operations: detect_unsafe_operations(content),
      input_validation: check_input_validation(content),
      authentication_issues: check_authentication_issues(content),
      risk_level: calculate_security_risk_level(content),
      analyzed_at: DateTime.utc_now(),
      file_path: msg.file_path
    }

    {:ok, security_analysis}
  end

  def analyze(%Analyze{analysis_type: :comprehensive} = msg, context) do
    # For comprehensive analysis, return security subset
    analyze(%{msg | analysis_type: :security}, context)
  end

  def analyze(%SecurityScan{} = msg, _context) do
    security_scan = %{
      vulnerabilities: scan_for_vulnerabilities(msg.content, msg.file_type),
      unsafe_operations: detect_unsafe_operations(msg.content),
      input_validation: check_input_validation(msg.content),
      authentication_issues: check_authentication_issues(msg.content),
      risk_level: calculate_security_risk_level(msg.content),
      cwe_mappings: map_to_cwe_categories(msg.content, msg.file_type),
      analyzed_at: DateTime.utc_now()
    }

    {:ok, security_scan}
  end

  def analyze(message, _context) do
    {:error, {:unsupported_message_type, message.__struct__}}
  end

  @impl true
  def supported_types do
    [Analyze, SecurityScan]
  end

  @impl true
  def priority, do: :high

  @impl true
  def timeout, do: 15_000

  @impl true
  def metadata do
    %{
      name: "Security Analyzer",
      description: "Detects security vulnerabilities and unsafe patterns in code",
      version: "1.0.0",
      categories: [:security, :code],
      tags: ["security", "vulnerability", "safety", "authentication"]
    }
  end

  # Core security analysis functions extracted from CodeAnalysisSkill

  defp scan_for_vulnerabilities(content, file_type) when is_binary(content) do
    vulnerabilities = []

    vulnerabilities =
      if String.contains?(content, "eval(") || String.contains?(content, "Code.eval_string") do
        [
          %{type: :code_injection, severity: :critical, message: "Potential code injection"}
          | vulnerabilities
        ]
      else
        vulnerabilities
      end

    vulnerabilities =
      if Regex.match?(~r/password|secret|token|key.*=.*"[^"]+"/i, content) do
        [
          %{type: :hardcoded_secret, severity: :high, message: "Potential hardcoded secret"}
          | vulnerabilities
        ]
      else
        vulnerabilities
      end

    # Add file-type specific vulnerabilities
    vulnerabilities = add_file_type_vulnerabilities(vulnerabilities, content, file_type)

    vulnerabilities
  end

  defp scan_for_vulnerabilities(_, _), do: []

  defp add_file_type_vulnerabilities(vulnerabilities, content, :elixir) do
    vulnerabilities =
      if String.contains?(content, ":os.cmd") do
        [
          %{
            type: :os_command_injection,
            severity: :high,
            message: "OS command execution detected"
          }
          | vulnerabilities
        ]
      else
        vulnerabilities
      end

    vulnerabilities =
      if String.contains?(content, "String.to_atom") &&
           String.contains?(content, "params") do
        [
          %{
            type: :atom_injection,
            severity: :medium,
            message: "Unsafe atom creation from user input"
          }
          | vulnerabilities
        ]
      else
        vulnerabilities
      end

    # Check for SQL injection in string interpolation
    vulnerabilities =
      if Regex.match?(~r/Repo\.query\([^)]*#\{[^}]+\}/i, content) ||
           Regex.match?(~r/SELECT.*WHERE.*#\{[^}]+\}/i, content) ||
           Regex.match?(~r/"[^"]*WHERE[^"]*#\{[^}]+\}[^"]*"/i, content) do
        [
          %{
            type: :sql_injection,
            severity: :critical,
            message: "Potential SQL injection vulnerability"
          }
          | vulnerabilities
        ]
      else
        vulnerabilities
      end

    vulnerabilities
  end

  defp add_file_type_vulnerabilities(vulnerabilities, _content, _file_type), do: vulnerabilities

  defp detect_unsafe_operations(content) when is_binary(content) do
    unsafe_ops = []

    unsafe_ops =
      if String.contains?(content, "System.cmd") do
        [%{operation: "System.cmd", risk: :command_injection} | unsafe_ops]
      else
        unsafe_ops
      end

    unsafe_ops =
      if String.contains?(content, ":os.cmd") do
        [%{operation: ":os.cmd", risk: :command_injection} | unsafe_ops]
      else
        unsafe_ops
      end

    unsafe_ops =
      if String.contains?(content, "File.write!") &&
           String.contains?(content, "params") do
        [%{operation: "File.write!", risk: :file_write_injection} | unsafe_ops]
      else
        unsafe_ops
      end

    unsafe_ops =
      if String.contains?(content, "GenServer.call") &&
           String.contains?(content, "String.to_atom") do
        [%{operation: "Dynamic GenServer calls", risk: :process_injection} | unsafe_ops]
      else
        unsafe_ops
      end

    unsafe_ops
  end

  defp detect_unsafe_operations(_), do: []

  defp check_input_validation(content) when is_binary(content) do
    validation_patterns = [
      ~r/validate|changeset|cast/,
      ~r/Ecto\.Changeset/,
      ~r/validate_\w+/
    ]

    validated_inputs =
      validation_patterns
      |> Enum.map(&count_pattern(content, &1))
      |> Enum.sum()

    unvalidated_risks = detect_unvalidated_inputs(content)

    %{
      validated_inputs: validated_inputs,
      unvalidated_risks: unvalidated_risks,
      validation_score: calculate_validation_score(validated_inputs, unvalidated_risks),
      recommendation: suggest_validation_improvements(content)
    }
  end

  defp check_input_validation(_),
    do: %{validated_inputs: 0, unvalidated_risks: [], validation_score: 0.0}

  defp check_authentication_issues(content) when is_binary(content) do
    issues = []

    issues =
      if String.contains?(content, "skip_before_action :authenticate") do
        [%{type: :skipped_auth, message: "Authentication bypass detected"} | issues]
      else
        issues
      end

    issues =
      if String.contains?(content, "conn |> assign(:current_user, nil)") do
        [%{type: :auth_bypass, message: "Manual user assignment bypass"} | issues]
      else
        issues
      end

    issues =
      if Regex.match?(~r/session\[.*\]\s*=\s*nil/i, content) do
        [%{type: :session_invalidation, message: "Improper session invalidation"} | issues]
      else
        issues
      end

    issues
  end

  defp check_authentication_issues(_), do: []

  defp calculate_security_risk_level(content) when is_binary(content) do
    risk_score = 0

    risk_score = risk_score + if String.contains?(content, "eval"), do: 10, else: 0
    risk_score = risk_score + if String.contains?(content, "System.cmd"), do: 5, else: 0
    risk_score = risk_score + if Regex.match?(~r/password.*=.*"/i, content), do: 7, else: 0
    risk_score = risk_score + if String.contains?(content, ":os.cmd"), do: 6, else: 0
    risk_score = risk_score + if String.contains?(content, "skip_before_action"), do: 4, else: 0

    cond do
      risk_score >= 10 -> :critical
      risk_score >= 7 -> :high
      risk_score >= 4 -> :medium
      risk_score > 0 -> :low
      true -> :none
    end
  end

  defp calculate_security_risk_level(_), do: :none

  defp map_to_cwe_categories(content, file_type) when is_binary(content) do
    categories = []

    categories =
      if String.contains?(content, ["eval", "Code.eval"]) do
        ["CWE-94: Code Injection" | categories]
      else
        categories
      end

    categories =
      if String.contains?(content, "System.cmd") and file_type == :elixir do
        ["CWE-78: OS Command Injection" | categories]
      else
        categories
      end

    categories =
      if Regex.match?(~r/password|secret|token.*=.*"[^"]+"/i, content) do
        ["CWE-798: Use of Hard-coded Credentials" | categories]
      else
        categories
      end

    categories =
      if String.contains?(content, "String.to_atom") do
        ["CWE-400: Uncontrolled Resource Consumption" | categories]
      else
        categories
      end

    categories
  end

  defp map_to_cwe_categories(_, _), do: []

  # Helper functions

  defp get_content_from_context(%{file_path: file_path}, context) do
    # Try to get content from context first, then read file
    case Map.get(context, :content) do
      nil -> read_file_content(file_path)
      content -> content
    end
  end

  defp read_file_content(file_path) do
    case File.read(file_path) do
      {:ok, content} -> content
      {:error, _} -> ""
    end
  end

  defp detect_file_type(file_path) do
    cond do
      String.ends_with?(file_path, ".ex") -> :elixir
      String.ends_with?(file_path, ".exs") -> :elixir_script
      String.ends_with?(file_path, ".js") -> :javascript
      String.ends_with?(file_path, ".ts") -> :typescript
      String.ends_with?(file_path, ".py") -> :python
      String.ends_with?(file_path, ".rb") -> :ruby
      true -> :unknown
    end
  end

  defp count_pattern(content, pattern) do
    content
    |> String.split(pattern)
    |> length()
    |> Kernel.-(1)
    |> max(0)
  end

  defp detect_unvalidated_inputs(content) do
    risks = []

    # Check for direct parameter usage without validation
    risks =
      if String.contains?(content, "params[") && not String.contains?(content, "changeset") do
        [:direct_param_usage | risks]
      else
        risks
      end

    # Check for unsafe query building
    risks =
      if String.contains?(content, "from(") && String.contains?(content, "params") do
        [:unsafe_query_building | risks]
      else
        risks
      end

    # Check for direct database operations with user input
    risks =
      if (String.contains?(content, "Repo.get") || String.contains?(content, "Repo.update")) &&
           String.contains?(content, "params") do
        [:unsafe_database_operations | risks]
      else
        risks
      end

    risks
  end

  defp calculate_validation_score(validated_count, unvalidated_risks) do
    base_score = if validated_count > 0, do: 0.7, else: 0.0
    risk_penalty = length(unvalidated_risks) * 0.2

    (base_score - risk_penalty)
    |> max(0.0)
    |> min(1.0)
  end

  defp suggest_validation_improvements(content) do
    cond do
      String.contains?(content, "changeset") ->
        "Good validation practices detected"

      String.contains?(content, "params[") ->
        "Consider using Ecto changesets for input validation"

      String.contains?(content, "cast(") ->
        "Add validation functions to your changesets"

      true ->
        "Consider implementing input validation for user data"
    end
  end
end
