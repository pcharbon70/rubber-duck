# LLM Provider Circuit Breaker Implementation

## Overview

The LLM Provider Circuit Breaker is a specialized resilience mechanism for managing failures in LLM API calls. It extends the base circuit breaker pattern with provider-specific features designed for expensive, rate-limited APIs.

## Problem Statement

LLM API calls present unique challenges:
- **High Cost**: Each failed request wastes money
- **Rate Limiting**: Providers enforce strict rate limits
- **Configuration Issues**: Invalid API keys should be handled differently than timeouts
- **Provider Diversity**: Different providers have different reliability characteristics

## Solution

### Key Features

1. **Provider-Specific Thresholds**
   - OpenAI/Anthropic: 3 failures before opening (expensive APIs)
   - Local models: 10 failures before opening (more lenient)
   - Custom thresholds per provider

2. **Failure Categorization**
   - `invalid_api_key`: Opens circuit immediately (configuration issue)
   - `rate_limit`: Opens circuit with retry-after timeout
   - `timeout`: Normal failure counting
   - `server_error`: Normal failure counting

3. **Cost-Aware Circuit Breaking**
   - Tracks cumulative cost per provider
   - Opens circuit if cost threshold exceeded
   - Prevents expensive API abuse

4. **Smart Fallback Selection**
   - Finds available providers in priority order
   - Excludes unavailable/rate-limited providers
   - Considers cost constraints

## Architecture

### Components

```elixir
# Main circuit breaker for LLM providers
RubberDuck.LLM.ProviderCircuitBreaker

# Integration with LLM service
RubberDuck.LLM.Service

# Underlying circuit breaker infrastructure
RubberDuck.Routing.CircuitBreaker
RubberDuck.Routing.CircuitBreakerSupervisor
```

### Flow

1. Request arrives at LLM Service
2. Check provider circuit breaker status
3. If open/cost exceeded → attempt fallback
4. Execute request and track result
5. Update circuit breaker state

## Configuration

```elixir
# Global defaults
config :rubber_duck, :llm_circuit_breaker,
  error_threshold: 3,        # Failures before opening
  timeout: 120_000,          # Recovery time (2 minutes)
  half_open_requests: 1,     # Test requests in half-open
  success_threshold: 2,      # Successes to close
  cost_threshold: 100.0      # Cost limit per hour

# Provider-specific (hardcoded in get_provider_config/1)
openai: %{error_threshold: 3, timeout: 120_000}
anthropic: %{error_threshold: 3, timeout: 120_000}
local: %{error_threshold: 10, timeout: 30_000}
```

## Usage Examples

### Basic Usage

```elixir
# Automatic circuit breaker integration
{:ok, response} = RubberDuck.LLM.Service.complete(request)

# Manual circuit breaker operations
ProviderCircuitBreaker.check_provider(:openai)
ProviderCircuitBreaker.record_success(:openai, %{cost: 0.01, latency_ms: 250})
ProviderCircuitBreaker.record_failure(:openai, :timeout)
```

### Fallback Selection

```elixir
# Find available fallback providers
fallbacks = ProviderCircuitBreaker.find_fallback_providers(
  :openai,
  exclude: [:anthropic],
  max_cost: 50.0
)
# => [:local, :fallback]
```

### Status Monitoring

```elixir
# Get provider status
status = ProviderCircuitBreaker.get_provider_status(:openai)
# => %{
#   state: :closed,
#   error_count: 1,
#   cost_used: 25.50,
#   avg_latency: 312.5,
#   rate_limited: false
# }

# Get all provider statuses
all_status = ProviderCircuitBreaker.get_all_provider_status()
```

### Manual Recovery

```elixir
# Reset a provider after fixing issues
ProviderCircuitBreaker.reset_provider(:openai)
```

## Implementation Details

### State Management

- Circuit breaker state managed by `RubberDuck.Routing.CircuitBreaker`
- Cost tracking uses Process dictionary (simplified for POC)
- Rate limiting tracked with timestamps

### Failure Handling

```elixir
case failure_type do
  :invalid_api_key ->
    # Configuration issue - open immediately
    force_open_circuit(provider_name, :configuration_error)
    
  :rate_limit ->
    # Rate limited - open with specific timeout
    force_open_circuit(provider_name, :rate_limited, retry_after)
    
  _ ->
    # Normal failure - count toward threshold
    CircuitBreaker.record_failure(provider_key(provider_name))
end
```

### Cost Tracking

```elixir
# Track cost after successful request
ProviderCircuitBreaker.record_success(provider_name, %{
  cost: estimate_cost(request, response),
  latency_ms: response_time
})

# Check cost before allowing request
defp check_cost_threshold(provider_name) do
  current_cost = get_cost_used(provider_name)
  if current_cost >= config.cost_threshold do
    {:error, :cost_exceeded}
  else
    :ok
  end
end
```

## Testing

Test coverage includes:
- Circuit state transitions
- Provider-specific thresholds
- Failure categorization
- Cost tracking
- Fallback selection
- Manual reset operations

Run tests:
```bash
mix test test/llm/provider_circuit_breaker_test.exs
```

## Monitoring and Telemetry

Circuit breaker events are logged with appropriate levels:
- `warning`: Circuit opened, failures recorded
- `error`: Force opening for configuration issues
- `info`: Using fallback provider

Future improvements:
- Telemetry events for Prometheus/Grafana
- Cost metrics dashboard
- Provider health dashboard

## Future Enhancements

1. **Persistent State**
   - Store circuit breaker state in Redis/ETS
   - Maintain state across restarts

2. **Advanced Cost Tracking**
   - Token-based cost calculation
   - Budget enforcement per time window
   - Cost prediction before requests

3. **Adaptive Thresholds**
   - Learn from historical patterns
   - Adjust thresholds based on time of day
   - Provider-specific learning

4. **Distributed Coordination**
   - Share circuit breaker state across nodes
   - Global rate limit coordination
   - Consensus-based circuit decisions

5. **Enhanced Fallback Logic**
   - Model capability matching
   - Quality-based fallback selection
   - Load balancing across providers

## Status

**Implementation Date**: 2025-08-07
**Status**: Complete ✅
**Tests**: 15 tests, all passing

The LLM Provider Circuit Breaker is fully integrated with the LLM Service and provides comprehensive protection against provider failures while optimizing for cost and availability.