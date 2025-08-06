defmodule RubberDuck.Actions.LLM.SelectProvider do
  @moduledoc """
  Action for intelligently selecting the best LLM provider for a request.

  Uses various criteria including availability, performance history,
  cost, and request requirements to select the optimal provider.
  """

  use Jido.Action,
    name: "llm_select_provider",
    description: "Select the optimal LLM provider for a request",
    schema: [
      request: [type: :map, required: true],
      performance_history: [type: :map, default: %{}],
      optimization_preference: [
        type: :atom,
        values: [:cost, :quality, :balanced],
        default: :balanced
      ],
      exclude_providers: [type: {:list, :atom}, default: []],
      required_capabilities: [type: {:list, :atom}, default: []]
    ]

  alias RubberDuck.LLM.{HealthMonitor, ProviderRegistry}

  @impl true
  def run(params, _context) do
    available_providers = ProviderRegistry.list_available()

    if Enum.empty?(available_providers) do
      {:error, :no_providers_available}
    else
      # Filter providers
      suitable_providers =
        available_providers
        |> exclude_providers(params.exclude_providers)
        |> filter_by_capabilities(params.required_capabilities)
        |> filter_by_request_requirements(params.request)

      if Enum.empty?(suitable_providers) do
        {:error, :no_suitable_providers}
      else
        # Score and rank providers
        best_provider =
          suitable_providers
          |> score_providers(params)
          |> select_best_provider()

        {:ok,
         %{
           provider: best_provider,
           selection_reason: determine_selection_reason(best_provider, params),
           alternatives: Enum.take(suitable_providers -- [best_provider], 2)
         }}
      end
    end
  end

  def describe do
    %{
      name: "Select LLM Provider",
      description: "Intelligently selects the best LLM provider based on multiple criteria",
      category: "llm",
      inputs: %{
        request: "The LLM request to find a provider for",
        performance_history: "Historical performance data for providers",
        optimization_preference: "What to optimize for: cost, quality, or balanced",
        exclude_providers: "List of provider names to exclude",
        required_capabilities: "List of required capabilities (e.g., :streaming, :embeddings)"
      },
      outputs: %{
        success: %{
          provider: "The selected provider configuration",
          selection_reason: "Human-readable reason for the selection",
          alternatives: "List of alternative providers that could be used"
        }
      }
    }
  end

  # Private functions

  defp exclude_providers(providers, exclude_list) do
    Enum.reject(providers, fn provider ->
      provider.name in exclude_list
    end)
  end

  defp filter_by_capabilities(providers, []), do: providers

  defp filter_by_capabilities(providers, required_capabilities) do
    Enum.filter(providers, fn provider ->
      provider_capabilities = get_provider_capabilities(provider)
      Enum.all?(required_capabilities, &(&1 in provider_capabilities))
    end)
  end

  defp filter_by_request_requirements(providers, request) do
    Enum.filter(providers, fn provider ->
      meets_request_requirements?(provider, request)
    end)
  end

  defp meets_request_requirements?(provider, request) do
    # Check if provider supports the requested model
    model = request[:model]

    if model do
      capabilities = provider.module.capabilities()
      model in capabilities.models || String.contains?(model, "compatible")
    else
      true
    end
  end

  defp get_provider_capabilities(provider) do
    capabilities = provider.module.capabilities()
    capability_list = []

    capability_list =
      if capabilities.completion, do: [:completion | capability_list], else: capability_list

    capability_list =
      if capabilities.streaming, do: [:streaming | capability_list], else: capability_list

    capability_list =
      if capabilities.embeddings, do: [:embeddings | capability_list], else: capability_list

    capability_list =
      if capabilities.function_calling,
        do: [:function_calling | capability_list],
        else: capability_list

    capability_list =
      if capabilities.vision, do: [:vision | capability_list], else: capability_list

    capability_list
  rescue
    # Assume basic completion capability
    _ -> [:completion]
  end

  defp score_providers(providers, params) do
    Enum.map(providers, fn provider ->
      score = calculate_provider_score(provider, params)
      Map.put(provider, :score, score)
    end)
  end

  defp calculate_provider_score(provider, params) do
    score_components = gather_score_components(provider, params)
    apply_optimization_weighting(score_components, params.optimization_preference)
  end

  defp gather_score_components(provider, params) do
    metrics = HealthMonitor.get_metrics(provider.name)
    history = Map.get(params.performance_history, provider.name, %{})

    %{
      base: 100.0,
      availability: calculate_availability_score(provider),
      performance: calculate_performance_score(metrics),
      response_time: calculate_response_time_score(metrics.avg_response_time || 1000),
      cost: calculate_cost_score(provider, params.request),
      historical: calculate_historical_score(history)
    }
  end

  defp calculate_availability_score(provider) do
    if provider.available, do: 30.0, else: 0.0
  end

  defp calculate_performance_score(metrics) do
    error_rate = metrics.error_rate || 0.0
    (1.0 - error_rate) * 30.0
  end

  defp apply_optimization_weighting(components, optimization_preference) do
    case optimization_preference do
      :cost -> calculate_cost_optimized_score(components)
      :quality -> calculate_quality_optimized_score(components)
      :balanced -> calculate_balanced_score(components)
    end
  end

  defp calculate_cost_optimized_score(components) do
    components.base + components.availability +
      components.performance * 0.5 + components.response_time * 0.3 +
      components.cost * 2.0 + components.historical
  end

  defp calculate_quality_optimized_score(components) do
    components.base + components.availability +
      components.performance * 1.5 + components.response_time * 1.2 +
      components.cost * 0.3 + components.historical
  end

  defp calculate_balanced_score(components) do
    components.base + components.availability + components.performance +
      components.response_time + components.cost + components.historical
  end

  defp calculate_response_time_score(avg_response_time) do
    cond do
      avg_response_time < 500 -> 20.0
      avg_response_time < 1000 -> 15.0
      avg_response_time < 2000 -> 10.0
      avg_response_time < 5000 -> 5.0
      true -> 0.0
    end
  end

  defp calculate_cost_score(provider, _request) do
    # Simplified cost scoring - in production, calculate based on token usage
    case provider.name do
      # Medium cost
      :openai -> 10.0
      # Higher cost
      :anthropic -> 8.0
      # Free
      :local -> 20.0
      # Default medium cost
      _ -> 12.0
    end
  end

  defp calculate_historical_score(history) do
    success_count = Map.get(history, :success_count, 0)
    quality_avg = Map.get(history, :quality_avg, 0.5)

    # More usage = more confidence
    usage_score = min(success_count / 10, 1.0) * 10.0

    # Higher quality = better score
    quality_score = quality_avg * 10.0

    (usage_score + quality_score) / 2
  end

  defp select_best_provider(scored_providers) do
    scored_providers
    |> Enum.sort_by(& &1.score, :desc)
    |> hd()
    |> Map.delete(:score)
  end

  defp determine_selection_reason(provider, params) do
    metrics = HealthMonitor.get_metrics(provider.name)

    reasons = []

    reasons = if provider.available, do: ["available" | reasons], else: reasons

    reasons =
      if metrics.error_rate < 0.1,
        do: ["reliable (#{Float.round((1 - metrics.error_rate) * 100, 1)}% success)" | reasons],
        else: reasons

    reasons = if metrics.avg_response_time < 1000, do: ["fast response" | reasons], else: reasons

    optimization_reason =
      case params.optimization_preference do
        :cost -> "optimized for cost"
        :quality -> "optimized for quality"
        :balanced -> "balanced selection"
      end

    reasons = [optimization_reason | reasons]

    "Selected #{provider.name}: " <> Enum.join(reasons, ", ")
  end
end
