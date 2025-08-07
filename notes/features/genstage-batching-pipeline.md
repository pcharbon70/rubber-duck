# Phase 1.2.2: GenStage Batching Pipeline

**Status:** In Progress  
**Current Phase:** Phase 1 - Core GenStage Infrastructure  
**Priority:** High  
**Estimated Effort:** Medium-Large  
**Dependencies:** Phase 1.2.1 (Compile-Time Dispatch Generation)

## Problem Statement

While our compile-time routing system achieved a 15x performance improvement (74,245 messages/second), we need to handle even higher throughput scenarios and provide better back-pressure management. Current limitations include:

1. **No Back-Pressure Handling**: The current system processes messages immediately without considering downstream capacity
2. **Suboptimal Batching**: Messages are processed individually or in simple batches without intelligent grouping
3. **No Adaptive Sizing**: Batch sizes are static and don't adapt to system load or message characteristics
4. **Limited Concurrency Control**: No dynamic adjustment of processing concurrency based on system resources
5. **Missing Flow Control**: No mechanism to handle traffic spikes or downstream service degradation

The system needs a GenStage-based pipeline that provides:
- Intelligent message batching with adaptive sizing
- Proper back-pressure handling from producers to consumers
- Priority-aware processing with dynamic concurrency
- Time-based and size-based batching triggers
- Comprehensive telemetry for batching operations

## Solution Overview

Implement a GenStage-based batching pipeline that sits between the compile-time router and message handlers. The pipeline will consist of:

1. **Message Producer Stage**: Collects incoming messages and manages batching logic
2. **Priority-Aware Consumer Stages**: Process messages with different priority levels using separate consumer pools
3. **Adaptive Batch Controller**: Dynamically adjusts batch sizes based on system metrics
4. **Telemetry Integration**: Comprehensive metrics for batch operations and performance monitoring

### Architecture Components

```
[CompileTimeRouter] 
    ↓ (Individual Messages)
[MessageProducer] 
    ↓ (Batched Events with Back-pressure)
[PriorityConsumerPool] 
    ↓ (Parallel Processing)
[Enhanced Message Handlers]
```

## Agent Consultations Performed

### Research Agent Consultation
**Topic**: GenStage batching patterns and best practices in Elixir 2025

**Key Findings**:
- GenStage provides demand-driven data flow with automatic back-pressure
- Producer-Consumer pattern ideal for message transformation and batching
- Broadway framework offers higher-level abstractions but may be overkill
- Dispatcher patterns: DemandDispatcher (FIFO), BroadcastDispatcher, PartitionDispatcher
- Common batching triggers: time-based, size-based, and hybrid approaches
- Buffer management crucial for handling burst traffic

**Recommendations**:
- Use GenStage.DemandDispatcher for load balancing across consumers
- Implement custom batching logic rather than Broadway for fine control
- Use :telemetry spans for comprehensive monitoring
- Consider GenStage.PartitionDispatcher for priority-based routing

### Elixir Expert Consultation
**Topic**: GenStage implementation patterns for high-throughput message processing

**Key Patterns**:
1. **Producer Buffer Management**: Use configurable buffer sizes with overflow handling
2. **Consumer Demand Strategy**: Dynamic demand based on processing capacity and queue length
3. **Back-pressure Propagation**: Proper demand signaling from consumers to producers
4. **Error Recovery**: Circuit breakers and retry logic for failed batches
5. **Telemetry Integration**: Use `:telemetry.span/3` for comprehensive metrics

**Implementation Considerations**:
- Start with simple DemandDispatcher, add complexity incrementally
- Use multiple consumer processes for different priority levels
- Implement graceful degradation when consumers are overwhelmed
- Consider supervisor restart strategies for fault tolerance

### Senior Engineer Reviewer Consultation  
**Topic**: Architectural decisions for producer-consumer pipeline design

**Architectural Decisions**:
1. **Separation of Concerns**: Keep batching logic separate from routing logic
2. **Configurable Parameters**: Make batch sizes, timeouts, and concurrency configurable
3. **Monitoring First**: Implement comprehensive telemetry before optimization
4. **Incremental Rollout**: Feature flags to enable/disable GenStage pipeline
5. **Backward Compatibility**: Maintain existing routing interface during transition

**Risk Mitigation**:
- Implement fallback to direct routing if GenStage pipeline fails
- Use feature flags for gradual rollout and A/B testing
- Extensive telemetry for performance monitoring and debugging
- Load testing with realistic message patterns

## Technical Details

### Core Components

#### 1. MessageProducer GenStage
```elixir
defmodule RubberDuck.Routing.MessageProducer do
  use GenStage
  
  # Batching configuration
  @default_config %{
    min_batch_size: 10,
    max_batch_size: 100,
    batch_timeout_ms: 50,
    buffer_size: 1000,
    adaptive_batching: true
  }
end
```

**Responsibilities**:
- Accept individual messages from CompileTimeRouter
- Buffer messages with configurable limits
- Create batches based on time and size triggers
- Emit batched events to consumers
- Handle back-pressure from downstream consumers
- Provide overflow handling for burst traffic

