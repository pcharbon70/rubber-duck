# Agent Communication Circuit Breaker Implementation

## Overview

The Agent Communication Circuit Breaker provides resilience for inter-agent communication in the Jido framework. It protects against unresponsive agents, message storms, recursive call chains, and cascading failures in the distributed agent system.

## Problem Statement

Agent-based architectures face unique communication challenges:
- **Unresponsive Agents**: Agents may become slow or completely unresponsive
- **Message Storms**: Recursive or cyclic messaging between agents
- **Cascading Failures**: One failed agent affecting entire agent network
- **Resource Exhaustion**: Message queues growing unbounded
- **Coordination Failures**: Distributed agent coordination breaking down
- **Timeout Cascades**: Slow agents causing system-wide timeouts

## Solution Architecture

### Three-Layer Protection

1. **Circuit Breaker Core** (`agents/circuit_breaker.ex`)
   - Per-agent circuit breakers with independent states
   - Instruction timeout tracking
   - Dead letter queue for failed messages
   - Agent availability checking

2. **Protected Agent Base** (`agents/protected_agent.ex`)
   - Enhanced base behavior with built-in protection
   - Automatic retry with exponential backoff
   - Chain and parallel execution patterns
   - Communication health monitoring

3. **Integration Layer**
   - Seamless integration with Jido.Agent framework
   - Transparent to existing agent implementations
   - Compatible with agent supervision trees

## Features

### Per-Agent Circuit Breakers

Different agents have different reliability requirements:

```elixir
# Configuration per agent type
llm_orchestrator: %{error_threshold: 3, timeout: 60_000}      # Critical
llm_monitoring: %{error_threshold: 10, timeout: 30_000}       # Lenient
project_agent: %{error_threshold: 5, timeout: 45_000}         # Moderate
user_agent: %{error_threshold: 3, timeout: 30_000}            # User-facing
```

### Dead Letter Queue

Failed instructions are queued for later retry:
- Size-limited queue (100 messages default)
- Manual or automatic retry capabilities
- Preserves instruction context and options
- FIFO with overflow protection

### Fallback Agents

Automatic failover to alternative agents:
```elixir
CircuitBreaker.send_instruction(
  :primary_agent,
  {:process, data},
  fallback: :backup_agent
)
```

## Usage

### Basic Circuit Breaker Usage

```elixir
# Send instruction with circuit breaker protection
result = CircuitBreaker.send_instruction(
  :llm_orchestrator,
  {:complete, request},
  timeout: 15_000
)

# Broadcast to multiple agents
results = CircuitBreaker.broadcast_to_agents(
  [:project_agent, :code_file_agent, :ai_analysis],
  {:analyze, data}
)

# Check circuit state
if CircuitBreaker.circuit_open?(:project_agent) do
  Logger.warning("Project agent circuit is open")
end
```

### Protected Agent Usage

```elixir
defmodule MyApp.MyAgent do
  use RubberDuck.Agents.ProtectedAgent,
    name: "my_agent",
    description: "A resilient agent",
    circuit_breaker: [
      error_threshold: 5,
      timeout: 30_000
    ]
  
  def handle_instruction({:process, data}, agent) do
    # Automatically protected by circuit breaker
    result = process_data(data)
    {{:ok, result}, agent}
  end
  
  def collaborate_with_other_agents(data) do
    # Use built-in protected communication
    send_to_agent(:other_agent, {:help, data})
  end
end
```

### Advanced Patterns

#### Retry with Exponential Backoff

```elixir
result = ProtectedAgent.send_with_retry(
  :ai_analysis,
  {:analyze, complex_data},
  retries: 3,
  retry_delay: 1000  # Doubles each retry
)
```

#### Sequential Chain Execution

```elixir
chain = [
  {:llm_orchestrator, fn _ -> {:prepare, data} end},
  {:ai_analysis, fn prev -> {:analyze, prev} end},
  {:project_agent, fn result -> {:store, result} end}
]

{:ok, final_result} = ProtectedAgent.execute_chain(chain)
```

#### Parallel Execution

```elixir
instructions = [
  {:agent1, {:task1, data1}},
  {:agent2, {:task2, data2}},
  {:agent3, {:task3, data3}}
]

results = ProtectedAgent.execute_parallel(instructions, timeout: 5000)
# => %{
#   agent1: {:ok, result1},
#   agent2: {:ok, result2},
#   agent3: {:error, :timeout}
# }
```

## Dead Letter Queue Management

### Viewing Failed Messages

```elixir
# Get failed messages for an agent
failed = CircuitBreaker.get_dead_letter_queue(:project_agent)
# => [
#   {{:analyze, "data1"}, [timeout: 5000]},
#   {{:optimize, "data2"}, [fallback: :ai_analysis]}
# ]
```

### Retrying Failed Messages

```elixir
# Retry all failed messages
results = CircuitBreaker.retry_dead_letters(:project_agent)

# Retry with different options
results = CircuitBreaker.retry_dead_letters(
  :project_agent,
  timeout: 20_000,
  fallback: :backup_agent
)
```

## Monitoring and Telemetry

### Health Status

```elixir
status = CircuitBreaker.get_status()
# => %{
#   llm_orchestrator: %{
#     state: :closed,
#     error_count: 1,
#     agent_available: true,
#     avg_response_time: 245.5,
#     failed_instructions: 0,
#     last_success: ~U[2025-08-07 15:30:00Z]
#   },
#   project_agent: %{
#     state: :open,
#     error_count: 5,
#     agent_available: false,
#     failed_instructions: 3
#   }
# }
```

