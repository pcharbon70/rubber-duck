# Comprehensive Tool Definition System Design for RubberDuck

## Architecture analysis reveals opportunity for unified tool system

Based on extensive research of the RubberDuck codebase architecture and LLM tool patterns, the coding assistant's Ash Framework foundation provides an ideal platform for building a sophisticated tool definition system. The existing Spark DSL infrastructure, combined with Reactor's workflow orchestration and planned MCP integration, creates natural extension points for a comprehensive tool system that can serve both internal engines and external MCP clients.

The analysis identified that RubberDuck's architecture follows a resource-oriented design pattern using Ash Framework, with declarative configuration through Spark DSL, event-driven workflows via Reactor, and a pluggable engine system. This architectural foundation aligns perfectly with modern LLM tool patterns observed across LangChain, OpenAI, and Anthropic implementations, while Elixir/OTP's concurrency model provides unique advantages for safe, scalable tool execution.

## Spark DSL enables declarative tool definitions with type safety

The proposed tool definition system leverages Spark DSL to create a declarative, extensible configuration language that maintains consistency with RubberDuck's existing patterns. This approach provides compile-time validation, code generation capabilities, and seamless integration with the current architecture.

```elixir
defmodule RubberDuck.Tool do
  use Spark.Dsl.Extension,
    sections: [@tool_definition, @execution, @security]

  @tool_definition %Spark.Dsl.Section{
    name: :tool,
    describe: "Define tool metadata and parameters",
    schema: [
      name: [type: :atom, required: true],
      description: [type: :string, required: true],
      category: [type: {:one_of, [:filesystem, :web, :command, :api, :composite]}],
      version: [type: :string, default: "1.0.0"]
    ],
    sections: [
      %Spark.Dsl.Section{
        name: :parameters,
        entities: [
          %Spark.Dsl.Entity{
            name: :param,
            target: RubberDuck.Tool.Parameter,
            args: [:name],
            schema: [
              name: [type: :atom, required: true],
              type: [type: :atom, required: true],
              description: [type: :string, required: true],
              required: [type: :boolean, default: false],
              default: [type: :any],
              constraints: [type: :keyword_list]
            ]
          }
        ]
      }
    ]
  }

  @execution %Spark.Dsl.Section{
    name: :execution,
    schema: [
      handler: [type: {:or, [:atom, {:tuple, [:atom, :atom]}]}, required: true],
      timeout: [type: :pos_integer, default: 30_000],
      async: [type: :boolean, default: true],
      retries: [type: :non_neg_integer, default: 3]
    ]
  }

  @security %Spark.Dsl.Section{
    name: :security,
    schema: [
      sandbox: [type: {:one_of, [:none, :process, :container]}, default: :process],
      capabilities: [type: {:list, :atom}, default: []],
      rate_limit: [type: :pos_integer],
      user_consent_required: [type: :boolean, default: false]
    ]
  }
end
```

This DSL approach enables tools to be defined declaratively while maintaining full type safety and validation. The system generates both runtime execution code and MCP-compatible tool descriptions from these definitions, ensuring consistency across all integration points.

## Multi-layer execution architecture ensures isolation and safety

The tool execution system implements a sophisticated multi-layer architecture that balances performance with security. Each layer serves a specific purpose in the execution pipeline, from request validation through result formatting.

**Validation Layer** performs comprehensive input validation using JSON Schema generated from Spark DSL definitions. This layer prevents malformed requests from reaching execution handlers and provides detailed error messages for debugging.

**Authorization Layer** integrates with Ash's policy system to enforce fine-grained access control. Tools can define custom authorization rules based on user roles, resource ownership, or contextual factors.

**Execution Layer** leverages Elixir's process isolation to run each tool in a supervised GenServer. This approach provides natural fault isolation - if a tool crashes, it doesn't affect the system. The layer supports configurable resource limits, timeouts, and cancellation.

**Result Processing Layer** handles output formatting, sensitive data filtering, and result caching. Results are validated against expected schemas before being returned to ensure type safety throughout the system.

```elixir
defmodule RubberDuck.Tool.Executor do
  use GenServer

  def execute(tool_name, params, opts \\ []) do
    with {:ok, tool} <- RubberDuck.Tool.Registry.get(tool_name),
         {:ok, validated} <- validate_params(tool, params),
         {:ok, authorized} <- authorize_execution(tool, opts[:actor]),
         {:ok, result} <- execute_sandboxed(tool, validated, opts) do
      process_result(result, tool)
    end
  end

  defp execute_sandboxed(tool, params, opts) do
    task = Task.Supervisor.async_nolink(
      RubberDuck.Tool.TaskSupervisor,
      fn -> 
        apply(tool.handler, :execute, [params])
      end,
      max_heap_size: opts[:max_heap_size] || 100_000_000
    )

    case Task.await(task, tool.timeout) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> handle_execution_error(reason, tool)
    end
  end
end
```

## MCP integration enables universal tool access

The MCP server implementation exposes RubberDuck's tools to any MCP-compatible client, including IDEs, chat interfaces, and other AI systems. The server maintains stateful connections and handles tool discovery, execution, and result streaming.

