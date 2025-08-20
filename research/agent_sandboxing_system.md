# Secure authorization systems for Rubber Duck agentic coding assistant

Based on comprehensive research of the Elixir ecosystem, Ash framework capabilities, and agent security patterns, here's a complete implementation guide for building secure authorization systems for your Rubber Duck agentic coding assistant.

## Architecture context and security foundation

The Rubber Duck project leverages **Jido** as its autonomous agent framework and **Ash** for resource management and authorization. Jido provides core agent capabilities through Actions (discrete work units), Agents (stateful entities), Sensors (monitoring), and Signals (communication), all built on OTP's fault-tolerant supervision trees. Ash brings declarative resource modeling with built-in policy-based authorization that integrates seamlessly with Phoenix and Ecto.

The security implementation must address multiple layers: agent execution sandboxing, tool access restrictions, external service integration, and multi-level permission configuration. The system requires both preventive controls (authorization policies) and detective controls (audit logging and anomaly detection).

## Core authorization implementation with Ash framework

### Policy-based resource authorization

Ash's `Ash.Policy.Authorizer` provides the foundation for implementing granular permissions. Here's how to model agent permissions as first-class resources:

```elixir
defmodule RubberDuck.Security.AgentPermission do
  use Ash.Resource, 
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id
    attribute :agent_id, :string, allow_nil?: false
    attribute :action, :string, allow_nil?: false # "execute_cli", "read_file", "git_push"
    attribute :resource_pattern, :string # "/project/src/**", "github.com/org/*"
    attribute :constraints, :map # {"max_daily_uses": 100, "allowed_hours": [9, 17]}
    attribute :expires_at, :utc_datetime
    timestamps()
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(agent_id == ^actor(:id))
    end
    
    policy action_type([:create, :update, :delete]) do
      authorize_if actor_attribute_equals(:role, :security_admin)
    end
  end
end
```

The authorization system should implement **capability-based security** where agents must explicitly possess capabilities to perform actions. This prevents privilege escalation and enables fine-grained control:

```elixir
defmodule RubberDuck.Security.CapabilityCheck do
  use Ash.Policy.FilterCheck

  def filter(actor, %{subject: subject}, _opts) do
    expr(
      exists(permissions, 
        agent_id == ^actor.id and
        action == ^subject.action.name and
        (is_nil(expires_at) or expires_at > ^DateTime.utc_now())
      )
    )
  end
end
```

### Multi-level permission hierarchy

The system needs three permission levels that cascade and can override each other:

**User-level permissions** define what capabilities a user can grant to their agents:
```elixir
defmodule RubberDuck.Accounts.UserPermissionSet do
  use Ash.Resource

  attributes do
    attribute :max_agents, :integer, default: 5
    attribute :allowed_tools, {:array, :string}, default: ["git", "file_system", "web_search"]
    attribute :resource_quotas, :map # CPU, memory, API call limits
  end
end
```

**Project-level permissions** scope agent capabilities to specific projects:
```elixir
defmodule RubberDuck.Projects.ProjectAgentPolicy do
  use Ash.Resource
  
  multitenancy do
    strategy :context
  end

  attributes do
    attribute :project_id, :uuid, allow_nil?: false
    attribute :allowed_paths, {:array, :string} # Paths agents can access
    attribute :forbidden_patterns, {:array, :string} # e.g., ["*.env", "**/.git/**"]
    attribute :tool_restrictions, :map
  end
end
```

**Session-based overrides** enable temporary permission elevation with audit trails:
```elixir
defmodule RubberDuck.Security.SessionOverride do
  use Ash.Resource

  attributes do
    attribute :session_id, :uuid
    attribute :elevated_permissions, {:array, :string}
    attribute :justification, :text, allow_nil?: false
    attribute :approved_by, :uuid
    attribute :expires_at, :utc_datetime, allow_nil?: false
  end

  actions do
    create :request_elevation do
      validate {RubberDuck.Validations.MaxDuration, max_hours: 4}
      change after_action(&audit_elevation_request/3)
    end
  end
end
```

