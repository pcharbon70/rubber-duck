# Skills System Complete Rewrite - Phase 2 Planning Document

## Problem Statement

The current skills system suffers from significant architectural issues that impede maintainability, testing, and evolution:

### Current State Analysis
- **CodeAnalysisSkill**: 1,154 lines with mixed concerns (security, performance, quality, impact)
- **LearningSkill**: 1,147 lines combining experience tracking, pattern analysis, and optimization
- **ProjectManagementSkill**: 1,112 lines handling project lifecycle, monitoring, and analytics
- **UserManagementSkill**: 933 lines mixing authentication, preferences, and activity tracking

### Critical Issues
1. **Monolithic Design**: Each skill handles multiple unrelated concerns
2. **Code Duplication**: Similar patterns repeated across skills (validation, error handling, telemetry)
3. **Testing Complexity**: Large modules are difficult to unit test effectively
4. **String-Based Signals**: Mix of legacy string patterns and typed messages creates confusion
5. **Mixed Responsibilities**: Skills act as both orchestrators and analyzers
6. **Poor Separation**: Business logic intertwined with signal handling

### Impact on Development
- Adding new analysis types requires modifying large files
- Bug fixes risk breaking unrelated functionality
- Testing requires complex setup and mocking
- Code reviews are challenging due to file size
- New team members face steep learning curve

## Solution Overview

### Core Architecture: Analyzer Pattern with Jido Compatibility

The solution maintains full `Jido.Skill` compatibility while decomposing monoliths into focused, composable components:

```
Skills (Thin Orchestrators)          Analyzers (Focused Components)
├── CodeAnalysisSkill (~80 lines)   ├── Code/Security (~120 lines)
├── LearningSkill (~90 lines)       ├── Code/Performance (~110 lines)
├── ProjectManagementSkill (~85)    ├── Code/Quality (~130 lines)
└── UserManagementSkill (~75)       ├── Learning/PatternDetector (~140)
                                    ├── Learning/ExperienceTracker (~95)
                                    ├── Project/HealthMonitor (~105)
                                    └── User/ActivityAnalyzer (~115)
```

### Key Design Principles
1. **Single Responsibility**: Each analyzer handles one specific concern
2. **Functional Core**: Analyzers are pure functions with explicit dependencies
3. **Jido Compatibility**: Skills continue to use `Jido.Skill` and handle signals
4. **Type Safety**: Leverage typed messages over string-based signals
5. **Composable Design**: Analyzers can be combined in different ways

## Agent Consultations

### Elixir Expert Consultation Results

**Architecture Recommendations:**
- Use behavior pattern for analyzers with consistent interface
- Prefer stateless analyzers (pure functions) over GenServer for simplicity
- Implement composition via pipeline pattern for complex analysis flows
- Use tagged tuples consistently: `{:ok, result}` | `{:error, reason}`

**Behavior Pattern:**
```elixir
@callback analyze(message :: struct(), context :: map()) :: 
  {:ok, result :: map()} | {:error, reason :: term()}

@callback validate(message :: struct()) :: 
  {:ok, message :: struct()} | {:error, reason :: term()}

@callback supported_types() :: [atom()]
```

**Composition Strategy:**
```elixir
# Pipeline composition for complex analysis
def run_analysis(message, analyzers) do
  analyzers
  |> Enum.reduce_while({:ok, %{message: message, results: []}}, fn analyzer, {:ok, acc} ->
    case analyzer.analyze(acc.message, context) do
      {:ok, result} -> {:cont, {:ok, %{acc | results: [result | acc.results]}}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end)
end
```

### Senior Engineer Consultation Results

**Compatibility Strategy:**
- Skills remain as `Jido.Skill` modules to preserve signal routing
- Skills delegate to analyzers while maintaining all Jido callbacks
- Gradual migration path preserves existing functionality
- Error handling and telemetry remain at skill level

**Migration Safety:**
- Phase 1: Extract analyzers while keeping skills unchanged externally  
- Phase 2: Skills delegate to analyzers internally
- Phase 3: Remove duplicate logic from skills
- Phase 4: Optimize analyzer composition

## Technical Details

### File Structure

