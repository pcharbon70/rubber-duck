defmodule RubberDuck.Verdict.Providers.EvaluationContext do
  @moduledoc """
  Evaluation context container for provider requirements and constraints.
  
  This module encapsulates all the context needed for AI provider selection
  and evaluation execution including:
  - Code evaluation requirements and constraints
  - User preferences and project settings
  - Budget and cost constraints
  - Quality thresholds and performance requirements
  - Provider preferences and restrictions
  """
  
  require Logger
  
  alias RubberDuck.Verdict.Configuration.VerdictConfigurationResolver
  
  @type t :: %__MODULE__{
    # Core evaluation data
    code: String.t(),
    evaluation_type: atom(),
    criteria: map(),
    
    # Context and requirements
    user_id: String.t() | nil,
    project_id: String.t() | nil,
    evaluation_id: String.t() | nil,
    
    # Provider requirements
    quality_threshold: float(),
    max_tokens: integer(),
    streaming_required: boolean(),
    
    # Cost constraints
    max_cost_per_evaluation: float(),
    budget_remaining: float(),
    cost_priority: float(),
    
    # Provider preferences
    preferred_providers: list(String.t()),
    restricted_providers: list(String.t()),
    routing_strategy: atom(),
    
    # Performance requirements
    max_response_time_ms: integer(),
    min_confidence_threshold: float(),
    
    # Metadata
    created_at: DateTime.t(),
    evaluation_priority: atom(),
    retry_count: integer(),
    source: atom()
  }
  
  @enforce_keys [:code, :evaluation_type]
  defstruct [
    # Core evaluation data
    :code,
    :evaluation_type,
    criteria: %{},
    
    # Context
    user_id: nil,
    project_id: nil,
    evaluation_id: nil,
    
    # Provider requirements
    quality_threshold: 0.8,
    max_tokens: 1500,
    streaming_required: false,
    
    # Cost constraints
    max_cost_per_evaluation: 1.0,
    budget_remaining: 50.0,
    cost_priority: 0.4,
    
    # Provider preferences
    preferred_providers: [],
    restricted_providers: [],
    routing_strategy: :balanced,
    
    # Performance requirements
    max_response_time_ms: 10_000,
    min_confidence_threshold: 0.6,
    
    # Metadata
    created_at: nil,
    evaluation_priority: :normal,
    retry_count: 0,
    source: :api
  ]
  
  @doc """
  Create evaluation context from basic parameters.
  """
  def new(code, evaluation_type, options \\ []) do
    context = %__MODULE__{
      code: code,
      evaluation_type: evaluation_type,
      created_at: DateTime.utc_now()
    }
    
    # Apply any provided options
    Enum.reduce(options, context, fn {key, value}, acc ->
      if Map.has_key?(acc, key) do
        Map.put(acc, key, value)
      else
        acc
      end
    end)
  end
  
  @doc """
  Build evaluation context with user/project configuration resolution.
  """
  def build_with_configuration(code, evaluation_type, user_id, project_id \\ nil, options \\ []) do
    Logger.debug("Building evaluation context for user #{user_id}, project #{project_id}")
    
    base_context = new(code, evaluation_type, [
      user_id: user_id,
      project_id: project_id,
      evaluation_id: Keyword.get(options, :evaluation_id),
      source: Keyword.get(options, :source, :api)
    ])
    
    case resolve_configuration_settings(user_id, project_id) do
      {:ok, config_settings} ->
        context_with_config = apply_configuration_to_context(base_context, config_settings)
        context_with_options = apply_context_options(context_with_config, options)
        
        case validate_evaluation_context(context_with_options) do
          :ok -> {:ok, context_with_options}
          {:error, reason} -> {:error, reason}
        end
      
      {:error, reason} ->
        Logger.warning("Failed to resolve configuration for context: #{inspect(reason)}")
        # Use base context with defaults
        {:ok, apply_context_options(base_context, options)}
    end
  end
  
  @doc """
  Extract provider requirements from evaluation context.
  """
  def extract_provider_requirements(%__MODULE__{} = context) do
    %{
      evaluation_type: context.evaluation_type,
      quality_threshold: context.quality_threshold,
      max_tokens: context.max_tokens,
      streaming: context.streaming_required,
      max_cost: context.max_cost_per_evaluation,
      max_response_time_ms: context.max_response_time_ms,
      preferred_providers: context.preferred_providers,
      restricted_providers: context.restricted_providers
    }
  end
  
  @doc """
  Extract routing constraints from evaluation context.
  """
  def extract_routing_constraints(%__MODULE__{} = context) do
    %{
      strategy: context.routing_strategy,
      cost_priority: context.cost_priority,
      quality_threshold: context.quality_threshold,
      budget_remaining: context.budget_remaining,
      max_cost_per_evaluation: context.max_cost_per_evaluation,
      preferred_providers: context.preferred_providers,
      restricted_providers: context.restricted_providers
    }
  end
  
  @doc """
  Build evaluation request for provider from context.
  """
  def to_evaluation_request(%__MODULE__{} = context, additional_metadata \\ %{}) do
    %{
      code: context.code,
      evaluation_type: context.evaluation_type,
      criteria: context.criteria,
      context: %{
        user_id: context.user_id,
        project_id: context.project_id,
        evaluation_id: context.evaluation_id
      },
      quality_threshold: context.quality_threshold,
      max_tokens: context.max_tokens,
      streaming: context.streaming_required,
      metadata: Map.merge(%{
        created_at: context.created_at,
        evaluation_priority: context.evaluation_priority,
        retry_count: context.retry_count,
        source: context.source
      }, additional_metadata)
    }
  end
  
  @doc """
  Update context for retry attempts.
  """
  def increment_retry_count(%__MODULE__{} = context) do
    %{context | retry_count: context.retry_count + 1}
  end
  
  @doc """
  Add metadata to evaluation context.
  """
  def add_metadata(%__MODULE__{} = context, key, value) when is_atom(key) do
    # Store additional metadata in criteria map for now
    updated_criteria = Map.put(context.criteria, key, value)
    %{context | criteria: updated_criteria}
  end
  
  @doc """
  Validate evaluation context completeness and constraints.
  """
  def validate_evaluation_context(%__MODULE__{} = context) do
    with :ok <- validate_core_fields(context),
         :ok <- validate_thresholds(context),
         :ok <- validate_budget_constraints(context),
         :ok <- validate_provider_preferences(context) do
      :ok
    else
      error -> error
    end
  end
  
  # Private implementation
  
  defp resolve_configuration_settings(user_id, project_id) do
    VerdictConfigurationResolver.resolve_configuration(user_id, project_id)
  end
  
  defp apply_configuration_to_context(context, config) do
    %{context |
      quality_threshold: Map.get(config, :default_quality_threshold, context.quality_threshold),
      max_tokens: Map.get(config, :max_tokens_per_evaluation, context.max_tokens),
      max_cost_per_evaluation: Map.get(config, :max_cost_per_evaluation, context.max_cost_per_evaluation),
      budget_remaining: Map.get(config, :daily_budget_remaining, context.budget_remaining),
      preferred_providers: Map.get(config, :preferred_providers, context.preferred_providers),
      restricted_providers: Map.get(config, :restricted_providers, context.restricted_providers),
      routing_strategy: Map.get(config, :routing_strategy, context.routing_strategy),
      criteria: Map.get(config, :evaluation_criteria_weights, context.criteria),
      min_confidence_threshold: Map.get(config, :escalation_threshold, context.min_confidence_threshold)
    }
  end
  
  defp apply_context_options(context, options) do
    Enum.reduce(options, context, fn {key, value}, acc ->
      case key do
        :quality_threshold -> %{acc | quality_threshold: value}
        :max_tokens -> %{acc | max_tokens: value}
        :streaming -> %{acc | streaming_required: value}
        :max_cost -> %{acc | max_cost_per_evaluation: value}
        :priority -> %{acc | evaluation_priority: value}
        :criteria -> %{acc | criteria: Map.merge(acc.criteria, value)}
        :routing_strategy -> %{acc | routing_strategy: value}
        _ -> acc  # Ignore unknown options
      end
    end)
  end
  
  defp validate_core_fields(context) do
    cond do
      is_nil(context.code) or String.trim(context.code) == "" ->
        {:error, "Code field is required and cannot be empty"}
      
      context.evaluation_type not in [:quality, :security, :performance, :maintainability, :style] ->
        {:error, "Invalid evaluation type: #{context.evaluation_type}"}
      
      true -> :ok
    end
  end
  
  defp validate_thresholds(context) do
    cond do
      context.quality_threshold < 0 or context.quality_threshold > 1 ->
        {:error, "Quality threshold must be between 0 and 1"}
      
      context.min_confidence_threshold < 0 or context.min_confidence_threshold > 1 ->
        {:error, "Confidence threshold must be between 0 and 1"}
      
      context.min_confidence_threshold > context.quality_threshold ->
        {:error, "Confidence threshold cannot exceed quality threshold"}
      
      true -> :ok
    end
  end
  
  defp validate_budget_constraints(context) do
    cond do
      context.max_cost_per_evaluation < 0 ->
        {:error, "Max cost per evaluation must be non-negative"}
      
      context.budget_remaining < 0 ->
        {:error, "Budget remaining cannot be negative"}
      
      context.max_cost_per_evaluation > context.budget_remaining ->
        {:error, "Max cost per evaluation exceeds remaining budget"}
      
      true -> :ok
    end
  end
  
  defp validate_provider_preferences(context) do
    all_providers = ["openai", "anthropic", "ollama", "azure", "vertex"]
    
    invalid_preferred = context.preferred_providers -- all_providers
    invalid_restricted = context.restricted_providers -- all_providers
    
    cond do
      length(invalid_preferred) > 0 ->
        {:error, "Invalid preferred providers: #{inspect(invalid_preferred)}"}
      
      length(invalid_restricted) > 0 ->
        {:error, "Invalid restricted providers: #{inspect(invalid_restricted)}"}
      
      true ->
        check_provider_preference_conflicts(context)
    end
  end
  
  defp check_provider_preference_conflicts(context) do
    # Check if user restricted all preferred providers
    if Enum.empty?(context.preferred_providers) do
      :ok
    else
      restricted_set = MapSet.new(context.restricted_providers)
      preferred_set = MapSet.new(context.preferred_providers)
      available_preferred = MapSet.difference(preferred_set, restricted_set)
      
      if MapSet.size(available_preferred) == 0 do
        {:error, "All preferred providers are restricted"}
      else
        :ok
      end
    end
  end
  
  # Utility functions
  
  @doc """
  Check if context allows specific provider.
  """
  def allows_provider?(%__MODULE__{} = context, provider_type) when is_atom(provider_type) do
    provider_string = to_string(provider_type)
    
    # Check if provider is restricted
    not_restricted = provider_string not in context.restricted_providers
    
    # Check if provider meets preferences (empty preferences means allow all)
    meets_preferences = Enum.empty?(context.preferred_providers) or 
                       provider_string in context.preferred_providers
    
    not_restricted and meets_preferences
  end
  
  @doc """
  Calculate context complexity score for provider routing.
  """
  def calculate_complexity_score(%__MODULE__{} = context) do
    base_score = 0.5
    
    # Adjust for code length
    code_complexity = min(0.3, String.length(context.code) / 10_000)
    
    # Adjust for evaluation type
    type_complexity = case context.evaluation_type do
      :security -> 0.8    # Security evaluations are complex
      :performance -> 0.7 # Performance analysis requires deep understanding
      :quality -> 0.6     # General quality assessment
      :maintainability -> 0.5
      :style -> 0.3       # Style checks are simpler
      _ -> 0.5
    end
    
    # Adjust for criteria complexity
    criteria_complexity = map_size(context.criteria) * 0.05
    
    # Combine factors
    total_complexity = base_score + code_complexity + type_complexity + criteria_complexity
    min(1.0, total_complexity)
  end
  
  @doc """
  Determine if context requires premium provider capabilities.
  """
  def requires_premium_provider?(%__MODULE__{} = context) do
    complexity_score = calculate_complexity_score(context)
    
    complexity_score > 0.7 or 
    context.quality_threshold > 0.9 or
    context.evaluation_type in [:security, :performance] or
    String.length(context.code) > 5000
  end
  
  @doc """
  Get estimated token count for context.
  """
  def estimate_token_count(%__MODULE__{} = context) do
    # Base tokens from code (rough estimate: ~4 chars per token)
    code_tokens = div(String.length(context.code), 4)
    
    # System prompt tokens
    system_tokens = 200
    
    # Evaluation prompt tokens based on type and criteria
    evaluation_tokens = case context.evaluation_type do
      :security -> 800   # Security prompts are detailed
      :performance -> 600
      :quality -> 500
      :maintainability -> 400
      :style -> 300
      _ -> 400
    end
    
    # Additional tokens for criteria details
    criteria_tokens = map_size(context.criteria) * 50
    
    # Response tokens (estimated)
    response_tokens = 500
    
    code_tokens + system_tokens + evaluation_tokens + criteria_tokens + response_tokens
  end
  
  @doc """
  Build provider-specific evaluation prompt from context.
  """
  def build_evaluation_prompt(%__MODULE__{} = context, provider_type) do
    base_prompt = get_evaluation_type_prompt(context.evaluation_type)
    criteria_section = build_criteria_section(context.criteria)
    provider_adaptation = adapt_prompt_for_provider(base_prompt, provider_type)
    
    """
    #{provider_adaptation}
    
    #{criteria_section}
    
    Quality Requirements:
    - Minimum quality threshold: #{context.quality_threshold}
    - Minimum confidence threshold: #{context.min_confidence_threshold}
    
    Please evaluate the following code and provide a detailed analysis:
    
    ```
    #{context.code}
    ```
    
    Respond in JSON format with the following structure:
    {
      "overall_score": 0.85,
      "confidence": 0.9,
      "issues": [
        {"type": "security", "severity": "high", "description": "SQL injection vulnerability", "line": 42}
      ],
      "recommendations": [
        "Use parameterized queries to prevent SQL injection",
        "Add input validation for user data"
      ],
      "reasoning": "Detailed explanation of the evaluation..."
    }
    """
  end
  
  @doc """
  Create context for retry attempt with updated constraints.
  """
  def for_retry(%__MODULE__{} = context, provider_failures \\ []) do
    # Exclude failed providers from preferences
    failed_provider_names = Enum.map(provider_failures, &to_string/1)
    updated_restricted = context.restricted_providers ++ failed_provider_names
    
    # Relax constraints slightly for retry
    relaxed_context = %{context |
      retry_count: context.retry_count + 1,
      restricted_providers: updated_restricted,
      quality_threshold: max(0.6, context.quality_threshold - 0.05),
      max_cost_per_evaluation: context.max_cost_per_evaluation * 1.2,
      max_response_time_ms: context.max_response_time_ms + 2000
    }
    
    Logger.debug("Created retry context (attempt #{relaxed_context.retry_count})")
    relaxed_context
  end
  
  defp get_evaluation_type_prompt(evaluation_type) do
    case evaluation_type do
      :quality ->
        "You are an expert code reviewer evaluating overall code quality including correctness, maintainability, readability, and adherence to best practices."
      
      :security ->
        "You are a cybersecurity expert analyzing code for security vulnerabilities, potential attack vectors, data handling issues, and security best practices."
      
      :performance ->
        "You are a performance optimization specialist evaluating code efficiency, resource usage, algorithmic complexity, and scalability characteristics."
      
      :maintainability ->
        "You are a software architecture expert assessing code maintainability, modularity, documentation quality, and long-term sustainability."
      
      :style ->
        "You are a code style expert reviewing formatting, naming conventions, code organization, and adherence to language-specific idioms and conventions."
      
      _ ->
        "You are an experienced software engineer performing comprehensive code evaluation across multiple quality dimensions."
    end
  end
  
  defp build_criteria_section(criteria) when map_size(criteria) > 0 do
    criteria_list = criteria
    |> Enum.map(fn {criterion, weight} ->
      percentage = Float.round(weight * 100, 1)
      "- #{criterion}: #{percentage}% weight"
    end)
    |> Enum.join("\n")
    
    "Evaluation Criteria and Weights:\n#{criteria_list}"
  end
  
  defp build_criteria_section(_), do: "Use standard evaluation criteria with balanced weighting."
  
  defp adapt_prompt_for_provider(prompt, provider_type) do
    case provider_type do
      :openai ->
        prompt <> "\n\nLeverage your comprehensive training data to provide detailed, actionable insights with specific code examples where helpful."
      
      :anthropic ->
        prompt <> "\n\nApply Constitutional AI principles to ensure your evaluation is helpful, harmless, and honest. Focus on constructive feedback that promotes safe and effective code practices."
      
      :ollama ->
        prompt <> "\n\nProvide clear, focused analysis that's appropriate for local model capabilities. Be concise while maintaining thoroughness."
      
      _ ->
        prompt
    end
  end
  
  # Context validation helpers
  
  def validate_context_for_provider(%__MODULE__{} = context, provider_type, provider_capabilities) do
    requirements = extract_provider_requirements(context)
    
    # Check token limits
    estimated_tokens = estimate_token_count(context)
    max_context = Map.get(provider_capabilities, :max_context_tokens, 4096)
    
    cond do
      estimated_tokens > max_context ->
        {:error, "Context too large for provider (#{estimated_tokens} > #{max_context} tokens)"}
      
      context.streaming_required and not Map.get(provider_capabilities, :supports_streaming, false) ->
        {:error, "Provider does not support required streaming"}
      
      context.evaluation_type not in Map.get(provider_capabilities, :evaluation_types, []) ->
        {:error, "Provider does not support evaluation type: #{context.evaluation_type}"}
      
      true -> :ok
    end
  end
  
  def context_summary(%__MODULE__{} = context) do
    %{
      evaluation_type: context.evaluation_type,
      code_length: String.length(context.code),
      quality_threshold: context.quality_threshold,
      estimated_tokens: estimate_token_count(context),
      complexity_score: calculate_complexity_score(context),
      requires_premium: requires_premium_provider?(context),
      retry_count: context.retry_count,
      preferred_providers: context.preferred_providers,
      budget_remaining: context.budget_remaining
    }
  end
end