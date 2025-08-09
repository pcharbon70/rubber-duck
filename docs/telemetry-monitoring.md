# RubberDuck Telemetry and Monitoring Guide

## Overview

RubberDuck uses native Elixir telemetry for comprehensive monitoring of ML/AI operations, providing zero-overhead performance tracking with detailed insights into system behavior.

## Performance Characteristics

Based on performance testing:
- **Telemetry overhead**: < 0.001ms per operation
- **Event throughput**: 5,000,000+ events/second
- **Memory impact**: < 2MB for 10,000 operations
- **Span accuracy**: Accurate to microsecond precision

## Metric Categories

### 1. Action Performance Metrics

#### Counters
- `rubber_duck.action.count` - Number of action executions
  - Tags: `action_type`, `resource`, `status`
  
#### Distributions
- `rubber_duck.action.duration` - Action execution time (milliseconds)
  - Tags: `action_type`, `resource`
- `rubber_duck.action.execution_time` - Detailed execution time distribution
  - Buckets: [50, 100, 250, 500, 1000, 2500, 5000, 10000]ms

### 2. Learning and AI Metrics

#### Gauges
- `rubber_duck.learning.accuracy` - Current learning accuracy (0.0-1.0)
  - Tags: `agent_type`, `context`
- `rubber_duck.learning.improvement_rate` - Rate of learning improvement
  - Tags: `agent_type`

#### Counters
- `rubber_duck.learning.feedback_processed` - Feedback events processed
  - Tags: `feedback_type`, `agent_id`
- `rubber_duck.learning.patterns_discovered` - Number of patterns found
  - Tags: `pattern_type`, `confidence`

### 3. Agent Health Metrics

#### Gauges
- `rubber_duck.agent.health` - Agent health status (0.0=critical, 0.5=warning, 1.0=healthy)
  - Tags: `agent_id`
- `rubber_duck.agent.performance` - Agent performance score
  - Tags: `agent_id`, `health`

#### Counters
- `rubber_duck.agent.goal.completed` - Goals completed by agents
  - Tags: `agent_id`, `goal_type`, `status`
- `rubber_duck.agent.experience.gained` - Experience accumulated
  - Tags: `agent_id`, `experience_type`

### 4. Business Impact Metrics

#### Gauges
- `rubber_duck.business.roi` - Return on investment percentage
- `rubber_duck.business.value_generated` - Value generated in USD
  - Tags: `source`, `confidence`
- `rubber_duck.business.cost_savings` - Cost savings from automation
  - Tags: `automation_type`, `currency`

#### Distributions
- `rubber_duck.impact.score` - Business impact scores
  - Tags: `analysis_type`, `domain`
  - Buckets: [1.0, 2.0, 3.0, 5.0, 7.0, 8.0, 9.0, 10.0]

### 5. System Health Metrics

#### Gauges
- `rubber_duck.ml.system.agents` - Number of active ML agents
- `rubber_duck.ml.system.performance` - Overall ML system performance (0.0-1.0)
- `rubber_duck.health.database` - Database connectivity (0=down, 1=up)

## Prometheus Integration

### Configuration

Add to `config/config.exs`:

```elixir
config :rubber_duck, :telemetry,
  prometheus_enabled: true,
  prometheus_port: 9568,
  ml_metrics_enabled: true,
  action_tracking_enabled: true,
  learning_metrics_enabled: true,
  impact_scoring_enabled: true
```

### Metrics Endpoint

Prometheus metrics are exposed at: `http://localhost:9568/metrics`

### Scrape Configuration

Add to `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'rubberduck'
    scrape_interval: 15s
    static_configs:
      - targets: ['localhost:9568']
```

## Grafana Dashboard Setup

### Import Dashboard

1. Access Grafana at `http://localhost:3000`
2. Navigate to Dashboards → Import
3. Use the provided dashboard JSON (see `grafana/rubberduck-ml-dashboard.json`)

### Key Visualizations

#### ML Performance Overview
- Action success rate gauge
- Action duration histogram
- Learning accuracy over time
- Agent health matrix

#### Business Impact Dashboard
- ROI trend graph
- Cost savings accumulator
- Value generation by source
- Impact score distribution

#### Agent Performance Comparison
- Top performing agents table
- Agent success rate comparison
- Goal completion trends
- Experience accumulation rates

## Alert Rules

### Critical Alerts

