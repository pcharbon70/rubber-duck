# Comprehensive Prompt Management System Design for Rubber Duck

## Executive summary and architecture overview

This design presents a three-tier prompt management system for the Rubber Duck agentic coding assistant, built on Elixir with the Ash framework for persistence and Jido library for agent orchestration. The system implements **hierarchical prompt composition** with system, project, and user levels, ensuring secure, performant, and multi-tenant prompt management. The architecture emphasizes real-time collaboration, version control, and seamless integration with existing LLM orchestration infrastructure.

The core innovation lies in combining Ash's powerful multi-tenancy capabilities with Jido's agent system to create a dynamic, context-aware prompt management solution that scales from single developers to enterprise teams while maintaining sub-50ms prompt resolution times through intelligent caching strategies.

## Three-tier prompt architecture design

The prompt management system implements a hierarchical three-tier architecture where each level serves a distinct purpose in the prompt composition pipeline. **System prompts** act as the foundational layer, providing immutable base instructions that define the agent's core capabilities, safety constraints, and behavioral boundaries. These prompts are versioned, admin-editable, and cached globally with a default fallback ensuring the system never operates without fundamental instructions.

**Project prompts** form the customization layer, allowing teams to inject domain-specific knowledge, coding standards, and project conventions without modifying system-level behavior. These optional prompts inherit from system prompts through Ash relationships, enabling sophisticated override patterns while maintaining security boundaries through row-level policies.

**User prompts** represent the dynamic interaction layer, incorporating session context, user preferences, and runtime variables. The composition strategy uses a deterministic injection order (System → Project → User) with clear delimiters preventing prompt injection attacks. Each tier maintains its own caching strategy: system prompts use global ETS tables with 24-hour TTL, project prompts employ tenant-scoped caching with 1-hour TTL, and user prompts utilize session-based in-memory storage.

```elixir
defmodule RubberDuck.PromptManagement.CompositionEngine do
  def compose_full_prompt(tenant_id, user_id, user_input) do
    system_prompt = get_system_prompt()
    project_prompt = get_project_prompt(tenant_id)
    user_context = get_user_context(user_id)
    
    [
      {"system", system_prompt},
      {"project", project_prompt},
      {"user", "#{user_context}\n\n#{user_input}"}
    ]
    |> Enum.reject(fn {_, content} -> is_nil(content) end)
    |> format_for_llm()
  end
  
  defp format_for_llm(prompt_parts) do
    prompt_parts
    |> Enum.map(fn {role, content} -> 
      "<#{role}_context>\n#{content}\n</#{role}_context>"
    end)
    |> Enum.join("\n\n")
  end
end
```

## Data models using Ash framework conventions

### Core Ash Resources

The data model leverages Ash's resource-oriented architecture with sophisticated multi-tenancy support. The **Prompt resource** serves as the central entity, implementing versioning through an append-only pattern where updates create new versions rather than modifying existing records.

