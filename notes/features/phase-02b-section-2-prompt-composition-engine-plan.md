# Feature: Phase 02b Section 2 - Prompt Composition Engine

## Problem Statement

### Current State
- **Phase 02b Section 1.1 Complete**: Core Prompt Resources (Prompt, PromptVersion, PromptUsage, PromptCategory) are fully implemented with hierarchical architecture
- **No Composition System**: Missing prompt composition engine to combine System/Project/User prompts into cohesive final prompts
- **No Variable Interpolation**: No secure variable substitution system for dynamic prompt customization
- **Missing LLM Integration**: No integration with existing LLMOrchestratorAgent for composed prompt injection
- **No Performance Optimization**: Missing intelligent caching and token optimization for prompt composition
- **No Security Validation**: Missing prompt injection prevention and content sanitization for composed prompts

### Business Impact
- **Limited Prompt Utility**: Users cannot leverage the hierarchical prompt system without composition capabilities
- **Poor Performance**: No caching system leads to repeated database queries and slow prompt resolution
- **Security Vulnerabilities**: No protection against prompt injection through variable interpolation or composition
- **Integration Gaps**: Cannot integrate composed prompts with existing LLM orchestration and RAG systems
- **Token Inefficiency**: No intelligent compression or optimization for model-specific token limits

### User Need
- **Hierarchical Composition**: Deterministic composition of System → Project → User prompts with proper inheritance
- **Variable Interpolation**: Safe and secure variable substitution with context awareness and validation
- **Performance Optimization**: Sub-50ms prompt resolution with intelligent multi-tier caching
- **LLM Integration**: Seamless integration with existing LLM orchestration for provider-specific formatting
- **Security Assurance**: Comprehensive security validation with prompt injection prevention

## Solution Overview

### Approach
Implement Phase 02b Section 2 by creating a comprehensive Prompt Composition Engine that builds upon the Core Prompt Resources foundation. This approach provides hierarchical prompt composition with deterministic resolution order (System → Project → User), secure variable interpolation, intelligent multi-tier caching, and seamless integration with existing LLM orchestration and RAG systems while maintaining security and performance optimization.

### Key Design Decisions
1. **Composition Engine Architecture**: Modular composition system with CompositionEngine, PromptResolver, VariableInterpolator, and TokenOptimizer
2. **Hierarchical Resolution**: Deterministic System → Project → User composition order with inheritance and override patterns
3. **Multi-Tier Caching**: Three-tier caching strategy (ETS → Redis → DETS) for sub-50ms resolution performance
4. **Security Integration**: Comprehensive prompt injection prevention with variable validation and content sanitization
5. **LLM Integration**: Seamless integration with existing LLMOrchestratorAgent and UniversalProviderService
6. **Performance Optimization**: Token-aware compression with model-specific optimization for different LLM providers

### Integration Points
- **Core Prompt Resources**: Build upon completed Prompt, PromptVersion, PromptUsage, PromptCategory resources
- **LLM Orchestration**: Integration with LLMOrchestratorAgent and provider selection systems
- **RAG System**: Enhanced context injection with project-specific prompts and user preferences
- **Reactor Workflows**: Support for named prompt references in workflow definitions
- **User Preferences**: Integration with Phase 1A user preference system for personalization
- **Security Systems**: Integration with existing authentication and authorization infrastructure

## Agent Consultations Performed

### research-agent
**Research Topic**: Modern prompt composition patterns, multi-tier caching strategies, and prompt injection prevention techniques
**Findings**: Research revealed advanced prompt composition techniques from OpenAI and Anthropic, multi-tier caching patterns from Redis Labs, and comprehensive prompt injection prevention strategies from OWASP. Key insights include hierarchical composition with inheritance patterns, intelligent cache warming strategies, and ML-based security validation approaches.

### elixir-expert
**Consultation Topic**: Elixir/Phoenix caching patterns, GenServer architecture, and Ash Framework service integration
**Guidance Received**: Expert guidance on ETS/Redis/DETS multi-tier caching implementation, GenServer-based composition engine architecture, and Ash Framework service integration patterns. Key recommendations include using Registry for distributed cache coordination, leveraging Phoenix PubSub for cache invalidation, and implementing proper supervision trees for composition services.

### senior-engineer-reviewer
**Architectural Review**: Strategic architecture for enterprise-scale prompt composition with performance and security
**Decisions Confirmed**: Architecture should prioritize performance and security while maintaining flexibility for different composition strategies. Recommended modular design with clear separation of concerns, comprehensive caching for performance optimization, and security validation at every composition step. Key principles: performance first, security by design, and seamless integration with existing systems.

## Technical Details

