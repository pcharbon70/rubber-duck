# Orchestrator Documentation

## Overview

The Orchestrator (`RubberDuck.Analyzers.Orchestrator`) is the coordination layer that manages multiple code analyzers to provide comprehensive, intelligent code analysis. It handles execution planning, cross-analyzer insights, and recommendation prioritization.

## Core Responsibilities

1. **Execution Planning**: Creates optimal execution plans based on analysis requirements
2. **Analyzer Coordination**: Manages parallel and sequential analyzer execution
3. **Insight Generation**: Discovers patterns across multiple analyzer results
4. **Recommendation Engine**: Prioritizes and consolidates actionable recommendations
5. **Health Scoring**: Calculates overall code health metrics

## Execution Strategies

### Quick Strategy
- **Purpose**: Fast feedback for development workflows
- **Analyzers**: Quality only
- **Execution**: Single pass
- **Timeout**: 5 seconds
- **Use Case**: Pre-commit hooks, IDE integration

### Standard Strategy
- **Purpose**: Balanced analysis for regular checks
- **Analyzers**: Quality, Security, Performance
- **Execution**: Parallel where possible
- **Timeout**: 15 seconds
- **Use Case**: PR reviews, CI pipelines

### Deep Strategy
- **Purpose**: Comprehensive analysis
- **Analyzers**: All available
- **Execution**: Multi-phase with dependencies
- **Timeout**: 30 seconds
- **Use Case**: Release preparation, audits

### Focused Strategy
- **Purpose**: Target specific concerns
- **Analyzers**: Based on initial findings
- **Execution**: Adaptive phases
- **Timeout**: 20 seconds
- **Use Case**: Issue investigation

### Adaptive Strategy
- **Purpose**: Dynamic analysis based on discoveries
- **Analyzers**: Starts minimal, expands as needed
- **Execution**: Progressive enhancement
- **Timeout**: Variable
- **Use Case**: Unknown codebases

## Execution Flow

```elixir
# 1. Request arrives
request = %{
  file_path: "app.ex",
  content: code_content,
  analyzers: :all,
  strategy: :standard
}

# 2. Create execution plan
plan = create_execution_plan(request)
# Returns:
%{
  strategy: :standard,
  phases: [
    %{type: :parallel, analyzers: [:quality, :security]},
    %{type: :sequential, analyzers: [:performance, :impact]}
  ],
  timeout: 15000
}

# 3. Execute plan
results = execute_analysis_plan(plan, request)

# 4. Generate insights
insights = generate_cross_analyzer_insights(results)

# 5. Create recommendations
recommendations = generate_recommendations(results, insights)

# 6. Calculate health
health = calculate_overall_health(results)
```

## Cross-Analyzer Insights

The Orchestrator identifies patterns across analyzer results:

### Security-Performance Correlation
```elixir
%{
  type: :security_performance_tradeoff,
  message: "Security improvements may impact performance by ~15%",
  source_analyzers: [:security, :performance],
  confidence: 0.8
}
```

### Quality-Impact Correlation
```elixir
%{
  type: :complex_high_impact_change,
  message: "High complexity code has high change impact risk",
  source_analyzers: [:quality, :impact],
  confidence: 0.9
}
```

### Critical Code Health
```elixir
%{
  type: :critical_code_health,
  message: "Multiple critical issues require immediate attention",
  source_analyzers: [:security, :quality, :performance],
  confidence: 1.0
}
```

## Recommendation Engine

### Prioritization Algorithm

Recommendations are prioritized based on:

1. **Priority Score** (0-3)
   - Critical: 0
   - High: 1
   - Medium: 2
   - Low: 3

2. **Impact Score** (0-2)
   - High: 0
   - Medium: 1
   - Low: 2

3. **Effort Score** (0-2)
   - Low: 0
   - Medium: 1
   - High: 2

Combined score = (priority * 3) + (impact * 2) + effort

### Example Recommendations

```elixir
[
  %{
    action: "Fix SQL injection vulnerability in user_query/1",
    priority: :critical,
    impact: :high,
    effort: :low,
    analyzers: [:security]
  },
  %{
    action: "Refactor complex_calculation/3 to reduce complexity",
    priority: :medium,
    impact: :medium,
    effort: :medium,
    analyzers: [:quality, :performance]
  }
]
```

## Health Score Calculation

### Overall Health Formula
```elixir
overall = (security * 0.3) + 
          (performance * 0.2) + 
          (quality * 0.3) + 
          (maintainability * 0.2)
```