**Key Features**:
- **Adaptive Batch Sizing**: Adjust batch sizes based on throughput metrics
- **Priority Grouping**: Group messages by priority level for optimal processing
- **Time-based Triggers**: Emit batches after configurable timeouts
- **Overflow Protection**: Implement circuit breaker patterns for buffer overflow

#### 2. PriorityConsumerPool
```elixir
defmodule RubberDuck.Routing.PriorityConsumerPool do
  use GenStage
  
  # Priority-based consumption with different concurrency levels
  @priority_configs %{
    critical: %{max_concurrency: 1, demand: 5},
    high: %{max_concurrency: 4, demand: 20}, 
    normal: %{max_concurrency: 8, demand: 50},
    low: %{max_concurrency: 2, demand: 100}
  }
end
```

**Responsibilities**:
- Subscribe to MessageProducer with priority-based demand
- Process batched messages with appropriate concurrency levels
- Implement priority-based routing to different handler pools
- Provide failure recovery and retry mechanisms
- Emit processing telemetry and metrics

#### 3. AdaptiveBatchController
```elixir
defmodule RubberDuck.Routing.AdaptiveBatchController do
  use GenServer
  
  # Monitors system metrics and adjusts batching parameters
  def handle_info(:adjust_batch_size, state) do
    new_batch_size = calculate_optimal_batch_size(state.metrics)
    notify_producer(new_batch_size)
    {:noreply, update_state(state, new_batch_size)}
  end
end
```

**Responsibilities**:
- Monitor system metrics (CPU, memory, message queue length)
- Dynamically adjust batch sizes based on performance
- Track throughput and latency metrics
- Coordinate with MessageProducer for parameter updates

#### 4. BatchingTelemetry
```elixir
defmodule RubberDuck.Telemetry.BatchingTelemetry do
  # New telemetry events for batching operations
  @events [
    [:rubber_duck, :batching, :producer, :buffer_status],
    [:rubber_duck, :batching, :batch, :created],
    [:rubber_duck, :batching, :batch, :processed], 
    [:rubber_duck, :batching, :consumer, :demand],
    [:rubber_duck, :batching, :backpressure, :applied],
    [:rubber_duck, :batching, :adaptive, :size_changed]
  ]
end
```

### Integration Points

#### 1. CompileTimeRouter Integration
- Add optional GenStage pipeline routing
- Maintain backward compatibility with direct dispatch
- Feature flag for enabling/disabling batching pipeline
- Performance comparison metrics

#### 2. Supervisor Tree Integration
```elixir
# In RubberDuck.Application
children = [
  # Existing children...
  
  # GenStage Batching Pipeline
  {RubberDuck.Routing.MessageProducer, config[:message_producer]},
  {RubberDuck.Routing.PriorityConsumerPool, config[:consumer_pool]},
  {RubberDuck.Routing.AdaptiveBatchController, config[:batch_controller]},
  
  # Existing children...
]
```

#### 3. Configuration Management
```elixir
# In config/config.exs
config :rubber_duck, :genstage_batching,
  enabled: true,
  message_producer: [
    min_batch_size: 10,
    max_batch_size: 100,
    batch_timeout_ms: 50,
    buffer_size: 1000
  ],
  consumer_pool: [
    critical: [max_concurrency: 1, demand: 5],
    high: [max_concurrency: 4, demand: 20],
    normal: [max_concurrency: 8, demand: 50], 
    low: [max_concurrency: 2, demand: 100]
  ]
```

## Success Criteria

### Performance Metrics
1. **Throughput Improvement**: Target 100,000+ messages/second (35% improvement over Phase 1.2.1)
2. **Back-pressure Effectiveness**: Zero message loss during traffic spikes
3. **Latency Management**: P95 latency < 50ms for high-priority messages
4. **Resource Efficiency**: CPU utilization remains stable under load

### Functional Requirements  
1. **Priority Handling**: Critical messages processed within 10ms
2. **Batch Efficiency**: Average batch utilization > 80%
3. **Adaptive Sizing**: Batch sizes automatically adjust within 30 seconds of load changes
4. **Fault Tolerance**: System recovers from consumer failures within 5 seconds

### Operational Requirements
1. **Telemetry Coverage**: All batching operations emit comprehensive metrics
2. **Configuration Flexibility**: All parameters configurable without code changes
3. **Monitoring Integration**: Dashboard metrics for batch performance and back-pressure
4. **Backward Compatibility**: Existing message routing continues to work unchanged

## Implementation Plan

### Phase 1: Core GenStage Infrastructure (Week 1)
1. **MessageProducer Implementation** ✅
   - Basic GenStage producer with buffer management ✅
   - Size-based and time-based batching triggers ✅
   - Integration with CompileTimeRouter (pending)
   - Basic telemetry emission ✅
   - **Completed**: Full MessageProducer with intelligent batching, back-pressure, and overflow protection

