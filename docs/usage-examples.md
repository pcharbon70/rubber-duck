# Code Analysis System - Usage Examples

## Basic Usage

### 1. Simple Quality Check

```elixir
alias RubberDuck.Messages.Code.QualityCheck
alias RubberDuck.Skills.CodeAnalysisSkill

# Check code quality
message = %QualityCheck{
  target: "my_module.ex",
  metrics: [:complexity, :coverage, :duplication],
  thresholds: %{
    complexity: 10,
    coverage: 0.8,
    duplication: 0.1
  }
}

{:ok, result} = CodeAnalysisSkill.handle_quality_check(message, %{})

# Result
%{
  quality_score: 0.75,
  metrics: %{
    complexity: 8,
    coverage: 0.85,
    duplication: 0.05,
    maintainability_index: 82.3,
    documentation_coverage: 0.9
  },
  issues: [
    %{
      type: :complexity,
      severity: :medium,
      message: "Function 'process_data/2' has complexity of 12",
      line: 45
    }
  ],
  recommendations: [
    "Consider breaking down complex functions",
    "Add tests for uncovered branches"
  ]
}
```

### 2. Security Vulnerability Scan

```elixir
alias RubberDuck.Messages.Code.SecurityScan

vulnerable_code = """
defmodule UserController do
  def search(conn, %{"query" => query}) do
    # SQL injection vulnerability!
    results = Repo.query("SELECT * FROM users WHERE name LIKE '%\#{query}%'")
    render(conn, "search.html", results: results)
  end
  
  def authenticate(conn, params) do
    # Hardcoded secret!
    secret_key = "sk-1234567890abcdef"
    token = generate_token(params.username, secret_key)
    conn |> put_session(:token, token)
  end
end
"""

message = %SecurityScan{
  content: vulnerable_code,
  file_type: :elixir
}

{:ok, result} = Security.analyze(message, %{})

# Result shows critical vulnerabilities
%{
  vulnerabilities: [
    %{
      type: :sql_injection,
      severity: :critical,
      message: "Potential SQL injection vulnerability",
      line: 4
    },
    %{
      type: :hardcoded_secret,
      severity: :high,
      message: "Potential hardcoded secret",
      line: 10
    }
  ],
  risk_level: :critical,
  cwe_mappings: ["CWE-89", "CWE-798"]
}
```

### 3. Comprehensive Analysis

```elixir
alias RubberDuck.Messages.Code.Analyze

# Analyze entire file with all analyzers
message = %Analyze{
  file_path: "/lib/critical_module.ex",
  analysis_type: :comprehensive,
  depth: :deep,
  auto_fix: false,
  context: %{
    content: File.read!("/lib/critical_module.ex"),
    git_branch: "feature/new-feature",
    author: "developer@example.com"
  }
}

{:ok, result} = CodeAnalysisSkill.handle_analyze(message, %{})

# Comprehensive result
%{
  file: "/lib/critical_module.ex",
  quality_score: 0.72,
  
  # Individual analyzer results
  quality: %{
    quality_score: 0.72,
    complexity: 15,
    issues: [...],
    maintainability_score: 0.68
  },
  
  security: %{
    vulnerabilities: [...],
    risk_level: :medium,
    recommendations: [...]
  },
  
  performance: %{
    optimization_potential: 35,
    bottlenecks: [...],
    time_complexity: :quadratic
  },
  
  impact: %{
    scope: :moderate,
    severity: :medium,
    dependencies: %{
      direct: 5,
      transitive: 23
    }
  },
  
  # Cross-analyzer insights
  insights: [
    %{
      type: :security_performance_tradeoff,
      message: "Security fixes may impact performance",
      confidence: 0.8
    }
  ],
  
  # Overall health metrics
  overall_health: %{
    overall: 0.65,
    security: 0.5,
    performance: 0.7,
    quality: 0.72,
    maintainability: 0.68
  }
}
```

## Advanced Usage

### 4. Performance-Focused Analysis

