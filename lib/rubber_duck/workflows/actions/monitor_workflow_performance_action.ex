defmodule RubberDuck.Workflows.Actions.MonitorWorkflowPerformanceAction do
  @moduledoc """
  Workflow performance monitoring action for analytics and optimization.

  This action provides comprehensive monitoring and analytics for workflow
  performance, enabling agents to make data-driven decisions about workflow
  adoption and optimization strategies.

  Features:
  - Real-time workflow performance monitoring with detailed metrics collection
  - Comparative analysis between autonomous and workflow execution strategies
  - Agent adoption pattern tracking with trend analysis and insights
  - Template effectiveness measurement with optimization recommendations
  - System health assessment with actionable performance guidance
  - Integration with existing monitoring infrastructure and telemetry systems

  Monitoring Dimensions:
  - **Execution Performance**: Time, success rate, resource usage
  - **Adoption Patterns**: Which agents adopt workflows and effectiveness
  - **Template Analytics**: Template usage patterns and effectiveness
  - **System Health**: Overall system impact of workflow adoption
  """

  use Jido.Action,
    name: "monitor_workflow_performance",
    schema: [
      monitoring_scope: [
        type: :atom,
        default: :system_wide,
        doc: "Monitoring scope (:system_wide, :agent_specific, :template_specific)"
      ],
      target_identifier: [type: :string, doc: "Target identifier (agent module or template name)"],
      monitoring_period: [type: :integer, default: 3600, doc: "Monitoring period in seconds"],
      analytics_config: [type: :map, default: %{}, doc: "Analytics configuration"],
      context: [type: :map, default: %{}, doc: "Monitoring context"]
    ]

  require Logger

  alias RubberDuck.Workflows.WorkflowMonitor

  @monitoring_scopes [:system_wide, :agent_specific, :template_specific, :adoption_analysis]

  @default_analytics_config %{
    include_performance_trends: true,
    include_adoption_patterns: true,
    include_template_effectiveness: true,
    include_system_health: true,
    enable_recommendations: true,
    detail_level: :comprehensive
  }

  @doc """
  Monitor workflow performance with comprehensive analytics and insights.

  Returns monitoring result with performance metrics, adoption analytics,
  and optimization recommendations for agent decision-making.
  """
  def run(params, _context) do
    %{
      monitoring_scope: scope,
      target_identifier: target_id,
      monitoring_period: period,
      analytics_config: analytics_config,
      context: monitoring_context
    } = params

    merged_analytics_config = Map.merge(@default_analytics_config, analytics_config)

    Logger.info("MonitorWorkflowPerformanceAction: Starting performance monitoring",
      scope: scope,
      target: target_id,
      period_seconds: period
    )

    monitoring_start_time = System.monotonic_time(:microsecond)

    with {:ok, validated_scope} <- validate_monitoring_scope(scope, target_id),
         {:ok, monitoring_data} <-
           collect_monitoring_data(validated_scope, period, merged_analytics_config),
         {:ok, analytics_result} <-
           perform_analytics_analysis(monitoring_data, merged_analytics_config),
         {:ok, recommendations} <-
           generate_monitoring_recommendations(analytics_result, monitoring_context) do
      monitoring_time = System.monotonic_time(:microsecond) - monitoring_start_time

      Logger.info("MonitorWorkflowPerformanceAction: Performance monitoring completed",
        scope: scope,
        monitoring_time_us: monitoring_time,
        insights_generated: length(recommendations)
      )

      {:ok,
       %{
         monitoring_data: monitoring_data,
         analytics_result: analytics_result,
         recommendations: recommendations,
         monitoring_metadata: %{
           monitoring_time_microseconds: monitoring_time,
           scope: validated_scope,
           period_analyzed: period,
           analytics_config: merged_analytics_config
         }
       }}
    else
      {:error, reason} ->
        Logger.error("MonitorWorkflowPerformanceAction: Performance monitoring failed",
          error: reason,
          scope: scope
        )

        {:error, reason}
    end
  end

  # Private implementation functions

  defp validate_monitoring_scope(scope, target_id) do
    Logger.debug("MonitorWorkflowPerformanceAction: Validating monitoring scope",
      scope: scope,
      target: target_id
    )

    if scope in @monitoring_scopes do
      validate_scope_with_target(scope, target_id)
    else
      {:error, {:invalid_monitoring_scope, scope}}
    end
  end

  defp validate_scope_with_target(scope, target_id) do
    case scope do
      scope when scope in [:agent_specific, :template_specific] ->
        if target_id do
          {:ok, %{scope: scope, target: target_id, validated: true}}
        else
          {:error, {:target_required_for_scope, scope}}
        end

      scope when scope in [:system_wide, :adoption_analysis] ->
        {:ok, %{scope: scope, target: :all, validated: true}}

      _ ->
        {:error, {:unsupported_scope, scope}}
    end
  end

  defp collect_monitoring_data(validated_scope, period, analytics_config) do
    Logger.debug("MonitorWorkflowPerformanceAction: Collecting monitoring data")

    case validated_scope.scope do
      :system_wide ->
        collect_system_wide_data(period, analytics_config)

      :agent_specific ->
        collect_agent_specific_data(validated_scope.target, period, analytics_config)

      :template_specific ->
        collect_template_specific_data(validated_scope.target, period, analytics_config)

      :adoption_analysis ->
        collect_adoption_analysis_data(period, analytics_config)
    end
  end

  defp collect_system_wide_data(period, analytics_config) do
    # Collect system-wide monitoring data
    with {:ok, adoption_stats} <- WorkflowMonitor.get_adoption_statistics(),
         {:ok, performance_comparison} <- WorkflowMonitor.get_performance_comparison(:all),
         {:ok, template_effectiveness} <- WorkflowMonitor.get_template_effectiveness() do
      monitoring_data = %{
        scope: :system_wide,
        period: period,
        adoption_statistics: adoption_stats,
        performance_comparison: performance_comparison,
        template_effectiveness: template_effectiveness,
        collected_at: DateTime.utc_now()
      }

      {:ok, monitoring_data}
    else
      {:error, reason} when is_atom(reason) ->
        {:error, {:adoption_statistics_failed, reason}}

      {:error, reason} ->
        {:error, {:monitoring_data_collection_failed, reason}}
    end
  end

  defp collect_agent_specific_data(agent_module, period, analytics_config) do
    # Collect agent-specific monitoring data
    agent_atom =
      if is_binary(agent_module), do: String.to_existing_atom(agent_module), else: agent_module

    case WorkflowMonitor.get_performance_comparison(agent_atom) do
      {:ok, performance_data} ->
        case WorkflowMonitor.get_adoption_recommendations(agent_atom) do
          {:ok, recommendations} ->
            monitoring_data = %{
              scope: :agent_specific,
              agent_module: agent_atom,
              period: period,
              performance_data: performance_data,
              adoption_recommendations: recommendations,
              collected_at: DateTime.utc_now()
            }

            {:ok, monitoring_data}

          {:error, reason} ->
            {:error, {:adoption_recommendations_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:agent_performance_data_failed, reason}}
    end
  end

  defp collect_template_specific_data(template_name, period, analytics_config) do
    # Collect template-specific monitoring data
    case WorkflowMonitor.get_template_effectiveness() do
      {:ok, template_effectiveness} ->
        template_atom =
          if is_binary(template_name),
            do: String.to_existing_atom(template_name),
            else: template_name

        template_data = Map.get(template_effectiveness.template_statistics, template_atom, %{})

        monitoring_data = %{
          scope: :template_specific,
          template_name: template_atom,
          period: period,
          template_data: template_data,
          overall_effectiveness: template_effectiveness.overall_effectiveness,
          collected_at: DateTime.utc_now()
        }

        {:ok, monitoring_data}

      {:error, reason} ->
        {:error, {:template_data_collection_failed, reason}}
    end
  end

  defp collect_adoption_analysis_data(period, analytics_config) do
    # Collect comprehensive adoption analysis data
    case WorkflowMonitor.get_adoption_statistics() do
      {:ok, adoption_stats} ->
        monitoring_data = %{
          scope: :adoption_analysis,
          period: period,
          adoption_statistics: adoption_stats,
          adoption_trends: adoption_stats.adoption_trends,
          top_adopting_agents: adoption_stats.top_adopting_agents,
          collected_at: DateTime.utc_now()
        }

        {:ok, monitoring_data}

      {:error, reason} ->
        {:error, {:adoption_analysis_failed, reason}}
    end
  end

  defp perform_analytics_analysis(monitoring_data, analytics_config) do
    Logger.debug("MonitorWorkflowPerformanceAction: Performing analytics analysis")

    analytics_result = %{
      scope: monitoring_data.scope,
      analysis_timestamp: DateTime.utc_now()
    }

    # Add scope-specific analytics
    enhanced_result =
      case monitoring_data.scope do
        :system_wide ->
          add_system_wide_analytics(analytics_result, monitoring_data, analytics_config)

        :agent_specific ->
          add_agent_specific_analytics(analytics_result, monitoring_data, analytics_config)

        :template_specific ->
          add_template_specific_analytics(analytics_result, monitoring_data, analytics_config)

        :adoption_analysis ->
          add_adoption_analytics(analytics_result, monitoring_data, analytics_config)
      end

    {:ok, enhanced_result}
  end

  defp add_system_wide_analytics(result, monitoring_data, config) do
    analytics = %{}

    # Performance trends analysis
    analytics =
      if config.include_performance_trends do
        performance_trends = analyze_performance_trends(monitoring_data.performance_comparison)
        Map.put(analytics, :performance_trends, performance_trends)
      else
        analytics
      end

    # Adoption patterns analysis
    analytics =
      if config.include_adoption_patterns do
        adoption_patterns = analyze_adoption_patterns(monitoring_data.adoption_statistics)
        Map.put(analytics, :adoption_patterns, adoption_patterns)
      else
        analytics
      end

    # Template effectiveness analysis
    analytics =
      if config.include_template_effectiveness do
        template_analysis = analyze_template_effectiveness(monitoring_data.template_effectiveness)
        Map.put(analytics, :template_effectiveness, template_analysis)
      else
        analytics
      end

    # System health analysis
    analytics =
      if config.include_system_health do
        health_analysis = analyze_system_health(monitoring_data)
        Map.put(analytics, :system_health, health_analysis)
      else
        analytics
      end

    Map.put(result, :analytics, analytics)
  end

  defp add_agent_specific_analytics(result, monitoring_data, config) do
    agent_analytics = %{
      agent_module: monitoring_data.agent_module,
      performance_analysis: analyze_agent_performance(monitoring_data.performance_data),
      adoption_insights: analyze_agent_adoption_insights(monitoring_data),
      optimization_opportunities: identify_agent_optimization_opportunities(monitoring_data)
    }

    Map.put(result, :agent_analytics, agent_analytics)
  end

  defp add_template_specific_analytics(result, monitoring_data, config) do
    template_analytics = %{
      template_name: monitoring_data.template_name,
      usage_analysis: analyze_template_usage(monitoring_data.template_data),
      effectiveness_score: calculate_template_effectiveness_score(monitoring_data.template_data),
      optimization_recommendations:
        generate_template_optimization_recommendations(monitoring_data.template_data)
    }

    Map.put(result, :template_analytics, template_analytics)
  end

  defp add_adoption_analytics(result, monitoring_data, config) do
    adoption_analytics = %{
      overall_adoption_rate: monitoring_data.adoption_statistics.average_adoption_rate,
      adoption_trend: monitoring_data.adoption_trends.trend,
      top_adopters: monitoring_data.top_adopting_agents,
      adoption_insights: analyze_adoption_insights(monitoring_data.adoption_statistics)
    }

    Map.put(result, :adoption_analytics, adoption_analytics)
  end

  # Analytics helper functions

  defp analyze_performance_trends(performance_comparison) do
    # Analyze performance trends from comparison data
    if Map.has_key?(performance_comparison.performance_improvement, :insufficient_data) do
      %{
        trend: :insufficient_data,
        message: "Insufficient performance data for trend analysis"
      }
    else
      improvement = performance_comparison.performance_improvement

      %{
        trend: determine_performance_trend(improvement),
        time_improvement: improvement.time_improvement,
        success_improvement: improvement.success_rate_improvement,
        overall_improvement: improvement.overall_performance_improvement,
        workflow_preferred: improvement.workflow_preferred
      }
    end
  end

  defp determine_performance_trend(improvement) do
    overall = improvement.overall_performance_improvement

    cond do
      overall > 0.2 -> :strongly_positive
      overall > 0.1 -> :positive
      overall > -0.1 -> :neutral
      overall > -0.2 -> :negative
      true -> :strongly_negative
    end
  end

  defp analyze_adoption_patterns(adoption_statistics) do
    # Analyze agent adoption patterns
    %{
      total_agents: adoption_statistics.total_agents_monitored,
      adopting_agents: adoption_statistics.agents_using_workflows,
      adoption_percentage: adoption_statistics.workflow_adoption_percentage,
      average_adoption_rate: adoption_statistics.average_adoption_rate,
      adoption_health: assess_adoption_health(adoption_statistics.workflow_adoption_percentage)
    }
  end

  defp assess_adoption_health(adoption_percentage) do
    cond do
      adoption_percentage > 0.6 -> :high_adoption
      adoption_percentage > 0.3 -> :moderate_adoption
      adoption_percentage > 0.1 -> :low_adoption
      true -> :minimal_adoption
    end
  end

  defp analyze_template_effectiveness(template_effectiveness) do
    # Analyze template system effectiveness
    %{
      overall_effectiveness: template_effectiveness.overall_effectiveness,
      most_effective: template_effectiveness.most_effective_template,
      least_effective: template_effectiveness.least_effective_template,
      template_count: map_size(template_effectiveness.template_statistics),
      effectiveness_distribution:
        calculate_effectiveness_distribution(template_effectiveness.template_statistics)
    }
  end

  defp calculate_effectiveness_distribution(template_stats) do
    if map_size(template_stats) > 0 do
      effectiveness_scores =
        template_stats
        |> Map.values()
        |> Enum.map(&Map.get(&1, :effectiveness_score, 0.0))

      %{
        min_effectiveness: Enum.min(effectiveness_scores),
        max_effectiveness: Enum.max(effectiveness_scores),
        avg_effectiveness: Enum.sum(effectiveness_scores) / length(effectiveness_scores),
        effectiveness_range: Enum.max(effectiveness_scores) - Enum.min(effectiveness_scores)
      }
    else
      %{
        min_effectiveness: 0.0,
        max_effectiveness: 0.0,
        avg_effectiveness: 0.0,
        effectiveness_range: 0.0
      }
    end
  end

  defp analyze_system_health(monitoring_data) do
    # Analyze overall system health
    adoption_stats = monitoring_data.adoption_statistics
    performance_comp = monitoring_data.performance_comparison

    health_factors = []

    # Adoption health
    adoption_health = assess_adoption_health(adoption_stats.workflow_adoption_percentage)
    health_factors = [adoption_health | health_factors]

    # Performance health
    performance_health =
      if Map.has_key?(performance_comp.performance_improvement, :insufficient_data) do
        :unknown
      else
        if performance_comp.performance_improvement.workflow_preferred do
          :positive
        else
          :neutral
        end
      end

    health_factors = [performance_health | health_factors]

    overall_health = determine_overall_health(health_factors)

    %{
      overall_health: overall_health,
      health_factors: health_factors,
      adoption_health: adoption_health,
      performance_health: performance_health,
      system_recommendations:
        generate_system_health_recommendations(overall_health, health_factors)
    }
  end

  defp determine_overall_health(health_factors) do
    positive_factors =
      Enum.count(health_factors, &(&1 in [:high_adoption, :moderate_adoption, :positive]))

    total_factors = length(health_factors)

    if total_factors > 0 do
      health_ratio = positive_factors / total_factors

      cond do
        health_ratio >= 0.8 -> :excellent
        health_ratio >= 0.6 -> :good
        health_ratio >= 0.4 -> :fair
        true -> :poor
      end
    else
      :unknown
    end
  end

  defp analyze_agent_performance(performance_data) do
    # Analyze specific agent performance
    if Map.has_key?(performance_data.performance_improvement, :insufficient_data) do
      %{
        analysis_status: :insufficient_data,
        message: "Insufficient performance data for agent analysis"
      }
    else
      improvement = performance_data.performance_improvement

      %{
        analysis_status: :complete,
        performance_score: calculate_agent_performance_score(improvement),
        workflow_effectiveness: improvement.workflow_preferred,
        time_efficiency: improvement.time_improvement,
        success_efficiency: improvement.success_rate_improvement,
        recommendation: generate_agent_performance_recommendation(improvement)
      }
    end
  end

  defp calculate_agent_performance_score(improvement) do
    # Calculate overall performance score for agent
    time_score = min(max(improvement.time_improvement, -1.0), 1.0) * 0.4
    success_score = min(max(improvement.success_rate_improvement, -1.0), 1.0) * 0.3
    overall_score = min(max(improvement.overall_performance_improvement, -1.0), 1.0) * 0.3

    total_score = time_score + success_score + overall_score
    Float.round(total_score, 3)
  end

  defp generate_agent_performance_recommendation(improvement) do
    cond do
      improvement.overall_performance_improvement > 0.15 ->
        "Strong workflow performance - recommend increased adoption"

      improvement.overall_performance_improvement > 0.05 ->
        "Moderate workflow benefits - continue selective adoption"

      improvement.overall_performance_improvement < -0.1 ->
        "Autonomous execution performing better - reduce workflow usage"

      true ->
        "Similar performance - continue current approach with monitoring"
    end
  end

  defp analyze_agent_adoption_insights(monitoring_data) do
    # Analyze agent adoption insights
    recommendations = monitoring_data.adoption_recommendations

    %{
      recommendation_count: length(recommendations),
      primary_recommendation: List.first(recommendations),
      adoption_guidance: classify_adoption_guidance(recommendations)
    }
  end

  defp classify_adoption_guidance(recommendations) do
    primary_rec = List.first(recommendations) || ""

    cond do
      String.contains?(primary_rec, "increase") or String.contains?(primary_rec, "recommend") ->
        :increase_adoption

      String.contains?(primary_rec, "reduce") or String.contains?(primary_rec, "autonomous") ->
        :reduce_adoption

      String.contains?(primary_rec, "continue") or String.contains?(primary_rec, "monitor") ->
        :maintain_current

      true ->
        :insufficient_guidance
    end
  end

  defp identify_agent_optimization_opportunities(monitoring_data) do
    # Identify optimization opportunities for agent
    performance_data = monitoring_data.performance_data

    opportunities = []

    opportunities =
      if Map.has_key?(performance_data.performance_improvement, :time_improvement) do
        time_improvement = performance_data.performance_improvement.time_improvement

        if time_improvement < -0.1 do
          ["Optimize workflow execution time - autonomous is faster" | opportunities]
        else
          opportunities
        end
      else
        opportunities
      end

    opportunities =
      if Map.has_key?(performance_data, :adoption_pattern) do
        adoption_rate = Map.get(performance_data.adoption_pattern, :adoption_rate, 0.0)

        cond do
          adoption_rate < 0.1 ->
            ["Consider workflow adoption for complex operations" | opportunities]

          adoption_rate > 0.8 ->
            ["Monitor for over-reliance on workflows" | opportunities]

          true ->
            opportunities
        end
      else
        opportunities
      end

    if Enum.empty?(opportunities) do
      ["No specific optimization opportunities identified"]
    else
      Enum.reverse(opportunities)
    end
  end

  defp analyze_template_usage(template_data) do
    # Analyze template usage patterns
    if map_size(template_data) > 0 do
      %{
        usage_count: Map.get(template_data, :usage_count, 0),
        success_rate: Map.get(template_data, :success_rate, 0.0),
        avg_execution_time: Map.get(template_data, :avg_execution_time, 0.0),
        effectiveness_score: Map.get(template_data, :effectiveness_score, 0.0),
        usage_health: assess_template_usage_health(template_data)
      }
    else
      %{
        usage_count: 0,
        success_rate: 0.0,
        avg_execution_time: 0.0,
        effectiveness_score: 0.0,
        usage_health: :no_usage_data
      }
    end
  end

  defp assess_template_usage_health(template_data) do
    usage_count = Map.get(template_data, :usage_count, 0)
    success_rate = Map.get(template_data, :success_rate, 0.0)
    effectiveness = Map.get(template_data, :effectiveness_score, 0.0)

    metrics = %{
      usage_count: usage_count,
      success_rate: success_rate,
      effectiveness: effectiveness
    }

    cond do
      excellent_template?(metrics) -> :excellent
      good_template?(metrics) -> :good
      fair_template?(metrics) -> :fair
      has_usage?(metrics) -> :poor
      true -> :no_usage
    end
  end

  defp excellent_template?(%{usage_count: usage, success_rate: success, effectiveness: eff}) do
    usage > 10 and success > 0.8 and eff > 0.7
  end

  defp good_template?(%{usage_count: usage, success_rate: success, effectiveness: eff}) do
    usage > 5 and success > 0.6 and eff > 0.5
  end

  defp fair_template?(%{usage_count: usage, success_rate: success}) do
    usage > 0 and success > 0.4
  end

  defp has_usage?(%{usage_count: usage}) do
    usage > 0
  end

  defp calculate_template_effectiveness_score(template_data) do
    if map_size(template_data) > 0 do
      Map.get(template_data, :effectiveness_score, 0.0)
    else
      0.0
    end
  end

  defp generate_template_optimization_recommendations(template_data) do
    if map_size(template_data) == 0 do
      ["No usage data available for optimization recommendations"]
    else
      usage_health = assess_template_usage_health(template_data)

      case usage_health do
        :excellent ->
          ["Template performing excellently - consider as model for other templates"]

        :good ->
          ["Template performing well - monitor for continued effectiveness"]

        :fair ->
          ["Template showing moderate performance - investigate optimization opportunities"]

        :poor ->
          ["Template underperforming - review implementation and usage patterns"]

        :no_usage ->
          ["Template not being used - consider promotion or retirement"]
      end
    end
  end

  defp generate_monitoring_recommendations(analytics_result, context) do
    Logger.debug("MonitorWorkflowPerformanceAction: Generating monitoring recommendations")

    recommendations = []

    # Add scope-specific recommendations
    recommendations =
      case analytics_result.scope do
        :system_wide ->
          add_system_wide_recommendations(recommendations, analytics_result)

        :agent_specific ->
          add_agent_specific_recommendations(recommendations, analytics_result)

        :template_specific ->
          add_template_specific_recommendations(recommendations, analytics_result)

        :adoption_analysis ->
          add_adoption_recommendations(recommendations, analytics_result)
      end

    # Add context-specific recommendations
    final_recommendations = add_context_recommendations(recommendations, context)

    {:ok, final_recommendations}
  end

  defp add_system_wide_recommendations(recommendations, analytics_result) do
    system_health = get_in(analytics_result, [:analytics, :system_health, :overall_health])

    case system_health do
      :excellent ->
        ["System workflow health is excellent - continue current approach" | recommendations]

      :good ->
        ["System performing well - monitor for optimization opportunities" | recommendations]

      :fair ->
        ["System showing mixed results - investigate underperforming areas" | recommendations]

      :poor ->
        [
          "System workflow adoption needs attention - review implementation strategy"
          | recommendations
        ]

      _ ->
        ["Continue monitoring system performance and adoption patterns" | recommendations]
    end
  end

  defp add_agent_specific_recommendations(recommendations, analytics_result) do
    agent_performance =
      get_in(analytics_result, [:agent_analytics, :performance_analysis, :recommendation])

    if agent_performance do
      [agent_performance | recommendations]
    else
      ["Continue monitoring agent performance for optimization insights" | recommendations]
    end
  end

  defp add_template_specific_recommendations(recommendations, analytics_result) do
    template_recs = get_in(analytics_result, [:template_analytics, :optimization_recommendations])

    if template_recs and not Enum.empty?(template_recs) do
      template_recs ++ recommendations
    else
      ["Continue monitoring template usage for optimization opportunities" | recommendations]
    end
  end

  defp add_adoption_recommendations(recommendations, analytics_result) do
    adoption_insights = get_in(analytics_result, [:adoption_analytics, :adoption_insights])

    ["Monitor adoption trends for system optimization insights" | recommendations]
  end

  defp add_context_recommendations(recommendations, context) do
    # Add context-specific recommendations
    final_recs = recommendations

    final_recs =
      if Map.get(context, :optimization_focus) do
        ["Focus optimization efforts based on context requirements" | final_recs]
      else
        final_recs
      end

    final_recs =
      if Map.get(context, :performance_critical, false) do
        ["Performance is critical - prioritize optimization recommendations" | final_recs]
      else
        final_recs
      end

    Enum.reverse(final_recs)
  end

  defp generate_system_health_recommendations(overall_health, health_factors) do
    case overall_health do
      :excellent ->
        ["Maintain current workflow adoption strategies"]

      :good ->
        ["System health is good - continue monitoring and gradual optimization"]

      :fair ->
        ["System health needs attention - focus on underperforming areas"]

      :poor ->
        ["System health is poor - review workflow implementation strategy"]

      _ ->
        ["Continue monitoring system health metrics"]
    end
  end

  defp analyze_adoption_insights(adoption_statistics) do
    # Analyze adoption insights for strategic recommendations
    %{
      adoption_maturity: assess_adoption_maturity(adoption_statistics),
      adoption_effectiveness: assess_adoption_effectiveness(adoption_statistics),
      growth_potential: assess_adoption_growth_potential(adoption_statistics)
    }
  end

  defp assess_adoption_maturity(adoption_statistics) do
    total_agents = adoption_statistics.total_agents_monitored
    adopting_agents = adoption_statistics.agents_using_workflows

    cond do
      total_agents > 10 and adopting_agents > 5 -> :mature
      total_agents > 5 and adopting_agents > 2 -> :developing
      total_agents > 0 and adopting_agents > 0 -> :early
      true -> :nascent
    end
  end

  defp assess_adoption_effectiveness(adoption_statistics) do
    avg_rate = adoption_statistics.average_adoption_rate

    cond do
      avg_rate > 0.7 -> :highly_effective
      avg_rate > 0.4 -> :moderately_effective
      avg_rate > 0.1 -> :somewhat_effective
      true -> :limited_effectiveness
    end
  end

  defp assess_adoption_growth_potential(adoption_statistics) do
    # Assess potential for adoption growth
    current_percentage = adoption_statistics.workflow_adoption_percentage

    cond do
      current_percentage < 0.2 -> :high_growth_potential
      current_percentage < 0.5 -> :moderate_growth_potential
      current_percentage < 0.8 -> :limited_growth_potential
      true -> :saturation_approaching
    end
  end
end
