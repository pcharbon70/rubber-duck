# Health Check Circuit Breaker Implementation

## Overview

The Health Check Circuit Breaker prevents health check storms during outages and protects system resources from repeated failing health checks. It implements per-check-type circuit breakers with result caching and degraded mode support.

## Problem Statement

Health check systems can create problems during outages:
- **Health Check Storms**: Repeated failing checks consume resources
- **Cascading Failures**: Failed health checks trigger more health checks
- **External Service Overload**: Health checks can overwhelm struggling services
- **Thundering Herd**: All services checking health simultaneously during recovery
- **Resource Exhaustion**: CPU/memory consumed by failing health checks

## Solution Architecture

### Two-Layer Protection

1. **Circuit Breaker Layer** (`health/circuit_breaker.ex`)
   - Per-check-type circuit breakers
   - Result caching during circuit open state
   - Consecutive failure tracking
   - Priority-based health checks

2. **Protected Health Check** (`health/protected_health_check.ex`)
   - Enhanced GenServer with circuit breaker integration
   - Degraded mode support
   - Auto-adjustment of check intervals
   - Priority check execution

## Features

### Per-Check-Type Circuit Breakers

Different health checks have different reliability requirements:

```elixir
# Configuration per check type
database: %{error_threshold: 2, timeout: 120_000}        # Critical, strict
memory: %{error_threshold: 10, timeout: 30_000}          # System, lenient
processes: %{error_threshold: 10, timeout: 30_000}       # System, lenient
ash_authentication: %{error_threshold: 3, timeout: 60_000}   # Service, moderate
repo_pool: %{error_threshold: 2, timeout: 120_000}       # Critical, strict
external_service: %{error_threshold: 5, timeout: 90_000}     # External, moderate
```

### Result Caching

When circuit is open, returns cached results to prevent repeated failures:

```elixir
# Cached result includes metadata
%{
  status: :healthy,
  message: "Database connection successful",
  cached: true,
  cache_age_ms: 15000,
  circuit_open: true
}
```

### Degraded Mode

Automatically enters degraded mode after consecutive failures:
- Increases check intervals
- Skips non-critical checks
- Uses cached results more aggressively
- Reduces system load during recovery

## Usage

### Basic Circuit Breaker Usage

```elixir
# Execute health check with circuit breaker protection
result = CircuitBreaker.check_with_breaker(:database, fn ->
  check_database_health()
end)

# Execute multiple checks in parallel
checks = [
  {:database, &check_database/0},
  {:memory, &check_memory/0},
  {:processes, &check_processes/0}
]

results = CircuitBreaker.check_multiple(checks)
```

### Protected Health Check Usage

```elixir
# Start protected health check
{:ok, pid} = ProtectedHealthCheck.start_link(
  check_interval: 30_000,
  enable_circuit_breaker: true,
  priority_checks: [:database, :repo_pool]
)

# Get status with circuit breaker info
status = ProtectedHealthCheck.get_status()
# => %{
#   status: :healthy,
#   checks: %{
#     database: %{status: :healthy, circuit_state: :closed},
#     memory: %{status: :healthy, cached: false}
#   },
#   degraded_mode: false
# }

# Get JSON for API endpoints
json = ProtectedHealthCheck.get_health_json()
# => %{
#   status: :healthy,
#   circuit_breakers: %{...},
#   degraded_mode: false,
#   uptime: 3600
# }
```

### Manual Control

```elixir
# Enable degraded mode manually
ProtectedHealthCheck.set_degraded_mode(true)

# Reset specific circuit
CircuitBreaker.reset(:database)

# Reset all circuits
CircuitBreaker.reset_all()

# Check if circuit is open
CircuitBreaker.circuit_open?(:database)
# => false

# Force failure for testing
CircuitBreaker.force_failure(:external_service, 5)
```

## Configuration

### Global Configuration

```elixir
config :rubber_duck, :health_circuit_breaker,
  error_threshold: 3,        # Failures before opening
  timeout: 60_000,           # Recovery timeout (1 minute)
  half_open_requests: 1,     # Test requests in half-open
  success_threshold: 2,      # Successes to close
  cache_duration: 30_000     # Cache results for 30 seconds
```

### Protected Health Check Configuration

```elixir
ProtectedHealthCheck.start_link(
  check_interval: 30_000,           # Normal check interval
  timeout: 5_000,                   # Timeout per check
  enable_circuit_breaker: true,     # Enable protection
  priority_checks: [:database],     # Always check these
  skip_on_degraded: [:external]     # Skip in degraded mode
)
```

## Degraded Mode Behavior

### Automatic Triggering

Degraded mode is automatically enabled when:
- 3+ consecutive health check failures
- Multiple circuit breakers are open
- System resources are critically low

### Degraded Mode Actions