## Process isolation and sandboxing with OTP

### Isolated agent execution environments

Each agent should run in an isolated OTP process with strict resource limits and capability restrictions:

```elixir
defmodule RubberDuck.Agents.IsolatedRunner do
  use GenServer

  def start_link(agent_config) do
    GenServer.start_link(__MODULE__, agent_config,
      spawn_opt: [
        max_heap_size: %{
          size: agent_config.memory_limit || 50_000_000,
          kill: true,
          error_logger: true
        },
        message_queue_len: 1000,
        priority: :low
      ]
    )
  end

  def init(agent_config) do
    # Set process dictionary for security context
    Process.put(:agent_id, agent_config.id)
    Process.put(:permissions, load_permissions(agent_config))
    
    # Schedule periodic resource checks
    :timer.send_interval(5_000, self(), :check_resources)
    
    {:ok, %{
      agent_id: agent_config.id,
      sandbox: create_sandbox(agent_config),
      start_time: :erlang.monotonic_time(:millisecond)
    }}
  end

  defp create_sandbox(config) do
    %{
      allowed_modules: config.allowed_modules || [],
      allowed_functions: build_function_whitelist(config),
      filesystem_root: config.filesystem_root,
      network_restrictions: config.network_restrictions
    }
  end
end
```

### AST-based code sandboxing for dynamic execution

When agents need to execute dynamic code, implement AST-level sandboxing to prevent malicious operations:

```elixir
defmodule RubberDuck.Security.CodeSandbox do
  @allowed_modules %{
    String => [:trim, :downcase, :upcase, :split, :replace],
    Map => [:get, :put, :delete, :keys, :values],
    Enum => [:map, :filter, :reduce, :find, :count]
  }

  def evaluate_sandboxed(code, context, agent_permissions) do
    with {:ok, ast} <- Code.string_to_quoted(code),
         :ok <- validate_ast_safety(ast, agent_permissions),
         :ok <- check_resource_usage(),
         {result, _} <- Code.eval_quoted(ast, context) do
      {:ok, result}
    else
      {:error, :forbidden_operation} = error -> 
        log_security_violation(code, agent_permissions)
        error
      error -> error
    end
  end

  defp validate_ast_safety(ast, permissions) do
    case safe_traverse(ast, permissions) do
      :ok -> :ok
      {:error, {:forbidden_call, module, function}} ->
        {:error, :forbidden_operation}
    end
  end
end
```

## Secure tool integration patterns

### OS CLI command restrictions

Implement a whitelist-based approach for CLI commands with argument validation:

```elixir
defmodule RubberDuck.Tools.SecureCLI do
  @allowed_commands %{
    "git" => ["status", "diff", "log", "branch", "checkout"],
    "npm" => ["install", "test", "run"],
    "mix" => ["deps.get", "compile", "test", "format"]
  }

  def execute_command(agent_id, command, args) do
    with :ok <- validate_command(command, args),
         :ok <- check_rate_limit(agent_id, command),
         :ok <- verify_filesystem_scope(command, args),
         {:ok, output} <- run_in_sandbox(command, args) do
      audit_command_execution(agent_id, command, args, :success)
      {:ok, output}
    else
      error ->
        audit_command_execution(agent_id, command, args, error)
        error
    end
  end

  defp run_in_sandbox(command, args) do
    # Use systemd-run or firejail for additional isolation
    System.cmd("systemd-run", [
      "--scope",
      "--property=MemoryMax=500M",
      "--property=CPUQuota=50%",
      "--setenv=PATH=/usr/bin:/bin",
      command | args
    ], stderr_to_stdout: true, cd: get_sandbox_directory())
  end
end
```

### GitHub and repository access control

Secure Git operations require proper SSH key management and token rotation:

```elixir
defmodule RubberDuck.Tools.GitHubIntegration do
  use Guardian, otp_app: :rubber_duck

  def create_agent_github_token(agent_id, scopes) do
    allowed_scopes = filter_allowed_scopes(agent_id, scopes)
    
    token_config = %{
      "agent_id" => agent_id,
      "scopes" => allowed_scopes,
      "expires_at" => DateTime.add(DateTime.utc_now(), 3600, :second)
    }
    
    {:ok, token, _claims} = encode_and_sign(token_config, %{}, 
      token_type: "agent_github_access",
      ttl: {1, :hour}
    )
    
    store_token_securely(agent_id, token)
    schedule_token_rotation(agent_id)
    
    {:ok, token}
  end

  defp filter_allowed_scopes(agent_id, requested_scopes) do
    agent_permissions = get_agent_permissions(agent_id)
    
    Enum.filter(requested_scopes, fn scope ->
      scope in agent_permissions.github_scopes
    end)
  end
end
```

## Runtime security monitoring and enforcement

### Dynamic permission evaluation with caching

Implement efficient runtime permission checks with intelligent caching:

```elixir
defmodule RubberDuck.Security.PermissionEvaluator do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    # Initialize ETS cache for permission lookups
    :ets.new(:permission_cache, [:set, :named_table, :public])
    {:ok, %{}}
  end

  def evaluate_permission(agent_id, action, resource) do
    cache_key = {agent_id, action, resource}
    
    case :ets.lookup(:permission_cache, cache_key) do
      [{_, result, timestamp}] when timestamp > expire_time() ->
        {:cached, result}
      _ ->
        result = evaluate_fresh(agent_id, action, resource)
        :ets.insert(:permission_cache, {cache_key, result, :erlang.monotonic_time()})
        {:evaluated, result}
    end
  end

  defp evaluate_fresh(agent_id, action, resource) do
    with {:ok, permissions} <- load_permission_chain(agent_id),
         :ok <- check_user_level(permissions.user, action),
         :ok <- check_project_level(permissions.project, resource),
         :ok <- apply_session_overrides(permissions.session),
         :ok <- verify_constraints(permissions.constraints) do
      :authorized
    else
      {:error, reason} -> {:denied, reason}
    end
  end
end
```

### Comprehensive audit logging system

Track all security-relevant events for compliance and forensics:

```elixir
defmodule RubberDuck.Security.AuditLogger do
  use GenServer
  require Logger

  def log_authorization_event(event_type, metadata) do
    enriched_event = metadata
    |> Map.put(:timestamp, DateTime.utc_now())
    |> Map.put(:event_id, Ecto.UUID.generate())
    |> Map.put(:event_type, event_type)
    
    # Log to multiple destinations
    Logger.info("Security event", enriched_event)
    
    # Store in database for long-term retention
    %RubberDuck.Audit.SecurityEvent{}
    |> RubberDuck.Audit.SecurityEvent.changeset(enriched_event)
    |> RubberDuck.Repo.insert!()
    
    # Emit telemetry for real-time monitoring
    :telemetry.execute(
      [:rubber_duck, :security, event_type],
      %{count: 1},
      enriched_event
    )
  end
end
```

### Privilege escalation detection

Monitor for suspicious patterns that indicate attempted privilege escalation:

```elixir
defmodule RubberDuck.Security.EscalationDetector do
  @suspicious_patterns [
    {:rapid_permission_requests, 5, :minute},
    {:failed_authorizations, 10, :minute},
    {:unusual_resource_access, 3, :hour}
  ]

  def analyze_agent_behavior(agent_id) do
    recent_events = get_recent_events(agent_id, :timer.hours(1))
    
    anomalies = Enum.flat_map(@suspicious_patterns, fn {pattern, threshold, window} ->
      case count_pattern_matches(recent_events, pattern, window) do
        count when count > threshold ->
          [{pattern, count, threshold}]
        _ -> []
      end
    end)
    
    if length(anomalies) > 0 do
      trigger_security_alert(agent_id, anomalies)
      apply_automatic_restrictions(agent_id)
    end
  end

  defp apply_automatic_restrictions(agent_id) do
    # Temporarily restrict agent permissions
    RubberDuck.Security.quarantine_agent(agent_id, duration: :timer.minutes(30))
    
    # Require manual review for further actions
    RubberDuck.Security.flag_for_review(agent_id, priority: :high)
  end
end
```

