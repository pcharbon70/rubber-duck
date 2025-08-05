# Jido Integration Opportunities for RubberDuck

## Executive Summary

This report analyzes opportunities to integrate Jido framework concepts (Skills, Instructions, and Directives) into the RubberDuck agentic coding assistant architecture. By leveraging these Jido patterns, RubberDuck can achieve better modularity, runtime flexibility, and plugin-based extensibility while simplifying its implementation.

## Current Architecture Analysis

### Existing Implementation

RubberDuck currently uses Jido at a basic level:
- **Agents**: Built using `Jido.Agent` with custom `RubberDuck.Agents.Base` wrapper
- **Actions**: Structured as Jido Actions for discrete functionality
- **Signals**: Used for agent communication
- **Sensors**: Limited use for monitoring (e.g., LLMHealthSensor)

### Identified Gaps

1. **No Skills System**: Agents and actions are tightly coupled, limiting reusability
2. **Limited Instructions**: Current implementation doesn't fully leverage Jido's Instruction patterns
3. **No Directives**: Runtime behavior modification is handled through custom state management
4. **Workflow Rigidity**: Runic integration planned but not leveraging Jido's dynamic capabilities

## Integration Opportunities

### 1. Skills Integration

#### Current State
- Agents have hardcoded actions and sensors
- No plugin architecture for extending agent capabilities
- Difficult to share functionality between agents

#### Proposed Enhancement with Skills

Transform agent capabilities into reusable Skills that can be mixed and matched:

```elixir
defmodule RubberDuck.Skills.CodeAnalysis do
  use Jido.Skill,
    name: "code_analysis",
    description: "Provides code analysis capabilities",
    opts_key: :analysis,
    signals: [
      input: ["code.analyze.*", "file.changed"],
      output: ["analysis.complete", "insight.generated"]
    ],
    config: [
      quality_threshold: [type: :float, default: 0.8],
      languages: [type: {:list, :atom}, default: [:elixir, :javascript]]
    ]

  def router do
    [
      %{path: "code.analyze.structure", instruction: %{action: Actions.AnalyzeStructure}},
      %{path: "code.analyze.quality", instruction: %{action: Actions.MonitorQuality}},
      %{path: "code.analyze.dependencies", instruction: %{action: Actions.DetectDependencies}}
    ]
  end
end
```

#### Benefits
- **Modularity**: Package related functionality together
- **Reusability**: Share skills across different agents
- **Extensibility**: Third-party skills can be added as plugins
- **Configuration**: Skills can be configured per-agent instance

### 2. Instructions Enhancement

#### Current State
- Actions are called directly or through simple workflows
- Limited ability to compose complex behaviors
- No standardized instruction format

#### Proposed Enhancement with Instructions

Leverage Jido's Instruction patterns for better workflow composition:

```elixir
# Phase 3: Tool Agent System Enhancement
defmodule RubberDuck.Agents.ToolExecutor do
  def execute_tool_workflow(tool_request) do
    instructions = [
      %Instruction{
        action: ValidateToolRequest,
        params: %{request: tool_request},
        context: %{phase: :validation}
      },
      %Instruction{
        action: SelectOptimalTool,
        params: %{criteria: tool_request.requirements},
        opts: [timeout: 5_000]
      },
      %Instruction{
        action: ExecuteTool,
        params: %{tool: :dynamic}, # Filled by previous instruction
        opts: [retry: true, max_retries: 3]
      }
    ]
    
    {:ok, normalized} = Instruction.normalize(instructions, shared_context())
    Jido.Workflow.run_chain(normalized)
  end
end
```

#### Benefits
- **Composability**: Build complex workflows from simple instructions
- **Runtime Flexibility**: Modify instruction parameters dynamically
- **Error Handling**: Built-in retry and compensation mechanisms
- **Traceability**: Each instruction has unique ID for debugging

### 3. Directives Integration