```elixir
defmodule RubberDuck.PromptManagement.Resources.Prompt do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: RubberDuck.PromptManagement,
    extensions: [AshAuditLog, AshStateMachine]

  postgres do
    table "prompts"
    repo RubberDuck.Repo
    
    migration_types content: :text
    
    custom_indexes do
      index [:tenant_id, :name, :prompt_level], unique: true, where: "is_active = true"
      index [:parent_id], where: "parent_id IS NOT NULL"
    end
  end

  multitenancy do
    strategy :attribute
    attribute :tenant_id
    global? false
  end

  attributes do
    uuid_primary_key :id
    
    attribute :name, :string do
      allow_nil? false
      constraints max_length: 255, 
                  format: ~r/^[a-z0-9_]+$/
    end
    
    attribute :content, :string do
      allow_nil? false
      constraints max_length: 32768  # ~8k tokens
    end
    
    attribute :prompt_level, :atom do
      constraints one_of: [:system, :project, :user]
      default :project
    end
    
    attribute :version, :integer, default: 1
    attribute :is_active, :boolean, default: true
    attribute :is_protected, :boolean, default: false
    
    attribute :metadata, :map, default: %{}
    attribute :variables, {:array, :string}, default: []
    attribute :token_count, :integer
    
    attribute :tenant_id, :uuid, allow_nil?: true  # Null for system prompts
    attribute :parent_id, :uuid
    attribute :created_by_id, :uuid
    attribute :approved_by_id, :uuid
    
    timestamps()
  end

  relationships do
    belongs_to :tenant, RubberDuck.Tenants.Tenant
    belongs_to :parent, __MODULE__, source_attribute: :parent_id
    belongs_to :created_by, RubberDuck.Users.User
    belongs_to :approved_by, RubberDuck.Users.User
    
    has_many :children, __MODULE__, destination_attribute: :parent_id
    has_many :versions, RubberDuck.PromptManagement.Resources.PromptVersion
    has_many :usages, RubberDuck.Analytics.PromptUsage
  end

  state_machine do
    initial_states [:draft]
    default_initial_state :draft
    
    state :draft
    state :pending_review
    state :approved
    state :archived
    
    transition :submit_for_review, from: :draft, to: :pending_review
    transition :approve, from: :pending_review, to: :approved
    transition :reject, from: :pending_review, to: :draft
    transition :archive, from: [:draft, :approved], to: :archived
  end

  actions do
    defaults [:read]
    
    create :create do
      primary? true
      accept [:name, :content, :prompt_level, :metadata, :variables, :parent_id]
      
      change set_attribute(:version, 1)
      change RubberDuck.Changes.CalculateTokenCount
      change RubberDuck.Changes.ValidatePromptSecurity
      
      change fn changeset, _context ->
        if changeset.attributes.prompt_level == :system do
          Ash.Changeset.force_change_attribute(changeset, :tenant_id, nil)
        else
          changeset
        end
      end
    end
    
    update :update do
      primary? true
      accept [:content, :metadata, :variables, :is_active]
      
      change increment(:version)
      change RubberDuck.Changes.CreateVersionSnapshot
      change RubberDuck.Changes.InvalidateCache
    end
    
    read :hierarchical_lookup do
      argument :name, :string, allow_nil?: false
      argument :tenant_id, :uuid
      
      prepare build(
        filter: expr(
          name == ^arg(:name) and 
          (tenant_id == ^arg(:tenant_id) or is_nil(tenant_id)) and
          is_active == true
        ),
        sort: [prompt_level: :asc],
        limit: 1
      )
    end
  end

  policies do
    policy action(:read) do
      authorize_if expr(prompt_level == :system)
      authorize_if relates_to_actor_via(:tenant)
    end
    
    policy action([:create, :update]) do
      authorize_if expr(prompt_level == :system and ^actor(:role) == :admin)
      authorize_if expr(prompt_level == :project and ^actor(:role) in [:admin, :owner])
      authorize_if expr(prompt_level == :user and created_by_id == ^actor(:id))
    end
    
    policy action(:destroy) do
      forbid_if expr(is_protected == true)
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  code_interface do
    define :get_by_name, args: [:name]
    define :create_prompt, args: [:name, :content, :prompt_level]
    define :update_content, args: [:content]
  end
end
```

### Database Schema

The PostgreSQL schema implements a sophisticated versioning and audit system with optimized indexes for hierarchical queries:

```sql
-- Main prompts table
CREATE TABLE prompts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  content TEXT NOT NULL,
  prompt_level VARCHAR(20) NOT NULL CHECK (prompt_level IN ('system', 'project', 'user')),
  version INTEGER DEFAULT 1,
  is_active BOOLEAN DEFAULT true,
  is_protected BOOLEAN DEFAULT false,
  metadata JSONB DEFAULT '{}',
  variables TEXT[] DEFAULT '{}',
  token_count INTEGER,
  tenant_id UUID REFERENCES tenants(id),
  parent_id UUID REFERENCES prompts(id),
  created_by_id UUID REFERENCES users(id),
  approved_by_id UUID REFERENCES users(id),
  state VARCHAR(50) DEFAULT 'draft',
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Versioning table
CREATE TABLE prompt_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  prompt_id UUID NOT NULL REFERENCES prompts(id) ON DELETE CASCADE,
  version_number INTEGER NOT NULL,
  content TEXT NOT NULL,
  metadata JSONB,
  token_count INTEGER,
  created_by_id UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(prompt_id, version_number)
);

-- Usage tracking for analytics
CREATE TABLE prompt_usages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  prompt_id UUID NOT NULL REFERENCES prompts(id),
  tenant_id UUID REFERENCES tenants(id),
  user_id UUID REFERENCES users(id),
  session_id UUID,
  tokens_used INTEGER,
  response_time_ms INTEGER,
  model_name VARCHAR(100),
  success BOOLEAN,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Optimized indexes
CREATE INDEX idx_prompts_lookup ON prompts(tenant_id, name, prompt_level) 
  WHERE is_active = true;
CREATE INDEX idx_prompts_hierarchy ON prompts(parent_id) 
  WHERE parent_id IS NOT NULL;
CREATE INDEX idx_versions_prompt ON prompt_versions(prompt_id, version_number DESC);
CREATE INDEX idx_usage_analytics ON prompt_usages(tenant_id, created_at DESC);

-- Row-level security
ALTER TABLE prompts ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON prompts
  FOR ALL
  USING (tenant_id = current_setting('app.current_tenant_id')::uuid 
         OR prompt_level = 'system');
```

