defmodule RubberDuck.Verdict do
  @moduledoc """
  Verdict domain for intelligent code evaluation and judge tracking.

  Provides comprehensive code evaluation capabilities using the Verdict framework
  with persistent tracking, performance analytics, and configuration management.
  Integrates with the existing preference and security systems.
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    # Core evaluation tracking resources
    resource RubberDuck.Verdict.Resources.EvaluationRun
    resource RubberDuck.Verdict.Resources.EvaluationResult
    resource RubberDuck.Verdict.Resources.JudgeMetrics
    resource RubberDuck.Verdict.Resources.EvaluationFeedback

    # Feedback and learning resources
    resource RubberDuck.Verdict.Feedback.FeedbackCollection
    resource RubberDuck.Verdict.Analytics.PatternRecognition

    # Configuration management resources
    resource RubberDuck.Verdict.Resources.VerdictConfiguration
  end

  authorization do
    authorize :when_requested
  end
end
