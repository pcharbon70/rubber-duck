# Quality Analyzer

## Overview

The Quality Analyzer (`RubberDuck.Analyzers.Code.Quality`) evaluates code quality, maintainability, and adherence to best practices. It provides comprehensive metrics and actionable recommendations for code improvement.

## Analysis Capabilities

### 1. Code Quality Metrics

#### Cyclomatic Complexity
- **Measurement**: Number of linearly independent paths through code
- **Range**: 1 (simple) to 20+ (very complex)
- **Threshold**: >10 triggers warnings, >15 critical

#### Lines of Code (LOC)
- **Measurement**: Non-comment, non-blank lines
- **Purpose**: Size and complexity indication
- **Consideration**: Context-dependent (utility vs business logic)

#### Code Duplication
- **Detection**: Similar code blocks and patterns
- **Measurement**: Percentage of duplicated code
- **Threshold**: >10% triggers recommendations

#### Documentation Coverage
- **Measurement**: Percentage of functions with @doc
- **Includes**: Module docs, function docs, type specs
- **Threshold**: <70% suggests improvement needed

### 2. Maintainability Assessment

#### Maintainability Index (MI)
Formula-based calculation considering:
- Halstead Volume (code complexity)
- Cyclomatic Complexity
- Lines of Code
- Comment density

**Scale**: 0-100 (higher is better)
- 85-100: Excellent maintainability
- 70-84: Good maintainability
- 50-69: Moderate maintainability
- 20-49: Difficult to maintain
- 0-19: Very difficult to maintain

### 3. Best Practices Assessment

#### Function Design
- Function length (lines)
- Parameter count
- Return value consistency
- Guard clause usage

#### Module Organization
- Module size
- Function count per module
- Proper separation of concerns
- Interface clarity

## Usage

### Direct Analysis

```elixir
alias RubberDuck.Analyzers.Code.Quality
alias RubberDuck.Messages.Code.QualityCheck

# Analyze code quality
message = %QualityCheck{
  target: "user_service.ex",
  metrics: [:complexity, :coverage, :duplication, :maintainability],
  thresholds: %{
    complexity: 10,
    coverage: 0.8,
    duplication: 0.1,
    maintainability: 70
  },
  context: %{
    content: """
    defmodule UserService do
      @moduledoc "Handles user-related operations"
      
      def create_user(attrs) when is_map(attrs) do
        with {:ok, validated} <- validate_attrs(attrs),
             {:ok, user} <- Repo.insert(%User{email: validated.email}),
             {:ok, profile} <- create_profile(user, validated) do
          {:ok, %{user | profile: profile}}
        else
          {:error, reason} -> {:error, reason}
        end
      end
      
      defp validate_attrs(%{email: email} = attrs) when is_binary(email) do
        if String.contains?(email, "@") do
          {:ok, attrs}
        else
          {:error, :invalid_email}
        end
      end
    end
    """
  }
}

{:ok, result} = Quality.analyze(message, %{})

# Result structure
%{
  quality_score: 0.85,              # Overall quality (0.0-1.0)
  maintainability_score: 0.82,      # Maintainability (0.0-1.0)
  
  metrics: %{
    loc: 23,                         # Lines of code
    complexity: 4,                   # Cyclomatic complexity
    coverage: 0.9,                   # Documentation coverage
    duplication: 0.02,               # Code duplication %
    maintainability_index: 78.5,     # MI score (0-100)
    documentation_coverage: 0.9       # @doc coverage
  },
  
  issues: [
    %{
      type: :complexity,
      severity: :medium,
      message: "Function 'create_user/1' has complexity of 4",
      line: 4,
      suggestion: "Consider breaking into smaller functions"
    }
  ],
  
  recommendations: [
    "Add @doc to private functions for better documentation",
    "Consider using Ecto.Changeset for validation",
    "Add @spec type specifications"
  ],
  
  suggestions: [
    %{
      type: :testing,
      priority: :high,
      action: "Increase test coverage",
      details: "Add unit tests for error paths and edge cases",
      effort: :medium,
      impact: :high
    }
  ],
  
  technical_debt_indicators: [
    %{
      type: :missing_specs,
      severity: :low,
      impact: "Reduced type safety and documentation"
    }
  ]
}
```

### Via Comprehensive Analysis