### Files to Create
```
/lib/rubber_duck/prompts/
├── composition/
│   ├── composition_engine.ex              # Core composition orchestration
│   ├── prompt_resolver.ex                 # Hierarchical prompt resolution
│   ├── variable_interpolator.ex           # Secure variable substitution
│   └── token_optimizer.ex                 # Intelligent token compression
├── services/
│   ├── prompt_orchestrator_agent.ex       # Prompt composition coordination agent
│   ├── composition_cache.ex               # Multi-tier caching system
│   └── security_validator.ex              # Composition security validation
└── integrations/
    ├── llm_orchestrator_integration.ex    # LLM orchestration enhancement
    └── rag_integration.ex                 # RAG system integration

/test/rubber_duck/prompts/composition/
├── composition_engine_test.exs            # Composition engine tests
├── prompt_resolver_test.exs               # Resolution logic tests
├── variable_interpolator_test.exs         # Variable interpolation tests
└── token_optimizer_test.exs               # Token optimization tests

/test/rubber_duck/prompts/services/
├── prompt_orchestrator_agent_test.exs     # Agent coordination tests
└── composition_cache_test.exs             # Caching system tests

/test/rubber_duck/prompts/
└── prompt_composition_integration_test.exs # Integration tests (2B.2.3-2B.2.6)
```

### Files to Modify
```
lib/rubber_duck/llm_providers/universal_provider_service.ex  # Enhanced prompt injection
lib/rubber_duck/agents/llm_orchestrator_agent.ex           # Composition integration
lib/rubber_duck/application.ex                             # Add composition services to supervision tree
```

### Dependencies
- **Existing**: `ash` (resources), `jido` (agents), `cachex` (caching), `phoenix_pubsub` (invalidation)
- **Enhanced**: Multi-tier caching, prompt composition, variable interpolation
- **Integration**: LLM orchestration, RAG system, Reactor workflows

### Architecture Design
New prompt composition infrastructure:
- **CompositionEngine**: Orchestrates hierarchical composition with System → Project → User resolution
- **PromptResolver**: Efficient prompt lookup with intelligent caching and fallback strategies
- **VariableInterpolator**: Secure variable substitution with context awareness and validation
- **TokenOptimizer**: Model-specific token compression with semantic integrity preservation
- **Multi-Tier Caching**: Three-tier strategy for optimal performance and cache coherence

## Success Criteria

### Functional Requirements
- **Hierarchical Composition**: Deterministic System → Project → User composition with proper inheritance and override patterns
- **Variable Interpolation**: Secure variable substitution with context awareness, validation, and dynamic user context integration
- **Performance Optimization**: Sub-50ms prompt resolution with intelligent caching and token optimization
- **LLM Integration**: Seamless integration with existing orchestration for provider-specific formatting and dynamic selection
- **Security Validation**: Comprehensive prompt injection prevention with content sanitization and ML-based detection

### Performance Requirements
- **Resolution Speed**: <50ms for hierarchical prompt composition including variable interpolation
- **Cache Performance**: >95% cache hit rates with intelligent warming and eviction strategies
- **Token Efficiency**: Intelligent compression maintaining semantic integrity while optimizing for model limits
- **Concurrent Access**: Support for high-concurrency composition with minimal lock contention
- **Memory Management**: Efficient memory usage with proper cleanup and cache size management

### Quality Requirements
- **>95% Test Coverage**: Comprehensive testing for all composition modules, services, and integration patterns
- **Credo Compliance**: All code meets project quality standards with no design-level violations
- **Security Validation**: Comprehensive security testing with prompt injection prevention validation
- **Performance Benchmarks**: Measurable performance improvements with documented benchmarks
- **Integration Testing**: Full integration validation with LLM orchestration, RAG, and workflow systems

## Implementation Plan

### Phase 1: Core Composition Engine (Task 2B.2.1.1)
- [ ] **2B.2.1.1.1**: Implement three-tier prompt resolution with deterministic System → Project → User composition order
- [ ] **2B.2.1.1.2**: Add deterministic composition order with inheritance patterns and override capabilities
- [ ] **2B.2.1.1.3**: Include variable interpolation with comprehensive security validation and injection prevention
- [ ] **2B.2.1.1.4**: Support template-based composition strategies with pattern recognition and optimization

### Phase 2: Prompt Resolution Service (Task 2B.2.1.2)
- [ ] **2B.2.1.2.1**: Efficient hierarchical prompt lookup with optimized database queries and relationship traversal
- [ ] **2B.2.1.2.2**: Cache-aware resolution with sub-50ms targets using intelligent multi-tier caching strategies
- [ ] **2B.2.1.2.3**: Fallback strategies for missing prompts with graceful degradation and error handling
- [ ] **2B.2.1.2.4**: Batch resolution for workflow optimization with performance monitoring and analytics

