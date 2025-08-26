defmodule RubberDuck.Agents do
  @moduledoc """
  Ash domain for the Judge Agent System coordination and management.

  This domain manages multi-agent coordination sessions, individual agent
  evaluation results, and inter-agent communication for the Verdict framework's
  intelligent code evaluation system.
  """

  use Ash.Domain

  resources do
    resource RubberDuck.Agents.CoordinationSession
    resource RubberDuck.Agents.AgentEvaluationResult
    resource RubberDuck.Agents.CoordinationMessage
  end
end
