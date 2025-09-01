# Feature: Phase 02b Section 1.1 - Core Prompt Resources

## Problem Statement

### Current State
- **No Prompt Management System**: RubberDuck currently lacks a centralized prompt management system for LLM interactions
- **Hardcoded Prompts**: Prompts are scattered throughout the codebase without versioning or management capabilities
- **Limited Customization**: No hierarchical prompt system allowing system/project/user level customization
- **No Multi-Tenancy**: Missing multi-tenant prompt isolation and access control mechanisms
- **Performance Issues**: No caching system for prompt resolution and composition
- **Security Gaps**: No prompt injection prevention or content validation systems

### Business Impact
- **Developer Productivity**: Developers must manually manage prompts across different contexts and use cases
- **Inconsistent AI Behavior**: Lack of standardized prompts leads to inconsistent LLM responses across the system
- **Security Vulnerabilities**: No protection against prompt injection attacks or malicious content
- **Performance Degradation**: Repeated prompt parsing and processing without caching optimization
- **Maintenance Overhead**: Scattered prompts make updates and maintenance difficult and error-prone

### User Need
- **Hierarchical Prompt Management**: System administrators, project teams, and individual users need different levels of prompt customization
- **Version Control**: Comprehensive versioning with history tracking, comparison, and rollback capabilities
- **Analytics and Optimization**: Usage tracking and performance metrics to optimize prompt effectiveness
- **Security and Validation**: Protection against prompt injection with content sanitization and security monitoring
- **Multi-Tenant Isolation**: Secure isolation of prompts across different tenants and projects

## Solution Overview

### Approach
Implement Phase 02b Section 1.1 by creating a comprehensive Core Prompt Resources system using Ash Framework resources with PostgreSQL backend. This approach provides hierarchical prompt management (System/Project/User), complete versioning and analytics, multi-tenant security, and performance optimization through intelligent caching. The implementation integrates seamlessly with existing LLM orchestration and Reactor workflow systems.

### Key Design Decisions
1. **Ash Framework Integration**: Use Ash resources for declarative prompt management with built-in validation and authorization
2. **Three-Tier Hierarchy**: System prompts (immutable), Project prompts (team customization), User prompts (personal preferences)
3. **PostgreSQL with RLS**: Multi-tenant data isolation using Row-Level Security for enterprise-grade separation
4. **Comprehensive Versioning**: Append-only versioning with complete history and rollback capabilities
5. **Performance First**: Multi-tier caching strategy with ETS, distributed, and persistent layers
6. **Security Integration**: Built-in prompt injection prevention and content validation

### Integration Points
- **LLM Orchestration**: Integration with existing LLMOrchestratorAgent and provider selection systems
- **Reactor Workflows**: Support for named prompt references in Reactor workflow definitions
- **User Preferences**: Integration with Phase 1A user preference system for personalization
- **RAG System**: Enhanced context injection from project knowledge bases
- **Authentication**: Integration with existing Ash Authentication for access control

## Agent Consultations Performed

### research-agent
**Research Topic**: PostgreSQL Row-Level Security for multi-tenancy, modern prompt orchestration patterns, and Ash Framework resource design
**Findings**: Research revealed comprehensive RLS patterns for secure multi-tenant data isolation, modern prompt engineering techniques from Microsoft POML and OpenAI, and Ash Framework best practices for domain-driven resource design. Key insights include hierarchical prompt composition strategies, performance optimization through intelligent caching, and security validation patterns for prompt injection prevention.

### elixir-expert
**Consultation Topic**: Ash Framework resource design, PostgreSQL optimization, and Elixir performance patterns
**Guidance Received**: Expert guidance on Ash resource relationships and validations, PostgreSQL indexing strategies for hierarchical queries, ETS caching patterns for performance optimization, and Phoenix PubSub integration for real-time collaboration. Key recommendations include using Ash's built-in policy system for authorization, leveraging postgres_lsm for efficient hierarchical queries, and implementing intelligent cache warming strategies.

