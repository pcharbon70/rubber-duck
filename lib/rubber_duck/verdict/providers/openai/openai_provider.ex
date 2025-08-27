defmodule RubberDuck.Verdict.Providers.OpenAI.OpenAIProvider do
  @moduledoc """
  OpenAI provider implementation for the Verdict framework.

  This module implements the ProviderInterface behavior for OpenAI's GPT models,
  providing:
  - GPT-4o and GPT-4o-mini integration for code evaluation
  - Streaming evaluation support for real-time feedback  
  - Rate limiting and cost optimization
  - Error handling and retry logic with exponential backoff
  - Integration with OpenAI's latest API features
  """

  @behaviour RubberDuck.Verdict.Providers.ProviderInterface

  require Logger

  alias RubberDuck.Verdict.Providers.ProviderInterface
  alias RubberDuck.Verdict.Providers.OpenAI.{OpenAIClient, OpenAIEvaluator, OpenAIRateLimiter}

  @provider_type :openai
  @supported_models %{
    "gpt-4o" => %{
      max_tokens: 128_000,
      cost_per_1k_tokens: 0.03,
      supports_streaming: true,
      capabilities: [:reasoning, :code_analysis, :security_analysis]
    },
    "gpt-4o-mini" => %{
      max_tokens: 128_000,
      cost_per_1k_tokens: 0.01,
      supports_streaming: true,
      capabilities: [:code_analysis, :basic_security]
    }
  }

  @default_config %{
    api_key: nil,
    models: %{
      screening: "gpt-4o-mini",
      detailed: "gpt-4o"
    },
    rate_limits: %{
      requests_per_minute: 500,
      tokens_per_minute: 10_000
    },
    cost_limits: %{
      max_cost_per_evaluation: 0.50,
      daily_budget: 100.00
    },
    timeout_ms: 30_000,
    retry_config: %{
      max_retries: 3,
      base_delay_ms: 1000,
      max_delay_ms: 10_000
    }
  }

  # ProviderInterface implementation

  @impl true
  def initialize(config) do
    Logger.info("Initializing OpenAI provider")

    merged_config = Map.merge(@default_config, config)

    case validate_openai_config(merged_config) do
      :ok ->
        # Initialize HTTP client and rate limiter
        case setup_openai_components(merged_config) do
          {:ok, components} ->
            state = %{
              config: merged_config,
              client: components.client,
              rate_limiter: components.rate_limiter,
              evaluator: components.evaluator,
              initialized_at: DateTime.utc_now(),
              stats: %{
                evaluations_completed: 0,
                total_cost: 0.0,
                avg_response_time: 0.0,
                success_rate: 1.0
              }
            }

            Logger.info("OpenAI provider initialized successfully")
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
    Logger.debug("Starting OpenAI evaluation for type: #{request.evaluation_type}")

    with {:ok, validated_request} <- validate_evaluation_request(request),
         {:ok, rate_limit_check} <- check_rate_limits(state, validated_request),
         {:ok, model} <- select_optimal_model(state, validated_request),
         {:ok, evaluation_result} <- perform_openai_evaluation(state, validated_request, model) do
      # Update provider statistics
      updated_state = update_provider_stats(state, evaluation_result)

      # Standardize response format
      standardized_response =
        ProviderInterface.standardize_response(
          evaluation_result,
          @provider_type,
          model,
          %{provider_state_updated: true}
        )

      Logger.debug("OpenAI evaluation completed successfully")
      {:ok, standardized_response}
    else
      error ->
        Logger.error("OpenAI evaluation failed: #{inspect(error)}")
        error
    end
  end

  @impl true
  def evaluate_code_streaming(state, request, callback) when is_function(callback) do
    Logger.debug("Starting OpenAI streaming evaluation")

    with {:ok, validated_request} <- validate_evaluation_request(request),
         {:ok, _rate_limit_check} <- check_rate_limits(state, validated_request),
         {:ok, model} <- select_optimal_model(state, validated_request) do
      # Perform streaming evaluation with callback for partial results
      case OpenAIEvaluator.evaluate_streaming(state.evaluator, validated_request, model, callback) do
        {:ok, final_result} ->
          updated_state = update_provider_stats(state, final_result)

          standardized_response =
            ProviderInterface.standardize_response(
              final_result,
              @provider_type,
              model,
              %{streaming: true, provider_state_updated: true}
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
      max_context_tokens: 128_000,
      supported_languages: ["elixir", "javascript", "python", "rust", "go", "java", "typescript"],
      evaluation_types: [:quality, :security, :performance, :maintainability, :style],
      cost_per_1k_tokens: @supported_models,
      rate_limits: @default_config.rate_limits,
      provider_strengths: [:general_purpose, :reasoning, :code_analysis],
      streaming_latency_ms: 200
    }

    {:ok, capabilities}
  end

  @impl true
  def health_check(state) do
    Logger.debug("Performing OpenAI provider health check")

    start_time = System.monotonic_time(:millisecond)

    # Simple health check: verify API access with minimal request
    health_request = %{
      model: "gpt-4o-mini",
      messages: [%{role: "user", content: "Health check"}],
      max_tokens: 10
    }

    case OpenAIClient.complete(state.client, health_request) do
      {:ok, _response} ->
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
           rate_limit_remaining: get_rate_limit_status(state),
           cost_budget_remaining: get_budget_remaining(state)
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
    with {:ok, model} <- select_optimal_model(state, request),
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
    Logger.info("Terminating OpenAI provider")

    # Clean up any persistent connections or resources
    if state.client do
      OpenAIClient.shutdown(state.client)
    end

    if state.rate_limiter do
      OpenAIRateLimiter.shutdown(state.rate_limiter)
    end

    :ok
  end

  # Private implementation

  defp validate_openai_config(config) do
    required_fields = [:api_key]
    missing_fields = Enum.filter(required_fields, &is_nil(Map.get(config, &1)))

    case missing_fields do
      [] -> validate_openai_models_config(config)
      fields -> {:error, "Missing OpenAI configuration: #{inspect(fields)}"}
    end
  end

  defp validate_openai_models_config(config) do
    models = Map.get(config, :models, %{})
    available_models = Map.keys(@supported_models)

    invalid_models =
      models
      |> Map.values()
      |> Enum.filter(&(&1 not in available_models))

    case invalid_models do
      [] -> :ok
      invalid -> {:error, "Unsupported OpenAI models: #{inspect(invalid)}"}
    end
  end

  defp setup_openai_components(config) do
    with {:ok, client} <- OpenAIClient.initialize(config),
         {:ok, rate_limiter} <- OpenAIRateLimiter.initialize(config.rate_limits),
         {:ok, evaluator} <- OpenAIEvaluator.initialize(config) do
      {:ok,
       %{
         client: client,
         rate_limiter: rate_limiter,
         evaluator: evaluator
       }}
    else
      error -> error
    end
  end

  defp validate_evaluation_request(request) do
    ProviderInterface.validate_evaluation_request(request)
  end

  defp check_rate_limits(state, request) do
    # Use conservative estimate
    estimated_tokens = estimate_token_usage(request, "gpt-4o-mini") |> elem(1)

    case OpenAIRateLimiter.check_limits(state.rate_limiter, 1, estimated_tokens) do
      :ok -> {:ok, :allowed}
      {:error, :rate_limited} = error -> error
      {:wait, delay_ms} -> {:ok, {:wait_required, delay_ms}}
    end
  end

  defp select_optimal_model(state, request) do
    models = state.config.models
    complexity_score = calculate_request_complexity(request)

    # Select model based on complexity and quality requirements
    model =
      cond do
        complexity_score > 0.8 or request.quality_threshold > 0.9 ->
          Map.get(models, :detailed, "gpt-4o")

        request.evaluation_type in [:security, :performance] ->
          Map.get(models, :detailed, "gpt-4o")

        true ->
          Map.get(models, :screening, "gpt-4o-mini")
      end

    if Map.has_key?(@supported_models, model) do
      {:ok, model}
    else
      {:error, "Model not supported: #{model}"}
    end
  end

  defp calculate_request_complexity(request) do
    base_complexity = 0.5

    # Adjust for code length
    code_complexity = min(0.3, String.length(request.code) / 5000)

    # Adjust for evaluation type
    type_complexity =
      case request.evaluation_type do
        :security -> 0.3
        :performance -> 0.25
        :quality -> 0.2
        :maintainability -> 0.15
        :style -> 0.1
        _ -> 0.2
      end

    min(1.0, base_complexity + code_complexity + type_complexity)
  end

  defp perform_openai_evaluation(state, request, model) do
    # Build OpenAI-specific evaluation prompt
    evaluation_prompt = build_openai_evaluation_prompt(request, model)

    openai_request = %{
      model: model,
      messages: [
        %{role: "system", content: get_system_prompt(request.evaluation_type)},
        %{role: "user", content: evaluation_prompt}
      ],
      # Leave room for response
      max_tokens: min(request.max_tokens, 4000),
      # Low temperature for consistent evaluations
      temperature: 0.1,
      response_format: %{type: "json_object"}
    }

    case OpenAIEvaluator.evaluate(state.evaluator, openai_request) do
      {:ok, response} ->
        parse_openai_response(response, request)

      error ->
        error
    end
  end

  defp build_openai_evaluation_prompt(request, model) do
    ProviderInterface.build_evaluation_prompt(
      request.code,
      request.evaluation_type,
      request.criteria,
      @provider_type
    )
  end

  defp get_system_prompt(evaluation_type) do
    base_prompt = "You are an expert code reviewer providing detailed, actionable feedback."

    type_specific =
      case evaluation_type do
        :security ->
          " Focus on identifying security vulnerabilities and recommending secure coding practices."

        :performance ->
          " Focus on performance optimization opportunities and efficiency improvements."

        :quality ->
          " Focus on overall code quality including correctness, readability, and maintainability."

        :maintainability ->
          " Focus on long-term maintainability and code organization."

        :style ->
          " Focus on code style, formatting, and adherence to language conventions."

        _ ->
          " Provide comprehensive analysis across all quality dimensions."
      end

    base_prompt <> type_specific <> " Always respond with valid JSON in the specified format."
  end

  defp parse_openai_response(response, original_request) do
    case Map.get(response, :choices) do
      [%{message: %{content: content}} | _] ->
        case Jason.decode(content) do
          {:ok, evaluation_data} ->
            {:ok,
             %{
               success: true,
               score: Map.get(evaluation_data, "overall_score", 0.7),
               confidence: Map.get(evaluation_data, "confidence", 0.8),
               issues: Map.get(evaluation_data, "issues", []),
               recommendations: Map.get(evaluation_data, "recommendations", []),
               reasoning: Map.get(evaluation_data, "reasoning", ""),
               cost_usd: calculate_actual_cost(response),
               tokens_used: get_token_usage(response),
               response_time_ms: Map.get(response, :response_time_ms, 0),
               metadata: %{
                 model: Map.get(response, :model, "gpt-4o-mini"),
                 finish_reason: get_in(response, [:choices, Access.at(0), :finish_reason])
               }
             }}

          {:error, json_error} ->
            # Fallback: parse as plain text
            Logger.warning(
              "OpenAI response not valid JSON, parsing as text: #{inspect(json_error)}"
            )

            ProviderInterface.extract_evaluation_result(content)
        end

      _ ->
        {:error, "Invalid OpenAI response format"}
    end
  end

  defp calculate_actual_cost(response) do
    # Extract token usage from response
    case Map.get(response, :usage) do
      %{total_tokens: total_tokens} ->
        model = Map.get(response, :model, "gpt-4o-mini")
        model_info = Map.get(@supported_models, model, %{cost_per_1k_tokens: 0.015})
        total_tokens / 1000 * model_info.cost_per_1k_tokens

      _ ->
        0.0
    end
  end

  defp get_token_usage(response) do
    case Map.get(response, :usage) do
      %{total_tokens: total_tokens} -> total_tokens
      _ -> 0
    end
  end

  defp estimate_token_usage(request, model) do
    model_info = Map.get(@supported_models, model)

    if model_info do
      # Estimate based on code length and evaluation complexity
      # ~4 chars per token
      code_tokens = div(String.length(request.code), 4)

      prompt_tokens =
        case request.evaluation_type do
          :security -> 800
          :performance -> 600
          :quality -> 500
          _ -> 400
        end

      # Estimated response length
      response_tokens = 500

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

  defp update_provider_stats(state, evaluation_result) do
    current_stats = state.stats
    evaluations_count = current_stats.evaluations_completed + 1

    # Update running averages
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

    updated_stats = %{
      evaluations_completed: evaluations_count,
      total_cost: new_total_cost,
      avg_response_time: new_avg_response_time,
      success_rate: new_success_rate
    }

    %{state | stats: updated_stats}
  end

  defp calculate_new_average(current_avg, new_value, count) do
    (current_avg * (count - 1) + new_value) / count
  end

  defp get_rate_limit_status(state) do
    case OpenAIRateLimiter.get_status(state.rate_limiter) do
      {:ok, status} -> status
      _ -> %{requests_remaining: 0, tokens_remaining: 0}
    end
  end

  defp get_budget_remaining(state) do
    daily_budget = state.config.cost_limits.daily_budget
    # Simplified - would track daily spending
    spent_today = state.stats.total_cost
    max(0.0, daily_budget - spent_today)
  end

  # Helper functions for OpenAI-specific logic

  def get_supported_models, do: Map.keys(@supported_models)

  def get_model_info(model) when model in ["gpt-4o", "gpt-4o-mini"] do
    Map.get(@supported_models, model)
  end

  def get_model_info(_), do: nil

  def calculate_cost_for_tokens(model, token_count) when is_integer(token_count) do
    case Map.get(@supported_models, model) do
      %{cost_per_1k_tokens: rate} -> token_count / 1000 * rate
      _ -> 0.0
    end
  end

  def recommend_model_for_evaluation(evaluation_type, quality_threshold, budget_constraint) do
    case {evaluation_type, quality_threshold, budget_constraint} do
      # High quality or complex evaluations
      {type, threshold, _} when type in [:security, :performance] or threshold > 0.9 ->
        "gpt-4o"

      # Budget-conscious evaluations
      {_, threshold, budget} when threshold <= 0.8 and budget <= 0.1 ->
        "gpt-4o-mini"

      # Balanced approach
      _ ->
        # Default to cost-effective option
        "gpt-4o-mini"
    end
  end
end