#### Current State
- Agent behavior changes require state updates
- No runtime modification of agent capabilities
- Limited ability to adapt agent behavior dynamically

#### Proposed Enhancement with Directives

Use Directives for runtime agent modification:

```elixir
# Phase 4: Multi-Agent Coordination Enhancement
defmodule RubberDuck.Agents.Coordinator do
  def adapt_to_workload(agent, metrics) do
    directives = cond do
      metrics.queue_size > 100 ->
        [
          %Directive.Spawn{
            module: RubberDuck.Agents.Worker,
            args: [pool_id: agent.id]
          },
          %Directive.RegisterAction{
            action_module: Actions.ParallelProcess
          }
        ]
      
      metrics.error_rate > 0.1 ->
        [
          %Directive.DeregisterAction{
            action_module: Actions.AggressiveOptimization
          },
          %Directive.Enqueue{
            action: :switch_to_safe_mode,
            params: %{reason: :high_error_rate}
          }
        ]
      
      true -> []
    end
    
    {:ok, directives}
  end
end
```

#### Benefits
- **Runtime Adaptation**: Modify agent behavior without restart
- **Dynamic Scaling**: Spawn/kill workers based on load
- **Feature Toggles**: Enable/disable capabilities dynamically
- **Self-Healing**: Agents can modify themselves based on performance

## Phase-Specific Improvements

### Phase 1: Agentic Foundation

**Current Plan**: Custom agent implementations with learning capabilities

**Jido Enhancement**:
- Package learning capabilities as a reusable `LearningSkill`
- Use Instructions for experience recording workflows
- Implement Directives for runtime learning parameter adjustment

```elixir
defmodule RubberDuck.Skills.Learning do
  use Jido.Skill,
    name: "learning",
    description: "Autonomous learning from experiences",
    opts_key: :learning

  def initial_state do
    %{
      experiences: [],
      patterns: %{},
      confidence_threshold: 0.7
    }
  end

  def router do
    [
      %{
        path: "experience.gained",
        instruction: %Instruction{
          action: Learn,
          opts: [async: true]
        }
      }
    ]
  end
end
```

### Phase 2: LLM Orchestration

**Current Plan**: Custom orchestrator with provider selection

**Jido Enhancement**:
- Create `LLMProviderSkill` for each provider
- Use Instructions for request routing logic
- Implement Directives for dynamic provider management

```elixir
defmodule RubberDuck.Skills.OpenAIProvider do
  use Jido.Skill,
    name: "openai_provider",
    signals: [
      input: ["llm.request.openai.*"],
      output: ["llm.response.*", "llm.error.*"]
    ]

  def router do
    [
      %{
        path: "llm.request.openai.complete",
        instruction: %Instruction{
          action: OpenAIComplete,
          opts: [timeout: 30_000]
        }
      }
    ]
  end
end
```

### Phase 2A: Runic Workflow Integration

**Current Plan**: Integrate Runic for workflow composition

**Jido Enhancement**:
- Combine Runic workflows with Jido Instructions
- Use Skills to package Runic workflow templates
- Implement workflow modification through Directives

```elixir
defmodule RubberDuck.Skills.WorkflowComposer do
  use Jido.Skill,
    name: "workflow_composer"

  def compose_workflow(goal) do
    # Use Runic for complex flow control
    runic_flow = Runic.Flow.new()
      |> Runic.Flow.step(analyze_goal(goal))
      |> Runic.Flow.branch(&select_path/1)
    
    # Convert to Jido Instructions for execution
    instructions = runic_to_instructions(runic_flow)
    
    %Directive.Enqueue{
      action: :execute_workflow,
      params: %{instructions: instructions}
    }
  end
end
```

### Phase 3: Tool Agent System

**Current Plan**: Intelligent tool selection and execution

**Jido Enhancement**:
- Each tool becomes a Skill with standardized interface
- Use Instructions for tool composition pipelines
- Implement tool hot-swapping via Directives

