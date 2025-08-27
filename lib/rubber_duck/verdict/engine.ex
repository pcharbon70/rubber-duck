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

  alias RubberDuck.Verdict.Optimization.{IntelligentCache, ProgressiveEvaluator}
  alias RubberDuck.Verdict.Resources.{EvaluationResult, EvaluationRun}
  alias RubberDuck.Verdict.Configuration.VerdictConfigurationResolver
  alias RubberDuck.LlmProviders.Adapters.EvaluationAdapter

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
      :ok -> perform_tracked_evaluation(code, evaluation_type, options)
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
        description:
          "Overall code quality assessment including readability, maintainability, and best practices",
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

  defp validate_evaluation_request(code, evaluation_type, _options) do
    cond do
      is_nil(code) or code == "" ->
        {:error, "Code cannot be empty"}

      not is_atom(evaluation_type) ->
        {:error, "Evaluation type must be an atom"}

      evaluation_type not in [
        :quality,
        :security,
        :performance,
        :maintainability,
        :best_practices,
        :comprehensive
      ] ->
        {:error, "Invalid evaluation type: #{evaluation_type}"}

      String.length(code) > 50_000 ->
        {:error, "Code too large for evaluation (max 50,000 characters)"}

      true ->
        :ok
    end
  end

  defp perform_tracked_evaluation(code, evaluation_type, options) do
    user_id = Keyword.get(options, :user_id)
    project_id = Keyword.get(options, :project_id)

    # Get evaluation configuration
    case get_evaluation_config(user_id, project_id) do
      {:ok, config} ->
        case create_evaluation_run(code, evaluation_type, config, options) do
          {:ok, evaluation_run} ->
            execute_tracked_evaluation_pipeline(
              evaluation_run,
              code,
              evaluation_type,
              config,
              options
            )

          error ->
            error
        end

      error ->
        error
    end
  end

  defp create_evaluation_run(code, evaluation_type, config, options) do
    user_id = Keyword.get(options, :user_id)
    project_id = Keyword.get(options, :project_id)

    code_hash = :crypto.hash(:sha256, code) |> Base.encode16()

    run_params = %{
      user_id: user_id,
      project_id: project_id,
      evaluation_type: evaluation_type,
      code_hash: code_hash,
      code_size_bytes: byte_size(code),
      configuration_snapshot: config,
      evaluation_strategy: determine_initial_strategy(evaluation_type, config),
      metadata: %{
        created_via: "verdict_engine",
        options: Map.new(options)
      }
    }

    case EvaluationRun.create(run_params) do
      {:ok, run} ->
        # Mark as started
        EvaluationRun.start_evaluation(run)

      error ->
        error
    end
  end

  defp execute_tracked_evaluation_pipeline(evaluation_run, code, evaluation_type, config, options) do
    # Execute the evaluation and track results
    case execute_evaluation_pipeline(code, evaluation_type, config, options) do
      {:ok, result} ->
        case store_evaluation_results(evaluation_run, result, config) do
          {:ok, _stored_results} -> finalize_tracked_evaluation(evaluation_run, result)
          error -> error
        end

      {:error, reason} ->
        # Mark evaluation as failed
        EvaluationRun.fail_evaluation(evaluation_run, %{error_message: inspect(reason)})
        {:error, reason}
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
        # Perform evaluation using Universal Provider System via EvaluationAdapter
        user_id = Keyword.get(options, :user_id, "system")
        project_id = Keyword.get(options, :project_id)
        
        evaluation_options = %{
          quality_threshold: Map.get(config, :default_quality_threshold, 0.8),
          max_tokens: Map.get(config, :max_tokens_per_evaluation, 1500),
          constitutional_ai_required: evaluation_type in [:security, :safety_critical],
          criteria: Map.get(config, :evaluation_criteria_weights, %{}),
          streaming: Keyword.get(options, :streaming, false),
          metadata: %{via_verdict_engine: true}
        }
        
        case EvaluationAdapter.evaluate_code(code, evaluation_type, user_id, project_id, evaluation_options) do
          {:ok, universal_result} ->
            # Adapt result for Verdict system format and cache
            verdict_result = adapt_universal_result_for_verdict(universal_result, config)
            IntelligentCache.cache_result(cache_key, verdict_result, config)
            {:ok, Map.put(verdict_result, :cache_hit, false)}

          error ->
            Logger.error("Universal provider evaluation failed, falling back to ProgressiveEvaluator")
            # Fallback to existing system if universal provider fails
            case ProgressiveEvaluator.evaluate(code, evaluation_type, config, options) do
              {:ok, result} ->
                IntelligentCache.cache_result(cache_key, result, config)
                {:ok, Map.put(result, :cache_hit, false)}
              error -> error
            end
        end

      error ->
        error
    end
  end

  defp resolve_verdict_preferences(user_id, project_id) do
    # Use the new three-tier configuration resolution system
    case VerdictConfigurationResolver.resolve_configuration(user_id, project_id) do
      {:ok, resolved_config} ->
        Logger.debug("Resolved Verdict configuration for user #{user_id}, project #{project_id}")
        {:ok, resolved_config}

      {:error, reason} ->
        Logger.warning(
          "Failed to resolve Verdict preferences, using defaults: #{inspect(reason)}"
        )

        # Fallback to system defaults if resolution fails
        case VerdictConfigurationResolver.get_system_configuration() do
          {:ok, system_config} -> {:ok, system_config}
          # Final fallback to hardcoded defaults
          _ -> {:ok, @default_config}
        end
    end
  end

  defp build_evaluation_config(preferences) do
    # Build evaluation configuration from resolved preferences
    Map.merge(@default_config, preferences)
  end

  defp estimate_token_usage(code, evaluation_type) do
    # Rough estimation based on code length and evaluation complexity
    # Rough approximation
    base_tokens = div(String.length(code), 4)

    multiplier =
      case evaluation_type do
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
    confidence =
      cond do
        estimated_tokens < 500 -> 0.9
        estimated_tokens < 2000 -> 0.8
        estimated_tokens < 5000 -> 0.7
        true -> 0.6
      end

    {:ok,
     %{
       estimated_cost: estimated_cost,
       estimated_tokens: estimated_tokens,
       confidence: confidence,
       model: model_config
     }}
  end

  defp determine_initial_strategy(evaluation_type, config) do
    case {evaluation_type, Map.get(config, :progressive_evaluation, true)} do
      {:security, _} -> :detailed
      {:comprehensive, _} -> :comprehensive
      {_, true} -> :progressive
      {_, false} -> :detailed
    end
  end

  defp store_evaluation_results(evaluation_run, result, _config) do
    result_params = build_result_storage_params(evaluation_run, result)

    case EvaluationResult.create(result_params) do
      {:ok, stored_result} -> {:ok, [stored_result]}
      error -> error
    end
  end

  defp build_result_storage_params(evaluation_run, result) do
    %{
      evaluation_run_id: evaluation_run.id,
      judge_unit_type: result.judge_unit || "base_judge",
      model_used: result.model_used,
      score: Decimal.new(result.score),
      confidence: Decimal.new(result.confidence),
      issues_found: result.issues || [],
      recommendations: result.recommendations || [],
      reasoning: result.reasoning,
      evaluation_stage: result.evaluation_stage || :detailed,
      tokens_used: result.tokens_used || 0,
      cost_usd: Decimal.new(result.cost_usd || 0.0),
      latency_ms: result.latency_ms || 0,
      llm_request_metadata: build_llm_metadata(result)
    }
  end

  defp build_llm_metadata(result) do
    %{
      model: result.model_used,
      timestamp: result.timestamp
    }
  end

  defp complete_evaluation_run(evaluation_run, result) do
    completion_params = %{
      total_cost_usd: Decimal.new(result.cost_usd || 0.0),
      total_tokens_used: result.tokens_used || 0,
      total_latency_ms: result.latency_ms || 0
    }

    EvaluationRun.complete_evaluation(evaluation_run, completion_params)
  end

  defp finalize_tracked_evaluation(evaluation_run, result) do
    # Complete the evaluation run
    case complete_evaluation_run(evaluation_run, result) do
      {:ok, completed_run} ->
        enhanced_result =
          Map.merge(result, %{
            evaluation_run_id: completed_run.id,
            tracking_enabled: true
          })

        {:ok, enhanced_result}

      error ->
        error
    end
  end
  
  # Universal Provider System Integration
  
  defp adapt_universal_result_for_verdict(universal_result, config) do
    # Adapt EvaluationAdapter result to Verdict Engine format
    %{
      evaluation_id: Ash.UUID.generate(),
      success: universal_result.success,
      score: universal_result.score,
      confidence: universal_result.confidence,
      model_used: universal_result.model,
      provider_used: to_string(universal_result.provider),
      
      # Evaluation details
      issues: universal_result.issues,
      recommendations: universal_result.recommendations,
      reasoning: universal_result.reasoning,
      
      # Cost and performance
      cost_usd: universal_result.cost_usd,
      tokens_used: universal_result.tokens_used,
      latency_ms: universal_result.response_time_ms,
      
      # Universal provider enhancements
      constitutional_ai_enhanced: Map.get(universal_result, :constitutional_ai_enhanced, false),
      universal_provider_used: true,
      evaluation_type: universal_result.evaluation_type,
      
      # Metadata
      timestamp: DateTime.utc_now(),
      metadata: Map.merge(Map.get(config, :metadata, %{}), %{
        universal_provider_integration: true,
        original_universal_metadata: universal_result.metadata
      })
    }
  end
end
