# Phase 2AI: JidoAI Integration & LLM Standardization

**[🧭 Phase Navigation](phase-navigation.md)** | **[📋 Complete Plan](implementation_plan_complete.md)**

---

## Phase 2AI Completion Status: 📋 Planned

### Summary
- 📋 **Section 2AI.1**: JidoAI Core Integration & Provider Configuration - **Planned**
- 📋 **Section 2AI.2**: Prompt System Migration to JidoAI.Prompt - **Planned**  
- 📋 **Section 2AI.3**: Agent LLM Interface Standardization - **Planned**
- 📋 **Section 2AI.4**: Keyring & Configuration Management - **Planned**
- 📋 **Section 2AI.5**: Multi-Provider Orchestration via JidoAI - **Planned**
- 📋 **Section 2AI.6**: Integration Testing & Legacy Migration - **Planned**

### Key Achievements (Planned)
- JidoAI unified LLM interface replacing fragmented provider systems
- Standardized prompt management using JidoAI.Prompt.MessageItem
- Hierarchical configuration via JidoAI.Keyring integration
- Provider abstraction using JidoAI's native multi-provider support
- Agent LLM interaction standardization across all 105+ agents
- Complete migration from UniversalProviderService to JidoAI patterns

---

## Phase Links
- **Previous**: [Phase 2: Autonomous LLM Orchestration System](phase-02-llm-orchestration.md)
- **Next**: [Phase 2A: Reactor Workflows](phase-02a-reactor-workflows.md)
- **Related**: [Phase 2B: Multi-Layered Prompt Management](phase-02b-multi-layered-prompts.md)

## All Phases
1. [Phase 1: Agentic Foundation & Core Infrastructure](phase-01-agentic-foundation.md)
2. [Phase 2: Autonomous LLM Orchestration System](phase-02-llm-orchestration.md)
3. **Phase 2AI: JidoAI Integration & LLM Standardization** *(Current)*
4. [Phase 2A: Reactor Workflows](phase-02a-reactor-workflows.md)
5. [Phase 2B: Multi-Layered Prompt Management](phase-02b-multi-layered-prompts.md)
6. [Phase 3: Intelligent Tool Agent System](phase-03-tool-agents.md)
7. [Phase 4: Multi-Agent Planning & Coordination](phase-04-planning-coordination.md)

---

## Overview

Transform RubberDuck's LLM integration by adopting JidoAI as the unified interface for all AI operations. This fundamental architectural shift replaces the current fragmented approach (UniversalProviderService, custom provider wrappers, ad-hoc prompt management) with JidoAI's structured, Elixir-native patterns for prompt management, provider abstraction, and AI workflow orchestration.

JidoAI provides the missing standardization layer that will enable true autonomous agent coordination through consistent LLM interfaces, structured prompt composition using `Jido.AI.Prompt.MessageItem`, hierarchical configuration via `Jido.AI.Keyring`, and native multi-provider support.

## 2AI.1 JidoAI Core Integration & Provider Configuration 📋 **PLANNED**

### 2AI.1.1 Dependency Management & Core Setup

#### Tasks:
- [ ] 2AI.1.1.1 Add JidoAI dependency 📋
  - [ ] 2AI.1.1.1.1 Add `{:jido_ai, "~> 0.5.2"}` to mix.exs dependencies
  - [ ] 2AI.1.1.1.2 Configure JidoAI in application supervision tree
  - [ ] 2AI.1.1.1.3 Set up JidoAI.Keyring for configuration management
  - [ ] 2AI.1.1.1.4 Initialize JidoAI agent integration patterns
- [ ] 2AI.1.1.2 Provider Configuration Migration 📋
  - [ ] 2AI.1.1.2.1 Migrate OpenAI configuration to JidoAI provider patterns
  - [ ] 2AI.1.1.2.2 Migrate Anthropic configuration to JidoAI provider patterns  
  - [ ] 2AI.1.1.2.3 Configure additional providers (Google, OpenRouter, Cloudflare)
  - [ ] 2AI.1.1.2.4 Set up provider fallback chains using JidoAI routing
- [ ] 2AI.1.1.3 Keyring Integration 📋
  - [ ] 2AI.1.1.3.1 Integrate with existing three-tier configuration system
  - [ ] 2AI.1.1.3.2 Migrate provider API keys to JidoAI.Keyring
  - [ ] 2AI.1.1.3.3 Set up session-based configuration overrides
  - [ ] 2AI.1.1.3.4 Configure hierarchical configuration resolution
