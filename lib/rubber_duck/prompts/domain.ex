defmodule RubberDuck.Prompts.Domain do
  @moduledoc """
  Prompts domain for hierarchical prompt management system.

  Provides comprehensive prompt management with three-tier hierarchy (System/Project/User),
  versioning, analytics, and multi-tenant security. Integrates with existing LLM
  orchestration and Reactor workflow systems for seamless prompt composition.

  Domain Resources:
  - **Prompt**: Core prompt resource with hierarchical architecture and security
  - **PromptVersion**: Version tracking with history and rollback capabilities
  - **PromptUsage**: Usage analytics with performance metrics and pattern analysis
  - **PromptCategory**: Category organization with hierarchical structure and access control

  Key Features:
  - Three-tier hierarchical prompt system (System → Project → User)
  - Comprehensive versioning with append-only audit trails
  - Multi-tenant security using PostgreSQL Row-Level Security
  - Performance optimization with intelligent caching strategies
  - Integration with existing authentication and authorization systems
  """

  use Ash.Domain

  resources do
    resource RubberDuck.Prompts.Resources.Prompt
    resource RubberDuck.Prompts.Resources.PromptVersion
    resource RubberDuck.Prompts.Resources.PromptUsage
    resource RubberDuck.Prompts.Resources.PromptCategory
  end

  authorization do
    authorize :by_default
  end

end
