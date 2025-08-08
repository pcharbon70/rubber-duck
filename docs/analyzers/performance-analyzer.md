# Performance Analyzer

## Overview

The Performance Analyzer (`RubberDuck.Analyzers.Code.Performance`) identifies performance bottlenecks, analyzes algorithmic complexity, and suggests optimization opportunities in code.

## Analysis Capabilities

### 1. Algorithmic Complexity Analysis

#### Time Complexity Detection
- **Linear O(n)**: Single loops, simple iterations
- **Quadratic O(n²)**: Nested loops, cartesian products
- **Logarithmic O(log n)**: Binary search patterns
- **Exponential O(2^n)**: Recursive patterns without memoization
- **Constant O(1)**: Direct access, simple operations

#### Space Complexity Assessment
- **Constant**: Fixed memory usage
- **Linear**: Memory grows with input size
- **Quadratic**: Memory grows quadratically

### 2. Database Operation Analysis

#### Query Pattern Detection
- N+1 query problems
- Missing indexes (suggested)
- Inefficient joins
- Large result sets without pagination

#### Database Bottleneck Identification
```elixir
# Detected patterns
patterns = [
  "Repo.all without limit",
  "Nested Repo queries in loops",
  "Missing preload calls",
  "Inefficient where clauses"
]
```

### 3. Memory Usage Analysis

#### Memory Leak Detection
- Unclosed resources
- Large data structures in memory
- Improper GenServer state growth

#### Memory Optimization Opportunities
- Stream usage instead of Enum
- Lazy evaluation patterns
- Memory-efficient data structures

### 4. Bottleneck Identification

#### Common Bottlenecks
- File I/O operations
- Network calls in loops
- Synchronous processing of large datasets
- Inefficient pattern matching

## Usage

### Direct Analysis

```elixir
alias RubberDuck.Analyzers.Code.Performance
alias RubberDuck.Messages.Code.PerformanceAnalyze

# Analyze performance issues
message = %PerformanceAnalyze{
  content: """
  def slow_function(users) do
    Enum.map(users, fn user ->
      # N+1 query problem!
      posts = Repo.all(from p in Post, where: p.user_id == ^user.id)
      %{user: user, post_count: length(posts)}
    end)
  end
  """,
  metrics: [:complexity, :hotspots, :optimizations]
}

{:ok, result} = Performance.analyze(message, %{})

# Result structure
%{
  time_complexity: :linear,
  space_complexity: :linear,
  optimization_potential: 75,  # 0-100 scale
  bottlenecks: [
    "Database query in enumeration loop at line 3",
    "Potential N+1 query pattern detected"
  ],
  database_operations: [
    %{
      type: :query,
      pattern: "Repo.all in loop",
      line: 3,
      severity: :high,
      impact: "O(n) database calls"
    }
  ],
  optimization_opportunities: [
    %{
      pattern: "n_plus_one_queries",
      suggestion: "Use Repo.preload or join to fetch related data",
      impact: :high,
      effort: :medium
    }
  ],
  memory_analysis: %{
    estimated_usage: :moderate,
    growth_pattern: :linear,
    risk_level: :low
  }
}
```

### Via Comprehensive Analysis

```elixir
alias RubberDuck.Messages.Code.Analyze

message = %Analyze{
  file_path: "/lib/performance_critical.ex",
  analysis_type: :performance,
  depth: :deep
}

{:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)
```

## Complexity Analysis Examples

### Time Complexity Detection

#### Linear O(n)
```elixir
def linear_example(list) do
  Enum.map(list, &process_item/1)
end
# Detected: :linear
```

#### Quadratic O(n²)
```elixir
def quadratic_example(list) do
  Enum.map(list, fn item ->
    Enum.filter(list, &related_to?(&1, item))
  end)
end
# Detected: :quadratic
```

#### Logarithmic O(log n)
```elixir
def binary_search(list, target, low \\ 0, high \\ nil) do
  high = high || length(list) - 1
  if low <= high do
    mid = div(low + high, 2)
    case Enum.at(list, mid) do
      ^target -> mid
      val when val < target -> binary_search(list, target, mid + 1, high)
      _ -> binary_search(list, target, low, mid - 1)
    end
  end
end
# Detected: :logarithmic
```

#### Exponential O(2^n)
```elixir
def fibonacci(n) when n <= 1, do: n
def fibonacci(n), do: fibonacci(n - 1) + fibonacci(n - 2)
# Detected: :exponential (without memoization)
```

## Database Performance Analysis

### N+1 Query Detection

```elixir
# PROBLEMATIC: N+1 queries
def get_users_with_posts(user_ids) do
  users = Repo.all(from u in User, where: u.id in ^user_ids)
  Enum.map(users, fn user ->
    posts = Repo.all(from p in Post, where: p.user_id == ^user.id)  # N queries!
    %{user: user, posts: posts}
  end)
end

# OPTIMIZED: Single query
def get_users_with_posts_optimized(user_ids) do
  Repo.all(from u in User, 
    where: u.id in ^user_ids,
    preload: :posts
  )
end
```

### Query Analysis Results

