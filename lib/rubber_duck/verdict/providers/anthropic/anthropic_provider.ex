defmodule RubberDuck.Verdict.Providers.Anthropic.AnthropicProvider do
  @moduledoc """
  Anthropic provider implementation for the Verdict framework.

  This module implements the ProviderInterface behavior for Anthropic's Claude models,
  providing:
  - Claude-3 family integration with Constitutional AI principles
  - Large context window optimization for complex code evaluation
  - Safety-first evaluation with bias detection and mitigation
  - Streaming support for real-time evaluation feedback
  - Integration with Claude's reasoning capabilities
  """

  @behaviour RubberDuck.Verdict.Providers.ProviderInterface

  require Logger

  alias RubberDuck.Verdict.Providers.ProviderInterface
  alias RubberDuck.Verdict.Providers.Anthropic.{AnthropicClient, AnthropicEvaluator}

  @provider_type :anthropic
  @supported_models %{
    "claude-3-5-sonnet-20241022" => %{
      max_tokens: 200_000,
      cost_per_1k_tokens: 0.015,
      supports_streaming: true,
      capabilities: [:reasoning, :code_analysis, :security_analysis, :constitutional_ai]
    },
    "claude-3-haiku-20240307" => %{
      max_tokens: 200_000,
      cost_per_1k_tokens: 0.01,
      supports_streaming: true,
      capabilities: [:code_analysis, :fast_evaluation]
    },
    "claude-3-opus-20240229" => %{
      max_tokens: 200_000,
      cost_per_1k_tokens: 0.075,
      supports_streaming: true,
      capabilities: [:deep_reasoning, :complex_analysis, :constitutional_ai]
    }
  }

  @default_config %{
    api_key: nil,
    models: %{
      screening: "claude-3-haiku-20240307",
      detailed: "claude-3-5-sonnet-20241022",
      comprehensive: "claude-3-opus-20240229"
    },
    constitutional_ai: %{
      safety_checks: true,
      bias_mitigation: true,
      content_filtering: true
    },
    rate_limits: %{
      requests_per_minute: 100,
      tokens_per_minute: 40_000
    },
    # Claude can be slower but more thorough
    timeout_ms: 45_000,
    context_optimization: %{
      max_context_tokens: 200_000,
      chunking_strategy: :semantic
    }
  }

  # ProviderInterface implementation

  @impl true
  def initialize(config) do
    Logger.info("Initializing Anthropic provider")

    merged_config = Map.merge(@default_config, config)

    case validate_anthropic_config(merged_config) do
      :ok ->
        case setup_anthropic_components(merged_config) do
          {:ok, components} ->
            state = %{
              config: merged_config,
              client: components.client,
              evaluator: components.evaluator,
              initialized_at: DateTime.utc_now(),
              stats: %{
                evaluations_completed: 0,
                total_cost: 0.0,
                avg_response_time: 0.0,
                success_rate: 1.0,
                safety_checks_performed: 0
              }
            }

            Logger.info("Anthropic provider initialized successfully")
            {:ok, state}

          error ->
            error
        end

      error ->
        error
    end
  end

  @impl true
  def evaluate_code(state, request) do
    Logger.debug("Starting Anthropic evaluation for type: #{request.evaluation_type}")

    with {:ok, validated_request} <- validate_evaluation_request(request),
         {:ok, model} <- select_optimal_claude_model(state, validated_request),
         {:ok, constitutional_check} <- perform_constitutional_ai_check(state, validated_request),
         {:ok, evaluation_result} <- perform_anthropic_evaluation(state, validated_request, model) do
      # Apply Constitutional AI post-processing
      processed_result =
        apply_constitutional_ai_processing(evaluation_result, constitutional_check)

      # Update provider statistics
      updated_state = update_provider_stats(state, processed_result, constitutional_check)

      # Standardize response format
      standardized_response =
        ProviderInterface.standardize_response(
          processed_result,
          @provider_type,
          model,
          %{constitutional_ai: constitutional_check}
        )

      Logger.debug("Anthropic evaluation completed successfully")
      {:ok, standardized_response}
    else
      error ->
        Logger.error("Anthropic evaluation failed: #{inspect(error)}")
        error
    end
  end

  @impl true
  def evaluate_code_streaming(state, request, callback) when is_function(callback) do
    Logger.debug("Starting Anthropic streaming evaluation")

    with {:ok, validated_request} <- validate_evaluation_request(request),
         {:ok, model} <- select_optimal_claude_model(state, validated_request),
         {:ok, constitutional_check} <- perform_constitutional_ai_check(state, validated_request) do
      # Perform streaming evaluation with Constitutional AI monitoring
      case AnthropicEvaluator.evaluate_streaming(
             state.evaluator,
             validated_request,
             model,
             callback
           ) do
        {:ok, final_result} ->
          processed_result =
            apply_constitutional_ai_processing(final_result, constitutional_check)

          updated_state = update_provider_stats(state, processed_result, constitutional_check)

          standardized_response =
            ProviderInterface.standardize_response(
              processed_result,
              @provider_type,
              model,
              %{streaming: true, constitutional_ai: constitutional_check}
            )

          {:ok, standardized_response}

        error ->
          error
      end
    else
      error -> error
    end
  end

  @impl true
  def get_capabilities(_state) do
    capabilities = %{
      supports_streaming: true,
      supports_function_calling: true,
      max_context_tokens: 200_000,
      supported_languages: ["elixir", "javascript", "python", "rust", "go", "java", "typescript"],
      evaluation_types: [:quality, :security, :performance, :maintainability, :style],
      cost_per_1k_tokens: @supported_models,
      rate_limits: @default_config.rate_limits,
      provider_strengths: [:reasoning, :safety, :constitutional_ai, :large_context],
      constitutional_ai_features: [:safety_checks, :bias_mitigation, :content_filtering],
      streaming_latency_ms: 300
    }

    {:ok, capabilities}
  end

  @impl true
  def health_check(state) do
    Logger.debug("Performing Anthropic provider health check")

    start_time = System.monotonic_time(:millisecond)

    # Simple health check with Claude
    health_request = %{
      model: "claude-3-haiku-20240307",
      messages: [%{role: "user", content: "Health check - respond with 'OK'"}],
      max_tokens: 10
    }

    case AnthropicClient.complete(state.client, health_request) do
      {:ok, response} ->
        response_time = System.monotonic_time(:millisecond) - start_time

        health_data =
          ProviderInterface.parse_health_status(
            response_time,
            state.stats.success_rate,
            # No current errors for successful health check
            0
          )

        {:ok,
         Map.merge(health_data, %{
           provider_type: @provider_type,
           api_accessible: true,
           constitutional_ai_active: state.config.constitutional_ai.safety_checks,
           context_optimization_enabled: true,
           model_availability: check_model_availability(state)
         })}

      {:error, reason} ->
        response_time = System.monotonic_time(:millisecond) - start_time

        {:error,
         %{
           provider_type: @provider_type,
           reason: reason,
           response_time_ms: response_time,
           api_accessible: false
         }}
    end
  end

  @impl true
  def estimate_cost(state, request) do
    with {:ok, model} <- select_optimal_claude_model(state, request),
         {:ok, token_estimate} <- estimate_token_usage(request, model) do
      model_info = Map.get(@supported_models, model, %{cost_per_1k_tokens: 0.015})

      cost_estimate =
        ProviderInterface.calculate_cost_estimate(
          token_estimate,
          model_info.cost_per_1k_tokens
        )

      {:ok, cost_estimate}
    else
      error -> error
    end
  end

  @impl true
  def terminate(state) do
    Logger.info("Terminating Anthropic provider")

    # Clean up resources
    if state.client do
      AnthropicClient.shutdown(state.client)
    end

    :ok
  end

  # Private implementation

  defp validate_anthropic_config(config) do
    required_fields = [:api_key]
    missing_fields = Enum.filter(required_fields, &is_nil(Map.get(config, &1)))

    case missing_fields do
      [] -> validate_anthropic_models_config(config)
      fields -> {:error, "Missing Anthropic configuration: #{inspect(fields)}"}
    end
  end

  defp validate_anthropic_models_config(config) do
    models = Map.get(config, :models, %{})
    available_models = Map.keys(@supported_models)

    invalid_models =
      models
      |> Map.values()
      |> Enum.filter(&(&1 not in available_models))

    case invalid_models do
      [] -> :ok
      invalid -> {:error, "Unsupported Claude models: #{inspect(invalid)}"}
    end
  end

  defp setup_anthropic_components(config) do
    with {:ok, client} <- AnthropicClient.initialize(config),
         {:ok, evaluator} <- AnthropicEvaluator.initialize(config) do
      {:ok,
       %{
         client: client,
         evaluator: evaluator
       }}
    else
      error -> error
    end
  end

  defp validate_evaluation_request(request) do
    ProviderInterface.validate_evaluation_request(request)
  end

  defp select_optimal_claude_model(state, request) do
    models = state.config.models
    complexity_score = calculate_request_complexity(request)

    # Select Claude model based on complexity and requirements
    model =
      cond do
        # Use Opus for most complex evaluations
        complexity_score > 0.9 or request.quality_threshold > 0.95 ->
          Map.get(models, :comprehensive, "claude-3-opus-20240229")

        # Use Sonnet for detailed analysis
        complexity_score > 0.7 or request.evaluation_type in [:security, :performance] ->
          Map.get(models, :detailed, "claude-3-5-sonnet-20241022")

        # Use Haiku for quick evaluations
        true ->
          Map.get(models, :screening, "claude-3-haiku-20240307")
      end

    if Map.has_key?(@supported_models, model) do
      {:ok, model}
    else
      {:error, "Model not supported: #{model}"}
    end
  end

  defp calculate_request_complexity(request) do
    base_complexity = 0.5

    # Adjust for code length (Claude handles large context well)
    code_complexity = min(0.2, String.length(request.code) / 10_000)

    # Adjust for evaluation type
    type_complexity =
      case request.evaluation_type do
        # Claude excels at security analysis
        :security -> 0.4
        :performance -> 0.3
        :quality -> 0.2
        :maintainability -> 0.25
        :style -> 0.1
        _ -> 0.25
      end

    min(1.0, base_complexity + code_complexity + type_complexity)
  end

  defp perform_constitutional_ai_check(state, request) do
    if state.config.constitutional_ai.safety_checks do
      # Perform Constitutional AI safety assessment
      safety_assessment = %{
        content_safety: assess_content_safety(request.code),
        bias_check: assess_potential_bias(request),
        harm_potential: assess_harm_potential(request),
        constitutional_compliance: true
      }

      {:ok, safety_assessment}
    else
      {:ok, %{constitutional_ai_disabled: true}}
    end
  end

  defp assess_content_safety(code) do
    # Simple content safety check
    concerning_patterns = [
      "password",
      "secret",
      "token",
      "key",
      "hack",
      "exploit",
      "bypass"
    ]

    detected_patterns =
      Enum.filter(concerning_patterns, fn pattern ->
        String.contains?(String.downcase(code), pattern)
      end)

    %{
      status: if(Enum.empty?(detected_patterns), do: :safe, else: :review_needed),
      detected_patterns: detected_patterns,
      safety_score: 1.0 - length(detected_patterns) * 0.1
    }
  end

  defp assess_potential_bias(request) do
    # Basic bias assessment based on evaluation criteria
    criteria = request.criteria

    # Check for balanced criteria weights
    weights = Map.values(criteria)
    max_weight = if Enum.empty?(weights), do: 0.5, else: Enum.max(weights)

    %{
      bias_risk: if(max_weight > 0.7, do: :high, else: :low),
      criteria_balance: 1.0 - max_weight,
      bias_score: min(1.0, 1.0 - (max_weight - 0.5))
    }
  end

  defp assess_harm_potential(request) do
    # Assess if the evaluation could lead to harmful outcomes
    evaluation_type = request.evaluation_type

    harm_risk =
      case evaluation_type do
        # Security analysis is beneficial
        :security -> :low
        # Performance optimization is beneficial
        :performance -> :low
        _ -> :minimal
      end

    %{
      harm_risk: harm_risk,
      harm_mitigation: :active,
      harm_score: 0.95
    }
  end

  defp perform_anthropic_evaluation(state, request, model) do
    # Build Anthropic-specific evaluation request
    anthropic_request = build_anthropic_request(request, model, state.config)

    case AnthropicEvaluator.evaluate(state.evaluator, anthropic_request) do
      {:ok, response} ->
        parse_anthropic_response(response, request)

      error ->
        error
    end
  end

  defp build_anthropic_request(request, model, config) do
    # Build Claude-optimized request
    system_prompt = build_constitutional_ai_system_prompt(request.evaluation_type, config)

    user_prompt =
      ProviderInterface.build_evaluation_prompt(
        request.code,
        request.evaluation_type,
        request.criteria,
        @provider_type
      )

    %{
      model: model,
      system: system_prompt,
      messages: [%{role: "user", content: user_prompt}],
      max_tokens: min(request.max_tokens, 4000),
      # Deterministic for code evaluation
      temperature: 0.0,
      top_p: 1.0
    }
  end

  defp build_constitutional_ai_system_prompt(evaluation_type, config) do
    base_prompt = get_claude_system_prompt(evaluation_type)

    constitutional_additions =
      if config.constitutional_ai.safety_checks do
        """

        Constitutional AI Guidelines:
        - Ensure your evaluation is helpful, harmless, and honest
        - Avoid bias in your assessment and recommendations
        - Focus on constructive, actionable feedback
        - Respect user privacy and code confidentiality
        - Promote safe and secure coding practices
        """
      else
        ""
      end

    base_prompt <> constitutional_additions
  end

  defp get_claude_system_prompt(evaluation_type) do
    case evaluation_type do
      :security ->
        """
        You are Claude, an AI assistant specializing in cybersecurity and secure coding practices.
        Your task is to thoroughly analyze code for security vulnerabilities while applying Constitutional AI principles.

        Focus on:
        - Identifying genuine security risks without creating false alarms
        - Providing constructive remediation guidance
        - Considering the broader security context
        - Ensuring recommendations promote safe, secure practices
        """

      :performance ->
        """
        You are Claude, an AI assistant with expertise in performance optimization and system efficiency.
        Apply your reasoning capabilities to analyze code performance characteristics.

        Evaluate:
        - Algorithmic efficiency and complexity analysis
        - Resource utilization patterns
        - Scalability considerations
        - Performance optimization opportunities
        """

      :quality ->
        """
        You are Claude, an AI assistant focused on code quality and software engineering best practices.
        Use your understanding of software development to provide comprehensive quality assessment.

        Assess:
        - Code correctness and logic flow
        - Maintainability and readability
        - Error handling and robustness
        - Best practice adherence
        """

      _ ->
        """
        You are Claude, an AI assistant providing expert code evaluation.
        Apply Constitutional AI principles to ensure your analysis is helpful, accurate, and constructive.
        """
    end
  end

  defp parse_anthropic_response(response, original_request) do
    case Map.get(response, :content) do
      [%{text: content} | _] ->
        case Jason.decode(content) do
          {:ok, evaluation_data} ->
            {:ok,
             %{
               success: true,
               score: Map.get(evaluation_data, "overall_score", 0.8),
               confidence: Map.get(evaluation_data, "confidence", 0.9),
               issues: Map.get(evaluation_data, "issues", []),
               recommendations: Map.get(evaluation_data, "recommendations", []),
               reasoning: Map.get(evaluation_data, "reasoning", ""),
               cost_usd: calculate_anthropic_cost(response),
               tokens_used: get_anthropic_token_usage(response),
               response_time_ms: Map.get(response, :response_time_ms, 0),
               metadata: %{
                 model: Map.get(response, :model, "claude-3-haiku-20240307"),
                 stop_reason: Map.get(response, :stop_reason)
               }
             }}

          {:error, json_error} ->
            Logger.warning(
              "Anthropic response not valid JSON, parsing as text: #{inspect(json_error)}"
            )

            ProviderInterface.extract_evaluation_result(content)
        end

      _ ->
        {:error, "Invalid Anthropic response format"}
    end
  end

  defp apply_constitutional_ai_processing(evaluation_result, constitutional_check) do
    # Apply Constitutional AI principles to filter and enhance results
    if constitutional_check.constitutional_compliance do
      # Enhance recommendations with Constitutional AI principles
      enhanced_recommendations =
        evaluation_result.recommendations
        |> Enum.map(&enhance_recommendation_with_constitutional_ai/1)
        |> add_constitutional_ai_recommendations(evaluation_result, constitutional_check)

      %{
        evaluation_result
        | recommendations: enhanced_recommendations,
          metadata: Map.put(evaluation_result.metadata, :constitutional_ai_processed, true)
      }
    else
      evaluation_result
    end
  end

  defp enhance_recommendation_with_constitutional_ai(recommendation) do
    # Ensure recommendations are constructive and helpful
    if String.contains?(recommendation, ["avoid", "don't", "never"]) do
      # Convert negative recommendations to positive ones
      positive_version = String.replace(recommendation, ~r/(avoid|don't|never)\s+/i, "consider ")
      "Constitutional AI enhanced: #{positive_version}"
    else
      recommendation
    end
  end

  defp add_constitutional_ai_recommendations(
         recommendations,
         evaluation_result,
         constitutional_check
       ) do
    constitutional_recs = []

    # Add safety recommendations if content safety issues detected
    constitutional_recs =
      case constitutional_check.content_safety.status do
        :review_needed ->
          [
            "Consider reviewing code for security-sensitive patterns and ensuring proper safeguards"
          ] ++ constitutional_recs

        _ ->
          constitutional_recs
      end

    # Add bias mitigation if needed
    constitutional_recs =
      case constitutional_check.bias_check.bias_risk do
        :high ->
          ["Consider ensuring evaluation criteria are balanced to avoid bias"] ++
            constitutional_recs

        _ ->
          constitutional_recs
      end

    recommendations ++ constitutional_recs
  end

  defp calculate_anthropic_cost(response) do
    # Extract token usage from Anthropic response
    case Map.get(response, :usage) do
      %{input_tokens: input_tokens, output_tokens: output_tokens} ->
        model = Map.get(response, :model, "claude-3-haiku-20240307")
        model_info = Map.get(@supported_models, model, %{cost_per_1k_tokens: 0.015})

        # Anthropic charges for input and output tokens
        total_tokens = input_tokens + output_tokens
        total_tokens / 1000 * model_info.cost_per_1k_tokens

      _ ->
        0.0
    end
  end

  defp get_anthropic_token_usage(response) do
    case Map.get(response, :usage) do
      %{input_tokens: input_tokens, output_tokens: output_tokens} ->
        input_tokens + output_tokens

      _ ->
        0
    end
  end

  defp estimate_token_usage(request, model) do
    model_info = Map.get(@supported_models, model)

    if model_info do
      # Claude can handle very large contexts efficiently
      # Claude tokenization is more efficient
      code_tokens = trunc(String.length(request.code) / 3.5)

      prompt_tokens =
        case request.evaluation_type do
          # Detailed security analysis
          :security -> 1000
          # Performance analysis
          :performance -> 800
          # General quality
          :quality -> 600
          _ -> 500
        end

      # Claude provides detailed responses
      response_tokens = 600

      total_estimate = code_tokens + prompt_tokens + response_tokens

      if total_estimate <= model_info.max_tokens do
        {:ok, total_estimate}
      else
        {:error,
         "Request too large for model #{model} (#{total_estimate} > #{model_info.max_tokens})"}
      end
    else
      {:error, "Unknown model: #{model}"}
    end
  end

  defp update_provider_stats(state, evaluation_result, constitutional_check) do
    current_stats = state.stats
    evaluations_count = current_stats.evaluations_completed + 1

    # Update statistics
    new_total_cost = current_stats.total_cost + evaluation_result.cost_usd

    new_avg_response_time =
      calculate_new_average(
        current_stats.avg_response_time,
        evaluation_result.response_time_ms,
        evaluations_count
      )

    new_success_rate =
      if evaluation_result.success do
        calculate_new_average(current_stats.success_rate, 1.0, evaluations_count)
      else
        calculate_new_average(current_stats.success_rate, 0.0, evaluations_count)
      end

    safety_checks_performed =
      if constitutional_check.constitutional_compliance do
        current_stats.safety_checks_performed + 1
      else
        current_stats.safety_checks_performed
      end

    updated_stats = %{
      evaluations_completed: evaluations_count,
      total_cost: new_total_cost,
      avg_response_time: new_avg_response_time,
      success_rate: new_success_rate,
      safety_checks_performed: safety_checks_performed
    }

    %{state | stats: updated_stats}
  end

  defp calculate_new_average(current_avg, new_value, count) do
    (current_avg * (count - 1) + new_value) / count
  end

  defp check_model_availability(state) do
    # Check which Claude models are available
    configured_models = Map.values(state.config.models)
    available_models = Map.keys(@supported_models)

    %{
      configured_models: configured_models,
      available_models: available_models,
      all_configured_available: Enum.all?(configured_models, &(&1 in available_models))
    }
  end

  # Public helper functions

  def get_supported_models, do: Map.keys(@supported_models)

  def get_model_info(model)
      when model in [
             "claude-3-5-sonnet-20241022",
             "claude-3-haiku-20240307",
             "claude-3-opus-20240229"
           ] do
    Map.get(@supported_models, model)
  end

  def get_model_info(_), do: nil

  def calculate_cost_for_tokens(model, token_count) when is_integer(token_count) do
    case Map.get(@supported_models, model) do
      %{cost_per_1k_tokens: rate} -> token_count / 1000 * rate
      _ -> 0.0
    end
  end

  def recommend_claude_model_for_evaluation(evaluation_type, quality_threshold, context_size) do
    case {evaluation_type, quality_threshold, context_size} do
      # Use Opus for highest quality or very complex evaluations
      {_, threshold, _} when threshold > 0.95 ->
        "claude-3-opus-20240229"

      # Use Sonnet for security and performance analysis
      {type, _, _} when type in [:security, :performance] ->
        "claude-3-5-sonnet-20241022"

      # Use Haiku for quick evaluations
      {_, threshold, size} when threshold <= 0.8 and size < 5000 ->
        "claude-3-haiku-20240307"

      # Default to Sonnet for balanced performance
      _ ->
        "claude-3-5-sonnet-20241022"
    end
  end
end