2. **PriorityConsumerPool Implementation** ✅
   - GenStage consumer with priority-based subscription ✅
   - Integration with existing message handlers ✅
   - Error handling and recovery mechanisms ✅
   - Consumer telemetry ✅
   - **Completed**: Full priority-based consumer pool with Task.Supervisor for concurrent processing

3. **Supervisor Integration**
   - Add GenStage components to supervision tree
   - Configure startup order and dependencies
   - Health check integration

### Phase 2: Adaptive Batching (Week 2)
1. **AdaptiveBatchController Implementation**
   - System metrics monitoring (CPU, memory, queue length)
   - Batch size optimization algorithms
   - Dynamic parameter adjustment
   - Performance metrics tracking

2. **Enhanced Telemetry**
   - Comprehensive batching telemetry events
   - Performance dashboards and alerts
   - Back-pressure monitoring
   - Adaptive sizing metrics

3. **Configuration Management**
   - Environment-specific configurations
   - Runtime parameter updates
   - Feature flag implementation

### Phase 3: Integration and Testing (Week 3)
1. **End-to-End Integration**
   - Complete pipeline from router to handlers
   - Error propagation and circuit breakers
   - Graceful degradation mechanisms
   - Load balancing verification

2. **Performance Testing**
   - Benchmark against Phase 1.2.1 performance
   - Load testing with realistic message patterns
   - Back-pressure effectiveness testing
   - Memory and CPU profiling

3. **Documentation and Monitoring**
   - Operation guides and configuration documentation
   - Monitoring setup and alerting rules
   - Performance tuning guidelines

### Phase 4: Production Rollout (Week 4)
1. **Gradual Rollout**
   - Feature flag controlled deployment
   - A/B testing with traffic splitting
   - Performance monitoring and comparison
   - Rollback procedures if needed

2. **Production Validation**
   - Production traffic analysis
   - Performance metric validation
   - Error rate monitoring
   - Capacity planning updates

## Notes/Considerations

### Technical Considerations
1. **Memory Management**: Batch buffers consume memory - need monitoring and limits
2. **Message Ordering**: GenStage may alter message processing order - document implications  
3. **Error Handling**: Failed batches need individual message retry mechanisms
4. **Startup Dependencies**: GenStage components require proper initialization order

### Operational Considerations
1. **Monitoring Complexity**: Additional metrics and dashboards required for batching pipeline
2. **Configuration Tuning**: Optimal parameters may vary by environment and load patterns
3. **Debugging Challenges**: Batched processing makes message tracing more complex
4. **Capacity Planning**: Need to account for buffer memory and processing overhead

### Risk Factors
1. **Performance Regression**: Complex batching logic might reduce throughput in low-load scenarios
2. **Memory Consumption**: Buffering increases memory usage, especially during traffic spikes
3. **Latency Impact**: Batching introduces latency for time-sensitive messages
4. **Complexity Increase**: Additional moving parts increase system complexity and potential failure modes

### Future Enhancements
1. **Message Deduplication**: Add deduplication logic within batches
2. **Cross-Priority Batching**: Smart batching across priority levels when appropriate
3. **External Back-pressure**: Integration with external service health checks
4. **Machine Learning Optimization**: ML-based batch size and timing optimization

---

## Current Implementation Status

### What's Completed ✅
1. **MessageProducer** (`lib/rubber_duck/routing/message_producer.ex`)
   - Full GenStage producer with intelligent batching
   - Size-based and time-based batch triggers
   - Back-pressure management with demand tracking
   - Buffer overflow protection
   - Comprehensive telemetry integration
   
2. **PriorityConsumerPool** (`lib/rubber_duck/routing/priority_consumer_pool.ex`)
   - Priority-based message processing (critical, high, normal, low)
   - Configurable concurrency levels per priority
   - Task.Supervisor for concurrent message processing
   - Automatic failure recovery and retry
   - Statistics tracking per priority level
   
3. **BatchingTelemetry** (`lib/rubber_duck/telemetry/batching_telemetry.ex`)
   - Complete telemetry event definitions
   - Producer, batch, consumer, and backpressure events
   - Default handlers for logging

### What's Next 🚀
1. **Supervisor Integration**: Add GenStage components to application supervision tree
2. **Integration with CompileTimeRouter**: Connect the pipeline to existing routing
3. **Testing**: Create comprehensive tests for producer and consumer
4. **Benchmarking**: Compare performance with Phase 1.2.1 baseline

### How to Test (Once Integrated)
```elixir
# Start the producer
{:ok, producer} = RubberDuck.Routing.MessageProducer.start_link()

# Start the consumer pool
{:ok, consumer} = RubberDuck.Routing.PriorityConsumerPool.start_link()

# Enqueue messages
RubberDuck.Routing.MessageProducer.enqueue(message, context)

# Check stats
RubberDuck.Routing.PriorityConsumerPool.get_stats()
```

**Next Steps**: Complete supervisor integration and connect the GenStage pipeline to the existing CompileTimeRouter for end-to-end message flow.