# Phase 2: Data Persistence & API Layer

**[🧭 Phase Navigation](phase-navigation.md)** | **[📋 Complete Plan](master-plan-overview.md)**

---

## Phase 2 Completion Status: 📋 0% Not Started

### Summary
- 📋 **Section 2.1**: Ash Domain Resources - **0% Not Started**
- 📋 **Section 2.2**: GraphQL & REST APIs - **0% Not Started**  
- 📋 **Section 2.3**: Phoenix Channels Integration - **0% Not Started**
- 📋 **Section 2.4**: Real-time Subscriptions - **0% Not Started**
- 📋 **Section 2.5**: Data Agent Layer - **0% Not Started**
- 📋 **Section 2.6**: Integration Tests - **0% Not Started**

### Key Objectives
- Integrate Ash framework for resource-driven data models
- Generate GraphQL and REST APIs automatically
- Implement real-time synchronization via Phoenix Channels
- Create data persistence agents with optimization
- Enable collaborative features through Presence

### Target Completion Date
**Target**: March 31, 2025

---

## Phase Links
- **Previous**: [Phase 1: Agentic Foundation & Core Infrastructure](phase-01-agentic-foundation.md)
- **Next**: [Phase 3: Intelligent Code Analysis System](phase-03-code-intelligence.md)
- **Related**: [Master Plan Overview](master-plan-overview.md)

## All Phases
1. [Phase 1: Agentic Foundation & Core Infrastructure](phase-01-agentic-foundation.md)
2. **Phase 2: Data Persistence & API Layer** 📋 *(Not Started)*
3. [Phase 3: Intelligent Code Analysis System](phase-03-code-intelligence.md)
4. [Phase 4: Security & Sandboxing System](phase-04-security-sandboxing.md)
5. [Phase 5: Real-time Collaboration Platform](phase-05-collaboration.md)
6. [Phase 6: Self-Learning & Intelligence](phase-06-self-learning.md)
7. [Phase 7: Production Optimization & Scale](phase-07-production-scale.md)

---

## Overview

This phase integrates Ash framework to provide a resource-driven data layer with automatic API generation. We establish domain models for coding sessions, projects, analyses, and suggestions, all exposed through GraphQL and REST endpoints. Real-time features are enabled through Phoenix Channels with Presence tracking for collaboration.

## 2.1 Ash Domain Resources 📋

#### Tasks:
- [ ] 2.1.1 Create CodingAssistant Domain
  - [ ] 2.1.1.1 Define domain boundaries and responsibilities
  - [ ] 2.1.1.2 Configure domain extensions (GraphQL, JSON:API)
  - [ ] 2.1.1.3 Set up authorization policies
  - [ ] 2.1.1.4 Implement domain-wide calculations
- [ ] 2.1.2 Implement Session Resource
  - [ ] 2.1.2.1 User session lifecycle management
  - [ ] 2.1.2.2 Session context tracking
  - [ ] 2.1.2.3 Activity history persistence
  - [ ] 2.1.2.4 Session analytics and metrics
- [ ] 2.1.3 Build Project Resource
  - [ ] 2.1.3.1 Project structure modeling
  - [ ] 2.1.3.2 File tree representation
  - [ ] 2.1.3.3 Configuration management
  - [ ] 2.1.3.4 Dependency tracking
- [ ] 2.1.4 Create Analysis Resource
  - [ ] 2.1.4.1 Analysis result storage
  - [ ] 2.1.4.2 Issue tracking and management
  - [ ] 2.1.4.3 Suggestion persistence
  - [ ] 2.1.4.4 Analysis history and trends

#### Skills:
- [ ] 2.1.5 Resource Management Skills
  - [ ] 2.1.5.1 ResourceValidationSkill with schema enforcement
  - [ ] 2.1.5.2 ResourceOptimizationSkill with query tuning
  - [ ] 2.1.5.3 ResourceCachingSkill with invalidation
  - [ ] 2.1.5.4 ResourceSyncSkill with conflict resolution

#### Actions:
- [ ] 2.1.6 Resource operation actions
  - [ ] 2.1.6.1 CreateResource action with validation
  - [ ] 2.1.6.2 UpdateResource action with optimistic locking
  - [ ] 2.1.6.3 QueryResource action with filtering
  - [ ] 2.1.6.4 AggregateResource action with calculations

#### Unit Tests:
- [ ] 2.1.7 Test resource CRUD operations
- [ ] 2.1.8 Test authorization policies
- [ ] 2.1.9 Test calculations and aggregates
- [ ] 2.1.10 Test resource relationships