```elixir
defmodule RubberDuck.MCP.ToolServer do
  use GenServer
  
  def handle_call({:json_rpc, %{"method" => "tools/list"}}, _from, state) do
    tools = RubberDuck.Tool.Registry.list_tools()
    |> Enum.map(&to_mcp_format/1)
    
    {:reply, {:ok, %{"tools" => tools}}, state}
  end

  def handle_call({:json_rpc, %{"method" => "tools/call", "params" => params}}, from, state) do
    %{"name" => tool_name, "arguments" => args} = params
    
    Task.start(fn ->
      result = RubberDuck.Tool.Executor.execute(tool_name, args, actor: state.actor)
      GenServer.reply(from, format_tool_result(result))
    end)
    
    {:noreply, state}
  end

  defp to_mcp_format(tool) do
    %{
      "name" => to_string(tool.name),
      "description" => tool.description,
      "inputSchema" => generate_json_schema(tool.parameters)
    }
  end
end
```

The MCP integration supports OAuth 2.1 authentication for remote access, tool annotations for UI hints, and proper error handling that distinguishes between protocol errors and tool execution failures.

## Security model leverages BEAM's process isolation

The security architecture takes advantage of BEAM's lightweight processes to provide multiple levels of isolation. Each tool execution runs in an isolated process with configurable resource limits, preventing runaway tools from affecting system stability.

**Process-level sandboxing** uses Erlang's built-in process flags to enforce memory limits and prevent excessive message queue growth. Tools that exceed limits are automatically terminated with proper cleanup.

**Capability-based security** restricts tool access to specific system resources. Tools must explicitly declare required capabilities (filesystem access, network access, etc.) which are enforced at runtime.

**Input sanitization** prevents common attack vectors like path traversal and command injection. The system provides built-in sanitizers for common patterns while allowing custom validation logic.

**Audit logging** tracks all tool executions with full context, enabling security analysis and compliance reporting. The audit system integrates with Ash's change tracking for complete traceability.

## Tool composition enables complex workflows

The system supports sophisticated tool composition patterns through integration with Reactor workflows. Composite tools can orchestrate multiple atomic tools, handle conditional logic, and manage distributed execution.

```elixir
defmodule RubberDuck.Tools.CodeRefactoring do
  use RubberDuck.Tool

  tool do
    name :refactor_module
    description "Analyzes and refactors an Elixir module"
    category :composite
  end

  workflow do
    step :parse_code, tool: :elixir_parser
    step :analyze_complexity, tool: :complexity_analyzer, 
         input: result(:parse_code)
    
    branch :needs_refactoring?, result(:analyze_complexity) do
      true ->
        step :identify_patterns, tool: :pattern_detector
        step :generate_refactoring, tool: :refactoring_generator
        step :validate_refactoring, tool: :code_validator
      
      false ->
        return {:ok, "No refactoring needed"}
    end
  end
end
```

This composition model enables building sophisticated tools from simpler components while maintaining clear execution boundaries and error handling.

## Implementation roadmap aligns with existing phases

The tool system implementation should be phased to align with RubberDuck's development roadmap:

**Phase 1 - Core Infrastructure** (Integrate with Phase 2): Implement basic tool registry, Spark DSL definitions, and execution engine. This provides the foundation for all subsequent features.

**Phase 2 - Engine Integration** (Align with Phase 3): Connect tools to the existing engine system, allowing engines to discover and execute tools. Add structured input/output handling for LLM integration.

**Phase 3 - Workflow Integration** (Align with Phase 4): Integrate tools with Reactor workflows, enabling complex tool compositions and conditional execution patterns.

**Phase 4 - MCP Server** (Implement Phase 8): Deploy full MCP server with authentication, tool discovery, and streaming support. This enables external tool access.

**Phase 5 - Advanced Features**: Add distributed execution, advanced sandboxing options, and performance optimizations based on usage patterns.

## Testing and validation ensure reliability

The tool system includes comprehensive testing infrastructure:

**Property-based testing** uses StreamData to generate random inputs and verify tool behavior across edge cases. This catches subtle bugs that example-based tests might miss.

**Integration testing** verifies tool interaction with engines, workflows, and MCP clients. Tests run in isolated environments to prevent interference.

**Performance benchmarking** tracks tool execution times, memory usage, and system impact. Automated alerts detect performance regressions.

**Security testing** includes fuzzing, penetration testing, and automated vulnerability scanning. The system undergoes regular security audits.

## Conclusion

This comprehensive tool definition system design leverages RubberDuck's existing architectural strengths while incorporating best practices from the broader LLM ecosystem. The Spark DSL approach provides elegant declarative configuration, while Elixir/OTP's process model enables robust isolation and concurrent execution. The phased implementation plan ensures smooth integration with existing systems while building toward full MCP compatibility.

The design prioritizes developer experience through declarative configuration, operational excellence through comprehensive monitoring and testing, and security through multiple isolation layers. By building on Ash Framework's resource-oriented patterns and Reactor's workflow capabilities, the tool system becomes a natural extension of RubberDuck's architecture rather than a bolted-on component.

# Designing a Hooks System for RubberDuck: A Comprehensive Implementation Guide