```
lib/rubber_duck/
├── skills/                           # Jido.Skill orchestrators (~80 lines each)
│   ├── base.ex                      # Common skill patterns (existing)
│   ├── code_analysis_skill.ex       # Delegates to Code analyzers
│   ├── learning_skill.ex            # Delegates to Learning analyzers  
│   ├── project_management_skill.ex  # Delegates to Project analyzers
│   └── user_management_skill.ex     # Delegates to User analyzers
├── analyzers/                        # New analyzer modules
│   ├── analyzer.ex                  # Behavior definition
│   ├── code/                        # Code analysis analyzers
│   │   ├── security.ex              # Security-focused analysis (~120 lines)
│   │   ├── performance.ex           # Performance analysis (~110 lines)
│   │   ├── quality.ex               # Code quality metrics (~130 lines)
│   │   └── impact.ex                # Change impact analysis (~125 lines)
│   ├── learning/                    # Learning system analyzers
│   │   ├── pattern_detector.ex      # Pattern recognition (~140 lines)
│   │   ├── experience_tracker.ex    # Experience management (~95 lines)
│   │   ├── feedback_processor.ex    # Feedback analysis (~105 lines)
│   │   └── optimizer.ex             # Optimization logic (~115 lines)
│   ├── project/                     # Project management analyzers
│   │   ├── health_monitor.ex        # Project health (~105 lines)
│   │   ├── structure_analyzer.ex    # Structure analysis (~120 lines)
│   │   ├── dependency_tracker.ex    # Dependency management (~100 lines)
│   │   └── metrics_collector.ex     # Metrics collection (~90 lines)
│   └── user/                        # User management analyzers
│       ├── activity_analyzer.ex     # Activity tracking (~115 lines)
│       ├── preference_manager.ex    # Preference management (~80 lines)
│       ├── session_validator.ex     # Session validation (~95 lines)
│       └── behavior_tracker.ex      # Behavior analysis (~110 lines)
└── analyzer_registry.ex             # Central registry for analyzer discovery
```

### Analyzer Behavior Definition

```elixir
defmodule RubberDuck.Analyzer do
  @moduledoc """
  Behavior for focused analysis components.
  
  Analyzers are stateless, pure functions that process typed messages
  and return analysis results. They integrate with Jido skills while
  maintaining separation of concerns.
  """
  
  @callback analyze(message :: struct(), context :: map()) :: 
    {:ok, result :: map()} | {:error, reason :: term()}
    
  @callback validate(message :: struct()) :: 
    {:ok, message :: struct()} | {:error, reason :: term()}
    
  @callback supported_types() :: [atom()]
  
  @callback priority() :: :low | :normal | :high | :critical
  
  @callback timeout() :: pos_integer()
  
  @optional_callbacks validate: 1, priority: 0, timeout: 0
end
```

### Example Implementation: Security Analyzer

```elixir
defmodule RubberDuck.Analyzers.Code.Security do
  @moduledoc """
  Security-focused code analysis.
  
  Identifies potential security vulnerabilities, unsafe patterns,
  and compliance issues in code files.
  """
  
  @behaviour RubberDuck.Analyzer
  
  @impl true
  def analyze(%Messages.Code.Analyze{analysis_type: :security} = msg, context) do
    with {:ok, parsed} <- parse_code(msg.file_path),
         {:ok, vulnerabilities} <- scan_vulnerabilities(parsed),
         {:ok, compliance} <- check_compliance(parsed, context) do
      
      result = %{
        vulnerabilities: vulnerabilities,
        compliance_score: compliance.score,
        security_rating: calculate_security_rating(vulnerabilities, compliance),
        recommendations: generate_security_recommendations(vulnerabilities),
        analyzed_at: DateTime.utc_now()
      }
      
      {:ok, result}
    end
  end
  
  def analyze(%Messages.Code.SecurityScan{} = msg, context) do
    # Handle security-specific message
    scan_for_security_issues(msg, context)
  end
  
  def analyze(message, _context) do
    {:error, {:unsupported_message_type, message.__struct__}}
  end
  
  @impl true
  def supported_types do
    [Messages.Code.Analyze, Messages.Code.SecurityScan]
  end
  
  @impl true
  def priority, do: :high
  
  @impl true  
  def timeout, do: 15_000
  
  # Private implementation functions...
  defp scan_vulnerabilities(parsed_code), do: {:ok, []}
  defp check_compliance(parsed_code, context), do: {:ok, %{score: 0.95}}
  defp calculate_security_rating(vulns, compliance), do: :medium
  defp generate_security_recommendations(vulns), do: []
  defp parse_code(file_path), do: {:ok, %{}}
end
```

### Skills Integration Pattern

