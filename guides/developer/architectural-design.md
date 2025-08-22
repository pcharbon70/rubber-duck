# RubberDuck Architectural Design Guide

## Overview

RubberDuck is an agent-based Elixir application built on the Ash Framework that provides autonomous code analysis and development assistance. The system uses a multi-agent architecture where specialized agents handle different aspects of the development workflow, from authentication to code analysis to LLM orchestration.

## Core Architecture Principles

### Agent-Centric Design
- Each major system component is implemented as an autonomous agent
- Agents make decisions based on goals rather than explicit instructions
- Coordination happens through signal-based communication and shared state
- Agents can operate independently or collaborate for complex tasks

### Skills-Based Modularity
- Functionality is packaged as reusable Skills that agents can use
- Skills provide specific capabilities (authentication, code analysis, etc.)
- Skills can be composed and configured at runtime
- Hot-swapping capabilities allow runtime updates without restarts

### Instruction and Directive System
- Instructions define executable workflows and action sequences
- Directives provide runtime configuration and behavior modification
- Both systems enable dynamic adaptation without code changes

## High-Level System Architecture

```mermaid
graph TB
    subgraph "Application Layer"
        WebUI[Web Interface]
        API[API Endpoints]
        CLI[Command Line Interface]
    end
    
    subgraph "Agent Layer"
        UA[User Agent]
        PA[Project Agent]
        CFA[Code File Agent]
        AAA[AI Analysis Agent]
        LLMO[LLM Orchestrator Agent]
        Auth[Authentication Agent]
    end
    
    subgraph "Skills Layer"
        UMS[User Management Skill]
        PMS[Project Management Skill]
        CAS[Code Analysis Skill]
        AUS[Authentication Skill]
        TDS[Threat Detection Skill]
    end
    
    subgraph "Infrastructure Layer"
        SR[Skills Registry]
        IE[Instructions Engine]
        DE[Directives Engine]
        DB[(Database)]
        VS[(Vector Store)]
    end
    
    WebUI --> UA
    API --> PA
    CLI --> CFA
    
    UA --> UMS
    PA --> PMS
    CFA --> CAS
    AAA --> CAS
    LLMO --> AUS
    Auth --> AUS
    Auth --> TDS
    
    UMS --> SR
    PMS --> SR
    CAS --> SR
    AUS --> SR
    TDS --> SR
    
    SR --> IE
    SR --> DE
    IE --> DB
    DE --> VS
```

## Core Agents

### Domain Agents

#### UserAgent (`lib/rubber_duck/agents/user_agent.ex`)
- Manages user sessions and preferences
- Handles user behavior pattern recognition
- Provides proactive assistance suggestions
- Integrates with authentication system

#### ProjectAgent (`lib/rubber_duck/agents/project_agent.ex`)
- Manages project lifecycle and structure
- Provides dependency detection and management
- Monitors code quality continuously
- Generates refactoring suggestions

#### CodeFileAgent (`lib/rubber_duck/agents/code_file_agent.ex`)
- Analyzes code changes and quality
- Updates documentation automatically
- Tracks dependency impacts
- Provides performance optimization recommendations

#### AIAnalysisAgent (`lib/rubber_duck/agents/ai_analysis_agent.ex`)
- Schedules analysis tasks based on project activity
- Assesses result quality and learns from feedback
- Generates insights and discovers patterns
- Coordinates with LLM providers

### Infrastructure Agents

#### AuthenticationAgent (`lib/rubber_duck/agents/authentication_agent.ex`)
- Manages session lifecycle autonomously
- Detects threats and responds adaptively
- Implements dynamic security policies
- Provides behavioral authentication

#### TokenAgent (`lib/rubber_duck/agents/token_agent.ex`)
- Manages token lifecycle with predictive renewal
- Analyzes usage patterns for anomaly detection
- Implements automatic renewal strategies
- Detects security anomalies

#### PermissionAgent (`lib/rubber_duck/agents/permission_agent.ex`)
- Adjusts permissions dynamically based on context
- Provides context-aware access control
- Implements risk-based authentication
- Monitors privilege escalation

### Data Management Agents

#### DataPersistenceAgent (`lib/rubber_duck/agents/data_persistence_agent.ex`)
- Optimizes queries autonomously
- Manages connection pools adaptively
- Implements predictive data caching
- Suggests index optimizations

