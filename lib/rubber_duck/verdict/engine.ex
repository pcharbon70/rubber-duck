defmodule RubberDuck.Verdict.Engine do
  @moduledoc """
  Core Verdict framework engine for intelligent code evaluation.
  
  Implements the Verdict framework's judge-time compute scaling approach using
  modular reasoning units and progressive evaluation to achieve 60-80% cost
  reduction while maintaining high-quality code assessment.
  
  Features:
  - Progressive evaluation with lightweight screening
  - Modular judge units for different evaluation types
  - Intelligent caching with semantic similarity
  - Token optimization and budget management
  - Integration with RubberDuck preference system
  """
  
  alias RubberDuck.Verdict.JudgeUnits.BaseJudgeUnit
  alias RubberDuck.Verdict.Optimization.{ProgressiveEvaluator, IntelligentCache}
  alias RubberDuck.Preferences.PreferenceResolver
  
  require Logger
  
  @default_config %{
    enabled: true,
    default_model: "gpt-4o-mini",
    quality_threshold: 0.8,
    max_tokens_per_evaluation: 1500,
    budget_per_day: 10.00,
    progressive_evaluation: true,
    cache_enabled: true
  }
  
  @doc """
  Evaluate code using the Verdict framework.
  
  ## Parameters
  - `code` - The code to evaluate
  - `evaluation_type` - Type of evaluation (:quality, :security, :performance, :maintainability)
  - `options` - Evaluation options and configuration overrides
  
  ## Returns
  - `{:ok, evaluation_result}` - Successful evaluation with scores and recommendations
  - `{:error, reason}` - Evaluation failed with reason
  """
  @spec evaluate_code(
    code :: String.t(),
    evaluation_type :: atom(),
    options :: keyword()
  ) :: {:ok, map()} | {:error, term()}
  def evaluate_code(code, evaluation_type, options \\ []) do
    case validate_evaluation_request(code, evaluation_type, options) do
      :ok -> perform_evaluation(code, evaluation_type, options)
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Get evaluation configuration for a user/project context.
  """
  @spec get_evaluation_config(user_id :: String.t(), project_id :: String.t() | nil) :: 
    {:ok, map()} | {:error, term()}
  def get_evaluation_config(user_id, project_id \\ nil) do
    case resolve_verdict_preferences(user_id, project_id) do
      {:ok, preferences} -> {:ok, build_evaluation_config(preferences)}
      error -> error
    end
  end
  
  @doc """
  Check if Verdict evaluation is enabled for a user/project.
  """
  @spec evaluation_enabled?(user_id :: String.t(), project_id :: String.t() | nil) :: boolean()
  def evaluation_enabled?(user_id, project_id \\ nil) do
    case get_evaluation_config(user_id, project_id) do
      {:ok, config} -> Map.get(config, :enabled, false)
      {:error, _} -> false
    end
  end
  
  @doc """
  Estimate the cost of an evaluation before execution.
  """
  @spec estimate_evaluation_cost(
    code :: String.t(),
    evaluation_type :: atom(),
    options :: keyword()
  ) :: {:ok, %{estimated_cost: float(), confidence: float()}} | {:error, term()}
  def estimate_evaluation_cost(code, evaluation_type, options \\ []) do
    # Calculate estimated tokens and model usage
    estimated_tokens = estimate_token_usage(code, evaluation_type)
    model_config = get_model_config(options)
    
    case calculate_cost_estimate(estimated_tokens, model_config, options) do
      {:ok, cost_data} -> {:ok, cost_data}
      error -> error
    end
  end
  
  @doc """
  Get available evaluation types and their descriptions.
  """
  @spec list_evaluation_types() :: [%{type: atom(), description: String.t(), cost_tier: atom()}]
  def list_evaluation_types do
    [
      %{
        type: :quality,
        description: "Overall code quality assessment including readability, maintainability, and best practices",
        cost_tier: :medium
      },
      %{
        type: :security,
        description: "Security vulnerability detection and secure coding practices evaluation",
        cost_tier: :high
      },
      %{
        type: :performance,
        description: "Performance analysis and optimization recommendations",
        cost_tier: :medium
      },
      %{
        type: :maintainability,
        description: "Code maintainability and technical debt assessment",
        cost_tier: :low
      },
      %{
        type: :best_practices,
        description: "Elixir and OTP best practices compliance check",
        cost_tier: :low
      },
      %{
        type: :comprehensive,
        description: "Full evaluation including all criteria with detailed analysis",
        cost_tier: :high
      }
    ]
  end
  
  ## Private Functions
  
  defp validate_evaluation_request(code, evaluation_type, options) do
    cond do
      is_nil(code) or code == "" ->
        {:error, "Code cannot be empty"}
      
      not is_atom(evaluation_type) ->
        {:error, "Evaluation type must be an atom"}
      
      evaluation_type not in [:quality, :security, :performance, :maintainability, :best_practices, :comprehensive] ->
        {:error, "Invalid evaluation type: #{evaluation_type}"}
      
      String.length(code) > 50_000 ->
        {:error, "Code too large for evaluation (max 50,000 characters)"}
      
      true -> :ok
    end
  end
  
  defp perform_evaluation(code, evaluation_type, options) do
    user_id = Keyword.get(options, :user_id)
    project_id = Keyword.get(options, :project_id)
    
    # Get evaluation configuration
    case get_evaluation_config(user_id, project_id) do
      {:ok, config} ->
        execute_evaluation_pipeline(code, evaluation_type, config, options)
      
      error -> error
    end
  end
  
  defp execute_evaluation_pipeline(code, evaluation_type, config, options) do
    # Check cache first
    cache_key = IntelligentCache.generate_cache_key(code, evaluation_type, config)
    
    case IntelligentCache.get_cached_result(cache_key) do
      {:ok, cached_result} ->
        Logger.info("Cache hit for evaluation: #{evaluation_type}")
        {:ok, Map.put(cached_result, :cache_hit, true)}
      
      {:error, :cache_miss} ->
        # Perform evaluation using progressive approach
        case ProgressiveEvaluator.evaluate(code, evaluation_type, config, options) do
          {:ok, result} ->
            # Cache the result for future use
            IntelligentCache.cache_result(cache_key, result, config)
            {:ok, Map.put(result, :cache_hit, false)}
          
          error -> error
        end
      
      error -> error
    end
  end
  
  defp resolve_verdict_preferences(user_id, project_id) do
    # Use the existing preference resolution system
    base_config = @default_config
    
    # This would resolve Verdict-specific preferences using PreferenceResolver
    # For now, return default configuration
    {:ok, base_config}
  end
  
  defp build_evaluation_config(preferences) do
    # Build evaluation configuration from resolved preferences
    Map.merge(@default_config, preferences)
  end
  
  defp estimate_token_usage(code, evaluation_type) do
    # Rough estimation based on code length and evaluation complexity
    base_tokens = div(String.length(code), 4)  # Rough approximation
    
    multiplier = case evaluation_type do
      :maintainability -> 1.2
      :best_practices -> 1.3  
      :quality -> 1.5
      :performance -> 1.7
      :security -> 2.0
      :comprehensive -> 3.0
      _ -> 1.0
    end
    
    round(base_tokens * multiplier)
  end
  
  defp get_model_config(options) do
    model = Keyword.get(options, :model, "gpt-4o-mini")
    
    # Model pricing (rough estimates)
    case model do
      "gpt-4o-mini" -> %{cost_per_token: 0.000002, max_tokens: 4096}
      "gpt-4o" -> %{cost_per_token: 0.00002, max_tokens: 8192}
      "claude-3-haiku" -> %{cost_per_token: 0.000003, max_tokens: 4096}
      "claude-3-sonnet" -> %{cost_per_token: 0.00001, max_tokens: 8192}
      _ -> %{cost_per_token: 0.000002, max_tokens: 4096}
    end
  end
  
  defp calculate_cost_estimate(estimated_tokens, model_config, _options) do
    estimated_cost = estimated_tokens * model_config.cost_per_token
    
    # Add confidence based on estimation accuracy
    confidence = cond do
      estimated_tokens < 500 -> 0.9
      estimated_tokens < 2000 -> 0.8
      estimated_tokens < 5000 -> 0.7
      true -> 0.6
    end
    
    {:ok, %{
      estimated_cost: estimated_cost,
      estimated_tokens: estimated_tokens,
      confidence: confidence,
      model: model_config
    }}
  end
end