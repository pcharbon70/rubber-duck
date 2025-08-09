# Designing an Elixir Code Smell Detection and Refactoring System with Ash and Jido

This comprehensive research report provides the architectural design and implementation guidance for building an automated code smell detection and refactoring system in Elixir, leveraging the Ash framework for persistence and the Jido library for intelligent agent orchestration.

## System architecture overview

The proposed system employs a multi-agent architecture where specialized agents handle detection, analysis, refactoring, and coordination tasks. The system automatically identifies both traditional code smells (Long Function, Feature Envy, Shotgun Surgery) and Elixir-specific smells (Complex multi-clause function, GenServer Envy, Exceptions for control-flow), then orchestrates appropriate refactoring actions through agent communication.

## Comprehensive code smell catalog and detection patterns

Research from the lucasvegi/Elixir-Code-Smells repository reveals **35+ documented code smells** affecting Elixir systems, categorized into design-related smells (14), low-level concerns (9), and traditional smells adapted for Elixir (12). Each smell has specific AST-based detection patterns suitable for automated analysis.

### Design-related Elixir smells

**GenServer Envy** occurs when Agent/Task abstractions are used beyond their specialized purposes. Detection involves identifying Agent modules with frequent message exchanges or Task processes used for persistent communication. The AST pattern searches for multiple `Agent.*` calls within single functions.

**Agent Obsession** manifests as direct Agent access spread across the system rather than centralized management. Detection patterns include finding `Agent.update/get` calls across multiple modules and checking for missing wrapper modules. The severity is medium as it reduces maintainability.

**Unsupervised Process** represents long-running processes created outside supervision trees. Detection involves finding `GenServer.start/3` calls without corresponding supervisor child specs. This high-severity smell critically impacts fault tolerance.

**Complex Multi-clause Functions** group unrelated business logic in single functions. Detection patterns identify functions with >5 different patterns unrelated to the same domain, with mixed data types indicating different purposes.

### Detection implementation with AST analysis

Elixir's AST structure consists of three-element tuples `{function_name, metadata, arguments}` with literals representing themselves. The system uses `Code.string_to_quoted/2` for parsing source code with column and token metadata preservation:

```elixir
defmodule ASTAnalyzer do
  def analyze_file(file_path) do
    with {:ok, content} <- File.read(file_path),
         {:ok, ast} <- Code.string_to_quoted(content, columns: true, token_metadata: true) do
      
      {_, issues} = Macro.postwalk(ast, [], &detect_patterns/2)
      issues
    end
  end
  
  defp detect_patterns({{:., _, [{:__aliases__, _, [:String]}, :to_atom]}, meta, _} = node, acc) do
    issue = %{type: :unsafe_atom_conversion, line: meta[:line], column: meta[:column]}
    {node, [issue | acc]}
  end
  
  defp detect_patterns({:case, meta, [_, [do: clauses]]}, acc) when length(clauses) > 5 do
    issue = %{type: :complex_case_statement, line: meta[:line], complexity: length(clauses)}
    {node, [issue | acc]}
  end
  
  defp detect_patterns(node, acc), do: {node, acc}
end
```

The Sourceror library enhances AST manipulation with comment preservation and zipper navigation, while Credo's utilities provide static analysis frameworks. Cyclomatic complexity calculation traverses the AST counting decision points like `:if`, `:case`, and `:cond` nodes.

## Ash framework persistence layer design

The persistence layer uses Ash resources to model code smells, detected instances, refactoring suggestions, and analysis history. This declarative approach separates data modeling from business logic while providing powerful query capabilities.

### Core resource definitions

The **CodeSmell resource** defines smell types with detection patterns:

```elixir
defmodule CodeAnalysis.Analysis.CodeSmell do
  use Ash.Resource,
    domain: CodeAnalysis.Analysis,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :category, :atom, constraints: [one_of: [:structural, :bloater, :change_preventer]]
    attribute :severity, :atom, default: :medium
    attribute :detection_pattern, :map  # JSON structure for detection rules
    attribute :enabled, :boolean, default: true
  end

  actions do
    read :by_category do
      argument :category, :atom, allow_nil?: false
      filter expr(category == ^arg(:category))
      prepare build(sort: [severity: :desc, name: :asc])
    end
    
    update :toggle_enabled do
      change set_attribute(:enabled, expr(not enabled))
    end
  end

  calculations do
    calculate :detection_count, :integer, 
      expr(count(detected_instances, query: [filter: created_at > ago(30, :day)]))
  end
end
```