```elixir
alias RubberDuck.Messages.Code.PerformanceAnalyze

slow_code = """
def process_large_dataset(data) do
  # Nested loops - O(n²) complexity
  Enum.map(data, fn item ->
    Enum.map(data, fn other ->
      if item.id != other.id do
        calculate_similarity(item, other)
      end
    end)
  end)
end
"""

message = %PerformanceAnalyze{
  content: slow_code,
  metrics: [:complexity, :hotspots, :optimizations]
}

{:ok, result} = Performance.analyze(message, %{})

# Performance analysis result
%{
  time_complexity: :quadratic,
  space_complexity: :linear,
  optimization_potential: 65,
  bottlenecks: [
    "Nested enumeration at line 3-9"
  ],
  optimization_opportunities: [
    %{
      pattern: "nested_enumeration",
      suggestion: "Consider using a more efficient algorithm",
      impact: :high
    }
  ]
}
```

### 5. Impact Assessment for Changes

```elixir
alias RubberDuck.Messages.Code.ImpactAssess

# Assess impact of code changes
message = %ImpactAssess{
  file_path: "/lib/core/user.ex",
  changes: %{
    lines_added: 50,
    lines_removed: 20,
    functions_modified: ["authenticate/2", "validate/1"],
    breaking_changes: true
  }
}

{:ok, result} = Impact.analyze(message, %{state: app_state})

# Impact assessment result
%{
  scope: :extensive,
  severity: :high,
  dependency_impact: %{
    direct_dependencies: 8,
    transitive_dependencies: 45,
    affected_modules: [
      "UserController",
      "AuthService",
      "SessionManager"
    ]
  },
  risk_assessment: %{
    level: :high,
    factors: [
      "Breaking API changes",
      "Core authentication modified",
      "High dependency count"
    ]
  },
  estimated_effort: :significant,
  rollback_complexity: :complex
}
```

## Integration Examples

### 6. CI/CD Pipeline Integration

```elixir
defmodule CI.CodeQualityCheck do
  alias RubberDuck.Messages.Code.Analyze
  alias RubberDuck.Skills.CodeAnalysisSkill
  
  def check_pull_request(pr_files) do
    results = Enum.map(pr_files, fn file ->
      message = %Analyze{
        file_path: file.path,
        analysis_type: :comprehensive,
        depth: :moderate,
        context: %{content: file.content}
      }
      
      case CodeAnalysisSkill.handle_analyze(message, %{}) do
        {:ok, result} -> {file.path, result}
        {:error, reason} -> {file.path, {:error, reason}}
      end
    end)
    
    # Aggregate results
    aggregate_results(results)
  end
  
  defp aggregate_results(results) do
    {passed, failed} = Enum.split_with(results, fn {_, result} ->
      case result do
        {:error, _} -> false
        result -> 
          result.overall_health.security >= 0.7 and
          result.quality_score >= 0.6
      end
    end)
    
    %{
      passed: length(passed),
      failed: length(failed),
      total_issues: count_issues(results),
      requires_review: length(failed) > 0
    }
  end
end
```

### 7. IDE Integration Example

```elixir
defmodule IDE.CodeAnalyzer do
  use GenServer
  alias RubberDuck.Messages.Code.Analyze
  
  def analyze_on_save(file_path, content) do
    GenServer.cast(__MODULE__, {:analyze, file_path, content})
  end
  
  def handle_cast({:analyze, file_path, content}, state) do
    # Quick analysis for immediate feedback
    message = %Analyze{
      file_path: file_path,
      analysis_type: :comprehensive,
      depth: :shallow,  # Quick for IDE
      context: %{content: content}
    }
    
    case CodeAnalysisSkill.handle_analyze(message, %{}) do
      {:ok, result} ->
        # Send results to IDE
        send_to_ide(format_for_ide(result))
        
      {:error, _reason} ->
        # Silent fail for IDE
        :ok
    end
    
    {:noreply, state}
  end
  
  defp format_for_ide(result) do
    %{
      diagnostics: convert_to_diagnostics(result.issues),
      quick_fixes: generate_quick_fixes(result.suggestions),
      health_badge: health_to_badge(result.overall_health.overall)
    }
  end
end
```

### 8. Batch Analysis for Codebase Audit