```elixir
alias RubberDuck.Messages.Code.Analyze

message = %Analyze{
  file_path: "/lib/complex_module.ex",
  analysis_type: :quality,
  depth: :deep
}

{:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)
```

## Quality Assessment Examples

### High-Quality Code

```elixir
defmodule HighQuality do
  @moduledoc """
  Example of well-written, maintainable code.
  
  This module demonstrates best practices for code quality.
  """
  
  @type user_attrs :: %{email: String.t(), name: String.t()}
  @type result :: {:ok, User.t()} | {:error, atom()}
  
  @doc """
  Creates a new user with the given attributes.
  
  ## Examples
  
      iex> create_user(%{email: "user@example.com", name: "John"})
      {:ok, %User{}}
      
      iex> create_user(%{email: "invalid", name: "John"})
      {:error, :invalid_email}
  """
  @spec create_user(user_attrs()) :: result()
  def create_user(attrs) when is_map(attrs) do
    with {:ok, validated} <- validate_user_attrs(attrs),
         {:ok, user} <- insert_user(validated) do
      {:ok, user}
    end
  end
  
  @spec validate_user_attrs(map()) :: {:ok, user_attrs()} | {:error, atom()}
  defp validate_user_attrs(%{email: email, name: name} = attrs) 
      when is_binary(email) and is_binary(name) do
    if valid_email?(email) do
      {:ok, attrs}
    else
      {:error, :invalid_email}
    end
  end
  
  @spec valid_email?(String.t()) :: boolean()
  defp valid_email?(email), do: String.contains?(email, "@")
end

# Quality Score: ~0.95
# - Excellent documentation
# - Proper type specifications
# - Good function decomposition
# - Low complexity
# - Clear error handling
```

### Poor-Quality Code

```elixir
defmodule PoorQuality do
  # No module documentation
  
  def do_stuff(x, y, z, a, b, c, d) do  # Too many parameters
    if x > 0 do
      if y > 0 do
        if z > 0 do
          if a > 0 do
            if b > 0 do
              if c > 0 do
                if d > 0 do
                  result = x + y + z + a + b + c + d
                  # Nested complexity: 7
                  Enum.reduce(1..100, result, fn i, acc ->
                    if rem(i, 2) == 0 do
                      acc + i
                    else
                      acc - i
                    end
                  end)
                else
                  -1
                end
              else
                -2
              end
            else
              -3
            end
          else
            -4
          end
        else
          -5
        end
      else
        -6
      end
    else
      -7
    end
  end
  
  # Duplicate code
  def process_a(data), do: data |> Enum.map(&(&1 * 2)) |> Enum.filter(&(&1 > 10))
  def process_b(data), do: data |> Enum.map(&(&1 * 2)) |> Enum.filter(&(&1 > 10))
end

# Quality Score: ~0.25
# - No documentation
# - High complexity (>15)
# - Too many parameters
# - Code duplication
# - Poor readability
```

## Quality Score Calculation

### Overall Quality Score Formula

```elixir
quality_score = (
  complexity_score * 0.3 +
  documentation_score * 0.25 +
  maintainability_score * 0.25 +
  duplication_score * 0.2
)
```

### Component Scores

#### Complexity Score
```elixir
complexity_score = case avg_complexity do
  c when c <= 5  -> 1.0
  c when c <= 10 -> 0.8
  c when c <= 15 -> 0.5
  _              -> 0.2
end
```

#### Documentation Score
```elixir
doc_score = documented_functions / total_functions
```

#### Duplication Score
```elixir
duplication_score = max(0, 1.0 - (duplication_percentage / 10.0))
```

## Technical Debt Detection

### Debt Indicators

1. **High Complexity**
   ```elixir
   %{
     type: :high_complexity,
     severity: :high,
     impact: "Difficult to test and maintain",
     functions: ["complex_calculation/5"]
   }
   ```

2. **Low Test Coverage**
   ```elixir
   %{
     type: :low_test_coverage,
     severity: :high,
     impact: "Increases risk of regressions",
     coverage: 0.45
   }
   ```

3. **Missing Documentation**
   ```elixir
   %{
     type: :missing_documentation,
     severity: :medium,
     impact: "Reduces code understandability",
     undocumented_count: 8
   }
   ```

4. **Code Duplication**
   ```elixir
   %{
     type: :code_duplication,
     severity: :medium,
     impact: "Maintenance burden and inconsistency risk",
     duplication_percentage: 15.2
   }
   ```