```elixir
defmodule RubberDuck.Skills.CodeAnalysisSkill do
  use RubberDuck.Skills.Base,
    name: "code_analysis",
    description: "Orchestrates code analysis through specialized analyzers",
    signal_patterns: ["code.analyze.*", "code.quality.*", "code.security.*"]
  
  alias RubberDuck.Analyzers.Code.{Security, Performance, Quality, Impact}
  alias RubberDuck.AnalyzerRegistry
  
  # Handle typed messages
  def handle_analyze(%Messages.Code.Analyze{} = message, context) do
    with {:ok, analyzers} <- get_analyzers_for_message(message),
         {:ok, results} <- run_analysis_pipeline(message, analyzers, context) do
      
      # Combine results from all analyzers
      combined_result = combine_analysis_results(results)
      emit_analysis_complete(combined_result)
      
      {:ok, combined_result}
    end
  end
  
  # Legacy signal support during migration
  def handle_signal_legacy(%{type: "code.analyze.file"} = signal, state) do
    # Convert to typed message and delegate
    case SignalAdapter.from_signal(signal) do
      {:ok, message} -> handle_analyze(message, %{state: state})
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp get_analyzers_for_message(%Messages.Code.Analyze{analysis_type: :comprehensive}) do
    {:ok, [Security, Performance, Quality, Impact]}
  end
  
  defp get_analyzers_for_message(%Messages.Code.Analyze{analysis_type: type}) do
    case type do
      :security -> {:ok, [Security]}
      :performance -> {:ok, [Performance]}
      :quality -> {:ok, [Quality]}
    end
  end
  
  defp run_analysis_pipeline(message, analyzers, context) do
    # Run analyzers in parallel for better performance
    tasks = Enum.map(analyzers, fn analyzer ->
      Task.async(fn -> analyzer.analyze(message, context) end)
    end)
    
    results = Task.await_many(tasks, 30_000)
    
    # Check for errors
    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {successes, []} ->
        {:ok, Enum.map(successes, fn {:ok, result} -> result end)}
      {_, errors} ->
        {:error, {:analyzer_failures, errors}}
    end
  end
  
  defp combine_analysis_results(results) do
    %{
      overall_score: calculate_overall_score(results),
      detailed_results: results,
      summary: generate_summary(results),
      timestamp: DateTime.utc_now()
    }
  end
end
```

### Error Handling and Fault Tolerance

1. **Analyzer Failures**: If one analyzer fails, others continue processing
2. **Timeout Handling**: Each analyzer has configurable timeout
3. **Circuit Breaker**: Protect against cascading failures
4. **Fallback Strategies**: Graceful degradation when analyzers unavailable
5. **Error Aggregation**: Collect and report all analyzer errors

### Testing Strategy

```elixir
# Analyzer unit tests (focused and fast)
defmodule SecurityAnalyzerTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Analyzers.Code.Security
  
  test "detects SQL injection vulnerabilities" do
    message = %Messages.Code.Analyze{
      file_path: "test_files/vulnerable.ex",
      analysis_type: :security
    }
    
    assert {:ok, result} = Security.analyze(message, %{})
    assert length(result.vulnerabilities) > 0
    assert Enum.any?(result.vulnerabilities, &(&1.type == :sql_injection))
  end
end

# Skills integration tests  
defmodule CodeAnalysisSkillTest do
  use ExUnit.Case
  
  test "orchestrates multiple analyzers correctly" do
    message = %Messages.Code.Analyze{
      file_path: "test.ex",
      analysis_type: :comprehensive
    }
    
    assert {:ok, result} = CodeAnalysisSkill.handle_analyze(message, %{})
    assert Map.has_key?(result, :security_results)
    assert Map.has_key?(result, :performance_results)
    assert Map.has_key?(result, :quality_results)
  end
end
```

## Success Criteria

### Quantitative Metrics
- [ ] Each analyzer module < 200 lines (target: 50-150 lines)
- [ ] Skills reduced to < 100 lines each (orchestration only)
- [ ] Test coverage maintained > 90%
- [ ] Performance impact < 5% (due to improved parallelization)
- [ ] Zero breaking changes to external API

### Qualitative Outcomes
- [ ] Clear separation of concerns achieved
- [ ] New analysis types can be added without modifying skills
- [ ] Analyzers are independently testable
- [ ] Code is more maintainable and readable
- [ ] Documentation clarity improved

### Compatibility Verification
- [ ] All existing Jido signal patterns continue working
- [ ] Skills maintain same external interface
- [ ] Agent integration unchanged
- [ ] Typed message support enhanced

## Implementation Plan