```elixir
defmodule Audit.CodebaseAnalyzer do
  alias RubberDuck.Messages.Code.Analyze
  require Logger
  
  def audit_codebase(directory) do
    directory
    |> find_elixir_files()
    |> Task.async_stream(&analyze_file/1, 
        max_concurrency: System.schedulers_online(),
        timeout: 30_000)
    |> Enum.reduce(%{total: 0, by_health: %{}}, fn
      {:ok, result}, acc ->
        update_statistics(acc, result)
      {:exit, :timeout}, acc ->
        Logger.warn("Analysis timeout")
        acc
    end)
    |> generate_report()
  end
  
  defp analyze_file(file_path) do
    message = %Analyze{
      file_path: file_path,
      analysis_type: :comprehensive,
      depth: :moderate
    }
    
    case CodeAnalysisSkill.handle_analyze(message, %{}) do
      {:ok, result} -> 
        %{
          file: file_path,
          health: result.overall_health.overall,
          issues: length(result.issues),
          category: categorize_health(result.overall_health.overall)
        }
      {:error, _} -> 
        %{file: file_path, health: 0, issues: 0, category: :error}
    end
  end
  
  defp categorize_health(score) do
    cond do
      score >= 0.9 -> :excellent
      score >= 0.7 -> :good
      score >= 0.5 -> :needs_improvement
      true -> :critical
    end
  end
end
```

### 9. Custom Analysis Pipeline

```elixir
defmodule CustomPipeline do
  alias RubberDuck.Analyzers.Orchestrator
  
  def analyze_with_context(file_path, pr_context) do
    # Custom orchestrator request
    request = %{
      file_path: file_path,
      content: File.read!(file_path),
      analyzers: determine_analyzers(pr_context),
      strategy: determine_strategy(pr_context),
      context: %{
        pr_title: pr_context.title,
        pr_labels: pr_context.labels,
        changed_files: pr_context.files,
        previous_issues: get_previous_issues(file_path)
      },
      options: %{
        timeout: 20_000,
        auto_fix: pr_context.auto_fix_enabled
      }
    }
    
    case Orchestrator.orchestrate(request) do
      {:ok, result} ->
        result
        |> filter_relevant_issues(pr_context)
        |> apply_team_preferences(pr_context.team)
        |> format_for_review()
        
      {:error, reason} ->
        Logger.error("Analysis failed: #{inspect(reason)}")
        default_response()
    end
  end
  
  defp determine_analyzers(%{labels: labels}) do
    cond do
      "security" in labels -> [:security, :quality]
      "performance" in labels -> [:performance, :quality]
      "hotfix" in labels -> [:security]
      true -> :all
    end
  end
  
  defp determine_strategy(%{labels: labels}) do
    cond do
      "urgent" in labels -> :quick
      "release" in labels -> :deep
      true -> :standard
    end
  end
end
```

## Testing Examples

### 10. Testing Analyzer Results

```elixir
defmodule CodeAnalysisTest do
  use ExUnit.Case
  alias RubberDuck.Messages.Code.Analyze
  
  test "detects SQL injection vulnerability" do
    vulnerable_code = """
    def search(query) do
      Repo.query("SELECT * FROM users WHERE name = '\#{query}'")
    end
    """
    
    message = %Analyze{
      file_path: "test.ex",
      analysis_type: :security,
      depth: :deep
    }
    
    assert {:ok, result} = CodeAnalysisSkill.handle_analyze(
      message, 
      %{content: vulnerable_code}
    )
    
    assert length(result.security.vulnerabilities) > 0
    assert Enum.any?(result.security.vulnerabilities, fn vuln ->
      vuln.type == :sql_injection
    end)
  end
  
  test "calculates correct health score" do
    good_code = """
    defmodule WellWritten do
      @moduledoc "Good documentation"
      
      def simple_function(x) when is_integer(x) do
        x * 2
      end
    end
    """
    
    message = %Analyze{
      file_path: "good.ex",
      analysis_type: :comprehensive,
      depth: :moderate
    }
    
    assert {:ok, result} = CodeAnalysisSkill.handle_analyze(
      message,
      %{content: good_code}
    )
    
    assert result.overall_health.overall > 0.8
    assert result.overall_health.security == 1.0
  end
end
```

## Performance Tips

1. **Use appropriate depth**: 
   - `:shallow` for real-time feedback
   - `:moderate` for regular checks
   - `:deep` for thorough audits

2. **Select specific analyzers** when you know what you need:
   ```elixir
   # Just security check
   %Analyze{analysis_type: :security, ...}
   ```

3. **Batch operations** for multiple files:
   ```elixir
   files |> Task.async_stream(&analyze/1, max_concurrency: 4)
   ```

4. **Cache results** for unchanged files:
   ```elixir
   if file_unchanged?(file) do
     get_cached_result(file)
   else
     perform_analysis(file)
   end
   ```

5. **Use timeout protection**:
   ```elixir
   Task.yield(analysis_task, 5000) || {:error, :timeout}
   ```