### Communication Health Monitoring

```elixir
# Monitor overall health
health = ProtectedAgent.monitor_communication_health()

# Automatic telemetry events
:telemetry.execute(
  [:rubber_duck, :agent, :circuit_breaker, :circuit_opened],
  %{count: 1},
  %{agent: :project_agent, reason: :timeout}
)
```

### Metrics Tracked

- **Response Times**: Average instruction execution time
- **Success/Failure Rates**: Per instruction type
- **Circuit State Changes**: Open/closed transitions
- **Dead Letter Queue Size**: Failed message accumulation
- **Agent Availability**: Process alive checks

## Configuration

### Global Configuration

```elixir
config :rubber_duck, :agent_circuit_breaker,
  error_threshold: 5,        # Default failures before opening
  timeout: 30_000,           # Default recovery timeout
  half_open_requests: 2,     # Test requests in half-open
  success_threshold: 3,      # Successes to close
  instruction_timeout: 10_000 # Default instruction timeout
```

### Per-Agent Configuration

```elixir
defmodule MyAgent do
  use RubberDuck.Agents.ProtectedAgent,
    circuit_breaker: [
      error_threshold: 3,      # More strict
      timeout: 60_000,         # Longer recovery
      instruction_timeout: 20_000
    ]
end
```

## Integration with Jido Framework

### Automatic Protection

All agents using `ProtectedAgent` base automatically get:
- Circuit breaker protection for all instructions
- Dead letter queue for failures
- Health monitoring
- Telemetry integration

### Transparent Operation

Existing agent code requires no changes:
```elixir
# Before (unprotected)
use RubberDuck.Agents.Base

# After (protected)
use RubberDuck.Agents.ProtectedAgent
```

### Supervision Compatibility

Works seamlessly with OTP supervision:
```elixir
children = [
  {MyProtectedAgent, [id: :agent1]},
  {AnotherProtectedAgent, [id: :agent2]}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

## Best Practices

1. **Set Appropriate Thresholds**
   - Critical agents: 2-3 failures
   - Standard agents: 5 failures
   - Monitoring agents: 10+ failures

2. **Configure Timeouts Carefully**
   - Instruction timeout: 5-10 seconds for most operations
   - Recovery timeout: 30-60 seconds
   - Consider agent workload

3. **Use Fallback Agents**
   - Define fallback paths for critical operations
   - Ensure fallbacks can handle the workload
   - Avoid circular fallbacks

4. **Monitor Dead Letter Queues**
   - Set up alerts for growing queues
   - Regularly retry or clear old messages
   - Investigate recurring failures

5. **Test Failure Scenarios**
   - Simulate agent failures
   - Test cascade prevention
   - Verify recovery behavior

## Failure Scenarios

### Agent Crash

```elixir
# Agent crashes during instruction
send_instruction(:crashing_agent, {:process, data})
# => {:error, {:exit, reason}}
# Message added to dead letter queue
# Circuit breaker records failure
```

### Timeout

```elixir
# Agent takes too long
send_instruction(:slow_agent, {:complex_task, data}, timeout: 1000)
# => {:error, :timeout}
# Circuit may open after repeated timeouts
```

### Circuit Open

```elixir
# Circuit already open from previous failures
send_instruction(:failed_agent, {:task, data})
# => {:error, :circuit_open}
# Attempts fallback if configured
# Adds to dead letter queue
```

## Performance Impact

- **Closed Circuit**: Minimal overhead (< 1ms)
- **Open Circuit**: Immediate rejection, no agent call
- **Dead Letter Queue**: O(1) insertion, O(n) retry
- **Parallel Broadcast**: Concurrent execution
- **Health Monitoring**: Async, non-blocking

## Future Enhancements

1. **Distributed Circuit Coordination**
   - Share circuit state across nodes
   - Consensus-based circuit decisions
   - Global dead letter queue

2. **Intelligent Routing**
   - Load-based agent selection
   - Predictive circuit breaking
   - Dynamic fallback determination

3. **Advanced Retry Strategies**
   - Priority-based retry
   - Scheduled retry windows
   - Retry budget management

4. **Agent Communication Patterns**
   - Saga pattern support
   - Event sourcing integration
   - CQRS with circuit breakers

5. **Observability Enhancements**
   - Distributed tracing
   - Circuit breaker dashboard
   - Communication flow visualization

## Testing Support

### Force Circuit States

```elixir
# Open circuit for testing
for _ <- 1..5 do
  CircuitBreaker.send_instruction(:test_agent, {:fail, :forced}, [])
end

assert CircuitBreaker.circuit_open?(:test_agent)

# Reset for cleanup
CircuitBreaker.reset(:test_agent)
```

### Mock Agents

```elixir
defmodule TestAgent do
  use RubberDuck.Agents.ProtectedAgent
  
  def handle_instruction({:test, response}, agent) do
    {{:ok, response}, agent}
  end
end
```

## Status

**Implementation Date**: 2025-08-07
**Status**: Complete ✅
**Tests**: Comprehensive test coverage

The agent communication circuit breaker successfully provides resilience for the Jido agent framework, preventing cascading failures and enabling graceful degradation during agent communication issues.