## 2.2 GraphQL & REST APIs 📋

#### Tasks:
- [ ] 2.2.1 Configure GraphQL Schema Generation
  - [ ] 2.2.1.1 Query definitions for all resources
  - [ ] 2.2.1.2 Mutation operations with validation
  - [ ] 2.2.1.3 Subscription endpoints for real-time
  - [ ] 2.2.1.4 Custom resolvers for complex queries
- [ ] 2.2.2 Implement REST Endpoints
  - [ ] 2.2.2.1 JSON:API compliant endpoints
  - [ ] 2.2.2.2 Resource filtering and pagination
  - [ ] 2.2.2.3 Sparse fieldsets and includes
  - [ ] 2.2.2.4 Batch operations support
- [ ] 2.2.3 Build API Documentation
  - [ ] 2.2.3.1 GraphQL introspection setup
  - [ ] 2.2.3.2 OpenAPI specification generation
  - [ ] 2.2.3.3 Interactive API explorer
  - [ ] 2.2.3.4 Client SDK generation
- [ ] 2.2.4 Create API Gateway Layer
  - [ ] 2.2.4.1 Rate limiting and throttling
  - [ ] 2.2.4.2 API key management
  - [ ] 2.2.4.3 Request/response logging
  - [ ] 2.2.4.4 API versioning strategy

#### Skills:
- [ ] 2.2.5 API Management Skills
  - [ ] 2.2.5.1 QueryOptimizationSkill for N+1 prevention
  - [ ] 2.2.5.2 CachingSkill for response caching
  - [ ] 2.2.5.3 RateLimitingSkill for abuse prevention
  - [ ] 2.2.5.4 VersioningSkill for compatibility

#### Unit Tests:
- [ ] 2.2.6 Test GraphQL queries and mutations
- [ ] 2.2.7 Test REST endpoint responses
- [ ] 2.2.8 Test API authorization
- [ ] 2.2.9 Test rate limiting behavior

## 2.3 Phoenix Channels Integration 📋

#### Tasks:
- [ ] 2.3.1 Implement CodingChannel
  - [ ] 2.3.1.1 Channel authentication and authorization
  - [ ] 2.3.1.2 Message routing to agents
  - [ ] 2.3.1.3 Error handling and recovery
  - [ ] 2.3.1.4 Channel presence tracking
- [ ] 2.3.2 Create ProjectChannel
  - [ ] 2.3.2.1 Project-specific subscriptions
  - [ ] 2.3.2.2 File change notifications
  - [ ] 2.3.2.3 Collaborative editing events
  - [ ] 2.3.2.4 Build status updates
- [ ] 2.3.3 Build AnalysisChannel
  - [ ] 2.3.3.1 Real-time analysis results
  - [ ] 2.3.3.2 Progress tracking for long operations
  - [ ] 2.3.3.3 Issue notifications
  - [ ] 2.3.3.4 Suggestion streaming
- [ ] 2.3.4 Implement CollaborationChannel
  - [ ] 2.3.4.1 User cursor synchronization
  - [ ] 2.3.4.2 Selection sharing
  - [ ] 2.3.4.3 Live typing indicators
  - [ ] 2.3.4.4 Voice/video signaling

#### Skills:
- [ ] 2.3.5 Channel Management Skills
  - [ ] 2.3.5.1 PresenceTrackingSkill for user state
  - [ ] 2.3.5.2 MessageRoutingSkill for distribution
  - [ ] 2.3.5.3 ConflictResolutionSkill for edits
  - [ ] 2.3.5.4 BroadcastOptimizationSkill for efficiency

#### Unit Tests:
- [ ] 2.3.6 Test channel join/leave
- [ ] 2.3.7 Test message broadcasting
- [ ] 2.3.8 Test presence synchronization
- [ ] 2.3.9 Test channel recovery

## 2.4 Real-time Subscriptions 📋

#### Tasks:
- [ ] 2.4.1 Implement GraphQL Subscriptions
  - [ ] 2.4.1.1 WebSocket transport setup
  - [ ] 2.4.1.2 Subscription resolver implementation
  - [ ] 2.4.1.3 Event filtering and authorization
  - [ ] 2.4.1.4 Subscription lifecycle management
- [ ] 2.4.2 Create PubSub Topics
  - [ ] 2.4.2.1 Topic hierarchy design
  - [ ] 2.4.2.2 Event aggregation and batching
  - [ ] 2.4.2.3 Topic-based authorization
  - [ ] 2.4.2.4 Cross-node event distribution
