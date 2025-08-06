# Action Framework Redesign - Phase 1.1

## Problem Statement

The current action modules in RubberDuck are monolithic, with the `UpdateEntity` action alone containing 1005 lines of mixed concerns. This creates several critical issues:

- **Maintenance Nightmare**: Finding and fixing bugs in 1000+ line modules is time-consuming
- **Testing Complexity**: Testing mixed concerns requires complex mocking and setup
- **Code Reusability**: Logic is tightly coupled and cannot be reused across actions
- **Performance Impact**: Large modules increase memory footprint and compilation time
- **Developer Experience**: Onboarding new developers is difficult with such complex modules

### Current State Analysis
- `UpdateEntity` action: 1005 lines
- Mixed responsibilities: validation, impact analysis, execution, learning, propagation
- Mock data fetchers embedded in action (lines 74-139)
- Complex nested logic with deep coupling

## Solution Overview

Implement a decomposed action architecture using:
1. **Thin Orchestrators**: Actions become simple coordinators
2. **Specialized Modules**: Each concern gets its own focused module
3. **Base Behavior**: Common action patterns extracted to `RubberDuck.Action.Base`
4. **Delegation Pattern**: Clear separation of responsibilities

### Key Design Decisions
- **No Backward Compatibility**: Complete rewrite without migration path
- **Module Size Limit**: Max 200 lines per module, ideally 50-100
- **Single Responsibility**: Each module handles exactly one concern
- **Composition Over Inheritance**: Use behaviors and protocols

## Technical Details

### File Structure
```
lib/rubber_duck/
├── actions/
│   ├── base.ex                    # New base behavior (NEW)
│   ├── core/
│   │   ├── update_entity/
│   │   │   ├── validator.ex       # Input validation (NEW)
│   │   │   ├── impact_analyzer.ex # Impact assessment (NEW)
│   │   │   ├── executor.ex        # Core execution (NEW)
│   │   │   ├── learner.ex         # Learning tracker (NEW)
│   │   │   └── propagator.ex      # Change propagation (NEW)
│   │   └── update_entity.ex       # Thin orchestrator (REFACTORED)
```

### Dependencies
- Existing: `Jido.Action`
- New: None required for this phase

### Module Responsibilities

#### `RubberDuck.Action.Base`
- Common action patterns
- Pipeline execution helpers
- Error handling
- Telemetry integration

#### `UpdateEntity.Validator`
- Parameter validation
- Entity state validation
- Change compatibility checks
- Business rule enforcement

#### `UpdateEntity.ImpactAnalyzer`
- Dependency graph analysis
- Change impact scoring
- Risk assessment
- Rollback point identification

#### `UpdateEntity.Executor`
- Apply changes to entity
- Version management
- Snapshot creation
- State transitions

#### `UpdateEntity.Learner`
- Track update outcomes
- Pattern recognition
- Success/failure analysis
- Model updates

#### `UpdateEntity.Propagator`
- Identify affected entities
- Queue dependent updates
- Manage cascade operations
- Handle circular dependencies

## Success Criteria

### Quantitative Metrics
- [ ] No module exceeds 200 lines
- [ ] UpdateEntity orchestrator under 50 lines
- [ ] 95% test coverage on all modules
- [ ] Zero mock data in production code
- [ ] Sub-100ms execution time for typical update

### Qualitative Metrics
- [ ] Clear separation of concerns
- [ ] Each module testable in isolation
- [ ] Self-documenting code structure
- [ ] Easy to understand data flow

## Implementation Plan

### Step 1: Create Base Behavior ✅
- [x] Create `lib/rubber_duck/actions/base.ex`
- [x] Define common callbacks
- [x] Implement pipeline helpers
- [x] Add telemetry hooks
- [x] Write comprehensive tests

### Step 2: Extract Validator Module ⬜
- [ ] Create `lib/rubber_duck/actions/core/update_entity/validator.ex`
- [ ] Move validation logic from UpdateEntity
- [ ] Define validation behavior
- [ ] Implement comprehensive validation rules
- [ ] Write unit tests

### Step 3: Extract ImpactAnalyzer Module ⬜
- [ ] Create `lib/rubber_duck/actions/core/update_entity/impact_analyzer.ex`
- [ ] Move impact assessment logic
- [ ] Implement dependency graph analysis
- [ ] Add risk scoring
- [ ] Write unit tests

### Step 4: Extract Executor Module ⬜
- [ ] Create `lib/rubber_duck/actions/core/update_entity/executor.ex`
- [ ] Move change application logic
- [ ] Implement snapshot management
- [ ] Add version tracking
- [ ] Write unit tests

### Step 5: Extract Learner Module ⬜
- [ ] Create `lib/rubber_duck/actions/core/update_entity/learner.ex`
- [ ] Move learning/tracking logic
- [ ] Implement outcome analysis
- [ ] Add pattern recognition
- [ ] Write unit tests

### Step 6: Extract Propagator Module ⬜
- [ ] Create `lib/rubber_duck/actions/core/update_entity/propagator.ex`
- [ ] Move propagation logic
- [ ] Implement cascade management
- [ ] Add circular dependency detection
- [ ] Write unit tests

### Step 7: Refactor UpdateEntity as Orchestrator ⬜
- [ ] Refactor to thin orchestrator
- [ ] Use delegation pattern
- [ ] Remove all business logic
- [ ] Coordinate module interactions
- [ ] Write integration tests

### Step 8: Remove Mock Data ⬜
- [ ] Create proper repository layer
- [ ] Move entity fetching to repositories
- [ ] Remove all mock fetch functions
- [ ] Update tests to use factories

### Step 9: Integration Testing ⬜
- [ ] End-to-end action tests
- [ ] Performance benchmarks
- [ ] Error handling scenarios
- [ ] Concurrent update tests

### Step 10: Documentation & Cleanup ⬜
- [ ] Update module documentation
- [ ] Create architecture diagrams
- [ ] Write migration guide
- [ ] Remove old code

## Current Status

### What Works
- ✅ Base behavior module (`RubberDuck.Action.Base`) fully implemented
- ✅ Delegation pattern with telemetry integration
- ✅ Pipeline execution helpers for chaining operations
- ✅ Error handling and rollback support
- ✅ All 14 tests passing

### What's Next
- Step 2: Extract Validator Module from UpdateEntity

### How to Run
```bash
# Run base behavior tests
mix test test/rubber_duck/actions/base_test.exs

# All tests pass successfully
```

## Notes/Considerations

### Risks
- Complex refactoring may introduce bugs
- Need to maintain system functionality during refactor
- Learning curve for new architecture

### Future Improvements
- Consider using GenStage for pipeline processing
- Add caching layer for impact analysis
- Implement parallel execution where possible

### Migration Strategy
1. Implement new architecture alongside old
2. Run both in parallel for validation
3. Switch over when confident
4. Remove old code in separate PR

### Edge Cases to Consider
- Concurrent updates to same entity
- Circular dependency chains
- Partial update failures
- Rollback scenarios
- Large batch updates

## Agent Consultations Needed

### Planned Consultations
1. **elixir-expert**: Best practices for behavior definition and delegation patterns
2. **senior-engineer-reviewer**: Architectural validation and module boundaries
3. **research-agent**: Pipeline processing patterns and error handling strategies

### Questions for Consultation
- Optimal way to implement delegation in Elixir
- Error handling patterns for pipeline processing
- Testing strategies for decomposed modules
- Performance implications of module boundaries

---

*Last Updated: [To be updated as implementation progresses]*
*Status: Planning Complete - Ready for Implementation*