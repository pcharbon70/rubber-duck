# Migration Guide: From Legacy Signals to Typed Messages

## Overview

This guide helps you migrate from the legacy string-based signal system to the new typed message system in the CodeAnalysisSkill v3.0.

## Key Changes

### Before (Legacy Signals - v2.x)
- String-based signal types: `"code.analyze.file"`
- Untyped data maps
- Signal pattern matching: `"code.*"`
- Runtime type checking

### After (Typed Messages - v3.0)
- Strongly-typed message structs
- Compile-time validation
- Direct message routing
- Pattern matching via infrastructure

## Migration Steps

### Step 1: Update Dependencies

Ensure you have the latest version:

```elixir
# mix.exs
defp deps do
  [
    {:rubber_duck, "~> 0.3.0"},
    # ...
  ]
end
```

### Step 2: Replace Signal Emissions

#### Before (Legacy)
```elixir
# Emitting a signal
emit_signal("code.analyze.file", %{
  file_path: "/lib/module.ex",
  depth: "deep"
})

emit_signal("code.security.scan", %{
  content: code_content
})

emit_signal("code.quality.check", %{
  target: "module.ex"
})
```

#### After (Typed Messages)
```elixir
# Import message modules
alias RubberDuck.Messages.Code.{Analyze, SecurityScan, QualityCheck}

# Create and route typed messages
message = %Analyze{
  file_path: "/lib/module.ex",
  analysis_type: :comprehensive,
  depth: :deep,
  auto_fix: false
}
{:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)

# Security scan
security_msg = %SecurityScan{
  content: code_content,
  file_type: :elixir
}
{:ok, result} = Security.analyze(security_msg, %{})

# Quality check
quality_msg = %QualityCheck{
  target: "module.ex",
  metrics: [:complexity, :coverage],
  thresholds: %{}
}
{:ok, result} = CodeAnalysisSkill.handle_quality_check(quality_msg, %{})
```

### Step 3: Update Signal Handlers

#### Before (Legacy)
```elixir
defmodule MySkill do
  use RubberDuck.Skills.Base,
    signal_patterns: [
      "code.analyze.*",
      "code.quality.*"
    ]
  
  def handle_signal(%{type: "code.analyze.file"} = signal, state) do
    data = signal[:data]
    # Process untyped data
    result = analyze_code(data[:file_path], data[:depth])
    {:ok, result, state}
  end
  
  def handle_signal(%{type: "code.quality.check"} = signal, state) do
    # Handle quality check
    {:ok, check_quality(signal.data), state}
  end
end
```

#### After (Typed Messages)
```elixir
defmodule MySkill do
  use RubberDuck.Skills.Base,
    name: "my_skill",
    description: "My analysis skill",
    category: "development"
    # No signal_patterns needed!
  
  alias RubberDuck.Messages.Code.{Analyze, QualityCheck}
  
  # Implement typed message handlers
  def handle_analyze(%Analyze{} = msg, context) do
    # Strongly-typed access
    result = analyze_code(msg.file_path, msg.depth)
    {:ok, result}
  end
  
  def handle_quality_check(%QualityCheck{} = msg, _context) do
    # Direct field access with compile-time checking
    {:ok, check_quality(msg.target, msg.metrics)}
  end
end
```

### Step 4: Update Tests

#### Before (Legacy)
```elixir
test "handles code analysis signal" do
  signal = %{
    type: "code.analyze.file",
    data: %{
      file_path: "test.ex",
      content: @test_code
    }
  }
  
  assert {:ok, result, _state} = MySkill.handle_signal(signal, %{})
  assert result.quality_score > 0
end
```

#### After (Typed Messages)
```elixir
test "handles code analysis message" do
  message = %Analyze{
    file_path: "test.ex",
    analysis_type: :comprehensive,
    depth: :moderate,
    auto_fix: false
  }
  
  context = %{content: @test_code}
  
  assert {:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)
  assert result.quality_score > 0
end
```

### Step 5: Handle Wildcard Patterns

If you were using wildcard patterns, they're now handled at the infrastructure level:

#### Before (Legacy)
```elixir
# Skill registered for "code.*"
signal_patterns: ["code.*"]

# Would receive all code.* signals
def handle_signal(%{type: "code." <> _subtype} = signal, state) do
  # Handle any code signal
end
```

#### After (Typed Messages)
```elixir
# Wildcard routing handled by PatternMatcher
# Your skill implements specific handlers

def handle_analyze(%Analyze{}, context), do: # ...
def handle_quality_check(%QualityCheck{}, context), do: # ...
def handle_security_scan(%SecurityScan{}, context), do: # ...

# Infrastructure routes based on message type
```