- [ ] 2.4.3 Build Event Stream Processing
  - [ ] 2.4.3.1 Event sourcing implementation
  - [ ] 2.4.3.2 Event replay capabilities
  - [ ] 2.4.3.3 Event transformation pipeline
  - [ ] 2.4.3.4 Dead letter queue handling
- [ ] 2.4.4 Implement Notification System
  - [ ] 2.4.4.1 Multi-channel notifications (email, push, in-app)
  - [ ] 2.4.4.2 Notification preferences management
  - [ ] 2.4.4.3 Notification batching and digest
  - [ ] 2.4.4.4 Delivery tracking and retry

#### Skills:
- [ ] 2.4.5 Subscription Management Skills
  - [ ] 2.4.5.1 EventFilteringSkill for relevance
  - [ ] 2.4.5.2 EventAggregationSkill for batching
  - [ ] 2.4.5.3 DeliveryGuaranteeSkill for reliability
  - [ ] 2.4.5.4 BackpressureSkill for flow control

#### Unit Tests:
- [ ] 2.4.6 Test subscription establishment
- [ ] 2.4.7 Test event delivery
- [ ] 2.4.8 Test filtering accuracy
- [ ] 2.4.9 Test notification delivery

## 2.5 Data Agent Layer 📋

#### Tasks:
- [ ] 2.5.1 Create DataPersistenceAgent
  - [ ] 2.5.1.1 Automatic query optimization
  - [ ] 2.5.1.2 Connection pool management
  - [ ] 2.5.1.3 Cache warming and invalidation
  - [ ] 2.5.1.4 Data archival strategies
- [ ] 2.5.2 Implement QueryOptimizerAgent
  - [ ] 2.5.2.1 Query plan analysis
  - [ ] 2.5.2.2 Index recommendation
  - [ ] 2.5.2.3 Query rewriting for performance
  - [ ] 2.5.2.4 Statistics collection and analysis
- [ ] 2.5.3 Build DataSyncAgent
  - [ ] 2.5.3.1 Cross-database synchronization
  - [ ] 2.5.3.2 Conflict detection and resolution
  - [ ] 2.5.3.3 Eventual consistency management
  - [ ] 2.5.3.4 Data versioning and history
- [ ] 2.5.4 Create BackupAgent
  - [ ] 2.5.4.1 Automated backup scheduling
  - [ ] 2.5.4.2 Point-in-time recovery
  - [ ] 2.5.4.3 Backup verification
  - [ ] 2.5.4.4 Disaster recovery procedures

#### Skills:
- [ ] 2.5.5 Data Management Skills
  - [ ] 2.5.5.1 QueryAnalysisSkill for optimization
  - [ ] 2.5.5.2 DataReplicationSkill for redundancy
  - [ ] 2.5.5.3 ConsistencySkill for integrity
  - [ ] 2.5.5.4 RecoverySkill for resilience

#### Unit Tests:
- [ ] 2.5.6 Test query optimization
- [ ] 2.5.7 Test data synchronization
- [ ] 2.5.8 Test backup and recovery
- [ ] 2.5.9 Test data consistency

## 2.6 Phase 2 Integration Tests 📋

#### Integration Tests:
- [ ] 2.6.1 Test complete API workflow
- [ ] 2.6.2 Test real-time data synchronization
- [ ] 2.6.3 Test channel-based collaboration
- [ ] 2.6.4 Test data persistence and retrieval
- [ ] 2.6.5 Test subscription delivery
- [ ] 2.6.6 Test cross-agent data flow

---

## Phase Dependencies

**Prerequisites:**
- Completed Phase 1 (Agentic Foundation)
- Ash Framework 3.0+ installed
- PostgreSQL 14+ configured
- Phoenix 1.7+ with Channels

**Provides Foundation For:**
- Phase 3: Data models for analysis results
- Phase 4: Secure data access patterns
- Phase 5: Collaboration data structures
- Phase 6: Training data persistence
- Phase 7: Scalable data architecture

**Key Outputs:**
- Complete Ash domain model
- Functional GraphQL/REST APIs
- Real-time Phoenix Channels
- Data persistence agents
- Subscription system
- API documentation

**Next Phase**: [Phase 3: Intelligent Code Analysis System](phase-03-code-intelligence.md) builds advanced analysis capabilities on this data foundation.
