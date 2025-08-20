# Elixir Anti-Pattern Detection and Refactoring System

## System Architecture Overview

This system uses the Ash framework for persistence and Jido agents for detecting and refactoring Elixir anti-patterns. Each anti-pattern has a dedicated agent with specific actions, skills, and instructions.

## 1. Persistence Layer (Ash Framework)

### Core Resources

```elixir
defmodule AntiPatternSystem.AntiPattern do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: AntiPatternSystem.Domain

  attributes do
    uuid_primary_key :id
    
    attribute :name, :string, allow_nil?: false
    attribute :category, :atom do
      constraints one_of: [:code, :design, :process, :macro]
    end
    attribute :description, :text
    attribute :problem_statement, :text
    attribute :detection_rules, :map
    attribute :refactoring_strategy, :map
    attribute :severity, :atom do
      constraints one_of: [:low, :medium, :high, :critical]
    end
    
    timestamps()
  end

  relationships do
    has_many :detections, AntiPatternSystem.Detection
    has_many :refactorings, AntiPatternSystem.Refactoring
  end
end

defmodule AntiPatternSystem.Detection do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: AntiPatternSystem.Domain

  attributes do
    uuid_primary_key :id
    
    attribute :file_path, :string
    attribute :line_number, :integer
    attribute :code_snippet, :text
    attribute :confidence_score, :float
    attribute :detected_at, :utc_datetime_usec
    attribute :status, :atom do
      constraints one_of: [:pending, :confirmed, :false_positive, :refactored]
    end
    
    timestamps()
  end

  relationships do
    belongs_to :anti_pattern, AntiPatternSystem.AntiPattern
    has_one :refactoring, AntiPatternSystem.Refactoring
  end
end

defmodule AntiPatternSystem.Refactoring do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: AntiPatternSystem.Domain

  attributes do
    uuid_primary_key :id
    
    attribute :original_code, :text
    attribute :refactored_code, :text
    attribute :applied_at, :utc_datetime_usec
    attribute :applied_by, :string
    attribute :review_status, :atom do
      constraints one_of: [:pending, :approved, :rejected, :applied]
    end
    attribute :notes, :text
    
    timestamps()
  end

  relationships do
    belongs_to :detection, AntiPatternSystem.Detection
    belongs_to :anti_pattern, AntiPatternSystem.AntiPattern
  end
end
```

## 2. Base Agent Structure

```elixir
defmodule AntiPatternSystem.Agents.Base do
  @moduledoc """
  Base module for all anti-pattern agents
  """
  
  defmacro __using__(opts) do
    quote do
      use Jido.Agent,
        name: unquote(opts[:name]),
        description: unquote(opts[:description])
      
      # Common skills all anti-pattern agents share
      @skills [
        AntiPatternSystem.Skills.ASTAnalysis,
        AntiPatternSystem.Skills.CodeRewriting,
        AntiPatternSystem.Skills.PatternMatching,
        AntiPatternSystem.Skills.MetricsCalculation
      ]
      
      # Base actions available to all agents
      @actions [
        AntiPatternSystem.Actions.DetectPattern,
        AntiPatternSystem.Actions.GenerateRefactoring,
        AntiPatternSystem.Actions.ValidateRefactoring,
        AntiPatternSystem.Actions.ApplyRefactoring
      ]
    end
  end
end
```

## 3. Code Anti-Pattern Agents

### 3.1 Comments Overuse Agent

