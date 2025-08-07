# RubberDuck Actions

Actions are the core building blocks for executing operations in the RubberDuck system. They follow the Jido Action pattern and provide a clean, composable way to implement business logic.

## Directory Structure

```
actions/
├── base.ex                    # Base behavior for all actions
├── core/                       # Core system actions
│   ├── update_entity.ex       # Main update orchestrator
│   ├── entity.ex              # Entity wrapper for cross-domain coordination
│   └── update_entity/         # Specialized update modules
│       ├── validator.ex       # Input validation
│       ├── impact_analyzer.ex # Impact assessment
│       ├── executor.ex        # Change execution
│       ├── learner.ex         # Learning and pattern recognition
│       └── propagator.ex      # Change propagation
└── README.md                  # This file
```

## Core Actions

### UpdateEntity

The primary action for updating entities with comprehensive validation, impact analysis, and learning capabilities.

**Usage:**
```elixir
alias RubberDuck.Actions.Core.UpdateEntity

params = %{
  entity_id: "user-123",
  entity_type: :user,
  changes: %{email: "new@example.com"},
  impact_analysis: true,
  auto_propagate: false,
  learning_enabled: true
}

{:ok, result} = UpdateEntity.run(params, context)
```

**Pipeline:**
1. Fetch entity
2. Validate changes
3. Analyze impact
4. Check goal alignment
5. Execute changes
6. Propagate (if enabled)
7. Learn from outcome (if enabled)

## Creating New Actions

### Basic Action Template

```elixir
defmodule RubberDuck.Actions.YourDomain.YourAction do
  use Jido.Action,
    name: "your_action",
    description: "What this action does",
    schema: [
      param1: [type: :string, required: true],
      param2: [type: :integer, default: 0]
    ]
  
  @impl true
  def run(params, context) do
    # Your action logic here
    {:ok, %{result: "success"}}
  end
end
```

### Using Base Behavior

For actions that need delegation and pipeline support:

```elixir
defmodule RubberDuck.Actions.YourDomain.ComplexAction do
  use Jido.Action,
    name: "complex_action",
    schema: [...]
  
  use RubberDuck.Action.Base
  
  # Delegate to other modules
  delegate_to YourModule, :process, as: :process_data
  
  @impl true
  def run(params, context) do
    with_pipeline(context) do
      params
      |> validate()
      |> process_data()
      |> finalize()
    end
  end
end
```

## Action Patterns

### 1. Simple Actions
For straightforward operations without complex dependencies:
```elixir
def run(params, _context) do
  # Direct implementation
  result = do_something(params)
  {:ok, result}
end
```

### 2. Pipeline Actions
For multi-step operations with error handling:
```elixir
def run(params, context) do
  params
  |> step_1()
  |> maybe_continue(&step_2/1)
  |> maybe_continue(&step_3/1)
  |> handle_result()
end
```

### 3. Delegating Actions
For actions that coordinate multiple modules:
```elixir
delegate_to ModuleA, :process_a
delegate_to ModuleB, :process_b

def run(params, context) do
  with {:ok, result_a} <- process_a(params, context),
       {:ok, result_b} <- process_b(result_a, context) do
    {:ok, combine_results(result_a, result_b)}
  end
end
```

## Testing Actions

### Unit Testing
```elixir
defmodule YourActionTest do
  use ExUnit.Case
  
  alias RubberDuck.Actions.YourDomain.YourAction
  
  test "successful execution" do
    params = %{param1: "value"}
    assert {:ok, result} = YourAction.run(params, %{})
    assert result.success == true
  end
  
  test "handles errors" do
    params = %{param1: nil}
    assert {:error, reason} = YourAction.run(params, %{})
    assert reason.message =~ "required"
  end
end
```

### Integration Testing
Test the full pipeline with all features enabled:
```elixir
test "end-to-end pipeline" do
  params = build_params(
    impact_analysis: true,
    auto_propagate: true,
    learning_enabled: true
  )
  
  assert {:ok, result} = YourAction.run(params, %{})
  assert result.impact_assessment != nil
  assert result.propagation_results.propagated == true
  assert result.learning_data.learned == true
end
```

## Best Practices

### 1. Keep Actions Focused
Each action should have a single, clear responsibility.

### 2. Use Schema Validation
Define clear schemas for your action parameters:
```elixir
schema: [
  id: [type: :string, required: true],
  options: [type: :map, default: %{}]
]
```

### 3. Handle Errors Gracefully
Always return proper error tuples:
```elixir
{:error, %{
  reason: :validation_failed,
  details: "..."
}}
```

### 4. Document Parameters
Add clear documentation for complex parameters:
```elixir
@doc """
Processes data with the following options:
- `:timeout` - Maximum execution time in milliseconds (default: 5000)
- `:retry_count` - Number of retries on failure (default: 3)
"""
```

### 5. Use Telemetry
Emit telemetry events for monitoring:
```elixir
:telemetry.execute(
  [:rubber_duck, :action, :your_action],
  %{duration: duration},
  %{action: "your_action", entity_id: params.id}
)
```

## Module Dependencies

- **Jido.Action**: Base action behavior from Jido SDK
- **RubberDuck.Action.Base**: Common patterns for RubberDuck actions
- **Entity**: Wrapper for cross-domain coordination
- **Ash Framework**: For resource management (when integrated)

## Performance Considerations

- Simple actions: Target < 100ms execution time
- Complex pipelines: Target < 1 second
- Use async operations for heavy processing
- Implement caching for frequently accessed data
- Consider batch operations for multiple updates

## Future Improvements

1. **Batch Actions**: Support for processing multiple entities
2. **Async Actions**: Background job integration
3. **Action Composition**: Combine multiple actions
4. **Action Versioning**: Support multiple versions of actions
5. **Action Analytics**: Built-in performance tracking

## Related Documentation

- [Action Framework Architecture](/docs/architecture/action-framework.md)
- [Jido SDK Documentation](https://hexdocs.pm/jido)
- [Testing Guide](/docs/testing.md)