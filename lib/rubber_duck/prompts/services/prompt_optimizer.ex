defmodule RubberDuck.Prompts.Services.PromptOptimizer do
  @moduledoc """
  Library optimization recommendations service for prompt analytics.

  Provides intelligent optimization recommendations based on usage patterns,
  performance analysis, and best practices. Includes prompt structure optimization,
  token efficiency improvements, and organizational recommendations.

  Features:
  - Prompt structure optimization with content analysis and suggestions
  - Token efficiency optimization with cost reduction recommendations
  - Organization optimization with library structure and categorization improvements
  - Performance optimization with response time and success rate improvements
  - Template generation suggestions based on usage pattern analysis
  - Automated optimization scoring with priority ranking and impact assessment
  """

  require Logger

  alias RubberDuck.Prompts.Resources.{Prompt, PromptUsage}
  alias RubberDuck.Prompts.Services.PromptAnalyticsEngine

  @optimization_types [:structure, :tokens, :performance, :organization, :templates]
  @impact_levels [:low, :medium, :high, :critical]
  @effort_levels [:minimal, :low, :medium, :high, :extensive]

  def analyze_optimization_opportunities(target_scope, options \\ %{}) do
    optimization_start_time = System.monotonic_time(:microsecond)

    Logger.debug("PromptOptimizer: Analyzing optimization opportunities",
      target_scope: target_scope,
      optimization_types: Map.get(options, :optimization_types, @optimization_types)
    )

    case execute_optimization_analysis(target_scope, options) do
      {:ok, optimization_results} ->
        optimization_time = System.monotonic_time(:microsecond) - optimization_start_time

        Logger.debug("PromptOptimizer: Optimization analysis completed",
          optimization_time_us: optimization_time,
          opportunities_found: count_optimization_opportunities(optimization_results)
        )

        {:ok, optimization_results}

      {:error, reason} ->
        Logger.error("PromptOptimizer: Optimization analysis failed", error: reason)
        {:error, reason}
    end
  end

  def generate_specific_recommendations(prompt_id, recommendation_types \\ [:all]) do
    case fetch_prompt_optimization_data(prompt_id) do
      {:ok, optimization_data} ->
        recommendations = build_targeted_recommendations(optimization_data, recommendation_types)
        {:ok, recommendations}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def calculate_optimization_impact(optimization_recommendations, current_metrics) do
    impact_analysis =
      Enum.map(optimization_recommendations, fn recommendation ->
        estimated_impact = estimate_recommendation_impact(recommendation, current_metrics)

        Map.merge(recommendation, %{
          estimated_impact: estimated_impact,
          roi_score: calculate_optimization_roi(estimated_impact, recommendation.effort_level),
          priority_score:
            calculate_optimization_priority(estimated_impact, recommendation.effort_level)
        })
      end)

    {:ok, impact_analysis}
  end

  def rank_optimizations_by_priority(
        optimization_recommendations,
        ranking_criteria \\ [:impact, :effort, :feasibility]
      ) do
    ranked_optimizations =
      optimization_recommendations
      |> Enum.map(fn rec -> add_ranking_scores(rec, ranking_criteria) end)
      |> Enum.sort_by(fn rec -> rec.combined_priority_score end, :desc)

    {:ok, ranked_optimizations}
  end

  # Private optimization analysis functions

  defp execute_optimization_analysis(target_scope, options) do
    optimization_types = Map.get(options, :optimization_types, @optimization_types)
    time_window = Map.get(options, :time_window, %{amount: 30, unit: :days})

    with {:ok, usage_data} <- fetch_optimization_data(target_scope, time_window),
         {:ok, optimization_opportunities} <-
           process_optimization_types(usage_data, optimization_types),
         {:ok, prioritized_recommendations} <-
           prioritize_optimization_opportunities(optimization_opportunities) do
      optimization_results = %{
        target_scope: target_scope,
        time_window: time_window,
        data_points_analyzed: length(usage_data),
        optimization_opportunities: optimization_opportunities,
        prioritized_recommendations: prioritized_recommendations,
        overall_optimization_potential:
          calculate_overall_optimization_potential(optimization_opportunities),
        quick_wins: identify_quick_optimization_wins(optimization_opportunities),
        analysis_metadata: %{
          analysis_timestamp: DateTime.utc_now(),
          optimization_types_analyzed: optimization_types
        }
      }

      {:ok, optimization_results}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_optimization_data(target_scope, time_window) do
    cutoff_date = DateTime.add(DateTime.utc_now(), -time_window.amount, time_window.unit)

    base_filters = %{inserted_at: {:>=, cutoff_date}}

    filters =
      case target_scope do
        %{prompt_id: prompt_id} -> Map.put(base_filters, :prompt_id, prompt_id)
        %{user_id: user_id} -> Map.put(base_filters, :used_by_id, user_id)
        :system -> base_filters
        _ -> {:error, :invalid_target_scope}
      end

    case filters do
      {:error, reason} ->
        {:error, reason}

      valid_filters ->
        case RubberDuck.Prompts.Domain.read(PromptUsage, valid_filters) do
          {:ok, usage_records} -> {:ok, usage_records}
          {:error, reason} -> {:error, {:optimization_data_fetch_failed, reason}}
        end
    end
  end

  defp process_optimization_types(usage_data, optimization_types) do
    opportunities = %{}

    # Process each optimization type
    processed_opportunities =
      Enum.reduce(optimization_types, opportunities, fn type, acc ->
        case analyze_optimization_type(type, usage_data) do
          {:ok, type_opportunities} ->
            Map.put(acc, type, type_opportunities)

          {:error, reason} ->
            Logger.warn("PromptOptimizer: Failed to analyze optimization type",
              type: type,
              error: reason
            )

            acc
        end
      end)

    {:ok, processed_opportunities}
  end

  defp analyze_optimization_type(:structure, usage_data) do
    structure_opportunities = %{
      prompt_length_optimization: analyze_prompt_length_issues(usage_data),
      variable_optimization: analyze_variable_usage_efficiency(usage_data),
      content_clarity: analyze_content_clarity_issues(usage_data),
      template_structure: analyze_template_structure_opportunities(usage_data)
    }

    {:ok, structure_opportunities}
  end

  defp analyze_optimization_type(:tokens, usage_data) do
    token_opportunities = %{
      token_reduction_potential: calculate_token_reduction_potential(usage_data),
      cost_optimization: calculate_token_cost_optimization(usage_data),
      compression_opportunities: identify_compression_opportunities(usage_data),
      efficiency_improvements: analyze_token_efficiency_improvements(usage_data)
    }

    {:ok, token_opportunities}
  end

  defp analyze_optimization_type(:performance, usage_data) do
    performance_opportunities = %{
      response_time_optimization: analyze_response_time_optimization(usage_data),
      success_rate_improvement: analyze_success_rate_improvements(usage_data),
      caching_optimization: analyze_caching_opportunities(usage_data),
      parallel_processing: analyze_parallel_processing_opportunities(usage_data)
    }

    {:ok, performance_opportunities}
  end

  defp analyze_optimization_type(:organization, usage_data) do
    organization_opportunities = %{
      categorization_improvements: analyze_categorization_opportunities(usage_data),
      library_structure: analyze_library_structure_optimization(usage_data),
      search_optimization: analyze_search_optimization_opportunities(usage_data),
      workflow_integration: analyze_workflow_integration_opportunities(usage_data)
    }

    {:ok, organization_opportunities}
  end

  defp analyze_optimization_type(:templates, usage_data) do
    template_opportunities = %{
      template_creation_suggestions: identify_template_creation_opportunities(usage_data),
      existing_template_optimization: analyze_existing_template_optimization(usage_data),
      reusability_improvements: analyze_reusability_improvements(usage_data),
      standardization_opportunities: identify_standardization_opportunities(usage_data)
    }

    {:ok, template_opportunities}
  end

  defp prioritize_optimization_opportunities(opportunities) do
    all_recommendations = extract_all_recommendations(opportunities)

    prioritized =
      all_recommendations
      |> Enum.map(&add_priority_scoring/1)
      |> Enum.sort_by(& &1.priority_score, :desc)

    {:ok, prioritized}
  end

  # Recommendation generation functions

  defp build_targeted_recommendations(optimization_data, recommendation_types) do
    base_recommendations = generate_base_recommendations(optimization_data)

    # Filter based on requested types
    filtered_recommendations =
      case recommendation_types do
        [:all] -> base_recommendations
        types -> filter_recommendations_by_type(base_recommendations, types)
      end

    # Add implementation guidance
    enhanced_recommendations =
      Enum.map(filtered_recommendations, fn rec ->
        Map.merge(rec, %{
          implementation_steps: generate_implementation_steps(rec),
          effort_estimate: estimate_implementation_effort(rec),
          expected_timeline: estimate_implementation_timeline(rec)
        })
      end)

    enhanced_recommendations
  end

  defp generate_base_recommendations(optimization_data) do
    recommendations = []

    # Response time recommendations
    avg_response_time = calculate_avg_response_time(optimization_data)

    recommendations =
      if avg_response_time > 3000 do
        [
          %{
            type: :performance,
            category: :response_time,
            description: "Optimize response time performance",
            current_value: avg_response_time,
            target_value: 2000,
            impact_level: :high,
            effort_level: :medium,
            specific_actions: [
              "Simplify prompt structure",
              "Reduce variable complexity",
              "Consider prompt caching"
            ]
          }
          | recommendations
        ]
      else
        recommendations
      end

    # Token optimization recommendations
    avg_tokens = calculate_avg_tokens_used(optimization_data)

    recommendations =
      if avg_tokens > 2000 do
        [
          %{
            type: :efficiency,
            category: :token_usage,
            description: "Optimize token usage for cost efficiency",
            current_value: avg_tokens,
            target_value: 1500,
            impact_level: :medium,
            effort_level: :low,
            specific_actions: [
              "Remove redundant content",
              "Optimize variable descriptions",
              "Use more concise language"
            ]
          }
          | recommendations
        ]
      else
        recommendations
      end

    # Success rate recommendations
    success_rate = calculate_success_rate(optimization_data)

    recommendations =
      if success_rate < 0.9 do
        [
          %{
            type: :reliability,
            category: :success_rate,
            description: "Improve prompt success rate",
            current_value: success_rate,
            target_value: 0.95,
            impact_level: :high,
            effort_level: :medium,
            specific_actions: [
              "Review failed usage patterns",
              "Improve error handling",
              "Enhance input validation"
            ]
          }
          | recommendations
        ]
      else
        recommendations
      end

    recommendations
  end

  # Analysis functions for different optimization types

  defp analyze_prompt_length_issues(usage_data) do
    # Analyze if prompt length correlates with performance issues
    long_prompts =
      Enum.filter(usage_data, fn record ->
        # Estimate prompt length from tokens used
        (record.tokens_used || 0) > 3000
      end)

    %{
      long_prompt_count: length(long_prompts),
      avg_performance_impact: calculate_length_performance_impact(long_prompts),
      optimization_potential: calculate_length_optimization_potential(long_prompts)
    }
  end

  defp calculate_token_reduction_potential(usage_data) do
    avg_tokens = calculate_avg_tokens_used(usage_data)

    # Calculate potential based on token distribution
    %{
      current_avg_tokens: avg_tokens,
      potential_reduction_percent:
        case avg_tokens do
          tokens when tokens > 4000 -> 35
          tokens when tokens > 3000 -> 25
          tokens when tokens > 2000 -> 15
          tokens when tokens > 1000 -> 10
          _ -> 5
        end,
      estimated_cost_savings: calculate_estimated_cost_savings(avg_tokens)
    }
  end

  defp analyze_response_time_optimization(usage_data) do
    response_times = extract_response_times(usage_data)

    %{
      current_avg_ms: calculate_avg_response_time(usage_data),
      p95_response_time: calculate_p95(response_times),
      slow_queries_count: Enum.count(response_times, fn time -> time > 5000 end),
      optimization_targets: identify_response_time_targets(response_times)
    }
  end

  # Utility calculation functions

  defp calculate_avg_response_time(usage_data) do
    valid_times =
      Enum.filter(usage_data, fn record ->
        record.response_time_ms && record.response_time_ms > 0
      end)

    case length(valid_times) do
      0 ->
        0.0

      count ->
        total = Enum.sum(Enum.map(valid_times, & &1.response_time_ms))
        Float.round(total / count, 2)
    end
  end

  defp calculate_success_rate(usage_data) do
    case length(usage_data) do
      0 ->
        0.0

      count ->
        success_count = Enum.count(usage_data, & &1.success)
        Float.round(success_count / count, 3)
    end
  end

  defp calculate_avg_tokens_used(usage_data) do
    valid_tokens =
      Enum.filter(usage_data, fn record ->
        record.tokens_used && record.tokens_used > 0
      end)

    case length(valid_tokens) do
      0 ->
        0.0

      count ->
        total = Enum.sum(Enum.map(valid_tokens, & &1.tokens_used))
        Float.round(total / count, 2)
    end
  end

  defp count_optimization_opportunities(optimization_results) do
    # Count total optimization opportunities across all types
    opportunities_count =
      optimization_results
      |> Map.values()
      |> Enum.flat_map(fn type_opportunities ->
        case type_opportunities do
          map when is_map(map) -> Map.values(map)
          list when is_list(list) -> list
          _ -> []
        end
      end)
      |> length()

    opportunities_count
  end

  defp calculate_overall_optimization_potential(opportunities) do
    # Calculate aggregated optimization potential across all types
    potential_scores =
      opportunities
      |> Map.values()
      |> Enum.flat_map(&extract_potential_scores/1)

    case length(potential_scores) do
      0 -> 0.0
      count -> Enum.sum(potential_scores) / count
    end
  end

  defp identify_quick_optimization_wins(opportunities) do
    # Find optimizations with high impact and low effort
    all_recommendations = extract_all_recommendations(opportunities)

    all_recommendations
    |> Enum.filter(fn rec ->
      rec.impact_level in [:high, :medium] and rec.effort_level in [:minimal, :low]
    end)
    |> Enum.take(5)
  end

  defp extract_all_recommendations(opportunities) do
    # Extract all recommendation objects from the opportunities map
    opportunities
    |> Map.values()
    |> Enum.flat_map(fn type_opps ->
      case type_opps do
        map when is_map(map) -> Map.values(map) |> List.flatten()
        list when is_list(list) -> list
        _ -> []
      end
    end)
    |> Enum.filter(&recommendation?/1)
  end

  defp add_priority_scoring(recommendation) do
    impact_score = score_impact_level(recommendation.impact_level)
    effort_score = score_effort_level(recommendation.effort_level)

    # Priority score: higher impact, lower effort = higher priority
    priority_score = impact_score * 2 - effort_score

    Map.merge(recommendation, %{
      impact_score: impact_score,
      effort_score: effort_score,
      priority_score: priority_score
    })
  end

  defp score_impact_level(:critical), do: 5
  defp score_impact_level(:high), do: 4
  defp score_impact_level(:medium), do: 3
  defp score_impact_level(:low), do: 2
  defp score_impact_level(_), do: 1

  defp score_effort_level(:minimal), do: 1
  defp score_effort_level(:low), do: 2
  defp score_effort_level(:medium), do: 3
  defp score_effort_level(:high), do: 4
  defp score_effort_level(:extensive), do: 5
  defp score_effort_level(_), do: 3

  # Helper functions for optimization analysis

  defp fetch_prompt_optimization_data(prompt_id) do
    time_window = %{amount: 30, unit: :days}
    cutoff_date = DateTime.add(DateTime.utc_now(), -time_window.amount, time_window.unit)

    case RubberDuck.Prompts.Domain.read(PromptUsage, %{
           prompt_id: prompt_id,
           inserted_at: {:>=, cutoff_date}
         }) do
      {:ok, usage_records} ->
        optimization_data = %{
          prompt_id: prompt_id,
          usage_records: usage_records,
          performance_metrics: calculate_performance_summary(usage_records),
          usage_patterns: analyze_usage_patterns(usage_records)
        }

        {:ok, optimization_data}

      {:error, reason} ->
        {:error, {:prompt_data_fetch_failed, reason}}
    end
  end

  defp calculate_performance_summary(usage_records) do
    %{
      avg_response_time: calculate_avg_response_time(usage_records),
      success_rate: calculate_success_rate(usage_records),
      avg_tokens: calculate_avg_tokens_used(usage_records),
      usage_frequency: calculate_usage_frequency(usage_records),
      error_patterns: analyze_error_patterns(usage_records)
    }
  end

  defp analyze_usage_patterns(usage_records) do
    %{
      context_distribution: group_by_context(usage_records),
      temporal_patterns: analyze_temporal_usage(usage_records),
      user_patterns: analyze_user_usage_patterns(usage_records)
    }
  end

  defp calculate_usage_frequency(usage_records) do
    case length(usage_records) do
      0 ->
        0.0

      count ->
        days_span = calculate_date_span(usage_records)
        Float.round(count / max(1, days_span), 2)
    end
  end

  defp calculate_date_span([]), do: 1

  defp calculate_date_span(usage_records) do
    first_date = usage_records |> Enum.min_by(& &1.inserted_at) |> Map.get(:inserted_at)
    last_date = usage_records |> Enum.max_by(& &1.inserted_at) |> Map.get(:inserted_at)

    max(1, DateTime.diff(last_date, first_date, :day))
  end

  defp group_by_context(usage_records) do
    usage_records
    |> Enum.group_by(& &1.context_type)
    |> Enum.map(fn {type, records} -> {type, length(records)} end)
    |> Map.new()
  end

  defp analyze_error_patterns(usage_records) do
    error_records = Enum.filter(usage_records, fn record -> not record.success end)

    %{
      error_count: length(error_records),
      error_rate: calculate_error_rate(usage_records),
      common_errors: group_errors_by_type(error_records)
    }
  end

  defp calculate_error_rate(usage_records) do
    case length(usage_records) do
      0 ->
        0.0

      total ->
        error_count = Enum.count(usage_records, fn record -> not record.success end)
        Float.round(error_count / total, 3)
    end
  end

  defp group_errors_by_type(error_records) do
    error_records
    |> Enum.group_by(fn record -> record.error_type end)
    |> Enum.map(fn {type, records} -> {type, length(records)} end)
    |> Map.new()
  end

  # Placeholder implementations for advanced optimization features
  defp analyze_variable_usage_efficiency(_usage_data), do: %{}
  defp analyze_content_clarity_issues(_usage_data), do: %{}
  defp analyze_template_structure_opportunities(_usage_data), do: %{}
  defp calculate_token_cost_optimization(_usage_data), do: %{}
  defp identify_compression_opportunities(_usage_data), do: %{}
  defp analyze_token_efficiency_improvements(_usage_data), do: %{}
  defp analyze_success_rate_improvements(_usage_data), do: %{}
  defp analyze_caching_opportunities(_usage_data), do: %{}
  defp analyze_parallel_processing_opportunities(_usage_data), do: %{}
  defp analyze_categorization_opportunities(_usage_data), do: %{}
  defp analyze_library_structure_optimization(_usage_data), do: %{}
  defp analyze_search_optimization_opportunities(_usage_data), do: %{}
  defp analyze_workflow_integration_opportunities(_usage_data), do: %{}
  defp identify_template_creation_opportunities(_usage_data), do: %{}
  defp analyze_existing_template_optimization(_usage_data), do: %{}
  defp analyze_reusability_improvements(_usage_data), do: %{}
  defp identify_standardization_opportunities(_usage_data), do: %{}
  defp calculate_length_performance_impact(_long_prompts), do: 0.2
  defp calculate_length_optimization_potential(_long_prompts), do: 0.15
  defp calculate_estimated_cost_savings(_avg_tokens), do: 0.0
  defp extract_response_times(usage_data), do: Enum.map(usage_data, &(&1.response_time_ms || 0))
  defp calculate_p95(times), do: Enum.at(Enum.sort(times), trunc(length(times) * 0.95), 0)
  defp identify_response_time_targets(_times), do: []
  defp extract_potential_scores(_opportunities), do: [0.5]
  defp add_ranking_scores(rec, _criteria), do: Map.put(rec, :combined_priority_score, 5.0)
  defp estimate_recommendation_impact(_rec, _metrics), do: %{improvement_percent: 15}
  defp calculate_optimization_roi(_impact, _effort), do: 2.0
  defp calculate_optimization_priority(_impact, _effort), do: 0.7
  defp filter_recommendations_by_type(recommendations, _types), do: recommendations
  defp generate_implementation_steps(_rec), do: []
  defp estimate_implementation_effort(_rec), do: :medium
  defp estimate_implementation_timeline(_rec), do: "1-2 weeks"
  defp recommendation?(item), do: is_map(item) and Map.has_key?(item, :type)
  defp analyze_prompt_length_issues(_usage_data), do: %{}
  defp analyze_temporal_usage(_usage_records), do: %{}
  defp analyze_user_usage_patterns(_usage_records), do: %{}
end