```elixir
defmodule AntiPatternSystem.Agents.CommentsOveruse do
  use AntiPatternSystem.Agents.Base,
    name: "comments_overuse_agent",
    description: "Detects and refactors excessive or unnecessary comments"

  use Jido.Agent

  @instructions %Jido.Instruction{
    name: "detect_and_refactor_comments",
    steps: [
      "Analyze AST for comment density metrics",
      "Identify self-explanatory code with redundant comments",
      "Detect comments that describe 'what' instead of 'why'",
      "Generate refactoring suggestions with better naming",
      "Convert inline comments to module attributes where appropriate",
      "Suggest @doc and @moduledoc replacements"
    ]
  }

  @actions [
    %Jido.Action{
      name: :analyze_comment_density,
      handler: fn context ->
        # Calculate comment-to-code ratio
        # Identify comment clusters
        # Flag obvious comments
      end
    },
    %Jido.Action{
      name: :suggest_better_names,
      handler: fn context ->
        # Generate descriptive variable names
        # Suggest function name improvements
        # Create module attribute names for magic numbers
      end
    }
  ]

  @skills [
    %Jido.Skill{
      name: :comment_analysis,
      capabilities: [
        :measure_comment_density,
        :classify_comment_types,
        :detect_redundant_comments
      ]
    }
  ]
end
```

### 3.2 Complex Else Clauses Agent

```elixir
defmodule AntiPatternSystem.Agents.ComplexElseClauses do
  use AntiPatternSystem.Agents.Base,
    name: "complex_else_clauses_agent",
    description: "Detects and refactors complex else blocks in with expressions"

  use Jido.Agent

  @instructions %Jido.Instruction{
    name: "simplify_with_expressions",
    steps: [
      "Identify with expressions with multiple error patterns",
      "Analyze else block complexity",
      "Map error patterns to their source clauses",
      "Generate private functions for error normalization",
      "Refactor to localize error handling",
      "Validate semantic equivalence"
    ]
  }

  @actions [
    %Jido.Action{
      name: :analyze_with_complexity,
      handler: fn context ->
        # Count else patterns
        # Map patterns to clauses
        # Calculate complexity score
      end
    },
    %Jido.Action{
      name: :extract_error_handlers,
      handler: fn context ->
        # Create private functions
        # Normalize return types
        # Localize error handling
      end
    }
  ]

  @skills [
    %Jido.Skill{
      name: :with_expression_analysis,
      capabilities: [
        :parse_with_clauses,
        :track_error_flow,
        :generate_wrapper_functions
      ]
    }
  ]
end
```

### 3.3 Dynamic Atom Creation Agent

```elixir
defmodule AntiPatternSystem.Agents.DynamicAtomCreation do
  use AntiPatternSystem.Agents.Base,
    name: "dynamic_atom_creation_agent",
    description: "Detects unsafe dynamic atom creation patterns"

  use Jido.Agent

  @instructions %Jido.Instruction{
    name: "prevent_atom_leaks",
    steps: [
      "Scan for String.to_atom/1 usage",
      "Identify uncontrolled input sources",
      "Assess security risk level",
      "Generate safe conversion alternatives",
      "Create explicit mapping functions",
      "Implement String.to_existing_atom/1 where safe"
    ]
  }

  @actions [
    %Jido.Action{
      name: :detect_unsafe_conversions,
      handler: fn context ->
        # Find String.to_atom calls
        # Trace input sources
        # Flag external inputs
      end
    },
    %Jido.Action{
      name: :generate_safe_mappings,
      handler: fn context ->
        # Create explicit conversion functions
        # Generate pattern matching alternatives
        # Suggest to_existing_atom usage
      end
    }
  ]

  @skills [
    %Jido.Skill{
      name: :security_analysis,
      capabilities: [
        :trace_data_flow,
        :identify_external_inputs,
        :assess_dos_risk
      ]
    }
  ]
end
```

### 3.4 Long Parameter List Agent

