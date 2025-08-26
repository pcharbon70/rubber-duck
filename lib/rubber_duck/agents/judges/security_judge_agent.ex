defmodule RubberDuck.Agents.Judges.SecurityJudgeAgent do
  @moduledoc """
  Specialized judge agent for evaluating security aspects of code.

  Focuses on security vulnerabilities, data protection, authentication,
  authorization, input validation, and defensive programming practices.
  """

  use Jido.Agent, name: "SecurityJudge"

  require Logger

  @judgment_criteria [
    :input_validation,
    :authentication_security,
    :authorization_patterns,
    :data_protection,
    :secure_communications,
    :error_information_disclosure,
    :injection_vulnerabilities,
    :cryptographic_practices
  ]

  @security_patterns [
    :sql_injection,
    :xss_vulnerabilities,
    :csrf_vulnerabilities,
    :insecure_direct_object_references,
    :security_misconfiguration,
    :sensitive_data_exposure,
    :insufficient_logging,
    :using_known_vulnerable_components
  ]

  @impl true
  def init(opts \\ []) do
    state = %{
      specialization: :security,
      criteria_weights: get_default_weights(),
      evaluation_history: [],
      vulnerability_database: load_vulnerability_patterns(),
      security_standards: load_security_standards(),
      performance_metrics: %{
        evaluations_completed: 0,
        avg_evaluation_time: 0.0,
        confidence_trend: [],
        vulnerabilities_found: 0
      },
      configuration: Keyword.get(opts, :config, %{})
    }

    {:ok, state}
  end

  @doc """
  Evaluate security aspects of code.

  ## Parameters
  - `agent` - The judge agent instance
  - `code` - Code to evaluate
  - `context` - Additional context including dependencies
  - `options` - Evaluation options

  ## Returns
  - `{:ok, evaluation_result, updated_agent}` - Evaluation successful
  - `{:error, reason, agent}` - Evaluation failed
  """
  def evaluate_security(agent, code, context \\ %{}, options \\ []) do
    start_time = System.monotonic_time(:millisecond)

    Logger.info("Starting security evaluation")

    case perform_security_analysis(code, context, options, agent.state) do
      {:ok, analysis} ->
        evaluation_result = build_evaluation_result(analysis, agent.state.criteria_weights)
        end_time = System.monotonic_time(:millisecond)
        evaluation_time = end_time - start_time

        updated_agent = update_performance_metrics(agent, evaluation_result, evaluation_time)

        Logger.info("Security evaluation completed (#{evaluation_time}ms)")
        {:ok, evaluation_result, updated_agent}

      {:error, reason} ->
        Logger.error("Security evaluation failed: #{reason}")
        {:error, reason, agent}
    end
  end

  @doc """
  Get judge agent capabilities and specialization info.
  """
  def get_capabilities(agent) do
    %{
      specialization: agent.state.specialization,
      criteria: @judgment_criteria,
      security_patterns: @security_patterns,
      strengths: [
        "Vulnerability detection and assessment",
        "Authentication and authorization review",
        "Input validation analysis",
        "Cryptographic practice evaluation",
        "Data protection assessment"
      ],
      limitations: [
        "No dynamic security testing",
        "Limited penetration testing capabilities",
        "No network security analysis"
      ]
    }
  end

  @doc """
  Configure security evaluation criteria weights.
  """
  def configure_weights(agent, new_weights) do
    merged_weights = Map.merge(agent.state.criteria_weights, new_weights)
    updated_state = %{agent.state | criteria_weights: merged_weights}

    {:ok, %{agent | state: updated_state}}
  end

  ## Private Helper Functions

  defp perform_security_analysis(code, context, options, agent_state) do
    analysis_results = %{
      input_validation: analyze_input_validation(code, context),
      authentication_security: analyze_authentication(code, context),
      authorization_patterns: analyze_authorization(code, context),
      data_protection: analyze_data_protection(code, context),
      secure_communications: analyze_secure_communications(code, context),
      error_information_disclosure: analyze_error_disclosure(code),
      injection_vulnerabilities: analyze_injection_vulnerabilities(code, context),
      cryptographic_practices: analyze_cryptography(code, context)
    }

    security_issues = collect_security_issues(analysis_results)
    vulnerability_summary = summarize_vulnerabilities(security_issues)
    recommendations = generate_security_recommendations(analysis_results, vulnerability_summary)

    {:ok,
     %{
       criteria_scores: analysis_results,
       identified_issues: security_issues,
       vulnerability_summary: vulnerability_summary,
       recommendations: recommendations,
       analysis_metadata: %{
         lines_analyzed: count_lines(code),
         functions_analyzed: count_functions(code),
         critical_vulnerabilities: count_critical_vulnerabilities(security_issues),
         security_score_breakdown: calculate_score_breakdown(analysis_results)
       }
     }}
  end

  defp analyze_input_validation(code, context) do
    issues = []

    # Check for unvalidated user input
    unvalidated_inputs = find_unvalidated_inputs(code)

    issues =
      if length(unvalidated_inputs) > 0,
        do: ["Unvalidated user inputs detected" | issues],
        else: issues

    # Check for insufficient input sanitization
    sanitization_issues = check_input_sanitization(code)
    issues = issues ++ sanitization_issues

    # Check for type validation
    type_validation_issues = check_type_validation(code)
    issues = issues ++ type_validation_issues

    score =
      calculate_input_validation_score(
        unvalidated_inputs,
        sanitization_issues,
        type_validation_issues
      )

    %{
      score: score,
      issues: issues,
      confidence: 0.8
    }
  end

  defp analyze_authentication(code, context) do
    issues = []

    # Check for weak authentication mechanisms
    weak_auth = detect_weak_authentication(code, context)
    issues = issues ++ weak_auth

    # Check for hardcoded credentials
    hardcoded_creds = find_hardcoded_credentials(code)

    issues =
      if length(hardcoded_creds) > 0,
        do: ["Hardcoded credentials detected" | issues],
        else: issues

    # Check for session management issues
    session_issues = analyze_session_management(code, context)
    issues = issues ++ session_issues

    score = calculate_authentication_score(weak_auth, hardcoded_creds, session_issues)

    %{
      score: score,
      issues: issues,
      confidence: 0.9
    }
  end

  defp analyze_authorization(code, context) do
    issues = []

    # Check for missing authorization checks
    missing_authz = find_missing_authorization(code, context)
    issues = issues ++ missing_authz

    # Check for privilege escalation risks
    escalation_risks = detect_privilege_escalation(code, context)
    issues = issues ++ escalation_risks

    # Check for insecure direct object references
    idor_issues = detect_insecure_direct_references(code)
    issues = issues ++ idor_issues

    score = calculate_authorization_score(missing_authz, escalation_risks, idor_issues)

    %{
      score: score,
      issues: issues,
      confidence: 0.8
    }
  end

  defp analyze_data_protection(code, context) do
    issues = []

    # Check for sensitive data exposure
    sensitive_exposure = detect_sensitive_data_exposure(code)
    issues = issues ++ sensitive_exposure

    # Check for insecure data storage
    insecure_storage = analyze_data_storage_security(code, context)
    issues = issues ++ insecure_storage

    # Check for data encryption requirements
    encryption_issues = check_encryption_usage(code, context)
    issues = issues ++ encryption_issues

    score =
      calculate_data_protection_score(sensitive_exposure, insecure_storage, encryption_issues)

    %{
      score: score,
      issues: issues,
      confidence: 0.7
    }
  end

  defp analyze_secure_communications(code, context) do
    issues = []

    # Check for insecure communication protocols
    insecure_protocols = detect_insecure_protocols(code, context)
    issues = issues ++ insecure_protocols

    # Check for certificate validation
    cert_validation_issues = check_certificate_validation(code)
    issues = issues ++ cert_validation_issues

    # Check for secure headers
    header_issues = analyze_security_headers(code, context)
    issues = issues ++ header_issues

    score =
      calculate_communication_score(insecure_protocols, cert_validation_issues, header_issues)

    %{
      score: score,
      issues: issues,
      confidence: 0.8
    }
  end

  defp analyze_error_disclosure(code) do
    issues = []

    # Check for information disclosure in error messages
    info_disclosure = find_information_disclosure(code)
    issues = issues ++ info_disclosure

    # Check for stack trace exposure
    stack_trace_issues = detect_stack_trace_exposure(code)
    issues = issues ++ stack_trace_issues

    # Check for debug information leakage
    debug_leakage = find_debug_information_leakage(code)
    issues = issues ++ debug_leakage

    score = calculate_error_disclosure_score(info_disclosure, stack_trace_issues, debug_leakage)

    %{
      score: score,
      issues: issues,
      confidence: 0.9
    }
  end

  defp analyze_injection_vulnerabilities(code, context) do
    issues = []

    # Check for SQL injection vulnerabilities
    sql_injection = detect_sql_injection(code, context)
    issues = issues ++ sql_injection

    # Check for code injection
    code_injection = detect_code_injection(code)
    issues = issues ++ code_injection

    # Check for command injection
    command_injection = detect_command_injection(code)
    issues = issues ++ command_injection

    score = calculate_injection_score(sql_injection, code_injection, command_injection)

    %{
      score: score,
      issues: issues,
      confidence: 0.9
    }
  end

  defp analyze_cryptography(code, context) do
    issues = []

    # Check for weak cryptographic algorithms
    weak_crypto = detect_weak_cryptography(code)
    issues = issues ++ weak_crypto

    # Check for improper key management
    key_management_issues = analyze_key_management(code, context)
    issues = issues ++ key_management_issues

    # Check for random number generation
    rng_issues = check_random_number_generation(code)
    issues = issues ++ rng_issues

    score = calculate_cryptography_score(weak_crypto, key_management_issues, rng_issues)

    %{
      score: score,
      issues: issues,
      confidence: 0.8
    }
  end

  # Scoring helper functions

  defp calculate_input_validation_score(unvalidated, sanitization, type_validation) do
    base_score = 1.0
    deductions = 0.0

    # Critical issue
    deductions = deductions + length(unvalidated) * 0.3
    deductions = deductions + length(sanitization) * 0.2
    deductions = deductions + length(type_validation) * 0.1

    max(0.0, base_score - deductions)
  end

  defp calculate_authentication_score(weak_auth, hardcoded_creds, session_issues) do
    base_score = 1.0
    deductions = 0.0

    deductions = deductions + length(weak_auth) * 0.25
    # Very critical
    deductions = deductions + length(hardcoded_creds) * 0.4
    deductions = deductions + length(session_issues) * 0.2

    max(0.0, base_score - deductions)
  end

  defp calculate_authorization_score(missing_authz, escalation, idor) do
    base_score = 1.0
    deductions = 0.0

    deductions = deductions + length(missing_authz) * 0.3
    deductions = deductions + length(escalation) * 0.35
    deductions = deductions + length(idor) * 0.25

    max(0.0, base_score - deductions)
  end

  defp calculate_data_protection_score(sensitive_exposure, insecure_storage, encryption_issues) do
    base_score = 1.0
    deductions = 0.0

    deductions = deductions + length(sensitive_exposure) * 0.3
    deductions = deductions + length(insecure_storage) * 0.25
    deductions = deductions + length(encryption_issues) * 0.2

    max(0.0, base_score - deductions)
  end

  defp calculate_communication_score(insecure_protocols, cert_issues, header_issues) do
    base_score = 1.0
    deductions = 0.0

    deductions = deductions + length(insecure_protocols) * 0.3
    deductions = deductions + length(cert_issues) * 0.2
    deductions = deductions + length(header_issues) * 0.1

    max(0.0, base_score - deductions)
  end

  defp calculate_error_disclosure_score(info_disclosure, stack_trace, debug_leakage) do
    base_score = 1.0
    deductions = 0.0

    deductions = deductions + length(info_disclosure) * 0.2
    deductions = deductions + length(stack_trace) * 0.15
    deductions = deductions + length(debug_leakage) * 0.1

    max(0.0, base_score - deductions)
  end

  defp calculate_injection_score(sql_injection, code_injection, command_injection) do
    base_score = 1.0
    deductions = 0.0

    # Critical
    deductions = deductions + length(sql_injection) * 0.4
    # Critical
    deductions = deductions + length(code_injection) * 0.35
    # Critical
    deductions = deductions + length(command_injection) * 0.35

    max(0.0, base_score - deductions)
  end

  defp calculate_cryptography_score(weak_crypto, key_management, rng_issues) do
    base_score = 1.0
    deductions = 0.0

    deductions = deductions + length(weak_crypto) * 0.3
    deductions = deductions + length(key_management) * 0.25
    deductions = deductions + length(rng_issues) * 0.2

    max(0.0, base_score - deductions)
  end

  # Analysis implementation stubs (simplified for demo)

  defp find_unvalidated_inputs(code), do: []
  defp check_input_sanitization(code), do: []
  defp check_type_validation(code), do: []
  defp detect_weak_authentication(code, _context), do: []
  defp find_hardcoded_credentials(code), do: []
  defp analyze_session_management(code, _context), do: []
  defp find_missing_authorization(code, _context), do: []
  defp detect_privilege_escalation(code, _context), do: []
  defp detect_insecure_direct_references(code), do: []
  defp detect_sensitive_data_exposure(code), do: []
  defp analyze_data_storage_security(code, _context), do: []
  defp check_encryption_usage(code, _context), do: []
  defp detect_insecure_protocols(code, _context), do: []
  defp check_certificate_validation(code), do: []
  defp analyze_security_headers(code, _context), do: []
  defp find_information_disclosure(code), do: []
  defp detect_stack_trace_exposure(code), do: []
  defp find_debug_information_leakage(code), do: []
  defp detect_sql_injection(code, _context), do: []
  defp detect_code_injection(code), do: []
  defp detect_command_injection(code), do: []
  defp detect_weak_cryptography(code), do: []
  defp analyze_key_management(code, _context), do: []
  defp check_random_number_generation(code), do: []

  defp count_lines(code), do: length(String.split(code, "\n"))
  defp count_functions(code), do: 3

  defp count_critical_vulnerabilities(security_issues) do
    Enum.count(security_issues, fn issue ->
      Map.get(issue, :severity) == :critical
    end)
  end

  defp calculate_score_breakdown(analysis_results) do
    Enum.reduce(analysis_results, %{}, fn {criterion, result}, acc ->
      Map.put(acc, criterion, result.score)
    end)
  end

  defp load_vulnerability_patterns do
    # Would load from security database
    %{
      injection_patterns: ["eval", "exec", "system"],
      crypto_patterns: ["md5", "sha1", "des"],
      auth_patterns: ["hardcoded", "basic_auth", "no_encryption"]
    }
  end

  defp load_security_standards do
    # Would load security standards like OWASP Top 10
    %{
      owasp_top_10: [
        "Injection",
        "Broken Authentication",
        "Sensitive Data Exposure",
        "XML External Entities",
        "Broken Access Control",
        "Security Misconfiguration"
      ]
    }
  end

  defp build_evaluation_result(analysis, weights) do
    weighted_score = calculate_weighted_score(analysis.criteria_scores, weights)
    overall_confidence = calculate_overall_confidence(analysis.criteria_scores)

    %{
      score: weighted_score,
      confidence: overall_confidence,
      specialization: :security,
      issues: analysis.identified_issues,
      vulnerability_summary: analysis.vulnerability_summary,
      recommendations: analysis.recommendations,
      detailed_analysis: analysis.criteria_scores,
      metadata: analysis.analysis_metadata,
      evaluation_timestamp: DateTime.utc_now()
    }
  end

  defp calculate_weighted_score(criteria_scores, weights) do
    total_weight = Enum.reduce(weights, 0.0, fn {_criterion, weight}, acc -> acc + weight end)

    if total_weight > 0 do
      Enum.reduce(criteria_scores, 0.0, fn {criterion, result}, acc ->
        weight = Map.get(weights, criterion, 0.1)
        normalized_weight = weight / total_weight
        acc + result.score * normalized_weight
      end)
    else
      0.5
    end
  end

  defp calculate_overall_confidence(criteria_scores) do
    confidences = Enum.map(criteria_scores, fn {_criterion, result} -> result.confidence end)
    if length(confidences) > 0, do: Enum.sum(confidences) / length(confidences), else: 0.5
  end

  defp collect_security_issues(analysis_results) do
    Enum.flat_map(analysis_results, fn {criterion, result} ->
      issues = Map.get(result, :issues, [])

      Enum.map(issues, fn issue ->
        %{
          criterion: criterion,
          description: issue,
          severity: determine_security_severity(issue, criterion),
          category: :security
        }
      end)
    end)
  end

  defp summarize_vulnerabilities(security_issues) do
    by_severity = Enum.group_by(security_issues, & &1.severity)

    %{
      critical: length(Map.get(by_severity, :critical, [])),
      high: length(Map.get(by_severity, :high, [])),
      medium: length(Map.get(by_severity, :medium, [])),
      low: length(Map.get(by_severity, :low, [])),
      total: length(security_issues)
    }
  end

  defp generate_security_recommendations(analysis_results, vulnerability_summary) do
    base_recommendations = [
      "Implement comprehensive input validation",
      "Review authentication and authorization mechanisms",
      "Ensure sensitive data is properly protected",
      "Use secure communication protocols"
    ]

    # Add severity-based recommendations
    severity_recs =
      if vulnerability_summary.critical > 0 do
        ["URGENT: Address critical security vulnerabilities immediately"]
      else
        []
      end

    base_recommendations ++ severity_recs
  end

  defp determine_security_severity(issue, criterion) do
    cond do
      String.contains?(issue, ["injection", "credentials", "escalation"]) -> :critical
      String.contains?(issue, ["authentication", "authorization", "exposure"]) -> :high
      String.contains?(issue, ["validation", "encryption", "protocol"]) -> :medium
      true -> :low
    end
  end

  defp get_default_weights do
    %{
      input_validation: 1.4,
      authentication_security: 1.5,
      authorization_patterns: 1.4,
      data_protection: 1.3,
      secure_communications: 1.0,
      error_information_disclosure: 0.8,
      # Highest weight
      injection_vulnerabilities: 1.6,
      cryptographic_practices: 1.2
    }
  end

  defp update_performance_metrics(agent, evaluation_result, evaluation_time) do
    metrics = agent.state.performance_metrics

    new_count = metrics.evaluations_completed + 1

    new_avg_time =
      (metrics.avg_evaluation_time * metrics.evaluations_completed + evaluation_time) / new_count

    new_confidence_trend = [evaluation_result.confidence | Enum.take(metrics.confidence_trend, 9)]
    new_vulnerabilities = metrics.vulnerabilities_found + length(evaluation_result.issues)

    updated_metrics = %{
      evaluations_completed: new_count,
      avg_evaluation_time: new_avg_time,
      confidence_trend: new_confidence_trend,
      vulnerabilities_found: new_vulnerabilities
    }

    %{agent | state: %{agent.state | performance_metrics: updated_metrics}}
  end
end