## Integration with LLM orchestration and Jido agents

The integration layer bridges the prompt management system with Jido's agent orchestration through a sophisticated workflow pipeline. The **PromptOrchestrator** agent coordinates prompt retrieval, composition, and injection into the LLM request flow:

```elixir
defmodule RubberDuck.Agents.PromptOrchestrator do
  use Jido.Agent,
    name: "prompt_orchestrator",
    description: "Manages prompt composition and LLM request orchestration",
    actions: [
      RubberDuck.Actions.RetrieveSystemPrompt,
      RubberDuck.Actions.RetrieveProjectPrompt,
      RubberDuck.Actions.ComposePrompt,
      RubberDuck.Actions.ValidateTokenLimit,
      RubberDuck.Actions.SendToLLM
    ],
    schema: [
      tenant_id: [type: :string, required: true],
      user_id: [type: :string, required: true],
      max_tokens: [type: :integer, default: 4096],
      model: [type: :string, default: "gpt-4"],
      temperature: [type: :float, default: 0.7]
    ]

  def orchestrate_request(params) do
    with {:ok, prompts} <- retrieve_hierarchical_prompts(params),
         {:ok, composed} <- compose_full_prompt(prompts, params.user_input),
         {:ok, validated} <- validate_and_optimize(composed, params.max_tokens),
         {:ok, response} <- send_to_llm(validated, params) do
      
      track_usage(prompts, response, params)
      {:ok, response}
    end
  end

  defp retrieve_hierarchical_prompts(params) do
    Jido.Workflow.Parallel.run([
      {RubberDuck.Actions.RetrieveSystemPrompt, []},
      {RubberDuck.Actions.RetrieveProjectPrompt, [tenant_id: params.tenant_id]},
      {RubberDuck.Actions.RetrieveUserContext, [user_id: params.user_id]}
    ], timeout: 500)
  end

  defp compose_full_prompt(prompts, user_input) do
    RubberDuck.Actions.ComposePrompt.run(%{
      system_prompt: prompts.system,
      project_prompt: prompts.project,
      user_context: prompts.user_context,
      user_input: user_input,
      injection_strategy: :hierarchical
    })
  end
end
```

The system integrates with Phase 2's LLM orchestration through event-driven patterns, where prompt updates trigger cache invalidation and hot-reload mechanisms. The **Runic workflow integration** (Phase 2a) enables declarative prompt chains where complex multi-step agent interactions reference named prompts:

```elixir
defmodule RubberDuck.Workflows.CodeRefactoring do
  use Runic.Workflow

  workflow :refactor_with_context do
    step :analyze, prompt: "code_analysis_prompt" do
      input :code
      output :analysis
    end
    
    step :suggest, prompt: "refactoring_suggestion_prompt" do
      input :analysis
      output :suggestions
    end
    
    step :implement, prompt: "code_generation_prompt" do
      input :suggestions, :original_code
      output :refactored_code
    end
  end
end
```

## Security implementation from Phase 8

Security measures implement defense-in-depth with multiple layers protecting against prompt injection, data leakage, and unauthorized access. The **prompt injection prevention** system uses a combination of static analysis, semantic filtering, and runtime validation:

```elixir
defmodule RubberDuck.Security.PromptValidator do
  @injection_patterns [
    ~r/ignore\s+previous\s+instructions/i,
    ~r/system\s*:\s*you\s+are/i,
    ~r/\[\[SYSTEM\]\]/,
    ~r/### OVERRIDE ###/
  ]
  
  @max_user_prompt_length 8192

  def validate_user_input(input, context) do
    with :ok <- check_length(input),
         :ok <- scan_injection_patterns(input),
         :ok <- validate_encoding(input),
         :ok <- check_semantic_safety(input, context) do
      {:ok, sanitize_input(input)}
    end
  end

  defp scan_injection_patterns(input) do
    if Enum.any?(@injection_patterns, &Regex.match?(&1, input)) do
      {:error, :potential_injection_detected}
    else
      :ok
    end
  end

  defp check_semantic_safety(input, context) do
    # Use ML classifier for sophisticated injection detection
    case RubberDuck.ML.InjectionClassifier.classify(input, context) do
      {:safe, _confidence} -> :ok
      {:suspicious, confidence} when confidence > 0.8 -> 
        {:error, :semantic_injection_risk}
      _ -> :ok
    end
  end

  defp sanitize_input(input) do
    input
    |> String.replace(~r/<script.*?>.*?</script>/is, "")
    |> String.replace(~r/\{\{.*?\}\}/, "")  # Remove template variables
    |> escape_special_tokens()
  end
end
```

**Authorization policies** enforce strict access control through Ash.Policy with role-based and attribute-based rules. The system implements audit logging for all prompt modifications with cryptographic proof of tampering:

```elixir
defmodule RubberDuck.Security.AuditLog do
  use Ash.Resource.Change

  def change(changeset, _, _) do
    changeset
    |> Ash.Changeset.after_action(fn changeset, result ->
      audit_entry = %{
        resource_type: "prompt",
        resource_id: result.id,
        action: changeset.action,
        actor_id: changeset.context.actor.id,
        tenant_id: changeset.context.tenant_id,
        changes: extract_changes(changeset),
        ip_address: changeset.context.ip_address,
        hash: calculate_audit_hash(changeset)
      }
      
      RubberDuck.AuditLog.create!(audit_entry)
      broadcast_security_event(audit_entry)
      
      {:ok, result}
    end)
  end

  defp calculate_audit_hash(changeset) do
    data = :erlang.term_to_binary({
      changeset.data,
      changeset.attributes,
      :os.system_time(:microsecond)
    })
    
    :crypto.hash(:sha256, data) |> Base.encode16()
  end
end
```

## Token cost management integration

The token optimization system from Phase 11 integrates deeply with prompt management, implementing intelligent caching, compression, and budget enforcement:

```elixir
defmodule RubberDuck.TokenManagement.Optimizer do
  @token_limits %{
    "gpt-4" => 8192,
    "gpt-3.5-turbo" => 4096,
    "claude-3" => 100000
  }

  def optimize_prompt_for_model(prompt_chain, model, budget) do
    total_tokens = calculate_token_count(prompt_chain)
    model_limit = @token_limits[model]
    effective_limit = min(model_limit, budget)
    
    if total_tokens <= effective_limit do
      {:ok, prompt_chain}
    else
      compress_prompt_chain(prompt_chain, effective_limit)
    end
  end

  defp compress_prompt_chain(prompt_chain, target_tokens) do
    # Priority-based compression
    priorities = %{system: 1.0, project: 0.8, user: 0.6}
    
    prompt_chain
    |> Enum.map(fn {level, content} ->
      compression_ratio = calculate_compression_ratio(
        content, 
        target_tokens,
        priorities[level]
      )
      
      {level, compress_content(content, compression_ratio)}
    end)
    |> validate_semantic_integrity()
  end

  defp compress_content(content, ratio) when ratio >= 1.0, do: content
  defp compress_content(content, ratio) do
    content
    |> RubberDuck.NLP.Summarizer.summarize(ratio: ratio)
    |> preserve_critical_instructions()
  end
end
```

The system tracks token usage per tenant with real-time budget enforcement and predictive cost analysis:

```elixir
defmodule RubberDuck.TokenManagement.BudgetEnforcer do
  use GenServer

  def check_budget(tenant_id, estimated_tokens) do
    GenServer.call(__MODULE__, {:check_budget, tenant_id, estimated_tokens})
  end

  def handle_call({:check_budget, tenant_id, tokens}, _from, state) do
    budget = get_tenant_budget(tenant_id)
    usage = get_current_usage(tenant_id)
    
    cond do
      usage.tokens_used + tokens > budget.hard_limit ->
        {:reply, {:error, :budget_exceeded}, state}
      
      usage.tokens_used + tokens > budget.soft_limit ->
        notify_approaching_limit(tenant_id, usage)
        {:reply, {:ok, :warning}, state}
      
      true ->
        {:reply, :ok, state}
    end
  end
end
```

## Web interface implementation from Phase 13

The Phoenix LiveView interface provides real-time collaborative prompt editing with syntax highlighting, version comparison, and live preview:

```elixir
defmodule RubberDuckWeb.Live.PromptManager do
  use RubberDuckWeb, :live_view
  require Logger

  @impl true
  def mount(_params, session, socket) do
    tenant_id = session["tenant_id"]
    
    if connected?(socket) do
      subscribe_to_prompt_updates(tenant_id)
      schedule_autosave()
    end

    {:ok,
     socket
     |> assign(
       tenant_id: tenant_id,
       prompts: load_prompts(tenant_id),
       selected_prompt: nil,
       editor_state: :idle,
       collaborators: [],
       version_history: []
     )
     |> assign_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="prompt-manager-container">
      <.prompt_sidebar prompts={@prompts} selected={@selected_prompt} />
      
      <div class="prompt-editor-main">
        <.prompt_header 
          prompt={@selected_prompt} 
          collaborators={@collaborators}
          on_save="save_prompt"
          on_preview="preview_prompt"
        />
        
        <div class="editor-container" phx-hook="PromptEditor" id="main-editor">
          <.form for={@form} phx-change="editor_change" phx-submit="save_prompt">
            <.monaco_editor 
              field={@form[:content]}
              language="markdown"
              theme="vs-dark"
              options={%{
                wordWrap: "on",
                minimap: %{enabled: false},
                lineNumbers: "on",
                rulers: [80, 120]
              }}
            />
          </.form>
        </div>
        
        <.version_timeline 
          versions={@version_history}
          on_select="load_version"
        />
      </div>
      
      <.prompt_preview 
        :if={@show_preview}
        content={@preview_content}
        variables={@detected_variables}
      />
    </div>
    """
  end

  @impl true
  def handle_event("editor_change", %{"content" => content}, socket) do
    # Debounced broadcasting of changes
    Process.cancel_timer(socket.assigns[:broadcast_timer])
    timer = Process.send_after(self(), {:broadcast_change, content}, 500)
    
    socket = 
      socket
      |> assign(broadcast_timer: timer)
      |> detect_variables(content)
      |> validate_prompt_syntax(content)
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("save_prompt", _, socket) do
    case save_prompt_with_validation(socket) do
      {:ok, prompt} ->
        {:noreply,
         socket
         |> put_flash(:info, "Prompt saved successfully")
         |> assign(selected_prompt: prompt)
         |> broadcast_save(prompt)}
      
      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def handle_info({:prompt_updated, prompt_id, changes}, socket) do
    socket = 
      if socket.assigns.selected_prompt.id == prompt_id do
        merge_external_changes(socket, changes)
      else
        update_prompt_in_sidebar(socket, prompt_id, changes)
      end
    
    {:noreply, socket}
  end

  defp detect_variables(socket, content) do
    variables = Regex.scan(~r/\{\{(\w+)\}\}/, content)
    |> Enum.map(fn [_, var] -> var end)
    |> Enum.uniq()
    
    assign(socket, detected_variables: variables)
  end
end
```

## API endpoints for CRUD operations

The GraphQL API provides comprehensive CRUD operations with real-time subscriptions for collaborative editing:

```elixir
defmodule RubberDuckWeb.Schema.PromptTypes do
  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  node object(:prompt) do
    field :name, non_null(:string)
    field :content, non_null(:string)
    field :prompt_level, non_null(:prompt_level_enum)
    field :version, non_null(:integer)
    field :is_active, non_null(:boolean)
    field :metadata, :json
    field :variables, list_of(:string)
    field :token_count, :integer
    
    field :parent, :prompt, resolve: dataloader(PromptManagement)
    field :versions, list_of(:prompt_version), resolve: dataloader(PromptManagement)
    
    field :can_edit, non_null(:boolean) do
      resolve fn prompt, _, %{context: %{current_user: user}} ->
        {:ok, can_edit?(prompt, user)}
      end
    end
  end

  object :prompt_queries do
    @desc "Get prompt by ID"
    field :prompt, :prompt do
      arg :id, non_null(:id)
      
      resolve fn %{id: id}, %{context: context} ->
        RubberDuck.PromptManagement.get_prompt(id, actor: context.current_user)
      end
    end

    @desc "Search prompts with filtering"
    connection field :prompts, node_type: :prompt do
      arg :filter, :prompt_filter_input
      arg :sort, list_of(:prompt_sort_input)
      
      resolve fn args, %{context: context} ->
        RubberDuck.PromptManagement.list_prompts(
          args,
          actor: context.current_user,
          tenant: context.tenant_id
        )
      end
    end

    @desc "Get effective prompt for a given context"
    field :effective_prompt, :composed_prompt do
      arg :name, non_null(:string)
      arg :level, :prompt_level_enum
      
      resolve fn args, %{context: context} ->
        RubberDuck.PromptManagement.get_effective_prompt(
          args.name,
          tenant_id: context.tenant_id,
          level: args[:level]
        )
      end
    end
  end

  object :prompt_mutations do
    @desc "Create a new prompt"
    field :create_prompt, :prompt do
      arg :input, non_null(:create_prompt_input)
      
      resolve fn %{input: input}, %{context: context} ->
        input
        |> Map.put(:tenant_id, context.tenant_id)
        |> RubberDuck.PromptManagement.create_prompt(actor: context.current_user)
      end
    end

    @desc "Update existing prompt"
    field :update_prompt, :prompt do
      arg :id, non_null(:id)
      arg :input, non_null(:update_prompt_input)
      
      resolve fn %{id: id, input: input}, %{context: context} ->
        RubberDuck.PromptManagement.update_prompt(
          id,
          input,
          actor: context.current_user
        )
      end
    end

    @desc "Archive prompt"
    field :archive_prompt, :prompt do
      arg :id, non_null(:id)
      
      resolve fn %{id: id}, %{context: context} ->
        RubberDuck.PromptManagement.archive_prompt(
          id,
          actor: context.current_user
        )
      end
    end
  end

  object :prompt_subscriptions do
    @desc "Subscribe to prompt updates"
    field :prompt_updated, :prompt do
      arg :prompt_id, :id
      arg :tenant_id, :id
      
      config fn args, %{context: context} ->
        cond do
          args[:prompt_id] -> {:ok, topic: "prompt:#{args.prompt_id}"}
          args[:tenant_id] -> {:ok, topic: "tenant:#{args.tenant_id}:prompts"}
          true -> {:ok, topic: "tenant:#{context.tenant_id}:prompts"}
        end
      end
      
      resolve fn prompt, _, _ ->
        {:ok, prompt}
      end
    end
  end
end
```

REST API endpoints provide backward compatibility:

```elixir
defmodule RubberDuckWeb.PromptController do
  use RubberDuckWeb, :controller
  
  action_fallback RubberDuckWeb.FallbackController

  def index(conn, params) do
    with {:ok, prompts} <- list_prompts(conn, params) do
      render(conn, "index.json", prompts: prompts)
    end
  end

  def create(conn, %{"prompt" => prompt_params}) do
    with {:ok, prompt} <- create_prompt(conn, prompt_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", prompt_path(conn, :show, prompt))
      |> render("show.json", prompt: prompt)
    end
  end

  def update(conn, %{"id" => id, "prompt" => prompt_params}) do
    with {:ok, prompt} <- update_prompt(conn, id, prompt_params) do
      render(conn, "show.json", prompt: prompt)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, _} <- archive_prompt(conn, id) do
      send_resp(conn, :no_content, "")
    end
  end
end
```

## Caching and performance optimization

The caching strategy implements a multi-tier approach optimizing for sub-50ms prompt resolution. **Level 1 cache** uses process-local ETS tables for hot prompts accessed within the last minute. **Level 2 cache** employs distributed Redis for cross-node sharing with 1-hour TTL. **Level 3 cache** persists to DETS for recovery after restarts.

