defmodule RubberDuck.LlmProviders.Orchestration.LearningEngine do
  @moduledoc """
  Learning engine for provider performance optimization and autonomous improvement.
  
  This engine provides:
  - ML-based provider performance analysis and prediction
  - Continuous learning from request-response patterns and outcomes
  - Cost-quality optimization with adaptive algorithms
  - Performance trend analysis and capacity forecasting
  - Integration with orchestration agents for intelligent decision making
  """
  
  use GenServer
  require Logger
  
  @learning_engine_name __MODULE__
  @learning_update_interval 300_000  # 5 minutes
  @data_retention_days 30
  
  # Public API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @learning_engine_name)
  end
  
  @doc """
  Record provider performance outcome for learning.
  """
  def record_outcome(provider, request_data, outcome_data) do
    GenServer.cast(@learning_engine_name, {:record_outcome, provider, request_data, outcome_data})
  end
  
  @doc """
  Get provider performance predictions.
  """
  def get_performance_predictions(provider, request_characteristics) do
    GenServer.call(@learning_engine_name, {:get_predictions, provider, request_characteristics})
  end
  
  @doc """
  Get learning insights and recommendations.
  """
  def get_learning_insights do
    GenServer.call(@learning_engine_name, :get_insights)
  end
  
  @doc """
  Update learning algorithms and parameters.
  """
  def update_learning_configuration(new_config) do
    GenServer.call(@learning_engine_name, {:update_config, new_config})
  end
  
  # GenServer implementation
  
  @impl true
  def init(opts) do
    state = %{
      provider_outcomes: %{},
      learning_models: %{},
      performance_predictions: %{},
      learning_configuration: %{
        learning_rate: Keyword.get(opts, :learning_rate, 0.1),
        adaptation_threshold: Keyword.get(opts, :adaptation_threshold, 0.05),
        prediction_confidence_threshold: Keyword.get(opts, :confidence_threshold, 0.7)
      },
      stats: %{
        total_outcomes_recorded: 0,
        learning_updates: 0,
        prediction_requests: 0
      }
    }
    
    # Schedule learning updates
    schedule_learning_update()
    
    Logger.info("Learning Engine started successfully")
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:record_outcome, provider, request_data, outcome_data}, state) do
    Logger.debug("Recording learning outcome for provider: #{provider}")
    
    # Create outcome record
    outcome_record = %{
      provider: provider,
      request_characteristics: request_data,
      outcome: outcome_data,
      timestamp: DateTime.utc_now()
    }
    
    # Update provider outcomes
    updated_outcomes = state.provider_outcomes
    |> Map.update(provider, [outcome_record], fn existing_outcomes ->
      [outcome_record | existing_outcomes] |> Enum.take(1000)  # Keep last 1000
    end)
    
    # Update stats
    updated_stats = Map.update!(state.stats, :total_outcomes_recorded, &(&1 + 1))
    
    new_state = %{state | 
      provider_outcomes: updated_outcomes,
      stats: updated_stats
    }
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_call({:get_predictions, provider, request_characteristics}, _from, state) do
    Logger.debug("Getting performance predictions for provider: #{provider}")
    
    # Get predictions from learning models
    predictions = case Map.get(state.learning_models, provider) do
      nil ->
        # No learning data, return baseline predictions
        generate_baseline_predictions(provider, request_characteristics)
      
      learning_model ->
        # Use learning model for predictions
        generate_learned_predictions(learning_model, request_characteristics)
    end
    
    # Update stats
    updated_stats = Map.update!(state.stats, :prediction_requests, &(&1 + 1))
    new_state = %{state | stats: updated_stats}
    
    {:reply, {:ok, predictions}, new_state}
  end
  
  @impl true
  def handle_call(:get_insights, _from, state) do
    # Generate comprehensive learning insights
    insights = %{
      provider_performance_summary: generate_provider_performance_summary(state.provider_outcomes),
      learning_model_accuracy: assess_learning_model_accuracy(state.learning_models),
      optimization_opportunities: identify_optimization_opportunities(state.provider_outcomes),
      prediction_confidence: calculate_overall_prediction_confidence(state.learning_models),
      learning_recommendations: generate_learning_recommendations(state)
    }
    
    {:reply, {:ok, insights}, state}
  end
  
  @impl true
  def handle_call({:update_config, new_config}, _from, state) do
    Logger.info("Updating learning configuration")
    
    updated_config = Map.merge(state.learning_configuration, new_config)
    new_state = %{state | learning_configuration: updated_config}
    
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_info(:learning_update, state) do
    Logger.debug("Performing learning model updates")
    
    # Update learning models based on recent outcomes
    updated_models = update_learning_models(state.provider_outcomes, state.learning_configuration)
    
    # Update performance predictions
    updated_predictions = update_performance_predictions(updated_models, state.provider_outcomes)
    
    # Update stats
    updated_stats = Map.update!(state.stats, :learning_updates, &(&1 + 1))
    
    new_state = %{state |
      learning_models: updated_models,
      performance_predictions: updated_predictions,
      stats: updated_stats
    }
    
    # Schedule next learning update
    schedule_learning_update()
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(_msg, state), do: {:noreply, state}
  
  # Private implementation
  
  defp generate_baseline_predictions(provider, request_characteristics) do
    # Generate baseline predictions without learning data
    %{
      cost_prediction: estimate_baseline_cost(provider, request_characteristics),
      quality_prediction: estimate_baseline_quality(provider, request_characteristics),
      performance_prediction: estimate_baseline_performance(provider, request_characteristics),
      confidence: 0.6,  # Lower confidence for baseline
      prediction_source: :baseline
    }
  end
  
  defp generate_learned_predictions(learning_model, request_characteristics) do
    # Generate predictions using learning model
    %{
      cost_prediction: predict_cost_with_learning(learning_model, request_characteristics),
      quality_prediction: predict_quality_with_learning(learning_model, request_characteristics),
      performance_prediction: predict_performance_with_learning(learning_model, request_characteristics),
      confidence: Map.get(learning_model, :confidence, 0.7),
      prediction_source: :learned
    }
  end
  
  defp estimate_baseline_cost(provider, request_characteristics) do
    estimated_tokens = Map.get(request_characteristics, :estimated_tokens, 1000)
    
    cost_per_1k_tokens = case provider do
      :anthropic -> 0.015
      :openai -> 0.02
      :ollama -> 0.0
      _ -> 0.015
    end
    
    (estimated_tokens / 1000) * cost_per_1k_tokens
  end
  
  defp estimate_baseline_quality(provider, request_characteristics) do
    base_quality = case provider do
      :anthropic -> 0.9
      :openai -> 0.85
      :ollama -> 0.75
      _ -> 0.8
    end
    
    # Adjust for complexity
    complexity = Map.get(request_characteristics, :content_complexity, :medium)
    
    case complexity do
      :high -> base_quality
      :medium -> base_quality * 0.95
      :low -> base_quality * 0.9
    end
  end
  
  defp estimate_baseline_performance(provider, request_characteristics) do
    base_time = case provider do
      :ollama -> 1500
      :openai -> 2500
      :anthropic -> 3500
      _ -> 3000
    end
    
    # Adjust for complexity
    complexity = Map.get(request_characteristics, :content_complexity, :medium)
    
    multiplier = case complexity do
      :high -> 1.5
      :medium -> 1.2
      :low -> 1.0
    end
    
    trunc(base_time * multiplier)
  end
  
  defp predict_cost_with_learning(learning_model, request_characteristics) do
    # Use learning model for cost prediction
    baseline_cost = estimate_baseline_cost(learning_model.provider, request_characteristics)
    
    # Apply learning adjustments
    learning_factor = Map.get(learning_model, :cost_learning_factor, 1.0)
    
    baseline_cost * learning_factor
  end
  
  defp predict_quality_with_learning(learning_model, request_characteristics) do
    # Use learning model for quality prediction
    baseline_quality = estimate_baseline_quality(learning_model.provider, request_characteristics)
    
    # Apply learning adjustments
    quality_improvement = Map.get(learning_model, :quality_improvement_factor, 0.0)
    
    min(1.0, baseline_quality + quality_improvement)
  end
  
  defp predict_performance_with_learning(learning_model, request_characteristics) do
    # Use learning model for performance prediction
    baseline_performance = estimate_baseline_performance(learning_model.provider, request_characteristics)
    
    # Apply learning adjustments
    performance_factor = Map.get(learning_model, :performance_learning_factor, 1.0)
    
    trunc(baseline_performance * performance_factor)
  end
  
  defp update_learning_models(provider_outcomes, learning_config) do
    # Update learning models based on recent outcomes
    provider_outcomes
    |> Enum.map(fn {provider, outcomes} ->
      learning_model = build_learning_model_for_provider(provider, outcomes, learning_config)
      {provider, learning_model}
    end)
    |> Enum.into(%{})
  end
  
  defp build_learning_model_for_provider(provider, outcomes, learning_config) do
    # Build learning model for specific provider
    if length(outcomes) >= 5 do
      %{
        provider: provider,
        total_data_points: length(outcomes),
        cost_learning_factor: calculate_cost_learning_factor(outcomes),
        quality_improvement_factor: calculate_quality_improvement_factor(outcomes),
        performance_learning_factor: calculate_performance_learning_factor(outcomes),
        confidence: calculate_model_confidence(outcomes),
        last_updated: DateTime.utc_now()
      }
    else
      %{
        provider: provider,
        total_data_points: length(outcomes),
        confidence: 0.3,  # Low confidence with insufficient data
        last_updated: DateTime.utc_now()
      }
    end
  end
  
  defp calculate_cost_learning_factor(outcomes) do
    # Calculate cost learning factor based on outcomes
    cost_accuracies = outcomes
    |> Enum.map(fn outcome ->
      predicted = get_in(outcome, [:request_characteristics, :cost_estimate]) || 0.1
      actual = get_in(outcome, [:outcome, :cost_usd]) || 0.1
      
      if predicted > 0 and actual > 0 do
        1.0 - abs(predicted - actual) / max(predicted, actual)
      else
        0.5
      end
    end)
    
    avg_accuracy = Enum.sum(cost_accuracies) / length(cost_accuracies)
    
    # Convert accuracy to learning factor
    if avg_accuracy > 0.8 do
      1.0  # Good accuracy, no adjustment needed
    else
      1.0 + (0.8 - avg_accuracy) * 0.2  # Adjust based on accuracy gap
    end
  end
  
  defp calculate_quality_improvement_factor(outcomes) do
    # Calculate quality improvement factor
    quality_trends = outcomes
    |> Enum.map(fn outcome ->
      outcome_quality = estimate_outcome_quality_from_data(outcome)
      baseline_quality = 0.8  # Assume baseline
      
      outcome_quality - baseline_quality
    end)
    
    avg_improvement = Enum.sum(quality_trends) / length(quality_trends)
    
    max(0.0, min(0.2, avg_improvement))  # Cap improvement factor
  end
  
  defp calculate_performance_learning_factor(outcomes) do
    # Calculate performance learning factor
    performance_variations = outcomes
    |> Enum.map(fn outcome ->
      actual_time = get_in(outcome, [:outcome, :response_time_ms]) || 3000
      baseline_time = 3000
      
      baseline_time / max(actual_time, 100)  # Better performance = higher factor
    end)
    
    avg_performance_factor = Enum.sum(performance_variations) / length(performance_variations)
    
    max(0.5, min(2.0, avg_performance_factor))  # Reasonable bounds
  end
  
  defp calculate_model_confidence(outcomes) do
    # Calculate confidence in learning model based on data consistency
    data_points = length(outcomes)
    
    confidence = case data_points do
      points when points > 50 -> 0.9
      points when points > 20 -> 0.8
      points when points > 10 -> 0.7
      _ -> 0.5
    end
    
    # Adjust for data consistency (simplified)
    success_rate = Enum.count(outcomes, fn outcome ->
      get_in(outcome, [:outcome, :success]) || false
    end) / length(outcomes)
    
    confidence * success_rate
  end
  
  defp estimate_outcome_quality_from_data(outcome) do
    # Estimate quality from outcome data
    success = get_in(outcome, [:outcome, :success]) || false
    response_length = get_in(outcome, [:outcome, :content]) |> then(fn content ->
      if is_binary(content), do: String.length(content), else: 0
    end)
    
    base_quality = if success, do: 0.8, else: 0.3
    length_bonus = min(0.1, response_length / 1000)
    
    base_quality + length_bonus
  end
  
  defp update_performance_predictions(learning_models, provider_outcomes) do
    # Update performance predictions based on learning models
    learning_models
    |> Enum.map(fn {provider, model} ->
      predictions = generate_provider_performance_predictions(model, provider_outcomes)
      {provider, predictions}
    end)
    |> Enum.into(%{})
  end
  
  defp generate_provider_performance_predictions(learning_model, provider_outcomes) do
    # Generate performance predictions using learning model
    %{
      expected_cost_range: calculate_expected_cost_range(learning_model),
      expected_quality_range: calculate_expected_quality_range(learning_model),
      expected_performance_range: calculate_expected_performance_range(learning_model),
      confidence_level: Map.get(learning_model, :confidence, 0.7),
      prediction_timestamp: DateTime.utc_now()
    }
  end
  
  defp calculate_expected_cost_range(learning_model) do
    base_cost = 0.05  # Default cost estimate
    
    factor = Map.get(learning_model, :cost_learning_factor, 1.0)
    adjusted_cost = base_cost * factor
    
    %{
      min_cost: adjusted_cost * 0.8,
      avg_cost: adjusted_cost,
      max_cost: adjusted_cost * 1.2
    }
  end
  
  defp calculate_expected_quality_range(learning_model) do
    base_quality = 0.8
    
    improvement = Map.get(learning_model, :quality_improvement_factor, 0.0)
    adjusted_quality = base_quality + improvement
    
    %{
      min_quality: max(0.0, adjusted_quality - 0.1),
      avg_quality: adjusted_quality,
      max_quality: min(1.0, adjusted_quality + 0.1)
    }
  end
  
  defp calculate_expected_performance_range(learning_model) do
    base_performance = 3000  # 3 seconds baseline
    
    factor = Map.get(learning_model, :performance_learning_factor, 1.0)
    adjusted_performance = trunc(base_performance * factor)
    
    %{
      min_response_time: trunc(adjusted_performance * 0.7),
      avg_response_time: adjusted_performance,
      max_response_time: trunc(adjusted_performance * 1.3)
    }
  end
  
  defp generate_provider_performance_summary(provider_outcomes) do
    provider_outcomes
    |> Enum.map(fn {provider, outcomes} ->
      summary = %{
        total_requests: length(outcomes),
        success_rate: calculate_provider_success_rate(outcomes),
        avg_cost: calculate_provider_avg_cost(outcomes),
        avg_quality: calculate_provider_avg_quality(outcomes),
        avg_response_time: calculate_provider_avg_response_time(outcomes)
      }
      
      {provider, summary}
    end)
    |> Enum.into(%{})
  end
  
  defp calculate_provider_success_rate(outcomes) do
    if Enum.empty?(outcomes) do
      0.0
    else
      successful = Enum.count(outcomes, fn outcome ->
        get_in(outcome, [:outcome, :success]) || false
      end)
      
      successful / length(outcomes)
    end
  end
  
  defp calculate_provider_avg_cost(outcomes) do
    if Enum.empty?(outcomes) do
      0.0
    else
      costs = outcomes
      |> Enum.map(fn outcome ->
        get_in(outcome, [:outcome, :cost_usd]) || 0.0
      end)
      
      Enum.sum(costs) / length(costs)
    end
  end
  
  defp calculate_provider_avg_quality(outcomes) do
    if Enum.empty?(outcomes) do
      0.0
    else
      qualities = outcomes
      |> Enum.map(&estimate_outcome_quality_from_data/1)
      
      Enum.sum(qualities) / length(qualities)
    end
  end
  
  defp calculate_provider_avg_response_time(outcomes) do
    if Enum.empty?(outcomes) do
      0
    else
      times = outcomes
      |> Enum.map(fn outcome ->
        get_in(outcome, [:outcome, :response_time_ms]) || 3000
      end)
      
      trunc(Enum.sum(times) / length(times))
    end
  end
  
  defp assess_learning_model_accuracy(learning_models) do
    learning_models
    |> Enum.map(fn {provider, model} ->
      accuracy = Map.get(model, :confidence, 0.5)
      {provider, accuracy}
    end)
    |> Enum.into(%{})
  end
  
  defp identify_optimization_opportunities(provider_outcomes) do
    # Identify opportunities for optimization
    opportunities = []
    
    # Check for cost optimization opportunities
    opportunities = provider_outcomes
    |> Enum.reduce(opportunities, fn {provider, outcomes}, acc ->
      avg_cost = calculate_provider_avg_cost(outcomes)
      
      if avg_cost > 0.1 do
        ["Consider cost optimization for #{provider} provider (avg cost: $#{Float.round(avg_cost, 3)})" | acc]
      else
        acc
      end
    end)
    
    # Check for performance optimization opportunities
    opportunities = provider_outcomes
    |> Enum.reduce(opportunities, fn {provider, outcomes}, acc ->
      avg_time = calculate_provider_avg_response_time(outcomes)
      
      if avg_time > 8000 do
        ["Consider performance optimization for #{provider} provider (avg time: #{avg_time}ms)" | acc]
      else
        acc
      end
    end)
    
    case opportunities do
      [] -> ["No optimization opportunities identified"]
      opps -> opps
    end
  end
  
  defp calculate_overall_prediction_confidence(learning_models) do
    if map_size(learning_models) == 0 do
      0.0
    else
      confidences = learning_models
      |> Map.values()
      |> Enum.map(&Map.get(&1, :confidence, 0.5))
      
      Enum.sum(confidences) / length(confidences)
    end
  end
  
  defp generate_learning_recommendations(state) do
    recommendations = []
    
    # Check learning data sufficiency
    total_outcomes = state.stats.total_outcomes_recorded
    
    recommendations = if total_outcomes < 50 do
      ["Collect more outcome data for improved learning accuracy" | recommendations]
    else
      recommendations
    end
    
    # Check model accuracy
    avg_confidence = calculate_overall_prediction_confidence(state.learning_models)
    
    recommendations = if avg_confidence < 0.7 do
      ["Consider adjusting learning parameters for improved accuracy" | recommendations]
    else
      recommendations
    end
    
    case recommendations do
      [] -> ["Learning system operating effectively"]
      recs -> recs
    end
  end
  
  defp schedule_learning_update do
    Process.send_after(self(), :learning_update, @learning_update_interval)
  end
end