The **DetectedSmell resource** tracks individual smell instances with location data and status tracking. It includes relationships to source files and refactoring suggestions, with calculated fields for effective severity and age metrics.

### Advanced query patterns

Ash enables complex filtering with aggregations and calculated fields:

```elixir
defmodule CodeAnalysis.Queries do
  def critical_smells_in_file(file_path) do
    Analysis.DetectedSmell
    |> Ash.Query.filter(file_path == ^file_path)
    |> Ash.Query.filter(status in [:detected, :acknowledged])
    |> Ash.Query.filter(code_smell.severity in [:high, :critical])
    |> Ash.Query.load([:code_smell, :refactoring_suggestions])
    |> Ash.Query.sort([{:code_smell, :severity}, :line_start])
    |> Analysis.read!()
  end
end
```

Database integration includes PostgreSQL constraints, custom indexes for performance optimization, and check constraints for data integrity. The system uses atomic operations with proper transaction boundaries.

## Jido agent architecture and communication

Jido provides a framework for autonomous agents built on OTP principles with signal-based communication using CloudEvents specification. The architecture centers on four primitives: Actions (discrete work units), Agents (stateful entities), Sensors (monitoring components), and Skills (composable behaviors).

### Detection agent implementation

The detection agent analyzes code files and signals the refactoring agent when smells are detected:

```elixir
defmodule CodeSmellDetection.Agents.DetectionAgent do
  use Jido.Agent,
    name: "code_smell_detector",
    actions: [
      CodeSmellDetection.Actions.AnalyzeFile,
      CodeSmellDetection.Actions.IdentifySmells,
      CodeSmellDetection.Actions.SignalRefactoring
    ],
    schema: [
      analyzed_files: [type: {:list, :string}, default: []],
      detected_smells: [type: {:list, :map}, default: []]
    ]

  def on_after_run(agent, %{smells: smells} = result) when length(smells) > 0 do
    signal = Jido.Signal.new!(%{
      type: "code_smell.detected",
      source: "/detection_agent",
      data: %{file_path: result.file_path, smells: smells},
      jido_dispatch: [
        {:pubsub, [topic: "code_quality"]},
        {:pid, [target: :refactoring_agent, async: true]}
      ]
    })
    
    Jido.Signal.emit(signal)
    {:ok, %{agent | state: Map.put(agent.state, :detected_smells, 
             agent.state.detected_smells ++ smells)}}
  end
end
```

### Refactoring agent with skill composition

The refactoring agent processes detection signals and applies appropriate transformations:

```elixir
defmodule CodeSmellDetection.Agents.RefactoringAgent do
  use Jido.Agent,
    name: "code_refactorer",
    skills: [
      CodeSmellDetection.Skills.RefactoringStrategies,
      CodeSmellDetection.Skills.CodeGeneration
    ]

  def handle_signal(%{type: "code_smell.detected"} = signal, _opts) do
    refactoring_task = %{
      id: Jido.ID.generate(),
      file_path: signal.data.file_path,
      smells: signal.data.smells,
      status: :queued,
      priority: calculate_priority(signal.data.smells)
    }
    
    {:ok, %{refactoring_queue: [refactoring_task]}}
  end
end
```

### Multi-agent coordination patterns

The system implements hierarchical orchestration with a quality orchestrator coordinating detection and refactoring agents. Communication patterns include direct messaging via PID targeting, PubSub broadcasting for topic-based distribution, and workflow chaining for sequential action execution.

Error handling employs circuit breaker patterns with exponential backoff for retry logic. The system maintains agent checkpoints for recovery from failures and uses dynamic supervisors for spawning temporary analysis agents.

## Code smell to refactoring mappings

Traditional refactorings map directly to Elixir implementations:

- **Long Method** → Extract Method, Decompose Conditional
- **Feature Envy** → Move Method, Move Field
- **Shotgun Surgery** → Move Method, Inline Class
- **Duplicate Code** → Extract Method, Form Template Method