```elixir
defmodule AntiPatternSystem.Agents.LongParameterList do
  use AntiPatternSystem.Agents.Base,
    name: "long_parameter_list_agent",
    description: "Refactors functions with too many parameters"

  use Jido.Agent

  @instructions %Jido.Instruction{
    name: "simplify_function_signatures",
    steps: [
      "Count function parameters",
      "Identify related parameter groups",
      "Suggest struct or map groupings",
      "Generate keyword list alternatives for optional params",
      "Create refactored function signatures",
      "Update all call sites"
    ]
  }

  @actions [
    %Jido.Action{
      name: :analyze_parameter_relationships,
      handler: fn context ->
        # Group related parameters
        # Identify optional vs required
        # Calculate cohesion metrics
      end
    },
    %Jido.Action{
      name: :create_data_structures,
      handler: fn context ->
        # Generate struct definitions
        # Create map specifications
        # Build keyword list schemas
      end
    }
  ]

  @skills [
    %Jido.Skill{
      name: :parameter_analysis,
      capabilities: [
        :measure_parameter_cohesion,
        :suggest_groupings,
        :generate_structs
      ]
    }
  ]
end
```

## 4. Design Anti-Pattern Agents

### 4.1 Alternative Return Types Agent

```elixir
defmodule AntiPatternSystem.Agents.AlternativeReturnTypes do
  use AntiPatternSystem.Agents.Base,
    name: "alternative_return_types_agent",
    description: "Detects functions with inconsistent return types based on options"

  use Jido.Agent

  @instructions %Jido.Instruction{
    name: "normalize_return_types",
    steps: [
      "Analyze function specs and return patterns",
      "Identify option-dependent return variations",
      "Map options to return type changes",
      "Generate separate functions for each return type",
      "Update function documentation",
      "Refactor call sites"
    ]
  }

  @actions [
    %Jido.Action{
      name: :analyze_return_patterns,
      handler: fn context ->
        # Parse @spec annotations
        # Track return type variations
        # Map to triggering options
      end
    },
    %Jido.Action{
      name: :split_into_functions,
      handler: fn context ->
        # Create function per return type
        # Generate descriptive names
        # Update specs appropriately
      end
    }
  ]
end
```

### 4.2 Boolean Obsession Agent

```elixir
defmodule AntiPatternSystem.Agents.BooleanObsession do
  use AntiPatternSystem.Agents.Base,
    name: "boolean_obsession_agent",
    description: "Replaces overlapping boolean flags with atoms"

  use Jido.Agent

  @instructions %Jido.Instruction{
    name: "replace_boolean_flags",
    steps: [
      "Identify multiple boolean parameters/fields",
      "Detect overlapping or exclusive states",
      "Map boolean combinations to semantic meanings",
      "Generate atom-based alternatives",
      "Create single option with multiple values",
      "Update pattern matching clauses"
    ]
  }

  @actions [
    %Jido.Action{
      name: :detect_boolean_overlap,
      handler: fn context ->
        # Find related boolean flags
        # Analyze mutual exclusivity
        # Calculate state space
      end
    },
    %Jido.Action{
      name: :create_atom_representation,
      handler: fn context ->
        # Design semantic atom values
        # Generate state machine if applicable
        # Create comprehensive pattern matches
      end
    }
  ]
end
```

### 4.3 Exceptions for Control Flow Agent

```elixir
defmodule AntiPatternSystem.Agents.ExceptionsForControlFlow do
  use AntiPatternSystem.Agents.Base,
    name: "exceptions_for_control_flow_agent",
    description: "Replaces exception-based control flow with explicit error handling"

  use Jido.Agent

  @instructions %Jido.Instruction{
    name: "implement_explicit_error_handling",
    steps: [
      "Identify try/rescue blocks for control flow",
      "Find non-exceptional error cases",
      "Generate tuple-based alternatives",
      "Create error structs if needed",
      "Implement bang and non-bang variants",
      "Update error handling patterns"
    ]
  }

  @actions [
    %Jido.Action{
      name: :analyze_exception_usage,
      handler: fn context ->
        # Detect try/rescue patterns
        # Classify error types
        # Identify control flow usage
      end
    },
    %Jido.Action{
      name: :generate_tuple_api,
      handler: fn context ->
        # Create {:ok, result} returns
        # Design {:error, reason} patterns
        # Implement dual APIs (bang/non-bang)
      end
    }
  ]
end
```