#### MigrationAgent (`lib/rubber_duck/agents/migration_agent.ex`)
- Executes migrations with intelligent rollback
- Validates data integrity automatically
- Predicts and mitigates performance impacts
- Makes rollback decisions based on failure patterns

#### QueryOptimizerAgent (`lib/rubber_duck/agents/query_optimizer_agent.ex`)
- Learns query patterns and optimizes them
- Rewrites queries automatically for performance
- Optimizes cache strategies based on usage
- Makes load balancing decisions with predictive scaling

## Skills System

### Core Skills Architecture

```mermaid
graph LR
    subgraph "Skills Registry"
        SR[Skills Registry]
        SC[Skill Configuration]
        SD[Skill Discovery]
    end
    
    subgraph "Authentication Skills"
        AS[Authentication Skill]
        TMS[Token Management Skill]
        PES[Policy Enforcement Skill]
        TDS[Threat Detection Skill]
    end
    
    subgraph "Analysis Skills"
        CAS[Code Analysis Skill]
        PMS[Project Management Skill]
        UMS[User Management Skill]
        QOS[Query Optimization Skill]
        LS[Learning Skill]
    end
    
    SR --> AS
    SR --> TMS
    SR --> PES
    SR --> TDS
    SR --> CAS
    SR --> PMS
    SR --> UMS
    SR --> QOS
    SR --> LS
    
    SC --> SR
    SD --> SR
```

### Skills Implementation

Skills are located in `lib/rubber_duck/skills/` and provide:
- Reusable functionality across agents
- Configuration and composition capabilities
- Runtime modification support
- Hot-swapping for updates without restarts

## LLM Orchestration System

### Architecture

```mermaid
graph TD
    subgraph "LLM Orchestration Layer"
        LLMO[LLM Orchestrator Agent]
        PS[Provider Selector]
        RO[Request Optimizer]
        RC[Response Cacher]
    end
    
    subgraph "Provider Integration"
        OpenAI[OpenAI Provider]
        Anthropic[Anthropic Provider]
        Local[Local Models]
    end
    
    subgraph "RAG System"
        EGA[Embedding Generation Agent]
        RCA[Retrieval Coordinator Agent]
        CBA[Context Builder Agent]
        PBA[Prompt Builder Agent]
    end
    
    subgraph "Supporting Systems"
        CB[Circuit Breaker]
        Cache[(Response Cache)]
        VS[(Vector Store)]
    end
    
    LLMO --> PS
    LLMO --> RO
    LLMO --> RC
    
    PS --> OpenAI
    PS --> Anthropic
    PS --> Local
    
    LLMO --> EGA
    LLMO --> RCA
    LLMO --> CBA
    LLMO --> PBA
    
    EGA --> VS
    RCA --> VS
    CBA --> Cache
    PBA --> Cache
    
    PS --> CB
    RO --> CB
```

### Key Components

#### Provider Management
- Autonomous provider selection based on request characteristics
- Cost-quality optimization with learning from outcomes
- Intelligent routing with load balancing
- Circuit breaker patterns for failure handling

#### RAG Pipeline
- Multi-strategy retrieval (semantic, fulltext, hybrid)
- Reciprocal Rank Fusion for result combination
- Context optimization for token efficiency
- Quality assessment with RAG Triad metrics

## Data Layer Architecture

### Database Design

```mermaid
erDiagram
    users {
        string id PK
        string email
        string hashed_password
        string confirmed_at
        timestamptz inserted_at
        timestamptz updated_at
    }
    
    tokens {
        string jti PK
        string aud
        string sub
        string exp
        string purpose
        timestamptz inserted_at
        timestamptz updated_at
    }
    
    api_keys {
        string id PK
        string name
        string key_hash
        string user_id FK
        timestamptz inserted_at
        timestamptz updated_at
    }
    
    chunks {
        string id PK
        string document
        string source
        text chunk
        vector embedding
        jsonb metadata
        timestamptz inserted_at
        timestamptz updated_at
    }
    
    users ||--o{ tokens : has
    users ||--o{ api_keys : owns
```

### Storage Systems
- **PostgreSQL**: Primary data storage with Ash resources
- **PGVector**: Vector embeddings for semantic search
- **ETS**: In-memory caching and session storage
- **Oban**: Background job processing

## Communication Patterns

### Signal-Based Communication

