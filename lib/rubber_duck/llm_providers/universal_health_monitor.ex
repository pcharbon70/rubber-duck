defmodule RubberDuck.LlmProviders.UniversalHealthMonitor do
  @moduledoc """
  Universal health monitoring system for AI providers across all domains.

  This module consolidates health monitoring from both the Verdict system and
  the Preferences LLM system into a unified monitor that tracks:
  - Domain-specific health metrics (evaluation, orchestration, planning, etc.)
  - Provider performance across multiple use cases
  - Cross-domain provider usage patterns and optimization
  - Automatic failover and recovery coordination
  - Integration with existing three-tier preference system

  Features merged from existing systems:
  - Verdict system: Sophisticated health monitoring, Constitutional AI tracking
  - Preferences system: Cost optimization monitoring, agent performance tracking
  """

  use GenServer
  require Logger

  alias RubberDuck.LlmProviders.UniversalProviderRegistry
  alias RubberDuck.LlmProviders.UniversalProviderInterface

  # Improved: 15 seconds (vs 30s in original systems)
  @health_check_interval 15_000
  # 1 hour performance tracking
  @performance_window_minutes 60
  # 5 minutes for cross-domain analysis
  @cross_domain_analysis_interval 300_000

  @alert_thresholds %{
    success_rate_critical: 0.90,
    success_rate_warning: 0.95,
    # 10 seconds
    response_time_critical: 10_000,
    # 5 seconds
    response_time_warning: 5_000,
    # Cost efficiency threshold
    cost_efficiency_warning: 0.6,
    # Performance variance across domains
    cross_domain_variance_warning: 0.3
  }

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get comprehensive health status for all providers across all domains.
  """
  def get_universal_health_status do
    GenServer.call(__MODULE__, :get_universal_health_status)
  end

  @doc """
  Get detailed health metrics for specific provider across all domains.
  """
  def get_provider_health(provider_type) do
    GenServer.call(__MODULE__, {:get_provider_health, provider_type})
  end

  @doc """
  Get domain-specific health metrics for provider.
  """
  def get_domain_health(provider_type, domain) do
    GenServer.call(__MODULE__, {:get_domain_health, provider_type, domain})
  end

  @doc """
  Record universal provider usage for comprehensive health tracking.
  """
  def record_universal_usage(provider_type, domain, usage_result) do
    GenServer.cast(__MODULE__, {:record_universal_usage, provider_type, domain, usage_result})
  end

  @doc """
  Get cross-domain provider performance analytics.
  """
  def get_cross_domain_analytics(provider_type) do
    GenServer.call(__MODULE__, {:get_cross_domain_analytics, provider_type})
  end

  @doc """
  Configure health thresholds for universal monitoring.
  """
  def configure_universal_thresholds(thresholds) do
    GenServer.cast(__MODULE__, {:configure_thresholds, thresholds})
  end

  @doc """
  Trigger immediate health check for provider across all domains.
  """
  def trigger_comprehensive_health_check(provider_type) do
    GenServer.cast(__MODULE__, {:trigger_health_check, provider_type})
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    # Subscribe to provider registry events
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "provider_registry_events")
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "provider_health_changes")
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "preference_changes")

    # Start monitoring cycles
    schedule_universal_health_monitoring()
    schedule_cross_domain_analysis()

    state = %{
      domain_health_data: %{},
      cross_domain_performance: %{},
      performance_history: %{},
      alert_thresholds: @alert_thresholds,
      monitoring_enabled: Keyword.get(opts, :enabled, true),
      stats: %{
        health_checks_performed: 0,
        cross_domain_analyses: 0,
        alerts_sent: 0,
        recovery_events: 0,
        monitoring_start_time: DateTime.utc_now()
      }
    }

    Logger.info("Universal Health Monitor started with interval: #{@health_check_interval}ms")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_universal_health_status, _from, state) do
    # Compile universal health status across all providers and domains
    universal_status =
      state.domain_health_data
      |> Enum.map(fn {provider_type, domain_health} ->
        cross_domain_metrics = Map.get(state.cross_domain_performance, provider_type, %{})
        performance_data = Map.get(state.performance_history, provider_type, %{})

        {provider_type,
         %{
           domain_health: domain_health,
           cross_domain_performance: cross_domain_metrics,
           performance_summary: summarize_performance_across_domains(performance_data),
           overall_health: UniversalProviderInterface.aggregate_domain_health(domain_health),
           last_updated: DateTime.utc_now()
         }}
      end)
      |> Enum.into(%{})

    {:reply, {:ok, universal_status}, state}
  end

  @impl true
  def handle_call({:get_provider_health, provider_type}, _from, state) do
    domain_health = Map.get(state.domain_health_data, provider_type, %{})
    cross_domain_performance = Map.get(state.cross_domain_performance, provider_type, %{})
    performance_history = Map.get(state.performance_history, provider_type, %{})

    comprehensive_health = %{
      domain_specific_health: domain_health,
      cross_domain_performance: cross_domain_performance,
      performance_history: get_recent_performance_history(performance_history),
      health_trends: calculate_health_trends(performance_history),
      recommendations: generate_health_recommendations(domain_health, cross_domain_performance),
      overall_health: UniversalProviderInterface.aggregate_domain_health(domain_health)
    }

    {:reply, {:ok, comprehensive_health}, state}
  end

  @impl true
  def handle_call({:get_domain_health, provider_type, domain}, _from, state) do
    domain_health = get_in(state.domain_health_data, [provider_type, domain])
    domain_performance = get_in(state.performance_history, [provider_type, domain], [])

    case domain_health do
      nil ->
        {:reply, {:error, :not_monitored}, state}

      health_data ->
        detailed_health =
          Map.merge(health_data, %{
            performance_metrics: calculate_domain_performance_metrics(domain_performance),
            recent_usage: Enum.take(domain_performance, 10),
            health_trend: calculate_domain_trend(domain_performance),
            domain_specific_recommendations:
              generate_domain_recommendations(domain, health_data, domain_performance)
          })

        {:reply, {:ok, detailed_health}, state}
    end
  end

  @impl true
  def handle_call({:get_cross_domain_analytics, provider_type}, _from, state) do
    cross_domain_data = Map.get(state.cross_domain_performance, provider_type, %{})
    domain_health = Map.get(state.domain_health_data, provider_type, %{})

    analytics = %{
      cross_domain_metrics: cross_domain_data,
      domain_comparison: compare_domain_performance(state.performance_history, provider_type),
      consistency_analysis: analyze_cross_domain_consistency(domain_health),
      optimization_opportunities: identify_optimization_opportunities(cross_domain_data),
      unified_recommendations: generate_cross_domain_recommendations(cross_domain_data)
    }

    {:reply, {:ok, analytics}, state}
  end

  @impl true
  def handle_cast({:record_universal_usage, provider_type, domain, usage_result}, state) do
    timestamp = DateTime.utc_now()

    # Create comprehensive usage entry
    usage_entry = %{
      timestamp: timestamp,
      domain: domain,
      success: Map.get(usage_result, :success, false),
      response_time_ms: Map.get(usage_result, :response_time_ms, 0),
      cost_usd: Map.get(usage_result, :cost_usd, 0.0),
      tokens_used: Map.get(usage_result, :tokens_used, 0),
      model_used: Map.get(usage_result, :model, "unknown"),
      use_case: Map.get(usage_result, :use_case, :general),
      specialized_features_used: Map.get(usage_result, :specialized_features, [])
    }

    # Update performance history
    updated_history =
      state.performance_history
      |> Map.update(provider_type, %{}, fn provider_history ->
        Map.update(provider_history, domain, [usage_entry], fn domain_history ->
          # Keep recent entries within window and limit memory usage
          cutoff_time = DateTime.add(timestamp, -@performance_window_minutes, :minute)

          recent_entries =
            Enum.filter(domain_history, &(DateTime.compare(&1.timestamp, cutoff_time) != :lt))

          [usage_entry | recent_entries] |> Enum.take(1000)
        end)
      end)

    # Update domain health data
    updated_domain_health =
      update_domain_health_from_usage(
        state.domain_health_data,
        provider_type,
        domain,
        usage_entry
      )

    # Update cross-domain performance analysis
    updated_cross_domain =
      update_cross_domain_performance(state.cross_domain_performance, provider_type, usage_entry)

    new_state = %{
      state
      | performance_history: updated_history,
        domain_health_data: updated_domain_health,
        cross_domain_performance: updated_cross_domain
    }

    # Check for health alerts
    check_and_send_universal_health_alerts(
      provider_type,
      domain,
      usage_entry,
      state.alert_thresholds
    )

    # Record usage in registry for analytics
    UniversalProviderRegistry.record_provider_usage(provider_type, domain, usage_result)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:configure_thresholds, thresholds}, state) do
    Logger.info("Updating universal health monitoring thresholds")
    updated_thresholds = Map.merge(state.alert_thresholds, thresholds)
    {:noreply, %{state | alert_thresholds: updated_thresholds}}
  end

  @impl true
  def handle_cast({:trigger_health_check, provider_type}, state) do
    Logger.info("Triggering comprehensive health check for #{provider_type}")

    # Trigger immediate health check through registry
    UniversalProviderRegistry.check_provider_health(provider_type)

    {:noreply, state}
  end

  @impl true
  def handle_info(:universal_health_monitoring, state) do
    if state.monitoring_enabled do
      Logger.debug("Starting universal health monitoring cycle")

      # Get all providers and perform health analysis
      case UniversalProviderRegistry.get_providers() do
        {:ok, providers} ->
          updated_state = perform_universal_health_analysis(providers, state)
          schedule_universal_health_monitoring()

          updated_stats = Map.update!(updated_state.stats, :health_checks_performed, &(&1 + 1))
          {:noreply, %{updated_state | stats: updated_stats}}

        {:error, reason} ->
          Logger.error(
            "Failed to get providers for universal health monitoring: #{inspect(reason)}"
          )

          schedule_universal_health_monitoring()
          {:noreply, state}
      end
    else
      schedule_health_monitoring()
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:cross_domain_analysis, state) do
    Logger.debug("Performing cross-domain performance analysis")

    updated_state = perform_cross_domain_analysis(state)
    schedule_cross_domain_analysis()

    updated_stats = Map.update!(updated_state.stats, :cross_domain_analyses, &(&1 + 1))
    {:noreply, %{updated_state | stats: updated_stats}}
  end

  @impl true
  def handle_info({:provider_registry_changed, event_data}, state) do
    Logger.debug("Provider registry changed for universal monitoring: #{inspect(event_data)}")

    case event_data do
      {:provider_registered, provider_type, supported_domains} ->
        # Initialize monitoring for new provider
        updated_state = initialize_provider_monitoring(state, provider_type, supported_domains)
        {:noreply, updated_state}

      {:provider_unregistered, provider_type} ->
        # Clean up monitoring data
        updated_state = cleanup_provider_monitoring(state, provider_type)
        {:noreply, updated_state}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # Private implementation

  defp perform_universal_health_analysis(providers, state) do
    Enum.reduce(providers, state, fn {provider_type, provider_info}, acc_state ->
      # Analyze health across all supported domains
      domain_health_results =
        provider_info.supported_domains
        |> Enum.map(fn domain ->
          domain_performance = get_in(acc_state.performance_history, [provider_type, domain], [])
          domain_health = analyze_domain_health(domain_performance, domain)
          {domain, domain_health}
        end)
        |> Enum.into(%{})

      # Update domain health data
      updated_domain_health =
        Map.put(acc_state.domain_health_data, provider_type, domain_health_results)

      %{acc_state | domain_health_data: updated_domain_health}
    end)
  end

  defp analyze_domain_health(domain_performance, domain) do
    if Enum.empty?(domain_performance) do
      %{
        status: :unknown,
        success_rate: 0.0,
        avg_response_time_ms: 0,
        total_requests: 0,
        domain_specific_metrics: get_default_domain_metrics(domain)
      }
    else
      success_count = Enum.count(domain_performance, & &1.success)
      total_requests = length(domain_performance)
      success_rate = success_count / total_requests

      avg_response_time =
        Enum.reduce(domain_performance, 0, &(&1.response_time_ms + &2)) / total_requests

      avg_cost = Enum.reduce(domain_performance, 0.0, &(&1.cost_usd + &2)) / total_requests

      status = determine_domain_health_status(success_rate, avg_response_time, domain)

      %{
        status: status,
        success_rate: success_rate,
        avg_response_time_ms: trunc(avg_response_time),
        avg_cost_per_request: avg_cost,
        total_requests: total_requests,
        error_count: total_requests - success_count,
        last_check: DateTime.utc_now(),
        domain_specific_metrics: calculate_domain_specific_metrics(domain_performance, domain),
        performance_trend: calculate_domain_performance_trend(domain_performance)
      }
    end
  end

  defp determine_domain_health_status(success_rate, avg_response_time, domain) do
    # Domain-specific health thresholds
    domain_thresholds =
      case domain do
        # Evaluation needs high accuracy
        :evaluation -> %{success_threshold: 0.95, response_threshold: 8000}
        # Orchestration needs speed
        :orchestration -> %{success_threshold: 0.90, response_threshold: 5000}
        # Planning can be slower
        :planning -> %{success_threshold: 0.85, response_threshold: 15000}
        _ -> %{success_threshold: 0.90, response_threshold: 10000}
      end

    cond do
      success_rate >= domain_thresholds.success_threshold and
          avg_response_time <= domain_thresholds.response_threshold ->
        :healthy

      success_rate >= 0.80 and avg_response_time <= domain_thresholds.response_threshold * 1.5 ->
        :degraded

      true ->
        :unhealthy
    end
  end

  defp get_default_domain_metrics(domain) do
    case domain do
      :evaluation ->
        %{constitutional_ai_usage: 0.0, evaluation_types_handled: [], avg_confidence: 0.0}

      :orchestration ->
        %{agent_communications: 0, cost_efficiency: 0.0, orchestration_complexity: 0.0}

      :planning ->
        %{planning_tasks: 0, reasoning_depth: 0.0, plan_success_rate: 0.0}

      _ ->
        %{}
    end
  end

  defp calculate_domain_specific_metrics(domain_performance, domain) do
    case domain do
      :evaluation ->
        constitutional_ai_usage =
          Enum.count(domain_performance, fn entry ->
            :constitutional_ai in Map.get(entry, :specialized_features_used, [])
          end) / length(domain_performance)

        evaluation_types =
          domain_performance
          |> Enum.map(&Map.get(&1, :use_case, :unknown))
          |> Enum.uniq()

        %{
          constitutional_ai_usage: constitutional_ai_usage,
          evaluation_types_handled: evaluation_types,
          avg_confidence: calculate_avg_metric(domain_performance, :confidence, 0.8)
        }

      :orchestration ->
        cost_efficiency = calculate_avg_metric(domain_performance, :cost_efficiency, 0.7)
        agent_communications = length(domain_performance)

        %{
          agent_communications: agent_communications,
          cost_efficiency: cost_efficiency,
          orchestration_complexity: calculate_avg_metric(domain_performance, :complexity, 0.5)
        }

      :planning ->
        planning_tasks = length(domain_performance)
        reasoning_depth = calculate_avg_metric(domain_performance, :reasoning_depth, 0.7)

        %{
          planning_tasks: planning_tasks,
          reasoning_depth: reasoning_depth,
          plan_success_rate:
            Enum.count(domain_performance, & &1.success) / length(domain_performance)
        }

      _ ->
        %{
          total_requests: length(domain_performance),
          success_rate: Enum.count(domain_performance, & &1.success) / length(domain_performance)
        }
    end
  end

  defp calculate_avg_metric(performance_data, metric_key, default_value) do
    if Enum.empty?(performance_data) do
      default_value
    else
      values = Enum.map(performance_data, &Map.get(&1, metric_key, default_value))
      Enum.sum(values) / length(values)
    end
  end

  defp calculate_domain_performance_trend(domain_performance) do
    if length(domain_performance) < 5 do
      :insufficient_data
    else
      recent_performance = Enum.take(domain_performance, 5)
      older_performance = Enum.slice(domain_performance, 5, 5)

      recent_success = Enum.count(recent_performance, & &1.success) / length(recent_performance)

      older_success =
        if Enum.empty?(older_performance) do
          recent_success
        else
          Enum.count(older_performance, & &1.success) / length(older_performance)
        end

      cond do
        recent_success > older_success + 0.1 -> :improving
        recent_success < older_success - 0.1 -> :degrading
        true -> :stable
      end
    end
  end

  defp update_domain_health_from_usage(domain_health_data, provider_type, domain, usage_entry) do
    current_domain_health =
      get_in(domain_health_data, [provider_type, domain], %{
        status: :unknown,
        consecutive_successes: 0,
        consecutive_failures: 0
      })

    updated_domain_health =
      if usage_entry.success do
        %{
          current_domain_health
          | status: :healthy,
            consecutive_successes: Map.get(current_domain_health, :consecutive_successes, 0) + 1,
            consecutive_failures: 0,
            last_success: DateTime.utc_now()
        }
      else
        failure_count = Map.get(current_domain_health, :consecutive_failures, 0) + 1

        %{
          current_domain_health
          | status: determine_status_from_failures(failure_count),
            consecutive_failures: failure_count,
            consecutive_successes: 0,
            last_failure: DateTime.utc_now()
        }
      end

    put_in(domain_health_data, [provider_type, domain], updated_domain_health)
  end

  defp determine_status_from_failures(failure_count) do
    cond do
      failure_count >= 5 -> :unhealthy
      failure_count >= 2 -> :degraded
      true -> :healthy
    end
  end

  defp update_cross_domain_performance(cross_domain_performance, provider_type, usage_entry) do
    current_cross_domain =
      Map.get(cross_domain_performance, provider_type, %{
        domains_used: MapSet.new(),
        total_cross_domain_requests: 0,
        domain_switching_frequency: 0.0,
        cost_efficiency_variance: 0.0
      })

    updated_domains = MapSet.put(current_cross_domain.domains_used, usage_entry.domain)

    %{
      current_cross_domain
      | domains_used: updated_domains,
        total_cross_domain_requests: current_cross_domain.total_cross_domain_requests + 1,
        last_domain_used: usage_entry.domain,
        last_usage_timestamp: usage_entry.timestamp
    }
    |> then(&Map.put(cross_domain_performance, provider_type, &1))
  end

  defp perform_cross_domain_analysis(state) do
    Logger.debug("Analyzing cross-domain provider performance")

    updated_cross_domain =
      state.providers
      |> Enum.reduce(state.cross_domain_performance, fn {provider_type, provider_info}, acc ->
        cross_domain_metrics =
          analyze_provider_cross_domain_performance(
            state.performance_history,
            provider_type,
            provider_info.supported_domains
          )

        Map.put(acc, provider_type, cross_domain_metrics)
      end)

    %{state | cross_domain_performance: updated_cross_domain}
  end

  defp analyze_provider_cross_domain_performance(
         performance_history,
         provider_type,
         supported_domains
       ) do
    provider_performance = Map.get(performance_history, provider_type, %{})

    domain_metrics =
      supported_domains
      |> Enum.map(fn domain ->
        domain_data = Map.get(provider_performance, domain, [])

        metrics =
          if Enum.empty?(domain_data) do
            %{requests: 0, avg_response_time: 0, success_rate: 0.0, avg_cost: 0.0}
          else
            %{
              requests: length(domain_data),
              avg_response_time:
                Enum.reduce(domain_data, 0, &(&1.response_time_ms + &2)) / length(domain_data),
              success_rate: Enum.count(domain_data, & &1.success) / length(domain_data),
              avg_cost: Enum.reduce(domain_data, 0.0, &(&1.cost_usd + &2)) / length(domain_data)
            }
          end

        {domain, metrics}
      end)
      |> Enum.into(%{})

    %{
      domain_metrics: domain_metrics,
      cross_domain_variance: calculate_cross_domain_variance(domain_metrics),
      domain_switching_analysis: analyze_domain_switching_patterns(provider_performance),
      optimization_recommendations:
        generate_cross_domain_optimization_recommendations(domain_metrics)
    }
  end

  defp calculate_cross_domain_variance(domain_metrics) do
    if map_size(domain_metrics) < 2 do
      0.0
    else
      response_times = domain_metrics |> Map.values() |> Enum.map(& &1.avg_response_time)
      success_rates = domain_metrics |> Map.values() |> Enum.map(& &1.success_rate)

      %{
        response_time_variance: calculate_variance(response_times),
        success_rate_variance: calculate_variance(success_rates),
        overall_consistency: calculate_overall_consistency(response_times, success_rates)
      }
    end
  end

  defp calculate_variance(values) when length(values) > 1 do
    mean = Enum.sum(values) / length(values)

    sum_squared_diffs =
      Enum.reduce(values, 0, fn value, acc ->
        acc + :math.pow(value - mean, 2)
      end)

    sum_squared_diffs / length(values)
  end

  defp calculate_variance(_), do: 0.0

  defp calculate_overall_consistency(response_times, success_rates) do
    # Normalize
    response_consistency = 1.0 - min(1.0, calculate_variance(response_times) / 10000)
    success_consistency = 1.0 - calculate_variance(success_rates)

    (response_consistency + success_consistency) / 2
  end

  defp analyze_domain_switching_patterns(provider_performance) do
    # Analyze how frequently domains are switched for same provider
    all_usage =
      provider_performance
      |> Map.values()
      |> List.flatten()
      |> Enum.sort_by(& &1.timestamp)

    if length(all_usage) < 2 do
      %{switching_frequency: 0.0, patterns: []}
    else
      switches =
        all_usage
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.count(fn [prev, curr] -> prev.domain != curr.domain end)

      %{
        switching_frequency: switches / (length(all_usage) - 1),
        total_requests: length(all_usage),
        domain_switches: switches
      }
    end
  end

  defp check_and_send_universal_health_alerts(provider_type, domain, usage_entry, thresholds) do
    alerts = []

    # Check for domain-specific alerts
    alerts =
      if not usage_entry.success do
        ["Universal provider #{provider_type} failed in #{domain} domain"] ++ alerts
      else
        alerts
      end

    alerts =
      if usage_entry.response_time_ms > thresholds.response_time_critical do
        [
          "Provider #{provider_type} response time critical in #{domain}: #{usage_entry.response_time_ms}ms"
        ] ++ alerts
      else
        alerts
      end

    # Check cost efficiency for orchestration domain
    alerts =
      if domain == :orchestration and usage_entry.cost_usd > 0 do
        cost_efficiency = calculate_usage_cost_efficiency(usage_entry)

        if cost_efficiency < thresholds.cost_efficiency_warning do
          [
            "Provider #{provider_type} cost efficiency low in orchestration: #{Float.round(cost_efficiency, 2)}"
          ] ++ alerts
        else
          alerts
        end
      else
        alerts
      end

    # Send alerts if any were triggered
    unless Enum.empty?(alerts) do
      send_universal_health_alerts(provider_type, domain, alerts)
    end
  end

  defp calculate_usage_cost_efficiency(usage_entry) do
    # Simple cost efficiency calculation
    if usage_entry.cost_usd > 0 and usage_entry.tokens_used > 0 do
      # Tokens per dollar per 1K tokens
      usage_entry.tokens_used / usage_entry.cost_usd / 1000
    else
      1.0
    end
  end

  defp send_universal_health_alerts(provider_type, domain, alerts) do
    # Broadcast universal alerts
    Phoenix.PubSub.broadcast(
      RubberDuck.PubSub,
      "universal_provider_alerts",
      {:universal_provider_alerts, provider_type, domain, alerts, DateTime.utc_now()}
    )

    Logger.warning(
      "Universal health alerts for #{provider_type}/#{domain}: #{Enum.join(alerts, "; ")}"
    )
  end

  defp initialize_provider_monitoring(state, provider_type, supported_domains) do
    # Initialize monitoring data structures for new provider
    domain_health_init =
      supported_domains
      |> Enum.map(fn domain -> {domain, %{status: :unknown, last_check: nil}} end)
      |> Enum.into(%{})

    usage_stats_init =
      supported_domains
      |> Enum.map(fn domain -> {domain, []} end)
      |> Enum.into(%{})

    updated_domain_health = Map.put(state.domain_health_data, provider_type, domain_health_init)

    updated_performance_history =
      Map.put(state.performance_history, provider_type, usage_stats_init)

    %{
      state
      | domain_health_data: updated_domain_health,
        performance_history: updated_performance_history
    }
  end

  defp cleanup_provider_monitoring(state, provider_type) do
    updated_domain_health = Map.delete(state.domain_health_data, provider_type)
    updated_performance_history = Map.delete(state.performance_history, provider_type)
    updated_cross_domain = Map.delete(state.cross_domain_performance, provider_type)

    %{
      state
      | domain_health_data: updated_domain_health,
        performance_history: updated_performance_history,
        cross_domain_performance: updated_cross_domain
    }
  end

  defp summarize_performance_across_domains(performance_data) when is_map(performance_data) do
    total_requests = performance_data |> Map.values() |> List.flatten() |> length()

    if total_requests == 0 do
      %{total_requests: 0, overall_success_rate: 0.0, domain_count: map_size(performance_data)}
    else
      all_usage = performance_data |> Map.values() |> List.flatten()
      successful_requests = Enum.count(all_usage, & &1.success)

      %{
        total_requests: total_requests,
        overall_success_rate: successful_requests / total_requests,
        domain_count: map_size(performance_data),
        avg_cost_per_request: Enum.reduce(all_usage, 0.0, &(&1.cost_usd + &2)) / total_requests,
        avg_response_time: Enum.reduce(all_usage, 0, &(&1.response_time_ms + &2)) / total_requests
      }
    end
  end

  defp summarize_performance_across_domains(_),
    do: %{total_requests: 0, overall_success_rate: 0.0}

  defp get_recent_performance_history(performance_history) when is_map(performance_history) do
    performance_history
    |> Enum.map(fn {domain, usage_list} ->
      recent_usage = Enum.take(usage_list, 5)
      {domain, recent_usage}
    end)
    |> Enum.into(%{})
  end

  defp get_recent_performance_history(_), do: %{}

  defp calculate_health_trends(performance_history) when is_map(performance_history) do
    performance_history
    |> Enum.map(fn {domain, usage_list} ->
      trend = calculate_domain_performance_trend(usage_list)
      {domain, trend}
    end)
    |> Enum.into(%{})
  end

  defp calculate_health_trends(_), do: %{}

  defp generate_health_recommendations(domain_health, cross_domain_performance) do
    recommendations = []

    # Check for domain-specific issues
    recommendations =
      domain_health
      |> Enum.reduce(recommendations, fn {domain, health}, acc ->
        case health.status do
          :unhealthy ->
            ["Consider alternative provider for #{domain} domain due to health issues"] ++ acc

          :degraded ->
            ["Monitor #{domain} domain performance - showing degradation"] ++ acc

          _ ->
            acc
        end
      end)

    # Check cross-domain performance issues
    variance = Map.get(cross_domain_performance, :cross_domain_variance, %{})
    overall_consistency = Map.get(variance, :overall_consistency, 1.0)

    recommendations =
      if overall_consistency < 0.7 do
        ["High performance variance across domains - consider provider configuration review"] ++
          recommendations
      else
        recommendations
      end

    case recommendations do
      [] -> ["Provider performing well across all domains"]
      recs -> recs
    end
  end

  defp generate_domain_recommendations(domain, health_data, performance_data) do
    recommendations = []

    # Domain-specific recommendations
    recommendations =
      case {domain, health_data.status} do
        {:evaluation, :degraded} ->
          ["Consider enabling Constitutional AI features for improved evaluation quality"] ++
            recommendations

        {:orchestration, :degraded} ->
          ["Consider cost optimization review for orchestration use case"] ++ recommendations

        {:planning, :unhealthy} ->
          [
            "Planning domain showing issues - consider using alternative provider for complex reasoning"
          ] ++ recommendations

        _ ->
          recommendations
      end

    # Performance-based recommendations
    if length(performance_data) > 5 do
      avg_response_time = calculate_avg_metric(performance_data, :response_time_ms, 0)

      recommendations =
        if avg_response_time > 8000 do
          ["Response times elevated for #{domain} - consider model optimization"] ++
            recommendations
        else
          recommendations
        end
    end

    case recommendations do
      [] -> ["#{domain} domain performance within normal parameters"]
      recs -> recs
    end
  end

  defp compare_domain_performance(performance_history, provider_type) do
    provider_performance = Map.get(performance_history, provider_type, %{})

    if map_size(provider_performance) < 2 do
      %{comparison_available: false, reason: "Insufficient domains for comparison"}
    else
      domain_stats =
        provider_performance
        |> Enum.map(fn {domain, usage_list} ->
          if Enum.empty?(usage_list) do
            {domain, %{avg_response_time: 0, success_rate: 0.0, avg_cost: 0.0}}
          else
            {domain,
             %{
               avg_response_time: calculate_avg_metric(usage_list, :response_time_ms, 0),
               success_rate: Enum.count(usage_list, & &1.success) / length(usage_list),
               avg_cost: calculate_avg_metric(usage_list, :cost_usd, 0.0)
             }}
          end
        end)
        |> Enum.into(%{})

      %{
        comparison_available: true,
        domain_stats: domain_stats,
        best_performing_domain: find_best_performing_domain(domain_stats),
        optimization_opportunities: identify_domain_optimization_opportunities(domain_stats)
      }
    end
  end

  defp find_best_performing_domain(domain_stats) do
    domain_stats
    |> Enum.max_by(fn {_domain, stats} ->
      # Composite score: high success rate, low response time, low cost
      stats.success_rate * 0.5 +
        1.0 / max(stats.avg_response_time, 1) * 0.3 +
        1.0 / max(stats.avg_cost, 0.001) * 0.2
    end)
    |> elem(0)
  end

  defp identify_domain_optimization_opportunities(domain_stats) do
    opportunities = []

    # Find domains with high costs
    high_cost_domains =
      domain_stats
      |> Enum.filter(fn {_domain, stats} -> stats.avg_cost > 0.5 end)
      |> Enum.map(fn {domain, _stats} -> domain end)

    opportunities =
      if not Enum.empty?(high_cost_domains) do
        ["High cost domains (#{Enum.join(high_cost_domains, ", ")}) - consider cost optimization"] ++
          opportunities
      else
        opportunities
      end

    # Find domains with slow response times
    slow_domains =
      domain_stats
      |> Enum.filter(fn {_domain, stats} -> stats.avg_response_time > 8000 end)
      |> Enum.map(fn {domain, _stats} -> domain end)

    opportunities =
      if not Enum.empty?(slow_domains) do
        [
          "Slow response domains (#{Enum.join(slow_domains, ", ")}) - consider performance optimization"
        ] ++ opportunities
      else
        opportunities
      end

    case opportunities do
      [] -> ["No optimization opportunities identified"]
      opps -> opps
    end
  end

  defp analyze_cross_domain_consistency(domain_health) do
    if map_size(domain_health) < 2 do
      %{consistency: :insufficient_data}
    else
      statuses = domain_health |> Map.values() |> Enum.map(&Map.get(&1, :status, :unknown))
      unique_statuses = Enum.uniq(statuses)

      consistency =
        case length(unique_statuses) do
          # All domains same status
          1 -> :perfect
          # Minor variations
          2 -> :good
          # High variability
          _ -> :poor
        end

      %{
        consistency: consistency,
        status_distribution: Enum.frequencies(statuses),
        recommendation: get_consistency_recommendation(consistency, unique_statuses)
      }
    end
  end

  defp get_consistency_recommendation(consistency, statuses) do
    case {consistency, statuses} do
      {:perfect, [:healthy]} -> "Excellent consistency - provider stable across all domains"
      {:perfect, [:degraded]} -> "Consistent degradation - investigate provider-wide issues"
      {:good, _} -> "Minor variations between domains - acceptable performance"
      {:poor, _} -> "High variability across domains - review domain-specific configurations"
    end
  end

  defp identify_optimization_opportunities(cross_domain_data) do
    opportunities = []

    variance = Map.get(cross_domain_data, :cross_domain_variance, %{})
    consistency = Map.get(variance, :overall_consistency, 1.0)

    opportunities =
      if consistency < 0.7 do
        ["High cross-domain performance variance - consider unified configuration optimization"] ++
          opportunities
      else
        opportunities
      end

    domain_metrics = Map.get(cross_domain_data, :domain_metrics, %{})

    # Find underperforming domains
    underperforming =
      domain_metrics
      |> Enum.filter(fn {_domain, metrics} ->
        Map.get(metrics, :success_rate, 1.0) < 0.9 or
          Map.get(metrics, :avg_response_time, 0) > 8000
      end)
      |> Enum.map(fn {domain, _} -> domain end)

    opportunities =
      if not Enum.empty?(underperforming) do
        ["Underperforming domains: #{Enum.join(underperforming, ", ")} - needs attention"] ++
          opportunities
      else
        opportunities
      end

    case opportunities do
      [] -> ["No cross-domain optimization opportunities identified"]
      opps -> opps
    end
  end

  defp generate_cross_domain_optimization_recommendations(domain_metrics) do
    recommendations = []

    # Compare domain performance and suggest optimizations
    best_domain = find_best_performing_domain(domain_metrics)
    best_stats = domain_metrics[best_domain]

    recommendations =
      domain_metrics
      |> Enum.reduce(recommendations, fn {domain, stats}, acc ->
        if domain != best_domain do
          suggestions = []

          suggestions =
            if stats.avg_response_time > best_stats.avg_response_time * 1.5 do
              ["Consider response time optimization for #{domain}"] ++ suggestions
            else
              suggestions
            end

          suggestions =
            if stats.avg_cost > best_stats.avg_cost * 1.3 do
              ["Consider cost optimization for #{domain}"] ++ suggestions
            else
              suggestions
            end

          acc ++ suggestions
        else
          acc
        end
      end)

    case recommendations do
      [] -> ["All domains performing similarly - no specific optimizations needed"]
      recs -> recs
    end
  end

  defp schedule_universal_health_monitoring do
    Process.send_after(self(), :universal_health_monitoring, @health_check_interval)
  end

  defp schedule_cross_domain_analysis do
    Process.send_after(self(), :cross_domain_analysis, @cross_domain_analysis_interval)
  end
end