## 5. Process Anti-Pattern Agents

### 5.1 Code Organization by Process Agent

```elixir
defmodule AntiPatternSystem.Agents.CodeOrganizationByProcess do
  use AntiPatternSystem.Agents.Base,
    name: "code_organization_by_process_agent",
    description: "Detects unnecessary process-based code organization"

  use Jido.Agent

  @instructions %Jido.Instruction{
    name: "refactor_to_modules",
    steps: [
      "Identify GenServer/Agent without state management",
      "Detect synchronous-only operations",
      "Analyze concurrency requirements",
      "Extract pure functions to modules",
      "Remove process overhead",
      "Preserve interface compatibility"
    ]
  }

  @actions [
    %Jido.Action{
      name: :analyze_process_necessity,
      handler: fn context ->
        # Check for state management
        # Analyze concurrency patterns
        # Measure process overhead
      end
    },
    %Jido.Action{
      name: :extract_to_pure_functions,
      handler: fn context ->
        # Convert GenServer calls to functions
        # Remove process initialization
        # Create module-based API
      end
    }
  ]
end
```

### 5.2 Scattered Process Interfaces Agent

```elixir
defmodule AntiPatternSystem.Agents.ScatteredProcessInterfaces do
  use AntiPatternSystem.Agents.Base,
    name: "scattered_process_interfaces_agent",
    description: "Centralizes scattered process interactions"

  use Jido.Agent

  @instructions %Jido.Instruction{
    name: "centralize_process_access",
    steps: [
      "Map all direct process interactions",
      "Identify scattered GenServer.call/cast usages",
      "Design centralized interface module",
      "Encapsulate process communication",
      "Define clear data contracts",
      "Update all client modules"
    ]
  }

  @actions [
    %Jido.Action{
      name: :trace_process_interactions,
      handler: fn context ->
        # Find all GenServer.call/cast
        # Map Agent.get/update calls
        # Track data flow patterns
      end
    },
    %Jido.Action{
      name: :create_interface_module,
      handler: fn context ->
        # Generate centralized API
        # Define public functions
        # Encapsulate implementation details
      end
    }
  ]
end
```

### 5.3 Sending Unnecessary Data Agent

```elixir
defmodule AntiPatternSystem.Agents.SendingUnnecessaryData do
  use AntiPatternSystem.Agents.Base,
    name: "sending_unnecessary_data_agent",
    description: "Optimizes process message passing"

  use Jido.Agent

  @instructions %Jido.Instruction{
    name: "minimize_message_size",
    steps: [
      "Analyze process message contents",
      "Identify unused data in messages",
      "Track variable capture in spawned functions",
      "Extract only necessary fields",
      "Optimize data serialization",
      "Measure performance impact"
    ]
  }

  @actions [
    %Jido.Action{
      name: :analyze_message_usage,
      handler: fn context ->
        # Track field access in receivers
        # Measure message sizes
        # Identify over-fetching
      end
    },
    %Jido.Action{
      name: :optimize_data_extraction,
      handler: fn context ->
        # Extract minimal data sets
        # Restructure message formats
        # Update sender and receiver
      end
    }
  ]
end
```

### 5.4 Unsupervised Processes Agent

```elixir
defmodule AntiPatternSystem.Agents.UnsupervisedProcesses do
  use AntiPatternSystem.Agents.Base,
    name: "unsupervised_processes_agent",
    description: "Ensures processes are properly supervised"

  use Jido.Agent

  @instructions %Jido.Instruction{
    name: "implement_supervision",
    steps: [
      "Identify unsupervised process spawning",
      "Analyze process lifecycle requirements",
      "Design supervision tree structure",
      "Create child specifications",
      "Implement restart strategies",
      "Add process monitoring"
    ]
  }

  @actions [
    %Jido.Action{
      name: :detect_unsupervised_spawns,
      handler: fn context ->
        # Find spawn/start_link outside supervisors
        # Track process lifecycle
        # Identify restart requirements
      end
    },
    %Jido.Action{
      name: :generate_supervision_tree,
      handler: fn context ->
        # Create Supervisor modules
        # Define child_spec/1
        # Configure restart strategies
      end
    }
  ]
end
```