### Phase 1: Foundation (Week 1-2)
1. **Create Analyzer Behavior**
   - Define `RubberDuck.Analyzer` behavior
   - Create `AnalyzerRegistry` for discovery
   - Set up testing infrastructure

2. **Extract First Analyzer**
   - Start with `Code.Security` analyzer
   - Extract from `CodeAnalysisSkill` 
   - Maintain parallel operation with existing code

3. **Validation**
   - Verify extracted analyzer works correctly
   - Confirm no regression in security analysis
   - Validate performance characteristics

### Phase 2: Core Analyzers (Week 3-4)
1. **Extract Core Code Analyzers**
   - `Code.Performance` from CodeAnalysisSkill
   - `Code.Quality` from CodeAnalysisSkill  
   - `Code.Impact` from CodeAnalysisSkill

2. **Update Skills to Delegate**
   - Modify CodeAnalysisSkill to use extracted analyzers
   - Implement parallel analyzer execution
   - Add error handling and result combining

3. **Testing and Validation**
   - Unit test each analyzer independently
   - Integration test skill orchestration
   - Performance benchmarking

### Phase 3: Learning Analyzers (Week 5-6)
1. **Extract Learning Components**
   - `Learning.PatternDetector`
   - `Learning.ExperienceTracker`
   - `Learning.FeedbackProcessor`
   - `Learning.Optimizer`

2. **Update LearningSkill**
   - Delegate to extracted analyzers
   - Maintain state management patterns
   - Handle cross-analyzer communication

### Phase 4: Project & User Analyzers (Week 7-8)
1. **Extract Remaining Analyzers**
   - Project management analyzers
   - User management analyzers

2. **Complete Skills Migration**
   - All skills become thin orchestrators
   - Remove duplicated code
   - Optimize analyzer composition

### Phase 5: Optimization & Cleanup (Week 9-10)
1. **Performance Optimization**
   - Implement analyzer caching where appropriate
   - Optimize parallel execution patterns
   - Add circuit breaker for fault tolerance

2. **Documentation and Testing**
   - Complete analyzer documentation
   - Comprehensive integration testing
   - Performance benchmarking vs original

3. **Migration Cleanup**
   - Remove deprecated code paths
   - Clean up test suites
   - Update development documentation

## Migration Strategy

### Backward Compatibility Approach
1. **Parallel Operation**: New analyzers run alongside existing code initially
2. **Feature Flagging**: Toggle between old and new implementations
3. **Gradual Rollout**: Migrate analysis types one at a time
4. **Rollback Plan**: Quick revert to original implementation if issues arise

### Risk Mitigation
- **Comprehensive Testing**: Both unit and integration tests before each phase
- **Performance Monitoring**: Continuous performance tracking during migration
- **Gradual Deployment**: Phase rollouts with monitoring
- **Feature Flags**: Ability to quickly disable new analyzers if needed

### Data Consistency
- **Message Format Compatibility**: Analyzers accept both new typed messages and converted legacy signals
- **Result Format Stability**: Analysis results maintain same structure for consumers
- **State Migration**: Learning system state preserved during analyzer extraction

## Monitoring and Observability

### Telemetry Points
- Analyzer execution time and success rate
- Skill orchestration performance
- Error rates by analyzer type
- Message routing efficiency

### Alerting
- Analyzer failure thresholds
- Performance degradation alerts
- Error rate increase notifications

### Dashboard Metrics
- Analysis throughput by type
- Analyzer performance comparisons
- Error distribution across analyzers
- Skills orchestration efficiency

## Benefits Realization

### Immediate Benefits (Phase 1-2)
- **Improved Testability**: Security analyzer can be tested independently
- **Clearer Code Organization**: Focused modules with single responsibilities
- **Faster Development**: New security checks don't require touching skill files

### Medium-term Benefits (Phase 3-5)
- **Parallel Processing**: Multiple analyzers run concurrently
- **Reusable Components**: Analyzers can be shared across skills
- **Easier Maintenance**: Bug fixes isolated to specific analyzers

### Long-term Benefits (Post-Implementation)
- **Extensibility**: New analysis types easily added as new analyzers
- **Performance**: Better resource utilization through parallelization
- **Team Velocity**: Developers can work on analyzers independently
- **Code Quality**: Smaller, focused modules are easier to review and maintain

This comprehensive rewrite maintains full Jido.Skill compatibility while achieving the modularity and maintainability goals through the analyzer pattern. The phased approach ensures safety while delivering incremental value throughout the implementation process.