### Phase 3: Variable Interpolation System (Task 2B.2.1.3)
- [ ] **2B.2.1.3.1**: Safe variable substitution with comprehensive validation and security checking
- [ ] **2B.2.1.3.2**: Context-aware variable resolution with user and project context integration
- [ ] **2B.2.1.3.3**: Support for dynamic variables from user context with real-time value resolution
- [ ] **2B.2.1.3.4**: Template inheritance and override patterns with composition validation

### Phase 4: Token Optimization System (Task 2B.2.1.4)
- [ ] **2B.2.1.4.1**: Intelligent prompt compression for model-specific token limits with semantic preservation
- [ ] **2B.2.1.4.2**: Priority-based content reduction strategies with importance scoring and selective compression
- [ ] **2B.2.1.4.3**: Semantic integrity preservation during compression with quality validation
- [ ] **2B.2.1.4.4**: Model-specific optimization for different LLM providers (GPT-4, Claude, etc.)

### Phase 5: LLM Orchestration Integration (Task 2B.2.2.1)
- [ ] **2B.2.2.1.1**: Inject composed prompts into LLM requests with provider-specific formatting
- [ ] **2B.2.2.1.2**: Provider-specific prompt formatting with model optimization and token management
- [ ] **2B.2.2.1.3**: Dynamic prompt selection based on request type, context, and user preferences
- [ ] **2B.2.2.1.4**: Fallback to system prompts when composition fails with error tracking and recovery

### Phase 6: Agent & Service Integration (Tasks 2B.2.2.2-2B.2.2.3)
- [ ] **2B.2.2.2**: Create PromptOrchestrator agent for coordination, caching management, validation, and analytics
- [ ] **2B.2.2.3**: Implement RAG integration with project-specific prompts, context injection, and performance optimization

### Phase 7: Comprehensive Testing (Tasks 2B.2.3-2B.2.6)
- [ ] **2B.2.3**: Test composition engine logic with hierarchical resolution and variable interpolation validation
- [ ] **2B.2.4**: Test variable interpolation with security validation and context awareness verification
- [ ] **2B.2.5**: Test LLM orchestration integration with provider formatting and dynamic selection validation
- [ ] **2B.2.6**: Test RAG enhancement integration with project context and performance optimization validation

## Risk Assessment

### Technical Risks
- **Performance Complexity**: Complex hierarchical composition might impact response times
  - *Mitigation*: Intelligent multi-tier caching, performance benchmarking, and optimization monitoring
- **Cache Coherence**: Multi-tier caching might cause consistency issues across distributed systems
  - *Mitigation*: Phoenix PubSub invalidation, cache coherence protocols, and consistency validation
- **Security Complexity**: Variable interpolation might introduce security vulnerabilities
  - *Mitigation*: Comprehensive validation, security testing, and prompt injection prevention

### Integration Risks
- **Coupling Risk**: Tight integration with LLM orchestration might create system dependencies
  - *Mitigation*: Loose coupling design, interface abstraction, and fallback mechanisms
- **Performance Impact**: Additional composition layer might impact existing LLM request performance
  - *Mitigation*: Performance optimization, caching strategies, and load testing validation

### Mitigation Strategies
1. **Comprehensive Testing**: >95% test coverage including security, performance, and integration testing
2. **Performance Monitoring**: Continuous performance tracking with automated alerts for degradation
3. **Security Validation**: Multiple layers of security testing and prompt injection prevention validation
4. **Gradual Integration**: Phased integration with feature flags and fallback mechanisms
5. **Cache Optimization**: Intelligent cache management with warming, eviction, and coherence strategies

## Architecture Considerations

### Composition Engine Design
- **Modular Architecture**: Clear separation of concerns with CompositionEngine, PromptResolver, VariableInterpolator, TokenOptimizer
- **Hierarchical Resolution**: System prompts provide base, Project prompts add customization, User prompts add personalization
- **Performance First**: Multi-tier caching with intelligent warming and sub-50ms resolution targets
- **Security Integration**: Security validation at every composition step with comprehensive injection prevention

### Caching Strategy
- **ETS Layer**: Process-local cache (1-minute TTL) for hot prompts and frequent access patterns
- **Redis Layer**: Distributed cache (1-hour TTL) for collaborative editing and cross-node sharing
- **DETS Layer**: Persistent cache (24-hour TTL) for long-term storage and restart recovery
- **Intelligent Management**: Cache warming, eviction, promotion, and coherence management

### Integration Architecture
- **LLM Orchestration**: Enhance existing LLMOrchestratorAgent with composed prompt injection and provider formatting
- **RAG System**: Project-specific prompt enhancement with context injection and user preference integration
- **Reactor Workflows**: Named prompt references with dynamic resolution during workflow execution
- **Security Systems**: Integration with authentication, authorization, and security validation infrastructure

This comprehensive plan provides the foundation for implementing sophisticated prompt composition capabilities while maintaining security, performance, and seamless integration with existing systems.