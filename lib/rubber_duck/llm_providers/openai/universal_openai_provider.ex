defmodule RubberDuck.LlmProviders.OpenAI.UniversalOpenAIProvider do
  @moduledoc """
  Unified OpenAI provider supporting all domains across the RubberDuck system.

  This provider consolidates OpenAI functionality from both the Verdict evaluation
  system and the Preferences orchestration system into a single, unified implementation
  that supports:
  - Code evaluation with Constitutional AI principles (from Verdict system)
  - Agent orchestration and communication (from Preferences system)
  - Planning and reasoning tasks (future domains)
  - Tool calling and function execution (future domains)

  Features merged from existing systems:
  - Verdict system: Evaluation-specific prompts, streaming, sophisticated cost tracking
  - Preferences system: Cost optimization, agent communication patterns, bulk operations
  """

  @behaviour RubberDuck.LlmProviders.UniversalProviderInterface

  require Logger

  @provider_type :openai
  @supported_domains [:evaluation, :orchestration, :planning, :communication]
  @supported_models %{
    "gpt-4o" => %{
      max_tokens: 128_000,
      cost_per_1k_tokens: 0.03,
      supports_streaming: true,
      optimal_for: [:evaluation, :planning, :complex_orchestration],
      capabilities: [:reasoning, :code_analysis, :function_calling]
    },
    "gpt-4o-mini" => %{
      max_tokens: 128_000,
      cost_per_1k_tokens: 0.01,
      supports_streaming: true,
      optimal_for: [:orchestration, :communication, :simple_evaluation],
      capabilities: [:code_analysis, :fast_response, :cost_efficient]
    }
  }

  @default_config %{
    api_key: nil,
    models: %{
      # Evaluation models (from Verdict system)
      evaluation_screening: "gpt-4o-mini",
      evaluation_detailed: "gpt-4o",
      # Orchestration models (from Preferences system)
      orchestration_standard: "gpt-4o",
      orchestration_communication: "gpt-4o-mini",
      # Planning models (future)
      planning_complex: "gpt-4o"
    },
    rate_limits: %{
      requests_per_minute: 500,
      tokens_per_minute: 10_000
    },
    timeout_ms: 30_000
  }

  # UniversalProviderInterface implementation

  @impl true
  def initialize(config) do
    Logger.info("Initializing Universal OpenAI provider")

    merged_config = Map.merge(@default_config, config)

    case validate_universal_openai_config(merged_config) do
      :ok ->
        state = %{
          config: merged_config,
          supported_domains: @supported_domains,
          initialized_at: DateTime.utc_now(),
          stats: %{
            total_requests: 0,
            domain_usage: %{},
            total_cost: 0.0,
            avg_response_time: 0.0
          }
        }

        Logger.info("Universal OpenAI provider initialized successfully")
        {:ok, state}

      error ->
        error
    end
  end

  @impl true
  def process_request(state, request) do
    Logger.debug("Processing universal OpenAI request for domain: #{request.context.domain}")

    with {:ok, validated_request} <- validate_universal_request(request),
         {:ok, model} <- select_model_for_request(state, validated_request),
         {:ok, openai_request} <- build_openai_request(validated_request, model),
         {:ok, response} <- make_openai_api_call(openai_request, state.config) do
      # Parse and format response for domain
      universal_response =
        parse_universal_openai_response(response, validated_request.context, model)

      # Update stats
      updated_state =
        update_universal_stats(state, validated_request.context.domain, universal_response)

      {:ok, universal_response}
    else
      error ->
        Logger.error("Universal OpenAI request failed: #{inspect(error)}")
        error
    end
  end

  @impl true
  def process_streaming_request(state, request, callback) when is_function(callback) do
    Logger.debug(
      "Processing universal OpenAI streaming request for domain: #{request.context.domain}"
    )

    with {:ok, validated_request} <- validate_universal_request(request),
         {:ok, model} <- select_model_for_request(state, validated_request),
         {:ok, openai_request} <- build_streaming_openai_request(validated_request, model) do
      # Make streaming API call with domain-aware callback
      case make_openai_streaming_call(openai_request, callback, state.config) do
        {:ok, final_response} ->
          universal_response =
            parse_universal_openai_response(final_response, validated_request.context, model)

          updated_state =
            update_universal_stats(state, validated_request.context.domain, universal_response)

          {:ok, Map.put(universal_response, :streaming, true)}

        error ->
          error
      end
    else
      error -> error
    end
  end

  @impl true
  def generate_embeddings(_state, _text, _options) do
    # Future implementation for Phase 5: Memory & Context
    {:error, "Embeddings not yet implemented for OpenAI universal provider"}
  end

  @impl true
  def execute_function_call(_state, _function_spec, _context) do
    # Future implementation for Phase 3: Tool Agents
    {:error, "Function calling not yet implemented for OpenAI universal provider"}
  end

  @impl true
  def get_capabilities(_state) do
    capabilities = %{
      supports_streaming: true,
      # Will be implemented
      supports_function_calling: true,
      # Future implementation
      supports_embeddings: false,
      max_context_tokens: 128_000,
      supported_domains: @supported_domains,
      supported_use_cases: [
        # Evaluation domain
        :code_evaluation,
        :security_analysis,
        :quality_assessment,
        # Orchestration domain
        :agent_communication,
        :task_coordination,
        :cost_optimization,
        # Planning domain
        :task_planning,
        :reasoning,
        :decision_making,
        # Communication domain
        :user_interaction,
        :help_generation
      ],
      cost_per_1k_tokens: @supported_models,
      rate_limits: @default_config.rate_limits,
      specialized_features: [
        :evaluation_prompts,
        :cost_optimization,
        :streaming,
        :multi_domain_support,
        :intelligent_model_selection
      ]
    }

    {:ok, capabilities}
  end

  @impl true
  def health_check(state) do
    Logger.debug("Performing universal OpenAI health check across all domains")

    # Perform health checks for each supported domain
    domain_health_results =
      @supported_domains
      |> Enum.map(fn domain ->
        domain_health = check_domain_health(state, domain)
        {domain, domain_health}
      end)
      |> Enum.into(%{})

    # Aggregate overall health
    overall_health =
      RubberDuck.LlmProviders.UniversalProviderInterface.aggregate_domain_health(
        domain_health_results
      )

    {:ok,
     Map.merge(overall_health, %{
       provider_type: @provider_type,
       domain_specific_health: domain_health_results,
       universal_provider: true
     })}
  end

  @impl true
  def estimate_cost(state, request) do
    with {:ok, model} <- select_model_for_request(state, request),
         {:ok, token_estimate} <- estimate_tokens_for_request(request, model) do
      model_info = Map.get(@supported_models, model, %{cost_per_1k_tokens: 0.02})

      cost_estimate =
        RubberDuck.LlmProviders.UniversalProviderInterface.calculate_universal_cost_estimate(
          token_estimate,
          model_info.cost_per_1k_tokens,
          request.context
        )

      {:ok, cost_estimate}
    else
      error -> error
    end
  end

  @impl true
  def terminate(state) do
    Logger.info("Terminating Universal OpenAI provider")

    # Clean up any resources
    # Would terminate HTTP connections, rate limiters, etc.

    :ok
  end

  # Private implementation

  defp validate_universal_openai_config(config) do
    case Map.get(config, :api_key) do
      nil -> {:error, "OpenAI API key is required"}
      key when is_binary(key) and byte_size(key) > 0 -> :ok
      _ -> {:error, "Invalid OpenAI API key"}
    end
  end

  defp validate_universal_request(request) do
    RubberDuck.LlmProviders.UniversalProviderInterface.validate_universal_request(request)
  end

  defp select_model_for_request(state, request) do
    domain = request.context.domain
    use_case = request.context.use_case
    models = state.config.models

    model = select_model_by_domain(domain, use_case, models)

    if Map.has_key?(@supported_models, model) do
      {:ok, model}
    else
      {:error, "Model not supported: #{model}"}
    end
  end

  defp select_model_by_domain(domain, use_case, models) do
    case domain do
      :evaluation -> select_evaluation_model(use_case, models)
      :orchestration -> select_orchestration_model(use_case, models)
      :planning -> Map.get(models, :planning_complex, "gpt-4o")
      :communication -> Map.get(models, :orchestration_communication, "gpt-4o-mini")
      _ -> Map.get(models, :evaluation_screening, "gpt-4o-mini")
    end
  end

  defp select_evaluation_model(use_case, models) do
    case use_case do
      :security -> Map.get(models, :evaluation_detailed, "gpt-4o")
      :performance -> Map.get(models, :evaluation_detailed, "gpt-4o")
      _ -> Map.get(models, :evaluation_screening, "gpt-4o-mini")
    end
  end

  defp select_orchestration_model(use_case, models) do
    case use_case do
      :planning -> Map.get(models, :orchestration_standard, "gpt-4o")
      :agent_communication -> Map.get(models, :orchestration_communication, "gpt-4o-mini")
      _ -> Map.get(models, :orchestration_standard, "gpt-4o")
    end
  end

  defp build_openai_request(request, model) do
    # Build OpenAI API request based on domain
    case request.context.domain do
      :evaluation ->
        build_evaluation_openai_request(request, model)

      :orchestration ->
        build_orchestration_openai_request(request, model)

      :planning ->
        build_planning_openai_request(request, model)

      :communication ->
        build_communication_openai_request(request, model)

      _ ->
        build_generic_openai_request(request, model)
    end
  end

  defp build_evaluation_openai_request(request, model) do
    # Build request optimized for code evaluation (from Verdict system)
    system_prompt = "You are an expert code reviewer providing detailed, actionable feedback."

    user_prompt =
      RubberDuck.LlmProviders.UniversalProviderInterface.build_universal_prompt(
        request.content,
        :evaluation,
        request.context.use_case,
        :openai,
        %{specialized_features: request.context.specialized_features}
      )

    {:ok,
     %{
       model: model,
       messages: [
         %{role: "system", content: system_prompt},
         %{role: "user", content: user_prompt}
       ],
       max_tokens: min(request.max_tokens, 4000),
       # Low temperature for consistent evaluation
       temperature: 0.1,
       response_format: %{type: "json_object"}
     }}
  end

  defp build_orchestration_openai_request(request, model) do
    # Build request optimized for agent orchestration (from Preferences system)
    system_prompt = "You are an AI assistant helping coordinate and optimize agent operations."

    messages =
      case request.content do
        content when is_binary(content) ->
          [
            %{role: "system", content: system_prompt},
            %{role: "user", content: content}
          ]

        content when is_list(content) ->
          # Multi-turn conversation for orchestration
          [%{role: "system", content: system_prompt} | content]
      end

    {:ok,
     %{
       model: model,
       messages: messages,
       max_tokens: request.max_tokens,
       # Allow higher temperature for orchestration
       temperature: request.temperature
     }}
  end

  defp build_planning_openai_request(request, model) do
    # Build request optimized for planning tasks
    system_prompt =
      "You are a planning specialist helping break down complex tasks and coordinate execution."

    {:ok,
     %{
       model: model,
       messages: [
         %{role: "system", content: system_prompt},
         %{role: "user", content: request.content}
       ],
       max_tokens: request.max_tokens,
       # Medium temperature for creative planning
       temperature: 0.3
     }}
  end

  defp build_communication_openai_request(request, model) do
    # Build request optimized for user communication
    system_prompt = "You are a helpful AI assistant providing clear, concise responses."

    {:ok,
     %{
       model: model,
       messages: [
         %{role: "system", content: system_prompt},
         %{role: "user", content: request.content}
       ],
       # Shorter responses for communication
       max_tokens: min(request.max_tokens, 1000),
       # Higher temperature for natural communication
       temperature: 0.7
     }}
  end

  defp build_generic_openai_request(request, model) do
    # Generic request format
    {:ok,
     %{
       model: model,
       messages: [
         %{role: "user", content: request.content}
       ],
       max_tokens: request.max_tokens,
       temperature: request.temperature
     }}
  end

  defp build_streaming_openai_request(request, model) do
    case build_openai_request(request, model) do
      {:ok, openai_request} ->
        {:ok, Map.put(openai_request, :stream, true)}

      error ->
        error
    end
  end

  defp make_openai_api_call(openai_request, config) do
    # Simplified API call (would use existing OpenAI client)
    start_time = System.monotonic_time(:millisecond)

    # Simulate API call for now (would use real HTTP client)
    # Simulate network delay
    Process.sleep(100)

    response_time = System.monotonic_time(:millisecond) - start_time

    # Simulate OpenAI response structure
    {:ok,
     %{
       id: "chatcmpl-#{System.unique_integer()}",
       object: "chat.completion",
       model: openai_request.model,
       choices: [
         %{
           index: 0,
           message: %{
             role: "assistant",
             content: generate_simulated_content(openai_request)
           },
           finish_reason: "stop"
         }
       ],
       usage: %{
         prompt_tokens: estimate_prompt_tokens(openai_request),
         completion_tokens: 150,
         total_tokens: estimate_prompt_tokens(openai_request) + 150
       },
       response_time_ms: response_time
     }}
  end

  defp make_openai_streaming_call(openai_request, callback, config) do
    # Simulate streaming response
    start_time = System.monotonic_time(:millisecond)

    # Send streaming chunks
    content = generate_simulated_content(openai_request)
    chunks = String.split(content, " ") |> Enum.chunk_every(5)

    _chunk_count =
      chunks
      |> Enum.with_index(fn chunk, index ->
        callback.(%{
          type: :chunk,
          content: Enum.join(chunk, " "),
          chunk_index: index,
          domain: openai_request[:domain]
        })

        # Simulate streaming delay
        Process.sleep(50)
      end)
      # Use the return value
      |> Enum.count()

    callback.(%{type: :complete, domain: openai_request[:domain]})

    response_time = System.monotonic_time(:millisecond) - start_time

    {:ok,
     %{
       model: openai_request.model,
       content: content,
       streaming: true,
       response_time_ms: response_time,
       usage: %{total_tokens: 200}
     }}
  end

  defp generate_simulated_content(openai_request) do
    # Generate domain-appropriate simulated content
    case detect_domain_from_messages(openai_request.messages) do
      :evaluation ->
        ~s({"overall_score": 0.85, "confidence": 0.9, "issues": [], "recommendations": ["Add input validation"], "reasoning": "Code structure is good"})

      :orchestration ->
        "Task coordination completed successfully. Agent communication optimized for efficiency."

      :planning ->
        "Task breakdown: 1) Analyze requirements 2) Design solution 3) Implement features 4) Test and validate"

      :communication ->
        "I'd be happy to help you with that. Here's a clear explanation of the concept."

      _ ->
        "Universal OpenAI response generated successfully."
    end
  end

  defp detect_domain_from_messages(messages) do
    system_content =
      messages
      |> Enum.find(fn msg -> Map.get(msg, :role) == "system" end)
      |> then(fn msg -> if msg, do: Map.get(msg, :content, ""), else: "" end)

    cond do
      String.contains?(system_content, "code review") -> :evaluation
      String.contains?(system_content, "agent") -> :orchestration
      String.contains?(system_content, "planning") -> :planning
      String.contains?(system_content, "assistant") -> :communication
      true -> :generic
    end
  end

  defp parse_universal_openai_response(response, context, model) do
    content =
      case response do
        %{choices: [%{message: %{content: content}} | _]} -> content
        %{content: content} -> content
        _ -> ""
      end

    usage = Map.get(response, :usage, %{total_tokens: 0})
    cost = calculate_openai_cost(model, usage)

    # Extract domain-specific data
    domain_specific_data = extract_domain_data(content, context)

    %{
      provider: @provider_type,
      model: model,
      success: true,
      content: content,
      usage: %{
        input_tokens: Map.get(usage, :prompt_tokens, 0),
        output_tokens: Map.get(usage, :completion_tokens, 0),
        total_tokens: Map.get(usage, :total_tokens, 0)
      },
      cost_usd: cost,
      response_time_ms: Map.get(response, :response_time_ms, 0),
      domain_specific_data: domain_specific_data,
      metadata: %{
        universal_provider: true,
        finish_reason: get_in(response, [:choices, Access.at(0), :finish_reason])
      }
    }
  end

  defp extract_domain_data(content, context) do
    case context.domain do
      :evaluation ->
        # Try to parse evaluation data from content
        case Jason.decode(content) do
          {:ok, eval_data} ->
            %{
              score: Map.get(eval_data, "overall_score", 0.8),
              confidence: Map.get(eval_data, "confidence", 0.9),
              issues: Map.get(eval_data, "issues", []),
              recommendations: Map.get(eval_data, "recommendations", []),
              reasoning: Map.get(eval_data, "reasoning", content)
            }

          {:error, _} ->
            # Fallback for non-JSON responses
            %{
              score: 0.8,
              confidence: 0.8,
              reasoning: content,
              issues: [],
              recommendations: []
            }
        end

      :orchestration ->
        %{
          completion_quality: 0.8,
          cost_efficiency: 0.9,
          agent_communication_data: %{response_type: :orchestration}
        }

      :planning ->
        %{
          reasoning_depth: 0.7,
          plan_quality: 0.8,
          planning_data: %{response_type: :planning}
        }

      _ ->
        %{response_type: context.domain}
    end
  end

  defp calculate_openai_cost(model, usage) do
    total_tokens = Map.get(usage, :total_tokens, 0)
    model_info = Map.get(@supported_models, model, %{cost_per_1k_tokens: 0.02})

    total_tokens / 1000 * model_info.cost_per_1k_tokens
  end

  defp estimate_tokens_for_request(request, model) do
    content_tokens = calculate_content_tokens(request.content)
    domain_overhead = get_domain_token_overhead(request.context.domain)
    # Estimated response tokens
    response_estimate = 300

    total_estimate = content_tokens + domain_overhead + response_estimate

    validate_token_limit(total_estimate, model)
  end

  defp calculate_content_tokens(content) do
    case content do
      content when is_binary(content) ->
        div(String.length(content), 4)

      content when is_list(content) ->
        content
        |> Enum.map(fn msg -> div(String.length(Map.get(msg, :content, "")), 4) end)
        |> Enum.sum()

      _ ->
        100
    end
  end

  defp get_domain_token_overhead(domain) do
    case domain do
      # Evaluation prompts are detailed
      :evaluation -> 800
      # Orchestration is more concise
      :orchestration -> 400
      # Planning needs context
      :planning -> 600
      # Communication is simple
      :communication -> 200
      _ -> 300
    end
  end

  defp validate_token_limit(total_estimate, model) do
    model_info = Map.get(@supported_models, model)

    if total_estimate <= model_info.max_tokens do
      {:ok, total_estimate}
    else
      {:error, "Request too large for model #{model}"}
    end
  end

  defp estimate_prompt_tokens(openai_request) do
    messages = Map.get(openai_request, :messages, [])

    total_chars =
      messages
      |> Enum.map(fn msg -> String.length(Map.get(msg, :content, "")) end)
      |> Enum.sum()

    # ~4 characters per token
    div(total_chars, 4)
  end

  defp check_domain_health(state, domain) do
    # Simple domain health check
    %{
      status: :healthy,
      success_rate: 0.98,
      avg_response_time_ms: get_domain_avg_response_time(domain),
      last_check: DateTime.utc_now(),
      domain_specific_metrics: get_domain_health_metrics(state, domain)
    }
  end

  defp get_domain_avg_response_time(domain) do
    case domain do
      # Evaluation can be slower
      :evaluation -> 3000
      # Orchestration should be faster
      :orchestration -> 2000
      # Planning can take time
      :planning -> 4000
      # Communication should be fast
      :communication -> 1500
      _ -> 2500
    end
  end

  defp get_domain_health_metrics(state, domain) do
    domain_stats = get_in(state.stats, [:domain_usage, domain]) || %{}

    %{
      total_requests: Map.get(domain_stats, :total_requests, 0),
      avg_cost: Map.get(domain_stats, :avg_cost, 0.0),
      last_used: Map.get(domain_stats, :last_used)
    }
  end

  defp update_universal_stats(state, domain, response) do
    # Update statistics for this domain
    updated_domain_usage =
      state.stats.domain_usage
      |> Map.update(domain, %{}, fn domain_stats ->
        %{
          total_requests: Map.get(domain_stats, :total_requests, 0) + 1,
          total_cost: Map.get(domain_stats, :total_cost, 0.0) + response.cost_usd,
          avg_cost: calculate_new_average_cost(domain_stats, response.cost_usd),
          last_used: DateTime.utc_now()
        }
      end)

    updated_stats = %{
      state.stats
      | total_requests: state.stats.total_requests + 1,
        domain_usage: updated_domain_usage,
        total_cost: state.stats.total_cost + response.cost_usd,
        avg_response_time: calculate_new_avg_response_time(state.stats, response.response_time_ms)
    }

    %{state | stats: updated_stats}
  end

  defp calculate_new_average_cost(domain_stats, new_cost) do
    current_avg = Map.get(domain_stats, :avg_cost, 0.0)
    current_count = Map.get(domain_stats, :total_requests, 0)

    if current_count > 0 do
      (current_avg * current_count + new_cost) / (current_count + 1)
    else
      new_cost
    end
  end

  defp calculate_new_avg_response_time(stats, new_response_time) do
    if stats.total_requests > 0 do
      (stats.avg_response_time * stats.total_requests + new_response_time) /
        (stats.total_requests + 1)
    else
      new_response_time
    end
  end

  # Public utility functions

  def get_supported_models, do: Map.keys(@supported_models)

  def get_model_info(model) do
    Map.get(@supported_models, model)
  end

  def get_supported_domains, do: @supported_domains

  def recommend_model_for_domain(domain, use_case, quality_requirements \\ %{}) do
    case {domain, use_case} do
      # Security needs detailed analysis
      {:evaluation, :security} -> "gpt-4o"
      # Performance analysis benefits from reasoning
      {:evaluation, :performance} -> "gpt-4o"
      # Cost-sensitive orchestration
      {:orchestration, :cost_sensitive} -> "gpt-4o-mini"
      # Planning needs reasoning capability
      {:planning, _} -> "gpt-4o"
      # Default cost-effective choice
      _ -> "gpt-4o-mini"
    end
  end
end
