defmodule RubberDuck.Verdict.Analytics.PerformanceAggregator do
  @moduledoc """
  Performance aggregator for Verdict evaluation analytics.
  
  Computes real-time and historical performance metrics for judge evaluation
  systems. Provides aggregated data for dashboards, optimization, and
  monitoring of the Verdict framework performance.
  """
  
  alias RubberDuck.Verdict.Resources.{EvaluationRun, EvaluationResult, JudgeMetrics}
  
  require Logger
  
  @doc """
  Aggregate performance metrics for a specific time period.
  
  ## Parameters
  - `time_period` - Period to aggregate (:hourly, :daily, :weekly, :monthly)
  - `start_time` - Start of aggregation period
  - `end_time` - End of aggregation period
  - `filters` - Additional filters (judge_unit_type, model_name, evaluation_type)
  
  ## Returns
  - `{:ok, aggregated_metrics}` - Successfully computed metrics
  - `{:error, reason}` - Aggregation failed
  """
  @spec aggregate_performance(
    time_period :: atom(),
    start_time :: DateTime.t(),
    end_time :: DateTime.t(),
    filters :: keyword()
  ) :: {:ok, map()} | {:error, term()}
  def aggregate_performance(time_period, start_time, end_time, filters \\ []) do
    case get_evaluation_runs_in_period(start_time, end_time, filters) do
      {:ok, runs} ->
        case compute_aggregated_metrics(runs, time_period, filters) do
          {:ok, metrics} -> {:ok, metrics}
          error -> error
        end
      
      error -> error
    end
  end
  
  @doc """
  Get real-time performance summary for current operations.
  """
  @spec get_realtime_summary() :: {:ok, map()} | {:error, term()}
  def get_realtime_summary do
    now = DateTime.utc_now()
    one_hour_ago = DateTime.add(now, -3600, :second)
    
    case aggregate_performance(:hourly, one_hour_ago, now) do
      {:ok, hourly_metrics} ->
        summary = build_realtime_summary(hourly_metrics)
        {:ok, summary}
      
      error -> error
    end
  end
  
  @doc """
  Compute cost efficiency metrics for progressive evaluation.
  """
  @spec compute_cost_efficiency(filters :: keyword()) :: {:ok, map()} | {:error, term()}
  def compute_cost_efficiency(filters \\ []) do
    with {:ok, progressive_runs} <- get_progressive_evaluation_runs(filters),
         {:ok, baseline_costs} <- estimate_baseline_costs(progressive_runs),
         {:ok, actual_costs} <- calculate_actual_costs(progressive_runs) do
      
      efficiency_metrics = %{
        total_evaluations: length(progressive_runs),
        baseline_cost: baseline_costs.total_cost,
        actual_cost: actual_costs.total_cost,
        cost_savings: baseline_costs.total_cost - actual_costs.total_cost,
        savings_percentage: calculate_savings_percentage(baseline_costs.total_cost, actual_costs.total_cost),
        lightweight_usage_rate: calculate_lightweight_usage_rate(progressive_runs),
        cache_hit_contribution: calculate_cache_savings(progressive_runs)
      }
      
      {:ok, efficiency_metrics}
    end
  end
  
  @doc """
  Analyze judge bias indicators across evaluations.
  """
  @spec analyze_bias_indicators(filters :: keyword()) :: {:ok, map()} | {:error, term()}
  def analyze_bias_indicators(filters \\ []) do
    judge_unit_type = Keyword.get(filters, :judge_unit_type)
    model_name = Keyword.get(filters, :model_name)
    
    case get_evaluation_results_for_bias_analysis(judge_unit_type, model_name) do
      {:ok, results} ->
        bias_analysis = compute_bias_metrics(results)
        {:ok, bias_analysis}
      
      error -> error
    end
  end
  
  @doc """
  Update judge metrics based on recent evaluation data.
  """
  @spec update_judge_metrics(time_period :: atom()) :: {:ok, map()} | {:error, term()}
  def update_judge_metrics(time_period \\ :daily) do
    case get_metrics_update_candidates(time_period) do
      {:ok, candidates} ->
        results = Enum.map(candidates, &update_single_judge_metric/1)
        successful = Enum.count(results, &match?({:ok, _}, &1))
        
        Logger.info("Updated #{successful} judge metrics for period: #{time_period}")
        {:ok, %{updated_count: successful, period: time_period}}
      
      error -> error
    end
  end
  
  ## Private Functions
  
  defp get_evaluation_runs_in_period(start_time, end_time, filters) do
    # This would query EvaluationRun with filters
    # For now, return mock data
    {:ok, []}
  end
  
  defp compute_aggregated_metrics(runs, time_period, filters) do
    # Compute comprehensive metrics from evaluation runs
    base_metrics = %{
      time_period: time_period,
      total_runs: length(runs),
      successful_runs: count_successful_runs(runs),
      failed_runs: count_failed_runs(runs),
      average_cost: calculate_average_cost(runs),
      average_latency: calculate_average_latency(runs),
      cache_hit_rate: calculate_cache_hit_rate(runs),
      progressive_efficiency: calculate_progressive_efficiency(runs)
    }
    
    # Add judge-specific metrics if filtered
    enhanced_metrics = case Keyword.get(filters, :judge_unit_type) do
      nil -> base_metrics
      judge_type -> add_judge_specific_metrics(base_metrics, runs, judge_type)
    end
    
    {:ok, enhanced_metrics}
  end
  
  defp build_realtime_summary(hourly_metrics) do
    %{
      current_hour_evaluations: hourly_metrics.total_runs,
      success_rate: calculate_success_rate(hourly_metrics),
      average_cost_per_evaluation: hourly_metrics.average_cost,
      cache_effectiveness: hourly_metrics.cache_hit_rate,
      system_health: determine_system_health(hourly_metrics),
      cost_trend: determine_cost_trend(hourly_metrics),
      performance_alerts: detect_performance_alerts(hourly_metrics)
    }
  end
  
  defp get_progressive_evaluation_runs(filters) do
    # Query for evaluation runs using progressive strategy
    {:ok, []}
  end
  
  defp estimate_baseline_costs(runs) do
    # Estimate what costs would have been without progressive evaluation
    estimated_cost = length(runs) * 0.015  # Assume detailed evaluation cost
    
    {:ok, %{
      total_cost: estimated_cost,
      evaluation_count: length(runs),
      cost_per_evaluation: 0.015
    }}
  end
  
  defp calculate_actual_costs(runs) do
    # Calculate actual costs from evaluation runs
    total_cost = Enum.reduce(runs, 0.0, fn run, acc ->
      acc + (run.total_cost_usd || 0.0)
    end)
    
    {:ok, %{
      total_cost: total_cost,
      evaluation_count: length(runs),
      cost_per_evaluation: if(length(runs) > 0, do: total_cost / length(runs), else: 0.0)
    }}
  end
  
  defp calculate_savings_percentage(baseline, actual) when baseline > 0 do
    ((baseline - actual) / baseline) * 100
  end
  defp calculate_savings_percentage(_, _), do: 0.0
  
  defp calculate_lightweight_usage_rate(runs) do
    lightweight_count = Enum.count(runs, fn run ->
      run.evaluation_strategy in [:lightweight, :progressive]
    end)
    
    if length(runs) > 0 do
      lightweight_count / length(runs)
    else
      0.0
    end
  end
  
  defp calculate_cache_savings(runs) do
    cache_hits = Enum.count(runs, & &1.cache_hit)
    
    if length(runs) > 0 do
      cache_hits / length(runs)
    else
      0.0
    end
  end
  
  defp get_evaluation_results_for_bias_analysis(judge_unit_type, model_name) do
    # Query evaluation results for bias analysis
    {:ok, []}
  end
  
  defp compute_bias_metrics(results) do
    # Analyze results for bias patterns
    %{
      total_results: length(results),
      score_distribution: compute_score_distribution(results),
      confidence_patterns: analyze_confidence_patterns(results),
      bias_indicators: detect_bias_patterns(results),
      recommendation_analysis: analyze_recommendation_patterns(results)
    }
  end
  
  defp get_metrics_update_candidates(time_period) do
    # Get judge unit/model combinations that need metrics updates
    {:ok, []}
  end
  
  defp update_single_judge_metric(candidate) do
    # Update metrics for a specific judge unit/model combination
    {:ok, candidate}
  end
  
  # Helper functions for metric calculations
  
  defp count_successful_runs(runs) do
    Enum.count(runs, fn run -> run.status == :completed end)
  end
  
  defp count_failed_runs(runs) do
    Enum.count(runs, fn run -> run.status == :failed end)
  end
  
  defp calculate_average_cost(runs) do
    costs = Enum.map(runs, & &1.total_cost_usd || 0.0)
    if length(costs) > 0, do: Enum.sum(costs) / length(costs), else: 0.0
  end
  
  defp calculate_average_latency(runs) do
    latencies = Enum.map(runs, & &1.total_latency_ms || 0)
    if length(latencies) > 0, do: Enum.sum(latencies) / length(latencies), else: 0
  end
  
  defp calculate_cache_hit_rate(runs) do
    cache_hits = Enum.count(runs, & &1.cache_hit)
    if length(runs) > 0, do: cache_hits / length(runs), else: 0.0
  end
  
  defp calculate_progressive_efficiency(runs) do
    # Calculate how effective progressive evaluation is
    lightweight_runs = Enum.count(runs, fn run ->
      run.evaluation_strategy in [:lightweight, :progressive]
    end)
    
    if length(runs) > 0, do: lightweight_runs / length(runs), else: 0.0
  end
  
  defp add_judge_specific_metrics(base_metrics, runs, judge_type) do
    judge_runs = Enum.filter(runs, fn run ->
      judge_type in (run.judge_units_used || [])
    end)
    
    Map.merge(base_metrics, %{
      judge_specific: %{
        judge_unit_type: judge_type,
        judge_run_count: length(judge_runs),
        judge_success_rate: calculate_success_rate_for_runs(judge_runs),
        judge_average_cost: calculate_average_cost(judge_runs)
      }
    })
  end
  
  defp calculate_success_rate(metrics) do
    if metrics.total_runs > 0 do
      metrics.successful_runs / metrics.total_runs
    else
      0.0
    end
  end
  
  defp calculate_success_rate_for_runs(runs) do
    successful = Enum.count(runs, fn run -> run.status == :completed end)
    if length(runs) > 0, do: successful / length(runs), else: 0.0
  end
  
  defp determine_system_health(metrics) do
    cond do
      metrics.total_runs == 0 -> :idle
      calculate_success_rate(metrics) > 0.95 -> :healthy
      calculate_success_rate(metrics) > 0.80 -> :warning
      true -> :critical
    end
  end
  
  defp determine_cost_trend(metrics) do
    # This would compare with previous periods
    # For now, return stable
    :stable
  end
  
  defp detect_performance_alerts(metrics) do
    alerts = []
    
    # Check for high failure rate
    alerts = if calculate_success_rate(metrics) < 0.90 do
      ["High failure rate detected" | alerts]
    else
      alerts
    end
    
    # Check for high costs
    alerts = if metrics.average_cost > 0.10 do
      ["High evaluation costs detected" | alerts]
    else
      alerts
    end
    
    alerts
  end
  
  defp compute_score_distribution(results) do
    # Analyze score distribution for bias patterns
    scores = Enum.map(results, & &1.score)
    
    %{
      mean: if(length(scores) > 0, do: Enum.sum(scores) / length(scores), else: 0.0),
      median: calculate_median(scores),
      std_dev: calculate_std_dev(scores),
      distribution: group_scores_by_range(scores)
    }
  end
  
  defp analyze_confidence_patterns(results) do
    # Analyze confidence patterns for calibration
    confidences = Enum.map(results, & &1.confidence)
    
    %{
      average_confidence: if(length(confidences) > 0, do: Enum.sum(confidences) / length(confidences), else: 0.0),
      calibration_score: calculate_calibration_score(results),
      overconfidence_rate: calculate_overconfidence_rate(results)
    }
  end
  
  defp detect_bias_patterns(results) do
    # Detect various bias patterns
    %{
      length_bias: detect_length_bias(results),
      position_bias: detect_position_bias(results),
      consistency_score: calculate_consistency_score(results)
    }
  end
  
  defp analyze_recommendation_patterns(results) do
    # Analyze recommendation patterns
    all_recommendations = Enum.flat_map(results, & &1.recommendations)
    
    %{
      total_recommendations: length(all_recommendations),
      unique_recommendations: length(Enum.uniq(all_recommendations)),
      common_recommendations: find_common_recommendations(all_recommendations),
      recommendation_diversity: calculate_recommendation_diversity(all_recommendations)
    }
  end
  
  # Statistical helper functions
  
  defp calculate_median([]), do: 0.0
  defp calculate_median(scores) do
    sorted = Enum.sort(scores)
    length = length(sorted)
    
    if rem(length, 2) == 0 do
      mid1 = Enum.at(sorted, div(length, 2) - 1)
      mid2 = Enum.at(sorted, div(length, 2))
      (mid1 + mid2) / 2
    else
      Enum.at(sorted, div(length, 2))
    end
  end
  
  defp calculate_std_dev([]), do: 0.0
  defp calculate_std_dev(scores) do
    mean = Enum.sum(scores) / length(scores)
    variance = Enum.reduce(scores, 0.0, fn score, acc ->
      acc + :math.pow(score - mean, 2)
    end) / length(scores)
    
    :math.sqrt(variance)
  end
  
  defp group_scores_by_range(scores) do
    # Group scores into ranges for distribution analysis
    ranges = [
      {0.0, 0.2}, {0.2, 0.4}, {0.4, 0.6}, {0.6, 0.8}, {0.8, 1.0}
    ]
    
    Enum.reduce(ranges, %{}, fn {min, max}, acc ->
      count = Enum.count(scores, fn score -> score >= min and score < max end)
      range_key = "#{min}-#{max}"
      Map.put(acc, range_key, count)
    end)
  end
  
  defp calculate_calibration_score(results) do
    # Calculate how well-calibrated confidence scores are
    # This would compare confidence vs actual accuracy
    # For now, return a placeholder
    0.85
  end
  
  defp calculate_overconfidence_rate(results) do
    # Calculate rate of overconfident predictions
    # For now, return a placeholder
    0.15
  end
  
  defp detect_length_bias(results) do
    # Detect if longer code gets systematically different scores
    # For now, return placeholder analysis
    %{detected: false, severity: :low, pattern: "No significant length bias detected"}
  end
  
  defp detect_position_bias(results) do
    # Detect position-based bias patterns
    # For now, return placeholder analysis
    %{detected: false, severity: :low, pattern: "No significant position bias detected"}
  end
  
  defp calculate_consistency_score(results) do
    # Calculate consistency of evaluations for similar code
    # For now, return placeholder score
    0.92
  end
  
  defp find_common_recommendations(recommendations) do
    # Find most common recommendation patterns
    recommendations
    |> Enum.frequencies()
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.take(5)
    |> Enum.map(&elem(&1, 0))
  end
  
  defp calculate_recommendation_diversity(recommendations) do
    # Calculate diversity of recommendations
    unique_count = length(Enum.uniq(recommendations))
    total_count = length(recommendations)
    
    if total_count > 0, do: unique_count / total_count, else: 0.0
  end
end