## Executive Summary

Based on extensive research of Claude's hooks system and Elixir patterns, I've designed a **project-aware** hooks architecture that maintains exact JSON format compatibility with Claude while leveraging Elixir's strengths. The key enhancement is that hooks are scoped per-project, with configurations loaded from:

1. **Project-specific hooks** in `<project>/.rubber_duck/settings.json` (version controlled)
2. **Local overrides** in `<project>/.rubber_duck/settings.local.json` (gitignored)
3. **Global user hooks** in `~/.rubber_duck/settings.json` (applied to all projects)

This design ensures that:

- Each project can have its own hooks configuration
- Hooks execute with the project directory as the working directory
- Teams can share project-specific hooks via version control
- Individual developers can add personal hooks without affecting others

Since the specific RubberDuck Phase 9 implementation details weren't publicly available, this design provides a flexible foundation that can integrate with any existing tool system architecture. The solution uses Elixir behaviors for extensibility, GenServers for state management, and pattern matching for efficient dispatch.

## 1. Core Architecture Design

### Hook System Components

The hooks system is project-aware and consists of five main components that work together to provide Claude-compatible functionality in Elixir:

```elixir
defmodule RubberDuck.Hooks.System do
  @moduledoc """
  Main entry point for the project-aware hooks system, maintaining compatibility
  with Claude's JSON format while leveraging Elixir patterns
  """
  
  use GenServer
  require Logger
  
  defstruct [
    :project_configs,  # Map of project_id => configuration
    :event_bus,
    :matcher_registry,
    :executor,
    :cache
  ]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def execute_hooks(project_id, event_name, data) do
    GenServer.call(__MODULE__, {:execute_hooks, project_id, event_name, data})
  end
  
  def load_project_hooks(project_id) do
    GenServer.call(__MODULE__, {:load_project_hooks, project_id})
  end
  
  def unload_project_hooks(project_id) do
    GenServer.call(__MODULE__, {:unload_project_hooks, project_id})
  end
  
  @impl true
  def init(_opts) do
    state = %__MODULE__{
      project_configs: %{},
      event_bus: RubberDuck.Hooks.EventBus,
      matcher_registry: RubberDuck.Hooks.MatcherRegistry,
      executor: RubberDuck.Hooks.Executor,
      cache: RubberDuck.Hooks.Cache
    }
    {:ok, state}
  end
  
  @impl true
  def handle_call({:load_project_hooks, project_id}, _from, state) do
    case RubberDuck.Hooks.ConfigLoader.load_configuration(project_id) do
      {:ok, config} ->
        new_configs = Map.put(state.project_configs, project_id, config)
        {:reply, :ok, %{state | project_configs: new_configs}}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:execute_hooks, project_id, event_name, data}, _from, state) do
    config = Map.get(state.project_configs, project_id)
    
    if config do
      context = Map.merge(data, %{
        project_id: project_id,
        config: config,
        project_root: get_project_root(project_id)
      })
      
      result = state.executor.execute_hooks(event_name, context)
      {:reply, result, state}
    else
      {:reply, {:error, :project_not_loaded}, state}
    end
  end
  
  defp get_project_root(project_id) do
    case RubberDuck.Workspace.get_project(project_id) do
      {:ok, project} -> project.root_path
      _ -> nil
    end
  end
end
```

### Configuration Loader

The configuration system is project-aware and reads from project-specific `.rubber_duck` directories:

```elixir
defmodule RubberDuck.Hooks.ConfigLoader do
  @doc """
  Loads hook configurations from project-specific .rubber_duck directory hierarchy,
  maintaining Claude's JSON format exactly
  """
  
  @global_config_path "~/.rubber_duck/settings.json"
  
  def load_configuration(project_id) do
    project_root = get_project_root(project_id)
    
    config_paths = [
      # Project-specific settings (checked in to version control)
      Path.join(project_root, ".rubber_duck/settings.json"),
      # Project-specific local settings (gitignored)
      Path.join(project_root, ".rubber_duck/settings.local.json"),
      # Global user settings
      @global_config_path
    ]
    
    config_paths
    |> Enum.map(&expand_path/1)
    |> Enum.filter(&File.exists?/1)
    |> Enum.reduce(%{}, &merge_configs/2)
    |> validate_schema()
  end
  
  defp get_project_root(project_id) do
    # Fetch from the Project resource using Ash
    case RubberDuck.Workspace.get_project(project_id) do
      {:ok, project} -> project.root_path
      _ -> raise "Project #{project_id} not found"
    end
  end
  
  defp expand_path(path) do
    Path.expand(path)
  end
  
  defp merge_configs(config_path, acc) do
    case File.read(config_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, config} -> deep_merge(acc, config)
          _ -> acc
        end
      _ -> acc
    end
  end
  
  defp deep_merge(map1, map2) do
    Map.merge(map1, map2, fn
      _k, v1, v2 when is_map(v1) and is_map(v2) -> deep_merge(v1, v2)
      _k, _v1, v2 -> v2
    end)
  end
  
  defp validate_schema(config) do
    # Validates against Claude's exact JSON schema
    case config do
      %{"hooks" => hooks} when is_map(hooks) ->
        {:ok, validate_hook_structure(hooks)}
      _ ->
        {:error, "Invalid hooks configuration"}
    end
  end
  
  defp validate_hook_structure(hooks) do
    # Validate each hook type and structure
    hooks
  end
end
```

