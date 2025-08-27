defmodule RubberDuck.LlmProviders.UniversalProviderInterface do
  @moduledoc """
  Universal provider interface for all LLM use cases across the RubberDuck system.

  This behavior defines the unified contract that all AI providers must implement
  to serve all system domains including:
  - Verdict framework code evaluation with Constitutional AI
  - Agent orchestration and multi-turn conversations
  - Tool calling and function execution
  - Planning and reasoning tasks
  - Embedding generation and similarity search

  The interface provides:
  - Standardized request/response format across all use cases
  - Domain-specific capability discovery and optimization
  - Unified cost tracking and budget management
  - Comprehensive health monitoring and failover
  - Streaming support for real-time feedback
  """

  @type domain_context :: %{
          domain: :evaluation | :orchestration | :planning | :communication | :tooling,
          use_case: atom(),
          requirements: map(),
          budget_constraints: map(),
          quality_thresholds: map(),
          specialized_features: list(atom()),
          user_id: String.t() | nil,
          project_id: String.t() | nil
        }

  @type universal_request :: %{
          content: String.t() | list(map()),
          context: domain_context(),
          streaming: boolean(),
          max_tokens: integer(),
          temperature: float(),
          provider_preferences: map(),
          metadata: map()
        }

  @type universal_response :: %{
          provider: atom(),
          model: String.t(),
          success: boolean(),
          content: String.t() | map(),
          usage: %{
            input_tokens: integer(),
            output_tokens: integer(),
            total_tokens: integer()
          },
          cost_usd: float(),
          response_time_ms: integer(),
          domain_specific_data: map(),
          metadata: map()
        }

  @type provider_capabilities :: %{
          supports_streaming: boolean(),
          supports_function_calling: boolean(),
          supports_embeddings: boolean(),
          max_context_tokens: integer(),
          supported_domains: list(atom()),
          supported_use_cases: list(atom()),
          cost_per_1k_tokens: %{String.t() => float()},
          rate_limits: map(),
          specialized_features: list(atom())
        }

  @type provider_health :: %{
          status: :healthy | :degraded | :unhealthy,
          success_rate: float(),
          avg_response_time_ms: integer(),
          last_check: DateTime.t(),
          error_count: integer(),
          availability_percentage: float(),
          domain_specific_health: map()
        }

  # Core universal provider contract

  @doc """
  Initialize the provider with configuration for all use cases.

  Returns provider state supporting evaluation, orchestration, and future domains.
  """
  @callback initialize(config :: map()) ::
              {:ok, state :: any()} | {:error, reason :: String.t()}

  @doc """
  Process universal request for any domain (evaluation, orchestration, etc.).

  Returns standardized response format with domain-specific data preservation.
  """
  @callback process_request(
              state :: any(),
              request :: universal_request()
            ) :: {:ok, universal_response()} | {:error, reason :: String.t()}

  @doc """
  Start streaming request with real-time updates for any domain.

  Supports both evaluation feedback and orchestration communication streaming.
  """
  @callback process_streaming_request(
              state :: any(),
              request :: universal_request(),
              callback :: (map() -> any())
            ) :: {:ok, universal_response()} | {:error, reason :: String.t()}

  @doc """
  Generate embeddings for text content (future Phase 5: Memory & Context).
  """
  @callback generate_embeddings(
              state :: any(),
              text :: String.t() | list(String.t()),
              options :: map()
            ) :: {:ok, embeddings :: list(list(float()))} | {:error, reason :: String.t()}

  @doc """
  Execute function calls for tool-using agents (Phase 3: Tool Agents).
  """
  @callback execute_function_call(
              state :: any(),
              function_spec :: map(),
              context :: domain_context()
            ) :: {:ok, result :: map()} | {:error, reason :: String.t()}

  @doc """
  Get provider capabilities across all supported domains.
  """
  @callback get_capabilities(state :: any()) ::
              {:ok, provider_capabilities()} | {:error, reason :: String.t()}

  @doc """
  Perform comprehensive health check covering all provider capabilities.
  """
  @callback health_check(state :: any()) ::
              {:ok, provider_health()} | {:error, reason :: String.t()}

  @doc """
  Estimate cost for universal request before execution.
  """
  @callback estimate_cost(
              state :: any(),
              request :: universal_request()
            ) :: {:ok, cost_estimate :: float()} | {:error, reason :: String.t()}

  @doc """
  Clean up provider resources across all domains.
  """
  @callback terminate(state :: any()) :: :ok

  # Helper functions for universal provider implementations

  @doc """
  Validate universal request structure for any domain.
  """
  def validate_universal_request(request) when is_map(request) do
    required_fields = [:content, :context]
    missing_fields = Enum.filter(required_fields, &(!Map.has_key?(request, &1)))

    case missing_fields do
      [] -> validate_request_context(request)
      fields -> {:error, "Missing required fields: #{inspect(fields)}"}
    end
  end

  def validate_universal_request(_), do: {:error, "Request must be a map"}

  defp validate_request_context(request) do
    context = Map.get(request, :context, %{})

    with :ok <- validate_domain(context),
         :ok <- validate_content_field(request),
         :ok <- validate_budget_constraints(context),
         :ok <- validate_specialized_features(context) do
      :ok
    else
      error -> error
    end
  end

  defp validate_domain(context) do
    case Map.get(context, :domain) do
      domain when domain in [:evaluation, :orchestration, :planning, :communication, :tooling] ->
        :ok

      _ ->
        {:error, "Invalid or missing domain in context"}
    end
  end

  defp validate_content_field(request) do
    case Map.get(request, :content) do
      content when is_binary(content) and byte_size(content) > 0 -> :ok
      content when is_list(content) and length(content) > 0 -> :ok
      _ -> {:error, "Content field must be non-empty string or list"}
    end
  end

  defp validate_budget_constraints(context) do
    case Map.get(context, :budget_constraints, %{}) do
      constraints when is_map(constraints) -> :ok
      _ -> {:error, "Budget constraints must be a map"}
    end
  end

  defp validate_specialized_features(context) do
    case Map.get(context, :specialized_features, []) do
      features when is_list(features) -> :ok
      _ -> {:error, "Specialized features must be a list"}
    end
  end

  @doc """
  Standardize universal response format across all providers and domains.
  """
  def standardize_universal_response(
        provider_response,
        provider_type,
        model,
        domain_context,
        metadata \\ %{}
      ) do
    %{
      provider: provider_type,
      model: model,
      success: Map.get(provider_response, :success, false),
      content: Map.get(provider_response, :content, ""),
      usage: standardize_usage_info(provider_response),
      cost_usd: Map.get(provider_response, :cost_usd, 0.0),
      response_time_ms: Map.get(provider_response, :response_time_ms, 0),
      domain_specific_data: extract_domain_specific_data(provider_response, domain_context),
      metadata: Map.merge(metadata, Map.get(provider_response, :metadata, %{}))
    }
  end

  defp standardize_usage_info(provider_response) do
    usage = Map.get(provider_response, :usage, %{})

    %{
      input_tokens: Map.get(usage, :input_tokens, 0),
      output_tokens: Map.get(usage, :output_tokens, 0),
      total_tokens:
        Map.get(
          usage,
          :total_tokens,
          Map.get(usage, :input_tokens, 0) + Map.get(usage, :output_tokens, 0)
        )
    }
  end

  defp extract_domain_specific_data(provider_response, domain_context) do
    case domain_context.domain do
      :evaluation ->
        %{
          score: Map.get(provider_response, :score, 0.0),
          confidence: Map.get(provider_response, :confidence, 0.0),
          issues: Map.get(provider_response, :issues, []),
          recommendations: Map.get(provider_response, :recommendations, []),
          reasoning: Map.get(provider_response, :reasoning, ""),
          constitutional_ai_data: Map.get(provider_response, :constitutional_ai_data, %{})
        }

      :orchestration ->
        %{
          completion_quality: Map.get(provider_response, :completion_quality, 0.8),
          cost_efficiency: Map.get(provider_response, :cost_efficiency, 0.7),
          agent_communication_data: Map.get(provider_response, :agent_data, %{})
        }

      :planning ->
        %{
          reasoning_depth: Map.get(provider_response, :reasoning_depth, 0.7),
          plan_quality: Map.get(provider_response, :plan_quality, 0.8),
          planning_data: Map.get(provider_response, :planning_data, %{})
        }

      _ ->
        Map.get(provider_response, :domain_data, %{})
    end
  end

  @doc """
  Calculate universal cost estimate supporting all domains.
  """
  def calculate_universal_cost_estimate(token_count, cost_per_1k_tokens, domain_context)
      when is_integer(token_count) and is_number(cost_per_1k_tokens) do
    base_cost = token_count / 1000 * cost_per_1k_tokens

    # Apply domain-specific cost adjustments
    domain_multiplier =
      case domain_context.domain do
        # Base cost for evaluation
        :evaluation -> 1.0
        # Slight discount for orchestration bulk usage
        :orchestration -> 0.9
        # Slight premium for complex planning
        :planning -> 1.1
        # Lower cost for simple communication
        :communication -> 0.8
        _ -> 1.0
      end

    base_cost * domain_multiplier
  end

  def calculate_universal_cost_estimate(_, _, _), do: {:error, "Invalid token count or cost rate"}

  @doc """
  Parse universal provider health status supporting all domains.
  """
  def parse_universal_health_status(
        response_time_ms,
        success_rate,
        domain_health_data \\ %{},
        error_count \\ 0
      ) do
    status =
      cond do
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
      availability_percentage: success_rate * 100,
      domain_specific_health: domain_health_data
    }
  end

  @doc """
  Build universal request from domain-specific parameters.
  """
  def build_universal_request(content, domain, use_case, options \\ %{}) do
    context = %{
      domain: domain,
      use_case: use_case,
      requirements: Map.get(options, :requirements, %{}),
      budget_constraints: Map.get(options, :budget_constraints, %{}),
      quality_thresholds: Map.get(options, :quality_thresholds, %{}),
      specialized_features: Map.get(options, :specialized_features, []),
      user_id: Map.get(options, :user_id),
      project_id: Map.get(options, :project_id)
    }

    %{
      content: content,
      context: context,
      streaming: Map.get(options, :streaming, false),
      max_tokens: Map.get(options, :max_tokens, 1500),
      temperature: Map.get(options, :temperature, 0.1),
      provider_preferences: Map.get(options, :provider_preferences, %{}),
      metadata: Map.get(options, :metadata, %{})
    }
  end

  @doc """
  Extract domain requirements for provider selection.
  """
  def extract_domain_requirements(universal_request) do
    context = universal_request.context

    %{
      domain: context.domain,
      use_case: context.use_case,
      budget_constraints: context.budget_constraints,
      quality_requirements: context.quality_thresholds,
      specialized_features_required: context.specialized_features,
      streaming_required: universal_request.streaming,
      max_tokens: universal_request.max_tokens,
      performance_requirements: Map.get(context.requirements, :performance, %{})
    }
  end

  @doc """
  Build provider prompt optimized for domain and provider type.
  """
  def build_universal_prompt(content, domain, use_case, provider_type, options \\ %{}) do
    domain_prompt = get_domain_prompt(domain, use_case)
    provider_adaptation = adapt_prompt_for_provider(domain_prompt, provider_type)
    specialized_instructions = build_specialized_instructions(options)

    case content do
      content when is_binary(content) ->
        """
        #{provider_adaptation}

        #{specialized_instructions}

        #{content}
        """

      content when is_list(content) ->
        # For multi-turn conversations (orchestration domain)
        content
    end
  end

  defp get_domain_prompt(domain, use_case) do
    case {domain, use_case} do
      {:evaluation, :security} ->
        "You are a security expert providing comprehensive code evaluation with Constitutional AI principles."

      {:evaluation, :quality} ->
        "You are a code quality expert providing detailed, actionable evaluation feedback."

      {:orchestration, :agent_communication} ->
        "You are an AI assistant facilitating intelligent agent-to-agent communication and coordination."

      {:orchestration, :planning} ->
        "You are a planning specialist helping agents coordinate complex multi-step tasks."

      {:planning, :task_breakdown} ->
        "You are a planning expert breaking down complex tasks into manageable steps."

      {:communication, :user_interaction} ->
        "You are a helpful AI assistant providing clear, concise communication."

      {:tooling, :function_selection} ->
        "You are a tool selection expert choosing optimal functions for specific tasks."

      _ ->
        "You are an AI assistant providing helpful, accurate responses."
    end
  end

  defp adapt_prompt_for_provider(prompt, provider_type) do
    case provider_type do
      :openai ->
        prompt <>
          "\n\nLeverage your comprehensive training to provide detailed, actionable insights."

      :anthropic ->
        prompt <>
          "\n\nApply Constitutional AI principles: be helpful, harmless, and honest in your response."

      :ollama ->
        prompt <> "\n\nProvide clear, focused analysis appropriate for local model capabilities."

      _ ->
        prompt
    end
  end

  defp build_specialized_instructions(options) do
    specialized_features = Map.get(options, :specialized_features, [])

    instructions = []

    instructions =
      if :constitutional_ai in specialized_features do
        ["Apply Constitutional AI safety principles throughout your analysis"] ++ instructions
      else
        instructions
      end

    instructions =
      if :cost_optimization in specialized_features do
        ["Consider cost-efficiency while maintaining quality in your response"] ++ instructions
      else
        instructions
      end

    instructions =
      if :safety_critical in specialized_features do
        ["This is a safety-critical evaluation - prioritize thorough analysis over speed"] ++
          instructions
      else
        instructions
      end

    case instructions do
      [] ->
        ""

      list ->
        "\nSpecial Requirements:\n" <> Enum.map_join(list, "\n", fn instr -> "- #{instr}" end)
    end
  end

  # Domain-specific utility functions

  @doc """
  Check if provider supports specific domain requirements.
  """
  def supports_domain_requirements?(provider_capabilities, domain_requirements) do
    domain_supported =
      domain_requirements.domain in Map.get(provider_capabilities, :supported_domains, [])

    use_case_supported =
      domain_requirements.use_case in Map.get(provider_capabilities, :supported_use_cases, [])

    # Check specialized feature support
    required_features = domain_requirements.specialized_features_required
    available_features = Map.get(provider_capabilities, :specialized_features, [])
    features_supported = Enum.all?(required_features, &(&1 in available_features))

    # Check performance requirements
    performance_met =
      case domain_requirements.performance_requirements do
        %{max_response_time: max_time} ->
          provider_avg_time = Map.get(provider_capabilities, :avg_response_time_ms, 5000)
          provider_avg_time <= max_time

        _ ->
          true
      end

    domain_supported and use_case_supported and features_supported and performance_met
  end

  @doc """
  Extract provider preferences from universal request for routing decisions.
  """
  def extract_routing_preferences(universal_request) do
    context = universal_request.context
    provider_prefs = universal_request.provider_preferences

    %{
      preferred_providers: Map.get(provider_prefs, :preferred_providers, []),
      restricted_providers: Map.get(provider_prefs, :restricted_providers, []),
      routing_strategy: Map.get(provider_prefs, :routing_strategy, :balanced),
      cost_priority: Map.get(context.budget_constraints, :cost_priority, 0.4),
      quality_priority: Map.get(context.quality_thresholds, :quality_priority, 0.4),
      speed_priority: Map.get(provider_prefs, :speed_priority, 0.2)
    }
  end

  @doc """
  Build domain-specific response from universal provider response.
  """
  def adapt_response_for_domain(universal_response, target_domain) do
    case target_domain do
      :evaluation ->
        # Format for Verdict framework consumption
        %{
          success: universal_response.success,
          score: Map.get(universal_response.domain_specific_data, :score, 0.7),
          confidence: Map.get(universal_response.domain_specific_data, :confidence, 0.8),
          issues: Map.get(universal_response.domain_specific_data, :issues, []),
          recommendations: Map.get(universal_response.domain_specific_data, :recommendations, []),
          reasoning:
            Map.get(
              universal_response.domain_specific_data,
              :reasoning,
              universal_response.content
            ),
          cost_usd: universal_response.cost_usd,
          tokens_used: universal_response.usage.total_tokens,
          response_time_ms: universal_response.response_time_ms,
          provider: universal_response.provider,
          model: universal_response.model,
          metadata: universal_response.metadata
        }

      :orchestration ->
        # Format for agent orchestration consumption
        %{
          content: universal_response.content,
          success: universal_response.success,
          cost_usd: universal_response.cost_usd,
          completion_quality:
            Map.get(universal_response.domain_specific_data, :completion_quality, 0.8),
          usage_efficiency: calculate_usage_efficiency(universal_response),
          provider_info: %{
            provider: universal_response.provider,
            model: universal_response.model,
            response_time_ms: universal_response.response_time_ms
          },
          metadata: universal_response.metadata
        }

      :planning ->
        # Format for planning and reasoning consumption
        %{
          content: universal_response.content,
          reasoning_quality:
            Map.get(universal_response.domain_specific_data, :reasoning_depth, 0.7),
          plan_completeness: Map.get(universal_response.domain_specific_data, :plan_quality, 0.8),
          cost_usd: universal_response.cost_usd,
          provider_info: %{
            provider: universal_response.provider,
            model: universal_response.model
          },
          metadata: universal_response.metadata
        }

      _ ->
        # Generic format
        %{
          content: universal_response.content,
          success: universal_response.success,
          cost_usd: universal_response.cost_usd,
          provider: universal_response.provider,
          model: universal_response.model,
          metadata: universal_response.metadata
        }
    end
  end

  defp calculate_usage_efficiency(universal_response) do
    total_tokens = universal_response.usage.total_tokens
    cost = universal_response.cost_usd
    response_time = universal_response.response_time_ms

    # Simple efficiency calculation (would be more sophisticated in production)
    if total_tokens > 0 and cost > 0 and response_time > 0 do
      # Higher efficiency for more tokens per dollar per second
      total_tokens / cost / (response_time / 1000)
    else
      1.0
    end
  end

  # Universal health monitoring utilities

  @doc """
  Aggregate health status across multiple domains for single provider.
  """
  def aggregate_domain_health(domain_health_map) do
    if Enum.empty?(domain_health_map) do
      %{status: :unknown, overall_health_score: 0.0}
    else
      domain_scores =
        domain_health_map
        |> Map.values()
        |> Enum.map(&calculate_domain_health_score/1)

      overall_score = Enum.sum(domain_scores) / length(domain_scores)

      overall_status =
        cond do
          overall_score >= 0.9 -> :healthy
          overall_score >= 0.7 -> :degraded
          true -> :unhealthy
        end

      %{
        status: overall_status,
        overall_health_score: overall_score,
        domain_breakdown: domain_health_map
      }
    end
  end

  defp calculate_domain_health_score(domain_health) when is_map(domain_health) do
    success_rate = Map.get(domain_health, :success_rate, 0.0)

    response_time_score =
      calculate_response_time_score(Map.get(domain_health, :avg_response_time_ms, 5000))

    error_score = calculate_error_score(Map.get(domain_health, :error_count, 0))

    success_rate * 0.5 + response_time_score * 0.3 + error_score * 0.2
  end

  defp calculate_domain_health_score(_), do: 0.0

  defp calculate_response_time_score(response_time_ms) do
    cond do
      # Excellent
      response_time_ms <= 1000 -> 1.0
      # Good  
      response_time_ms <= 3000 -> 0.8
      # Acceptable
      response_time_ms <= 5000 -> 0.6
      # Poor
      response_time_ms <= 10000 -> 0.4
      # Very poor
      true -> 0.2
    end
  end

  defp calculate_error_score(error_count) do
    cond do
      error_count == 0 -> 1.0
      error_count <= 2 -> 0.8
      error_count <= 5 -> 0.6
      error_count <= 10 -> 0.4
      true -> 0.2
    end
  end

  @doc """
  Validate provider configuration for universal use.
  """
  def validate_universal_provider_config(provider_type, config) do
    with :ok <- validate_basic_config(config),
         :ok <- validate_provider_specific_config(provider_type, config),
         :ok <- validate_domain_configurations(config) do
      :ok
    else
      error -> error
    end
  end

  defp validate_basic_config(config) do
    required_universal_fields = [:enabled, :models]
    missing_fields = Enum.filter(required_universal_fields, &(!Map.has_key?(config, &1)))

    case missing_fields do
      [] -> :ok
      fields -> {:error, "Missing universal config fields: #{inspect(fields)}"}
    end
  end

  defp validate_provider_specific_config(provider_type, config) do
    case provider_type do
      :openai -> validate_openai_universal_config(config)
      :anthropic -> validate_anthropic_universal_config(config)
      :ollama -> validate_ollama_universal_config(config)
      _ -> {:error, "Unknown provider type: #{provider_type}"}
    end
  end

  defp validate_domain_configurations(config) do
    # Validate domain-specific configurations if present
    domain_configs = Map.get(config, :domain_configs, %{})

    invalid_domains =
      domain_configs
      |> Map.keys()
      |> Enum.filter(
        &(&1 not in [:evaluation, :orchestration, :planning, :communication, :tooling])
      )

    case invalid_domains do
      [] -> :ok
      invalid -> {:error, "Invalid domain configurations: #{inspect(invalid)}"}
    end
  end

  defp validate_openai_universal_config(config) do
    # Validate OpenAI-specific universal configuration
    models = Map.get(config, :models, %{})
    valid_models = ["gpt-4o", "gpt-4o-mini", "gpt-3.5-turbo"]

    invalid_models =
      models
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.filter(&(&1 not in valid_models))

    case invalid_models do
      [] -> :ok
      invalid -> {:error, "Invalid OpenAI models: #{inspect(invalid)}"}
    end
  end

  defp validate_anthropic_universal_config(config) do
    # Validate Anthropic-specific universal configuration
    models = Map.get(config, :models, %{})

    valid_models = [
      "claude-3-5-sonnet-20241022",
      "claude-3-haiku-20240307",
      "claude-3-opus-20240229"
    ]

    invalid_models =
      models
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.filter(&(&1 not in valid_models))

    case invalid_models do
      [] -> :ok
      invalid -> {:error, "Invalid Anthropic models: #{inspect(invalid)}"}
    end
  end

  defp validate_ollama_universal_config(config) do
    # Ollama models are flexible, validate endpoint and basic structure
    case Map.get(config, :endpoint) do
      endpoint when is_binary(endpoint) and byte_size(endpoint) > 0 -> :ok
      _ -> {:error, "Valid endpoint required for Ollama configuration"}
    end
  end
end