## Common Migration Patterns

### Pattern 1: Conditional Analysis Types

#### Before
```elixir
def handle_signal(%{type: "code.analyze.file", data: data}, state) do
  result = case data[:analysis_type] do
    "security" -> run_security_analysis(data)
    "performance" -> run_performance_analysis(data)
    _ -> run_comprehensive_analysis(data)
  end
  {:ok, result, state}
end
```

#### After
```elixir
def handle_analyze(%Analyze{analysis_type: :security} = msg, context) do
  {:ok, run_security_analysis(msg, context)}
end

def handle_analyze(%Analyze{analysis_type: :performance} = msg, context) do
  {:ok, run_performance_analysis(msg, context)}
end

def handle_analyze(%Analyze{} = msg, context) do
  {:ok, run_comprehensive_analysis(msg, context)}
end
```

### Pattern 2: Data Validation

#### Before
```elixir
def handle_signal(%{type: "code.analyze.file", data: data}, state) do
  # Manual validation
  unless data[:file_path] do
    {:error, :missing_file_path, state}
  end
  
  unless data[:depth] in ["shallow", "moderate", "deep"] do
    {:error, :invalid_depth, state}
  end
  
  # Process if valid
  {:ok, analyze(data), state}
end
```

#### After
```elixir
# Validation happens at message creation
message = %Analyze{
  file_path: "/lib/file.ex",  # Required field
  analysis_type: :comprehensive,
  depth: :moderate  # Type-checked atom
}

# Message protocol validates
case Message.validate(message) do
  {:ok, valid_msg} -> handle_analyze(valid_msg, context)
  {:error, reason} -> {:error, reason}
end
```

### Pattern 3: Async Processing

#### Before
```elixir
def handle_signal(%{type: "code.analyze.file"} = signal, state) do
  Task.start(fn ->
    result = perform_analysis(signal.data)
    emit_signal("code.analysis.complete", result)
  end)
  {:ok, state}
end
```

#### After
```elixir
def handle_analyze(%Analyze{} = msg, context) do
  Task.start(fn ->
    result = perform_analysis(msg, context)
    # Return result directly or via callback
    send(context.reply_to, {:analysis_complete, result})
  end)
  {:ok, %{status: :processing}}
end
```

## Backward Compatibility

### Using SignalAdapter

For gradual migration, use the SignalAdapter:

```elixir
alias RubberDuck.Adapters.SignalAdapter

# Convert legacy signal to typed message
signal = %{type: "code.analyze.file", data: %{file_path: "test.ex"}}
{:ok, message} = SignalAdapter.from_signal(signal)

# Convert typed message to signal (if needed)
{:ok, signal} = SignalAdapter.to_signal(message)
```

### Dual-Mode Skills

During migration, skills can support both:

```elixir
defmodule TransitionSkill do
  # Handle typed messages
  def handle_analyze(%Analyze{} = msg, context) do
    {:ok, process_analyze(msg)}
  end
  
  # Legacy signal support (deprecated)
  def handle_signal(%{type: "code.analyze.file"} = signal, state) do
    # Convert to typed message
    {:ok, msg} = SignalAdapter.from_signal(signal)
    {:ok, result} = handle_analyze(msg, %{})
    {:ok, result, state}
  end
end
```

## Benefits of Migration

1. **Compile-time Safety**: Catch errors during compilation
2. **Better IDE Support**: Autocomplete and type information
3. **Clear Contracts**: Explicit message structure
4. **Easier Testing**: Create test messages easily
5. **Performance**: No runtime string matching

## Troubleshooting

### Issue: "Unknown signal type"
**Solution**: Register the message type in the Registry or use SignalAdapter

### Issue: "Missing required field"
**Solution**: Typed messages enforce required fields - ensure all are provided

### Issue: "Pattern not matched"
**Solution**: Implement specific handlers for each message type

### Issue: "State vs Context confusion"
**Solution**: 
- Context = test/analysis context (includes content)
- State = skill state (for Base module integration)

## Getting Help

1. Check the [Architecture Documentation](./architecture/code-analysis-system.md)
2. Review [Usage Examples](./usage-examples.md)
3. Consult the [API Reference](./api-reference.md)
4. Open an issue in the repository

## Deprecation Timeline

- **v2.x**: Legacy signals supported (current)
- **v3.0**: Typed messages introduced, legacy deprecated
- **v4.0**: Legacy signal support removed (planned)

Plan your migration accordingly!