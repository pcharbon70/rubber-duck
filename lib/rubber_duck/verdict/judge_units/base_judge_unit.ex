defmodule RubberDuck.Verdict.JudgeUnits.BaseJudgeUnit do
  @moduledoc """
  Base judge unit for Verdict framework evaluations.
  
  Provides the foundational evaluation capabilities and standard interface
  for all judge units. Implements the core evaluation logic with prompt
  engineering, response parsing, and result validation.
  """
  
  require Logger
  
  @behaviour RubberDuck.Verdict.JudgeUnits.JudgeUnitBehaviour
  
  @default_prompt_template """
  You are an expert code reviewer. Evaluate the following code based on the specified criteria.
  
  Code to evaluate:
  ```elixir
  <%= code %>
  ```
  
  Evaluation criteria: <%= criteria %>
  
  Please provide:
  1. Overall score (0.0 to 1.0)
  2. Specific issues found
  3. Recommendations for improvement
  4. Confidence in your assessment (0.0 to 1.0)
  
  Respond in the following JSON format:
  {
    "score": <score>,
    "confidence": <confidence>,
    "issues": ["issue1", "issue2"],
    "recommendations": ["rec1", "rec2"],
    "reasoning": "Brief explanation of assessment"
  }
  """
  
  @doc """
  Evaluate code using this judge unit.
  
  ## Parameters
  - `code` - The code to evaluate
  - `criteria` - Evaluation criteria
  - `config` - Judge unit configuration
  
  ## Returns
  - `{:ok, evaluation_result}` - Successful evaluation
  - `{:error, reason}` - Evaluation failed
  """
  @spec evaluate(code :: String.t(), criteria :: String.t(), config :: map()) :: 
    {:ok, map()} | {:error, term()}
  def evaluate(code, criteria, config \\ %{}) do
    case build_evaluation_prompt(code, criteria, config) do
      {:ok, prompt} ->
        case execute_llm_request(prompt, config) do
          {:ok, response} -> parse_evaluation_response(response, config)
          error -> error
        end
      
      error -> error
    end
  end
  
  @doc """
  Get the capabilities and configuration for this judge unit.
  """
  @spec get_capabilities() :: map()
  def get_capabilities do
    %{
      unit_type: :base_judge,
      supported_criteria: [:quality, :security, :performance, :maintainability, :best_practices],
      input_types: [:elixir_code, :text],
      output_format: :structured_assessment,
      cost_tier: :medium,
      typical_latency_ms: 2000,
      confidence_calibrated: true
    }
  end
  
  @doc """
  Validate that this judge unit can handle the specified evaluation.
  """
  @spec can_evaluate?(evaluation_type :: atom(), config :: map()) :: boolean()
  def can_evaluate?(evaluation_type, config \\ %{}) do
    capabilities = get_capabilities()
    
    evaluation_type in capabilities.supported_criteria and
    validate_config_requirements(config)
  end
  
  ## Private Functions
  
  defp build_evaluation_prompt(code, criteria, config) do
    template = Map.get(config, :prompt_template, @default_prompt_template)
    
    try do
      prompt = EEx.eval_string(template, code: code, criteria: criteria)
      {:ok, prompt}
    rescue
      error -> {:error, "Failed to build prompt: #{inspect(error)}"}
    end
  end
  
  defp execute_llm_request(prompt, config) do
    model = Map.get(config, :model, "gpt-4o-mini")
    max_tokens = Map.get(config, :max_tokens, 1000)
    temperature = Map.get(config, :temperature, 0.1)
    
    # Mock LLM request for now
    # In real implementation, this would make actual API calls
    case simulate_llm_response(prompt, model, max_tokens, temperature) do
      {:ok, response} -> {:ok, response}
      error -> error
    end
  end
  
  defp simulate_llm_response(_prompt, model, _max_tokens, _temperature) do
    # Simulate different response patterns based on model
    case model do
      "gpt-4o-mini" ->
        {:ok, %{
          response: """
          {
            "score": 0.75,
            "confidence": 0.8,
            "issues": ["Variable naming could be improved", "Missing documentation"],
            "recommendations": ["Use more descriptive variable names", "Add module documentation"],
            "reasoning": "Code is functional but could benefit from better naming and documentation"
          }
          """,
          model_used: model,
          tokens_used: 450,
          latency_ms: 1200
        }}
      
      "gpt-4o" ->
        {:ok, %{
          response: """
          {
            "score": 0.82,
            "confidence": 0.9,
            "issues": ["Consider using guards for input validation", "Function could be split for better readability"],
            "recommendations": ["Add input validation with guards", "Extract helper function for complex logic"],
            "reasoning": "Well-structured code with minor improvements possible for robustness and readability"
          }
          """,
          model_used: model,
          tokens_used: 680,
          latency_ms: 2100
        }}
      
      _ ->
        {:error, "Unsupported model: #{model}"}
    end
  end
  
  defp parse_evaluation_response(response, config) do
    try do
      case Jason.decode(response.response) do
        {:ok, parsed_result} ->
          # Validate and normalize the result
          case validate_evaluation_result(parsed_result) do
            {:ok, validated_result} ->
              final_result = Map.merge(validated_result, %{
                model_used: response.model_used,
                tokens_used: response.tokens_used,
                latency_ms: response.latency_ms,
                judge_unit: "base_judge",
                timestamp: DateTime.utc_now()
              })
              
              {:ok, final_result}
            
            error -> error
          end
        
        {:error, reason} ->
          {:error, "Failed to parse LLM response: #{inspect(reason)}"}
      end
    rescue
      error -> {:error, "Response parsing failed: #{inspect(error)}"}
    end
  end
  
  defp validate_evaluation_result(result) do
    required_fields = ["score", "confidence", "issues", "recommendations", "reasoning"]
    
    missing_fields = Enum.filter(required_fields, fn field ->
      not Map.has_key?(result, field)
    end)
    
    cond do
      not Enum.empty?(missing_fields) ->
        {:error, "Missing required fields: #{Enum.join(missing_fields, ", ")}"}
      
      not is_number(result["score"]) or result["score"] < 0 or result["score"] > 1 ->
        {:error, "Score must be a number between 0.0 and 1.0"}
      
      not is_number(result["confidence"]) or result["confidence"] < 0 or result["confidence"] > 1 ->
        {:error, "Confidence must be a number between 0.0 and 1.0"}
      
      not is_list(result["issues"]) ->
        {:error, "Issues must be a list"}
      
      not is_list(result["recommendations"]) ->
        {:error, "Recommendations must be a list"}
      
      true ->
        {:ok, %{
          score: result["score"],
          confidence: result["confidence"],
          issues: result["issues"],
          recommendations: result["recommendations"],
          reasoning: result["reasoning"]
        }}
    end
  end
  
  defp validate_config_requirements(config) do
    # Basic configuration validation
    model = Map.get(config, :model, "gpt-4o-mini")
    max_tokens = Map.get(config, :max_tokens, 1000)
    
    model in ["gpt-4o-mini", "gpt-4o", "claude-3-haiku", "claude-3-sonnet"] and
    is_integer(max_tokens) and max_tokens > 0 and max_tokens <= 8192
  end
end