```mermaid
sequenceDiagram
    participant UA as User Agent
    participant PA as Project Agent
    participant CFA as Code File Agent
    participant DB as Database
    
    UA->>PA: project.create signal
    PA->>CFA: code.analyze signal
    CFA->>DB: store analysis
    CFA->>PA: analysis.complete signal
    PA->>UA: project.ready signal
```

### Message Flow
- Agents communicate through structured signals
- Pub/Sub pattern for loose coupling
- Event sourcing for audit trails
- Circuit breakers for reliability

## Security Architecture

### Multi-Layer Security

```mermaid
graph TB
    subgraph "Authentication Layer"
        Login[Login/Registration]
        Token[Token Management]
        Session[Session Control]
    end
    
    subgraph "Authorization Layer"
        Permissions[Permission Agent]
        Policies[Dynamic Policies]
        Context[Context-Aware Access]
    end
    
    subgraph "Monitoring Layer"
        SMS[Security Monitor Sensor]
        Threat[Threat Detection]
        Anomaly[Anomaly Detection]
    end
    
    subgraph "Response Layer"
        Auto[Automatic Response]
        Recovery[Security Recovery]
        Learning[Learning from Attacks]
    end
    
    Login --> Token
    Token --> Session
    Session --> Permissions
    Permissions --> Policies
    Policies --> Context
    Context --> SMS
    SMS --> Threat
    Threat --> Anomaly
    Anomaly --> Auto
    Auto --> Recovery
    Recovery --> Learning
```

### Security Features
- Behavioral authentication with pattern analysis
- Adaptive security policies based on risk assessment
- Real-time threat detection and response
- Security event correlation and learning

## Workflow Orchestration

### Reactor Integration

```mermaid
graph LR
    subgraph "Workflow Engine"
        WB[Workflow Builder]
        WE[Workflow Executor]
        WM[Workflow Monitor]
    end
    
    subgraph "Reactor Features"
        Steps[Reactor Steps]
        Comp[Compensation]
        Deps[Dependencies]
        Middle[Middleware]
    end
    
    subgraph "Agent Integration"
        AW[Agent Workflows]
        Optional[Optional Usage]
        Auto[Autonomous Operation]
    end
    
    WB --> Steps
    WE --> Comp
    WM --> Deps
    Middle --> AW
    AW --> Optional
    Optional --> Auto
```

### Workflow Features
- Optional workflow orchestration for complex operations
- Compensation patterns for error recovery
- Dependency analysis for optimal execution order
- Agent autonomy preserved with workflow enhancement

## Performance and Scalability

### Concurrency Model

```mermaid
graph TB
    subgraph "Supervision Tree"
        App[Application]
        Repo[Repository]
        Agents[Agent Supervisor]
        Web[Web Supervisor]
    end
    
    subgraph "Agent Processes"
        UA[User Agent Pool]
        PA[Project Agent Pool]
        CFA[Code File Agent Pool]
        LLMO[LLM Orchestrator Pool]
    end
    
    subgraph "Background Processes"
        Oban[Oban Jobs]
        Telemetry[Telemetry Collector]
        Health[Health Monitor]
    end
    
    App --> Repo
    App --> Agents
    App --> Web
    
    Agents --> UA
    Agents --> PA
    Agents --> CFA
    Agents --> LLMO
    
    App --> Oban
    App --> Telemetry
    App --> Health
```

### Performance Features
- Dynamic process pools for agents
- ETS-based caching for fast data access
- Background job processing with Oban
- Circuit breakers for resilience
- Telemetry and monitoring for optimization

## Development Workflow

### Agent Development Lifecycle

```mermaid
graph LR
    Design[Agent Design] --> Implement[Implementation]
    Implement --> Skills[Skills Integration]
    Skills --> Test[Testing]
    Test --> Deploy[Deployment]
    Deploy --> Monitor[Monitoring]
    Monitor --> Learn[Learning]
    Learn --> Optimize[Optimization]
    Optimize --> Design
```

### Testing Strategy
- Unit tests for individual agent behaviors
- Integration tests for agent coordination
- Performance tests for scalability validation
- Chaos engineering for resilience testing

## Configuration Management

### Hierarchical Configuration