- [ ] 2AI.1.1.4 Application Integration 📋
  - [ ] 2AI.1.1.4.1 Add JidoAI to RubberDuck.Application supervision tree
  - [ ] 2AI.1.1.4.2 Configure JidoAI telemetry integration
  - [ ] 2AI.1.1.4.3 Set up JidoAI error reporting with Tower
  - [ ] 2AI.1.1.4.4 Configure JidoAI with Phoenix PubSub integration

#### Skills:
- [ ] 2AI.1.2 JidoAI Provider Skills 📋
  - [ ] 2AI.1.2.1 ProviderConfigurationSkill with Keyring integration
  - [ ] 2AI.1.2.2 ProviderRoutingSkill with intelligent selection
  - [ ] 2AI.1.2.3 ProviderHealthSkill with monitoring
  - [ ] 2AI.1.2.4 ProviderFallbackSkill with error recovery

#### Actions:
- [ ] 2AI.1.3 Configuration actions 📋
  - [ ] 2AI.1.3.1 ConfigureJidoAI action for setup
  - [ ] 2AI.1.3.2 MigrateProviderConfig action for migration
  - [ ] 2AI.1.3.3 ValidateJidoAISetup action for verification
  - [ ] 2AI.1.3.4 TestProviderConnectivity action for health

#### Unit Tests:
- [ ] 2AI.1.4 Test JidoAI dependency integration 
- [ ] 2AI.1.5 Test provider configuration migration 
- [ ] 2AI.1.6 Test Keyring hierarchical resolution 
- [ ] 2AI.1.7 Test application supervision integration 

## 2AI.2 Prompt System Migration to JidoAI.Prompt 📋 **PLANNED**

### 2AI.2.1 Core Prompt Migration

#### Tasks:
- [ ] 2AI.2.1.1 Create JidoAIPromptAdapter 📋
  - [ ] 2AI.2.1.1.1 Adapt existing Prompt resources to JidoAI.Prompt.MessageItem
  - [ ] 2AI.2.1.1.2 Migrate hierarchical prompt composition to JidoAI templates
  - [ ] 2AI.2.1.1.3 Implement EEx template integration for dynamic prompts
  - [ ] 2AI.2.1.1.4 Create prompt versioning using JidoAI.Prompt history
- [ ] 2AI.2.1.2 Template System Integration 📋
  - [ ] 2AI.2.1.2.1 Migrate PromptComposer to use JidoAI.Prompt rendering
  - [ ] 2AI.2.1.2.2 Convert variable interpolation to JidoAI template params
  - [ ] 2AI.2.1.2.3 Integrate with JidoAI's EEx and Liquid template engines
  - [ ] 2AI.2.1.2.4 Preserve existing security validation patterns
- [ ] 2AI.2.1.3 Message Structure Migration 📋
  - [ ] 2AI.2.1.3.1 Convert three-tier prompts to JidoAI message lists
  - [ ] 2AI.2.1.3.2 Implement system/user/assistant role mapping
  - [ ] 2AI.2.1.3.3 Migrate metadata and context to JidoAI structures
  - [ ] 2AI.2.1.3.4 Preserve prompt inheritance and composition patterns
- [ ] 2AI.2.1.4 Performance Optimization 📋
  - [ ] 2AI.2.1.4.1 Integrate JidoAI prompt caching with existing cache layers
  - [ ] 2AI.2.1.4.2 Optimize template rendering performance
  - [ ] 2AI.2.1.4.3 Maintain sub-50ms prompt resolution targets
  - [ ] 2AI.2.1.4.4 Create performance monitoring for JidoAI operations

#### Skills:
- [ ] 2AI.2.2 Prompt Migration Skills 📋
  - [ ] 2AI.2.2.1 PromptAdapterSkill for format conversion
  - [ ] 2AI.2.2.2 TemplateRenderingSkill with JidoAI integration
  - [ ] 2AI.2.2.3 MessageCompositionSkill for role management
  - [ ] 2AI.2.2.4 PromptOptimizationSkill for performance

