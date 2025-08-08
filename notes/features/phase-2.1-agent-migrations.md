# Phase 2.1: High-Priority Agent Migration Plan

## Executive Summary

Phase 2.1 focuses on migrating three high-priority agents from the legacy signal-based system to the new typed message handling system. This follows the successful completion of Phase 1, where all skills were migrated to use typed messages exclusively.

**Agents in Scope:**
- LLMOrchestratorAgent
- AIAnalysisAgent  
- LLMMonitoringAgent

**Goal:** Remove all `handle_signal` functions and ensure all functionality uses `handle_instruction` with typed messages, maintaining backward compatibility during the migration.

## Current State Analysis

### LLMOrchestratorAgent
- **Location:** `/lib/rubber_duck/agents/llm_orchestrator_agent.ex`
- **Signal Handlers:** 2 functions (`handle_signal`)
  - `@signal_request_completed` (line 260)
  - `@signal_request_failed` (line 283)
- **Typed Handlers:** 4 functions (`handle_instruction`)
  - `{:complete, request}` (line 74)
  - `{:stream, request}` (line 85)
  - `{:fallback, msg}` (line 96)
  - `{:select_provider, msg}` (line 108)
- **Status:** Mixed implementation - has both signal and typed message handlers

### AIAnalysisAgent
- **Location:** `/lib/rubber_duck/agents/ai_analysis_agent.ex`
- **Signal Handlers:** 4 functions (`handle_signal`)
  - `@project_changed` (line 248)
  - `@file_modified` (line 262)
  - `@analysis_requested` (line 276)
  - `@feedback_received` (line 286)
- **Typed Handlers:** 6+ functions (`handle_instruction`)
  - `{:analyze_project, project_id}` (line 80)
  - `{:analyze_code_file, file_id}` (line 98)
  - `{:schedule_analysis, params}` (line 123)
  - `{:process_feedback, feedback}` (line 134)
  - `{:discover_patterns, scope}` (line 152)
  - `{:generate_insights, context}` (line 171)
  - Additional compatibility handlers for message routing
- **Status:** Mixed implementation - comprehensive typed handlers with legacy signal support

### LLMMonitoringAgent
- **Location:** `/lib/rubber_duck/agents/llm_monitoring_agent.ex`
- **Signal Handlers:** 5 functions (`handle_signal`)
  - `"llm.health.provider.failed"` (line 88)
  - `"llm.health.provider.degraded"` (line 105)
  - `"llm.health.provider.healthy"` (line 122)
  - `"llm.health.check.completed"` (line 134)
  - `"llm.fallback.triggered"` (line 160)
- **Typed Handlers:** 4 functions (`handle_instruction`)
  - `{:diagnose_provider, provider_name}` (line 175)
  - `{:predict_failures, time_window}` (line 181)
  - `:get_health_summary` (line 187)
  - `{:health_check, msg}` (line 193)
- **Status:** Mixed implementation - signal-heavy with some typed handlers

## Available Typed Messages

The following typed message structures are available for routing:

### LLM Domain Messages
- `RubberDuck.Messages.LLM.HealthCheck` - Health check operations
- `RubberDuck.Messages.LLM.Fallback` - Fallback operations
- `RubberDuck.Messages.LLM.ProviderSelect` - Provider selection
- `RubberDuck.Messages.LLM.Complete` - LLM completion requests

### AI Domain Messages  
- `RubberDuck.Messages.AI.Analyze` - Analysis requests
- `RubberDuck.Messages.AI.QualityAssess` - Quality assessment
- `RubberDuck.Messages.AI.PatternDetect` - Pattern detection
- `RubberDuck.Messages.AI.InsightGenerate` - Insight generation

### Message Protocol Features
- Strong typing with validation
- Automatic routing via `route/2` function
- Priority and timeout handling
- Backward compatibility via `to_jido_signal/1`

## Migration Strategy

### Phase 2.1.1: LLMOrchestratorAgent
**Priority:** High (core LLM operations)

**Signal → Message Mappings:**
1. `@signal_request_completed` → Use existing `RubberDuck.Messages.LLM.Complete` response handling
2. `@signal_request_failed` → Use existing `RubberDuck.Messages.LLM.Fallback` message

**Implementation Steps:**
1. Analyze signal payload structures and map to typed message fields
2. Create handler adapters that convert signal logic to instruction logic
3. Route incoming typed messages to new handlers
4. Update `emit_signal` calls to use typed message routing
5. Remove signal handler functions
6. Update tests to use typed messages

### Phase 2.1.2: AIAnalysisAgent  
**Priority:** High (analysis workflows)