### Phase 4: Multi-Agent Planning

**Current Plan**: Distributed agent coordination

**Jido Enhancement**:
- Use Skills for agent discovery and capability negotiation
- Implement planning through Instruction composition
- Enable dynamic team formation via Directives

### Phase 5: Memory & Context

**Current Plan**: Self-organizing memory agents

**Jido Enhancement**:
- Create `MemorySkill` with different storage strategies
- Use Instructions for memory operations workflow
- Implement memory optimization through Directives

### Phase 7: Conversation System

**Current Plan**: Learning conversation agents

**Jido Enhancement**:
- Package conversation patterns as Skills
- Use Instructions for multi-turn dialogue management
- Adapt conversation style via Directives

### Phase 9: Instruction Management

**Current Plan**: Hierarchical instruction system

**Jido Enhancement**:
- Leverage Jido's Instruction patterns directly
- Create `PromptSkill` for LLM instruction optimization
- Use Directives for runtime prompt modification

## Implementation Recommendations

### 1. Immediate Actions

1. **Refactor Base Agent**: Update `RubberDuck.Agents.Base` to support Skills
2. **Create Core Skills**: Extract common functionality into reusable Skills
3. **Implement Skill Registry**: Central registry for skill discovery and management

### 2. Migration Strategy

1. **Phase 1**: Convert existing actions into Skill-based routers
2. **Phase 2**: Replace custom workflows with Instruction chains
3. **Phase 3**: Implement Directive-based runtime modification
4. **Phase 4**: Enable third-party Skill development

### 3. Architecture Benefits

- **Modularity**: Clean separation of concerns through Skills
- **Flexibility**: Runtime behavior modification via Directives
- **Composability**: Complex behaviors from simple Instructions
- **Extensibility**: Plugin architecture for community contributions
- **Maintainability**: Standardized patterns reduce custom code

## Example: Refactored ProjectAgent

```elixir
defmodule RubberDuck.Agents.ProjectAgent do
  use Jido.Agent,
    name: "project_agent",
    schema: [
      project_id: [type: :string, required: true],
      monitoring_enabled: [type: :boolean, default: true]
    ]

  def start_link(opts) do
    skills = [
      {RubberDuck.Skills.CodeAnalysis, [quality_threshold: 0.9]},
      {RubberDuck.Skills.DependencyManagement, []},
      {RubberDuck.Skills.RefactoringAdvisor, [confidence: 0.8]},
      {RubberDuck.Skills.Learning, []}
    ]
    
    routes = [
      {"project.analyze", %Instruction{
        action: :compose_analysis_workflow,
        opts: [timeout: 60_000]
      }},
      {"project.optimize", %Instruction{
        action: :run_optimization_pipeline
      }}
    ]
    
    Jido.Agent.Server.start_link(
      agent: __MODULE__,
      skills: skills,
      routes: routes,
      opts: opts
    )
  end

  # Runtime adaptation
  def handle_performance_degradation(agent, metrics) do
    directives = [
      %Directive.DeregisterAction{
        action_module: ExpensiveAnalysis
      },
      %Directive.RegisterAction{
        action_module: LightweightAnalysis
      },
      %Directive.Enqueue{
        action: :notify_performance_mode,
        params: %{mode: :degraded, metrics: metrics}
      }
    ]
    
    {:ok, directives}
  end
end
```

## Conclusion

Integrating Jido's Skills, Instructions, and Directives into RubberDuck will:

1. **Simplify Architecture**: Replace custom implementations with proven patterns
2. **Increase Flexibility**: Enable runtime adaptation and plugin extensibility
3. **Improve Maintainability**: Standardized patterns reduce complexity
4. **Enable Innovation**: Community can contribute Skills without core changes
5. **Future-Proof Design**: Leverage Jido's ongoing development

The investment in refactoring to fully leverage Jido will pay dividends in reduced complexity, increased capability, and community extensibility.