Elixir-specific refactorings leverage language features:

- **Nested Conditionals** → Pattern Matching in Function Heads
- **Complex Case Statements** → Multi-Clause Functions
- **Imperative Processing** → Pipeline with `|>` operator
- **Mutable State** → Immutable Data Structures

## Automated refactoring implementation

The Rfx framework provides automated refactoring operations with change set architecture:

```elixir
defmodule RefactoringEngine do
  def apply_extract_method(ast, start_line, end_line, new_method_name) do
    # Extract code block
    extracted_block = extract_lines(ast, start_line, end_line)
    
    # Create new method definition
    new_method = quote do
      def unquote(new_method_name)() do
        unquote(extracted_block)
      end
    end
    
    # Replace original with method call
    replacement = quote do: unquote(new_method_name)()
    
    # Apply transformations
    transformed_ast = ast
    |> insert_method(new_method)
    |> replace_block(start_line, end_line, replacement)
    
    {:ok, transformed_ast}
  end
end
```

Safety mechanisms include comprehensive test coverage validation, dependency analysis before refactoring, atomic transformations with rollback capability, and behavioral equivalence testing post-refactoring.

## Agent orchestration workflows

The system supports three orchestration patterns:

**Sequential orchestration** processes refactorings in linear pipeline fashion, suitable for ordered steps with clear dependencies.

**Concurrent orchestration** enables parallel processing of independent tasks, maximizing resource utilization for faster analysis.

**Event-driven architecture** provides loose coupling between agents with asynchronous processing and easy agent addition/removal.

Failure handling implements compensation patterns for rollback and saga patterns for multi-step transactions:

```elixir
defmodule RefactoringTransaction do
  def execute_with_rollback(operations) do
    {results, compensations} = 
      Enum.reduce_while(operations, {[], []}, fn op, {results, comps} ->
        case execute_operation(op) do
          {:ok, result, compensation} ->
            {:cont, {[result | results], [compensation | comps]}}
          {:error, reason} ->
            Enum.each(comps, &execute_compensation/1)
            {:halt, {:error, reason}}
        end
      end)
    
    {:ok, Enum.reverse(results)}
  end
end
```

## Implementation recommendations

### System deployment architecture

Deploy agents using OTP supervision trees with the following structure:

1. **Orchestrator Agent** - Coordinates overall workflow
2. **Detection Agent Pool** - Parallel file analysis
3. **Planning Agent** - Maps smells to refactorings
4. **Refactoring Agent Pool** - Applies transformations
5. **Validation Agent** - Runs tests and checks

### Integration points

The Ash-Jido integration enables persistent state management through Ash resources while maintaining agent autonomy. Actions can directly interact with Ash changesets for data persistence:

```elixir
defmodule CodeSmellDetection.Actions.PersistAnalysis do
  use Jido.Action
  
  def run(%{smells: smells, file_path: path}, _context) do
    CodeAnalysis.DetectedSmell
    |> Ash.Changeset.for_create(:detect_new_smell, %{
      file_path: path,
      smells: smells,
      analysis_date: DateTime.utc_now()
    })
    |> CodeAnalysis.Repo.create()
  end
end
```

### Performance optimization strategies

- Use parallel AST traversal for large codebases with Task.async_stream
- Implement memoization for repeated pattern matching operations
- Process files in chunks to manage memory consumption
- Enable early termination for specific analysis patterns
- Leverage Elixir's lightweight processes for concurrent agent execution

### User interaction patterns

Implement a three-stage approval workflow: detection and analysis presentation, refactoring preview with diff visualization, and application with validation. Support both CLI and web dashboard interfaces for different use cases.

## Conclusion

This architecture provides a robust foundation for building an intelligent code smell detection and refactoring system in Elixir. By combining Ash's declarative data modeling with Jido's autonomous agent framework, the system achieves scalability, fault tolerance, and extensibility while maintaining code quality through automated analysis and transformation. The event-driven architecture ensures loose coupling between components, while comprehensive safety mechanisms protect against unintended code modifications. This design leverages Elixir's strengths in concurrent processing, pattern matching, and fault-tolerant system design to create a production-ready code quality management platform.