**Signal → Message Mappings:**
1. `@project_changed` → `RubberDuck.Messages.AI.Analyze` with `:project` type
2. `@file_modified` → `RubberDuck.Messages.AI.Analyze` with `:code` type
3. `@analysis_requested` → `RubberDuck.Messages.AI.Analyze` (direct mapping)
4. `@feedback_received` → Use existing learning message infrastructure

**Implementation Steps:**
1. Convert signal subscription logic to message routing
2. Refactor signal payloads to use typed message structures
3. Update autonomous scheduling to emit typed messages
4. Migrate pattern detection to use `RubberDuck.Messages.AI.PatternDetect`
5. Remove signal handler functions
6. Update integration tests

### Phase 2.1.3: LLMMonitoringAgent
**Priority:** Medium (monitoring and health)

**Signal → Message Mappings:**
1. `"llm.health.provider.*"` signals → `RubberDuck.Messages.LLM.HealthCheck`
2. `"llm.health.check.completed"` → Enhanced `RubberDuck.Messages.LLM.HealthCheck` with results
3. `"llm.fallback.triggered"` → `RubberDuck.Messages.LLM.Fallback`

**Implementation Steps:**
1. Consolidate health-related signals into typed messages
2. Update health metric collection to use typed messages
3. Refactor corrective action logic to emit typed messages
4. Remove signal subscription and handler functions
5. Update health monitoring tests

## Jido Best Practices Integration

Based on Jido usage rules, the migration will follow these principles:

### 1. Pure Function Patterns
- All `handle_instruction` functions will return tagged tuples
- State updates will be immutable
- Error handling will use pattern matching

### 2. Schema Validation
- All agent state schemas are already defined
- Message validation will be handled by the Protocol implementation
- Parameter validation will use pattern matching in function heads

### 3. OTP Integration
- Agents will maintain supervision tree compatibility
- Error recovery will use lifecycle hooks (`on_error`)
- Process communication will use `GenServer.call/cast` patterns

### 4. Functional Composition
- Message handlers will compose smaller, pure functions  
- Complex workflows will be broken into discrete steps
- Error propagation will use `with` statements

## Implementation Plan

### Step 1: Create Message Handler Adapters (Week 1)

For each agent, create adapter functions that:
1. Accept typed messages
2. Extract relevant data
3. Call existing business logic
4. Return properly formatted responses

```elixir
# Example adapter pattern
def handle_instruction({:health_status_changed, msg}, agent) do
  # Extract from typed message
  provider = msg.provider
  status = msg.status
  
  # Call existing business logic
  updated_agent = update_provider_status(agent, provider, status)
  
  # Return proper format
  {:ok, %{status_updated: true}, updated_agent}
end
```

### Step 2: Update Message Routing (Week 1)

Update the `RubberDuck.Routing.MessageRouter` to properly route messages to the new handlers:

1. Ensure all target message types have proper routing rules
2. Test message validation and routing
3. Verify priority and timeout handling

### Step 3: Migrate Signal Emission (Week 2)

Replace `emit_signal` calls throughout the agents with typed message emission:

```elixir
# Old approach
emit_signal(@signal_request_completed, payload)

# New approach  
message = %RubberDuck.Messages.LLM.Complete{...}
MessageRouter.route(message)
```

### Step 4: Remove Signal Handlers (Week 2)

Systematically remove `handle_signal` functions:
1. Verify all functionality is covered by typed handlers
2. Remove signal subscription logic from `init/1`
3. Clean up signal constant definitions
4. Remove signal-related helper functions

### Step 5: Update Tests (Week 3)

Migrate all tests to use typed messages:
1. Update unit tests to call `handle_instruction` instead of `handle_signal`
2. Use typed message structures in test data
3. Test message validation and routing
4. Add integration tests for end-to-end message flows

### Step 6: Validation and Cleanup (Week 3)

Final validation phase:
1. Run full test suite to ensure no regressions
2. Test agent startup and supervision
3. Verify message routing in development environment
4. Clean up any remaining legacy code
5. Update documentation

## Backward Compatibility Strategy

During the migration, backward compatibility will be maintained through:

### 1. Message Protocol Compatibility
- All typed messages implement `to_jido_signal/1` for legacy support
- Existing signal subscribers can continue to work during transition
- Gradual migration of signal emitters to typed messages

### 2. Dual Handler Support (Temporary)
- Keep both signal and typed handlers during migration period
- Route legacy signals to new typed handlers via adapter pattern
- Remove signal handlers only after full validation

### 3. Configuration Compatibility
- Agent configuration schemas remain unchanged
- Existing supervision tree structure maintained
- No breaking changes to agent initialization

## Testing Strategy

### Unit Tests
For each agent, create comprehensive unit tests covering:

```elixir
describe "handle_instruction/2" do
  test "handles health check message" do
    msg = %RubberDuck.Messages.LLM.HealthCheck{
      provider: :openai,
      check_type: :full
    }
    
    {:ok, result, _updated_agent} = 
      LLMMonitoringAgent.handle_instruction({:health_check, msg}, initial_agent)
    
    assert result.overall_status in [:healthy, :degraded, :unhealthy]
  end
end
```

### Integration Tests
Test complete message flows:

1. Message creation and validation
2. Router message delivery 
3. Agent message handling
4. Response message generation
5. State updates and persistence

### Performance Tests
Verify that the typed message system maintains performance:

1. Message routing latency
2. Agent response times
3. Memory usage patterns
4. Process message queue behavior

### Compatibility Tests
Ensure smooth transition:

1. Legacy signal handling during migration
2. Mixed message/signal environments
3. Agent restart and recovery scenarios
4. Supervision tree stability

## Success Criteria

### Functional Requirements
- [ ] All `handle_signal` functions removed from target agents
- [ ] All functionality accessible via `handle_instruction` with typed messages
- [ ] Agent state management unchanged
- [ ] No breaking changes to agent APIs
- [ ] Full test coverage for new message handlers

### Performance Requirements  
- [ ] Message handling latency within 5% of signal handling
- [ ] No increase in memory usage per agent
- [ ] Agent startup time unchanged
- [ ] System throughput maintained under load

### Quality Requirements
- [ ] 100% test coverage for new message handlers
- [ ] No regressions in existing functionality
- [ ] Code complexity metrics maintained or improved
- [ ] Documentation updated for new patterns

### Operational Requirements
- [ ] Agents start and stop cleanly
- [ ] Supervision tree recovery works correctly
- [ ] Message routing errors handled gracefully
- [ ] Logging and observability maintained

## Risk Mitigation

### High-Risk Areas
1. **State Consistency:** Agent state updates during migration
   - *Mitigation:* Comprehensive state validation tests
   - *Rollback:* Keep signal handlers until full validation

2. **Message Routing:** Complex message routing logic
   - *Mitigation:* Unit tests for all routing scenarios
   - *Rollback:* Fallback to signal-based routing

3. **Performance Impact:** Typed message overhead
   - *Mitigation:* Performance benchmarks before/after
   - *Rollback:* Optimize message structures if needed

### Medium-Risk Areas
1. **Integration Complexity:** Multiple agent interactions
   - *Mitigation:* Integration test suite
   - *Rollback:* Phased migration approach

2. **Test Coverage:** Comprehensive test migration
   - *Mitigation:* Test-driven migration approach
   - *Rollback:* Maintain parallel test suites

## Timeline

### Week 1: Foundation
- Create message handler adapters for all three agents
- Update message routing configuration
- Begin LLMOrchestratorAgent migration

### Week 2: Core Migration  
- Complete LLMOrchestratorAgent migration
- Migrate AIAnalysisAgent signal handlers
- Update message emission patterns

### Week 3: Completion
- Complete LLMMonitoringAgent migration
- Comprehensive testing and validation
- Documentation updates and cleanup

### Week 4: Buffer
- Address any issues found in testing
- Performance optimization if needed
- Final validation and sign-off

## Dependencies

### Internal Dependencies
- Message routing system must be stable
- All required typed messages must be implemented
- Base agent infrastructure must support instruction handling

### External Dependencies  
- No external service changes required
- No database schema changes required
- No configuration file changes required

## Monitoring and Observability

During and after migration:

### Metrics to Track
- Agent message processing latency
- Message routing success rates
- Agent restart frequency
- Error rates by message type

### Logging Enhancements
- Message routing decisions
- Handler selection logic
- State transition logging
- Performance timing logs

### Alerting
- Agent startup failures
- Message routing errors
- Handler execution timeouts
- State validation failures

## Conclusion

Phase 2.1 represents a critical step in the modernization of the RubberDuck agent system. By migrating these three high-priority agents to the typed message system, we will:

1. **Improve Type Safety:** Eliminate runtime signal routing errors
2. **Enhance Maintainability:** Clear message contracts and validation
3. **Enable Future Features:** Foundation for advanced message features
4. **Maintain Stability:** Backward compatibility during transition

The systematic approach outlined in this plan ensures minimal risk while achieving the architectural goals of the typed message system migration.

## Next Steps

1. **Review and Approval:** Get stakeholder approval for the migration plan
2. **Resource Allocation:** Assign developers to the migration tasks
3. **Environment Setup:** Prepare development and testing environments
4. **Execution:** Begin with Week 1 foundation work
5. **Progress Tracking:** Regular check-ins and milestone reviews

---

*Document Version: 1.0*  
*Created: 2025-08-08*  
*Status: Draft - Pending Review*