### senior-engineer-reviewer
**Architectural Review**: Strategic architecture for enterprise-scale prompt management with multi-tenancy and security
**Decisions Confirmed**: Architecture should prioritize security and performance while maintaining flexibility for different prompt types and use cases. Recommended three-tier hierarchy with clear separation of concerns, comprehensive versioning for audit trails, and performance optimization through intelligent caching. Key principles: security by design, performance optimization, and seamless integration with existing systems.

## Technical Details

### Files to Create
```
/lib/rubber_duck/prompts/
├── resources/
│   ├── prompt.ex                           # Main Prompt Ash resource with hierarchy
│   ├── prompt_version.ex                   # Version history tracking resource
│   ├── prompt_usage.ex                     # Usage analytics resource
│   ├── prompt_category.ex                  # Category organization resource
│   └── prompt_variable.ex                  # Dynamic variable management resource
└── domain.ex                               # Prompts domain definition

/priv/repo/migrations/
├── 20240831_001_create_prompt_tables.exs       # Core prompt tables
├── 20240831_002_create_prompt_indexes.exs      # Performance indexes
├── 20240831_003_create_prompt_policies.exs     # Row-level security
└── 20240831_004_seed_system_prompts.exs        # Default system prompts

/test/rubber_duck/prompts/resources/
├── prompt_test.exs                         # Prompt resource tests
├── prompt_version_test.exs                 # Version tracking tests
├── prompt_usage_test.exs                   # Usage analytics tests
└── prompt_category_test.exs                # Category organization tests

/test/rubber_duck/prompts/
└── core_prompt_resources_integration_test.exs  # Integration tests (2B.1.3-2B.1.6)
```

### Files to Modify
```
lib/rubber_duck/application.ex              # Add Prompts domain to supervision tree
mix.exs                                     # Ensure PostgreSQL and Ash dependencies
config/config.exs                           # Domain configuration
```

### Dependencies
- **Existing**: `ash` (resources), `ash_postgres` (data layer), `ash_authentication` (access control)
- **Enhanced**: PostgreSQL RLS, database indexing, ETS caching integration
- **Integration**: LLM orchestration, Reactor workflows, user preferences

### Database Design
New PostgreSQL tables with Row-Level Security:
- **prompts**: Main prompt storage with hierarchy levels and multi-tenancy
- **prompt_versions**: Complete version history with content snapshots and metadata
- **prompt_usages**: Usage analytics with performance metrics and pattern analysis
- **prompt_categories**: Hierarchical organization with nested categories and access control
- **prompt_variables**: Dynamic variable definitions for template interpolation

## Success Criteria

### Functional Requirements
- **Hierarchical Prompt System**: Complete three-tier hierarchy (System/Project/User) with deterministic composition
- **Comprehensive Versioning**: Version tracking with history, comparison, and rollback capabilities
- **Multi-Tenant Security**: Secure isolation using PostgreSQL RLS with proper access control
- **Usage Analytics**: Complete analytics with performance metrics, success rates, and pattern analysis
- **Category Organization**: Hierarchical category system with nested structures and usage tracking

### Performance Requirements
- **Prompt Resolution**: <50ms for hierarchical prompt lookup and composition
- **Database Performance**: Optimized queries with proper indexing for hierarchical data access
- **Cache Efficiency**: High cache hit rates with intelligent warming and eviction strategies
- **Concurrent Access**: Support for multiple concurrent users with minimal lock contention
- **Memory Management**: Efficient memory usage with proper cleanup and resource management

### Quality Requirements
- **>95% Test Coverage**: Comprehensive testing for all resources, operations, and integration patterns
- **Credo Compliance**: All code meets project quality standards with no design-level violations
- **Security Validation**: Comprehensive security testing with prompt injection prevention validation
- **Performance Benchmarks**: Measurable performance improvements with documented benchmarks
- **Integration Testing**: Full integration validation with existing LLM orchestration and workflow systems

## Implementation Plan

### Phase 1: Core Ash Resources (Tasks 2B.1.1.1-2B.1.1.4)
- [ ] **2B.1.1.1**: Create Prompt resource with three-tier hierarchy, versioning, multi-tenancy support, and approval workflows
- [ ] **2B.1.1.2**: Implement PromptVersion resource with complete history tracking, content snapshots, and rollback capabilities
- [ ] **2B.1.1.3**: Build PromptUsage resource with analytics tracking, performance metrics, and usage pattern analysis
- [ ] **2B.1.1.4**: Create PromptCategory resource with hierarchical organization, access control, and usage tracking