#### Actions:
- [ ] 2AI.2.3 Migration actions 📋
  - [ ] 2AI.2.3.1 ConvertToJidoAIPrompt action for migration
  - [ ] 2AI.2.3.2 RenderJidoAITemplate action for processing
  - [ ] 2AI.2.3.3 ValidateJidoAIPrompt action for verification
  - [ ] 2AI.2.3.4 OptimizeJidoAIPrompt action for performance

#### Unit Tests:
- [ ] 2AI.2.4 Test prompt format migration accuracy 
- [ ] 2AI.2.5 Test JidoAI template rendering compatibility 
- [ ] 2AI.2.6 Test message structure preservation 
- [ ] 2AI.2.7 Test performance optimization effectiveness 

## 2AI.3 Agent LLM Interface Standardization 📋 **PLANNED**

### 2AI.3.1 Universal Agent LLM Interface

#### Tasks:
- [ ] 2AI.3.1.1 Create AgentLLMInterface behavior 📋
  - [ ] 2AI.3.1.1.1 Define standard LLM interaction patterns for all agents
  - [ ] 2AI.3.1.1.2 Implement JidoAI.Agent integration for agent-to-LLM communication
  - [ ] 2AI.3.1.1.3 Create agent prompt composition using JidoAI.Prompt
  - [ ] 2AI.3.1.1.4 Standardize agent LLM response handling
- [ ] 2AI.3.1.2 LLM Agent Behavior Mixin 📋
  - [ ] 2AI.3.1.2.1 Create JidoAIAgentMixin with standard LLM methods
  - [ ] 2AI.3.1.2.2 Implement prompt composition helpers for agents
  - [ ] 2AI.3.1.2.3 Add provider selection logic for agent contexts
  - [ ] 2AI.3.1.2.4 Create agent-specific error handling patterns
- [ ] 2AI.3.1.3 Existing Agent Migration 📋
  - [ ] 2AI.3.1.3.1 Migrate LLMOrchestratorAgent to JidoAI patterns
  - [ ] 2AI.3.1.3.2 Update all 105+ agents to use standardized LLM interface
  - [ ] 2AI.3.1.3.3 Migrate RAG agents to JidoAI.Prompt for query construction
  - [ ] 2AI.3.1.3.4 Update prompt composition agents to use JidoAI templates
- [ ] 2AI.3.1.4 Agent Communication Enhancement 📋
  - [ ] 2AI.3.1.4.1 Implement agent-to-agent LLM communication via JidoAI
  - [ ] 2AI.3.1.4.2 Create shared prompt libraries for multi-agent workflows
  - [ ] 2AI.3.1.4.3 Implement agent context sharing through JidoAI sessions
  - [ ] 2AI.3.1.4.4 Create agent coordination patterns using JidoAI workflows

#### Skills:
- [ ] 2AI.3.2 Agent LLM Skills 📋
  - [ ] 2AI.3.2.1 AgentPromptSkill for standardized prompting
  - [ ] 2AI.3.2.2 AgentResponseSkill for response processing
  - [ ] 2AI.3.2.3 AgentContextSkill for context management
  - [ ] 2AI.3.2.4 AgentCoordinationSkill for multi-agent communication

#### Actions:
- [ ] 2AI.3.3 Agent interface actions 📋
  - [ ] 2AI.3.3.1 StandardizeLLMInterface action for migration
  - [ ] 2AI.3.3.2 UpdateAgentLLMCalls action for refactoring
  - [ ] 2AI.3.3.3 ValidateAgentLLMIntegration action for testing
  - [ ] 2AI.3.3.4 OptimizeAgentLLMPerformance action for enhancement

#### Unit Tests:
- [ ] 2AI.3.4 Test agent LLM interface standardization 
- [ ] 2AI.3.5 Test agent prompt composition via JidoAI 
- [ ] 2AI.3.6 Test agent-to-agent LLM communication 
- [ ] 2AI.3.7 Test agent context sharing through JidoAI 

## 2AI.4 Keyring & Configuration Management 📋 **PLANNED**

### 2AI.4.1 Hierarchical Configuration Integration

#### Tasks:
- [ ] 2AI.4.1.1 Integrate JidoAI.Keyring with existing systems 📋
  - [ ] 2AI.4.1.1.1 Connect Keyring with Phase 1A user preferences
  - [ ] 2AI.4.1.1.2 Integrate with existing three-tier configuration resolution
  - [ ] 2AI.4.1.1.3 Create configuration inheritance patterns
  - [ ] 2AI.4.1.1.4 Implement session-based provider overrides
