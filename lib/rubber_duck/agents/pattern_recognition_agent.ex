defmodule RubberDuck.Agents.PatternRecognitionAgent do
  @moduledoc """
  Machine learning-powered pattern recognition agent for continuous learning system.

  Identifies success patterns, failure modes, user preference patterns, and judge
  performance patterns using clustering algorithms, anomaly detection, and
  temporal analysis to fuel adaptive system improvements.
  """

  use Jido.Agent, name: "PatternRecognition"

  require Logger

  alias RubberDuck.Verdict.Analytics.{
    ComparativePerformanceAnalyzer,
    FailureModeDetector,
    SuccessPatternAnalyzer,
    TemporalTrendAnalyzer,
    UserPreferenceProfiler
  }

  @analysis_types [
    :success_patterns,
    :failure_modes,
    :user_preferences,
    :temporal_trends,
    :judge_performance,
    :system_optimization
  ]

  @pattern_confidence_thresholds %{
    success_patterns: 0.8,
    failure_modes: 0.75,
    user_preferences: 0.7,
    temporal_trends: 0.65,
    judge_performance: 0.8,
    system_optimization: 0.7
  }

  @impl true
  def init(opts \\ []) do
    state = %{
      active_analyses: %{},
      pattern_cache: %{},
      learning_models: %{},
      analysis_history: [],
      performance_metrics: %{
        patterns_identified: 0,
        analysis_time_avg: 0.0,
        pattern_accuracy_rate: 0.9,
        model_update_count: 0
      },
      configuration: %{
        max_concurrent_analyses: Keyword.get(opts, :max_concurrent, 3),
        pattern_confidence_threshold: Keyword.get(opts, :confidence_threshold, 0.7),
        cache_retention_hours: Keyword.get(opts, :cache_retention, 24),
        ml_model_update_frequency: Keyword.get(opts, :model_update_freq, :daily)
      }
    }

    {:ok, state}
  end

  @doc """
  Recognize patterns in feedback and evaluation data using ML algorithms.

  ## Parameters
  - `agent` - The pattern recognition agent instance
  - `analysis_type` - Type of pattern analysis to perform
  - `data_set` - Data to analyze for patterns
  - `options` - Analysis options and configuration

  ## Returns
  - `{:ok, recognized_patterns, updated_agent}` - Pattern recognition successful
  - `{:error, reason, agent}` - Pattern recognition failed
  """
  def recognize_patterns(agent, analysis_type, data_set, options \\ []) do
    start_time = System.monotonic_time(:millisecond)

    Logger.info("Starting #{analysis_type} pattern recognition on #{length(data_set)} items")

    case validate_analysis_request(analysis_type, data_set, options) do
      :ok ->
        case execute_pattern_analysis(agent, analysis_type, data_set, options) do
          {:ok, patterns, updated_agent} ->
            analysis_time = System.monotonic_time(:millisecond) - start_time
            final_agent = update_analysis_metrics(updated_agent, patterns, analysis_time)

            Logger.info(
              "Pattern recognition completed in #{analysis_time}ms: #{length(patterns.identified_patterns)} patterns found"
            )

            {:ok, patterns, final_agent}

          {:error, reason} ->
            Logger.error("Pattern recognition failed: #{reason}")
            {:error, reason, agent}
        end

      {:error, reason} ->
        Logger.error("Analysis request validation failed: #{reason}")
        {:error, reason, agent}
    end
  end

  @doc """
  Analyze patterns for specific learning focus areas.

  ## Parameters
  - `agent` - The pattern recognition agent instance
  - `focus_areas` - List of specific areas to focus analysis on
  - `data_context` - Context data for focused analysis
  - `options` - Analysis options

  ## Returns
  - `{:ok, focused_patterns, updated_agent}` - Focused analysis successful
  - `{:error, reason, agent}` - Analysis failed
  """
  def analyze_focused_patterns(agent, focus_areas, data_context, options \\ []) do
    Logger.info("Analyzing focused patterns for areas: #{inspect(focus_areas)}")

    focused_analyses =
      Enum.map(focus_areas, fn area ->
        analyze_single_focus_area(agent, area, data_context, options)
      end)

    successful_analyses = Enum.filter(focused_analyses, &match?({:ok, _}, &1))
    failed_analyses = Enum.filter(focused_analyses, &match?({:error, _}, &1))

    if length(successful_analyses) > 0 do
      combined_patterns = combine_focused_analyses(successful_analyses)
      updated_agent = record_focused_analysis_success(agent, focus_areas, combined_patterns)

      {:ok, combined_patterns, updated_agent}
    else
      error_reasons = Enum.map(failed_analyses, fn {:error, reason} -> reason end)
      {:error, "All focused analyses failed: #{Enum.join(error_reasons, "; ")}", agent}
    end
  end

  @doc """
  Get current pattern recognition statistics and model performance.
  """
  def get_recognition_stats(agent) do
    stats = agent.state.performance_metrics
    cache_info = analyze_pattern_cache(agent.state.pattern_cache)

    %{
      total_patterns_identified: stats.patterns_identified,
      average_analysis_time_ms: stats.analysis_time_avg,
      pattern_accuracy_rate: stats.pattern_accuracy_rate,
      model_update_count: stats.model_update_count,
      active_analyses_count: map_size(agent.state.active_analyses),
      cached_patterns_count: cache_info.total_cached,
      cache_hit_rate: cache_info.hit_rate,
      learning_model_count: map_size(agent.state.learning_models),
      recent_analysis_history: Enum.take(agent.state.analysis_history, 10)
    }
  end

  @doc """
  Configure pattern recognition parameters and thresholds.
  """
  def configure_recognition(agent, new_config) do
    merged_config = Map.merge(agent.state.configuration, new_config)
    updated_agent = put_in(agent.state.configuration, merged_config)

    Logger.info("Updated pattern recognition configuration")
    {:ok, updated_agent}
  end

  @doc """
  Clear pattern cache and reset learning models.
  """
  def reset_learning_models(agent, reset_options \\ []) do
    keep_history = Keyword.get(reset_options, :keep_history, true)

    updated_state = %{
      agent.state
      | pattern_cache: %{},
        learning_models: %{},
        analysis_history: if(keep_history, do: agent.state.analysis_history, else: [])
    }

    Logger.info("Learning models reset")
    {:ok, %{agent | state: updated_state}}
  end

  ## Private Analysis Functions

  defp validate_analysis_request(analysis_type, data_set, options) do
    cond do
      analysis_type not in @analysis_types ->
        {:error, "Unknown analysis type: #{analysis_type}"}

      not is_list(data_set) ->
        {:error, "Data set must be a list"}

      Enum.empty?(data_set) ->
        {:error, "Data set cannot be empty"}

      not is_list(options) ->
        {:error, "Options must be a keyword list"}

      true ->
        :ok
    end
  end

  defp execute_pattern_analysis(agent, analysis_type, data_set, options) do
    # Check cache first for performance
    cache_key = generate_cache_key(analysis_type, data_set, options)

    case get_cached_patterns(agent, cache_key) do
      {:hit, cached_patterns} ->
        Logger.debug("Using cached patterns for #{analysis_type}")
        {:ok, cached_patterns, agent}

      :miss ->
        case perform_fresh_analysis(agent, analysis_type, data_set, options) do
          {:ok, fresh_patterns, updated_agent} ->
            final_agent = cache_patterns(updated_agent, cache_key, fresh_patterns)
            {:ok, fresh_patterns, final_agent}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp perform_fresh_analysis(agent, analysis_type, data_set, options) do
    case analysis_type do
      :success_patterns ->
        analyze_success_patterns(agent, data_set, options)

      :failure_modes ->
        analyze_failure_modes(agent, data_set, options)

      :user_preferences ->
        analyze_user_preference_patterns(agent, data_set, options)

      :temporal_trends ->
        analyze_temporal_trends(agent, data_set, options)

      :judge_performance ->
        analyze_judge_performance_patterns(agent, data_set, options)

      :system_optimization ->
        analyze_system_optimization_patterns(agent, data_set, options)

      _ ->
        {:error, "Unsupported analysis type: #{analysis_type}"}
    end
  end

  # Specific pattern analysis implementations

  defp analyze_success_patterns(agent, data_set, options) do
    Logger.debug("Analyzing success patterns in #{length(data_set)} data points")

    case SuccessPatternAnalyzer.identify_success_patterns(data_set, options) do
      {:ok, success_patterns} ->
        pattern_result = %{
          analysis_type: :success_patterns,
          identified_patterns: success_patterns,
          confidence: calculate_pattern_confidence(success_patterns, :success_patterns),
          data_points_analyzed: length(data_set),
          pattern_metadata: %{
            analyzer: :success_pattern_analyzer,
            version: "1.0.0",
            analyzed_at: DateTime.utc_now()
          },
          actionable_insights: extract_success_insights(success_patterns),
          recommended_actions: generate_success_actions(success_patterns)
        }

        updated_agent = update_learning_model(agent, :success_patterns, pattern_result)
        {:ok, pattern_result, updated_agent}

      {:error, reason} ->
        {:error, "Success pattern analysis failed: #{reason}"}
    end
  end

  defp analyze_failure_modes(agent, data_set, options) do
    Logger.debug("Analyzing failure modes in #{length(data_set)} data points")

    case FailureModeDetector.detect_failure_patterns(data_set, options) do
      {:ok, failure_patterns} ->
        pattern_result = %{
          analysis_type: :failure_modes,
          identified_patterns: failure_patterns,
          confidence: calculate_pattern_confidence(failure_patterns, :failure_modes),
          data_points_analyzed: length(data_set),
          pattern_metadata: %{
            analyzer: :failure_mode_detector,
            version: "1.0.0",
            analyzed_at: DateTime.utc_now()
          },
          actionable_insights: extract_failure_insights(failure_patterns),
          recommended_actions: generate_failure_mitigation_actions(failure_patterns)
        }

        updated_agent = update_learning_model(agent, :failure_modes, pattern_result)
        {:ok, pattern_result, updated_agent}

      {:error, reason} ->
        {:error, "Failure mode analysis failed: #{reason}"}
    end
  end

  defp analyze_user_preference_patterns(agent, data_set, options) do
    Logger.debug("Analyzing user preference patterns in #{length(data_set)} data points")

    case UserPreferenceProfiler.profile_user_preferences(data_set, options) do
      {:ok, preference_patterns} ->
        pattern_result = %{
          analysis_type: :user_preferences,
          identified_patterns: preference_patterns,
          confidence: calculate_pattern_confidence(preference_patterns, :user_preferences),
          data_points_analyzed: length(data_set),
          pattern_metadata: %{
            analyzer: :user_preference_profiler,
            version: "1.0.0",
            analyzed_at: DateTime.utc_now()
          },
          actionable_insights: extract_preference_insights(preference_patterns),
          recommended_actions: generate_personalization_actions(preference_patterns)
        }

        updated_agent = update_learning_model(agent, :user_preferences, pattern_result)
        {:ok, pattern_result, updated_agent}

      {:error, reason} ->
        {:error, "User preference analysis failed: #{reason}"}
    end
  end

  defp analyze_temporal_trends(agent, data_set, options) do
    Logger.debug("Analyzing temporal trends in #{length(data_set)} data points")

    case TemporalTrendAnalyzer.analyze_trends(data_set, options) do
      {:ok, trend_patterns} ->
        pattern_result = %{
          analysis_type: :temporal_trends,
          identified_patterns: trend_patterns,
          confidence: calculate_pattern_confidence(trend_patterns, :temporal_trends),
          data_points_analyzed: length(data_set),
          pattern_metadata: %{
            analyzer: :temporal_trend_analyzer,
            version: "1.0.0",
            analyzed_at: DateTime.utc_now()
          },
          actionable_insights: extract_trend_insights(trend_patterns),
          recommended_actions: generate_trend_actions(trend_patterns)
        }

        updated_agent = update_learning_model(agent, :temporal_trends, pattern_result)
        {:ok, pattern_result, updated_agent}

      {:error, reason} ->
        {:error, "Temporal trend analysis failed: #{reason}"}
    end
  end

  defp analyze_judge_performance_patterns(agent, data_set, options) do
    Logger.debug("Analyzing judge performance patterns in #{length(data_set)} data points")

    case ComparativePerformanceAnalyzer.analyze_judge_performance(data_set, options) do
      {:ok, performance_patterns} ->
        pattern_result = %{
          analysis_type: :judge_performance,
          identified_patterns: performance_patterns,
          confidence: calculate_pattern_confidence(performance_patterns, :judge_performance),
          data_points_analyzed: length(data_set),
          pattern_metadata: %{
            analyzer: :comparative_performance_analyzer,
            version: "1.0.0",
            analyzed_at: DateTime.utc_now()
          },
          actionable_insights: extract_performance_insights(performance_patterns),
          recommended_actions: generate_performance_optimization_actions(performance_patterns)
        }

        updated_agent = update_learning_model(agent, :judge_performance, pattern_result)
        {:ok, pattern_result, updated_agent}

      {:error, reason} ->
        {:error, "Judge performance analysis failed: #{reason}"}
    end
  end

  defp analyze_system_optimization_patterns(agent, data_set, options) do
    Logger.debug("Analyzing system optimization patterns in #{length(data_set)} data points")

    # Multi-analyzer approach for comprehensive optimization analysis
    optimization_analyses = [
      {SuccessPatternAnalyzer, :identify_optimization_patterns},
      {FailureModeDetector, :detect_inefficiency_patterns},
      {ComparativePerformanceAnalyzer, :analyze_system_bottlenecks}
    ]

    analysis_results =
      Enum.map(optimization_analyses, fn {analyzer, method} ->
        apply(analyzer, method, [data_set, options])
      end)

    case consolidate_optimization_analysis(analysis_results) do
      {:ok, optimization_patterns} ->
        pattern_result = %{
          analysis_type: :system_optimization,
          identified_patterns: optimization_patterns,
          confidence: calculate_pattern_confidence(optimization_patterns, :system_optimization),
          data_points_analyzed: length(data_set),
          pattern_metadata: %{
            analyzer: :multi_analyzer_optimization,
            version: "1.0.0",
            analyzed_at: DateTime.utc_now(),
            analyzers_used: optimization_analyses
          },
          actionable_insights: extract_optimization_insights(optimization_patterns),
          recommended_actions: generate_system_optimization_actions(optimization_patterns)
        }

        updated_agent = update_learning_model(agent, :system_optimization, pattern_result)
        {:ok, pattern_result, updated_agent}

      {:error, reason} ->
        {:error, "System optimization analysis failed: #{reason}"}
    end
  end

  # Focused analysis helpers

  defp analyze_single_focus_area(agent, focus_area, data_context, options) do
    case focus_area do
      :judge_selection_optimization ->
        analyze_judge_selection_patterns(agent, data_context, options)

      :evaluation_quality_improvement ->
        analyze_evaluation_quality_patterns(agent, data_context, options)

      :cost_efficiency_optimization ->
        analyze_cost_efficiency_patterns(agent, data_context, options)

      :bias_pattern_detection ->
        analyze_bias_patterns(agent, data_context, options)

      _ ->
        {:error, "Unknown focus area: #{focus_area}"}
    end
  end

  defp analyze_judge_selection_patterns(agent, data_context, options) do
    # Analyze patterns in judge selection effectiveness
    selection_data = extract_judge_selection_data(data_context)

    case recognize_patterns(agent, :judge_performance, selection_data, options) do
      {:ok, patterns, updated_agent} ->
        focused_result = %{
          focus_area: :judge_selection_optimization,
          pattern_analysis: patterns,
          optimization_opportunities: identify_judge_selection_optimizations(patterns),
          confidence: patterns.confidence
        }

        {:ok, focused_result}

      {:error, reason, _agent} ->
        {:error, reason}
    end
  end

  defp analyze_evaluation_quality_patterns(agent, data_context, options) do
    # Analyze patterns in evaluation quality and accuracy
    quality_data = extract_evaluation_quality_data(data_context)

    case recognize_patterns(agent, :success_patterns, quality_data, options) do
      {:ok, patterns, updated_agent} ->
        focused_result = %{
          focus_area: :evaluation_quality_improvement,
          pattern_analysis: patterns,
          quality_improvement_opportunities: identify_quality_improvements(patterns),
          confidence: patterns.confidence
        }

        {:ok, focused_result}

      {:error, reason, _agent} ->
        {:error, reason}
    end
  end

  defp analyze_cost_efficiency_patterns(agent, data_context, options) do
    # Analyze patterns in cost efficiency and resource utilization
    cost_data = extract_cost_efficiency_data(data_context)

    case recognize_patterns(agent, :system_optimization, cost_data, options) do
      {:ok, patterns, updated_agent} ->
        focused_result = %{
          focus_area: :cost_efficiency_optimization,
          pattern_analysis: patterns,
          cost_optimization_opportunities: identify_cost_optimizations(patterns),
          confidence: patterns.confidence
        }

        {:ok, focused_result}

      {:error, reason, _agent} ->
        {:error, reason}
    end
  end

  defp analyze_bias_patterns(agent, data_context, options) do
    # Analyze patterns that might indicate bias in evaluations
    bias_data = extract_bias_indicator_data(data_context)

    case recognize_patterns(agent, :failure_modes, bias_data, options) do
      {:ok, patterns, updated_agent} ->
        focused_result = %{
          focus_area: :bias_pattern_detection,
          pattern_analysis: patterns,
          bias_mitigation_opportunities: identify_bias_mitigations(patterns),
          confidence: patterns.confidence
        }

        {:ok, focused_result}

      {:error, reason, _agent} ->
        {:error, reason}
    end
  end

  # Pattern analysis and caching helpers

  defp generate_cache_key(analysis_type, data_set, options) do
    data_hash = :crypto.hash(:sha256, :erlang.term_to_binary(data_set)) |> Base.encode16()
    options_hash = :crypto.hash(:sha256, :erlang.term_to_binary(options)) |> Base.encode16()

    "#{analysis_type}_#{String.slice(data_hash, 0..7)}_#{String.slice(options_hash, 0..7)}"
  end

  defp get_cached_patterns(agent, cache_key) do
    case Map.get(agent.state.pattern_cache, cache_key) do
      nil ->
        :miss

      cached_entry ->
        if cache_entry_valid?(cached_entry, agent.state.configuration.cache_retention_hours) do
          {:hit, cached_entry.patterns}
        else
          :miss
        end
    end
  end

  defp cache_patterns(agent, cache_key, patterns) do
    cache_entry = %{
      patterns: patterns,
      cached_at: DateTime.utc_now(),
      access_count: 1
    }

    updated_cache = Map.put(agent.state.pattern_cache, cache_key, cache_entry)
    %{agent | state: %{agent.state | pattern_cache: updated_cache}}
  end

  defp cache_entry_valid?(cache_entry, retention_hours) do
    hours_since_cached = DateTime.diff(DateTime.utc_now(), cache_entry.cached_at, :hour)
    hours_since_cached <= retention_hours
  end

  defp calculate_pattern_confidence(patterns, pattern_type) when is_map(patterns) do
    pattern_count = length(Map.get(patterns, :patterns, []))
    base_confidence = Map.get(@pattern_confidence_thresholds, pattern_type, 0.7)

    # More patterns generally mean higher confidence
    pattern_bonus = min(0.2, pattern_count / 10.0)

    # Pattern strength affects confidence
    strength_bonus = calculate_pattern_strength_bonus(patterns)

    min(1.0, base_confidence + pattern_bonus + strength_bonus)
  end

  defp calculate_pattern_confidence(patterns, _pattern_type) when is_list(patterns) do
    if Enum.empty?(patterns) do
      0.0
    else
      # Average confidence of individual patterns
      confidences =
        Enum.map(patterns, fn pattern ->
          Map.get(pattern, :confidence, 0.7)
        end)

      Enum.sum(confidences) / length(confidences)
    end
  end

  defp calculate_pattern_confidence(_patterns, _pattern_type), do: 0.5

  defp calculate_pattern_strength_bonus(patterns) do
    # Calculate bonus based on pattern strength indicators
    pattern_list = Map.get(patterns, :patterns, [])

    if Enum.empty?(pattern_list) do
      0.0
    else
      average_strength =
        Enum.reduce(pattern_list, 0.0, fn pattern, acc ->
          strength = Map.get(pattern, :strength, 0.5)
          acc + strength
        end) / length(pattern_list)

      # Convert strength to confidence bonus
      min(0.15, average_strength * 0.2)
    end
  end

  # Learning model management

  defp update_learning_model(agent, model_type, pattern_result) do
    current_models = agent.state.learning_models

    updated_model =
      case Map.get(current_models, model_type) do
        nil ->
          initialize_pattern_model(model_type, pattern_result)

        existing_model ->
          update_existing_pattern_model(existing_model, pattern_result)
      end

    updated_models = Map.put(current_models, model_type, updated_model)
    %{agent | state: %{agent.state | learning_models: updated_models}}
  end

  defp initialize_pattern_model(model_type, pattern_result) do
    %{
      model_type: model_type,
      created_at: DateTime.utc_now(),
      update_count: 1,
      latest_patterns: pattern_result.identified_patterns,
      confidence_history: [pattern_result.confidence],
      average_confidence: pattern_result.confidence,
      pattern_evolution: [
        %{
          timestamp: DateTime.utc_now(),
          pattern_count: length(pattern_result.identified_patterns),
          confidence: pattern_result.confidence
        }
      ]
    }
  end

  defp update_existing_pattern_model(existing_model, pattern_result) do
    new_confidence_history = [
      pattern_result.confidence | Enum.take(existing_model.confidence_history, 9)
    ]

    new_average_confidence = Enum.sum(new_confidence_history) / length(new_confidence_history)

    new_evolution_entry = %{
      timestamp: DateTime.utc_now(),
      pattern_count: length(pattern_result.identified_patterns),
      confidence: pattern_result.confidence
    }

    %{
      existing_model
      | update_count: existing_model.update_count + 1,
        latest_patterns: pattern_result.identified_patterns,
        confidence_history: new_confidence_history,
        average_confidence: new_average_confidence,
        pattern_evolution: [new_evolution_entry | Enum.take(existing_model.pattern_evolution, 19)],
        last_updated: DateTime.utc_now()
    }
  end

  # Performance tracking

  defp update_analysis_metrics(agent, pattern_result, analysis_time_ms) do
    current_metrics = agent.state.performance_metrics

    new_pattern_count =
      current_metrics.patterns_identified + length(pattern_result.identified_patterns)

    new_avg_time =
      (current_metrics.analysis_time_avg * current_metrics.patterns_identified + analysis_time_ms) /
        new_pattern_count

    updated_metrics = %{
      patterns_identified: new_pattern_count,
      analysis_time_avg: new_avg_time,
      # Would be updated based on validation
      pattern_accuracy_rate: current_metrics.pattern_accuracy_rate,
      model_update_count: current_metrics.model_update_count + 1
    }

    # Add to analysis history
    history_entry = %{
      analysis_type: pattern_result.analysis_type,
      timestamp: DateTime.utc_now(),
      patterns_found: length(pattern_result.identified_patterns),
      confidence: pattern_result.confidence,
      analysis_time_ms: analysis_time_ms
    }

    updated_history = [history_entry | Enum.take(agent.state.analysis_history, 49)]

    %{
      agent
      | state: %{
          agent.state
          | performance_metrics: updated_metrics,
            analysis_history: updated_history
        }
    }
  end

  # Analysis combination and consolidation

  defp combine_focused_analyses(successful_analyses) do
    combined_patterns =
      Enum.flat_map(successful_analyses, fn {:ok, analysis} ->
        Map.get(analysis, :identified_patterns, [])
      end)

    combined_insights =
      Enum.flat_map(successful_analyses, fn {:ok, analysis} ->
        Map.get(analysis, :actionable_insights, [])
      end)

    combined_actions =
      Enum.flat_map(successful_analyses, fn {:ok, analysis} ->
        Map.get(analysis, :recommended_actions, [])
      end)

    average_confidence = calculate_average_confidence_from_analyses(successful_analyses)

    %{
      analysis_type: :multi_focus_analysis,
      identified_patterns: combined_patterns,
      confidence: average_confidence,
      actionable_insights: deduplicate_insights(combined_insights),
      recommended_actions: deduplicate_actions(combined_actions),
      focus_areas_analyzed: length(successful_analyses),
      combined_at: DateTime.utc_now()
    }
  end

  defp consolidate_optimization_analysis(analysis_results) do
    successful_results = Enum.filter(analysis_results, &match?({:ok, _}, &1))

    if Enum.empty?(successful_results) do
      {:error, "All optimization analyses failed"}
    else
      consolidated_patterns =
        Enum.flat_map(successful_results, fn {:ok, result} ->
          Map.get(result, :patterns, [])
        end)

      {:ok,
       %{
         patterns: consolidated_patterns,
         analysis_count: length(successful_results),
         consolidation_confidence: calculate_consolidation_confidence(successful_results)
       }}
    end
  end

  defp record_focused_analysis_success(agent, focus_areas, combined_patterns) do
    # Record successful focused analysis in agent state
    success_record = %{
      focus_areas: focus_areas,
      patterns_found: length(combined_patterns.identified_patterns),
      confidence: combined_patterns.confidence,
      analyzed_at: DateTime.utc_now()
    }

    updated_history = [success_record | Enum.take(agent.state.analysis_history, 29)]
    %{agent | state: %{agent.state | analysis_history: updated_history}}
  end

  # Cache analysis and management

  defp analyze_pattern_cache(pattern_cache) do
    total_entries = map_size(pattern_cache)

    if total_entries == 0 do
      %{total_cached: 0, hit_rate: 0.0, average_age_hours: 0.0}
    else
      cache_entries = Map.values(pattern_cache)

      total_access_count = Enum.sum(Enum.map(cache_entries, & &1.access_count))

      hit_rate =
        if total_access_count > 0,
          do: (total_access_count - total_entries) / total_access_count,
          else: 0.0

      average_age_hours =
        Enum.reduce(cache_entries, 0.0, fn entry, acc ->
          hours_old = DateTime.diff(DateTime.utc_now(), entry.cached_at, :hour)
          acc + hours_old
        end) / total_entries

      %{
        total_cached: total_entries,
        hit_rate: max(0.0, hit_rate),
        average_age_hours: average_age_hours
      }
    end
  end

  # Insight and action extraction helpers

  defp extract_success_insights(success_patterns) when is_map(success_patterns) do
    patterns = Map.get(success_patterns, :patterns, [])

    Enum.map(patterns, fn pattern ->
      %{
        insight_type: :success_factor,
        pattern_description: Map.get(pattern, :description, "Success pattern identified"),
        confidence: Map.get(pattern, :confidence, 0.7),
        impact_potential: assess_success_impact_potential(pattern),
        replication_difficulty: assess_replication_difficulty(pattern)
      }
    end)
  end

  defp extract_success_insights(_), do: []

  defp generate_success_actions(success_patterns) when is_map(success_patterns) do
    patterns = Map.get(success_patterns, :patterns, [])

    base_actions = ["reinforce_successful_patterns", "replicate_winning_strategies"]

    pattern_specific_actions =
      Enum.flat_map(patterns, fn pattern ->
        case Map.get(pattern, :type) do
          :judge_coordination -> ["optimize_judge_coordination", "improve_consensus_mechanisms"]
          :evaluation_efficiency -> ["enhance_evaluation_speed", "optimize_resource_usage"]
          :user_satisfaction -> ["maintain_quality_standards", "preserve_user_experience"]
          _ -> []
        end
      end)

    base_actions ++ pattern_specific_actions
  end

  defp generate_success_actions(_), do: ["monitor_for_success_patterns"]

  defp extract_failure_insights(failure_patterns) when is_map(failure_patterns) do
    patterns = Map.get(failure_patterns, :patterns, [])

    Enum.map(patterns, fn pattern ->
      %{
        insight_type: :failure_indicator,
        failure_mode: Map.get(pattern, :mode, "Failure pattern detected"),
        severity: assess_failure_severity(pattern),
        frequency: Map.get(pattern, :frequency, :unknown),
        mitigation_priority: calculate_mitigation_priority(pattern)
      }
    end)
  end

  defp extract_failure_insights(_), do: []

  defp generate_failure_mitigation_actions(failure_patterns) when is_map(failure_patterns) do
    patterns = Map.get(failure_patterns, :patterns, [])

    high_severity_patterns =
      Enum.filter(patterns, fn pattern ->
        assess_failure_severity(pattern) in [:high, :critical]
      end)

    base_actions = ["investigate_failure_root_causes", "implement_failure_prevention"]

    severity_actions =
      if length(high_severity_patterns) > 0 do
        ["urgent_failure_mitigation", "immediate_system_review"]
      else
        ["routine_failure_monitoring", "gradual_improvement"]
      end

    base_actions ++ severity_actions
  end

  defp generate_failure_mitigation_actions(_), do: ["monitor_for_failure_patterns"]

  # Pattern-specific insight extraction (stubs for full implementation)

  defp extract_preference_insights(_patterns),
    do: [%{insight: :user_preference_detected, action: :personalize_experience}]

  defp extract_trend_insights(_patterns),
    do: [%{insight: :temporal_trend_detected, action: :adjust_temporal_strategy}]

  defp extract_performance_insights(_patterns),
    do: [%{insight: :performance_pattern_detected, action: :optimize_judge_selection}]

  defp extract_optimization_insights(_patterns),
    do: [%{insight: :optimization_opportunity, action: :implement_optimization}]

  defp generate_personalization_actions(_patterns),
    do: ["personalize_user_experience", "adapt_evaluation_flow"]

  defp generate_trend_actions(_patterns),
    do: ["adapt_to_temporal_trends", "optimize_time_based_strategies"]

  defp generate_performance_optimization_actions(_patterns),
    do: ["optimize_judge_performance", "improve_coordination"]

  defp generate_system_optimization_actions(_patterns),
    do: ["optimize_system_performance", "enhance_resource_utilization"]

  # Data extraction helpers for focused analysis

  defp extract_judge_selection_data(data_context),
    do: Map.get(data_context, :judge_selection_history, [])

  defp extract_evaluation_quality_data(data_context),
    do: Map.get(data_context, :evaluation_results, [])

  defp extract_cost_efficiency_data(data_context),
    do: Map.get(data_context, :cost_performance_data, [])

  defp extract_bias_indicator_data(data_context),
    do: Map.get(data_context, :evaluation_fairness_data, [])

  # Optimization opportunity identification

  defp identify_judge_selection_optimizations(_patterns),
    do: ["improve_routing_algorithm", "enhance_specialization_matching"]

  defp identify_quality_improvements(_patterns),
    do: ["refine_evaluation_criteria", "enhance_scoring_accuracy"]

  defp identify_cost_optimizations(_patterns),
    do: ["reduce_computational_overhead", "optimize_resource_allocation"]

  defp identify_bias_mitigations(_patterns),
    do: ["implement_bias_detection", "enhance_fairness_monitoring"]

  # Calculation helpers

  defp calculate_average_confidence_from_analyses(analyses) do
    confidences =
      Enum.map(analyses, fn {:ok, analysis} ->
        Map.get(analysis, :confidence, 0.5)
      end)

    if Enum.empty?(confidences) do
      0.0
    else
      Enum.sum(confidences) / length(confidences)
    end
  end

  defp calculate_consolidation_confidence(successful_results) do
    if Enum.empty?(successful_results) do
      0.0
    else
      # Base confidence reduced for consolidation uncertainty
      base_confidence = 0.6

      # More successful results increase confidence
      result_bonus = min(0.3, length(successful_results) / 5.0)

      base_confidence + result_bonus
    end
  end

  defp deduplicate_insights(insights) do
    # Remove duplicate insights based on type and content
    Enum.uniq_by(insights, fn insight ->
      {Map.get(insight, :insight_type), Map.get(insight, :pattern_description)}
    end)
  end

  defp deduplicate_actions(actions) do
    # Remove duplicate actions
    Enum.uniq(actions)
  end

  # Assessment helpers (stubs for comprehensive implementation)

  defp assess_success_impact_potential(_pattern), do: :high
  defp assess_replication_difficulty(_pattern), do: :medium
  defp assess_failure_severity(_pattern), do: :medium
  defp calculate_mitigation_priority(_pattern), do: :high
end