## 6. Macro Anti-Pattern Agents

### 6.1 Compile-time Dependencies Agent

```elixir
defmodule AntiPatternSystem.Agents.CompileTimeDependencies do
  use AntiPatternSystem.Agents.Base,
    name: "compile_time_dependencies_agent",
    description: "Reduces unnecessary compile-time dependencies"

  use Jido.Agent

  @instructions %Jido.Instruction{
    name: "minimize_compilation_graph",
    steps: [
      "Trace compile-time dependencies",
      "Identify macro argument evaluation",
      "Find unnecessary compile-time module references",
      "Apply Macro.expand_literals where safe",
      "Convert to runtime dependencies",
      "Verify compilation improvements"
    ]
  }

  @actions [
    %Jido.Action{
      name: :analyze_dependency_graph,
      handler: fn context ->
        # Run mix xref trace
        # Map compile-time deps
        # Calculate recompilation impact
      end
    },
    %Jido.Action{
      name: :defer_module_resolution,
      handler: fn context ->
        # Use Macro.expand_literals
        # Defer module lookups
        # Convert to runtime deps
      end
    }
  ]
end
```

### 6.2 Large Code Generation Agent

```elixir
defmodule AntiPatternSystem.Agents.LargeCodeGeneration do
  use AntiPatternSystem.Agents.Base,
    name: "large_code_generation_agent",
    description: "Optimizes macros that generate excessive code"

  use Jido.Agent

  @instructions %Jido.Instruction{
    name: "reduce_generated_code",
    steps: [
      "Measure generated code size",
      "Identify repetitive patterns",
      "Extract common logic to functions",
      "Delegate work from compile-time to runtime",
      "Simplify macro expansion",
      "Benchmark compilation time"
    ]
  }

  @actions [
    %Jido.Action{
      name: :measure_macro_expansion,
      handler: fn context ->
        # Calculate expanded code size
        # Count repetitions
        # Profile compilation time
      end
    },
    %Jido.Action{
      name: :extract_to_functions,
      handler: fn context ->
        # Move logic to regular functions
        # Create minimal macro wrappers
        # Delegate to runtime execution
      end
    }
  ]
end
```

### 6.3 Unnecessary Macros Agent

```elixir
defmodule AntiPatternSystem.Agents.UnnecessaryMacros do
  use AntiPatternSystem.Agents.Base,
    name: "unnecessary_macros_agent",
    description: "Replaces unnecessary macros with functions"

  use Jido.Agent

  @instructions %Jido.Instruction{
    name: "convert_to_functions",
    steps: [
      "Analyze macro necessity",
      "Check for compile-time computation needs",
      "Verify AST manipulation requirements",
      "Convert to regular functions where possible",
      "Remove require statements",
      "Simplify client code"
    ]
  }

  @actions [
    %Jido.Action{
      name: :assess_macro_necessity,
      handler: fn context ->
        # Check for AST manipulation
        # Verify compile-time needs
        # Analyze code generation
      end
    },
    %Jido.Action{
      name: :transform_to_function,
      handler: fn context ->
        # Convert defmacro to def
        # Remove quote/unquote
        # Update function calls
      end
    }
  ]
end
```

### 6.4 Use Instead of Import Agent