```elixir
%{
  database_operations: [
    %{
      type: :query,
      pattern: "Repo.all in enumeration",
      line: 4,
      severity: :high,
      optimization: "Use preload or join",
      estimated_queries: "1 + N",
      impact: :high
    }
  ],
  optimization_opportunities: [
    %{
      pattern: "n_plus_one_queries",
      current_complexity: "O(n)",
      optimized_complexity: "O(1)",
      suggestion: "Replace with single query using preload"
    }
  ]
}
```

## Memory Analysis

### Memory Usage Patterns

```elixir
# MEMORY INEFFICIENT
def process_large_file(filename) do
  filename
  |> File.read!()           # Loads entire file into memory
  |> String.split("\n")     # Creates list of all lines
  |> Enum.map(&process_line/1)  # Processes all at once
end

# MEMORY EFFICIENT
def process_large_file_stream(filename) do
  filename
  |> File.stream!()         # Lazy stream
  |> Stream.map(&String.trim/1)
  |> Stream.map(&process_line/1)
  |> Enum.take(1000)        # Process in chunks
end
```

### Memory Analysis Results

```elixir
%{
  memory_analysis: %{
    estimated_usage: :high,
    growth_pattern: :linear,
    risk_level: :high,
    recommendations: [
      "Use File.stream! instead of File.read! for large files",
      "Consider Stream instead of Enum for large datasets"
    ]
  },
  optimization_opportunities: [
    %{
      pattern: "large_file_loading",
      impact: :high,
      suggestion: "Stream processing for memory efficiency"
    }
  ]
}
```

## Optimization Potential Scoring

The optimization potential is scored on a 0-100 scale:

### Scoring Components

1. **Complexity Issues** (0-50 points)
   - Exponential: +50
   - Quadratic: +30
   - Logarithmic: +10
   - Linear/Constant: +5

2. **Database Issues** (0-30 points)
   - N+1 queries: +30
   - Missing pagination: +20
   - Inefficient queries: +15

3. **Memory Issues** (0-20 points)
   - Large file loading: +20
   - Memory leaks: +18
   - Inefficient data structures: +10

### Score Interpretation

- **0-20**: Excellent performance
- **21-40**: Good performance, minor optimizations
- **41-60**: Moderate issues, optimizations recommended
- **61-80**: Significant issues, optimization needed
- **81-100**: Critical performance issues

## Configuration

Performance analysis can be configured:

```elixir
opts = %{
  performance_check: true,           # Enable/disable analysis
  complexity_threshold: :moderate,   # :low, :moderate, :high
  include_memory_analysis: true,     # Include memory patterns
  database_analysis: true,           # Analyze DB operations
  optimization_suggestions: true    # Include fix suggestions
}
```

## Best Practices

### For Developers

1. **Avoid N+1 Queries**
   ```elixir
   # Use preload or joins
   Repo.all(from u in User, preload: :posts)
   ```

2. **Use Streams for Large Data**
   ```elixir
   # Instead of Enum.map for large datasets
   Stream.map(large_list, &process/1) |> Enum.take(100)
   ```

3. **Minimize Database Roundtrips**
   ```elixir
   # Batch operations
   Repo.insert_all(User, user_data)
   ```

4. **Profile Critical Paths**
   ```elixir
   # Use :eprof, :fprof, or ExProf
   :eprof.profile(fn -> critical_function() end)
   ```

### For Performance Teams

1. Run deep performance analysis on critical paths
2. Set up automated performance regression testing
3. Monitor optimization potential scores over time
4. Establish performance budgets for new features

## Integration with Monitoring

### Performance Metrics Integration

```elixir
defmodule PerformanceMonitor do
  def track_analysis_results(file_path, performance_result) do
    metrics = %{
      optimization_potential: performance_result.optimization_potential,
      complexity: performance_result.time_complexity,
      bottlenecks_count: length(performance_result.bottlenecks),
      db_issues: length(performance_result.database_operations)
    }
    
    # Send to monitoring system
    TelemetryMetrics.emit([:code_analysis, :performance], metrics)
  end
end
```

### Alerting on Performance Issues

```elixir
def check_performance_regression(current_score, historical_score) do
  if current_score > historical_score + 20 do
    Alert.send(:performance_regression, %{
      file: file_path,
      current: current_score,
      historical: historical_score,
      difference: current_score - historical_score
    })
  end
end
```

## Limitations

1. **Static Analysis Only**: Cannot detect runtime performance issues
2. **Language Specific**: Optimized for Elixir patterns
3. **Context Dependent**: May not understand business logic context
4. **Estimation Based**: Complexity analysis is pattern-based, not precise

## Future Enhancements

1. **Runtime Integration**: Connect with application monitoring
2. **Benchmark Generation**: Create automated benchmarks
3. **Machine Learning**: Learn from performance patterns
4. **Profile Integration**: Import profiler data
5. **Custom Rules**: Project-specific performance rules
6. **Memory Profiling**: Real-time memory usage analysis
7. **Concurrency Analysis**: Detect concurrency bottlenecks

## Related Tools

- **ExProf**: Elixir profiler integration
- **Benchee**: Benchmark result correlation
- **Observer**: Live system monitoring
- **Recon**: Production debugging tools