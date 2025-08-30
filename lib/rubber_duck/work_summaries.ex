defmodule RubberDuck.WorkSummaries do
  @moduledoc """
  Work Summaries domain for coding assistant work tracking and analysis.

  This domain manages the persistence and retrieval of coding assistant work summaries,
  providing comprehensive tracking of development activities, performance metrics,
  and historical analysis capabilities.

  Domain Resources:
  - WorkSummary: Core summary content with metadata and timestamps
  - CodingAssistant: Assistant profiles and capability tracking
  - WorkSession: Grouping of related summaries into logical sessions

  Integration Points:
  - Phase 2 LLM Orchestration: Uses existing provider skills for summary generation
  - Ash Framework: Follows established domain and resource patterns
  - Jido Skills: Integrates with Skills registry for summary generation actions
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource RubberDuck.WorkSummaries.Resources.WorkSummary
    resource RubberDuck.WorkSummaries.Resources.CodingAssistant
    resource RubberDuck.WorkSummaries.Resources.WorkSession
  end

  authorization do
    authorize :when_requested
  end
end