- [ ] 2AI.4.1.2 Provider Configuration Migration 📋
  - [ ] 2AI.4.1.2.1 Migrate OpenAI API keys to Keyring management
  - [ ] 2AI.4.1.2.2 Migrate Anthropic configurations to Keyring
  - [ ] 2AI.4.1.2.3 Set up provider-specific configuration sections
  - [ ] 2AI.4.1.2.4 Create provider fallback configuration chains
- [ ] 2AI.4.1.3 Budget Integration 📋
  - [ ] 2AI.4.1.3.1 Connect JidoAI provider usage with budget tracking
  - [ ] 2AI.4.1.3.2 Implement cost-aware provider selection via Keyring
  - [ ] 2AI.4.1.3.3 Create budget override patterns using session values
  - [ ] 2AI.4.1.3.4 Integrate with existing budget alert system
- [ ] 2AI.4.1.4 Security & Validation 📋
  - [ ] 2AI.4.1.4.1 Implement secure key storage patterns
  - [ ] 2AI.4.1.4.2 Create configuration validation using JidoAI patterns
  - [ ] 2AI.4.1.4.3 Add configuration audit trail integration
  - [ ] 2AI.4.1.4.4 Implement configuration change notifications

#### Skills:
- [ ] 2AI.4.2 Configuration Skills 📋
  - [ ] 2AI.4.2.1 KeyringManagementSkill for configuration
  - [ ] 2AI.4.2.2 ConfigurationResolutionSkill for hierarchy
  - [ ] 2AI.4.2.3 ProviderConfigSkill for provider setup
  - [ ] 2AI.4.2.4 SecurityConfigSkill for secure handling

#### Actions:
- [ ] 2AI.4.3 Configuration actions 📋
  - [ ] 2AI.4.3.1 MigrateToKeyring action for key migration
  - [ ] 2AI.4.3.2 ResolveConfiguration action for resolution
  - [ ] 2AI.4.3.3 ValidateKeyringSetup action for validation
  - [ ] 2AI.4.3.4 SecureConfigurationAccess action for security

#### Unit Tests:
- [ ] 2AI.4.4 Test Keyring integration with existing preferences 
- [ ] 2AI.4.5 Test configuration hierarchy resolution 
- [ ] 2AI.4.6 Test provider configuration migration 
- [ ] 2AI.4.7 Test secure configuration handling 

## 2AI.5 Multi-Provider Orchestration via JidoAI 📋 **PLANNED**

### 2AI.5.1 Provider Abstraction Layer

#### Tasks:
- [ ] 2AI.5.1.1 Create JidoAIProviderManager 📋
  - [ ] 2AI.5.1.1.1 Implement unified provider interface using JidoAI patterns
  - [ ] 2AI.5.1.1.2 Create provider capability assessment via JidoAI
  - [ ] 2AI.5.1.1.3 Implement intelligent provider routing
  - [ ] 2AI.5.1.1.4 Create provider health monitoring integration
- [ ] 2AI.5.1.2 Replace UniversalProviderService 📋
  - [ ] 2AI.5.1.2.1 Migrate all UniversalProviderService.complete() calls to JidoAI
  - [ ] 2AI.5.1.2.2 Replace custom streaming with JidoAI streaming patterns
  - [ ] 2AI.5.1.2.3 Migrate cost estimation to JidoAI provider cost calculation
  - [ ] 2AI.5.1.2.4 Update provider health checking to use JidoAI monitoring
- [ ] 2AI.5.1.3 Provider Selection Enhancement 📋
  - [ ] 2AI.5.1.3.1 Implement domain-aware provider selection using JidoAI
  - [ ] 2AI.5.1.3.2 Create context-sensitive provider routing
  - [ ] 2AI.5.1.3.3 Implement cost-quality optimization via JidoAI
  - [ ] 2AI.5.1.3.4 Create provider learning patterns with JidoAI feedback
- [ ] 2AI.5.1.4 Integration with Existing Systems 📋
  - [ ] 2AI.5.1.4.1 Update LLMOrchestratorAgent to use JidoAI provider management
  - [ ] 2AI.5.1.4.2 Migrate RAG system to JidoAI for embedding generation
  - [ ] 2AI.5.1.4.3 Update Verdict system to use JidoAI providers
  - [ ] 2AI.5.1.4.4 Integrate with Phase 2B prompt composition via JidoAI

