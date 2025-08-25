defmodule RubberDuck.Verdict.JudgeUnits.JudgeUnitBehaviour do
  @moduledoc """
  Behaviour definition for Verdict framework judge units.
  
  Defines the standard interface that all judge units must implement
  for consistent evaluation capabilities and pipeline orchestration.
  """
  
  @doc """
  Evaluate code using this judge unit.
  
  ## Parameters
  - `code` - The code to evaluate
  - `criteria` - Evaluation criteria
  - `config` - Judge unit configuration
  
  ## Returns
  - `{:ok, evaluation_result}` - Successful evaluation with structured results
  - `{:error, reason}` - Evaluation failed with detailed error reason
  """
  @callback evaluate(code :: String.t(), criteria :: String.t(), config :: map()) :: 
    {:ok, map()} | {:error, term()}
  
  @doc """
  Get the capabilities and configuration requirements for this judge unit.
  
  ## Returns
  Map containing:
  - `unit_type` - Type identifier for this judge unit
  - `supported_criteria` - List of evaluation criteria this unit can handle
  - `input_types` - Types of input this unit can process
  - `output_format` - Format of evaluation results
  - `cost_tier` - Relative cost tier (:low, :medium, :high)
  - `typical_latency_ms` - Expected evaluation latency
  - `confidence_calibrated` - Whether confidence scores are well-calibrated
  """
  @callback get_capabilities() :: map()
  
  @doc """
  Check if this judge unit can handle the specified evaluation type and configuration.
  
  ## Parameters
  - `evaluation_type` - Type of evaluation to perform
  - `config` - Configuration for the evaluation
  
  ## Returns
  - `true` - This judge unit can handle the evaluation
  - `false` - This judge unit cannot handle the evaluation
  """
  @callback can_evaluate?(evaluation_type :: atom(), config :: map()) :: boolean()
end