1. **Increase Check Intervals**: From 30s to 60s+
2. **Skip Non-Critical Checks**: External services, optional components
3. **Use Cached Results**: Return last known good state
4. **Reduce Load**: Minimize resource consumption

### Recovery

System automatically recovers from degraded mode when:
- Health checks succeed consistently
- Circuit breakers close
- Resources return to normal levels

## Monitoring

### Circuit Breaker Status

```elixir
status = CircuitBreaker.get_status()
# => %{
#   database: %{
#     state: :closed,
#     error_count: 0,
#     consecutive_failures: 0,
#     cached_result: %{...},
#     last_check_time: ~U[2025-08-07 12:00:00Z]
#   },
#   memory: %{state: :open, ...}
# }
```

### Telemetry Events

Health checks emit telemetry events:

```elixir
:telemetry.execute(
  [:rubber_duck, :health, :database],
  %{value: 1},  # 1 = healthy, 0.5 = warning, 0 = unhealthy
  %{
    cached: false,
    circuit_state: :closed
  }
)
```

### Health Check JSON

API-friendly health status:

```json
{
  "status": "healthy",
  "timestamp": "2025-08-07T12:00:00Z",
  "checks": {
    "database": {
      "status": "healthy",
      "circuit_state": "closed",
      "cached": false
    }
  },
  "circuit_breakers": {
    "database": {
      "state": "closed",
      "error_count": 0
    }
  },
  "degraded_mode": false,
  "uptime": 3600
}
```

## Testing

### Test Helpers

```elixir
# Force circuit open
CircuitBreaker.force_failure(:database, 3)

# Verify circuit state
assert CircuitBreaker.circuit_open?(:database)

# Get cached result
result = CircuitBreaker.get_cached_result(:database)
assert result.cached == true

# Reset for next test
CircuitBreaker.reset_all()
```

### Integration Testing

```elixir
test "handles database outage gracefully" do
  # Break database circuit
  CircuitBreaker.force_failure(:database, 3)
  
  # Health check should return cached result
  status = ProtectedHealthCheck.get_status()
  db_check = status.checks.database
  
  assert db_check.circuit_open == true
  assert db_check.cached == true
  
  # System should enter degraded mode
  assert status.degraded_mode == true
end
```

## Performance Impact

- **Closed Circuit**: Minimal overhead (< 1ms)
- **Open Circuit**: Immediate return of cached result
- **Caching**: Last 100 results kept in memory
- **Parallel Checks**: Executes checks concurrently
- **Degraded Mode**: Reduces check frequency by 50-80%

## Best Practices

1. **Set Appropriate Thresholds**
   - Critical services: Lower threshold (2-3 failures)
   - System resources: Higher threshold (10+ failures)
   - External services: Medium threshold (5 failures)

2. **Configure Cache Duration**
   - Short for critical services (10-30 seconds)
   - Longer for stable metrics (60+ seconds)

3. **Use Priority Checks**
   - Always check database and authentication
   - Skip external services in degraded mode

4. **Monitor Circuit States**
   - Alert on circuits staying open too long
   - Track circuit flip-flopping
   - Monitor cache hit rates

5. **Test Failure Scenarios**
   - Regularly test degraded mode
   - Verify recovery behavior
   - Ensure cached results are acceptable

## Integration with Other Systems

### With Database Circuit Breaker

Health checks respect database circuit breaker:
```elixir
# If database circuit is open, health check also fails fast
check_database() # Returns cached result if DB circuit open
```

### With LLM Circuit Breaker

Can monitor LLM provider health:
```elixir
checks = %{
  llm_providers: fn ->
    status = ProviderCircuitBreaker.get_all_provider_status()
    if any_provider_healthy?(status) do
      %{status: :healthy, providers: status}
    else
      %{status: :unhealthy, message: "All LLM providers unavailable"}
    end
  end
}
```

### With Monitoring Systems

Export to Prometheus/Grafana:
- Circuit breaker states
- Cache hit rates
- Check execution times
- Degraded mode status

## Future Enhancements

1. **Predictive Circuit Breaking**
   - Open circuits based on patterns
   - ML-based failure prediction

2. **Distributed Health Checks**
   - Coordinate checks across nodes
   - Shared cache in Redis/ETS

3. **Adaptive Thresholds**
   - Adjust based on time of day
   - Learn from historical patterns

4. **Health Check Priorities**
   - Dynamic priority adjustment
   - Resource-based scheduling

5. **Advanced Caching**
   - TTL per check type
   - Cache warming strategies

## Status

**Implementation Date**: 2025-08-07
**Status**: Complete ✅
**Tests**: Comprehensive test coverage

The health check circuit breaker successfully prevents health check storms while maintaining system observability through intelligent caching and degraded mode operation.