```elixir
defmodule RubberDuck.PromptCache do
  use GenServer
  require Logger

  @l1_ttl 60_000      # 1 minute
  @l2_ttl 3_600_000   # 1 hour
  @l3_ttl 86_400_000  # 24 hours

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get(key, opts \\ []) do
    case check_l1_cache(key) do
      {:ok, value} -> 
        record_hit(:l1)
        {:ok, value}
      
      :miss ->
        case check_l2_cache(key) do
          {:ok, value} ->
            record_hit(:l2)
            warm_l1_cache(key, value)
            {:ok, value}
          
          :miss ->
            case check_l3_cache(key) do
              {:ok, value} ->
                record_hit(:l3)
                warm_upper_caches(key, value)
                {:ok, value}
              
              :miss ->
                fetch_and_cache(key, opts)
            end
        end
    end
  end

  defp check_l1_cache(key) do
    case :ets.lookup(:prompt_cache_l1, key) do
      [{^key, value, expiry}] when expiry > System.monotonic_time() ->
        {:ok, value}
      _ ->
        :miss
    end
  end

  defp check_l2_cache(key) do
    case Redix.command(:redix, ["GET", "prompt:#{key}"]) do
      {:ok, nil} -> :miss
      {:ok, value} -> {:ok, :erlang.binary_to_term(value)}
      {:error, _} -> :miss
    end
  end

  defp warm_upper_caches(key, value) do
    Task.start(fn ->
      warm_l1_cache(key, value)
      warm_l2_cache(key, value)
    end)
  end

  def invalidate(pattern) do
    GenServer.cast(__MODULE__, {:invalidate, pattern})
  end

  def handle_cast({:invalidate, pattern}, state) do
    # Clear L1 cache
    :ets.match_delete(:prompt_cache_l1, {pattern, :_, :_})
    
    # Clear L2 cache
    Task.start(fn ->
      {:ok, keys} = Redix.command(:redix, ["KEYS", "prompt:#{pattern}"])
      Enum.each(keys, &Redix.command(:redix, ["DEL", &1]))
    end)
    
    # Broadcast invalidation to other nodes
    Phoenix.PubSub.broadcast(
      RubberDuck.PubSub,
      "cache:invalidation",
      {:invalidate_prompts, pattern}
    )
    
    {:noreply, state}
  end
end
```

Performance monitoring tracks cache hit rates, prompt resolution times, and token usage patterns:

```elixir
defmodule RubberDuck.Metrics.PromptMetrics do
  use Prometheus.Metric

  def setup do
    Counter.declare(
      name: :prompt_cache_hits,
      help: "Prompt cache hit count by level",
      labels: [:cache_level]
    )
    
    Histogram.declare(
      name: :prompt_resolution_duration,
      help: "Time to resolve complete prompt chain",
      buckets: [10, 25, 50, 100, 250, 500, 1000],
      labels: [:tenant_id]
    )
    
    Gauge.declare(
      name: :prompt_cache_size,
      help: "Current cache size by level",
      labels: [:cache_level]
    )
  end

  def record_resolution_time(tenant_id, duration_ms) do
    Histogram.observe(
      [name: :prompt_resolution_duration, labels: [tenant_id]], 
      duration_ms
    )
  end
end
```

## Migration strategy from current system

The migration implements a phased approach ensuring zero downtime and gradual rollout:

### Phase 1: Data Migration (Week 1-2)
```elixir
defmodule RubberDuck.Migrations.PromptMigration do
  def migrate_existing_prompts do
    # Extract existing prompts from codebase
    existing_prompts = scan_codebase_for_prompts()
    
    # Create system-level prompts
    Enum.each(existing_prompts.system, fn prompt ->
      RubberDuck.PromptManagement.create_prompt(%{
        name: prompt.name,
        content: prompt.content,
        prompt_level: :system,
        metadata: %{
          migrated_from: prompt.source_file,
          original_format: prompt.format
        }
      })
    end)
    
    # Migrate per-project configurations
    migrate_project_configs()
  end
  
  defp scan_codebase_for_prompts do
    Path.wildcard("lib/**/*.ex")
    |> Enum.flat_map(&extract_prompts_from_file/1)
    |> categorize_prompts()
  end
end
```

### Phase 2: Dual-Mode Operation (Week 3-4)
The system operates in compatibility mode, supporting both old and new prompt systems:

```elixir
defmodule RubberDuck.PromptAdapter do
  def get_prompt(name, opts \\ []) do
    case opts[:use_legacy] do
      true -> get_legacy_prompt(name)
      false -> get_new_prompt(name, opts)
      nil -> get_with_fallback(name, opts)
    end
  end
  
  defp get_with_fallback(name, opts) do
    case get_new_prompt(name, opts) do
      {:ok, prompt} -> {:ok, prompt}
      {:error, :not_found} -> get_legacy_prompt(name)
    end
  end
end
```

### Phase 3: Validation and Testing (Week 5-6)
Comprehensive validation ensures prompt equivalence:

```elixir
defmodule RubberDuck.Migrations.PromptValidator do
  def validate_migration do
    legacy_prompts = get_all_legacy_prompts()
    
    Enum.map(legacy_prompts, fn legacy ->
      new = get_migrated_prompt(legacy.name)
      
      %{
        name: legacy.name,
        content_match: compare_content(legacy.content, new.content),
        token_difference: calculate_token_diff(legacy, new),
        semantic_similarity: calculate_similarity(legacy, new)
      }
    end)
  end
end
```

### Phase 4: Cutover (Week 7)
Final migration with monitoring and rollback capability:

```elixir
defmodule RubberDuck.Migrations.Cutover do
  def execute_cutover do
    # Enable feature flag
    RubberDuck.FeatureFlags.enable(:new_prompt_system)
    
    # Start monitoring
    RubberDuck.Metrics.PromptMetrics.start_migration_monitoring()
    
    # Gradual rollout
    schedule_progressive_rollout([
      {0.1, :hours, 1},
      {0.25, :hours, 4},
      {0.5, :hours, 12},
      {1.0, :hours, 24}
    ])
  end
end
```

## Example implementation code

### Complete Prompt Management Module

```elixir
defmodule RubberDuck.PromptManagement do
  use Ash.Domain

  resources do
    resource RubberDuck.PromptManagement.Resources.Prompt
    resource RubberDuck.PromptManagement.Resources.PromptVersion
    resource RubberDuck.PromptManagement.Resources.PromptUsage
    resource RubberDuck.PromptManagement.Resources.PromptCategory
  end

  def compose_prompt_chain(tenant_id, user_id, prompt_name, user_input) do
    with {:ok, system} <- get_system_prompt(prompt_name),
         {:ok, project} <- get_project_prompt(tenant_id, prompt_name),
         {:ok, user_context} <- get_user_context(user_id),
         {:ok, composed} <- compose(system, project, user_context, user_input),
         {:ok, validated} <- validate_composition(composed) do
      
      track_usage(composed, tenant_id, user_id)
      {:ok, composed}
    end
  end

  defp compose(system, project, user_context, user_input) do
    chain = []
    
    chain = if system, do: [{:system, system.content} | chain], else: chain
    chain = if project, do: [{:project, interpolate(project.content, user_context)} | chain], else: chain
    chain = [{:user, user_input} | chain]
    
    {:ok, Enum.reverse(chain)}
  end

  defp interpolate(content, context) do
    Regex.replace(~r/\{\{(\w+)\}\}/, content, fn _, var ->
      Map.get(context, String.to_atom(var), "")
    end)
  end
end
```

### Jido Workflow Integration

```elixir
defmodule RubberDuck.Workflows.PromptedCodeGeneration do
  use Jido.Workflow

  def generate_with_prompts(request) do
    workflow = 
      Jido.Workflow.new()
      |> add_step(:retrieve_prompts, RubberDuck.Actions.RetrievePrompts)
      |> add_step(:analyze_request, RubberDuck.Actions.AnalyzeRequest)
      |> add_step(:generate_code, RubberDuck.Actions.GenerateCode)
      |> add_step(:validate_output, RubberDuck.Actions.ValidateCode)
      |> add_step(:format_response, RubberDuck.Actions.FormatResponse)
    
    Jido.Workflow.execute(workflow, request)
  end
end
```

This comprehensive design provides a production-ready, scalable prompt management system that integrates seamlessly with the Rubber Duck architecture while maintaining security, performance, and developer experience as top priorities. The system supports everything from single-developer usage to enterprise-scale deployments with thousands of concurrent users.
