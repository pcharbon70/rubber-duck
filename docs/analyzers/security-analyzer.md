# Security Analyzer

## Overview

The Security Analyzer (`RubberDuck.Analyzers.Code.Security`) identifies potential security vulnerabilities, unsafe patterns, and authentication issues in code.

## Detection Capabilities

### Vulnerability Types

#### 1. Code Injection
- **Pattern**: `eval()`, `Code.eval_string`
- **Severity**: Critical
- **Message**: "Potential code injection"

#### 2. SQL Injection
- **Patterns**:
  - `Repo.query()` with string interpolation
  - `SELECT...WHERE` with `#{}`
  - Query strings with embedded variables
- **Severity**: Critical
- **Message**: "Potential SQL injection vulnerability"

#### 3. Hardcoded Secrets
- **Pattern**: `password|secret|token|key.*=.*"[^"]+"`
- **Severity**: High
- **Message**: "Potential hardcoded secret"

#### 4. Command Injection
- **Patterns**:
  - `System.cmd()` with user input
  - `:os.cmd` execution
- **Severity**: High
- **Message**: "OS command execution detected"

#### 5. Atom Injection
- **Pattern**: `String.to_atom()` with user params
- **Severity**: Medium
- **Message**: "Unsafe atom creation from user input"

### Input Validation Assessment

The analyzer checks for:
- Unvalidated user inputs
- Missing parameter sanitization
- Direct use of external data
- SQL query construction patterns

### Authentication Issues

Detects:
- Hardcoded credentials
- Weak authentication patterns
- Missing authorization checks
- Session management issues

## Usage

### Direct Analysis

```elixir
alias RubberDuck.Analyzers.Code.Security
alias RubberDuck.Messages.Code.SecurityScan

# Analyze code content
message = %SecurityScan{
  content: """
  def unsafe_query(user_id) do
    Repo.query("SELECT * FROM users WHERE id = '\#{user_id}'")
  end
  """,
  file_type: :elixir
}

{:ok, result} = Security.analyze(message, %{})

# Result structure
%{
  vulnerabilities: [
    %{
      type: :sql_injection,
      severity: :critical,
      message: "Potential SQL injection vulnerability"
    }
  ],
  unsafe_operations: [],
  input_validation: %{
    validated_inputs: [],
    unvalidated_risks: ["user_id parameter"]
  },
  authentication_issues: [],
  risk_level: :critical,
  cwe_mappings: ["CWE-89"],
  analyzed_at: ~U[2024-01-15 10:30:00Z]
}
```

### Via Orchestrator

```elixir
alias RubberDuck.Messages.Code.Analyze

message = %Analyze{
  file_path: "/lib/vulnerable.ex",
  analysis_type: :security,
  depth: :deep
}

{:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)
```

## Risk Level Calculation

Risk levels are determined by:

1. **Critical**: Any critical vulnerability found
2. **High**: High-severity vulnerabilities or multiple medium issues
3. **Medium**: Medium-severity vulnerabilities
4. **Low**: Minor issues or suspicious patterns
5. **None**: No security issues detected

## CWE Mapping

The analyzer maps vulnerabilities to Common Weakness Enumeration (CWE) categories:

- **CWE-89**: SQL Injection
- **CWE-78**: OS Command Injection
- **CWE-94**: Code Injection
- **CWE-798**: Use of Hard-coded Credentials
- **CWE-502**: Deserialization of Untrusted Data

## Configuration

Security analysis can be configured through skill options:

```elixir
opts = %{
  security_scan: true,           # Enable/disable security analysis
  severity_threshold: :medium,   # Minimum severity to report
  include_cwe_mapping: true      # Include CWE references
}
```

## Best Practices

### For Developers

1. **Never interpolate user input directly into queries**
   ```elixir
   # Bad
   Repo.query("SELECT * FROM users WHERE id = '#{id}'")
   
   # Good
   Repo.query("SELECT * FROM users WHERE id = $1", [id])
   ```

2. **Avoid hardcoding secrets**
   ```elixir
   # Bad
   api_key = "sk-1234567890"
   
   # Good
   api_key = System.get_env("API_KEY")
   ```

3. **Validate all user inputs**
   ```elixir
   # Good
   def process_input(input) when is_binary(input) do
     sanitized = sanitize_input(input)
     # Process sanitized input
   end
   ```

### For Security Teams

1. Run deep security analysis on critical code paths
2. Configure CI/CD to fail on critical vulnerabilities
3. Regular security audits with comprehensive analysis
4. Track and remediate technical security debt

## Limitations

- Pattern-based detection may have false positives
- Cannot detect all runtime security issues
- Limited to static analysis capabilities
- Language-specific patterns (optimized for Elixir)

## Future Enhancements

1. **Taint Analysis**: Track data flow from sources to sinks
2. **SAST Integration**: Integrate with specialized security tools
3. **Custom Rules**: Allow project-specific security rules
4. **Remediation Suggestions**: Provide automated fixes
5. **Dependency Scanning**: Check for vulnerable dependencies