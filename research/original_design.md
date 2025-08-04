Elixir Agentic Coding Assistant System Design
System Overview and Goals
The coding assistant is built on Elixir for concurrency and fault-tolerance, using the Ash Framework for declarative modeling and persistence, and Jido for orchestrating autonomous agents. The design combines cutting-edge LLM techniques with robust engineering practices
raw.githubusercontent.com
raw.githubusercontent.com
. Key goals include: multi-provider AI model support, multi-user collaboration via Phoenix Channels/Presence, real-time streaming of AI responses, and a modular, extensible architecture. The system will allow different AI providers/models to be configured and used interchangeably, support collaborative editing sessions, and persist all important data (using AshPostgres with the option of in-memory AshEts for ephemeral data) as needed. The result is an AI coding assistant that can plan, execute, evaluate, and learn in an agentic loop, while seamlessly integrating into developer workflows.
Domain Model and Persistence (Ash Framework)
All core entities are modeled as Ash Resources with an AshPostgres data layer. For example, we define resources for Project, CodeFile, AnalysisResult, Prompt etc., capturing the relationships between them
raw.githubusercontent.com
. Each Project has attributes like name and a root_path (the directory sandbox on disk), and relations to collaborators/users. CodeFile resources store file path, content, AST or embeddings, and link to a Project
raw.githubusercontent.com
. Using Ash’s DSL, we enforce constraints (e.g. unique project names per user, or non-null file path) and implement policies for authorization. We leverage Ash’s multitenancy support so that data can be scoped by organization or user context
raw.githubusercontent.com
. For instance, Prompt templates (see below) have a scope field (global/project/user) and belong to an org/user if applicable, ensuring that team-specific prompts or instructions are isolated
raw.githubusercontent.com
. Ash gives us generated APIs (which we expose via Phoenix and optionally GraphQL) for CRUD operations on these resources. It also provides change tracking and extension points for side-effects. For example, when a CodeFile is updated, we can hook an Ash change to trigger re-analysis of that file (e.g. using a custom TriggerAnalysis change)
raw.githubusercontent.com
. We use Ash’s Policy Authorizer to enforce that only project members can read/write files of that project, etc. All data is stored in Postgres via AshPostgres, enabling persistence and queries. In initial development phases, we could use Ash’s in-memory ETS layer (AshEts) for rapid iteration, then switch to Postgres without changing our business logic. Ash’s declarative nature ensures our domain remains well-defined and consistent across the system.
Pluggable Engines and Tooling Architecture
To handle various AI-powered functions (code completion, generation, explanation, testing, etc.), the system uses a pluggable engine approach with a Spark DSL extension. We define an EngineSystem DSL where each engine is declared with a name, implementation module, default model config, and context strategy
raw.githubusercontent.com
. New engines can be added easily by listing them in this DSL (for example, a :documentation engine for generating docs, or a :refactoring engine) without altering core logic. Each engine implements a common behavior (e.g., a generate/2 function that takes context and a handler for streaming) and is run in its own supervised process for isolation
raw.githubusercontent.com
. For instance, we have engines like: CompletionEngine for code completions, GenerationEngine for generating new files or functions, TestEngine for unit test creation, etc., each potentially using different LLM models or strategies
raw.githubusercontent.com
. In parallel, the assistant incorporates a Tool System inspired by frameworks like LangChain, but implemented in Elixir. Tools are discrete capabilities (running code, searching docs, refactoring code, etc.) that the AI agents can invoke. We utilize Spark DSL to declaratively define tools, including their name, description, input schema (parameters), and execution details
raw.githubusercontent.com
raw.githubusercontent.com
. This yields a library of tools that are type-safe and self-documented. The system ensures that each tool execution goes through a multi-layer pipeline for safety: Validation Layer (inputs are validated against a JSON schema derived from the DSL, preventing malformed data)
raw.githubusercontent.com
, Authorization Layer (Ash policies or explicit rules check if the user/agent is allowed to use this tool)
raw.githubusercontent.com
, Execution Layer (the tool runs in an isolated Elixir process, e.g. a Task supervised by a TaskSupervisor, with timeouts and resource limits)
raw.githubusercontent.com
raw.githubusercontent.com
, and Result Processing (output is post-processed, e.g. truncating or filtering sensitive info, and then returned to the agent)
raw.githubusercontent.com
. This design means if a tool crashes or hangs, it won’t crash the main agent – the supervision tree will handle it and an error will be returned, preserving system stability
raw.githubusercontent.com
raw.githubusercontent.com
. Many tools leverage the Elixir/BEAM strengths for isolation. For example, a CodeFormatter tool can call the Elixir code formatter on a separate OS process if needed, or a RunTests tool might execute tests in a sandboxed environment (perhaps using Docker or an isolated Beam node). The tools can also compose: using Reactor (a workflow DSL), we can define composite tools that call multiple atomic tools in sequence or in parallel to accomplish higher-level tasks
raw.githubusercontent.com
. An example from the design is a CodeRefactoring composite tool that parses code, analyzes it, generates refactored code, and then validates the changes, all defined in a declarative workflow
raw.githubusercontent.com
. This composition uses Reactor’s DAG capabilities to express conditional or parallel steps (e.g., run multiple analysis in parallel on code, then combine results)
raw.githubusercontent.com
raw.githubusercontent.com
. For external integration, the system includes an MCP (Multi-Client Protocol) server that exposes the tool library via JSON-RPC over websockets. This allows external IDE plugins or other AI systems to query available tools and invoke them remotely
raw.githubusercontent.com
raw.githubusercontent.com
. It maintains state (auth, sessions) and uses the same execution pipeline internally. All tool and engine interactions are logged and auditable (Ash’s change tracking plus custom audit logs)
raw.githubusercontent.com
, so we maintain traceability of what the AI did (which commands it ran, etc.). The pluggable design means we can update or add capabilities (for example, a DependencyInstaller tool to add a library to mix.exs) in a modular way.
LLM Integration and Multi-Provider Support
At the heart of the assistant is the LLM integration layer. We implement a GenServer-based LLM Service that abstracts over different providers (OpenAI, Anthropic, local models, etc.)
raw.githubusercontent.com
. This service is configured with multiple provider clients (e.g., OpenAI API client and an Anthropic API client, or HuggingFace local model runner), and it can select which to use per request. Providers and models are configurable: for instance, our EngineSystem might specify default models (GPT-4 for completion, Claude 2 for generation, etc.), but at runtime a user could select a different model for a request. The LLM Service uses strategies like round-robin or priority-based selection to distribute calls, and includes fallback logic: if one provider fails or is slow, it can automatically retry with another (as long as the output format is compatible)
raw.githubusercontent.com
. This ensures high availability and optimal performance/cost – for example, try a local model first, but if the confidence or result is not sufficient, fall back to a larger cloud model. We use streaming APIs when available. The service supports sending partial results back through a callback mechanism. For example, as the LLM returns tokens for a code completion, our engine process will receive those and push them over the Phoenix channel to the client in real-time
raw.githubusercontent.com
. This provides a responsive experience where the user sees the code being written token-by-token, similar to GitHub Copilot. Key AI techniques integrated into the workflow include:
Chain-of-Thought prompting – The assistant can prompt the model to reason step-by-step for complex tasks. This has been shown to significantly improve solution correctness (e.g., a structured CoT prompt improved pass@1 by ~13.8% in coding challenges)
raw.githubusercontent.com
. We use CoT in scenarios like planning a function implementation: the model is first asked to outline its approach in pseudo-code or steps, which it then follows to write the code.
Retrieval-Augmented Generation (RAG) – Before answering questions or generating code, the assistant searches a knowledge base of project code and documentation to pull in relevant context
raw.githubusercontent.com
. For instance, if the user asks about a function, we retrieve its source or related docs and provide that to the LLM. Studies show RAG can yield 3-4× improvements in correctness for coding tasks by grounding the model with real project data
raw.githubusercontent.com
. We implement this via an embedded vector database (Postgres with pgvector), storing embeddings of code and docs, and using similarity search to fetch relevant snippets
raw.githubusercontent.com
.
Iterative Self-Correction – The system can automatically refine its output by running tests or static analyzers and feeding the results back into the model. For example, after generating code, it might compile and execute tests; if failures occur, it summarizes the errors and has the LLM attempt a fix. This loop of generate -> evaluate -> fix has yielded major accuracy gains (e.g., correctness rising from ~54% to ~82% after one test-fix cycle in research)
raw.githubusercontent.com
. In our implementation, an agent (or tool) can invoke the test suite (via ExUnit or a TestRunner tool) and capture failures, then call the LLM again with that feedback. This may repeat for a few iterations (with safeguards to avoid infinite loops).
Agentic planning and tool use – Beyond single-turn prompts, the assistant uses a multi-step agent approach where it can decide on actions (tools or further queries) to achieve an objective. This aligns with the ReAct pattern (Reason+Act) and other agent frameworks. It enables the assistant to, say, plan out how to implement a feature by decomposing it, searching the project, writing code, running tests, etc., autonomously. Such agentic workflows have shown about a 5–20% improvement on complex tasks by combining the strengths of LLM reasoning with external tool usage
raw.githubusercontent.com
raw.githubusercontent.com
. Our system uses Jido to facilitate this: the LLM’s plan is executed step by step by calling tools (with each tool’s result fed back), rather than one giant prompt.
All LLM calls and prompts are managed carefully. We use a Prompt Builder/Manager to assemble prompts from various pieces (system instructions, relevant retrieved context, conversation history, code context, etc.)
raw.githubusercontent.com
raw.githubusercontent.com
. This ensures consistency and allows us to easily swap prompt templates or apply formatting. The prompt content can include the project’s instruction files (like coding style guidelines from the repository) and user preferences (e.g. “use functional style” flags). We also sanitize prompts to avoid injection attacks and apply an instructions filter that strips or alters any user-provided instruction to the AI that might be malicious or disallowed (for example, attempting to get the AI to ignore safety guidelines)
raw.githubusercontent.com
. The LLM Service also includes rate limiting and caching. We integrate with tools like circuit breakers to avoid repeatedly calling a failing API and token-bucket rate limiters to stay within provider quotas
raw.githubusercontent.com
raw.githubusercontent.com
. Responses for identical queries (or embeddings for identical texts) can be cached in an ETS or Redis cache to save cost and latency on repeated queries
raw.githubusercontent.com
. The multi-provider setup means if one API is down or too slow, we can dynamically route to another provider, which is crucial for reliability. All of these features together form a robust LLM integration layer that can leverage the best available models while mitigating their weaknesses with tools and structured approaches.
Agentic Planning System (Multi-Agent Coordination with Jido)
One of the most important aspects of the assistant is its ability to handle complex, multi-step tasks like “Implement this feature in the codebase” or “Analyze this code and improve it”. Rather than relying on a single prompt/response, the system uses a multi-agent planning system to break down and solve such tasks. This is motivated by research showing that LLMs alone struggle with extended autonomous planning (only ~12% success in one study) but excel when guided by structured frameworks with validation
raw.githubusercontent.com
. Our planning system is built using the Jido agent framework, meaning each part of the planning process is handled by an independent but cooperative agent (an OTP process) and they communicate via message passing (signals/events) in a loosely coupled way. Planning Agents and their responsibilities include:
PlanCoordinatorAgent – the central orchestrator of a planning session. It receives the user’s request (goal) and decides which planning template/strategy to use. It then manages the overall lifecycle of the plan, triggering other agents in sequence and collecting their results. This agent ensures the process converges or stops appropriately (e.g., deciding to finish when the plan is satisfactory or abort after too many failures)
raw.githubusercontent.com
.
TaskDecomposerAgent – takes a high-level goal and decomposes it into discrete subtasks or steps. It might use an LLM (with a prompt like “List the steps to achieve X”) or apply a predefined plan template. The result is a draft task list or plan outline
raw.githubusercontent.com
. For example, for a feature request, it might break it down into “Update database schema”, “Implement API endpoint”, “Write tests”, etc.
SubtaskExecutorAgent – responsible for executing an individual subtask. For tasks that require code generation or editing, it will invoke the appropriate Engine (e.g., call the CodeGeneration engine or a Refactoring tool). It streams progress (e.g., partial code as it’s being generated) and reports completion or any errors back to the coordinator. Multiple SubtaskExecutors can run in parallel if the plan allows (for instance, two independent tasks) to speed up the process.
CriticAgent – evaluates the output of tasks using various criteria. We implement several critics (as instances of CriticAgent specialized in different areas): e.g., a SyntaxCritic checks if the code compiles, a TestCritic runs tests on the new code, a StyleCritic reviews code against style guidelines. Critics can deliver hard feedback that blocks progress (e.g., “the code doesn’t compile, we must fix this”) or soft feedback (non-mandatory suggestions)
raw.githubusercontent.com
. In the planning loop, after a subtask executes, relevant critics are invoked to judge the result. This echoes the “LLM-Modulo” idea: use external validators alongside the LLM
raw.githubusercontent.com
.
RefinementAgent – if a critic flags an issue or a task otherwise fails, the RefinementAgent steps in to adjust the plan or output. It may prompt the LLM to fix the code (e.g., “The test failed with XYZ, please fix the bug”), or modify the task list (e.g., add an extra step to address a discovered sub-problem)
raw.githubusercontent.com
. The refinement agent works with the PlanCoordinator to integrate these changes and then the execution resumes. Essentially, this implements iterative self-correction at the plan level: the plan refines itself until it succeeds or a limit is reached.
These agents communicate through Jido signals (which under the hood uses pub-sub events). For instance, the PlanCoordinator might emit a plan.decompose signal with the goal, which the TaskDecomposerAgent subscribes to; when it produces subtasks, it emits a plan.decomposed event that includes the task list. The PlanCoordinator receives that and then for each task emits a plan.execute_task event, which triggers a SubtaskExecutorAgent (or many) to run that task. Once a task is done, an event is emitted (e.g. task.completed or task.result) which the CriticAgents listen to (or the PlanCoordinator directs to them)
raw.githubusercontent.com
. The critics each send back their feedback (perhaps on a channel like task.reviewed or via the coordinator aggregating feedback)
raw.githubusercontent.com
. If there is a failure, plan.refine is signaled and the RefinementAgent engages. This loop continues until all tasks are completed and validated, at which point the PlanCoordinator signals the plan as finished (could be plan.done). The final result might be a code diff, a set of files, or a summary, which we can then feed into a Workflow Orchestrator if the task was, say, to actually apply changes to the project. (In our design, the PlanCoordinator could output an Ash Workflow – an executable set of changes – or directly apply changes via the tools and commit them.) The planning templates are defined using a Spark DSL for planning (akin to how we define tools). Each template describes a certain scenario’s ideal plan structure. For example, a template for a “feature implementation with TDD” might specify: first write a specification, then tests, then code, then refactor
raw.githubusercontent.com
. Each step can optionally specify a particular critic (e.g., after implementing code, run the tests critic). The template can also encode strategy metadata like “execute sequentially” or “allow reflection” (where the plan can revisit steps). The PlanCoordinator chooses a template based on the task type (:bugfix, :feature, :optimization, etc.)
raw.githubusercontent.com
. These templates make the planning more declarative and standardized, while still allowing flexibility (the agents fill in details, and can deviate if needed). Agents are implemented as OTP processes (GenServers) and are supervised. For each new planning session, a DynamicSupervisor starts a fresh set of agent processes (PlanCoordinator and whichever agents it spawns) to isolate state
raw.githubusercontent.com
. When the plan is complete or aborted, the whole supervision subtree can be easily terminated, freeing resources. This also means multiple planning sessions (from different users or projects) can run concurrently on different processes (and even different nodes in a cluster). We also consider reusing some agents as shared services: for example, rather than spinning up new CriticAgents for every plan, we might run a pool of persistent CriticAgents that subscribe to all critique events across plans
raw.githubusercontent.com
. This could improve efficiency by reusing loaded state (say a SecurityCriticAgent that has loaded a vulnerability database). These design choices are configurable – initially, we may keep it simple with per-plan agents for isolation. Overall, the agentic planning system brings modularity and reliability. Each agent focuses on one aspect (decomposition, execution, critique, etc.), which aligns with the single-responsibility principle and makes testing easier. We can swap in improved agents (e.g., a more advanced TaskDecomposer using Tree-of-Thought for harder problems) without disrupting others. By having critics in the loop, we ensure the plan’s quality is assessed at each stage, addressing the known weakness of LLMs blundering through tasks without feedback
raw.githubusercontent.com
raw.githubusercontent.com
. And using Jido’s messaging avoids tight coupling – agents don’t call each other directly (reducing risk of deadlocks); instead they emit events and any agent interested can react. This publish/subscribe model also makes it simple to add new capabilities: if we later add an OptimizationAgent that listens for a plan completion event and suggests improvements, it can be done without altering the existing agent code – just subscribe it to the relevant signals.
Conversational Interface and Memory System
Users (whether through an IDE plugin, web UI, or CLI) interact with the assistant via a conversational interface. We use Phoenix Channels for all client communication, enabling real-time, bidirectional messaging over WebSocket. Each conversation (chat session or assistant thread) corresponds to a channel topic like "conversation:<id>" that clients join
raw.githubusercontent.com
. This design easily supports multiple front-end types: a web UI (LiveView or custom JS) can join and get JSON or HTML-formatted messages, a CLI client can connect and specify it wants plain text responses, etc. We include a field for client_type and negotiation in the join params to tailor the format if needed
raw.githubusercontent.com
. For example, if a LiveView joins, the server might send responses with some HTML formatting or ANSI coloring for a TUI client
raw.githubusercontent.com
. When a client joins a conversation channel, the server spins up (or connects to) a Conversation process (GenServer) that will handle state for that chat session
raw.githubusercontent.com
raw.githubusercontent.com
. This process is responsible for managing the conversational memory and context. We implement a three-tier memory inspired by techniques from recent AI systems: short-term memory for the recent dialogue (last N messages), mid-term memory for important patterns or facts extracted, and long-term memory for older knowledge (persisted)
raw.githubusercontent.com
. The short-term memory is stored in an in-memory ETS table for speed
raw.githubusercontent.com
. Each conversation GenServer uses an ETS table (named per conversation) to record the last several messages or interactions, giving microsecond-level access for retrieval
raw.githubusercontent.com
. Mid-term memory is handled by a PatternExtractor process that periodically analyzes the conversation (e.g., every 5 minutes or after X messages) to detect recurring topics or intentions
raw.githubusercontent.com
raw.githubusercontent.com
. For instance, if many messages revolve around "database migration", it might save a pattern like "topic: database migration" with examples. These patterns are stored in a medium-term store (could be an ETS table or an Ash resource for patterns). Long-term memory relies on vector embedding storage: salient information (e.g., summaries of each conversation session, important Q&A pairs) are embedded and saved in a Postgres table with pgvector, via the Memory Manager. The Memory Manager GenServer can retrieve relevant long-term memories by semantic search when needed
raw.githubusercontent.com
. When the user sends a message, the Conversation process first stores it (in short-term memory ETS and also sends it to the PatternExtractor buffer for mid-term)
raw.githubusercontent.com
raw.githubusercontent.com
. Then it constructs the context for the LLM: it will pull the recent messages from short-term (ensuring they fit the model’s context window, possibly dropping oldest if needed), add any highly relevant mid-term patterns (if, for example, the user’s question triggers a keyword that matches a saved pattern, include a summary of those past discussions), and potentially query long-term memory or project knowledge base if the query seems to require it
raw.githubusercontent.com
raw.githubusercontent.com
. For instance, if the user asks “Can you remind me what we decided last week about X?”, the system can search the vector store for “X” and retrieve a summary or the exact past conversation snippet. The composed context typically includes: a system message (with high-level instructions/policy), a few relevant instruction/prompt files (from the project’s configured instructions, see next section), and then a series of messages (some from the user, some from assistant, etc.) representing the conversation state. The conversation process also tracks metadata like the last user activity time to implement smart behaviors (e.g., only proactively suggest help when the user has paused typing for >5s as per rubber-ducking best practices
raw.githubusercontent.com
). It uses a sliding window with relevance scoring for context: instead of naively taking the last 20 messages, it can prioritize messages by importance. For example, if the conversation is long but the current question is about “database migration”, it might ensure that earlier discussion about migrations is kept even if some more recent off-topic chat is dropped. The system can use a relevance function (embedding similarity between the new query and past messages) to select which messages to include when truncating
raw.githubusercontent.com
. This maximizes the useful information the LLM sees, within token limits. Phoenix Presence is enabled on conversation channels to support multi-user chat (like a group conversation with the AI, or handoff between devices). When a user joins, we track their presence with metadata (e.g., user name, client type, join time)
raw.githubusercontent.com
. The Presence list can be used to show who else is viewing the conversation. This could enable a future feature where multiple developers chat with the assistant in the same session (the assistant is another “participant”), useful for pair programming or code review scenarios. Presence also helps in reconnection logic – if a user temporarily disconnects, when they rejoin we can signal the Conversation process to replay missed events or restore the last state. The conversation state is persisted in snapshots as needed for reliability. We create an Ash resource for ConversationSnapshot which stores a compressed version of the conversation (or its mid/long-term state) every so often. On reconnect or server restart, the system can load the latest snapshot and replay any events from the event store or logs to recover state
raw.githubusercontent.com
. This ensures that even long-running chats or important context is not lost due to outages. The message handling inside the channel supports both natural language and explicit commands. We have a simple protocol: the client can label a message as type: "chat" (default, just plain conversation) or type: "command" (if the user explicitly invokes a command like /test), or even "mixed" if the client is unsure. On receiving a message, the channel server will wrap it into a standard message struct (with content, type, timestamp, sender info) and pass it to the Conversation GenServer
raw.githubusercontent.com
. If it’s a command, we route it to a Command Processor instead of the LLM: e.g., a /analyze command might directly call a static analysis tool and return results. If it’s chat, we call the LLM Service to get a completion, providing the built context and enabling CoT or RAG as configured
raw.githubusercontent.com
. If it’s mixed, we use an intent classifier to figure out how to split it
raw.githubusercontent.com
. We have implemented a basic classifier that checks for a leading slash or known command keywords. For more complex cases (e.g., “I think we should /refactor the module to use ETS”), the system can employ the LLM itself to parse out the command. We have an analyze_intent function where the LLM is given the user input and a list of available commands, and it returns a JSON indicating if there’s a command and what its args are
raw.githubusercontent.com
. This result might be: {"type": "mixed", "command_parts": ..., "chat_parts": ...} which we then handle accordingly (execute the command part and use the result in a chat reply, etc.). Each Conversation channel supports streaming responses to the client. As mentioned, when the LLM generation is in progress, we stream intermediate tokens. In our Phoenix Channel, we might push events like "completion_chunk" for each delta
raw.githubusercontent.com
. The front-end can append these to the chat UI in real-time. When the answer is done, a "completion_done" event is pushed with maybe some metadata
raw.githubusercontent.com
. This provides an experience of the assistant “thinking out loud” and is useful for long answers (the user sees progress) and for possibly interrupting if the answer is going off-track. Similarly, for tools, we stream their output. If the assistant runs tests, we could stream test results live (e.g., which tests passed or failed in real time). Finally, we ensure the conversation channel is secure and efficient. All clients must authenticate (e.g., via Phoenix Token or session) before joining a conversation (the join will verify the user has access to that conversation)
raw.githubusercontent.com
. We can use topic names that include a user or project identifier to enforce scoping. Messages can be serialized in a compact form (we support MessagePack in addition to JSON for lower overhead if needed)
raw.githubusercontent.com
. And we handle idle disconnects and cleanup: if a conversation is inactive for a long time and no users are present, we may shut down the GenServer to free memory, writing a snapshot to the DB. If the user comes back, a new process starts and restores state (this ties into the snapshot system mentioned earlier).
Instruction and Prompt Management System
To guide the AI and provide context beyond just code, the assistant incorporates a markdown-based instruction system. This allows developers to include custom instructions, rules, or context information in their project (and for themselves globally) that the assistant will always consider. This concept is inspired by tools like Claude’s claude.md or Cursor’s *.mdc rule files
raw.githubusercontent.com
. In our design, we support multiple layers of instructions:
Global instructions – maintained by the server admin or user in a home directory (e.g., ~/.rubber_duck/settings.md or similar), applied to all projects (e.g., “Always follow Elixir best practices such as the ones in the company style guide.”).
Project instructions – stored in the repository, e.g., a .rubber_duck/ folder with files like instructions.md, or in simpler form a top-level CLAUDE.md for compatibility
raw.githubusercontent.com
raw.githubusercontent.com
. These are version-controlled and meant to describe the project-specific conventions, architecture notes, or any rules the AI should follow for that codebase. They automatically load when that project is active.
Directory-specific instructions – our advanced design allows placing instruction files in subdirectories, such as an AGENTS.md in a particular folder, which will only apply when working on files in that folder or its children
raw.githubusercontent.com
. For example, a backend/AGENTS.md might contain backend-specific guidelines, while a frontend/AGENTS.md has front-end specific ones. The system will include those instructions when the context is a file in that directory tree, thereby providing more targeted guidance.
User prompts and templates – via the UI, a user can also create and store prompt templates (e.g., a template for “explain this code in simple terms”). These are saved in Ash (with fields for content, title, variables, etc.) and can be shared or reused. They can also be tagged to auto-suggest them in certain contexts (for instance, a prompt template tagged “testing” might be suggested whenever the user opens a test file).
All these instructions are processed by an Instruction Processor pipeline. We use Solid (an Elixir implementation of Liquid templating) instead of raw EEx for rendering any templates, because Solid is safe – it won’t allow arbitrary code execution and doesn’t leak atoms (important when users can create variables)
raw.githubusercontent.com
. The instruction files can include placeholders that get filled with runtime context. For example, in a prompt you might have {{project_name}} or {{current_file}}, which the system will replace with the actual project name or current file path. Solid gives us basic logic too (conditional blocks, loops) but within safe limits. System-provided templates (that we trust) could still use EEx if needed for more complex logic, but all user content goes through Solid for security. We also use Earmark to convert Markdown to HTML when needed (for display in a web UI), but the core instructions are kept in Markdown text for the LLM to read (it actually often works better if the instructions are given in a simple text format). When the assistant prepares a prompt for the LLM, it will gather applicable instructions: global, project-wide, directory-specific (if any), and possibly some dynamic ones. It then filters and sorts them by priority. We allow a YAML frontmatter in instruction files where users can set a priority (high/normal/low) and tags/types (e.g., “always” vs “sometimes”)
raw.githubusercontent.com
. For example, a critical security instruction might be marked high priority, ensuring it always goes in the prompt if there's space. If there are too many instructions to fit (token-wise), we drop low-priority ones first. Additionally, our system supports keyword-based conditional inclusion: in the metadata, an instruction can specify a list of keywords and a match type (any, all, some) which must be present in the user’s query or context for that instruction to apply
raw.githubusercontent.com
raw.githubusercontent.com
. For instance, a file security_guidelines.md might only be included if the user’s question or the code context contains words like “auth” or “JWT” or “login” (meaning it’s relevant to security)
raw.githubusercontent.com
. This prevents overloading the LLM with irrelevant instructions. We implemented a KeywordMatcher module that takes the metadata and the current conversation text and decides for each file to include or exclude
raw.githubusercontent.com
raw.githubusercontent.com
. The instruction files are loaded through a Hierarchical Loader that searches the file system (using our sandboxed file access). On startup or when a new project is opened, we scan the .rubber_duck/ directory and other known locations for instruction files. We also allow multiple files (like Cursor does with multiple rule files) – perhaps categorized by purpose (one for style, one for architectural rules, etc.). The loader merges all found instructions into a unified set. If there are conflicts (e.g., two files have contradictory content or the same key), we have a resolution strategy: e.g., project instructions override global, directory-specific might override project if more specific, etc. Each instruction file’s metadata can also include an identifier so we can update or replace it without duplication. To keep things efficient, we employ caching. Processed instructions (after template rendering) are stored in an ETS cache keyed by (project, file path, maybe a version hash)
raw.githubusercontent.com
raw.githubusercontent.com
. If nothing has changed and the context is the same, we reuse the cached instruction text for the prompt. We also watch the filesystem for changes to instruction files using the FileSystem library (with inotify/FSEvents). The InstructionWatcher GenServer subscribes to changes in any .md files in the instruction directories and will invalidate the cache and notify running conversations if something is edited
raw.githubusercontent.com
raw.githubusercontent.com
. This means if a user updates the claude.md in their repo, they can see the effect immediately – the assistant will reload it (we can even have it send a system message like “Project instructions updated.” to the conversation). We broadcast an update event via Phoenix PubSub which our InstructionChannel (for UIs that edit instructions) or conversation channels can handle
raw.githubusercontent.com
raw.githubusercontent.com
. Because instructions can contain code or shell commands in examples, we treat them as potentially untrusted input to the LLM. We ensure that any code in instructions is clearly delineated (using markdown ``` fences) so that the model doesn’t accidentally execute it thinking it’s part of the system prompt. Our TemplateSecurityPipeline performs multi-layer checks: it validates the template format and length (to avoid extremely long or degenerate inputs), it sanitizes any injected variables (for instance, if a variable might contain user text that includes forbidden content, although unlikely in this context)
raw.githubusercontent.com
raw.githubusercontent.com
. The goal is to prevent scenarios where a malicious user could manipulate an instruction such that, when rendered, it breaks the assistant’s logic or reveals something unintended. On the prompt management side (as distinct from file-based instructions), we have an Ash resource for Prompt which stores user-defined prompt templates. Each prompt can have many versions (we maintain history so you can revert changes or see how a prompt evolved)
raw.githubusercontent.com
. We also allow prompts to be categorized or tagged for easy finding. Through a simple UI or CLI, the user can list available prompts or search them (we index the title and content for search using Postgres full-text search or trigram indexes
raw.githubusercontent.com
raw.githubusercontent.com
). The user can then invoke a prompt by name, which will fill in variables and feed it to the assistant. Some prompts might be marked as “auto-run” in certain contexts – for example, a prompt that always runs when opening a PR diff could be auto-triggered. The Prompt Selector in the system can automatically suggest or select prompts based on the context using rules or ML (e.g., if the user is editing a test file, suggest the “write tests” prompt)
raw.githubusercontent.com
. All these features (instructions and prompts) greatly enhance the assistant’s utility by injecting human knowledge and preferences into the AI’s behavior. From an implementation perspective, we keep them version-controlled and auditable. They act almost like an extension of the system’s “brain” that the user controls. This approach follows industry trends: both GitHub Copilot and Cursor introduced similar concepts because they empower users to customize the AI for their project’s needs
raw.githubusercontent.com
.
Secure Project Filesystem Sandbox
The assistant is designed to work with potentially large and sensitive codebases. To ensure safety, it operates within a per-project sandbox when accessing the filesystem. Each Project resource has a root_path attribute which is the only directory the assistant’s file operations can touch
raw.githubusercontent.com
. We implement strict path validation on every file operation: before reading or writing a file, the requested path is resolved against the project root and checked that it does not escape that directory (no .. to parent, no absolute path outside the root)
raw.githubusercontent.com
. We use Path.expand and a custom Path.safe_relative function, and ensure the expanded path begins with the project’s root path prefix
raw.githubusercontent.com
. If any check fails, the operation is rejected with an error (and logged for security auditing). We also limit file name length and block any paths with suspicious characters (null bytes, etc.)
raw.githubusercontent.com
. Additionally, we guard against symlink attacks. If the project’s folder contains symlinks, there’s a risk someone could create a symlink that points outside (e.g., project/evil -> /etc/passwd). To mitigate this, whenever the assistant is about to open a file, it does an File.lstat and if the path is a symlink, we read its target and ensure the target is still within the project directory
raw.githubusercontent.com
. Our ProjectSymlinkSecurity module can also do a scan of the whole project for any symlinks that point out, and either warn or ignore those files
raw.githubusercontent.com
raw.githubusercontent.com
. Essentially, the assistant will treat such symlinked files as out-of-bounds. All file access goes through a dedicated ProjectFileManager module that the assistant uses as an API. This module wraps standard File operations with the checks above and adds logging/telemetry. For example, ProjectFileManager.read_file(project, path) will validate the path, check file size limits (so we don’t accidentally try to read a huge file into memory)
raw.githubusercontent.com
raw.githubusercontent.com
, then perform the read. We favor using low-level :file functions for performance (reading with :file.open in raw mode to avoid the single-process file server bottleneck in OTP)
raw.githubusercontent.com
. Similarly, write_file will validate and then do an atomic write: we write to a temp file and rename it, to avoid partially written files if something crashes mid-write
raw.githubusercontent.com
. Writes also go through a permission check – we only allow writing if the user has write access (owner or collaborator with permission) which we check via project collaborators metadata
raw.githubusercontent.com
. We even intercept delete operations: instead of permanently deleting, we move the file to a .trash directory within the project (with a timestamp)
raw.githubusercontent.com
. This provides a safety net in case of accidental deletions (the user or admin can retrieve from trash) and ensures the assistant doesn’t lose data irreversibly without explicit intent. A background job or admin can periodically clean the trash directories. For performance, the ProjectFileManager includes an in-memory cache of file information. Directory listings (which can be expensive on large folders) are cached with a TTL. When you list a directory, we store the list of files and their metadata in an ETS table, keyed by project and directory path
raw.githubusercontent.com
. Subsequent requests use the cache if fresh. The cache is invalidated automatically when any file in that directory changes (our file watcher will publish events to clear relevant cache entries)
raw.githubusercontent.com
raw.githubusercontent.com
. Also, the user can manually flush or the system flushes after a certain time. We also cache file contents or ASTs for quick re-read if they haven’t changed (tracked by file modification time). Because code editors often request the same file multiple times (for analysis, etc.), this significantly reduces disk I/O. Crucially, the assistant supports real-time collaboration on files. We integrated a file-watching mechanism using the :file_system Elixir library. When a Project is opened (first user connects), a DynamicSupervisor starts a ProjectFileWatcher GenServer for that project
raw.githubusercontent.com
raw.githubusercontent.com
. This watcher subscribes to OS filesystem events for the project directory (recursively). When it receives events (like a file modified, created, or deleted)
raw.githubusercontent.com
, it validates the path (to ensure the event is within the sandbox)
raw.githubusercontent.com
, batches events over a short window (to coalesce rapid changes)
raw.githubusercontent.com
, then broadcasts a message over Phoenix PubSub for that project’s file topic
raw.githubusercontent.com
. All clients editing that project (who have subscribed to "project:<id>:files") will get an update. For example, if User A creates a new file, User B’s UI will immediately be notified and can show the new file in the tree. Our LiveView front-end uses this to live-update the file list and also to highlight lines that others are editing (we broadcast edit diffs or cursors as well, though that is an extension beyond the core spec). The LiveView also uses Phoenix Presence on "project:<id>:presence" to track active users in the project, which the UI can display (e.g., “Alice (Web) and Bob (CLI) are viewing this project”)
raw.githubusercontent.com
raw.githubusercontent.com
. To manage scale, we’ve imposed some limits: we won’t watch more than a certain number of projects concurrently (configurable, say 100) to avoid exhausting OS file watcher handles. A ProjectWatcherManager keeps a tally and if the limit is exceeded, it will stop the least recently active watcher (and require it to restart if needed later)
raw.githubusercontent.com
. We also automatically stop watchers that have been idle (no changes and no users) for, say, 30 minutes
raw.githubusercontent.com
raw.githubusercontent.com
. The OS limits like max file descriptors and max watcher handles can be tuned via environment variables (we set ERL_MAX_PORTS and OS ulimit as needed)
raw.githubusercontent.com
. In essence, we strive to support large monorepos with thousands of files – our design tested on sample data and adjusted caching and limits to handle e.g. 10,000+ files with minimal overhead. All file actions trigger telemetry events that can be used for monitoring and rate limiting. We wrap critical functions in an instrument_operation that logs duration and result to Telemetry metrics
raw.githubusercontent.com
. This can feed into an ops dashboard to see e.g. file read latency or error rates. We also apply a rate limiter (via the Hammer library or a simple ETS counter) on file operations per user to prevent abuse (like a user triggering thousands of file reads per second)
raw.githubusercontent.com
. For instance, after 100 file operations in a minute, further operations could be rejected or delayed for that user
raw.githubusercontent.com
. This protects the system from being overloaded by any single client or misbehaving agent. By combining these measures – strict path checks, symlink guards, permission checks, caching, and watchers – the assistant safely supports editing and analyzing project files in real time. The sandbox ensures one project can’t access another’s files (if running on a shared server) and if the AI were to be prompted maliciously to reveal something like “open /etc/passwd”, it simply can’t – the validation will stop it. This gives confidence to teams that their code stays secure and the AI won’t leak or destroy it, and it allows multiple collaborators to benefit from the AI’s insights together.
Integrated Tools and Hooks for Extensibility
The assistant’s capabilities can be extended through a rich set of tools and a hook system for custom behaviors. As noted, we have defined numerous tools via the Tool DSL. These cover a wide range of developer needs. For example: a TaskDecomposer tool (which can be used outside of the full agent planning context, e.g., a user can manually invoke it to outline tasks)
raw.githubusercontent.com
, a CodeGenerator tool to generate code from a spec
raw.githubusercontent.com
, CodeRefactorer to improve or modify existing code
raw.githubusercontent.com
, CodeExplainer to produce documentation or explanations of code
raw.githubusercontent.com
, RepoSearch to search for a string or symbol across the project files
raw.githubusercontent.com
, TestGenerator and TestRunner for testing workflows
raw.githubusercontent.com
, DebugAssistant to analyze error logs or stack traces
raw.githubusercontent.com
, DependencyInspector to list dependencies and versions used
raw.githubusercontent.com
, DocFetcher to fetch online documentation (with caching so we don’t spam external docs)
raw.githubusercontent.com
, CodeFormatter to format code according to Elixir standards
raw.githubusercontent.com
, SemanticEmbedder to vectorize code for similarity search
raw.githubusercontent.com
, TodoExtractor to find TODO/FIXME comments
raw.githubusercontent.com
, CodeComparer to diff two code snippets or versions
raw.githubusercontent.com
, CodeNavigator to jump to definitions (could integrate with LSP or a tags file)
raw.githubusercontent.com
, CodeSummarizer to summarize a file/module
raw.githubusercontent.com
, PromptOptimizer to refine a prompt for better results
raw.githubusercontent.com
, ChangelogGenerator to generate a changelog from commit history or diff
raw.githubusercontent.com
, ProjectSummarizer to describe the project’s overall structure
raw.githubusercontent.com
, RegexExtractor to run regex queries on code
raw.githubusercontent.com
, TypeInferrer to suggest specs/types for functions
raw.githubusercontent.com
, FunctionMover to relocate functions between modules safely
raw.githubusercontent.com
, and CredoAnalyzer to run Credo lint checks
raw.githubusercontent.com
, among others. (There are 26 listed in our design docs, and more can be added as needed.) This comprehensive toolset gives the assistant “hands” to perform actions that pure text generation cannot, making it a true coding assistant rather than just a chatbot. To ensure these tools operate safely, each declares what capabilities it needs
raw.githubusercontent.com
raw.githubusercontent.com
. For example, a tool that writes to the file system will declare it needs :filesystem capability. Our Tool Executor will enforce that only tools allowed in the current context (maybe user-approved) can actually perform those ops. For instance, we might require explicit user consent before a tool can run a system command or make an HTTP request (capabilities like :shell or :network). This is configurable: an enterprise might disable the DocFetcher network tool for privacy, etc. The Hook System is a special extensibility feature that enables user-defined automations. Inspired by Anthropic’s Claude JSON hooks, it allows the assistant to run arbitrary user-provided scripts in response to certain events, in a controlled way
raw.githubusercontent.com
. We support hooks for events such as PreToolUse (before a tool executes), PostToolUse (after a tool finishes), OnMessage (when a user sends a message, before the AI responds), etc. The configuration for hooks is read from JSON files (to maximize compatibility with existing formats) in the project’s .rubber_duck directory and user’s home config. We merge global and project hook configs, similar to instructions, so that a user can have personal hooks that always run (perhaps to log something), and a project can have shared hooks (for team rules)
raw.githubusercontent.com
. A hook config specifies a command to run (it could be a shell script, an Elixir script, etc.) and which events to attach to, along with patterns to match which tool or command it applies to. For example, one could configure a PreToolUse hook on the RunTests tool that runs a script to reset the test database before any tests run. Or a PostToolUse hook on the CodeGenerator tool that runs a linter on the generated code. The assistant will execute these hook commands in the project’s working directory (so they can easily interact with the project files) and pass them a JSON payload via stdin describing the event (including fields like session_id, tool_name, tool_input, etc.)
raw.githubusercontent.com
raw.githubusercontent.com
. The hook can output JSON to stdout which the assistant will read. By convention, if the JSON output contains certain fields, we interpret them: for instance, "continue": false with a "stopReason" means the hook wants to halt the tool/action (maybe it found a policy violation)
raw.githubusercontent.com
. Or in a PostToolUse, the hook might output some analysis of the tool’s result which we could surface to the user. In PreToolUse, a hook could even modify the input (though that’s advanced). We maintain Claude-compatibility in that if users have existing Claude hook configs, our system should accept them (the JSON schema is the same)
raw.githubusercontent.com
raw.githubusercontent.com
. Under the hood, hooks are run via the Hooks Executor which is carefully sandboxed: it runs each hook with a time limit (e.g. 60 seconds)
raw.githubusercontent.com
raw.githubusercontent.com
, and we could run them in a separate OS process or a restricted OS user if security requires (so a malicious script can’t do much harm). The output is captured and parsed. If a hook blocks an action (e.g., returns “deny” for a PreToolUse), the assistant will respect that: it will not proceed to call the tool, and will inform the user (for example, “Action X was stopped by project hook: reason…”). This provides a powerful mechanism for governance – teams can enforce rules like “Do not allow the AI to make any code change without a peer review”, by implementing that in a hook. We integrate the hook system with Jido as well: whenever a relevant event happens, an internal signal is emitted (like signal(type="hook.PreToolUse", data={...})) which our HooksAgent can catch and handle by launching the hook command, rather than calling it synchronously. This way, hook execution doesn’t block the main flow – the agent can await the hook’s result or timeout. The HooksAgent coordinates loading the configurations (it will load or reload on file changes similar to instructions)
raw.githubusercontent.com
raw.githubusercontent.com
 and caching them. Pattern matching is done to decide which hooks apply (we support simple wildcard patterns or regex for matching tool names etc.)
raw.githubusercontent.com
raw.githubusercontent.com
. The combination of the extensive tool library and the hooks system makes the assistant highly customizable and extensible. Out of the box, it can do a lot (generate code, run tests, format, analyze, etc.), and users can add new tools in Elixir (thanks to our DSL) or add hooks to integrate external programs or enforce team-specific processes. As new needs arise, developers can script the assistant’s behavior without modifying the core – for example, integrate with an external API by writing a small command-line tool and calling it via a hook or custom tool. This design future-proofs the system and invites an ecosystem of community-contributed tools.
Self-Evaluation and Continuous Improvement
To maintain high answer quality and catch errors, the assistant uses both automated and semi-automated evaluation mechanisms. One aspect of this is the earlier mentioned CriticAgents (syntax, test, etc.) in the planning loop, which act as synchronous validators. But beyond that, we also incorporate an LLM-as-Judge approach in certain scenarios. Research has shown that an LLM can effectively critique or score another LLM’s output with surprisingly high agreement to human judgment
raw.githubusercontent.com
. We leverage this by having (optionally) a secondary model review the assistant’s code answers. For example, after producing a solution to a coding problem, we can prompt a judge model: “Evaluate this solution for correctness, style, etc., and score it 1-10 or identify issues.” This is done with carefully designed prompts (including chain-of-thought to have the judge reason)
raw.githubusercontent.com
. The judge’s feedback can be used in a few ways: If it identifies flaws, we can feed that back into a refinement loop (the Self-Correction Engine). Or, if we maintain a reward model, the scores can accumulate to inform which model/provider we use (e.g., if one provider’s outputs start scoring poorly, switch to another). We also integrate traditional evaluation metrics for code generation as part of our CI/CD and model fine-tuning cycle. For instance, we use Pass@k: when we test the assistant on a set of coding tasks (like HumanEval problems), we generate multiple attempts and see if at least one passes the tests
raw.githubusercontent.com
. This metric gives us a sense of how often the assistant can eventually get a correct answer if given retries. We also track exact match accuracy for simpler cases (did it produce the expected output exactly)
raw.githubusercontent.com
, though that’s usually too strict for code. We can compute CodeBLEU to compare structural similarity of generated code to reference solutions
raw.githubusercontent.com
raw.githubusercontent.com
, which is useful when there’s more than one correct solution. In runtime, after the assistant writes code, we can run the project’s test suite and measure how many tests passed – a functional correctness rate
raw.githubusercontent.com
. If less than 100%, the assistant knows something is wrong. We also consider compilation success as a quick check – did the code even compile? (If not, definitely an issue to fix)
raw.githubusercontent.com
raw.githubusercontent.com
. These automated metrics are used not only to improve the model (during training or model selection) but can also be surfaced to users as confidence indicators (e.g., “The solution passed 90% of our test cases” or “This code doesn’t compile, let me fix it”). During development of the assistant itself, we have a suite of unit and integration tests for its prompts and tools. We will regularly run these and possibly incorporate property-based tests (with StreamData) for certain functions (like the prompt template rendering or the file sandbox operations)
raw.githubusercontent.com
. The system is instrumented so that we can do automated evaluations of the AI’s performance on known tasks and measure things like average tokens used, success rate, etc., in a regression suite. For continuous improvement, we have hooks for incorporating user feedback. If a user rates an answer or indicates it was wrong, that can be logged and used to fine-tune the model or update the prompts. We can also do periodic retrospective analysis: have the assistant or another agent re-read past conversations to see if the advice given led to errors later (kind of an automated hindsight analysis). Advanced techniques like reinforcement learning from AI feedback (where a pool of agents debate or vote on the best answer) are also considered; e.g., using a multi-judge system where several variant outputs are judged and the best is chosen, as per recent research
raw.githubusercontent.com
raw.githubusercontent.com
. While these are experimental, our architecture (with pluggable Engine and Critic agents) is flexible enough to accommodate such improvements. For example, we could add a DebateAgent that generates multiple solutions and a JudgeAgent that picks one, integrating with the Engine Manager. Constitutional AI is another concept we integrate: we maintain a set of rules or a “constitution” that the AI should follow (these include ethical guidelines, but also coding style rules, etc.). We can use a ConstitutionalCritic that checks the AI’s output against these rules (for instance, “No use of deprecated functions” or “No leaking of credentials”) and either corrects it or refuses output that violates them
raw.githubusercontent.com
raw.githubusercontent.com
. This is akin to having an automated code reviewer always look over the AI’s shoulder. In summary, the assistant doesn’t just rely on the primary LLM’s immediate output. It has layers of self-evaluation: running code, judging with another model, comparing against known metrics, and iterating if needed. These are all important for building trust – users will know that when the assistant says “All tests passed” or “I’m 90% confident this is correct”, it’s because it actually verified those things, not just guessing. And in cases where the assistant is not confident, it will be transparent (maybe provide two approaches if unsure, or ask the user for clarification rather than hallucinate an answer).
Real-Time Feedback and Status Updates
To make the system’s operation transparent and user-friendly, it provides rich real-time status updates. We created a dedicated Phoenix Channel topic for status messages: "status:conversation:<id>" which clients can join in addition to the main conversation channel
raw.githubusercontent.com
. This channel broadcasts structured events about the internal state or actions of the assistant, separate from the assistant’s direct answers. For example, if the assistant starts using the RepoSearch tool, it might broadcast a status: “Searching the repository for ‘initialize_app’...” with category "tool". If it’s running a long plan, it can broadcast “Planning step 2 of 5: Generating tests” with category "workflow/progress". Errors are also reported here (distinct from the chat) – e.g., “Error: OpenAI API timed out, retrying with fallback model.” as an "error" status. Clients can choose which categories to subscribe to. The channel join can include a list of desired categories (engine, tool, workflow, progress, info, error, etc.)
raw.githubusercontent.com
raw.githubusercontent.com
. If a client only wants high-level info and errors, they can subscribe to just those. On the server side, we implemented a StatusBroadcaster (initially as a GenServer, later as an Agent process) that listens for internal status events and fans them out. In the original design, components would call a function like Status.update(conv_id, :engine, "Calling GPT-4") which would cast to a StatusBroadcaster GenServer that queued and batched messages, then broadcast via PubSub
raw.githubusercontent.com
raw.githubusercontent.com
. We have since refactored this into an Agent-based system: using Jido, we emit structured signals (events) for status updates, and a StatusBroadcastingAgent subscribes to all of them and handles the batching/broadcasting asynchronously
raw.githubusercontent.com
raw.githubusercontent.com
. The categories are consistent and extended (we added "conversation" and "analysis" as categories too for things like conversation-level notices or background analysis results)
raw.githubusercontent.com
. The broadcaster batches messages to avoid overloading clients. For example, if 100 file search results are coming, it might batch them into groups of 50 and send two messages rather than 100 tiny messages
raw.githubusercontent.com
raw.githubusercontent.com
. Each broadcast includes a list of messages (each with id, text, metadata) and a timestamp and possibly a batch_id
raw.githubusercontent.com
. The front-end can display them nicely, e.g., accumulating progress in a single progress bar if multiple related messages come. We also ensure ordering is preserved as much as possible by these batches. On the client side, we provided example JavaScript (or LiveView handling) that listens to "status_update" events on the status channel and updates the UI accordingly
raw.githubusercontent.com
raw.githubusercontent.com
. For instance, we might have an area in the IDE that shows “Status: Running tests (2/10 passed)...”. These status messages greatly improve UX, because the user is not left in the dark wondering what the AI is doing. It’s akin to the debug console in VSCode when you run something. Moreover, since multiple users can be in the session, everyone sees the status – so if Bob triggers a long-running action, Alice will see that it’s in progress. From an engineering standpoint, the status broadcasting is done via Phoenix PubSub to reach the channel processes subscribed
raw.githubusercontent.com
. We opted to broadcast on topics of form "status:<conversation_id>" with the category inside the payload, rather than separate topics for each category, for simplicity (the channel filters by category on join). The StatusBroadcastingAgent collects metrics such as how many messages it processed, how many dropped (if the queue was full)
raw.githubusercontent.com
raw.githubusercontent.com
, etc., which can be observed for debugging or tuning. We set reasonable queue limits (maybe 1000 messages) to prevent runaway memory if an agent goes haywire spamming status – if overflow, oldest messages drop and a warning is logged
raw.githubusercontent.com
raw.githubusercontent.com
. The system is designed to handle very high throughput – since status messages are mostly small and textual, and batching reduces overhead, we can comfortably deal with hundreds of updates per second, which is far above what we’d normally need
raw.githubusercontent.com
. An example of the status update usage: When an Engine starts processing a request, it calls Status.engine(conversation_id, "Using OpenAI GPT-4", %{model: "gpt-4", step: "start"})
raw.githubusercontent.com
. This appears on the client as maybe a small note “Assistant: (Engine) Initializing OpenAI engine [model: gpt-4]”. If an error occurs, like OpenAI returns an error, we do Status.error(conversation_id, "OpenAI API error", %{error: reason}) and the user will see that in red in their status feed
raw.githubusercontent.com
. Similarly, when the agent calls a tool: Status.tool(conversation_id, "Executing web search", %{query: "...")
raw.githubusercontent.com
. If the user finds these messages too verbose, they can unsubscribe from certain categories by sending a "unsubscribe_category" message over the channel (we allow dynamic sub/unsub)
raw.githubusercontent.com
raw.githubusercontent.com
. The status system, while not critical to functionality, greatly helps with transparency and trust. Users have a window into the AI’s “mind” – they see the steps it’s taking (which also helps them learn or debug, e.g., they see it ran tests and all tests passed, so they trust the code more
raw.githubusercontent.com
). It also helps us as developers debug the sequence of events in complex multi-agent scenarios. We’ve instrumented the status agent with telemetry as well, so we can monitor performance (e.g., how long batching takes, etc.)
raw.githubusercontent.com
.
Performance, Scalability, and Deployment
The system is built to be scalable and performant from day one. Elixir/OTP’s concurrency model allows us to handle many simultaneous conversations and tasks. Each conversation is a lightweight process, each agent is a process, each tool run, etc., so the work naturally gets distributed across CPU cores. In testing, a single Elixir node can easily handle hundreds of active conversations (depending on how heavy the LLM calls are, which are actually the bottleneck and mostly network-bound). The design supports clustering: by using Phoenix PubSub (which can be distributed via PG2 or Redis), Presence, and database-backed state, we can run multiple nodes to serve even more users
raw.githubusercontent.com
. For example, one node might handle conversations 1-100, another 101-200, etc., and they coordinate through Postgres and PubSub for things like broadcasting global announcements or ensuring a user’s requests go to the correct node. Ash’s resources and Phoenix channels are inherently cluster-ready (with PubSub), so no single node assumption is baked in. We employ numerous caching and optimization layers: in-memory ETS for frequently accessed data (recent messages, AST caches, instruction cache)
raw.githubusercontent.com
, persistent cache for vectors and long-term memory in Postgres (with proper indexing)
raw.githubusercontent.com
, and even the ability to use external caches like Redis for sharing cache across nodes. We also do smart batching of requests where possible: e.g., we vectorize 10 files in one batch call to the embedding API instead of individually
raw.githubusercontent.com
. For LLM API calls, if multiple similar requests come in, we could batch them (though that’s advanced and requires identical prompts). The agent planning system can run subtasks in parallel when independence is clear, cutting down total time for complex jobs
raw.githubusercontent.com
. On the LLM provider side, we maintain connection pools or reuse to avoid re-init overhead, and use asynchronous calls heavily so we don’t block on network I/O. We also support streaming compression like using binary WebSocket frames or messagepack to reduce payload sizes for large code (some frontends might accept gzipped responses, etc., which can be enabled for large messages to not choke slower connections). Fault-tolerance is a core: if any component crashes, the supervisors will restart it
raw.githubusercontent.com
. For instance, if the LLM Service GenServer crashes (maybe due to an uncaught exception parsing a response), it will restart in milliseconds and the conversation processes will simply retry their call. The system is designed such that most tasks are either short or can be broken into chunks that can be retried idempotently. We also incorporate circuit breakers on external services – e.g., if OpenAI is failing repeatedly, we trip a breaker and route all requests to an alternative model for a few minutes
raw.githubusercontent.com
. This prevents cascading failures and timeout pile-ups. Security considerations include authentication on all channels (using Phoenix Token or session auth), end-to-end encryption (if deployed in a web environment, use WSS/HTTPS), and strict authorization on actions (a user can only access their org’s projects, etc.). We use Phoenix’s built-in CSRF and parameter sanitization for any HTTP endpoints. The LLM output is also post-processed to ensure it doesn’t contain disallowed content – our instructions to the model include not revealing sensitive info, but we also double-check outputs for any obvious policy violations (for example, using a simple content filter or again an LLM-based moderator). This is especially important if the assistant is ever connected to production environments or could potentially be prompted with something like “Drop the database” – our governance (via hooks or built-in checks) would intercept such destructive commands unless explicitly allowed by the user. For deployment, the system can run as a Phoenix application. We containerize it with all needed dependencies (the language model clients, etc.). One can deploy it on a server or cloud instance. It supports both a single-user mode (e.g., a developer running it locally with just their projects) and a multi-tenant mode (e.g., a SaaS where many users’ data separated by org). Phoenix Channels and LiveView allow us to easily integrate into VSCode or a web IDE – we just need a client library (JavaScript or ElixirLS plugin) to interact with the channels. We anticipate providing thin client adapters for popular IDEs that connect to the Phoenix backend via WebSocket. Logging and monitoring are set up such that each request or conversation has a trace ID. We log important events (like “LLM request to OpenAI started/ended”, “File X modified by AI”, “Tool Y executed”) which can be reviewed later
raw.githubusercontent.com
raw.githubusercontent.com
. These logs help in auditing what the AI did, which is useful for debugging and for user trust (some orgs might require a log of all code changes the AI proposed). We can even output a summary at the end of a plan: e.g., “Plan completed: 3 files changed, 2 tests added.” We have also kept future enhancements in mind: the architecture can accommodate a switch to more local models (we could run an LLM inside the server via NX or an external GPU server – we would treat it as another provider in the LLM Service). The agent and tool approach is model-agnostic, so as research improves (say GPT-5 or a new planning algorithm), we can plugin without redesign. The separation of concerns (conversation vs planning vs tools vs memory) follows the principle of modular design
raw.githubusercontent.com
raw.githubusercontent.com
, making it easier to maintain and evolve each part. In conclusion, this system design marries advanced AI capabilities (reasoning, planning, self-correction, etc.) with solid software engineering (Elixir’s concurrency, Ash’s type-safe modeling, Phoenix’s real-time communication). It provides a comprehensive solution for an AI coding assistant that is not only powerful in terms of intelligence but also reliable, transparent, and aligned with developer needs
raw.githubusercontent.com
raw.githubusercontent.com
. By broadcasting its status and reasoning, integrating with version control and tests, and respecting project conventions through instructions, it becomes a natural extension of the developer’s environment – effectively a smart “rubber duck” that talks back with wisdom and keeps the whole team in the loop. The design is ready to support collaborative development, scale to big projects, and continuously improve as it learns from more data and feedback. It sets a foundation that can keep incorporating the latest in AI research (like new prompt strategies or multi-modal inputs in the future) without a complete overhaul, thanks to the agentic, modular architecture.
