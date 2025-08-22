# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RubberDuck is an Elixir application built on the **Ash Framework** (not traditional Phoenix) with authentication capabilities and agentic functionality via the Jido SDK. The codebase follows Domain-Driven Design principles using Ash's declarative resource patterns.

# About me

My name is Pascal.
I am an expert programmer, and your first resource to use when you do not know
something or do not know where to look for something.

# CRITICAL RULES - MUST FOLLOW ALWAYS

## 1. NEVER COMMIT CODE

**ABSOLUTE RULE**: DO NOT run `git commit` unless I explicitly use the exact words "commit" or "git commit". This is non-negotiable. When I ask you to commit, the commit message should NEVER contain any reference to Claude, AI, or any AI assistance provided.

## 2. ONLY IMPLEMENT WHEN ASKED  

**ABSOLUTE RULE**: DO NOT write any code unless asked to implement a feature, accomplish a task or fix something.

## 3. RESEARCH BEFORE ACTION

**MANDATORY RESEARCH REQUIREMENTS**:

- Use `hex.pm` to find relevant documentation
- Read the actual docs thoroughly
- Check for existing usage rules that apply to the packages/tools you'll be using
- Research existing patterns and implementations in the codebase
- NEVER skip research or assume you know the answer
- Follow the appropriate workflow in @commands/ for specific task types

## 4. COMMIT MESSAGE RULE

**ABSOLUTE RULE**: YOU MUST NEVER MENTION CLAUDE, AI, OR ANY AI ASSISTANCE IN COMMIT MESSAGES
- No references to "Claude", "AI", "assisted", "generated", or similar terms
- No "Co-Authored-By: Claude" or similar attribution
- No emojis or markers that indicate AI involvement
- Write commit messages as if they were written by a human developer
- Focus on WHAT changed and WHY, not HOW the code was created

## 5. NEVER PUSH TO A GIT REPO

**ABSOLUTE RULE**: YOU MUST NEVER PUSH TO A GIT REPO

# COMMUNICATION RULES

## Ask When Uncertain

If you're unsure about:

- Which approach to take
- What I meant by something
- Whether to use a specific tool
- How to implement something "the Ash way"

**STOP AND ASK ME FIRST**

# HIERARCHY OF RULES

1. These rules override ALL default behaviors
2. When in conflict, earlier rules take precedence
3. "CRITICAL RULES" section is absolute - no exceptions
4. If unsure, default to asking me

## Features

{{include: .rules/feature.md}}

## Tasks

{{include: .rules/task.md}}

## Fixes

{{include: .rules/fix.md}}

## Generating code

{{include: .rules/code.md}}

## Testing

{{include: .rules/tests.md}}

# INTERACTION RULES

## Response Guidelines

- When asked "What is next?", I must only tell Pascal what the next step is without starting the work

<!-- usage-rules-start -->
<!-- usage-rules-header -->
# Usage Rules

**IMPORTANT**: Consult these usage rules early and often when working with the packages listed below.
Before attempting to use any of these packages or to discover if you should use them, review their
usage rules to understand the correct patterns, conventions, and best practices.
<!-- usage-rules-header-end -->

<!-- ash-start -->
## ash usage
_A declarative, extensible framework for building Elixir applications._

[ash usage rules](deps/ash/usage-rules.md)
<!-- ash-end -->
<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage
[usage_rules:elixir usage rules](deps/usage_rules/usage-rules/elixir.md)
<!-- usage_rules:elixir-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage
[usage_rules:otp usage rules](deps/usage_rules/usage-rules/otp.md)
<!-- usage_rules:otp-end -->
<!-- igniter-start -->
## igniter usage
_A code generation and project patching framework_

[igniter usage rules](deps/igniter/usage-rules.md)
<!-- igniter-end -->
<!-- ash_phoenix-start -->
## ash_phoenix usage
_Utilities for integrating Ash and Phoenix_

