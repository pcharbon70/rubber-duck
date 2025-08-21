defmodule RubberDuck.Agents.DataPersistenceAgent do
  @moduledoc """
  Data persistence agent for autonomous query optimization and performance learning.

  This agent manages database queries, connection pools, caching strategies,
  and index optimization with intelligent learning from performance patterns.
  """

  use Jido.Agent,
    name: "data_persistence_agent",
    description: "Autonomous query optimization with performance learning",
    category: "database",
    tags: ["database", "optimization", "performance"],
    vsn: "1.0.0",
    actions: []

  alias RubberDuck.Skills.{LearningSkill, QueryOptimizationSkill}
  alias RubberDuck.Repo

  @doc """
  Create a new DataPersistenceAgent instance.
  """
  def create_data_agent do
    with {:ok, agent} <- __MODULE__.new(),
         {:ok, agent} <-
           __MODULE__.set(agent,
             connection_pool_stats: %{},
             query_performance_history: [],
             cache_performance: %{},
             optimization_results: %{},
             index_recommendations: [],
             learning_insights: [],
             last_optimization: nil
           ) do
      {:ok, agent}
    end
  end

  @doc """
  Optimize query with learning and performance analysis.
  """
  def optimize_query(agent, query, execution_context \\ %{}) do
    case QueryOptimizationSkill.optimize_query(
           %{query: query, execution_context: execution_context},
           agent
         ) do
      {:ok, optimization_result, updated_agent} ->
        # Track query performance
        performance_record = %{
          query_hash: generate_query_hash(query),
          original_query: query,
          optimized_query: optimization_result.optimized_query,
          optimization_applied: optimization_result.optimization_applied,
          performance_impact: measure_performance_impact(optimization_result),
          timestamp: DateTime.utc_now()
        }

        query_history = [performance_record | agent.query_performance_history] |> Enum.take(1000)

        {:ok, final_agent} =
          __MODULE__.set(updated_agent,
            query_performance_history: query_history,
            last_optimization: DateTime.utc_now()
          )

        {:ok, optimization_result, final_agent}

      error ->
        error
    end
  end

  @doc """
  Analyze query patterns and suggest optimizations.
  """
  def analyze_query_patterns(agent, time_window_hours \\ 24) do
    query_history = agent.query_performance_history
    recent_cutoff = DateTime.add(DateTime.utc_now(), -time_window_hours * 3600, :second)

    recent_queries = Enum.filter(query_history, fn record ->
      DateTime.compare(record.timestamp, recent_cutoff) == :gt
    end)

    pattern_analysis = %{
      total_queries: length(recent_queries),
      unique_patterns: count_unique_query_patterns(recent_queries),
      performance_distribution: analyze_performance_distribution(recent_queries),
      optimization_effectiveness: calculate_optimization_effectiveness(recent_queries),
      recommended_actions: generate_pattern_recommendations(recent_queries)
    }

    {:ok, pattern_analysis}
  end

  @doc """
  Suggest database indexes based on query patterns.
  """
  def suggest_indexes(agent, table, analysis_period_hours \\ 48) do
    query_history = agent.query_performance_history
    cutoff_time = DateTime.add(DateTime.utc_now(), -analysis_period_hours * 3600, :second)

    relevant_queries = Enum.filter(query_history, fn record ->
      DateTime.compare(record.timestamp, cutoff_time) == :gt and
      query_references_table?(record.original_query, table)
    end)

    query_patterns = extract_query_patterns(relevant_queries)

    case QueryOptimizationSkill.suggest_index(
           %{table: table, query_patterns: query_patterns},
           agent
         ) do
      {:ok, index_analysis, updated_agent} ->
        # Store index recommendations
        index_recommendations = [index_analysis | agent.index_recommendations] |> Enum.take(100)

        {:ok, final_agent} =
          __MODULE__.set(updated_agent,
            index_recommendations: index_recommendations,
            last_index_analysis: DateTime.utc_now()
          )

        {:ok, index_analysis, final_agent}

      error ->
        error
    end
  end

  @doc """
  Optimize caching strategy based on access patterns.
  """
  def optimize_caching(agent, current_cache_config \\ %{}) do
    query_history = agent.query_performance_history
    access_patterns = extract_access_patterns(query_history)

    case QueryOptimizationSkill.cache_strategy(
           %{access_patterns: access_patterns, cache_config: current_cache_config},
           agent
         ) do
      {:ok, cache_optimization, updated_agent} ->
        # Update cache performance tracking
        cache_performance = Map.merge(agent.cache_performance, %{
          last_optimization: cache_optimization,
          optimization_timestamp: DateTime.utc_now(),
          predicted_improvement: cache_optimization.performance_prediction
        })

        {:ok, final_agent} =
          __MODULE__.set(updated_agent,
            cache_performance: cache_performance,
            last_cache_optimization: DateTime.utc_now()
          )

        {:ok, cache_optimization, final_agent}

      error ->
        error
    end
  end

  @doc """
  Monitor connection pool performance and adjust settings.
  """
  def monitor_connection_pool(agent) do
    # Get current connection pool statistics
    pool_stats = get_connection_pool_stats()
    
    pool_analysis = %{
      current_stats: pool_stats,
      pool_health: assess_pool_health(pool_stats),
      utilization_efficiency: calculate_pool_efficiency(pool_stats),
      recommended_adjustments: recommend_pool_adjustments(pool_stats),
      scaling_predictions: predict_pool_scaling_needs(pool_stats, agent)
    }

    # Update connection pool tracking
    connection_stats = Map.merge(agent.connection_pool_stats, %{
      last_analysis: pool_analysis,
      analysis_timestamp: DateTime.utc_now(),
      health_trend: assess_pool_health_trend(agent.connection_pool_stats, pool_stats)
    })

    {:ok, updated_agent} =
      __MODULE__.set(agent,
        connection_pool_stats: connection_stats,
        last_pool_monitoring: DateTime.utc_now()
      )

    {:ok, pool_analysis, updated_agent}
  end

  @doc """
  Get comprehensive database performance report.
  """
  def get_performance_report(agent) do
    performance_report = %{
      query_optimization_summary: summarize_query_optimization(agent),
      connection_pool_summary: summarize_connection_pool(agent),
      cache_performance_summary: summarize_cache_performance(agent),
      index_recommendations_summary: summarize_index_recommendations(agent),
      overall_database_health: calculate_overall_database_health(agent),
      learning_insights_summary: summarize_learning_insights(agent),
      report_generated_at: DateTime.utc_now()
    }

    {:ok, performance_report}
  end

  # Private helper functions

  defp generate_query_hash(query) do
    query_string = to_string(query)
    :crypto.hash(:sha256, query_string) |> Base.encode16(case: :lower)
  end

  defp measure_performance_impact(optimization_result) do
    # Measure the impact of query optimization
    if optimization_result.optimization_applied do
      # Estimate improvement based on optimization analysis
      estimated_improvement = Map.get(optimization_result.analysis, :estimated_improvement, 0.0)
      
      %{
        improvement_estimated: estimated_improvement,
        confidence: optimization_result.analysis.optimization_confidence,
        measurement_method: :estimated
      }
    else
      %{
        improvement_estimated: 0.0,
        confidence: 1.0,
        measurement_method: :no_optimization
      }
    end
  end

  defp count_unique_query_patterns(queries) do
    queries
    |> Enum.map(&Map.get(&1, :query_hash))
    |> Enum.uniq()
    |> length()
  end

  defp analyze_performance_distribution(queries) do
    if Enum.empty?(queries) do
      %{distribution: :no_data}
    else
      performance_scores = Enum.map(queries, fn record ->
        Map.get(record.performance_impact, :improvement_estimated, 0.0)
      end)

      %{
        average_improvement: Enum.sum(performance_scores) / length(performance_scores),
        max_improvement: Enum.max(performance_scores),
        min_improvement: Enum.min(performance_scores),
        improvement_distribution: categorize_improvements(performance_scores)
      }
    end
  end

  defp calculate_optimization_effectiveness(queries) do
    optimized_queries = Enum.filter(queries, & &1.optimization_applied)
    total_queries = length(queries)

    if total_queries == 0 do
      %{effectiveness: :no_data, optimization_rate: 0.0}
    else
      optimization_rate = length(optimized_queries) / total_queries
      avg_improvement = if Enum.empty?(optimized_queries) do
        0.0
      else
        improvements = Enum.map(optimized_queries, fn query ->
          Map.get(query.performance_impact, :improvement_estimated, 0.0)
        end)
        Enum.sum(improvements) / length(improvements)
      end

      %{
        optimization_rate: optimization_rate,
        average_improvement: avg_improvement,
        effectiveness: categorize_optimization_effectiveness(avg_improvement)
      }
    end
  end

  defp generate_pattern_recommendations(queries) do
    recommendations = []

    # Recommend based on optimization patterns
    unoptimized_count = Enum.count(queries, &(not &1.optimization_applied))
    
    recommendations = if unoptimized_count > length(queries) * 0.3 do
      ["Consider enabling automatic query optimization" | recommendations]
    else
      recommendations
    end

    # Recommend based on performance patterns
    slow_queries = Enum.filter(queries, fn query ->
      estimated_time = get_estimated_execution_time(query)
      estimated_time > 1000  # > 1 second
    end)

    recommendations = if length(slow_queries) > 5 do
      ["Focus on optimizing slow queries (#{length(slow_queries)} identified)" | recommendations]
    else
      recommendations
    end

    if Enum.empty?(recommendations) do
      ["Query performance is within acceptable parameters"]
    else
      recommendations
    end
  end

  defp query_references_table?(query, table) do
    query_string = to_string(query)
    table_string = to_string(table)
    
    String.contains?(query_string, table_string)
  end

  defp extract_query_patterns(queries) do
    # Extract query patterns for analysis
    Enum.map(queries, fn query ->
      %{
        query_hash: query.query_hash,
        performance_impact: query.performance_impact,
        optimization_applied: query.optimization_applied,
        execution_context: %{}  # Simplified for now
      }
    end)
  end

  defp extract_access_patterns(query_history) do
    # Extract access patterns for cache optimization
    Enum.map(query_history, fn record ->
      %{
        query_type: determine_query_type(record.original_query),
        access_count: 1,  # Each record represents one access
        data_size: estimate_query_result_size(record.original_query),
        timestamp: record.timestamp
      }
    end)
  end

  defp get_connection_pool_stats do
    # TODO: Integrate with actual Ecto connection pool stats
    # For now, simulate connection pool statistics
    %{
      pool_size: 10,
      checked_out: :rand.uniform(8),
      checked_in: :rand.uniform(8),
      overflow: :rand.uniform(2),
      total_connections: 10,
      average_wait_time_ms: :rand.uniform(100),
      max_wait_time_ms: :rand.uniform(500),
      timeouts: :rand.uniform(3)
    }
  end

  defp assess_pool_health(pool_stats) do
    utilization = pool_stats.checked_out / pool_stats.pool_size
    timeout_rate = pool_stats.timeouts / max(pool_stats.total_connections, 1)
    
    cond do
      timeout_rate > 0.1 -> :critical  # > 10% timeout rate
      utilization > 0.9 -> :warning    # > 90% utilization
      utilization > 0.7 -> :moderate   # > 70% utilization
      true -> :healthy
    end
  end

  defp calculate_pool_efficiency(pool_stats) do
    utilization = pool_stats.checked_out / pool_stats.pool_size
    wait_efficiency = max(1.0 - (pool_stats.average_wait_time_ms / 1000.0), 0.0)
    
    (utilization + wait_efficiency) / 2
  end

  defp recommend_pool_adjustments(pool_stats) do
    adjustments = []
    health = assess_pool_health(pool_stats)
    
    adjustments = case health do
      :critical ->
        ["Increase pool size immediately", "Investigate connection leaks" | adjustments]
      
      :warning ->
        ["Consider increasing pool size", "Monitor for connection leaks" | adjustments]
      
      :moderate ->
        ["Monitor connection usage patterns" | adjustments]
      
      _ ->
        adjustments
    end

    if pool_stats.average_wait_time_ms > 100 do
      adjustments = ["Optimize query performance to reduce wait times" | adjustments]
    end

    if Enum.empty?(adjustments) do
      ["Connection pool performance is optimal"]
    else
      adjustments
    end
  end

  defp predict_pool_scaling_needs(pool_stats, agent) do
    # Predict future connection pool scaling needs
    query_history = agent.query_performance_history
    recent_query_count = count_recent_queries(query_history, 3600)  # Last hour
    
    predicted_growth = case recent_query_count do
      count when count > 1000 -> :high_growth_expected
      count when count > 500 -> :moderate_growth_expected
      count when count > 100 -> :low_growth_expected
      _ -> :stable_usage_expected
    end

    scaling_recommendation = case {assess_pool_health(pool_stats), predicted_growth} do
      {:critical, _} -> :immediate_scaling_required
      {:warning, growth} when growth in [:high_growth_expected, :moderate_growth_expected] -> :proactive_scaling_recommended
      {:moderate, :high_growth_expected} -> :monitor_for_scaling
      _ -> :no_scaling_needed
    end

    %{
      predicted_growth: predicted_growth,
      scaling_recommendation: scaling_recommendation,
      recommended_pool_size: calculate_recommended_pool_size(pool_stats, predicted_growth),
      confidence: calculate_scaling_confidence(query_history)
    }
  end

  defp assess_pool_health_trend(connection_stats, current_stats) do
    previous_health = Map.get(connection_stats, :last_health, :unknown)
    current_health = assess_pool_health(current_stats)
    
    case {previous_health, current_health} do
      {:healthy, :moderate} -> :declining
      {:moderate, :warning} -> :declining
      {:warning, :critical} -> :rapidly_declining
      {:critical, :warning} -> :improving
      {:warning, :moderate} -> :improving
      {:moderate, :healthy} -> :improving
      {same, same} -> :stable
      _ -> :fluctuating
    end
  end

  # Summary functions

  defp summarize_query_optimization(agent) do
    history = agent.query_performance_history
    recent_history = Enum.take(history, 100)
    
    %{
      total_queries_optimized: length(recent_history),
      optimization_success_rate: calculate_overall_optimization_rate(recent_history),
      average_performance_improvement: calculate_average_improvement(recent_history),
      top_optimization_opportunities: identify_top_opportunities(recent_history)
    }
  end

  defp summarize_connection_pool(agent) do
    stats = Map.get(agent.connection_pool_stats, :last_analysis, %{})
    
    %{
      current_pool_health: Map.get(stats, :pool_health, :unknown),
      efficiency_score: Map.get(stats, :utilization_efficiency, 0.0),
      recent_adjustments: Map.get(stats, :recommended_adjustments, []),
      scaling_status: Map.get(stats, :scaling_predictions, %{})
    }
  end

  defp summarize_cache_performance(agent) do
    cache_perf = agent.cache_performance
    
    %{
      cache_optimization_applied: Map.has_key?(cache_perf, :last_optimization),
      predicted_hit_ratio: get_in(cache_perf, [:predicted_improvement, :predicted_hit_ratio]) || 0.0,
      cache_health: assess_cache_health(cache_perf),
      optimization_recommendations: get_in(cache_perf, [:last_optimization, :monitoring_recommendations]) || []
    }
  end

  defp summarize_index_recommendations(agent) do
    recommendations = agent.index_recommendations
    recent_recommendations = Enum.take(recommendations, 20)
    
    %{
      total_recommendations: length(recent_recommendations),
      high_priority_count: count_high_priority_indexes(recent_recommendations),
      estimated_performance_benefit: calculate_total_index_benefit(recent_recommendations),
      implementation_complexity: assess_overall_index_complexity(recent_recommendations)
    }
  end

  defp calculate_overall_database_health(agent) do
    query_health = assess_query_health(agent.query_performance_history)
    connection_health = Map.get(agent.connection_pool_stats, :last_analysis, %{}) |> Map.get(:pool_health, :unknown)
    cache_health = assess_cache_health(agent.cache_performance)
    
    health_scores = %{
      healthy: 4, moderate: 3, warning: 2, critical: 1, unknown: 0
    }

    total_score = health_scores[query_health] + health_scores[connection_health] + health_scores[cache_health]
    average_score = total_score / 3.0

    cond do
      average_score > 3.5 -> :excellent
      average_score > 2.5 -> :good
      average_score > 1.5 -> :adequate
      average_score > 0.5 -> :concerning
      true -> :critical
    end
  end

  defp summarize_learning_insights(agent) do
    insights = agent.learning_insights
    
    %{
      total_insights: length(insights),
      recent_insights: Enum.take(insights, 10),
      insight_categories: categorize_insights(insights),
      learning_effectiveness: assess_learning_effectiveness(insights)
    }
  end

  # Helper functions

  defp determine_query_type(query) do
    query_string = to_string(query) |> String.upcase()
    
    cond do
      String.starts_with?(query_string, "SELECT") -> :select
      String.starts_with?(query_string, "INSERT") -> :insert
      String.starts_with?(query_string, "UPDATE") -> :update
      String.starts_with?(query_string, "DELETE") -> :delete
      true -> :other
    end
  end

  defp estimate_query_result_size(_query) do
    # TODO: Implement actual result size estimation
    # For now, simulate result sizes
    :rand.uniform(10240)  # 0-10KB
  end

  defp count_recent_queries(query_history, seconds_ago) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -seconds_ago, :second)
    
    Enum.count(query_history, fn record ->
      DateTime.compare(record.timestamp, cutoff_time) == :gt
    end)
  end

  defp calculate_recommended_pool_size(current_stats, predicted_growth) do
    current_size = current_stats.pool_size
    
    case predicted_growth do
      :high_growth_expected -> round(current_size * 1.5)
      :moderate_growth_expected -> round(current_size * 1.3)
      :low_growth_expected -> round(current_size * 1.1)
      _ -> current_size
    end
  end

  defp calculate_scaling_confidence(query_history) do
    # Base confidence on historical data quality
    if length(query_history) < 10 do
      0.3  # Low confidence with little data
    else
      data_quality = min(length(query_history) / 100.0, 1.0)
      temporal_coverage = assess_temporal_coverage(query_history)
      
      (data_quality + temporal_coverage) / 2
    end
  end

  defp assess_temporal_coverage(query_history) do
    if Enum.empty?(query_history) do
      0.0
    else
      timestamps = Enum.map(query_history, & &1.timestamp)
      earliest = Enum.min_by(timestamps, &DateTime.to_unix/1)
      latest = Enum.max_by(timestamps, &DateTime.to_unix/1)
      
      coverage_hours = DateTime.diff(latest, earliest, :hour)
      min(coverage_hours / 24.0, 1.0)  # Full confidence at 24+ hours coverage
    end
  end

  defp categorize_improvements(performance_scores) do
    Enum.frequencies_by(performance_scores, fn score ->
      cond do
        score > 0.5 -> :high_improvement
        score > 0.2 -> :moderate_improvement
        score > 0.0 -> :low_improvement
        true -> :no_improvement
      end
    end)
  end

  defp categorize_optimization_effectiveness(avg_improvement) do
    cond do
      avg_improvement > 0.5 -> :highly_effective
      avg_improvement > 0.3 -> :moderately_effective
      avg_improvement > 0.1 -> :slightly_effective
      true -> :ineffective
    end
  end

  defp get_estimated_execution_time(query) do
    # Extract estimated execution time from query record
    Map.get(query.performance_impact, :estimated_time_ms, 100)
  end

  defp calculate_overall_optimization_rate(queries) do
    if Enum.empty?(queries) do
      0.0
    else
      optimized_count = Enum.count(queries, & &1.optimization_applied)
      optimized_count / length(queries)
    end
  end

  defp calculate_average_improvement(queries) do
    optimized_queries = Enum.filter(queries, & &1.optimization_applied)
    
    if Enum.empty?(optimized_queries) do
      0.0
    else
      improvements = Enum.map(optimized_queries, fn query ->
        Map.get(query.performance_impact, :improvement_estimated, 0.0)
      end)
      
      Enum.sum(improvements) / length(improvements)
    end
  end

  defp identify_top_opportunities(queries) do
    # Identify queries with highest optimization potential
    queries
    |> Enum.filter(&(not &1.optimization_applied))
    |> Enum.sort_by(fn query -> get_estimated_execution_time(query) end, :desc)
    |> Enum.take(5)
    |> Enum.map(fn query -> 
      %{
        query_hash: query.query_hash,
        estimated_improvement: get_estimated_execution_time(query) / 1000.0
      }
    end)
  end

  defp assess_cache_health(cache_performance) do
    if map_size(cache_performance) == 0 do
      :unknown
    else
      hit_ratio = get_in(cache_performance, [:predicted_improvement, :predicted_hit_ratio]) || 0.5
      
      cond do
        hit_ratio > 0.85 -> :excellent
        hit_ratio > 0.70 -> :good
        hit_ratio > 0.50 -> :adequate
        true -> :poor
      end
    end
  end

  defp count_high_priority_indexes(recommendations) do
    Enum.count(recommendations, fn rec ->
      priority = get_in(rec, [:implementation_priority, :high_priority]) || []
      not Enum.empty?(priority)
    end)
  end

  defp calculate_total_index_benefit(recommendations) do
    benefits = Enum.map(recommendations, fn rec ->
      Map.get(rec.performance_impact, :performance_improvement, 0.0)
    end)
    
    if Enum.empty?(benefits), do: 0.0, else: Enum.sum(benefits) / length(benefits)
  end

  defp assess_overall_index_complexity(recommendations) do
    complexities = Enum.map(recommendations, fn rec ->
      Map.get(rec.performance_impact, :implementation_complexity, :simple)
    end)

    complexity_scores = %{simple: 1, moderate: 2, complex: 3, very_complex: 4}
    total_score = Enum.sum(Enum.map(complexities, &complexity_scores[&1]))
    avg_score = total_score / max(length(complexities), 1)

    cond do
      avg_score > 3.0 -> :very_complex
      avg_score > 2.0 -> :complex
      avg_score > 1.5 -> :moderate
      true -> :simple
    end
  end

  defp assess_query_health(query_history) do
    recent_queries = Enum.take(query_history, 100)
    
    if Enum.empty?(recent_queries) do
      :unknown
    else
      slow_query_rate = Enum.count(recent_queries, fn query ->
        get_estimated_execution_time(query) > 1000
      end) / length(recent_queries)

      cond do
        slow_query_rate > 0.2 -> :critical  # > 20% slow queries
        slow_query_rate > 0.1 -> :warning   # > 10% slow queries
        slow_query_rate > 0.05 -> :moderate # > 5% slow queries
        true -> :healthy
      end
    end
  end

  defp categorize_insights(insights) do
    # TODO: Implement insight categorization
    %{performance: length(insights), optimization: 0, caching: 0}
  end

  defp assess_learning_effectiveness(_insights) do
    # TODO: Implement learning effectiveness assessment
    0.7  # Moderate effectiveness as default
  end
end