## 2. Matcher System Design

### Extensible Matcher Behavior

Using Elixir behaviors to create an extensible matcher system:

```elixir
defmodule RubberDuck.Hooks.Matcher do
  @callback match?(pattern :: String.t(), target :: String.t()) :: boolean()
  @callback priority() :: integer()
  
  @doc """
  Default implementation for exact string matching
  """
  def match?(pattern, target) when pattern == target, do: true
  def match?("*", _target), do: true
  def match?("", _target), do: true
  def match?(pattern, target) do
    # Check if it's a regex pattern (contains |)
    if String.contains?(pattern, "|") do
      RegexMatcher.match?(pattern, target)
    else
      false
    end
  end
end

defmodule RubberDuck.Hooks.Matchers.RegexMatcher do
  @behaviour RubberDuck.Hooks.Matcher
  
  def match?(pattern, target) do
    # Convert Claude's pipe-separated format to regex
    regex_pattern = pattern
    |> String.split("|")
    |> Enum.map(&Regex.escape/1)
    |> Enum.join("|")
    |> then(&"^(#{&1})$")
    
    case Regex.compile(regex_pattern) do
      {:ok, regex} -> Regex.match?(regex, target)
      _ -> false
    end
  end
  
  def priority(), do: 50
end
```

### Matcher Registry

A GenServer to manage and discover matchers dynamically:

```elixir
defmodule RubberDuck.Hooks.MatcherRegistry do
  use GenServer
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def register_matcher(name, module) do
    GenServer.call(__MODULE__, {:register, name, module})
  end
  
  def find_matching_hooks(event_type, tool_name, hooks_config) do
    GenServer.call(__MODULE__, {:find_matching, event_type, tool_name, hooks_config})
  end
  
  @impl true
  def handle_call({:find_matching, event_type, tool_name, hooks_config}, _from, state) do
    matching_hooks = case hooks_config[event_type] do
      nil -> []
      hook_specs -> 
        hook_specs
        |> Enum.filter(fn spec ->
          matcher = Map.get(spec, "matcher", "")
          # Only PreToolUse and PostToolUse use matchers
          if event_type in ["PreToolUse", "PostToolUse"] do
            RubberDuck.Hooks.Matcher.match?(matcher, tool_name)
          else
            true
          end
        end)
        |> Enum.flat_map(fn spec -> Map.get(spec, "hooks", []) end)
    end
    
    {:reply, matching_hooks, state}
  end
end
```

## 3. Event Bus Integration

### Project-Aware GenServer Event Bus

```elixir
defmodule RubberDuck.Hooks.EventBus do
  use GenServer
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def emit(project_id, event_name, data) do
    GenServer.cast(__MODULE__, {:emit, project_id, event_name, data})
  end
  
  def emit_sync(project_id, event_name, data) do
    GenServer.call(__MODULE__, {:emit_sync, project_id, event_name, data}, 30_000)
  end
  
  @impl true
  def handle_call({:emit_sync, project_id, event_name, data}, _from, state) do
    result = RubberDuck.Hooks.System.execute_hooks(project_id, event_name, data)
    {:reply, result, state}
  end
  
  @impl true
  def handle_cast({:emit, project_id, event_name, data}, state) do
    Task.start(fn ->
      RubberDuck.Hooks.System.execute_hooks(project_id, event_name, data)
    end)
    {:noreply, state}
  end
end
```

## 4. Hook Executor with Claude Compatibility

### Project-Aware Executor Implementation

The executor handles the actual hook execution while maintaining Claude's exact input/output format and sets the proper working directory:

```elixir
defmodule RubberDuck.Hooks.Executor do
  require Logger
  
  @timeout 60_000  # 60 second default timeout
  
  def execute_hooks(event_name, context) do
    # Get matching hooks
    hooks = RubberDuck.Hooks.MatcherRegistry.find_matching_hooks(
      event_name, 
      context.tool_name, 
      context.config
    )
    
    # Execute hooks in sequence (or parallel for independent hooks)
    Enum.reduce_while(hooks, {:ok, context}, fn hook, {:ok, acc_context} ->
      case execute_single_hook(hook, event_name, acc_context) do
        {:continue, new_context} -> {:cont, {:ok, new_context}}
        {:stop, reason} -> {:halt, {:stop, reason}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
  
  defp execute_single_hook(hook, event_name, context) do
    # Prepare input data matching Claude's format exactly
    input_data = build_hook_input(event_name, context)
    
    # Execute the command in the project directory
    timeout = Map.get(hook, "timeout", @timeout) * 1000
    command = Map.get(hook, "command", "")
    project_root = context.project_root
    
    case execute_command(command, input_data, timeout, project_root) do
      {:ok, exit_code, stdout, stderr} ->
        process_hook_result(event_name, exit_code, stdout, stderr)
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp build_hook_input(event_name, context) do
    # Base fields for all events - use project root as cwd
    base = %{
      "session_id" => context.session_id,
      "transcript_path" => context.transcript_path,
      "cwd" => context.project_root || File.cwd!(),
      "hook_event_name" => event_name,
      "project_id" => context.project_id
    }
    
    # Add event-specific fields
    case event_name do
      "PreToolUse" ->
        Map.merge(base, %{
          "tool_name" => context.tool_name,
          "tool_input" => context.tool_input
        })
        
      "PostToolUse" ->
        Map.merge(base, %{
          "tool_name" => context.tool_name,
          "tool_input" => context.tool_input,
          "tool_response" => context.tool_response
        })
        
      "UserPromptSubmit" ->
        Map.merge(base, %{
          "prompt" => context.prompt,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        })
        
      _ -> base
    end
  end
  
  defp execute_command(command, input_data, timeout, project_root) do
    json_input = Jason.encode!(input_data)
    
    # Resolve command path relative to project if it's a relative path
    resolved_command = resolve_command_path(command, project_root)
    
    task = Task.async(fn ->
      System.cmd("sh", ["-c", resolved_command], 
        input: json_input,
        stderr_to_stdout: false,
        cd: project_root,  # Execute in project directory
        env: [{"RUBBER_DUCK_PROJECT_ROOT", project_root}]
      )
    end)
    
    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {output, exit_code}} ->
        {:ok, exit_code, output, ""}
      {:ok, {output, stderr, exit_code}} ->
        {:ok, exit_code, output, stderr}
      nil ->
        {:error, :timeout}
    end
  end
  
  defp resolve_command_path(command, project_root) do
    # If the command references a file in .rubber_duck/, make it relative to project
    if String.starts_with?(command, ".rubber_duck/") or String.contains?(command, " .rubber_duck/") do
      String.replace(command, ".rubber_duck/", Path.join(project_root, ".rubber_duck/") <> "/")
    else
      command
    end
  end
  
  defp process_hook_result(event_name, exit_code, stdout, stderr) do
    case exit_code do
      0 ->
        # Try to parse JSON output
        case Jason.decode(stdout) do
          {:ok, json_output} ->
            handle_json_output(event_name, json_output)
          _ ->
            # Non-JSON output, continue normally
            {:continue, %{}}
        end
        
      2 ->
        # Blocking error - stderr is fed to system
        Logger.error("Hook blocked with error: #{stderr}")
        {:stop, stderr}
        
      _ ->
        # Non-blocking error
        Logger.warn("Hook failed with exit code #{exit_code}: #{stderr}")
        {:continue, %{}}
    end
  end
  
  defp handle_json_output(_event_name, %{"continue" => false, "stopReason" => reason}) do
    {:stop, reason}
  end
  
  defp handle_json_output("PreToolUse", json_output) do
    # Handle PreToolUse specific output
    case get_in(json_output, ["hookSpecificOutput", "permissionDecision"]) do
      "deny" -> 
        reason = get_in(json_output, ["hookSpecificOutput", "permissionDecisionReason"])
        {:stop, reason}
      _ ->
        {:continue, json_output}
    end
  end
  
  defp handle_json_output(_event_name, json_output) do
    {:continue, json_output}
  end
end
```

## 5. Integration with RubberDuck Tool System

### Project-Aware Tool System Adapter

Since the specific RubberDuck implementation wasn't found, here's a flexible adapter pattern that includes project context:

```elixir
defmodule RubberDuck.Hooks.ToolAdapter do
  @moduledoc """
  Adapter to integrate hooks with the existing RubberDuck tool system
  """
  
  defmacro __using__(opts) do
    quote do
      def before_tool_execution(project_id, tool_name, tool_input) do
        context = %{
          tool_name: tool_name,
          tool_input: tool_input,
          session_id: get_session_id(),
          transcript_path: get_transcript_path(project_id)
        }
        
        case RubberDuck.Hooks.EventBus.emit_sync(project_id, "PreToolUse", context) do
          {:ok, _} -> :continue
          {:stop, reason} -> {:stop, reason}
          {:error, error} -> {:error, error}
        end
      end
      
      def after_tool_execution(project_id, tool_name, tool_input, tool_response) do
        context = %{
          tool_name: tool_name,
          tool_input: tool_input,
          tool_response: tool_response,
          session_id: get_session_id(),
          transcript_path: get_transcript_path(project_id)
        }
        
        RubberDuck.Hooks.EventBus.emit(project_id, "PostToolUse", context)
      end
      
      defp get_transcript_path(project_id) do
        # Generate transcript path relative to project
        case RubberDuck.Workspace.get_project(project_id) do
          {:ok, project} ->
            Path.join([project.root_path, ".rubber_duck", "transcripts", 
                      "session_#{get_session_id()}.json"])
          _ ->
            nil
        end
      end
    end
  end
end
```

### Spark DSL Integration with Project Context

If RubberDuck uses Spark DSL for tool definitions, here's how to integrate with project awareness:

```elixir
defmodule RubberDuck.Tool.DSL do
  use Spark.Dsl
  
  defmacro tool(name, opts \\ [], do: block) do
    quote do
      # Original tool definition
      unquote(block)
      
      # Wrap with hooks
      defoverridable [execute: 2]
      
      def execute(project_id, input) do
        tool_name = unquote(name)
        
        # Pre-execution hook
        case RubberDuck.Hooks.ToolAdapter.before_tool_execution(project_id, tool_name, input) do
          :continue ->
            result = super(project_id, input)
            
            # Post-execution hook
            RubberDuck.Hooks.ToolAdapter.after_tool_execution(project_id, tool_name, input, result)
            
            result
            
          {:stop, reason} ->
            {:error, {:hook_blocked, reason}}
        end
      end
    end
  end
end
```

### Project Context Manager

A helper module to manage project-specific context:

```elixir
defmodule RubberDuck.Hooks.ProjectContext do
  @moduledoc """
  Manages project-specific hook context and lifecycle
  """
  
  use GenServer
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def on_project_open(project_id) do
    GenServer.cast(__MODULE__, {:project_opened, project_id})
  end
  
  def on_project_close(project_id) do
    GenServer.cast(__MODULE__, {:project_closed, project_id})
  end
  
  def get_active_projects do
    GenServer.call(__MODULE__, :get_active_projects)
  end
  
  @impl true
  def init(_) do
    {:ok, %{active_projects: MapSet.new()}}
  end
  
  @impl true
  def handle_cast({:project_opened, project_id}, state) do
    # Load hooks for this project
    RubberDuck.Hooks.System.load_project_hooks(project_id)
    
    # Watch for configuration changes
    watch_project_config(project_id)
    
    new_active = MapSet.put(state.active_projects, project_id)
    {:noreply, %{state | active_projects: new_active}}
  end
  
  @impl true
  def handle_cast({:project_closed, project_id}, state) do
    # Unload hooks for this project
    RubberDuck.Hooks.System.unload_project_hooks(project_id)
    
    # Stop watching configuration
    unwatch_project_config(project_id)
    
    new_active = MapSet.delete(state.active_projects, project_id)
    {:noreply, %{state | active_projects: new_active}}
  end
  
  defp watch_project_config(project_id) do
    case RubberDuck.Workspace.get_project(project_id) do
      {:ok, project} ->
        config_path = Path.join(project.root_path, ".rubber_duck")
        # Use FileSystem library to watch for changes
        {:ok, _pid} = FileSystem.start_link(dirs: [config_path], name: :"watcher_#{project_id}")
        FileSystem.subscribe(:"watcher_#{project_id}")
      _ ->
        :ok
    end
  end
  
  defp unwatch_project_config(project_id) do
    # Stop the file watcher for this project
    case Process.whereis(:"watcher_#{project_id}") do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end
  
  @impl true
  def handle_info({:file_event, watcher_pid, {path, _events}}, state) do
    # Reload configuration if settings files changed
    if String.ends_with?(path, "settings.json") or String.ends_with?(path, "settings.local.json") do
      # Extract project_id from watcher name
      project_id = extract_project_id_from_watcher(watcher_pid)
      RubberDuck.Hooks.System.load_project_hooks(project_id)
    end
    {:noreply, state}
  end
  
  defp extract_project_id_from_watcher(watcher_pid) do
    # Implementation to map watcher PID back to project_id
    # This would typically use a registry or ETS table
  end
end
```

## 6. Performance Optimization with ETS Cache

```elixir
defmodule RubberDuck.Hooks.Cache do
  use GenServer
  
  @table_name :hook_cache
  @ttl :timer.minutes(5)
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def get_or_compute(key, compute_fn) do
    case :ets.lookup(@table_name, key) do
      [{^key, value, expiry}] when expiry > System.monotonic_time() ->
        {:ok, value}
      _ ->
        value = compute_fn.()
        put(key, value)
        {:ok, value}
    end
  end
  
  def put(key, value) do
    expiry = System.monotonic_time() + @ttl
    :ets.insert(@table_name, {key, value, expiry})
  end
  
  @impl true
  def init(_) do
    :ets.new(@table_name, [:named_table, :public, :set, 
             read_concurrency: true, write_concurrency: true])
    schedule_cleanup()
    {:ok, %{}}
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @ttl)
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    now = System.monotonic_time()
    :ets.select_delete(@table_name, [{{:"$1", :"$2", :"$3"}, 
                                      [{:<, :"$3", now}], [true]}])
    schedule_cleanup()
    {:noreply, state}
  end
end
```

## 7. Supervision Tree Structure

```elixir
defmodule RubberDuck.Hooks.Supervisor do
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    children = [
      # Core components
      {RubberDuck.Hooks.ConfigLoader, []},
      {RubberDuck.Hooks.MatcherRegistry, []},
      {RubberDuck.Hooks.EventBus, []},
      {RubberDuck.Hooks.Cache, []},
      
      # Dynamic supervisor for hook workers
      {DynamicSupervisor, name: RubberDuck.Hooks.WorkerSupervisor,
       strategy: :one_for_one, max_restarts: 10, max_seconds: 60},
      
      # Main hooks system
      {RubberDuck.Hooks.System, []}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

## 8. Directory Structure

Following Claude's conventions adapted for RubberDuck with project-specific hooks:

```
# Project directory structure
my_project/
├── .rubber_duck/
│   ├── settings.json           # Project-specific hooks (version controlled)
│   ├── settings.local.json     # Local overrides (gitignored)
│   ├── hooks/                  # Project-specific hook scripts
│   │   ├── format_code.exs
│   │   ├── run_tests.sh
│   │   └── check_types.py
│   └── transcripts/            # Session transcripts
│       └── session_*.json