```mermaid
graph TB
    subgraph "Configuration Layers"
        Global[Global Config]
        Env[Environment Config]
        Agent[Agent Config]
        Runtime[Runtime Directives]
    end
    
    subgraph "Configuration Sources"
        Files[Config Files]
        Env_Vars[Environment Variables]
        Database[Database Settings]
        Dynamic[Dynamic Updates]
    end
    
    Global --> Env
    Env --> Agent
    Agent --> Runtime
    
    Files --> Global
    Env_Vars --> Env
    Database --> Agent
    Dynamic --> Runtime
```

### Configuration Features
- Layered configuration with override capabilities
- Runtime configuration updates through Directives
- Environment-specific settings
- Agent-specific configuration options

## Monitoring and Observability

### Telemetry Architecture

```mermaid
graph LR
    subgraph "Data Collection"
        Agents[Agent Metrics]
        System[System Metrics]
        Business[Business Metrics]
    end
    
    subgraph "Processing"
        Collector[Telemetry Collector]
        Aggregator[Data Aggregator]
        Analyzer[Pattern Analyzer]
    end
    
    subgraph "Storage & Visualization"
        TSDB[(Time Series DB)]
        Dashboard[Monitoring Dashboard]
        Alerts[Alert System]
    end
    
    Agents --> Collector
    System --> Collector
    Business --> Collector
    
    Collector --> Aggregator
    Aggregator --> Analyzer
    
    Analyzer --> TSDB
    TSDB --> Dashboard
    TSDB --> Alerts
```

### Monitoring Features
- Real-time agent performance tracking
- System health monitoring
- Business metric collection
- Automated alerting and response

## Future Architecture Evolution

### Planned Enhancements

1. **Memory and Context Management**: Three-tier memory system with intelligent context optimization
2. **Communication Agents**: Enhanced inter-agent communication and coordination
3. **Security Enhancement**: Advanced threat detection and autonomous security responses
4. **Production Management**: Autonomous deployment and scaling capabilities
5. **Advanced Analysis**: Machine learning pipeline for pattern detection and code optimization

### Extensibility Points

- **New Agent Types**: Framework supports adding specialized agents
- **Additional Skills**: Modular skills can be developed independently
- **Provider Integration**: New LLM providers can be integrated easily
- **Workflow Enhancement**: Reactor-based workflows for complex orchestration
- **Custom Instructions**: Domain-specific instruction sets can be added

## Development Guidelines

### Adding New Agents
1. Define agent purpose and capabilities
2. Implement using `Jido.Agent` behavior
3. Create associated Skills for reusable functionality
4. Add appropriate tests and documentation
5. Register with supervision tree

### Creating Skills
1. Use `Jido.Skill` behavior for implementation
2. Define clear input/output signals
3. Implement configuration options
4. Ensure composability with other Skills
5. Add comprehensive tests

### Implementing Instructions
1. Define clear action parameters and outcomes
2. Implement error handling and compensation
3. Add telemetry and monitoring
4. Ensure idempotency where appropriate
5. Document usage patterns

### Using Directives
1. Define clear configuration schemas
2. Implement validation and safety checks
3. Ensure graceful fallback behavior
4. Add audit logging for changes
5. Test runtime modification scenarios

## Best Practices

### Code Organization
- Follow Ash Framework conventions
- Use Jido patterns for agent implementation
- Maintain clear separation between agents and skills
- Implement comprehensive error handling

### Testing Approach
- Test agent behaviors in isolation
- Validate agent coordination scenarios
- Use property-based testing for complex logic
- Implement chaos engineering for resilience

### Performance Optimization
- Use ETS for fast in-memory operations
- Implement circuit breakers for external dependencies
- Monitor and optimize agent communication patterns
- Use background jobs for non-critical operations

### Security Considerations
- Implement defense in depth
- Use behavioral authentication where appropriate
- Monitor and log security events
- Implement automatic threat response where safe

## Troubleshooting Guide

### Common Issues
- **Agent Startup Failures**: Check supervision tree configuration
- **Skill Loading Issues**: Verify Skills Registry initialization
- **Communication Problems**: Validate signal routing configuration
- **Performance Issues**: Review telemetry data and agent pool sizing

### Debugging Tools
- Agent state inspection via telemetry
- Signal flow tracing through PubSub logs
- Performance metrics dashboard
- Health check endpoints for system status

## Conclusion

The RubberDuck architecture provides a robust, scalable foundation for autonomous development assistance. The agent-based design enables independent component evolution while maintaining system cohesion through Skills, Instructions, and Directives. This architecture supports both current functionality and future enhancements while maintaining operational excellence and developer productivity.