### Phase 2: Database Schema & Optimization (Tasks 2B.1.2.1-2B.1.2.3)
- [ ] **2B.1.2.1**: Design optimized PostgreSQL schema with multi-tenancy, hierarchical indexes, RLS policies, and constraints
- [ ] **2B.1.2.2**: Create supporting tables for versions, usages, categories, and variables with proper relationships
- [ ] **2B.1.2.3**: Implement database migrations with proper ordering, rollback procedures, and system prompt seeding

### Phase 3: Domain Integration & Testing (Tasks 2B.1.3-2B.1.6)
- [ ] **2B.1.3**: Test Ash resource operations with comprehensive CRUD validation and relationship testing
- [ ] **2B.1.4**: Test multi-tenancy isolation with Row-Level Security validation and cross-tenant access prevention
- [ ] **2B.1.5**: Test versioning mechanisms with history tracking, comparison, and rollback functionality
- [ ] **2B.1.6**: Test database constraints and policies with data integrity and security policy validation

### Phase 4: Performance & Integration Validation
- [ ] **Performance Testing**: Benchmark prompt resolution performance and validate <50ms targets
- [ ] **Integration Testing**: Validate integration with existing LLM orchestration and authentication systems
- [ ] **Security Testing**: Comprehensive security validation with prompt injection prevention testing
- [ ] **Load Testing**: Concurrent access testing with multi-tenant isolation validation

## Risk Assessment

### Technical Risks
- **Performance Impact**: Complex hierarchical queries might impact database performance
  - *Mitigation*: Comprehensive indexing strategy, intelligent caching, and query optimization
- **Security Complexity**: Multi-tenant RLS policies might introduce security vulnerabilities
  - *Mitigation*: Thorough security testing, policy validation, and comprehensive audit trails
- **Integration Complexity**: Integration with existing systems might cause conflicts or performance degradation
  - *Mitigation*: Gradual integration approach, backward compatibility, and comprehensive testing

### Integration Risks
- **Existing System Impact**: New prompt resources might conflict with existing LLM orchestration
  - *Mitigation*: Careful integration testing, feature flags for gradual rollout, fallback mechanisms
- **Database Performance**: Additional tables and RLS policies might impact existing database operations
  - *Mitigation*: Performance benchmarking, index optimization, and query performance monitoring

### Mitigation Strategies
1. **Comprehensive Testing**: >95% test coverage including security, performance, and integration testing
2. **Gradual Rollout**: Phased implementation with extensive validation at each step
3. **Performance Monitoring**: Continuous performance tracking with automated alerts for degradation
4. **Security Validation**: Multiple layers of security testing and prompt injection prevention validation
5. **Backward Compatibility**: Support for existing hardcoded prompts during migration period

## Architecture Considerations

### Ash Framework Integration
- **Domain-Driven Design**: Prompts domain with clear resource boundaries and relationships
- **Declarative Resources**: Leveraging Ash's declarative resource patterns for consistency
- **Built-in Authorization**: Using Ash's policy system for multi-tenant access control
- **Event Integration**: AshEvents for audit trails and real-time collaboration

### PostgreSQL Optimization Strategy
- **Row-Level Security**: Secure multi-tenant data isolation with performance optimization
- **Hierarchical Indexing**: Specialized indexes for efficient hierarchical prompt queries
- **Constraint Enforcement**: Foreign key constraints and check constraints for data integrity
- **Migration Strategy**: Proper migration ordering with rollback capabilities

### Performance Architecture
- **Three-Tier Caching**: ETS (process-local) → Distributed (Redis) → Persistent (DETS)
- **Intelligent Cache Management**: Cache warming, eviction, and promotion strategies
- **Query Optimization**: Efficient hierarchical queries with minimal database round trips
- **Memory Management**: Proper resource cleanup and memory pressure management

## Code Examples