## External service security integration

### OAuth2 and JWT token management

Implement secure token handling for GitHub, GitLab, and other services:

```elixir
defmodule RubberDuck.Security.TokenManager do
  use GenServer

  @token_rotation_interval :timer.hours(6)

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    schedule_rotation()
    {:ok, %{tokens: %{}, rotation_schedule: %{}}}
  end

  def handle_info(:rotate_tokens, state) do
    rotated_tokens = Enum.map(state.tokens, fn {service, token_info} ->
      case rotate_service_token(service, token_info) do
        {:ok, new_token} ->
          store_in_vault(service, new_token)
          notify_agents_of_rotation(service)
          {service, new_token}
        {:error, reason} ->
          Logger.error("Failed to rotate token for #{service}: #{inspect(reason)}")
          {service, token_info}
      end
    end)
    
    schedule_rotation()
    {:noreply, %{state | tokens: Map.new(rotated_tokens)}}
  end

  defp store_in_vault(service, token) do
    Vaultex.Client.write(
      "secret/rubber_duck/tokens/#{service}",
      %{"token" => token, "rotated_at" => DateTime.utc_now()},
      :app_role,
      %{role_id: System.get_env("VAULT_ROLE_ID")}
    )
  end
end
```

### Secure credential storage with HashiCorp Vault

Integrate Vault for centralized secrets management:

```elixir
defmodule RubberDuck.Security.VaultIntegration do
  @behaviour Config.Provider

  def init(path), do: path

  def load(config, vault_path) do
    secrets = fetch_secrets_from_vault(vault_path)
    
    Config.Reader.merge(config, [
      rubber_duck: [
        api_tokens: secrets["api_tokens"],
        ssh_keys: secrets["ssh_keys"],
        encryption_keys: secrets["encryption_keys"]
      ]
    ])
  end

  defp fetch_secrets_from_vault(path) do
    case Vaultex.Client.read(path, :kubernetes, get_k8s_auth()) do
      {:ok, secrets} -> secrets
      {:error, reason} ->
        Logger.error("Failed to fetch secrets: #{inspect(reason)}")
        raise "Vault initialization failed"
    end
  end
end
```

## Implementation recommendations and best practices

### Deployment strategy

1. **Start with core authorization**: Implement Ash policies and basic agent isolation first
2. **Add sandboxing progressively**: Begin with simple command whitelisting, then add AST-based sandboxing
3. **Layer security controls**: Combine preventive (authorization) and detective (monitoring) controls
4. **Enable comprehensive logging**: Audit everything from day one for security analysis

### Performance optimization

The authorization system should maintain sub-millisecond latency through:
- **Permission caching** with TTL-based invalidation
- **Filter-based policies** that translate to database queries
- **Preloaded permission sets** for active agents
- **Async audit logging** to avoid blocking operations

### Security monitoring priorities

Focus monitoring on these critical areas:
- **Privilege escalation attempts** (rapid permission changes, unusual access patterns)
- **Resource abuse** (CPU, memory, API quota violations)  
- **External service interactions** (Git operations, API calls)
- **Failed authorization attempts** (potential reconnaissance)

### Integration with Jido agents

Wrap Jido agents with security middleware that enforces permissions before action execution:

```elixir
defmodule RubberDuck.Agents.SecureJidoAgent do
  use Jido.Agent

  def handle_signal(signal, state) do
    with :ok <- authorize_signal(signal, state),
         :ok <- check_rate_limits(state.agent_id),
         {:ok, result} <- super(signal, state) do
      audit_successful_action(signal, state, result)
      {:ok, result}
    else
      {:error, :unauthorized} = error ->
        audit_authorization_failure(signal, state)
        error
    end
  end
end
```

This comprehensive authorization system provides defense-in-depth security while maintaining the flexibility needed for an agentic coding assistant. The combination of Ash's declarative policies, OTP's process isolation, and careful integration with external services creates a robust security foundation that can evolve with your project's needs.