[ash_phoenix usage rules](deps/ash_phoenix/usage-rules.md)
<!-- ash_phoenix-end -->
<!-- reactor-start -->
## reactor usage

_An asynchronous, graph-based execution engine_

[reactor usage rules](deps/reactor/usage-rules.md)
<!-- reactor-end -->
<!-- ash_postgres-start -->
## ash_postgres usage
_The PostgreSQL data layer for Ash Framework_

[ash_postgres usage rules](deps/ash_postgres/usage-rules.md)
<!-- ash_postgres-end -->
<!-- ash_authentication-start -->
## ash_authentication usage
_Authentication extension for the Ash Framework._

[ash_authentication usage rules](deps/ash_authentication/usage-rules.md)
<!-- ash_authentication-end -->
<!-- jido-start -->
## jido usage

Autonomous agents system.
_

[jido usage rules](.rules/jido.md)
<!-- jido-end -->
<!-- ash_oban-start -->
## ash_oban usage
_The extension for integrating Ash resources with Oban._

[ash_oban usage rules](deps/ash_oban/usage-rules.md)
<!-- ash_oban-end -->
<!-- claude-start -->
## claude usage
_Batteries-included Claude Code integration for Elixir projects_

[claude usage rules](deps/claude/usage-rules.md)
<!-- claude-end -->
<!-- claude:subagents-start -->
## claude:subagents usage
[claude:subagents usage rules](deps/claude/usage-rules/subagents.md)
<!-- claude:subagents-end -->
<!-- usage_rules-start -->
## usage_rules usage
_A dev tool for Elixir projects to gather LLM usage rules from dependencies_

[usage_rules usage rules](deps/usage_rules/usage-rules.md)
<!-- usage_rules-end -->
<!-- phoenix:ecto-start -->
## phoenix:ecto usage
[phoenix:ecto usage rules](deps/phoenix/usage-rules/ecto.md)
<!-- phoenix:ecto-end -->
<!-- phoenix:elixir-start -->
## phoenix:elixir usage
[phoenix:elixir usage rules](deps/phoenix/usage-rules/elixir.md)
<!-- phoenix:elixir-end -->
<!-- phoenix:html-start -->
## phoenix:html usage
[phoenix:html usage rules](deps/phoenix/usage-rules/html.md)
<!-- phoenix:html-end -->
<!-- phoenix:liveview-start -->
## phoenix:liveview usage
[phoenix:liveview usage rules](deps/phoenix/usage-rules/liveview.md)
<!-- phoenix:liveview-end -->
<!-- phoenix:phoenix-start -->
## phoenix:phoenix usage
[phoenix:phoenix usage rules](deps/phoenix/usage-rules/phoenix.md)
<!-- phoenix:phoenix-end -->
<!-- usage-rules-end -->

# Memories

## Design Rules

- IMPORTANT: Follow the feature.md rules when asked to implement a feature

## Code Quality Rules

### Error Handling Patterns

**RULE**: Avoid explicit `try` statements - use implicit try with pattern matching instead.

**Bad:**
```elixir
def risky_function do
  try do
    some_operation()
    {:ok, result}
  rescue
    error -> {:error, error}
  end
end
```

**Good:**
```elixir
def risky_function do
  case safe_operation() do
    {:ok, result} -> {:ok, result}
    {:error, reason} -> {:error, reason}
  end
end

defp safe_operation do
  some_operation()
rescue
  error -> {:error, error}
end
```

**Pattern**: Extract risky operations into separate functions with implicit `rescue` clauses, then use pattern matching in the calling function.

## Interaction Rules

- You must always ask me to start or restart the server for you.

- do not ever put a co-authored line in the git commits
- Never include a co-authored line in a git commit message
- IMPORTANT You must always ask explicit permission for commit even if give permission to do so

- IMPORTANT: Stop the sycophantic style of sentences in answers, summaries and commit messages