### Component Scores

- **Security**: 0.0 (critical issues) to 1.0 (no issues)
- **Performance**: Based on optimization potential
- **Quality**: Derived from complexity and coverage
- **Maintainability**: Calculated from MI index

## Configuration

### Request Options
```elixir
%{
  file_path: String.t(),           # Required
  content: String.t(),              # Optional (read from file if missing)
  analyzers: :all | [atom()],      # Analyzers to run
  strategy: atom(),                 # Execution strategy
  context: map(),                   # Additional context
  options: %{
    timeout: integer(),             # Max execution time
    auto_fix: boolean(),           # Apply automatic fixes
    parallel_execution: boolean()  # Enable parallel execution
  }
}
```

### Strategy Customization
```elixir
# Custom strategy
custom_strategy = %{
  name: :custom,
  phases: [
    %{type: :parallel, analyzers: [:security, :quality]},
    %{type: :conditional, 
     condition: &high_risk?/1,
     analyzers: [:impact]}
  ],
  timeout: 20000
}
```

## Error Handling

### Analyzer Failures
- Individual analyzer failures don't stop orchestration
- Failed analyzers return default/empty results
- Errors are logged and included in metadata

### Timeout Handling
- Each analyzer has individual timeout
- Overall orchestration timeout
- Graceful degradation on timeout

### Recovery Strategies
```elixir
# Fallback on analyzer failure
defp handle_analyzer_error(analyzer, error) do
  Logger.error("Analyzer #{analyzer} failed: #{inspect(error)}")
  get_default_result(analyzer)
end
```

## Performance Optimization

### Parallel Execution
- Independent analyzers run concurrently
- Task.async_stream with controlled concurrency
- Optimal for multi-core systems

### Caching
- Results cached by file path and content hash
- Cache invalidation on file changes
- Configurable cache TTL

### Lazy Loading
- Analyzers loaded on demand
- Content read only when needed
- Progressive result building

## Usage Examples

### Basic Orchestration
```elixir
alias RubberDuck.Analyzers.Orchestrator

request = %{
  file_path: "/lib/app.ex",
  content: File.read!("/lib/app.ex"),
  analyzers: :all,
  strategy: :standard
}

{:ok, result} = Orchestrator.orchestrate(request)
```

### Custom Analyzer Selection
```elixir
request = %{
  file_path: "/lib/critical.ex",
  analyzers: [:security, :quality],
  strategy: :focused
}

{:ok, result} = Orchestrator.orchestrate(request)
```

### With Context
```elixir
request = %{
  file_path: "/lib/module.ex",
  analyzers: :all,
  strategy: :adaptive,
  context: %{
    git_diff: git_diff_output,
    previous_analysis: last_result,
    user_preferences: user_config
  }
}

{:ok, result} = Orchestrator.orchestrate(request)
```

## Integration Points

### With CodeAnalysisSkill
```elixir
# CodeAnalysisSkill delegates to Orchestrator
def handle_analyze(msg, context) do
  request = build_orchestrator_request(msg, context)
  case Orchestrator.orchestrate(request) do
    {:ok, result} -> format_result(result)
    {:error, reason} -> handle_error(reason)
  end
end
```

### With CI/CD
```yaml
# GitHub Actions example
- name: Run Code Analysis
  run: |
    mix code.analyze \
      --strategy deep \
      --fail-on critical
```

## Monitoring and Metrics

### Key Metrics
- Analyzer execution times
- Strategy distribution
- Insight generation rate
- Recommendation acceptance rate
- Health score trends

### Logging
```elixir
Logger.info("Orchestration started", 
  strategy: strategy,
  analyzers: analyzers,
  file: file_path
)

Logger.debug("Phase completed",
  phase: phase_num,
  duration: duration_ms,
  results: length(results)
)
```

## Future Enhancements

1. **Machine Learning Integration**
   - Learn optimal strategies from historical data
   - Predict likely issues based on code patterns
   - Adaptive timeout adjustment

2. **Distributed Execution**
   - Run analyzers on multiple nodes
   - Horizontal scaling for large codebases
   - Result aggregation across nodes

3. **Real-time Analysis**
   - Stream processing for live coding
   - Incremental analysis on changes
   - WebSocket support for IDE integration

4. **Custom Strategies**
   - User-defined execution plans
   - Project-specific analyzer chains
   - Dynamic strategy selection

5. **Enhanced Insights**
   - ML-powered pattern detection
   - Historical trend analysis
   - Predictive issue detection