defmodule RubberDuck.Verdict.Providers.ProviderInterface do
  @moduledoc """
  Unified provider interface for all AI evaluation providers.
  
  This behaviour defines the contract that all AI providers (OpenAI, Anthropic, 
  Ollama, etc.) must implement to integrate with the Verdict framework.
  
  The interface provides:
  - Standardized evaluation methods across all providers
  - Unified response format for consistent processing
  - Provider capability discovery and health monitoring
  - Cost tracking and rate limiting integration
  - Streaming evaluation support for real-time feedback
  """
  
  @type provider_config :: %{
    optional(atom()) => any(),
    api_key: String.t() | nil,
    endpoint: String.t() | nil,
    models: %{atom() => String.t()},
    rate_limits: map(),
    cost_limits: map(),
    streaming: map(),
    health_check: map()
  }
  
  @type evaluation_request :: %{
    code: String.t(),
    evaluation_type: atom(),
    criteria: map(),
    context: map(),
    quality_threshold: float(),
    max_tokens: integer(),
    streaming: boolean(),
    metadata: map()
  }
  
  @type evaluation_response :: %{
    provider: atom(),
    model: String.t(),
    success: boolean(),
    score: float(),
    confidence: float(),
    issues: list(map()),
    recommendations: list(String.t()),
    reasoning: String.t(),
    cost_usd: float(),
    tokens_used: integer(),
    response_time_ms: integer(),
    metadata: map()
  }
  
  @type provider_capabilities :: %{
    supports_streaming: boolean(),
    supports_function_calling: boolean(),
    max_context_tokens: integer(),
    supported_languages: list(String.t()),
    evaluation_types: list(atom()),
    cost_per_1k_tokens: %{String.t() => float()},
    rate_limits: map()
  }
  
  @type provider_health :: %{
    status: :healthy | :degraded | :unhealthy,
    success_rate: float(),
    avg_response_time_ms: integer(),
    last_check: DateTime.t(),
    error_count: integer(),
    availability_percentage: float()
  }
  
  # Core provider contract
  
  @doc """
  Initialize the provider with configuration.
  
  Returns provider state for subsequent operations.
  """
  @callback initialize(config :: provider_config()) :: 
    {:ok, state :: any()} | {:error, reason :: String.t()}
  
  @doc """
  Perform code evaluation using this provider.
  
  Returns evaluation results in standardized format.
  """
  @callback evaluate_code(
    state :: any(), 
    request :: evaluation_request()
  ) :: {:ok, evaluation_response()} | {:error, reason :: String.t()}
  
  @doc """
  Start streaming evaluation with real-time updates.
  
  Returns stream of partial results until completion.
  """
  @callback evaluate_code_streaming(
    state :: any(),
    request :: evaluation_request(),
    callback :: (map() -> any())
  ) :: {:ok, evaluation_response()} | {:error, reason :: String.t()}
  
  @doc """
  Get provider capabilities and supported features.
  """
  @callback get_capabilities(state :: any()) :: 
    {:ok, provider_capabilities()} | {:error, reason :: String.t()}
  
  @doc """
  Perform health check for this provider.
  """
  @callback health_check(state :: any()) :: 
    {:ok, provider_health()} | {:error, reason :: String.t()}
  
  @doc """
  Estimate cost for evaluation request before execution.
  """
  @callback estimate_cost(
    state :: any(),
    request :: evaluation_request()
  ) :: {:ok, cost_estimate :: float()} | {:error, reason :: String.t()}
  
  @doc """
  Clean up provider resources.
  """
  @callback terminate(state :: any()) :: :ok
  
  # Helper functions for provider implementations
  
  @doc """
  Validate evaluation request structure.
  """
  def validate_evaluation_request(request) when is_map(request) do
    required_fields = [:code, :evaluation_type, :criteria]
    missing_fields = Enum.filter(required_fields, &(!Map.has_key?(request, &1)))
    
    case missing_fields do
      [] -> validate_request_values(request)
      fields -> {:error, "Missing required fields: #{inspect(fields)}"}
    end
  end
  
  def validate_evaluation_request(_), do: {:error, "Request must be a map"}
  
  defp validate_request_values(request) do
    with :ok <- validate_code_field(request),
         :ok <- validate_evaluation_type(request),
         :ok <- validate_criteria_field(request),
         :ok <- validate_thresholds(request) do
      :ok
    else
      error -> error
    end
  end
  
  defp validate_code_field(request) do
    case Map.get(request, :code) do
      code when is_binary(code) and byte_size(code) > 0 -> :ok
      _ -> {:error, "Code field must be a non-empty string"}
    end
  end
  
  defp validate_evaluation_type(request) do
    case Map.get(request, :evaluation_type) do
      type when type in [:quality, :security, :performance, :maintainability, :style] -> :ok
      _ -> {:error, "Invalid evaluation type"}
    end
  end
  
  defp validate_criteria_field(request) do
    case Map.get(request, :criteria) do
      criteria when is_map(criteria) -> :ok
      _ -> {:error, "Criteria must be a map"}
    end
  end
  
  defp validate_thresholds(request) do
    quality_threshold = Map.get(request, :quality_threshold, 0.8)
    max_tokens = Map.get(request, :max_tokens, 1500)
    
    cond do
      not is_number(quality_threshold) or quality_threshold < 0 or quality_threshold > 1 ->
        {:error, "Quality threshold must be between 0 and 1"}
      not is_integer(max_tokens) or max_tokens < 1 or max_tokens > 100_000 ->
        {:error, "Max tokens must be between 1 and 100,000"}
      true -> :ok
    end
  end
  
  @doc """
  Standardize evaluation response format across providers.
  """
  def standardize_response(provider_response, provider_type, model, metadata \\ %{}) do
    %{
      provider: provider_type,
      model: model,
      success: Map.get(provider_response, :success, false),
      score: Map.get(provider_response, :score, 0.0),
      confidence: Map.get(provider_response, :confidence, 0.0),
      issues: Map.get(provider_response, :issues, []),
      recommendations: Map.get(provider_response, :recommendations, []),
      reasoning: Map.get(provider_response, :reasoning, ""),
      cost_usd: Map.get(provider_response, :cost_usd, 0.0),
      tokens_used: Map.get(provider_response, :tokens_used, 0),
      response_time_ms: Map.get(provider_response, :response_time_ms, 0),
      metadata: Map.merge(metadata, Map.get(provider_response, :metadata, %{}))
    }
  end
  
  @doc """
  Calculate cost estimate based on token count and provider pricing.
  """
  def calculate_cost_estimate(token_count, cost_per_1k_tokens) when is_integer(token_count) and is_number(cost_per_1k_tokens) do
    (token_count / 1000) * cost_per_1k_tokens
  end
  
  def calculate_cost_estimate(_, _), do: {:error, "Invalid token count or cost rate"}
  
  @doc """
  Parse provider health status into standardized format.
  """
  def parse_health_status(response_time_ms, success_rate, error_count \\ 0) do
    status = cond do
      success_rate >= 0.98 and response_time_ms < 2000 -> :healthy
      success_rate >= 0.90 and response_time_ms < 5000 -> :degraded  
      true -> :unhealthy
    end
    
    %{
      status: status,
      success_rate: success_rate,
      avg_response_time_ms: response_time_ms,
      last_check: DateTime.utc_now(),
      error_count: error_count,
      availability_percentage: success_rate * 100
    }
  end
  
  @doc """
  Build evaluation prompt for specific provider and evaluation type.
  """
  def build_evaluation_prompt(code, evaluation_type, criteria, provider_type) do
    base_prompt = get_base_prompt(evaluation_type)
    criteria_instructions = build_criteria_instructions(criteria)
    provider_specific_prompt = adapt_prompt_for_provider(base_prompt, provider_type)
    
    """
    #{provider_specific_prompt}
    
    #{criteria_instructions}
    
    Please evaluate the following code:
    
    ```
    #{code}
    ```
    
    Provide your evaluation in JSON format with:
    - overall_score (0-1 float)
    - confidence (0-1 float) 
    - issues (array of issue objects)
    - recommendations (array of strings)
    - reasoning (detailed explanation string)
    """
  end
  
  defp get_base_prompt(evaluation_type) do
    case evaluation_type do
      :quality ->
        "You are an expert code reviewer evaluating code quality including correctness, maintainability, and best practices."
      
      :security ->
        "You are a security expert analyzing code for vulnerabilities, security risks, and security best practices."
      
      :performance ->
        "You are a performance specialist evaluating code efficiency, resource usage, and scalability characteristics."
      
      :maintainability ->
        "You are a software architecture expert assessing code maintainability, readability, and long-term sustainability."
      
      :style ->
        "You are a code style expert reviewing formatting, naming conventions, and adherence to language idioms."
      
      _ ->
        "You are an experienced software engineer performing comprehensive code evaluation."
    end
  end
  
  defp build_criteria_instructions(criteria) when is_map(criteria) do
    instructions = criteria
    |> Enum.map(fn {criterion, weight} ->
      "- #{criterion}: #{Float.round(weight * 100, 1)}% weight"
    end)
    |> Enum.join("\n")
    
    "Evaluation criteria and weights:\n#{instructions}"
  end
  
  defp build_criteria_instructions(_), do: "Use standard evaluation criteria."
  
  defp adapt_prompt_for_provider(prompt, provider_type) do
    case provider_type do
      :openai ->
        prompt <> "\n\nUse your comprehensive training to provide detailed, actionable feedback."
      
      :anthropic ->
        prompt <> "\n\nApply Constitutional AI principles to ensure helpful, harmless, and honest evaluation."
      
      :ollama ->
        prompt <> "\n\nFocus on clear, concise analysis appropriate for local model capabilities."
      
      _ ->
        prompt
    end
  end
  
  @doc """
  Extract structured evaluation from provider response.
  """
  def extract_evaluation_result(response_text) when is_binary(response_text) do
    # Try to extract JSON first
    case Jason.decode(response_text) do
      {:ok, %{} = json_result} ->
        {:ok, json_result}
      
      {:error, _} ->
        # Fall back to text parsing
        extract_from_text(response_text)
    end
  end
  
  def extract_evaluation_result(_), do: {:error, "Invalid response format"}
  
  defp extract_from_text(text) do
    # Simple text parsing fallback
    lines = String.split(text, "\n")
    
    score = extract_score_from_text(lines)
    confidence = extract_confidence_from_text(lines)
    reasoning = extract_reasoning_from_text(lines)
    
    {:ok, %{
      overall_score: score,
      confidence: confidence,
      reasoning: reasoning,
      issues: [],
      recommendations: []
    }}
  end
  
  defp extract_score_from_text(lines) do
    score_line = Enum.find(lines, &String.contains?(&1, ["score", "rating"]))
    
    case score_line do
      nil -> 0.5
      line ->
        case Regex.run(~r/(\d+\.?\d*)/, line) do
          [_, score_str] -> 
            case Float.parse(score_str) do
              {score, _} when score <= 1.0 -> score
              {score, _} when score <= 10.0 -> score / 10.0
              {score, _} when score <= 100.0 -> score / 100.0
              _ -> 0.5
            end
          _ -> 0.5
        end
    end
  end
  
  defp extract_confidence_from_text(lines) do
    confidence_line = Enum.find(lines, &String.contains?(&1, ["confidence", "certainty"]))
    
    case confidence_line do
      nil -> 0.7
      line ->
        case Regex.run(~r/(\d+\.?\d*)/, line) do
          [_, conf_str] ->
            case Float.parse(conf_str) do
              {conf, _} when conf <= 1.0 -> conf
              {conf, _} when conf <= 100.0 -> conf / 100.0
              _ -> 0.7
            end
          _ -> 0.7
        end
    end
  end
  
  defp extract_reasoning_from_text(lines) do
    # Take the longest line as reasoning, or join multiple lines
    reasoning_lines = Enum.filter(lines, fn line ->
      String.length(line) > 20 and 
      not String.contains?(line, ["score", "confidence", "rating"])
    end)
    
    case reasoning_lines do
      [] -> "Evaluation completed."
      lines -> Enum.join(lines, " ")
    end
  end
end