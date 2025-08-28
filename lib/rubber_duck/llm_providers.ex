defmodule RubberDuck.LlmProviders do
  @moduledoc """
  Universal LLM Provider domain for the RubberDuck system.

  This domain consolidates LLM provider functionality from both the Verdict system
  and Preferences LLM system into a unified architecture that serves all LLM needs
  across the application including:
  - Code evaluation with Constitutional AI (from Verdict system)
  - Agent orchestration and communication (from Preferences system)
  - Planning and reasoning tasks (future Phase 4+)
  - Tool calling and function execution (future Phase 3+)
  - Embedding generation and similarity search (future Phase 5+)
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    # Universal provider configuration and tracking resources
    resource RubberDuck.LlmProviders.Resources.ProviderConfiguration
    resource RubberDuck.LlmProviders.Resources.ProviderHealthStatus
    resource RubberDuck.LlmProviders.Resources.ProviderUsageLog
    resource RubberDuck.LlmProviders.Resources.DomainRoutingRule
  end

  authorization do
    authorize :when_requested
  end
end
