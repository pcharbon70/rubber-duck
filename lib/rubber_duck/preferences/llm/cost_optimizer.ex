defmodule RubberDuck.Preferences.Llm.CostOptimizer do
  @moduledoc """
  Cost optimization engine for LLM provider selection.

  Implements intelligent cost-quality trade-offs based on user preferences,
  budget constraints, and request characteristics. Optimizes provider
  and model selection to minimize costs while maintaining quality thresholds.
  """

  require Logger

  alias RubberDuck.Preferences.Llm.{ModelSelector, ProviderConfig}
  alias RubberDuck.Preferences.PreferenceResolver

  @doc """
  Select the most cost-effective provider/model for a request.
  """
  @spec optimize_selection(
          user_id :: binary(),
          request_opts :: keyword(),
          project_id :: binary() | nil
        ) ::
          {:ok, %{provider: atom(), model: String.t(), estimated_cost: float(), config: map()}}
          | {:error, String.t()}
  def optimize_selection(user_id, request_opts \\ [], project_id \\ nil) do
    config = ProviderConfig.get_complete_config(user_id, project_id)
    cost_config = config.cost_optimization

    if cost_config.optimization_enabled do
      perform_cost_optimization(user_id, request_opts, config, project_id)
    else
      # Use standard model selection without cost optimization
      case ModelSelector.select_model(user_id, request_opts, project_id) do
        {:ok, selection} ->
          estimated_cost = estimate_request_cost(selection, request_opts)
          {:ok, Map.put(selection, :estimated_cost, estimated_cost)}

        error ->
          error
      end
    end
  end

  @doc """
  Check if a request fits within budget constraints.
  """
  @spec within_budget?(
          user_id :: binary(),
          estimated_cost :: float(),
          project_id :: binary() | nil
        ) :: boolean()
  def within_budget?(user_id, estimated_cost, project_id \\ nil) do
    {:ok, budget_status} = get_current_budget_status(user_id, project_id)
    remaining_budget = budget_status.remaining_budget
    cost_per_token_threshold = get_cost_threshold(user_id, project_id)

    estimated_cost <= remaining_budget and
      estimated_cost <= cost_per_token_threshold
  end

  @doc """
  Get cost optimization recommendations for a user/project.
  """
  @spec get_optimization_recommendations(user_id :: binary(), project_id :: binary() | nil) :: [
          map()
        ]
  def get_optimization_recommendations(user_id, project_id \\ nil) do
    config = ProviderConfig.get_complete_config(user_id, project_id)
    usage_stats = get_usage_statistics(user_id, project_id)

    recommendations = []

    # Check for expensive provider usage
    recommendations = recommendations ++ check_expensive_provider_usage(config, usage_stats)

    # Check for model optimization opportunities
    recommendations = recommendations ++ check_model_optimization(config, usage_stats)

    # Check for budget threshold adjustments
    recommendations = recommendations ++ check_budget_thresholds(config, usage_stats)

    # Check for fallback configuration optimization
    recommendations = recommendations ++ check_fallback_optimization(config, usage_stats)

    recommendations
  end

  @doc """
  Calculate potential savings from optimization recommendations.
  """
  @spec calculate_potential_savings(
          user_id :: binary(),
          recommendations :: [map()],
          project_id :: binary() | nil
        ) :: %{
          total_potential_savings: float(),
          monthly_savings_estimate: float(),
          optimization_opportunities: [map()]
        }
  def calculate_potential_savings(user_id, recommendations, project_id \\ nil) do
    usage_stats = get_usage_statistics(user_id, project_id)
    current_monthly_cost = Map.get(usage_stats, :monthly_cost, 0.0)

    total_savings =
      recommendations
      |> Enum.map(&Map.get(&1, :potential_savings, 0.0))
      |> Enum.sum()

    %{
      total_potential_savings: total_savings,
      monthly_savings_estimate: min(total_savings, current_monthly_cost * 0.5),
      optimization_opportunities: recommendations,
      current_monthly_cost: current_monthly_cost,
      generated_at: DateTime.utc_now()
    }
  end

  # Private functions

  defp perform_cost_optimization(_user_id, request_opts, config, _project_id) do
    enabled_providers = config.enabled_providers
    quality_threshold = config.cost_optimization.quality_threshold

    # Get all viable provider/model combinations
    viable_options = get_viable_options(enabled_providers, request_opts, quality_threshold)

    # Sort by cost efficiency (cost per quality unit)
    sorted_options =
      viable_options
      |> Enum.map(&calculate_cost_efficiency(&1, request_opts))
      |> Enum.sort_by(& &1.cost_efficiency)

    case sorted_options do
      [best_option | _] ->
        provider_config = Map.get(config.provider_configs, best_option.provider, %{})

        {:ok,
         %{
           provider: best_option.provider,
           model: best_option.model,
           estimated_cost: best_option.estimated_cost,
           cost_efficiency: best_option.cost_efficiency,
           quality_score: best_option.quality_score,
           config: provider_config
         }}

      [] ->
        {:error, "No cost-effective options available"}
    end
  end

  defp get_viable_options(providers, request_opts, quality_threshold) do
    providers
    |> Enum.flat_map(fn provider ->
      models = ModelSelector.get_alternative_models(provider)

      Enum.map(models, fn model ->
        %{
          provider: provider,
          model: model,
          capabilities: ModelSelector.get_model_capabilities(provider, model)
        }
      end)
    end)
    |> Enum.filter(fn option ->
      ModelSelector.meets_requirements?(
        option.provider,
        option.model,
        extract_requirements(request_opts)
      ) and
        estimate_quality_score(option.provider, option.model) >= quality_threshold
    end)
  end

  defp calculate_cost_efficiency(option, request_opts) do
    input_tokens = Keyword.get(request_opts, :estimated_input_tokens, 1000)
    output_tokens = Keyword.get(request_opts, :estimated_output_tokens, 500)

    estimated_cost =
      ModelSelector.estimate_cost(option.provider, option.model, input_tokens, output_tokens)

    quality_score = estimate_quality_score(option.provider, option.model)

    cost_efficiency = if quality_score > 0, do: estimated_cost / quality_score, else: 999_999.0

    option
    |> Map.put(:estimated_cost, estimated_cost)
    |> Map.put(:quality_score, quality_score)
    |> Map.put(:cost_efficiency, cost_efficiency)
  end

  defp estimate_quality_score(provider, model) do
    # Simplified quality scoring - in production this would use ML models
    # or historical performance data
    get_provider_quality_score(provider, model)
  end

  defp get_provider_quality_score(provider, model) do
    case provider do
      :anthropic -> get_anthropic_score(model)
      :openai -> get_openai_score(model)
      :google -> get_google_score(model)
      _ -> 0.70
    end
  end

  defp get_anthropic_score("claude-3-5-sonnet-20241022"), do: 0.95
  defp get_anthropic_score("claude-3-opus-20240229"), do: 0.94
  defp get_anthropic_score("claude-3-5-haiku-20241022"), do: 0.85
  defp get_anthropic_score(_), do: 0.80

  defp get_openai_score("gpt-4"), do: 0.92
  defp get_openai_score("gpt-4-turbo"), do: 0.90
  defp get_openai_score("gpt-4o"), do: 0.93
  defp get_openai_score("gpt-3.5-turbo"), do: 0.80
  defp get_openai_score(_), do: 0.75

  defp get_google_score("gemini-1.5-pro"), do: 0.88
  defp get_google_score("gemini-1.5-flash"), do: 0.82
  defp get_google_score(_), do: 0.75

  defp extract_requirements(request_opts) do
    %{
      min_context_window: Keyword.get(request_opts, :min_context_window, 4096),
      max_cost_per_token: Keyword.get(request_opts, :max_cost_per_token, 0.0001),
      requires_functions: Keyword.get(request_opts, :requires_functions, false),
      requires_vision: Keyword.get(request_opts, :requires_vision, false),
      min_output_tokens: Keyword.get(request_opts, :min_output_tokens, 1024)
    }
  end

  defp get_cost_threshold(user_id, project_id) do
    case PreferenceResolver.resolve(user_id, "llm.cost.cost_per_token_threshold", project_id) do
      {:ok, threshold} -> threshold
      # Default threshold
      {:error, _} -> 0.00001
    end
  end

  defp get_current_budget_status(_user_id, _project_id) do
    # Placeholder for budget system integration
    # This would integrate with Phase 11 cost management
    {:ok,
     %{
       remaining_budget: 100.0,
       monthly_limit: 500.0,
       current_usage: 400.0,
       days_remaining: 15
     }}
  end

  defp get_usage_statistics(user_id, project_id) do
    # Placeholder for usage analytics
    # This would integrate with telemetry and usage tracking
    %{
      monthly_cost: 45.50,
      monthly_requests: 1250,
      average_cost_per_request: 0.036,
      most_used_provider: :anthropic,
      cost_trend: :increasing,
      user_id: user_id,
      project_id: project_id
    }
  end

  defp check_expensive_provider_usage(_config, usage_stats) do
    most_used = Map.get(usage_stats, :most_used_provider)
    avg_cost = Map.get(usage_stats, :average_cost_per_request, 0.0)

    if most_used && avg_cost > 0.05 do
      [
        %{
          type: :expensive_provider,
          message: "Consider switching to a more cost-effective provider",
          current_provider: most_used,
          current_avg_cost: avg_cost,
          potential_savings: avg_cost * 0.3,
          priority: :medium
        }
      ]
    else
      []
    end
  end

  defp check_model_optimization(_config, _usage_stats) do
    # Check if user is using expensive models for simple tasks
    # This would analyze request patterns in a real implementation
    []
  end

  defp check_budget_thresholds(config, usage_stats) do
    monthly_cost = Map.get(usage_stats, :monthly_cost, 0.0)
    threshold = config.cost_optimization.cost_per_token_threshold

    if monthly_cost > 100.0 and threshold > 0.00005 do
      [
        %{
          type: :budget_threshold,
          message: "Consider lowering cost per token threshold",
          current_threshold: threshold,
          suggested_threshold: threshold * 0.8,
          potential_savings: monthly_cost * 0.2,
          priority: :low
        }
      ]
    else
      []
    end
  end

  defp check_fallback_optimization(config, _usage_stats) do
    # Check if fallback configuration could be optimized
    fallback_chain = config.fallback_config.chain

    if length(fallback_chain) > 3 do
      [
        %{
          type: :fallback_optimization,
          message: "Consider simplifying fallback chain for better performance",
          current_chain_length: length(fallback_chain),
          suggested_length: 3,
          potential_savings: 5.0,
          priority: :low
        }
      ]
    else
      []
    end
  end

  defp estimate_request_cost(selection, request_opts) do
    input_tokens = Keyword.get(request_opts, :estimated_input_tokens, 1000)
    output_tokens = Keyword.get(request_opts, :estimated_output_tokens, 500)

    ModelSelector.estimate_cost(
      selection.provider,
      selection.config.model,
      input_tokens,
      output_tokens
    )
  end
end