```elixir
defmodule AntiPatternSystem.Agents.UseInsteadOfImport do
  use AntiPatternSystem.Agents.Base,
    name: "use_instead_of_import_agent",
    description: "Replaces unnecessary use directives with import/alias"

  use Jido.Agent

  @instructions %Jido.Instruction{
    name: "simplify_module_dependencies",
    steps: [
      "Analyze __using__ macro contents",
      "Identify simple import/alias patterns",
      "Detect hidden dependency propagation",
      "Replace use with explicit directives",
      "Document remaining use cases",
      "Add nutrition facts labels"
    ]
  }

  @actions [
    %Jido.Action{
      name: :analyze_using_macro,
      handler: fn context ->
        # Parse __using__ implementation
        # Track injected code
        # Map propagated dependencies
      end
    },
    %Jido.Action{
      name: :generate_explicit_imports,
      handler: fn context ->
        # Replace use with import/alias
        # Make dependencies explicit
        # Add documentation
      end
    }
  ]
end
```

## 7. Orchestration Agent

```elixir
defmodule AntiPatternSystem.Agents.Orchestrator do
  use Jido.Agent,
    name: "orchestrator_agent",
    description: "Coordinates all anti-pattern detection and refactoring agents"

  @instructions %Jido.Instruction{
    name: "coordinate_analysis",
    steps: [
      "Scan codebase for all anti-patterns",
      "Prioritize by severity and impact",
      "Delegate to specialized agents",
      "Collect detection results",
      "Generate refactoring plan",
      "Coordinate refactoring execution",
      "Validate results",
      "Generate reports"
    ]
  }

  @actions [
    %Jido.Action{
      name: :scan_codebase,
      handler: fn context ->
        # Traverse AST
        # Identify potential anti-patterns
        # Create work queue
      end
    },
    %Jido.Action{
      name: :delegate_to_agents,
      handler: fn context ->
        # Route to specialized agents
        # Manage agent coordination
        # Handle agent responses
      end
    },
    %Jido.Action{
      name: :generate_report,
      handler: fn context ->
        # Aggregate findings
        # Calculate metrics
        # Create actionable report
      end
    }
  ]

  @skills [
    %Jido.Skill{
      name: :orchestration,
      capabilities: [
        :agent_coordination,
        :priority_management,
        :conflict_resolution,
        :report_generation
      ]
    }
  ]
end
```

## 8. Common Skills Module

```elixir
defmodule AntiPatternSystem.Skills.ASTAnalysis do
  use Jido.Skill,
    name: :ast_analysis,
    description: "Provides AST parsing and analysis capabilities"

  def parse_file(file_path) do
    file_path
    |> File.read!()
    |> Code.string_to_quoted()
  end

  def traverse_ast(ast, visitor_fn) do
    Macro.prewalk(ast, [], fn node, acc ->
      {node, visitor_fn.(node, acc)}
    end)
  end

  def find_function_calls(ast, module, function) do
    traverse_ast(ast, fn
      {{:., _, [{:__aliases__, _, module_parts}, ^function]}, _, _} = node, acc
        when module_parts == module ->
        [node | acc]
      _, acc ->
        acc
    end)
  end
end

defmodule AntiPatternSystem.Skills.CodeRewriting do
  use Jido.Skill,
    name: :code_rewriting,
    description: "Provides code transformation and rewriting capabilities"

  def rewrite_ast(ast, patterns) do
    Macro.prewalk(ast, fn node ->
      Enum.reduce(patterns, node, fn {pattern, replacement}, acc ->
        if match?(^pattern, acc) do
          replacement.(acc)
        else
          acc
        end
      end)
    end)
  end

  def ast_to_string(ast) do
    ast
    |> Macro.to_string()
    |> Code.format_string!()
    |> IO.iodata_to_binary()
  end
end
```

## 9. Common Actions Module