#### Skills:
- [ ] 2AI.5.2 Orchestration Skills 📋
  - [ ] 2AI.5.2.1 ProviderOrchestrationSkill for coordination
  - [ ] 2AI.5.2.2 ProviderSelectionSkill for intelligent routing
  - [ ] 2AI.5.2.3 ProviderOptimizationSkill for performance
  - [ ] 2AI.5.2.4 ProviderLearningSkill for improvement

#### Actions:
- [ ] 2AI.5.3 Orchestration actions 📋
  - [ ] 2AI.5.3.1 RouteToJidoAIProvider action for routing
  - [ ] 2AI.5.3.2 OptimizeProviderSelection action for intelligence
  - [ ] 2AI.5.3.3 MonitorProviderHealth action for monitoring
  - [ ] 2AI.5.3.4 LearnFromProviderOutcomes action for improvement

#### Unit Tests:
- [ ] 2AI.5.4 Test provider abstraction layer functionality 
- [ ] 2AI.5.5 Test UniversalProviderService replacement 
- [ ] 2AI.5.6 Test provider selection enhancement 
- [ ] 2AI.5.7 Test integration with existing systems 

## 2AI.6 Integration Testing & Legacy Migration 📋 **PLANNED**

### 2AI.6.1 Comprehensive Migration Strategy

#### Tasks:
- [ ] 2AI.6.1.1 Create Migration Framework 📋
  - [ ] 2AI.6.1.1.1 Build automated migration scripts for existing LLM calls
  - [ ] 2AI.6.1.1.2 Create compatibility testing framework
  - [ ] 2AI.6.1.1.3 Implement gradual rollout with feature flags
  - [ ] 2AI.6.1.1.4 Create rollback procedures for migration issues
- [ ] 2AI.6.1.2 Legacy System Replacement 📋
  - [ ] 2AI.6.1.2.1 Complete removal of UniversalProviderService
  - [ ] 2AI.6.1.2.2 Replace all legacy LLM provider calls with JidoAI
  - [ ] 2AI.6.1.2.3 Remove custom provider wrapper implementations
  - [ ] 2AI.6.1.2.4 Clean up legacy configuration and unused modules
- [ ] 2AI.6.1.3 Performance Validation 📋
  - [ ] 2AI.6.1.3.1 Compare JidoAI performance vs existing systems
  - [ ] 2AI.6.1.3.2 Validate prompt resolution performance improvements
  - [ ] 2AI.6.1.3.3 Test provider routing efficiency
  - [ ] 2AI.6.1.3.4 Benchmark end-to-end LLM operation performance
- [ ] 2AI.6.1.4 Integration Testing 📋
  - [ ] 2AI.6.1.4.1 End-to-end testing with all 105+ agents using JidoAI
  - [ ] 2AI.6.1.4.2 Multi-provider integration testing
  - [ ] 2AI.6.1.4.3 Prompt composition integration testing
  - [ ] 2AI.6.1.4.4 System-wide JidoAI integration validation

#### Skills:
- [ ] 2AI.6.2 Migration Skills 📋
  - [ ] 2AI.6.2.1 MigrationFrameworkSkill for automation
  - [ ] 2AI.6.2.2 CompatibilityTestingSkill for validation
  - [ ] 2AI.6.2.3 PerformanceValidationSkill for benchmarking
  - [ ] 2AI.6.2.4 IntegrationTestingSkill for system validation

#### Actions:
- [ ] 2AI.6.3 Migration actions 📋
  - [ ] 2AI.6.3.1 ExecuteMigration action for automated migration
  - [ ] 2AI.6.3.2 ValidateCompatibility action for testing
  - [ ] 2AI.6.3.3 BenchmarkPerformance action for validation
  - [ ] 2AI.6.3.4 CompleteIntegration action for finalization

#### Integration Tests:
- [ ] 2AI.6.4 Test complete JidoAI integration across all systems 📋
- [ ] 2AI.6.5 Test backward compatibility with existing functionality 📋
- [ ] 2AI.6.6 Test performance improvements vs legacy systems 📋
- [ ] 2AI.6.7 Test multi-provider coordination via JidoAI 📋
- [ ] 2AI.6.8 Test prompt composition integration via JidoAI 📋

## Required Phase Updates

### Phase 2: Autonomous LLM Orchestration System