5. **Large Functions**
   ```elixir
   %{
     type: :large_functions,
     severity: :medium,
     impact: "Difficult to understand and test",
     functions: ["process_request/2", "handle_complex_case/3"]
   }
   ```

## Recommendations Engine

### Suggestion Categories

#### Testing Improvements
```elixir
%{
  type: :testing,
  priority: :high,
  action: "Increase test coverage",
  details: "Add unit tests for uncovered code paths, especially edge cases",
  effort: :medium,
  impact: :high
}
```

#### Documentation Improvements
```elixir
%{
  type: :documentation,
  priority: :medium,
  action: "Add missing documentation",
  details: "Add @doc and @spec to public functions",
  effort: :low,
  impact: :medium
}
```

#### Refactoring Suggestions
```elixir
%{
  type: :refactoring,
  priority: :high,
  action: "Reduce function complexity",
  details: "Break down complex_calculation/5 into smaller functions",
  effort: :high,
  impact: :high
}
```

#### Code Organization
```elixir
%{
  type: :organization,
  priority: :medium,
  action: "Extract common functionality",
  details: "Create shared module for duplicate validation logic",
  effort: :medium,
  impact: :medium
}
```

## Configuration Options

```elixir
quality_config = %{
  # Complexity thresholds
  complexity_warning: 10,
  complexity_critical: 15,
  
  # Documentation requirements
  doc_coverage_threshold: 0.7,
  require_module_docs: true,
  require_function_specs: false,
  
  # Duplication detection
  duplication_threshold: 0.1,
  minimum_duplicate_lines: 5,
  
  # Function size limits
  max_function_lines: 50,
  max_function_parameters: 5,
  
  # Maintainability
  maintainability_threshold: 70
}
```

## Best Practices Enforcement

### Function Design Rules

1. **Single Responsibility**: Functions should have one clear purpose
2. **Parameter Limits**: Maximum 4-5 parameters
3. **Return Consistency**: Consistent return patterns ({:ok, result} | {:error, reason})
4. **Guard Usage**: Use guards for input validation

### Module Organization Rules

1. **Size Limits**: Modules should be <500 lines
2. **Function Count**: <20 public functions per module
3. **Clear Interfaces**: Well-defined public API
4. **Separation of Concerns**: Business logic separated from I/O

### Documentation Standards

1. **Module Docs**: Every public module needs @moduledoc
2. **Function Docs**: Public functions need @doc
3. **Type Specs**: Complex functions need @spec
4. **Examples**: Include usage examples in docs

## Integration Examples

### Pre-commit Hook

```elixir
defmodule PreCommitQuality do
  def check_quality(changed_files) do
    results = Enum.map(changed_files, fn file ->
      message = %QualityCheck{
        target: file,
        metrics: [:complexity, :coverage],
        thresholds: %{complexity: 10, coverage: 0.7}
      }
      
      Quality.analyze(message, %{})
    end)
    
    failed = Enum.filter(results, &quality_check_failed?/1)
    
    if Enum.empty?(failed) do
      {:ok, "All quality checks passed"}
    else
      {:error, format_quality_errors(failed)}
    end
  end
end
```

### Code Review Integration

```elixir
defmodule CodeReviewQuality do
  def analyze_pr_diff(pr_diff) do
    quality_issues = []
    
    # Analyze complexity changes
    if complexity_increased?(pr_diff) do
      quality_issues = [complexity_warning(pr_diff) | quality_issues]
    end
    
    # Check for missing docs
    if new_functions_undocumented?(pr_diff) do
      quality_issues = [documentation_warning(pr_diff) | quality_issues]
    end
    
    quality_issues
  end
end
```

## Limitations

1. **Static Analysis Only**: Cannot measure runtime quality aspects
2. **Context Unaware**: May not understand business logic context
3. **Language Specific**: Optimized for Elixir patterns
4. **Metric Limitations**: Metrics are indicators, not absolute measures

## Future Enhancements

1. **Custom Rules**: Project-specific quality rules
2. **Historical Tracking**: Quality trends over time
3. **Team Standards**: Team-specific coding standards
4. **IDE Integration**: Real-time quality feedback
5. **Machine Learning**: Learn from code review patterns
6. **Cross-Module Analysis**: Dependencies and coupling analysis
7. **Performance Correlation**: Link quality metrics with performance
8. **Automated Fixes**: Suggest and apply code improvements