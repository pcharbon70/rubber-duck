defmodule RubberDuck.Preferences.Llm.RoutingIntegration do
  @moduledoc """
  Integration layer between preference system and LLM orchestration.

  Provides hooks into LLM provider selection logic, implements preference-based
  routing, and manages provider migration while maintaining audit trails.
  """

  require Logger

  alias RubberDuck.Preferences.Llm.{CostOptimizer, FallbackManager, ModelSelector, ProviderConfig}

  @doc """
  Override default provider selection with preference-based logic.
  """
  @spec select_provider_with_preferences(
          user_id :: binary(),
          request_opts :: keyword(),
          project_id :: binary() | nil
        ) ::
          {:ok, %{provider: atom(), model: String.t(), config: map()}} | {:error, String.t()}
  def select_provider_with_preferences(user_id, request_opts \\ [], project_id \\ nil) do
    # Record selection attempt for analytics
    record_selection_attempt(user_id, request_opts, project_id)

    config = ProviderConfig.get_complete_config(user_id, project_id)

    case determine_selection_strategy(config, request_opts) do
      :cost_optimized ->
        Logger.debug("Using cost-optimized provider selection")
        CostOptimizer.optimize_selection(user_id, request_opts, project_id)

      :quality_first ->
        Logger.debug("Using quality-first provider selection")
        quality_first_selection(user_id, request_opts, project_id)

      :preference_based ->
        Logger.debug("Using preference-based provider selection")
        ModelSelector.select_model(user_id, request_opts, project_id)
    end
  end

  @doc """
  Route request to appropriate provider based on preferences and load balancing.
  """
  @spec route_request(user_id :: binary(), request :: map(), project_id :: binary() | nil) ::
          {:ok, %{provider: atom(), routing_info: map()}} | {:error, String.t()}
  def route_request(user_id, _request, project_id \\ nil) do
    config = ProviderConfig.get_complete_config(user_id, project_id)

    with {:ok, selection} <- select_provider_with_preferences(user_id, [], project_id),
         {:ok, routing_info} <- apply_load_balancing(selection.provider, config) do
      record_routing_decision(user_id, selection.provider, routing_info, project_id)

      {:ok,
       %{
         provider: selection.provider,
         model: selection.model,
         config: selection.config,
         routing_info: routing_info,
         fallback_chain: FallbackManager.get_fallback_chain(user_id, project_id)
       }}
    else
      error -> error
    end
  end

  @doc """
  Handle provider migration while preserving context.
  """
  @spec migrate_provider(
          user_id :: binary(),
          from_provider :: atom(),
          to_provider :: atom(),
          context :: map(),
          project_id :: binary() | nil
        ) ::
          {:ok, %{migration_info: map()}} | {:error, String.t()}
  def migrate_provider(user_id, from_provider, to_provider, context \\ %{}, project_id \\ nil) do
    Logger.info("Migrating from #{from_provider} to #{to_provider} for user #{user_id}")

    # Validate target provider is available
    enabled_providers = ProviderConfig.get_enabled_providers(user_id, project_id)

    if to_provider in enabled_providers do
      # Perform migration with context preservation
      {:ok, migrated_context} =
        preserve_context_across_providers(from_provider, to_provider, context)

      record_provider_migration(user_id, from_provider, to_provider, project_id)

      {:ok,
       %{
         migration_info: %{
           from_provider: from_provider,
           to_provider: to_provider,
           context_preserved: map_size(migrated_context) > 0,
           migrated_at: DateTime.utc_now(),
           migration_reason: "automatic_migration"
         },
         new_context: migrated_context
       }}
    else
      {:error, "Target provider #{to_provider} is not enabled"}
    end
  end

  @doc """
  Monitor provider effectiveness based on preferences.
  """
  @spec monitor_provider_effectiveness(
          user_id :: binary(),
          provider :: atom(),
          performance_data :: map(),
          project_id :: binary() | nil
        ) :: :ok
  def monitor_provider_effectiveness(user_id, provider, performance_data, project_id \\ nil) do
    config = ProviderConfig.get_complete_config(user_id, project_id)
    monitoring_config = config.monitoring_config

    if monitoring_config.performance_tracking do
      # Record performance metrics
      record_provider_performance(user_id, provider, performance_data, project_id)

      # Check if performance meets thresholds
      check_performance_thresholds(provider, performance_data, monitoring_config)

      # Update provider health status
      update_provider_health(user_id, provider, performance_data, project_id)
    end

    :ok
  end

  @doc """
  Enable A/B testing for provider selection.
  """
  @spec enable_ab_testing(user_id :: binary(), test_config :: map(), project_id :: binary() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def enable_ab_testing(user_id, test_config, project_id \\ nil) do
    # Implement A/B testing logic for provider selection
    test_groups = Map.get(test_config, :groups, [])
    duration = Map.get(test_config, :duration_hours, 24)

    if length(test_groups) >= 2 do
      # Assign user to test group
      test_group = assign_test_group(user_id, test_groups)

      # Record A/B test participation
      record_ab_test_participation(user_id, test_group, test_config, project_id)

      {:ok,
       %{
         test_group: test_group,
         provider_override: Map.get(test_group, :provider),
         test_duration: duration,
         test_id: Map.get(test_config, :test_id),
         started_at: DateTime.utc_now()
       }}
    else
      {:error, "A/B test requires at least 2 test groups"}
    end
  end

  # Private helper functions

  defp determine_selection_strategy(config, request_opts) do
    cost_enabled = config.cost_optimization.optimization_enabled
    quality_priority = Keyword.get(request_opts, :quality_priority, false)

    cond do
      quality_priority -> :quality_first
      cost_enabled -> :cost_optimized
      true -> :preference_based
    end
  end

  defp quality_first_selection(user_id, _request_opts, project_id) do
    config = ProviderConfig.get_complete_config(user_id, project_id)

    # Sort providers by quality, then by preference
    quality_sorted_providers =
      config.enabled_providers
      |> Enum.map(fn provider ->
        default_model = get_default_model_for_provider(provider, config)
        quality = estimate_quality_score(provider, default_model)
        {provider, default_model, quality}
      end)
      |> Enum.sort_by(fn {_provider, _model, quality} -> quality end, :desc)

    case quality_sorted_providers do
      [{provider, model, _quality} | _] ->
        provider_config = Map.get(config.provider_configs, provider, %{})

        {:ok,
         %{
           provider: provider,
           model: model,
           config: provider_config
         }}

      [] ->
        {:error, "No providers available"}
    end
  end

  defp apply_load_balancing(provider, config) do
    load_balancing_strategy = get_load_balancing_strategy(config)

    routing_info = %{
      strategy: load_balancing_strategy,
      provider: provider,
      assigned_at: DateTime.utc_now(),
      routing_id: generate_routing_id()
    }

    case load_balancing_strategy do
      "round_robin" -> apply_round_robin_routing(provider, routing_info)
      "least_connections" -> apply_least_connections_routing(provider, routing_info)
      "weighted" -> apply_weighted_routing(provider, routing_info)
      "random" -> apply_random_routing(provider, routing_info)
      _ -> {:ok, routing_info}
    end
  end

  defp get_load_balancing_strategy(config) do
    Map.get(config, :load_balancing, "round_robin")
  end

  defp apply_round_robin_routing(provider, routing_info) do
    # Simplified round-robin implementation
    instance_id = :erlang.phash2({provider, System.system_time()}, 10)
    {:ok, Map.put(routing_info, :instance_id, instance_id)}
  end

  defp apply_least_connections_routing(_provider, routing_info) do
    # Simplified least connections implementation
    # In production, this would check actual connection counts
    # Simulate least loaded instance
    instance_id = :rand.uniform(5)
    {:ok, Map.put(routing_info, :instance_id, instance_id)}
  end

  defp apply_weighted_routing(provider, routing_info) do
    # Simplified weighted routing
    weights = get_provider_weights()
    weight = Map.get(weights, provider, 1.0)
    {:ok, Map.put(routing_info, :weight, weight)}
  end

  defp apply_random_routing(_provider, routing_info) do
    instance_id = :rand.uniform(10)
    {:ok, Map.put(routing_info, :instance_id, instance_id)}
  end

  defp get_provider_weights do
    # Default weights - in production this would be preference-based
    %{
      anthropic: 1.0,
      openai: 0.8,
      google: 0.6,
      local: 1.2
    }
  end

  defp preserve_context_across_providers(from_provider, to_provider, context) do
    # Simplified context migration - in production this would handle
    # provider-specific context formats and conversions

    migrated_context =
      context
      |> Map.put(:migrated_from, from_provider)
      |> Map.put(:migrated_to, to_provider)
      |> Map.put(:migration_timestamp, DateTime.utc_now())

    {:ok, migrated_context}
  end

  defp get_default_model_for_provider(provider, config) do
    provider_config = Map.get(config.provider_configs, provider, %{})
    Map.get(provider_config, :model, ModelSelector.get_default_model(provider))
  end

  defp generate_routing_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp assign_test_group(user_id, test_groups) do
    # Simple hash-based assignment for consistent group assignment
    group_index = :erlang.phash2(user_id, length(test_groups))
    Enum.at(test_groups, group_index)
  end

  # Analytics and telemetry functions

  defp record_selection_attempt(user_id, request_opts, project_id) do
    :telemetry.execute(
      [:rubber_duck, :llm, :selection_attempt],
      %{count: 1},
      %{
        user_id: user_id,
        project_id: project_id,
        request_type: Keyword.get(request_opts, :type, :unknown),
        timestamp: DateTime.utc_now()
      }
    )
  end

  defp record_routing_decision(user_id, provider, routing_info, project_id) do
    :telemetry.execute(
      [:rubber_duck, :llm, :routing_decision],
      %{count: 1},
      %{
        user_id: user_id,
        provider: provider,
        routing_strategy: routing_info.strategy,
        project_id: project_id,
        timestamp: DateTime.utc_now()
      }
    )
  end

  defp record_provider_migration(user_id, from_provider, to_provider, project_id) do
    :telemetry.execute(
      [:rubber_duck, :llm, :provider_migration],
      %{count: 1},
      %{
        user_id: user_id,
        from_provider: from_provider,
        to_provider: to_provider,
        project_id: project_id,
        timestamp: DateTime.utc_now()
      }
    )
  end

  defp record_provider_performance(user_id, provider, performance_data, project_id) do
    :telemetry.execute(
      [:rubber_duck, :llm, :provider_performance],
      performance_data,
      %{
        user_id: user_id,
        provider: provider,
        project_id: project_id,
        timestamp: DateTime.utc_now()
      }
    )
  end

  defp check_performance_thresholds(provider, performance_data, monitoring_config) do
    thresholds = monitoring_config.alert_thresholds
    error_rate = Map.get(performance_data, :error_rate, 0.0)
    response_time = Map.get(performance_data, :avg_response_time, 0)

    # Check if thresholds are exceeded
    if error_rate > Map.get(thresholds, "error_rate", 0.1) do
      Logger.warning("Provider #{provider} error rate exceeded threshold: #{error_rate}")
    end

    if response_time > Map.get(thresholds, "response_time_ms", 10_000) do
      Logger.warning("Provider #{provider} response time exceeded threshold: #{response_time}ms")
    end
  end

  defp update_provider_health(user_id, provider, performance_data, project_id) do
    health_status = determine_health_status(performance_data)

    :telemetry.execute(
      [:rubber_duck, :llm, :provider_health_update],
      %{health_score: health_status.score},
      %{
        user_id: user_id,
        provider: provider,
        health_status: health_status.status,
        project_id: project_id,
        timestamp: DateTime.utc_now()
      }
    )
  end

  defp determine_health_status(performance_data) do
    error_rate = Map.get(performance_data, :error_rate, 0.0)
    response_time = Map.get(performance_data, :avg_response_time, 0)
    availability = Map.get(performance_data, :availability, 1.0)

    health_score = calculate_health_score(error_rate, response_time, availability)

    status =
      cond do
        health_score >= 0.9 -> :healthy
        health_score >= 0.7 -> :degraded
        true -> :unhealthy
      end

    %{score: health_score, status: status}
  end

  defp calculate_health_score(error_rate, response_time, availability) do
    # Simple health scoring algorithm
    # Max 50% penalty for errors
    error_penalty = min(error_rate * 10, 0.5)
    # Max 30% penalty for slow responses
    response_penalty = min(response_time / 20_000, 0.3)
    availability_score = availability

    max(0.0, availability_score - error_penalty - response_penalty)
  end

  defp record_ab_test_participation(user_id, test_group, test_config, project_id) do
    :telemetry.execute(
      [:rubber_duck, :llm, :ab_test_participation],
      %{count: 1},
      %{
        user_id: user_id,
        test_id: Map.get(test_config, :test_id),
        test_group: Map.get(test_group, :name),
        provider_override: Map.get(test_group, :provider),
        project_id: project_id,
        timestamp: DateTime.utc_now()
      }
    )
  end

  # Utility functions for quality estimation - moved from CostOptimizer to avoid circular dependency
  defp estimate_quality_score(provider, model) do
    get_anthropic_quality(provider, model) ||
      get_openai_quality(provider, model) ||
      get_google_quality(provider, model) ||
      0.70
  end

  defp get_anthropic_quality(:anthropic, "claude-3-5-sonnet-20241022"), do: 0.95
  defp get_anthropic_quality(:anthropic, "claude-3-opus-20240229"), do: 0.94
  defp get_anthropic_quality(:anthropic, "claude-3-5-haiku-20241022"), do: 0.85
  defp get_anthropic_quality(_, _), do: nil

  defp get_openai_quality(:openai, "gpt-4"), do: 0.92
  defp get_openai_quality(:openai, "gpt-4-turbo"), do: 0.90
  defp get_openai_quality(:openai, "gpt-4o"), do: 0.93
  defp get_openai_quality(:openai, "gpt-3.5-turbo"), do: 0.80
  defp get_openai_quality(_, _), do: nil

  defp get_google_quality(:google, "gemini-1.5-pro"), do: 0.88
  defp get_google_quality(:google, "gemini-1.5-flash"), do: 0.82
  defp get_google_quality(_, _), do: nil
end