#### Updates Required:
- [ ] Replace `UniversalProviderService` with `JidoAI` provider management
- [ ] Migrate `LLMOrchestratorAgent` to use `JidoAI.Agent` patterns  
- [ ] Update RAG system to use `JidoAI.Prompt` for query construction
- [ ] Replace custom provider configurations with `JidoAI.Keyring`
- [ ] Migrate streaming infrastructure to JidoAI streaming patterns
- [ ] Update circuit breaker integration to work with JidoAI providers

### Phase 2B: Multi-Layered Prompt Management

#### Updates Required:
- [ ] Replace `PromptComposerAgent` with `JidoAI.Prompt.MessageItem` composition
- [ ] Migrate hierarchical prompt system to JidoAI template inheritance
- [ ] Update security validation to work with JidoAI message structures
- [ ] Integrate caching system with JidoAI session management
- [ ] Update variable interpolation to use JidoAI template parameters
- [ ] Migrate real-time collaboration to JidoAI prompt versioning

### All Subsequent Phases (3-23)

#### Universal Updates Required:
- [ ] Replace all custom LLM calls with JidoAI standardized interface
- [ ] Migrate prompt construction to `JidoAI.Prompt.MessageItem`
- [ ] Update provider selection to use JidoAI routing
- [ ] Replace configuration management with `JidoAI.Keyring`
- [ ] Update streaming implementations to JidoAI patterns
- [ ] Migrate cost calculation to JidoAI provider cost estimation

---

## JidoAI Integration Benefits

### Unified LLM Interface
- **Single API**: Replace fragmented provider systems with unified JidoAI interface
- **Provider Abstraction**: JidoAI handles all provider differences and routing
- **Standardized Patterns**: Consistent LLM interaction patterns across all agents
- **Native Integration**: Seamless integration with Jido agent framework

### Enhanced Prompt Management
- **Structured Prompts**: `JidoAI.Prompt.MessageItem` for type-safe prompt composition
- **Template System**: EEx and Liquid template support for dynamic prompts
- **Message Roles**: Native system/user/assistant role management
- **Version Control**: Built-in prompt versioning and history tracking

### Improved Configuration
- **Hierarchical Config**: `JidoAI.Keyring` for sophisticated configuration management
- **Session Overrides**: Process-specific configuration overrides
- **Secure Key Management**: Built-in secure API key handling
- **Dynamic Configuration**: Runtime configuration updates without restarts

### Provider Excellence
- **Multi-Provider**: Native support for OpenAI, Anthropic, Google, OpenRouter, Cloudflare
- **Intelligent Routing**: Domain and context-aware provider selection
- **Health Monitoring**: Built-in provider health and performance monitoring
- **Fallback Chains**: Sophisticated provider fallback and error recovery

---

## Phase Dependencies

**Prerequisites:**
- Phase 1: Agentic Foundation (for agent infrastructure)
- Phase 2: LLM Orchestration System (to be refactored)
- Understanding of JidoAI patterns and provider management
- Existing three-tier configuration system (to be integrated)

**Provides Foundation For:**
- Phase 2A: Reactor Workflows (enhanced with JidoAI LLM integration)
- Phase 2B: Multi-Layered Prompts (migrated to JidoAI.Prompt patterns)
- Phase 3: Tool Agent System (using standardized LLM interface)
- Phase 4+: All agents using unified JidoAI interface

**Migration Impact:**
- **Breaking Changes**: All LLM interactions must use JidoAI - no backward compatibility
- **Configuration Replacement**: JidoAI.Keyring replaces all legacy configuration systems
- **Performance Improvements**: Unified JidoAI interface eliminates complexity
- **Enhanced Capabilities**: Full access to JidoAI's advanced features only

**Key Outputs:**
- Unified LLM interface using JidoAI across all 105+ agents
- Migrated prompt system using JidoAI.Prompt.MessageItem
- Hierarchical configuration via JidoAI.Keyring integration
- Provider standardization using JidoAI's multi-provider support
- Enhanced agent LLM communication patterns
- Complete migration from fragmented to unified LLM architecture

**Next Phase**: [Phase 2A: Reactor Workflows](phase-02a-reactor-workflows.md) builds upon this unified LLM foundation to create enhanced workflow orchestration with standardized AI integration.

**Critical Note**: This phase must be completed before Phase 2A implementation as it fundamentally changes how agents interact with LLMs. All subsequent phases depend on this unified JidoAI interface.