### Prompt Resource (2B.1.1.1)
```elixir
defmodule RubberDuck.Prompts.Resources.Prompt do
  @moduledoc \"\"\"
  Core Prompt resource with three-tier hierarchical architecture.
  
  Supports System prompts (immutable base instructions), Project prompts
  (team customization), and User prompts (personal preferences) with
  comprehensive versioning, multi-tenancy, and security validation.
  \"\"\"

  use Ash.Resource,
    domain: RubberDuck.Prompts.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "prompts"
    repo RubberDuck.Repo

    # Multi-tenant row-level security
    base_filter_sql "tenant_id = current_setting('app.tenant_id')::uuid"
  end

  attributes do
    uuid_primary_key :id
    
    attribute :name, :string, allow_nil?: false
    attribute :content, :string, allow_nil?: false
    attribute :prompt_type, :atom, constraints: [one_of: [:system, :project, :user]]
    attribute :tenant_id, :uuid, allow_nil?: false
    attribute :project_id, :uuid
    attribute :user_id, :uuid
    attribute :status, :atom, constraints: [one_of: [:draft, :pending, :approved, :archived]]
    attribute :metadata, :map, default: %{}
    
    timestamps()
  end

  relationships do
    belongs_to :category, RubberDuck.Prompts.Resources.PromptCategory
    belongs_to :parent, __MODULE__
    has_many :versions, RubberDuck.Prompts.Resources.PromptVersion
    has_many :usages, RubberDuck.Prompts.Resources.PromptUsage
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    create :create_system_prompt do
      argument :content, :string, allow_nil?: false
      argument :name, :string, allow_nil?: false
      
      change set_attribute(:prompt_type, :system)
      change set_attribute(:status, :approved)
    end

    create :create_project_prompt do
      argument :content, :string, allow_nil?: false
      argument :name, :string, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      
      change set_attribute(:prompt_type, :project)
      change set_attribute(:status, :draft)
    end

    create :create_user_prompt do
      argument :content, :string, allow_nil?: false
      argument :name, :string, allow_nil?: false
      argument :user_id, :uuid, allow_nil?: false
      
      change set_attribute(:prompt_type, :user)
      change set_attribute(:status, :approved)
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(prompt_type == :system)
      authorize_if expr(prompt_type == :project and project_id == ^actor(:project_id))
      authorize_if expr(prompt_type == :user and user_id == ^actor(:id))
    end

    policy action_type(:update) do
      authorize_if expr(prompt_type == :system and ^actor(:role) == :admin)
      authorize_if expr(prompt_type == :project and ^actor(:project_role) in [:owner, :admin])
      authorize_if expr(prompt_type == :user and user_id == ^actor(:id))
    end
  end

  validations do
    validate present([:name, :content, :prompt_type, :tenant_id])
    validate match(:name, ~r/^[a-zA-Z0-9_.-]+$/, message: "Name must contain only alphanumeric characters, dots, dashes, and underscores")
    validate string_length(:content, min: 10, max: 50_000)
  end
end
```

### PromptVersion Resource (2B.1.1.2)
```elixir
defmodule RubberDuck.Prompts.Resources.PromptVersion do
  @moduledoc \"\"\"
  Version tracking resource for comprehensive prompt history management.
  
  Stores complete version history with content snapshots, metadata,
  and diff generation capabilities for audit trails and rollback support.
  \"\"\"

  use Ash.Resource,
    domain: RubberDuck.Prompts.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "prompt_versions"
    repo RubberDuck.Repo
  end

  attributes do
    uuid_primary_key :id
    
    attribute :version_number, :integer, allow_nil?: false
    attribute :content_snapshot, :string, allow_nil?: false
    attribute :change_summary, :string
    attribute :diff_data, :map, default: %{}
    attribute :created_by_id, :uuid, allow_nil?: false
    attribute :metadata, :map, default: %{}
    
    timestamps()
  end

  relationships do
    belongs_to :prompt, RubberDuck.Prompts.Resources.Prompt
  end

  actions do
    defaults [:create, :read]

    create :create_version do
      argument :prompt_id, :uuid, allow_nil?: false
      argument :content_snapshot, :string, allow_nil?: false
      argument :change_summary, :string
      
      change manage_relationship(:prompt_id, :prompt, type: :append_and_remove)
    end
  end
end
```

This comprehensive plan provides the foundation for implementing sophisticated hierarchical prompt management while maintaining security, performance, and integration with existing systems.