```yaml
- alert: AgentHealthCritical
  expr: rubber_duck_agent_health < 0.5
  for: 5m
  annotations:
    summary: "Agent {{ $labels.agent_id }} health critical"

- alert: LowActionSuccessRate
  expr: rate(rubber_duck_action_count{status="failure"}[5m]) > rate(rubber_duck_action_count{status="success"}[5m])
  for: 10m
  annotations:
    summary: "Action failure rate exceeding success rate"

- alert: MLSystemPerformanceDegraded
  expr: rubber_duck_ml_system_performance < 0.6
  for: 15m
  annotations:
    summary: "ML system performance below threshold"
```

### Warning Alerts

```yaml
- alert: HighActionLatency
  expr: histogram_quantile(0.95, rubber_duck_action_execution_time_bucket) > 5000
  for: 10m
  annotations:
    summary: "95th percentile action latency above 5 seconds"

- alert: LearningAccuracyDeclining
  expr: deriv(rubber_duck_learning_accuracy[10m]) < -0.1
  for: 20m
  annotations:
    summary: "Learning accuracy declining for {{ $labels.agent_type }}"
```

## Custom Telemetry Usage

### Adding Action Telemetry

```elixir
use RubberDuck.Telemetry.ActionTelemetry

ActionTelemetry.span(
  [:rubber_duck, :action],
  %{
    action_type: "my_action",
    resource: "my_resource"
  },
  fn ->
    # Your action logic here
    {:ok, result}
  end
)
```

### Recording Business Impact

```elixir
alias RubberDuck.Telemetry.BusinessImpactTelemetry

# Record efficiency gain
BusinessImpactTelemetry.record_efficiency_gain(
  "data_processing",
  before_ms: 5000,
  after_ms: 1000
)

# Record cost savings
BusinessImpactTelemetry.record_cost_savings(
  :automation,
  amount: 10000,
  currency: "USD"
)
```

### Tracking Agent Performance

```elixir
alias RubberDuck.Telemetry.AgentTelemetry

# Record goal completion
AgentTelemetry.record_goal_completion(
  agent_id,
  goal_type,
  duration_ms,
  success
)

# Track learning event
AgentTelemetry.record_learning_event(
  agent_id,
  :pattern,
  confidence: 0.85,
  patterns_found: 5
)
```

## Troubleshooting

### High Memory Usage

If telemetry is consuming excessive memory:

1. Check for telemetry handler leaks:
   ```elixir
   :telemetry.list_handlers()
   ```

2. Reduce metric retention in Prometheus:
   ```yaml
   storage.tsdb.retention.time: 7d  # Reduce from default 15d
   ```

3. Implement sampling for high-frequency events:
   ```elixir
   if :rand.uniform() < 0.1 do  # 10% sampling
     :telemetry.execute([:high_freq_event], measurements, metadata)
   end
   ```

### Missing Metrics

If metrics aren't appearing:

1. Verify telemetry supervisor is running:
   ```elixir
   Supervisor.which_children(RubberDuck.Telemetry.Supervisor)
   ```

2. Check Prometheus scraping:
   ```bash
   curl http://localhost:9568/metrics
   ```

3. Verify metric names match Prometheus format:
   - Dots (.) become underscores (_)
   - Colons (:) become underscores (_)

### Performance Degradation

If telemetry impacts performance:

1. Run performance tests:
   ```bash
   mix test test/rubber_duck/telemetry/performance_test.exs
   ```

2. Disable non-critical metrics:
   ```elixir
   config :rubber_duck, :telemetry,
     ml_metrics_enabled: false,  # Disable if not needed
     impact_scoring_enabled: false
   ```

3. Use async telemetry emission for non-critical events:
   ```elixir
   Task.start(fn ->
     :telemetry.execute(event, measurements, metadata)
   end)
   ```

## Best Practices

1. **Use Consistent Naming**: Follow the pattern `rubber_duck.category.metric`
2. **Tag Appropriately**: Include relevant context but avoid high-cardinality tags
3. **Batch When Possible**: Use spans to group related operations
4. **Monitor the Monitors**: Track telemetry system health itself
5. **Document Custom Metrics**: Add new metrics to this guide
6. **Test Performance Impact**: Run performance tests when adding new telemetry
7. **Use Appropriate Metric Types**:
   - Counters for events/counts
   - Gauges for current values
   - Distributions for latencies/sizes
   - Summaries for percentiles

## Metric Reference

For a complete list of all metrics and their meanings, see the inline documentation in:
- `lib/rubber_duck/telemetry.ex` - Core metrics definitions
- `lib/rubber_duck/telemetry/action_telemetry.ex` - Action metrics
- `lib/rubber_duck/telemetry/agent_telemetry.ex` - Agent metrics
- `lib/rubber_duck/telemetry/business_impact_telemetry.ex` - Business metrics