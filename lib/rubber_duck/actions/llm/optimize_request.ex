defmodule RubberDuck.Actions.LLM.OptimizeRequest do
  @moduledoc """
  Action for optimizing LLM requests before execution.
  
  Applies various optimization strategies to reduce costs,
  improve response quality, and enhance performance.
  """

  use Jido.Action,
    name: "llm_optimize_request",
    description: "Optimize an LLM request for cost and performance",
    schema: [
      request: [type: :map, required: true],
      optimization_goals: [type: {:list, :atom}, default: [:cost, :quality]],
      provider_hints: [type: :map, default: %{}],
      max_context_tokens: [type: :pos_integer, default: 4096],
      enable_caching: [type: :boolean, default: true]
    ]

  require Logger

  @impl true
  def run(params, _context) do
    with :ok <- validate_optimization_params(params) do
      try do
        request = params.request
        goals = params.optimization_goals
        provider_hints = params.provider_hints
        
        optimized_request = 
          request
          |> optimize_for_goals(goals, provider_hints)
          |> trim_context_if_needed(params.max_context_tokens)
          |> add_caching_headers(params.enable_caching)
          |> optimize_parameters()
          |> validate_optimized_request()
        
        case optimized_request do
          {:ok, optimized} ->
            optimizations_applied = detect_optimizations(request, optimized)
            
            {:ok, %{
              optimized_request: optimized,
              original_request: request,
              optimizations_applied: optimizations_applied,
              estimated_savings: estimate_cost_savings(request, optimized),
              quality_impact: estimate_quality_impact(optimizations_applied)
            }}
          
          {:error, reason} ->
            {:error, %{
              reason: reason,
              original_request: request,
              stage: :validation
            }}
        end
      rescue
        exception ->
          Logger.error("Request optimization failed: #{inspect(exception)}\n#{Exception.format_stacktrace()}")
          {:error, %{
            reason: {:exception, exception},
            message: Exception.message(exception),
            original_request: params.request
          }}
      end
    else
      {:error, reason} -> {:error, %{reason: reason, stage: :param_validation}}
    end
  end

  def describe do
    %{
      name: "Optimize LLM Request",
      description: "Optimizes LLM requests for better performance and lower costs",
      category: "llm",
      inputs: %{
        request: "The original LLM request to optimize",
        optimization_goals: "List of optimization goals (e.g., :cost, :quality, :speed)",
        provider_hints: "Provider-specific optimization hints",
        max_context_tokens: "Maximum allowed context size in tokens",
        enable_caching: "Whether to add caching headers"
      },
      outputs: %{
        success: %{
          optimized_request: "The optimized request",
          original_request: "The original request for comparison",
          optimizations_applied: "List of optimizations that were applied",
          estimated_savings: "Estimated cost savings percentage",
          quality_impact: "Estimated impact on response quality"
        },
        error: %{
          reason: "Why optimization failed",
          original_request: "The original request"
        }
      }
    }
  end

  # Private functions

  defp optimize_for_goals(request, goals, provider_hints) do
    Enum.reduce(goals, request, fn goal, acc ->
      apply_goal_optimization(acc, goal, provider_hints)
    end)
  end

  defp apply_goal_optimization(request, :cost, _hints) do
    request
    |> reduce_max_tokens()
    |> use_cheaper_model_if_appropriate()
    |> disable_unnecessary_features()
  end

  defp apply_goal_optimization(request, :quality, _hints) do
    request
    |> increase_temperature_diversity()
    |> enable_best_of_sampling()
    |> use_better_model_if_needed()
  end

  defp apply_goal_optimization(request, :speed, hints) do
    request
    |> reduce_max_tokens()
    |> disable_streaming_if_small()
    |> apply_provider_speed_hints(hints)
  end

  defp apply_goal_optimization(request, _, _), do: request

  defp trim_context_if_needed(request, max_tokens) do
    try do
      messages = request[:messages] || []
      
      estimated_tokens = estimate_message_tokens(messages)
      
      if estimated_tokens > max_tokens do
        Logger.debug("Trimming context from ~#{estimated_tokens} to ~#{max_tokens} tokens")
        trimmed_messages = trim_messages_to_fit(messages, max_tokens)
        Map.put(request, :messages, trimmed_messages)
      else
        request
      end
    rescue
      exception ->
        Logger.warning("Failed to trim context: #{inspect(exception)}. Using original request.")
        request
    end
  end

  defp estimate_message_tokens(messages) do
    messages
    |> Enum.map(fn msg ->
      content = msg["content"] || msg[:content] || ""
      # Rough estimation: 1 token per 4 characters
      div(String.length(content), 4)
    end)
    |> Enum.sum()
  end

  defp trim_messages_to_fit(messages, max_tokens) do
    # Keep system message and most recent messages
    system_messages = Enum.filter(messages, &(&1["role"] == "system" || &1[:role] == "system"))
    other_messages = Enum.reject(messages, &(&1["role"] == "system" || &1[:role] == "system"))
    
    # Take messages from the end until we hit the limit
    {kept_messages, _} = 
      other_messages
      |> Enum.reverse()
      |> Enum.reduce_while({[], max_tokens - estimate_message_tokens(system_messages)}, fn msg, {acc, remaining} ->
        msg_tokens = div(String.length(msg["content"] || msg[:content] || ""), 4)
        
        if msg_tokens <= remaining do
          {:cont, {[msg | acc], remaining - msg_tokens}}
        else
          {:halt, {acc, remaining}}
        end
      end)
    
    system_messages ++ kept_messages
  end

  defp add_caching_headers(request, true) do
    Map.put(request, :cache_control, %{
      max_age: 3600,
      key_prefix: generate_cache_key_prefix(request)
    })
  end
  defp add_caching_headers(request, false), do: request

  defp optimize_parameters(request) do
    request
    |> optimize_temperature()
    |> optimize_max_tokens()
    |> optimize_top_p()
    |> remove_redundant_params()
  end

  defp optimize_temperature(request) do
    case request[:temperature] do
      nil -> request
      temp when temp > 1.5 -> 
        Logger.debug("Reducing excessive temperature from #{temp} to 1.2")
        Map.put(request, :temperature, 1.2)
      _ -> request
    end
  end

  defp optimize_max_tokens(request) do
    case request[:max_tokens] do
      nil -> Map.put(request, :max_tokens, 1000)  # Set reasonable default
      tokens when tokens > 4000 ->
        Logger.debug("Reducing max_tokens from #{tokens} to 2000")
        Map.put(request, :max_tokens, 2000)
      _ -> request
    end
  end

  defp optimize_top_p(request) do
    # If using temperature, we don't need top_p
    if request[:temperature] && request[:temperature] > 0 do
      Map.delete(request, :top_p)
    else
      request
    end
  end

  defp remove_redundant_params(request) do
    request
    |> Map.delete(:presence_penalty) # Often not needed
    |> Map.delete(:frequency_penalty) # Often not needed
    |> Map.delete(:logit_bias) # Rarely used
  end

  defp reduce_max_tokens(request) do
    case request[:max_tokens] do
      nil -> request
      tokens when tokens > 1000 -> Map.put(request, :max_tokens, div(tokens, 2))
      _ -> request
    end
  end

  defp use_cheaper_model_if_appropriate(request) do
    model = request[:model] || ""
    
    cheaper_alternative = case model do
      "gpt-4" <> _ -> "gpt-3.5-turbo"
      "claude-3-opus" <> _ -> "claude-3-sonnet"
      "claude-3-sonnet" <> _ -> "claude-3-haiku"
      _ -> model
    end
    
    if cheaper_alternative != model do
      Logger.debug("Switching from #{model} to cheaper #{cheaper_alternative}")
      Map.put(request, :model, cheaper_alternative)
    else
      request
    end
  end

  defp disable_unnecessary_features(request) do
    request
    |> Map.put(:stream, false)  # Streaming adds overhead
    |> Map.delete(:functions)   # Function calling is expensive
    |> Map.delete(:tools)       # Tools are expensive
  end

  defp increase_temperature_diversity(request) do
    case request[:temperature] do
      nil -> Map.put(request, :temperature, 0.7)
      temp when temp < 0.5 -> Map.put(request, :temperature, 0.7)
      _ -> request
    end
  end

  defp enable_best_of_sampling(request) do
    # Some providers support best_of for quality
    if request[:n] == nil || request[:n] == 1 do
      Map.put(request, :best_of, 2)
    else
      request
    end
  end

  defp use_better_model_if_needed(request) do
    model = request[:model] || ""
    
    quality_upgrade = case model do
      "gpt-3.5-turbo" -> "gpt-4-turbo"
      "claude-3-haiku" -> "claude-3-sonnet"
      "claude-3-sonnet" -> "claude-3-opus"
      _ -> model
    end
    
    if quality_upgrade != model do
      Logger.debug("Upgrading from #{model} to higher quality #{quality_upgrade}")
      Map.put(request, :model, quality_upgrade)
    else
      request
    end
  end

  defp disable_streaming_if_small(request) do
    max_tokens = request[:max_tokens] || 1000
    
    if max_tokens < 500 do
      Map.put(request, :stream, false)
    else
      request
    end
  end

  defp apply_provider_speed_hints(request, hints) do
    Enum.reduce(hints, request, fn {key, value}, acc ->
      Map.put(acc, key, value)
    end)
  end

  defp validate_optimized_request({:error, _} = error), do: error
  defp validate_optimized_request(request) do
    cond do
      # Must have messages or prompt
      !Map.has_key?(request, :messages) && !Map.has_key?(request, :prompt) ->
        {:error, :missing_content}
      
      # Messages must not be empty
      Map.get(request, :messages, []) == [] && !Map.has_key?(request, :prompt) ->
        {:error, :empty_messages}
      
      true ->
        {:ok, request}
    end
  end

  defp detect_optimizations(original, optimized) do
    optimizations = []
    
    # Model change
    optimizations = if original[:model] != optimized[:model] do
      [:model_changed | optimizations]
    else
      optimizations
    end
    
    # Context trimmed
    original_msgs = length(original[:messages] || [])
    optimized_msgs = length(optimized[:messages] || [])
    optimizations = if original_msgs > optimized_msgs do
      [:context_trimmed | optimizations]
    else
      optimizations
    end
    
    # Parameters optimized
    optimizations = if original[:max_tokens] != optimized[:max_tokens] do
      [:max_tokens_adjusted | optimizations]
    else
      optimizations
    end
    
    # Features disabled
    optimizations = if Map.has_key?(original, :functions) && !Map.has_key?(optimized, :functions) do
      [:functions_disabled | optimizations]
    else
      optimizations
    end
    
    # Caching enabled
    optimizations = if Map.has_key?(optimized, :cache_control) do
      [:caching_enabled | optimizations]
    else
      optimizations
    end
    
    Enum.reverse(optimizations)
  end

  defp estimate_cost_savings(original, optimized) do
    # Simplified cost estimation
    original_cost = estimate_request_cost(original)
    optimized_cost = estimate_request_cost(optimized)
    
    if original_cost > 0 do
      savings_percent = ((original_cost - optimized_cost) / original_cost) * 100
      Float.round(savings_percent, 1)
    else
      0.0
    end
  end

  defp estimate_request_cost(request) do
    model_cost = case request[:model] do
      "gpt-4" <> _ -> 10.0
      "gpt-3.5-turbo" -> 1.0
      "claude-3-opus" <> _ -> 15.0
      "claude-3-sonnet" <> _ -> 3.0
      "claude-3-haiku" <> _ -> 0.25
      _ -> 1.0
    end
    
    tokens = (request[:max_tokens] || 1000) / 1000
    model_cost * tokens
  end

  defp estimate_quality_impact(optimizations) do
    # Estimate impact on quality based on optimizations
    negative_impact = Enum.count(optimizations, fn opt ->
      opt in [:model_changed, :context_trimmed, :functions_disabled]
    end)
    
    case negative_impact do
      0 -> :none
      1 -> :minimal
      2 -> :moderate
      _ -> :significant
    end
  end

  defp generate_cache_key_prefix(request) do
    # Generate a stable cache key prefix based on request structure
    model = request[:model] || "default"
    system_msg = get_system_message(request)
    
    content = "#{model}:#{system_msg}"
    :crypto.hash(:md5, content) |> Base.encode16() |> String.slice(0..7)
  end

  defp get_system_message(request) do
    try do
      messages = request[:messages] || []
      
      messages
      |> Enum.find(fn msg -> 
        is_map(msg) && (msg["role"] == "system" || msg[:role] == "system")
      end)
      |> case do
        nil -> ""
        msg -> msg["content"] || msg[:content] || ""
      end
      |> String.slice(0..100)
    rescue
      _ -> ""
    end
  end
  
  defp validate_optimization_params(params) do
    cond do
      not is_map(params) ->
        {:error, :invalid_params}
        
      not is_map(params[:request]) ->
        {:error, :invalid_request}
        
      not is_list(params[:optimization_goals]) ->
        {:error, :invalid_optimization_goals}
        
      not is_integer(params[:max_context_tokens]) || params[:max_context_tokens] <= 0 ->
        {:error, :invalid_max_context_tokens}
        
      true ->
        :ok
    end
  end
end