# Global user directory
~/.rubber_duck/
├── settings.json               # Global hooks for all projects
└── hooks/                      # Global hook scripts
    ├── security_check.sh
    └── license_check.py
```

### Gitignore recommendations

Add to your project's `.gitignore`:

```
.rubber_duck/settings.local.json
.rubber_duck/transcripts/
```

## 9. Example Hook Configurations

### Project-specific hooks in `my_project/.rubber_duck/settings.json`

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": ".rubber_duck/hooks/format_code.exs",
            "timeout": 30
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Compile",
        "hooks": [
          {
            "type": "command",
            "command": "mix test --cover"
          }
        ]
      }
    ]
  }
}
```

### Local overrides in `my_project/.rubber_duck/settings.local.json`

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": ".rubber_duck/hooks/custom_linter.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

### Global hooks in `~/.rubber_duck/settings.json`

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.rubber_duck/hooks/security_check.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "~/.rubber_duck/hooks/log_activity.py"
          }
        ]
      }
    ]
  }
}
```

### Example project hook script `.rubber_duck/hooks/format_code.exs`

```elixir
#!/usr/bin/env elixir

# Read input from stdin
input = IO.read(:stdio, :all)
{:ok, data} = Jason.decode(input)

# Format based on file extension
case Path.extname(data["tool_input"]["path"] || "") do
  ".ex" -> System.cmd("mix", ["format", data["tool_input"]["path"]])
  ".exs" -> System.cmd("mix", ["format", data["tool_input"]["path"]])
  ".js" -> System.cmd("prettier", ["--write", data["tool_input"]["path"]])
  _ -> :ok
end

# Return success
IO.puts(Jason.encode!(%{continue: true}))
```

## 10. Security Considerations

Implementing Claude's security model in Elixir with project isolation:

```elixir
defmodule RubberDuck.Hooks.Security do
  @blocked_commands ~w(rm rf sudo chmod)
  @sensitive_paths ~w(.env .git secrets)
  
  def validate_hook_command(command, project_root) do
    cond do
      contains_blocked_command?(command) ->
        {:error, "Command contains blocked operations"}
      
      contains_sensitive_path?(command) ->
        {:error, "Command accesses sensitive paths"}
      
      escapes_project_root?(command, project_root) ->
        {:error, "Command attempts to access files outside project"}
        
      true ->
        :ok
    end
  end
  
  defp contains_blocked_command?(command) do
    Enum.any?(@blocked_commands, &String.contains?(command, &1))
  end
  
  defp contains_sensitive_path?(command) do
    Enum.any?(@sensitive_paths, &String.contains?(command, &1))
  end
  
  defp escapes_project_root?(command, project_root) do
    # Check for path traversal attempts
    String.contains?(command, "../") or 
    String.contains?(command, "..\\") or
    String.contains?(command, "~") and not String.starts_with?(command, "~/.rubber_duck/")
  end
  
  @doc """
  Validates that a hook script file is safe to execute
  """
  def validate_hook_file(file_path, project_root) do
    cond do
      # Must be within project or global hooks directory
      not within_allowed_directory?(file_path, project_root) ->
        {:error, "Hook file must be in .rubber_duck/hooks directory"}
      
      # Check file permissions (should not be world-writable)
      world_writable?(file_path) ->
        {:error, "Hook file has unsafe permissions"}
        
      true ->
        :ok
    end
  end
  
  defp within_allowed_directory?(file_path, project_root) do
    normalized = Path.expand(file_path)
    
    # Allow project hooks
    String.starts_with?(normalized, Path.join(project_root, ".rubber_duck/hooks/")) or
    # Allow global hooks
    String.starts_with?(normalized, Path.expand("~/.rubber_duck/hooks/"))
  end
  
  defp world_writable?(file_path) do
    case File.stat(file_path) do
      {:ok, %{mode: mode}} ->
        # Check if world-writable bit is set
        (mode &&& 0o002) != 0
      _ ->
        true  # Assume unsafe if we can't check
    end
  end
end
```

### Project Isolation

The hooks system enforces project boundaries:

1. **Working Directory**: Hooks always execute with the project root as the working directory
2. **Path Resolution**: Relative paths in hooks are resolved relative to the project root
3. **Environment Variables**: `RUBBER_DUCK_PROJECT_ROOT` is set for hook scripts
4. **File Access**: Security checks prevent accessing files outside the project (except for global hooks)

### Hook Script Security

Best practices for hook scripts:

```bash
#!/bin/bash
# Example secure hook script

# Use project root from environment
PROJECT_ROOT="${RUBBER_DUCK_PROJECT_ROOT:-$(pwd)}"

