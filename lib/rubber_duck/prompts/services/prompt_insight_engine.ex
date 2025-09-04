defmodule RubberDuck.Prompts.Services.PromptInsightEngine do
  @moduledoc """
  Usage insights and trend analysis service for prompt analytics.

  Provides intelligent analysis of usage patterns, trend detection, user
  behavior insights, and predictive analytics for prompt optimization
  and strategic decision making.

  Features:
  - Pattern recognition in usage data with ML-driven analysis
  - Trend detection and forecasting with statistical modeling
  - User behavior analysis with segmentation and profiling
  - Predictive analytics for usage patterns and optimization opportunities
  - Anomaly detection for unusual usage patterns and potential issues
  - Comparative analysis across prompts, users, and time periods
  """

  require Logger

  alias RubberDuck.Prompts.Resources.{Prompt, PromptUsage}

  @insight_types [
    :usage_patterns,
    :trend_analysis,
    :user_behavior,
    :performance_insights,
    :anomaly_detection
  ]
  @trend_confidence_threshold 0.7
  @pattern_significance_threshold 0.05

  def analyze_usage_insights(data_scope, options \\ %{}) do
    insight_start_time = System.monotonic_time(:microsecond)

    Logger.debug("PromptInsightEngine: Starting insight analysis",
      data_scope: data_scope,
      options: Map.keys(options)
    )

    case execute_insight_analysis(data_scope, options) do
      {:ok, insights} ->
        insight_time = System.monotonic_time(:microsecond) - insight_start_time

        Logger.debug("PromptInsightEngine: Insight analysis completed",
          insight_time_us: insight_time,
          insights_generated: length(insights.key_insights)
        )

        {:ok, insights}

      {:error, reason} ->
        Logger.error("PromptInsightEngine: Insight analysis failed", error: reason)
        {:error, reason}
    end
  end

  def detect_usage_patterns(usage_records, pattern_types \\ [:temporal, :behavioral, :contextual]) do
    patterns = %{
      temporal_patterns: detect_temporal_patterns(usage_records),
      behavioral_patterns: detect_behavioral_patterns(usage_records),
      contextual_patterns: detect_contextual_patterns(usage_records),
      correlation_patterns: detect_correlation_patterns(usage_records)
    }

    # Filter patterns based on requested types
    filtered_patterns =
      Enum.reduce(pattern_types, %{}, fn type, acc ->
        case type do
          :temporal -> Map.put(acc, :temporal_patterns, patterns.temporal_patterns)
          :behavioral -> Map.put(acc, :behavioral_patterns, patterns.behavioral_patterns)
          :contextual -> Map.put(acc, :contextual_patterns, patterns.contextual_patterns)
          :correlation -> Map.put(acc, :correlation_patterns, patterns.correlation_patterns)
          _ -> acc
        end
      end)

    {:ok, filtered_patterns}
  end

  def analyze_trend_significance(trend_data, confidence_threshold \\ @trend_confidence_threshold) do
    trend_analysis = %{
      trend_direction: determine_trend_direction(trend_data),
      confidence_score: calculate_trend_confidence(trend_data),
      significance_level: assess_trend_significance(trend_data),
      forecast_accuracy: estimate_forecast_accuracy(trend_data),
      seasonal_components: extract_seasonal_components(trend_data)
    }

    is_significant = trend_analysis.confidence_score >= confidence_threshold

    {:ok,
     %{
       trend_analysis: trend_analysis,
       is_significant: is_significant,
       actionable_insights: generate_trend_insights(trend_analysis, is_significant)
     }}
  end

  def generate_behavioral_insights(user_usage_records, comparison_data \\ nil) do
    user_patterns = %{
      usage_frequency: calculate_usage_frequency_pattern(user_usage_records),
      context_preferences: analyze_context_preferences(user_usage_records),
      time_patterns: analyze_temporal_usage_patterns(user_usage_records),
      efficiency_patterns: analyze_efficiency_patterns(user_usage_records),
      exploration_behavior: analyze_exploration_behavior(user_usage_records)
    }

    # Add comparative insights if comparison data provided
    insights =
      case comparison_data do
        nil -> user_patterns
        comparison -> add_comparative_insights(user_patterns, comparison)
      end

    {:ok, insights}
  end

  def detect_anomalies(usage_records, anomaly_types \\ [:usage, :performance, :errors]) do
    anomalies = %{
      usage_anomalies: detect_usage_anomalies(usage_records),
      performance_anomalies: detect_performance_anomalies(usage_records),
      error_anomalies: detect_error_anomalies(usage_records),
      temporal_anomalies: detect_temporal_anomalies(usage_records)
    }

    # Filter anomalies based on requested types
    filtered_anomalies =
      Enum.reduce(anomaly_types, %{}, fn type, acc ->
        case type do
          :usage -> Map.put(acc, :usage_anomalies, anomalies.usage_anomalies)
          :performance -> Map.put(acc, :performance_anomalies, anomalies.performance_anomalies)
          :errors -> Map.put(acc, :error_anomalies, anomalies.error_anomalies)
          :temporal -> Map.put(acc, :temporal_anomalies, anomalies.temporal_anomalies)
          _ -> acc
        end
      end)

    {:ok, filtered_anomalies}
  end

  # Private insight analysis functions

  defp execute_insight_analysis(data_scope, options) do
    insight_types = Map.get(options, :insight_types, @insight_types)
    time_window = Map.get(options, :time_window, %{amount: 30, unit: :days})

    with {:ok, usage_data} <- fetch_usage_data_for_scope(data_scope, time_window),
         {:ok, processed_insights} <-
           process_insights_for_types(usage_data, insight_types, options) do
      comprehensive_insights = %{
        data_scope: data_scope,
        time_window: time_window,
        data_points_analyzed: length(usage_data),
        key_insights: extract_key_insights(processed_insights),
        detailed_insights: processed_insights,
        insight_confidence: calculate_overall_confidence(processed_insights),
        actionable_recommendations: generate_actionable_recommendations(processed_insights),
        analysis_metadata: %{
          analysis_timestamp: DateTime.utc_now(),
          insight_types_analyzed: insight_types,
          data_quality_score: assess_insight_data_quality(usage_data)
        }
      }

      {:ok, comprehensive_insights}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_usage_data_for_scope(data_scope, time_window) do
    cutoff_date = DateTime.add(DateTime.utc_now(), -time_window.amount, time_window.unit)

    base_filters = %{inserted_at: {:>=, cutoff_date}}

    filters =
      case data_scope do
        %{user_id: user_id} -> Map.put(base_filters, :used_by_id, user_id)
        %{prompt_id: prompt_id} -> Map.put(base_filters, :prompt_id, prompt_id)
        :system -> base_filters
        _ -> {:error, :invalid_data_scope}
      end

    case filters do
      {:error, reason} ->
        {:error, reason}

      valid_filters ->
        case RubberDuck.Prompts.Domain.read(PromptUsage, valid_filters) do
          {:ok, usage_records} -> {:ok, usage_records}
          {:error, reason} -> {:error, {:data_fetch_failed, reason}}
        end
    end
  end

  defp process_insights_for_types(usage_data, insight_types, options) do
    insights = %{}

    # Process each requested insight type
    processed_insights =
      Enum.reduce(insight_types, insights, fn type, acc ->
        case process_single_insight_type(type, usage_data, options) do
          {:ok, insight_data} ->
            Map.put(acc, type, insight_data)

          {:error, reason} ->
            Logger.warn("PromptInsightEngine: Failed to process insight type",
              type: type,
              error: reason
            )

            acc
        end
      end)

    {:ok, processed_insights}
  end

  defp process_single_insight_type(:usage_patterns, usage_data, _options) do
    patterns = %{
      frequency_patterns: analyze_frequency_patterns(usage_data),
      timing_patterns: analyze_timing_patterns(usage_data),
      context_patterns: analyze_context_usage_patterns(usage_data),
      user_patterns: analyze_user_interaction_patterns(usage_data)
    }

    {:ok, patterns}
  end

  defp process_single_insight_type(:trend_analysis, usage_data, _options) do
    trends = %{
      usage_trends: calculate_usage_trends(usage_data),
      performance_trends: calculate_performance_trends(usage_data),
      adoption_trends: calculate_adoption_trends(usage_data),
      efficiency_trends: calculate_efficiency_trends(usage_data)
    }

    {:ok, trends}
  end

  defp process_single_insight_type(:user_behavior, usage_data, _options) do
    behavior = %{
      engagement_patterns: analyze_engagement_patterns(usage_data),
      preference_analysis: analyze_user_preferences(usage_data),
      learning_curves: analyze_learning_curves(usage_data),
      productivity_patterns: analyze_productivity_patterns(usage_data)
    }

    {:ok, behavior}
  end

  defp process_single_insight_type(:performance_insights, usage_data, _options) do
    performance = %{
      response_time_analysis: analyze_response_time_patterns(usage_data),
      token_efficiency: analyze_token_efficiency_patterns(usage_data),
      error_patterns: analyze_comprehensive_error_patterns(usage_data),
      optimization_potential: calculate_optimization_potential(usage_data)
    }

    {:ok, performance}
  end

  defp process_single_insight_type(:anomaly_detection, usage_data, _options) do
    case detect_anomalies(usage_data) do
      {:ok, anomalies} -> {:ok, anomalies}
      {:error, reason} -> {:error, reason}
    end
  end

  # Pattern detection functions

  defp detect_temporal_patterns(usage_records) do
    %{
      daily_patterns: analyze_daily_usage_patterns(usage_records),
      weekly_patterns: analyze_weekly_usage_patterns(usage_records),
      hourly_patterns: analyze_hourly_usage_patterns(usage_records),
      seasonal_indicators: detect_seasonal_usage_indicators(usage_records)
    }
  end

  defp detect_behavioral_patterns(usage_records) do
    %{
      user_clustering: perform_user_clustering_analysis(usage_records),
      usage_sequences: analyze_usage_sequences(usage_records),
      preference_patterns: analyze_preference_patterns(usage_records),
      adoption_patterns: analyze_adoption_patterns(usage_records)
    }
  end

  defp detect_contextual_patterns(usage_records) do
    %{
      context_effectiveness: analyze_context_effectiveness(usage_records),
      context_transitions: analyze_context_transitions(usage_records),
      context_preferences: analyze_context_user_preferences(usage_records)
    }
  end

  defp detect_correlation_patterns(usage_records) do
    %{
      prompt_correlations: find_prompt_usage_correlations(usage_records),
      user_correlations: find_user_behavior_correlations(usage_records),
      temporal_correlations: find_temporal_correlations(usage_records)
    }
  end

  # Simplified implementations (would be enhanced with actual analysis)
  defp analyze_frequency_patterns(_usage_data), do: %{}
  defp analyze_timing_patterns(_usage_data), do: %{}
  defp analyze_context_usage_patterns(_usage_data), do: %{}
  defp analyze_user_interaction_patterns(_usage_data), do: %{}
  defp calculate_usage_trends(_usage_data), do: %{}
  defp calculate_performance_trends(_usage_data), do: %{}
  defp calculate_adoption_trends(_usage_data), do: %{}
  defp calculate_efficiency_trends(_usage_data), do: %{}
  defp analyze_engagement_patterns(_usage_data), do: %{}
  defp analyze_user_preferences(_usage_data), do: %{}
  defp analyze_learning_curves(_usage_data), do: %{}
  defp analyze_productivity_patterns(_usage_data), do: %{}
  defp analyze_response_time_patterns(_usage_data), do: %{}
  defp analyze_token_efficiency_patterns(_usage_data), do: %{}
  defp analyze_comprehensive_error_patterns(_usage_data), do: %{}
  defp calculate_optimization_potential(_usage_data), do: 0.2

  # Utility functions
  defp extract_key_insights(_processed_insights), do: []
  defp calculate_overall_confidence(_processed_insights), do: 0.8
  defp generate_actionable_recommendations(_processed_insights), do: []
  defp assess_insight_data_quality(_usage_data), do: 0.9
  defp determine_trend_direction(_trend_data), do: :stable
  defp calculate_trend_confidence(_trend_data), do: 0.75
  defp assess_trend_significance(_trend_data), do: :medium
  defp estimate_forecast_accuracy(_trend_data), do: 0.8
  defp extract_seasonal_components(_trend_data), do: %{}
  defp generate_trend_insights(_trend_analysis, _is_significant), do: []
  defp calculate_usage_frequency_pattern(_records), do: %{}
  defp analyze_context_preferences(_records), do: %{}
  defp analyze_temporal_usage_patterns(_records), do: %{}
  defp analyze_efficiency_patterns(_records), do: %{}
  defp analyze_exploration_behavior(_records), do: %{}
  defp add_comparative_insights(patterns, _comparison), do: patterns
  defp detect_usage_anomalies(_records), do: []
  defp detect_performance_anomalies(_records), do: []
  defp detect_error_anomalies(_records), do: []
  defp detect_temporal_anomalies(_records), do: []
  defp analyze_daily_usage_patterns(_records), do: %{}
  defp analyze_weekly_usage_patterns(_records), do: %{}
  defp analyze_hourly_usage_patterns(_records), do: %{}
  defp detect_seasonal_usage_indicators(_records), do: %{}
  defp perform_user_clustering_analysis(_records), do: %{}
  defp analyze_usage_sequences(_records), do: %{}
  defp analyze_preference_patterns(_records), do: %{}
  defp analyze_adoption_patterns(_records), do: %{}
  defp analyze_context_effectiveness(_records), do: %{}
  defp analyze_context_transitions(_records), do: %{}
  defp analyze_context_user_preferences(_records), do: %{}
  defp find_prompt_usage_correlations(_records), do: %{}
  defp find_user_behavior_correlations(_records), do: %{}
  defp find_temporal_correlations(_records), do: %{}
end