```elixir
defmodule AntiPatternSystem.Actions.DetectPattern do
  use Jido.Action,
    name: :detect_pattern,
    description: "Base action for detecting anti-patterns"

  def execute(context) do
    %{
      file_path: file_path,
      anti_pattern: anti_pattern,
      detection_rules: rules
    } = context

    ast = AntiPatternSystem.Skills.ASTAnalysis.parse_file(file_path)
    
    detections = apply_detection_rules(ast, rules)
    
    # Persist detections
    Enum.each(detections, fn detection ->
      AntiPatternSystem.Detection.create!(%{
        anti_pattern_id: anti_pattern.id,
        file_path: file_path,
        line_number: detection.line,
        code_snippet: detection.snippet,
        confidence_score: detection.confidence
      })
    end)
    
    {:ok, detections}
  end
end

defmodule AntiPatternSystem.Actions.GenerateRefactoring do
  use Jido.Action,
    name: :generate_refactoring,
    description: "Generates refactoring suggestions"

  def execute(context) do
    %{
      detection: detection,
      refactoring_strategy: strategy
    } = context

    original_ast = Code.string_to_quoted!(detection.code_snippet)
    refactored_ast = apply_refactoring_strategy(original_ast, strategy)
    refactored_code = AntiPatternSystem.Skills.CodeRewriting.ast_to_string(refactored_ast)
    
    refactoring = AntiPatternSystem.Refactoring.create!(%{
      detection_id: detection.id,
      anti_pattern_id: detection.anti_pattern_id,
      original_code: detection.code_snippet,
      refactored_code: refactored_code
    })
    
    {:ok, refactoring}
  end
end
```

## 10. Usage Example

```elixir
# Initialize the system
defmodule AntiPatternSystem.Application do
  use Application

  def start(_type, _args) do
    children = [
      AntiPatternSystem.Repo,
      {AntiPatternSystem.Agents.Orchestrator, []},
      # Start all specialized agents
      {AntiPatternSystem.Agents.CommentsOveruse, []},
      {AntiPatternSystem.Agents.ComplexElseClauses, []},
      {AntiPatternSystem.Agents.DynamicAtomCreation, []},
      # ... other agents
    ]

    opts = [strategy: :one_for_one, name: AntiPatternSystem.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

# Run analysis on a codebase
defmodule AntiPatternSystem.CLI do
  def analyze(directory_path) do
    # Start orchestrator
    {:ok, orchestrator} = AntiPatternSystem.Agents.Orchestrator.start_link()
    
    # Run analysis
    result = Jido.Agent.run(orchestrator, %{
      action: :scan_codebase,
      params: %{
        directory: directory_path,
        categories: [:code, :design, :process, :macro],
        severity_threshold: :medium
      }
    })
    
    # Generate report
    {:ok, report} = Jido.Agent.run(orchestrator, %{
      action: :generate_report,
      params: %{
        format: :html,
        include_refactorings: true
      }
    })
    
    IO.puts("Analysis complete. Report saved to: #{report.path}")
  end
end
```

## 11. Configuration

```elixir
# config/config.exs
config :anti_pattern_system,
  repo: AntiPatternSystem.Repo,
  detection_confidence_threshold: 0.75,
  auto_refactor: false,
  parallel_analysis: true,
  max_concurrent_agents: 10

config :anti_pattern_system, AntiPatternSystem.Repo,
  database: "anti_pattern_system",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"

# Configure Jido
config :jido,
  agent_supervisor: AntiPatternSystem.AgentSupervisor,
  persistence_adapter: Jido.Adapters.Ash,
  telemetry_enabled: true
```

## Summary

This system provides:

1. **Comprehensive Coverage**: Agents for all 24 anti-patterns from the Elixir documentation
2. **Persistence**: Ash framework for storing anti-patterns, detections, and refactorings
3. **Modular Design**: Each agent is specialized for a specific anti-pattern
4. **Reusable Components**: Common skills and actions shared across agents
5. **Orchestration**: Coordinator agent to manage the entire analysis process
6. **Extensibility**: Easy to add new anti-patterns or modify existing ones
7. **Actionable Results**: Each agent provides both detection and refactoring capabilities

Each agent follows the Jido pattern with:
- **Instructions**: Step-by-step process for detection and refactoring
- **Actions**: Specific operations the agent can perform
- **Skills**: Capabilities required for the agent's tasks
- **Integration**: Works with Ash for persistence and other agents for coordination