# Validate we're in a project directory
if [ ! -f "$PROJECT_ROOT/.rubber_duck/settings.json" ]; then
    echo "Not in a valid RubberDuck project" >&2
    exit 1
fi

# Only operate on files within the project
find "$PROJECT_ROOT" -name "*.ex" -type f | while read -r file; do
    # Process only if file is within project bounds
    realpath "$file" | grep -q "^$PROJECT_ROOT/" && mix format "$file"
done
```

## Implementation Recommendations

### Hook Loading Order and Precedence

The hooks system loads configurations in the following order (later ones override earlier ones):

1. **Global hooks** (`~/.rubber_duck/settings.json`) - Applied to all projects
2. **Project hooks** (`<project>/.rubber_duck/settings.json`) - Project-specific, version controlled
3. **Local hooks** (`<project>/.rubber_duck/settings.local.json`) - Personal overrides, gitignored

This allows for:

- Organization-wide standards in project hooks
- Personal productivity tools in global hooks  
- Temporary debugging hooks in local settings

### Phase 1: Core Infrastructure

1. Implement the basic GenServer architecture with project awareness
2. Create the configuration loader with JSON parsing and merging
3. Set up the matcher system with exact string matching
4. Build the event bus for hook execution

### Phase 2: Claude Compatibility

1. Implement all hook event types
2. Ensure exact JSON input/output format matching
3. Handle all exit codes and control flow patterns
4. Add security validations

### Phase 3: Tool System Integration

1. Create adapters for existing RubberDuck tools
2. Implement Spark DSL macros if applicable
3. Add performance monitoring and caching
4. Set up the supervision tree

### Phase 4: Advanced Features

1. Add more sophisticated matchers (glob patterns, MCP tool names)
2. Implement parallel hook execution where safe
3. Add hook composition and dependencies
4. Create development tools and debugging aids

### Phase 5: Project Management

1. Implement automatic hook loading on project open
2. Add file watching for configuration changes
3. Create project context lifecycle management
4. Build multi-project support]

This design provides a robust, extensible hooks system that maintains exact compatibility with Claude's JSON format while leveraging Elixir's strengths in concurrency, fault tolerance, and pattern matching. The modular architecture allows for gradual implementation and easy integration with any existing RubberDuck tool system.

# RubberDuck Tool Inventory

This document lists all 26 tools designed for use in the RubberDuck agentic coding assistant system. Each tool integrates with the Jido workflow and follows Elixir best practices.

---

## 1. **TaskDecomposer**

**Description:** Decomposes a high-level specification into an ordered list of implementation tasks.

---

## 2. **CodeGenerator**

**Description:** Generates Elixir code from a given description or signature.

---

## 3. **CodeRefactorer**

**Description:** Applies structural or semantic transformations to existing code based on an instruction.

---

## 4. **CodeExplainer**

**Description:** Produces a human-readable explanation or docstring for the provided Elixir code.

---

## 5. **RepoSearch**

**Description:** Searches project files by keyword, symbol, or pattern.

---

## 6. **TestGenerator**

**Description:** Generates unit or property-based tests for a given function or behavior.

---

## 7. **TestRunner**

**Description:** Executes tests and returns results including logs, failures, and coverage.

---

## 8. **DebugAssistant**

**Description:** Analyzes stack traces or runtime errors and suggests causes or fixes.

---

## 9. **DependencyInspector**

**Description:** Detects internal and external dependencies used in code.

---

## 10. **DocFetcher**

**Description:** Retrieves documentation from online sources such as HexDocs or GitHub.

---

## 11. **CodeFormatter**

**Description:** Formats Elixir code using standard formatter rules.

---

## 12. **SemanticEmbedder**

**Description:** Produces vector embeddings of code for similarity search.

---

## 13. **TestSummarizer**

**Description:** Summarizes test results and identifies key failures or gaps.

---

## 14. **TodoExtractor**

**Description:** Scans code for TODO, FIXME, and other deferred work comments.

---

## 15. **SignalEmitter**

**Description:** Emits a Jido signal to trigger workflows or agent communication.

---

## 16. **FunctionSignatureExtractor**

**Description:** Extracts function names, arities, and documentation from code.

---

## 17. **CodeComparer**

**Description:** Compares two code versions and highlights semantic differences.

---

## 18. **CodeNavigator**

**Description:** Locates symbols within a codebase and maps them to file and line number.

---

## 19. **CodeSummarizer**

**Description:** Summarizes the responsibilities and purpose of a file or module.

---

## 20. **PromptOptimizer**

**Description:** Rewrites prompts for clarity, efficiency, or better LLM outcomes.

---

## 21. **ChangelogGenerator**

**Description:** Generates changelog entries from diffs or commit summaries.

---

## 22. **ProjectSummarizer**

**Description:** Provides a high-level description of the structure and components of a project.

---

## 23. **RegexExtractor**

**Description:** Extracts patterns from code using regex queries.

---

## 24. **TypeInferrer**

**Description:** Infers types from function bodies and suggests `@spec` declarations.

---

## 25. **FunctionMover**

**Description:** Moves functions between files or modules and updates references.

---

## 26. **CredoAnalyzer**

**Description:** Runs Credo static analysis to check for code quality issues.

---
